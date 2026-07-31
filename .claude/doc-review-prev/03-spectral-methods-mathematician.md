# Review — Spectral-methods / Fourier-on-the-torus mathematician

Audit of the rendered GBGPeriodicFields site + design docs (`manuscript-full.md`).
Scope: transform normalization, spectral differential operators (sign / Nyquist),
the convolution theorem, Parseval / radial spectra, the interpolation/anterpolation
adjoint pair, DirectDFT vs NUFFT. Primary lens: internal consistency across pages.

**General note:** the core spectral mathematics is, overwhelmingly, correct and
mutually consistent. The forward-unnormalized / inverse-1/N convention, the
`ik` / `-|k|²` multipliers and their signs, the deliberate Nyquist split
(derivative wavenumbers zeroed vs squared wavenumbers keeping true k²), the
convolution theorem `F(f⋆g)=f̂·ĝ`, the rfft half-spectrum Parseval weighting
(`α=1` on self-conjugate planes, `2` else), `sum(radial_spectrum)==inner==C(0)`,
the Helmholtz/Leray multiplier `I − k̂k̂ᵀ`, and the DirectDFT/NUFFT formulas all
check out and agree between the Architecture, Formalization, and API-docstring
surfaces. The findings below are the discrepancies I did find.

---

## Finding 1 — `E(κ)` denotes two different quantities across pages (factor of 2)

- **type:** normalization
- **severity:** major
- **confidence:** high

The symbol `E(κ)` (the energy spectrum) is bound to **two quantities differing by
a factor of 2** across user-facing surfaces: in some places it *is* the package's
`radial_spectrum` (so `Σ E = ⟨f,f⟩ = ⟨|u|²⟩`), in others it is *half* of it (the
physics kinetic-energy spectrum, `Σ E = ½⟨|u|²⟩ = k`).

**`E(κ) = radial_spectrum` (no ½):**
- PAGE: api / Reductions, `radial_spectrum` docstring: "The radial (shell-binned)
  spectrum resolves a field's L² energy over wavenumber-magnitude shells
  (`radial_spectrum` $\equiv E(\kappa)$)." and "$\sum_\kappa E(\kappa) = \langle f, f\rangle$".
- PAGE: tutorial, "Fiberwise algebra and L²/measure reductions":
  `round(sum(spectrum); digits = 4)   # Σ E(k) = inner(u, u)` → `1.5`.
- PAGE: testing (coverage paragraph): "the exact refinement
  $\sum_\kappa E(\kappa) = \langle f, f\rangle$".

**`E(κ) = ½·radial_spectrum` (with ½):**
- PAGE: architecture, decision 21: "The consumer's energy spectrum over the shell
  wavenumber $\kappa$ ($= |k|$) is $E(\kappa) = \tfrac{1}{2} \mathrm{spectrum}$".
- PAGE: architecture, decision 22: "the energy spectrum
  $E(k) = \tfrac{1}{2} \mathrm{radial\_spectrum}$".
- PAGE: examples / hist_cpu, Diagnostics:
  "$\sum_\kappa E(\kappa) = \tfrac{1}{2}\langle\lvert u\rvert^{2}\rangle = k$, the
  turbulent kinetic energy" and "$E(\kappa) = \tfrac{1}{2} \times$ the shell-resolved
  Parseval inner".

The sharpest contradiction is between two runnable user-facing surfaces:
tutorial `# Σ E(k) = inner(u, u)` (= `⟨|u|²⟩`) versus HIST
`Σ E(k) = ½⟨|u|²⟩ = k` — the *same* symbol `Σ E(k)` equal to `⟨|u|²⟩` on one
page and to `½⟨|u|²⟩` on another. Equivalently the Reductions docstring binds
`radial_spectrum ≡ E(κ)` while the Architecture explicitly binds
`E(κ) = ½·radial_spectrum` — directly opposite bindings of `E(κ)`. This is exactly
the factor-of-2 that silently mis-normalizes a K41 spectrum plot, and for a
turbulence audience `E(κ)` conventionally means the ½-version (`∫E dκ = TKE`).

**contradicts:** PAGE: api / Reductions ("`radial_spectrum` $\equiv E(\kappa)$",
"$\sum_\kappa E(\kappa)=\langle f,f\rangle$") ⇄ PAGE: architecture decision 21/22
("$E(\kappa)=\tfrac12\,\mathrm{spectrum}$") and PAGE: examples / hist_cpu
("$\sum_\kappa E(\kappa)=\tfrac12\langle|u|^2\rangle=k$"); axis = whether `E(κ)`
already carries the physical ½ (a factor of 2).

