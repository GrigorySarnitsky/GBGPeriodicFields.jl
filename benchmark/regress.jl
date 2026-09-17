# The canary-judge lane (CLAUDE.md roadmap; PERFORMANCE.md §7 gap 3): the automated
# achieved-TIME regression net the audits cannot provide. One canary per execution MECHANISM —
# not per operation — judged against a frozen per-host baseline with a hard exit code.
#
#   julia --project=benchmark          benchmark/regress.jl cpu  [--freeze]
#   julia --project=benchmark/gpu/cuda benchmark/regress.jl cuda [--freeze]
#   julia --project=benchmark/gpu/rocm benchmark/regress.jl gpu  [--freeze]
#
# The baseline lives in benchmark/baselines/<host>-<backend>[-tN].json and is COMMITTED: an
# intended slowdown refreezes it IN THE SAME COMMIT with the reason (the pass-audit protocol,
# applied to time). Judgement: BenchmarkTools.judge on minimum times, tolerance 25% (≥ 2× the
# documented ~10% jitter) — a :regression on any canary exits nonzero. On the CPU the streaming
# canaries are additionally measured serial-vs-threaded through the with_threading override and
# must satisfy threaded ≤ 1.1 × serial — the alarm the finding-(l) inversion lacked for six
# weeks. (The transfer and binning canaries thread outside the override and skip that check.)
#
# EVERY canary is SYNCHRONIZED. A device launch is asynchronous, so timing a bare thunk measures the
# launch, not the work: before this was added the CUDA `add!` canary read ~12 us for a 128^3 vector
# pass whose 151 MB cannot move in under ~190 us, and the whole GPU lane was judging launch latency.
# `canary_sync()` blocks on the backend after each thunk, and `--selfcheck` proves the wrapper is not
# a no-op by timing a deliberately large device pass with and without it.

using BenchmarkTools
using Statistics: mean
using Random
import KernelAbstractions

const BACKEND = isempty(ARGS) ? "cpu" : ARGS[1]
const FREEZE = "--freeze" in ARGS
const SELFCHECK = "--selfcheck" in ARGS
const USECUDA = BACKEND == "cuda"
const USEGPU = USECUDA || BACKEND in ("gpu", "rocm")

if USECUDA
  @eval using CUDA
  @eval CUDA.allowscalar(false)
  # Refuse to measure on UNIFIED memory. The per-row GC policy reads `CUDA.used_memory()`, which does not
  # count unified allocations, so every row would read as non-allocating and run GC-free; the timings
  # would describe host-device paging rather than the package; and `allowscalar(false)` is not enforced
  # for unified arrays. The setting comes from a `LocalPreferences.toml` ([CUDACore] default_memory),
  # possibly inherited from a stacked environment, so it is checked here rather than assumed absent.
  @eval CUDA.is_unified(CuArray{Float64}(undef, 1)) && error(
    "benchmark harness: CUDA arrays are being allocated in UNIFIED memory (CUDA.jl's `default_memory` " *
    "preference). The harness cannot measure that configuration honestly — run it from an environment " *
    "without the preference. See docs/PERFORMANCE.md finding (as) and §7 gap 9.")
  device_array(a) = CuArray(a)
elseif USEGPU
  @eval using AMDGPU
  @eval AMDGPU.allowscalar(false)
  device_array(a) = ROCArray(a)
else
  device_array(a) = a
end

using GBGPeriodicFields
using GBGPeriodicFields: field_data

const N = 128
const T = Float64
const M_POINTS = 100_000

Random.seed!(2026)
grid = Grid3D((N, N, N), (T(2π), T(2π), T(2π)))
layout = RealFourierLayout()
sshape = field_spectral_shape(grid, layout, Val(0))
vshape = field_spectral_shape(grid, layout, Val(1))

