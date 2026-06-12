# L²/measure reduction benchmarks: base reductions that collapse a section to a scalar / fiber value
# (docs/PERFORMANCE.md, docs/ARCHITECTURE.md decision 18). These are bandwidth-bound streaming
# reductions (sum / dot / maximum). Their host scalar/fiber result forces GPU completion, so — unlike
# the in-place field kernels — no `bench_sync` is needed for the GPU timing to be honest.
#
# A representative cross-section across the cost profiles: sum-based (integral/mean), dot-based
# (inner/l2norm), the allocate-then-reduce path (lpnorm via the pointwise norm), and a plain reduce
# (maximum).

function add_reductions!(group, AT, ::Type{T}, grid, tag) where {T}
  s = scalar_phys(AT, T, grid)
  u = vector_phys(AT, T, grid); v = vector_phys(AT, T, grid)
  us = vector_spec(AT, T, grid); vs = vector_spec(AT, T, grid)
  m = FieldSpectralMultipliers(us)
  correlation_plans = plans_for(u, AT, T, grid)
  group["integral scalar | $tag"] = @benchmarkable integral($s)
  group["mean vector | $tag"]     = @benchmarkable mean($u)            # fiber-valued (sum over base + copy)
  group["inner vec.vec | $tag"]   = @benchmarkable inner($u, $v)       # the energy workhorse (dot)
  group["l2norm vec | $tag"]      = @benchmarkable l2norm($u)
  group["lpnorm vec Inf | $tag"]  = @benchmarkable lpnorm($u, Inf)     # norm(u) alloc + sup
  group["maximum scalar | $tag"]  = @benchmarkable maximum($s)
  group["inner spectral | $tag"]  = @benchmarkable inner($us, $vs)     # Parseval: dot + the kₓ=0/Nyquist planes
  group["radial_spectrum vec | $tag"] = @benchmarkable radial_spectrum($us, $m)   # shell-resolved inner (per-shell masked sums)
  group["radial_correlation vec | $tag"] = @benchmarkable radial_correlation($us, $correlation_plans)  # Wiener–Khinchin: inverse rfft + shell average
end
