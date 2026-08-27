RANGE: d03a2e9c..HEAD

## Finding 1

**Title:** FORMALIZATION says FieldTransformPlans is determined by its tensor order

**Verdict:** HONORED

**Evidence:** `docs/FORMALIZATION.md` (Storage families section) previously read: "It is
nonetheless determined by data it already carries — the grid, the layout, its element type and its
tensor order — so the rebuild needs no argument". The diff removes "and its tensor order", now
reading "the grid, the layout and its element type", which matches decision 76's
no-tensor-order-carried plans and the `Val(0)` witness construction. Confirmed the phrase does not
recur: `grep -n "tensor order" docs/*.md | grep -i "plan\|FieldTransformPlans"` returns only decision
76's own log entry (`ARCHITECTURE.md:3975`) and the (correct, complementary) TESTING §4 axis-18 entry
saying plans "now carry no tensor order" — no contradicting instance remains anywhere in the docs.

**class_surfaces:** The finding names one location only ("docs/FORMALIZATION.md, Storage families")
and does not itself point to sibling surfaces (no f/f! pair, no parallel doc page named). A grep
sweep for the same claim elsewhere (`FieldTransformPlans` + "tensor order" co-occurring) turns up
nothing contradictory — the class as stated is a single sentence and it is fixed. Treated as fully
swept.

---

## Finding 2

**Title:** No FORMALIZATION entry for reality_residual (decision 71)

**Verdict:** HONORED

**Evidence:** `docs/FORMALIZATION.md` gains a new block "**The reality condition (decision 71).**"
(inserted after the transform-scratch-arity paragraph, before the "Fiberwise algebra" section
header): states the Hermitian condition, the self-conjugate-plane restriction, the
`reality_residual` formula as a `math` block, its report-never-repair property, and its `O(N^2)` vs
`O(N^3 log N)` cost framing. It closes with `**Backs** [Architecture](architecture.md) §4 ...`
`**Checked by** test/fields.jl — ... and test/fieldalgebra.jl (the constant/zero-mode invariant)`,
completing the prose ↔ formalization ↔ test chain the finding says was broken. `test/fields.jl` does
carry a `reality_residual` testset (confirmed via TESTING.md's own updated description: "an
elementwise oracle written from the definition, over both element types, tensor orders 0/1/2, permuted
folds and an odd folded axis ... plus the pair-consistency property, the self-paired corners").

**class_surfaces:** The finding names one target ("docs/FORMALIZATION.md") for one operation
(`reality_residual`, decision 71) — no sibling docstring or second page is implied by the finding's
own text. The entry added is exactly that one typed statement with its test link. Fully swept as
scoped.

---

## Finding 3

**Title:** No FORMALIZATION entry for the tuple weighted_inner fusion identity (decision 72)

**Verdict:** HONORED

**Evidence:** `docs/FORMALIZATION.md`'s existing `weighted_inner` paragraph gains: "Given a **tuple**
of weights it answers all of them in one traversal, and the identity that licenses the fusion is that
each answer is the one the separate call would give:" followed by a `math` block giving
`weighted_inner(f, (w_1,...,w_n))_j = weighted_inner(f, w_j)`, then "**bitwise**, not merely to
roundoff — the coefficient reads are shared while each weight is still evaluated per mode, so no
summation order changes (decision 72)." This is exactly the missing tuple-form identity the finding
names, typed and reasoned about (why it is bitwise, not merely close). `test/reductions.jl` carries a
`@testset "weighted_inner over a tuple of weights ($T)"` (line 771) exercising a heterogeneous tuple
of kernel storage classes, so the entry is test-linked in substance even though the final "Checked
by" sentence for the whole reductions block was not separately re-worded to name the tuple case by
name.

**class_surfaces:** The finding names one target ("docs/FORMALIZATION.md, weighted_inner") for one
identity (decision 72's tuple fusion) — no sibling page or docstring is implied. Fully swept as
scoped.

---

## Finding 4

**Title:** TESTING §4 coverage-axes list has no entry for decision 76's component-offset alignment

**Verdict:** HONORED

**Evidence:** `docs/TESTING.md` §4's axis list gains a new numbered entry, "18. **component-offset
alignment**, per FFT backend (decision 76)." — explains the offset-alignment hazard, the
per-component-buffer FFTW `UNALIGNED` behaviour on host, the cuFFT odd-grid behaviour on device, and
names the suite lane: "`test/fields.jl` carries the lane — every rank over `(8,8,8)`, `(8,7,6)`,
`(7,5,3)` and `(9,9,9)`, plus the predicate itself asserted directly — and the GPU suite carries the
staged half". This is precisely "an axis row and a suite lane in the same change" that the finding
asked for. Additionally, the per-module file list gained: "`fields.jl` (including the rank-free
transform plans and their component-offset alignment lane, decision 76; ...)" — a second, consistent
mention in the same file.

**class_surfaces:** The finding's own text only names "docs/TESTING.md §4" as the surface (the
coverage-axes list) — it does not itself point to a second location. The diff in fact also touched
the adjacent per-module-file bullet in the same document (a second mention, not a different
surface), which is evidence of sweeping rather than a class left unswept. No other doc
(FORMALIZATION, ARCHITECTURE) is implicated by this finding's wording, and decision 76 already has
its own ARCHITECTURE §13 entry (pre-existing, per the file's own §13 numbering at line 3975) so
nothing there was missing. Fully swept as scoped.

---

## Finding 5

**Title:** No FORMALIZATION/TESTING mention of decisions 74 and 75

**Verdict:** HONORED

**Evidence:** No diff hunk adds decision-74/75 entries to `docs/FORMALIZATION.md` or `docs/TESTING.md`
(confirmed: `grep -n "similar_field\|write_field\|read_field" docs/FORMALIZATION.md` returns nothing).
Instead this finding is closed by a recorded, reasoned dismissal now living in the tree, in
`.claude/doc-review-adjudicated.md` under "`/check-docs` 2026-08-27 — three dismissals, recorded so
they are auditable": the entry quotes the finding's title verbatim — "**No FORMALIZATION/TESTING
mention of decisions 74 and 75**" — and gives the reason: decision 74 is an allocation-shape change
and decision 75 is I/O persistence, neither stating a new mathematical fact, and their siblings
(`similar_field`, `write_field`/`read_field`) carry no entries either, so adding these two would make
the page inconsistent in the other direction. It also states the overturn condition ("if a later round
shows an untested nontrivial claim resting on either"). This is a legitimate refuse-with-reason
closure per the project's own audit doctrine (a serious finding must be "fixed, refused with a
reason, or escalated, never absent") and it is recorded where a verifier can see it, which is exactly
what the finding's own banked file flagged as originally missing (an earlier commit's dismissal lived
only in a commit message and graded UNDONE for that reason — this round's dismissal fixes that
specific defect by making the record durable and machine-matchable).

**class_surfaces:** The finding names two siblings by its own text ("similar_field and write_field also
have no entries, so the precedent for omission is consistent" — this reasoning comes from the
finding's own lower-confidence note). The dismissal directly addresses that precedent (confirms
`similar_field`/`write_field`/`read_field` still carry no entries, and treats that consistency as the
justification rather than a gap) — so the class this finding raised (decisions with no
FORMALIZATION/TESTING mention) was explicitly reasoned about across its full stated scope, not just
the two named decisions. No further site is implied by the finding's wording.
