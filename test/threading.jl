# CPU threading. The threaded assignment path must be **bitwise-identical** to serial — these
# are non-reducing maps, so each output index is written once from the same fused expression —
# and the gate / cutoff / override must behave. Runs in both lanes: the default single-threaded
# `Pkg.test()` (where `with_threading(enabled=true)` forces the threaded code path to run
# inline, exercising the chunking logic) and a threaded lane (`JULIA_NUM_THREADS>1`, real
# parallelism). See docs/TESTING.md.

using Test
using GBGPeriodicFields
using Base.Broadcast: broadcasted

const F = GBGPeriodicFields.Fields
const T = Float64
const grid = Grid3D((32, 31, 30), (2π, 2π, 2π))     # 29760 elements ≥ the default 2^14 cutoff

# serial vs forced-threaded results of the same field op, compared bitwise
ser(f) = with_threading(enabled = false) do; f(); end
thr(f) = with_threading(enabled = true) do; f(); end
bitwise(f) = field_data(ser(f)) == field_data(thr(f))


@testset "threading.jl" begin

  @testset "config / gate / override" begin
    @test threading_cutoff() == 1 << 14
    @test F._use_threads(1) == false                                          # below cutoff → serial
    @test with_threading(enabled = false) do; F._use_threads(10^9) end == false   # forced serial
    @test with_threading(enabled = true)  do; F._use_threads(10^9) end == true    # forced threaded
    set_threading_cutoff!(64); @test threading_cutoff() == 64; set_threading_cutoff!(1 << 14)
    @test F._THREADING_OVERRIDE[] === nothing                                 # default = auto
    @test_throws ErrorException with_threading(enabled = false) do; error("boom") end
    @test F._THREADING_OVERRIDE[] === nothing                                 # restored after exception
  end

  @testset "_assign! threaded == serial (index styles + singleton axes)" begin
    n = 40
    A3 = rand(n, n, n); B3 = rand(n, n, n)
    A5 = rand(n, n, n, 3, 3); B5 = rand(n, n, n, 3, 3); S5 = rand(n, n, n, 1, 1)
    # materialize! into dest1 (serial); _assign! into dest2 (forced threaded); NaN-prefill so a
    # chunking gap surfaces as a surviving NaN.
    function same(dest1, dest2, makebc)
      fill!(dest1, NaN); fill!(dest2, NaN)
      Base.Broadcast.materialize!(dest1, makebc())
      with_threading(enabled = true) do; F._assign!(dest2, makebc()); end
      return Array(dest1) == Array(dest2) && !any(isnan, dest2)
    end

    @test same(zeros(n, n, n), zeros(n, n, n), () -> broadcasted(+, A3, B3))                 # dense Array
    @test same(view(zeros(n, n, n, 3), :, :, :, 2), view(zeros(n, n, n, 3), :, :, :, 2),     # contiguous (IndexLinear) view
               () -> broadcasted(-, view(A5, :, :, :, 1, 1), view(B5, :, :, :, 1, 1)))
    Da = zeros(n, n, n, 3, 3); Db = zeros(n, n, n, 3, 3)
    @test same(selectdim(selectdim(Da, 4, 2), 4, 3), selectdim(selectdim(Db, 4, 2), 4, 3),   # strided (IndexCartesian) tensor view
               () -> broadcasted(+, selectdim(selectdim(A5, 4, 2), 4, 3), selectdim(selectdim(B5, 4, 2), 4, 3)))
    @test same(zeros(n, n, n, 3, 3), zeros(n, n, n, 3, 3), () -> broadcasted(*, S5, A5))      # singleton operand axes
  end

  @testset "field operations threaded == serial (bitwise)" begin
    a = ScalarFieldPhysical((x, y, z) -> sin(x) * cos(y) + 0.3, grid)
    b = ScalarFieldPhysical((x, y, z) -> cos(z), grid)
    u = VectorFieldPhysical((x, y, z) -> (sin(x), cos(y), sin(z)), grid)
    v = VectorFieldPhysical((x, y, z) -> (cos(x), sin(y), 1.0), grid)
    @test bitwise(() -> a + b)
    @test bitwise(() -> a - b)
    @test bitwise(() -> 2.5 * a)
    @test bitwise(() -> a + 1.5)        # physical constant add (pointwise)
    @test bitwise(() -> u + v)

    d1 = ScalarFieldPhysical(zeros(T, 32, 31, 30), grid); d2 = ScalarFieldPhysical(zeros(T, 32, 31, 30), grid)
    with_threading(enabled = false) do; @. d1 = a - b + 2.0 * a; end
    with_threading(enabled = true)  do; @. d2 = a - b + 2.0 * a; end
    @test field_data(d1) == field_data(d2)
  end

end
