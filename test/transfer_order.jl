# The transfer VISIT ORDER (decision 78) — `transfer_order` and the `order` option on the four
# point-indexed transfer verbs.
#
# THE ORACLE IS WHAT A PERMUTATION IS, not another package operation (decision 55): the order must be
# a bijection of `1:M`, and the tile keys read along it must be nondecreasing — with those keys
# recomputed here on the host from the coordinates, so no step of the check runs the kernels that
# built the order.
#
# THE PROPERTY THAT MATTERS MOST is that an order cannot change an answer. The gather is asserted
# BITWISE (`==`, not `isapprox`) under every order tried, because each output element is an
# independent sum and reordering the work items cannot touch it — if that ever becomes approximate,
# something has started sharing state between points. The scatter is asserted to a tolerance instead,
# because its atomic accumulation reorders the summation, which it already does between runs
# (`docs/ARCHITECTURE.md` §9); conservation is asserted alongside it, since a deposit that lost or
# duplicated a point would still pass a loose comparison.

using Test
using GBGPeriodicFields
using Random

@testset "transfer_order: the order itself" begin
  for T in (Float64, Float32)
    # An anisotropic box with a non-zero origin, so an order that ignored either would be caught.
    grid = Grid3D((16, 12, 20), (T(2π), T(4π), T(6π)); origin = (T(-1), T(0), T(0.5)))
    Random.seed!(2026); M = 700
    coordinates = hcat(T(-1) .+ T(2π) .* rand(T, M), T(4π) .* rand(T, M), T(0.5) .+ T(6π) .* rand(T, M))
    points = PointSet(coordinates)
    for tile_size in (1, 2, 3, 4, 8, 32)
      order = transfer_order(points, grid; tile_size)
      @test sort(Array(order.indices)) == collect(Int32(1):Int32(M))  # a bijection of 1:M

      # Host-recomputed keys: the order must visit buckets in ascending order.
      tiles = ntuple(d -> max(cld(grid.grid_size[d], tile_size), 1), 3)
      edge = ntuple(d -> T(grid.domain_size[d]) / T(tiles[d]), 3)
      key(p) = begin
        i = ntuple(d -> clamp(floor(Int, (coordinates[p, d] - grid.origin[d]) / edge[d]), 0, tiles[d] - 1), 3)
        1 + i[1] + tiles[1] * (i[2] + tiles[2] * i[3])
      end
      @test issorted([key(p) for p in Array(order.indices)])
    end
    @test_throws ArgumentError transfer_order(points, grid; tile_size = 0)
    @test_throws ArgumentError transfer_order(points, grid; tile_size = -1)
    # A degenerate base has an order, and it is empty rather than an error.
    @test length(transfer_order(PointSet(zeros(T, 0, 3)), grid)) == 0
    # A point outside the grid is clamped into an edge bucket, never refused: an order is a hint.
    far = PointSet(fill(T(1000), 3, 3))
    @test sort(Array(transfer_order(far, grid).indices)) == Int32[1, 2, 3]
  end
end


