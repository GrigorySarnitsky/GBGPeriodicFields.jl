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
# FieldSpectralMultipliers, curl, cross, helmholtz_projection, divergence, and
# interpolate (grid→point). What this script must HAND-ROLL — every one a candidate
# for promotion into the package — is collected in examples/README.md (the "gap
# list"). The hand-rolled bits all touch `field_data(...)` with scalar indexing,
# which is fine on the CPU; the forthcoming HIST_ROCm.jl (allowscalar(false)) is
# what will force those into the package.
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
# Spectral utilities — built from the package's own per-axis squared wavenumbers
# (m.squared_wavenumber_1..3, true k² kept at Nyquist). GAP: the package exposes
# the 1-D wavenumber arrays but no |k|-field / mask / shell-average / "apply f(k)".
# =============================================================================

# 3-D |k|² over the (Nkx, Ny, Nz) spectral grid.
function ksquared(m)
  s1 = reshape(m.squared_wavenumber_1, :, 1, 1)
  s2 = reshape(m.squared_wavenumber_2, 1, :, 1)
  s3 = reshape(m.squared_wavenumber_3, 1, 1, :)
  return s1 .+ s2 .+ s3
end

# 2/3-rule de-aliasing mask: keep |kᵢ| ≤ (2/3)·k_Nyquist on every axis.
function dealias_mask(m, p)
  kcut2 = (2 / 3 * (p.N / 2) * 2π / p.L)^2
  a1 = reshape(m.squared_wavenumber_1 .<= kcut2, :, 1, 1)
  a2 = reshape(m.squared_wavenumber_2 .<= kcut2, 1, :, 1)
  a3 = reshape(m.squared_wavenumber_3 .<= kcut2, 1, 1, :)
  return Float64.(a1 .& a2 .& a3)
end

# Multiply every fiber component of a spectral field by a per-mode factor w(k)
# (de-alias mask, integrating factor, IC envelope). This is the diagonal-operator
# "apply f(k)" the package does not expose publicly.
function apply_spectral!(field, w3d)
  d = field_data(field)
  d .*= reshape(w3d, size(w3d)..., 1)
  return field
end

# Per-mode integer wavenumber magnitude |k| (L = 2π ⇒ already integer-scaled).
wavenumber_magnitude(m, p) = sqrt.(ksquared(m)) .* (p.L / 2π)


# =============================================================================
# Diagnostics — kinetic energy and dissipation in PHYSICAL space (robust, no rfft
# Parseval bookkeeping); the shell spectrum E(k) is the one spectral reduction.
# GAP: the package has no public mean/l2norm/maximum/energy/enstrophy/spectrum.
# =============================================================================

kinetic_energy(u, p) = 0.5 * sum(abs2, field_data(u)) / p.N^3          # ½⟨|u|²⟩
dissipation(ω, p)    = p.ν * sum(abs2, field_data(ω)) / p.N^3          # ν⟨|ω|²⟩ (homogeneous)

function max_speed(u)
  d = field_data(u)
  return sqrt(maximum(@views d[:, :, :, 1].^2 .+ d[:, :, :, 2].^2 .+ d[:, :, :, 3].^2))
end

# Shell-averaged energy spectrum E(κ): ½ Σ_{|k|∈shell} |û|² / N⁶, with the rfft
# half-complex doubling (×2 for 0 < kx < Nyquist). ∑ₖ E(κ) ≈ kinetic energy.
function energy_spectrum(uh, m, p)
  d = field_data(uh)
  s1, s2, s3 = m.squared_wavenumber_1, m.squared_wavenumber_2, m.squared_wavenumber_3
  Nkx = length(s1)
  kmax = floor(Int, p.N / 2)
  E = zeros(kmax + 1)
  inv = 1 / (2 * float(p.N)^6)
  for k in axes(d, 3), j in axes(d, 2), i in 1:Nkx
    κ = round(Int, sqrt(s1[i] + s2[j] + s3[k]) * p.L / 2π)
    κ > kmax && continue
    weight = (i == 1 || (iseven(p.N) && i == Nkx)) ? 1.0 : 2.0
    E[κ + 1] += inv * weight * (abs2(d[i, j, k, 1]) + abs2(d[i, j, k, 2]) + abs2(d[i, j, k, 3]))
  end
  return collect(0:kmax), E
end


# =============================================================================
# Forcing — hold the energy in shells 1 ≤ |k| ≤ k_force at E_force by rescaling
# those modes (scaling preserves ∇·u = 0). Deterministic, unconditionally
# stationary. GAP: needs shell/band access (consumer-level otherwise).
# =============================================================================

