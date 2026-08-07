# CLAUDE.md — GBGPeriodicFields

Julia package: real-valued scalar/vector/second-order-tensor fields on 3D rectangular
periodic domains, with physical-space and real-to-complex (rfft) spectral
representations, on CPU (`Array`) and GPU (`CuArray`, `ROCArray`) — **single node, shared-memory only**
(CPU multithreading and a single GPU; distributed/multi-node and multi-GPU are out of scope). Production
target: **NAISS Arrhenius** (decision 37) — CPU nodes carry the beyond-GPU-VRAM grids (the CPU path's
tuning target, not small tests), and the GPU nodes have **`aarch64` (Grace) hosts**, so **never adopt an
x86-only dependency or recommendation** (e.g. the MKL FFT provider); nothing in the tree is known
x86-only, but nothing has been built on ARM yet (`docs/PERFORMANCE.md` §7 gap 7). Built as the field
layer for pseudospectral fluid/turbulence solvers, with the interpolation/anterpolation point layer for
Lagrangian-particle methods in place. Development is **GPU-first**; CPU multithreading is implemented (hybrid, behind the
`_assign!` primitive — see `docs/ARCHITECTURE.md` §9).

Before any structural or design change, read `docs/ARCHITECTURE.md`. It explains why
the architecture is the way it is; do not re-litigate recorded decisions without the
user. **Design changes must be justified by established mathematics** — the
differential-geometry / fiber-bundle framing of §2 (whose fiber carries the **Cartesian Euclidean**
structure on one fixed orthonormal frame: introduce no curvilinear-coordinate machinery, explicit
metric tensors, or vector/covector distinction unless the design changes to need them) (fields and point-values as sections
of a flat tensor bundle over a base; the vertical fiberwise / horizontal grid-bound
operation split) — **not by convenience**: "it's convenient", "for symmetry", or "for
completeness" is never a valid justification (cf. invariant 1's deliberate absences). The
conceptual model and the writing/docstring conventions are recorded once — in
`docs/ARCHITECTURE.md` (§2 and its documentation policy) and this file; the umbrella module
`src/GBGPeriodicFields.jl` only points there (its former AI-tips block was merged out, to keep one source).

## Modules and wiring

- `src/FiberSections.jl` — base-agnostic foundation: the `AbstractFiberSection{T,R}` supertype (field and point-value types subtype it), the **fiber types** (`FiberVector{T} = SVector{3,T}`, `FiberTensor2/3/4`, `fiber_shape` — the value at one base point, base-agnostic by construction, so `Points` takes its fiber vocabulary from here rather than from the grid module; moved from `Fields` 2026-07-28), the `_assign!`/`@_assign!` threading primitive, and the **vertical-algebra code generators** (per-component formula + kernel-body builders, incl. norm/sym/skew/dev via `section_scalar_type`) — reused verbatim by `FieldAlgebra` and `Points`, so each fiberwise formula is written once.
- `src/Fields.jl` — types (`Grid3D` — uniform, and it enforces that: the four-argument constructor rejects a `grid_spacing` contradicting `domain_size ./ grid_size`, decision 45 — `RealFourierLayout`, field types; `FiberVector{T} = SVector{3,T}`, `FiberTensor2{T} = SMatrix{3,3,T,9}`, plus `FiberTensor3/4`), memory layout, broadcast style, compatibility checks, `FieldTransformPlans`, `FieldSpectralMultipliers`, the public allocator `similar_field` (a section carrying a reference's representation, order, grid and backend — uninitialized storage; `Points` mirrors it with `similar_pointvalues`; decision 44), and the field↔HDF5 persistence generics `write_field`/`read_field` (the durable-snapshot serializer — a field maps to one self-describing HDF5 group; the methods live in the `ext/GBGPeriodicFieldsHDF5Ext.jl` weak-dependency extension, loaded with `HDF5`; the consumer owns the file and any notion of time — invariant 12; decision 29).
- `src/FieldAlgebra.jl` — fiberwise/pointwise algebra; method families emitted by code generators. Includes `combine!` (the weighted combination / axpby `α·a + β·b`, linear ⇒ both representations, alias-safe) and `det`/`det!` (the determinant, the third invariant `I₃`; nonlinear ⇒ physical-only, mirrored to point-values where `tr` lives; decision 27). Also **`map!`/`map`** (decision 48, decision-35's first instance): the arbitrary-fiber-map escape hatch — an extension of `Base.map!`/`Base.map` applying any φ per base point through the shared `_fiberwise_pass!` executor (the pure-fiber adapter — assemble → φ → flatten — lives in `FiberSections`), fields in physical representation here and point-values in `Points`; physical-only (nonlinear), order-changing (`exp∘det`), multi-input, α/β, allocation-free, the section-valued sibling of the mapped reductions.
- `src/DifferentialOperators.jl` — spectral operators (`gradient`, `divergence`, `curl`, `symmetric_gradient` (the fused symmetric part of `∇u`, `Ŝ_ij = (i/2)(k_j û_i + k_i û_j)` — the symmetric peer of `curl`, skipping the full gradient; decision 27), `laplacian`, `inverse_laplacian`, `helmholtz_projection`, in-place variants). Imports `FieldSpectralMultipliers` and its compatibility/broadcast helpers from Fields; the umbrella re-exports the Fields version. Owns only the spectral kernels and the operators. The in-place `!` operators are **allocation-free** (lazy `|k|²` via `_squared_wavenumber_broadcast` returning an unfused `Broadcasted`, + fused `laplacian!`/`inverse_laplacian!` kernels), so a preallocated in-place hot loop allocates nothing per step — required for hassle-free GPU runs (no manual GC/`reclaim`; decision 24, guarded by `test/allocations.jl`). Keep it that way: new in-place kernels must fuse their scratch, not materialize it. `helmholtz_projection!` is a **one-pass KernelAbstractions kernel** (the third KA site): per mode it reads the three source components once, computes the longitudinal factor `a_j û_j/|a|²` once (every factor from the derivative-wavenumber family — the exact discrete projector, idempotent and divergence-annihilating at every mode; decision 42), writes all three outputs — 2.7–6.5× the old three-broadcast form, **alias-safe by construction** (dest === source needs no guard temporary, bitwise-equal; sources deliberately not `@Const`). `helmholtz_projection!` and `divergence!` (both fiber signatures) take the **kernel-composed arities** `op!(dest, f, mult, kernel[, α, β])` — a `convolve!` fused into the operator's own pass (the product of Fourier symbols; α/β as in `convolve!`, the four-arg form delegating `one(T)`, `zero(T)`), + allocating `op(f, mult, kernel)` wrappers; `curl!` deliberately has no kernel arity (no consumer). Decision 32.
- `src/Convolution.jl` — **periodic convolution** of a field with a kernel, in spectral representation (the kernel-multiplier role of the measure structure — one integration structure whose other two roles are the reductions and the grid↔point transfer). `convolve`/`convolve!` apply a kernel `ĝ` (a `ScalarFieldSpectral` transfer function) as the coefficientwise product `f̂·ĝ` — the operation invariant 1 names but bans as `*`, offered under its true name `convolve` (exported infix `⋆`; never `*`); a scalar kernel broadcasts over the fiber, with α/β, alias-safe (no guard, like `laplacian!`), spectral-only; `convolve(g₁,g₂)` composes kernels. **Decision 51:** `spectral_cutoff`/`spectral_band` return a **`RadialKernel`** — the symbol σ(|k|²) itself, evaluated per mode (a closure + three references vs `O(N³)` coefficients; signatures unchanged), with `radial_kernel(σ, ref, mult)` for any other symbol (integrating factor, smooth filter, hyperviscosity), `materialize_kernel` the opt-in escape hatch, radial∘radial composing into a radial and radial∘separable into a lazy `ProductKernel` (cross-family, one pass), and `weighted_inner` accepting a radial weight but deliberately not a separable one. A symbol closure must capture **values, never a type** — a captured `Type` is not a bitstype and a GPU launch rejects it. `spectral_cutoff` builds the isotropic sharp low-pass (de-aliasing) kernel; `spectral_band(ref,mult,wavenumber_low,wavenumber_high)` is the annular generalization (cutoff = the `wavenumber_low = 0` case); `radial_kernel(identity, ref, mult)` is the `|k|²` symbol itself (the consumer builds `exp(−ν|k|²Δt)`/envelopes/Germano from it — invariant 12, decision 21; the materializing `squared_wavenumber_field` was removed by decision 60); `assignment_window(ref,mult)` is the linear/CIC mass-assignment window `Ŵ=∏ sinc²(kₐΔxₐ/2)` for **deconvolving** a gridded point density (Phase 2 of the RDF route, decision 22); `translation_kernel(ref,mult,h)` is the shift theorem's phase `ĝ=e^{−ik·h}`, which **displaces** a field by a physical offset h (`f ↦ f(x−h)`) — the one **complex** kernel, whose Nyquist value must be the *real* factor `cos(πhₐ/Δxₐ)` (even part ← true `|k|`, odd part ← the Nyquist-zeroed derivative `k`; the first op to use **both** multiplier families — invariant 5) or the result is no real field's spectrum (decision 28). **Decision 50:** `translation_kernel` and `assignment_window` return a **`SeparableKernel`** — the three per-axis factors they already built, with the final materialization dropped, so the kernel costs three `O(N)` arrays instead of `O(N³)` coefficients (~10 KiB vs 129 MiB at 256³) and a pass reads no kernel storage; bitwise-identical results (the tests use the materialized product as oracle), decision 28's Nyquist split untouched, with per-axis `convolve` composition, `inv` (the reciprocal, = the deconvolution), and the in-place `translation_kernel!`. A kernel argument is the union of the two storage classes **package-wide** (the protocol —
`AbstractSpectralKernel`, `_kernel_data`, `_check_kernel_compatibility`, the `SpectralKernel` union — lives in `Fields` so `DifferentialOperators` and `Reductions` can see it too; a test walks every kernel-taking entry point and requires both classes to agree bitwise); the generic `ScalarFieldSpectral` path stays for kernels that are not closed forms. **Decision 33 (IT items 2+7):** `exponential_convolve!`/`exponential_convolve` apply the exponential radial kernel `exp(c·|k|² + s·ŵ)` **lazily from the wavenumber arrays** (never materialized; for c≤0 the periodic Gaussian `e^{−cΔ}`; ŵ an optional real per-mode field entered as scale×field so a per-call scale is free; a *scalar* offset is a deliberate absence — it folds into α as `e^{s₀}`), with single-operand α/β forms and two-operand `(dest, α, a, β, b, mult, c[, s, ŵ])` forms; and `combine!` gains the kernel-composed method `combine!(dest, α, a, β, b, kernel)` (defined here, not FieldAlgebra — the parity baseline filters by module, so 206 stands), the decision-32 trailing-kernel idiom; `b === dest` is the filtered accumulate (alias-safe, so no second trailing α/β — the glyph-collision rule). Imports the spectral types + helpers from Fields. `docs/ARCHITECTURE.md` §2, decisions 20, 21, 22, 28, 33.
- `src/Points.jl` — the unstructured base (with the point↔HDF5 persistence generics `write_points`/`read_points`, the field pair's twin — a `PointSet` or a point-value section maps to one self-describing group, positions and values kept separate; methods in the same weak-dependency extension; decision 46): point-data types (`Point`, `PointSet`, and `ScalarPointValues`/`VectorPointValues`/`TensorPointValues` under `AbstractPointValues <: AbstractFiberSection`, all exported) and their **full fiberwise algebra** (M2 + M3 mirroring the field surface in physical representation, generated by reusing the FieldAlgebra builders over an extended section interface — no formula written twice), plus the representation-free peer of **`map!`/`map`** (decision 48; reusing FieldAlgebra's shared `_map_pass!` driver, no physical-only split). Implemented and tested.
- `src/Interpolation.jl` — the grid↔point transfer: **interpolation** (gather `W`, grid→point; also the callable `f(x)`) and its adjoint **anterpolation** (scatter `Wᵀ`, point→grid, with α/β), an adjoint pair under one `AbstractTransferScheme` (exactly L²-adjoint after the `N/M` measure rescaling) (a scheme = choice of *kernel* + *representation*; decision 23). **Two families.** *Physical-domain splines* (`AbstractSplineScheme`): smooth `LalescuSpline(n,m)` (two-point Hermite, `CatmullRom = (1,1)` default, TurTLE-pinned) and `C⁰` `LagrangeSpline(n)`; portable KernelAbstractions + Atomix kernels (CPU/CUDA/AMDGPU, atomic scatter); shared partition-of-unity weights ⇒ conservation. *Spectral-domain exact transfer* (`DirectDFT`, on a field in spectral representation): the literal `O(NM)` inverse/forward DFT `f(xₚ)=(1/N)Σₖ α(k)·Re(f̂ e^{ik·(xₚ−o)})` / `Σₚ qₚ e^{−ik·(xₚ−o)}` — reproduces the band-limited field exactly (divergence-free reference; matches `to_physical` at nodes), the transparent baseline + the oracle for the native fast `NUFFT(reference; tol)` (`O(N log N + M)` windowed gridding = spread→FFT→deconvolve, reusing the transfer kernels + oversampled plans + an `assignment_window`-style deconvolution; own-native, no dependency; exact to ε vs `DirectDFT` on the resolved **sub-Nyquist** band — the rfft Nyquist is projected out, so the pair stay exact adjoints). `docs/ARCHITECTURE.md` §10, decision 23.
- `src/Reductions.jl` — the **L²/measure structure** (the third operation family, after the vertical fiberwise algebra and horizontal differential operators): base reductions over `AbstractFiberSection`, against the base's measure (`Grid3D` cell volume / `PointSet` counting). `integral` (extensive `∫f dμ`), `inner`/`l2norm`/`lpnorm` (normalized L²), the multiplier-weighted `weighted_inner(f[,g],w) = ⟨f,w·g⟩` (spectral-only, the reduction-dual of `convolve`, generalizing `inner`; `w=|k|²` is the Dirichlet energy; fused, allocation-light; decision 27). The weight is a kernel in **any** of the four storage classes — all bitwise-equal, the former `Union{StoredKernel,RadialKernel}` having been a narrow signature rather than a constraint — and a **complex** weight is refused wherever the type can decide it (`combine_eltypes`, a folded branch measured free), so `translation_kernel`'s phase cannot be silently read as its real part; `StoredKernel` is the documented exemption, its complex storage carrying no information about the multiplier (decision 62), and `mean`/`std`/`var`/`cov` (extending `Statistics`; `mean` fiber-preserving, `std`/`var` scalar-only, `cov` the vector covariance tensor) + `maximum`/`minimum`/`extrema` (extending `Base`, scalar sections). Every reduction also has a **mapped form** taking a leading fiber map — `mean(det,A)`, `maximum(norm,u)`, `integral(det,A)` — reducing a nonlinear fiber invariant in one fused pass with **no intermediate section** (mirrors `Statistics`' `mean(f,itr)` / `Base`'s `maximum(f,itr)`; `var`/`std` have no such stdlib spelling, so neither do we; naming the map is also what makes an order statistic well posed above R=0, lifting the bare scalar-only restriction; physical-only, since the map is nonlinear). **The reduction is split by backend so fused wins on BOTH** (`_reduce_fiber`): CPU gets a pairwise-blocked vectorized loop over the component arrays, GPU keeps one fused `Broadcasted` pass. Reason: reducing a lazy `Broadcasted` forfeits the CPU's vectorized blocked reduce loop (5.6× on the reduce alone), costing more than the extra section materializing moves; a GPU has no such loop to lose (thread-parallel, bandwidth-bound) and fusing saves it a section write+read-back. Same-map A/B (`mean(det,A)` vs `mean(det(A))`, 128³ F64): CPU 5.1 vs 13.0 ms, GPU 0.55 vs 0.69 ms — fused faster on both, 0 bytes vs 16.8 MB. Pairwise blocking also makes the CPU path the most *accurate* route (1.2e-16 vs the lazy form's 3.7e-15). Strided gather is only ~2×; the `StaticArray` build is free. **Measurement trap (hit twice):** `LinearAlgebra.norm` on a fiber is the overflow-safe scaled 2-norm, 4.3× the naive `√Σuᵢ²` the fieldwise `norm` uses — so `maximum(norm,u)` vs `lpnorm(u,Inf)` varies algorithm AND route and falsely reads as a fusion penalty (same formula: fused 1.8 vs 4.2 ms). Vary one thing at a time. Three spellings silently allocate and are pinned at zero by `test/allocations.jl` (multi-arg `mapreduce` materializes a section on CPU; a vararg closure has an uninferrable component count; a forwarded `Function` arg needs its type named in the signature or Julia will not specialize). Decision 30. Measure reductions on **fields in physical representation + point-values**; `inner`/`l2norm` (Parseval — equal to the physical inner, rfft half-spectrum weighting) and `integral`/`mean` (the zero/DC Fourier mode, reusing `_spectral_zero_mode_data`/`_spectral_constant_scale`) *also* act on fields in **spectral representation**, equal to the physical value with no transform, and the **radial reductions** `radial_spectrum(f,mult)` (shell-resolved inner = the radial power spectrum, spectral-only) + `radial_correlation(f,plans)` (its physical-space Wiener–Khinchin dual, the shell-averaged two-point autocorrelation `C(r)=𝓕⁻¹(|f̂|²)/N`); `sum(spectrum) == C(0) == inner` (decisions 21, 22), each with a **two-field co-spectrum** form `radial_spectrum(f,g)` / `radial_correlation(f,g)` (cross-power / cross-correlation, refining the mixed `inner(f,g)`; symmetric, may be negative; the one-field forms are the g=f case). `mean(points) = (1/M)·Σ` (counting measure). The radial reductions share two device-clean **fused scatter-add** binning kernels (shell index, fiber contraction, and Parseval weight derived per element from the mode/grid index — no staging arrays; the shell count analytic from the corner; decisions 25, 34): `radial_spectrum` is pinned allocation-tight, `radial_correlation` keeps only its substance (the power field + the allocating inverse transform). Physics stays consumer-side. `docs/ARCHITECTURE.md` §2, decisions 18, 21, 22, 25, 34.
- Include order: FiberSections → Fields → FieldAlgebra → DifferentialOperators → Convolution → Points → Interpolation → Reductions. Cross-module access only through explicit `using ..Module: name, ...` lists — never a bare `using`.
- `ext/` holds weak-dependency package extensions (Julia `[weakdeps]`/`[extensions]`) — currently `GBGPeriodicFieldsHDF5Ext` (section↔HDF5 I/O — `write_field`/`read_field` for fields, `write_points`/`read_points` for the point layer; loaded only when `HDF5` is present; decisions 29, 46). Bare `function … end` stubs + docstrings stay in the core so `?write_field` works without HDF5.

## Core invariants — do not violate

*These are the operative statements. A one-line-each **rendered** copy lives in `docs/ARCHITECTURE.md` §2 ("The invariants"), because the design docs cite them by number dozens of times and a reader of the site had nowhere to look them up. The two are a deliberate duplication: **edit both in the same change**, the rendered list being the compressed form of whatever is stated here.*

