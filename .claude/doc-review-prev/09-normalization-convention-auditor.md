# Findings — Normalization & Convention Auditor

Reviewer hat: NORMALIZATION & CONVENTION specialist. Focus: every normalization
factor and indexing convention must be (a) structurally correct and (b) identical
everywhere it appears. Document read: `manuscript-full.md` (whole rendered site +
design docs).

## Summary of what was mechanically cross-checked and found CONSISTENT

For the record (these are the load-bearing factors my hat targets; all verified
identical across every page that states them, so NOT findings):

- **Transform 1/N placement** — forward unnormalized, inverse carries 1/N:
  architecture §4, formalization ("Representations and transforms":
  `f̂(k)=Σ_x f e^{-ik·x}`, `f(x)=(1/N)Σ_k f̂ e^{ik·x}`), Fields transform
  docstrings. Consistent.
- **DC-mode integral/mean** — `mean=f̂(0)/N`, `integral=(|Ω|/N)f̂(0)`,
  `f̂(0)=Σ_x f`: architecture §12, formalization ("Reductions"), Reductions
  `integral`/`inner` docstrings. Consistent.
- **Constant-add zero-mode scaling** — `F(f+c)=f̂+cN δ_{k,0}`, `N=prod(grid_size)`:
  architecture §2, formalization, `FieldAlgebra.add!`, `_spectral_constant_scale`.
  Consistent.
- **Spectral multiplier signs** — `∇→ik`, `∇·→ik·`, `∇×→ik×`, `Δ→-|k|²`,
  `Δ⁻¹→-|k|⁻²` (0 at k=0), `P→I-k̂k̂ᵀ = δ_ij-k_ik_j/|k|²`: architecture §4,
  formalization, every DifferentialOperators docstring, Notation page. Consistent.
- **symmetric_gradient** `Ŝ_ij=(i/2)(k_jû_i+k_iû_j)`: formalization + API. Consistent.
- **Nyquist split** — derivative wavenumber zeroed, squared wavenumber keeps true k²:
  architecture §4, formalization, Fields `_axis_wavenumber_values`, DiffOps module,
  Convolution builders. Consistent.
- **rfft half-spectrum Parseval weight** — `α(k)=1` on self-conjugate (k_x=0 and
  even-N_x Nyquist) planes, `2` else; `inner=(1/N²)Re(2Σ_{k_x≥0}-Σ_{k_x=0}-Σ_{Nyq})`:
  formalization, `radial_spectrum`, `weighted_inner`, `DirectDFT`. Consistent
  (1/N² throughout).
- **Convolution theorem** — `F(f⋆g)=f̂·ĝ`, NO stray 1/N (forward unnormalized):
  architecture §2/§11, formalization, `convolve!`. Consistent.
- **Interpolation/anterpolation adjoint N/M** — `M⟨Wf,q⟩_pts=N⟨f,Wᵀq⟩_grid`,
  `ι_*=(N/M)Wᵀ`: architecture §10, formalization, Interpolation module docstring.
  Consistent.
- **DirectDFT factors** — `f(x_p)=(1/N)Σ_k f̂ e^{ik·(x_p-o)}` (full) `=(1/N)Σ_stored
  α(k)Re(...)` (half): architecture §10, formalization, `DirectDFT`. Consistent.
- **Structure-function / K41 normalizations** (examples page) — `S^(E)=(1/3)⟨|Δu|²⟩
  =(2/3)(C(0)-C(r))`, `S^(E)_K41=(11/9)C_2 ε^{2/3}Δx^{2/3}`, `S^(L)=C_0 ε Δt`,
  `E(κ)=C_K ε^{2/3}κ^{-5/3}`, constants `C_2≈2.1, C_0≈6, C_K≈1.6`. Dimensionally
  complete, all constants carried, internally consistent.

Two discrepancies survived. Details below.

---

## Finding 1 — `translation_kernel` displayed formula contradicts the formalization (and its own prose) at the Nyquist frequency

