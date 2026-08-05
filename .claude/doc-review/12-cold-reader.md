# Cold-reader hat — findings

Reviewer stance: a scientific programmer fluent in Fourier analysis and Julia, but new to
this specific package, reading the rendered site top-to-bottom with the design docs withheld.
Findings below are ranked most-severe first.

---

## 1. The symbol `g` is defined as "a field," then reused throughout `Convolution` for "the kernel" — which the module insists is *not* a field

- Type: contradiction
- Severity: major
- Confidence: high
- Locations:
  - PAGE: notation, "Base and fiber" table — `"$f$, $g$ | a field: one value attached to every point of the base..."`
  - PAGE: api / Convolution, module docstring — `"A kernel is not a field."` and, in the very same page, `"a low-pass filter when the kernel $g$ is a smoothing bump: \[(f \star g)(x) = \int_\Omega f(y)\,g(x-y)\,dy\]"`
- Contradicts: the Notation page states it "is the single reference — a docstring introduces a symbol on first use and need not repeat the convention," yet its own canonical table assigns `g` to "a field," and the `Convolution` module — whose central design point is "a kernel is not a field" (a `StoredKernel` wraps a field precisely to change its role) — reuses that exact glyph for the kernel throughout its formulas (`$\hat g$`, `$\hat g(k)=1$ is the identity`, etc.) with no note that this is a deliberate departure from the table.
- Description: A cold reader forms the belief from the Notation page that `f, g` are interchangeable field labels. Arriving at `Convolution`, every formula's `g` is actually the kernel, an object the module repeatedly and emphatically says is not a field. The collision is exactly the kind of "same glyph, two meanings" the docs' own style claims to avoid, and it lands on the module whose entire raison d'être is the field/kernel distinction.

---

## 2. The symbol `W` means the interpolation operator in the Notation table, then means the CIC "tent" window in `assignment_window`

- Type: contradiction
- Severity: major
- Confidence: high
- Locations:
  - PAGE: notation, "Operators" table — `"$W$, $W^{\top}$ | interpolation (gather) and its adjoint anterpolation (scatter) | interpolate, anterpolate"`
  - PAGE: api / Convolution, `assignment_window` — `"As a real physical object $W$ is the linear B-spline ("tent") cloud... the function returns its transfer function $\hat W(k)$, the squared sinc"`
- Contradicts: same axis as finding 1 — the Notation table's stated exclusivity for `W` (the gather map, a linear operator ℝ-section → point-values) versus `assignment_window`'s reuse of `W`/`Ŵ` for a scalar window function and its Fourier multiplier (a convolution kernel). These are different mathematical objects (an operator between different spaces vs. a real-valued function of position/wavenumber), not the same `W` restated.
- Description: `assignment_window`'s own text even connects the window to `LalescuSpline(0, 0)`, the linear interpolation kernel — so the reuse is thematically motivated — but the docstring never says "this `W` is unrelated to `interpolate`'s `W`," and a cold reader who just memorized the Notation table's `W ≡ interpolate` will misread the window formulas as somehow about the gather operator itself.

---

## 3. `κ` is reserved for the radial shell magnitude, then reused per-axis in `translation_kernel`

- Type: contradiction
- Severity: major
- Confidence: high
- Locations:
  - PAGE: notation, "Base and fiber" table — `"$\kappa$ | a wavenumber-shell magnitude, $\kappa = \lvert k\rvert$ — the radial coordinate a spectrum is resolved over"`
  - PAGE: api / Convolution, `translation_kernel` — `"\hat g(k) = \prod_{a=1}^{3} [\cos(\kappa_a h_a) - i\sin(\tilde\kappa_a h_a)]$, where $\kappa_a$ is the true wavenumber and $\tilde\kappa_a$ the Nyquist-zeroed derivative one"`
- Contradicts: the Notation table already has a symbol for a wavenumber's per-axis component, `k_a` ("$k$ | a wavenumber vector ($k_a$ is its $a$-th component...)"). `translation_kernel` needed a second, unreserved name to distinguish "true" from "Nyquist-zeroed" per-axis wavenumbers, and picked the one letter the table had already pinned to a completely different quantity (the scalar shell radius used throughout `Reductions`).
- Description: A reader who has just internalized "κ = |k|, the radial spectrum coordinate" (used consistently and correctly in `radial_spectrum`/`radial_correlation`) then meets `κ_a` meaning something else entirely — an axis-indexed wavenumber component, indistinguishable in spirit from the table's own `k_a`. Nothing in `translation_kernel`'s text flags the reuse.

---

## 4. `N` and `M` are used unglossed on the very first content page, before the Notation page defines them

- Type: organization
- Severity: minor
- Confidence: high
- Locations:
  - PAGE: Home, "Main components" — `"exactly L²-adjoint after the measure rescaling by $N/M$ that the module page derives"`
  - PAGE: notation, "Base and fiber" table (page 3 of the site, after Home) — `"$N$ | the grid-point count..."`, `"$M$ | the number of points..."`
- Description: In a strict top-to-bottom read, `N/M` appears on the very first page with no gloss (unlike `W`/`W^\top` in the same sentence, which the surrounding prose does name as "gather"/"scatter"). The formal definitions of `N` and `M` do not arrive until the Notation page, two pages later. A first-time reader has no way to know at that point whether `N/M` means "grid points over sample points" or something else.

---

## 5. "The resolved band" is used before it is defined

