# 06-doc-pages — closure grading

## Finding 1

**Verdict:** HONORED

**Evidence:** `git diff d03a2e9c..HEAD -- docs/src/api.md` shows all three named gaps closed in the
module-map bullets:
- Fields bullet gained `"constructors that take a storage family directly"` (decision 74) and
  `"the reality check reality_residual"` (bonus, ties to finding 2).
- Points bullet gained `"base-space motion (\`displace!\` and \`wrap!\`)"` (decision 73).
- Interpolation bullet gained `"together with scheme persistence (\`write_scheme\`/\`read_scheme\`)"`
  (decision 75).

Cross-checked against `docs/src/index.md` (the comparison target the finding names): index.md's
`Fields`/`Points`/`Interpolation` bullets (lines 43, 47–48) already carried all three decisions before
this fix pass (untouched by the diff — `git diff d03a2e9c..HEAD -- docs/src/index.md` is empty), so
api.md now matches the page it was stale against. The specific staleness the finding named is gone.

**class_surfaces:** The finding's own scope is "api.md's entries are stale relative to index.md" — a
two-page consistency claim, not a broader "every page must mention every decision" claim. The only
other surface a reader would check for the same relation is index.md itself, which was already current
(confirmed above) and needed no edit. No other page is implied by the finding's text. Sweep: complete
for the surfaces the finding actually names.

## Finding 2

**Verdict:** LINE-ONLY

**Evidence:** The finding names TWO locations equally: `docs/src/index.md` and `docs/src/api.md`. The
diff (`git diff d03a2e9c..HEAD -- docs/src/api.md`) added `"the reality check \`reality_residual\`"` to
the Fields bullet — that surface is fixed. But `git diff d03a2e9c..HEAD -- docs/src/index.md` is
completely empty, and a direct read of the current file confirms the Fields bullet at
`docs/src/index.md:43` still lists grids/representations/transforms/allocator/constructors/kernel
supertype/broadcasting/HDF5/`adapt` — no `reality_residual` anywhere in that bullet or elsewhere on the
page. One of the two named sites was fixed; the other, named with equal weight in the finding's own
"Location" field, was left exactly as flagged.

**class_surfaces:** `docs/src/index.md:43` (Fields bullet) — NOT swept, still missing `reality_residual`.
`docs/src/api.md:9` (Fields bullet) — swept. Since the finding explicitly names both pages as the
defect's extent and only one was touched, this is textbook LINE-ONLY.

## Finding 3

**Verdict:** LINE-ONLY

**Evidence:** `git diff d03a2e9c..HEAD -- docs/src/tutorial.md` removes the redundant
`scalar_plans = FieldTransformPlans(φ, scalar_spectral)` line, reuses the vector field's `plans` for the
scalar Laplacian call, and adds explanatory prose: *"a `FieldTransformPlans` carries no tensor order and
one pair serves every rank — build one per backend and element type, not per rank."* The quoted site
(tutorial.md line ~70) is fixed cleanly and correctly, matching the docstring's own rule.

**class_surfaces:** The finding's own text states the general convention being violated — one
`FieldTransformPlans` per backend/element type, never per tensor order — which is exactly the pattern
that recurs in the package's other consumer-shaped doc surfaces. A grep for `FieldTransformPlans(` across
the tree shows the SAME anti-pattern, untouched by this diff:
- `examples/HIST_CPU.jl:323-326` — builds `vplans` (vector) and a separate `splans` (scalar) via two
  `FieldTransformPlans(...)` calls, exactly the per-rank duplication the tutorial was just corrected for.
- `examples/gpu/rocm/HIST_ROCm.jl:347-350` — the same `vplans`/`splans` duplication on the GPU demo.
- `docs/src/examples/hist_cpu.md:364-367` — the Literate-rendered copy of the CPU example, carrying the
  same duplication (CLAUDE.md itself states a Literate example "IS a rendered doc page" subject to the
  same scrutiny).

`git diff --stat d03a2e9c..HEAD` confirms none of these three files were touched by the fix pass. The
class (documentation surfaces modeling the "build a plans per rank" anti-pattern) was not swept beyond
the one quoted tutorial line.

## Finding 4

**Verdict:** UNDONE

**Evidence:** `git diff --stat d03a2e9c..HEAD` shows neither `examples/HIST_CPU.jl` nor
`examples/gpu/rocm/HIST_ROCm.jl` in the changed-file list. Direct greps confirm: `advect!` is still
defined and called at `examples/HIST_CPU.jl:265,368` and `examples/gpu/rocm/HIST_ROCm.jl:294,391`
unchanged, hand-rolling point motion; `grep -n "displace!\|wrap!" examples/HIST_CPU.jl
examples/gpu/rocm/HIST_ROCm.jl` returns nothing — the decision-73 primitives the finding says exist for
exactly this pattern are not used anywhere in either demo. Nothing in the diff addresses this finding.

**class_surfaces:** The finding names both demo call sites directly (`examples/HIST_CPU.jl:262`,
`examples/gpu/rocm/HIST_ROCm.jl:291`) plus their Literate-rendered counterpart
`docs/src/examples/hist_cpu.md` (same `advect!` pattern, generated from the CPU script). All three are
unswept — none appear in the diff.
