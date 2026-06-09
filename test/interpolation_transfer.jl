# Tests for the grid↔point transfer kernels in src/Interpolation.jl: the Lalescu-spline
# interpolation (gather, W) and anterpolation (scatter, Wᵀ). Oracles independent of the package:
# analytic polynomial reproduction (interior points, so the periodic stencil does not wrap), the
# adjointness identity ⟨W f, q⟩ = ⟨f, Wᵀ q⟩ (holds for ANY field/values), partition-of-unity
# conservation, and known closed-form weights (Lagrange at m=0, Catmull–Rom at n=1,m=1). GPU parity
# lives in test/gpu/suite.jl.

using Test
using GBGPeriodicFields      # exports `dot` (works on the plain value arrays here)
using Random

# Evaluate the per-axis spline weights β_q(t) for all stencil nodes from a scheme's coefficients.
spline_weights(scheme, t) = scheme.coefficients * [t^p for p in 0:size(scheme.coefficients, 2)-1]

@testset "interpolation / anterpolation transfer" begin
  Random.seed!(20260609)

  @testset "spline weights" begin
    # Partition of unity (⇒ conservation) for a range of (n, m).
    for (n, m) in ((0, 0), (1, 0), (1, 1), (2, 0), (2, 1), (2, 2), (3, 1), (3, 3))
      scheme = LalescuSpline(n, m)
      for t in 0.0:0.1:1.0
        @test sum(spline_weights(scheme, t)) ≈ 1.0 atol = 1e-12
      end
    end

    # n=1, m=1 reproduces the Catmull–Rom basis exactly.
    catmull_rom(t) = [(-0.5t + t^2 - 0.5t^3), (1 - 2.5t^2 + 1.5t^3), (0.5t + 2t^2 - 1.5t^3), (-0.5t^2 + 0.5t^3)]
    for t in 0.0:0.1:1.0
      @test spline_weights(CatmullRom, t) ≈ catmull_rom(t) atol = 1e-12
    end

    # m=0 reproduces the Lagrange basis over the 2n+2 nodes (offsets -n..n+1).
    for n in (1, 2, 3)
      scheme = LalescuSpline(n, 0)
      offsets = collect(-n:n+1)
      lagrange(t) = [prod((t - offsets[j]) / (offsets[i] - offsets[j]) for j in eachindex(offsets) if j != i)
                     for i in eachindex(offsets)]
      for t in 0.0:0.1:1.0
        @test spline_weights(scheme, t) ≈ lagrange(t) atol = 1e-10
      end
    end

    @test_throws ArgumentError LalescuSpline(1, 2)   # m > n is rejected
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

      # Higher-order Lagrange reproduces higher-degree polynomials (n=3 ⇒ degree ≤ 7).
      cubic(x, y, z) = T(0.2) + x - T(0.1) * y^3 + T(0.4) * x * y * z
      inner = T(0.4 * 2π) .+ T(0.2 * 2π) .* rand(T, M, 3)
      xs_inner = PointSet(inner)
      vc = interpolate(ScalarFieldPhysical(cubic, grid), xs_inner, LalescuSpline(3, 0))
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
end
