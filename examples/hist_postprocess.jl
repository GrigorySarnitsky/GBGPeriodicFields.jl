# =============================================================================
# hist_postprocess.jl — shared analysis, HDF5 I/O and plotting for the HIST demos.
#
# Both HIST_CPU.jl and gpu/rocm/HIST_ROCm.jl `include` this file. It holds the parts
# that are NOT about exercising the package — the host-side statistics, the data dump,
# and the Plots.jl figures — so the two solver scripts stay focused on the package
# itself and do not duplicate the plotting boilerplate. Everything here is written
# type-generically (Float64 on the CPU, Float32 on the GPU) and operates on host
# arrays / fields, so the same code serves both.
#
# The pipeline is split SIMULATE → DUMP → PLOT: the solver writes every plotted curve
# and scalar to an HDF5 file (`save_hist`), then renders (`make_hist_plots`). A
# separate `plot_hist.jl <file.h5>` re-renders from a saved file WITHOUT re-running the
# DNS — so the plots can be polished freely (the run is the expensive part).
# =============================================================================

using HDF5
using Plots
using Plots.PlotMeasures: mm
using PGFPlotsX                      # LaTeX plotting backend
using LaTeXStrings                   # L"..." math in axis labels and annotations
using Statistics: mean

# Activate the LaTeX (PGFPlotsX) backend HERE, at include time — not inside make_hist_plots. Switching the
# Plots backend inside a function and then plotting in that same function body hits a world-age error (the
# backend's freshly-defined methods are invisible to the already-compiled body, so the figure's backend
# object stays `nothing`). amsmath + newtx (the user's preferred text/math fonts) go in the LaTeX preamble.
pgfplotsx()
for command in ("\\usepackage{amsmath}", "\\usepackage[upint,varvw]{newtx}")
  command ∉ PGFPlotsX.CUSTOM_PREAMBLE && push!(PGFPlotsX.CUSTOM_PREAMBLE, command)
end


# =============================================================================
# Second-order structure functions (per-component) and the velocity autocorrelations.
#
# These are the standard per-component second-order structure functions — one third of the
# trace ⟨|δu|²⟩ (the K41 forms):
#   Eulerian   S⁽ᴱ⁾(Δx) = (1/3)⟨|u(x+Δx) − u(x)|²⟩      (all components, isotropically
#                                                         averaged over direction)
#   Lagrangian S⁽ᴸ⁾(Δt) = (1/3)⟨|U(t+Δt) − U(t)|²⟩       (over particles & time origins)
# For a homogeneous field the Eulerian one is got from the velocity autocorrelation,
# S⁽ᴱ⁾(r) = (2/3)(C(0) − C(r)) with C(r) = ⟨u(x)·u(x+r)⟩ — so the driver reads it straight
# off the package's FFT-based `radial_correlation` (the shell-averaged C(r)); no
# hand-rolled spatial shift, and it scales to any grid. The Lagrangian one is the
# matching `(2/3)(R(0) − R(τ))`, but is computed below directly from the per-particle
# velocity increments (robust, and the recorded V is small).
# =============================================================================

# Lagrangian velocity autocorrelation R(τ) = ⟨U(t)·U(t+τ)⟩ and per-component structure function
# S⁽ᴸ⁾(τ) = (1/3)⟨|U(t+τ) − U(t)|²⟩, both over particles and time origins, in ONE pass over
# the recorded velocities. V is a host array (n_particles, 3, n_records); the lag axis τ
# includes τ = 0 (R(0) = ⟨|U|²⟩, S⁽ᴸ⁾(0) = 0). lag_dt = rec_stride · dt.
function lagrangian_stats(V, lag_dt)
  M, _, T = size(V)
  lag_max = max(T ÷ 3, 1)
  τ = collect(0:lag_max) .* lag_dt
  R = zeros(lag_max + 1)
  S2 = zeros(lag_max + 1)
  for ℓ in 0:lag_max
    acc_corr = 0.0
    acc_diff = 0.0
    for n in 1:(T - ℓ)
      @inbounds for c in 1:3, i in 1:M
        a = V[i, c, n]
        b = V[i, c, n + ℓ]
        acc_corr += a * b
        acc_diff += abs2(b - a)
      end
    end
    denominator = M * (T - ℓ)
    R[ℓ + 1] = acc_corr / denominator
    S2[ℓ + 1] = (acc_diff / denominator) / 3        # per-component: (1/3)⟨|ΔU|²⟩
  end
  return τ, R, S2
