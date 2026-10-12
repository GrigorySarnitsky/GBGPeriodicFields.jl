## =============================================================================
# `HIST_CUDA.jl` runs forced Homogeneous Isotropic Stationary Turbulence on an NVIDIA GPU.
# It is `gpu/rocm/HIST_ROCm.jl` with the device package and array type swapped (`CUDA`, `CuArray`);
# the timings and memory figures quoted in the configuration notes below were measured on AMD cards
# unless they say otherwise.
#
# The device twin of `examples/HIST_CPU.jl`: the SAME pseudospectral DNS and the same
# plots, but every array lives in GPU memory (`CuArray`) and scalar indexing of
# device arrays is DISABLED (`CUDA.allowscalar(false)`) — so any stray scalar
# index inside a package method throws, turning the package's no-scalar-indexing
# GPU rule into a checked guarantee. Default element type is `Float32`, the
# realistic consumer-GPU precision.
#
# Like its CPU sibling this is a DEMONSTRATION, not the production solver: the full pseudospectral
# DNS built on this package is
# [`GBGHomogeneousTurbulence.jl`](https://grigorysarnitsky.github.io/GBGHomogeneousTurbulence.jl).
#
# Read `HIST_CPU.jl` first; this file flags only what CHANGES for the GPU:
#
# - All field storage is built from device arrays (`dev(...)`); the FFT plans,
#   spectral multipliers (the wavenumber arrays the derivatives use) and the shell-mask kernels land on-device automatically.
# - The package operations are backend-agnostic and run unchanged: `curl`, `cross`,
#   `helmholtz_projection`, the transforms, the ``L^{2}``/measure reductions
#   (`inner`/`l2norm`/`lpnorm`, `radial_spectrum`, and `radial_correlation`),
#   `convolve` with the kernel builders (`spectral_cutoff` / `spectral_band` /
#   `radial_kernel`), the lazy `exponential_convolve!`, and `interpolate`.
# - There is now NOTHING device-special left to hand-roll. The forcing band is a
#   `spectral_band` kernel (band energy via `inner`, rescale via `convolve`) and the
#   energy spectrum is `radial_spectrum` (on-device shell binning, no host copy) —
#   the same source as `HIST_CPU.jl`, run on device arrays. The only remaining
#   non-package bit is the random-solenoidal IC generator, which is representation-neutral.
#
# Like `HIST_CPU.jl`, the run is split into **simulate**, **dump** and **plot** stages: every
# plotted curve is written to `output/HIST_CUDA_<preset>.h5` (`HIST_CUDA_giant.h5` for `--giant`,
# `HIST_CUDA_default.h5` with no flag, so a quick run never overwrites a long one) and the figures (the compensated
# structure-function layout, the spectrum, the stationarity history and the velocity
# autocorrelations) are rendered by the shared `examples/hist_postprocess.jl` — the last
# line below re-plots without re-running.
#
# ```sh
# julia --project=examples/gpu/cuda examples/gpu/cuda/HIST_CUDA.jl            # full run (default 32³)
# julia --project=examples/gpu/cuda examples/gpu/cuda/HIST_CUDA.jl --giant    # 320³ Float32, Re_λ≈130 (the documented figures; fits a 16 GB card)
# julia --project=examples/gpu/cuda examples/gpu/cuda/HIST_CUDA.jl --mega     # 256³ Float32, Re_λ≈109
# julia --project=examples/gpu/cuda examples/gpu/cuda/HIST_CUDA.jl --huge     # 192³ Float32, Re_λ≈93
# julia --project=examples/gpu/cuda examples/gpu/cuda/HIST_CUDA.jl --fast     # 64³, for nicer statistics
# julia --project=examples/gpu/cuda examples/gpu/cuda/HIST_CUDA.jl --smoke    # quick check
# julia --project=examples examples/plot_hist.jl examples/gpu/cuda/output/HIST_CUDA_giant.h5   # re-plot, no re-run
# ```
## =============================================================================

using CUDA
CUDA.allowscalar(false)                  # invariant 6, mechanically enforced

using GBGPeriodicFields
using GBGPeriodicFields: field_data, field_grid          # raw-array / grid accessors
using Random, Statistics, Printf, LinearAlgebra

const OUTDIR = joinpath(@__DIR__, "output")
const FT = Float32                         # element type (Float32 = realistic GPU precision)
dev(host_array) = CuArray(host_array)     # move a host array onto the device
include(joinpath(@__DIR__, "..", "..", "hist_postprocess.jl"))   # statistics, HDF5 I/O, plots (shared)


