# Tests for src/FieldAlgebra.jl (M2 scope): addition/subtraction, real scaling,
# scalar-field multiplication and division, in both representations. The spectral
# tests check the zero-mode constant invariant and the linearity of allowed
# operations via FFT round-trips, and assert the intentional absences.

using Test
using GBGPeriodicFields

const T = Float64
const gs = (8, 8, 8)
const grid = Grid3D(gs, (2π, 2π, 2π))
const layout = RealFourierLayout()
const F = GBGPeriodicFields.Fields

comp(data, i) = data[:, :, :, i]                     # vector component slice (Array copy)
phys_scalar(f) = ScalarFieldPhysical(f, grid)
phys_scalar_zero() = ScalarFieldPhysical(zeros(T, gs...), grid)

# Forward+inverse plans matching the tensor order of `physical`.
function plans_for(physical)
  R = field_tensor_order(physical)
  shape = F.spectral_field_shape(grid, layout, Val(R))
  spectral = R == 0 ? ScalarFieldSpectral(zeros(Complex{T}, shape), grid) :
             R == 1 ? VectorFieldSpectral(zeros(Complex{T}, shape), grid) :
                      TensorFieldSpectral{R}(zeros(Complex{T}, shape), grid)
  return FieldTransformPlans(physical, spectral)
end

