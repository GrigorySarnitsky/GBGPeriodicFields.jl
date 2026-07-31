# Cold-Reader Review — GBGPeriodicFields rendered site

Hat: **scientific programmer, comfortable with Fourier analysis and Julia, but NEW to this
package**, reading the user-facing site top-to-bottom with the source and the design docs
withheld. The acceptance test throughout is the **cold read**: a noun or symbol that silently
assumes I already hold the package's context is the defect.

Pages read (site-only consolidation): Home, api (overview), notation, tutorial, and the API
pages Convolution / DifferentialOperators / FiberSections / FieldAlgebra / Fields /
GBGPeriodicFields / Interpolation / Points / Reductions, plus the examples/hist_cpu Literate page.

Overall: the *mathematics* is strikingly internally consistent (the rfft half-spectrum weight
α(k), the 1/N vs 1/M measures, the index conventions, the det/tr invariants, the Parseval
normalizations all line up across pages — I could not find a numeric contradiction). The defects
are about **self-containedness and dead cross-references**, plus a couple of structural gaps.

---

## Finding 1 — `FieldSpectralMultipliers(field)` is promised "documented separately below" but never documented; it is the form everyone actually uses

- **type:** api-gap
- **severity:** major
- **confidence:** high
- **locations:**
  - PAGE: api / Fields — "Transform-plan and multiplier types" → `FieldSpectralMultipliers`. The type docstring documents **only** the two explicit six-array constructors (`FieldSpectralMultipliers(grid, layout, wavenumber_1…squared_wavenumber_3)` and `FieldSpectralMultipliers(field, wavenumber_1…squared_wavenumber_3)`), then says: *"These two constructors are explicit: you supply both the wavenumbers and the squared wavenumbers… A convenience constructor `FieldSpectralMultipliers(field)` builds both families from the field's grid and layout with the correct Nyquist treatment; **it is documented separately below.**"*
  - No `FieldSpectralMultipliers(field)` one-argument entry appears anywhere below on the Fields page (the remaining entries are Transform operations, accessors, FFT threads, and Internal API — none of them the convenience constructor).
  - PAGE: api / DifferentialOperators — module docstring: *"The wavenumber symbols are held in a `FieldSpectralMultipliers`, built from a field with `FieldSpectralMultipliers(field)` or from the explicit six-array constructor."*
  - PAGE: tutorial — "Differential operators": `multipliers = FieldSpectralMultipliers(scalar_spectral);` — the tutorial's only way to build multipliers is exactly this undocumented one-argument form.
- **description:** The docstring explicitly forward-references a convenience constructor ("documented separately below") that is absent from the rendered page. This is both a **dead cross-reference** ("below" points to nothing) and a genuine **doc hole**: the one-argument `FieldSpectralMultipliers(field)` is the constructor the tutorial, the DifferentialOperators overview, and the HIT example all invoke, yet a reader who needs to know its Nyquist behaviour, its argument, or even that it exists as its own method finds only a pointer that goes nowhere. A cold reader following the tutorial hits `FieldSpectralMultipliers(scalar_spectral)` and, on clicking through to the type, is told the real doc is "below" — and it isn't.
- **resolution_hint:** Either add the standalone docstring/`@docs` entry for the one-argument constructor, or fold its description into the type docstring and drop the "documented separately below" pointer.

---

## Finding 2 — The central fiber-bundle vocabulary (base / section / tensor bundle / fiber) is never plainly defined on the reader's entry path; the tutorial defers the mental model to a design doc a site reader cannot open

- **type:** clarity
- **severity:** major
- **confidence:** medium
- **locations:**
  - PAGE: tutorial — intro: *"The mental model (`docs/ARCHITECTURE.md` §2): a field is a real physical object — a section of a tensor bundle over a periodic box."* and the closing line *"`docs/ARCHITECTURE.md` explains why the package is shaped this way."* The designated entry point ("New here? Start with the Getting started tour", per the Home page) introduces the core concept only by pointing at a repo-path/§-number a reader on the rendered site or at the REPL cannot follow.
  - PAGE: notation — "Base and fiber" table: *"$f$, $g$ | a field — **a section of the tensor bundle over the base** | —"*. The glossary defines the field in terms of three words ("section", "tensor bundle", "base") that it never itself defines; the section is *titled* "Base and fiber" yet defines neither "base" nor "fiber".
  - PAGE: Home — "Main components", Reductions bullet: *"the L²/measure structure — **base reductions** over fields and point-values … integrating **the base** away against its measure … (sup/inf over **scalar sections**)"* — "base" and "section" used as load-bearing terms of art on the landing page with no gloss.
  - The plainest binding sits on PAGE: api / FiberSections (a page whose own Internal-API framing is "documented for contributors"): *"A field (a section over a `Grid3D`) and a collection of off-grid point-values (a section over a `PointSet`) are both sections of a tensor bundle over a base."* — correct, but far from where the vocabulary is first used, and on a foundations page a user is unlikely to reach first.
