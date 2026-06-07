# CLAUDE.md — GBGPeriodicFields

Julia package: real-valued scalar/vector/second-order-tensor fields on 3D rectangular
periodic domains, with physical-space and real-to-complex (rfft) spectral
representations, on CPU (`Array`) and GPU (`CuArray`, `ROCArray`). Built as the field
layer for pseudospectral fluid/turbulence solvers; Lagrangian particle interpolation
is a later target. Development is **GPU-first**; CPU multithreading is deliberately
deferred (design recorded — see below).

Before any structural or design change, read `docs/ARCHITECTURE.md`. It explains why
the architecture is the way it is; do not re-litigate recorded decisions without the
user. The umbrella module `src/GBGPeriodicFields.jl` carries an AI-tips comment block
with the conceptual model and docstring conventions — follow it, keep it
single-source, and keep it updated when new project rules are established.

## Modules and wiring

- `src/Fields.jl` — types (`Grid3D`, `RealFourierLayout`, field types; `FiberVector{T} = SVector{3,T}`, `FiberTensor2{T} = SMatrix{3,3,T,9}`, plus `FiberTensor3/4`), memory layout, broadcast style, compatibility checks, `FieldTransformPlans`, `FieldSpectralMultipliers`.
- `src/FieldAlgebra.jl` — fiberwise/pointwise algebra; method families emitted by code generators.
- `src/DifferentialOperators.jl` — spectral operators (`gradient`, `divergence`, `curl`, `laplacian`, `inverse_laplacian`, `helmholtz_projection`, in-place variants). **Mid-refactor**: still contains the old `FieldSpectralMultipliers` (it moved to Fields), and the umbrella re-exports it from the wrong module. Fix per roadmap.
- Include order: Fields → FieldAlgebra → DifferentialOperators. Cross-module access only through explicit `using ..Fields: name, ...` lists — never a bare `using ..Fields`.

## Core invariants — do not violate

1. **The public method set is the spec.** Deliberate absences encode representation
   validity: no spectral field×field products, no spectral division by a scalar
   field, no spectral pointwise norms. Operations linear in the field (constants,
   fiber-constant contractions, transposes, sym/skew/dev) exist in both
   representations; nonlinear-in-field operations are physical-space only. Never add
   a missing combination "for completeness". After any codegen change, verify the
   method set is unchanged (workflow below).
2. Fields are real physical objects; physical/spectral are *representations* of the
   same object. Complex arrays are storage detail, never user-facing. Say "field in
   spectral representation", not "spectral field".
3. Fiber-last data layout: `(Nx, Ny, Nz[, 3[, 3]])`. Component slices are contiguous;
   the layout is relied on by FFT batching and future threading. Do not change it.
4. AbstractFFTs normalization: forward unnormalized, inverse normalized. Adding a
   physical constant in spectral representation updates **only the zero Fourier
   mode**, scaled by `prod(grid_size)` (`_spectral_constant_scale`). Never touch all
   coefficients.
5. Nyquist handling differs by multiplier on purpose: derivative wavenumbers are
   zeroed at the Nyquist frequency on even-length axes (keeps derivatives of real
   fields real); squared wavenumbers keep the true k² there (correct
   Laplacian/inverse Laplacian). Do not "unify" them.
6. GPU portability: storage is generic `AbstractArray`; no scalar indexing of GPU
   arrays in package methods; allocate with `similar(field_data(reference), ...)` /
   `similar_field`; prefer fused broadcasted assignments.
7. No type piracy. Import before extending: `import Base: +, -, *, /`,
   `import LinearAlgebra: dot, ⋅, cross, ×, mul!, transpose!, norm`.
8. No fiber-fiber methods (e.g. `dot(::FiberVector, ::FiberVector)`) — the fiber
   types are StaticArrays aliases and already have them.
9. Aliasing: in-place ops whose destination may alias an input go through
   `_guard_noalias!`; `mul!` is exempt and instead documents that destination must
   not alias (LinearAlgebra convention).
10. α/β kernels: five-argument forms convert `T(α)`, `T(β)` and branch on
    `iszero(β_value)` (overwrite vs accumulate); three-argument forms delegate with
    `one(T)`, `zero(T)`.

## Code generation rules (FieldAlgebra)

- Per-component formulas are written **once**; `@eval` tables stamp out
  representation, argument-order, and in-place/allocating variants. Builders:
  `_vector_component`/`_tensor_component` (kinds `:field`/`:fiber`), `_sum_terms`,
  `_product`, `_vector_kernel_body`/`_tensor_kernel_body` (with `alpha_beta` flag),
  `_scalar_kernel_body`, `_guard_noalias!`.
