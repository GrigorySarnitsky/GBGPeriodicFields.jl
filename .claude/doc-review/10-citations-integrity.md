# Scientific-integrity & citations audit

Hat: citations-integrity

## Finding 1 — Not one reference in the entire rendered site carries a clickable DOI, link, or even a bare DOI string

- **Type:** citation
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - PAGE: architecture, §10 References block (12 entries), e.g. "C. C. Lalescu, B. Teaca, D. Carati, Implementation of high order spline interpolations for tracking test particles in discretized fields, J. Comput. Phys. 229(17) (2010) 5862–5869."
  - PAGE: architecture, §10 TurTLE reference: "Comput. Phys. Commun. 278 (2022) 108406; arXiv:2107.01104. Code: gitlab.mpcdf.mpg.de/TurTLE/turtle." — the arXiv id and the code URL are given as inert plain text, not links.
  - PAGE: interpolation (docstrings), `LalescuSpline`/`CatmullRom`/`AbstractSplineScheme`/`fornberg_weights`/`NUFFT` reference blocks — same plain-text style.
  - PAGE: architecture, §13 decision 19 — the Grafakos book citation, plain text, no openlibrary link.
- **Description:** Every one of the ~15 distinct works cited across the site (Lalescu 2010, TurTLE 2022, van Hinsberg 2012, Barnett/Magland/af Klinteberg 2019, Fornberg 1988, Sundaram & Collins 1996, Crowe/Sharma/Stock 1977, Brandt & Lubrecht 1990, Peskin 2002, Hockney & Eastwood 1988, Birdsall & Langdon 1991, Catmull & Rom 1974, Grafakos 2014) is rendered as an inert bibliographic string. A corpus grep for `doi.org`, `openlibrary`, any bare `10.xxxx/...` DOI, or any Markdown link syntax `](http` returns zero hits anywhere in the rendered site. A reader who wants to follow up on, say, the TurTLE pin or the NUFFT kernel has to manually retype and search every citation by hand — nothing is one click away, not even the arXiv id or the gitlab code URL that are spelled out as plain text right next to the reference. This is a corpus-wide gap, not an isolated slip: every reference block on every page has the same shape.
- **Resolution hint:** wrap each reference's title in a DOI/openlibrary Markdown link, verbatim-identical between its every appearance (the §References canonical copy and each docstring's inline copy).

## Finding 2 — Author-list punctuation for the NUFFT citation breaks from the "&"-joined convention used by every other 3-author citation

- **Type:** citation
- **Severity:** minor
- **Confidence:** high
- **Locations:**
  - PAGE: interpolation, §10-adjacent prose: "the stencil width and the shape parameter β ... follow the **Barnett–Magland–af Klinteberg ES rule** for the tolerance."
  - Contrast, same page/family: "Catmull & Rom 1974", "Sundaram & Collins 1996", "Hockney & Eastwood 1988", "Birdsall & Langdon 1991", "Brandt & Lubrecht 1990", "Lalescu, Teaca & Carati (2010)".
- **Contradicts:** every other ≤3-author citation in the corpus joins the last two names with `&` (e.g. "Crowe, Sharma & Stock 1977"); the NUFFT-kernel authors are instead joined with en dashes throughout ("Barnett–Magland–af Klinteberg"), the one 3-author name-list in the whole corpus not using the house `A, B & C` form.
- **Description:** A single named rule ("the ES rule") is attributed to three authors joined by en dashes, reading as a hyphenated compound name rather than an author list — every other multi-author in-text citation in the document uses the `&`-joined form. Minor, but it is the one visible inconsistency in an otherwise very disciplined citation-formatting corpus.

## Finding 3 — The measure-taxonomy math anchor (Grafakos) is the one citation not backed by a matching §References entry, unlike every other named/published method

- **Type:** citation
- **Severity:** minor
- **Confidence:** medium
- **Locations:** PAGE: architecture, §13 decision 19: "The math anchor (Grafakos, Classical Fourier Analysis, 3rd ed., Graduate Texts in Mathematics 249, Springer, 2014, Thm 2.5.10)."
- **Description:** Every other named/published method in the corpus (Lalescu splines, TurTLE, van Hinsberg, Fornberg, Sundaram & Collins, Catmull–Rom, the NUFFT kernel, the anterpolation-lineage citations) gets its full bibliographic detail placed in a dedicated "References (this section)" list at the end of its owning section, with the in-text mention staying short (author–year). The Grafakos citation instead carries its full bibliographic detail inline, with no companion entry in any References block anywhere in the document — a structural inconsistency in *where* a full reference lives, even though the content itself is not wrong. A reader scanning only the References blocks for a bibliography would miss this one.

## Finding 4 — TurTLE arXiv identifier cannot be corroborated from the document and is worth an external check

- **Type:** citation
- **Severity:** nit
- **Confidence:** low
- **Locations:** PAGE: architecture / interpolation, three verbatim-identical copies: "Comput. Phys. Commun. 278 (2022) 108406; arXiv:2107.01104."
- **Description:** The three copies of the TurTLE reference are at least mutually consistent (see the positive note below), so this is not an internal-consistency defect — it is a plain outside-knowledge flag from having seen turbulence-tracking literature before: the arXiv id quoted does not match this reviewer's independent recollection of the TurTLE preprint number, though memory alone is not authoritative here. Worth a quick manual cross-check against the published arXiv page before treating it as settled, since a wrong id would silently misdirect every reader who follows it (once links are added per Finding 1).

## Positive notes (not findings, recorded so the panel doesn't re-flag them)

- Every full bibliographic reference that appears more than once (Lalescu 2010, TurTLE 2022, Fornberg 1988, Sundaram & Collins 1996) is **verbatim-identical** at each occurrence (architecture §10, §13, and the `Interpolation` docstrings) — no drift found.
- Author-count discipline is otherwise correct throughout: every ≤3-author work is named in full (`Lalescu, Teaca & Carati`, `Crowe, Sharma & Stock`, …) and every 4-author work correctly collapses to "First et al." in prose (`Lalescu et al. (2022)`, `van Hinsberg et al. (2012)`), with the full reference block still listing all authors.
- No inaccessible source (gitignored monograph, "accompanying thesis," unlinkable appendix/figure) is cited anywhere in the corpus — the anterpolation-lineage citations (Peskin, Hockney & Eastwood, Birdsall & Langdon, Crowe/Sharma/Stock, Brandt & Lubrecht) are all standard, publicly locatable works.
- No overclaiming language was found: "exact" is used carefully and only where substantiated (`DirectDFT` is called exact, `NUFFT` is explicitly qualified "to a requested tolerance ε"), and searches for "optimal," "the first," and unwarranted eponym use turned up nothing.
- Classical/eponymous names used without a citation (K41, Wiener–Khinchin, Parseval, Catmull–Rom as a spline name) are handled correctly per the project's own stated convention — no citation is owed for using an eponymous name, only for citing the work itself.
