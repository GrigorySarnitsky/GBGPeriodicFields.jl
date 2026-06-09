# GBGPeriodicFields — Architecture and Rationale

This document records the architecture of the package and, more importantly, *why*
it is the way it is. It exists so that future work (human or AI) extends the design
instead of accidentally reverting it. `CLAUDE.md` carries the operational summary;
this file carries the reasoning. The AI-tips block in `src/GBGPeriodicFields.jl`
carries the conceptual model and writing conventions.

## 1. Purpose and scope

The package is the field layer for pseudospectral simulation of incompressible
fluid dynamics and turbulence on three-dimensional rectangular periodic domains. It
provides scalar, vector, and second-order tensor fields with two storage
representations — physical space and real-to-complex (rfft) spectral space — plus
FFT transform plans, spectral multipliers, storage-wise broadcasting, fiberwise
algebra (FieldAlgebra), and spectral differential operators (DifferentialOperators).
Interpolation and its adjoint anterpolation — the grid↔point transfer layer that
serves consumer-side Lagrangian particle tracking — are partly in place (§10): the
point-value sections and their algebra exist; the transfer kernels are planned. The
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
3-torus) with a single global frame, so the bundle is trivial — just `E = B × V`
for a base `B` and a fiber `V`. The fiber is the tensor order, a tensor power of
`ℝ³`: `V = ℝ` (scalar), `ℝ³` (vector, `FiberVector`), `ℝ³ ⊗ ℝ³ = ℝ³ˣ³`
(second-order tensor, `FiberTensor2`), and higher (`FiberTensor3/4`). A section
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
  shared `AbstractFiberSection{T, R}` supertype spanning both, in a planned
  `FiberSections` module (§10).
- **Differential operators are the complementary horizontal structure** — gradient,
  divergence, curl, Laplacian are derivatives *along the base*, using the flat
  connection of the periodic box (§4). They are bound to a base with a differentiable
  structure: they act on grid sections (in the spectral representation) and not on
  point-value sections, which carry the vertical algebra but no derivatives.
- **Representation is a choice of basis for a grid section's data** (distinct from the
  fiber frame above): physical storage uses the nodal basis, spectral storage the Fourier
  basis, and the rfft is the linear isomorphism between them. A point-value section has no second
  representation — there is no periodic grid to transform over — so the point types
  are representation-free (§10).

