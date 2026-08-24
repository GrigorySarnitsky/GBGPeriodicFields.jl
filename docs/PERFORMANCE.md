# Performance — GBGPeriodicFields

This is the third rationale companion to [`ARCHITECTURE.md`](architecture.md) and
[`TESTING.md`](testing.md): where those explain *why* the package is built as it is and *how* its
correctness is checked, this one explains *how performance is reasoned about, measured, and tracked*.
Read it before optimizing anything or adding a benchmark. The throughline is the same as for tests:
a performance claim is only as good as the independent measurement behind it — and on the platform
that matters.


## 1. Philosophy

**Memory-bound, GPU-first, measure-don't-guess.** Four principles set everything below.

- **The baseline is memory bandwidth, not flops.** Every operation here has *low arithmetic
  intensity* — a handful of floating-point operations per element moved (§2). So "fast" means
  "moving the necessary bytes efficiently," and adding cores or tuning arithmetic helps only until
  the memory system saturates. The roofline ceiling for this package is the bandwidth roof, not the
  compute roof ([roofline](https://developer.nvidia.com/blog/accelerating-hpc-applications-with-nsight-compute-roofline-analysis/)).
- **GPU-first, and the CPU path targets a whole cluster node.** Production runs on the GPU, and where
  an optimization helps one platform and hurts the other — which *happens*, and is proven below — the
  GPU wins across the range both can run. One carve-out, exercised once: the rule ranks *platforms*,
  not the particular card a number came from, so where the measured GPU disagrees with the production
  one the production target decides. §4(c) is that case — an option ≈6% slower in `Float64` on the
  test card was kept, the reversal tracing to that card's `Float64` throughput rather than to the
  code. A carve-out claimed without a measured reason the test hardware is unrepresentative would
  just be the rule being ignored.
  The CPU path is not, however, a convenience for toy problems.
  It carries two roles that must not be confused. Development and small tests run on the CPU because
  that is where a workstation is, and at those grids performance rarely decides anything. The role the
  CPU path is tuned *for* is the other one: **a single large CPU node, running the resolutions that do
  not fit one GPU's memory.** Distributed and multi-GPU execution are out of scope
  (`docs/ARCHITECTURE.md` §1), so the ceiling is whatever one node holds — and on a CPU node that
  ceiling is high. A NAISS Arrhenius thin CPU node pairs two 128-core AMD EPYC 9755 processors with
  768 GB of DDR5, a fat node carries 3 TB, and one GH200 in the GPU partition offers 96 GB of HBM.
  Counting one scalar field in either representation as 8 bytes per grid point in `Float64` and a solver's
  live set at order 25 such fields, a single GH200 runs out near ``768^3`` while a thin CPU node
  reaches roughly ``1536^3`` and a fat node beyond it. The CPU therefore owns a band of resolutions
  no single GPU can reach, and inside that band it is the production platform, not a fallback. CPU
  multithreading (`docs/ARCHITECTURE.md` §9) is the mechanism that band rests on.
- **Measure before you optimize, and measure on the production platform.** No optimization is kept
  without a same-session side-by-side comparison showing it helps the GPU. This session's record is instructive: of the
  candidates that *looked* like wins, polynomial-eval tuning was already free, the periodic-wrap
  hoist made the default scheme *slower*, and point sorting — the textbook locality optimization —
  *regressed* the GPU gather. Only the one the measurement pointed at (loop order) survived (§4). The
  lesson is the method, not those verdicts: **both negative results were re-measured on current
  hardware in 2026-08-07 and reversed sign for the default scheme** — which is the same principle
  applied twice, since a verdict is only ever about the platform it was taken on (§4(c)).

- **A benchmark run owns the machine, and a number is not a result until it is explained.** Two
  obligations, both learned the hard way. **Run benchmarks alone** — no test suite, no documentation
  build, no second lane, nothing else on the host, and *especially* not while a GPU sweep is in
  flight. A device benchmark is host-bound at small grids (the synchronisation and, on the GPU path,
  the per-sample GC), so competing work inflates it by a roughly fixed amount per case; that alone
  invented a 2.2× "regression" at ``64^3``, an inflated canary baseline (the frozen per-host
  regression-guard suite `benchmark/regress.jl` judges against; §7), and a phantom "environment
  shift" attributed to a driver, all in one session. Check `uptime` and the GPU's utilisation before
  starting, and wait rather than measure into a busy box. **Then read what came back.** Running a
  sweep and reporting that it completed is not a measurement: compare against the previous archive
(the saved per-sweep result file a characterization run writes; §6),
  state which operations moved and in which direction, and account for every systematic movement
  before naming a cause. The cheapest discriminator is whether a penalty is *additive* or
  *proportional* — a fixed offset that is constant in absolute time while its ratio collapses with
  grid size is overhead, not arithmetic — and the second is whether the same commit range moved the
  other backend, since a real code regression is not confined to one device.

A scope note carried from the architecture: **platform optima diverge**, so every result below is
reported per platform, never as a single number. (The **L²/measure reductions** — `integral`, `inner`,
`l2norm`, `mean`, …; `docs/ARCHITECTURE.md` decision 18 — are bandwidth-bound streaming reductions
whose only subtlety is floating-point summation order, tolerance-tested rather than bitwise; they are
now part of the suite, §5.)


## 2. The performance model

What bounds each public operation class — the mental model a benchmark either confirms or refutes.

- **FFT transforms** (`to_physical`/`to_spectral`) → bound by **FFTW** (CPU) / **rocFFT**/**cuFFT**
  (GPU). The
  package adds only the normalization convention and the fiber-last layout (`docs/ARCHITECTURE.md`
  §3–4); the transform itself is the library's. Not something we tune — but the dominant cost of any
  spectral step, so it is benchmarked to track the libraries and our plan/layout overhead. The GPU
  libraries have no FFTW-style planner search, and the tuning surfaces they *do* have are currently
  out of reach from Julia — recorded here so nobody re-discovers them: cuFFT offers a patient-JIT
  plan property (LTO-finalized kernels — slower planning for faster execution) and LTO load/store
  callbacks that fuse user ops into the transform's own passes, none of it wrapped by CUDA.jl's FFT
  interface ([cuFFT docs](https://docs.nvidia.com/cuda/cufft/)); rocFFT has an offline tuner
  producing per-size/per-architecture solution maps, not surfaced by AMDGPU.jl. The one reachable
  lever is rocFFT's `ROCFFT_RTC_CACHE_PATH` kernel cache (an environment variable; see §7 gap 6).
- **Field algebra (M2 + M3), the differential operators, and convolution** → **memory-bandwidth-bound**. A
  fiberwise add, contraction, wavenumber multiply, kernel multiply (`convolve`), or arbitrary fiber map (`map!` — its adapter assembles the fiber in registers, adding no memory traffic over the named ops, so it tracks `det!`) reads and writes `O(1)` numbers per grid point
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
    grids we run the field is largely **cache-resident** (a 256³ scalar `Float32` field is 67 MB, inside the
    the retired card's 96 MB Infinity Cache), so there is little locality left to win.
  - **CPU**: bound by the cache hierarchy + hardware prefetchers, which *reward* locality — the
    opposite pull.

  This single fact — GPU wants spread, CPU wants locality — explains the platform-divergent results
  in §4 (loop order, sorting) and is the most important thing to internalize before touching the
  transfer. Hold it as a mechanism rather than a verdict: it explains why sorting *can* fail to pay
  on a GPU, and on the card that recorded that result it did. On the RX 7900 XTX the same experiment
  reversed for the default scheme (§4(c)), so the balance between the two pulls is a property of the
  card, not a constant.
- **Base-space motion** (decision 73) → four rows in the `transfer` class (`displace!` one- and
  three-term, the three-term torus arity, and `wrap!`): ``O(M)`` streaming over ``(M, 3)`` arrays,
  bandwidth-trivial beside a gather — 30–300× cheaper than the `CatmullRom` gather at the same point
  count, which is the boundary-costs-nothing claim the rows document. The fused wrap is free in
  **traffic** (the torus row's counts equal the cover row's, pinned by the pass audit) but not in
  serial **arithmetic**: floating-point `mod` is compute-visible where one core does all the work
  (``256^3``-derived points, `Float64`: torus 7.0 against cover 2.2 ms at ``t1``) and vanishes into
  bandwidth where the pass is memory-bound (1.41 against 1.24 ms at ``t8``; 91.5 against 64.6 µs on
  the RX 7900 XTX). The fusion itself pays exactly there: at ``t8`` the fused torus pass beats
  cover-then-`wrap!` by 33% (1.41 against 2.12 ms), and on the device by 22%.
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

- **No scalar indexing of device arrays** (invariant 6) — checked under `allowscalar(false)` in both
  the test and benchmark GPU runs, but **only when those are run**: they need a physical device, they
  are opt-in, they are not part of `Pkg.test()`, and CI is manual-only. It is a guarantee the design
  makes and a check that confirms it on demand — not a gate a regression cannot get past. A scalar
  index introduced during CPU-only work stands until someone runs the GPU suite.
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

The transfer-layer results below were measured on an **Intel i7-12700K** (8 P-cores) and on a
**since-retired AMD card**, `Float32`, ~1 point per 27 grid cells. That card is gone from the fleet and
from `RESULTS.md`; what is kept here is the qualitative finding in each case, not its absolute numbers,
and anything re-measured on the current cards (RX 7900 XTX, RTX 5070 Ti) says so explicitly. These are the
cumulative results of the transfer-layer optimization work; the benchmark suite (§5) regenerates the
tracked subset on demand.

**(a) Memory-bound, and smoothness is free.** Interpolation runs at ~12% of peak bandwidth at 256³;
cost scales with the stencil *volume* ``(2n{+}2)^3``, and the spline degree (`m`) is invisible — the
weight polynomials hide under memory latency. So pick the smoothness for accuracy, never for speed.

| gather scheme | stencil | GPU 256³ (621k pts) | throughput |
|:---|:---|:---|:---|
| `LalescuSpline(0,0)` (trilinear)   | 2³ = 8   | 0.51 ms                | 1230 Mpts/s |
| `LalescuSpline(1,1)` (Catmull–Rom) | 4³ = 64  | 3.55 ms                | 175 Mpts/s  |
| `LalescuSpline(3,m)` (Lalescu 8-pt)| 8³ = 512 | 28.0 ms (flat in `m`)  | 22 Mpts/s   |

**(b) Loop order — contiguous axis innermost (KEPT).** Iterating the contiguous `x` axis innermost
(stride-1 stencil access) vs `z`-innermost (stride ``N_x N_y``, the grid's ``x``,``y`` dimensions):

| | GPU 256³ | GPU 512³ (Lalescu) | CPU (Catmull–Rom / Lalescu) |
|:---|:---|:---|:---|
| speedup (x-inner / z-inner) | 1.6–1.7× | **3.9×** (785→203 ms) | 0.75× (i7-12700K, 2026-06 — **superseded**, see below) |

Kept x-inner as a **GPU-first** choice — the CPU's large caches absorb the strided access and its
`z`-inner form vectorizes better, but the GPU is the production platform. **Re-measured
(2026-07-22), and x-inner now stands on CPU evidence too:** decision 37 reopened this tiebreak
because its cache justification dies in the CPU production band, so the A/B was repeated at 512³
`Float64` (≈5×10⁶ points, the harness's one-per-27-cells density, Ryzen 9800X3D) — and the old
penalty does not reproduce there. The z-inner
nest gains only ~9–10% on the 4³ Catmull–Rom stencil and **loses 23%** (serial; 5% at eight
threads) on the 8³ Lalescu stencil, whose per-point working set no longer fits the reuse the old
measurement enjoyed. A per-backend loop order would also break gather bit-identity across
backends for at most a single-digit win on one scheme; the split is rejected and the x-inner nest
is the recorded choice for both platforms.

**(c) Rejected by measurement.** Two "obvious" optimizations that did not survive:

- **Wrap-hoist** (precompute the ``3(2n{+}2)`` periodic node offsets to kill inner-loop `mod`s):
  bit-identical, but **regressed the default Catmull–Rom by 10–14%** — the extra registers cut
  occupancy. Proof the kernels are memory/occupancy-bound, not ALU-bound. **RE-MEASURED 2026-08-07 and
  REOPENED: the sign is reversed for the default scheme, and the CPU was never tested.** Two kernels
  differing only in where the wrap is computed, verified bitwise equal, ratios hoisted-over-base:

(a table cannot render inside a list item, so the ratios are listed by scheme, in grid order
  ``64^3``, ``128^3``, ``256^3``, ``512^3``):

  - GPU trilinear — 0.969, 0.990, 0.978, 0.992
  - GPU `CatmullRom` — **0.698**, **0.713**, 0.829, 0.895
  - GPU `Lalescu(3,3)` — **0.516**, 1.122, **2.017**, (not run)
  - CPU trilinear — 0.897, 0.843, 0.884, 0.843
  - CPU `CatmullRom` — **0.368**, **0.433**, 0.584, 0.607
  - CPU `Lalescu(3,3)` — **0.276**, **0.297**, 0.359, (not run)

  Three things follow. **The recorded occupancy mechanism is right**, and ``R = 3`` on the GPU is where
  it shows: 24 registers per thread turns a ``2\times`` win at ``64^3`` into a ``2\times`` loss at
  ``256^3`` as the working set grows and occupancy becomes the binding constraint. **But it does not
  bite the default scheme on RDNA3** — `CatmullRom` hoisted is 10–30% *faster* at every grid, where the
  the retired AMD card recorded 10–14% slower. **And the CPU, never measured for this, wins hugely and
  everywhere** — up to ``3.6\times`` — which is what the mechanism predicts: a CPU thread has no
  occupancy to lose, and `mod` by a *runtime* grid size is a genuine integer division rather than a
  compiler-strength-reduced constant. That matters because the CPU path carries the beyond-VRAM grids
  (ARCHITECTURE.md decision 37). On both backends the benefit **shrinks as the grid grows** and the
  gather becomes more latency-bound, converging toward 1 without crossing it for ``W \le 4``.

  **Reopened, not adopted**, and the caveat is load-bearing: these are *standalone* kernels sharing the
  package's loop order but not its spline weights, and the hoist is written with `ntuple`, which need
  not compile like the original attempt did. The ratios establish that the trade is worth re-examining
  on current hardware, **not** what the package's own kernel would measure.
- **Morton particle sorting** (the textbook GPU-locality optimization): recorded as **0.5–1.0× on GPU**
  (gather) — concentrating access *kills* the memory-level/DRAM-bank parallelism the GPU needs, and the
  field is cache-resident anyway — though **2.2–4.4× on CPU**. **That gather result does NOT reproduce on
  the RX 7900 XTX (re-measured 2026-08-07), and the question is reopened.** Identical points, reordered
  only, at the same 1-per-27 density: Morton reaches **1.43×** (`Float32` ``128^3`` `CatmullRom`,
  105.7 → 73.6 µs) and **1.40×** (`Float32` ``256^3`` trilinear, 116.8 → 83.4 µs), and helps in three of
  four cells for `CatmullRom` — **the default scheme**. One cell clearly loses, `Float64` ``256^3``
  trilinear at ``0.74\times``. The original was measured on a since-retired card, so this is plausibly
  an RDNA2-versus-RDNA3 difference rather than a bad measurement; either way the recorded range no longer
  describes the hardware the project runs on. **It is reopened, not overturned**, and three things must
  hold before it is adopted: the ordering must be rebuilt as points move (measured host cost 31.7 ms at
  ``256^3``, paying back after 377 gathers; an on-device radix sort at an estimated 1–2 ms would pay back
  after 12–24, which is the number that matters and is *not* yet measured), the benchmark compares
  perfectly-sorted against perfectly-random while a real point set drifts between the two, and the
  **companion scatter result below is unaffected and remains the larger objection**. The companion **atomic-free node-centric
  scatter** is correct, conserving and bit-**deterministic**, but **6–24× slower on GPU**: at our
  sparse 1-per-27 density it traverses ~27× more (empty) reverse-stencil cells than the atomic
  scatter touches particles. Sorting + node-centric deposition is a *dense*-particle (PIC) technique;
  wrong for this regime. (If deterministic anterpolation ever becomes a hard requirement, it is the
  available — slow-at-sparse — answer.)
- **Storing the Helmholtz denominator as a precomputed derivative-squared wavenumber family**
  (rather than squaring ``a`` in-register — decision 42 dropped exactly these arrays, and after
  decision 47 restored the gated CPU loop the question was whether to bring them back). Measured
  head-to-head, in-register vs a stored ``a^2`` array, same projection otherwise: **CPU in-register
  wins everywhere** — Float64 ``+4\%`` (``128^3``/``256^3``), Float32 ``+10\%`` — because a register
  multiply of the already-loaded ``a`` beats an extra stride-1 load, and the stored form keeps three
  more arrays resident. On the **GPU** in-register ties in **Float32** but is ``\approx 6\%`` *slower*
  in **Float64** — and that lone reversal is a **test-hardware artifact, not a production signal**.
  The kernel is memory-bound (the F64/F32 time ratio is ``\approx 2.1\times`` at ``256^3``, tracking
  the ``2\times`` byte ratio, not any compute ratio); the reason dropping three squaring-multiplies
  helps in F64 is that the **RTX 5070 Ti's consumer-Blackwell FP64 runs at ``\sim 1/64`` rate**, so
  its FP64 ALU becomes co-limiting alongside memory and the extra multiplies tip it over. The
  production GPU is **GH200** (decision 37 — Grace-Hopper, **full-rate ``1{:}2`` FP64**), where that
  ALU has ``\sim 32\times`` the F64 throughput and cannot be co-limiting on a memory-bound kernel — so
  the F64 case is expected to behave like F32 (a tie), and the stored array's extra reads to help
  nowhere. That is an inference from the memory-bound measurement and the known FP64 rates, **not**
  measured on a GH200 (none on hand). Even taking the ``6\%`` at face value, capturing it needs a
  per-backend kernel split — re-introducing the two-bodies-in-sync coupling that produced the
  decision-47 dead-loop bug — for a win seen only on a card the production runs will not use. **Kept
  in-register**; the arrays stay dropped. This also retires the original (wrong) hypothesis that
  decision 42's in-register arithmetic cost the regression the canary flagged — it did not; the dead
  loop did (decision 47), and the arithmetic is free-to-favourable on every path that matters.

**(d) Anterpolation and contention.** The scatter costs ≈**2.2–2.7×** the gather (atomic
read-modify-write + a full-grid prescale). On that RDNA2 card `Float32` atomic-add was native but `Float64`
is emulated (CAS loop) ⇒ ≈**1.3–1.7×** slower; contention is worst at *moderate* clustering
(~2 pts/cell), not extreme (extreme stays cache-hot).

**(e) CPU vs GPU.** The transfer threads on CPU through `KernelAbstractions`' `CPU()` backend with no
code change, scaling ≈**4.5–5.7×** on 8 threads before the bandwidth plateau; the GPU is ≈**9–22×**
the 8-thread CPU (≈ the 384-vs-~60 GB/s bandwidth ratio for the heavy schemes, more for the light
ones via parallelism).

**(f) Allocation-free in-place operators — the GPU hot-loop discipline.** A pseudospectral solver
applies the differential operators thousands of times in its time loop, so any per-call scratch an operator
allocates internally matters. On the GPU it matters *a lot*: such scratch escapes Julia's GC (which
triggers on *host* memory, while the scratch is *device* memory), so the device pool grows every step
until VRAM fills and the run wedges (allocator spinning, GPU idle) or `hipMalloc` aborts — observed at
192³/256³. The fix made the in-place differential operators allocate **nothing**: `_squared_wavenumber_broadcast`
(the ``|k|^2`` coordinate) is returned **lazily** (an unfused `Broadcasted`, no ``O(N^3)`` array), and the
`helmholtz_projection!` / `laplacian!` / `inverse_laplacian!` kernels fuse their former temporaries into
the component broadcasts — each now allocates ``\sim 0`` bytes in place (measured; guarded by
`test/allocations.jl`), with identical results. Payoff: a **preallocated, in-place** pseudospectral DNS
step allocates nothing per step → **no manual `GC.gc()`/`reclaim`, flat VRAM**. The forced-HIT example
(`examples/gpu/rocm/HIST_ROCm.jl`, 192³ `Float32`, ``\mathrm{Re}_\lambda \approx 93``) sustains **≈ 34 ms/step**
(8000 steps, ≈ 270 s) on the retired card this way. *Discipline for consumers:* preallocate a workspace and
use the `!` forms with a destination distinct from the sources; the fiber `norm`/`lpnorm`
deliberately materialize one field and are the exceptions (`dev!` left the list when decision 39 fused
its trace into a register; use `maximum(abs, …)` for a CFL speed).
[Decision 24; decisions 38/39 later retired the alias-guard copies — aliased in-place calls are now
computed directly and stay zero-byte — and the decision-40 threaded reductions run on the same audit.]

**(g) Allocation-bounded radial diagnostics — the same GC trap, in the binning.** The same device-GC
hazard as (f) lived in the *diagnostics*. The `radial_spectrum` / `radial_correlation` reductions binned by looping over
the ``|k|``- (or ``|r|``-) shells and reducing a masked broadcast per shell. The shell count scales with
the grid (``\approx \sqrt{3} N_a/2``, ``\approx 220`` at ``N_a = 256``, with ``N_a`` the per-axis point
count), and each iteration allocates a
full-grid mask — and, because a `mapreduce` over a `Broadcasted` *materializes* on this GPU stack rather
than fusing, the masked product too: ``O(N)`` full-grid temporaries per call, which the host-triggered GC
does not reclaim. A single ``256^3`` `radial_correlation` snapshot churned several GB and wedged a 12 GB
card at the *first* snapshot. The fix bins in a **single scatter-add pass** — one portable
`KernelAbstractions` + `Atomix` histogram kernel atomically accumulating each element into its shell — so
per-call temporaries drop from ``O(N)`` to ``O(1)``. Correctness is unchanged (same per-shell sums; CPU
`test/reductions.jl` + GPU parity hold). Payoff: the ``256^3`` `Float32` forced-HIT example
(``\approx 87`` ms/step) now runs to completion at a flat ``\sim\!6`` GB
(``\approx 8`` GB peak) through its snapshots, where the per-shell form wedged at the first one. The scatter contends on the small accumulator set, acceptable for an *occasional* diagnostic
(not a per-step call); a privatized histogram is a possible future optimization. [Decision 25.]
Decision 34 later fused the remaining ``O(1)`` staging — the shell-index, magnitude, and weighted
planes — into the binning kernels themselves (shell, fiber contraction, and Parseval weight derived
per element from the index; the shell count analytic from the corner), taking `radial_spectrum` from
three staged spectral planes per call to its ``\sim\!1.4`` KB accumulator and leaving
`radial_correlation` only its substance (the power field and the allocating inverse transform).

**(h) FFTW `ESTIMATE` can badly mis-plan single-precision transforms — pass `MEASURE` for production.**
`FieldTransformPlans` builds its FFTW plans with the default `ESTIMATE` flag (instant, but it *guesses*
the algorithm instead of timing candidates). On a Ryzen 9800X3D (Zen 5, stock FFTW 3.3.11) that guess is
~5× too slow for the 256³ `Float32` transforms — in **both** directions, at every thread count — because
its hardcoded single-precision codelet heuristics misjudge this CPU generation. Rebuilding with
`FFTW.MEASURE` (a one-time, timed plan search) fixes it, and the planning cost (seconds) amortizes over a
long run. Pure in-place transform, 256³ `Float32`, minimum time:

| threads | c2r (`to_physical!`), `ESTIMATE`→`MEASURE` | r2c (`to_spectral!`), `ESTIMATE`→`MEASURE` |
|:---|:---|:---|
| 1 | 170 → 33.3 ms (**5.1×**) | 168 → 33.6 ms (**5.0×**) |
| 4 | 47.3 → 14.0 ms (**3.4×**) | 46.3 → 12.9 ms (**3.6×**) |
| 8 | 27.5 → 12.0 ms (**2.3×**) | 26.2 → 10.2 ms (**2.6×**) |

The gain narrows as threads are added — the planner's advantage is largest where a single core is doing
all of the work — so the headline is the single-threaded figure. (Read from the current `RESULTS.md`
rather than re-measured for this table. The earlier printed figures were a one-off snapshot whose t4/t8
`MEASURE` times ran 35–75% faster than anything in the committed archive, and the surrounding prose
promises this table tracks the live record.)

It is size- and CPU-specific (128³ is fine; the i7-12700K shows no such inversion) — a classic `ESTIMATE`
pitfall, not a package issue.

**The *inversion* is Zen 5's; the *mis-planning* is not — corrected 2026-08-23 from a corpus-wide sweep
of the committed table.** Reading `ESTIMATE`/`MEASURE` as a ratio rather than looking for a
`Float32`-slower-than-`Float64` ordering, the i7-12700K mis-plans single precision too, at
``256^3``/t1: **2.13×** (`to_physical scalar`), **2.40×** (`to_spectral scalar`) and **2.10×**
(`to_physical vector`), against ``5.17``/``5.07``/``4.10×`` on the 9800X3D. Double precision is
``1.20``–``1.46×`` on the i7 and ``1.15``–``2.83×`` on the Ryzen. So the effect is **precision-specific
on both microarchitectures** and merely three times worse on Zen 5. What is genuinely Zen-5-only is that
it is severe enough to *flip the ordering* — on the i7 the `ESTIMATE` `Float32` transform is still
faster than its `Float64` twin (``88.0`` against ``127.3`` ms), so nothing looks wrong unless the
`measure` twin is consulted, which is exactly why the narrower attribution was recorded. The sentence
above stays true as written about the inversion; what changes is that "misjudge this CPU generation"
must not be read as "and only that generation", and a consumer on **any** x86 CPU doing long
single-precision runs should pass `MEASURE`.

*This widens rather than narrows the ARM concern in §7 gap 8*, which cites this finding as a Zen 5
artifact among the reasons no x86 CPU result transfers to `aarch64`. An `ESTIMATE` heuristic that
mis-plans single precision on two unrelated x86 microarchitectures is more likely to do so on a third
platform, not less — so `MEASURE` should be in the first Arrhenius measurement, not discovered there. The default stays `ESTIMATE` (cheap, deterministic, right for
tests and short runs); the escape hatch already exists,
`FieldTransformPlans(phys, spec; fft_flags = FFTW.MEASURE)` (or `FFTW.PATIENT`). `MEASURE` overwrites its
input arrays while planning, so build the plans on scratch fields before seeding data. The forced-HIT CPU
example (`examples/HIST_CPU.jl`) now plans with `MEASURE`. **Update (2026-07-21, the 512³ sweep):** the
mis-plan persists into the CPU production band — at 512³ the `ESTIMATE`d scalar `Float32` c2r ties the
`Float64` one to three digits (402.297 vs 402.195 ms, t8), single precision buying *nothing* — so the
`RESULTS.md` 9800X3D `Float32` FFT columns at 256³–512³ should be read as `ESTIMATE`-planned (the package
default, deliberately what the suite measures), not as the CPU's `Float32` capability.
**Update (2026-07-22):** the pair is now a standing measurement — every CPU FFT row in the suite carries
a `measure` twin planned with `FFTW.MEASURE` (built on scratch fields, per the overwrite caveat above), so
`RESULTS.md` shows the `ESTIMATE` experience and the tuned production path side by side and this finding's
delta is re-measured per host, size, and type on every sweep. GPU rows have no twin — the device FFT
libraries take no planner flag. First sweep with the twins (12700K): even this host — no `Float32`/`Float64`
*inversion* — leaves 1.7–1.8× to the planner at ``256^3`` `Float32` single-threaded (1.2–1.4× elsewhere at
t1), while at t8 the pair is within jitter: the planner choice matters most exactly where a long serial
production run lives, and threading largely hides it.

**(i) A fused reduction needs a different shape per backend — get that right and it wins on both.** The
mapped forms (decision 30) reduce a function of the fiber value at every base point without
materializing it. A single formulation cannot serve both devices, and the first implementation shipped
the GPU's shape to the CPU, where it ran *slower* than the materializing route it was meant to replace.
Splitting it fixes that. Measured with the **same map on both sides** (`mean(det, A)` against
`mean(det(A))`, ``N = 128``, `Float64`):

| backend | fused | materialize + reduce | |
|:---|:---|:---|:---|
| CPU (vectorized blocked loop) | **5.1 ms**, 0 B | 13.0 ms, 16.8 MB | fused 2.5× faster |
| GPU, RX 7900 XTX (fused `Broadcasted`) | **0.55 ms**, 0 B | 0.69 ms, 16.8 MB | fused 1.3× faster |

Decomposing the CPU side shows why one shape could not do both, and it is not the layout:

| step | ``N = 128``, `Float64`, 1 thread | factor |
|:---|:---|:---|
| `maximum` over a contiguous array | 0.56 ms | baseline |
| reducing a lazy `Broadcasted` instead (one stream, no gather) | 3.1 ms | **5.6×** |
| three strided streams instead of one | 6.4 ms | 2× |
| building the `StaticArray` per base point | 5.6–6.4 ms | free |
| `LinearAlgebra.norm` instead of naive ``\sqrt{\sum_i u_i^2}`` | 27.7 ms | **4.3×** |

The dominant term is the reduction losing its vectorized blocked loop, which costs more than the extra
section of traffic that materializing pays — so on a CPU the fix is simply not to reduce a lazy
expression: the implementation runs its own blocked loop over the component arrays instead. A GPU has no
such loop to forfeit (thread-parallel, bandwidth-bound), so index arithmetic hides behind memory latency
and the skipped section write and read-back is pure profit; it keeps the fused `Broadcasted`. Blocking
the CPU loop pairwise, as Base's own reduction does, additionally makes it the **most accurate** route
(relative error ``1.2\times10^{-16}``, against ``3.7\times10^{-15}`` for the lazy form and
``1.6\times10^{-16}`` for materializing). The strided gather that fiber-last layout (invariant 3) forces
contributes only ``2\times``, and the `StaticArray` build is free.

The last row is a **measurement trap worth recording**: `LinearAlgebra.norm` on a fiber uses the
overflow-safe scaled 2-norm, ``4.3\times`` the plain magnitude the fieldwise `norm` evaluates. So
comparing `maximum(norm, u)` against `lpnorm(u, Inf)` varies the algorithm *and* the route together and
reads as a fusion penalty that is not the fusion — given the same formula the fused form is 1.8 ms
against 4.2 ms. This analysis reported the confounded number twice before decomposing it. Vary one thing
at a time here.

Three formulations that look equivalent are not, and each silently reintroduces allocation: a
multi-argument `mapreduce` (fused by `GPUArrays`, but materializing a full section on the CPU), an
anonymous vararg closure (uninferrable component count), and a forwarded `Function`-typed argument left
untyped in the signature (Julia declines to specialize on it). All three are pinned at zero bytes by
`test/allocations.jl`. [Decision 30.]

**(j) A multi-output kernel beats broadcast recomputation — the one-pass Helmholtz projection.** The
projection writes three output components that share one intermediate (the longitudinal factor
``a_j\hat u_j/(a \cdot a)``, with ``a`` the derivative wavenumber — decision 42's exact
denominator), which a broadcast cannot express: the three-broadcast form recomputed the
shared dot product per component — nine component reads and three divisions per mode for three
writes. The one-pass `KernelAbstractions` kernel (decision 32) reads each source component once,
computes the factor once, and writes all three components — and, reading a whole mode before writing
it, serves the aliased in-place call with no guard temporary. Measured on the 12700K
(``64^3``–``128^3``, `Float64`; the fused-vs-three-broadcast ratio), against the KA-on-CPU path this
operation ran before decision 40 replaced it with a gated CPU loop of the same shape (decision 42
briefly severed that loop and decision 47 restored it — see the canary lane, §7 gap 3):

| threads | ``64^3`` | ``128^3`` |
|:---|:---|:---|
| 1 | 3.9× | 4.1× |
| 4 | 6.5× | 2.7× |

Two costs worth recording. The KA launch allocates a small **size-independent** host-side bookkeeping
(~1.5 KB serial, ~7 KB at four threads — task spawning), where the broadcast route allocated
~0.3 KB; the allocation audit's fraction-of-a-field threshold absorbs it, and the field-sized guard
temporary of the aliased call (~0.84 MB at the audit size, IT's 3.19-unit transient at ``256^3``) is
what is gone. And the kernel-composed form (`helmholtz_projection!(…, kernel)`, decision 32) adds one
scalar-field read to the same pass — measured +6–16% over the plain projection, against ~+50% for the
separate `convolve!` pass it replaces.

**(k) A lazy kernel is a reuse question, not a free win — and the naive A/B forgets the build pass.**
The exponential family (decision 33) evaluates ``\exp(c|k|^2)`` per mode instead of reading a stored
kernel field. Whether that pays depends on what the stored route would actually do:

| comparison (vector field) | CPU ``128^3`` F64, 4 threads | GPU ``256^3`` F32, RX 7900 XTX |
|:---|:---|:---|
| lazy vs stored kernel, kernel **fixed** | 9.1 vs 5.4 ms — stored 1.7× | 0.94 vs 0.87 ms — stored 1.08× |
| lazy vs rebuild + apply, exponent **varies** | comparable (the rebuild pays the same `exp`) | 0.94 vs 0.46 + 0.87 ms — **lazy 1.4×** |
| two-operand fused vs sequential `combine!` + `convolve!` | 9.9 vs 11.3 ms — **fused 1.14×** | 1.11 vs 1.68 ms — **fused 1.5×** |
| kerneled `combine!` vs the sequential pair | 7.4 vs 11.3 ms — **fused 1.5×** | 1.13 vs 1.68 ms — **fused 1.5×** |

Three lessons. The *fusion* forms (the bottom two rows) win on both backends — they save a
destination write and re-read, which no amount of `exp` cost eats. The *lazy-vs-stored* single-operand
trade is governed by reuse: a fixed kernel amortizes its build and then wins on pure bandwidth
(the per-mode exponential costs more than the field read it saves — dramatically so on CPU, where
`exp` is expensive and the broadcast re-evaluates it once per fiber component); a varying exponent
forces the stored route to pay a full build pass per change, and the lazy form then wins. And the
measurement trap: an A/B of `exponential_convolve!` against a prebuilt `convolve!` silently compares
against a route whose build pass happened outside the timer — state which reuse pattern is being
measured before quoting a ratio. A possible future optimization — hoisting the exponential over the
fiber in a mode-loop kernel, the decision-32 shape — would cut the CPU vector case's threefold `exp`
re-evaluation; it waits for a CPU-bound consumer (the audits' consumer runs GPU-first).
That deferral predates decision 37 and should be read against it: "GPU-first" no longer settles a CPU
cost by itself, since the CPU path's tuning target is now a full cluster node running grids past one
GPU's memory. A threefold `exp` re-evaluation per fiber is exactly the kind of per-component redundant
work that is nearly free while a field is cache-resident and is not once it is not. The item stays
deferred for want of a consumer, not because the cost is deemed unimportant — and it wants a
node-scale CPU measurement before it is ranked.

**(l) The threaded `_assign!` inner loop runs at ~8.6 GB/s per thread — mid thread counts sit *above*
serial on the streaming ops.** Found by the first 512³ CPU sweep (2026-07-21) and visible, unnoticed, in
every committed CPU column before it: on **both** measured CPUs, at **every** grid size, `add!`/
`gradient!`/`symmetric_gradient!` and the rest of the `_assign!`-routed streaming family run *slower* at
2 and 4 threads than at 1, with 8 threads only marginally recovering (9800X3D `add!` scalar `Float64`,
t1→t2→t4→t8: 64³ 40 µs → 368 → 185 → 95; 512³ 83.9 ms → 187.6 → 94.2 → 73.6). The serial path is
`materialize!` — SIMD, ~41 GB/s on one Zen 5 core, already near the desktop's DRAM ceiling — while the
threaded path (`_assign_threaded!`) indexes the fused `Broadcasted` **element by element through a
`CartesianIndex`**, which does not vectorize: measured single-threaded at 512³, 375 ms against
`materialize!`'s 79 ms, a **4.7× per-core penalty**. Every threaded lane is that loop divided by its
thread count until the aggregate hits DRAM (375/2 = 187.5, 375/4 = 93.8 — reproducing the sweep cells to
three digits). Two corollaries, both measured: **linear indexing plus `@simd` — the alternative the
implementation's own comment contemplates, legal now that the compat floor is 1.12 — does not help**
(365 ms; `Broadcasted` `getindex` stays scalar either way), so the fix is not an index-style swap but
per-chunk `materialize!` over sliced broadcast arguments; and the ops that thread through **other**
routes are unaffected (FFTW threads itself; the `KernelAbstractions` kernels partition natively —
`anterpolate!` scales 3.4 s → 562 ms, t1→t8, in the same sweep). Consequences while the fix is pending:
on a 2-channel desktop, `JULIA_NUM_THREADS=1` is the *fastest* CPU configuration for the streaming ops
below ~256³ and within ~15% of t8 at 512³; on the many-channel node of decision 37
(`docs/ARCHITECTURE.md`), where serial is ~1/12 of socket bandwidth, the slow loop still saturates the
socket eventually but wastes ~4.7× the cores doing it. The threading *tests* are unaffected (bitwise
identity holds — the loop is slow, not wrong). **Fixed (2026-07-22, decision 38):** the threaded path
now runs the standard fused `materialize!` per contiguous slab of the largest axis, so each slab
executes the same SIMD kernel as serial — measured on the probe, 512³ `Float64` `add!`: t2
187.7 → **73.3 ms** (the DRAM ceiling, previously reached only at t8), t8 unchanged at the ceiling,
and 64³ t8 95 → 28 µs (threading now *wins* at small sizes). Both hosts' CPU columns in
`RESULTS.md` are re-swept post-fix (Enteropia and Aiporetne, 2026-07-22); pre-fix t2–t8 numbers
survive only in superseded archives and measure the retired loop.

**(m) `exp` producing a `Float32` subnormal costs ~16× per element — and a fixed benchmark exponent
measured exactly that.** On x86 an arithmetic result in the subnormal band — between the smallest
normal ``\approx 1.2\times10^{-38}`` and the underflow-to-zero point ``\approx 1.4\times10^{-45}``
for `Float32` — is produced through a microcode assist: measured 37.1 ns/element, against 2.4 for a
normal result and 1.2 for a full underflow to exact zero. For the lazy kernel
``\exp(c\lvert k\rvert^2)`` the affected arguments, ``c\lvert k\rvert^2 \in [-103, -87]``, form a
spherical shell in ``k``-space; the benchmark's former fixed ``c = -0.1`` put ~11% of a ``64^3``
grid's modes inside it, inflating the `Float32` `exponential_convolve!` cell to 2.7–3.1× its
`Float64` twin (the blend ``1 + 0.11 \times 15 \approx 2.6``; the sublinear ``64^3 \to 128^3`` size
step was the tell), so the row measured libm underflow handling, not the operation. The benchmark
coefficient is now scale-aware — ``c = -4/\lvert k\rvert^2_{\mathrm{corner}}``, the kernel spanning
``[e^{-4}, 1]`` at every size — verified to close the ``64^3`` type gap from 3.0× to 1.05–1.08×;
cells swept before 2026-07-23 carry the old exponent. The operation keeps exact semantics (no
flush-to-zero guard): `Float64`'s band (arguments below ``\approx -708``) is unreachable by physical
kernels, GPUs flush subnormals natively, and a `Float32` CPU consumer with a genuinely deep kernel —
an aggressive Gaussian filter — pays the shell honestly; the `exponential_convolve!` docstring
carries the caveat.

**(n) The shell-binning atomics contend on an accumulator smaller than a dozen cache lines —
threading inverts at small grids, and `Float32` bins double the collisions.** The radial family
(`radial_spectrum`, `radial_correlation`, the co-spectra) ends in one `Atomix.@atomic` add per
stored mode into a packed bins array of 56 (``64^3``) to 223 (``256^3``) entries — on x86 a CAS
loop that must own the bin's cache line exclusively, so true same-bin contention (serialized
retries) stacks with false sharing (different bins on one 64-byte line). A model scatter (4M adds,
eight threads) reproduces the table: serial 4.6 ns/element; threaded over a ``64^3``-scale packed bin
array 17–19 ns —
threading *quadruples* the per-add cost, the table's ``64^3`` inversion (t8 1.3–1.6× slower than
t1); `Float32` packed at 223 bins runs 1.51× `Float64` (16 bins per line versus 8 — the table's t8
type reversal, 1.44–1.5×); one-bin-per-line padding equalizes the types and finally scales at 223
bins (2.7–2.8 ns) yet still trails serial at the ``64^3`` count (same-bin collisions, ``\approx 8/56``
per add). At
production sizes the mode reads are DRAM-bound and the contention hides, so the anomaly is confined
to small-grid diagnostics costing single-digit milliseconds — recorded, not fixed. Read the ≈48×
`Float64` radial gap at both of its levels, which are not in tension: its **mechanism** is vendor
hardware — RDNA emulates the global `Float64` atomic with a CAS loop where NVIDIA has it natively,
which is why the gap collapses to 1.11× in `Float32` (§6) — while its **exposure** is an addressable
implementation gap, because the global atomic scatter has no per-workgroup pre-reduction, the
standard technique for exactly this kernel shape, and with one the emulated atomic would be hit a
few times per workgroup instead of once per mode. Every other cross-vendor ratio in this document
sits in the 1.5–4× band a bandwidth ratio explains; this one is an order of magnitude larger because
the un-pre-reduced kernel runs straight into the one operation the two vendors implement most
differently.
Candidates when a
consumer's cadence makes it matter: bin padding (backend-uniform; kills the `Float32` reversal, not
the ``64^3`` inversion); per-thread private bins with an ordered merge on CPU (kills both *and*
makes the CPU binning bitwise thread-invariant, retiring one of `docs/ARCHITECTURE.md` §9's two
tolerance-tested accumulators, at the price of splitting the deliberately single-source
KernelAbstractions kernel); workgroup-local bins on GPU — the same redesign's lever on the ~48×
CUDA-over-ROCm `Float64` radial gap (§6 and §7 measure it at 48–49× on the current archive), which is this kernel under RDNA3's CAS-loop `Float64` atomics.


**(o) An axis-factored kernel is bandwidth-bound like the stored kernel it replaces, so what decides
its speed is how the per-axis product is INDEXED and how the launch is SHAPED — not how few streams it
reads.** Decision 50 stores a separable kernel (`SeparableKernel`) as three ``O(N)`` per-axis factors instead of an
``O(N^3)`` field, which removes one field-sized stream from every application (three down to two). That
alone predicts a speed-up; it does not deliver one, and the two failed attempts are the instructive
part. Handing the lazy product to the **linear-indexed** fiberwise executor makes every element convert
a linear index to a cartesian one — an integer division, emulated on a GPU — measured **0.29×** a stored
kernel (vector, ``256^3``, `Float64`, RTX 5070 Ti). Replacing that with a hand-written **three-dimensional**
`KernelAbstractions` kernel removed the conversion and gained nothing (0.78× vector) while *halving* the
scalar case to **0.55×**: the folded axis is ``N/2 + 1`` — **129** at ``256^3`` — so a three-dimensional
launch fragments warps against a row length that is not a multiple of the warp size, where the stored
path's flat launch stays coalesced. What works is the plainest form, **one flat broadcast** over the
whole section with the factors carrying singleton axes (they extend along the remaining mode axes and
along the fiber): cartesian indexing *and* a flat, coalesced launch.

The **CPU needs the opposite route**, and the same measurement says so. That five-operand broadcast,
three of whose operands carry singleton axes, does not vectorize: it ran at a fixed ~330 M elements/s —
the *same rate* in `Float32` as in `Float64`, the signature of an element-bound loop rather than a
bandwidth-bound one. So the CPU takes a gated hand-written twin (§9's kernel-pair shape): the two outer
factors hoisted to scalars, leaving an inner pass over contiguous storage for `@simd`. Loop order in
that twin is worth stating, because the obvious choice is wrong — with the fiber components innermost
the pass jumps between component blocks every row and the *threaded* case fell to 0.98×; walking each
component's block start-to-end inside a thread's slab restored 1.14×.

Ratios against the stored kernel (vector field, ``>1`` = axis-factored faster):

| | GPU F64 | GPU F32 | CPU t1 F64 | CPU t1 F32 | CPU t8 F64 | CPU t8 F32 |
|---|---:|---:|---:|---:|---:|---:|
| ``64^3`` | 0.98 | 0.95 | 0.44 | 0.46 | 0.62 | 0.52 |
| ``128^3`` | 0.79 | 0.83 | 0.66 | 0.45 | **1.44** | 0.50 |
| ``256^3`` | 0.78 | **1.01** | 0.91 | 0.54 | **1.15** | **1.18** |
| ``512^3`` | — | — | 0.85 | 0.60 | **1.12** | **1.12** |

The trend is the point: **the ratio improves with grid size on the CPU**, because the saving is
bytes not moved (two streams instead of three) while the cost is per-element arithmetic. The GPU column
does not follow it — the ratio there sits near parity at ``64^3`` and drifts slightly down, a device
being bandwidth-bound at every size in this range rather than crossing out of cache. Small grids sit
in cache — the stored kernel's extra read is nearly free there, so the axis-factored form only pays for
its arithmetic and loses. Past cache the pass becomes DRAM-bound and the missing stream wins: at
``256^3``–``512^3`` threaded, the CPU is **1.12–1.18× faster**, and `Float32` on the GPU reaches parity.

The `Float64` GPU column is a **consumer-card artifact, not the production case**. The two extra complex
multiplies are 12 FP64 flops per element; the gap at ``256^3`` is 363 µs for 305 MFLOP, an implied
**0.84 TFLOP/s** — precisely the RTX 5070 Ti's 1/64-rate FP64. On the decision-37 GH200 (full-rate FP64)
the same work is ~9 µs, so `Float64` there should track the `Float32` column and land near 1.15×.

The same split applies to the kernel-composed `combine!`, which initially kept the linear-indexed
route and so ran the rejected shape at ``R \ge 1`` — measured at roughly a third of the stored
kernel's speed until it took the cartesian routes as well, after which it is **1.1×** *faster* than
the stored kernel at ``256^3`` threaded. A kernel storage class is only as fast as the slowest entry
point that accepts it.

**The radial class of decision 51 (`RadialKernel`) takes the same two routes, for the same reason.** A kernel depending
on the mode only through ``|k|^2`` stores no coefficients at all — a symbol closure and three references
to the squared-wavenumber rows — so it removes the same field-sized stream, and its arithmetic is one
extra add plus the symbol evaluation. Everything above transfers: a device takes the flat broadcast, a
CPU takes the gated component-major twin, and both index the wavenumber axes cartesian. The one
addition is an ordering constraint the separable class does not have. The squared wavenumber must be
summed ``(\kappa_1^2 + \kappa_2^2) + \kappa_3^2``, matching the left association the broadcast itself
uses, or the compressed and stored paths agree only to rounding rather than bit for bit — and the suite
asserts the stronger form.

The symbol is a **closure, and it must capture values rather than a type**. Capturing an element type —
writing `one(T)` inside the closure with `T` closed over — makes the captured object a `Type`, which is
not a bitstype, and a GPU launch rejects it outright. Hoist the constants to values before the closure
is built.

Three rules generalize. **Reach for the broadcast route before a hand-written kernel on a device** —
§9's execution-route policy, here vindicated by measurement, since Julia's broadcast machinery chose a
better launch than the hand-rolled kernel did. **A broadcast over singleton-axis operands is the
exception on a CPU**, where it does not vectorize and a hand-written twin is worth its keep. And when a
fused pass underperforms, **measure the launch shape and the traversal order before blaming the
arithmetic** — both failed attempts here were layout problems wearing an arithmetic costume.

**(p) CPU FFT at the larger grids moved 20–50% between the 2026-07-30 and 2026-08-05 sweeps on
`Enteropia`, and the 2026-08-07 `Aiporetne` control says the cause is specific to that host.** The full
re-sweep of the 9800X3D lanes found a cluster confined to the `fft`
class: at ``256^3`` `Float64`, `-t1` `to_physical scalar` went 83.8 → 116.0 ms and `to_spectral scalar`
171.9 → 207.4 ms; `-t8` saw `to_spectral vector` at ``128^3`` go 11.3 → 16.7 ms. **It is reproducible,
not jitter** — three standalone probes of the ``256^3`` `Float64` rows returned 115.8 / 116.8 / 116.5
and 208.3 / 209.3 / 211.1 ms, a spread under 1%.

What it is *not*, each checked rather than assumed: not a package change (the transform path has zero
changed code lines between the two commits — the 136 insertions in `Fields.jl` are docstrings and
decision 61's type parameter); not FFTW (the `libfftw3` artifact dates from 2026-05-25 and
`benchmark/Manifest.toml` from 2026-07-22, both predating the older archive); not Julia (1.12.6 for
both sweeps); and not a machine-wide slowdown — the other **596** rows of the same lanes have a median
drift of ``-0.12\%``, so only the FFT rows moved. It is CPU-only: the cuFFT lane shows no `fft` row
among its movers. The one difference the record does show is a reboot between the two sweeps
(current kernel `7.0.0-28-generic`), and no pre-reboot kernel or microcode version was recorded, so a
platform change can be neither confirmed nor excluded on that host alone.

**The control ran on `Aiporetne` (i7-12700K) on 2026-08-07, and at the larger grids the shift does not
reproduce.** That host's lanes were last measured 2026-07-22, so the comparison spans an even wider
commit range than the one that produced the finding. Across its **192** `fft` rows (four thread lanes ×
48) exactly **one** row at ``256^3`` moved slower, by ``+1.0\%``, against `Enteropia`'s ``+38\%`` on the
row the finding names; the per-lane medians run ``-4.5\%`` to ``-6.8\%``. State this precisely rather
than as "nothing got slower", which a first pass over a single lane wrongly suggested: **23 of the 192
rows did move slower**, but all except that one ``256^3`` row sit at ``64^3`` or ``128^3``, and the three
exceeding 20% (``+46.8\%``, ``+23.5\%``, ``+22.2\%``) are all small-grid cells at `-t4`/`-t8`, where
thread overhead dominates a workload of well under a millisecond and the scatter is largest. The finding
is about the *larger* grids, and there the two hosts moved in opposite directions over overlapping
periods.
`Aiporetne` runs kernel `7.0.0-28-generic` — **the same version `Enteropia` recorded after its reboot** —
so if a kernel or microcode change were responsible, this host should show the slow vintage and instead
shows the fast one. That exonerates the platform version specifically, which is stronger than a bare
failure to reproduce, and leaves the cause in `Enteropia`'s own machine state.

**The control's own movement is equally unexplained, and saying so is the point.** `Aiporetne`'s `fft`
rows did not merely fail to slow — they got materially *faster*, by 5–46% at the larger grids, with the
`FFTW.MEASURE` twins moving most (``256^3`` `Float32` `to_spectral scalar measure`, `-t1`: 64.8 → 35.0
ms, a ratio of ``0.54``). No package change touches the transform path over that range either. So both
hosts show an `fft`-class-confined shift across a re-sweep, in opposite directions, with unrecorded
platform state on both sides. The conservative reading is not that one host regressed and the other did
not, but that **`fft` timings are not stable across sweeps on either host** while the conditions of a
sweep go unrecorded — which is exactly what the vintage caveat exists to express. Whatever moves them is
below the package, and neither direction has been traced. **Treat `fft` rows as comparable only within a
vintage**, and treat a cross-vintage `fft` comparison as uninformative rather than as evidence.

**Studied on `Aiporetne`, 2026-08-07: five candidates eliminated by measurement, and the instrument
gap closed.** The `fft` class is the only one whose cost depends on a plan chosen at runtime, so it is
the natural suspect, but each mechanism was tested rather than argued:

  - **Cross-process variation is not it.** The finding's own row (`to_physical scalar`, `Float64`,
    ``256^3``) measured in eight separate processes spans 156.1–165.0 ms — a spread of ``1.06\times``,
    against the 20–50% to be explained.
  - **Hybrid core placement is not it, but it IS a latent hazard.** The 12700K is 8 P-cores plus 4
    E-cores. Pinned to an E-core the same row measures **255.8–266.1 ms against 156.5–164.3 ms on a
    P-core — ``1.63\times``** — easily enough to produce the effect. It does not, because every
    unpinned sample landed in the P-core range: Linux reliably places a single compute-bound thread on
    a P-core. **A sweep run under `taskset`, a cgroup, or a systemd slice that admits E-cores would
    read 1.6× slow with nothing else changed**, which is worth knowing before anyone constrains one.
  - **Transparent huge pages are not it.** THP is in `madvise` mode with `AnonHugePages: 0`, so the
    arrays are never huge-page backed on this host — the mode cannot vary between sweeps because
    nothing requests it.
  - **Memory fragmentation is not it.** `buddyinfo` shows 26,625 free order-10 blocks after 22 hours
    of uptime, so large allocations are not falling back to scattered pages.
  - **Plan selection is not it.** With `fft_flags` unset — what every plain row uses — plans are built
    with FFTW's default `ESTIMATE`, a deterministic heuristic, not the timed search `MEASURE` performs.
    The `measure` twins are the only rows whose plan choice can vary from run to run.

**What remains is state that persists across a session, and the finding could not be attributed
because none of it was recorded.** That is an instrument gap rather than a mystery, and it is now
closed: `characterize.jl` stamps `kernel`, `microcode`, `cpu`, `governor`, `no_turbo`, `smt`, `thp`,
`julia` and `threads` into every archive beside the commit and date, so the next occurrence is a diff
rather than a reconstruction. `Aiporetne`'s state at this sweep: kernel `7.0.0-28-generic`, microcode
`0x3e`, governor `powersave` with turbo enabled, SMT on, THP `madvise`. Note the governor in
particular — `powersave` on `intel_pstate` still boosts, but its ramp depends on recent load history,
which is exactly the kind of cross-sweep state nothing was capturing.

**RESOLVED 2026-08-09 on the host that showed it: the shift was a ONE-OFF, not a persistent state
change.** `Enteropia`'s CPU lanes were re-swept against the 2026-08-05 archive over an interval whose
`src/` edits are **docstring text only** — five files were touched by a documentation pass, and
stripping docstrings and comments from both revisions leaves **zero** differing executable lines — so
anything that moved would be platform or measurement. Nothing moved. The `fft` class is flat — per-lane medians ``-1.4\%``, ``-1.2\%`` and ``-1.1\%`` at `-t1`,
`-t2` and `-t4` — and at ``256^3``, where the event was ``+20``–``50\%``, the medians are ``-3.7\%``,
``-6.5\%`` and ``-1.2\%``. Every other class is flat on the same lanes, 600 rows each, with overall
medians of ``+0.0\%``, ``-0.2\%`` and ``-0.2\%``.

**What that licenses, and what it does not.** The instrument reproduces itself across four days on
this host, so the harness is sound and the 2026-08-05 `fft` reading was a transient of that particular
sweep rather than a lasting change in the machine — which is also why the `Aiporetne` control found
nothing to confirm. It does **not** identify the transient's cause, and it cannot: the state that would
have named it was never recorded, and the episode is over. The finding therefore closes as
*unattributed but bounded* — a single sweep's `fft` column, on one host, not reproduced before or
since. The stamping is the durable outcome: these three lanes are the first archives in the tree
carrying platform state, so a recurrence becomes a diff. The `-t8` lane could not be re-measured at
all, for the unrelated reason in (q).

**(q) FFTW's threaded executor segfaults at `-t8` — REPRODUCIBLE on `Enteropia`, and the lane completes
only when split across processes.** The heading below and the 105-trial non-reproduction that follows it are
kept as the record of how this looked before 2026-08-09; both are now superseded. On that date the
`-t8` characterization lane failed **three times consecutively** on `Enteropia` (9800X3D), taking the
tally on that host to **four failures in five attempts** across two dates. Every crash carries the
identical stack — `signal 11` in `spawn_apply` inside `libfftw3`, reached through FFTW.jl's
`spawnloop` (`providers.jl:49`) on a Julia task — and every one landed in the `reductions` class,
whose `radial_correlation` takes an inverse transform. The crash point *moves* between attempts
(``64^3`` `Float64`, then ``128^3`` `Float64`, at 2, 8 and 10 minutes in), which marks it a race rather
than a bad cell, and the process had accumulated 289M and 1071M allocations with 5874 and 14598
collections when it died.

**The 2026-08-07 non-reproduction was run on the wrong host.** That attempt — 105 trials, ~50,500
transform executions, no crash — ran on `Aiporetne`. It closes as evidence about `Aiporetne`, where the
fault has never appeared, and says nothing about `Enteropia`, where it now appears about four times in
five. The finding already flagged that a host-specific trigger was not excluded; it is now the leading
explanation. Two targeted repros on the *failing* host also came back clean — 2,400 `radial_correlation`
calls at `-t8`, and twelve rounds of build → run → drop → `GC.gc(true)` across the `fft`, `transfer` and
`reductions` classes — so the fault needs the full lane's duration and allocation pressure, not merely
its operations. A short reproducer is not cheaply available.

**The lane is obtainable anyway, by splitting it across processes.** The mitigation below is unusable
here — building plans under `set_fft_threads!(1)` removes the callback, but the `-t8` lane exists
precisely to measure threaded FFT, so it would corrupt the column it is meant to produce. What works
instead is running the lane as **one process per grid** (`CHAR_SIZES=64`, then 128, 256, 512) and
merging the four archives: 64³, 256³ and 512³ passed first time, 128³ on its second attempt, and the
parts hold disjoint rows (150 each) so the union is what an uncrashed process would have written.
`RESULTS.md`'s `CPU 9800X3D t8` column was rebuilt that way on 2026-08-10 and is flat against the
2026-08-05 one it replaces — median ``+0.0\%`` over 600 rows, the largest movers being the `measure`
twins whose `MEASURE` plan search legitimately re-decides between runs.

**That is a workaround, and it sharpens the diagnosis rather than closing it.** The fault is unchanged
and a plain `-t8` invocation still dies here. But a fresh process doing only ``128^3`` **also** crashed,
2.5 minutes in, so the trigger is not simply a long-lived process accumulating state; splitting helps
because it shortens each exposure and makes a retry cheap, not because it removes the hazard. Combined
with the crash point moving between attempts, the fault reads as a low-probability race whose rate rises
with the number of threaded transform executions — which is why the small grids, with their enormous
call counts per second, are where it keeps landing.

**The conditions, tabulated from five crashes — and the four things that are NOT enough.** The tally
is five because the four failures of the single-process lane (three on 2026-08-09, one on 2026-08-05,
against one success) are joined by a fifth from the split run of 2026-08-10, whose ``128^3`` process
crashed on its first attempt before succeeding on its second. Every crash
on record shares four properties: `-t8` (FFTW's thread count tracks Julia's, so eight workers; `-t1`,
`-t2` and `-t4` have never failed across many lanes), the host `Enteropia`, the **`reductions` class**
— five times out of five, never `fft`, `algebra`, `operators`, `convolution` or `transfer` — and a
small or middling grid (``128^3`` four times, ``64^3`` once, never ``256^3`` or ``512^3``, though that
last is partly survivorship because the monolithic lanes died before reaching them). What it is *not*
is an accumulation threshold: the allocation counter at death spans 158M to 1071M and the collection
count 1753 to 14598, a sevenfold spread on both.

Four reproduction attempts at `-t8` on the failing host all came back **clean**, and each one narrows
the cause: 2,400 `radial_correlation` calls; twelve rounds of build → run → drop → `GC.gc(true)` over
`fft`, `transfer` and `reductions`; **five rounds of the `reductions` class alone at the exact crashing
cell**; and the full `Pkg.test()` suite. So neither the operation, nor plan churn, nor the class, nor
eight threads is sufficient on its own.

**What every real crash had that none of those had is the rest of the process.** In each one, `fft`,
`algebra`, `operators`, `convolution` and `transfer` had already run before `reductions` was reached —
and `fft` is the class that builds the most plans, including the `measure` twins that invoke FFTW's
**timed planner**. That is the exact window FFTW.jl documents, quoted below: the collector may run
during the `spawnloop` callback *while the planner is executing*. Its deferred plan destruction and
`GC.safepoint()` spin exist to stop that **deadlocking**; a segfault is the other failure, the shape of
a plan freed by its finalizer while another thread is still executing it. The working description is
therefore a low-probability race, per threaded transform execution, whose window is opened by earlier
planner activity in the same process — which explains both why the small grids catch it (their call
counts per second are enormous) and why splitting the lane helps without fixing anything.

**Separately, the package itself is fine at eight threads.** `Pkg.test()` under `JULIA_NUM_THREADS=8`
passes in full — 6182 tests across 92 testsets, zero failures, identical to `-t1` and `-t4` — so this
is not a general ``-t8`` hazard for a consumer, and the CI matrix's `-t1`/`-t4` pair is not hiding a
broken configuration. It is the sustained benchmark lane, with its millions of small threaded
transforms, that finds the race.

**(q, historical) FFTW's threaded executor segfaulted once at `-t8`, and did not reproduce.** The first ``-t8``
characterization lane died with `signal 11` inside `spawn_apply` in `libfftw3`, reached through
FFTW.jl's `spawnloop`, while running the `reductions` class at ``128^3`` `Float64` — which touches FFTW because
`radial_correlation` takes an inverse transform. The package sets FFTW's thread count to match Julia's
at load, so ``-t8`` is the only lane driving FFTW with eight worker threads; `-t1`, `-t2` and `-t4` all
completed. Re-running the identical lane succeeded (30m31s, `rc=0`), so the fault is **intermittent**.
Nothing was corrupted: `characterize.jl` writes its JSON only at the end, so the crash left the previous
archive intact rather than half-written — worth knowing, because a harness that wrote incrementally
would have produced a silently mixed-vintage column instead.

**Attempted reproduction, 2026-08-07: 105 trials, ~50,500 transform executions, no crash — but the
fault is now LOCATED rather than mysterious.** Two stressors were built against the mechanism instead
of re-running a 30-minute lane. Both drove eight FFTW worker threads at ``128^3`` `Float64` through
`radial_correlation`, which is what the original crash was running (it takes an inverse transform and
materialises a power field), with **plan churn** so finalizers had work pending while the next round
executed: v1 forced collection between rounds, v2 instead kept the heap near its threshold from a
background allocating task, so the collector would fire *inside* the callback rather than between
calls. Totals: 105 trials, ~50,500 transform executions, ~6,200 plan build-and-destroy cycles, on
`Aiporetne` (i7-12700K) with FFTW.jl 1.10.0 and FFTW_jll 3.3.12+0. Every trial exited 0.

**What the attempt did establish.** FFTW.jl's own source documents this interaction zone: "the
garbage-collector may run at unexpected times. For example, it may run during the `spawnloop` callback
while the FFTW planner is executing", and it carries deferred plan destruction plus a `GC.safepoint()`
spin specifically so that case cannot **deadlock** on the `fftwlock`. A **segfault** is a different
failure from the one that machinery guards, and the shape that produces one is a plan being destroyed
by its finalizer while another thread is still executing it — a use-after-free reached through
`spawn_apply`. That is consistent with every recorded detail: it needs plan lifetime to overlap
execution, it needs the collector to run at an unlucky moment, and it appeared only in the `-t8` lane,
the one driving the callback with eight workers.

**What it does not establish.** A non-reproduction bounds the rate, it does not clear the code: under
adversarial conditions the fault is rarer than about 1 in 50,000 transforms on this host, against an
original of one occurrence in one 30-minute lane. The crash was also seen on `Enteropia` (9800X3D) and
this attempt ran on `Aiporetne`, so a host-specific trigger is not excluded.

**The mitigation, if it ever bites a consumer, is known and is not free.** Building plans under
`set_fft_threads!(1)` removes the callback entirely — the thread count is fixed at plan-build time
(finding (t)) — and also removes that finding's per-call allocation. The cost is real: FFTW threading
is worth about ``2\times`` at ``256^3`` on the 12700K (`to_physical scalar` `Float64`, 153.4 ms at
`-t1` against 78.2 ms at `-t8`), so this is a robustness-for-throughput trade to make deliberately,
not a default to change.

**(r) Every kernel-taking operation moved 20–45% on the CPU between the 2026-07-22 and 2026-08-07
sweeps, and the cause is decision 51 reaching them through finding (k).** The re-sweep's slower rows
were almost exactly the operations that *take* a kernel — `divergence!∘kernel`, `helmholtz!∘kernel`,
`convolve!`, `combine!∘kernel` — across every thread count and both element types.

**The GPU half of this finding is WITHDRAWN, not explained.** Both archives it originally compared were
measured in the broken regime of (s), so the device cluster was a difference between two
collector-dominated measurements and says nothing about the operations. It cannot be recovered either,
since answering it now would require the *old code* re-measured on the *fixed* harness, which no
archive contains. The `gcsample` setting never applied to CPU lanes, so what follows is CPU-only and is real.

**Bisected rather than argued.** The archives were gone, so the same operations were re-measured at
`48b6254a` and at `HEAD` in adjacent worktrees sharing one dependency manifest, on an idle box, `-t1`.
Three control rows taking no kernel (`add!`, `laplacian!`, the plain `divergence!`) came out flat at
``0.93``–``1.01``, which is what licenses reading anything into the rest:

| row (``64^3`` / ``128^3`` `Float64`) | HEAD / old |
|:---|:---|
| `combine!∘kernel vector` | ``2.28\times`` / ``1.65\times`` |
| `convolve! vector` | ``1.98\times`` / ``1.02\times`` |
| `divergence!∘kernel` | ``1.33\times`` / ``1.24\times`` |
| `helmholtz!∘kernel` | ``1.27\times`` / ``1.23\times`` |
| `convolve! scalar` | ``1.01\times`` / ``0.91\times`` |
| `exponential_convolve!` | ``1.00\times`` / ``1.00\times`` |

**The mechanism is a per-fiber-component recompute of the kernel symbol.** Decision 51 made
`spectral_cutoff` and `spectral_band` return a `RadialKernel`, whose `_kernel_data` is a lazy
``\sigma(\lvert k\rvert^2)`` over the ``(N_{k_x}, N_y, N_z)`` mode grid. Against a **scalar** field that
shape matches and the symbol is evaluated once per mode; against a **vector** field the trailing
singleton is extruded over the fiber and the symbol is evaluated **once per component**. A stored
kernel re-reads a cached array in the same place, which is far cheaper. Measured directly at `HEAD`,
radial against its own materialized twin:

| tensor order | ``64^3`` (compute-bound) | ``128^3`` (bandwidth-bound) |
|:---|:---|:---|
| ``R = 0`` | ``1.02`` | ``0.88`` — radial faster |
| ``R = 1`` | ``1.99`` | ``1.02`` |
| ``R = 2`` | ``1.52`` | ``1.06`` |

``R = 0`` never pays it, which is the signature; `exponential_convolve!` takes multipliers rather than a
kernel object and is untouched, which is the control. The case ``R = 2`` sits *below* ``R = 1`` because nine
complex components are memory-heavy enough that bandwidth starts dominating even at ``64^3``, which is
the same effect that removes the penalty entirely at ``128^3``.

**This is finding (k)'s trade, arriving somewhere new.** That finding already recorded a lazy kernel
costing ``1.7\times`` a stored one on the CPU when the kernel is *fixed*; decision 51 then changed what
`spectral_cutoff` returns, so every operation taking a cutoff kernel inherited the penalty without any
of them changing. It also reconciles what looked like a contradiction: the report's own `∘ radial`
versus `∘ stored` rows show radial *faster*, because they are measured at ``128^3`` and `-t8`, deep in
the bandwidth-bound regime where the saved kernel stream wins. Both readings are correct; the regime
decides.

**The hoist was prototyped, measured, and DECLINED.** The obvious fix is to evaluate the symbol once
per mode and reuse it across the fiber — the decision-38/39 fused-pass pattern — and it is *not*
materialization: the value lives in a row-sized buffer of ``N_{k_x}`` floats, a few hundred bytes,
never an ``O(N^3)`` array. It was written that way (σ once per ``(i_2, i_3)`` row into a stack buffer,
then applied across components with contiguous SIMD access in ``i_1``), checked bitwise against
`convolve!`, and timed against the current broadcast:

| tensor order | ``128^3`` hoist / broadcast | ``256^3`` hoist / broadcast |
|:---|:---|:---|
| ``R = 0`` | ``0.72`` | ``0.92`` |
| ``R = 1`` | ``0.95`` | ``1.02`` — slower |
| ``R = 2`` | ``0.99`` | ``1.07`` — slower |

**It buys nothing where it matters and costs a little.** At ``256^3`` the pass is bandwidth-bound, so
the recompute is already hidden behind memory latency while the buffer adds a store and a load that
the memory-bound regime hides less well. The ``R = 0`` column gains, but ``R = 0`` never paid the fiber
penalty in the first place — that gain is over the broadcast machinery itself, at a tensor order with
no fiber to extrude over.

**The premise behind wanting the fix was also wrong, and measuring is what showed it.** A traffic count
says the radial class should beat stored by ``1/(2R+1)`` — about 14% at ``R = 1`` — and that the
recompute was eating it. At ``256^3`` `Float64` the radial broadcast measures **41.9 ms against
stored's 45.0 ms**, already 6.8% ahead: it *is* realizing its memory saving at production scale, and
there was no forfeited 14% to recover. The ``1.02`` reading at ``128^3`` is the transition point
between the two regimes, not evidence of a permanent loss.

**So the penalty is real but confined to the regime nobody ships in.** It appears at ``64^3`` and
serial, where the pass is compute-bound; the CPU path's tuning target is the beyond-VRAM band
(ARCHITECTURE.md decision 37), and there the radial class is already the faster of the two. Decision 51
stands as measured: ``O(1)`` builders, competitive application at production grids, and a small-grid
compute penalty that no reasonable fix removes without costing more elsewhere. **No change is
warranted**, and the pass audit's separate ``\hat w`` extrusion holder should be re-priced against this
result before anyone acts on it either.

**(s) Every GPU number this project has ever recorded is inflated 2–29× by `gcsample`, and the
operations were never what was being timed.** `characterize.jl` sets
`BenchmarkTools.DEFAULT_PARAMETERS.gcsample = true` for device lanes, and `regress.jl` sets
`gcsample = USEGPU`. That runs a full `GC.gc()` **before every sample**, whose finalizers free device
buffers and synchronize the device — a cost that lands on a measurement whose operation is tens of
microseconds. Measured A/B on the RX 7900 XTX, `Float64`, the whole `convolution` class run through the
suite's own code with only that one parameter changed:

- ``64^3``: inflation ``18.4``–``29.2\times`` (`convolve! scalar` 956 µs against 32.7 µs)
- ``128^3``: inflation ``5.8``–``19.8\times`` (`convolve! scalar` 1.128 ms against 56.9 µs)
- ``256^3``: inflation ``1.9``–``4.25\times`` (`convolve! vector` 2.494 ms against 1.218 ms)

The `gcsample = true` figures reproduce the committed archive to within a few percent, which is what
identifies the archive as this regime rather than some other.

**The tell was visible in the table all along.** With the overhead in, `convolve! scalar` and
`convolve! vector` at ``128^3`` read 1.094 and 1.177 ms — a **3× difference in bytes moved appearing as
1.08×**, because both were dominated by a shared ~1 ms floor. With it out they read 57 and 182 µs, a
ratio of ``3.2`` that matches the data volume. A device column whose scalar and vector rows nearly
coincide is not measuring the device.

**It is not a uniform scale factor, so it corrupts comparisons *within* a column too.** The inflation
varies per row (``1.94``–``4.25\times`` at ``256^3`` alone), and at least one documented conclusion
**reverses** when it is removed: `convolve! vector ∘ radial` against `∘ stored` reads ``1.48\times``
*slower* for the radial class at ``256^3`` with `gcsample`, and ``0.90\times`` — *faster* — without it,
with the same flip at ``128^3``. Decision 51's radial kernel is therefore **faster than the stored class
on this card**, in the same direction as CUDA. The claim recorded in `bd1e4f30` that decision 51's trade
"has opposite sign on the two vendors" is **retracted**: it rested on a probe that also ran
`gcsample = true`, and the apparent sign came from two rows being inflated by different factors
(``9.5\times`` against ``5.8\times``), not from the kernels.

**Scope.** `gcsample` is gated on `USEGPU` in both harnesses, so **CPU columns and CPU canary baselines
are clean** and every GPU column of `RESULTS.md` — all four cards, every grid — plus both hosts' GPU
canary baselines are affected. Cross-card GPU comparisons are affected twice over, since each vendor's
free-and-synchronize cost differs; the recorded "RTX 5070 Ti is ≈1.8× the RX 7900 XTX" was not safe to
rely on until re-measured, and on re-measurement (both cards, fixed regime) it **fell to 1.09× in
`Float64` at ``256^3``** — see the resolved cross-card entry in (v).

**Why it was there, and why deleting it was not the fix.** It was added deliberately (2026-06-11)
because the `reductions` class wedged the device: `lpnorm` materializes a magnitude field per call,
BenchmarkTools' sampling loop does almost no *host* allocation, so Julia's GC never fired, and the
AMDGPU pool grew until the allocator spun. That failure is real, and a bare `gcsample = false`
reinstates it.

**The fix, landed and validated: `gcsample` is now decided PER ROW, by measurement.** Only a row that
creates device arrays fast enough to exhaust the pool within its own trial needs the per-sample
collector, and `_apply_gcsample_policy!` in `characterize.jl` finds those rows rather than assuming
them. Each row is warmed up, then run with the collector **disabled** while the device pool is watched;
the growth is projected over the trial from the row's own per-call time, and a row projected to exceed
2 GiB keeps `gcsample`. Host bytes cannot serve as the signal — a KernelAbstractions launch allocates
host bytes per call, so a first attempt using them classified every launching row as allocating and
changed nothing.

**The probe's own output is the evidence it works, because it independently reproduces invariant 13.**
At ``128^3`` it measures 0.0 MiB of pool growth for *every* in-place operation and finds exactly the
documented materializers: `lpnorm` 144 MiB, `radial_correlation` and the cross-correlation 1310 MiB,
the spectral `inner`'s ``O(N^2)`` correction planes 13.5 MiB, `materialize_kernel` 146 MiB. That list
was written from the code years before this probe existed, and the probe was not told it.

**Validated on the case the setting existed for.** Running `characterize.jl` itself over `convolution`
and `reductions` at ``128^3`` **and** ``256^3`` `Float64`: it completes without wedging, keeps
`gcsample` on exactly six rows (the two `materialize_kernel` rows and the four documented reduction
materializers), and the in-place rows recover their physics — `convolve!` scalar against vector reads
57.3 against 181.0 µs, a ratio of ``3.16`` matching the data volume, where the archive read 1.094
against 1.177 ms. The figures reproduce an independent `gcsample = false` measurement to within 1%.
CPU lanes are untouched, the policy being gated on the backend.

**The probe could wedge the card it was written to protect, and did.** It runs GC-free, so its first
version's fixed eight calls were themselves an unbounded allocation: `transfer` at ``256^3``, whose
NUFFT allocates oversampled work arrays per call, filled the pool and hung a re-sweep for two and a
half hours with VRAM at 99%, device activity at 0%, and one core spinning in the allocator. The
`catch`-based fail-safe did not fire because **a wedge is a hang, not an exception**. The probe is now
bounded by memory with an early exit — one call at a time, stopping the moment growth passes 512 MiB,
which is already decisive — so its peak use is that ceiling plus one call rather than the pool.
`SIGTERM` did not reach the spinning process; `SIGKILL` released the pool cleanly and the archive
survived, `characterize.jl` writing its JSON only at the end.

**An allocating row need not pay a GC per sample either.** Since the probe measures per-call growth,
`samples` is capped from it (a 4 GiB budget, `evals` pinned to 1) and the row runs GC-free with a
bounded pool. This matters because the user-facing transforms allocate their result by definition, so
the whole device `fft` column was otherwise still timed on the collector. Only a row whose *single*
call is too large to repeat — the vector transforms, at ~400 MB each — keeps the per-sample GC. A
capped row's parameters are deliberate and must not be passed to `tune!`, which would search `evals`
upward and undo the cap.

**Re-swept 2026-08-07, and the correction is the size the A/B predicted.** Against the pre-fix archive,
the RX 7900 XTX column moved by a median of ``-81.6\%`` over 467 rows: `operators` ``-92.0\%``,
`convolution` ``-85.0\%``, `algebra` ``-82.9\%``, `reductions` ``-81.1\%``, `transfer` ``-80.6\%``,
`fft` ``-71.7\%``. Individual rows fall 97%. The physics is back — `convolve!` scalar against vector at
``128^3`` reads 57.3 against 180.0 µs, a ratio of ``3.14`` matching the data volume, where the old
column read 1.094 against 1.177 ms. The canary was refrozen on the fixed harness and is green with
**zero** rows needing the per-sample GC, every canary being an in-place mechanism: that lane had been
pure collector overhead.

**A defect in that fix suppressed `tune!` for the entire device suite, and is now repaired.** The
policy returns the rows whose parameters it set deliberately so they are not re-tuned, and it
identified them with `allocating || params.evals == 1`. The second test was meant to catch a *capped*
row, which reports `allocating = false` but has had `evals` pinned to 1 — except that **1 is also
`BenchmarkTools`' untuned default**, so the test matched every row in the suite and `tune!` ran on
none of them. The flat rows are documented three paragraphs above as "tuned normally", so the code
contradicted its own specification. A capped row now carries its own flag. The repair was verified by
perturbation on a synthetic suite rather than by reading: a flat row must leave `fixed` empty, and a
row whose stubbed pool grows 100 MiB per call must still appear there with no per-sample GC.

**Its footprint is bounded, confined to the fastest rows, and MEASURED — it is 6–8% on three of them.**
Tuning only raises `evals` above 1 when a call is short enough that per-sample overhead is comparable
to the work. Rather than reason about which rows those are, the two disciplines were run against each
other on the RTX 5070 Ti at ``64^3`` `Float64`: of the whole `convolution` class only
`spectral_cutoff`, `radial_kernel` and `spectral_band` — the ``O(1)`` closure builders at
``\approx 0.4`` µs — tune above `evals = 1` (to ≈ 207), and untuned they read **6–8% high** (400.0
against 373.8 ns; 390.0 against 361.2; 400.0 against 376.5). Every other row stays at `evals = 1` and
ties to within 1%, including `materialize_kernel radial` at 11.4 µs — so the threshold sits far below
the 20 µs a first estimate assumed, and the affected set is three builder mechanisms rather than every
sub-20 µs row. A 6–8% bias on three closure-construction rows is inside the documented jitter and
changes no conclusion, so the RX 7900 XTX column needs no re-sweep on this account; its builder rows
are simply known to read a few percent high until that lane is next swept.

**Scope, stated exactly.** The policy is reached only under `USEGPU`; the CPU branch calls
`tune!(suite)` and always did, so no CPU column is touched. Before the per-row policy existed
`tune!(suite)` ran unconditionally for devices too, which makes the **RX 7900 XTX re-sweep of
2026-08-07 the only archive in the tree measured with tuning suppressed** — every other column,
device and CPU alike, is tuned. The canary is unaffected: `regress.jl` carries its own standalone
copy of the policy that neither caps samples nor returns a do-not-tune set, so no frozen baseline
needs refreezing.

**`RESULTS.md` now holds both GPU columns in the fixed regime**, the RX 7900 XTX re-swept 2026-08-07
and the RTX 5070 Ti 2026-08-09, so the two are comparable again — see the resolved cross-card entry in
(v). Two further columns were **dropped rather than carried**: both belonged to cards since retired
from the fleet, both were measured in the broken regime, and neither could be re-swept, so a reader
could never correct or compare them — and a column like that invites exactly the comparison it cannot
support.

**(t) A threaded FFTW plan allocates Julia-side task state on every call — size-independent,
nondeterministic, and fixed when the plan is BUILT rather than when it is called.** The 2026-08-04
survey run reported `to_spectral!` allocating 8–12 KB per step on odd grids under permuted layout
folds, which invariant 13 would make a per-step leak. It is not one, and the package is
allocation-free there.

FFTW.jl reaches its worker threads through a Julia callback, so a plan built with more than one thread
allocates task state per transform call. Three properties identify it as harness rather than scratch:

  - **Size-independent.** The same 7008 B/step for a 12 KB field and for a 2.6 MB one, over grids from
    ``8^3`` to ``48^3``. Field-sized scratch would scale; this does not.
  - **Nondeterministic.** The same configuration measured 7008, 10464, 23173 and 48557 B/step on
    different runs, since the number of tasks actually spawned varies with scheduling.
  - **Set at plan-build time.** A plan built under `set_fft_threads!(1)` measures **exactly 0 B/step**
    even when called from a four-thread session, while one built under four threads measures 7008 in
    the same session. Restoring the setting before the call changes nothing.

The value also depends on the layout fold — 7008 for the default and ``(2,1,3)``, 10464 for
``(3,1,2)`` — which is what made it look like a permuted-layout defect. It is the plan's stage count,
not the package's code path.

**The gate was already right and the survey was not.** `test/allocations.jl` bounds this class with
``4096 \times`` the thread count, which is why it passes at `-t4`; the survey's sequences lane used a
purely field-proportional bound, so a constant several-kilobyte cost overran it on the small fixtures.
The lane now builds a dedicated single-threaded plan for the allocation measurement — the only place
the cost can be removed — and reports 0 B/step deterministically across repeated `-t4` runs, with the
tight field-proportional bound kept for detection power. **Raising the bound would have been the wrong
fix**: it would have set a threshold against a quantity that varies 7× run to run, which is how a
harness stops measuring anything.

**(u) Jitter is not uniform across the table: a small grid at a high thread count carries up to
``1.44\times`` run-to-run variance, and the committed "~10%" was a blanket claim that does not hold
there.** Two `mean(norm) vec` cells were flagged as regressions by the 2026-08-07 re-sweep — GPU
``128^3`` `Float32` at ``+121.9\%`` and CPU `-t8` ``64^3`` `Float32` at ``+111.2\%``. Neither is one.

The GPU cell was measured on both sides in the broken `gcsample` regime of (s); re-swept on the fixed
harness the column is monotone and physical again (`Float32` 87.3 → 241.0 → 849.0 µs across
``64^3``–``256^3``, `Float64` 97.7 → 236.8 → 1371 µs), and the old 538.9 µs reading — which sat *below*
its own ``64^3`` row — is gone.

The CPU cell is real jitter, and measuring it is what shows the scale. Five repeats of the same
measurement, `Float32` `mean(norm) vec`:

| cell | five minima (µs) | spread |
|:---|:---|:---|
| ``64^3`` `-t8` | 31.2, 31.0, 31.3, 30.8, 44.4 | ``1.44\times`` |
| ``64^3`` `-t1` | 192.1 – 193.8 | ``1.01\times`` |
| ``256^3`` `-t8` | 5434 – 5931 | ``1.09\times`` |
| ``256^3`` `-t1` | 13063 – 13295 | ``1.02\times`` |

The variance is confined to **small grid × high thread count**, where ~31 µs of work is comparable to
the cost of spawning eight threads and BenchmarkTools' minimum over a one-second budget does not
suppress the tail. The mode at that cell is ~31 µs, which is what the *old* archive recorded (32.0);
the re-sweep happened to catch the tail (67.5). Thread scaling there is in fact monotone when measured
cleanly — 193.2, 100.4, 53.0, 43.8 µs at `-t1/-t2/-t4/-t8`.

**So a movement of tens of percent in a small-grid, high-thread cell is not evidence.** Compare those
rows at ``256^3`` or above, or at low thread counts; the report header now says so rather than claiming
a uniform ~10%.

**(v) Which recorded decisions the `gcsample` defect could have corrupted — audited, not assumed.**
Finding (s) invalidates GPU numbers, and several recorded decisions were justified by GPU numbers, so
the question is which of them could now be wrong. The inflation was **not a uniform factor** (1.94–4.25×
at ``256^3``, 18–29× at ``64^3``), and a uniform factor is the only kind that cancels in an A/B ratio —
so the exposure is worst where a claimed ratio is near 1. That is exactly how decision 51's radial
versus stored comparison flipped sign.

**The blast radius is narrower than it first looks.** `BenchmarkTools`' own default is
`gcsample = false`, and only three entry points ever set it: `characterize.jl`, `regress.jl`, and the
two `runbenchmarks.jl` drivers. **An ad-hoc `@benchmark` head-to-head is therefore unaffected**, which
is how most of the decision-bearing comparisons in this document were taken. A useful corroborating
test: the per-sample GC put a floor of roughly 1 ms on any device row at ``\le 128^3``, so **a recorded
GPU figure below that floor cannot have been measured under it**.

**Re-checked on the fixed harness, and surviving:**

  - **Decision 30's backend split** (`mean(det, A)` fused against `mean(det(A))` materialising, ``128^3``
    `Float64`, RX 7900 XTX). Recorded: 0.55 vs 0.69 ms, fused ``1.3\times``. Re-measured: **0.259 vs
    0.486 ms, fused ``1.87\times``** — same direction, stronger, and both absolutes fell as the collector
    floor came off. The GPU branch of `_reduce_fiber` is pointed the right way. Its recorded figures also
    sit below the 1 ms floor, so they were never under `gcsample` to begin with.
  - **Decision 51** (radial against stored): re-measured on the fixed harness, radial is 9–12% *faster*
    at ``128^3`` and ``256^3``. The claim that its trade "has opposite sign on the two vendors",
    published in `bd1e4f30`, was retracted the same night.
  - **Finding (o)** (an axis-factored kernel does not win): the AMD side agrees on the fixed harness —
    separable 241.9 µs against stored 181.1 µs at ``128^3`` `Float64`. The qualitative conclusion holds;
    its RTX 5070 Ti specifics need re-measuring on that host.

**At risk and NOT resolvable here.** These rest on GPU ratios small enough to sit inside the
inflation's per-row variance, and none can be re-checked from this box:

  - **The Morton-sorting rejection, gather half — RE-CHECKED, and it does not hold on the current
    card.** This was first recorded here as unresolvable because the sorting dependency and the sorted
    gather were deleted. That was wrong on the part that matters: only the *sort* was deleted, and the
    sort is not what the measurement times. `interpolate!` still exists and Morton order is just a
    permutation of the `PointSet`, which a host `sortperm` produces perfectly well for a benchmark. See
    §4(c), where the entry now carries the re-measurement.
  - **The wrap-hoist rejection — RE-MEASURED, and reopened (see §4(c)).** Filing it here as a `gcsample`
    casualty was probably wrong twice over: the record describes a "same-session A/B", i.e. an ad-hoc
    comparison that `BenchmarkTools` would have run with `gcsample = false` anyway, so the defect likely
    never touched it. What it *was* at risk from is the same thing as Morton — retired RDNA2 hardware.
    Re-measured on RDNA3 the sign reverses for the default scheme (`CatmullRom` hoisted 10–30% *faster*,
    against a recorded 10–14% slower) and the CPU, never tested for this, wins by up to ``3.6\times``.
  - **Decision 42's GPU figure — RE-CHECKED on the RX 7900 XTX, and it is a tie.** The recorded
    "in-register ties in `Float32`, ``\approx 6\%`` slower in `Float64`" was measured on the RTX 5070 Ti,
    so this is a different card rather than a direct re-run. Both variants written as standalone
    kernels differing only in the denominator — and verified **bitwise equal** — give stored-over-
    in-register ratios of ``0.955`` (`Float64` ``128^3``), ``0.998`` (`Float64` ``256^3``), ``1.015``
    (`Float32` ``128^3``) and ``1.004`` (`Float32` ``256^3``). The recorded *direction* reproduces
    weakly — in-register is 4.5% slower in `Float64` at ``128^3`` — while everything else ties inside
    1.5%, so the effect is real but marginal and vanishes at the larger grid. **The decision is
    untouched either way**: it rests on the CPU result (in-register wins everywhere, ``+4\%``/``+10\%``),
    and the CPU was never affected. Worth stating plainly because it is the natural worry:
    **neither variant materialises anything field-sized.** The stored family is three PER-AXIS vectors
    of length ``N_{k_x}``, ``N_y``, ``N_z`` — a few KB, the same ``O(N)`` shape as the derivative
    wavenumbers — so the trade is three register multiplies against three stride-1 loads from
    cache-resident vectors, not memory pressure. (The stored family must be the derivative-squared
    ``a^2``, not the multipliers' true-``\lvert k\rvert^2`` family: invariant 5 keeps the true value at
    Nyquist where the derivative wavenumbers are zeroed, so substituting it would change the answer
    there.)
  - **Every cross-card ratio — RESOLVED 2026-08-09, and the headline one was wrong.** Both sides were
    inflated by *vendor-specific* amounts, so nothing could be said until both cards were re-swept;
    they now are. The prediction that the large ratios keep their direction and none keeps its
    magnitude was **half right**. The ``\approx 48\times`` `Float64` radial gap is confirmed almost
    exactly — 48.64× on `co-spectrum vec.vec` and 48.07× on `radial_spectrum vec` at ``256^3``, the
    atomic-scatter difference — and it survives because it is enormous. The **"≈1.8× median" does
    not**: at ``256^3`` the median over 71 comparable rows is **1.09× in `Float64` and 1.28× in
    `Float32`**, which is near parity, and the RX 7900 XTX in fact has the wider memory bus. The
    advantage the old figure described is real but **concentrated where the work is small**: 2.21×
    and 3.06× at ``64^3``, 1.35× and 1.65× at ``128^3``, decaying to parity as the rows become
    bandwidth-bound — the signature of a launch-latency edge, not a throughput one. And the AMD card
    **wins seven of the transfer class's eight rows** at ``256^3`` `Float64`, which no previous
    comparison could have shown: the four spline gathers and scatters run at 0.53–0.68× the NVIDIA
    time (so 1.5–1.9× the speed), the two `NUFFT` rows sit near parity at 0.85–0.95×, and the one
    NVIDIA win is `anterpolate! Lalescu(3,3)` at 1.11×.
    Treat "the fleet's fastest card" as true only at small grids and in `Float64` atomics.

**Structurally safe: everything measured on the CPU.** `gcsample` was gated on the backend throughout,
so decisions 38, 39 and 40, the threading work, finding (k)'s and (l)'s CPU numbers, and the CPU half of
every split decision are untouched by this. That is most of the tuning record.

**(w) The fix for (s) never ran on CUDA — it called a function that does not exist, and the catch-all
reported the failure as a measurement.** The per-row policy asks the device pool how much it grew, and
on the NVIDIA side it asked with `CUDA.total_memory() - CUDA.available_memory()`. **`CUDA.available_memory`
is not a binding in the CUDA.jl this tree resolves** (CUDACore 6.2.0); the call raised `UndefVarError` on
every row. Each row's probe is wrapped in a `try`/`catch` whose documented intent is "unclassifiable ⇒
keep the old, safe behaviour", so **every row on CUDA fell back to `gcsample = true`** — the exact regime
(s) exists to remove.

**It announced itself as a result.** The run printed `per-sample GC kept for N allocating row(s): …` and
named them, which reads as a measurement of N allocating rows. Those lists were each class's **complete**
row list: `operators` reported all nine of its rows — `laplacian!`, `curl!`, `divergence!` and the rest —
every one of which `test/allocations.jl` pins at zero bytes. That is the tell, and it is the same shape as
(s)'s own: a device column whose in-place operations look like allocators is not measuring allocation.
The condition was caught three classes into the first `Enteropia` re-sweep (2026-08-09) by noticing that
`add! scalar` and `spectral_cutoff` cannot possibly be allocating rows.

**Root cause is unexercised code, and it was flagged in advance.** The policy was written on a host with
no NVIDIA card, and the note queuing this re-sweep said in as many words that the CUDA branch "has never
been exercised, unlike the AMD path". The AMD path was correct throughout — `AMDGPU.used_memory()` exists
— so **finding (s)'s AMD re-sweep and every conclusion drawn from it are unaffected**. What follows is
narrower and worse: **no CUDA archive has ever been measured under the per-row policy**, so the RTX 5070
Ti column remained in the pre-fix regime even after the fix shipped.

**Both halves repaired.** The call is now `CUDA.used_memory()`, the same name the AMD path already used,
which makes the two vendors symmetric. Its semantics were verified rather than assumed: a 16 MiB `CuArray`
moves it by exactly 16 MiB, `reclaim` returns it to zero, and it reads zero at rest — and being
**pool-scoped it ignores other processes on the card**, where the device-wide `total - free` reported
32 MiB for that same 16 MiB array and would drift with anything else using the GPU. The second repair
matters more than the first: `apply_gcsample_policy!` now returns the rows whose probe **threw**
separately from the rows it classified, and prints a `!!` banner with the count and the first exception,
plus an unmissable line when *every* row failed. A fallback that cannot be told apart from a result is how
a broken instrument reports success.

**Verified after the repair**, `Float64` ``64^3`` on the RTX 5070 Ti: `operators` nine rows, zero probe
failures, zero rows keeping the collector; `algebra` ten rows, the same. The probe reproduces invariant 13
on CUDA exactly as it did on AMD, having been told nothing about it.

**(x) The `storage` class, measured at last: the identity is free, and the two bus directions are not
symmetric.** The class decision 63 added was swept on the RTX 5070 Ti on 2026-08-17 (42 rows, ``64^3``
to ``256^3``, both element types) and says three things.

*Adapting to the family a section already lives in costs ``118`` ns, flat.* It reads 118.2–122.1 ns at
every grid and both types — five orders of magnitude below the ``19.8`` ms a ``256^3`` `Float64` vector
takes to actually cross. Decision 63 *documents* that this case is the identity; this measures it, and
the flatness is the proof: a copy would scale with the grid and this does not.

*Device-to-host is about ``4\times`` slower than host-to-device, at every size and both types.* A
``256^3`` `Float64` scalar goes out in ``6.03`` ms and comes back in ``23.72`` ms; the vector, ``19.77``
against ``72.18`` ms; in `Float32`, ``2.46`` against ``11.41`` ms and ``9.00`` against ``36.27`` ms. The
outbound rate is ``\approx 22`` GB/s, which is a healthy PCIe 4.0 figure; the inbound is ``\approx 5.6``
GB/s, far below it. The asymmetry is therefore not the bus — it is that the return trip **allocates its
destination**, a fresh pageable host array, and pays for the pages as well as the transfer. That is
evidence for the open design question the roadmap already carries: whether `adapt` should gain an
in-place form writing into a caller's preallocated destination. A consumer pulling a field back every
few steps is currently paying an allocation it has no way to hoist.

*And the asymmetry is now actionable.* Decision 69 added `adapt!`, which moves into a destination that
already exists; measured on the same card and field, `copyto!` into a preallocated host array runs at
``19.0`` GiB/s against ``5.1`` for the allocating form, a ``3.75\times`` recovery that brings the return
trip to the outbound rate. The `storage` class carries `adapt!` rows beside the allocating ones, so the
comparison stays measured rather than remembered.

*And it is now measured, not projected.* Decision 69's `adapt!` rows sit beside the allocating ones in
the table since 2026-08-23: on the return trip it is **3.48–3.66×** at ``256^3``, and **outbound it is
a wash** (``1.0\times``) — which is this finding's own diagnosis confirming itself, the device
allocation being pooled and cheap so there was never a page cost to avoid that way. The gain also has a
**size threshold**: a ``128^3`` `Float64` scalar (16.8 MB) shows ``1.01\times`` where the vector on the
same grid (50 MB) shows ``3.48\times``, which is what page faults on fresh host pages look like — they
bite only once an allocation outgrows the allocator's reused blocks.

*The two non-section rows behave as their structure predicts.* `adapt multipliers` is ``\approx 13`` µs
independent of the grid — six ``O(N)`` per-axis arrays, so the cost is six transfers' fixed overhead
rather than bytes — and `adapt plans (rebuild)` grows ``7.4 \to 23.5`` µs with the grid, which is the
FFT planning it redoes rather than anything copied.

*The RX 7900 XTX was swept 2026-08-23 and confirms every structural claim above, while disagreeing on
one magnitude.* The identity is free there too (``146``–``159`` ns, flat across grids and both element
types, against the ``118``–``122`` ns NVIDIA reads); the outbound `adapt!` is a wash (``1.01``–``1.09``);
the return trip recovers **``2.79``–``2.99×``** at ``256^3`` against NVIDIA's ``3.48``–``3.66×``; and the
**size threshold reproduces exactly** — a ``128^3`` `Float64` scalar shows ``0.99×``, no gain at all,
where the vector on the same grid shows ``3.06×``. Two structural properties holding on an independent
runtime is what promotes them from a CUDA observation to a property of the operation.

*The magnitude that differs is the outbound bus, and it is the vendor rather than the package.* A
``256^3`` `Float64` scalar crosses **to** the AMD card in ``11.42`` ms against NVIDIA's ``6.03`` — an
outbound rate of ``\approx 11.8`` GB/s against ``\approx 22`` — while the return trip is near parity
(``24.40`` against ``23.72`` ms). So the ``4\times`` asymmetry this finding is named for is
``\approx 2.1\times`` on AMD, not because the return is faster but because the outbound is slower. The
package issues one `copyto!` per component in both cases, so nothing here is ours to fix; the
consequence for a consumer is only that the outbound leg is the one worth hoisting on AMD, where on
NVIDIA it is nearly free. The same latency signature shows in `adapt multipliers`, which is ``\approx
147`` µs on AMD against ``\approx 13`` µs on NVIDIA: six small ``O(N)`` transfers, so the row prices
per-transfer overhead, and an ``11\times`` gap there is the launch-latency profile these two cards show
throughout the small-grid rows rather than anything about bytes.

**(y) The two `materialize_kernel` rows cannot be read ACROSS thread counts: their ``t1`` cell depends
on what ran before it in the same process.** A corpus sweep flagged one cell as unexplained —
`materialize_kernel radial`, `Float64` ``512^3``, i7-12700K, ``t2`` reading 143.0 ms against ``t1``
93.2 and ``t4`` 76.7, i.e. slower than *both* neighbours. It was re-measured on the assumption it was
a transient. **It is not.** Two independent processes returned 143.18 and 143.57 ms, agreeing with
each other to 0.3% and with the archive to ``1.00\times``, and the neighbours reproduced too (``t1``
91.7, ``t4`` 76.6). The table is right.

*What is wrong is the comparison, not the number.* Measured standalone, the operation scales cleanly at
every thread count — ``296 \to 145 \to 79 \to 54`` ms for ``t1``/``t2``/``t4``/``t8``, a clean halving
— so there is no threading defect. The ``t2`` and ``t4`` cells agree with standalone measurement to
within 2%; the ``t1`` cell does not, and is ``3.2\times`` faster in the suite than alone. The
difference was bisected to a single ingredient by elimination: constructing the row through
`build_suite` gives 295.5 ms, adding `tune!` gives 298.0, but running the **whole class in one
process** — what `characterize.jl` does — gives **91.6 ms**, reproducing the archive. So the row is
sensitive to the 17 rows that stream through multi-GB fields ahead of it, and only at one thread.
`materialize_kernel separable` behaves identically, which is what identifies the class: these are the
only two rows that **allocate an ``O(N^3)`` result per call** rather than writing into a preallocated
destination.

*Five hypotheses were tested and refuted*, and they are recorded so nobody re-runs them: first-touch
page faults (a recycled page-warm block and freshly mapped pages measure 297.8 against 299.9 ms);
the kernel symbol (`spectral_band(1,3)`, `spectral_cutoff(N/3)` and `spectral_cutoff(2)` are within
1% of each other); dead-code elimination, the most plausible of them, since `bench_sync` reads only
its argument's *type* and the result is otherwise dead — but the exact harness expression measured
standalone is 297.3 ms and forcing the data to be observed adds only ``1.14\times``; `evals`, which
`tune!` sets to 1 in every lane; and heap history, since holding 6 GB of live fields first changes
nothing (300.2 → 296.2 ms). A bimodal distribution was excluded by sampling 93 times at ``t1``, where
the minimum is still 300.4 ms. **The mechanism is therefore not identified** — what is established is
that the effect is real, reproducible, confined to ``t1``, and confined to the two allocating rows.

*The follow-up sweep (2026-08-24) generalized the finding and drew its boundary by measurement.* Every
suite row that allocates a field-sized result per call was measured standalone at ``t1``,
``512^3`` `Float64`, against its archived cell. **Clean: all eight allocating `fft` rows** — standalone
agrees with the archive within 3%, so per-call allocation is *not* the discriminator, and finding (h)'s
`ESTIMATE`/`MEASURE` ratios rest on uncontaminated cells. **Affected: exactly five rows** — the two
`materialize_kernel` rows (``2.8``–``3.2\times``), `lpnorm vec Inf` (``1.63\times``), and
`radial_correlation`/`cross-correlation` (``1.2``–``1.7\times``, at ``t1`` *and* ``t2``, worst in
`Float32` at ``512^3``). The five are the rows that allocate their result *inside the operation*
(via `similar`/broadcast) rather than through a transform plan; whether that distinction is the
mechanism or merely coextensive with it is not established.

*The archive is internally consistent, and needs no re-measurement.* Re-running the archive's exact
process shape — all classes, one process, ``512^3`` `Float64` — reproduces the archived cell for every
affected row at ``t1`` (``0.98``–``1.00\times``: `lpnorm` 222.1 against 223.6 ms,
`radial_correlation` 5458 against 5581, `cross-correlation` 5607 against 5734, both `materialize_kernel`
rows exact) and for the correlations at ``t2`` (``1.01``–``1.03\times``). A **class-only** process is
a *third* regime: sufficient history for `materialize_kernel` (the convolution class reproduces its
archive cells) but not for the reductions three, whose class-only values sit with standalone. So the
fast values are not stale and not wrong — they are what the full sweep reproducibly measures — and the
rule is that a cell from one process shape must never be compared against a measurement from another.
The four rows decisions 71/72 added were checked the same way and are **regime-insensitive**
(`reality_residual vector` 47.5 against the merged 47.4 ms; `weighted_inner x3 fused` 2.020 against
2.065 s), so their class-only-merged cells are comparable with their full-sweep column.

*One cell is bistable and should not be trusted at all:* `materialize_kernel separable`'s ``t2``. The
archive reads 63.4 ms; three same-day measurements in three process shapes — class-only twice,
full-sweep once — all read 156.5, and within the archive itself the cell sits *below* its own ``t4``
(82.0 ms), the same inversion signature. The 2026-08-07 sweep evidently landed the fast regime at
``t2`` for this row where every 2026-08-24 process lands the slow one, so regime selection at ``t2`` is
not even deterministic across sweeps. Both `materialize_kernel` rows' ``t4``/``t8`` cells reproduce
everywhere (radial 76.7/47.9, separable 82.0/50.3, matched today to 1%).

*The consequence is a reading rule.* For the two `materialize_kernel` rows, read thread scaling from
``t4`` upward — both ``t1`` (bistable, ``\approx 3\times``) and ``t2`` (bistable for `separable`) sit
in history-selected regimes — and for `lpnorm` and the two correlation rows, compare their ``t1``/``t2``
cells only against sweeps of the same process shape. Within `RESULTS.md` every CPU column is a full
sweep, so the table is self-consistent; what is invalid is comparing those cells against a standalone
probe or a class-only lane. This is the same *class* of defect as finding (s), a row reporting the
harness rather than the operation, and it was found the same way — by re-measuring a number that looked
wrong instead of explaining it.

## 5. The benchmark suite

A standing suite under `benchmark/` (sibling of `test/`), **opt-in** — *not* part of
`Pkg.test()`, exactly like the GPU tests. A call to `build_suite(; array_type, types, sizes)` builds a
`BenchmarkTools.BenchmarkGroup` parameterised by the **device array type** (`Array` on CPU;
`CuArray`/`ROCArray` on GPU — the same approach `test/gpu/suite.jl` uses with `to_device`), so one suite
runs everywhere. A `bench_sync` blocks the backend so BenchmarkTools times GPU work to completion. **Every** row that
writes to a device buffer synchronizes it, including the transfer rows: relying on a driver's internal
synchronization is what left `NUFFT` anterpolation's final assignment outside its own measurement, and
a benchmark should assume nothing about where a driver happens to block.

Classes covered: **FFT** transforms (each CPU row with a `measure` twin planned via `FFTW.MEASURE`, so
the default-`ESTIMATE` experience and the tuned production path sit side by side and finding (h) is
re-measured per host/size/type on every sweep; GPU rows have no twin, the device FFT libraries taking no
planner flag; plus, per scalar/vector, the decision-64 pair — the preserving scratch arity of
`to_physical!` and the destructive three-argument baseline it is priced against, whose delta is the
cost of preservation), **field algebra** (M2 + M3, representative — including the weighted
combination `combine!` and the determinant `det!`), **differential operators** (including the fused
`symmetric_gradient!` and the kernel-composed `helmholtz_projection!`/`divergence!` forms of
decision 32, whose baseline is the sequential operator + `convolve!` pair they replace), **convolution** (`convolve!` scalar/vector, the lazy `exponential_convolve!` — its exponent scale-aware, so every
size measures the streaming pass and not the `Float32` subnormal band (finding (m)) — and the kernel-composed
`combine!` of decision 33 — their baselines the stored-kernel `convolve!` and the sequential
`combine!` + `convolve!` pair — + the builders `spectral_cutoff` /
`spectral_band` / `radial_kernel` / `assignment_window` / `translation_kernel` — a builder is
paid once and its kernel applied many times, so it is swept for regressions, not for hot-path cost, and
a builder returning a compressed kernel is timed on one factor rather than a field it never allocates —
the `spectral_cutoff` and `spectral_band` rows previously wrapped their builder in `materialize_kernel`
and so reported an ``O(1)`` lazy build at the cost of an ``O(N^3)`` materialization, with neither
trackable on its own).
Each **compressed kernel class** is additionally swept *against its materialized twin* at the point of
application — `convolve!` on a vector field with the kernel axis-factored, radial, and stored — since
the classes compute the same coefficients and only their cost differs, so the stored form is the
baseline that makes a storage change legible (finding (o)). The class OPERATIONS join it: the general
`radial_kernel` builder against the two named bands, `materialize_kernel` on both compressed classes
(the escape hatch allocates the ``O(N^3)`` field the classes exist to avoid, so its cost is what a
consumer trades away by materializing), the in-place `translation_kernel!` against its allocating
sibling, and `inv` — whose row **doubled** when decision 56 gave it a zero policy, and deliberately so:
that guard is three ``O(N)`` reductions over the axis factors, measured at **40.6 µs** on an RTX 5070 Ti
against a **9.5 µs** reciprocal, so it dominates the operation. It is accepted rather than optimized
away, because a kernel is inverted once and applied many times — this class is swept for regressions,
not for hot-path cost — and because the alternative is returning a non-finite coefficient that poisons
every later result. Read against an archive from before 2026-07-30, that step is the guard, not drift.
Then the **interpolation/anterpolation
transfer** (the spline schemes plus the spectral `NUFFT`; the exact `DirectDFT` is its oracle, not a swept regression target), and the
**L²/measure reductions** (`integral`/`mean`/`inner`/`l2norm`/`lpnorm`/`maximum`, the covariance
tensor `cov` — the one reduction whose result is fiber-valued at ``R = 2``, so it streams a vector
field and writes nine accumulators — the scalar-only `var` in **both** representations, which prices what
skipping the transform is worth (decision 49 gave it a Parseval form), the fused multiplier-weighted
`weighted_inner`, the spectral Parseval
`inner`, the spectral zero-mode `integral`/`mean` (an O(1) DC-coefficient read, not a streaming reduction),
and the radial reductions `radial_spectrum` / `radial_correlation` plus the two-field co-spectra
`radial_spectrum(f, g)` / `radial_correlation(f, g)` — a single scatter-add shell-binning pass and an
inverse rfft, diagnostic-cost; the co-spectra cost the same as the single-field forms, sharing their
binning), including the **mapped forms** `maximum(norm, u)` / `mean(norm, u)` / `mean(det, A)` /
`mean(tr, A)`, whose `maximum(norm, u)` row pairs with the `lpnorm vec Inf` row as a direct A/B — the
same quantity, one materializing a magnitude section and one not.

**Storage-family moves** (`adapt`, decision 63) are the seventh class, and the only one whose cost is a
**link** rather than a device: a host↔device copy is bounded by the bus, so it does not improve with the
card and does not scale like anything else in the table. The class is **device-only and empty on a CPU
lane** — `adapt` to the family one already occupies is the identity, so a host row would time a no-op
and report nanoseconds as though a transfer had happened. It sweeps both directions separately (they
are not symmetric on any real link), the identity case (so that its being nearly free is *visible*
rather than merely asserted), the multipliers (six ``O(N)`` axis vectors, so latency-bound where the
field rows are volume-bound), and `adapt` on a `FieldTransformPlans`, which is not a transfer at all
but a **planning pass** on the target and is priced separately for that reason. The practical guidance
the class exists to support is unchanged by any of its numbers: a solver should cross the bus during
setup and stay resident, because a per-step transfer of a ``256^3`` `Float64` field is tens of
milliseconds against the tens of microseconds its operations take.

Run it:

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

**The coverage contract.** Every public operation class is benchmarked (representative members) over **{Float64, Float32} ×
{representative grid sizes} × {CPU `-t1`, CPU `-t4`, GPU}**, unless a class has an explicit exemption
with its reason — the storage class of decision 63 is device-only, because `adapt` to the family one
already occupies is the identity and a CPU row would time a no-op. New code adds its benchmark to the
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
(`benchmark/characterize.sh`) runs the full matrix — every op-class (including FFT) over each
backend's default grids (**CPU 64³–512³**, **device 64³–256³**, since a device cannot hold 512³ in
`Float64`), on the **CPU thread sweep 1/2/4/8** (powers of two up to the performance cores) and the
**GPU** — building **one (grid size, element type) at a time** to bound memory (a 256³ `Float64`
tensor field is ~1.1 GB; holding all classes for both types at 256³ overflows the 12 GB GPU — gap 6),
and assembles it into the committed report
[`benchmark/RESULTS.md`](https://github.com/GrigorySarnitsky/GBGPeriodicFields.jl/blob/master/benchmark/RESULTS.md)
(the raw per-run JSON under `benchmark/results/` is gitignored). Regenerate it on any platform with
that one script; it stamps the date, commit, and host. The `characterize.jl` sweep additionally stamps **each
archive JSON** with its own measurement vintage (`commit=`/`measured=` BenchmarkGroup tags), and
`report.jl` prints the per-column vintages in the header — so a column measured at an older commit is
visible as such instead of silently inheriting the report's HEAD (the 2026-07-22 decision-40
reductions skew, one host's archive swept hours before a threading feature landed, is the motivating
incident).

A representative slice — `128³`, `Float64`, minimum time (CPU = Ryzen 9800X3D, GPU = RTX 5070 Ti),
read from the current `RESULTS.md` rather than measured for this table. The
last two columns are speedups *in ×*: CPU thread scaling (`-t1` → `-t4`) and the GPU's lead over the
4-thread CPU. `RESULTS.md` now carries **two CPU thread sweeps** (i7-12700K and Ryzen 9800X3D) and
**two GPU columns** — the RX 7900 XTX (gfx1100, ROCm, 24 GB) and the RTX 5070 Ti (Blackwell `sm_120`,
CUDA, 16 GB); the two retired cards were dropped on 2026-08-07, having been measured in the broken
`gcsample` regime of §4(s) with no hardware left to re-sweep them on. The 7900 XTX adds a 512³
`Float32` point, and both cards cover the full 256³ matrix in both element types. At 256³ the two are
near parity (§4(v)): the median over 71 comparable rows is 1.09× in `Float64` and 1.28× in `Float32`,
the NVIDIA lead being a small-grid launch-latency effect rather than a throughput one, and the AMD card
winning the whole `transfer` class by 1.5–1.9×. Across vendors the **reductions** class shows the widest gap and the
clearest architectural signature: the radial reductions (`radial_spectrum`/`radial_correlation`)
bin on an `Atomix` scatter-add histogram, and CUDA's atomic throughput far outruns RDNA3's —
`radial_spectrum` on a vector field at 256³ is **≈48× faster** on the 5070 Ti than the 7900 XTX in
`Float64` (54.973 → 1.144 ms) but only **1.11×** in `Float32` (0.915 → 0.824 ms). Re-measured
2026-08-09 with both cards in the fixed regime of §4(s)/§4(w): the ``\approx 48\times`` is confirmed
to three significant figures, while the `Float32` figure — previously recorded as ≈3.5× — is not,
and its collapse sharpens the conclusion rather than weakening it. The cross-vendor gap on this
operation is the emulated-atomic penalty of §4(d) at work (RDNA has no native global `Float64`
atomics): in `Float32`, where both cards have native atomics, they are equal. That names the
mechanism; finding (n) prices the exposure — a per-workgroup pre-reduction would mostly hide it, so
the gap is hardware-caused but implementation-addressable. The 7900 XTX pays
≈60× going `Float32`→`Float64` on this op, against the 5070 Ti's ≈1.4×. Those are the post-decision-34
figures, the staging planes fused away, so the atomics are the whole measurement. The full operation × type × grid × thread/backend matrix is in
`RESULTS.md`:

| operation (128³, Float64) | CPU `-t1` | CPU `-t4` | GPU | threads `-t1`→`-t4` | GPU vs `-t4` |
|---|--:|--:|--:|--:|--:|
| `to_spectral` scalar (FFT)            | 10.27 ms | 2.93 ms | 0.399 ms | 3.5× |  7.3× |
| `mul!` tensor·vec (M3 algebra)        |  7.03 ms | 4.43 ms | 0.321 ms | 1.6× | 13.8× |
| `laplacian!` scalar (operator)        |  2.21 ms | 0.27 ms | 0.030 ms | 8.3× |  9.0× |
| `interpolate!` Catmull–Rom (gather)   |  5.63 ms | 1.46 ms | 0.132 ms | 3.9× | 11.0× |
| `interpolate!` Lalescu (3,3) (gather) | 41.63 ms | 10.50 ms | 0.772 ms | 4.0× | 13.6× |
| `anterpolate!` Catmull–Rom (scatter)  | 22.47 ms | 6.13 ms | 0.169 ms | 3.7× | 36.2× |

Two patterns the speedup columns make plain. **The bandwidth-bound classes barely thread** at this
size — the tensor product gains only 1.6× from 4 threads, being DRAM-bandwidth-bound rather than
compute-bound, confirming §2. (Before decision 38 the cheapest of them, `add!`, *regressed* under
threading; the slab-threaded rewrite made thread scaling monotone, which is why no row here does.) **The transfer threads well** (≈3.9×
on the Catmull–Rom gather) because its stencil gather carries more work per byte. And the **GPU leads
the 4-thread CPU by ~3.5–27×**, the spread itself being the point (and the serial CPU by far more — the Catmull–Rom gather at ``256^3`` `Float64` runs 150.4 ms
serial against 1.646 ms on the RTX 5070 Ti, ≈91×, and 1.048 ms on the RX 7900 XTX, which **wins the
whole transfer class** by 1.5–1.9× — re-measured 2026-08-09 in the fixed regime), widest for the light/parallel ops and narrowing toward the bandwidth ratio for the heavy
streaming ones. (`Float32` is ~0.6–0.7× of these `Float64` times on the GPU; the full
operation × type × grid × thread/backend matrix — including the per-grid scaling and the 1/2/4/8
thread sweep — is in `benchmark/RESULTS.md`.)


## 7. Current coverage and known gaps

**Covered:** the public operation classes (FFT, algebra, operators, convolution, transfer, reductions; the device-only storage class of decision 63 is wired into the suite but has not yet been swept into the committed archive — see gap 7)
parameterised by element type and grid size, runnable on CPU (`-t1`/`-t4`) and GPU (ROCm or CUDA) through one
device-parameterised suite; the manual save→`judge` regression workflow; and the **exhaustive characterization**
(`characterize.sh` → committed `benchmark/RESULTS.md`): every op-class (incl. FFT) at each backend's default grids (CPU 64³–512³, device 64³–256³),
across two CPU 1/2/4/8 thread sweeps (i7-12700K, Ryzen 9800X3D) and two GPUs — RX 7900 XTX (gfx1100,
ROCm) and RTX 5070 Ti (Blackwell `sm_120`, CUDA); the 7900 XTX is extended to
a 512³ `Float32` point for the bandwidth-bound classes, and the **9800X3D sweep covers 64³–512³, both
element types, all classes** — the first data in the CPU production band of `docs/ARCHITECTURE.md`
decision 37 (a 512³ `Float64` CPU sweep needs tens of GB of host RAM, which a 123 GB workstation clears
with room to spare; it was these lanes that exposed finding (l)). The decision-27 additions (`combine!`, `det!`,
`symmetric_gradient!`, `weighted_inner`) are wired into their classes and CPU-verified (0 allocations for
`combine!`/`det!`/`symmetric_gradient!`; the small bounded guard for `weighted_inner`); they enter the
committed `RESULTS.md` table on its next GPU-host refresh. **Done (2026-07-21):** both GPU archives are
refreshed — the RX 7900 XTX (2026-07-20) and the RTX 5070 Ti — so every decision-27/32/33/34 row
(`combine!`, `det!`, `symmetric_gradient!`, `weighted_inner`, the kernel-composed
`helmholtz_projection!`/`divergence!`/`combine!` arities, `exponential_convolve!`, and the fused radial
diagnostics) now carries both GPU columns at 64³–256³, both element types. The refresh also re-confirmed
the §6 atomic-scatter contrast on the fused decision-34 kernels: `radial_spectrum` vector `Float64` 256³
is 54.973 ms on the 7900 XTX against 1.144 ms on the 5070 Ti (the figures §6 and §4(v) carry; this
paragraph's earlier 65.95/1.371 pair predated the §4(s) per-row GC repair and is superseded) — a ~48×
CUDA lead on what is now a pure
scatter-add (its staging planes are gone, so the atomics are the whole story).

**Gaps:**

1. **CLOSED — the device rows no longer carry a blanket per-sample GC.** This gap used to warn that
   the GPU `reductions`/`convolution` figures were latency rather than throughput, because every device
   row ran with `gcsample = true`. Finding (s) removed that: the collector is now decided **per row**
   from a measured device-pool probe, and only the documented materializers keep it. The committed
   archive is in the fixed regime on both cards, and the old warning's own symptom is gone — a
   ``64^3`` `Float64` `convolve! scalar` reads 33.1 µs on the RX 7900 XTX and 10.8 µs on the RTX
   5070 Ti, against the ``\approx 1.5`` ms floor this gap was written to describe.
2. **CUDA spans two NVIDIA generations, both on `Enteropia`** (the office box; CPU Ryzen 9800X3D).
   `characterize.jl` now takes a `cuda` backend beside `gpu`/`rocm` (CuArray + `CUDA.reclaim()`, no
   comgr warm), so the memory-bounded one-class-at-a-time sweep runs on NVIDIA too. The **RTX 5070 Ti**
   (Blackwell `sm_120`, 16 GB) covers
   the **full 64³–256³ matrix** (both element types, all six classes; ~10.8 GB peak). 512³ exceeds
   16 GB — the `mul!` tensor field alone is 4.5 GB and the build OOMs — but unlike AMD's HIP (gap 6),
   CUDA **OOMs gracefully** (a Julia `OutOfGPUMemoryError`, no context corruption), so probing the
   ceiling is safe. `Enteropia` now also contributes its **9800X3D** CPU thread sweep beside the
   i7-12700K (host `Aiporetne`).
3. **Automated time-regression detection — BUILT (`benchmark/regress.jl`, 2026-07-22).** One
   canary per execution *mechanism* (twelve: the broadcast route, each fused-kernel class, the
   tree reductions, FFT, transfer gather/scatter, the binning) at ``128^3`` `Float64`,
   ``\sim``1–2 minutes per backend, judged on minimum times against a **committed** per-host
   baseline (`benchmark/baselines/<host>-<backend>[-tN].json`) at a 25% tolerance with a hard
   exit code, plus the CPU serial-vs-threaded alarm
   ``t_\mathrm{threaded} \le 1.1 t_\mathrm{serial}`` on every override-governed canary — the alarm
   that finding (l) lacked.
   Refreeze protocol: an intended slowdown reruns with `--freeze` **in the same commit**, with the
   reason. Calibration lesson from its first run, recorded so it is not relearned: 20 samples of a
   ``\sim``250 µs canary let minima jitter ``\sim 2\times`` at eight threads and false-alarm;
   the frozen calibration is 100 samples × 5 evals (batch-averaged minima), which held 12/12
   invariant across repeated judges on both backends. Baselines for both hosts are committed —
   Enteropia (cpu-t1, cpu-t8, cuda) and Aiporetne (cpu-t1, cpu-t8, rocm; frozen 2026-07-22 with
   that host's post-rewrite re-sweep, its freeze-run inversion alarm 8/8 ok). Deliberately **not**
   push-triggered CI (cost policy; shared runners are noise): the `BenchmarkGroup` layout still
   keeps
   [AirspeedVelocity.jl](https://github.com/MilesCranmer/AirspeedVelocity.jl) or
   [PkgBenchmark.jl](https://github.com/JuliaCI/PkgBenchmark.jl) a drop-in if a CI story ever
   changes. **First live catch (2026-07-24):** the `t1` helmholtz canary flagged at 1.27× baseline,
   which turned out not to be a slowdown but a dead-code bug — decision 42 had dropped the kernel's
   squared-wavenumber arguments while leaving the gated `::CPU` loop's signature stale, so the loop
   fell out of dispatch and CPU helmholtz silently reverted to the KA-on-CPU launch decision 40 had
   escaped. Restoring the loop returned the canary to baseline **without a refreeze** — the check
   working exactly as designed, catching an achieved-time regression the allocation and pass audits
   cannot see (decision 47).
4. **The canary is a ``128^3`` relative instrument, and on an X3D part it is largely cache-resident.**
   Its grid is fixed at ``128^3`` (`benchmark/regress.jl`, unchanged since the lane was built) so a lane
   costs 2–3 minutes and gets run. The consequence, measured on Enteropia 2026-08-05: `add!` moves
   151 MB against a 96 MB L3, so repeated samples keep much of it resident and the single-thread figure
   reads 63.8 GB/s — well above the ~41 GB/s a Zen 5 core sustains from DRAM (§4(l)). **The canary
   therefore does not probe the DRAM-bound regime**, which is the one decision 37 names as the CPU
   path's tuning target; at ``512^3`` the same working set is 9.66 GB and cannot cache. A regression
   that appears only once a field stops fitting would pass this net silently. That regime is covered
   instead by the characterization sweep (`benchmark/characterize.jl`, ``64^3``–``512^3``), which is
   the instrument to reach for when a change plausibly alters memory traffic rather than arithmetic.
5. **Run-to-run variance** — absolute numbers carry ~10% jitter, and the **atomic-binning canary is
   the widest**: `radial_spectrum` at `-t8` on Enteropia measured 4.871, 4.793, 4.747 and 4.504 ms over
   four back-to-back repeats against a 4.384 ms baseline (2026-08-05) — an 8% spread with every draw
   above the frozen value, which sits low in its own distribution. Its scatter-add threads outside the
   `with_threading` override and its summation order is nondeterministic, so contention decides the
   figure. Read a single reading of that row against the baseline as noise unless it clears the 25%
   tolerance, and confirm any movement against the other backends before believing it. Cross-platform/-commit
   comparisons are only meaningful within a single session (hence the side-by-side discipline of
   §3); the tables here are indicative magnitudes, not contract values. The allocating kernel
   *builders* (`spectral_cutoff` / `spectral_band` / `radial_kernel` /
   `assignment_window` / `translation_kernel`) are the noisy extreme: their threaded ``256^3``
   cells swung ±50% between two same-day sweeps (GC timing on paid-once allocating passes) — read
   them as indicative only, never as regressions.
6. **GPU at 256³ — three traps, none a rocFFT bug** (measured on a since-retired 12 GB AMD card;
   the ``256^3`` ceiling below is specific to that capacity, while the cold-compile and allocator traps
   are not capacity-dependent. The wedge-instead-of-error behaviour itself still binds the current
   cards — it simply moves up a grid, as this gap's own 2026-06-26 update records for a 512³
   `Float64` sweep on the 24 GB card).
   Earlier notes blamed "rocFFT 256³ planning"; that was wrong. The facts, measured:
   - **256³ FFT works.** Scalar and vector r2c/c2r at 256³ take ~1 s to plan and ~15–20 ms to run;
     the full `fft` class passes at 256³.
   - **Cold kernel compilation looks like a hang.** The first GPU use after a reboot compiles
     kernels host-side via AMD `comgr` → 0% GPU, 100% CPU, VRAM pool reserved, no output, for
     minutes. *Never kill a cold first run* — a killed compile never persists to `~/.cache/comgr`, so
     the next run restarts cold. The `characterize.jl` sweep warms the cache with one trivial kernel up front.
     A further mitigation for the rocFFT share of the compile: setting the `ROCFFT_RTC_CACHE_PATH`
     environment variable to a writable file makes rocFFT persist its runtime-compiled FFT kernels
     there and reuse them across processes, turning that part of the cold start into a one-time cost
     ([rocFFT runtime compilation](https://rocm.docs.amd.com/projects/rocFFT/en/docs-6.1.0/how-to/runtime-compilation.html)).
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
   standing limit on that card was the 12 GB ceiling itself: even one class's both-element-type 256³
   fields strain it (hence the one-class-at-a-time build), and 512³ won't fit on that card. If a future
   OOM-segfault degrades the context, reset with `rocm-smi --gpureset` from a console (it can crash an
   active display session) or reboot.

   **Update (2026-06-26, RX 7900 XTX, gfx1100, 24 GB).** On RDNA3 256³ is indeed trivial for every class
   (both element types), and a **512³ `Float32`** point is now in `RESULTS.md` for the bandwidth-bound
   classes (`fft`, `algebra`, `operators`, `convolution`). But 512³ is *not* free even at 24 GB:
   `transfer` is omitted (its NUFFT oversamples ×2 to a 1024³ work grid) and `reductions` is omitted
   (the radial reductions hold a ≈24 GB live set at 512³ — vector fields in both representations + the
   inverse-rfft plans). A 512³ `Float64` sweep of the heavy classes exceeds 24 GB,
   and a HIP OOM **wedges** the allocator (GPU 0 %, one host core spinning, VRAM full) rather than
   erroring — the same trap as the cold-compile / GC-free hangs above, and `gcsample` does *not* help
   when the *live* set (not GC lag) is what overflows. So the 512³ column is `Float32` and skips those two.

7. **The `storage` class is swept on BOTH vendors — CLOSED 2026-08-23.** Decision 63's device-only
   class carries 66 rows in each of the `GPU 5070TI` and `GPU 7900XTX` columns, and the four rows
   decisions 71 and 72 added are filled on all five `Aiporetne` lanes, so `RESULTS.md` has seven class
   sections with no half-filled table left. See finding (x) for the cross-vendor reading, which is the
   comparison this class exists to support. Method note, kept because it is what makes a partial sweep
   safe: `characterize.jl` **overwrites** the archive it is given, so a class-only sweep must be
   written to a separate file and merged. Both halves were done that way — the CUDA one verified 426
   pre-existing rows bit-identical afterwards, the ROCm one 467 — and the merge is verified in **both
   directions**, re-merging the pre-merge backup into the merged archive to confirm it adds nothing and
   changes nothing, which catches a row silently dropped as well as a row silently altered.
8. **`aarch64` is a production host architecture with zero coverage.** The recorded production
   target (`docs/ARCHITECTURE.md` decision 37) is NAISS Arrhenius, and its GPU nodes are GH200
   superchips: the CUDA device is hosted by a 72-core **Grace CPU — ARM, `aarch64`** — while the
   CPU partition is x86-64 EPYC. The GPU path's host code will therefore eventually build and run
   on ARM, and nothing in this package has ever been compiled, tested, or benchmarked on that
   architecture. No blocker is *known*: the stack is pure Julia plus JLL artifacts published for
   `aarch64-linux` (FFTW, HDF5), and CUDA.jl runs on `aarch64` hosts, Grace Hopper among them. But
   "no known blocker" is not "verified", and none of the x86-measured CPU findings transfer —
   finding (h)'s `ESTIMATE` mis-planning turns out to reach both x86 microarchitectures in the fleet
   rather than being the Zen 5 artifact it was first recorded as — which is a reason to carry `MEASURE`
   to ARM as a default expectation rather than a reason to assume it is absent — and NEON changes FFTW's
   codelet landscape entirely. Standing guard until access lands: **never adopt an x86-only
   dependency or recommendation** — the MKL FFTW provider, which has no `aarch64` build, is the
   canonical tempting example — and when it does land, the first step on an Arrhenius node is the
   test matrix, then this benchmark suite.
