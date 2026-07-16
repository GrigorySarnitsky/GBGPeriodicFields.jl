# CLAUDE.md — GBGPeriodicFields

Julia package: real-valued scalar/vector/second-order-tensor fields on 3D rectangular
periodic domains, with physical-space and real-to-complex (rfft) spectral
representations, on CPU (`Array`) and GPU (`CuArray`, `ROCArray`) — **single node, shared-memory only**
(CPU multithreading and a single GPU; distributed/multi-node and multi-GPU are out of scope). Built as the field
layer for pseudospectral fluid/turbulence solvers, with the interpolation/anterpolation point layer for
Lagrangian-particle methods in place. Development is **GPU-first**; CPU multithreading is implemented (hybrid, behind the
`_assign!` primitive — see `docs/ARCHITECTURE.md` §9).

Before any structural or design change, read `docs/ARCHITECTURE.md`. It explains why
the architecture is the way it is; do not re-litigate recorded decisions without the
user. **Design changes must be justified by established mathematics** — the
differential-geometry / fiber-bundle framing of §2 (fields and point-values as sections
of a flat tensor bundle over a base; the vertical fiberwise / horizontal grid-bound
operation split) — **not by convenience**: "it's convenient", "for symmetry", or "for
completeness" is never a valid justification (cf. invariant 1's deliberate absences). The
conceptual model and the writing/docstring conventions are recorded once — in
`docs/ARCHITECTURE.md` (§2 and its documentation policy) and this file; the umbrella module
`src/GBGPeriodicFields.jl` only points there (its former AI-tips block was merged out, to keep one source).

## Modules and wiring

