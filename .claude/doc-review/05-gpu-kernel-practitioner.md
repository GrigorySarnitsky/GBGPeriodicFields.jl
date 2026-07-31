# Review: GPU-kernel / performance practitioner

Reviewer stance: portable array-code (CUDA/ROCm/KernelAbstractions) practitioner, scrutinizing the
allocation-free contract, GPU portability (no scalar indexing, `similar`/`similar_field`), kernel
fusion claims, CPU/CUDA/ROCm backend parity, the memory-bound performance model, and precision
(Float32/Float64) as a studied axis — for internal consistency across the rendered site.

Overall the document is unusually careful with its numbers (many cross-checked figures — e.g. the
`materialize!` bandwidth arithmetic in finding (l), the loop-order speedup ratios in finding (b), the
NUFFT oversampling factor — multiply out exactly), which makes the handful of places where the
threading/allocation/performance story does *not* reconcile stand out as real gaps rather than noise.

---

## Finding 1 — `helmholtz_projection!`'s CPU-threading classification contradicts itself

**Type:** contradiction
**Severity:** major
**Confidence:** high

**Locations:**
- PAGE: architecture, §9 ("Performance model and CPU threading"): "Two operation families, however,
  are KA kernels on every backend — the gather/scatter transfer kernels (§10), and the radial shell
  binning (decisions 25, 34) — ... (`helmholtz_projection!` left this set when decision 40 gave it a
  gated loop twin, so what remains is exactly the atomic/irregular kernels — the exemption is
  structural, not historical)." — immediately followed, in the **same paragraph**, by: "The two kernels
  with disjoint writes — **the projection and the gather** — are bitwise-reproducible, and were
  measured to be so across 1, 2, 4 and 8 threads."
- PAGE: architecture, §13 decision log ("The reductions thread on a fixed tree..."): "Finally,
  `helmholtz_projection!` gains the decision-38-shape gated `::CPU` loop twin — bitwise-equal to its
  KernelAbstractions engine, verified — so **the policy-exempt set shrinks to the operations whose
  kernels are structurally atomic/irregular: the grid↔point transfer and the radial binning.** The
  exemption is now a principle, not a history."
- PAGE: testing, §7 ("Current coverage and known gaps"): "...and, separately, **the three
  `KernelAbstractions` kernels, which thread by KA's own partitioning rather than through `_assign!`
  and so cannot be checked by toggling `with_threading` at all**: the disjoint-write pair
  (`helmholtz_projection`, the gather) is asserted bitwise, including against a subprocess launched at
  a different thread count, while the two `Atomix` accumulators (the anterpolation scatter, the shell
  binning) are held to a tolerance..."

**Contradicts:** The §9 body text's own first sentence in the same paragraph, and decision 40's plain
statement, both say `helmholtz_projection!` **left** the "KA-partitions-every-backend, ignores
`with_threading`" bucket — it now has a gated CPU loop that *does* answer to `_use_threads`/
`with_threading` on a CPU array (only its device KA kernel is exempt). Two sentences later in the very
same §9 paragraph, and again in `testing.md` §7, `helmholtz_projection`/`the projection` is still
counted as one of the (now-supposedly-two-family) always-KA, `with_threading`-blind kernels. The axis
of disagreement: *does toggling `with_threading` change `helmholtz_projection!`'s CPU behavior or
not?* Per decision 40: yes (gated loop, like `gradient!`/`curl!`). Per the leftover sentences in §9 and
per `testing.md` §7: no ("cannot be checked... at all").

**Description:** This directly affects a GPU-kernel/threading reader's mental model of which ops are
reachable through the `with_threading` override and the serial-cutoff gate versus which always launch
via KA's own `nthreads()` partitioning. A contributor reading only `testing.md` (a design companion
explicitly meant to explain "how the tests are built") would conclude `helmholtz_projection!` cannot be
exercised via the `with_threading` toggle and would test it only via the cross-process `-t` comparison
— missing that decision 40 gave it a gated loop that the in-process toggle *does* reach. The `§9`
self-contradiction reads as an incompletely reconciled edit: the parenthetical noting
`helmholtz_projection!`'s departure was inserted at the first mention, but the enumeration a few
sentences later ("the projection and the gather") was not updated to match, and `testing.md`'s
description of "the three KernelAbstractions kernels" was not touched at all.

---

## Finding 2 — a ROCm-specific ("rocBLAS") fact is restated as a blanket "unavailable on GPU" claim

**Type:** contradiction
**Severity:** major
**Confidence:** medium-high