end

# Integral scale from a (one-sided) autocorrelation: L = ∫₀^∞ ρ(s) ds with ρ = corr/corr(0),
# truncated at the first zero crossing (the standard convention — beyond it the periodic-box
# correlation has a meaningless negative tail). `coordinate` is the matching separation/lag
# axis. Trapezoidal; serves both the Eulerian length (from C(r)) and the Lagrangian time
# (from R(τ)).
function integral_scale(coordinate, correlation)
  ρ = correlation ./ correlation[1]
  stop = something(findfirst(<=(0), ρ), length(ρ))
  scale = 0.0
  for i in 1:(stop - 1)
    scale += 0.5 * (ρ[i] + ρ[i + 1]) * (coordinate[i + 1] - coordinate[i])
  end
  return scale
end


# =============================================================================
# HDF5 I/O — dump every plotted curve and scalar so the figures can be regenerated
# without re-running the solver. The bundle is a flat Dict of names → arrays/scalars;
# save and load are exact inverses (each entry is one HDF5 dataset).
# =============================================================================

function save_hist(path, bundle::AbstractDict)
  h5open(path, "w") do file
    for (name, value) in bundle
      file[name] = value
    end
  end
  return path
end

function load_hist(path)
  bundle = Dict{String, Any}()
  h5open(path, "r") do file
    for name in keys(file)
      bundle[name] = read(file[name])
    end
  end
  return bundle
end


# =============================================================================
# Plots — Plots.jl with the PGFPlotsX (LaTeX) backend, so every axis label and
# annotation is typeset by LaTeX (amsmath + newtx; preamble set in make_hist_plots).
# Clean lines, no markers. The headline figure is the pair of compensated structure functions: the
# Eulerian and Lagrangian structure functions each normalized by their Kolmogorov
# inertial scaling (so a K41 inertial range would show as a plateau at 1). We keep
# the energy spectrum and the stationarity history too, and add the autocorrelations
# the integral scales are measured from.
#
# K41 inertial-range normalizations, applied here from the RAW stored data so the
# constants C₂, C₀ can be changed at plot time:
#   Eulerian:   S⁽ᴱ⁾(Δx) / [ (11/9) C₂ ε^{2/3} Δx^{2/3} ]   vs  Δx/η
#   Lagrangian: S⁽ᴸ⁾(Δt) / [ C₀ ε Δt ]                       vs  Δt/τ_η
# Marked scales: Eulerian λ/η (Taylor) and L/η (integral, from the autocorrelation);
# Lagrangian √(τ_η τ_u)/τ_η (the log-midpoint Taylor-time proxy) and τ_u/τ_η (integral).
# =============================================================================

# A dotted vertical line at `xpos` labelled `label`, placed at height `ypos` (the labels
# sit in the headroom above the curve; callers stagger the heights so close-by scales — as
# at the low demo Reynolds number, where λ ≈ L — do not overprint).
function mark_scale!(plt, xpos, label, ypos)
  vline!(plt, [xpos]; ls = :dot, lc = :gray, lw = 1, label = "")
  annotate!(plt, xpos, ypos, text(label, 8, :black, :center, :center))
  return plt
end

