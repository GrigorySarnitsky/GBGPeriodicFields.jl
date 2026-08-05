# Scientific-integrity & citations audit — GBGPeriodicFields rendered docs

Hat: citations-integrity. Substrate: `manuscript-full.md` (rendered-site consolidation) only.

## Finding 1 — No reference anywhere in the rendered site carries a DOI (or an openlibrary link for a book)

- **Type:** citation
- **Severity:** major
- **Confidence:** medium
- **Locations:**
  - Architecture §10 References block, e.g. "C. C. Lalescu, B. Teaca, D. Carati, Implementation of high order spline interpolations for tracking test particles in discretized fields, J. Comput. Phys. 229(17) (2010) 5862–5869." (plain text, no link)
  - Interpolation API page, `LalescuSpline` References block: same three citations (Lalescu 2010, TurTLE 2022, Fornberg 1988), also unlinked
  - `NUFFT` docstring: "Reference: A. H. Barnett, J. Magland, L. af Klinteberg, ... SIAM J. Sci. Comput. 41(5) (2019) C479–C504." — unlinked
  - Book references "R. W. Hockney, J. W. Eastwood, Computer Simulation Using Particles, Adam Hilger, Bristol, 1988" and "C. K. Birdsall, A. B. Langdon, Plasma Physics via Computer Simulation, Adam Hilger, Bristol, 1991" — no DOI *and* no `openlibrary.org` link
- **Description:** the whole document contains exactly two hyperlinks, both plain-text GitHub install URLs on the Home page (`https://github.com/GrigorySarnitsky/GBGPeriodicFields.jl`); every one of the roughly dozen bibliographic references (Lalescu 2010, TurTLE 2022, van Hinsberg 2012, Barnett/Magland/af Klinteberg 2019, Fornberg 1988, Sundaram & Collins 1996, Crowe/Sharma/Stock 1977, Brandt & Lubrecht 1990, Peskin 2002, Hockney & Eastwood 1988, Birdsall & Langdon 1991, Catmull & Rom 1974) is plain, unlinked text with no DOI and, for the two books, no `openlibrary.org` fallback. Titles are also not italicized. Every reference is otherwise well-formed (correct authors/journal/volume/pages as far as I can check) and internally verbatim-consistent across its repeated appearances.
- **Contradicts:** the package's own stated documentation policy requires "Every reference carries a clickable DOI on its title — `[*Title*](https://doi.org/…)`, or an `openlibrary.org/…/works/…` link for a book with no DOI" — and this rendered surface satisfies that for zero of ~13 distinct works.
- **Resolution hint:** most likely an artifact of this particular reader-text extraction (which appears to drop `[text](url)` hrefs and italics markup uniformly, since even the two known-good GitHub links only survive as raw code-block text, not as rendered hyperlinks) rather than a genuine regression in the source `.md`/docstrings — worth a quick `grep 'doi.org' src/ docs/src` in the actual repo before treating this as a real fix item.

## Finding 2 — `PSI-Cell`/`PSI-CELL` model name styled three different ways

- **Type:** citation
- **Severity:** nit
- **Confidence:** medium
- **Locations:**
  - Architecture §10 prose: "projection / Particle-Source-In-Cell (particle-laden-flow DNS — Crowe, Sharma & Stock 1977)" and, a sentence later in the reference title, "The Particle-Source-In-Cell (**PSI-CELL**) model for gas–droplet flows" — full caps
  - Architecture §10 synonym list (same page, decision-log copy): "projection/**PSI-Cell**" — mixed case
  - `anterpolate!` docstring: "projection (**particle-source-in-cell**)" — all lowercase
- **Description:** the same cited model/acronym (Crowe, Sharma & Stock 1977) is rendered as `PSI-Cell`, `PSI-CELL`, and `particle-source-in-cell` across three surfaces referring to the identical citation, rather than one consistent spelling.
- **Contradicts:** self — three renderings of the one acronym tied to one reference.

## Finding 3 — Catmull–Rom (1974) reference has no accompanying inline author-year mention anywhere it is used

- **Type:** citation
- **Severity:** minor
- **Confidence:** low
- **Locations:**
  - Architecture §10 References block: "E. Catmull, R. Rom, A class of local interpolating splines, in: Computer Aided Geometric Design, Academic Press, 1974, pp. 317–326."
  - `CatmullRom` docstring: "a four-point $C^1$ stencil that reproduces the Catmull–Rom spline (and quadratic polynomials exactly)" — names the eponym but never tags it "(Catmull & Rom 1974)"
- **Description:** every other full reference in the §10 block has a matching in-text author-year (or "Reference:") anchor somewhere in the surrounding prose or a docstring; Catmull & Rom is the one full citation in that list with no such anchor — only the bare eponym "Catmull–Rom" appears, everywhere. Likely deliberate under the package's own "eponymous method names take no year unless actually citing the work" exemption, but the presence of the full reference entry implies the work *is* being cited (as the source the reproduction claim is checked against), so the missing inline tag is a small inconsistency in an otherwise-followed "vice-versa" rule.
- **Contradicts:** the pattern set by every other §10 reference (Lalescu, TurTLE, van Hinsberg, Barnett, Fornberg, Sundaram & Collins, Crowe/Sharma/Stock, Brandt & Lubrecht, Peskin, Hockney & Eastwood, Birdsall & Langdon), each of which is inline-anchored by author-year in the same section's prose.

## Clean areas checked (no findings)

- Author-year format is applied consistently per the stated rule (≤3 authors named in full, e.g. "Lalescu, Teaca & Carati (2010)", "Crowe, Sharma & Stock 1977", "Brandt & Lubrecht 1990"; 4+ authors compressed to "First et al.", e.g. "van Hinsberg et al. (2012)", "Lalescu et al. 2022" for the 4-author TurTLE paper).
- Every full reference that appears more than once (Lalescu 2010 ×3, TurTLE 2022 ×3, Fornberg 1988 ×3, Sundaram & Collins 1996 ×2, Brandt & Lubrecht 1990 ×2) is verbatim-identical byte-for-byte across all its appearances — no drift found.
- No fabricated or misattributed citations detected: spot-checked authors/titles/journals/years for Lalescu (2010), TurTLE (2022), Barnett/Magland/af Klinteberg (2019, FINUFFT ES-kernel paper), Fornberg (1988), Sundaram & Collins (1996), Peskin (2002), Catmull & Rom (1974) against known literature — all plausible and correctly attributed.
- No inaccessible source cited anywhere (no gitignored monograph, "accompanying thesis," or unlinkable appendix/figure) — the K41/Kolmogorov material in the Examples page is correctly presented on standard public terms with no citation, per the package's own policy for classical results.
- No inline citation lacks a matching full reference, and (aside from Finding 3) no full reference lacks a matching inline anchor — checked exhaustively for every named/published method surfaced in the document (Lalescu splines, TurTLE pin, van Hinsberg B-spline, NUFFT/ES-kernel, Fornberg weights, Catmull-Rom, Sundaram-Collins, the anterpolation-naming lineage).
- No overclaiming language found ("exact," "allocation-free," etc. are used only where the surrounding prose substantiates them, e.g. `NUFFT` is explicitly described as agreeing with `DirectDFT` "to a tolerance `tol`," never as itself exact; "allocation-free" claims are consistently paired with the documented bounded-exception list). No "first/largest/optimal" priority claims found that aren't accurate self-description of internal scope (e.g. "the largest surface on the table" describing implementation size, not a priority claim).
- Wiener–Khinchin spelling (en dash) is consistent across all 9 occurrences.
