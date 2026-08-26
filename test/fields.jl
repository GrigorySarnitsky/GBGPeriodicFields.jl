# Tests for src/Fields.jl: field construction, FFT round-trips, spectral
# multipliers (cross-checked against AbstractFFTs), Nyquist handling,
# storage-wise broadcasting, and domain-compatibility checks.

using Test
using GBGPeriodicFields
using AbstractFFTs: rfftfreq, fftfreq

# Internal (non-exported) helpers and the Fields-defined FieldSpectralMultipliers
# are reached through the submodule. Note: the umbrella currently re-exports
# FieldSpectralMultipliers from DifferentialOperators (a mid-refactor leftover),
# so we qualify F.FieldSpectralMultipliers to test the Fields implementation.
const F = GBGPeriodicFields.Fields

const T = Float64
const grid = Grid3D((8, 7, 6), (2π, 2π, 2π))     # mixed parity: even, odd, even
const layout = RealFourierLayout()

@testset "Fields.jl" begin

  @testset "construction + shapes" begin
    sp = ScalarFieldPhysical((x, y, z) -> sin(x) * cos(y) + 0.3, grid)
    vp = VectorFieldPhysical((x, y, z) -> (sin(x), cos(y), sin(z)), grid)
    tp = TensorFieldPhysical{2}((x, y, z) -> [sin(x) cos(y) 0.0; 0.0 sin(z) cos(x); 1.0 0.0 sin(y)], grid)
    @test size(field_data(sp)) == (8, 7, 6)
    @test size(field_data(vp)) == (8, 7, 6, 3)
    @test size(field_data(tp)) == (8, 7, 6, 3, 3)
    @test field_tensor_order(sp) == 0
    @test field_tensor_order(vp) == 1
    @test field_tensor_order(tp) == 2
    @test field_scalar_type(sp) == Float64
    @test eltype(field_data(sp)) == Float64
  end

  @testset "Grid3D enforces its own uniformity" begin
    # The four-argument constructor takes a spacing the caller supplies, and a value that
    # contradicts domain_size ./ grid_size would mislocate every interpolated point silently
    # (the transfer kernels read grid_spacing directly), so it is rejected rather than stored.
    sizes, lengths, o = (8, 7, 6), (2π, 4π, 6π), (0.0, 0.0, 0.0)
    consistent = lengths ./ Float64.(sizes)
    @test Grid3D(sizes, lengths, consistent, o).grid_spacing == consistent
    @test Grid3D(sizes, lengths).grid_spacing == consistent          # the two-argument form agrees
    @test_throws ArgumentError Grid3D(sizes, lengths, (1.0, 1.0, 1.0), o)
    @test_throws ArgumentError Grid3D(sizes, lengths, (consistent[1], 2 * consistent[2], consistent[3]), o)
    @test_throws ArgumentError Grid3D((0, 7, 6), lengths, consistent, o)
    # a spacing reached by an equivalent but different arithmetic route must still be accepted
    @test Grid3D(sizes, lengths, ntuple(a -> lengths[a] / sizes[a], 3), o) isa Grid3D
    # and the tolerance is relative, so it holds at Float32 as well
    @test Grid3D(sizes, Float32.(lengths), Float32.(lengths) ./ Float32.(sizes),
                 Float32.(o)) isa Grid3D{Float32}
  end

  @testset "FFT round-trip (scalar/vector/tensor)" begin
    for (field, R) in (
        (ScalarFieldPhysical((x, y, z) -> sin(x) * cos(y) + 0.3, grid), 0),
        (VectorFieldPhysical((x, y, z) -> (sin(x), cos(y), sin(2z)), grid), 1),
        (TensorFieldPhysical{2}((x, y, z) -> [sin(x) cos(y) 0.0; 0.0 sin(z) cos(x); 1.0 0.0 sin(y)], grid), 2),
      )
      spec_shape = F.spectral_field_shape(grid, layout, Val(R))
      spectral = R == 0 ? ScalarFieldSpectral(zeros(Complex{T}, spec_shape), grid) :
                 R == 1 ? VectorFieldSpectral(zeros(Complex{T}, spec_shape), grid) :
                          TensorFieldSpectral{R}(zeros(Complex{T}, spec_shape), grid)
      plans = FieldTransformPlans(field, spectral)
      back = to_physical(to_spectral(field, plans), plans)
      @test field_data(back) ≈ field_data(field)
    end
  end

  @testset "allocating transforms preserve their input" begin
    a = ScalarFieldPhysical((x, y, z) -> sin(x) * cos(y) + 0.3, grid)
    spectral_zero = ScalarFieldSpectral(zeros(Complex{T}, F.spectral_field_shape(grid, layout, Val(0))), grid)
    plans = FieldTransformPlans(a, spectral_zero)

    physical_before = copy(field_data(a))
    spectral = to_spectral(a, plans)
    @test field_data(a) == physical_before          # forward leaves the physical input intact

    spectral_before = copy(field_data(spectral))
    back = to_physical(spectral, plans)
    @test field_data(spectral) == spectral_before    # inverse leaves the spectral input intact (would fail on FFTW without the copy)
    @test field_data(back) ≈ field_data(a)           # and the round-trip is still correct
  end

  @testset "scratch arity of to_physical!: preserving AND allocation-free (decision 64)" begin
    a = ScalarFieldPhysical((x, y, z) -> sin(x) * cos(y) + 0.3, grid)
    spectral_zero = ScalarFieldSpectral(zeros(Complex{T}, F.spectral_field_shape(grid, layout, Val(0))), grid)
    plans = FieldTransformPlans(a, spectral_zero)
    spectral = to_spectral(a, plans)
    scratch = similar_field(spectral, Val(0))
    out = similar_field(a, Val(0))

    spectral_before = copy(field_data(spectral))
    to_physical!(out, spectral, plans, scratch)
    # The whole contract, each half separately: the source survives BITWISE (the claim the 3-arg form
    # cannot make on FFTW), and the answer equals the allocating preserving form bitwise (that form's
    # own oracle is the independent DFT sum, so this chain terminates independently).
    @test field_data(spectral) == spectral_before
    @test field_data(out) == field_data(to_physical(spectral, plans))

    # Aliasing is refused, not defined: shared storage would consume the very source the arity
    # preserves. Same-array is the only sharing decision 59 leaves constructible, so this is the case.
    @test_throws ArgumentError to_physical!(out, spectral, plans, spectral)
    # And the scratch is a field like any other: a context mismatch is refused the same way.
    other_grid = Grid3D((4, 4, 4), (2pi, 2pi, 2pi))
    mismatched = ScalarFieldSpectral(zeros(Complex{T}, F.spectral_field_shape(other_grid, layout, Val(0))), other_grid)
    @test_throws ArgumentError to_physical!(out, spectral, plans, mismatched)

    # Vector twin through the same method (the arity is order-generic).
    u = VectorFieldPhysical(rand(T, size(field_data(a))..., 3), grid)
    vplans = FieldTransformPlans(u, similar_field(spectral_zero, Val(1)))
    uh = to_spectral(u, vplans)
    uh_before = copy(field_data(uh))
    uscr = similar_field(uh, Val(1))
    uout = similar_field(u, Val(1))
    to_physical!(uout, uh, vplans, uscr)
    @test field_data(uh) == uh_before
    @test field_data(uout) == field_data(to_physical(uh, vplans))
  end

  @testset "spectral multipliers vs AbstractFFTs" begin
    sp = ScalarFieldPhysical((x, y, z) -> sin(x), grid)
    spectral = to_spectral(sp, FieldTransformPlans(sp, ScalarFieldSpectral(zeros(Complex{T}, F.spectral_field_shape(grid, layout, Val(0))), grid)))
    m = F.FieldSpectralMultipliers(spectral)

    N = grid.grid_size
    L = grid.domain_size

    # dim 1 is the rfft half axis; dims 2,3 are full complex axes.
    k1_full = (2π / L[1]) .* collect(rfftfreq(N[1], N[1]))   # integer freqs via fs = N
    k2_full = (2π / L[2]) .* collect(fftfreq(N[2], N[2]))
    k3_full = (2π / L[3]) .* collect(fftfreq(N[3], N[3]))

    # squared wavenumbers keep the true k^2 everywhere (no Nyquist zeroing)
    @test Array(m.squared_wavenumber_1) ≈ k1_full .^ 2
    @test Array(m.squared_wavenumber_2) ≈ k2_full .^ 2
    @test Array(m.squared_wavenumber_3) ≈ k3_full .^ 2

    # derivative wavenumbers zero the Nyquist mode on even axes (1, 3), not on odd (2)
    k1_deriv = copy(k1_full); k1_deriv[N[1] ÷ 2 + 1] = 0.0   # even -> zero last (Nyquist)
    k3_deriv = copy(k3_full); k3_deriv[N[3] ÷ 2 + 1] = 0.0   # even -> zero -N/2 entry
    @test Array(m.wavenumber_1) ≈ k1_deriv
    @test Array(m.wavenumber_2) ≈ k2_full          # odd axis: unchanged
    @test Array(m.wavenumber_3) ≈ k3_deriv
  end

  @testset "broadcasting" begin
    a = ScalarFieldPhysical((x, y, z) -> sin(x), grid)
    b = ScalarFieldPhysical((x, y, z) -> cos(y), grid)
    c = ScalarFieldPhysical((x, y, z) -> 1.0, grid)

    # in-place fused assignment writes into destination storage
    dest = F.similar_field(a, Val(0))
    @. dest = a - b + c
    @test field_data(dest) ≈ field_data(a) .- field_data(b) .+ field_data(c)

    # out-of-place returns a new field of the right concrete type
    out = a .+ b
    @test out isa ScalarFieldPhysical
    @test field_data(out) ≈ field_data(a) .+ field_data(b)

    # scalar (Real) broadcast against a field
    out2 = @. a + 2.0
    @test field_data(out2) ≈ field_data(a) .+ 2.0

    # mixing physical and spectral representations is rejected
    spectral = to_spectral(a, FieldTransformPlans(a, ScalarFieldSpectral(zeros(Complex{T}, F.spectral_field_shape(grid, layout, Val(0))), grid)))
    @test_throws Exception (a .+ spectral)
  end

  @testset "compatibility accept/reject" begin
    a = ScalarFieldPhysical((x, y, z) -> sin(x), grid)
    v = VectorFieldPhysical((x, y, z) -> (sin(x), cos(y), sin(z)), grid)
    other_grid = Grid3D((8, 7, 6), (2π, 2π, 4π))   # different domain size
    a_other = ScalarFieldPhysical((x, y, z) -> sin(x), other_grid)

    @test F.check_field_compatibility(a, a) === nothing
    @test_throws ArgumentError F.check_field_compatibility(a, a_other)        # grid mismatch
    @test_throws ArgumentError F.check_field_compatibility(a, v)              # order mismatch

    # domain-compatibility allows differing tensor order (gradient/divergence path)
    @test F._check_field_domain_compatibility(a, v) === nothing
    @test_throws ArgumentError F._check_field_domain_compatibility(a, a_other)
  end

