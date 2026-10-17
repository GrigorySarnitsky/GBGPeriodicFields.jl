<!-- gbg:managed begin v2.0.0-rc.79 — rewritten by `gbg sync`; do not edit -->
@.gbg/policy/00-index.md

The rulebook above is the whole of it: the rules, the terms they use, and what GBGPeriodicFields has
switched off with its reason. Nothing restates a rule outside it — a rule quoted in two files is a
rule that will be reworded in one.

Unasked, run `Pkg.test()` and nothing else; before every push the docs build runs too, through the
push hook, and a failing build stops the push. What a rule finds is reported, never fixed silently:
documentation may be fixed without asking, and anything else waits for an answer.

The readers of a review are derived from the rules and the tool's catalogue of disciplines. A
reader or a discipline this package needs and the tool lacks is requested of the tool, as a request
file the owner has approved, never written here.

A run an earlier session left open is continued before anything else, and the chat says so:
`gbg run next` says what to launch or that the stage is ready to collect, and the run goes on to
its close. It waits for the owner only when `gbg run next` says the tree moved since the launch.
<!-- gbg:managed end -->

# CLAUDE.md — GBGPeriodicFields

Julia package: real-valued scalar/vector/second-order-tensor fields on 3D rectangular
periodic domains, with physical-space and real-to-complex (rfft) spectral
representations, on CPU (`Array`) and GPU (`CuArray`, `ROCArray`) — **single node, shared-memory only**
(CPU multithreading and a single GPU; distributed/multi-node and multi-GPU are out of scope). Production
target: **NAISS Arrhenius** (decision 37) — CPU nodes carry the beyond-GPU-VRAM grids (the CPU path's
tuning target, not small tests), and the GPU nodes have **`aarch64` (Grace) hosts**, so **never adopt an
x86-only dependency or recommendation** (e.g. the MKL FFT provider); nothing in the tree is known
x86-only, but nothing has been built on ARM yet (`docs/PERFORMANCE.md` §7 gap 8). Built as the field
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

