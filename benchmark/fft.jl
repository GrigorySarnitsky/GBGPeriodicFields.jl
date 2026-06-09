# FFT transform benchmarks: allocating to_spectral / to_physical (the user-facing forms; they copy,
# so they are reusable across evals — invariant 11). Scalar and vector orders.

function add_fft!(group, AT, ::Type{T}, grid, tag) where {T}
  for (label, mk) in (("scalar", scalar_phys), ("vector", vector_phys))
    phys = mk(AT, T, grid)
    plans = plans_for(phys, AT, T, grid)
    spec = to_spectral(phys, plans)
    group["to_spectral $label | $tag"] = @benchmarkable (s = to_spectral($phys, $plans); bench_sync(field_data(s)))
    group["to_physical $label | $tag"] = @benchmarkable (p = to_physical($spec, $plans); bench_sync(field_data(p)))
  end
end
