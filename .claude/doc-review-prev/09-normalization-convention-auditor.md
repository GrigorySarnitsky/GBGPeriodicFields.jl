# Normalization & Convention Auditor — findings

Hat: `normalization-convention-auditor`. Scope: mechanical cross-check of every normalization
factor, sign, and indexing convention in the rendered site (transform 1/N placement, DC-mode
scaling, spectral-multiplier signs, wavenumber-grid/FFT-ordering convention, rfft half-spectrum
Parseval weight, convolution normalization, interpolation/anterpolation adjoint measure factor).

## Method note (for the record, not a finding)

I mechanically re-derived and cross-checked the following load-bearing formulas across every
page that restates them, and found them **fully consistent** everywhere they recur (quoted
against each other, not just read once):

- Forward-unnormalized / inverse-normalized transform convention, and the constant-add zero-mode
  scale `_spectral_constant_scale = prod(grid_size)` (Architecture §2, §4; Formalization
  "Representations and transforms"; `FieldAlgebra.add!`/`subtract!` docstrings;
  `_spectral_constant_scale` docstring) — identical everywhere.
- The DC-mode `integral`/`mean` relations `mean(f) = f̂(0)/N`, `integral(f) = (|Ω|/N) f̂(0)`
  (Architecture §12, decision log, Formalization, `Reductions.integral`/`inner` docstrings,
  `examples/hist_cpu` Parseval printf) — identical everywhere, including the trivial but easy-to-
  drift consistency check `Σ_x f(x) = f̂(0)`.
- The rfft half-spectrum Parseval weight α(k) (1 on the folded-axis zero/even-Nyquist planes, 2
  elsewhere, folded axis = `fft_dims[1]`) — identical across the spectral `inner`, `weighted_inner`,
  `radial_spectrum`, `DirectDFT`'s type-2 sum, and the decision-41 folded-axis generalization note.
  I independently re-derived `weighted_inner`'s spectral formula from its stated physical form
  ⟨f, w⋆g⟩ and confirmed it algebraically collapses to the documented Σ_k α(k)w(k)Σ_c Re(...) form,
  and confirmed it reduces to the plain `inner` formula at w≡1.
- `radial_correlation`'s `C(r) = (1/N)·𝓕⁻¹(|f̂|²)(r)` — re-derived from the discrete
  Wiener–Khinchin identity from scratch (given the package's own forward-unnormalized/inverse-
  normalized convention) and confirmed it is exactly the formula printed on every one of its four
  restatements (Architecture §12, decision-22 log entry, Formalization, `Reductions.radial_correlation`
  docstring), including the `C(0) = (1/N²)Σ|f̂|²` Parseval cross-check.
- The convolution normalization (`convolve`'s coefficientwise product carries no stray 1/N; the
  continuum integral is `|Ω|/N` times the discrete circular sum) — consistent between the
  `Convolution` module docstring, `convolve!`'s own docstring, and the decision log.
- The interpolation/anterpolation measure-adjoint factor `ι* = (N/M) W^⊤` and the raw identity
  `M·⟨Wf,q⟩_pts = N·⟨f,W^⊤q⟩_grid` — identical (never inverted to `M/N`) across the Architecture
  §10 body, the decision log (three separate entries), the Formalization page's from-scratch
  derivation (which explicitly flags and fixes the naive-adjoint slip `⟨Wf,q⟩=⟨f,W^⊤q⟩`), the
  `Interpolation` module docstring, and `DirectDFT`'s docstring. I independently re-derived the
  `DirectDFT` type-1/type-2 adjoint pair by full expansion (expanding the `Re(·)` and the α(k)
  weight) and confirmed the stated type-1 sum is exactly the correct adjoint of the type-2
  reconstruction under this measure-weighted pairing — a case where a naive "literal transpose"
  intuition gives the wrong sign/scale, but the documented formula is the one that is actually
  correct.
- All differential-operator spectral signs (`∇→ik`, `Δ→−|k|²`, `Δ⁻¹→−1/|k|²` off the zero mode,
  `curl→ik×`, `ℙ = id − â âᵀ` with the decision-42 exact `a·a` denominator) and the Nyquist
  split (derivative wavenumbers zeroed, squared wavenumbers true) — consistent across
  Architecture §4, Formalization, and every `DifferentialOperators` docstring.
- `translation_kernel`'s Hermitian-safe Nyquist construction (even part from the true wavenumber,
  odd part from the derivative wavenumber) — consistent across all four restatements, and I
  verified by direct computation that the resulting Nyquist factor `cos(πh_a/Δx_a)` is correct.
