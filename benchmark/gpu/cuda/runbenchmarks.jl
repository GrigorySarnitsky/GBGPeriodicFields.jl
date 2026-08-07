# CUDA / NVIDIA benchmark runner (mirrors benchmark/gpu/rocm/runbenchmarks.jl and
# test/gpu/cuda/runtests.jl):
#
#   julia --project=benchmark/gpu/cuda -e 'using Pkg; Pkg.instantiate()'   # one-time
#   julia --project=benchmark/gpu/cuda benchmark/gpu/cuda/runbenchmarks.jl
#   julia --project=benchmark/gpu/cuda benchmark/gpu/cuda/runbenchmarks.jl save results/cuda-baseline.json
#
# Scalar indexing is disabled, so invariant 6 (no scalar GPU indexing) is checked while benchmarking.

using CUDA
CUDA.allowscalar(false)
using BenchmarkTools

CUDA.functional() || error("no functional CUDA device")

include(joinpath(@__DIR__, "..", "..", "benchmarks.jl"))

BenchmarkTools.DEFAULT_PARAMETERS.seconds = 1.0
# A blanket per-sample GC bounds GPU memory, but it is NOT "cheap on the non-allocating classes": it
# inflates every device row 2–29× and times the collector rather than the operation
# (docs/PERFORMANCE.md §4(s)). It cannot simply be dropped either — it is what stops an allocating row
# (lpnorm materializes a magnitude field per call, and Julia's GC triggers on host, not device,
# pressure) exhausting the pool until the allocator wedges. So it is decided PER ROW from a measured
# device-pool probe, exactly as characterize.jl does; the shared implementation lives in
# benchmarks.jl so the three device entry points cannot drift apart.
BenchmarkTools.DEFAULT_PARAMETERS.gcsample = false

suite = build_suite(; array_type = CuArray)
kept, fixed = apply_gcsample_policy!(suite; device_used = () -> CUDA.total_memory() - CUDA.available_memory(), reclaim = CUDA.reclaim)
println("per-sample GC kept for $(length(kept)) allocating row(s)", isempty(kept) ? "" : ": " * join(kept, ", "))
println("Tuning on CUDA / NVIDIA: ", CUDA.device(), " ...")
for (class, group) in suite, (key, benchmark) in group
  "$(class)/$(strip(split(key, '|')[1]))" in fixed || tune!(benchmark)
end
results = run(suite; verbose = false)
print_results(results; label = "CUDA / NVIDIA")

if length(ARGS) ≥ 2 && ARGS[1] == "save"
  mkpath(dirname(ARGS[2]))
  BenchmarkTools.save(ARGS[2], results)
  println("\nsaved baseline -> ", ARGS[2])
elseif length(ARGS) ≥ 2 && ARGS[1] == "judge"
  baseline = BenchmarkTools.load(ARGS[2])[1]
  println("\n## judge vs ", ARGS[2], ":")
  show(stdout, MIME"text/plain"(), judge(minimum(results), minimum(baseline)))
  println()
end