- Type: organization
- Severity: minor
- Confidence: high
- Locations:
  - PAGE: api / DifferentialOperators, `helmholtz_projection!` — `"an identity exact on the resolved band (the inverse Laplacian keeps the true $k^2$ while the projector is built from the derivative family — the two coincide off the Nyquist planes)"`
  - PAGE: api / GBGPeriodicFields — `"The resolved band is the set of wavenumbers a grid's resolution actually represents, up to the Nyquist frequency on each axis."`
- Description: The umbrella `GBGPeriodicFields` page is where "the resolved band" is formally introduced as one of "three words [that] recur in every operation's documentation," but the module pages are ordered alphabetically, so `Convolution` and `DifferentialOperators` (which both use the phrase) are read before it. A cold reader hits "the resolved band" in `helmholtz_projection!`'s docstring with only context to go on.

---

## 6. The package's "three roles of one structure" idea is given three different names across pages

- Type: normalization
- Severity: minor
- Confidence: medium
- Locations:
  - PAGE: Home — `"the reductions, periodic convolution, and the grid↔point transfer, which are one integration structure in three roles"`
  - PAGE: api / Convolution, module docstring — `"This is the kernel-multiplier role of the package's measure structure..."` followed, in the same paragraph, by `"The reductions, this module, and the grid↔point transfer realize one integration structure in three roles."`
  - PAGE: api / Reductions, module docstring — `"The L² / measure structure on sections — the third operation family..."`
- Description: The same underlying concept is called "integration structure," "measure structure," and "L² / measure structure" across three pages — and `Convolution`'s own module docstring uses two of the three names in the same paragraph, without ever stating they denote the same thing. A cold reader has to infer the equivalence rather than being told it.

---

## 7. "Each reduction above also accepts a leading function" reads as broader than the five reductions that actually do

- Type: contradiction
- Severity: minor
- Confidence: medium-high
- Locations:
  - PAGE: api / Reductions, "The parts are" bullet list — `"The mapped forms — each reduction above also accepts a leading function, applied to the fiber value at every base point..."` (this bullet follows ones for `integral`, `mean`/`std`/`var`/`cov`, `inner`, `maximum`/`minimum`/`extrema`, and the radial reductions)
  - PAGE: api / Reductions, closing note — `"Five of the reductions — `integral`, `mean`, `maximum`, `minimum` and `extrema` — also have a mapped form..."`
- Contradicts: "each reduction above" (which follows bullets for `std`/`var`/`cov`, `inner`, `radial_spectrum`/`radial_correlation` too) versus the later, precise "five of the reductions."
- Description: Reading the module docstring's own bulleted list top to bottom, "each reduction above" most naturally scopes over every preceding bullet in that same list — including `inner`, `std`/`var`/`cov`, and the radial reductions, none of which in fact gain a mapped form. Only the closing paragraph near the bottom of the page narrows this to exactly five names. A reader who stops at the module docstring (as the rubric's own "module docstring = map" convention encourages) comes away with the wrong scope.

---

## 8. `SpectralKernel` is used as a dispatch type in many signatures before its defining docstring is reached

- Type: organization
- Severity: nit
- Confidence: medium
- Locations:
  - PAGE: api / Convolution — `"convolve!(destination, field, kernel::SpectralKernel)"` (module docstring, first of many signatures using the name)
  - PAGE: api / Convolution, "Kernel storage classes" intro — `"Every operation taking a kernel dispatches on `SpectralKernel`... It is documented with `Fields`..."`
  - PAGE: api / Fields, "Spectral kernel protocol" — the actual `SpectralKernel` type docstring
- Description: `SpectralKernel` appears as a type annotation in roughly ten signatures across `Convolution` and `DifferentialOperators` before its own supertype docstring, on the later `Fields` page. The forward reference is explicitly signposted ("documented with `Fields`"), which softens this, but a reader following the site's alphabetical module order still meets the type used long before meeting its "home."

---

## 9. `fft_dims[1]` is used as shorthand for "the folded axis" before `RealFourierLayout` (the type that owns that field) is introduced

- Type: organization
- Severity: nit
- Confidence: medium
- Locations:
  - PAGE: notation, α(k) row — `"...on the folded axis (the layout's `fft_dims[1]`, not necessarily the first physical axis)..."`
  - PAGE: api / Fields, `RealFourierLayout` — the type whose field `fft_dims` is being referenced, introduced much later
- Description: The Notation page (read third) treats `fft_dims[1]` as a known code identifier, but the type that defines this field, `RealFourierLayout`, is not documented until the `Fields` module page, read far later in an alphabetical module walk. The gloss given ("the folded axis is the one the real-to-complex transform halves") is good enough to get by, but the specific code path `fft_dims[1]` is unexplained baggage at that point.

---

## 10. "Canonical" multipliers are used in `RadialKernel`'s composition rule before the concept is fully defined

- Type: organization
- Severity: nit
- Confidence: low-medium
- Locations:
  - PAGE: api / Convolution, `RadialKernel` — `"two kernels over canonical multipliers of the same concrete type... merge, while a kernel over a caller's own coordinates keeps both operands as a `ProductKernel`"`
  - PAGE: api / Fields, `FieldSpectralMultipliers` — `"Whether the arrays were derived from the grid or supplied by the caller is recorded in the type, as a final `Canonical` parameter..."` (the fuller explanation, on the later page)
- Description: `RadialKernel`'s own docstring does gloss "canonical" reasonably ("built by the convenience constructor from the grid" vs. "supplied through the explicit constructor"), so this is a soft finding, but the authoritative explanation of why canonicity is a *type-level* fact (and therefore decidable at compile time, which is the actual point of the composition rule) is a page away and read later.