- **description:** "base", "section", and "tensor bundle" are the package's foundational nouns and appear on Home, the tutorial, Reductions, Convolution, Interpolation, and Points, but the only place they are actually bound in plain language is the contributor-facing FiberSections page (where "base" = the `Grid3D` or `PointSet`). "fiber" gets a one-word parenthetical gloss in the tutorial ("The fiber (tensor order) is set by the constructor"), but "base" never gets even that on any headline page. A cold reader must reverse-engineer "base = the domain (grid or point set)" from usage. The tutorial — the one page meant to onboard — punts the whole mental model to `docs/ARCHITECTURE.md §2`, which is exactly the surface a cold/REPL reader cannot reach.
- **resolution_hint:** Give the tutorial (or the notation "Base and fiber" header) one plain sentence: the *base* is the domain a field lives on (a grid or a point set); a *section* assigns a fiber value (a scalar/vector/tensor) to each base point; the *fiber* is that per-point tensor. Replace the `docs/ARCHITECTURE.md §2` path with a live link to the rendered Architecture page.

---

## Finding 3 — The rendered HIT example cites the package's internal numbered invariants ("invariant 11", "invariant 12") and "the README", none of which exist on the user-facing site

- **type:** clarity
- **severity:** minor
- **confidence:** medium
- **locations:**
  - PAGE: examples / hist_cpu — "Right-hand side and time integration": *"`to_physical!` consumes its spectral source **(invariant 11)**."*
  - Same page, "Spectral utilities and the preallocated workspace": *"(their $\nu$ / $\Delta t$ / width are the consumer's, **per invariant 12**)."*
  - Same page, `step!`: *"(the buffer `ws.Ek`; $\nu$, $\Delta t$ are physics — **invariant 12**)"*.
  - Same page, "Initial condition": *"(The random-solenoidal IC generator is the one remaining package gap — **see the README**.)"*
- **description:** The example page is a rendered doc surface, but it repeatedly cites the package's numbered-invariant list ("invariant 11" = the transform input contract; "invariant 12" = the no-time/no-particles rule) and "the README". A cold reader has no glossary of numbered invariants anywhere on the site (they live in the design docs / CLAUDE.md), and "the README" is not a page a docs-site reader can necessarily follow. These read as "you are missing a document you should have" — the same class the project's own policy bans for docstrings ("must not cite a §-number or a repo path"). The parenthetical *reasons* are fine; it is the bare invariant-number citation that dangles.
- **resolution_hint:** State the reason in words on the page ("`to_physical!` may overwrite its spectral source, so we transform a copy") and drop the invariant number, or link the rendered Architecture page anchor.

---

## Finding 4 — `mean` / `std` / `var` / `maximum` / `minimum` / `extrema` are advertised as reductions but have no dedicated docstring; `std`/`var` normalization and the base-average semantics are left unspecified

- **type:** api-gap
- **severity:** minor
- **confidence:** medium
- **locations:**
  - PAGE: Home — "Main components", Reductions bullet lists them as first-class reductions: *"`mean`/`std`/`var` integrating the base away against its measure, plus the measure-independent `maximum`/`minimum`/`extrema` (sup/inf over scalar sections)"*.
  - PAGE: api / Reductions — closing note: *"The `mean`, `std`, and `var` moments (extending `Statistics`) and the `maximum`, `minimum`, and `extrema` order statistics (extending `Base`) are also defined for sections; they are method extensions of the standard-library generics rather than package exports, and **are described in the module summary above.**"* The only "description" is the one-line module bullets: *"`mean`, `std`, `var` — the intensive, fiber-preserving base moments (they extend `Statistics`; the `mean` of a vector field is a `FiberVector`)."*
