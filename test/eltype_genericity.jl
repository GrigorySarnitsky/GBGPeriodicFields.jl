# Element-type genericity on CPU. The package is generic over T<:AbstractFloat, but the
# rest of the suite only exercises Float64. This runs a representative cross-section for
# each T in (Float64, Float32) and asserts both correctness (with eltype-scaled
# tolerances) and that operations PRESERVE the element type — a stray Float64 literal or
# a missing conversion would silently promote to Float64 and is caught here.

using Test
using GBGPeriodicFields

const F = GBGPeriodicFields.Fields
const ELEMENT_TYPES = (Float64, Float32)

comp(data, i) = data[:, :, :, i]


function run_eltype_tests(::Type{T}) where {T<:AbstractFloat}
  grid = Grid3D((8, 7, 6), (T(2π), T(2π), T(2π)))     # mixed parity, Grid3D{T}
  layout = RealFourierLayout()
  reltol = T === Float32 ? 1.0f-4 : 1e-10
  abstol = T === Float32 ? 1.0f-5 : 1e-12
  approx(a, b) = isapprox(a, b; rtol = reltol, atol = abstol)

  function plans_for(physical)
    R = field_tensor_order(physical)
    shape = F.field_spectral_shape(grid, layout, Val(R))
    spectral = R == 0 ? ScalarFieldSpectral(zeros(Complex{T}, shape), grid) :
               R == 1 ? VectorFieldSpectral(zeros(Complex{T}, shape), grid) :
                        TensorFieldSpectral{R}(zeros(Complex{T}, shape), grid)
    return FieldTransformPlans(physical, spectral)
  end

  @testset "T = $T" begin

    @testset "construction yields element type $T" begin
      a = ScalarFieldPhysical(Array, (x, y, z) -> sin(x), grid)
      v = VectorFieldPhysical(Array, (x, y, z) -> (sin(x), cos(y), sin(z)), grid)
      A = TensorFieldPhysical{2}(Array, (x, y, z) -> fill(sin(x), 3, 3), grid)
      @test field_scalar_type(a) === T
      @test eltype(field_data(a)) === T
      @test eltype(field_data(v)) === T
      @test eltype(field_data(A)) === T
    end

    @testset "FFT round-trip preserves type and value" begin
      a = ScalarFieldPhysical(Array, (x, y, z) -> sin(x) * cos(y) + 0.3, grid)
      plans = plans_for(a)
      spectral = to_spectral(a, plans)
      @test eltype(field_data(spectral)) === Complex{T}
      back = to_physical(spectral, plans)
      @test eltype(field_data(back)) === T
      @test approx(field_data(back), field_data(a))
    end

    @testset "algebra preserves element type and values" begin
      a = ScalarFieldPhysical(Array, (x, y, z) -> sin(x), grid)
      b = ScalarFieldPhysical(Array, (x, y, z) -> cos(y), grid)
      u = VectorFieldPhysical(Array, (x, y, z) -> (sin(x), cos(y), sin(z)), grid)
      v = VectorFieldPhysical(Array, (x, y, z) -> (cos(x), sin(y), 1.0), grid)
      A = TensorFieldPhysical{2}(Array, (x, y, z) -> [sin(x) cos(y) 0.0; 0.0 sin(z) cos(x); 1.0 0.0 sin(y)], grid)

      sum_ab = a + b
      scaled = 2.5 * a               # a Float64 scalar must not promote a Float32 field
      contraction = dot(u, v)
      product = A * u
      combined = combine!(F.similar_field(u, Val(1)), 2.5, u, -1.5, v)   # Float64 weights must not promote
      determinant = det(A)
      for field in (sum_ab, scaled, contraction, product, combined, determinant)
        @test eltype(field_data(field)) === T
      end
      @test approx(field_data(sum_ab), field_data(a) .+ field_data(b))
      @test approx(field_data(scaled), 2.5 .* field_data(a))
      @test approx(field_data(contraction),
                   comp(field_data(u), 1) .* comp(field_data(v), 1) .+
                   comp(field_data(u), 2) .* comp(field_data(v), 2) .+
                   comp(field_data(u), 3) .* comp(field_data(v), 3))
      @test approx(comp(field_data(product), 1),
                   sum(field_data(A)[:, :, :, 1, j] .* comp(field_data(u), j) for j in 1:3))
      @test approx(field_data(combined), 2.5 .* field_data(u) .- 1.5 .* field_data(v))
      @test approx(field_data(determinant),
                   [det(field_data(A)[i, j, k, :, :]) for i in 1:8, j in 1:7, k in 1:6])
    end

    @testset "laplacian round-trip: Δ sin x = -sin x" begin
      phi = ScalarFieldPhysical(Array, (x, y, z) -> sin(x), grid)
      m = FieldSpectralMultipliers(to_spectral(phi, plans_for(phi)))
      lap = to_physical(laplacian(to_spectral(phi, plans_for(phi)), m), plans_for(phi))
      @test eltype(field_data(lap)) === T
      @test approx(field_data(lap), .-field_data(phi))
    end

    @testset "spectral symmetric_gradient / weighted_inner preserve element type" begin
      u = VectorFieldPhysical(Array, (x, y, z) -> (sin(x), cos(y), sin(z)), grid)
      us = to_spectral(u, plans_for(u))
      m = FieldSpectralMultipliers(us)
      S = symmetric_gradient(us, m)
      @test eltype(field_data(S)) === Complex{T}
      @test approx(field_data(S), field_data(sym(gradient(us, m))))

      w1 = GBGPeriodicFields.Convolution.StoredKernel(
             ScalarFieldSpectral(fill(one(Complex{T}), F.field_spectral_shape(grid, layout, Val(0))), grid))
      @test weighted_inner(us, w1) isa T                    # a Float64 must not leak in
      @test approx(weighted_inner(us, w1), inner(us, us))
    end

    # `lpnorm` leaked a Float64 for every exponent except the two that return early. The exponents were
    # written `p` and `1 / p`, which are `Float64` whatever the section holds, so `Float32 ^ Float64`
    # widened the result — a lost element type, not merely an inference wobble. This testset checked
    # `weighted_inner` for exactly that leak and never checked the reduction that had it, so the axis is
    # swept over the exponent here: the two early-return values AND the general branch, integer and
    # fractional, since only the general branch was ever wrong.
    @testset "lpnorm preserves element type at every exponent" begin
      u = VectorFieldPhysical(Array, (x, y, z) -> (sin(x), cos(y), sin(z)), grid)
      for p in (1, 2, 3, T(2.5), Inf)
        @test lpnorm(u, p) isa T
      end
      @test lpnorm(u, 2) isa T && approx(lpnorm(u, 2), l2norm(u))
      s = ScalarFieldPhysical(Array, (x, y, z) -> sin(x), grid)
      for p in (1, 3, Inf)
        @test lpnorm(s, p) isa T
      end
      q = ScalarPointValues(rand(T, 12))                   # the counting-measure base, same property
      @test lpnorm(q, 3) isa T
    end

  end
end


@testset "element-type genericity (Float64 + Float32)" begin
  for T in ELEMENT_TYPES
    run_eltype_tests(T)
  end
end
