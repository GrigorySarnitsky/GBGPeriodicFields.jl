# Base-space motion (decision 73): `displace!` — the point set moved along coefficient-weighted
# vector sections, in the universal cover or, with a grid, on the periodic domain proper — and
# `wrap!`, the reduction to the canonical representative in the fundamental domain. The oracle is
# an independent raw-array reference (plain Julia on copies), never another package operation; the
# wrap contract's three subtleties — the folded endpoint, non-finite transparency, and origin
# awareness — are each pinned by name.

using Test
using GBGPeriodicFields
using GBGPeriodicFields: with_threading

# Per-axis minimum-image closeness: the right metric for comparing wrapped representatives, since a
# coordinate a roundoff below the boundary is ~L away in R³ but ~0 away on the torus.
function toroidal_close(a, b, tolerance)
  for axis in 1:3
    extent = (2π, 4π, 6π)[axis]
    for i in axes(a, 1)
      d = abs(a[i, axis] - b[i, axis])
      min(d, extent - d) <= tolerance * extent || return false
    end
  end
  return true
end

@testset "base-space motion (displace!/wrap!)" begin
  for T in (Float64, Float32)
    @testset "$T" begin
      M = 257                                       # deliberately not a power of two
      L = (T(2π), T(4π), T(6π))                     # anisotropic box
      grid = Grid3D((8, 12, 16), L)
      X0 = rand(T, M, 3) .* T(2π)
      sections = [VectorPointValues(randn(T, M, 3)) for _ in 1:3]
      coefficients = (T(0.31), T(-1.2), T(0.07))

      @testset "cover displacement against the raw-array reference" begin
        points = PointSet(copy(X0))
        result = displace!(points, (coefficients[1], sections[1]))
        @test result === points                     # in-place ops return their destination
        reference = X0 .+ coefficients[1] .* point_values(sections[1])
        @test point_coordinates(points) == reference

        # The n-term form is ONE fused traversal; the reference applies the same weighted sum
        # term-by-term on raw arrays. Identical up to the association order of the sum, which the
        # fused pass fixes left-to-right — the same order the reference uses, so equality is exact.
        points = PointSet(copy(X0))
        displace!(points, map(tuple, coefficients, Tuple(sections))...)
        reference = copy(X0)
        for (c, v) in zip(coefficients, sections)
          reference .+= c .* point_values(v)
        end
        @test point_coordinates(points) == reference
      end

      @testset "destination/source form preserves its source" begin
        source = PointSet(copy(X0))
        destination = PointSet(zeros(T, M, 3))
        displace!(destination, source, (coefficients[1], sections[1]), (coefficients[2], sections[2]))
        @test point_coordinates(source) == X0
        reference = X0 .+ coefficients[1] .* point_values(sections[1]) .+
                         coefficients[2] .* point_values(sections[2])
        @test point_coordinates(destination) == reference
        # The aliased call (destination === source) computes the same values.
        aliased = PointSet(copy(X0))
        displace!(aliased, aliased, (coefficients[1], sections[1]), (coefficients[2], sections[2]))
        @test point_coordinates(aliased) == point_coordinates(destination)
      end

      @testset "zero terms copy (and wrap) the source" begin
        source = PointSet(copy(X0))
        destination = PointSet(ones(T, M, 3))
        displace!(destination, source)
        @test point_coordinates(destination) == X0
        far = PointSet(X0 .+ T(10) .* reshape(collect(L), 1, 3))
        displace!(far, far, grid)
        # Compare in the metric of the torus: a representative that lands a roundoff below the
        # boundary sits at ~L in coordinates but at ~0 in toroidal distance.
        @test toroidal_close(point_coordinates(far), X0, T === Float64 ? 1e-12 : 1e-3)
      end

      @testset "torus displacement == cover displacement then wrap!, bitwise" begin
        fused = PointSet(copy(X0))
        unfused = PointSet(copy(X0))
        terms = map(tuple, coefficients, Tuple(sections))
        displace!(fused, grid, terms...)
        displace!(unfused, terms...)
        wrap!(unfused, grid)
        @test point_coordinates(fused) == point_coordinates(unfused)
        for axis in 1:3
          column = view(point_coordinates(fused), :, axis)
          @test all(zero(T) .<= column .< L[axis])
        end
      end

      @testset "wrap! reduces to the fundamental domain" begin
        # Whole-period shifts land back on the starting representative (up to one roundoff-scale
        # difference per mod); in-box coordinates pass through untouched.
        inbox = PointSet(clamp.(copy(X0), T(0.1), T(6)) .* reshape([T(1), T(1), T(1)], 1, 3))
        before = copy(point_coordinates(inbox))
        wrap!(inbox, Grid3D((8, 12, 16), (T(7), T(7), T(7))))
        @test point_coordinates(inbox) == before

        shifted = PointSet(X0 .+ T(3) .* reshape(collect(L), 1, 3))
        wrap!(shifted, grid)
        @test toroidal_close(point_coordinates(shifted), X0, T === Float64 ? 1e-12 : 1e-3)
      end

      @testset "the excluded endpoint is folded" begin
        # Floating-point mod can return the period itself for a coordinate a hair below zero —
        # the very case the fold exists for. Pin the assumption, then the behaviour.
        T === Float64 && @test mod(-1e-20, 2π) === 2π
        tiny = -eps(T) * T(16)
        points = PointSet(T[tiny tiny tiny])
        wrap!(points, grid)
        for axis in 1:3
          x = point_coordinates(points)[1, axis]
          @test zero(T) <= x < L[axis]              # never the excluded endpoint itself
        end
      end

      @testset "non-finite coordinates pass through non-finite" begin
        points = PointSet(T[NaN 1 1; Inf 1 1; -Inf 1 1])
        wrap!(points, grid)
        @test isnan(point_coordinates(points)[1, 1])
        @test !isfinite(point_coordinates(points)[2, 1])
        @test !isfinite(point_coordinates(points)[3, 1])
        @test all(isfinite, point_coordinates(points)[:, 2:3])   # finite columns untouched by the fold
      end

      @testset "the fundamental domain follows the origin" begin
        origin = (T(1), T(-2), T(1//2))
        shifted_grid = Grid3D((8, 12, 16), L; origin = origin)
        points = PointSet(rand(T, M, 3) .* T(40) .- T(20))
        wrap!(points, shifted_grid)
        for axis in 1:3
          column = view(point_coordinates(points), :, axis)
          @test all(origin[axis] .<= column .< origin[axis] + L[axis])
        end
      end

      @testset "sampling is invariant under whole-period shifts (the no-wrap contract)" begin
        field = ScalarFieldPhysical((x, y, z) -> sin(x) * cos(y) + T(0.3) * sin(z), grid)
        inside = PointSet(copy(X0))
        outside = PointSet(X0 .+ T(2) .* reshape(collect(L), 1, 3))
        a = interpolate(field, inside, CatmullRom)
        b = interpolate(field, outside, CatmullRom)
        @test point_values(a) ≈ point_values(b) rtol = (T === Float64 ? 1e-10 : 1e-3)
      end

      @testset "mixed precision and mismatched point counts are refused" begin
        points = PointSet(copy(X0))
        Tother = T === Float64 ? Float32 : Float64
        @test_throws ArgumentError displace!(points, (T(1), VectorPointValues(rand(Tother, M, 3))))
        @test_throws DimensionMismatch displace!(points, (T(1), VectorPointValues(rand(T, M + 1, 3))))
        @test_throws DimensionMismatch displace!(points, PointSet(rand(T, M + 1, 3)))
        @test_throws ArgumentError wrap!(points, Grid3D((8, 12, 16), (Tother(2π), Tother(4π), Tother(6π))))
        @test_throws ArgumentError displace!(points, Grid3D((8, 12, 16), (Tother(2π), Tother(4π), Tother(6π))),
                                             (T(1), sections[1]))
      end

      @testset "threading override does not change the result" begin
        serial = PointSet(copy(X0))
        threaded = PointSet(copy(X0))
        terms = map(tuple, coefficients, Tuple(sections))
        with_threading(() -> displace!(serial, grid, terms...); enabled = false)
        with_threading(() -> displace!(threaded, grid, terms...); enabled = true)
        @test point_coordinates(serial) == point_coordinates(threaded)   # bitwise (decision 38 discipline)
      end
    end
  end
end
