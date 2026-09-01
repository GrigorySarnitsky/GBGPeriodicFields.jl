RANGE: ac1226e4..HEAD

# Verify-fixes: 01-guards.md (guards hat)

## Finding 1

**Verdict: LINE-ONLY**

- **Quoted claim:** "All three sites are decision 77's `inverse_curl` formula, so this is ONE class
  carried on three surfaces — swept together, which is the 'fix the class, not the line' rule."
- **Evidence the three named sites are fixed** (`git diff ac1226e4..HEAD`):
  ```
  -    given ``w``, as one coefficientwise pass ``\hat u = \mathrm{i}\,a\times\hat w/\lvert a\rvert^{2}``
  +    given ``w``, as one coefficientwise pass ``\hat u = \mathrm{i} a\times\hat w/\lvert a\rvert^{2}``
  -(\nabla\times)^{-1}\hat w(k) = \frac{\mathrm{i}\,a\times\hat w}{\lvert a\rvert^{2}},
  +(\nabla\times)^{-1}\hat w(k) = \frac{\mathrm{i} a\times\hat w}{\lvert a\rvert^{2}},
  -\\hat u(k) = \\frac{\\mathrm{i}\\,a(k) \\times \\hat w(k)}{\\lvert a(k)\\rvert^{2}} ,
  +\\hat u(k) = \\frac{\\mathrm{i} a(k) \\times \\hat w(k)}{\\lvert a(k)\\rvert^{2}} ,
  ```
  `src/DifferentialOperators.jl` (docstring, ~1179), `docs/ARCHITECTURE.md` (~4050),
  `docs/FORMALIZATION.md` (~256) all converted `\mathrm{i}\,a` → `\mathrm{i} a`. These three are genuinely fixed.
- **But the class is bigger than the finding's own enumeration, and a fourth surface restating the
  identical formula was left untouched.** `src/DifferentialOperators.jl:576`, a plain `#` comment
  immediately above `_inverse_curl_kernel!` (the same operator, same decision 77), still reads:
  `# them. The mode value is ``\mathrm{i}\,a\times\hat w/|a|^2``, and the denominator is the` —
  confirmed present at `ac1226e4` (`git show ac1226e4:src/DifferentialOperators.jl | sed -n '576p'`)
  and unchanged through HEAD. This is the exact same gratuitous ``\,`` before `a` in the exact same
  formula, in the exact same file, ~600 lines from the fixed docstring.
  `guards.sh`'s "gratuitous thin space (src)" hard check does not catch it only because it greps for
  the doubled backslash `\\\\,` that a Julia string literal needs to escape — a plain `#` comment
  needs no such escaping and so is invisible to that particular pattern, not because the comment is
  outside the rule's scope (CLAUDE.md exempts comments from the *render* requirement, not from LaTeX
  idiom once LaTeX-looking notation is written there, and this file already writes double-backtick
  math in other comments around it). The finding's own framing — "decision 77's `inverse_curl`
  formula … swept together" — names the class as every restatement of this formula, and this
  restatement was not found.
- **class_surfaces** (from the finding's own words: "decision 77's `inverse_curl` formula" carried on
  however many surfaces it appears):
  - `src/DifferentialOperators.jl:1179` (docstring) — swept (fixed).
  - `docs/ARCHITECTURE.md:4050` — swept (fixed).
  - `docs/FORMALIZATION.md:256` — swept (fixed).
  - `src/DifferentialOperators.jl:576` (the `_inverse_curl_kernel!` comment restating the same
    formula) — **NOT swept**, identical defect still present at HEAD.

## Finding 2

**Verdict: LINE-ONLY**

