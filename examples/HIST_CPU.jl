# =============================================================================
# HIST_CPU.jl — forced Homogeneous Isotropic Stationary Turbulence, on the CPU.
#
# A *small, demonstration* pseudospectral DNS that drives GBGPeriodicFields as a
# consumer would, then plots the Eulerian and Lagrangian second-order velocity
# structure functions, each NORMALIZED BY ITS KOLMOGOROV SCALING (so a K41 inertial
# range shows as a plateau at 1 — the layout of Fig. A.1 in the thesis this demo
# accompanies), alongside the energy spectrum, the stationarity history, and the
# velocity autocorrelations. It is deliberately small (default 32³ / `--fast` 64³) —
# the goal is a readable, end-to-end workflow, NOT a production DNS. At these
# resolutions there is almost no inertial range, so the normalized curves do not
# reach a clean plateau and the K41 references are *references*, not fits; raise `N`
# (and lengthen the run) for nicer curves.
#
# Method (standard Orszag–Patterson rotational form):
#   ∂û/∂t = P[(u×ω)^] − ν k² û + f̂,     ω = ∇×u,   P = Leray (Helmholtz) projection.
# Time integration is integrating-factor RK2 (viscosity exact via exp(−νk²Δt),
# nonlinear term explicit), 2/3-rule de-aliasing, and a deterministic large-scale
# forcing that holds the energy in the lowest shells fixed (⇒ statistical
# stationarity, no tuning).
#
# What the PACKAGE provides here: Grid3D, the field types, FFT plans/transforms,
# FieldSpectralMultipliers, curl, cross, helmholtz_projection, divergence; the
# L²/measure reductions inner / l2norm / lpnorm (energy, dissipation, the CFL speed,
# the divergence check), radial_spectrum (the radial energy spectrum E(k)) and
# radial_correlation (the velocity autocorrelation, whose integral is the integral
# length L); convolve with the kernel/coordinate builders spectral_cutoff (de-alias),
# spectral_band (the forcing band) and squared_wavenumber_field (|k|², for the
# integrating-factor / IC-envelope symbols); and interpolate (grid→point). What this
# script must still HAND-ROLL — every one a candidate for promotion into the package —
# is collected in examples/README.md (the "gap list"): the random-solenoidal IC
# generator, and the Eulerian-S₂ field-shift (circshift). Those touch `field_data(...)`;
# the forcing and the spectrum are now pure package ops (see HIST_ROCm.jl, fully on-device).
#
# The analysis, the HDF5 data dump and the plotting live in examples/hist_postprocess.jl
# (shared with the GPU twin). The run is split SIMULATE → DUMP → PLOT: every plotted
# curve is written to output/HIST_CPU.h5, so the figures can be regenerated WITHOUT
# re-running the DNS via   julia --project=examples examples/plot_hist.jl output/HIST_CPU.h5
#
#   julia --project=examples examples/HIST_CPU.jl            # full run (default 32³, ~1 min)
#   julia --project=examples examples/HIST_CPU.jl --fast     # 64³, for nicer statistics
#   julia --project=examples examples/HIST_CPU.jl --smoke    # tiny, for a quick check
# =============================================================================

using GBGPeriodicFields
using GBGPeriodicFields: field_data, field_grid          # raw-array / grid accessors
using Random, Statistics, Printf, LinearAlgebra

const OUTDIR = joinpath(@__DIR__, "output")
include(joinpath(@__DIR__, "hist_postprocess.jl"))       # statistics, HDF5 I/O, plots (shared)


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

# A high-Reynolds configuration (`--huge`) — 192³ at a lower viscosity, so the Reynolds number
# (Re_λ ≈ 98) and the scale separation λ ≪ L, τ_η ≪ τ_u are large enough to read off the plots; the grid
# resolves it (k_max·η ≈ 1.1). At fixed forcing Re_λ is set by ν, not the grid, so 192³ already gives the
# separation; it is also a comfortable fit on a 12 GB GPU. Heavy: minutes on a GPU, much longer on the CPU.
huge() = Params(N = 192, ν = 3.0e-3, n_spinup = 800, n_stats = 1200, n_particles = 8000,
                rec_stride = 4, snap_stride = 60)


