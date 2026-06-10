# Exhaustive characterization run: all op-classes over grids 64³–256³, on the backend chosen by
# ARGS[1] ("cpu"/"gpu"), saving a BenchmarkTools JSON to ARGS[2]. Runs **one (size, element-type) at a
# time** (build → run → free) so peak memory stays bounded to a single grid + type — required on the
# 12 GB GPU, where building all classes for both Float64 and Float32 at 256³ exhausts VRAM and HIP's
# pool allocator segfaults rather than erroring (see docs/PERFORMANCE.md §6 gap 5). Thread count is
# taken from the launch (`-tN`); the thread sweep is driven by benchmark/characterize.sh. Results are
# assembled into the committed benchmark/RESULTS.md by benchmark/report.jl. See docs/PERFORMANCE.md §6.

using BenchmarkTools

const USEGPU = !isempty(ARGS) && ARGS[1] == "gpu"
if USEGPU
  @eval using AMDGPU
  @eval AMDGPU.allowscalar(false)
  ARRAY_TYPE = @eval ROCArray
  # Warm the AMD code-object cache (~/.cache/comgr) with one trivial kernel. The FIRST GPU use after
  # a reboot compiles kernels host-side (0% GPU, 100% CPU) and can take minutes — indistinguishable
  # from a hang. Letting it complete here populates the on-disk cache; never kill a cold first run
  # (a killed compile never persists, so the next run restarts cold). See docs/PERFORMANCE.md §6.
  @eval let a = AMDGPU.rand(Float32, 256, 256)
    AMDGPU.synchronize()
    sum(a .* 2.0f0)
    AMDGPU.synchronize()
  end
  println("GPU code-object cache warmed")
  flush(stdout)
else
  ARRAY_TYPE = Array
end

include(joinpath(@__DIR__, "benchmarks.jl"))

# Both element types by default; one is built at a time (see the loop) to bound memory.
const CHAR_SIZES = haskey(ENV, "CHAR_SIZES") ?
  Tuple(parse.(Int, split(ENV["CHAR_SIZES"], ","))) : (64, 128, 256)
BenchmarkTools.DEFAULT_PARAMETERS.seconds = 1.0

# Classes to drop before tuning/running, e.g. `CHAR_SKIP=fft` (a generic escape hatch — empty by
# default; the GPU runs FFT fine, see gap 5).
const CHAR_SKIP = haskey(ENV, "CHAR_SKIP") ? split(ENV["CHAR_SKIP"], ",") : String[]
const RUN_CLASSES = filter(c -> !(c in CHAR_SKIP), collect(CLASSES))

combined = BenchmarkGroup()
for class in RUN_CLASSES
  combined[class] = BenchmarkGroup()
end

# One (size, type) at a time: a 256³ Float64 tensor field is ~1.1 GB, so holding all classes for both
# types at once overflows 12 GB of VRAM. Build → tune → run → free per pair keeps the peak bounded.
for N in CHAR_SIZES, T in TYPES
  println(USEGPU ? "ROCm" : "CPU-t$(Threads.nthreads())", "  tuning + running $(T) $(N)^3 ...")
  flush(stdout)
  suite = build_suite(; array_type = ARRAY_TYPE, types = (T,), sizes = (N,), skip = CHAR_SKIP)
  tune!(suite)
  results = run(suite; verbose = false)
  for class in RUN_CLASSES, key in keys(results[class])
    combined[class][key] = results[class][key]
  end
  suite = nothing
  results = nothing
  GC.gc(true)                         # free this pair's fields before the next (bounds peak memory)
end

label = USEGPU ? "ROCm / AMDGPU" : "CPU, $(Threads.nthreads()) thread(s)"
print_results(combined; label = label)
if length(ARGS) ≥ 2
  mkpath(dirname(ARGS[2]))
  BenchmarkTools.save(ARGS[2], combined)
  println("\nsaved -> ", ARGS[2])
end