- **Quoted claim (as it stood after this file's own round-3 addendum):** "Re-scan after the sweep:
  **0 remaining on every doc surface, and 0 in `src/`**," following a 19-line reword sweep in commit
  `4b9c8a2d` across `ARCHITECTURE.md` (11), `PERFORMANCE.md` (5), `TESTING.md` (2),
  `FORMALIZATION.md` (1).
- **The specific quoted site (`src/Fields.jl:1392`) is fixed:**
  ```
  -is what keeps the transforms allocation-free. `reshape` on an `Array` returns a new `Array` sharing
  +is what keeps the transforms allocation-free. A `reshape` of an `Array` returns a new `Array`
  +sharing
  ```
  (verified against the diff; the sentence now opens "A `reshape`…").
- **The class was swept twice (round 1 nominally, round 3 for real) and the second sweep's own "0
  remaining" claim is still wrong.** Running the documented scan
  (`grep -nE '\. (\`[a-z]|\`\`)'` over every rationale doc, `docs/src/*.md`, `docs/src/api/*.md`, both
  Literate examples, filtered for comments/bullets/decision-log entries/abbreviations/checkmarks —
  exactly the exemption list the round-3 commit itself states) at HEAD still finds two genuine,
  unexempted violations, neither in the round-3 fixed-line list (ARCHITECTURE.md 240, 2466, 2513,
  2746, 2826, 3631, 3677, 3833, 3850, 4029, 4150; PERFORMANCE.md 1182, 1517, 1618, 2113, 2466):
  - `docs/ARCHITECTURE.md:1017` — plain body prose (§10, not a bullet, not a decision-log entry):
    "…proper, the wrap fused into the same pass. `wrap!(points, grid)` is the zero-term case kept as
    its own named verb: …" — a new sentence opening with a backtick code identifier.
  - `docs/PERFORMANCE.md:1496` — plain body prose inside a `**CPU …** (five rows).` paragraph:
    "…14.36 against 14.55. `convolve! vector ∘ radial` re-measures at 8.195 ms against the archive's
    8.277." — same defect.
  - (Checked and correctly excluded as false positives / exempt: `docs/ARCHITECTURE.md:3279` and
    `:3576` sit inside §13 decision-log entries 62 and 69, exempt by CLAUDE.md's explicit "a bullet /
    list item — including a §13 decision-log entry" exemption; the eleven `docs/FORMALIZATION.md`
    hits all end in the documented `` ``\checkmark`` `` marker or are `i.e.` abbreviations, both
    named exemptions; `docs/TESTING.md:153,178` are commas inside one flowing bulleted list item.)
  - `guards.sh` itself still reports 0 for "sentence opens with code/math" at HEAD, but only because
    its scan (line 77 of the script) remains scoped to `src/*.jl` and was never extended to
    `$DOCS_MD` — the exact instrument gap this file's own round-3 addendum diagnosed and reported as
    an open instrument finding rather than fixing. The manual sweep meant to compensate for that gap
    is itself incomplete.
- **class_surfaces** (from the finding's own words — "a sentence opens with a capitalized ordinary
  word… reword" is a corpus-wide rule, and the round-3 addendum itself names the class as "every
  rendered surface — the four rationale docs, `docs/src/*.md`, `docs/src/api/*.md`, and both Literate
  examples"):
  - `src/Fields.jl:1392` — swept (the quoted site, fixed).
  - The 19 lines named in the round-3 commit across `ARCHITECTURE.md`/`PERFORMANCE.md`/`TESTING.md`/
    `FORMALIZATION.md` — swept (fixed; spot-checked several, all now open on a capitalized word).
  - `docs/ARCHITECTURE.md:1017` — **NOT swept**, still violates.
  - `docs/PERFORMANCE.md:1496` — **NOT swept**, still violates.
  - `guards.sh:77`'s `$DOCS_MD` scope gap — reported as an open instrument finding, not closed (this
    part is honestly disclosed, not a hidden miss).

## Finding 3

**Verdict: HONORED**

- **Quoted claim:** both signatures in `src/Convolution.jl` (originally lines 1311 and 1412)
  rewrapped with one further break each, hanging indent preserved, "Scan now reports 0."
- **Evidence, both sites, from the diff:**
  ```
  -    _exponential_convolution_modes!(backend, destination, source, multipliers, coefficient,
  -                                    offset_scale, offset_data, α, β, fibres, mode_size)
  +    _exponential_convolution_modes!(backend, destination, source, multipliers,
  +                                    coefficient, offset_scale, offset_data,
  +                                    α, β, fibres, mode_size)
  ```
  and the matching change at the `_exponential_combination_modes!` docstring ~1412. Measured directly
  in the current file: the three wrapped lines are 78/75/60 and 86/75/60 columns — all ≤ 88.
- **Class swept, not just the line:** re-ran the exact class check
  (`awk '/^"""/{...} length>88{print FILENAME":"FNR}'` over all nine `src/*.jl` files, the same
  formula `guards.sh`'s "wide docstring signature (>88)" triage line uses) at HEAD — **0 hits**,
  confirming no docstring signature anywhere in `src/` currently exceeds the column limit, not only
  the two touched lines.
- **class_surfaces:** the finding names no sibling docstring or convention beyond "every rendered
  docstring signature ≤ ~88 columns" (CLAUDE.md's no-horizontal-scroll rule, corpus-wide); the
  independent full-corpus re-check above is the sweep and it is clean.
