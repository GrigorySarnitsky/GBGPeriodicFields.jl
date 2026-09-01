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
  defect for a day.)**" (confirmed by direct `Read` of the current file at that location). This
  matches the finding's exact suggested remedy — a parenthetical correction note at decision 56,
  in the style of the log's other superseded-by annotations, naming decision 59 and stating the
  operational conclusion still holds for a different reason. The false claim at decision 56 no
  longer stands unqualified for a reader who stops there.
- **class_surfaces:** The finding's own text scopes the contradiction to exactly two locations
  inside `docs/ARCHITECTURE.md` — decision 56 (`docs/ARCHITECTURE.md:3061`) and decision 59
  (`docs/ARCHITECTURE.md:3196-3198`) — and explicitly contrasts this case with the log's *other*
  superseded-by annotations (decisions 57, 60, 61), citing those as evidence of the convention
  being broken here, not as additional sites this finding asks to be swept. It names no sibling
  docstring, no other operator family, and no other "false claim left uncorrected" instance. Both
  named locations are addressed: decision 56 now carries the correction; decision 59's text is
  unchanged and was already correct. No other surface is implied by the finding's own words, so
  there is no unswept class to demote on.
  (Noted but not counted against this verdict, since the finding never pointed at it under the
  enumerate-from-the-finding rule: `CLAUDE.md`'s own decision-59 summary, around the roadmap/
  decision-log mirror text, still paraphrases the old `sym!(A, A)` guard-rejection framing without
  the same correction. This is outside `docs/ARCHITECTURE.md`, which is the only file this finding
  names, so it does not change the verdict.)

## Finding 2

- **Verdict:** HONORED
- **Evidence:** Both quoted sites are fixed: line 1301 `` `lpnorm(·, Inf)` `` → `` `lpnorm` at
  ``p = \infty`` `` (now a real code span plus a separate LaTeX math span, no interpunct-in-
  backticks, confirmed at `docs/ARCHITECTURE.md:1304` in the current file); line 2698
  `` `mean(φ, ·)` `` → "a mapped `mean`" (interpunct placeholder removed entirely, confirmed at
  `docs/ARCHITECTURE.md:2701`). The finding explicitly framed this as a CLASS ("precisely the
  class the rubric singles out by name"), and the banked findings file's own addendum records a
  round-2 fix pass that found and closed a survivor outside this lane's own file,
  `src/FieldAlgebra.jl:46` (`` `mean(det, ·)` `` → `` `mean(det, A)` ``), confirmed present in
  `git diff ac1226e4..HEAD -- src/FieldAlgebra.jl`. Independently re-swept here (not trusting the
  addendum's own "zero remaining" claim): grepped every file under `src/*.jl`, `docs/*.md`,
  `docs/src/*.md`, `docs/src/api/*.md`, `examples/*.jl` and `examples/gpu/rocm/*.jl` for a
  backtick span containing `·`, then filtered by hand for lines starting `#` (comments, exempt per
  the rubric). Two hits remain, both inside `#` comment lines and therefore correctly out of
  scope: `src/Reductions.jl:631` and `src/Reductions.jl:705`. Zero rendered-surface survivors.
- **class_surfaces:** The finding names the general rubric class ("a lone ≤/·" in backticks,
  quoted directly from `CLAUDE.md`'s own rule) rather than a fixed list of sibling locations, so
  the class is exactly what a corpus grep can enumerate. The two quoted sites
  (`docs/ARCHITECTURE.md:1301`, `docs/ARCHITECTURE.md:2698`) are both fixed, and the independent
  corpus-wide sweep above confirms no remaining rendered instance of the flagged pattern anywhere
  in `src/*.jl`, the four rationale docs, `docs/src/*.md`, `docs/src/api/*.md`, or the two
  Literate examples — the exact surface set the rubric's rule 4(c)/CLAUDE.md doc-battery
  instructions name as in scope.

## Finding 3

- **Verdict:** HONORED
- **Evidence:** `docs/ARCHITECTURE.md:1032` changed from "**References (this section).**" to:
  "**References.** The canonical list for the WHOLE document — every section and every docstring
  cites into it, which is why the citation policy and the `check-docs` DOI cross-check both name
  it §References. It sits here because the transfer literature is its largest single block, not
  because its scope is this section." (confirmed by direct `Read` of the current file). This is
  exactly the finding's first suggested remedy ("rename §10's 'References (this section)' heading
  to something that documents it as the file-wide bibliography, and drop 'this section' from its
  own heading"), plus an added sentence binding the name "§References" (as `CLAUDE.md`'s citation
  policy uses it) to this specific location, closing the "reader has no section of that name to
  navigate to" gap the finding raised. `grep -n '^#'` over the current file confirms this bold
  lead-in structurally still sits inside `## 10. Interpolation and anterpolation` (a bold
  paragraph, not a distinct heading with its own anchor) — the fixer took the "rename" branch of
  the finding's two offered alternatives rather than "add a real top-level heading," which the
  finding accepted as equally valid.
- **class_surfaces:** The finding's location is singular by its own statement — "`docs/
  ARCHITECTURE.md` as a whole (no '## References' or '§References' heading anywhere)" — naming
  only the one missing/mis-scoped heading, and citing `CLAUDE.md`'s citation-policy prose (lines
  196, 499, 502, 505, 693) purely as the source of the reader's expectation that such a heading
  exists, not as additional sites the finding asks to be edited. Those `CLAUDE.md` lines are now
  satisfied by the renamed/explained heading rather than requiring edits of their own, and the
  finding names no other doc page or docstring expecting a "§References" target. No unswept
  surface is implied by the finding's own words.
