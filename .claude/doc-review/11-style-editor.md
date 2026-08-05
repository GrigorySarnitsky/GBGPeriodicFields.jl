# Style / Consistency Review — Technical Copy-Editor Hat

Scope: the full reader-text consolidation of the rendered site (`manuscript-full.md`) plus the raw
built HTML under `docs/build/`. Focus: internal uniformity of notation, docstring skeleton, register,
and rendering fidelity (checked directly against the KaTeX/HTML source, not just the text
extraction).

---

## Finding 1 — Duplicate HTML `id` on the Fields API page (broken anchor permalinks)

- **Type:** typesetting / format
- **Severity:** major
- **Confidence:** high
- **Location(s):** `docs/build/api/Fields/index.html` — the `AbstractFieldPhysical` type docstring
  and the `AbstractFieldSpectral` type docstring, both on the "Fields" API page.
- **Description:** Both docstrings carry the identical admonition "A section owns its storage," and
  Documenter's heading-slugifier assigns them the **exact same generated id**:
  `id="A-section-owns-its-storage-62892ad948359268"`, verified to occur literally twice in the raw
  HTML (checked across every built page — this is the only duplicate `id` on the whole site). A
  duplicate `id` is invalid HTML, and in every browser an in-page anchor (`#A-section-owns-...`) and
  the admonition's own "Permalink" icon on the *second* occurrence both resolve to the *first*
  element, so the second admonition's permalink is silently broken. The `Points` page's analogous
  admonition (a single occurrence) does not collide with either.