function force!(uh, m, p)
  d = field_data(uh)
  s1, s2, s3 = m.squared_wavenumber_1, m.squared_wavenumber_2, m.squared_wavenumber_3
  Nkx = length(s1)
  in_band(i, j, k) = (κ = sqrt(s1[i] + s2[j] + s3[k]) * p.L / 2π; 0.5 ≤ κ ≤ p.k_force + 0.5)
  band = 0.0
  for k in axes(d, 3), j in axes(d, 2), i in 1:Nkx
    in_band(i, j, k) || continue
    weight = (i == 1 || (iseven(p.N) && i == Nkx)) ? 1.0 : 2.0
    band += weight * (abs2(d[i, j, k, 1]) + abs2(d[i, j, k, 2]) + abs2(d[i, j, k, 3])) / (2 * float(p.N)^6)
  end
  band < 1e-12 && return uh                              # guard (IC seeds the band)
  scale = sqrt(p.E_force / band)
  for k in axes(d, 3), j in axes(d, 2), i in 1:Nkx
    in_band(i, j, k) || continue
    d[i, j, k, 1] *= scale; d[i, j, k, 2] *= scale; d[i, j, k, 3] *= scale
  end
  return uh
end


# =============================================================================
# Right-hand side and time integration
# =============================================================================

# N̂(û) = de-aliased Leray projection of (u×ω)^. Returns (N̂, u_physical); the
# physical velocity is reused for particle advection, so it is handed back.
function nonlinear(uh, m, plans, mask)
  ωh = curl(uh, m)                       # spectral vorticity  (package)
  u  = to_physical(uh, plans)            # ALLOCATING ⇒ preserves û (invariant 11)
  ω  = to_physical(ωh, plans)
  Nh = to_spectral(cross(u, ω), plans)   # (u × ω)^         (package cross)
  Nh = helmholtz_projection(Nh, m)       # Leray projection (drops the pressure)
  apply_spectral!(Nh, mask)              # 2/3 de-alias
  return Nh, u
end

# One integrating-factor RK2 (Heun) step. E = exp(−νk²Δt) applied as a multiplier.
#   k₁ = N̂(ûₙ);  û* = E·(ûₙ + Δt·k₁);  k₂ = N̂(û*)
#   ûₙ₊₁ = E·ûₙ + (Δt/2)(E·k₁ + k₂);   then force.
# Returns the start-of-step physical velocity (for particle advection).
function step!(uh, m, plans, mask, ksq, p, dt)
  E = exp.(-p.ν .* ksq .* dt)
  k1, u = nonlinear(uh, m, plans, mask)

  ustar = VectorFieldSpectral(field_data(uh) .+ dt .* field_data(k1), field_grid(uh))
  apply_spectral!(ustar, E)
  k2, _ = nonlinear(ustar, m, plans, mask)

  apply_spectral!(uh, E)                                  # û ← E·ûₙ
  field_data(uh) .+= (dt / 2) .* (reshape(E, size(E)..., 1) .* field_data(k1) .+ field_data(k2))
  force!(uh, m, p)
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

function random_solenoidal(grid, m, plans, ksq, p; kp = 2.0)
  rng = MersenneTwister(p.seed)
  uh = to_spectral(VectorFieldPhysical(randn(rng, p.N, p.N, p.N, 3), grid), plans)
  apply_spectral!(uh, exp.(-(ksq ./ kp^2)))               # concentrate at large scales
  helmholtz_projection!(uh, uh, m)                        # make solenoidal (alias-guarded)
  force!(uh, m, p)                                        # set the forced-band energy
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
  ksq  = ksquared(m)
  mask = dealias_mask(m, p)
  Δx   = p.L / p.N

  # --- initial condition ----------------------------------------------------
  uh = random_solenoidal(grid, m, vplans, ksq, p)
  apply_spectral!(uh, mask)

  # --- spin-up to stationarity (adaptive Δt) --------------------------------
  t_hist = Float64[]; E_hist = Float64[]; ε_hist = Float64[]
  t = 0.0
  for n in 1:p.n_spinup
    u = to_physical(uh, vplans)
    dt = p.cfl * Δx / max(max_speed(u), 1e-6)
    push!(t_hist, t); push!(E_hist, kinetic_energy(u, p))
    push!(ε_hist, dissipation(to_physical(curl(uh, m), vplans), p))
    step!(uh, m, vplans, mask, ksq, p, dt)
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
    u = step!(uh, m, vplans, mask, ksq, p, dt)                    # u = start-of-step velocity
    push!(t_hist, t); push!(E_hist, kinetic_energy(u, p))
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
  K  = kinetic_energy(u, p)
  ε  = dissipation(to_physical(curl(uh, m), vplans), p)
  uprime = sqrt(2K / 3)
  Reλ = sqrt(15 * uprime^4 / (p.ν * ε))
  η   = (p.ν^3 / ε)^(1 / 4)
  kmaxη = (2 / 3) * (p.N / 2) * η
  # divergence check (should be ~roundoff): ‖∇·u‖ / (k_rms ‖u‖)
  divp = to_physical(divergence(uh, m), splans)
  divrel = sqrt(mean(abs2, field_data(divp))) / (sqrt(mean(ksq)) * sqrt(2K) + 1e-30)
  ek_k, ek_E = energy_spectrum(uh, m, p)
  @printf("  K=%.4g  ε=%.4g  u'=%.4g  Re_λ=%.1f  η=%.3g  k_max·η=%.2f  ‖∇·u‖_rel=%.1e\n",
          K, ε, uprime, Reλ, η, kmaxη, divrel)
  @printf("  Σ E(k)=%.4g vs K=%.4g  (Parseval check)\n", sum(ek_E), K)
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
