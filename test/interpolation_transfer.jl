# Tests for the grid↔point transfer kernels in src/Interpolation.jl: the Lalescu-spline
# interpolation (gather, W) and anterpolation (scatter, Wᵀ). Oracles independent of the package:
# analytic polynomial reproduction (interior points, so the periodic stencil does not wrap), the
# adjointness identity ⟨W f, q⟩ = ⟨f, Wᵀ q⟩ (holds for ANY field/values), partition-of-unity
# conservation, known closed-form weights (linear at m=0, Catmull–Rom at n=1,m=1, the Lagrange
# cardinal basis for LagrangeSpline), and a bit-for-bit pin to TurTLE's reference coefficients. GPU
# parity lives in test/gpu/suite.jl.

using Test
using GBGPeriodicFields      # exports `dot` (works on the plain value arrays here)
using Random

# Evaluate the per-axis spline weights β_q(t) for all stencil nodes from a scheme's coefficients.
spline_weights(scheme, t) = scheme.coefficients * [t^p for p in 0:size(scheme.coefficients, 2)-1]

@testset "interpolation / anterpolation transfer" begin
  Random.seed!(20260609)

  @testset "spline weights" begin
    # Partition of unity (⇒ conservation) for a range of (n, m), both hierarchies.
    for (n, m) in ((0, 0), (1, 0), (1, 1), (1, 2), (2, 0), (2, 1), (2, 2), (2, 4), (3, 1), (3, 3))
      scheme = LalescuSpline(n, m)
      for t in 0.0:0.1:1.0
        @test sum(spline_weights(scheme, t)) ≈ 1.0 atol = 1e-12
      end
    end
    for n in (0, 1, 2, 3, 4)
      for t in 0.0:0.1:1.0
        @test sum(spline_weights(LagrangeSpline(n), t)) ≈ 1.0 atol = 1e-12
      end
    end

    # n=1, m=1 reproduces the Catmull–Rom basis exactly.
    catmull_rom(t) = [(-0.5t + t^2 - 0.5t^3), (1 - 2.5t^2 + 1.5t^3), (0.5t + 2t^2 - 1.5t^3), (-0.5t^2 + 0.5t^3)]
    for t in 0.0:0.1:1.0
      @test spline_weights(CatmullRom, t) ≈ catmull_rom(t) atol = 1e-12
    end

    # Smooth m=0 is linear interpolation over the two central nodes (offsets 0, 1; index n+1, n+2),
    # independent of n — TurTLE's spline_n? floor, NOT a Lagrange interpolant of the whole stencil.
    for n in (1, 2, 3)
      scheme = LalescuSpline(n, 0)
      for t in 0.0:0.1:1.0
        w = spline_weights(scheme, t)
        @test w[n + 1] ≈ 1 - t atol = 1e-12
        @test w[n + 2] ≈ t atol = 1e-12
        @test sum(abs, w[setdiff(1:length(w), (n + 1, n + 2))]) ≈ 0 atol = 1e-12
      end
    end

    # LagrangeSpline(n) reproduces the Lagrange cardinal basis over the 2n+2 nodes (offsets -n..n+1).
    for n in (1, 2, 3)
      scheme = LagrangeSpline(n)
      offsets = collect(-n:n+1)
      lagrange(t) = [prod((t - offsets[j]) / (offsets[i] - offsets[j]) for j in eachindex(offsets) if j != i)
                     for i in eachindex(offsets)]
      for t in 0.0:0.1:1.0
        @test spline_weights(scheme, t) ≈ lagrange(t) atol = 1e-10
      end
    end

    # Validity: smoothness capped at m ≤ 2n (TurTLE: "no C³ interpolant with a 4-point kernel").
    @test LalescuSpline(1, 2) isa LalescuSpline    # m = 2 = 2n is now valid (TurTLE beta_n1_m2)
    @test_throws ArgumentError LalescuSpline(1, 3)  # m = 3 > 2n = 2
    @test_throws ArgumentError LalescuSpline(0, 1)  # m = 1 > 2n = 0
    @test_throws ArgumentError LalescuSpline(-1)
    @test_throws ArgumentError LagrangeSpline(-1)
  end

  @testset "TurTLE reference coefficients (pin)" begin
    # The smooth weights are pinned bit-for-bit to TurTLE's beta_n{n}_m{m}
    # (cpp/particles/interpolation/spline_n{n}.cpp), transcribed here verbatim (deriv 0).
    turtle = Dict(
      (1, 1) => x -> [x*(x*(-x/2 + 1) - 1/2), x^2*(3x/2 - 5/2) + 1, x*(x*(-3x/2 + 2) + 1/2), x^2*(x/2 - 1/2)],
      (1, 2) => x -> [x*(x*(x*(x*(x - 5/2) + 3/2) + 1/2) - 1/2),
                      x^2*(x*(x*(-3x + 15/2) - 9/2) - 1) + 1,
                      x*(x*(x*(x*(3x - 15/2) + 9/2) + 1/2) + 1/2),
                      x^3*(x*(-x + 5/2) - 3/2)],
      (2, 1) => x -> [x*(x*(x/12 - 1/6) + 1/12), x*(x*(-7x/12 + 5/4) - 2/3), x^2*(4x/3 - 7/3) + 1,
                      x*(x*(-4x/3 + 5/3) + 2/3), x*(x*(7x/12 - 1/2) - 1/12), x^2*(-x/12 + 1/12)])
    for ((n, m), beta) in turtle
      scheme = LalescuSpline(n, m)
      for t in 0.0:0.05:1.0
        @test spline_weights(scheme, t) ≈ beta(t) atol = 1e-12
      end
    end
  end

  for T in (Float64, Float32)
    grid = Grid3D((16, 15, 14), (T(2π), T(2π), T(2π)))
    spacing = T(2π) ./ (16, 15, 14)
    M = 64
    poly_tol = T == Float64 ? 1e-10 : 1e-3
    adj_tol = T == Float64 ? 1e-10 : 1e-3

    @testset "polynomial reproduction, interior points ($T)" begin
      # Points in the central region so the (2n+2)³ stencil never wraps; a low-degree polynomial
      # field is then reproduced exactly (linear/quadratic for Catmull–Rom).
      coords = T(0.3 * 2π) .+ T(0.4 * 2π) .* rand(T, M, 3)
      xs = PointSet(coords)

      linear(x, y, z) = T(0.3) + T(0.7) * x - T(0.4) * y + T(0.2) * z
      values = interpolate(ScalarFieldPhysical(linear, grid), xs)
      @test point_values(values) ≈ [linear(coords[p, :]...) for p in 1:M] rtol = poly_tol

      quadratic(x, y, z) = T(1) + x - T(0.5) * y^2 + T(0.3) * x * z
      vq = interpolate(ScalarFieldPhysical(quadratic, grid), xs)
      @test point_values(vq) ≈ [quadratic(coords[p, :]...) for p in 1:M] rtol = poly_tol

      # Vector field: each component interpolated independently.
      vf = VectorFieldPhysical((x, y, z) -> (linear(x, y, z), -quadratic(x, y, z), T(2) * linear(x, y, z)), grid)
      vv = interpolate(vf, xs)
      @test vv isa VectorPointValues
      for p in 1:M
        @test point_values(vv)[p, :] ≈ [linear(coords[p, :]...), -quadratic(coords[p, :]...), 2 * linear(coords[p, :]...)] rtol = poly_tol
      end

      # The Lagrange hierarchy reproduces higher-degree polynomials (LagrangeSpline(3) ⇒ degree ≤ 7).
      cubic(x, y, z) = T(0.2) + x - T(0.1) * y^3 + T(0.4) * x * y * z
      inner = T(0.4 * 2π) .+ T(0.2 * 2π) .* rand(T, M, 3)
      xs_inner = PointSet(inner)
      vc = interpolate(ScalarFieldPhysical(cubic, grid), xs_inner, LagrangeSpline(3))
      @test point_values(vc) ≈ [cubic(inner[p, :]...) for p in 1:M] rtol = (T == Float64 ? 1e-8 : 1e-2)
    end

    @testset "adjointness ⟨Wf,q⟩ = ⟨f,Wᵀq⟩ ($T)" begin
      # Holds for ANY field and any point values (a property of the linear maps), so use random
      # data over the whole domain (stencils wrap — fine, the identity is exact regardless).
      xs = PointSet(T(2π) .* rand(T, M, 3))
      cases = ((ScalarFieldPhysical(rand(T, 16, 15, 14), grid),                 ScalarPointValues(rand(T, M))),
               (VectorFieldPhysical(rand(T, 16, 15, 14, 3), grid),              VectorPointValues(rand(T, M, 3))),
               (TensorFieldPhysical{2}(rand(T, 16, 15, 14, 3, 3), grid),        TensorPointValues{2}(rand(T, M, 3, 3))))
      for (field, q) in cases
        Wf = interpolate(field, xs)
        Wtq = anterpolate(grid, xs, q)
        @test dot(point_values(Wf), point_values(q)) ≈ dot(field_data(field), field_data(Wtq)) rtol = adj_tol
      end
    end

    @testset "measure-weighted L² adjointness via inner ($T)" begin
      # The measure-consistent adjoint W* satisfies ⟨Wf, q⟩_{L²(points)} = ⟨f, W*q⟩_{L²(grid)}. Both base
      # measures are uniform (counting points, cell-volume grid), so W* = (N/M)·Wᵀ — a scalar rescaling
      # of the conserving counting-transpose anterpolation, no new operation. Equivalently, with the
      # normalized `inner` (decision 18): M·inner(Wf, q) = N·inner(f, Wᵀq) — the raw transpose
      # adjointness above, now stated in the measure structure (closes decision 17/19's "future" L²
      # adjoint, expressible via `inner`).
      N = prod(grid.grid_size)
      xs = PointSet(T(2π) .* rand(T, M, 3))
      cases = ((ScalarFieldPhysical(rand(T, 16, 15, 14), grid),          ScalarPointValues(rand(T, M))),
               (VectorFieldPhysical(rand(T, 16, 15, 14, 3), grid),       VectorPointValues(rand(T, M, 3))),
               (TensorFieldPhysical{2}(rand(T, 16, 15, 14, 3, 3), grid), TensorPointValues{2}(rand(T, M, 3, 3))))
      for (field, q) in cases
        @test isapprox(M * inner(interpolate(field, xs), q),
                       N * inner(field, anterpolate(grid, xs, q)); rtol = adj_tol)
      end
    end

    @testset "conservation and α/β ($T)" begin
      xs = PointSet(T(2π) .* rand(T, M, 3))
      q = ScalarPointValues(rand(T, M))

      deposited = anterpolate(grid, xs, q)
      @test sum(field_data(deposited)) ≈ sum(point_values(q)) rtol = (T == Float64 ? 1e-10 : 1e-4)

      # overwrite (β = 0) must ignore the destination's prior contents (NaN included)
      overwrite = ScalarFieldPhysical(fill(T(NaN), 16, 15, 14), grid)
      anterpolate!(overwrite, xs, q, CatmullRom, T(1), T(0))
      @test all(isfinite, field_data(overwrite))
      @test field_data(overwrite) ≈ field_data(deposited) rtol = (T == Float64 ? 1e-12 : 1e-4)

      # α scaling
      scaled = anterpolate(grid, xs, q)
      anterpolate!(scaled, xs, q, CatmullRom, T(3), T(0))
      @test field_data(scaled) ≈ 3 .* field_data(deposited) rtol = (T == Float64 ? 1e-10 : 1e-3)

      # accumulate (β = 1): deposit twice ⇒ 2× the single deposit
      accumulate = anterpolate(grid, xs, q)
      anterpolate!(accumulate, xs, q, CatmullRom, T(1), T(1))
      @test field_data(accumulate) ≈ 2 .* field_data(deposited) rtol = (T == Float64 ? 1e-10 : 1e-3)
    end

    @testset "periodicity ($T)" begin
      # The interpolant is periodic: evaluating at x and x + L gives the same value.
      field = ScalarFieldPhysical((x, y, z) -> sin(x) + cos(2y) + sin(3z), grid)
      base = T.([1.1, 2.2, 0.7])
      shifted = base .+ T(2π) .* [1, -1, 2]
      @test field(base) ≈ field(shifted) rtol = (T == Float64 ? 1e-12 : 1e-4)
    end
  end

  # Rough / adversarial scenarios: geometry and stencil corners that the random-interior tests
  # above do not exercise. Float64 (these probe logic, not precision); adjointness and conservation
  # are exact identities, so they catch axis/origin/wrap/atomic bugs regardless of "niceness".
  @testset "rough / adversarial scenarios" begin
    adjoint(field, xs, q, scheme) =
      isapprox(dot(point_values(interpolate(field, xs, scheme)), point_values(q)),
               dot(field_data(field), field_data(anterpolate(field_grid(field), xs, q, scheme))); rtol = 1e-9)
    conserves(grid, xs, q, scheme) =
      isapprox(sum(field_data(anterpolate(grid, xs, q, scheme))), sum(point_values(q)); rtol = 1e-9)

    @testset "non-zero origin + strongly anisotropic grid" begin
      # spacings differ by ~400× across axes; origin far from zero and negative on one axis.
      grid = Grid3D((10, 8, 12), (2π, 0.5, 40.0); origin = (-1.3, 7.0, 100.0))
      Δ = (2π / 10, 0.5 / 8, 40.0 / 12)
      origin = (-1.3, 7.0, 100.0)
      M = 50
      # interior points (Catmull–Rom stencil stays in-bounds): origin_d + Δ_d*(1.5 .. N_d-2.5)
      coords = hcat((origin[d] .+ Δ[d] .* (1.5 .+ ((10, 8, 12)[d] - 4) .* rand(M)) for d in 1:3)...)
      xs = PointSet(coords)
      lin(x, y, z) = 0.5 + 0.3x - 1.1y + 0.02z
      v = interpolate(ScalarFieldPhysical(lin, grid), xs)
      @test point_values(v) ≈ [lin(coords[p, :]...) for p in 1:M] rtol = 1e-9   # per-axis origin/spacing correct
      q = ScalarPointValues(rand(M))
      whole = PointSet(hcat((origin[d] .+ ((2π, 0.5, 40.0)[d]) .* rand(M) for d in 1:3)...))
      @test adjoint(ScalarFieldPhysical(rand(10, 8, 12), grid), whole, q, CatmullRom)
      @test conserves(grid, whole, q, CatmullRom)
    end

    @testset "points exactly on grid nodes (t = 0)" begin
      grid = Grid3D((8, 8, 8), (2π, 2π, 2π))
      Δ = 2π / 8
      field = ScalarFieldPhysical((x, y, z) -> sin(x) * cos(y) + sin(z), grid)
      node_index = [(1, 1, 1), (3, 4, 5), (8, 8, 8), (1, 8, 4)]
      coords = [Δ * (idx[d] - 1) for idx in node_index, d in 1:3]
      v = interpolate(field, PointSet(coords))
      @test point_values(v) ≈ [field_data(field)[idx...] for idx in node_index] rtol = 1e-12  # interpolating property
    end

    @testset "stencil wider than the grid (degenerate periodic wrap)" begin
      grid = Grid3D((4, 4, 4), (2π, 2π, 2π))   # n=3 ⇒ 8-node stencil aliases onto 4 nodes
      scheme = LagrangeSpline(3)               # all 8 nodes carry weight (unlike the linear m=0)
      xs = PointSet(2π .* rand(30, 3))
      q = ScalarPointValues(rand(30))
      @test adjoint(ScalarFieldPhysical(rand(4, 4, 4), grid), xs, q, scheme)
      @test conserves(grid, xs, q, scheme)
    end

    @testset "heavy atomic-scatter contention" begin
      grid = Grid3D((8, 8, 8), (2π, 2π, 2π))
      # thousands of points crowded into one cell ⇒ massive atomic accumulation on a few nodes
      coords = 0.25 .* rand(4000, 3)
      xs = PointSet(coords)
      q = ScalarPointValues(rand(4000))
      @test conserves(grid, xs, q, CatmullRom)            # lost atomic updates would break this
      @test adjoint(ScalarFieldPhysical(rand(8, 8, 8), grid), xs, q, CatmullRom)
    end

    @testset "tensor order R = 3" begin
      grid = Grid3D((6, 6, 6), (2π, 2π, 2π))
      xs = PointSet(2π .* rand(20, 3))
      f3 = TensorFieldPhysical{3}(rand(6, 6, 6, 3, 3, 3), grid)
      q3 = TensorPointValues{3}(rand(20, 3, 3, 3))
      @test interpolate(f3, xs) isa TensorPointValues{3}
      @test adjoint(f3, xs, q3, CatmullRom)
      @test conserves(grid, xs, q3, CatmullRom)
    end

    @testset "smooth higher schemes (n,m) = (2,1) and (3,2)" begin
      grid = Grid3D((20, 20, 20), (2π, 2π, 2π))
      Δ = 2π / 20
      M = 40
      coords = Δ .* (4.0 .+ 11.0 .* rand(M, 3))   # interior (stencil up to 8 stays in-bounds)
      xs = PointSet(coords)
      # Both reproduce ≥ cubic: (2,1) reproduces min(2m+1,2n)=3, (3,2) reproduces 5.
      cubic(x, y, z) = 1.0 + x - 0.5y^2 + 0.3x * z - 0.05y^3
      whole = PointSet(2π .* rand(M, 3))
      q = ScalarPointValues(rand(M))
      for scheme in (LalescuSpline(2, 1), LalescuSpline(3, 2))
        vq = interpolate(ScalarFieldPhysical(cubic, grid), xs, scheme)
        @test point_values(vq) ≈ [cubic(coords[p, :]...) for p in 1:M] rtol = 1e-8
        @test adjoint(ScalarFieldPhysical(rand(20, 20, 20), grid), whole, q, scheme)
        @test conserves(grid, whole, q, scheme)
      end
    end

    @testset "single point (M = 1)" begin
      grid = Grid3D((8, 8, 8), (2π, 2π, 2π))
      xs = PointSet(reshape([1.1, 2.2, 0.7], 1, 3))
      @test length(point_values(interpolate(ScalarFieldPhysical((x, y, z) -> sin(x), grid), xs))) == 1
      q = ScalarPointValues([2.5])
      @test sum(field_data(anterpolate(grid, xs, q))) ≈ 2.5 rtol = 1e-12
    end
  end