- K41/turbulence formulas in the `examples/hist_cpu` page (`S⁽ᴱ⁾ = ⅔(C(0)−C(r))`, the 11/9
  longitudinal-to-full-trace structure-function ratio, `ε = ν⟨|ω|²⟩`, `λ = u'√(15ν/ε)`,
  `Re_λ = √(15u'⁴/(νε))`, `u' = √(2K/3)`) — all independently re-derived and confirmed correct,
  standard identities, self-consistently applied.

Given this document's own decision log records an unusually deep formula-re-derivation pass
already having been carried out (§13's "coverage-axes audit" and "formula-sweep" entries), the
near-total absence of exploitable normalization contradictions is expected. I found exactly one
genuine, quotable inconsistency, reported below.

---

## Finding 1 — `kmaxη` drops the `2π/L` domain-length factor that its sibling wavenumber
## calculations in the same script carry explicitly

- **Type:** normalization
- **Severity:** minor
- **Confidence:** medium

**Locations:**

- PAGE: `examples / hist_cpu`, § "Setup" driver code:
  > `dealias = spectral_cutoff(uspec0, m, (2 / 3) * (p.N / 2) * (2π / p.L))`
  > `band    = spectral_band(uspec0, m, 0.5 * (2π / p.L), (p.k_force + 0.5) * (2π / p.L))`
- PAGE: `examples / hist_cpu`, § "The driver", final-diagnostics code block:
  > `kmaxη = (2 / 3) * (p.N / 2) * η`
- PAGE: `examples / hist_cpu`, § "Parameters" (`Params` struct):
  > `L::Float64      = 2π          # box size (so wavenumbers are integers)`

**Axis of disagreement:** both `dealias`/`band` on one side and `kmaxη` on the other compute the
same kind of quantity — a physical wavenumber magnitude built from a mode count `p.N/2` (the
Nyquist mode index) or a shell index (`p.k_force`) — but `dealias` and `band` explicitly multiply
by the domain-length scaling factor `(2π / p.L)` (converting a bare mode-index count into a true
angular wavenumber), while the `kmaxη` diagnostic, computed from the identical mode count
`p.N / 2`, omits that factor entirely. `κ_max·η` is supposed to be the dimensionless product of a
true wavenumber and the Kolmogorov length `η` (itself a genuine physical length, `η =
(ν³/ε)^(1/4)`); as written, `kmaxη` is instead `(2/3)·(N/2)·η`, i.e. `(mode count)·(length)`, which
is only equal to the intended `(2/3)·κ_Nyquist·η` because `p.L` is fixed at its default `2π`
everywhere in this script (making `2π/p.L = 1`), never overridden by any of the shipped `smoke`/
`fast`/`huge`/`mega` configurations.

**Description:** This is numerically harmless under every configuration the page actually ships
(since `L` is never changed away from its documented default of `2π`, and the struct's own comment
discloses the assumption — "so wavenumbers are integers"), so the printed `κ_max·η ≈ 1.13` /
`≈ 1.3` diagnostics for `--huge`/`--mega` are not wrong. But the formula as literally written is not
general — it silently reintroduces a domain-length error if a reader adapts the demo with a
different box size `p.L`, which is exactly the class of drift this package's own house style
elsewhere insists on writing out explicitly (`dealias`/`band` a few lines earlier, and the general
architecture note that "an anisotropic domain… exercises the 2π/L wavenumber scaling… a dropped
length factor is visible"). Since `dealias` and `band` in the very same script carry the factor
defensively while `kmaxη` does not, this reads as an inconsistency in how the same physical
quantity (a wavenumber-index-to-physical-wavenumber conversion) is computed within one page,
rather than a deliberate, uniformly-applied convention.

**resolution_hint (advisory):** either multiply `kmaxη` by `(2π / p.L)` to match the `dealias`/
`band` pattern, or add a short inline comment at the `kmaxη` line noting it relies on the same
"`L = 2π` ⇒ wavenumbers are integers" convention documented on the `Params` struct, so the
omission reads as intentional rather than as a dropped factor.

---

## Summary

Exactly one finding, minor severity, medium confidence — a dimensional-completeness inconsistency
confined to the worked example page (`examples/hist_cpu`), not the core package API or its
docstrings. Every load-bearing normalization factor in the core API surface (`Fields`,
`FieldAlgebra`, `DifferentialOperators`, `Convolution`, `Interpolation`, `Reductions`) that I could
cross-check against a restatement on another page was found consistent, correctly signed, and
independently re-derivable from the stated conventions.
