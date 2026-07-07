# Spectral differential-operator benchmarks: in-place forms op!(dest, src, multipliers) on a field
# already in spectral representation (the operator kernel — a wavenumber multiply — not the FFT).

function add_operators!(group, AT, ::Type{T}, grid, tag) where {T}
  s = scalar_spec(AT, T, grid); sout = scalar_spec(AT, T, grid)
  u = vector_spec(AT, T, grid); uout = vector_spec(AT, T, grid)
  tout = tensor_spec(AT, T, grid)
  m = FieldSpectralMultipliers(s)
  group["gradient! scalar->vec | $tag"]   = @benchmarkable (gradient!($uout, $s, $m); bench_sync(field_data($uout)))
  group["divergence! vec->scalar | $tag"] = @benchmarkable (divergence!($sout, $u, $m); bench_sync(field_data($sout)))
  group["curl! vec->vec | $tag"]          = @benchmarkable (curl!($uout, $u, $m); bench_sync(field_data($uout)))
  group["symmetric_gradient! vec->tensor | $tag"] = @benchmarkable (symmetric_gradient!($tout, $u, $m); bench_sync(field_data($tout)))
  group["laplacian! scalar | $tag"]       = @benchmarkable (laplacian!($sout, $s, $m); bench_sync(field_data($sout)))
  group["helmholtz! vec->vec | $tag"]     = @benchmarkable (helmholtz_projection!($uout, $u, $m); bench_sync(field_data($uout)))
end