- **description:** These are public, user-visible reductions (the landing page presents them as such), yet none carries a home docstring with a signature, a formula, or the per-base coverage every other reduction on the page documents (`inner`/`integral`/`l2norm`/`lpnorm` each spell out the `Grid3D` cell-volume vs `PointSet` counting average). Concretely, a cold reader cannot learn from the site whether `std`/`var` divide by `N` or `N−1` (population vs sample), nor how `mean` weights the two bases — the module summary says only "intensive, fiber-preserving." For a package this careful about measures elsewhere, the silent normalization of `std`/`var` is the sharp gap.
- **resolution_hint:** Give `mean`/`std`/`var` a short shared docstring stating the base averaging and the variance normalization; `maximum`/`minimum`/`extrema` can stay brief since they inherit `Base` semantics, but note the scalar-section restriction.

---

## Finding 5 — The public "evaluate a field at a point" callable `f(x)` is documented under Interpolation's *Internal API* (contributor) section

- **type:** organization
- **severity:** minor
- **confidence:** medium
- **locations:**
  - PAGE: api / Interpolation — module docstring presents it as a headline user feature: *"plus the callable `f(x)` (and its broadcast `f.(xs)`) as the ergonomic face of a single-point gather."*
  - Same page, but its actual entry is under **"## Internal API"** (introduced as *"the in-kernel helpers — documented for contributors"*): *"`GBGPeriodicFields.Fields.AbstractFieldPhysical` — Method … `(field::AbstractFieldPhysical)(x; scheme = CatmullRom)` … This is the ergonomic face of a one-point `interpolate` gather…"*.
- **description:** The callable `field(x)` is exactly the ergonomic entry a newcomer reaches for ("how do I evaluate my field at an off-grid point?"), and the module docstring advertises it as such, yet its documentation is filed in the contributor-only Internal-API block among `_fornberg`/`_locate`/`_axis_weights`. A cold reader scanning the "Transfer operations" section for it will not find it there. (The module docstring also promises the broadcast `f.(xs)`, which the method entry does not actually document.)
- **resolution_hint:** Surface the call-overload under the public "Transfer operations" group next to `interpolate`, and add a line documenting `f.(xs)`.

---

## Finding 6 — Home lumps `integral`, `inner`, `l2norm`, `lpnorm`, `mean/std/var` as uniformly "measure-weighted … integrating the base away against its measure", but Reductions insists `integral` is the *one* extensive reduction and `inner`/`mean` are intensive

- **type:** contradiction
- **severity:** minor
- **confidence:** medium
- **locations:**
  - PAGE: Home — "Main components", Reductions bullet: *"the **measure-weighted** `integral`, `inner`, `l2norm`, `lpnorm`, and `mean`/`std`/`var` **integrating the base away against its measure**, plus the measure-independent `maximum`/`minimum`/`extrema`"*.
  - PAGE: api / Reductions — `integral`: *"It is **the one extensive reduction, the only one that scales with the base measure**; reach for `inner` or `mean` when you want an **intensive, size-independent** average instead."* and `inner`: *"It is intensive (it matches `mean`)…"*.
- **contradicts:** PAGE: api / Reductions, `integral` — "the one extensive reduction, the only one that scales with the base measure … `inner` or `mean` … intensive, size-independent" — vs PAGE: Home which characterizes `integral` and `inner`/`mean` together as "measure-weighted … integrating the base away against its measure". Axis of disagreement: **extensive (scales with the measure) vs intensive (size-independent)** — Home blurs the very distinction Reductions draws emphatically.
- **description:** The Home phrasing invites a cold reader to believe `inner`/`mean`, like `integral`, scale with the domain size ("measure-weighted"), which the reduction pages explicitly deny (only `integral` scales with the measure; `inner`/`mean` are normalized averages). It is a landing-page simplification, but on the exact axis the detailed page treats as load-bearing.
- **resolution_hint:** On Home, separate the extensive `integral` from the intensive `inner`/`l2norm`/`lpnorm`/`mean`, mirroring the Reductions distinction.

---

## Finding 7 — "assignment" carries two unrelated technical meanings across pages

- **type:** clarity
- **severity:** minor
- **confidence:** low
- **locations:**
  - PAGE: api / Convolution — `assignment_window`: *"the linear (cloud-in-cell) **mass-assignment** window … for deconvolving a gridded point density"* (assignment = depositing per-point mass onto grid nodes).
  - PAGE: api / FiberSections — `threading_cutoff`: *"Here **an assignment is a fused elementwise write into field storage** — the `_assign!` primitive behind every in-place operation"* (assignment = a broadcast write into an array).
