# 04 — differential-geometer (pure mathematician: bundles, measure, functional analysis)

Fresh-eyed audit of the rendered site's *intrinsic / structural* mathematics: base vs fiber,
vertical vs horizontal, section vs representation, domains and codomains, measures and adjoints.
Findings are collected only — nothing was edited.

---

## 1. The measure-weighted adjoint is derived from the wrong pairing (decision 19 / decision 17)

- **type:** math (measure/adjoint slip) · **severity:** major · **confidence:** high
- **locations:**
  - PAGE: architecture, §13 decision 19 (the measure taxonomy): *"The measure-weighted L² adjoint — $W$, $W^\top$ adjoint with the grid carrying $\Delta x^3$ and points counting — … it is $(N/M) W^\top$"*
  - PAGE: architecture, §13 decision 17: *"The L²/volume-weighted (measure-consistent) adjoint is $(N/M) W^\top$"*
  - PAGE: formalization, §Interpolation / anterpolation: *"The clean adjunction uses the measure-adjoint $\iota_* := (N/M) W^{\top}$"*, derived from $\langle f,g\rangle_{\text{grid}} = \frac1N\sum_n$, $\langle a,b\rangle_{\text{pts}} = \frac1M\sum_p$
- **contradicts:** formalization's derivation — axis: *which pair of measures produces the $N/M$ factor*.
- **description:** The $N/M$ factor comes from the two **normalized** (probability) pairings, $1/N$ on
  the grid and $1/M$ on the points, exactly as the formalization expands it. Under the pairing the
  decision-19 sentence names — grid carrying the cell volume $\Delta x^3$, points carrying counting —
  the adjoint of $W$ is $(1/\Delta x^3)W^\top = (N/\lvert\Omega\rvert)W^\top$, not $(N/M)W^\top$; the
  two agree only if $\lvert\Omega\rvert = M$. The rendered rationale therefore states a factor its own
  stated measures do not give.
- **resolution_hint:** say "with both bases carrying their normalized (total-mass-one) measures", or
  quote the $N/\lvert\Omega\rvert$ factor for the volume/counting pairing.

---

## 2. Does interpolation carry α/β, or only anterpolation?

- **type:** contradiction · **severity:** major · **confidence:** high
- **locations:**
  - PAGE: architecture, §10: *"Both carry the usual allocating / in-place (`!`) pair and a five-argument `α`/`β` form"*; and §13 decision 13: *"each with allocating, in-place, and α/β-accumulate forms"*
  - PAGE: api / Interpolation, module docstring: *"the $\alpha$/$\beta$ accumulation weights that only the scatter takes"*; and `interpolate!`'s signatures, which carry no `α`, `β`
- **contradicts:** the two sides disagree on the axis *which member of the adjoint pair takes the accumulation weights*, hence on how symmetric the pair is.
- **description:** §10 makes α/β a shared property of the pair and names the callable `f(x)` as the
  *only* asymmetry; the module docstring names two asymmetries (codomain, and α/β on the scatter
  alone) and the published `interpolate!` signature has no weights. One of the two is wrong about the
  operator surface. Structurally the docstring's version is the coherent one — accumulation belongs
  to whichever map writes into a preallocated section — but the design doc is what a reader trusts.
- **resolution_hint:** correct §10 and decision 13 to the shipped surface, keeping "symmetric named pair" but listing both asymmetries.

---

## 3. The domain of `inv` is stated two different ways

- **type:** contradiction · **severity:** major · **confidence:** high
- **locations:**
  - PAGE: api / Convolution, module docstring: *"the coefficientwise reciprocal of a kernel … (`inv`, defined for all four classes)"*
  - PAGE: formalization, §Convolution: *"The reciprocal `inv` … defined on a class where that is again closed — separable (per axis) and radial (in the symbol)"*
- **contradicts:** axis — *on which subtypes of `SpectralKernel` is `inv` defined* (four vs two).
- **description:** An operator's domain is exactly the kind of statement the formalization page exists
  to pin, and it names two classes while the module page names four. Both cannot be the operator's
  domain. (Decision 57 in the log also describes an `inv` on the stored class, which points at the
  formalization entry being the stale one.) A reader deriving what `ProductKernel` supports gets
  opposite answers from the two surfaces.

---

## 4. `SpectralKernel` is described as excluding its own stored subtype

