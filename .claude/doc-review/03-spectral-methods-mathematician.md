# Doc review — Applied Mathematician (pseudospectral / Fourier methods on the torus)

Scope: the rendered site `manuscript-full.md` (Home, api overview, architecture, formalization,
notation, performance, testing, tutorial, all API docstring pages, and the HIST_CPU example).

Headline: **the core spectral-methods mathematics is sound and internally consistent across every
page.** I verified, and found agreement everywhere, on: the forward-unnormalized / inverse-1/N transform
pair and where the 1/N lives; the constant-add touching only the zero mode scaled by N; integral/mean via
the DC coefficient with the |Ω|/N and prod(grid_size) factors; the ik / −|k|² multipliers and their signs;
the deliberate Nyquist split (derivative wavenumber zeroed on even axes, squared wavenumber keeping true
k²); the decision-42 exact discrete Helmholtz projector id − â âᵀ with the |a|² (derivative-family)
denominator vs the resolved-band composite u − ∇Δ⁻¹(∇·u); the convolution theorem f̂·ĝ with the Hermitian
reality condition; the Parseval half-spectrum weighting (α = 1 on the self-conjugate zero and even-Nyquist
planes, 2 else, with 1/N²); radial_spectrum sum == inner and radial_correlation C(0) == inner
(Wiener–Khinchin); the unnormalized-sinc² CIC assignment window; the translation-kernel Nyquist treatment
(even/cos ← true k, odd/sin ← Nyquist-zeroed derivative k); DirectDFT type-1/type-2 and the measure-weighted
adjoint; the spline reproduction degrees (min(2m+1,2n) smooth / 2n+1 Lagrange, Catmull–Rom = (1,1) cubic C¹
with quadratic precision); the heat-kernel identity e^{−cΔ} with Gaussian length √(−2c); and the K41
constants (E = C_K ε^{2/3} κ^{−5/3}; per-component S₂ = (11/9) C₂ ε^{2/3} r^{2/3}).

The findings below are formatting / staleness / bookkeeping issues, not mathematical errors.

---

## Finding 1 — Notation glossary: the wavenumber row is truncated/mangled; κ = |k| is never defined
- **type:** typesetting
- **severity:** major
- **confidence:** high
- **locations:**
  - PAGE: notation, "Base and fiber" table, line 744 — rendered verbatim as:
    `$k$ | a wavenumber vector ($k_a$ is its $a$-th component, `` | k`
  - Contrast the well-formed neighbours, PAGE: notation, same table:
    `$N$ | the grid-point count $\prod_i N_i$ | prod(grid_size)` and
    `$h$ | a physical displacement ($h_a$ is its component along axis $a$); … | translation_kernel`
- **description:** On the canonical Notation page (self-described as "the single reference" for the docs'
  symbols), the row for the wavenumber `$k$` has a **broken Meaning cell**: it ends mid-sentence at
  "$k_a$ is its $a$-th component, " followed by a **stray empty inline-code span** ` `` ` and then the
  column break. The intended magnitude clause is lost. The almost-certain cause is the exact GFM-table
  hazard the house rulebook warns about repeatedly (a `|` — including an abs/norm bar — is parsed as a
  column delimiter): a cell containing `|k|` (the magnitude) breaks the table row. Consequence beyond the
  cosmetic break: the wavenumber **magnitude symbol κ = |k| is never defined on the Notation page**, even
  though κ is used pervasively downstream — `radial_spectrum` ("bin-center wavenumber magnitudes $\kappa$",
  "$\kappa$ ($=|k|$)"), the Reductions module summary, and the HIST example ("$\kappa = \lvert\mathbf{k}\rvert$").
  A reader reaching the glossary for κ finds a garbled row.
- **resolution_hint (advisory):** restore the cell without a raw pipe — e.g. write the magnitude as
  `$\kappa = \lVert k\rVert$` (or `\lvert k\rvert` using `\lvert…\rvert`, no bare `|`), and add a κ row so
  the shell-magnitude symbol used across Reductions/examples is glossed on the reference page.

---

