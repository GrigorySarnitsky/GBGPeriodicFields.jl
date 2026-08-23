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
  us = vector_spec(AT, T, grid); vs = vector_spec(AT, T, grid); ss = scalar_spec(AT, T, grid)
  m = FieldSpectralMultipliers(us)
  # A stored |k|² weight, which is what this row has always measured: `radial_kernel(identity, …)` is
  # the |k|² symbol since decision 60 removed the materializing builder, and `materialize_kernel` puts
  # it back in the stored class so the measurement — and its frozen baseline — is unchanged.
  weight = materialize_kernel(radial_kernel(identity, m))
  correlation_plans = plans_for(u, AT, T, grid)
  group["integral scalar | $tag"] = @benchmarkable integral($s)
  group["mean vector | $tag"]     = @benchmarkable mean($u)            # fiber-valued (sum over base + copy)
  group["inner vec.vec | $tag"]   = @benchmarkable inner($u, $v)       # the energy workhorse (dot)
  group["l2norm vec | $tag"]      = @benchmarkable l2norm($u)
  group["lpnorm vec Inf | $tag"]  = @benchmarkable lpnorm($u, Inf)     # norm(u) alloc + sup
  group["maximum scalar | $tag"]  = @benchmarkable maximum($s)
  # The one reduction with a fiber-valued result above R = 0: it streams the vector field twice (a
  # mean, then the centred outer product) and accumulates nine numbers, so it prices the second
  # moment against the first that `mean vector` above measures.
  group["cov vector | $tag"]      = @benchmarkable cov($u)
  # Scalar-only by decision 49, and available in both representations: the physical form streams the
  # field twice (mean, then centred squares) while the spectral form is Parseval's ⟨f,f⟩ − mean², so
  # the pair prices what skipping the transform is worth.
  group["var scalar | $tag"]          = @benchmarkable var($s)
  group["var spectral scalar | $tag"] = @benchmarkable var($ss)
  # The reality check (decision 71). It belongs beside the diagnostics rather than the measure
  # reductions: it touches one or two PLANES, not the volume, so its row exists to show that
  # O(N^2) shape against the O(N^3) rows around it rather than to be compared with them.
  # Three weights fused into one traversal (decision 72) against the three separate calls it replaces:
  # the pair of rows IS the claim, so they sit together.
  wk1 = spectral_cutoff(m, T(3)); wk2 = radial_kernel(identity, m); wk3 = spectral_band(m, T(1), T(2))
  group["weighted_inner x3 separate | $tag"] =
    @benchmarkable (weighted_inner($us, $wk1), weighted_inner($us, $wk2), weighted_inner($us, $wk3))
  group["weighted_inner x3 fused | $tag"] = @benchmarkable weighted_inner($us, ($wk1, $wk2, $wk3))
  group["reality_residual scalar | $tag"] = @benchmarkable reality_residual($ss)
  group["reality_residual vector | $tag"] = @benchmarkable reality_residual($us)
  group["inner spectral | $tag"]  = @benchmarkable inner($us, $vs)     # Parseval: dot + the kₓ=0/Nyquist planes
  group["weighted_inner vec | $tag"]     = @benchmarkable weighted_inner($us, $weight)       # fused ⟨f, |k|²·f⟩ (no filtered field)
  group["weighted_inner vec.vec | $tag"] = @benchmarkable weighted_inner($us, $vs, $weight)  # mixed ⟨f, |k|²·g⟩
  group["integral spectral vec | $tag"] = @benchmarkable integral($us) # zero-mode read: O(1) DC coefficient, no transform
  group["mean spectral vec | $tag"]     = @benchmarkable mean($us)
  group["radial_spectrum vec | $tag"] = @benchmarkable radial_spectrum($us, $m)   # shell-resolved inner (scatter-add shell binning, decision 25)
  group["radial_correlation vec | $tag"] = @benchmarkable radial_correlation($us, $correlation_plans)  # Wiener–Khinchin: inverse rfft + shell average
  group["co-spectrum vec.vec | $tag"] = @benchmarkable radial_spectrum($us, $vs, $m)   # cross-power: same binning, Re(f̂·conj ĝ) density
  group["cross-correlation vec.vec | $tag"] = @benchmarkable radial_correlation($us, $vs, $correlation_plans)  # cross-corr: inverse rfft of conj(f̂)·ĝ

  # Mapped forms: one fused pass that gathers the fiber per base point, against the two-pass spellings
  # they replace. `maximum(norm, u)` pairs directly with `lpnorm vec Inf` above (same quantity, one
  # materializing a magnitude section and one not), so the two rows read as an A/B.
  A = tensor_phys(AT, T, grid)
  group["maximum(norm) vec | $tag"] = @benchmarkable maximum(norm, $u)   # fused peer of lpnorm(u, Inf)
  group["mean(norm) vec | $tag"]    = @benchmarkable mean(norm, $u)
  group["mean(det) tensor | $tag"]  = @benchmarkable mean(det, $A)       # cubic fiber invariant, no det field
  group["mean(tr) tensor | $tag"]   = @benchmarkable mean(tr, $A)
end