(The vertical/horizontal language is the bundle-theoretic one — fiber directions versus the
connection's base directions — applied here by analogy to *operations*: the fiberwise algebra
is order-zero and fiber-preserving, the differential operators are the connection's covariant
derivative, order one. Strictly, *vertical* (`ker dπ`, canonical) and *horizontal* (a
connection-chosen complement) are subbundles of the total space's tangent bundle.)

Transfer between sections over *different* bases is the interpolation/anterpolation
pair: pulling a grid section back to points (evaluation, `f(x) = ⟨δₓ, f⟩`) and the
adjoint pushforward of point masses onto the grid. The full function–measure duality
is given in §10 and the `Interpolation` module docstring.

### Representation validity lives in the method set

The frame picture fixes exactly which operations may be offered in which
representation: an operation exists in a representation only when it is *the same
operation on the underlying section there* — equivalently, only when it commutes
with the rfft isomorphism.

- **Linear in the field** — addition/subtraction of fields, scaling by real
  numbers, contractions with *constant* fibers, transpose, sym/skew/dev: valid in
  both representations, because the Fourier transform commutes with them.
- **Adding constants** — in physical space, every grid value shifts; in spectral
  space, `F(f + c) = F(f) + c·N·δ_{k,0}` under the unnormalized-forward convention,
  so only the zero mode changes, scaled by `prod(grid_size)`. This is why
  `_spectral_constant_scale` exists and why constant kernels in spectral
  representation touch a single coefficient (per component).
- **Nonlinear in the field** — products of two fields, division by a scalar field,
  pointwise norms, contractions of two fields (dot, cross, tensor `mul!`, inner
  products): physical space only. The coefficientwise spectral product is *not* the
  Fourier representation of the pointwise product (that would be a convolution),
  so offering it would silently compute the wrong physical operation.

The consequence is a hard project invariant: **a missing method is a statement,
not an omission**. The 198-method public surface of FieldAlgebra is the
machine-checkable encoding of the validity table above. Any refactor must
reproduce the method set exactly; it was verified signature-for-signature against
the original — M2 (98 methods: `add!`/`subtract!`/`multiply!`/`divide!`/`+`/`-`/`*`/`/`)
and then M3 (the dot/cross/`mul!`/transpose/norm/sym/skew/dev contraction and
decomposition families, plus their `*` operators), bringing the total to 198 and
parity-checked at runtime in `test/method_parity.jl`. The point-value algebra
realizes the *vertical* operations on the unstructured base — it mirrors the
**physical** field surface and is locked by its own separate baseline (§10).

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
elementwise kernels, and trivially chunkable index ranges for the deferred CPU
threading. Component access goes through views
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
layout. It lives in **Fields**, as a sibling of `FieldTransformPlans`, because it
is representation infrastructure (what the spectral axes *mean*), not a
differential operator; it moved out of DifferentialOperators during the refactor.
Two constructors by design:

- An explicit constructor taking all six arrays (lengths validated). This makes
  the type testable in isolation and lets callers control the backend.
- A convenience constructor from a field: wavenumbers `2π·n/L` are built on the
  host and copied to the field's backend via `similar` + `copyto!` (no scalar
  GPU writes).

**The Nyquist split is deliberate and must not be unified.** On even-length axes:

- Derivative multipliers are **zeroed at the Nyquist frequency**. The Nyquist
  mode of a real signal is a pure cosine; multiplying by `ik_N` would produce a
  component the real signal cannot represent, and the symmetric, real-preserving
  choice for its derivative is zero. This is standard pseudospectral practice and
  keeps derivatives of real fields exactly real.
- Squared multipliers keep the **true k²** at Nyquist. The Laplacian of the
  Nyquist mode is perfectly well defined (`-k_N²·mode`); zeroing it would silently
  remove grid-scale dissipation and corrupt `inverse_laplacian`.

Reference tests pin this down: multipliers vs `fftfreq`/`rfftfreq`, transform
round-trips, and a real-field Nyquist end-to-end test (the derivative zeroed at Nyquist
vs the squared wavenumber kept) — see `docs/TESTING.md`.

## 5. Validation design

Fields owns compatibility checking, built from atomic Boolean predicates
(`_same_scalar_type`, `_same_tensor_order`, `_same_grid`, `_same_layout`) composed
into `_check_same_domain`, the representation-dispatched
`_check_field_domain_compatibility` (physical-physical and spectral-spectral
methods — the dispatch barrier that prevents cross-representation mixing), the
public `check_field_compatibility`, and `_check_field_matches_context` for
transform plans.

History: FieldAlgebra used to carry near-duplicate checkers
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

## 6. The code-generation architecture of FieldAlgebra

### Why it emerged

The original FieldAlgebra was 3033 hand-written lines defining ~198 public
methods, with per-component kernels unrolled by hand (three statements per vector
operation, nine per tensor). The regularity was overwhelming: one mathematical
operation expands into 8–32 near-identical methods (two representations × two
argument orders × in-place/allocating × vector/tensor). Hand maintenance meant
every new operation or convention change had to be edited consistently in dozens
of places — a divergence machine. The refactor regenerates the **same** method
set from small tables, so each formula and each convention is written exactly
once, while the public surface (and its deliberate absences) stays bit-identical.

### Layers

- **M1 — expression builders** (`Code generation` section of FieldAlgebra):
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
unstructured base (§10) — the formulas are base-independent (§2). They currently live
in FieldAlgebra and are imported by the point layer; Phase A moves them down into the
shared `FiberSections` module so both consumers source them from one place.

