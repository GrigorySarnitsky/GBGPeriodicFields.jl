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

  @testset "codegen kernels threaded == serial (bitwise)" begin
    u  = VectorFieldPhysical((x, y, z) -> (sin(x) * cos(y), cos(z), sin(z) + 0.2), grid)
    v  = VectorFieldPhysical((x, y, z) -> (cos(x), sin(2y), cos(z)), grid)
    A  = TensorFieldPhysical{2}((x, y, z) -> [sin(x) cos(y) 0.3; 0.5 sin(z) cos(x); 1.0 cos(z) sin(y)], grid)
    B  = TensorFieldPhysical{2}((x, y, z) -> [cos(x) 0.1 sin(y); sin(z) cos(y) 0.2; 0.7 sin(x) cos(z)], grid)
    sf = ScalarFieldPhysical((x, y, z) -> 2.0 + sin(x), grid)

    @test bitwise(() -> dot(u, v))          # vector inner product (scalar kernel)
    @test bitwise(() -> cross(u, v))        # cross product
    @test bitwise(() -> dot(A, B))          # tensor Frobenius product
    @test bitwise(() -> A * u)              # tensor·vector
    @test bitwise(() -> u * A)              # vector·tensor
    @test bitwise(() -> A * B)              # tensor·tensor
    @test bitwise(() -> transpose(A))       # bare-view permutation (identity-wrap path)
    @test bitwise(() -> sym(A))
    @test bitwise(() -> skew(A))
    @test bitwise(() -> dev(A))
    @test bitwise(() -> norm(u))
    @test bitwise(() -> norm(A))
    @test bitwise(() -> sf * u)             # scalar-field × vector (singleton-axis kernel)
    @test bitwise(() -> u / sf)             # division by a scalar field

    # mul! both branches
    acc_s = 2.0 * (A * u); acc_t = 2.0 * (A * u)
    with_threading(enabled = false) do; mul!(acc_s, A, u, 3.0, 5.0); end
    with_threading(enabled = true)  do; mul!(acc_t, A, u, 3.0, 5.0); end
    @test field_data(acc_s) == field_data(acc_t)                                   # accumulate (β ≠ 0)
    ov_s = VectorFieldPhysical(fill(T(NaN), 32, 31, 30, 3), grid)
    ov_t = VectorFieldPhysical(fill(T(NaN), 32, 31, 30, 3), grid)
    with_threading(enabled = false) do; mul!(ov_s, A, u, 1.0, 0.0); end
    with_threading(enabled = true)  do; mul!(ov_t, A, u, 1.0, 0.0); end
    @test field_data(ov_s) == field_data(ov_t) && !any(isnan, field_data(ov_t))    # overwrite (β = 0)
  end

  @testset "differential operators threaded == serial (bitwise)" begin
    # 40³ so the spectral component arrays (21×40×40 ≈ 34k) clear the cutoff and thread.
    og = Grid3D((40, 40, 40), (2π, 2π, 2π))
    layout = RealFourierLayout()
    function plans_for(physical)
      R = field_tensor_order(physical)
      shape = F.spectral_field_shape(og, layout, Val(R))
      spectral = R == 0 ? ScalarFieldSpectral(zeros(Complex{T}, shape), og) :
                 R == 1 ? VectorFieldSpectral(zeros(Complex{T}, shape), og) :
                          TensorFieldSpectral{R}(zeros(Complex{T}, shape), og)
      return FieldTransformPlans(physical, spectral)
    end
    phi = ScalarFieldPhysical((x, y, z) -> sin(x) * cos(y) + sin(2z), og)
    u = VectorFieldPhysical((x, y, z) -> (sin(x) + cos(y), sin(y) + cos(z), sin(z) + cos(x)), og)
    phis = to_spectral(phi, plans_for(phi)); us = to_spectral(u, plans_for(u))
    m = FieldSpectralMultipliers(phis)

    @test bitwise(() -> gradient(phis, m))                          # scalar → vector
    @test bitwise(() -> laplacian(phis, m))
    @test bitwise(() -> inverse_laplacian(laplacian(phis, m), m))
    @test bitwise(() -> divergence(us, m))
    @test bitwise(() -> curl(us, m))
    @test bitwise(() -> gradient(us, m))                            # vector → tensor
    @test bitwise(() -> helmholtz_projection(us, m))
  end

end
