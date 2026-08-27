# Closure grading — 03-docstrings-A

## Finding 1

**Verdict:** HONORED

**Evidence:** `git diff d03a2e9c..HEAD -- src/Fields.jl` shows the `adapt` docstring's
`FieldTransformPlans` warning changed from:

> "the plans carry their own grid, layout, element type and tensor order, so the two arrays"

to:

> "the plans carry their own grid, layout and element type — and no tensor order, since
> decision 76 — so the two arrays"

(`src/Fields.jl` around line 2200). This is exactly the site the finding names.

**class_surfaces:** The finding's own text names two other surfaces to check for
consistency, not to independently re-fix: (1) "the FieldTransformPlans docstring 100
lines earlier" — `src/Fields.jl:1292` already reads "The plans are backend-, array-type-
and scalar-type-specific, and **carry no tensor order**" and was untouched by this diff
(it was already correct — no contradiction remained to fix there); (2) "decision 76" —
`docs/src/architecture.md:3967`, "**The transform plans carry no tensor order**", also
untouched by this diff (pre-existing and already correct, confirmed via
`git diff d03a2e9c..HEAD -- docs/src/architecture.md` showing no changes near decision 76).
A grep of `src/` and `docs/src/` for "plans carry" / "carry.*tensor order" turns up no
other stale instance of the false claim. Both named surfaces were already consistent with
the fix, so the one contradictory sentence was the whole class; it is now gone.

---

## Finding 2

**Verdict:** HONORED

**Evidence:** `git diff d03a2e9c..HEAD -- src/Fields.jl` adds to the `FieldSpectralMultipliers`
"The fields are" list:

```
+- `wavenumber_view_1..3`, `squared_wavenumber_view_1..3` — the same six vectors, each stored
+  pre-oriented as a 3-D view along its own axis. They hold no data of their own: they alias the
+  vectors above, and exist so a broadcast-route operator never rebuilds a `reshape` per call
+  (decision 70). Read them through `_wavenumber_broadcast_view` and `_squared_wavenumber_broadcast`
+  rather than directly.
```

Counting the struct definition at `src/Fields.jl:1722-1744`: `grid`, `fourier_layout`,
`wavenumber_1..3`, `squared_wavenumber_1..3`, `wavenumber_view_1..3`,
`squared_wavenumber_view_1..3` — 14 fields total, all now listed in the docstring
(2 + 3 + 3 + 3 + 3).

**class_surfaces:** The finding's own text is scoped to one struct
(`src/Fields.jl`, `FieldSpectralMultipliers`) and does not name a sibling type or a second
"fields are" list sharing the same gap. No other surface is implied by the finding's
wording, so there is nothing else to sweep for this specific finding.

---

## Finding 3

**Verdict:** UNDONE

**Evidence:** `git diff d03a2e9c..HEAD -- src/FiberSections.jl` touches only a comment
placement for `_MapValues` (moving a `#`-comment from between the docstring and the struct
to above the docstring) — nothing else in the file changed. The two sites the finding
names are byte-identical between `d03a2e9c` and `HEAD`:

- `_vector_kernel_body` docstring (`src/FiberSections.jl:484`, both before and after):
  ``"With `alpha_beta = true` it emits the five-argument `destination = α * formula + β *
  destination` form and branches on `iszero(β_value)`"`` — `formula` is a function
  parameter (an `i -> expr` closure), not a value, so `α * formula + β * destination` is
  not an expression the code ever evaluates; it is pseudo-code inside a backtick span.
- `_fiberwise_pass!` docstring (`src/FiberSections.jl:794`, both before and after):
  ``"every target element receives `α * f(element values..., constants...)`, plus `β`
  times its prior value"`` — `element values...` is prose, not a real Julia argument list,
  inside a backtick span.

Confirmed via `git show d03a2e9c:src/FiberSections.jl | sed -n '480,520p'` and
`sed -n '790,850p'` against the current file: both blocks match verbatim. Neither site was
touched by the fix pass.

**class_surfaces:** The finding names exactly two sites —
`src/FiberSections.jl` `_vector_kernel_body` and `_fiberwise_pass!` — as the location of
the defect (both quoted above); the same finding's rationale (formula-like pseudo-code in
backticks, not well-formed Julia) applies by construction to `_tensor_kernel_body`
(`src/FiberSections.jl:517`, "writing `destination_ij .= formula(i, j)`") and
`_fiberwise_slab!`, which sit immediately beside the two named sites and share the same
builder-doc idiom — none of these were touched either. Neither the two literally-named
sites nor the neighboring instances of the same pattern were edited.
