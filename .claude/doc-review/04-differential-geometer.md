# Hat: differential-geometer (pure mathematician — bundles, measure, functional analysis)

Audit of the rendered site's *intrinsic / structural* mathematics: base vs fiber, vertical vs
horizontal, section vs representation, domains and codomains, measure taxonomy, adjoint and
projection claims. 17 findings, most severe first.

---

## 1. Decision 49's Parseval variance identity drops the `1/N²` and the multiplicity `α(k)`

- **type:** math · **severity:** major · **confidence:** high
- **locations:**
  - PAGE: architecture, §13 decision 49 — "$\operatorname{var}(f) = \langle f, f\rangle - \langle f\rangle^2 = \sum_{k \ne 0} |\hat f_k|^2$"
  - PAGE: formalization, "Variance, standard deviation, and covariance" — "$= \frac{1}{N^2}\sum_{k\ne 0} \alpha(k) |\hat f(k)|^2$"
  - PAGE: api / Reductions, `var` — "$\langle f, f\rangle - \langle f\rangle^2 = N^{-2}\sum_{k\ne 0} \alpha(k) |\hat f_k|^2$"
- **contradicts:** formalization + the `var` docstring, on the axis of *normalization*.
- **description:** The decision-log form is a false equality under either reading of the sum: over
  the stored half-spectrum it needs the multiplicity $\alpha(k)$, and under any reading it needs
  $1/N^2$ (the unnormalized-forward convention, invariant 4). The two correct copies agree with each
  other, so the log entry is the outlier. A reader who takes §13 as self-contained — which the
  architecture header promises — gets a variance wrong by $N^2$.
- **resolution_hint:** copy the formalization's displayed form verbatim into decision 49.

## 2. `weighted_inner` refuses two of the four kernel classes, while `Convolution` says all four are interchangeable — and the stated reason argues the wrong way

- **type:** contradiction · **severity:** major · **confidence:** high
- **locations:**
  - PAGE: api / Convolution, module — "the four classes reach every kernel-taking entry point interchangeably"
  - PAGE: api / Reductions, `weighted_inner` — "a separable kernel is deliberately not accepted"
  - PAGE: architecture, §13 decision 51 — "deliberately not a separable one — a magnitude-dependent weight does not factor per axis"
  - PAGE: testing, §4 axes — "`StoredKernel`, `SeparableKernel`, `RadialKernel` and the cross-family `ProductKernel` must agree bitwise"
- **contradicts:** the Convolution module claim and the testing coverage axis, on the axis of *which
  kernel classes an entry point admits*.