## Finding 2 — HIST_CPU example: stale "alias-guarded" / "no-alias path" comments on helmholtz_projection!
- **type:** contradiction
- **severity:** minor
- **confidence:** high
- **locations:**
  - PAGE: examples / hist_cpu, `rhs!`, line 3881:
    `helmholtz_projection!(Nh, ws.Nt, m)           # Leray projection — DISTINCT dest ⇒ no-alias path (no allocation)`
  - PAGE: examples / hist_cpu, `random_solenoidal`, line 3933:
    `helmholtz_projection!(uh, uh, m)                        # make solenoidal (alias-guarded)`
  - Contradicted by PAGE: api / DifferentialOperators, `helmholtz_projection!` docstring, line 1594:
    "The `destination` may alias `field` at no cost: the projection is computed in a single pass that reads
    all three components of a mode before writing any of them, so the aliased call needs no temporary."
  - Also contradicted by PAGE: architecture §7, line 291 ("The former guard family (`_guard_noalias!`…) …
    is retired") and decision 32, line 517 ("the guard and its temporary are retired … the aliased call is
    bitwise-identical to the non-aliased one"); PAGE: testing line 1016 ("the guard-free aliased
    `helmholtz_projection!`").
- **description:** The example's inline comments describe the **superseded** guarded implementation. Under
  the current design (decision 32) the one-pass kernel is alias-safe by construction and allocation-free
  **whether or not** the destination aliases the source, so there is no separate "no-alias path" and no
  "guard". The comment at 3933 is on a genuinely aliased call `(uh, uh, m)` and directly asserts a guard
  that no longer exists; the comment at 3881 implies (via "DISTINCT dest ⇒ no-alias path") that an aliased
  call would take a different, allocating path. Both mislead a reader who is being taught the
  allocation-free pattern. (The code itself is correct; only the annotations are stale.) The `rhs!` docstring
  header still calls the same operator "DISTINCT dest ⇒ no-alias path" — worth aligning with the operator's
  own "alias at no cost" wording.
- **resolution_hint (advisory):** reword to e.g. `# Leray projection (one pass, alias-safe, no allocation)`
  and `# make solenoidal (in-place, alias-safe)`.

---

## Finding 3 — lpnorm docstring: orphaned "Ω / |Ω|" sentence (symbols introduced but never used)
- **type:** clarity
- **severity:** nit
- **confidence:** high
- **locations:**
  - PAGE: api / Reductions, `lpnorm` docstring, line 3556: "Here $\Omega$ is the periodic box and
    $|\Omega|$ its volume."
  - The lpnorm formulas immediately above (lines 3551–3555) use only $N$, $M$, $x$, $p$ — neither $\Omega$
    nor $|\Omega|$ appears anywhere in this docstring.
- **description:** A trailing sentence defines $\Omega$ and $|\Omega|$ that the docstring never uses (the
  grid form is written as the discrete $\tfrac{1}{N}\sum_x$, not a continuum $\tfrac{1}{|\Omega|}\int$).
  It reads as a leftover from a template/sibling docstring (`inner` legitimately introduces $\Omega$/$|\Omega|$
  because it carries the continuum $\tfrac{1}{|\Omega|}\int_\Omega$ form). Harmless but a dangling
  definition on an otherwise clean page.
- **resolution_hint (advisory):** delete the sentence, or write lpnorm's grid form with the continuum
  $\tfrac{1}{|\Omega|}\int_\Omega |f|^p$ face the way `inner`/`integral` do so the binding is used.

---

## Finding 4 — Decision-24 log entry shows the pre-decision-42 Helmholtz factor (k, |k|²), not the current (a, |a|²)
- **type:** contradiction
- **severity:** minor
- **confidence:** low
- **locations:**
  - PAGE: architecture, §13 decision 24, line 465: "…and Helmholtz projection
    ($\hat f_i - k_i (k_j\hat f_j)/|k|^2$)…"; and "the aliased `helmholtz_projection!(x, x)` allocates its
    guard temporary upstream (§7)", with the forward note "(The projection has since moved on from both
    details: its one-pass kernel computes the longitudinal part once per mode and serves the aliased call
    directly, guard retired — decision 32.)"
  - Current authoritative form, PAGE: api / DifferentialOperators, line 1600:
    `$\widehat{(\mathbb P u)}_i(k) = (\delta_{ij} - \frac{a_i a_j}{|a|^2})\hat u_j(k)$` with `$a$` the
    derivative wavenumber; PAGE: formalization line 602–604 (`$\mathbb P \to \mathrm{id} - \hat a\hat a^\top$`,
    `$\hat a = a/|a|$`, decision 42); PAGE: architecture decision 42, line 553.
- **description:** Decision 24's inline projection factor uses the **true** wavenumber `k` and denominator
  `|k|²`; decision 42 later made the projector use the **derivative** family `a` and `|a|²` (so it is the
  exact discrete projector at every mode). The two coincide sub-Nyquist, so this is not a live math error —
  but decision 24's self-contained entry (the log is browsed "entry-by-entry") shows a now-superseded
  formula, and its forward-note flags the aliasing/one-pass change (decision 32) while **not** flagging the
  denominator change (decision 42). Low confidence because the append-only log is intended to preserve
  historical state; flagged only because the entry's own forward-note is partial.

---

## Finding 5 — Point-value method-count bookkeeping does not reconcile: 118 → 122 with only +2 accounted
- **type:** contradiction
- **severity:** minor
- **confidence:** low
- **locations:**
  - Historical (decision log), PAGE: architecture line 400: "locked by a separate 118-method baseline";
    line 435: "the … point-value 118-method parity baselines are unchanged".
  - Current, PAGE: architecture decision 27, line 482: "grows to 206 field methods (`combine!` adds 2,
    `det`/`det!` 1 each) and **122 point-value methods** (`det`/`det!` 1 each)"; PAGE: testing line 948 /
    architecture line 348 also state 122.
