# Equality of sections (decision 91): `==` and `isequal` compare what two sections HOLD. Before this,
# `u == v` fell back to `Base`'s `===` and answered whether they were the same object, so two fields of
# identical values compared unequal. The oracle is the definition, over raw arrays built independently.

using Test
using GBGPeriodicFields

@testset "== and isequal compare fields by value ($T)" for T in (Float64, Float32)
  grid = Grid3D((6, 5, 4), T.((2π, 4π, 2π)))
  other_box = Grid3D((6, 5, 4), T.((2π, 2π, 2π)))
  layout = RealFourierLayout()
  values = rand(T, 6, 5, 4, 3)
  u = VectorFieldPhysical(copy(values), grid, layout)
  v = VectorFieldPhysical(copy(values), grid, layout)
  @test u == v
  @test isequal(u, v)
  @test hash(u) == hash(v)
  # One value changed anywhere makes them unequal.
  w = VectorFieldPhysical(copy(values), grid, layout); field_data(w)[6, 5, 4, 3] += one(T)
  @test u != w
  # Another box, another layout, another tensor order: different fields.
  @test u != VectorFieldPhysical(copy(values), other_box, layout)
  @test u != VectorFieldPhysical(copy(values), grid, RealFourierLayout((2, 1, 3)))
  @test ScalarFieldPhysical(values[:, :, :, 1], grid, layout) != u
  # Signed zeros and NaN follow Julia's arrays: == ignores the sign of zero and NaN equals nothing;
  # isequal is the bit-identical test.
  zero_plus = ScalarFieldPhysical(zeros(T, 6, 5, 4), grid, layout)
  zero_minus = ScalarFieldPhysical(fill(-zero(T), 6, 5, 4), grid, layout)
  @test zero_plus == zero_minus
  @test !isequal(zero_plus, zero_minus)
  with_nan = ScalarFieldPhysical(fill(T(NaN), 6, 5, 4), grid, layout)
  @test with_nan != ScalarFieldPhysical(fill(T(NaN), 6, 5, 4), grid, layout)
  @test isequal(with_nan, ScalarFieldPhysical(fill(T(NaN), 6, 5, 4), grid, layout))
  # Spectral representation compares the same way.
  shape = field_spectral_shape(grid, layout, Val(0))
  coefficients = rand(Complex{T}, shape...)
  @test ScalarFieldSpectral(copy(coefficients), grid, layout) == ScalarFieldSpectral(copy(coefficients), grid, layout)
  # Refused rather than answered: across representations, and across precisions.
  @test_throws ArgumentError u == VectorFieldSpectral(Array, grid, layout)
  @test_throws ArgumentError VectorFieldSpectral(Array, grid, layout) == u
  @test_throws ArgumentError isequal(u, VectorFieldSpectral(Array, grid, layout))
  other_precision = T === Float64 ? Float32 : Float64
  @test_throws ArgumentError u == VectorFieldPhysical(other_precision.(values),
                                                      Grid3D((6, 5, 4), other_precision.((2π, 4π, 2π))), layout)
end


@testset "== and isequal compare point sections by value ($T)" for T in (Float64, Float32)
  positions = rand(T, 7, 3)
  @test PointSet(copy(positions)) == PointSet(copy(positions))
  @test PointSet(copy(positions)) != PointSet(positions .+ one(T))
  @test PointSet(copy(positions)) != PointSet(rand(T, 8, 3))
  @test hash(PointSet(copy(positions))) == hash(PointSet(copy(positions)))
  values = rand(T, 7, 3)
  @test VectorPointValues(copy(values)) == VectorPointValues(copy(values))
  @test isequal(VectorPointValues(copy(values)), VectorPointValues(copy(values)))
  @test VectorPointValues(copy(values)) != VectorPointValues(values .* 2)
  @test ScalarPointValues(values[:, 1]) != VectorPointValues(copy(values))
  other_precision = T === Float64 ? Float32 : Float64
  @test_throws ArgumentError ScalarPointValues(values[:, 1]) == ScalarPointValues(other_precision.(values[:, 1]))
end
