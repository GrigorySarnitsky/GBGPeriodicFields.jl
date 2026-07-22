# GBGPeriodicFields — Architecture and Rationale

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
fluid dynamics and turbulence on three-dimensional rectangular periodic domains. It
provides scalar, vector, and second-order tensor fields with two storage
representations — physical and spectral (the spectral one stored non-redundantly as the
real-to-complex / `rfft` half-spectrum) — plus
FFT transform plans, spectral multipliers, storage-wise broadcasting, fiberwise
algebra (`FieldAlgebra`), spectral differential operators (`DifferentialOperators`), periodic
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
of a base ``B`` and a fiber ``V``. The fiber is a tensor power of ``\mathbb R^3``, fixed by the
**tensor order** ``R``: ``V = \mathbb R`` (``R = 0``, scalar), ``\mathbb R^3`` (``R = 1``, vector, `FiberVector`),
``\mathbb R^3 \otimes \mathbb R^3 = \mathbb R^{3\times 3}`` (``R = 2``, second-order tensor, `FiberTensor2`),
and higher (`FiberTensor3/4`). A section
assigns a fiber value to each base point; the fiber-last data layout ([§3](@ref "3. Types and memory layout")) is exactly
that section, stored base-indexed.

Three structures of the package are then *parameters of a section*, not separate
worlds:

- **The base** is either the structured grid `Grid3D` — a field is a section sampled
  on the grid — or the unstructured point set `PointSet` — point-values are a section
  sampled at scattered points ([§10](@ref "10. Interpolation and anterpolation (the grid↔point transfer layer)")). Same fibers, different base.
- **Fiberwise algebra is the vertical (within-fiber) structure**: addition, real
  scaling, contraction with a constant fiber, dot/cross/tensor products, transpose,
  sym/skew/dev, and norms all act inside fibers, pointwise in the base, and are
  therefore **base-independent** — the very same operation on the very same fiber
  type, whether the base is a grid or a point set. This is the structural reason one
  set of generated kernels ([§6](@ref "6. The code-generation architecture of `FieldAlgebra`")) serves fields and point-values verbatim, and the
  mathematical motivation for treating the **section as the primary abstraction**: a
  shared `AbstractFiberSection{T, R}` supertype spanning both, in the
  `FiberSections` module ([§10](@ref "10. Interpolation and anterpolation (the grid↔point transfer layer)")).
- **Differential operators are the complementary horizontal structure** — gradient,
  divergence, curl, Laplacian are derivatives *along the base*, using the flat
  connection of the periodic box ([§4](@ref "4. Spectral machinery")). They are bound to a base with a differentiable
  structure: they act on grid sections (in the spectral representation) and not on
  point-value sections, which carry the vertical algebra but no derivatives.
- **Base reductions are the third operation family** — integrating the base away against a
  **measure** the base carries (`Grid3D` cell volume; `PointSet` counting): `integral`
  (extensive), the normalized `inner`/`l2norm`, and the `mean`/`std`/`var` moments. They map a
  section to a scalar or a fiber and are base-dependent (the measure is the base's), yet — like
  the vertical algebra — are shared by fields and point-values through `AbstractFiberSection`
  ([§12](@ref "12. Reductions"), decision 18). The same *measure* concept recurs as the interpolation kernel (below) and a
  convolution multiplier (the `Convolution` module, decision 20): one L²/integration structure in three roles (the
  measure taxonomy, decision 19).
- **Representation is a choice of basis for a grid section's data** (distinct from the
  fiber frame above): physical storage uses the nodal basis, spectral storage the Fourier
  basis, and the rfft is the linear isomorphism between them. A point-value section has no second
  representation — there is no periodic grid to transform over — so the point types
  are representation-free ([§10](@ref "10. Interpolation and anterpolation (the grid↔point transfer layer)")).