- **description:** A newcomer meeting "assignment" on the Convolution page (mass deposition) and again on the FiberSections page (a fused array write) has to infer that the same word names two unrelated operations. Each is glossed locally, so this is mild, but it is a one-word / two-meanings collision of the kind the project's own "one concept per notation" rule targets.
- **resolution_hint:** Consider "mass-deposition window" or keep "mass-assignment" but never shorten it to bare "assignment" near the transfer material; the threading sense is fine as "a fused write".

---

## Finding 8 — The exponential base is typeset upright `\mathrm{e}` in `translation_kernel` but italic `e` in `DirectDFT`, for the same Fourier phase

- **type:** typesetting
- **severity:** minor
- **confidence:** medium
- **locations:**
  - PAGE: api / Convolution — `translation_kernel`: *"$\hat g(k) = \mathrm{e}^{-\mathrm{i}  k \cdot h} = \prod_{a=1}^{3} \bigl[ \cos(k_a h_a) - \mathrm{i} \sin(k_a h_a) \bigr]$"* — upright base.
  - PAGE: api / Interpolation — `DirectDFT`: *"$f(x_p) = \frac{1}{N} \sum_{k} \hat f(k)  e^{\mathrm{i} k\cdot (x_p - o)}$ … $(W^\top q)(k) = \sum_p q_p  e^{-\mathrm{i} k\cdot (x_p - o)}$"* — italic base.
- **description:** The notation page mandates upright `\mathrm{i}` and upright `\mathrm{d}` and the docstrings comply on those, but the exponential base `e` in the same complex-exponential expressions is upright in one operation's docstring and italic in another. It is the identical object (the shift-theorem phase / DFT kernel), so the styling should match. Minor, but it is a visible inconsistency between two docstrings a reader compares when relating convolution-by-`translation_kernel` to spectral interpolation.
- **resolution_hint:** Pick one (upright `\mathrm{e}`, matching `\mathrm{i}`/`\mathrm{d}`) and apply it everywhere; add an `e` row to the notation "Conventions" table.

---

## Finding 9 — The fiberwise-magnitude symbol `|·|` (`norm ≡ |·|`) is used across FieldAlgebra and Reductions but is missing from the notation glossary, which lists only `‖·‖`

- **type:** clarity
- **severity:** minor
- **confidence:** medium
- **locations:**
  - PAGE: notation — "Operators" table lists *"$\lVert\cdot\rVert$ | the $L^2$ norm | l2norm"* but has **no `|·|` row**, though the page's stated purpose is *"The symbols used throughout the docstrings … with the code object each one denotes."*
  - PAGE: api / FieldAlgebra — `norm!`: *"the fiberwise norm of a physical-space field (`norm` $\equiv |\cdot|$)"*, distinguishing pointwise `|·|` from the global `‖·‖`.
  - PAGE: api / Reductions — `lpnorm`: *"where $|f|$ is the pointwise fiber magnitude (the fiberwise `norm`)"*, and `l2norm` builds `‖·‖` from `|f|`.
- **description:** The site draws a real, load-bearing distinction between the pointwise fiber magnitude `|·|` (the `norm`/`norm!` operation) and the global `L²` norm `‖·‖` (`l2norm`), but the notation glossary — advertised as the single reference — binds only `‖·‖`. A cold reader consulting the glossary to disambiguate `|f|` vs `‖f‖` finds only the latter.
- **resolution_hint:** Add a `|·| → norm` row to the notation "Operators" table.

---

## Finding 10 — "the Laplacian convention" for the Nyquist frequency is invoked on the Convolution page as a known thing, but is only explained on other pages

- **type:** clarity
- **severity:** minor
- **confidence:** low
- **locations:**
  - PAGE: api / Convolution — `spectral_cutoff`: *"The squared wavenumber $|k|^2$ keeps the true value at the Nyquist frequency **(the Laplacian convention)**."*; repeated verbatim in `spectral_band` (*"with $|k|^2$ keeping the true value at the Nyquist frequency (the Laplacian convention)"*) and `squared_wavenumber_field` (*"summed with the true value kept at the Nyquist frequency (the Laplacian convention)"*).
  - The convention is only spelled out on PAGE: api / DifferentialOperators (module docstring: *"first-derivative wavenumbers are zeroed at the Nyquist frequency on even-length axes, while squared wavenumbers keep the true squared wavenumber there"*) and PAGE: api / Fields Internal API (`_axis_wavenumber_values`).
