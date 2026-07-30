# Tests for src/FieldAlgebra.jl (M2 scope): addition/subtraction, real scaling,
# scalar-field multiplication and division, in both representations. The spectral
# tests check the zero-mode constant invariant and the linearity of allowed
# operations via FFT round-trips, and assert the intentional absences.

using Test
using GBGPeriodicFields
using Random

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

  @testset "trace (fields + fibers, both representations)" begin
    A = TensorFieldPhysical{2}(tensor_a, grid)
    Ad = field_data(A)
    expected = tcomp(Ad, 1, 1) .+ tcomp(Ad, 2, 2) .+ tcomp(Ad, 3, 3)
    @test tr(A) isa ScalarFieldPhysical
    @test field_data(tr(A)) ≈ expected
    @test field_data(tr(sym(A))) ≈ expected                        # antisymmetric part is traceless
    @test maximum(abs, field_data(tr(dev(A)))) < 1e-12             # deviator is traceless
    dest = F.similar_field(A, Val(0)); tr!(dest, A)                # in-place matches allocating
    @test field_data(dest) ≈ expected

    M = FiberTensor2{T}(ntuple(i -> Float64(i) + 0.5, 9))
    @test tr(M) ≈ M[1, 1] + M[2, 2] + M[3, 3]

    As = to_spectral(A, plans_for(A))                              # linear ⇒ coefficient-wise
    @test tr(As) isa ScalarFieldSpectral
    @test field_data(tr(As)) ≈ tcomp(field_data(As), 1, 1) .+ tcomp(field_data(As), 2, 2) .+ tcomp(field_data(As), 3, 3)
  end

  @testset "determinant (fields + fibers, physical only)" begin
    A = TensorFieldPhysical{2}(tensor_a, grid)
    Ad = field_data(A)
    expected = [det(Ad[i, j, k, :, :]) for i in 1:gs[1], j in 1:gs[2], k in 1:gs[3]]  # per-point 3×3 LU det (independent of Sarrus)
    @test det(A) isa ScalarFieldPhysical
    @test field_data(det(A)) ≈ expected
    dest = F.similar_field(A, Val(0)); det!(dest, A)               # in-place matches allocating
    @test field_data(dest) ≈ expected

    M = FiberTensor2{T}(ntuple(i -> Float64(i)^2 + 0.3, 9))        # a single fiber value already has det
    @test det(M) ≈ det(Matrix(M))

    As = to_spectral(A, plans_for(A))                              # nonlinear ⇒ spectral form intentionally absent
    @test_throws MethodError det(As)
    @test_throws MethodError det!(F.similar_field(As, Val(0)), As)
  end

  @testset "weighted combination combine! (physical + spectral)" begin
    av = VectorFieldPhysical((x, y, z) -> (sin(x), cos(y), sin(z)), grid)
    bv = VectorFieldPhysical((x, y, z) -> (cos(x), sin(y), z + 0.2), grid)
    dest = F.similar_field(av, Val(1))
    combine!(dest, 2.0, av, -3.0, bv)
    @test field_data(dest) ≈ 2.0 .* field_data(av) .- 3.0 .* field_data(bv)
    @test field_data(dest) ≈ field_data(2.0 * av - 3.0 * bv)       # equals the operator expression α·a + β·b

    a0 = phys_scalar((x, y, z) -> sin(x)); b0 = phys_scalar((x, y, z) -> cos(y) + 0.3)
    d0 = phys_scalar_zero(); combine!(d0, 0.5, a0, 4.0, b0)        # R = 0
    @test field_data(d0) ≈ 0.5 .* field_data(a0) .+ 4.0 .* field_data(b0)
    At = TensorFieldPhysical{2}(tensor_a, grid); Bt = TensorFieldPhysical{2}(tensor_b, grid)
    dt = F.similar_field(At, Val(2)); combine!(dt, -1.0, At, 2.0, Bt)  # R = 2
    @test field_data(dt) ≈ -1.0 .* field_data(At) .+ 2.0 .* field_data(Bt)

    as = to_spectral(av, plans_for(av)); bs = to_spectral(bv, plans_for(bv))  # spectral: same on coefficients
    ds = F.similar_field(as, Val(1)); combine!(ds, 0.5, as, 4.0, bs)
    @test field_data(ds) ≈ 0.5 .* field_data(as) .+ 4.0 .* field_data(bs)

    u = VectorFieldPhysical((x, y, z) -> (sin(x), cos(y), sin(z)), grid); u0 = copy(field_data(u))
    k = VectorFieldPhysical((x, y, z) -> (1.0, cos(z), x), grid)
    combine!(u, 1.0, u, 0.5, k)                                    # alias-safe accumulate u ← u + ½k
    @test field_data(u) ≈ u0 .+ 0.5 .* field_data(k)
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


