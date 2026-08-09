# Benchmark suite for GBGPeriodicFields — a sibling of test/. NOT part of Pkg.test() (opt-in, like
# the GPU tests). `build_suite(; array_type)` parameterises allocation by the device array type, so
# the same suite runs on CPU (`Array`, default) and GPU (`ROCArray`/`CuArray`); see the runners in
# benchmark/runbenchmarks.jl and benchmark/gpu/<backend>/runbenchmarks.jl. Coverage and methodology
# are documented in docs/PERFORMANCE.md.
#
# (Define `const SUITE = build_suite()` here to opt into the PkgBenchmark/AirspeedVelocity
# convention later; omitted for now so the GPU runner does not build a CPU suite on include.)

using GBGPeriodicFields
using BenchmarkTools
using Random
using Statistics: mean, cov, var, std # extended on sections in Reductions (not re-exported)
using KernelAbstractions: synchronize, get_backend
import FFTW                 # the MEASURE planner flag for the CPU fft twins (fft.jl)

Random.seed!(20260609)

include(joinpath(@__DIR__, "harness.jl"))
include(joinpath(@__DIR__, "fft.jl"))
include(joinpath(@__DIR__, "algebra.jl"))
include(joinpath(@__DIR__, "operators.jl"))
include(joinpath(@__DIR__, "convolution.jl"))
include(joinpath(@__DIR__, "transfer.jl"))
include(joinpath(@__DIR__, "reductions.jl"))

const CLASSES = ("fft", "algebra", "operators", "convolution", "transfer", "reductions")

# `skip` drops whole classes before any of their fields/plans are built — required for the GPU
# sweep, where merely *building* the fft class creates rocFFT plans (the gfx103x stall point); see
# characterize.jl and docs/PERFORMANCE.md §6 gap 5.
function build_suite(; array_type = Array, types = TYPES, sizes = SIZES, skip = String[])
  suite = BenchmarkGroup()
  want(class) = !(class in skip)
  for class in CLASSES
    want(class) && (suite[class] = BenchmarkGroup())
  end
  for T in types, N in sizes
    grid = make_grid(T, N)
    tag = string(T, " ", N, "^3")
    want("fft")        && add_fft!(suite["fft"], array_type, T, grid, tag)
    want("algebra")    && add_algebra!(suite["algebra"], array_type, T, grid, tag)
    want("operators")  && add_operators!(suite["operators"], array_type, T, grid, tag)
    want("convolution") && add_convolution!(suite["convolution"], array_type, T, grid, tag)
    want("transfer")   && add_transfer!(suite["transfer"], array_type, T, grid, tag)
    want("reductions") && add_reductions!(suite["reductions"], array_type, T, grid, tag)
  end
  return suite
end

# Print a minimum-time (+ allocations) table per class, sorted by key.
function print_results(results; label = "")
  for class in CLASSES
    println("\n## ", class, isempty(label) ? "" : "  ($label)")
    for key in sort(collect(keys(results[class])))
      estimate = minimum(results[class][key])
      println(rpad(key, 38), lpad(BenchmarkTools.prettytime(time(estimate)), 12),
              lpad(string(allocs(estimate)), 9), " allocs")
    end
  end
end


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

# NOTE: the device hooks are INJECTED by the caller (`device_used`, `reclaim`) rather than resolved
# here, because benchmarks.jl is backend-agnostic — it is included by the CPU driver too, where
# neither CUDA nor AMDGPU is loaded.

# An allocating row does not have to be timed with the collector in its loop either. Its per-call
# growth is already measured, so instead cap the SAMPLE COUNT to keep the pool bounded and run it
# GC-free like everything else: `samples = budget / growth_per_call`, evaluated once each, with the
# collector run after the row rather than inside it. This is what lets the allocating transforms —
# the whole device `fft` column — be timed on the transform instead of on the collector.
const GCSAMPLE_ROW_BUDGET = 4 * 2^30      # 4 GiB of pool growth tolerated within one capped row
const GCSAMPLE_MIN_SAMPLES = 5            # below this a minimum is not worth reporting