@testset "FieldAlgebra.jl" begin

  @testset "addition / subtraction (physical)" begin
    a = phys_scalar((x, y, z) -> sin(x))
    b = phys_scalar((x, y, z) -> cos(y))
    c = phys_scalar((x, y, z) -> sin(z) + 0.5)

    @test field_data(a + b) ≈ field_data(a) .+ field_data(b)
    @test field_data(a - b) ≈ field_data(a) .- field_data(b)
    @test field_data(-a) ≈ .-field_data(a)
    @test (+a) === a

    dest = phys_scalar_zero()
    add!(dest, a, b, c)                       # multi-argument in-place sum
    @test field_data(dest) ≈ field_data(a) .+ field_data(b) .+ field_data(c)
    subtract!(dest, a, b, c)
    @test field_data(dest) ≈ field_data(a) .- field_data(b) .- field_data(c)

    # scalar field ± real number, both argument orders
    @test field_data(a + 2.0) ≈ field_data(a) .+ 2.0
    @test field_data(2.0 + a) ≈ field_data(a) .+ 2.0
    @test field_data(a - 2.0) ≈ field_data(a) .- 2.0
    @test field_data(2.0 - a) ≈ 2.0 .- field_data(a)
  end

  @testset "field ± constant fiber (physical)" begin
    v = VectorFieldPhysical((x, y, z) -> (sin(x), cos(y), sin(z)), grid)
    k = FiberVector{T}((1.0, 2.0, 3.0))     # StaticArraysCore: construct from a tuple
    vk = v + k
    for i in 1:3
      @test comp(field_data(vk), i) ≈ comp(field_data(v), i) .+ k[i]
    end
    @test field_data(k + v) ≈ field_data(vk)
    @test comp(field_data(v - k), 2) ≈ comp(field_data(v), 2) .- k[2]
    @test comp(field_data(k - v), 2) ≈ k[2] .- comp(field_data(v), 2)

    A = FiberTensor2{T}(ntuple(i -> Float64(i), 9))   # column-major 9-tuple
    t = TensorFieldPhysical{2}((x, y, z) -> fill(sin(x), 3, 3), grid)
    tA = t + A
    @test field_data(tA)[:, :, :, 2, 3] ≈ field_data(t)[:, :, :, 2, 3] .+ A[2, 3]
  end

  @testset "real scaling (physical + spectral)" begin
    a = phys_scalar((x, y, z) -> sin(x) * cos(y) + 0.3)
    @test field_data(2.0 * a) ≈ 2.0 .* field_data(a)
    @test field_data(a * 2.0) ≈ 2.0 .* field_data(a)
    @test field_data(a / 4.0) ≈ field_data(a) ./ 4.0

    dest = phys_scalar_zero()
    multiply!(dest, 3.0, a)
    @test field_data(dest) ≈ 3.0 .* field_data(a)

    # scaling commutes with the transform: scale in spectral, recover scaled physical
    plans = plans_for(a)
    spec = to_spectral(a, plans)
    @test field_data(to_physical(2.5 * spec, plans)) ≈ 2.5 .* field_data(a)
  end

  @testset "scalar-field multiplication / division (physical)" begin
    sf = phys_scalar((x, y, z) -> 2.0 + sin(x))      # nonzero everywhere
    v = VectorFieldPhysical((x, y, z) -> (cos(x), sin(y), 1.0), grid)
    a = phys_scalar((x, y, z) -> cos(z))
    k = FiberVector{T}((1.0, -2.0, 0.5))

    sv = sf * v
    for i in 1:3
      @test comp(field_data(sv), i) ≈ field_data(sf) .* comp(field_data(v), i)
    end
    @test field_data(v * sf) ≈ field_data(sv)              # commuted order
    @test field_data(sf * a) ≈ field_data(sf) .* field_data(a)

    # scalar field × constant fiber -> vector field
    sk = sf * k
    for i in 1:3
      @test comp(field_data(sk), i) ≈ field_data(sf) .* k[i]
    end
    @test field_data(k * sf) ≈ field_data(sk)

    # division by a scalar field
    for i in 1:3
      @test comp(field_data(v / sf), i) ≈ comp(field_data(v), i) ./ field_data(sf)
    end
    @test field_data(a / sf) ≈ field_data(a) ./ field_data(sf)
    @test field_data(2.0 / sf) ≈ 2.0 ./ field_data(sf)
    @test comp(field_data(k / sf), 1) ≈ k[1] ./ field_data(sf)
  end

  @testset "spectral constant addition: zero-mode only (invariant 4)" begin
    a = phys_scalar((x, y, z) -> sin(x) * cos(y))
    plans = plans_for(a)
    spec = to_spectral(a, plans)
    spec_plus = spec + 1.5

    # Only the zero Fourier coefficient changed, by c * prod(grid_size).
    delta = field_data(spec_plus) .- field_data(spec)
    @test delta[1, 1, 1] ≈ 1.5 * prod(gs)
    rest = copy(delta); rest[1, 1, 1] = 0
    @test all(iszero, rest)

    # physical values shift by exactly the constant after inverse transform
    @test field_data(to_physical(spec_plus, plans)) ≈ field_data(a) .+ 1.5
  end

  @testset "spectral scalar-field × fiber is coefficient-wise (linear)" begin
    a = phys_scalar((x, y, z) -> 0.7 + sin(x) * sin(y))
    k = FiberVector{T}((2.0, -1.0, 0.5))
    splans = plans_for(a)
    spec = to_spectral(a, splans)

    veck = spec * k                                   # VectorFieldSpectral
    @test veck isa VectorFieldSpectral
    vplans = plans_for(VectorFieldPhysical(zeros(T, gs..., 3), grid))
    back = to_physical(veck, vplans)
    for i in 1:3
      @test comp(field_data(back), i) ≈ field_data(a) .* k[i]
    end
  end

  @testset "intentional absences (spectral nonlinear products)" begin
    a = phys_scalar((x, y, z) -> sin(x))
    b = phys_scalar((x, y, z) -> cos(x))
    v = VectorFieldPhysical((x, y, z) -> (sin(x), 1.0, 1.0), grid)
    aplans = plans_for(a); vplans = plans_for(v)
    as = to_spectral(a, aplans); bs = to_spectral(b, aplans); vs = to_spectral(v, vplans)

    @test_throws MethodError as * bs              # field×field product not in spectral
    @test_throws MethodError as * vs              # scalar field × vector field not in spectral
    @test_throws MethodError vs / as              # division by a scalar field not in spectral
    @test_throws MethodError multiply!(F.similar_field(vs, Val(1)), as, vs)
  end

end
