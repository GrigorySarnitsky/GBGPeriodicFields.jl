# Tests for src/DifferentialOperators.jl: the spectral differential operators,
# verified by analytic round-trips (physical -> spectral -> operator -> physical)
# using the Fields convenience constructor FieldSpectralMultipliers(field).

using Test
using GBGPeriodicFields
using Random: MersenneTwister

const T = Float64
const gs = (8, 8, 8)
const grid = Grid3D(gs, (2π, 2π, 2π))
const layout = RealFourierLayout()
const F = GBGPeriodicFields.Fields

comp(data, i) = data[:, :, :, i]
tcomp(data, i, j) = data[:, :, :, i, j]
scalar_field(f) = ScalarFieldPhysical(f, grid)

# Forward+inverse plans matching the tensor order of `physical`.
function plans_for(physical)
  R = field_tensor_order(physical)
  shape = F.spectral_field_shape(grid, layout, Val(R))
  spectral = R == 0 ? ScalarFieldSpectral(zeros(Complex{T}, shape), grid) :
             R == 1 ? VectorFieldSpectral(zeros(Complex{T}, shape), grid) :
                      TensorFieldSpectral{R}(zeros(Complex{T}, shape), grid)
  return FieldTransformPlans(physical, spectral)
end

zero_vector() = VectorFieldPhysical(zeros(T, gs..., 3), grid)
zero_tensor() = TensorFieldPhysical{2}(zeros(T, gs..., 3, 3), grid)

