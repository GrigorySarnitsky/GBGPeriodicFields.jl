# Moving Fourier modes between grid resolutions: `embed_modes!` and `extract_modes!` (decision 85).
#
# The class exists because these rows measure something no other class does: an operation whose cost
# is set by a field the caller does NOT pass as its destination. Both verbs walk the coarse field, so
# a row's time should follow the coarse grid and barely move when the fine grid grows — and the
# failure they exist to prevent, a pass over the fine field, would show up here as a row that tracks
# the sweep's grid size instead. That is the whole reading of this class, so the coarse grid is held
# at a fixed small size while the swept `grid` is the fine one.
#
# The ratio is a real axis, not a detail: a forcing on a coarse block of a large run has a ratio of
# tens, while a restart from a coarser run has a ratio of two. Two ratios are swept per lane, the
# fixed coarse grid giving the first and a half-sized coarse grid the second.

function add_resolution!(group, AT, ::Type{T}, grid, tag) where {T}
  layout = RealFourierLayout()
  # A fixed small block, as a forcing or an Euler-forced low band would be, and a half-sized coarse
  # grid, as a restart from a coarser run would be. Both are clamped to stay coarser than the sweep's
  # grid on every axis, since the operation refuses anything else.
  block_size = map(n -> min(16, n ÷ 2), grid.grid_size)
  half_size = map(n -> max(2, n ÷ 2), grid.grid_size)

  fine_scalar = ScalarFieldSpectral(AT, grid; layout)
  fine_vector = VectorFieldSpectral(AT, grid; layout)
  fill!(field_data(fine_scalar), 0)
  fill!(field_data(fine_vector), 0)

  for (label, coarse_size) in (("block", block_size), ("half", half_size))
    all(coarse_size .< grid.grid_size) || continue
    coarse_grid = Grid3D(coarse_size, grid.domain_size)
    coarse_scalar = ScalarFieldSpectral(AT, coarse_grid; layout)
    coarse_vector = VectorFieldSpectral(AT, coarse_grid; layout)
    fill!(field_data(coarse_scalar), 0)
    fill!(field_data(coarse_vector), 0)

    group["embed_modes! scalar $label | $tag"] =
      @benchmarkable (embed_modes!($fine_scalar, $coarse_scalar); bench_sync(field_data($fine_scalar)))
    group["embed_modes! vector $label | $tag"] =
      @benchmarkable (embed_modes!($fine_vector, $coarse_vector); bench_sync(field_data($fine_vector)))
    group["extract_modes! scalar $label | $tag"] =
      @benchmarkable (extract_modes!($coarse_scalar, $fine_scalar); bench_sync(field_data($coarse_scalar)))
    group["extract_modes! vector $label | $tag"] =
      @benchmarkable (extract_modes!($coarse_vector, $fine_vector); bench_sync(field_data($coarse_vector)))
    # The accumulating arity reads the destination's shared modes as well, which is the arity a
    # forcing uses every stage; swept once, on the block ratio that names that use.
    label == "block" || continue
    group["embed_modes! vector accumulate $label | $tag"] =
      @benchmarkable (embed_modes!($fine_vector, $coarse_vector, $(T(0.5)), $(one(T))); bench_sync(field_data($fine_vector)))
  end
end