**Locations:**
- PAGE: architecture, §13 decision log ("Allocation-free in-place operators are a standing,
  exhaustively-enforced contract"): "...the mixed `inner(f, g)` of two distinct fields allocates an
  $O(N^2)$ kₓ-plane correction, because a `dot` over the strided plane view (which would fuse, no
  temporary) is **unsupported on the GPU (rocBLAS `dotc` has no strided method — verified on the
  device)**."
- PAGE: testing, §2 (`allocations.jl` description): "...and the documented allocators are bounded —
  ... and the spectral vector `inner`'s O(N²) Parseval-correction planes, **a strided-view `dot` being
  unavailable on GPU**; guards the GPU hot-loop discipline, decisions 24/25/34)."

**Contradicts:** The Architecture entry names the *specific, verified* evidence: rocBLAS's complex dot
(`dotc`) has no strided method, "verified on the device" (i.e., on the AMD/ROCm host). `testing.md`
restates the same fact with no backend qualifier at all — "unavailable on GPU" — generalizing a
vendor-specific limitation to every GPU backend the package supports, including CUDA (the package's
other first-class target: `Enteropia`/RTX 5070 Ti is used throughout `PERFORMANCE.md` for exactly this
kind of atomic/kernel comparison). cuBLAS's dot routines accept arbitrary strides via `incx`/`incy`, so
this O(N²)-materializing fallback plausibly exists only because of ROCm's specific `dotc` restriction —
it is not obviously a fundamental GPU limitation. The document is otherwise careful to keep CUDA and
ROCm claims separate (e.g. the Float64-atomic discussion in §4(d)/(n)/§6 is explicitly scoped to
"RDNA"/gfx1031/gfx1100, never stated as a blanket "GPU" fact), which makes the blanket phrasing here
look like an inconsistency in the document's own standard of rigor, not merely a stylistic
simplification.

**Description:** If CUDA's cuBLAS in fact handles the strided case, then (a) the "unavailable on GPU"
claim in `testing.md` is simply false for the CUDA backend, and (b) there may be an un-flagged missed
optimization: the package could be paying the O(N²) correction-plane materialization on CUDA
unnecessarily, purely because the fallback path was written for ROCm's limitation and never
re-examined per backend. Either way, a reader focused on the CUDA host (which this project treats as a
primary target, not an afterthought) is being told something the document's own more careful sibling
passage does not actually establish for that backend.

---

## Finding 3 — the loop-order table states a stale "0.75× (regression)" CPU figure the very next sentence disowns

**Type:** contradiction
**Severity:** minor
**Confidence:** medium

**Locations:**
- PAGE: performance, §4(b) ("Loop order — contiguous axis innermost (KEPT)"), the summary table:
  `speedup (x-inner / z-inner) | 1.6–1.7× | 3.9× (785→203 ms) | 0.75× (regression)` for the "CPU
  (Catmull–Rom / Lalescu)" column.
- Same finding, next paragraph: "Re-measured (2026-07-22), and x-inner now stands on CPU evidence too:
  decision 37 reopened this tiebreak because its cache justification dies in the CPU production band,
  so the A/B was repeated at 512³ `Float64`... — **and the old penalty does not reproduce there.** The
  z-inner nest gains only ~9–10% on the 4³ Catmull–Rom stencil and **loses 23% (serial; 5% at eight
  threads)** on the 8³ Lalescu stencil..."

**Contradicts:** The table's own CPU cell says "0.75× (regression)" as if it were the current,
representative figure; the prose immediately underneath states this specific number "does not
reproduce" and gives a materially different re-measurement (roughly 0.77–0.91× depending on stencil
and thread count, not the flat 0.75× the table shows). The table is never edited or annotated
"superseded" — a reader who scans only the table (a natural way to consume a benchmark section) walks
away with the disowned number.

**Description:** This is a presentation/staleness defect rather than a factual error per se — the
document does eventually clarify — but it sits inside the "What we have found" section, which is
exactly where a GPU/CPU kernel developer would go to look up a definitive per-platform number before
making a tuning decision. The fix is mechanical (mark the table cell superseded, or replace it with the
re-measured range) but the current state genuinely contradicts itself within one finding.

---

## Finding 4 — two different absolute-time/ratio figures given for the same `radial_spectrum` (7900 XTX vs 5070 Ti, Float64, 256³) benchmark

**Type:** contradiction
**Severity:** minor
**Confidence:** medium

**Locations:**
- PAGE: performance, §6 ("A representative slice..."): "`radial_spectrum` at 256³ is ≈12× faster on
  the 5070 Ti than the 7900 XTX in `Float32`, widening to **≈32× in `Float64` (92 → 2.9 ms)**; the
  extra `Float64` factor is the emulated-atomic penalty of §4(d)..."
