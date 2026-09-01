RANGE: ac1226e4..HEAD

## Finding 1

- **Verdict:** HONORED
- **Evidence:** `git diff ac1226e4..HEAD` shows all three sites fixed:
  - `src/DifferentialOperators.jl:576-577` (comment, exempt — see below) — untouched, but the
    docstring/rendered sites are what count:
  - `docs/ARCHITECTURE.md`: `` \hat u = \mathrm{i}\,a\times\hat w/... `` → `` \hat u = \mathrm{i} a\times\hat w/... `` (two occurrences, decision-77 prose entry and the `inverse_curl`
    formula block).
  - `docs/FORMALIZATION.md`: `` \\hat u(k) = \\frac{\\mathrm{i}\\,a(k) \\times ... `` →
    `` \\hat u(k) = \\frac{\\mathrm{i} a(k) \\times ... ``.
  - Re-ran the guard's own class scan (`hard "gratuitous thin space (src)"` /
    `"(docs)"` from `.claude/commands/check-docs/guards.sh`) directly:
    `grep -rnP '\\\\,(?!\\\\mathrm\{d\})' src` → 0 hits;
    `grep -nP '\\,(?!\\mathrm\{d\})' <DOCS_MD files>` → 0 hits. Both are the exact class-wide
    checks the fixer's own status line claims ("Re-scan clean"), verified independently, not
    merely trusted from the banked note.
  - The one remaining `\mathrm{i}\,` instance found by grep
    (`src/DifferentialOperators.jl:576`) is inside a `#` code comment, which CLAUDE.md's Style
    section explicitly exempts from the math-rendering rules ("Plain `#` code comments stay
    Unicode (they are not rendered)"), and the guard's own thin-space regex is written against
    the doubled-backslash docstring form, which a single-backslash comment does not match — so
    this is not a missed instance of the class, it is outside the class by the rule's own
    scope.
- **class_surfaces:** The finding names three sites verbatim (src:1179, ARCHITECTURE.md:4050,
  FORMALIZATION.md:256) and calls them "decision 77's `inverse_curl` formula... swept
  together." All three named surfaces are confirmed fixed in the diff. No further surface is
  implied by the finding's text (it explicitly scopes to "this ONE class" on "three surfaces"),
  and the guard's own class-wide regex scan (which covers every `src/*.jl` and every doc page,
  not just the three named lines) independently confirms zero remaining instances in any
  rendered/docstring surface. Fully swept.

## Finding 2

- **Verdict:** HONORED
- **Evidence:** `git diff ac1226e4..HEAD -- src/Fields.jl`:
  ```
  -first, is what keeps the transforms allocation-free. `reshape` on an `Array` returns a new `Array`
  +first, is what keeps the transforms allocation-free. A `reshape` of an `Array` returns a new `Array`
  ```
  Reworded per the rule (no capitalization of the binding, ordinary word leads). Independently
  re-ran the guard's own soft heuristic for this exact class
  (`grep -rnE '\. (\`[a-z]|\`\`)' src/*.jl | grep -vE ':[0-9]+:[[:space:]]*#'`) — 0 hits across
  the whole `src/` tree, confirming no other sentence in any docstring opens on a lowercase
  code identifier immediately after a period.
- **class_surfaces:** The finding is a single quoted site (`src/Fields.jl:1392`) citing a
  general CLAUDE.md style rule ("a sentence opens with a capitalized ordinary word... never a
  lowercase code identifier"), not a named family of sibling sites. The rule itself is
  general-purpose, so the relevant "class" is every sentence-opener violation in every
  docstring, not a specific operation family. The guard's soft heuristic scan (which greps all
  of `src/*.jl`, not just Fields.jl) returned 0, confirming the class is swept package-wide, not
  merely at the one quoted line.

## Finding 3

- **Verdict:** HONORED
- **Evidence:** `git diff ac1226e4..HEAD -- src/Convolution.jl` shows both signatures rewrapped
  with an added line break, hanging indent preserved:
  - `_exponential_convolution_modes!` docstring signature (originally :1311, now split into three
    lines instead of two).
  - `_exponential_combination_modes!` docstring signature (originally :1412, same treatment).
  Measured current column widths directly: all continuation lines now ≤86 columns (was: the
  finding's own quote shows the un-wrapped line was column-91/99). Independently re-ran the
  guard's own class-wide check (`soft "wide docstring signature (>88)"` from guards.sh — an awk
  scan over all 9 `src/*.jl` files for indented docstring signature lines exceeding 88 columns):
  0 hits across the entire package, not just the two named sites.
- **class_surfaces:** The finding names two sites (`src/Convolution.jl:1311`, `:1412`) and
  attributes both to "decision 79's kernel-pair helpers... the wrap was one argument short of
  the limit when written" — i.e. it scopes itself to these two specific, related signatures
  rather than claiming a package-wide pattern. Both named sites are confirmed fixed. The
  guard's own class-wide scan over every docstring signature in every `src/*.jl` file (not
  merely Convolution.jl) independently confirms 0 remaining >88-column docstring signatures
  anywhere in the package, so even reading "class" maximally broadly (any wide docstring
  signature, not just this decision's two), the sweep is complete.

## Overall

All three findings in this lane's banked file are genuinely fixed at their quoted sites, and for
each, an independent re-run of the guard script's own class-wide (not line-specific) checks
confirms zero remaining instances of the pattern anywhere in `src/` and the doc pages scanned by
`guards.sh`. `bash .claude/commands/check-docs/guards.sh` currently exits 0 with all 14
must-be-empty scans clean, and the two remaining triage (soft/heuristic) hits are exactly the two
documented false positives the banked file itself records as dismissed-with-reason
(`src/Convolution.jl:347` and `docs/ARCHITECTURE.md:381`), with the third recorded false positive
(`docs/src/notation.md:20`) also present and consistent with the ban-documenting exemption. No
new defects, no scope creep, no laundering — the fixer edited the claim sites directly rather than
softening or deleting the surrounding prose.
