# Exhaustive characterization run: all op-classes over the default grids for the backend (CPU
# 64³–512³, device 64³–256³ — see CHAR_SIZES below), on the backend chosen by
# ARGS[1] ("cpu" default; "gpu"/"rocm" = AMDGPU; "cuda" = NVIDIA), saving a BenchmarkTools JSON to
# ARGS[2]. Runs **one (size, element-type) at a time** (build → run → free) so peak memory stays
# bounded to a single grid + type — required on a memory-limited GPU, where building all classes for
# both Float64 and Float32 at 256³ exhausts VRAM (on AMD, HIP's pool allocator segfaults rather than
# erroring; CUDA OOMs gracefully — see docs/PERFORMANCE.md §6 gap 5). The GPU path is
# backend-parametric: only the array type, the pool `reclaim()`, and the AMD-only code-object warm
# differ. Thread count is taken from the launch (`-tN`); the thread sweep is driven by
# benchmark/characterize.sh. Results are assembled into the committed benchmark/RESULTS.md by
# benchmark/report.jl. See docs/PERFORMANCE.md §6.
#
# KNOWN FAILURE — a `-t8` CPU lane segfaults on `Enteropia`, and the workaround is to split it.
# A single process at `-t8` dies with `signal 11` inside FFTW's threaded executor (`spawn_apply`,
# reached through FFTW.jl's `spawnloop`) partway through the `reductions` class: four failures in five
# attempts on that host, never once on `Aiporetne`. The package is NOT at fault — `Pkg.test()` passes
# in full under `JULIA_NUM_THREADS=8` — and neither is any single ingredient, since the class alone,
# the operation alone, plan churn alone and the test suite all fail to reproduce it. Run the lane as
# one process per grid instead (`CHAR_SIZES=64`, then 128, 256, 512) and merge the part-archives; the
# parts hold disjoint rows, so the union is what one uncrashed process would have written. Do not
# "fix" it with `set_fft_threads!(1)`: that removes the callback and the crash, but this lane exists
# to measure threaded FFT. Conditions, mechanism and the four clean reproduction attempts are in
# docs/PERFORMANCE.md §4(q); the recipe is in benchmark/README.md.

using BenchmarkTools
using Dates

const BACKEND = isempty(ARGS) ? "cpu" : ARGS[1]
const USECUDA = BACKEND == "cuda"
const USEGPU  = USECUDA || BACKEND in ("gpu", "rocm")
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
  ARRAY_FAMILY = @eval CuArray
  # CUDA JIT-compiles each kernel through the driver and caches SASS in ~/.nv/ComputeCache; there is
  # no host-side comgr stall (the AMD trap below), so no explicit cache warm is needed.
elseif USEGPU
  @eval using AMDGPU
  @eval AMDGPU.allowscalar(false)
  ARRAY_FAMILY = @eval ROCArray
  # Warm the AMD code-object cache (~/.cache/comgr) with one trivial kernel. The FIRST GPU use after
  # a reboot compiles kernels host-side (0% GPU, 100% CPU) and can take minutes — indistinguishable
  # from a hang. Letting it complete here populates the on-disk cache; never kill a cold first run
  # (a killed compile never persists, so the next run restarts cold). See docs/PERFORMANCE.md §6.
  @eval let a = AMDGPU.rand(Float32, 256, 256)
    AMDGPU.synchronize()
    sum(a .* 2.0f0)
    AMDGPU.synchronize()
  end
  println("GPU code-object cache warmed")
  flush(stdout)
else
  ARRAY_FAMILY = Array
end

include(joinpath(@__DIR__, "benchmarks.jl"))

