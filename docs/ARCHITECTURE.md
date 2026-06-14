# GBGPeriodicFields — Architecture and Rationale

This document records the architecture of the package and, more importantly, *why*
it is the way it is. It exists so that future work (human or AI) extends the design
instead of accidentally reverting it. `CLAUDE.md` carries the operational summary;
this file carries the reasoning. The AI-tips block in `src/GBGPeriodicFields.jl`
carries the conceptual model and writing conventions.

This file is **self-contained**: every piece of notation — a mathematical symbol (in LaTeX) or a
`code` identifier — is introduced in plain language at its first use, the meaning stated before or in
the same sentence as the symbol. So it reads top-to-bottom, and each §11 decision-log entry reads on
its own, without opening the source or another document. (Universally standard math — ``\nabla``,
``\Delta``, ``\int``, ``\mathbb R`` — may stand unglossed.) Keep it that way when editing.

## 1. Purpose and scope

The package is the field layer for pseudospectral simulation of incompressible
fluid dynamics and turbulence on three-dimensional rectangular periodic domains. It
provides scalar, vector, and second-order tensor fields with two storage
representations — physical and spectral (the spectral one stored non-redundantly as the
real-to-complex / `rfft` half-spectrum) — plus
FFT transform plans, spectral multipliers, storage-wise broadcasting, fiberwise
algebra (`FieldAlgebra`), and spectral differential operators (`DifferentialOperators`).
Interpolation and its adjoint anterpolation — the grid↔point transfer layer that
serves consumer-side Lagrangian particle tracking — are in place (§10): the point-value
sections, their fiberwise algebra, and the transfer **schemes** — local splines (Lalescu, Teaca &
Carati 2010: the smooth Hermite and ``C^0`` Lagrange hierarchies) and exact spectral-domain transfers
(`DirectDFT`, `NUFFT`), unified under one `AbstractTransferScheme`. The
same code must run
on CPU `Array`s and on GPU arrays (CUDA `CuArray`, AMDGPU `ROCArray`); development
prioritizes GPU correctness and performance first.

