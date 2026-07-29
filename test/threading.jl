# CPU threading. The threaded assignment path must be **bitwise-identical** to serial — these
# are non-reducing maps, so each output index is written once from the same fused expression —
# and the gate / cutoff / override must behave. Runs in both lanes: the default single-threaded
# `Pkg.test()` (where `with_threading(enabled=true)` forces the threaded code path to run
# inline, exercising the chunking logic) and a threaded lane (`JULIA_NUM_THREADS>1`, real
# parallelism). See docs/TESTING.md.

using Test
using GBGPeriodicFields
using Base.Broadcast: broadcasted
using Random
import Statistics

const F = GBGPeriodicFields.Fields
const FS = GBGPeriodicFields.FiberSections   # the threading primitives moved here (Phase A)
const DifferentialOperators = GBGPeriodicFields.DifferentialOperators
const Convolution = GBGPeriodicFields.Convolution
import KernelAbstractions as KA              # for the helmholtz dispatch-target guard
const T = Float64
const grid = Grid3D((32, 31, 30), (2π, 2π, 2π))     # 29760 elements ≥ the default 2^14 cutoff

# serial vs forced-threaded results of the same field op, compared bitwise
ser(f) = with_threading(enabled = false) do; f(); end
thr(f) = with_threading(enabled = true) do; f(); end
bitwise(f) = field_data(ser(f)) == field_data(thr(f))

# --- support for the KernelAbstractions reproducibility testset at the foot of this file.
# A digest, so a subprocess can report a whole array over one line of stdout. The definition is
# written once and textually embedded in the subprocess source below, so the two cannot drift.
const KA_DIGEST_SOURCE = """
function ka_digest(a)
  h = 0xcbf29ce484222325                      # FNV-1a, 64-bit
  for byte in reinterpret(UInt8, vec(collect(a)))
    h = (h ⊻ byte) * 0x100000001b3
  end
  return h
end
"""
eval(Meta.parse(KA_DIGEST_SOURCE))

const KA_SEED = 20260721
const KA_POINTS = 4_000

# The inputs are seeded and drawn single-threaded, so every thread count builds the same ones. The
# spectral field is filled directly rather than transformed: FFTW matches its thread count to Julia's,
# so routing through `to_spectral` would put FFTW's own reproducibility inside a test about KA kernels.
const KA_SETUP_SOURCE = """
const T = Float64
ka_grid = Grid3D((32, 32, 32), (2π, 2π, 2π))
ka_shape = spectral_field_shape(ka_grid, RealFourierLayout(), Val(1))
Random.seed!($(KA_SEED))
ka_us = VectorFieldSpectral(rand(Complex{T}, ka_shape), ka_grid)
ka_m = FieldSpectralMultipliers(ka_us)
ka_points = PointSet(T(2π) .* rand(T, $(KA_POINTS), 3))
ka_field = ScalarFieldPhysical(rand(T, 32, 32, 32), ka_grid)
ka_values = ScalarPointValues(rand(T, $(KA_POINTS)))
"""

const KA_PROBE_SOURCE = """
using GBGPeriodicFields, Random
$(KA_DIGEST_SOURCE)
$(KA_SETUP_SOURCE)
println(ka_digest(field_data(helmholtz_projection(ka_us, ka_m))))
println(ka_digest(point_values(interpolate(ka_field, ka_points))))
"""