@testset "det multiplicativity: det(AB) = det(A)·det(B) ($T)" for T in (Float64, Float32)
  rtol = T === Float64 ? 1e-10 : 1e-3
  N = 4
  grid = Grid3D((N, N, N), (T(2π), T(2π), T(2π)))
  A = TensorFieldPhysical{2}(rand(T, N, N, N, 3, 3), grid)
  B = TensorFieldPhysical{2}(rand(T, N, N, N, 3, 3), grid)
  @test field_data(det(A * B)) ≈ field_data(det(A) * det(B)) rtol = rtol
end


@testset "coverage-axes closure: α = 0, aliasing, the constant family, permuted fold ($TP)" for TP in (Float64, Float32)
  g8 = Grid3D((8, 6, 4), (TP(2π), TP(2π), TP(2π)))
  layout_d = RealFourierLayout()
  layout_p = RealFourierLayout((2, 1, 3))
  x = VectorFieldPhysical(rand(TP, 8, 6, 4, 3), g8)
  y = VectorFieldPhysical(rand(TP, 8, 6, 4, 3), g8)
  A2 = TensorFieldPhysical{2}(rand(TP, 8, 6, 4, 3, 3), g8)

  # α = 0, β ≠ 0 — the pure β-rescale branch of the two α/β-capable algebra ops, previously
  # asserted nowhere in the package (0·op + β·dest is exact for finite operands)
  dest = VectorFieldPhysical(rand(TP, 8, 6, 4, 3), g8)
  before = copy(field_data(dest))
  mul!(dest, A2, x, TP(0), TP(2))
  @test field_data(dest) == 2 .* before
  dest2 = VectorFieldPhysical(rand(TP, 8, 6, 4, 3), g8)
  combine!(dest2, TP(0), x, TP(2), y)                       # α = 0 annihilates the first operand
  @test field_data(dest2) == 2 .* field_data(y)

  # destination-aliasing for the M2 family — both directions, previously untested anywhere;
  # the field ± constant path is the branchy one (`===`-checked copy), so it is the key case
  ref_add = x + y
  xa = VectorFieldPhysical(copy(field_data(x)), g8); add!(xa, xa, y)          # dest ≡ a
  @test field_data(xa) == field_data(ref_add)
  yb = VectorFieldPhysical(copy(field_data(y)), g8); add!(yb, x, yb)          # dest ≡ b
  @test field_data(yb) == field_data(ref_add)
  ref_sub = x - y
  xs = VectorFieldPhysical(copy(field_data(x)), g8); subtract!(xs, xs, y)
  @test field_data(xs) == field_data(ref_sub)
  ys = VectorFieldPhysical(copy(field_data(y)), g8); subtract!(ys, x, ys)
  @test field_data(ys) == field_data(ref_sub)
  kv = FiberVector{TP}(TP[1, 2, 3])
  xc = VectorFieldPhysical(copy(field_data(x)), g8); add!(xc, xc, kv)         # aliased constant add
  @test field_data(xc) == field_data(x + kv)
  xcs = VectorFieldPhysical(copy(field_data(x)), g8); subtract!(xcs, xcs, kv)
  @test field_data(xcs) == field_data(x - kv)
  sm = ScalarFieldPhysical(rand(TP, 8, 6, 4), g8)
  sma = ScalarFieldPhysical(copy(field_data(sm)), g8); multiply!(sma, sma, TP(3))
  @test field_data(sma) == field_data(sm * TP(3))
  smd = ScalarFieldPhysical(copy(field_data(sm)), g8); divide!(smd, smd, TP(3))
  @test field_data(smd) == field_data(sm / TP(3))
  # cross!: dest ≡ b — the antisymmetric direction (only dest ≡ a was ever tested)
  ref_cross = cross(x, y)
  yx = VectorFieldPhysical(copy(field_data(y)), g8); cross!(yx, x, yx)
  @test field_data(yx) == field_data(ref_cross)
  # norm!: the scalar-operand self-alias is shape-compatible and was untested
  sn = ScalarFieldPhysical(copy(field_data(sm)), g8); norm!(sn, sn)
  @test field_data(sn) == field_data(norm(sm))

  # spectral in-place aliasing for the fused unary quartet — physical aliasing is tested, but
  # every spectral exercise used a fresh destination; decision 39 claims bitwise equality
  t_scaff = TensorFieldSpectral{2}(zeros(Complex{TP}, spectral_field_shape(g8, layout_d, Val(2))), g8)
  plans_t = FieldTransformPlans(A2, t_scaff)
  As2 = to_spectral(A2, plans_t)
  for (op!, op) in ((transpose!, transpose), (sym!, sym), (skew!, skew), (dev!, dev))
    ref_u = op(As2)
    aliased = TensorFieldSpectral{2}(copy(field_data(As2)), g8)
    op!(aliased, aliased)
    @test field_data(aliased) == field_data(ref_u)
  end

  # tensor-tensor mul! with a FiberTensor2 constant — four methods (both orders × both
  # representations) with previously ZERO coverage of any kind; per-point matmul oracle
  C = FiberTensor2{TP}(TP[1 2 0; 0 1 3; 1 0 1])
  Cm = Matrix(C)
  ref_AC = similar(field_data(A2)); ref_CA = similar(field_data(A2))
  for l in 1:4, j in 1:6, i in 1:8
    ref_AC[i, j, l, :, :] .= field_data(A2)[i, j, l, :, :] * Cm
    ref_CA[i, j, l, :, :] .= Cm * field_data(A2)[i, j, l, :, :]
  end
  destT = TensorFieldPhysical{2}(zeros(TP, 8, 6, 4, 3, 3), g8)
  mul!(destT, A2, C); @test field_data(destT) ≈ ref_AC
  mul!(destT, C, A2); @test field_data(destT) ≈ ref_CA
  destTs = TensorFieldSpectral{2}(zeros(Complex{TP}, spectral_field_shape(g8, layout_d, Val(2))), g8)
  mul!(destTs, As2, C); @test field_data(to_physical(destTs, plans_t)) ≈ ref_AC
  mul!(destTs, C, As2); @test field_data(to_physical(destTs, plans_t)) ≈ ref_CA

  # the spectral constant family — reversed-order and subtract directions were value-uncovered
  # (allocation-only); round-trip oracles, plus the physical tensor family full-array
  s_scaff = ScalarFieldSpectral(zeros(Complex{TP}, spectral_field_shape(g8, layout_d, Val(0))), g8)
  plans_s = FieldTransformPlans(sm, s_scaff)
  ss = to_spectral(sm, plans_s)
  c = TP(0.7)
  @test field_data(to_physical(ss - c, plans_s)) ≈ field_data(sm) .- c
  @test field_data(to_physical(c - ss, plans_s)) ≈ c .- field_data(sm)
  v_scaff = VectorFieldSpectral(zeros(Complex{TP}, spectral_field_shape(g8, layout_d, Val(1))), g8)
  plans_v = FieldTransformPlans(x, v_scaff)
  us = to_spectral(x, plans_v)
  kv_shape = reshape(collect(kv), 1, 1, 1, 3)
  @test field_data(to_physical(kv - us, plans_v)) ≈ kv_shape .- field_data(x)
  Ct = reshape(Cm, 1, 1, 1, 3, 3)
  @test field_data(to_physical(C + As2, plans_t)) ≈ Ct .+ field_data(A2)
  @test field_data(to_physical(As2 - C, plans_t)) ≈ field_data(A2) .- Ct
  @test field_data(to_physical(C - As2, plans_t)) ≈ Ct .- field_data(A2)
  @test field_data(A2 + C) ≈ field_data(A2) .+ Ct
  @test field_data(C + A2) ≈ field_data(A2) .+ Ct
  @test field_data(A2 - C) ≈ field_data(A2) .- Ct
  @test field_data(C - A2) ≈ Ct .- field_data(A2)

  # tr and det on the non-cubic grid, both element types, against direct per-point formulas
  # (tr was F64-cubic-only; det's F32 exercise was the multiplicativity identity, not an oracle)
  ref_tr = field_data(A2)[:, :, :, 1, 1] .+ field_data(A2)[:, :, :, 2, 2] .+ field_data(A2)[:, :, :, 3, 3]
  @test field_data(tr(A2)) ≈ ref_tr
  @test field_data(to_physical(tr(As2), plans_s)) ≈ ref_tr
  ref_det = [det(Matrix{TP}(field_data(A2)[i, j, l, :, :])) for i in 1:8, j in 1:6, l in 1:4]
  @test field_data(det(A2)) ≈ ref_det

  # permuted-fold representatives, one per executor family (broadcast M2, fiberwise-executor
  # M3, the zero-mode constant path): the algebra is coefficientwise, so these pin that no
  # code path silently assumes the fold sits on array dimension 1
  p_scaff = VectorFieldSpectral(zeros(Complex{TP}, spectral_field_shape(g8, layout_p, Val(1))), g8, layout_p)
  p1 = VectorFieldPhysical(rand(TP, 8, 6, 4, 3), g8, layout_p)
  p2 = VectorFieldPhysical(rand(TP, 8, 6, 4, 3), g8, layout_p)
  plans_p = FieldTransformPlans(p1, p_scaff)
  p1s = to_spectral(p1, plans_p); p2s = to_spectral(p2, plans_p)
  @test field_data(to_physical(p1s + p2s, plans_p)) ≈ field_data(p1) .+ field_data(p2)
  @test field_data(to_physical(p1s + kv, plans_p)) ≈ field_data(p1) .+ kv_shape   # zero-mode path
  ps_scaff = ScalarFieldSpectral(zeros(Complex{TP}, spectral_field_shape(g8, layout_p, Val(0))), g8, layout_p)
  ps_phys = ScalarFieldPhysical(zeros(TP, 8, 6, 4), g8, layout_p)
  plans_ps = FieldTransformPlans(ps_phys, ps_scaff)
  @test field_data(to_physical(dot(p1s, kv), plans_ps)) ≈
        dropdims(sum(kv_shape .* field_data(p1), dims = 4), dims = 4)
