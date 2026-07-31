# Panel review — SCIENTIFIC-INTEGRITY & CITATIONS auditor

Document reviewed: `manuscript-full.md` (reader-text consolidation of the whole rendered site
incl. design docs). Focus: named/published-method citations, author–year consistency across pages,
inline-cite ↔ full-reference matching, verbatim consistency, inaccessible sources, and overclaims.

## Summary of what is CLEAN (positive verification)

- **Every full-reference string is bibliographically accurate** against my own knowledge — Fornberg
  1988 (Math. Comp. 51(184), 699–706), Lalescu/Teaca/Carati 2010 (JCP 229(17), 5862–5869), van
  Hinsberg et al. 2012 (SISC 34(4), B479–B498), Barnett/Magland/af Klinteberg 2019 (SISC 41(5),
  C479–C504), Sundaram & Collins 1996 (JCP 124(2), 337–350), TurTLE 2022 (CPC 278, 108406), Catmull &
  Rom 1974, Crowe/Sharma/Stock 1977, Brandt & Lubrecht 1990, Peskin 2002. No wrong year/volume/pages.
- **Repeated full references are byte-identical across pages** (verified: Lalescu 2010 at lines
  340/2728/2790; TurTLE at 341/2791/2808; Fornberg at 344/2792/2872; Barnett at 343/2838; Sundaram at
  345/2729). No verbatim drift.
- **Author–year style is applied correctly and consistently** (≤3 named, 4+ → "et al."): Lalescu,
  Teaca & Carati (2010) [3 named]; Lalescu et al. (2022) [4 → et al.]; van Hinsberg et al. (2012) [4 →
  et al.]; Barnett–Magland–af Klinteberg [3 named]; Sundaram & Collins; Fornberg; Catmull & Rom.
- **The NUFFT "exponential-of-semicircle" kernel is correctly attributed** to Barnett/Magland/af
  Klinteberg 2019 (the FINUFFT paper), inline (line 449) and in the full ref.
- **No inaccessible/private source is cited on any user-facing surface** — the examples/HIST page uses
  only informal "Kolmogorov (K41)" with dimensionally complete guides (C_K ε^{2/3} κ^{-5/3}); no
  monograph, thesis, or "appendix A" appears anywhere.
- **Overclaim language is substantiated, not inflated**: "exact"/"allocation-free"/"bit-for-bit" are
  everywhere qualified by "measured", "guarded by `test/allocations.jl`", "verified ~1e-16", "agreement
  ≤ 1e-15". No "optimal / fastest / state-of-the-art / first-of-its-kind" claims.

---

## Finding 1 — Grafakos citation carries a live placeholder "Thm 2.5.x" and no full reference

- **type**: citation
- **severity**: minor
- **confidence**: high
- **locations**:
  - PAGE architecture, §12 / decision 19 (line 408): *"The math anchor (Grafakos, Classical Fourier
    Analysis, Thm 2.5.x): on a uniform periodic box every homogeneous (translation-invariant) linear
    operator is a Fourier multiplier …"*
- **contradicts**: (n/a — self-contained defect)
- **description**: On a rendered user-facing page the theorem number is the literal placeholder
  "**Thm 2.5.x**". Additionally, unlike every implemented-method citation (which gets a full reference
  with authors/venue/pages), this book is cited with **no author initials, no edition, no year, no
  publisher, and no full-reference entry** anywhere. A reader cannot resolve either the theorem or the
  edition. (I am aware this is a deliberately tracked TODO in the project's own notes — reported here
  because, as rendered, it is an incomplete citation visible to the reader; a book normally also carries
  an openlibrary link under this project's own policy.)

## Finding 2 — Decision log says anterpolation synonyms are "listed on the binding"; the rendered `anterpolate!`/`anterpolate` docstrings list none, and drop the Brandt & Lubrecht coinage

- **type**: contradiction
- **severity**: minor
- **confidence**: high
- **locations**:
  - PAGE architecture, §10 (line 337): *"The binding will carry a docstring listing the synonyms —
    adjoint of interpolation; spreading; deposition; scatter; projection / PSI-Cell; gridding;
    two-way-coupling source/feedback — so a reader from any of those fields finds it. We adopt
    anterpolation (Brandt & Lubrecht 1990) …"*
  - PAGE architecture, §13 / decision 17 (line 384): *"synonyms — spreading, deposition, scatter,
    projection/PSI-Cell, gridding, two-way-coupling feedback — listed on the binding"*
  - PAGE api / Interpolation, `anterpolate!` (lines 2753–2761) and `anterpolate` (2764–2770): the
    rendered docstrings say only *"the adjoint (transpose) of `interpolate!`"* / *"Deposit (scatter) …"*
    — **no synonym list, and no Brandt & Lubrecht attribution** (verified: none of
    spreading/deposition/PSI-Cell/gridding/Brandt/Lubrecht appears in the docstring body).
- **contradicts**: architecture §13 decision 17 (line 384) states the synonyms are *"listed on the
  binding"* (present tense), whereas the rendered binding (`anterpolate!`, lines 2753–2761) lists them
  nowhere. Axis of disagreement: **claimed vs. actual docstring content of the `anterpolate` binding.**
- **description**: The whole point of the synonym list — discoverability "so a reader from any of those
  fields finds it" — is undelivered in the rendered docs; the list appears nowhere on the user-facing
  surface (not on `anterpolate`, not in the Interpolation module docstring). Consequently the full
  reference **Brandt & Lubrecht 1990** (arch §10, line 347), the source of the very term "anterpolation"
  the package is named after, is used only for an architecture-only naming aside and never reaches the
  operation's own docstring.

## Finding 3 — Hockney & Eastwood 1988 and Birdsall & Langdon 1991 are inline-cited but have no full reference, while their sibling synonym-sources (Crowe, Brandt, Peskin) do

- **type**: citation
- **severity**: nit
- **confidence**: high
- **locations**:
  - PAGE architecture, §10 (line 337): *"deposition / charge assignment (particle-in-cell — **Hockney &
    Eastwood 1988; Birdsall & Langdon 1991**)"* — these two author–year cites appear inline only.
  - PAGE architecture, §10 References block (lines 340–349): full references are present for the peer
    synonym-sources **Crowe, Sharma & Stock 1977** (line 346), **Brandt & Lubrecht 1990** (347), **Peskin
    2002** (348), but **not** for Hockney & Eastwood or Birdsall & Langdon.