end


@testset "transform plans carry no tensor order (decision 76) ($TP)" for TP in (Float64, Float32)
  layout = RealFourierLayout()
  # Every parity class, including the all-odd grids whose component offsets are the awkward ones.
  @testset "round trip at every rank, grid $(dims)" for dims in ((8, 8, 8), (8, 7, 6), (7, 5, 3), (9, 9, 9))
    grid = Grid3D(dims, (TP(2π), TP(2π), TP(2π)))
    for (physical_type, spectral_type) in ((ScalarFieldPhysical, ScalarFieldSpectral),
                                           (VectorFieldPhysical, VectorFieldSpectral),
                                           (TensorFieldPhysical, TensorFieldSpectral))
      physical = physical_type(Array, grid, layout)
      spectral = spectral_type(Array, grid, layout)
      copyto!(field_data(physical), rand(TP, size(field_data(physical))))
      original = copy(field_data(physical))
      plans = FieldTransformPlans(physical, spectral)
      to_spectral!(spectral, physical, plans)
      to_physical!(physical, spectral, plans)
      @test isapprox(field_data(physical), original; rtol = TP === Float32 ? 1.0f-4 : 1e-12)
    end
  end

  # The property the decision rests on: a plan pair is a property of the BASE, so one built from a
  # scalar field transforms a vector and a tensor field. Under the old per-rank plans this call was
  # not merely slower — it did not exist, because the plan's tensor order was part of its type.
  grid = Grid3D((8, 7, 6), (TP(2π), TP(2π), TP(2π)))
  scalar_plans = FieldTransformPlans(ScalarFieldPhysical(Array, grid, layout),
                                     ScalarFieldSpectral(Array, grid, layout))
  for (physical_type, spectral_type) in ((VectorFieldPhysical, VectorFieldSpectral),
                                         (TensorFieldPhysical, TensorFieldSpectral))
    physical = physical_type(Array, grid, layout)
    spectral = spectral_type(Array, grid, layout)
    copyto!(field_data(physical), rand(TP, size(field_data(physical))))
    original = copy(field_data(physical))
    to_spectral!(spectral, physical, scalar_plans)
    to_physical!(physical, spectral, scalar_plans)
    @test isapprox(field_data(physical), original; rtol = TP === Float32 ? 1.0f-4 : 1e-12)
  end

  # A host grid never needs the staging buffer: misalignment is answered by the planner flag.
  @test FieldTransformPlans(ScalarFieldPhysical(Array, Grid3D((7, 5, 3), (TP(2π), TP(2π), TP(2π))), layout),
                            ScalarFieldSpectral(Array, Grid3D((7, 5, 3), (TP(2π), TP(2π), TP(2π))), layout)
                            ).component_scratch === nothing

  # The alignment predicate is a fact about the base, not a guess: all-odd grids are exactly the ones
  # a device backend refuses, and every all-even grid is accepted by both.
  for dims in ((7, 5, 3), (9, 9, 9))
    @test !last(GBGPeriodicFields.Fields._component_offsets_align(
      Grid3D(dims, (TP(2π), TP(2π), TP(2π))), layout, TP))
  end
  for dims in ((8, 8, 8), (8, 12, 16), (64, 64, 64))
    @test all(GBGPeriodicFields.Fields._component_offsets_align(
      Grid3D(dims, (TP(2π), TP(2π), TP(2π))), layout, TP))
  end