end


# map! / map — the arbitrary-φ fiberwise operation (decision 35's first map! instance). Checked against
# the named nonlinear operations as independent oracles, plus hand references, order changes, multi-input,
# α/β, aliasing, output-order inference, and the physical-only absence.
@testset "map! / map (arbitrary φ)" begin
  for TP in (Float64, Float32)
    gmap = Grid3D((6, 4, 8), (TP(2π), TP(4π), TP(6π)))   # anisotropic, mixed even lengths, non-cubic
    rng = MersenneTwister(2024)
    A = TensorFieldPhysical(rand(rng, TP, 6, 4, 8, 3, 3), gmap)
    u = VectorFieldPhysical(rand(rng, TP, 6, 4, 8, 3), gmap)
    w = VectorFieldPhysical(rand(rng, TP, 6, 4, 8, 3), gmap)
    s = ScalarFieldPhysical(rand(rng, TP, 6, 4, 8), gmap)

    # Equivalence with the named nonlinear fiber invariants (which are LinearAlgebra maps on the fiber).
    @test field_data(map(det, A)) ≈ field_data(det(A))
    @test field_data(map(tr, A)) ≈ field_data(tr(A))
    @test field_data(map(norm, u)) ≈ field_data(norm(u))

    # Composition, order-changing (tensor → scalar), with a hand reference and element-type preservation.
    dref = field_data(det(A))
    @test field_data(map(exp ∘ det, A)) ≈ exp.(dref)
    @test eltype(field_data(map(exp ∘ det, A))) === TP

    # Scalar → scalar, and a symmetric-part lambda vs the named `sym` (order-preserving).
    @test field_data(map(x -> x^2 + one(TP), s)) ≈ field_data(s) .^ 2 .+ one(TP)
    @test field_data(map(x -> (x + transpose(x)) / 2, A)) ≈ field_data(sym(A))
    @test field_data(map(x -> 2x, A)) ≈ 2 .* field_data(A)

    # Multi-input: order-changing (dot) and order-preserving (sum, cross) vs the named binary ops.
    @test field_data(map((a, b) -> a + b, u, w)) ≈ field_data(u + w)
    @test field_data(map((a, b) -> dot(a, b), u, w)) ≈ field_data(dot(u, w))
    @test field_data(map((a, b) -> cross(a, b), u, w)) ≈ field_data(cross(u, w))

    # In-place map! overwrites (α = 1, β = 0), from non-zero prior content, equal to the allocating map.
    dest = map(exp ∘ det, A); map!(det, dest, A)
    @test field_data(dest) ≈ dref

    # α/β accumulate (single source): starting at det(A), 2·det + 1·det = 3·det.
    acc = map(det, A); base = copy(field_data(acc)); map!(det, acc, A, TP(2), TP(1))
    @test field_data(acc) ≈ 3 .* base

    # α = 0, β ≠ 0 branch: the map result is discarded and the destination is pure-rescaled (dest = β·dest).
    r0 = map(det, A); r0base = copy(field_data(r0)); map!(det, r0, A, TP(0), TP(2))
    @test field_data(r0) ≈ 2 .* r0base

    # Aliasing: destination === source is safe by construction (fused pass reads before it writes).
    Aa = TensorFieldPhysical(copy(field_data(A)), gmap)
    map!(x -> 2x, Aa, Aa)
    @test field_data(Aa) ≈ 2 .* field_data(A)

    # Aliasing with multiple sources: destination === one of the sources (still read-before-write).
    ua = VectorFieldPhysical(copy(field_data(u)), gmap); u_before = copy(field_data(u))
    map!((a, b) -> a + b, ua, ua, w)     # dest ≡ first source
    @test field_data(ua) ≈ u_before .+ field_data(w)

    # The allocating `map` infers the output tensor order from φ (scalar / vector / tensor).
    @test map(det, A) isa ScalarFieldPhysical
    @test map(x -> 2x, u) isa VectorFieldPhysical
    @test map(x -> x * transpose(x), u) isa TensorFieldPhysical{2}     # vector → tensor (outer product)
  end

  # Parity (odd axis lengths) + non-zero origin: immaterial to a pointwise map, but on the coverage
  # checklist — one representative field, the named-op equivalence, and the α=0/β≠0 branch.
  godd = Grid3D((5, 4, 7), (2π, 2π, 2π); origin = (0.3, -0.7, 1.1))
  Ao = TensorFieldPhysical(rand(MersenneTwister(9), 5, 4, 7, 3, 3), godd)
  @test field_data(map(det, Ao)) ≈ field_data(det(Ao))
  ro = map(det, Ao); rob = copy(field_data(ro)); map!(det, ro, Ao, 0.0, 2.0)
  @test field_data(ro) ≈ 2 .* rob

  # Permuted rfft layout (decision 41): the ALLOCATING map must carry the reference's layout, not
  # default it. It did not, and `map` was broken on every permuted fold from the day it shipped —
  # the destination mismatched its source and the call threw. The axis this pins is metadata
  # propagation through an allocating operation, not the fold's effect on any transform.
  @testset "permuted rfft layout: map carries the layout" begin
    gp = Grid3D((8, 6, 4), (2π, 2π, 2π))
    for fold in ((2, 1, 3), (3, 2, 1), (1, 3, 2))
      lp = RealFourierLayout(fold)
      Ap = TensorFieldPhysical(rand(MersenneTwister(41), 8, 6, 4, 3, 3), gp, lp)
      up = VectorFieldPhysical(rand(MersenneTwister(42), 8, 6, 4, 3), gp, lp)
      @test field_layout(map(det, Ap)).fft_dims == fold              # tensor → scalar
      @test field_layout(map(x -> 2x, Ap)).fft_dims == fold          # order-preserving
      @test field_layout(map(x -> x * transpose(x), up)).fft_dims == fold   # vector → tensor
      @test field_data(map(det, Ap)) ≈ field_data(det(Ap))           # and still correct
    end
  end

  # Physical-space only (invariant 1): no map! method for a field in spectral representation (Base.map!
  # needs AbstractArray, so this is a genuine absence; the allocating map delegates to map!, and
  # Base.map's catch-all makes its own hasmethod uninformative).
  @test !hasmethod(map!, Tuple{typeof(det), ScalarFieldSpectral, TensorFieldSpectral{2}})
  @test !hasmethod(map!, Tuple{typeof(det), VectorFieldSpectral, VectorFieldSpectral})
