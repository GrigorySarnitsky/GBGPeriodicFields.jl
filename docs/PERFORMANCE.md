# Performance — GBGPeriodicFields

This is the third companion to [`ARCHITECTURE.md`](architecture.md) and
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
  GPU wins across the range both can run. The CPU path is not, however, a convenience for toy problems.
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
  hoist made the default scheme *slower*, and particle sorting — the textbook locality optimization —
  *regressed* the GPU gather. Only the one the measurement pointed at (loop order) survived (§4).

- **A benchmark run owns the machine, and a number is not a result until it is explained.** Two
  obligations, both learned the hard way. **Run benchmarks alone** — no test suite, no documentation
  build, no second lane, nothing else on the host, and *especially* not while a GPU sweep is in
  flight. A device benchmark is host-bound at small grids (the synchronisation and, on the GPU path,
  the per-sample GC), so competing work inflates it by a roughly fixed amount per case; that alone
  invented a 2.2× "regression" at ``64^3``, an inflated canary baseline, and a phantom "environment
  shift" attributed to a driver, all in one session. Check `uptime` and the GPU's utilisation before
  starting, and wait rather than measure into a busy box. **Then read what came back.** Running a
  sweep and reporting that it completed is not a measurement: compare against the previous archive,
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
  lever is rocFFT's `ROCFFT_RTC_CACHE_PATH` kernel cache (an environment variable; see §7 gap 5).
- **Field algebra (M2 + M3), spectral differential operators, and convolution** → **memory-bandwidth-bound**. A
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
  occupancy. Proof the kernels are memory/occupancy-bound, not ALU-bound.
- **Morton particle sorting** (the textbook GPU-locality optimization): **0.5–1.0× on GPU** (gather)
  — concentrating access *kills* the memory-level/DRAM-bank parallelism the GPU needs, and the field
  is cache-resident anyway — though **2.2–4.4× on CPU**. The companion **atomic-free node-centric
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
read-modify-write + a full-grid prescale). On gfx1031 `Float32` atomic-add is native but `Float64`
is emulated (CAS loop) ⇒ ≈**1.3–1.7×** slower; contention is worst at *moderate* clustering
(~2 pts/cell), not extreme (extreme stays cache-hot).

**(e) CPU vs GPU.** The transfer threads on CPU through `KernelAbstractions`' `CPU()` backend with no
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
(`examples/gpu/rocm/HIST_ROCm.jl`, 192³ `Float32`, ``\mathrm{Re}_\lambda \approx 93``) sustains **≈ 34 ms/step**
(8000 steps, ≈ 270 s) on the RX 6700 XT this way. *Discipline for consumers:* preallocate a workspace and
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
(``\approx 87`` ms/step) now runs to completion on the RX 6700 XT at a flat ``\sim\!6`` GB
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
|---|---|---|
| 1 | 163 → 30 ms (**5.4×**) | 167 → 31 ms (**5.3×**) |
| 4 | 43.7 → 9.5 ms (**4.6×**) | 41.7 → 8.3 ms (**5.1×**) |
| 8 | 23.5 → 6.8 ms (**3.4×**) | 21.8 → 4.8 ms (**4.5×**) |

It is size- and CPU-specific (128³ is fine; the i7-12700K shows no such inversion) — a classic `ESTIMATE`
pitfall on a new CPU, not a package issue. The default stays `ESTIMATE` (cheap, deterministic, right for
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
|---|---|---|---|
| CPU (vectorized blocked loop) | **5.1 ms**, 0 B | 13.0 ms, 16.8 MB | fused 2.5× faster |
| GPU, RX 7900 XTX (fused `Broadcasted`) | **0.55 ms**, 0 B | 0.69 ms, 16.8 MB | fused 1.3× faster |

Decomposing the CPU side shows why one shape could not do both, and it is not the layout:

| step | ``N = 128``, `Float64`, 1 thread | factor |
|---|---|---|
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
|---|---|---|
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
|---|---|---|
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
and 64³ t8 97 → 28 µs (threading now *wins* at small sizes). Both hosts' CPU columns in
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
to small-grid diagnostics costing single-digit milliseconds — recorded, not fixed. Candidates when a
consumer's cadence makes it matter: bin padding (backend-uniform; kills the `Float32` reversal, not
the ``64^3`` inversion); per-thread private bins with an ordered merge on CPU (kills both *and*
makes the CPU binning bitwise thread-invariant, retiring one of `docs/ARCHITECTURE.md` §9's two
tolerance-tested accumulators, at the price of splitting the deliberately single-source
KernelAbstractions kernel); workgroup-local bins on GPU — the same redesign's lever on the ~80×
CUDA-over-ROCm `Float64` radial gap, which is this kernel under RDNA3's CAS-loop `Float64` atomics.


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
| ``64^3``  | 0.67 | 0.68 | — | — | 0.45 | 0.30 |
| ``128^3`` | 0.78 | 0.71 | 0.69 | 0.45 | 0.92 | 0.48 |
| ``256^3`` | 0.77 | **1.00** | 0.94 | 0.55 | **1.14** | **1.18** |
| ``512^3`` | — | — | 0.93 | 0.60 | **1.12** | **1.14** |

