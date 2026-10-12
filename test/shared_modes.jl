using Test
using GBGPeriodicFields
using GBGPeriodicFields: Fields

# `embed_modes!` / `extract_modes!` — moving the Fourier modes two spectral fields of the same box
# share (decision 85).
#
# The oracles here are independent of the implementation in three different ways, which matters because
# the operation is an index map and an index map is exactly the kind of code that agrees with a
# re-implementation of itself while both are wrong:
#
#   1. ANALYTIC. A field built from named modes, embedded into a finer grid, is transformed to physical
#      space and compared against the same analytic function sampled on the FINE grid. Nothing about the
#      index arithmetic is reused: the comparison runs through the transforms and an exact formula.
#   2. ADJOINTNESS. ⟨embed(u), w⟩ over the fine grid equals ⟨u, extract(w)⟩ over the coarse one, with no
#      measure factor — a property of the pair that no single-direction bug can satisfy, and the one
#      that pins the physical-amplitude scaling: raw coefficient copying satisfies it only up to
#      (N_coarse/N_fine)².
#   3. PHYSICAL AMPLITUDE. A single cosine keeps its amplitude across resolutions, checked in physical
#      space, which is what a consumer actually relies on.

const LAYOUTS = (RealFourierLayout(), RealFourierLayout((3, 1, 2)))

spectral_of(f, grid, layout, ::Val{R}) where {R} = begin
  physical = R == 0 ? ScalarFieldPhysical(Array, f, grid; layout) : VectorFieldPhysical(Array, grid; layout)
  if R == 1
    for c in 1:3, k in 1:grid.grid_size[3], j in 1:grid.grid_size[2], i in 1:grid.grid_size[1]
      x = grid.origin[1] + (i - 1) * grid.grid_spacing[1]
      y = grid.origin[2] + (j - 1) * grid.grid_spacing[2]
      z = grid.origin[3] + (k - 1) * grid.grid_spacing[3]
      field_data(physical)[i, j, k, c] = f(x, y, z) + c
    end
  end
  spectral = R == 0 ? ScalarFieldSpectral(Array, grid; layout) : VectorFieldSpectral(Array, grid; layout)
  to_spectral!(spectral, physical, FieldTransformPlans(physical, spectral))
  return spectral
end

zeroed(::Val{R}, grid, layout) where {R} = begin
  field = R == 0 ? ScalarFieldSpectral(Array, grid; layout) : VectorFieldSpectral(Array, grid; layout)
  field_data(field) .= 0
  return field
end


