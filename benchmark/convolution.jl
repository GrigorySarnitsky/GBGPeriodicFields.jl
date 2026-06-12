# Convolution benchmarks: periodic convolution as the coefficientwise spectral product f̂·ĝ — apply
# a Fourier kernel ĝ (a ScalarFieldSpectral) to a field in spectral representation. The in-place
# convolve! is a bandwidth-bound coefficientwise multiply (read the kernel + field, write the field),
# the same cost profile as laplacian!; a scalar kernel over a vector field touches three components.
# `bench_sync` forces GPU completion. `spectral_cutoff` builds a kernel (allocates + one mask pass).

function add_convolution!(group, AT, ::Type{T}, grid, tag) where {T}
  s = scalar_spec(AT, T, grid); sout = scalar_spec(AT, T, grid)
  u = vector_spec(AT, T, grid); uout = vector_spec(AT, T, grid)
  kernel = scalar_spec(AT, T, grid)            # a transfer function ĝ (values are irrelevant to timing)
  m = FieldSpectralMultipliers(s)
  group["convolve! scalar | $tag"] = @benchmarkable (convolve!($sout, $s, $kernel); bench_sync(field_data($sout)))
  group["convolve! vector | $tag"] = @benchmarkable (convolve!($uout, $u, $kernel); bench_sync(field_data($uout)))
  group["spectral_cutoff | $tag"]  = @benchmarkable bench_sync(field_data(spectral_cutoff($s, $m, 2)))
  group["spectral_band | $tag"]    = @benchmarkable bench_sync(field_data(spectral_band($s, $m, 1, 3)))
  group["squared_wavenumber_field | $tag"] = @benchmarkable bench_sync(field_data(squared_wavenumber_field($s, $m)))
end
