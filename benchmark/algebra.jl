# Field-algebra benchmarks: in-place forms (preallocated destination) so the timing isolates the
# fiberwise kernel, not allocation. A representative M2 + M3 cross-section.

function add_algebra!(group, AT, ::Type{T}, grid, tag) where {T}
  a = scalar_phys(AT, T, grid); b = scalar_phys(AT, T, grid); sdest = scalar_phys(AT, T, grid)
  u = vector_phys(AT, T, grid); v = vector_phys(AT, T, grid); vdest = vector_phys(AT, T, grid)
  A = tensor_phys(AT, T, grid)
  alpha = T(2); beta = T(3)
  group["add! scalar | $tag"]     = @benchmarkable (add!($sdest, $a, $b); bench_sync(field_data($sdest)))
  group["combine! vec | $tag"]    = @benchmarkable (combine!($vdest, $alpha, $u, $beta, $v); bench_sync(field_data($vdest)))
  group["dot! vec.vec | $tag"]    = @benchmarkable (dot!($sdest, $u, $v); bench_sync(field_data($sdest)))
  group["cross! | $tag"]          = @benchmarkable (cross!($vdest, $u, $v); bench_sync(field_data($vdest)))
  group["mul! tensor.vec | $tag"] = @benchmarkable (mul!($vdest, $A, $u); bench_sync(field_data($vdest)))
  group["norm! vec | $tag"]       = @benchmarkable (norm!($sdest, $u); bench_sync(field_data($sdest)))
  group["tr! tensor | $tag"]      = @benchmarkable (tr!($sdest, $A); bench_sync(field_data($sdest)))
  group["det! tensor | $tag"]     = @benchmarkable (det!($sdest, $A); bench_sync(field_data($sdest)))
  # map! (arbitrary φ) rides the same fused executor: map!(det, …) should track det! (the adapter is
  # register-only), and the multi-input form the corresponding named binary op.
  group["map!(det) tensor | $tag"] = @benchmarkable (map!(det, $sdest, $A); bench_sync(field_data($sdest)))
  group["map!(+) vec | $tag"]      = @benchmarkable (map!(bench_add, $vdest, $u, $v); bench_sync(field_data($vdest)))
  # Operand counts past the group of eight (decision 88). Eight operands take one pass, nine take two
  # and sixteen three, each later pass re-reading the partial sum from the destination. Against a fold
  # that read every operand once, the extra traffic is one destination read and write per extra pass,
  # so the three rows price what grouping costs. Sixteen scalar fields are 16 GiB at 512^3 Float64.
  operands = [scalar_phys(AT, T, grid) for _ in 1:16]
  for n in (8, 9, 16)
    arguments = (sdest, operands[1:n]...)
    group["add! scalar x$n | $tag"] = @benchmarkable (bench_call(add!, $arguments); bench_sync(field_data($sdest)))
  end
end

bench_add(a, b) = a + b     # named (not a closure) so the benchmark buffer stays stable across evals