## =============================================================================
# Parameters
## =============================================================================

Base.@kwdef struct Params
  N::Int          = 32          # grid points per side
  L::Float64      = 2π          # box size (so wavenumbers are integers)
  ν::Float64      = 5.0e-2      # kinematic viscosity (tuned for k_max·η ≳ 1 at 32^3)
  k_force::Int    = 2           # force shells 1 ≤ |k| ≤ k_force
  E_force::Float64 = 0.6        # energy held in the forced band (sets the velocity scale)
  cfl::Float64    = 0.5         # advective CFL number
  n_spinup::Int   = 1500        # steps to reach stationarity (statistics discarded)
  n_stats::Int    = 2000        # steps over which statistics are collected
  n_particles::Int = 2000       # Lagrangian tracers
  rec_stride::Int = 3           # record particle velocity every this many stats steps
  snap_stride::Int = 100        # take an Eulerian SF snapshot every this many stats steps
  seed::Int       = 42
end

# A tiny configuration for a quick end-to-end check (`--smoke`).
smoke() = Params(n_spinup = 15, n_stats = 40, n_particles = 300, rec_stride = 1, snap_stride = 10)

# A larger, still-quick configuration for nicer statistics (`--fast`) — ``64^{3}``, more tracers.
fast() = Params(N = 64, n_spinup = 400, n_stats = 800, n_particles = 4000, rec_stride = 2, snap_stride = 40)

# A high-Reynolds configuration (`--huge`) — ``192^{3}`` at a lower viscosity. At fixed forcing the
# Reynolds number (``\mathrm{Re}_\lambda \approx 93``) is set by ``\nu``, not the grid, so this already
# gives the scale separation ``\lambda \ll L``, ``\tau_\eta \ll \tau_u``; the grid only has to RESOLVE
# it (``\kappa_{\max}\eta \approx 1.13`` here), and ``192^{3}`` is a comfortable fit on a 12 GB card.
# The CFL is conservative (0.3) and ``\nu`` carries a resolution margin **because the statistics-window
# ``\Delta t`` is frozen** (for a uniform Lagrangian axis): over a long averaging window a CFL-tight,
# marginally-resolved run eventually hits a velocity peak that the frozen ``\Delta t`` cannot handle
# and blows up — the conservative CFL is what keeps the long run stable. The `n_spinup` steps clear
# the initial energy overshoot; `n_stats` time-averages over a few of the forcing's energy-oscillation
# periods (see the `mega` note below). A few minutes on the GPU.
huge() = Params(N = 192, ν = 3.2e-3, cfl = 0.3, n_spinup = 3300, n_stats = 4700, n_particles = 8000,
                rec_stride = 4, snap_stride = 60)

# Push the grid to ``256^{3}`` (`--mega`) at a lower viscosity than `--huge`: measured
# ``\mathrm{Re}_\lambda \approx 109`` with ``\kappa_{\max}\eta \approx 1.3`` (comfortably resolved),
# ``\approx 90`` ms/step on the earlier 12 GB RX 6700 XT, since replaced by the 24 GB RX 7900 XTX
# behind the `--giant` figures. This is the practical Reynolds ceiling for the scheme — a
# lower viscosity (``\nu = 2\times10^{-3}``, ``\mathrm{Re}_\lambda \approx 120``) drops
# ``\kappa_{\max}\eta`` to ``\approx 1.08``, where the marginally-resolved flow blows up over a long
# run. It fits a 12 GB card only because *both* the time loop and the diagnostics are
# allocation-bounded: the hot loop is allocation-free and the radial binning is a single scatter-add
# pass (the per-shell form materialized ``\sim N`` full-grid temporaries per snapshot and wedged the
# card). The footprint is essentially flat at the preallocated working set (``\approx 6`` GB, with an
# ``\approx 8`` GB peak through the snapshots).
#
# Stationarity (the same recipe as `huge`): the band-rescaling forcing, from a low-energy smooth
# initial condition, makes ``k(t)`` overshoot its mean near ``t \approx 7`` turnovers and then
# *oscillate* about it with a slowly-damped ``\approx 7``-turnover period — it does not settle to a
# flat plateau. So `n_spinup` clears the overshoot (measured in turnover times — at ``256^{3}`` the
# finer grid forces a smaller ``\Delta t``, hence more steps than the coarser grids for the same
# physical time) and `n_stats` time-averages over a few oscillation periods. The CFL is conservative
# (0.3) because the statistics-window ``\Delta t`` is frozen (for a uniform Lagrangian axis): over a
# long run a CFL-tight, marginally-resolved field eventually hits a velocity peak the frozen
# ``\Delta t`` cannot handle.
mega() = Params(N = 256, ν = 2.5e-3, cfl = 0.3, n_spinup = 4500, n_stats = 4500, n_particles = 8000,
                rec_stride = 4, snap_stride = 100)

