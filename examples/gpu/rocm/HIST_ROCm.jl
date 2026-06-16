# =============================================================================
# HIST_ROCm.jl — forced Homogeneous Isotropic Stationary Turbulence, on an AMD GPU.
#
# The device twin of examples/HIST_CPU.jl: the SAME pseudospectral DNS and the same
# plots, but every array lives in GPU memory (`ROCArray`) and scalar indexing of
# device arrays is DISABLED (`AMDGPU.allowscalar(false)`) — so any stray scalar
# index inside a package method throws, turning invariant 6 (no scalar indexing of
# GPU arrays) into a checked guarantee. Default element type is Float32, the
# realistic consumer-GPU precision.
#
# Read HIST_CPU.jl first; this file flags only what CHANGES for the GPU:
#   • All field storage is built from device arrays (`dev(...)`); the FFT plans,
#     multipliers and the shell-mask kernels land on-device automatically.
#   • The package operations are backend-agnostic and run unchanged: curl, cross,
#     helmholtz_projection, the transforms, the L²/measure reductions
#     (inner/l2norm/lpnorm, radial_spectrum, and radial_correlation), convolve with the
#     kernel/coordinate builders (spectral_cutoff / spectral_band / squared_wavenumber_field),
#     and interpolate.
#   • There is now NOTHING device-special left to hand-roll. The forcing band is a
#     `spectral_band` kernel (energy via `inner(convolve(û,band),û)`, rescale via
#     `convolve`) and the energy spectrum is `radial_spectrum` (on-device shell binning,
#     no host copy) — the same source as HIST_CPU.jl, run on device arrays. The only
#     remaining non-package bits (examples/README.md gap list) are the random-solenoidal
#     IC generator and the Eulerian-S₂ field-shift, both representation-neutral.
#
# Like HIST_CPU.jl, the run is split SIMULATE → DUMP → PLOT: every plotted curve is written
# to output/HIST_ROCm.h5 and the figures (the thesis Fig. A.1 structure-function layout, the
# spectrum, the stationarity history and the velocity autocorrelations) are rendered by the
# shared examples/hist_postprocess.jl; re-plot without re-running via
#   julia --project=examples examples/plot_hist.jl examples/gpu/rocm/output/HIST_ROCm.h5
#
#   julia --project=examples/gpu/rocm examples/gpu/rocm/HIST_ROCm.jl            # full run (default 32³)
#   julia --project=examples/gpu/rocm examples/gpu/rocm/HIST_ROCm.jl --fast     # 64³, for nicer statistics
#   julia --project=examples/gpu/rocm examples/gpu/rocm/HIST_ROCm.jl --smoke    # quick check
# =============================================================================

using AMDGPU
AMDGPU.allowscalar(false)                  # invariant 6, mechanically enforced

using GBGPeriodicFields
using GBGPeriodicFields: field_data, field_grid          # raw-array / grid accessors
using Random, Statistics, Printf, LinearAlgebra

const OUTDIR = joinpath(@__DIR__, "output")
const FT = Float32                         # element type (Float32 = realistic GPU precision)
dev(host_array) = ROCArray(host_array)     # move a host array onto the device
include(joinpath(@__DIR__, "..", "..", "hist_postprocess.jl"))   # statistics, HDF5 I/O, plots (shared)


# =============================================================================
# Parameters
# =============================================================================

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
  seed::Int       = 1234
end

# A tiny configuration for a quick end-to-end check (`--smoke`).
smoke() = Params(n_spinup = 15, n_stats = 40, n_particles = 300, rec_stride = 1, snap_stride = 10)

# A larger, still-quick configuration for nicer statistics (`--fast`) — 64³, more tracers.
fast() = Params(N = 64, n_spinup = 400, n_stats = 800, n_particles = 4000, rec_stride = 2, snap_stride = 40)