- `src/FiberSections.jl` — base-agnostic foundation: the `AbstractFiberSection{T,R}` supertype (field and point-value types subtype it), the `_assign!`/`@_assign!` threading primitive, and the **vertical-algebra code generators** (per-component formula + kernel-body builders, incl. norm/sym/skew/dev via `section_scalar_type`) — reused verbatim by `FieldAlgebra` and `Points`, so each fiberwise formula is written once.
- `src/Fields.jl` — types (`Grid3D`, `RealFourierLayout`, field types; `FiberVector{T} = SVector{3,T}`, `FiberTensor2{T} = SMatrix{3,3,T,9}`, plus `FiberTensor3/4`), memory layout, broadcast style, compatibility checks, `FieldTransformPlans`, `FieldSpectralMultipliers`.
- `src/FieldAlgebra.jl` — fiberwise/pointwise algebra; method families emitted by code generators. Includes `combine!` (the weighted combination / axpby `α·a + β·b`, linear ⇒ both representations, alias-safe) and `det`/`det!` (the determinant, the third invariant `I₃`; nonlinear ⇒ physical-only, mirrored to point-values where `tr` lives; decision 27).
- `src/DifferentialOperators.jl` — spectral operators (`gradient`, `divergence`, `curl`, `symmetric_gradient` (the fused symmetric part of `∇u`, `Ŝ_ij = (i/2)(k_j û_i + k_i û_j)` — the symmetric peer of `curl`, skipping the full gradient; decision 27), `laplacian`, `inverse_laplacian`, `helmholtz_projection`, in-place variants). Imports `FieldSpectralMultipliers` and its compatibility/broadcast helpers from Fields; the umbrella re-exports the Fields version. Owns only the spectral kernels and the operators. The in-place `!` operators are **allocation-free** (lazy `|k|²` via `_squared_wavenumber_broadcast` returning an unfused `Broadcasted`, + fused `helmholtz_projection!`/`laplacian!`/`inverse_laplacian!` kernels), so a preallocated in-place hot loop allocates nothing per step — required for hassle-free GPU runs (no manual GC/`reclaim`; decision 24, guarded by `test/allocations.jl`). Keep it that way: new in-place kernels must fuse their scratch, not materialize it.
- `src/Convolution.jl` — **periodic convolution** of a field with a kernel, in spectral representation (the kernel-multiplier family). `convolve`/`convolve!` apply a kernel `ĝ` (a `ScalarFieldSpectral` transfer function) as the coefficientwise product `f̂·ĝ` — the operation invariant 1 names but bans as `*`, offered under its true name `convolve` (exported infix `⋆`; never `*`); a scalar kernel broadcasts over the fiber, with α/β, alias-safe (no guard, like `laplacian!`), spectral-only; `convolve(g₁,g₂)` composes kernels. `spectral_cutoff` builds the isotropic sharp low-pass (de-aliasing) kernel; `spectral_band(ref,mult,k_lo,k_hi)` is the annular generalization (cutoff = the `k_lo=0` case); `squared_wavenumber_field(ref,mult)` is the `|k|²` radial coordinate as a `ScalarFieldSpectral` (the consumer builds `exp(−ν|k|²Δt)`/envelopes/Germano from it — invariant 12, decision 21); `assignment_window(ref,mult)` is the linear/CIC mass-assignment window `Ŵ=∏ sinc²(kₐΔxₐ/2)` for **deconvolving** a gridded point density (Phase 2 of the RDF route, decision 22); `translation_kernel(ref,mult,h)` is the shift theorem's phase `ĝ=e^{−ik·h}`, which **displaces** a field by a physical offset h (`f ↦ f(x−h)`) — the one **complex** kernel, whose Nyquist value must be the *real* factor `cos(πhₐ/Δxₐ)` (even part ← true `|k|`, odd part ← the Nyquist-zeroed derivative `k`; the first op to use **both** multiplier families — invariant 5) or the result is no real field's spectrum (decision 28). Imports the spectral types + helpers from Fields. `docs/ARCHITECTURE.md` §2, decisions 20, 21, 22, 28.
- `src/Points.jl` — the unstructured base: point-data types (`Point`, `PointSet`, and `ScalarPointValues`/`VectorPointValues`/`TensorPointValues` under `AbstractPointValues <: AbstractFiberSection`, all exported) and their **full fiberwise algebra** (M2 + M3 mirroring the physical field surface, generated by reusing the FieldAlgebra builders over an extended section interface — no formula written twice). Implemented and tested.
- `src/Interpolation.jl` — the grid↔point transfer: **interpolation** (gather `W`, grid→point; also the callable `f(x)`) and its adjoint **anterpolation** (scatter `Wᵀ`, point→grid, with α/β), an L²-adjoint pair under one `AbstractTransferScheme` (a scheme = choice of *kernel* + *representation*; decision 23). **Two families.** *Physical-domain splines* (`AbstractSplineScheme`): smooth `LalescuSpline(n,m)` (two-point Hermite, `CatmullRom = (1,1)` default, TurTLE-pinned) and `C⁰` `LagrangeSpline(n)`; portable KernelAbstractions + Atomix kernels (CPU/CUDA/AMDGPU, atomic scatter); shared partition-of-unity weights ⇒ conservation. *Spectral-domain exact transfer* (`DirectDFT`, on a field in spectral representation): the literal `O(NM)` inverse/forward DFT `f(xₚ)=(1/N)Σₖ α(k)·Re(f̂ e^{ik·(xₚ−o)})` / `Σₚ qₚ e^{−ik·(xₚ−o)}` — reproduces the band-limited field exactly (divergence-free reference; matches `to_physical` at nodes), the transparent baseline + the oracle for the native fast `NUFFT(reference; tol)` (`O(N log N + M)` windowed gridding = spread→FFT→deconvolve, reusing the transfer kernels + oversampled plans + an `assignment_window`-style deconvolution; own-native, no dependency; exact to ε vs `DirectDFT` on the resolved **sub-Nyquist** band — the rfft Nyquist is projected out, so the pair stay exact adjoints). `docs/ARCHITECTURE.md` §10, decision 23.
- `src/Reductions.jl` — the **L²/measure structure** (the third operation family, after the vertical fiberwise algebra and horizontal differential operators): base reductions over `AbstractFiberSection`, against the base's measure (`Grid3D` cell volume / `PointSet` counting). `integral` (extensive `∫f dμ`), `inner`/`l2norm`/`lpnorm` (normalized L²), the multiplier-weighted `weighted_inner(f[,g],w) = ⟨f,w·g⟩` (spectral-only, the reduction-dual of `convolve`, generalizing `inner`; `w=|k|²` is the Dirichlet energy; fused, allocation-light; decision 27), and `mean`/`std`/`var` (extending `Statistics`, fiber-preserving) + `maximum`/`minimum`/`extrema` (extending `Base`, scalar sections). Measure reductions on **physical fields + point-values**; `inner`/`l2norm` (Parseval — equal to the physical inner, rfft half-spectrum weighting) and `integral`/`mean` (the zero/DC Fourier mode, reusing `_spectral_zero_mode_data`/`_spectral_constant_scale`) *also* act on fields in **spectral representation**, equal to the physical value with no transform, and the **radial reductions** `radial_spectrum(f,mult)` (shell-resolved inner = the radial power spectrum, spectral-only) + `radial_correlation(f,plans)` (its physical-space Wiener–Khinchin dual, the shell-averaged two-point autocorrelation `C(r)=𝓕⁻¹(|f̂|²)/N`); `sum(spectrum) == C(0) == inner` (decisions 21, 22), each with a **two-field co-spectrum** form `radial_spectrum(f,g)` / `radial_correlation(f,g)` (cross-power / cross-correlation, refining the mixed `inner(f,g)`; symmetric, may be negative; the one-field forms are the g=f case). `mean(points) = (1/M)·Σ` (counting measure). The radial pair shares one device-clean **scatter-add** shell-binning pass (`_bin_by_shell`; decision 25). Physics stays consumer-side. `docs/ARCHITECTURE.md` §2, decisions 18, 21, 22, 25.
- Include order: FiberSections → Fields → FieldAlgebra → DifferentialOperators → Convolution → Points → Interpolation → Reductions. Cross-module access only through explicit `using ..Module: name, ...` lists — never a bare `using`.

