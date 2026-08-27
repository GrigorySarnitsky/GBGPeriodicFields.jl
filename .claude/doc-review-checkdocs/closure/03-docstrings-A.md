RANGE: d03a2e9c..HEAD

## Finding 1

**Title:** adapt's docstring says the plans carry their own tensor order

**Verdict:** HONORED

**Evidence:** `git diff d03a2e9c..HEAD -- src/Fields.jl` shows the `adapt` docstring's
"Transform plans are rebuilt, not moved" warning changed from:

> the plans carry their own grid, layout, element type and tensor order

to:

> the plans carry their own grid, layout and element type — and no tensor order, since
> decision 76 — so the two arrays

This now agrees with the `FieldTransformPlans` docstring ~100 lines earlier (unchanged by
this diff, and already correct): "The plans are backend-, array-type- and scalar-type-specific,
and **carry no tensor order**" (src/Fields.jl:1292-1296), and with `docs/ARCHITECTURE.md:3975`
decision 76 ("The transform plans carry no tensor order").

**class_surfaces:** The finding's own text names exactly two comparison points: (a) "the
FieldTransformPlans docstring 100 lines earlier" (src/Fields.jl:1292) — this was already
correct pre-fix, so it needed no edit and none was made; (b) "decision 76" — a code/decision-log
fact, not a docstring site to sweep, already correctly stated in `docs/ARCHITECTURE.md:3975`.
A targeted grep (`plans (carry|carries).{0,40}tensor order`) across src/, docs/ARCHITECTURE.md,
docs/FORMALIZATION.md, docs/TESTING.md, docs/PERFORMANCE.md and docs/src/ found no other stale
"plans carry tensor order" claim outside the one line fixed. One adjacent internal-helper
docstring (`_physical_field_of_order`, src/Fields.jl:2243, "it has only the plans' own grid,
layout, element type and order") uses the bare word "order" ambiguously in the same
neighborhood, but it is an internal `_`-prefixed helper (exempt from the strict docstring
rubric) and does not use the phrase "tensor order," so it is not clearly part of the same
false-claim class rather than a loose paraphrase. Given the finding named only the two sites
above and both are now consistent, and no other explicit false claim was found on a corpus
sweep, this is graded HONORED rather than LINE-ONLY.

---

## Finding 2

**Title:** FieldSpectralMultipliers' 'The fields are' list omits the six oriented views of decision 70

**Verdict:** HONORED

**Evidence:** `git diff d03a2e9c..HEAD -- src/Fields.jl` adds to the `FieldSpectralMultipliers`
"The fields are" bullet list:

> - `wavenumber_view_1..3`, `squared_wavenumber_view_1..3` — the same six vectors, each stored
>   pre-oriented as a 3-D view along its own axis. They hold no data of their own: they alias the
>   vectors above, and exist so a broadcast-route operator never rebuilds a `reshape` per call
>   (decision 70). Read them through `_wavenumber_broadcast_view` and `_squared_wavenumber_broadcast`
>   rather than directly.

Verified against the actual struct definition (`src/Fields.jl`, `struct FieldSpectralMultipliers`):
the field names `wavenumber_view_1/2/3` and `squared_wavenumber_view_1/2/3` match exactly, and
the twelve-array total (six base + six oriented views) the finding cited is now fully documented.
The two named helper functions (`_wavenumber_broadcast_view`, `_squared_wavenumber_broadcast`)
both exist in src/Fields.jl and are the actual accessors used by `DifferentialOperators.jl`.

**class_surfaces:** The finding is narrowly about one struct's one docstring listing having an
incomplete field enumeration ("the struct stores twelve arrays; the docstring documents six").
There is only one `FieldSpectralMultipliers` docstring in the package (no sibling/duplicate
listing elsewhere — confirmed via `grep -n "The fields are" src/Fields.jl` showing this is the
sole occurrence for this struct), so there is no second surface implied by the finding's own
text to sweep. Graded HONORED.

---

## Finding 3

**Title:** Formula-like pseudo-code in backticks in the FiberSections codegen builders

**Verdict:** UNDONE

**Evidence:** `git diff d03a2e9c..HEAD -- src/FiberSections.jl` shows only a cosmetic change
(moving a `#` comment above rather than below the `_MapValues` docstring) — no change to
`_vector_kernel_body`, `_fiberwise_pass!`, or any backtick-wrapped
`destination = α * formula + β * destination`-shaped pseudo-code span. Confirmed no other hunks
touch this file's kernel-body builders in the diff.

This finding is recorded in `.claude/doc-review-adjudicated.md` under "/check-docs 2026-08-27 —
three dismissals," quoted verbatim as the finding's own title: "Formula-like pseudo-code in
backticks in the FiberSections codegen builders — quoted verbatim from the banked finding. The
spans ... describe the *shape of the code the generator emits*, not mathematics, in internal
`_`-prefixed builders that the rubric already treats loosely. Rewriting them as LaTeX would
misrepresent them as formulas." The adjudicated file itself notes that its own mechanical
verifier ("verify-fixes.js") "correctly graded all three UNDONE, because a dismissal that is not
recorded in the tree is indistinguishable from neglect," and records the reason here so a future
round can "close against this note or overturn it explicitly" rather than re-litigate it. Per
that same precedent and the task's own hard rule ("default to the unfavourable verdict... grade
it on a hunk you can quote"), this is graded UNDONE (no code hunk addresses it) with this note
attached: it is a **recorded, reasoned dismissal**, not neglect — mark it as settled-not-a-defect
rather than an open gap requiring further fix-pass action.

**class_surfaces:** The finding names two specific functions, `_vector_kernel_body` and
`_fiberwise_pass!`, both in src/FiberSections.jl, as the sites carrying the offending
backtick-wrapped pseudo-code. Neither is touched by the diff. No other file was checked for the
same pattern since the dismissal reasoning (internal `_`-prefixed builders describing generated
code shape, not math) applies to the whole class of such internal codegen docstrings, and the
finding names no sibling surface beyond these two functions.
