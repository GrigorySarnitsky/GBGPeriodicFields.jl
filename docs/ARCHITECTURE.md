# Architecture — GBGPeriodicFields

This document records the architecture of the package and, more importantly, *why*
it is the way it is. It exists so that future work (human or AI) extends the design
instead of accidentally reverting it. `CLAUDE.md` carries the operational summary;
this file carries the reasoning — and, since the umbrella module's AI-tips block was merged in, the
conceptual model (§2) and the writing/docstring conventions (the §2 documentation policy) as well.

This file is **self-contained**: every piece of notation — a mathematical symbol (in LaTeX) or a
`code` identifier — is introduced in plain language at its first use, the meaning stated before or in
the same sentence as the symbol. So it reads top-to-bottom, and each [§13](@ref "13. Decision log") decision-log entry reads on
its own, without opening the source or another document. (Universally standard math — ``\nabla``,
``\Delta``, ``\int``, ``\mathbb R`` — may stand unglossed.) Keep it that way when editing.

## 1. Purpose and scope

The package is the field layer for pseudospectral simulation of incompressible
fluid dynamics and turbulence on three-dimensional rectangular periodic domains. Its
primary consumer is [`GBGIsotropicTurbulence.jl`](https://grigorysarnitsky.github.io/GBGIsotropicTurbulence.jl), a direct numerical simulation of
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
section of ``E`` to a section of ``T^{*}\Omega \otimes E``, and the frame identifies ``T\Omega`` with
``V``, so the package can type ``\nabla u`` as a fiber tensor of one order higher with no raising or
lowering to track. That single global frame is **orthonormal**, so the fiber carries the ordinary Cartesian Euclidean
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
  divergence, curl, Laplacian are derivatives *along the base*, using the flat
  connection of the periodic box ([§4](@ref "4. Spectral machinery")). Read that
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
   `ROCArray` and a `reshape` of any of them all pass. `mul!` keeps
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
    is [`adapt`](@ref) (decision 63), and crossing **precisions** remains future work.

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

The coefficientwise product *downstairs* is **convolution** upstairs (offered as `convolve` ``\equiv \star``,
[§11](@ref "11. Convolution")); the pointwise product ``f \cdot g`` transforms to a convolution with **no** coefficientwise spectral
form — exactly why those nonlinear operations are physical-space only.

The same finiteness makes a nonlinear result **aliased**. A product doubles the spectral band — the
determinant (a triple product) triples it, a non-polynomial map such as the norm is unbounded — so content
beyond the grid's Nyquist (highest stored) wavenumber folds back onto the resolved modes when the
physical result is transformed to spectral representation. The gridpoint values themselves stay exact; the
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
  and no natural verb) take that **noun**: `gradient`, `divergence`, `curl`, `laplacian`,
  `inverse_laplacian`, `helmholtz_projection`.
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
correspondence is never left implicit: `gradient` ``\equiv \nabla``, `divergence` ``\equiv \nabla\cdot``, `curl`
``\equiv \nabla\times``, `laplacian` ``\equiv \Delta``, `inverse_laplacian`
``\equiv \Delta^{-1}``, `helmholtz_projection` ``\equiv \mathbb{P}``, `inner`
``\equiv \langle\cdot,\cdot\rangle``, `l2norm` ``\equiv \lVert\cdot\rVert_2``, `integral`
``\equiv \int\,\mathrm{d}\mu``, `convolve` ``\equiv \star``, `interpolate`/`anterpolate`
``\equiv W``/``W^\top``, `to_spectral`/`to_physical` ``\equiv \mathcal F``/``\mathcal F^{-1}``,
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
``\equiv \nabla``, `divergence` ``\equiv \nabla\cdot``, `curl` ``\equiv \nabla\times``, `laplacian`
``\equiv \Delta`` — is *diagonalized* by it into a pointwise multiplier ``\hat L = m(k) \cdot`` (``\mathrm{i}k``,
``\mathrm{i}k\cdot``, ``\mathrm{i}k\times``, ``-|k|^2``):

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
up, in `check_field_compatibility` only, because the domain check must let order differ for the
operators that change it (`gradient`, `divergence`). Composed on top are the representation-dispatched
`_check_field_domain_compatibility` (physical-physical and spectral-spectral
methods — the dispatch barrier that prevents cross-representation mixing), the
unexported `check_field_compatibility` (un-prefixed, but documented with the internals), and `_check_field_matches_context` for
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
`check_field_compatibility` before `_copy_field_data!`.

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
`section_scalar_type` — is written exactly once.

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
\langle a, b\rangle_{\mathrm{pts}} = \frac{1}{M} \sum_{p=1}^{M} a_p\cdot b_p,
\qquad\qquad
\langle f, g\rangle_{\mathrm{grid}} = \frac{1}{|\Omega|}\int_{\Omega} f(x)\cdot g(x)\,\mathrm{d}x
= \frac{1}{N} \sum_{x} f(x)\cdot g(x),
```

each normalized by its total measure — the ``M`` points, and the box volume ``|\Omega|`` (equivalently
the ``N`` grid cells) — exactly as the package's `inner` computes them. Writing
``\operatorname{sample}_{\mathrm{grid}}`` for sampling a function at the grid nodes,
``\operatorname{eval}_{\mathrm{pts}}`` for evaluating it at the points, and ``\phi`` for any polynomial in
``\Pi_d`` (the polynomials up to the scheme's reproduction degree ``d``), the adjointness and the polynomial reproduction read

```math
\sum_{p} (W f)_p\cdot q_p = \sum_{x} f(x)\cdot(W^{\top} q)(x),
\qquad\qquad
W \bigl(\operatorname{sample}_{\mathrm{grid}} \phi\bigr) = \operatorname{eval}_{\mathrm{pts}} \phi
\quad (\phi \in \Pi_d),
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
  ``\varepsilon`` on the resolved sub-Nyquist band). The adjoint relation carries
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
(Fornberg 1988) derivatives at the two bracketing nodes — and **pinned bit-for-bit against TurTLE's
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