# =============================================================================
# Spectral utilities. The DIAGONAL (in Fourier) operators here — de-aliasing, the
# integrating factor exp(−νk²Δt), the IC envelope — are applied with the package's
# `convolve` (periodic convolution = a coefficientwise multiply by a transfer
# function ĝ). The de-alias filter is the package's `spectral_cutoff` builder; the
# physics kernels (which carry ν, Δt, the envelope width) are consumer-built
# `ScalarFieldSpectral`s and applied with the same `convolve` (invariant 12). The
# radial coordinate they need — |k|² — is the package's `squared_wavenumber_field`
# (no hand-rolled wavenumber broadcast); the consumer just broadcasts exp(...) over it.
# =============================================================================

# Wrap a per-mode transfer function w(k) (a real (Nkx, Ny, Nz) array) as a scalar
# field in spectral representation — the consumer's half of a convolution; the
# package applies it via `convolve`. The integrating factor and the IC envelope are
# built this way (their ν / Δt / width are the consumer's, per invariant 12).
spectral_kernel(reference, w) = ScalarFieldSpectral(ComplexF64.(w), field_grid(reference))


# Preallocated scratch fields for the in-place hot loop, so a step allocates nothing (this is how a
# real DNS is written — performance first). Holds the integrating factor `Ek`, the RK stages and the
# velocity/vorticity work fields; the loop and `step!` write into these instead of allocating.
function make_workspace(grid, layout, p)
  spectral_vector() = VectorFieldSpectral(zeros(ComplexF64, spectral_field_shape(grid, layout, Val(1))), grid)
  physical_vector() = VectorFieldPhysical(zeros(p.N, p.N, p.N, 3), grid)
  return (ωh = spectral_vector(), k1 = spectral_vector(), k2 = spectral_vector(),
          ustar = spectral_vector(), uhc = spectral_vector(), tmp = spectral_vector(),
          Nt = spectral_vector(),                          # (u×ω)^ scratch (distinct helmholtz source)
          Ek = ScalarFieldSpectral(zeros(ComplexF64, spectral_field_shape(grid, layout, Val(0))), grid),
          u = physical_vector(), ω0 = physical_vector(), ω = physical_vector(),
          uω = physical_vector(), uxω = physical_vector())
end


# =============================================================================
# Diagnostics — kinetic energy, dissipation, the CFL speed and the energy spectrum
# are all package reductions now (Reductions module): `inner(f,g) = ⟨f·g⟩`,
# `lpnorm(u, Inf) = sup|u|`, and `radial_spectrum(û, m)` = the shell-resolved inner
# (the radial power spectrum, `Σ spectrum = inner` ⇒ Σ E = ½⟨|u|²⟩). No field_data
# loops; the energy spectrum is one call.
# =============================================================================

kinetic_energy(u) = 0.5 * inner(u, u)                                  # ½⟨|u|²⟩   (Reductions.inner)
dissipation(ω, p) = p.ν * inner(ω, ω)                                  # ν⟨|ω|²⟩   (homogeneous)
# CFL speed: max |velocity component|, an allocation-free reduction over the raw array. (lpnorm(u, Inf)
# is the true sup|u| but materializes a magnitude field every call — avoided so the hot loop allocates
# nothing; the max component differs from the magnitude by at most √3, well inside the CFL margin.)
max_speed(u)      = maximum(abs, field_data(u))

# E(κ) = ½ × the shell-resolved Parseval inner; ∑ₖ E(κ) = ½⟨|u|²⟩ = kinetic energy.
function energy_spectrum(uh, m)
  shells, spectrum = radial_spectrum(uh, m)                             # (|k| bins, Σ_{shell} |û|²)  (package)
  return shells, 0.5 .* spectrum                                       # E(κ): physics ½ stays consumer-side
