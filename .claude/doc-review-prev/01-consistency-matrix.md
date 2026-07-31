# Consistency Matrix — findings (hat: consistency-matrix)

Auditor built a matrix of every recurring entity (symbols, defining formulas,
normalizations, code names, counts, test-file attributions) and diffed it across all
18 pages of the rendered site + design docs (`manuscript-full.md`). Findings below,
most severe first.

---

## 1. `E(κ)` / `E(k)` means the radial spectrum in some pages and HALF of it in others (factor of 2)
- **type:** contradiction · **severity:** major · **confidence:** high
- **The symbol `E(κ)` (energy spectrum) is bound to two different quantities across the site, differing by a factor of ½.**

**Side A — `E(κ)` = `radial_spectrum` itself, so `Σ E(κ) = inner(f,f) = ⟨|u|²⟩`:**
- PAGE: api / Reductions, `radial_spectrum` docstring: "The radial (shell-binned) spectrum … (`radial_spectrum` $\equiv E(\kappa)$)" and "$\sum_\kappa E(\kappa) = \langle f, f\rangle$ … The consumer's kinetic-energy spectrum is $\tfrac{1}{2} E(\kappa)$".
- PAGE: formalization, §Reductions: "$\sum_i E(\kappa_i) = \langle f,f\rangle$" with "$E(\kappa_i) = \frac{1}{N^2}\sum … \alpha(k)\sum_c |\hat f_c(k)|^2$".
- PAGE: testing, §7: "the shell-resolved Parseval inner `radial_spectrum` … the exact refinement $\sum_\kappa E(\kappa) = \langle f, f\rangle$".
- PAGE: tutorial, "Fiberwise algebra and L²/measure reductions": `round(sum(spectrum); digits = 4)   # Σ E(k) = inner(u, u)` → `1.5` (and `inner(u,u)` is `1.5`).

**Side B — `E(κ)` = ½·`radial_spectrum` (the physical energy spectrum), so `Σ E(κ) = ½⟨|u|²⟩ = k` (TKE):**
- PAGE: architecture, §13 decision 21: "The consumer's energy spectrum over the shell wavenumber $\kappa$ ($= |k|$) is $E(\kappa) = \tfrac{1}{2} \mathrm{spectrum}$".
- PAGE: architecture, §13 decision 22: "the energy spectrum $E(k) = \tfrac{1}{2} \mathrm{radial\_spectrum}$".
- PAGE: examples / hist_cpu, Diagnostics: "$\sum_\kappa E(\kappa) = \tfrac{1}{2}\langle\lvert u\rvert^{2}\rangle = k$, the turbulent kinetic energy" and `return shells, 0.5 .* spectrum   # E(κ): physics ½ stays consumer-side`.

- **contradicts:** Reductions API binds `radial_spectrum` $\equiv E(\kappa)$ (so `E` sums to `inner`), while architecture decision 21/22 asserts `E(κ) = ½·radial_spectrum` (so `E` sums to `½ inner`). The two runnable user examples are the sharpest clash: tutorial prints `Σ E(k) = inner(u,u)` (=1.5) but examples/hist_cpu prints/states `Σ E(k) = ½⟨|u|²⟩ = k` (= ½ inner). Axis: whether `E(κ)` is the package quantity or half of it.
- **resolution_hint:** Either rename the package quantity (drop `radial_spectrum ≡ E(κ)`, call it the "shell spectrum" and reserve `E(κ)` for the physics ½-form everywhere), or make architecture/examples stop calling ½·spectrum "`E(κ)`". Pick one meaning site-wide.

---

## 2. Architecture §2 headline says "206-method surface" but its own step-by-step arithmetic stops at 202
- **type:** math · **severity:** major · **confidence:** high
- PAGE: architecture, §2 "Representation validity lives in the method set": "The **206-method** public surface of `FieldAlgebra` … — M2 (98 methods…) and then M3 (…), **bringing the total to 198**; the later trace `tr`/`tr!` addition **brings it to 202**, all parity-checked at runtime".
- The running total (98 → 198 → 202) never reaches the stated 206; the missing +4 (`combine!` +2, `det`/`det!` +2) is only accounted for elsewhere (decision 27: "grows to 206 field methods (`combine!` adds 2, `det`/`det!` 1 each)"). So the paragraph asserts 206 but derives 202.
- **contradicts:** within the same paragraph — "206-method public surface" vs "brings it to 202". Also vs §6/§10 ("206-method"), decision 27 line, api/testing ("206").
- **resolution_hint:** Continue the arithmetic to 206 (add the `combine!` and `det`/`det!` step) or drop the stale running total.

---

