# Normalization & Convention Auditor — findings

**Scope of this pass.** I mechanically cross-checked every normalization-bearing formula that
appears more than once across the rendered site: the FFT forward/inverse normalization and the
zero-mode constant-add scaling (`prod(grid_size)`/`N δ_{k,0}`); the derivative/Laplacian/Helmholtz
multipliers (`ik`, `-|k|²`, `id - aaᵀ/(a·a)`) and their Nyquist split; the rfft half-spectrum
Parseval weight α(k) (1 on self-conjugate planes, 2 elsewhere) everywhere it is used (`inner`,
`weighted_inner`, `radial_spectrum`, `radial_correlation`, `DirectDFT`); the `N/M` interpolation
adjoint-measure factor; the convolution theorem's cell-volume bridge (`|Ω|/N` between the
continuum integral and the discrete circular sum); the `assignment_window` sinc² window; the
`translation_kernel` Nyquist real-attenuation factor `cos(π h_a/Δx_a)`; and the `2π/L` wavenumber
scaling for anisotropic boxes — across Home, api, architecture, formalization, notation,
performance, testing, tutorial, every api/* module page, and the HIST_CPU example.

**Overall result.** This document is unusually rigorous and internally consistent on exactly the
axis this hat audits. Every formula I could cross-reference against a second statement of the same
quantity agreed bit-for-bit in its normalization constant, sign, and index convention — a direct
consequence of the extensive "Formalization" page, whose stated purpose is precisely to force every
normalization into the open and check it by expansion. I found no blocker- or major-severity
normalization contradictions. The items below are the only two things worth recording, both minor
or nit, both low-to-medium confidence.

---

### Finding 1 — DirectDFT's type-2 formula is stated two different levels of explicitness on two pages

- **Type:** normalization
- **Severity:** minor
- **Confidence:** low
- **Locations:**
  - *architecture, §10:* "the literal inverse/forward DFT `f(x_p)=(1/N)Σ_k f̂(k) e^{ik·(x_p-o)}`"
    (no mention of the stored half-spectrum, the Parseval weight α(k), or the real part).
  - *api / Interpolation, `DirectDFT`:* "`f(x_p) = (1/N) Σ_k f̂(k) e^{ik·(x_p-o)} = (1/N) Σ_{stored k} α(k)·Re(f̂(k) e^{ik·(x_p-o)})`"
    — the same identity, but now explicitly showing the equivalent form over the *stored* rfft
    half-spectrum with the α(k) weight and the real part.
- **Contradicts:** not a true contradiction — the two are mathematically equal — but a reader who
  only sees the Architecture page's bare `Σ_k f̂(k) e^{ik·x}` (with no domain given for `k` and no
  α(k)/Re) and who already knows `f̂` is stored as a half-spectrum could misread it as the naive sum
  restricted to the stored half with no doubling weight, which would be wrong by roughly a factor of
  two per off-axis mode.
- **Description:** Architecture is explicitly the informal/overview document and Formalization/the
  API page are explicitly the precise ones, so this is very likely by design rather than drift.
  Flagging only because it is the one place in the site where the same named formula is given in two
  visibly different levels of completeness without a forward pointer from the terse form to the
  explicit one.
- **Resolution hint:** optional — a one-clause pointer from the Architecture sentence to the
  Interpolation docstring's explicit stored-half-spectrum form would close the gap for a reader who
  stops at Architecture.

### Finding 2 — Δ is heavily overloaded (Laplacian, grid spacing, shell width, timestep) with only one binding stated on the Notation page

- **Type:** normalization
- **Severity:** nit
- **Confidence:** low
- **Locations:**
  - *notation, "Base and fiber" table:* "`Δ` is reserved for the Laplacian, and `Δx_a` for the grid
    spacing" — only these two uses of the glyph `Δ` are explicitly bound.
  - *api / Reductions, `radial_spectrum`:* "...and shell width `Δk` (the box fundamental)..." — a
    third use, `Δk`, introduced without an explicit binding clause on that page or a back-reference
    to the Notation page's `Δ` convention.
  - *examples/hist_cpu:* "`Δt`" (timestep) used throughout, which is fine since the example
    explicitly documents its own local notation, but adds a fourth reading of the same glyph.
- **Contradicts:** none of the four uses are mathematically in tension with each other (they are
  clearly disambiguated by the trailing subscript/letter in every case), so this is not a
  correctness defect.
- **Description:** The house rule in `CLAUDE.md` ("One notation per concept... grep the doc for any
  existing symbol denoting the same thing") is aimed at exactly this kind of glyph reuse. `Δx_a`,
  `Δk`, and `Δt` are all standard, unambiguous idiom and cause no confusion in practice, but the
  Notation page's table only explicitly names `Δ` (Laplacian) and `Δx_a` (spacing) — `Δk` is
  introduced cold on the Reductions page with no cross-reference to the convention, which is a very
  small self-containedness gap rather than a normalization error.
- **Resolution hint:** optional — add `Δk` (and, if wanted, `Δt` as a locally-scoped exemption like
  the example's bold `k`) to the Notation page's table for completeness.

---

**Everything else checked and found consistent** (for the record, since a normalization audit's
main value is negative evidence): the `N δ_{k,0}` constant-add scaling (Architecture, Formalization,
`add!` docstring, `_spectral_constant_scale` all agree); the Nyquist split between derivative and
squared-wavenumber families (stated identically in Architecture §4, Formalization, the Notation
page, `FieldSpectralMultipliers`, and every operator docstring that touches it); the Helmholtz
projector `id − aaᵀ/(a·a)` (Architecture, Formalization, `helmholtz_projection!` docstring, all
bit-identical); the α(k) half-spectrum weight (1 on self-conjugate planes / 2 elsewhere — stated
identically in Notation, Formalization, `inner`, `weighted_inner`, `radial_spectrum`,
`radial_correlation`, and `DirectDFT`); the `N/M` interpolation adjoint factor (Architecture §10,
Formalization, and the Interpolation module page all derive and state the same
`M⟨Wf,q⟩_pts = N⟨f,Wᵀq⟩_grid` identity and the same `(N/M)Wᵀ` measure-adjoint); the convolution
`|Ω|/N` cell-volume bridge between the continuum integral and the discrete circular sum; the
`assignment_window` sinc² formula; the `translation_kernel` Nyquist attenuation `cos(πh_a/Δx_a)`;
the `var`/`cov` Bessel-correction factor `B/(B−1)`; and the `2π/L` wavenumber scaling for
anisotropic boxes throughout the differential-operator and reduction docstrings.
