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