end


# =============================================================================
# Forcing — hold the kinetic energy in shells 1 ≤ |k| ≤ k_force at E_force. Built
# entirely from package ops: `band` is a `spectral_band` mask kernel; the band
# energy is ½ inner(convolve(û, band), û) (Parseval); rescaling the in-band modes
# is one more `convolve` (scaling preserves ∇·u = 0). No scalar indexing.
# =============================================================================

function force!(uh, band, ws, p)
  convolve!(ws.tmp, uh, band)                           # band-pass copy into scratch (no allocation)
  band_kinetic = 0.5 * inner(ws.tmp, uh)                # ½⟨|u_band|²⟩ via Parseval (package inner)
  band_kinetic < 1e-12 && return uh                     # guard (IC seeds the band)
  scale = sqrt(p.E_force / band_kinetic)
  convolve!(uh, uh, band, scale - 1, 1)                 # rescale in-band modes: one convolve (α/β, alloc-free)
  return uh
end


# =============================================================================
# Right-hand side and time integration — IN-PLACE, no per-step allocation (this is how a
# DNS is really written). The work fields all live in the preallocated `ws`; the package's
# in-place operators write into them (`curl!`, `to_physical!`, `cross!`, `to_spectral!`,
# `helmholtz_projection!`, `convolve!`), and the linear combinations are in-place broadcasts
# on the raw arrays. Nothing here allocates, so there is no GC/`reclaim` pressure (see the
# README on why the allocating style needs manual GC on some GPUs — this avoids it).
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

# One integrating-factor RK2 (Heun) step, fully in place. The integrating factor E = exp(−νk²Δt)
# (ν, Δt are physics — invariant 12) is applied with `convolve!`. Assumes `ws.u`, `ws.ω0` already
# hold the START-of-step physical velocity & vorticity (the loop fills them, and also uses them for
# the diagnostics), so k₁ reuses them — no recomputation.
#   k₁ = N̂(ûₙ);  û* = E·(ûₙ + Δt·k₁);  k₂ = N̂(û*);  ûₙ₊₁ = E·ûₙ + (Δt/2)(E·k₁ + k₂);  then force.
function step!(uh, ws, m, plans, dealias, band, ksq, p, dt)
  field_data(ws.Ek) .= complex.(exp.(-p.ν .* ksq .* dt))         # E = exp(−νk²Δt) into scratch
  rhs!(ws.k1, ws.u, ws.ω0, ws, m, plans, dealias)                # k₁ = N̂(ûₙ)  (cached start-of-step u, ω)
  field_data(ws.ustar) .= field_data(uh) .+ dt .* field_data(ws.k1)
  convolve!(ws.ustar, ws.ustar, ws.Ek)                           # û* = E·(ûₙ + Δt·k₁)
  to_velocity_vorticity!(ws.uω, ws.ω, ws.ustar, ws, m, plans)    # û*'s velocity & vorticity (scratch)
  rhs!(ws.k2, ws.uω, ws.ω, ws, m, plans, dealias)                # k₂ = N̂(û*)
  convolve!(ws.k1, ws.k1, ws.Ek)                                 # E·k₁
  convolve!(uh, uh, ws.Ek)                                       # E·ûₙ
  field_data(uh) .+= (dt / 2) .* (field_data(ws.k1) .+ field_data(ws.k2))   # ûₙ₊₁
  force!(uh, band, ws, p)
  return uh
end


# =============================================================================
# Particles — RK2 in space on the frozen start-of-step velocity field (the O(Δt²)
# field-staleness is fine for a demo). Uses the package's interpolate (gather).
# Positions wrap into [0, L). Records and returns the start-of-step velocity.
# =============================================================================