**References (this section).**

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
- E. Catmull, R. Rom, [*A class of local interpolating splines*](https://doi.org/10.1016/B978-0-12-079050-0.50020-5), in: Computer Aided Geometric Design, Academic Press, 1974, pp. 317–326.
- L. Grafakos, [*Classical Fourier Analysis*](https://doi.org/10.1007/978-1-4939-1194-3), 3rd ed., Graduate Texts in Mathematics **249**, Springer, 2014
  (Thm 2.5.10: on a uniform periodic box every homogeneous linear operator is a Fourier multiplier — the math anchor for decision 19's taxonomy). It is cited by that anchor rather than by this section, and
  is kept in this list as the document's single Fourier-analysis reference.

## 11. Convolution

!!! note "The current shape of the kernel protocol is here, not in the decision log"
    §13 records how the kernel design *arrived* — decisions 19, 20, 21, 50, 51, 56, 60, 61 and 62 each
    changed part of it, and several supersede earlier ones. Reconstructing the present state from that
    chain is not the intended reading. This section is the current state: **a kernel is its own kind of
    object, never a field**; `SpectralKernel` is the abstract supertype of four storage classes —
    `StoredKernel` (one coefficient per mode), `SeparableKernel` (per-axis factors), `RadialKernel` (a
    symbol of ``\lvert k\rvert^2``) and `ProductKernel` (any two held unmultiplied); all four are
    interchangeable wherever a kernel is *applied* and agree bit for bit, `materialize_kernel` expands a
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

## 13. Decision log

*Chronological and append-only — later entries supersede earlier "remaining"/"deferred"
notes (e.g. the CPU threading and the interpolation layer) rather than contradicting them.*

1. `Fields` refactor: atomic compatibility predicates; shared
   `_check_same_domain`; `_check_field_matches_context` for transforms.
2. `FieldSpectralMultipliers` moved `DifferentialOperators` → `Fields`; explicit
   six-array constructor (validated lengths) plus convenience constructor;
   host-built wavenumbers copied to the backend; **Nyquist split** between
   derivative and squared multipliers (correctness, see [§4](@ref "4. Spectral machinery")).
3. `FieldAlgebra` rewritten around code generation with the invariant that the
   public method set is reproduced exactly; M2 + M3 delivered and parity-verified
   at runtime (198 methods, the full surface). Validation rewired to direct
   `_check_field_domain_compatibility` calls — alias wrappers explicitly
   rejected.
4. Docstring policy: one docstring per operation on the bare binding, curated
   signatures + validity prose; generators never emit docstrings.
5. Operators defined in `function op(...) ... end` form (parse-proven house
   style); short form only for unary `+`.
6. GPU-first; CPU threading designed (`_assign!`, [§9](@ref "9. Performance model and CPU threading")) and deliberately deferred.
7. Refactor complete: `FieldAlgebra` loads and is parity-verified (M2 + M3, 198
   methods); `DifferentialOperators` rewired to import `FieldSpectralMultipliers`
   and its helpers from `Fields`, with the umbrella re-export corrected (the old
   five-argument constructor removed by design); reference test suite in place
   (`test/`, `Pkg.test()` green) including the method-parity baseline.
   Remaining: deferred CPU threading ([§9](@ref "9. Performance model and CPU threading")) and the planned interpolation layer.
8. StaticArrays promoted from `StaticArraysCore` to a direct dependency — the
   package indexes fibers and uses their algebra in the generated kernels, so the
   type-only core package left `field ± fiber`, `scalarfield * fiber`, and the M3
   fiber contractions undefined at runtime (see [§3](@ref "3. Types and memory layout")).
9. Transform input-preservation contract: in-place `to_physical!`/`to_spectral!`
   may overwrite their source (FFTW c2r destroys input; backend-divergent), so the
   allocating `to_physical`/`to_spectral` copy the input to keep non-`!` calls
   non-mutating (see [§4](@ref "4. Spectral machinery")).
10. GPU testing is opt-in and **dependency-free for the package**: the data layer is
    generic over `AbstractArray`, FFT plans are built through `AbstractFFTs`
    (backend-dispatched on the array type) and allocations inherit their backend via
    `similar`, so a GPU backend is only ever a *test* dependency. It lives in
    per-backend environments under `test/gpu/` (`rocm/` and `cuda/`), each
    instantiated only on matching hardware (AMD at home, NVIDIA at the office); a
    shared, backend-agnostic `suite.jl` runs the public surface on device arrays with
    `allowscalar(false)` — turning invariant 6 into a checked guarantee — and compares
    against the trusted CPU result. The default `Pkg.test()` stays backend-free, so it
    is portable across CI and every machine.
11. Test-suite buildout (beyond the GPU work in item 10): element-type genericity
    (`Float32` alongside `Float64`), anisotropic-domain operators (the ``2\pi/L`` scaling),
    in-place and alias-guard coverage, a Nyquist end-to-end test, and the operator
    **adjointness / structural identities** on randomized band-limited fields
    (``\nabla\cdot = -\nabla^\top``, self-adjoint curl, negative-**semidefinite** Laplacian — negative-definite
    on the zero-mean subspace, its kernel being the constant mode — exactly idempotent Helmholtz
    projection (decision 42) — the discrete energy/entropy structure). Intentional-absence tests are
    symmetric across representations: nonlinear products absent in spectral; the
    differential operators absent in physical (spectral-only — no finite-difference
    operators yet). `Aqua.test_all` was added, which required `[compat]` bounds for every
    dependency. Two deliberate deferrals: a global L²/integration reduction is reserved
    for *separate code* (so adjointness tests use an inline L² inner product), and
    doctests wait until the package stabilizes and tutorials are written. **The doctest deferral
    is closed:** `docs/make.jl` sets `doctest = true` and `docs/src/tutorial.md` carries `jldoctest`
    blocks, so the tutorial's examples are executed by the docs build. Coverage detail
    lives in `docs/TESTING.md`.
12. CPU threading implemented ([§9](@ref "9. Performance model and CPU threading")), realizing the design formerly deferred in items 6/9. A
    `Fields._assign!` primitive threads elementwise/fiberwise assignments on CPU
    (`Base.Threads`, contiguous chunks, bitwise-identical to serial), routed in via the
    field broadcast `copyto!` and the kernel assignments (codegen `_to_broadcasted` plus the
    `@_assign!` macro for hand-written kernels); FFTW threads are matched to Julia's at load.
    Hybrid policy: on when `nthreads() > 1` and above a ``2^{14}`` serial cutoff, with a
    task-local `with_threading` ScopedValue override; the GPU path stays on the
    `materialize!` fallback. `[compat] julia` was raised to 1.11 here (for ScopedValue); the floor has
    since moved again, to 1.12 (decision 31).
    Reductions remain deferred (separate FP-ordering design).
13. Interpolation-layer design fixed ([§10](@ref "10. Interpolation and anterpolation (the grid↔point transfer layer)")):
    grid→point **interpolation** as the callable `f(x)` / `f.(xs)` plus the named
    `interpolate` / `interpolate!`; point→grid **anterpolation** as `anterpolate` /
    `anterpolate!` — the symmetric named pair, each with allocating and in-place forms, and the
    α/β-accumulate form on the scatter only (the `mul!` convention, since they are the linear maps
    ``W`` / ``W^\top``);
    only interpolation also has the pointwise callable `f(x)` (the adjoint of interpolation;
    synonyms — spreading,
    deposition, scatter, projection/PSI-Cell, gridding, two-way-coupling feedback — listed
    on the binding; "extrapolation" rejected as a misnomer). Adjointness is explained in
    the module docstring via the function–measure duality (Dirac evaluation vs. pushforward
    of point masses). Method:
    the **Lalescu local splines** (Lalescu, Teaca & Carati 2010) as in **TurTLE**
    (Lalescu et al. 2022) — local Hermite-with-finite-difference
    derivatives, tunable `(neighbours n, smoothness m)`, single (physical)
    representation, GPU-friendly; van Hinsberg B-spline (2012) and NUFFT exact-spectral
    are the higher-accuracy / reference alternatives held in reserve. Interpolation and
    anterpolation share the same partition-of-unity weights, so anterpolation is the
    conservative transpose (Sundaram & Collins 1996) — required to conserve total water
    and latent heat in the two-way-coupled parcel DNS. Implemented (item 17).
14. Point-data types fixed ([§10](@ref "10. Interpolation and anterpolation (the grid↔point transfer layer)")) and the math-backend policy recorded. The unstructured base
    reuses the base/fiber split: `Point{T} = SVector{3,T}` (a position; an **alias** of
    `FiberVector`, not a wrapper); `PointSet` (`M` positions, **SoA** `(M,3)`, grid-free);
    and `PointValues` as **three concrete types** mirroring the field zoo —
    `ScalarPointValues` / `VectorPointValues` / `TensorPointValues{R}` under
    `AbstractPointValues`, SoA, **representation-free**. Naming is domain-neutral by policy:
    the package is a math backend, so no *particle* / *tracer* type and **no concept of time**
    (no advection / integration / temporal state) — those are the consumer's. The types live in
    `Interpolation`, importing `Fields` helpers; they are implemented and tested (only the
    transfer kernels of item 13 remain future work — see item 15 for the algebra).
15. Point-value algebra implemented ([§10](@ref "10. Interpolation and anterpolation (the grid↔point transfer layer)")): `FieldAlgebra`'s code generators are **reused
    verbatim** over an extended point-value section interface, mirroring the full *physical*
    field surface (M2 + M3, storage-wise broadcasting) with no duplicated formula; locked by a
    separate **118-method baseline** (the 198-method field surface byte-unchanged), zero
    ambiguities, tested on CPU (`test/pointvalues_algebra.jl`) and GPU (ROCm). The shared
    `AbstractFiberSection{T, R}` supertype the fiber-bundle model ([§2](@ref "2. The central principle: the architecture follows established mathematics")) invites — and the lift of
    the inlined norm/sym/skew/dev formulas into a builder — is the planned next step, not yet
    undertaken.
16. Phase A consolidation **done** ([§2](@ref "2. The central principle: the architecture follows established mathematics"), [§10](@ref "10. Interpolation and anterpolation (the grid↔point transfer layer)")). The foundation module **`FiberSections`** holds the
    base-agnostic supertype `AbstractFiberSection{T,R}` (the field and point-value types subtype
    it), the `_assign!` threading primitive, and the **vertical-algebra code generators** — the
    single home for every fiberwise formula (norm/sym/skew/dev included, via `section_scalar_type`),
    reused verbatim by `FieldAlgebra` and `Points`. The former `Interpolation` module is **split**
    into **`Points`** (unstructured-base section objects + their generated algebra — a noun peer of
    `Fields`) and **`Interpolation`** (the transfer maps — an operation peer of
    `DifferentialOperators`). The field/point asymmetry is math-mandated (no point differential
    operators, no second representation; the point algebra is a small generated emission folded into
    `Points`). Both parity baselines (198 + 118) held byte-for-byte through every step, zero
    ambiguities. (The transfer kernels themselves followed — item 17.)
17. Transfer kernels implemented ([§10](@ref "10. Interpolation and anterpolation (the grid↔point transfer layer)")): interpolation (gather ``W``, also the callable `f(x)`) and
    anterpolation (scatter ``W^\top``, with the α/β `mul!` convention) as the Lalescu local splines.
    **Both hierarchies** are provided: the smooth `LalescuSpline(n, m)` — a two-point Hermite of
    degree ``2m{+}1`` matching the value and the order-``1, \dots, m`` derivatives (centred Fornberg
    finite differences) at the two bracketing nodes, ``C^m`` with ``0 \le m \le 2n`` (`CatmullRom`, the
    cubic ``n=1, m=1``, is the default; ``m=0`` is linear) — and the ``C^0`` `LagrangeSpline(n)`, the
    degree-``2n{+}1`` interpolant of all ``2n{+}2`` nodes. The smooth weights are **pinned bit-for-bit
    against TurTLE's `beta_n{n}_m{m}`** (`n` ↔ `interp_neighbours`, `m` ↔ `smoothness`; agreement
    ``\le`` 1e-15) — an earlier "interpolate the central ``2(n{-}m){+}2`` nodes" draft was corrected
    after reading the TurTLE source, Lalescu's smooth spline being a *two-point* Hermite, not a
    central-node hybrid. Reproduction is ``\min(2m{+}1, 2n)`` for ``n \ge 1`` (smooth) / ``2n{+}1`` (Lagrange); the
    closed-form Catmull–Rom and the Lagrange cardinal
    basis are independent anchors, with partition of unity (⇒ conservation). Kernels are portable
    across CPU / CUDA / AMDGPU via **KernelAbstractions** (new dep) with the atomic scatter via
    **Atomix** (new dep); both index the native arrays linearly, so one kernel serves
    scalar/vector/tensor orders. Adjointness in the counting pairing — ``\sum_p (Wf)_p \cdot q_p = \sum_n f_n \cdot (W^\top q)_n``, the unnormalized sums over the ``M`` points and the ``N`` grid nodes — and conservation hold to roundoff;
    tested on CPU (`test/interpolation_transfer.jl`, Float64/Float32, incl. the TurTLE pin) and GPU
    (ROCm). Physical-space only. The kernels loop with the **contiguous (x) axis innermost**
    (stride-1 stencil access) — a measured GPU-first choice (≈1.6× at 256³, ≈3.9× for the 512³
    Lalescu on a since-retired card), re-affirmed on CPU in the decision-37 production band: the 512³
    Zen 5 A/B found z-inner ~10% ahead only on the narrow Catmull–Rom stencil and 23% *behind* on
    the wide Lalescu one, so x-inner stands on both platforms and the reopened tiebreak is closed
    (`PERFORMANCE.md` §4b).
    The measure-consistent adjoint against the two **normalized** pairings is ``(N/M) W^\top`` (``N`` grid
    points, ``M`` sample points; the factor is the ratio of the ``1/N`` and ``1/M`` normalizations, not of
    a cell volume) — both base measures are uniform,
    so it is a scalar rescaling of the counting-transpose anterpolation, not a new operation — and is
    verified via `inner` as ``M \texttt{inner}(Wf, q) = N \texttt{inner}(f, W^\top q)`` (`test/interpolation_transfer.jl`, decision 19).
18. **The L² / measure structure on sections — the third operation family (done).** Advances
    the reduction deferral of items 6/11/[§9](@ref "9. Performance model and CPU threading"). The package's operations split into **vertical**
    (fiberwise, pointwise — `dot`, `norm`, `cross`; return sections), **horizontal** (differential —
    `gradient`, …; return sections), and now **base reductions** — integrate the base away against a
    **measure** it carries; return a fiber value or a scalar. Math grounding ([§2](@ref "2. The central principle: the architecture follows established mathematics")): a section lives in
    ``L^2(\mathrm{base}, \mu) \otimes V`` — the fiber ``V`` is a tensor factor, not flattened away — and
    the inner product pairs the two factors — the fiber contraction is the metric pairing on ``V``
    (cf. **Manifolds.jl** `inner(M,p,X,Y)`, a fiber-level pairing) and the base integral is the
    ``L^2(\mathrm{base}, \mu)`` factor —
    the measure is an explicit object (cf. **Gridap.jl** `Measure`, **MeasureTheory.jl**), and the
    moments are the canonical reductions (cf. `Statistics` `mean`/`std`/`var`). All dispatch on
    `AbstractFiberSection`, so fields **and** point-values share one set of formulas (`FiberSections`
    "write it once").

    *The measure is a property of the base.* `Grid3D` → uniform Lebesgue quadrature (cell volume
    ``\prod_i \Delta x_i``); `PointSet` → **counting** measure (unit weight per point) — and this is
    *forced*, not a choice: a `PointSet` is grid-free ([§10](@ref "10. Interpolation and anterpolation (the grid↔point transfer layer)"), carries no domain), so the only well-defined
    measure is counting. Consequences:

    `integral(f)` is the **extensive** sum against the measure, `mean(f)` the **intensive** average
    ``\texttt{mean}(f) = \tfrac{1}{\mathrm{count}}\sum f`` — per base:

    - `Grid3D` (``N`` cells): ``\texttt{integral}(f) = \int_\Omega f\,\mathrm{d}x = (\lvert\Omega\rvert/N)\sum f``, ``\texttt{mean}(f) = \tfrac{1}{N}\sum f``.
    - `PointSet` (``M`` points): ``\texttt{integral}(f) = \sum f``, ``\texttt{mean}(f) = \tfrac{1}{M}\sum f``.

    So `mean` is the arithmetic average over base elements in both cases — ``\tfrac{1}{M}\sum`` over points
    (a plain sample mean), ``\tfrac{1}{N}\sum`` over the grid (which, the grid being uniform, equals the
    domain average ``\langle\cdot\rangle``). Names and conventions:

    - `integral(f)` — the **extensive** ``\int f\,\mathrm{d}\mu`` (the one quantity that scales with the base measure).
    - `mean(f)`, `std(f)`, `var(f)` — extend `Statistics` (we own the types ⇒ not piracy);
      **intensive**, **fiber-preserving** (`mean(VectorField) → FiberVector`, base reduced).
    - `inner(f, g)` — the **normalized** L² inner product ``\langle f, g\rangle = \texttt{mean}(\texttt{dot}(f, g))`` → **scalar**
      (fiber-contracting). *Normalized* (intensive) by deliberate choice: it matches the `mean`
      convention above and the intensive quantities of homogeneous turbulence (kinetic energy
      ``\tfrac{1}{2} \texttt{inner}(u,u) = \tfrac{1}{2}\langle |u|^2\rangle``); for points it is ``\tfrac{1}{M}\sum \texttt{dot}``, consistent with `mean`. Not the
      textbook extensive ``\int f\cdot g\,\mathrm{d}x`` — that is `integral(dot(f,g))` if ever needed.
    - ``\texttt{l2norm}(f) = \sqrt{\texttt{inner}(f,f)}``, generalized as `lpnorm(f, p)` (``p=2`` default; ``p=\infty`` ⇒ sup of the
      fiber magnitude — the CFL case). Chosen over `norm_L2`; **does not** touch the vertical `norm`.
    - `maximum`/`minimum`/`extrema` — extend `Base` for scalar sections; vector/tensor sup of
      magnitude via `lpnorm(·, Inf)`.
    - **No LinearAlgebra overloading**: `dot`/`norm` stay the vertical pointwise ops (return sections,
      scalar fields); the global `inner`/`l2norm` are package generics returning numbers.

    `inner`/`l2norm` are representation-invariant (Parseval): the physical reductions came first, and the
    **spectral `inner`/`l2norm` are now implemented** — for two fields in spectral representation
    ``\texttt{inner}(\hat f, \hat g)`` equals the physical inner via the rfft half-spectrum Parseval weighting (each mode
    counts twice except those on the ``k_x=0`` plane and, for even ``N_x``, the Nyquist plane — the planes the
    rfft maps to themselves under conjugation, whose partners are already stored, so they count once), computed
    as a `dot` over the array plus two plane corrections — allocation-free in the `inner(f, f)`/`l2norm` case, while the mixed `inner(f, g)` materializes its two correction planes (decision 26). The `integral` and `mean` reductions are
    representation-invariant too, by a different route — the zero (DC) Fourier mode: under the
    unnormalized-forward convention the DC coefficient is ``\hat f(0) = \sum_x f(x)`` (real for a real
    field), so the mean is ``\hat f(0)/N`` and the integral ``(|\Omega|/N) \hat f(0)`` with no transform,
    read from the same zero-mode slot the constant-add writes (invariant 4). The `lpnorm` reduction and
    `maximum`/`minimum`/`extrema` have no single-coefficient form and remain physical-only — `lpnorm` at
    every exponent, ``p = 2`` included, that case being served in spectral representation by `l2norm`
    rather than by an `lpnorm` method. (This entry's original wording also grouped `std`/`var` with them;
    decision 49 later found those two physical-only by scoping rather than by validity, and gave them
    their spectral form.)
    **Physics stays consumer-side**: energy ``\tfrac{1}{2} \texttt{inner}(u,u)``, enstrophy
    ``\tfrac{1}{2} \texttt{inner}(\omega,\omega)``, dissipation ``\nu \texttt{inner}(\omega,\omega)``, rms ``\sqrt{\texttt{inner}}``, intensities from `std`. The FP-ordering
    concern that deferred reductions (item 11) is real — so they are implemented with a defined summation
    order and a tolerance-based test (not the bitwise one used for the threaded assignments).
19. **The measure taxonomy — one L²/integration structure, three roles for "measure"; the recorded
    foundation for the spectral-multiplier family later realized as `Convolution` (decision 20).** The word *measure* recurs across the package
    (reductions, interpolation, and convolution) not by coincidence but
    because all three are facets of the **same L²/integration structure on sections** ([§2](@ref "2. The central principle: the architecture follows established mathematics")). This entry
    fixes the taxonomy so the three never get conflated and so the multiplier family starts from a
    recorded design. The math anchor (Grafakos, [*Classical Fourier Analysis*](https://doi.org/10.1007/978-1-4939-1194-3),
    3rd ed., Graduate Texts in Mathematics **249**, Springer, 2014, Thm 2.5.10): on a uniform
    periodic box every **homogeneous (translation-invariant) linear operator is a Fourier multiplier** — a
    coefficientwise ``m(k)`` — and the *bounded* ones are exactly those with symbol ``m(k) \in L^\infty``, where
    ``\lVert T\rVert_{L^2 \to L^2} = \lVert m\rVert_\infty``. So "apply ``m(k)``" is not a convenience — it is the complete representation of
    the translation commutant. The existing operators are all such multipliers: `helmholtz_projection` ([§4](@ref "4. Spectral machinery")),
    the consumer's 2/3 de-alias mask, and the integrating factor ``\exp(-\nu k^2 \Delta t)`` are the **bounded** ones
    (``m \in L^\infty``); `gradient`/`curl`/`laplacian` are the **unbounded** multipliers (symbols ``\mathrm{i}k``, ``-|k|^2 \notin L^\infty``),
    diagonalized identically but outside the norm identity above.

    The roles — each as *what it is; operation(s); the map it performs; status*:

    - **base-quadrature**: `Grid3D` cell volume ``\prod_i \Delta x_i`` / `PointSet` counting; ops
      `integral`, `inner`, `mean`, `std`, `lpnorm`, `radial_spectrum` (the ``|k|``-resolved `inner`);
      section → scalar / fiber / radial profile; **done** (decisions 18, 21).
    - **kernel — multiplier**: translation-invariant convolution, symbol ``m(k) \in L^\infty``;
      `convolve` / `convolve!` plus the builders `spectral_cutoff` / `spectral_band` /
      `radial_kernel` (any real symbol of ``|k|^2``); grid → grid
      (a Fourier multiplier); **done** (`Convolution`, decisions 20, 21).
    - **kernel — transfer**: off-grid partition-of-unity convolution (unit mass; signed or positive);
      `interpolate` (``W``) / `anterpolate` (``W^\top``); grid ↔ point (base-change, *not* a
      multiplier); **done** (decisions 13/17).
    - **sample-space (FDF)**: spatially-filtered fine-grained Dirac density, over the
      velocity/composition sample space; no package operation; **out** (physics; invariant 12).

    *Interpolation is the base-changing sibling of the multiplier, not a multiplier.* The gather weights
    `{W(x_p, x_g)}_g` are a discrete grid measure of **total mass 1** (partition of unity), so
    ``u(x_p) = \int u\,\mathrm{d}\mu_{x_p}`` is integration of the field against a unit-mass kernel measure centered at
    the point — the same *species* as a homogeneous filter. Two differences make it its own operation
    ([§10](@ref "10. Interpolation and anterpolation (the grid↔point transfer layer)"), in `Interpolation`, not under the multiplier family): (i) its codomain is the **unstructured
    point base**, which has no wavenumbers, so it is a **base-change** (grid↔point), *not* a Fourier
    multiplier (it degenerates to one only when points coincide with nodes); (ii) the default
    `CatmullRom`/`Lagrange` kernels have **negative side-lobes** — a *signed* unit-mass measure (higher
    reproduction order, but overshoot), while only the linear `m=0` / positive-B-spline end is a genuine
    **probability measure** (monotone). Reproduction order = number of matched **moments** of the kernel
    measure (0th moment `=1` = partition of unity = constants reproduced). This signed/positive split is
    the *same* dichotomy the LES research surfaces below — evidence the kernel measure is one concept.

    *The transfer adjoint is a row-1 (base-measure) statement, and that is why reductions came first.*
    Anterpolation ``W^\top`` is the adjoint of ``W``; "adjoint w.r.t. which pairing?" is answered by the base
    measures. As shipped (decision 17) the adjointness ``\sum_p (Wf)_p \cdot q_p = \sum_n f_n \cdot (W^\top q)_n`` (the unnormalized counting pairing) and conservation
    ``\sum_g (W^\top q)_g = \sum_p q_p`` hold in the **counting/transpose** pairing (the extensive facet of row 1;
    conservation = partition of unity). The **measure-weighted L² adjoint** — ``W``, ``W^\top`` adjoint with **both bases carrying their
    normalized (total-mass-one) measures**, ``\tfrac{1}{N}\sum_n`` on the grid and ``\tfrac{1}{M}\sum_p`` on the
    points, which is what `inner` computes — is the **bridge from row 1 to the transfer kernel**, and is
    now **done**: both measures being uniform, it is ``(N/M) W^\top`` (a scalar rescaling, no new
    operation). The ``N/M`` is exactly the ratio of those two normalizations; pairing an unnormalized
    cell-volume grid measure against counting points would instead give ``(N/|\Omega|) W^\top``,
    verified via `inner` as ``M \texttt{inner}(Wf, q) = N \texttt{inner}(f, W^\top q)`` (`test/interpolation_transfer.jl`). That the
    reductions had to precede it is recorded here.

    *The multiplier family (designed here; realized as `Convolution`, decision 20) carries three research-grounded guardrails.*
    The deep-research findings on LES filtering do **not** change the design — they justify it and bound
    it:
    - **The symbol is data, never parameters** — this is how the family stays inside invariant 12 (no
      time, no physics). The applicator multiplies a field-in-spectral by a precomputed ``k``-array; ``\nu``,
      ``\Delta t``, filter width, and positivity all live in how the *consumer* builds that array from the
      `FieldSpectralMultipliers` wavenumbers ([§4](@ref "4. Spectral machinery")). The viscous factor ``\exp(-\nu k^2 \Delta t)`` is literally the
      heat-kernel probability measure, yet the package never sees ``\nu`` or ``\Delta t``.
    - **Do not restrict to positive ("measure") symbols.** ``L^\infty``-symbol is the right generality;
      convolution-with-a-finite-measure is a *strict subclass* whose symbol must be **continuous**, and
      the 2/3 mask and sharp spectral cutoff have **discontinuous** symbols (kernels not in ``L^1``) — so
      they are *not* such convolutions yet are valid multipliers we rely on. Positivity of the kernel ⟺
      positive-definite symbol (**Bochner**) ⟹ probability measure ⟹ realizable SGS stress
      (**Vreman, Geurts & Kuerten 1994**, realizability *iff* positive filter) ⟹ bona-fide filtered PDF
      (**Colucci et al. 1998**, the FDF); all of that is **consumer** semantics. No
      `PositiveFilter` type, no realizability checks. (`Interpolation` already ships signed kernels by
      default — consistent.)
    - **Homogeneous-only scope.** Variable-width filters are *not* multipliers (commutation error;
      **Ghosal & Moin 1995**, **Vasilyev, Lund & Moin 1998**) — and the uniform torus admits only
      homogeneous operators anyway, so this is a clarifying boundary, not a gap. Projections are the
      *idempotent* multipliers (the sharp cutoff; `helmholtz_projection` is the matrix-valued one we
      already ship); smoothings are the non-idempotent ones — same family, no special case.

    Open at the time (untouched by the research; all resolved in decision 20 — the `Convolution`
    module, the `convolve` op, the `spectral_cutoff` builder): a name distinct from the existing
    `FieldSpectralMultipliers` *data* (e.g. a `FourierSymbol` operator or a generic `apply_multiplier!`);
    placement (extend `DifferentialOperators`, which owns the fixed diagonal symbols, vs. a new module);
    and how many neutral builders to ship (bare applicator vs. a `spectral_cutoff` helper — never a
    physics-named `gaussian_les_filter`). v1 is scalar symbols; matrix-valued symbols are deferred
    (`helmholtz_projection` covers the only case currently needed). The Germano differential filter
    ``1/(1 + \Delta^2 k^2)`` is architecturally inert — whatever its symbol, it is one more scalar multiplier the
    consumer supplies.
20. **Convolution — the kernel-multiplier family realized ([§2](@ref "2. The central principle: the architecture follows established mathematics"); the new `Convolution` module).**
    Implements the multiplier designed in decision 19 as periodic (circular) convolution of a field
    with a kernel, in spectral representation: by the convolution theorem on the torus, `f ⋆ g` is the
    **coefficientwise spectral product** ``\hat f \cdot \hat g``. The kernel `g` is supplied by its transfer function
    ``\hat g`` as a **`ScalarFieldSpectral`** (decision 19's open "kernel as a field" call, chosen for
    elegance); a scalar kernel broadcasts over the fiber, so one method serves scalar/vector/tensor
    fields, and because a kernel is itself a scalar field in spectral representation, `convolve(g₁,
    g₂)` composes two kernels for free (the `R = 0` case). (Superseded by decision 60: a kernel is now
    its own type, so a `ScalarFieldSpectral` is wrapped in a `StoredKernel` to declare that role and
    composition is unambiguous by type rather than by argument position.) `convolve` / `convolve!` mirror `laplacian`
    / `laplacian!`: coefficientwise ⇒ alias-safe (no `_guard_noalias!`; destination may alias the
    field), `@_assign!`-routed (threads on CPU), with the five-argument `α`/`β` accumulate form
    (invariant 10). Spectral representation only — there is no physical-space `convolve` (the
    differential-operator precedent).

    *This completes invariant 1 rather than weakening it.* The coefficientwise spectral product is the
    operation invariant 1 names but bans **as `*`** (because `*` would read as the spectral *pointwise*
    product, which it is not). It is offered here under its true name — `convolve`, never `*` — and is
    linear in the field for a fixed kernel; the spectral pointwise product, division, and norms remain
    absent. The `convolve` / `convolve!` / `spectral_cutoff` family are separate generics, so the `FieldAlgebra`
    198-method and point-value 118-method parity baselines are unchanged.

    One neutral builder ships: `spectral_cutoff(multipliers, k)` — the isotropic sharp
    low-pass (idempotent projection), the basis of de-aliasing / spectral truncation; physics (an LES
    filter, an integrating factor ``\exp(-\nu k^2 \Delta t)``) stays a set of coefficients the consumer builds
    from the wavenumbers, wrapped as a `StoredKernel` since decision 60 (invariant 12). Naming follows the [§2](@ref "2. The central principle: the architecture follows established mathematics") convention (the verb `convolve` for a
    generic transformation; the module noun `Convolution`, parallel to `Interpolation` / `interpolate`).
    Tested CPU (`test/convolution.jl`, Float64/Float32 — the translation kernel
    ``\exp(-\mathrm{i} k_x m \Delta x) \Leftrightarrow`` `circshift` is the independent physical oracle, plus identity/scaling/
    cutoff-idempotence/composition/α-β/alias) and GPU (ROCm device-vs-CPU parity in `test/gpu/suite.jl`);
    benchmarked (the `convolution` class). The L²-weighted and matrix-valued (anisotropic) kernels
    remain future.
21. **Shell-space spectral primitives — the radial coordinate, the band-pass, and the shell-resolved
    inner (extending `Convolution` + `Reductions`).** Three neutral primitives surfaced by the
    `examples/HIST_*` demos, each the code image of an established object and each slotting into an
    existing family — no new module, no parity-baseline change (separate generics), physics names
    stay consumer-side (invariant 12). They close the largest hand-rolled pieces of a real
    pseudospectral consumer (the energy spectrum, the forcing band, the viscous integrating factor):

    - **`squared_wavenumber_field(reference, multipliers)` (`Convolution`; REMOVED by decision 60 —
      `radial_kernel(identity, …)` is the same symbol as a closure)** — the radial coordinate
      ``|k|^2`` of spectral space as a `ScalarFieldSpectral` (real, stored complex, like a cutoff mask).
      Decision 19 fixed that "the symbol is data": the consumer builds ``\exp(-\nu |k|^2 \Delta t)``, a smooth
      envelope, or a Germano filter ``1/(1 + \Delta^2 |k|^2)`` by broadcasting over its `field_data`, then applies
      it with `convolve`. The package hands over the coordinate; ``\nu``, ``\Delta t``, the width stay consumer-side.
      It wraps the existing `_squared_wavenumber_broadcast` (the Laplacian's ``|k|^2``, true value at
      Nyquist — invariant 5).
    - **`spectral_band(multipliers, wavenumber_low, wavenumber_high)` (`Convolution`)** — the isotropic annular
      band-pass, the generalization of `spectral_cutoff` (now its `wavenumber_low = 0` special case, refactored
      to delegate). Idempotent ⇒ a projection; it selects a wavenumber shell — a de-alias band, a
      forcing band, a filter ring. With it the demos' low-shell forcing becomes pure package ops:
      band energy `= inner(u_band, u_band)` with `u_band = convolve(u, band)`, then a rescaling `convolve`
      — no scalar indexing, and the `inner(f, f)` form is allocation-free (its fused-`abs2` fast path).
    - **`radial_spectrum(f, multipliers)` (`Reductions`; introduced as `shell_spectrum`, renamed in
      decision 22)** — the **radial (shell-binned) power spectrum**: `inner` decomposed into isotropic
      ``|k|``-shells. Returns `(shells, spectrum)` with the exact refinement `sum(spectrum) == inner(f, f)`
      (same rfft half-spectrum Parseval weighting, now resolved per mode). This is the genuinely new
      reduction — spectral-representation only, like the Parseval `inner` — and the architectural framing
      is precisely *"the energy spectrum is the radially-resolved inner"* (decision 19's L²/integration
      structure, refined by the spectral radial coordinate). The consumer's energy spectrum over the
      shell wavenumber ``\kappa`` (``= |k|``) is ``E(\kappa) = \tfrac{1}{2} \texttt{spectrum}``; the
      neutral noun keeps physics out (invariant 12). Shells run to the corner wavenumber so the
      refinement is exact; on a de-aliased field the high-``|k|`` shells are empty.

    *Device-clean by construction.* `radial_kernel` / `spectral_band` are broadcast kernel
    builders (the `spectral_cutoff` pattern); `radial_spectrum` bins via a single **scatter-add** pass — one
    portable atomic-histogram kernel over the modes (no scalar indexing), an occasional diagnostic.
    *(Originally a sequence of masked reductions, one per shell, with the histogram scatter deferred as
    "unneeded"; **decision 25** lifted the deferral — the per-shell masks allocated ``O(N)`` full-grid
    temporaries per call (``N`` the points per axis), which on the GPU the garbage collector cannot reclaim
    promptly, so a single ``256^3`` diagnostic wedged a 12 GB card.)* Tested CPU (`test/convolution.jl` band/coordinate vs the ``|k|^2`` oracle + cutoff equivalence;
    `test/reductions.jl` `sum(radial_spectrum) == inner`, the single-mode shell placement) and GPU (ROCm
    device-vs-CPU parity in `test/gpu/suite.jl`); benchmarked (the `reductions` / `convolution` classes).
    The `examples/HIST_CPU.jl` + `examples/gpu/rocm/HIST_ROCm.jl` demos are refactored onto them, making
    the GPU forcing + spectrum fully on-device. Matrix-valued (anisotropic) shells remain future; the
    **co-spectrum `radial_spectrum(f, g)`** is now **done** (decision 22, the two-field cross-power). **Renamed `shell_spectrum → radial_spectrum` in
    decision 22 (done); the physical-space dual `radial_correlation` is decision-22 Phase 1, also done.**
22. **Radial statistics — the spectrum↔correlation duality (Wiener–Khinchin), and the FFT route to
    point pair-statistics (RDF). [Phase 1 (`radial_correlation`), Phase 2 (`assignment_window` + the
    pair-correlation recipe), and the two-field co-spectra (`radial_spectrum(f, g)` / `radial_correlation(f, g)`) all DONE.]**

    *The object.* A field's **two-point correlation function** and its **power spectrum** are one object
    in two representations, linked by the **Wiener–Khinchin theorem**: on the periodic grid the circular
    autocorrelation ``C(r) = \langle f(x) \cdot f(x+r)\rangle`` equals ``\mathcal F^{-1}(|\hat f|^2)/N`` exactly — the inverse
    transform of the power spectrum, normalized by the grid-point count ``N`` (the cross-correlation theorem).
    Radially averaging gives the **isotropic radial statistics**, a Fourier-dual pair — average ``|\hat f|^2``
    over ``|k|``-shells (the spectrum), or ``\mathcal F^{-1}(|\hat f|^2)`` over ``|r|``-shells (the correlation). This is
    invariant 2 — *physical and spectral are representations of one object* — raised to **second-order
    statistics**: the spectrum and the correlation function are not two diagnostics but one, viewed in
    the two representations. The `radial_spectrum` reduction (decision 21, introduced as `shell_spectrum`) is the
    spectral half; this entry designs the physical half and the point application, and fixes the
    terminology so the family is coherent.

    *Terminology (decided; the rename is **done**).* `shell_spectrum` is renamed **`radial_spectrum`**,
    and the physical dual **`radial_correlation`** is added (Phase 1, **done**). "Radial" is the
    isotropic-average qualifier common to both spaces — and to the *radial* distribution function of point
    statistics; "shell" named the binning implementation and does not pair with the physical-space
    correlation. The two are the **radial reductions**: a Fourier-dual pair in `Reductions`, each mapping
    a field to a 1-D radial profile, named by the quantity's noun per [§2](@ref "2. The central principle: the architecture follows established mathematics") (`spectrum` / `correlation`)
    under the `radial` qualifier. The `radial_spectrum` math is unchanged (`sum == inner`). Physics names
    stay consumer-side: the energy spectrum ``E(k) = \tfrac{1}{2} \texttt{radial\_spectrum}``, the integral/Taylor scales from
    `radial_correlation`, the RDF `g(r)` from `radial_correlation` of a density field. (The rename was
    safe — the API is not frozen and `shell_spectrum` had shipped the same day with no external users.)

    *The physical dual — `radial_correlation` (done).* ``C(r)`` = radially-averaged ``\langle f(x) \cdot f(x+r)\rangle``
    (full fiber contraction — the trace of the correlation tensor, mirroring `inner`) ``= \mathcal F^{-1}(|\hat f|^2)/N``
    binned over minimum-image ``|r|`` shells. The zero-separation value is ``C(0) = \langle |f|^2\rangle = \texttt{inner}(f, f)`` (the
    second moment — the variance only when ``f`` is mean-free); and for a zero-mean field ``C(r) \to 0``
    at large ``r``. **The open design point was resolved
    as the user chose:** `radial_correlation(f, plans)` takes the field in spectral representation **plus
    its transform plans** (symmetric with how the differential operators take `multipliers`) — `Reductions`
    imports `to_physical` from `Fields` to do the one inverse rfft, then bins with the same scatter-add
    machinery as `radial_spectrum` (the single-pass shell histogram; decision 25), in ``r`` instead of ``|k|``. Verified against an independent
    binned-circshift autocorrelation (CPU `test/reductions.jl`, GPU `test/gpu/suite.jl`) and `C(0) = inner`.

    *The two-field co-spectra — `radial_spectrum(f, g)` / `radial_correlation(f, g)` (done).* The mixed
    second-order statistics of two compatible, equal-order fields, refining the **mixed** `inner(f, g)` exactly as
    the single-field forms refine `inner(f, f)`. The **co-spectrum** bins the Parseval-weighted cross-power
    density ``\sum_c \mathrm{Re}(\hat f_c \overline{\hat g_c})`` (``c`` indexing the fiber components) over ``|k|``-shells (``\sum_\kappa P_{fg} = \texttt{inner}(f, g)``);
    the **cross-correlation** ``C_{fg}(r) = \langle f(x)\cdot g(x+r)\rangle = \mathcal F^{-1}(\overline{\hat f} \hat g)/N``
    binned over ``|r|``-shells (``C_{fg}(0) = \texttt{inner}(f, g)``). Two properties fall out of the math and are
    pinned by tests: each is **symmetric** in ``f, g`` — ``\mathrm{Re}`` is conjugation-symmetric for the spectrum,
    and the ``\pm r`` folding of the min-image shells symmetrizes the correlation (``C_{fg}(-r) = C_{gf}(r)``, so the
    radial average is ``\tfrac{1}{2}(C_{fg}+C_{gf})``) — and the single-field forms are exactly the ``g = f`` case
    (``\mathrm{Re}(\hat f \overline{\hat f}) = |\hat f|^2``; asserted bit-identical). Unlike the power spectrum the
    co-spectrum **may be negative** in a shell (anticorrelated modes — the canonical use is a momentum/scalar flux
    co-spectrum, where sign is physical). Implementation reuses the single-field code: the binning helpers
    (`_radial_spectrum_bin`, `_correlation_field_from` + `_radial_average`) are shared, the two-field methods only swap
    the per-mode density (``|\hat f|^2 \to \mathrm{Re}(\hat f \overline{\hat g})``) / the per-component spectrum
    (``|\hat f|^2 \to \overline{\hat f} \hat g``, Hermitian for real ``f, g`` ⇒ the c2r reconstruction is exactly real).
    (The helper set has since been consolidated: the staging fused into the binning kernels themselves and
    `_correlation_field_from` folded into the correlation methods — decision 34; the sharing structure is unchanged.)
    These are **new methods on the existing `Reductions` generics** — no export change, the 198/118 parity baselines
    are unchanged. Verified CPU (`test/reductions.jl`: analytical oracles — an orthogonal pair ``\cos x \perp \sin x``
    giving zero, and ``\cos x \pm \cos 2x`` giving ``\pm\tfrac{1}{2}`` in adjacent shells that cancel to ``\texttt{inner} = 0``;
    the ``g = f`` consistency; the ``f \leftrightarrow g`` symmetry; and an independent binned-circshift cross-correlation
    on a random pair) + GPU (ROCm device-vs-CPU parity, `test/gpu/suite.jl`); benchmarked (`reductions` class).

    *Points → RDF (Phase 2, done).* The pair correlation ``g(r)`` of ``M`` points is computable
    in ``O(N \log N + M)`` (vs ``O(M^2)`` direct counting) via the **FFT structure-factor estimator** — exactly
    the implemented recipe: **anterpolate** the points to a grid density (positive/linear assignment), form the
    overdensity ``\delta = \rho/\bar\rho - 1``, **FFT**, **deconvolve** ``\hat\delta`` by the assignment window
    ``\hat W``, then `radial_correlation` of the deconvolved field gives ``\xi(r) = \langle\delta(x)\delta(x+r)\rangle``
    and ``g(r) = 1 + \xi(r)`` (the ``i=j`` self term is the shot noise, isolated in the ``r=0`` shell, so
    ``g`` at ``r>0`` is clean). With ``\hat\rho(k) = \sum_i e^{-\mathrm{i} k \cdot x_i}``,
    ``S(k) = |\hat\rho|^2/M = 1 + \bar n \hat h(k)`` (Ornstein–Zernike) and ``g = 1 + h``. We already owned
    anterpolate + the transforms + both radial reductions; the **one new neutral primitive is the
    assignment-window deconvolution**, the rest is the consumer recipe (invariant 12). Three corrections, all
    handled:

    - **Assignment-window deconvolution (`assignment_window`, `Convolution`).** Scattering with kernel ``W``
      gives ``\hat\rho_g = \hat W(k) \hat\rho``, so the measured spectrum is suppressed by ``|\hat W(k)|^2`` —
      divide it out (a `convolve` by ``1/\hat W``). Shipped for the **linear (CIC) positive** assignment:
      ``\hat W(k) = \prod_a \operatorname{sinc}^2(k_a\Delta x_a/2)``, no in-band zeros. (Higher positive
      B-splines / the signed-kernel closed forms remain future.)
    - **Shot noise.** The ``i=j`` self term is a constant ``+1`` floor in ``S(k)`` (a ``\delta(r)`` at the
      origin): in the binned ``g(r)`` it lands entirely in the ``r=0`` shell, so evaluating ``g`` at ``r>0`` is the
      subtraction (no extra step). Consumer-side by convention.
    - **Aliasing / resolution.** The grid folds high-``k`` at Nyquist — trust ``k \lesssim \tfrac{2}{3} k_\mathrm{Nyq}``, and ``g(r)``
      below a few grid cells is unreliable regardless of corrections. FFT-RDF resolves **intermediate /
      large-scale clustering** (e.g. inertial-range preferential concentration), *not* a sharp contact
      peak (interlacing — Sefusatti et al. 2016 — is a future refinement). This matches the intended consumer
      use; it is a documented boundary, not a defect.

    *Verified (`test/rdf.jl`):* `assignment_window` against its ``\prod \operatorname{sinc}^2`` formula
    (even/odd grids, both element types), and the full recipe against an **independent direct ``O(M^2)``
    physical-space pair count** on a clustered point set — the recipe recovers the clustering peak (within
    ~10% of direct counting) and the ``g \to 1`` baseline (the normalization).

    *Decision-19 tie-in.* A density estimate wants the **positive (probability-measure)** end of the
    kernel taxonomy (the linear ``m = 0`` / a B-spline), not the signed default `CatmullRom`, so ``g(r) \ge 0``
    and ``\hat W(k)`` has no in-band zeros (no division blow-up in the deconvolution). Decision 19's recorded
    signed/positive split becomes a concrete, motivated choice here.

    *Invariant 12.* `radial_spectrum` / `radial_correlation` and `assignment_window` are neutral
    (harmonic analysis / spatial statistics). The names RDF, structure factor, pair correlation, and the
    shot-noise / normalization conventions (which encode "what a particle is") stay consumer-side — the
    package ships the primitives and a documented recipe (`test/rdf.jl`, validated against direct pair
    counting), **not** a `radial_distribution_function` function: that scoping held.

    *Phasing — all done.* **Phase 1:** `radial_correlation(f, plans)` (the field duality; neutral, no new
    math), ``\Delta r`` = the finest grid spacing, minimum-image ``|r|`` binning, ``C(0) = \texttt{inner}``
    exact. **Phase 2:** `assignment_window` (the linear/CIC ``\prod \operatorname{sinc}^2`` deconvolution
    window, `Convolution`) + the documented point-RDF recipe, validated against direct ``O(M^2)`` counting.
    **Co-spectra (done):** the two-field `radial_spectrum(f, g)` / `radial_correlation(f, g)` (the
    cross-power / cross-correlation pair — momentum/scalar fluxes; new methods on the existing generics that
    reuse the single-field binning, refining the mixed `inner(f, g)`; symmetric, may be negative — see above).
    **Future (deferred until a consumer makes them concrete):** higher positive-B-spline / signed-kernel
    window transforms and interlacing (sharper small-``r`` ``g``); and — the "meaningful fibers over the
    radial coordinate" — the anisotropic / tensor-valued radial spectra ``E_{ij}(\kappa)`` and the
    Craya–Herring longitudinal/transverse split, which only earn their structure under anisotropy
    (e.g. shear flow), per the [§2](@ref "2. The central principle: the architecture follows established mathematics") rule against speculative structure.
23. **Spectral-domain transfer — `DirectDFT` (exact) and the native `NUFFT` (fast). [Both DONE.]**

    *The object.* The transfer layer ([§10](@ref "10. Interpolation and anterpolation (the grid↔point transfer layer)")) had one scheme family — the physical-domain local splines.
    This adds the **spectral-domain** transfer: evaluation/deposition between Fourier coefficients and
    scattered points, the exact off-grid form of the field. Both families are unified under a new
    supertype `AbstractTransferScheme`, sharing the `interpolate`/`anterpolate` verbs and the adjoint
    contract (the counting-transpose pairing, which the ``N/M`` rescaling above turns into the exact
    L² adjoint); a scheme is a choice of *(kernel, representation)*. The spectral schemes dispatch on a
    field in spectral representation (invariant 2: hand ``W`` whichever representation it acts on — a
    spectral solver hands ``\hat f`` for free); `anterpolate` returns a section, here in spectral
    representation (the Fourier coefficients of ``\sum_p q_p\delta_{x_p}``).

    *`DirectDFT` (done).* The literal ``O(NM)`` sum (``N`` the grid-point count, ``o`` the grid origin):
    type-2 ``f(x_p) = \tfrac{1}{N}\sum_{\text{stored }k}
    \alpha(k) \mathrm{Re}(\hat f(k) e^{\mathrm{i} k\cdot(x_p-o)})`` (the rfft half-spectrum reconstruction, with
    the Parseval weight ``\alpha`` of decision 18 — ``1`` on the ``k_x=0``/even-Nyquist planes, ``2`` else),
    type-1 ``(W^\top q)(k) = \sum_p q_p e^{-\mathrm{i} k\cdot(x_p-o)}``. It is the *definition* of the
    spectral-domain pair, so it is at once a transparent exact baseline, the **divergence-free
    reference** (it reproduces the band-limited field exactly — verified ``\sim 10^{-16}`` off-grid —
    where the splines break ``\nabla\cdot u=0``), and the **oracle** that will validate `NUFFT`. It
    matches `to_physical` at the grid nodes and `to_spectral` from node samples (both exact to round-off),
    and satisfies ``M \langle W\hat f, q\rangle_{\mathrm{pts}} = N \langle \hat f, W^\top q\rangle_{\mathrm{grid}}`` (the
    measure factor, as for the splines — decision 17). Two simple KernelAbstractions kernels (type-2
    over points, type-1 over modes — no atomics), the per-axis wavenumbers + ``\alpha`` built host→device
    like the multipliers; no FFT, window, or oversampling. Stateless `DirectDFT()`; CPU + GPU-portable.
    **Standing principle** (beyond this pair): when a fast or approximate method is added, its exact
    reference ships as a **first-class sibling scheme**, built first — at once the definition a user can
    reach for at small sizes and the oracle the fast form is validated against — never a `test/`-only helper.

    *Native `NUFFT` (decided: own it, no dependency — done).* The fast ``O(N\log N + M)`` windowed
    gridding form of `DirectDFT`: **spread → FFT → deconvolve**, all reusing existing machinery — the
    transfer kernels (spread/gather with an exponential-of-semicircle window in place of the spline
    coefficients), a `FieldTransformPlans` on an oversampled (``\sigma=2``) grid, and a ``1/\hat\psi``
    deconvolution `ScalarFieldSpectral` — ``\psi`` the smooth compact spreading window, ``\hat\psi`` its
    Fourier transform — built like `assignment_window` (which **is** the ``\hat\psi`` of the linear/CIC
    window — so `NUFFT` generalizes the decision-22 RDF deconvolution). The one new ingredient is that
    window ``\psi`` (exp-of-semicircle, GPU-trivial) and its transform ``\hat\psi``
    (host quadrature, the ``z=\sin\theta`` substitution regularizing the endpoint); the stencil width
    and the shape parameter ``\beta`` (the ES-kernel constant of the NUFFT literature — unrelated to
    the package's ``\alpha``/``\beta`` accumulation weights) follow the Barnett–Magland–af Klinteberg
    ES rule for the tolerance.
    Verified against `DirectDFT` (and `to_physical`) to the requested tolerance ``\varepsilon``
    (the default requests `tol = 1e-10`; the exponential-of-semicircle window over-delivers, ``\sim 10^{-12}`` measured there) for scalar and
    vector fields, with the NUFFT pair an **exact adjoint** (``\sim 10^{-15}``).

    *The Nyquist edge.* The one subtlety: the rfft half-spectrum Nyquist mode of an even axis cannot be
    split losslessly into the finer oversampled grid (zero-padding a real spectrum). It is **projected
    out** in the deconvolution, so `NUFFT`'s type-1/type-2 remain exact adjoints on the **resolved
    sub-Nyquist band** — exactly the band a spectral solver uses (de-aliasing, or any natural spectral
    decay, zeros the Nyquist), where the transfer is exact to ``\varepsilon``. `DirectDFT` (no
    oversampling) carries the Nyquist exactly; the two agree on the sub-Nyquist band.

    `NonuniformFFTs.jl` was evaluated (it fits — real-data rfft, AMDGPU/KA, batched) but **not adopted**:
    owning it keeps the package self-contained and makes the spline transfer and the NUFFT share one
    spread machinery, with `DirectDFT` and a direct ``O(NM)`` DFT as independent ground truth. Tested
    CPU (`test/transfer_spectral.jl`) + GPU parity; method parity 198/118 unchanged (the transfer verbs
    are not in those surfaces).

24. **Allocation-free in-place spectral operators (the GPU hot-loop discipline).** A solver runs the
    operators thousands of times in its time loop. On the GPU, any scratch an operator allocates
    internally is invisible to Julia's garbage collector — the collector triggers on *host* memory
    pressure, but the scratch lives in *device* memory — so the device memory pool grows every step
    until it fills VRAM, and the run then wedges (the allocator spins, GPU idle) or `hipMalloc` aborts.
    The discipline this forces: the in-place ``!`` operators must allocate **nothing**, writing only
    into their preallocated destination. Two changes brought the spectral operators into line. *(a)*
    `_squared_wavenumber_broadcast` — the radial coordinate ``|k|^2 = k_1^2 + k_2^2 + k_3^2`` — now
    returns a **lazy** `Broadcasted` over the three per-axis squared-wavenumber vectors instead of a
    materialized ``O(N^3)`` array (``N`` the points per axis), so the Laplacian (``-|k|^2\hat f``),
    inverse Laplacian (``-\hat f/|k|^2``) and Helmholtz projection
    (``\hat f_i - k_i (k_j\hat f_j)/|k|^2``) fuse it into their own broadcasts without ever allocating
    it. *(b)* The `laplacian!`, `inverse_laplacian!` and `helmholtz_projection!` kernels were rewritten
    so their former per-call temporaries (the longitudinal coefficient ``k_j\hat f_j/|k|^2``, the safe
    ``1/|k|^2`` that is ``1`` at the zero mode) are **fused** into the component assignments rather than
    materialized; the projection recomputes the longitudinal part inline for each component, which is
    safe because the kernel always receives a destination distinct from the source — the aliased
    `helmholtz_projection!(x, x)` allocates its guard temporary upstream ([§7](@ref "7. Aliasing policy")).
    (The projection has since moved on from both details: its one-pass kernel computes the longitudinal
    part once per mode and serves the aliased call directly, guard retired — decision 32.)
    Net: each of the three now allocates ``\sim 0`` bytes in place (measured), with identical arithmetic
    and results (the full suite is unchanged) — so a preallocated, in-place pseudospectral step allocates
    nothing per step and runs on a 12 GB consumer GPU with **no manual `GC.gc()` / `reclaim`, at flat
    VRAM** (the `examples/` HIST solvers demonstrate this — ``192^3`` Float32 at ``\sim\!34`` ms/step on
    a since-retired card). Guarded by `test/allocations.jl` (every in-place spectral operator, transform,
    `convolve!`, and fiber product/shuffle, both element types). The fiber norm, `lpnorm` and `dev!`
    deliberately materialize one field (a pointwise magnitude, or the trace they subtract) and are the
    documented exceptions — a consumer's CFL speed uses `maximum(abs, …)` rather than `lpnorm`.

25. **Allocation-bounded radial diagnostics — the shell binning as a single scatter-add (the GPU-GC
    corollary of decision 24).** Decision 24 made the time *loop* allocation-free; this brings the
    *diagnostics* into the same discipline, for the same reason. The radial statistics — `radial_spectrum`
    (the ``|k|``-shell power spectrum) and `radial_correlation` (the ``|r|``-shell two-point correlation) —
    binned by looping over the shells and, for each shell ``s``, reducing a masked broadcast (sum of the
    per-mode value over the modes whose rounded shell index equals ``s``). The number of shells scales with
    the grid — ``\lceil \sqrt{3} N/2\rceil`` (``N`` the points per axis), ``\approx 220`` at ``N = 256`` —
    and each iteration allocates a full-grid temporary: the Boolean shell mask, and (because on the GPU
    stack a `mapreduce` over a `Broadcasted` materializes its argument rather than fusing) the masked
    product too. That is ``O(N)`` full-grid temporaries per *single* diagnostic call. On the GPU these are
    dead immediately but not reclaimed: Julia's garbage collector triggers on *host* memory pressure, and a
    dead device array is a tiny host wrapper owning a large *device* buffer (the mechanism of decision 24),
    so the pool climbs. One ``256^3`` correlation snapshot churned several GB; with the live working set
    already ``\sim\!6`` GB, the first snapshot wedged a 12 GB card (the allocator spinning, GPU idle).

    The fix replaces the per-shell loop with a single **scatter-add** pass — one portable
    `KernelAbstractions` + `Atomix` histogram kernel (`_shell_bin_kernel!`, driven by `_bin_by_shell`) that
    sweeps the array once and, per element, atomically adds the value (and a unit population count) into the
    accumulator of its shell, keyed by a precomputed integer shell index. (Decision 34 later fused even
    that staging away: the shell index and the binned quantity are now derived per element inside the
    kernels, and the precomputed-index pair retired.) Per-call full-grid temporaries
    drop from ``O(N)`` to ``O(1)`` (the shell-index array, the binned quantity, and the tiny
    length-``(\text{number of shells})`` accumulators): the spectrum keeps the value sum (normalized by
    ``N^2``), the correlation divides it by the per-shell population. This is the *same* atomic scatter the
    point→grid `anterpolate` already uses ([§10](@ref "10. Interpolation and anterpolation (the grid↔point transfer layer)")),
    now depositing mode/point energies into radial shells instead of point quantities onto the grid; it
    lifts the "histogram scatter deferred as unneeded" sub-decision of decision 21. The trade-off —
    contention on the small accumulator set — is acceptable for an *occasional* diagnostic (every
    `snap_stride` steps in a solver), and the old form was itself ``O(\mathrm{shells}\times N^3)`` work; a
    privatized/shared-memory histogram is a possible future optimization, unneeded now.

    Correctness is unchanged (the scatter sums the same per-shell quantities as the masked reductions): CPU
    `test/reductions.jl` (the analytic ``\langle\sin^2\rangle`` and independent binned-circshift oracles,
    both element types) and GPU parity `test/gpu/suite.jl` (`allowscalar(false)` — the scatter is
    device-clean, no scalar indexing) both hold. End to end, the ``256^3`` Float32 forced-HIT example
    on a 12 GB card (``\approx 87`` ms/step) now runs to completion at a flat ``\sim\!6`` GB
    (``\approx 8`` GB peak) through its `radial_correlation` snapshots, where the per-shell form wedged at
    the first one.

26. **Allocation-free in-place operators are a standing, exhaustively-enforced contract (generalizing 24
    and 25).** Decisions 24 (the spectral operators) and 25 (the radial binning) each fixed *one* family
    that allocated a per-call temporary the GPU could not afford. This decision promotes the property from
    a sequence of point fixes to a package-wide invariant: **every in-place `!` operator allocates no
    field-sized scratch** when called on preallocated buffers with a destination distinct from its sources
    — kernels fuse their temporaries into the assignment, never materialize them. The motivation is the one
    from decision 24: a solver applies these operators thousands of times per step, and on the GPU a
    per-call temporary escapes Julia's garbage collector (which triggers on *host* memory pressure, while
    the temporary is a *device* buffer behind a tiny host wrapper), so the device pool grows every step
    until the run wedges or `hipMalloc` aborts.

    *The enforcement is an exhaustive test, `test/allocations.jl`.* It warms one in-place call per signature
    and asserts a second `@allocated` call stays below a small fraction of one field — across both element
    types, both representations, tensor orders ``R = 0, 1, 2``, the field/constant/reversed and α/β argument
    branches, the point-value algebra, and the spline transfer (the *whole* in-place surface, not a sample).
    **It runs on the CPU on purpose:** there a materialized field is a host `Array` and `@allocated` counts
    its full bytes, so a stray temporary trips the threshold; on the GPU the same `similar`/broadcast
    allocates a *device* buffer whose host wrapper is only a few hundred bytes, so GPU `@allocated` would
    report ``\sim 0`` and miss the leak. The operator code is generic over the array type, so a
    field-sized **materialization** — a `similar` or a broadcast landing in a temporary — is
    backend-symmetric: seeing it on the CPU is seeing it on the GPU, and the CPU is simply where it is
    visible. That symmetry covers the materialization class, not every byte a device run allocates: a
    `KernelAbstractions` launch also takes a small, size-independent host-side bookkeeping allocation
    (finding (j), ~1.5–7 KB, thread-count-dependent) with no CPU-serial counterpart, which the audit's
    fraction-of-a-field threshold absorbs rather than measures — sound, because the leak this contract
    exists to stop scales with the grid and bookkeeping does not.
    The contract binds new code: a
    new in-place operator (or any function documented allocation-free) must be added to the audit
    (invariant 13; the §4 coverage contract in `docs/TESTING.md`).

    *Documented exceptions — bounded, not zero.* A few operations materialize one field *by design* and are
    excluded from the zero assertion, getting a *bounded* guard instead (catching a regression to ``O(N)`` —
    or ``O(\mathrm{shells})`` — extra while allowing the legitimate one-field temporary): the fiber
    `norm!`/`lpnorm` (a pointwise magnitude) and
    the radial diagnostics (``O(1)``-bounded); `dev!` left this list when decision 39 fused its trace
    into a register, and `std`/`var` when decision 49 rewrote them as two fused passes — measured at 16
    bytes rather than a field. The spectral `inner` is the subtle case (``N``
    the points per axis): `inner(f, f)` — an energy or `l2norm` — is allocation-free, since
    ``\overline{\hat f} \hat f = |\hat f|^2`` is real and the whole Parseval sum, correction planes
    included, is a fused `sum(abs2, …)`; but the mixed `inner(f, g)` of two distinct fields allocates an
    ``O(N^2)`` kₓ-plane correction, because a `dot` over the strided plane view (which would fuse, no
    temporary) has no method on the AMD path (rocBLAS `dotc` takes no strided argument — verified on the
    device), and one route serving every backend is preferred to a per-vendor split.
    Consumers form a hot-loop energy as `inner(f, f)` or the physical `inner` (a contiguous `dot`); the
    `examples/` forcing computes its band energy as `inner(u_band, u_band)` for exactly this reason. The
    audit found the whole in-place surface already clean; the only allocation it surfaced was the mixed
    spectral `inner`, resolved by the `inner(f, f)` fast path above.

27. **Consumer-driven fused and missing field-math operations — `combine!`, `det`, `symmetric_gradient`,
    `weighted_inner` (done); a quadratic-form reduction deferred.** The sibling consumer
    `GBGIsotropicTurbulence` (a thin physics solver built on this field layer) asked the package to absorb
    the field-math it hand-rolls hottest, on the principle that a field library should serve its consumer the
    way **numpy/BLAS serve scientific Python** — not only composable primitives, but *fused* kernels for the
    recurring composites. The reason is concrete: Julia fuses within a single broadcast or `mapreduce` but
    **not across function-call boundaries**, so a chain like `gradient!` → `sym!` → `inner` is three separate
    passes that each materialize a tensor-sized intermediate — and on a memory-bound GPU consumer that
    intermediate's peak footprint, not the bandwidth, is the binding constraint. The rule for what to absorb:
    **fuse away the intermediate the consumer never needs, or supply a genuinely missing primitive** — never
    add an operation "for completeness" (invariant 1). An adversarial triage kept four and deferred one; each
    kept operation is general field math with no time, particles, or physics (invariant 12 — the physics
    names stay consumer-side).

    *The four, by family.*
    - `combine!(dest, α, a, β, b)` (`FieldAlgebra`) writes the real-weighted combination ``\alpha a +
      \beta b`` of two same-representation fields ``a, b`` with real weights ``\alpha, \beta``, in one fused
      pass. It was a genuine gap: `add!` is unit-weight (``a+b``) and `multiply!` scales a single field, so
      the weighted combination (an axpby) had no form and the consumer reached into field storage with
      hand-rolled broadcasts at nine call sites. It completes the package's own ``\alpha/\beta`` accumulation
      convention (already on `mul!`/`convolve!`); being linear in the fields it is defined in **both**
      representations, and being coefficientwise it is alias-safe with no guard (``a`` or ``b`` may be
      `dest`). It is a new verb rather than a five-argument `add!`, to keep `add!`'s constant-variant dispatch
      clean. It stays **field-only** — the consumers are field updates, and the package does not add a
      point-value method for symmetry alone.
    - `det`/`det!` (`FieldAlgebra`) is the fiberwise determinant, the **third principal invariant** ``I_3``
      (the signed factor by which the tensor scales volumes as a linear map) — the sibling of the trace
      ``\operatorname{tr}`` (the first invariant ``I_1``) the
      package already carried; the gap was the missing invariant, not a completeness fill. The second
      invariant ``I_2`` stays absent, having no consumer — and a consumer that wants it can build it
      from the two that ship, as ``I_2 = \tfrac{1}{2}(I_1^2 - \operatorname{tr}(A^2))``. Being cubic
      in the components it is **nonlinear**, so it is physical-space only (there is no spectral
      determinant), exactly like `norm`. It reuses the shared per-component formula builder in
      `FiberSections`, so it lands on **both** fields and point-values (mirroring ``\operatorname{tr}``, which
      already lived on both) with the formula written once.
    - `symmetric_gradient`/`!` (`DifferentialOperators`) forms the symmetric part of a vector field's
      gradient, ``S_{ij} = \tfrac{1}{2} (\partial_{x_j} u_i + \partial_{x_i} u_j)`` for a vector field ``u``,
      **directly** — spectrally ``\hat S_{ij} = \tfrac{\mathrm{i}}{2} (k_j \hat u_i + k_i \hat u_j)`` with the
      same Nyquist-correct derivative wavenumbers ``k`` as `gradient` — skipping the full nine-component
      gradient tensor ``\nabla u`` that `sym(gradient(u))` builds only to symmetrize. It is the **fused
      symmetric peer of `curl`**, which already extracts the *antisymmetric* part of ``\nabla u`` (as a
      vector). The name is the charter-neutral mathematical one; the fluids name "strain rate" stays in the
      consumer, exactly as the package says `curl` where the consumer says "vorticity".
    - `weighted_inner(f, w)` / `weighted_inner(f, g, w)` (`Reductions`) is the multiplier-weighted L² inner
      product of two fields ``f, g`` in spectral representation against a real Fourier multiplier ``w(k)``,
      ``\langle f, w g\rangle = \tfrac{1}{N^2}\sum_k \alpha(k) w(k)\sum_c \mathrm{Re}(\hat f_c 
      \overline{\hat g_c})`` (with ``\alpha(k)`` the rfft half-spectrum Parseval weight — a fixed
      per-mode function, distinct from the scalar accumulation weight ``\alpha`` of `combine!` above —
      ``N`` the grid-point count, and ``c`` the fiber index) — the field ``g`` filtered by ``w`` and paired with ``f`` in one
      fused pass with no filtered field materialized. It is the **reduction-dual of `convolve`** (apply a
      spectral symbol, then reduce) and generalizes `inner` (the ``w \equiv 1`` case); ``w = |k|^2`` gives the
      ``H^1``/Dirichlet energy ``\langle f, -\Delta g\rangle``. Spectral representation only, like the
      Parseval `inner`. The consumer formed in-band energy every step as `convolve!` into scratch then
      `inner`; the fused form removes that scratch field.

    *The deferral.* A fifth request, a quadratic-form reduction ``\langle v, A v\rangle =
    \operatorname{mean}(v_i A_{ij} v_j)`` (a vector field ``v`` contracted through a second-order tensor field
    ``A``), was **declined for now**: its own request flagged it "for completeness of the fused-reduction
    set", its saving is a single *vector* intermediate at diagnostic cadence, and its consumer (the enstrophy
    production ``\langle \omega_i S_{ij} \omega_j\rangle``, the vorticity ``\omega`` through the strain ``S``)
    is not yet live — so by the [§2](@ref "2. The central principle: the architecture follows established mathematics") rule against speculative structure it waits until that consumer
    lands, when it is a small addition on the existing `inner` machinery.

    *Scope and verification.* The public method set grows to **206** field methods (from the 202 the
    earlier trace addition left, `combine!` adding 2 and `det`/`det!` 1 each) and **122** point-value
    methods (from 120 — the same earlier trace addition that took the field surface 198 → 202 carried
    `tr`/`tr!` onto point-values, 118 → 120 — `det`/`det!` 1 each); `symmetric_gradient` and
    `weighted_inner` live in other modules and leave those baselines untouched. Each operation carries the
    full definition-of-done: a CPU behaviour test against an independent oracle over both element types (and
    both grids where they apply), GPU device-parity, the `test/allocations.jl` guard
    (`combine!`/`det!`/`symmetric_gradient!` allocation-free; `weighted_inner` allocation-light — only a
    small per-axis weight vector, far cheaper than the radial reductions
    `radial_spectrum`/`radial_correlation`, which build an ``O(N)`` shell-index pass), and a benchmark.
    That `combine!` stays field-only and the quadratic form waits both follow the same rule: **the consumer,
    not symmetry, decides where an operation lives.**

28. **Spectral translation — `translation_kernel`, and the reality condition a complex kernel must meet.**
    The sibling consumer `GBGIsotropicTurbulence` asked for a fifth kernel builder: the multiplier that
    **translates** a field by a physical displacement ``h = (h_1, h_2, h_3)`` (a length
    per axis, in the box's units), carrying a field ``f`` at position ``x`` to the displaced field
    ``f(x - h)``. Its consumer is phase-shift de-aliasing, where the nonlinear product is evaluated a
    second time on a half-cell-displaced grid and averaged with the unshifted evaluation — the memory-lean
    alternative to padding the grid; it also serves shift-and-average filters and the relocation of a probe.

    *Why the package owns it.* Translation is a **coordinate-only** operation on the field, with no physics
    in it — the exact sibling of the derivative and cutoff multipliers the package already owns — and by the
    shift theorem it *is* a convolution: with the Dirac delta displaced to ``h``, whose transfer
    function is the pure phase ``\hat g(k) = e^{-\mathrm{i}  k\cdot h}`` at wavenumber ``k``. So it needs
    no new operation, only a new kernel (decision 20): `convolve!` already applies a scalar kernel to any
    tensor order, with its accumulation weights, alias-safely. **Only the builder was missing** —
    the package exposes no function-of-wavenumbers constructor, and the allocation helper `similar_field` is
    internal, so a consumer cannot build the kernel without reaching into the package's internals.

    *The correctness trap — the real reason it belongs here.* A kernel must leave a **real** field real. The
    rfft half-spectrum stores only the modes whose first wavenumber component is non-negative; the rest are
    implied by the reality of the field, ``\hat f(-k) = \overline{\hat f(k)}``. Multiplying by a kernel
    preserves that symmetry — and so returns a field rather than a complex impostor — exactly when the kernel
    is itself Hermitian, ``\hat g(-k) = \overline{\hat g(k)}``, equivalently when its physical-space form
    ``g`` is real. The four kernels shipped before this one are real and even in ``k``, so they satisfy the
    condition without anyone having to think about it. The translation phase does not, at one frequency per
    axis: the **Nyquist** frequency of an even-length axis (with ``N_a`` points and spacing ``\Delta x_a``
    along axis ``a``), the mode that is its own conjugate partner and where the kernel is therefore forced to
    be real. The two obvious candidates each fail, and they fail *differently*:
    - The **true phase** ``e^{-\mathrm{i}  k\cdot h}`` built from the signed wavenumbers is complex at
      Nyquist for a fractional displacement, so it returns coefficients that are no real field's — the
      inverse transform then silently keeps only their Hermitian part. (Whole-cell displacements are safe:
      the factor there is ``(-1)^m`` for a displacement of ``m`` cells, which is real.)
    - The **Nyquist-zeroed derivative wavenumbers** — the ones `gradient` uses, and the fix the request
      itself proposed — do keep the kernel real (the factor becomes ``1``), but the value is *wrong*: they
      leave the Nyquist mode unmoved, where a one-cell shift must flip its sign.

    The correct multiplier follows from what the Nyquist mode *is*. It carries a single real amplitude
    standing for both of the wavenumbers ``\pm\pi/\Delta x_a``, so its band-limited form is the cosine
    ``\cos(\pi x_a/\Delta x_a)``, and displacing that cosine and re-sampling it on the grid multiplies it by
    the real factor ``\cos(\pi h_a/\Delta x_a)`` — equal to ``(-1)^m`` for a whole-cell displacement of
    ``m`` cells, and to ``0`` for a half-cell one, a displaced Nyquist mode being genuinely not representable
    on the same grid. Splitting the phase into its even and odd parts,
    ``e^{-\mathrm{i} k_a h_a} = \cos(k_a h_a) - \mathrm{i} \sin(k_a h_a)``, states the rule in
    one line: **the even (cosine) part takes the true wavenumber, the odd (sine) part takes the derivative
    wavenumber.** Those are exactly the package's two multiplier families (invariant 5: squared wavenumbers
    keep the true value at Nyquist, derivative wavenumbers are zeroed there), so the builder is a
    three-factor broadcast and the Nyquist correction falls out of a convention already in place for the very
    same reason — an odd function of ``k`` must vanish at Nyquist to keep a real field real, which is why the
    derivative multiplier is zeroed there. The `translation_kernel` builder is the first operation to use **both**
    families, and it confirms that split rather than excepting it.

    *Consequences, documented on the operation.* The kernel is a pure phase of unit modulus on every resolved
    mode, so it moves the field without touching any amplitude; at Nyquist it is a real attenuation instead.
    Translations therefore compose and invert exactly on the resolved band but not at Nyquist (displacing by
    ``h`` and back scales that one mode by ``\cos^2``). None of this reaches a field already truncated
    by a de-aliasing cutoff, which is the consumer's case.

    *Scope: the builder only.* No fused `translate!` — a `convolve!` that builds its own kernel — although
    the request offered one. The kernel depends on nothing but the displacement, so building it per call
    would allocate a field-sized array on every invocation, exactly the allocation the package forbids in
    place (decisions 24, 26). The family's build-once-apply-many pattern is already the right one: a
    displaced evaluation builds the two kernels (for ``+h`` and ``-h``) once and applies them with
    `convolve!` at zero allocation.

    *Verification.* Two independent oracles pin the operator, and each rejects one of the wrong kernels: a
    whole-cell displacement equals `circshift` **on a random field**, which carries content at every mode
    including Nyquist; and a sub-cell displacement equals the exact `DirectDFT` evaluation of the field at
    the displaced nodes ``x_n - h`` (decision 23). The random field matters — the band-limited fields the
    older convolution tests use pass with *any* of the three candidate kernels, which is precisely how a
    hand-rolled kernel gets away with being wrong. Reality is checked directly (transforming the displaced
    field out and back is the identity, the inverse transform being the Hermitian projector, so a
    non-Hermitian result would move), alongside the analytic displaced cosine, the Nyquist attenuation, and
    unit modulus on the resolved band — over both element types, a mixed-parity grid, GPU device-parity, and
    a benchmark. The method-set baselines (206 field / 122 point-value methods) are untouched: like
    `convolve` itself, this is a new generic in `Convolution`.


29. **HDF5 field persistence — `write_field` / `read_field`, a weak-dependency extension.** The sibling
    consumer `GBGStreamingStatistics` ships `write_histogram` / `read_histogram` to persist its durable
    summaries to HDF5; the request was the field analogue, so a solver can **checkpoint a field for
    restart**, dump a **full-resolution snapshot** for later analysis, or hand a field to another tool as
    easily as it dumps statistics. The demos already hand-rolled HDF5 for their plotted curves; this makes
    the fields themselves first-class.

    *Persistence, not a mathematical operation — so it does not touch the math API.* Serializing a field is
    I/O, not an operation on sections, so the rule that design changes be justified by established
    mathematics ([§2](@ref "2. The central principle: the architecture follows established mathematics")),
    which governs the *operation set*, does not bar it — and the mechanism keeps it out of the way:
    `write_field` / `read_field` are a **weak-dependency package extension** (`[weakdeps]` HDF5 +
    `[extensions]`, methods in `ext/GBGPeriodicFieldsHDF5Ext.jl`), so the HDF5 binary never enters the core
    and a user who does not persist pays nothing. Bare `function write_field end` stubs and their docstrings
    live in `Fields`, so `?write_field` and the manual work without HDF5 loaded; the methods appear only when
    it is. This mirrors the sibling exactly.

    *The line held (invariant 12 — no time).* A field is a self-describing object — its numeric array plus
    its `Grid3D` geometry, Fourier layout, element type, and tensor order — so it maps onto **one HDF5
    group**: the array is the dataset `data`, and everything else is attributes (a `type` tag, a schema
    `version`, the grid geometry, the `fft_dims`, the element type, the tensor order, the representation).
    The primitive is **one field at a time**, and — the load-bearing choice — it takes an *open* `File` or
    `Group`, never a path. So the consumer bundles a whole **iteration snapshot** (velocity, vorticity, …)
    into one file under separate names and attaches *its own* `time` / `iteration` attributes: the package
    serializes the fields, the consumer owns the bundling and every notion of time. There is no `Snapshot`
    type and no clock in the field layer. A field group and a `GBGStreamingStatistics` histogram group share
    the same self-describing-group convention, so a run's fields and its statistics can live in one file.

    *Both representations, host and device.* A field in physical representation stores a real array; a field in spectral
    representation stores its complex half-spectrum (HDF5 round-trips complex arrays). Device (GPU) arrays
    are copied to the host on write via `Array(…)` — backend-agnostic, a no-op on the CPU — and the reload is
    a host field the consumer moves to a device if wanted. On read, `read_field` dispatches on the stored
    `type` tag and reconstructs through the public constructor: the element type follows the stored array (real or
    complex), the tensor order follows its dimensionality, and the grid spacing is recomputed bit-for-bit, so
    the reload is **exact**. The sugar `parent[name] = field` is `setindex!` for `write_field`, made strictly
    more specific than HDF5's own array-writing `setindex!` so it never clashes.

    *Scope.* Every field type (the six: scalar / vector / tensor × physical / spectral); no compression or
    chunking options until a consumer needs them; no snapshot / time type (invariant 12).

    *Verification.* The round-trip test `test/hdf5.jl` covers every field type over both element types,
    asserting the data (real and complex), the full `Grid3D` geometry, the element type, the tensor order,
    and the layout are recovered bit-for-bit; it exercises the `setindex!` sugar, a snapshot bundle carrying consumer-owned
    `time` / `iteration` attributes, the self-describing attributes read back as plain HDF5, and the error
    paths (a dataset instead of a group, an absent name, a group with no type tag). The method-set baselines
    (206 field / 122 point-value methods) are untouched — `write_field` / `read_field` are new generics, and
    their methods exist only under the extension.


30. **Mapped reductions — a leading function on five of the measure reductions.** The consumer
    `GBGIsotropicTurbulence` audited its memory and found a recurring shape: to average a nonlinear
    invariant of a tensor field — the determinant of a strain tensor, the magnitude of a velocity — it had
    to build that invariant as a **whole section** first and then reduce it, paying one field of scratch
    for a single number. Here a *section* is a field or a set of point-values, and its **fiber value** at a
    base point is the scalar, vector, or ``3 \times 3`` tensor sitting over that point. So five reductions
    gained a form taking a leading function, applied to the fiber value at every base point:
    `mean(det, A)` averages a determinant, `maximum(norm, u)` takes a supremum of magnitude, and the
    mapped quantity is consumed as it is formed rather than stored.

    *The standard library sets the surface, including where it stops.* The mapped spellings mirror
    `Statistics`' `mean(f, itr)` and `Base`'s `sum`/`maximum`/`minimum`/`extrema` with a leading function,
    so `mean`, `maximum`, `minimum`, `extrema`, and the package's own `integral` (the extensive peer of
    `mean`) take one. `Statistics` gives `var` and `std` **no** such method, so neither does this package:
    inventing a spelling the standard library declines to have would be exactly the "for completeness"
    addition invariant 1 exists to refuse. Being a nonlinear map of the fiber, the mapped forms are
    **physical-only**, like `lpnorm` and `std` before them.

    *It reconciles an older deliberate absence rather than overturning it.* The bare
    `maximum`/`minimum`/`extrema` are scalar-section-only on purpose: the supremum of a vector or tensor
    section is ambiguous between the components and the magnitude, and the package refuses to guess
    ([§12](@ref "12. Reductions")). The mapped form does not guess — the caller *names* the map, so
    `maximum(norm, u)` is well posed where `maximum(u)` is not. The absence was of an ambiguous operation,
    and naming the map is precisely the condition that removes the ambiguity, so the mapped forms carry no
    *ambiguity* restriction. That is the restriction this entry lifts, and it is not the same as carrying
    no ceiling at all: decision 56 later fixed the supported surface at ``R < 3``, and the
    fiber-preserving and mapped reductions throw above it rather than return a wrong answer. They also give a fused peer to `lpnorm(u, Inf)`, which computes the same
    supremum of magnitude by materializing a magnitude section first.

    *Fiber-last layout dictates the implementation, and hides two allocation traps.* Because components are
    stored last (invariant 3), a base point's components sit a whole base apart, so a fiber cannot be
    reinterpreted into a `StaticArray` in place; the fiber is instead gathered through a lazy `Broadcasted`
    over the component arrays, which reduces in one pass on both backends. Two spellings that look
    equivalent are not, and each silently allocates:
    - the multi-argument `mapreduce(fiber_map, combine, components...)` is fused by `GPUArrays` but falls
      back on the CPU to a route that materializes a full section-sized array;
    - an anonymous `(values...) -> fiber_map(V(values))` leaves the component count uninferrable, so the
      fiber cannot be built in registers and the reduction allocates per base point — measured at about
      four and a half times the tensor section's own size. A callable struct carrying the fiber type
      restores the inference.

    A third trap sits in the public signatures: Julia declines to specialize on an argument of `Function`
    type that a method only forwards instead of calling, so each mapped form names its map's type as a
    parameter. Without that, the map arrives boxed and every call allocates. All three are guarded by the
    `@allocated` audit, which pins the whole family at zero bytes.

    *The reduction is split by backend, so the fused route wins on both.* How a reduction consumes its
    input is where the backends disagree, and a single formulation cannot serve both. Reducing a
    contiguous array uses a vectorized blocked loop; reducing a lazy `Broadcasted` forgoes that loop, at
    a measured ``5.6\times`` on the reduction alone — more than materializing an extra section costs in
    traffic. A GPU has no such loop to forfeit: its reduction is thread-parallel and bandwidth-bound, so
    index arithmetic hides behind memory latency and the section write and read-back that fusing skips
    is pure profit. The implementation therefore reduces through a **vectorized blocked loop over the
    component arrays on a CPU** and **one fused pass over a lazy `Broadcasted` on a GPU**. Measured with
    the same map on both sides (`mean(det, A)` against `mean(det(A))`, ``N = 128``, `Float64`), the fused
    route then costs 5.1 ms against 13.0 ms on a CPU and 0.55 ms against 0.69 ms on a GPU — cheaper on
    both, allocating nothing against one full section. The CPU loop blocks pairwise like Base's own
    reduction, which also makes it the *most accurate* of the routes (relative error ``1.2\times10^{-16}``
    against the lazy form's ``3.7\times10^{-15}``). The strided gather that fiber-last layout forces
    costs only about ``2\times``, and building the `StaticArray` per base point is free.

    *A caveat that outranks the route, recorded because it misled this analysis twice.* The fiber map's
    own cost can outweigh the choice of reduction entirely. `LinearAlgebra.norm` applied to a fiber uses
    the overflow-safe scaled 2-norm, measured at ``4.3\times`` the plain ``\sqrt{\sum_i u_i^2}`` that the
    fieldwise `norm` evaluates. Comparing `maximum(norm, u)` against `lpnorm(u, Inf)` therefore varies the
    algorithm *and* the route at once, and reads as a fusion penalty that is not the fusion at all —
    given the same formula, the fused form is 1.8 ms against 4.2 ms. Vary one thing at a time when
    measuring this family. The `integral` docstring carries the practical form of both points for the
    reader who never opens this file.


31. **The Julia compat floor moved 1.11 → 1.12, on a measurement rather than a preference.** The package
    declared `julia = "1.11"`, and CI ran that as an explicit compat-floor lane beside current stable. The
    floor is now 1.12, so the matrix differs only in thread count (`-t1` against `-t4`) and the local
    pre-commit run is a single lane.

    *What the measurement showed, which is the opposite of the obvious guess.* On 1.11 the package **runs
    faster** — every operation measured, on a ``64^3`` grid in `Float64`, in the **threaded** lane (so these absolute
    times are not comparable with §4(l)'s single-thread column, and none of them needs to be — the
    comparison here is one Julia version against another on one fixed configuration): `mean(det, A)` 0.241 ms against
    0.251, the threaded assignment `add!` 0.296 against 0.338, `radial_spectrum` 1.743 against 2.288,
    `inner` 0.012 against 0.017. What is slower is **compilation**, by a wide margin and concentrated in
    exactly the generated and broadcast-heavy surfaces this package is built from: first-call cost for
    `add!` (the `_assign!` primitive) is ``4.5\times`` higher on 1.11, and the `KernelAbstractions` binning
    path ``1.4\times``. That is why the two slowest testsets were `threading.jl` and the radial-diagnostic
    allocation audit, and why a full `Pkg.test()` took 31 minutes on 1.11 against 5.4 on 1.12.

    *Why "make it as fast" was not on the table.* The gap is Julia 1.11's compiler working on our
    `@eval`-generated method families and fused broadcasts, not a pathology in the package — there is
    nothing here to fix. Baking the workload into the precompile image with `PrecompileTools` would
    relocate the cost to precompile time rather than remove it, for a standing maintenance surface. So the
    choice was to pay 31 minutes per pre-commit check or to drop the lane; since the local run is
    mandatory (CI is manual-only, [`TESTING.md`](testing.md)), the tax fell on every commit.

    *What it buys, and what it costs.* Dropped with it: the per-version manifest dance (the gitignored
    top-level `Manifest.toml` is Julia-version-specific, so running the second lane meant moving it aside
    and restoring it — a footgun that bit twice while gathering the numbers above), and the wide lower
    bound on the `LoweredCodeUtils` test pin, which existed only to admit the older `JET` that 1.11
    resolved to. The cost is that the floor now tracks current stable closely, and that sibling packages
    declaring `julia = "1.11"` — `GBGIsotropicTurbulence` does — must be bumped in step, or they claim
    support for a Julia their dependency no longer builds on.

32. **The one-pass Helmholtz kernel, and a convolution fused into the projection and the divergence
    (the operator ∘ kernel family).** Two requests from the consumer package `GBGIsotropicTurbulence`
    ("IT") — items 1 and 6 of its 2026-07 memory and compute audits — triaged adversarially and landed
    as one kernel rewrite, because they touch the same code.

    *The one-pass projection.* `helmholtz_projection!` — the Leray/Helmholtz projection ``\mathbb P``,
    which removes a vector field's curl-free part — used to run as three fused broadcasts, one per
    output component, each recomputing the longitudinal factor ``k_j \hat u_j / |k|^2`` (the
    wavenumber-parallel part of the field, ``k`` the wavenumber vector and ``\hat u`` the field's
    spectral coefficients) from all three source components: nine component reads per mode for three
    writes, and an in-place call (destination aliasing the source) was detected and routed through a
    guard temporary costing one full vector field per call — the single largest transient in IT's
    measured budget, and the one op whose *natural* call is in place. It is now a single portable
    `KernelAbstractions` kernel (the package's third KA site, after the transfer kernels and the shell
    binning): per mode, the three source values are read into registers, the longitudinal factor is
    computed once, and the three destinations are written. Three reads for three writes, and
    **alias-safe by construction** — all of a mode's reads precede its writes, and modes are disjoint —
    so the guard and its temporary are retired ([§7](@ref "7. Aliasing policy")) and the aliased call is
    bitwise-identical to the non-aliased one. Two implementation notes worth recording: the sources are
    deliberately **not** marked `@Const`, whose no-other-writes promise the aliased call would break;
    and the KA launch keeps a small size-independent host-side bookkeeping allocation (measured
    ``\sim``1.5–7 KB, thread-count-dependent), which the allocation audit's fraction-of-a-field
    threshold absorbs — the field-sized temporary is what is gone. Measured on the 12700K, the rewrite
    is 2.7–6.5× faster than the three-broadcast form (``64^3``–``128^3`` Float64, one and four
    threads) — the memory fix paid compute, as predicted: the projection is bandwidth-bound, and nine
    reads became three.

    *The kernel-composed forms.* `helmholtz_projection!` and `divergence!` gain trailing
    `kernel[, α, β]` arities: `op!(dest, f, multipliers, kernel)` and
    `op!(dest, f, multipliers, kernel, α, β)`, with the four-argument form delegating with `one(T)`,
    `zero(T)` (invariant 10) and allocating `op(f, multipliers, kernel)` wrappers. The mathematics is
    the [§4](@ref "4. Spectral machinery") multiplier picture closing under composition: a
    coefficientwise kernel ``\hat g`` (a Fourier symbol, as `convolve!` takes it) commutes through both
    operators — scalar times matrix symbol for ``\mathbb P``, scalar times the contraction
    ``\mathrm{i} k \cdot`` for the divergence — so "operator then convolve" is itself one Fourier
    multiplier, and the fused form computes it in the operator's own pass. The consumer pattern it
    serves is mask-de-aliasing: every de-aliased right-hand side in a pseudospectral solver is the
    operator followed immediately by `convolve!` with the de-alias kernel, so fusing saves that pass's
    full read and write of the destination (two passes of the field's class per evaluation). **The
    `α`/`β` pair is load-bearing, not completeness**: the fused form *replaces* a `convolve!` that
    carries `α`/`β` — IT already rides the ``-\nabla\cdot`` sign of its scalar advection on
    `convolve!`'s `α` — so shipping less would strand the very chains being fused; and `β` collapses
    IT's phase-shift de-aliasing tail entirely, as two projection calls — the primary with the de-alias
    kernel at ``\alpha = 1/2``, the displaced evaluation with the **composed** kernel (de-alias ∘
    shift-back, built once at setup by the kernel composition `convolve(g₁, g₂)`) at
    ``\alpha = 1/2``, ``\beta = 1`` — eliminating
    the standalone shift-back, average, and truncation passes (four passes per evaluation at wiring
    time; two more were already banked consumer-side by rewriting the average as `convolve!`'s
    five-argument form). The `curl!` operator deliberately does **not** get the kernel arity: IT's curls feed
    transforms directly, so there is no consumer — the absence is the §2 **no-speculative-structure**
    rule, *not* invariant 1. The distinction matters and the two must not be blurred: invariant 1's
    absences are mathematical statements a user can rely on (a spectral `*` is invalid and always will
    be), while this one is merely unbuilt — `curl!` is exactly as composable with a kernel as
    `divergence!`, and the arity would be added the day a consumer wants it. Recorded
    here. Validity is unchanged: spectral-only, the kernel under `convolve!`'s Hermitian reality
    condition, and the Nyquist split untouched (per-mode scalars multiply regardless of their Nyquist
    values). Guards: the fused-equals-sequential equalities, the α/β references, the bitwise aliased
    projection, and the kernel-aliasing case in `test/differentialoperators.jl`; zero-allocation pins
    for every new arity and the aliased call in `test/allocations.jl`; device-vs-host parity in
    `test/gpu/suite.jl`; the fused-vs-sequential benchmark rows in the `operators` class.

33. **The exponential radial kernel and the kernel-composed combination (the lazy-kernel pair).** Two
    requests from `GBGIsotropicTurbulence`'s audits — items 2 and 7 — landed as one broadcast-builder
    family in `Convolution`, because the second is the first with a two-field prologue.

    *The exponential family.* `exponential_convolve!` (allocating `exponential_convolve`) applies the
    exponential radial kernel ``\exp(c |k|^2 + s \hat w)`` — ``c`` a real coefficient on the squared
    wavenumber ``|k|^2``, ``\hat w`` an optional real per-mode exponent field with real scale ``s`` —
    evaluated **lazily from the three one-dimensional wavenumber arrays** inside the fused assignment.
    The kernel is never built, so against the stored-kernel route (`radial_kernel` →
    consumer broadcast → `convolve!`) it removes the kernel's residency, its build pass, and its full
    field read per application, reading ``O(N)`` wavenumber rows instead (``N`` the points per axis).
    The measured trade is a **reuse question** ([`PERFORMANCE.md`](performance.md) finding (k)): with a
    varying exponent — the consumer's case, whose stage substeps differ — the lazy form beats
    rebuild-then-apply by ``\approx 1.4\times`` on the GPU; with one fixed kernel applied many times
    the stored route keeps a ``\approx 1.1\times`` (GPU) to ``\approx 1.7\times`` (CPU) edge, the
    per-mode exponential costing more than the field read it saves. The two-operand fused forms below
    win on both backends regardless (``\approx 1.1``–``1.5\times``, the CPU two-operand case the low
    end — the finding-(k) table of `PERFORMANCE.md` is the source of record).
    For ``c \le 0`` the kernel is, as a real physical object, the periodic Gaussian: the operator
    ``e^{-c\Delta}``, smoothing at length ``\sqrt{-2c}`` — and the identification is exact on the
    grid because the exponent uses the same true-Nyquist squared-wavenumber family as the Laplacian's
    own symbol (invariant 5).

    *The boundary, and two signature decisions made against the request's framing.* The consumer
    framed the exponent as built from a diffusivity and a substep; neither crosses PF's boundary
    (invariant 12) — the consumer folds them into the dimensionless ``c``, and the name "rate" was
    declined (a rate is per-unit-time, and the array that would cross is the dimensionless product,
    not the rate). Working the consumer's stage structure sharpened the offset into its final shape:
    a **scalar** exponent offset does not exist, because ``\exp(c|k|^2 + s_0) = e^{s_0} \exp(c|k|^2)``
    folds into the accumulate weight ``\alpha`` — a deliberate absence; and the **per-mode** offset
    enters as **scale times field** (``s \hat w``, not a pre-scaled array), because the consumer's
    substeps vary per stage — with a bare offset array every stage would pay a full array rebuild,
    while the scalar ``s`` is free and the resident ``\hat w`` is built once.

    *The kernel-composed combination.* `combine!` gains the method
    `combine!(dest, α, a, β, b, kernel)` — the weighted combination convolved with a stored kernel,
    ``\hat g \cdot (\alpha \hat a + \beta \hat b)``, in one coefficientwise pass — and
    `exponential_convolve!` carries the same two-operand form with its lazy kernel. The consumer
    evidence is the integrating-factor state update (a `combine!` followed immediately by a
    `convolve!` with the factor, per stage per field — two full passes of the destination saved per
    site, about six vector plus six scalar passes per three-stage step); the lazy twin additionally
    retires the factor's per-stage build. A third proposed consumer — the phase-shift average — was
    found not to be an instance of this form at all (its kernel lands on one operand), and is served
    instead by decision 32's ``\beta`` accumulate; the correction is recorded there. With
    ``b === \texttt{dest}`` the method computes the kernel-filtered accumulate in place
    (coefficientwise, hence alias-safe with no guard), which is why it carries **no** second trailing
    accumulate pair — two ``\alpha``/``\beta`` roles in one signature is the glyph-collision failure
    mode, and the aliasing provides the accumulate for free.

    *Naming and the method-set bookkeeping.* The kerneled combination is a **method of `combine!`
    with a trailing kernel argument** — the decision-32 composition idiom (`divergence!` and
    `helmholtz_projection!` compose the same way) — not a new verb; the earlier `weighted_inner`
    naming (decision 27) is the *reductions* family's convention and stands there. The method is
    defined in `Convolution`, and the honest reason is narrower than "include order": `DifferentialOperators`
    precedes `Convolution` too and kept its own kernel-composed `divergence!`/`helmholtz_projection!`
    arities (decision 32), so precedence alone does not decide it. What differs is that those two are
    *operators whose symbol the kernel multiplies*, defined where the operator lives, whereas
    `combine!`'s kernel form is a convolution applied to a combination — a `Convolution` operation
    taking a `FieldAlgebra` verb's arguments. Placing it here happens to leave the `FieldAlgebra`
    method-parity baseline untouched, the parity count filtering on the defining module. That is an
    observation about a consequence and **never a reason**: a baseline exists to notice movement, so
    avoiding movement is not a design goal, and placement follows the operation's mathematics. A change
    that moves a count refreezes it with the reason (decision 53's protocol) rather than being reshaped
    to avoid it. Validity:
    spectral-only (a kernel is a spectral object; the physical absence is a validity absence), the
    exponential kernel real, even, and positive — Hermitian-safe by construction — and a
    complex-valued ``\hat w`` breaks reality exactly as any consumer-built kernel can under
    `convolve!` (the docstring warns; the trust model is unchanged). Guards: stored-kernel equality
    oracles, the single-mode eigenvalue oracle ``e^{c}\cos x``, fused-equals-sequential for both
    two-operand forms, the in-place filtered accumulate, and the absences in `test/convolution.jl`;
    zero-allocation pins in `test/allocations.jl`; device parity in `test/gpu/suite.jl`; and the
    `convolution` benchmark rows whose baseline is the sequential `combine!` + `convolve!` pair.

34. **The radial diagnostics fuse their staging into the binning kernels.** The audits' item 5: each
    `radial_spectrum` call staged three full spectral planes — a fiber-contracted magnitude array, an
    integer shell-index array, and a Parseval-weighted array — before the decision-25 scatter-add pass
    consumed them (measured 1.6 of the consuming solver `GBGIsotropicTurbulence`'s units at ``256^3``, reproduced here; the cross-power form
    staged a fourth, fiber-shaped, plane), and `radial_correlation` staged a separation-magnitude and
    a shell-index array of its own. All of it is now derived **per element inside the kernels**: the
    spectral kernel computes a mode's ``|k|`` from the three one-dimensional squared-wavenumber arrays
    (the same left-associated sum the lazy ``|k|^2`` broadcast evaluates, so shell assignment is
    bitwise-unchanged), contracts the fiber inline (``\sum_c |\hat f_c|^2``, or
    ``\sum_c \mathrm{Re}(\hat f_c \overline{\hat g_c})`` for the cross form — one kernel, the second
    field `nothing`-dispatched away), and reads the rfft Parseval weight off the plane index; the
    physical kernel derives the minimum-image separation from the grid index and folds the ``1/N``
    correlation normalization into the tiny per-shell average. The shell count is computed
    **analytically from the corner**: the separable ``|k|^2`` (and the min-image ``|r|``) is maximized
    componentwise, so the corner value is the same floating-point sum the kernel forms for that
    element — three ``O(N)`` reductions over one-dimensional arrays (spectrum) or pure host
    arithmetic (correlation), and no bin can overflow by construction. Each kernel allocates only the
    accumulators it uses (the spectrum drops the population counter the correlation needs).

    Measured at the audit size: `radial_spectrum` fell from three staged planes to ``\sim 1.4`` KB —
    the shell accumulator plus launch bookkeeping — and moved from the bounded-diagnostic guard to a
    tight fraction-of-a-field pin in `test/allocations.jl` (scalar, vector, tensor, and cross forms).
    `radial_correlation` keeps exactly its substance: the per-component power field it builds and the
    allocating inverse transform (whose input copy is invariant-11 semantics — a recorded possible
    trim is `to_physical!` with a package-built physical destination, destroying the scratch it no
    longer needs; not taken, since the wedge-class problem was the ``O(N)``-temporary staging, which
    is gone). The decision-25 helpers `_shell_bin_kernel!`/`_bin_by_shell` — the precomputed-index
    histogram this fusion supersedes — are retired (that entry carries the pointer); the identities
    (``\sum_\kappa P = \langle f,f\rangle``, ``C(0) = \langle f,f\rangle``, the ``g = f`` reductions
    bit-identical to the single-field forms) held through the rewrite unchanged.

35. **The audit-response declines, recorded: no general fusion API, two memory items deferred, and
    the counterparty's standing reservation.** The 2026-07 audit exchange with `GBGIsotropicTurbulence`
    ("IT") shipped five items (decisions 32–34). This entry records what was *declined or deferred*,
    because a decline is a decision, not a gap.

    *No general fusion API.* After two rounds of fusion requests the natural follow-up was "expose a
    general fusion mechanism and stop shipping one-offs." Declined, on five grounds. **(a)** The
    general mechanism already exists de facto — Julia's dot-broadcast fuses over fields — and it is
    precisely the problem: it is unguarded, able to express what the method set deliberately withholds
    (a `.*` of two fields in spectral representation is the banned coefficientwise product), and no
    type system can help, since a legitimate kernel *is* a `ScalarFieldSpectral` — kernel application
    and the banned field product are indistinguishable at the type level. (Decision 60 later made a
    kernel its own type, so that particular pair *is* now distinguishable; the ground stands anyway,
    since a `.*` of two fields remains expressible and unguarded.) The broadcast layer is
    therefore internal machinery, not a public contract ([§8](@ref "8. Broadcasting")). **(b)** The
    public method set is the spec (invariant 1); a fusion surface erases it. **(c)** Verification does
    not fuse: each named operation carries alias analysis, the `α`/`β` branch, Nyquist reasoning
    (decision 28 needed *both* wavenumber families to keep a displaced field real), the Hermitian
    reality condition, allocation pins, device parity, and bitwise threading identity — a
    client-composed kernel carries none of them, and the consumer's own architecture ("raise, don't
    reimplement") exists because it does not want to own kernel correctness. **(d)** The triage
    protocol is where correctness happens: across two rounds it caught a wrong signature, a missing
    `β`, an invariant-12 boundary violation, and produced two fusions larger than requested — a
    compiler would have delivered none of that. **(e)** Demand is measurably exhausted: everything
    that survived triage instantiates one structure — sections in spectral representation as a module
    over the ring of Fourier symbols — whose operations the named set now covers (ring multiplication
    is kernel composition, the ring-weighted combination is decision 33, operator ∘ symbol is
    decision 32), and with the five items landed IT's frozen pass ledger sits at its fused ideal.
    Two **validity-closed escalation paths** are recorded for when demand materializes, not built:
    radial real symbols ``\sigma(|k|^2)`` as closure kernels (real and even by construction, hence
    Hermitian-safe and Nyquist-unambiguous; `exponential_convolve!` is the family's first instance,
    and a third functional form — a Gaussian filter, hyperviscosity ``\exp(-\nu (|k|^2)^p \tau)`` —
    is the trigger to generalize); and a stdlib-shaped physical `map!(φ, dest, sections...)` (since
    **built** — decision 48), the
    section-valued sibling of the mapped reductions (every pointwise fiber map is valid in physical
    representation), waiting for a consumer needing a fiber map outside the shipped algebra.

    *Deferred: symmetric second-order tensor storage (IT item 3).* Mathematically legitimate — the
    symmetric tensors ``\mathrm{Sym}^2(V)`` are a genuine subbundle, so a six-component storage type
    clears the [§2](@ref "2. The central principle: the architecture follows established mathematics")
    bar — but it is the largest surface on the table (two field types, a symmetric fiber type,
    six-component transform plans, and a combinatorial decision over the 206-method algebra), and a
    symmetric type wired into only a few operations is exactly the partial surface invariant 1 exists
    to prevent. It is also dominated on its own motivating episode by item 4 below, which composes
    with it. Revisit when a consumer needs the symmetric type as a first-class algebra citizen, not as
    storage for one diagnostic.

    *Deferred: an in-place real-to-complex transform mode (IT item 4).* Requested "when convenient"
    with its consumer archived, so the no-speculative-structure rule settles it — and the design cost
    is real: in-place r2c needs the padded first dimension ``2(N_1/2+1)`` (``N_1`` the first-axis
    points), making the physical data a non-contiguous view, which collides with invariant 3's
    contiguity guarantee (relied on by FFT batching and the threading chunking) and needs a
    rocFFT/cuFFT in-place story. It is, though, the largest-reach memory lever on the table; if
    memory genuinely binds, un-archiving the consumer to make this concrete beats pursuing the
    symmetric storage. The wider byte-level buffer-sharing framing is a scratch-arena design, and the
    package's stance is that the consumer owns buffers.

    *The counterparty's standing reservation, quoted so ground (e) stays honest.* IT pre-registered —
    deliberately not raising it now — that its post-wiring ledger sits *near but not at* the fused
    ideal: the residual is the two-output stage update
    ``(\hat h, \hat u) \leftarrow (\hat N + a \hat h,\ \mathcal E \odot (\hat u + b \hat h))`` — a
    module map with **two outputs** sharing an intermediate, outside the ring structure the shipped
    set closes (not ring multiplication, not the ring-weighted combination, not operator ∘ symbol) —
    of order 13 % of its pass traffic under the mask strategies. If the regenerated ledger confirms it
    once the five items are wired, it returns as a round-3 request with consumer evidence, per the
    demand protocol. It would not fail the §2 bar (a map into a direct sum of section spaces with
    ring-weighted entries is honest structure); the questions it will face are surface shape — the
    package has no two-destination operation — and whether the measured share justifies one.

36. **The pass audit: element traffic measured per operation against a frozen fused ideal.** The
    audit exchange proved a hole in the verification stool: an *unfused* operation passes every
    existing layer — the correctness oracles (right values), the allocation audit (recomputation
    allocates nothing), static analysis — and only a benchmark number drifts, with no ideal beside it
    to notice. The three-broadcast Helmholtz projection read every source component three times per
    mode from decision 24 until decision 32, and no test failed. Since the pointwise operations are
    bandwidth-bound streaming ([`PERFORMANCE.md`](performance.md) §2), their element traffic *is*
    their cost — so `test/pass_audit.jl` now measures it and pins it exactly.

    *Method — measured, not transcribed.* the consuming solver `GBGIsotropicTurbulence`'s compute audit (its decision 34) freezes an
    analytically transcribed per-step pass ledger with a fused-ideal bound (live-ins read once,
    live-outs written once, intermediates free) and a named-holder gap register; that is the honest
    form for a *schedule* its author owns. The package has no schedule (invariant 12), so its unit is
    the **operation** — and, per its own testing philosophy (verify against ground truth, never the
    code's own account), it *measures* rather than transcribes: a test-local `CountingArray`
    (`getindex`/`setindex!` under atomic counters) slides beneath the field types through the generic
    storage of invariant 6, flows through the field broadcast, `_assign!`, and the
    KernelAbstractions CPU kernels alike, and every audited call asserts each participating array's
    **exact absolute element counts** — absolute, not per-array multiples, because legitimate
    patterns break multiples (`sym!` reads an off-diagonal twice and a diagonal once). Beside each
    frozen count sits the fused ideal, and a count above its ideal must carry a **named holder** or
    the suite fails — the gap register transplanted intact. CPU-only, like the allocation audit and
    for the same reason: the code is generic, so the pass structure is backend-independent, while
    launch counts and achieved bandwidth stay benchmark-side. Excluded with reasons — each exclusion cut to its
    true width: the transform **interiors** (FFTW's internal passes are FFTW's; plans reject wrapped
    storage — but an operation *containing* a transform still audits its countable stages, and
    `radial_correlation`'s input read and its decision-34 physical binning kernel are audited, the
    wrapper never reaching the FFT because `similar` on it yields plain storage); the anterpolation
    **scatter** (its `Atomix` accumulate needs pointer atomics a wrapper cannot provide — the
    *gather* is audited at its exact per-point stencil arithmetic, ``M (2n+2)^3`` field reads per
    component, and extending the atomics onto the wrapper is the recorded route to the scatter); and
    O(N) configuration arrays and point positions (only field- and point-value-shaped storage is
    wrapped, its own scope line).

    *What the first measurement found.* The decision-32/33/34 kernels sit **at their ideals** — the
    one-pass projection reads 3 and writes 3 (the audit would have failed the old 9), its ``\beta = 0`` forms provably never read the destination, the KA kernel reads a composed `ĝ` once per mode
    where the broadcast family re-reads a scalar kernel once per fiber component, and the fused
    radial binning reads the field once. The standing gaps are all one family — **per-component
    formula granularity**: `gradient!` re-reads its scalar source per output (3×), `curl!` and
    `cross!` read each source component per formula containing it (2×), `symmetric_gradient!` 5×,
    `mul!`'s vector operand 3×, and the broadcast kernels re-read a scalar kernel per fiber
    component — each now frozen with its holder named, so any of them is a known, priced candidate
    for a decision-32-style one-pass rewrite the day a consumer's ledger makes one worth it. (Since
    retired: decisions 38/39 took the whole family to its fused ideals; the one holder standing is
    the exponential ŵ fiber extrusion.) Two
    curiosities the exact counters caught: `LinearAlgebra`'s generic `dot` (and the component
    reduction under `mean`) peeks one element to type its accumulator (+1 read, frozen with its
    holder), while the fused mapped reductions peek nothing.

    *Regeneration.* `PASS_AUDIT_PRINT=1 julia --project=. test/pass_audit.jl` prints every measured
    cell; a raised count is a fusion regression unless a new holder justifies it, and a deliberate
    change freezes its new values in the same commit, citing the decision — IT's regeneration
    protocol, verbatim.

37. **The CPU path's performance target is one cluster node, not small problems — and that reopens the
    GPU-first tiebreaks.** The performance model ([§9](@ref "9. Performance model and CPU threading"),
    `PERFORMANCE.md` §1) recorded the CPU path as serving "development, testing, and small problems",
    and every platform tiebreak below was licensed by that sentence. It understated the role. The CPU
    path does serve development and small tests — but at those grids performance seldom decides
    anything, so that role sets no tuning target. The role that does is the opposite of small: **a
    single large CPU node, running the resolutions that exceed one GPU's memory.** Since distributed
    and multi-GPU execution are out of scope ([§1](@ref "1. Purpose and scope")), the memory ceiling of
    a run is whatever one node holds, and a CPU node holds far more than a GPU. On NAISS Arrhenius —
    the concrete target — a thin CPU node pairs two 128-core AMD EPYC 9755 processors with 768 GB of
    DDR5 and a fat node carries 3 TB, while the GPU partition's GH200 offers 96 GB of HBM. Taking one
    scalar field in either representation as 8 bytes per grid point in `Float64` (the physical array and
    the rfft half-spectrum agree to within a part in the per-axis size) and a solver's live set at order 25 fields, one
    GH200 stops near ``768^3`` where a thin CPU node reaches about ``1536^3``. The two partitions are
    also distinct machines, so the split is clean: GPU work runs on GPU nodes, CPU work on CPU nodes.

    *What this reopens.* Three recorded results rest on the understated premise, and each was measured
    outside the regime that now matters. The **loop order** ([`PERFORMANCE.md`](performance.md) §4b)
    kept the ``x``-inner stencil traversal for the transfer kernels at a measured ``0.75\times`` CPU
    regression, justified on two grounds — that "the CPU's large caches absorb the strided access", and
    that the GPU is the production platform. At ``1536^3`` a single `Float64` vector field is 87 GB
    against 512 MB of L3 per socket, so the first ground fails outright, and the second no longer holds in this
    band; the regression there is plausibly worse than the measured figure, not better. The **pass
    audit's standing gaps** (decision 36; since retired by decisions 38/39) — `gradient!` re-reading its source ``3\times``,
    `symmetric_gradient!` ``5\times`` — are close to free while a field is cache-resident and become
    pure DRAM traffic once it is not, so they price very differently here. And **NUMA first-touch**,
    which [§9](@ref "9. Performance model and CPU threading") sets aside as a consumer concern, is a
    two-socket node's dominant risk: `similar` reserves address space without touching pages, so the
    placement is decided by whichever code writes first, and a threaded `_assign!` write distributes
    while a serial fill concentrates. Whether that lands well is a measurement nobody has taken.

    *The measurement gap this exposes.* `benchmark/characterize.jl` sweeps ``64^3``–``256^3`` by
    default, and no CPU column above ``256^3`` has ever been recorded — so the entire CPU production
    band is unmeasured, and the tiebreaks above were settled two to four octaves below it. Closing
    that is a prerequisite for revisiting them, and it is only partly possible off-cluster: a
    single-socket workstation can extend the grid sweep but cannot exhibit a NUMA effect at all.

    *The same target fixes a portability bar: `aarch64`.* Arrhenius's GPU nodes are GH200
    superchips, so the CUDA device is hosted by a Grace CPU — an ARM (`aarch64`) host — and
    production will eventually run on both partitions. The package must therefore stay buildable on
    ARM, and **no design decision or dependency may be adopted that is x86-only** — the canonical
    tempting example is swapping the FFT provider to MKL, which has no `aarch64` build; any
    x86-intrinsic tuning falls under the same bar. Nothing in the current dependency tree is known
    to be x86-only (pure Julia plus JLL artifacts published for `aarch64-linux`), but nothing has
    ever been built or tested on ARM either — a coverage gap recorded in
    [`PERFORMANCE.md`](performance.md) §7.

38. **The threaded assignment runs the real engine per slab, and the fused operators leave the
    broadcast route.** Finding (l) (`PERFORMANCE.md` §4) showed the threaded `_assign!` path
    indexing the fused `Broadcasted` element by element — a loop that does not vectorize (~8.6 GB/s
    per thread against `materialize!`'s ~41 on one Zen 5 core), so two and four threads ran *slower*
    than serial on every streaming operation, on both archived CPUs, at every size, unnoticed since
    the feature landed. Two rewrites follow. *The broadcast route:* `_assign_threaded!` now splits
    the destination's slab axis (the last among the largest, so a whole-vector-field write splits a
    grid axis and never the length-3 fiber) and runs the standard fused `materialize!` per slab over
    view-sliced operands — each slab executes the same SIMD kernel as serial, each element is
    written once from the same expression, bitwise identity preserved; a `Val` function barrier
    keeps the slicing inferred (a runtime axis boxed kilobytes per slab), and the allocation audit
    absorbs the remaining size-independent per-task bookkeeping with an explicit field-destination
    floor. Measured: 512³ `Float64` `add!` at two threads fell 187.7 → 73.3 ms — the DRAM ceiling,
    which previously took all eight. *The operator kernels:* `gradient!` (both arities), `curl!`,
    and `symmetric_gradient!` are one-pass kernels in the decision-32 shape — a KernelAbstractions
    kernel on a device, a slab-threaded stride-1 `@simd` loop on the CPU (the KA CPU backend was
    measured at 17.7 GB/s single-thread, hence the loop) — every source coefficient read once per
    mode, the audit rows at their fused ideals, `curl!`'s alias guard retired (its fused pass reads
    a mode before writing it), and each verified **bitwise** against captured oracles of the
    replaced broadcasts. The serial trade is recorded honestly: `symmetric_gradient!`'s nine-output
    loop spills registers and gives back ~5% single-threaded at 512³ while gaining 1.54× at eight
    threads; a two-pass split is the fallback if a serial consumer ever needs it.

39. **One generic fused executor runs the fiberwise algebra; the alias-guard family is retired.**
    The table-stamped algebra ran one broadcast per output component, re-reading shared sources
    once per formula (the audit's holders: `cross!` 2×, `mul!`'s vector operand 3×, `sym!`'s
    off-diagonals 2×, `det!`'s cofactor rows 2×, the scalar-field action and divisor once per
    output component, `convolve!`'s scalar kernel once per fiber component) and wrapped the index
    shuffles in `_guard_noalias!` — a field-sized temporary on every aliased call. Now a pure
    scalar **values function** per operation maps one element's source values (plus fiber
    constants) to the tuple of outputs, and one portable executor (`_fiberwise_pass!`) streams it:
    sources read once into registers, every output written from them, the α/β convention owned
    centrally, alias-safe by construction. The backend split follows decision 30 — one
    KernelAbstractions kernel on a device, a slab-threaded `@simd` loop over the **linear** index
    range on the CPU — and linear indexing is what makes the executor base-agnostic: contiguous
    component views index identically for a 3-D grid and a 1-D point set, so fields and
    point-values share it, and the values functions are stamped from the same per-component
    formula builders the broadcasts used (a `:scalar` accessor kind plus `_undot`), keeping every
    formula written once. Routed through it: `cross!`, the `mul!` family, `transpose!`, `sym!`,
    `skew!`, `dev!`, `det!`, the scalar-field action/division, and the kernel-composed
    `convolve!`/`combine!` fiber paths (α folded into the values so the broadcast's own association
    is preserved); `dot!`/`tr!`/the norms stay broadcasts — their traffic was already ideal. The
    exponential family's fiber extrusion stays a named holder: its per-mode coefficient is the
    lazy cartesian ``|k|^2``, which the linear executor cannot see — the priced fix is the
    finding-(k) mode-loop hoist. `dev!` stopped materializing its trace (now a per-element
    register) and left the documented-allocators list. Every routed operation verified **bitwise**
    against captured oracles (54 cases: both element types, physical and spectral, field and
    fiber-constant patterns, aliased shuffles through the former guard path, α/β accumulates, the
    point-value mirrors), and both parity baselines (206 + 122) are byte-identical — the public
    surface never moved.

40. **The reductions thread on a fixed tree — bitwise thread-count-invariant — and
    `helmholtz_projection!` joins the gated loops.** The last §9 deferral closes. Every CPU
    reduction — `inner` (physical and the spectral Parseval forms), `l2norm`, `integral`, `mean`,
    `std`/`var`, `maximum`/`minimum`/`extrema`, and the whole mapped-form family — now reduces
    through one **fixed midpoint tree**: a binary recursion whose splits are a function of the
    element count alone, its top ``\lceil \log_2 \texttt{nthreads} \rceil + 1`` levels evaluated as
    spawned tasks (through the same `_use_threads` gate as every other route) and its leaves as the
    existing pairwise-blocked `@simd` loops. Because the tree never depends on the schedule, the
    result is **bitwise-identical at every thread count** — serial equals two threads equals
    sixty-four — which the threading suite asserts both by toggling the override and across a
    subprocess launched at a different `-t`. This is deliberately stronger than the tolerance
    framing the reductions previously carried: that framing remains for **cross-backend**
    comparisons (a GPU reduction tree is the device's own), while same-backend CPU values now carry
    an exact contract. The chunk-indexed, fixed-combine design is also the post-task-migration
    idiom (no `threadid()` state anywhere), and accuracy inherits the pairwise story — the tree
    only deepens it. Two ledger holders retired on the way: the fixed-tree kernels seed their
    accumulator from the first element, so the "+1 typing peek" rows of `inner` and `mean` froze at
    ideal (and the audit immediately caught — and priced away — a first-component double pass in
    the new dims reducer, doing exactly its job). The switch changes reduction values once, in the
    last bits (a different, deeper summation tree), absorbed by the analytic oracles.
    `weighted_inner` stays serial for now: its coefficient is the lazy cartesian ``|k|^2``, the
    finding-(k) class, deferred with the exponential family's hoist. Measured honestly on the
    2-channel desktop the gains are 10–25% at eight threads (serial streaming already sits near the
    read ceiling there); the beneficiary is the decision-37 node, where serial is a twelfth of the
    socket. Finally, `helmholtz_projection!` gains the decision-38-shape gated `::CPU` loop twin —
    bitwise-equal to its KernelAbstractions engine, verified — so the policy-exempt set shrinks to
    the operations whose kernels are structurally atomic/irregular: the grid↔point transfer and the
    radial binning. The exemption is now a principle, not a history. (Decision 42 then accidentally
    severed this loop from dispatch for a day; decision 47 restored it and added the guard that pins
    it live.)

41. **The spectral reductions follow the layout's folded axis** (decided 2026-07-23; a Phase-B
    formula-sweep finding). `_parseval_weight`, the spectral `inner`'s correction planes, and the
    shell-binning kernel all folded **array dimension 1** unconditionally, while `RealFourierLayout`
    admits any `fft_dims` permutation and the transforms and `DirectDFT` were already general — so a
    legal permuted layout silently corrupted the spectral `inner`, `weighted_inner`, and the radial
    family. Generalized: the folded dimension is read from `fft_dims[1]` — the Parseval weight is
    reshaped along it, the correction planes select it, and the shell kernel takes it as a `Val` and
    picks the folded mode index — with the default layout bitwise unchanged. Why the tests never
    caught it: no test ever *constructed* a non-default layout, so the hardcoded dimension always
    coincided with the fold on every tested path. `test/reductions.jl` now runs the Parseval, shell,
    and weighted identities under permuted layouts (`(2, 1, 3)`, `(3, 2, 1)`, a mixed-parity grid),
    and `test/gpu/suite.jl` carries a device-parity case. The follow-up layout sweep (same
    session) extends the lane across every layer whose correctness rests on `fft_dims`:
    `test/fields.jl` (a permuted transform round-trip + both multiplier families against
    `rfftfreq`/`fftfreq` on every axis, odd and even folds), `test/differentialoperators.jl`
    (analytic gradient/Laplacian under a permuted fold), `test/convolution.jl` (the translation
    kernel's circshift oracle with a live Nyquist factor on the folded axis),
    `test/transfer_spectral.jl` (`DirectDFT` at the nodes + `NUFFT` against its oracle),
    `test/hdf5.jl` (`fft_dims` persistence), and the reductions set gains `radial_correlation`.
    The sweep immediately caught a third site: the `NUFFT` constructor allocated its oversampled
    work fields with the layout-correct shapes but wrapped them through the layout-dropping
    `_wrap_field`/`_wrap_field_spectral` helpers, so a permuted reference threw a shape mismatch at
    construction (the embed maps and the deconvolution were already general). The wrappers gained
    layout-taking forms and the constructor threads the reference's layout through both templates;
    the bare-grid spline `anterpolate` keeps the default-layout form, having no reference to
    inherit from.

42. **The Helmholtz projector joins the derivative family whole — exact idempotency and exact
    solenoidality** (decided 2026-07-23; a Phase-B formula-sweep finding). The one-pass kernel
    divided the derivative-wavenumber numerator ``a`` by the **true** ``|k|^2``, so at a
    mixed-Nyquist mode (``a \cdot a < |k|^2``) the projector was neither exactly idempotent nor
    exactly divergence-annihilating — the identities held sub-Nyquist only, and
    `test/adjointness.jl` deliberately scoped its fixtures to dodge it (its own header conceded the
    restriction). The denominator is now ``a \cdot a``, squared in-register from the same loaded
    wavenumber values (**both** the KA kernel and the gated `::CPU` loop drop their three
    squared-wavenumber array arguments — the loop was missed on the first pass; decision 47), making
    ``\mathbb P = \mathrm{id} - (a a^{\top})/(a \cdot a)`` the exact orthogonal projector onto the kernel
    of the discrete divergence: ``\mathbb P^2 = \mathbb P`` and ``\nabla\cdot(\mathbb P u) = 0`` at
    **every** mode, the zero and pure-Nyquist modes passing through as the identity. Sub-Nyquist the
    two families coincide value for value, so resolved-band results are bitwise unchanged and every
    existing analytic and parity test holds as-is. The composite
    ``\mathbb P u = u - \nabla \Delta^{-1}(\nabla\cdot u)`` becomes the resolved-band description
    (``\Delta^{-1}`` keeps the true ``k^2`` per invariant 5); the projector definition is primary.
    Full-spectrum Nyquist-content identities are pinned in `test/differentialoperators.jl`.

43. **The coverage-axes audit — the explicit denominator, its closure lanes, and the one bug it
    found** (2026-07-23; the follow-up the decision-41/42 defects demanded). The three
    layout/Nyquist defects shared one cause: the suite was exhaustive only over the axes it
    named, and no written list of axes existed — so an axis living solely in the type system
    (`fft_dims` with one value ever constructed) was invisible to every sweep. The denominator
    is now written down (`docs/TESTING.md` §4, fourteen axes at the time — decisions 60, 61 and 63 have
    since taken the list to seventeen: representation, tensor order,
    element type on the CPU lane, layout fold, axis parity, grid-size cubicity, domain-length
    anisotropy, origin, degenerate bases, the ``\alpha = 0`` branch, aliasing patterns, Nyquist
    content, backend, thread count), with the rule that a new type parameter or admissible
    input region adds its axis row and its suite lane in the same change. Five sequential audit
    lanes filled the operation × axis matrix and every finding was closed as fixed or
    dismissed-with-reason. The closure testsets (~300 assertions across ten test files) include
    the full operator set against closed forms on a non-cubic anisotropic permuted box in both
    element types with mixed-Nyquist oracles; the kernel-composed arities on full-spectrum
    fixtures; `adjointness.jl`'s new full-spectrum lane (the decision-42-exact identities; the
    dissipation identity alone stays band-limited — invariant 5's design); the
    ``\alpha = 0, \beta \ne 0`` branch of every α/β-capable operation, previously asserted
    nowhere in the package; destination-aliasing in both directions, including the branchy
    field ± constant path and `cross!` with the destination aliasing the second operand; the
    four never-exercised tensor-constant `mul!` methods; the reversed and subtract directions
    of the spectral constant family; every kernel builder and the lazy exponential kernel off
    the default box; the anisotropic `translation_kernel`; the spectral transfer on an odd fold
    with origin, out-of-box points, tensor order two, and a non-default oversampling — with
    independent oracles for both verbs; the point-algebra aliasing block; guard wiring through
    the public entries; the HDF5 corruption paths (plus two new `ArgumentError` guards in the
    extension for a missing `data` dataset or geometry attribute); and the anisotropic radial
    family with single-mode placement oracles. The audit's one genuine code bug, found by the
    degenerate-input probe lane: the CPU fixed-tree reductions seeded their accumulator from
    the first element before checking emptiness — an `@inbounds` out-of-bounds read on an
    M = 0 point set — whose user-visible symptom was `maximum`/`minimum`/`extrema` fabricating
    `0.0` on an empty section instead of erroring, a silent no-data-versus-zero trap for the
    Lagrangian consumers whose point sets legitimately empty. The four tree entries now guard
    emptiness with deliberate per-operation semantics mirroring the stdlib counterpart and the
    device branch: an order statistic throws the Base empty-collection `ArgumentError`, the
    mean family (`mean`, `var`, `std`, `l2norm`, the normalized `inner`) is NaN, and the raw
    sum is zero, so `integral` over no points is exactly zero; the fiber (mapped) path already
    had its guard. Every other probed degenerate — axes of length one and two, the Nyquist
    split there, zero-work kernel launches across all three transfer schemes, out-of-box
    periodic wrap, the ``\alpha = \beta = 0`` NaN-prefill — behaved exactly as the documented
    invariants promise and is now pinned. The audit's meta-result: beyond this one bug, every
    previously unexercised path proved correct once tested — decision 39's bitwise
    alias-safety, `assignment_window`'s true-``k`` Nyquist convention, the NUFFT tensor path,
    the radial shell bound at any aspect ratio (structural: the corner bound is the sum of the
    same per-axis maxima the kernel forms, and rounding is monotone) — and the one docstring
    defect (`radial_spectrum`'s non-cubic caveat naming ``\min(N_i)/2``, wrong once lengths and
    sizes decorrelate) was corrected to the per-axis inscribed-sphere form.

44. **The section allocators become public: `similar_field` and `similar_pointvalues`** (decided
    2026-07-24; a `/check-consistency` panel finding). Both build a section carrying a reference's
    representation, tensor order, base grid and storage backend — the allocation a consumer needs for
    the scratch an in-place loop writes into — yet both were documented as Internal API, under a
    heading stating they are not public. The evidence that this was a gap rather than a boundary is
    the flagship example: `examples/HIST_CPU.jl`, which exists to show how a real consumer writes
    against the package, hand-rolled the equivalent thirteen times in `make_workspace`, spelling out
    `spectral_field_shape`, `zeros`, an element type and a concrete field constructor for each scratch
    field. Two facts settle the direction. A consumer cannot reach the idiom without them, since the
    concrete constructors demand exactly the shape and element-type knowledge the allocator exists to
    encapsulate; and the GPU twin needed a parallel hand-rolled copy differing only in a `dev(...)`
    wrapper, where the allocator carries the backend for free. Both are now exported and documented
    in their own API-page sections, and both examples build their whole workspace through them. The
    allocated storage is **uninitialized** (`similar`, not `zeros`), which the docstrings state and
    the examples handle by zeroing what they allocate. The method-parity baselines (206 field / 122
    point-value methods) are untouched: those lock the algebra generics, and these are separate ones.

45. **`Grid3D` enforces its own uniformity** (decided 2026-07-24; a `/check-consistency` panel
    finding). The type is documented as a uniform grid, so its spacing is not independent data — it
    is `domain_size ./ grid_size` along every axis. But `grid_spacing` is *stored* (the transfer
    kernels read it directly, and recomputing it per launch buys nothing), and Julia's generated
    four-argument constructor is public, so a caller could hand in a spacing bearing no relation to
    the domain and get a silently self-contradictory grid. Nothing in the tree did: the only
    four-argument call site was the two-argument convenience constructor itself, with the HDF5
    reader, the NUFFT oversampled grid and the tests all going through the two-argument form — and
    the reader in fact re-derives the spacing on load, so a persisted inconsistent grid would not
    have survived its own round trip. The failure it invites is the quiet kind: the spline transfer
    kernels turn a position into a cell index with the stored spacing, so a wrong value mislocates
    every interpolated point instead of raising anything. An inner constructor now rejects a spacing
    that contradicts the domain, and a non-positive grid size with it. The comparison is a relative
    floating-point tolerance rather than equality, so a spacing reached by an equivalent but
    different arithmetic route is still accepted; that case is pinned in `test/fields.jl`, along with
    both rejections and the `Float32` tolerance.

46. **HDF5 persistence extends to the point layer — `write_points` / `read_points`** (decided
    2026-07-24). Decision 29 gave fields a serializer and stopped there, which left a plain asymmetry:
    a solver could checkpoint the velocity field it was integrating but not the point set it was
    advecting through that field, so a restart could not reconstruct the state it had. Since the point
    layer exists for consumer-side Lagrangian methods ([§10](@ref "10. Interpolation and anterpolation (the grid↔point transfer layer)")), the half that cannot be persisted is the
    half a restart most needs. The pair mirrors the field pair exactly, in the same weak-dependency
    extension, with the same bare generics and docstrings in the core so `?write_points` works without
    `HDF5` loaded.

    *Why decision 29's reasoning carries over unchanged.* Serializing a section is I/O, not an operation
    on sections, so the rule that design changes be justified by established mathematics ([§2](@ref "2. The central principle: the architecture follows established mathematics")) —
    which governs the *operation set* — does not bar it, exactly as for fields. Invariant 12 is
    untouched as well: a `PointSet` is a set of positions, not a particle with a history, and the
    package still attaches no notion of time. The consumer owns the file, bundles a snapshot, and writes
    its own `time` / `iteration` attributes.

    *The group is simpler than a field's, because a point object carries less.* A field group must
    describe its `Grid3D` geometry, its Fourier layout and its representation; a point object has none
    of those. So the group holds the array as the dataset `data` plus four attributes — a `type` tag, a
    schema `version`, the element type, and the point count — with a fifth, `tensor_order`, on a
    point-value section but *not* on a `PointSet`, which is a base and has no fiber. The tensor order is
    recovered on read from the array's dimensionality, as a field's is.

    *Positions and values are separate groups, deliberately.* They are separate objects — the base, and
    sections over it — and one stored set of positions is often shared by several value sets, so
    embedding the coordinates in every value group would duplicate the largest array in the file. A
    consumer that wants them bundled writes both under one parent group, which costs nothing and keeps
    the choice with the consumer.

    *Verification.* `test/hdf5.jl` covers both element types across all four point types (including a
    third-order `TensorPointValues`, whose order must survive as the array's dimensionality), the
    `parent[name] = points` sugar, the self-description attributes — asserting that a `PointSet` group
    carries no `tensor_order` and no grid geometry — that the two families coexist in one file with
    neither reader accepting the other's groups, and the five corrupted-group error paths. The testset
    grew from 143 to 207 assertions.

47. **The gated `helmholtz_projection!` CPU loop, dead since decision 42, is restored — and the
    canary lane caught it** (2026-07-24). Decision 42 rewrote the projector's denominator to the
    derivative-family ``a \cdot a``, computed in-register, and dropped the three squared-wavenumber
    array arguments. It updated the KA kernel, the generic launch method, and the dispatcher — but
    left the gated `::CPU` loop (decision 40) with its old six-array signature. With the dispatcher
    now passing three wavenumber arrays where the loop demanded six, the loop's arity no longer
    matched, so it silently stopped being a dispatch candidate and every CPU call fell through to the
    generic `KernelAbstractions`-on-`CPU()` launch — the ~17 GB/s single-thread path decision 40
    existed to escape. The gated loop had become dead code, and its stale body still read the
    *true*-``|k|^2`` array, so had the arity ever been fixed without the body it would have computed
    the wrong Nyquist denominator.

    *No numerical harm occurred*, because CPU and GPU both ran the one correct KA kernel: parity and
    the full-spectrum Nyquist tests passed throughout. Three things did break. Decision 40's stated
    reach — cutoff and `with_threading` governing helmholtz — was false for a day. The
    `with_threading` bitwise assertion added for a 2026-07-24 consistency finding was **vacuous**: it
    toggled an override the live path ignores, comparing a path against itself. And the operation ran
    slower, which is what surfaced it — the canary lane (`benchmark/regress.jl`), on its first live
    exercise, flagged the `t1` helmholtz canary at 1.27× its frozen baseline, the exact
    achieved-time regression the allocation and pass audits cannot see.

    The fix drops the three squared arguments from the loop and squares ``a`` in-register, mirroring
    the kernel; the loop is verified **bitwise-equal** to the KA kernel on a Nyquist-bearing field,
    and divergence-annihilating at every mode. The canary returned to baseline **without a refreeze**
    — proof the baseline was right and the code had drifted, not the reverse. The gap that let a
    dispatch fall through unseen is closed by a **dispatch-target guard** in `test/threading.jl`: a
    CPU helmholtz call must resolve to the `KernelAbstractions.CPU` specialization, not the
    untyped-backend fallback. The lesson generalizes — an operation with a device kernel *and* a
    gated CPU twin has **two** bodies to keep in sync, and only the guard makes "they diverged"
    visible at test time rather than in a benchmark weeks later.

48. **`map!` / `map` — the arbitrary-fiber-map escape hatch, physical-only by construction**
    (2026-07-28). The section-valued sibling of the mapped reductions (decision 30) and decision-35's
    first `map!` instance: `map!(φ, destination, sources...)` applies an arbitrary fiber map φ to every
    base point and *writes a section*, where `mean(φ, ·)` reduces it. It reuses the `_fiberwise_pass!`
    executor unchanged — that executor already takes a runtime values function and keeps its `targets`
    and `arrays` tuples separate, so an *order-changing* map (`exp ∘ det` : tensor → scalar) works with
    no new machinery — so `map!` inherits the fused pass's parallelism (a device kernel on a GPU, a
    slab-threaded loop on a CPU) and its allocation-free contract, and is embarrassingly parallel
    (disjoint writes, no atomics), bitwise thread-count-invariant on the CPU.

    The only `φ`-specific piece is a small adapter in `FiberSections` (`_MapValues`): it groups the flat
    component scalars a fused pass hands it back into fibers (column-major, so assembly is a bare
    `SMatrix` constructor and the flatten a bare `Tuple`), applies `φ`, and flattens the result — a struct,
    not a closure, so the input count stays type-level, exactly `_FiberGather`'s reasoning for the
    reductions. The public methods live where the vertical algebra lives: `FieldAlgebra` for physical
    fields, `Points` for point-values (both over the shared `_map_pass!` driver), extending
    `Base.map!` / `Base.map` (not piracy — the types are ours). It is **physical-only** for fields: an
    arbitrary `φ` is nonlinear, so by invariant 1 there is no spectral method, and the result is aliased in
    spectral representation (the `FieldAlgebra` module warning). Point-values are representation-free and
    carry no such restriction. The allocating `map` infers the output tensor order from `φ`'s return type
    (`Base.promote_op`); when it cannot, it errors and steers to `map!` with a preallocated destination.

    Why an escape hatch is allowed at all, against invariant 1's "the method set is the spec": `map!` is
    **validity-closed** — physical-only-by-construction is its type signature, so it can only ever produce
    a valid operation, never forge an invalid spectral one. It does **not** subsume the named algebra:
    the linear fiber operations (`tr`, `sym`, `skew`, `dev`, `transpose`) exist in *both* representations
    and so cannot route through a physical-only map, and the named nonlinear ones (`det`, `norm`) already
    share the same executor a level down — `map!` serves the *un-named* maps, and the named operations
    stay named to keep the representation-validity encoding intact.

49. **`var`/`std` are scalar-only, gain a spectral form, and the vector second central moment is the new
    covariance `cov`** (2026-07-28). The fiber-preserving `var`/`std` — a per-component variance /
    standard deviation for a vector or tensor section — were two mistakes wearing one API. First, they
    were physical-only by *scoping*, not validity: ``\operatorname{var}(f) = \langle f, f\rangle -
    \langle f\rangle^2 = N^{-2}\sum_{k \ne 0} \alpha(k) |\hat f_k|^2`` (the fluctuation energy, with
    ``\alpha(k)`` the rfft half-spectrum multiplicity and the ``N^{-2}`` the normalization the inner
    product itself carries), both terms already
    Parseval-available, so they were wrongly grouped with the genuinely physical-only `lpnorm`/`maximum`.
    Second, the per-component value is only the **basis-dependent diagonal** of the covariance tensor
    ``R_{ij} = \langle u'_i u'_j\rangle \in \operatorname{Sym}^2(V)`` — the coordinate-free second *central* moment, the primes marking fluctuations about the mean —
    and ``\operatorname{std} = \sqrt{\operatorname{var}}`` has *no canonical vector form* at all: the
    matrix square root of the covariance is not a standard deviation, the per-component root is
    basis-dependent, and ``\sqrt{\operatorname{tr} R}`` is a scalar RMS — three different objects. And
    `var`-as-covariance could not even be uniform (a vector's covariance has tensor order 2, a tensor's order 4;
    the result would be an order-4 **fiber value**, not a section, so the ``R < 3`` *section* ceiling is
    not what stands in the way — `FiberTensor4` exists as a type. The actual limit is narrower: the
    fiber assembly in `FiberSections` (`_fiber_type`/`_assemble_fiber`) is enumerated through order 2,
    so an order-4 result has nowhere to be built. `cov` is therefore defined on **vector** sections
    alone, which is where its consumer is).

    So `var`/`std` are now **scalar-only** — the one representation where each is unambiguous — physical
    *and* spectral (the Parseval form, equal to the physical value; the spectral one-pass loses precision
    to cancellation when the mean dominates its fluctuations, which the docstring notes). A vector or
    tensor section raises a clear error pointing to `cov`. The new **`cov`** (extending `Statistics.cov`; not
    re-exported at the time, like `mean`/`var`/`std` — all four have been re-exported by the umbrella
    since 2026-08-13, per the naming rule's export policy in §2) returns the symmetric covariance `FiberTensor2` of a
    vector section — its diagonal the per-component variances (the normal stresses, in a turbulence
    reading), its off-diagonal the covariances (the shear stresses) a per-component `var` discarded —
    computed in one fused mapped pass as ``\operatorname{mean}(u \otimes u) - \bar u \otimes \bar u``
    (reusing decision 48's `map!` machinery through the mapped `mean`), Bessel-scaled. It is physical-only
    (the outer product is nonlinear). The 206/122 parity baselines are unchanged — these are `Statistics`
    extensions, outside the M2 + M3 surface.

50. **The separable kernels are stored as their per-axis factors, not as fields** (2026-07-28).
    `translation_kernel` and `assignment_window` build a kernel that **factors over the axes**,
    ``\hat g(k) = \prod_a g_a(k_a)``, and both already computed the three one-dimensional factors
    internally before materializing their product into a full field on the last line. That last line is
    now gone: both return a `SeparableKernel` holding the three factors, and the product is evaluated one
    mode at a time inside the pass that consumes it.

    The saving is a *representation* change with no numerical content — every result is **bitwise
    identical** to the materialized kernel, at every tensor order and on both the overwrite and the
    ``\alpha``/``\beta`` branch, which is what the tests assert against the stored product as oracle. What
    changes is the cost: three ``O(N)`` arrays in place of ``O(N^3)`` coefficients (5 KiB against 16.2 MiB
    at ``128^3``, ~10 KiB against 129 MiB at ``256^3``), and a pass that reads **no field-sized kernel
    stream** — the three ``O(N)`` factors are read per mode, so a kernel application drops from three
    field-sized streams to two.

    Fewer streams did **not** hand back a free speed-up, and finding out why fixed the implementation.
    Applying the kernel is bandwidth-bound, so the saved stream is worth having only if evaluating the
    product costs less than the read it replaces, and *how* the product is indexed decides that. Handing
    the lazy product to the linear-indexed fiberwise executor makes every element convert a linear index
    to a cartesian one — an integer division, which a GPU emulates — and that measured **0.29×** a stored
    kernel at ``256^3``. A hand-written three-dimensional kernel removed the conversion but lost as much
    again to warp fragmentation, because the folded axis is ``N/2 + 1`` — 129 at ``256^3`` — so its rows
    do not align to a warp (**0.55×** on a scalar field, worse than doing nothing). What works is the
    plainest form: **one flat broadcast** over the whole section, the per-axis factors carrying singleton
    axes so they extend along the remaining mode axes and along the fiber. Broadcasting indexes them
    cartesian *and* keeps the launch flat and coalesced. Measured against the stored kernel at ``256^3``
    on an RTX 5070 Ti: **1.37× (scalar) and 1.00× (vector) in `Float32`**, and 0.96× / 0.77× in
    `Float64` — the `Float64` shortfall being the extra complex multiplies against a consumer card's
    1/64-rate FP64, which full-rate production hardware does not pay. The lesson is the general one for
    this package: reach for the broadcast route before a hand-written kernel, and measure the launch
    shape, not only the arithmetic. Decision 28's Nyquist
    treatment survives unchanged and unexamined, because the per-axis factors are produced by exactly the
    code that was already correct.

    The mechanism is that a kernel's contribution to a fused pass is fetched through `_kernel_data`,
    which yields a stored array for a kernel held as a field and an **instantiated `Broadcasted`** for a
    separable one. Both the broadcast route and the linear-indexed fiberwise executor consume that lazy
    product exactly as they consume an array — verified including inside the `KernelAbstractions` device
    kernel — so no operator body changed to accept one; the kernel arguments merely widened to a union of
    the two storage classes. That widening initially reached only within `Convolution` — every operator
    arity outside it stayed hard-typed to a stored kernel, so a `SeparableKernel` threw a `MethodError`
    at `helmholtz_projection!`, `divergence!` and `weighted_inner`. The module-placement panel of
    2026-07-28 caught the overclaim and the gap: the kernel *protocol* (`AbstractSpectralKernel`, the
    `_kernel_data` and `_check_kernel_compatibility` generics, the `SpectralKernel` union) now lives in
    `Fields`, the one module every kernel-applying module can see, and the arities are genuinely widened
    package-wide — pinned by a test that walks every kernel-taking entry point and requires the two
    storage classes to agree bitwise.

    Two operations come with the type. Composition stays inside the family (the factors multiply axis by
    axis) — but composing two *translation* kernels is deliberately **not** the same operator as one
    kernel for the summed displacement, because at an even axis's Nyquist the real factor
    ``\cos(\pi h_a/\Delta x_a)`` obeys ``\cos a\cos b \ne \cos(a+b)``; displacements compose by addition,
    which is the more correct route as well as the cheaper one. And `inv` gives the reciprocal kernel,
    separable because ``1/\prod_a g_a = \prod_a (1/g_a)`` — the deconvolution an assignment
    window exists for, which retires the one place the point-density recipe reached into kernel storage.

    Deliberately **not** done here: a general `SeparableSymbol(σ₁, σ₂, σ₃)` closure. Per-axis factors
    supplied as functions of ``k_a`` would be silently ambiguous about *which* wavenumber family they are
    handed — the true ``|k_a|`` that keeps its Nyquist value, or the derivative ``k_a`` that is zeroed
    there (invariant 5) — which is precisely the trap decision 28 documents. Storing the factors, built by
    the package, keeps that choice where it was already made correctly. The radial fragment
    ``\sigma(|k|^2)`` is a separate closure-shaped escalation and is not this decision.

51. **The radial kernel: a symbol of ``|k|^2``, evaluated per mode** (2026-07-29). The escalation
    decision 35 recorded and the consuming solver `GBGIsotropicTurbulence`'s `lazy-per-mode-symbols.md` requested. `spectral_cutoff` and
    `spectral_band` no longer build a field; they return a `RadialKernel` holding the symbol
    ``\sigma`` itself, and `radial_kernel(σ, multipliers)` builds one for any other symbol
    — a smooth filter envelope, a hyperviscous ``\exp(-\nu(|k|^2)^p\tau)``, an integrating factor.
    The kernel costs a closure and three references against ``O(N^3)`` coefficients, and the builders'
    signatures are unchanged, so no call site moves.

    Why the family is closed with no case analysis: ``|k|^2`` is real and **even** in every component,
    so any real ``\sigma`` of it is real and even too, hence Hermitian-symmetric — the coefficients are
    always some real field's. It also carries the true squared wavenumber at an even axis's Nyquist
    (invariant 5), which is the value a magnitude symbol wants there. This is exactly the argument
    decision 50 found *unavailable* for a separable closure, where per-axis factors are ambiguous
    between the two wavenumber families; the radial case has one family, so the argument that killed
    that closure does not carry over.

    **Storage is a symbol, not a table, because a radial kernel has no cheap middle.** An axis-factored
    kernel wins by evaluating its transcendentals ``3N`` times and multiplying per mode; ``|k|^2`` is a
    function of the *sum* of the squared axis wavenumbers, so a general ``\sigma`` of it does not factor
    and there is no per-axis table to precompute (the exponential does factor, and is why
    `exponential_convolve!` is its own operation rather than a `radial_kernel` call) — only the closure (``\sigma`` evaluated per mode, on a ``|k|^2`` that
    is itself already lazy over three stored ``O(N)`` axis arrays) or a full field. Which wins follows
    the crossover of `PERFORMANCE.md` finding (o) plus the symbol's own cost: a cheap ``\sigma`` (a
    mask is one comparison) or one whose parameters **change per call** — the integrating factor, whose
    substep varies every stage — favours the closure decisively, since a stored kernel must be rebuilt
    and re-read; a fixed expensive ``\sigma`` applied many times can favour materializing, which
    `materialize_kernel` provides.

    Composition follows the families. Two radial symbols multiply into one radial symbol (**refined by
    decision 61**: unconditionally so only when both operands carry canonical multipliers of the same
    concrete type; any other radial pairing keeps both operands); a radial and
    an axis-factored kernel do not collapse, so `convolve` returns a `ProductKernel` holding both and
    multiplying their per-mode values — the cross-family composition that lets a mask and a
    displacement apply in one pass. Only a *compressed* kernel may lead: `convolve(stored, compressed)`
    stays "apply a kernel to this scalar field", since a `ScalarFieldSpectral` is also a field.
    (Superseded by decision 60: a field is no longer a kernel, so the lead-argument rule is gone —
    both orders apply and agree bitwise, and composing two kernels is unambiguous by type.)
    `weighted_inner` accepted a stored or radial kernel as a weight and deliberately **not** a separable
    one — **superseded by decision 62**, which found that restriction to be no constraint at all and
    widened the weight to every class. The reasoning recorded here was already the third attempt at the
    question and still short of the mark: it correctly called the exclusion **scoping, not validity**
    (a real separable ``w`` gives a well-defined ``\langle f, w g\rangle``, so invariant 1 never reached
    it) but still supposed each admitted class would cost its own fused reduction path, which measurement
    disproved — every class already agreed bitwise through the one pass. The two rationales *it* was
    correcting were wrong outright: that separable factors are not real in general, contradicted by
    `assignment_window`'s ``\operatorname{sinc}^2``; and that a magnitude-dependent weight does not factor
    per axis, which argues about the radial class that *was* accepted rather than the separable one that
    was not.

    One implementation trap, found on the device and worth the sentence: a symbol closure must capture
    **values, never a type**. The `spectral_band` builder first captured `T` to write `one(T)`/`zero(T)` in the
    body, which makes the closure hold a `Type{Float64}` — not a bitstype, so a GPU launch rejects it
    outright. Capturing the two values instead fixes it, and the `radial_kernel` docstring states the
    rule.

52. **An adversarial mutation audit of the test suite, and the two live bugs it found** (2026-07-29).
    The suite was audited by *injecting* defects rather than by reading coverage: six defect classes —
    each drawn from a real escape — proposed small, silent, plausible edits, and every one was applied
    in an isolated worktree with the suite actually run, so "uncaught" is a measured fact rather than a
    prediction. The framing was chosen because every defect found in the preceding review had been
    invisible to a coverage read-through: an axis consulted and waved off with wrong reasoning, a
    documented claim no test asserted, a property held by one function and silently absent in its
    neighbour, a test that passed while comparing a path against itself, one direction of a symmetric
    operation.

    **Two live bugs came out of it, both confirmed by direct execution before any fix.** A `NUFFT` plan
    used at a *higher* tensor order than the reference it was built from returned **NaN and
    uninitialized memory** — the spread wrote fewer fibre components than the extract read — where
    `DirectDFT` handled the identical call correctly; the plan's own order was never checked, only the
    field's against the values'. And `extrema` **leaked** the scalar-only restriction that `maximum`
    and `minimum` enforce: those are absent above ``R = 0`` by not being defined there, which suffices
    because `Base` has no fallback that accepts a section — but `extrema` has one, so it iterated and
    returned the per-component pair the restriction exists to refuse. An absence that relies on the
    *absence of a fallback* is not an absence; it has to be stated.

    **The audit's sharpest finding was fixture blindness, not missing tests.** The vector gradient's
    testset is named for the index convention ``(\nabla u)_{ij} = \partial_{x_j} u_i``, but its fixture
    ``u = (\sin x, \sin y, \sin z)`` has a **diagonal** gradient, so transposing the whole operator
    passed silently — the name asserted a convention the fixture could not see. The tensor divergence
    was worse: it had **no analytic oracle at all**, its only value fixture being a tensor of nine
    identical components (hence ``A \equiv A^{\top}``, every index permutation invisible), with every
    other assertion self-referential — threaded against serial, device against host, compressed kernel
    against stored — each comparing one contraction against itself. Both now carry closed-form oracles
    over deliberately asymmetric fixtures, and **both were verified by re-applying the mutation and
    confirming the new tests fail**, which is the check that distinguishes a real test from a vacuous
    one.

    The general lesson is about fixtures rather than counts: a symmetric fixture cannot see an
    asymmetric defect, and a self-referential assertion cannot see a defect shared by both sides. When
    an operation's convention is stated in a name or a docstring, the fixture must be able to falsify
    it.

53. **The parity baseline is derived, not enumerated** (2026-07-29). The mutation audit's structural
    half asked what would fail automatically if a new operation shipped with no tests, and the answer
    was: almost nothing. Of eight enforcement layers only the documentation gate
    (`checkdocs = :exports`) reacts to a new export at all; every other layer is a hand-maintained
    list. The parity baseline is the sharpest case, because it is the one that *claims* to enforce
    invariant 1: it counts 28 enumerated generic names filtered to two modules, so decisions 48, 49
    and 51 each added public surface — `map!`/`map`, `cov`, the kernel builders — and neither the 206
    nor the 122 moved.

    Beside it now sits a **derived** baseline: one frozen count per module, over every function that
    module owns, counted across the methods defined in that module. Any new method anywhere moves a
    number, which must then be refrozen deliberately — the pass-audit protocol applied to the method
    table. Verified by adding an untested generic to `Reductions` and confirming the derived baseline
    fails while both enumerated ones stay silent. The enumerated baseline stays, because it localizes a
    change to the generic that moved; the derived one exists to make sure *something* moves.

    The distinction generalizes past this one file. A guard that enumerates what it checks can only be
    as complete as the last person's memory, and this package's guards are otherwise good enough that
    the gap is invisible: the same audit found the allocation ledger, the traffic ledger, the JET call
    list and the canary suite all hand-enumerated, and the dispatch-pair scan covering three of eight
    modules. Prefer deriving the set to be checked from the code — `methods`, `names`, the export
    list — over writing it down, wherever the derivation is possible.

54. **Four mechanical guards, each proven by mutation** (2026-07-29). Decision 53 answered *what*
    forces a future addition to be tested — almost nothing — and this is the response. Every guard
    replaces a convention with something that fails on its own, and none was believed until a
    deliberate defect was injected and the guard was watched to fail.

    **Derived parity.** The enumerated baseline names 28 generics in two modules, so decisions 48, 49
    and 51 each added public surface invisibly. A derived count per module, over every function that
    module owns, now moves whenever any method does. *Proof:* an untested generic in `Reductions`
    fails it while both enumerated baselines stay green.

    **Ledger completeness.** `allocations.jl` and `pass_audit.jl` were hand-written tables; each now
    derives its requirement from the export list, and an exemption must carry a reason. *Proof:* on
    its first run it found four operations audited nowhere while their own siblings were —
    `subtract!` beside `add!`, `skew!`/`dev!` beside `sym!`, `norm!` beside `det!`.

    **Reachability.** `which(...)` answers "what would run for these types", not "does the public
    entry point get there" — the gap decision 47's dead loop lived in. A subprocess now gives each
    gated CPU twin a throwing override and calls the *public* operation. *Proof:* hoisting the
    generic kernel branch above the family branches makes two twins dead code; the probe fails on
    exactly those two while every `which(...)` assertion stays green.

    **Generated sweeps.** Metadata propagation is checked over four folds for every field-producing
    operation, with order-carrying argument slots varied *independently* — the sampling the rest of
    the suite lacks, since every other fixture builds field, point-values and plan from one ``R`` and
    so runs down the diagonal of a cube. And the analytic oracles are generated over a fixture family
    that is asymmetric by construction. *Proof:* dropping the layout in `materialize_kernel` or in
    `similar_field`'s vector arity fails the first; transposing `gradient`'s packing or contracting
    `divergence`'s wrong index fails the second. All four survived the entire suite beforehand.

    Two lessons generalize past the guards themselves. **A guard needs a guard:** the reachability
    probe first reported a live twin as dead, because the override was less specific than the method
    it meant to replace — so it now asserts each override actually owns a method, separating "stale
    probe" from "dead twin". And **generate where the oracle is free.** Metadata and asymmetry cost
    nothing per case, which is why those two sweeps are generated; an analytic oracle costs one rule
    per *operator*, not per case, which is why that one is generated too. What genuinely resists
    generation is small: a claim with no value oracle at all, and the ambient method table (whether
    `Base` supplies a fallback that swallows an intended absence — the `extrema` leak of decision 52).

55. **Oracle provenance is an enumerated axis** (2026-07-29). §1 of `docs/TESTING.md` has always
    opened with the bar — *verify against independent ground truth, never against the code's own
    other path* — and nothing enforced it. So `weighted_inner` shipped and lived its whole life
    without a single direct value: every assertion compared it to `inner`, to `laplacian`, to
    `gradient`, or to a sharp band applied by `convolve`. Each of those is a real test and each
    catches real defects; together they establish that `weighted_inner` is correct exactly insofar as
    four other operators are.

    The mutation audit of decision 52 could not see this, and the reason is worth recording, because
    it is the same shape as the coverage-axes gap decision 43 closed. That audit asked *would a
    defect be caught?* — and for `weighted_inner` the answer is yes, because a relational chain
    terminating in an anchored reference does catch defects. The question it never asked is *does
    this operation have an oracle that is independent of other package operations?* An axis nobody
    enumerates is invisible to a review, and a review is where this one was supposed to be caught.

    Every public value-returning operation now carries a recorded provenance in
    `test/oracle_registry.jl` — analytic, independent, property, relational, or structural — with the
    file its strongest oracle lives in. Two assertions do the work: an operation with no entry fails
    the suite, and an operation classified `:relational` fails it too. The second is the standing
    bar rather than a snapshot; the set is empty today and the assertion is what keeps it empty.
    *Proof:* a new exported operation in `Reductions`, tested nowhere, fails the registry.

    **The registry's own domain was the next instance, found within the hour.** It derived the surface
    from `names(GBGPeriodicFields)`, and the package at the time deliberately re-exported none of the generics it
    *extends* rather than declares (the `Statistics` and `LinearAlgebra` ones have since been — the
    export policy in §2) — so `map`/`map!` (decision 48), `mean`/`std`/`var`/`cov` (49), the
    order statistics, and the field arithmetic `+ - * /` were all invisible to it, as they had been to
    both ledgers. Scanning module namespaces instead reached those, and still missed `inv` (decision
    50), whose method is defined under the qualified name `Base.inv` and therefore creates no binding
    to scan. The derivation that holds walks the loaded modules and asks each function whether a
    package module owns one of its methods — the one question whose answer cannot depend on how the
    definition was spelled. Domain 58 → 103 → 113.

    Widening it immediately paid: the traffic ledger parsed its row labels by splitting on whitespace,
    so `"map!(det) tensor→scalar"` recorded `Symbol("map!(det)")` and four more rows recorded phantoms
    naming nothing. The entry for `map!` read as unaudited while two rows for it sat in the file. Both ledgers now
    assert that every captured name resolves to a real package function — the decision-54
    *a guard needs a guard* lesson, applied a second time to a second guard.

    This is the fourth instance of one pattern, and the pattern is now the point. Decision 43 found
    a missing coverage axis, decision 48 shipped a bug through an axis waved off as not applicable,
    decision 53 found the guards enumerating what they check, and this one finds a review enumerating
    what it asks. The defect is never the individual gap — it is that the list of things to check was
    written by hand and believed. Derive the list from the code, and make the missing entry fail.

56. **An external static audit, triaged and answered** (2026-07-30). A manual static review of `src/`,
    `ext/`, `test/`, `docs/` and `benchmark/` at commit `2c6ff752` filed 57 findings. It was read as
    evidence rather than as a work list: a sample was verified against the code first, and that sample
    already showed three failure modes — **stale** (its benchmark part predates the same day's
    benchmark commits), **severity-inflated**, and **understated**. The last mattered most, so it is
    worth naming: what the report called a "partial, meaningless contraction" in `inner` was an
    out-of-bounds read under `@inbounds` that returned a plausible number because the memory beyond
    the array happened to be zero.

    Four findings were **rejected** as recorded trade-offs rather than defects: manual-only CI for the
    package tests and for the canary lane (a deliberate cost decision after the free tier was
    exhausted), and the absence of `aarch64` and GH200 measurements (already `PERFORMANCE.md` §7 gap
    7). Those are real limitations; none is news, and re-enabling push CI would reverse an explicit
    decision.

    **The user's rule governed the rest: no silent failures and no silent corruptions.** That decided
    every open question. Where an operation returned a plausible wrong value it was made to throw;
    where it already failed loudly but in the wrong place, the check moved to the entry point; and
    where the honest answer was "this is not supported", the boundary was documented and pinned by a
    test rather than enforced by a constructor.

    **Compatibility became one protocol, not seven checks.** `_context_grid` / `_context_layout` are
    generics that every participant in a spectral operation answers — fields and multiplier sets in
    `Fields`, all three kernel classes in `Convolution`, the `NUFFT` plan in `Interpolation` — so a
    single predicate compares any two of them without either module knowing the other's field names.
    Storage family joined the field domain check, expressed as the array type's name so it costs
    nothing at run time. The audit proposed a context descriptor struct; dispatch does the same work
    without a new type.

    **The tensor-order ceiling is `R < 3` (writing `R` for a section's tensor order), documented rather than enforced** (user-decided). The
    reductions, `map` and the decompositions serve ``R \le 2``; storage, persistence, the vector-space
    operations, `inner`/`l2norm` and the spline transfer serve higher orders, and general `R` was
    deferred to ship the second-order surface a pseudospectral solver needs. Enforcement at the
    constructor was considered and rejected: it would break the R=3 paths that legitimately work, and
    it buys nothing, because above the ceiling every entry point either works or **throws** — verified,
    not assumed. A contract lane pins exactly that property, so the boundary is visible and an
    operation that ever starts returning a plausible wrong value there fails a test.

    **One finding is confirmed and deliberately not fixed.** A fused pass reads element ``n`` and
    writes element ``n``, which makes `sym!(A, A)` safe and makes two *different* views overlapping at
    *different* base indices unsafe — `cross!` on views offset by one along an axis gives the wrong
    answer, serially and threaded. A `mightalias` guard would reject `sym!(A, A)` itself, whose target
    and source component views already have different footprints on one parent, and decision 39 made
    that case guard-free after measurement. Rather than ship a check that might break a measured,
    load-bearing property, the contract is now stated precisely in the docstring and the failing case
    is recorded here.

    **A crash the audit did not find turned up while testing its alias claim.** `eachindex` of a
    non-contiguous view is `CartesianIndices`, not a range, and the fused executor's partitioner had a
    method only for ranges — so an operation on a view-backed destination threw from inside the
    scheduler at eight threads and succeeded at one. Storage is a generic `AbstractArray` by invariant
    6, so that is a legitimate operand, and thread-count dependence is precisely what
    `test/threading.jl` exists to catch. It was invisible because every fixture in that file is backed
    by a plain `Array` — the fixture-blindness of decision 52, in a new place.

    The generalizable lesson is about the **denominator** again. The operation `materialize_kernel` was missing for
    an exported kernel class while every completeness ledger read it as covered, because the ledgers
    count operation NAMES and the generic had methods. The fix that matters is not the method; it is
    that the sweep now takes the **subtype set**, derived from the module namespace, so a new class
    fails until it is given a specimen.

57. **`StoredKernel` — the kernel role, made explicit where it matters** (2026-07-30, user-decided).
    A `ScalarFieldSpectral` serves two roles: a field in spectral representation, and the storage class
    for a kernel held as one coefficient per mode. That doubling is what the `SpectralKernel` union
    exists to express, and for *applying* a kernel it is exactly right — the coefficients are the
    coefficients, whatever the object means.

    It stops being right for operations whose meaning depends on the role. Decision 56 added `inv` on
    a stored kernel so a mixed compressed/stored product could be inverted, and in doing so defined the
    coefficientwise reciprocal of a field in spectral representation — which is a nonlinear operation
    on a field, exactly the class invariant 1 excludes there. The value returned is not wrong; the
    method's existence is, because a user writing `inv(f)` for a field gets an operation the spec says
    the package does not have.

    The fix is a marker rather than a restriction, because the ambiguity has a natural resolution:
    **passing a field as a kernel argument already declares the role.** So `StoredKernel(f)` states it
    where a caller means it, `inv` is defined on the marker instead of on the field type, and
    composition wraps automatically — `convolve(compressed, f)` yields a product whose stored factor is
    a `StoredKernel`, so a mixed product still inverts with nothing asked of the caller. Application is
    untouched: the union still accepts a bare field everywhere a kernel is taken, so nothing that
    worked before needs a wrapper. (**Superseded by decision 60**, which is precisely where that
    stopped being true: a bare `ScalarFieldSpectral` no longer dispatches as a kernel, so code that
    passed one now *does* need `StoredKernel` — the compatibility this entry preserved was given up
    deliberately, for the type to carry the role.)

    Two options were weighed and rejected. Restricting `inv` to the compressed classes was cheapest —
    the only consumer of the stored method is the mixed-product path — but it leaves a kernel that
    exists only as coefficients, read from HDF5 or measured, with no inverse at all. Documenting the
    role and keeping the method was cheaper still, and the reason it loses is worth stating: the risk
    there is not a user harmed but the invariant eroded, and "the public method set is the spec" is
    only true while the method set is kept honest.

    The marker is also the shape the kernel protocol wants long-term. With a stored class that is a
    real type, the `SpectralKernel` union could collapse to the abstract supertype and every
    kernel-taking entry point would take one type. That is a breaking change and is not made here; it
    is now a one-step move rather than a redesign. (**Superseded by decision 60**, which made exactly
    that move: `SpectralKernel` is now an abstract supertype and every entry point names the one type,
    so the union this entry reasons about no longer exists.)

    The subtype sweep of decision 56 earned itself immediately: adding the class failed that testset
    until it was given a specimen, which is precisely the moment to notice a new class needs the
    class-wide methods.

58. **The context-mismatch matrix — a derived denominator for the negative surface** (2026-07-30,
    user-directed). The suite already held ~94 negative assertions before the audit, so the gap was
    never "no negative tests". Every one of them was written by hand, which makes a negative surface
    complete only until someone adds an argument slot — and the audit's source findings were almost
    all SEMANTIC mismatches, structurally indistinguishable from valid input, which is exactly the
    class nobody thinks to write a case for.

    Decision 56 closed those findings but closed them the same way: `contracts.jl` is 72 assertions
    and two loops, a hand-picked table. The instruction here was to generate *all* the combinations
    rather than choose representatives, and the design that achieves it is two tiers, each with a
    denominator read out of the code.

    **Tier 1, the protocol product.** The participant set is `methods(_context_grid)`, and every
    ordered pair is checked against every mismatch axis in both argument orders. Adding a participant
    adds a row and a column; adding one without a builder fails a completeness assertion rather than
    silently sitting out. **Tier 2, the entry-point product.** Every method the package owns is
    scanned for a context-carrying parameter, giving (operation, carrier-kind) pairs — the right unit,
    since α/β variants of one call reach one check. Each pair must be invoked or exempted with a
    reason.

    **The two are not redundant, and the mutations prove which is which.** Neutering the shared
    predicate fails Tier 1. Removing one entry point's check while the predicate stands leaves Tier 1
    entirely green and fails Tier 2. A predicate nobody calls and a caller with no predicate are
    different defects, and one tier sees each.

    **The derivation caught seven combinations the hand-written table had missed**, which is the whole
    argument for deriving it. Five were kernel arities — `convolve!`, `divergence!`,
    `helmholtz_projection!`, `combine!`, `weighted_inner` — invisible because a slot declared as the
    `SpectralKernel` UNION is a subtype of neither of its halves, so a plain `<:` test walks past it.
    Two more were the allocating kernel forms, invisible one level further up: `SpectralKernel{T}` is a
    `UnionAll` wrapping that union, so it is not even `isa Union`. (**Superseded by decision 60**: the
    union became an abstract supertype, so a plain `<:` test now finds those slots — the derived
    denominator this entry builds is unchanged, but the invisibility it works around is gone.) Both misses were in the *detector*,
    found only because the completeness assertion compares what it derived against what was written by
    hand and complains in both directions. A one-directional check would have reported success.

    The axis worth naming is `domain`: two grids of **identical shape** and different extent. Every
    array is the same size, every structural check passes, and only a context comparison can tell them
    apart — which is why the operations that lacked one returned plausible wrong answers for months
    rather than failing.

59. **A section owns its storage, which is what makes invariant 9 true** (2026-07-30, user-decided).
    The exhaustive suite's first lane crossed a shared storage pool over every in-place operation and
    found fourteen that returned a wrong answer, silently, across three execution routes. The cause is
    one sentence: a fused pass reads element ``n`` and writes element ``n``, which is safe when the
    destination IS an input and unsafe when one section's element ``n`` is another's element
    ``n + m``. Two overlapping views at different base offsets are exactly that.

    Three fixes were available and two were wrong. A `mightalias` guard on every pass would work but
    puts a per-call test on paths decision 39 measured as guard-free, and leaves invariant 9 needing a
    caveat forever. A **contiguity** requirement looks right and is not: `reshape(view(flat, 2:end), …)`
    is densely strided, overlaps another dense view at an offset, and still corrupts — verified, not
    reasoned. Contiguity is the wrong property; **ownership** is the right one.

    So the constructors reject storage with a `SubArray` anywhere in its parent chain. Two sections can
    then share memory only by being backed by the same array, which is the case the passes already
    handle, so the class is not guarded against — it is unconstructible. The check is on ownership
    rather than layout, so `Array`, `CuArray`, `ROCArray` and a `reshape` of any of them all pass and
    invariant 6 is untouched. Note that `isa DenseArray` would NOT have served: it is `false` for a
    contiguous host view and `true` for the identical CUDA construction, so it answers differently per
    backend.

    **The cost is one foreclosed pattern**: a consumer keeping solver stages in one buffer and slicing
    `view(stages, :, :, :, :, k)`. Those slices are contiguous and disjoint, hence safe, and they are
    now refused. Accepted deliberately, on the principle that **relaxing a restriction later is safe
    and tightening one is breaking** — if a consumer needs it, permitting views that are full in the
    three base dimensions is a small non-breaking follow-up, and that class provably cannot produce a
    base-index offset.

    Two claims made while investigating this were wrong and are recorded so they are not repeated. "A
    view-backed field cannot be transformed" — false; only the *allocating* `to_spectral` rejects one,
    while `to_spectral!` accepts it, which is why views sat in the worst possible state: working for
    the algebra, working for one transform, failing for the other, and corrupting under overlap. And
    "a `mightalias` guard would reject `sym!(A, A)`" — false; the component views for target ``(i,j)``
    and source ``(j,i)`` select disjoint memory, so `mightalias` is `false` on them. That mistaken
    belief is why the defect was deferred for a day.

    The invariant now says what is true rather than what was hoped: aliasing is safe by construction
    **because** a section owns its storage. The survey in `test/exhaustive/` checks both halves — that no assignment
    changes an answer, and that the refusal has not reopened — and the second is mutation-verified:
    removing one constructor's check makes the lane name every reopened case and turn its exit from
    0 to 2.

60. **A field in spectral representation is not a kernel** (2026-08-03, user-decided). `SpectralKernel`
    was a **union** of `ScalarFieldSpectral` — a scalar field carrying one coefficient per mode — and an
    abstract `AbstractSpectralKernel` covering the compressed classes. Three things were wrong with
    that. The abstract type *read* broader than the union while being strictly narrower, so its name
    misled at every signature. A `StoredKernel` marker had to exist purely so `inv` could tell a kernel
    from a field, since the two hold identical data. And `convolve` became asymmetric in a way
    commutativity forbids: `convolve(field, kernel)` **applied** the kernel while
    `convolve(kernel, field)` **composed**, because argument position was the only thing left carrying
    the role.

    The union is gone. `SpectralKernel{T}` is now the **abstract supertype** of four concrete classes —
    `StoredKernel` (one coefficient per mode), `SeparableKernel` (per-axis factors), `RadialKernel` (the
    real function ``\sigma`` of ``\lvert k\rvert^2``, held as a closure), and `ProductKernel` (two
    factors held unmultiplied). Every signature naming `kernel::SpectralKernel{T}` is unchanged,
    `materialize_kernel` returns a `StoredKernel`, and **both argument orders of `convolve` apply and
    agree bitwise at every tensor order**. Composing two convolution operators *is* convolving their
    kernels, so composition keeps the same verb and is now unambiguous by type rather than by position.

    A field of coefficients is wrapped once, where the kernel is built. Measured at ``64^3``, the
    wrapper costs 144 bytes at construction and **zero per call**, with `_kernel_data` inlining to a
    `getfield` — so the cost objection to requiring the wrapper does not exist. Two package methods
    went (`Fields` 105 → 103, refrozen with the reason), and the materializing
    `squared_wavenumber_field` was **removed**: ``\lvert k\rvert^2`` is a radial function, so
    `radial_kernel(identity, multipliers)` is the same object at a closure's cost rather
    than ``O(N^3)`` coefficients.

    **The rename's one hazard was caught by the pass audit and by no other layer.** A guard reading
    `kernel isa AbstractSpectralKernel` MEANT "compressed"; renaming made it true for the stored class
    too, routing it off the fused pass — vector traffic 3M reads against a frozen ideal of M. Every
    correctness oracle passed throughout, because the answer stayed right and only the traffic changed.
    That is exactly the hole decision 36 built the element-traffic ledger to cover.

61. **A radial kernel's coordinates are part of its type** (2026-08-04, user-directed). The product of
    two radial symbols is a radial symbol — always, mathematically. Yet
    `convolve(::RadialKernel, ::RadialKernel)` returned `RadialKernel` *or* `ProductKernel` depending on
    an `===` test of the two operands' multiplier objects, so inference saw a union and the result type
    turned on object identity, which is invisible at a call site. The exhaustive survey reported it as a
    type-stability finding in every configuration it built.

    The conservatism was not wrong. A composite keeps ONE multiplier set, so collapsing two kernels that
    evaluate their symbols against different wavenumbers would silently apply the second symbol at the
    first's ``\lvert k\rvert^2``. Equal grid and layout do not rule that out, because the six-array
    `FieldSpectralMultipliers` constructor validates the arrays' LENGTHS and not their values — the
    escape hatch a sheared, time-dependent (Rogallo) coordinate set would use, which §12 keeps
    consumer-side. So the type `RadialKernel` did not carry the guarantee its name implies, and the
    runtime check was compensating for that at every composition.

    The fix puts the guarantee in the type. `FieldSpectralMultipliers` gains a final `Canonical` type
    parameter recording whether its arrays were **derived from the grid** (the convenience constructor)
    or **supplied by a caller** (the six-array form). Two canonical sets of the same concrete type, on a
    matching grid and layout, hold identical values by construction — same derivation, same inputs — so
    the collapse is unconditional there and is selected by dispatch. Every other pairing, including a
    custom set on either side and two canonical sets of different array types (different backends), keeps
    both operands. All four cases now infer a concrete type, and the parameter goes **last** so that
    every bare `::FieldSpectralMultipliers` annotation and the one `{T}` accessor are untouched.

    **One behaviour change, and it is the one the mathematics asks for**: two separately-built canonical
    multiplier sets used to give a `ProductKernel` and now collapse to a `RadialKernel`. They hold equal
    values, so the collapsed form is correct; the old answer was merely conservative. The lane in `test/contracts.jl`
    asserted the conservative behaviour and now asserts the collapse, alongside a custom set reaching the
    retained form — the canonical-versus-custom axis, added to `docs/TESTING.md` §4 in the same change.

    The type stability is the smaller half of this. A composition happens once, outside any loop, and a
    two-wide union costs nothing measurable there. What the change buys is that `RadialKernel` now means
    what it says.

62. **Any kernel class may weight a reduction, and a complex weight is refused** (2026-08-05,
    user-directed). `weighted_inner(f, g, w)` — the multiplier-weighted inner product
    ``\langle f, w g\rangle`` of decision 27 — took its weight as `Union{StoredKernel, RadialKernel}`,
    two of the four storage classes a kernel comes in (decision 60). It now takes any `SpectralKernel`.

    **The restriction was never a constraint.** Every class implements the `_kernel_data` protocol as an
    instantiated broadcastable — coefficients for the stored class, a lazy per-axis product for the
    separable one, a lazy symbol evaluation for the radial one, a lazy product of two for the composite —
    and the fused reduction never asks which class it holds. Running its body unchanged against the two
    excluded classes gave results **bitwise identical** to the accepted route, before any code was
    changed. The `Union` was a signature written narrowly and never revisited.

    **Two rationales for it were recorded over time, and both were wrong.** The first said a separable
    kernel's factors are not real in general — contradicted by `assignment_window`, whose
    ``\operatorname{sinc}^2`` factors are real. The second said a magnitude-dependent weight does not
    factor per axis, which is a true statement *about the radial class that was accepted* and says
    nothing about the separable one that was not. Both are now recorded beside the code as dead, because
    the failure mode here is inventing a third: when a restriction has no reason, each attempt to state
    one produces a sentence that is locally plausible and describes something else.

    **A complex weight now throws.** ``\langle f, w g\rangle`` is an inner product only for a real ``w``,
    and the previous code took `real(w)` elementwise — so `translation_kernel`, the one complex builder,
    would have been silently accepted with its phase read as a cosine attenuation. The rejection is made
    where the **type** decides it, through `Base.Broadcast.combine_eltypes` on the kernel's data (plain
    `eltype` of an unmaterialized `Broadcasted` is `Any` and does not infer). The branch is on a
    compile-time-known element type and folds away: measured at ``128^3``, old-versus-new ratios are
    1.001 (radial), 0.997 (separable) and 1.000 (stored) — free, which was the condition set for adding
    it at all.

    **`StoredKernel` is the one exemption, and it is a genuine one.** Its storage is `Complex{T}` by
    construction, a spectral field's being complex, so its type cannot distinguish a real multiplier from
    a complex one — a materialized `spectral_cutoff` and a materialized `translation_kernel` have the
    same type. Separating them needs a full extra pass over the coefficients, which this reduction's
    single-pass contract does not permit, so that class keeps the documented real-part behaviour. The
    rule is therefore *the check is made wherever the type can decide it*, which is a statement about
    what is knowable for free rather than an inconsistency to tidy away later. **Settled by the user
    (2026-08-05): the exemption stands and the ``O(N)`` scan is declined.** Reaching that path takes a
    deliberate act — hand-building a stored kernel's coefficients, or explicitly materializing a complex
    one — and a consumer who does either knows what they are doing; paying a full coefficient scan on
    every call to protect a deliberate act is the wrong trade.

    Covered in `test/reductions.jl` (each class bitwise-equal to its own materialized form over
    ``R = 0, 1, 2`` in the tensor order ``R``; the complex refusal on the separable class, on a composition carrying it, and the
    stored exemption), pinned allocation-free for all three newly admitted classes in
    `test/allocations.jl` — the assertion that would catch a widening which quietly reached for
    `materialize_kernel` — and given device parity in `test/gpu/suite.jl`, where the composite class
    nests two lazy `Broadcasted`s and is the case that would resurface the `instantiate` this reduction
    already needed for AMDGPU's `mapreducedim!`. Both tests were verified by mutation: disabling the
    realness check, and dropping a factor from the separable kernel's data, each fail the suite. The
    `Reductions` module baseline moves 119 → 123 — the widening itself is a signature change rather than
    new methods, and the four are the two internal helpers it needed, at two methods each.

63. **Storage families are crossed by `adapt`, the ecosystem's verb, and precision is not crossed at
    all** (2026-08-10, user-directed). Invariant 14 makes every operation **refuse** a pair of sections
    that disagree in storage family, rather than promoting or transferring one to meet the other. That
    refusal was always half a design: it names what the package will not do implicitly without offering
    the explicit operation that does it. The complement has now shipped, and it is not a new verb.

    **The interface is `Adapt.jl`'s `adapt`.** `Adapt` exists for exactly this — take a struct holding
    arrays, return the same struct holding another array type — and CUDA, AMDGPU, oneAPI, Metal,
    GPUArrays and KernelAbstractions all speak it. The package defines `adapt_structure` for the six
    field types, the three point-value types, `PointSet`, `FieldSpectralMultipliers`, the four spectral
    kernel classes and `FieldTransformPlans`, and re-exports `adapt` so `using GBGPeriodicFields`
    supplies it. Every method rebuilds through the same allocator the rest of the package uses, so the
    grid, the Fourier layout, the origin and the tensor order propagate **by construction** rather than
    by being remembered — the defect that made `map` drop the layout on every permuted fold
    (decision 48).

    **A package-owned verb was considered and declined.** It would have been a pure synonym: with
    precision excluded, `adapt(CuArray, u)` takes exactly one parameter, and a second spelling is a
    second thing to keep consistent. The decisive argument is a dependency one. Because
    `adapt_structure` dispatches on a generic target, CUDA supplies the `CuArray` storage rule and
    AMDGPU the `ROCArray` one, so **the package gains both vendors without depending on either** —
    preserving the rule that vendor stacks stay test-only. A hand-rolled `convert_storage` would need
    that same generic dispatch and would be `adapt` under another name. `Adapt` itself is a
    dependency-free package already reachable through `KernelAbstractions`, and pure Julia, so it is
    safe for the `aarch64` target of decision 37.

    **Precision is deliberately excluded, and the reason is structural as well as prudential.** The
    prudential half is `cu`, which silently demotes `Float64` to `Float32`: a transfer that changes what
    a solver computes is the anti-pattern invariant 14 was written against. The structural half is that
    precision is not the same kind of operation at all — `Grid3D{T}` stores the domain size, spacing and
    origin as ``NTuple{3, T}`` and a field demands its grid share its element type, so changing
    precision must rebuild the grid, where changing storage touches only the array. It remains recorded
    future work.

    **Transform plans are rebuilt, and they need nothing from the caller.** An FFT plan is bound to its
    backend and cannot be moved. It was first thought that adapting one would have to refuse and send
    the user to the constructor — wrong, and the question that exposed it was whether a plan requires
    both representations. It does not: the constructor reads no data, only shape, element type and
    family, and a plan **outlives the arrays it was planned against** (verified on FFTW and cuFFT). A
    `FieldTransformPlans` stores its own grid and layout and carries `T` (its element type) and `R` (its
    tensor order) as type parameters, so
    it can allocate its own witnesses, plan, and release them. The struct now also records the planner
    request it was built with, because a rebuild would otherwise fall back to `ESTIMATE` — which
    finding (h) of `docs/PERFORMANCE.md` records as capable of badly mis-planning a single-precision
    transform. Planner flags are an `FFTW` concept and a device rebuild ignores them (`cuFFT` rejects
    them with an unrelated-looking pointer error) while **retaining** them, so a later move back to the
    host restores the original intent.

    **Adapting to the family one is already in is the identity**, following `Adapt` and `convert`: it
    returns the same object, sharing storage. That is why the gate drives the metadata assertions with a
    custom adaptor mapping a host array to a *distinct* host array — adapting to `Array` would exercise
    nothing. The GPU suite's three hand-written device-twin helpers were deleted in favour of the
    shipped interface, so the suite can no longer pass by testing a private imitation of it.

    **The derived per-module baselines move** (decision 53's protocol, refrozen with the reason in the
    same commit): `Fields` 103 → 115 — four `adapt_structure` methods and the eight internals they need
    (`_storage_prototype`, the two three-method order-dispatch families, and `_is_canonical`) —
    `Convolution` 79 → 83 for one method per kernel class, and `Points` 207 → 209 for the point-value
    and `PointSet` methods.

    **A pre-existing limitation surfaced on the way, unrelated to this change**: `cuFFT` rejects any
    non-strictly-increasing FFT region, so a permuted `RealFourierLayout` (decision 41) cannot be
    planned on CUDA at all — only the default ``(1, 2, 3)`` fold works there. It is recorded in
    `docs/TESTING.md` §4 rather than fixed, since it is a vendor constraint and the permuted folds are a
    CPU-side generality.

64. **The preserving scratch arity of `to_physical!`** (2026-08-13, requested by the consuming solver
    `GBGIsotropicTurbulence` ("IT") in its third request round). The
    inverse real transform may consume its input as scratch (the transform input contract above:
    `FFTW` destroys it, some device backends happen not to), so the package offered two contracts —
    the destructive in-place `to_physical!(physical, spectral, plans)` and the preserving-but-
    allocating `to_physical(spectral, plans)` — and the preserving **allocation-free** member was
    missing. Every consumer whose spectral coefficients are a state it keeps (a spectral solver's
    resolved fields, or any field recovered to physical space more than once) was hand-composing
    `copyto!` plus the destructive form; the requesting solver did exactly that in two wrappers and a
    phase-shift chain that recovers twice from one source.

    **The new member is a fourth-argument arity of the existing generic, not a new verb:**
    `to_physical!(physical, spectral, plans, spectral_scratch)` copies the coefficients into the
    caller-supplied scratch, transforms from there, and returns with `spectral` bitwise-unchanged and
    nothing allocated; the scratch's coefficients are undefined on return, exactly as the
    three-argument form leaves its source — stated that way deliberately, because the destruction
    itself is backend-divergent and the *contract* must not be. The arity form follows the house
    convention for "same operation, more contract" (the kernel-composed operator arities of
    decision 32, the α/β accumulation forms): the operation is still the transform, and the trailing
    argument buys the preservation contract, checked by dispatch — the scratch must be a spectral
    field of the same element type and tensor order, which a keyword could only check at runtime.

    **Aliasing is refused, not defined**: `spectral_scratch` sharing storage with `spectral` would
    make the copy a no-op and the transform would then consume the very source the argument exists to
    preserve — a silent contract violation, the worst kind. Same-array is the only sharing the
    ownership rule of decision 59 leaves constructible, so the one cheap `===` check on the storage is
    exhaustive. The copy is a plain `copyto!` over the storage, deliberately: the price of
    preservation is exactly one extra read and write of the coefficients, and nothing else — a
    benchmark row prices it against the destructive form directly.

    **The `to_spectral!` twin is deliberately absent.** Not because the forward transform is safe —
    the input contract records it as backend-divergent too — but because the requesting consumer
    established that every forward transform's source in its loops is consumable by design, so the
    twin would be speculative structure — the §2 rule, not invariant 1: as decision 32 says of the
    identical shape, an invariant-1 absence is a mathematical statement a user can rely on, while this
    one is merely unbuilt. It becomes a one-method addition the day a consumer needs it. Tested by a bitwise preservation check against the
    three-argument form's contract, bitwise equality with the allocating form (whose own oracle is
    the independent DFT sum, terminating the chain independently), the aliasing and context
    refusals, a zero-allocation pin, and GPU parity; the `Fields` baseline moves 115 → 116.

65. **`SpectralKernel` is exported** (2026-08-15, from the round-6 documentation panel). The four
    concrete kernel storage classes — `StoredKernel`, `SeparableKernel`, `RadialKernel` and
    `ProductKernel` — were exported while the supertype they share was not, so a user who wanted to
    write a method or a type annotation against the family had to name
    `GBGPeriodicFields.Fields.SpectralKernel` explicitly. That is the type appearing in the public
    signature of `convolve!`, of the kernel-composed `divergence!` and `helmholtz_projection!`, and of
    `weighted_inner`, so the export makes the type public exactly where its methods already are.

    **The panel's larger finding was declined, and the reason is worth recording.** A hat proposed
    moving the protocol — the abstract type and the two generics `_kernel_data` and
    `_check_kernel_compatibility` — out of `Fields`, on the argument that the package had met the same
    structural problem before and solved it by extracting `FiberSections`. Three placements were
    considered against the alternative of leaving it. `FiberSections` is refused on the architecture's
    own mathematics: its defining property is base-agnosticism, and a spectral kernel is one
    multiplier per Fourier mode of a specific grid under a specific layout — base-bound and
    representation-specific, the horizontal side of the §2 split rather than the vertical one. A
    dedicated module is refused as disproportionate: the protocol is three declarations with no
    dependencies and no bodies, where `FiberSections` was extracted for shared *content* — the fiber
    types, `_assign!`, the whole vertical-algebra codegen. And moving the protocol *down* into
    `Convolution` — which the include order permits, since `Convolution` and `DifferentialOperators`
    have no dependency edge in either direction — is refused on dependency direction: it would make
    `DifferentialOperators` and `Reductions` depend on a heavyweight *peer* to obtain an abstract
    type, where today all three depend only on the foundation. A protocol in the foundation is what
    keeps the consumers independent of one another.

    The placement is also not an accident but the second instance of a recorded convention:
    `FieldSpectralMultipliers` was moved *into* `Fields` from `DifferentialOperators` for the
    identical reason. The shared context object and its compatibility protocol live in `Fields`; the
    module that owns the mathematics owns the concrete types and the builders. No method is added, so
    every parity baseline is unchanged.

66. **The kernel builders drop their `reference` field** (2026-08-15, from the same panel round). The
    five builders took a `reference` field in spectral representation *and* a
    `FieldSpectralMultipliers`, where the multipliers already carry everything the reference supplied.
    Reading the bodies settles it: each used the reference for exactly `field_scalar_type`,
    `field_grid`, `field_layout` and the compatibility check, and a `FieldSpectralMultipliers` stores
    `grid::Grid3D{T}` and `fourier_layout` — so the grid, the layout and the element type are all in
    it. Even the array backend came from the multipliers rather than the reference: the per-axis
    factors are built by broadcasting over `multipliers.squared_wavenumber_*`, so the result already
    lived in the multipliers' storage family.

    **The build-time check was itself the proof.** `_check_multipliers_compatibility` compares the
    scalar type, the grid and layout, and the storage family — which is to say it refused every pair
    in which the reference could have told us anything the multipliers did not. An argument required
    to agree with another argument in every observable respect carries no information.

    **It was a fossil, not a choice.** Before decisions 50 and 51 these builders returned a
    materialized field of coefficients, and allocating one needs a storage prototype of the right
    shape, type and backend — which the reference was. Those decisions replaced the materialization
    with per-axis factors and a closure, and shipped "signatures unchanged" to avoid breaking
    consumers; the argument's only job went with the materialization and nobody noticed, because it
    still type-checked and was still validated. The in-place `translation_kernel!` had already been
    written in the target shape, taking the multipliers alone.

    **The audit covered every other `reference` argument and found no second instance.** The
    `similar_*` allocators are defined by their reference; `_axis_wavenumber_arrays` and
    `_nufft_index_map` take one as a `similar` prototype, which nothing else supplies;
    `_nufft_deconvolution` and the `NUFFT` constructor take the only field they are given. The
    spectral `anterpolate(reference, points, quantities, scheme)` is the one arguable case — a
    `NUFFT` scheme stores its own `reference_grid` and `reference_layout` — but its `DirectDFT`
    sibling is a stateless singleton with no other source of grid, layout, backend or element type,
    and both are methods of one verb under one scheme-agnostic contract, so the argument stays and
    the mismatch is caught: the allocating form delegates to `anterpolate!`, which runs
    `_check_nufft_compatibility`.

    *Consequence for the negative surface.* Each builder now takes exactly one context-carrying
    argument, so there is no second context to disagree with at build time and the five move from
    invocations to exemptions in `test/context_entrypoints.jl`. Nothing is lost — a kernel carrying a
    foreign context is caught where it meets a field, which the nine `(operation, kernel)` rows
    already cover — and `translation_kernel!`, which takes a kernel *and* multipliers, keeps its
    two-carrier check. The gate moves 6541 → 6523: twenty assertions retire with the five pairs (a
    matching case and three foreign ones each) and three replace one, the retired call now being
    asserted to fail loudly rather than resolve. No method count changes; every parity baseline
    holds.
