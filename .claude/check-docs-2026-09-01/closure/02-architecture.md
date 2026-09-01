RANGE: ac1226e4..HEAD

## Finding 1

- **Verdict:** HONORED
- **Evidence:** `git diff ac1226e4..HEAD -- docs/ARCHITECTURE.md` shows, inside decision 56
  (around line 3061-3067), the sentence "A `mightalias` guard would reject `sym!(A, A)` itself,
  whose target and source component views already have different footprints on one parent, and
  decision 39 made that case guard-free after measurement." is now immediately followed by:
  "**(FALSE, per decision 59: the target ``(i,j)`` and source ``(j,i)`` views select disjoint
  memory, so `mightalias` is `false` and would not reject the call. No guard is still the right
  answer, for decision 59's different reason. Marked here because this belief deferred the
  defect for a day.)**" This matches the finding's exact suggested remedy (a parenthetical
  correction note at decision 56, in the style of the log's other superseded-by annotations,
  naming decision 59 and stating the operational conclusion still holds for a different reason).
  The false claim at decision 56 no longer stands unqualified.
- **class_surfaces:** The finding's own text scopes the contradiction to exactly two locations
  inside `docs/ARCHITECTURE.md` — decision 56 (`docs/ARCHITECTURE.md:3061`) and decision 59
  (`docs/ARCHITECTURE.md:3196-3198`) — and names no other surface, sibling docstring, or
  convention elsewhere that would need sweeping; it is a single internal-contradiction defect,
  not a claimed class. Both named locations are addressed by the diff (decision 56 now carries
  the correction; decision 59's text is unchanged and was already correct). No other surface is
  implied by the finding's own words.
  (Incidental, not counted against this verdict since the finding never named it: `CLAUDE.md:2301`
  still repeats the uncorrected claim "it would have rejected `sym!(A, A)`" in its own roadmap
  prose — the finding did not point at `CLAUDE.md`, so this is not part of this finding's class
  under the enumerate-from-the-finding rule, but is worth flagging separately.)

## Finding 2

- **Verdict:** HONORED
- **Evidence:** Both quoted sites are fixed: line 1301 `` `lpnorm(·, Inf)` `` → `` `lpnorm` at
  ``p = \infty`` `` (verified at `docs/ARCHITECTURE.md:1304`, now a real code span plus a
  separate LaTeX math span, no interpunct-in-backticks); line 2698 `` `mean(φ, ·)` `` → "a mapped
  `mean`" (verified at `docs/ARCHITECTURE.md:2701`, interpunct placeholder removed entirely). The
  finding explicitly framed this as a CLASS ("precisely the class the rubric singles out by
  name"), and the banked file's own addendum records a round-2 sweep that found and fixed a
  survivor outside this lane's file, `src/FieldAlgebra.jl:46` (`` `mean(det, ·)` `` →
  `` `mean(det, A)` ``), confirmed present in `git diff ac1226e4..HEAD -- src/FieldAlgebra.jl`.
  Independently re-swept here: `grep -rnP '`[^`\n]*·[^`\n]*`' src/*.jl docs/*.md docs/src/*.md
  docs/src/api/*.md examples/*.jl examples/gpu/rocm/*.jl`, excluding `#` comment lines, returns
  zero hits; the same check for a lone `≤` in backticks also returns zero. The class is swept
  clean across every rendered surface named in the rubric.
- **class_surfaces:** The finding names the general rubric class ("a lone ≤/·" in backticks) but
  no specific sibling location beyond the two quoted lines; the two quoted sites
  (`docs/ARCHITECTURE.md:1301`, `docs/ARCHITECTURE.md:2698`) are both fixed, and an independent
  corpus-wide grep (not merely trusting the diff or the addendum) confirms no remaining instance
  of the flagged pattern anywhere in `src/*.jl`, the rationale docs, `docs/src/*.md`,
  `docs/src/api/*.md`, or the two Literate examples.

## Finding 3

- **Verdict:** HONORED
- **Evidence:** `docs/ARCHITECTURE.md:1032` changed from "**References (this section).**" to:
  "**References.** The canonical list for the WHOLE document — every section and every docstring
  cites into it, which is why the citation policy and the `check-docs` DOI cross-check both name
  it §References. It sits here because the transfer literature is its largest single block, not
  because its scope is this section." This is exactly the finding's first suggested remedy
  ("rename §10's 'References (this section)' heading … and drop 'this section' from its own
  heading"), plus an explanation binding the name "§References" (as `CLAUDE.md` uses it) to this
  location. Confirmed the section-header structure (`grep -n '^#' docs/ARCHITECTURE.md`) still
  places this bold lead-in inside `## 10. Interpolation and anterpolation`, i.e. it remains a
  bold paragraph rather than a distinct `##`/`###` heading with its own anchor — the fixer chose
  the "rename" option over the "add a real top-level heading" option, both of which the finding
  offered as acceptable alternatives.
- **class_surfaces:** The finding's location is singular — "`docs/ARCHITECTURE.md` as a whole (no
  '## References' or '§References' heading anywhere)" — naming only the one missing/mis-scoped
  heading and citing `CLAUDE.md`'s policy text as the source of the expectation, not as a second
  site needing edits. `CLAUDE.md`'s own uses of "§References" (lines 196, 499, 502, 505, 693) are
  the reader's *expectations*, not additional defect sites the finding asks to be swept — they are
  now satisfied by the renamed/explained heading rather than needing edits of their own. No other
  surface is implied by the finding's text.
