!!! info "Written by AI, not regularly reviewed"
    This page is written by AI and is not reviewed regularly by a human.

# Architecture — GBGPeriodicFields

This document records the architecture of the package and, more importantly, *why*
it is the way it is. It exists so that future work (human or AI) extends the design
instead of accidentally reverting it. `CLAUDE.md` carries the operational summary;
this file carries the reasoning — and, since the umbrella module's AI-tips block was merged in, the
conceptual model (§2) and the writing/docstring conventions (the §2 documentation policy) as well.

This file is **self-contained**: every piece of notation — a mathematical symbol (in LaTeX) or a
`code` identifier — is introduced in plain language at its first use, the meaning stated before or in
the same sentence as the symbol. So it reads top-to-bottom, and each entry of the [decision log](@ref "Decision log — GBGPeriodicFields") reads on
its own, without opening the source or another document. (Universally standard math — ``\nabla``,
``\Delta``, ``\int``, ``\mathbb R`` — may stand unglossed.) Keep it that way when editing.

## 1. Purpose and scope

The package is the field layer for pseudospectral simulation of incompressible
fluid dynamics and turbulence on three-dimensional rectangular periodic domains. Its
primary consumer is [`GBGHomogeneousTurbulence.jl`](https://grigorysarnitsky.github.io/GBGHomogeneousTurbulence.jl), a direct numerical simulation of
homogeneous isotropic turbulence built on it; the operation families below were shaped by
what that solver needs, which is why a proposed addition without a consumer is deferred
rather than built. It
provides scalar, vector, and second-order tensor fields with two storage
representations — physical and spectral (the spectral one stored non-redundantly as the
real-to-complex / `rfft` half-spectrum) — plus
FFT transform plans, spectral multipliers, storage-wise broadcasting, fiberwise
algebra (`FieldAlgebra`), differential operators applied as spectral multipliers
(`DifferentialOperators`), periodic
convolution (`Convolution`), and the L²/measure reductions (`Reductions`).
Interpolation and its adjoint anterpolation — the grid↔point transfer layer that
serves consumer-side Lagrangian particle tracking — are in place ([§10](@ref "10. Interpolation and anterpolation (the grid↔point transfer layer)")): the point-value
sections, their fiberwise algebra, and the transfer **schemes** — local splines (Lalescu, Teaca &
Carati 2010: the smooth Hermite and ``C^0`` Lagrange hierarchies) and exact spectral-domain transfers
(`DirectDFT`, `NUFFT`), unified under one `AbstractTransferScheme`. The
same code must run
on CPU `Array`s and on GPU arrays (CUDA `CuArray`, AMDGPU `ROCArray`); development
prioritizes GPU correctness and performance first. The target is a **single node** with
**shared-memory parallelism only** — CPU multithreading ([§9](@ref "9. Performance model and CPU threading"))
and a **single GPU** device. Distributed-memory / multi-node execution (a cluster, MPI) and multi-GPU
sharding are deliberately **out of scope** — a consumer's concern if ever needed, not this field layer's
(every field is one host or device array, allocated via `similar`).

The package is a **math backend** — a library of field operations that turbulence and cloud
solvers consume, not a solver itself. Its vocabulary is therefore domain-neutral (base/fiber,
point/value), never *particle* or *tracer* (a consumer's interpretation), and it carries **no
concept of time**: no advection, time integration, or temporal state. Trajectory dynamics
belong to the consumer ([§10](@ref "10. Interpolation and anterpolation (the grid↔point transfer layer)")).

## 2. The central principle: the architecture follows established mathematics

Every abstraction in this package is the code image of a standard mathematical
object, and design decisions are settled by that mathematics rather than by
implementation convenience. The primary source is **differential geometry — the
language of fiber bundles and their sections**; the working rule is that a proposed
abstraction must first be identifiable as a known mathematical object (or a faithful
discretization of one) before it earns a place in the design. "For completeness" or
"it would be convenient" is never a justification — indeed the recurring lesson
below is that the *absence* of an operation is itself a precise mathematical
statement.

### The fiber-bundle model

A field, and a collection of values sampled at scattered locations, are both
**sections of a tensor bundle over a base**. The domain is a flat periodic box (a
3-torus) with a single global frame, so the bundle is trivial — just the product ``E = B \times V``
of a base ``B`` and a fiber ``V``. **The word "base" carries two related meanings here, and they are
worth separating once.** The *continuum* base is the torus ``\Omega`` itself. The bundle is
drawn over **both**: the trivial product exists over ``\Omega`` and over each discrete base alike, and
§10's pullback ``\iota`` is exactly what relates them. The *discrete* base is the finite set a section is
actually stored on — a `Grid3D` of nodes or a `PointSet` of scattered locations, each a finite subset
of ``\Omega`` — and it is the one meant wherever the docs say a section is "over a base" or a
reduction "integrates the base away". Neither reading is dispensable: the continuum carries the
derivative and the measure, the discrete set carries the data. The fiber is a tensor power of ``\mathbb R^3``, fixed by the
**tensor order** ``R``: ``V = \mathbb R`` (``R = 0``, scalar), ``\mathbb R^3`` (``R = 1``, vector, `FiberVector`),
``\mathbb R^3 \otimes \mathbb R^3 = \mathbb R^{3\times 3}`` (``R = 2``, second-order tensor, `FiberTensor2`),
and higher (`FiberTensor3/4`).

That single global frame is what lets a derivative index be stored as a fiber index: ``\nabla`` maps a
section of ``E`` to a section of ``E \otimes T^{*}\Omega``, and the frame identifies ``T\Omega`` —
and, being orthonormal, ``T^{*}\Omega`` with it — with the GENERATING space ``\mathbb R^3``, the
``R = 1`` fiber. It is not identified with ``V``, which has rank ``3^R`` and matches ``T\Omega``
only at ``R = 1``. So ``E \otimes T^{*}\Omega`` has fiber ``V \otimes \mathbb R^3 =
(\mathbb R^3)^{\otimes (R+1)}`` and the package can type ``\nabla u`` as a fiber tensor of one
order higher with no raising or lowering to track. The derivative factor comes LAST because that is
its slot: ``(\nabla u)_{ij} = \partial_{x_j} u_i``, and the divergence contracts it. That single global frame is **orthonormal**, so the fiber carries the ordinary Cartesian Euclidean
structure: components are referred to one fixed rectangular frame, indices are neither raised nor
lowered, and there is no metric to carry because it is the identity. This is what makes the bundle
trivial and flat rather than merely *modelled* as such, and it is why the bundle vocabulary here
organizes the code without promising machinery on manifolds — the tensors are Cartesian tensors in the
classical continuum-mechanics sense. **Do not introduce curvilinear-coordinate machinery, explicit
metric tensors, or a vector/covector distinction** unless the package design changes to need them: each
would make the frame a variable the whole operation set has to carry, and none has a consumer. A
section
assigns a fiber value to each base point; the fiber-last data layout ([§3](@ref "3. Types and memory layout")) is exactly
that section, stored base-indexed.

The package's structures then organize around that one object, rather than standing as separate
worlds. Two of them are *parameters* of a section — what a section is built from — and three are
*operation families*, maps acting on sections, each reaching only as far as the structure it needs:

- **The base** is either the structured grid `Grid3D` — a field is a section sampled
  on the grid — or the unstructured point set `PointSet` — point-values are a section
  sampled at scattered points ([§10](@ref "10. Interpolation and anterpolation (the grid↔point transfer layer)")). Same fibers, different base.
- **Fiberwise algebra is the vertical (within-fiber) structure**: addition, real
  scaling, contraction with a constant fiber, dot/cross/tensor products, transpose,
  sym/skew/dev, norms, and an arbitrary fiber map (`map!`, the escape hatch) all act inside fibers, pointwise in the base, and are
  therefore **base-independent** — the very same operation on the very same fiber
  type, whether the base is a grid or a point set. This is the structural reason one
  set of generated kernels ([§6](@ref "6. The code-generation architecture of `FieldAlgebra`")) serves fields and point-values verbatim, and the
  mathematical motivation for treating the **section as the primary abstraction**: a
  shared `AbstractFiberSection{T, R}` supertype spanning both, in the
  `FiberSections` module ([§10](@ref "10. Interpolation and anterpolation (the grid↔point transfer layer)")).
- **Differential operators are the complementary horizontal structure** — gradient,
  divergence, curl, Laplacian are derivatives *along the base*, using the periodic box's
  flat *connection* — its one fixed frame, which lets vectors over different base points be
  compared directly ([§4](@ref "4. Spectral machinery")). Read that
  precisely, since a `Grid3D` is a finite set and has no tangent bundle of its own: the
  derivative lives on the **continuum** torus, and a grid section reaches it by standing
  for the trigonometric polynomial its coefficients define, of which each operator is the
  exact term-by-term derivative on the resolved band (the even-axis Nyquist term is zeroed, invariant 5).
What distinguishes the two bases is therefore whether
  such an identification exists — a uniform periodic grid determines that polynomial, so
  it inherits the derivative; a `PointSet` of scattered points determines no such
  interpolant, so point-value sections carry the vertical algebra and no derivatives.
- **Base reductions are the third operation family** — integrating the base away against a
  **measure** the base carries (`Grid3D` cell volume; `PointSet` counting): `integral`
  (extensive), the normalized `inner`/`l2norm`, and the `mean`/`std`/`var` moments. They map a
  section to a scalar or a fiber — with one sub-family deliberately excepted, since naming it
  here saves a reader the contradiction: the **radial** reductions `radial_spectrum` and
  `radial_correlation` return a *profile*, a pair of vectors over shells, not a single value. They are
  base-dependent (the measure is the base's), yet — like
  the vertical algebra — are shared by fields and point-values through `AbstractFiberSection`
  ([§12](@ref "12. Reductions"), decision 18). The same *measure* concept recurs as the interpolation kernel (below) and a
  convolution multiplier (the `Convolution` module, decision 20): one L²/integration structure in three roles (the
  measure taxonomy, decision 19).
- **Representation is a choice of basis for a grid section's data** (distinct from the
  fiber frame above): physical storage uses the nodal basis, spectral storage the Fourier
  basis, and the rfft is the linear isomorphism between them. "Basis" is the right intuition and
  slightly flatters the codomain: the transform is not an automorphism of one space, because the
  stored complex half-spectrum has strictly more real dimensions than the section it came from. It is
  an isomorphism onto the **Hermitian-constrained subspace** of that array — the constraint being what
  makes the map a bijection and the round trip exact (`FORMALIZATION.md` states it typed). A point-value section has no second
  representation — there is no periodic grid to transform over — so the point types
  are representation-free ([§10](@ref "10. Interpolation and anterpolation (the grid↔point transfer layer)")).

(The vertical/horizontal language is the bundle-theoretic one — fiber directions versus the
connection's base directions — applied here by analogy to *operations*: the fiberwise algebra
is order-zero and **base-preserving** — it covers the identity on the base, acting inside the fiber
over each point and touching no neighbour. It is deliberately *not* called fiber-*preserving*, which
this document reserves — in a narrower sense than the standard bundle-theoretic one — for a map that
leaves the fiber by the identity (the transfer maps, the
fiber-preserving reductions); `dot`, `norm`, `det` and `map!` all change the fiber. The horizontal
family, by contrast, is built from the connection's
covariant derivative, order one. Built *from* rather than *equal to*: `gradient`, `divergence`,
`curl` and `symmetric_gradient` are that derivative, but `inverse_laplacian` and
`helmholtz_projection` invert or project with it and are **nonlocal** — no local
partial-derivative formula, the value at a point depending on the whole field. Strictly, *vertical* (``\ker \mathrm{d}\pi``, the kernel of the bundle
projection ``\pi``'s differential — canonical) and *horizontal* (a connection-chosen complement) are
subbundles of the total space's tangent bundle.)

Transfer between sections over *different* bases is the interpolation/anterpolation
pair: pulling a grid section back to points (evaluation — pairing with a Dirac mass ``\delta_x`` — ``f(x) = \delta_x(f)``) and the
adjoint pushforward of point masses onto the grid. The full function–measure duality
is given in [§10](@ref "10. Interpolation and anterpolation (the grid↔point transfer layer)"); the `Interpolation` module docstring carries its concrete face (the
shared-weight adjoint identity with the ``M``/``N`` measure factors); the interpolation weights are
themselves a unit-mass kernel **measure** (signed for the higher-order schemes), the
base-changing sibling of the convolution multiplier — see the measure taxonomy
(decision 19).

### The architecture map

A field — or values sampled at scattered points — is a **section** ``s``, a right inverse of the bundle
projection ``\pi``:

```math
B \xrightarrow{ s } E \xrightarrow{ \pi } B, \qquad \pi \circ s = \mathrm{id}_B,
```

with base ``B`` (the structured `Grid3D` or the unstructured `PointSet`), ``E = B \times V`` the trivial
tensor bundle, and ``s`` the field (`AbstractFiberSection`): one fiber value per base point. Everything
below operates on sections, plus the support mechanics — each explained in its own section, referenced
here rather than repeated:

- **Representations** — physical (nodal) and spectral (rfft, written ``\hat f``) views of one section,
  exchanged by the isomorphism ``\mathcal F`` (`to_spectral`/`to_physical`); the spectral machinery and the
  operator-as-multiplier square are [§4](@ref "4. Spectral machinery").
- **Vertical — fiberwise algebra** ([`FieldAlgebra`](@ref GBGPeriodicFields.FieldAlgebra) on fields, [`Points`](@ref GBGPeriodicFields.Points) on point-values): add/scale,
  the weighted combination `combine!`, contract (`dot`/`cross`), transpose, sym/skew/dev, the `tr`/`det`
  invariants, pointwise norms — generated once ([§6](@ref "6. The code-generation architecture of `FieldAlgebra`")) — plus
  [`map!`](@ref GBGPeriodicFields.FieldAlgebra.map!), the arbitrary-`φ` **escape hatch** (any un-named
  pointwise fiber map, over the same fused executor; decision 48).
- **Horizontal — differential operators** ([`DifferentialOperators`](@ref GBGPeriodicFields.DifferentialOperators)): `gradient`, `divergence`, `curl`,
  `symmetric_gradient`, `laplacian`, …, applied as spectral multipliers ([§4](@ref "4. Spectral machinery")).
- **Convolution** ([`Convolution`](@ref GBGPeriodicFields.Convolution)): the kernel multiply ``\hat f \cdot \hat g`` in spectral representation ([§11](@ref "11. Convolution")).
- **Measure / L²** ([`Reductions`](@ref GBGPeriodicFields.Reductions)): `integral`, `inner`, `weighted_inner`, `l2norm`, `mean`, the radial spectra ([§12](@ref "12. Reductions")).
- **The grid↔point transfer** ([`Interpolation`](@ref GBGPeriodicFields.Interpolation)): interpolation ``W`` and its adjoint anterpolation
  ``W^{\top}`` ([§10](@ref "10. Interpolation and anterpolation (the grid↔point transfer layer)")).
- **Moving between storage families** ([`adapt`](@ref), decision 63): host and device are two families of
  the same object, and crossing between them is an explicit operation rather than something arithmetic
  does implicitly — invariant 14 refuses a mixed pair, and this is its named complement.
- **Support mechanics** — types & memory layout ([§3](@ref "3. Types and memory layout")), validation design ([§5](@ref "5. Validation design")), code generation ([§6](@ref "6. The code-generation architecture of `FieldAlgebra`")),
  aliasing ([§7](@ref "7. Aliasing policy")), broadcasting ([§8](@ref "8. Broadcasting")), performance & threading ([§9](@ref "9. Performance model and CPU threading")).

Reductions, convolution, and the grid↔point transfer are the same L²/integration structure in three
roles — the **measure taxonomy** (decision 19). Which operation is valid in which representation, the naming rules, and the
documentation policy follow.

### The invariants

Fourteen rules constrain every change, and the rest of this document refers to them by number. They
are collected here so a reader meeting "invariant 6" has somewhere to look; each is stated in one line,
with a pointer to the section that develops it.

1. **The public method set is the spec.** Deliberate absences encode representation validity — there is
   no field-times-field multiplication in spectral representation (the coefficientwise product is a convolution, offered
   under its true name in [§11](@ref "11. Convolution")), no spectral division by a scalar field, no spectral pointwise
   norms. Operations linear in the field exist in both representations; nonlinear ones are
   physical-space only. A missing combination is never added for completeness (see the next subsection).
2. **A field is a real physical object**, and physical and spectral are two *representations* of it.
   Complex arrays are storage detail, never user-facing — hence "a field in spectral representation",
   not "a spectral field".
3. **The data layout is fiber-last**, ``(N_x, N_y, N_z[, 3[, 3]])``, so component slices are
   contiguous; FFT batching and CPU threading both rely on it ([§3](@ref "3. Types and memory layout")).
4. **The transform normalization is `AbstractFFTs`'**: forward unnormalized, inverse normalized. Adding
   a physical constant in spectral representation therefore updates **only** the zero Fourier mode,
   scaled by the grid-point count, rather than every coefficient ([§4](@ref "4. Spectral machinery")).
5. **The Nyquist split is deliberate.** On an even-length axis the derivative wavenumber is zeroed at
   the Nyquist frequency, so derivatives of real fields stay real, while the squared wavenumber keeps
   the true ``k^2``, so the Laplacian and Poisson-type solves stay correct. The two families are not
   unified ([§4](@ref "4. Spectral machinery")).
6. **The package is GPU-portable by construction**: storage is a generic `AbstractArray`, no package
   method scalar-indexes a device array, allocation goes through `similar`/`similar_field`, and fused
   broadcast assignments are preferred ([§9](@ref "9. Performance model and CPU threading")).
7. **No type piracy**: a `Base` or `LinearAlgebra` function is imported before it is extended.
8. **No fiber-fiber methods.** The fiber types are `StaticArrays` aliases and already carry their own
   algebra, so the package does not redefine it.
9. **Aliasing is safe by construction, and a section owns its storage so that it is.** Every fused
   pass reads an element's sources into registers before writing any of its outputs, so an in-place
   aliased call is computed directly and is bitwise-identical to the non-aliased one; the former guard
   family is retired. That argument holds only while one section's element ``n`` is the other's element
   ``n``, which is the **ownership** half of the invariant and not a detail of it: the constructors
   reject borrowed storage — a `SubArray` anywhere in the parent chain — leaving same-array as the only
   way two sections can share memory (decision 59). Ownership, not layout: an `Array`, a `CuArray`, a
   `ROCArray` and a `reshape` of any of them all pass. The `mul!` contract keeps
   `LinearAlgebra`'s documented contract that the destination must not alias ([§7](@ref "7. Aliasing policy")).
10. **The ``\alpha``/``\beta`` convention.** A five-argument form converts both weights to the field's
    scalar type and branches on ``\beta = 0`` (overwrite) versus ``\beta \ne 0`` (accumulate); a
    three-argument form delegates to it with ``\alpha = 1``, ``\beta = 0``. Throughout, ``\alpha`` scales
    the computed result and ``\beta`` the destination accumulated onto. **Two deliberate exceptions, and
    only these two:** `combine!` is the weighted combination ``\alpha a + \beta b``, so its two weights
    scale its two *operands* instead — which is what the operation is, and what its name announces —
    and `exponential_convolve!`'s two-operand forms carry the same combination, and so the same reading
    of the glyphs, into a fused convolution. Both are operations whose *definition* is a weighted
    combination; no operation may reuse the glyphs for a role other than that.
11. **The transform input contract.** The allocating transforms preserve their input; the in-place ones
    may overwrite the source, and the inverse real transform uses its spectral input as scratch on some
    backends but not others. Never rely on a `!`-transform's source surviving — with one deliberate
    exception that guarantees it: the four-argument scratch arity of `to_physical!`, which consumes a
    caller-supplied scratch in the source's place (decision 64; [§4](@ref "4. Spectral machinery")).
12. **This is a math backend — no time, and no particles.** The terminology stays domain-neutral
    (base and fiber, point and value), and the package introduces no advection, time integration, or
    per-step state; trajectory dynamics belong to the consumer ([§10](@ref "10. Interpolation and anterpolation (the grid↔point transfer layer)")).
13. **Allocation-free is an enforced contract.** Every in-place `!` operator allocates no field-sized
    scratch when called on preallocated buffers with a destination distinct from its sources. This is
    load-bearing on a GPU: a per-call device temporary escapes Julia's garbage collector, which
    triggers on host pressure and cannot see the device buffer a dead array owns, so the pool grows
    every step until the run wedges ([§9](@ref "9. Performance model and CPU threading")).
14. **Sections combine only within one precision and one storage family — never by conversion.** An
    operation over two or more sections requires them to agree in element type and in storage family
    (`Array` with `Array`, `CuArray` with `CuArray`), and refuses anything else with a clear error
    rather than promoting, copying, or transferring. The refusal is a decision of the package, not an
    accident of a vendor library declining a mixed-pointer call or a kernel launcher declining mixed
    arrays. It binds every argument an operation takes, the destination and the non-section partners
    included — a spectral field and its multipliers must match too. Conversion is an explicitly-named
    operation, never something an arithmetic operation does implicitly: crossing **storage families**
    is [`adapt`](@ref) (decision 63), or [`adapt!`](@ref) into a destination that already exists
    (sections only; decision 69), and crossing **precisions** remains future work.

### Representation validity lives in the method set

Seeing each representation as a **basis for a grid section's data** — the nodal basis
(physical) and the Fourier basis (spectral), with the rfft the linear isomorphism between
them — fixes exactly which operations are valid where: an operation exists in a
representation only when it is *the same operation on the underlying section there* —
equivalently, only when it commutes with the rfft isomorphism.

- **Linear in the field** — addition/subtraction of fields, scaling by real
  numbers, contractions with *constant* fibers, transpose, sym/skew/dev: valid in
  both representations, because the Fourier transform commutes with them.
- **Adding constants** — in physical space, every grid value shifts; in spectral
  space, ``\mathcal F(f + c) = \mathcal F(f) + c N \delta_{k,0}`` under the unnormalized-forward convention,
  with ``N`` the total grid-point count (`prod(grid_size)`) and ``k`` the wavenumber — so only the zero
  mode (``k = 0``) changes, scaled by ``N``. This is why
  `_spectral_constant_scale` exists and why constant kernels in spectral
  representation touch a single coefficient (per component).
- **Nonlinear in the field** — products of two fields, division by a scalar field,
  pointwise norms, contractions of two fields (dot, cross, tensor `mul!`, and the
  fiberwise tensor inner product `dot!` — not the `inner` reduction, which is Parseval-valid in
  spectral representation): physical-space only. The coefficientwise spectral product is *not* the
  Fourier representation of the pointwise product (that would be a convolution),
  so offering it *as a product* would silently compute the wrong physical operation —
  that coefficientwise product *is* convolution, exposed under its true name as `convolve`
  (the `Convolution` module, decision 20), never as `*`.

The pointwise product is *not* preserved by ``\mathcal F`` — the **convolution-theorem square**
(``\star`` denoting periodic convolution, the package's `convolve`):

```math
\begin{CD}
(f,g)            @>{\star}>>   f \star g \\
@V{\mathcal F}VV               @VV{\mathcal F}V \\
(\hat f,\hat g)  @>>{\cdot}>   \hat f \cdot \hat g
\end{CD}
\qquad\qquad \mathcal F(f \star g) = \hat f \cdot \hat g .
```

The coefficientwise product *downstairs* is **convolution** upstairs (offered as `convolve` (``\star``),
[§11](@ref "11. Convolution")); the pointwise product ``f \cdot g`` transforms to a convolution with **no** coefficientwise spectral
form — exactly why those nonlinear operations are physical-space only.

The same finiteness makes a nonlinear result **aliased**. A product doubles the spectral band — the
determinant (a triple product) triples it, a non-polynomial map such as the norm is unbounded — so content
beyond the grid's Nyquist (highest stored) wavenumber folds back onto the resolved modes when the
physical result is transformed to spectral representation. The grid point values themselves stay exact; the
aliasing is a spectral-representation artifact, and de-aliasing — the sharp low-pass `spectral_cutoff`, or
phase-shift via `translation_kernel` ([§11](@ref "11. Convolution")) — is the consumer's choice, the
package supplying the tools rather than the strategy.

The consequence is a hard project invariant: **a missing method is a statement,
not an omission**. The 206-method public surface of `FieldAlgebra` is the
machine-checkable encoding of the validity table above. Any refactor must
reproduce the method set exactly; it was verified signature-for-signature against
the original — M2 (98 methods: `add!`/`subtract!`/`multiply!`/`divide!`/`+`/`-`/`*`/`/`)
and then M3 (the dot/cross/`mul!`/transpose/norm/sym/skew/dev/trace contraction and
decomposition families, plus their `*` operators), bringing the total to 198; the later
trace `tr`/`tr!` addition brings it to 202, and the weighted combination `combine!` (2)
with the determinant `det`/`det!` (2; decision 27) complete the 206-method surface, all
parity-checked at runtime in `test/method_parity.jl`. The point-value algebra
realizes the *vertical* operations on the unstructured base — it mirrors the
**physical** field surface and is locked by its own separate baseline ([§10](@ref "10. Interpolation and anterpolation (the grid↔point transfer layer)")).

### Naming conventions

Operation names follow *what the operation is* — the same mathematics-first principle:

- **Reductions** (section → scalar/fiber) take the **quantity's noun**: `integral`, `inner`,
  `l2norm`, `lpnorm`, `radial_spectrum` (the radial profile is still the quantity's noun).
- **Canonically named operators** (section → section with a standard, often eponymous operator name
  and no natural verb) take that **noun**: `gradient`, `divergence`, `curl`, `inverse_curl`,
  `laplacian`, `inverse_laplacian`, `helmholtz_projection`.
- **Generic transformations** (section → section, named by the action) take the **verb**: the
  elementwise algebra (`add`, `subtract`, `multiply`, `divide`), the representation changes
  (`to_physical`, `to_spectral`), and the kernel-measure maps `interpolate` / `anterpolate` and
  `convolve`.
- **In-place** forms append `!` uniformly (`gradient!`, `interpolate!`, `convolve!`).
- **Extensions of Base / LinearAlgebra / Statistics** keep the source name, overriding the above
  (`dot`, `cross`, `mul!`, `transpose`, `norm`, `map`, `map!`, `mean`, `std`, `var`, `cov`,
  `maximum`, `minimum`, `extrema`); the continuum-mechanics decomposition abbreviations `sym` / `skew` / `dev` are likewise
  conventional. An extended generic is **re-exported when its source is not already in scope**, so that a
  caller never has to know which standard library a verb happens to live in: the `LinearAlgebra` and
  `Statistics` names are re-exported by the umbrella, while the `Base` ones need no such treatment.
  Re-exporting a binding the package only extends is safe — two packages re-exporting the *same*
  binding do not collide, only two exporting *different* bindings of one name do.
- **Modules** carry the family **noun** (`Fields`, `DifferentialOperators`, `Reductions`,
  `Interpolation`, `Convolution`); the operations inside follow the rules above — so
  `Convolution` / `convolve` mirrors `Interpolation` / `interpolate`.

The discriminator that places a new operation: a *generic transformation with a natural verb* is a
verb (convolution → `convolve`); a *canonically named operator* is its noun (the Laplacian →
`laplacian`). The operators `gradient`/`laplacian`/`helmholtz_projection` are nouns because they are the names of
those operators, not by a noun preference.

### Documentation policy

The `@eval` code generators ([§6](@ref "6. The code-generation architecture of `FieldAlgebra`")) emit methods only, never docstrings. Each operation has one
docstring attached to the bare binding (`function f end` for package-owned generics; the
bare imported name for Base/LinearAlgebra functions — never `function f end`
there, since a missing import would silently create a new generic). Docstrings
show a few canonical signatures plus prose about representation validity,
including which combinations are intentionally absent. Exhaustive signature lists
were dropped: they duplicated the tables and went stale instantly.

**Mathematics is rendered LaTeX, with the symbol bound to the code.** All math in docstrings and
in these doc pages is written as Documenter LaTeX (KaTeX) in **standard notation** — inline
``\langle f, g\rangle``, display ```math``` blocks — never Unicode-glyph approximations (`⟨f,g⟩`,
`Σ`, `∫`). Because the package is *grounded in mathematics* (the principle of this section), each
code object is **explicitly identified with its mathematical symbol on first mention** so the
correspondence is never left implicit: `gradient` (``\nabla``), `divergence` (``\nabla\cdot``),
`curl` (``\nabla\times``), `laplacian` (``\Delta``), `inverse_laplacian` (``\Delta^{-1}``),
`helmholtz_projection` (``\mathbb{P}``), `inner` (``\langle\cdot,\cdot\rangle``),
`l2norm` (``\lVert\cdot\rVert_2``), `integral` (``\int\,\mathrm{d}\mu``), `convolve` (``\star``),
`interpolate`/`anterpolate` (``W``/``W^\top``),
`to_spectral`/`to_physical` (``\mathcal F``/``\mathcal F^{-1}``),
a field in spectral representation written ``\hat f``. (In a `"""` docstring the LaTeX backslashes
are escaped `\\`; in a `.md` page they are raw. Plain `#` comments stay Unicode — they are not
rendered.) `Reductions` is the reference implementation.

## 3. Types and memory layout

`Grid3D{T}` holds domain geometry; `RealFourierLayout` records the rfft layout.
Field types are parameterized by scalar type `T<:AbstractFloat`:
`ScalarFieldPhysical/Spectral`, `VectorFieldPhysical/Spectral`,
`TensorFieldPhysical{2}/TensorFieldSpectral{2}`. Constant fiber values are
StaticArrays aliases — `FiberVector{T} = SVector{3,T}`,
`FiberTensor2{T} = SMatrix{3,3,T,9}` (plus `FiberTensor3/4`) — so fiber-fiber
algebra comes from `StaticArrays`/`LinearAlgebra` and the package never defines it.
**StaticArrays is a direct dependency**, not just the type-only `StaticArraysCore`:
the package indexes fibers (`a[i]`, `A[i, j]`) and uses their algebra inside the
generated kernels, so the core-types package alone leaves those operations undefined.

Data layout is **fiber-last**: `(Nx, Ny, Nz)` for scalars, `(Nx, Ny, Nz, 3)` for
vectors, `(Nx, Ny, Nz, 3, 3)` for tensors; spectral arrays are `Complex{T}` with
the axis carrying the real transform halved per rfft — the first axis under the default
`RealFourierLayout`, which may assign any of the three. Rationale: with column-major storage, each
component slice `data[:, :, :, i(, j)]` is one contiguous block. That gives
batched per-component FFTs, coalesced GPU access, pure streaming writes for
elementwise kernels, and trivially chunkable index ranges for the CPU
threading ([§9](@ref "9. Performance model and CPU threading")). Component access goes through views
(`_vector_component_data`, `_tensor2_component_data`); views are lazy, so
splicing them into generated formulas costs nothing.

Storage is any `AbstractArray`, and the package names no vendor type and no memory kind. A field's
**storage family** is the kind of array holding its values — `Array`, `CuArray`, `ROCArray` — and on
CUDA the same `CuArray` may sit in device memory or in **unified memory** paged between the GPU and host
RAM. Which of the two is CUDA.jl's configuration rather than the package's, and every allocating route
follows it, so a CUDA run can hold fields larger than the card with no change to the code (decision 84,
[Running on a GPU](gpu.md)).

## 4. Spectral machinery

`FieldTransformPlans` owns the FFT plans (per backend). Forward transforms are
unnormalized; inverse transforms carry the normalization (AbstractFFTs
convention) — this single convention choice propagates into the zero-mode constant
updates described above.

**Transform input-preservation contract.** The in-place `to_physical!`/`to_spectral!`
apply their plans through `mul!`, the no-copy path, so the *source* field may be
overwritten as scratch. This is intrinsic to real↔complex FFTs: FFTW's
complex-to-real (`irfft`) transform destroys its input by default, and the
multidimensional case has no input-preserving algorithm at all. It is also
backend-divergent, and *which* backend overwrites *which* direction is not uniform:
FFTW preserves the forward `to_spectral!` but destroys the inverse `to_physical!`, while a
GPU backend (rocFFT) can differ on either. The package therefore guarantees **nothing** about a
plain `!`-transform's source on any backend, matching the `to_spectral!`/`to_physical!` docstrings —
the one guaranteed-preserving `!` call is the four-argument `to_physical!` scratch arity, which pays
one explicit copy into a caller-supplied scratch for exactly that guarantee (decision 64); to keep
a uniform, portable contract, the allocating `to_physical`/`to_spectral` copy their input before
transforming, so non-`!` calls never mutate their argument (the Julia convention)
while `!` calls stay allocation-light and document that the source may be consumed.

`FieldSpectralMultipliers` holds six one-dimensional arrays: derivative
wavenumbers `wavenumber_1..3` and `squared_wavenumber_1..3`, plus the grid and
layout. It lives in **`Fields`**, as a sibling of `FieldTransformPlans`, because it
is representation infrastructure (what the spectral axes *mean*), not a
differential operator; it moved out of `DifferentialOperators` during the refactor.
Two constructors by design:

- An explicit constructor taking all six arrays (lengths validated). This makes
  the type testable in isolation and lets callers control the backend.
- A convenience constructor from a field: wavenumbers ``2\pi n/L`` are built on the
  host and copied to the field's backend via `similar` + `copyto!` (no scalar
  GPU writes).

The two differ in the type they produce, not only in convenience: a final `Canonical` type parameter
records whether the arrays were **derived from the grid** (the convenience constructor) or **supplied
by the caller** (the explicit one, which validates lengths and not values). Two canonical sets on a
matching grid and layout therefore hold equal values by construction, which is what lets `convolve`
collapse two radial kernels without a runtime test — see decision 61.

**The Nyquist split is deliberate and must not be unified.** On even-length axes:

- Derivative multipliers are **zeroed at the Nyquist frequency**. The Nyquist
  mode of a real signal is a pure cosine; multiplying by ``\mathrm{i} k_N`` would produce a
  component the real signal cannot represent, and the symmetric, real-preserving
  choice for its derivative is zero. This is standard pseudospectral practice and
  keeps derivatives of real fields exactly real.
- Squared multipliers keep the **true ``k^2``** at Nyquist. The Laplacian of the
  Nyquist mode is perfectly well defined (``-k_N^2 \mathrm{mode}``); zeroing it would silently
  remove grid-scale dissipation and corrupt `inverse_laplacian`.

Reference tests pin this down: multipliers vs `fftfreq`/`rfftfreq`, transform
round-trips, and a real-field Nyquist end-to-end test (the derivative zeroed at Nyquist
vs the squared wavenumber kept) — see `docs/TESTING.md`.

**Operators are multipliers — the intertwiner square.** ``\mathcal F`` (`to_spectral`, with inverse
`to_physical`) is a linear isomorphism, and every translation-invariant operator ``L`` — `gradient`
(``\nabla``), `divergence` (``\nabla\cdot``), `curl` (``\nabla\times``),
`laplacian` (``\Delta``) — is *diagonalized* by it into a pointwise multiplier ``\hat L = m(k) \cdot`` (``\mathrm{i}a``,
``\mathrm{i}a\cdot``, ``\mathrm{i}a\times``, ``-|k|^2``, writing ``a`` for the derivative wavenumber and ``k`` for
the true one — the Nyquist split just above):

```math
\begin{CD}
f      @>{\mathcal F}>>   \hat f \\
@V{L}VV                   @VV{\hat L}V \\
Lf     @>>{\mathcal F}>   \widehat{Lf}
\end{CD}
\qquad\qquad \mathcal F\circ L = \hat L\circ\mathcal F .
```

This commuting square *is* invariant 2 (one object, two representations) and the entire design of
`DifferentialOperators`: ``L`` is never formed in physical space — the multiplier ``\hat L`` is applied
in spectral and conjugated by ``\mathcal F^{\pm1}``. It is the worked case of [§2](@ref "2. The central principle: the architecture follows established mathematics")'s representation-validity
rule: an operation may be offered in a representation **iff** its square commutes.

## 5. Validation design

`Fields` owns compatibility checking, built from atomic Boolean predicates
(`_same_scalar_type`, `_same_grid`, `_same_layout`, `_same_backend`) composed
into `_check_same_domain`. The last of those is what realizes invariant 14: it throws when two
sections live in different storage families (an `Array` against a `CuArray`), and it sits in the
domain check rather than below it, so the error does not depend on which operation the user happened
to call. Tensor order is deliberately **not** among them — `_same_tensor_order` is checked one level
up, in `_check_field_compatibility` only, because the domain check must let order differ for the
operators that change it (`gradient`, `divergence`). Composed on top are the representation-dispatched
`_check_field_domain_compatibility` (physical-physical and spectral-spectral
methods — the dispatch barrier that prevents cross-representation mixing), the
unexported `_check_field_compatibility` (un-prefixed, but documented with the internals), and `_check_field_matches_context` for
transform plans.

History: `FieldAlgebra` used to carry near-duplicate checkers
(`_check_scalar_field_compatibility`, `_check_tensor2_vector_field_compatibility`).
These were removed in favor of **direct calls** to
`Fields._check_field_domain_compatibility` — an explicit decision against alias
names: one concept, one name, imported explicitly.

Check placement follows one rule: bodies that go through field broadcasting do
not pre-check, because the broadcast machinery already enforces compatibility
(shape/grid/style promotion); bodies that bypass broadcasting — copy-then-kernel
paths, zero-mode updates — check explicitly. This is why, e.g. physical
scalar±Real methods are bare broadcasts while their spectral counterparts call
`_check_field_compatibility` before `_copy_field_data!`.

## 6. The code-generation architecture of `FieldAlgebra`

### Why it emerged

The original `FieldAlgebra` was 3033 hand-written lines defining ~198 public
methods, with per-component kernels unrolled by hand (three statements per vector
operation, nine per tensor). The regularity was overwhelming: one mathematical
operation expands into 8–32 near-identical methods (two representations × two
argument orders × in-place/allocating × vector/tensor). Hand maintenance meant
every new operation or convention change had to be edited consistently in dozens
of places — a divergence machine. The refactor regenerates the **same** method
set from small tables, so each formula and each convention is written exactly
once, while the public surface (and its deliberate absences) stays bit-identical.

### Layers

- **M1 — expression builders** (the vertical-algebra builders in `FiberSections`, imported by `FieldAlgebra`):
  `_vector_component(symbol, kind, i)` / `_tensor_component(symbol, kind, i, j)`
  produce component-access expressions, with `kind = :field` (component view) or
  `:fiber` (StaticArrays indexing); `_sum_terms` and `_product` combine formulas;
  `_vector_kernel_body` / `_tensor_kernel_body` (with `alpha_beta::Bool`) and
  `_scalar_kernel_body` wrap formulas into kernel bodies ending in
  `return destination`. With `alpha_beta = true` the body branches on
  `iszero(β_value)` so the pure-overwrite path stays allocation-free.
- **M2 — elementwise families (done)**: flat `@eval` tables stamp out
  constant-fiber kernels (an update lambda `(target, value) -> :($target .+= $value)`
  applied per component via statement splats), field-field combination and
  operators, scalar-constant operators, field±fiber (one row per field type carries
  the kernels and yields eight methods), real scaling, and scalar-field×fiber
  (rows carry the destination tensor order for `similar_field(…, Val(order))`).
  Type parameters enter tables as expressions —
  `:(TensorFieldPhysical{2, T})` with `where {T<:AbstractFloat}` on the emitted
  method. Irregular corners stay explicit, each with a comment saying why:
  the scalar±Real family (physical broadcasts vs zero-mode updates; reversed
  subtraction is its own operation), the four ambiguity-resolving `multiply!`
  signatures, and the physical-only divisions.
- **M3 — contraction kernels (done)**: one formula table per family — dot, cross,
  tensor-vector and tensor-tensor `mul!`, transpose, tensor inner products,
  pointwise norms, sym/skew/dev — fed through the kernel-body builders. Per-family
  flags: `has_beta` (α/β accumulation for the `mul!` families; five-argument forms
  convert `T(α)`, `T(β)`, three-argument forms delegate `one(T)`, `zero(T)`) and
  the routing through the fused executor (cross and the unary index-shuffles —
  transpose, sym, skew, dev — run alias-safe by construction, an element's sources
  read before its outputs are written, decision 39; `mul!` documents the no-alias
  contract instead, per LinearAlgebra convention). The `sym`/`skew`/`dev` methods
  on bare `FiberTensor2` remain explicit StaticArrays one-liners.
- **M4 — public wrappers/operators (done, folded into M3)**: the allocating
  forms and the `*` operators (tensor·vector, tensor·tensor) are generated
  alongside their `mul!`/`dot`/`cross`/… kernels, completing the 206-method surface.

The same builders are reused verbatim to generate the point-value algebra over the
unstructured base ([§10](@ref "10. Interpolation and anterpolation (the grid↔point transfer layer)")) — the formulas are base-independent ([§2](@ref "2. The central principle: the architecture follows established mathematics")). They live in the shared
`FiberSections` module (with the `_assign!` primitive); both `FieldAlgebra` and `Points` source
them from there, so each fiberwise formula — including the norm/sym/skew/dev ones, via
`_section_scalar_type` — is written exactly once.

### Verifying codegen changes

With Julia available, verification is runtime introspection: load the package,
compare per-generic `methods(f)` counts against the committed baseline
(`test/method_parity.jl`), and run `detect_ambiguities` (from `Test`) over the
package. The full M2+M3 baseline is 206 public methods (e.g. `*` 28, `mul!` 30,
`dot`/`dot!` 10 each, `add!` 14, `combine!` 2, `tr` 2, `det`/`det!` 1 each). (During the no-Julia refactor phase, parity was
checked by simulating table expansion and diffing normalized signatures against the
original file; runtime introspection supersedes that.)

## 7. Aliasing policy

Alias safety is **by construction**: every fused pass — the one-pass differential operators
(decisions 32 and 38's operator kernels) and the generic fiberwise executor behind the algebra
(decision 39) — reads all of an element's source values into registers before writing any of that
element's destinations, and elements are disjoint, so an in-place call (`curl!(u, u, m)`,
`transpose!(A, A)`, `sym!(A, A)`) is computed directly and is bitwise-identical to the
non-aliased call, with no temporary.

That argument carries one hypothesis, load-bearing rather than incidental: one section's element ``n``
has to be the other's element ``n``. **Ownership** supplies it — a section's constructor rejects
borrowed storage, a `SubArray` anywhere in the parent chain, so same-array is the only way two sections
can share memory (decision 59). Before that rule, two partially-overlapping views at different base
indices broke the argument silently across fourteen operations; such a pair is now not merely
undetected but unconstructible.

The former guard family (`_guard_noalias!` and its
point-value twin), which ran an aliased call through a fresh field and a copy-back, is retired —
decision 39 removed its last callers. The one remaining aliasing rule is contractual: `mul!`
documents that the destination must not alias the inputs, matching `LinearAlgebra.mul!` semantics
(its fused pass happens to be alias-safe too, but the documented contract is not widened).

## 8. Broadcasting

`Fields` broadcast storage-wise: a field in a broadcast stands for its data array,
and the field broadcast style (owned by `Fields`) materializes into field storage.
Style promotion is one-sided by design — define a single binary rule per style
pair, never symmetric mixed-representation rules. The broadcast layer doubles as
the compatibility enforcement for broadcast-mediated methods ([§5](@ref "5. Validation design")).

**The broadcast layer is internal machinery, not a public contract.** A consumer *can* dot-broadcast
fields — Julia's dispatch makes that unpreventable without hostile piracy against `Base` idiom — and
the expression will fuse and return a field; but nothing about that surface is specified, verified,
or guarded. In particular it can express what the method set deliberately withholds (invariant 1): a
`.*` between two fields in spectral representation compiles and computes the banned coefficientwise
product, with none of the named operations' checks. The public contract is the named method set; the
broadcast layer exists to implement it (decision 35).

## 9. Performance model and CPU threading

Elementwise field operations are memory-bandwidth-bound streaming; FFTs dominate
asymptotically. Both are now threaded on CPU (shared memory). On GPU, broadcasting and
the device FFT libraries already launch parallel kernels, so the CPU threading is
dispatched away (below). The full performance model (per operation class), the externally
sourced best practices, the recorded benchmark findings, and the tracked benchmark suite
live in the companion [`PERFORMANCE.md`](performance.md).

**FFTs.** FFTW threading is baked in at **plan time**, so the package's `__init__` calls
`FFTW.set_num_threads(Threads.nthreads())` before any `FieldTransformPlans` is built
(`set_fft_threads!` retunes it). Oversubscription caveat: FFTW's pthreads multiply with
Julia's tasks — code that parallelizes *across* fields and transforms inside each task
should build plans under `set_fft_threads!(1)`. The common case (one field, transforms
serial in a time loop) wants `nthreads()` FFTW threads, the default.

**Elementwise/fiberwise ops.** One internal primitive `_assign!(destination, bc)` in
`FiberSections`. The generic method is `Broadcast.materialize!` — the safe polarity: GPU and unknown
array wrappers keep the standard fused broadcast, so **invariant 6 holds by dispatch**, not
discipline. The `Union{Array, SubArray{…,<:Array}}` specialization threads a single
instantiated `Broadcasted` over contiguous chunks (fusion preserved — one `Broadcasted`
tree, no temporaries, one memory pass), **bitwise-identical to serial** because each output index is
written once. The threaded path splits the destination's slab axis — the last among the largest,
so a whole-vector-field write splits a grid axis, never the length-3 fiber — and runs the standard
fused `materialize!` per slab over sliced views of the operands, so each slab executes the same
SIMD kernel the serial path uses (decision 38; its per-element predecessor ran ~4.7× slower per
core and *inverted* at low thread counts — [`PERFORMANCE.md`](performance.md) §4 finding (l)). A serial cutoff (`_SERIAL_CUTOFF`, default ``2^{14}``) keeps small ops — including
the one-element zero-mode views — serial. Policy is **hybrid**: threaded when
`nthreads() > 1` and above the cutoff, with a task-local `ScopedValue` override
(`with_threading(enabled = …)`) for nested-parallel callers.

Two plug points route work through `_assign!`: the field broadcast style's `copyto!` (all
whole-field dotted ops and the field-level algebra), and the kernel assignments — the
codegen body builders emit `_assign!(target, …)` (via `_to_broadcasted`, which rewrites a
dotted formula into a lazy `broadcasted` tree at codegen time), and the hand-written
`FieldAlgebra` / `DifferentialOperators` kernels use the `@_assign!` macro in place of `.=`. (The
decision-39 fused executor is the third route: its stamped per-element values functions run inside
`_fiberwise_pass!`'s own kernel and slab loop, governed by the same gate — the route policy below.) No
types, signatures, or method tables change — the 206-method surface and the zero-ambiguity
property are preserved. **Discipline:** a raw elementwise write must go through
`_assign!`/`@_assign!`, never a bare `.=`, or it silently runs single-threaded.

Reductions (global norms, integrals — the L²/measure structure) are now provided in the `Reductions`
module (decision 18), built on `sum`/`dot`/`maximum` rather than the threaded `_assign!`: those reorder
floating-point adds (pairwise on the host, differently on threads/GPU), so they are **tolerance-tested,
not bitwise** like the assignments here. (The only already-threaded part is a *prior* step in a couple of them:
`lpnorm` for ``p \ne 2`` builds the pointwise fiber magnitude ``\lvert f\rvert`` via the vertical
`norm` — an `_assign!`-routed fiberwise op, hence threaded — then reduces *that* with the plain
`sum`/`maximum`. The reductions `inner`/`l2norm`/`integral`/`mean` build no such field, so they are a single,
unthreaded `dot`/`sum`.) That remaining work landed as decision 40: every CPU reduction now runs a
fixed midpoint tree, spawned at its top levels through the same gate, bitwise thread-count-invariant;
the speedup saturates at socket bandwidth over single-core (typically
2–6×; more on multi-socket nodes, where thread pinning and NUMA first-touch matter — ThreadPinning.jl).
Placement is **not** settled by `similar`, which reserves address space without touching pages: the
first *write* decides, so a threaded `_assign!` fill distributes pages across domains while a serial
one concentrates them. On the two-socket cluster node decision 37 names as the CPU path's target, that
difference is the dominant bandwidth risk, and no measurement of it exists — a single-socket
workstation cannot produce one.

**The execution-route policy — which mechanism a new or rewritten operation takes.** The routes
below were each adopted by measurement (decisions 30, 38, 39, 40); together they form the standing
rule, so a future operation is placed by its *structure*, not by precedent-mining:

1. **Single-output elementwise work whose traffic is already at the fused ideal** takes the
   **broadcast route** (`@_assign!`): one fused expression, the threading gate and slab
   `materialize!` on CPU, the device's native broadcast elsewhere. (`add!`, `combine!`,
   `laplacian!`, the scalar `convolve!`.)
2. **Multi-output fiberwise work with shared source reads and no coordinate-dependent
   coefficient** takes the **fused executor** (`_fiberwise_pass!`): a values function stamped from
   the shared formula tables, one KernelAbstractions kernel on a device, the gated linear `@simd`
   loop on CPU. (`cross!`, the `mul!` family, the shuffles and decompositions, `det!`, the
   scalar-field actions, the fiber cases of `convolve!`.)
3. **Elementwise work whose coefficient depends on the mode's cartesian index** (wavenumbers)
   takes a **decision-38-shape pair**: a hand-written KA kernel for devices and a gated cartesian
   `@simd` loop for CPU, both from one set of per-mode expressions. (`gradient!`, `curl!`,
   `symmetric_gradient!`, `helmholtz_projection!`, and the compressed kernels' application —
   decision 50's axis-factored class and decision 51's radial one, which take the same route for the
   same reason: a *broadcast* device route paired with a gated CPU loop, rather than a hand-written
   kernel with one, for the measurement in `PERFORMANCE.md` finding (o). The
   exponential family currently broadcasts over the lazy ``|k|^2`` and is the recorded candidate for
   this shape — the finding-(k) hoist.)
4. **Reductions** take the **backend split of decisions 30/40**: the fixed midpoint tree on CPU —
   gated, spawned at its top levels, bitwise thread-count-invariant — and the device's own
   parallel reduce elsewhere.
5. **Atomic accumulation or data-dependent irregular access** — and only that — takes
   **KernelAbstractions on every backend** (the transfer gather/scatter, the shell binning): a
   gated loop cannot serve atomics or per-point stencils, so these are the only operations outside
   the threading policy, and the atomic ones are tolerance-tested where reordering perturbs last
   bits.

Whatever the route, three obligations are constant: a migration is verified **bitwise against the
implementation it replaces** (or against an oracle when the arithmetic legitimately changes), the
pass-audit row lands at its fused ideal or carries a named holder, and alias safety is either by
construction (an element's reads precede its writes) or a documented contract (`mul!`).

**The kernel sites split into two classes for the threading policy — and two kernels are not
bitwise.** The fused operations of decisions 38/39 (`gradient!`, `curl!`, `symmetric_gradient!`, the
fiberwise executor behind the algebra) are `KernelAbstractions` kernels **on a device only**; on a
CPU array they run slab-threaded plain loops that pass through the same `_use_threads` gate as the
broadcast route, so the cutoff and the `with_threading` override govern them.

**Bitwise is a same-backend contract, and the reason it cannot cross a backend is compiler
contraction.** A device compiler folds `x + c * v` into a fused multiply-add, rounding once where the
host's two instructions round twice, so the same source expression is not the same arithmetic. The
difference is a last bit — for `displace!` it measures ``1.8 \times 10^{-15}`` in `Float64` on
coordinates of order one — but it is real, it is not noise, and it is why every cross-backend
comparison in the suites is tolerance-tested while thread-count invariance is asserted exactly.
Writing `muladd` on the host side to force the two into agreement was measured and declined: it buys no
speed on either backend, improves the error bound without improving every element, and would rest a
package guarantee on undocumented vendor contraction (`PERFORMANCE.md` finding (z)).

One pairing the route list above does not name outright, because it mixes two of its entries, is worth
recording since decision 50 added the second instance: an operation may take the **broadcast route on a
device and a hand-written gated loop on a CPU**. The `helmholtz_projection!` operator pairs a `KernelAbstractions`
kernel with a gated CPU loop (decisions 38, 40); the axis-factored kernel of decision 50 pairs a
*broadcast* with one. The reason is measured rather than aesthetic — a broadcast whose operands carry
singleton axes indexes cartesian and launches flat, which is what a device wants, but does not vectorize
on a CPU, where it ran at a fixed element rate independent of precision (`PERFORMANCE.md` finding (o)).
Either way the pair is backend-dispatched and carries decision 47's dispatch-target guard, without which
the CPU half is dead code the tests cannot see.

Two groups of operations, however,
are KA kernels **on every backend** — the gather/scatter transfer kernels
([§10](@ref "10. Interpolation and anterpolation (the grid↔point transfer layer)")), and the radial
shell binning (decisions 25, 34) — and on a CPU array these launch on the `CPU()` backend, which
partitions the index range by `Threads.nthreads()` itself (`helmholtz_projection!` left this set when
decision 40 gave it a gated loop twin, so what remains is exactly the atomic/irregular kernels — the
exemption is structural, not historical). Two consequences follow for those two families,
and neither is a defect to fix — they are the price of their kernel shapes. First, a KA launch
**never consults the `_assign!` policy above**: the serial cutoff and the `with_threading` override
do not reach those two groups, which thread by KA's rules at every size (the
exclusion is stated on `with_threading`'s own docstring). Second, the two kernels that accumulate through `Atomix` — the anterpolation scatter and the
shell binning — sum in a **nondeterministic order**, and floating-point addition is not associative,
so they are **not bitwise-reproducible**: not across thread counts, and not even between two runs at
one thread count. Measured on a Ryzen 9800X3D over twelve trials at 8 and 16 threads, every trial
differed, `anterpolate!` by 2–3 ulp of the field's scale and `radial_spectrum` only inside
numerically-zero shells (max ``\lvert \Delta \rvert`` = 1.4e-47). The remaining kernel with **disjoint**
writes — the gather — is bitwise-reproducible, and was measured to be so across
1, 2, 4 and 8 threads, as is `helmholtz_projection!` on the gated loop it moved to. The threading suite (`test/threading.jl`) encodes exactly this split: bitwise equality asserted for
the disjoint writers (including against a subprocess launched at a different thread count, the one
comparison the in-process `with_threading` toggle cannot make for a KA kernel), a tolerance for the `Atomix` pair —
the same tolerance-not-bitwise treatment the reductions above receive, and for the same reason.

## 10. Interpolation and anterpolation (the grid↔point transfer layer)

Lagrangian particle tracking by a consumer ([§1](@ref "1. Purpose and scope")) requires two transfer operations
between the Eulerian fields and off-grid positions. They are formal adjoints of one another, and the
package gives each a fixed name:

- **Interpolation** — grid → point (the *gather* direction): evaluate a field `f` at the off-grid
  positions `xs` (a `PointSet`, ``x_p`` the ``p``-th position). Allocating
  `interpolate(f, xs[, scheme])` / in-place `interpolate!(out, f, xs[, scheme])`, plus the
  callable `f(x)` (and its broadcast `f.(xs)`) as the ergonomic face of `interpolate`.
- **Anterpolation** — point → grid (the *scatter* direction): deposit per-point quantities `qs`
  (``q_p`` the value at ``x_p``) back onto a field. Allocating
  `anterpolate(grid, xs, qs[, scheme])` / in-place `anterpolate!(field, xs, qs[, scheme])`.

Both carry the usual allocating / in-place (`!`) pair. The `α`/`β` accumulate form (``\beta = 0``
overwrite, ``\beta \ne 0`` accumulate — the `mul!` convention, since they are the linear maps ``W`` /
``W^\top``) belongs to **anterpolation alone**: accumulation is what a scatter needs, and it is the
direction that writes into a preallocated field, while a gather fills a fresh point-value section. So
the pair is symmetric in name and adjointness, and asymmetric in three places: a gather yields point
values while its adjoint returns a field; the accumulate weights are taken by the scatter alone; and
only interpolation gets the callable `f(x)`, because evaluation is pointwise while its adjoint is not
(see the module docstring). The driving case is two-way coupling in the cloud-parcel DNS this package serves:
the water-vapour mass and latent heat a droplet releases on condensation (or absorbs on evaporation) must
be returned to the supersaturation and temperature fields.

**The two operations are a conserving adjoint pair.** Interpolation and anterpolation
share the **same stencil weights** ``w``, which form a partition of unity (``\sum w = 1``);
anterpolation is then the exact adjoint of interpolation, and — since ``\sum w = 1`` — the total
deposited quantity is conserved: summed over the grid, the scattered field equals the input summed over
the points, in each fiber component. Using mismatched weights injects a
spurious source/dissipation term (Sundaram & Collins 1996). For the parcel application
this is mandatory — total water and latent heat must be conserved as vapour passes
between droplets and the fields — so the design fixes anterpolation as the adjoint of
whatever interpolation kernel is in use. The function–measure duality underlying this
adjointness — evaluation as pairing with a Dirac mass, ``f(x) = \delta_x(f)``, and anterpolation
as the pushforward of point masses against the normalized counting measure, ``\tfrac{1}{M}\sum_p q_p \delta_{x_p}`` (regularized to ``\tfrac{1}{M}\sum_p q_p w(\cdot - x_p)``,
i.e. a regularized point source) — is given in full in the `Interpolation` module docstring.

Those two facts — adjointness and a partition-of-unity reproduction — are the commuting identities below.
The two inner products are concrete pairings against the measure each base carries: on point-values
``a, b`` the **counting measure** makes ``\langle\cdot,\cdot\rangle_{\mathrm{pts}}`` a sum over the ``M``
points, while on fields ``f, g`` the **cell-volume measure** makes
``\langle\cdot,\cdot\rangle_{\mathrm{grid}}`` a volume integral over the box ``\Omega`` (with ``\cdot`` the
fiber contraction — the ordinary product for scalars, the dot product for vectors). Both are
**normalized by the total measure** — divided by ``M`` and by ``|\Omega|`` respectively, as the displays
below carry — which is what makes them intensive averages rather than extensive totals, and it is
precisely that normalization the ``N/M`` factor further down is accounting for:

```math
\begin{gathered}
\langle a, b\rangle_{\mathrm{pts}} = \frac{1}{M} \sum_{p=1}^{M} a_p\cdot b_p, \\
\langle f, g\rangle_{\mathrm{grid}} = \frac{1}{|\Omega|}\int_{\Omega} f(x)\cdot g(x)\,\mathrm{d}x
= \frac{1}{N} \sum_{x} f(x)\cdot g(x),
\end{gathered}
```

each normalized by its total measure — the ``M`` points, and the box volume ``|\Omega|`` (equivalently
the ``N`` grid cells) — exactly as the package's `inner` computes them. Writing
``\operatorname{sample}_{\mathrm{grid}}`` for sampling a function at the grid nodes,
``\operatorname{eval}_{\mathrm{pts}}`` for evaluating it at the points, and ``\phi`` for any polynomial in
``\Pi_d`` (the polynomials up to the scheme's reproduction degree ``d``), the adjointness and the polynomial reproduction read

```math
\begin{gathered}
\sum_{p} (W f)_p\cdot q_p = \sum_{x} f(x)\cdot(W^{\top} q)(x), \\
W \bigl(\operatorname{sample}_{\mathrm{grid}} \phi\bigr) = \operatorname{eval}_{\mathrm{pts}} \phi
\quad (\phi \in \Pi_d),
\end{gathered}
```

the left is the plain transpose ``W^{\top}`` — the partition-of-unity scatter `anterpolate` applies;
normalizing each side by its base count gives the measure-weighted ``M \langle W f, q\rangle_{\mathrm{pts}} =
N \langle f, W^{\top} q\rangle_{\mathrm{grid}}`` (``N`` grid nodes, ``M`` points — the ``N/M`` is just the two
normalizations). Intrinsically the pair is a
**pullback–pushforward**: writing ``\iota : B_{\mathrm{points}} \to \Omega`` for the map from the point base
``B_{\mathrm{points}}`` to the torus ``\Omega`` that carries each point to its location ``x_p``, pulling the
**trivial** bundle back along ``\iota`` keeps
the fiber and changes only the base, ``B_{\mathrm{points}} \times V = \iota^{*}(\Omega \times V)`` — a
**base-change, not a fiber operation** (decision 19):

```math
\begin{CD}
B_{\mathrm{points}} \times V @>{\iota \times \mathrm{id}_V}>> \Omega \times V \\
@V{\pi}VV @VV{\pi}V \\
B_{\mathrm{points}} @>>{\iota}> \Omega
\end{CD}
```

Interpolation is the **pullback of the section**, ``W = \iota^{*} \otimes \mathrm{id}_V`` (fiber-preserving —
the trivial bundle leaves the fiber by the identity; ``(Wf)_p = f(x_p)``); anterpolation the
**pushforward of the dual measure**, ``\iota_{*}`` (``\iota_{*} q = \tfrac{1}{M}\sum_p q_p \delta_{x_p}``,
the Dirac mass above regularized by the stencil — pushed forward against the **normalized** counting
measure, the same one ``\langle\cdot,\cdot\rangle_{\mathrm{pts}}`` uses, which is what puts the ``1/M``
there and makes the identification below come out at ``N/M`` rather than ``N``). That pushforward lands in **measures**, while
``(N/M) W^{\top} q`` is a **section**; the two are identified only after regularizing by the stencil and
taking the density with respect to the normalized grid measure, and with those two steps understood
``\iota_{*} = (N/M) W^{\top}`` for the uniform measures, the
scalar rescaling that turns the implemented transpose ``W^{\top}`` into the exact L²-adjoint. They have
**opposite variance** — ``\iota`` pulls a function back but pushes a measure forward — so the adjointness
*is* their adjunction ``\langle \iota^{*} f, q\rangle_{\mathrm{pts}} = \langle f, \iota_{*} q\rangle_{\mathrm{grid}}``. (Strictly ``W`` is ``\iota^{*}`` *after* a
reconstruction — the spline or band-limited spectral interpolant lifting grid samples to a section over
``\Omega`` — which the reproduction identity above shows is exact on ``\Pi_d``.)

**Two scheme families (decision 23).** The `scheme` argument is an
`AbstractTransferScheme` — the choice of *kernel* and *representation* that realizes ``W`` / ``W^\top``
(the commutative-diagram view above: a scheme is how the Dirac ``\delta_{x_p}`` is realized). Two
families share the same `interpolate`/`anterpolate` verbs and the same adjointness contract:

- **Physical-domain splines** (`AbstractSplineScheme`) — local kernels on the **physical** nodal
  values (the gather/scatter kernels below); approximate, conserving, the production default.
- **Spectral-domain exact transfer** — acting on a field in **spectral** representation, the literal
  inverse/forward DFT ``f(x_p) = \tfrac{1}{N}\sum_k \hat f(k) e^{\mathrm{i} k\cdot(x_p-o)}`` and its adjoint
  ``(W^\top q)(k) = \sum_p q_p e^{-\mathrm{i} k\cdot(x_p-o)}`` (here ``N`` is the grid-point count, ``o`` the
  grid origin, and ``x_p`` the ``p``-th sample point). The gather's ``\sum_k`` runs over the **full**
  spectrum; the equivalent sum over the *stored* rfft half — carrying the Parseval weight ``\alpha(k)``
  (the per-mode multiplicity: ``1`` where a stored coefficient represents only itself, ``2`` where it
  stands for a conjugate pair the half-spectrum dropped) and a real part, which is what the code
  evaluates — is written out where `DirectDFT` is detailed
  below, and is worth reading before anyone reproduces the compact form against a half-spectrum array. `DirectDFT` is the exact ``O(NM)`` form — the
  *definition* of the spectral-domain pair, hence a transparent baseline, the divergence-free
  reference (it reproduces the band-limited field exactly, matching `to_physical` at the nodes), and
  the oracle for the fast `NUFFT` (the ``O(N\log N + M)`` windowed gridding version, owned natively —
  spread → FFT → deconvolve, reusing the spline kernels with a window, an oversampled
  `FieldTransformPlans`, and an `assignment_window`-style deconvolution; exact to a requested tolerance
  ``\varepsilon`` on the resolved band). The adjoint relation carries
  the measure factor as for the splines: ``M \langle W\hat f, q\rangle_{\mathrm{pts}} = N \langle \hat f, W^\top q\rangle_{\mathrm{grid}}``.

**Method: the local splines (the physical-domain family).** The package uses the local high-order spline
interpolation of **Lalescu, Teaca & Carati (2010)**, as implemented in the **TurTLE**
code (Lalescu et al. 2022). At its core it is Hermite interpolation
with the node derivatives supplied by finite differences, which makes the interpolant
simultaneously local, high-order, and smooth; in the cubic four-point case it reduces to
the Catmull–Rom spline (Catmull & Rom 1974). Concretely `f(x)` is a tensor-product
weighted sum ``\sum w_{i_1} w_{i_2} w_{i_3}  f(c+i)`` over a compact ``(2n{+}2)^3`` stencil
(``n`` the per-axis finite-difference half-width) — ``c`` the grid cell containing ``x`` and ``i`` the
integer node offset within the stencil — with closed-form polynomial weights ``w``. Lalescu's **two hierarchies** share this stencil: the **smooth**
hierarchy (`LalescuSpline(n, m)`) is a two-point Hermite of degree ``2m{+}1`` that matches the
value and the first ``m`` derivatives at the two bracketing nodes (``C^m``, ``0 \le m \le 2n``; ``m = 0``
is linear, ``n = 1, m = 1`` is Catmull–Rom), and the **Lagrange** hierarchy (`LagrangeSpline(n)`)
is the ``C^0`` degree-``2n{+}1`` interpolant of all ``2n{+}2`` nodes. Field derivatives needed for the velocity gradient /
deformation tensor are obtained by differentiating the same local polynomial, not from a
separate field. Three properties make it the right fit:

1. **Single representation, no global precompute.** The weights act directly on the
   real-space nodal values, so interpolation acts only on the physical representation — unlike the
   spectral-domain schemes (`DirectDFT`, `NUFFT`; decision 23, below), which act on the spectral
   representation directly and reconstruct the band-limited field exactly. (The B-spline interpolation
   of van Hinsberg et al. (2012) — whose coefficients require a *global* transform that, in a spectral
   code, costs one FFT — is the higher-accuracy *local* alternative still in reserve.)
   **PLANNED — the van Hinsberg global B-spline (needs a design discussion before coding):** a
   coefficient pre-transform, then a compact local stencil — higher accuracy per stencil width, at the
   cost of a global solve that breaks the "single representation" property, so it needs a
   coefficient-field type and a transform step. It would slot under `AbstractTransferScheme` but
   changes the data flow (a global precompute), so it is a recorded *future direction*, not a drop-in
   scheme. (The other once-planned alternative — exact spectral transfer — is **done**: the
   ``O(NM)`` `DirectDFT` oracle and the fast `NUFFT`, owned natively with no `NonuniformFFTs.jl`
   dependency, under `AbstractTransferScheme`; decision 23.) See item 17 and the references below.
2. **GPU-friendly** (the GPU-first invariant, [§1](@ref "1. Purpose and scope")): per-point interpolation is a gather
   of ``(2n{+}2)^3`` neighbours plus a fused multiply–add — embarrassingly parallel, no FFT, no
   global solve, no communication beyond the periodic stencil wrap. Anterpolation is the
   matching scatter.
3. **Trivial, conservative anterpolation:** the same closed-form ``w`` deposit a point's
   source over its stencil with ``\sum w = 1`` — exactly the conserving two-way-coupling
   feedback the parcel DNS needs.

The interpolation order is a tunable parameter `(n, m)`, not hard-wired, so accuracy can
be matched to the spectral resolution (standard practice for pseudospectral particle
tracking). The transfer kernels are implemented as portable KernelAbstractions gather/scatter
kernels (the scatter accumulates atomically); the smooth per-axis weights are generated for any
`(n, m)` by a small linear solve — match the value and the order-`1…m` centred-finite-difference
(Fornberg 1988) derivatives at the two bracketing nodes — and **pinned to 1e-12 against TurTLE's
`beta_n{n}_m{m}`** (`n` ↔ `interp_neighbours`, `m` ↔ `smoothness`), with the closed-form Catmull–Rom
(`n = 1, m = 1`) as an independent anchor. The smooth scheme reproduces polynomials to degree
``\min(2m+1, 2n)`` for ``n \ge 1``; the Lagrange scheme to degree ``2n+1``. The bound needs that scope because
the two-point `n = 0` stencil is linear and reproduces degree 1, where the formula would read 0.

**Data types — the unstructured base, in the package's own language.** Interpolation needs
to name two new objects: off-grid locations and the field values there. The package names
them in its base/fiber vocabulary, *not* as particles — deliberately, because
`GBGPeriodicFields` is a **math backend** ([§1](@ref "1. Purpose and scope")): "particle"/"tracer" is the consumer's
interpretation (a location with physical attributes and an equation of motion), not a
primitive here. The organizing principle reuses the existing base/fiber split: a field is a
*section* — fibers (scalar, `FiberVector`, `FiberTensor2`) over a *base* — and so far the
base has always been the structured `Grid3D`. Interpolation adds the **unstructured base**
and its section, reusing the *same* fibers; the maps between sections over the two bases are
interpolation ``W`` and its adjoint anterpolation ``W^\top`` (the same
``W``/``W^\top`` used above).

- **`Point{T} = SVector{3,T}`** — a single position; a base-space *alias* of `FiberVector`
  (same representation, different role). An alias, not a wrapper, so consumer arithmetic
  stays StaticArrays-native (invariant 8); position vs. value is a distinction of role, not
  dispatch.
- **`PointSet`** — `M` positions in **structure-of-arrays** layout `(M, 3)` (point index
  first, coordinate last — each coordinate axis contiguous across points, mirroring the
  field's fiber-last `(Nx,Ny,Nz,3)` for coalesced GPU gather). Grid-free: periodicity wraps
  any coordinate, so positions are untethered from a grid; the field supplies the grid at
  transfer time.
- **`PointValues`** — the section over a `PointSet`, as **three concrete types mirroring the
  field zoo** — `ScalarPointValues` / `VectorPointValues` / `TensorPointValues{R}` under an
  abstract `AbstractPointValues`, SoA layout `(M,)` / `(M,3)` / `(M,3,3)`. They are
  **representation-free**: a point value is always a physical-space quantity (even exact
  spectral interpolation *produces* physical values), so there is no physical/spectral split
  here, unlike the field types.

All wrap a generic `AbstractArray` and allocate via `similar`, so they are backend-generic
(CPU / CUDA / AMDGPU) for free; compatibility reduces to `M`-matching and matching tensor
order (a `_check_…` predicate in the `Fields` style). The types live in the `Points`
module, importing `Fields` helpers via an explicit `using ..Fields: …`.

**Implemented and tested.** The point types, their full fiberwise algebra (M2 + M3, generated by reusing `FieldAlgebra`'s per-component builders over an extended section interface — [§6](@ref "6. The code-generation architecture of `FieldAlgebra`") — and locked by a separate 122-method parity baseline, the 206-method field surface byte-unchanged), and all transfer schemes (the local splines plus the spectral `DirectDFT`/`NUFFT`, decision 23) are implemented and covered on CPU (Float64/Float32) and the GPU (ROCm, `allowscalar(false)`).

**Why the code says "anterpolation."** The point→grid (scatter) operation is named
differently in every community, with no dominant choice: *spreading* (immersed-boundary
method, where it is explicitly the adjoint ``S = J^*`` of interpolation, built from the
same kernel — Peskin 2002; also NUFFT type-1), *deposition* / *charge assignment*
(particle-in-cell — Hockney & Eastwood 1988; Birdsall & Langdon 1991), *scatter*
(data-parallel computing), *projection* / *Particle-Source-In-Cell* (particle-laden-flow
DNS — Crowe, Sharma & Stock 1977), *gridding* (MRI and radio interferometry), and, in
cloud microphysics, no operator noun at all — only the *source/sink term* it produces
and the *two-way coupling* / *thermodynamic feedback* it enacts. We adopt
**anterpolation** (Brandt & Lubrecht 1990) because it is the single term whose literal
definition is "the adjoint of interpolation" — it names the operation by the property
that matters, independent of application. The binding carries a docstring listing the
synonyms — *adjoint of interpolation; spreading; deposition; scatter; projection /
PSI-Cell; gridding; two-way-coupling source/feedback* — so a reader from any of those
fields finds it. **"Extrapolation" is deliberately rejected**: extrapolation means
evaluating *outside* the convex hull of the data, whereas a sample point lies *inside* a
grid cell and the operation is a weighted distribution; the loose use of "extrapolation"
for it (seen in a few papers) is a misnomer.

**Base-space motion: `displace!` and `wrap!` (decision 73).** The transfer verbs above move field
*values* between the grid and the points; nothing above moves the *points*. The consuming solver's
trajectory update is exactly that missing operation — each position advanced along a weighted sum of
vector values held over it, ``x_p \leftarrow x_p + \sum_j c_j v_j(p)``, where ``x_p`` is the
position of point ``p``, the ``v_j`` are `VectorPointValues` sections (each holding one vector value
per point), and each ``c_j`` is one plain real number — one scalar per term of the sum, not a
per-point array — and until this decision it could only be
written by unwrapping the storage and broadcasting on raw arrays, outside every contract the layer
states. The geometry says it is a legitimate operation and says where its boundaries are. On this
package's flat periodic base with its one global orthonormal frame
([§2](@ref "2. The central principle: the architecture follows established mathematics")), the tangent space at every point is
canonically the fiber's Cartesian ``\mathbb R^3``, so a vector value over a point defines a
displacement with no connection machinery: displacement is coordinate addition. It is a **named
operation and not a `+` method**, because positions are points of the periodic domain, not vectors —
an algebra on positions would assert a linear structure the base does not have, and the
position-versus-value role split stays intact. And it comes in two forms the type structure itself
dictates: a `PointSet` deliberately carries no grid, so `displace!` **without** a grid cannot wrap
and is displacement in the universal cover ``\mathbb R^3`` — the unwrapped torus, where a
      coordinate keeps growing instead of folding back (winding preserved — a mean-square
displacement needs it), while `displace!` **with** a trailing `Grid3D` is displacement on the torus
proper, the wrap fused into the same pass. The call `wrap!(points, grid)` is the zero-term case kept as its
own named verb: reduction to the canonical representative in the half-open fundamental domain
``[o_a, o_a + L_a)`` per axis — origin-aware, with the floating-point endpoint folded (`mod` can
return the period itself for a coordinate a hair below the origin) and non-finite coordinates passed
through non-finite, so a diverged trajectory is never silently rewritten into a tidy in-box
position. Sampling never requires the wrap — the transfer kernels wrap their stencil indices, so
interpolation is invariant under shifting a coordinate by whole periods — but canonicalization is
load-bearing for precision on long runs (absolute floating-point resolution degrades as a coordinate
grows), which is why the wrap is a package contract and not consumer hygiene. The coefficients are
part of what the operation *is*, so they are not the α/β accumulation scalars and the operation
takes no trailing α/β (the `combine!` precedent); there is deliberately no allocating sibling,
displacement being motion of an existing base. The ``n``-term form runs in one fused traversal —
positions read once, each section once, positions written once — which collapses a ``K``-step
Adams–Bashforth update from ``K`` passes to one.

**References.** The canonical list for the WHOLE document — every section and every docstring cites
into it, which is why the citation policy and the `check-docs` DOI cross-check both name it
§References. It sits here because the transfer literature is its largest single block, not because
its scope is this section.

- C. C. Lalescu, B. Teaca, D. Carati, [*Implementation of high order spline interpolations for tracking test particles in discretized fields*](https://doi.org/10.1016/j.jcp.2009.10.046), J. Comput. Phys. **229**(17) (2010) 5862–5869.
- C. C. Lalescu, B. Bramas, M. Rampp, M. Wilczek, [*An efficient particle tracking algorithm for large-scale parallel pseudo-spectral simulations of turbulence*](https://doi.org/10.1016/j.cpc.2022.108406) (TurTLE), Comput. Phys. Commun. **278** (2022) 108406; arXiv:2107.01104. Code: gitlab.mpcdf.mpg.de/TurTLE/turtle.
- M. A. T. van Hinsberg, J. H. M. ten Thije Boonkkamp, F. Toschi, H. J. H. Clercx, [*On the efficiency and accuracy of interpolation methods for spectral codes*](https://doi.org/10.1137/110849018), SIAM J. Sci. Comput. **34**(4) (2012) B479–B498.
- A. H. Barnett, J. Magland, L. af Klinteberg, [*A parallel nonuniform fast Fourier transform library based on an exponential of semicircle kernel*](https://doi.org/10.1137/18M120885X), SIAM J. Sci. Comput. **41**(5) (2019) C479–C504.
- B. Fornberg, [*Generation of finite difference formulas on arbitrarily spaced grids*](https://doi.org/10.1090/S0025-5718-1988-0935077-0), Math. Comp. **51**(184) (1988) 699–706.
- S. Sundaram, L. R. Collins, [*Numerical considerations in simulating a turbulent suspension of finite-volume particles*](https://doi.org/10.1006/jcph.1996.0064), J. Comput. Phys. **124**(2) (1996) 337–350.
- C. T. Crowe, M. P. Sharma, D. E. Stock, [*The Particle-Source-In-Cell (PSI-CELL) model for gas–droplet flows*](https://doi.org/10.1115/1.3448756), J. Fluids Eng. **99**(2) (1977) 325–332.
- A. Brandt, A. A. Lubrecht, [*Multilevel matrix multiplication and fast solution of integral equations*](https://doi.org/10.1016/0021-9991%2890%2990171-V), J. Comput. Phys. **90**(2) (1990) 348–370 (an early use of "anterpolation" for the adjoint of interpolation).
- C. S. Peskin, [*The immersed boundary method*](https://doi.org/10.1017/S0962492902000077), Acta Numerica **11** (2002) 479–517 (spreading = adjoint of interpolation).
- R. W. Hockney, J. W. Eastwood, [*Computer Simulation Using Particles*](https://doi.org/10.1201/9780367806934), Adam Hilger, Bristol, 1988 (deposition / charge assignment; the NGP and CIC windows).
- C. K. Birdsall, A. B. Langdon, [*Plasma Physics via Computer Simulation*](https://doi.org/10.1201/9781315275048), Adam Hilger, Bristol, 1991 (deposition / charge assignment).
- J. M. Domínguez, A. J. C. Crespo, M. Gómez-Gesteira, J. C. Marongiu, [*Neighbour lists in smoothed particle hydrodynamics*](https://doi.org/10.1002/fld.2481), Int. J. Numer. Methods Fluids **67**(12) (2011) 2026–2042 (cell traversal order for neighbour search; corroborates decision 78's own measurement that lexicographic block order beats Z-order/Morton for this access pattern).
- E. Catmull, R. Rom, [*A class of local interpolating splines*](https://doi.org/10.1016/B978-0-12-079050-0.50020-5), in: Computer Aided Geometric Design, Academic Press, 1974, pp. 317–326.
- L. Grafakos, [*Classical Fourier Analysis*](https://doi.org/10.1007/978-1-4939-1194-3), 3rd ed., Graduate Texts in Mathematics **249**, Springer, 2014
  (Thm 2.5.10: on a uniform periodic box every homogeneous linear operator is a Fourier multiplier — the math anchor for decision 19's taxonomy). It is cited by that anchor rather than by this section, and
  is kept in this list as the document's single Fourier-analysis reference.

## 11. Convolution

!!! note "The current shape of the kernel protocol is here, not in the decision log"
    The [decision log](@ref "Decision log — GBGPeriodicFields") records how the kernel design
    *arrived* — decisions 19, 20, 21, 50, 51, 56, 60, 61 and 62 each
    changed part of it, and several supersede earlier ones. Reconstructing the present state from that
    chain is not the intended reading. This section is the current state: **a kernel is its own kind of
    object, never a field**; `SpectralKernel` is the abstract supertype of four storage classes —
    `StoredKernel` (one coefficient per mode), `SeparableKernel` (per-axis factors), `RadialKernel` (a
    symbol of ``\lvert k\rvert^2``) and `ProductKernel` (any two held unmultiplied); all four are
    interchangeable wherever a kernel is *applied* and agree bit for bit on the host (on a device a
    *complex*-valued kernel is the one exception, the classes agreeing there to rounding), `materialize_kernel` expands a
    compressed one, and `inv` and `weighted_inner` are the two entry points with narrower contracts.

`Convolution` is the **kernel-multiplier** role of the measure structure: periodic (circular) convolution of a field with a
kernel, in spectral representation. By the convolution theorem ([§2](@ref "2. The central principle: the architecture follows established mathematics")), ``f \star g`` is the coefficientwise
product ``\hat f \cdot \hat g``; `convolve`/`convolve!` (``\equiv \star``, also exported as the infix operator `⋆`) apply a kernel — a `SpectralKernel`,
in any of its storage classes — whose transfer function ``\hat g`` multiplies every fiber component (one method for
scalar, vector, and tensor fields), with the α/β accumulate form and alias-safety of a coefficientwise op.
It is the **spectral sibling of `DifferentialOperators`** (both are coefficientwise multipliers, [§4](@ref "4. Spectral machinery")) and the
**same-base counterpart of the `Interpolation` transfer** (decision 19); offered under its true name
`convolve`, never as `*` (invariant 1). Spectral representation only; physics (an LES filter, an integrating
factor ``\exp(-\nu |k|^2 \Delta t)``) stays a consumer-built kernel (invariant 12). Five neutral builders
ship: `spectral_cutoff` (the isotropic sharp low-pass), `spectral_band` (its annular generalization),
`radial_kernel` (any real symbol of ``|k|^2``, held as a closure),
`assignment_window` (the ``\prod_a \operatorname{sinc}^2`` CIC deconvolution window), and
`translation_kernel` (the shift theorem's phase ``e^{-\mathrm{i} k\cdot h}``, which displaces a field by a
physical offset ``h``). The first four are real and even in the wavenumber ``k``; `translation_kernel` is
the one **complex** kernel, and the reality condition a complex kernel must meet — the Hermitian symmetry
``\hat g(-k) = \overline{\hat g(k)}``, equivalently a real physical-space kernel ``g`` — is what forces its
value at the Nyquist frequency to be a real attenuation rather than a phase (decision 28). Two fused
forms extend the family without a stored kernel or an extra pass (decision 33):
`exponential_convolve!`/`exponential_convolve` apply the exponential radial kernel
``\exp(c |k|^2 + s \hat w)`` evaluated lazily from the wavenumber arrays (for ``c \le 0`` the periodic
Gaussian ``e^{-c\Delta}``; ``\hat w`` an optional real per-mode exponent field entered as scale times
field, ``s`` its scale), in single-field and weighted-two-field forms; and the kernel-composed
`combine!` method convolves a weighted combination ``\hat g \cdot (\alpha \hat a + \beta \hat b)`` in
the same fused pass — the decision-32 composition idiom (the operation's own verb, a trailing kernel
argument) applied to the combination. See decisions 20, 21, 22, 28, 33.

## 12. Reductions

`Reductions` is the **L² / measure** family — the third operation family, integrating a section over its
base against the measure the base carries (`Grid3D`'s uniform cell volume, `PointSet`'s counting measure;
decision 18). The `integral` (``\equiv \int\,\mathrm{d}\mu``) is the extensive sum; `inner` (``\equiv \langle\cdot,\cdot\rangle``),
`l2norm`, and `lpnorm` are the normalized L² product and norms, and `weighted_inner`
(``\equiv \langle\cdot, w \cdot\rangle``) is the spectral multiplier-weighted product ``\langle f, w g\rangle`` —
the reduction-dual of `convolve`, generalizing `inner` (decision 27); `mean`/`std`/`var`/`cov` (extending `Statistics`)
and `maximum`/`minimum`/`extrema` (extending `Base`) the order statistics, all acting on **fields in physical representation
and point-values** (representation-free); `cov` returns the vector second *central* moment as a symmetric
``\mathrm{Sym}^2(V)`` tensor, which a fiber-preserving `var` would reduce to its basis-dependent diagonal.
The scalar-only `std`/`var` additionally read from **spectral** representation through Parseval
(decision 49), built from ``\langle f,f\rangle - \langle f\rangle^2`` — Bessel-scaled for `var`, its square
root for `std` — both terms already spectral-available. The reductions `inner`/`l2norm` *also* act on a field in **spectral** representation
via Parseval's theorem (equal to the physical inner, no transform; the rfft half-spectrum weighting), and
`integral`/`mean` via the zero (DC) Fourier mode — ``\hat f(0) = \sum_x f`` gives the mean ``\hat f(0)/N``
and the integral ``(|\Omega|/N) \hat f(0)``, no transform. The **radial**
pair are spectral/physical duals: `radial_spectrum` (the shell-resolved `inner` — the power spectrum) and
its Wiener–Khinchin dual `radial_correlation` (the two-point autocorrelation
``C(r) = \mathcal F^{-1}(|\hat f|^2)/N``), each with a two-field **co-spectrum** form. Five of them —
`integral`, `mean`, `maximum`, `minimum` and `extrema` — additionally have a **mapped** form taking a leading function — a map applied to the section's fiber value
at every base point, so `mean(det, A)` averages a determinant and `maximum(norm, u)` takes a supremum of
magnitude, each reduced in one pass with no intermediate section (decision 30). Physics (kinetic
energy ``\tfrac{1}{2}\langle u,u\rangle``, dissipation, rms) stays consumer-side. See decisions 18, 21, 22, 30.


## Decision log

The decision log is its own document: [`docs/DECISIONS.md`](@ref "Decision log — GBGPeriodicFields").
It is append-only and is cited from here, and from the source, as "decision N".