# The `--giant` configuration — ``320^{3}`` at ``\nu = 1.85\times10^{-3}``
# (``\kappa_{\max}\eta \approx 1.3``, `mega`'s resolution one grid level up): time-averaged
# ``\mathrm{Re}_\lambda \approx 130``, ``\approx 51`` ms/step at an ``\approx 9.9`` GB peak on a 16 GB
# RTX 5070 Ti (2026-10-08) — the configuration and run behind the documented figures, whose data is
# committed as `examples/figures/HIST_CUDA_giant.h5`. The forcing oscillates (a period of about ten
# time units here; see the `mega` note), so the `n_stats` window time-averages the statistics over
# about two full oscillation periods, and the ``k(t)/\varepsilon(t)`` history shows that bounded
# oscillation about a constant mean (``\mathrm{Re}_\lambda \approx 130`` is the time-averaged value,
# not an instantaneous one).
giant() = Params(N = 320, ν = 1.85e-3, cfl = 0.3, n_spinup = 7000, n_stats = 16000, n_particles = 8000,
                 rec_stride = 4, snap_stride = 100)


## =============================================================================
# Spectral utilities (device). The diagonal-in-Fourier operators — de-aliasing,
# the integrating factor ``\exp(-\nu \kappa^{2}\Delta t)``, the initial-condition envelope — are
# applied with the package's `convolve` (periodic convolution = a coefficientwise
# multiply by a transfer function ``\hat{g}``); the de-alias filter is
# `spectral_cutoff`, and the physics kernels (carrying ``\nu``, ``\Delta t``, the
# envelope width) are radial functions of ``\lvert\mathbf{k}\rvert^{2}`` the consumer
# supplies — the package carries no physics. All of these operate on whatever backend the reference field lives
# on, so on the GPU they stay entirely on-device.
## =============================================================================

# A kernel is its own kind of object rather than a field of coefficients, and the physics kernels here
# — the viscous integrating factor and the initial envelope — are radial symbols of
# ``\lvert\mathbf{k}\rvert^{2}``, so neither needs a device array of coefficients at all:
# `exponential_convolve!` evaluates ``\exp(-\nu\lvert\mathbf{k}\rvert^{2}\Delta t)`` per mode from the
# wavenumber arrays, and `radial_kernel` stores a closure. The consumer never hand-rolls a wavenumber
# broadcast either way.


# Preallocated DEVICE scratch for the in-place hot loop, so a step allocates nothing — and therefore
# the `CUDA` memory pool never grows (no wedge, no manual GC / `reclaim`). An allocating loop would
# pile up device temporaries faster than Julia's host-triggered GC frees them; preallocation is the
# fix. This is how a real GPU DNS is written: performance first.
function make_workspace(physical_reference, spectral_reference)
  ## `similar_field` copies the reference's representation, grid AND storage backend, so on
  ## this device twin the scratch lands in GPU memory without a `dev(...)` in sight — the
  ## same source as `HIST_CPU.jl`. Its storage is uninitialized, hence the zeroing.
  scratch(reference, order) = (field = similar_field(reference, order); field .= 0; field)
  spectral_vector() = scratch(spectral_reference, Val(1))
  physical_vector() = scratch(physical_reference, Val(1))
  return (ωh = spectral_vector(), k1 = spectral_vector(), k2 = spectral_vector(),
          ustar = spectral_vector(), uhc = spectral_vector(), tmp = spectral_vector(),
          Nt = spectral_vector(),                          # (u×ω)^ scratch (distinct helmholtz source)
          u = physical_vector(), ω0 = physical_vector(), ω = physical_vector(),
          uω = physical_vector(), uxω = physical_vector())
end