end


@testset "permuted rfft layout: transforms and both multiplier families ($TP)" for TP in (Float64, Float32)
  grid_p = Grid3D((8, 7, 6), (TP(2π), TP(4π), TP(6π)))        # mixed parity + anisotropic lengths
  for dims in ((2, 1, 3), (3, 2, 1))                          # odd fold (N=7), then even fold (N=6)
    layout_p = RealFourierLayout(dims)
    field = VectorFieldPhysical(rand(TP, 8, 7, 6, 3), grid_p, layout_p)
    scaffold = VectorFieldSpectral(zeros(Complex{TP}, spectral_field_shape(grid_p, layout_p, Val(1))),
                                   grid_p, layout_p)
    plans = FieldTransformPlans(field, scaffold)
    back = to_physical(to_spectral(field, plans), plans)
    @test field_data(back) ≈ field_data(field)

    # The multiplier arrays index spatial axes; only the layout's first transform axis is
    # rfft-folded. Both families vs rfftfreq/fftfreq on every axis (invariant 5: the derivative
    # family zeroes an even axis's Nyquist, the squared family keeps the true k² there).
    m = FieldSpectralMultipliers(to_spectral(field, plans))
    wavenumbers = (Array(m.wavenumber_1), Array(m.wavenumber_2), Array(m.wavenumber_3))
    squares = (Array(m.squared_wavenumber_1), Array(m.squared_wavenumber_2),
               Array(m.squared_wavenumber_3))
    for axis in 1:3
      n = grid_p.grid_size[axis]
      scale = TP(2π) / grid_p.domain_size[axis]
      full = scale .* collect(TP, axis == dims[1] ? rfftfreq(n, n) : fftfreq(n, n))
      derivative = copy(full)
      iseven(n) && (derivative[n ÷ 2 + 1] = 0)
      @test vec(wavenumbers[axis]) ≈ derivative
      @test vec(squares[axis]) ≈ full .^ 2
    end
  end
