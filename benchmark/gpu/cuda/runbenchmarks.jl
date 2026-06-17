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
# GC before each sample bounds GPU memory. Allocating reductions (lpnorm materializes a pointwise
# magnitude field per call) otherwise pile up under BenchmarkTools' GC-free sampling loop — Julia's
# GC triggers on host, not device, pressure, so it never fires — until the CUDA pool exhausts and
# the allocator wedges (see docs/PERFORMANCE.md §7). Cheap on the non-allocating classes.
BenchmarkTools.DEFAULT_PARAMETERS.gcsample = true

suite = build_suite(; array_type = CuArray)
println("Tuning on CUDA / NVIDIA: ", CUDA.device(), " ...")
tune!(suite)
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
