# Exhaustive characterization run: all op-classes over grids 64³–256³, on the backend chosen by
# ARGS[1] ("cpu"/"gpu"), saving a BenchmarkTools JSON to ARGS[2]. Runs **size-by-size** (build →
# run → free) so peak memory stays bounded to one grid size. Thread count is taken from the launch
# (`-tN`); the thread sweep is driven by benchmark/characterize.sh. Results are assembled into the
# committed benchmark/RESULTS.md by benchmark/report.jl. See docs/PERFORMANCE.md §6.

using BenchmarkTools

const USEGPU = !isempty(ARGS) && ARGS[1] == "gpu"
if USEGPU
  @eval using AMDGPU
  @eval AMDGPU.allowscalar(false)
  ARRAY_TYPE = @eval ROCArray
else
  ARRAY_TYPE = Array
end

include(joinpath(@__DIR__, "benchmarks.jl"))

# CPU runs to 256³; the GPU is capped at 128³ by default — a 256³ GPU run wedges host-side
# (0% GPU, 100% CPU), consistent with a rocFFT 256³ batched-plan stall under AMDGPU (the 256³ GPU
# *transfer* kernels run fine, so it is the FFT class). Override with CHAR_SIZES, e.g.
# `CHAR_SIZES=64,128,256 julia … characterize.jl gpu …`.
const CHAR_SIZES = haskey(ENV, "CHAR_SIZES") ?
  Tuple(parse.(Int, split(ENV["CHAR_SIZES"], ","))) : (USEGPU ? (64, 128) : (64, 128, 256))
BenchmarkTools.DEFAULT_PARAMETERS.seconds = 1.0

combined = BenchmarkGroup()
for class in CLASSES
  combined[class] = BenchmarkGroup()
end

for N in CHAR_SIZES
  println(USEGPU ? "ROCm" : "CPU-t$(Threads.nthreads())", "  tuning + running $(N)^3 ...")
  suite = build_suite(; array_type = ARRAY_TYPE, sizes = (N,))
  tune!(suite)
  results = run(suite; verbose = false)
  for class in CLASSES, key in keys(results[class])
    combined[class][key] = results[class][key]
  end
  suite = nothing
  results = nothing
  GC.gc(true)                         # free this size's fields before the next (bounds peak memory)
end

label = USEGPU ? "ROCm / AMDGPU" : "CPU, $(Threads.nthreads()) thread(s)"
print_results(combined; label = label)
if length(ARGS) ≥ 2
  mkpath(dirname(ARGS[2]))
  BenchmarkTools.save(ARGS[2], combined)
  println("\nsaved -> ", ARGS[2])
end