(The vertical/horizontal language is the bundle-theoretic one — fiber directions versus the
connection's base directions — applied here by analogy to *operations*: the fiberwise algebra
is order-zero and fiber-preserving, the differential operators are the connection's covariant
derivative, order one. Strictly, *vertical* (``\ker \mathrm{d}\pi``, the kernel of the bundle
projection ``\pi``'s differential — canonical) and *horizontal* (a connection-chosen complement) are
subbundles of the total space's tangent bundle.)

Transfer between sections over *different* bases is the interpolation/anterpolation
pair: pulling a grid section back to points (evaluation — pairing with a Dirac mass ``\delta_x`` — ``f(x) = \langle \delta_x, f\rangle``) and the
adjoint pushforward of point masses onto the grid. The full function–measure duality
is given in [§10](@ref "10. Interpolation and anterpolation (the grid↔point transfer layer)") and the `Interpolation` module docstring; the interpolation weights are
themselves a unit-mass kernel **measure** (signed for the higher-order schemes), the
base-changing sibling of the convolution multiplier — see the measure taxonomy
(decision 19).

### The architecture map

A field — or values sampled at scattered points — is a **section** ``s``, a right inverse of the bundle
projection ``\pi``:

```math
B \xrightarrow{ s } E \xrightarrow{ \pi } B, \qquad \pi \circ s = \operatorname{id}_B,
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
  invariants, pointwise norms — generated once ([§6](@ref "6. The code-generation architecture of `FieldAlgebra`")).
- **Horizontal — differential operators** ([`DifferentialOperators`](@ref GBGPeriodicFields.DifferentialOperators)): `gradient`, `divergence`, `curl`,
  `symmetric_gradient`, `laplacian`, …, applied as spectral multipliers ([§4](@ref "4. Spectral machinery")).
- **Convolution** ([`Convolution`](@ref GBGPeriodicFields.Convolution)): the kernel multiply ``\hat f \cdot \hat g`` in spectral representation ([§11](@ref "11. Convolution")).
- **Measure / L²** ([`Reductions`](@ref GBGPeriodicFields.Reductions)): `integral`, `inner`, `weighted_inner`, `l2norm`, `mean`, the radial spectra ([§12](@ref "12. Reductions")).
- **The grid↔point transfer** ([`Interpolation`](@ref GBGPeriodicFields.Interpolation)): interpolation ``W`` and its adjoint anterpolation
  ``W^{\top}`` ([§10](@ref "10. Interpolation and anterpolation (the grid↔point transfer layer)")).
- **Support mechanics** — types & memory layout ([§3](@ref "3. Types and memory layout")), validation design ([§5](@ref "5. Validation design")), code generation ([§6](@ref "6. The code-generation architecture of `FieldAlgebra`")),
  aliasing ([§7](@ref "7. Aliasing policy")), broadcasting ([§8](@ref "8. Broadcasting")), performance & threading ([§9](@ref "9. Performance model and CPU threading")).

Reductions, convolution, and the grid↔point transfer are the same L²/integration structure in three
roles — the **measure taxonomy** (decision 19). Which operation is valid in which representation, the naming rules, and the
documentation policy follow.

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
  pointwise norms, contractions of two fields (dot, cross, tensor `mul!`, inner
  products): physical space only. The coefficientwise spectral product is *not* the
  Fourier representation of the pointwise product (that would be a convolution),
  so offering it *as a product* would silently compute the wrong physical operation —
  that coefficientwise product *is* convolution, exposed under its true name as `convolve`
  (the `Convolution` module, decision 20), never as `*`.

The pointwise product is *not* preserved by ``\mathcal F`` — the **convolution-theorem square**:

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
  (`dot`, `cross`, `mul!`, `transpose`, `norm`, `mean`, `std`, `var`, `maximum`, `minimum`,
  `extrema`); the continuum-mechanics decomposition abbreviations `sym` / `skew` / `dev` are likewise
  conventional.
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
``\equiv \langle\cdot,\cdot\rangle``, `l2norm` ``\equiv \lVert\cdot\rVert``, `integral`
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
the first axis halved per rfft. Rationale: with column-major storage, each
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
`!`-transform's source on any backend, matching the `to_spectral!`/`to_physical!` docstrings; to keep
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
(`_same_scalar_type`, `_same_tensor_order`, `_same_grid`, `_same_layout`) composed
into `_check_same_domain`, the representation-dispatched
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

Alias safety is **by construction**: every fused pass — the one-pass spectral operators
(decisions 32 and 38's operator kernels) and the generic fiberwise executor behind the algebra
(decision 39) — reads all of an element's source values into registers before writing any of that
element's destinations, and elements are disjoint, so an in-place call (`curl!(u, u, m)`,
`transpose!(A, A)`, `sym!(A, A)`) is computed directly and is bitwise-identical to the
non-aliased call, with no temporary. The former guard family (`_guard_noalias!` and its
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
`Fields`. The generic method is `Broadcast.materialize!` — the safe polarity: GPU and unknown
array wrappers keep the standard fused broadcast, so **invariant 6 holds by dispatch**, not
discipline. The `Union{Array, SubArray{…,<:Array}}` specialization threads a single
instantiated `Broadcasted` over contiguous chunks (fusion preserved — one `Broadcasted`
tree, no temporaries, one memory pass), **bitwise-identical to serial** because each output index is
written once. The threaded path splits the destination's slab axis — the last among the largest,
so a whole-vector-field write splits a grid axis, never the length-3 fiber — and runs the standard
fused `materialize!` per slab over sliced views of the operands, so each slab executes the same
SIMD kernel the serial path uses (decision 38; its per-element predecessor ran ~4.7× slower per
core and *inverted* at low thread counts — [`PERFORMANCE.md`](performance.md) §4 finding (l)). A serial cutoff (`_SERIAL_CUTOFF`, default 2^14) keeps small ops — including
the one-element zero-mode views — serial. Policy is **hybrid**: threaded when
`nthreads() > 1` and above the cutoff, with a task-local `ScopedValue` override
(`with_threading(enabled = …)`) for nested-parallel callers.

Two plug points route work through `_assign!`: the field broadcast style's `copyto!` (all
whole-field dotted ops and the field-level algebra), and the kernel assignments — the
codegen body builders emit `_assign!(target, …)` (via `_to_broadcasted`, which rewrites a
dotted formula into a lazy `broadcasted` tree at codegen time), and the hand-written
`FieldAlgebra` / `DifferentialOperators` kernels use the `@_assign!` macro in place of `.=`. No
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

**The kernel sites split into two classes for the threading policy — and two kernels are not
bitwise.** The fused operations of decisions 38/39 (`gradient!`, `curl!`, `symmetric_gradient!`, the
fiberwise executor behind the algebra) are `KernelAbstractions` kernels **on a device only**; on a
CPU array they run slab-threaded plain loops that pass through the same `_use_threads` gate as the
broadcast route, so the cutoff and the `with_threading` override govern them. Two operation families, however,
are KA kernels **on every backend** — the gather/scatter transfer kernels
([§10](@ref "10. Interpolation and anterpolation (the grid↔point transfer layer)")), and the radial
shell binning (decisions 25, 34) — and on a CPU array these launch on the `CPU()` backend, which
partitions the index range by `Threads.nthreads()` itself (`helmholtz_projection!` left this set when
decision 40 gave it a gated loop twin, so what remains is exactly the atomic/irregular kernels — the
exemption is structural, not historical). Two consequences follow for that pair,
and neither is a defect to fix — they are the price of their kernel shapes. First, a KA launch
**never consults the `_assign!` policy above**: the serial cutoff and the `with_threading` override
do not reach those two operation families, which thread by KA's rules at every size (the
exclusion is stated on `with_threading`'s own docstring). Second, the two kernels that accumulate through `Atomix` — the anterpolation scatter and the
shell binning — sum in a **nondeterministic order**, and floating-point addition is not associative,
so they are **not bitwise-reproducible**: not across thread counts, and not even between two runs at
one thread count. Measured on a Ryzen 9800X3D over twelve trials at 8 and 16 threads, every trial
differed, `anterpolate!` by 2–3 ulp of the field's scale and `radial_spectrum` only inside
numerically-zero shells (max ``\lvert \Delta \rvert`` = 1.4e-47). The two kernels with **disjoint**
writes — the projection and the gather — are bitwise-reproducible, and were measured to be so across
1, 2, 4 and 8 threads. The threading suite (`test/threading.jl`) encodes exactly this split: bitwise equality asserted for
the disjoint pair (including against a subprocess launched at a different thread count, the one
comparison the in-process `with_threading` toggle cannot make), a tolerance for the `Atomix` pair —
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

Both carry the usual allocating / in-place (`!`) pair and a five-argument `α`/`β` form (``\beta = 0``
overwrite, ``\beta \ne 0`` accumulate — the `mul!` convention, since they are the linear maps ``W`` /
``W^\top``; accumulation is the common case for the scatter). They are the symmetric named pair — only
interpolation also gets the callable `f(x)`, because evaluation is pointwise while its adjoint is not (see
the module docstring). The driving case is two-way coupling in the cloud-parcel DNS this package serves:
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
adjointness — evaluation as pairing with a Dirac mass, ``f(x) = \langle \delta_x, f\rangle``, and anterpolation
as the pushforward of point masses, ``\sum_p q_p \delta_{x_p}`` (regularized to ``\sum_p q_p w(\cdot - x_p)``,
i.e. a regularized point source) — is given in full in the `Interpolation` module docstring.

Those two facts — adjointness and a partition-of-unity reproduction — are the commuting identities below.
The two inner products are concrete pairings against the measure each base carries: on point-values
``a, b`` the **counting measure** makes ``\langle\cdot,\cdot\rangle_{\text{pts}}`` a plain sum over the
``M`` particles, while on fields ``f, g`` the **cell-volume measure** makes
``\langle\cdot,\cdot\rangle_{\text{grid}}`` a volume integral over the box ``\Omega`` (with ``\cdot`` the
fiber contraction — the ordinary product for scalars, the dot product for vectors):

```math
\langle a, b\rangle_{\text{pts}} = \frac{1}{M} \sum_{p=1}^{M} a_p\cdot b_p,
\qquad\qquad
\langle f, g\rangle_{\text{grid}} = \frac{1}{|\Omega|}\int_{\Omega} f(x)\cdot g(x)\,\mathrm{d}x
= \frac{1}{N} \sum_{x} f(x)\cdot g(x),
```

each normalized by its total measure — the ``M`` particles, and the box volume ``|\Omega|`` (equivalently
the ``N`` grid cells) — exactly as the package's `inner` computes them. Writing
``\operatorname{sample}_{\text{grid}}`` for sampling a function at the grid nodes,
``\operatorname{eval}_{\text{pts}}`` for evaluating it at the points, and ``\phi`` for any polynomial in
``\Pi_d`` (the polynomials up to the scheme's reproduction degree ``d``), the adjointness and the polynomial reproduction read

```math
\sum_{p} (W f)_p\cdot q_p = \sum_{x} f(x)\cdot(W^{\top} q)(x),
\qquad\qquad
W \bigl(\operatorname{sample}_{\text{grid}} \phi\bigr) = \operatorname{eval}_{\text{pts}} \phi
\quad (\phi \in \Pi_d),
```

the left is the plain transpose ``W^{\top}`` — the partition-of-unity scatter `anterpolate` applies;
normalizing each side by its base count gives the measure-weighted ``M \langle W f, q\rangle_{\text{pts}} =
N \langle f, W^{\top} q\rangle_{\text{grid}}`` (``N`` grid cells, ``M`` points — the ``N/M`` is just the two
normalizations). Intrinsically the pair is a
**pullback–pushforward**: writing ``\iota : B_{\text{points}} \to \Omega`` for the map from the point base
``B_{\text{points}}`` to the torus ``\Omega`` that carries each point to its location ``x_p``, pulling the
**trivial** bundle back along ``\iota`` keeps
the fiber and changes only the base, ``B_{\text{points}} \times V = \iota^{*}(\Omega \times V)`` — a
**base-change, not a fiber operation** (decision 19):

```math
\begin{CD}
B_{\text{points}} \times V @>{\iota \times \mathrm{id}_V}>> \Omega \times V \\
@V{\pi}VV @VV{\pi}V \\
B_{\text{points}} @>>{\iota}> \Omega
\end{CD}
```

Interpolation is the **pullback of the section**, ``W = \iota^{*} \otimes \mathrm{id}_V`` (fiber-preserving —
the trivial bundle leaves the fiber by the identity; ``(Wf)_p = f(x_p)``); anterpolation the
**pushforward of the dual measure**, ``\iota_{*}`` (``\iota_{*} q = \sum_p q_p \delta_{x_p}``, the
Dirac mass above regularized by the stencil) — for the uniform measures ``\iota_{*} = (N/M) W^{\top}``, the
scalar rescaling that turns the implemented transpose ``W^{\top}`` into the exact L²-adjoint. They have
**opposite variance** — ``\iota`` pulls a function back but pushes a measure forward — so the adjointness
*is* their adjunction ``\langle \iota^{*} f, q\rangle_{\text{pts}} = \langle f, \iota_{*} q\rangle_{\text{grid}}``. (Strictly ``W`` is ``\iota^{*}`` *after* a
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
  grid origin, and ``x_p`` the ``p``-th sample point). `DirectDFT` is the exact ``O(NM)`` form — the
  *definition* of the spectral-domain pair, hence a transparent baseline, the divergence-free
  reference (it reproduces the band-limited field exactly, matching `to_physical` at the nodes), and
  the oracle for the fast `NUFFT` (the ``O(N\log N + M)`` windowed gridding version, owned natively —
  spread → FFT → deconvolve, reusing the spline kernels with a window, an oversampled
  `FieldTransformPlans`, and an `assignment_window`-style deconvolution; exact to a requested tolerance
  ``\varepsilon`` on the resolved sub-Nyquist band). The adjoint relation carries
  the measure factor as for the splines: ``M \langle W\hat f, q\rangle_{\text{pts}} = N \langle \hat f, W^\top q\rangle_{\text{grid}}``.

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
`min(2m+1, 2n)`; the Lagrange scheme to degree `2n+1`.

**Data types — the unstructured base, in the package's own language.** Interpolation needs
to name two new objects: off-grid locations and the field values there. The package names
them in its base/fiber vocabulary, *not* as particles — deliberately, because
GBGPeriodicFields is a **math backend** ([§1](@ref "1. Purpose and scope")): "particle"/"tracer" is the consumer's
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
- E. Catmull, R. Rom, [*A class of local interpolating splines*](https://doi.org/10.1016/B978-0-12-079050-0.50020-5), in: Computer Aided Geometric Design, Academic Press, 1974, pp. 317–326.

## 11. Convolution

`Convolution` is the **kernel-multiplier** family: periodic (circular) convolution of a field with a
kernel, in spectral representation. By the convolution theorem ([§2](@ref "2. The central principle: the architecture follows established mathematics")), ``f \star g`` is the coefficientwise
product ``\hat f \cdot \hat g``; `convolve`/`convolve!` (``\equiv \star``, also exported as the infix operator `⋆`) apply a kernel supplied as a
`ScalarFieldSpectral` transfer function ``\hat g``, which multiplies every fiber component (one method for
scalar, vector, and tensor fields), with the α/β accumulate form and alias-safety of a coefficientwise op.
It is the **spectral sibling of `DifferentialOperators`** (both are coefficientwise multipliers, [§4](@ref "4. Spectral machinery")) and the
**same-base counterpart of the `Interpolation` transfer** (decision 19); offered under its true name
`convolve`, never as `*` (invariant 1). Spectral representation only; physics (an LES filter, an integrating
factor ``\exp(-\nu |k|^2 \Delta t)``) stays a consumer-built kernel (invariant 12). Five neutral builders
ship: `spectral_cutoff` (the isotropic sharp low-pass), `spectral_band` (its annular generalization),
`squared_wavenumber_field` (the ``|k|^2`` radial coordinate consumers build symbols from),
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
the reduction-dual of `convolve`, generalizing `inner` (decision 27); `mean`/`std`/`var` (extending `Statistics`)
and `maximum`/`minimum`/`extrema` (extending `Base`) are the moments — all on **physical fields and
point-values** (representation-free). The reductions `inner`/`l2norm` *also* act on a field in **spectral** representation
via Parseval's theorem (equal to the physical inner, no transform; the rfft half-spectrum weighting), and
`integral`/`mean` via the zero (DC) Fourier mode — ``\hat f(0) = \sum_x f`` gives the mean ``\hat f(0)/N``
and the integral ``(|\Omega|/N) \hat f(0)``, no transform. The **radial**
pair are spectral/physical duals: `radial_spectrum` (the shell-resolved `inner` — the power spectrum) and
its Wiener–Khinchin dual `radial_correlation` (the two-point autocorrelation
``C(r) = \mathcal F^{-1}(|\hat f|^2)/N``), each with a two-field **co-spectrum** form. Each reduction
additionally has a **mapped** form taking a leading function — a map applied to the section's fiber value
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
    on the zero-mean subspace, its kernel being the constant mode — idempotent Helmholtz
    projection — the discrete energy/entropy structure). Intentional-absence tests are
    symmetric across representations: nonlinear products absent in spectral; the
    differential operators absent in physical (spectral-only — no finite-difference
    operators yet). `Aqua.test_all` was added, which required `[compat]` bounds for every
    dependency. Two deliberate deferrals: a global L²/integration reduction is reserved
    for *separate code* (so adjointness tests use an inline L² inner product), and
    doctests wait until the package stabilizes and tutorials are written. Coverage detail
    lives in `docs/TESTING.md`.
12. CPU threading implemented ([§9](@ref "9. Performance model and CPU threading")), realizing the design formerly deferred in items 6/9. A
    `Fields._assign!` primitive threads elementwise/fiberwise assignments on CPU
    (`Base.Threads`, contiguous chunks, bitwise-identical to serial), routed in via the
    field broadcast `copyto!` and the kernel assignments (codegen `_to_broadcasted` plus the
    `@_assign!` macro for hand-written kernels); FFTW threads are matched to Julia's at load.
    Hybrid policy: on when `nthreads() > 1` and above a `2^14` serial cutoff, with a
    task-local `with_threading` ScopedValue override; the GPU path stays on the
    `materialize!` fallback. `[compat] julia` was raised to 1.11 here (for ScopedValue); the floor has
    since moved again, to 1.12 (decision 31).
    Reductions remain deferred (separate FP-ordering design).
13. Interpolation-layer design fixed ([§10](@ref "10. Interpolation and anterpolation (the grid↔point transfer layer)")):
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
    central-node hybrid. Reproduction is ``\min(2m{+}1, 2n)`` (smooth) / ``2n{+}1`` (Lagrange); the
    closed-form Catmull–Rom and the Lagrange cardinal
    basis are independent anchors, with partition of unity (⇒ conservation). Kernels are portable
    across CPU / CUDA / AMDGPU via **KernelAbstractions** (new dep) with the atomic scatter via
    **Atomix** (new dep); both index the native arrays linearly, so one kernel serves
    scalar/vector/tensor orders. Adjointness in the counting pairing — ``\sum_p (Wf)_p \cdot q_p = \sum_n f_n \cdot (W^\top q)_n``, the unnormalized sums over the ``M`` points and the ``N`` grid nodes — and conservation hold to roundoff;
    tested on CPU (`test/interpolation_transfer.jl`, Float64/Float32, incl. the TurTLE pin) and GPU
    (ROCm). Physical-space only. The kernels loop with the **contiguous (x) axis innermost**
    (stride-1 stencil access) — a measured GPU-first choice (≈1.6× at 256³, ≈3.9× for the 512³
    Lalescu on the RX 6700 XT), re-affirmed on CPU in the decision-37 production band: the 512³
    Zen 5 A/B found z-inner ~10% ahead only on the narrow Catmull–Rom stencil and 23% *behind* on
    the wide Lalescu one, so x-inner stands on both platforms and the reopened tiebreak is closed
    (`PERFORMANCE.md` §4b).
    The L²/volume-weighted (measure-consistent) adjoint is ``(N/M) W^\top`` (``N`` grid points, ``M`` sample
    points) — both base measures are uniform,
    so it is a scalar rescaling of the counting-transpose anterpolation, not a new operation — and is
    verified via `inner` as ``M \mathrm{inner}(Wf, q) = N \mathrm{inner}(f, W^\top q)`` (`test/interpolation_transfer.jl`, decision 19).
18. **The L² / measure structure on sections — the third operation family (done).** Advances
    the reduction deferral of items 6/11/[§9](@ref "9. Performance model and CPU threading"). The package's operations split into **vertical**
    (fiberwise, pointwise — `dot`, `norm`, `cross`; return sections), **horizontal** (differential —
    `gradient`, …; return sections), and now **base reductions** — integrate the base away against a
    **measure** it carries; return a fiber value or a scalar. Math grounding ([§2](@ref "2. The central principle: the architecture follows established mathematics")): a section lives in
    `L²(base, μ)`; the inner product is the metric pairing (cf. **Manifolds.jl** `inner(M,p,X,Y)`),
    the measure is an explicit object (cf. **Gridap.jl** `Measure`, **MeasureTheory.jl**), and the
    moments are the canonical reductions (cf. `Statistics` `mean`/`std`/`var`). All dispatch on
    `AbstractFiberSection`, so fields **and** point-values share one set of formulas (`FiberSections`
    "write it once").

    *The measure is a property of the base.* `Grid3D` → uniform Lebesgue quadrature (cell volume
    ``\prod_i \Delta x_i``); `PointSet` → **counting** measure (unit weight per point) — and this is
    *forced*, not a choice: a `PointSet` is grid-free ([§10](@ref "10. Interpolation and anterpolation (the grid↔point transfer layer)"), carries no domain), so the only well-defined
    measure is counting. Consequences:

    `integral(f)` is the **extensive** sum against the measure, `mean(f)` the **intensive** average
    ``\mathrm{mean}(f) = \tfrac{1}{\text{count}}\sum f`` — per base:

    - `Grid3D` (``N`` cells): ``\mathrm{integral}(f) = \int_\Omega f\,\mathrm{d}x = (\lvert\Omega\rvert/N)\sum f``, ``\mathrm{mean}(f) = \tfrac{1}{N}\sum f``.
    - `PointSet` (``M`` points): ``\mathrm{integral}(f) = \sum f``, ``\mathrm{mean}(f) = \tfrac{1}{M}\sum f``.

    So `mean` is the arithmetic average over base elements in both cases — ``\tfrac{1}{M}\sum`` over points
    (a plain sample mean), ``\tfrac{1}{N}\sum`` over the grid (which, the grid being uniform, equals the
    domain average ``\langle\cdot\rangle``). Names and conventions:

    - `integral(f)` — the **extensive** ``\int f\,\mathrm{d}\mu`` (the one quantity that scales with the base measure).
    - `mean(f)`, `std(f)`, `var(f)` — extend `Statistics` (we own the types ⇒ not piracy);
      **intensive**, **fiber-preserving** (`mean(VectorField) → FiberVector`, base reduced).
    - `inner(f, g)` — the **normalized** L² inner product ``\langle f, g\rangle = \mathrm{mean}(\mathrm{dot}(f, g))`` → **scalar**
      (fiber-contracting). *Normalized* (intensive) by deliberate choice: it matches the `mean`
      convention above and the intensive quantities of homogeneous turbulence (kinetic energy
      ``\tfrac{1}{2} \mathrm{inner}(u,u) = \tfrac{1}{2}\langle |u|^2\rangle``); for points it is ``\tfrac{1}{M}\sum \mathrm{dot}``, consistent with `mean`. Not the
      textbook extensive ``\int f\cdot g\,\mathrm{d}x`` — that is `integral(dot(f,g))` if ever needed.
    - ``\mathrm{l2norm}(f) = \sqrt{\mathrm{inner}(f,f)}``, generalized as `lpnorm(f, p)` (``p=2`` default; ``p=\infty`` ⇒ sup of the
      fiber magnitude — the CFL case). Chosen over `norm_L2`; **does not** touch the vertical `norm`.
    - `maximum`/`minimum`/`extrema` — extend `Base` for scalar sections; vector/tensor sup of
      magnitude via `lpnorm(·, Inf)`.
    - **No LinearAlgebra overloading**: `dot`/`norm` stay the vertical pointwise ops (return sections,
      scalar fields); the global `inner`/`l2norm` are package generics returning numbers.

    `inner`/`l2norm` are representation-invariant (Parseval): the physical reductions came first, and the
    **spectral `inner`/`l2norm` are now implemented** — for two fields in spectral representation
    ``\mathrm{inner}(\hat f, \hat g)`` equals the physical inner via the rfft half-spectrum Parseval weighting (each mode
    counts twice except those on the ``k_x=0`` plane and, for even ``N_x``, the Nyquist plane — the planes the
    rfft maps to themselves under conjugation, whose partners are already stored, so they count once), computed
    as a `dot` over the array plus two plane corrections — allocation-free in the `inner(f, f)`/`l2norm` case, while the mixed `inner(f, g)` materializes its two correction planes (decision 26). `integral` and `mean` are
    representation-invariant too, by a different route — the zero (DC) Fourier mode: under the
    unnormalized-forward convention the DC coefficient is ``\hat f(0) = \sum_x f(x)`` (real for a real
    field), so the mean is ``\hat f(0)/N`` and the integral ``(|\Omega|/N) \hat f(0)`` with no transform,
    read from the same zero-mode slot the constant-add writes (invariant 4). `lpnorm` (for ``p \ne 2``),
    `std`/`var`, and `maximum`/`minimum`/`extrema` have no single-coefficient form and remain physical-only.
    **Physics stays consumer-side**: energy ``\tfrac{1}{2} \mathrm{inner}(u,u)``, enstrophy
    ``\tfrac{1}{2} \mathrm{inner}(\omega,\omega)``, dissipation ``\nu \mathrm{inner}(\omega,\omega)``, rms ``\sqrt{\mathrm{inner}}``, intensities from `std`. The FP-ordering
    concern that deferred reductions (item 11) is real — so they are implemented with a defined summation
    order and a tolerance-based test (not the bitwise one used for the threaded assignments).
19. **The measure taxonomy — one L²/integration structure, three roles for "measure"; the recorded
    foundation for the spectral-multiplier family later realized as `Convolution` (decision 20).** The word *measure* recurs across the package
    (reductions, interpolation, and convolution) not by coincidence but
    because all three are facets of the **same L²/integration structure on sections** ([§2](@ref "2. The central principle: the architecture follows established mathematics")). This entry
    fixes the taxonomy so the three never get conflated and so the multiplier family starts from a
    recorded design. The math anchor (Grafakos, *Classical Fourier Analysis*, Thm 2.5.10): on a uniform
    periodic box every **homogeneous (translation-invariant) linear operator is a Fourier multiplier** — a
    coefficientwise ``m(k)`` — and the *bounded* ones are exactly those with symbol ``m(k) \in L^\infty``, where
    ``\lVert T\rVert_{L^2 \to L^2} = \lVert m\rVert_\infty``. So "apply ``m(k)``" is not a convenience — it is the complete representation of
    the translation commutant. The existing operators are all such multipliers: `helmholtz_projection` ([§4](@ref "4. Spectral machinery")),
    the consumer's 2/3 dealias mask, and the integrating factor ``\exp(-\nu k^2 \Delta t)`` are the **bounded** ones
    (``m \in L^\infty``); `gradient`/`curl`/`laplacian` are the **unbounded** multipliers (symbols ``\mathrm{i}k``, ``-|k|^2 \notin L^\infty``),
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
    conservation = partition of unity). The **measure-weighted L² adjoint** — ``W``, ``W^\top`` adjoint with the
    grid carrying ``\Delta x^3`` and points counting — is the **bridge from row 1 to the transfer kernel**, and is
    now **done**: both measures being uniform, it is ``(N/M) W^\top`` (a scalar rescaling, no new operation),
    verified via `inner` as ``M \mathrm{inner}(Wf, q) = N \mathrm{inner}(f, W^\top q)`` (`test/interpolation_transfer.jl`). That the
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
20. **Convolution — the kernel-multiplier family realized ([§2](@ref "2. The central principle: the architecture follows established mathematics"); the new `Convolution` module).**
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
    from the wavenumbers (invariant 12). Naming follows the [§2](@ref "2. The central principle: the architecture follows established mathematics") convention (the verb `convolve` for a
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
      band energy `= inner(u_band, u_band)` with `u_band = convolve(u, band)`, then a rescaling `convolve`
      — no scalar indexing, and the `inner(f, f)` form is allocation-free (its fused-`abs2` fast path).
    - **`radial_spectrum(f, multipliers)` (`Reductions`; introduced as `shell_spectrum`, renamed in
      decision 22)** — the **radial (shell-binned) power spectrum**: `inner` decomposed into isotropic
      ``|k|``-shells. Returns `(shells, spectrum)` with the exact refinement `sum(spectrum) == inner(f, f)`
      (same rfft half-spectrum Parseval weighting, now resolved per mode). This is the genuinely new
      reduction — spectral-representation only, like the Parseval `inner` — and the architectural framing
      is precisely *"the energy spectrum is the radially-resolved inner"* (decision 19's L²/integration
      structure, refined by the spectral radial coordinate). The consumer's energy spectrum over the
      shell wavenumber ``\kappa`` (``= |k|``) is ``E(\kappa) = \tfrac{1}{2} \mathrm{spectrum}``; the
      neutral noun keeps physics out (invariant 12). Shells run to the corner wavenumber so the
      refinement is exact; on a de-aliased field the high-``|k|`` shells are empty.

    *Device-clean by construction.* `squared_wavenumber_field` / `spectral_band` are broadcast kernel
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
    the two representations. `radial_spectrum` (decision 21, introduced as `shell_spectrum`) is the
    spectral half; this entry designs the physical half and the point application, and fixes the
    terminology so the family is coherent.

    *Terminology (decided; the rename is **done**).* `shell_spectrum` is renamed **`radial_spectrum`**,
    and the physical dual **`radial_correlation`** is added (Phase 1, **done**). "Radial" is the
    isotropic-average qualifier common to both spaces — and to the *radial* distribution function of point
    statistics; "shell" named the binning implementation and does not pair with the physical-space
    correlation. The two are the **radial reductions**: a Fourier-dual pair in `Reductions`, each mapping
    a field to a 1-D radial profile, named by the quantity's noun per [§2](@ref "2. The central principle: the architecture follows established mathematics") (`spectrum` / `correlation`)
    under the `radial` qualifier. `radial_spectrum`'s math is unchanged (`sum == inner`). Physics names
    stay consumer-side: the energy spectrum ``E(k) = \tfrac{1}{2} \mathrm{radial\_spectrum}``, the integral/Taylor scales from
    `radial_correlation`, the RDF `g(r)` from `radial_correlation` of a density field. (The rename was
    safe — the API is not frozen and `shell_spectrum` had shipped the same day with no external users.)

    *The physical dual — `radial_correlation` (done).* ``C(r)`` = radially-averaged ``\langle f(x) \cdot f(x+r)\rangle``
    (full fiber contraction — the trace of the correlation tensor, mirroring `inner`) ``= \mathcal F^{-1}(|\hat f|^2)/N``
    binned over minimum-image ``|r|`` shells. ``C(0) = \langle |f|^2\rangle = \mathrm{inner}(f, f)`` (the
    variance); for a zero-mean field ``C(r) \to 0`` at large ``r``. **The open design point was resolved
    as the user chose:** `radial_correlation(f, plans)` takes the field in spectral representation **plus
    its transform plans** (symmetric with how the differential operators take `multipliers`) — `Reductions`
    imports `to_physical` from `Fields` to do the one inverse rfft, then bins with the same scatter-add
    machinery as `radial_spectrum` (the single-pass shell histogram; decision 25), in ``r`` instead of ``|k|``. Verified against an independent
    binned-circshift autocorrelation (CPU `test/reductions.jl`, GPU `test/gpu/suite.jl`) and `C(0) = inner`.

    *The two-field co-spectra — `radial_spectrum(f, g)` / `radial_correlation(f, g)` (done).* The mixed
    second-order statistics of two compatible, equal-order fields, refining the **mixed** `inner(f, g)` exactly as
    the single-field forms refine `inner(f, f)`. The **co-spectrum** bins the Parseval-weighted cross-power
    density ``\sum_c \mathrm{Re}(\hat f_c \overline{\hat g_c})`` (``c`` indexing the fiber components) over ``|k|``-shells (``\sum_\kappa P_{fg} = \mathrm{inner}(f, g)``);
    the **cross-correlation** ``C_{fg}(r) = \langle f(x)\cdot g(x+r)\rangle = \mathcal F^{-1}(\overline{\hat f} \hat g)/N``
    binned over ``|r|``-shells (``C_{fg}(0) = \mathrm{inner}(f, g)``). Two properties fall out of the math and are
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
    giving zero, and ``\cos x \pm \cos 2x`` giving ``\pm\tfrac{1}{2}`` in adjacent shells that cancel to ``\mathrm{inner} = 0``;
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
    (e.g. shear flow), per the [§2](@ref "2. The central principle: the architecture follows established mathematics") rule against speculative structure.
23. **Spectral-domain transfer — `DirectDFT` (exact) and the native `NUFFT` (fast). [Both DONE.]**

    *The object.* The transfer layer ([§10](@ref "10. Interpolation and anterpolation (the grid↔point transfer layer)")) had one scheme family — the physical-domain local splines.
    This adds the **spectral-domain** transfer: evaluation/deposition between Fourier coefficients and
    scattered points, the exact off-grid form of the field. Both families are unified under a new
    supertype `AbstractTransferScheme`, sharing the `interpolate`/`anterpolate` verbs and the L²-adjoint
    contract; a scheme is a choice of *(kernel, representation)*. The spectral schemes dispatch on a
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
    and the shape parameter ``\beta`` follow the Barnett–Magland–af Klinteberg ES rule for the tolerance.
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
    an RX 6700 XT). Guarded by `test/allocations.jl` (every in-place spectral operator, transform,
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
    `snap_stride` steps in a solver), and the old form was itself ``O(\text{shells}\times N^3)`` work; a
    privatized/shared-memory histogram is a possible future optimization, unneeded now.

    Correctness is unchanged (the scatter sums the same per-shell quantities as the masked reductions): CPU
    `test/reductions.jl` (the analytic ``\langle\sin^2\rangle`` and independent binned-circshift oracles,
    both element types) and GPU parity `test/gpu/suite.jl` (`allowscalar(false)` — the scatter is
    device-clean, no scalar indexing) both hold. End to end, the ``256^3`` Float32 forced-HIT example
    on a 12 GB RX 6700 XT (``\approx 87`` ms/step) now runs to completion at a flat ``\sim\!6`` GB
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
    report ``\sim 0`` and miss the leak. The operator code is generic over the array type, so a CPU
    materialization *is* a GPU one — the CPU is simply where it is visible. The contract binds new code: a
    new in-place operator (or any function documented allocation-free) must be added to the audit
    (invariant 13; the §4 coverage contract in `docs/TESTING.md`).

    *Documented exceptions — bounded, not zero.* A few operations materialize one field *by design* and are
    excluded from the zero assertion, getting a *bounded* guard instead (catching a regression to ``O(N)`` —
    or ``O(\text{shells})`` — extra while allowing the legitimate one-field temporary): the fiber
    `norm!`/`lpnorm` (a pointwise magnitude), `dev!` (the trace it subtracts), `std`/`var` (deviations), and
    the radial diagnostics (occasional, ``O(1)``-bounded). The spectral `inner` is the subtle case (``N``
    the points per axis): `inner(f, f)` — an energy or `l2norm` — is allocation-free, since
    ``\overline{\hat f} \hat f = |\hat f|^2`` is real and the whole Parseval sum, correction planes
    included, is a fused `sum(abs2, …)`; but the mixed `inner(f, g)` of two distinct fields allocates an
    ``O(N^2)`` kₓ-plane correction, because a `dot` over the strided plane view (which would fuse, no
    temporary) is unsupported on the GPU (rocBLAS `dotc` has no strided method — verified on the device).
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
      package already carried; the gap was the missing invariant, not a completeness fill. Being cubic
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
      \overline{\hat g_c})`` (with ``\alpha(k)`` the rfft half-spectrum Parseval weight, ``N`` the grid-point
      count, and ``c`` the fiber index) — the field ``g`` filtered by ``w`` and paired with ``f`` in one
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

    *Scope and verification.* The public method set grows to **206** field methods (`combine!` adds 2,
    `det`/`det!` 1 each) and **122** point-value methods (`det`/`det!` 1 each); `symmetric_gradient` and
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
    derivative multiplier is zeroed there. `translation_kernel` is the first operation to use **both**
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

    *Both representations, host and device.* A physical field stores a real array; a field in spectral
    representation stores its complex half-spectrum (HDF5 round-trips complex arrays). Device (GPU) arrays
    are copied to the host on write via `Array(…)` — backend-agnostic, a no-op on the CPU — and the reload is
    a host field the consumer moves to a device if wanted. On read, `read_field` dispatches on the stored
    `type` tag and reconstructs through the public constructor: the element type follows the stored array (real or
    complex), the tensor order follows its dimensionality, and the grid spacing is recomputed bit-for-bit, so
    the reload is **exact**. The sugar `parent[name] = field` is `setindex!` for `write_field`, made strictly
    more specific than HDF5's own array-writing `setindex!` so it never clashes.


30. **Mapped reductions — a leading function on every measure reduction.** The consumer
    `GBGIsotropicTurbulence` audited its memory and found a recurring shape: to average a nonlinear
    invariant of a tensor field — the determinant of a strain tensor, the magnitude of a velocity — it had
    to build that invariant as a **whole section** first and then reduce it, paying one field of scratch
    for a single number. Here a *section* is a field or a set of point-values, and its **fiber value** at a
    base point is the scalar, vector, or ``3 \times 3`` tensor sitting over that point. So each reduction
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
    tensor-order restriction. They also give a fused peer to `lpnorm(u, Inf)`, which computes the same
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

    *Scope.* Every field type (the six: scalar / vector / tensor × physical / spectral); no compression or
    chunking options until a consumer needs them; no snapshot / time type (invariant 12).

    *Verification.* The round-trip test `test/hdf5.jl` covers every field type over both element types,
    asserting the data (real and complex), the full `Grid3D` geometry, the element type, the tensor order,
    and the layout are recovered bit-for-bit; it exercises the `setindex!` sugar, a snapshot bundle carrying consumer-owned
    `time` / `iteration` attributes, the self-describing attributes read back as plain HDF5, and the error
    paths (a dataset instead of a group, an absent name, a group with no type tag). The method-set baselines
    (206 field / 122 point-value methods) are untouched — `write_field` / `read_field` are new generics, and
    their methods exist only under the extension.


31. **The Julia compat floor moved 1.11 → 1.12, on a measurement rather than a preference.** The package
    declared `julia = "1.11"`, and CI ran that as an explicit compat-floor lane beside current stable. The
    floor is now 1.12, so the matrix differs only in thread count (`-t1` against `-t4`) and the local
    pre-commit run is a single lane.

    *What the measurement showed, which is the opposite of the obvious guess.* On 1.11 the package **runs
    faster** — every operation measured, on a ``64^3`` grid in `Float64`: `mean(det, A)` 0.241 ms against
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
    serves is mask-dealiasing: every dealiased right-hand side in a pseudospectral solver is the
    operator followed immediately by `convolve!` with the dealias kernel, so fusing saves that pass's
    full read and write of the destination (two passes of the field's class per evaluation). **The
    `α`/`β` pair is load-bearing, not completeness**: the fused form *replaces* a `convolve!` that
    carries `α`/`β` — IT already rides the ``-\nabla\cdot`` sign of its scalar advection on
    `convolve!`'s `α` — so shipping less would strand the very chains being fused; and `β` collapses
    IT's phase-shift dealiasing tail entirely, as two projection calls — the primary with the dealias
    kernel at ``\alpha = 1/2``, the displaced evaluation with the **composed** kernel (dealias ∘
    shift-back, built once at setup by the kernel composition `convolve(g₁, g₂)`) at
    ``\alpha = 1/2``, ``\beta = 1`` — eliminating
    the standalone shift-back, average, and truncation passes (four passes per evaluation at wiring
    time; two more were already banked consumer-side by rewriting the average as `convolve!`'s
    five-argument form). `curl!` deliberately does **not** get the kernel arity: IT's curls feed
    transforms directly, so there is no consumer — the absence is the invariant-1 discipline, recorded
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
    The kernel is never built, so against the stored-kernel route (`squared_wavenumber_field` →
    consumer broadcast → `convolve!`) it removes the kernel's residency, its build pass, and its full
    field read per application, reading ``O(N)`` wavenumber rows instead (``N`` the points per axis).
    The measured trade is a **reuse question** ([`PERFORMANCE.md`](performance.md) finding (k)): with a
    varying exponent — the consumer's case, whose stage substeps differ — the lazy form beats
    rebuild-then-apply by ``\approx 1.4\times`` on the GPU; with one fixed kernel applied many times
    the stored route keeps a ``\approx 1.1\times`` (GPU) to ``\approx 2\times`` (CPU) edge, the
    per-mode exponential costing more than the field read it saves. The two-operand fused forms below
    win on both backends regardless (``\approx 1.4``–``1.7\times``).
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
    ``b === \mathrm{dest}`` the method computes the kernel-filtered accumulate in place
    (coefficientwise, hence alias-safe with no guard), which is why it carries **no** second trailing
    accumulate pair — two ``\alpha``/``\beta`` roles in one signature is the glyph-collision failure
    mode, and the aliasing provides the accumulate for free.

    *Naming and the method-set bookkeeping.* The kerneled combination is a **method of `combine!`
    with a trailing kernel argument** — the decision-32 composition idiom (`divergence!` and
    `helmholtz_projection!` compose the same way) — not a new verb; the earlier `weighted_inner`
    naming (decision 27) is the *reductions* family's convention and stands there. The method is
    defined in `Convolution` (the kernel is a `Convolution` concept; `FieldAlgebra` precedes it in
    the include order and never sees kernels), which also keeps the `FieldAlgebra` method-parity
    baseline untouched by construction — the parity count filters on the defining module. Validity:
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
    consumed them (measured 1.6 of IT's units at ``256^3``, reproduced here; the cross-power form
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
    and the banned field product are indistinguishable at the type level. The broadcast layer is
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
    is the trigger to generalize); and a stdlib-shaped physical `map!(φ, dest, sections...)`, the
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

    *Method — measured, not transcribed.* IT's compute audit (its decision 34) freezes an
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
    wrapped, IT's own scope line).

    *What the first measurement found.* The decision-32/33/34 kernels sit **at their ideals** — the
    one-pass projection reads 3 and writes 3 (the audit would have failed the old 9), its `β = 0`
    forms provably never read the destination, the KA kernel reads a composed `ĝ` once per mode
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
    scalar field in either representation as ``8 N^3`` bytes in `Float64` (the physical array and the
    rfft half-spectrum agree to within a part in ``N``) and a solver's live set at order 25 fields, one
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
    element count alone, its top ``\lceil \log_2 \mathrm{nthreads} \rceil + 1`` levels evaluated as
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
    radial binning. The exemption is now a principle, not a history.
