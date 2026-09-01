# Lane 01 — docs/ARCHITECTURE.md (sections 1–13 + References)

Full read of the file (4239 lines): sections 1–12 read in full, decision-log entries 1–59
sampled/read in full where quoted, entries 60–79 read and verified in full against `src/`
(struct definitions for `FieldSpectralMultipliers`, `FieldTransformPlans`, `Grid3D`;
`transfer_order` signature; the 206/122 method-parity baseline in
`test/method_parity.jl`). Cross-checked several formulas and counts against source and against
`CLAUDE.md`'s own record of the same numbers.

## Finding 1

- **Check:** 1 (CORRECT) — a decision-log entry states a claim later explicitly retracted, with
  no correction marker, so it stands as false if a reader meets it on its own (which the file's
  own self-containment note, lines 9–13, promises each decision-log entry supports).
- **Location:** `docs/ARCHITECTURE.md:3061` (decision 56), contradicted by
  `docs/ARCHITECTURE.md:3196–3198` (decision 59).
- **Quote (decision 56, line 3061):** "A `mightalias` guard would reject `sym!(A, A)` itself,
  whose target and source component views already have different footprints on one parent, and
  decision 39 made that case guard-free after measurement."
- **Quote (decision 59, lines 3196–3198):** "And 'a `mightalias` guard would reject `sym!(A, A)`'
  — false; the component views for target ``(i,j)`` and source ``(j,i)`` select disjoint memory,
  so `mightalias` is `false` on them. That mistaken belief is why the defect was deferred for a
  day."
- **Why it violates the rule:** Decision 59 explicitly names the sentence in decision 56 as a
  "mistaken belief" that is "false." Decision 56's own text, however, presents exactly that claim
  as settled fact used to justify declining a guard — and it carries no "(superseded by decision
  59)" annotation, unlike every other place in the log where a later decision corrects an earlier
  one (e.g. decisions 57, 60, 61 are explicitly marked "Superseded by decision 60" etc. at their
  point of correction). The decision log's own stated convention (lines 1115–1116) is that later
  entries "supersede earlier … notes rather than contradicting them" — here the two entries do
  flatly contradict each other, and the reader has no signal at decision 56 that its stated
  reasoning was wrong. A reader who stops at decision 56 (or searches only it) is told something
  false and given no pointer to the correction that follows six entries later.
- **Fix:** Add a parenthetical correction note at line 3061 (decision 56), in the same style as
  the other superseded-by annotations in this log, e.g. "(This premise was found mistaken by
  decision 59 — a `mightalias` guard would in fact accept `sym!(A, A)`; the operational
  conclusion — no guard was added — happens to still hold, for the different reason decision 59
  records.)"

## Finding 2

- **Check:** 4 (FORMATTED, bidirectionally) — a backtick code span must hold only well-formed
  Julia; CLAUDE.md's rule gives "a lone ≤/·" as its explicit example of banned content.
