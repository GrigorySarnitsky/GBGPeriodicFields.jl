# The cheap benchmark gate: build every row at a tiny grid, RUN each one once, and check the one
# harness invariant a run-once sweep cannot see by timing alone.
#
#   julia --project=benchmark benchmark/gate.jl            # CPU
#   julia --project=benchmark/gpu/cuda benchmark/gate.jl cuda
#   julia --project=benchmark/gpu/rocm benchmark/gate.jl rocm
#
# WHY IT RUNS RATHER THAN BUILDS. `@benchmarkable` only stores its expression, so the suite BUILDS
# clean while a row errors at run time — decision 60 broke two classes this way and nothing noticed
# for three days. Running every row once at ``16^3`` costs seconds, needs no idle machine, and is not
# a measurement, so it does not violate the owns-the-machine rule.
#
# WHY IT ALSO CHECKS THE POINT SET. Running each row once proves rows work in isolation; it cannot
# prove they leave each other alone. The transfer class shared ONE `PointSet` between its `displace!`
# and `wrap!` rows, which mutate positions in place, and the `ordered` rows, whose traversal order was
# built from those positions — so every archived `ordered` row up to 2026-08-31 timed a stale order
# and reported decision 78's feature as a loss (PERFORMANCE.md finding (ak)). The invariant is that a
# row must not mutate state another row's SETUP captured, and one `displace!` call already breaks it,
# so a single pass is enough to catch it. This check is written to FAIL if the fix is reverted; that
# was verified by reverting it, not assumed.
using BenchmarkTools

const BACKEND = isempty(ARGS) ? "cpu" : ARGS[1]
if BACKEND == "cuda"
  @eval using CUDA
  @eval CUDA.allowscalar(false)
  ARRAY_TYPE = @eval CuArray
elseif BACKEND in ("gpu", "rocm")
  @eval using AMDGPU
  @eval AMDGPU.allowscalar(false)
  ARRAY_TYPE = @eval ROCArray
elseif BACKEND == "cpu"
  ARRAY_TYPE = Array
else
  error("unknown backend $(repr(BACKEND)) (want cpu|cuda|rocm)")
end

include(joinpath(@__DIR__, "benchmarks.jl"))

registry = Dict{String, Any}()
suite = build_suite(; array_type = ARRAY_TYPE, types = (Float64, Float32), sizes = (16,), registry)

ran, failed = 0, String[]
for (class, group) in suite, (key, benchmark) in group
  try
    run(benchmark; samples = 1, evals = 1, gcsample = false, gctrial = false)
    global ran += 1
  catch e
    push!(failed, "$(class) / $(key): $(sprint(showerror, e))")
  end
end

# The invariant. `point_positions` returns the live array, so this compares what the rows left
# behind against the copy taken at build time.
mutated = String[]
for (tag, (points, pristine)) in registry
  Array(point_positions(points)) == Array(pristine) || push!(mutated, tag)
end

println("gate ($(BACKEND)): $(ran) rows ran, $(length(failed)) failed | ",
        "transfer point sets unmutated: $(length(registry) - length(mutated))/$(length(registry))")
for f in failed
  println("  FAILED  ", f)
end
for tag in sort(mutated)
  println("  MUTATED transfer point set for $(tag) — a row is writing state another row's setup " *
          "captured (PERFORMANCE.md finding (ak))")
end
isempty(failed) && isempty(mutated) || exit(1)
