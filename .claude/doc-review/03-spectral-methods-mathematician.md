# Hat 03 — Spectral-methods mathematician (pseudospectral / Fourier on the torus)

Review of the rendered site consolidation (`manuscript-full.md`). Findings ranked most-severe first.

---

## 1. The rfft image is mis-stated: "coefficients on the self-conjugate planes are real"

- **type:** math — **severity:** major — **confidence:** high

**Locations**

- PAGE: formalization, §Declarations — *"The image is the Hermitian-constrained subspace — the coefficients on the folded axis's self-conjugate planes are real"*
- PAGE: notation, §Scalar weights, `α(k)` row — *"its self-conjugate planes are the two … whose coefficients are their own conjugates"*

**Contradicts**

- PAGE: architecture, §13 decision 18 — *"the planes the rfft maps to themselves under conjugation, whose partners are already stored, so they count once"*
- PAGE: formalization, §Representations — *"the $k_x = 0$ plane, and on an even axis the Nyquist plane … are self-conjugate"* (plane-level, correct)

**Description.** On the $k_x=0$ and even-Nyquist planes the constraint is that the *plane* is closed under $k\mapsto -k$ — $\hat f(0,-k_y,-k_z)=\overline{\hat f(0,k_y,k_z)}$ — not that each coefficient is real. Only the eight modes with every component at $0$ or Nyquist are real. The dimension count confirms it: the excess $2N_yN_z$ reals is exactly the two planes' conjugate-symmetry constraint, not $2N_yN_z$ reality constraints. Two surfaces state the false version; the two correct statements are on the same pages.

**resolution_hint:** reword both to "closed under conjugation / each coefficient's partner is also stored".

---

## 2. Architecture's spectral `var` formula drops $1/N^2$ and the Parseval weight

- **type:** math — **severity:** major — **confidence:** high

**Locations**

- PAGE: architecture, §13 decision 49 — *"$\operatorname{var}(f) = \langle f, f\rangle - \langle f\rangle^2 = \sum_{k \ne 0} |\hat f_k|^2$"*

**Contradicts**

- PAGE: formalization, §Reductions — *"$= \frac{1}{N^2}\sum_{k\ne 0} \alpha(k) |\hat f(k)|^2$"*
- PAGE: api / Reductions, `var` — *"$\langle f,f\rangle - \langle f\rangle^2 = N^{-2}\sum_{k\ne 0}\alpha(k)|\hat f_k|^2$"*

**Description.** The decision-49 entry equates an intensive quantity with an unnormalized, unweighted mode sum. Under the package's convention (unnormalized forward, invariant 4) the identity needs both the $1/N^2$ and the rfft half-spectrum multiplicity $\alpha(k)$; without them it is wrong by $N^2$ and by roughly a factor of two. The decision log is declared self-contained and read entry-by-entry, so this one cannot borrow the correction from §12.

**resolution_hint:** copy the formalization form verbatim into the decision entry.

---

## 3. "The resolved band" is defined inclusive of Nyquist on the umbrella page and exclusive everywhere the identities are scoped

- **type:** contradiction — **severity:** major — **confidence:** high

**Locations**

- PAGE: api / GBGPeriodicFields, module docstring — *"The resolved band is the set of wavenumbers a grid's resolution actually represents, up to the Nyquist frequency on each axis."*

**Contradicts**

- PAGE: formalization, §Differential operators — *"on the resolved band — every mode off the even-axis Nyquist planes"*
- PAGE: api / DifferentialOperators, `helmholtz_projection!` — *"an identity exact on the resolved band … the two coincide off the Nyquist planes"*

**Description.** The umbrella page introduces "resolved band" as recurring package vocabulary and defines it to *include* the Nyquist frequency. Every load-bearing use scopes a claim by *excluding* the even-axis Nyquist planes — the dissipation identity $\langle\Delta\varphi,\varphi\rangle=-\lVert\nabla\varphi\rVert^2$, the composite $\mathbb P u = u-\nabla\Delta^{-1}(\nabla\cdot u)$, the unit-modulus translation phase, NUFFT's tolerance. A reader taking the umbrella definition will read those scoped claims as unconditional. Elsewhere the disambiguator "sub-Nyquist band" is used precisely because the bare term is ambiguous.