# A high-Reynolds configuration (`--huge`) — 192³ at a lower viscosity. The Reynolds number (Re_λ ≈ 93) is
# set by ν, not the grid, so this already gives the scale separation λ ≪ L, τ_η ≪ τ_u; the grid only has to
# RESOLVE it (k_max·η ≈ 1.13 here). 192³ is a comfortable fit on a 12 GB card. The CFL is conservative (0.3)
# and ν carries a resolution margin **because the statistics-window Δt is frozen** (for a uniform Lagrangian
# axis): over a long averaging window a CFL-tight, marginally-resolved run eventually hits a velocity peak
# that the frozen Δt cannot handle and blows up — the conservative CFL is what keeps the long run stable.
# n_spinup clears the initial energy overshoot; n_stats time-averages over a few of the forcing's
# energy-oscillation periods (see the `mega` note below). A few minutes on the GPU.
huge() = Params(N = 192, ν = 3.2e-3, cfl = 0.3, n_spinup = 3300, n_stats = 4700, n_particles = 8000,
                rec_stride = 4, snap_stride = 60)

# Push the grid to 256³ (`--mega`) at a lower viscosity than `--huge` (measured Re_λ ≈ 109, k_max·η ≈ 1.34
# — still comfortably resolved; ≈ 87 ms/step on an RX 6700 XT). This fits a 12 GB card only because *both*
# the time loop and the diagnostics are allocation-bounded: the hot loop is allocation-free (decision 24),
# and the radial-correlation/spectrum binning is a single scatter-add pass rather than a per-shell masked
# reduction (decision 25) — the latter materialized ~N full-grid temporaries per snapshot that the GPU GC
# could not reclaim, and used to wedge the card at the first snapshot. Footprint is now ~flat at the
# preallocated working set (~6 GB, ≈ 8 GB peak through the snapshots). The viscosity carries a resolution
# margin and the CFL is conservative (0.4) because the statistics-window Δt is frozen (for a uniform
# Lagrangian axis): a marginally-resolved, CFL-tight high-Re run can blow up on an intermittent velocity
# burst (the more aggressive ν = 2e-3 did exactly that, in particle advection).
#
# Stationarity: the band-rescaling forcing, started from a low-energy smooth initial condition, injects
# energy faster than it dissipates, so E(t) overshoots its mean near t ≈ 7 turnovers and then *oscillates*
# about it with a slowly-damped ≈ 7-turnover period (the forcing–dissipation lag) — it does not settle to a
# flat plateau. n_spinup clears the large initial overshoot (measured in turnover times — at 256³ the finer
# grid forces a smaller Δt, hence more steps than the coarser grids for the same physical time); the n_stats
# window then captures the developed flow (a small ~5% residual oscillation about the mean). For a *longer*
# averaging window, also lower the CFL as `huge` does — the frozen Δt is CFL-fragile over long runs, where
# an energy-oscillation peak can eventually blow it up.
mega() = Params(N = 256, ν = 2.5e-3, cfl = 0.4, n_spinup = 3800, n_stats = 1200, n_particles = 8000,
                rec_stride = 4, snap_stride = 100)


# =============================================================================
# Spectral utilities (device). The diagonal-in-Fourier operators — de-aliasing,
# the integrating factor exp(−νk²Δt), the IC envelope — are applied with the
# package's `convolve` (a coefficientwise multiply by a transfer function ĝ); the
# de-alias filter is `spectral_cutoff`, the physics kernels are consumer-built
# `ScalarFieldSpectral`s (invariant 12). All of these operate on whatever backend
# the reference field lives on, so on the GPU they stay entirely on-device.
# =============================================================================

# Wrap a per-mode transfer function w(k) (a real device array) as a scalar field in
# spectral representation — the consumer's half of a convolution. The |k|² it needs
# is the package's `squared_wavenumber_field` (a device ScalarFieldSpectral), so the
# consumer never hand-rolls a wavenumber broadcast.
spectral_kernel(reference, w) = ScalarFieldSpectral(Complex{FT}.(w), field_grid(reference))