physical_scalar = ScalarFieldPhysical(device_array(rand(T, N, N, N)), grid)
physical_u = VectorFieldPhysical(device_array(rand(T, N, N, N, 3)), grid)
physical_v = VectorFieldPhysical(device_array(rand(T, N, N, N, 3)), grid)
physical_A = TensorFieldPhysical(device_array(rand(T, N, N, N, 3, 3)), grid)
spectral_s = ScalarFieldSpectral(device_array(rand(Complex{T}, sshape)), grid)
spectral_u = VectorFieldSpectral(device_array(rand(Complex{T}, vshape)), grid)
spectral_d = VectorFieldSpectral(device_array(zeros(Complex{T}, vshape)), grid)
tensor_d = TensorFieldPhysical(device_array(zeros(T, N, N, N, 3, 3)), grid)
vector_d = VectorFieldPhysical(device_array(zeros(T, N, N, N, 3)), grid)
kernel = spectral_cutoff(FieldSpectralMultipliers(spectral_s), N ÷ 3)
multipliers = FieldSpectralMultipliers(spectral_s)
plans = FieldTransformPlans(physical_scalar, spectral_s)
points = PointSet(device_array(T(2π) .* rand(T, M_POINTS, 3)))
point_q = ScalarPointValues(device_array(rand(T, M_POINTS)))
point_out = ScalarPointValues(device_array(zeros(T, M_POINTS)))
physical_out = ScalarFieldPhysical(device_array(zeros(T, N, N, N)), grid)

# One canary per mechanism. `streaming = true` marks the ops the CPU serial-vs-threaded
# assertion applies to (they honor the with_threading override).
const CANARIES = [
  ("assign-broadcast add!",      true,  () -> add!(vector_d, physical_u, physical_v)),
  ("fused-operator gradient!",   true,  () -> gradient!(spectral_d, spectral_s, multipliers)),
  ("gated-loop helmholtz!",      true,  () -> helmholtz_projection!(spectral_d, spectral_u, multipliers)),
  ("executor mul!",              true,  () -> mul!(vector_d, physical_A, physical_u)),
  ("executor sym!",              true,  () -> sym!(tensor_d, physical_A)),
  ("convolve!",                  true,  () -> convolve!(spectral_d, spectral_u, kernel)),
  ("tree-reduction inner",       true,  () -> inner(physical_u, physical_v)),
  ("mapped mean(norm,u)",        true,  () -> mean(norm, physical_u)),
  ("fft to_physical!",           false, () -> to_physical!(physical_out, spectral_s, plans)),
  ("transfer gather",            false, () -> interpolate!(point_out, physical_scalar, points)),
  ("transfer scatter",           false, () -> anterpolate!(physical_out, points, point_q)),
  ("binning radial_spectrum",    false, () -> radial_spectrum(spectral_u, multipliers)),
]

baseline_dir = joinpath(@__DIR__, "baselines")
mkpath(baseline_dir)
tag = USECUDA ? "cuda" : USEGPU ? "rocm" : "cpu-t$(Threads.nthreads())"
baseline_path = joinpath(baseline_dir, "$(gethostname())-$(tag).json")

# One handle for the backend every canary runs on; `synchronize` is a cheap no-op on the CPU.
const CANARY_BACKEND = KernelAbstractions.get_backend(field_data(spectral_d))
canary_sync() = KernelAbstractions.synchronize(CANARY_BACKEND)

suite = BenchmarkGroup()
for (name, _, thunk) in CANARIES
  suite[name] = @benchmarkable ($thunk(); canary_sync()) samples = 100 evals = 5 seconds = 3 gcsample = USEGPU
end

# `gcsample = USEGPU` above is the SAFE default, not the intended one. A blanket per-sample GC on a
# device inflates a canary 2–29× and times the collector rather than the mechanism
# (docs/PERFORMANCE.md §4(s)), so the same measured policy `characterize.jl` uses is applied here:
# only a row whose device-pool growth would exhaust the pool within its own trial keeps it. Every
# canary is an in-place mechanism, so in practice none should — but this measures rather than assumes,
# and any row that cannot be probed stays on the safe default.
if USEGPU
  const CANARY_TRIAL_BUDGET = 2 * 2^30
  # Pool-live bytes, same name on both vendors. `CUDA.available_memory` does not exist, so the old
  # spelling threw on every call and the catch-all below silently kept the collector (§4(w)).
  _device_used() = USECUDA ? CUDA.used_memory() : AMDGPU.used_memory()
  _reclaim() = USECUDA ? CUDA.reclaim() : AMDGPU.reclaim()
  kept, failed = String[], String[]
  probe_error = Ref{Any}(nothing)
  for (name, benchmark) in suite
    probe_failed = false
    allocating = try
      warmup(benchmark)
      GC.gc(true); _reclaim()
      before = _device_used()
      GC.enable(false)
      # Bounded by memory with an early exit: the probe runs with the collector off, so a fixed call
      # count can itself exhaust the pool (it did, on `transfer` at 256³ in characterize.jl).
      calls, growth, fastest = 0, 0, Inf
      try
        for _ in 1:8
          trial = run(benchmark; samples = 1, evals = 1, gcsample = false, gctrial = false)
          calls += 1
          fastest = min(fastest, time(minimum(trial)))
          growth = max(0, _device_used() - before)
          growth > 512 * 2^20 && break
        end
      finally
        GC.enable(true)
      end
      per_call = growth / calls
      seconds_per_call = fastest / 1e9
      per_call * (seconds_per_call > 0 ? benchmark.params.seconds / seconds_per_call : Inf) >
        CANARY_TRIAL_BUDGET
    catch e
      # Record the failure instead of hiding it behind the safe default — see benchmarks.jl.
      probe_failed = true
      probe_error[] === nothing && (probe_error[] = e)
      true
    end
    benchmark.params.gcsample = allocating
    allocating && push!(kept, name)
    probe_failed && push!(failed, name)
    GC.gc(true); _reclaim()
  end
  println("canary: per-sample GC kept for $(length(kept)) row(s)",
          isempty(kept) ? "" : ": " * join(sort(kept), ", "))
  if !isempty(failed)
    println("canary: !! gcsample PROBE FAILED on $(length(failed)) of $(length(suite)) row(s) — they ",
            "are timed on the collector, not the mechanism.")
    println("canary: !! first error: ", sprint(showerror, probe_error[]))
  end