# Both element types and the standard grids by default; one (class, size, type) is built at a time
# (see the loop) to bound memory. `CHAR_SIZES` / `CHAR_TYPES` override the grids / element types.
#
# The default grid set is BACKEND-DEPENDENT, and deliberately so. A CPU host carries the
# beyond-VRAM grids — that is the CPU path's tuning target (decision 37) — so 512³ belongs in its
# default sweep rather than behind an override. It sat behind one until 2026-07-29, which meant the
# band existed in `RESULTS.md` and in no invocation anyone would repeat, so a routine run silently
# DROPPED it from an archive that already carried it. That is exactly what happened.
#
# A device stops at 256³ because 512³ in `Float64` exceeds even a 24 GB card (the heavy classes'
# working sets approach the ceiling, and a HIP OOM segfaults rather than erroring; see
# docs/PERFORMANCE.md §7), and 16 GB cannot hold it at all. A 512³ GPU point is therefore an
# explicit lane: `CHAR_SIZES=512 CHAR_TYPES=Float32 CHAR_SKIP=transfer,reductions`.
const DEFAULT_CHAR_SIZES = USEGPU ? (64, 128, 256) : (64, 128, 256, 512)
const CHAR_SIZES = haskey(ENV, "CHAR_SIZES") ?
  Tuple(parse.(Int, split(ENV["CHAR_SIZES"], ","))) : DEFAULT_CHAR_SIZES
_char_type(s) = s == "Float64" ? Float64 : s == "Float32" ? Float32 :
  error("CHAR_TYPES entry must be Float64 or Float32, got $(repr(s))")
const CHAR_TYPES = haskey(ENV, "CHAR_TYPES") ?
  Tuple(_char_type(strip(s)) for s in split(ENV["CHAR_TYPES"], ",")) : TYPES
BenchmarkTools.DEFAULT_PARAMETERS.seconds = 1.0
# `gcsample` is decided PER ROW on the GPU, by `_apply_gcsample_policy!` below. It used to be set
# globally here, which cost every device row a full `GC.gc()` before every sample and inflated the
# whole GPU corpus 2–29× — the operations were not what was being timed (docs/PERFORMANCE.md §4(s)).
# It cannot simply be dropped: it is what stops an allocating row exhausting the pool.

# The per-row `gcsample` policy lives in benchmarks.jl so the three device entry points
# (characterize.jl and the two runbenchmarks.jl drivers) cannot drift apart. See PERFORMANCE.md §4(s).
# Both vendors expose the POOL's live bytes under the same name, which is the quantity the policy
# wants: it starts at zero, tracks an allocation exactly (16 MiB for a 16 MiB array), returns to zero
# on reclaim, and — unlike a device-wide `total - free` — is blind to other processes on the card.
# `CUDA.available_memory` does NOT exist, so the CUDA path used to throw on every call and the
# probe's catch-all classified the ENTIRE device suite as allocating (PERFORMANCE.md §4(w)).
_device_used_bytes() = USECUDA ? CUDA.used_memory() : AMDGPU.used_memory()
_device_reclaim() = USECUDA ? CUDA.reclaim() : AMDGPU.reclaim()
_apply_gcsample_policy!(suite) =
  apply_gcsample_policy!(suite; device_used = _device_used_bytes, reclaim = _device_reclaim)

# Classes to drop before tuning/running, e.g. `CHAR_SKIP=fft` (a generic escape hatch — empty by
# default; the GPU runs FFT fine, see gap 5).
const CHAR_SKIP = haskey(ENV, "CHAR_SKIP") ? split(ENV["CHAR_SKIP"], ",") : String[]
const RUN_CLASSES = filter(c -> !(c in CHAR_SKIP), collect(CLASSES))

# Stamp the archive with its measurement vintage (commit + sweep date) as BenchmarkGroup tags:
# report.jl prints a per-column vintage line from them, so a column measured at an older commit is
# visible as such instead of silently inheriting the report's HEAD (the 2026-07-22 decision-40
# reductions skew — one host's archive swept hours before a threading feature landed — is the
# motivating incident).
run_commit = try
  readchomp(`git rev-parse --short HEAD`)
catch
  "unknown"