end


# The infix aliases are public operations and must agree with the named functions they alias.
#
# Found by the oracle registry's citation check (decision 55): `⋅` was recorded as covered by this
# file, which used only `dot` — the glyph itself was never exercised. `×` and `⋆` were, which is why
# only one of the three surfaced. An alias is a separate binding, so "the function it forwards to is
# tested" is not the same claim as "the alias forwards".
@testset "the infix operator aliases agree with their named functions" begin
  grid = Grid3D((4, 4, 4), (2π, 2π, 2π))
  u = VectorFieldPhysical(rand(4, 4, 4, 3), grid)
  v = VectorFieldPhysical(rand(4, 4, 4, 3), grid)
  A = TensorFieldPhysical{2}(rand(4, 4, 4, 3, 3), grid)
  B = TensorFieldPhysical{2}(rand(4, 4, 4, 3, 3), grid)

  @test field_data(u ⋅ v) == field_data(dot(u, v))
  @test field_data(A ⋅ B) == field_data(dot(A, B))
  @test field_data(u × v) == field_data(cross(u, v))

  # The spectral kernel alias, on the representation where convolution is defined.
  layout = RealFourierLayout()
  spectral = ScalarFieldSpectral(
    zeros(ComplexF64, GBGPeriodicFields.Fields.spectral_field_shape(grid, layout, Val(0))), grid, layout)
  multipliers = FieldSpectralMultipliers(spectral)
  us = VectorFieldSpectral(randn(ComplexF64,
    GBGPeriodicFields.Fields.spectral_field_shape(grid, layout, Val(1))), grid, layout)
  kernel = spectral_band(spectral, multipliers, 0, 2)
  @test field_data(us ⋆ kernel) == field_data(convolve(us, kernel))
end