## =============================================================================
# Diagnostics — every one is a package reduction, running on-device unchanged
# (`sum`/`dot`/`maximum` are GPU-portable): the kinetic energy
# ``\tfrac{1}{2}\langle\lvert u\rvert^{2}\rangle``, the dissipation
# ``\nu\langle\lvert\omega\rvert^{2}\rangle``, the CFL speed, and — now also
# on-device — the energy spectrum via `radial_spectrum` (a single scatter-add
# shell-binning pass, no host copy, no scalar indexing).
## =============================================================================

kinetic_energy(u) = 0.5 * inner(u, u)                                 # ½⟨|u|²⟩   (Reductions.inner)
dissipation(ω, p) = p.ν * inner(ω, ω)                                 # ν⟨|ω|²⟩   (homogeneous)
# CFL speed: ``\max_i \lvert u_i\rvert``, the largest velocity component in absolute value — an
# allocation-free device reduction over the raw array. (`lpnorm(u, Inf)` is the true
# ``\sup\lvert u\rvert`` but materializes a magnitude field every call — avoided so the hot loop keeps
# the GPU pool flat; the max component under-estimates the magnitude by at
# most ``\sqrt{3}``, so the effective CFL number is at most that much larger than the nominal one —
# absorbed by the conservative `cfl` the long runs use.)
max_speed(u)      = maximum(abs, field_data(u))

# The spectrum is half the shell-resolved Parseval inner, ``E(\kappa) = \tfrac{1}{2} P(\kappa)``, so the shell sum recovers the
# turbulent kinetic energy: ``\sum_\kappa E(\kappa) = \tfrac{1}{2}\langle\lvert u\rvert^{2}\rangle = k``.
# The `radial_spectrum` reduction bins on-device and returns small host vectors — no host copy of
# the field.
function energy_spectrum(uh, m)
  shells, spectrum = radial_spectrum(uh, m)                            # device binning (package)
  return shells, 0.5 .* spectrum
end


## =============================================================================
# Forcing — hold the kinetic energy in the shells from ``\lvert\mathbf{k}\rvert = 1``
# up to `k_force` at `E_force`, now pure package ops (identical to `HIST_CPU.jl`):
# `band` is a `spectral_band` mask kernel; the band energy is
# ``\tfrac{1}{2}\langle\lvert u_{\mathrm{band}}\rvert^{2}\rangle``, computed as
# `FT(0.5) * inner(ws.tmp, ws.tmp)` on the workspace's scratch field `ws.tmp` (Parseval; the same-argument `inner(f, f)` is
# allocation-free); rescaling the in-band modes goes through `helmholtz_projection!`
# with the band as its kernel, so only the solenoidal part is amplified, and
# `reality_projection!` then drops the coefficients no real field has; without
# either, a long run's rounding error in the band grows step after step (see
# `HIST_CPU.jl`). No precomputed mask / weight, no sum-reduction by hand — all
# on-device.
## =============================================================================

function force!(uh, band, ws, p, m)
  convolve!(ws.tmp, uh, band)                             # band-pass copy into scratch (no allocation)
  band_kinetic = FT(0.5) * inner(ws.tmp, ws.tmp)         # ½⟨|u_band|²⟩ = ½ inner(u_band,u_band): f===f ⇒ allocation-free
  band_kinetic < FT(1e-12) && return uh                   # guard (the initial condition seeds the band)
  scale = sqrt(FT(p.E_force) / band_kinetic)
  helmholtz_projection!(uh, uh, m, band, scale - 1, 1)  # rescale the band's solenoidal part (α/β, alloc-free)
  reality_projection!(uh)                                 # drop what no real field has (two planes)
  return uh
end


## =============================================================================
# Right-hand side and time integration — IN-PLACE, no per-step allocation
# (identical structure to `HIST_CPU.jl`). The work fields live in the preallocated
# device `ws`; the package's in-place operators (`curl!`, `to_physical!`, `cross!`,
# `to_spectral!`, `helmholtz_projection!`, `convolve!`) write into them on-device,
# and the linear combinations are in-place device broadcasts. Nothing allocates, so
# the `CUDA` pool stays flat — no wedge, no manual `reclaim` (that was the
# allocating style).
## =============================================================================

# Physical velocity & vorticity of a field in spectral representation, into the given buffers. The `uh` buffer is preserved by
# transforming a COPY of it — `to_physical!` may overwrite its spectral source as scratch.
function to_velocity_vorticity!(u_out, ω_out, uh, ws, m, plans)
  curl!(ws.ωh, uh, m)                          # ω̂ = ∇×û  (û preserved)
  to_physical!(ω_out, ws.ωh, plans)            # physical vorticity (consumes ω̂)
  copyto!(field_data(ws.uhc), field_data(uh))  # keep û: transform a scratch copy
  to_physical!(u_out, ws.uhc, plans)           # physical velocity (consumes the copy)
  return u_out, ω_out