- **description:** Two defects in one place. The blanket "interchangeable at every entry point" is
  false: `weighted_inner`'s own signature is `Union{StoredKernel, RadialKernel}`. And the
  justification is a non-sequitur — it explains why a *radial* symbol is not separable (a fact about
  the accepted class), not why a separable real symbol $\prod_a g_a(k_a)$ is an inadmissible weight.
  A separable real $w$ gives a perfectly well-defined $\langle f, wg\rangle$, so the absence is
  *scoping*, not validity — the very mislabelling decision 49 confesses to for `var`/`std` ("physical-only
  by scoping, not validity"). Citing invariant 1 for it overstates it.
- **resolution_hint:** qualify the module sentence, and restate the exclusion as a scoping choice
  (no consumer) rather than a structural/validity one.

## 3. §2 says the transfer weights *are* a unit-mass kernel measure; the Interpolation page excludes the spectral schemes — and that exclusion looks wrong for `DirectDFT`

- **type:** contradiction · **severity:** major · **confidence:** medium
- **locations:**
  - PAGE: architecture, §2 — "the interpolation weights are themselves a unit-mass kernel measure (signed for the higher-order schemes)"
  - PAGE: api / Interpolation, module — "the spectral schemes are exact adjoints without being partitions of unity"
  - PAGE: architecture, §13 decision 19 — "The gather weights … are a discrete grid measure of total mass 1 (partition of unity)"
- **contradicts:** the Interpolation module docstring, on the axis of *which schemes carry unit
  kernel mass / conservation*.
- **description:** §2 and decision 19 state unit mass for the transfer kernel as such; the module
  docstring carves the spectral family out. Both cannot stand. Worse, the carve-out is doubtful for
  `DirectDFT`: it "reproduces the band-limited field exactly", a constant is band-limited, so its
  equivalent nodal weights sum to one; and its type-1 zero mode is exactly $\sum_p q_p$, which *is*
  the conservation statement. Only `NUFFT` (tolerance) genuinely falls short.
- **resolution_hint:** scope §2 to the kernel families that are partitions of unity, and re-derive
  the `DirectDFT` case before excluding it.

## 4. `DirectDFT`'s spectral `anterpolate` can land outside the Hermitian subspace the formalization declares as the codomain

- **type:** method · **severity:** major · **confidence:** medium
- **locations:**
  - PAGE: formalization, Representations — "The image is the Hermitian-constrained subspace"
  - PAGE: formalization, Spectral transfer — "$(W^{\top}q)(k) = \sum_p q_p e^{-\mathrm{i} k\cdot(x_p-o)}$"
  - PAGE: architecture, §13 decision 23 — "`DirectDFT` (no oversampling) carries the Nyquist exactly"
- **description:** On an even folded axis the rfft identifies the Nyquist mode with its own negative
  ($-N/2 \equiv N/2$), so a real field's coefficients must satisfy
  $\hat g(N/2,-k_2,-k_3) = \overline{\hat g(N/2,k_2,k_3)}$. The type-1 sum satisfies this only when
  every $x_{p,1}$ is a grid node; off-grid it does not. The deposited object is then no real field's
  half-spectrum — exactly the hazard decision 28 documents for `translation_kernel` and decision 23
  fixes for `NUFFT` by projecting the Nyquist out. `DirectDFT` is left with the claim of exactness
  and no caveat.
- **resolution_hint:** state the Nyquist reality caveat on `DirectDFT`'s anterpolate, or document
  the projection if the code already applies one.

## 5. `FieldAlgebra` claims pointwise-over-the-base is what makes the surface representation-agnostic — then contradicts itself

- **type:** contradiction · **severity:** major · **confidence:** high
- **locations:**
  - PAGE: api / FieldAlgebra, module — "That is what makes the whole surface representation-agnostic"
  - PAGE: api / FieldAlgebra, module — "not linear in a field argument … is defined only in physical-space representation"
  - PAGE: architecture, §2 — "an operation exists in a representation only when … it commutes with the rfft isomorphism"
- **contradicts:** the same docstring two paragraphs later, and §2's validity rule, on the axis of
  *what licenses an operation in both representations*.
- **description:** Acting pointwise in the base is neither necessary nor sufficient for commuting
  with $\mathcal F$: `det` and `norm` are pointwise and emphatically not representation-agnostic,
  which the module itself says next. The property that transfers is *linearity in the field*. As
  written this is a category slip — locality in the base substituted for equivariance under the
  transform — on the module's own summary line.
- **resolution_hint:** "…which is why the *linear* operations here are representation-preserving."

## 6. The tutorial equates the fiber with the tensor order — the exact category error the formalization page names as its motivating defect

- **type:** other · **severity:** major · **confidence:** high
- **locations:**
  - PAGE: tutorial, "Grids and fields" — "The fiber (tensor order) is set by the constructor"
  - PAGE: architecture, §2 — "The fiber is a tensor power of $\mathbb R^3$, fixed by the tensor order $R$"
  - PAGE: formalization, preamble — "a vector space equated with an integer"
- **contradicts:** architecture §2, on the axis of *fiber (a vector space) vs tensor order (an
  integer parameter)*.
- **description:** The apposition "the fiber (tensor order)" identifies $V$ with $R$. §2 gets it
  right — $V$ is *fixed by* $R$ — and the formalization page cites precisely this conflation as the
  defect its typed statements exist to catch. It sits on the first page a user reads, which is where
  the vocabulary is learned.
- **resolution_hint:** "The tensor order — and with it the fiber — is set by the constructor."

## 7. "Fiber-preserving" carries three different meanings across the site

- **type:** normalization · **severity:** minor · **confidence:** high
- **locations:**
  - PAGE: architecture, §2 — "the fiberwise algebra is order-zero and fiber-preserving"
  - PAGE: formalization, Interpolation — "Both transfer maps are fiber-preserving (the trivial bundle leaves the fiber by the identity)"
  - PAGE: api / Reductions, `integral` — "The result is fiber-preserving: a scalar for a scalar section"
- **contradicts:** itself across pages, on the axis of *what "fiber-preserving" preserves*.
- **description:** Sense (b) and (c) mean "identity on $V$"; sense (a) can only mean "covers
  $\mathrm{id}_B$", since `dot`, `norm`, `det` and `map!` all change $V$ ($\mathbb R^{3\times3}\to\mathbb R$).
  Under the (b)/(c) reading, §2's sentence is simply false for most of the algebra it describes. The
  tutorial says the right thing for the same operations — "preserves the base" — which is the
  formulation to standardize on.
- **resolution_hint:** reserve "fiber-preserving" for $\otimes\,\mathrm{id}_V$; say "base-preserving"
  or "vertical" in §2.

## 8. §10 calls the point base's elements "particles", against the document's own invariant 12

- **type:** language-tone · **severity:** minor · **confidence:** high
- **locations:**
  - PAGE: architecture, §10 — "a plain sum over the $M$ particles"
  - PAGE: architecture, §10 — "each normalized by its total measure — the $M$ particles"
  - PAGE: architecture, §2 invariants — "The terminology stays domain-neutral (base and fiber, point and value)"
- **contradicts:** invariant 12 as stated in §2 and re-argued in §10 ("'particle'/'tracer' is the
  consumer's interpretation … not a primitive here"), on the axis of *vocabulary*.
- **description:** Two occurrences in the very section that defends the domain-neutral naming. The
  base elements are points; the count is $M$ points.

## 9. §10's prose gloss of the two pairings drops the normalization its own formulas carry

- **type:** math · **severity:** minor · **confidence:** high
- **locations:**
  - PAGE: architecture, §10 — "the counting measure makes $\langle\cdot,\cdot\rangle_{\mathrm{pts}}$ a plain sum"
  - PAGE: architecture, §10 — "$\langle a, b\rangle_{\mathrm{pts}} := \frac{1}{M}\sum_p a_p\cdot b_p$"
- **contradicts:** the display two lines below it, on the axis of *normalized vs extensive measure*.
- **description:** The gloss says "plain sum" (counting) and "a volume integral over the box"
  (Lebesgue) where both displayed pairings are normalized by total measure ($1/M$, $1/|\Omega|$).
  Since the whole $N/M$ discussion that follows turns on exactly that normalization, the loose gloss
  undercuts the paragraph it introduces.

## 10. The formalization's $\mathbb P$ multiplier states no convention at $a\cdot a = 0$, though $\Delta^{-1}$ beside it does

- **type:** math · **severity:** minor · **confidence:** high
- **locations:**
  - PAGE: formalization, Differential operators — "$\Delta^{-1} \to -|k|^{-2}\ (0\text{ at }k=0)$, $\mathbb P \to \mathrm{id} - \frac{a a^{\top}}{a \cdot a}$"
  - PAGE: api / DifferentialOperators, `helmholtz_projection!` — "passes every mode with $a = 0$ unchanged … $a \ne 0$"
- **description:** The expression is undefined at the zero mode and at the pure-Nyquist corners where
  the whole derivative wavenumber vanishes — a nonempty set on any even grid. The API docstring
  supplies the convention; the page whose stated job is to give every operator an honest domain does
  not, while declaring the neighbouring $\Delta^{-1}$'s. (The identities $\mathbb P^2 = \mathbb P$,
  $\nabla\cdot(\mathbb P u)=0$ do hold with the identity convention — this is about the statement,
  not the operator.)

## 11. "Three structures … are parameters of a section" is followed by five bullets, three of them operation families

- **type:** organization · **severity:** minor · **confidence:** high
- **locations:**
  - PAGE: architecture, §2 — "Three structures of the package are then parameters of a section, not separate worlds:"
  - PAGE: architecture, §2 — "Fiberwise algebra is the vertical (within-fiber) structure"
- **description:** The list runs base, vertical algebra, differential operators, base reductions,
  representation. Base and representation (and, implicitly, tensor order) are parameters of a
  section; an operation family is not — it is a map *on* sections. Both the count and the category
  drifted, in the paragraph that sets up the whole conceptual model.

## 12. `cov` is the second *central* moment on two pages and the plain "second moment" on two others

- **type:** contradiction · **severity:** minor · **confidence:** high
- **locations:**
  - PAGE: api / Reductions, `cov` — "the covariance of the fluctuations, not the raw second moment $\langle u_i u_j\rangle$"
  - PAGE: architecture, §12 — "`cov` returns the vector second moment as a symmetric $\mathrm{Sym}^2(V)$ tensor"
  - PAGE: Home — "the covariance tensor `cov` (a vector field's second moment, kept coordinate-free)"
- **contradicts:** the `cov` docstring, on the axis of *central vs raw second moment*.
- **description:** $\langle u\otimes u\rangle$ and $\langle u'\otimes u'\rangle$ differ by
  $\bar u\otimes\bar u$ and coincide only for a mean-free field — not a safe assumption for a
  general vector section. The formalization gets it right ("second central moment"); the two summary
  surfaces do not.

## 13. The divergence/gradient adjointness has no typed entry, though it is cited as a pinned structural identity

- **type:** citation · **severity:** minor · **confidence:** medium
- **locations:**
  - PAGE: testing, §1 — "the adjoint relations (divergence as the negative gradient adjoint, self-adjoint curl…)"
  - PAGE: architecture, §13 — "$\nabla\cdot = -\nabla^\top$"
  - PAGE: formalization, preamble — "a statement here with no test is a coverage gap to close"
- **description:** The formalization types $\mathbb P^2=\mathbb P$, $\nabla\cdot\nabla\times=0$,
  $\nabla\times\nabla=0$, curl self-adjointness, $\Delta$ self-adjointness and the dissipation
  identity — but not $\langle\nabla\varphi,u\rangle = -\langle\varphi,\nabla\cdot u\rangle$, which is
  the one relation *between different fiber orders* (scalar and vector sections) and therefore the
  one whose spaces most need naming. By the page's own gap rule, a missing entry is the defect.

## 14. $N$ is "grid cells" in the reductions and "grid points" in the glossary

- **type:** normalization · **severity:** nit · **confidence:** high
- **locations:**
  - PAGE: notation — "$N$ | the grid-point count $\prod_i N_i$ | prod(grid_size)"
  - PAGE: api / Reductions, `integral` — "where $N$ is the number of grid cells"
  - PAGE: formalization, Declarations — "$N = N_x N_y N_z$ cells"
- **description:** A node and a cell are different objects (a node carries no volume), and the whole
  quadrature story is "each node carries the volume of its cell". On a uniform periodic grid the
  counts coincide, so nothing is numerically wrong — but the identification is never stated, and the
  two words alternate freely for one symbol.

## 15. "A section lives in $L^2(\mathrm{base}, \mu)$" flattens the fiber away

- **type:** math · **severity:** nit · **confidence:** medium
- **locations:**
  - PAGE: architecture, §13 decision 18 — "a section lives in $L^2(\mathrm{base}, \mu)$"
  - PAGE: formalization, preamble — "a section space written $\mathbb R^N$ that had quietly flattened the fiber away"
- **description:** The correct space is $L^2(\mathrm{base},\mu; V)$ (equivalently
  $L^2(\mathrm{base},\mu)\otimes V$). The formalization names this exact omission as the class of
  slip it exists to catch, and §12/`Reductions` elsewhere is careful that a reduction returns a
  *fiber*, which only makes sense if $V$ is in the space.

## 16. "Rank 2 / rank 4" for tensor order, and "which the package does not carry" against `FiberTensor4`

- **type:** other · **severity:** nit · **confidence:** medium
- **locations:**
  - PAGE: architecture, §13 decision 49 — "a vector's covariance is rank 2, a tensor's rank 4, which the package does not carry"
  - PAGE: api / FiberSections — "`FiberTensor4{T}` … alias for `SArray{Tuple{3,3,3,3}, T, 4, 81}`"
- **description:** The site's term everywhere else is *tensor order* $R$; "rank" additionally
  collides with matrix rank, live here since `cov` returns a rank-deficient-able $\mathrm{Sym}^2$
  tensor. And the fiber type of order 4 does exist — what is absent is a *section* of order 4 (the
  documented $R < 3$ ceiling), which is the honest way to say it.

## 17. `curl` described as "the local rotation rate"

- **type:** math · **severity:** nit · **confidence:** medium
- **locations:**
  - PAGE: api / DifferentialOperators, module — "`curl` $\equiv \nabla\times$ returns the local rotation rate of a vector field"
- **description:** $\nabla\times u$ is *twice* the local angular velocity of a fluid element
  ($\omega = 2\Omega$); the rotation rate is $\tfrac12\nabla\times u$, and the antisymmetric part of
  $\nabla u$ that the module elsewhere pairs `curl` with carries the factor. Since the neighbouring
  `symmetric_gradient` bullet is exact about its $\tfrac12$, the looseness stands out.
