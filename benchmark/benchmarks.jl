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
using KernelAbstractions: synchronize, get_backend

Random.seed!(20260609)

include(joinpath(@__DIR__, "harness.jl"))
include(joinpath(@__DIR__, "fft.jl"))
include(joinpath(@__DIR__, "algebra.jl"))
include(joinpath(@__DIR__, "operators.jl"))
include(joinpath(@__DIR__, "transfer.jl"))

const CLASSES = ("fft", "algebra", "operators", "transfer")

function build_suite(; array_type = Array, types = TYPES, sizes = SIZES)
  suite = BenchmarkGroup()
  for class in CLASSES
    suite[class] = BenchmarkGroup()
  end
  for T in types, N in sizes
    grid = make_grid(T, N)
    tag = string(T, " ", N, "^3")
    add_fft!(suite["fft"], array_type, T, grid, tag)
    add_algebra!(suite["algebra"], array_type, T, grid, tag)
    add_operators!(suite["operators"], array_type, T, grid, tag)
    add_transfer!(suite["transfer"], array_type, T, grid, tag)
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

