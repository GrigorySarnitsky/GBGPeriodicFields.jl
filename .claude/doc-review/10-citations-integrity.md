# Scientific-integrity & citations audit — GBGPeriodicFields rendered docs

Hat: **citations-integrity**. Scope: the full rendered site consolidation
(`manuscript-full.md`, all pages, including the four design docs and every API
docstring page). This hat checks author-year consistency, inline-cite ↔
full-reference correspondence (including the required DOI), verbatim
consistency of repeated reference copies, absence of inaccessible sources, and
overclaiming.

Positive context established before the findings below (so the findings read
against a baseline, not a blank slate): every *repeated* full bibliographic
entry I could byte-compare across pages is in fact byte-identical — the
Lalescu, Teaca & Carati (2010) reference (3 copies), the TurTLE / Lalescu et
al. (2022) reference (3 copies), the Fornberg (1988) reference (2 copies),
the Sundaram & Collins (1996) reference (2 copies), the Brandt & Lubrecht
(1990) reference (2 copies), and the Barnett, Magland & af Klinteberg (2019)
reference (2 copies) all match verbatim between `ARCHITECTURE.md` §10's
"References (this section)" block and their docstring copies. Author-name
formatting (`Initial. Initial. Surname`) and the up-to-three/`et al.`
author-count convention are applied correctly everywhere I could check. No
citation anywhere traces to an inaccessible source (no hit for
thesis/monograph/inspiration/appendix/accompanying across the whole document).
The findings below are the exceptions to that otherwise-careful baseline.

---

## Finding 1 — Two of four synonym citations in one sentence get full references, two don't

- **Type:** citation
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - PAGE: architecture, §10, "Why the code says 'anterpolation.'" — *"The
    point→grid (scatter) operation is named differently in every community,
    with no dominant choice: spreading (immersed-boundary method, where it is
    explicitly the adjoint $S = J^*$ of interpolation, built from the same
    kernel — Peskin 2002; also NUFFT type-1), deposition / charge assignment
    (particle-in-cell — Hockney & Eastwood 1988; Birdsall & Langdon 1991),
    scatter (data-parallel computing), projection / Particle-Source-In-Cell
    (particle-laden-flow DNS — Crowe, Sharma & Stock 1977), gridding (MRI and
    radio interferometry)... We adopt anterpolation (Brandt & Lubrecht 1990)
    because it is the single term whose literal definition is 'the adjoint of
    interpolation.'"*
  - PAGE: architecture, §10, "References (this section)" (the block
    immediately following the paragraph above) — contains full entries for
    *"C. S. Peskin, The immersed boundary method, Acta Numerica 11 (2002)
    479–517..."* and *"C. T. Crowe, M. P. Sharma, D. E. Stock, The
    Particle-Source-In-Cell (PSI-CELL) model for gas–droplet flows, J. Fluids
    Eng. 99(2) (1977) 325–332."* and *"A. Brandt, A. A. Lubrecht,
    Multilevel matrix multiplication..."* — but **no entry anywhere in the
    document** for Hockney & Eastwood (1988) or Birdsall & Langdon (1991).
