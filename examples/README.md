# Examples

Small programs that drive **GBGPeriodicFields** the way a real consumer would — a forced
homogeneous-isotropic-turbulence (HIT) pseudospectral DNS, on the CPU and on an AMD GPU. They double as
a check on the public API (anything an example must *hand-roll* is a candidate for promotion into the
package — see the **Gap list**) and, importantly, as a check on the package's **GPU ergonomics**:
written the way DNS codes really are — **preallocated, in-place, allocation-free in the time loop** — the
solver runs on a 12 GB consumer GPU with no manual garbage collection.

This environment is separate from the package and from `test/` / `benchmark/`; the package is a path
dependency via `[sources]`. Manifests, the HDF5 data dumps, and the rendered plots are gitignored.

```sh
julia --project=examples -e 'using Pkg; Pkg.instantiate()'   # one-time
```

The analysis, the HDF5 data dump, and the plotting live in the shared **`hist_postprocess.jl`** (used by
both twins); the solvers themselves stay focused on exercising the package. The run is split
**simulate → dump → plot**: each run writes every plotted curve to an HDF5 file, so the figures can be
re-styled without re-running the DNS via `plot_hist.jl`.

---

## `HIST_CPU.jl` — forced homogeneous isotropic stationary turbulence (CPU)

A *minimal, demonstration* pseudospectral DNS of forced HIT that plots the **Eulerian and Lagrangian
second-order velocity structure functions**, each compensated by its Kolmogorov (K41) inertial scaling,
alongside the energy spectrum, the stationarity history, and the
velocity autocorrelations. The goal is a readable, **performance-first** workflow: the time loop is
fully in-place over a preallocated workspace (no per-step field allocation) — both how a real DNS is
written and what keeps the GPU twin hassle-free.

```sh
julia --project=examples examples/HIST_CPU.jl            # full run (default 32³, ~1 min)
julia --project=examples examples/HIST_CPU.jl --fast     # 64³, nicer statistics
julia --project=examples examples/HIST_CPU.jl --huge     # 192³, Re_λ≈93 (heavy; minutes)
julia --project=examples examples/HIST_CPU.jl --mega     # 256³, Re_λ≈109 (very heavy on CPU — hours; documented figures use the GPU twin at 320³)
julia -t8 --project=examples examples/HIST_CPU.jl --fast  # 8 CPU threads (matters most at N ≥ 64)
julia --project=examples examples/HIST_CPU.jl --smoke    # tiny, ~seconds, for a quick check
julia --project=examples examples/plot_hist.jl examples/output/HIST_CPU.h5   # re-plot saved data, no re-run
```

