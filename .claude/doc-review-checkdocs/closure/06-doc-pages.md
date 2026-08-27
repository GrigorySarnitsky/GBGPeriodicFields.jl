RANGE: d03a2e9c..HEAD

## Finding 1

**Verdict:** HONORED

**Evidence:** `git diff d03a2e9c..HEAD -- docs/src/api.md` shows all three named lines updated:
- Fields entry (line 9) gained `the reality check \`reality_residual\`, constructors that take a
  storage family directly, and \`adapt\`, ... with its in-place sibling \`adapt!\`` (decisions 71, 74,
  63/69).
- Points entry (line 13) gained `base-space motion (\`displace!\` and \`wrap!\`)` (decision 73).
- Interpolation entry (line 14) gained `together with scheme persistence (\`write_scheme\`/\`read_scheme\`)`
  (decision 75).

Confirmed current `docs/src/api.md` (lines 9/13/14) and `docs/src/index.md` (lines 43/47/48) now carry
matching content for all three decisions — checked side by side, both pages mention
`reality_residual`, `adapt!`, `displace!`/`wrap!`, and `write_scheme`/`read_scheme`. No other summary
listing in the repo (`architecture.md` §2 has its own prose map, `README`-equivalent is `index.md`
itself) was found to still omit them.

**class_surfaces:** The finding's own text names the comparison class explicitly — "stale relative to
`docs/src/index.md`" — so the one other surface it implies is `docs/src/index.md`'s "Main components"
list (the finding's location is api.md lines 9/13/14; its implied sibling is index.md's equivalent
lines, then ~40-48). Diff confirms `docs/src/index.md:43,47,48` were touched in the same commit
(`2a43a724`) and now read consistently with api.md. Both named surfaces swept.

---

## Finding 2

**Verdict:** HONORED

**Evidence:** `git diff d03a2e9c..HEAD -- docs/src/index.md` line 43: `+ the reality check
\`reality_residual\`,` inserted into the Fields summary. `git diff d03a2e9c..HEAD -- docs/src/api.md`
line 9: same phrase `the reality check \`reality_residual\`,` inserted into the Fields summary there
too. Both of the finding's two named locations (`docs/src/index.md`, `docs/src/api.md`) now mention
`reality_residual`; its full prose section on the Fields API page (`docs/src/api/Fields.md`, not
touched by the diff but not claimed stale by the finding) is unaffected and still the canonical home.

**class_surfaces:** The finding names exactly two surfaces — `docs/src/index.md` and
`docs/src/api.md` — as the two "summary" pages `reality_residual` was missing from, contrasted with
"its own prose section on the Fields API page" which already had it. Both named surfaces are directly
edited in the diff (confirmed above), so the class as stated by the finding is fully swept.

---

## Finding 3

**Verdict:** HONORED

**Evidence:** `git diff d03a2e9c..HEAD -- docs/src/tutorial.md` shows the second,
tensor-order-specific `scalar_plans = FieldTransformPlans(φ, scalar_spectral);` doctest line removed,
replaced by explanatory prose ("a `FieldTransformPlans` carries no tensor order and one pair serves
every rank — build one per backend and element type, not per rank") and the downstream `to_physical`/
`to_spectral` calls in that block switched from `scalar_plans` to the single `plans` built earlier for
the vector field. This directly resolves the contradiction with the `FieldTransformPlans` docstring
the finding cites.

Beyond the single tutorial line, the SAME defect pattern (a redundant scalar-specific plans pair built
alongside the vector plans, for a scalar diagnostic) was independently present in BOTH shipped example
scripts and was swept in the same diff:
- `examples/HIST_CPU.jl`: removed the `splans = FieldTransformPlans(ScalarFieldPhysical(...), ...)`
  block, added a comment explaining the one-pair-per-rank rule, and changed `to_physical(divergence(uh,
  m), splans)` → `to_physical(divergence(uh, m), vplans)`.
- `examples/gpu/rocm/HIST_ROCm.jl`: identical treatment — `splans` removed, comment added, `splans` →
  `vplans` at the divergence-diagnostic call site.

This is a genuine class sweep, not a line patch: the fixer found and corrected the same
misunderstanding-of-the-contract in the tutorial AND in both example drivers that exhibited it.

**class_surfaces:** The finding's own location is `docs/src/tutorial.md:70`; its implied class is "any
site building `FieldTransformPlans` per tensor order rather than reusing one pair" — a direct
consequence of the docstring contract it cites. The natural sibling surfaces are the shipped
`examples/` drivers, which are consumer-shaped code demonstrating the same API. Both
`examples/HIST_CPU.jl` and `examples/gpu/rocm/HIST_ROCm.jl` had the identical anti-pattern (a `splans`
built alongside `vplans` for one scalar diagnostic) and both are fixed in this diff, per the evidence
above. Grepped for any remaining second-plans-per-rank construction in `docs/src/tutorial.md`,
`examples/HIST_CPU.jl`, `examples/gpu/rocm/HIST_ROCm.jl` — none found (`FieldTransformPlans(` now
appears exactly once per file, tagged "any rank" in the examples).

---

## Finding 4

**Verdict:** HONORED

**Evidence:** This finding ("The examples' `advect!` hand-rolls point motion instead of using
`displace!`/`wrap!`") is explicitly recorded in
`.claude/doc-review-adjudicated.md` under "`/check-docs 2026-08-27` — three dismissals, recorded so
they are auditable," quoted there verbatim: *"The examples' `advect!` hand-rolls point motion instead
of using `displace!`/`wrap!`"* — with the stated reason: `displace!` covers the displacement, but the
demo's RK2 midpoint update is time-stepping, a consumer concern the package deliberately excludes
(invariant 12); CLAUDE.md already queues the rewrite for the consumer package, with an explicit
overturn condition ("if the demo is rewritten for other reasons"). This dismissal-with-reason was
itself added to the tree in this diff range (`git diff d03a2e9c..HEAD -- .claude/doc-review-adjudicated.md`
shows the entire "three dismissals" section, including this entry, as new). Confirmed `advect!` in
`examples/HIST_CPU.jl` (lines 265-271) is textually unchanged by the diff and still hand-rolls the RK2
midpoint update via bare `interpolate`/`mod`, consistent with the recorded refusal rather than neglect.
Per the task's adjudication rule, a finding covered by the adjudicated file is not an open defect; here
it is a reasoned, tree-recorded refusal (the finding's own text already flagged itself "Lower
confidence"), which the project's own `gate.py` philosophy treats as a valid closure alongside "fixed."

**class_surfaces:** The finding names two sites — `examples/HIST_CPU.jl:262` and
`examples/gpu/rocm/HIST_ROCm.jl:291` (current line numbers ~265 and ~291 respectively after other
edits). Both were checked: neither's `advect!` was rewritten to use `displace!`/`wrap!`, consistent
with the declined-not-silently-ignored status recorded in the adjudicated file, which explicitly
covers both example files under one dismissal (no per-file distinction is drawn in the finding or the
dismissal). No class sweep was owed since the finding was declined rather than accepted.
