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
# A blanket per-sample GC bounds GPU memory, but it is NOT "cheap on the non-allocating classes": it
# inflates every device row 2–29× and times the collector rather than the operation
# (docs/PERFORMANCE.md §4(s)). It cannot simply be dropped either — it is what stops an allocating row
# (lpnorm materializes a magnitude field per call, and Julia's GC triggers on host, not device,
# pressure) exhausting the pool until the allocator wedges. So it is decided PER ROW from a measured
# device-pool probe, exactly as characterize.jl does; the shared implementation lives in
# benchmarks.jl so the three device entry points cannot drift apart.
BenchmarkTools.DEFAULT_PARAMETERS.gcsample = false

suite = build_suite(; array_type = ROCArray)
kept, fixed = apply_gcsample_policy!(suite; device_used = AMDGPU.used_memory, reclaim = AMDGPU.reclaim)
println("per-sample GC kept for $(length(kept)) allocating row(s)", isempty(kept) ? "" : ": " * join(kept, ", "))
println("Tuning on ROCm / AMDGPU: ", AMDGPU.device(), " ...")
for (class, group) in suite, (key, benchmark) in group
  "$(class)/$(strip(split(key, '|')[1]))" in fixed || tune!(benchmark)
end
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
