# Grid <-> point transfer benchmarks: interpolate! (gather) and anterpolate! (scatter, alpha=1,
# beta=0) across the stencil widths that matter (trilinear / Catmull-Rom / Lalescu 8-point). The
# transfer drivers synchronise internally — EXCEPT that NUFFT anterpolation synchronises its extract
# and then launches the final assignment before returning, so its GPU row omitted that write and could
# overlap it with the next evaluation. A benchmark must not depend on a driver's internal
# synchronisation anyway: assume nothing and sync the destination of every transfer row.

function add_transfer!(group, AT, ::Type{T}, grid, tag) where {T}
  field = scalar_phys(AT, T, grid)
  points, q, _ = point_setup(AT, T, grid)
  out = interpolate(field, points, CatmullRom)   # allocate the matching output once, reuse
  for (label, scheme) in (("trilinear", LalescuSpline(0, 0)), ("CatmullRom", CatmullRom), ("Lalescu(3,3)", LalescuSpline(3, 3)))
    group["interpolate! $label | $tag"] = @benchmarkable (interpolate!($out, $field, $points, $scheme); bench_sync(point_values($out)))
    group["anterpolate! $label | $tag"] = @benchmarkable (anterpolate!($field, $points, $q, $scheme, $(T(1)), $(T(0))); bench_sync(field_data($field)))
  end
  # Spectral-domain transfer: the fast windowed NUFFT (one plan built once). DirectDFT is the exact
  # O(N·M) oracle — its cost is quadratic in the work and not a regression target, so it is not swept.
  spectral = scalar_spec(AT, T, grid)
  nufft = NUFFT(spectral; tol = 1e-6)            # w = 8 stencil — a representative accuracy
  spectral_out = interpolate(spectral, points, nufft)
  group["interpolate! NUFFT | $tag"] = @benchmarkable (interpolate!($spectral_out, $spectral, $points, $nufft); bench_sync(point_values($spectral_out)))
  group["anterpolate! NUFFT | $tag"] = @benchmarkable (anterpolate!($spectral, $points, $q, $nufft, $(T(1)), $(T(0))); bench_sync(field_data($spectral)))

  # Base-space motion (decision 73): the trajectory-update primitives beside the transfer they feed.
  # Three terms is the AB3 shape the fused n-term form exists for; the torus row prices the wrap
  # fused into the same pass, and `wrap!` alone prices the canonicalization. All are O(M) streaming
  # over (M, 3) arrays — bandwidth-trivial next to a gather, which is the point of measuring them:
  # the rows document that the boundary crossing costs nothing.
  npart = npoints(points)
  v1 = VectorPointValues(AT(randn(T, npart, 3)))
  v2 = VectorPointValues(AT(randn(T, npart, 3)))
  v3 = VectorPointValues(AT(randn(T, npart, 3)))
  c = T(0.01)
  group["displace! 1-term | $tag"] = @benchmarkable (displace!($points, ($c, $v1)); bench_sync(point_coordinates($points)))
  group["displace! 3-term | $tag"] = @benchmarkable (displace!($points, ($c, $v1), ($c, $v2), ($c, $v3)); bench_sync(point_coordinates($points)))
  group["displace! 3-term torus | $tag"] = @benchmarkable (displace!($points, $grid, ($c, $v1), ($c, $v2), ($c, $v3)); bench_sync(point_coordinates($points)))
  group["wrap! | $tag"] = @benchmarkable (wrap!($points, $grid); bench_sync(point_coordinates($points)))
end