- **Resolution hint:** Give the two admonitions distinct titles (they already say the same thing for
  two different types — one plausible fix is to keep the full admonition on one type and let the
  other's admonition body add a short discriminator to its title), or make one a one-line pointer to
  the other, consistent with the "one concept, one home" cross-referencing rule.

## Finding 2 — Bare code identifier inside a math span (`$FiberTensor2$`)

- **Type:** typesetting
- **Severity:** major
- **Confidence:** high
- **Location(s):** Architecture page, decision-log entry "`var`/`std` are scalar-only... the new
  covariance `cov`": *"The new `cov`... returns the symmetric covariance `<span>$FiberTensor2$</span>`
  of a vector section..."* (raw HTML: `<span>$FiberTensor2$</span>`).
- **Description:** Every other mention of `FiberTensor2` on the same page (five total) is correctly
  backticked as code. This one lone instance is wrapped in a bare `$...$` math span instead. Per the
  house rule ("a code identifier never sits inside a math span"), KaTeX will render this as the
  italic product of eleven single letters — "F i b e r T e n s o r 2" — not as the type name. This is
  exactly the silent-rendering-failure class the style guide singles out by name.
- **Resolution hint:** Change `$FiberTensor2$` to `` `FiberTensor2` ``.

## Finding 3 — Math inequality wrapped in backticks instead of LaTeX (`` `R ≥ 2` ``)

- **Type:** typesetting
- **Severity:** major
- **Confidence:** high
- **Location(s):** `api/Points` page, `TensorPointValues` type docstring: *"One tensor value of order
  `R` per point (`R ≥ 2`; use `ScalarPointValues`...)"* (raw HTML: `<code>R ≥ 2</code>`).
- **Description:** A formula (`R ≥ 2`) is placed in a code span rather than rendered as LaTeX. This is
  the exact example the house style calls out as a banned pattern ("never math that merely looks
  code-ish ([lo, hi), `R ≥ 2`, a lone ≤/·)"). It is also the *only* instance of `≥`/`≤` inside a
  `<code>` span anywhere on the built site — every comparable tensor-order bound elsewhere in the
  corpus (`0 ≤ m ≤ 2n`, `R < 3`, etc.) is rendered as math, so this is an isolated inconsistency, not
  a systemic one.
- **Resolution hint:** Render as `` $R \ge 2$ ``, matching the surrounding corpus convention.

## Finding 4 — Bare Unicode formula in a full-line comment of the Literate example

- **Type:** typesetting
- **Severity:** major
- **Confidence:** high
- **Location(s):** `examples/hist_cpu` page (generated from `examples/HIST_CPU.jl`), inside
  `run_hist_stats`'s snapshot block: *"# Eulerian statistics from the FFT velocity autocorrelation
  C(r) (package, shell-averaged): the # per-component S⁽ᴱ⁾(r) = (2/3)(C(0)−C(r)) and the integral
  length L = ∫ρ follow from it — no hand-rolled # spatial shift."*
- **Description:** These are full-line `#` comments (indented, standing alone with no code on the
  same line, inside an `if` block), which the project's own rule states render as **prose** on the
  Literate-generated page, not as code comments — yet they contain bare Unicode math
  (`S⁽ᴱ⁾(r) = (2/3)(C(0)−C(r))`, superscript glyphs included, and `∫ρ`) instead of LaTeX. A sweep of
  every full-line comment across the whole page found this to be the **only** surviving instance of
  the class — everywhere else in the same file, the equivalent narrative comments correctly use
  `$...$` math (e.g. the integrating-factor and Reynolds-number passages a few lines away). This is
  exactly the previously-documented failure mode ("a LaTeX pass was once applied to only the two
  paragraphs the user pointed at, leaving the rest... in Unicode/backtick math") recurring as a single
  missed spot rather than a page-wide problem.
- **Resolution hint:** Rewrite as e.g. ``# per-component $S^{(E)}(r) = \tfrac{2}{3}(C(0) - C(r))$ and
  the integral length $L = \int \rho$...`` and rebuild/grep the page per the project's own "verify by
  building" rule.

## Finding 5 — The verbatim in-place-steer sentence is not verbatim for the transfer verbs

- **Type:** format
- **Severity:** minor
- **Confidence:** medium
- **Location(s):** `api/Interpolation` page — `interpolate!`: *"Use this in-place form when `out` is
  already allocated; the allocating `interpolate` returns a fresh result instead."*; `anterpolate!`:
  *"Use this in-place form when `field` is already allocated; the allocating `anterpolate` returns a
  fresh result instead."* Compare all 25 other occurrences of this sentence across `Convolution`,
  `DifferentialOperators`, `FieldAlgebra`, which read, verbatim, "...when `destination` is already
  allocated...".
- **Description:** The docstring rubric fixes this steer sentence's wording around the word
  "destination." Here the first argument is genuinely named `out` (`interpolate!`) and `field`
  (`anterpolate!`) rather than `destination`, so the sentence was adapted to match the real
  parameter name — reasonable on its own, but it makes this one pair the only place in the corpus
  where the fixed template's anchor word varies, breaking the otherwise-perfect uniformity a reader
  would reasonably expect from "verbatim."
- **Resolution hint:** Either accept the deliberate substitution and note the exception once (e.g. in
  the rubric itself), or rename consistently — this is a judgment call, not necessarily a defect.

## Finding 6 — Hyphenation drift on the representation-validity catchphrase

- **Type:** language-tone
- **Severity:** nit
- **Confidence:** medium
- **Location(s):** Architecture page, §2 "Representation validity lives in the method set": *"...the
  fiberwise tensor inner product `dot!`... not the `inner` reduction... ): physical space only."*
  — unhyphenated, versus ten other occurrences of "physical-space only" / "Physical-space only"
  elsewhere on the same and other pages (e.g. decision-log entries for `combine!`'s kernel-composed
  form, `symmetric_gradient`, `weighted_inner`, `translation_kernel`). A parallel, smaller drift exists
  for "spectral representation only" (4×) vs. "spectral-representation only" (1×, the `radial_spectrum`
  decision entry).
- **Resolution hint:** Standardize on the hyphenated compound-adjective form used by the large
  majority ("physical-space only," "spectral-representation only").

## Findings considered and set aside

- **Tables, admonition titles, `\left`/`\right` usage, DOI links, citation "et al." threshold,
  imaginary-unit/differential notation, "knob"/"tweak" register, "per-step"/"particle" vocabulary
  outside the rationale docs, constructor-first Type docstrings:** all checked directly against the
  raw HTML/source and found uniformly compliant with the house conventions across every page
  inspected. In particular: every Markdown-style table in the manuscript renders as a proper
  `<table>` (spot-checked on `notation`, `performance`, and `testing`, 9+4 tables inspected); every
  `!!!`-style admonition on every page carries a custom, non-generic title; the sole `\left\{...\right.`
  system-brace exception is the only `\left`/`\right` pair on the site; every reference title carries
  a `doi.org` link in the raw HTML even though the text-extraction strips it; and citation author-count
  conventions (≤3 named, "et al." for 4+, e.g. van Hinsberg et al. 2012) are followed correctly
  everywhere checked.
- A minor discrepancy between "17.7 GB/s" (Architecture §9, the KA-CPU-backend measurement) and
  "~17 GB/s" (a later decision-log entry paraphrasing the same figure) was noted but is low-value —
  a rounded restatement of the same number in prose, not a contradiction — and is omitted from the
  ranked list above.