- **type:** contradiction (also math / normalization)
- **severity:** major
- **confidence:** high

**Locations (both quoted):**

PAGE: api / Convolution, `translation_kernel` docstring. The displayed transfer
function is presented as the pure phase, with the SAME wavenumber `k_a` inside
both `cos` and `sin`:

> "Its transfer function $\hat g$ at wavenumber $k$ is the shift theorem's phase,
> assembled per axis from that wavenumber's component $k_a$ and the displacement
> $h_a$ along the axis:
> \[\hat g(k) = \mathrm{e}^{-\mathrm{i}  k \cdot h}
>           = \prod_{a=1}^{3} \bigl[ \cos(k_a h_a) - \mathrm{i} \sin(k_a h_a) \bigr].\]"

PAGE: formalization, "Convolution" section. The *implemented* multiplier is
written with DIFFERENT wavenumbers: `cos` takes the **true** signed wavenumber
`κ_a`, `sin` takes the **derivative** wavenumber `κ̃_a` (which is zeroed at the
Nyquist frequency, invariant 5):

> "Write $\kappa_a$ for the true signed wavenumber of axis $a$, $\tilde\kappa_a$
> for the derivative wavenumber (equal to $\kappa_a$ except at the Nyquist
> frequency of an even-length axis, where it is zeroed — invariant 5) ... The
> implemented multiplier is the separable product
> \[\hat g_h(k) = \prod_{a=1}^{3} \bigl[  \cos(\kappa_a h_a) \;-\; \mathrm i
> \sin(\tilde\kappa_a h_a)  \bigr].\]"

and, explicitly rejecting the API's formula as one of the *wrong* candidates:

> "the true phase $e^{-\mathrm i k\cdot h}$ is not Hermitian at Nyquist for a
> fractional displacement, and the all-derivative-wavenumber kernel is Hermitian
> but carries the wrong value."

**contradicts:** formalization "Convolution" —
`ĝ_h(k)=∏_a[cos(κ_a h_a) − i·sin(κ̃_a h_a)]` (implemented, real at Nyquist) versus
the Convolution API's `ĝ(k)=e^{-ik·h}=∏_a[cos(k_a h_a) − i·sin(k_a h_a)]` (the "true
phase," complex at Nyquist). **Axis of disagreement:** the sine's wavenumber
argument at an even-axis Nyquist frequency — derivative (zeroed ⇒ factor is the
*real* `cos(π h_a/Δx_a)`) versus true (⇒ a *complex* unit-modulus phase).

**description:**
The two pages give literally different product formulas for the same kernel.
Expanding at an even-axis Nyquist mode:
- Formalization form: `cos(κ_N h) − i·sin(κ̃_N h) = cos(π h/Δx) − i·sin(0) =
  cos(π h/Δx)` — **real**, hence Hermitian (the Nyquist mode is its own conjugate
  partner, so it MUST be real for the result to be a real field). This is decision 28.
- Convolution API form: `cos(k_N h) − i·sin(k_N h) = e^{-i k_N h}` — **complex** for
  a fractional displacement. This is exactly "the true phase `e^{-ik·h}` [that] is
  not Hermitian at Nyquist," which the formalization names as a rejected candidate.

