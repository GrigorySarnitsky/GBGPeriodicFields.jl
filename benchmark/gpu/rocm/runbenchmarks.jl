# ROCm / AMDGPU benchmark runner (mirrors test/gpu/rocm/runtests.jl):
#
#   julia --project=benchmark/gpu/rocm -e 'using Pkg; Pkg.instantiate()'   # one-time
#   julia --project=benchmark/gpu/rocm benchmark/gpu/rocm/runbenchmarks.jl
#   julia --project=benchmark/gpu/rocm benchmark/gpu/rocm/runbenchmarks.jl save results/rocm-baseline.json
#
# Scalar indexing is disabled, so invariant 6 (no scalar GPU indexing) is checked while benchmarking.

using AMDGPU
AMDGPU.allowscalar(false)
using BenchmarkTools

AMDGPU.functional() || error("no functional ROCm device")

include(joinpath(@__DIR__, "..", "..", "benchmarks.jl"))

BenchmarkTools.DEFAULT_PARAMETERS.seconds = 1.0

suite = build_suite(; array_type = ROCArray)
println("Tuning on ROCm / AMDGPU: ", AMDGPU.device(), " ...")
tune!(suite)
results = run(suite; verbose = false)
print_results(results; label = "ROCm / AMDGPU")

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
