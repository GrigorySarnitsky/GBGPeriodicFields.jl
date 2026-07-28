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
  # sequential pair above is its baseline). The exponent coefficient is scale-aware,
  # c = -4/|k|²_corner, so exp spans [e⁻⁴, 1] at every grid size — the range of a realistic
  # integrating factor, and the same measurement at every size. The former fixed c = -0.1 put an
  # ~11% shell of a 64³ grid's modes in Float32's subnormal band, so that cell measured the x86
  # subnormal assist (~16× per element) instead of the operation (PERFORMANCE.md finding (m)).
  corner_squared = maximum(m.squared_wavenumber_1) + maximum(m.squared_wavenumber_2) +
                   maximum(m.squared_wavenumber_3)
  coefficient = -T(4) / T(corner_squared); weight_a = T(0.3); weight_b = T(0.7)
  group["exponential_convolve! scalar | $tag"] = @benchmarkable (exponential_convolve!($sout, $s, $m, $coefficient); bench_sync(field_data($sout)))
  group["exponential_convolve! vector | $tag"] = @benchmarkable (exponential_convolve!($uout, $u, $m, $coefficient); bench_sync(field_data($uout)))
  group["combine!∘kernel vector | $tag"] = @benchmarkable (combine!($uout, $weight_a, $u, $weight_b, $uout, $kernel); bench_sync(field_data($uout)))
  group["spectral_cutoff | $tag"]  = @benchmarkable bench_sync(materialize_kernel(spectral_cutoff($s, $m, 2)) |> field_data)
  group["spectral_band | $tag"]    = @benchmarkable bench_sync(materialize_kernel(spectral_band($s, $m, 1, 3)) |> field_data)
  group["squared_wavenumber_field | $tag"] = @benchmarkable bench_sync(field_data(squared_wavenumber_field($s, $m)))
  # The two separable builders return their three per-axis factors (decision 50), so the build is O(N)
  # and there is no field to sync on — sync one factor instead.
  group["assignment_window | $tag"] = @benchmarkable bench_sync(assignment_window($s, $m).factor_1)
  offset = ntuple(d -> T(0.5) * grid.grid_spacing[d], 3)     # a half-cell displacement
  group["translation_kernel | $tag"] = @benchmarkable bench_sync(translation_kernel($s, $m, $offset).factor_1)
  # Applying an axis-factored kernel against applying the same kernel stored as a field: same result,
  # one field-sized stream fewer (the kernel is never read from memory).
  separable = translation_kernel(s, m, offset)
  stored = ScalarFieldSpectral(copy(Base.copy(GBGPeriodicFields.Convolution._kernel_data(separable))),
                               grid, field_layout(s))
  group["convolve! vector ∘ separable | $tag"] = @benchmarkable (convolve!($uout, $u, $separable); bench_sync(field_data($uout)))
  group["convolve! vector ∘ stored    | $tag"] = @benchmarkable (convolve!($uout, $u, $stored); bench_sync(field_data($uout)))
end