end


@testset "origin-aware sampling, explicit multipliers, guard errors ($TP)" for TP in (Float64, Float32)
  # the function-sampling constructors evaluate at origin + (i-1)Δ — no test ever set a
  # non-zero origin on this path (the HDF5 origin case supplies a raw array, bypassing it)
  origin = (TP(0.4), TP(-0.7), TP(1.1))
  grid_o = Grid3D((8, 6, 4), (TP(2π), TP(4π), TP(6π)); origin = origin)
  s = ScalarFieldPhysical((x, y, z) -> x, grid_o)
  @test field_data(s)[3, 1, 1] ≈ origin[1] + 2 * grid_o.grid_spacing[1]
  u = VectorFieldPhysical((x, y, z) -> (y, z, x), grid_o)
  @test field_data(u)[1, 2, 1, 1] ≈ origin[2] + grid_o.grid_spacing[2]
  @test field_data(u)[1, 1, 2, 2] ≈ origin[3] + grid_o.grid_spacing[3]
  A = TensorFieldPhysical{2}((x, y, z) -> fill(z, 3, 3), grid_o)
  @test field_data(A)[1, 1, 3, 2, 2] ≈ origin[3] + 2 * grid_o.grid_spacing[3]

  # the explicit multiplier constructors (documented public API, never previously called):
  # feeding the convenience constructor's own arrays back must reproduce it field for field
  grid_m = Grid3D((8, 6, 4), (TP(2π), TP(2π), TP(2π)))
  layout_m = RealFourierLayout((2, 1, 3))
  ref = ScalarFieldSpectral(zeros(Complex{TP}, spectral_field_shape(grid_m, layout_m, Val(0))),
                            grid_m, layout_m)
  mc = FieldSpectralMultipliers(ref)
  for built in (
      FieldSpectralMultipliers(grid_m, layout_m,
        mc.wavenumber_1, mc.wavenumber_2, mc.wavenumber_3,
        mc.squared_wavenumber_1, mc.squared_wavenumber_2, mc.squared_wavenumber_3),
      FieldSpectralMultipliers(ref,
        mc.wavenumber_1, mc.wavenumber_2, mc.wavenumber_3,
        mc.squared_wavenumber_1, mc.squared_wavenumber_2, mc.squared_wavenumber_3),
    )
    @test built.wavenumber_1 == mc.wavenumber_1 && built.wavenumber_2 == mc.wavenumber_2 &&
          built.wavenumber_3 == mc.wavenumber_3
    @test built.squared_wavenumber_1 == mc.squared_wavenumber_1 &&
          built.squared_wavenumber_2 == mc.squared_wavenumber_2 &&
          built.squared_wavenumber_3 == mc.squared_wavenumber_3
    @test built.fourier_layout.fft_dims == (2, 1, 3)
  end

  # one representative per previously-untested guard class
  @test_throws DimensionMismatch FieldSpectralMultipliers(grid_m, layout_m,
    mc.wavenumber_1[1:2], mc.wavenumber_2, mc.wavenumber_3,
    mc.squared_wavenumber_1, mc.squared_wavenumber_2, mc.squared_wavenumber_3)
  @test_throws ArgumentError RealFourierLayout((1, 1, 3))          # not a permutation
  @test_throws DimensionMismatch ScalarFieldPhysical(zeros(TP, 8, 6, 5), grid_m)
  mismatched = ScalarFieldSpectral(
    zeros(Complex{TP}, spectral_field_shape(grid_m, RealFourierLayout(), Val(0))), grid_m)
  physical_m = ScalarFieldPhysical(zeros(TP, 8, 6, 4), grid_m, layout_m)
  @test_throws ArgumentError FieldTransformPlans(physical_m, mismatched)
