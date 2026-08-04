# Doc Review — Hat: Computational Scientist (API User)

Reviewer stance: I tried to use this library from the rendered docs alone — build a field,
transform it, take a gradient, convolve, reduce, interpolate to points — and checked
constructors, argument/return documentation, and cross-consistency between the various
"map" summaries and each operation's own docstring. All quotes below are taken verbatim
from `manuscript-full.md` (the "PAGE:" banners identify the source page).

Findings are ordered by severity (major first).

---

## Finding 1 — `FieldSpectralMultipliers(field)`, used in the tutorial and the flagship example, has no discoverable docstring

- **Type:** api-gap
- **Severity:** major
- **Confidence:** high

**Locations:**
- PAGE: tutorial — `julia> multipliers = FieldSpectralMultipliers(scalar_spectral);` (Differential
  operators section) and PAGE: examples / hist_cpu — `m = FieldSpectralMultipliers(uspec0)`: the
  one-argument convenience constructor is the form actually used by both worked examples on the
  site.
- PAGE: api / DifferentialOperators (module docstring): "The wavenumber symbols are held in a
  `FieldSpectralMultipliers`, built from a field with `FieldSpectralMultipliers(field)` or from
  the explicit six-array constructor."
- PAGE: api / Fields, `FieldSpectralMultipliers` — Type: the rendered signature block shows only
  the two six-array constructors —
  ```
  FieldSpectralMultipliers(grid::Grid3D{T}, fourier_layout::RealFourierLayout,
    wavenumber_1, wavenumber_2, wavenumber_3,
    squared_wavenumber_1, squared_wavenumber_2, squared_wavenumber_3) where {T<:AbstractFloat}

  FieldSpectralMultipliers(field::AbstractFieldSpectral{T},
    wavenumber_1, wavenumber_2, wavenumber_3,
    squared_wavenumber_1, squared_wavenumber_2, squared_wavenumber_3) where {T<:AbstractFloat}
  ```
  — followed by the explicit promise: "A convenience constructor `FieldSpectralMultipliers(field)`
  builds both families from the field's grid and layout with the correct Nyquist treatment; **it
  carries its own docstring.**"

**Description:** The one-argument form `FieldSpectralMultipliers(field)` is not a minor
convenience — it is the constructor a normal user actually calls (both the Getting-Started
tutorial and the HIST_CPU.jl example use it exclusively; neither ever calls the six-array form).
The Fields API page's own text asserts that this constructor "carries its own docstring," but no
such docstring — no signature block, no argument list, no description of what `field`'s type must
be or what it returns — appears anywhere on the Fields page or anywhere else in the manuscript
(I grepped every occurrence of `FieldSpectralMultipliers` in the document). A reader following the
tutorial who wants to know what `FieldSpectralMultipliers(scalar_spectral)` actually requires
(does it accept any tensor order? Any representation? What if a physical field is passed instead
of a spectral one?) has nothing to consult beyond the two unrelated six-array signatures and a
promise that goes nowhere.

**Resolution hint:** Either the convenience constructor's docstring failed to attach to the
binding (and needs restoring in `src/Fields.jl`), or `docs/make.jl`'s `@docs` block for
`FieldSpectralMultipliers` only picked up two of the three methods. Either way, add a signature
block for `FieldSpectralMultipliers(field::AbstractFieldSpectral)` to the Fields API page.

---

## Finding 2 — `mean`, `std`, `var`, `maximum`, `minimum`, `extrema` are filed under "Internal API," which says they are "not part of the public interface"

- **Type:** organization (borders on contradiction)
- **Severity:** major
- **Confidence:** high

**Locations:**
- PAGE: api / Reductions, module docstring (top of page) lists these as two of the module's five
  headline families: "`mean`, `std`, `var` — the intensive, fiber-preserving base moments (they
  extend `Statistics`; the `mean` of a vector field is a `FiberVector`)..." and "`maximum`,
  `minimum`, `extrema` — the $L^\infty$ end, extending `Base`. The bare forms take a scalar
  section; the mapped forms below extend them to every tensor order."