The trend is the point: **the ratio improves with grid size on every platform**, because the saving is
bytes not moved (two streams instead of three) while the cost is per-element arithmetic. Small grids sit
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

## 5. The benchmark suite

A standing suite under `benchmark/` (sibling of `test/`), **opt-in** — *not* part of
`Pkg.test()`, exactly like the GPU tests. A call to `build_suite(; array_type, types, sizes)` builds a
`BenchmarkTools.BenchmarkGroup` parameterised by the **device array type** (`Array` on CPU;
`ROCArray`/`CuArray` on GPU — the same approach `test/gpu/suite.jl` uses with `to_device`), so one suite
runs everywhere. A `bench_sync` blocks the backend so BenchmarkTools times GPU work to completion.

Classes covered: **FFT** transforms (each CPU row with a `measure` twin planned via `FFTW.MEASURE`, so
the default-`ESTIMATE` experience and the tuned production path sit side by side and finding (h) is
re-measured per host/size/type on every sweep; GPU rows have no twin, the device FFT libraries taking no
planner flag), **field algebra** (M2 + M3, representative — including the weighted
combination `combine!` and the determinant `det!`), **spectral operators** (including the fused
`symmetric_gradient!` and the kernel-composed `helmholtz_projection!`/`divergence!` forms of
decision 32, whose baseline is the sequential operator + `convolve!` pair they replace), **convolution** (`convolve!` scalar/vector, the lazy `exponential_convolve!` — its exponent scale-aware, so every
size measures the streaming pass and not the `Float32` subnormal band (finding (m)) — and the kernel-composed
`combine!` of decision 33 — their baselines the stored-kernel `convolve!` and the sequential
`combine!` + `convolve!` pair — + the builders `spectral_cutoff` /
`spectral_band` / `squared_wavenumber_field` / `assignment_window` / `translation_kernel` — a builder is
paid once and its kernel applied many times, so it is swept for regressions, not for hot-path cost, and
a builder returning a compressed kernel is timed on one factor rather than a field it never allocates).
Each **compressed kernel class** is additionally swept *against its materialized twin* at the point of
application — `convolve!` on a vector field with the kernel axis-factored, radial, and stored — since
the classes compute the same coefficients and only their cost differs, so the stored form is the
baseline that makes a storage change legible (finding (o)), the **interpolation/anterpolation
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
same quantity, one materializing a magnitude section and one not. Run it:

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
(`benchmark/characterize.sh`) runs the full matrix — every op-class (including FFT) over each
backend's default grids (**CPU 64³–512³**, **device 64³–256³**, since a device cannot hold 512³ in
`Float64`), on the **CPU thread sweep 1/2/4/8** (powers of two up to the performance cores) and the
**GPU** — building **one (grid size, element type) at a time** to bound memory (a 256³ `Float64`
tensor field is ~1.1 GB; holding all classes for both types at 256³ overflows the 12 GB GPU — gap 5),
and assembles it into the committed report
[`benchmark/RESULTS.md`](https://github.com/GrigorySarnitsky/GBGPeriodicFields.jl/blob/master/benchmark/RESULTS.md)
(the raw per-run JSON under `benchmark/results/` is gitignored). Regenerate it on any platform with
that one script; it stamps the date, commit, and host. `characterize.jl` additionally stamps **each
archive JSON** with its own measurement vintage (`commit=`/`measured=` BenchmarkGroup tags), and
`report.jl` prints the per-column vintages in the header — so a column measured at an older commit is
visible as such instead of silently inheriting the report's HEAD (the 2026-07-22 decision-40
reductions skew, one host's archive swept hours before a threading feature landed, is the motivating
incident).

