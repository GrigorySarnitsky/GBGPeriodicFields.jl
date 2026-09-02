# DEFECT: a FIELD handed to the fiber-map slot of `map!`/`map` was accepted and RAN. A field in
# physical representation is callable — `f(x)` samples it — so `map!(f, destination, source)` with a
# field `f` type-checked, and what it then computed depended on the source's tensor order. With a
# VECTOR source the fiber is an `SVector{3}`, which the callable reads as a POSITION, so the call
# silently interpolated the field at its own source's values and returned a plausible number
# (0.9999999999999998 for a constant field, in the probe that found it). With a SCALAR source it did
# fail, but as `BoundsError: attempt to access Float64 at index [2]`, naming neither the argument nor
# the mistake. Both families were affected: a point-value fiber at R = 1 is an `SVector{3}` exactly as
# a field's is.
#
# There was nothing to protect — φ maps a fiber to a fiber, while a field is a section — so the fix
# refuses by type rather than removing the callable, which stays.
#
# FOUND: open interface question (2), raised by a doc panel as an API-collision observation and
# measured 2026-09-02, which is what turned "means something the caller probably did not intend" into
# "returns a plausible number from a computation nobody asked for". FIXED: the commit that promoted
# this file.
using Test
using GBGPeriodicFields

@testset "a field is refused in the fiber-map slot of map!/map" begin
  grid = Grid3D((8, 8, 8), (2π, 2π, 2π))
  layout = RealFourierLayout()

  scalar = ScalarFieldPhysical(Array, grid, layout);  field_data(scalar) .= 1.0
  vector = VectorFieldPhysical(Array, grid, layout);  field_data(vector) .= 0.5
  destination = ScalarFieldPhysical(Array, grid, layout)
  spectral = ScalarFieldSpectral(Array, grid, layout)

  point_data = VectorPointValues(fill(0.5, 2, 3))
  point_destination = ScalarPointValues(zeros(2))

  # The vector source is the dangerous one: it used to succeed silently.
  @test_throws ArgumentError map!(scalar, destination, vector)
  @test_throws ArgumentError map!(scalar, destination, scalar)
  @test_throws ArgumentError map!(scalar, destination, vector, 1.0, 0.0)
  @test_throws ArgumentError map(scalar, vector)

  # The point-value family carries the same hazard for the same reason.
  @test_throws ArgumentError map!(scalar, point_destination, point_data)
  @test_throws ArgumentError map(scalar, point_data)

  # A field in spectral representation is not callable, so it would have failed anyway — but with a
  # `MethodError` that named nothing. It is refused by the same guard, for the same message.
  @test_throws ArgumentError map!(spectral, destination, vector)

  # The refusal must not have cost the ordinary path its meaning or its allocation contract.
  double(x) = 2x
  map!(double, destination, scalar)
  @test all(field_data(destination) .== 2.0)
  map!(double, destination, scalar)                       # warm before measuring
  @test (@allocated map!(double, destination, scalar)) == 0

  # And the callable itself is untouched: this is a refusal of one composition, not a removal.
  @test scalar([0.5, 0.5, 0.5]) ≈ 1.0
end