@testset "threading.jl" begin

  @testset "config / gate / override" begin
    @test threading_cutoff() == 1 << 14
    @test FS._use_threads(1) == false                                          # below cutoff → serial
    @test with_threading(enabled = false) do; FS._use_threads(10^9) end == false   # forced serial
    @test with_threading(enabled = true)  do; FS._use_threads(10^9) end == true    # forced threaded
    set_threading_cutoff!(64); @test threading_cutoff() == 64; set_threading_cutoff!(1 << 14)
    @test FS._THREADING_OVERRIDE[] === nothing                                 # default = auto
    @test_throws ErrorException with_threading(enabled = false) do; error("boom") end
    @test FS._THREADING_OVERRIDE[] === nothing                                 # restored after exception
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
      with_threading(enabled = true) do; FS._assign!(dest2, makebc()); end
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
    @test bitwise(() -> map(det, A))        # map! (decision 48) rides the same slab-threaded executor
    @test bitwise(() -> map(x -> 2x, A))    # tensor → tensor
    @test bitwise(() -> map((a, b) -> a + b, u, v))   # multi-input

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

  @testset "spectral operators (differential + convolution) threaded == serial (bitwise)" begin
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
    @test bitwise(() -> symmetric_gradient(us, m))                  # fused sym∇ (gated kernel pair)
    @test bitwise(() -> laplacian(us, m))                           # vector Δ (coefficientwise)
    As = gradient(us, m)
    @test bitwise(() -> divergence(As, m))                          # tensor2 → vector arity
    @test bitwise(() -> helmholtz_projection(us, m))                # gated CPU loop twin (decision 40)
    # `helmholtz_projection` belongs here since decision 40 gave it a gated CPU loop beside its
    # device kernel: the `with_threading` override `bitwise` toggles now reaches it, so the two
    # lanes really do execute different code. Its cross-thread-count digest is checked below.
    # The `bitwise` assertion above is meaningful only if the CPU call actually reaches that gated
    # loop rather than the KA-on-CPU launch (which ignores the override, so the check would compare a
    # path against itself). A concrete anchor that it does — the class-wide reachability guard is the
    # separate testset below (decision 47).
    let comp = F._vector_component_data
      d = similar_field(us, Val(1))
      target = which(DifferentialOperators._helmholtz_projection_modes!,
        Tuple{KA.CPU, map(typeof, (comp(d, 1), comp(d, 2), comp(d, 3),
          comp(us, 1), comp(us, 2), comp(us, 3),
          m.wavenumber_1, m.wavenumber_2, m.wavenumber_3, nothing, 1.0, 0.0))...})
      @test target.sig.parameters[2] === KA.CPU                    # the gated loop, not the fallback
    end

    # The separable kernel is the second device-kernel / gated-CPU-twin pair (decision 50): the device
    # route is one flat broadcast, the CPU route a hand-written slab loop. Same guard as helmholtz —
    # a CPU call must resolve to the ::CPU twin, or the bitwise check below would compare the
    # broadcast against itself and the twin would be dead code (decision 47's lesson).
    let separable = translation_kernel(phis, m, (0.3, -0.7, 1.1)), d = similar_field(us, Val(1))
      target = which(Convolution._separable_convolution_pass!,
        Tuple{KA.CPU, typeof(field_data(d)), typeof(field_data(us)),
              map(typeof, (separable.factor_1, separable.factor_2, separable.factor_3, 1.0, 0.0))...})
      @test target.sig.parameters[2] === KA.CPU                    # the gated loop, not the broadcast
      @test bitwise(() -> convolve(us, separable))                 # threaded == serial, bitwise
      @test bitwise(() -> convolve(phis, separable))
      sep_s = 2.0 * convolve(us, separable); sep_t = 2.0 * convolve(us, separable)   # equal, initialized
      with_threading(enabled = false) do; convolve!(sep_s, us, separable, 0.5, 2.0); end
      with_threading(enabled = true)  do; convolve!(sep_t, us, separable, 0.5, 2.0); end
      @test field_data(sep_s) == field_data(sep_t)                 # the α/β accumulate branch
    end

    # convolution: convolve! is the same coefficientwise @_assign! map as laplacian! (β = 0 overwrite
    # via the three-argument form; β ≠ 0 accumulate below).
    kernel = spectral_cutoff(phis, m, 5)
    @test bitwise(() -> convolve(phis, kernel))                     # scalar field ⋆ kernel
    @test bitwise(() -> convolve(us, kernel))                       # vector field ⋆ scalar kernel (over the fiber)
    cacc_s = 2.0 * convolve(phis, kernel); cacc_t = 2.0 * convolve(phis, kernel)
    with_threading(enabled = false) do; convolve!(cacc_s, phis, kernel, 3.0, 5.0); end
    with_threading(enabled = true)  do; convolve!(cacc_t, phis, kernel, 3.0, 5.0); end
    @test field_data(cacc_s) == field_data(cacc_t)                  # α/β accumulate branch (β ≠ 0)
  end

  @testset "backend-dispatch pairs stay reachable (the decision-47 class)" begin
    # Every operation with a device kernel AND a gated/blocked CPU twin dispatches through
    # `get_backend(x)`: a `::KernelAbstractions.CPU` method (the threaded CPU body — a gated `@simd`
    # loop or a fixed reduction tree) beside a generic-backend method (the device launch / device
    # reduce). If the `::CPU` method's arity drifts from what the call site passes, it silently stops
    # being a dispatch candidate and CPU execution reverts to the generic path — losing the
    # `with_threading`/cutoff gate and, for reductions, bitwise thread-count-invariance. That is
    # exactly how the gated `helmholtz_projection!` loop went dead for a day (decision 47): decision
    # 42 dropped the kernel's three squared-wavenumber arguments but left the loop's signature stale.
    #
    # Guard the whole class, not the one instance that broke: enumerate every function in the three
    # modules that owns a `::KernelAbstractions.CPU` method, and require each such method's arity to
    # have a matching-arity generic sibling — otherwise the CPU method is unreachable from its
    # dispatcher. The frozen count makes a newly-added pair announce itself (add it, confirm it is
    # guarded) and makes a lost generic twin fail rather than pass silently.
    function _cpu_and_generic_arities(f)
      cpu, generic = Set{Int}(), Set{Int}()
      for method in methods(f)
        parameters = Base.unwrap_unionall(method.sig).parameters
        length(parameters) < 2 && continue
        first_argument = parameters[2]
        first_argument = first_argument isa TypeVar ? first_argument.ub : first_argument
        argument_count = length(parameters) - 1
        first_argument === KA.CPU && push!(cpu, argument_count)
        first_argument === Any && push!(generic, argument_count)
      end
      return cpu, generic
    end

    dispatch_pairs = 0
    for mod in (GBGPeriodicFields.DifferentialOperators, FS, GBGPeriodicFields.Reductions)
      for name in names(mod; all = true)
        isdefined(mod, name) || continue
        f = getfield(mod, name)
        f isa Function || continue
        cpu, generic = _cpu_and_generic_arities(f)
        isempty(cpu) && continue                       # not a backend-dispatch pair
        # every threaded-CPU arity is reachable: a generic sibling of the same arity exists, so the
        # `::CPU` method wins on CPU arrays (more specific first argument) rather than falling through
        @test issubset(cpu, generic)
        dispatch_pairs += 1
      end
    end
    # the five DifferentialOperators `_*_modes!`, the FiberSections `_fiberwise_pass!`, and the five
    # Reductions `_tree_*`/`_reduce_fiber` — eleven pairs. Bump this when a new one is added.
    @test dispatch_pairs == 11
  end

  @testset "kernel sites reproducible across thread counts" begin
    # The `bitwise` helper above cannot reach a KernelAbstractions kernel, so it must not be used
    # for one: `with_threading` sets `_assign!`'s override, and a KA launch never consults it —
    # KA partitions by `Threads.nthreads()` — so both of that helper's lanes execute identical
    # code and the comparison degenerates to `x == x`. Reproducibility is therefore established
    # two ways here: repeats within this process, and one subprocess at a different `-t`.
    # `helmholtz_projection` is included for its cross-`-t` digest: on a CPU array it runs the
    # decision-40 gated loop rather than a KA kernel, and that loop must be thread-count-invariant
    # too (its in-process toggle check lives in the gated-operations testset above).
    #
    # The two `Atomix` scatter-add kernels are EXEMPT from bitwise equality by nature. Floating
    # point addition is not associative, so a nondeterministic accumulation order perturbs the
    # last bits, and the order genuinely varies run to run. Measured on a Ryzen 9800X3D over
    # twelve trials, at both 8 and 16 threads: every trial differed, `anterpolate!` by 2–3 ulp of
    # the field's scale and `radial_spectrum` only inside numerically-zero shells (max |Δ| =
    # 1.4e-47). They are held to a tolerance instead, which still fails a broken scatter — that
    # would differ by O(1), not by an ulp.
    include_string(@__MODULE__, KA_SETUP_SOURCE)   # the same source the subprocess runs

    # disjoint writes, no atomics → bitwise-reproducible repeat to repeat
    projections = [field_data(helmholtz_projection(ka_us, ka_m)) for _ in 1:4]
    @test all(==(projections[1]), projections)
    gathers = [point_values(interpolate(ka_field, ka_points)) for _ in 1:4]
    @test all(==(gathers[1]), gathers)

    # Atomix accumulate → equal to tolerance, not bitwise
    scatters = [field_data(anterpolate(ka_grid, ka_points, ka_values)) for _ in 1:4]
    @test all(s -> isapprox(s, scatters[1], rtol = 1e-10), scatters)
    spectra = [radial_spectrum(ka_us, ka_m)[2] for _ in 1:4]
    @test all(s -> isapprox(s, spectra[1], rtol = 1e-10), spectra)

    # the genuine cross-thread-count comparison the `bitwise` helper cannot make: recompute the two
    # deterministic kernels in a subprocess launched at a different thread count and compare digests
    other_threads = Threads.nthreads() == 1 ? 4 : 1
    probe_output = readchomp(`$(Base.julia_cmd()) --project=$(Base.active_project()) -t$other_threads -e $KA_PROBE_SOURCE`)
    probe_projection, probe_gather = split(probe_output)
    @test probe_projection == string(ka_digest(projections[1]))
    @test probe_gather == string(ka_digest(gathers[1]))
  end

  @testset "reductions: fixed-tree, thread-count-invariant (bitwise)" begin
    # Decision 40: every CPU reduction runs the SAME midpoint tree at every thread count (spawned
    # top levels, serial leaves), so its value is bitwise-identical serial vs threaded AND across
    # thread counts — unlike the tolerance-tested Atomix kernels, these carry an exact contract.
    red_grid = Grid3D((24, 24, 24), (2π, 2π, 2π))
    Random.seed!(KA_SEED + 1)
    red_phi = ScalarFieldPhysical(rand(T, 24, 24, 24), red_grid)
    red_u = VectorFieldPhysical(rand(T, 24, 24, 24, 3), red_grid)
    red_A = TensorFieldPhysical(rand(T, 24, 24, 24, 3, 3), red_grid)
    red_us = VectorFieldSpectral(rand(Complex{T}, F.spectral_field_shape(red_grid, RealFourierLayout(), Val(1))), red_grid)
    red_ops = (() -> inner(red_u, red_u), () -> inner(red_us, red_us), () -> l2norm(red_us),
               () -> integral(red_u), () -> Statistics.mean(red_A), () -> Statistics.mean(det, red_A),
               () -> Statistics.std(red_phi), () -> maximum(red_phi), () -> extrema(red_phi))
    for op in red_ops
      @test (with_threading(enabled = false) do; op() end) == (with_threading(enabled = true) do; op() end)
    end

    # the cross-thread-count half, via the same subprocess mechanism as the KA testset
    reduction_probe = """
    using GBGPeriodicFields, Random, Statistics
    $(KA_DIGEST_SOURCE)
    const T = Float64
    red_grid = Grid3D((24, 24, 24), (T(2π), T(2π), T(2π)))
    Random.seed!($(KA_SEED + 1))
    red_phi = ScalarFieldPhysical(rand(T, 24, 24, 24), red_grid)
    red_u = VectorFieldPhysical(rand(T, 24, 24, 24, 3), red_grid)
    red_A = TensorFieldPhysical(rand(T, 24, 24, 24, 3, 3), red_grid)
    values = Float64[inner(red_u, red_u), integral(red_u)..., Statistics.mean(det, red_A),
                     Statistics.std(red_phi), maximum(red_phi)]
    println(ka_digest(values))
    """
    local_values = Float64[inner(red_u, red_u), integral(red_u)..., Statistics.mean(det, red_A),
                           Statistics.std(red_phi), maximum(red_phi)]
    other = Threads.nthreads() == 1 ? 4 : 1
    red_output = readchomp(`$(Base.julia_cmd()) --project=$(Base.active_project()) -t$other -e $reduction_probe`)
    @test red_output == string(ka_digest(local_values))
  end

