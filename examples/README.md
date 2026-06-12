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
  nonlinear term explicit; `Δt` from advective CFL. The integrating factor is a consumer-built
  `ScalarFieldSpectral` kernel applied with `convolve` (the coefficientwise multiply `f̂·ĝ`).
- **De-aliasing:** 2/3 rule, as the package's `spectral_cutoff` sharp low-pass kernel (`convolve`).
- **Forcing:** rescale the lowest shells (`1 ≤ |k| ≤ 2`) to a fixed energy each step — deterministic,
  unconditionally stationary (scaling preserves `∇·u = 0`).
- **Particles:** ~2000 tracers, RK2 advection on the start-of-step velocity via `interpolate`,
  positions wrapped periodically; per-tracer velocity recorded for the Lagrangian statistics. *(The
  time loop is the consumer's — the package has no concept of time, by design.)*

### What it exercises in the package

`Grid3D`, the field types, `FieldTransformPlans` + `to_physical`/`to_spectral`,
`FieldSpectralMultipliers`, `curl`, `cross`, `helmholtz_projection`, `divergence`; the **L²/measure
reductions** `inner`/`l2norm`/`lpnorm` (energy `½ inner(u,u)`, dissipation `ν inner(ω,ω)`, the CFL
speed `lpnorm(u,Inf)`, and the divergence check `l2norm(∇·u)`); **`convolve` + `spectral_cutoff`**
(the 2/3 de-alias filter, the `exp(−νk²Δt)` integrating factor, the IC envelope — all diagonal Fourier
multipliers); and `interpolate` (grid→point, returning `VectorPointValues`). Two built-in correctness
cross-checks: the Parseval identity `½ inner(û,û) == ½⟨|u|²⟩` (the package's spectral `inner` reproduces
the physical energy exactly) and `‖∇·u‖ ≈ roundoff` (the run asserts both).

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

Each item the example surfaced as a hand-roll is, by design, a candidate for promotion into the
package. Most are now closed — the GPU twin (`allowscalar(false)`) forced the remaining ones in.

**Closed:**

- ✅ **Reductions over a field** (`Reductions`): `integral`, `inner`, `l2norm`, `lpnorm`,
  `mean`/`std`/`var`/`maximum`. The script uses `½ inner(u,u)`, `ν inner(ω,ω)`, `lpnorm(u, Inf)`,
  `l2norm(∇·u)` — no `field_data` reach-in for the energetics.
- ✅ **Apply a diagonal spectral operator `f(k)`** (`Convolution`): `convolve` applies any
  `ScalarFieldSpectral` transfer function; `spectral_cutoff` builds the sharp isotropic low-pass.
  The 2/3 de-alias filter is `spectral_cutoff`; the `exp(−νk²Δt)` integrating factor and the IC
  envelope are consumer-built kernels applied with `convolve` (ν, Δt, width are physics — invariant 12).
- ✅ **`|k|`-field and shell band utilities** (`Convolution`, decision 21): `squared_wavenumber_field`
  is the `|k|²` radial coordinate (the consumer builds `exp(−νk²Δt)` / the envelope from it);
  `spectral_band(ref, mult, k_lo, k_hi)` is the annular band-pass. The **forcing** is now pure package
  ops — band energy `= ½ inner(convolve(û, band), û)`, rescale via `convolve` — no shell loop.
- ✅ **Energy spectrum `E(k)`** (`Reductions`, decision 21): `radial_spectrum(û, mult)` is the
  shell-resolved Parseval inner (`sum(spectrum) == inner`); the consumer's `E = ½ spectrum`. The
  binning is device-clean (masked reductions), so on the GPU the spectrum needs no host copy.

**Still open** (the script hand-rolls these on `field_data`, both representation-neutral):

1. **Random solenoidal field generator** with a target spectrum (an initial-condition helper). The
   script builds the random field + envelope + Helmholtz projection by hand.
2. *Minor:* a periodic field-shift helper (the Eulerian `S₂` uses `circshift` on the raw array); and
   `gradient(vector)→tensor` for the velocity-gradient tensor, which the script sidesteps via the
   homogeneous identity `ε = ν⟨|ω|²⟩`.

Forcing and time integration themselves stay a *consumer* concern (the package has no time/forcing);
what the package now supplies is every spectral primitive they are built from.

---

## `gpu/rocm/HIST_ROCm.jl` — the same DNS on an AMD GPU

The device twin of `HIST_CPU.jl`: the same physics and the same four plots, but every array lives in
GPU memory (`ROCArray`) and **scalar indexing of device arrays is disabled** (`AMDGPU.allowscalar(false)`),
so any stray scalar index inside a package method *throws* — invariant 6 enforced, not trusted. Default
element type is **Float32** (realistic consumer-GPU precision). It lives in its own sub-environment
(AMDGPU is heavy and needs ROCm) — exactly like `test/gpu/rocm` and `benchmark/gpu/rocm`:

```sh
julia --project=examples/gpu/rocm -e 'using Pkg; Pkg.instantiate()'        # one-time (installs AMDGPU)
julia --project=examples/gpu/rocm examples/gpu/rocm/HIST_ROCm.jl           # full run
julia --project=examples/gpu/rocm examples/gpu/rocm/HIST_ROCm.jl --smoke   # quick check
```

**What the GPU forced into the package.** With `allowscalar(false)`, the CPU script's hand-rolled
`field_data` loops cannot run on-device — so they drove the spectral primitives into the package (the
"closed" gaps above). The result: **the GPU twin runs the exact same source as `HIST_CPU.jl` for the
forcing and the spectrum** — `spectral_band` + `inner` + `convolve` for the forcing, `radial_spectrum`
for E(k) — on device arrays, with no host copy and no scalar-indexed mask. The energetics
(`inner`/`l2norm`/`lpnorm`), every diagonal-Fourier apply (`convolve` / `spectral_cutoff` /
`spectral_band` / `squared_wavenumber_field`), and the shell-resolved spectrum all run unchanged
on-device. A representative Float32 run reports `K ≈ 0.67`, `Re_λ ≈ 15`, `k_max·η ≈ 1.6`,
`‖∇·u‖_rel ≈ 1e-8` (Float32 roundoff), and the spectral-`inner` Parseval check matches the physical
energy to all printed digits.

The only non-package pieces left (gap list above) are the random-solenoidal IC generator and the
Eulerian-`S₂` field-shift — both representation-neutral and host-side here, neither on the GPU hot path.