**resolution_hint:** define the resolved band as strictly below the Nyquist planes, or rename the scoped uses to "sub-Nyquist band" consistently.

---

## 4. `ProductKernel` is defined as radial×separable in two places but holds stored×stored and radial×radial in two others

- **type:** contradiction — **severity:** major — **confidence:** high

**Locations**

- PAGE: formalization, §Convolution — *"a product (`ProductKernel`), $\hat g = \sigma(|k|^2)\prod_a g_a(\kappa_a)$, which is what composing across the two compressed families gives"*, and *"Composition is closed within a family"*
- PAGE: api / Convolution, module docstring — *"`ProductKernel` — a radial and a separable factor held unmultiplied"*

**Contradicts**

- PAGE: api / Convolution, `ProductKernel` — *"That covers every cross-family pair, two stored kernels …, and two radial kernels whose coordinates cannot be shown to agree"*
- PAGE: api / Convolution, `convolve!` — *"every other pair — two stored kernels, a cross-family pair, or radial operands failing that test — becomes a `ProductKernel`"*

**Description.** The formalization's typed statement is strictly narrower than the implemented class, and its companion claim "composition is closed within a family" is false for the stored family (stored∘stored yields a `ProductKernel`, deliberately, to avoid an $O(N^3)$ materialization). The Home page compounds it by listing `ProductKernel` among classes "which store a closed-form multiplier rather than its coefficients" — untrue of a stored×stored product.

**resolution_hint:** state the product class as "two kernels held unmultiplied", and qualify family closure as separable-closed, radial-closed-under-canonical-coordinates, stored-not-closed.

---

## 5. `inv` is not interchangeable across storage classes, contradicting the blanket interchangeability claim

- **type:** contradiction — **severity:** minor — **confidence:** high

**Locations**

- PAGE: api / Convolution, module docstring — *"the four classes reach every kernel-taking entry point interchangeably"*; §Kernel storage classes — *"All four are applied identically and give bitwise-identical results"*

**Contradicts**

- PAGE: api / Convolution, `inv(kernel::StoredKernel)` — *"no kernel undoes it and this throws rather than returning a non-finite coefficient"*
- PAGE: api / Convolution, `inv(kernel::RadialKernel)` — *"the radial method documents the precondition it cannot test cheaply"*

**Description.** Inverting a sharp cutoff throws if the kernel is a `StoredKernel` and silently yields non-finite coefficients if it is the `RadialKernel` the builder actually returns — the same mathematical object, two different outcomes at the same entry point. The interchangeability claim is stated twice without the `inv` carve-out, and `spectral_cutoff` now returns the radial class by default, so the silent branch is the common one.

**resolution_hint:** scope the interchangeability claim to *application* (kernel×field passes) and name `inv` as the exception, with its per-class contract.

---

## 6. The transform pair omits the grid origin that `DirectDFT` carries

- **type:** math — **severity:** minor — **confidence:** medium

**Locations**

- PAGE: formalization, §Representations — *"$\hat f(k) = \sum_{x} f(x) e^{-\mathrm{i} k\cdot x}$"*

**Contradicts**

- PAGE: formalization, §Spectral transfer — *"$f(x_p) = \frac{1}{N}\sum_{\text{stored }k}\alpha(k)\mathrm{Re}\bigl(\hat f(k) e^{\mathrm{i} k\cdot(x_p-o)}\bigr)$"* ($o$ the grid origin)

**Description.** The declared transform pair uses the bare phase $e^{\mp\mathrm{i}k\cdot x}$, while the spectral transfer — which must agree with `to_physical` at the nodes — uses $e^{\mathrm{i}k\cdot(x_p-o)}$. On a grid with non-zero origin (an admissible, tested axis) the two conventions differ by $e^{-\mathrm{i}k\cdot o}$, so as written the round trip and `DirectDFT` cannot both be exact. The formalization page exists to pin exactly this kind of convention.