# Preallocated DEVICE scratch for the in-place hot loop, so a step allocates nothing — and therefore
# the AMDGPU memory pool never grows (no wedge, no manual GC/reclaim). An allocating loop would pile
# up device temporaries faster than Julia's host-triggered GC frees them; preallocation is the fix
# (see examples/README.md). This is how a real GPU DNS is written: performance first.
function make_workspace(grid, layout, p)
  spectral_vector() = VectorFieldSpectral(dev(zeros(Complex{FT}, spectral_field_shape(grid, layout, Val(1)))), grid)
  physical_vector() = VectorFieldPhysical(dev(zeros(FT, p.N, p.N, p.N, 3)), grid)
  return (ωh = spectral_vector(), k1 = spectral_vector(), k2 = spectral_vector(),
          ustar = spectral_vector(), uhc = spectral_vector(), tmp = spectral_vector(),
          Nt = spectral_vector(),                          # (u×ω)^ scratch (distinct helmholtz source)
          Ek = ScalarFieldSpectral(dev(zeros(Complex{FT}, spectral_field_shape(grid, layout, Val(0)))), grid),
          u = physical_vector(), ω0 = physical_vector(), ω = physical_vector(),
          uω = physical_vector(), uxω = physical_vector())
end


# =============================================================================
# Diagnostics — every one is a package reduction, running on-device unchanged
# (sum/dot/maximum are GPU-portable): kinetic energy ½⟨|u|²⟩, dissipation ν⟨|ω|²⟩,
# the CFL speed, and — now also on-device — the energy spectrum via radial_spectrum
# (the shell binning is masked reductions, no host copy, no scalar indexing).
# =============================================================================

kinetic_energy(u) = 0.5 * inner(u, u)                                 # ½⟨|u|²⟩   (Reductions.inner)
dissipation(ω, p) = p.ν * inner(ω, ω)                                 # ν⟨|ω|²⟩   (homogeneous)
# CFL speed: max |velocity component|, an allocation-free device reduction. (lpnorm(u, Inf) is the true
# sup|u| but materializes a magnitude field each call — avoided so the hot loop keeps the GPU pool flat.)
max_speed(u)      = maximum(abs, field_data(u))

# E(κ) = ½ × the shell-resolved Parseval inner; ∑ₖ E(κ) = ½⟨|u|²⟩ = kinetic energy.
# radial_spectrum bins on-device and returns small host vectors — no host copy of the field.
function energy_spectrum(uh, m)
  shells, spectrum = radial_spectrum(uh, m)                            # device binning (package)
  return shells, 0.5 .* spectrum
end


# =============================================================================
# Forcing — hold the kinetic energy in shells 1 ≤ |k| ≤ k_force at E_force, now pure
# package ops (identical to HIST_CPU.jl): `band` is a `spectral_band` mask kernel;
# the band energy is ½ inner(convolve(û, band), û) (Parseval); rescaling the in-band
# modes is one more `convolve`. No precomputed mask / weight, no sum-reduction by
# hand — all on-device (scaling preserves ∇·u = 0).
# =============================================================================

function force!(uh, band, ws, p)
  convolve!(ws.tmp, uh, band)                             # band-pass copy into scratch (no allocation)
  band_kinetic = FT(0.5) * inner(ws.tmp, uh)              # ½⟨|u_band|²⟩ via Parseval (package inner)
  band_kinetic < FT(1e-12) && return uh                   # guard (IC seeds the band)
  scale = sqrt(FT(p.E_force) / band_kinetic)
  convolve!(uh, uh, band, scale - 1, 1)                 # rescale in-band modes: one convolve (α/β, alloc-free)
  return uh
end


