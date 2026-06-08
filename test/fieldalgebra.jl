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
tcomp(data, i, j) = data[:, :, :, i, j]              # tensor component slice (Array copy)
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

  # ---------------------------------------------------------------------------
  # M3: contractions, products, permutations, norms, decompositions
  # ---------------------------------------------------------------------------

  tensor_a(x, y, z) = [sin(x) cos(y) 0.3; 0.5 sin(z) cos(x); 1.0 cos(z) sin(y)]
  tensor_b(x, y, z) = [cos(x) 0.1 sin(y); sin(z) cos(y) 0.2; 0.7 sin(x) cos(z)]

  @testset "vector dot / cross (physical + fiber)" begin
    u = VectorFieldPhysical((x, y, z) -> (sin(x), cos(y), sin(z) + 0.2), grid)
    v = VectorFieldPhysical((x, y, z) -> (cos(x), sin(2y), cos(z)), grid)
    k = FiberVector{T}((1.0, -2.0, 0.5))
    ud = field_data(u); vd = field_data(v)

    d = dot(u, v)
    @test d isa ScalarFieldPhysical
    @test field_data(d) ≈ comp(ud, 1) .* comp(vd, 1) .+ comp(ud, 2) .* comp(vd, 2) .+ comp(ud, 3) .* comp(vd, 3)
    @test field_data(dot(u, k)) ≈ comp(ud, 1) .* k[1] .+ comp(ud, 2) .* k[2] .+ comp(ud, 3) .* k[3]
    @test field_data(dot(k, u)) ≈ field_data(dot(u, k))           # inner product is commutative

    c = cross(u, v); cd = field_data(c)
    @test c isa VectorFieldPhysical
    @test comp(cd, 1) ≈ comp(ud, 2) .* comp(vd, 3) .- comp(ud, 3) .* comp(vd, 2)
    @test comp(cd, 2) ≈ comp(ud, 3) .* comp(vd, 1) .- comp(ud, 1) .* comp(vd, 3)
    @test comp(cd, 3) ≈ comp(ud, 1) .* comp(vd, 2) .- comp(ud, 2) .* comp(vd, 1)
    @test field_data(cross(k, u)) ≈ .-field_data(cross(u, k))     # cross is antisymmetric

    # alias safety: writing into an input still gives the correct result (guard)
    w = cross(u, v)
    cross!(u, u, v)
    @test field_data(u) ≈ field_data(w)
  end

  @testset "tensor inner product + transpose" begin
    A = TensorFieldPhysical{2}(tensor_a, grid)
    B = TensorFieldPhysical{2}(tensor_b, grid)
    Ad = field_data(A); Bd = field_data(B)

    inner = dot(A, B)
    @test inner isa ScalarFieldPhysical
    @test field_data(inner) ≈ sum(tcomp(Ad, i, j) .* tcomp(Bd, i, j) for i in 1:3 for j in 1:3)

    At = transpose(A)
    for i in 1:3, j in 1:3
      @test tcomp(field_data(At), i, j) ≈ tcomp(Ad, j, i)
    end
  end

  @testset "tensor-vector and tensor-tensor products" begin
    A = TensorFieldPhysical{2}(tensor_a, grid)
    B = TensorFieldPhysical{2}(tensor_b, grid)
    u = VectorFieldPhysical((x, y, z) -> (sin(x), cos(y), sin(z)), grid)
    Ad = field_data(A); Bd = field_data(B); ud = field_data(u)

    w = A * u                                                     # left action  (A u)ᵢ = Aᵢⱼ uⱼ
    for i in 1:3
      @test comp(field_data(w), i) ≈ sum(tcomp(Ad, i, j) .* comp(ud, j) for j in 1:3)
    end
    wr = u * A                                                    # right action (u A)ᵢ = uⱼ Aⱼᵢ
    for i in 1:3
      @test comp(field_data(wr), i) ≈ sum(comp(ud, j) .* tcomp(Ad, j, i) for j in 1:3)
    end
    C = A * B                                                     # (A B)ᵢⱼ = Aᵢₖ Bₖⱼ
    for i in 1:3, j in 1:3
      @test tcomp(field_data(C), i, j) ≈ sum(tcomp(Ad, i, k) .* tcomp(Bd, k, j) for k in 1:3)
    end

    # five-argument accumulation: destination = α * product + β * destination
    base = A * u
    dest = 2.0 * (A * u)
    keep = copy(field_data(dest))
    mul!(dest, A, u, 3.0, 5.0)
    @test field_data(dest) ≈ 3.0 .* field_data(base) .+ 5.0 .* keep

    # overwrite branch (β = 0): the destination's prior contents are ignored, NaN
    # included; if it accumulated instead of overwriting, the NaNs would survive.
    overwrite = VectorFieldPhysical(fill(T(NaN), gs..., 3), grid)
    mul!(overwrite, A, u, 1.0, 0.0)
    @test field_data(overwrite) ≈ field_data(base)
  end

  @testset "norms (physical only)" begin
    s = ScalarFieldPhysical((x, y, z) -> sin(x) - 0.5, grid)
    u = VectorFieldPhysical((x, y, z) -> (sin(x), cos(y), sin(z)), grid)
    A = TensorFieldPhysical{2}(tensor_a, grid)
    @test field_data(norm(s)) ≈ abs.(field_data(s))
    @test field_data(norm(u)) ≈ sqrt.(comp(field_data(u), 1) .^ 2 .+ comp(field_data(u), 2) .^ 2 .+ comp(field_data(u), 3) .^ 2)
    @test field_data(norm(A)) ≈ sqrt.(sum(tcomp(field_data(A), i, j) .^ 2 for i in 1:3 for j in 1:3))
  end

  @testset "sym / skew / dev (fields + fibers)" begin
    A = TensorFieldPhysical{2}(tensor_a, grid)
    Ad = field_data(A)
    S = sym(A); K = skew(A); D = dev(A)
    @test field_data(S) .+ field_data(K) ≈ Ad                     # A = sym + skew
    @test tcomp(field_data(S), 1, 2) ≈ tcomp(field_data(S), 2, 1)        # symmetric
    @test tcomp(field_data(K), 1, 2) ≈ .-tcomp(field_data(K), 2, 1)      # antisymmetric
    @test tcomp(field_data(K), 2, 2) ≈ zeros(T, gs)                      # zero diagonal
    @test maximum(abs, tcomp(field_data(D), 1, 1) .+ tcomp(field_data(D), 2, 2) .+ tcomp(field_data(D), 3, 3)) < 1e-12  # traceless (to roundoff)

    M = FiberTensor2{T}(ntuple(i -> Float64(i) + 0.5, 9))
    @test sym(M) ≈ (M + transpose(M)) / 2
    @test skew(M) ≈ (M - transpose(M)) / 2
    @test dev(M) ≈ M - ((M[1, 1] + M[2, 2] + M[3, 3]) / 3) * one(M)
  end

  @testset "spectral linear contractions are coefficient-wise" begin
    A = TensorFieldPhysical{2}(tensor_a, grid)
    u = VectorFieldPhysical((x, y, z) -> (sin(x), cos(y), sin(z)), grid)
    k = FiberVector{T}((1.0, -2.0, 0.5))
    As = to_spectral(A, plans_for(A)); us = to_spectral(u, plans_for(u))

    Ast = transpose(As)                                           # index permutation of coefficients
    for i in 1:3, j in 1:3
      @test tcomp(field_data(Ast), i, j) ≈ tcomp(field_data(As), j, i)
    end
    Ss = sym(As)
    @test tcomp(field_data(Ss), 1, 2) ≈ 0.5 .* (tcomp(field_data(As), 1, 2) .+ tcomp(field_data(As), 2, 1))

    ds = dot(us, k)                                               # vector field · fiber, coefficient-wise
    @test field_data(ds) ≈ comp(field_data(us), 1) .* k[1] .+ comp(field_data(us), 2) .* k[2] .+ comp(field_data(us), 3) .* k[3]

    ws = As * k                                                   # tensor field · fiber -> vector field
    @test ws isa VectorFieldSpectral
    for i in 1:3
      @test comp(field_data(ws), i) ≈ sum(tcomp(field_data(As), i, j) .* k[j] for j in 1:3)
    end
  end

  @testset "M3 intentional absences (spectral nonlinear products)" begin
    u = VectorFieldPhysical((x, y, z) -> (sin(x), 1.0, 1.0), grid)
    v = VectorFieldPhysical((x, y, z) -> (cos(x), 1.0, 1.0), grid)
    A = TensorFieldPhysical{2}(tensor_a, grid)
    B = TensorFieldPhysical{2}(tensor_b, grid)
    us = to_spectral(u, plans_for(u)); vs = to_spectral(v, plans_for(v))
    As = to_spectral(A, plans_for(A)); Bs = to_spectral(B, plans_for(B))

    @test_throws MethodError dot(us, vs)          # two vector fields, spectral
    @test_throws MethodError cross(us, vs)        # cross of two vector fields, spectral
    @test_throws MethodError dot(As, Bs)          # two tensor fields, spectral
    @test_throws MethodError As * Bs              # tensor-tensor field product, spectral
    @test_throws MethodError As * us              # tensor-vector field product, spectral
    @test_throws MethodError norm(us)             # pointwise norm, spectral
    @test_throws MethodError norm(As)
  end

  @testset "in-place forms and alias guards" begin
    u = VectorFieldPhysical((x, y, z) -> (sin(x), cos(y), sin(z) + 0.2), grid)
    v = VectorFieldPhysical((x, y, z) -> (cos(x), sin(2y), cos(z)), grid)
    A = TensorFieldPhysical{2}(tensor_a, grid)
    sf = phys_scalar((x, y, z) -> 2.0 + sin(x))     # nonzero everywhere

    # contractions / norms / division write into a caller-supplied destination
    sdest = F.similar_field(u, Val(0)); dot!(sdest, u, v)
    @test field_data(sdest) ≈ field_data(dot(u, v))
    ndest = F.similar_field(u, Val(0)); norm!(ndest, u)
    @test field_data(ndest) ≈ field_data(norm(u))
    qdest = F.similar_field(v, Val(1)); divide!(qdest, v, sf)
    @test field_data(qdest) ≈ field_data(v / sf)

    # index-shuffles into a caller-supplied destination
    tdest = F.similar_field(A, Val(2)); transpose!(tdest, A)
    @test field_data(tdest) ≈ field_data(transpose(A))
    symdest = F.similar_field(A, Val(2)); sym!(symdest, A)
    @test field_data(symdest) ≈ field_data(sym(A))

    # alias guards (invariant 9): destination === source must still be correct
    At = field_data(transpose(A)); Asym = field_data(sym(A))
    Askew = field_data(skew(A)); Adev = field_data(dev(A))
    a1 = TensorFieldPhysical{2}(tensor_a, grid); transpose!(a1, a1); @test field_data(a1) ≈ At
    a2 = TensorFieldPhysical{2}(tensor_a, grid); sym!(a2, a2);       @test field_data(a2) ≈ Asym
    a3 = TensorFieldPhysical{2}(tensor_a, grid); skew!(a3, a3);      @test field_data(a3) ≈ Askew
    a4 = TensorFieldPhysical{2}(tensor_a, grid); dev!(a4, a4);       @test field_data(a4) ≈ Adev
  end

  @testset "linear field/fiber ops: physical/spectral symmetry" begin
    # Operations linear in the field exist in BOTH representations and commute with the
    # transform: applying in spectral and inverting equals applying in physical. (Nonlinear
    # field-field products are physical-only — asserted absent in spectral above.)
    u = VectorFieldPhysical((x, y, z) -> (sin(x) * cos(y), cos(z), sin(z) + 0.3), grid)
    A = TensorFieldPhysical{2}(tensor_a, grid)
    sf = phys_scalar((x, y, z) -> 0.7 + sin(x) * sin(y))
    k = FiberVector{T}((1.0, -2.0, 0.5))
    M = FiberTensor2{T}(ntuple(i -> Float64(i) + 0.5, 9))
    uplans = plans_for(u); Aplans = plans_for(A); sfplans = plans_for(sf)
    us = to_spectral(u, uplans); As = to_spectral(A, Aplans); sfs = to_spectral(sf, sfplans)

    # apply in spectral, invert, and compare to the physical result (plans match the
    # result's tensor order).
    same(spectral_result, physical_result, plans) =
      field_data(to_physical(spectral_result, plans)) ≈ field_data(physical_result)

    @test same(us + k, u + k, uplans)              # field ± fiber (spectral: zero-mode update)
    @test same(k + us, k + u, uplans)
    @test same(us - k, u - k, uplans)
    @test same(As + M, A + M, Aplans)
    @test same(sfs * k, sf * k, uplans)            # scalar field × fiber -> vector
    @test same(k * sfs, k * sf, uplans)
    @test same(dot(us, k), dot(u, k), sfplans)     # vector · fiber -> scalar
    @test same(dot(k, us), dot(k, u), sfplans)
    @test same(cross(us, k), cross(u, k), uplans)  # vector × fiber -> vector
    @test same(cross(k, us), cross(k, u), uplans)
    @test same(As * k, A * k, uplans)              # tensor · fiber -> vector
    @test same(transpose(As), transpose(A), Aplans)
    @test same(sym(As), sym(A), Aplans)
    @test same(skew(As), skew(A), Aplans)
    @test same(dev(As), dev(A), Aplans)
    @test same(2.5 * us, 2.5 * u, uplans)          # real scaling
    @test same(us / 4.0, u / 4.0, uplans)
  end

end
