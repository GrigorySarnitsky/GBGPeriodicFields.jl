# GPU-kernel practitioner — review findings

Hat: performance-focused GPU-kernel practitioner (CUDA/ROCm/KernelAbstractions, allocation and bandwidth discipline).

Scope read: Home, api overview, architecture (full, incl. §13 decision log), formalization/notation (skimmed), performance (full), testing (full), and spot checks of the Fields, DifferentialOperators, Convolution, Reductions API pages.

Overall note: this is an unusually self-consistent document set — nearly every numeric claim I cross-checked (kernel-composed speedups, exponential-kernel reuse ratios, subnormal cost multiplier, loop-order percentages, mapped-reduction CPU/GPU ratios) reproduced exactly across pages. The findings below are therefore mostly *tensions between a stated rule and a later exception*, or *staleness/incompleteness* rather than flat factual contradictions.

---

## Finding 1 — The "GPU wins" tiebreak rule is stated as unconditional, then explicitly not applied to the one case where it would matter

**Type:** contradiction
**Severity:** major
**Confidence:** medium

**Locations:**
- PAGE: performance, §1 Philosophy: *"where an optimization helps one platform and hurts the other — which happens, and is proven below — **the GPU wins across the range both can run**."*
- PAGE: performance, §4(c): *"On the GPU in-register ties in Float32 but is **≈6% slower in Float64** — and that lone reversal is a test-hardware artifact, not a production signal... **Kept in-register**; the arrays stay dropped."*

**Description:** §1 states the tiebreak rule as a flat policy with no stated exception. §4(c) then measures a real regression on the actually-owned GPU (RTX 5070 Ti) for the chosen implementation and keeps it anyway, reasoning that the *production* GPU (GH200, never benchmarked) would behave differently. That may well be the right engineering call, but it is a case where the measured GPU loses and the CPU-favoring option is kept — the opposite of what §1's rule says happens "across the range both can run." §1 is never updated to note this carve-out (measured-hardware-not-representative-of-production), so a reader who takes §1 at face value will be surprised by §4(c).

---

## Finding 2 — Invariant 6 ("GPU-portable by construction," "checked guarantee") has no enforcement in the default dev/CI flow

**Type:** clarity / overclaim
**Severity:** major
**Confidence:** medium

**Locations:**
- PAGE: architecture, "The invariants": *"The package is GPU-portable by construction: storage is a generic `AbstractArray`, no package method scalar-indexes a device array... (§9)."*
- PAGE: performance, §3: *"No scalar indexing of device arrays (invariant 6) — **a checked guarantee** under `allowscalar(false)` in both the test and benchmark GPU runs."*
- PAGE: testing, §5: *"GPU tests are **opt-in and separate** (not part of `Pkg.test()`)... a GPU backend is only ever a test dependency."*
- PAGE: testing, §6: *"CI... is manual-only... each commit is authored locally and the full matrix is run before pushing."*

**Description:** The language ("by construction," "checked guarantee," one of fourteen invariants that "constrain every change") implies a standing, always-on guarantee. The only mechanism that actually checks it (`allowscalar(false)` in `test/gpu/`) is opt-in, requires physical hardware, is excluded from `Pkg.test()`, and CI itself is manual-only (not push-triggered). So a scalar-indexing regression in ordinary CPU-only development can land, commit, and even reach a tagged release without anything in the described workflow catching it — the guarantee is real only when someone remembers to run GPU tests on a machine with a device. The docs never soften "checked guarantee" to reflect that conditionality.

---

## Finding 3 — A known CPU-specific 3× inefficiency is deferred on "GPU-first" grounds that a later decision (37) undercuts

**Type:** contradiction
**Severity:** minor
**Confidence:** medium

**Locations:**
- PAGE: performance, §4(k): *"the per-mode exponential costing more than the field read it saves — dramatically so on CPU, where `exp` is expensive and the broadcast re-evaluates it once per fiber component... it waits for a CPU-bound consumer (**the audits' consumer runs GPU-first**)."*
- PAGE: architecture, decision "The CPU path's performance target is one cluster node, not small problems": *"a single large CPU node, running the resolutions that exceed one GPU's memory... the CPU path does serve development and small tests — but... The role that does [set the tuning target] is the opposite of small."*

**Description:** The deferral of the exponential-kernel CPU hoist rests on "GPU-first" as if that settles CPU cost as unimportant. Decision 37 (recorded later in the same document) explicitly rejects that framing for the CPU path in general, reopening several other tiebreaks (loop order, pass-audit gaps) specifically because they were "close to free while a field is cache-resident and become pure DRAM traffic once it is not" at production CPU-node scale. The exponential-kernel CPU finding is never revisited under decision 37's lens, even though it is exactly the kind of per-fiber-component redundant work decision 37 says now matters.

---

## Finding 4 — The single largest cross-vendor GPU performance gap in the document (≈48×) traces to a missing standard optimization, flagged only as "recorded, not fixed"

