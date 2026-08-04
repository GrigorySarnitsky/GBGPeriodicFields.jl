# Normalization & Convention Auditor — findings

Hat: `normalization-convention-auditor`. Scope: mechanical verification of every normalization
factor, sign, and indexing convention (transform normalization, DC-mode scaling, spectral-multiplier
signs, Nyquist handling, Parseval weighting, convolution normalization, and the interpolation/
anterpolation measure factor) across the full rendered site, cross-checked page to page.

Overall: the corpus is unusually disciplined here — the FFT normalization (unnormalized forward /
`1/N` inverse), the DC-mode scale `cN·δ_{k,0}`, the Nyquist split (derivative wavenumbers zeroed,
squared wavenumbers exact), the `α(k)` rfft half-spectrum Parseval weight, the `N/M` interpolation
adjoint factor, the `sinc²` assignment window, the `cos(πh_a/Δx_a)` Nyquist translation factor, and
the `2π/L` wavenumber scaling are all stated identically everywhere they recur (Architecture,
Formalization, Notation, and every relevant API docstring), including across a Formalization page
built specifically to catch this class of drift. Only two defects survived that scrutiny.

---

## Finding 1 — Two incompatible rationales for why `weighted_inner` refuses a `SeparableKernel` weight

**Type:** contradiction
**Severity:** major
**Confidence:** high

**Locations:**
- PAGE "architecture", decision 51 entry: *"`weighted_inner` accepts a radial kernel as a weight and
  deliberately not a separable one — **a magnitude-dependent weight does not factor per axis**, so it
  is not in that family (invariant 1)."*
- PAGE "api / Fields", §Spectral kernel protocol: *"`weighted_inner` on the stored and radial classes
  only, **a separable weight not being real in general**."*
- PAGE "api / Reductions", `weighted_inner` docstring, argument `w`: *"a separable kernel is
  deliberately not accepted, **its factors not being real in general**."*

**Contradicts:** the Architecture page's structural rationale (a magnitude-dependent weight simply
doesn't factor per axis — a *family-shape* argument) versus the Fields/Reductions pages' reality
rationale (separable factors "not real in general" — a *Hermitian-symmetry* argument). These are two
different, non-equivalent justifications for excluding the same kernel class from the same operation.

**Description:** The reality-based rationale is also internally inconsistent with the rest of the
corpus: `assignment_window` — the package's other `SeparableKernel` builder besides `translation_kernel`
— returns per-axis factors that are `sinc²`, which are real by construction (only `translation_kernel`'s
factors are complex). So "a separable weight [is] not real in general" is not true of every
`SeparableKernel`, and the exclusion as stated would wrongly seem to leave open whether a real
separable weight (e.g. a materialized `assignment_window`) should be admissible. The Architecture
page's family-shape rationale is the one that actually holds regardless of realness. A reader who
meets the restriction on the Fields or Reductions page gets a reason that doesn't match the one given
in the design document, and that reason doesn't hold for every instance of the excluded type.

---

## Finding 2 — `var`'s Bessel-correction formula on the Formalization page is not generalized to the point-set base, unlike the adjacent `cov` formula

**Type:** normalization
**Severity:** minor
**Confidence:** medium

**Locations:**
- PAGE "formalization", §Reductions: *"The default applies Bessel's correction on top,
  `var(f) = N/(N-1)·(⟨f,f⟩ − ⟨f⟩²)`, so the identity reads from both representations..."* — here `N`
  was fixed earlier on the same page (§Declarations) as *"$N = N_x N_y N_z$ cells"*, i.e. the
  grid-specific count.
- Two lines later, same page, the `cov` formula: *"$R_{ij} = \frac{B}{B-1}(\dots)$ ... where $B$ is
  the count of the base the section lives over — $N$ cells for a grid, $M$ points for a point set —
  **since `cov` is defined on both**."*
- PAGE "api / Reductions", `Statistics.var` docstring: *"...the Bessel-corrected mean of the squared
  deviation ... $\tfrac{1}{N-1}\sum_n(f_n-\bar f)^2$ over a grid's $N$ cells **and**
  $\tfrac{1}{M-1}\sum_p$ over a point set's $M$ points..."* — confirming `var`/`std` do run over both
  bases, exactly like `cov`.

**Contradicts:** the Formalization page's own `var` formula (stated only with the grid-specific `N`)
against its own `cov` formula immediately following (which explicitly introduces the generic base
count `B` precisely because the same statistic is "defined on both" bases) — and against the
Reductions API page, which spells the Bessel factor for `var` as `N/(N-1)` on a grid *and* `M/(M-1)`
on a point set.

**Description:** The Formalization page is the page whose stated purpose is to force every
normalization constant into the open by expanding it in typed form (per its own §0: "checked by
expansion... a coverage gap to close" if a statement drifts). Its typed statement for the `var`
Bessel correction uses the grid-only symbol `N` where the surrounding text (and the sibling `cov`
statement two lines below) shows the honest general form needs the base count `B` (`N` for a grid,
`M` for a point set). The formula as literally written would read as wrong on a `PointSet`, which
`var`/`std` are documented elsewhere to support.

**Resolution hint (advisory):** restate the `var` Bessel-correction line with the same `B` (or `N`/`M`)
generalization the `cov` line already carries, on the same page.
