# Cold-Reader Review — GBGPeriodicFields Rendered Docs

Reviewer stance: a scientific programmer fluent in Fourier analysis and Julia, but new to
this package, reading the rendered site top-to-bottom with the source and design docs
withheld. Findings below are strictly about terms, symbols, and concepts used before (or
never) defined on the user-facing site — not about correctness of the underlying math.

---

## Finding 1 — The Notation page itself uses undefined terms, breaking its own stated promise

**Type:** clarity
**Severity:** major
**Confidence:** high
**Locations:**
- PAGE: notation, "Scalar weights": "$1$ on a self-conjugate plane of the folded axis, $2$ elsewhere"
- PAGE: notation, opening: "This page is the single reference — a docstring introduces a symbol on first use and need not repeat the convention."

**Description:** The Notation page explicitly bills itself as the self-contained reference
that lets every docstring skip re-explaining a symbol. Yet in its own "Scalar weights"
row for $\alpha(k)$, it uses "a self-conjugate plane" and "the folded axis" with zero
definition anywhere before this point in the site (Home, api overview, and everything
above this row). A cold reader hits jargon on page 3 that only gets explained many pages
later (Fields' `RealFourierLayout`/`FieldSpectralMultipliers`). This directly undercuts
the page's purpose.

---

## Finding 2 — "Nyquist" is used heavily in the first module page read (Convolution) before it is ever defined

**Type:** clarity
**Severity:** major
**Confidence:** high
**Locations:**
- PAGE: api / Convolution, `translation_kernel`: "At the Nyquist frequency of an even-length axis the factor is instead the real number"
- PAGE: api / DifferentialOperators, module docstring (first paragraph): "zeroed at the Nyquist frequency on even-length axes"
- PAGE: api / Fields, `FieldSpectralMultipliers` (convenience constructor): "the highest stored mode is the Nyquist mode: its first-derivative wavenumber is set to zero"

**Description:** In the site's alphabetical module order, Convolution is the first API
module page and DifferentialOperators the second; both open by relying heavily on "the
Nyquist frequency/mode" as if already known. The only place the site actually explains
what "the Nyquist mode" means for this package's storage (why it is special, why
even-length axes) is Fields' `FieldSpectralMultipliers` docstring, read many pages later.
A cold reader is asked to use the concept long before meeting its definition.

---

## Finding 3 — "canonical" multipliers used in Convolution before being defined in Fields

**Type:** clarity
**Severity:** minor
**Confidence:** high
**Locations:**
- PAGE: api / Convolution, `RadialKernel`: "two kernels over canonical multipliers of the same concrete type"
- PAGE: api / Fields, `FieldSpectralMultipliers` (six/nine-argument form): "the convenience constructor marks them canonical, the explicit forms do not"

**Description:** `RadialKernel`'s docstring leans on "canonical multipliers" to explain
when two radial kernels merge under composition, but "canonical" is not explained
anywhere before this point — its actual meaning (multipliers built by the convenience
constructor vs. supplied explicitly) is given only on the later Fields page. A reader
cannot evaluate the claim about merging when it first appears.

---

## Finding 4 — "band-limited" / "the resolved band" used well before its only formal definition

**Type:** clarity
**Severity:** minor
**Confidence:** high
**Locations:**
- PAGE: api / FieldAlgebra, module docstring: "its result is not band-limited"
- PAGE: api / GBGPeriodicFields, module docstring: "The resolved band is the set of wavenumbers a grid's resolution actually represents, up to the Nyquist frequency on each axis."