- `src/FiberSections.jl` — base-agnostic foundation: the `AbstractFiberSection{T,R}` supertype (field and point-value types subtype it), the **fiber types** (`FiberVector{T} = SVector{3,T}`, `FiberTensor2/3/4`, `fiber_shape` — the value at one base point, base-agnostic by construction, so `Points` takes its fiber vocabulary from here rather than from the grid module; moved from `Fields` 2026-07-28), the `_assign!`/`@_assign!` threading primitive, and the **vertical-algebra code generators** (per-component formula + kernel-body builders, incl. norm/sym/skew/dev via `_section_scalar_type`) — reused verbatim by `FieldAlgebra` and `Points`, so each fiberwise formula is written once. It also holds the grouped n-ary fold `_nary_assign!` behind `add!`/`subtract!` over any operand count and the executor's per-source map adapter (decision 88: a caller-chosen count is worked in fixed groups, every per-element step that indexes the operands a GENERATED function with a literal index per operand, never a splat or tuple `map`, which leave the specialized path at 32, nor a closure indexing a mixed tuple, which the first version used and which allocated 8.3 MB per call on the CPU and did not compile on a device — caught by the CUDA suite, not the CPU audit. A generated body must carry `Expr(:meta, :inline)` itself, `@inline` not applying to `@generated`: without it the read blocked the executor's `@simd` loop, `mul!` 3.2× slower on CPU and 13.5× on device, with every test passing — caught only by the canary).
- `src/Fields.jl` — types (`Grid3D` — uniform, and it enforces that: the four-argument constructor rejects a `grid_spacing` contradicting `domain_size ./ grid_size`, decision 45 — `RealFourierLayout`, field types; `FiberVector{T} = SVector{3,T}`, `FiberTensor2{T} = SMatrix{3,3,T,9}`, plus `FiberTensor3/4`), memory layout, broadcast style, compatibility checks, `FieldTransformPlans` (which since decision 76 carries **no tensor order** — a transform is defined on the box and a rank-`R` field is that transform along a fiber, so one plan pair serves every rank, applied per contiguous component; a grid whose component offsets a transform library would refuse is answered by `FFTW.UNALIGNED` on the host and a component buffer on a device, never by refusing the grid; built from a pair of fields or, since decision 93, from an array family with the grid and layout alone — `FieldTransformPlans(CuArray, grid; layout)` — both planning on one-component arrays of their own, so `MEASURE` never overwrites a caller's field), `FieldSpectralMultipliers` (likewise built from a field or, since decision 94, from an array family with the grid and layout, both canonical), the public allocator `similar_field` (a section carrying a reference's representation, order, grid and backend — uninitialized storage; `Points` mirrors it with `similar_point_values`; decision 44), the **reference-free allocating constructors** (decision 74: the six field constructors (whose layout is the keyword `layout` since decision 99) accept an *array family* in place of the array — `VectorFieldSpectral(ROCArray, grid; layout)` — and produce uninitialized storage themselves; element type from the grid, a mismatched or complex family parameter refused; the route for a consumer holding only domain context and no field to copy from, closing IT's raw-`similar` workaround), the **reality condition's check and projection** — `reality_residual` (how far a field's coefficients are from being a real field's spectrum; decision 71) and `reality_projection!` (the orthogonal projector onto real-field spectra on the two stored self-conjugate planes, in place, ``O(N^2)``, the twin of `helmholtz_projection!`; decision 83). Decision 71's premise that the package's own output satisfies the condition "by construction" holds only to round-off — FFTW is exact at some power-of-two sizes and ulp-level elsewhere, rocFFT and cuFFT ulp-level at every size — and a forcing proportional to the field amplifies that residual exponentially where viscosity does not damp it, which is how the consumer's forced runs died at a seed-independent time; the projection removes it exactly where the round trip only resets it to the transform's floor. The report/repair split stands: the check reports, the projection is an explicit verb the caller invokes, and nothing is folded into a transform), the **mean-free projector** `mean_free_projection!` (decision 90: the orthogonal projector onto zero-mean fields, spectral representation only, one write per fiber component and no host readback — a consumer had been writing the zero coefficient through raw storage), the **array-family move** `adapt` (extended from `Adapt.jl` and re-exported, for every section, kernel and plan — grid/layout/origin/order propagate by construction, plans rebuild themselves; precision deliberately excluded; decision 63) with its in-place sibling `adapt!` (sections only — a built object has no storage to fill; decision 69), both refusing every mismatch with a reason (decision 91), and **equality** `==`/`isequal`/`hash` on fields, point values and point sets by value (decision 91: the default had compared identity, so two equal fields compared unequal; physical against spectral, and mixed precisions or families, are refused), and the field↔HDF5 persistence generics `write_field`/`read_field` and the in-place `read_field!` (the durable-snapshot serializer — a field maps to one self-describing HDF5 group; a host field is written with no copy and `read_field!` fills an existing field after refusing every mismatch, a device one through a one-component host buffer, decision 93; the methods live in the `ext/GBGPeriodicFieldsHDF5Ext.jl` weak-dependency extension, loaded with `HDF5`; the consumer owns the file and any notion of time — invariant 12; decision 29), the **resolution verbs** `embed_modes!`/`extract_modes!` (decision 85: two grids over ONE box name the same physical modes where they overlap, so a coarser field's modes write into a finer one and read back, each leaving the destination's other modes untouched and costing the COARSE field — the route by which a forcing computed on a small grid reaches a large one with no transform. Amplitudes are PHYSICAL: the ratio of point counts is applied inside, which makes the round trip an identity and the two verbs EXACT adjoints with no measure factor, unlike `W`/`Wᵀ`'s `N/M`. The coarse Nyquist shell is EXCLUDED — the coarse grid identifies ±N_c/2 where the fine grid stores them apart, so the datum does not determine the pair — and that exclusion is what makes the shared set a subspace. Refusals are structural: same box, origin, layout, scalar type, tensor order, family; coarse ≤ fine per axis; EQUAL grids refused. Two verbs rather than one because the motivating consumer calls both directions on the same pair of fields, where a single direction-inferring verb would make a transposed call legal and leave a run silently unforced; no allocating siblings, the destination's other modes being part of the result), and the **display layer** (decision 82: a section owns a field-sized array, so the default struct display printed it — 5.6 M characters for a `PointSet` of ``10^5`` points, and, the half that bites harder, whatever an exception interpolating the object would carry. Two forms: a one-line self-delimiting `Type{T}(body)` for a container / `$(...)` / an error message, and the REPL's `MIME"text/plain"`. The body carries what the package REFUSES on — extent, origin and the fold, shown only when they leave the ordinary ``2\pi`` box — so two fields that will not combine cannot print alike; coordinates print at FULL precision and the predicate suppressing them is EXACT equality, both halves having been wrong in a first draft. Nothing reads an element. `Grid3D`, the multipliers, the plans, the four kernel classes, the point types, the traversal order and the transfer schemes all have one; the derived gate is `test/display.jl`. The work also unified THREE spellings of the array family, two of which called `parent` once and so answered `ReshapedArray` for a doubly-wrapped device array — `_same_backend` is invariant 14's predicate, so that was a live divergence, not a tidy-up).
- `src/FieldAlgebra.jl` — fiberwise/pointwise algebra; method families emitted by code generators. Includes `combine!` (the weighted combination / axpby `α·a + β·b`, linear ⇒ both representations, alias-safe) and `det`/`det!` (the determinant, the third invariant `I₃`; nonlinear ⇒ physical-only, mirrored to point-values where `tr` lives; decision 27). Also **`map!`/`map`** (decision 48, decision-35's first instance): the arbitrary-fiber-map escape hatch — an extension of `Base.map!`/`Base.map` applying any φ per base point through the shared `_fiberwise_pass!` executor (the pure-fiber adapter — assemble → φ → flatten — lives in `FiberSections`), fields in physical representation here and point-values in `Points`; physical-only (nonlinear), order-changing (`exp∘det`), multi-input, α/β, allocation-free, the section-valued sibling of the mapped reductions.
- `src/DifferentialOperators.jl` — differential operators applied as spectral multipliers (`gradient`, `divergence`, `curl`, `symmetric_gradient` (the fused symmetric part of `∇u`, `Ŝ_ij = (i/2)(k_j û_i + k_i û_j)` — the symmetric peer of `curl`, skipping the full gradient; decision 27), `laplacian`, `inverse_laplacian`, `inverse_curl` (the solenoidal preimage of a curl, `û = i a × ŵ/|a|²`; decision 77), `helmholtz_projection`, in-place variants). Imports `FieldSpectralMultipliers` and its compatibility/broadcast helpers from Fields; the umbrella re-exports the Fields version. Owns only the spectral kernels and the operators. The in-place `!` operators are **allocation-free** (lazy `|k|²` via `_squared_wavenumber_broadcast` returning an unfused `Broadcasted` over views the multipliers **store** rather than reshape per call — decision 70, without which each of `laplacian!`/`inverse_laplacian!`/`divergence!`/`exponential_convolve!` dripped 144 B a call — + fused `laplacian!`/`inverse_laplacian!` kernels), so a preallocated in-place hot loop allocates nothing per step, which is now asserted as **literally zero** on the serial lane rather than merely below a field — required for hassle-free GPU runs (no manual GC/`reclaim`; decision 24, guarded by `test/allocations.jl`). Keep it that way: new in-place kernels must fuse their scratch, not materialize it. `helmholtz_projection!` is a **one-pass KernelAbstractions kernel** (the third KA site): per mode it reads the three source components once, computes the longitudinal factor `a_j û_j/|a|²` once (every factor from the derivative-wavenumber family — the exact discrete projector, idempotent and divergence-annihilating at every mode; decision 42), writes all three outputs — 2.7–6.5× the old three-broadcast form, **alias-safe by construction** (dest === source needs no guard temporary, bitwise-equal; sources deliberately not `@Const`). `helmholtz_projection!` and `divergence!` (both fiber signatures) take the **kernel-composed arities** `op!(dest, f, mult, kernel[, α, β])` — a `convolve!` fused into the operator's own pass (the product of Fourier symbols; α/β as in `convolve!`, the four-arg form delegating `one(T)`, `zero(T)`), + allocating `op(f, mult, kernel)` wrappers; `curl!` deliberately has no kernel arity (no consumer). Decision 32.
- `src/Convolution.jl` — **periodic convolution** of a field with a kernel, in spectral representation (the kernel-multiplier role of the measure structure — one integration structure whose other two roles are the reductions and the grid↔point transfer). `convolve`/`convolve!` apply a kernel `ĝ` (a `ScalarFieldSpectral` transfer function) as the coefficientwise product `f̂·ĝ` — the operation invariant 1 names but bans as `*`, offered under its true name `convolve` (exported infix `⋆`; never `*`); a scalar kernel broadcasts over the fiber, with α/β, alias-safe (no guard, like `laplacian!`), spectral-only; `convolve(g₁,g₂)` composes kernels. **Decision 66:** the five builders take their `FieldSpectralMultipliers` and nothing else — the former leading `reference` field carried nothing the multipliers did not already hold (grid, layout, element type, and the backend the axis factors are broadcast onto), and was a fossil of the pre-decision-50/51 era when a builder materialized a field of coefficients and needed a storage prototype. **Decision 51:** `spectral_cutoff`/`spectral_band` return a **`RadialKernel`** — the symbol σ(|k|²) itself, evaluated per mode (a closure + three references vs `O(N³)` coefficients; signatures unchanged), with `radial_kernel(σ, mult)` for any other symbol (integrating factor, smooth filter, hyperviscosity), `materialize_kernel` the opt-in escape hatch (and `materialize_kernel!` its allocation-free twin into an existing `StoredKernel`, decision 90), radial∘radial composing into a radial and radial∘separable into a lazy `ProductKernel` (cross-family, one pass), and `weighted_inner` accepting a radial weight but deliberately not a separable one. A symbol closure must capture **values, never a type** — a captured `Type` is not a bitstype and a GPU launch rejects it. `spectral_cutoff` builds the isotropic sharp low-pass (de-aliasing) kernel; `spectral_band(mult,wavenumber_low,wavenumber_high)` is the annular generalization (cutoff = the `wavenumber_low = 0` case); `radial_kernel(identity, mult)` is the `|k|²` symbol itself (the consumer builds `exp(−ν|k|²Δt)`/envelopes/Germano from it — invariant 12, decision 21; the materializing `squared_wavenumber_field` was removed by decision 60); `assignment_window(mult)` is the linear/CIC mass-assignment window `Ŵ=∏ sinc²(kₐΔxₐ/2)` for **deconvolving** a gridded point density (Phase 2 of the RDF route, decision 22); `tophat_window(mult, width)` is the box average of edges `l` (one number for a cube, a triple for a rectangular box), the per-axis `sinc(kₐlₐ/2)` as a `SeparableKernel` from the true `kₐ` — HT's request of 2026-09-22 for its scale-resolved energy `k(l)` — and `assignment_window` is now that window at the grid spacing composed with itself, `convolve(w, w)`, bitwise the former closed form (decision 87); `translation_kernel(mult,h)` is the shift theorem's phase `ĝ=e^{−ik·h}`, which **displaces** a field by a physical offset h (`f ↦ f(x−h)`) — the one **complex** kernel, whose Nyquist value must be the *real* factor `cos(πhₐ/Δxₐ)` (even part ← true `|k|`, odd part ← the Nyquist-zeroed derivative `k`; the first op to use **both** multiplier families — invariant 5) or the result is no real field's spectrum (decision 28). **Decision 50:** `translation_kernel` and `assignment_window` return a **`SeparableKernel`** — the three per-axis factors they already built, with the final materialization dropped, so the kernel costs three `O(N)` arrays instead of `O(N³)` coefficients (~10 KiB vs 129 MiB at 256³) and a pass reads no kernel storage; bitwise-identical results (the tests use the materialized product as oracle), decision 28's Nyquist split untouched, with per-axis `convolve` composition, `inv` (the reciprocal, = the deconvolution), and the in-place `translation_kernel!`. A kernel argument is any of the four storage classes **package-wide** (the protocol — the exported
supertype `SpectralKernel` (decision 65) plus `_kernel_data` and `_check_kernel_compatibility` — lives in `Fields` so `DifferentialOperators` and `Reductions` can see it too; a test walks every kernel-taking entry point and requires both classes to agree bitwise); the generic `ScalarFieldSpectral` path stays for kernels that are not closed forms. **Decision 33 (IT items 2+7):** `exponential_convolve!`/`exponential_convolve` apply the exponential radial kernel `exp(c·|k|² + s·ŵ)` **lazily from the wavenumber arrays** (never materialized; for c≤0 the periodic Gaussian `e^{−cΔ}`; ŵ an optional real per-mode field entered as scale×field so a per-call scale is free; a *scalar* offset is a deliberate absence — it folds into α as `e^{s₀}`), with single-operand α/β forms and two-operand `(dest, α, a, β, b, mult; coefficient[, offset, offset_scale])` forms (the exponent by keyword since decision 101), ŵ a stored field or, since decision 92, a `RadialKernel` evaluated once per mode beside the exponent (a radial rate stores nothing); and `combine!` gains the kernel-composed method `combine!(dest, α, a, β, b, kernel)` (defined here, not FieldAlgebra — the parity baseline filters by module, so 206 stands), the decision-32 trailing-kernel idiom; `b === dest` is the filtered accumulate (alias-safe, so no second trailing α/β — the glyph-collision rule). Imports the spectral types + helpers from Fields. `docs/ARCHITECTURE.md` §2, decisions 20, 21, 22, 28, 33.
- `src/Points.jl` — the unstructured base (with the point↔HDF5 persistence generics `write_points`/`read_points`, the field pair's twin — a `PointSet` or a point-value section maps to one self-describing group, positions and values kept separate; methods in the same weak-dependency extension; decision 46): point-data types (`Point`, `PointSet`, and `ScalarPointValues`/`VectorPointValues`/`TensorPointValues` under `AbstractPointValues <: AbstractFiberSection`, all exported) and their **full fiberwise algebra** (M2 + M3 mirroring the field surface in physical representation, generated by reusing the FieldAlgebra builders over an extended section interface — no formula written twice), plus the representation-free peer of **`map!`/`map`** (decision 48; reusing FieldAlgebra's shared `_map_pass!` driver, no physical-only split), and **base-space motion** (decision 73): `displace!` — each point moved along coefficient-weighted `VectorPointValues` sections, `x_p ← x_p + Σ_j c_j v_j(p)`, the exponential map of the flat torus (a named verb, never `+` — positions are not vectors), n-term fused into one traversal per group of eight terms (decision 88 — a caller-chosen count is grouped, the torus wrap once after the last group), in the universal cover (no grid — winding preserved) or on the torus proper (a trailing `Grid3D`, the wrap fused in), destination/source or in-place, coefficients part of the definition (the `combine!` α/β-exception class), no allocating sibling — and `wrap!(points, grid)`, the canonical representative in the half-open `[o, o+L)` per axis: origin-aware, endpoint folded (`mod(-1e-20, 2π) === 2π` is pinned), non-finite in ⇒ non-finite out so a diverged trajectory is never silently boxed; sampling needs no wrap (deck-invariant stencils, documented with its honest range limit), but canonicalization is precision-load-bearing on long runs. Implemented and tested.
- `src/Interpolation.jl` — the grid↔point transfer: **interpolation** (gather `W`, grid→point; also the callable `f(x)`) and its adjoint **anterpolation** (scatter `Wᵀ`, point→grid, with α/β), an adjoint pair under one `AbstractTransferScheme` (exactly L²-adjoint after the `N/M` measure rescaling) (a scheme = choice of *kernel* + *representation*; decision 23). **Two families.** *Physical-domain splines* (`AbstractSplineScheme`): smooth `LalescuSpline(stencil_width; smoothness = stencil_width ÷ 2 - 1)` (two-point Hermite, `CatmullRom = LalescuSpline(4)` the usual choice, TurTLE-pinned; the scheme is a required positional argument of the transfer verbs since decision 97, and the constructors take the stencil width since decision 98) and `C⁰` `LagrangeSpline(stencil_width)`; portable KernelAbstractions + Atomix kernels (CPU/CUDA/AMDGPU, atomic scatter); shared partition-of-unity weights ⇒ conservation. *Spectral-domain exact transfer* (`DirectDFT`, on a field in spectral representation): the literal `O(NM)` inverse/forward DFT `f(xₚ)=(1/N)Σₖ α(k)·Re(f̂ e^{ik·(xₚ−o)})` / `Σₚ qₚ e^{−ik·(xₚ−o)}` — reproduces the band-limited field exactly (divergence-free reference; matches `to_physical` at nodes), the transparent baseline + the oracle for the native fast `NUFFT(reference; tolerance)` — or, since decision 103, `NUFFT(array_family, grid, Val(R); layout)` for a caller holding no field — (`O(N log N + M)` windowed gridding = spread→FFT→deconvolve, reusing the transfer kernels + oversampled plans + an `assignment_window`-style deconvolution, and since decision 85 the public `embed_modes!`/`extract_modes!` for the coarse↔oversampled step, which retired its own index maps; own-native, no dependency; exact to ε vs `DirectDFT` on the resolved **sub-Nyquist** band — the rfft Nyquist is projected out, so the pair stay exact adjoints). With the **traversal order** (decisions 78, 80): `point_traversal_order(grid, points; tile_size)` builds a permutation grouping points by block of grid cells, and the four point-indexed verbs take it as a `traversal` keyword — a TRAVERSAL order, not a reordering (`traversal[i]` is the point the `i`-th unit of work handles), so nothing moves, no signature changed, the gather is bitwise invariant under it, and a `PointSet` cannot desynchronise from the `PointValues` beside it; built by a portable counting pass (three KA/Atomix kernels, no new dependency, 0.1 ms at ``256^3``), worth ``3.4``–``4.5\times`` on device at ``256^3`` with ``10^6`` points and repaying inside a single transfer. Points move and an order goes stale as they do, so `point_traversal_order!(traversal, grid, points, scratch)` rebuilds one in place against a `PointTraversalOrderScratch` — nothing it allocates scales with the point count, where the allocating form costs about 15 MiB at ``256^3`` with ``10^6`` points on a device pool a host-pressure collector cannot see (decision 80). The same decision made the periodic wrap a WALK (`_wrap_step`, a conditional zero per node instead of a `mod`), bitwise identical and worth ``1.3``–``2.1\times`` on the CPU gather. With **scheme persistence** (decision 75): `write_scheme`/`read_scheme` map a transfer scheme to and from one self-describing HDF5 group (bare generics + docstrings here, methods in the same weak-dependency extension as the field/point pairs), so a checkpoint restores not only where a point set samples but how. A scheme is a **parameter record, not a section** — the spline weight matrix is derived from `(n, m)` — so the group carries attributes and **no `data` dataset**, and reading reconstructs through the ordinary constructor (which revalidates `0 ≤ m ≤ 2n`); the element type is resolved through a **closed table, never `eval`**. Covers `LalescuSpline`/`LagrangeSpline`/`DirectDFT` (`CatmullRom` is `LalescuSpline(1,1)` and needs no identity of its own); **`NUFFT` is a documented refusal** — it owns oversampled plans and a reference-bound window, the `FieldTransformPlans` class decision 63 rebuilds rather than moves. A test-side completeness guard walks every concrete scheme type so a new family cannot ship unpersistable. The same change gave all three read verbs one shared schema-version gate — `read_points` had never checked its version, though the extension header claimed it did. `docs/ARCHITECTURE.md` §10, decisions 23, 75.
- `src/Reductions.jl` — the **L²/measure structure** (the third operation family, after the vertical fiberwise algebra and horizontal differential operators): base reductions over `AbstractFiberSection`, against the base's measure (`Grid3D` cell volume / `PointSet` counting). `integral` (extensive `∫f dμ`), `inner`/`l2norm`/`lpnorm` (normalized L²), the multiplier-weighted `weighted_inner(f[,g],w) = ⟨f,w·g⟩` (spectral-only, the reduction-dual of `convolve`, generalizing `inner`; `w=|k|²` is the Dirichlet energy; fused, allocation-light; decision 27) — which also takes a **tuple of weights**, answering up to four in one traversal and one device readback rather than one per weight, a longer tuple one traversal per group of four (decision 88 — a 32-weight tuple had failed to compile on a device) (bitwise-equal to the separate calls; **wins on all ten lanes — 1.16–2.97× on the two CPUs (median 1.33), 1.51–2.81× on the two GPUs**, re-derived 2026-08-31; the entry's original "1.64–1.97× uniformly" is RETIRED — finding (ac) moved the CPU leg onto the threaded fixed tree, which is the path both compared rows traverse, so the ratio moved without either arm changing; decision 72). The weight is a kernel in **any** of the four storage classes — all bitwise-equal, the former `Union{StoredKernel,RadialKernel}` having been a narrow signature rather than a constraint — and a **complex** weight is refused wherever the type can decide it (`combine_eltypes`, a folded branch measured free), so `translation_kernel`'s phase cannot be silently read as its real part; `StoredKernel` is the documented exemption, its complex storage carrying no information about the multiplier (decision 62), and `mean`/`std`/`var`/`cov` (extending `Statistics`; `mean` fiber-preserving, `std`/`var` scalar-only, `cov` the vector covariance tensor) + `maximum`/`minimum`/`extrema` (extending `Base`, scalar sections). Every reduction also has a **mapped form** taking a leading fiber map — `mean(det,A)`, `maximum(norm,u)`, `integral(det,A)` — reducing a nonlinear fiber invariant in one fused pass with **no intermediate section** (mirrors `Statistics`' `mean(f,itr)` / `Base`'s `maximum(f,itr)`; `var`/`std` have no such stdlib spelling, so neither do we; naming the map is also what makes an order statistic well posed above R=0, lifting the bare scalar-only restriction; physical-only, since the map is nonlinear). **The reduction is split by backend so fused wins on BOTH** (`_reduce_fiber`): CPU gets a pairwise-blocked vectorized loop over the component arrays, GPU keeps one fused `Broadcasted` pass. Reason: reducing a lazy `Broadcasted` forfeits the CPU's vectorized blocked reduce loop (5.6× on the reduce alone), costing more than the extra section materializing moves; a GPU has no such loop to lose (thread-parallel, bandwidth-bound) and fusing saves it a section write+read-back. Same-map A/B (`mean(det,A)` vs `mean(det(A))`, 128³ F64): CPU 5.1 vs 13.0 ms, GPU 0.55 vs 0.69 ms — fused faster on both, 0 bytes vs 16.8 MB. Pairwise blocking also makes the CPU path the most *accurate* route (1.2e-16 vs the lazy form's 3.7e-15). Strided gather is only ~2×; the `StaticArray` build is free. **Measurement trap (hit twice):** `LinearAlgebra.norm` on a fiber is the overflow-safe scaled 2-norm, 4.3× the naive `√Σuᵢ²` the fieldwise `norm` uses — so `maximum(norm,u)` vs `lpnorm(u,Inf)` varies algorithm AND route and falsely reads as a fusion penalty (same formula: fused 1.8 vs 4.2 ms). Vary one thing at a time. Three spellings silently allocate and are pinned at zero by `test/allocations.jl` (multi-arg `mapreduce` materializes a section on CPU; a vararg closure has an uninferrable component count; a forwarded `Function` arg needs its type named in the signature or Julia will not specialize). Decision 30. Measure reductions on **fields in physical representation + point-values**; `inner`/`l2norm` (Parseval — equal to the physical inner, rfft half-spectrum weighting) and `integral`/`mean` (the zero/DC Fourier mode, reusing `_spectral_zero_mode_data`/`_spectral_constant_scale`) *also* act on fields in **spectral representation**, equal to the physical value with no transform, and the **radial reductions** `radial_spectrum(f,mult)` (shell-resolved inner = the radial power spectrum, spectral-only) + `radial_correlation(f,plans)` (its physical-space Wiener–Khinchin dual, the shell-averaged two-point autocorrelation `C(r)=𝓕⁻¹(|f̂|²)/N`); `sum(spectrum) == C(0) == inner` (decisions 21, 22), each with a **two-field co-spectrum** form `radial_spectrum(f,g)` / `radial_correlation(f,g)` (cross-power / cross-correlation, refining the mixed `inner(f,g)`; symmetric, may be negative; the one-field forms are the g=f case). `mean(points) = (1/M)·Σ` (counting measure). The radial reductions share two device-clean **fused scatter-add** binning kernels (shell index, fiber contraction, and Parseval weight derived per element from the mode/grid index — no staging arrays; the shell count analytic from the corner; decisions 25, 34): `radial_spectrum` is pinned allocation-tight, `radial_correlation` keeps only its substance (the power field + the allocating inverse transform). Physics stays consumer-side. `docs/ARCHITECTURE.md` §2, decisions 18, 21, 22, 25, 34.
- Include order: FiberSections → Fields → FieldAlgebra → DifferentialOperators → Convolution → Points → Interpolation → Reductions. Cross-module access only through explicit `using ..Module: name, ...` lists — never a bare `using`.
- `ext/` holds weak-dependency package extensions (Julia `[weakdeps]`/`[extensions]`) — currently `GBGPeriodicFieldsHDF5Ext` (section↔HDF5 I/O — `write_field`/`read_field`/`read_field!` for fields, `write_points`/`read_points` for the point layer; loaded only when `HDF5` is present; decisions 29, 46). Bare `function … end` stubs + docstrings stay in the core so `?write_field` works without HDF5.

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
   fused pass (the one-pass differential operators and the `_fiberwise_pass!` executor behind the
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
    accumulated onto. **Two deliberate exceptions, and only these two:** `combine!` IS the weighted
    combination `α·a + β·b`, so its weights scale its two *operands* — what the operation is, and what
    its name announces — and `exponential_convolve!`'s two-operand forms
    `(dest, α, a, β, b, mult; coefficient)` carry that same combination into a fused convolution. Both are
    operations whose definition IS a weighted combination. No operation may reuse the glyphs for any
    other role; that is the glyph-collision rule decision 33 applies when it declines a second
    trailing α/β.
11. Transform input contract: allocating `to_physical`/`to_spectral` preserve their
    input (they copy it); the in-place `to_physical!`/`to_spectral!` may overwrite the
    source. The inverse real transform (FFTW complex-to-real) destroys its spectral
    input as scratch, and this is backend-divergent (AMD/rocFFT preserves it). Never
    rely on a plain `!`-transform's source surviving; use the allocating form to keep it, or the
    four-argument `to_physical!` scratch arity (decision 64), the one `!` call that guarantees
    preservation — it consumes the caller's scratch instead.
12. **Math backend — no time, no particles.** The package is a field-operation library that
    solvers consume, not a solver. Use domain-neutral terminology (base/fiber, point/value),
    never *particle*/*tracer*. Introduce **no concept of time** — no advection, time
    integration, temporal interpolation, or per-step state; trajectory dynamics belong to the
    consumer. The interpolation data types follow this: `Point` (alias `SVector{3,T}`),
    `PointSet` (SoA positions), `PointValues` (three field-mirroring types). See `docs/ARCHITECTURE.md` §10.
13. **Allocation-free is an enforced contract** (`RULE.TEST.ALLOC_ZERO`; the audit is declared to the
    tool). This is load-bearing for GPU hot loops: a
    per-call device temporary escapes Julia's GC (which triggers on *host* pressure, blind to the *device*
    buffer a dead array owns), so the pool grows every step until the run wedges (decisions 24, 25, 26).
    **A threshold cannot see a constant that never grows, so the class is also pinned at zero where
    zero is knowable.** Most rows are `@alloc_below field_threshold` (one field plus `4096 ×
    nthreads()`), and that slack is honest — FFTW reaches its workers through a Julia callback, so a
    multi-threaded plan allocates nondeterministic task state, 7008–48557 B for one configuration
    across runs (`docs/PERFORMANCE.md` §4(t)). But decision 76's per-component transforms then leaked
    a **constant 128 B a call** — two `reshape` wrappers, one per operand, `reshape` on an `Array`
    returning a new heap-allocated `Array` sharing the data — and it sat under that threshold for ten
    days, invisible here and found by a **consumer** whose hot loop asserts literal zero per step. The
    transforms therefore carry a second lane that sets FFTW to one thread, where the callback is gone
    and the only remaining bytes are the package's own, and asserts `== 0` for `R = 0, 1, 2`.
    The audit is `test/allocations.jl`. It runs on the host, and a device can allocate where the host
    does not: the in-place `displace!` on the torus copied a column per axis on CUDA only, a device
    view being a new array each time it is made (decision 95). The GPU suite therefore carries an
    aliased-allocation lane asserting zero device bytes for each in-place operation with its
    destination also an input. Deliberate materializers (`norm!`/`lpnorm` — `dev!` left the list when decision 39
    fused its trace into a register and `std`/`var` when decision 49 rewrote them as two fused passes, `radial_correlation` (the power
    field + its transform; `radial_spectrum` is pinned tight since decision 34), the mixed
    spectral `inner(f, g)` — rocBLAS offering no `dotc` over a strided `ROCArray` view) are the documented
    exceptions.
14. **Sections combine only within one precision and one array family — never by conversion.** An
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
    multi-argument operation routes through one of them or states why it need not. Conversion is an
    **explicitly-named operation**, never something arithmetic does implicitly: crossing **storage
    families** is `adapt`, extended from `Adapt.jl` and re-exported (decision 63), or `adapt!` into a
    destination that already exists (sections only; decision 69) — and crossing **precisions** remains
    future work (roadmap below). That `adapt!` is a package-owned verb rather than a `copyto!` method
    is the point, not an accident: the package's `copyto!` is the broadcast entry point, so a
    section-to-section `copyto!` that crossed families would cross where `destination .= source`
    refuses under this very invariant.

## Code generation rules (FiberSections + FieldAlgebra)

- Per-component formulas are written **once** in `FiberSections` (shared by `FieldAlgebra` and
  `Points`); `@eval` tables in each consumer stamp out the representation, argument-order, and
  in-place/allocating variants. Builders (all in `FiberSections`):
  `_vector_component`/`_tensor_component` (kinds `:field`/`:fiber`), `_sum_terms`,
  `_product`, `_vector_kernel_body`/`_tensor_kernel_body` (with `alpha_beta` flag),
  `_scalar_kernel_body`, the contraction/decomposition formula builders, and `_section_scalar_type`
  (real `T` for any section), and the **fused fiberwise executor** `_fiberwise_pass!` (decision 39:
  one KA kernel + one slab-threaded linear `@simd` CPU loop running every stamped values function;
  the former per-consumer alias guards are retired — fused passes are alias-safe by construction).
- Generators emit **methods only — never docstrings**: `function f end` for package-owned
  generics, the bare imported name for Base/LinearAlgebra functions. Docstrings list a few
  canonical signatures plus validity prose, and mention intentional absences.
- Irregular corners stay explicit **with a comment saying why** (scalar±Real family,
  the four ambiguity-resolving `multiply!` methods, physical-only divisions).
- Validation: call `Fields._check_field_domain_compatibility` (imported explicitly)
  **directly** — no aliases or wrapper names. Placement rule: broadcast-mediated
  bodies do not pre-check (the broadcast machinery enforces compatibility); paths
  that bypass broadcasting (copy + kernel, zero-mode updates) check explicitly.
- Operators are defined in `function +(...) ... end` form (the parse-proven house
  style); short form only for `+(field::AbstractField) = field`.

## Documentation policy — the docstring rubric

The rulebook holds the docstring rubric; what follows is PF's own part of it. §Style below elaborates
the individual conventions and their rationale, and the rendered glossary at `docs/src/notation.md` is
the reader's copy of the notation.

**Two-tier structure.**
- **Module docstring.** The invariants a PF module's map names are physical vs spectral representation
  and the base measure.
- **Function docstring — PF's part.** The order is `RULE.DOC.HOME_ORDER`'s. The caveats a user needs are
  memory, accuracy and gotchas, as a `!!! warning` where load-bearing; a **named/published** method carries
  an inline citation verbatim-consistent with `ARCHITECTURE.md` §References, and a classical one (the
  Lagrange interpolant, Fornberg weights) none. **Exclude:** implementation internals (→ `#` comments),
  unexplained specialist jargon, architectural rationale (→ `ARCHITECTURE.md`), and the formal/intrinsic
  apparatus (→ `FORMALIZATION.md`).

**Operator aliases.** The operator aliases (`+ - * / ⋅ × ⋆`) are thin wrappers of the `!` home, as
the allocating form is, and the bare operators `+ - * /` carry thin allocating docstrings so the pairing
is documented and REPL-visible.

**The four shape rules (user-decided 2026-07-24; the `/check-consistency` uniformity pass).** The
rubric above says what a docstring must *contain*; these fix the *shape*, so the same content is not
written four ways. **(1) Arguments.** The marker is an `# Arguments` heading. Count the arguments a
*signature* takes, not the distinct names across type-specialized variants (`norm!` takes two in every
overload and stays prose). A **thin allocating wrapper is exempt**: it documents no arguments at all, leading with the
one-sentence meaning and `@ref`-linking the home, so the threshold never applies to it. **(2) Types.**
Prose is reserved for the one-sentence identity above the `# Fields` section. **(4) The in-place steer** sits after the identity paragraph and before the arguments, and names the
destination argument the signature actually has — `destination` in most of the corpus, but `out` in
`interpolate!` and `field` in `anterpolate!`.
**(5) Aliasing.** PF's cases: `cross!`, `transpose!`, `sym!`, `skew!` and `dev!` carry nothing locally
and are correct as they stand; `curl!` and `helmholtz_projection!` state it in their `destination` bullet
because each reads all three components of a mode before writing any (moved there on 2026-08-05, the
majority position of `convolve!` and `combine!`); `mul!` states its contrary contract, a destination that
must **not** alias.

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

**API pages are math-grouped.** Group public objects into the operation **families of
`ARCHITECTURE.md` §2** under hand-written `###` headers via explicit `@docs` blocks (not `@autodocs`,
which cannot express a semantic group), each object in the family whose defining mathematics it
realizes; keep an `f`/`f!` pair together with the `!` home first; order a group by increasing tensor
order. Lead a page with its **headline operations**, then the supporting types/schemes they take
(Interpolation: the transfer operations before the transfer-scheme catalogue). Keep `@contents` as the
table of contents. `checkdocs = :exports` guards a dropped export.

**Notation** (glossary: `docs/src/notation.md`). Indices are italic ``i, j, k, \dots`` in order, used
freely alongside the upright imaginary unit ``\mathrm{i}``; a partial derivative is
``\partial_{x_i}`` (subscript the coordinate), and a second-order derivative is ``\partial^2_{x_i x_i}`` (a
repeated fiber index is summed, Einstein convention — so the Laplacian is ``\Delta f = \partial^2_{x_i x_i} f``,
no explicit ``\sum``).

**Prose is grammatical.** The defects named here are verbless fragments, noun-stacks, `label:`-colon
tags and comma splices; restore the grammar without adding fluff.

**Sentence openers.** A lowercase start is fixed by **rewording** so an ordinary word leads — never by
capitalizing the identifier, whose binding is lowercase by nature (`` `divergence` uses this kernel`` →
"The `divergence` operator uses this kernel"; a formula opener `` ``n = 0`` is linear`` → "The case
``n = 0`` is linear"). A Literate example's full-line `# ` line **renders as prose**, so it is **not**
exempt as a code comment is; and a **capitalized** type/module/file opener (`Point`, `DirectDFT`,
`RESULTS.md`) already begins with a capital.

**Correctness is verified, not asserted.** PF's recorded false equivalences: the cross-product index
splice, `LalescuSpline(n, 0)` vs `(0, 0)`, and the false
`LagrangeSpline ≡ LalescuSpline(n, 0)` (linear vs degree ``2n+1``).

**Intrinsic maps and concrete forms.** PF's intrinsic maps are `ι*`, `ι_*`, the pushforward of Dirac
measures and `Π_d`; the concrete forms a docstring uses for them are ``\sum_p``, ``\int_\Omega`` and
`W`/`Wᵀ` as named maps.

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

**Physical-space meaning first — PF's cases.** `Convolution` is the reference: `convolve` leads with the periodic filtering integral (f⋆g)(x) = ∫_Ω f(y)·g(x−y) dy (and
its discrete circular sum) before the coefficientwise product f̂·ĝ; `assignment_window` leads with the
linear/CIC B-spline "tent" cloud W(x) before returning its transfer function Ŵ. Where no clean form
exists, the docstring says so: a sharp spectral cutoff is a non-compact sinc/Dirichlet kernel, and
`squared_wavenumber_field` was the symbol of −∇² rather than a kernel. **Correctness:** check the physical↔spectral relation is *exact* for the package's convention
(unnormalized forward, invariant 4 — the convolution theorem holds for both the integral and the discrete
sum); a stray 1/N, cell-volume, or |Ω| normalization factor is the easy slip here.

**The symbol bound to the code.** Mathematics uses **standard notation** (∇, Δ, ⟨·,·⟩, ‖·‖, ∫, 𝔽,
etc.), and **every code object is explicitly bound to its math symbol on first mention** — `laplacian` (``\\Delta``), `gradient` (``\\nabla``), `inner`
(``\\langle\\cdot,\\cdot\\rangle``), the spectral representation written ``\\hat f`` — so the reader
always knows which symbol *is* which function. Plain `#` code comments stay Unicode (they are
not rendered). `Reductions` is the reference implementation of this convention.

**Signature wrapping.** A long docstring signature is hand-wrapped with a hanging indent under the first
argument (the `anterpolate!` convention, ≤ ~88 source columns).

**Math spacing and command support — standard LaTeX idiom.** These are the conventions a fluent LaTeX
author writes by default; the defects they head off — manual spacing, reflexive ``\\left``/``\\right`` — are
novice tells, not subtle bugs. KaTeX supports a subset of LaTeX, so for anything tool-specific consult
KaTeX's published support table — do not assume parity.

**These are correct — do NOT "fix" them:** ``\\sim\\!`` and relation-modifier tightening; ``\\quad``/``\\qquad`` for display-equation separation; and
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
points::PointSet, …)`). Wrapping is **docstring-only**: the source `function` definition
is left exactly as written, however long (it is not a rendered surface, so its length does not matter). A
generic multi-dispatch *summary* (the `add!`/`subtract!`/`combine!`/`multiply!`/`divide!` M2 family) types
the args carrying one type across the overloads (`α::Real`) and keeps generic the ones that span types (a
field argument; `constant` = `Real`/`FiberVector`/`FiberTensor2`) — `add!(destination, a, b, fields...)` is
such a summary, with no variadic method in the code to mirror.

**The representation qualifier TRAILS what it qualifies — in identifiers as well as prose (codified
2026-09-02).** Invariant 2 bans "spectral field"; the same ban binds an identifier, because a name is
read as prose. This is why the types are `ScalarFieldPhysical` and `AbstractFieldSpectral` rather than
`PhysicalScalarField` — the trailing qualifier reads "scalar field, physical representation", which is
what invariant 2 asks for, and the leading one reads as the phrase it forbids. The rule was implicit in
the type names and unwritten, so the FUNCTIONS drifted the other way and six of them read as violations
for months: `physical_field_shape`, `spectral_field_shape`, `_physical_field_of_order`,
`_spectral_field_of_order`, `_similar_physical_field`, `_similar_spectral_field` — now
`field_physical_shape`, `field_spectral_shape`, `_field_physical_of_order`, `_field_spectral_of_order`,
`_similar_field_physical`, `_similar_field_spectral`. Placing the qualifier immediately after `field`
also makes the name mirror the TYPE it describes, so `AbstractFieldPhysical` ↔ `field_physical_shape`
is a correspondence a reader can rely on.

**The rule binds only where the adjective modifies the FIELD**, and the exemption already recorded
below is unchanged: `spectral_cutoff`, `spectral_band`, `radial_kernel` and `FieldSpectralMultipliers`
are NOT in this class, a kernel being a genuinely spectral object; nor is a local naming a field in one
representation (`spectral_scratch`, `physical_prototype`) or a property of the storage
(`spectral_stride`). A sweep that flags those is over-reading the rule — the first one run here did.

**Operators are not "spectral" — the representation adjective stays off the operator (user-decided
2026-08-14).** Gradient, divergence, curl and their family are ordinary differential operators on the
real physical object; what is spectral is where the package applies them. Write **"the differential
operators"** bare (the module name carries no adjective), and where the representation matters,
**"applied as spectral multipliers"** — the same rule as invariant 2's "field in spectral
representation, never spectral field", one type up. "Spectral kernels", `FieldSpectralMultipliers`
and the `spectral_*` API names are NOT in this class (kernels genuinely are spectral objects; API
renames are breaking), and the decision log keeps its original wording.

**Neutral reference register.** PF applies it to docstrings, the four design docs, the doc pages, `#`
comments and `@testset` names.

**Positional vs keyword arguments — PF's part.** Since GBGCodingTools rc.63 the rule makes every
argument with a default a keyword, so PF's four former switches (`origin`, `array_type`, the callable
field's `scheme`, `corrected`) comply and were removed on 2026-10-06; positional arguments with a
default in PF's surface are now review findings, an interface change being the owner's to approve.
One switch remains, owner-decided 2026-10-07 (decision 100): `RealFourierLayout(fft_dims)` keeps its
positional default, its argument being the layout value itself. **Decision 103 (2026-10-15) audited
every default and name** under the consumer's rules: a default is written as its value and `nothing`
names only an absence the docstring states; a setting qualifying an absent term is kept and stated
(`offset_scale` with no `offset`, `fft_timelimit` under `ESTIMATE`); a name mirrors its interface or
is a full word (`npoints` stays as Base's count idiom). The entry lists what was checked and found
consistent, so a later audit closes against it.
`point_traversal_order(grid, points)` leads with the grid because it is TRANSFER infrastructure — the
transfer verbs' order (`anterpolate(grid, points, …)`), not the motion verbs' trailing-grid one
(`wrap!(points, grid)`); the two families are deliberate and a new function joins the family whose
verbs it serves.

**Greek scalars — PF's names.** The locals are `α_value`/`β_value`; the NUFFT's quadrature locals
`omega`/`theta` stay ASCII with its window-shape `beta` (the keyword is `window_shape` since decision 103); and TurTLE's `beta_n{n}_m{m}` weight name is
external and stays.

**Cost register, not time — a docstring frames expense, never temporal cadence.** The package carries no
concept of time (invariant 12), so a **docstring must not describe *when* or *how often* a consumer calls
an operation** — never "per-step call", "occasional diagnostic", "every step", "each timestep", "hot loop"
(usage-frequency framing). State the **cost** instead, with a concrete quantitative anchor: fused vs.
allocating, single pass vs. several, ``O(1)``/``O(N)``/``O(N\log N)``, "one wavenumber row, not a field",
"comparable to one `inner`", "far cheaper than …". The reader decides the cadence from the cost. (`weighted_inner`
was reworded from "suits a per-step call, unlike the occasional shell diagnostics" to "a single weighted pass,
comparable to one spectral `inner` … far cheaper than the radial reductions, which build an ``O(N)`` shell-index
pass"; `radial_spectrum` likewise.) The **rationale docs** — `DECISIONS.md` (esp. the decision-24/26
allocation contract), `PERFORMANCE.md` — *may* reference the consumer's per-step solver loop, since explaining
*why* allocation-free matters requires it; a bare function/`#`-comment mention of "each call" (an invocation, not
a time unit) is also fine. The bar is on **docstring prose**.

**What documents an argument.** A ``- `arg` — …`` bullet, a binding clause, an `arg = value` mention, or
a `::Type` for a conventional first argument.

**`docs/ARCHITECTURE.md` is self-contained — PF's part.** It covers package-specific math symbols too
(`W`/`Wᵀ`, the base, the fiber, tensor order `R`, `ψ̂`, `κ`, `α`, the counts `N`/`M`, the origin `o`, …);
keep the header's self-contained note true when editing. The decision log is held to the rule's scope,
which exempts it (owner-ruled 2026-09-27).

**Citations — PF's part.** Inside an existing parenthetical the year is bare, with no nested
parentheses (`(de-aliasing; Sundaram & Collins 1996)`). The canonical reference list is `docs/ARCHITECTURE.md` §References: the works the package **implements /
pins to** — Lalescu 2010, TurTLE 2022, van Hinsberg, Fornberg, the anterpolation lineage. A DOI in a
docstring stays REPL-safe, the URL rendering as visible text rather than a dead link.
Non-implemented related-work asides (e.g. LES SGS models) may stay informal author–year with no full
reference; plain `#` code comments are exempt (not rendered). The inaccessible source PF must never cite
is the gitignored monograph under `inspiration/`, and the downloadable `examples/` scripts and READMEs
are user-facing surfaces too; present every diagnostic on its own public terms (the trace structure
functions and their K41 normalizations are standard turbulence — describe them, at most cite a public
source).

**Standing open item (2026-07-22 battery remainder).** The economy `/check-docs` run (13 Sonnet
lanes + main-thread synthesis; raw findings, removed with the old instruments on 2026-10-06, in git history) fixed
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

**An argument-shape inconsistency is SETTLED, not a defect (user-decided 2026-08-05).**
`radial_kernel(sigma, multipliers)` leads with its **function** where
`spectral_cutoff`/`spectral_band`/`assignment_window`/`translation_kernel` lead with their multipliers:
leading with the symbol follows Julia's `map(f, collection)` convention for the argument that
distinguishes the general builder from the named ones. Changing it is breaking. A later review that
re-raises it should close against this note.

**The `/check-docs` battery is CLOSED (2026-08-04).** Eleven economy lanes (nine surface lanes + the
family and cold-reader lanes) plus the deterministic guards and the built-HTML pass; every finding
verified in the main thread and closed as fixed or dismissed-with-reason. **Three were mine, from the
decision-60 work three days earlier:** `ARCHITECTURE.md` had **no decision-log entry for decision 60** while
citing it four times (definition-of-done item 3, skipped), the invariant list said "Thirteen rules"
after invariant 14 was added, and three `Fields` compatibility docstrings never mentioned the
array-family check that invariant 14 had put in their code. **Two were real defects rather than
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
were recorded rather than churned (above). A build lint for the decision-60 claim class was added the
same day; since the migration to GBGCodingTools, `RULE.DOC.RETIRED_CLAIMS` is that guard.

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
turbulent kinetic energy there); and decision-log mentions of the retired `_guard_noalias!` stay
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

**Mathematical correctness — PF's slips and its chain.** Check which *spaces* a map acts between, the
fiber included, not only scalar formula values: the `𝟙`/`W` transfer slip wrote the section space
`ℝ^N⊗V` as `ℝ^N` (flattening the fiber) and conflated the grid all-ones `𝟙_N` with the point `𝟙_M`, a
structural error the value-check missed because it verified formulas, not spaces; "the fiber *is* the
tensor order" equated a vector space with an integer. Watch for overclaims ("exact"/"all"/"never" that
aren't literally true; bounded-vs-unbounded multiplier confusions; continuum-integral vs discrete-sum).
The §10 `⟨Wf,q⟩ = ⟨f,Wᵀq⟩` slip — clean only for the measure-adjoint `ι_*`, but off by the `N/M` measure
factor for the implemented (counting) transpose under the *normalized* inner — passed a read-through and
was caught by a code-check (`inner = dot/_base_count`). The nontrivial statements live formally in
`docs/FORMALIZATION.md`; check each prose claim **against its entry** — the chain is *prose ↔
formalization ↔ test* (the prose must agree with the typed statement, the statement is verified against
the code, the linked test enforces it numerically) — and treat a nontrivial claim with **no entry**, or an
entry with **no test link**, as a coverage gap. Hand-verified typed notes, not a proof assistant.

**Doc-edit checks — PF's part.** Symbol binding is run as a **positive enumeration**, not a read-through:
list every distinct symbol, sub/superscript, operator name and bold/blackboard letter in the passage and,
for each, quote the clause that binds it; a symbol with no citable binding **is** the defect — the
elementary ones included (`f` the field, `x` a position, `q` a per-point value), which is how `f`/`x`/`q`
once slipped through a review. Every code identifier — functions, types, **module names**
(`FieldAlgebra`, `DifferentialOperators`, …), struct fields — is **always** backticked and **never** bare
(the bare-`FieldAlgebra` slip). And a docstring or summary that names only a *subset* of what the code now
provides is stale even if every sentence is literally true (the Interpolation module docstring said "uses
the local spline interpolation" after the spectral `DirectDFT`/`NUFFT` schemes shipped): check each
module, operation and summary against the current `export`s and method set.

**A flagged instance is a sample of a class.** When the class is swept, report the class and the count.

**"Check the docs" — PF's surfaces.** They are `ARCHITECTURE.md`, `FORMALIZATION.md`, `TESTING.md`,
`PERFORMANCE.md`, every `src/` docstring and every `docs/src` page, and the report is the matrix
(surfaces × checks: findings, fixes, and what is verified clean). **Cheap
(economy) scan lanes are the DEFAULT — full-strength lanes only on explicit request — and the fix
phase always completes at full strength in the main thread, closing every finding as fixed or
dismissed-with-reason in the same run; every mode ends with zero open findings (policy 2026-07-23,
after the 2026-07-22 economy run deferred its judgment tail).** The review itself now runs through
the tool (`gbg run documentation-review`), which sets its own readers and models.

**Variant pairs — PF's part.** The getter is the home of a getter/`set_…!` pair (it owns the meaning),
and a thin wrapper reads like `gradient` → *"Allocating form of [`gradient!`](@ref): allocate the result
and return it. A scalar field gives its gradient vector field ∇φ; a vector field u gives ∇u. See
`gradient!` for the componentwise definition and the spectral kernel."*, or `set_threading_cutoff!` →
*"Set [`threading_cutoff`](@ref) to `n`…"*. The partial derivative is written `\partial_{x_i}`, never
the bare-index `\partial_i` the allocating operators once wrote.

**A Literate example — PF's part.** "Full-line" includes **indented** comments inside a function body: a
2-space-indented `# …` on its own line still renders as prose, so the driver's internal step comments are
rendered too (Literate strips the indentation).

**Verify a doc edit by building it.** The command is `julia --project=docs docs/make.jl`, gated on its
exit status. After editing a Literate example, regenerate it (`Literate.markdown(src, out;
documenter=false)`) and grep the OUTPUT prose for Unicode-math glyphs and backtick-wrapped formulas until
the count is **zero**; the example page is a "check the docs" surface too.

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

**Markdown tables in a list.** Inside a list (e.g. a `DECISIONS.md` entry) use a **nested bullet list**
instead of a table, and keep literal `|` out of cells (a `|` — even inside ``…`` math, like a norm/abs
bar — is counted as a column delimiter). Bit twice: the decision-18 and decision-19 tables. Grep guard:
`grep -rnE '^[[:space:]]+\|[-:| ]+\|' docs` must return nothing.

**One notation per concept — PF's cases.** If an abstract operator and its matrix (or a continuous vs
discrete form) genuinely both appear, name each one's distinct role **once** and stop — the `W`/`𝓘`/`ι`
interpolation tangle (matrix, operator and pullback all for the same map) was the failure. A
package-wide convention that cannot move (the α/β accumulation, invariant 10) keeps its glyph and the
local use renames: `β` meant both the `mul!` accumulation scalar and the spline stencil weight, and `p`
both the point index (`xₚ`, `Σₚ`) and a polynomial (`p ∈ Πₘ`), fixed as stencil weight → `w`,
polynomial → `φ`.

**Coordinate-free notation — PF's part.** The preferred forms are the pullback `ι*`, the pushforward
`ι_*`, `W`/`Wᵀ` as maps, and the measure pairings as honest sums/integrals (`Σ_p a_p·b_p`,
`∫_Ω f·g dx`). It is **also a correctness guard**: the `𝟙`/`W_{pn}` transfer picture passed the binding
and formula-value checks yet was structurally wrong (the fiber flattening and the `𝟙_N`/`𝟙_M`
conflation above). `docs/FORMALIZATION.md` holds the component expansions but is **not** exempt from
correctness.

**One concept, one home; everywhere else links.** Explain each idea in the single section that owns it;
every other mention is a one-line hook + a `[…](@ref)` / §-link, never a re-derivation — and a diagram
lives with its topic, not in a group-by-form bin. In `ARCHITECTURE.md`, §2 is the overview/**map** (the
bundle foundation + a linked one-liner per part); §§3–12 own the details (each part of the map has a body
section). The append-only decision log is its own document, `docs/DECISIONS.md`, self-contained by
design — its overlap with the architecture's body is intentional, so do **not** dedupe it against the
body. It lived as §13 of `ARCHITECTURE.md` until 2026-09-19, where it was three quarters of that file;
it was split so `RULE.DOC.RETIRED_CLAIMS` could be switched off for the log alone, a decision log
necessarily quoting a retired claim in order to record that it was retired.

**Cross-referencing — PF's part.** Live Documenter `@ref` links are the encouraged way to point across the
docs (a mistyped `@ref` fails the build, so it cannot rot): (1) **never** link the docstring's own binding, its argument names,
`Symbol`/option tokens, struct fields, or `Base` names; (2) a **family** of built-ins (the spline schemes,
the reductions) is **one** catalogue destination, not five — name each member in plain backticks and
`@ref` the default — **unless the members are distinct types a reader must CHOOSE between**, as the four
`SpectralKernel` storage classes are, where each is linked (user-directed 2026-09-02); (3) **at-home
test** — if a sentence would sit equally well in the *target's* own docstring, cut it and link (the
function's own defining formula and its validity/absence clauses always stay — physical-meaning-first
outranks DRY). A thrown error, like a rendered docstring, must not cite a `§`-number or a repo path
(those live in `#` comments, `CLAUDE.md`, and the design docs, which cross-cite freely).

## Verification workflow

**Consent gate — PF's gated lanes (user-directed 2026-08-04).** Every lane beyond `Pkg.test()` is
expensive in wall-clock and in machine occupancy: the **exhaustive survey** (`test/exhaustive/`, 75–115 min), the **benchmarks** and the **canary lane**
(`benchmark/`), the **GPU suites** (`test/gpu/*`), the tool's review runs (`gbg run
documentation-review`) and its leak scan (`gbg leak`), and any multi-agent fan-out. The gate also protects measurement, since a long unasked run occupies the box that
`docs/PERFORMANCE.md` §1 requires to be idle.

**The pre-tool review instruments are gone (2026-10-06, owner-approved).** PF's in-tree
`/check-docs`, `/check-consistency`, `/bug-hunt` and `/audit-changes`, their verifiers, their banked
review rounds and the build's `lint_review_closure()` were deleted when PF moved to GBGCodingTools
rc.63; git history keeps them (last present at `b761d966`). Documentation reviews run through the
tool (`gbg run documentation-review`), and its leak scan is `gbg leak`. What they taught that still
binds lives in the rulebook: a static claim about code is a hypothesis until a program fails, a
self-reported closure is not closure, and a check is tested in both directions.

Before adding or changing tests, read `docs/TESTING.md` — the testing philosophy and
the per-operation coverage contract. Its §4 carries the explicit **coverage-axes list** — the
denominator over which "exhaustive" is defined, and the authoritative copy; a partial enumeration
lived here for months and had drifted to naming fourteen of the twenty-one, which is precisely the
failure the rule below describes, so read §4 rather than any summary of it. A new type parameter or
admissible input region adds its axis row and its suite lane in the same change — an axis missing
from the list is exactly how the decision-41/42 bugs stayed invisible. Before optimizing or benchmarking, read
`docs/PERFORMANCE.md` — the performance model, best practices, recorded findings, and the
benchmark coverage contract.

### Definition of done — for a new or changed operation/feature

1. **Correctness tests** — a CPU behaviour test against an *independent* oracle (analytic or
   hand-computed), over both element types and both bases where applicable, **and GPU parity**
   in `test/gpu/suite.jl` (device-vs-CPU under `allowscalar(false)`). The `docs/TESTING.md` §4
   coverage contract is the spec — for an in-place `!` operator that includes its row in
   `test/allocations.jl` (invariant 13) **and in `test/pass_audit.jl`** (decision 36, the `CountingArray`
   element-traffic ledger — the layer that catches an unfused recompute, which every other layer passes;
   `PASS_AUDIT_PRINT=1` regenerates), and a new **public value-returning** operation needs its
   `test/oracle_registry.jl` classification (decision 55). All three are declared to GBGCodingTools, as
   is `test/method_parity.jl`, so `RULE.TEST.ALLOC_ZERO`, `PASS_AUDIT`, `ORACLE_INDEPENDENT` and
   `METHOD_PARITY` bind.
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
3. **The guiding docs** — `docs/DECISIONS.md` (the decision-log entry) and `docs/ARCHITECTURE.md`
   (the relevant section), `docs/FORMALIZATION.md` (a typed entry for any nontrivial new/changed statement — re-verify
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
   `examples/gpu/rocm/HIST_ROCm.jl` where a device exists), for any change to the public surface.
   Skipping it shipped two broken demos at once
   (2026-08-04): decision 60 stopped a field in spectral representation from being a kernel, and both
   demos were still passing a `ScalarFieldSpectral` to `convolve!`, so each threw a `MethodError` in
   its own time-stepping loop; the CPU one had additionally been multiplying by a `ws.Ek` buffer that
   an earlier `exponential_convolve!` refactor left allocated, zeroed and never filled. Every layer
   the project has — the gate, the pass audit, the survey, the docs build — passed throughout, because
   an example is the one shipped surface none of them touch. The `smoke()` preset exists for exactly this and costs a few seconds of simulation.

Minimum bar for any change:

- Load: `julia --project -e 'using GBGPeriodicFields'` (catches `@eval` and wiring errors).
- Method parity after codegen edits: compare per-generic `methods(f)` counts
  against the committed baseline (`test/method_parity.jl`). Full M2+M3 surface is
  **206 public methods** (e.g. `*` 28, `mul!` 30, `dot`/`dot!` 10 each, `add!` 14, `combine!` 2, `tr` 2, `det`/`det!` 1 each).
- Ambiguities: `test/method_parity.jl` runs `detect_ambiguities` (from `Test`) over
  the whole package — the explicit `multiply!` quartet exists precisely to resolve
  these. `test/aqua.jl` runs `Aqua.test_all` for broader package checks (type piracy,
  compat bounds, stale deps, unbound type parameters, …).
- `julia --project -e 'using Pkg; Pkg.test()'` (the `test/` suite now exists; keep it green).
- **`Pkg.test()` is the GATE; `test/exhaustive/` is the SURVEY** (`docs/TESTING.md` §1). The lifecycle
  joins them: the survey discovers, a fix lands, the gate pins it forever. (The GPU suite and the
  benchmarks are opt-in for an unrelated reason — hardware, and a quiet machine.)
- The **exhaustive suite** is opt-in and separate too: `julia -t4 --project=test test/exhaustive/runtests.jl`
  holds the full Cartesian product and is run occasionally, like a documentation review, not on every change. It
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
    which combinations are real calls. **125 of the 126 public operations** are reached (re-measured
    2026-09-06, after the traversal order and its scratch joined the pool); the one with no buildable
    call is `show`, a printer whose `IO` slot the pool deliberately does not fill — its sixteen methods
    are closed by a recorded reason citing `test/display.jl`.
  - `checks.jl` — five universal properties over every invocation (preservation, structural, metadata,
    determinism, type-stability), the ones whose oracle does not depend on what the operation computes.
  - `values.jl` + `references.jl` — an **independent value oracle for 125 of 126 operations** (2026-09-06;
    the one without is `show`, a printer, closed by a recorded reason — the traversal order, its in-place
    form and its `length` gained oracles the same day, having shipped unsurveyed), each written
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
   predicates; `FieldSpectralMultipliers` moved here (it also stores each wavenumber vector **pre-oriented** as a 3-D view, so the broadcast-route operators never rebuild a `reshape` per call — decision 70; explicit six-array constructor +
   convenience constructor from a field; host-built wavenumbers copied to backend).
   The transform input contract is invariant 11; its preserving allocation-free member is the scratch
   arity `to_physical!(physical, spectral, plans, spectral_scratch)` (decision 64, IT round 3 —
   source bitwise-preserved, scratch consumed, aliasing refused; the `to_spectral!` twin is
   deliberately absent, every IT forward source being consumable by design).
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
   `Pkg.test()` green, **11032 tests** across 177 top-level testsets (measured 2026-10-15 with decision 103's `NUFFT` family-form lane; it read 10890/175 on 2026-10-13 with decision 102's regression witness; it read 10880/173 on 2026-10-12 with decision 101's `test/argument_shapes.jl`; it read 10827/171 on 2026-10-07 with decisions 97–100: the HDF5 schema-version-1 reads, the scheme and spline changes and the sampling constructors' `array_family` tests; it read 10805/169 on 2026-10-03 with decisions 89–96 and the survey's equality rows; it read 10193/148 on 2026-09-27 with decision 88 and the `map` path its survey run found — `test/caller_counts.jl`, the allocation audit's grouped-count rows and its rows for each compressed kernel class through the kernel-composed passes; it read 9834/145 on 2026-09-18 with decision 85 — `test/shared_modes.jl` and the rows decision 85 added to the allocation, pass-audit, threading, absence and peer gates; it read 9657/143 on 2026-09-05 with decision 83 — `test/fields.jl`'s projector lane is 196 cells per element type, and the operation joined the pass-audit, allocation, peer-rejection, absence-gate and dispatch-guard rows; it read 9346/142 on 2026-09-04 with decision 82 — and note that `test/display.jl` accounts for 117 of the 201 added since the previous reading, so the rest is drift the earlier figure had already accumulated, which is the standing hazard this parenthesis goes on to describe; it read 9145/139 on 2026-09-03 with decision 80;
   it read 7777/120 on 2026-08-27, decision 76 included — it read 7737/118 before that change added its rank-free-plans lane; it read 6519 on 2026-08-10, after decision 63 added `test/adapt.jl`; it read 6182/92 the day before and 6179 four days earlier), identical at `-t1`, `-t4` and `-t8`; threaded lane `JULIA_NUM_THREADS=4`; the opt-in GPU parity suite is **454** on CUDA (measured 2026-09-01, exit 0 in 4m12s — PARITY with ROCm, which also reads 454; the 422 this line carried was a 2026-08-27 reading taken before decisions 77–79 landed, and the handover that claimed 454 was right; it read 412 on 2026-08-26, green with zero failures — but only
   after the run that took the measurement found six real ones, all in decision 73's `displace!`, three per
   element type. It had read 373 on 2026-08-15 and 361 on 2026-08-10, and no GPU run on **either** backend
   had included decisions 73–75 until this one; the CUDA environment had also stopped resolving in the
   interim, so the suite was silently unrunnable rather than merely unrun. **ROCm reads 567 passed with 2 recorded skips on 2026-10-17** (`afbf1176`, exit 0 in 6m53s, no failure — CUDA's 695 less the 108 aliased-allocation cells, which skip because the ROCm runner has no device byte counter, and the 20 cost bounds, reported rather than judged on a backend with none frozen; it read 494/494 on 2026-09-05, 491 plus decision 83's three
   device cells). **CUDA reads 695/695 on 2026-10-15** (decision 103's family-form plan from the device family, eight cells, exit 0 in 5m30s; it read 687/687 on 2026-10-13, decision 102's device refusal and eight `@inferred` checks per element type, exit 0 in 5m36s; it read 669/669 on 2026-10-12 with decision 101's device calls, exit 0 in 5m28s, the cost lane within its frozen bounds; it read 669/669 on 2026-10-07) (decision 100's sampled-field device cells; the unified lane reads 538 passed with 4 recorded skips — the allocation and cost lanes, which cannot count or time unified memory — plus 44/44 of its own, on 2026-10-08). It read **667/667 on 2026-10-03** (decisions 89–96, decision 95's aliased-allocation lane — 108 cells — and the device-cost lane's 20 frozen bounds; ROCm has not run since 2026-09-05). **CUDA re-ran 2026-09-26 on `Enteropia` with decision 88 and reads 520/520**, exit 0 in 4m43s (the fourteen new cells are decision 88's operand-count rows; its first run errored in both element types' convolution testset, the defect decision 88 records); it read 506/506 earlier that day with decision 87, exit 0 in 4m19s (the two new cells are `tophat_window`'s device row in each element type); it read 504/504 on 2026-09-18 with decision 85, exit 0 in 4m21s (the ten new cells are the resolution verbs' device lane; it read 494/494 on 2026-09-17) — the device lane, asserted not unified before it started, so PARITY across ROCm, CUDA device and CUDA unified (the unified lane, `test/gpu/cuda-unified`, reads 520/520 plus 44/44 of its own on 2026-09-26 with decision 88; it read 494/494 plus 44/44 on 2026-09-17). Before that it re-ran
   2026-08-31 at 454/454, up from the stale 395 of 2026-08-23. **PARITY with CUDA is now VERIFIED** (2026-09-01, on `Enteropia`): both
   backends read 454/454, exit 0. **CUDA re-ran 2026-09-04 with decision 82 and reads 491/491, exit 0 in
   4m17s** — 454 → 466 was decision 80's device lane, which is where its claim actually bites, every
   array `point_traversal_order!` avoids allocating being a device array; 466 → 491 is decision 82's,
   and both of ITS properties need a device to check at all, since a host run can neither trip
   `allowscalar(false)` nor construct a section whose family the display could name wrongly. ROCm re-ran
   2026-09-04 on `Aiporetne` and reads **491/491**, exit 0 in 5m16s — parity again, the lag closed. The earlier discrepancy was a stale
   figure in this file, not a divergence —
   the handover's 454 was right and the 422 predated decisions 77–79. That run is the first to stage
   decisions 73–79 on AMD at all, so the three ROCm-specific first-runs are covered: the
   `PointTraversalOrder` Int32 atomics with its device `cumsum`, the exponential kernel's device `exp`
   including the complex-ŵ parity case, and decision 76's staged odd-grid lane.) Every one of these three counts has been found stale by the first measurement taken after a gap — the CUDA figure sat at 328 while ten tests were added, and the CPU figure sat at 4745/72 through the exhaustive-survey work that carried it to 6179/92, drifting by 1434 in the same sentence that observed the CUDA drift. A count nothing asserts is not a fact about the suite; it is a fact about when it was last typed, so re-measure rather than cite these). `test/display.jl`: the decision-82 display layer, verified by PROPERTIES rather than against a correct string — a derived completeness gate over every concrete package struct type (a `show` or a cited exemption, stale exemptions failing too, falsified by planting both defects), a length bound at a grid where the defaults flood, self-delimitation inside a container, the discrimination property against `_check_field_domain_compatibility` over every pair of a refused family plus a box differing in the ninth decimal, and the parameter records round-tripping through Julia's own parser. `test/fields.jl`: FFT round-trip, multipliers vs
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
   the **TurTLE `beta_n{n}_m{m}` pin** (to 1e-12, not bitwise — the test asserts `atol = 1e-12`), plus adversarial corners (non-zero origin /
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
   (the differential operators incl. `symmetric_gradient!`, the guard-free **aliased** `helmholtz_projection!`, and the kernel-composed `helmholtz_projection!`/`divergence!` arities (decision 32), transforms, `convolve!`, the lazy `exponential_convolve!` (single- and two-operand, incl. the scale×field offset) and the kernel-composed `combine!` (decision 33), and `add!`/`combine!`/`subtract!`/`mul!`/`multiply!`/`divide!`/`dot!`/
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
   (norm/sym/skew/dev de-duplicated via `_section_scalar_type`). Both parity baselines held
   byte-identical throughout.
7. **Interpolation/anterpolation transfer** — **done** (`docs/ARCHITECTURE.md` §10, decision 17):
   the Lalescu local splines, **both hierarchies** — smooth `LalescuSpline(stencil_width; smoothness)` (two-point Hermite,
   width `2n+2`, degree `2m+1`, `0≤m≤2n`, default `m = n`; `m=0` linear, `CatmullRom = LalescuSpline(4)` the usual choice) and `C⁰` `LagrangeSpline(stencil_width)`
   (degree `2n+1`). `interpolate` (gather `W`) and `anterpolate` (scatter `Wᵀ`, α/β) as portable
   **KernelAbstractions + Atomix** kernels (CPU/CUDA/AMDGPU; atomic scatter). The smooth weights are
   **pinned to TurTLE's `beta_n{n}_m{m}` at `atol = 1e-12`** (`n`↔`interp_neighbours`, `m`↔`smoothness`);
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

**ENTEROPIA — the queue is CLOSED (run 2026-08-31 on this host; the handover was `225d3581`).**
Check `hostname`; on `Aiporetne` this is not actionable. Both open A/Bs ran, and a third defect
surfaced while running them. The record is `docs/PERFORMANCE.md` findings (al) — the A/B — and (ak),
the stale traversal order. Nothing here is actionable again until the next sweep.

- **Decision 76 regresses on CUDA too, so it is cross-vendor — but ONLY at ``64^3``.** Vector
  transforms run ``1.11``–``1.35\times`` slower there against eight scalar controls flat at
  ``0.99``–``1.01\times``, the same signature ROCm gave at ``1.15``–``1.61\times``. Extending the A/B
  to ``128^3`` and ``256^3`` puts the vector rows at ``0.87``–``1.03\times`` — flat or FASTER — and
  ROCm's intermediate grids wash out likewise. Three plan executions where there was one is a fixed
  per-call cost: decisive at ``\approx 20`` us, invisible at milliseconds. **So the roadmap item is a
  small-grid inefficiency, not a regression at the production band**, and should be re-prioritised
  accordingly rather than treated as the cross-vendor regression the handover framed.
- **Decision 78's walk does NOT regress on CUDA; it wins in every cell.** All 24 gather and scatter
  cells sit at or below ``1.002\times``, `Lalescu(3,3)` reaching ``0.46\times``. **The falsifiable
  prediction FAILED**: ``256^3`` `Float32` (67 MB) was predicted to regress harder on this card's
  ``\approx 48`` MB L2 than on the 7900 XTX's 96 MB Infinity Cache, and it WINS at ``0.90\times``.
  The weaker monotone claim fails too, `CatmullRom`'s win growing with the working set while
  `Lalescu(3,3)`'s shrinks. Finding (aj)'s cache-boundary account is corrected in place: it describes
  the ROCm measurements and is not a property of the walk. **The AMD regression is vendor-specific,
  and its mechanism is now measured** — register pressure halving occupancy on gfx1100, finding (aq).
- **The old arm this queue named was the WRONG COMMIT, and the queue's own caveat caught it.**
  `93d9d8da` predates `d5f6814a`, which repaired the CUDA `gcsample` probe (§4(w)), so every row
  measured there ran on the per-sample collector: three samples with `gcsample = true` against 668
  GC-free in the new arm. That compares two measurement disciplines rather than two versions of a
  kernel, and it would have reported the new code faster for the wrong reason. The arm was rebuilt at
  `ef70e913` — the last commit before decision 76 and after the probe repair — with `GPUCompiler`
  pinned to 2.4.1 in both. **Compare per-row `evals`, `samples` and `gcsample` before believing any
  arm**; that is the check that fired.
- **The CUDA test count is RESOLVED (2026-09-01, user-directed): 454/454, exit 0 in 4m12s, PARITY
  with ROCm.** The handover's 454 was right and this file's 422 was a stale 2026-08-27 reading taken
  before decisions 77–79 landed; the two backends never diverged. Both figures are corrected above.
- **CLOSED 2026-10-04 — the compile-only falsification test of finding (aq).** On `sm_120a` the walk
  takes `CatmullRom` from 90 registers to 80, so its register-limited occupancy rises from 21 to 25
  warps of 48 (`Lalescu(3,3)`: 112 to 128 registers, 18 to 16 warps), with no spill at either commit.
  The walk crosses no register tier on NVIDIA for the scheme that regresses on gfx1100, so (aq)'s
  register-pressure account survives. `benchmark/kernel_resources.jl` now has a working CUDA arm.
- **Still open here:** the canary needs a device vector-transform mechanism, decision 76 being
  confirmed on both vendors. Its `fft` mechanism is `to_physical!` SCALAR at ``128^3``, exactly the
  configuration that decision leaves alone, so the next regression on that axis is equally invisible.

**AIPORETNE — the 2026-10-16 queue RAN 2026-10-17 on this host; steps 1–3, 5 and 6 are CLOSED, step 4 is
OPEN and step 7 was not asked.** Step 1: every environment instantiated and loaded, GBGCodingTools at rc.79
with tree `09d1e60e` in all three of its environments. Step 2: decisions 84–103 now execute on AMD with no
failure, 567 passed and 2 recorded skips, the arithmetic in the count line above. Step 3: `HIST_ROCm.jl --smoke`
green, Parseval exact. Step 5: the canary is GREEN, all twelve mechanisms within 3% of the 2026-09-04
baseline. **Step 4 is NOT done: the ROCm cost bounds cannot be frozen**, because passes on this card do not
agree to 0.02 — the spread is bimodal between processes (`Float32` scalar `convolve!` with a radial kernel
reads 1.43–1.46 in some, 2.34–2.67 in others) and every `Float32` pass trips the busy warning on an idle card;
the figures are in `docs/PERFORMANCE.md` finding (aw). Two gaps for the owner, neither fixed: the ROCm runner
defines no `device_bytes_allocated`, so decision 95's aliased-allocation lane has never asserted anything on
AMD; and `weighted_inner` costs 3.2–3.5 times a copy in `Float64` here against CUDA's 1.33.
**Step 7 (the survey, owner-approved 2026-10-17) was blocked by a package defect it found, now FIXED (owner-directed, same day).** The mapped
reductions `extrema`, `minimum`, `maximum`, `mean` and `integral` accept a FIELD as the fiber map, the
class `map!`/`map` were fixed for on 2026-09-02: on the CPU `extrema(s, u)` silently returns the scalar
field interpolated at the vector field's values read as positions, and on ROCm compiling that kernel
segfaults LLVM (`extrema(s, u)` on two device fields, exit 139), killing every survey process at the same
call. A second, HARNESS defect, also fixed that day on the owner's word:
from a GPU environment `device_backends()` imported the vendor inside a running function and then
could not see the new binding under Julia 1.12's world age, so the survey reported "BACKENDS: cpu"
and never crossed the device. Routing the lookups through `invokelatest` (`e3c539c2`) was NOT enough —
every AMDGPU method was too new for the running sweep, so every device pool still failed to build — and
the vendor is now imported at top level when `invocations.jl` is included, before any lane begins. The original queue follows. The ROCm suite last ran 2026-09-05 at 494/494, so decisions 84–103 have never
executed on AMD; CUDA reads 695/695 at `af0019b3`. In this order, each step alone on the machine:

1. **Pull and load.** `git pull`; master is at `af0019b3` or later. The three AMD environments carry
   gitignored manifests — `test/gpu/rocm`, `benchmark/gpu/rocm`, `examples/gpu/rocm` — so in each run
   `Pkg.instantiate()` and then LOAD (`using GBGPeriodicFields, AMDGPU`); resolve and instantiate
   passing is not enough (2026-08-31, four stale environments found only at load). In `test/gpu/rocm`
   also `Pkg.update("GBGCodingTools")` to rc.79 and verify the manifest's `git-tree-sha1` equals the
   tag's tree (`gh api repos/GrigorySarnitsky/GBGCodingTools.jl/git/commits/<sha> --jq .tree.sha`,
   09d1e60e…). Warm the card once with a trivial kernel after a reboot: a cold comgr JIT looks like a
   hang, and a cold run is never killed.
2. **The ROCm suite:** `julia --project=test/gpu/rocm test/gpu/rocm/runtests.jl`. The suite is
   backend-agnostic, so expect **695/695**; a different number is a finding, not a rounding difference,
   unless the log says why: the device-cost lane reports rather than judges on a backend with no
   frozen bounds (step 4), and the aliased-allocation lane (108 cells) is SKIPPED, with an `@info`,
   where the backend cannot count device bytes — on CUDA it runs. First-runs on AMD, in the order they are likeliest to differ from CUDA: decision 88's
   grouped n-ary fold (a generated per-group body that failed to compile on CUDA at first); decision
   95's aliased-allocation lane, 108 cells asserting zero device bytes, where a device VIEW allocated on
   CUDA; decision 102's `@inferred` reductions on device (`inner`, `l2norm`, `lpnorm`, `std`, `var`,
   `==`, `isequal` — the assertions are PF's, but AMDGPU's `dot` and `==` are its own) and its
   `translation_kernel!` refusal; decision 103's `NUFFT(ROCArray, grid, Val(R); layout)` and the
   `adapt` plan rebuild handing `fft_flags` to a ROCm target (ignored, as cuFFT ignores it); decision
   93's `read_field!` through a host buffer and the plans' family form; decisions 85 (resolution
   verbs), 87 (`tophat_window`), 90 (`mean_free_projection!`, `materialize_kernel!`), 91 (equality
   and `hash` on device), 94 (multipliers' family form) and 97–101 (scheme positional, sampling
   constructors with the family). A failure is REPORTED, never fixed silently; a device-specific
   defect gets a regression witness and a decision entry, as decision 102's did.
3. **The example:** `julia --project=examples/gpu/rocm examples/gpu/rocm/HIST_ROCm.jl --smoke`.
4. **Freeze the ROCm device-cost bounds.** The lane (`device_cost_lane` in `test/gpu/suite.jl`, ten
   cases at ``256^3``) is reported, not judged, on a backend with no entry in `DEVICE_COST_BOUNDS`.
   Two idle-machine passes agreeing to 0.02, each bound the higher of the two plus 10%, entered under
   the suite's own backend label for the RX 7900 XTX, both element types; the reason beside the
   numbers in the commit, and the ROCm reading added to `docs/PERFORMANCE.md` finding (av). The
   `weighted_inner` excess (1.33–1.88 on CUDA) is known and left (owner-ruled 2026-10-03); the AMD
   figure is reported, not fixed.
5. **The ROCm canary:** `julia --project=benchmark/gpu/rocm benchmark/regress.jl gpu`, baseline
   frozen 2026-09-04. A red here is a hypothesis: check first whether the baseline predates a harness
   fix (the 2026-08-07 phantom), and whether only the unsynchronised mechanisms moved.
6. **Record:** the ROCm count line in this file (now "ROCm reads 494/494 as of 2026-09-05") and the
   bounds; commit and push — the push hook runs the docs build and REFUSES a tree with uncommitted
   tracked files, so commit everything first.
7. **Optional, with the owner's word:** the survey has never run on AMD. `julia -t4
   --project=test/gpu/rocm test/exhaustive/runtests.jl` with `SURVEY_CONFIGURATIONS` (a regex on
   configuration names) in processes of a dozen configurations or fewer — about 7 min and 3.5 GB of
   host memory per configuration, never released, cause unidentified — through `script -qfec` so the
   log is line-buffered. Note that the survey omits the plans and the `NUFFT` for a permuted layout on
   ANY device (`plannable` in `invocations.jl`), a cuFFT limit rocFFT does not share; on ROCm that is
   a harness conservatism to record, not a finding.

**AIPORETNE — ALL THREE ITEMS CLOSED 2026-09-04 on this host** (all three were filed from Enteropia;
check `hostname`). The record of (1) and (2) is `docs/PERFORMANCE.md` finding (ap), of (3) finding
(aq); the entries are kept below for what they taught. Nothing here is actionable until the next
handover.

**(1) CLOSED 2026-09-04 — the ROCm suite reads 491/491, exit 0 in 5m16s, PARITY with CUDA.** It had
read 454 since 2026-08-31 against CUDA's 491. The 37 cells between them are
decision 80's device lane (454 → 466) and decision 82's (466 → 491), and in both cases the device
lane is where the claim actually bites — every array `point_traversal_order!` avoids allocating is a
device array, and neither of decision 82's display properties can be checked on a host at all, since
a host run can neither trip `allowscalar(false)` nor construct a section whose array family the
display could name wrongly. Run `julia --project=test/gpu/rocm test/gpu/rocm/runtests.jl` and expect
**491/491**; a different number is a finding, not a rounding difference.

Decision 82 also unified three spellings of the array family into one recursing predicate, and
that predicate is `_same_backend` — invariant 14's. It is exercised on every device row in the
suite, so this run is the ROCm evidence for it. Note the suite is the ONLY thing outstanding for
that decision: `Pkg.test()` (9346/142), the docs build and the CUDA suite are all green at
`b1c0b973`.

**(2) CLOSED 2026-09-04 by a FULL re-sweep, not the splice this entry prescribes** — `src/` had moved
by nine files since the archives' commit, which is the case the splice tool refuses; finding (ap)
has the numbers (five lanes flat to four decimals, the `ordered` rows repaired to ``0.22``–``0.87\times``),
and the regeneration found that `d828f406` had renamed a row in `RESULTS.md` by hand, now fixed by a
row-alias map in `report.jl`. The original entry follows. Five of this host's archives reported a
benchmark defect rather than a measurement, and only this host could repair them. The `ordered` transfer rows timed a STALE traversal order — the class shared
one `PointSet` between its `displace!`/`wrap!` rows, which mutate positions in place, and the
`ordered` rows, whose order was built from those positions (`PERFORMANCE.md` finding (ak)). The
harness is fixed and Enteropia's five archives are repaired; `cpu-12700k-t{1,2,4,8}` and
`gpu-rx7900xtx` are not, so `RESULTS.md` currently reports decision 78's traversal order as a **loss** in
those five columns where it is a ``3``–``4\times`` win. Steps:

1. `git pull`, then run the gate on both backends: `julia --project=benchmark benchmark/gate.jl` and
   the `rocm` arm. Every transfer point set must report unmutated; that is the invariant that broke.
2. Re-measure the **transfer class only** on each of the five lanes —
   `CHAR_SKIP=fft,algebra,operators,convolution,reductions,storage` — into a SEPARATE file per lane,
   never over the archive. The `-t8` lane needs no split here; §4(q) is `Enteropia`-specific.
3. Splice each with `julia --project=benchmark benchmark/replace_class.jl <archive> <fresh> transfer`.
   It verifies every untouched row bit-identical, refuses a row-set mismatch, and restores from its
   backup on failure. **A splice is only honest while the package is unchanged between the two
   measurements** — confirm `git diff <the archive's commit tag> HEAD -- src/` is empty first, which
   is what licensed it on Enteropia. If `src/` moved, re-sweep the lane instead.
4. Regenerate `RESULTS.md` over all ten archives, and delete the stale-`ordered` caveat paragraph
   from `report.jl`'s header prose once no column carries one.

**(3) CLOSED 2026-09-04 — it is register pressure: on gfx1100 the walk compiles `CatmullRom` to 192
VGPRs with 292 bytes of scratch at 8 waves per EU, where `mod` gave 91 VGPRs, no scratch and 16; the
flat `Lalescu(3,3)` is unchanged on every line (104 → 107 VGPRs, occupancy 12 → 12). Read from the
compiled code object at both commits, finding (aq), with the CUDA falsification test stated there.
The original question follows.** Why is decision 78's device gather regression AMD-only? Enteropia measured 24 of 24
gather/scatter cells at or below ``1.002\times`` on the 5070 Ti, so the cache-boundary explanation
finding (aj) offered is dead — it predicted a regression on that card at ``256^3`` `Float32` and got
a ``0.90\times`` win, and the two schemes move in opposite directions across the same boundary. The
``1.74\times`` on the 7900 XTX is real and was reproduced three times, and it now has **no
mechanism**. The candidates need the card: how the AMDGPU backend schedules the walk's serialised
address chain, and what occupancy that chain costs. Until one is established, the corner stays
documented rather than fixed, as decision 78 already records.

**AIPORETNE — the queue is CLOSED (run 2026-08-31 on this host; the handover was `b452fb17`).**
All eight items ran. Nothing here is actionable again until the next sweep; the durable lessons are
kept below and the one new open question is in the roadmap (the decision-76 device cost).

- **Environments — FOUR were stale, and the queue named three.** `test/gpu/rocm`,
  `benchmark/gpu/rocm`, `examples/gpu/rocm` and the ROOT project all needed `instantiate`
  (`PrecompileTools` missing; `failed to find source of parent package: "LLVM"`), each surfacing only
  at LOAD. `benchmark` was NOT stale: it failed the queue's check only because that check asked for
  `AMDGPU`, which the CPU lane deliberately does not declare. A failing load is not by itself a stale
  environment — read the error before counting it.
- **ROCm suite 395 → 454/454, exit 0.** Decisions 73–79 are now staged on AMD,
  including the three first-runs: the `PointTraversalOrder` Int32 atomics and device `cumsum`, the
  exponential kernel's device `exp` with the complex-ŵ parity case, and decision 76's staged
  odd-grid lane. `examples/gpu/rocm/HIST_ROCm.jl --smoke` is green (Parseval exact,
  ``\lVert\nabla\cdot u\rVert_{\mathrm{rel}} = 10^{-7}``).
- **The five lanes are swept and merged**: CPU t1/t2/t4/t8 (60/51/44/41 min) and the ROCm lane plus
  its ``512^3`` `Float32` part, merged with `merge_parts.jl` reporting `forward: true | reverse:
  true`. A plain `-t8` invocation completed without incident, re-confirming that the §4(q) FFTW
  segfault is `Enteropia`-specific. Canaries green on all three lanes and refrozen; `RESULTS.md`
  regenerated over all ten archives with both hosts now stamped 2026-08-31.
- **Every mover is explained — finding (aj).** Medians 0.994–1.002 across all five lanes. The two
  candidate regressions were each settled by an A/B against the old commit rather than by argument,
  and they came out opposite ways: the CPU scalar `fft` shift is NOT the package (old and new code
  measure identically today, so it is the §4(p) measurement-environment class), while the ROCm
  vector `fft` slowdown IS the package (decision 76, 1.39–1.61× at ``64^3``).
- **The triage notes are corrected.** The `exponential_convolve!` known-flag entry was DELETED, its
  condition fully resolved on both hosts — a note whose premise has expired is worse than no note.
  The `weighted_inner` entry now says what is actually left: only the ``64^3`` rows, carrying ~1.1 ms
  against a 1 ms floor, overhead-bound rather than the finding-(ac) pathology. The radial shell
  binning remains the only section-A unexplained, which is the intended pressure.

*Method note, kept because getting it wrong destroys data:* `characterize.jl` **overwrites** the
archive it is given, so measure into a SEPARATE file and merge. Verify the merge in **both
directions** — re-merge the pre-merge backup into the merged archive and confirm it adds nothing and
changes nothing, which catches a dropped row as well as an altered one; all five lanes reported
`added: 0, pre-existing rows changed: 0`. Regenerate `RESULTS.md` over **all ten** archives or the
other host's columns vanish. Note also that the `storage` class is **device-only by construction**
(`benchmark/storage.jl` returns immediately for `Array`, `adapt` to one's own family being the
identity), so its eight `—` CPU columns are the honest reading and not a gap to fill.

**Both vendor risks were checked and neither materialized.** *(a)* Decision 72's tuple reduction is
`reduce` with a **tuple accumulator** over an instantiated `Broadcasted` — the same family as decision
62's trap, but a *different* AMDGPU code path from `sum`/`mapreduce`, so no CUDA run could speak for
it. It neither threw nor fell back, and turns in its **largest speedups of any lane** (1.86–2.70×).
Had it thrown, the fallback was a KernelAbstractions kernel carrying one accumulator per weight, in the
decision-34 binning shape; keep that in mind if a future AMDGPU release regresses it. *(b)* Decision
71's `reality_residual` walks whole planes with `reverse` and `circshift`, chosen so it never indexes a
device array elementwise; it does not fall back to scalar indexing under `allowscalar(false)` on ROCm
either. **Decisions 60, 61 and 62 had already
executed on ROCm** (RX 7900 XTX, gfx1100), where before they had shipped verified on CUDA alone. The
pointed one was decision 62: `weighted_inner` admits a `ProductKernel`, whose `_kernel_data` nests **two
lazy `Broadcasted`s**, and the `Base.Broadcast.instantiate` in that function exists precisely because
**AMDGPU's `mapreducedim!` throws on a `Broadcasted` with `Nothing` axes where the CPU tolerates it** —
so the nesting was the predicted place for it to resurface, and no CUDA run could tell us. **It did not
resurface.** The suite was green at 352 tests that day, matching CUDA's count at the time, and the case
is a real one rather than an absent one: `test/gpu/suite.jl` composes `convolve(cutoff, window)` —
radial ∘ separable, which *is* a `ProductKernel` — and checks it against both the CPU value and the
materialized kernel, with the complex-weight refusal exercised on-device beside it. That same day was
also the first time **anything** had executed `examples/gpu/rocm/HIST_ROCm.jl`.

**The benchmark half is CLOSED too (2026-08-07).** The canary is green on all three lanes after a
refreeze whose reason is in `bd1e4f30`: this host's ROCm baseline predated `canary_sync` by a week and
two of its twelve mechanisms were timing launches rather than work (`add!` at 17.5 µs and `to_physical!`
at 25.8 µs for a 128³ pass, both under the physical floor), Enteropia's having been refrozen by the sync
commit itself. The **12700K 512³ band is measured** — 512³ became a CPU default in `b59a2793`, so the
plain invocation covers it and the old advice to override `CHAR_SIZES` is obsolete. `RESULTS.md` was
regenerated with **all twelve columns of the time intact**, verified by the untouched columns
reproducing bit-for-bit at +0.0%; it now carries **ten**, the two retired cards having been dropped
later the same day by `db7e6dd8` (both were measured in the broken `gcsample` regime and neither card
exists to be re-swept, so their columns could never be corrected or compared).

**RESOLVED — the GPU measurement defect and its re-sweep: `PERFORMANCE.md` §4(s).** Device lanes ran
`gcsample = true`, so a full `GC.gc()` preceded **every sample** and dominated operations lasting tens
of microseconds — **18.4–29.2× at 64³, 5.8–19.8× at 128³, 1.9–4.25× at 256³**. The tell was always in
the table: `convolve! scalar` and `convolve! vector` at 128³ read 1.094 and 1.177 ms, 3× the bytes
showing as 1.08×. It was **not** a uniform factor, so one recorded conclusion reversed: decision 51's
radial kernel is **9–12% faster** than the stored class on the 7900 XTX, not slower, and `bd1e4f30`'s
"opposite sign on the two vendors" is **retracted**. **CPU columns were never affected.**

**Fixed and re-swept.** `_apply_gcsample_policy!` in `characterize.jl` (mirrored in `regress.jl`)
decides the discipline **per row from a measured device-pool probe**: flat rows run GC-free; allocating
rows get `samples` capped from their measured per-call growth (4 GiB budget, `evals` pinned to 1, so
they are timed on the operation too); only a row whose single call is too large to repeat keeps the
per-sample GC. **Two traps, both hit and both fixed:** host bytes are not the signal (a KA launch
allocates host bytes per call, so a first attempt classified everything as allocating), and the probe
runs GC-free so a fixed call count can itself wedge the card — `transfer` at 256³ hung a sweep for 2.5
hours, and `catch => true` never fired because **a wedge is a hang, not an exception**. The probe is now
bounded by memory with an early exit. A capped row must never be passed to `tune!`.

The 7900 XTX was re-swept 2026-08-07: median **−81.6%** over 467 rows, `convolve!` scalar-to-vector
ratio back to 3.14, canary green with **zero** rows needing the GC. The two retired columns were
dropped (broken regime, no card to re-measure).

**The 5070 Ti was re-swept 2026-08-09, so BOTH GPU columns are now in the fixed regime and comparable
again.** Median **−46.4%** over 426 rows (`convolution` −69.1%, `operators` −52.7%, `reductions`
−48.3%, `algebra` −36.0%, `fft` −17.1%, `transfer` −16.1%) — smaller than AMD's −81.6% because
NVIDIA's collect-and-synchronize is cheaper, and the drop is largest exactly where per-row work is
smallest, which is the signature of removing a fixed per-sample cost. Acceptance met: `convolve!`
scalar-to-vector recovered to 3.08 (`Float64` ``256^3``) and 2.24 (`Float32` ``128^3``); at ``64^3``
it stays near 1.3 because 18 µs is launch-bound, not collector-bound, and the absolutes there fell
64.2 → 18.0 µs. Rows are monotone in grid size again, and `add! scalar` at ``256^3`` now reads 782
GB/s — 87% of the card's peak, i.e. physically interpretable for the first time. Canary refrozen and
green. `RESULTS.md` regenerated over all ten archives with the other nine columns bit-for-bit
identical.

**Two recorded cross-card claims were corrected by it** (`PERFORMANCE.md` §4(v), §6): the "≈1.8×
median" is **1.09×** (`Float64`) / 1.28× (`Float32`) at ``256^3`` — near parity, the NVIDIA edge being
concentrated at small grids (2.21×/3.06× at ``64^3``) where launch latency dominates; and the
reductions `Float32` gap, recorded at ≈3.5×, is **1.11×**. The ``\approx 48\times`` `Float64` radial
gap is confirmed to three figures (48.07×), which makes the story cleaner: that whole gap **is** the
emulated-`Float64`-atomic penalty, since in `Float32` the cards are equal. The RX 7900 XTX **won the
entire transfer class** at ``256^3`` by 1.5–1.9× **as of that 2026-08-09 reading; on the current table
it wins five of the eight rows** at ``1.25``–``1.79\times`` and loses the `CatmullRom` gather plus both
`NUFFT` directions, decision 78's AMD-only gather regression having landed in between. "The fleet's
fastest card" holds only at small grids and in `Float64` atomics.

**The fix itself had never run on CUDA — `PERFORMANCE.md` §4(w), found 2026-08-09 three classes into
the Enteropia re-sweep.** The probe asked the pool for its size with `CUDA.total_memory() -
CUDA.available_memory()`, and **`CUDA.available_memory` is not a binding** in the CUDA.jl this tree
resolves, so it threw on every row and the catch-all ("unclassifiable ⇒ safe default") put **every CUDA
row back on `gcsample = true`**. It then printed `per-sample GC kept for N allocating row(s)`, which
reads as a measurement — the lists were each class's *complete* row list, `operators` naming all nine
including `laplacian!` and `curl!`, which `test/allocations.jl` pins at zero. The AMD path was always
correct, so **§4(s)'s −81.6% and everything drawn from it stand**; what was wrong is that no CUDA
archive had ever been measured under the per-row policy. Fixed by `CUDA.used_memory()` (pool-scoped,
verified: 16 MiB for a 16 MiB array, 0 after reclaim, blind to other processes — where `total - free`
read 32 MiB for that array), and, the half that matters more, **a failed probe is now reported apart
from a measured one** with a `!!` banner naming the count and the exception. Post-repair at ``64^3``
`Float64`: `operators` 9 rows / 0 failures / 0 kept, `algebra` 10 / 0 / 0.

**§4(p) is CLOSED as unattributed-but-bounded (2026-08-09): the CPU `fft` shift was a ONE-OFF.** It had
been narrowed to `Enteropia` (the `Aiporetne` control found no movement at the larger grids, positively
excluding a platform-wide kernel or microcode cause, both hosts running `7.0.0-28-generic`), but neither
host's movement was explained. Re-sweeping `Enteropia`'s CPU lanes on 2026-08-09, over an interval with
**no source changes**, the shift **did not recur**: the `fft` class is flat at −1.4%/−1.2%/−1.1% for
`-t1/-t2/-t4`, and at 256³ — where the event was +20–50% — the medians are −3.7%, −6.5%, −1.2%. Every
other class is flat too, 600 rows per lane, overall +0.0%/−0.2%/−0.2%. So the harness reproduces itself
across four days and the 2026-08-05 reading was a transient of that sweep, not a lasting change. The
cause stays unidentified and now always will: the state that would name it was never recorded and the
episode is over. The durable outcome is the **stamping** — those three lanes are the first archives
carrying kernel/microcode/governor/SMT/THP, so a recurrence is a diff rather than a reconstruction.

**§4(q) is now REPRODUCIBLE on this host, and the `-t8` lane completes only when SPLIT.** A single
`-t8` process failed three times consecutively with `signal 11` in `spawn_apply` (`libfftw3`) via
FFTW.jl's `spawnloop`, taking `Enteropia` to four failures in five attempts; the crash point moves
between runs, so it is a race, always inside `reductions`, whose `radial_correlation` transforms. **The
2026-08-07 "105 trials, no crash" ran on `Aiporetne`** and is evidence about that host only — the fault
has never appeared there. **The workaround: one process per grid** (`CHAR_SIZES=64`, then 128, 256,
512), merged into one archive — 64³/256³/512³ passed first time, 128³ on its second, 150 disjoint rows
each. The t8 column was rebuilt that way 2026-08-10 and is flat against the one it replaces (+0.0%
median over 600 rows; the largest movers are the `measure` twins, whose `MEASURE` plan search
legitimately re-decides). **It is a workaround, not a fix** — a plain `-t8` invocation still dies, and a
*fresh* process doing only 128³ also crashed 2.5 min in, so splitting helps by shortening exposure and
cheapening retries, not by removing the hazard. `set_fft_threads!(1)` would remove the callback but
would corrupt the very column the lane exists to measure. **The package itself is fine at eight
threads:** `Pkg.test()` under `JULIA_NUM_THREADS=8` passes in full (6182/92, zero failures), so the
`-t1`/`-t4` CI matrix is not hiding a broken configuration. **§4(r) is RESOLVED (2026-08-07):** the CPU kernel-op cluster is decision 51
reaching those operations through finding (k). A `RadialKernel`'s symbol is a lazy `Broadcasted` over the
3D mode grid, so against a **scalar** field it is evaluated once per mode but against a **vector** it is
extruded over the fiber and evaluated **per component** — bisected at `48b6254a` vs HEAD with flat
controls, and confirmed by the penalty scaling with tensor order (R=0 1.02, R=1 1.99, R=2 1.52 at 64³)
and vanishing at 128³ where the saved kernel-array traffic pays for it. That also reconciles the
apparent contradiction: the `∘ radial` vs `∘ stored` rows show radial faster because they sit at 128³/`-t8`,
in the bandwidth-bound regime. **The hoist fix was prototyped, MEASURED and DECLINED** — it buys nothing where it
matters: at 256³ it is 1.02× (R=1) and 1.07× (R=2) *slower* than the current broadcast, because the pass
is bandwidth-bound there and the recompute is already hidden while the row buffer adds a store and a
load. The premise was wrong too: a traffic count said radial should beat stored by ~14% at R=1 and was
forfeiting it, but at 256³ radial already measures 41.9 ms against stored's 45.0 — 6.8% ahead. The
penalty is confined to 64³-and-serial, which is not the CPU tuning target (decision 37). **No change is
warranted**, and the pass audit's separate ŵ-extrusion holder should be re-priced against this before
anyone acts on it. The §4(r) GPU half is **withdrawn**, both its archives having been in the broken regime. Traps and the full task list remain in
the synced memory `aiporetne-verify-rocm-decisions-60-62`.
**Do not run `characterize.sh` there** — it would hand `report.jl` only the lanes it just produced and
silently drop Enteropia's two columns and both retired cards from `RESULTS.md`.

**The per-method coverage ledger is BUILT and reads ZERO uncovered (2026-08-28).** The resumption
point recorded here since 2026-08-02 is closed; `test/exhaustive/method_ledger.jl` implements it and
`test/exhaustive/README.md` says how to run, read and extend it. **598 cells over 119 operations as of 2026-09-06: 579 covered by an assertion, 19 closed by a
recorded reason, 0 UNCOVERED** — the morning run had read 19 uncovered (the traversal order's
methods, its `length` and `adapt_structure`, the fifteen `show` methods, and decision 83's
one-argument form), all closed the same day: value rows and a block-key oracle for the traversal
order, rows for the in-place projector, and a `:not_a_value` reason per `show` method citing
`test/display.jl`. The 2026-08-29 figure was 575 cells over 114 operations: 572 covered by
an assertion, 3 closed by a recorded reason, 0 uncovered**, with the value lane at 516 comparisons
against 169 rows before. The gap it existed to close was per-symbol bookkeeping — one checked method
marked a whole generic done, so `mul!` reported covered on one row out of dozens.

**Coverage is DERIVED, never declared:** the value lane runs under `--code-coverage` twice, once whole
and once with the assertion tuples empty but every fixture still built, and a method counts as covered
only if an assertion added hits to its span. No row is annotated with the method it exercises, because
a hand-maintained mapping is the defect being replaced. Methods sharing a definition site (the codegen
families) are closed together and the grouping is REPORTED rather than merged silently.

**A reason is NOT a dismissal.** The four cells closed that way are two error fallbacks that exist to
throw (`extrema` and `var` on a non-scalar section) and two dispatch-ambiguity resolvers a valid call
cannot reach — none of them returns a value an oracle could compare. Each one's REFUSAL is asserted,
and each reason cites the assertion by file and line (`test/reductions.jl:658,664-665,668` and the
point-value regression). A reason that cannot name its assertion is not admissible: write the
assertion, or leave the cell uncovered.

**A reason names exactly ONE method, by signature**. Keying by definition SITE was tried first and was wrong twice over: one entry silently closed the
four codegen methods sharing an `@eval` line — the "covered by a sibling builder" escape, caught by
probe 4 — and any edit above the method invalidated the key, which the stale check then reported as a
missing method when only the line had moved. A signature is stable under edits and names one method,
so a reason can neither drift nor over-close.

**Five falsification probes live in `selfcheck_method_ledger()`, and they take their target from a
perturbed COPY of the lane** so probes 4 and 5 keep working now that the real count is zero: a check
that goes dark when the thing it guards succeeds is the failure this lane exists to prevent. Three
defects in the ledger itself were found this way or by chasing one uncredited cell, and none was
visible by reading it — the boolean fixture subtraction stripping credit across shared spans, and a
line index re-enumerated from `names(mod; all = true)`, which does not report an operator a module
imports from `Base` and so suppressed 107 cells while their hits sat in the coverage file.

**A DEFECT the sweeps surfaced, and it was the point layer.** Writing a row to reach one cell showed
`multiply!`/`divide!` on point-values accepting a destination of the wrong tensor order: a scalar ×
scalar product written into a vector destination was broadcast over the fiber, and a VECTOR result
written into a tensor destination was expanded along the trailing axis and returned as a wrong-shaped
answer rather than an error. The field twin has always refused both, because it calls
`_check_field_compatibility`, which is the domain check AND `_same_tensor_order`, where the point twin
checked only `_check_npoints_match` — the point count, which cannot speak for the fiber. Invariant 14
binds the destination of an in-place call, and `Points.jl` documents those four signatures as
"mirroring FieldAlgebra"; they did not. Fixed 2026-08-29, witness promoted to
`test/regressions/pointvalues-scalar-action-wrong-order-destination.jl`.

**Open items from the 2026-08-04 survey runs.** **(1) `to_spectral!`'s ~8–12 KB per step is CLOSED
(2026-08-07): it was the harness, not a leak** — `PERFORMANCE.md` §4(t). FFTW.jl reaches its worker
threads through a Julia callback, so a plan built with more than one thread allocates task state per
call: size-independent (the same 7008 B for a 12 KB field and a 2.6 MB one), nondeterministic (7008,
10464, 23173 and 48557 B/step for one configuration across runs), and fixed when the **plan is built**
rather than when it is called — a plan built under `set_fft_threads!(1)` measures exactly 0 B/step even
when called from a 4-thread session. The fold dependence (7008 default, 10464 for `(3,1,2)`) is the
plan's stage count, not a permuted-layout defect. The gate was already right, bounding this class with
`4096 × nthreads()`; the survey's lane used a field-proportional bound and so overran on small
fixtures. The lane now builds a dedicated single-threaded plan for the measurement and reports 0
B/step deterministically. Raising the bound would have been the wrong fix — it would set a threshold
against a quantity that varies 7× run to run. **(2) The value lane has now executed and is
CLOSED (2026-08-15)** — it had thrown from 2026-08-03 until a fix on 2026-08-04, leaving its
independent oracles unverified against the present code. The survey was run in full after decision 66, again on
2026-08-28, and again on **2026-08-29** after the per-method ledger landed (`-t4`, from `test` so the
HDF5 pair is reachable, ~85 minutes). **First DEVICE run of the survey, 2026-10-13 on `Enteropia` (CUDA), staged: the survey had not loaded in a GPU environment since 2026-08-27 (`using Adapt`), and its spectral pool had never reached the device (only `rand` went through `device`), so no earlier "device" run had crossed that axis. Fixed, with four device-only harness false positives (library plan workspace, the odd grid's documented scratch, a `Float32`-blind determinism tolerance, an untagged backend). Run as processes of a dozen configurations (`SURVEY_CONFIGURATIONS`), the product not fitting one process (about 3.5 GB of host memory per configuration, cause unidentified). Over the standard-layout configurations, both element types and all four grids: 0 correctness findings on either backend. Two PACKAGE findings, both fixed by decision 102: `translation_kernel!` accepted a real-valued `SeparableKernel` and failed by conversion, and `inner`, `l2norm`, `lpnorm`, `std`, `var`, `==` and `isequal` inferred `Any` on device fields through CUDA.jl's `dot` and GPUArrays' `==`. A third observation, no `FieldTransformPlans` on CUDA for a permuted layout, is the documented cuFFT limit (`docs/src/gpu.md`), not a finding; the survey's device fixtures now omit the plans for such a layout instead of losing the configuration's whole device leg.** **Re-run 2026-10-15 on `Enteropia` (`-t4`) after decision 103, the keyword table carrying `with_threading`'s `mode = :automatic`: every figure of the 2026-10-12 second run unchanged — 3,641,856 invocations, 1,538,400 checked, 0 correctness and 0 type-stability findings, 56,736 value comparisons with 134 of 135 oracles, the per-method ledger 0 uncovered of 612, 0 failures in every behaviour lane, 66 context-mismatch findings over 139 cells, the same 72 `radial_spectrum` cells, exit 2 for them alone; the canary green on all three lanes the same evening.** **Re-run 2026-10-12 on `Enteropia` (`-t4`) after decision 101 and the harness's keyword support (`REQUIRED_KEYWORDS` in `invocations.jl`; before it, every engine-built call of the exponential family threw on its missing `coefficient` and was skipped silently): 3,467,136 invocations, 0 correctness and 0 type-stability findings, 56,736 value comparisons with 134 of 135 operations carrying an independent oracle, the per-method ledger 0 uncovered of 612 cells (589 by an assertion, 23 by a recorded reason), 0 failures in every behaviour lane, 66 context-mismatch findings over 139 cells, the same 72 `radial_spectrum` cells, exit 2 for them alone. The 900 fewer invocations per configuration are all decision 101's, counted against the pre-decision tree: the exponential family's positional coefficient and offset slots are gone (1,070 → 212), the reference-taking `anterpolate` forms with them (90 → 30), and the one-argument allocators add 18. A second run the same day, the table now giving the exponential family three keyword sets (no offset, a stored-field offset, a radial-kernel offset) so the offset forms the positional slot used to reach get the universal checks again: 3,641,856 invocations, 1,538,400 returned and checked (1,410,048 before), every other figure unchanged.** **Re-run 2026-10-08 on `Enteropia` (`-t4`, about 95 minutes) after decisions 97–100: 3,553,536 invocations, 0 correctness and 0 type-stability findings, 56,256 value comparisons with 134 of 135 operations carrying an independent oracle, the per-method ledger 0 uncovered of 614 cells, 0 failures in every behaviour lane, 68 context-mismatch findings over 141 cells (all the known kinds), and the same 72 `radial_spectrum` cells, exit 2 for them alone. The canary was green on all three lanes the same day, and the CPU baselines were refrozen: the executor's `mul!` and `sym!` had become 20% and 28% faster than the frozen figures, the other ten mechanisms within 3%.** **Re-run 2026-10-03 on `Enteropia` (`-t4`) after decisions 89–96, the first full run since 2026-09-27: 3,655,296 invocations, 0 correctness and 0 type-stability findings, 56,256 value comparisons with 134 of 135 operations carrying an independent oracle (the one without is `show`), the per-method ledger 0 uncovered of 621 cells (598 by an assertion, 23 by a recorded reason), 0 failures in every behaviour lane, 69 context-mismatch findings over 142 cells, the same 72 known `radial_spectrum` cells, exit 2 for that reason alone.** The run before it found decision 91's `==`/`isequal`/`hash` uncovered and `hash` unreachable (its seed slot had no pool); both were closed — value rows from the definition, a seed pool, and the four cross-representation refusals recorded as reasons citing `test/equality.jl`. Of the 69 context-mismatch findings, 67 are the known class refused by dispatch before a domain check and one is the `length` axis, which has no builder. The last was a FIBER CONTRACT line, `anterpolate(f, pts, q, spline)` declared one tensor order and accepting three: a harness declaration left stale on 2026-08-01, when the entry's call moved to the grid-taking allocating form, which follows the values' order by design. Corrected to fiber-generic the same day; the lane reads 68 over 141. **Re-run 2026-09-27 on `Enteropia` (`-t4`, 94 min) after decision 88's rows landed: 3,606,720 invocations, 0 correctness and 0 type-stability findings, 54,144 value comparisons with 128 of 129 operations carrying an independent oracle, the per-method ledger 0 uncovered of 604 cells, 0 failures in every behaviour lane, 63 context-mismatch cells, the same 72 known `radial_spectrum` cells.** Its first run that day found the `map`/`map!` path past 32 sources (decision 88) and one `displace!` method no row reached; both closed before this run. The figures that follow are the **2026-09-06 afternoon** run's, on
an idle `Aiporetne` (88 minutes), after the morning run had found a week's un-surveyed coverage debt
from decisions 78, 80 and 82 and it was closed: **3,419,808 invocations** over 96 configurations,
**50,400 value comparisons with 125 of 126 operations carrying an independent oracle** — the one
without is `show`, closed by a recorded reason; the 2026-08-29 run read 121 of 121 over a smaller
surface — **0 correctness findings and 0 type-stability findings**, the per-method ledger at
**0 uncovered of 598 cells** (579 by an assertion, 19 by a recorded reason), 293
applicable-but-unasserted cells (283 before), 63 context-mismatch findings over 133 cells, and 0
failures in the declared relations (2,496),
representation/invariance/allocation/ordering (4,992) and sequences (1,632) lanes, 0 disagreeing
assignments in the storage-aliasing lane, and *every* mismatched argument refused in the context lane.
**Re-measure rather than cite these** — every one of them has been found stale by the first
measurement taken after a gap. The only value disagreements are the 72 known `radial_spectrum` cells
(Float32, mixed/shifted grids — the tie-break issue recorded below).

**(3) The four HARNESS findings that run surfaced are FIXED (2026-08-17), and clearing them exposed a
real one.** The survey reported 42,336 findings that were not defects — 18,144 structural and 24,192
type-stability, every one an `adapt_structure(<section>, <object>)` call, because `Adapt.jl`'s hook
takes an *untyped adaptor* slot and the invocation engine filled it from the section pool, building
"adapt these plans **to** this field". Fixed by naming the adaptor slot (`_adaptor_slots`) and filling
it from an adaptor pool, which keeps the operation covered by real calls instead of dropping it.
Clearing that noise made the residue legible and it was two more of the same class, both verified
against the code before being touched: the finiteness scan read `FieldTransformPlans`'
`fft_timelimit = Inf` — FFTW's "no time limit" **setting** — as non-finite data (288 cells), and the
inference query keyed on `typeof(Array) === DataType` where a real call site passes `Type{Array}`, so
it asked a weaker question and got the correct answer `Any` (2,880 cells). And `adapt` was reported as
living in a weak-dependency extension, which it does not; the not-reached line now splits the two
reasons, derived from whether the binding resolves to a package module. **Result: structural findings
0, type-stability 42,336 → 384.**

**(4) CLOSED 2026-08-17 by decision 68 — `adapt` was type-unstable for multipliers and
radial kernels, and now is not.** `adapt(Array, ·)` returns a non-concrete type for `FieldSpectralMultipliers`,
`RadialKernel` and `ProductKernel`, though not for `SeparableKernel`. One root cause:
`adapt_structure(to, multipliers)` passes `_is_canonical(multipliers)` as a **runtime `Bool`** to a
constructor that lifts it into the `Canonical` **type parameter**, so inference cannot resolve it; the
kernels inherit the imprecision because they carry the multipliers' type. **Behaviour is correct** —
the flag is preserved (`typeof(m) === typeof(adapt(Array, m))`) — so this is inference, not a wrong
answer. It is worth fixing because decision 61 made `canonical` a type parameter precisely so
`convolve` can collapse two radial kernels **statically**: after a bus crossing that decision would
fall back to runtime. Binding `Canonical` in `adapt_structure`'s signature was measured **insufficient** (constant
propagation does not reach through the constructor's validation); the constructor now takes
`Val{Canonical}`, so the flag is in the type domain at the call. Pinned by a type-level assertion in
`test/adapt.jl`, the value-level one having passed all along. **(5) `schema_presence` is CLOSED (2026-08-17), and it was never the guard violation** — that
conflation is worth recording because it cost a detour. The check read **0/4** with the marker
"applicable everywhere, asserted nowhere", which sits in the coverage-by-check-type table and is a
different thing from the *second-order guard*, whose count happened also to be 1. Three faults, all in
the instrument: applicability said all four persistence verbs record a schema, when only the two
**writers** do (a reader's matching property is that it *requires* one, which the corrupted-group lanes
already assert as `domain_rejection`); the classifier recognized only `haskey(`, while the suite
asserts a schema by READING attributes and comparing them (`attrs(g)["version"] == 1`), so every
positive assertion was typed `:correct`; and attribution scans **one line at a time**, so a wrapped
`@test` hides either its class or its operation — which is why the first attempt at a fix still read
0/2. Now **2/2**, with `write_field`/`write_points` named on single-line assertions that check the
promised attributes are present. The classifier moved six assertions from `:correct` to
`:schema_presence` (694 → 688, 3 → 9): credit MOVED rather than appeared, as predicted.

**(6) CLOSED 2026-08-17 — the guard was right and neither side it accused was wrong.** The violation
read `inner: a lane asserts allocation, which the ledger calls inapplicable`. Neither the rule nor the
lane was at fault: the ledger had never determined the *fact* the rule depends on. `:allocation`
applies when an operation is in-place **or returns a real**, and `returns_real` was derived by asking
`Base.return_types` about each method's **declared signature** — which, for a package that dispatches
on abstract types throughout, has no answer. `inner`'s declared signature genuinely infers `Any`; with
concrete arguments it infers `Float64`. The same fault as the checks lane's earlier one, in a second
place: asking inference about a type nobody passes. **Blast radius: 42 of 112 operations** had neither
return fact determined, silently marking `allocation`, `inequality` and `structural` inapplicable —
`dot` among them, which plainly returns a section. The facts now come from concrete calls the
invocation engine already builds, with the declared signature kept as the fallback for anything
unbuildable; "neither" is 30, and those are genuine (accessors returning arrays, `cov` returning a
fiber value rather than a section, the kernel builders). Two traps, both caught by measuring:
`invocations` returns a *report tuple*, so the first attempt read its arity as a count and inferred
nothing; and the concrete results include `Union{}`, inference's way of saying a call throws, which is
a subtype of everything and made `inner` and `maximum` claim to return sections. Both `Any` and
`Union{}` are now filtered as the non-facts they are.

**Every public operation is now REACHED by the invocation engine (2026-08-29).** Two were not:
`displace!`, whose terms are `(coefficient, section)` TUPLES that no pool object could supply — the one
operation put out of reach by its argument SHAPE rather than its types — now fixed by a term-pair pool
entry, so its four methods get the five universal checks across all 96 configurations; and `adapt`,
which the package never defines at all (it extends `adapt_structure`, the hook `adapt` dispatches
through) and which is now reported as *not defined here, covered through its hook* rather than counted
as a coverage hole. The two are different things and lumping them together read as a gap where there
was none.

**The survey is clean on every lane it asserts.** The 2026-08-29 run reports **0** correctness findings,
**0** type-stability findings, **0** guard violations, and 0 failures in relations / representation /
invariance / allocation / ordering / sequences / storage aliasing. The 576 type-stability findings its
predecessor reported are gone because the defect they named was fixed — **all one operation**: `reality_residual`
inferred `Any` on every configuration, because it reached the folded plane through a runtime dimension
and the filtered generator `Tuple(a for a in 1:3 if a != folded)` has a type inference cannot narrow.
Fixed by naming the axis as `Val{D}`, the same remedy `Interpolation`'s folded-plane helpers use. That is
what the survey is for: the operation was correct, tested, and documented, and only a lane asking a
question nobody had asked of it could see the defect. What remains is the 72 known `radial_spectrum`
value cells (the Float32 shell tie-break recorded above), 63 context-mismatch cells that refuse at
dispatch rather than at a domain check, and 369 applicable-but-unasserted ledger cells, which are a
coverage report rather than a failure.

**The un-guarded promise kinds are now ENFORCED, and the enforcement found a defect on its first run
(2026-08-29, user-directed).** The applicability ledger tracked five promise kinds advisorily; the two
with no other guard are now gates in `Pkg.test()`, in the allocation-audit shape — derived denominator,
an invocation or a cited exemption per member, completeness both directions, falsified by perturbation:

- **`test/peer_rejections.jl` (tier 3 of the context matrix).** 88 operations validate (a `_check_*`
  reachable in their lowered IR); 36 were enforced by tier 2's carrier gate; the other **52 had no gate
  at all** — the PEER family, whose check is against a second section. Every one is now invoked with a
  foreign peer and must refuse. **First run found the mixed physical `inner(f, g)` accepting two fields
  on different domains and on different layouts** — `_check_contractible` compared orders and counts
  but never the grid's domain or the layout, `inner` was its single caller, and every sibling refuses
  the identical pair. Fixed by delegating a field pair to the same domain check the siblings use; the
  gate is the permanent witness. Also first-asserted: `wrap!`'s precision refusal, `displace!`'s
  point-count refusal, `copyto!` refusing a cross-context broadcast.
- **`test/absence_gate.jl`.** Every representation-asymmetric operation (38, derived by
  `typeintersect` over its signatures) is CALLED on the side invariant 1 leaves absent and must throw.
  No exemptions — every absence is spellable. All 38 refuse; the absence half of the ledger's backlog
  is now enforced rather than counted.
- **`invariance`, `metadata` and `representation` are NOT given new gates, deliberately.** Each is
  already checked per-operation by the survey's DERIVED lanes — the universal metadata check
  (160,992 cells), the representation/invariance lane (4,992 cells), both built from the method table,
  so their completeness holds by construction and now reaches every public operation. The gate suite
  keeps its representative threading assertions plus the decision-47 dispatch-pair guard; a per-op
  threaded-vs-serial sweep in `Pkg.test()` would re-run the survey's lane at gate cost for no new
  information. The ledger's under-count on these rows is its text attribution failing to see runtime
  lanes, not missing enforcement.

**A quarter of the applicability ledger's backlog was an accounting entry for a DEAD CHECK (fixed
2026-08-29).** `:result_type` asked whether a result matched what inference promised, which
`Base.return_types` makes unfalsifiable — it is a sound over-approximation, so in valid Julia the
answer is always yes and the check could only ever have caught a compiler bug. `checks.jl` retired it
for `:type_stability`, which asks the falsifiable question and immediately found 576 real cells. But
its applicability row survived the retirement, marked applicable to every operation, so the ledger kept
120 cells on its books and counted 95 of them as gaps nothing would ever close. Removed from both
`APPLICABILITY` and the assertion classifier; measured on a full run, applicable 1086 → 966 and
unasserted **378 → 283**, with every other lane byte-identical. **The lesson generalises past this
instance: when a check is retired, its ledger row is a second place to delete, and a coverage backlog
should be audited for dead questions before anyone is asked to work it down.**

**The survey's EXIT CODE is permanently 2, and the reason is the harness finding below.** Measured
2026-08-29 (`SURVEY_EXIT_CODE=2`, captured rather than inferred, after two earlier runs whose status
was lost to a detached launch). Every lane that asserts behaviour is clean — 0 correctness findings, 0
type-stability findings, 0 guard violations, 0 relation/representation/invariance/allocation/ordering/
sequence/aliasing failures, and the per-method ledger at 0 uncovered — but `value_findings > 0` forces
exit 2, and those 72 cells are the `radial_spectrum` Float32 shell tie-break recorded immediately
below. So the survey cannot exit 0 until that harness issue is fixed, which means **its exit status
currently carries no information**: it is red for a reason everyone knows, which is the same failure as
a check whose column reads as noise. Read the report, not the status, until the tie-break lands — and
fixing it is the thing that makes the status meaningful again.

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
and an operation covered only relationally.

**Mutation audit (decision 52, 2026-07-29).** The suite was audited by INJECTING defects in isolated
worktrees, not by reading coverage. It found two live bugs (a `NUFFT` plan used above its own tensor order
returned NaN/uninitialized memory; `extrema` leaked the scalar-only absence that `maximum`/`minimum`
enforce, because `Base` HAS a fallback for it) and, more importantly, **fixture blindness**: the gradient testset was
named for an index convention its diagonal fixture could not see, and the tensor divergence had no analytic
oracle at all — nine identical components, so the tensor equalled its own transpose, with every other assertion
self-referential. Both now
have closed-form oracles over asymmetric fixtures, **each verified by re-applying the mutation and confirming
the new test fails**. PF's self-referential pairs are threaded vs serial, device vs host, and compressed
vs stored.

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

- **A GPU cost check against the memory an operation must move — TODO, raise with GBGCodingTools
  (owner-directed 2026-09-30; not started).** No check in PF or HT, and none in the tool, asks whether
  a device operation runs as fast as the memory it must move allows. HT's traffic audit found
  `weighted_inner`'s one-field form reading its field twice, through HT's own forcing, and a one-off
  timing script of HT's then showed the whole device pass at 40–60% above a plain read on the RTX
  5070 Ti. PF measured the rest at 256³ on a vector field: the band symbol is evaluated once per fiber
  component instead of once per mode (+0.107 ms `Float32`, +0.172 ms `Float64`), and the mixed-shape
  broadcast pays per-element index arithmetic (+0.059 ms `Float32`, nothing measurable in `Float64`).
  Those two are computation, not traffic, so a counting audit cannot see them; only a timing against
  the minimum traffic can. The double read is FIXED (2026-09-30): the one-field form takes the one-read
  path on both backends, bitwise unchanged, and the weighted reductions now have traffic-audit rows,
  the reductions never having had any. The two computation costs are NOT fixed, and wait for the
  harness, which would also rank their likely dormant siblings: `convolve!`/`combine!` with a radial
  kernel on a vector or tensor field, `laplacian!`/`inverse_laplacian!` on vector fields, and the
  separable kernels' index cost. HT answered (2026-09-30) that its timing was a one-off probe with no
  wiring to the tool, and that its traffic audit is the tool's engine, on the CPU, as PF's is. The
  owner ruled that the tool is not extended with benchmarks yet; raised with the tool's session on
  2026-10-03 at his word, and ANSWERED by GBGCodingTools rc.56 (`RULE.TEST.DEVICE_COST`): the GPU
  suite now carries the lane (`device_cost_lane`, ten cases at 256³), its bounds frozen for CUDA
  from an idle run on 2026-10-03 (`PERFORMANCE.md` finding (av)): `weighted_inner` 1.33 `Float64`,
  1.67/1.88 `Float32` scalar/vector against plain `add!` at 0.97 — the excess is not only the
  per-component symbol, the scalar form has it too. ROCm is reported, not judged, until frozen.
  **The `weighted_inner` excess is KNOWN AND LEFT (owner-ruled 2026-10-03):** HT measured it at 3.8%
  of a `Float32` step and 1.9% of a `Float64` one (3 calls, 256³, its default run), so reaching the
  traffic floor would save 1.7% and 0.5%, too little for a device reduction kernel with bitwise CPU
  invariance. The frozen bound keeps it from growing; reopen if a production configuration makes its
  share several times larger. **The `Float32` 4-D broadcast excess is KNOWN AND LEFT too (owner-ruled
  2026-10-03):** GPUArrays' generic broadcast pays four-index arithmetic per element, 1.23–1.57 for
  same-shape vector/tensor `add!`/`combine!`/scaling at 256³ against 0.97 when flattened; the
  executor, mixed shapes, `Float64` and spectral fields are unaffected. Flattening in PF's device
  `_assign!` was declined (small share of a step, the most general path, decision 95's aliasing trap,
  ROCm unmeasured); finding (av) has the figures.
- **CUDA unified memory — SUPPORTED and documented (2026-09-17, decision 84).** A single GPU can hold
  fields larger than its memory with no code change: CUDA.jl's `default_memory = "unified"` preference,
  under **`[CUDACore]`** with `CUDACore` in the job project's `[extras]` — the `[CUDA]` spelling in
  CUDA.jl's own template is a SILENT NO-OP since CUDA.jl 6, and `docs/make.jl` rejects it. The one home
  for the how-to is `docs/src/gpu.md` ("Running on a GPU", both vendors; ROCm has no counterpart).
  Measured on `Enteropia`: ~8% slower when it fits, ``2.9\times`` device memory when oversubscribed over
  PCIe (Performance finding (as)); GH200 UNMEASURED (§7 gap 9). The lane `test/gpu/cuda-unified`
  (494/494 + 44/44 on 2026-09-17) refuses to run unless the preference took effect; it CANNOT check
  invariant 6, because CUDA.jl does not honour `allowscalar(false)` for unified arrays, so it adds to
  the device lane and never replaces it. The benchmark harness REFUSES unified memory
  (`CUDA.used_memory()` does not count it). **Re-verify the page on ANY CUDA.jl minor bump** — the
  preference's home moved once already and nothing but the lane's residency check would notice.
- **Multi-GPU and memory spill — a PROPOSAL awaiting a ruling (2026-09-16), not started.**
  Arrhenius' GPU nodes carry **four GH200** each (96 GiB HBM + 128 GB LPDDR + 72 Grace cores per
  superchip; NVLink all-to-all inside the node, ~9× slower access to the host memory a GPU can spill
  into). The full proposal, its fact base, three adversarial reviews and the rulings that resolved them
  are in `.claude/mgpu-proposal/` — read `DESIGN.md` §0 first, which lists the eleven decisions the
  adversarial pass reversed. **It overturns §1's single-node scope and demotes decision 37, so nothing
  moves without the owner's word.** Three things are worth knowing without reading it.
  **(1) Six live defects it uncovered, worth fixing whatever is decided about multi-GPU**, all verified
  in the tree: the decision-74 family constructors destroy a requested memory kind
  (`_allocated_field_storage`, `Fields.jl:893-896`); `_spectral_zero_mode_data` (`:1663`) hardcodes the
  DC mode at local `(1,1,1)`; `_parseval_weight` (`Reductions.jl:946-953`) reads the self-conjugate plane
  indices from the LOCAL extent; the transfer kernels take `prod(grid.grid_size)` as the component stride
  (`Interpolation.jl:1145-1147` → `:974`); the two function-initialized field constructors
  (`Fields.jl:467-479`, `:612-627`) allocate one shape and loop another; and three one-level `parent`
  spellings still diverge from `_same_backend` (`Fields.jl:1966-1970`, `Interpolation.jl:1080`, `:1907-1908`).
  They fall in three classes, and the first is the one that matters now: **`_allocated_field_storage`
  is live TODAY on a single GPU** — it blocks PER-FIELD placement only, since whole-process unified
  memory through CUDA.jl's preference already works and is documented (decision 84, below); the zero mode, the Parseval weight, the
  transfer stride and the two function-initialized constructors go live the moment a base is decomposed;
  the three `parent` spellings go live the moment any wrapper array type appears (a halo or distributed
  array being the first).
  **(2) The architecture predicts the cost and the prediction holds**: 59 of ~93 public operations in the
  field half are unchanged by a decomposed base, because fiberwise algebra is vertical and the operators
  are pointwise in mode space — verified site by site, and it survives only because the operators
  special-case the zero mode and Nyquist **by value** (`ifelse(iszero(squared), …)`,
  `DifferentialOperators.jl:215,274,595,645`), never by index. 20 operations communicate; 14 need a ruling.
  **(3) The threshold question is the owner's, and it is a science question.** This package's consumer
  records 128³ (×18), 256³ (×16) and 384³ (×2) and nothing above; 512³ `Float64` is ~27 GiB against one
  GH200's 96 GiB, so it needs neither feature. Spill alone is small and CUDA-only (AMDGPU has no unified
  memory at all, and gfx1100 could not validate it); four GPUs is a programme of the order of 17–25
  sessions plus consumer work, and its zero-cost competitor — four independent runs on one node — is the
  baseline it has to beat.

- **The forward plan's unused device buffer — DEFERRED (decision 96, 2026-10-03).** One spectral
  scalar per plan set (about 68 MB at 256³ `Float32`, 1.8 GB at 768³), freed by building the inverse
  from the forward plan. Take it up when a run is limited by device memory; the second-copy item
  beside it is declined.

The package is feature-complete for its core mission. Recorded next steps, in priority order:

- **IT's 2026-08-29 codegen report — item 2 DONE, item 3 CLOSED as measured-and-declined (2026-08-31)** (the synced request is
  `GBGHomogeneousTurbulence/.claude/pf-request-2026-08-29-cpu-kernel-performance.md`; item 1, the
  serial `weighted_inner`, is FIXED — `PERFORMANCE.md` finding (ac)). **(2) is DONE (2026-08-30, decision 79):** the
  exponential family's ``R \ge 1`` forms run a decision-38 kernel pair evaluating `exp` ONCE per
  mode — bitwise identical to the broadcast (126-cell A/B), zero bytes on the serial lane, the
  ŵ-extrusion holder retired at the fused ideal. Measured: CPU `-t1` ``2.4``–``3.9\times``, `-t4`
  ``1.65\times``, device ``1.3``–``2.1\times`` `Float64`; two residual cells disclosed in the
  decision (F64 ``256^3``-at-exactly-t8 +3–6% on the V-Cache host; device F32 combination −2%).
  The change also found the decision-47 guard's module-shaped blind spot — three Convolution
  kernel pairs had NEVER been in its scan — and a fixture-blindness instance (a real-typed factor
  buffer passing 126 cells because every ŵ fixture was real-valued in complex storage). **(3) is PROTOTYPED and half-REJECTED (2026-08-30,
  option 3 run on the user's word; scripts in the session scratchpad, no src changes).** The
  prototype ran the PACKAGE call against two hand loops replicating its exact formulas — a plain
  `@inbounds` restructuring (option 1) and the same under `@simd`, i.e. the explicit no-overlap
  promise (option 2) — for `cross` and the tensor–vector `mul!`, bitwise-verified in all 36 cells.
  **Option 2 is DEAD: `@simd` ≡ plain within noise everywhere**, because LLVM already vectorizes the
  restructured loop behind its own runtime overlap guards — so the two-body no-alias fast path, with
  its bitwise proof burden and decision-47 drift risk, buys nothing over restructuring alone and
  must not be built. **Option 1 is real but regime-bound on this host**: at one thread it wins
  ``1.16``–``1.58\times`` `Float64` and ``1.32``–``3.58\times`` `Float32`, but at four and eight
  threads every out-of-cache size is ALREADY at the memory roof (43–47 GB/s, both arms, ratios
  0.96–1.05) — the 9800X3D's cores are fast enough that the scalar engine saturates DRAM from t4.
  IT's 12700K reads 30 GB/s aggregate at t8 — which the first version of
  this entry called "far below any DDR5 roof" and read as headroom. **That host runs DDR4-2666**
  (user-corrected): dual-channel theoretical 42.7 GB/s, practically ~32–36 for a multi-stream
  pattern, so 30 GB/s at t8 is ~90% of the achievable roof and the 12700K is ALSO saturated at
  high threads. IT's own "instruction-capped, not bandwidth-capped" inference falls with it. The
  corrected expectation: the port gains ~nothing at production thread counts on EITHER fleet host —
  its remaining value is the ``1.2``–``1.6\times`` at one/two threads (their 23 GB/s at t1 against
  a ~32–36 roof leaves perhaps ``1.3\times``), and IT runs production at 16–20 threads, so the
  consumer case is weak. **CLOSED as measured-and-declined 2026-08-31**, the 12700K run having been
  taken on `Aiporetne` and confirmed the expectation: out of cache the restructured arm is
  ``1.03``–``1.05\times`` at t1 for `Float64` and ``1.06``–``1.42\times`` for `Float32`, falling to
  ``1.01``–``1.03\times`` at t4 and ``0.99``–``1.00\times`` at t8, with `bitwise=true` in all 36
  cells. The script's own verdict rule — hand ``\approx`` simd ``\approx`` package at t4/t8 out of
  cache — is therefore met on a second microarchitecture, and **option 2 is dead**: `@simd` is
  indistinguishable from the plain restructuring everywhere, so the two-body no-alias fast path must
  not be built. The single real win is `Float32` `mul!` at ONE thread (``1.42\times`` at ``256^3``),
  and the bandwidth column explains why it does not survive: the package call sits at 20.3 GB/s there
  against the hand loop's 28.7, while by t4 both arms read 27–28 GB/s. Note the honest limit of the
  claim — what is measured is that restructuring gains nothing at t4/t8, which is the decision
  criterion; DRAM saturation is the likely mechanism but the ratio, not the roof, is what the verdict
  rests on. `benchmark/study_fiberwise_simd.jl` has answered its question and is deletable.
  Full figures in PERFORMANCE.md finding (aj). The port itself, if it were ever
  re-triggered, is a ONE-body restructuring of `_fiberwise_pass!`'s CPU loop — the highest-blast-radius
  engine in the package, so it takes the full battery, but no second body and no new contract. Also in the file, take-or-leave: no FMA anywhere on CPU, KA's
  ~1.8 MB/step task spawns at ``128^3``, oversized device workgroups, and the 18 `lmul` + 18 pre-C2R
  copies a rocFFT native scale factor could fold.

- **Should the four radial-symbol operators move to the KERNEL route? — INVESTIGATE, not started
  (recorded 2026-08-23, user-directed).** Decision 70 stopped `laplacian!`, `inverse_laplacian!`,
  `divergence!` and `exponential_convolve!` from allocating 144 B a call by storing six pre-oriented
  views on `FieldSpectralMultipliers`. That fixed the symptom on the route those operators are on. The
  open question is whether they belong on that route at all: `gradient!`, `curl!`,
  `helmholtz_projection!` and `symmetric_gradient!` are **already** KernelAbstractions kernels taking
  the raw vectors, and already measured zero — which is exactly why they never appeared in the
  consumer's report. By §9's execution-route policy a cartesian-coefficient operator is a decision-38
  kernel pair, so the four may simply have been on the wrong side of it, and decision 70 patched the
  route instead of moving them.

  **What kernelising would buy.** It would retire the six stored views and, with them, the six type
  parameters and the three sites that match `Canonical` positionally (`_is_canonical`,
  `adapt_structure`, `Convolution`'s static collapse) — which broke at once when decision 70 shifted
  it, and which is the real cost of that fix. The 288 B of resident headers it would also reclaim are
  not a reason; they are 0.0002% of one scalar field at ``256^3``.

  **What argues against, and must be answered rather than assumed.** *(1)* It does **not** reach every
  caller: the same helper feeds `RadialKernel`'s `_kernel_data`, which is consumed inside *other*
  operations' fused passes, so kernelising four operators leaves the kernel-protocol path still
  reshaping per call unless that path comes along too. *(2)* Decision 24 chose the fused-broadcast form
  for `laplacian!`/`inverse_laplacian!` **deliberately and with measurements**, so this overturns a
  recorded decision and needs its own. *(3)* Decision 40 requires every gated CPU loop to be proven
  bitwise thread-count-invariant against its device twin, and decision 47 records what happens when
  such a pair silently falls out of dispatch.

  **Scope, so the cost is visible before anyone starts.** Port the three differential operators to the
  decision-38 kernel-pair shape with gated CPU loops; prove bitwise thread-invariance in
  `test/threading.jl`; re-run the `operators` and `convolution` benchmark classes on **both** backends
  (this owns the machine); and decide whether `_kernel_data` can take the same treatment. **Decision
  rule:** keep whichever route is architecturally consistent *at no performance loss* — if kernelising
  wins and covers the kernel-protocol path, the stored views and their six parameters retire with it;
  if it does not cover that path, decision 70 stands and this entry closes as answered.

- **The radial shell binning does not thread on CPU — INVESTIGATE (recorded 2026-08-30, found by
  the born-slow triage's first run).** `radial_spectrum vec` and the co-spectrum read flat t1 → t8 on
  BOTH hosts at ``\approx 2.7`` GB/s — far below the roof, so it is not bandwidth saturation: the
  Atomix scatter-add into the shell accumulators serialises on cache-line contention (a few hundred
  shells, every thread hammering the same lines). Same class as finding (ac), found by the instrument
  built in answer to it (finding (ag)). The fix shape would be per-thread shell accumulators reduced
  at the end — the accumulator is ``O(N)``, tiny, so the memory objection to privatization does not
  apply — but §9's KA-everywhere policy for the binning kernels and GPU parity bind, and any change
  re-runs the `reductions` class on both backends (owns the machine). Until then the row stays
  flagged as UNEXPLAINED in `RESULTS.md`'s triage section, which is the designed pressure.

- **`reality_residual` neither threads nor fuses — INVESTIGATE and possibly fix (recorded
  2026-08-23, user-directed).** The 2026-08-23 sweep measured **zero thread scaling on both CPUs at
  every grid**: the i7-12700K reads 80.2 µs at one thread against 80.6 at eight, 362 against 366 µs at
  ``128^3``, 1.586 against 1.588 ms at ``256^3``, and at ``512^3`` eight threads is **9.7% slower**
  (13.258 → 14.542 ms); the 9800X3D is flat to within a percent at every grid too. Decision 71's entry
  records the observation and the reason it was left; this entry is the question of whether to close it.

  **The mechanism is two facts, and the second is the one that matters.** *(1)* The pass is written as
  whole-array `reverse`, `circshift` and `maximum` over one or two planes, so it runs through `Base`,
  and `Base`'s `maximum` is serial. *(2)* It is **allocation-bound rather than compute-bound**:
  measured, it allocates **≈6× the plane bytes it reads** (395 KB at ``64^3``, 1.58 MB at ``128^3``,
  6.29 MB at ``256^3``, i.e. 5.87/5.92/5.96× — three temporaries over each of the two stored planes,
  from `reverse`, `circshift`, and materializing `plane .- conj.(partner)` as `maximum`'s argument).
  So **threading the reduction alone would not fix it** — the serial allocation would still dominate,
  which is very likely what the ``512^3`` inversion is. Anyone starting from "give it a threaded
  reduce" will do work and measure nothing.

  **The fix, if it is worth doing, is to fuse rather than to thread.** One pass deriving the mirrored
  partner index inline — the same arithmetic `reverse`-then-`circshift` performs, since index ``j``
  pairs with ``\mathrm{mod}(-(j-1), n) + 1`` — removes all six temporaries, and *then* the gated CPU
  loop threads it for free. That is the §9 execution-route policy's cartesian-coefficient case, so a
  decision-38 kernel pair is the shape the architecture already prescribes.

  **One structural obstacle to know before scoping it.** `reality_residual` lives in `Fields`, which is
  included **second**, while the threaded fixed-tree reduce (`_indexed_tree_reduce`,
  `_fiber_tree_reduce`) lives in `Reductions`, included **last** — so the operation structurally
  *cannot* reach that tree, and no import will fix it. `FiberSections` (included first) carries
  `_assign!` and `_use_threads` but no threaded reduction. So the routes are: write the kernel pair
  with its own reduction, lift a threaded reduce primitive down into `FiberSections`, or move the
  operation. Each is a different size and the middle one touches shared foundations. **Decision 83
  wrote the traversal this item prescribes** — `_reality_projection_planes!` walks the stored planes
  with modular-index mirroring, layout-general through a `Val` on the folded axis, each pair owned by
  one work item and no temporaries — so the residual's fused form is now a reduction over the same
  index arithmetic (`_plane_linear`, the pair ownership) rather than a design question; only the
  threaded-reduce placement above remains to choose.

  **What argues against acting at all, and must be weighed rather than skipped.** The operation is
  ``O(N^2)`` beside the ``O(N^3 \log N)`` round trip it exists to let a caller avoid, so even the
  ``512^3`` figure is ~13 ms against a transform pair costing orders more — the diagnostic is already
  far cheaper than the thing it replaces. The **GPU gains nothing**, being flat and launch-bound at
  238–244 µs (AMD) and 99–104 µs (NVIDIA), so this is a CPU-only win, and decision 37 names the CPU's
  tuning target as the beyond-VRAM grids where the ``512^3`` row does at least sit. And decision 40
  requires any gated CPU loop to be proven **bitwise thread-count-invariant** against its device twin,
  with decision 47 recording what happens when such a pair silently falls out of dispatch — a real
  cost for a diagnostic.

  **Decision rule.** Fuse only if the fused single-pass form is *at least as fast serially* as the
  present one (it removes six allocations, so it should be) — the threading is then a free consequence
  rather than the justification. If fusing does not pay serially, leave it: threading an
  allocation-bound pass is the wrong fix, and the honest outcome is to record that and close.
  **Definition of done** as usual: a CPU oracle test, GPU parity, bitwise thread-invariance in
  `test/threading.jl`, a `test/pass_audit.jl` row (the allocation figure above is the baseline to beat),
  a bounded allocation guard in `test/allocations.jl` rather than a zero one, the `reductions`
  benchmark class re-run on **both** backends, and the four guiding docs.

**LOW PRIORITY — the 2026-08-31/09-01 performance work (user-ruled 2026-09-01).** All of it came
out of the CUDA A/B, the adversarial claim audit and the regression hunt over the committed history
of `RESULTS.md`. It is deprioritised deliberately, and the reasoning is kept so nobody re-escalates
it on sight: every defect here is NARROW (one cell, or one grid, or one retired card), each sits
inside a change that is strongly net-positive, and **each fix is riskier than the defect it repairs**
— conditioning a kernel on scheme, rank, verb, host or grid means a second body, which is what
decision 47 records going silently dead.

**It is FOUR KINDS of thing, and reading it as one ranked list makes nonsense of it** — the sections
below are labelled by kind, and are ordered by what to do FIRST rather than by kind.
**PREVENTION** is a monitoring script to wire in and a checklist rule; neither repairs a number, they
stop the next defect shipping unseen. **DISMISSALS** are flags already checked and closed, recorded
so they are not re-found as news. **CONFIRMED DEFECTS** are shipped regressions with a matched A/B
behind them. **OPEN QUESTIONS** are measurements that would tell us whether a defect exists at all;
nothing is known to be wrong in them yet.

Two rankings, over two different sets, because they are the two questions a reader actually has.
*Which defect matters most?* The **AMD gather**: alone among the three it hits the DEFAULT scheme at
a production grid across a whole backend, and it ranks low only because it is blocked on hardware
that lives on the other host, where it is already queued. *What should be done first?* The
**prevention item**, which is not a defect at all — it costs about an hour and is the only instrument
that would have caught this class, so it earns its place ahead of work that repairs a single cell.

*PREVENTION — do these first; they repair no number.*

- **Make the history regression scan ride the post-sweep analysis — DONE 2026-09-02 (`39abd66c`),
  this entry left unmarked until 2026-10-03.** `report.jl`'s `history_section()` runs it at every
  `RESULTS.md` regeneration, with the hypothesis warning, and the 2026-09-21 table carries its section
  (109 cells at or over 1.25×, all within the dismissed and confirmed classes below). The original
  entry follows. `benchmark/history_regressions.py` reads `RESULTS.md` at every commit that
  regenerated it and flags cells slower at HEAD than their in-regime best. Its first run found
  finding (am), a ``1.46``–``1.48\times`` regression that had shipped for two days past the canary
  (a fixed sample not containing the row), the born-slow triage (which asks about thread scaling and
  declared peers, never history) and three sweep write-ups (each comparing one archive against one
  predecessor). None of those can see a step in a row nobody is watching; this reads every cell's
  whole history at once. Print it beside the triage in `report.jl`, and carry its docstring's warning
  with every flag: a flagged cell is a HYPOTHESIS until a matched A/B against the commit before the
  step confirms it, because the table mixes hosts, sweep shapes and measurement regimes.

- **Sweep an axis for BOTH verbs, not one — DONE 2026-09-02.** The width-8 scatter regressed because
  finding (ad) swept the scheme axis on the GATHER and left the scatter at `CatmullRom`, so the
  configuration that broke was never measured at all. It is now `docs/TESTING.md` §4's **axis 20**
  (the adjoint verb) and a paragraph in `docs/PERFORMANCE.md` §5's coverage contract — both places,
  because the lesson came from a benchmark sweep while the same blind spot would hide a correctness
  bug equally well. "Swept the axis" is false until every verb defined on it has been swept.

  Two errors in this entry's own earlier wording, worth keeping as a caution about acting on a
  recorded item without re-reading its target: it said to add the verb "beside scheme and stencil
  width" in §4, and **neither is an axis there** — the list runs representation, ``R``, element type,
  layout fold, parity, cubicity, anisotropy, origin, degenerate bases, α/β, aliasing, Nyquist,
  backend, threads, kernel storage class, multiplier provenance, array family, component-offset
  alignment, stencil width parity. And it named §4 alone, though the miss was a **benchmark** sweep
  and §4 is the test suite's denominator.

*DISMISSALS — checked and closed; do not re-open without new evidence.*

- **The unconfirmed flags, recorded so they are not re-found as news.** The history hunt also raised
  the CPU `fft` cluster (``1.5``–``1.74\times`` on the 12700K), `materialize_kernel`
  (``1.9``–``2.5\times``), `adapt plans (rebuild)`, and small-grid `NUFFT` on the 9800X3D. None is
  confirmed and most are probably measurement: the `fft` rows move SCALAR and vector together and by
  the same amount, which fails the control that would implicate decision 76 and puts them in the
  §4(p) environment class, and `materialize_kernel` is named in finding (y) as process-history
  sensitive to ``3.2\times`` on identical code. `divergence!∘kernel` and `helmholtz!∘kernel` were
  checked and are FLAT on this host (10.331 → 10.315 and 19.313 → 19.336 ms), so they are vintage
  artefacts and are closed.

*CONFIRMED DEFECTS — each with a matched A/B behind it. The third, the AMD gather at
``1.74\times``, is not listed here: it needs the card and is queued in the AIPORETNE block above.*

- **Decision 76 costs a device vector transform at ``64^3`` on BOTH vendors, and nothing above it —
  and the open question is whether it can be made faster EVERYWHERE (TODO below; recorded
  2026-08-31 from the AMD sweep, scoped by the CUDA A/B the same day, target set by the user).**
  **Read this scoping first:** the cost is a SMALL-GRID one. On CUDA the ``64^3`` vector rows run
  ``1.11``–``1.35\times`` slower, and at ``128^3``/``256^3`` they run ``0.87``–``1.03\times`` — flat
  or faster — against scalar controls at ``0.98``–``1.00``; ROCm's intermediate grids wash out the
  same way. Three plan executions where there was one is a fixed per-call cost, decisive against a
  ``\approx 20`` us transform and invisible against a millisecond one. Since decision 37 names the
  beyond-VRAM grids as the tuning target, **this is an inefficiency at a grid nobody tunes for**, not
  a regression against the production band, and it should be weighed against the host gain below
  rather than treated as a defect needing a route. The rank-free plans apply a transform per contiguous
  component. On the host that WON, up to ``2.4\times`` on vector transforms at ``512^3`` `Float32`.
  On the device it LOSES **at ``64^3``, and that is the only grid where the attribution is
  established**: an A/B against the pre-decision commit, both arms back-to-back on an idle card,
  reads ``1.15``–``1.61\times`` slower for vector transforms there against ``1.00``–``1.09\times``
  for the scalar controls in the same run. Scalar flat while vector moves is the signature that names
  the cause, decision 76 being unable to touch a rank-0 field, which is its own single component
  either way.

  **The ``512^3`` `Float32` shift is NOT decision 76 — the control fails there.** Scalar moved
  ``1.17``–``1.27\times`` against vector's ``1.24``–``1.28\times``, i.e. together, so whatever moved
  that grid moved every transform on it and the decision's marginal contribution is within noise of
  zero. Its cause is unidentified and lies in the wide `93d9d8da..b452fb17` range or in the
  environment. Do not cite it as evidence for the per-component loop; the first version of this entry
  did, and that was an attribution error caught by re-reading the scalar column. The intermediate
  grids wash out at ``0.84``–``1.16\times``. **The mechanism is the per-component loop, NOT the staging buffer** — `_forward_components!`
  issues one `mul!` per component, so a rank-1 transform became three single-component plan executions
  where it had been one batched execution over three. The buffer is built only when
  `_component_offsets_align` reports an odd physical stride (`device = iseven(physical_stride)`), and
  every benchmark grid is even, so no measured row touches it. Decision 76's own "measured cost is nil
  or negative" was a HOST measurement against `FFTW`; the batched-to-per-component change is the part
  that crosses to a device, and it crossed unmeasured.

  **Two cautions before anyone acts.** The archive-to-archive diff OVERSTATES it at ``512^3``
  (``1.759\times`` against the A/B's ``1.275\times``), because those allocating device rows are
  process-history-sensitive — finding (y), which this sweep extended to the device at ``1.74\times``
  for one row on identical code. And the canary is blind here: its `fft` mechanism is `to_physical!`
  SCALAR at ``128^3``, exactly the configuration the decision leaves alone, so all three lanes read
  green through this. Any fix must add a device vector-transform mechanism to that lane, or the next
  regression on this axis is equally invisible.

  **TODO — can decision 76 be made faster EVERYWHERE? (user-directed 2026-08-31.)** The framing that
  matters is not "recover what the batched plan had" but "beat both arms at every grid", because the
  two arms each win somewhere: the per-component loop gains up to ``2.4\times`` on host vector
  transforms at ``512^3`` `Float32` and loses ``1.11``–``1.61\times`` on a device at ``64^3``, while
  above that grid it is already flat or faster on both vendors. A route that keeps the host gain and
  removes the small-grid device cost is therefore a strict improvement over BOTH the old code and the
  current code, and that is the target.

  The natural route is to keep the rank-freedom in the TYPE and recover batching at EXECUTION: a plan
  built once per rank on demand and cached on the `FieldTransformPlans`, or a backend that accepts a
  batch count when the transform is executed rather than when it is planned. Invariant 3 already makes
  a rank-1 field's three components one contiguous block, which is what makes this possible at all;
  decision 76's own argument was that a transform is defined on the box and a rank-`R` field is that
  transform along a fiber, and nothing in it requires ISSUING the executions separately.

  **Measure before designing.** The whole device cost is a fixed per-call overhead — three plan
  executions where there was one — so the first question is how much of the ``64^3`` gap is launch
  overhead that a batched execution would remove, and whether a per-rank plan cache costs anything at
  the grids where the loop currently WINS. A route that fixes ``64^3`` and gives back the ``512^3``
  host gain is not worth taking. **Definition of done** as usual, plus: an A/B on BOTH vendors across
  ``64^3``–``512^3`` (not one grid — the mis-scoping this entry already records twice), and a device
  vector-transform mechanism added to the canary, since that lane is structurally blind here.

  Decision 76 is correct and stays; this is a question about how it reaches the device, not a
  correctness one, and the ROCm suite is green at 454/454 throughout.

- **Reverse decision 78's width-8 scatter regression — the only SHIPPED regression the history hunt
  found (recorded 2026-09-01; `PERFORMANCE.md` finding (am)).** `anterpolate! Lalescu(3,3)` at
  ``512^3`` `Float64` costs ``1.45``–``1.48\times`` on the 9800X3D, on every thread lane, confirmed by
  A/B against `7bbbc75a`. It is one cell — the same row is the 12700K's largest win — but it sits on
  the CPU production grid decision 37 names, and a consumer using the widest stencil pays it.

  **Do NOT fix it with a branch.** Conditioning the walk on scheme, rank, verb or host means a second
  kernel body, which decision 47 records going silently dead. The target is an implementation that
  keeps the walk's cheaper arithmetic **without serialising the address chain** — for instance
  advancing a small block of stencil indices independently so several address streams stay in flight,
  which is the property the `mod` form has and the walk gave up. Measure against BOTH arms across the
  scheme × verb × grid × element-type product, not one verb: this regression exists precisely because
  finding (ad) swept the gather and left the scatter at `CatmullRom`.

  **Test the cache hypothesis while there**, since it now covers four platforms and would predict
  where else this bites: the walk regresses on the two ``\approx 96`` MB last-level-cache platforms
  and helps on the two ``\le 48`` MB ones. A third large-cache platform should regress.

*OPEN QUESTIONS — nothing is known to be wrong yet; these are measurements, not fixes.*

- **The retired-RX-6700-XT verdict cluster — RE-MEASURE (recorded 2026-08-31 by the adversarial
  claim audit; the largest remaining hole it found).** Four GPU verdicts in `PERFORMANCE.md` §4 rest
  on a card that left the fleet, and §4(v) — the section written to re-audit exactly that class —
  did not reach them: **§4(a)** ("spline degree is invisible", stated unqualified from a GPU-only
  table), **§4(b)** (the loop-order table), **§4(c)**'s neighbours, and **§4(d)** (the scatter/gather
  atomics ratio and the non-monotonic clustering curve, never checked on CUDA or RDNA3). The reason
  to distrust them as a group is measured, not theoretical: of the three verdicts taken in that
  2026-06 session, **two have since reversed sign** on current hardware (the wrap-hoist and Morton).
  One transfer-class sweep per card closes the cluster.

- **Is the x-inner loop order still right? — RE-MEASURE, two-host (same audit).** Decision 17 records
  the transfer kernels looping with the contiguous axis innermost, "≈1.6× at ``256^3``, ≈3.9× for the
  ``512^3`` Lalescu gather", and calls the tiebreak "closed on both platforms". The GPU half was
  measured **once, on the retired RX 6700 XT**; the only later measurement is CPU-only, and no
  archive contains a z-inner row. Neither current card has run it. The order is baked into the shared
  kernel body, so a wrong verdict is not something a consumer can work around. **Expect it to hold** —
  the effect is first-order transaction count against a second-order memory-level-parallelism one, and
  x-inner also won the CPU re-measurement — so what is actually defective is the word "closed" and the
  unqualified ``3.9\times``. Method if it is run: A/B the package's own kernel (not a standalone
  probe), gate the permuted arm on the transfer tests passing to tolerance first since it reorders the
  summation, matched `CHAR_*` in both arms, and **report per scheme, never as a median** — finding (al)
  measured two schemes moving in opposite directions across one cache boundary. The headline
  ``512^3`` cell needs Aiporetne; 16 GB cannot hold it.

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
- **Storage-family moves — DONE (2026-08-10, decision 63); PRECISION conversion still open.**
  Invariant 14 refuses a mixed pair rather than converting, which is the right default; the complement
  is now shipped for **storage**, and it is not a package-owned verb. The package extends
  `Adapt.adapt_structure` for the six field types, the three point-value types, `PointSet`,
  `FieldSpectralMultipliers`, all four kernel classes and `FieldTransformPlans`, and re-exports
  `adapt`, so `adapt(CuArray, u)` / `adapt(Array, u_d)` is the interface. A named synonym was declined:
  with precision excluded it takes one parameter, and because `adapt_structure` dispatches on a generic
  target the package gains **both vendors without depending on either**, which a hand-rolled verb could
  not. Everything a section carries besides storage propagates by construction (rebuilt through
  `similar_field`/`similar_point_values`), adapting to one's own family is the identity, and plans are
  **rebuilt unaided** — they carry their own grid, layout, `T` and `R`, a plan outlives its witness
  arrays, and the struct now records its planner request so a rebuild does not silently drop to
  `ESTIMATE` (flags are FFTW-only, so a device rebuild ignores but retains them). Tested in
  `test/adapt.jl` via a custom adaptor (adapting to `Array` would exercise nothing) and in the GPU
  suite, which dropped its three hand-written device-twin helpers in favour of the real interface.
  **Still open — precision.** Deliberately excluded: `cu`'s silent `Float64`→`Float32` is the
  anti-pattern invariant 14 exists to prevent, and it is structurally a different operation, since
  `Grid3D{T}` stores the domain size, spacing and origin at the field's element type and so must be
  rebuilt too. The in-place form **shipped** as `adapt!` (decision 69, 2026-08-18): sections only, no target
  argument since the destination already is the family, measured at ``\approx 4\times`` the allocating
  return trip because that trip's cost is mostly allocating the destination (finding (x)). **What
  remains open here is precision alone** — and whether a **spectral** field's precision change is
  offered at all, on which invariant 2 has an opinion.
- **Point ordering for the gather — DONE (2026-08-30, decision 78), and Morton was the WRONG guess.**
  Shipped as `point_traversal_order` plus a `traversal` keyword on the four point-indexed transfer
  verbs — shipped as `order` and renamed by decision 80 — giving a TRAVERSAL order
  (`traversal[i]` is the point the `i`-th unit of work handles), so nothing is moved, no signature
  changed, and a `PointSet` can never desynchronise from the `PointValues` beside it. Measured at
  ``256^3`` with ``10^6`` points: device gather ``3.4\times`` and scatter ``3.7\times`` (scalar
  `Float64`), rising to ``4.5\times``/``4.1\times`` for a vector field; CPU ``2.2\times`` and
  ``3.2\times`` — and the payoff RISES with stencil width, reaching ``6.95\times`` on CPU at eight
  nodes per axis, so the option matters most exactly where a run is most expensive; at ``1024^3`` the
  `CatmullRom` gets ``1.21\times`` where an eight-node stencil gets ``4.29\times``. **The gating
  measurement the old entry demanded is taken: 0.24–0.27 ms as shipped** (0.098–0.13 ms for the build
  alone, before the permutation validation), a portable
  counting pass over blocks of cells rather than a sort, so it repays inside ONE transfer rather than
  the estimated 12–24 — and the vendor `sortperm` it assumed is ``25\times`` more expensive than the
  portable route, so the dependency question closed itself. **Morton lost to plain lexicographic block
  order** on every cell, which Domínguez et al. (2011) also report for this access pattern. Details in
  `docs/PERFORMANCE.md` finding (ad).

- **Wrap-hoist in the transfer kernels — DONE (2026-08-30, decision 78), by a different mechanism
  than the one that was rejected.** The rejected hoist precomputed index tuples with `ntuple` and paid
  registers for them, which is why it lost occupancy at ``R = 3``. The shipped form is a WALK: the
  stencil visits consecutive nodes, so `_wrap_step` advances each index by one with a conditional zero
  instead of calling `mod` per node, removing 29 of the 32 integer divisions LLVM was emitting per
  point per fibre. **Bitwise identical** over 48 configurations including a stencil wider than the
  grid. **It has one bad corner**, which the first sweep missed by measuring only
  `CatmullRom`: it wins ``1.3``–``1.9\times`` on CPU up to six nodes per axis and
  ``1.03``–``1.28\times`` on the device throughout, but loses **4–14% on CPU at eight nodes per axis,
  only above about four threads and only at ``R = 1``** — at one thread it is 17–22% FASTER, and
  ``R = 2`` is less affected. **"On the device throughout" is WRONG and was corrected 2026-08-31**:
  the device `CatmullRom` gather at ``256^3`` `Float64` is ``1.74``–``1.78\times`` SLOWER, measured
  three times by matched A/B. The sign tracks the working set against the card's 96 MB Infinity
  Cache — ``0.75``/``0.92\times`` at ``128^3``, ``\approx 1.22\times`` at ``256^3`` `Float32`
  (67 MB), ``1.74\times`` at ``256^3`` `Float64` (134 MB, the only measured configuration exceeding
  it) — so the very memory-level-parallelism mechanism this entry already names for the CPU corner
  applies on the device too, and the original device sweep simply never crossed the cache boundary.
  `CatmullRom` is the scheme it bites because it reads 64 nodes per point, the family's lowest
  arithmetic intensity; `Lalescu(3,3)` reads 512 and stays flat. See PERFORMANCE.md finding (aj). **The mechanism first recorded was backwards**: `mod` is the form that
  vectorizes and neither variant spills ON THE HOST, so the CPU loss is the walk saturating bandwidth
  sooner and forfeiting the memory-level parallelism independent indices keep, which is also the only
  story consistent with a sign that flips on thread count. **On gfx1100 the walk DOES spill** for
  `CatmullRom` — 192 VGPRs, 292 bytes of scratch, occupancy halved 16 → 8, the flat `Lalescu(3,3)`
  untouched — which is the AMD-only device regression's mechanism, finding (aq). Kept with the corner documented. Finding (ad) carries the swept table.

  **THE CORNER IS BIGGER THAN THIS ENTRY SAYS, found 2026-09-01 (finding (am)).** Every figure above
  is the GATHER; the width-8 **scatter** was never swept, and it costs **``1.45``–``1.48\times`` at
  ``512^3`` `Float64` on the 9800X3D** — confirmed by A/B against `7bbbc75a`, on every thread lane
  including ``t1``, where this entry claims the walk is 17–22% faster. It is ONE cell (widest stencil
  × largest grid × `Float64` × that host); the rest of the class is ``0.73``–``1.11\times`` there and
  ``0.56``–``0.95\times`` on the 12700K, where the same cell is the table's largest win. **The
  working-set story above is superseded**: the walk regresses on the two ``\approx 96`` MB
  last-level-cache platforms (9800X3D V-Cache, RX 7900 XTX Infinity Cache) and helps on the two
  smaller ones (12700K, RTX 5070 Ti), and a 1 GB field fits none of them — so the split is by the
  memory system's capacity to serve independent misses, not by residency. Still kept, still not
  branched (decision 47), and the route to reversing it is in the roadmap.

- **Open interface questions from the doc panels (recorded 2026-08-15, none started).** Each is a real
  observation that survived verification, and each is breaking, so they wait for a breaking round
  — the bundle is now **EMPTY**: item (1) closed 2026-08-15, items (3) and (5)
  2026-09-02
  rather than being taken piecemeal. They are recorded **here** because the panel's own findings pile
  (`.claude/doc-review/`) is gitignored and is deleted by the second-next run. **(1)** *(CLOSED 2026-08-15, decision 67 — `Base.similar`
  declined for the section allocators; the reasoning is on both docstrings and the item is in the
  do-not-re-flag list.)* **(2)** *(DONE 2026-09-02 — `map!`/`map` refuse a field in the φ slot; the
  callable `f(x)` stays.* A field in physical representation is callable, so passing one as φ
  type-checked and RAN: with a vector source it silently interpolated the field at its own source's
  fiber values read as positions and returned a plausible number, and with a scalar source it threw a
  `BoundsError` naming nothing. Both families carried it — a point-value fiber at ``R = 1`` is an
  `SVector{3}` exactly as a field's is — so `Fields` owns the two-method guard
  `_refuse_field_as_fiber_map` and `FieldAlgebra` and `Points` each call it from their three
  `map!`/`map` methods. Measured free: the non-field path is a no-op the compiler removes, and vector
  `map!` allocates the same 144 B before and after. `Fields` refrozen 128 → 130 with the reason;
  witness in `test/regressions/callable-field-as-fiber-map.jl`, confirmed to FAIL on the pre-fix tree
  before being kept. Removing the callable — the framing this item shipped with — was never needed.
  The fix MISSED the class: the five mapped reductions take the same φ and kept accepting a field, on the
  CPU returning a plausible number and on ROCm crashing the compiler, until 2026-10-17, when the first ROCm
  survey found it and one guard call in their shared pass closed all five; witness in
  `test/regressions/callable-field-as-reduction-fiber-map.jl`, which fails on the unfixed tree.)
  **(3)** *(CLOSED 2026-09-02 (user): `AbstractField` stays a `Union` — leave it as is, do
  nothing, and do not re-raise.* The decision-60 analogy that motivated the item is about NAMING, not
  cost, and the cost question was settled by measurement rather than argument: the same body under
  `::AbstractField`, under `::AbstractFieldPhysical` and untyped runs at 15.92 / 15.99 / 16.15 µs on a
  ``64^3`` scalar field, identical within noise, with inference returning a concrete `Float64` through
  the Union. Julia specialises on the concrete argument type, so the annotation never reaches the
  compiled code. A `Union` costs where it is a **struct field type** or an **array element type**, and
  this one is neither — it appears in 31 method signatures and nowhere else. Note also what decision
  60 actually measured: its *replacement* being free (the `StoredKernel` wrapper, 144 bytes at
  construction and zero per call), not the old union being slow.)
  **(5)** *(CLOSED 2026-09-02 (user): `Grid3D`'s two-argument constructor keeps `origin` as a
  KEYWORD — leave it as is, do nothing.* The finding is correct: the four-argument form takes it
  positionally, and the policy then made a result-affecting argument positional, `origin` shifting every
  node. It was a **recorded exception to that policy** until GBGCodingTools rc.63 (2026-10-06)
  reworded the rule so that every argument with a default is a keyword; the keyword now complies and
  its switch is gone. A re-raise closes against this note. Facts in front of the decision: `Grid3D` is the only
  PUBLIC entry point taking an origin at all, while every INTERNAL taker — `_locate`,
  `_wrap_coordinate`, the tile-key kernel — already has it positional, so the keyword is the lone
  outlier and the disagreement is confined to one type's own constructor pair; blast radius 24 in-repo
  `origin =` call sites, up from the 15 recorded on 2026-08-15, plus unknown use in
  `GBGHomogeneousTurbulence`.) **(4)** *(DONE 2026-09-02 — `Points` now uses one prefix, spelled as the prose spells it:*
  `point_positions` (and the `PointSet` field `coordinates` → `positions`),
  `point_value_tensor_order`, `similar_point_values` and five internals off the same stem;
  `point_values` and `npoints` are unchanged, the latter being defined on BOTH types so no prefix
  fits. The spelling was settled by measurement: "pointvalue" unhyphenated occurred in prose **zero**
  times against 98 for "point-value", so the identifiers were the outlier rather than the docs.
  `point_value_*` was chosen over a uniform `point_*` because it keeps the type distinction — those
  accessors are on `AbstractPointValues`, not `PointSet`. Breaking, as recorded; the consumer
  `GBGHomogeneousTurbulence` needs the same rename.)

- **`point_traversal_order`'s in-place form — DONE (2026-09-03, decision 80).** The docstring's promise
  ("There is no in-place form yet") is kept: `point_traversal_order!(traversal, grid, points, scratch)` rebuilds
  a traversal order into storage the caller owns, against a `PointTraversalOrderScratch` built once for a grid,
  a point count and a `tile_size`. Measured **constant in the point count** — 1248 bytes at ``10^3``
  points and 1312 at ``10^6``, all of it `KernelAbstractions` launch bookkeeping on the host, where
  the allocating form grows 18.9 KB → 13.0 MB. The permutation check survives the move (it takes the
  caller's marks now), both forms share one build so they cannot drift, and the block layout travels
  with the scratch rather than as a keyword so an order and its histogram cannot disagree. Rejected
  alternatives and their reasons are in the decision entry. **GPU parity RAN 2026-09-03 on `Enteropia`:
  466/466, exit 0 in 4m16s**, up from 454 — the twelve new cells are this decision's device lane, and
  they are the ones that matter, every array the form avoids allocating being a device array. ROCm is
  a lag, not a gap: `Aiporetne` still reads 454 and picks this up on its next run.
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
  100 samples × 5 evals — 20 samples let µs-canaries false-alarm. The `evals = 5` is **live**:
  `tune!` does not override an explicitly-set `evals` (measured 2026-08-09, and the frozen baselines
  store 5), which is load-bearing here — it amortizes a per-sample GC over five calls, so the CUDA
  canary lane was only ~10% inflated by the §4(s) defect where that host's `characterize.jl` sweep,
  running at `evals = 1`, was ~46%.
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

- During large refactors, complete "supposedly working" drafts are acceptable for
  architecture review, but loading + parity checks are required before calling work
  finished.
- **Commits and CI — PF's part.** Old commits keep whatever trailer they were written with; history is
  not rewritten. CI is manual-only because push-triggered CI burned the free tier, and a device change
  also runs the GPU suite before its commit. The sub-environments whose manifests are gitignored are
  `docs/`, `test/gpu/*` and `benchmark/*`. **One Julia, two thread counts.** The compat
  floor was raised 1.11 → 1.12 on 2026-07-19, so the CI matrix now differs only in `-t1` vs `-t4`
  and there is no second local lane and no per-version manifest dance. Why 1.11 went: the package
  *ran* faster on it (every op, 1.11 vs 1.12 steady-state), but compiling cost several times more
  (`_assign!` 4.5×, the `KernelAbstractions` path 1.4×), so `Pkg.test()` took 31 min against 5.4 —
  a pure compile-time tax, unfixable from our side, for a Julia nothing in the fleet runs. Sibling
  packages (`GBGHomogeneousTurbulence` declares `julia = "1.11"`) are being bumped separately.
