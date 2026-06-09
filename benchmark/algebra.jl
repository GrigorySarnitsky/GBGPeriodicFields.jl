# Field-algebra benchmarks: in-place forms (preallocated destination) so the timing isolates the
# fiberwise kernel, not allocation. A representative M2 + M3 cross-section.

function add_algebra!(group, AT, ::Type{T}, grid, tag) where {T}
  a = scalar_phys(AT, T, grid); b = scalar_phys(AT, T, grid); sdest = scalar_phys(AT, T, grid)
  u = vector_phys(AT, T, grid); v = vector_phys(AT, T, grid); vdest = vector_phys(AT, T, grid)
  A = tensor_phys(AT, T, grid)
  group["add! scalar | $tag"]     = @benchmarkable (add!($sdest, $a, $b); bench_sync(field_data($sdest)))
  group["dot! vec.vec | $tag"]    = @benchmarkable (dot!($sdest, $u, $v); bench_sync(field_data($sdest)))
  group["cross! | $tag"]          = @benchmarkable (cross!($vdest, $u, $v); bench_sync(field_data($vdest)))
  group["mul! tensor.vec | $tag"] = @benchmarkable (mul!($vdest, $A, $u); bench_sync(field_data($vdest)))
  group["norm! vec | $tag"]       = @benchmarkable (norm!($sdest, $u); bench_sync(field_data($sdest)))
end
