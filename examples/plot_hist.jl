# =============================================================================
# plot_hist.jl — re-render the HIST figures from a saved HDF5 dump, WITHOUT re-running
# the DNS. The solver run is the expensive part; this lets the plots be polished freely.
#
#   julia --project=examples examples/plot_hist.jl <run.h5> [outdir]
#
# Needs only HDF5 + Plots (no GBGPeriodicFields, no GPU): it reads the curves the solver
# already computed. Works on any dump (CPU, ROCm or CUDA); the figures take the dump's file name
# as their prefix, e.g. HIST_CUDA_giant.h5 gives HIST_CUDA_giant_spectrum.png.
# =============================================================================

include(joinpath(@__DIR__, "hist_postprocess.jl"))

function main()
  isempty(ARGS) && error("usage: julia --project=examples examples/plot_hist.jl <run.h5> [outdir]")
  path = ARGS[1]
  bundle = load_hist(path)
  outdir = length(ARGS) >= 2 ? ARGS[2] : dirname(abspath(path))
  prefix = splitext(basename(path))[1]
  println("re-plotting ", path, "  (backend=", get(bundle, "backend", "?"), ", N=", get(bundle, "N", "?"), ")")
  make_hist_plots(bundle; outdir = outdir, prefix = prefix)
end

main()