**resolution_hint (advisory):** pick one binding and use it everywhere. Cleanest:
reserve `E(κ)` for the physical KE spectrum (`= ½·radial_spectrum`, the textbook
convention the Architecture and HIST already use) and rename the docstring/tutorial
binding to "spectrum" / `radial_spectrum` (not `E(κ)`), so `Σ radial_spectrum =
inner` and `E(κ) = ½·radial_spectrum`. Add `E(κ)` to the Notation page to anchor it
(it is currently undefined there, which is the root cause of the drift).

---

## Finding 2 — Architecture §2 method-count walkthrough stops at 202 but claims 206

- **type:** contradiction
- **severity:** minor
- **confidence:** high

PAGE: architecture, §2 "Representation validity lives in the method set":
"The **206**-method public surface of `FieldAlgebra` is the machine-checkable
encoding of the validity table above. … M2 (98 methods: …) and then M3 (…),
bringing the total to **198**; the later trace `tr`/`tr!` addition brings it to
**202**, all parity-checked at runtime …".

The enumerated build-up ends at 202 and never reaches the 206 asserted in the same
sentence — it omits the decision-27 additions (`combine!` +2, `det`/`det!` +2) that
actually take 202 → 206. §6 and decision 27 give the reconciled current figure:
PAGE: architecture §6 "The full M2+M3 baseline is **206** public methods (e.g. …
`combine!` 2, `tr` 2, `det`/`det!` 1 each)"; decision 27 "The public method set
grows to **206** field methods (`combine!` adds 2, `det`/`det!` 1 each)". So the §2
walkthrough is internally inconsistent (headline 206 vs enumerated 202) and stale
relative to §6 / decision 27.

**contradicts:** PAGE: architecture §2 ("… brings it to 202") ⇄ PAGE: architecture
§6 / decision 27 ("206 public methods … `combine!` 2 … `det`/`det!`"); axis = the
FieldAlgebra public-method count.

**resolution_hint:** extend the §2 walkthrough "… brings it to 202; and the
`combine!` + `det`/`det!` additions (decision 27) bring it to 206", or drop the
running arithmetic and state 206.

---

## Finding 3 — RDF FFT-route complexity `O(N + M log M)` contradicts the FFT-dominated recipe and the O(N log N + M) used elsewhere

- **type:** performance
- **severity:** minor
- **confidence:** medium

PAGE: architecture, decision 22 (Points → RDF): "The pair correlation $g(r)$ of $M$
points is computable in **$O(N + M \log M)$** (vs $O(M^2)$ direct counting) via the
FFT structure-factor estimator — exactly the implemented recipe: anterpolate … FFT …
deconvolve … then `radial_correlation` …".

The recipe it describes is FFT-dominated (a forward FFT + an inverse FFT over the
grid) with a plain `O(M)` scatter and **no sort of the points**, so its cost is
`O(N log N + M)`, not `O(N + M log M)`. The stated expression puts the log on the
wrong term: it drops the `log N` on the FFT (writing bare `N`) and adds a spurious
`log M` (a point sort that the recipe does not perform). This also disagrees with
the complexity used for the same FFT-based transfer class elsewhere:
PAGE: performance §2 "`NUFFT` is its **$O(N\log N + M)$** fast form" and
PAGE: api / Interpolation, NUFFT "the **$O(N\log N + M)$** windowed-gridding …".

**contradicts:** PAGE: architecture decision 22 ("$O(N + M \log M)$") ⇄
PAGE: performance §2 / PAGE: api / Interpolation ("$O(N\log N + M)$"); axis = which
term carries the logarithm in an FFT-based algorithm.

**resolution_hint:** change decision 22 to `O(N log N + M)` (`N` = total grid
points).

---

## Finding 4 — `translation_kernel`: docstring displays the plain phase (rejected at Nyquist); Formalization/decision-28 display the split cos(κ)/sin(κ̃) kernel

- **type:** math
- **severity:** minor
- **confidence:** medium

The **implemented** translation multiplier is the one with the Nyquist
derivative-wavenumber split, per PAGE: formalization, Convolution:
"$\hat g_h(k) = \prod_{a=1}^{3}\bigl[\cos(\kappa_a h_a) - \mathrm i \sin(\tilde\kappa_a h_a)\bigr]$"
(with `κ̃` the *derivative* wavenumber, zeroed at Nyquist) — and PAGE: architecture,
decision 28: "the even (cosine) part takes the true wavenumber, the odd (sine) part
takes the derivative wavenumber."