- **type:** contradiction (category/taxonomy) · **severity:** major · **confidence:** high
- **locations:**
  - PAGE: api / Fields, module docstring: *"`SpectralKernel` is the supertype of every coefficientwise multiplier that is not stored as a field"*
  - PAGE: api / Convolution, module docstring: *"Every kernel subtypes `SpectralKernel`"*, and *"`StoredKernel` — one coefficient per mode … It wraps a `ScalarFieldSpectral`"*
- **contradicts:** axis — *the extension of the supertype*: does the stored (field-backed) class belong to it?
- **description:** `StoredKernel` **is** stored as a field of coefficients and **does** subtype
  `SpectralKernel`, so the Fields sentence excludes precisely the class decision 60 introduced to make
  the supertype total. This is the residue of the retired union (compressed-only abstract type + field),
  and it misdescribes the type's extension at the one place a reader meets it while reading `Fields`.

---

## 5. Architecture §12 is stale on which reductions are representation-invariant

- **type:** contradiction · **severity:** major · **confidence:** medium
- **locations:**
  - PAGE: architecture, §12: *"`mean`/`std`/`var` … are the moments — all on fields in physical representation and point-values"*, with only *"`inner`/`l2norm` … and `integral`/`mean`"* listed as also spectral
  - PAGE: api / Reductions, module docstring: *"`inner`/`l2norm` by Parseval's theorem, `integral`/`mean` from the zero (DC) Fourier mode, and the scalar-only `std`/`var` from Parseval"*
- **contradicts:** axis — *representation validity of `var`/`std`*; §12 also omits `cov` from the moment family entirely.
- **description:** Decision 49 gave `var`/`std` a Parseval form and added the covariance tensor `cov`
  as the coordinate-free vector second moment. The body section that owns the reduction family still
  reads as before: it implies `var`/`std` are physical-only and never names `cov`. Since §12 is the
  current-state description (not the append-only log), it now contradicts the module docstring on a
  validity claim — the class of statement invariant 1 says is the spec.

---

## 6. The formalization page uses $W$ for two different objects

- **type:** typesetting/notation (one glyph, two meanings) · **severity:** major · **confidence:** high
- **locations:**
  - PAGE: formalization, §Fiberwise algebra (map!/map): *"$\varphi : V_1 \times \dots \times V_m \to W$ … The output fiber space $W$"*
  - PAGE: formalization, §Reductions (mapped forms): *"($W$ on this page is the gather operator, so the generic codomain takes another letter)"*
  - PAGE: formalization, §Interpolation: *"$W := W_b \otimes \mathrm{id}_V : \Gamma_G \to \Gamma_P$"*
- **contradicts:** the page's own explicit reservation of $W$ — axis: *what the glyph $W$ denotes*.
- **description:** The Reductions entry goes out of its way to avoid $W$ for a map's codomain because
  $W$ is the gather; the `map!` entry, on the same page, uses $W$ for exactly that — a fiber vector
  space — while $W$ elsewhere is an operator $\Gamma_G \to \Gamma_P$. A space and a map between
  section spaces sharing a glyph on the page whose purpose is typed precision is the failure the
  Reductions parenthetical already diagnosed.
- **resolution_hint:** use $U$ (or $V_{\text{out}}$) in the `map!` entry, matching the Reductions entry.

---

## 7. `radial_kernel` described as a coordinate rather than as a builder taking a symbol

- **type:** contradiction (operator conflated with its parameter) · **severity:** major · **confidence:** high
- **locations:**
  - PAGE: formalization, §Convolution: *"`radial_kernel` the $|k|^2$ coordinate consumers build symbols from"*
  - PAGE: api / Convolution: *"`radial_kernel` — build a `RadialKernel` from any real function $\sigma$ of the squared wavenumber"*; PAGE: Home: *"`radial_kernel` builds a kernel from any symbol of $|k|^2$"*
- **contradicts:** axis — *what the object is*: the radial coordinate $|k|^2$, or the map $\sigma \mapsto \hat g = \sigma(|k|^2)$.
- **description:** The formalization sentence is the removed `squared_wavenumber_field`'s description
  transplanted onto its replacement, so the builder is identified with its argument's argument. The
  same page's own kernel-class list gets it right (*"radial … held as the real symbol $\sigma$"*), and
  the weighted-inner docstring shows the honest spelling `radial_kernel(identity, …)` — i.e. the
  coordinate is the value at $\sigma = \mathrm{id}$, not the builder.