# =============================================================================
# Right-hand side and time integration — IN-PLACE, no per-step allocation (identical structure to
# HIST_CPU.jl). The work fields live in the preallocated device `ws`; the package's in-place operators
# (`curl!`, `to_physical!`, `cross!`, `to_spectral!`, `helmholtz_projection!`, `convolve!`) write into
# them on-device, and the linear combinations are in-place device broadcasts. Nothing allocates, so the
# AMDGPU pool stays flat — no wedge, no manual reclaim (that was the allocating style; see README).
# =============================================================================

# Physical velocity & vorticity of a spectral field, into the given buffers. `uh` is preserved by
# transforming a COPY of it — `to_physical!` consumes its spectral source (invariant 11).
function to_velocity_vorticity!(u_out, ω_out, uh, ws, m, plans)
  curl!(ws.ωh, uh, m)                          # ω̂ = ∇×û  (û preserved)
  to_physical!(ω_out, ws.ωh, plans)            # physical vorticity (consumes ω̂)
  copyto!(field_data(ws.uhc), field_data(uh))  # keep û: transform a scratch copy
  to_physical!(u_out, ws.uhc, plans)           # physical velocity (consumes the copy)
  return u_out, ω_out
end

# N̂ = de-aliased Leray projection of (u×ω)^, written into `Nh`, from physical u, ω.
function rhs!(Nh, u, ω, ws, m, plans, dealias)
  cross!(ws.uxω, u, ω)                          # u × ω  (physical)
  to_spectral!(ws.Nt, ws.uxω, plans)            # (u×ω)^ into scratch
  helmholtz_projection!(Nh, ws.Nt, m)           # Leray projection — DISTINCT dest ⇒ no-alias path (no allocation)
  convolve!(Nh, Nh, dealias)                    # 2/3 de-alias (coefficientwise multiply)
  return Nh
end

# One integrating-factor RK2 (Heun) step, fully in place. E = exp(−νk²Δt) (ν, Δt are physics —
# invariant 12) applied with `convolve!`. Assumes `ws.u`, `ws.ω0` hold the START-of-step physical
# velocity & vorticity (the loop fills them, and also uses them for the diagnostics), so k₁ reuses them.
#   k₁ = N̂(ûₙ);  û* = E·(ûₙ + Δt·k₁);  k₂ = N̂(û*);  ûₙ₊₁ = E·ûₙ + (Δt/2)(E·k₁ + k₂);  then force.
function step!(uh, ws, m, plans, dealias, band, ksq, p, dt)
  field_data(ws.Ek) .= Complex{FT}.(exp.(-FT(p.ν) .* ksq .* FT(dt)))    # E = exp(−νk²Δt) into scratch
  rhs!(ws.k1, ws.u, ws.ω0, ws, m, plans, dealias)                       # k₁ = N̂(ûₙ)  (cached start-of-step u, ω)
  field_data(ws.ustar) .= field_data(uh) .+ FT(dt) .* field_data(ws.k1)
  convolve!(ws.ustar, ws.ustar, ws.Ek)                                  # û* = E·(ûₙ + Δt·k₁)
  to_velocity_vorticity!(ws.uω, ws.ω, ws.ustar, ws, m, plans)           # û*'s velocity & vorticity (scratch)
  rhs!(ws.k2, ws.uω, ws.ω, ws, m, plans, dealias)                       # k₂ = N̂(û*)
  convolve!(ws.k1, ws.k1, ws.Ek)                                        # E·k₁
  convolve!(uh, uh, ws.Ek)                                              # E·ûₙ
  field_data(uh) .+= (FT(dt) / 2) .* (field_data(ws.k1) .+ field_data(ws.k2))   # ûₙ₊₁
  force!(uh, band, ws, p)
  return uh
end


# =============================================================================
# Particles — RK2 in space on the frozen start-of-step velocity field via the
# package's interpolate (gather). All device arrays; positions wrap into [0, L).
# =============================================================================

