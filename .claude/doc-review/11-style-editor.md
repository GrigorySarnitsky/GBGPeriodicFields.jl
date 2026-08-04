# Style / Internal-Consistency Review — hat: style-editor

Reviewed the full reader-text consolidation (`manuscript-full.md`, all pages) and the raw built HTML
under `docs/build/` (admonition markup, KaTeX math spans, tables, cross-reference links, code-block
widths). Findings below are ranked most-severe first.

---

## Finding 1 — No reference carries a DOI (or openlibrary) link anywhere in the corpus

**Type:** citation **Severity:** major **Confidence:** high

**Locations:**
- PAGE: architecture, §10 References — `- C. C. Lalescu, B. Teaca, D. Carati, Implementation of high
  order spline interpolations for tracking test particles in discretized fields, J. Comput. Phys.
  229(17) (2010) 5862–5869.` (plain text, no link)
- PAGE: api/Interpolation — `Reference: C. C. Lalescu, B. Bramas, M. Rampp, M. Wilczek, An efficient
  particle tracking algorithm for large-scale parallel pseudo-spectral simulations of turbulence
  (TurTLE), Comput. Phys. Commun. 278 (2022) 108406; arXiv:2107.01104.` (no DOI link)
- Same pattern for every reference in `architecture` §10/§11 (11 entries) and every `Reference:`/
  `References` docstring block in api/Interpolation (LalescuSpline, LagrangeSpline, NUFFT, DirectDFT).

**Description:** The house rubric (documentation policy, "Citations") is explicit and specific: "Every
reference carries a clickable DOI on its title — `[*Title*](https://doi.org/…)`, or an
`openlibrary.org/…/works/…` link for a book with no DOI." A corpus-wide search for `doi.org` and
`openlibrary` in the rendered text returns zero hits. Every citation, in both `ARCHITECTURE.md` §10/§11
and every docstring `Reference:`/`References` block, is a plain, unlinked bibliographic string. This is
not one page out of step with another — it is a total, uniform absence of the one formatting feature the
rubric calls mandatory, so a reader "sees it without opening another file" in name only; nothing is
actually clickable anywhere.

---

## Finding 2 — Two incompatible skeletons for the "fields/arguments" bulleted-list convention, split cleanly by module

**Type:** format **Severity:** major **Confidence:** high

**Locations:**
- PAGE: api/Fields — `The fields are` *(no colon)*, then `- \`grid_size::NTuple{3, Int}\`: the number of
  grid points in each spatial direction.` (colon separator) — repeated identically for
  `RealFourierLayout`, `ScalarFieldPhysical/Spectral`, `VectorFieldPhysical/Spectral`,
  `TensorFieldPhysical/Spectral`, `FieldTransformPlans`, `FieldSpectralMultipliers` (13 instances, all
  colon-separated, all headed "The fields are" with no colon).
- PAGE: api/Points — same pattern, `The fields are` (no colon) / `- \`data\`: the values, ...` (colon
  separator), for `PointSet`, `ScalarPointValues`, `VectorPointValues`, `TensorPointValues`.