- **contradicts**: the §10 reference block's own treatment of the same class of citation — some
  synonym-community attributions get a full reference, two do not. Axis: **which PIC/synonym sources
  earn a full-reference entry.**
- **description**: The §10 "References (this section)" block is the doc's only full-reference list and
  the de-facto canonical one, yet it is inconsistent about the PIC-lineage asides: either these are
  informal related-work mentions that need no full reference (in which case Crowe/Brandt/Peskin are
  over-referenced), or they warrant full references (in which case Hockney & Eastwood and Birdsall &
  Langdon are missing them). Pick one rule and apply it to the whole synonym set.

## Finding 4 — "Sefusatti et al." cited with no year, unlike every other related-work aside

- **type**: citation
- **severity**: nit
- **confidence**: high
- **locations**:
  - PAGE architecture, §13 / decision 22 (line 441): *"FFT-RDF resolves intermediate / large-scale
    clustering …, not a sharp contact peak (interlacing — **Sefusatti et al.** — is a future
    refinement)."*
- **contradicts**: the surrounding informal-aside citations, which all carry a year — *"Vreman, Geurts
  & Kuerten 1994"* (line 419), *"Colucci et al. 1998"* (419), *"Ghosal & Moin 1995"* (420), *"Vasilyev,
  Lund & Moin 1998"* (420). Axis: **author–year completeness of informal citations.**
- **description**: The context-standard author–year style the project uses requires a year on the
  author-prominent form. "Sefusatti et al." is the lone bare-name-without-year citation in the docs.

## Finding 5 — `LagrangeSpline` reference block omits Lalescu, Teaca & Carati 2010, though the scheme is documented elsewhere as one of "the two hierarchies of Lalescu, Teaca & Carati (2010)"

- **type**: contradiction
- **severity**: minor
- **confidence**: medium
- **locations**:
  - PAGE api / Interpolation, `AbstractSplineScheme` (line 2854): *"Supertype of the physical-domain
    local interpolation schemes — **the two hierarchies of Lalescu, Teaca & Carati (2010)**: the smooth
    `LalescuSpline` and the C⁰ `LagrangeSpline`."*  (Same framing in architecture line 326: *"Lalescu's
    two hierarchies … the Lagrange hierarchy (`LagrangeSpline(n)`)"*.)
  - PAGE api / Interpolation, `LagrangeSpline` References block (lines 2806–2808): cites **only** the
    TurTLE paper (Lalescu et al. 2022); the Lalescu, Teaca & Carati **2010** paper is absent.
  - Contrast: `LalescuSpline` References (2788–2792) cites Lalescu 2010 **and** TurTLE **and** Fornberg.
- **contradicts**: `AbstractSplineScheme` (line 2854) attributes the Lagrange hierarchy to Lalescu,
  Teaca & Carati (2010), while the `LagrangeSpline` type's own reference block attributes it only to
  TurTLE 2022. Axis: **which paper the `LagrangeSpline` scheme is credited to.**
- **description**: Either the Lagrange hierarchy derives from Lalescu 2010 (then its reference block
  should include that paper, mirroring `LalescuSpline`), or it is classical Lagrange interpolation not
  originating with Lalescu (then the `AbstractSplineScheme`/architecture "two hierarchies of Lalescu,
  Teaca & Carati (2010)" framing over-attributes it). As rendered, the two surfaces disagree.

## Finding 6 — DOIs not verifiable from this artifact; no `doi.org` text present anywhere (flag for source-side check)

- **type**: format
- **severity**: nit
- **confidence**: low
- **locations**:
  - Every reference block: PAGE architecture §10 (lines 340–349); PAGE api / Interpolation (2728–2729,
    2790–2792, 2808, 2838); PAGE api / Points-region Fornberg (2872). None shows a DOI.
- **contradicts**: the project's stated citation policy that *every* reference carry a clickable DOI on
  its title.
- **description**: A grep for `doi.org` over the entire consolidated site returns **zero** hits.
  However, this reader-text consolidation **strips all hyperlink URLs** — confirmed by the per-docstring
  "source" GitHub links, which render as the bare word "source" with no URL — so a title that *is* a DOI
  hyperlink would appear here as plain title text, indistinguishable from a title with no link.
  Therefore I cannot confirm whether the required clickable DOIs are present. Flagged low-confidence:
  **verify against the docstring/`.md` source**; if the reference titles genuinely lack DOI links, it
  violates policy, but that determination cannot be made from this artifact.