- PAGE: performance, §7 ("Current coverage and known gaps"): "The refresh also re-confirmed the §6
  atomic-scatter contrast on the fused decision-34 kernels: `radial_spectrum` **vector** `Float64` 256³
  is **65.95 ms** on the 7900 XTX against **1.371 ms** on the 5070 Ti — **a ~48× CUDA lead** on what is
  now a pure scatter-add (its staging planes are gone, so the atomics are the whole story)."

**Contradicts:** Same nominal quantity (radial_spectrum, Float64, 256³, 7900 XTX vs 5070 Ti) reported
as 92 → 2.9 ms (~32×) in one place and 65.95 → 1.371 ms (~48×) in another, with neither absolute time
matching and the ratio itself moving by 50%. The document's own "run-to-run variance" caveat elsewhere
states jitter is "~10%" — both of these deltas (92→65.95 ms is −28%; 2.9→1.371 ms is −53%) exceed that
band, so this reads as a genuine re-measurement rather than noise. §7 frames itself as a
"re-confirm[ation]" of §6's *qualitative* contrast (CUDA atomics far outrunning RDNA3's) after decision
34 fused away `radial_spectrum`'s staging planes — which is a plausible mechanism for the numbers to
move (removing staging plausibly changes the AMD and NVIDIA times by different relative amounts) — but
§6 is never marked as the pre-decision-34 measurement, so the two numbers simply sit in the document as
if both were current.