---

## 8. $f(x) = \langle \delta_x, f\rangle$ uses the package's *normalized* bracket

- **type:** math (normalization / notation collision) · **severity:** minor · **confidence:** medium
- **locations:**
  - PAGE: architecture, §2: *"evaluation — pairing with a Dirac mass $\delta_x$ — $f(x) = \langle \delta_x, f\rangle$"* (repeated in §10)
  - PAGE: notation, Operators table: *"$\langle\cdot,\cdot\rangle$ | the normalized $L^2$ inner product | inner"*; PAGE: formalization: $\langle f,g\rangle_{\text{grid}} := \frac1N\sum_n f_n\cdot g_n$
- **contradicts:** axis — *the meaning of the bracket*: distributional duality pairing vs the $1/N$-normalized inner product.
- **description:** The glyph is declared package-wide as the normalized inner; read that way the
  identity would give $f(x)/N$, not $f(x)$. The intended object is the duality pairing between a
  measure and a continuous function, which carries no $1/N$. Since the whole $N/M$ story of §10 turns
  on which normalization each pairing has, using the same brackets for the unnormalized duality is
  exactly where a reader loses track of the factor.
- **resolution_hint:** write $\delta_x(f)$, or $\langle\cdot,\cdot\rangle_{\text{duality}}$ with one clause saying it is unnormalized.

---

## 9. The pushforward $\iota_*$ is a measure but is equated with a grid section

- **type:** math (category/type conflation) · **severity:** minor · **confidence:** medium
- **locations:**
  - PAGE: architecture, §10: *"anterpolation the pushforward of the dual measure, $\iota_{*}$ ($\iota_{*} q = \sum_p q_p \delta_{x_p}$ …) — for the uniform measures $\iota_{*} = (N/M) W^{\top}$"*
- **description:** $\sum_p q_p\delta_{x_p}$ is a ($V$-valued) measure on the torus; $(N/M)W^\top q$ is
  an element of $\Gamma_G$, a section. The identification silently performs two steps — regularization
  by the stencil, then taking the density with respect to the (normalized) grid measure — and neither
  is named, so a map into measures and a map into sections wear one symbol. The phrase "the dual
  measure" also leaves unsaid *dual to what*. The formalization page states the honest version
  ($\iota_* := (N/M)W^\top$, an operator $\Gamma_P \to \Gamma_G$) without reconciling it with §10's
  measure-valued definition.
- **resolution_hint:** one clause: "regularized and read as a density against the grid's measure, $\iota_*$ is realized on sections as $(N/M)W^\top$".

---

## 10. Is the base the grid's nodes or its cells?

- **type:** normalization/terminology (base object vs measure element) · **severity:** minor · **confidence:** high
- **locations:**
  - PAGE: formalization, Declarations: *"grid sections, $N = N_x N_y N_z$ cells"*; PAGE: api / Reductions (`integral`): *"where $N$ is the number of grid cells"*
  - PAGE: api / FieldAlgebra: *"the base — the set of locations the field attaches a value to, which for a field is the grid's cells"*
  - PAGE: api / Fields (`Grid3D`): *"`grid_size`: the number of grid points in each spatial direction"*; PAGE: notation: *"$N$ | the grid-point count"*; PAGE: api / Interpolation: *"over the $N$ grid nodes"*
- **contradicts:** axis — *what the $N$ base elements are*: nodes (where values live) or cells (the quadrature volumes).
- **description:** The base of a field section is the set of **nodes**; a "cell" is the volume element
  the quadrature measure attaches to a node. The docs use cells, points, and nodes interchangeably for
  the same index set, including inside one page. It is numerically harmless on a uniform torus but it
  blurs precisely the base/measure distinction the measure taxonomy (decision 19) exists to keep, and
  it makes "fiber value at each cell" read as a finite-volume rather than a collocation object.
- **resolution_hint:** fix one word — nodes/grid points for the base, "cell volume" only for the measure — and sweep the class.

---

## 11. Two incompatible reasons for refusing a separable weight in `weighted_inner`

