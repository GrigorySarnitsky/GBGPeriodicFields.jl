# =============================================================================
# HIST_CPU.jl — forced Homogeneous Isotropic Stationary Turbulence, on the CPU.
#
# A *small, demonstration* pseudospectral DNS that drives GBGPeriodicFields as a
# consumer would, then plots the Eulerian and Lagrangian second-order velocity
# structure functions. It is deliberately tiny (default 32^3) — the goal is a
# readable, end-to-end workflow, NOT a production DNS. At 32^3 there is almost no
# inertial range, so the K41 slope guides on the plots are *references*, not fits;
# bump `N` to 64/128 (and lengthen the run) for nicer curves.
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
# the divergence check) and radial_spectrum (the radial energy spectrum E(k));
# convolve with the kernel/coordinate builders spectral_cutoff (de-alias),
# spectral_band (the forcing band) and squared_wavenumber_field (|k|², for the
# integrating-factor / IC-envelope symbols); and interpolate (grid→point). What this
# script must still HAND-ROLL — every one a candidate for promotion into the package —
# is collected in examples/README.md (the "gap list"): the random-solenoidal IC
# generator, and the Eulerian-S₂ field-shift (circshift). Those touch `field_data(...)`;
# the forcing and the spectrum are now pure package ops (see HIST_ROCm.jl, fully on-device).
#
#   julia --project=examples examples/HIST_CPU.jl            # full run (~1 min)
#   julia --project=examples examples/HIST_CPU.jl --smoke    # tiny, for a quick check
# =============================================================================

using GBGPeriodicFields
using GBGPeriodicFields: field_data, field_grid          # raw-array / grid accessors
using Random, Statistics, Printf, LinearAlgebra
using Plots

const OUTDIR = joinpath(@__DIR__, "output")


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


# =============================================================================
# Diagnostics — kinetic energy, dissipation, the CFL speed and the energy spectrum
# are all package reductions now (Reductions module): `inner(f,g) = ⟨f·g⟩`,
# `lpnorm(u, Inf) = sup|u|`, and `radial_spectrum(û, m)` = the shell-resolved inner
# (the radial power spectrum, `Σ spectrum = inner` ⇒ Σ E = ½⟨|u|²⟩). No field_data
# loops; the energy spectrum is one call.
# =============================================================================

kinetic_energy(u) = 0.5 * inner(u, u)                                  # ½⟨|u|²⟩   (Reductions.inner)
dissipation(ω, p) = p.ν * inner(ω, ω)                                  # ν⟨|ω|²⟩   (homogeneous)
max_speed(u)      = lpnorm(u, Inf)                                     # sup|u|, the CFL velocity

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

function force!(uh, band, p)
  band_kinetic = 0.5 * inner(convolve(uh, band), uh)    # ½⟨|u_band|²⟩ via Parseval (package inner)
  band_kinetic < 1e-12 && return uh                     # guard (IC seeds the band)
  scale = sqrt(p.E_force / band_kinetic)
  field_data(uh) .+= (scale - 1) .* field_data(convolve(uh, band))   # in-band modes × scale
  return uh
end


# =============================================================================
# Right-hand side and time integration
# =============================================================================

# N̂(û) = de-aliased Leray projection of (u×ω)^. Returns (N̂, u_physical); the
# physical velocity is reused for particle advection, so it is handed back.
function nonlinear(uh, m, plans, dealias)
  ωh = curl(uh, m)                       # spectral vorticity  (package)
  u  = to_physical(uh, plans)            # ALLOCATING ⇒ preserves û (invariant 11)
  ω  = to_physical(ωh, plans)
  Nh = to_spectral(cross(u, ω), plans)   # (u × ω)^         (package cross)
  Nh = helmholtz_projection(Nh, m)       # Leray projection (drops the pressure)
  convolve!(Nh, Nh, dealias)             # 2/3 de-alias (convolve with the sharp cutoff)
  return Nh, u
end

# One integrating-factor RK2 (Heun) step. The integrating factor E = exp(−νk²Δt)
# is a consumer-built kernel (its ν, Δt are physics, invariant 12), applied with
# the package's `convolve` (the coefficientwise multiply f̂·ĝ).
#   k₁ = N̂(ûₙ);  û* = E·(ûₙ + Δt·k₁);  k₂ = N̂(û*)
#   ûₙ₊₁ = E·ûₙ + (Δt/2)(E·k₁ + k₂);   then force.
# Returns the start-of-step physical velocity (for particle advection).
function step!(uh, m, plans, dealias, band, ksq, p, dt)
  Ek = spectral_kernel(uh, exp.(-p.ν .* ksq .* dt))      # integrating factor exp(−νk²Δt)
  k1, u = nonlinear(uh, m, plans, dealias)

  ustar = convolve(uh + dt * k1, Ek)                     # û* = E·(ûₙ + Δt·k₁)
  k2, _ = nonlinear(ustar, m, plans, dealias)

  # ûₙ₊₁ = E·ûₙ + (Δt/2)(E·k₁ + k₂)   — linear field algebra + convolve, then commit
  copyto!(field_data(uh), field_data(convolve(uh, Ek) + (dt / 2) * (convolve(k1, Ek) + k2)))
  force!(uh, band, p)
  return u
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

