# Lane 00 — deterministic guards, DOI cross-check, argument coverage

Run 2026-09-01. `guards.sh` exited 1 on the first run and 0 after the fixes below.
`doi_crosscheck.py` exited 0; `argcov.jl` reported 0 candidates.

## Finding 1

- **Check:** 4 (formatted — notation idiom).
- **Location:** `src/DifferentialOperators.jl:1179`, `docs/ARCHITECTURE.md:4050`,
  `docs/FORMALIZATION.md:256`.
- **Quote:** ``\hat u(k) = \frac{\mathrm{i}\,a(k) \times \hat w(k)}{\lvert a(k)\rvert^{2}}``
- **Rule:** CLAUDE.md §Style — the thin space ``\,`` is reserved for the differential
  ``\,\mathrm{d}x``; between adjacent factors it is gratuitous and doubles the space TeX already
  sets. `guards.sh` scans this as a must-be-empty class.
- **Fix:** ``\mathrm{i}\,a`` → ``\mathrm{i} a`` (a plain space, never deletion). All three sites are
  decision 77's `inverse_curl` formula, so this is ONE class carried on three surfaces — swept
  together, which is the "fix the class, not the line" rule.
- **Status:** FIXED, all three. Re-scan clean.

## Finding 2

- **Check:** 4 (formatted — sentence openers).
- **Location:** `src/Fields.jl:1392`.
- **Quote:** "…is what keeps the transforms allocation-free. `reshape` on an `Array` returns a new
  `Array` sharing the data…"
- **Rule:** CLAUDE.md §Style — a sentence opens with a capitalized ordinary word, never a lowercase
  code identifier; the fix is to REWORD, never to capitalize the binding (its name is lowercase by
  nature).
- **Fix:** "A `reshape` of an `Array` returns a new `Array` sharing the data".
- **Status:** FIXED. Scan now reports 0 for the class.

## Finding 3

- **Check:** 4 (formatted — no horizontal scroll).
- **Location:** `src/Convolution.jl:1311` (91 columns) and `:1412` (99 columns).
- **Quote:** `_exponential_convolution_modes!(backend, destination, source, multipliers, coefficient,`
- **Rule:** CLAUDE.md §Style — a rendered docstring signature does not auto-wrap, so hand-wrap it with
  a hanging indent under the first argument, ≤ ~88 source columns.
- **Fix:** one further break in each, hanging indent preserved. Both are decision 79's kernel-pair
  helpers, added 2026-08-30 — the wrap was one argument short of the limit when written.
- **Status:** FIXED, both. Scan now reports 0.

## Verified clean (no finding)

Indented markdown tables; neutral register (`knob`/`tweak`); bare-index ``\partial_i``; unbraced
fractions; ``\!`` before a fixed-size delimiter; the doubled negative thin; ``\mathbb`` on a digit;
`@ref` abutting a code span. All must-be-empty, all empty.

**DOI cross-check:** 7 DOIs in docstrings, 13 in §References, **0 missing**. Six §References DOIs are
cited by no docstring, which the script reports as information rather than a defect — a design doc may
legitimately be a reference's only citer.

**Argument coverage:** **0** undocumented-argument candidates in the bulleted form. 23 thin allocating
wrappers, 108 internal `_`-prefixed helpers and 69 fewer-than-three-argument docstrings exempted by
the rubric's three named exemptions.

## Triage — heuristic hits read and dismissed with reason

- `src/Convolution.jl:347` "formula in backticks": the span is a real Julia call,
  `radial_kernel(k2 -> exp(-ν * k2 * Δt), …)`, whose lambda legitimately contains `ν`. Backticks are
  correct; this is the recorded false positive.
- `docs/ARCHITECTURE.md:381` "formula in backticks": the line is the rule text quoting its own
  anti-pattern (`⟨f,g⟩` shown as what NOT to write). Recorded false positive.
- `docs/src/notation.md:20` ``\left``/``\right``: the glossary row that documents the ban and must
  spell the banned form to do so. Recorded false positive.

---

## Fix-pass addendum (main thread, round 3) — closing Finding 2's LINE-ONLY