Threading is **opt-in**: with no `-t` flag Julia (and the package's CPU threading, and FFTW) run on one
thread. At 32³ multithreading buys little; pass `-t8` once you raise `N`.

Output lands in `examples/output/`: the data dump `HIST_CPU.h5` (every plotted curve + the run scalars)
and the PNGs `structure_functions` (the headline two-panel figure), `spectrum`, `stationarity`,
`autocorrelation`, and a 2×2 `summary`.

### Method

Incompressible Navier–Stokes in **rotational form**, so the nonlinear step maps onto the package. Here
$\hat u$ is the velocity in spectral representation, $\mathbb{P}$ the Helmholtz projection onto
divergence-free fields, $\omega = \nabla\times u$ the vorticity, $\nu$ the kinematic viscosity, and
$\kappa$ the wavenumber magnitude — written
$\kappa$ rather than $k$ throughout, because this page follows the turbulence convention in which $k$
is the turbulent kinetic energy:

```math
\frac{\partial \hat u}{\partial t} = \mathbb{P}\bigl[\widehat{u\times\omega}\bigr] - \nu \kappa^2 \hat u + \hat f
```

- **Time integration:** integrating-factor RK2 (Heun) — viscosity exact via $\exp(-\nu \kappa^2 \Delta t)$, the
  nonlinear term explicit; $\Delta t$ from advective CFL. The whole step is **in-place over a preallocated
  workspace** — `curl!`, `to_physical!`/`to_spectral!`, `cross!`, `helmholtz_projection!`, `convolve!`,
  and raw-array AXPYs write into preallocated buffers, so a step allocates no fields.
- **De-aliasing:** 2/3 rule, the package's `spectral_cutoff` sharp low-pass kernel (`convolve!`).
- **Forcing:** rescale the lowest shells ($1 \le \kappa \le 2$) to a fixed energy each step — deterministic,
  unconditionally stationary (scaling preserves $\nabla\cdot u = 0$).
- **Particles:** a few thousand tracers, RK2 advection on the start-of-step velocity via `interpolate`,
  positions wrapped periodically; per-tracer velocity recorded for the Lagrangian statistics. *(The
  time loop is the consumer's — the package has no concept of time, by design.)*

### What it exercises in the package

`Grid3D`, the field types, `FieldTransformPlans` + the in-place `to_physical!`/`to_spectral!`,
`FieldSpectralMultipliers`, the in-place `curl!`, `cross!`, `helmholtz_projection!`, `divergence`; the
**L²/measure reductions** `inner`/`l2norm` (energy $\tfrac{1}{2}\langle u, u\rangle$, dissipation $\nu\langle\omega, \omega\rangle$, the
divergence check $\lVert\nabla\cdot u\rVert$), `radial_spectrum` (the energy spectrum $E(\kappa)$) and
**`radial_correlation`** (the shell-averaged velocity autocorrelation $C(r)$, whose integral is the
integral length $L$, and from which the Eulerian per-component structure function follows as
$S^{(E)}(r) = \tfrac{2}{3}\bigl(C(0)-C(r)\bigr)$); **`convolve!` + `spectral_cutoff`** (the 2/3 de-alias filter, the $\exp(-\nu \kappa^2 \Delta t)$
integrating factor, the IC envelope); and `interpolate` (grid→point). The hot loop uses the **in-place,
allocation-free** `!` forms throughout — the differential operators allocate ~0 bytes (`docs/ARCHITECTURE.md`
decision 24) — and the CFL speed uses `maximum(abs, field_data(u))` rather than `lpnorm` (the latter
materializes a magnitude field). Built-in correctness cross-checks: the Parseval identity
$\tfrac{1}{2}\langle\hat u, \hat u\rangle = \tfrac{1}{2}\langle |u|^2\rangle$ and $\lVert\nabla\cdot u\rVert \approx \text{roundoff}$ (both asserted).

### Reading the plots (and the Reynolds-number caveat)

The headline `structure_functions` figure shows the Eulerian and Lagrangian **per-component**
structure functions (one third of the trace $\langle |\delta u|^2\rangle$), each normalized by its Kolmogorov inertial scaling —
$S^{(E)}(\Delta x) / [\tfrac{11}{9} C_2 \varepsilon^{2/3} \Delta x^{2/3}]$ vs $\Delta x/\eta$, and $S^{(L)}(\Delta t) / [C_0 \varepsilon \Delta t]$ vs $\Delta t/\tau_\eta$ ($C_2 = 2.1$,
$C_0 = 6.0$). A K41 inertial range shows as a **plateau at 1**. Marked on each panel are the **Taylor** and
**integral** scales — $\lambda/\eta$ and $L/\eta$ (Eulerian), $\sqrt{\tau_\eta \tau_u}/\tau_\eta$ and $\tau_u/\tau_\eta$ (Lagrangian) — where the
integral length $L$ and time $\tau_u$ are measured as the **integrals of the velocity autocorrelations**
($L = \int \rho(r)\,\mathrm{d}r$ from `radial_correlation`; $\tau_u = \int \rho_L(\tau)\,\mathrm{d}\tau$ from the tracked particles); the
`autocorrelation` figure shows the two $\rho$ curves. The Lagrangian Taylor-time marker uses the
log-midpoint proxy $\sqrt{\tau_\eta \tau_u}$ — so it needs no acceleration statistics.

At the default **32³** ($\mathrm{Re}_\lambda \approx 16$) there is essentially no inertial range, so the normalized curves
form a hump rather than a plateau, and $\lambda \approx L$ (the scales have not separated) — expected, not a bug.
**`--huge` (192³, $\mathrm{Re}_\lambda \approx 93$)** separates them cleanly ($\lambda/\eta \approx 19$, $L/\eta \approx 43$) and the Eulerian curve
approaches the plateau. The `spectrum` concentrates energy at large scales and falls through the
dissipation range; $k(t)$, $\varepsilon(t)$ are statistically steady past the spin-up.

### Options

All in the `Params` struct at the top: `N`, `ν`, forcing band/energy (`k_force`, `E_force`), `cfl`,
step counts (`n_spinup`, `n_stats`), `n_particles`, recording strides, `seed`. The
`smoke()` / `fast()` / `huge()` / `mega()` configurations select 32³ / 64³ / 192³ / 256³ (the last very
heavy on the CPU; the documented figures use the GPU twin at 320³).

---

## Gap list — what this example reveals the package still lacks

Each item the example surfaced as a hand-roll is a candidate for promotion into the package. The GPU
twin (`allowscalar(false)`) forced most of them in.

**Closed:**

- ✅ **Reductions over a field** (`Reductions`): `integral`, `inner`, `l2norm`, `lpnorm`, `mean`/`std`/…
- ✅ **Apply a diagonal operator in spectral representation — a Fourier multiplier $f(k)$ —** (`Convolution`): `convolve!` + `spectral_cutoff`.
- ✅ **Radial-symbol and shell-band kernels** (`Convolution`): `radial_kernel`, `spectral_band`.
- ✅ **Energy spectrum $E(\kappa)$** (`Reductions`): `radial_spectrum`.
- ✅ **Eulerian structure function without a hand-rolled spatial shift** — $S^{(E)}(r) = \tfrac{2}{3}\bigl(C(0)-C(r)\bigr)$ reads
  straight off the FFT-based `radial_correlation` (the shell-averaged velocity autocorrelation), so the
  earlier `circshift` reach-in is gone; the integral length $L = \int \rho(r)\,\mathrm{d}r$ comes from the same call.

**Still open** (the script hand-rolls these, both representation-neutral):

1. **Random solenoidal field generator** with a target spectrum (an initial-condition helper). The
   script builds the random field + envelope + Helmholtz projection by hand.
2. *Minor:* the Lagrangian autocorrelation / structure function are
   host-side loops over the recorded per-particle velocities (inherent to particle tracking).

Forcing and time integration themselves stay a *consumer* concern (the package has no time / forcing).

---

## `gpu/rocm/HIST_ROCm.jl` — the same DNS on an AMD GPU

The device twin: the same physics, the same plots, but every array lives in GPU memory (`ROCArray`) and
scalar indexing of device arrays is **disabled** (`AMDGPU.allowscalar(false)`), so any stray scalar
index inside a package method *throws* — invariant 6 enforced, not trusted. Default element type is
**Float32**. It lives in its own sub-environment (AMDGPU is heavy and needs ROCm):

```sh
julia --project=examples/gpu/rocm -e 'using Pkg; Pkg.instantiate()'         # one-time (installs AMDGPU)
julia --project=examples/gpu/rocm examples/gpu/rocm/HIST_ROCm.jl --giant    # 320³ Float32, Re_λ≈130 (the documented figures)
julia --project=examples/gpu/rocm examples/gpu/rocm/HIST_ROCm.jl --mega     # 256³ Float32, Re_λ≈109
julia --project=examples/gpu/rocm examples/gpu/rocm/HIST_ROCm.jl --huge     # 192³ Float32, Re_λ≈93
julia --project=examples/gpu/rocm examples/gpu/rocm/HIST_ROCm.jl --fast     # 64³
julia --project=examples/gpu/rocm examples/gpu/rocm/HIST_ROCm.jl --smoke    # quick check
```

**Hassle-free on the GPU — the point of the preallocated rewrite.** Because the time loop is in-place
over a preallocated workspace and the package's in-place operators are allocation-free (the differential
operators allocate ~0 bytes — `docs/ARCHITECTURE.md` decision 24), the run creates **no per-step
garbage**: the AMDGPU memory pool stays flat, with **no manual `GC.gc()` / `reclaim`** and no wedge. A
representative **256³ Float32** run (`--mega`) on an RX 6700 XT (12 GB) — the earlier 12 GB ceiling, below
the 320³ RX 7900 XTX run behind the figures above — reaches $\mathrm{Re}_\lambda \approx 109$, $\kappa_{\max}\eta \approx 1.33$ (comfortably resolved), and sustains **≈ 87
ms/step** (9000 steps, ≈ 785 s of simulation), with the spectral-`inner` Parseval check matching the
physical energy to all printed digits and $\lVert\nabla\cdot u\rVert_{\text{rel}} \approx 1.6\times 10^{-7}$ (Float32 roundoff). It fits 12 GB because
the working set stays ≈ 6 GB (≈ 8 GB peak through the snapshots) — both the time loop and the radial
binning are allocation-bounded. This is about the practical $\mathrm{Re}_\lambda$ ceiling for the scheme: a lower $\nu$
raises $\mathrm{Re}_\lambda$ but drops $\kappa_{\max}\eta$ below ≈ 1.1, where the marginally-resolved flow blows up over a long
averaging window. `--huge` (192³, $\mathrm{Re}_\lambda \approx 93$) is the lighter, very comfortable fit. An *allocating* style would instead grow the device pool every step until it
wedges or `hipMalloc` aborts — which is exactly why a real GPU DNS preallocates.

The only non-package pieces left (gap list) are the random-solenoidal IC generator and the host-side
Lagrangian statistics — both representation-neutral, neither on the GPU hot path.
