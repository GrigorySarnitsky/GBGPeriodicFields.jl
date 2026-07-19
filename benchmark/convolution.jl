# Convolution benchmarks: periodic convolution as the coefficientwise spectral product f̂·ĝ — apply
# a Fourier kernel ĝ (a ScalarFieldSpectral) to a field in spectral representation. The in-place
# convolve! is a bandwidth-bound coefficientwise multiply (read the kernel + field, write the field),
# the same cost profile as laplacian!; a scalar kernel over a vector field touches three components.
# `bench_sync` forces GPU completion. `spectral_cutoff` builds a kernel (allocates + one mask pass),
# and `translation_kernel` likewise (three per-axis cos/sin vectors, then one separable product pass) —
# a kernel is built once and applied many times, so a builder's cost is amortized over its uses.

function add_convolution!(group, AT, ::Type{T}, grid, tag) where {T}
  s = scalar_spec(AT, T, grid); sout = scalar_spec(AT, T, grid)
  u = vector_spec(AT, T, grid); uout = vector_spec(AT, T, grid)
  kernel = scalar_spec(AT, T, grid)            # a transfer function ĝ (values are irrelevant to timing)
  m = FieldSpectralMultipliers(s)
  group["convolve! scalar | $tag"] = @benchmarkable (convolve!($sout, $s, $kernel); bench_sync(field_data($sout)))
  group["convolve! vector | $tag"] = @benchmarkable (convolve!($uout, $u, $kernel); bench_sync(field_data($uout)))
  # decision 33: the lazy exponential kernel (evaluates exp per mode instead of reading a stored
  # kernel field) and the kernel-composed combination (combine! + convolve! as one pass — the
  # sequential pair above is its baseline)
  coefficient = T(-0.1); weight_a = T(0.3); weight_b = T(0.7)
  group["exponential_convolve! scalar | $tag"] = @benchmarkable (exponential_convolve!($sout, $s, $m, $coefficient); bench_sync(field_data($sout)))
  group["exponential_convolve! vector | $tag"] = @benchmarkable (exponential_convolve!($uout, $u, $m, $coefficient); bench_sync(field_data($uout)))
  group["combine!∘kernel vector | $tag"] = @benchmarkable (combine!($uout, $weight_a, $u, $weight_b, $uout, $kernel); bench_sync(field_data($uout)))
  group["spectral_cutoff | $tag"]  = @benchmarkable bench_sync(field_data(spectral_cutoff($s, $m, 2)))
  group["spectral_band | $tag"]    = @benchmarkable bench_sync(field_data(spectral_band($s, $m, 1, 3)))
  group["squared_wavenumber_field | $tag"] = @benchmarkable bench_sync(field_data(squared_wavenumber_field($s, $m)))
  group["assignment_window | $tag"] = @benchmarkable bench_sync(field_data(assignment_window($s, $m)))
  offset = ntuple(d -> T(0.5) * grid.grid_spacing[d], 3)     # a half-cell displacement
  group["translation_kernel | $tag"] = @benchmarkable bench_sync(field_data(translation_kernel($s, $m, $offset)))
end