## Core invariants — do not violate

1. **The public method set is the spec.** Deliberate absences encode representation
   validity: no spectral field×field *multiplication* (`*`/`multiply!`) — the
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
9. Aliasing: in-place ops whose destination may alias an input go through
   `_guard_noalias!`; `mul!` is exempt and instead documents that destination must
   not alias (LinearAlgebra convention).
10. α/β kernels: five-argument forms convert `T(α)`, `T(β)` and branch on
    `iszero(β_value)` (overwrite vs accumulate); three-argument forms delegate with
    `one(T)`, `zero(T)`.
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
    Deliberate materializers (`norm!`/`lpnorm`/`dev!`/`std`/`var`, the radial diagnostics, the mixed
    spectral `inner(f, g)` — a strided-view `dot` being unavailable on the GPU) are the documented
    exceptions and get a *bounded* regression guard, not a zero guard.

## Code generation rules (FiberSections + FieldAlgebra)

- Per-component formulas are written **once** in `FiberSections` (shared by `FieldAlgebra` and
  `Points`); `@eval` tables in each consumer stamp out the representation, argument-order, and
  in-place/allocating variants. Builders (all in `FiberSections`):
  `_vector_component`/`_tensor_component` (kinds `:field`/`:fiber`), `_sum_terms`,
  `_product`, `_vector_kernel_body`/`_tensor_kernel_body` (with `alpha_beta` flag),
  `_scalar_kernel_body`, the contraction/decomposition formula builders, and `section_scalar_type`
  (real `T` for any section). The alias guard `_guard_noalias!` stays per-consumer (it allocates
  via the base's `similar_*`).
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
(codegen builders, alias guards, shared Fields helpers, spectral kernels) carries
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
``\\equiv \\langle\\cdot,\\cdot\\rangle``, `l2norm` ``\\equiv \\lVert\\cdot\\rVert``, `convolve`
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
umbrella docstring listed only some operation families), so check each module/operation/summary still names
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
because the checks were repeatedly run one-at-a-time, surface-by-surface, across one review.

**The review unit is the operation family and the cold read — the two defects a per-docstring pass
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
bundle foundation + a linked one-liner per part); §§3–12 own the details (each operation family has a body
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

Before adding or changing tests, read `docs/TESTING.md` — the testing philosophy and
the per-operation coverage contract. Before optimizing or benchmarking, read
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
   materializer gets a bounded guard instead).
2. **Performance test** — a benchmark in the matching `benchmark/` class (a new `add_<class>!` +
   wiring into `benchmarks.jl`/`report.jl` if it is a new class), per the `docs/PERFORMANCE.md` §5
   benchmark coverage contract. Run it; regenerate `benchmark/RESULTS.md` when practical.
