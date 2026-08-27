# 01-architecture — closure grading

## Finding 1

**Verdict:** HONORED

**Evidence:** `git diff d03a2e9c..HEAD -- docs/ARCHITECTURE.md` at decision 63:

```
-    `FieldTransformPlans` stores its own grid and layout and carries `T` (its element type) and `R` (its
-    tensor order) as type parameters, so
-    it can allocate its own witnesses, plan, and release them. The struct now also records the planner
+    `FieldTransformPlans` stores its own grid and layout and carries `T` (its element type) as a type
+    parameter, so it can allocate its own witnesses, plan, and release them. (It also carried `R`, its
+    tensor order, when this was written; **decision 76 removed it** — a transform is a property of the
+    base, so one plan pair now serves every rank and the rebuild uses order-0 witnesses.) The struct now also records the planner
```

The stale claim is removed and replaced with a correct, dated superseded-by note (functionally the
same convention used by decision 20's "(Superseded by decision 60: …)" parenthetical — the finding's
own comparison class — even though the wording isn't verbatim identical). Verified against the current
code: `src/Fields.jl:1298` — `struct FieldTransformPlans{T<:AbstractFloat, PF, PI, G<:Grid3D{T},
L<:RealFourierLayout, S}` — carries no `R`, matching the corrected claim.

**class_surfaces:** The finding names one class: sites claiming `FieldTransformPlans` carries `R` as a
type parameter, and the sibling convention of a superseded-by note (citing decisions 20/50/51/57/60 as
the pattern to follow). Swept:
- `docs/ARCHITECTURE.md` decision 63 (the quoted site) — fixed, in diff.
- `docs/FORMALIZATION.md:724-733` (the decision-63-backing entry, "`FieldTransformPlans` is the one
  companion that is rebuilt rather than moved…") — inspected, makes no R-type-parameter claim, so
  nothing there needed fixing (not touched by the diff, but not stale either).
- Grepped `docs/ARCHITECTURE.md`, `docs/FORMALIZATION.md`, `docs/PERFORMANCE.md`, `docs/TESTING.md` for
  any other "carries R as a type parameter" / "tensor order … type parameter" phrasing tied to
  `FieldTransformPlans` — none found; the decision-63 §13 entry was the only stale instance.
- `src/Fields.jl:1298,1378` (the actual struct/constructor) — confirmed already correct (no doc
  drift there to begin with).
No other site in the class was left stale.

## Finding 2

**Verdict:** HONORED

**Evidence:** `git diff d03a2e9c..HEAD -- docs/ARCHITECTURE.md` at decision 49:

```
-    product itself carries), both terms already
+    product itself carries; that displayed form is the **population** moment — `corrected = false` —
+    and `var`'s default `corrected = true` returns it scaled by ``N/(N-1)``), both terms already
```

The formula is now explicitly labelled as the population (`corrected = false`) form and the default
Bessel-corrected behaviour is stated inline, closing the omission the finding names.

**class_surfaces:** The finding is about one displayed formula in `docs/ARCHITECTURE.md` §13 decision
49. Checked the other places the same var/std spectral formula and its Bessel-correction default are
documented:
- `docs/FORMALIZATION.md:459-478` ("Variance, standard deviation, and covariance (decision 49)") —
  already states both the `corrected=false` population form and the `corrected=true` default with the
  ``N_B/(N_B-1)`` factor; not stale, nothing to fix, not touched by the diff (correctly left alone).
- `src/Reductions.jl:543-571` (`var` docstring) and `:715-733` (spectral `var` implementation +
  internal `#` comment) — already document/implement the correction default correctly; the internal
  comment above `function var(field::ScalarFieldSpectral...)` states the population formula without
  repeating the correction caveat, but it is an unrendered `#` comment (exempt by the project's own
  documentation-policy carve-out for internal comments), not a rendered claim, so it is not part of
  this class.
- `docs/TESTING.md` — grepped for `var`/population/Bessel language tied to decision 49; no matches, no
  stale claim to sweep.
No other rendered surface repeated the omitted-correction error, so the single fixed site closes the
class.