function advect!(X, u, dt, p)
  v1 = point_values(interpolate(u, PointSet(X)))          # CatmullRom gather (package, device kernel)
  Xmid = mod.(X .+ FT(dt) .* v1, FT(p.L))
  v2 = point_values(interpolate(u, PointSet(Xmid)))
  X .= mod.(X .+ (FT(dt) / 2) .* (v1 .+ v2), FT(p.L))
  return v1
end


# =============================================================================
# Initial condition — random field (built on the host, moved to the device),
# large-scale envelope, projected solenoidal, band-energy normalized.
# =============================================================================

function random_solenoidal(grid, m, plans, ws, ksq, band, p; kp = 2.0)
  rng = MersenneTwister(p.seed)
  uh = to_spectral(VectorFieldPhysical(dev(randn(rng, FT, p.N, p.N, p.N, 3)), grid), plans)
  envelope = spectral_kernel(uh, exp.(-(ksq ./ FT(kp)^2)))           # concentrate at large scales
  convolve!(uh, uh, envelope)                                        # apply it (alias-safe, coefficientwise)
  helmholtz_projection!(uh, uh, m)                                   # make solenoidal (alias-guarded)
  force!(uh, band, ws, p)                                            # set the forced-band energy
  return uh
end


# =============================================================================
# Structure functions, autocorrelations and integral scales — the trace S₂'s, the
# Lagrangian velocity autocorrelation, and the integral-scale reduction all live in
# examples/hist_postprocess.jl (shared with the CPU twin; eulerian_trace_s2! keeps the
# whole-field circshift on-device, only the scalar reductions land on the host). The
# Eulerian integral length comes from radial_correlation (below); the Lagrangian
# integral time from lagrangian_stats.
# =============================================================================


# =============================================================================
# Driver
# =============================================================================