3. **The four guiding docs** — `docs/ARCHITECTURE.md` (a decision-log entry **and** the relevant
   section), `docs/FORMALIZATION.md` (a typed entry for any nontrivial new/changed statement — re-verify
   the expansion against the new code, link its test), `docs/TESTING.md` (§2 layout + §7 coverage), and
   `docs/PERFORMANCE.md` (model + coverage/gaps), as applicable. They are the spec, not an afterthought.
4. **The rest of the docs + this file** — the API page (`docs/src/api/…` and `make.jl`
   modules/pages for a new module), the `docs/src/index.md` / `docs/src/api.md` module lists, and
   **`CLAUDE.md`** itself (the module list, include order, roadmap, and test summary).

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
   index-shuffles (transpose, sym/skew/dev) are alias-guarded via `_guard_noalias!`.
3. **DifferentialOperators.jl** — **done**: the duplicate `FieldSpectralMultipliers`
   and its helpers removed and imported from Fields, export dropped, and the umbrella
   now re-exports the Fields version (verified: every Fields export surfaces as the
   same object through the umbrella). Operators tested by analytic round-trips in
   `test/differentialoperators.jl`. The old five-argument
   `FieldSpectralMultipliers(grid, layout, k1, k2, k3)` constructor is gone by design —
   use the field convenience constructor or the explicit six-array form. The fused
   `symmetric_gradient`/`!` (the symmetric part of `∇u`, the peer of `curl`, skipping the full gradient;
   decision 27) was added, tested by the `sym(gradient)` equivalence + analytic diagonals (incl. the
   anisotropic box) + GPU parity + allocation-free.
4. **Tests** — `test/` suite (`runtests.jl` + per-module files + `test/Project.toml`;
   `Pkg.test()` green, ~2200 tests; threaded lane `JULIA_NUM_THREADS=4`). `test/fields.jl`: FFT round-trip, multipliers vs
   `fftfreq`/`rfftfreq`, Nyquist behavior, validation, transform input-preservation.
   `test/fieldalgebra.jl`: M2 + M3 arithmetic and contractions in both
   representations, the weighted combination `combine!` (physical+spectral, alias-safe accumulate) and the
   determinant `det` (per-point LU oracle, spectral absence), the spectral zero-mode invariant, in-place
   forms and the unary alias guards, the
   physical/spectral symmetry of the linear field/fiber operations, and the
   intentional absences. `test/differentialoperators.jl`: gradient/divergence/curl/
   symmetric_gradient/laplacian/inverse_laplacian/helmholtz by analytic round-trips, incl. in-place
   operators, the Nyquist end-to-end split, the div(curl)=0 / curl(grad)=0 identities, the
   `symmetric_gradient = sym(gradient)` equivalence + its symmetry,
   and an anisotropic
   (2π, 4π, 6π) box exercising the 2π/L wavenumber scaling (incl. `symmetric_gradient`). `test/convolution.jl`: convolution as
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
   inversion, and the fiber broadcast over vector/tensor fields. `test/interpolation.jl`: the
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
   (`integral`/`mean`/`inner`/`l2norm`/`lpnorm`/`std`/`var`/`maximum`) on physical fields and
   point-values vs analytic oracles (`⟨sin⟩=0`, `⟨sin²⟩=½`) and manual references, Float64/Float32,
   the `(1/N)Σ`-grid / `(1/M)Σ`-points arithmetic-mean semantics, the `integral = measure·mean`
   relation (anisotropic box), the energy identity, the **spectral zero-mode `integral`/`mean`** (equal to
   the physical reductions via the DC coefficient) with `std`/`var`/`lpnorm`/`maximum` still spectral-absent;
   the **multiplier-weighted `weighted_inner`** `⟨f,w·g⟩` (w≡1 → `inner`, w=|k|² → the Dirichlet energy
   `⟨f,−Δf⟩`/`⟨∇f,∇f⟩`, sharp-band idempotence `‖w⋆f‖²`, f↔g symmetry; scalar/vector/tensor, two grids,
   spectral-only, physical absence); plus
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
   `test/convolution.jl` additionally covers `spectral_band` (annular,
   `spectral_cutoff = band(0,k)`, idempotent, `|k|²` membership oracle), `squared_wavenumber_field`
   (|k|² vs the analytic sum, real-valued). `test/rdf.jl`
   (decision 22 Phase 2): `assignment_window` against its ∏ sinc² formula, and the FFT pair-correlation recipe (anterpolate density → deconvolve by
   `assignment_window` → `radial_correlation` → g(r)) validated against an **independent direct O(M²)
   pair count** on a clustered point set (the clustering peak + the g→1 baseline). `test/eltype_genericity.jl`:
   a representative cross-section in Float64 and Float32, asserting element-type
   preservation. `test/method_parity.jl`:
   the full 206-method field baseline + the 122-method point-value baseline + ambiguity check. `test/aqua.jl`: `Aqua.test_all`
   (ambiguities, unbound args, piracy, compat, stale deps). `test/jet.jl`: JET `@test_call`
   static analysis of the public ops (filtered to package modules). `test/adjointness.jl`: operator
   adjointness and structural identities (div=-gradᵀ, self-adjoint curl, negative-definite
   Laplacian, idempotent Helmholtz projection) on randomized band-limited fields. `test/randomized.jl`:
   property-based tests — algebraic laws (vector-space, dot/cross/mul!/transpose/sym/skew/dev,
   reduction symmetry/linearity/Cauchy–Schwarz, convolution bilinearity/commutativity, div(curl)=0,
   curl(grad)=0) on random fields, point-values, and kernels over several trials. `test/allocations.jl`:
   a **comprehensive** `@allocated` audit (both element types) — the *entire* in-place `!` surface
   (spectral operators incl. `symmetric_gradient!`, transforms, `convolve!`, and `add!`/`combine!`/`subtract!`/`mul!`/`multiply!`/`divide!`/`dot!`/
   `cross!`/`transpose!`/`sym!`/`skew!`/`det!` over physical+spectral × R=0/1/2 × field/constant/reversed × α/β, the
   point-value algebra (incl. `det!`), and the spline `interpolate!`/`anterpolate!`) allocates ~0 bytes; the hot-loop
   reductions (physical `inner`, the fused `weighted_inner`, `maximum`, `integral`/`mean`/`std`/`var`) do not materialize a field; and the
   documented allocators are bounded (`norm!`/`dev!`/`lpnorm`/`radial_*` are occasional diagnostics; the
   spectral *vector* `inner` allocates only its O(N²) Parseval-correction planes — a strided-view `dot`,
   which would fuse, is unavailable on the GPU). Locks the GPU hot-loop discipline (decisions 24, 25).
   GPU coverage is opt-in and lives
   outside `Pkg.test()` in `test/gpu/` (per-backend environments; `test/gpu/suite.jl`
   exercises the public surface (fields, the PointValues algebra, the interpolation/anterpolation transfer, convolution, and the L²/measure reductions) on device arrays across Float64 and Float32 with `allowscalar(false)`, comparing
   against the CPU result — the GPU **vendor** stacks (CUDA/AMDGPU) stay test-only; only the backend-agnostic KernelAbstractions/Atomix (used by the transfer kernels) are package deps).