**Description:** For a reader who cares about backend-parity numbers specifically (this hat's mandate),
having two live, materially different figures for what reads as the identical benchmark cell — one in
the headline "representative slice," one in the "known gaps" section — is confusing at minimum and
should be reconciled (either cross-reference explicitly, or update §6's inline number to match the
"re-confirmed" one).

---

## Finding 5 — PERFORMANCE.md's Helmholtz-projection benchmark numbers describe the pre-decision-40 CPU code path (KA `CPU()` backend), not the current one (gated loop)

**Type:** performance
**Severity:** minor
**Confidence:** low-medium

**Locations:**
- PAGE: performance, §4(j) ("A multi-output kernel beats broadcast recomputation — the one-pass
  Helmholtz projection"): "Measured on the 12700K... the fused-vs-three-broadcast ratio... **The KA
  launch allocates a small size-independent host-side bookkeeping (~1.5 KB serial, ~7 KB at four
  threads — task spawning)**, where the broadcast route allocated ~0.3 KB..."
- PAGE: architecture, §13 decision log ("The reductions thread on a fixed tree..."): "`helmholtz_projection!`
  gains the decision-38-shape **gated `::CPU` loop twin** — bitwise-equal to its KernelAbstractions
  engine, verified..."

**Contradicts (weakly — a currency gap, not a flat contradiction):** Finding (j) explicitly attributes
`helmholtz_projection!`'s CPU allocation profile to "**the KA launch**" with "task spawning" overhead —
language that matches the KernelAbstractions `CPU()` backend model (which, per §9, partitions by
`Threads.nthreads()` itself). Decision 40 (later in the append-only log) replaced that CPU path with a
"gated `::CPU` loop twin" — the same execution shape used by `gradient!`/`curl!`/`symmetric_gradient!`
after decision 38, which is a *slab-threaded `@simd` loop through the `_use_threads` gate*, not a KA
launch. Finding (j) was, as far as the document shows, never revisited after decision 40 to say whether
its "2.7–6.5×" speedup range and its "~1.5–7 KB task-spawning" allocation figures still describe the
current CPU implementation, or whether they are now historical (decision-32-era) numbers superseded by
a rewrite the document elsewhere treats as a real, benchmarked change (decision 38's rewrite of the
sibling ops is given fresh numbers post-rewrite; decision 40's twin for `helmholtz_projection!` is not).

**Description:** Flagging this at lower confidence because it requires inferring that decision 40's
CPU change would materially move finding (j)'s specific numbers — the document doesn't say so
explicitly either way. But given the document's own pattern (decision 38's CPU rewrite for the sibling
kernels *did* get fresh, dated benchmark numbers), the absence of an equivalent re-measurement note for
`helmholtz_projection!` after decision 40 is a coverage gap worth flagging for a hat centered on
"is the documented performance story internally consistent."

---

## Finding 6 — the numbered invariants (including invariant 6, "no scalar indexing") are cited dozens of times but never defined anywhere in the rendered document

**Type:** clarity
**Severity:** minor
**Confidence:** medium-high

**Locations:**
- PAGE: architecture, opening paragraph (the page's own self-containedness promise): "**This file is
  self-contained: every piece of notation — a mathematical symbol (in LaTeX) or a `code` identifier —
  is introduced in plain language at its first use**, the meaning stated before or in the same sentence
  as the symbol. So it reads top-to-bottom, and **each §13 decision-log entry reads on its own, without
  opening the source or another document.**"
- PAGE: architecture, §9: "...so **invariant 6** holds by dispatch, not discipline." (first occurrence
  in reading order; no gloss given at or before this point).
- PAGE: architecture, §13 decision log, repeatedly: "invariant 12" (×9), "invariant 1" (×6),
  "invariant 5" (×6), "invariant 3" (×3), "invariant 10" (×2), "invariant 2" (×3), "invariant 4",
  "invariant 8", "invariant 13" (×2) — none of these numbers are ever spelled out as a definition in
  the rendered document; each is used as if the reader already has the numbered list memorized.
- PAGE: performance, §3 (best practices bullet list): "No scalar indexing of device arrays
  (**invariant 6**) — a checked guarantee under `allowscalar(false)`..." — the closest thing to a
  gloss in the whole document, but it occurs on a *later* page than Architecture's first, unglossed use.

**Description:** This is squarely within the brief for this hat — "invariant 6" is the document's own
shorthand for exactly the property I was asked to scrutinize (no scalar indexing of device arrays), and
it is used as load-bearing justification ("holds by dispatch, not discipline") without ever being
stated. The page's own opening paragraph promises that "each §13 decision-log entry reads on its own,
without opening the source or another document" — yet dozens of decision-log entries lean on "invariant
N" numbers that are defined only in the (unpublished, per this review's scope) `CLAUDE.md`. A cold
reader of the rendered site has no way to look up what invariant 1, 2, 3, 4, 5, 6, 8, 10, 12, or 13
actually assert; they can only reconstruct approximate meanings from repeated contextual use. This
directly undercuts my ability (and any reader's) to verify precisely what GPU-portability guarantee
"invariant 6" is claimed to provide, versus what the code/tests actually check.

---

## Finding 7 — the "512³ (10⁶ points...)" re-measurement doesn't match the stated point density for the rest of §4

**Type:** math
**Severity:** nit
**Confidence:** low

**Locations:**
- PAGE: performance, §4 preamble: "Measured on the home AMD Radeon RX 6700 XT... and Intel i7-12700K
  (8 P-cores), `Float32`, **~1 point per 27 grid cells**. These are the cumulative results of the
  transfer-layer optimization work..."
- PAGE: performance, §4(b): "...so the A/B was repeated at 512³ `Float64` (**10⁶ points**, Ryzen
  9800X3D) — and the old penalty does not reproduce there."

**Description:** At the stated "~1 per 27" density, a 512³ = 134,217,728-cell grid would carry
≈4.97 × 10⁶ transfer points, not the "10⁶" cited for this specific re-measurement — roughly a 5×
discrepancy. This may simply be a different, unstated point count deliberately chosen for the
decision-37 CPU re-measurement (which already deviates from §4's stated default methodology by using
`Float64` and a different CPU), in which case the density change should arguably be called out the same
way the precision and CPU changes are; or it may be a loose/rounded figure not meant to track the ~1:27
ratio precisely. Low confidence and low severity, but flagged as a genuine numeric inconsistency between
a stated general parameter and a specific instance that doesn't restate it.

---

## Summary table

| # | Finding | Type | Severity | Confidence |
|---|---|---|---|---|
| 1 | `helmholtz_projection!` threading classification self-contradicts (§9 + testing.md vs decision 40) | contradiction | major | high |
| 2 | "unavailable on GPU" generalizes a rocBLAS-specific, ROCm-verified fact | contradiction | major | medium-high |
| 3 | Loop-order table's "0.75× (regression)" contradicted by the very next sentence | contradiction | minor | medium |
| 4 | Two different radial_spectrum XTX-vs-5070Ti Float64 256³ figures (32× vs 48×) | contradiction | minor | medium |
| 5 | Helmholtz-projection benchmark numbers not revisited after decision 40's CPU rewrite | performance | minor | low-medium |
| 6 | Numbered invariants (incl. invariant 6) cited but never defined in the rendered doc | clarity | minor | medium-high |
| 7 | "10⁶ points" at 512³ doesn't match the stated "~1 per 27" density | math | nit | low |

No overclaims of "zero-copy" were found. The allocation-free contract's documented-exception list
(`norm!`/`lpnorm`/`std`/`var`, `radial_correlation`, the mixed spectral `inner(f,g)`) is stated
consistently everywhere it appears, including the `dev!`-left-the-list update from decision 39
propagating correctly to every page that lists it — that part of the allocation story is in good shape.
