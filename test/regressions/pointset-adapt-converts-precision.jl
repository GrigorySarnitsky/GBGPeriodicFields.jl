# DEFECT: `adapt!(destination::PointSet, source::PointSet)` checked the point count and nothing else, so
# a `Float64` source written into a `Float32` point set went through `copyto!` and was ROUNDED to
# `Float32` — a silent precision conversion, the one thing `adapt!`'s docstring ("precision is not
# converted here") and invariant 14 forbid. The field and point-value methods never had it: their
# signatures tied the two element types together.
#
# FOUND: 2026-09-28, while making `adapt!` refuse every mismatch with a reason (decision 91), by
# trying each mismatch against each method. FIXED: the commit that promoted this file.
using Test
using GBGPeriodicFields

@testset "adapt! refuses to convert a point set's precision" begin
  destination = PointSet(zeros(Float32, 4, 3))
  source = PointSet(rand(Float64, 4, 3))
  @test_throws ArgumentError adapt!(destination, source)
  @test all(iszero, point_positions(destination))            # nothing was written
end
