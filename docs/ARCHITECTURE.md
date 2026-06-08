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
Lagrangian particle interpolation is a planned later layer. The same code must run
on CPU `Array`s and on GPU arrays (CUDA `CuArray`, AMDGPU `ROCArray`); development
prioritizes GPU correctness and performance first.

## 2. The central principle: representation validity lives in the method set

A field is one physical object; physical and spectral storage are two
representations of it. An operation is offered in a representation only when it is
mathematically the same operation on the underlying physical object there:

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
parity-checked at runtime in `test/method_parity.jl`.

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

## 9. Performance model and the deferred CPU-threading design

Elementwise field operations are memory-bandwidth-bound streaming; FFTs dominate
asymptotically but only once FFTW is actually threaded — and FFTW threading is
baked in at **plan time**, so `FFTW.set_num_threads(Threads.nthreads())` must run
before `FieldTransformPlans` constructs plans. On GPU, broadcasting already
launches parallel kernels; there is nothing to add. On CPU, Base broadcasting is
single-threaded, and the agreed (deferred) design is:

- One internal primitive `_assign!(destination, bc::Broadcast.Broadcasted)` in
  Fields. Generic fallback = `Broadcast.materialize!` (the safe polarity: GPU and
  unknown wrappers keep standard fused broadcast); the specialization for
  `Union{Array, SubArray{…,<:Array}}` threads a *single* instantiated/preprocessed
  `Broadcasted` tree over chunked indices — fusion preserved, one pass over
  memory — with a serial cutoff (~2^14 elements) that automatically exempts the
  one-element zero-mode views.
- Plug points: the field broadcast style's `copyto!` (threads all whole-field
  operations with zero FieldAlgebra changes) and the kernel-body builders emitting
  `_assign!(target, Broadcast.broadcasted(...))` instead of `target .= formula`
  (three or four builder functions; every generated kernel inherits it), plus
  one-line edits in the few explicit kernels.
- Deferral is safe: threaded non-reducing maps are bitwise identical to serial,
  the GPU path is untouched by construction, and no types, signatures, or tables
  change. The interim discipline is to keep elementwise writes flowing through
  field-level broadcasts or named kernels — no ad-hoc raw-array `.=` scattered in
  new code — so the eventual edit stays mechanical.
- Reductions (global norms, energy integrals) are a separate, later concern:
  chunk-partial accumulation, with the usual floating-point ordering caveat.
- Expectations: speedup saturates at socket bandwidth over single-core bandwidth
  (typically 2–6×; more on multi-socket nodes, where thread pinning and NUMA
  first-touch matter — ThreadPinning.jl).

## 10. Decision log

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
