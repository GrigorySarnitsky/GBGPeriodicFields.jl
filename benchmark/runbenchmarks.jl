# CPU benchmark runner. Run at a chosen thread count (matching the CI lanes):
#
#   julia --project=benchmark -t1 benchmark/runbenchmarks.jl
#   julia --project=benchmark -t4 benchmark/runbenchmarks.jl
#
# Save a baseline, then judge a later run against it (manual regression check):
#
#   julia --project=benchmark benchmark/runbenchmarks.jl save results/cpu-baseline.json
#   julia --project=benchmark benchmark/runbenchmarks.jl judge results/cpu-baseline.json
#
# Not part of Pkg.test() — opt-in, like the GPU tests. See docs/PERFORMANCE.md.

include(joinpath(@__DIR__, "benchmarks.jl"))

BenchmarkTools.DEFAULT_PARAMETERS.seconds = 1.0

suite = build_suite()                       # CPU (Array)
println("Tuning on CPU (threads = ", Threads.nthreads(), ") ...")
tune!(suite)
results = run(suite; verbose = false)
print_results(results; label = "CPU, $(Threads.nthreads()) thread(s)")

if length(ARGS) ≥ 2 && ARGS[1] == "save"
  mkpath(dirname(ARGS[2]))
  BenchmarkTools.save(ARGS[2], results)
  println("\nsaved baseline -> ", ARGS[2])
elseif length(ARGS) ≥ 2 && ARGS[1] == "judge"
  baseline = BenchmarkTools.load(ARGS[2])[1]
  println("\n## judge vs ", ARGS[2], " (min-time; :regression / :improvement / :invariant):")
  show(stdout, MIME"text/plain"(), judge(minimum(results), minimum(baseline)))
  println()
end