function advect!(X, u, dt, p)
  v1 = point_values(interpolate(u, PointSet(X)))          # CatmullRom gather (package)
  Xmid = mod.(X .+ dt .* v1, p.L)
  v2 = point_values(interpolate(u, PointSet(Xmid)))
  X .= mod.(X .+ (dt / 2) .* (v1 .+ v2), p.L)
  return v1
end


# =============================================================================
# Initial condition — random field, large-scale envelope, projected solenoidal,
# band-energy normalized. GAP: a random-solenoidal-IC generator helper.
# =============================================================================

function random_solenoidal(grid, m, plans, ws, ksq, band, p; kp = 2.0)
  rng = MersenneTwister(p.seed)
  uh = to_spectral(VectorFieldPhysical(randn(rng, p.N, p.N, p.N, 3), grid), plans)
  envelope = spectral_kernel(uh, exp.(-(ksq ./ kp^2)))    # concentrate at large scales
  convolve!(uh, uh, envelope)                             # apply it (alias-safe, coefficientwise)
  helmholtz_projection!(uh, uh, m)                        # make solenoidal (alias-guarded)
  force!(uh, band, ws, p)                                 # set the forced-band energy
  return uh
end


# =============================================================================
# Structure functions, autocorrelations and integral scales — the trace S₂'s
# (eulerian_trace_s2! / lagrangian_stats), the Lagrangian velocity autocorrelation,
# and the integral-scale reduction (integral_scale) all live in hist_postprocess.jl
# (shared with the GPU twin). The Eulerian integral length comes from the package's
# radial_correlation (below); the Lagrangian integral time from lagrangian_stats.
# =============================================================================


# =============================================================================
# Driver
# =============================================================================

