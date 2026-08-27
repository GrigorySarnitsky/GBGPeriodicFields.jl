# Closure grading — 02-rationale-docs (hat: rationale-docs)

Graded against `git diff d03a2e9c..HEAD`.

## Finding 1

**Finding:** FORMALIZATION says FieldTransformPlans is determined by its tensor order (docs/FORMALIZATION.md,
Storage families) — contradicted by decision 76; `adapt_structure` uses `Val(0)` witnesses.

**Verdict:** HONORED

**Evidence:** `docs/FORMALIZATION.md` diff:
```
-`FieldTransformPlans` ... is nonetheless determined by
-data it already carries — the grid, the layout, its element type and its tensor order — so the rebuild
+`FieldTransformPlans` ... is nonetheless determined by
+data it already carries — the grid, the layout and its element type — so the rebuild
```
The stale "and its tensor order" clause is removed, matching decision 76 / the `Val(0)` witness code
(`src/Fields.jl:1298-1306`, comment: "the plan is a property of the base and carries no tensor order: one
pair serves every rank"). The sibling claim in `docs/ARCHITECTURE.md`'s decision-63 entry was swept in the
same diff:
```
-A `FieldTransformPlans` stores its own grid and layout and carries `T` (its element type) and `R` (its
-tensor order) as type parameters, so
+A `FieldTransformPlans` stores its own grid and layout and carries `T` (its element type) as a type
+parameter, so it can allocate its own witnesses, plan, and release them. (It also carried `R`, its
+tensor order, when this was written; **decision 76 removed it** — ...)
```

**class_surfaces:** The finding names one surface explicitly — `docs/FORMALIZATION.md`, Storage families —
and implies (via "contradicted by decision 76") that any other doc surface repeating the same "plans carry
a tensor order" claim is the same class. Checked: `docs/ARCHITECTURE.md` decision-63 entry (~line 3355) —
carried the identical stale claim and **was swept** in this diff (quoted above). `src/Fields.jl`'s
`FieldTransformPlans` docstring/struct comments (~line 1298) — already correct pre-fix (decision 76's own
code-side commit), nothing stale to sweep. `docs/src/tutorial.md:62` — already states "carries no tensor
order," consistent, not stale. No other instance of the stale claim found by grep across `docs/*.md` and
`src/Fields.jl`. The class was genuinely swept, not just the one quoted line.

---

## Finding 2

**Finding:** No FORMALIZATION entry for `reality_residual` (decision 71) — docs/FORMALIZATION.md. A tested,
nontrivial claim with no typed entry breaks the prose-formalization-test chain.

**Verdict:** HONORED

**Evidence:** New block added to `docs/FORMALIZATION.md` (after the transform section):
```
+**The reality condition (decision 71).** A half-spectrum is the spectrum of a REAL field iff it is
+Hermitian, ``\hat f(-k) = \overline{\hat f(k)}``. ...
+```math
+\mathrm{reality\_residual}(\hat f) = \max_{k \in \text{self-conjugate planes}}
+                                      \bigl\lvert \hat f(k) - \overline{\hat f(-k)} \bigr\rvert ,
+```
+... which is zero for anything the package produces ...
+
+**Backs** [Architecture](architecture.md) §4 and the `Fields` transform docstrings.
+**Checked by** `test/fields.jl` — ...
```
This closes the prose↔formalization↔test chain the finding named: `docs/TESTING.md` already links
`reality_residual` to an elementwise oracle in `test/fields.jl` (pre-existing text, confirmed unchanged by
this diff at the surrounding lines), so the new FORMALIZATION entry's "Checked by `test/fields.jl`" claim is
substantiated, not dangling.

**class_surfaces:** The finding names only `docs/FORMALIZATION.md` as the missing site; it does not itself
imply other surfaces (it is a "no entry" finding, not a "wrong claim repeated elsewhere" finding). No
further surface to check beyond confirming the test-link target exists, which it does.

---

## Finding 3

**Finding:** No FORMALIZATION entry for the tuple `weighted_inner` fusion identity (decision 72) —
docs/FORMALIZATION.md, weighted_inner. Only the single-weight form is formalized.

**Verdict:** HONORED

**Evidence:** `docs/FORMALIZATION.md` diff, immediately after the existing single-weight `weighted_inner`
formula:
```
+generalizing `inner` (the ``w\equiv1`` case) — the reduction-dual of `convolve`. Given a **tuple** of
+weights it answers all of them in one traversal, and the identity that licenses the fusion is that each
+answer is the one the separate call would give:
+
+```math
+\mathrm{weighted\_inner}(f, (w_1,\dots,w_n))_j = \mathrm{weighted\_inner}(f, w_j),
+\qquad j = 1,\dots,n ,
+```
+
+**bitwise**, not merely to roundoff — the coefficient reads are shared while each weight is still
+evaluated per mode, so no summation order changes (decision 72).
```
This is exactly the missing identity the finding names, stated as a typed equation with the bitwise
(not merely-to-roundoff) qualifier the class of nearby entries uses.

**class_surfaces:** The finding names only `docs/FORMALIZATION.md`, weighted_inner section — no other
surface implied (it is not a "claim repeated elsewhere" finding, it is a coverage gap in one page's one
section). Nothing further to sweep.

---

## Finding 4

**Finding:** TESTING §4 coverage-axes list has no entry for decision 76's component-offset alignment
(docs/TESTING.md §4). A new admissible input region must get an axis row and a suite lane in the same
change; TESTING mentions decision 76 nowhere.

**Verdict:** HONORED

**Evidence:** `docs/TESTING.md` diff adds axis 18 to the §4 coverage-axes list:
```
+18. **component-offset alignment**, per FFT backend (decision 76). A rank-``R`` field's component `c`
+    begins at element offset ``(c-1)\prod_a N_a``, and a transform library may refuse a pointer whose
+    alignment differs from the one it planned for ... `test/fields.jl` carries the lane — every rank over
+    `(8,8,8)`, `(8,7,6)`, `(7,5,3)` and `(9,9,9)`, plus the predicate itself asserted directly — and the
+    GPU suite carries the staged half, since the host never reaches it.
```
and also updates the per-module-behaviour-files list (§2-area) to cite decision 76 for `fields.jl`:
```
-- **Per-module behaviour files** — `fields.jl` (including the real-field **reality condition** of
+- **Per-module behaviour files** — `fields.jl` (including the rank-free transform plans and their
+  component-offset alignment lane, decision 76; the real-field **reality condition** of
```
Both the axis-list entry and the suite-lane citation the finding asked for ("gets an axis row and a suite
lane in the same change") are present.

**class_surfaces:** The finding is scoped to one page, one list (`docs/TESTING.md` §4); it does not itself
name sibling surfaces. Checked whether `docs/FORMALIZATION.md` or `docs/ARCHITECTURE.md` needed a matching
mention of decision 76's alignment behavior for completeness — `docs/ARCHITECTURE.md`'s decision-76 entry
(~line 3967, pre-existing) already documents the alignment mechanism narratively; not part of this
finding's scope (a coverage-axes-list finding, not an architecture-narrative finding). Nothing left unswept
within the finding's own named surface.

---

## Finding 5

**Finding:** No FORMALIZATION/TESTING mention of decisions 74 and 75 (docs/FORMALIZATION.md,
docs/TESTING.md). Lower confidence: the lane notes `similar_field` and `write_field` also have no entries,
so the precedent for omission is consistent.

**Verdict:** UNDONE

**Evidence:** `git diff d03a2e9c..HEAD -- docs/ARCHITECTURE.md docs/FORMALIZATION.md docs/TESTING.md | grep
-in "74\|75\|scheme\|allocating"` returns nothing — the diff touches neither decision 74 (allocating
constructors) nor decision 75 (transfer-scheme persistence) anywhere in the three rationale docs.
`docs/FORMALIZATION.md` still carries zero mentions of "decision 74", "decision 75", "write_scheme",
"read_scheme", or "allocating constructor" after the fix pass (`grep -n` empty). Note: `docs/TESTING.md`
already mentioned both decisions *before* this fix pass (lines ~153 and ~482 of the pre-fix file, unchanged
by this diff) — the finding's premise about TESTING.md was already largely stale/wrong at file time, and
its own "lower confidence" hedge anticipated this being declined-as-non-defect. But whether declined or
simply missed, the fix pass made **no edit whatsoever** addressing this finding, so per the grading rule
("if you cannot find any relevant edit, it is UNDONE") this is UNDONE rather than a documented dismissal.

**class_surfaces:** The finding names `docs/FORMALIZATION.md` and `docs/TESTING.md` directly for decisions
74 and 75. TESTING.md: already had partial coverage pre-fix (not swept further, but also not the gap).
FORMALIZATION.md: genuinely has no typed entries for either decision, and the diff adds none — the gap
named by the finding is unaddressed on its primary named surface.
