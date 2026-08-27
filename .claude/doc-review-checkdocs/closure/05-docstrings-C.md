RANGE: d03a2e9c..HEAD

## Finding 1

**Finding:** The umbrella docstring never names `reality_residual` (src/GBGPeriodicFields.jl, Fields bullet) — exported per decision 71 but absent from the module summary.

**Verdict:** HONORED

**Evidence:** `git diff d03a2e9c..HEAD -- src/GBGPeriodicFields.jl` shows the Fields bullet gained: "...and `reality_residual` reports how far a field's coefficients are from being a real field's spectrum (it reports, and never repairs)." `reality_residual` is now named in the Fields bullet, matching the wording used for it elsewhere in the codebase (invariant/decision 71's "reports, never repairs" framing).

**class_surfaces:** The finding's own text scopes the defect to one site — "the umbrella docstring, Fields bullet" — and gives no other surface (no sibling docstring, no other module bullet, no other page named or implied). There is nothing else for the class to sweep; the single named site is fixed. Confirmed by reading the full Fields bullet post-diff: no other decision-71 mention of `reality_residual` is missing elsewhere in that bullet or the umbrella docstring.

## Finding 2

**Finding:** The umbrella docstring never names `adapt!` (src/GBGPeriodicFields.jl, Fields bullet) — exported per decision 69; only `adapt` was named.

**Verdict:** HONORED

**Evidence:** Same hunk: "...`adapt` has an in-place sibling `adapt!` for a destination that already exists..." `adapt!` is now named alongside `adapt` in the Fields bullet.

**class_surfaces:** Finding names a single site (the Fields bullet) with no other surface implied (no sibling page, no other bullet). Fixed at that site; nothing else to sweep.

## Finding 3

**Finding:** The umbrella docstring never mentions the family-taking constructors of decision 74 (src/GBGPeriodicFields.jl, Fields bullet) — only `similar_field` was named as an allocator.

**Verdict:** HONORED

**Evidence:** Same hunk: "The six field constructors also accept a storage **family** in place of an array — `VectorFieldSpectral(CuArray, grid, layout)` — for a caller holding domain context but no field to copy from..." This names the decision-74 family-taking constructors directly.

**class_surfaces:** Finding names a single site (the Fields bullet); no other module bullet or page is named or implied by the finding's text. Fixed at that site; nothing else to sweep.