@testset "DifferentialOperators.jl" begin

  @testset "gradient (scalar -> vector)" begin
    phi = scalar_field((x, y, z) -> sin(x))
    m = FieldSpectralMultipliers(to_spectral(phi, plans_for(phi)))
    g = to_physical(gradient(to_spectral(phi, plans_for(phi)), m), plans_for(zero_vector()))
    @test comp(field_data(g), 1) ≈ field_data(scalar_field((x, y, z) -> cos(x)))   # ∂ₓ sin x = cos x
    @test maximum(abs, comp(field_data(g), 2)) < 1e-12
    @test maximum(abs, comp(field_data(g), 3)) < 1e-12
  end

  # The tensor divergence had NO analytic oracle: its only value fixture was a tensor of nine IDENTICAL
  # components, so A ≡ Aᵀ and contracting the wrong index was invisible, while every other assertion on
  # it was self-referential (threaded vs serial, device vs host, compressed vs stored kernel — each
  # comparing the same contraction against itself). This pins the convention (∇·A)ᵢ = ∂ⱼAᵢⱼ against a
  # closed form, with a tensor whose components are all distinct and A ≠ Aᵀ (decision 52).
  @testset "divergence (tensor -> vector): (∇·A)ᵢ = ∂ⱼAᵢⱼ, against a closed form" begin
    # A₁₂ = sin y and A₂₃ = sin z are the only non-zero entries, so (∇·A) = (cos y, cos z, 0) exactly,
    # and the transposed contraction ∂ⱼAⱼᵢ would give (0, 0, 0) instead.
    A = TensorFieldPhysical{2}((x, y, z) -> [0.0 sin(y) 0.0; 0.0 0.0 sin(z); 0.0 0.0 0.0], grid)
    As = to_spectral(A, plans_for(A))
    m = FieldSpectralMultipliers(As)
    d = to_physical(divergence(As, m), plans_for(zero_vector()))
    @test comp(field_data(d), 1) ≈ field_data(scalar_field((x, y, z) -> cos(y)))
    @test comp(field_data(d), 2) ≈ field_data(scalar_field((x, y, z) -> cos(z)))
    @test maximum(abs, comp(field_data(d), 3)) < 1e-12
    # and the convention is not the transpose's: ∇·A ≠ ∇·Aᵀ for this A
    At = to_spectral(TensorFieldPhysical{2}((x, y, z) -> [0.0 0.0 0.0; sin(y) 0.0 0.0; 0.0 sin(z) 0.0], grid),
                     plans_for(A))
    dt = to_physical(divergence(At, m), plans_for(zero_vector()))
    @test !isapprox(field_data(d), field_data(dt))
    # ∇·(∇u) = Δu componentwise, an independent route through two operators
    u = VectorFieldPhysical((x, y, z) -> (sin(y), sin(z), sin(x)), grid)
    us = to_spectral(u, plans_for(u))
    mu = FieldSpectralMultipliers(us)
    @test field_data(divergence(gradient(us, mu), mu)) ≈ field_data(laplacian(us, mu))
  end

  @testset "gradient (vector -> tensor): (∇u)ᵢⱼ = ∂ⱼuᵢ" begin
    u = VectorFieldPhysical((x, y, z) -> (sin(x), sin(y), sin(z)), grid)
    m = FieldSpectralMultipliers(to_spectral(u, plans_for(u)))
    G = to_physical(gradient(to_spectral(u, plans_for(u)), m), plans_for(zero_tensor()))
    @test tcomp(field_data(G), 1, 1) ≈ field_data(scalar_field((x, y, z) -> cos(x)))
    @test tcomp(field_data(G), 2, 2) ≈ field_data(scalar_field((x, y, z) -> cos(y)))
    @test tcomp(field_data(G), 3, 3) ≈ field_data(scalar_field((x, y, z) -> cos(z)))
    # A DIAGONAL fixture cannot see the index convention this testset is named for: with
    # u = (sin x, sin y, sin z) every off-diagonal entry is zero, so (∇u)₁₂ and (∇u)₂₁ are
    # indistinguishable and transposing the whole operator passes silently. Pin it with a fixture whose
    # gradient is genuinely off-diagonal (decision 52).
    ushift = VectorFieldPhysical((x, y, z) -> (sin(y), sin(z), sin(x)), grid)
    Gs = to_physical(gradient(to_spectral(ushift, plans_for(ushift)), m), plans_for(zero_tensor()))
    @test tcomp(field_data(Gs), 1, 2) ≈ field_data(scalar_field((x, y, z) -> cos(y)))   # ∂_y u₁
    @test tcomp(field_data(Gs), 2, 3) ≈ field_data(scalar_field((x, y, z) -> cos(z)))   # ∂_z u₂
    @test tcomp(field_data(Gs), 3, 1) ≈ field_data(scalar_field((x, y, z) -> cos(x)))   # ∂_x u₃
    @test maximum(abs, tcomp(field_data(Gs), 2, 1)) < 1e-12    # the transposed slots stay empty
    @test maximum(abs, tcomp(field_data(Gs), 3, 2)) < 1e-12
    @test maximum(abs, tcomp(field_data(Gs), 1, 3)) < 1e-12

    @test maximum(abs, tcomp(field_data(G), 1, 2)) < 1e-12
  end

  @testset "divergence (vector -> scalar)" begin
    u = VectorFieldPhysical((x, y, z) -> (sin(x), sin(y), sin(z)), grid)
    m = FieldSpectralMultipliers(to_spectral(u, plans_for(u)))
    d = to_physical(divergence(to_spectral(u, plans_for(u)), m), plans_for(scalar_field((x, y, z) -> 0.0)))
    @test field_data(d) ≈ field_data(scalar_field((x, y, z) -> cos(x) + cos(y) + cos(z)))
  end

  @testset "curl" begin
    u = VectorFieldPhysical((x, y, z) -> (0.0, 0.0, sin(x)), grid)   # ∇ × u = (0, -cos x, 0)
    m = FieldSpectralMultipliers(to_spectral(u, plans_for(u)))
    c = to_physical(curl(to_spectral(u, plans_for(u)), m), plans_for(zero_vector()))
    @test maximum(abs, comp(field_data(c), 1)) < 1e-12
    @test comp(field_data(c), 2) ≈ field_data(scalar_field((x, y, z) -> -cos(x)))
    @test maximum(abs, comp(field_data(c), 3)) < 1e-12
  end

  @testset "symmetric_gradient: sym(∇u), formed fused" begin
    u = VectorFieldPhysical((x, y, z) -> (sin(x) + cos(2y), sin(y) * cos(z), cos(x) + sin(3z)), grid)
    us = to_spectral(u, plans_for(u))
    m = FieldSpectralMultipliers(us)
    S = symmetric_gradient(us, m)
    @test S isa TensorFieldSpectral{2}
    @test field_data(S) ≈ field_data(sym(gradient(us, m)))              # == sym(∇u) exactly (same coefficients)
    @test field_data(S) ≈ permutedims(field_data(S), (1, 2, 3, 5, 4))   # symmetric in the fiber indices

    # analytic: S₁₁ = ∂ₓu₁ = cos x; S₁₂ = ½(∂_y u₁ + ∂ₓ u₂) = ½(−2 sin 2y + 0) = −sin 2y
    Sp = to_physical(S, plans_for(zero_tensor()))
    @test tcomp(field_data(Sp), 1, 1) ≈ field_data(scalar_field((x, y, z) -> cos(x)))
    @test tcomp(field_data(Sp), 1, 2) ≈ field_data(scalar_field((x, y, z) -> -sin(2y)))
    @test tcomp(field_data(Sp), 2, 1) ≈ tcomp(field_data(Sp), 1, 2)     # symmetry in physical space too

    dest = TensorFieldSpectral{2}(zeros(Complex{T}, F.spectral_field_shape(grid, layout, Val(2))), grid)
    symmetric_gradient!(dest, us, m)                                    # in-place matches allocating
    @test field_data(dest) ≈ field_data(S)
  end

  @testset "laplacian: Δ sin(x) = -sin(x)" begin
    phi = scalar_field((x, y, z) -> sin(x))
    m = FieldSpectralMultipliers(to_spectral(phi, plans_for(phi)))
    lap = to_physical(laplacian(to_spectral(phi, plans_for(phi)), m), plans_for(phi))
    @test field_data(lap) ≈ .-field_data(phi)
  end

  @testset "inverse_laplacian inverts laplacian on a zero-mean field" begin
    phi = scalar_field((x, y, z) -> sin(x) * cos(y))
    m = FieldSpectralMultipliers(to_spectral(phi, plans_for(phi)))
    lap_spec = laplacian(to_spectral(phi, plans_for(phi)), m)
    recovered = to_physical(inverse_laplacian(lap_spec, m), plans_for(phi))
    @test field_data(recovered) ≈ field_data(phi)
  end

  @testset "helmholtz projection yields a divergence-free field" begin
    u = VectorFieldPhysical((x, y, z) -> (sin(x), sin(y), 0.0), grid)   # ∇·u = cos x + cos y ≠ 0
    m = FieldSpectralMultipliers(to_spectral(u, plans_for(u)))
    projected = helmholtz_projection(to_spectral(u, plans_for(u)), m)
    div_after = to_physical(divergence(projected, m), plans_for(scalar_field((x, y, z) -> 0.0)))
    @test maximum(abs, field_data(div_after)) < 1e-12
  end

  @testset "kernel-composed operators: a convolution fused into ℙ and ∇· (decision 32)" begin
    u = VectorFieldPhysical((x, y, z) -> (sin(x) + cos(2y), sin(y) * cos(z), cos(x) + sin(3z)), grid)
    us = to_spectral(u, plans_for(u))
    m = FieldSpectralMultipliers(us)
    g = spectral_cutoff(m, 2.5)                     # nontrivial: removes the |k| > 2.5 shells

    # the fused form equals the sequential operator-then-convolve composition, coefficient for
    # coefficient (α = 1 makes the fused scale exactly ĝ, so the products round identically)
    @test field_data(helmholtz_projection(us, m, g)) == field_data(convolve(helmholtz_projection(us, m), g))
    @test field_data(divergence(us, m, g)) == field_data(convolve(divergence(us, m), g))

    A = TensorFieldPhysical{2}((x, y, z) -> fill(sin(x) * cos(y), 3, 3), grid)
    As = to_spectral(A, plans_for(A))
    @test field_data(divergence(As, m, g)) == field_data(convolve(divergence(As, m), g))

    # α/β accumulate against a hand-built reference, and the α = −1 sign fold (exact: (−1)·x = −x)
    sequential = convolve(helmholtz_projection(us, m), g)
    accumulated = VectorFieldSpectral(copy(field_data(us)), grid)
    helmholtz_projection!(accumulated, us, m, g, T(1 // 2), T(2))
    @test field_data(accumulated) ≈ T(1 // 2) .* field_data(sequential) .+ T(2) .* field_data(us)
    negated = F.similar_field(us, Val(0))
    divergence!(negated, us, m, g, T(-1), T(0))
    @test field_data(negated) == .-field_data(convolve(divergence(us, m), g))
    taccumulated = VectorFieldSpectral(copy(field_data(us)), grid)
    divergence!(taccumulated, As, m, g, T(1 // 2), T(2))
    @test field_data(taccumulated) ≈ T(1 // 2) .* field_data(convolve(divergence(As, m), g)) .+ T(2) .* field_data(us)

    # the kernel may alias the destination (the product is coefficientwise)
    # The kernel wraps the very array being written, so this is still the aliased case: `StoredKernel`
    # declares the role without copying anything.
    kernel_as_destination = ScalarFieldSpectral(copy(field_data(materialize_kernel(g).field)), grid)
    divergence!(kernel_as_destination, us, m,
                GBGPeriodicFields.Convolution.StoredKernel(kernel_as_destination))
    @test field_data(kernel_as_destination) == field_data(convolve(divergence(us, m), g))
  end

  @testset "anisotropic domain (2π, 4π, 6π): wavenumber scaling" begin
    # Lx ≠ Ly ≠ Lz, so the 2π/L factor in the wavenumbers is non-trivial: a dropped
    # length factor (assuming L = 2π on every axis) would corrupt the y and z
    # derivatives while leaving x correct. sin(x)/sin(y)/sin(z) are each periodic on
    # this box (their 2π period divides 2π, 4π, 6π) and resolved (modes 1, 2, 3 < 4).
    aniso = Grid3D(gs, (2π, 4π, 6π))
    function aplans(physical)
      R = field_tensor_order(physical)
      data = zeros(Complex{T}, F.spectral_field_shape(aniso, layout, Val(R)))
      spectral = R == 0 ? ScalarFieldSpectral(data, aniso) :
                 R == 1 ? VectorFieldSpectral(data, aniso) :
                          TensorFieldSpectral{R}(data, aniso)
      return FieldTransformPlans(physical, spectral)
    end
    aniso_scalar(f) = ScalarFieldPhysical(f, aniso)

    phi = aniso_scalar((x, y, z) -> sin(x) + sin(y) + sin(z))
    m = FieldSpectralMultipliers(to_spectral(phi, aplans(phi)))

    g = to_physical(gradient(to_spectral(phi, aplans(phi)), m),
                    aplans(VectorFieldPhysical(zeros(T, gs..., 3), aniso)))
    @test comp(field_data(g), 1) ≈ field_data(aniso_scalar((x, y, z) -> cos(x)))   # Lx = 2π
    @test comp(field_data(g), 2) ≈ field_data(aniso_scalar((x, y, z) -> cos(y)))   # Ly = 4π
    @test comp(field_data(g), 3) ≈ field_data(aniso_scalar((x, y, z) -> cos(z)))   # Lz = 6π

    lap = to_physical(laplacian(to_spectral(phi, aplans(phi)), m), aplans(phi))
    @test field_data(lap) ≈ field_data(aniso_scalar((x, y, z) -> -(sin(x) + sin(y) + sin(z))))

    # symmetric_gradient on the anisotropic box: the diagonal Sᵢᵢ = ∂_{xᵢ}uᵢ picks up the per-axis
    # 2π/L, so a dropped Ly = 4π / Lz = 6π factor corrupts S₂₂ / S₃₃ while leaving S₁₁ correct.
    ua = VectorFieldPhysical((x, y, z) -> (sin(x), sin(y), sin(z)), aniso)
    ma = FieldSpectralMultipliers(to_spectral(ua, aplans(ua)))
    Sa = to_physical(symmetric_gradient(to_spectral(ua, aplans(ua)), ma),
                     aplans(TensorFieldPhysical{2}(zeros(T, gs..., 3, 3), aniso)))
    @test tcomp(field_data(Sa), 1, 1) ≈ field_data(aniso_scalar((x, y, z) -> cos(x)))   # Lx = 2π
    @test tcomp(field_data(Sa), 2, 2) ≈ field_data(aniso_scalar((x, y, z) -> cos(y)))   # Ly = 4π
    @test tcomp(field_data(Sa), 3, 3) ≈ field_data(aniso_scalar((x, y, z) -> cos(z)))   # Lz = 6π
    @test maximum(abs, tcomp(field_data(Sa), 1, 2)) < 1e-12                              # off-diagonals vanish
  end

  @testset "in-place operators and alias guards" begin
    u = VectorFieldPhysical((x, y, z) -> (sin(x) + cos(y), sin(y) + cos(z), sin(z) + cos(x)), grid)
    m = FieldSpectralMultipliers(to_spectral(u, plans_for(u)))
    us = to_spectral(u, plans_for(u))

    # in-place forms with a caller-supplied destination match the allocating forms
    gdest = F.similar_field(us, Val(2)); gradient!(gdest, us, m)
    @test field_data(gdest) ≈ field_data(gradient(us, m))
    ddest = F.similar_field(us, Val(0)); divergence!(ddest, us, m)
    @test field_data(ddest) ≈ field_data(divergence(us, m))
    cdest = F.similar_field(us, Val(1)); curl!(cdest, us, m)
    @test field_data(cdest) ≈ field_data(curl(us, m))
    ldest = F.similar_field(us, Val(1)); laplacian!(ldest, us, m)
    @test field_data(ldest) ≈ field_data(laplacian(us, m))
    ildest = F.similar_field(us, Val(1)); inverse_laplacian!(ildest, laplacian(us, m), m)
    @test field_data(ildest) ≈ field_data(inverse_laplacian(laplacian(us, m), m))
    hdest = F.similar_field(us, Val(1)); helmholtz_projection!(hdest, us, m)
    @test field_data(hdest) ≈ field_data(helmholtz_projection(us, m))

    # aliasing: curl! and helmholtz_projection! both compute the aliased call directly (each fused
    # pass reads a mode's three source components before writing any), so the aliased result is
    # bitwise-identical to the non-aliased one — no guard temporary on either
    expected_curl = field_data(curl(us, m))
    aliased = to_spectral(u, plans_for(u)); curl!(aliased, aliased, m)
    @test field_data(aliased) == expected_curl
    expected_projection = field_data(helmholtz_projection(us, m))
    aliased_projection = to_spectral(u, plans_for(u)); helmholtz_projection!(aliased_projection, aliased_projection, m)
    @test field_data(aliased_projection) == expected_projection
  end

  @testset "Nyquist mode end-to-end (the derivative / squared split)" begin
    # cos(4x) on N = 8 is the Nyquist mode of axis 1. The first-derivative wavenumber is
    # zeroed there (so ∂ of a real field stays real — the true derivative -4 sin(4x) is
    # identically 0 at the grid points), while the squared wavenumber keeps k² = 16.
    phi = scalar_field((x, y, z) -> cos(4x))
    m = FieldSpectralMultipliers(to_spectral(phi, plans_for(phi)))
    g = to_physical(gradient(to_spectral(phi, plans_for(phi)), m), plans_for(zero_vector()))
    @test maximum(abs, comp(field_data(g), 1)) < 1e-12                            # derivative zeroed at Nyquist
    lap = to_physical(laplacian(to_spectral(phi, plans_for(phi)), m), plans_for(phi))
    @test field_data(lap) ≈ field_data(scalar_field((x, y, z) -> -16 * cos(4x)))   # squared keeps k² = 16
  end

  @testset "vector-calculus identities: div(curl u) = 0, curl(grad φ) = 0" begin
    u = VectorFieldPhysical((x, y, z) -> (sin(x) + cos(y), sin(y) + cos(z), sin(z) + cos(x)), grid)
    m = FieldSpectralMultipliers(to_spectral(u, plans_for(u)))
    us = to_spectral(u, plans_for(u))
    div_curl = to_physical(divergence(curl(us, m), m), plans_for(scalar_field((x, y, z) -> 0.0)))
    @test maximum(abs, field_data(div_curl)) < 1e-12

    phi = scalar_field((x, y, z) -> sin(x) * cos(y) + sin(2z))
    ps = to_spectral(phi, plans_for(phi))
    curl_grad = to_physical(curl(gradient(ps, m), m), plans_for(zero_vector()))
    @test maximum(abs, field_data(curl_grad)) < 1e-12
  end

  @testset "intentional absences (differential operators are spectral-only)" begin
    # Differentiation lives in the spectral representation; there are no physical-grid
    # (finite-difference) operators yet, by design. Symmetric to the spectral nonlinear
    # absences in test/fieldalgebra.jl: those assert nonlinear products are absent in
    # spectral, these assert the differential operators are absent in physical.
    phi = scalar_field((x, y, z) -> sin(x))
    u = VectorFieldPhysical((x, y, z) -> (sin(x), cos(y), sin(z)), grid)
    m = FieldSpectralMultipliers(to_spectral(phi, plans_for(phi)))
    @test_throws MethodError gradient(phi, m)
    @test_throws MethodError gradient(u, m)
    @test_throws MethodError divergence(u, m)
    @test_throws MethodError curl(u, m)
    @test_throws MethodError laplacian(phi, m)
    @test_throws MethodError inverse_laplacian(phi, m)
    @test_throws MethodError helmholtz_projection(u, m)
    g_absence = spectral_cutoff(m, 2.5)
    @test_throws MethodError divergence(u, m, g_absence)                 # kernel-composed forms too
    @test_throws MethodError helmholtz_projection(u, m, g_absence)
  end

end


@testset "helmholtz projection: exactly idempotent and solenoidal with Nyquist content ($T)" for T in (Float64, Float32)
  rtol = T === Float64 ? 1e-11 : 1e-4
  N = 8
  grid = Grid3D((N, N, N), (T(2π), T(2π), T(2π)))
  layout = RealFourierLayout()
  phys = VectorFieldPhysical(rand(T, N, N, N, 3), grid)
  scaffold = VectorFieldSpectral(zeros(Complex{T}, spectral_field_shape(grid, layout, Val(1))), grid)
  plans = FieldTransformPlans(phys, scaffold)
  uh = to_spectral(phys, plans)          # a full spectrum: the Nyquist planes carry content
  m = FieldSpectralMultipliers(uh)
  projected = helmholtz_projection(uh, m)
  # The discrete divergence is annihilated at every mode, the mixed-Nyquist planes included
  # (decision 42: the projector's denominator is the derivative-family |a|²).
  residual = maximum(abs, field_data(divergence(projected, m)))
  original = maximum(abs, field_data(divergence(uh, m)))
  @test residual ≤ rtol * original
  # Exact idempotency, not only on the resolved band.
  twice = helmholtz_projection(projected, m)
  @test field_data(twice) ≈ field_data(projected) rtol = rtol
end


@testset "inverse_laplacian: a non-mean-free input is projected onto the compatible part ($T)" for T in (Float64, Float32)
  N = 8
  grid = Grid3D((N, N, N), (T(2π), T(2π), T(2π)))
  layout = RealFourierLayout()
  phys = ScalarFieldPhysical(rand(T, N, N, N) .+ T(3), grid)     # mean far from zero
  scaffold = ScalarFieldSpectral(zeros(Complex{T}, spectral_field_shape(grid, layout, Val(0))), grid)
  plans = FieldTransformPlans(phys, scaffold)
  fh = to_spectral(phys, plans)
  m = FieldSpectralMultipliers(fh)
  psi = inverse_laplacian(fh, m)
  @test field_data(psi)[1, 1, 1] == 0                    # the zero mode is set to exactly zero
  back = laplacian(psi, m)
  expected = field_data(to_spectral(phys, plans))        # a fresh copy of the coefficients …
  expected[1, 1, 1] = 0                                  # … with the mean projected out
  atol = (T === Float64 ? 1e-9 : 1e-1) * maximum(abs, expected)
  @test field_data(back) ≈ expected atol = atol          # Δψ = f − f̄, per mode
end



@testset "permuted rfft layout + anisotropic box: the operator set vs closed forms ($TP)" for TP in (Float64, Float32)
  # One deliberately hostile base: non-cubic sizes (8,6,4), unequal lengths (2π,4π,6π) so every
  # per-axis 2π/L factor differs, and a permuted rfft fold (axis 2). The closed-form oracles
  # carry the per-axis fundamentals explicitly, so an axis mix-up or a dropped length factor
  # is loud, in both element types (the F32 numerics previously ran only under GPU parity).
  atol_c = TP === Float64 ? 1e-12 : 2e-4
  sizes = (8, 6, 4)
  lengths = (TP(2π), TP(4π), TP(6π))
  kf = ntuple(a -> TP(2π) / lengths[a], 3)                   # fundamentals (1, 1/2, 1/3)
  grid_p = Grid3D(sizes, lengths)
  layout_p = RealFourierLayout((2, 1, 3))                    # fold on spatial axis 2
  xs = [(i - 1) * lengths[1] / sizes[1] for i in 1:8]
  ys = [(j - 1) * lengths[2] / sizes[2] for j in 1:6]
  zs = [(l - 1) * lengths[3] / sizes[3] for l in 1:4]

  s = ScalarFieldPhysical(
    [sin(kf[1] * xs[i]) * cos(kf[2] * ys[j]) for i in 1:8, j in 1:6, l in 1:4], grid_p, layout_p)
  s_scaffold = ScalarFieldSpectral(zeros(Complex{TP}, spectral_field_shape(grid_p, layout_p, Val(0))),
                                   grid_p, layout_p)
  plans_s = FieldTransformPlans(s, s_scaffold)
  v_scaffold_p = VectorFieldPhysical(zeros(TP, 8, 6, 4, 3), grid_p, layout_p)
  v_scaffold_s = VectorFieldSpectral(zeros(Complex{TP}, spectral_field_shape(grid_p, layout_p, Val(1))),
                                     grid_p, layout_p)
  plans_v = FieldTransformPlans(v_scaffold_p, v_scaffold_s)
  t_scaffold_p = TensorFieldPhysical{2}(zeros(TP, 8, 6, 4, 3, 3), grid_p, layout_p)
  t_scaffold_s = TensorFieldSpectral{2}(
    zeros(Complex{TP}, spectral_field_shape(grid_p, layout_p, Val(2))), grid_p, layout_p)
  plans_t = FieldTransformPlans(t_scaffold_p, t_scaffold_s)
  sh = to_spectral(s, plans_s)
  m = FieldSpectralMultipliers(sh)

  # gradient and laplacian: ∇s = (kf₁ cos·cos, −kf₂ sin·sin, 0), Δs = −(kf₁² + kf₂²)·s
  g = to_physical(gradient(sh, m), plans_v)
  @test view(field_data(g), :, :, :, 1) ≈
        [kf[1] * cos(kf[1] * xs[i]) * cos(kf[2] * ys[j]) for i in 1:8, j in 1:6, l in 1:4] atol = atol_c
  @test view(field_data(g), :, :, :, 2) ≈
        [-kf[2] * sin(kf[1] * xs[i]) * sin(kf[2] * ys[j]) for i in 1:8, j in 1:6, l in 1:4] atol = atol_c
  @test maximum(abs, view(field_data(g), :, :, :, 3)) ≤ atol_c
  lap = to_physical(laplacian(sh, m), plans_s)
  @test field_data(lap) ≈ -(kf[1]^2 + kf[2]^2) .* field_data(s) atol = atol_c

  # u = (sin(kf₂ y), sin(kf₃ z), sin(kf₁ x)) is solenoidal with closed-form curl and symmetric
  # gradient; v = u + ∇s has divergence Δs and the exact Helmholtz projection ℙv = u
  u = VectorFieldPhysical(zeros(TP, 8, 6, 4, 3), grid_p, layout_p)
  v = VectorFieldPhysical(zeros(TP, 8, 6, 4, 3), grid_p, layout_p)
  for l in 1:4, j in 1:6, i in 1:8
    field_data(u)[i, j, l, 1] = sin(kf[2] * ys[j])
    field_data(u)[i, j, l, 2] = sin(kf[3] * zs[l])
    field_data(u)[i, j, l, 3] = sin(kf[1] * xs[i])
    field_data(v)[i, j, l, 1] = field_data(u)[i, j, l, 1] + kf[1] * cos(kf[1] * xs[i]) * cos(kf[2] * ys[j])
    field_data(v)[i, j, l, 2] = field_data(u)[i, j, l, 2] - kf[2] * sin(kf[1] * xs[i]) * sin(kf[2] * ys[j])
    field_data(v)[i, j, l, 3] = field_data(u)[i, j, l, 3]
  end
  uh = to_spectral(u, plans_v)
  vh = to_spectral(v, plans_v)
  @test maximum(abs, field_data(to_physical(divergence(uh, m), plans_s))) ≤ atol_c
  @test field_data(to_physical(divergence(vh, m), plans_s)) ≈
        -(kf[1]^2 + kf[2]^2) .* field_data(s) atol = atol_c
  curl_u = to_physical(curl(uh, m), plans_v)
  @test view(field_data(curl_u), :, :, :, 1) ≈
        [-kf[3] * cos(kf[3] * zs[l]) for i in 1:8, j in 1:6, l in 1:4] atol = atol_c
  @test view(field_data(curl_u), :, :, :, 2) ≈
        [-kf[1] * cos(kf[1] * xs[i]) for i in 1:8, j in 1:6, l in 1:4] atol = atol_c
  @test view(field_data(curl_u), :, :, :, 3) ≈
        [-kf[2] * cos(kf[2] * ys[j]) for i in 1:8, j in 1:6, l in 1:4] atol = atol_c
  S = to_physical(symmetric_gradient(uh, m), plans_t)
  @test view(field_data(S), :, :, :, 1, 2) ≈
        [kf[2] * cos(kf[2] * ys[j]) / 2 for i in 1:8, j in 1:6, l in 1:4] atol = atol_c
  @test view(field_data(S), :, :, :, 1, 3) ≈
        [kf[1] * cos(kf[1] * xs[i]) / 2 for i in 1:8, j in 1:6, l in 1:4] atol = atol_c
  @test view(field_data(S), :, :, :, 2, 3) ≈
        [kf[3] * cos(kf[3] * zs[l]) / 2 for i in 1:8, j in 1:6, l in 1:4] atol = atol_c
  @test maximum(abs, view(field_data(S), :, :, :, 1, 1)) ≤ atol_c
  @test maximum(abs, view(field_data(S), :, :, :, 2, 2)) ≤ atol_c
  @test maximum(abs, view(field_data(S), :, :, :, 3, 3)) ≤ atol_c
  @test field_data(to_physical(helmholtz_projection(vh, m), plans_v)) ≈ field_data(u) atol = atol_c
  @test field_data(to_physical(inverse_laplacian(laplacian(sh, m), m), plans_s)) ≈
        field_data(s) atol = atol_c

  # mixed-Nyquist closed forms: f = cos(kN₁x)·cos(kN₂y) is pure Nyquist on two axes at once —
  # the derivative family zeroes both (gradient and curl annihilate it), the squared family
  # keeps the true k² (the laplacian scales it exactly, invariant 5)
  kN = (sizes[1] ÷ 2 * kf[1], sizes[2] ÷ 2 * kf[2])
  f_nyq = ScalarFieldPhysical(
    [cos(kN[1] * xs[i]) * cos(kN[2] * ys[j]) for i in 1:8, j in 1:6, l in 1:4], grid_p, layout_p)
  fh_nyq = to_spectral(f_nyq, plans_s)
  @test maximum(abs, field_data(to_physical(gradient(fh_nyq, m), plans_v))) ≤ atol_c
  @test field_data(to_physical(laplacian(fh_nyq, m), plans_s)) ≈
        -(kN[1]^2 + kN[2]^2) .* field_data(f_nyq) atol = 40 * atol_c
  w_nyq = VectorFieldPhysical(zeros(TP, 8, 6, 4, 3), grid_p, layout_p)
  view(field_data(w_nyq), :, :, :, 3) .= field_data(f_nyq)
  @test maximum(abs, field_data(to_physical(curl(to_spectral(w_nyq, plans_v), m), plans_v))) ≤ atol_c

  # kernel-composed arities on a FULL-SPECTRUM random field (Nyquist content flows through the
  # decision-42 projector and the kernel product): fused == sequential, and the α = 0, β ≠ 0
  # branch — previously asserted nowhere in the package — must reduce to dest ← β·dest
  vr = VectorFieldPhysical(rand(TP, 8, 6, 4, 3), grid_p, layout_p)
  vrh = to_spectral(vr, plans_v)
  # `squared_wavenumber_field` returns the |k|² COORDINATE, a field a consumer builds symbols from —
  # so using it as a kernel now states that role explicitly.
  w = radial_kernel(identity, m)
  @test field_data(symmetric_gradient(vrh, m)) ≈ field_data(sym(gradient(vrh, m)))
  fused_div = F.similar_field(sh, Val(0))
  divergence!(fused_div, vrh, m, w)
  @test field_data(fused_div) ≈ field_data(convolve(divergence(vrh, m), w))
  fused_helm = F.similar_field(vrh, Val(1))
  helmholtz_projection!(fused_helm, vrh, m, w)
  @test field_data(fused_helm) ≈ field_data(convolve(helmholtz_projection(vrh, m), w))
  before_helm = copy(field_data(fused_helm))
  helmholtz_projection!(fused_helm, vrh, m, w, TP(0), TP(2))
  @test field_data(fused_helm) == 2 .* before_helm
  before_div = copy(field_data(fused_div))
  divergence!(fused_div, vrh, m, w, TP(0), TP(2))
  @test field_data(fused_div) == 2 .* before_div

  # dest === source aliasing for the coefficientwise pair (previously unpinned anywhere)
  lap_ref = laplacian(vrh, m)
  aliased = VectorFieldSpectral(copy(field_data(vrh)), grid_p, layout_p)
  laplacian!(aliased, aliased, m)
  @test field_data(aliased) == field_data(lap_ref)
  inv_ref = inverse_laplacian(vrh, m)
  aliased_inv = VectorFieldSpectral(copy(field_data(vrh)), grid_p, layout_p)
  inverse_laplacian!(aliased_inv, aliased_inv, m)
  @test field_data(aliased_inv) == field_data(inv_ref)
end


# Decision 50 + the module-placement panel's M2: a kernel argument accepts EITHER storage class —
# one held as a field, or a compressed SpectralKernel evaluated per mode. This testset is the
# guard that the gap cannot reappear: it walks every kernel-taking entry point in the package and
# requires the two classes to agree bitwise. When a new kernel family lands, add it to `kernels`.
@testset "every kernel-taking entry point accepts both storage classes" begin
  for TP in (Float64, Float32)
    gk = Grid3D((8, 6, 4), (TP(2π), TP(4π), TP(6π)))
    lk = RealFourierLayout()
    s0 = ScalarFieldSpectral(zeros(Complex{TP}, spectral_field_shape(gk, lk, Val(0))), gk, lk)
    mk = FieldSpectralMultipliers(s0)
    compressed = translation_kernel(mk, (TP(0.3), TP(-0.7), TP(1.1)))
    stored = materialize_kernel(compressed)
    rng = MersenneTwister(50)
    u = VectorFieldSpectral(rand(rng, Complex{TP}, size(field_data(s0))..., 3), gk, lk)
    A = TensorFieldSpectral(rand(rng, Complex{TP}, size(field_data(s0))..., 3, 3), gk, lk)
    both(build) = field_data(build(compressed)) == field_data(build(stored))

    @test both(k -> convolve(u, k))                                     # Convolution
    @test both(k -> helmholtz_projection(u, mk, k))                     # DifferentialOperators
    @test both(k -> divergence(u, mk, k))
    @test both(k -> divergence(A, mk, k))                               # tensor fiber signature
    # the in-place forms, overwrite and α/β
    for (dest_order, build) in ((1, (d, k) -> helmholtz_projection!(d, u, mk, k)),
                                (0, (d, k) -> divergence!(d, u, mk, k)),
                                (1, (d, k) -> divergence!(d, A, mk, k)))
      dc = similar_field(u, Val(dest_order)); ds = similar_field(u, Val(dest_order))
      build(dc, compressed); build(ds, stored)
      @test field_data(dc) == field_data(ds)
    end
    ac = 2 * divergence(u, mk, stored); as = 2 * divergence(u, mk, stored)
    divergence!(ac, u, mk, compressed, TP(1 // 2), TP(2))
    divergence!(as, u, mk, stored, TP(1 // 2), TP(2))
    @test field_data(ac) == field_data(as)
    # the kernel-composed combine! (Convolution) takes both too
    b = VectorFieldSpectral(rand(rng, Complex{TP}, size(field_data(s0))..., 3), gk, lk)
    cc = similar_field(u, Val(1)); cs = similar_field(u, Val(1))
    combine!(cc, TP(1 // 3), u, TP(2 // 3), b, compressed)
    combine!(cs, TP(1 // 3), u, TP(2 // 3), b, stored)
    @test field_data(cc) == field_data(cs)
  end
end


# ── the Jacobian's index convention ───────────────────────────────────────────────────────────────
#
# Ported from the exhaustive survey, which found this unpinned. The only check on `gradient`'s
# vector→tensor mode was `symmetric_gradient = sym(gradient(u))`, and `sym(M) = sym(Mᵀ)` erases a
# transposed fibre-index pair before the comparison ever sees it — so an implementation computing
# ∂u_j/∂x_i in place of ∂u_i/∂x_j passed. The fixture is deliberately asymmetric: the two off-diagonal
# entries below are different functions with different amplitudes, so swapping them cannot go unnoticed.
@testset "gradient (vector -> tensor): the index convention (∇u)_ij = ∂u_i/∂x_j" begin
  x = [i for i in range(0, 2π, length = gs[1] + 1)[1:end-1], _ in 1:gs[2], _ in 1:gs[3]]
  y = [j for _ in 1:gs[1], j in range(0, 2π, length = gs[2] + 1)[1:end-1], _ in 1:gs[3]]
  data = zeros(T, gs..., 3)
  data[:, :, :, 1] .= sin.(y)            # u₁ = sin(y)  ⇒ ∂u₁/∂x₂ = cos(y)
  data[:, :, :, 2] .= sin.(3 .* x)       # u₂ = sin(3x) ⇒ ∂u₂/∂x₁ = 3cos(3x)
  u = VectorFieldPhysical(data, grid)
  plans = plans_for(u)
  multipliers = FieldSpectralMultipliers(to_spectral(u, plans))
  jacobian = to_physical(gradient(to_spectral(u, plans), multipliers), plans_for(zero_tensor()))
  J = field_data(jacobian)

  @test tcomp(J, 1, 2) ≈ cos.(y)         atol = 1e-10
  @test tcomp(J, 2, 1) ≈ 3 .* cos.(3 .* x) atol = 1e-10
  # The discriminator: the two entries are genuinely different, so a transposed implementation would
  # have to fail one of the assertions above. Asserting that keeps this test from silently becoming
  # symmetric if the fixture is ever edited.
  @test !isapprox(cos.(y), 3 .* cos.(3 .* x); atol = 1e-6)
  for (i, j) in ((1, 1), (2, 2), (3, 3), (1, 3), (3, 1), (2, 3), (3, 2))
    @test all(abs.(tcomp(J, i, j)) .< 1e-10)
  end
end
