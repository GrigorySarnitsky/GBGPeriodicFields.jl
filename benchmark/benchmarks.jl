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
using Statistics: mean      # extended on sections in the Reductions module (not re-exported)
using KernelAbstractions: synchronize, get_backend

Random.seed!(20260609)

include(joinpath(@__DIR__, "harness.jl"))
include(joinpath(@__DIR__, "fft.jl"))
include(joinpath(@__DIR__, "algebra.jl"))
include(joinpath(@__DIR__, "operators.jl"))
include(joinpath(@__DIR__, "transfer.jl"))
include(joinpath(@__DIR__, "reductions.jl"))

const CLASSES = ("fft", "algebra", "operators", "transfer", "reductions")

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

