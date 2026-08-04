# /check-consistency — consolidated findings (2026-07-24, economy run)

## Run metadata

- **Panel:** 12 hats, **economy tiering** (10 scan hats on Sonnet + the two mathematician
  anchors — `spectral-methods-mathematician`, `differential-geometer` — on Opus 4.8). First live
  exercise of the economy mode.
- **91 findings** total: 60 from the ten workflow hats, 20 (`structure-consistency`) + 11
  (`software-architect`) from the two standalone re-runs.
- **Two hats cap-killed:** `software-architect` and `structure-consistency` overran the 64k
  output-token cap on the first pass (unbounded findings dump); re-run standalone with an output
  cap, and the recurrence guard committed to `panel.js` (`599390a5`).
- **Verification:** every blocker/major was confirmed against current `src/` and the **built
  HTML** before being listed as real (the discipline's "rendered text is not ground truth" rule).
  That step overturned two initial reads — see Dispositions.

## Economy-tier validation (the meta-result)

The tiering worked as designed. The ten Sonnet scan hats produced sharp, evidence-cited findings
and **corroborated the two Opus anchors on every load-bearing item** — the broken `|k|` row was
independently caught by seven hats, the `L²-adjoint` overclaim by the applied and pure
mathematician together, the stale alias-guards by four hats. The one Sonnet **false positive** ("no
citation carries a DOI") was caught by the main-thread verification exactly as the asymmetry
predicts (a cheap hat's false positive is cheap to catch downstream; the anchors exist for the
false-*negative* class that has no verifier). Net: the anchors confirmed the core spectral and
structural mathematics **sound**, the scan hats found the formatting/staleness/consistency defects,
and verification separated real from artifact.

## Dispositions — FIX PASS COMPLETE, all 91 findings closed (updated 2026-07-24)

The collect-only run was followed the same day by a fix pass. Closure **per hat**, which is the
auditable count — the clusters below are a reading aid and under-itemized two hats:

| hat | filed | closed | open |
|---|---|---|---|
| 01 consistency-matrix | 6 | 6 | — |
| 02 software-architect | 11 | 11 | — |
| 03 spectral-methods (Opus) | 5 | 5 | — |
| 04 differential-geometer (Opus) | 6 | 6 | — |
| 05 gpu-kernel-practitioner | 7 | 7 | — |
| 06 structure-consistency | 20 | 20 | — (18 fixed, 2 dismissed with reason) |
| 07 latex-typesetter | 7 | 7 | — |
| 08 api-user | 7 | 7 | — |
| 09 normalization-auditor | 1 | 1 | — |
| 10 citations-integrity | 4 | 3 | — (the fourth is the confirmed false positive) |
| 11 style-editor | 5 | 5 | — |
| 12 cold-reader | 12 | 12 | — |

**Three findings were closed only because the banked files were read directly** — the consolidated
clusters below never itemized them: `04/2` (the horizontal family called "the connection's covariant
derivative", though `inverse_laplacian`/`helmholtz_projection` are nonlocal), `04/3` (`W` reused for a
generic fiber-map codomain against `W` the gather operator on the same page), and `04/4`
(self-adjoint curl asserted and tested with no typed Formalization entry — it is not among the four
unconditional identities listed there). That is why the command file now states that a fix pass is
driven from `NN-*.md`, never from this summary.

**Left with a first-principle reason:** the §13 decision-log mentions of the retired `_guard_noalias!`
and decision 24's pre-decision-42 Helmholtz factor stay as append-only history; `var`/`std` keep the
Bessel-corrected default mirroring `Statistics.var` (user-decided), with the keyword and the
population caveat now documented.

**Commits:** `612c955d` (91-finding fix pass), `ca2a9012`, `da633a43` (decisions 44/45), `96deb989`
(the taxonomy), `5c238029` + `7229de78` (uniformity stage 1 + the four shape rules), `b0286b2c`.

| Cluster | Severity | Hats | Verified | Note |
|---|---|---|---|---|
| C1 broken `\|k\|` notation row | blocker | 7 | ✅ built HTML | fix ready: `\lvert k\rvert` (no pipes) + add κ |
| C2 summaries under-list operations | major | 4 | ✅ source | umbrella + Home stale vs module pages |
| C3 "L²-adjoint pair" overclaim | major | 2 | ✅ source | the slip the formalization page names |
| C4 spline `min(2m+1,2n)` unqualified | major | 1 | ✅ source | wrong at named `LalescuSpline(0,0)` |
| C5 stale "alias-guard" references | major | 4 | ✅ source | retired by decision 39 |
| C6 helmholtz threading §9/TESTING stale | major | 1 | ✅ source | decision 40 gated it; pages contradict |
| C7 convenience-ctor docstring unrendered | major | 1 | ✅ built HTML | `FieldSpectralMultipliers(field)` doc doesn't surface |
| C8 notation-glyph overloads (α, hat, W) | major | 3 | ✅ (â from my d42 edit) | one glyph, two meanings |
| C9 cold-read taxonomy / naming drift | major | 1 | ⚠️ soft | "operation family" & radial-pair framing vary |
| C10 demo/plot typesetting drift | major | 2 | ✅ source | `\mathbf{k}` vs `k`; thin-spaces in plot labels |
| C11 structure/uniformity + stats-under-Internal-API | blocker/major | 2 | ✅ source | public stats under a "not public" heading |
| C12 citation completeness (Grafakos, synonyms) | major | 3 | ✅ source | Grafakos alone has no link/year |
| C13 `\texttt` vs `\mathrm` for code-in-formula | major | 1 | ✅ source | `inner` written both ways |
| C14 gpu "unavailable on GPU" over-generalizes | major | 1 | ✅ source | AMD-rocBLAS-specific stated as "GPU" |
| minors/nits (≈ 30) | minor/nit | — | mixed | see the per-cluster list below |
| FP1 "no citation has a DOI" | — | 1 | ❌ FALSE POSITIVE | 10 DOIs in built HTML; rendered-text artifact |

## Ranked clusters (deduplicated)

### C1 — BLOCKER — Notation `|k|` row breaks the glossary table; κ never defined  [7 hats]
`latex-typesetter`✦blocker, `style-editor`✦blocker, `api-user`✦major, `cold-reader`✦major,
`spectral-methods`✦major, `software-architect`✦minor, `differential-geometer`✦nit — the single
most-corroborated finding. **Source:** `docs/src/notation.md:32` writes the magnitude as `` `|k|` ``;
the literal `|` characters are parsed as GFM table-column delimiters, so the row fragments. **Built
HTML (ground truth):** renders as "…its `a`-th component, `` k" — "its magnitude)" and the entire
`FieldSpectralMultipliers` code cell are dropped, and **κ = |k| is never defined** despite pervasive
downstream use (`radial_spectrum`, shells, the HIST example). Exactly the hazard `CLAUDE.md` names
("keep literal `|` out of cells… bit twice"); this is a live third instance that evades the indented-table
grep guard. **Fix class:** write `\lvert k\rvert` (no pipe chars) and add a κ row.

### C2 — MAJOR — Summary/index surfaces under-list or mis-list operations  [4 hats]
`consistency-matrix`✦major, `cold-reader`✦major, `api-user`✦major+minor. **Verified:** the umbrella
`GBGPeriodicFields` docstring (`src/GBGPeriodicFields.jl:41`) omits `mean`/`std`/`var`/`maximum`/
`minimum`/`extrema` from Reductions, `add!`/`subtract!` from FieldAlgebra, `write_field`/`read_field`
from Fields; the Home page (`index.md:43`) omits `symmetric_gradient` from DifferentialOperators.
Every module's own page lists these — only the top-level maps drifted. **Fix:** complete the summaries.

### C3 — MAJOR — "L²-adjoint pair" overclaim  [2 hats: both mathematicians]
`consistency-matrix`✦major + `differential-geometer`✦minor. **Verified source:** `index.md:46`,
`api.md:14`, and decision 23 call the shipped `W`/`Wᵀ` pair an "L²-adjoint pair/contract", but the
formalization page derives that the true L²-adjoint is `(N/M)Wᵀ` and names the bare-pair claim "the
slip" it exists to catch. Every *equation* carries the M/N factor correctly; only the summary *labels*
overclaim. **Fix:** drop "L²" on the summary surfaces (say "adjoint pair", matching the module page) or
add the N/M caveat.

### C4 — MAJOR — Spline reproduction `min(2m+1,2n)` stated unqualified  [1 hat]
`consistency-matrix`✦major. **Verified:** `ARCHITECTURE.md:737` and the decision-log entry (`:983`)
state the formula with no `(n≥1)` scope, while the `LalescuSpline` docstring scopes it correctly.
Evaluated at the document's own named `LalescuSpline(0,0)` it gives `min(1,0)=0` ("reproduces only
constants") — false; 2-point linear reproduces degree 1. **Fix:** add "(for n≥1)" to both ARCHITECTURE
restatements.

### C5 — MAJOR — Stale "alias-guard" references (retired by decision 39)  [4 hats]
`software-architect`✦major, `spectral-methods`✦minor, `differential-geometer`✦minor, `api-user`✦minor.
**Verified:** `examples/HIST_CPU.jl` comments an aliased `helmholtz_projection!(uh, uh, m)` call
"(alias-guarded)" (its sibling one line up correctly says "alias-safe"); the FieldAlgebra and Points
Internal-API intros list "the alias guard" among current internals. Decision 39 retired the guard
family; the one-pass kernel is alias-safe by construction. **Fix:** reword to "alias-safe, coefficientwise".

### C6 — MAJOR — helmholtz threading: §9/TESTING stale vs decision 40  [1 hat]
`gpu-kernel-practitioner`✦major. **Verified:** ARCHITECTURE §9 first says `helmholtz_projection!`
"left" the KA-only bucket when decision 40 gave it a gated CPU loop; two sentences later, and at
`TESTING.md:81`/`:310`, it is still listed among the KA kernels that "cannot be checked by toggling
`with_threading`". Directly contradictory. **Fix:** drop helmholtz from the KA-only "disjoint-write
pair" wording post-decision-40.

### C7 — MAJOR — `FieldSpectralMultipliers(field)` convenience-ctor docstring never renders  [1 hat]
`api-user`✦major. **Verified built HTML:** the convenience-constructor docstring (`Fields.jl:1179`,
body "Build the spectral multipliers from the grid…") renders **zero** times — `@docs
FieldSpectralMultipliers` surfaces only the *type* docstring (which documents the explicit 6/8-arg
form). Both worked examples and the flagship demo use the 1-arg form, and the type docstring itself
promises the convenience ctor "carries its own docstring" — a broken promise. *(Initially mis-triaged
as a false positive because the docstring exists in source; the built-HTML check corrected it.)* **Fix:**
give the convenience method its own `@docs` entry, or merge its body into the type docstring.

### C8 — MAJOR — Notation-glyph overloads (one glyph, two meanings)  [3 hats]
`cold-reader`✦major (α = caller accumulation weight vs the Parseval multiplicity `α(k)`),
`consistency-matrix`✦minor (the hat accent = "spectral representation" everywhere, reused as the unit
vector `â = a/|a|` in the decision-42 projector formula — *introduced by my own decision-42 edits* to
FORMALIZATION/ARCHITECTURE, while the operator's docstring spells the ratio out and avoids it),
`differential-geometer`✦nit (`W` reused for a generic fiber-map codomain vs the interpolation operator).
**Fix:** the α(k) and â clashes want either a Notation-page gloss or a different local glyph.

### C9 — MAJOR — Cold-read taxonomy / naming drift  [1 hat, soft]
`cold-reader`✦major ×2: "operation family" framed several ways across the user pages (3-kind split
that omits Convolution; Convolution self-declaring; per-operator "family"; one-per-submodule), and the
`{radial_spectrum, radial_correlation}` pair named four ways ("radial pair"/"radial diagnostics"/
"radial reductions"/"the power spectrum & its dual"). Real cold-read friction, but **soft** — no single
page is wrong, and the SITEONLY hat cannot see the ARCHITECTURE §2 taxonomy that actually governs. Treat
as a wording-harmonization item, not a defect.

### C10 — MAJOR — Demo/plot typesetting drift  [2 hats]
`style-editor`✦major + `latex-typesetter`✦minor: `examples/HIST_CPU.jl` (and `HIST_ROCm.jl`) use bold
`\mathbf{k}` for the wavenumber vector — the sole bold-vector use in the corpus — against the
corpus-wide plain italic `k` (notation.md). Motive is legitimate (frees italic `k` for TKE, Pope
convention), but it clashes with "one notation per concept". `latex-typesetter`✦major: the plot-axis
`L"…"` labels in `examples/hist_postprocess.jl:155,172,176,193` insert `\,` thin spaces between
juxtaposed factors — including line 193, the *exact* `C_K ε^{2/3} κ^{-5/3}` formula the notation page
cites as its example of correct juxtaposition. Ships in the figures (that file is not Literate-rendered).

### C11 — BLOCKER/MAJOR — Public stats under an "Internal API / not public" heading + structure uniformity  [2 hats]
`structure-consistency`✦blocker + `api-user`✦major (corroborating): `mean`/`std`/`var`/`maximum`/
`minimum`/`extrema` are named as headline Reductions operations in the module summary, yet their
per-function docstrings render under the page's "## Internal API" heading whose lead sentence says
"not part of the public interface" (they are stdlib method-extensions, so autodocs bins them there).
A reader seeking `mean`'s formula lands under a "these are internal" header. Plus `structure-consistency`'s
uniformity majors (arg-doc runs in 3 incompatible shapes; type docs split prose vs bulleted "The fields
are"; admonition titles mixed; the "Use this in-place form when…" boilerplate is DifferentialOperators-only;
`sym`/`skew`/`dev` use a unique opening template). **Fix:** surface the six stats outside the Internal-API
bin (a dedicated `@docs` group), then a uniformity pass.

### C12 — MAJOR — Citation completeness  [3 hats]
`citations-integrity`✦major (two of four anterpolation-synonym citations get full refs — Hockney &
Eastwood 1988, Birdsall & Langdon 1991 — while the other two don't), `style-editor`✦minor +
`citations-integrity`✦minor (**Grafakos** is verified the *only* one of 10 references on the site with
no clickable DOI/openlibrary link, and no year, despite anchoring a whole design decision by theorem
number), `citations-integrity`✦minor ("Germano and coworkers" no year). **Fix:** add the openlibrary
link + year to Grafakos; complete or drop the two uncited synonyms.

### C13 — MAJOR — `\texttt{}` vs `\mathrm{}` for a code identifier inside a formula  [1 hat]
`latex-typesetter`✦major. **Verified:** `inner` is written `\texttt{inner}` (4×, `src/Reductions.jl`)
and `\mathrm{inner}` (12×, `ARCHITECTURE.md`; also TESTING). `CLAUDE.md` mandates `\texttt{}` for a code
name inside a formula. Same for `destination`/`dest`/`dot`/`tr` in various kernels. **Fix:** normalize to
`\texttt{}` per the rulebook.

### C14 — MAJOR — gpu "unavailable on GPU" over-generalizes an AMD-specific fact  [1 hat]
`gpu-kernel-practitioner`✦major. **Verified:** `ARCHITECTURE.md:1485` scopes the strided-`dot` gap to
"rocBLAS `dotc` … verified on the device" (AMD), but TESTING restates it unqualified as "unavailable on
the GPU" — cuBLAS generally supports strided `dot`. **Fix:** scope the TESTING wording to the ROCm/AMDGPU
backend.

### Minors & nits (≈ 30, grouped)
- **PERFORMANCE staleness (gpu):** the loop-order table's "0.75× (regression)" cell is disowned by the
  next sentence ("does not reproduce"); two un-reconciled `radial_spectrum` 256³ F64 figures (§6 92→2.9 ms
  vs §7 65.95→1.371 ms); finding-(j) helmholtz benchmark describes the pre-decision-40 KA path; the "10⁶
  points at 512³" density doesn't match "~1 per 27 cells".
- **Numbered invariants** (invariant 6 etc.) are cited dozens of times but the list itself is never
  enumerated on the rendered site (it lives in `CLAUDE.md`) — breaks ARCHITECTURE's self-containedness promise.
- **`N` bound two ways** (total `∏Nᵢ` vs per-axis) in the decision-log/PERFORMANCE `8N³` passages; the
  ARCHITECTURE copy lacks the gloss PERFORMANCE carries.
- **`kmaxη` drops `2π/L`** in `HIST_CPU.jl` (harmless only because `L=2π` always).
- **My own recent edits:** the `\,` thin-space in `Reductions.jl:882` (decision-41 radial caveat), the
  `â` glyph clash (decision-42) — both from this week's work.
- **latex:** a gratuitous `\;` in `Convolution.jl:677` (`assignment_window`); a doubled-backtick seam in
  the `maximum` docstring; a possible long-display-overflow candidate (`Interpolation.jl:20`, unverified).
- **software-architect:** `AbstractField` used in signatures but never introduced; Interpolation's "the one
  asymmetry in the API" contradicted by two more; `exponential_convolve!` α/β meaning varies across its
  overloads; `similar_field`/`similar_pointvalues` kept internal though the example reimplements them 8×;
  `Grid3D` stores redundant `grid_spacing`; `var`/`std` Bessel-corrected default on a complete grid population;
  `threading_cutoff` global-mutable vs `with_threading` task-local.
- **style:** Formalization headings bake raw Markdown link syntax into their anchor ids; the Internal-API
  H3 Types/Functions split is applied inconsistently across the 8 module pages.
- **api-user:** `anterpolate!`'s signature block omits the DirectDFT/NUFFT forms its three siblings show.
- **cold-reader clarity:** "module action" (algebra) vs the "— Module" type tag; tr!/det! invariant naming
  (I₁ vs I₃, I₂ never mentioned); "the pair-correlation route" referenced but never set up; "bundle" names
  the architecture but is never glossed; single-arg ⟨·⟩ average absent from the Notation table.
- **decision-24 log** shows the pre-decision-42 `(k,|k|²)` Helmholtz factor (append-only history — low);
  **method count 118→122** doesn't reconcile from the +2 stated (the tr/tr! mirror is unstated); **lpnorm**
  has an orphaned Ω/|Ω| sentence; the **"67 MB field fits in cache"** tensor order is ambiguous.

## Verified-clean (the anchors' + normalization auditor's spot-lists)

The two Opus anchors and the normalization auditor independently re-derived and **confirmed sound**:
the forward-unnormalized/inverse-1/N transform pair and 1/N placement; the constant-add zero-mode ×N
scaling; integral/mean via the DC mode; the `ik`/`−|k|²` signs and the Nyquist split; the exact
decision-42 discrete projector `id − â âᵀ` with the `a·a` denominator (idempotent, solenoidal at every
mode) vs the resolved-band composite; the Parseval half-spectrum weighting (α=1 on self-conjugate planes,
2 else, 1/N²); `sum(radial_spectrum)=inner`, Wiener–Khinchin `C(0)=inner`, `𝓕C=|f̂|²/N`; the
translation-kernel Nyquist construction; the assignment-window ∏sinc²; the DirectDFT type-1/2
measure-adjoint; the spline reproduction degrees and Catmull–Rom=(1,1); the fiber is **never flattened**
(`ℝ^N⊗V`, distinct `𝟙_N`/`𝟙_M` — the past flatten/conflation errors stay fixed); and the K41 constants.
**The core spectral and structural mathematics is sound and internally consistent** — the findings are
formatting, staleness, notation, and completeness, not math errors.

## Confirmed false positive (1)

- `citations-integrity` ✦major "No citation in the substrate carries a visible DOI" — the built site
  has **10 distinct `doi.org` links**; the hat read the consolidated manuscript where hrefs are stripped
  to visible text (it self-hedged to medium confidence for this reason). Artifact of reading rendered
  text, not a defect. The real sub-finding (Grafakos alone lacks a link) is C12.

## Per-hat banked files

`01-consistency-matrix.md` (6) · `02-software-architect.md` (11, re-run) · `03-spectral-methods-mathematician.md`
(5, Opus) · `04-differential-geometer.md` (6, Opus) · `05-gpu-kernel-practitioner.md` (7) ·
`06-structure-consistency.md` (20, re-run) · `07-latex-typesetter.md` (7) · `08-api-user.md` (7) ·
`09-normalization-convention-auditor.md` (1) · `10-citations-integrity.md` (4) · `11-style-editor.md` (5) ·
`12-cold-reader.md` (12).