- **type:** method (justification) · **severity:** minor · **confidence:** medium
- **locations:**
  - PAGE: api / Reductions (`weighted_inner`): *"a separable kernel is deliberately not accepted, its factors not being real in general"*
  - PAGE: architecture, §13 decision 51: *"`weighted_inner` accepts a radial kernel as a weight and deliberately not a separable one — a magnitude-dependent weight does not factor per axis, so it is not in that family"*
- **contradicts:** axis — *why the separable class is excluded*.
- **description:** The docstring's reason is a genuine validity statement (the pairing needs a real
  multiplier; separable factors are complex in general, e.g. the translation phase). The decision-log
  reason argues the converse direction — that a radial weight is not separable — which is no reason to
  refuse a separable one, and would equally "prove" that the radial class is out of the separable
  family rather than that the separable class is invalid here. A deliberate absence is a mathematical
  statement (invariant 1), so its stated ground should be the one that holds.

---

## 12. The spectral representation is never given a space, so $\mathcal F$ has no declared codomain

- **type:** math (domain/codomain left unchecked) · **severity:** minor · **confidence:** medium
- **locations:**
  - PAGE: formalization, Declarations: only $V$, $\Gamma_G$, $\Gamma_P$ are declared; then *"The transform $\mathcal F$ … is the rfft isomorphism between the physical (nodal) and spectral representations of a grid section"*
  - PAGE: architecture, §2: *"the rfft is the linear isomorphism between them"*
- **description:** Every other object on the page is given a space; the spectral side is not. As a map
  into the stored complex array, $\mathcal F$ is **not** onto: the stored half-spectrum has strictly
  more real dimensions than $\Gamma_G$, and the image is the Hermitian-constrained subspace (the
  $k$-plane self-conjugacy the page itself notes). That constraint is exactly what the Parseval weight
  $\alpha(k)$ and the reality condition on kernels encode, so declaring
  $\hat\Gamma_G := \{\hat f \in \mathbb C^{K}\otimes V : \hat f(-k) = \overline{\hat f(k)}\}$ would make
  three later statements (Parseval, Hermitian kernels, `var` from modes $k\ne0$) type-check rather than
  read as conventions.

---

## 13. The formalization reserves $k$ for the wavenumber, then sums over it as a fiber index

- **type:** typesetting (notation collision) · **severity:** nit · **confidence:** high
- **locations:**
  - PAGE: formalization, Declarations: *"(the letter $k$ is reserved for the wavenumber below)"*
  - PAGE: formalization, §Fiberwise algebra: *"$(u\times v)_i = \varepsilon_{ijk} u_j v_k$"*, *"$(AB)_{ij} = A_{ik}B_{kj}$"*
- **description:** The page states an unconditional reservation and breaks it two sections later. The
  Notation page carries the reconciliation (*"As an index, $k$ occurs only in component subscripts …
  the standalone $k$ … is always the wavenumber"*), so the fix is to import that clause rather than to
  claim a reservation the page does not keep.

---

## 14. "inner products" listed as physical-space-only among the nonlinear contractions

- **type:** clarity (name collision with a spectral-valid reduction) · **severity:** nit · **confidence:** medium
- **locations:**
  - PAGE: architecture, §2 (Representation validity): *"Nonlinear in the field — products of two fields, division by a scalar field, pointwise norms, contractions of two fields (dot, cross, tensor `mul!`, inner products): physical space only."*
  - PAGE: api / Reductions (`inner`): *"For two fields in spectral representation `inner` returns the same value by Parseval's theorem with no inverse transform"*
- **description:** The intended referent is the fiberwise tensor inner product `dot!`, but the exported
  reduction is literally named `inner` and is valid in spectral representation — so the validity
  table's phrase reads as forbidding what the reductions page provides. The distinction is real
  (fiberwise contraction returns a section, the L² pairing returns a number), which is why naming it
  matters here.

---

## 15. "fiber order" vs "tensor order"

- **type:** normalization (vocabulary) · **severity:** nit · **confidence:** medium
- **locations:**
  - PAGE: api / Reductions (`inner`): *"two compatible sections of equal fiber order"*
  - PAGE: api / FiberSections (`AbstractFiberSection`): *"`R` is the tensor order"*
- **description:** One integer parameter, two names. Since a nearby documented defect class is exactly
  "a vector space equated with an integer" (the fiber $V$ vs the order $R$), the package is better
  served by using *tensor order* uniformly for $R$ and reserving *fiber* for the space $V$.