end

# The buffer `Nh` holds ``\hat{N}``, the de-aliased Leray projection of
# ``\widehat{u\times\omega}`` formed from physical ``u`` and ``\omega``.
function rhs!(Nh, u, ω, ws, m, plans, dealias)
  cross!(ws.uxω, u, ω)                          # u × ω  (physical)
  to_spectral!(ws.Nt, ws.uxω, plans)            # (u×ω)^ into scratch
  helmholtz_projection!(Nh, ws.Nt, m)           # Leray projection — DISTINCT dest ⇒ no-alias path (no allocation)
  convolve!(Nh, Nh, dealias)                    # 2/3 de-alias (coefficientwise multiply)
  mean_free_projection!(Nh)                     # the mean of u × ω is zero; drop its rounding error
  return Nh
end

# This function takes one integrating-factor RK2 (Heun) step, fully in place. The integrating factor
# ``\mathcal{E} = \exp(-\nu \kappa^{2}\Delta t)`` (``\nu``, ``\Delta t`` are physics
# the package never sees) is applied with `exponential_convolve!`, which evaluates it per mode from
# the wavenumber arrays, so no kernel field is built, stored, or read. It assumes `ws.u`, `ws.ω0` hold the
# START-of-step physical velocity & vorticity (the loop fills them and uses them for the
# diagnostics), so the first stage reuses them. With ``\hat{N}`` the de-aliased
# projected nonlinearity (the buffers `ws.k1`, `ws.k2` hold ``\hat{N}_1``, ``\hat{N}_2``):
#
# ```math
# \begin{aligned}
# \hat{N}_1 &= \hat{N}(\hat{u}_n), &
# \hat{u}^{*} &= \mathcal{E} (\hat{u}_n + \Delta t \hat{N}_1), \\
# \hat{N}_2 &= \hat{N}(\hat{u}^{*}), &
# \hat{u}_{n+1} &= \mathcal{E} \hat{u}_n + \tfrac{\Delta t}{2} (\mathcal{E} \hat{N}_1 + \hat{N}_2),
# \end{aligned}
# ```
#
# then force.
function step!(uh, ws, m, plans, dealias, band, p, dt)
  rhs!(ws.k1, ws.u, ws.ω0, ws, m, plans, dealias)                       # k₁ = N̂(ûₙ)  (cached start-of-step u, ω)
  field_data(ws.ustar) .= field_data(uh) .+ FT(dt) .* field_data(ws.k1)
  ## the stage's display math is in the block above; this factor is evaluated per mode from
  ## the wavenumber arrays, so no kernel field is built, one fewer device array resident.
  exponential_convolve!(ws.ustar, ws.ustar, m; coefficient = -p.ν * dt)
  to_velocity_vorticity!(ws.uω, ws.ω, ws.ustar, ws, m, plans)           # û*'s velocity & vorticity (scratch)
  rhs!(ws.k2, ws.uω, ws.ω, ws, m, plans, dealias)                       # k₂ = N̂(û*)
  exponential_convolve!(ws.k1, ws.k1, m; coefficient = -p.ν * dt)                     # ℰ·k₁, the same lazy factor
  exponential_convolve!(uh, uh, m; coefficient = -p.ν * dt)                           # ℰ·ûₙ
  field_data(uh) .+= (FT(dt) / 2) .* (field_data(ws.k1) .+ field_data(ws.k2))   # ûₙ₊₁
  force!(uh, band, ws, p, m)
  return uh
end


## =============================================================================
# Particles — RK2 in space on the frozen start-of-step velocity field (the
# ``O(\Delta t^{2})`` field-staleness is fine for a demo), via the package's
# `interpolate` (gather). All device arrays; positions wrap into ``[0, L)``.
## =============================================================================

function advect!(X, u, dt, p)
  v1 = point_values(interpolate(u, PointSet(X), CatmullRom))          # CatmullRom gather (package, device kernel)
  Xmid = mod.(X .+ FT(dt) .* v1, FT(p.L))
  v2 = point_values(interpolate(u, PointSet(Xmid), CatmullRom))
  X .= mod.(X .+ (FT(dt) / 2) .* (v1 .+ v2), FT(p.L))
  return v1
end