end


# The real-field layout's conjugate-symmetry contract, made checkable (decision 71). The oracle is
# ELEMENTWISE and written from the definition — it shares no code with the implementation, which walks
# whole planes with `reverse`/`circshift` so it never indexes a device array one element at a time.
@testset "reality_residual: the constraint the half-spectrum cannot enforce ($T)" for T in (Float64, Float32)
  function reality_oracle(field)
    d = field_data(field); fold = field_layout(field).fft_dims[1]
    N = field_grid(field).grid_size; others = Tuple(a for a in 1:3 if a != fold)
    planes = iseven(N[fold]) ? (1, size(d, fold)) : (1,)
    r = zero(T)
    for p in planes, idx in CartesianIndices(d)
      idx[fold] == p || continue
      t = collect(Tuple(idx))
      for a in others; t[a] = mod(-(idx[a] - 1), N[a]) + 1 end
      r = max(r, abs(d[idx] - conj(d[CartesianIndex(t...)])))
    end
    return r
  end

  # Grids chosen so the folded axis is even (two self-conjugate planes) and odd (only the zero plane),
  # crossed with permuted folds, because the folded axis is `fft_dims[1]` and not necessarily the first.
  for (sizes, layout) in (((8, 8, 8), RealFourierLayout()),
                          ((8, 8, 8), RealFourierLayout((2, 1, 3))),
                          ((8, 7, 6), RealFourierLayout()),
                          ((7, 8, 8), RealFourierLayout()))          # ODD folded axis: no Nyquist plane
    grid = Grid3D(sizes, T.((2pi, 2pi, 2pi)))
    for R in (0, 1, 2)
      physical = R == 0 ? ScalarFieldPhysical(rand(T, sizes...), grid, layout) :
                 R == 1 ? VectorFieldPhysical(rand(T, sizes..., 3), grid, layout) :
                          TensorFieldPhysical{2}(rand(T, sizes..., 3, 3), grid, layout)
      spectral = similar_field(ScalarFieldSpectral(
        zeros(Complex{T}, spectral_field_shape(grid, layout, Val(0))...), grid, layout), Val(R))
      plans = FieldTransformPlans(physical, spectral)
      transformed = to_spectral(physical, plans)

      # A spectrum that came from a real field satisfies it exactly — that is the whole reason the
      # package's own outputs never need checking.
      @test reality_residual(transformed) == 0
      @test reality_residual(transformed) == reality_oracle(transformed)

      # Break ONE of a conjugate pair: the residual is exactly the magnitude of what was injected.
      data = field_data(transformed)
      δ = Complex{T}(0.6, 0.25)
      plane_index = ntuple(a -> a == layout.fft_dims[1] ? 1 : 3, 3)
      data[plane_index..., ntuple(_ -> 1, R)...] += δ
      @test reality_residual(transformed) ≈ abs(δ)
      @test reality_residual(transformed) ≈ reality_oracle(transformed)

      # Fixing the partner restores it, so the test is about PAIRS, not about touching storage.
      partner = ntuple(a -> a == layout.fft_dims[1] ? 1 : mod(-(3 - 1), sizes[a]) + 1, 3)
      data[partner..., ntuple(_ -> 1, R)...] += conj(δ)
      @test reality_residual(transformed) ≈ 0 atol = 8 * eps(T)

      # A self-paired mode must be REAL, and the residual is twice its imaginary part.
      data[ntuple(_ -> 1, 3)..., ntuple(_ -> 1, R)...] += Complex{T}(0, 0.3)
      @test reality_residual(transformed) ≈ 2 * T(0.3) atol = 8 * eps(T)

      # The documented repair: a physical round trip IS the projection onto a real field's spectrum.
      @test reality_residual(to_spectral(to_physical(transformed, plans), plans)) ≈ 0 atol = 8 * eps(T)
    end
  end

  # Physical representation has no such constraint, so it has no method (invariant 1).
  grid = Grid3D((8, 8, 8), T.((2pi, 2pi, 2pi)))
  @test_throws MethodError reality_residual(ScalarFieldPhysical(rand(T, 8, 8, 8), grid))