function random_solenoidal(grid, m, plans, ksq, band, p; kp = 2.0)
  rng = MersenneTwister(p.seed)
  uh = to_spectral(VectorFieldPhysical(randn(rng, p.N, p.N, p.N, 3), grid), plans)
  envelope = spectral_kernel(uh, exp.(-(ksq ./ kp^2)))    # concentrate at large scales
  convolve!(uh, uh, envelope)                             # apply it (alias-safe, coefficientwise)
  helmholtz_projection!(uh, uh, m)                        # make solenoidal (alias-guarded)
  force!(uh, band, p)                                     # set the forced-band energy
  return uh
end


# =============================================================================
# Structure functions (second order)
# =============================================================================

# Eulerian longitudinal S₂(r) = ⟨[(u(x+rê)−u(x))·ê]²⟩, averaged over the 3 axes.
# Accumulates into S2acc (one entry per separation r = 1…N/2 grid points).
function eulerian_s2!(S2acc, u, p)
  d = field_data(u)
  for r in 1:(p.N ÷ 2)
    s = 0.0
    for (a, shift) in ((1, (-r, 0, 0)), (2, (0, -r, 0)), (3, (0, 0, -r)))
      ca = @view d[:, :, :, a]
      s += mean(abs2, circshift(ca, shift) .- ca)         # u_a(x+rê) − u_a(x)
    end
    S2acc[r] += s / 3
  end
  return S2acc
end

# Lagrangian S₂(τ) = ⟨|u_p(t+τ) − u_p(t)|²⟩ over particles and time origins.
# V is (n_particles, 3, n_records); τ = lag · (rec_stride · dt).
function lagrangian_s2(V, lag_dt)
  M, _, T = size(V)
  lagmax = max(T ÷ 3, 1)
  τ = collect(1:lagmax) .* lag_dt
  S2 = zeros(lagmax)
  for ℓ in 1:lagmax
    acc = 0.0
    for n in 1:(T - ℓ)
      @inbounds for c in 1:3, i in 1:M               # allocation-free increment
        acc += abs2(V[i, c, n + ℓ] - V[i, c, n])
      end
    end
    S2[ℓ] = acc / (M * (T - ℓ))
  end
  return τ, S2
end


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
  Δx   = p.L / p.N

  # --- initial condition ----------------------------------------------------
  uh = random_solenoidal(grid, m, vplans, ksq, band, p)
  convolve!(uh, uh, dealias)

  # --- spin-up to stationarity (adaptive Δt) --------------------------------
  t_hist = Float64[]; E_hist = Float64[]; ε_hist = Float64[]
  t = 0.0
  for n in 1:p.n_spinup
    u = to_physical(uh, vplans)
    dt = p.cfl * Δx / max(max_speed(u), 1e-6)
    push!(t_hist, t); push!(E_hist, kinetic_energy(u))
    push!(ε_hist, dissipation(to_physical(curl(uh, m), vplans), p))
    step!(uh, m, vplans, dealias, band, ksq, p, dt)
    t += dt
  end

  # Freeze Δt for the statistics window so the Lagrangian τ-axis is uniform.
  dt = p.cfl * Δx / max(max_speed(to_physical(uh, vplans)), 1e-6)

  # --- statistics window: advance, advect particles, accumulate stats -------
  X = p.L .* rand(MersenneTwister(p.seed + 1), p.n_particles, 3)   # seed tracers
  n_rec = p.n_stats ÷ p.rec_stride
  V = zeros(p.n_particles, 3, n_rec)                              # recorded velocities
  S2e = zeros(p.N ÷ 2); n_snap = 0
  rec = 0
  for n in 1:p.n_stats
    u = step!(uh, m, vplans, dealias, band, ksq, p, dt)          # u = start-of-step velocity
    push!(t_hist, t); push!(E_hist, kinetic_energy(u))
    push!(ε_hist, dissipation(to_physical(curl(uh, m), vplans), p))
    v = advect!(X, u, dt, p)
    if n % p.rec_stride == 0 && rec < n_rec
      rec += 1
      V[:, :, rec] .= v
    end
    if n % p.snap_stride == 0
      eulerian_s2!(S2e, u, p); n_snap += 1
    end
    t += dt
  end
  S2e ./= max(n_snap, 1)

  # --- final diagnostics ----------------------------------------------------
  u  = to_physical(uh, vplans)
  K  = kinetic_energy(u)
  ε  = dissipation(to_physical(curl(uh, m), vplans), p)
  uprime = sqrt(2K / 3)
  Reλ = sqrt(15 * uprime^4 / (p.ν * ε))
  η   = (p.ν^3 / ε)^(1 / 4)
  kmaxη = (2 / 3) * (p.N / 2) * η
  # divergence check (should be ~roundoff): ‖∇·u‖ / (k_rms ‖u‖), via the package l2norm.
  divp = to_physical(divergence(uh, m), splans)
  divrel = l2norm(divp) / (sqrt(mean(ksq)) * l2norm(u) + 1e-30)
  ek_k, ek_E = energy_spectrum(uh, m)
  @printf("  K=%.4g  ε=%.4g  u'=%.4g  Re_λ=%.1f  η=%.3g  k_max·η=%.2f  ‖∇·u‖_rel=%.1e\n",
          K, ε, uprime, Reλ, η, kmaxη, divrel)
  # Parseval: the package's spectral `inner` (rfft half-spectrum weighting) reproduces
  # the physical ½⟨|u|²⟩ exactly — same energy, computed in spectral representation.
  @printf("  ½⟨|u|²⟩: physical=%.6g  spectral inner(û,û)=%.6g  |  Σ E(k)=%.4g  (Parseval)\n",
          K, 0.5 * inner(uh, uh), sum(ek_E))
  @assert isfinite(K) && isfinite(ε) && divrel < 1e-6 "non-finite or non-solenoidal state"

  # --- structure functions --------------------------------------------------
  r_e = (1:(p.N ÷ 2)) .* Δx
  τ_l, S2l = lagrangian_s2(V, p.rec_stride * dt)

  make_plots(p, t_hist, E_hist, ε_hist, ek_k, ek_E, r_e, S2e, τ_l, S2l, uprime)
  return nothing
