RANGE: ac1226e4..HEAD

## Finding 1

- **Verdict:** HONORED
- **Evidence:** `git diff ac1226e4..HEAD -- src/DifferentialOperators.jl docs/ARCHITECTURE.md docs/FORMALIZATION.md` shows all three named sites changed identically (the gratuitous `\,` between `\mathrm{i}` and `a` dropped to a plain space):
  - `src/DifferentialOperators.jl:1179`: `` \hat u = \mathrm{i}\,a\times\hat w/\lvert a\rvert^{2} `` → `` \mathrm{i} a\times\hat w/\lvert a\rvert^{2} ``
  - `docs/ARCHITECTURE.md:4050`: `` \frac{\mathrm{i}\,a\times\hat w}{\lvert a\rvert^{2}} `` → `` \frac{\mathrm{i} a\times\hat w}{\lvert a\rvert^{2}} ``
  - `docs/FORMALIZATION.md:256`: `` \\mathrm{i}\\,a(k) `` → `` \\mathrm{i} a(k) ``
  Independently re-ran the finding's own cited check, `guards.sh`'s must-be-empty scans
  (`grep -rnP '\\\\,(?!\\\\mathrm\{d\})' src` and `grep -rnP '\\,(?!\\mathrm\{d\})'` over the DOCS_MD
  set): **both return empty**, confirming the rendered-surface class this specific check governs is
  clean, not just the three quoted lines.
  One textual survivor exists but is out of the check's scope: `src/DifferentialOperators.jl:576`, a
  `#` comment immediately above `_inverse_curl_kernel!` restating the same formula
  (`` \mathrm{i}\,a\times\hat w/|a|^2 ``, single backslash, unescaped). `guards.sh`'s src scan
  deliberately matches only `\\,` (the double-backslash form a `"""`-docstring's escaping produces),
  not a comment's single-backslash LaTeX-lookalike text — the same "comments are not rendered, and are
  correctly out of scope" reasoning this repo's own round-2 fix (commit `bd86f4cc`) already applied to
  an analogous interpunct survivor in `src/Reductions.jl`. Since the finding's own three named sites
  are exactly "decision 77's `inverse_curl` formula" reproduced across the docstring/ARCHITECTURE/
  FORMALIZATION trio, and does not claim the implementation's own explanatory comment as a fourth
  member, and since that comment is not a rendered surface under CLAUDE.md's "plain `#` code comments
  stay Unicode (they are not rendered)" carve-out, this is not counted against the verdict.
- **class_surfaces:** The finding's own location list names exactly three surfaces —
  `src/DifferentialOperators.jl:1179`, `docs/ARCHITECTURE.md:4050`, `docs/FORMALIZATION.md:256` — all
  three re-derivations of one formula (decision 77's `inverse_curl`), explicitly framed as "ONE class
  carried on three surfaces." No other rendered surface carries this formula (checked: `grep -rn
  "mathrm{i}" src docs` finds no fourth docstring/doc-page occurrence). All three are swept.

## Finding 2

- **Verdict:** LINE-ONLY
- **Evidence:** `git diff ac1226e4..HEAD -- src/Fields.jl` shows the one quoted line fixed by reword:
  "…is what keeps the transforms allocation-free. `reshape` on an `Array` returns a new `Array` sharing
  the data…" → "…allocation-free. A `reshape` of an `Array` returns a new `Array` sharing the data…".
  But the rule invoked — CLAUDE.md §Style, "a sentence opens with a capitalized ordinary word, never a
  lowercase code identifier" — is a general, package-wide prose convention, not scoped to
  `src/Fields.jl`, and `guards.sh` has **no hard (must-be-empty) check for it at all**: the only related
  scan is the *soft* heuristic `sentence opens with code/math`
  (`grep -rnE '\. (\`[a-z]|\`\`)' src/*.jl | grep -vE ':[0-9]+:[[:space:]]*#'`), which is itself scoped
  only to `src/*.jl` and never touches the `docs/` pages at all. Re-running that soft scan on `src/*.jl`
  does return empty, but independently searching the doc pages the finding's rule equally governs
  (`docs/ARCHITECTURE.md`, `docs/FORMALIZATION.md`, `docs/TESTING.md`, `docs/PERFORMANCE.md`,
  `docs/src/**`) for the same pattern, filtering bullet/list items and `e.g./i.e.` (both CLAUDE.md's
  own stated exemptions) turns up multiple live, non-exempt survivors in plain prose paragraphs:
  - `docs/FORMALIZATION.md:113` — "…where a mode's partner lies in the same plane. `` `reality_residual` `` measures the departure," — a bold-lead prose paragraph ("**The reality condition (decision 71).**"), not a bullet, not `e.g./i.e.`.
  - `docs/PERFORMANCE.md:1517` — "…(2026-08-30, from IT's codegen report). `` `weighted_inner` `` was GPU-first: …" — a bold finding-label prose paragraph ("**(ac) …**"), not a bullet.
  - `docs/PERFORMANCE.md:2113` — "…a comparison whose two sides share…" context: "…decision 72's speedup against a sibling sharing the same code path. `` `weighted_inner` `` was serial from the day it shipped…" — same class, plain prose ("**(ag) …**").
  So the class (sentences opening with a lowercase code identifier, package-wide) was fixed at the one
  cited line and not swept — the closure note claiming "the class-level scan… clean" conflated a
  narrower `src/*.jl`-only soft heuristic with the general rule the finding actually cites, and never
  ran a scan over the doc pages at all.
- **class_surfaces:** The finding's own rule text is generic — "CLAUDE.md §Style" naming a package-wide
  sentence-opener convention, with only one example location given (`src/Fields.jl:1392`). The implied
  class-surfaces are every rendered prose surface the same style rule governs: every `src/*.jl`
  docstring (swept — soft scan clean) and every `docs/*.md` / `docs/src/**.md` page (NOT swept — three
  live counterexamples quoted above, found by a five-minute grep). LINE-ONLY by the instrument's own
  "an empty or vague answer demotes" rule is not needed here since concrete surviving instances are
  quoted directly.

## Finding 3

- **Verdict:** HONORED
- **Evidence:** `git diff ac1226e4..HEAD -- src/Convolution.jl` shows both signatures re-wrapped with
  one additional line break each, hanging indent under the first argument preserved:
  - `_exponential_convolution_modes!` (was `src/Convolution.jl:1311`): `backend, destination, source, multipliers, coefficient,` / `offset_scale, offset_data, α, β, fibres, mode_size)` (91 cols) → three lines, `backend, destination, source, multipliers,` / `coefficient, offset_scale, offset_data,` / `α, β, fibres, mode_size)`.
  - `_exponential_combination_modes!` (was `:1412`): same shape, three lines.
  Independently re-ran the finding's own cited check — the "wide docstring signature (>88)" awk scan
  from `guards.sh`, across all nine audited `src/` files — and it returns **zero** hits, confirming the
  class (not merely the two quoted lines) is clean.
- **class_surfaces:** The finding names exactly two sites, `src/Convolution.jl:1311` and `:1412`, and
  explicitly scopes the class to "decision 79's kernel-pair helpers, added 2026-08-30" — it does not
  claim other files or other decisions carry the same overflow. The guard's repo-wide awk re-scan
  (independently re-run above, not merely trusted from the banked note) confirms no docstring signature
  in any of the nine `src/` files exceeds 88 columns, so the class as the finding frames it is fully
  swept.