- PAGE: api/Convolution — `The fields are:` *(with colon)*, then `- \`field\` — the \`ScalarFieldSpectral\`
  holding the coefficients, referenced rather than copied.` (em-dash separator) — repeated for
  `SeparableKernel`, `RadialKernel`, `ProductKernel` (4 instances, all em-dash-separated, all headed "The
  fields are:" with a colon).

**Contradicts:** Same rubric item ("A type that stores named, user-readable fields documents them under
`The fields are`, one bullet per field") realized two mutually exclusive ways: Fields.jl/Points.jl use
`` `name::Type`: description `` under an uncolon'd heading; Convolution.jl uses `` `name` — description ``
under a colon'd heading. The "arguments are:" sibling convention (32 instances) is uniformly em-dash
*and* uniformly colon-headed everywhere **except** one straggler at `FieldTransformPlans` (`` `physical`:
the field supplying... ``), which follows the Fields-module colon style instead of the corpus-wide
em-dash norm used by the other 31 instances of "The arguments are:".

**Description:** Two distinct textual "shapes" for what is supposed to be one fixed skeleton, and the
split tracks module boundaries exactly (Fields.jl + Points.jl vs. everywhere else), which reads as one
author/pass using a different template for those two files than for the rest of the API surface.

---

## Finding 3 — Admonition title states "R < 3" in bare text where the adjoining prose states the same bound as LaTeX "$R \le 2$"

**Type:** typesetting **Severity:** minor **Confidence:** medium

**Locations:**
- PAGE: api/GBGPeriodicFields — admonition title: `The supported tensor order is R < 3` (rendered as
  plain, unstyled text — not a math span, not backticked).
- Same page, body sentence immediately following: `... are defined for $R \le 2$ and throw above it.`

**Description:** One bound on one type parameter, given twice for the same fact, in two different
symbolic registers: bare ASCII `R < 3` in the admonition title vs. properly-typeset `$R \le 2$` (a KaTeX
inline span) one sentence later in the body. Per the house rule on "math that merely looks code-ish" (`R
≥ 2` is explicitly named as an example that must be LaTeX, never bare text), the title's `R < 3` is the
class of thing the rubric singles out — and it sits directly beside the correctly-typeset form of the
identical statement, which is the "one notation per concept" rule tripped inside a single docstring.

---

## Finding 4 — `translation_kernel!`'s in-place steer sentence departs from the fixed template used by all 26 other in-place forms

**Type:** format **Severity:** minor **Confidence:** medium

**Locations:**
- PAGE: api/Convolution — `translation_kernel!`: *"Use this in-place form when a displacement changes
  and the kernel is already allocated; the allocating `translation_kernel` returns a fresh kernel
  instead."*
- Every other in-place form in the corpus (26 instances, e.g. api/DifferentialOperators `gradient!`,
  api/FieldAlgebra `+`, `dot!`, `sym!`, ..., api/Interpolation `interpolate!`/`anterpolate!`): *"Use this
  in-place form when `destination` is already allocated; the allocating `f` returns a fresh result
  instead."*

**Description:** The rubric requires this sentence "verbatim." `translation_kernel!` rebuilds an
existing `SeparableKernel` for a new offset rather than filling a `destination` argument, so a literal
copy of the template would not typecheck against its actual signature — but the fix adds an entirely new
clause ("when a displacement changes") rather than the minimal substitution every other deviating case in
the corpus uses (e.g. `interpolate!`/`anterpolate!` substitute only the parameter name — `out`, `field`
— and keep the rest of the sentence verbatim). This is the one steer sentence in the whole corpus that
changes the sentence's structure rather than only its noun.

---

## Finding 5 — FiberSections' "functions-only" Internal API section documents a Constant, not a function

**Type:** organization **Severity:** nit **Confidence:** medium

**Locations:**
- PAGE: api/FiberSections, `## Internal API` (single unlabelled block, no `### Types`/`### Functions`
  split): first entry is `` `GBGPeriodicFields.FiberSections._SERIAL_CUTOFF` — Constant ``.
- Compare PAGE: api/Fields, `## Internal API`, which *does* split into `### Types` / *(functions,
  unlabelled continuation)* because it documents both kinds.

**Description:** The stated organizing rule is binary — "a section documenting both types and functions
uses `### Types` and `### Functions`... one documenting only functions uses a single unlabelled block."
`FiberSections`' unlabelled block is presumably in the "functions-only" bucket, but its very first bound
symbol is a `Constant`, a third kind the binary rule never names. It is not a "Type" (so the split rule
doesn't obviously trigger) but it is also not a "Function" (so calling the section "functions-only" is
imprecise). A reader relying on the stated split rule to predict a page's shape would not predict this.

---

## Finding 6 — Every rendered table site-wide (including long, multi-sentence prose cells) is right-aligned

**Type:** typesetting **Severity:** nit **Confidence:** low

**Locations:**
- PAGE: notation, "Conventions" table, raw HTML: every `<td>`/`<th>` in the table (including the
  multi-sentence "Convention" column, e.g. the ~40-word cell explaining the imaginary unit) carries
  `style="text-align: right"`.
- Same pattern in every other rendered table in the build (`testing/index.html`,
  `performance/index.html`, ...): all columns right-aligned, regardless of content length.

**Description:** This is uniform across the site (so it is not, strictly, an *inconsistency* between two
places), but it is a plausible unintended silent-rendering artifact: Documenter/CommonMark right-aligns a
GFM table column by default when the source table has no `:---`/`---:` alignment markers, and a table
whose "Convention"/description column holds full sentences reads oddly ragged-left, flush-right. Worth a
maintainer glance at whether right-alignment was the intended choice for prose columns, since it is very
unusual for descriptive text.

---

## Notes on things checked and found clean (for the record, not separate findings)

- Imaginary unit (`\mathrm{i}`), differential (`\mathrm{d}`), partial-derivative subscripting
  (`\partial_{x_i}`, `\partial^2_{x_i x_i}`), and the `\left`/`\right` ban are all followed consistently
  everywhere sampled; no bare-italic `i`, no `\imath` used live (only mentioned as the forbidden form in
  its own gloss), no unmatched `\left(`/`\left[`.
- "Knob"/"tweak" register: zero occurrences. "Per-step"/"hot loop" cadence language is confined to
  `ARCHITECTURE.md`/`PERFORMANCE.md`, which the rubric explicitly exempts.
- Particle/tracer vocabulary is confined to (a) explicit statements that the package deliberately avoids
  that vocabulary, and (b) the consumer-facing `examples/hist_cpu` demo, both allowed by the rubric.
- Admonition titles are uniformly custom and descriptive (no bare "Warning"/"Note" found in the built
  HTML `admonition-header` spans, 26 instances checked across 8 pages).
- `@ref` cross-references all resolved to live links in the built HTML; no literal `@ref` text leaked, no
  "link immediately followed by a code span" seam found.
- Citation author-count register (≤3 named, `First et al.` for 4+) is applied correctly everywhere
  sampled, including the TurTLE citation (4 authors → "Lalescu et al. (2022)") vs. the 2010 paper (3
  authors → named in full).
- "The arguments are:"-headed blocks are uniformly colon-terminated (32/32) and uniformly em-dash
  separated except the one FieldTransformPlans straggler noted in Finding 2.
- No stray ASCII `alpha`/`beta` prose words outside the two documented exceptions (the NUFFT `beta`
  keyword, `alpha_beta`/`beta_n{n}_m{m}` identifiers).
- The Grafakos citation's theorem-number placeholder is resolved ("Thm 2.5.10"), not left as a
  placeholder.