But the user-facing docstring displays the **un-split** true phase as the kernel's
transfer function: PAGE: api / Convolution, `translation_kernel`:
"$\hat g(k) = \mathrm{e}^{-\mathrm{i} k \cdot h} = \prod_{a=1}^{3}\bigl[\cos(k_a h_a) - \mathrm{i} \sin(k_a h_a)\bigr]$"
— the same `k_a` inside both `cos` and `sin`. That is exactly the "true phase"
candidate decision 28 explicitly rejects ("complex at Nyquist for a fractional
displacement, so it returns coefficients that are those of no real field"); the
docstring repairs it only afterward in prose ("At the Nyquist frequency the phase
becomes a real attenuation"). So the two pages display *different* formulas for the
same implemented kernel, and the docstring's displayed equality is, taken literally,
the non-Hermitian form.

**contradicts:** PAGE: api / Convolution `translation_kernel`
("$\prod[\cos(k_a h_a) - \mathrm i\sin(k_a h_a)]$") ⇄ PAGE: formalization Convolution /
PAGE: architecture decision 28 ("$\prod[\cos(\kappa_a h_a) - \mathrm i\sin(\tilde\kappa_a h_a)]$");
axis = whether the sine factor uses the true or the Nyquist-zeroed derivative wavenumber.

**resolution_hint:** in the docstring, keep `e^{-ik·h}` as the physical-meaning
lead but display the *implemented* split product (as the Formalization does), so the
shown transfer function is the one actually applied.

---

## Finding 5 — HIST calls `S⁽ᴱ⁾ = ⅓⟨|δu|²⟩` the "trace" structure function, but the trace is `⟨|δu|²⟩` (3× larger)

- **type:** math
- **severity:** minor
- **confidence:** medium

PAGE: examples / hist_cpu defines and repeatedly labels the second-order structure
function as the **trace**:
- Results: "the **trace** second-order velocity structure functions … 
  $S^{(E)}(\Delta x) = \tfrac{1}{3}\big\langle \lvert u(x+\Delta x) - u(x)\rvert^{2}\big\rangle
  = \tfrac{2}{3}\big(C(0) - C(r)\big)$".
- Statistics / code comments: "the **trace** structure function
  $S^{(E)}(r) = \tfrac{2}{3} (C(0) - C(r))$" and
  `S2_E = (2 / 3) .* (C[1] .- C)  # Eulerian trace structure function`.

The quantity actually computed is `⅓⟨|δu|²⟩ = ⅔(C(0)−C(r))` — the **per-component
(average single-component)** SF. The *trace* of the SF tensor `D_ij = ⟨δu_i δu_j⟩`
is `D_ii = ⟨|δu|²⟩ = 2(C(0)−C(r))`, i.e. three times larger. So `⅓⟨|δu|²⟩` is
one-third of the trace, and "trace" is a misnomer. (The computation itself and the
K41 normalization `11/9·C₂·ε^{2/3}Δx^{2/3}` are mutually consistent with the ⅓
definition — only the *name* is wrong.)

**contradicts:** self — the shown definition
`S^{(E)} = ⅓⟨|δu|²⟩` versus the word "trace" (which denotes `⟨|δu|²⟩`) in the same
passages; axis = trace `D_ii` vs its per-component third.

**resolution_hint:** call it the "per-component" (or "one-third-trace" /
"isotropic single-component") second-order structure function, not the "trace"; or
keep "trace" and drop the ⅓ (then `S = 2(C(0)−C(r))` with K41 `11/3·C₂·…`).

---

## Finding 6 — NUFFT default tolerance: constructor `tol = 1e-10` vs decision 23's "~10⁻¹² at the default"

- **type:** performance
- **severity:** minor
- **confidence:** low

PAGE: api / Interpolation, `NUFFT` constructor: "`NUFFT(reference…; tol = 1e-10, …)`
… `tol` — the target accuracy". PAGE: architecture, decision 23: "Verified against
`DirectDFT` (and `to_physical`) **to the requested tolerance $\varepsilon$
($\sim 10^{-12}$ at the default)**".

The default *requested* `tol` is `1e-10`, but decision 23 characterizes the default
`ε` as `~10⁻¹²`. This is likely achieved-vs-requested (the ES-window rule usually
over-delivers), which would be fine — but the phrasing "the requested tolerance ε
(~10⁻¹² at the default)" reads as if the default requested ε were `10⁻¹²`, which
mismatches the `1e-10` constructor default. Flagging as a low-confidence possible
imprecision.

**contradicts:** PAGE: api / Interpolation ("tol = 1e-10") ⇄ PAGE: architecture
decision 23 ("requested tolerance ε (~10⁻¹² at the default)"); axis = the default
NUFFT tolerance value.

**resolution_hint:** if `~10⁻¹²` is the *achieved* error at the `1e-10` default, say
"achieved ~10⁻¹² at the default tol = 10⁻¹⁰"; otherwise reconcile the numbers.

---

## Finding 7 — `N` overloaded (total grid points vs points-per-axis)

- **type:** normalization
- **severity:** nit
- **confidence:** low

`N` denotes the **total grid-point count** in the L²/transfer mathematics
(PAGE: architecture §10, PAGE: formalization "$N = N_x N_y N_z$", PAGE: notation
"$N$ | the grid-point count $\prod_i N_i$", decision 23 "$N = N_x N_y N_z$ the
grid-point count") but the **per-axis** point count in the allocation/binning
discussions (PAGE: architecture decisions 24/25 "$N$ the points per axis";
PAGE: performance §4(g) "$\approx \sqrt{3} N/2$ … with $N$ the per-axis size here —
not the total $N$ of §2"). The doc **explicitly re-glosses** `N` at each per-axis
use, so this is self-disambiguated and at most a nit against the "one concept, one
notation" rule — noted only because it interacts with Finding 3 (in `O(N + M log M)`
the intended meaning of `N` is itself unclear).

**resolution_hint:** none needed for correctness; if desired, use `n` (or `N₁`) for
the per-axis count in decisions 24/25 and performance §4(g).

---

### Checked and found consistent (no finding)
- Forward-unnormalized / inverse-`1/N` convention: Formalization §Representations,
  Architecture §4, Fields transform docstrings — all agree.
- Constant-add touches only the DC mode scaled by `N = prod(grid_size)`:
  Architecture §2, invariant 4, `add!` docstring, Formalization — agree.
- Spectral multipliers `ik`, `ik·`, `ik×`, `−|k|²`, `−1/|k|²` (0 at k=0),
  `I−k̂k̂ᵀ`: DifferentialOperators docstrings ⇄ Formalization ⇄ Architecture §4 —
  signs and forms agree; `ΔΔ⁻¹=1`, `P²=P`, `P` self-adjoint all check.
- Nyquist split (derivative wavenumber zeroed vs squared kept): Architecture §4,
  invariant 5, `FieldSpectralMultipliers` / `_axis_wavenumber_values` docstrings,
  DifferentialOperators module header — uniform.
- Convolution theorem `F(f⋆g)=f̂·ĝ` with unnormalized forward; Hermitian-kernel
  reality condition `ĝ(−k)=conj ĝ(k)`: Convolution docstrings ⇄ Architecture §11 ⇄
  Formalization — agree.
- rfft half-spectrum Parseval weighting (`α=1` on `kx=0` / even-Nyquist planes, `2`
  else); `sum(radial_spectrum)==inner`; `C(0)==inner`; `C(r)=F⁻¹(|f̂|²)/N`
  normalization: Reductions docstrings ⇄ Formalization ⇄ Architecture §12 — agree
  and expand correctly.
- Interpolation/anterpolation adjoint `M⟨Wf,q⟩ = N⟨f,Wᵀq⟩` (bare `⟨Wf,q⟩=⟨f,Wᵀq⟩`
  false unless N=M), partition-of-unity conservation: Interpolation module docstring
  ⇄ Formalization ⇄ Architecture §10 — agree.
- Spline smoothness/order: `LalescuSpline(n,m)` degree `2m+1`, `C^m`, reproduction
  `min(2m+1,2n)`; `CatmullRom = (1,1)` cubic `C¹` quadratic-precision; `LagrangeSpline(n)`
  `C⁰` degree `2n+1`; `m=0`/`n=0` linear — consistent across Interpolation page,
  Architecture §10, decision-log, and correctly distinguished (no
  `LagrangeSpline ≡ LalescuSpline(n,0)` conflation).
- DirectDFT type-2/type-1 sums and NUFFT (spread→FFT→deconvolve, σ=2, Nyquist
  projected out): Interpolation page ⇄ Formalization ⇄ Architecture §10/decision 23 —
  agree.
- HIST integrating-factor RK2 (Heun) update, 2/3 de-alias, `u'=√(2K/3)`,
  `Re_λ=√(15u'⁴/(νε))`, `λ=u'√(15ν/ε)`, K41 spectrum `C_K ε^{2/3} κ^{-5/3}` — all
  internally consistent and dimensionally complete.
