# Property-based ("fuzz") tests: algebraic laws that hold for ANY input, checked on RANDOM fields,
# point-values, and kernels over several trials. These complement the analytic-oracle tests elsewhere
# — a formula correct for sin(x) can still hide an index/sign swap that random data exposes — and the
# operator structural identities on random band-limited fields in adjointness.jl. Float64 (these probe
# formula logic, not precision; element-type preservation is eltype_genericity.jl's job).

using Test
using GBGPeriodicFields
using GBGPeriodicFields: field_data
using Random
using Statistics: mean

@testset "randomized property tests" begin
  Random.seed!(20260611)
  grid = Grid3D((6, 5, 4), (2π, 2π, 2π))                 # small, mixed parity (even, odd, even)
  layout = RealFourierLayout()
  gs = grid.grid_size
  rtol = 1e-10
  same(x, y) = isapprox(field_data(x), field_data(y); rtol = rtol, atol = 1e-12)
  rs() = ScalarFieldPhysical(randn(gs...), grid)
  rv() = VectorFieldPhysical(randn(gs..., 3), grid)
  rt() = TensorFieldPhysical{2}(randn(gs..., 3, 3), grid)
  rsf() = ScalarFieldPhysical(rand(gs...) .+ 2, grid)    # in [2,3] ⇒ safe for division

  for trial in 1:3
    @testset "vector-space laws ($trial)" begin
      a, b, c = rs(), rs(), rs()
      α, β = randn(), randn()
      @test same(a + b, b + a)
      @test same((a + b) + c, a + (b + c))
      @test same(α * (a + b), α * a + α * b)
      @test same((α + β) * a, α * a + β * a)
      @test same(a - b, a + (-1.0) * b)
      u, v = rv(), rv(); sf = rsf()
      @test same(u + v, v + u)
      @test same(sf * (u + v), sf * u + sf * v)            # scalar-field distributivity
      @test same(sf * (u / sf), u)                         # division by a scalar field round-trips
    end

    @testset "contractions and products ($trial)" begin
      u, v = rv(), rv()
      A, B = rt(), rt()
      @test same(dot(u, v), dot(v, u))                                       # dot symmetric
      @test same(cross(u, v), (-1.0) * cross(v, u))                          # cross anti-symmetric
      @test maximum(abs, field_data(dot(u, cross(u, v)))) < 1e-10            # u ⟂ (u × v)
      @test maximum(abs, field_data(cross(u, u))) < 1e-12                    # u × u = 0
      @test same(A * (u + v), A * u + A * v)                                 # tensor·vector linear
      @test same((A + B) * u, A * u + B * u)
      @test same((A * B) * u, A * (B * u))                                   # linear maps compose
      @test same(transpose(A) * u, u * A)                                    # Aᵀu = uA
      @test same(dot(A, B), dot(B, A))                                       # Frobenius symmetric
    end

    @testset "transpose / sym / skew / dev ($trial)" begin
      A = rt()
      @test same(transpose(transpose(A)), A)                                 # involution
      @test same(sym(A) + skew(A), A)                                        # symmetric + skew = A
      @test same(transpose(sym(A)), sym(A))                                  # sym is symmetric
      @test same(transpose(skew(A)), (-1.0) * skew(A))                       # skew is anti-symmetric
      d = field_data(dev(A))
      trace = d[:, :, :, 1, 1] .+ d[:, :, :, 2, 2] .+ d[:, :, :, 3, 3]
      @test maximum(abs, trace) < 1e-10                                      # dev is traceless
    end

    @testset "norms ($trial)" begin
      u = rv(); α = randn()
      @test isapprox(field_data(norm(u)) .^ 2, field_data(dot(u, u)); rtol = rtol)   # |u|² = u·u
      @test same(norm(α * u), abs(α) * norm(u))                                       # |αu| = |α||u|
    end

    @testset "reduction laws ($trial)" begin
      f, g, h = rs(), rs(), rs()
      α = randn()
      @test inner(f, g) ≈ inner(g, f) rtol = rtol                            # symmetric
      @test inner(f, f) ≥ 0                                                   # positive
      @test l2norm(f) ≈ sqrt(inner(f, f)) rtol = rtol
      @test inner(α * f, g) ≈ α * inner(f, g) rtol = rtol                    # linear
      @test inner(f + g, h) ≈ inner(f, h) + inner(g, h) rtol = rtol
      @test inner(f, g)^2 ≤ inner(f, f) * inner(g, g) + 1e-10                # Cauchy–Schwarz
      @test mean(f + g) ≈ mean(f) + mean(g) rtol = rtol                      # mean additive
      @test integral(f) ≈ prod(grid.domain_size) * mean(f) rtol = rtol      # extensive = |Ω|·intensive
    end
  end

  @testset "spectral: convolution bilinearity + operator identities (random band-limited)" begin
    tospec(phys) = (R = field_tensor_order(phys);
                    shape = spectral_field_shape(grid, layout, Val(R));
                    spec0 = R == 0 ? ScalarFieldSpectral(zeros(ComplexF64, shape), grid) :
                            R == 1 ? VectorFieldSpectral(zeros(ComplexF64, shape), grid) :
                                     TensorFieldSpectral{R}(zeros(ComplexF64, shape), grid);
                    to_spectral(phys, FieldTransformPlans(phys, spec0)))
    f1, f2 = tospec(rs()), tospec(rs())
    g1, g2 = tospec(rs()), tospec(rs())                                      # arbitrary scalar kernels
    @test same(convolve(f1 + f2, g1), convolve(f1, g1) + convolve(f2, g1))   # bilinear in the field
    @test same(convolve(g1, g2), convolve(g2, g1))                          # kernel composition commutes
    @test same(convolve(2.0 * f1, g1), 2.0 * convolve(f1, g1))              # homogeneous

    u = tospec(rv()); φ = tospec(rs())
    m = FieldSpectralMultipliers(φ)
    @test maximum(abs, field_data(divergence(curl(u, m), m))) < 1e-8        # div(curl u) = 0
    @test maximum(abs, field_data(curl(gradient(φ, m), m))) < 1e-8          # curl(grad φ) = 0
  end

  @testset "point-values algebra laws (random)" begin
    M = 20
    u1, u2 = VectorPointValues(randn(M, 3)), VectorPointValues(randn(M, 3))
    Ap = TensorPointValues{2}(randn(M, 3, 3))
    pvsame(x, y) = isapprox(point_values(x), point_values(y); rtol = rtol, atol = 1e-12)
    @test pvsame(u1 + u2, u2 + u1)
    @test pvsame(sym(Ap) + skew(Ap), Ap)
    @test isapprox(point_values(dot(u1, u2)), point_values(dot(u2, u1)); rtol = rtol)
    @test inner(u1, u2) ≈ inner(u2, u1) rtol = rtol
    @test inner(u1, u1) ≥ 0
  end
end