**resolution_hint:** write the pair over $(x-o)$, or state once that $x$ denotes the offset-from-origin node coordinate.

---

## 7. Symbol collisions: $\kappa$ means two things, and the per-axis wavenumber and the separable factor each have two symbols

- **type:** typesetting — **severity:** minor — **confidence:** high

**Locations**

- PAGE: notation, §Base and fiber — *"$\kappa$ | a wavenumber-shell magnitude, $\kappa = \lvert k\rvert$"*; and *"$k$ … ($k_a$ is its $a$-th component)"*
- PAGE: api / Convolution, `translation_kernel` — *"$\kappa_a$ is the true wavenumber and $\tilde\kappa_a$ the Nyquist-zeroed derivative one"*
- PAGE: formalization, §Convolution — *"Write $\kappa_a$ for the signed wavenumber of axis $a$"*, and separable factors written *"$\prod_a g_a(\kappa_a)$"*
- PAGE: api / Convolution, `SeparableKernel` — *"$\hat g(k) = \prod_a \sigma_a(k_a)$"* versus `RadialKernel`'s *"$\hat g(k) = \sigma(\lvert k\rvert^2)$"*

**Description.** The notation page binds $\kappa$ to the shell magnitude and $k_a$ to a wavenumber component, yet the translation kernel and the formalization use $\kappa_a$ for the component. Separately, $\sigma$ denotes both the radial symbol of $|k|^2$ and a per-axis separable factor, and the same factor is $g_a$ on one page and $\sigma_a$ on another. Both directions of the docs' own "one notation per concept, one concept per notation" rule are broken, in the one family where the two wavenumber conventions must be told apart.

**resolution_hint:** use $k_a$/$\tilde k_a$ for the two per-axis families, reserve $\kappa$ for shell magnitude, and pick one letter for separable factors.

---

## 8. Central versus raw second moment conflated: $C(0)$ called "the variance", `cov` called "the second moment"

- **type:** math — **severity:** minor — **confidence:** high

**Locations**

- PAGE: architecture, §13 decision 22 — *"The zero-separation value is $C(0) = \langle |f|^2\rangle = \texttt{inner}(f, f)$ (the variance)"*
- PAGE: Home, `Reductions` bullet — *"the covariance tensor `cov` (a vector field's second moment, kept coordinate-free)"*

**Contradicts**

- PAGE: formalization, §Reductions — *"$\operatorname{var}(f)\bigm|_{\texttt{corrected=false}} = \langle f, f\rangle - \langle f\rangle^2$"*
- PAGE: api / Reductions, `cov` — *"this is the covariance of the fluctuations, not the raw second moment $\langle u_i u_j\rangle$"*

**Description.** $C(0)=\langle|f|^2\rangle$ is the second moment; it equals the variance only for a mean-free field, and the same decision entry immediately invokes the zero-mean case for the large-$r$ limit — so the qualifier was available and not used. The Home page's "second moment" for `cov` is the mirror slip, contradicted explicitly by `cov`'s own docstring. Both matter because the package now ships `var` with the mean subtracted.

**resolution_hint:** "(the second moment; the variance when $f$ is mean-free)" and "second *central* moment" respectively.

---

## 9. Is `lpnorm(f̂, 2)` available in spectral representation? Two answers

- **type:** contradiction — **severity:** minor — **confidence:** medium

**Locations**

- PAGE: architecture, §13 decision 18 — *"The `lpnorm` reduction (for $p \ne 2$), `std`/`var`, and `maximum`/`minimum`/`extrema` … remain physical-only"*

**Contradicts**

- PAGE: api / Reductions, `lpnorm` — *"It is physical-space only."*
- PAGE: formalization, §Reductions — *"Physical fields and point-values only."*