# Eulerian structure function normalized by its K41 scaling, vs Δx/η.
function eulerian_panel(b)
  η, ε, C₂ = b["eta"], b["epsilon"], b["C2"]
  r, S2 = b["r"], b["S2_E"]                        # r = 0 is already excluded by the driver when it
                                                   # stores the bundle; slicing again here would drop
                                                   # the smallest NONZERO separation as well
  norm = (11 / 9) * C₂ * ε^(2 / 3) .* r .^ (2 / 3)
  x, y = r ./ η, S2 ./ norm
  ymax = maximum(y)
  plt = plot(x, y; xscale = :log10, lw = 2, label = "",
             xlabel = L"\Delta x / \eta",
             ylabel = L"S^{(E)}(\Delta x) / \bigl(\tfrac{11}{9} C_2 \varepsilon^{2/3} \Delta x^{2/3}\bigr)",
             title = "Eulerian structure function", ylims = (0, 1.28 * ymax),
             left_margin = 8mm, bottom_margin = 5mm, right_margin = 5mm)
  mark_scale!(plt, b["lambda"] / η, L"\lambda/\eta", 1.20 * ymax)
  mark_scale!(plt, b["L_int"] / η, L"L/\eta", 1.10 * ymax)
  return plt
end

# Lagrangian structure function normalized by its K41 scaling, vs Δt/τ_η.
# Skips the τ = 0 sample (the normalization ∝ Δt and the log axis both exclude it).
function lagrangian_panel(b)
  τ_η, ε, C₀ = b["tau_eta"], b["epsilon"], b["C0"]
  τ, S2 = b["tau"][2:end], b["S2_L"][2:end]
  x, y = τ ./ τ_η, S2 ./ (C₀ * ε .* τ)
  ymax = maximum(y)
  plt = plot(x, y; xscale = :log10, lw = 2, label = "",
             xlabel = L"\Delta t / \tau_\eta",
             ylabel = L"S^{(L)}(\Delta t) / (C_0 \varepsilon \Delta t)",
             title = "Lagrangian structure function", ylims = (0, 1.28 * ymax),
             left_margin = 8mm, bottom_margin = 5mm, right_margin = 5mm)
  τ_u = b["tau_u"]
  mark_scale!(plt, sqrt(τ_η * τ_u) / τ_η, L"\sqrt{\tau_\eta \tau_u}/\tau_\eta", 1.20 * ymax)
  mark_scale!(plt, τ_u / τ_η, L"\tau_u/\tau_\eta", 1.10 * ymax)
  return plt
end

# Ticks and grid lines every half decade over `values`' range, labelled as powers of ten, so a slope
# can be read off the grid rather than estimated between decades.
function half_decade_ticks(values)
  low, high = floor(2 * log10(minimum(values))) / 2, ceil(2 * log10(maximum(values))) / 2
  exponents = low:0.5:high
  label(e) = isinteger(e) ? latexstring("10^{", Int(e), "}") : latexstring("10^{", e, "}")
  return (10 .^ exponents, label.(exponents))
end


# Energy spectrum E(κ) with the K41 inertial-range form C_K ε^(2/3) κ⁻⁵ᐟ³ (C_K ≈ 1.6, the Kolmogorov
# constant). This is the dimensionally-complete K41 prediction, not a bare κ⁻⁵ᐟ³ slope: E(κ) has the
# dimensions of energy·length (velocity²·length), κ⁻⁵ᐟ³ has dimensions length^(5/3), and the prefactor
# C_K ε^(2/3) (dimensions length^(4/3)/time²) is exactly what reconciles them — so there must be a constant
# in front, and it carries ε, the measured dissipation rate.
function spectrum_panel(b)
  populated = findall(@. (b["ek_k"] > 0) & (b["ek_E"] > 0))
  k, E = b["ek_k"][populated], b["ek_E"][populated]
  C_K, ε = get(b, "CK", 1.6), b["epsilon"]                  # Kolmogorov constant (plot-time) and dissipation
  plt = plot(k, E; xscale = :log10, yscale = :log10, lw = 2, label = L"E(\kappa)",
             xlabel = L"\kappa", ylabel = L"E(\kappa)", title = "energy spectrum", legend = :bottomleft,
             xticks = half_decade_ticks(k), yticks = half_decade_ticks(E))
  plot!(plt, k, C_K .* ε^(2 / 3) .* k .^ (-5 / 3); ls = :dash, lw = 1.5,
        label = L"C_K \varepsilon^{2/3} \kappa^{-5/3}\ \mathrm{(K41)}")
  return plt