1. **The public method set is the spec.** Deliberate absences encode representation
   validity: no field×field *multiplication* in spectral representation (`*`/`multiply!`) — the
   coefficientwise product is a convolution, offered under its true name as `convolve`
   (never `*`; `Convolution`, decision 20) — no spectral division by a scalar field, no
   spectral pointwise norms. Operations linear in the field (constants,
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
9. Aliasing is safe **by construction**, and a section **owns its storage** so that it is. Every
   fused pass (the one-pass spectral operators and the `_fiberwise_pass!` executor behind the
   algebra) reads all of an element's sources into registers before writing any of its outputs, so
   in-place aliased calls are computed directly, bitwise-identical to non-aliased — the former
   `_guard_noalias!` family is retired (decisions 38/39). That argument holds only while one
   section's element ``n`` is the other's element ``n``, so the constructors **reject borrowed
   storage** — a `SubArray` anywhere in the parent chain — which leaves same-array as the only way
   two sections can share memory (decision 59). Ownership, not layout: `Array`, `CuArray`, `ROCArray`
   and a `reshape` of any of them all pass, so invariant 6 is untouched. `mul!` keeps its documented
   contract that destination must not alias (LinearAlgebra convention), without widening it.
10. α/β kernels: five-argument forms convert `T(α)`, `T(β)` and branch on
    `iszero(β_value)` (overwrite vs accumulate); three-argument forms delegate with
    `one(T)`, `zero(T)`. Throughout, α scales the computed result and β the destination
    accumulated onto. **One deliberate exception, and the only one:** `combine!` IS the weighted
    combination `α·a + β·b`, so its weights scale its two *operands* — what the operation is, and what
    its name announces. No other operation may reuse the glyphs for a second role; that is the
    glyph-collision rule decision 33 applies when it declines a second trailing α/β.
11. Transform input contract: allocating `to_physical`/`to_spectral` preserve their
    input (they copy it); the in-place `to_physical!`/`to_spectral!` may overwrite the
    source. The inverse real transform (FFTW complex-to-real) destroys its spectral
    input as scratch, and this is backend-divergent (AMD/rocFFT preserves it). Never
    rely on a `!`-transform's source surviving; use the allocating form to keep it.
12. **Math backend — no time, no particles.** The package is a field-operation library that
    solvers consume, not a solver. Use domain-neutral terminology (base/fiber, point/value),
    never *particle*/*tracer*. Introduce **no concept of time** — no advection, time
    integration, temporal interpolation, or per-step state; trajectory dynamics belong to the
    consumer. The interpolation data types follow this: `Point` (alias `SVector{3,T}`),
    `PointSet` (SoA positions), `PointValues` (three field-mirroring types). See `docs/ARCHITECTURE.md` §10.
13. **Allocation-free is an enforced contract.** Every in-place `!` operator allocates **no** field-sized
    scratch when called on preallocated buffers with a destination distinct from its sources — fuse
    temporaries into the assignment, never materialize them. This is load-bearing for GPU hot loops: a
    per-call device temporary escapes Julia's GC (which triggers on *host* pressure, blind to the *device*
    buffer a dead array owns), so the pool grows every step until the run wedges (decisions 24, 25, 26).
    Enforced **exhaustively** by `test/allocations.jl` via `@allocated` **on the CPU** — where a
    materialized array's full bytes are counted; on the GPU it is a device buffer behind a tiny host
    wrapper, invisible to `@allocated`, so a GPU measurement would miss the very leak that wedges a hot
    loop. A new in-place op — or any function claimed allocation-free — **must** be added to that audit.
    Deliberate materializers (`norm!`/`lpnorm` — `dev!` left the list when decision 39
    fused its trace into a register and `std`/`var` when decision 49 rewrote them as two fused passes, `radial_correlation` (the power
    field + its transform; `radial_spectrum` is pinned tight since decision 34), the mixed
    spectral `inner(f, g)` — rocBLAS offering no `dotc` over a strided `ROCArray` view) are the documented
    exceptions and get a *bounded* regression guard, not a zero guard.
14. **Sections combine only within one precision and one storage family — never by conversion.** An
    operation over two or more sections requires them to agree in **element type** and in **storage
    family** (`Array` with `Array`, `CuArray` with `CuArray`, `ROCArray` with `ROCArray`), and
    **refuses** anything else with a clear `ArgumentError` rather than promoting, copying, or
    transferring. Two properties make this a contract rather than an observation. First, the refusal
    must be the **package's decision**: `inner` once refused a device/host pair only because CUBLAS
    had no method taking a `CuPtr` and a `Ptr` together, and `gradient` refused host multipliers only
    because KernelAbstractions declined to launch over mixed arrays — the right outcome resting on a
    vendor's method table, which would go silent the moment any path accepted the mixed call. Second,
    it binds **every argument**, not the obvious ones: the destination of an in-place call, and the
    **non-section partners** — a spectral field and its `FieldSpectralMultipliers` must match too,
    and multipliers are not a section, so nothing section-level covers them. The checks live in
    `_check_same_domain`, `_check_contractible` and `_check_multipliers_compatibility`; a new
    multi-argument operation routes through one of them or states why it need not. Conversion between
    precisions or storage families is a **future, explicitly-named operation** (roadmap below), never
    something arithmetic does implicitly.

## Code generation rules (FiberSections + FieldAlgebra)

- Per-component formulas are written **once** in `FiberSections` (shared by `FieldAlgebra` and
  `Points`); `@eval` tables in each consumer stamp out the representation, argument-order, and
  in-place/allocating variants. Builders (all in `FiberSections`):
  `_vector_component`/`_tensor_component` (kinds `:field`/`:fiber`), `_sum_terms`,
  `_product`, `_vector_kernel_body`/`_tensor_kernel_body` (with `alpha_beta` flag),
  `_scalar_kernel_body`, the contraction/decomposition formula builders, and `section_scalar_type`
  (real `T` for any section), and the **fused fiberwise executor** `_fiberwise_pass!` (decision 39:
  one KA kernel + one slab-threaded linear `@simd` CPU loop running every stamped values function;
  the former per-consumer alias guards are retired — fused passes are alias-safe by construction).
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

## Documentation policy — the docstring rubric

This is the organizing spec for every user-facing docstring and API page; §Style below elaborates the
individual conventions and their rationale, and the rendered glossary at `docs/src/notation.md` is the
reader's copy of the notation. Two audiences, one rule each: a **module docstring is a map**; a
**function docstring is a home**.

**Two-tier structure.**
- **Module docstring = map.** What the module is, its scope and place in the architecture, and its
  invariants (physical vs spectral, the base measure) — then a **linked one-liner per operation
  family, and no formulas.** Every formula lives in the operation's own docstring.
- **Function docstring = home**, in this order: (1) a plain one-sentence identity in the user's terms;
  (2) when to use it, versus the alternatives; (3) each argument (positional and keyword) and its
  effect; (4) the caveats a user needs (memory, accuracy, gotchas), as a `!!! warning` where
  load-bearing; (5) one physical-meaning-first formula **if a clean one exists**, never overflowing
  (hand-wrap with `aligned`/`gathered`); (6) an inline citation for a **named/published** method
  (verbatim-consistent with `ARCHITECTURE.md` §References) and **none** for a classical one (the
  Lagrange interpolant, Fornberg weights); (7) cross-links. **Exclude:** implementation internals
  (→ `#` comments), unexplained specialist jargon, architectural rationale (→ `ARCHITECTURE.md`), and
  the formal/intrinsic apparatus (→ `FORMALIZATION.md`).

**One concept, one home.**
- *Across dispatch.* One docstring per operation, on the bare binding (`function f end`); a generic
  carries **one** docstring, never one per method. Per-scheme or per-representation specifics live in
  the scheme's / representation's own docstring, linked (the transfer verbs collapse 12 → 4 this way).
- *Across `f`/`f!`.* The in-place `!` form is the **home** — it owns the componentwise formula and the
  kernel — and is listed **first**; the allocating form and any operator alias (`+ - * / ⋅ × ⋆`) is a
  **thin wrapper** that leads with the one-sentence meaning and `@ref`-links the home, carrying no
  second copy of the formula. The bare operators `+ - * /` carry thin allocating docstrings so the
  pairing is documented and REPL-visible.

**The four shape rules (user-decided 2026-07-24; the `/check-consistency` uniformity pass).** The
rubric above says what a docstring must *contain*; these fix the *shape*, so the same content is not
written four ways. **(1) Arguments.** A docstring documenting **three or more arguments, or any
keyword argument**, uses the bulleted form led by `The arguments are:`; with fewer, the arguments are
bound in running prose and there are no bullets. Never mix the two within one docstring. Count the
arguments a *signature* takes, not the distinct names across type-specialized variants (`norm!` takes
two in every overload and stays prose, though its three signatures name the second one three ways).
A **thin allocating wrapper is exempt**: it documents no arguments at all, leading with the
one-sentence meaning and `@ref`-linking the home, so the threshold never applies to it. **(2) Types.**
A type that stores named, user-readable fields documents them under `The fields are`, one bullet per
field; prose is reserved for the one-sentence identity above that list. **(3) Admonitions.** Every
`!!!` block carries a **custom descriptive title** stating the caveat (`!!! warning "The destination
must not alias an input"`), never a bare `!!! warning` rendering as "Warning" — a reader skimming the
page should learn the hazard without opening the block. **(4) The in-place steer.** Every `!` form
that *has* an allocating sibling carries this sentence verbatim, after the identity paragraph and
before the arguments: *"Use this in-place form when `destination` is already allocated; the allocating
[`f`](@ref) returns a fresh result instead."* The sentence names **the destination argument the signature actually has** — `destination` in most of the
corpus, but `out` in `interpolate!` and `field` in `anterpolate!` — since naming a parameter the method
does not take would be worse than the variance; "verbatim" governs the wording around that name, not the
name itself. An operator sibling (`+`, `-`, `*`, `/`) is written in
plain backticks, not `@ref`, as a style choice — the glyph reads better unlinked. (The operators **do**
now sit on the FieldAlgebra `@docs` block, paired after their in-place homes like `dot!`/`dot`, so a
link *would* resolve; they were previously mis-swept into that page's Internal API by the `Public =
false` autodocs — the same public-but-unexported-Base-extension class as the stats on the Reductions
page. The bare backtick stays the convention regardless.)
**(5) Aliasing.** An operation-specific statement of whether `destination` may alias an input lives in
the **`destination` argument bullet**, not as standalone prose before or after the argument list — that
is where a reader asks the question, and the template already puts argument caveats there. Settled
2026-08-05 on the majority position (`convolve!`, `combine!`); `curl!` and `helmholtz_projection!` were
the two outliers and were moved. The package-wide guarantee itself belongs in the module docstring and is
**not** repeated per operation — which is why `cross!`, `transpose!`, `sym!`, `skew!` and `dev!` carry
nothing locally and are correct as they stand. An operation states it for itself only when it has an
operation-specific *reason* to give (`curl!` and `helmholtz_projection!` each read all three components
of a mode before writing any), or when its contract is the contrary one (`mul!`, whose destination must
**not** alias).

**Two exemptions to rule 1, made explicit after the 2026-08-04 battery flagged them as violations:**
an **internal `_`-prefixed helper** documents its arguments in whatever form reads best (the threshold
exists to keep a *user-facing* argument list findable, and the codegen builders and kernel bodies are
read alongside their code); and a **single element-type keyword** (`T = Float64` on `LalescuSpline`,
`LagrangeSpline`, and the callable field's `scheme`) bound in one prose clause does not trigger the
bulleted form, since one self-evident keyword is not the long-list problem the rule addresses.
A `!` form with **no** allocating sibling (`combine!`) and a setter (`set_fft_threads!`,
`set_threading_cutoff!`) take no such sentence. **`translation_kernel!` is an exemption** (recorded
2026-08-04, after three independent panel hats flagged the deviation): it rebuilds an existing
`SeparableKernel` for a new displacement rather than filling a `destination`, so the verbatim sentence
would name an argument its signature does not have. It carries the same steer reworded to its own
parameter, and that is the intended form, not drift; `to_physical!`/`to_spectral!` already steer to their
siblings for the stronger input-preservation reason (invariant 11) and are not doubled.

**An `## Internal API` section splits by heading only when it holds both kinds.** A section documenting
**both types and functions** uses `### Types` and `### Functions` over two `@autodocs` blocks (`Fields`,
`Points`, `Interpolation`); one documenting **only functions** uses a single unlabelled block and no `###`
at all (`Convolution`, `DifferentialOperators`, `FieldAlgebra`, `FiberSections`, `Reductions`). The split
tracks the content, never the page. Every such section also opens with the same disclaimer sentence.
**And a `@ref` never abuts a second code span** — ``[`f`](@ref)`(args)` `` renders as two adjacent
monospace chips with a visible seam, so write the whole call as the link text with an explicit target,
``[`lpnorm(f, Inf)`](@ref lpnorm)``.

**API pages are math-grouped.** Group public objects into the operation **families of
`ARCHITECTURE.md` §2** under hand-written `###` headers via explicit `@docs` blocks (not `@autodocs`,
which cannot express a semantic group). Each object appears **once**, in the family whose defining
mathematics it realizes; keep an `f`/`f!` pair together with the `!` home first; order a group by
increasing tensor order. Lead a page with its **headline operations**, then the supporting
types/schemes they take (Interpolation: the transfer operations before the transfer-scheme catalogue).
Drop `@index` — it lists only module-owned bindings, so it silently omits the imported/extended
operators and mixes in the internals; keep `@contents` as the table of contents. `checkdocs = :exports`
guards a dropped export.

**Coverage.** A measure reduction documents **every base it supports** — a `Grid3D`'s cell-volume
average *and* a `PointSet`'s counting average — not just one.

**Notation** (glossary: `docs/src/notation.md`). The imaginary unit is upright ``\mathrm{i}`` (never
bare italic `i`, never `\imath`/`\mathbb{i}`), which frees `i` as an index; indices are italic
``i, j, k, \dots`` in order, used freely alongside ``\mathrm{i}``; a partial derivative is
``\partial_{x_i}`` (subscript the coordinate), and a second-order derivative is ``\partial^2_{x_i x_i}`` (a
repeated fiber index is summed, Einstein convention — so the Laplacian is ``\Delta f = \partial^2_{x_i x_i} f``,
no explicit ``\sum``). No horizontal scroll, and a code identifier never
sits inside a math span.

**Prose is grammatical.** Every sentence has a subject and a verb; no verbless fragments, noun-stacks,
`label:`-colon tags, or comma splices. **Concise means few words, not missing verbs** — the goal is
compact prose that still reads as sentences aloud; restore the grammar without adding fluff.

**A sentence opens with a capitalized ordinary word — never a lowercase code identifier or a math
formula.** A lowercase start is the defect, so **reword** so an ordinary word leads — never capitalize
the identifier, whose binding is lowercase by nature (`` `divergence` uses this kernel`` → "The
`divergence` operator uses this kernel"; a formula opener `` ``n = 0`` is linear`` → "The case ``n = 0``
is linear"). **Exempt** (a fragment, or not rendered): a **bullet / list item** — including a §13
decision-log entry and an argument-doc bullet; a `#` **code** comment — *but* a Literate example's
full-line `# ` line **renders as prose**, so it is **not** exempt; and a **capitalized**
type/module/file opener (`Point`, `DirectDFT`, `RESULTS.md`), which already begins with a capital. The
`/check-docs` sentence-opener scan flags this class (it triages out the `e.g.`/`i.e.` abbreviations and
the end-of-line ``\checkmark`` markers it also catches).

**Correctness is verified, not asserted.** Check every formula, normalization, adjoint relation, and
especially every **cross-scheme equivalence** by expanding it (degree, reproduction, indices, types)
against the code — a plausible "X is just Y" is a false claim until the expansion matches. This session
alone: the cross-product index splice, `LalescuSpline(n, 0)` vs `(0, 0)`, and the false
`LagrangeSpline ≡ LalescuSpline(n, 0)` (linear vs degree ``2n+1``).

**Reconciled tensions.** *Compact vs grammatical:* grammaticality is the floor, compactness the goal
above it. *Coordinate-free notation:* the intrinsic maps (`ι*`, `ι_*`, the pushforward of Dirac
measures, `Π_d`) belong to the **design docs**; a docstring uses the honest concrete forms (``\sum_p``,
``\int_\Omega``, `W`/`Wᵀ` as named maps). *Physical-meaning-first vs DRY:* a thin wrapper keeps its one
plain-meaning sentence and sheds only the re-derived formula.

## Style

Two-space indentation; two blank lines between top-level definitions; section banner
comments; descriptive names without abbreviations; moderately long lines are fine.
When unsure about Base/stdlib/package behavior, check official docs — don't guess. Avoid unnecessary
explicit local-variable type declarations; for a linear solve use `\`/factorizations/`ldiv!`, never an
explicit matrix inverse.

**Docstrings vs comments.** Prefer docstrings; reserve plain comments for non-intuitive
*why* (rationale a good name can't convey — the Nyquist split, the α/β branch, aliasing
reasoning, "irregular corner kept explicit because…"). Hand-written internal machinery
(codegen builders, the fused executor, shared Fields helpers, spectral kernels) carries
docstrings; they surface in each module's **Internal API** docs section via
`@autodocs ... Public = false`. The `@eval`-generated methods/kernels carry none (the
formula docstring lives on the builder) — consistent with "generators emit methods only —
never docstrings", which governs generated methods, not the hand-written builders.

**Physical-space meaning first — even for spectral-representation operations.** By invariant 2 a field is
a real physical object and spectral is only a *representation*, so a docstring for an operation that is
*computed* in spectral representation must still **state what it does to the real object in physical space
first — with the explicit relation/formula — then give the spectral form** it actually uses. `Convolution`
is the reference: `convolve` leads with the periodic filtering integral (f⋆g)(x) = ∫_Ω f(y)·g(x−y) dy (and
its discrete circular sum) before the coefficientwise product f̂·ĝ; `assignment_window` leads with the
linear/CIC B-spline "tent" cloud W(x) before returning its transfer function Ŵ. Give the physical form
**whenever a clean one exists**; when it does not — a sharp spectral cutoff is a non-compact sinc/Dirichlet
kernel, `squared_wavenumber_field` is the symbol of −∇² rather than a kernel — say so briefly rather than
forcing it. **Correctness:** check the physical↔spectral relation is *exact* for the package's convention
(unnormalized forward, invariant 4 — the convolution theorem holds for both the integral and the discrete
sum); a stray 1/N, cell-volume, or |Ω| normalization factor is the easy slip here.

**Math in docstrings and doc pages — rendered LaTeX, standard notation, symbol linked to code.**
All mathematics in **docstrings and doc pages** is written as **rendered LaTeX** (Documenter's
KaTeX), never Unicode-glyph approximations: inline as ``` ``\\langle f,g\\rangle`` ``` (double
backticks; in a `"""` docstring the LaTeX backslashes are escaped `\\`, e.g. ``` ``\\Delta f`` ```;
in a `.md` page raw `` `` ``), display as a ```` ```math ```` block. Use **standard mathematical
notation** (∇, Δ, ⟨·,·⟩, ‖·‖, ∫, 𝔽, etc.). **Every code object is explicitly bound to its math
symbol on first mention** — `laplacian` ``\\equiv \\Delta``, `gradient` ``\\equiv \\nabla``,
`divergence` ``\\equiv \\nabla\\cdot``, `curl` ``\\equiv \\nabla\\times``, `inner`
``\\equiv \\langle\\cdot,\\cdot\\rangle``, `l2norm` ``\\equiv \\lVert\\cdot\\rVert_2``, `convolve`
``\\equiv \\star``, `helmholtz_projection` ``\\equiv \\mathbb{P}``, `to_spectral`/`to_physical`
``\\equiv \\mathcal F``/``\\mathcal F^{-1}``, the spectral representation written ``\\hat f`` — so the
reader always knows which symbol *is* which function. Plain `#` code comments stay Unicode (they are
not rendered). `Reductions` is the reference implementation of this convention.

**Silent-rendering-failure micro-rules — markup KaTeX/Documenter render *wrong without failing the build*.**
The bidirectional rule catches the two *loud* failures (a formula in backticks; a bare code name); these
four are *silent* — the source looks right, the page renders broken, and a read-through of the *source*
never catches it. **(a) A code identifier never sits inside a math span.** KaTeX renders a name inside a
``` ``…`` ``` / ```` ```math ```` span as the product of italic single letters (`gradient` → eight italics,
not the word). Backtick it in prose; a code name that must appear *inside* a formula is wrapped
``` ``\\texttt{gradient}`` ```. The `code` ``\\equiv \\Delta`` binding (code **adjacent** to math) is
correct — the token **inside** the span is the defect. **(b) A formula is one LaTeX span** — never split it
across a ``` ``…`` ``` span and an adjacent `` `code` `` span (``` ``0 \\le m \\le`` ``` `2n` renders
broken); keep it one span, a trailing code name in ``\\texttt{}``. **(c) Inline math stays on ONE source
line.** A wrapped continuation of an inline ``` ``…`` ``` span that begins with a CommonMark list/blockquote
leader (`- `/`* `/`+ `/`> `/`1.`, ≤ 3 leading spaces) is parsed as a **new list item** and silently drops
the span out of math mode — the §13 decision log (a list) and any bulleted math are the high-risk spots, and
the α/β `convolve` formula wrapping onto a `+ …` line was exactly this. Break the *prose* around the span,
not the span; **`docs/make.jl`'s `lint_inline_math()` fails the build on it** (scanning `src/` docstrings +
the four rationale docs + every `docs/src` page incl. the generated example), so even a docstring-only
change must pass it. **(d) No horizontal scroll.** A rendered code block (a docstring signature) and a
display-math block do not auto-wrap — hand-wrap a long signature with a hanging indent under the first
argument (the `anterpolate!` convention, ≤ ~88 source columns) and a wide display formula with
`aligned`/`gathered`, never one line packing equations behind ``\\quad``; inline math reflows and is exempt.
And **a backtick span holds only well-formed Julia** — a name/type/call/expression — never math that merely
looks code-ish (`[lo, hi)`, `R ≥ 2`, a lone `≤`/`·`); those are LaTeX (``\\ge``). The real operators
`×`/`⋅`/`≈` backticked *are* code and stay.

**Math spacing and command support — standard LaTeX idiom.** These are the conventions a fluent LaTeX
author writes by default; the defects they head off — manual spacing, reflexive ``\\left``/``\\right`` — are
novice tells, not subtle bugs. **Never:**
- **manually space around a relation or binary operator** — ``\\;``/``\\:``/``\\,`` next to
  ``=``/``<``/``\\in``/``+``/``-`` doubles the space TeX already puts there; write ``a = b``, not ``a \\;=\\; b``,
  and let TeX space it.
- **put ``\\!`` before an opening/closing delimiter that follows an operator or name** (``\\bigl``/``\\Bigl``/``\\bigr``)
  — as in ``\\max\\!\\bigl(``, ``\\mathrm{Re}\\!\\bigl(``, ``\\mathcal F^{-1}\\!\\Bigl(``: there is already no gap there
  (Op–Open and Ord–Open spacing is zero), so the ``\\!`` only jams the delimiter into the name; write
  ``\\max\\bigl(``.
- **double a negative thin as ``\\!\\!`` before ``\\sum``/``\\int``** — it overshoots into an overlap; juxtapose.
- **write ``\\mathbb{…}`` on anything but a capital ``A``–``Z`` or ``k``** — KaTeX's blackboard font covers only
  those glyphs, so ``\\mathbb{1}`` (or any digit) falls back to a *plain* glyph with the font silently dropped;
  for the indicator/identity write ``\\mathbf{1}`` (or ``\\boldsymbol{1}``). KaTeX supports a subset of LaTeX, so
  for anything tool-specific consult KaTeX's published support table — do not assume parity.
- **use ``\\left``/``\\right`` for auto-sized delimiters** — size every delimiter by hand instead
  (``\\bigl``/``\\Bigl`` … ``\\bigr``/``\\Bigr``): those are Open/Close atoms (no added gap, and the size is the one
  you chose), where ``\\left … \\right`` is an Inner atom that adds a spurious gap around the fence (so
  ``f\\bigl(x\\bigr)`` closes up where ``f\\left(x\\right)`` leaves a gap). **Sole exception:** a system / cases
  written ``\\left\\{ … \\right.`` — an auto-sized left brace closed by a null ``\\right.``.

**These are correct — do NOT "fix" them:** ``\\sim\\!`` and relation-modifier tightening; ``\\,\\mathrm{d}x`` (the thin
space before an upright differential is wanted); ``\\quad``/``\\qquad`` for display-equation separation; and
``\\mathrm{Re}`` versus ``\\operatorname{Re}`` before a delimiter (identical output — Ord–Open = Op–Open
= 0 — so do not churn between them).

**Why this list exists:** every rule is standard LaTeX idiom plus a few documented exceptions, not a matter of
taste. When unsure, reach for a standard LaTeX reference (and KaTeX's support table for what it supports), never
a plausible-sounding typographic argument — the one convention here once justified by taste, the retired
``\\left`` "over-inflates around subscripted sums" claim, was simply wrong.

**A docstring signature mirrors the code's types, and only the docstring wraps.** An argument typed in
the actual method is typed in the docstring; one the code leaves untyped stays untyped — so an untyped
codegen builder or kernel body (`_vector_component(symbol, kind, i)`, `_apply_convolution!(…)`) keeps its
untyped header, while a fully-typed method shows the types (`anterpolate!(field::AbstractFieldPhysical,
points::PointSet, …)`). Wrapping to ≤ ~88 columns is **docstring-only**: the source `function` definition
is left exactly as written, however long (it is not a rendered surface, so its length does not matter). A
generic multi-dispatch *summary* (the `add!`/`subtract!`/`combine!`/`multiply!`/`divide!` M2 family) types
the args carrying one type across the overloads (`α::Real`) and keeps generic the ones that span types (a
field argument; `constant` = `Real`/`FiberVector`/`FiberTensor2`) — `add!(destination, a, b, fields...)` is
such a summary, with no variadic method in the code to mirror.

**Neutral reference register — never "knob".** A tunable argument is an **option** (or *keyword argument*,
*setting*, *choice* — the spline order `(n, m)`, the `NUFFT` `tol`, the α/β accumulation), never a "knob".
Applies to docstrings, the four design docs, the doc pages, `#` comments, and `@testset` names.

**Greek scalars — Unicode `α`/`β`, with two named exceptions.** The axpby accumulation scalars are written
**Unicode `α`/`β`** everywhere — arguments, locals (`α_value`/`β_value`), kernel bodies, and docstrings —
matching the `@eval` codegen, which itself emits Unicode `α`/`β` (so there is **no** codegen friction; the
earlier "Unicode is friction in generated code" rationale was wrong). A hand-written op spelling them ASCII
`alpha`/`beta` is **drift, not a choice** — do not reintroduce it (a `/check-consistency` sweep should flag
it). **Two deliberate ASCII holdouts, not to be "unified":** the `alpha_beta::Bool` codegen flag (it names the
α/β *variant*, not the scalar — `α_β::Bool` would read as a scalar product); and the **NUFFT** window-shape
`beta` with its quadrature locals `omega`/`theta` — a self-consistent implementation block whose `beta` is a
public **keyword argument + struct field** in the English register of `tol`/`width`/`oversampling` (a Unicode
`β` keyword would be an odd Greek among English, and the rename is breaking). TurTLE's `beta_n{n}_m{m}` weight
name is external and likewise stays.

**Cost register, not time — a docstring frames expense, never temporal cadence.** The package carries no
concept of time (invariant 12), so a **docstring must not describe *when* or *how often* a consumer calls
an operation** — never "per-step call", "occasional diagnostic", "every step", "each timestep", "hot loop"
(usage-frequency framing). State the **cost** instead, with a concrete quantitative anchor: fused vs.
allocating, single pass vs. several, ``O(1)``/``O(N)``/``O(N\log N)``, "one wavenumber row, not a field",
"comparable to one `inner`", "far cheaper than …". The reader decides the cadence from the cost. (`weighted_inner`
was reworded from "suits a per-step call, unlike the occasional shell diagnostics" to "a single weighted pass,
comparable to one spectral `inner` … far cheaper than the radial reductions, which build an ``O(N)`` shell-index
pass"; `radial_spectrum` likewise.) The **rationale docs** — `ARCHITECTURE.md` (esp. the decision-24/26
allocation contract), `PERFORMANCE.md` — *may* reference the consumer's per-step solver loop, since explaining
*why* allocation-free matters requires it; a bare function/`#`-comment mention of "each call" (an invocation, not
a time unit) is also fine. The bar is on **docstring prose**.

**Argument coverage (signature-driven) — a sweep separate from the symbol sweep, run *from the signature*.**
For each docstring, enumerate **every argument in its signature** (positional *and* keyword) and cite where
the body documents each (a `- **`arg`**` bullet, a binding clause, an `arg = value` mention, or a `::Type`
for a conventional first arg); flag any `UNDOCUMENTED`. The self-contained *symbol* sweep is not enough — an
argument that surfaces only *inside a formula* reads as "bound by use" and slips through (a tolerance or
stencil width shown only in a formula never gets its own entry).

**`docs/ARCHITECTURE.md` is self-contained — introduce notation in plain text before it is used.** As
the top-level design document it must read top-to-bottom (and, since the §13 decision log is browsed
entry-by-entry, each entry on its own) **without** opening the source or another doc. So **every piece
of notation — a math symbol in LaTeX or a `code` identifier — is introduced in plain language at its
first use**, the meaning stated *before or in the same sentence as* the symbol; later uses may then be
bare. This is stricter than the code↔symbol binding above: it also covers package-specific math symbols
(`W`/`Wᵀ`, the base, the fiber, tensor order `R`, `ψ̂`, `κ`, `α`, the counts `N`/`M`, the origin `o`, …).
Universally standard math may stand unglossed (∇, Δ, ∫, ℝ, plain summation indices). Decisions 18/19 are
the reference entries; keep the header's self-contained note true when editing.

**Citations — one uniform style across docstrings and doc pages.** In-text, **context-standard
author–year**: author-prominent → parenthesized year (`Lalescu, Teaca & Carati (2010)`); inside an
existing parenthetical → bare year, no nested parens (`(de-aliasing; Sundaram & Collins 1996)`). Name
**up to three** authors (`A & B`; `A, B & C`); **four or more → `First et al.`** — except keep enough
surnames to disambiguate two works that would otherwise collide. **Full references:** doc pages cite
short and the canonical full reference lives in `docs/ARCHITECTURE.md` §References (the works the package
**implements / pins to** — Lalescu 2010, TurTLE 2022, van Hinsberg, Fornberg, the anterpolation lineage);
**docstrings carry the full reference inline** (a `# References` block, or a one-line `Reference:`) so a
REPL reader sees it without opening another file — and each inline copy must match the §References entry
**verbatim** (drift is the chosen duplication's only risk, so this is the thing to check). **Every
reference carries a clickable DOI on its title** — `[*Title*](https://doi.org/…)`, or an
`openlibrary.org/…/works/…` link for a book with no DOI — verbatim-identical in the §References list and
every inline docstring copy; a DOI stays REPL-safe (the URL renders as visible text, not a dead link).
**A reference *block* of two or more citations is a bullet list, one citation per line**, never a
semicolon-joined paragraph (unreadable when rendered); a lone citation stays inline as `Reference: …`.
**Not
citations:** eponymous method *names* (the `Catmull–Rom` spline, `Lagrange`/`Hermite` interpolation,
`Fornberg` weights) take **no year** unless you are actually citing the work; non-implemented
related-work asides (e.g. LES SGS models) may stay informal author–year with no full reference; plain
`#` code comments are exempt (not rendered). **Never cite an inaccessible source** — the gitignored
monograph under `inspiration/`, an "accompanying thesis", "appendix A", "Fig. A.1", or any "accompanying"
material the reader cannot open — in **any** user-facing surface: rendered doc pages **and** the
downloadable `examples/` scripts and READMEs. A citation the reader cannot follow is dead weight and
implies they are missing something they cannot get; present every diagnostic on its own public terms
(the trace structure functions and their K41 normalizations are standard turbulence — describe them, at
most cite a public source).

**Standing open item (2026-07-22 battery remainder).** The economy `/check-docs` run (13 Sonnet
lanes + main-thread synthesis; raw findings in `.claude/check-docs-2026-07-22-findings.json`) fixed
every verified `certain` finding and the cheap `likely` ones; the 2026-07-23 completion pass closed
the rest — **all 134 findings are now fixed or dismissed-with-reason** (five cheap relocation lanes +
main-thread triage at full strength, per the cost-mode policy above: the 13-finding sentence-opener
block fell to the list-item exemption the rule itself states; the FORMALIZATION display-wrap and
inner-notation touch-ups landed; `mean`/`var`/`std`/`maximum`/`minimum`/`extrema` gained their
rubric-compliant function docstrings — `var` documenting its Bessel correction, verified against the
code; the HIST_ROCm LaTeX pass landed 2026-07-22). The re-derivation sweep CLOSED the remainder
2026-07-23: eleven sequential economy lanes over a rebuilt 659-formula inventory (a deliberate
superset of the ~314 — every relational span included), each formula independently re-derived against
the implementing code with evidence-bearing verdicts, every mismatch adversarially confirmed in the
main thread, ~10% of matches audited. Result: 597 MATCH, 38 MEASURED accepted, **22 MISMATCH — all
fixed** (continuum-vs-discrete exactness qualifiers on `inner`/`lpnorm` and `convolve`'s cell-volume
bridge; resolved-band scoping of ``\mathbb P^2 = \mathbb P`` and the dissipation identity; the
inverse-Laplacian mean-free compatibility condition; stale performance anchors realigned to finding
(k); the folded-axis ``k_x`` shorthand bound to `fft_dims[1]`; the ``64^3`` shell count 57→56;
notation drift), 2 principled UNVERIFIABLEs, `lpnorm` gained its typed FORMALIZATION entry. **Both
code questions were RESOLVED 2026-07-23** (user-decided): decision 41 generalized the spectral
reductions to follow `fft_dims[1]` (the folded-axis hardcoding is gone; permuted-layout
Parseval/shell/weighted tests + a GPU parity case pin it), and decision 42 made ``\mathbb P`` the
exact discrete projector (the ``a \cdot a`` denominator — exactly idempotent and
divergence-annihilating at every mode, bitwise-unchanged sub-Nyquist). The ledgered test additions
landed: the non-mean-free `inverse_laplacian` input and the ``\det(AB) = \det A \det B``
assertion.

**Two argument-shape inconsistencies are SETTLED, not defects (user-decided 2026-08-05).** The callable
`field(x; scheme = …)` takes its scheme as a **keyword** while `interpolate`/`anterpolate` take it
positionally, and `radial_kernel(sigma, reference, multipliers)` leads with its **function** where
`spectral_cutoff`/`spectral_band`/`assignment_window`/`translation_kernel` lead with `reference`. Both
were raised by the 12-hat panel as real interface inconsistencies; both are kept — a keyword suits a
one-point convenience whose default is the usual case, and leading with the symbol follows Julia's
`map(f, collection)` convention for the argument that distinguishes the general builder from the named
ones. Changing either is breaking. A later review that re-raises them should close against this note.

**The `/check-docs` battery is CLOSED (2026-08-04).** Eleven economy lanes (nine surface lanes + the
family and cold-reader lanes) plus the deterministic guards and the built-HTML pass; every finding
verified in the main thread and closed as fixed or dismissed-with-reason. **Three were mine, from the
decision-60 work three days earlier:** `ARCHITECTURE.md` had **no §13 entry for decision 60** while
citing it four times (definition-of-done item 3, skipped), the invariant list said "Thirteen rules"
after invariant 14 was added, and three `Fields` compatibility docstrings never mentioned the
storage-family check that invariant 14 had put in their code. **Two were real defects rather than
prose:** `docs/PERFORMANCE.md` §6's representative table was stale by 6–14× on its GPU column (last
touched 2026-06-10, regenerated here from the committed archive rather than re-measured, since a
benchmark run needs an idle host), and `examples/hist_postprocess.jl` double-truncated the
structure-function abscissa — the driver already drops `r = 0`, so the second `[2:end]` was silently
discarding the smallest *nonzero* separation from every plotted and normalized inertial range.
**The `var`/`std` spectral formula was wrong in three places** (FORMALIZATION, the `var` docstring, the
`Reductions` module docstring): it stated the *population* moment while claiming Bessel correction, and
its normalization was ``1/N`` where the inner product carries ``1/N^2`` — found independently by two
lanes and confirmed numerically. The cold-reader lane's headline finding is worth keeping: **`section`
appears 108 times across rendered docstrings and was never once defined**, `fiber` 261 times and `base`
113 — the glossary page defines them, but a REPL reader typing `?mean` never sees that page, so the
umbrella docstring now binds base/fiber/section/resolved-band in plain language. Two rule-1 exemptions
were recorded rather than churned (above). `lint_retired_claims()` in `docs/make.jl` was added the same
day and is the build-enforced guard for the decision-60 claim class.

**The 12-hat `/check-consistency` panel is CLOSED (2026-07-24).** The first live economy-tiered run
(ten Sonnet scan hats + the two mathematician anchors on Opus; banked per-hat reports in
`.claude/doc-review/`) collected **91 findings** in 14 clusters, and the fix pass closed every one as
fixed or dismissed-with-reason. Both blockers were real and are gone: the notation glossary's
``\lvert k\rvert`` row (literal `|` characters eaten as GFM column delimiters, so the row fragmented
in the built HTML and ``\kappa`` was never defined despite pervasive use — a third instance of the
hazard the table rule already names, now swept corpus-wide by a code-span parser and found to have
exactly that one member), and the six public statistics rendering under the Reductions page's
"Internal API" heading (fixed with a `nameof`-filtered `@autodocs` pair, since they are deliberately
not re-exported and a bare `@docs mean` cannot resolve). The anchors independently re-derived and
**confirmed the core spectral and structural mathematics sound** — every finding was formatting,
staleness, notation, or completeness, none a math error. The two hats that overran the 64k output cap
were re-run standalone and the recurrence guard is in `panel.js` (`599390a5`). Judgment calls worth
knowing: the ``\hat a`` unit-vector introduced by the decision-42 edits was retired in favour of the
explicit ``(a a^{\top})/(a \cdot a)`` the operator actually computes (the hat means *spectral
representation* package-wide and cannot move); the Parseval multiplicity ``\alpha(k)`` **kept** its
glyph against invariant 10's accumulation ``\alpha``, resolved by a Notation-page gloss rather than a
rename, because the two are distinguished by the mode argument and every site already glosses it; the
example's bold ``\mathbf{k}`` **stays**, now declared as a local override (italic ``k`` is the
turbulent kinetic energy there); and §13 decision-log mentions of the retired `_guard_noalias!` stay
as history, only current-state surfaces being reworded. One finding was a coverage gap rather than a
docs defect and is fixed in the suite: decision 40 gave `helmholtz_projection!` a gated CPU loop, so
the `with_threading` toggle reaches it and `test/threading.jl` now asserts it bitwise there (the
assertion had stayed in the KA testset, where the docs still claimed it belonged). **That C6
assertion was VACUOUS when added and was fixed by decision 47:** decision 42 had already severed the
gated loop from dispatch (it dropped the kernel's squared-wavenumber arguments but left the loop's
signature stale, so the arity no longer matched and CPU helmholtz fell through to the
override-ignoring KA-on-CPU launch), so the `with_threading` toggle reached nothing and `bitwise`
compared a path against itself. The canary lane caught the resulting slowdown; the fix restored the
loop and added a dispatch-target guard so a device-kernel/gated-CPU-twin pair diverging is caught at
test time, not in a later benchmark.

**The docstring-template uniformity pass is CLOSED (2026-07-24).** The `/check-consistency` panel's
`structure-consistency` hat filed 20 findings; the consolidated summary compressed 19 of them into one
parenthetical, so the first fix pass closed only its blocker. All 20 are now closed — **18 fixed, 2
dismissed with reason** — under four user-decided shape rules recorded in the docstring rubric above
(the ≥3-arguments-or-a-keyword threshold, `The fields are` on every type with stored fields, a custom
descriptive title on every admonition, and the verbatim in-place steer). Commits `5c238029`,
`7229de78`, `878d0af1`, `b41de4fe`, `0db08c87`, `a7b88ab2` and the closing one.

**The two dismissals.** Finding 10 asked the `dot`/`cross` wrappers to shed their
representation-validity prose, but the cross-referencing rule says a function's validity/absence
clauses *always* stay — only a re-derived formula is cut — and invariant 1 makes those clauses
load-bearing, a deliberate absence having to be visible where a user meets it. Half of finding 13
asked `DifferentialOperators`/`Convolution` module bullets to match their page section headers, but
the rubric *mandates* math-grouped pages under hand-written headers, so a module listing operations
while its page groups them by family is the design.

**Two scope corrections worth keeping.** Rule 1 reaches ten docstrings, not the ~17 a naive classifier
suggests: arity counts what a signature takes rather than the distinct names across type-specialized
overloads (`norm!` takes two in all three of its), and a thin allocating wrapper documents no arguments
at all. And finding 12 is half-applied on purpose — Interpolation's `# API` header really was unique
and is gone, but its `# References` block stays, that being the citation policy's own docstring form.

**Open items are tracked here, never as hidden comments in the rendered docs.** Every `docs/` rationale
doc is Documenter-rendered, and an **inline HTML comment there leaks as visible escaped text** (verified
2026-07-05: `<!-- … -->` rendered literally on the page) — so a TODO lives in this file, and a placeholder
that must appear in a rendered doc is written as *visible* text and resolved by confirmation, never by
guessing. (The one past instance — decision 19's "Grafakos, Thm 2.5.x" theorem-number placeholder — was
resolved 2026-07-15, confirmed as Thm 2.5.10 against the user's copy.)

**Mathematical correctness is its own check — distinct from formatting.** A sentence can be perfectly
formatted, perfectly glossed, and still **false**. So every mathematical/definitional claim in the docs
must be **true and precise**, checked on its own. Guard especially against: **category/type errors** (a
vector space equated with an integer — "the fiber *is* the tensor order" was exactly this; an operator
conflated with its parameter; a representation with the object; **an operator's domain/codomain left
unchecked** — verify *which spaces* a map acts between, the fiber included, not only scalar formula values:
the `𝟙`/`W` transfer slip wrote the section space `ℝ^N⊗V` as `ℝ^N` (flattening the fiber) and conflated the
grid all-ones `𝟙_N` with the point `𝟙_M`, a structural error the value-check missed because it verified
formulas, not spaces); **imprecise equalities / normalizations**
(FFT/Parseval factors, a missing ``1/N``, adjoint relations); and **overclaims** ("exact"/"all"/"never"
that aren't literally true; bounded-vs-unbounded multiplier confusions; continuum-integral vs
discrete-sum). When unsure, verify against the implementation and a standard reference. **Run this as a
positive verification, not a read-through** — a false-but-plausible statement is as invisible as an unbound
symbol: enumerate every formula, normalization constant (the `1/N`, `1/N²`, `2π/L`, Parseval factors),
adjoint/transpose relation, and quantifier, and verify EACH independently against the implementation (read
the code, quote the line) or a derivation, noting how. The §10 `⟨Wf,q⟩ = ⟨f,Wᵀq⟩` slip — clean only for the
measure-adjoint `ι_*`, but off by the `N/M` measure factor for the implemented (counting) transpose under
the *normalized* inner — was exactly such a plausible-looking equality: a read-through passed it, a
code-check (`inner = dot/_base_count`) caught it. **The lightweight way to run this:** write the statement
formally on scratch — every object typed, the types taken from the code — and expand it; if it won't type,
or an equality won't expand-match, the prose is imprecise. The nontrivial statements live formally in
`docs/FORMALIZATION.md`; check each prose claim **against its entry** — the chain is *prose ↔ formalization ↔
test* (the prose must agree with the typed statement, the statement is verified against the code, the linked
test enforces it numerically) — and treat a nontrivial claim with **no entry**, or an entry with **no test
link**, as a coverage gap. Hand-verified typed notes, not a
proof assistant.

**Doc-edit checklist — run ALL FIVE on every documentation change (most strictly on `ARCHITECTURE.md`):**
**(1) Correct** — every claim mathematically true and precise (no category errors, normalization slips, or
overclaims); **(2) Self-contained** — **every** symbol is *bound* to its meaning in plain language at
first use, the elementary working ones included (`f` the field, `x` a position, `q` a per-point value,
index letters), not just the exotic; a concept *mentioned nearby* (a function argument, a passing noun)
is **not** a binding, and a self-contained sweep must not be scoped to a hand-picked symbol list that
skips the basics (how `f`/`x`/`q` slipped through a review). **Run this as a positive enumeration, not a
read-through** — an unbound symbol is invisible by omission (the eye supplies a plausible meaning and moves
on), so *list every distinct symbol, sub/superscript, operator name, and bold/blackboard letter in the
passage* and, for each, quote the clause that binds it; a symbol with no citable binding **is** the defect.
**The same defined-or-linked bar binds *terms of art*, not only symbols** — a noun that names a package
concept (an *assignment*, a *section*, a *cutoff*, "the destination's length") must be explained in a clause
on the page or `@ref`-linked, never left correct only to a reader who already holds the module's context;
the acceptance test is the *cold read* (see the operation-family rule below). Reading-to-notice missed exactly this class — the unbound all-ones `𝟙`, the `⟨·,·⟩_pts`/`⟨·,·⟩_grid`
inner-product measures, and the `sample`/`eval` operators all *looked* like ordinary math; **(3) Formatted —
bidirectional** — math is LaTeX and **never** backticks (the `E = B × V` slip; and ASCII-only math like
`S = J*` — single letters joined by `=`/`*`/juxtaposition — which carries no math glyph, so it evades a
glyph grep *and* reads as code: catch this class by **reading**, not grep), **and** every code identifier —
functions, types, **module names** (`FieldAlgebra`, `DifferentialOperators`, …), struct fields — is **always**
backticked and **never** bare (the bare-`FieldAlgebra` slip); check *both* directions (a backtick span must be
greppable in `src/`; a code name must never sit in plain prose); **(4) Current** — no stale claims; statements
match the code's present state, **and complete** — a docstring/summary that names only a *subset* of what
the code now provides is stale even if every sentence is literally true (the Interpolation module docstring
said "uses the local spline interpolation" after the spectral `DirectDFT`/`NUFFT` schemes shipped; the
umbrella docstring listed only some of its submodules' operations), so check each module/operation/summary still names
everything added since it was written, against the current `export`s / method set; **(5) Cited** — citations follow the citation policy above (context-standard
author–year; ≤3 authors named, `First et al.` for 4+; full reference inline in docstrings and canonical in
`ARCHITECTURE.md` §References, the copies verbatim-consistent). These are the standing bar, not one-off audits.
(The formatting check is the one that has bitten twice — once each direction — so verify both explicitly.)

**A flagged instance is a sample of a class — fix the class, not the line.** When a check (or the user)
catches one defect, treat it as evidence of a *pattern*, not a lone typo: characterize the class and
**sweep every doc surface for it** — `ARCHITECTURE.md`, every module and operation docstring in `src/`, and
the `docs/src/` pages — by grep or per-section enumeration, then fix all occurrences in one pass and report
the class and the count. Fixing only the pointed-at line and waiting to be handed the next instance is the
failure this rule exists to stop (across one review it happened repeatedly — the §10 symbol bindings, the
indented tables, the unbound symbols — each patched singly while the rest of the class sat untouched).

**"Check the docs" = the complete battery, never one check or one file.** When asked to check / review /
audit the docs (in any words), run the FULL matrix in one go: every check above (the five-point checklist +
the notation/structure rules) across every surface — `ARCHITECTURE.md`, `FORMALIZATION.md`, `TESTING.md`, `PERFORMANCE.md`,
every `src/` docstring, and every `docs/src` page. The `/check-docs` command (`.claude/commands/check-docs.md`)
encodes this exact protocol; running it — or the equivalent surface-parallel fan-out — is the default
reading of the request. Do **not** run one check, sweep one file, then stop and wait to be asked for the
next; report the matrix (surfaces × checks: findings, fixes, and what is verified clean). This rule exists
because the checks were repeatedly run one-at-a-time, surface-by-surface, across one review. **Cheap
(economy) scan lanes are the DEFAULT — full-strength lanes only on explicit request — and the fix
phase always completes at full strength in the main thread, closing every finding as fixed or
dismissed-with-reason in the same run; every mode ends with zero open findings (policy 2026-07-23,
after the 2026-07-22 economy run deferred its judgment tail). The same cost policy governs
`/check-consistency` (the 12-hat rendered-docs panel): economy is the default — ten hats on the
cheap scan model, the two mathematician hats (`spectral-methods-mathematician`,
`differential-geometer`) anchored at full strength, because a cheap hat's false positive is caught
by the main-thread verification but a subtle-math false negative has no downstream verifier;
verification/consolidation/fix are never economized; **a fix pass is driven from the banked per-hat reports, never from the consolidated summary** — consolidation is lossy by design (the 2026-07-24 run buried 19 of one hat's 20 findings in a parenthetical and downgraded another hat's major contradiction to "soft"), so the summary is the user's reading artifact and the `NN-*.md` files are the work list, closed by finding number and a hat's own severity respected; `strength: "full"` only on explicit request.**

**The review unit is the operation's whole variant set and the cold read — the two defects a per-docstring pass
structurally misses.** Every check above runs *inside* one docstring (is each symbol bound? each formula
true? each name backticked?), so two classes slip through by construction — one *relational*, one
*audience-relative* — and both bit this session. **(1) Variant-pair drift.** One operation is documented
across several bindings — the allocating `f` and the in-place `f!`, a getter and its `set_…!`, sometimes a
physical and a spectral generic. The *operation's* defining math (the componentwise formula, the spectral
kernel) has **one home** — the primary binding: the `!` form for the spectral operators (it owns the
kernel), the getter for a getter/setter (it owns the meaning) — and every other variant is a **thin wrapper
that leads with the one-sentence physical meaning, names its result intrinsically, and `@ref`-links the
home**, carrying no second copy of the formula (`gradient` → *"Allocating form of [`gradient!`](@ref):
allocate the result and return it. A scalar field gives its gradient vector field ∇φ; a vector field u gives
∇u. See `gradient!` for the componentwise definition and the spectral kernel."*; `set_threading_cutoff!` →
*"Set [`threading_cutoff`](@ref) to `n`…"*). This is "one concept, one home" and the cross-referencing
*at-home test* applied to the **generic pair** — the site nobody audits, because each string reads fine
alone; it *reconciles* with "physical-meaning-first outranks DRY" (the wrapper keeps the one plain-meaning
sentence, sheds only the *re-derivation*). Typed twice, the math **drifts** — the allocating operators wrote
the partial as `\partial_i` while the `!` forms wrote `\partial_{x_i}`, the "one notation per concept" rule
broken *across* the pair and invisible to a within-string sweep. **Guards:** the wrapper of each `f`/`f!` and
getter/`set_…!` pair must carry **no** display formula and **must** link its home; and a banned-variant grep
(bare-index `\partial_[ijk]` empty; canonical `\partial_{x_i}`) is **build-enforced** by `docs/make.jl`'s
`lint_notation_variants()`. **(2) Cold-reader opacity.** A docstring can bind every *symbol* (passing
*Self-contained*) yet be unreadable to someone who has not read the module, because its **terms of art are
nouns, not symbols**: `threading_cutoff` said "the element count at or above which an *assignment* is split"
— every word defined *elsewhere*, none on the page. Extend the defined-or-linked bar from symbols to
**nouns** (checklist (2)): the first sentence says what the thing *is* in plain words, and a term naming a
package concept is inlined in a clause or `@ref`-linked on first use. **Acceptance test — the cold read:**
parse the docstring with the module's context withheld; a noun that silently assumes you already know the
package is the defect. Both are family/context properties, so neither guard is another per-string grep —
`/check-docs` adds a lane that **groups each operation's generics and diffs them** and a lane that **reads
each exported docstring in isolation**; when one instance surfaces, sweep the *class* across every family per
"fix the class, not the line".

**A Literate example (e.g. `examples/HIST_CPU.jl`) IS a rendered doc page — sweep and verify it like one.**
Every **full-line `# ` comment becomes Markdown prose** on the built page (only inline `# …` after code on the
same line, and `##` double-hash lines, stay as code comments). **"Full-line" includes INDENTED comments inside
a function body** — a 2-space-indented `# …` on its own line still renders as prose, so the driver's internal
step comments are rendered too (Literate strips the indentation). One consequence bit this page: a full-line
comment **inside a control-flow block** (e.g. the first line inside an `if`/`for`) splits the code fence and
strands the block header from its body. For a comment that must stay *in* the code — inside control flow, or
any implementation note you don't want rendered — use `##` (Literate keeps it as a `#` code comment, math-glyph
exempt) or make it inline after code; reserve full-line `# ` for genuine narrative prose at statement
boundaries. So **all math in the prose comments is rendered and must be LaTeX** — double-backtick inline,
```math``` display — exactly as in `ARCHITECTURE.md`. **Two forbidden
failure modes, both found littered across this page:** (a) bare **Unicode glyphs** in prose (`Re_λ`, `λ ≪ L`,
`∇·u = 0`, `exp(−νk²Δt)`) render as literal text, not math; (b) **math wrapped in backticks** — backticks are
ONLY for a **code identifier that actually appears in the code** (a function/type/field/file name), so a
*formula* in backticks (`` `exp(−νk²Δt)` ``, `` `|k|²` ``, `` `½⟨|u|²⟩` ``) is a lie: it renders as monospace
code yet names nothing in the code. Convert BOTH kinds to LaTeX; keep backticks only for real code names. And an
**underscored identifier in prose must be backticked** (`` `n_spinup` ``), or Markdown parses `n_spinup … n_stats`
as an *italic* span across the underscores.

**Verify a doc edit by BUILDING the page, not by eyeballing the diff.** After editing a Literate example,
regenerate it (`Literate.markdown(src, out; documenter=false)`) and grep the OUTPUT prose for Unicode-math
glyphs and backtick-wrapped formulas until the count is **zero** — the built page is the source of truth for
what renders. The example page is a "check the docs" surface: the battery above (and `/check-docs`) must build
and grep `examples/*.jl` → markdown too, not only `ARCHITECTURE.md` / `src/`. **This rule exists because a
LaTeX pass was once applied to only the two paragraphs the user pointed at, leaving the rest of the page in
Unicode/backtick math — the "fix the class, not the line" rule violated, and the gap went uncaught because the
rendered page was never built and grepped (only the touched paragraphs were eyeballed).**

**Demo & figure standards (the `examples/` HIST demos).** A figure presented as a *result* must come from
a **verified-stationary** flow: check the `k(t)`/`ε(t)` history fluctuates about a constant mean (not
drifting) before presenting — a structure function over a transient is biased. The band-rescaling forcing
oscillates (≈ 7-turnover period), so spin past the energy overshoot and time-average over several periods,
and keep the frozen stats-`Δt` CFL conservative (≤ 0.3) or a long, marginally-resolved run blows up (NaN →
advect crash). A **plotted reference power-law must be dimensionally complete and carry its constant** —
the K41 spectrum guide is ``C_K\,\varepsilon^{2/3}\,\kappa^{-5/3}`` with the measured `ε`, never a bare
``\kappa^{-5/3}`` slope (different dimensions: ``E(\kappa)`` is energy per unit wavenumber); always check a
reference line's dimensions match the curve it overlays. Example plots use the **PGFPlotsX (LaTeX)
backend** with the amsmath/newtx preamble and `LaTeXStrings` `L"..."` labels (never Unicode glyphs or
backticks), **clean lines, no markers** — and `pgfplotsx()` is activated at **top-level / include time**,
not inside the plotting function (else a world-age error: the figure's backend object stays `nothing`,
surfaced as a cryptic `was_shown` `FieldError`); on a log axis skip the `r=0` / `τ=0` point. Turbulence
notation follows Pope: `k` = turbulent kinetic energy, `κ` = wavenumber magnitude, `E(κ)` = spectrum —
kept distinct (the integrating factor is `ℰ`, the RK stages `N̂₁`/`N̂₂`).

**Markdown tables must be top-level — never indented inside a list item.** Documenter (CommonMark.jl) will
not form a GFM table inside an indented list item; it falls back to literal text (the pipes and `---`
render verbatim, rows mashed). Inside a list (e.g. an `ARCHITECTURE.md` §13 decision entry) use a **nested
bullet list** instead, and keep literal `|` out of cells (a `|` — even inside ``…`` math, like a norm/abs
bar — is counted as a column delimiter). Bit twice: the decision-18 and decision-19 tables. Grep guard:
`grep -rnE '^[[:space:]]+\|[-:| ]+\|' docs` must return nothing.

**One notation per concept — and one concept per notation.** The self-contained check guards that every symbol
is *introduced*; it does **not** guard that a concept has only *one* symbol. Before introducing a math
symbol, check it isn't a synonym for one already in use. If an abstract operator and its matrix (or a
continuous vs discrete form) genuinely both appear, name each one's distinct role **once** and stop — one
object wearing three symbols (the `W`/`𝓘`/`ι` interpolation tangle: matrix, operator, and pullback all
for the same map) is the failure mode. It is easy to *create* this when an edit adds new notation (here,
`ι`) without retiring the old (`𝓘`), so when an edit introduces a symbol, grep the doc for any existing
symbol denoting the same thing and reconcile them. **Run the rule the other way too:** a single glyph must
not carry two meanings in one section. When you introduce a symbol, grep the section for the glyph and
confirm it is free — `β` meaning both the `mul!` accumulation scalar *and* the spline stencil weight, and
`p` meaning both the point index (`xₚ`, `Σₚ`) *and* a polynomial (`p ∈ Πₘ`), were the failure mode (fixed by
yielding the local use: stencil weight → `w`, polynomial → `φ`). A package-wide convention that cannot move
(the α/β accumulation, invariant 10) keeps the glyph; the local use renames.

**Prefer coordinate-free notation (a check).** State maps and pairings **intrinsically** — operators (the
pullback `ι*`, the pushforward `ι_*`, `W`/`Wᵀ` as maps) and the measure pairings as honest sums/integrals
(`Σ_p a_p·b_p`, `∫_Ω f·g dx` — concrete *and* coordinate-free in spirit; keep these, they are preferred).
**Avoid coordinate/matrix machinery that buries the bundle structure:** the dense matrix of a section-level
map (`W_{pn}`), an all-ones vector `𝟙`, a mass matrix, or flattening a section space `ℝ^N⊗V` to `ℝ^N`
(which hides base vs fiber). **Carve-out:** component notation for the genuine *fiber* tensor algebra is
fine — the fiber has a canonical global frame and a `FiberTensor2` really is a 3×3 matrix, so
`(Au)_i = A_{ij}u_j` is the clearest form; the rule targets *section/base* flattening, not the fiber. If a
basis/matrix form is genuinely needed (e.g. to mirror the code), state the basis **and** the space it acts
on, kept as a clearly-marked shadow of the intrinsic object. This is **also a correctness guard**: the
`𝟙`/`W_{pn}` transfer picture passed the binding and formula-value checks yet was structurally wrong (the
fiber flattening + the `𝟙_N`/`𝟙_M` conflation above) — a coordinate-free lens catches what a value-check
cannot. (`docs/FORMALIZATION.md` is the **sanctioned home** for the coordinate/matrix/component expansions —
exempt from this preference, since *checking* precision requires expanding into components, but **not**
exempt from correctness.)

**One concept, one home; everywhere else links.** Explain each idea in the single section that owns it;
every other mention is a one-line hook + a `[…](@ref)` / §-link, never a re-derivation — and a diagram
lives with its topic, not in a group-by-form bin. In `ARCHITECTURE.md`, §2 is the overview/**map** (the
bundle foundation + a linked one-liner per part); §§3–12 own the details (each part of the map has a body
section); §13 is the append-only decision log, self-contained by design (its overlap with the body is
intentional — do **not** dedupe it against the body).

**Cross-referencing — discriminating-minimalist; a link earns its place.** Live Documenter `@ref` links are
the encouraged way to point across the docs (a mistyped `@ref` fails the build, so it cannot rot), but
**backtick every code identifier and promote to `@ref` only where a reader would genuinely jump and there is
one clear destination**: (1) link a target **at most once per docstring** (its first genuine mention); (2)
**never** link the docstring's own binding, its argument names, `Symbol`/option tokens, struct fields, or
`Base` names; (3) a **family** of built-ins (the spline schemes, the reductions) is **one** catalogue
destination, not five — name each member in plain backticks and `@ref` the default; (4) **at-home test** —
if a sentence would sit equally well in the *target's* own docstring, cut it and link (the function's own
defining formula and its validity/absence clauses always stay — physical-meaning-first outranks DRY). **No
dead references on the user-facing surface:** a rendered docstring or a thrown error must not cite a
`§`-number or a repo path (those live in `#` comments, `CLAUDE.md`, and the design docs, which cross-cite
freely); a docstring must read **complete at the REPL**, where links are dead — a link adds depth one hop
away, never a fact the reader needs.

## Verification workflow

**Consent gate (user-directed 2026-08-04) — unasked, run ONLY `Pkg.test()`.** Every other verification
lane is expensive in wall-clock and in machine occupancy, and the decision to spend that is the user's:
the **exhaustive survey** (`test/exhaustive/`, 75–115 min), the **benchmarks** and the **canary lane**
(`benchmark/`), the **GPU suites** (`test/gpu/*`), **`/check-docs`**, **`/check-consistency`**, and any
multi-agent fan-out each require explicit consent **before** being started. The correct output when one
of them would be informative is to *name it and its cost* — "the survey would confirm this, ~90 min,
shall I run it?" — and wait. This is a consent boundary, not licence to leave work unfinished: finish
the code, run `Pkg.test()`, and report what remains unverified and why. It also protects measurement,
since a long unasked run occupies the box that `docs/PERFORMANCE.md` §1 requires to be idle.

Before adding or changing tests, read `docs/TESTING.md` — the testing philosophy and
the per-operation coverage contract. Its §4 now carries the explicit **coverage-axes list**
(the denominator over which "exhaustive" is defined: representation, R, eltype-on-CPU, layout
fold, parity, cubicity, length anisotropy, origin, degenerate bases, the α=0/β≠0 branch,
aliasing patterns, Nyquist content, backend, threads); a new type parameter or admissible input
region adds its axis row and its suite lane in the same change — an axis missing from the list
is exactly how the decision-41/42 bugs stayed invisible. Before optimizing or benchmarking, read
`docs/PERFORMANCE.md` — the performance model, best practices, recorded findings, and the
benchmark coverage contract.

### Definition of done — for a new or changed operation/feature

These four are **systematically forgotten** — treat the feature as unfinished until each is
explicitly checked (not "should work", *done and verified*):

1. **Correctness tests** — a CPU behaviour test against an *independent* oracle (analytic or
   hand-computed), over both element types and both bases where applicable, **and GPU parity**
   in `test/gpu/suite.jl` (device-vs-CPU under `allowscalar(false)`). The `docs/TESTING.md` §4
   coverage contract is the spec — and for an in-place `!` operator that includes an `@allocated`
   assertion in `test/allocations.jl` (invariant 13: allocation-free, measured on the CPU; a deliberate
   materializer gets a bounded guard instead) **and a `test/pass_audit.jl` row** (decision 36: exact
   per-array element reads/writes measured via the `CountingArray` harness, frozen beside the fused
   ideal, a named holder for any gap — the layer that catches an unfused recompute, which every other
   layer passes; `PASS_AUDIT_PRINT=1` regenerates). A new **public value-returning** operation also
   needs its `test/oracle_registry.jl` classification (decision 55) — and if the honest answer is
   `:relational`, that is a finding to close, not a label to record.
2. **Performance test** — a benchmark in the matching `benchmark/` class (a new `add_<class>!` +
   wiring into `benchmarks.jl`/`report.jl` if it is a new class), per the `docs/PERFORMANCE.md` §5
   benchmark coverage contract. Run it; regenerate `benchmark/RESULTS.md` when practical.
   **A benchmark run owns the machine** (`docs/PERFORMANCE.md` §1): nothing else on the host while it
   runs — no `Pkg.test()`, no docs build, no second lane, and never a foreground job alongside a GPU
   sweep. A device benchmark is host-bound at small grids, so competing work inflates it by a roughly
   fixed amount per case; check `uptime` and GPU utilisation first and wait for an idle box rather
   than measure into a busy one. **And always ANALYSE the run, never merely report that it finished**
   — diff against the previous archive, say which operations moved and in which direction, and
   explain every systematic movement before naming a cause. Two discriminators do most of the work:
   an *additive* penalty (constant in absolute time, its ratio collapsing as the grid grows) is
   overhead rather than arithmetic, and a real regression shows up on **both** backends over the same
   commit range, not one. An unexplained uniform shift is a measurement artefact until proven
   otherwise — usually contention, and on this project it has never once been the driver.
3. **The four guiding docs** — `docs/ARCHITECTURE.md` (a decision-log entry **and** the relevant
   section), `docs/FORMALIZATION.md` (a typed entry for any nontrivial new/changed statement — re-verify
   the expansion against the new code, link its test), `docs/TESTING.md` (§2 layout + §7 coverage), and
   `docs/PERFORMANCE.md` (model + coverage/gaps), as applicable. They are the spec, not an afterthought.
4. **The rest of the docs + this file** — the API page (`docs/src/api/…` and `make.jl`
   modules/pages for a new module), the `docs/src/index.md` / `docs/src/api.md` module lists, and
   **`CLAUDE.md`** itself (the module list, include order, roadmap, and test summary).
5. **The BENCHMARKS, BUILT AND RUN — not just the class you touched.** Decision 60 broke two of the
   six classes and nothing noticed for three days: `benchmark/reductions.jl` failed to **build** (its
   `weighted_inner` weight was the deleted `squared_wavenumber_field`, so the whole class contributed
   zero rows), and 7 of 19 `benchmark/convolution.jl` rows failed to **run**. Note the two-stage
   failure: `@benchmarkable` only *stores* its expression, so the suite BUILDS clean and every one of
   those rows still errors at run time — building is not a check. The cheap gate is a tiny-grid sweep
   that runs every row once (`samples = 1, evals = 1` at `16³`, seconds not minutes), which needs no
   idle machine and is not a measurement, so it does not violate the owns-the-machine rule.
6. **The examples, RUN — `julia --project=examples examples/HIST_CPU.jl --smoke`** (and the GPU twin
   `examples/gpu/rocm/HIST_ROCm.jl` where a device exists), for any change to the public surface. The
   `examples/` demos are consumer-shaped code that is both a rendered doc page and a downloadable
   script, and **nothing else executes them** — not `Pkg.test()`, not the docs build, which renders
   `HIST_CPU.jl` through Literate without running it. That gap shipped two broken demos at once
   (2026-08-04): decision 60 stopped a field in spectral representation from being a kernel, and both
   demos were still passing a `ScalarFieldSpectral` to `convolve!`, so each threw a `MethodError` in
   its own time-stepping loop; the CPU one had additionally been multiplying by a `ws.Ek` buffer that
   an earlier `exponential_convolve!` refactor left allocated, zeroed and never filled. Every layer
   the project has — the gate, the pass audit, the survey, the docs build — passed throughout, because
   an example is the one shipped surface none of them touch. A static check cannot close this: the
   defect was a call that no longer dispatches, not a name that no longer exists, so only running it
   finds it. The `smoke()` preset exists for exactly this and costs a few seconds of simulation.

Grep the docs for stale "deferred/none-exist/future" claims about whatever you just implemented —
those are the usual rot. Then the mechanical bar:

"Should work" is not done. Minimum bar for any change:

- Load: `julia --project -e 'using GBGPeriodicFields'` (catches `@eval` and wiring errors).
- Method parity after codegen edits: compare per-generic `methods(f)` counts
  against the committed baseline (`test/method_parity.jl`). Full M2+M3 surface is
  **206 public methods** (e.g. `*` 28, `mul!` 30, `dot`/`dot!` 10 each, `add!` 14, `combine!` 2, `tr` 2, `det`/`det!` 1 each).
- Ambiguities: `test/method_parity.jl` runs `detect_ambiguities` (from `Test`) over
  the whole package — the explicit `multiply!` quartet exists precisely to resolve
  these. `test/aqua.jl` runs `Aqua.test_all` for broader package checks (type piracy,
  compat bounds, stale deps, unbound type parameters, …).
- `julia --project -e 'using Pkg; Pkg.test()'` (the `test/` suite now exists; keep it green).
- **`Pkg.test()` is a GATE; `test/exhaustive/` is a SURVEY** — the split that decides where a new test
  belongs (`docs/TESTING.md` §1). A gate re-checks claims we already know and must be green or the
  change does not ship; a survey searches for combinations nobody enumerated and is *read*, not passed.
  So: a **specific** oracle and every **completeness guard** go in the gate (a guard must fail the
  moment an operation arrives uncovered, which an occasional run cannot do); a **universal** oracle over
  a **product** goes in the survey; and anything that may legitimately be **non-green** must go in the
  survey, because a suppressed failure reads as a pass and is worse than an absent test. The lifecycle
  joins them: the survey discovers, a fix lands, the gate pins it forever. (The GPU suite and the
  benchmarks are opt-in for an unrelated reason — hardware, and a quiet machine.)
- The **exhaustive suite** is opt-in and separate too: `julia -t4 --project=test test/exhaustive/runtests.jl`
  holds the full Cartesian product and is run occasionally, like `/check-docs`, not on every change. It
  is a **report**, not a gate — it runs blind to the package's decisions, prints everything that does
  not work, cites a decision beside a known gap rather than suppressing it, and names the combinations
  it could not construct so its silence is never mistaken for a pass. Exit `0` clean, `1` a quality
  finding, `2` a correctness finding or a harness problem. **75 minutes over 96 configurations**,
  measured with `-t4` on an idle host (element type × 4 grid shapes, one odd on every axis × **3** layout folds ×
  threads × **2** seeds × a shifted origin). Run it with `-t4`: the thread-invariance check is gated on
  `Threads.nthreads() > 1`, so without it that axis is dead and half the configurations are duplicates. Run it from `test/gpu/cuda` or `test/gpu/rocm` to cross the backend axis, and from `test`
  (which carries `HDF5`) to reach the persistence pair.
  Its lanes, and the property each rests on:
  - `invocations.jl` — the operation domain is **derived from the method table**, not listed: every
    package-owned method's parameter slots are filled from a canonical pool and `applicable` settles
    which combinations are real calls. All **112 public operations** are reached.
  - `checks.jl` — five universal properties over every invocation (preservation, structural, metadata,
    determinism, type-stability), the ones whose oracle does not depend on what the operation computes.
  - `values.jl` + `references.jl` — an **independent value oracle for all 112 operations**, each written
    from the operation's *documented* definition over raw arrays, so a disagreement indicts either the
    code or the docstring. The transforms use a literal DFT sum; persistence is read back with the raw
    HDF5 API, because `read_field` as an oracle for `write_field` only checks the pair against itself.
  - `properties.jl` — the 25 declared relations (adjointness, algebraic identity, round-tripping), plus
    representation agreement, thread invariance, allocation, ordering and numeric domain rejection.
  - `sequences.jl` — what a single call cannot exhibit: plan reuse, repeated application, round-trip
    cycling, and **n-step allocation**, which is the measurement invariant 13 is actually about.
  - `pools.jl` — the context-mismatch product, its axes read out of the compatibility predicates' own
    lowered IR.
  - `selfcheck.jl` — **the harness checked against itself**: every universal check is driven against an
    operation built to violate it, and a check that does not fire is a failure. This caught a *vacuous*
    check — `result_type` asked whether the result matched inference, which `Base.return_types` makes
    unfalsifiable, so 85008 "clean" cells meant nothing. It was replaced by type-stability.
  - `ledger.jl` — every `(operation × check-type)` cell, applicability **derived** from each operation's
    name, method table and lowered IR.
- GPU tests are **opt-in and separate** (not part of `Pkg.test()`): per-backend
  environments under `test/gpu/` (`rocm/` and `cuda/`) run a backend-agnostic
  suite with scalar indexing disabled. Run on a machine with a device, e.g.
  `julia --project=test/gpu/rocm test/gpu/rocm/runtests.jl` (see `test/gpu/README.md`).
- Benchmarks are **opt-in and separate** too (not part of `Pkg.test()`): the `benchmark/` suite
  (`docs/PERFORMANCE.md`). For a perf-relevant change, run `benchmark/runbenchmarks.jl` and `judge`
  against a saved baseline before/after — and confirm on the GPU, since platform optima diverge.
- Consult `Project.toml` for dependencies and versions; do not assume.

## Current state and roadmap

1. **Fields.jl** — refactored, done and test-covered (`test/fields.jl`): compatibility
   predicates; `FieldSpectralMultipliers` moved here (explicit six-array constructor +
   convenience constructor from a field; host-built wavenumbers copied to backend).
   The transform input contract is invariant 11.
2. **FieldAlgebra.jl** — **done** (full public surface): M2 (add/subtract, the weighted
   combination `combine!`, real scaling, scalar-field multiplication) + M3 (dot, cross, tensor-vector and
   tensor-tensor `mul!` with α/β, transpose, tensor inner products, norms,
   sym/skew/dev, trace, determinant) generated, loading, and verified — **206 public methods** (the
   pre-refactor surface plus the trace `tr`/`tr!`, the combination `combine!`, and the determinant
   `det`/`det!`; parity baseline locked in
   `test/method_parity.jl`), zero
   ambiguities, behaviour tested in `test/fieldalgebra.jl`. Fiber ops use full
   **StaticArrays** (a package dependency — `StaticArraysCore` gave only the types).
   `mul!` keeps the LinearAlgebra no-alias contract; cross and the unary
   index-shuffles (transpose, sym/skew/dev) are alias-safe by construction (decision 39).
3. **DifferentialOperators.jl** — **done**: the duplicate `FieldSpectralMultipliers`
   and its helpers removed and imported from Fields, export dropped, and the umbrella
   now re-exports the Fields version (verified: every Fields export surfaces as the
   same object through the umbrella). Operators tested by analytic round-trips in
   `test/differentialoperators.jl`. The old five-argument
   `FieldSpectralMultipliers(grid, layout, k1, k2, k3)` constructor is gone by design —
   use the field convenience constructor or the explicit six-array form. The fused
   `symmetric_gradient`/`!` (the symmetric part of `∇u`, the peer of `curl`, skipping the full gradient;
   decision 27) was added, tested by the `sym(gradient)` equivalence + analytic diagonals (incl. the
   anisotropic box) + GPU parity + allocation-free. **Decision 32 (IT audit items 1+6):**
   `helmholtz_projection!` rewritten as the one-pass KA kernel (aliased in-place call guard-free and
   bitwise-equal; 2.7–6.5× the three-broadcast form), and the kernel-composed arities
   `helmholtz_projection!`/`divergence!``(dest, f, mult, kernel[, α, β])` added (fused
   operator-then-convolve, the product of symbols; `curl!` deliberately excluded — no consumer) —
   tested by fused == sequential equalities, the α = −1 sign fold, kernel aliasing, allocation pins,
   and GPU parity.
4. **Tests** — `test/` suite (`runtests.jl` + per-module files + `test/Project.toml`;
   `Pkg.test()` green, **6179 tests** across 92 top-level testsets, identical at `-t1` and `-t4`; threaded lane `JULIA_NUM_THREADS=4`; the opt-in GPU parity suite is **352** on both backends (CUDA measured 2026-08-05, ROCm 2026-08-06). Every one of these three counts has been found stale by the first measurement taken after a gap — the CUDA figure sat at 328 while ten tests were added, and the CPU figure sat at 4745/72 through the exhaustive-survey work that carried it to 6179/92, drifting by 1434 in the same sentence that observed the CUDA drift. A count nothing asserts is not a fact about the suite; it is a fact about when it was last typed, so re-measure rather than cite these). `test/fields.jl`: FFT round-trip, multipliers vs
   `fftfreq`/`rfftfreq`, Nyquist behavior, validation, transform input-preservation. The
   **permuted-layout lane** (decision 41) spans the suite: `fields.jl` (round-trip + both
   multiplier families under odd and even permuted folds), `differentialoperators.jl` (analytic
   operators), `convolution.jl` (the translation kernel's folded-axis Nyquist oracle),
   `transfer_spectral.jl` (`DirectDFT`/`NUFFT`), `reductions.jl` (Parseval/shell/weighted +
   `radial_correlation`), and `hdf5.jl` (`fft_dims` persistence). The **coverage-axes closure
   lane** (decision 43) spans ten files: `coverage-axes closure` testsets in `fieldalgebra.jl`
   (α=0, aliasing both directions, the tensor-constant `mul!` quartet, the reversed/subtract
   constant family, permuted-fold representatives), `convolution.jl` (builders + the lazy
   exponential off the default box, anisotropic `translation_kernel`, α=0, dest≡kernel),
   `pointvalues_algebra.jl` and `interpolation_transfer.jl` (α=0, aliasing, guard wiring,
   M=0), the `hostile base` spectral-transfer testset (odd fold + anisotropy + origin, both
   verbs, R=2 NUFFT, out-of-box), the anisotropic radial + `empty base (M = 0)` reductions
   testsets (the decision-43 out-of-bounds fix), the `origin-aware sampling` fields testset,
   `adjointness.jl`'s full-spectrum lane, and the HDF5 corrupted-group paths.
   `test/fieldalgebra.jl`: M2 + M3 arithmetic and contractions in both
   representations, the weighted combination `combine!` (physical+spectral, alias-safe accumulate) and the
   determinant `det` (per-point LU oracle, spectral absence), the spectral zero-mode invariant, in-place
   forms and the aliased unary in-place calls, the
   physical/spectral symmetry of the linear field/fiber operations, and the
   intentional absences. `test/differentialoperators.jl`: gradient/divergence/curl/
   symmetric_gradient/laplacian/inverse_laplacian/helmholtz by analytic round-trips, incl. in-place
   operators, the Nyquist end-to-end split, the div(curl)=0 / curl(grad)=0 identities, the
   `symmetric_gradient = sym(gradient)` equivalence + its symmetry,
   and an anisotropic
   (2π, 4π, 6π) box exercising the 2π/L wavenumber scaling (incl. `symmetric_gradient`); the
   **kernel-composed forms** (decision 32) — fused == sequential operator-then-`convolve!` (ℙ and ∇·,
   both fiber signatures), α/β accumulate vs a hand-built reference, the α=−1 sign fold, kernel
   aliasing the destination — and the guard-free aliased `helmholtz_projection!` (bitwise-equal to
   non-aliased). `test/convolution.jl`: convolution as
   the coefficientwise product `f̂·ĝ` — the translation kernel `exp(-i kₐ m Δ) ⇔ circshift` along
   **all three axes on scalar and vector fields** (independent physical oracle); identity/scaling/cutoff
   over **scalar, vector, and tensor (R=2)** fields (the 5-D fiber broadcast); sharp-cutoff idempotence,
   kernel-composition associativity, the α/β accumulate form (incl. R=2), in-place aliasing safety, a
   **mixed-parity (8,7,6) grid** (odd axis + Nyquist), Float64/Float32, and the physical-space
   intentional absence; plus `translation_kernel` (decision 28) — the same `circshift` oracle but on a
   **random** field (which *has* Nyquist content, unlike the band-limited fields above, so the Nyquist
   factor is actually exercised; odd + even whole-cell shifts on each axis), the exact **`DirectDFT`
   evaluation at the displaced nodes** as the sub-cell oracle, an analytic displaced cosine, the
   **reality check** (a displaced half-spectrum survives a transform round trip — the inverse transform
   is the Hermitian projector, so the true-Nyquist-phase kernel *moves*), the Nyquist attenuation
   (half-cell kills `cos(4x)`; one cell flips it), unit modulus on the resolved band, composition +
   inversion, and the fiber broadcast over vector/tensor fields; plus the **lazy exponential kernel +
   kernel-composed `combine!`** (decision 33) — `exponential_convolve!` == the stored kernel via
   `convolve!` (scalar + vector), the independent single-mode eigenvalue `e^c·cos x`, α/β, the
   scale×field offset, both two-operand forms == the sequential `combine!`-then-convolve pair, the
   `b === dest` filtered accumulate, kernel-aliasing, and the physical absences. `test/interpolation.jl`: the
   point-data types. `test/pointvalues_algebra.jl`: the point-value M2 + M3 surface (incl. the determinant `det`) checked
   against per-point references, Float64/Float32. `test/interpolation_transfer.jl`: the Lalescu-spline
   transfer — interior polynomial reproduction, adjointness `⟨Wf,q⟩=⟨f,Wᵀq⟩`, conservation, α/β,
   periodicity, the weight limits (linear `m=0`, Catmull–Rom `n=1,m=1`, Lagrange cardinal basis) and
   the **bit-for-bit TurTLE `beta_n{n}_m{m}` pin**, plus adversarial corners (non-zero origin /
   anisotropic grid, on-node points, stencil-wider-than-grid, heavy atomic-scatter contention, R=3,
   the smooth `(2,1)`/`(3,2)` schemes). `test/transfer_spectral.jl`: the spectral-domain `DirectDFT`
   transfer — `interpolate` == `to_physical` at the grid nodes and **exact off-grid reconstruction** of
   the band-limited field (the divergence-free reference, scalar + solenoidal vector), `anterpolate` ==
   `to_spectral` from node samples, the adjoint relation `M·⟨Wf̂,q⟩ = N·⟨f̂,Wᵀq⟩` (R=0/1/2), α/β
   accumulate, and the physical-field intentional absence; **plus `NUFFT`** vs the `DirectDFT` oracle on
   band-limited scalar/vector fields (exact to ε), the NUFFT adjoint pair, exact off-grid reconstruction,
   α/β + tunable width/β; Float64/Float32. `test/reductions.jl`: the L²/measure reductions
   (`integral`/`mean`/`inner`/`l2norm`/`lpnorm`/`std`/`var`/`maximum`) on fields in physical representation and
   point-values vs analytic oracles (`⟨sin⟩=0`, `⟨sin²⟩=½`) and manual references, Float64/Float32,
   the `(1/N)Σ`-grid / `(1/M)Σ`-points arithmetic-mean semantics, the `integral = measure·mean`
   relation (anisotropic box), the energy identity, the **spectral zero-mode `integral`/`mean`** (equal to
   the physical reductions via the DC coefficient) with `std`/`var`/`lpnorm`/`maximum` still spectral-absent;
   the **mapped forms** (decision 30) — a constant diagonal tensor's analytic invariants (`det=24`, `tr=9`),
   the identity map reproducing the bare fiber-valued reductions, `⟨sin²⟩=½`, the
   `maximum(norm,u) == lpnorm(u,Inf)` coincidence (fused vs materializing), a random tensor vs an
   **independent explicit per-point reduction**, the counting-measure forms on point-values, and the
   spectral absence of the whole family;
   the **multiplier-weighted `weighted_inner`** `⟨f,w·g⟩` (w≡1 → `inner`, w=|k|² → the Dirichlet energy
   `⟨f,−Δf⟩`/`⟨∇f,∇f⟩`, sharp-band idempotence `‖w⋆f‖²`, f↔g symmetry; scalar/vector/tensor, two grids,
   spectral-only, physical absence), with **every kernel storage class** admitted as a weight and each
   bitwise-equal to its own materialized form, the complex-weight refusal (on a separable kernel, on a
   composition carrying it, and the `StoredKernel` exemption), and allocation pins for the three newly
   admitted classes (decision 62); plus
   `radial_spectrum` (the shell-resolved Parseval inner) checked via `sum(spectrum) == inner` over
   scalar/vector/tensor on even- and odd-Nₓ grids and the single-mode shell placement, and
   `radial_correlation` (the Wiener–Khinchin dual) checked against an **independent binned-circshift
   autocorrelation** + `C(0) == inner` (scalar/vector/tensor, even/odd grids), plus **analytical oracles**
   (constant field → E(0)=c²/C(r)=c²; cos(x) → E(|k|=1)=½) and a **random field checked directly in
   physical space**; and the **two-field co-spectra** `radial_spectrum(f,g)` / `radial_correlation(f,g)`
   (cross-power / cross-correlation, refining the *mixed* `inner(f,g)`) checked by analytical oracles
   (orthogonal `cos x ⟂ sin x` → 0; `cos x ± cos 2x` → ±½ in adjacent shells, cancelling to inner=0 —
   the co-spectrum **can be negative**), the f↔g symmetry, the g=f reduction to the single-field forms
   (bit-identical), and an **independent binned-circshift cross-correlation** on a random pair.
   `test/convolution.jl` additionally covers `spectral_band` (annular, with `spectral_cutoff` the
   `wavenumber_low = 0` case, idempotent, `|k|²` membership oracle) and the radial `|k|²` symbol
   (`radial_kernel(identity, …)` vs the analytic sum, real-valued). `test/rdf.jl`
   (decision 22 Phase 2): `assignment_window` against its ∏ sinc² formula, and the FFT pair-correlation recipe (anterpolate density → deconvolve by
   `assignment_window` → `radial_correlation` → g(r)) validated against an **independent direct O(M²)
   pair count** on a clustered point set (the clustering peak + the g→1 baseline). `test/eltype_genericity.jl`:
   a representative cross-section in Float64 and Float32, asserting element-type
   preservation. `test/method_parity.jl`:
   the full 206-method field baseline + the 122-method point-value baseline + ambiguity check, plus the
   **derived** per-module baseline of decision 53 (one frozen count per module over every function that
   module owns, so any new method anywhere moves a number — the enumerated lists name 28 generics in
   two modules and so missed decisions 48, 49 and 51 entirely). `test/metadata_sweep.jl`: a generated
   sweep asserting every field-producing operation propagates layout, grid, order and element type,
   over four folds and both element types, with order-carrying argument slots varied **independently**.
   `test/generated_analytic.jl`: closed-form oracles over a fixture family asymmetric by construction —
   every component and axis slot drawing a distinct amplitude, frequency and phase. `test/oracle_registry.jl`
   (decision 55): the recorded oracle provenance of every public value-returning operation, failing on
   an unclassified operation and on one covered only against other package operations; its domain, and
   the two ledgers', comes from `test/public_surface.jl`, which derives the public surface from method
   ownership rather than from `names` (the latter cannot see an extended generic such as `map`, `cov`
   or the field arithmetic). `test/aqua.jl`: `Aqua.test_all`
   (ambiguities, unbound args, piracy, compat, stale deps). `test/jet.jl`: JET `@test_call`
   static analysis of the public ops (filtered to package modules). `test/adjointness.jl`: operator
   adjointness and structural identities (div=-gradᵀ, self-adjoint curl, negative-definite
   Laplacian, idempotent Helmholtz projection) on randomized band-limited fields. `test/randomized.jl`:
   property-based tests — algebraic laws (vector-space, dot/cross/mul!/transpose/sym/skew/dev,
   reduction symmetry/linearity/Cauchy–Schwarz, convolution bilinearity/commutativity, div(curl)=0,
   curl(grad)=0) on random fields, point-values, and kernels over several trials. `test/allocations.jl`:
   a **comprehensive** `@allocated` audit (both element types) — the *entire* in-place `!` surface
   (spectral operators incl. `symmetric_gradient!`, the guard-free **aliased** `helmholtz_projection!`, and the kernel-composed `helmholtz_projection!`/`divergence!` arities (decision 32), transforms, `convolve!`, the lazy `exponential_convolve!` (single- and two-operand, incl. the scale×field offset) and the kernel-composed `combine!` (decision 33), and `add!`/`combine!`/`subtract!`/`mul!`/`multiply!`/`divide!`/`dot!`/
   `cross!`/`transpose!`/`sym!`/`skew!`/`det!` over physical+spectral × R=0/1/2 × field/constant/reversed × α/β, the
   point-value algebra (incl. `det!`), and the spline `interpolate!`/`anterpolate!`) allocates ~0 bytes; the hot-loop
   reductions (physical `inner`, the fused `weighted_inner`, `maximum`, `integral`/`mean`/`std`/`var`, and the **mapped forms** `mean(det,·)`/`mean(norm,·)`/`maximum(norm,·)`/`integral(det,·)` — zero bytes, guarding the three silent-allocation spellings of decision 30) do not materialize a field; and the
   documented allocators are bounded (`norm!`/`dev!`/`lpnorm`/`radial_correlation` materialize by design — `radial_spectrum` is pinned tight since decision 34 fused its staging; the
   spectral *vector* `inner` allocates only its O(N²) Parseval-correction planes — a strided-view `dot`,
   which would fuse, has no rocBLAS `dotc` method over a strided `ROCArray` view). Locks the GPU hot-loop discipline (decisions 24, 25).
   `test/pass_audit.jl`: the **element-traffic ledger** (decision 36) —
   a `CountingArray` harness measures each audited op's exact per-array reads/writes against a frozen
   fused-ideal table with named holders for gaps (the decision-32/33/34 kernels sit at ideal; the
   per-component-formula family's former gaps (`gradient!` 3×, `curl!`/`cross!` 2×,
   `symmetric_gradient!` 5×, `mul!` 3×, the scalar-kernel fiber re-reads) were retired at their fused
   ideals by decisions 38/39; the one remaining holder is the exponential ŵ fiber extrusion, priced
   as the finding-(k) hoist).
   GPU coverage is opt-in and lives
   outside `Pkg.test()` in `test/gpu/` (per-backend environments; `test/gpu/suite.jl`
   exercises the public surface (fields, the PointValues algebra, the interpolation/anterpolation transfer, convolution, and the L²/measure reductions) on device arrays across Float64 and Float32 with `allowscalar(false)`, comparing
   against the CPU result — the GPU **vendor** stacks (CUDA/AMDGPU) stay test-only; only the backend-agnostic KernelAbstractions/Atomix (used by the transfer kernels) are package deps).
5. **CPU threading** — **done** (`docs/ARCHITECTURE.md` §9): the `_assign!` primitive threads
   elementwise/fiberwise ops on CPU (Base.Threads, contiguous chunks, bitwise-identical to
   serial), routed in via the field broadcast `copyto!` and the kernel assignments (codegen
   `_to_broadcasted` + the `@_assign!` macro); FFTW threads match Julia's at load (`__init__`).
   Hybrid policy: on when `nthreads() > 1` above a `2^14` cutoff, with a `with_threading`
   ScopedValue override; GPU stays on the `materialize!` fallback. **The execution-route policy is
   recorded in `docs/ARCHITECTURE.md` §9** — a new op is placed by structure: single-output at-ideal
   → broadcast; multi-output fiberwise → the executor; cartesian-coefficient → a decision-38 kernel
   pair; reductions → the fixed tree; atomics/irregular (and only that) → KA-everywhere, the sole
   policy-exempt class. Tested bitwise in
   `test/threading.jl` (run the threaded lane with `JULIA_NUM_THREADS=4`). The 2026-07-21 threading
   inversion (finding (l): the old per-element chunk loop ran ~8.6 GB/s/thread vs `materialize!`'s ~41,
   so t2/t4 were slower than serial) is **fixed by decision 38** — per-slab `materialize!` over sliced
   operands, bitwise-identical, 512³ t2 `add!` 187.7 → 73.3 ms; both hosts' archives are re-swept
   post-fix (Enteropia `e6e8a76`; Aiporetne 2026-07-22 — 12700K + 7900 XTX, thread scaling monotone). The **two
   `KernelAbstractions` groups outside this policy** (the transfer and the binning — the
   atomic/irregular kernels; helmholtz joined the gated loops in decision 40, and the
   decision-38/39 kernels were gated from birth) are covered separately in the same file:
   a KA launch partitions by `Threads.nthreads()` itself and never consults the cutoff or the
   `with_threading` override, so toggling it compares a path against itself — the check varies the
   thread count across a subprocess instead. The disjoint-write pair (`helmholtz_projection!`, the
   gather) is bitwise-reproducible; the two `Atomix` accumulators (anterpolation scatter, shell
   binning) are **not** — a nondeterministic summation order costs `anterpolate!` 2–3 ulp, so they
   are tolerance-tested like the reductions (`docs/ARCHITECTURE.md` §9). **Discipline:** raw
   elementwise writes go through `_assign!`/`@_assign!`, not bare `.=`. The L²/measure reductions
   now exist (`src/Reductions.jl`, item 8) and are **threaded on the decision-40 fixed tree** —
   bitwise thread-count-invariant on CPU (the cross-`-t` subprocess check in `test/threading.jl`
   asserts it); tolerances remain for cross-backend comparisons only.
6. **Point layer** (`Points` objects/algebra + `Interpolation` transfer) — point-data types and their **full fiberwise algebra**
   done and tested (CPU `test/pointvalues_algebra.jl` + `test/interpolation.jl`; GPU ROCm;
   122-method point-value parity baseline, zero ambiguities). The algebra reuses the
   FieldAlgebra code generators verbatim over an extended section interface (`field_data` /
   `_vector_component_data` / `_tensor2_component_data`) — no formula written twice — and
   mirrors the *physical* field surface only (point values are representation-free).
   **Phase A consolidation done (`docs/ARCHITECTURE.md` §2, §10):** the `FiberSections` foundation
   module + the `AbstractFiberSection{T,R}` supertype (fields and point-values subtype it); the
   `Points` / `Interpolation` split (point objects + algebra in `Points`; the transfer scaffold in
   `Interpolation`); and the shared vertical-algebra codegen + `_assign!` lifted into `FiberSections`
   (norm/sym/skew/dev de-duplicated via `section_scalar_type`). Both parity baselines held
   byte-identical throughout.
7. **Interpolation/anterpolation transfer** — **done** (`docs/ARCHITECTURE.md` §10, decision 17):
   the Lalescu local splines, **both hierarchies** — smooth `LalescuSpline(n,m)` (two-point Hermite,
   degree `2m+1`, `0≤m≤2n`; `m=0` linear, `CatmullRom = (1,1)` default) and `C⁰` `LagrangeSpline(n)`
   (degree `2n+1`). `interpolate` (gather `W`) and `anterpolate` (scatter `Wᵀ`, α/β) as portable
   **KernelAbstractions + Atomix** kernels (CPU/CUDA/AMDGPU; atomic scatter). The smooth weights are
   **pinned bit-for-bit to TurTLE's `beta_n{n}_m{m}`** (`n`↔`interp_neighbours`, `m`↔`smoothness`);
   reproduction `min(2m+1,2n)` smooth / `2n+1` Lagrange; adjoint and conserving (partition of unity).
   Tested CPU (`test/interpolation_transfer.jl`, Float64/Float32, incl. the TurTLE pin) + GPU (ROCm).
   Physical-space only; the L²-weighted (measure-consistent) adjoint is **done** — uniform measures make
   it `(N/M)·Wᵀ` (a scalar rescaling, no new op), verified via `inner` as `M·inner(Wf,q)=N·inner(f,Wᵀq)`
   (`test/interpolation_transfer.jl`).
8. **L²/measure reductions** — **done** (`src/Reductions.jl`; `docs/ARCHITECTURE.md` §2, decision 18):
   the third operation family after the vertical (fiberwise) algebra and horizontal (differential)
   operators. `integral` (extensive `∫f dμ`), `inner`/`l2norm`/`lpnorm` (normalized L²), the
   multiplier-weighted `weighted_inner` `⟨f,w·g⟩` (spectral-only, the reduction-dual of `convolve`,
   generalizing `inner`; `w=|k|²` = the Dirichlet energy; fused, allocation-light; decision 27), plus
   `mean` (extending `Statistics`, fiber-preserving), the scalar-only `std`/`var` and the vector covariance tensor `cov`, and `maximum`/`minimum`/`extrema`
   (extending `Base`, scalar sections), plus the **mapped forms** taking a leading fiber map
   (`mean(det,A)`, `maximum(norm,u)`, `integral(det,A)` — one fused pass, no intermediate section,
   GPU-first; decision 30) — on `AbstractFiberSection`, against the base measure
   (`Grid3D` cell volume / `PointSet` counting). The measure reductions act on **fields in physical representation +
   point-values** (representation-free); `inner`/`l2norm` (Parseval, rfft half-spectrum weighting) and
   `integral`/`mean` (the zero/DC Fourier mode, reusing `_spectral_zero_mode_data`/`_spectral_constant_scale`)
   additionally act on **spectral** fields, = the physical value with no transform. `mean(points) = (1/M)·Σ`; `inner`/`mean` are
   intensive (normalized), `integral` extensive. Physics stays consumer-side (energy `½ inner(u,u)`,
   etc.). Tested in `test/reductions.jl`; the 206/122 parity baselines are unchanged (separate
   generics). GPU-portable by construction (`sum`/`dot`/`maximum`); GPU parity covered in
   `test/gpu/suite.jl`. **`radial_spectrum` added (decision 21):** the shell-resolved Parseval inner —
   the radial power spectrum `(shells, spectrum)` with `sum(spectrum) == inner(f,f)`, spectral-only,
   device-clean via a single **scatter-add** shell-binning pass (`KernelAbstractions`/`Atomix` histogram;
   decision 25 — replaced the O(N) per-shell masked reductions that wedged a 12 GB card
   at 256³ under the GPU GC; decision 34 then fused the remaining staging — the shell-index,
   magnitude, and weighted planes — into the kernel itself, shell count analytic from the corner, so
   the spectrum now allocates only its accumulator). **`radial_correlation` added (decision 22, Phase 1):**
   its physical-space Wiener–Khinchin dual `(separations, C)` — `C(r)=𝓕⁻¹(|f̂|²)/N` shell-averaged over
   minimum-image `|r|`, with `C(0)==inner`; takes `(f_spectral, plans)` (Reductions imports `to_physical`
   for the one inverse rfft); device-clean. **Two-field co-spectra added (decision 22, done):**
   `radial_spectrum(f,g)` (cross-power, binning `Σ_c Re(f̂_c conj ĝ_c)`) and `radial_correlation(f,g)`
   (cross-correlation `C_fg(r)=⟨f(x)·g(x+r)⟩` via `conj(f̂)·ĝ`), each refining the *mixed* `inner(f,g)`
   (`sum(E_fg)==C_fg(0)==inner(f,g)`); both **symmetric** in f,g, the co-spectrum **may be negative**, and the
   single-field forms are the g=f case — new methods on the existing generics reusing the single-field
   binning (no export/parity change). The tensor-valued/anisotropic spectra (`E_ij(κ)`, Craya–Herring
   long/transverse) remain deferred until an anisotropic consumer (decision 22); the point-RDF Phase 2 is done (item 9).
9. **Convolution** — **done** (`src/Convolution.jl`; `docs/ARCHITECTURE.md` §2, decision 20): the
   kernel-multiplier role — periodic (circular) convolution of a field with a kernel, in spectral
   representation, as the coefficientwise product `f̂·ĝ`. `convolve`/`convolve!` apply a kernel `ĝ`
   supplied as a `ScalarFieldSpectral` (the transfer function); a scalar kernel broadcasts over the
   fiber (one method, all tensor orders), with α/β accumulate (invariant 10), coefficientwise ⇒
   alias-safe (no guard, like `laplacian!`), `@_assign!`-routed, spectral-only. `convolve(g₁,g₂)`
   composes kernels for free (the `R=0` case). `spectral_cutoff` is the one neutral builder (isotropic
   sharp low-pass / idempotent projection); physics (LES filter, integrating factor `exp(-νk²Δt)`)
   stays a consumer-built kernel (invariant 12). **Completes invariant 1** — the coefficientwise
   product, named `convolve`, never `*`; the 206/122 parity baselines are unchanged (separate
   generic). Tested CPU (`test/convolution.jl`, Float64/Float32, the translation-kernel ⇔ circshift
   oracle) + GPU (ROCm parity in `test/gpu/suite.jl`); benchmarked (`convolution` class). Naming per
   the §2 convention (verb `convolve`; module noun `Convolution`, parallel to
   `Interpolation`/`interpolate`). **Shell-space builders added (decision 21):** `spectral_band`
   (annular band-pass, with `spectral_cutoff` the `wavenumber_low = 0` case) and the `|k|²` radial symbol
   consumers build kernels from (`radial_kernel(identity, …)` since decision 60 removed the
   materializing `squared_wavenumber_field`); together with `radial_spectrum` (item 8) they
   close the demos' forcing-band + spectrum hand-rolls and make the GPU `HIST_ROCm.jl` forcing +
   spectrum fully on-device. **`assignment_window` added (decision 22 Phase 2):** the linear/CIC
   mass-assignment deconvolution window `Ŵ=∏ sinc²(kₐΔxₐ/2)`, the neutral primitive for the FFT
   point-RDF route (consumer recipe in `test/rdf.jl`, validated vs direct O(M²) pair counting).
   **`translation_kernel` added (decision 28):** the shift theorem's phase `ĝ=e^{−ik·h}` — displaces a
   field by a physical offset h (`f ↦ f(x−h)`), applied with the existing `convolve!` (build once, apply
   many; **no** fused `translate!` — a per-call kernel build would allocate a field every call). The one
   **complex** kernel, so it exposes the reality condition a kernel must meet (Hermitian `ĝ(−k)=conj ĝ(k)`
   ⟺ a real physical-space kernel, now on `convolve!`'s docstring): at an even axis's Nyquist the multiplier
   must be the **real** `cos(πhₐ/Δxₐ)`, not a phase — got by taking the even (cos) part from the **true**
   `|k|` (`√squared_wavenumber`) and the odd (sin) part from the **Nyquist-zeroed derivative** `k`. Both
   naive fixes fail, each differently: the true phase breaks Hermitian symmetry (→ no real field), and the
   all-derivative-wavenumber kernel (the consumer's proposed fix) misses the Nyquist sign flip of an odd
   whole-cell shift. Consumer: phase-shift de-aliasing. **The lazy-kernel pair added (decision 33, IT
   items 2+7):** `exponential_convolve!`/`exponential_convolve` — the exponential radial kernel
   `exp(c·|k|² + s·ŵ)` evaluated per mode from the lazy `|k|²` (no kernel field built, stored, or read;
   `e^{−cΔ}` for c≤0; scalar offset deliberately absent — folds into α; per-mode offset as scale×field so
   a per-call scale is free), single-operand α/β + two-operand combination forms — and the
   kernel-composed `combine!(dest, α, a, β, b, kernel)` method (the weighted combination convolved in one
   pass; `b === dest` = the filtered accumulate). Tested vs stored-kernel oracles + the single-mode
   eigenvalue `e^c·cos x` + sequential pairs (`test/convolution.jl`), pinned allocation-free, GPU parity
   in the suite; consumers: the integrating-factor state updates (2 passes per site saved, 6+6 per RK3
   step) and every exponential factor build IT's `velocity_factor!` used to pay per stage.

**AIPORETNE — the ROCm correctness half is CLOSED (2026-08-06); the benchmark half is in progress.**
Check `hostname` first; on `Enteropia` this item is not actionable. **Decisions 60, 61 and 62 have now
executed on ROCm** (RX 7900 XTX, gfx1100), where before they had shipped verified on CUDA alone. The
pointed one was decision 62: `weighted_inner` admits a `ProductKernel`, whose `_kernel_data` nests **two
lazy `Broadcasted`s**, and the `Base.Broadcast.instantiate` in that function exists precisely because
**AMDGPU's `mapreducedim!` throws on a `Broadcasted` with `Nothing` axes where the CPU tolerates it** —
so the nesting was the predicted place for it to resurface, and no CUDA run could tell us. **It did not
resurface.** The suite is green at 352 tests (the same count as CUDA), and the case is a real one rather
than an absent one: `test/gpu/suite.jl` composes `convolve(cutoff, window)` — radial ∘ separable, which
*is* a `ProductKernel` — and checks it against both the CPU value and the materialized kernel, with the
complex-weight refusal exercised on-device beside it. **`examples/gpu/rocm/HIST_ROCm.jl` has now been
executed**, for the first time by anything: `--smoke` exits 0, `‖∇·u‖_rel = 1.0e-07` (Float32 roundoff),
and Parseval agrees three ways (physical 0.664797, spectral `inner` 0.664797, `Σ E(k)` 0.6648).

**The benchmark half is CLOSED too (2026-08-07).** The canary is green on all three lanes after a
refreeze whose reason is in `bd1e4f30`: this host's ROCm baseline predated `canary_sync` by a week and
two of its twelve mechanisms were timing launches rather than work (`add!` at 17.5 µs and `to_physical!`
at 25.8 µs for a 128³ pass, both under the physical floor), Enteropia's having been refrozen by the sync
commit itself. The **12700K 512³ band is measured** — 512³ became a CPU default in `b59a2793`, so the
plain invocation covers it and the old advice to override `CHAR_SIZES` is obsolete. `RESULTS.md` is
regenerated with **all twelve columns intact**, verified by the untouched columns reproducing
bit-for-bit at +0.0%.

**BLOCKING, and it invalidates every GPU number the project has: `PERFORMANCE.md` §4(s).** Device lanes
run `gcsample = true` (both `characterize.jl` and `regress.jl`, gated on the backend), so a full
`GC.gc()` — finalizers freeing device buffers, synchronizing — precedes **every sample** and dominates
operations lasting tens of microseconds. Measured A/B with only that parameter changed: **18.4–29.2× at
64³, 5.8–19.8× at 128³, still 1.9–4.25× at 256³**, the inflated values reproducing the committed archive.
The tell was always in the table: `convolve! scalar` and `convolve! vector` at 128³ read 1.094 and 1.177
ms — 3× the bytes showing as 1.08× — where the true figures are 57 and 182 µs. It is **not** a uniform
factor, so it corrupts within-column comparisons too, and at least one recorded conclusion reverses:
decision 51's radial kernel is **faster** than the stored class on the 7900 XTX, not slower, so
`bd1e4f30`'s "opposite sign on the two vendors" is **retracted**. **CPU columns and CPU canary baselines
are clean.** Deleting `gcsample` is not the fix — it exists because the `reductions` class wedged the
device pool (2026-06-11) — so the fix must keep a GC discipline off the per-sample path (`gctrial`, plus
the existing per-(class, grid, type) `GC.gc(true)` + `reclaim()`), and that has **not been tested**.
Until it is, treat every GPU cell as an upper bound of unknown tightness, and do not compare a new GPU
sweep against the existing archives.

**§4(p) is NARROWED, not solved: the CPU `fft` shift is Enteropia-specific, and neither host's movement
is explained.** At the larger grids the shift does not reproduce here — of 192 `fft` rows exactly one at
256³ moved slower, by +1.0%, against `Enteropia`'s +38% (23 rows did move slower, but all the rest sit at
64³/128³, the three over 20% being small-grid `-t4`/`-t8` cells; the first pass over one lane wrongly
read as "nothing got slower"). Since this box runs the *same* kernel Enteropia recorded post-reboot
(`7.0.0-28-generic`), a platform-wide kernel or microcode cause is positively **excluded**. But this
host's `fft` rows moved *faster* by 5–46% over the same kind of comparison, equally unexplained, so the
honest reading is that `fft` timings are unstable across sweeps on both hosts while sweep conditions go
unrecorded — a cross-vintage `fft` comparison is uninformative, not evidence. **One new finding is open — `PERFORMANCE.md` §4(r):** every kernel-*taking*
operation moved 20–45% on both backends, and decision 51 looks like the cause but is contradicted by the
report's own `∘ radial` vs `∘ stored` rows (radial is *faster* on the very lane whose kernel-composed
operators slowed). Recorded as unexplained rather than attributed. Traps and the full task list remain in
the synced memory `aiporetne-verify-rocm-decisions-60-62`.
**Do not run `characterize.sh` there** — it would hand `report.jl` only the lanes it just produced and
silently drop Enteropia's two columns and both retired cards from `RESULTS.md`.

**RESUMPTION POINT — the exhaustive survey's per-method coverage ledger (designed 2026-08-02, NOT
built).** The survey crosses its axes everywhere except where the independent oracles live: the
universal-checks lane derives its product from the method table, while the **value lane is a hand-written
list** of rows — one fixture per operation, mostly `R = 0`, one scheme, one α/β setting. A reasoned
mutation audit produced eighteen survivors and every one is that single fact rather than a missing axis
(tensor order, α/β, scheme, or the operation axis taken per METHOD rather than per symbol). Coverage is
bookkept per symbol, so one checked method marks a whole generic done — `mul!` has 48 methods and reports
covered on one row. **Measured denominator: 112 operations, 556 package-owned methods, 169 value rows**;
556 overstates the work because the heavy operations are code-generated from one builder, so the estimate
of genuinely distinct behaviours needing an oracle is 60–120. **Definition of done: every
`(operation × method)` cell has a value row or a recorded reason, and the ledger fails when it has
neither** — decision 55's provenance rule applied per method. The ledger is the measuring instrument, so
it must be **falsified by perturbation, never by reading** (delete a row, the count rises by exactly one;
add one, it falls; a row naming a nonexistent method reports unmatched; a reason-closed cell stays
distinguishable from a row-closed one) — this session already shipped one instrument that measured the
wrong set and reported success. Full design, queue and order of work in `test/exhaustive/DESIGN.md`.

**Open items from the 2026-08-04 survey runs, NOT yet closed.** Two findings the exhaustive survey
reported that have not been acted on. **(1) `to_spectral!` allocates ~8–12 KB per step** on odd grids
under permuted layout folds (the sequences lane, measured over 64 steps against a 1260-byte field) —
invariant 13 is about exactly this measurement, so it is either an FFTW plan-scratch exemption that
should be documented and bounded, or a real per-step leak. Not investigated. **(2) The value lane has
never executed against the current package**: `values.jl` did `field + materialize_kernel(...)`, which
broke when decision 60 made that return a `StoredKernel`, so the lane threw before running from
2026-08-03 until the fix on 2026-08-04. Its 112 independent oracles are therefore unverified against
the present code; a run is ~90–115 min and needs consent (see the consent gate above).

**Open HARNESS finding (not a package defect) — the survey's `radial_spectrum` oracle is
convention-dependent (2026-08-04).** The value lane reports `radial_spectrum` disagreeing with
`ref_radial_spectrum` on Float32 anisotropic grids. It is not a defect in either: the GATE already
tests this operation against real physics — a constant field puts all energy in the ``|k| = 0`` shell
with ``E(0) = c^2``, ``\cos x`` puts ``\langle\cos^2\rangle = 1/2`` in the ``|k| = 1`` shell, plus
Parseval and the co-spectra — and those pass. The survey's reference instead RE-IMPLEMENTS the binning
(`round(sqrt(|k|²)/Δk)`), so it compares the package against a second implementation of an arbitrary
convention. On the anisotropic boxes the wavenumbers are multiples of `2π/L = (1, 1/2, 1/3)`, so
``|k|/Δk`` lands exactly on a half-integer for 18 of 150 modes, and a 4e-7 difference between the two
sides' Float32 wavenumber arrays decides which way `round` breaks the tie. Energy moves between
ADJACENT shells and `sum(spectrum) == inner` holds exactly on both sides.

**Two fixes were tried and both MEASURED as wrong — do not retry them.** Computing the shell index in
Float64 (each term widened before the sum) made 32³ WORSE, 3.4% → 4.8%, and 128³ only marginally
better, 1.2% → 1.1%, because the difference is in the wavenumber ARRAYS and no downstream widening
repairs an input difference; it also cost **+17% GPU throughput on Float32** (0.129 → 0.151 ms at
128³, consumer NVIDIA running FP64 at 1/64 rate) and broke the `cos_y` gate assertion, which pins a
mode sitting exactly on ``|k|/\Delta k = 1.5``. The magnitude falls slowly with resolution: 3.4% at
32³, 3.1% at 64³, 1.2% at 128³.

**The fix belongs in the harness.** Either build the survey's fixture so no mode lands on a tie, or
assert the tie-independent properties the gate already uses — Parseval and peak placement — instead of
per-shell equality against a re-implemented convention.

**Oracle provenance is enforced (decision 55, 2026-07-29).** `docs/TESTING.md` §1 opened with
*verify against independent ground truth, never against the code's own other path* for a year with
nothing checking it, so `weighted_inner` shipped verified entirely against `inner`, `laplacian`,
`gradient` and `convolve` — every assertion sound, none of them independent of the package. The
mutation audit could not see it, because it asked *would a defect be caught?* (yes — a relational
chain terminating in an anchored reference does catch defects) and never *does this operation have an
oracle independent of other package operations?* `test/oracle_registry.jl` now records a provenance
for every public value-returning operation, and fails on two conditions: an operation with no entry,
and an operation covered only relationally. **Standing rule: a new public operation is unfinished
until it is classified there** — the classification is the moment to notice it has no independent
oracle, rather than a year later.

**Mutation audit (decision 52, 2026-07-29).** The suite was audited by INJECTING defects in isolated
worktrees, not by reading coverage. It found two live bugs (a  plan used above its own tensor order
returned NaN/uninitialized memory;  leaked the scalar-only absence that / enforce,
because  HAS a fallback for it) and, more importantly, **fixture blindness**: the gradient testset was
named for an index convention its diagonal fixture could not see, and the tensor divergence had no analytic
oracle at all — nine identical components, so , with every other assertion self-referential. Both now
have closed-form oracles over asymmetric fixtures, **each verified by re-applying the mutation and confirming
the new test fails**. Standing rule from it: a symmetric fixture cannot see an asymmetric defect, and a
self-referential assertion (threaded vs serial, device vs host, compressed vs stored) cannot see a defect
shared by both sides — when a convention is stated in a name or docstring, the fixture must be able to
falsify it.

**Standing item — a testing-protocol and allocator review (user-directed 2026-07-28).** Two findings
motivate it, both surfaced by the module-placement panel rather than by the suite. **(1) A missing
coverage axis.** `map(φ, field)` was broken for every permuted `RealFourierLayout` from the day it
shipped (decision 48): the allocating form built its result with two-argument constructors, which
default the layout, so the field's metadata was silently dropped. The `docs/TESTING.md` §4 axis list has
no entry for it — the closest, the *layout fold*, reads as an FFT concern, which is exactly how the
axis got waved off as "N/A, physical-only" during a coverage review that was explicitly asked for. The
axis the list needs is **"field metadata (layout, grid, origin) must survive any operation that
ALLOCATES its result"**, and every allocating operation belongs in that lane. **(2) One canonical
allocator.** The same helper is now hand-written three times — `similar_field` (`Fields`), `_wrap_field`
(`Interpolation`, which patched this trap locally with a comment that never propagated), and
`_map_output_field` (`FieldAlgebra`, which did not). The review should decide whether one canonical
allocator can serve all three and whether every allocating operation must route through it, which would
make the metadata-propagation axis enforceable by construction rather than by test. Benchmarks are in
scope of the same review.

**Decision 60 — a field in spectral representation is not a kernel (2026-08-03).** `SpectralKernel` was
a UNION of `ScalarFieldSpectral` and an abstract `AbstractSpectralKernel`, which made the abstract type
read broader than the union while being narrower, and forced a `StoredKernel` marker to exist purely so
`inv` could tell a kernel from a field. It also made `convolve` asymmetric in a way commutativity
forbids: `convolve(field, kernel)` applied while `convolve(kernel, field)` COMPOSED, because argument
position was the only thing left carrying the role. The union is gone. `SpectralKernel{T}` is now the
abstract supertype of the four classes — `StoredKernel` (one coefficient per mode), `SeparableKernel`
(per-axis factors), `RadialKernel` (the symbol), `ProductKernel` (two factors unmultiplied) — every
signature naming `kernel::SpectralKernel{T}` is unchanged, `materialize_kernel` returns `StoredKernel`,
and both argument orders of `convolve` apply and agree bitwise at every tensor order. Composing two
convolution operators IS convolving their kernels, so composition keeps the same verb and is now
unambiguous by type. A field of coefficients is wrapped once, where the kernel is built: measured at
64³, the wrapper costs 144 bytes at construction and **zero per call**, with `_kernel_data` inlining to
a `getfield`. Two package methods went (`Fields` 105 → 103 methods, refrozen with the reason). The
rename's one hazard, caught by the pass audit and not by any other layer: a guard reading
`kernel isa AbstractSpectralKernel` MEANT "compressed", and renaming made it true for the stored class
too, routing it off the fused pass — vector traffic 3M reads against a frozen ideal of M.

## Planned directions (recorded — not started)

The package is feature-complete for its core mission. Recorded next steps, in priority order:

- **Spectral-domain transfer (decision 23) — DONE.** Both schemes shipped natively (no dependency)
  under `AbstractTransferScheme`: `DirectDFT` (exact `O(NM)` + the oracle) and the fast windowed
  `NUFFT` (`O(N log N + M)` gridding = spread→FFT→deconvolve, reusing the transfer kernels + oversampled
  plans + an `assignment_window`-style deconvolution), validated against `DirectDFT` to ε on the
  resolved sub-Nyquist band. **Future:** lift the Nyquist projection (lossless rfft Nyquist split in the
  zero-pad) if an exact-at-Nyquist consumer ever needs it.
- **General tensor order `R >= 3` (deferred, decision 56).** The supported surface is `R < 3`. Storage,
  HDF5 persistence, the vector-space operations, `inner`/`l2norm` and the local-spline transfer already
  serve higher orders; the fiber-preserving and mapped reductions, `map`/`map!`, and the
  `sym`/`skew`/`dev` decompositions are defined for `R <= 2` and **throw** above it. Deferred rather
  than declined — the second-order surface is what a pseudospectral solver needs, and shipping it
  first was the point. Closing it means generic fiber assembly above `R = 2` in `FiberSections`
  (`_fiber_type`/`_assemble_fiber` are enumerated for 0/1/2) and a rank-generic stored-kernel
  convolution. **The boundary is pinned by a test lane** (`test/contracts.jl`), whose property is that
  above the ceiling every entry point either works or throws — never returns a wrong value — so that
  lane is what must keep passing while this is open.
- **Alias safety for partially overlapping distinct views — CLOSED by decision 59, not open.** This
  was recorded as a known limitation under decision 56: two *different* views overlapping at
  *different* base indices break the fused pass's read-then-write argument (`cross!` on views offset
  by one along an axis returned the wrong answer, serially and threaded, undetected). Decision 59
  removed the class rather than guarding it — a section's constructor **rejects borrowed storage**, a
  `SubArray` anywhere in the parent chain, so such a pair is now **unconstructible** and same-array is
  the only way two sections can share memory. Verified 2026-08-05: building a field on a `view` throws
  `ArgumentError: a ScalarFieldPhysical must own its storage`. The `mightalias` guard reasoning stays
  recorded as why the guard route was declined — it would have rejected `sym!(A, A)`, whose target and
  source component views already have different footprints on one parent (decision 39 made that
  guard-free after measurement).
- **Explicit conversions between storage families and precisions (ROADMAP — not needed soon).**
  Invariant 14 refuses a mixed pair rather than converting, which is the right default: an implicit
  host↔device transfer inside an arithmetic operation is a silent multi-millisecond cost in a loop
  that is otherwise device-resident, and an implicit precision promotion silently changes what a
  solver is computing. The complement is a **named** operation whose cost is visible at the call
  site. Shape, when a consumer needs it: a single generic in the `Fields` allocator family
  (`similar_field`'s neighbourhood) taking a section and a target — `convert_storage(field, CuArray)`
  and `convert_precision(field, Float32)`, or one `convert_section(field; storage, precision)` — with
  the point-value and `PointSet` twins, since the point layer mirrors the field surface. It must
  preserve everything else the section carries (grid, layout, origin, tensor order) exactly, which
  makes it a case for the metadata-propagation axis the testing review already wants. Open questions
  to settle before coding: whether a precision change of a field in **spectral** representation is
  offered at all (it is a lossy operation on coefficients rather than on the physical object, so
  invariant 2 has an opinion); whether `FieldSpectralMultipliers`, `FieldTransformPlans` and the
  kernels convert too, since a converted field is unusable without its partners; and whether the
  verb allocates only, or gains an in-place form writing into a preallocated destination of the
  target family, which is what a solver moving a field every step would actually want. No consumer
  yet, so this is recorded rather than designed.
- **van Hinsberg global B-spline — still needs a design discussion before coding** (`docs/ARCHITECTURE.md`
  §10, decision 17): a coefficient pre-transform + compact stencil (higher accuracy, but a global solve
  that breaks "single representation", so it needs a coefficient-field type + transform step).
- **Deferred until a consumer makes them concrete** (the §2 rule against speculative structure):
  **discrete Voronoi volumes — the label-grid route (PLANNED, user-directed 2026-07-22)**: per-point
  estimates of the minimum-image Voronoi cell volumes — the natural quadrature measure of the point
  base — computed WITHOUT constructing geometry: build a nearest-point label grid on an N³ working
  grid (Jump Flooding — Rong & Tan 2006 — or a cell-list direct pass; KA kernels, periodic `mod`
  indexing, ping-pong integer scratch that stays internal, never a public field type), then volumes =
  per-label voxel counts × cell volume via the Atomix scatter-add histogram (the radial-binning
  kernel shape). Fully package-idiomatic: GPU-first both vendors, CPU by the same backend split.
  Shape ≈ `voronoi_volumes(points, grid[, options]) -> ScalarPointValues`; the label-grid resolution
  is the accuracy option — relative volume error ≈ (voxels per cell)^(−1/2) (512³ ≈ 3% at 10⁵
  points; 1024³ ≈ 3% at 10⁶). Tests per house style: the Monte-Carlo oracle (uniform samples →
  nearest point), the exact conservation ``\sum_p V_p = |\Omega|`` (every voxel labeled exactly
  once), analytic lattices (equal cells), and two-point configurations with hand-computable bisector
  volumes; full definition-of-done (parity, allocation + pass-audit rows, a benchmark). The **exact
  tessellation (cells, topology, neighbors) stays declined** as before: combinatorial geometry is the
  wrong computational kind here — Voro++ consumer-side remains the exactness oracle if one is wanted.
  Feeds directly into
  the **weighted point measure** (recorded 2026-07-22): the measure-with-density on the unstructured
  base — `integral(q, w) = Σ wₚ qₚ`, `mean`/`inner`/`l2norm` against a per-point density `w` over the
  counting measure — the point-base sibling of `weighted_inner`, reusing the whole reduction
  machinery. Consumer: these Voronoi volumes as quadrature weights for clustering-PDF diagnostics
  (preferential concentration à la Monchaux, Bourgoin & Cartellier 2010) — the PDFs themselves stay
  consumer-side. Trigger for the measure: the volumes landing;
  the fused **quadratic-form reduction** `⟨v,A·v⟩ = mean(v_i A_ij v_j)` (a bilinear reduction; the IT
  request flagged it "for completeness of the fused-reduction set", its win a single vector intermediate at
  diagnostic cadence, its consumer — enstrophy production `⟨ω·S·ω⟩` — not yet live; a small add on the
  existing `inner` machinery when it lands; decision 27); anisotropic / tensor-valued radial spectra
  `E_ij(κ)` + the Craya–Herring longitudinal/transverse
  split (shear-flow anisotropy diagnostics); higher positive-B-spline / signed-kernel RDF windows +
  interlacing; matrix-valued convolution kernels (threaded reductions landed — decision 40). Shear-flow support (Rogallo
  time-dependent multipliers + remeshing) stays consumer-side.
- **`var`/`std` — DONE (2026-07-28, decision 49).** A design review
  found both mis-scoped. **(1) Spectral form:** they are physical-only by *scoping, not validity* —
  `var(f) = inner(f, f) − mean(f)²` (spectrally `Σ_{k≠0} |f̂_k|²`, the fluctuation energy), both terms
  already spectral-available, so they were wrongly grouped with the genuinely-physical-only
  `lpnorm`/`maximum` (which have no Parseval form). **(2) Per-component vs covariance:** fiber-preserving
  `var`/`std` on a vector/tensor field return the *basis-dependent diagonal* of the covariance tensor
  `R_ij = ⟨u'_i u'_j⟩ ∈ Sym²(V)`, dropping the off-diagonal covariances — fiber-preserving `mean` is
  coordinate-free (linear) but fiber-preserving `var` is not (quadratic). **Definite fix:** document both
  honestly — the per-component / diagonal-of-covariance meaning for R>0, and physical-only-by-scoping (not
  validity). **Optional builds (consumer-gated):** spectral `var`/`std` (a thin delegation to
  `inner − mean²`); a `cov` returning the `Sym²(V)` covariance (Reynolds-stress) tensor — a consumer-side
  diagnostic (invariant 12) in the `E_ij(κ)` family (`R_ij = Σ_{k≠0} û_i conj(û_j)`), tying to the
  symmetric-storage item (decision 35, IT item 3).
- **The canary-judge benchmark lane — BUILT (`benchmark/regress.jl`, 2026-07-22).** The last unautomated
  regression layer: achieved-TIME regressions (SIMD loss, launch drift, library bumps) — the class
  `pass_audit`/`allocations`/JET cannot see, and the one that let the threading inversion sit in the
  committed table for six weeks. Shape: a per-mechanism canary suite (~10 ops × one size/type,
  2–3 min/backend, reusing `build_suite`), **frozen per-host baselines committed** under
  `benchmark/baselines/` (canary-sized, kilobytes), `benchmark/regress.jl` judging minimum times at a
  25% tolerance (≥2× documented jitter) with a nonzero exit on regression, an explicit
  `tN ≤ 1.1·t1` streaming-op assertion, and the pass-audit refreeze protocol (an intended slowdown
  refreezes its baseline in the same commit, with the reason). Per-host, never cross-host; both
  backends; NOT CI (cost policy; cloud runners are noise). Both hosts' baselines are committed under
  `benchmark/baselines/` — Enteropia (cpu-t1, cpu-t8, cuda) and Aiporetne (cpu-t1, cpu-t8, rocm;
  frozen 2026-07-22 with that host's post-rewrite re-sweep, its inversion alarm 8/8 ok); calibration
  100 samples × 5 evals — 20 samples let µs-canaries false-alarm.
  **Definition-of-done addition: a perf-relevant change runs `regress.jl` green, or refreezes with
  its reason in the same commit.**
- **The audit-exchange declines and standing candidates (decision 35).** No general fusion API — the
  named-op + adversarial-triage protocol IS the fusion mechanism; the broadcast layer is internal, not a
  public contract (§8). Two **validity-closed escalation paths**, recorded not built: radial real
  symbols `σ(|k|²)` as closure kernels (`exponential_convolve!` is the family's first instance; a third
  functional form — Gaussian filter, hyperviscosity — triggers the generalization), and a stdlib-shaped
  physical `map!(φ, dest, sections...)` (the section-valued sibling of the mapped reductions). Deferred
  with reasons: IT item 3 (symmetric 6-component tensor storage — legitimate `Sym²(V)` math, but the
  largest surface and dominated by item 4 on its own episode) and item 4 (in-place r2c — padded-stride
  collision with invariant 3's contiguity; the largest memory lever if its consumer is un-archived).
  Pre-registered round-3 candidate from IT: the **two-output stage update**
  `(ĥ, û) ← (N̂ + a·ĥ, ℰ⊙(û + b·ĥ))` (~13% of its pass traffic; a module map into a direct sum — would
  pass §2; the open questions are the two-destination surface shape and whether the share justifies it).
- **`map!` / `map` — DONE (2026-07-28, decision 48).** The decision-35 physical `map!` candidate shipped,
  built to the spec below (kept as the record). **Module:**
  `FieldAlgebra` (physical-field methods) + `Points` (point-value methods) — it is a *vertical/fiberwise*
  op (family 1), so **not** `Reductions` (it does not reduce against the measure) and **not**
  `FiberSections` (internal foundation, no public exports); it also falls under the FieldAlgebra
  nonlinear-aliasing warning. **Engine:** reuse `_fiberwise_pass!` (it already takes a runtime `f` and
  keeps `targets`/`arrays` separate, so an *order-changing* map like `exp∘det` : tensor→scalar works; it is
  KA-GPU + slab-threaded-CPU, allocation-free, `@_assign!`-routed) — no new engine. **Surface:** extend
  `Base.map!` / `Base.map` (`import Base: map, map!`; not piracy, we own the types). **Validity:** methods
  on `AbstractFieldPhysical` and `AbstractPointValues` only; a field in spectral representation gets **no** method
  (invariant 1 — arbitrary φ is nonlinear ⇒ physical-only). **Shapes:** multi-input `map!(φ, dest, f, g, …)`
  (φ takes the input fibers' tuple, returns the output fiber); optional α/β accumulate (the engine already
  carries it, overwrite = `true`/`false`); the allocating `map(φ, f)` infers the output tensor order from φ
  via `Base.promote_op(φ, fiber_type)` or a sample fiber. **Parallelism:** embarrassingly parallel —
  disjoint writes, no atomics — so it scales cleanly and is bitwise thread-count-invariant on CPU; φ must
  be a pure, GPU-safe function (no captured state, no scalar indexing). **Definition-of-done:** a CPU
  oracle test + GPU parity in `test/gpu/suite.jl` + the `@allocated` zero in `test/allocations.jl` + a
  `test/pass_audit.jl` row; a benchmark in the fiberwise class; the four guiding docs (ARCHITECTURE
  decision + section, FORMALIZATION typed entry, TESTING §4 axes, PERFORMANCE); and CLAUDE.md (module list;
  record it as decision-35's first `map!` instance). Its docstring lands under the FieldAlgebra
  nonlinear-aliasing warning.

## Working agreements

- The API is not frozen; do not build backward-compatibility shims.
- During large refactors, complete "supposedly working" drafts are acceptable for
  architecture review, but loading + parity checks are required before calling work
  finished.
- Errors found later are fixed one by one; architectural soundness is judged on the
  full picture first.
- **Commit ⇒ push, on `master`.** This is a *private* repo synced across machines through
  GitHub, so work is committed **directly on `master`** (the default branch — do not branch)
  and **pushed in the same step**; GitHub is the cross-machine sync path and the docs site
  deploys on push. End every commit message with `Co-Authored-By: Claude Opus 4.8
  <noreply@anthropic.com>`; never use `[skip ci]`.
- **CI is manual-only — run the matrix LOCALLY pre-commit.** Push-triggered CI burned the
  free tier, so the workflow runs only on manual dispatch / tags, **not on push**. Before
  committing a code change, run `Pkg.test()` (plus the GPU suite where a device change
  warrants it); a docstring/doc/example-only change needs only a load + the relevant doc
  build. Docs still deploy on push. (Sub-environment `Manifest`s under `docs/`, `test/gpu/*`,
  `benchmark/*` are gitignored and go stale locally when package deps change — `Pkg.resolve`
  that env if precompile breaks; CI is unaffected.) **One Julia, two thread counts.** The compat
  floor was raised 1.11 → 1.12 on 2026-07-19, so the CI matrix now differs only in `-t1` vs `-t4`
  and there is no second local lane and no per-version manifest dance. Why 1.11 went: the package
  *ran* faster on it (every op, 1.11 vs 1.12 steady-state), but compiling cost several times more
  (`_assign!` 4.5×, the `KernelAbstractions` path 1.4×), so `Pkg.test()` took 31 min against 5.4 —
  a pure compile-time tax, unfixable from our side, for a Julia nothing in the fleet runs. Sibling
  packages (`GBGIsotropicTurbulence` declares `julia = "1.11"`) are being bumped separately.