- **description:** The current point-value baseline is 122; the last count stated in the decision log before
  it is 118. Decision 27 attributes only **+2** to point-values (det/det!, "1 each"), which would give
  118 + 2 = 120, not 122. The missing +2 is presumably the `tr`/`tr!` pair mirrored onto point-values
  (decision 27's det entry, line 479, notes det "mirror[s] tr, which already lived on both"), but that
  point-value increment is never stated as a count anywhere, so the numbers as written (118 … then "grows
  … 122 (det/det! 1 each)") don't add up on their face. This is decision-log/count bookkeeping (outside the
  spectral-methods remit) and low confidence, since the field-side companion counts (198 → 206) travel with
  it under the documented append-only convention; flagged as an internal-consistency observation only.

---

## Verified-clean (spot list, to document what was cross-checked and found consistent)
- Transform pair: `$\hat f(k)=\sum_x f e^{-ik\cdot x}$`, `$f=\tfrac1N\sum_k \hat f e^{ik\cdot x}$` — formalization
  line 581–582, architecture §4 line 252, Fields transform docstrings. Uniform.
- Constant add → zero mode × N (= prod(grid_size)): architecture §2 line 222, formalization line 586,
  `add!` line 2057. Uniform.
- integral/mean via DC mode: `$\hat f(0)=\sum_x f$`, mean `$=\hat f(0)/N$`, integral `$=(|\Omega|/N)\hat f(0)$`
  — architecture §12 line 367, formalization line 654, `integral` line 3493. Uniform.
- Nyquist split (derivative zeroed on even axes / squared keeps true k²): architecture §4 line 257–260,
  `_axis_wavenumber_values` line 2924, formalization line 604, invariant echoed in every kernel-builder
  docstring. Uniform.
- Parseval half-spectrum weight α (1 on self-conjugate planes, 2 else, 1/N²): formalization line 664,
  `weighted_inner` line 3527, `radial_spectrum` line 3572, `DirectDFT` line 3237, `inner` line 3515. Uniform.
- radial_spectrum ∑P = inner; radial_correlation C(0)=inner, `$\mathcal F C=|\hat f|^2/N$`: formalization
  line 666–671, Reductions docstrings line 3572/3586, tutorial line 1096, example line 3839. Uniform.
- translation_kernel Nyquist (cos←true k, sin←Nyquist-zeroed derivative k; real cos(πh_a/Δx_a) at Nyquist):
  architecture decision 28 line 489, formalization line 633–639, docstring line 3300–3304. Uniform and correct.
- assignment_window `$\hat W=\prod_a\mathrm{sinc}^2(k_a\Delta x_a/2)$`, unnormalized sinc, no in-band zeros:
  formalization line 630, docstring line 1283. Correct (FT of the linear/CIC tent).
- Spline reproduction: min(2m+1,2n) smooth / 2n+1 Lagrange; Catmull–Rom = (1,1) cubic C¹, quadratic
  precision; `LalescuSpline(0,0)` = 2-point linear = the CIC assignment: `LalescuSpline` line 3203–3205,
  `LagrangeSpline` line 3223, `CatmullRom` line 3216, architecture line 342/404. Uniform.
- K41: E(κ)=C_K ε^{2/3} κ^{−5/3} (C_K≈1.6); per-component S₂ = (11/9) C₂ ε^{2/3} r^{2/3} (C₂≈2.1);
  S^{(E)} = ⅓⟨|δu|²⟩ = ⅔(C(0)−C(r)); u'=√(2K/3); Re_λ=√(15 u'⁴/(νε)); λ=u'√(15ν/ε); ε=ν⟨|ω|²⟩ — all
  dimensionally complete and mutually consistent (example lines 4044–4048, 4120–4135). Correct.
