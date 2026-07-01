# Performance — GBGPeriodicFields

This is the third companion to [`ARCHITECTURE.md`](architecture.md) and
[`TESTING.md`](testing.md): where those explain *why* the package is built as it is and *how* its
correctness is checked, this one explains *how performance is reasoned about, measured, and tracked*.
Read it before optimizing anything or adding a benchmark. The throughline is the same as for tests:
a performance claim is only as good as the independent measurement behind it — and on the platform
that matters.


## 1. Philosophy

**Memory-bound, GPU-first, measure-don't-guess.** Three principles set everything below.

- **The baseline is memory bandwidth, not flops.** Every operation here has *low arithmetic
  intensity* — a handful of floating-point operations per element moved (§2). So "fast" means
  "moving the necessary bytes efficiently," and adding cores or tuning arithmetic helps only until
  the memory system saturates. The roofline ceiling for this package is the bandwidth roof, not the
  compute roof ([roofline](https://developer.nvidia.com/blog/accelerating-hpc-applications-with-nsight-compute-roofline-analysis/)).
- **GPU-first (invariant 6).** Production runs on the GPU; the CPU path is for development, testing,
  and small problems. When an optimization helps one platform and hurts the other — which *happens*,
  and is proven below — the GPU wins. CPU multithreading is a supported feature (`docs/ARCHITECTURE.md`
  §9), but it is not the platform performance is optimized *for*.
- **Measure before you optimize, and measure on the production platform.** No optimization is kept
  without a same-session side-by-side comparison showing it helps the GPU. This session's record is instructive: of the
  candidates that *looked* like wins, polynomial-eval tuning was already free, the periodic-wrap
  hoist made the default scheme *slower*, and particle sorting — the textbook locality optimization —
  *regressed* the GPU gather. Only the one the measurement pointed at (loop order) survived (§4).

A scope note carried from the architecture: **platform optima diverge**, so every result below is
reported per platform, never as a single number. (The **L²/measure reductions** — `integral`, `inner`,
`l2norm`, `mean`, …; `docs/ARCHITECTURE.md` decision 18 — are bandwidth-bound streaming reductions
whose only subtlety is floating-point summation order, tolerance-tested rather than bitwise; they are
now part of the suite, §5.)


## 2. The performance model

What bounds each public operation class — the mental model a benchmark either confirms or refutes.

- **FFT transforms** (`to_physical`/`to_spectral`) → bound by **FFTW** (CPU) / **rocFFT** (GPU). The
  package adds only the normalization convention and the fiber-last layout (`docs/ARCHITECTURE.md`
  §3–4); the transform itself is the library's. Not something we tune — but the dominant cost of any
  spectral step, so it is benchmarked to track the libraries and our plan/layout overhead.
- **Field algebra (M2 + M3), spectral differential operators, and convolution** → **memory-bandwidth-bound**. A
  fiberwise add, contraction, wavenumber multiply, or kernel multiply (`convolve`) reads and writes `O(1)` numbers per grid point
  and does `O(1)` flops on them — arithmetic intensity well below the roofline ridge. Consequence:
  on CPU, thread scaling saturates once the cores jointly saturate DRAM bandwidth (the plateau in
  §4); on GPU, the figure of merit is achieved bandwidth, not occupancy.
- **The grid↔point transfer** (`interpolate`/`anterpolate`), local-stencil **spline** schemes → the
  subtle one. Each point gathers (or scatters) a ``(2n{+}2)^3`` stencil (``n`` the spline half-width) with data-dependent indices, so
  it is bound by **irregular memory access**, and the binding *differs by platform*:
  - **GPU**: maximize **memory-level parallelism** — many distinct cache lines and DRAM banks in
    flight at once to hide latency
    ([coalescing/occupancy](https://rocm.docs.amd.com/projects/HIP/en/latest/how-to/performance_guidelines.html)).
    Scattered (unsorted) points naturally *spread* access and feed that parallelism; and at the
    grids we run the field is largely **cache-resident** (a 256³ `Float32` field is 67 MB, inside the
    RX 6700 XT's 96 MB Infinity Cache), so there is little locality left to win.
  - **CPU**: bound by the cache hierarchy + hardware prefetchers, which *reward* locality — the
    opposite pull.

  This single fact — GPU wants spread, CPU wants locality — explains the platform-divergent results
  in §4 (loop order, sorting) and is the most important thing to internalize before touching the
  transfer.
- **The spectral transfer** (`DirectDFT`/`NUFFT`) → a different cost class. `DirectDFT` is the exact
  ``O(N M)`` double sum (compute-bound, no FFT, no window) — the oracle; `NUFFT` is its
  ``O(N\log N + M)`` fast form, an oversampled FFT plus a windowed spread/gather, so it is FFT-bound in
  the grid size ``N`` and carries the same irregular-access spread/gather as the splines in the point
  count ``M``.


## 3. Best practices

Short checklists, each grounded in an external reference. Most are already enforced by the
architecture or the tests; they are collected here so an optimizer has them in one place.

**Julia** (Julia [Performance Tips](https://docs.julialang.org/en/v1/manual/performance-tips/);
[Modern Julia Workflows](https://modernjuliaworkflows.org/optimizing/)):

- **Type stability** — non-concrete types force boxing and allocation. Checked package-wide by
  `test/jet.jl` (`JET.@test_call`).
- **Zero allocations in hot paths** — an unexpected allocation almost always signals a type problem.
  Prefer the in-place `!` forms; allocate scratch once and reuse. (`@allocated`/BenchmarkTools report it.)
- **`@inbounds` in kernels**, **isbits / `SVector` kernel arguments** (so the spline coefficient
  matrices pass into GPU kernels *by value*, no device array), and **fused broadcasts through
  `_assign!`** rather than a bare `.=` (the codegen + threading contract, `docs/ARCHITECTURE.md` §9).
- **Allocate via `similar`/`similar_field`** so results inherit the input's backend (the one-line
  reason a CPU-written method runs on a `ROCArray` unchanged).

**GPU** (ROCm/HIP [performance guidelines](https://rocm.docs.amd.com/projects/HIP/en/latest/how-to/performance_guidelines.html)):

- **No scalar indexing of device arrays** (invariant 6) — a checked guarantee under
  `allowscalar(false)` in both the test and benchmark GPU runs.
- **Favour spread access for memory-level parallelism**, and **loop the contiguous (`x`) axis
  innermost** so per-thread stencil access is stride-1 (§4 measured this at up to 3.9×).
- **Minimize host↔device transfer**; keep fields resident on the device. **Allocate once, operate
  in place.**

**Methodology** (BenchmarkTools.jl [manual](https://juliaci.github.io/BenchmarkTools.jl/)):

- **Warm up** (compile) before timing; **synchronize the backend** — GPU work is asynchronous, so an
  un-synced timer measures launch latency, not the kernel (the suite's `bench_sync`).
- **Report the minimum** of many samples (least-noise estimator) alongside the median.
- **Side-by-side comparison in one session**: build both variants (baseline and candidate) and time
  them on identical data, back-to-back, in a single process — the only reliable way to resolve a
  difference smaller than the ~10% run-to-run variance (separate launches drift with thermal state,
  allocation layout, and cache).
- **Control the thread count** (`-t1` vs `-t4`), and **always confirm on the GPU** before keeping an
  optimization (platform divergence is real, §4).


## 4. What we have found

Measured on the home **AMD Radeon RX 6700 XT** (gfx1031, 12 GB, 96 MB Infinity Cache, ~384 GB/s
peak) and **Intel i7-12700K** (8 P-cores), `Float32`, ~1 point per 27 grid cells. These are the
cumulative results of the transfer-layer optimization work; the benchmark suite (§5) regenerates the
tracked subset on demand.

**(a) Memory-bound, and smoothness is free.** Interpolation runs at ~12% of peak bandwidth at 256³;
cost scales with the stencil *volume* ``(2n{+}2)^3``, and the spline degree (`m`) is invisible — the
weight polynomials hide under memory latency. So pick the smoothness for accuracy, never for speed.

| gather scheme | stencil | GPU 256³ (621k pts) | throughput |
|---|---|---|---|
| `LalescuSpline(0,0)` (trilinear)   | 2³ = 8   | 0.51 ms                | 1230 Mpts/s |
| `LalescuSpline(1,1)` (Catmull–Rom) | 4³ = 64  | 3.55 ms                | 175 Mpts/s  |
| `LalescuSpline(3,m)` (Lalescu 8-pt)| 8³ = 512 | 28.0 ms (flat in `m`)  | 22 Mpts/s   |

**(b) Loop order — contiguous axis innermost (KEPT).** Iterating the contiguous `x` axis innermost
(stride-1 stencil access) vs `z`-innermost (stride ``N_x N_y``, the grid's ``x``,``y`` dimensions):

| | GPU 256³ | GPU 512³ (Lalescu) | CPU (Catmull–Rom / Lalescu) |
|---|---|---|---|
| speedup (x-inner / z-inner) | 1.6–1.7× | **3.9×** (785→203 ms) | **0.75×** (regression) |

Kept x-inner as a **GPU-first** choice — the CPU's large caches absorb the strided access and its
`z`-inner form vectorizes better, but the GPU is the production platform.

**(c) Rejected by measurement.** Two "obvious" optimizations that did not survive:

- **Wrap-hoist** (precompute the ``3(2n{+}2)`` periodic node offsets to kill inner-loop `mod`s):
  bit-identical, but **regressed the default Catmull–Rom by 10–14%** — the extra registers cut
  occupancy. Proof the kernels are memory/occupancy-bound, not ALU-bound.
- **Morton particle sorting** (the textbook GPU-locality optimization): **0.5–1.0× on GPU** (gather)
  — concentrating access *kills* the memory-level/DRAM-bank parallelism the GPU needs, and the field
  is cache-resident anyway — though **2.2–4.4× on CPU**. The companion **atomic-free node-centric
  scatter** is correct, conserving and bit-**deterministic**, but **6–24× slower on GPU**: at our
  sparse 1-per-27 density it traverses ~27× more (empty) reverse-stencil cells than the atomic
  scatter touches particles. Sorting + node-centric deposition is a *dense*-particle (PIC) technique;
  wrong for this regime. (If deterministic anterpolation ever becomes a hard requirement, it is the
  available — slow-at-sparse — answer.)

**(d) Anterpolation and contention.** The scatter costs ≈**2.2–2.7×** the gather (atomic
read-modify-write + a full-grid prescale). On gfx1031 `Float32` atomic-add is native but `Float64`
is emulated (CAS loop) ⇒ ≈**1.3–1.7×** slower; contention is worst at *moderate* clustering
(~2 pts/cell), not extreme (extreme stays cache-hot).

**(e) CPU vs GPU.** The transfer threads on CPU through KernelAbstractions' `CPU()` backend with no
code change, scaling ≈**4.5–5.7×** on 8 threads before the bandwidth plateau; the GPU is ≈**9–22×**
the 8-thread CPU (≈ the 384-vs-~60 GB/s bandwidth ratio for the heavy schemes, more for the light
ones via parallelism).

**(f) Allocation-free in-place operators — the GPU hot-loop discipline.** A pseudospectral solver
applies the spectral operators thousands of times in its time loop, so any per-call scratch an operator
allocates internally matters. On the GPU it matters *a lot*: such scratch escapes Julia's GC (which
triggers on *host* memory, while the scratch is *device* memory), so the device pool grows every step
until VRAM fills and the run wedges (allocator spinning, GPU idle) or `hipMalloc` aborts — observed at
192³/256³. The fix made the in-place spectral operators allocate **nothing**: `_squared_wavenumber_broadcast`
(the ``|k|^2`` coordinate) is returned **lazily** (an unfused `Broadcasted`, no ``O(N^3)`` array), and the
`helmholtz_projection!` / `laplacian!` / `inverse_laplacian!` kernels fuse their former temporaries into
the component broadcasts — each now allocates ``\sim 0`` bytes in place (measured; guarded by
`test/allocations.jl`), with identical results. Payoff: a **preallocated, in-place** pseudospectral DNS
step allocates nothing per step → **no manual `GC.gc()`/`reclaim`, flat VRAM**. The forced-HIT example
(`examples/gpu/rocm/HIST_ROCm.jl`, 192³ `Float32`, ``Re_\lambda \approx 93``) sustains **≈ 34 ms/step**
(8000 steps, ≈ 270 s) on the RX 6700 XT this way. *Discipline for consumers:* preallocate a workspace and
use the `!` forms with a destination distinct from the sources; the fiber `norm`/`lpnorm`/`dev!`
deliberately materialize one field and are the exceptions (use `maximum(abs, …)` for a CFL speed).
[Decision 24.]

**(g) Allocation-bounded radial diagnostics — the same GC trap, in the binning.** The same device-GC
hazard as (f) lived in the *diagnostics*. `radial_spectrum` / `radial_correlation` binned by looping over
the ``|k|``- (or ``|r|``-) shells and reducing a masked broadcast per shell. The shell count scales with
the grid (``\approx \sqrt{3}\,N/2``, ``\approx 220`` at ``N = 256``), and each iteration allocates a
full-grid mask — and, because a `mapreduce` over a `Broadcasted` *materializes* on this GPU stack rather
than fusing, the masked product too: ``O(N)`` full-grid temporaries per call, which the host-triggered GC
does not reclaim. A single ``256^3`` `radial_correlation` snapshot churned several GB and wedged a 12 GB
card at the *first* snapshot. The fix bins in a **single scatter-add pass** — one portable
`KernelAbstractions` + `Atomix` histogram kernel atomically accumulating each element into its shell — so
per-call temporaries drop from ``O(N)`` to ``O(1)``. Correctness is unchanged (same per-shell sums; CPU
`test/reductions.jl` + GPU parity hold). Payoff: the ``256^3`` `Float32` forced-HIT example
(``\approx 87`` ms/step) now runs to completion on the RX 6700 XT at a flat ``\sim\!6`` GB
(``\approx 8`` GB peak) through its snapshots, where the per-shell form wedged at the first one. The scatter contends on the small accumulator set, acceptable for an *occasional* diagnostic
(not a per-step call); a privatized histogram is a possible future optimization. [Decision 25.]

**(h) FFTW `ESTIMATE` can badly mis-plan single-precision transforms — pass `MEASURE` for production.**
`FieldTransformPlans` builds its FFTW plans with the default `ESTIMATE` flag (instant, but it *guesses*
the algorithm instead of timing candidates). On a Ryzen 9800X3D (Zen 5, stock FFTW 3.3.11) that guess is
~5× too slow for the 256³ `Float32` transforms — in **both** directions, at every thread count — because
its hardcoded single-precision codelet heuristics misjudge this CPU generation. Rebuilding with
`FFTW.MEASURE` (a one-time, timed plan search) fixes it, and the planning cost (seconds) amortizes over a
long run. Pure in-place transform, 256³ `Float32`, minimum time:

| threads | c2r (`to_physical!`), `ESTIMATE`→`MEASURE` | r2c (`to_spectral!`), `ESTIMATE`→`MEASURE` |
|---|---|---|
| 1 | 163 → 30 ms (**5.4×**) | 167 → 31 ms (**5.3×**) |
| 4 | 43.7 → 9.5 ms (**4.6×**) | 41.7 → 8.3 ms (**5.1×**) |
| 8 | 23.5 → 6.8 ms (**3.4×**) | 21.8 → 4.8 ms (**4.5×**) |

It is size- and CPU-specific (128³ is fine; the i7-12700K shows no such inversion) — a classic `ESTIMATE`
pitfall on a new CPU, not a package issue. The default stays `ESTIMATE` (cheap, deterministic, right for
tests and short runs); the escape hatch already exists,
`FieldTransformPlans(phys, spec; fft_flags = FFTW.MEASURE)` (or `FFTW.PATIENT`). `MEASURE` overwrites its
input arrays while planning, so build the plans on scratch fields before seeding data. The forced-HIT CPU
example (`examples/HIST_CPU.jl`) now plans with `MEASURE`.


## 5. The benchmark suite

A standing suite under `benchmark/` (sibling of `test/`), **opt-in** — *not* part of
`Pkg.test()`, exactly like the GPU tests. `build_suite(; array_type, types, sizes)` builds a
`BenchmarkTools.BenchmarkGroup` parameterised by the **device array type** (`Array` on CPU;
`ROCArray`/`CuArray` on GPU — the same approach `test/gpu/suite.jl` uses with `to_device`), so one suite
runs everywhere. A `bench_sync` blocks the backend so BenchmarkTools times GPU work to completion.

Classes covered: **FFT** transforms, **field algebra** (M2 + M3, representative), **spectral
operators**, **convolution** (`convolve!` scalar/vector + the builders `spectral_cutoff` /
`spectral_band` / `squared_wavenumber_field` / `assignment_window`), the **interpolation/anterpolation
transfer** (the spline schemes plus the spectral `NUFFT`; the exact `DirectDFT` is its oracle, not a swept regression target), and the
**L²/measure reductions** (`integral`/`mean`/`inner`/`l2norm`/`lpnorm`/`maximum`, the spectral Parseval
`inner`, and the radial pair `radial_spectrum` / `radial_correlation` plus the two-field co-spectra
`radial_spectrum(f, g)` / `radial_correlation(f, g)` — a single scatter-add shell-binning pass and an
inverse rfft, diagnostic-cost; the co-spectra cost the same as the single-field forms, sharing their
binning). Run it:

```sh
julia --project=benchmark -e 'using Pkg; Pkg.instantiate()'   # one-time
julia --project=benchmark -t1 benchmark/runbenchmarks.jl       # serial lane
julia --project=benchmark -t4 benchmark/runbenchmarks.jl       # threaded lane
julia --project=benchmark/gpu/rocm benchmark/gpu/rocm/runbenchmarks.jl   # GPU (on hardware)
```

The tracked SUITE uses **modest grids (64³, 128³)** for fast, repeatable, regression-sensitive
runs; the large characterisation sweep behind §4 (256³/512³) is reachable with `build_suite(; sizes
= (256,))`. Manifests are gitignored (repo convention); each environment reproduces from its
`Project.toml`.

**The coverage contract.** Every public operation is benchmarked over **{Float64, Float32} ×
{representative grid sizes} × {CPU `-t1`, CPU `-t4`, GPU}**. New code adds its benchmark to the
matching per-class file — the performance analogue of the test coverage contract (`TESTING.md` §4).


## 6. Tracking regressions, and per-platform results

**Workflow (manual, BenchmarkTools).** Save a baseline, then `judge` a later run against it on the
minimum-time estimates:

```sh
julia --project=benchmark benchmark/runbenchmarks.jl save results/cpu-baseline.json
julia --project=benchmark benchmark/runbenchmarks.jl judge results/cpu-baseline.json   # :regression / :improvement / :invariant
```

Because CI runners have no GPU, **GPU tracking is manual**: run the GPU suite on the device and
record the numbers here. Adding a platform = mirror `benchmark/gpu/rocm/` (a `Project.toml` + a
2-line `runbenchmarks.jl`); the suite needs no changes.

**Two scales.** The **tracked SUITE** (`runbenchmarks.jl`, grids 64³/128³) is the quick,
regression-sensitive run used with `save`/`judge` above. The **exhaustive characterization**
(`benchmark/characterize.sh`) runs the full matrix — every op-class (including FFT) over grids
**64³–256³**, on the **CPU thread sweep 1/2/4/8** (powers of two up to the performance cores) and the
**GPU** — building **one (grid size, element type) at a time** to bound memory (a 256³ `Float64`
tensor field is ~1.1 GB; holding all classes for both types at 256³ overflows the 12 GB GPU — gap 5),
and assembles it into the committed report
[`benchmark/RESULTS.md`](https://github.com/GrigorySarnitsky/GBGPeriodicFields.jl/blob/master/benchmark/RESULTS.md)
(the raw per-run JSON under `benchmark/results/` is gitignored). Regenerate it on any platform with
that one script; it stamps the date, commit, and host.

A representative slice — `128³`, `Float64`, minimum time (CPU = i7-12700K, GPU = RX 6700 XT). The
last two columns are speedups *in ×*: CPU thread scaling (`-t1` → `-t4`) and the GPU's lead over the
4-thread CPU. `RESULTS.md` now carries **two CPU thread sweeps** (i7-12700K and Ryzen 9800X3D) and
**four GPU columns** — the GTX 1070 (Pascal, CUDA, pre-swap), the RX 6700 XT shown here, the RX 7900 XTX
(gfx1100, 24 GB), and the RTX 5070 Ti (Blackwell sm_120, CUDA, 16 GB). At 256³ (kernel-dominated, not
launch- or `gcsample`-floored) the 7900 XTX runs ~1.7–3.8× faster than the 6700 XT — widest in
`Float32` — and adds a 512³ `Float32` point; the 5070 Ti covers the full 256³ matrix (both element
types, all six classes). The full operation × type × grid × thread/backend matrix is in `RESULTS.md`:

| operation (128³, Float64) | CPU `-t1` | CPU `-t4` | GPU | threads `-t1`→`-t4` | GPU vs `-t4` |
|---|--:|--:|--:|--:|--:|
| `to_spectral` scalar (FFT)            | 7.11 ms | 3.88 ms | 0.40 ms | 1.8× |  9.6× |
| `mul!` tensor·vec (M3 algebra)        | 13.5 ms | 11.0 ms | 0.97 ms | 1.2× | 11.4× |
| `laplacian!` scalar (operator)        | 3.09 ms | 2.81 ms | 0.21 ms | 1.1× | 13.4× |
| `interpolate!` Catmull–Rom (gather)   | 13.8 ms | 3.52 ms | 0.28 ms | 3.9× | 12.7× |
| `interpolate!` Lalescu (3,3) (gather) | 85.4 ms | 21.7 ms | 1.57 ms | 3.9× | 13.8× |
| `anterpolate!` Catmull–Rom (scatter)  | 29.6 ms | 7.64 ms | 0.67 ms | 3.9× | 11.5× |

Two patterns the speedup columns make plain. **The bandwidth-bound classes barely thread** at this
size — algebra and operators gain only ≤1.2× from 4 threads (the cheapest, `add!`, even regresses: it
is already DRAM-bandwidth-saturated on one core), confirming §2. **The transfer threads well** (≈3.9×
on the Catmull–Rom gather) because its stencil gather carries more work per byte. And the **GPU leads
the 4-thread CPU by ~10–14×** (and the serial CPU by up to ~50× — e.g. Catmull–Rom gather, 13.8 →
0.28 ms), widest for the light/parallel ops and narrowing toward the bandwidth ratio for the heavy
streaming ones. (`Float32` is ~0.6–0.7× of these `Float64` times on the GPU; the full
operation × type × grid × thread/backend matrix — including the per-grid scaling and the 1/2/4/8
thread sweep — is in `benchmark/RESULTS.md`.)


## 7. Current coverage and known gaps

**Covered:** the public operation classes (FFT, algebra, operators, convolution, transfer, reductions)
parameterised by element type and grid size, runnable on CPU (`-t1`/`-t4`) and GPU (ROCm or CUDA) through one
device-parameterised suite; the manual save→`judge` regression workflow; and the **exhaustive characterization**
(`characterize.sh` → committed `benchmark/RESULTS.md`): every op-class (incl. FFT) at grids 64³–256³,
across two CPU 1/2/4/8 thread sweeps (i7-12700K, Ryzen 9800X3D) and four GPUs — GTX 1070 (Pascal,
CUDA), RX 6700 XT, RX 7900 XTX, and RTX 5070 Ti (Blackwell sm_120, CUDA); the 7900 XTX is extended to
a 512³ `Float32` point for the bandwidth-bound classes.

**Gaps:**

1. **GPU `reductions`/`convolution` are measured with `gcsample` — read them as latency, not
   throughput.** Both classes are now in `RESULTS.md` for every platform (CPU 1/2/4/8 + GPU). The GPU
   figures use `gcsample = true` (gap 5): a GC before each sample bounds memory but adds a fixed
   per-sample cost, so the small-grid GPU times (≈1.5 ms at 64³) are dominated by that overhead, not by
   the kernel — read those as per-call latency, and trust the 256³ figures, where the kernel dominates
   and the GPU pulls ahead of the CPU. The CPU columns and the non-allocating GPU classes are
   unaffected (gcsample is cheap when there is nothing to collect).
2. **CUDA spans two NVIDIA generations, both on `Enteropia`** (the office box; CPU Ryzen 9800X3D).
   `characterize.jl` now takes a `cuda` backend beside `gpu`/`rocm` (CuArray + `CUDA.reclaim()`, no
   comgr warm), so the memory-bounded one-class-at-a-time sweep runs on NVIDIA too. The archived
   **GTX 1070** (Pascal, 8 GB) stays a 64³/128³ column — an 8 GB Pascal card tops out below 256³, so
   those rows read `—`. Its in-place replacement, the **RTX 5070 Ti** (Blackwell sm_120, 16 GB), covers
   the **full 64³–256³ matrix** (both element types, all six classes; ~10.8 GB peak). 512³ exceeds
   16 GB — the `mul!` tensor field alone is 4.5 GB and the build OOMs — but unlike AMD's HIP (gap 5),
   CUDA **OOMs gracefully** (a Julia `OutOfGPUMemoryError`, no context corruption), so probing the
   ceiling is safe. `Enteropia` now also contributes its **9800X3D** CPU thread sweep beside the
   i7-12700K (host `Aiporetne`).
3. **Automated CI regression** — deferred. The `BenchmarkGroup` layout keeps
   [AirspeedVelocity.jl](https://github.com/MilesCranmer/AirspeedVelocity.jl) (PR-over-PR CPU
   comparison) or [PkgBenchmark.jl](https://github.com/JuliaCI/PkgBenchmark.jl) a drop-in later.
4. **Run-to-run variance** — absolute numbers carry ~10% jitter, so cross-platform/-commit
   comparisons are only meaningful within a single session (hence the side-by-side discipline of
   §3); the tables here are indicative magnitudes, not contract values.
5. **GPU at 256³ — three traps, none a rocFFT bug** (RX 6700 XT, gfx1031, 12 GB, ROCm 7.2.4).
   Earlier notes blamed "rocFFT 256³ planning"; that was wrong. The facts, measured:
   - **256³ FFT works.** Scalar and vector r2c/c2r at 256³ take ~1 s to plan and ~15–20 ms to run;
     the full `fft` class passes at 256³.
   - **Cold kernel compilation looks like a hang.** The first GPU use after a reboot compiles
     kernels host-side via AMD `comgr` → 0% GPU, 100% CPU, VRAM pool reserved, no output, for
     minutes. *Never kill a cold first run* — a killed compile never persists to `~/.cache/comgr`, so
     the next run restarts cold. `characterize.jl` warms the cache with one trivial kernel up front.
   - **The 256³ working set overflows 12 GB VRAM, and HIP segfaults instead of erroring** — the crash
     is `hipMallocFromPoolAsync` in `libamdhip64.so`. Two compounding causes, two fixes: (i) holding
     *all six classes'* fields live for one (size, type) exceeds 12 GB at 256³ (a 4-class sweep fit;
     adding reductions + convolution did not) → `characterize.jl` builds **one (op-class, size,
     element-type) at a time**, bounding the working set to a single class (~few GB); (ii) GC returns
     freed device memory to the AMDGPU *pool*, not the OS, so the pool high-water mark accumulates
     across iterations and 256³ OOMs late (the first pairs fit, the last does not) → **`AMDGPU.reclaim()`
     between iterations** releases blocks back to the OS. Knock-on: a VRAM-OOM segfault can still
     degrade the HIP context until a reboot / `rocm-smi --gpureset`, after which even small ops segfault
     under load.
   - **A GC-free benchmark loop wedges the allocating reductions** — independent of grid size (seen at
     64³), and the cause of a 4-hour hang. `lpnorm` materializes a pointwise-magnitude field per call;
     BenchmarkTools' `tune!`/`run` does almost no *host* allocation, so Julia's GC (host-pressure
     triggered) never fires, the dead GPU temps pile into the AMDGPU pool until it hits 12 GB, and the
     allocator spins — CPU pegged, GPU idle, VRAM maxed, for hours. It is **GC-lag, not a leak**
     (`GC.gc()` every ~50 calls holds the pool flat; a real solver fires GC every step, so the op is
     fine in use). Fixed by **`gcsample = true`** for GPU runs (`characterize.jl` and the ROCm runner):
     a GC before each sample bounds the pool — the `reductions` class then completes at ~0.5 GB peak.
     Distinct from the cold-compile hang above — there comgr is *active* (compiling, minutes); here it
     is *idle* (wedged, hours).

   With the per-(op-class, size, type) build the full 64³–256³ GPU column **is** in `RESULTS.md`. The
   standing limit on the 6700 XT is the 12 GB ceiling itself: even one class's both-element-type 256³
   fields strain it (hence the one-class-at-a-time build), and 512³ won't fit on that card. If a future
   OOM-segfault degrades the context, reset with `rocm-smi --gpureset` from a console (it can crash an
   active display session) or reboot.

   **Update (2026-06-26, RX 7900 XTX, gfx1100, 24 GB).** On RDNA3 256³ is indeed trivial for every class
   (both element types), and a **512³ `Float32`** point is now in `RESULTS.md` for the bandwidth-bound
   classes (`fft`, `algebra`, `operators`, `convolution`). But 512³ is *not* free even at 24 GB:
   `transfer` is omitted (its NUFFT oversamples ×2 to a 1024³ work grid) and `reductions` is omitted
   (the radial diagnostics hold a ≈24 GB live set at 512³ — vector physical + spectral fields + the
   inverse-rfft plans). A 512³ `Float64` sweep of the heavy classes exceeds 24 GB,
   and a HIP OOM **wedges** the allocator (GPU 0 %, one host core spinning, VRAM full) rather than
   erroring — the same trap as the cold-compile / GC-free hangs above, and `gcsample` does *not* help
   when the *live* set (not GC lag) is what overflows. So the 512³ column is `Float32` and skips those two.