- **description:** A cold reader who lands on the Convolution page (e.g. to build a filter) meets the parenthetical "(the Laplacian convention)" three times as if it were already established, but nothing on that page says what the Nyquist convention is or why a squared wavenumber differs from a first-derivative wavenumber there. It reads complete only to someone who has already absorbed the DifferentialOperators / Fields Nyquist split. Minor, since a Fourier-literate reader can infer "keep the true k² at Nyquist," but the phrase presumes shared context.
- **resolution_hint:** Replace the bare "(the Laplacian convention)" with a half-sentence ("the true k² is kept at the Nyquist frequency, as for the Laplacian"), or `@ref`-link the DifferentialOperators explanation.

---

## Finding 11 — Home and the api overview carry a flattened, partly-empty outline; three module docstrings show a missing space where a trailing paragraph abuts the last bullet (possible lazy-continuation render, or a consolidation artifact)

- **type:** format
- **severity:** nit
- **confidence:** low
- **locations:**
  - PAGE: Home — "API reference" and PAGE: api — the tail of each page is a long list with many empty items (bare "- " lines) and a duplicated module roster (e.g. "GBGPeriodicFields.jl", then a blank "- ", "Re-exported modules", "FiberSections", "Fiber-section supertype", … repeated on both pages).
  - Missing space after a sentence-ending period where a paragraph follows the last list bullet:
    - PAGE: Home, Reductions bullet: *"…refining the mixed `inner(f, g)`)**.Pointwise** (fiberwise) products and norms live in `FieldAlgebra`…"*
    - PAGE: api / DifferentialOperators, module: *"…projects a vector field onto its divergence-free part**.The Nyquist** frequency is treated differently by symbol…"*
    - PAGE: api / GBGPeriodicFields, module: *"…the radial diagnostics `radial_spectrum` and `radial_correlation`**.`FiberSections`** is the base-agnostic foundation…"*
- **description:** The empty-bullet outline on Home/api is almost certainly a `@contents`/navigation dump captured by the reader-text consolidation rather than a real page defect, so I flag it low-confidence. The three "period-glued-to-next-sentence" cases are more interesting: they all occur exactly where a module docstring's closing paragraph follows a bulleted list, which is the classic Markdown *lazy-continuation* pitfall (the paragraph gets absorbed into the final list item) — worth verifying against the live build, since if it renders that way the trailing prose is mis-nested inside the last bullet. If instead the live pages render the paragraph separately, this is just a consolidation artifact.
- **resolution_hint:** Confirm on the built HTML; if the trailing paragraphs render inside the last `<li>`, insert a blank line before them in the module docstrings.

---

### Notes on things that checked out (not defects)

- The rfft half-spectrum Parseval weight α(k) ("1 on the k_x = 0 plane and the even-N_x Nyquist plane, 2 otherwise") is stated identically in `DirectDFT`, `weighted_inner`, and `radial_spectrum`. Consistent.
- The half dimension = `fft_dims[1]` = axis 1 (k_x, N_x) is consistent across `RealFourierLayout`, `rfft_shape`, the `convolve!` Hermitian note ("modes with k₁ ≥ 0"), and the α(k) planes.
- Measure normalizations (integral `|Ω|/N·Σ`, inner `1/N·Σ` / `1/M·Σ`, spectrum `1/N²`) all cohere; `integral = |Ω|·mean`, `l2norm = √inner`, `Σ_κ E(κ) = inner`.
- Index conventions ((∇u)_{ij}=∂_{x_j}u_i, div contracts the last index, S_{ij}=½(∂_{x_j}u_i+∂_{x_i}u_j), helmholtz (δ_ij − k_ik_j/|k|²)) are mutually consistent and reproduce div(grad)=Δ and ℙ correctly.
- `CatmullRom = LalescuSpline(1,1)` ("cubic, quadratic precision, four-point C¹") is consistent across the Interpolation module, `interpolate!`, the `CatmullRom` constant, `LalescuSpline`, and `AbstractSplineScheme`; the linear special cases (`LalescuSpline` m=0, `LagrangeSpline` n=0, `LalescuSpline(0,0)` for `assignment_window`) agree.
- The HIT example's turbulence relations are correct (the 11/9 trace-structure-function factor, Re_λ=√(15u'⁴/νε), ε=ν⟨|ω|²⟩, the dimensionally-complete K41 guide C_K ε^{2/3} κ^{-5/3}); the 320³/256³/192³ Re_λ figures are consistent between the CLI table and the Results section. Using "particles/tracers" in the example is consistent with the design (the example is explicitly the consumer, "the package has no concept of time, by design").
- `tutorial` numeric outputs check: `inner(u,u)=1.5` for u=(sin x, cos y, sin z) and `sum(spectrum)=1.5` are correct and self-consistent.