**Description:** "Band-limited" and "the resolved band" recur constantly from the very
first module pages (Convolution, DifferentialOperators, FieldAlgebra) as load-bearing
concepts for validity statements ("its result is not band-limited... de-alias before
spectral reuse"), but the only page that actually defines what "resolved band" means is
the umbrella `GBGPeriodicFields` module page, positioned well after those pages in
reading order.

---

## Finding 5 — "alias"/"aliasing" is silently overloaded for two unrelated concepts

**Type:** clarity
**Severity:** major
**Confidence:** medium-high
**Locations:**
- PAGE: api / FieldAlgebra, module docstring: "Nonlinear results are aliased in spectral representation" (spectral/Nyquist-folding sense)
- PAGE: api / FieldAlgebra, module docstring: "may be called with the destination aliasing an input" (memory-sharing sense)
- PAGE: api / FieldAlgebra, module docstring: "Alias-safe means the SAME section, not any shared storage"

**Description:** The same word "alias" denotes two physically unrelated phenomena
throughout the docs: (1) two array arguments sharing memory (storage aliasing — "the
destination may alias the source"), and (2) spectral aliasing from a nonlinear
operation's out-of-band content folding back onto resolved modes ("its result... aliases
if transformed back to spectral representation"). Both senses appear in the same
paragraphs of the same docstrings with no disambiguating gloss anywhere on the site,
despite the docs elsewhere being careful to disambiguate overloaded symbols (e.g., the
Notation page's explicit $\alpha$ vs. $\alpha(k)$ split).

---

## Finding 6 — "symbol" (the PDE/Fourier sense) is never explicitly glossed

**Type:** clarity
**Severity:** minor
**Confidence:** medium
**Locations:**
- PAGE: Home, "Main components": "`radial_kernel` builds a kernel from any symbol of $|k|^2$"
- PAGE: api / Convolution, `RadialKernel`: "its symbol, in the sense the differential operators use for the multiplier a coefficientwise operator applies"

**Description:** "Symbol" (a function of the wavenumber representing a coefficientwise
spectral multiplier, as in "the symbol of a differential operator") is used from the
Home page onward as an established term of art, and later docstrings explicitly point
back to "the sense the differential operators use" — but no page ever states in plain
language what a symbol is. A reader without prior PDE/Fourier-operator vocabulary has to
infer it entirely from repeated usage.

---

## Finding 7 — "measure" is never formally defined beyond two concrete instances

**Type:** clarity
**Severity:** minor
**Confidence:** medium
**Locations:**
- PAGE: Home, vocabulary paragraph: "it pairs a section against the base's measure — the reductions, periodic convolution, and the grid↔point transfer, which are one integration structure in three roles"
- PAGE: api / Reductions, module docstring: "against the measure the base carries: a `Grid3D` uses its uniform quadrature (the cell volume), and a `PointSet` uses its counting measure"

**Description:** "Measure" is used as the organizing abstraction tying together
reductions, convolution, and the grid↔point transfer, but the site never states what a
measure is in general (a weighting used to average/integrate over a base) — only the
two concrete instances (cell volume, point counting) are ever given. A reader unfamiliar
with the measure-theory term has to reverse-engineer the generalization from those two
examples.

---

## Finding 8 — "assignment" carries two unrelated meanings across the site with no disambiguation

**Type:** clarity
**Severity:** minor
**Confidence:** medium
**Locations:**
- PAGE: api / FiberSections, `threading_cutoff`: "an assignment is a fused elementwise write into field storage"
- PAGE: api / Convolution, `assignment_window`: "the linear (cloud-in-cell) mass-assignment window... for deconvolving a gridded point density"

**Description:** "Assignment" is defined once, precisely, as the CS/threading term
(a fused elementwise write, gated by `threading_cutoff`) — but "mass-assignment" in
`assignment_window` refers to an unrelated physics/PIC concept (depositing point mass
onto grid cells). Nothing on the site flags that these are different meanings of the
same word, so a reader who has just internalized the threading-page definition may
expect `assignment_window` to relate to threaded writes.

---

## Finding 9 — `LalescuSpline(0, 0)` is named as an explanatory anchor before it is ever defined

**Type:** clarity
**Severity:** minor
**Confidence:** medium
**Locations:**
- PAGE: api / Convolution, `assignment_window`: "the positive linear assignment (`LalescuSpline(0, 0)`, the 2-point linear kernel used for a density)"
- PAGE: api / Interpolation, `LalescuSpline`: "Smooth ($C^m$) local spline interpolation of Lalescu, Teaca & Carati (2010)..."

**Description:** `assignment_window`'s docstring (Convolution page, read early) cites
`LalescuSpline(0, 0)` by name and expects the reader to already understand what that
constructor call means; the type itself is introduced only on the much-later
Interpolation page. A cold reader hits a specific, unglossed type/argument combination
well before its home page.

---

## Finding 10 — "spectral layout" and "Fourier layout" are used as unstated synonyms for the same object

**Type:** clarity
**Severity:** nit
**Confidence:** low-medium
**Locations:**
- PAGE: api / Convolution, `RadialKernel` fields: "the base and spectral layout the kernel was built for"
- PAGE: api / Fields, `RealFourierLayout`: "Layout convention for three-dimensional real-to-complex Fourier transforms" / `field_layout` returns "the `RealFourierLayout` associated with a field"

**Description:** Several pages (Convolution, Interpolation's `_check_nufft_compatibility`)
informally call the same stored object "the spectral layout," while Fields consistently
calls it "the Fourier layout" / `RealFourierLayout` / `fourier_layout`. The two phrases
are never explicitly equated, so a careful reader may wonder briefly whether "spectral
layout" is a distinct concept from the `RealFourierLayout` the rest of the site names.

---

## Summary

The package's public vocabulary (base, fiber, section, representation) is introduced
cleanly and repeated consistently — that part reads well cold. The recurring problem is
structural: the API reference is ordered alphabetically by module (Convolution,
DifferentialOperators, FiberSections, FieldAlgebra, Fields, GBGPeriodicFields,
Interpolation, Points, Reductions), but several load-bearing concepts (Nyquist handling,
the folded/half-spectrum axis, canonical multipliers, the resolved band, named spline
schemes) are defined only on Fields/GBGPeriodicFields/Interpolation — pages that sort
well after the modules that depend on them most (Convolution, DifferentialOperators,
FieldAlgebra). A top-to-bottom cold read meets the *use* of these terms long before their
*definition*. Separately, a few ordinary English words ("alias," "assignment," "symbol,"
"measure") are pressed into service as terms of art without ever being flagged as such,
creating avoidable ambiguity for a first-time reader.