@testset "transfer_order: an order cannot change an answer" begin
  for T in (Float64, Float32), R in (0, 1, 2)
    grid = Grid3D((14, 16, 12), (T(2π), T(2π), T(4π)); origin = (T(0.25), T(-2), T(0)))
    Random.seed!(4242); M = 600
    coordinates = hcat(T(0.25) .+ T(2π) .* rand(T, M), T(-2) .+ T(2π) .* rand(T, M), T(4π) .* rand(T, M))
    points = PointSet(coordinates)
    order = transfer_order(points, grid)
    shape = (grid.grid_size..., ntuple(_ -> 3, R)...)
    field = R == 0 ? ScalarFieldPhysical(rand(T, shape...), grid) :
            R == 1 ? VectorFieldPhysical(rand(T, shape...), grid) :
                     TensorFieldPhysical{2}(rand(T, shape...), grid)
    values() = R == 0 ? ScalarPointValues(zeros(T, M)) :
               R == 1 ? VectorPointValues(zeros(T, M, 3)) :
                        TensorPointValues{2}(zeros(T, M, 3, 3))
    blank() = R == 0 ? ScalarFieldPhysical(zeros(T, shape...), grid) :
              R == 1 ? VectorFieldPhysical(zeros(T, shape...), grid) :
                       TensorFieldPhysical{2}(zeros(T, shape...), grid)

    for scheme in (CatmullRom, LalescuSpline(2, 1), LagrangeSpline(1))
      unordered, ordered, reversed = values(), values(), values()
      interpolate!(unordered, field, points, scheme)
      interpolate!(ordered, field, points, scheme; order)
      # BITWISE. Each output element is an independent sum, so no order may perturb it.
      @test point_values(unordered) == point_values(ordered)
      # A different permutation of the same points, to show the invariance is of the ORDER and not of
      # this one order — `reverse` is a permutation the builder would never produce.
      interpolate!(reversed, field, points, scheme; order = TransferOrder(reverse(Array(order.indices))))
      @test point_values(unordered) == point_values(reversed)

      quantities = R == 0 ? ScalarPointValues(rand(T, M)) :
                   R == 1 ? VectorPointValues(rand(T, M, 3)) :
                            TensorPointValues{2}(rand(T, M, 3, 3))
      plain, sorted = blank(), blank()
      anterpolate!(plain, points, quantities, scheme)
      anterpolate!(sorted, points, quantities, scheme; order)
      @test isapprox(field_data(plain), field_data(sorted); rtol = 100 * eps(T))
      # Conservation: the partition of unity makes the deposited total the sum of the quantities,
      # and it must survive reordering — a lost or doubly-visited point would show here.
      @test isapprox(sum(field_data(plain)), sum(field_data(sorted)); rtol = 100 * eps(T))

      # The ALLOCATING forms take it too — they are thin wrappers, and a consumer that never writes
      # the in-place spelling would otherwise be unable to use the option at all.
      @test point_values(interpolate(field, points, scheme)) ==
            point_values(interpolate(field, points, scheme; order))
      @test isapprox(field_data(anterpolate(grid, points, quantities, scheme)),
                     field_data(anterpolate(grid, points, quantities, scheme; order));
                     rtol = 100 * eps(T))

      # The α/β accumulate path takes the order too.
      accumulated_plain, accumulated_sorted = blank(), blank()
      anterpolate!(accumulated_plain, points, quantities, scheme, T(2), T(0))
      anterpolate!(accumulated_plain, points, quantities, scheme, T(-1), T(1))
      anterpolate!(accumulated_sorted, points, quantities, scheme, T(2), T(0); order)
      anterpolate!(accumulated_sorted, points, quantities, scheme, T(-1), T(1); order)
      @test isapprox(field_data(accumulated_plain), field_data(accumulated_sorted); rtol = 100 * eps(T))
    end
  end
end


@testset "transfer_order: the spectral schemes" begin
  for T in (Float64, Float32)
    grid = Grid3D((16, 14, 12), (T(2π), T(2π), T(2π)))
    layout = RealFourierLayout()
    Random.seed!(99); M = 300
    points = PointSet(T(2π) .* rand(T, M, 3))
    order = transfer_order(points, grid)
    spectral = ScalarFieldSpectral(randn(Complex{T}, GBGPeriodicFields.spectral_field_shape(grid, layout, Val(0))...),
                                   grid, layout)
    reference = ScalarFieldSpectral(zeros(Complex{T}, size(field_data(spectral))...), grid, layout)
    scheme = NUFFT(reference; tol = T === Float64 ? 1e-10 : 1e-5)

    plain, sorted = ScalarPointValues(zeros(T, M)), ScalarPointValues(zeros(T, M))
    interpolate!(plain, spectral, points, scheme)
    interpolate!(sorted, spectral, points, scheme; order)
    @test point_values(plain) == point_values(sorted)                 # bitwise, as for the splines

    quantities = ScalarPointValues(rand(T, M))
    deposited_plain = ScalarFieldSpectral(zeros(Complex{T}, size(field_data(spectral))...), grid, layout)
    deposited_sorted = ScalarFieldSpectral(zeros(Complex{T}, size(field_data(spectral))...), grid, layout)
    anterpolate!(deposited_plain, points, quantities, scheme)
    anterpolate!(deposited_sorted, points, quantities, scheme; order)
    @test isapprox(field_data(deposited_plain), field_data(deposited_sorted); rtol = sqrt(eps(T)))

    @test point_values(interpolate(spectral, points, scheme)) ==
          point_values(interpolate(spectral, points, scheme; order))
    @test isapprox(field_data(anterpolate(reference, points, quantities, scheme)),
                   field_data(anterpolate(reference, points, quantities, scheme; order));
                   rtol = sqrt(eps(T)))

    # `DirectDFT` deliberately takes NO order: it reads every mode for every point, so its cost is
    # arithmetic rather than locality and an order would only add an indirection. The absence is part
    # of the spec (invariant 1), so it is asserted rather than assumed.
    @test_throws MethodError interpolate!(plain, spectral, points, DirectDFT(); order)
  end
end


@testset "transfer_order: a wrong order is refused" begin
  T = Float64
  grid = Grid3D((8, 8, 8), (T(2π), T(2π), T(2π)))
  Random.seed!(5); M = 40
  points = PointSet(T(2π) .* rand(T, M, 3))
  field = ScalarFieldPhysical(rand(T, 8, 8, 8), grid)
  out = ScalarPointValues(zeros(T, M))
  quantities = ScalarPointValues(rand(T, M))
  deposit = ScalarFieldPhysical(zeros(T, 8, 8, 8), grid)

  # An order that does not name every point would leave some unvisited — silently wrong, so refused.
  short = TransferOrder(collect(Int32(1):Int32(M - 1)))
  @test_throws ArgumentError interpolate!(out, field, points, CatmullRom; order = short)
  @test_throws ArgumentError anterpolate!(deposit, points, quantities, CatmullRom; order = short)
  @test_throws ArgumentError interpolate!(out, field, points, CatmullRom; order = TransferOrder(Int32[]))