function run_hist(p::Params)
  isdir(OUTDIR) || mkpath(OUTDIR)
  @printf("HIST_CPU: N=%d  ν=%.3g  forcing |k|≤%d @ E=%.2g  (%d spinup + %d stats steps)\n",
          p.N, p.ν, p.k_force, p.E_force, p.n_spinup, p.n_stats)
  @printf("  threads: Julia=%d  (package CPU threading %s — launch with `-tN` to use more cores)\n",
          Threads.nthreads(), Threads.nthreads() > 1 ? "ON" : "off")

  # --- setup: grid, plans, multipliers, masks -------------------------------
  grid   = Grid3D((p.N, p.N, p.N), (p.L, p.L, p.L))
  layout = RealFourierLayout()
  uphys0 = VectorFieldPhysical(zeros(p.N, p.N, p.N, 3), grid)
  uspec0 = VectorFieldSpectral(zeros(ComplexF64, spectral_field_shape(grid, layout, Val(1))), grid)
  vplans = FieldTransformPlans(uphys0, uspec0)            # vector physical ↔ spectral
  splans = FieldTransformPlans(ScalarFieldPhysical(zeros(p.N, p.N, p.N), grid),
                               ScalarFieldSpectral(zeros(ComplexF64, spectral_field_shape(grid, layout, Val(0))), grid))
  m    = FieldSpectralMultipliers(uspec0)
  ksq  = real.(field_data(squared_wavenumber_field(uspec0, m)))   # |k|² (package), for the consumer symbols
  # 2/3-rule de-alias filter and the forcing band, both as package shell-mask kernels.
  dealias = spectral_cutoff(uspec0, m, (2 / 3) * (p.N / 2) * (2π / p.L))
  band    = spectral_band(uspec0, m, 0.5 * (2π / p.L), (p.k_force + 0.5) * (2π / p.L))
  ws   = make_workspace(grid, layout, p)                # preallocated scratch (a step allocates nothing)
  Δx   = p.L / p.N

  # --- initial condition ----------------------------------------------------
  uh = random_solenoidal(grid, m, vplans, ws, ksq, band, p)
  convolve!(uh, uh, dealias)

  # --- spin-up to stationarity (adaptive Δt) --------------------------------
  t_hist = Float64[]; E_hist = Float64[]; ε_hist = Float64[]
  t = 0.0
  sim_start = time()                                          # wall-clock of the simulation (the time loops)
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
  X = p.L .* rand(MersenneTwister(p.seed + 1), p.n_particles, 3)   # seed tracers
  n_rec = p.n_stats ÷ p.rec_stride
  V = zeros(p.n_particles, 3, n_rec)                              # recorded velocities
  Cacc = Float64[]; sep = Float64[]; n_snap = 0   # time-averaged velocity autocorrelation C(r)
  rec = 0
  for n in 1:p.n_stats
    to_velocity_vorticity!(ws.u, ws.ω0, uh, ws, m, vplans)       # start-of-step velocity & vorticity
    push!(t_hist, t); push!(E_hist, kinetic_energy(ws.u)); push!(ε_hist, dissipation(ws.ω0, p))
    step!(uh, ws, m, vplans, dealias, band, ksq, p, dt)          # advances ûₙ (reuses ws.u, ws.ω0 for k₁)
    v = advect!(X, ws.u, dt, p)                                  # advect on the start-of-step velocity
    if n % p.rec_stride == 0 && rec < n_rec
      rec += 1
      V[:, :, rec] .= v
    end
    if n % p.snap_stride == 0
      # Eulerian statistics from the FFT velocity autocorrelation C(r) (package, shell-averaged):
      # the trace S⁽ᴱ⁾(r) = (2/3)(C(0) − C(r)) and the integral length L = ∫ρ both follow from it
      # — no hand-rolled spatial shift. Accumulate C over snapshots for a time average.
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
  # divergence check (should be ~roundoff): ‖∇·u‖ / (k_rms ‖u‖), via the package l2norm.
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
  rho_L = R_l ./ R_l[1]
  τ_u   = integral_scale(τ_l, R_l)

  @printf("  K=%.4g  ε=%.4g  u'=%.4g  Re_λ=%.1f  η=%.3g  k_max·η=%.2f  ‖∇·u‖_rel=%.1e\n",
          K, ε, uprime, Reλ, η, kmaxη, divrel)
  @printf("  simulation: %.1f s wall-clock for %d steps at %d³  (%.1f ms/step)\n",
          sim_seconds, p.n_spinup + p.n_stats, p.N, 1e3 * sim_seconds / (p.n_spinup + p.n_stats))
  @printf("  scales: λ/η=%.2f  L/η=%.2f  |  τ_u/τ_η=%.2f  √(τ_η·τ_u)/τ_η=%.2f\n",
          λ / η, L_int / η, τ_u / τ_η, sqrt(τ_η * τ_u) / τ_η)
  # Parseval: the package's spectral `inner` (rfft half-spectrum weighting) reproduces
  # the physical ½⟨|u|²⟩ exactly — same energy, computed in spectral representation.
  @printf("  ½⟨|u|²⟩: physical=%.6g  spectral inner(û,û)=%.6g  |  Σ E(k)=%.4g  (Parseval)\n",
          K, 0.5 * inner(uh, uh), sum(ek_E))
  @assert isfinite(K) && isfinite(ε) && divrel < 1e-6 "non-finite or non-solenoidal state"

  # --- dump every plotted curve to HDF5, then plot (re-plot via plot_hist.jl) -
  bundle = Dict{String, Any}(
    "backend" => "CPU", "eltype" => "Float64",
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
  save_hist(joinpath(OUTDIR, "HIST_CPU.h5"), bundle)
  make_hist_plots(bundle; outdir = OUTDIR, prefix = "HIST_CPU")
  return nothing
end


# =============================================================================
# Entry point
# =============================================================================

function main()
  p = ("--smoke" in ARGS) ? smoke() :
      ("--fast"  in ARGS) ? fast()  :
      ("--huge"  in ARGS) ? huge()  : Params()
  run_hist(p)
end

main()