- **Location:** `docs/ARCHITECTURE.md:1301` and `docs/ARCHITECTURE.md:2698`.
- **Quote (line 1301):** "magnitude via `lpnorm(·, Inf)`."
- **Quote (line 2698):** "where `mean(φ, ·)` reduces it."
- **Why it violates the rule:** Both backtick spans use "·" (U+00B7 MIDDLE DOT, confirmed by byte
  inspection) as a placeholder for "some argument." This is not valid Julia syntax — it is not a
  name, type, call, or expression that appears in the code — and is precisely the class the rubric
  singles out by name ("never math that merely looks code-ish ([lo, hi), R ≥ 2, a lone ≤/·)").
  Note this is a different character from Julia's actual infix dot-product operator `⋅`
  (U+22C5 DOT OPERATOR, which the package does export as `dot`'s infix alias) — so even a reader
  who knows Julia's dot-product syntax would not recognize "·" as valid.
- **Fix:** Reword to avoid the placeholder-as-code, e.g. "magnitude via `lpnorm` with `p = Inf`"
  and "which `mean` reduces when given a leading function `φ`" — or use plain prose ("`lpnorm(u,
  Inf)`" style with a real argument) rather than a bare interpunct standing in for "an argument."

## Finding 3

- **Check:** 5 (CURRENT/COMPLETE) and 6 (CITED) — `CLAUDE.md`'s own citation policy names a
  section of this file that does not exist under that name.
- **Location:** `docs/ARCHITECTURE.md` as a whole (no "## References" or "§References" heading
  anywhere); the only reference list is `docs/ARCHITECTURE.md:1032`, headed
  "**References (this section).**", scoped to §10.
- **Quote (CLAUDE.md, Documentation policy → Citations):** "doc pages cite short and the
  canonical full reference lives in `docs/ARCHITECTURE.md` §References (the works the package
  **implements / pins to** — Lalescu 2010, TurTLE 2022, van Hinsberg, Fornberg, the anterpolation
  lineage)."
- **Why it violates the rule:** `grep`ing the whole file for `§References`, `# References`, or any
  `@ref "References"` anchor finds nothing; the only candidate is §10's own
  "References (this section)" block (line 1032), which the file itself scopes explicitly to
  "this section" rather than to the document as a whole (and decision 19's Grafakos citation notes
  it is "cited by that anchor rather than by this section, and is kept in this list as the
  document's single Fourier-analysis reference" — an acknowledgment that this list is doing
  double duty as the document-wide bibliography without being named as one). A reader following
  `CLAUDE.md`'s pointer to "`docs/ARCHITECTURE.md` §References" to verify a docstring's inline
  citation is verbatim-consistent has no section of that name to navigate to.
- **Fix:** Either rename §10's "References (this section)" heading to something that documents it
  as the file-wide bibliography (and drop "this section" from its own heading), or add a
  short top-level "## References" section (or an explicit anchor) that `CLAUDE.md` and `@ref`
  links can target by the name they already use.

## Verified clean (spot-checked, no findings)

- The 206-method field / 122-method point-value parity baseline is stated consistently
  everywhere it recurs in §§2, 6, 10 and decisions 15, 16, 17, 27, 44, 49, 53, and matches
  `test/method_parity.jl`'s `@test sum(...) == 206` / `== 122` assertions.
- `FieldSpectralMultipliers`'s struct definition in `src/Fields.jl` has its `Canonical` type
  parameter last, as decisions 61 and 70 both claim ("the parameter goes last", "Canonical moved
  six places").
- `FieldTransformPlans{T, PF, PI, G, L, S}` in `src/Fields.jl` carries six type parameters and no
  tensor-order parameter, matching decision 76's claim that "`R` … no longer" appears.
- `transfer_order(grid::Grid3D, points::PointSet; tile_size = 4)` in `src/Interpolation.jl`
  matches decision 78's claim that the signature "leads with the grid."
- `Grid3D`'s inner constructor validates spacing against `domain_size ./ grid_size` as decision 45
  claims.
- The fourteen invariants (§2's "The invariants") are correctly counted and each is later
  developed in the section it points to; no invariant number is reused or skipped.
- Decisions 60–79 were read in full for internal consistency (dates, superseded-by markers,
  method-count deltas per decision, e.g. `Fields` 103→115→116→119→120→122, `Convolution`
  79→83→(+17 dispatch pairs), `Reductions` 119→123→124, `Points` 207→209→211→226) — all
  running totals check out arithmetically against the deltas stated in each entry.
- The `α(k)` (Parseval multiplicity) vs `α`/`β` (invariant-10 accumulation) glyph reuse, flagged
  by an earlier `/check-consistency` panel per `CLAUDE.md`, is glossed at first use in this file
  (line ~882–883) with the mode argument `(k)` distinguishing it; not re-flagged here as it is
  already a recorded, adjudicated decision.

---

## Fix-pass addendum (main thread, round 2) — closing Finding 2's LINE-ONLY

The round-2 verifier graded Finding 2 **LINE-ONLY**, correctly. The finding named two sites in
`ARCHITECTURE.md` but framed them as instances of a CLASS ("precisely the class the rubric singles
out by name: a lone ≤/·"), and the first pass fixed the two quoted lines without sweeping the class.
The verifier found a live survivor in a RENDERED docstring: `src/FieldAlgebra.jl:46`,
`` `mean(det, ·)` ``.

Fixed: the placeholder is replaced by a real call, `` `mean(det, A)` ``, which is what the sibling
`Reductions` docstrings already use.

Class re-swept across every rendered surface — `src/*.jl`, the four rationale docs, `docs/src/*.md`,
`docs/src/api/*.md`, and both Literate examples — for a backtick span containing an interpunct,
excluding `#` comment lines. **Zero remaining.** The two hits at `src/Reductions.jl:631,705` are
inside `#` comments, which are not rendered and are correctly out of scope, as the verifier itself
noted.

This is the second time in one battery that a finding naming two sites turned out to name a class;
it is the exact failure the "fix the class, not the line" rule exists for, and the verifier caught
both because it reads the finding rather than the diff.