"""
    apply_gcsample_policy!(suite; device_used, reclaim) -> (kept, fixed)

Choose each benchmark's memory discipline from a measured device-pool probe. Returns the rows that
kept the per-sample GC and the set of rows whose parameters are now deliberate and must not be tuned.

Each row is warmed up (so compilation is not measured), then run one call at a time with the
collector disabled while the device pool is watched, stopping as soon as growth passes
`GCSAMPLE_PROBE_CEILING` — the probe is bounded by memory rather than by a call count, because it
runs GC-free and a fixed count can itself exhaust the pool. The growth is projected over the row's
trial from its own per-call time, giving three outcomes:

  - **flat** (the whole in-place surface) — no GC in the loop, tuned normally;
  - **allocating, cappable** — no GC in the loop either, with `samples` capped from the measured
    per-call growth so the pool cannot fill, and `evals` pinned to 1 so the cap means what it says;
  - **allocating, one call already huge** — the per-sample GC, the only safe option left.

The first two are timed on the operation rather than on the collector (docs/PERFORMANCE.md §4(s)).
A row whose parameters were set here is returned in `fixed` and must not be passed to `tune!`, which
would search `evals` upward and undo the cap. Any failure to probe leaves the row on the safe
setting, so an unclassifiable row behaves exactly as it did before this policy existed.
"""
function apply_gcsample_policy!(suite; device_used, reclaim)
  kept, fixed = String[], Set{String}()
  for (class, group) in suite, (key, benchmark) in group
    sample_capped = false
    allocating = try
      warmup(benchmark)
      GC.gc(true)
      reclaim()
      before = device_used()
      GC.enable(false)
      calls, growth, fastest = 0, 0, Inf
      try
        for _ in 1:GCSAMPLE_PROBE_CALLS
          trial = run(benchmark; samples = 1, evals = 1, gcsample = false, gctrial = false)
          calls += 1
          fastest = min(fastest, time(minimum(trial)))
          growth = max(0, device_used() - before)
          growth > GCSAMPLE_PROBE_CEILING && break   # decisive already — stop before filling the pool
        end
      finally
        GC.enable(true)
      end
      growth_per_call = growth / calls
      seconds_per_call = fastest / 1e9
      calls_per_trial = seconds_per_call > 0 ?
        benchmark.params.seconds / seconds_per_call : Inf
      if growth_per_call * calls_per_trial > GCSAMPLE_TRIAL_BUDGET
        # Allocating. Rather than pay a GC per sample, cap the samples so the pool cannot fill, and
        # still measure the operation. `capped` is recorded so the row can be reported honestly.
        capped = clamp(floor(Int, GCSAMPLE_ROW_BUDGET / max(growth_per_call, 1)),
                       GCSAMPLE_MIN_SAMPLES, benchmark.params.samples)
        if capped > GCSAMPLE_MIN_SAMPLES
          benchmark.params.samples = capped
          benchmark.params.evals = 1        # keep calls == samples so the cap means what it says
          sample_capped = true
          false                             # runs GC-free, bounded by the sample cap
        else
          true                              # one call is already huge — only a per-sample GC is safe
        end
      else
        false
      end
    catch
      true                             # unclassifiable ⇒ keep the old, safe behaviour
    end
    benchmark.params.gcsample = allocating
    name = "$(class)/$(strip(split(key, '|')[1]))"
    allocating && push!(kept, name)
    # An allocating row's parameters are now deliberate — a sample cap, or a per-sample GC — so it
    # must NOT be re-tuned: `tune!` would search `evals` upward and undo the cap that bounds the pool.
    # The cap is tracked by its own flag rather than inferred from `evals == 1`, which is ALSO the
    # untuned default: reading it here matched every row, so the whole device suite silently skipped
    # `tune!` instead of only the capped rows.
    (allocating || sample_capped) && push!(fixed, name)
    GC.gc(true)
    reclaim()
  end
  return kept, fixed
end