end


# =============================================================================
# Plots (Plots.jl / GR) — four panels saved as PNGs under examples/output/.
# =============================================================================

function make_plots(p, t, E, ε, ek_k, ek_E, r_e, S2e, τ_l, S2l, uprime)
  ENV["GKSwstype"] = "100"        # headless GR (write PNG without a display)
  gr()

  # energy spectrum (only populated, positive shells)
  kpos = findall(@. (ek_k > 0) & (ek_E > 0))
  kk, Ek = ek_k[kpos], ek_E[kpos]
  spec = plot(kk, Ek; xscale = :log10, yscale = :log10, marker = :circle, ms = 2, label = "E(k)",
              xlabel = "k", ylabel = "E(k)", title = "energy spectrum", legend = :bottomleft)
  plot!(spec, kk, Ek[1] .* (kk ./ kk[1]).^(-5 / 3); ls = :dash, label = "k⁻⁵ᐟ³ (K41)")

  # stationarity: E(t), ε(t), with the spin-up → statistics boundary marked
  stat = plot(t, E; label = "E(t)", xlabel = "t", title = "stationarity", legend = :right)
  plot!(stat, t, ε; label = "ε(t)")
  vline!(stat, [t[min(p.n_spinup + 1, length(t))]]; ls = :dot, label = "stats start")

  # Eulerian longitudinal S₂(r), with the K41 inertial guide and the large-r plateau
  se = plot(r_e, S2e; xscale = :log10, yscale = :log10, marker = :circle, ms = 2, label = "S₂(r)",
            xlabel = "r", ylabel = "S₂", title = "Eulerian longitudinal S₂(r)", legend = :bottomright)
  plot!(se, r_e, S2e[1] .* (r_e ./ r_e[1]).^(2 / 3); ls = :dash, label = "r²ᐟ³ (K41)")
  hline!(se, [2 * uprime^2]; ls = :dot, label = "2u'² plateau")

  # Lagrangian S₂(τ), with the K41 linear-in-τ guide
  lp = findall(>(0), S2l)
  sl = plot(τ_l[lp], S2l[lp]; xscale = :log10, yscale = :log10, marker = :circle, ms = 2,
            label = "S₂(τ)", xlabel = "τ", ylabel = "S₂", title = "Lagrangian S₂(τ)", legend = :bottomright)
  isempty(lp) || plot!(sl, τ_l[lp], S2l[lp[1]] .* (τ_l[lp] ./ τ_l[lp[1]]); ls = :dash, label = "∝ τ (K41)")

  for (fig, name) in ((spec, "spectrum"), (stat, "stationarity"), (se, "eulerian_s2"), (sl, "lagrangian_s2"))
    savefig(fig, joinpath(OUTDIR, "HIST_CPU_$(name).png"))
  end
  savefig(plot(spec, stat, se, sl; layout = (2, 2), size = (1100, 850)),
          joinpath(OUTDIR, "HIST_CPU_summary.png"))
  println("  wrote plots → ", OUTDIR)
  return nothing
end


# =============================================================================
# Entry point
# =============================================================================

function main()
  p = ("--smoke" in ARGS) ? smoke() : Params()
  run_hist(p)
end

main()
