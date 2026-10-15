# Grid <-> point transfer benchmarks: interpolate! (gather) and anterpolate! (scatter, alpha=1,
# beta=0) across the stencil widths that matter (trilinear / Catmull-Rom / Lalescu 8-point). The
# transfer drivers synchronise internally — EXCEPT that NUFFT anterpolation synchronises its extract
# and then launches the final assignment before returning, so its GPU row omitted that write and could
# overlap it with the next evaluation. A benchmark must not depend on a driver's internal
# synchronisation anyway: assume nothing and sync the destination of every transfer row.

# `registry`, when given, records this tag's point set and a pristine copy of its coordinates, so
# `benchmark/gate.jl` can assert the invariant this class once broke: a row must not mutate state
# another row's SETUP captured. Nothing else reads it, and it is `nothing` in every measured run.
function add_transfer!(group, AT, ::Type{T}, grid, tag; registry = nothing) where {T}
  field = scalar_phys(AT, T, grid)
  points, q, _ = point_setup(AT, T, grid)
  registry === nothing || (registry[tag] = (points, copy(point_positions(points))))
  out = interpolate(field, points, CatmullRom)   # allocate the matching output once, reuse
  for (label, scheme) in (("trilinear", LalescuSpline(2; smoothness = 0)), ("CatmullRom", CatmullRom), ("Lalescu(3,3)", LalescuSpline(8; smoothness = 3)))
    group["interpolate! $label | $tag"] = @benchmarkable (interpolate!($out, $field, $points, $scheme); bench_sync(point_values($out)))
    group["anterpolate! $label | $tag"] = @benchmarkable (anterpolate!($field, $points, $q, $scheme, $(T(1)), $(T(0))); bench_sync(field_data($field)))
  end
  # The traversal order (decision 78): building one, and the same two verbs following it. The ordered rows
  # are the ones a consumer sees when it reuses positions across transfers, and the `point_traversal_order`
  # row is what that costs — the three belong together, because the option only pays when the build is
  # amortized over at least one transfer.
  visit_order = point_traversal_order(grid, points)
  # `.indices`: the builder returns the validated `PointTraversalOrder`, and `bench_sync` synchronizes on
  # an array. This row broke silently when the wrapper landed and the tiny-grid gate was not re-run —
  # the decision-60 class, caught by the next gate run.
  group["point_traversal_order | $tag"] = @benchmarkable (bench_sync(point_traversal_order($grid, $points).indices))
  # The in-place rebuild against the allocating build. The point of the row is not that it is faster
  # — it runs the same three kernels over the same points — but that a regression which reintroduced
  # a per-rebuild allocation would show here as a divergence between the two, on a device most of all.
  rebuild_scratch = PointTraversalOrderScratch(grid, points)
  group["point_traversal_order! | $tag"] =
    @benchmarkable (point_traversal_order!($visit_order, $grid, $points, $rebuild_scratch);
                    bench_sync(($visit_order).indices))
  group["interpolate! CatmullRom ordered | $tag"] =
    @benchmarkable (interpolate!($out, $field, $points, CatmullRom; traversal = $visit_order); bench_sync(point_values($out)))
  group["anterpolate! CatmullRom ordered | $tag"] =
    @benchmarkable (anterpolate!($field, $points, $q, CatmullRom, $(T(1)), $(T(0)); traversal = $visit_order); bench_sync(field_data($field)))
  # A VECTOR field, which is what a particle-tracking consumer actually gathers — every transfer row
  # above is scalar, so the case that matters most to the consumer had never been measured (noted by
  # the 2026-08-30 technique survey). It is also where the traversal order pays most, the field traffic
  # being three components against one coordinate triple, so the ordered pair is measured beside it.
  vector_field = vector_phys(AT, T, grid)
  vector_out = interpolate(vector_field, points, CatmullRom)
  vector_q = interpolate(vector_field, points, CatmullRom)
  group["interpolate! CatmullRom vector | $tag"] =
    @benchmarkable (interpolate!($vector_out, $vector_field, $points, CatmullRom); bench_sync(point_values($vector_out)))
  group["interpolate! CatmullRom vector ordered | $tag"] =
    @benchmarkable (interpolate!($vector_out, $vector_field, $points, CatmullRom; traversal = $visit_order); bench_sync(point_values($vector_out)))
  group["anterpolate! CatmullRom vector | $tag"] =
    @benchmarkable (anterpolate!($vector_field, $points, $vector_q, CatmullRom, $(T(1)), $(T(0))); bench_sync(field_data($vector_field)))
  group["anterpolate! CatmullRom vector ordered | $tag"] =
    @benchmarkable (anterpolate!($vector_field, $points, $vector_q, CatmullRom, $(T(1)), $(T(0)); traversal = $visit_order); bench_sync(field_data($vector_field)))

  # Spectral-domain transfer: the fast windowed NUFFT (one plan built once). DirectDFT is the exact
  # O(N·M) oracle — its cost is quadratic in the work and not a regression target, so it is not swept.
  spectral = scalar_spec(AT, T, grid)
  nufft = NUFFT(spectral; tolerance = 1e-6)            # w = 8 stencil — a representative accuracy
  spectral_out = interpolate(spectral, points, nufft)
  group["interpolate! NUFFT | $tag"] = @benchmarkable (interpolate!($spectral_out, $spectral, $points, $nufft); bench_sync(point_values($spectral_out)))
  group["anterpolate! NUFFT | $tag"] = @benchmarkable (anterpolate!($spectral, $points, $q, $nufft, $(T(1)), $(T(0))); bench_sync(field_data($spectral)))

  # Base-space motion (decision 73): the trajectory-update primitives beside the transfer they feed.
  # Three terms is the AB3 shape the fused n-term form exists for; the torus row prices the wrap
  # fused into the same pass, and `wrap!` alone prices the canonicalization. All are O(M) streaming
  # over (M, 3) arrays — bandwidth-trivial next to a gather, which is the point of measuring them:
  # the rows document that the boundary crossing costs nothing.
  #
  # These rows MUTATE their point set in place, and tune!/run execute every row in the group —
  # so they take their OWN copy of the positions. Sharing `points` poisoned the ordered rows
  # above: `visit_order` describes the initial positions, and ~10^4 samples of drift at c = 0.01
  # left it a valid permutation with no locality, so every archived ordered row up to 2026-08-31
  # timed a stale order (1.75 ms where a fresh order gives 0.49 ms — PERFORMANCE.md finding (ak)).
  # The unordered rows never noticed: drifted-then-wrapped positions are as uniform as fresh ones.
  motion_points = PointSet(copy(point_positions(points)))
  npart = npoints(motion_points)
  v1 = VectorPointValues(AT(randn(T, npart, 3)))
  v2 = VectorPointValues(AT(randn(T, npart, 3)))
  v3 = VectorPointValues(AT(randn(T, npart, 3)))
  c = T(0.01)
  group["displace! 1-term | $tag"] = @benchmarkable (displace!($motion_points, ($c, $v1)); bench_sync(point_positions($motion_points)))
  group["displace! 3-term | $tag"] = @benchmarkable (displace!($motion_points, ($c, $v1), ($c, $v2), ($c, $v3)); bench_sync(point_positions($motion_points)))
  group["displace! 3-term torus | $tag"] = @benchmarkable (displace!($motion_points, $grid, ($c, $v1), ($c, $v2), ($c, $v3)); bench_sync(point_positions($motion_points)))
  group["wrap! | $tag"] = @benchmarkable (wrap!($motion_points, $grid); bench_sync(point_positions($motion_points)))
  # Past the group of eight terms (decision 88): eight terms are one pass, nine two, thirty-three five,
  # each later pass re-reading the positions it continues from.
  sections = [VectorPointValues(AT(randn(T, npart, 3))) for _ in 1:33]
  for n in (8, 9, 33)
    arguments = (motion_points, ((c, sections[k]) for k in 1:n)...)
    group["displace! $(n)-term | $tag"] = @benchmarkable (bench_call(displace!, $arguments); bench_sync(point_positions($motion_points)))
  end
end
