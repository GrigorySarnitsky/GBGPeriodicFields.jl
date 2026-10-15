# Decision 101: the argument shapes the positional audit of 2026-10-12 settled. Each assertion states
# the behaviour the new shape promises, against a value the test builds independently.
using Test
using GBGPeriodicFields


@testset "argument shapes of decision 101 ($T)" for T in (Float64, Float32)
  grid = Grid3D((8, 6, 4), T.((2pi, 2pi, 2pi)))
  permuted = RealFourierLayout((3, 1, 2))

  @testset "similar_field and similar_point_values default to the reference's order" begin
    for reference in (ScalarFieldPhysical(Array, grid), VectorFieldSpectral(Array, grid; layout = permuted),
                      TensorFieldPhysical{2}(Array, grid))
      made = similar_field(reference)
      @test typeof(made) === typeof(reference)
      @test field_layout(made) == field_layout(reference)
      @test size(field_data(made)) == size(field_data(reference))
    end
    for reference in (ScalarPointValues(zeros(T, 5)), VectorPointValues(zeros(T, 5, 3)))
      made = similar_point_values(reference)
      @test typeof(made) === typeof(reference)
      @test size(point_values(made)) == size(point_values(reference))
    end
  end

  @testset "anterpolate takes a grid and a layout for every scheme" begin
    points = PointSet(T.(rand(7, 3)) .* T(2pi))
    values = ScalarPointValues(T.(rand(7)))
    reference = ScalarFieldSpectral(Array, grid; layout = permuted)
    for scheme in (CatmullRom, DirectDFT())
      deposited = anterpolate(grid, points, values, scheme; layout = permuted)
      @test field_layout(deposited) == permuted
      @test field_grid(deposited) == grid
    end
    # The default layout is the standard one, except for a NUFFT plan, whose own layout it takes.
    @test field_layout(anterpolate(grid, points, values, DirectDFT())) == RealFourierLayout()
    plan = NUFFT(reference; tolerance = T === Float64 ? 1e-8 : 1.0f-4)
    @test field_layout(anterpolate(grid, points, values, plan)) == permuted
    # The deposit agrees with the in-place form into a field built the old way.
    into = ScalarFieldSpectral(Array, grid; layout = permuted)
    anterpolate!(into, points, values, DirectDFT())
    @test field_data(anterpolate(grid, points, values, DirectDFT(); layout = permuted)) == field_data(into)
  end

  @testset "NUFFT refuses a non-positive window width or shape, and derives them when absent" begin
    reference = ScalarFieldSpectral(Array, grid)
    @test_throws ArgumentError NUFFT(reference; window_width = 0)
    @test_throws ArgumentError NUFFT(reference; window_width = -2)
    @test_throws ArgumentError NUFFT(reference; window_shape = 0)
    @test_throws ArgumentError NUFFT(reference; window_shape = -1.0)
    derived = NUFFT(reference; tolerance = 1e-6)
    @test derived.width == NUFFT(reference; tolerance = 1e-6, window_width = derived.width).width
    @test derived.beta == NUFFT(reference; tolerance = 1e-6, window_shape = derived.beta).beta
  end

  @testset "with_threading needs its mode named, one of three" begin
    @test_throws UndefKeywordError with_threading(() -> 1)
    @test with_threading(() -> 2; mode = :serial) == 2
    @test with_threading(() -> 3; mode = :automatic) == 3
    @test_throws ArgumentError with_threading(() -> 4; mode = :fast)   # decision 103: a symbol mode
  end

  @testset "the sampling constructors take the array family first" begin
    f = (x, y, z) -> sin(x) * cos(y) + z
    sampled = ScalarFieldPhysical(Array, f, grid)
    expected = [f((i - 1) * grid.grid_spacing[1], (j - 1) * grid.grid_spacing[2], (k - 1) * grid.grid_spacing[3])
                for i in 1:8, j in 1:6, k in 1:4]
    @test field_data(sampled) ≈ T.(expected)
    @test_throws MethodError ScalarFieldPhysical(f, grid)
  end
end