## 3. rocFFT forward-transform preservation: "preserves both directions" vs "reserves the right to use r2c inputs as scratch"
- **type:** contradiction · **severity:** major · **confidence:** medium
- PAGE: architecture, §4: "It is also backend-divergent — verified that **AMD/rocFFT (via AMDGPU.jl) preserves both directions on tested sizes**, while FFTW does not."
- PAGE: api / Fields, `to_spectral!` docstring: "The forward transform may overwrite `physical` on some backends (for example **rocFFT reserves the right to use real-to-complex inputs as scratch**); the FFTW CPU backend preserves it, but do not rely on the source surviving."
- **contradicts:** Architecture says rocFFT preserves BOTH directions (so it preserves the forward r2c input); the `to_spectral!` docstring singles out rocFFT as the backend that may scratch the forward (r2c) input while FFTW preserves it. Axis: does rocFFT preserve the forward-transform input?
- **resolution_hint:** Reconcile the empirical claim (architecture) with the conservative contract (docstring); if rocFFT empirically preserves both but is not contractually guaranteed to, say so consistently in both places.

---

## 4. Notation glossary defines the wavenumber magnitude as ‖k‖, but every formula uses |k|
- **type:** normalization · **severity:** minor · **confidence:** high
- PAGE: notation, §Base and fiber: "$k$ | a wavenumber vector ($k_a$ is its $a$-th component, **$\lVert k\rVert$ its magnitude**) | FieldSpectralMultipliers".
- Every actual usage of the wavenumber magnitude across the site is **$|k|$** (single bars): `laplacian` `$-|k|^2$`, `squared_wavenumber_field` `$|k|^2 = k_1^2+k_2^2+k_3^2$`, `spectral_cutoff` `$|k|\le k_c$`, formalization `$-|k|^2$`, radial reductions `$|k|$`-shells, etc. (grep: `|k|` appears 77×; `\lVert k\rVert` appears once — only in the glossary).
- **contradicts:** The single notation reference (`notation` page) uses `‖k‖` for a quantity the whole rest of the site writes `|k|`.
- **resolution_hint:** Change the glossary to `$|k|$` (or make usage `‖k‖`); the glossary should mirror usage. Note `‖·‖` is also assigned to `l2norm` on the same page, so `‖k‖` double-loads the glyph.

---

## 5. Fiber `norm` written |·| in FieldAlgebra/notation but ‖·‖ in Formalization
- **type:** normalization · **severity:** minor · **confidence:** medium
- PAGE: api / FieldAlgebra, `norm!`: "(`norm` $\equiv |\cdot|$)" and "$|\varphi|, \quad |u| = \sqrt{u_i u_i}, \quad |A| = \sqrt{A_{ij} A_{ij}}$" (single bars); notation page reserves `$\lVert\cdot\rVert$` for `l2norm`.
- PAGE: formalization, §Fiberwise algebra: "$\lVert u\rVert = \sqrt{u_i u_i}, \quad \lVert A\rVert = \sqrt{A_{ij}A_{ij}}$" (double bars for the *fiber* pointwise norm).
- **contradicts:** The same fiber (pointwise) `norm` operation is `|·|` in FieldAlgebra but `‖·‖` in Formalization — and `‖·‖` is elsewhere the global `l2norm`, so Formalization's fiber-norm `‖·‖` collides with the L²-norm symbol.
- **resolution_hint:** Use `|·|` for the fiber norm in Formalization too, keeping `‖·‖` for `l2norm`.

---

## 6. Performance §6/§7: code identifiers render without their underscores (radialspectrum, symmetricgradient!, weightedinner) and inline code is jammed against prose
- **type:** typesetting · **severity:** minor · **confidence:** high
- PAGE: performance, §6: "the radial diagnostics (`radialspectrum`/`radialcorrelation`) …`radialspectrum`at 256³ is ≈12× faster … in`Float32`, widening to ≈32× in`Float64`(92 → 2.9 ms)". (underscores lost + missing spaces around inline code)
- PAGE: performance, §7: "The decision-27 additions (`combine!`, `det!`, `symmetricgradient!`,`weightedinner`) … the small bounded wrappers for`symmetricgradient!`/`weighted_inner`". (Here `symmetricgradient!`/`weightedinner` lost underscores while `weighted_inner` kept them — in the SAME sentence.)
- The same names render correctly WITH underscores elsewhere on the same page (§5: "`radial_spectrum` / `radial_correlation`"). grep confirms `radialspectrum|radialcorrelation|symmetricgradient|weightedinner` occur only at lines 757 and 769.
- **contradicts:** Same identifiers rendered two ways on one page; consistent with the documented Markdown "unbackticked underscore → emphasis" trap.
- **resolution_hint:** Backtick the affected names properly and restore spaces around inline code in these two paragraphs.

