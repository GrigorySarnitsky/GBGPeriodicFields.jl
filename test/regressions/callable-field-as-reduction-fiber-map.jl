# DEFECT: a FIELD handed to the fiber-map slot of a mapped reduction — `integral`, `mean`, `maximum`,
# `minimum`, `extrema` — was accepted and RAN. It is the defect `map!`/`map` were fixed for on
# 2026-09-02 (`callable-field-as-fiber-map.jl`), in the five operations that take the same argument and
# were not swept with them. A field in physical representation is callable, so `extrema(s, u)` with a
# scalar field `s` and a vector field `u` type-checked; on the CPU it read each fiber of `u` as a
# POSITION, interpolated `s` there and returned a plausible pair, (-1.93, 2.13) in the probe that found
# it. On an AMD device the same call did not return at all: compiling its kernel segfaulted LLVM.
#
# FOUND: the first exhaustive survey run on ROCm (2026-10-17), whose invocation engine builds
# `extrema(field, field)` from the method table; every device process died at that call. On the CPU
# the survey had built the same call on every run and counted it clean, the result being finite,
# deterministic and well typed. FIXED: the commit that promoted this file.
using Test
using GBGPeriodicFields
using Statistics: mean

@testset "a field is refused in the fiber-map slot of the mapped reductions" begin
  grid = Grid3D((8, 8, 8), (2π, 2π, 2π))
  layout = RealFourierLayout()

  scalar = ScalarFieldPhysical(Array, grid; layout);  field_data(scalar) .= 1.0
  vector = VectorFieldPhysical(Array, grid; layout);  field_data(vector) .= 0.5
  tensor = TensorFieldPhysical(Array, grid; layout);  field_data(tensor) .= 0.25
  spectral = ScalarFieldSpectral(Array, grid; layout)
  point_data = VectorPointValues(fill(0.5, 2, 3))

  # All five, over each tensor order of source: the vector source is the one that used to succeed.
  for reduction in (integral, mean, maximum, minimum, extrema), source in (scalar, vector, tensor)
    @test_throws ArgumentError reduction(scalar, source)
  end

  # The point-value forms share the pass, and the hazard.
  for reduction in (integral, mean, maximum, minimum, extrema)
    @test_throws ArgumentError reduction(scalar, point_data)
  end

  # A field in spectral representation is not callable, but it is refused by the same guard.
  @test_throws ArgumentError maximum(spectral, vector)

  # The refusal must not have cost the ordinary path its meaning or its allocation contract.
  first_component(x) = x[1]
  @test mean(first_component, vector) ≈ 0.5
  @test extrema(first_component, vector) == (0.5, 0.5)
  mean(first_component, vector)                           # warm before measuring
  @test (@allocated mean(first_component, vector)) == 0
end