5. **CPU threading** — **done** (`docs/ARCHITECTURE.md` §9): the `_assign!` primitive threads
   elementwise/fiberwise ops on CPU (Base.Threads, contiguous chunks, bitwise-identical to
   serial), routed in via the field broadcast `copyto!` and the kernel assignments (codegen
   `_to_broadcasted` + the `@_assign!` macro); FFTW threads match Julia's at load (`__init__`).
   Hybrid policy: on when `nthreads() > 1` above a `2^14` cutoff, with a `with_threading`
   ScopedValue override; GPU stays on the `materialize!` fallback. Tested bitwise in
   `test/threading.jl` (run the threaded lane with `JULIA_NUM_THREADS=4`). **Discipline:** raw
   elementwise writes go through `_assign!`/`@_assign!`, not bare `.=`. The L²/measure reductions
   now exist (`src/Reductions.jl`, item 8) on `sum`/`dot`/`maximum` and are tolerance-tested; only
   *threading* them (custom chunk accumulation) remains deferred.
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
   `mean`/`std`/`var` (extending `Statistics`, fiber-preserving) and `maximum`/`minimum`/`extrema`
   (extending `Base`, scalar sections) — on `AbstractFiberSection`, against the base measure
   (`Grid3D` cell volume / `PointSet` counting). The measure reductions act on **physical fields +
   point-values** (representation-free); `inner`/`l2norm` (Parseval, rfft half-spectrum weighting) and
   `integral`/`mean` (the zero/DC Fourier mode, reusing `_spectral_zero_mode_data`/`_spectral_constant_scale`)
   additionally act on **spectral** fields, = the physical value with no transform. `mean(points) = (1/M)·Σ`; `inner`/`mean` are
   intensive (normalized), `integral` extensive. Physics stays consumer-side (energy `½ inner(u,u)`,
   etc.). Tested in `test/reductions.jl`; the 206/122 parity baselines are unchanged (separate
   generics). GPU-portable by construction (`sum`/`dot`/`maximum`); GPU parity covered in
   `test/gpu/suite.jl`. **`radial_spectrum` added (decision 21):** the shell-resolved Parseval inner —
   the radial power spectrum `(shells, spectrum)` with `sum(spectrum) == inner(f,f)`, spectral-only,
   device-clean via a single **scatter-add** shell-binning pass (`KernelAbstractions`/`Atomix` histogram,
   `_bin_by_shell`; decision 25 — replaced the O(N) per-shell masked reductions that wedged a 12 GB card
   at 256³ under the GPU GC). **`radial_correlation` added (decision 22, Phase 1):**
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
   kernel-multiplier family — periodic (circular) convolution of a field with a kernel, in spectral
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
   (annular band-pass, `spectral_cutoff = band(0,k)`) and `squared_wavenumber_field` (the `|k|²`
   radial coordinate consumers build symbols from); together with `radial_spectrum` (item 8) they
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
   whole-cell shift. Consumer: phase-shift de-aliasing.