- Generators emit **methods only — never docstrings**. One docstring per operation,
  on the bare binding: `function f end` for package-owned generics, the bare imported
  name for Base/LinearAlgebra functions. Docstrings list a few canonical signatures
  plus validity prose, and mention intentional absences.
- Irregular corners stay explicit **with a comment saying why** (scalar±Real family,
  the four ambiguity-resolving `multiply!` methods, physical-only divisions).
- Validation: call `Fields._check_field_domain_compatibility` (imported explicitly)
  **directly** — no aliases or wrapper names. Placement rule: broadcast-mediated
  bodies do not pre-check (the broadcast machinery enforces compatibility); paths
  that bypass broadcasting (copy + kernel, zero-mode updates) check explicitly.
- Operators are defined in `function +(...) ... end` form (the parse-proven house
  style); short form only for `+(field::AbstractField) = field`.

## Style

Two-space indentation; two blank lines between top-level definitions; section banner
comments; descriptive names without abbreviations; moderately long lines are fine.
When unsure about Base/stdlib/package behavior, check official docs — don't guess.

## Verification workflow

"Should work" is not done. Minimum bar for any change:

- Load: `julia --project -e 'using GBGPeriodicFields'` (catches `@eval` and wiring errors).
- Method parity after codegen edits: compare per-generic `methods(f)` counts
  against the committed baseline (`test/method_parity.jl`). Full M2+M3 surface is
  **198 public methods** (e.g. `*` 28, `mul!` 30, `dot`/`dot!` 10 each, `add!` 14).
- Ambiguities: run Aqua.jl `detect_ambiguities` — the explicit `multiply!` quartet
  exists precisely to resolve these.
- `julia --project -e 'using Pkg; Pkg.test()'` (the `test/` suite now exists; keep it green).
- Consult `Project.toml` for dependencies and versions; do not assume.

## Current state and roadmap

1. **Fields.jl** — refactored, done and test-covered (`test/fields.jl`): compatibility
   predicates; `FieldSpectralMultipliers` moved here (explicit six-array constructor +
   convenience constructor from a field; host-built wavenumbers copied to backend).
   Transform input contract: allocating `to_physical`/`to_spectral` preserve their
   input (they copy it); the in-place `!` forms may overwrite the source (FFTW
   complex-to-real destroys the spectral input; backend-divergent — AMD/rocFFT does not).
2. **FieldAlgebra.jl** — **done** (full public surface): M2 (add/subtract, real
   scaling, scalar-field multiplication) + M3 (dot, cross, tensor-vector and
   tensor-tensor `mul!` with α/β, transpose, tensor inner products, norms,
   sym/skew/dev) generated, loading, and verified — **198 public methods** (the
   pre-refactor surface, parity baseline locked in `test/method_parity.jl`), zero
   ambiguities, behaviour tested in `test/fieldalgebra.jl`. Fiber ops use full
   **StaticArrays** (a package dependency — `StaticArraysCore` gave only the types).
   `mul!` keeps the LinearAlgebra no-alias contract; cross and the unary
   index-shuffles (transpose, sym/skew/dev) are alias-guarded via `_guard_noalias!`.
3. **DifferentialOperators.jl** — remove the moved `FieldSpectralMultipliers`
   definitions, fix its exports and the umbrella's re-export, qualify Fields helpers.
   Old five-argument multiplier-constructor callers break by design.
4. **Tests** — `test/` suite (`runtests.jl` + per-module files + `test/Project.toml`;
   `Pkg.test()` green, 173 tests). `test/fields.jl`: FFT round-trip, multipliers vs
   `fftfreq`/`rfftfreq`, Nyquist behavior, validation, transform input-preservation.
   `test/fieldalgebra.jl`: M2 + M3 arithmetic and contractions in both
   representations, the spectral zero-mode invariant, alias safety, and the
   intentional absences. `test/method_parity.jl`: the full 198-method baseline +
   ambiguity check. Pending: DifferentialOperators coverage.
5. **Deferred by decision** — CPU threading via the `_assign!` primitive
   (design recorded in `docs/ARCHITECTURE.md` §9; until then, keep elementwise writes
   flowing through field-level broadcasts or named kernels so the later switch stays
   mechanical). `FFTW.set_num_threads(Threads.nthreads())` must run before plan
   construction once CPU performance matters.

## Working agreements

- The API is not frozen; do not build backward-compatibility shims.
- During large refactors, complete "supposedly working" drafts are acceptable for
  architecture review, but loading + parity checks are required before calling work
  finished.
- Errors found later are fixed one by one; architectural soundness is judged on the
  full picture first.
