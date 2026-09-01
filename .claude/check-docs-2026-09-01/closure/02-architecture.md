RANGE: ac1226e4..HEAD

## Finding 1

- **Verdict:** HONORED
- **Evidence:** `git diff ac1226e4..HEAD -- docs/ARCHITECTURE.md` shows decision 56 (around line
  3061-3067) now reads: "A `mightalias` guard would reject `sym!(A, A)` itself, whose target and
  source component views already have different footprints on one parent, and decision 39 made
  that case guard-free after measurement. **(FALSE, per decision 59: the target ``(i,j)`` and
  source ``(j,i)`` views select disjoint memory, so `mightalias` is `false` and would not reject
  the call. No guard is still the right answer, for decision 59's different reason. Marked here
  because this belief deferred the defect for a day.)** Rather than ship a check that might break
  a measured, load-bearing property, ..." — confirmed by direct `Read` of the current file at that
  location. This is exactly the finding's suggested remedy: a parenthetical correction note at
  decision 56, in the log's superseded-by style, naming decision 59, restating the correct fact,
  and noting the operational conclusion (no guard) still holds for the different reason. A reader
  who stops at decision 56 is no longer told the false claim unqualified.
- **class_surfaces:** The finding's own text scopes the contradiction to exactly two locations
  inside `docs/ARCHITECTURE.md` — decision 56 (line 3061) and decision 59 (lines 3196-3198) — and
  cites the log's *other* superseded-by annotations (decisions 57, 60, 61) only as evidence of a
  broken convention, not as additional sites to sweep. It names no sibling docstring, no other
  operator family, and no other "false claim left uncorrected" instance anywhere else in the
  document. Both named locations are addressed: decision 56 now carries the correction; decision
  59's text was already correct and is unchanged. Independently grepped `mightalias` across the
  whole tree (`docs/ARCHITECTURE.md:3064,3067,3177,3202-3203`, `CLAUDE.md:2301`) — `CLAUDE.md:2301`
  repeats the same old "would have rejected `sym!(A, A)`" framing uncorrected, but the finding
  never named or implied `CLAUDE.md` as a surface (it is scoped throughout to the ARCHITECTURE.md
  decision log's own self-containment convention), so this is noted but does not demote the
  verdict under the enumerate-from-the-finding rule.

## Finding 2

- **Verdict:** HONORED
- **Evidence:** Both originally quoted sites are fixed: `docs/ARCHITECTURE.md:1301` (now ~1304)
  `` `lpnorm(·, Inf)` `` → `` `lpnorm` at ``p = \infty`` `` (a real code span plus a separate LaTeX
  math span, no interpunct inside backticks); `docs/ARCHITECTURE.md:2698` (now ~2701)
  `` `mean(φ, ·)` `` → "a mapped `mean`" (placeholder removed). Both confirmed present verbatim in
  `git diff ac1226e4..HEAD -- docs/ARCHITECTURE.md`. The finding explicitly framed the defect as a
  CLASS ("precisely the class the rubric singles out by name"), and the round-2 fix
  (`git diff ac1226e4..HEAD -- src/FieldAlgebra.jl`) shows a survivor the first pass missed —
  `` `mean(det, ·)` `` → `` `mean(det, A)` `` at `src/FieldAlgebra.jl:46` — closed in commit
  `bd86f4cc`. Independently re-swept here with a Python regex over every backtick span in
  `src/*.jl`, `docs/*.md`, `docs/src/*.md`, `docs/src/api/*.md`, `examples/*.jl` and
  `examples/**/*.jl` for a literal `·` inside backticks: exactly two hits remain,
  `src/Reductions.jl:631` and `src/Reductions.jl:705`, both confirmed by direct read to be
  full-line `#` comments (not rendered as prose — this is plain `src/` code, not a Literate
  example), so they are correctly out of scope per the rubric's exemption. Zero rendered-surface
  survivors.
- **class_surfaces:** The finding names the general rubric class ("a lone ≤/·" in backticks,
  quoting `CLAUDE.md`'s rule directly) rather than a fixed site list, so the class is exactly what
  a corpus-wide grep enumerates. The independent sweep above (same surface set the rubric's rule
  4(c)/`CLAUDE.md` doc-battery instructions name: `src/*.jl`, the four rationale docs,
  `docs/src/*.md`, `docs/src/api/*.md`, both Literate examples) confirms no remaining instance in
  any rendered surface.

## Finding 3

- **Verdict:** HONORED
- **Evidence:** `docs/ARCHITECTURE.md:1032` changed from "**References (this section).**" to:
  "**References.** The canonical list for the WHOLE document — every section and every docstring
  cites into it, which is why the citation policy and the `check-docs` DOI cross-check both name
  it §References. It sits here because the transfer literature is its largest single block, not
  because its scope is this section." — confirmed by direct read of the current file and by
  `git diff ac1226e4..HEAD -- docs/ARCHITECTURE.md`. This is the finding's first suggested remedy
  ("rename §10's 'References (this section)' heading ... and drop 'this section' from its own
  heading"), with an added sentence explicitly binding the name "§References" to this location —
  closing the "reader has no section of that name to navigate to" gap. Checked decision 19's
  adjacent Grafakos entry (line ~1050, "It is cited by that anchor rather than by this section, and
  is kept in this list as the document's single Fourier-analysis reference") for consistency with
  the rename: it still reads correctly against the new framing (the list is now explicitly
  document-wide, and the Grafakos note's "this list"/"this section" phrasing is unaffected).
- **class_surfaces:** The finding's location is singular by its own statement — "`docs/
  ARCHITECTURE.md` as a whole (no '## References' or '§References' heading anywhere)" — naming the
  one missing/mis-scoped heading. It cites `CLAUDE.md`'s citation-policy prose (lines 196, 499,
  502, 505, 693) only as the source of the reader's expectation, not as additional edit sites — and
  those lines require no change since they already say "§References" and now correctly resolve.
  Grepped `§References` and `References (this section)` across the tree: no other doc page or
  docstring names a differently-scoped "§References" target, and the old "(this section)" phrasing
  is gone from `docs/ARCHITECTURE.md`. No unswept surface implied by the finding's own words. Note:
  the fixer took the "rename as bold lead-in" branch rather than "add a real `##` heading with its
  own anchor" — both were offered by the finding as equally valid fixes, so this is not a
  deficiency, only a recorded choice of branch.