- Same page, immediately before the internal-API heading: "The `mean`, `std`, and `var` moments
  (extending `Statistics`) and the `maximum`, `minimum`, and `extrema` order statistics (extending
  `Base`) are also defined for sections... they are **method extensions of the standard-library
  generics rather than package exports**, and are described in the module summary above."
- Same page, the very next heading: "## Internal API / **These symbols are not part of the public
  interface**; they are documented for contributors — the base measure (count and cell measure)
  and the fiber-preserving reduction helper." Immediately under this heading sit the actual
  docstring blocks: `Base.extrema`, `Base.maximum`, and further down `Statistics.mean`,
  `Statistics.std`, `Statistics.var`.
- Corroborating: both PAGE: Home and PAGE: api (overview) list the Reductions page's table of
  contents identically as "Integral reductions / Inner-product and norm reductions / Radial
  reductions / Internal API" — there is no fifth, "moments"-labeled public subsection anywhere in
  the navigation, so the misfiling is baked into the page structure, not a one-off rendering
  accident.

**Description:** Regardless of the technical rationale offered ("method extensions... rather than
package exports"), the section header a reader actually lands on says point-blank that `mean`,
`std`, `var`, `maximum`, `minimum`, and `extrema` are not part of the public interface — directly
contradicting the same page's own module docstring, which names them as core, load-bearing
reduction families (and which the HIST_CPU.jl example, the Architecture decision log, and the
Testing coverage all treat as first-class stable API). A user hunting for the documented behaviour
of `mean` — is it fiber-preserving? Bessel-corrected? Does it accept a mapped form? — finds the
answer only after being told they are looking in the wrong place.

**Resolution hint:** Give these six functions their own `##`-level subsection (e.g. "Moments and
order-statistic reductions") parallel to "Integral reductions" / "Inner-product and norm
reductions" / "Radial reductions," instead of the `@autodocs`/Internal-API catch-all.

---

## Finding 3 — Notation-page table row for the wavenumber symbol `k` is garbled/truncated

- **Type:** format
- **Severity:** major
- **Confidence:** high

**Location:** PAGE: notation, "Base and fiber" table. Every other row in the table has exactly two
`|` separators (three columns: Symbol / Meaning / Code):
```
$M$ | the number of points | npoints
$k$ | a wavenumber vector ($k_a$ is its $a$-th component, `` | k
$h$ | a physical displacement ($h_a$ is its component along axis $a$); $\Delta$ is reserved for the Laplacian, and $\Delta x_a$ for the grid spacing | translation_kernel
```

**Description:** The `k` row breaks off mid-sentence ("...its $a$-th component, `` | k") with no
"Meaning" text completed and no "Code" column at all — unlike every neighboring row, which is a
clean three-column entry. This is the wavenumber symbol, arguably the single most heavily used
symbol on the entire site (it appears in nearly every spectral formula across Architecture,
Formalization, DifferentialOperators, and Convolution), so a broken glossary entry for it is
disproportionately costly to a reader trying to pin down the code binding. The shape of the defect
— a table row terminating exactly at a stray "`` |`` inside what was clearly meant to be an
absolute-value notation `` `|k|` `` — is the classic markdown-table failure mode where a literal
pipe character inside a table cell is parsed as a new column delimiter, truncating everything after
it. The "Code" column value for `k` (probably something like `wavenumber_1`/`FieldSpectralMultipliers`)
never renders at all.

**Resolution hint:** Escape or rephrase the `|k|` reference inside that cell (e.g. move the
absolute-value notation out of the pipe-delimited row, or use `\lvert k \rvert` instead of a
backtick-wrapped `|k|`), and restore the row's Code column.

---

## Finding 4 — Home page and umbrella module docstring disagree on whether `DifferentialOperators` includes `symmetric_gradient`

- **Type:** contradiction
- **Severity:** minor
- **Confidence:** high

**Locations:**
- PAGE: Home, "Main components": "`DifferentialOperators`: spectral differential operators —
  gradient, divergence, curl, Laplacian, inverse Laplacian, and Helmholtz projection." —
  `symmetric_gradient` is not named.
- PAGE: api / GBGPeriodicFields, module docstring: "`DifferentialOperators` provides the spectral
  operators `gradient`, `divergence`, `curl`, `symmetric_gradient`, `laplacian`,
  `inverse_laplacian`, and `helmholtz_projection`." — `symmetric_gradient` **is** named.
- Contradicts: PAGE: api / DifferentialOperators itself devotes a full subsection to
  `symmetric_gradient!`/`symmetric_gradient` under "## First-order differential operators," and its
  own module docstring lists it as one of seven operation families, so it is unambiguously a
  first-class, documented operator — just inconsistently rostered at the summary level.

**Description:** Two different "map" one-liners for the exact same module, on the same
documentation site, list a different set of operators. A reader who only reads the Home page's
component list (a very natural first stop) would not know `symmetric_gradient` exists at all.

---

## Finding 5 — Top-level one-liner summaries recurrently omit operations that each module's own docstring documents (a pattern, not a single instance)

- **Type:** api-gap
- **Severity:** minor
- **Confidence:** medium-high

**Locations / instances:**
1. **DifferentialOperators / `symmetric_gradient`** — see Finding 4 above (omitted from the Home
   page list only).
2. **Reductions / the moments and order statistics** — PAGE: api / GBGPeriodicFields, module
   docstring: "`Reductions` provides the L²/measure reductions `integral`, `inner`,
   `weighted_inner`, `l2norm`, and `lpnorm`, plus the radial diagnostics `radial_spectrum` and
   `radial_correlation`." This omits `mean`, `std`, `var`, `maximum`, `minimum`, `extrema`
   entirely — even though the Reductions module's own docstring (PAGE: api / Reductions) names
   these as two of its five headline families (see Finding 2), and PAGE: Home's own Reductions
   bullet *does* enumerate them ("...the normalized, intensive `inner`, `l2norm`, `lpnorm`, and
   `mean`/`std`/`var`... plus the measure-independent `maximum`/`minimum`/`extrema`..."). So the
   two top-level summaries disagree with each other here too, in the opposite direction from
   Finding 4.
3. **Fields / HDF5 persistence** — PAGE: Home, "Main components": "`Fields`: grids, Cartesian
   fiber types, field representations (physical and spectral), FFT transforms, field utilities,
   and broadcasting support." and PAGE: api / GBGPeriodicFields, module docstring: "`Fields`
   supplies the field and grid types, the storage layout and broadcasting, the FFT transform
   plans, and the transforms `to_physical` and `to_spectral` between the two representations." —
   neither mentions `write_field`/`read_field` at all, even though the Fields module's own
   docstring (PAGE: api / Fields) lists "Persistence — `write_field` and `read_field` map a field
   to and from one self-describing HDF5 group..." as one of its six named provisions, and the page
   devotes an entire "## HDF5 persistence" section to it.

**Description:** Taken together, these three instances (spanning three different modules) show
that neither of the site's two "map" layers — the Home page's "Main components" list nor the
`GBGPeriodicFields` umbrella module's own docstring — is reliably a complete précis of what each
submodule documents on its own page. Each is complete for some modules and stale for others, and
(per Finding 4 / instance 2 above) the two summaries even disagree with *each other* about which
module gets the fuller treatment. Individually these are minor completeness gaps (the operations
are all correctly documented one click away, on the module's own page); together they indicate the
top-level summaries are not being kept in lockstep with the module docstrings as new operations
land.

---

## Finding 6 — `anterpolate!`'s canonical-signature block omits the spectral (`DirectDFT`/`NUFFT`) forms shown for all three sibling functions

- **Type:** api-gap
- **Severity:** minor
- **Confidence:** medium

**Locations:**
- PAGE: api / Interpolation, `interpolate!` shows three canonical signatures — the spline form,
  `..., scheme::DirectDFT)`, and `..., scheme::NUFFT)`.
- Same page, `anterpolate` (allocating) shows three canonical signatures — the spline form,
  `..., scheme::DirectDFT)`, and `..., scheme::NUFFT)`.
- Same page, `anterpolate!` (in-place) shows **only one**:
  ```
  anterpolate!(field::AbstractFieldPhysical, points::PointSet,
               quantities::AbstractPointValues,
               scheme::AbstractSplineScheme = CatmullRom,
               α::Real = true, β::Real = false)
  ```
  even though its own prose says: "the physical-domain local splines... scatter onto a
  physical-space field, while `DirectDFT` and `NUFFT` deposit into a field in spectral
  representation" — describing a signature variant (`field::AbstractFieldSpectral`,
  `scheme::DirectDFT`/`NUFFT`) that is never actually shown.

**Description:** Of the four sibling transfer functions on this page, three show all three
canonical forms (spline / DirectDFT / NUFFT) and one — the in-place scatter, arguably the most
performance-sensitive of the four since it is the one used in a two-way-coupling hot loop — shows
only the spline form. A user wanting to call `anterpolate!` with a spectral field and `DirectDFT`
or `NUFFT` has no shown signature to check argument order or types against, unlike everywhere else
on the page.

---

## Finding 7 — HIST_CPU.jl example comment calls an aliased `helmholtz_projection!` call "alias-guarded," contradicting the documented alias-safe-by-construction / guard-retired design

- **Type:** contradiction
- **Severity:** minor
- **Confidence:** high

**Locations:**
- PAGE: examples / hist_cpu, `random_solenoidal`:
  ```
  convolve!(uh, uh, envelope)                             # apply it (alias-safe, coefficientwise)
  helmholtz_projection!(uh, uh, m)                        # make solenoidal (alias-guarded)
  ```
- Contradicts PAGE: api / DifferentialOperators, `helmholtz_projection!` docstring: "The
  `destination` may alias `field` **at no cost**: the projection is computed in a single pass that
  reads all three components of a mode before writing any of them, so the aliased call **needs no
  temporary**."
- Contradicts PAGE: architecture, decision log (the one-pass Helmholtz kernel entry): "an in-place
  call (destination aliasing the source) was detected and routed through a guard temporary costing
  one full vector field per call... alias-safe by construction — all of a mode's reads precede its
  writes... so **the guard and its temporary are retired**."

**Description:** The word "guarded" is a holdover from the pre-decision-32 design, where an
aliased in-place `helmholtz_projection!(x, x, m)` really was routed through a copy-back guard
temporary (costing a full field per call, described elsewhere as "the single largest transient" in
the consumer's measured budget). The current, extensively documented behaviour is the opposite: the
aliased call is alias-safe *by construction*, with the guard mechanism explicitly retired, and the
call costs nothing extra. The comment one line above it, on the analogous aliased `convolve!` call,
correctly says "alias-safe" — making the very next line's "alias-guarded" read as an internal
inconsistency within the same code block, not just a drift from the rest of the site. A reader of
the flagship example, taking the comment at face value, would come away believing
`helmholtz_projection!` still needs (or silently pays for) a guard when aliased, which is exactly
what the rest of the documentation goes out of its way to say is no longer true.

---

## Notes on what checked out cleanly

For completeness: I hand-verified every doctest in the Getting-Started tutorial (the `inner(u,u) =
1.5` and `sum(spectrum) = 1.5` results follow exactly from `u = (sin x, cos y, sin z)` on a
16-point-per-axis grid, where the discrete sum of `cos(2x)` over a full period vanishes exactly, so
`⟨sin²⟩ = ⟨cos²⟩ = 1/2` to round-off — matching the doctest output precisely) and cross-checked
every constructor call in both the tutorial and HIST_CPU.jl against its documented signature
(`Grid3D`, `VectorFieldPhysical`/`Spectral`, `ScalarFieldPhysical`/`Spectral`, `RealFourierLayout`,
`FieldTransformPlans`, `PointSet`) — all consistent. I also re-derived the RK2 integrating-factor
update in `step!` term-by-term against the displayed formula
($\hat u_{n+1} = \mathcal E \hat u_n + \tfrac{\Delta t}{2}(\mathcal E \hat N_1 + \hat N_2)$) and the
in-place `convolve!(uh, uh, band, scale-1, 1)` rescaling identity in `force!` — both are
mathematically exact matches for what the code computes. `FieldAlgebra`, `Convolution`, and
`DifferentialOperators` (aside from Findings 1, 4, 6, 7 above) document every argument and default
I checked, including keyword arguments on `NUFFT`, `LalescuSpline`, and `LagrangeSpline`.