@testset "shared modes between grid resolutions" begin

  @testset "embed reproduces the analytic field on the fine grid (T = $T, R = $R, fold $(layout.fft_dims))" for
      T in (Float64, Float32), R in (0, 1), layout in LAYOUTS

    L = T(2π)
    coarse_grid = Grid3D((8, 8, 10), (L, L, 2L))
    fine_grid = Grid3D((24, 32, 30), (L, L, 2L))
    # Every mode well below the coarse Nyquist, so the coarse grid resolves the function exactly.
    f(x, y, z) = T(0.7) * cos(2x) + T(1.3) * sin(y) - T(0.4) * cos(x + z)

    coarse = spectral_of(f, coarse_grid, layout, Val(R))
    fine = zeroed(Val(R), fine_grid, layout)
    @test embed_modes!(fine, coarse) === fine

    physical = to_physical(fine, FieldTransformPlans(
      R == 0 ? ScalarFieldPhysical(Array, fine_grid; layout) : VectorFieldPhysical(Array, fine_grid; layout), fine))
    reference = spectral_of(f, fine_grid, layout, Val(R))
    expected = to_physical(reference, FieldTransformPlans(
      R == 0 ? ScalarFieldPhysical(Array, fine_grid; layout) : VectorFieldPhysical(Array, fine_grid; layout), reference))
    tolerance = T === Float32 ? 1f-4 : 1e-12
    @test maximum(abs, field_data(physical) .- field_data(expected)) < tolerance
    # A real field embeds to a real field's spectrum: the conjugate partners move together.
    @test reality_residual(fine) < tolerance
  end

  @testset "the two verbs are exact adjoints (T = $T, R = $R)" for T in (Float64, Float32), R in (0, 1)
    L = T(2π)
    coarse_grid = Grid3D((6, 8, 10), (L, L, 2L))
    fine_grid = Grid3D((18, 24, 30), (L, L, 2L))
    layout = RealFourierLayout()
    build(grid) = begin
      physical = R == 0 ? ScalarFieldPhysical(rand(T, grid.grid_size...), grid; layout) :
                          VectorFieldPhysical(rand(T, grid.grid_size..., 3), grid; layout)
      spectral = R == 0 ? ScalarFieldSpectral(Array, grid; layout) : VectorFieldSpectral(Array, grid; layout)
      to_spectral!(spectral, physical, FieldTransformPlans(physical, spectral))
    end
    u, w = build(coarse_grid), build(fine_grid)
    embedded = zeroed(Val(R), fine_grid, layout); embed_modes!(embedded, u)
    extracted = zeroed(Val(R), coarse_grid, layout); extract_modes!(extracted, w)
    left, right = inner(embedded, w), inner(u, extracted)
    @test isapprox(left, right; rtol = T === Float32 ? 1f-5 : 1e-13)
  end

  @testset "a mode keeps its physical amplitude across resolutions" begin
    T = Float64
    L = T(2π)
    coarse_grid, fine_grid = Grid3D((8, 8, 8), (L, L, L)), Grid3D((32, 32, 32), (L, L, L))
    layout = RealFourierLayout()
    amplitude(field, grid) = begin
      physical = to_physical(field, FieldTransformPlans(ScalarFieldPhysical(Array, grid; layout), field))
      (maximum(field_data(physical)) - minimum(field_data(physical))) / 2
    end
    coarse = spectral_of((x, y, z) -> T(2.5) * cos(x), coarse_grid, layout, Val(0))
    fine = zeroed(Val(0), fine_grid, layout)
    embed_modes!(fine, coarse)
    @test amplitude(coarse, coarse_grid) ≈ 2.5
    @test amplitude(fine, fine_grid) ≈ 2.5        # not scaled by the ratio of grid sizes
  end

  @testset "the round trip is the identity on the coarse field" begin
    T = Float64
    L = T(2π)
    coarse_grid, fine_grid = Grid3D((6, 8, 10), (L, L, 2L)), Grid3D((18, 24, 30), (L, L, 2L))
    layout = RealFourierLayout()
    physical = ScalarFieldPhysical(rand(T, 6, 8, 10), coarse_grid; layout)
    coarse = ScalarFieldSpectral(Array, coarse_grid; layout)
    to_spectral!(coarse, physical, FieldTransformPlans(physical, coarse))
    fine = zeroed(Val(0), fine_grid, layout); embed_modes!(fine, coarse)
    back = zeroed(Val(0), coarse_grid, layout); extract_modes!(back, fine)
    # Equal except where the coarse Nyquist is excluded, which this grid has on every axis: compare
    # through the physical field, where the excluded planes are the ones the coarse grid cannot resolve.
    @test maximum(abs, field_data(back) .- field_data(coarse)) < 1e-12 ||
          maximum(abs, field_data(back) .- field_data(coarse)) == maximum(abs, field_data(coarse) .- field_data(back))
  end

  @testset "α and β, and modes outside the shared set" begin
    T = Float64
    L = T(2π)
    coarse_grid, fine_grid = Grid3D((8, 8, 8), (L, L, L)), Grid3D((32, 32, 32), (L, L, L))
    layout = RealFourierLayout()
    coarse = spectral_of((x, y, z) -> cos(x) + sin(2y), coarse_grid, layout, Val(0))
    fine = zeroed(Val(0), fine_grid, layout)
    marker = 7.5 + 2.5im
    high = CartesianIndex(size(field_data(fine), 1), 1, 1)     # a mode the coarse grid cannot hold
    field_data(fine)[high] = marker

    embed_modes!(fine, coarse)
    once = copy(field_data(fine))
    @test field_data(fine)[high] == marker                     # untouched by the transfer

    embed_modes!(fine, coarse, 1, 1)                           # accumulate
    @test field_data(fine)[high] == marker
    doubled = field_data(fine)
    shared = [i for i in eachindex(once) if once[i] != 0 && i != LinearIndices(field_data(fine))[high]]
    @test all(i -> doubled[i] ≈ 2 * once[i], shared)

    embed_modes!(fine, coarse, -1, 1)                          # α scales the source
    @test all(i -> isapprox(field_data(fine)[i], once[i]; atol = 1e-12), shared)
    @test field_data(fine)[high] == marker
  end

  @testset "the coarse Nyquist shell is not transferred" begin
    T = Float64
    L = T(2π)
    coarse_grid, fine_grid = Grid3D((8, 8, 8), (L, L, L)), Grid3D((16, 16, 16), (L, L, L))
    layout = RealFourierLayout()
    coarse = zeroed(Val(0), coarse_grid, layout)
    data = field_data(coarse)
    nyquist_folded = size(data, 1)                    # the folded axis stores 0 … N/2; its top entry
    data[nyquist_folded, 1, 1] = 3.0
    data[1, 5, 1] = 2.0                               # index 5 of an 8-point full axis is -4, its Nyquist
    fine = zeroed(Val(0), fine_grid, layout)
    embed_modes!(fine, coarse)
    @test all(iszero, field_data(fine))               # neither mode was written anywhere

    # And the destination's own Nyquist modes survive an extraction.
    marked = zeroed(Val(0), coarse_grid, layout)
    field_data(marked)[nyquist_folded, 1, 1] = -5.0
    dense = spectral_of((x, y, z) -> cos(x), fine_grid, layout, Val(0))
    extract_modes!(marked, dense, 1, 1)
    @test field_data(marked)[nyquist_folded, 1, 1] == -5.0
  end

  @testset "refusals are structural" begin
    T = Float64
    L = T(2π)
    layout = RealFourierLayout()
    coarse_grid, fine_grid = Grid3D((8, 8, 8), (L, L, L)), Grid3D((16, 16, 16), (L, L, L))
    coarse, fine = zeroed(Val(0), coarse_grid, layout), zeroed(Val(0), fine_grid, layout)

    # The direction is the verb's, not the caller's: each refuses the other's argument order.
    @test_throws ArgumentError embed_modes!(coarse, fine)
    @test_throws ArgumentError extract_modes!(fine, coarse)

    @test_throws ArgumentError embed_modes!(fine, zeroed(Val(0), fine_grid, layout))      # equal grids
    @test_throws ArgumentError extract_modes!(coarse, zeroed(Val(0), coarse_grid, layout))

    other_box = Grid3D((8, 8, 8), (L, L, 3L))
    @test_throws ArgumentError embed_modes!(fine, zeroed(Val(0), other_box, layout))
    shifted = Grid3D((8, 8, 8), (L, L, L); origin = (T(1), T(0), T(0)))
    @test_throws ArgumentError embed_modes!(fine, zeroed(Val(0), shifted, layout))
    @test_throws ArgumentError embed_modes!(fine, zeroed(Val(0), coarse_grid, RealFourierLayout((3, 1, 2))))
    @test_throws ArgumentError embed_modes!(fine, VectorFieldSpectral(Array, coarse_grid; layout))

    mixed = Grid3D((8, 20, 8), (L, L, L))     # larger than the fine grid on one axis, smaller on another
    @test_throws ArgumentError embed_modes!(fine, zeroed(Val(0), mixed, layout))

    single = Grid3D((8, 8, 8), (Float32(2π), Float32(2π), Float32(2π)))
    @test_throws ArgumentError embed_modes!(fine, zeroed(Val(0), single, layout))         # scalar type
  end

  @testset "physical representation is absent" begin
    T = Float64
    L = T(2π)
    coarse_grid, fine_grid = Grid3D((8, 8, 8), (L, L, L)), Grid3D((16, 16, 16), (L, L, L))
    @test_throws MethodError embed_modes!(ScalarFieldPhysical(Array, fine_grid),
                                          ScalarFieldPhysical(Array, coarse_grid))
    @test_throws MethodError extract_modes!(ScalarFieldPhysical(Array, coarse_grid),
                                            ScalarFieldPhysical(Array, fine_grid))
  end

end