## Planned directions (recorded — not started)

The package is feature-complete for its core mission. Recorded next steps, in priority order:

- **Spectral-domain transfer (decision 23) — DONE.** Both schemes shipped natively (no dependency)
  under `AbstractTransferScheme`: `DirectDFT` (exact `O(NM)` + the oracle) and the fast windowed
  `NUFFT` (`O(N log N + M)` gridding = spread→FFT→deconvolve, reusing the transfer kernels + oversampled
  plans + an `assignment_window`-style deconvolution), validated against `DirectDFT` to ε on the
  resolved sub-Nyquist band. **Future:** lift the Nyquist projection (lossless rfft Nyquist split in the
  zero-pad) if an exact-at-Nyquist consumer ever needs it.
- **van Hinsberg global B-spline — still needs a design discussion before coding** (`docs/ARCHITECTURE.md`
  §10, decision 17): a coefficient pre-transform + compact stencil (higher accuracy, but a global solve
  that breaks "single representation", so it needs a coefficient-field type + transform step).
- **Deferred until a consumer makes them concrete** (the §2 rule against speculative structure):
  the fused **quadratic-form reduction** `⟨v,A·v⟩ = mean(v_i A_ij v_j)` (a bilinear reduction; the IT
  request flagged it "for completeness of the fused-reduction set", its win a single vector intermediate at
  diagnostic cadence, its consumer — enstrophy production `⟨ω·S·ω⟩` — not yet live; a small add on the
  existing `inner` machinery when it lands; decision 27); anisotropic / tensor-valued radial spectra
  `E_ij(κ)` + the Craya–Herring longitudinal/transverse
  split (shear-flow anisotropy diagnostics); higher positive-B-spline / signed-kernel RDF windows +
  interlacing; matrix-valued convolution kernels; threaded reductions. Shear-flow support (Rogallo
  time-dependent multipliers + remeshing) stays consumer-side.

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
  committing a code change, run the full test matrix locally on **both** Julia versions
  (1.11 and release, via juliaup) — `Pkg.test()` plus the GPU suite where a device change
  warrants it; a docstring/doc/example-only change needs only a load + the relevant doc
  build. Docs still deploy on push. (Sub-environment `Manifest`s under `docs/`, `test/gpu/*`,
  `benchmark/*` are gitignored and go stale locally when package deps change — `Pkg.resolve`
  that env if precompile breaks; CI is unaffected.) **The two CPU lanes need a per-version
  resolve locally:** the gitignored top-level `Manifest.toml` is Julia-version-specific, so a
  1.12-resolved manifest makes `julia +1.11 … Pkg.test()` error immediately (`manifest generated
  by a different version of Julia`) — move/clear `Manifest.toml` so 1.11 resolves fresh, then
  restore the 1.12 one (CI is unaffected: each matrix job resolves from scratch on a clean checkout).
