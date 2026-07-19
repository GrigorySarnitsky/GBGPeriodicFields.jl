# Tests for src/DifferentialOperators.jl: the spectral differential operators,
# verified by analytic round-trips (physical -> spectral -> operator -> physical)
# using the Fields convenience constructor FieldSpectralMultipliers(field).

using Test
using GBGPeriodicFields

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

  @testset "gradient (vector -> tensor): (∇u)ᵢⱼ = ∂ⱼuᵢ" begin
    u = VectorFieldPhysical((x, y, z) -> (sin(x), sin(y), sin(z)), grid)
    m = FieldSpectralMultipliers(to_spectral(u, plans_for(u)))
    G = to_physical(gradient(to_spectral(u, plans_for(u)), m), plans_for(zero_tensor()))
    @test tcomp(field_data(G), 1, 1) ≈ field_data(scalar_field((x, y, z) -> cos(x)))
    @test tcomp(field_data(G), 2, 2) ≈ field_data(scalar_field((x, y, z) -> cos(y)))
    @test tcomp(field_data(G), 3, 3) ≈ field_data(scalar_field((x, y, z) -> cos(z)))
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
    g = spectral_cutoff(us, m, 2.5)                     # nontrivial: removes the |k| > 2.5 shells

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
    kernel_as_destination = ScalarFieldSpectral(copy(field_data(g)), grid)
    divergence!(kernel_as_destination, us, m, kernel_as_destination)
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

    # aliasing: curl! guards with a temporary; helmholtz_projection! computes the aliased call
    # directly (the one-pass kernel reads a mode's three components before writing them), so its
    # aliased result is bitwise-identical to the non-aliased one
    expected_curl = field_data(curl(us, m))
    aliased = to_spectral(u, plans_for(u)); curl!(aliased, aliased, m)
    @test field_data(aliased) ≈ expected_curl
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
    g_absence = spectral_cutoff(to_spectral(phi, plans_for(phi)), m, 2.5)
    @test_throws MethodError divergence(u, m, g_absence)                 # kernel-composed forms too
    @test_throws MethodError helmholtz_projection(u, m, g_absence)
  end

end
