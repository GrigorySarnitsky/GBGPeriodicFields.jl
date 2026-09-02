# Tests for src/Points.jl: the point data types of the off-grid transfer layer —
# construction and shape validation, accessors, tensor order, point counts, and the
# npoints-match compatibility check, across Float64 and Float32. (The interpolation /
# anterpolation transfer kernels are not implemented yet, so there is nothing else to test.)

using Test
using GBGPeriodicFields

# The internal compatibility helper is reached through the submodule.
const I = GBGPeriodicFields.Points

@testset "Interpolation types" begin
  for T in (Float64, Float32)
    M = 5

    @testset "construction + accessors ($T)" begin
      coordinates = reshape(collect(T, 1:(3M)), M, 3)
      point_set = PointSet(coordinates)
      @test npoints(point_set) == M
      @test point_positions(point_set) === coordinates
      @test eltype(point_positions(point_set)) == T

      scalar_values = ScalarPointValues(rand(T, M))
      vector_values = VectorPointValues(rand(T, M, 3))
      tensor_values = TensorPointValues(rand(T, M, 3, 3))

      @test point_value_tensor_order(scalar_values) == 0
      @test point_value_tensor_order(vector_values) == 1
      @test point_value_tensor_order(tensor_values) == 2
      @test tensor_values isa TensorPointValues{2}
      @test TensorPointValues{2}(rand(T, M, 3, 3)) isa TensorPointValues{2}

      @test npoints(scalar_values) == M
      @test npoints(vector_values) == M
      @test npoints(tensor_values) == M
      @test size(point_values(scalar_values)) == (M,)
      @test size(point_values(vector_values)) == (M, 3)
      @test size(point_values(tensor_values)) == (M, 3, 3)

      @test scalar_values isa AbstractPointValues{T, 0}
      @test vector_values isa AbstractPointValues{T, 1}
      @test tensor_values isa AbstractPointValues{T, 2}
    end

    @testset "Point alias ($T)" begin
      p = Point{T}(one(T), zero(T), -one(T))
      @test p isa Point{T}
      @test length(p) == 3
      @test eltype(p) == T
    end

    @testset "shape validation ($T)" begin
      @test_throws DimensionMismatch PointSet(rand(T, M, 2))          # not (M, 3)
      @test_throws DimensionMismatch VectorPointValues(rand(T, M, 2)) # not (M, 3)
      @test_throws DimensionMismatch TensorPointValues{2}(rand(T, M, 3))    # wrong fiber shape
      @test_throws DimensionMismatch TensorPointValues{2}(rand(T, M, 3, 2)) # wrong fiber shape
    end

    @testset "npoints-match compatibility ($T)" begin
      point_set = PointSet(rand(T, M, 3))
      vector_values = VectorPointValues(rand(T, M, 3))
      @test I._check_npoints_match(point_set, vector_values) === nothing

      mismatched = VectorPointValues(rand(T, M + 1, 3))
      @test_throws DimensionMismatch I._check_npoints_match(point_set, mismatched)
    end
  end
end