end

# A guard for the guard: if `canary_sync()` did not actually block, an asynchronous launch would
# time the same with and without it. Ratio on a device is large (the pass is bandwidth-bound); on the
# CPU the work is synchronous anyway, so the check is skipped rather than given a meaningless bound.
if SELFCHECK
  probe() = add!(vector_d, physical_u, physical_v)
  probe(); canary_sync()
  bare   = minimum(@benchmark probe() samples = 50 evals = 1).time
  synced = minimum(@benchmark (probe(); canary_sync()) samples = 50 evals = 1).time
  println("sync self-check: bare $(BenchmarkTools.prettytime(bare)), ",
          "synchronized $(BenchmarkTools.prettytime(synced)), ratio $(round(synced / bare, digits = 2))×")
  if USEGPU && synced < 2 * bare
    println("SELF-CHECK FAILED — synchronization is not blocking; every device timing below is launch latency")
    exit(3)
  end
  USEGPU || println("  (CPU: work is synchronous, so a ratio near 1 is expected and proves nothing)")
end

println("canary: $(length(CANARIES)) mechanisms, $(N)³ $(T), host $(gethostname()), backend $(tag)")
tune!(suite)
results = run(suite; verbose = false)

exit_code = 0

if FREEZE
  BenchmarkTools.save(baseline_path, results)
  println("baseline frozen -> $(baseline_path)")
else
  if !isfile(baseline_path)
    println("NO BASELINE at $(baseline_path) — run with --freeze first"); exit(2)
  end
  baseline = BenchmarkTools.load(baseline_path)[1]
  println(rpad("canary", 30), rpad("now", 14), rpad("baseline", 14), "judgement")
  for (name, _, _) in CANARIES
    j = judge(minimum(results[name]), minimum(baseline[name]); time_tolerance = 0.25)
    verdict = BenchmarkTools.time(j)
    println(rpad(name, 30), rpad(BenchmarkTools.prettytime(time(minimum(results[name]))), 14),
            rpad(BenchmarkTools.prettytime(time(minimum(baseline[name]))), 14), verdict)
    verdict == :regression && (global exit_code = 1)
  end
end

# The inversion alarm: on CPU, every override-governed streaming canary must not run SLOWER
# threaded than serial (tolerance 1.1×). Skipped on one thread and on devices.
if !USEGPU && Threads.nthreads() > 1
  println("\nserial-vs-threaded (threaded must be ≤ 1.1 × serial):")
  for (name, streaming, thunk) in CANARIES
    streaming || continue
    thunk()                                              # warm
    serial = minimum(with_threading(() -> (@elapsed thunk()); enabled = false) for _ in 1:5)
    threaded = minimum(with_threading(() -> (@elapsed thunk()); enabled = true) for _ in 1:5)
    ok = threaded <= 1.1 * serial
    println(rpad(name, 30), rpad(BenchmarkTools.prettytime(1e9 * serial), 14),
            rpad(BenchmarkTools.prettytime(1e9 * threaded), 14), ok ? "ok" : "INVERSION")
    ok || (global exit_code = 1)
  end
end

println(exit_code == 0 ? "\nCANARY GREEN" : "\nCANARY RED")
exit(exit_code)
