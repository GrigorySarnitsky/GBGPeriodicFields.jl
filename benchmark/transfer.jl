# Grid <-> point transfer benchmarks: interpolate! (gather) and anterpolate! (scatter, alpha=1,
# beta=0) across the stencil widths that matter (trilinear / Catmull-Rom / Lalescu 8-point). The
# transfer drivers synchronise internally, so no explicit bench_sync is needed.

function add_transfer!(group, AT, ::Type{T}, grid, tag) where {T}
  field = scalar_phys(AT, T, grid)
  points, q, _ = point_setup(AT, T, grid)
  out = interpolate(field, points, CatmullRom)   # allocate the matching output once, reuse
  for (label, scheme) in (("trilinear", LalescuSpline(0, 0)), ("CatmullRom", CatmullRom), ("Lalescu(3,3)", LalescuSpline(3, 3)))
    group["interpolate! $label | $tag"] = @benchmarkable interpolate!($out, $field, $points, $scheme)
    group["anterpolate! $label | $tag"] = @benchmarkable anterpolate!($field, $points, $q, $scheme, $(T(1)), $(T(0)))
  end
end
