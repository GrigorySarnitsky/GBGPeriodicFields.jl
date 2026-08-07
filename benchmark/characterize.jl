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

using BenchmarkTools
using Dates

const BACKEND = isempty(ARGS) ? "cpu" : ARGS[1]
const USECUDA = BACKEND == "cuda"
const USEGPU  = USECUDA || BACKEND in ("gpu", "rocm")
if USECUDA
  @eval using CUDA
  @eval CUDA.allowscalar(false)
  ARRAY_TYPE = @eval CuArray
  # CUDA JIT-compiles each kernel through the driver and caches SASS in ~/.nv/ComputeCache; there is
  # no host-side comgr stall (the AMD trap below), so no explicit cache warm is needed.
elseif USEGPU
  @eval using AMDGPU
  @eval AMDGPU.allowscalar(false)
  ARRAY_TYPE = @eval ROCArray
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
  ARRAY_TYPE = Array
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

# A row needs the per-sample GC only if it CREATES device arrays fast enough to exhaust the pool
# during its own trial. Host bytes are NOT the signal — a KernelAbstractions launch allocates host
# bytes per call, so every launching row looks allocating by that measure — so the device pool is
# measured directly: with the collector disabled, an allocating row's buffers cannot be reclaimed and
# the pool grows, while an in-place row's pool is exactly flat. Measured at 128³ this reproduces
# invariant 13's documented materializer list on its own (`lpnorm` 144 MiB, `radial_correlation`
# 1310 MiB, the spectral `inner`'s correction planes 13.5 MiB, `materialize_kernel` 146 MiB) and
# gives 0.0 MiB for every in-place operation.
const GCSAMPLE_PROBE_CALLS = 8
# The trigger is the growth PROJECTED over a whole trial, not the bytes per call: a row allocating a
# little but running very often is the same wedge as one allocating a lot rarely, and a flat
# byte threshold cannot see the difference.
const GCSAMPLE_TRIAL_BUDGET = 2 * 2^30   # 2 GiB of pool growth tolerated within one row's trial
# The probe runs with the collector DISABLED, which makes it capable of the very wedge it exists to
# prevent: the first version ran a fixed 8 calls, and `transfer` at 256³ — whose NUFFT allocates
# oversampled work arrays per call — filled a 24 GB pool and hung the sweep (VRAM 99%, GPU activity
# 0%, one core spinning in the allocator). Bound the probe by MEMORY and stop early: once growth is
# unmistakable the answer is already known, so there is no reason to keep allocating to confirm it.
# Peak probe usage is therefore this ceiling plus one call's allocation, never the pool.
const GCSAMPLE_PROBE_CEILING = 512 * 2^20   # 512 MiB of growth is already a decisive answer

_device_used_bytes() = USECUDA ? (CUDA.total_memory() - CUDA.available_memory()) :
                                 AMDGPU.used_memory()

"""
    _apply_gcsample_policy!(suite) -> Vector{String}

Set `gcsample` per benchmark from a measured device-pool probe, and return the rows that kept it.

Each row is warmed up (so compilation is not measured), then run `GCSAMPLE_PROBE_CALLS` times with
the collector disabled while the device pool is watched. The growth is projected over the row's trial
budget from its own per-call time; a row projected to exceed `GCSAMPLE_TRIAL_BUDGET` keeps the
per-sample GC, and every other row — the whole in-place surface — runs without it and is therefore
timed on the operation rather than on the collector (docs/PERFORMANCE.md §4(s)).

Any failure to probe leaves the row on the safe setting, so the fail-safe direction is preserved:
an unclassifiable row behaves exactly as it did before this policy existed.
"""
function _apply_gcsample_policy!(suite)
  kept = String[]
  for (class, group) in suite, (key, benchmark) in group
    allocating = try
      warmup(benchmark)
      GC.gc(true)
      USECUDA ? CUDA.reclaim() : AMDGPU.reclaim()
      before = _device_used_bytes()
      GC.enable(false)
      calls, growth, fastest = 0, 0, Inf
      try
        for _ in 1:GCSAMPLE_PROBE_CALLS
          trial = run(benchmark; samples = 1, evals = 1, gcsample = false, gctrial = false)
          calls += 1
          fastest = min(fastest, time(minimum(trial)))
          growth = max(0, _device_used_bytes() - before)
          growth > GCSAMPLE_PROBE_CEILING && break   # decisive already — stop before filling the pool
        end
      finally
        GC.enable(true)
      end
      growth_per_call = growth / calls
      seconds_per_call = fastest / 1e9
      calls_per_trial = seconds_per_call > 0 ?
        benchmark.params.seconds / seconds_per_call : Inf
      growth_per_call * calls_per_trial > GCSAMPLE_TRIAL_BUDGET
    catch
      true                             # unclassifiable ⇒ keep the old, safe behaviour
    end
    benchmark.params.gcsample = allocating
    allocating && push!(kept, "$(class)/$(strip(split(key, '|')[1]))")
    GC.gc(true)
    USECUDA ? CUDA.reclaim() : AMDGPU.reclaim()
  end
  return kept
end

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
combined = BenchmarkGroup(["commit=$(run_commit)", "measured=$(Dates.format(Dates.now(), "yyyy-mm-dd"))"])
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
  suite = build_suite(; array_type = ARRAY_TYPE, types = (T,), sizes = (N,), skip = vcat(CHAR_SKIP, others))
  if USEGPU
    kept = _apply_gcsample_policy!(suite)
    println("  per-sample GC kept for $(length(kept)) allocating row(s)",
            isempty(kept) ? "" : ": " * join(kept, ", "))
    flush(stdout)
  end
  tune!(suite)
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