end


@testset "allocating constructors (family, grid[, layout]) — decision 74" begin
  for T in (Float64, Float32)
    grid = Grid3D((8, 6, 4), (T(2π), T(4π), T(6π)))          # anisotropic, mixed parity
    for layout in (RealFourierLayout(), RealFourierLayout((3, 1, 2)))   # incl. a permuted fold
      # Every allocated field must be indistinguishable in TYPE and SHAPE from its data-built twin,
      # and must carry the grid and layout it was given (the decision-48 metadata trap: metadata
      # must survive any operation that allocates its result).
      cases = (
        (ScalarFieldPhysical(Array, grid, layout),
         ScalarFieldPhysical(zeros(T, physical_field_shape(grid, Val(0))), grid, layout)),
        (VectorFieldPhysical(Array, grid, layout),
         VectorFieldPhysical(zeros(T, physical_field_shape(grid, Val(1))), grid, layout)),
        (TensorFieldPhysical(Array, grid, layout),
         TensorFieldPhysical(zeros(T, physical_field_shape(grid, Val(2))), grid, layout)),
        (TensorFieldPhysical{3}(Array, grid, layout),
         TensorFieldPhysical{3}(zeros(T, physical_field_shape(grid, Val(3))), grid, layout)),
        (ScalarFieldSpectral(Array, grid, layout),
         ScalarFieldSpectral(zeros(Complex{T}, spectral_field_shape(grid, layout, Val(0))), grid, layout)),
        (VectorFieldSpectral(Array, grid, layout),
         VectorFieldSpectral(zeros(Complex{T}, spectral_field_shape(grid, layout, Val(1))), grid, layout)),
        (TensorFieldSpectral(Array, grid, layout),
         TensorFieldSpectral(zeros(Complex{T}, spectral_field_shape(grid, layout, Val(2))), grid, layout)),
        (TensorFieldSpectral{4}(Array, grid, layout),
         TensorFieldSpectral{4}(zeros(Complex{T}, spectral_field_shape(grid, layout, Val(4))), grid, layout)),
      )
      for (allocated, twin) in cases
        @test typeof(allocated) === typeof(twin)
        @test size(field_data(allocated)) == size(field_data(twin))
        @test field_grid(allocated) === grid
        @test field_layout(allocated) === layout
      end
      # ...and from similar_field of the twin — the reference-based and reference-free routes agree.
      @test typeof(ScalarFieldSpectral(Array, grid, layout)) ===
            typeof(similar_field(cases[5][2], Val(0)))
    end

    # The default layout is the default RealFourierLayout, as in the data constructors.
    @test field_layout(ScalarFieldPhysical(Array, grid)) == RealFourierLayout()

    # A parameterized family must AGREE with the grid's element type; complex is always refused
    # (spectral storage is allocated as Complex{T} internally — invariant 2's storage-detail rule).
    @test VectorFieldPhysical(Array{T}, grid) isa VectorFieldPhysical
    Tother = T === Float64 ? Float32 : Float64
    @test_throws ArgumentError ScalarFieldPhysical(Array{Tother}, grid)
    @test_throws ArgumentError ScalarFieldSpectral(Array{Complex{T}}, grid)

    # The storage is real storage a field can use: write it, transform it, round-trip it.
    u = VectorFieldPhysical(Array, grid)
    field_data(u) .= T(1)
    uh = ScalarFieldSpectral(Array, grid)          # spectral scratch, allocated the same way
    plans = FieldTransformPlans(ScalarFieldPhysical(Array, grid), uh)
    s = ScalarFieldPhysical(Array, grid)
    field_data(s) .= rand(T, size(field_data(s)))
    back = to_physical(to_spectral(s, plans), plans)
    @test field_data(back) ≈ field_data(s) rtol = (T === Float64 ? 1e-12 : 1e-5)
  end
end
