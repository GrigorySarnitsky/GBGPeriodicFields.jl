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
second-order velocity structure functions**, each normalized by its Kolmogorov scaling (the layout of
Fig. A.1 in the accompanying thesis), alongside the energy spectrum, the stationarity history, and the
velocity autocorrelations. The goal is a readable, **performance-first** workflow: the time loop is
fully in-place over a preallocated workspace (no per-step field allocation) — both how a real DNS is
written and what keeps the GPU twin hassle-free.

```sh
julia --project=examples examples/HIST_CPU.jl            # full run (default 32³, ~1 min)
julia --project=examples examples/HIST_CPU.jl --fast     # 64³, nicer statistics
julia --project=examples examples/HIST_CPU.jl --huge     # 192³, Re_λ≈98 (heavy; minutes)
julia -t8 --project=examples examples/HIST_CPU.jl --fast  # 8 CPU threads (matters most at N ≥ 64)
julia --project=examples examples/HIST_CPU.jl --smoke    # tiny, ~seconds, for a quick check
julia --project=examples examples/plot_hist.jl examples/output/HIST_CPU.h5   # re-plot saved data, no re-run
```

Threading is **opt-in**: with no `-t` flag Julia (and the package's CPU threading, and FFTW) run on one
thread. At 32³ multithreading buys little; pass `-t8` once you raise `N`.

Output lands in `examples/output/`: the data dump `HIST_CPU.h5` (every plotted curve + the run scalars)
and the PNGs `structure_functions` (the headline two-panel Fig. A.1 figure), `spectrum`, `stationarity`,
`autocorrelation`, and a 2×2 `summary`.

### Method

Incompressible Navier–Stokes in **rotational form**, so the nonlinear step maps onto the package:

```
∂û/∂t = P[(u×ω)^] − ν k² û + f̂ ,   ω = ∇×u ,   P = Leray (Helmholtz) projection
```

- **Time integration:** integrating-factor RK2 (Heun) — viscosity exact via `exp(−νk²Δt)`, the
  nonlinear term explicit; `Δt` from advective CFL. The whole step is **in-place over a preallocated
  workspace** — `curl!`, `to_physical!`/`to_spectral!`, `cross!`, `helmholtz_projection!`, `convolve!`,
  and raw-array AXPYs write into preallocated buffers, so a step allocates no fields.
- **De-aliasing:** 2/3 rule, the package's `spectral_cutoff` sharp low-pass kernel (`convolve!`).
- **Forcing:** rescale the lowest shells (`1 ≤ |k| ≤ 2`) to a fixed energy each step — deterministic,
  unconditionally stationary (scaling preserves `∇·u = 0`).
- **Particles:** a few thousand tracers, RK2 advection on the start-of-step velocity via `interpolate`,
  positions wrapped periodically; per-tracer velocity recorded for the Lagrangian statistics. *(The
  time loop is the consumer's — the package has no concept of time, by design.)*

### What it exercises in the package

`Grid3D`, the field types, `FieldTransformPlans` + the in-place `to_physical!`/`to_spectral!`,
`FieldSpectralMultipliers`, the in-place `curl!`, `cross!`, `helmholtz_projection!`, `divergence`; the
**L²/measure reductions** `inner`/`l2norm` (energy `½ inner(u,u)`, dissipation `ν inner(ω,ω)`, the
divergence check `l2norm(∇·u)`), `radial_spectrum` (the energy spectrum `E(k)`) and
**`radial_correlation`** (the shell-averaged velocity autocorrelation `C(r)`, whose integral is the
integral length `L`, and from which the Eulerian trace structure function follows as
`S⁽ᴱ⁾(r) = ⅔(C(0)−C(r))`); **`convolve!` + `spectral_cutoff`** (the 2/3 de-alias filter, the `exp(−νk²Δt)`
integrating factor, the IC envelope); and `interpolate` (grid→point). The hot loop uses the **in-place,
allocation-free** `!` forms throughout — the spectral operators allocate ~0 bytes (`docs/ARCHITECTURE.md`
decision 24) — and the CFL speed uses `maximum(abs, field_data(u))` rather than `lpnorm` (the latter
materializes a magnitude field). Built-in correctness cross-checks: the Parseval identity
`½ inner(û,û) == ½⟨|u|²⟩` and `‖∇·u‖ ≈ roundoff` (both asserted).

### Reading the plots (and the Reynolds-number caveat)

The headline `structure_functions` figure follows thesis Fig. A.1: the Eulerian and Lagrangian **trace**
structure functions, each normalized by its Kolmogorov inertial scaling —
`S⁽ᴱ⁾(Δx) / [(11/9) C₂ ε²ᐟ³ Δx²ᐟ³]` vs `Δx/η`, and `S⁽ᴸ⁾(Δt) / [C₀ ε Δt]` vs `Δt/τ_η` (`C₂=2.1`,
`C₀=6.0`). A K41 inertial range shows as a **plateau at 1**. Marked on each panel are the **Taylor** and
**integral** scales — `λ/η` and `L/η` (Eulerian), `√(τ_η·τ_u)/τ_η` and `τ_u/τ_η` (Lagrangian) — where the
integral length `L` and time `τ_u` are measured as the **integrals of the velocity autocorrelations**
(`L = ∫ρ(r)dr` from `radial_correlation`; `τ_u = ∫ρ_L(τ)dτ` from the tracked particles); the
`autocorrelation` figure shows the two `ρ` curves. The Lagrangian Taylor-time marker uses the
log-midpoint proxy `√(τ_η·τ_u)` — so it needs no acceleration statistics.

At the default **32³** (`Re_λ ≈ 16`) there is essentially no inertial range, so the normalized curves
form a hump rather than a plateau, and `λ ≈ L` (the scales have not separated) — expected, not a bug.
**`--huge` (192³, `Re_λ ≈ 98`)** separates them cleanly (`λ/η ≈ 19`, `L/η ≈ 45`) and the Eulerian curve
approaches the plateau. The `spectrum` concentrates energy at large scales and falls through the
dissipation range; `E(t)`, `ε(t)` are statistically steady past the spin-up.

### Knobs

All in the `Params` struct at the top: `N`, `ν`, forcing band/energy (`k_force`, `E_force`), `cfl`,
step counts (`n_spinup`, `n_stats`), `n_particles`, recording strides, `seed`. The
`smoke()` / `fast()` / `huge()` configurations select 32³ / 64³ / 192³.

---

## Gap list — what this example reveals the package still lacks

Each item the example surfaced as a hand-roll is a candidate for promotion into the package. The GPU
twin (`allowscalar(false)`) forced most of them in.

**Closed:**

- ✅ **Reductions over a field** (`Reductions`): `integral`, `inner`, `l2norm`, `lpnorm`, `mean`/`std`/…
- ✅ **Apply a diagonal spectral operator `f(k)`** (`Convolution`): `convolve!` + `spectral_cutoff`.
- ✅ **`|k|`-field and shell-band utilities** (`Convolution`): `squared_wavenumber_field`, `spectral_band`.
- ✅ **Energy spectrum `E(k)`** (`Reductions`): `radial_spectrum`.
- ✅ **Eulerian structure function without a hand-rolled spatial shift** — `S⁽ᴱ⁾(r) = ⅔(C(0)−C(r))` reads
  straight off the FFT-based `radial_correlation` (the shell-averaged velocity autocorrelation), so the
  earlier `circshift` reach-in is gone; the integral length `L = ∫ρ(r)dr` comes from the same call.

**Still open** (the script hand-rolls these, both representation-neutral):

1. **Random solenoidal field generator** with a target spectrum (an initial-condition helper). The
   script builds the random field + envelope + Helmholtz projection by hand.
2. *Minor:* `gradient(vector)→tensor` for the velocity-gradient tensor, which the script sidesteps via
   the homogeneous identity `ε = ν⟨|ω|²⟩`; and the Lagrangian autocorrelation / structure function are
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
julia --project=examples/gpu/rocm examples/gpu/rocm/HIST_ROCm.jl --huge     # 192³ Float32, Re_λ≈98
julia --project=examples/gpu/rocm examples/gpu/rocm/HIST_ROCm.jl --fast     # 64³
julia --project=examples/gpu/rocm examples/gpu/rocm/HIST_ROCm.jl --smoke    # quick check
```

**Hassle-free on the GPU — the point of the preallocated rewrite.** Because the time loop is in-place
over a preallocated workspace and the package's in-place operators are allocation-free (the spectral
operators allocate ~0 bytes — `docs/ARCHITECTURE.md` decision 24), the run creates **no per-step
garbage**: the AMDGPU memory pool stays flat, with **no manual `GC.gc()` / `reclaim`** and no wedge. A
representative **192³ Float32** run on an RX 6700 XT (12 GB) reaches `Re_λ ≈ 98`, `k_max·η ≈ 1.1`
(resolved), and sustains **≈ 42 ms/step** (2000 steps, ≈ 83 s of simulation), with the spectral-`inner`
Parseval check matching the physical energy to all printed digits and `‖∇·u‖_rel ≈ 1e-8` (Float32
roundoff). At fixed forcing the Reynolds number is set by `ν`, not the grid, so 192³ already gives the
scale separation; a larger grid only adds dissipation-range resolution, at more memory (192³ is a
comfortable fit on 12 GB). An *allocating* style would instead grow the device pool every step until it
wedges or `hipMalloc` aborts — which is exactly why a real GPU DNS preallocates.

The only non-package pieces left (gap list) are the random-solenoidal IC generator and the host-side
Lagrangian statistics — both representation-neutral, neither on the GPU hot path.
