RANGE: ac1226e4..HEAD

Note: the task pointed at `.claude/check-docs-2026-09-01/02-architecture.md`, which does not
exist. The lane-01 file `.claude/check-docs-2026-09-01/01-architecture.md` is the only
architecture-hat findings file in that round's directory and is unambiguously the intended
target (its own header reads "Lane 01 — docs/ARCHITECTURE.md"), so it was graded.

## Finding 1

- **Verdict:** HONORED
- **Evidence:** `git diff ac1226e4..HEAD -- docs/ARCHITECTURE.md` at decision 56 (line ~3061-3066):
  the sentence "A `mightalias` guard would reject `sym!(A, A)` itself, whose target and source
  component views already have different footprints on one parent, and decision 39 made that case
  guard-free after measurement." now has an inserted parenthetical immediately after it: "**(FALSE,
  per decision 59: the target ``(i,j)`` and source ``(j,i)`` views select disjoint memory, so
  `mightalias` is `false` and would not reject the call. No guard is still the right answer, for
  decision 59's different reason. Marked here because this belief deferred the defect for a
  day.)**" — matches the requested fix (a superseded-by-style correction note at the decision-56
  site) essentially verbatim in intent and content.
- **class_surfaces:** The finding names exactly one contradiction pair — decision 56
  (`docs/ARCHITECTURE.md:3061`) vs. decision 59 (`docs/ARCHITECTURE.md:3196-3198`) — and does not
  claim or imply any further unmarked contradictions elsewhere in the decision log (it cites
  decisions 57/60/61 only as examples of the *correct*, already-used superseded-by convention, not
  as additional defect sites). The one named site is fixed in the style those examples set. No
  other surface is implied by the finding's own text, so there is nothing else to check as
  unswept.

## Finding 2

- **Verdict:** HONORED
- **Evidence:** Both quoted sites fixed. Line ~1301: `` magnitude via `lpnorm(·, Inf)`. `` →
  `` magnitude via `lpnorm` at ``p = \infty``. `` (the middle-dot placeholder removed from the
  backtick span; the argument is now stated in prose/math, matching the finding's suggested fix
  almost verbatim). Line ~2698: `` where `mean(φ, ·)` reduces it `` → `` where a mapped `mean`
  reduces it `` (again the placeholder dropped from the code span). Swept the class: `grep -n
  '`[^`]*·[^`]*`' docs/ARCHITECTURE.md` returns no matches post-fix — no other backtick span in the
  file carries a middle-dot placeholder, so this is not merely the two quoted lines patched but the
  pattern eliminated file-wide.
- **class_surfaces:** The finding names two explicit locations (`docs/ARCHITECTURE.md:1301` and
  `docs/ARCHITECTURE.md:2698`) and frames the defect as a character-class problem ("·" as
  placeholder-code) rather than naming any further sibling surface (no docstring or other doc page
  is named). Both named locations are fixed, and a file-wide grep for the same offending pattern
  in `docs/ARCHITECTURE.md` (the finding's own stated location) comes back empty, confirming the
  class was swept on the surface the finding scoped itself to.

## Finding 3

- **Verdict:** HONORED
- **Evidence:** `**References (this section).**` (§10, line 1032) → `**References.** The canonical
  list for the WHOLE document — every section and every docstring cites into it, which is why the
  citation policy and the `check-docs` DOI cross-check both name it §References. It sits here
  because the transfer literature is its largest single block, not because its scope is this
  section.` This is exactly Fix option 1 from the finding ("rename §10's 'References (this
  section)' heading to something that documents it as the file-wide bibliography ... and drop
  'this section' from its own heading"). Post-fix, `grep -n "§References" docs/ARCHITECTURE.md`
  now matches at line 1034 (self-referentially, right under the renamed heading), so a reader who
  greps the document for the term `CLAUDE.md` uses lands exactly on this block and is told
  explicitly that this is the target. `CLAUDE.md`'s own `§References` citations (lines 196, 499,
  502, 505, 693) are unchanged and still resolve to this now-correctly-labeled block.
- **class_surfaces:** The finding's location is `docs/ARCHITECTURE.md` as a whole (no
  `## References` heading anywhere) plus the single existing `**References (this section).**`
  block at line 1032; it names no sibling page or docstring as needing the same fix (the
  `CLAUDE.md` citation-policy quote is the *consumer* of the name, not a second site defining it).
  The one defining site was renamed and given the disambiguating cross-reference text the fix
  asked for; nothing else in the finding's own text names a second surface to sweep.