The round-3 verifier graded Finding 2 **LINE-ONLY**, and it was right about something I had asserted
without checking. My round-1 note claimed the sentence-opener class was clean because `guards.sh`
reported 0 for it. **`guards.sh`'s scan for that class is scoped to `src/*.jl` only** — line 77 —
while the command's own readable source-of-truth spells it `grep -rnE '\. (`[a-z]|``)' src/*.jl
$DOCS_MD`. The script is NARROWER THAN ITS OWN SPEC, and the doc pages had never been scanned for
this rule at all. The verifier found three survivors by scanning what the rule governs rather than
what the script covers.

Swept properly. Running the documented scan over every rendered surface — the four rationale docs,
`docs/src/*.md`, `docs/src/api/*.md`, and both Literate examples — with the documented exemptions
applied (list items, `#` comments, `e.g.`/`i.e.`/`cf.`/`incl.` abbreviations, end-of-line
``\checkmark`` markers, and a math-formula opener judged separately) leaves **19 genuine
violations**, all now reworded to lead with an ordinary capitalized word, never by capitalizing the
binding:

- `docs/ARCHITECTURE.md` — 11 (lines 240, 2466, 2513, 2746, 2826, 3631, 3677, 3833, 3850, 4029, 4150)
- `docs/PERFORMANCE.md` — 5 (1182, 1517, 1618, 2113, 2466)
- `docs/TESTING.md` — 2 (410, 432)
- `docs/FORMALIZATION.md` — 1 (113)

Re-scan after the sweep: **0 remaining on every doc surface, and 0 in `src/`**.

**Instrument finding, reported not silently fixed** (instruments are frozen; a change to one is its
own deliberate commit): `guards.sh:77` should scan `$DOCS_MD` alongside `src/*.jl`, as the command
documentation says it does. Until it does, its "ok" for this class covers `src/` only — and a check
that is narrower than it appears is worse than an absent one, because it is read as coverage. This is
the same class of defect the instrument's own history records: a scan run with `| head -5` that
reported five hits when there were thirty-one.

---

## Fix-pass addendum (main thread, round 4)

Two LINE-ONLY verdicts, one honoured and one dismissed with reason.

### Finding 2 — the sentence-opener class: MY sweep was narrower than the rule

Round 3 claimed "0 remaining on every doc surface". Wrong, and wrong in the exact way I had just
criticised `guards.sh` for one commit earlier. My scan matched
`` \.\s+`[a-z][A-Za-z0-9_!./]*` `` — a character class that excludes parentheses, commas, spaces and
`∘`, so any span holding a CALL or a multi-word row name slipped through silently. The verifier found
two survivors; the corrected pattern `` \.\s+`[a-z][^`]*` `` finds three:

- `docs/ARCHITECTURE.md:1017` — `` `wrap!(points, grid)` `` → "The call `wrap!(points, grid)`"
- `docs/ARCHITECTURE.md:3279` — `` `weighted_inner(f, g, w)` `` → "The reduction `weighted_inner(…)`"
- `docs/PERFORMANCE.md:1496` — `` `convolve! vector ∘ radial` `` → "The row `convolve! vector ∘ radial`"

Re-scan with the corrected pattern: **0**. The lesson is the one this battery keeps re-teaching — a
scan is only as wide as its pattern, and reporting its silence as coverage is how a class survives a
sweep that claims to have closed it. I did to my own scan what `guards.sh` does to this rule.

### Finding 1 — the fourth thin-space site: DISMISSED with reason

`src/DifferentialOperators.jl:576` restates the `inverse_curl` formula with ``\mathrm{i}\,a`` in a
plain `#` comment above `_inverse_curl_kernel!`. It is **not a defect**: CLAUDE.md exempts `#`
comments from the rendering rules twice over — "`#` comments are exempt — not rendered" in the
check-docs surface list, and "Plain `#` code comments stay Unicode (they are not rendered)" in
§Style. The thin-space rule is a rule about RENDERED math spacing, and nothing renders that line.

This is consistent with what the examples lane did rather than in tension with it: there I fixed two
`##` code comments for the `L` glyph collision, because one symbol meaning two things is a
COMPREHENSION defect that a reader of the code meets whether or not it renders. A gratuitous thin
space in an unrendered comment has no reader-visible effect at all. Semantic defects reach into
comments; typographic ones do not.