**Type:** performance
**Severity:** minor
**Confidence:** medium

**Locations:**
- PAGE: performance, §4(n): *"workgroup-local bins on GPU — the same redesign's lever on the **~48× CUDA-over-ROCm `Float64` radial gap**... **recorded, not fixed**."*
- PAGE: performance, §6: *"`radial_spectrum` on a vector field at 256³ is ≈3.5× faster on the 5070 Ti than the 7900 XTX in `Float32`, widening to **≈48×** in `Float64`."*

**Description:** Not a contradiction — this is an honest disclosure — but worth flagging from a kernel-practitioner's expertise: every other reported vendor gap in the document is in the 1.5–4× band (bandwidth-ratio scale); this one is an order of magnitude larger and is explicitly attributed to a missing standard technique (per-workgroup/shared-memory pre-reduction before the global atomic scatter). Given the radial reductions are explicitly framed as a "diagnostic" (not hot-loop) cost elsewhere in the same document, the 48× figure risks being read as a fundamental vendor-hardware gap rather than what the doc's own root-cause analysis says it is: an addressable implementation gap. No roadmap item exists for it (contrast with the explicitly tracked "Deferred" list in architecture §13), so its priority is invisible to a reader skimming the roadmap.

---

## Finding 5 — "A CPU materialization is a GPU one" is stated as a blanket equivalence but the doc's own finding (j) shows backend-specific launch bookkeeping that a CPU `@allocated` run cannot see

**Type:** clarity
**Severity:** minor
**Confidence:** low

**Locations:**
- PAGE: architecture, decision "Allocation-free in-place operators are a standing, exhaustively-enforced contract": *"The operator code is generic over the array type, so a CPU materialization is a GPU one — the CPU is simply where it is visible."*
- PAGE: performance, §4(j): *"The KA launch allocates a small size-independent host-side bookkeeping (~1.5–7 KB, thread-count-dependent)... which the allocation audit's fraction-of-a-field threshold absorbs."*

**Description:** The blanket claim ("a CPU materialization is a GPU one") is the stated justification for why CPU-only `@allocated` auditing is sufficient proof of GPU allocation-freeness. Finding (j), in the same document, shows a class of allocation (KA launch/task-spawn bookkeeping) that is backend-specific in origin and is only *absorbed by a threshold*, not verified equal across backends by the CPU-only audit. This is a narrower, more defensible claim ("`similar`/broadcast-derived scratch is backend-symmetric") than the blanket sentence actually states, and the blanket sentence is repeated verbatim in several places (architecture decisions 25/26, testing §4) without the caveat.

---

## Finding 6 — Reductions API docstring for the mapped forms omits the later fixed-tree threading rewrite, describing an implementation detail that decision 40 superseded

**Type:** organization / staleness
**Severity:** nit
**Confidence:** low

**Locations:**
- PAGE: api / Reductions, `integral` mapped-form docstring: *"It gets there by different means on each, chosen internally: a vectorized blocked loop on a CPU, a single fused pass on a GPU."*
- PAGE: architecture, decision "The reductions thread on a fixed tree — bitwise thread-count-invariant": *"Every CPU reduction — ... and the whole mapped-form family — now reduces through one fixed midpoint tree: a binary recursion... its leaves as the existing pairwise-blocked `@simd` loops."*

**Description:** Not factually wrong (the blocked loop is still there, at the tree's leaves), but the docstring's "a vectorized blocked loop on a CPU" reads as the whole CPU story, when decision 40 wrapped it in a task-spawning binary-split tree specifically to make it bitwise thread-count-invariant — a property a GPU-kernel-practitioner reader would care about and that the docstring doesn't mention at all (not even a forward pointer to `ARCHITECTURE.md` §9). Per the doc's own documentation policy this level of internal-mechanism detail is deliberately excluded from function docstrings, so this is a low-severity completeness nit rather than a defect, but it means the API page alone slightly understates the CPU threading story relative to what architecture.md records as current.

---

## Not flagged, checked and found consistent (for the record)

- Every ratio in `exponential_convolve!`'s docstring (≈1.4×, ≈1.1×/1.7×, ≈1.5×/1.1×) matches performance §4(k)'s table exactly.
- The Float32 subnormal cost multiplier (~16×) in the docstring matches the measured 37.1/2.4 ≈ 15.5× in §4(m).
- The `helmholtz_projection!` docstring's aliasing and denominator ($a\cdot a$) description matches decisions 32/42/47 exactly, including the CPU/KA dual-kernel dispatch-guard story.
- The mapped-reduction CPU/GPU speedup figures ("roughly two and a half times on a CPU and a quarter on a GPU") match §4(i)'s table (2.5× and 1.26×) exactly.
- The x-inner loop-order percentages (512³ Zen 5: ~10% ahead / 23% behind) are quoted identically in both the decision log and §4(b).