A representative slice — `128³`, `Float64`, minimum time (CPU = i7-12700K, GPU = RX 6700 XT). The
last two columns are speedups *in ×*: CPU thread scaling (`-t1` → `-t4`) and the GPU's lead over the
4-thread CPU. `RESULTS.md` now carries **two CPU thread sweeps** (i7-12700K and Ryzen 9800X3D) and
**four GPU columns** — the GTX 1070 (Pascal, CUDA, pre-swap), the RX 6700 XT shown here, the RX 7900 XTX
(gfx1100, 24 GB), and the RTX 5070 Ti (Blackwell `sm_120`, CUDA, 16 GB). At 256³ (kernel-dominated, not
launch- or `gcsample`-floored) the 7900 XTX runs ~1.7–3.8× faster than the 6700 XT — widest in
`Float32` — and adds a 512³ `Float32` point; the 5070 Ti covers the full 256³ matrix (both element
types, all six classes). Across vendors the **reductions** class shows the widest gap and the
clearest architectural signature: the radial reductions (`radial_spectrum`/`radial_correlation`)
bin on an `Atomix` scatter-add histogram, and CUDA's atomic throughput far outruns RDNA3's —
`radial_spectrum` on a vector field at 256³ is ≈3.5× faster on the 5070 Ti than the 7900 XTX in
`Float32`, widening to ≈49× in `Float64` (67.1 → 1.38 ms); the extra `Float64` factor is the
emulated-atomic penalty of §4(d) (RDNA has no native global `Float64` atomics), the 7900 XTX paying
≈21× for `Float32`→`Float64` on this op against the 5070 Ti's ≈1.5×. Those are the post-decision-34
figures, the staging planes fused away, so the atomics are the whole measurement. The full operation × type × grid × thread/backend matrix is in
`RESULTS.md`:

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
(`characterize.sh` → committed `benchmark/RESULTS.md`): every op-class (incl. FFT) at each backend's default grids (CPU 64³–512³, device 64³–256³),
across two CPU 1/2/4/8 thread sweeps (i7-12700K, Ryzen 9800X3D) and four GPUs — GTX 1070 (Pascal,
CUDA), RX 6700 XT, RX 7900 XTX, and RTX 5070 Ti (Blackwell `sm_120`, CUDA); the 7900 XTX is extended to
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
is 65.95 ms on the 7900 XTX against 1.371 ms on the 5070 Ti — a ~48× CUDA lead on what is now a pure
scatter-add (its staging planes are gone, so the atomics are the whole story).

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
   those rows read `—`. Its in-place replacement, the **RTX 5070 Ti** (Blackwell `sm_120`, 16 GB), covers
   the **full 64³–256³ matrix** (both element types, all six classes; ~10.8 GB peak). 512³ exceeds
   16 GB — the `mul!` tensor field alone is 4.5 GB and the build OOMs — but unlike AMD's HIP (gap 5),
   CUDA **OOMs gracefully** (a Julia `OutOfGPUMemoryError`, no context corruption), so probing the
   ceiling is safe. `Enteropia` now also contributes its **9800X3D** CPU thread sweep beside the
   i7-12700K (host `Aiporetne`).
3. **Automated time-regression detection — BUILT (`benchmark/regress.jl`, 2026-07-22).** One
   canary per execution *mechanism* (twelve: the broadcast route, each fused-kernel class, the
   tree reductions, FFT, transfer gather/scatter, the binning) at ``128^3`` `Float64`,
   ``\sim``1–2 minutes per backend, judged on minimum times against a **committed** per-host
   baseline (`benchmark/baselines/<host>-<backend>[-tN].json`) at a 25% tolerance with a hard
   exit code, plus the CPU serial-vs-threaded alarm ``t_\mathrm{threaded} \le 1.1
   t_\mathrm{serial}`` on every override-governed canary — the alarm finding (l) lacked.
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
4. **Run-to-run variance** — absolute numbers carry ~10% jitter, so cross-platform/-commit
   comparisons are only meaningful within a single session (hence the side-by-side discipline of
   §3); the tables here are indicative magnitudes, not contract values. The allocating kernel
   *builders* (`spectral_cutoff` / `spectral_band` / `squared_wavenumber_field` /
   `assignment_window` / `translation_kernel`) are the noisy extreme: their threaded ``256^3``
   cells swung ±50% between two same-day sweeps (GC timing on paid-once allocating passes) — read
   them as indicative only, never as regressions.
5. **GPU at 256³ — three traps, none a rocFFT bug** (RX 6700 XT, gfx1031, 12 GB, ROCm 7.2.4).
   Earlier notes blamed "rocFFT 256³ planning"; that was wrong. The facts, measured:
   - **256³ FFT works.** Scalar and vector r2c/c2r at 256³ take ~1 s to plan and ~15–20 ms to run;
     the full `fft` class passes at 256³.
   - **Cold kernel compilation looks like a hang.** The first GPU use after a reboot compiles
     kernels host-side via AMD `comgr` → 0% GPU, 100% CPU, VRAM pool reserved, no output, for
     minutes. *Never kill a cold first run* — a killed compile never persists to `~/.cache/comgr`, so
     the next run restarts cold. `characterize.jl` warms the cache with one trivial kernel up front.
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
   standing limit on the 6700 XT is the 12 GB ceiling itself: even one class's both-element-type 256³
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

6. **`aarch64` is a production host architecture with zero coverage.** The recorded production
   target (`docs/ARCHITECTURE.md` decision 37) is NAISS Arrhenius, and its GPU nodes are GH200
   superchips: the CUDA device is hosted by a 72-core **Grace CPU — ARM, `aarch64`** — while the
   CPU partition is x86-64 EPYC. The GPU path's host code will therefore eventually build and run
   on ARM, and nothing in this package has ever been compiled, tested, or benchmarked on that
   architecture. No blocker is *known*: the stack is pure Julia plus JLL artifacts published for
   `aarch64-linux` (FFTW, HDF5), and CUDA.jl runs on `aarch64` hosts, Grace Hopper among them. But
   "no known blocker" is not "verified", and none of the x86-measured CPU findings transfer —
   finding (h)'s `ESTIMATE` mis-planning is a Zen 5 heuristic artifact, and NEON changes FFTW's
   codelet landscape entirely. Standing guard until access lands: **never adopt an x86-only
   dependency or recommendation** — the MKL FFTW provider, which has no `aarch64` build, is the
   canonical tempting example — and when it does land, the first step on an Arrhenius node is the
   test matrix, then this benchmark suite.