---

## 7. `translation_kernel` transfer-function formula: naive phase in the API docstring vs the Nyquist-split implemented multiplier in Formalization
- **type:** math · **severity:** minor · **confidence:** medium
- PAGE: api / Convolution, `translation_kernel`: "$\hat g(k) = \mathrm{e}^{-\mathrm{i} k\cdot h} = \prod_{a=1}^{3}\bigl[\cos(k_a h_a) - \mathrm{i}\sin(k_a h_a)\bigr]$" — both factors use the same `k_a` (i.e. the pure phase `e^{-ik·h}`), with the Nyquist correction only in following prose.
- PAGE: formalization, §Convolution: "The implemented multiplier is the separable product $\hat g_h(k) = \prod_{a=1}^{3}[\cos(\kappa_a h_a) - \mathrm i\sin(\tilde\kappa_a h_a)]$" — cosine uses the TRUE wavenumber `κ_a`, sine uses the DERIVATIVE wavenumber `κ̃_a` (zeroed at Nyquist).
- **contradicts:** The API docstring equates `ĝ(k)` with `e^{-ik·h}` (both terms `k_a`), which architecture decision 28 and formalization explicitly call the WRONG (non-Hermitian-at-Nyquist) candidate; formalization gives the actual implemented split. Axis: the sine factor's wavenumber (true vs derivative) at Nyquist.
- **resolution_hint:** Show the implemented split in the API docstring (or clearly mark `e^{-ik·h}` as the resolved-band value only), matching formalization.

---

## 8. `assignment_window` sinc² test attributed to `test/convolution.jl` in Formalization but to `test/rdf.jl` in Architecture + Testing
- **type:** citation · **severity:** minor · **confidence:** medium
- PAGE: formalization, §Convolution: "Checked by `test/convolution.jl` — … cutoff idempotence, **the $\operatorname{sinc}^2$ window**, and the physical-space intentional absence".
- PAGE: architecture, §13 decision 22: "Verified (`test/rdf.jl`): `assignment_window` against its $\prod \operatorname{sinc}^2$ formula".
- PAGE: testing, §2 layout + §7: `assignment_window` listed under `rdf.jl`; the `convolution.jl` builder list is `spectral_cutoff / spectral_band / squared_wavenumber_field / translation_kernel` (no `assignment_window`).
- **contradicts:** Which test file verifies the `assignment_window` sinc² window — `convolution.jl` (formalization) vs `rdf.jl` (architecture + testing).
- **resolution_hint:** Point formalization's sinc²-window check at `test/rdf.jl`.

---

