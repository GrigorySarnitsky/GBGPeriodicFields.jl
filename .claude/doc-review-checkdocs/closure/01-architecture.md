RANGE: d03a2e9c..HEAD

## Finding 1

**Title:** Decision 63 claims FieldTransformPlans carries R (its tensor order) as a type parameter

**Verdict:** HONORED

**Evidence:** `git diff d03a2e9c..HEAD -- docs/ARCHITECTURE.md` shows decision 63's entry rewritten:

```
- `FieldTransformPlans` stores its own grid and layout and carries `T` (its element type) and `R` (its
- tensor order) as type parameters, so
+ `FieldTransformPlans` stores its own grid and layout and carries `T` (its element type) as a type
+ parameter, so it can allocate its own witnesses, plan, and release them. (It also carried `R`, its
+ tensor order, when this was written; **decision 76 removed it** — a transform is a property of the
+ base, so one plan pair now serves every rank and the rebuild uses order-0 witnesses.)
```

The stale claim is gone and a superseded-by note is now present, matching the convention the finding
pointed at (decisions 20/50/51/57/60). Verified against `src/Fields.jl`: `FieldTransformPlans{T}` is
parameterized only on `T`, no `R`.

**class_surfaces:** The finding's own text implies the general convention ("unlike decisions
20/50/51/57/60") but names only the one decision-63 site as defective — it does not itself enumerate
other pages carrying the same stale claim. Checking the class anyway, since the underlying wrong fact
("FieldTransformPlans carries R as a type parameter") could recur elsewhere: grep of
`FieldTransformPlans` + "tensor order"/"type parameter" across `docs/*.md`, `docs/src/*.md`, `CLAUDE.md`
and `src/*.jl` (excluding the built `docs/build/` HTML) turns up no other stale instance —
`docs/src/tutorial.md:62` already reads "carries no tensor order", `CLAUDE.md`'s Fields.jl bullet
already reads "since decision 76 carries no tensor order", and `docs/FORMALIZATION.md`'s companion
passage was independently fixed in this same commit range (confirmed via the banked closure file for
the rationale-docs hat, `.claude/doc-review-checkdocs/closure/02-rationale-docs.md` Finding 1, which
grepped the same class across ARCHITECTURE/TESTING/tutorial and found it fully swept). Decision 63 in
`docs/ARCHITECTURE.md` was the one remaining stale site and it is now fixed. Class fully swept.

---

## Finding 2

**Title:** Decision 49's spectral var formula omits the default Bessel correction

**Verdict:** HONORED

**Evidence:** `git diff d03a2e9c..HEAD -- docs/ARCHITECTURE.md` shows decision 49's entry gains, right
after the population-moment formula:

```
+ product itself carries; that displayed form is the **population** moment — `corrected = false` —
+ and `var`'s default `corrected = true` returns it scaled by ``N/(N-1)``), both terms already
```

This states plainly that the formula shown is the uncorrected population moment and that the actual
default (`corrected = true`) scales it by `N/(N-1)`, which is exactly the gap the finding named.

**class_surfaces:** The finding is specific to the one displayed formula in ARCHITECTURE.md's decision
49 entry; it does not name sibling surfaces explicitly, but the same "population-moment formula stated
without the correction caveat" class was checked across the corpus. `docs/FORMALIZATION.md`'s "Variance,
standard deviation, and covariance" passage (decision 49) already carried the correct, honestly-labelled
pair of formulas before this fix pass (`\operatorname{var}(f)\bigm|_{\texttt{corrected=false}} = ...`
followed by the `N_B/(N_B-1)`-scaled default) — confirmed by diffing `docs/FORMALIZATION.md` over the
same range, which shows no change to that passage, meaning it was already correct and needed none.
`src/Reductions.jl`'s `var`/`std`/`cov` docstrings (grepped for `corrected`) already document the
Bessel correction and its default explicitly. No other stale "population moment, uncorrected" formula
for `var` exists in `docs/ARCHITECTURE.md`, `docs/FORMALIZATION.md`, or `src/Reductions.jl`. Class fully
swept — the ARCHITECTURE.md decision-49 entry was the only defective site.