- **Contradicts:** the sentence cites four synonym-community precedents with
  identical parenthetical author-year rigor (Peskin 2002; Hockney & Eastwood
  1988; Birdsall & Langdon 1991; Crowe, Sharma & Stock 1977). Two of the four
  (Peskin; Crowe et al.) are promoted to full bibliographic entries in the
  section's own reference block; the other two (Hockney & Eastwood; Birdsall
  & Langdon) are not, with no stated reason for the split and no full
  reference for them anywhere else in the site. This is exactly the axis the
  citation policy singles out: *"every inline cite has a matching full
  reference (in the Architecture page's per-section reference blocks, ...),
  and vice-versa."*
- **Description:** Both omitted works are real, correctly-dated citations
  (Hockney & Eastwood's *Computer Simulation Using Particles* and Birdsall &
  Langdon's *Plasma Physics via Computer Simulation* — both standard
  particle-in-cell references, both legitimately dated to their well-known
  1988/1991 reprint editions), so this is not a fabrication concern — it is a
  completeness/consistency gap. It is also not obviously explained by a
  "book vs. journal-article" rule: the citation policy explicitly provides a
  mechanism for citing a book without a DOI (*"or an openlibrary.org/…/works/…
  link for a book with no DOI"*), so book status does not exempt a citation
  from needing a full entry. Nor is it explained by an
  "implemented-vs-aside" rule: `CLAUDE.md`'s own citation policy explicitly
  names *"the anterpolation lineage"* as one of the categories of work this
  package "implements/pins to" and therefore owes a canonical full reference
  — and Hockney & Eastwood / Birdsall & Langdon sit inside that exact lineage
  paragraph, alongside Peskin and Crowe et al., who did get promoted. The
  `anterpolate!` docstring itself (PAGE: api / Interpolation) sidesteps the
  problem more cleanly — it repeats the same synonym list but drops every
  parenthetical citation except Brandt & Lubrecht (1990) for the adopted term
  — which only sharpens the contrast with the Architecture page's inconsistent
  treatment of the same list.
- **Resolution hint (advisory):** either add full-reference entries for
  Hockney & Eastwood (1988) and Birdsall & Langdon (1991) to the §10
  reference block (matching Peskin/Crowe's treatment), or demote all four
  synonym citations to the informal "no full reference" treatment the
  `anterpolate!` docstring already uses, so the sentence's four citations are
  handled uniformly one way or the other.

---

## Finding 2 — No citation in the given substrate carries a visible DOI

- **Type:** citation
- **Severity:** major
- **Confidence:** medium (see caveat below — this is a substrate-fidelity
  caveat, not a hedge on the underlying observation)
- **Locations:** every full-reference entry in the document — the ten entries
  in PAGE: architecture §10 "References (this section)" (e.g. *"C. C.
  Lalescu, B. Teaca, D. Carati, Implementation of high order spline
  interpolations for tracking test particles in discretized fields, J.
  Comput. Phys. 229(17) (2010) 5862–5869."*), the PAGE: api / Interpolation
  module "References" block, and every docstring `Reference:`/`References`
  block (`LalescuSpline`, `LagrangeSpline`, `NUFFT`, `anterpolate!`,
  `_fornberg`).
- **Contradicts:** the project's own citation policy (quoted in this
  session's context) states, without qualification: *"Every reference
  carries a clickable DOI on its title — `[*Title*](https://doi.org/…)`, or
  an `openlibrary.org/…/works/…` link for a book with no DOI — verbatim-
  identical in the §References list and every inline docstring copy; a DOI
  stays REPL-safe (the URL renders as visible text, not a dead link)."* This
  is also explicitly part of this hat's brief (*"every inline cite has a
  matching full reference ... each with a clickable DOI"*).
- **Description:** across the entire 4139-line consolidated document there is
  not one occurrence of `doi.org`, the literal string `DOI`, a raw
  `10.xxxx/...` DOI pattern, an `openlibrary.org` link, or markdown link
  syntax `](...)` of any kind, for any citation — every reference title
  (e.g. *"Implementation of high order spline interpolations for tracking
  test particles in discretized fields"*) reads as plain, unmarked text
  indistinguishable in formatting from the surrounding author/journal/page
  text. **Caveat on confidence:** this document is a "reader-text
  consolidation" of rendered HTML, and I cannot fully rule out that the
  extraction step dropped `href` targets while keeping visible anchor text
  (a title wrapped in a DOI link would still just show as its plain title in
  a text-only extraction). Two observations push against that innocent
  explanation, though: (1) other markdown emphasis this document is careful
  to preserve — code identifiers in backticks, math in `$...$`/`\[...\]` —
  survives everywhere without exception, so a tool careful enough to keep
  those would plausibly keep link markup too; and (2) plain (non-hyperlinked)
  URL text elsewhere in the document *does* survive intact (the GitHub
  install command, `Code: gitlab.mpcdf.mpg.de/TurTLE/turtle.` inside the
  TurTLE reference itself) — so the extraction pipeline is not stripping
  URL-shaped text on principle. On balance this reads as a real gap rather
  than an artifact, but it is worth a direct check against the live rendered
  page before treating it as confirmed.
- **Resolution hint (advisory):** spot-check one docstring's rendered HTML
  (e.g. `NUFFT`'s "Reference:" line) directly in a browser; if no DOI link is
  present there either, this is a site-wide gap against the package's own
  documented policy and affects all ten works in the reference list.

---

## Finding 3 — The Grafakos citation carries no year (and no edition), unlike every other named citation

- **Type:** citation
- **Severity:** minor
- **Confidence:** medium
- **Locations:** PAGE: architecture, §13 decision log, "The measure taxonomy"
  entry — *"The math anchor (Grafakos, Classical Fourier Analysis, Thm
  2.5.10): on a uniform periodic box every homogeneous (translation-
  invariant) linear operator is a Fourier multiplier..."*
- **Contradicts:** every other named/published citation in the document
  carries at minimum a publication year in the standard "Author Year"
  parenthetical form — including citations exempted from a *full* reference,
  such as *"(Vreman, Geurts & Kuerten 1994...)"*, *"(Ghosal & Moin 1995,
  Vasilyev, Lund & Moin 1998)"*, and *"(Colucci et al. 1998, the FDF)"* two
  paragraphs later in the very same decision-log entry. Grafakos is the one
  named citation in the whole document with no year at all.
- **Description:** the citation policy's "no year" exemption is for
  *eponymous method names* used as bare nouns (the Catmull–Rom spline,
  Fornberg weights) — not for a citation actively invoking a specific
  theorem number from a specific book to ground a design decision, which is
  what this is (*"the math anchor"* for the whole measure-taxonomy
  argument). `CLAUDE.md`'s own standing-open-items note confirms this was a
  deliberately tracked, carefully-verified citation (the theorem number was
  confirmed against a physical copy on 2026-07-15) — which makes the
  continued absence of a year read as a residual gap rather than a one-off
  oversight, since the citation clearly received dedicated attention.
  Additionally, Grafakos's *Classical Fourier Analysis* has multiple editions
  (2004, 2008, 2014, and the two-volume *Classical and Modern Fourier
  Analysis* split), and theorem numbering is not guaranteed stable across
  them — so citing only a theorem number, with neither year nor edition, is
  the one citation in the document that a reader cannot reliably chase down
  even in principle.
- **Resolution hint (advisory):** add a year (and ideally an edition/volume)
  to disambiguate — `(Grafakos, Classical Fourier Analysis, 3rd ed. 2014,
  Thm 2.5.10)` or similar, matching whichever printing the theorem number was
  actually checked against.

---

## Finding 4 — "the dynamic procedure of Germano and coworkers" carries no year, unlike its sibling informal LES citations

- **Type:** citation
- **Severity:** minor
- **Confidence:** medium
- **Locations:** PAGE: api / Convolution, `squared_wavenumber_field`
  docstring — *"a consumer builds a Fourier symbol from it — a viscous
  integrating factor $\exp(-\nu |k|^2 \Delta t)$, a smooth spectral envelope,
  or a subgrid test filter of the dynamic procedure of Germano and coworkers
  (an LES closure choice) — by broadcasting over its `field_data`..."*
- **Contradicts:** the document's other informal (no-full-reference)
  LES-adjacent citations all carry an explicit year even though none of them
  carry a full bibliographic entry — PAGE: architecture §13, "The measure
  taxonomy" entry: *"realizable SGS stress (Vreman, Geurts & Kuerten 1994...)
  ⟹ bona-fide filtered PDF (Colucci et al. 1998, the FDF)"* and *"commutation
  error; Ghosal & Moin 1995, Vasilyev, Lund & Moin 1998"*. All four of those
  are the same rhetorical class as the Germano mention (a non-implemented,
  related-work aside naming a specific published technique), and all four
  get a year; only the Germano mention does not.
- **Description:** *"of Germano and coworkers"* names specific researchers
  in connection with a specific, real, named technique (the dynamic
  Smagorinsky/dynamic-procedure family for LES closures, due to Germano,
  Piomelli, Moin & Cabot and follow-on work), which reads as an actual
  citation attempt rather than a bare eponym like "the Catmull–Rom spline" —
  eponym phrasing would more naturally read "the dynamic procedure" or "a
  Germano-style dynamic filter" without "and coworkers." Given the sibling
  citations two sections over in the same page family all supply a year, the
  omission here looks like a citation that never got the same treatment
  rather than a deliberate stylistic choice.
- **Resolution hint (advisory):** either add a year (`Germano et al. 1991` is
  the standard anchor for the dynamic procedure) to match the sibling
  informal citations, or reword to a bare eponym with no author name at all
  ("a dynamic-procedure test filter") if no specific paper is intended to be
  invoked.

---

## Checks performed with a clean result (not reported as findings)

- Verbatim byte-for-byte consistency of every repeated full reference
  (Lalescu 2010 ×3, TurTLE/Lalescu 2022 ×3, Fornberg 1988 ×2, Sundaram &
  Collins 1996 ×2, Brandt & Lubrecht 1990 ×2, Barnett et al. 2019 ×2) —
  confirmed identical via direct string extraction and diff, not just visual
  read-through.
- Author-count convention (`A & B` for two, `A, B & C` for three, `First et
  al.` for four or more) — checked against every citation with a
  reconstructable author list (Sundaram & Collins; Lalescu, Teaca & Carati;
  Lalescu et al./TurTLE's 4 authors; van Hinsberg et al.'s 4 authors) and
  found correct throughout.
- No citation traces to an inaccessible source — zero hits for
  thesis/monograph/inspiration/appendix/accompanying anywhere in the
  document (this project has a standing rule against exactly this failure
  mode, and the rendered docs pass it cleanly).
- No unsubstantiated priority/superiority overclaims found — searched for
  "the first," "novel," "state of the art," "optimal," "best," "unique,"
  "pioneering," "breakthrough," "superior," "outperform," "guarantee(s)" and
  read every hit in context; all are either internal/structural claims about
  the package's own prior state (e.g. "the first operation to use both
  wavenumber families," meaning first within this codebase) or accurate,
  hedged, measurement-qualified performance statements ("measured at ≈1.4×
  ... on a GPU at 256³"), never an external claim of scientific priority or
  competitive superiority.
- K41/Kolmogorov-constant usage in the example pages (`C_K ≈ 1.6`, `C_2 ≈
  2.1`, `C_0 ≈ 6`) is treated as standard turbulence convention with no
  citation, consistent with the project's own standing rule to keep
  diagnostics on public/standard terms rather than cite anything
  inaccessible.
- The "2+ citations → bullet list; 1 citation → inline `Reference:`" format
  rule is applied correctly at every site checked (`LalescuSpline`'s 3
  references bulleted; `LagrangeSpline`/`NUFFT`/`anterpolate!`/`_fornberg`'s
  single references each inline).
