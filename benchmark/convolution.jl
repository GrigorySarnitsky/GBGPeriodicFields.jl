# Convolution benchmarks: periodic convolution as the coefficientwise spectral product f̂·ĝ — apply
# a Fourier kernel ĝ to a field in spectral representation. The in-place convolve! is a
# bandwidth-bound coefficientwise multiply (read the kernel + field, write the field), the same cost
# profile as laplacian!; a scalar kernel over a vector field touches three components.
# `bench_sync` forces GPU completion.
#
# A kernel reaches convolve! in one of several storage classes, which compute the same coefficients
# and differ only in cost, so each compressed class is swept AGAINST ITS MATERIALIZED TWIN: that
# baseline is what makes a storage change legible, and comparing the classes to each other would not.
# Builders are swept for regressions rather than hot-path cost — a kernel is built once and applied
# many times — and a builder returning a compressed kernel is timed on one factor rather than on a
# field it never allocates.

function add_convolution!(group, AT, ::Type{T}, grid, tag) where {T}
  s = scalar_spec(AT, T, grid); sout = scalar_spec(AT, T, grid)
  u = vector_spec(AT, T, grid); uout = vector_spec(AT, T, grid)
  # A kernel is its own type since decision 60: a field of coefficients declares the role by being
  # wrapped, which costs nothing per call (the wrapper holds a reference).
  kernel = StoredKernel(scalar_spec(AT, T, grid))   # a transfer function ĝ (values irrelevant to timing)
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
  # These two rows named the builders but timed `materialize_kernel(builder(...))`, so an O(1) lazy
  # build was reported at the cost of an O(N³) materialization and neither could be tracked separately.
  # The builder rows now time the builder — there is no field to sync on, so sync a wavenumber row the
  # symbol closes over — and the materialization has rows of its own further down.
  group["spectral_cutoff | $tag"]  = @benchmarkable bench_sync(spectral_cutoff($m, 2).multipliers.squared_wavenumber_1)
  group["spectral_band | $tag"]    = @benchmarkable bench_sync(spectral_band($m, 1, 3).multipliers.squared_wavenumber_1)
  # The two separable builders return their three per-axis factors (decision 50), so the build is O(N)
  # and there is no field to sync on — sync one factor instead.
  group["assignment_window | $tag"] = @benchmarkable bench_sync(assignment_window($m).factor_1)
  group["tophat_window | $tag"] = @benchmarkable bench_sync(tophat_window($m, 0.7).factor_1)
  offset = ntuple(d -> T(0.5) * grid.grid_spacing[d], 3)     # a half-cell displacement
  group["translation_kernel | $tag"] = @benchmarkable bench_sync(translation_kernel($m, $offset).factor_1)
  # Applying an axis-factored kernel against applying the same kernel stored as a field: same result,
  # one field-sized stream fewer (the kernel is never read from memory).
  separable = translation_kernel(m, offset)
  stored = materialize_kernel(separable)       # the same coefficients, in the stored class
  group["convolve! vector ∘ separable | $tag"] = @benchmarkable (convolve!($uout, $u, $separable); bench_sync(field_data($uout)))
  group["convolve! vector ∘ stored    | $tag"] = @benchmarkable (convolve!($uout, $u, $stored); bench_sync(field_data($uout)))
  # The radial class against the same baseline. It stores no coefficients at all — a symbol and three
  # references — so it removes the same stream as the axis-factored form while paying one extra add
  # and the symbol evaluation per mode. Its own stored twin is the baseline, so the two compressed
  # classes are read against a common reference rather than against each other.
  radial = spectral_band(m, 1, 3)
  radial_stored = materialize_kernel(radial)
  group["convolve! vector ∘ radial    | $tag"] = @benchmarkable (convolve!($uout, $u, $radial); bench_sync(field_data($uout)))
  group["convolve! vector ∘ radial-stored | $tag"] = @benchmarkable (convolve!($uout, $u, $radial_stored); bench_sync(field_data($uout)))
  # The general radial builder, against the two named bands above: a symbol closure costs no more to
  # build than a cutoff, so a consumer bringing its own symbol pays nothing for the generality.
  smooth = k2 -> exp(-T(0.01) * k2)
  group["radial_kernel | $tag"] = @benchmarkable bench_sync(radial_kernel($smooth, $m).multipliers.squared_wavenumber_1)
  # The documented escape hatch. Expanding a compressed kernel allocates the O(N³) field the class
  # exists to avoid, so its cost is what a consumer trades away by materializing.
  group["materialize_kernel radial | $tag"]    = @benchmarkable bench_sync(field_data(materialize_kernel($radial).field))
  group["materialize_kernel separable | $tag"] = @benchmarkable bench_sync(field_data(materialize_kernel($separable).field))
  # The in-place twin (decision 90): the same pass into a StoredKernel that already exists, so the
  # difference from the rows above is the field-sized allocation alone.
  materialized = materialize_kernel(radial)
  group["materialize_kernel! radial | $tag"]    = @benchmarkable (materialize_kernel!($materialized, $radial); bench_sync(field_data($materialized.field)))
  group["materialize_kernel! separable | $tag"] = @benchmarkable (materialize_kernel!($materialized, $separable); bench_sync(field_data($materialized.field)))
  # Rebuilding a separable kernel in place, against the allocating builder it replaces: both are O(N)
  # per-axis work, so the difference is the three small allocations, not the trigonometry.
  translation_scratch = translation_kernel(m, offset)
  group["translation_kernel! | $tag"] = @benchmarkable bench_sync(translation_kernel!($translation_scratch, $m, $offset).factor_1)
  # The reciprocal that deconvolves: O(N) per axis for a separable kernel, never a field.
  group["inv separable | $tag"] = @benchmarkable bench_sync(inv($separable).factor_1)
end