## =============================================================================
# Initial condition — random field (built on the host, moved to the device),
# large-scale envelope, projected solenoidal, band-energy normalized.
## =============================================================================

function random_solenoidal(grid, m, plans, ws, band, p; kp = 2.0)
  rng = MersenneTwister(p.seed)
  uh = to_spectral(VectorFieldPhysical(dev(randn(rng, FT, p.N, p.N, p.N, 3)), grid), plans)
  envelope = radial_kernel(k2 -> k2 > 0 ? exp(-k2 / FT(kp)^2) : zero(k2), m)  # large scales; none at κ = 0 (no mean flow)
  convolve!(uh, uh, envelope)                                        # apply it (alias-safe, coefficientwise)
  helmholtz_projection!(uh, uh, m)                                   # make solenoidal (alias-safe, one pass)
  force!(uh, band, ws, p, m)                                         # set the forced-band energy
  return uh
end


## =============================================================================
# Structure functions, autocorrelations and integral scales — the per-component
# ``S_2``'s, the Lagrangian velocity autocorrelation, and the integral-scale
# reduction all live in `examples/hist_postprocess.jl` (shared with the CPU twin).
# The Eulerian ``S_2`` needs no spatial shift at all: it reads off the FFT-based
# `radial_correlation`, so only the scalar reductions land on the host. The
# Eulerian integral length comes from
# `radial_correlation` (below); the Lagrangian integral time from `lagrangian_stats`.
## =============================================================================


## =============================================================================
# Driver
## =============================================================================