end
# PLATFORM STATE, stamped into the archive alongside the commit. PERFORMANCE.md §4(p) records an
# `fft`-confined 20–50% shift between two sweeps that is reproducible within a session, moves in
# OPPOSITE directions on the two hosts, and cannot be attributed because **no platform state was
# recorded on either side** — a reboot fell between the sweeps and nothing captured what changed.
# That is an instrument gap, not a mystery: without these fields any future occurrence is equally
# unfalsifiable. They are read best-effort, since none of them exists on every platform.
_read_first(path) = try strip(readchomp(path)) catch; "unknown" end
_kernel = try readchomp(`uname -r`) catch; "unknown" end
_microcode = try
  m = match(r"microcode\s*:\s*(\S+)", read("/proc/cpuinfo", String)); m === nothing ? "unknown" : m[1]
catch; "unknown" end
_cpu_model = try
  m = match(r"model name\s*:\s*(.+)", read("/proc/cpuinfo", String)); m === nothing ? "unknown" : strip(m[1])
catch; "unknown" end
_governor = _read_first("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor")
_no_turbo = _read_first("/sys/devices/system/cpu/intel_pstate/no_turbo")
_smt = _read_first("/sys/devices/system/cpu/smt/control")
# A 2 MB-page-backed array and a 4 KB-backed one differ substantially on bandwidth-bound work, so the
# mode matters even when it is off: `madvise` with nothing requesting it means no huge pages at all.
_thp = _read_first("/sys/kernel/mm/transparent_hugepage/enabled")
combined = BenchmarkGroup(["commit=$(run_commit)", "measured=$(Dates.format(Dates.now(), "yyyy-mm-dd"))",
                           "julia=$(VERSION)", "kernel=$(_kernel)", "microcode=$(_microcode)",
                           "cpu=$(_cpu_model)", "governor=$(_governor)", "no_turbo=$(_no_turbo)",
                           "smt=$(_smt)", "thp=$(_thp)", "threads=$(Threads.nthreads())"])
for class in RUN_CLASSES
  combined[class] = BenchmarkGroup()
end

# One (class, size, type) at a time. A 256³ Float64 tensor field is ~1.1 GB; the six classes' fields
# held live together exceed 12 GB of VRAM even for a single element type (a 4-class sweep fit, adding
# reductions + convolution does not). Building a single class at a time bounds the working set to one
# class's fields — a few GB at 256³ — well under the ceiling. Build → tune → run → free per class.
for N in CHAR_SIZES, T in CHAR_TYPES, class in RUN_CLASSES
  println(USECUDA ? "CUDA" : USEGPU ? "ROCm" : "CPU-t$(Threads.nthreads())",
          "  tuning + running $(class) $(T) $(N)^3 ...")
  flush(stdout)
  others = filter(!=(class), collect(CLASSES))
  suite = build_suite(; array_family = ARRAY_FAMILY, types = (T,), sizes = (N,), skip = vcat(CHAR_SKIP, others))
  if USEGPU
    kept, fixed, failed = _apply_gcsample_policy!(suite)
    println("  per-sample GC kept for $(length(kept)) allocating row(s)",
            isempty(kept) ? "" : ": " * join(kept, ", "))
    flush(stdout)
    # Tune only the rows whose parameters the policy did not fix.
    for (class, group) in suite, (key, benchmark) in group
      "$(class)/$(strip(split(key, '|')[1]))" in fixed || tune!(benchmark)
    end
  else
    tune!(suite)
  end
  results = run(suite; verbose = false)
  for key in keys(results[class])
    combined[class][key] = results[class][key]
  end
  suite = nothing
  results = nothing
  GC.gc(true)                         # free this class's fields before the next (bounds peak memory)
  # GC returns device memory to the driver's pool, not the OS, so the pool's high-water mark would
  # accumulate across iterations and 256³ eventually OOMs. reclaim() releases the freed blocks back to
  # the OS so each (class, size, type) starts clean (both vendors pool and expose reclaim()).
  USECUDA ? CUDA.reclaim() : (USEGPU && AMDGPU.reclaim())
end

label = USECUDA ? "CUDA / NVIDIA" : USEGPU ? "ROCm / AMDGPU" : "CPU, $(Threads.nthreads()) thread(s)"
print_results(combined; label = label)
if length(ARGS) ≥ 2
  mkpath(dirname(ARGS[2]))
  BenchmarkTools.save(ARGS[2], combined)
  println("\nsaved -> ", ARGS[2])
end