The package is a **math backend** — a library of field operations that turbulence and cloud
solvers consume, not a solver itself. Its vocabulary is therefore domain-neutral (base/fiber,
point/value), never *particle* or *tracer* (a consumer's interpretation), and it carries **no
concept of time**: no advection, time integration, or temporal state. Trajectory dynamics
belong to the consumer (§10).

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
of a base ``B`` and a fiber ``V``. The fiber is a tensor power of ``\mathbb R^3``, fixed by the
**tensor order** ``R``: ``V = \mathbb R`` (``R = 0``, scalar), ``\mathbb R^3`` (``R = 1``, vector, `FiberVector`),
``\mathbb R^3 \otimes \mathbb R^3 = \mathbb R^{3\times 3}`` (``R = 2``, second-order tensor, `FiberTensor2`),
and higher (`FiberTensor3/4`). A section
assigns a fiber value to each base point; the fiber-last data layout (§3) is exactly
that section, stored base-indexed.

Three structures of the package are then *parameters of a section*, not separate
worlds:

- **The base** is either the structured grid `Grid3D` — a field is a section sampled
  on the grid — or the unstructured point set `PointSet` — point-values are a section
  sampled at scattered points (§10). Same fibers, different base.
- **Fiberwise algebra is the vertical (within-fiber) structure**: addition, real
  scaling, contraction with a constant fiber, dot/cross/tensor products, transpose,
  sym/skew/dev, and norms all act inside fibers, pointwise in the base, and are
  therefore **base-independent** — the very same operation on the very same fiber
  type, whether the base is a grid or a point set. This is the structural reason one
  set of generated kernels (§6) serves fields and point-values verbatim, and the
  mathematical motivation for treating the **section as the primary abstraction**: a
  shared `AbstractFiberSection{T, R}` supertype spanning both, in the
  `FiberSections` module (§10).
- **Differential operators are the complementary horizontal structure** — gradient,
  divergence, curl, Laplacian are derivatives *along the base*, using the flat
  connection of the periodic box (§4). They are bound to a base with a differentiable
  structure: they act on grid sections (in the spectral representation) and not on
  point-value sections, which carry the vertical algebra but no derivatives.
- **Base reductions are the third operation family** — integrating the base away against a
  **measure** the base carries (`Grid3D` cell volume; `PointSet` counting): `integral`
  (extensive), the normalized `inner`/`l2norm`, and the `mean`/`std`/`var` moments. They map a
  section to a scalar or a fiber and are base-dependent (the measure is the base's), yet — like
  the vertical algebra — are shared by fields and point-values through `AbstractFiberSection`
  (§9, decision 18). The same *measure* concept recurs as the interpolation kernel (below) and a
  convolution multiplier (the `Convolution` module, decision 20): one L²/integration structure in three roles (the
  measure taxonomy, decision 19).
- **Representation is a choice of basis for a grid section's data** (distinct from the
  fiber frame above): physical storage uses the nodal basis, spectral storage the Fourier
  basis, and the rfft is the linear isomorphism between them. A point-value section has no second
  representation — there is no periodic grid to transform over — so the point types
  are representation-free (§10).

(The vertical/horizontal language is the bundle-theoretic one — fiber directions versus the
connection's base directions — applied here by analogy to *operations*: the fiberwise algebra
is order-zero and fiber-preserving, the differential operators are the connection's covariant
derivative, order one. Strictly, *vertical* (``\ker \mathrm{d}\pi``, the kernel of the bundle
projection ``\pi``'s differential — canonical) and *horizontal* (a connection-chosen complement) are
subbundles of the total space's tangent bundle.)

Transfer between sections over *different* bases is the interpolation/anterpolation
pair: pulling a grid section back to points (evaluation, ``f(x) = \langle \delta_x, f\rangle``) and the
adjoint pushforward of point masses onto the grid. The full function–measure duality
is given in §10 and the `Interpolation` module docstring; the interpolation weights are
themselves a unit-mass kernel **measure** (signed for the higher-order schemes), the
base-changing sibling of the convolution multiplier — see the measure taxonomy
(decision 19).

### The construction in commutative diagrams

The same picture as the diagrams the rest of this section leans on. A **field is a section** — a
right inverse of the bundle projection ``\pi``:

```math
B \;\xrightarrow{\,s\,}\; E \;\xrightarrow{\,\pi\,}\; B, \qquad \pi \circ s = \operatorname{id}_B,
```

with ``B`` the base (the structured `Grid3D` or the unstructured `PointSet`), ``E = B \times V`` the
trivial tensor bundle, and ``s`` the field (`AbstractFiberSection`): exactly one fiber value per base
point.

**Representations and operators — the intertwiner square.** ``\mathcal F`` (`to_spectral`, with inverse
`to_physical`) is a linear isomorphism, and every translation-invariant operator ``L`` — `gradient`
``\equiv \nabla``, `divergence` ``\equiv \nabla\cdot``, `curl` ``\equiv \nabla\times``, `laplacian`
``\equiv \Delta`` — is *diagonalized* by it into a pointwise multiplier ``\hat L = m(k)\,\cdot`` (``ik``,
``ik\cdot``, ``ik\times``, ``-|k|^2``):

```math
\begin{CD}
f      @>{\mathcal F}>>   \hat f \\
@V{L}VV                   @VV{\hat L}V \\
Lf     @>>{\mathcal F}>   \widehat{Lf}
\end{CD}
\qquad\qquad \mathcal F\circ L \;=\; \hat L\circ\mathcal F .
```

This commuting square *is* invariant 2 (one object, two representations) and the entire design of
`DifferentialOperators`: ``L`` is never formed in physical space — the multiplier ``\hat L`` is applied
in spectral and conjugated by ``\mathcal F^{\pm1}``. It also draws the line for the validity table just
below: an operation may be offered in a representation **iff** its square commutes.

**Why there is no spectral product — the convolution-theorem square.** The pointwise product is *not*
preserved by ``\mathcal F``:

```math
\begin{CD}
(f,g)            @>{\star}>>   f \star g \\
@V{\mathcal F}VV               @VV{\mathcal F}V \\
(\hat f,\hat g)  @>>{\cdot}>   \hat f \cdot \hat g
\end{CD}
\qquad\qquad \mathcal F(f \star g) \;=\; \hat f \cdot \hat g .
```

The coefficientwise product *downstairs* is **convolution** upstairs — so it is offered under its true
name `convolve` ``\equiv \star`` (`Convolution`, decision 20), never as ``*``. Dually, the pointwise
product ``f \cdot g`` transforms to a convolution ``\hat f \star \hat g`` that has **no** coefficientwise
spectral form — which is precisely why field×field products (and `dot`, `cross`, pointwise norms) are
physical-space only (invariant 1).

**The grid↔point transfer — the adjoint pair.** Interpolation ``W`` (gather, grid→point) and
anterpolation ``W^{\top}`` (scatter, point→grid) are ``L^2``-adjoints, and the same partition-of-unity
stencil that makes them adjoint also reproduces low-degree polynomials exactly:

```math
\langle W f,\, q\rangle_{\text{pts}} \;=\; \langle f,\, W^{\top} q\rangle_{\text{grid}},
\qquad\qquad
W\,\bigl(\operatorname{sample}_{\text{grid}} p\bigr) \;=\; \operatorname{eval}_{\text{pts}} p
\quad (p \in \Pi_m).
```

The left identity is adjointness; the right is reproduction (``\Pi_m`` = polynomials up to the scheme's
order). Together they are conservation — the two facts checked in `test/interpolation_transfer.jl`. With
uniform measures, ``W^{\top}`` is the literal transpose up to the ``N/M`` measure factor — ``N`` the
number of grid points, ``M`` the number of sample points (§10).

**The transfer, intrinsically — a pullback–pushforward.** Write ``\iota : B_{\text{points}} \to \Omega`` for the
map carrying each point to its location ``x_p`` in the torus ``\Omega`` (the grid ``B_{\text{grid}}`` is itself a
sampling of ``\Omega``). Pulling the **trivial** bundle back along ``\iota`` keeps the fiber and changes only the
base, ``B_{\text{points}} \times V = \iota^{*}(\Omega \times V)`` — the transfer is a **base-change, not a fiber
operation** (the measure taxonomy, decision 19):

```math
\begin{CD}
B_{\text{points}} \times V @>{\iota\,\times\,\mathrm{id}_V}>> \Omega \times V \\
@V{\pi}VV @VV{\pi}V \\
B_{\text{points}} @>>{\iota}> \Omega
\end{CD}
```

Interpolation is then the **pullback of the section**, ``W = \iota^{*}`` with ``(Wf)_p = f(x_p)``; anterpolation
the **pushforward of the dual measure**, ``W^{\top} = \iota_{*}`` with ``\iota_{*} q = \sum_p q_p\,\delta_{x_p}``
(the Dirac mass regularized by the stencil; §10). They have **opposite variance** — functions pull back, measures
push forward — and the adjointness identity above *is* their adjunction, ``\langle \iota^{*} f, q\rangle = \langle f, \iota_{*} q\rangle``.
(Strictly ``W = \iota^{*}\circ R``, with ``R`` the reconstruction — spline or band-limited spectral interpolant —
lifting grid samples to a section over ``\Omega``; the reproduction identity above is ``R`` exact on ``\Pi_m``.)

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
  space, ``\mathcal F(f + c) = \mathcal F(f) + c\,N\,\delta_{k,0}`` under the unnormalized-forward convention,
  so only the zero mode changes, scaled by `prod(grid_size)`. This is why
  `_spectral_constant_scale` exists and why constant kernels in spectral
  representation touch a single coefficient (per component).
- **Nonlinear in the field** — products of two fields, division by a scalar field,
  pointwise norms, contractions of two fields (dot, cross, tensor `mul!`, inner
  products): physical space only. The coefficientwise spectral product is *not* the
  Fourier representation of the pointwise product (that would be a convolution),
  so offering it *as a product* would silently compute the wrong physical operation —
  that coefficientwise product *is* convolution, exposed under its true name as `convolve`
  (the `Convolution` module, decision 20), never as `*`.

The consequence is a hard project invariant: **a missing method is a statement,
not an omission**. The 198-method public surface of `FieldAlgebra` is the
machine-checkable encoding of the validity table above. Any refactor must
reproduce the method set exactly; it was verified signature-for-signature against
the original — M2 (98 methods: `add!`/`subtract!`/`multiply!`/`divide!`/`+`/`-`/`*`/`/`)
and then M3 (the dot/cross/`mul!`/transpose/norm/sym/skew/dev contraction and
decomposition families, plus their `*` operators), bringing the total to 198 and
parity-checked at runtime in `test/method_parity.jl`. The point-value algebra
realizes the *vertical* operations on the unstructured base — it mirrors the
**physical** field surface and is locked by its own separate baseline (§10).

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
  (`dot`, `cross`, `mul!`, `transpose`, `norm`, `mean`, `std`, `var`, `maximum`, `minimum`,
  `extrema`); the continuum-mechanics decomposition abbreviations `sym` / `skew` / `dev` are likewise
  conventional.
- **Modules** carry the family **noun** (`Fields`, `DifferentialOperators`, `Reductions`,
  `Interpolation`, `Convolution`); the operations inside follow the rules above — so
  `Convolution` / `convolve` mirrors `Interpolation` / `interpolate`.

The discriminator that places a new operation: a *generic transformation with a natural verb* is a
verb (convolution → `convolve`); a *canonically named operator* is its noun (the Laplacian →
`laplacian`). `gradient`/`laplacian`/`helmholtz_projection` are nouns because they are the names of
those operators, not by a noun preference.

### Documentation policy

The `@eval` code generators (§6) emit methods only, never docstrings. Each operation has one
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
``\equiv \langle\cdot,\cdot\rangle``, `l2norm` ``\equiv \lVert\cdot\rVert``, `integral`
``\equiv \int\,d\mu``, `convolve` ``\equiv \star``, `interpolate`/`anterpolate`
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
algebra comes from StaticArrays/LinearAlgebra and the package never defines it.
**StaticArrays is a direct dependency**, not just the type-only `StaticArraysCore`:
the package indexes fibers (`a[i]`, `A[i, j]`) and uses their algebra inside the
generated kernels, so the core-types package alone leaves those operations undefined.

Data layout is **fiber-last**: `(Nx, Ny, Nz)` for scalars, `(Nx, Ny, Nz, 3)` for
vectors, `(Nx, Ny, Nz, 3, 3)` for tensors; spectral arrays are `Complex{T}` with
the first axis halved per rfft. Rationale: with column-major storage, each
component slice `data[:, :, :, i(, j)]` is one contiguous block. That gives
batched per-component FFTs, coalesced GPU access, pure streaming writes for
elementwise kernels, and trivially chunkable index ranges for the CPU
threading (§9). Component access goes through views
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
backend-divergent — verified that AMD/rocFFT (via AMDGPU.jl) preserves both
directions on tested sizes, while FFTW does not. To keep a uniform, portable
contract, the allocating `to_physical`/`to_spectral` copy their input before
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

**The Nyquist split is deliberate and must not be unified.** On even-length axes:

- Derivative multipliers are **zeroed at the Nyquist frequency**. The Nyquist
  mode of a real signal is a pure cosine; multiplying by ``i k_N`` would produce a
  component the real signal cannot represent, and the symmetric, real-preserving
  choice for its derivative is zero. This is standard pseudospectral practice and
  keeps derivatives of real fields exactly real.
- Squared multipliers keep the **true ``k^2``** at Nyquist. The Laplacian of the
  Nyquist mode is perfectly well defined (``-k_N^2\,\mathrm{mode}``); zeroing it would silently
  remove grid-scale dissipation and corrupt `inverse_laplacian`.

Reference tests pin this down: multipliers vs `fftfreq`/`rfftfreq`, transform
round-trips, and a real-field Nyquist end-to-end test (the derivative zeroed at Nyquist
vs the squared wavenumber kept) — see `docs/TESTING.md`.

## 5. Validation design

`Fields` owns compatibility checking, built from atomic Boolean predicates
(`_same_scalar_type`, `_same_tensor_order`, `_same_grid`, `_same_layout`) composed
into `_check_same_domain`, the representation-dispatched
`_check_field_domain_compatibility` (physical-physical and spectral-spectral
methods — the dispatch barrier that prevents cross-representation mixing), the
public `check_field_compatibility`, and `_check_field_matches_context` for
transform plans.

History: `FieldAlgebra` used to carry near-duplicate checkers
(`_check_scalar_field_compatibility`, `_check_tensor2_vector_field_compatibility`).
These were removed in favor of **direct calls** to
`Fields._check_field_domain_compatibility` — an explicit decision against alias
names: one concept, one name, imported explicitly.

Check placement follows one rule: bodies that go through field broadcasting do
not pre-check, because the broadcast machinery already enforces compatibility
(shape/grid/style promotion); bodies that bypass broadcasting — copy-then-kernel
paths, zero-mode updates — check explicitly. This is why, e.g., physical
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

- **M1 — expression builders** (`Code generation` section of `FieldAlgebra`):
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
  `alias_guard` (cross and the unary index-shuffles — transpose, sym, skew, dev —
  wrap through `_guard_noalias!`; `mul!` is exempt and documents the no-alias
  contract instead, per LinearAlgebra convention). The `sym`/`skew`/`dev` methods
  on bare `FiberTensor2` remain explicit StaticArrays one-liners.
- **M4 — public wrappers/operators (done, folded into M3)**: the allocating
  forms and the `*` operators (tensor·vector, tensor·tensor) are generated
  alongside their `mul!`/`dot`/`cross`/… kernels, completing the 198-method surface.

The same builders are reused verbatim to generate the point-value algebra over the
unstructured base (§10) — the formulas are base-independent (§2). They live in the shared
`FiberSections` module (with the `_assign!` primitive); both `FieldAlgebra` and `Points` source
them from there, so each fiberwise formula — including the norm/sym/skew/dev ones, via
`section_scalar_type` — is written exactly once.

### Verifying codegen changes

With Julia available, verification is runtime introspection: load the package,
compare per-generic `methods(f)` counts against the committed baseline
(`test/method_parity.jl`), and run `detect_ambiguities` (from `Test`) over the
package. The full M2+M3 baseline is 198 public methods (e.g. `*` 28, `mul!` 30,
`dot`/`dot!` 10 each, `add!` 14). (During the no-Julia refactor phase, parity was
checked by simulating table expansion and diffing normalized signatures against the
original file; runtime introspection supersedes that.)

## 7. Aliasing policy

`_aliases_destination` detects backing-array sharing between the destination and
any field operand (constant fibers never alias). `_guard_noalias!(kernel!,
destination, output_order, operands)` runs the kernel into a fresh
`similar_field` and copies back only when aliasing is detected, so the guard is
free in the common case. It exists because index-shuffling operations (cross
products, transpose, sym/skew/dev) read several source components while writing
each destination component — in-place aliasing would consume already-overwritten
data. `mul!` deliberately skips the guard and documents that the destination must
not alias the inputs, matching `LinearAlgebra.mul!` semantics.

## 8. Broadcasting

`Fields` broadcast storage-wise: a field in a broadcast stands for its data array,
and the field broadcast style (owned by `Fields`) materializes into field storage.
Style promotion is one-sided by design — define a single binary rule per style
pair, never symmetric mixed-representation rules. The broadcast layer doubles as
the compatibility enforcement for broadcast-mediated methods (§5).

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
`Fields`. The generic method is `Broadcast.materialize!` — the safe polarity: GPU and unknown
array wrappers keep the standard fused broadcast, so **invariant 6 holds by dispatch**, not
discipline. The `Union{Array, SubArray{…,<:Array}}` specialization threads a single
instantiated `Broadcasted` over contiguous chunks (each chunk a fused `copyto!`; fusion
preserved, one memory pass), **bitwise-identical to serial** because each output index is
written once. A serial cutoff (`_SERIAL_CUTOFF`, default 2^14) keeps small ops — including
the one-element zero-mode views — serial. Policy is **hybrid**: threaded when
`nthreads() > 1` and above the cutoff, with a task-local `ScopedValue` override
(`with_threading(enabled = …)`) for nested-parallel callers.

Two plug points route work through `_assign!`: the field broadcast style's `copyto!` (all
whole-field dotted ops and the field-level algebra), and the kernel assignments — the
codegen body builders emit `_assign!(target, …)` (via `_to_broadcasted`, which rewrites a
dotted formula into a lazy `broadcasted` tree at codegen time), and the hand-written
`FieldAlgebra` / `DifferentialOperators` kernels use the `@_assign!` macro in place of `.=`. No
types, signatures, or method tables change — the 198-method surface and the zero-ambiguity
property are preserved. **Discipline:** a raw elementwise write must go through
`_assign!`/`@_assign!`, never a bare `.=`, or it silently runs single-threaded.

Reductions (global norms, integrals — the L²/measure structure) are now provided in the `Reductions`
module (decision 18), built on `sum`/`dot`/`maximum` rather than the threaded `_assign!`: those reorder
floating-point adds (pairwise on the host, differently on threads/GPU), so they are **tolerance-tested,
not bitwise** like the assignments here. (The only already-threaded part is a *prior* step in a couple of them:
`lpnorm` for ``p \ne 2`` builds the pointwise fiber magnitude ``\lvert f\rvert`` via the vertical
`norm` — an `_assign!`-routed fiberwise op, hence threaded — then reduces *that* with the plain
`sum`/`maximum`. `inner`/`l2norm`/`integral`/`mean` build no such field, so they are a single,
unthreaded `dot`/`sum`.) Threading them further (custom chunk-partial accumulation) is
the remaining work; expected speedup then saturates at socket bandwidth over single-core (typically
2–6×; more on multi-socket nodes, where thread pinning and NUMA first-touch matter — ThreadPinning.jl —
a consumer concern, since the package allocates serially via `similar`).

## 10. Interpolation and anterpolation (the grid↔point transfer layer)

Lagrangian particle tracking by a consumer (§1) requires two transfer operations
between the Eulerian fields and off-grid positions. They are formal adjoints of one
another, and the package gives each a fixed name:

- **Interpolation** — grid → point (the *gather* direction): allocating
  `interpolate(f, xs[, scheme])` / in-place `interpolate!(out, f, xs[, scheme])`, plus the
  callable `f(x)` (and its broadcast `f.(xs)`) as the ergonomic face of `interpolate`.
- **Anterpolation** — point → grid (the *scatter* direction): allocating
  `anterpolate(grid, xs, qs[, scheme])` / in-place `anterpolate!(field, xs, qs[, scheme])`,
  depositing per-point quantities onto a field. Both operations carry the usual
  allocating / in-place (`!`) pair and a five-argument `α`/`β` form (``\beta = 0`` overwrite,
  ``\beta \ne 0`` accumulate — the `mul!` convention, since they are the linear maps ``W`` / ``W^\top``;
  accumulation is the common case for the scatter). `interpolate` / `anterpolate!` are the
  symmetric named pair — only interpolation also gets the callable `f(x)`, because evaluation
  is pointwise while its adjoint is not (see the module docstring). The driving case is
  two-way coupling in the cloud-parcel DNS this package serves — the water-vapour mass and
  latent heat a droplet releases on condensation (or absorbs on evaporation) must be returned
  to the supersaturation and temperature fields.

**One adjoint pair, two scheme families (decision 23).** The `scheme` argument is an
`AbstractTransferScheme` — the choice of *kernel* and *representation* that realizes ``W`` / ``W^\top``
(the §2 commutative-diagram view: a scheme is how the Dirac ``\delta_{x_p}`` is realized). Two
families share the same `interpolate`/`anterpolate` verbs and the same adjointness contract:

- **Physical-domain splines** (`AbstractSplineScheme`) — local kernels on the **physical** nodal
  values (the gather/scatter kernels below); approximate, conserving, the production default.
- **Spectral-domain exact transfer** — acting on a field in **spectral** representation, the literal
  inverse/forward DFT ``f(x_p) = \tfrac1N\sum_k \hat f(k)\,e^{i k\cdot(x_p-o)}`` and its adjoint
  ``(W^\top q)(k) = \sum_p q_p\,e^{-i k\cdot(x_p-o)}`` (here ``N`` is the grid-point count, ``o`` the
  grid origin, and ``x_p`` the ``p``-th sample point). `DirectDFT` is the exact ``O(NM)`` form — the
  *definition* of the spectral-domain pair, hence a transparent baseline, the divergence-free
  reference (it reproduces the band-limited field exactly, matching `to_physical` at the nodes), and
  the oracle for the fast `NUFFT` (the ``O(N\log N + M)`` windowed gridding version, owned natively —
  spread → FFT → deconvolve, reusing the spline kernels with a window, an oversampled
  `FieldTransformPlans`, and an `assignment_window`-style deconvolution; exact to a requested tolerance
  ``ε`` on the resolved sub-Nyquist band). The adjoint relation carries
  the measure factor as for the splines: ``M\,\langle W\hat f, q\rangle_{\mathrm{pts}} = N\,\langle \hat f, W^\top q\rangle``.

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
that matters, independent of application. The binding will carry a docstring listing the
synonyms — *adjoint of interpolation; spreading; deposition; scatter; projection /
PSI-Cell; gridding; two-way-coupling source/feedback* — so a reader from any of those
fields finds it. **"Extrapolation" is deliberately rejected**: extrapolation means
evaluating *outside* the convex hull of the data, whereas a sample point lies *inside* a
grid cell and the operation is a weighted distribution; the loose use of "extrapolation"
for it (seen in a few papers) is a misnomer.

**The two operations are a conserving adjoint pair.** Interpolation and anterpolation
share the **same stencil weights**, which form a partition of unity (``\sum \beta = 1``);
anterpolation is then the exact transpose of interpolation, and the total deposited
quantity is conserved: ``\mathbf 1^\top (W^\top q) = (W \mathbf 1)^\top q = \mathbf 1^\top q``. Using mismatched weights injects a
spurious source/dissipation term (Sundaram & Collins 1996). For the parcel application
this is mandatory — total water and latent heat must be conserved as vapour passes
between droplets and the fields — so the design fixes anterpolation as the transpose of
whatever interpolation kernel is in use. The function–measure duality underlying this
adjointness — evaluation as pairing with a Dirac mass, ``f(x) = \langle \delta_x, f\rangle``, and anterpolation
as the pushforward of point masses, ``\mathcal I^* q = \sum_p q_p\,\delta_{x_p}`` (regularized to ``\sum_p q_p\,\beta(\cdot - x_p)``,
i.e. a regularized point source) — is given in full in the `Interpolation` module docstring.

**Method: the local splines (the physical-domain family).** The package uses the local high-order spline
interpolation of **Lalescu, Teaca & Carati (2010)**, as implemented in the **TurTLE**
code (Lalescu et al. 2022). At its core it is Hermite interpolation
with the node derivatives supplied by finite differences, which makes the interpolant
simultaneously local, high-order, and smooth; in the cubic four-point case it reduces to
the Catmull–Rom spline (Catmull & Rom 1974). Concretely `f(x)` is a tensor-product
weighted sum ``\sum \beta_{i_1} \beta_{i_2} \beta_{i_3}\, f(c+i)`` over a compact ``(2n{+}2)^3`` stencil, with closed-form
polynomial weights ``\beta``. Lalescu's **two hierarchies** share this stencil: the **smooth**
hierarchy (`LalescuSpline(n, m)`) is a two-point Hermite of degree ``2m{+}1`` that matches the
value and the first ``m`` derivatives at the two bracketing nodes (``C^m``, ``0 \le m \le 2n``; ``m = 0``
is linear, ``n = 1, m = 1`` is Catmull–Rom), and the **Lagrange** hierarchy (`LagrangeSpline(n)`)
is the ``C^0`` degree-``2n{+}1`` interpolant of all ``2n{+}2`` nodes. Field derivatives needed for the velocity gradient /
deformation tensor are obtained by differentiating the same local polynomial, not from a
separate field. Three properties make it the right fit:

1. **Single representation, no global precompute.** The weights act directly on the
   real-space nodal values, so interpolation reads only the physical representation — unlike the
   spectral-domain schemes (`DirectDFT`, `NUFFT`; decision 23, below), which read the spectral
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
2. **GPU-friendly** (the GPU-first invariant, §1): per-point interpolation is a gather
   of ``(2n{+}2)^3`` neighbours plus a fused multiply–add — embarrassingly parallel, no FFT, no
   global solve, no communication beyond the periodic stencil wrap. Anterpolation is the
   matching scatter.
3. **Trivial, conservative anterpolation:** the same closed-form ``\beta`` deposit a point's
   source over its stencil with ``\sum \beta = 1`` — exactly the conserving two-way-coupling
   feedback the parcel DNS needs.

The interpolation order is a tunable parameter `(n, m)`, not hard-wired, so accuracy can
be matched to the spectral resolution (standard practice for pseudospectral particle
tracking). The transfer kernels are implemented as portable KernelAbstractions gather/scatter
kernels (the scatter accumulates atomically); the smooth per-axis weights are generated for any
`(n, m)` by a small linear solve — match the value and the order-`1…m` centred-finite-difference
(Fornberg 1988) derivatives at the two bracketing nodes — and **pinned bit-for-bit against TurTLE's
`beta_n{n}_m{m}`** (`n` ↔ `interp_neighbours`, `m` ↔ `smoothness`), with the closed-form Catmull–Rom
(`n = 1, m = 1`) as an independent anchor. The smooth scheme reproduces polynomials to degree
`min(2m+1, 2n)`; the Lagrange scheme to degree `2n+1`.

**Data types — the unstructured base, in the package's own language.** Interpolation needs
to name two new objects: off-grid locations and the field values there. The package names
them in its base/fiber vocabulary, *not* as particles — deliberately, because
GBGPeriodicFields is a **math backend** (§1): "particle"/"tracer" is the consumer's
interpretation (a location with physical attributes and an equation of motion), not a
primitive here. The organizing principle reuses the existing base/fiber split: a field is a
*section* — fibers (scalar, `FiberVector`, `FiberTensor2`) over a *base* — and so far the
base has always been the structured `Grid3D`. Interpolation adds the **unstructured base**
and its section, reusing the *same* fibers; the maps between sections over the two bases are
interpolation ``\mathcal I = W`` and its adjoint anterpolation ``\mathcal I^* = W^\top`` (the same
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
order (a `_check_…` predicate in the `Fields` style). The types live in the `Interpolation`
module, importing `Fields` helpers via an explicit `using ..Fields: …`.

**Implemented status.** The point types, their **full fiberwise algebra**, and the transfer
schemes (interpolation / anterpolation — the local splines plus the spectral-domain `DirectDFT` and
`NUFFT`, decision 23) are all implemented and tested. The algebra mirrors the *physical* field surface — the base-independent vertical
operations of §2 (M2 vector-space and scalar-field products; M3 dot/cross/`mul!`/transpose/
norm/sym/skew/dev), with storage-wise broadcasting — and is generated by **reusing
`FieldAlgebra`'s per-component formula and kernel-body builders verbatim** (§6) over an extended
section interface (`field_data` / `_vector_component_data` / `_tensor2_component_data`, which
`Interpolation` extends for the point types), so no formula is written twice. It is locked by
a separate **118-method point-value parity baseline** (the 198-method field surface is
byte-unchanged), has zero ambiguities, and is covered on CPU (`test/pointvalues_algebra.jl`,
Float64/Float32) and on the GPU (the ROCm suite under `allowscalar(false)`).

**Consolidation status — the module structure the model implies.** The fiber-bundle model (§2)
calls for a base-agnostic foundation and a clean object/operation naming split. Both are now in
place:

- the foundation module **`FiberSections`** holds the base-agnostic supertype
  `AbstractFiberSection{T, R}` (the field and point-value types subtype it), the CPU-threading /
  fused-assignment primitive `_assign!`, and the vertical-algebra **code generators** — the single
  home where each fiberwise formula (including norm/sym/skew/dev, via `section_scalar_type`) is
  written once and reused by both `FieldAlgebra` and `Points`;
- the former `Interpolation` module is **split in two** — **`Points`** holds the unstructured-base
  section *objects* (`PointSet` and the point-value types `ScalarPointValues` / `VectorPointValues` /
  `TensorPointValues`) and their generated algebra (a noun-named peer of
  `Fields`), while **`Interpolation`** holds the transfer maps — the grid↔point schemes (local splines
  plus the spectral-domain `DirectDFT`/`NUFFT`) under one `AbstractTransferScheme`, a peer of
  `DifferentialOperators`.

The field/point asymmetry is deliberate and **mandated by the mathematics**, not
inertia: points have no differential operators (no horizontal structure, §2) and no second
representation, so there is no point peer to `DifferentialOperators` and no representation
machinery in `Points`; and the point algebra is a small *generated* emission that folds into
`Points` rather than earning a separate `FieldAlgebra`-sized module (whose bulk is the 198
hand-curated methods plus the representation-specific irregular corners — the spectral zero-mode
updates, the `multiply!` quartet). What the split *fixes* is the naming: section *objects* live
in noun-named modules (`Fields`, `Points`), operations in operation-named ones (`FieldAlgebra`,
`DifferentialOperators`, `Interpolation`). Each stage reproduces both parity baselines (198 field
+ 118 point) byte-for-byte, with zero ambiguities.

**No concept of time (§1).** The package has, and for now keeps, *no* notion of time — no
advection, no time integration, no temporal interpolation, no per-step state. It answers only
the timeless "field ⇄ values at positions." Trajectory integration `dx/dt = u(x)` and any
time stepping are the consumer's: it holds the positions and advances them, calling this
package once per evaluation, statelessly. This is the same boundary as "no particles" — both
the moving-object abstraction and its dynamics are solver concerns.

**References (this section).**

- C. C. Lalescu, B. Teaca, D. Carati, *Implementation of high order spline interpolations
  for tracking test particles in discretized fields*, J. Comput. Phys. **229**(17) (2010)
  5862–5869.
- C. C. Lalescu, B. Bramas, M. Rampp, M. Wilczek, *An efficient particle tracking algorithm
  for large-scale parallel pseudo-spectral simulations of turbulence* (TurTLE), Comput.
  Phys. Commun. **278** (2022) 108406; arXiv:2107.01104. Code:
  gitlab.mpcdf.mpg.de/TurTLE/turtle.
- M. A. T. van Hinsberg, J. H. M. ten Thije Boonkkamp, F. Toschi, H. J. H. Clercx, *On the
  efficiency and accuracy of interpolation methods for spectral codes*, SIAM J. Sci.
  Comput. **34**(4) (2012) B479–B498.
- B. Fornberg, *Generation of finite difference formulas on arbitrarily spaced grids*, Math.
  Comp. **51**(184) (1988) 699–706.
- S. Sundaram, L. R. Collins, *Numerical considerations in simulating a turbulent suspension
  of finite-volume particles*, J. Comput. Phys. **124**(2) (1996) 337–350.
- C. T. Crowe, M. P. Sharma, D. E. Stock, *The Particle-Source-In-Cell (PSI-CELL) model for
  gas–droplet flows*, J. Fluids Eng. **99**(2) (1977) 325–332.
- A. Brandt, A. A. Lubrecht, *Multilevel matrix multiplication and fast solution of integral
  equations*, J. Comput. Phys. **90**(2) (1990) 348–370 (an early use of "anterpolation"
  for the adjoint of interpolation).
- C. S. Peskin, *The immersed boundary method*, Acta Numerica **11** (2002) 479–517
  (spreading = adjoint of interpolation).
- E. Catmull, R. Rom, *A class of local interpolating splines*, in: Computer Aided Geometric
  Design, Academic Press, 1974, pp. 317–326.

## 11. Decision log

*Chronological and append-only — later entries supersede earlier "remaining"/"deferred"
notes (e.g. the CPU threading and the interpolation layer) rather than contradicting them.*

1. `Fields` refactor: atomic compatibility predicates; shared
   `_check_same_domain`; `_check_field_matches_context` for transforms.
2. `FieldSpectralMultipliers` moved `DifferentialOperators` → `Fields`; explicit
   six-array constructor (validated lengths) plus convenience constructor;
   host-built wavenumbers copied to the backend; **Nyquist split** between
   derivative and squared multipliers (correctness, see §4).
3. `FieldAlgebra` rewritten around code generation with the invariant that the
   public method set is reproduced exactly; M2 + M3 delivered and parity-verified
   at runtime (198 methods, the full surface). Validation rewired to direct
   `_check_field_domain_compatibility` calls — alias wrappers explicitly
   rejected.
4. Docstring policy: one docstring per operation on the bare binding, curated
   signatures + validity prose; generators never emit docstrings.
5. Operators defined in `function op(...) ... end` form (parse-proven house
   style); short form only for unary `+`.
6. GPU-first; CPU threading designed (`_assign!`, §9) and deliberately deferred.
7. Refactor complete: `FieldAlgebra` loads and is parity-verified (M2 + M3, 198
   methods); `DifferentialOperators` rewired to import `FieldSpectralMultipliers`
   and its helpers from `Fields`, with the umbrella re-export corrected (the old
   five-argument constructor removed by design); reference test suite in place
   (`test/`, `Pkg.test()` green) including the method-parity baseline.
   Remaining: deferred CPU threading (§9) and the planned interpolation layer.
8. StaticArrays promoted from `StaticArraysCore` to a direct dependency — the
   package indexes fibers and uses their algebra in the generated kernels, so the
   type-only core package left `field ± fiber`, `scalarfield * fiber`, and the M3
   fiber contractions undefined at runtime (see §3).
9. Transform input-preservation contract: in-place `to_physical!`/`to_spectral!`
   may overwrite their source (FFTW c2r destroys input; backend-divergent), so the
   allocating `to_physical`/`to_spectral` copy the input to keep non-`!` calls
   non-mutating (see §4).
10. GPU testing is opt-in and **dependency-free for the package**: the data layer is
    generic over `AbstractArray`, FFT plans are built through `AbstractFFTs`
    (backend-dispatched on the array type) and allocations inherit their backend via
    `similar`, so a GPU backend is only ever a *test* dependency. It lives in
    per-backend environments under `test/gpu/` (`rocm/` now, `cuda/` later), each
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
    on the zero-mean subspace, its kernel being the constant mode — idempotent Helmholtz
    projection — the discrete energy/entropy structure). Intentional-absence tests are
    symmetric across representations: nonlinear products absent in spectral; the
    differential operators absent in physical (spectral-only — no finite-difference
    operators yet). `Aqua.test_all` was added, which required `[compat]` bounds for every
    dependency. Two deliberate deferrals: a global L²/integration reduction is reserved
    for *separate code* (so adjointness tests use an inline L² inner product), and
    doctests wait until the package stabilizes and tutorials are written. Coverage detail
    lives in `docs/TESTING.md`.
12. CPU threading implemented (§9), realizing the design formerly deferred in items 6/9. A
    `Fields._assign!` primitive threads elementwise/fiberwise assignments on CPU
    (`Base.Threads`, contiguous chunks, bitwise-identical to serial), routed in via the
    field broadcast `copyto!` and the kernel assignments (codegen `_to_broadcasted` plus the
    `@_assign!` macro for hand-written kernels); FFTW threads are matched to Julia's at load.
    Hybrid policy: on when `nthreads() > 1` and above a `2^14` serial cutoff, with a
    task-local `with_threading` ScopedValue override; the GPU path stays on the
    `materialize!` fallback. `[compat] julia` was raised to 1.11 (for ScopedValue).
    Reductions remain deferred (separate FP-ordering design).
13. Interpolation-layer design fixed (§10):
    grid→point **interpolation** as the callable `f(x)` / `f.(xs)` plus the named
    `interpolate` / `interpolate!`; point→grid **anterpolation** as `anterpolate` /
    `anterpolate!` — the symmetric named pair, each with allocating, in-place, and
    α/β-accumulate forms (the `mul!` convention, since they are the linear maps ``W`` / ``W^\top``);
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
14. Point-data types fixed (§10) and the math-backend policy recorded. The unstructured base
    reuses the base/fiber split: `Point{T} = SVector{3,T}` (a position; an **alias** of
    `FiberVector`, not a wrapper); `PointSet` (`M` positions, **SoA** `(M,3)`, grid-free);
    and `PointValues` as **three concrete types** mirroring the field zoo —
    `ScalarPointValues` / `VectorPointValues` / `TensorPointValues{R}` under
    `AbstractPointValues`, SoA, **representation-free**. Naming is domain-neutral by policy:
    the package is a math backend, so no *particle* / *tracer* type and **no concept of time**
    (no advection / integration / temporal state) — those are the consumer's. The types live in
    `Interpolation`, importing `Fields` helpers; they are implemented and tested (only the
    transfer kernels of item 13 remain future work — see item 15 for the algebra).
15. Point-value algebra implemented (§10): `FieldAlgebra`'s code generators are **reused
    verbatim** over an extended point-value section interface, mirroring the full *physical*
    field surface (M2 + M3, storage-wise broadcasting) with no duplicated formula; locked by a
    separate **118-method baseline** (the 198-method field surface byte-unchanged), zero
    ambiguities, tested on CPU (`test/pointvalues_algebra.jl`) and GPU (ROCm). The shared
    `AbstractFiberSection{T, R}` supertype the fiber-bundle model (§2) invites — and the lift of
    the inlined norm/sym/skew/dev formulas into a builder — is the planned next step, not yet
    undertaken.
16. Phase A consolidation **done** (§2, §10). The foundation module **`FiberSections`** holds the
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
17. Transfer kernels implemented (§10): interpolation (gather ``W``, also the callable `f(x)`) and
    anterpolation (scatter ``W^\top``, with the α/β `mul!` convention) as the Lalescu local splines.
    **Both hierarchies** are provided: the smooth `LalescuSpline(n, m)` — a two-point Hermite of
    degree ``2m{+}1`` matching the value and the order-``1, \dots, m`` derivatives (centred Fornberg
    finite differences) at the two bracketing nodes, ``C^m`` with ``0 \le m \le 2n`` (`CatmullRom`, the
    cubic ``n=1, m=1``, is the default; ``m=0`` is linear) — and the ``C^0`` `LagrangeSpline(n)`, the
    degree-``2n{+}1`` interpolant of all ``2n{+}2`` nodes. The smooth weights are **pinned bit-for-bit
    against TurTLE's `beta_n{n}_m{m}`** (`n` ↔ `interp_neighbours`, `m` ↔ `smoothness`; agreement
    ``\le`` 1e-15) — an earlier "interpolate the central ``2(n{-}m){+}2`` nodes" draft was corrected
    after reading the TurTLE source, Lalescu's smooth spline being a *two-point* Hermite, not a
    central-node hybrid. Reproduction is ``\min(2m{+}1, 2n)`` (smooth) / ``2n{+}1`` (Lagrange); the
    closed-form Catmull–Rom and the Lagrange cardinal
    basis are independent anchors, with partition of unity (⇒ conservation). Kernels are portable
    across CPU / CUDA / AMDGPU via **KernelAbstractions** (new dep) with the atomic scatter via
    **Atomix** (new dep); both index the native arrays linearly, so one kernel serves
    scalar/vector/tensor orders. Adjointness ``\langle Wf, q\rangle = \langle f, W^\top q\rangle`` and conservation hold to roundoff;
    tested on CPU (`test/interpolation_transfer.jl`, Float64/Float32, incl. the TurTLE pin) and GPU
    (ROCm). Physical-space only. The kernels loop with the **contiguous (x) axis innermost**
    (stride-1 stencil access) — a measured GPU-first choice (≈1.6× at 256³, ≈3.9× for the 512³
    Lalescu on the RX 6700 XT; ~25% slower on CPU for wide stencils, which invariant 6 accepts).
    The L²/volume-weighted (measure-consistent) adjoint is ``(N/M)\,W^\top`` — both base measures are uniform,
    so it is a scalar rescaling of the counting-transpose anterpolation, not a new operation — and is
    verified via `inner` as ``M\,\mathrm{inner}(Wf, q) = N\,\mathrm{inner}(f, W^\top q)`` (`test/interpolation_transfer.jl`, decision 19).
18. **The L² / measure structure on sections — the third operation family (done).** Advances
    the reduction deferral of items 6/11/§9. The package's operations split into **vertical**
    (fiberwise, pointwise — `dot`, `norm`, `cross`; return sections), **horizontal** (differential —
    `gradient`, …; return sections), and now **base reductions** — integrate the base away against a
    **measure** it carries; return a fiber value or a scalar. Math grounding (§2): a section lives in
    `L²(base, μ)`; the inner product is the metric pairing (cf. **Manifolds.jl** `inner(M,p,X,Y)`),
    the measure is an explicit object (cf. **Gridap.jl** `Measure`, **MeasureTheory.jl**), and the
    moments are the canonical reductions (cf. **Statistics** `mean`/`std`/`var`). All dispatch on
    `AbstractFiberSection`, so fields **and** point-values share one set of formulas (`FiberSections`
    "write it once").

    *The measure is a property of the base.* `Grid3D` → uniform Lebesgue quadrature (cell volume
    ``\prod_i \Delta x_i``); `PointSet` → **counting** measure (unit weight per point) — and this is
    *forced*, not a choice: a `PointSet` is grid-free (§10, carries no domain), so the only well-defined
    measure is counting. Consequences:

    `integral(f)` is the **extensive** sum against the measure, `mean(f)` the **intensive** average
    ``\mathrm{mean}(f) = \tfrac{1}{\text{count}}\sum f`` — per base:

    - `Grid3D` (``N`` cells): ``\mathrm{integral}(f) = \int_\Omega f\,dx = (\lvert\Omega\rvert/N)\sum f``, ``\mathrm{mean}(f) = \tfrac1N\sum f``.
    - `PointSet` (``M`` points): ``\mathrm{integral}(f) = \sum f``, ``\mathrm{mean}(f) = \tfrac1M\sum f``.

    So `mean` is the arithmetic average over base elements in both cases — ``\tfrac1M\sum`` over points
    (a plain sample mean), ``\tfrac1N\sum`` over the grid (which, the grid being uniform, equals the
    domain average ``\langle\cdot\rangle``). Names and conventions:

    - `integral(f)` — the **extensive** ``\int f\,d\mu`` (the one quantity that scales with the base measure).
    - `mean(f)`, `std(f)`, `var(f)` — extend **Statistics** (we own the types ⇒ not piracy);
      **intensive**, **fiber-preserving** (`mean(VectorField) → FiberVector`, base reduced).
    - `inner(f, g)` — the **normalized** L² inner product ``\langle f, g\rangle = \mathrm{mean}(\mathrm{dot}(f, g))`` → **scalar**
      (fiber-contracting). *Normalized* (intensive) by deliberate choice: it matches the `mean`
      convention above and the intensive quantities of homogeneous turbulence (kinetic energy
      ``\tfrac12\,\mathrm{inner}(u,u) = \tfrac12\langle |u|^2\rangle``); for points it is ``\tfrac1M\sum \mathrm{dot}``, consistent with `mean`. Not the
      textbook extensive ``\int f\cdot g\,dx`` — that is `integral(dot(f,g))` if ever needed.
    - ``\mathrm{l2norm}(f) = \sqrt{\mathrm{inner}(f,f)}``, generalized as `lpnorm(f, p)` (``p=2`` default; ``p=\infty`` ⇒ sup of the
      fiber magnitude — the CFL case). Chosen over `norm_L2`; **does not** touch the vertical `norm`.
    - `maximum`/`minimum`/`extrema` — extend **Base** for scalar sections; vector/tensor sup of
      magnitude via `lpnorm(·, Inf)`.
    - **No LinearAlgebra overloading**: `dot`/`norm` stay the vertical pointwise ops (return sections,
      scalar fields); the global `inner`/`l2norm` are package generics returning numbers.

    `inner`/`l2norm` are representation-invariant (Parseval): the physical reductions came first, and the
    **spectral `inner`/`l2norm` are now implemented** — for two fields in spectral representation
    ``\mathrm{inner}(\hat f, \hat g)`` equals the physical inner via the rfft half-spectrum Parseval weighting (each mode
    counts twice except those on the ``k_x=0`` plane and, for even ``N_x``, the Nyquist plane — the planes the
    rfft maps to themselves under conjugation, whose partners are already stored, so they count once), computed
    allocation-free as a `dot` over the array plus two plane corrections (the other reductions —
    `integral`/`mean`/`lpnorm`/`maximum` — remain physical-only, not being Parseval-invariant).
    **Physics stays consumer-side**: energy ``\tfrac12\,\mathrm{inner}(u,u)``, enstrophy
    ``\tfrac12\,\mathrm{inner}(\omega,\omega)``, dissipation ``\nu\,\mathrm{inner}(\omega,\omega)``, rms ``\sqrt{\mathrm{inner}}``, intensities from `std`. The FP-ordering
    concern that deferred reductions (item 11) is real — so they are implemented with a defined summation
    order and a tolerance-based test (not the bitwise one used for the threaded assignments).
19. **The measure taxonomy — one L²/integration structure, three roles for "measure"; the recorded
    foundation for the spectral-multiplier family later realized as `Convolution` (decision 20).** The word *measure* recurs across the package
    (reductions, interpolation, and convolution) not by coincidence but
    because all three are facets of the **same L²/integration structure on sections** (§2). This entry
    fixes the taxonomy so the three never get conflated and so the multiplier family starts from a
    recorded design. The math anchor (Grafakos, *Classical Fourier Analysis*, Thm 2.5.x): on a uniform
    periodic box every **homogeneous (translation-invariant) linear operator is a Fourier multiplier** — a
    coefficientwise ``m(k)`` — and the *bounded* ones are exactly those with symbol ``m(k) \in L^\infty``, where
    ``\lVert T\rVert_{L^2 \to L^2} = \lVert m\rVert_\infty``. So "apply ``m(k)``" is not a convenience — it is the complete representation of
    the translation commutant. The existing operators are all such multipliers: `helmholtz_projection` (§4),
    the consumer's 2/3 dealias mask, and the integrating factor ``\exp(-\nu k^2 \Delta t)`` are the **bounded** ones
    (``m \in L^\infty``); `gradient`/`curl`/`laplacian` are the **unbounded** multipliers (symbols ``ik``, ``-|k|^2 \notin L^\infty``),
    diagonalized identically but outside the norm identity above.

    The roles — each as *what it is; operation(s); the map it performs; status*:

    - **base-quadrature**: `Grid3D` cell volume ``\prod_i \Delta x_i`` / `PointSet` counting; ops
      `integral`, `inner`, `mean`, `std`, `lpnorm`, `radial_spectrum` (the ``|k|``-resolved `inner`);
      section → scalar / fiber / radial profile; **done** (decisions 18, 21).
    - **kernel — multiplier**: translation-invariant convolution, symbol ``m(k) \in L^\infty``;
      `convolve` / `convolve!` plus the builders `spectral_cutoff` / `spectral_band` /
      `squared_wavenumber_field` (the radial coordinate consumers build symbols from); grid → grid
      (a Fourier multiplier); **done** (`Convolution`, decisions 20, 21).
    - **kernel — transfer**: off-grid partition-of-unity convolution (unit mass; signed or positive);
      `interpolate` (``W``) / `anterpolate` (``W^\top``); grid ↔ point (base-change, *not* a
      multiplier); **done** (decisions 13/17).
    - **sample-space (FDF)**: spatially-filtered fine-grained Dirac density, over the
      velocity/composition sample space; no package operation; **out** (physics; invariant 12).

    *Interpolation is the base-changing sibling of the multiplier, not a multiplier.* The gather weights
    `{W(x_p, x_g)}_g` are a discrete grid measure of **total mass 1** (partition of unity), so
    ``u(x_p) = \int u\,d\mu_{x_p}`` is integration of the field against a unit-mass kernel measure centered at
    the point — the same *species* as a homogeneous filter. Two differences make it its own operation
    (§10, in `Interpolation`, not under the multiplier family): (i) its codomain is the **unstructured
    point base**, which has no wavenumbers, so it is a **base-change** (grid↔point), *not* a Fourier
    multiplier (it degenerates to one only when points coincide with nodes); (ii) the default
    `CatmullRom`/`Lagrange` kernels have **negative side-lobes** — a *signed* unit-mass measure (higher
    reproduction order, but overshoot), while only the linear `m=0` / positive-B-spline end is a genuine
    **probability measure** (monotone). Reproduction order = number of matched **moments** of the kernel
    measure (0th moment `=1` = partition of unity = constants reproduced). This signed/positive split is
    the *same* dichotomy the LES research surfaces below — evidence the kernel measure is one concept.

    *The transfer adjoint is a row-1 (base-measure) statement, and that is why reductions came first.*
    Anterpolation ``W^\top`` is the adjoint of ``W``; "adjoint w.r.t. which pairing?" is answered by the base
    measures. As shipped (decision 17) the adjointness ``\langle Wf, q\rangle = \langle f, W^\top q\rangle`` and conservation
    ``\sum_g (W^\top q)_g = \sum_p q_p`` hold in the **counting/transpose** pairing (the extensive facet of row 1;
    conservation = partition of unity). The **measure-weighted L² adjoint** — ``W``, ``W^\top`` adjoint with the
    grid carrying ``\Delta x^3`` and points counting — is the **bridge from row 1 to the transfer kernel**, and is
    now **done**: both measures being uniform, it is ``(N/M)\,W^\top`` (a scalar rescaling, no new operation),
    verified via `inner` as ``M\,\mathrm{inner}(Wf, q) = N\,\mathrm{inner}(f, W^\top q)`` (`test/interpolation_transfer.jl`). That the
    reductions had to precede it is recorded here.

    *The multiplier family (designed here; realized as `Convolution`, decision 20) carries three research-grounded guardrails.*
    The deep-research findings on LES filtering do **not** change the design — they justify it and bound
    it:
    - **The symbol is data, never parameters** — this is how the family stays inside invariant 12 (no
      time, no physics). The applicator multiplies a field-in-spectral by a precomputed ``k``-array; ``\nu``,
      ``\Delta t``, filter width, and positivity all live in how the *consumer* builds that array from the
      `FieldSpectralMultipliers` wavenumbers (§4). The viscous factor ``\exp(-\nu k^2 \Delta t)`` is literally the
      heat-kernel probability measure, yet the package never sees ``\nu`` or ``\Delta t``.
    - **Do not restrict to positive ("measure") symbols.** ``L^\infty``-symbol is the right generality;
      convolution-with-a-finite-measure is a *strict subclass* whose symbol must be **continuous**, and
      the 2/3 mask and sharp spectral cutoff have **discontinuous** symbols (kernels not in ``L^1``) — so
      they are *not* such convolutions yet are valid multipliers we rely on. Positivity of the kernel ⟺
      positive-definite symbol (**Bochner**) ⟹ probability measure ⟹ realizable SGS stress
      (**Vreman, Geurts & Kuerten 1994**, realizability *iff* positive filter) ⟹ bona-fide filtered PDF
      (**Colucci et al. 1998**, the FDF); all of that is **consumer** semantics. No
      `PositiveFilter` type, no realizability checks. (Interpolation already ships signed kernels by
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
20. **Convolution — the kernel-multiplier family realized (§2; the new `Convolution` module).**
    Implements the multiplier designed in decision 19 as periodic (circular) convolution of a field
    with a kernel, in spectral representation: by the convolution theorem on the torus, `f ⋆ g` is the
    **coefficientwise spectral product** ``\hat f \cdot \hat g``. The kernel `g` is supplied by its transfer function
    ``\hat g`` as a **`ScalarFieldSpectral`** (decision 19's open "kernel as a field" call, chosen for
    elegance); a scalar kernel broadcasts over the fiber, so one method serves scalar/vector/tensor
    fields, and because a kernel is itself a scalar field in spectral representation, `convolve(g₁,
    g₂)` composes two kernels for free (the `R = 0` case). `convolve` / `convolve!` mirror `laplacian`
    / `laplacian!`: coefficientwise ⇒ aliasing-safe (no `_guard_noalias!`; destination may alias the
    field), `@_assign!`-routed (threads on CPU), with the five-argument `α`/`β` accumulate form
    (invariant 10). Spectral representation only — there is no physical-space `convolve` (the
    differential-operator precedent).

    *This completes invariant 1 rather than weakening it.* The coefficientwise spectral product is the
    operation invariant 1 names but bans **as `*`** (because `*` would read as the spectral *pointwise*
    product, which it is not). It is offered here under its true name — `convolve`, never `*` — and is
    linear in the field for a fixed kernel; the spectral pointwise product, division, and norms remain
    absent. `convolve` / `convolve!` / `spectral_cutoff` are separate generics, so the `FieldAlgebra`
    198-method and point-value 118-method parity baselines are unchanged.

    One neutral builder ships: `spectral_cutoff(reference, multipliers, k)` — the isotropic sharp
    low-pass (idempotent projection), the basis of de-aliasing / spectral truncation; physics (an LES
    filter, an integrating factor ``\exp(-\nu k^2 \Delta t)``) stays a `ScalarFieldSpectral` the consumer builds
    from the wavenumbers (invariant 12). Naming follows the §2 convention (the verb `convolve` for a
    generic transformation; the module noun `Convolution`, parallel to `Interpolation` / `interpolate`).
    Tested CPU (`test/convolution.jl`, Float64/Float32 — the translation kernel
    ``\exp(-i k_x m \Delta x) \Leftrightarrow`` `circshift` is the independent physical oracle, plus identity/scaling/
    cutoff-idempotence/composition/α-β/alias) and GPU (ROCm device-vs-CPU parity in `test/gpu/suite.jl`);
    benchmarked (the `convolution` class). The L²-weighted and matrix-valued (anisotropic) kernels
    remain future.
21. **Shell-space spectral primitives — the radial coordinate, the band-pass, and the shell-resolved
    inner (extending `Convolution` + `Reductions`).** Three neutral primitives surfaced by the
    `examples/HIST_*` demos, each the code image of an established object and each slotting into an
    existing family — no new module, no parity-baseline change (separate generics), physics names
    stay consumer-side (invariant 12). They close the largest hand-rolled pieces of a real
    pseudospectral consumer (the energy spectrum, the forcing band, the viscous integrating factor):

    - **`squared_wavenumber_field(reference, multipliers)` (`Convolution`)** — the radial coordinate
      ``|k|^2`` of spectral space as a `ScalarFieldSpectral` (real, stored complex, like a cutoff mask).
      Decision 19 fixed that "the symbol is data": the consumer builds ``\exp(-\nu |k|^2 \Delta t)``, a smooth
      envelope, or a Germano filter ``1/(1 + \Delta^2 |k|^2)`` by broadcasting over its `field_data`, then applies
      it with `convolve`. The package hands over the coordinate; ``\nu``, ``\Delta t``, the width stay consumer-side.
      It wraps the existing `_squared_wavenumber_broadcast` (the Laplacian's ``|k|^2``, true value at
      Nyquist — invariant 5).
    - **`spectral_band(reference, multipliers, k_lo, k_hi)` (`Convolution`)** — the isotropic annular
      band-pass, the generalization of `spectral_cutoff` (now its `k_lo = 0` special case, refactored
      to delegate). Idempotent ⇒ a projection; it selects a wavenumber shell — a de-alias band, a
      forcing band, a filter ring. With it the demos' low-shell forcing becomes pure package ops:
      band energy `= inner(convolve(u, band), u)`, then a rescaling `convolve` — no scalar indexing.
    - **`radial_spectrum(f, multipliers)` (`Reductions`; introduced as `shell_spectrum`, renamed in
      decision 22)** — the **radial (shell-binned) power spectrum**: `inner` decomposed into isotropic
      ``|k|``-shells. Returns `(shells, spectrum)` with the exact refinement `sum(spectrum) == inner(f, f)`
      (same rfft half-spectrum Parseval weighting, now resolved per mode). This is the genuinely new
      reduction — spectral-representation only, like the Parseval `inner` — and the architectural framing
      is precisely *"the energy spectrum is the radially-resolved inner"* (decision 19's L²/integration
      structure, refined by the spectral radial coordinate). The consumer's energy spectrum over the
      shell wavenumber ``\kappa`` (``= |k|``) is ``E(\kappa) = \tfrac12\,\mathrm{spectrum}``; the
      neutral noun keeps physics out (invariant 12). Shells run to the corner wavenumber so the
      refinement is exact; on a de-aliased field the high-``|k|`` shells are empty.

    *Device-clean by construction.* `squared_wavenumber_field` / `spectral_band` are broadcast kernel
    builders (the `spectral_cutoff` pattern); `radial_spectrum` bins via a sequence of **masked
    reductions** (one per shell), not a histogram scatter — no scalar indexing, no atomics, GPU-portable
    as an occasional diagnostic (a per-step spectrum would want an atomic-histogram kernel; deferred,
    unneeded). Tested CPU (`test/convolution.jl` band/coordinate vs the ``|k|^2`` oracle + cutoff equivalence;
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
    the two representations. `radial_spectrum` (decision 21, introduced as `shell_spectrum`) is the
    spectral half; this entry designs the physical half and the point application, and fixes the
    terminology so the family is coherent.

    *Terminology (decided; the rename is **done**).* `shell_spectrum` is renamed **`radial_spectrum`**,
    and the physical dual **`radial_correlation`** is added (Phase 1, **done**). "Radial" is the
    isotropic-average qualifier common to both spaces — and to the *radial* distribution function of point
    statistics; "shell" named the binning implementation and does not pair with the physical-space
    correlation. The two are the **radial reductions**: a Fourier-dual pair in `Reductions`, each mapping
    a field to a 1-D radial profile, named by the quantity's noun per §2 (`spectrum` / `correlation`)
    under the `radial` qualifier. `radial_spectrum`'s math is unchanged (`sum == inner`). Physics names
    stay consumer-side: the energy spectrum ``E(k) = \tfrac12\,\mathrm{radial\_spectrum}``, the integral/Taylor scales from
    `radial_correlation`, the RDF `g(r)` from `radial_correlation` of a density field. (The rename was
    safe — the API is not frozen and `shell_spectrum` had shipped the same day with no external users.)

    *The physical dual — `radial_correlation` (done).* ``C(r)`` = radially-averaged ``\langle f(x) \cdot f(x+r)\rangle``
    (full fiber contraction — the trace of the correlation tensor, mirroring `inner`) ``= \mathcal F^{-1}(|\hat f|^2)/N``
    binned over minimum-image ``|r|`` shells. ``C(0) = \langle |f|^2\rangle = \mathrm{inner}(f, f)`` (the
    variance); for a zero-mean field ``C(r) \to 0`` at large ``r``. **The open design point was resolved
    as the user chose:** `radial_correlation(f, plans)` takes the field in spectral representation **plus
    its transform plans** (symmetric with how the differential operators take `multipliers`) — `Reductions`
    imports `to_physical` from `Fields` to do the one inverse rfft, then bins with the same masked-reduction
    machinery as `radial_spectrum`, in ``r`` instead of ``|k|``. Verified against an independent
    binned-circshift autocorrelation (CPU `test/reductions.jl`, GPU `test/gpu/suite.jl`) and `C(0) = inner`.

    *The two-field co-spectra — `radial_spectrum(f, g)` / `radial_correlation(f, g)` (done).* The mixed
    second-order statistics of two compatible, equal-order fields, refining the **mixed** `inner(f, g)` exactly as
    the single-field forms refine `inner(f, f)`. The **co-spectrum** bins the Parseval-weighted cross-power
    density ``\sum_c \mathrm{Re}(\hat f_c \overline{\hat g_c})`` over ``|k|``-shells (``\sum_\kappa E_{fg} = \mathrm{inner}(f, g)``);
    the **cross-correlation** ``C_{fg}(r) = \langle f(x)\cdot g(x+r)\rangle = \mathcal F^{-1}(\overline{\hat f}\,\hat g)/N``
    binned over ``|r|``-shells (``C_{fg}(0) = \mathrm{inner}(f, g)``). Two properties fall out of the math and are
    pinned by tests: each is **symmetric** in ``f, g`` — ``\mathrm{Re}`` is conjugation-symmetric for the spectrum,
    and the ``\pm r`` folding of the min-image shells symmetrizes the correlation (``C_{fg}(-r) = C_{gf}(r)``, so the
    radial average is ``\tfrac12(C_{fg}+C_{gf})``) — and the single-field forms are exactly the ``g = f`` case
    (``\mathrm{Re}(\hat f\,\overline{\hat f}) = |\hat f|^2``; asserted bit-identical). Unlike the power spectrum the
    co-spectrum **may be negative** in a shell (anticorrelated modes — the canonical use is a momentum/scalar flux
    co-spectrum, where sign is physical). Implementation reuses the single-field code: the binning helpers
    (`_radial_spectrum_bin`, `_correlation_field_from` + `_radial_average`) are shared, the two-field methods only swap
    the per-mode density (``|\hat f|^2 \to \mathrm{Re}(\hat f\,\overline{\hat g})``) / the per-component spectrum
    (``|\hat f|^2 \to \overline{\hat f}\,\hat g``, Hermitian for real ``f, g`` ⇒ the c2r reconstruction is exactly real).
    These are **new methods on the existing `Reductions` generics** — no export change, the 198/118 parity baselines
    are unchanged. Verified CPU (`test/reductions.jl`: analytical oracles — an orthogonal pair ``\cos x \perp \sin x``
    giving zero, and ``\cos x \pm \cos 2x`` giving ``\pm\tfrac12`` in adjacent shells that cancel to ``\mathrm{inner} = 0``;
    the ``g = f`` consistency; the ``f \leftrightarrow g`` symmetry; and an independent binned-circshift cross-correlation
    on a random pair) + GPU (ROCm device-vs-CPU parity, `test/gpu/suite.jl`); benchmarked (`reductions` class).

    *Points → RDF (Phase 2, done).* The pair correlation ``g(r)`` of ``M`` points is computable
    in ``O(N + M \log M)`` (vs ``O(M^2)`` direct counting) via the **FFT structure-factor estimator** — exactly
    the implemented recipe: **anterpolate** the points to a grid density (positive/linear assignment), form the
    overdensity ``\delta = \rho/\bar\rho - 1``, **FFT**, **deconvolve** ``\hat\delta`` by the assignment window
    ``\hat W``, then `radial_correlation` of the deconvolved field gives ``\xi(r) = \langle\delta(x)\delta(x+r)\rangle``
    and ``g(r) = 1 + \xi(r)`` (the ``i=j`` self term is the shot noise, isolated in the ``r=0`` shell, so
    ``g`` at ``r>0`` is clean). With ``\hat\rho(k) = \sum_i e^{-i k \cdot x_i}``,
    ``S(k) = |\hat\rho|^2/M = 1 + \bar n\,\hat h(k)`` (Ornstein–Zernike) and ``g = 1 + h``. We already owned
    anterpolate + the transforms + both radial reductions; the **one new neutral primitive is the
    assignment-window deconvolution**, the rest is the consumer recipe (invariant 12). Three corrections, all
    handled:

    - **Assignment-window deconvolution (`assignment_window`, `Convolution`).** Scattering with kernel ``W``
      gives ``\hat\rho_g = \hat W(k)\,\hat\rho``, so the measured spectrum is suppressed by ``|\hat W(k)|^2`` —
      divide it out (a `convolve` by ``1/\hat W``). Shipped for the **linear (CIC) positive** assignment:
      ``\hat W(k) = \prod_a \operatorname{sinc}^2(k_a\Delta x_a/2)``, no in-band zeros. (Higher positive
      B-splines / the signed-kernel closed forms remain future.)
    - **Shot noise.** The ``i=j`` self term is a constant ``+1`` floor in ``S(k)`` (a ``\delta(r)`` at the
      origin): in the binned ``g(r)`` it lands entirely in the ``r=0`` shell, so reading ``g`` at ``r>0`` is the
      subtraction (no extra step). Consumer-side by convention.
    - **Aliasing / resolution.** The grid folds high-``k`` at Nyquist — trust ``k \lesssim \tfrac23 k_\mathrm{Nyq}``, and ``g(r)``
      below a few grid cells is unreliable regardless of corrections. FFT-RDF resolves **intermediate /
      large-scale clustering** (e.g. inertial-range preferential concentration), *not* a sharp contact
      peak (interlacing — Sefusatti et al. — is a future refinement). This matches the intended consumer
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
    math), ``\Delta r`` = the finest grid spacing, minimum-image ``|r|`` binning, ``C(0) = \mathrm{inner}``
    exact. **Phase 2:** `assignment_window` (the linear/CIC ``\prod \operatorname{sinc}^2`` deconvolution
    window, `Convolution`) + the documented point-RDF recipe, validated against direct ``O(M^2)`` counting.
    **Co-spectra (done):** the two-field `radial_spectrum(f, g)` / `radial_correlation(f, g)` (the
    cross-power / cross-correlation pair — momentum/scalar fluxes; new methods on the existing generics that
    reuse the single-field binning, refining the mixed `inner(f, g)`; symmetric, may be negative — see above).
    **Future (deferred until a consumer makes them concrete):** higher positive-B-spline / signed-kernel
    window transforms and interlacing (sharper small-``r`` ``g``); and — the "meaningful fibers over the
    radial coordinate" — the anisotropic / tensor-valued radial spectra ``E_{ij}(\kappa)`` and the
    Craya–Herring longitudinal/transverse split, which only earn their structure under anisotropy
    (e.g. shear flow), per the §2 rule against speculative structure.
23. **Spectral-domain transfer — `DirectDFT` (exact) and the native `NUFFT` (fast). [Both DONE.]**

    *The object.* The transfer layer (§10) had one scheme family — the physical-domain local splines.
    This adds the **spectral-domain** transfer: evaluation/deposition between Fourier coefficients and
    scattered points, the exact off-grid form of the field. Both families are unified under a new
    supertype `AbstractTransferScheme`, sharing the `interpolate`/`anterpolate` verbs and the L²-adjoint
    contract; a scheme is a choice of *(kernel, representation)*. The spectral schemes dispatch on a
    field in spectral representation (invariant 2: hand ``W`` whichever representation it reads — a
    spectral solver hands ``\hat f`` for free); `anterpolate` returns a section, here in spectral
    representation (the Fourier coefficients of ``\sum_p q_p\delta_{x_p}``).

    *`DirectDFT` (done).* The literal ``O(NM)`` sum (``N`` the grid-point count, ``o`` the grid origin):
    type-2 ``f(x_p) = \tfrac1N\sum_{\text{stored }k}
    \alpha(k)\,\mathrm{Re}(\hat f(k)\,e^{i k\cdot(x_p-o)})`` (the rfft half-spectrum reconstruction, with
    the Parseval weight ``\alpha`` of decision 18 — ``1`` on the ``k_x=0``/even-Nyquist planes, ``2`` else),
    type-1 ``(W^\top q)(k) = \sum_p q_p e^{-i k\cdot(x_p-o)}``. It is the *definition* of the
    spectral-domain pair, so it is at once a transparent exact baseline, the **divergence-free
    reference** (it reproduces the band-limited field exactly — verified ``\sim 10^{-16}`` off-grid —
    where the splines break ``\nabla\cdot u=0``), and the **oracle** that will validate `NUFFT`. It
    matches `to_physical` at the grid nodes and `to_spectral` from node samples (both exact to round-off),
    and satisfies ``M\,\langle W\hat f, q\rangle_{\mathrm{pts}} = N\,\langle \hat f, W^\top q\rangle`` (the
    measure factor, as for the splines — decision 17). Two simple KernelAbstractions kernels (type-2
    over points, type-1 over modes — no atomics), the per-axis wavenumbers + ``\alpha`` built host→device
    like the multipliers; no FFT, window, or oversampling. Stateless `DirectDFT()`; CPU + GPU-portable.

    *Native `NUFFT` (decided: own it, no dependency — done).* The fast ``O(N\log N + M)`` windowed
    gridding form of `DirectDFT`: **spread → FFT → deconvolve**, all reusing existing machinery — the
    transfer kernels (spread/gather with an exponential-of-semicircle window in place of the spline
    coefficients), a `FieldTransformPlans` on an oversampled (``\sigma=2``) grid, and a ``1/\hat\psi``
    deconvolution `ScalarFieldSpectral` — ``\psi`` the smooth compact spreading window, ``\hat\psi`` its
    Fourier transform — built like `assignment_window` (which **is** the ``\hat\psi`` of the linear/CIC
    window — so `NUFFT` generalizes the decision-22 RDF deconvolution). The one new ingredient is that
    window ``\psi`` (exp-of-semicircle, GPU-trivial) and its transform ``\hat\psi``
    (host quadrature, the ``z=\sin\theta`` substitution regularizing the endpoint); the stencil width
    and the shape parameter ``\beta`` follow the Barnett–Magland–af Klinteberg ES rule for the tolerance.
    Verified against `DirectDFT` (and `to_physical`) to the requested tolerance ``\varepsilon``
    (``\sim 10^{-12}`` at the default) for scalar and
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