end


# ---------------------------------------------------------------------------------------------
# REACHABILITY of the gated CPU twins (decision 53, guard 3).
#
# `which(...)` above answers "if someone called this with these types, what would run?" — it does
# NOT answer "does the public entry point get there?". Those are different, and the difference is
# where decision 47's dead loop lived: the twin stayed a perfectly good dispatch candidate and simply
# lost its only caller. The mutation audit reproduced the class six times over; reordering a branch
# in `convolve!` makes two hand-written twins unreachable while every `which(...)` assertion here
# still passes.
#
# This probes reachability directly. In a SUBPROCESS (so the definitions cannot leak into the rest of
# the suite), each twin is given a more-specific override that throws a distinct sentinel; then the
# PUBLIC operation is called. If the sentinel escapes, the twin is on the live path. If the call
# succeeds, the twin is dead code and the guard fails — which is the whole point.
@testset "gated CPU twins are REACHED from the public API, not merely resolvable" begin
  probe = """
  using GBGPeriodicFields
  import KernelAbstractions as KA
  const M = GBGPeriodicFields
  const C = M.Convolution
  const D = M.DifferentialOperators
  const FS = M.FiberSections

  # A distinct sentinel per twin, so one subprocess can probe them all without interference.
  struct Reached <: Exception; which::String; end

  C._separable_convolution_pass!(::KA.CPU, d, s, f1, f2, f3, a, b) = throw(Reached("separable_convolution"))
  C._separable_combination_pass!(::KA.CPU, d, x, y, f1, f2, f3, a, b) = throw(Reached("separable_combination"))
  C._radial_convolution_pass!(::KA.CPU, d, s, sym, q1, q2, q3, a, b) = throw(Reached("radial_convolution"))
  D._helmholtz_projection_modes!(::KA.CPU, d1, d2, d3, s1, s2, s3, w1, w2, w3, k, a, b) = throw(Reached("helmholtz"))
  # NOTE the exact signature: an override must be at least as specific as the method it replaces, or
  # Julia keeps the real one and the probe reports "NOTHING" — indistinguishable from dead code. The
  # assertion below that every override lives in Main is what tells the two apart.
  FS._fiberwise_pass!(::KA.CPU, f::F, targets::NTuple{NT, Any}, arrays, constants, a, b) where {F, NT} =
    throw(Reached("fiberwise_pass"))

  g = Grid3D((8, 6, 4), (2π, 2π, 2π)); l = RealFourierLayout()
  s0 = ScalarFieldSpectral(zeros(ComplexF64, 5, 6, 4), g, l)
  m = FieldSpectralMultipliers(s0)
  u = VectorFieldSpectral(rand(ComplexF64, 5, 6, 4, 3), g, l)
  b = VectorFieldSpectral(rand(ComplexF64, 5, 6, 4, 3), g, l)
  d = M.Fields.similar_field(u, Val(1))
  sep = translation_kernel(s0, m, (0.3, -0.7, 1.1))
  rad = spectral_cutoff(s0, m, 3.0)
  up = VectorFieldPhysical(rand(8, 6, 4, 3), g)
  vp = VectorFieldPhysical(rand(8, 6, 4, 3), g)

  # Guard the guard: every override must actually own a method, or a signature drift would make this
  # testset report dead code where the truth is a stale probe.
  for (f, nm) in ((C._separable_convolution_pass!, "separable_convolution"),
                  (C._separable_combination_pass!, "separable_combination"),
                  (C._radial_convolution_pass!, "radial_convolution"),
                  (D._helmholtz_projection_modes!, "helmholtz"),
                  (FS._fiberwise_pass!, "fiberwise_pass"))
    any(m -> m.module === Main, methods(f)) || println(nm, "=STALE-PROBE")
  end

  # (public call, the twin it must reach)
  probes = [
    (() -> convolve!(d, u, sep),                     "separable_convolution"),
    (() -> combine!(d, 0.5, u, 0.5, b, sep),         "separable_combination"),
    (() -> convolve!(d, u, rad),                     "radial_convolution"),
    (() -> helmholtz_projection!(d, u, m),           "helmholtz"),
    (() -> cross(up, vp),                            "fiberwise_pass"),
  ]
  for (call, expected) in probes
    reached = try
      call(); "NOTHING"
    catch e
      e isa Reached ? e.which : "OTHER:" * string(typeof(e))
    end
    println(expected, "=", reached)
  end
  """
  output = readchomp(`$(Base.julia_cmd()) --project=$(Base.active_project()) -e $probe`)
  results = Dict(split(line, "=")[1] => split(line, "=")[2]
                 for line in split(output, '\n') if occursin('=', line))
  for twin in ("separable_convolution", "separable_combination", "radial_convolution",
               "helmholtz", "fiberwise_pass")
    haskey(results, twin) || error("probe produced no line for $twin; output was:\n$output")
    results[twin] == twin ||
      @error "a gated CPU twin is NOT reached from its public entry point — it is dead code" twin reached = results[twin]
    @test results[twin] == twin
  end
end
