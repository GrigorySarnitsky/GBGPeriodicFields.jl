# Exhaustive characterization run: all op-classes over grids 64³–256³, on the backend chosen by
# ARGS[1] ("cpu" default; "gpu"/"rocm" = AMDGPU; "cuda" = NVIDIA), saving a BenchmarkTools JSON to
# ARGS[2]. Runs **one (size, element-type) at a time** (build → run → free) so peak memory stays
# bounded to a single grid + type — required on a memory-limited GPU, where building all classes for
# both Float64 and Float32 at 256³ exhausts VRAM (on AMD, HIP's pool allocator segfaults rather than
# erroring; CUDA OOMs gracefully — see docs/PERFORMANCE.md §6 gap 5). The GPU path is
# backend-parametric: only the array type, the pool `reclaim()`, and the AMD-only code-object warm
# differ. Thread count is taken from the launch (`-tN`); the thread sweep is driven by
# benchmark/characterize.sh. Results are assembled into the committed benchmark/RESULTS.md by
# benchmark/report.jl. See docs/PERFORMANCE.md §6.

using BenchmarkTools

const BACKEND = isempty(ARGS) ? "cpu" : ARGS[1]
const USECUDA = BACKEND == "cuda"
const USEGPU  = USECUDA || BACKEND in ("gpu", "rocm")
if USECUDA
  @eval using CUDA
  @eval CUDA.allowscalar(false)
  ARRAY_TYPE = @eval CuArray
  # CUDA JIT-compiles each kernel through the driver and caches SASS in ~/.nv/ComputeCache; there is
  # no host-side comgr stall (the AMD trap below), so no explicit cache warm is needed.
elseif USEGPU
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

# Both element types and the standard grids by default; one (class, size, type) is built at a time
# (see the loop) to bound memory. `CHAR_SIZES` / `CHAR_TYPES` override the grids / element types —
# e.g. `CHAR_SIZES=512 CHAR_TYPES=Float32` runs only the 512³ Float32 point (the large-grid sweep
# that would OOM in Float64 even on a 24 GB card — the heavy classes' working sets approach the
# ceiling and a HIP OOM segfaults rather than erroring; see docs/PERFORMANCE.md §7).
const CHAR_SIZES = haskey(ENV, "CHAR_SIZES") ?
  Tuple(parse.(Int, split(ENV["CHAR_SIZES"], ","))) : (64, 128, 256)
_char_type(s) = s == "Float64" ? Float64 : s == "Float32" ? Float32 :
  error("CHAR_TYPES entry must be Float64 or Float32, got $(repr(s))")
const CHAR_TYPES = haskey(ENV, "CHAR_TYPES") ?
  Tuple(_char_type(strip(s)) for s in split(ENV["CHAR_TYPES"], ",")) : TYPES
BenchmarkTools.DEFAULT_PARAMETERS.seconds = 1.0
# On GPU, GC before each sample so allocating reductions (lpnorm's per-call magnitude temp) do not
# exhaust the AMDGPU memory pool under BenchmarkTools' GC-free sampling loop — without this the
# `reductions` class wedges the device (full pool + spinning allocator; docs/PERFORMANCE.md §7).
USEGPU && (BenchmarkTools.DEFAULT_PARAMETERS.gcsample = true)

# Classes to drop before tuning/running, e.g. `CHAR_SKIP=fft` (a generic escape hatch — empty by
# default; the GPU runs FFT fine, see gap 5).
const CHAR_SKIP = haskey(ENV, "CHAR_SKIP") ? split(ENV["CHAR_SKIP"], ",") : String[]
const RUN_CLASSES = filter(c -> !(c in CHAR_SKIP), collect(CLASSES))

combined = BenchmarkGroup()
for class in RUN_CLASSES
  combined[class] = BenchmarkGroup()
end

# One (class, size, type) at a time. A 256³ Float64 tensor field is ~1.1 GB; the six classes' fields
# held live together exceed 12 GB of VRAM even for a single element type (a 4-class sweep fit, adding
# reductions + convolution does not). Building a single class at a time bounds the working set to one
# class's fields — a few GB at 256³ — well under the ceiling. Build → tune → run → free per class.
for N in CHAR_SIZES, T in CHAR_TYPES, class in RUN_CLASSES
  println(USECUDA ? "CUDA" : USEGPU ? "ROCm" : "CPU-t$(Threads.nthreads())",
          "  tuning + running $(class) $(T) $(N)^3 ...")
  flush(stdout)
  others = filter(!=(class), collect(CLASSES))
  suite = build_suite(; array_type = ARRAY_TYPE, types = (T,), sizes = (N,), skip = vcat(CHAR_SKIP, others))
  tune!(suite)
  results = run(suite; verbose = false)
  for key in keys(results[class])
    combined[class][key] = results[class][key]
  end
  suite = nothing
  results = nothing
  GC.gc(true)                         # free this class's fields before the next (bounds peak memory)
  # GC returns device memory to the driver's pool, not the OS, so the pool's high-water mark would
  # accumulate across iterations and 256³ eventually OOMs. reclaim() releases the freed blocks back to
  # the OS so each (class, size, type) starts clean (both vendors pool and expose reclaim()).
  USECUDA ? CUDA.reclaim() : (USEGPU && AMDGPU.reclaim())
end

label = USECUDA ? "CUDA / NVIDIA" : USEGPU ? "ROCm / AMDGPU" : "CPU, $(Threads.nthreads()) thread(s)"
print_results(combined; label = label)
if length(ARGS) ≥ 2
  mkpath(dirname(ARGS[2]))
  BenchmarkTools.save(ARGS[2], combined)
  println("\nsaved -> ", ARGS[2])
end