function run_hist(p::Params)
  AMDGPU.functional() || error("no functional AMD GPU / ROCm — this is the GPU example (see HIST_CPU.jl for CPU)")
  isdir(OUTDIR) || mkpath(OUTDIR)
  @printf("HIST_ROCm: N=%d  %s  ν=%.3g  forcing |k|≤%d @ E=%.2g  (%d spinup + %d stats steps)\n",
          p.N, FT, p.ν, p.k_force, p.E_force, p.n_spinup, p.n_stats)
  @printf("  device: %s\n", AMDGPU.device())

  # --- setup: grid, plans, multipliers, device kernels ----------------------
  grid   = Grid3D((p.N, p.N, p.N), (FT(p.L), FT(p.L), FT(p.L)))
  layout = RealFourierLayout()
  uphys0 = VectorFieldPhysical(dev(zeros(FT, p.N, p.N, p.N, 3)), grid)
  uspec0 = VectorFieldSpectral(dev(zeros(Complex{FT}, spectral_field_shape(grid, layout, Val(1)))), grid)
  vplans = FieldTransformPlans(uphys0, uspec0)            # vector physical ↔ spectral (device FFT plans)
  splans = FieldTransformPlans(ScalarFieldPhysical(dev(zeros(FT, p.N, p.N, p.N)), grid),
                               ScalarFieldSpectral(dev(zeros(Complex{FT}, spectral_field_shape(grid, layout, Val(0)))), grid))
  m    = FieldSpectralMultipliers(uspec0)                 # wavenumbers copied to the device backend
  ksq  = real.(field_data(squared_wavenumber_field(uspec0, m)))   # |k|² (package), device array
  # 2/3-rule de-alias filter and the forcing band, both as package shell-mask kernels (device).
  dealias = spectral_cutoff(uspec0, m, (2 / 3) * (p.N / 2) * (2π / p.L))
  band    = spectral_band(uspec0, m, FT(0.5 * (2π / p.L)), FT((p.k_force + 0.5) * (2π / p.L)))
  ws   = make_workspace(grid, layout, p)                  # preallocated device scratch (a step allocates nothing)
  Δx   = p.L / p.N

  # --- initial condition ----------------------------------------------------
  uh = random_solenoidal(grid, m, vplans, ws, ksq, band, p)
  convolve!(uh, uh, dealias)

  # --- spin-up to stationarity (adaptive Δt) --------------------------------
  t_hist = Float64[]; E_hist = Float64[]; ε_hist = Float64[]
  t = 0.0
  sim_start = time()                                           # wall-clock of the simulation (the time loops)
  for n in 1:p.n_spinup
    to_velocity_vorticity!(ws.u, ws.ω0, uh, ws, m, vplans)       # start-of-step velocity & vorticity
    dt = p.cfl * Δx / max(max_speed(ws.u), 1e-6)
    push!(t_hist, t); push!(E_hist, kinetic_energy(ws.u)); push!(ε_hist, dissipation(ws.ω0, p))
    step!(uh, ws, m, vplans, dealias, band, ksq, p, dt)
    t += dt
  end

  # Freeze Δt for the statistics window so the Lagrangian τ-axis is uniform.
  to_velocity_vorticity!(ws.u, ws.ω0, uh, ws, m, vplans)
  dt = p.cfl * Δx / max(max_speed(ws.u), 1e-6)

  # --- statistics window: advance, advect particles, accumulate stats -------
  X = dev(FT.(p.L .* rand(MersenneTwister(p.seed + 1), p.n_particles, 3)))   # tracers on-device
  n_rec = p.n_stats ÷ p.rec_stride
  V = zeros(FT, p.n_particles, 3, n_rec)                          # recorded velocities (HOST)
  Cacc = Float64[]; sep = Float64[]; n_snap = 0   # time-averaged velocity autocorrelation C(r)
  rec = 0
  for n in 1:p.n_stats
    to_velocity_vorticity!(ws.u, ws.ω0, uh, ws, m, vplans)       # start-of-step velocity & vorticity
    push!(t_hist, t); push!(E_hist, kinetic_energy(ws.u)); push!(ε_hist, dissipation(ws.ω0, p))
    step!(uh, ws, m, vplans, dealias, band, ksq, p, dt)          # advances ûₙ (reuses ws.u, ws.ω0 for k₁)
    v = advect!(X, ws.u, dt, p)                                  # advect on the start-of-step velocity
    if n % p.rec_stride == 0 && rec < n_rec
      rec += 1
      V[:, :, rec] .= Array(v)                                    # copy this step's velocities to the host
    end
    if n % p.snap_stride == 0
      # Eulerian statistics from the FFT velocity autocorrelation (package, device-clean — on-device
      # binning, host result): S⁽ᴱ⁾(r) = (2/3)(C(0) − C(r)) and L = ∫ρ. Accumulate for a time average.
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

  # --- final diagnostics ----------------------------------------------------
  u  = to_physical(uh, vplans)
  K  = kinetic_energy(u)
  ε  = dissipation(to_physical(curl(uh, m), vplans), p)
  uprime = sqrt(2K / 3)
  Reλ = sqrt(15 * uprime^4 / (p.ν * ε))
  η   = (p.ν^3 / ε)^(1 / 4)                 # Kolmogorov length
  τ_η = sqrt(p.ν / ε)                        # Kolmogorov time
  λ   = uprime * sqrt(15 * p.ν / ε)          # Taylor microscale (length), λ = u'√(15ν/ε)
  kmaxη = (2 / 3) * (p.N / 2) * η
  # divergence check (should be ~Float32 roundoff): ‖∇·u‖ / (k_rms ‖u‖), via the package l2norm.
  divp = to_physical(divergence(uh, m), splans)
  divrel = l2norm(divp) / (sqrt(mean(ksq)) * l2norm(u) + 1e-30)
  ek_k, ek_E = energy_spectrum(uh, m)

  # --- length / time scales from the velocity autocorrelations --------------
  # Eulerian: the time-averaged C(r) (= ⟨u(x)·u(x+r)⟩, C(0) = ⟨|u|²⟩) gives the integral length
  # L = ∫₀ ρ(r) dr and the trace structure function S⁽ᴱ⁾(r) = (2/3)(C(0) − C(r)). Lagrangian: the
  # particle-velocity autocorrelation R(τ) (from the recorded V), integral time τ_u = ∫₀ ρ_L(τ) dτ.
  rho_E = C ./ C[1]
  L_int = integral_scale(sep, C)
  S2_E  = (2 / 3) .* (C[1] .- C)             # Eulerian trace structure function (homogeneous identity)
  τ_l, R_l, S2l = lagrangian_stats(V, p.rec_stride * dt)
  rho_L  = R_l ./ R_l[1]
  τ_u    = integral_scale(τ_l, R_l)

  @printf("  K=%.4g  ε=%.4g  u'=%.4g  Re_λ=%.1f  η=%.3g  k_max·η=%.2f  ‖∇·u‖_rel=%.1e\n",
          K, ε, uprime, Reλ, η, kmaxη, divrel)
  @printf("  simulation: %.1f s wall-clock for %d steps at %d³ %s  (%.1f ms/step)\n",
          sim_seconds, p.n_spinup + p.n_stats, p.N, FT, 1e3 * sim_seconds / (p.n_spinup + p.n_stats))
  @printf("  scales: λ/η=%.2f  L/η=%.2f  |  τ_u/τ_η=%.2f  √(τ_η·τ_u)/τ_η=%.2f\n",
          λ / η, L_int / η, τ_u / τ_η, sqrt(τ_η * τ_u) / τ_η)
  # Parseval: the package's spectral `inner` (rfft half-spectrum weighting) reproduces
  # the physical ½⟨|u|²⟩ — same energy, computed in spectral representation, on-device.
  @printf("  ½⟨|u|²⟩: physical=%.6g  spectral inner(û,û)=%.6g  |  Σ E(k)=%.4g  (Parseval)\n",
          K, 0.5 * inner(uh, uh), sum(ek_E))
  @assert isfinite(K) && isfinite(ε) && divrel < 1e-4 "non-finite or non-solenoidal state"

  # --- dump every plotted curve to HDF5, then plot (re-plot via plot_hist.jl) -
  bundle = Dict{String, Any}(
    "backend" => "ROCm", "eltype" => string(FT),
    "N" => p.N, "L_box" => p.L, "nu" => p.ν, "dt" => dt, "n_spinup" => p.n_spinup,
    "K" => K, "epsilon" => ε, "uprime" => uprime, "Re_lambda" => Reλ,
    "eta" => η, "tau_eta" => τ_η, "lambda" => λ, "L_int" => L_int, "tau_u" => τ_u,
    "kmax_eta" => kmaxη, "div_rel" => divrel, "C2" => 2.1, "C0" => 6.0, "sim_seconds" => sim_seconds,
    "t" => t_hist, "E" => E_hist, "eps_t" => ε_hist,
    "ek_k" => collect(ek_k), "ek_E" => collect(ek_E),
    "r" => sep[2:end], "S2_E" => S2_E[2:end],          # structure-function panel (excludes r = 0)
    "tau" => τ_l, "S2_L" => S2l, "rho_L" => rho_L,
    "sep" => collect(sep), "rho_E" => rho_E,           # autocorrelation panel (includes r = 0)
  )
  save_hist(joinpath(OUTDIR, "HIST_ROCm.h5"), bundle)
  make_hist_plots(bundle; outdir = OUTDIR, prefix = "HIST_ROCm")
  return nothing
end


# =============================================================================
# Entry point
# =============================================================================

function main()
  p = ("--smoke" in ARGS) ? smoke() :
      ("--fast"  in ARGS) ? fast()  :
      ("--huge"  in ARGS) ? huge()  :
      ("--mega"  in ARGS) ? mega()  : Params()
  run_hist(p)
end

main()