### Documentation policy

Generators emit methods only, never docstrings. Each operation has one docstring
attached to the bare binding (`function f end` for package-owned generics; the
bare imported name for Base/LinearAlgebra functions — never `function f end`
there, since a missing import would silently create a new generic). Docstrings
show a few canonical signatures plus prose about representation validity,
including which combinations are intentionally absent. Exhaustive signature lists
were dropped: they duplicated the tables and went stale instantly.

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

Fields broadcast storage-wise: a field in a broadcast stands for its data array,
and the field broadcast style (owned by Fields) materializes into field storage.
Style promotion is one-sided by design — define a single binary rule per style
pair, never symmetric mixed-representation rules. The broadcast layer doubles as
the compatibility enforcement for broadcast-mediated methods (§5).

## 9. Performance model and CPU threading

Elementwise field operations are memory-bandwidth-bound streaming; FFTs dominate
asymptotically. Both are now threaded on CPU (shared memory). On GPU, broadcasting and
the device FFT libraries already launch parallel kernels, so the CPU threading is
dispatched away (below).

**FFTs.** FFTW threading is baked in at **plan time**, so the package's `__init__` calls
`FFTW.set_num_threads(Threads.nthreads())` before any `FieldTransformPlans` is built
(`set_fft_threads!` retunes it). Oversubscription caveat: FFTW's pthreads multiply with
Julia's tasks — code that parallelizes *across* fields and transforms inside each task
should build plans under `set_fft_threads!(1)`. The common case (one field, transforms
serial in a time loop) wants `nthreads()` FFTW threads, the default.

**Elementwise/fiberwise ops.** One internal primitive `_assign!(destination, bc)` in
Fields. The generic method is `Broadcast.materialize!` — the safe polarity: GPU and unknown
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
FieldAlgebra / DifferentialOperators kernels use the `@_assign!` macro in place of `.=`. No
types, signatures, or method tables change — the 198-method surface and the zero-ambiguity
property are preserved. **Discipline:** a raw elementwise write must go through
`_assign!`/`@_assign!`, never a bare `.=`, or it silently runs single-threaded.

Reductions (global norms, energy integrals) remain a separate, later concern: chunk-partial
accumulation reorders floating-point adds, so they need their own design and a
tolerance-based test, not the bitwise one used here. Expectations: speedup saturates at
socket bandwidth over single-core (typically 2–6×; more on multi-socket nodes, where thread
pinning and NUMA first-touch matter — ThreadPinning.jl — a consumer concern, since the
package allocates serially via `similar`).

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
  allocating / in-place (`!`) pair and a five-argument `α`/`β` form (`β = 0` overwrite,
  `β ≠ 0` accumulate — the `mul!` convention, since they are the linear maps `W` / `Wᵀ`;
  accumulation is the common case for the scatter). `interpolate` / `anterpolate!` are the
  symmetric named pair — only interpolation also gets the callable `f(x)`, because evaluation
  is pointwise while its adjoint is not (see the module docstring). The driving case is
  two-way coupling in the cloud-parcel DNS this package serves — the water-vapour mass and
  latent heat a droplet releases on condensation (or absorbs on evaporation) must be returned
  to the supersaturation and temperature fields.

