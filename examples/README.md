# Examples

Small, self-contained programs that drive **GBGPeriodicFields** the way a real consumer would.
They double as a check on the public API: anything an example has to *hand-roll* is a candidate for
promotion into the package (see **Gap list** below).

This environment is separate from the package and from `test/` / `benchmark/`; the package is a path
dependency via `[sources]`. Manifest and rendered plots are gitignored.

```sh
julia --project=examples -e 'using Pkg; Pkg.instantiate()'   # one-time
```

---

## `HIST_CPU.jl` — forced homogeneous isotropic stationary turbulence (CPU)

A *minimal, demonstration* pseudospectral DNS of forced HIT that plots the **Eulerian and Lagrangian
second-order velocity structure functions**. The goal is a readable end-to-end workflow, **not** a
production solver.

```sh
julia --project=examples examples/HIST_CPU.jl            # full run (default 32³, ~1 min), single-threaded
julia -t8 --project=examples examples/HIST_CPU.jl        # use 8 CPU threads (matters most at N ≥ 64)
julia --project=examples examples/HIST_CPU.jl --smoke    # tiny, ~seconds, for a quick check
```

Threading is **opt-in**: with no `-t` flag Julia runs on one thread, so the package's CPU threading
(and FFTW) stay serial — the run prints `threads: Julia=N` at startup. At 32³ multithreading buys
little (the memory-bandwidth-bound algebra/operators barely thread — PERFORMANCE.md §6 — and much of
the wall-clock is one-time Plots compilation); pass `-t8` once you raise `N` for cleaner statistics.

Output PNGs land in `examples/output/`: `spectrum`, `stationarity`, `eulerian_s2`, `lagrangian_s2`,
and a 2×2 `summary`.

### Method

Incompressible Navier–Stokes in **rotational form**, so the nonlinear step maps onto the package:

```
∂û/∂t = P[(u×ω)^] − ν k² û + f̂ ,   ω = ∇×u ,   P = Leray (Helmholtz) projection
```

- **Time integration:** integrating-factor RK2 (Heun) — viscosity exact via `exp(−νk²Δt)`, the
  nonlinear term explicit; `Δt` from advective CFL.
- **De-aliasing:** 2/3 rule.
- **Forcing:** rescale the lowest shells (`1 ≤ |k| ≤ 2`) to a fixed energy each step — deterministic,
  unconditionally stationary (scaling preserves `∇·u = 0`).
- **Particles:** ~2000 tracers, RK2 advection on the start-of-step velocity via `interpolate`,
  positions wrapped periodically; per-tracer velocity recorded for the Lagrangian statistics. *(The
  time loop is the consumer's — the package has no concept of time, by design.)*

### What it exercises in the package

`Grid3D`, the field types, `FieldTransformPlans` + `to_physical`/`to_spectral`,
`FieldSpectralMultipliers`, `curl`, `cross`, `helmholtz_projection`, `divergence`, and `interpolate`
(grid→point, returning `VectorPointValues`). Two built-in correctness cross-checks: the Parseval
identity `Σ E(k) == ½⟨|u|²⟩` and `‖∇·u‖ ≈ roundoff` (the run asserts both).

### Reading the plots (and the 32³ caveat)

At the default **32³** there is essentially no inertial range, so the K41 guides (`k⁻⁵ᐟ³`, `r²ᐟ³`,
`∝ τ`) are **references, not fits** — the data is not expected to follow them. What *is* meaningful:
the spectrum concentrates energy at large scales and falls off through the dissipation range; `E(t)`
and `ε(t)` are statistically steady past the spin-up; `S₂(r)` rises and rolls over to the `2u'²`
plateau; `S₂(τ)` rises from the ballistic small-τ regime to the decorrelation plateau. A representative
run reports `K ≈ 0.67`, `ε ≈ 0.25`, `Re_λ ≈ 16`, `k_max·η ≈ 1.6` (resolved). **For clean scaling
ranges, raise `N` to 64 or 128** (edit `Params`) and lengthen the run — the script is otherwise
unchanged.

### Knobs

All in the `Params` struct at the top of the file: `N`, `ν`, forcing band/energy (`k_force`,
`E_force`), `cfl`, step counts (`n_spinup`, `n_stats`), `n_particles`, recording strides, `seed`.

---

## Gap list — what this example reveals the package still lacks

Each item is something the script computes on raw `field_data(...)` arrays (fine on CPU; **forbidden
on GPU under `allowscalar(false)`**). The forthcoming `HIST_ROCm.jl` will make #1 and #2 mandatory.

1. **Reductions over a field** — even `K = ½·mean(|u|²)`, `ε = ν·mean(|ω|²)`, and `max|u|` require
   reaching into `field_data` and calling `mean`/`maximum`. There is no public
   `mean`/`l2norm`/`maximum`/`energy`/`enstrophy`. (Reductions are deferred by design — this pins down
   the device-portable API shape needed.)
2. **Apply a diagonal spectral operator `f(k)`** — the 2/3 de-alias mask, the integrating factor
   `exp(−νk²Δt)`, and the IC envelope all multiply a spectral field by a per-mode real factor. The
   package owns the wavenumber arrays (`m.squared_wavenumber_1..3`) and diagonal kernels internally
   but exposes no public "apply `f(k)`".
3. **`|k|`-field and shell utilities** — a wavenumber-magnitude field, shell masks/bands, and a
   shell-average (for the spectrum `E(k)`), all derivable from `m.squared_wavenumber_*` but not
   exposed.
4. **Random solenoidal field generator** with a target spectrum (an initial-condition helper).
5. **Energy spectrum `E(k)`** as a first-class diagnostic (a binned spectral reduction; built here by
   hand with the rfft Parseval weighting).
6. *Minor:* a periodic field-shift helper (the Eulerian `S₂` uses `circshift` on the raw array); and
   `gradient(vector)→tensor` for the velocity-gradient tensor, which this script sidesteps via the
   homogeneous identity `ε = ν⟨|ω|²⟩`.

Forcing itself stays a *consumer* concern (the package has no time/forcing), but it needs the shell
access of #2/#3.

---

## `HIST_ROCm.jl` — *(planned)*

The same physics with `array_type = ROCArray` and `allowscalar(false)`. Because the scalar-indexed
hand-rolled pieces above (reductions, the `f(k)` apply, the forcing band) cannot run on the device,
this twin is what will drive gaps #1–#3 into the package as device-portable operations.