end


@testset "coverage-axes closure: α = 0, the bang gather, callable vector, guard wiring ($TP)" for TP in (Float64, Float32)
  grid_s = Grid3D((8, 7, 6), (TP(2π), TP(2π), TP(2π)))
  field = VectorFieldPhysical(rand(TP, 8, 7, 6, 3), grid_s)
  rng = MersenneTwister(31)
  P = TP(2π) .* rand(rng, TP, 5, 3)
  points = PointSet(P)
  q = VectorPointValues(rand(rng, TP, 5, 3))

  # α = 0, β ≠ 0: the spline scatter reduces to the pure β-rescale (asserted nowhere before)
  dest = VectorFieldPhysical(rand(TP, 8, 7, 6, 3), grid_s)
  before = copy(field_data(dest))
  anterpolate!(dest, points, q, CatmullRom, TP(0), TP(2))
  @test field_data(dest) == 2 .* before

  # the bang gather called by name, overwriting a dirty output (only the allocating wrapper
  # was ever exercised)
  dirty = VectorPointValues(fill(TP(NaN), 5, 3))
  interpolate!(dirty, field, points, CatmullRom)
  @test point_values(dirty) ≈ point_values(interpolate(field, points, CatmullRom))

  # the callable field(x) on a vector field (was scalar-only)
  @test collect(field(TP.(P[1, :]))) ≈ vec(point_values(interpolate(field, PointSet(P[1:1, :]), CatmullRom)))

  # the npoints-mismatch guards fire through the public verbs (only the internal check had a test)
  mismatched = VectorPointValues(rand(rng, TP, 4, 3))
  @test_throws DimensionMismatch interpolate!(mismatched, field, points, CatmullRom)
  @test_throws DimensionMismatch anterpolate!(dest, points, mismatched, CatmullRom)

  # M = 0: empty gather and scatter are sane (probe-verified, decision 43) and stay pinned
  empty_points = PointSet(zeros(TP, 0, 3))
  @test npoints(interpolate(field, empty_points, CatmullRom)) == 0
  empty_q = VectorPointValues(zeros(TP, 0, 3))
  @test maximum(abs, field_data(anterpolate(grid_s, empty_points, empty_q, CatmullRom))) == 0
end