end

# Stationarity history: turbulent kinetic energy k(t) and dissipation ε(t), with the spin-up boundary.
# (k for the turbulent kinetic energy, the standard symbol; κ — not k — is the wavenumber in the spectrum.)
function stationarity_panel(b)
  t = b["t"]
  plt = plot(t, b["E"]; lw = 2, label = L"k(t)", xlabel = L"t", title = "stationarity", legend = :right)
  plot!(plt, t, b["eps_t"]; lw = 2, label = L"\varepsilon(t)")
  boundary = min(Int(b["n_spinup"]) + 1, length(t))
  vline!(plt, [t[boundary]]; ls = :dot, label = "stats start")
  return plt
end

# The two velocity autocorrelations the integral scales are measured from — the spatial
# ρ(r) (its integral is L) and the Lagrangian ρ_L(τ) (its integral is τ_u) — as two panels,
# each with its integral scale marked (the integral is taken to the first zero crossing).
function autocorrelation_panel(b)
  η, τ_η = b["eta"], b["tau_eta"]
  spatial = plot(b["sep"][2:end] ./ η, b["rho_E"][2:end]; xscale = :log10, lw = 2,
                 label = "", xlabel = L"r/\eta", ylabel = L"\rho(r)",
                 title = "spatial velocity autocorrelation", left_margin = 5mm, bottom_margin = 5mm)
  vline!(spatial, [b["L_int"] / η]; ls = :dot, lc = :gray, label = "")
  annotate!(spatial, b["L_int"] / η, 0.9, text(L"L/\eta", 8, :black, :center, :center))
  hline!(spatial, [0]; lc = :gray, ls = :dot, label = "")

  temporal = plot(b["tau"][2:end] ./ τ_η, b["rho_L"][2:end]; xscale = :log10, lw = 2,
                  label = "", xlabel = L"\tau/\tau_\eta", ylabel = L"\rho_L(\tau)",
                  title = "Lagrangian velocity autocorrelation", left_margin = 5mm, bottom_margin = 5mm)
  vline!(temporal, [b["tau_u"] / τ_η]; ls = :dot, lc = :gray, label = "")
  annotate!(temporal, b["tau_u"] / τ_η, 0.9, text(L"\tau_u/\tau_\eta", 8, :black, :center, :center))
  hline!(temporal, [0]; lc = :gray, ls = :dot, label = "")
  return plot(spatial, temporal; layout = (1, 2), size = (1100, 430))
end

# Render and save all figures; `prefix` distinguishes the CPU and GPU outputs.
function make_hist_plots(bundle; outdir, prefix)
  isdir(outdir) || mkpath(outdir)

  eul = eulerian_panel(bundle)
  lag = lagrangian_panel(bundle)
  spec = spectrum_panel(bundle)
  stat = stationarity_panel(bundle)
  acf = autocorrelation_panel(bundle)
  structure = plot(eul, lag; layout = (1, 2), size = (1100, 430))

  save(fig, name) = savefig(fig, joinpath(outdir, "$(prefix)_$(name).png"))
  save(structure, "structure_functions")
  save(spec, "spectrum")
  save(stat, "stationarity")
  save(acf, "autocorrelation")
  savefig(plot(spec, stat, eul, lag; layout = (2, 2), size = (1100, 850)),
          joinpath(outdir, "$(prefix)_summary.png"))
  println("  wrote plots → ", outdir)
  return nothing
end