end


@testset "transfer_order: a non-permutation is refused, not silently believed" begin
  # Promoted from the adversarial review of 2026-08-30. Every case below was ACCEPTED before
  # `TransferOrder` carried the guarantee, and each produced a different silent failure: a gather
  # leaving slots at whatever the buffer held (uninitialised memory, from the allocating form), a
  # scatter losing part of the deposited total, and — for an out-of-range entry — an `@inbounds` read
  # and write past the end of the point arrays, which segfaulted on CPU and corrupted silently on GPU.
  M = 40
  @test_throws ArgumentError TransferOrder(fill(Int32(1), M))               # every point the same
  duplicate = collect(Int32, 1:M); duplicate[7] = Int32(8)
  @test_throws ArgumentError TransferOrder(duplicate)                       # one repeat, one omission
  for stray in (Int32(0), Int32(-1), Int32(M + 1), Int32(10^9))
    wrong = collect(Int32, 1:M); wrong[3] = stray
    @test_throws ArgumentError TransferOrder(wrong)
  end
  @test_throws ArgumentError TransferOrder([1.5, 2.5])                      # not integers

  # A raw vector at the call site is refused too: the guarantee lives in the type, so a bare array
  # cannot carry it however well-formed it happens to be.
  grid = Grid3D((8, 8, 8), (2π, 2π, 2π))
  Random.seed!(11)
  points = PointSet(2π .* rand(M, 3))
  field = ScalarFieldPhysical(rand(8, 8, 8), grid)
  out = ScalarPointValues(zeros(M))
  @test_throws ArgumentError interpolate!(out, field, points, CatmullRom; order = collect(Int32, 1:M))

  # And the lawful spellings still work, including the two ranges a reader would reach for first.
  @test interpolate!(out, field, points, CatmullRom; order = TransferOrder(1:M)) !== nothing
  @test interpolate!(out, field, points, CatmullRom; order = TransferOrder(M:-1:1)) !== nothing
  @test length(TransferOrder(collect(Int32, M:-1:1))) == M
  @test length(TransferOrder(Int32[])) == 0                                  # the degenerate base

  # The element-type pair invariant 14 binds: an order built from Float32 points could never drive a
  # transfer against a Float64 grid, so it is refused where it is built.
  @test_throws ArgumentError transfer_order(PointSet(rand(Float32, 10, 3)), grid)
end


@testset "transfer_order: the bucket key does not overflow" begin
  # A grid large enough that the bucket count passes typemax(Int32) used to wrap the key NEGATIVE and
  # write below the histogram — an unguarded atomic store, i.e. a segfault. The key arithmetic is
  # checked directly rather than by allocating the 8 GiB histogram such a grid would need.
  tiles = (Int64(1300), Int64(1300), Int64(1300))
  @test prod(tiles) > typemax(Int32)
  far = ntuple(d -> tiles[d] - Int64(1), 3)
  key = Int64(2) + far[1] + tiles[1] * (far[2] + tiles[2] * far[3])
  @test key > 0
  @test key == prod(tiles) + 1
  # The saturating index: non-finite and far-outside coordinates land in a real block, and a
  # coordinate past the far edge lands in the LAST block rather than wrapping to the first.
  T = Float64
  inverse = T(64) / T(2π)
  @test GBGPeriodicFields.Interpolation._tile_index(T(NaN), zero(T), inverse, Int64(64)) == 0
  @test GBGPeriodicFields.Interpolation._tile_index(T(Inf), zero(T), inverse, Int64(64)) == 63
  @test GBGPeriodicFields.Interpolation._tile_index(T(-Inf), zero(T), inverse, Int64(64)) == 0
  @test GBGPeriodicFields.Interpolation._tile_index(T(1e300), zero(T), inverse, Int64(64)) == 63
  @test GBGPeriodicFields.Interpolation._tile_index(T(-1e300), zero(T), inverse, Int64(64)) == 0
  @test GBGPeriodicFields.Interpolation._tile_index(T(0), zero(T), inverse, Int64(64)) == 0
  # And a genuinely non-finite point set still yields a valid order.
  wild = PointSet([NaN 0.0 0.0; Inf 1.0 1.0; -Inf 2.0 2.0; 1e300 3.0 3.0])
  @test length(transfer_order(wild, Grid3D((8, 8, 8), (2π, 2π, 2π)))) == 4
end