**Why the code says "anterpolation."** The point→grid (scatter) operation is named
differently in every community, with no dominant choice: *spreading* (immersed-boundary
method, where it is explicitly the adjoint `S = J*` of interpolation, built from the
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
share the **same stencil weights**, which form a partition of unity (`Σ β = 1`);
anterpolation is then the exact transpose of interpolation, and the total deposited
quantity is conserved: `1ᵀ(Wᵀq) = (W1)ᵀq = 1ᵀq`. Using mismatched weights injects a
spurious source/dissipation term (Sundaram & Collins 1996). For the parcel application
this is mandatory — total water and latent heat must be conserved as vapour passes
between droplets and the fields — so the design fixes anterpolation as the transpose of
whatever interpolation kernel is in use. The function–measure duality underlying this
adjointness — evaluation as pairing with a Dirac mass, `f(x) = ⟨δₓ, f⟩`, and anterpolation
as the pushforward of point masses, `𝓘*q = Σₚ qₚ δ_xₚ` (regularized to `Σₚ qₚ β(·−xₚ)`,
i.e. a regularized point source) — is given in full in the `Interpolation` module docstring.

**Method: the Lalescu local splines.** The package will use the local high-order spline
interpolation of **Lalescu, Teaca & Carati (2010)**, as implemented in the **TurTLE**
code (Lalescu, Bramas, Rampp & Wilczek 2022). At its core it is Hermite interpolation
with the node derivatives supplied by finite differences, which makes the interpolant
simultaneously local, high-order, and smooth; in the cubic four-point case it reduces to
the Catmull–Rom spline (Catmull & Rom 1974). Concretely `f(x)` is a tensor-product
weighted sum `Σ βᵢ₁ βᵢ₂ βᵢ₃ f(c+i)` over a compact `(2n+2)³` stencil, with closed-form
polynomial weights `β` parameterized by two integers: a neighbourhood `n` (kernel size
`2n+2`) and a smoothness `m` (the count of continuous derivatives); `m = 0` recovers
plain Lagrange interpolation. Field derivatives needed for the velocity gradient /
deformation tensor are obtained by differentiating the same local polynomial, not from a
separate field. Three properties make it the right fit:

1. **Single representation, no global precompute.** The weights act directly on the
   real-space nodal values, so interpolation reads only the physical representation. (The
   B-spline interpolation of van Hinsberg et al. 2012 — whose coefficients require a
   *global* transform that, in a spectral code, costs one FFT — is the higher-accuracy
   alternative kept in reserve; exact spectral interpolation via a type-2 NUFFT is the
   global, divergence-free extreme, planned only as a high-accuracy reference oracle.)
2. **GPU-friendly** (the GPU-first invariant, §1): per-point interpolation is a gather
   of `(2n+2)³` neighbours plus a fused multiply–add — embarrassingly parallel, no FFT, no
   global solve, no communication beyond the periodic stencil wrap. Anterpolation is the
   matching scatter.
3. **Trivial, conservative anterpolation:** the same closed-form `β` deposit a point's
   source over its stencil with `Σ β = 1` — exactly the conserving two-way-coupling
   feedback the parcel DNS needs.

The interpolation order is a tunable parameter `(n, m)`, not hard-wired, so accuracy can
be matched to the spectral resolution (standard practice for pseudospectral particle
tracking). **The transfer kernels are not yet implemented; this paragraph records the
design decision so implementation begins from it** — the point-value data types and their
algebra (below) *are* implemented.

**Data types — the unstructured base, in the package's own language.** Interpolation needs
to name two new objects: off-grid locations and the field values there. The package names
them in its base/fiber vocabulary, *not* as particles — deliberately, because
GBGPeriodicFields is a **math backend** (§1): "particle"/"tracer" is the consumer's
interpretation (a location with physical attributes and an equation of motion), not a
primitive here. The organizing principle reuses the existing base/fiber split: a field is a
*section* — fibers (`scalar`/`FiberVector`/`FiberTensor2`) over a *base* — and so far the
base has always been the structured `Grid3D`. Interpolation adds the **unstructured base**
and its section, reusing the *same* fibers; `𝓘` / `𝓘*` are the maps between sections over the
two bases.

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
order (a `_check_…` predicate in the Fields style). The types live in the `Interpolation`
module, importing Fields helpers via an explicit `using ..Fields: …`.

**Implemented status.** The point types and their **full fiberwise algebra** are implemented
and tested; only the transfer kernels (interpolation / anterpolation, above) remain future
work. The algebra mirrors the *physical* field surface — the base-independent vertical
operations of §2 (M2 vector-space and scalar-field products; M3 dot/cross/`mul!`/transpose/
norm/sym/skew/dev), with storage-wise broadcasting — and is generated by **reusing
FieldAlgebra's per-component formula and kernel-body builders verbatim** (§6) over an extended
section interface (`field_data` / `_vector_component_data` / `_tensor2_component_data`, which
`Interpolation` extends for the point types), so no formula is written twice. It is locked by
a separate **118-method point-value parity baseline** (the 198-method field surface is
byte-unchanged), has zero ambiguities, and is covered on CPU (`test/pointvalues_algebra.jl`,
Float64/Float32) and on the GPU (the ROCm suite under `allowscalar(false)`).

**Planned consolidation — the module structure the model implies.** Fields and point-values
today share the generated kernels but not a supertype, and the point objects, their algebra, and
the (future) transfer all sit in one `Interpolation` module. The fiber-bundle model (§2) implies
a cleaner layout, planned for the next refactor:

- a new foundation module **`FiberSections`** holds the base-agnostic core —
  `AbstractFiberSection{T, R}`, the section interface (the component accessors), the `_assign!`
  primitive, and the vertical-algebra **code generators**: the single home where each fiberwise
  formula is written once, including the norm/sym/skew/dev formulas presently *replicated* in the
  point layer rather than sourced from a builder;
- the current `Interpolation` module **splits in two**: **`Points`** holds the unstructured-base
  section *objects* (`PointSet`, `*PointValues`) and their generated algebra — a noun-named peer
  of `Fields`; **`Interpolation`** keeps only the transfer maps (`interpolate`/`anterpolate`) — an
  operation-named peer of `DifferentialOperators`.

The remaining field/point asymmetry is deliberate and **mandated by the mathematics**, not
inertia: points have no differential operators (no horizontal structure, §2) and no second
representation, so there is no point peer to `DifferentialOperators` and no representation
machinery in `Points`; and the point algebra is a small *generated* emission that folds into
`Points` rather than earning a separate `FieldAlgebra`-sized module (whose bulk is the 198
hand-curated methods plus the representation-specific irregular corners — the spectral zero-mode
updates, the `multiply!` quartet). What the split *fixes* is the naming: section *objects* live
in noun-named modules (`Fields`, `Points`), operations in operation-named ones (`FieldAlgebra`,
`DifferentialOperators`, `Interpolation`). This refactor is planned and not yet undertaken; it
must reproduce both parity baselines (198 field + 118 point) byte-for-byte, with zero
ambiguities.

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

1. Fields refactor: atomic compatibility predicates; shared
   `_check_same_domain`; `_check_field_matches_context` for transforms.
2. `FieldSpectralMultipliers` moved DifferentialOperators → Fields; explicit
   six-array constructor (validated lengths) plus convenience constructor;
   host-built wavenumbers copied to the backend; **Nyquist split** between
   derivative and squared multipliers (correctness, see §4).
3. FieldAlgebra rewritten around code generation with the invariant that the
   public method set is reproduced exactly; M2 + M3 delivered and parity-verified
   at runtime (198 methods, the full surface). Validation rewired to direct
   `_check_field_domain_compatibility` calls — alias wrappers explicitly
   rejected.
4. Docstring policy: one docstring per operation on the bare binding, curated
   signatures + validity prose; generators never emit docstrings.
5. Operators defined in `function op(...) ... end` form (parse-proven house
   style); short form only for unary `+`.
6. GPU-first; CPU threading designed (`_assign!`, §9) and deliberately deferred.
7. Refactor complete: FieldAlgebra loads and is parity-verified (M2 + M3, 198
   methods); DifferentialOperators rewired to import `FieldSpectralMultipliers`
   and its helpers from Fields, with the umbrella re-export corrected (the old
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
    (`Float32` alongside `Float64`), anisotropic-domain operators (the `2π/L` scaling),
    in-place and alias-guard coverage, a Nyquist end-to-end test, and the operator
    **adjointness / structural identities** on randomized band-limited fields
    (`div = -gradᵀ`, self-adjoint curl, negative-definite Laplacian, idempotent Helmholtz
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
    α/β-accumulate forms (the `mul!` convention, since they are the linear maps `W` / `Wᵀ`);
    only interpolation also has the pointwise callable `f(x)` (the adjoint of interpolation;
    synonyms — spreading,
    deposition, scatter, projection/PSI-Cell, gridding, two-way-coupling feedback — listed
    on the binding; "extrapolation" rejected as a misnomer). Adjointness is explained in
    the module docstring via the function–measure duality (Dirac evaluation vs. pushforward
    of point masses). Method:
    the **Lalescu local splines** (Lalescu, Teaca & Carati 2010) as in **TurTLE**
    (Lalescu, Bramas, Rampp & Wilczek 2022) — local Hermite-with-finite-difference
    derivatives, tunable `(neighbours n, smoothness m)`, single (physical)
    representation, GPU-friendly; van Hinsberg B-spline (2012) and NUFFT exact-spectral
    are the higher-accuracy / reference alternatives held in reserve. Interpolation and
    anterpolation share the same partition-of-unity weights, so anterpolation is the
    conservative transpose (Sundaram & Collins 1996) — required to conserve total water
    and latent heat in the two-way-coupled parcel DNS. Not yet implemented.
14. Point-data types fixed (§10) and the math-backend policy recorded. The unstructured base
    reuses the base/fiber split: `Point{T} = SVector{3,T}` (a position; an **alias** of
    `FiberVector`, not a wrapper); `PointSet` (`M` positions, **SoA** `(M,3)`, grid-free);
    and `PointValues` as **three concrete types** mirroring the field zoo —
    `ScalarPointValues` / `VectorPointValues` / `TensorPointValues{R}` under
    `AbstractPointValues`, SoA, **representation-free**. Naming is domain-neutral by policy:
    the package is a math backend, so no *particle* / *tracer* type and **no concept of time**
    (no advection / integration / temporal state) — those are the consumer's. The types live in
    `Interpolation`, importing Fields helpers; they are implemented and tested (only the
    transfer kernels of item 13 remain future work — see item 15 for the algebra).
15. Point-value algebra implemented (§10): FieldAlgebra's code generators are **reused
    verbatim** over an extended point-value section interface, mirroring the full *physical*
    field surface (M2 + M3, storage-wise broadcasting) with no duplicated formula; locked by a
    separate **118-method baseline** (the 198-method field surface byte-unchanged), zero
    ambiguities, tested on CPU (`test/pointvalues_algebra.jl`) and GPU (ROCm). The shared
    `AbstractFiberSection{T, R}` supertype the fiber-bundle model (§2) invites — and the lift of
    the inlined norm/sym/skew/dev formulas into a builder — is the planned next step, not yet
    undertaken.
16. Phase A module structure fixed (planned; §2, §10). The fiber-bundle model is realized in
    modules by (a) a new foundation module **`FiberSections`** — the base-agnostic core:
    `AbstractFiberSection{T,R}`, the section interface, the `_assign!` primitive, and the
    vertical-algebra code generators (the single home for every fiberwise formula, including the
    replicated norm/sym/skew/dev); and (b) splitting the current `Interpolation` into **`Points`**
    (unstructured-base section objects + their generated algebra — a noun peer of `Fields`) and
    **`Interpolation`** (the transfer maps only — an operation peer of `DifferentialOperators`).
    The remaining field/point asymmetry is math-mandated: no point differential operators and no
    second representation, and the point algebra is a small generated emission that folds into
    `Points` rather than earning a `FieldAlgebra`-sized module. The naming is what gets fixed:
    objects in noun modules (`Fields`, `Points`), operations in operation modules. Must reproduce
    both parity baselines (198 + 118) byte-for-byte; not yet undertaken.
