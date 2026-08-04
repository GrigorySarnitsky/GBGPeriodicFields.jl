# Hat 03 — Spectral-methods mathematician (pseudospectral / Fourier on the periodic torus)

Reviewed: the whole rendered site (Home, api, architecture, formalization, notation, performance,
testing, tutorial, all api/* module pages, examples/hist_cpu).

Verdict up front: the **core spectral mathematics is sound**. I re-derived the transform pair and its
normalization, the constant/zero-mode rule, the Nyquist split, the derivative/Laplacian symbols, the
convolution theorem and the Hermitian reality condition (including the `translation_kernel` Nyquist
factor), the rfft half-spectrum Parseval weight `α(k)`, `var`/`cov`, the Wiener–Khinchin pair and the
`DirectDFT` type-1/type-2 adjoint with its `α(k)/N` weighting, and the spline reproduction bound
`min(2m+1, 2n)` — all check out. The example's K41 normalizations (`11/9 C₂ ε^{2/3} Δx^{2/3}`,
`C₀ ε Δt`, `C_K ε^{2/3} κ^{-5/3}`, `S₂ = (2/3)(C(0) − C(r))`, `ε = ν⟨|ω|²⟩`) are dimensionally and
numerically right. Every finding below is a **stale or contradictory statement**, not a broken formula.

---

## 1. Formalization states radial∘radial composition as unconditionally closed; the code and the API page say it is conditional

- **type:** contradiction · **severity:** major · **confidence:** high
- **locations:**
  - PAGE: formalization, §Convolution → "Kernel storage is a representation":
    "*Radial composed with radial is radial, $\sigma_1 \sigma_2$ being again a function of $|k|^2$*" —
    carried under the page's "expanded against the code and tested $\checkmark$" banner.
  - PAGE: api / Convolution, `ProductKernel`: "*two radial symbols multiply into one radial symbol
    **when both are evaluated against the same coordinates***"; `convolve!`: "*two radial ones into a
    single closure **when both are built over canonical multipliers of the same concrete type***…
    *radial operands failing that test — becomes a `ProductKernel`*".
  - PAGE: architecture, §13 decision 61: "*collapsing two kernels that evaluate their symbols against
    different wavenumbers would silently apply the second symbol at the first's $|k|^2$*".
- **contradicts:** axis = whether radial∘radial is closed unconditionally or only for matching
  canonical multiplier sets.
- **description:** The formalization is the page whose job is to be the typed, checked statement, and
  it asserts the very closure decision 61 deliberately refused to make unconditional. As written it
  would license exactly the silent coordinate substitution (a sheared/custom multiplier set) that
  decision 61 exists to prevent. Mathematically the product of two radial symbols *is* radial only
  when both are radial in the **same** `|k|²`.
- **resolution_hint:** Add the canonical-multiplier hypothesis to the formalization bullet and link
  `RadialKernel`'s condition; keep the unconditional statement only for one fixed coordinate set.

## 2. `_squared_wavenumber_broadcast` still advertises the pre-decision-42 Helmholtz projector

- **type:** contradiction · **severity:** major · **confidence:** high
- **locations:**
  - PAGE: api / Fields, Internal API, `_squared_wavenumber_broadcast`: "*Used by the Laplacian,
    inverse Laplacian, and **Helmholtz projection***" and "*($-|k|^2 \hat s$, **$\hat s_i - k_i k_j
    \hat s_j / |k|^2$**, …)*".
  - PAGE: api / DifferentialOperators, `helmholtz_projection!`: "*subtracts the longitudinal part
    $a_i (a\cdot\hat u)/|a|^2$, with $a$ the **derivative wavenumber***".
  - PAGE: architecture, §13 decision 42: "*The denominator is now $a \cdot a$ … (both the KA kernel
    and the gated `::CPU` loop **drop their three squared-wavenumber array arguments**)*".
- **contradicts:** axis = which wavenumber family the projector divides by (true `|k|²` vs the
  derivative family `a·a`).
- **description:** This is the one place where mixing the families is not cosmetic: with the true
  `|k|²` denominator against a Nyquist-zeroed numerator, `ℙ` is neither exactly idempotent nor exactly
  divergence-annihilating at mixed-Nyquist modes — the defect decision 42 fixed and that
  `formalization` now pins as unconditional. The internal docstring documents the retired formula and
  names an operator that no longer consumes the helper at all.
- **resolution_hint:** Drop "Helmholtz projection" from the user list and replace the second example
  expression with a Laplacian/inverse-Laplacian one.

## 3. Architecture §12 still says the moments are physical-only, and never mentions `cov`

- **type:** contradiction · **severity:** major · **confidence:** high
- **locations:**
  - PAGE: architecture, §12 Reductions: "*`mean`/`std`/`var` (extending `Statistics`) and
    `maximum`/`minimum`/`extrema` (extending `Base`) are the moments — **all on fields in physical
    representation and point-values***"; only "*`inner`/`l2norm`*" and "*`integral`/`mean`*" are then
    granted spectral forms.
  - PAGE: api / Reductions, module docstring: "*and the **scalar-only `std`/`var` from Parseval***";
    `var`: "*In spectral representation it is read from Parseval*".
  - PAGE: architecture, §13 decision 49 (same document): "*So `var`/`std` are now scalar-only … **physical and spectral** (the Parseval form)*".
- **contradicts:** axis = representation validity of `var`/`std` (and the existence of `cov`).
- **description:** §12 is the current-state section a reader consults for the reduction family's
  validity table, and it now disagrees with the API page, the formalization, and its own decision log.
  It also omits `cov` entirely, so the vector second moment has no home in the architecture text while
  being advertised on the Home page and documented on the API page.

## 4. The Testing page contradicts itself on the spectral `std`/`var`

- **type:** contradiction · **severity:** major · **confidence:** high
- **locations:** PAGE: testing, §7 coverage:
  - "*the spectral zero-mode `integral`/`mean` … with **`std`/`var`/`lpnorm`/`maximum` still absent in
    spectral representation***";
  - earlier on the same page, §2 file list: "*and — decision 49 — the **scalar-only `std`/`var` with
    their spectral Parseval form***".
- **contradicts:** axis = whether a spectral `std`/`var` method exists.
- **description:** Two sentences on one page assert the opposite membership of the same operations in
  the spectral surface. Since the package's whole "deliberate absence" doctrine is read off such
  lists, a reader cannot tell which absence is intentional.

## 5. `radial_kernel` is described as "the `|k|²` coordinate" — the docstring of the removed `squared_wavenumber_field`

- **type:** contradiction · **severity:** minor · **confidence:** high
- **locations:**
  - PAGE: formalization, §Convolution: "*`radial_kernel` **the $|k|^2$ coordinate consumers build
    symbols from***".
  - PAGE: testing, §7: "*and `radial_kernel` (**the $|k|^2$ radial coordinate** vs the analytic sum,
    real-valued)*".
  - PAGE: api / Convolution, `radial_kernel`: "*Build the `RadialKernel` for **an arbitrary real
    function of the squared wavenumber***"; architecture decision 60: "*the materializing
    `squared_wavenumber_field` was removed: … `radial_kernel(identity, …)` is the same object*".
- **contradicts:** axis = what `radial_kernel` returns (a fixed `|k|²` coordinate field vs a builder
  taking an arbitrary symbol σ).
- **description:** Two surfaces inherited the retired builder's description verbatim, so they present
  the general symbol constructor as a single fixed multiplier. This is the same defect class in two
  places — worth sweeping the corpus for other survivals of `squared_wavenumber_field`'s prose.

## 6. `translation_kernel` and `translation_kernel!` state opposite build costs on one page

- **type:** contradiction · **severity:** minor · **confidence:** high
- **locations:** PAGE: api / Convolution, Kernel builders:
  - `translation_kernel`: "*one kernel serves every field it is applied to (**its own cost is a single
    pass over the coefficients**)*";
  - `translation_kernel!`: "*The cost is **three $O(N)$ axis passes, not a field***";
  - `SeparableKernel`: "*the kernel **never occupies a field's worth of memory***".
- **contradicts:** axis = whether building the displacement kernel touches `O(N³)` coefficients.
- **description:** The allocating builder's sentence survives from before decision 50 made the
  displacement kernel separable; it tells the reader the build is a full coefficient pass, which is
  precisely the cost the class was introduced to remove, and it contradicts its own in-place sibling
  two entries later.

## 7. The formalization limits `inv` to two classes; the API defines it for four

- **type:** contradiction · **severity:** minor · **confidence:** high
- **locations:**
  - PAGE: formalization, §Convolution: "*The reciprocal `inv` … **defined on a class where that is
    again closed — separable (per axis) and radial (in the symbol)***".
  - PAGE: api / Convolution, module docstring: "*the coefficientwise reciprocal of a kernel is the
    kernel that deconvolves by it (`inv`, **defined for all four classes**)*", with documented
    `inv(::ProductKernel)` and `inv(::StoredKernel)` methods.
- **contradicts:** axis = the domain of `inv` over the kernel storage classes.
- **description:** The formalization's closure argument is fine as mathematics but is now an
  understatement of the shipped surface (`ProductKernel` inverts factorwise; `StoredKernel` inverts
  coefficientwise with a zero check). A reader auditing "the method set is the spec" against the
  formal page gets the wrong denominator.

## 8. The public transform docstrings never state where the `1/N` lives

- **type:** clarity · **severity:** minor · **confidence:** high
- **locations:**
  - PAGE: api / Fields, `to_spectral` / `to_physical` / `to_spectral!` / `to_physical!` /
    `FieldTransformPlans`: e.g. "*Transform a field from physical space to spectral space, returning a
    newly allocated spectral-space field*" — no normalization statement anywhere in the four.
  - The convention appears only in PAGE: architecture §4 ("*Forward transforms are unnormalized;
    inverse transforms carry the normalization*"), PAGE: formalization, and the **internal**
    `_spectral_constant_scale` ("*under the unnormalized-forward FFT convention*").
- **description:** Every user-facing formula on the Convolution, Reductions and Interpolation pages
  (`αN⁻²` Parseval sums, `f̂(0)/N`, `C(r) = 𝓕⁻¹(|f̂|²)/N`, the `cN δ_{k,0}` constant rule, the
  `1/N` in `DirectDFT`) is only checkable once the reader knows the forward transform is
  unnormalized. At the REPL — where the docstrings must read complete and cross-links are dead — that
  fact is unavailable on the very functions that define `𝓕`/`𝓕⁻¹`.
- **resolution_hint:** One sentence on `to_spectral` (home) plus a pointer from `to_physical`.

## 9. `translation_kernel`'s displayed formula uses one symbol `k_a` for two different wavenumber families

- **type:** math · **severity:** minor · **confidence:** high
- **locations:**
  - PAGE: api / Convolution, `translation_kernel`: "*$\hat g(k) = e^{-\mathrm{i} k \cdot h} =
    \prod_{a=1}^{3} [\cos(k_a h_a) - \mathrm{i}\sin(k_a h_a)]$*", followed by "*the even cosine takes
    the true wavenumber $k_a$ and the odd sine the **Nyquist-zeroed derivative wavenumber***".
  - PAGE: formalization, §Convolution, which writes the same object with two symbols:
    "*$\hat g_h(k) = \prod_a [\cos(\kappa_a h_a) - \mathrm{i}\sin(\tilde\kappa_a h_a)]$*".
- **description:** As displayed, the equation asserts the implemented multiplier equals the pure phase
  `e^{-ik·h}` everywhere, which is false at an even axis's Nyquist frequency — the one place the whole
  decision-28 argument turns on. The prose repairs it in the next sentence by silently redefining
  `k_a` mid-formula. The formalization's `κ_a` / `κ̃_a` split is the correct rendering.

## 10. `NUFFT`'s `oversampling ≥ 2` constraint is justified by an argument that only excludes σ = 1

- **type:** method · **severity:** minor · **confidence:** medium
- **locations:** PAGE: api / Interpolation, `NUFFT`: "*`oversampling` — the linear oversampling factor
  of the work grid (default `2`); **must be at least 2** (a value of 1 leaves no spectral guard band,
  so the gridding breaks down)*".
- **description:** The stated reason rules out σ = 1, not σ ∈ (1, 2). Low-upsampling NUFFTs
  (σ ≈ 1.25 with a wider ES window) are standard practice in the same Barnett–Magland–af Klinteberg
  line the docstring cites, and they exist precisely to save the 8× work-grid memory the admonition
  below it flags as the GPU concern. Either the bound is an implementation limit (say so) or the
  justification is the wrong one.

## 11. `radial_spectrum`'s shell width on an anisotropic box invites empty/comb-like shells, and only the corner caveat is documented

- **type:** method · **severity:** minor · **confidence:** medium
- **locations:** PAGE: api / Reductions, `radial_spectrum`: "*isotropic $|k|$-shells one fundamental
  wavenumber wide (the box's smallest nonzero wavenumber, $\Delta k = 2\pi / \max_a L_a$)*"; the only
  documented caveat is "*On a non-cubic box the shells beyond the inscribed sphere … are incompletely
  sampled*".
- **description:** Taking Δk from the **largest** `L_a` makes the shell width finer than the mode
  spacing `2π/L_a` along every shorter axis, so on a strongly anisotropic box a systematic fraction of
  shells is empty and the profile combs. The total is still exactly `inner`, so nothing is wrong — but
  the shell-resolved curve a consumer plots is affected by a second anisotropy artifact the docstring
  does not name, alongside the one it does. A related sharp edge: `round(|k|/Δk)` is decided by
  ties-to-even for modes landing exactly on a half-integer, which anisotropic boxes hit exactly.
- **resolution_hint:** One clause beside the inscribed-sphere caveat.

## 12. Architecture §12's radial/`weighted_inner` paragraph omits the two-field forms' spectral-only scoping consistently with the API — checked, no defect

*(Recorded as verified rather than as a finding, since the panel asked for cross-checks: the Parseval
weight `α(k)`, the `Σ P = ⟨f,f⟩` / `C(0) = ⟨f,f⟩` refinements, the co-spectrum symmetry, the
`⟨f, w g⟩ = ⟨f, w f⟩` idempotence clause, `var = ⟨f,f⟩ − ⟨f⟩²`, `cov`'s Bessel scaling, the
`DirectDFT` adjoint with its `α(k)/N` weight, `assignment_window`'s `∏ sinc²` and its non-vanishing on
the resolved band, and the `min(2m+1, 2n)` / `2n+1` reproduction degrees all expand correctly and agree
across pages.)*
