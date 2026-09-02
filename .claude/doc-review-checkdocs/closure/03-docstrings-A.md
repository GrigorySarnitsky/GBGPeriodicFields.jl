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
docstring (`_field_physical_of_order`, src/Fields.jl:2243, "it has only the plans' own grid,
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

**Verdict:** HONORED

**Evidence:** closed 2026-09-01, when this round's remaining open finding was worked rather than
the round being closed as superseded. `src/FiberSections.jl:490` wrote ``destination_i .= formula(i)``
in a code span — `destination_i` is not an identifier the code has, the real target being
`_vector_component_data(destination, i)` — and `:802` wrote ``α * f(element values..., constants...)``,
which is math, not Julia. Both are rewritten: 490 names the real target in prose, 802 is now a LaTeX
span. Verified by re-scan: no `destination_<index>` pseudo-identifier remains in any code span in
`src/`, and the surviving `_i`/`_ij` matches are LaTeX math spans or real lambda forms (`i -> expr`).

**class_surfaces:** the finding named two sites, `src/FiberSections.jl:490` (`_vector_kernel_body`)
and `src/FiberSections.jl:802` (`_fiberwise_pass!`); both fixed. Sweeping the class rather than the
quoted lines found a THIRD the finding did not name — `src/FiberSections.jl:523`, the tensor twin
`_tensor_kernel_body`, carrying the identical `destination_ij .= formula(i, j)` — also fixed. A
package-wide re-scan of `src/*.jl` for a pseudo-identifier inside a backtick span now returns no
remaining instance.