function run_hist(p::Params; run_name = "HIST_CUDA_default")
  CUDA.functional() || error("no functional NVIDIA GPU / CUDA — this is the GPU example (see HIST_CPU.jl for CPU)")
  isdir(OUTDIR) || mkpath(OUTDIR)
  @printf("HIST_CUDA: N=%d  %s  ν=%.3g  forcing |k|≤%d @ E=%.2g  (%d spinup + %d stats steps)\n",
          p.N, FT, p.ν, p.k_force, p.E_force, p.n_spinup, p.n_stats)
  @printf("  device: %s\n", CUDA.name(CUDA.device()))

  # The setup builds the grid, transform plans, spectral multipliers, the de-alias filter and forcing band
  # (device kernels), and the preallocated workspace.
  grid   = Grid3D((p.N, p.N, p.N), (FT(p.L), FT(p.L), FT(p.L)))
  layout = RealFourierLayout()
  uphys0 = VectorFieldPhysical(dev(zeros(FT, p.N, p.N, p.N, 3)), grid)
  uspec0 = VectorFieldSpectral(dev(zeros(Complex{FT}, field_spectral_shape(grid, layout, Val(1)))), grid)
  # One plan pair serves every tensor order (a transform is a property of the box), so the scalar
  # divergence diagnostic below reuses these plans instead of planning a second pair.
  vplans = FieldTransformPlans(uphys0, uspec0)            # physical ↔ spectral, any rank (device plans)
  m    = FieldSpectralMultipliers(uspec0)                 # wavenumbers copied to the device backend
  # 2/3-rule de-alias filter and the forcing band, both as package shell-mask kernels (device).
  dealias = spectral_cutoff(m, (2 / 3) * (p.N / 2) * (2π / p.L))
  band    = spectral_band(m, FT(0.5 * (2π / p.L)), FT((p.k_force + 0.5) * (2π / p.L)))
  ws   = make_workspace(uphys0, uspec0)                   # preallocated device scratch (a step allocates nothing)
  Δx   = p.L / p.N

  # Build the initial condition, then de-alias it.
  uh = random_solenoidal(grid, m, vplans, ws, band, p)
  convolve!(uh, uh, dealias)

  # Spin up to stationarity (adaptive ``\Delta t``; these statistics are discarded). Each step fills the
  # cached start-of-step velocity/vorticity (`to_velocity_vorticity!`), records ``k(t)`` and
  # ``\varepsilon(t)``, then advances `uh`.
  t_hist = Float64[]; E_hist = Float64[]; ε_hist = Float64[]
  t = 0.0
  sim_start = time()                                           # wall-clock of the simulation (the time loops)
  for n in 1:p.n_spinup
    to_velocity_vorticity!(ws.u, ws.ω0, uh, ws, m, vplans)       # start-of-step velocity & vorticity
    dt = p.cfl * Δx / max(max_speed(ws.u), 1e-6)
    push!(t_hist, t); push!(E_hist, kinetic_energy(ws.u)); push!(ε_hist, dissipation(ws.ω0, p))
    step!(uh, ws, m, vplans, dealias, band, p, dt)
    t += dt
  end

  # Freeze ``\Delta t`` for the statistics window so the Lagrangian ``\tau``-axis is uniform.
  to_velocity_vorticity!(ws.u, ws.ω0, uh, ws, m, vplans)
  dt = p.cfl * Δx / max(max_speed(ws.u), 1e-6)

  # In the statistics window (``\Delta t`` frozen so the Lagrangian ``\tau``-axis is uniform), advance the
  # field, advect the tracers on the start-of-step velocity, record their velocities, and accumulate
  # the autocorrelation.
  X = dev(FT.(p.L .* rand(MersenneTwister(p.seed + 1), p.n_particles, 3)))   # tracers on-device
  n_rec = p.n_stats ÷ p.rec_stride
  V = zeros(FT, p.n_particles, 3, n_rec)                          # recorded velocities (HOST)
  Cacc = Float64[]; sep = Float64[]; n_snap = 0   # time-averaged velocity autocorrelation C(r)
  rec = 0
  for n in 1:p.n_stats
    to_velocity_vorticity!(ws.u, ws.ω0, uh, ws, m, vplans)       # start-of-step velocity & vorticity
    push!(t_hist, t); push!(E_hist, kinetic_energy(ws.u)); push!(ε_hist, dissipation(ws.ω0, p))
    step!(uh, ws, m, vplans, dealias, band, p, dt)               # advances ûₙ (reuses ws.u, ws.ω0 for k₁)
    v = advect!(X, ws.u, dt, p)                                  # advect on the start-of-step velocity
    if n % p.rec_stride == 0 && rec < n_rec
      rec += 1
      V[:, :, rec] .= Array(v)                                    # copy this step's velocities to the host
    end
    if n % p.snap_stride == 0
      ## Eulerian statistics from the FFT velocity autocorrelation C(r) (package, device-
      ## clean — on-device binning, host result): the per-component S⁽ᴱ⁾(r) =
      ## (2/3)(C(0)−C(r)) and the integral length ℒ = ∫ρ follow from it — no hand-rolled
      ## spatial shift. Accumulate C over snapshots for a time average.
      s, Csnap = radial_correlation(uh, vplans)
      isempty(Cacc) ? (sep = s; Cacc = copy(Csnap)) : (Cacc .+= Csnap)
      n_snap += 1
    end
    t += dt
  end
  if n_snap == 0                                  # ensure ≥1 sample (if snap_stride > n_stats)
    sep, Cacc = radial_correlation(uh, vplans); n_snap = 1
  end
  C = Cacc ./ n_snap                              # time-averaged autocorrelation
  sim_seconds = time() - sim_start                # full simulation wall-clock (spin-up + statistics)

  # The final diagnostics are the energetics, the Kolmogorov/Taylor scales, the divergence check, the spectrum.
  u  = to_physical(uh, vplans)
  K  = kinetic_energy(u)
  ε  = dissipation(to_physical(curl(uh, m), vplans), p)
  uprime = sqrt(2K / 3)
  Reλ = sqrt(15 * uprime^4 / (p.ν * ε))
  η   = (p.ν^3 / ε)^(1 / 4)                 # Kolmogorov length
  τ_η = sqrt(p.ν / ε)                        # Kolmogorov time
  λ   = uprime * sqrt(15 * p.ν / ε)          # Taylor microscale (length), λ = u'√(15ν/ε)
  kmaxη = (2 / 3) * (p.N / 2) * (2π / p.L) * η        # the 2π/L makes the wavenumber physical
  # The divergence check, at `Float32` round-off, is ``\lVert\nabla\cdot u\rVert / (\kappa_{\mathrm{rms}} \lVert u\rVert)`` with the energy-weighted rms wavenumber, via `l2norm`.
  divp = to_physical(divergence(uh, m), vplans)
  κ_rms = sqrt(weighted_inner(uh, radial_kernel(identity, m)) / max(inner(uh, uh), 1e-300))
  divrel = l2norm(divp) / (κ_rms * l2norm(u) + 1e-30)
  ek_k, ek_E = energy_spectrum(uh, m)

  # The length and time scales come from the velocity autocorrelations.
  # On the Eulerian side the time-averaged ``C(r) = \langle u(x)\cdot u(x+r)\rangle`` (with
  # ``C(0) = \langle\lvert u\rvert^{2}\rangle``) gives the integral length, over separations of its normalized form, ``\mathcal{L} = \int_0^\infty \rho(r)\,\mathrm{d}r``
  # and the per-component structure function ``S^{(E)}(r) = \tfrac{2}{3} (C(0) - C(r))``. On the Lagrangian side
  # the particle-velocity autocorrelation ``R(\tau)`` (from the recorded `V`) gives the integral time over
  # time lags of its normalized form, ``\tau_u = \int_0^\infty \rho_L(\tau)\,\mathrm{d}\tau``.
  rho_E = C ./ C[1]
  L_int = integral_scale(sep, C)
  S2_E  = (2 / 3) .* (C[1] .- C)             # Eulerian per-component structure function (homogeneous identity)
  τ_l, R_l, S2l = lagrangian_stats(V, p.rec_stride * dt)
  rho_L  = R_l ./ R_l[1]
  τ_u    = integral_scale(τ_l, R_l)

  @printf("  K=%.4g  ε=%.4g  u'=%.4g  Re_λ=%.1f  η=%.3g  k_max·η=%.2f  ‖∇·u‖_rel=%.1e\n",
          K, ε, uprime, Reλ, η, kmaxη, divrel)
  @printf("  simulation: %.1f s wall-clock for %d steps at %d³ %s  (%.1f ms/step)\n",
          sim_seconds, p.n_spinup + p.n_stats, p.N, FT, 1e3 * sim_seconds / (p.n_spinup + p.n_stats))
  @printf("  scales: λ/η=%.2f  L/η=%.2f  |  τ_u/τ_η=%.2f  √(τ_η·τ_u)/τ_η=%.2f\n",
          λ / η, L_int / η, τ_u / τ_η, sqrt(τ_η * τ_u) / τ_η)
  # By Parseval, the package's spectral `inner` (rfft half-spectrum weighting) reproduces the physical
  # ``\tfrac{1}{2}\langle\lvert u\rvert^{2}\rangle`` exactly — same energy, computed in spectral
  # representation, on-device.
  @printf("  ½⟨|u|²⟩: physical=%.6g  spectral inner(û,û)=%.6g  |  Σ E(k)=%.4g  (Parseval)\n",
          K, 0.5 * inner(uh, uh), sum(ek_E))

  # Dump every plotted curve to HDF5, then plot (re-plot later via `plot_hist.jl`, no re-run).
  bundle = Dict{String, Any}(
    "backend" => "CUDA", "eltype" => string(FT),
    "N" => p.N, "L_box" => p.L, "nu" => p.ν, "dt" => dt, "n_spinup" => p.n_spinup,
    "K" => K, "epsilon" => ε, "uprime" => uprime, "Re_lambda" => Reλ,
    "eta" => η, "tau_eta" => τ_η, "lambda" => λ, "L_int" => L_int, "tau_u" => τ_u,
    "kmax_eta" => kmaxη, "div_rel" => divrel, "C2" => 2.1, "C0" => 6.0, "CK" => 1.6, "sim_seconds" => sim_seconds,
    "t" => t_hist, "E" => E_hist, "eps_t" => ε_hist,
    "ek_k" => collect(ek_k), "ek_E" => collect(ek_E),
    "r" => sep[2:end], "S2_E" => S2_E[2:end],          # structure-function panel (excludes r = 0)
    "tau" => τ_l, "S2_L" => S2l, "rho_L" => rho_L,
    "sep" => collect(sep), "rho_E" => rho_E,           # autocorrelation panel (includes r = 0)
  )
  save_hist(joinpath(OUTDIR, run_name * ".h5"), bundle)
  ## checked after the dump, so a failed check keeps the run's data for inspection
  @assert isfinite(K) && isfinite(ε) && divrel < 1e-4 "non-finite or non-solenoidal state"
  make_hist_plots(bundle; outdir = OUTDIR, prefix = run_name)
  return nothing
end


## =============================================================================
# Entry point
## =============================================================================

# The preset's name also names the output, so each configuration keeps its own dump.
const PRESETS = ("smoke" => smoke, "fast" => fast, "huge" => huge, "giant" => giant, "mega" => mega)

function main()
  chosen = findfirst(preset -> "--" * first(preset) in ARGS, PRESETS)
  name, configuration = chosen === nothing ? ("default", Params) : PRESETS[chosen]
  run_hist(configuration(); run_name = "HIST_CUDA_" * name)
end

main()