So the displayed equation `ĝ(k)=e^{-ik·h}` in the user-facing `translation_kernel`
docstring is FALSE at the Nyquist frequency for the kernel the package actually
applies. It also contradicts the docstring's OWN prose two lines below —
"At the Nyquist frequency the phase becomes a real attenuation ... the kernel
therefore carries this real factor rather than a complex phase — and it has to be
real" — so the docstring simultaneously displays a pure-phase formula and then
verbally overturns it. The architecture §11 mention (`translation_kernel` "the
shift theorem's phase $e^{-ik·h}$") is safe because it never writes the explicit
`∏[cos − i·sin]` expansion and adds the Nyquist caveat in prose; the Convolution
API is the only surface that writes the wrong product expansion. Since decision 28
exists precisely to get this Nyquist factor right, the home docstring displaying the
rejected form is a real defect, only partly mitigated by the correcting prose.

**resolution_hint (advisory):** Match the formalization: either write the displayed
formula with the split wavenumbers `∏_a[cos(κ_a h_a) − i·sin(κ̃_a h_a)]`, or scope
the `ĝ(k)=e^{-ik·h}` equality explicitly to the resolved (sub-Nyquist) band and give
the Nyquist factor `cos(π h_a/Δx_a)` as the actual value there.

---

## Finding 2 — symbol `E(κ)` denotes two quantities differing by a factor of 2 across pages (radial power spectrum vs. kinetic-energy spectrum)

- **type:** normalization (symbol-overload / halving of the radial spectrum)
- **severity:** minor
- **confidence:** medium

**Locations (both quoted):**

PAGE: api / Reductions, `radial_spectrum` docstring binds the code name to the
symbol `E(κ)` as the raw Parseval spectrum, whose shell sum is the *un-halved*
inner product:

> "The radial (shell-binned) spectrum resolves a field's L² energy over
> wavenumber-magnitude shells (`radial_spectrum` $\equiv E(\kappa)$)."
> ... "$\sum_\kappa E(\kappa) = \langle f, f\rangle$ ..."
> ... "The consumer's kinetic-energy spectrum is $\tfrac{1}{2} E(\kappa)$; the
> package keeps the neutral name ..."

PAGE: examples / hist_cpu uses the SAME symbol `E(κ)` for the *half-scaled*
kinetic-energy spectrum, whose shell sum is `½⟨|u|²⟩`:

> "$E(\kappa) = \tfrac{1}{2} \times$ the shell-resolved Parseval inner;
> $\sum_\kappa E(\kappa) = \tfrac{1}{2}\langle\lvert u\rvert^{2}\rangle = k$, the
> kinetic energy."

and in the Results section:

> "The energy spectrum $E(\kappa)$, compared against the K41 inertial-range form
> $E(\kappa) = C_K \varepsilon^{2/3} \kappa^{-5/3}$ ..."

**contradicts:** api/Reductions `radial_spectrum` (`E(κ)` with `Σ E = ⟨f,f⟩ =
⟨|u|²⟩`) versus examples/hist_cpu (`E(κ)` with `Σ E = ½⟨|u|²⟩ = k`). **Axis of
disagreement:** whether the glyph `E(κ)` carries the physics factor of ½. The two
uses differ by exactly a factor of 2.

**description:**
`radial_spectrum` returns the raw Parseval-weighted spectrum (`Σ = inner`, verified
consistent in the tutorial too: `sum(spectrum) = inner(u,u) = 1.5`), and the
Reductions docstring binds `radial_spectrum ≡ E(κ)`. The HIST demo, following the
standard turbulence convention where `∫E dκ = ½⟨u²⟩ = k`, applies the ½ and reuses
the symbol `E(κ)` for the resulting kinetic-energy spectrum. Both surfaces flag the
½ as consumer-side physics (Reductions: "the consumer's kinetic-energy spectrum is
½ E(κ)"; examples: "E(κ): physics ½ stays consumer-side"), so this is a deliberate,
disclosed convention split rather than a hidden error — hence minor. But the net
effect is that the reader meets the same symbol `E(κ)` bound to the raw spectrum in
the API reference and to the half-scaled spectrum in the worked example, a factor-of-2
overload of one glyph across two pages. Worth noting because a factor-of-2 in the
radial power spectrum is exactly the kind of silent slip this convention split invites;
here it is handled correctly but the shared symbol is the weak point.

**resolution_hint (advisory):** Consider giving the raw package spectrum its own
symbol (e.g. `Ê(κ)` or "the shell energy") distinct from the physics `E(κ)=½·`,
or add a one-line cross-note in the examples page that its `E(κ)` is `½ ×
radial_spectrum`. No factor is wrong; only the symbol is shared.