**Description.** The parenthetical "(for $p\ne 2$)" scopes the restriction so that $p=2$ — which the docstring says "reduces to `l2norm`", itself Parseval-available in spectral — would be defined on a spectral field. The API and the formalization say `lpnorm` is physical-only without qualification. One of the two is wrong about the method set, which invariant 1 makes a specification question rather than a wording one. (The same sentence's "`std`/`var` … physical-only" is superseded by decision 49; the `lpnorm` clause is not superseded by anything.)

**resolution_hint:** settle whether the $p=2$ spectral method exists and make all three surfaces say so.

---

## 10. `convolve!`'s enumeration of "every kernel the package builds" omits `radial_kernel`

- **type:** clarity — **severity:** nit — **confidence:** high

**Locations**

- PAGE: api / Convolution, `convolve!`, reality admonition — *"Every kernel the package builds satisfies it: the real, even ones (`spectral_cutoff`, `spectral_band`, `assignment_window`) … and the complex `translation_kernel`"*

**Contradicts**

- PAGE: architecture, §11 — *"Five neutral builders ship … The first four are real and even in the wavenumber $k$"*

**Description.** Five builders ship; the reality admonition lists four. `radial_kernel` (and the lazy exponential kernel) are exactly the interesting cases for a Hermitian-safety claim, since they are the ones a consumer parameterizes — and `RadialKernel`'s own docstring gives the closure argument ($\sigma$ real of $|k|^2$ ⇒ real and even). Leaving them out of "every kernel the package builds" reads as a gap where the argument is in fact strongest.

**resolution_hint:** add `radial_kernel` to the real-and-even list and cross-link `RadialKernel`'s closure argument.

---

## 11. $\sum_k$ under a half-spectrum weight is not scoped to stored modes

- **type:** clarity — **severity:** nit — **confidence:** medium

**Locations**

- PAGE: api / Reductions, `weighted_inner` — *"$= \frac{1}{N^2} \sum_{k} \alpha(k) w(k) \sum_c \mathrm{Re}(\hat f_c \overline{\hat g_c})$"*
- PAGE: api / Reductions, `var` — *"$N^{-2}\sum_{k\ne 0} \alpha(k) |\hat f_k|^2$"*

**Description.** The multiplicity weight $\alpha(k)$ is only meaningful over the *stored* half-spectrum; read over the full mode set (which is how the notation page defines $\sum_k$: "over the Fourier modes") the sums double-count by roughly two. The neighbouring `inner` display and `DirectDFT` both write $\sum_{\text{stored }k}$ or spell the planes out explicitly, so the convention exists and is simply not applied here.

**resolution_hint:** write $\sum_{\text{stored }k}$ in both displays.

---

## Verified clean (spot-checked by expansion)

Forward-unnormalized / inverse-$1/N$ convention and its downstream $1/N$, $1/N^2$, $cN\delta_{k,0}$, $(|\Omega|/N)\hat f(0)$ factors; the $\mathrm{i}k$, $\mathrm{i}k\cdot$, $\mathrm{i}k\times$, $-|k|^2$, $-|k|^{-2}$ symbols and their signs; the Nyquist split and its two consumers; $\mathbb P = \mathrm{id}-(aa^\top)/(a\cdot a)$, its exact idempotency/solenoidality and the resolved-band composite; curl self-adjointness; $\hat S_{ij}=\tfrac{\mathrm i}{2}(k_j\hat u_i+k_i\hat u_j)$; the convolution theorem and its cell-volume bridge; the translation kernel's even/odd wavenumber split and $\cos(\pi h_a/\Delta x_a)$ Nyquist factor; $\hat W=\prod\operatorname{sinc}^2(k_a\Delta x_a/2)$ against the unit-integral tent; the exponential kernel as $e^{-c\Delta}$ with smoothing length $\sqrt{-2c}$; Parseval with $\alpha(k)$, $\sum_i P(\kappa_i)=\langle f,f\rangle$, $C(0)=\langle f,f\rangle$, $C_{fg}(-r)=C_{gf}(r)$; the $M/N$ transfer adjoint, conservation, $\iota_*=(N/M)W^\top$; `DirectDFT` type-1/type-2 and their adjointness; spline degrees, $C^m$, reproduction $\min(2m+1,2n)$ and the $n=0$ carve-out; the example's rotational-form RHS and integrating-factor Heun step.
