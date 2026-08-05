# GPU-kernel practitioner — review findings

Hat: performance-focused GPU-kernel practitioner (portable CUDA/ROCm/KernelAbstractions array code,
allocation and bandwidth discipline).

---

## Finding 1 — `FieldTransformPlans` docstring's FFT mis-plan ratio does not match the Performance page's own measured table for the same finding

**Type:** contradiction (math/numbers) · **Severity:** major · **Confidence:** high

**Locations:**
- PAGE `api / Fields`, `FieldTransformPlans` docstring: *"measured on a Zen 5 desktop, the `Float32`
  transforms ran **3.4–5.4× slower** than a timed plan at $256^3$, ... in both directions and **at
  every thread count**."*
- PAGE `performance`, §4 finding (h) table (same Zen 5 / Ryzen 9800X3D measurement):
  `threads 1 → 5.1×/5.0×`, `threads 4 → 3.4×/3.6×`, `threads 8 → **2.3×/2.6×**`.

**Description:** The docstring's claimed range (3.4×–5.4×) is supposed to hold "at every thread
count," but the Performance page's own table for this exact finding shows the `t=8` ratios (2.3×,
2.6×) falling *below* the docstring's stated 3.4× floor, and no table entry reaches the docstring's
5.4× ceiling (the table's maximum is 5.1×). Either the docstring's range is stale/wrong or the table
is; as written the two pages report different numbers for the same benchmark.

---

## Finding 2 — `weighted_inner`'s "comparable to one spectral `inner`" cost claim omits that `inner` is threaded and `weighted_inner` is not

**Type:** contradiction (performance model) · **Severity:** major · **Confidence:** medium

**Locations:**
- PAGE `api / Reductions`, `weighted_inner` docstring: *"the cost is a single weighted pass over the
  coefficients — **comparable to one spectral `inner`**."*
- PAGE `architecture`, decision log (the fixed-tree reductions entry): *"Every CPU reduction —
  `inner` ... now reduces through one fixed midpoint tree ... **`weighted_inner` stays serial for
  now**: its coefficient is the lazy cartesian $|k|^2$, the finding-(k) class, deferred."*

**Description:** After decision 40, `inner` (including its spectral Parseval form) runs on the
multi-threaded fixed-tree reduction, while `weighted_inner` explicitly does not. On the CPU
production-node path the docs themselves emphasize (the 128/256-core cluster node of decision 37),
this is not a minor detail: `inner` scales with threads and `weighted_inner` does not, so the two
stop being "comparable" in cost exactly on the platform the docs say the CPU path is tuned for. The
`weighted_inner` docstring gives no such caveat.

---

## Finding 3 — A decision-log claim that "nothing that worked before needs a wrapper" is contradicted by the current rendered API, and the supersede note doesn't say so

**Type:** contradiction / staleness · **Severity:** major · **Confidence:** medium

**Locations:**
- PAGE `architecture`, decision log, the `StoredKernel` entry (2026-07-30): *"Application is
  untouched: **the union still accepts a bare field everywhere a kernel is taken, so nothing that
  worked before needs a wrapper**."* (later self-annotated: *"(Superseded by decision 60, which made
  exactly that move: `SpectralKernel` is now an abstract supertype ... so the union this entry
  reasons about no longer exists.)"*)
- PAGE `api / Convolution`, module docstring (current): *"**A kernel is not a field.** ... `StoredKernel`
  ... wraps a `ScalarFieldSpectral`, which is how a consumer declares that those coefficients are
  playing the kernel role rather than being a field."* — repeated verbatim later on the same page:
  *"A field in spectral representation is not a kernel. ... **Wrap the field in a `StoredKernel`** to
  declare the role."*

**Description:** Once the union became an abstract-type hierarchy (decision 60), a bare
`ScalarFieldSpectral` no longer satisfies `kernel::SpectralKernel{T}` — the current API page requires
explicit `StoredKernel(f)` wrapping. The July-30 entry's specific claim ("nothing that worked before
needs a wrapper") is therefore now false, but the self-correcting note attached to that entry only
says the *union* no longer exists — it does not flag that the wrapper-optionality claim itself has
been reversed. A reader who stops at the supersede pointer, rather than cross-checking the
Convolution page, would come away believing bare fields still work unwrapped.

---

## Finding 4 — Performance page's "~10–14×" GPU-vs-4-thread-CPU summary doesn't match its own table (3.5×–27.1×)

**Type:** clarity / imprecise summary · **Severity:** minor · **Confidence:** medium

**Locations:**
- PAGE `performance`, §6, representative table: `GPU vs -t4` column values `6.6×, 11.4×, 3.5×, 7.7×,
  12.6×, 27.1×`.
- Same page, immediately after: *"the GPU leads the 4-thread CPU by **~10–14×** ... widest for the
  light/parallel ops and narrowing toward the bandwidth ratio for the heavy streaming ones."*

**Description:** Three of the six listed operations (`laplacian!` 3.5×, `to_spectral` 6.6×,
`interpolate!` Catmull–Rom 7.7×) sit well below the claimed "~10–14×" range, and one (`anterpolate!`
27.1×) sits well above it. The qualifying clause ("widest for light ops, narrowing for heavy
streaming") gestures at the spread but the headline number itself is not a fair midpoint or median of
the six values shown immediately above it (median ≈ 9.55×, and the range spans nearly an order of
magnitude).

---

## Finding 5 — The RX 7900 XTX vs RTX 5070 Ti `radial_spectrum` Float64 comparison is quoted twice with slightly different numbers

**Type:** contradiction (minor numeric drift) · **Severity:** nit · **Confidence:** low

**Locations:**
- PAGE `architecture`, decision log (shell-space primitives entry): *"`radial_spectrum` on a vector
  field at 256³ is ≈3.5× faster on the 5070 Ti than the 7900 XTX in Float32, widening to **≈49×** in
  Float64 (**67.1 → 1.38 ms**)."*
- PAGE `performance`, §7 gaps (the "Done 2026-07-21" refresh note): *"`radial_spectrum` vector `Float64`
  256³ is **65.95 ms** on the 7900 XTX against **1.371 ms** on the 5070 Ti — a **~48×** CUDA lead."*

**Description:** Both citations describe the same op/size/precision/GPU pair but report different
absolute times (67.1 vs 65.95 ms; 1.38 vs 1.371 ms) and a different ratio (49× vs 48×). The doc's own
`PERFORMANCE.md` §7 "run-to-run variance" note says results carry ~10% jitter and are "indicative
magnitudes, not contract values," which likely explains this — the two entries are probably two
different sweep runs — but neither passage flags that it is a re-measurement of a figure quoted
elsewhere, so a reader cross-referencing them sees an unexplained (if small) discrepancy in what looks
like a single reference statistic.

---

## Summary

No violation of invariant 6 (no scalar indexing of device arrays), no case where an operation is
documented as GPU-portable while another page admits it is not (the one genuine backend-capability gap
— rocBLAS `dotc` lacking a strided method, forcing the mixed spectral `inner(f,g)` to materialize its
Parseval correction planes — is consistently and honestly documented everywhere it appears), and no
"allocation-free"/"zero-copy" overclaim that the docs elsewhere contradict. The findings above are
concentrated in two classes: (a) specific performance numbers quoted in more than one place that don't
quite agree (Findings 1, 4, 5), and (b) a performance/API claim that was true when written but has been
overtaken by a later decision without the later decision's note fully retracting it (Findings 2, 3).
