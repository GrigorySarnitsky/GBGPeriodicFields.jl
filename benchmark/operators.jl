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
  # The inverse is a separate kernel, not the same pass run backwards: it divides by ``|k|^2`` and must
  # special-case the zero mode, so its cost is a reciprocal per mode plus a branch the forward pass has not.
  group["inverse_laplacian! scalar | $tag"] = @benchmarkable (inverse_laplacian!($sout, $s, $m); bench_sync(field_data($sout)))
  group["helmholtz! vec->vec | $tag"]     = @benchmarkable (helmholtz_projection!($uout, $u, $m); bench_sync(field_data($uout)))
  # kernel-composed forms (decision 32): the operator with a convolution fused into the same pass,
  # against which the sequential operator + convolve! pair is the baseline the fusion replaces
  kernel = spectral_cutoff(s, m, T(size(field_data(s), 2)) / 3)
  group["helmholtz!∘kernel vec->vec | $tag"]   = @benchmarkable (helmholtz_projection!($uout, $u, $m, $kernel); bench_sync(field_data($uout)))
  group["divergence!∘kernel vec->scalar | $tag"] = @benchmarkable (divergence!($sout, $u, $m, $kernel); bench_sync(field_data($sout)))
end