## 9. Decision log carries stale 198-method / 118-method counts vs the current 206 / 122 in the body and map
- **type:** contradiction · **severity:** minor · **confidence:** medium
- PAGE: architecture, §10 body: "locked by a separate **122-method** parity baseline, the **206-method** field surface byte-unchanged".
- PAGE: architecture, §13 decision entries: "locked by a separate **118-method** baseline (the **198-method** field surface byte-unchanged)"; "Both parity baselines (**198 + 118**) held byte-for-byte"; "the `FieldAlgebra` **198-method** and point-value **118-method** parity baselines are unchanged".
- **contradicts:** The same "field surface held byte-unchanged during the point-value work" claim is stated with 206/122 in the §10 body but 198/118 in the §13 log. (Decision 27 later updates to 206/122, so this is chronological staleness in an append-only log — but a reader browsing entries entry-by-entry, as the log is designed to be read, sees "198 methods, the full surface" contradicting §2/§6/§10's 206.)
- **resolution_hint:** Either accept as documented chronology, or add a "(now 206/122; decision 27)" hook on the earlier entries that call 198/118 "the full surface".

---

## 10. Architecture §10: reproduction identity stated over `Π_d` but referenced as `Π_m`
- **type:** typesetting · **severity:** minor · **confidence:** medium
- PAGE: architecture, §10: defines "$\phi$ for any polynomial in $\Pi_d$ (the polynomials up to the scheme's reproduction degree $d$)" and states the reproduction identity "$… \quad (\phi \in \Pi_d)$", then a few lines later: "which the reproduction identity above shows is **exact on $\Pi_m$**."
- **contradicts:** `Π_d` (defined = reproduction degree, `d = min(2m+1, 2n)`) vs `Π_m` (`m` = the smoothness parameter, a different quantity). The trailing `Π_m` should be `Π_d`.
- **resolution_hint:** Change `Π_m` → `Π_d`.

---

## 11. `sm120` vs `sm_120` (RTX 5070 Ti architecture tag)
- **type:** format · **severity:** nit · **confidence:** high
- PAGE: performance, §6: "the RTX 5070 Ti (Blackwell **sm120**, CUDA, 16 GB)" and §6 again "(Blackwell **sm120**)".
- PAGE: performance, §7: "the RTX 5070 Ti (Blackwell **sm_120**, 16 GB)".
- **resolution_hint:** Pick one spelling (`sm_120` is the CUDA convention).

---

## 12. Symbol `k`: wavenumber vector in the core docs, turbulent kinetic energy in the examples page
- **type:** normalization · **severity:** minor · **confidence:** low
- PAGE: notation: "$k$ | a wavenumber vector"; API/formalization use `k` (non-bold) for the wavenumber vector (e.g. `$\hat f(k) = \sum_x f(x) e^{-\mathrm i k\cdot x}$`).
- PAGE: examples / hist_cpu: uses bold `$\mathbf{k}$` for the wavenumber vector, `$\kappa = |\mathbf{k}|$` for its magnitude, and non-bold `$k$` for the turbulent kinetic energy ("$= k$, the turbulent kinetic energy").
- **contradicts:** `k` (non-bold) is the wavenumber vector everywhere except the examples page, where it is TKE (with `𝐤` promoted to the vector). This is a deliberate Pope-convention switch in the physics demo, but it is a genuine cross-site symbol collision the notation page does not flag.
- **resolution_hint:** Optionally note in the examples page that it adopts Pope's `k`=TKE convention distinct from the package's `k`=wavenumber; low priority.

---

## 13. Interpolation module docstring uses `⟨·,·⟩_{PointSet}` / `⟨·,·⟩_{Grid3D}`; architecture + formalization use `⟨·,·⟩_{pts}` / `⟨·,·⟩_{grid}`
- **type:** typesetting · **severity:** nit · **confidence:** low
- PAGE: api / Interpolation: "$M \langle Wf, q \rangle_{\texttt{PointSet}} = … = N \langle f, W^\top q \rangle_{\texttt{Grid3D}}$".
- PAGE: architecture §10 / formalization: "$\langle a, b\rangle_{\text{pts}}$" and "$\langle f, g\rangle_{\text{grid}}$".
- **contradicts:** Same two inner-product measures subscripted with code type-names vs text tags across pages. (Both are otherwise-legal, just inconsistent.)

---

## 14. `convolve!` "real-and-even kernels" list omits `squared_wavenumber_field`
- **type:** clarity · **severity:** nit · **confidence:** low
- PAGE: api / Convolution, `convolve!`: "the real, even ones (`spectral_cutoff`, `spectral_band`, `assignment_window`) trivially, and the complex `translation_kernel` by construction."
- PAGE: architecture §11: "The **first four** are real and even in the wavenumber $k$" — i.e. `spectral_cutoff`, `spectral_band`, `squared_wavenumber_field`, `assignment_window`.
- **contradicts:** The `convolve!` enumeration lists three of the four real-even builders and silently drops `squared_wavenumber_field`. (Illustrative list; minor.)

---

## 15. `α` overloaded: fiber-component index (Fields type docstrings) vs α/β accumulation weight (algebra/transfer)
- **type:** typesetting · **severity:** nit · **confidence:** low
- PAGE: api / Fields, `VectorFieldPhysical`/`VectorFieldSpectral`: "storage order `values_at_grid[i, j, k, α]`, where `α = 1, 2, 3`".
- PAGE: api / FieldAlgebra, Convolution, Interpolation: `α` is the accumulation weight (`combine!(dest, α, a, β, b)`, `mul!(…, α, β)`, `convolve!(…, α, β)`, `anterpolate!(…, α, β)`).
- **contradicts:** `α` denotes a fiber component index in the Fields storage-order docstrings but the package-wide accumulation scalar in the operator docstrings. (Tensor fields already use `α₁,…,αᵣ` for indices; the vector case reuses bare `α`.)

---

## 16. Home page / architecture: sentences run together with no space or paragraph break (possible consolidation artifact)
- **type:** typesetting · **severity:** nit · **confidence:** low
- PAGE: Home, Main components: "…refining the mixed `inner(f, g)`).**Pointwise (fiberwise) products** and norms live in `FieldAlgebra`…" (no space/break after the close-paren).
- PAGE: architecture: several spots, e.g. "never as `*`.**The pointwise product** is not preserved…", "…performance & threading (§9).**Reductions, convolution**…", "…representation-free (§10).**(The vertical/horizontal language**…".
- **contradicts:** N/A (formatting). May be an artifact of the reader-text consolidation joining adjacent blocks; flag low-confidence pending a check against the live HTML.
