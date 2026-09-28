!!! info "Written by AI, not regularly reviewed"
    This page is written by AI and is not reviewed regularly by a human.

# Decision log — GBGPeriodicFields

*Chronological and append-only.* Each entry records a decision, what it replaced, and the evidence
that settled it; a later entry supersedes an earlier one's "remaining" or "deferred" note rather
than contradicting it. An entry may use notation the architecture or an earlier entry introduced.

This log lived as §13 of [the architecture](@ref "Architecture — GBGPeriodicFields") until
2026-09-19, where it was three quarters of that file and pushed the design it documents into the
last quarter. It is cited throughout the package as "decision N", and those citations are unchanged.

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
    single home for every fiberwise formula (norm/sym/skew/dev included, via `_section_scalar_type`),
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
    degree-``2n{+}1`` interpolant of all ``2n{+}2`` nodes. The smooth weights are **pinned to a tolerance
    against TurTLE's `beta_n{n}_m{m}`** (`n` ↔ `interp_neighbours`, `m` ↔ `smoothness`; the pin asserts
    ``\le`` 1e-12, `test/interpolation_transfer.jl`) — an earlier "interpolate the central ``2(n{-}m){+}2`` nodes" draft was corrected
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
      magnitude via `lpnorm` at ``p = \infty``.
    - **No LinearAlgebra overloading**: `dot`/`norm` stay the vertical pointwise ops (return sections,
      scalar fields); the global `inner`/`l2norm` are package generics returning numbers.

    `inner`/`l2norm` are representation-invariant (Parseval): the physical reductions came first, and the
    **spectral `inner`/`l2norm` are now implemented** — for two fields in spectral representation
    ``\texttt{inner}(\hat f, \hat g)`` equals the physical inner via the rfft half-spectrum Parseval weighting (each mode
    counts twice except those on the ``k_x=0`` plane and, for even ``N_x``, the Nyquist plane — the planes the
    rfft maps to themselves under conjugation, whose partners are already stored, so they count once), computed
    as a `dot` over the array plus a plane correction per self-conjugate plane — allocation-free in the
    `inner(f, f)`/`l2norm` case, while the mixed `inner(f, g)` materializes those planes: the folded
    axis's zero plane always, and its Nyquist plane as well when that axis has even length, so an odd
    folded axis pays for one and an even one for two (decision 26). The `integral` and `mean` reductions are
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
    (``m \in L^\infty``); `gradient`/`curl`/`laplacian` are the **unbounded** multipliers (symbols ``\mathrm{i}a``, ``-|k|^2 \notin L^\infty``),
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
    stay consumer-side: the energy spectrum ``E(\kappa) = \tfrac{1}{2} \texttt{radial\_spectrum}``, the integral/Taylor scales from
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
    band** — exactly the band a spectral solver uses (de-aliasing, or any natural spectral
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
    [`GBGHomogeneousTurbulence`](https://grigorysarnitsky.github.io/GBGHomogeneousTurbulence.jl) (a thin
    physics solver built on this field layer) asked the package to absorb
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
      ``\langle f, w g\rangle = \tfrac{1}{N^2}\sum_{\text{stored }k} \alpha(k) w(k)\sum_c \mathrm{Re}(\hat f_c 
      \overline{\hat g_c})`` (with ``\alpha(k)`` the rfft half-spectrum Parseval weight — a fixed
      per-mode function, distinct from the scalar accumulation weight ``\alpha`` of `combine!` above —
      ``N`` the grid-point count, and ``c`` the fiber index) — the field ``g`` filtered by ``w`` and paired with ``f`` in one
      fused pass with no filtered field materialized. It is the **reduction-dual of `convolve`** (apply a
      spectral symbol, then reduce) and generalizes `inner` (the ``w \equiv 1`` case); ``w = |k|^2`` gives the
      ``H^1``/Dirichlet energy ``\langle f, -\Delta g\rangle``. Spectral representation only, like the
      Parseval `inner`. The consumer formed in-band energy every step as `convolve!` into scratch then
      `inner`; the fused form removes that scratch field.

    *The deferral.* A fifth request, a quadratic-form reduction ``\langle v, A v\rangle =
    \texttt{mean}(v_i A_{ij} v_j)`` (a vector field ``v`` contracted through a second-order tensor field
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
    The sibling consumer `GBGHomogeneousTurbulence` asked for a fifth kernel builder: the multiplier that
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
    consumer [`GBGStreamingStatistics`](https://grigorysarnitsky.github.io/GBGStreamingStatistics.jl) ships `write_histogram` / `read_histogram` to persist its durable
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
    `GBGHomogeneousTurbulence` audited its memory and found a recurring shape: to average a nonlinear
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
    declaring `julia = "1.11"` — `GBGHomogeneousTurbulence` does — must be bumped in step, or they claim
    support for a Julia their dependency no longer builds on.

32. **The one-pass Helmholtz kernel, and a convolution fused into the projection and the divergence
    (the operator ∘ kernel family).** Two requests from the consumer package `GBGHomogeneousTurbulence`
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
    ``\mathrm{i} a \cdot`` for the divergence — so "operator then convolve" is itself one Fourier
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
    requests from `GBGHomogeneousTurbulence`'s audits — items 2 and 7 — landed as one broadcast-builder
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
    consumed them (measured 1.6 of the consuming solver `GBGHomogeneousTurbulence`'s units at ``256^3``, reproduced here; the cross-power form
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
    the counterparty's standing reservation.** The 2026-07 audit exchange with `GBGHomogeneousTurbulence`
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

    *Method — measured, not transcribed.* the consuming solver `GBGHomogeneousTurbulence`'s compute audit (its decision 34) freezes an
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
    finding-(k) mode-loop hoist. The `dev!` operation stopped materializing its trace (now a per-element
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
    `weighted_inner` stayed serial at the time of this decision — its coefficient being the lazy
    cartesian ``|k|^2``, the finding-(k) class — and was moved onto this same fixed tree on
    2026-08-30 (PERFORMANCE.md finding (ac)), so the deferral recorded here is discharged. Measured honestly on the
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
    coincided with the fold on every tested path. The suite's `test/reductions.jl` now runs the Parseval, shell,
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

44. **The section allocators become public: `similar_field` and `similar_point_values`** (decided
    2026-07-24; a `/check-consistency` panel finding). Both build a section carrying a reference's
    representation, tensor order, base grid and storage backend — the allocation a consumer needs for
    the scratch an in-place loop writes into — yet both were documented as Internal API, under a
    heading stating they are not public. The evidence that this was a gap rather than a boundary is
    the flagship example: `examples/HIST_CPU.jl`, which exists to show how a real consumer writes
    against the package, hand-rolled the equivalent thirteen times in `make_workspace`, spelling out
    `field_spectral_shape`, `zeros`, an element type and a concrete field constructor for each scratch
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
    base point and *writes a section*, where a mapped `mean` reduces it. It reuses the `_fiberwise_pass!`
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
    \langle f\rangle^2 = N^{-2}\sum_{\text{stored }k \ne 0} \alpha(k) |\hat f_k|^2`` (the fluctuation energy, with
    ``\alpha(k)`` the rfft half-spectrum multiplicity and the ``N^{-2}`` the normalization the inner
    product itself carries; that displayed form is the **population** moment — `corrected = false` —
    and `var`'s default `corrected = true` returns it scaled by ``N/(N-1)``), both terms already
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
    so an order-4 result has nowhere to be built. The `cov` reduction is therefore defined on **vector** sections
    alone, which is where its consumer is).

    So `var`/`std` are now **scalar-only** — the one representation where each is unambiguous — physical
    *and* spectral (the Parseval form, equal to the physical value; the spectral one-pass loses precision
    to cancellation when the mean dominates its fluctuations, which the docstring notes). A vector or
    tensor section raises a clear error pointing to `cov`. The new **`cov`** (extending `Statistics.cov`; not
    re-exported at the time, like `mean`/`var`/`std` — all four have been re-exported by the umbrella
    since 2026-08-13, per the naming rule's export policy in §2) returns the symmetric covariance `FiberTensor2` of a
    vector section — its diagonal the per-component variances (the normal stresses, in a turbulence
    reading), its off-diagonal the covariances (the shear stresses) a per-component `var` discarded —
    computed in one fused mapped pass as ``\texttt{mean}(u \otimes u) - \bar u \otimes \bar u``
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
    decision 35 recorded and the consuming solver `GBGHomogeneousTurbulence`'s `lazy-per-mode-symbols.md` requested. The builders `spectral_cutoff` and
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
    reductions, `map` and the decompositions serve ``R \le 2``; storage, HDF5 persistence, the vector-space
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
    that case guard-free after measurement. **(FALSE, per decision 59: the target ``(i,j)`` and source
    ``(j,i)`` views select disjoint memory, so `mightalias` is `false` and would not reject the call.
    No guard is still the right answer, for decision 59's different reason. Marked here because this
    belief deferred the defect for a day.)** Rather than ship a check that might break a measured,
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
    user-directed). The reduction `weighted_inner(f, g, w)` — the multiplier-weighted inner product
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

    **The interface is [`Adapt.jl`](https://github.com/JuliaGPU/Adapt.jl)'s `adapt`.** `Adapt` exists for exactly this — take a struct holding
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
    origin as `NTuple{3, T}` and a field demands its grid share its element type, so changing
    precision must rebuild the grid, where changing storage touches only the array. It remains recorded
    future work.

    **Transform plans are rebuilt, and they need nothing from the caller.** An FFT plan is bound to its
    backend and cannot be moved. It was first thought that adapting one would have to refuse and send
    the user to the constructor — wrong, and the question that exposed it was whether a plan requires
    both representations. It does not: the constructor reads no data, only shape, element type and
    family, and a plan **outlives the arrays it was planned against** (verified on FFTW and cuFFT). A
    `FieldTransformPlans` stores its own grid and layout and carries `T` (its element type) as a type
    parameter, so it can allocate its own witnesses, plan, and release them. (It also carried `R`, its
    tensor order, when this was written; **decision 76 removed it** — a transform is a property of the
    base, so one plan pair now serves every rank and the rebuild uses order-0 witnesses.) The struct now also records the planner
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
    `GBGHomogeneousTurbulence` ("IT") in its third request round). The
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

67. **`Base.similar` is declined for the section allocators** (2026-08-15, user-decided, from the same
    panel round). A hat observed that `similar_field` and `similar_point_values` do what `Base.similar`
    exists to do for an array-like wrapper — build compatible uninitialized storage from a reference —
    and that no rationale for declining it was recorded anywhere, unlike the explicit "we own the
    types, so extending is not piracy" note that justifies extending `dot`, `cross` and `mean`. The
    observation is fair; the conclusion does not follow, and the names stay.

    **The second argument is the problem.** `Base.similar`'s four canonical forms are `similar(A)`,
    `similar(A, ::Type{T})`, `similar(A, dims)` and `similar(A, ::Type{T}, dims)`: that positional
    slot means an element type or a set of dimensions. Here it means the **tensor order**, carried as
    a `Val{R}`, which is neither. Borrowing a name while breaking the convention that gives the name
    its meaning is worse than a distinct name, which promises nothing.

    **And its most idiomatic spelling would be a trap.** `similar(A, T)` is *the* way a Julia
    programmer changes element type, while changing element type is exactly what this package must
    never do implicitly — invariant 14 refuses a mixed-precision pair rather than promoting it, and
    decision 63 excluded precision from `adapt` for the same reason. So `similar(u, Float32)` would
    read as a request for single precision, which is the one operation the design refuses to perform
    quietly, and the better the reader knows Julia the more likely they are to write it. It is not
    even a storage-level operation: `Grid3D{T}` holds the domain size, spacing and origin at the
    element type, so a precision change rebuilds the grid.

    Two smaller reasons complete it. The `data` form wraps storage the caller supplies, and
    `Base.similar` never takes data, so half the family could not carry the name in any case and the
    package would end up with both spellings. And a section is not an `AbstractArray` — these types
    subtype `AbstractFiberSection{T, R}` — so `similar`'s eltype-and-dims contract cannot express the
    grid, layout, representation and tensor order that propagating is this operation's whole purpose.

    A narrow additive alternative was considered and declined with it: defining **only**
    `Base.similar(::AbstractFiberSection)`, the no-extra-argument form, which carries no semantic
    collision and would let a newcomer's reflex work while `similar(u, Float32)` failed loudly. It
    would still be a second spelling of one operation, which invariant 1 declines to add for
    convenience. The reasoning now lives on both allocators' docstrings, where a reader meets the
    name and asks the question.

68. **`adapt` keeps the canonical flag in the TYPE, not just in the value** (2026-08-17). Moving a
    `FieldSpectralMultipliers` between storage families returned an object whose last type parameter —
    decision 61's `Canonical` — inference could not resolve, and `RadialKernel` and `ProductKernel`
    inherited the imprecision through the multipliers type they carry. The rebuilt *value* was always
    right, so nothing computed a wrong answer; what was lost is the point of putting the flag in the
    type at all. Decision 61 did that so `convolve` can collapse two radial kernels over canonical
    multipliers **statically**, and a non-concrete parameter turns that back into a run-time decision
    for every kernel that has crossed the bus.

    The cause is one line: `adapt_structure` read the flag with `_is_canonical`, an ordinary `Bool`,
    and handed it to a constructor that lifts its *value* into `new{…, canonical}`. Every other
    construction passes a literal, which inference folds, so the defect existed only on the one path
    that forwards the flag from an existing object — which is exactly the path no unit test typed.
    **Binding `Canonical` in `adapt_structure`'s own signature was tried first and measured
    insufficient**: constant propagation does not reach through the constructor's length validation.
    The flag is therefore taken as `Val{Canonical}`, so it is in the type domain at the call rather
    than lifted out of a value inside `new`. Four call sites, all in `Fields`, and no method is added,
    so every parity baseline holds.

    *Verification.* `test/adapt.jl` asserts both halves for canonical and caller-supplied multipliers
    and for all three kernel classes that can carry them: that the moved object's type is unchanged,
    and that `Base.return_types(adapt, …)` is **concrete**. The value assertion alone passed
    throughout the period the type assertion would have failed, which is why the test now makes both.
    The gate moves 6523 → 6533.

    *How it was found.* Not by a test — by the exhaustive survey, and only after its adaptor-slot
    noise was cleared the same day. The finding sat under 42,336 cells reporting non-defects, which is
    the argument for repairing an instrument rather than reading around it.

69. **`adapt!` — the storage move into a destination that already exists** (2026-08-18). `adapt`
    allocates its result, and for the return trip that allocation is most of the cost: finding (x)
    measured a device-to-host move at ``5.1`` GiB/s against the ``19.0`` GiB/s the same transfer
    reaches into a destination that already exists, on the same card and the same ``256^3`` `Float64`
    field. The gap is not the bus — the outbound direction runs at ``\approx 22`` GB/s — it is that
    the return trip allocates a fresh pageable host array and pays for the pages. A consumer pulling a
    field back on any regular basis had no way to hoist that.

    *Measured into the table 2026-08-23, which sharpened the estimate.* On the return trip `adapt!` is
    **3.48–3.66×** the allocating form at ``256^3`` (both element types, scalar and vector); the first
    estimate said "about ``4\times``", from a bare-array probe. **Outbound it is a wash**
    (``1.0\times``), which is the diagnosis confirming itself — the device allocation is pooled and
    cheap, so there was never a page cost to avoid in that direction. And the gain has a **size
    threshold**: a ``128^3`` `Float64` *scalar* (16.8 MB) shows ``1.01\times`` while the *vector* on
    the same grid (50 MB) shows ``3.48\times``, consistent with the cause being page faults on fresh
    host pages, which bite only once an allocation is too large for the allocator's reused blocks.

    **The name is ours, and `copyto!` was rejected for a reason worth recording.** `Adapt.jl` has no
    in-place form — it exports `adapt`, `WrappedArray`, `parent_type`, `unwrap_type` and the
    `adapt_structure`/`adapt_storage` hooks — so `adapt!` is a package-owned verb paired with a
    re-exported one. Julia's standard verb for "into a preallocated destination" is `copyto!`, and it
    is exactly what the implementation calls on the underlying arrays; it is the wrong *public*
    spelling here because the package's only `copyto!` methods are the broadcast entry point. A
    section-to-section `copyto!` that crossed storage families would cross where
    `destination .= source` **refuses** under invariant 14 — the same two objects giving opposite
    answers under two spellings, which is the ambiguity decision 60 removed rather than one to add.

    **The signature takes no target.** `adapt(to, x)` needs one; `adapt!(destination, source)` does
    not, because the destination already *is* the target family, so the two cannot disagree.
    Everything except the family must match — element type, tensor order, grid, Fourier layout — and
    the check is `_check_adapt_target`, which is `_check_same_domain` minus its backend clause;
    reusing that check would refuse precisely the pair this verb is for. A representation mismatch has
    **no method** rather than an error, since a physical field and a spectral one are not the same
    section, and precision is not converted here for the same reason `adapt` does not convert it. A
    same-family pair is an ordinary copy rather than an error, so generic code need not ask which side
    of the bus it is on, and an aliased call is a guarded no-op.

    **Sections only, deliberately.** `adapt` also moves a `FieldSpectralMultipliers`, a spectral
    kernel and a `FieldTransformPlans`; those have no in-place spelling because they are *built*
    rather than filled — moving plans replans the transforms and a `RadialKernel` carries a closure —
    so there is no preallocated storage a destination could offer. That is an absence in invariant 1's
    sense: stated, and not to be filled in for symmetry.

    *Verification.* The gate proves everything except the crossing, which on a host-only run cannot
    exist: destination returned and filled, metadata untouched, every mismatch refused, the aliased
    no-op, and — the assertion the feature stands on — zero allocation, with the destinations built
    outside the measured call, since building one inside it measures the very allocation the operation
    exists to avoid. The crossing itself is the CUDA suite's, both directions and the point layer with
    it (373 → 382). A `test/pass_audit.jl` row pins the traffic at its ideal, one read per source
    element and one write per destination element. Benchmark rows sit beside the allocating ones in
    the `storage` class, because the comparison *is* the justification. Gate 6535 → 6574; `Fields`
    116 → 119 (`adapt!`'s two field methods and `_check_adapt_target`) and `Points` 209 → 211 (the two
    point methods), both refrozen with their reasons.

70. **The radial-symbol operators allocate nothing, not merely less than a field** (2026-08-23,
    raised by the consuming solver with a reproduction). The operators `laplacian!`, `inverse_laplacian!`,
    `divergence!` and `exponential_convolve!` each allocated **144 bytes per call**, constant in the
    grid. The cause is one line repeated: `_squared_wavenumber_broadcast` and
    `_wavenumber_broadcast_view` built their `reshape` wrappers *per invocation*, and a `reshape`
    allocates a 48-byte array header — three of them, every call. The consumer measured 1152 B per
    RK3 step and 720 B per RK2 step, byte-exact multiples of 144, which is what a per-step constant
    looks like from the outside.

    **Why the audit did not see it.** `test/allocations.jl` pinned these under `field_threshold`,
    which is deliberately generous because its job is to catch a **materialized field** — and 144 B
    passes that trivially. So the guard said "no field" while `CLAUDE.md` said "allocates nothing per
    step", and nothing in the tree could tell the two claims apart. A consumer counting bytes per step
    could. The pin is now split: serial asserts **zero**, which is the claim; the threaded lane keeps
    a bound, because `Base.Threads` allocates task state per `_assign!` that is kilobytes and
    grid-independent. Both lanes assert something, since a testset that silently skips is how this
    reappears.

    **The fix stores the orientation instead of rebuilding it.** `FieldSpectralMultipliers` gains six
    fields — each of its six vectors reshaped to `(n,1,1)`, `(1,n,1)` or `(1,1,n)` — built once in the
    constructor, aliasing the vectors rather than copying them (verified: same pointer, and a mutation
    of the vector is visible through the view). The two helpers return the stored views, and every
    caller reaches zero. The 1-D fields stay exactly as they were, because 87 sites read them — the KA
    kernels take raw vectors, `radial_spectrum` takes their `maximum`, the separable builders
    broadcast per axis — so this is additive, not a change of shape.

    **It cost six type parameters, and three sites match them positionally.** `_is_canonical`,
    `adapt_structure` (decision 68) and `Convolution`'s static collapse of two radial kernels
    (decision 61, which spells the canonical case as a trailing `true`) all broke at once when
    `Canonical` moved six places — loudly, at load. A comment at the struct now names the three, and
    both properties are re-verified: the collapse is still static and `adapt`'s inference still
    concrete.

    *One test was measuring the wrong thing and is now measuring the right one.* Decision 51's storage
    claim was asserted as `summarysize(cutoff) < 1024`, which broke at 1136. But that bound counted
    the kernel **plus the multipliers it references**, whose per-axis vectors are ``O(N)`` — a
    small-grid constant wearing the name of a property. The claim is "a closure and three references",
    so it is now asserted as exactly that: the kernel *references* the caller's multipliers rather
    than copying them, and what it adds on top of them is **152 bytes at every grid**, compared across
    two that differ by 512× in mode count.

71. **`reality_residual` — the contract the half-spectrum cannot enforce** (2026-08-23, requested by
    the consuming solver at low priority). A real field's spectrum satisfies
    ``\hat f(-k) = \overline{\hat f(k)}``, and the real-to-complex layout exploits that by storing
    only half the modes — so for most modes the redundant partner is *not stored* and cannot disagree.
    Two planes are the exception: the folded axis's zero plane, and its Nyquist plane when that axis
    has even length, are each their own mirror, so within them **both** partners are stored and the
    constraint becomes a relation a caller can break. The `reality_residual` diagnostic returns the largest
    discrepancy ``\lvert \hat f(k) - \overline{\hat f(-k)} \rvert`` over those planes, zero exactly
    when the coefficients are a real field's.

    **The gap it closes is a promise the type makes but does not guarantee.** By invariant 2 a field
    is a real physical object and the complex array is storage detail, so `ScalarFieldSpectral` *means*
    "the coefficients of a real field" — and nothing enforced the symmetry that makes it true. Every
    operation downstream is entitled to assume it and all of them keep working when it is false, which
    is why the failure shows up as spectral diagnostics quietly disagreeing with physical images. The
    consuming solver had documented the contract as far as it could: *"Coefficients written by hand
    must respect the real-field layout's conjugate symmetry — it is not checked."* This is what lets
    that sentence change.

    **It reports rather than repairs, and the repair already exists.** A physical round trip *is* the
    projection onto a real field's spectrum, since the inverse real transform is exactly that
    projector — measured: a residual of `0.728` returns to `0.0`. So a repairing verb would be an
    optimization of something reachable today, not a capability, and it would silently rewrite a
    caller's data at the one boundary where the responsibility is explicitly theirs. The check is
    ``O(N^2)`` — one or two planes — against the round trip's ``O(N^3 \log N)``. The table shows that
    shape rather than asserting it: on the CPU it runs 92 µs → 367 µs → 1.478 ms across
    ``64^3``/``128^3``/``256^3``, about fourfold per doubling, which is a plane's area; on the GPU it
    is flat at 99–104 µs over the same range, a plane being too small to be anything but launch-bound.
    The ``O(N^3)`` `inner` beside it goes 85 µs → 204 µs → 1.115 ms.

    **A second vendor and a second CPU confirm both halves of that shape** (measured 2026-08-23). The
    RX 7900 XTX is flat at 238–244 µs across ``64^3``/``128^3``/``256^3``, the same launch-bound
    plateau at a different height, and the i7-12700K grows 80 µs → 362 µs → 1.586 ms → 13.258 ms out to
    ``512^3``, fourfold per doubling as the area argument requires. The two profiles **cross**: at
    ``64^3`` the CPU is about three times faster than the AMD card, and by ``256^3`` the card is about
    six times faster than the CPU, which is what a launch-bound cost meeting an area-bound one looks
    like. A caller choosing where to run this should read the crossover rather than the peak.

    **It does not thread, and threading is not what it would need.** The i7-12700K reads 80.2 µs at one
    thread and 80.6 at eight, 1.586 ms against 1.588 at ``256^3``, and at ``512^3`` eight threads is
    9.7% *slower*; the 9800X3D is likewise flat — zero scaling on both CPUs at every grid. The pass is
    written as whole-array `reverse`, `circshift` and `maximum` over one or two planes, so it runs
    through `Base` rather than through the package's threaded assignment primitive, and it structurally
    cannot reach the fixed reduction tree, which lives in a module included after this one. But the
    binding constraint is that the pass is **allocation-bound**: it allocates ``\approx 6\times`` the
    plane bytes it reads — three temporaries over each stored plane, from the reversal, the shift, and
    materializing the difference as the reduction's argument — so a threaded reduce alone would leave
    the serial allocation in place, which is the likeliest reading of the ``512^3`` inversion. The fix
    that would work is to fuse the mirrored index into one pass, after which threading follows for
    free. That is worth doing only if the fused form is at least as fast serially, since this is an
    ``O(N^2)`` diagnostic beside the ``O(N^3 \log N)`` round trip it exists to let a caller avoid and
    the GPU, being launch-bound, gains nothing either way. Recorded as a roadmap item rather than
    settled here.

    **Two naming decisions.** It is *not* called `symmetrize!`, though that is the requester's word and
    TurTLE's precedent: the package already exports `sym`, `sym!`, `symmetric_gradient` and
    `symmetric_gradient!` for the symmetric part of a tensor's **fiber**, and reusing the word for a
    relation among **spectral** coefficients would put one name on two operations acting on different
    structures. It is named for the *reality condition* instead, which is the vocabulary
    `convolve!`'s docstring and decision 28 already use. And it does **not** zero the Nyquist planes as
    TurTLE's `symmetrize()` does: invariant 5 keeps Nyquist content deliberately, so a violation there
    is named like any other.

    *Verification.* An elementwise oracle written from the definition, sharing no code with the
    implementation — which walks whole planes with `reverse`/`circshift` so it never indexes a device
    array one element at a time, and is checked under `allowscalar(false)` in the CUDA suite. Crossed
    over both element types, tensor orders 0/1/2, permuted folds, an **odd** folded axis (one
    self-conjugate plane rather than two), the pair-consistency property (fixing the partner restores
    zero), the self-paired corners (whose residual is twice the imaginary part), and the round-trip
    repair. `Fields` 119 → 120, refrozen with its reason; the gate gains 170 assertions.

72. **Several weights, one traversal** (2026-08-23, the consuming solver's highest-value request).
    `weighted_inner(f, (w₁, …, wₙ))` returns one scalar per weight from a **single** pass over the
    coefficients. The requester's variance controller reduces the same field three times at every RK
    stage — against unity, a forced band, and ``\lvert\kappa\rvert^2`` — and it is not the
    arithmetic it pays for but the **return to the host**: each scalar is a blocking readback, nine of
    the ten synchronizations in a default run. One call is one readback.

    **The tuple is the whole design, and its spelling was not free.** A tuple carries its length in
    its type, so the return is a concrete `NTuple{n, T}` and a caller destructures it. Fusing needs an
    accumulator per weight, and the obvious spelling — `zip` the operands — **falls back to scalar
    indexing** and dies under `allowscalar(false)`; broadcasting into an `NTuple` and reducing with a
    tuple `+` stays on the device. That is measured, not assumed. In the committed table it beats the
    three calls it replaces on **every one of the ten lanes** — **1.16–2.97× on the two CPUs** (median
    ``1.33``) and **1.51–2.81× on the two GPUs** — before counting the two synchronizations that stop
    happening.

    **The CPU band was re-derived 2026-08-31; this entry's original ``1.64``–``1.97\times``
    "uniformly" is retired.** Only 4 of 64 CPU cells now fall in that band, and one row (12700K,
    ``256^3`` `Float64`) spans ``1.56`` to ``2.89\times`` across its thread lanes where it read
    ``1.71``–``1.72`` flat. Nothing about the tuple form changed: finding (ac) moved the CPU leg onto
    the threaded fixed tree, the path **both** compared rows traverse, so the ratio moved without
    either arm being touched. The decision stands — the tuple form wins every cell — but a ratio
    between two rows is not stable under a change to the path they share.

    Three things the spread says. The CPU figure sits near two rather than three because
    only the *coefficient* reads are shared: each weight is still evaluated per mode, so a third of the
    traffic was never the target. The NVIDIA card's `Float64` rows are its weakest (1.36× at ``256^3``
    against 1.96× for `Float32`), which is what a consumer card doing double precision at 1/64 rate
    looks like — compute-bound work has less to gain from reading less. And the AMD card does **not**
    show that split (1.86× against 2.48× at ``256^3``, and its best figures anywhere), which is the
    same explanation seen from the other side rather than a second one.

    **The AMD figures were measured 2026-08-23, and the vendor risk they were checking did not
    materialize.** A tuple accumulator reduced with a custom non-`+` operator is a different AMDGPU
    code path from `sum` or `mapreduce`, and decision 62 had already found one place where that
    vendor's `mapreducedim!` throws on a `Broadcasted` the CPU accepts — so no CUDA run could speak
    for this one. It neither threw nor fell back: the ROCm suite reads 395 of 395, the same count as
    CUDA, and the operation turns in its largest speedups of any lane. The `Base.Broadcast.instantiate`
    that decision 62 made load-bearing is still what makes that true, and remains required.

    **It is one method on the existing generic, not a new operation.** ``\langle f, w f\rangle`` at
    several weights is the same mathematics at several ``w``, so invariant 1 is satisfied by extending
    `weighted_inner` rather than naming something new; a variadic form was declined because
    `weighted_inner(f, w₁, w₂)` sits too close to the two-field `weighted_inner(f, g, w)` for a reader
    to separate at a glance, where a tuple says *these are weights* structurally. The **two-field**
    generalization ``\langle f, w g\rangle`` at several weights is deliberately absent: no consumer
    asked, and invariant 1 does not add combinations for completeness. Every refusal the single-weight
    form makes is made here in any position — a complex multiplier, a foreign context — and an empty
    tuple returns `()` without touching the field.

    **Fusion is exact, and one thing a consumer will notice is not.** The fused result is **bitwise
    identical** to the separate calls, same arithmetic in the same order with only the pass shared.
    But `inner(f, f)` and `weighted_inner(f, unit)` differ in the last ulps — ``1.1\times10^{-14}``
    relative, measured — because `inner` reduces on the threaded fixed tree and this pass does not.
    That difference is **pre-existing** and belongs to the two routes, not to fusing; it is recorded
    because a consumer replacing `inner(f, f)` with the unit-weight entry will see it and should know
    which of the two it came from.

    **The stronger form the request floated — a device-resident scalar pack that `convolve!` accepts
    as a coefficient source — is declined**, on a concrete cost rather than a principle. The
    requester's own arithmetic between the reduction and the use is
    ``A = (\varepsilon - R)/(2k_f)`` guarded by an emptiness test: a division **and a branch**.
    Keeping the scalars on the device would require ``\alpha`` to accept a device handle across every
    α/β signature in the package (invariant 10's contract, dozens of methods) *and* the consumer to
    run a device-side select — the package dictating where a consumer's formula executes, which is
    invariant 12's line. It is also diminishing: the tuple form already takes that run from ten
    crossings to four, and the remaining three are one per stage.

    *Verification.* 344 gate assertions: fused bitwise-equal to the separate calls for every ``n`` from
    1 to 5 over a **heterogeneous** tuple holding one weight of each storage class, both element types,
    tensor orders 0/1/2, permuted folds; the order property (reversing the weights reverses the results
    and nothing else, which is the guard against accumulating into the wrong slot); `@inferred` for the
    concrete `NTuple`; both refusals in any position; the empty tuple; and the `inner` agreement at its
    honest tolerance. On device, values match both the separate device calls and the host, under
    `allowscalar(false)`. Pinned allocation-light beside the single-weight row, with a benchmark pair —
    fused against three separate — because that comparison is the claim. `Reductions` 123 → 124.

73. **Base-space motion: `displace!` and `wrap!` — the exponential map of the flat torus, and the
    canonical representative** (2026-08-24, requested by the consuming solver). The solver's
    Lagrangian layer routed every field *sampling* through the point layer but performed every
    trajectory *update* by unwrapping storage and broadcasting on raw arrays — the only raw-array
    arithmetic on point-typed data in its tree — because moving the base is not expressible in the
    fiberwise algebra, which by design maps sections to sections and never moves a point. The gap is
    real and the operation is canonical: on a flat periodic base whose fiber carries one global
    orthonormal frame, the tangent space at every base point is canonically the Cartesian
    ``\mathbb R^3`` of the fiber, so displacing a point ``x_p`` along vector values ``v_j(p)`` held
    over it, each section scaled by one real number ``c_j``, is exactly ``x_p \leftarrow x_p + \sum_j c_j
    v_j(p)`` — the exponential map of the flat metric, which carries a point along a vector and on
    a flat torus is plain addition, needing no connection choices. The design
    facts, each argued from that geometry:
    - **A named verb, never `+`.** Positions are points of the domain manifold, not vectors; an
      algebra on `PointSet` would assert a linear structure the base does not have. The verb `displace!` is
      the one operation that legitimately couples base and fiber, and it crosses the
      position-versus-value role split by name rather than dissolving it.
    - **The grid argument selects cover or torus, and the type structure forces that split.** A
      `PointSet` carries no grid (a deliberate absence recorded on its docstring), so the grid-free
      arity *cannot* wrap: it is displacement in the universal cover — the unwrapped torus, where a
      coordinate keeps growing instead of folding back — which preserves winding — a
      mean-square-displacement diagnostic needs exactly that. The arity taking a `Grid3D` is
      displacement on the torus proper: the reduction to the fundamental domain is fused into the
      same pass, not a second traversal. Only `domain_size` and `origin` enter; the mesh plays no
      role.
    - **`wrap!` owns the periodic-box subtleties once.** The canonical representative lands in the
      half-open ``[o_a, o_a + L_a)`` per axis — **origin-aware**, which the consumer's own
      four-line wrap was not (`mod(X, L)` assumes a zero origin) — with the excluded endpoint
      folded explicitly (floating-point `mod` can return the period itself: `mod(-1e-20, 2π) ===
      2π`, a pinned test), and the fold testing equality rather than order so a non-finite
      coordinate passes through non-finite — an `x < L` test is false for `NaN` and would silently
      rewrite a diverged trajectory into a tidy in-box position. The `mod` function maps an infinity to `NaN`,
      so divergence survives as non-finiteness, though not as the same non-finite value.
    - **Sampling needs no wrap, and that is now a documented contract with an honest limit.** The
      transfer kernels wrap their stencil indices, so interpolation is invariant under shifting a
      coordinate by whole periods (tested, at tolerance — the invariance is exact in exact
      arithmetic and floating-close in practice). It is not "any finite coordinate": at extreme
      magnitudes the cell-index arithmetic leaves its exact range, and absolute floating-point
      resolution degrades as coordinates grow — single precision especially — which is why regular
      canonicalization is load-bearing on a long run rather than presentation-layer hygiene.
    - **The coefficients are the operation's definition, not α/β.** As with `combine!` (the
      recorded invariant-10 exception class), the ``c_j`` scale the operands of what the operation
      *is*; no trailing α/β pair exists or may be added (the glyph-collision rule).
    - **In-place only, one fused traversal.** There is no allocating sibling — displacement is
      motion of an existing base, and a fresh-`PointSet` variant has no consumer (invariant 1). The
      ``n``-term form reads the positions once, each section once, and writes once, collapsing a
      ``K``-term Adams–Bashforth combination from ``K`` broadcast passes to one; the destination
      may be the source (the fused pass reads an element's inputs before writing its outputs,
      invariant 9), and a separate destination form serves the predictor step that writes
      ``X^\ast`` beside ``X``.
    - **Implementation shape.** The pass is `_assign!`-routed (threaded on CPU, `materialize!` on
      device, bitwise thread-count-invariant), built by recursion over the term tuple rather than
      by closures — a closure capturing the element type heap-allocates itself, and an unbounded
      forwarded `Vararg` is not specialized, both measured before the recursive spelling brought
      every arity to zero bytes. The torus arity runs column-wise so each axis sees its extent and
      origin as plain scalars; the columns are contiguous (SoA), so traffic is still one traversal.
    - **Refusals are the package's decision** (invariant 14): point count, scalar type and storage
      family are checked explicitly against the destination — the torus path bypasses the broadcast
      machinery's own enforcement, and a `Grid3D` is checked as the non-section partner it is.
    - **Verification.** An independent raw-array oracle over both element types; the fused torus
      arity bitwise-equal to cover-then-`wrap!`; the endpoint, non-finite and origin contracts each
      pinned by name; GPU parity exact on both arities plus the mixed-family refusals; zero-byte
      allocation rows for every arity; exact traffic rows (the torus row's counts identical to the
      cover row's — the fused wrap measured free); four benchmark rows in the `transfer` class.
      `Points` 211 → 226 (five public methods, ten internal), the field surface untouched.

74. **Allocation from context: the constructors accept a storage family** (2026-08-24, requested by
    the consuming solver). Every route to field storage required an existing value in hand: the six
    concrete constructors take a storage array the caller must already have produced on the right
    backend, and `similar_field` (decision 44) copies its context from a reference field. A consumer
    whose domain frame deliberately owns **no** field-sized arrays — the design this package's own
    lazy kernels enable, and which the solver's memory ledger now *asserts* — therefore had no
    sanctioned route to its first field, and was reading a multipliers axis vector as a
    backend-and-element-type witness for a raw `Base.similar`, reproducing the package's
    shape-and-backend logic outside the package.
    - **The surface is the constructors, not a new verb.** The request framed the need as "the
      reference-free completion of the `similar_field` family", but `similar_field`'s identity is
      allocation *from a reference* — "similar" with nothing to be similar to is a contradiction in
      the name (and `Base.similar` itself was declined for these allocators by decision 67, for
      convention reasons that would apply doubly here). What was missing is **construction from
      context**, and construction already has a home: the same six constructors now accept a storage
      *family* — `Array`, `CuArray`, `ROCArray` — in place of the array, and produce the storage
      themselves: `VectorFieldSpectral(ROCArray, grid, layout)`. No new export, no new name; the
      representation and tensor order are carried by the type name, as they always were.
    - **The element type comes from the grid.** `Grid3D{T}` already stores the domain at the field's
      element type, so the metadata list the request enumerates — grid, layout, order,
      representation, element type, backend — has one redundant entry, and the surface drops it: a
      bare family takes `T` from the grid, a parameterized `Array{Float32}` must agree with the grid
      or is refused (invariant 14, refusal over conversion), and a complex parameter is refused
      always — the field's element type is its real scalar type, spectral storage being a
      representation detail allocated as `Complex{T}` internally (invariant 2).
    - **The backend is a generic array type**, the decision-63 argument verbatim: dispatching on a
      generic target gains both vendors without depending on either, and the family is reduced to
      its unparameterized wrapper (the `_storage_family` comparison in reverse) before the storage
      is produced.
    - **The storage is uninitialized**, exactly as `similar_field`'s is (decision 44 records the
      same choice): zero-filling is a cost the caller may not want, and the constructor's contract
      is storage, not values.
    - **Dispatch note.** The physical types also carry a sampling constructor whose function
      argument is untyped, so `ScalarFieldPhysical(Array, grid)` would have reached it (and failed
      at call time); the family methods are typed `Type{<:AbstractArray}` and win by specificity.
      The ambiguity check guards the pair.
    - **No benchmark row, deliberately.** An allocator's cost is the backend allocator's, not the
      package's, and finding (y) records exactly what a per-call field-sized allocation does to a
      benchmark row: it lands in a process-history-selected regime and stops being comparable
      across process shapes. A row would measure the harness's memory history, not the operation.
    - **Verification.** Every allocated field is type-identical to its data-built twin and to
      `similar_field` of that twin, over both element types, two layout folds (the decision-48
      metadata trap — layout, grid and origin must survive any operation that allocates), the
      default-layout arity, orders through ``R = 4``, and a physical round trip through freshly
      allocated scratch; both refusals; on device, allocation directly on the vendor family with a
      reduction and both refusals exercised (`test/gpu/suite.jl`). `Fields` 120 → 122 (the two
      helpers; the sixteen constructor methods are Type methods the per-function count does not
      see). The consumer deletes its `_reference`/`_blank` pair, and no code of its reads a
      multipliers field for any purpose but wavenumbers.

75. **Transfer schemes persist, because a scheme *is* its parameters** (2026-08-24, requested by the
    consuming solver). The HDF5 extension persisted the ten section classes and nothing else, so a
    consumer restoring a tracer set — positions, values, *and the scheme that samples with them* —
    had one leaf it could not reach through the package. Writing the tags itself would have put this
    package's type names, outside this package's schema version, in a second package: the drift
    argument that carried decision 74, one layer up.
    - **The line is drawn by what an object *is*, not by which types were asked for.** A
      `LalescuSpline` stores `neighbours`, `smoothness` and a weight `SMatrix` — but the matrix is
      **derived**, recomputed by the constructor from ``(n, m)``. So the faithful record is the
      parameters, and storing the weights would duplicate derived data, the very thing the
      consumer's checkpoint design avoids everywhere else. `LagrangeSpline` is the same with one
      parameter, and `DirectDFT` is the degenerate case: a singleton whose tag is its whole record.
      It is covered although nobody asked, because that makes the HDF5-persisted class *"a scheme that is
      its parameters"* rather than *"the two the consumer named"*.
    - **`NUFFT` is refused, and the refusal is a statement about the object.** It owns oversampled
      FFT plans and a deconvolution window built against a particular reference field. That is a
      compiled schedule, the same kind of object as `FieldTransformPlans`, which decision 63 likewise
      **rebuilds rather than moves** when storage families change. A stored NUFFT would be either a
      large duplicate of derived data or a parameter set pretending to be the object; the consumer
      rebuilds it from the reference field it restores anyway. The error says so and names the
      rebuild.
    - **The group has attributes and no `data`.** Every other object written to HDF5 is a section and its
      group is built around an array; a scheme's is not, which is the shape difference worth naming
      rather than smoothing over.
    - **The element type is resolved through a closed table, never `eval`.** Reconstruction needs the
      weight element type back from the string `"Float64"`, and the obvious spelling — parse and
      evaluate — would execute an arbitrary expression out of a file this package did not write. The
      mapping is a two-entry `Dict` and anything else is refused.
    - **Reading revalidates rather than trusts.** The parameters go back through the ordinary
      constructor, so a group asserting an impossible combination (``m > 2n``) throws there instead
      of yielding a malformed scheme, and the group's schema version, type tag, and required
      attributes are each checked.
    - **An adjacent defect, found and fixed in the same change.** The extension's header has always
      claimed its self-describing attributes are "CHECKED, not merely written", and for `read_field`
      they were — but **`read_points` never checked its schema version**, so a point group written by
      a newer version was silently accepted. The version gate is now one shared helper applied by all
      three read verbs, and the header's claim is true for the first time.
    - **Definition of done, with two reasoned exemptions.** No GPU parity lane: a scheme is a
      host-side parameter record, and the persistence layer returns host objects by construction, so
      there is nothing for a device to disagree about. No benchmark row: the operation writes four
      attributes, and there is no HDF5 benchmark class to put it in — inventing one to time a
      constant would measure the library, not the package.
    - **Verification.** Round trips over nine schemes — both spline families across the parameter
      region including the ``m = 2n`` boundary and the ``n = m = 0`` corner, both element types, the
      `CatmullRom` alias (which needs no identity of its own: it *is* `LalescuSpline(1, 1)` and
      returns egal to it), `DirectDFT`, and the `parent[name] = scheme` sugar — asserted with `===`,
      the strongest available equality, and reinforced by a behavioural check that a read scheme
      interpolates **bitwise** identically, so the test still bites if a scheme ever gains state that
      egality sees and the stored parameters do not determine. Eight malformed-group paths each
      refused for their own reason, the `NUFFT` refusal on both the verb and the sugar, and a
      **completeness guard** walking every concrete `AbstractTransferScheme` subtype and requiring it
      to round-trip or be a recorded refusal — verified by perturbation (dropping one scheme fails
      it), so a future scheme family cannot ship silently unpersistable.

76. **The transform plans carry no tensor order** (2026-08-26, prompted by a residency request from
    the consuming solver `GBGHomogeneousTurbulence` ("IT")). `FieldTransformPlans` was parameterized on
    the tensor order ``R``, and built one plan pair per rank: a scalar field, a vector field and a
    second-order tensor field each needed their own. That was never a recorded decision — it was the
    shape the original construction happened to take — and it is a **category error** in the terms
    §2 already sets out. A real Fourier transform on a periodic box is defined **on the box**; a
    rank-``R`` field is that transform applied along a fiber. The transform is therefore horizontal,
    a property of the base, and ``R`` is vertical, a property of the fiber. Encoding the second
    inside the first is the same defect the documentation rules name elsewhere as "a vector space
    equated with an integer".

    **What it cost, in a currency the package does not itself pay.** On a GPU backend the wrapper
    behind `plan_rfft` allocates a device array per plan, sized to the coefficients that plan
    transforms. Per-rank plans therefore multiply that array by the rank: IT measured 516 MiB of plan
    residency against 1158 MiB of working arrays at ``256^3`` in single precision, with a further
    1161 MiB once a nine-component diagnostic is enabled. The package holds no plans of its own, so
    the saving accrues entirely to consumers — but the **arrangement** that causes it is the
    package's, and so is the fix.

    **One pair now serves every rank.** The plans are built for a single component (the tensor-order
    zero shapes), and each transform applies them once per component over contiguous component views,
    which the fiber-last layout of invariant 3 makes possible: a component of a rank-``R`` field is a
    contiguous block, exposed by one reshape. `FieldTransformPlans{T, PF, PI, G, L, S}` no longer
    names ``R``, the transform generics no longer match on it, and the compatibility check was
    already rank-free — it compares grid and layout, which is exactly what a base-level object should
    match on (decision 56's context protocol).

    **The measured cost is nil or negative ON THE HOST, which is why this could be taken at all —
    and the device was not measured then.** PERFORMANCE.md findings (aj) and (al) later measured
    it on both vendors: the per-component loop costs ``1.11``–``1.61\times`` on a device vector
    transform at ``64^3`` and is flat or faster at every larger grid, so the host verdict below
    stands and is not a claim about a GPU. Holding
    planner effort fixed — and that qualifier is load-bearing, see finding (z) and below — a
    single-component plan runs at ``0.98``–``1.04`` of the batched plan at one thread and
    ``0.72``–``1.13`` at eight, i.e. free at ``t1`` and a **10–28% win at ``256^3`` on eight
    threads**, which is the regime decision 37 names as the CPU tuning target. IT reports the same
    direction on its own harness.

    **The obstacle, and why it does not become a restriction.** A component of a rank-``R`` field
    begins at element offset ``(c-1) \prod N_a``, and a transform library may refuse a pointer whose
    alignment differs from the one it planned for. The two backends ask different questions, so the
    package answers them differently and `_component_offsets_align` reports both. `FFTW` records an
    alignment *class* for the real and the complex array alike; the answer there is to plan with
    `FFTW.UNALIGNED`, which costs no memory and, measured, 2–65% of throughput — paid only by grids
    that need it, and no production grid does. The `cuFFT` library needs only the real pointer aligned to its
    complex element, which reduces to the real component stride being even, i.e. to the grid **not
    being odd on all three axes**; a device has no `UNALIGNED` flag, so such a grid transforms
    through a component-sized buffer instead. Both answers are chosen once, at construction, from the
    grid alone. **No grid is refused**, which was the alternative considered and declined: every
    other absence in the package encodes mathematics (invariant 1), whereas "no grid with three odd
    axes" would have encoded a pointer-alignment rule, and the ``\mathrm{odd}`` axes are what
    invariant 5's even/odd Nyquist split is tested against.

    **A measurement trap that nearly reversed the conclusion, recorded because it is cheap to repeat.**
    `FFTW_MEASURE` is `0`, so passing `flags = FFTW.UNALIGNED` **replaces** the default rather than
    adding to it and silently selects `MEASURE`. A first pass read `UNALIGNED` as up to ``4.3\times``
    *faster*; it was comparing planner efforts, not plan shapes. The constructor therefore composes
    the flag onto the caller's request (`requested | FFTW.UNALIGNED`) rather than replacing it. A
    second pass had one plan of six left on `ESTIMATE` by an incomplete edit, which read as a
    ``4.6\times`` penalty for the very variant under test. Vary one thing at a time; this is the
    third and fourth instance the performance notes record.

    **A finding that fell out of it and is worth more than this decision.** Under `ESTIMATE`, which
    is what the package plans with by default, a ``256^3`` `Float32` forward transform measures
    **513 ms** against `Float64`'s **496 ms** — single precision should be roughly twice as fast, not
    equal. Under `MEASURE` the same two cells read **108 ms** and **180 ms**. That is a factor of
    ``4.7`` left on the floor by the default planner effort, it is independent of everything above,
    and it belongs to `PERFORMANCE.md` finding (h)'s territory rather than to this entry.

77. **The inverse curl — `curl` inverted on the solenoidal subspace** (2026-08-28, user-requested).
    `inverse_curl!`/`inverse_curl` recover the divergence-free vector field ``u`` whose curl is a
    given ``w``, as one coefficientwise pass ``\hat u = \mathrm{i} a\times\hat w/\lvert a\rvert^{2}``
    with ``a`` the derivative wavenumbers of invariant 5 and the ``k = 0`` mode written zero.

    - **Why it is well posed, and what the choice costs.** ``\nabla\times u = w`` fixes ``u`` only up
      to a gradient, since ``\nabla\times\nabla\phi = 0``; this returns the representative that is
      itself divergence-free, which is the *gauge* the operator picks and the one a velocity field
      satisfies. It also needs a solvable right-hand side — a curl is divergence-free, so
      ``\nabla\cdot w = 0`` is a condition on the input, and a violating ``w`` has its longitudinal
      part annihilated rather than reported. That mirrors `inverse_laplacian`, which likewise
      projects a non-mean-free input onto the compatible part instead of refusing it.
    - **Both wavenumber families would give the same answer sub-Nyquist; only one is exact.** The
      numerator and the denominator are built from the SAME derivative family, so
      ``(\nabla\times)^{-1}(\nabla\times)`` reproduces a solenoidal field exactly at every mode
      rather than only on the resolved band — decision 42's argument, one operator over.
    - **Route.** A one-pass `KernelAbstractions` kernel with a gated CPU twin, which is what §9's
      execution-route policy prescribes for a cartesian-coefficient operator reading three components
      of a mode and writing three. It is therefore alias-safe by construction (all of a mode's reads
      precede its writes) and needs no guard temporary. The decision-47 dispatch-pair guard counted
      the new pair and the reachability probe covers it, so a stale CPU-twin arity fails at test time.
    - **Deliberate absences.** No α/β arity and no kernel-composed arity, matching `curl!` rather than
      `helmholtz_projection!`: there is no consumer for either, and invariant 1 says a combination is
      added when something needs it, not for symmetry with a neighbour.

78. **The transfer traversal order — locality as an option, and the wrap as a walk** (2026-08-30,
    user-directed). The grid↔point transfer is dominated by *where* its points read and write, not by
    the arithmetic on them, and two separate things were costing it.

    - **The problem, measured before anything was built.** A consumer holds points in the order it
      seeded them, which bears no relation to the grid, so consecutive work-items touch unrelated
      parts of the field and every stencil is a fresh set of cache misses. At a ``256^3`` grid with
      ``10^6`` points — the regime the consumer runs — visiting the same points in grid order instead
      was worth ``3.1\times`` on the device gather and ``3.8\times`` on the scatter. The signature was
      visible in the baseline before the cause was: the `Float64` gather cost ``2.0\times`` its
      `Float32` twin at ``256^3`` but only ``1.26\times`` at ``128^3``, which is a field outgrowing
      cache rather than arithmetic getting harder.

    - **An order is a TRAVERSAL ORDER, not a reordering, and that is the whole design.** `order[i]` names
      the point work-item ``i`` handles. Nothing is moved, and each point's result still lands in its
      own slot. The alternative — permuting the `PointSet` — was rejected because a consumer holds
      `PointValues` indexed alongside its points, and a permutation behind its back desynchronises
      them silently. It also makes the option **purely additive**: a keyword on the four point-indexed
      verbs, no signature changed, and a consumer that ignores it sees nothing. `GBGHomogeneousTurbulence`
      is in final development, which made that a requirement rather than a preference.

    - **The gather is bitwise invariant under any order**, because each output element is an
      independent sum; the tests assert `==`, not `isapprox`, and a *reversed* order beside the built
      one, so the invariance is of the order and not of one order. The scatter's atomic summation
      order changes, which it already does between runs (§9), so it is compared to tolerance with
      conservation asserted beside it.

    - **Validity is carried by a TYPE, after an adversarial review showed it was only asserted.** The
      first version took a bare index vector and checked its length and storage family. A vector of
      the right length that was not a permutation was accepted, and every failure it caused was
      silent: a gather left slots unwritten, so the allocating form returned uninitialised memory as
      point values; a scatter lost part of the deposited total; an out-of-range entry read and wrote
      past the end of an array inside `@inbounds`, segfaulting on CPU and corrupting quietly on
      device. The check's own error message already claimed the bijection was enforced.
      `PointTraversalOrder` now validates once, where the order is built — two reductions and a marking
      pass, the same work a per-transfer check would do but paid once — so the transfers read a field
      they can trust. Same shape as decision 59: make the property structural rather than guarded.

    - **The order is built by a counting pass, not a sort.** Three portable
      `KernelAbstractions`/`Atomix` kernels — key, histogram, place — over blocks of cells, adding no
      dependency and needing no vendor sort. It costs **0.24–0.27 ms** on device at ``256^3`` — the
      figure for the code that ships, the build itself being 0.098–0.13 ms before the permutation
      validation the adversarial review added — so it
      repays inside a single transfer; the recorded estimate it replaces guessed 12–24 transfers,
      having assumed a vendor sort, and the vendor `sortperm` over the same keys does cost
      ``25\times`` more.

    - **Morton was the recorded plan and it LOSES.** Plain lexicographic block order beat Z-order on
      every measured cell, and the literature agrees for this access pattern: Domínguez et al. (2011)
      report the same result in SPH and name the discriminator — Morton wins where cell access is
      random, lexicographic where it is a sequential sweep, which a sorted stencil transfer is. Two
      further candidates were measured and dropped: stability within a bucket changes nothing, so the
      atomic placement stands, and one bucket per cell is no better while costing ``14\times`` more to
      build.

    - **The periodic wrap became a walk.** The stencil visits consecutive nodes, so each index is its
      predecessor plus one — yet every node index came from `mod`, which LLVM shared down to 32
      integer divisions per point per fibre. `_wrap_step` replaces the division with a conditional
      zero, keeping three `mod`s per point for the starts. It is **bitwise identical to the previous
      kernel**, verified over 48 configurations including a stencil wider than the grid, where the
      walk wraps repeatedly; only the index arithmetic changed.

    - **The walk has one bad corner, and this entry has now described it wrongly twice.** It is worth
      ``1.3``–``1.9\times`` on the CPU gather up to six nodes per axis, and on the device it wins on
      CUDA (24 of 24 cells at or below ``1.002\times``) while LOSING ``1.74\times`` on the RX 7900
      XTX `CatmullRom` gather at ``256^3`` `Float64` — the "1.03–1.28x on the device throughout"
      this entry used to carry is RETRACTED by PERFORMANCE.md findings (aj) and (al). At eight
      nodes per axis it can also lose on CPU: **4–14% depending on the scheme, only from about four
      threads, and at ``R = 1`` rather than at every rank** — ``R = 2`` is less affected, and at one
      thread the walk is 17–22% FASTER. The mechanism recorded here was backwards: `mod` is the form
      that VECTORIZES (983–1588 vector instructions against the walk's 133–138) and neither variant
      spills on the host, so the CPU loss is the walk forfeiting the memory-level parallelism that
      independent indices keep. On gfx1100 the walk DOES spill for `CatmullRom` (192 VGPRs,
      occupancy halved 16 → 8), the device regression's mechanism — finding (aq). The corner is
      stated rather than fixed, decision 47 forbidding the conditional second body; finding (ad)
      carries the tables.

    - **What the two wrong versions had in common** is worth more than either correction: each was
      measured at one point of a space and written as though it held across it — first at one scheme,
      then at one thread count. The rule the package already applies to tests, that a fixture must be
      able to falsify the claim its name makes, applies to benchmarks in exactly the same way.

    - **Where it does not pay, which is why it is an option and not a default.** At ``64^3`` with
      ``10^5`` points everything is launch-bound and building an order for a single transfer loses. On
      a CPU whose cache holds the whole field there is little locality to win, and the order's own
      scattered reads of the coordinates cost more than they save. The win grows with tensor order,
      because a vector field reads three components per point against one coordinate triple.

    - **It also grows with the STENCIL, which is the axis the first sweep missed.** Across schemes of
      2, 4, 6 and 8 nodes per axis the device gather reads ``1.86``, ``3.39``, ``3.84``, ``3.69\times``
      and the CPU rises to ``6.95\times`` at the widest — a wider stencil reads more nodes per point,
      so there is more traffic for locality to save. Past ``256^3`` the schemes separate sharply: at
      ``1024^3`` the default gets ``1.21\times`` where an eight-node stencil gets ``4.29\times``. The
      option therefore matters most exactly where a run is most expensive. The measured tables are
      `docs/PERFORMANCE.md` finding (ad).

    - **The speedups are a property of the INPUT order.** Measured across seedings at ``256^3`` with
      ``10^6`` points, the same operation reads ``12\times`` for uniformly random positions and
      ``0.93\times`` for a lattice in sweep order, with the ordered arm nearly constant throughout —
      it normalises the access pattern, and what varies is how bad the baseline was. The option
      repairs a bad order rather than improving a good one, which is the honest statement of when a
      consumer should reach for it.

    - **The signature leads with the grid** (`point_traversal_order(grid, points)`), corrected 2026-08-30
      from a points-first first version: the function is TRANSFER infrastructure, so it takes the
      transfer verbs' argument order (`anterpolate(grid, points, …)`), not the motion verbs'
      trailing-grid one (`wrap!(points, grid)`) it briefly borrowed. The `tile_size` option was
      questioned the same day and KEPT on a measurement: the optimal tile tracks the backend, not
      the interpolation scheme (flat in tile on the device at stencil widths 4 and 8 alike; the CPU
      prefers coarser blocks for both), and one order serves any scheme and both directions, so a
      scheme argument would misstate both what the option controls and what the order is valid for.

    - **No cadence, per invariant 12.** An order describes where the points were when it was built. A
      consumer whose points move decides when to rebuild it; the package holds no notion of time, and
      the measured build cost is small enough that "every step" is a defensible default for a consumer
      to choose.

79. **The exponential fiber hoist — one `exp` per mode, and the routes it forced** (2026-08-30,
    user-directed; IT item 2). The exponential kernel ``\exp(c |k|^2 [+ s \hat w])`` depends on the
    mode alone, yet the broadcast route evaluated it per output element — three times per mode for a
    vector field, nine for a tensor, identical arguments each time. The consumer's codegen report
    measured that at ``\approx 3.5\times`` the shape-identical `combine!` single-threaded, and it was
    the pass audit's standing ŵ-extrusion holder.

    - **The change is BITWISE INVISIBLE, and that is the contract it was built under.** The user's
      condition was no regression of any kind, so every variant was verified bit-identical to the
      committed broadcast over 126 cells — seven arities including the aliased filtered accumulate,
      three tensor orders, both element types, odd folds — before any performance was even measured.
      Equal arguments give equal bits; only the number of `exp` EVALUATIONS changes. The scalar
      (``R = 0``) forms keep the broadcast route untouched: one component, nothing to hoist.

    - **Three CPU bodies, each forced by a measurement.** The first attempt looped the fiber
      innermost and lost 24% at ``256^3`` `Float64` `-t8` — the visit-order lesson in reverse, 3^R
      strided streams where the broadcast had one. The second buffered one x-row of factors and
      still trailed by 3–6% there, the factors being computed BEFORE the row streams rather than
      under them. The shipped body fuses the factor computation into the FIRST component's pass —
      `exp` hides under that stream exactly as it hides under the broadcast — and the remaining
      components reuse the buffer as pure streams: strictly less work than the broadcast in every
      regime. SERIALLY the bufferless body runs instead, because decision 70's lane pins this
      operator at literally zero bytes on the serial lane and a row buffer is an allocation; the
      two bodies are bitwise identical, so the split costs a comment.

    - **What it bought, measured.** CPU `-t1` (the consumer's stated pain): ``2.4``–``3.9\times``;
      `-t4` at ``256^3``: ``1.65\times``; device: ``1.3``–``2.1\times`` across every `Float64` cell.
      **What it did not: two residual cells, disclosed rather than absorbed.** `Float64` vector at
      ``256^3`` and EXACTLY eight threads on the 9800X3D reads +3–6% (the transition band where the
      field just exceeds the V-Cache and eight threads just saturate the bus while `exp` still fills
      a third of the roof — at ``512^3`` `-t8` the two routes are even to 0.7%); and the device
      `Float32` combination at ``256^3`` reads −2%, stable. Both are the price of the constraint
      being measured honestly instead of asserted.

    - **A complex ŵ found the fixture blindness.** The factor buffer was first typed real, and 126
      bitwise cells passed — every fixture held real values in complex storage, so the imaginary
      part was zero everywhere (decision 52's class, again). A true spectrum as ŵ threw
      `InexactError` where the broadcast had always computed the complex exponential; the buffer now
      takes the offset storage's element type, so decision 79 tightens no contract the broadcast
      honoured. The threading toggle keeps that fixture, at an offset scale small enough that the
      exponent stays finite — its first version overflowed `exp` and read three identical NaN
      payloads as a route mismatch.

    - **The decision-47 guard had a module-shaped blind spot, and this change found it.** The
      dispatch-pair scan named three modules, and Convolution was not one — so the two new
      `_*_modes!` pairs did not announce themselves, and neither had the THREE pre-existing pairs
      (`_separable_*_pass!` ×2, `_radial_convolution_pass!`) that had carried gated CPU loops since
      the decision-50/51 era with nothing checking their arities stayed dispatch candidates. The
      scan now includes Convolution and the frozen count is 17, with the lesson recorded where the
      count is: a frozen count only defends the modules the scan names.

    - **The ŵ-extrusion holder is retired at the fused ideal.** The pass audit measured the offset
      field's traffic drop 3M → M on the vector fixture, which is the entire fix the holder had
      priced; `test/pass_audit.jl` freezes the new ideal with the history in place.

80. **A traversal order is rebuilt in place, so a moving point set stops growing the device pool**
    (2026-09-03, user-directed). Decision 78 shipped `point_traversal_order` as an allocating builder, and
    its own docstring closed with the sentence "There is no in-place form yet". Nothing tracked that
    "yet": a consumer whose points move rebuilds, and each rebuild allocated four arrays — the
    `Int32` result, the counting sort's `Int64` bucket keys, the histogram with its exclusive prefix
    sum, and the `Bool` marks the permutation check writes — about 15 MiB at ``256^3`` with ``10^6``
    points. On a device those are freed by a collector that runs on **host** pressure and cannot see
    them, which is the failure mode invariant 13 exists to prevent, reached through a builder rather
    than through an operator.

    - **The scratch is the caller's, not the order's.** `point_traversal_order!(order, grid, points,
      scratch)` takes a `PointTraversalOrderScratch`, built once for a grid, a point count and a
      `tile_size`. Two other shapes were considered and rejected. Letting the allocating builder
      RETAIN the arrays it already allocates would have given the simpler call
      `point_traversal_order!(order, grid, points)` at no extra peak memory — but it triples what a
      build-once consumer holds, and it makes an operation's allocation depend on how its argument
      was constructed, since `PointTraversalOrder(indices)` accepts a user-supplied permutation and has no
      scratch to carry. Sizing the scratch inside the call would have defeated the purpose. The
      explicit argument follows decision 64's four-argument `to_physical!`, which is this package's
      recorded answer to the same question: when an in-place form needs working storage, the caller
      supplies it and the cost stays visible at the call site.

    - **The block layout travels with the scratch, not as a keyword.** `point_traversal_order!` takes no
      `tile_size`; it reads the block counts from the scratch it was given. A keyword would have let
      an order and its histogram disagree about how many buckets exist, which is an out-of-range
      atomic write rather than a wrong answer — the same class as the `Int32` key overflow decision
      78 records fixing.

    - **The validation survived the move.** The allocating form validates the permutation rather than
      trusting it, and the `Bool` marks it writes are one of the four arrays that accumulated. The
      check is not traded away for the allocation contract: `_validate_traversal` gained a method taking
      the caller's marks, so the in-place path runs the identical check against scratch storage.

    - **It is not zero, and the docstring does not claim zero.** Three `KernelAbstractions` launches
      and the validation's own leave about 1.2 KiB of host-side launch bookkeeping — the same class as
      the FFTW callback of `PERFORMANCE.md` §4(t). What matters is that it is **constant in the point
      count**: measured 1248 bytes at ``10^3`` points and 1312 at ``10^6``, where the allocating form
      grows from 18.9 KB to 13.0 MB. Nothing per-rebuild scales, and nothing per-rebuild is on a
      device.

    - **Renamed to `PointTraversalOrder` in the same round** (user-directed). `TransferOrder` was
      the minority spelling of its own concept: the prose said "visit order" 28 times and "transfer
      order" 7, and the API page section was already titled for the former, so the code name and the
      documentation disagreed 4:1. Worse, `order` means **tensor order** 249 times in this package,
      and the same source tree held both `order = field_tensor_order(...)` and `order =
      transfer_order(...)` — the keyword read, at the call site, as if it took a rank. And in plain
      English "transfer order" parses as an instruction to transfer, which is the wrong first reading
      for this package's audience. `Point` matches the layer's own prefix family (`PointSet`,
      `point_positions`, `point_value_tensor_order`), and "traversal" already carries the sense "one
      pass over the points" here — `displace!` documents "one fused traversal" — and is the word the
      cited reference uses, Domínguez et al. (2011) being described in §References as a cell
      **traversal order** for neighbour search. The keyword moved with the type, `order` to
      `traversal`, since leaving it would have preserved the exact ambiguity the rename removes. The
      prose moved too: "visit order" is retired so the concept keeps one name.

    - **An adversarial review (2026-09-03) found two claims the code did not keep, and both are now
      enforced rather than reworded.** `_check_point_traversal_order` refused a foreign-family order
      and told the caller to "move it with `adapt`", while no `adapt_structure` method existed — so
      Adapt's identity default handed the same order back and the caller met the identical refusal.
      And the refill's grid check tested that the scratch's block layout FITS inside the grid rather
      than agreeing with it, so a scratch built on a ``16^3`` grid was accepted for a rebuild on a
      ``32^3`` one, silently doubling the block edge while the docstring claimed the layout was
      checked. The scratch now stores its grid and the refill compares it, which also catches an
      extent or origin change that a size test never could. Both are pinned in
      `test/point_traversal_order.jl`, the `adapt` one through a probe adaptor, since adapting to the
      family an object is already in is the identity by contract and cannot distinguish a working
      method from a missing one.

    - **The memory figures moved when this decision landed, and the docstring had kept the old ones.**
      `cumsum` on an `Int32` count array widens to `Int64`, so the pre-decision path held the running
      total at twice the counts' width; the scratch allocates it with `similar`, at the same width.
      The grid-scaled storage is therefore 2 MiB rather than 3 at the default `tile_size` on a
      ``256^3`` grid, and 128 MiB rather than 192 at `tile_size = 1`. The narrowing is safe for the
      same reason the order itself is `Int32`: the running total's largest value is the point count,
      which must already fit an `Int32` index.

    - **Both forms share one build.** `_fill_traversal!` and `_traversal_tiles` are called by the allocating
      builder and the in-place one alike, so the two cannot drift into computing different orders —
      the failure decision 47 records for a device kernel and its gated CPU twin, in a different
      place. `test/point_traversal_order.jl` asserts the agreement **block-wise** rather than index-wise,
      because the scatter's atomics leave the order within a block unspecified in both forms; an
      index-wise comparison would be testing the atomics, not the operation.

81. **The traversal order's running total is threaded on the host** (2026-09-04, user-directed).
    Building a traversal order runs three `KernelAbstractions` kernels, which thread by KA's own
    partitioning, and one running total over the block counts, which did not thread at all: it was
    `cumsum!`, a serial loop on a host array. Its cost is set by the number of BLOCKS — that is, by
    the grid and `tile_size` — and not by the point count, so it does not shrink as the rest of the
    build is parallelised. Measured on a 9800X3D at ``10^6`` points with the default `tile_size`: at
    ``256^3`` it was 4% of the build at eight threads, and at ``512^3``, the grid decision 37 names as
    the CPU tuning target, **25%**.

    - **`_scan_offsets!` replaces the call, and only the host method threads.** The generic method is
      `cumsum!`, which is already a parallel scan on a device; the host method is a two-pass form —
      each chunk sums its own slice, the chunk totals are scanned serially, each chunk then writes its
      slice offset by the total before it. Below a chunk of 4096 blocks, or with threading turned off,
      it falls back to `cumsum!`. Measured end-to-end at ``512^3``: the build goes 3.41 → 2.91 ms at
      four threads and 2.85 → 2.26 ms at eight, so ``1.17``–``1.26\times``; the scan alone is
      ``2.6``–``7.3\times``.

    - **Bitwise equality is a property here, not a tolerance.** Integer addition is exact and
      associative, so regrouping the sums cannot change them and the threaded result equals `cumsum!`
      bit for bit — no fixed reduction tree of the kind decision 40 needed for floats. Pinned over
      sizes bracketing the cutoff and four distributions.

    - **The overflow contract had to be carried across deliberately.** `cumsum!` into a narrow integer
      RAISES on overflow; a scan accumulating in that same width wraps silently, and a wrapped total
      is a negative offset that the placement kernel would use as an index inside `@inbounds` — the
      class decision 78 records fixing. The chunk totals are therefore accumulated wide and the grand
      total is checked against `typemax` before the second pass. Both forms are asserted to throw.

    - **A data race in the first draft is worth recording, because reading did not catch it.** Pass
      two wrote `acc = carry[c]` where `acc` was already bound in the enclosing function scope, so
      the assignment targeted the OUTER local and every task shared one accumulator. It produced
      wrong answers and ran 50× slower than the serial loop. It surfaced only because the correctness
      harness crashed on its first mismatch; the fix is `local run = …`, and the hazard is that a name
      reused from an enclosing scope inside `Threads.@threads` is shared rather than shadowed.

82. **A section owns a field-sized array, so it needs a display** (2026-09-04, user-directed). Julia's
    default struct display prints every field, and a section's largest field is the data. A `PointSet`
    of ``10^5`` points therefore rendered as 5.6 million characters, a `NUFFT` as 2.5 million, and a
    `SeparableKernel` on a ``512^3`` grid as 56742. The REPL flood is the visible half. The half that
    bites harder is that this is what an exception carries: every error message in the package reads
    well today only because each author remembered to interpolate `size(field_data(f))` rather than
    `f`, and nothing enforced that.

    - **Two forms, because Julia uses them in different places.** The two-argument `show` is what
      appears inside a container, inside `$(...)` interpolation and inside an exception, so it is one
      line and **self-delimiting** — `Type{T}(body)`, parenthesised the way `Diagonal([1.0, 2.0])` and
      `CartesianIndex(1, 2, 3)` are. A bare `Type: a, b` cannot be told from its neighbours once a
      container puts commas between elements, and a display that is ambiguous in a container is
      ambiguous in the error message that motivated it. The three-argument `MIME"text/plain"` form is
      the REPL's and may spend lines; it carries the stored shape and element type, which for a field
      in spectral representation are the rfft half spectrum in a complex type rather than the grid.

    - **What the body carries is decided by what the package REFUSES on, not by what is interesting.**
      `_check_field_domain_compatibility` rejects a pair differing in scalar type, grid size, extent,
      origin, layout or storage family. A display omitting those printed two byte-identical strings
      for the two operands of the very error it existed to explain — measured on four mutually
      incompatible fields, which rendered as one string. Extent, origin and the fold are therefore
      shown whenever they differ from the ordinary isotropic ``2\pi`` box at the origin in axis order,
      which keeps the common line near fifty characters while making that collision impossible.
      The property is asserted directly, over every pair of a family of refused fields.

      The rule binds **every base-bound object, not only the fields**: an object shows what the check
      that refuses it compares. A `NUFFT` keeps its reference grid and layout precisely because a plan
      handed a same-order field on another domain returns a silently wrong answer; a traversal scratch
      is refused a rebuild against another grid; a kernel reaches the same domain check through
      `_check_kernel_compatibility`.

      All three showed their grid *size* and nothing else, so all three collided on exactly the pairs
      they are refused on — found by re-reading rather than by the testset, which covered fields alone
      when it was written.

    - **Coordinates print at full precision, and the predicate that suppresses them is EXACT.** Both
      halves were wrong in a first draft and the second is the instructive one. Rounding to four
      significant digits reintroduced the collision one axis-scale down, since the grid check is exact
      equality and boxes differing in the sixth digit are refused. Fixing that alone was not enough:
      the test asking whether the box was ordinary was `≈(2π)`, so a box of ``2\pi + 10^{-9}`` fell
      inside the default tolerance and its extent was suppressed before precision could matter. A
      loose predicate deciding *whether* to print defeats any precision in the printing. The regression
      test carries that case.

    - **Nothing may read an element.** Every quantity is host-side metadata, so a display is safe under
      `allowscalar(false)` and forces no synchronisation. A future addition printing a norm, a range or
      a sample value would break that on the backend where it matters most, so it is prohibited rather
      than discouraged.

    - **A derived quantity is not shown in place of what it derives from.** A spline scheme's weight
      matrix comes from ``(n, m)`` — the property decision 75 persists it by — and the default printed
      747 characters of matrix and neither number. The constructor call is the honest form and it
      round-trips, with Julia's parser as an independent oracle. `Grid3D` was the same case, printing
      the `grid_spacing` that decision 45 requires to equal `domain_size ./ grid_size`.

      The element type appears as the keyword the constructor takes, and only when it is not the
      default, so both forms round-trip while a `Float32` and a `Float64` scheme — which invariant 14
      refuses against each other — cannot print alike.

    - **The gate is DERIVED, in the allocation-audit shape.** `test/display.jl` enumerates every
      concrete struct type the package defines and requires each to carry a package-owned `show` or a
      cited exemption, with completeness checked both ways so a stale exemption fails too. A listed set
      of types would go stale exactly when a type is added, which is when the check has something to
      say. Falsified by perturbation before being kept: a planted struct fails it, and so does an
      exemption naming a type that does not exist.

      Six types are exempt — `RealFourierLayout`, whose default is already short, unambiguous and
      round-tripping, and five pass-local callable adapters that are never returned, never stored on a
      user-visible object, and never interpolated into an error.

    - **The work surfaced a defect it was not looking for: three spellings of the storage family.**
      `Fields._storage_family` took a section and called `parent` once, `Points._motion_storage_family`
      duplicated it for `displace!`'s refusal, and the display added a third that recursed.

      Two of the three were wrong. The constructors reject only a `SubArray`, so a `reshape` of a
      `PermutedDimsArray` of a device array is constructible, and one `parent` call answers
      `ReshapedArray` for it — not a storage family at all. So `_same_backend` could refuse two
      differently-wrapped views of the *same* device memory. That is invariant 14's predicate, so
      unifying them on the recursing form makes a check stricter as well as removing a divergence
      between a refusal and the display beside it.

83. **`reality_projection!` — the projector onto real-field spectra, because decision 71's premise
    holds only to the ulp** (2026-09-05, requested by the consuming solver with a measured failure;
    owner-decided). Decision 71 declined a repairing verb on three grounds: everything the package
    produces satisfies the reality condition by construction; the repair already exists as a physical
    round trip; and a repairing verb would silently rewrite a caller's data. The first two are now
    measured false, and the third is honoured by the design rather than overturned.

    **The premise, measured on this fleet's AMD host.** The `reality_residual` of a fresh `to_spectral`
    of a random real field is exactly zero for FFTW at ``32^3``, ``64^3`` and ``128^3`` and nonzero at
    ``96^3`` and ``256^3`` (``1.3\times10^{-4}`` and ``7.4\times10^{-4}`` in `Float32` coefficient
    units), and nonzero for rocFFT at every size (``2\times10^{-5}`` to ``8\times10^{-4}``); cuFFT
    behaves like rocFFT on the consumer's host. So "by construction" is true only for FFTW at some
    power-of-two sizes, and elsewhere a spectrum leaves the transform carrying an anti-Hermitian part
    at the round-off floor.

    **Why a floor becomes a field.** On the folded axis's zero plane both members of a conjugate
    pair are stored, and their anti-Hermitian combination is invisible to the inverse real transform
    — so the nonlinear term, formed from physical fields, neither sees it nor feeds it — and is
    damped only by ``\nu\kappa^2`` at ``\kappa \approx 1``. Any forcing proportional to the field,
    ``\hat N \mathrel{+}= A \mathbf{1}_{\text{band}} \hat u``, amplifies it with the same
    coefficient ``A`` as the physical modes, which ``A`` must hold positive on average to balance
    the dissipation.

    The consumer measured the net growth at ``A - \nu\kappa^2 \approx 0.26`` per time unit: from the
    `Float32` floor the parasitic mode reaches order one at ``t \approx 60``, and six seeds died at
    ``t = 66``–``71`` for RK3 and RK4 alike and for both dealiasing rules, `Float64` at ``t = 142``
    — ``\ln(10^9)/0.26 \approx 80`` time units later, as the rate predicts. Spectral energy held its
    target throughout while the physical field's energy, dissipation and maximum speed collapsed;
    the residual went ``4\times10^{-2} \to 1.3\times10^{6}``. Same shape as Wang & Rosa (2009) on
    the divergence-free constraint: a linear constraint the discretisation does not enforce, a
    round-off seed, a linear amplifier, and re-projection per step as the remedy.

    **What ships.** `reality_projection!(destination, source)` and the in-place
    `reality_projection!(field)`: on the stored self-conjugate planes — the folded axis's zero
    plane, and its Nyquist plane when the full axis is even — each pair is replaced by
    ``\tfrac{1}{2}(\hat f(k) + \overline{\hat f(-k)})`` and its conjugate, a self-paired corner by its
    real part from the same formula, and nothing else is touched. This is the orthogonal projector
    onto real-field spectra in the Parseval inner product: ``\mathbb R``-linear, idempotent — a
    projected pair is bit-identical under a second application — and commuting with every per-mode
    multiplier ``m`` with ``m(-k) = \overline{m(k)}``. FORMALIZATION carries the typed statement.

    Semantics decided with the request: projection only — no Nyquist zeroing, which is a dealiasing
    policy and the consumer's truncation keeps those planes empty anyway; a mutator returning its
    argument, no residual returned, so `reality_residual` stays the checker and the report/repair
    split of decision 71 stands; and nothing folded into `to_spectral!`, since a fresh transform of
    real data satisfies the condition to round-off and the defect lives in state accumulated in
    place. The two-argument form exists so the twins read alike and costs a field copy before the
    ``O(N^2)`` projection; the in-place form is the cheap one and the one the consumer calls, once
    per step beside `helmholtz_projection!` at the step's closing deposit.

    **Why the round trip is not the same repair.** It costs ``O(N^3 \log N)`` — six transforms per
    step on a vector field — and, measured by the consumer, it resets the residual only to the
    transform's floor, since the forward transform reseeds it; the projection zeroes it exactly and
    perturbs no other mode, where the round trip perturbs every mode by round-off. Decision 71's
    "the repair already exists" named a worse operation for this purpose, not the same one.

    **Naming.** `reality_projection!`, pairing with `reality_residual`: the two verbs act on one
    condition and share its stem, and "the reality condition" is the term decision 28 and `convolve!`
    already use. Declined: `real_projection!` — the request's word — because it is accurate only at
    the four self-paired corners, where the result is literally ``\operatorname{Re}\hat f``, and reads
    as `real(z)` everywhere else; `hermitian_projection!`, because `LinearAlgebra.hermitianpart` is
    the same projection on MATRICES and the package's fibers are matrices, so the name would read as a
    fiber operation — the collision decision 71 recorded for `symmetrize!`, TurTLE's word; and
    `real_field_projection!`, precise but a rename of the shipped verb for precision it already has.

    **Implementation.** A decision-38 kernel pair in `Fields`, beside the residual (one concept, one
    home): a `KernelAbstractions` kernel on a device and a gated slab-threaded loop on the CPU, both
    calling one inlined `_project_pair!` so they agree bitwise. Each pair is owned by its
    lexicographically smaller member, so it is touched by exactly one work item and no two items
    write one element — the pass audit's ideal, every stored plane element read once and written
    once, holds exactly.

    Indices are mirrored modularly and placed by the layout's folded axis through a `Val` dispatch,
    so a permuted fold projects whichever axis is folded and there are no `reverse`/`circshift`
    temporaries — the traversal the roadmap prescribes for fusing `reality_residual`, now written.
    `Fields` joined the decision-47 dispatch guard's scanned modules with its first kernel pair (17
    → 18), and its method count refroze 141 → 157 with all sixteen named (nine hand-written, seven
    generated by `@kernel`).

    **Verification.** `test/fields.jl`: 196 cells per element type — the identity on an exact
    spectrum, an elementwise pair-mean oracle over the ORIGINAL coefficients, off-plane coefficients
    bitwise untouched, exact idempotence, agreement with the round trip to ``64\varepsilon``,
    linearity, commutation with the Laplacian symbol, the two-argument form, the domain refusal and
    the physical absence, over tensor orders 0/1/2, permuted folds and an odd folded axis. GPU
    parity on ROCm: 491 → 494, the device result exactly Hermitian and bit-equal to the host's. The
    allocation audit pins both arities, the pass audit both rows at the ideal, and the benchmark
    gates run the four new rows (192 → 196 CPU, 206 → 210 ROCm).

    CUDA parity is the office host's to run; its count moves too.

    **Measured (2026-09-05, idle box; the other 80 `operators` rows reproduced the day-old archives
    at medians ``0.998``–``1.001``).** Scalar `Float64` at one thread: 20, 102, 449 and 3140 us
    across ``64^3``–``512^3``, against `reality_residual`'s 80, 362, 1586 and 13258 on the same host
    — ``4.2\times`` faster at ``512^3`` while also writing, the fused traversal having no
    `reverse`/`circshift` temporaries. Eight threads bring ``512^3`` to 331 us, ``9.5\times``. The
    vector rows run three times the scalar ones at small grids and 14.7 ms at ``512^3`` `Float64`
    one-threaded, 4.5 ms at eight. On the RX 7900 XTX every ``64^3``–``256^3`` cell sits at 27–48 us,
    launch-bound, where the residual sits at 238–244; ``512^3`` `Float32` vector reads 302 us.

    **The pass is strided by the layout's nature.** The folded axis is the contiguous one, so its
    zero plane is one element per cache line: ``512^3`` scalar moves 16.8 MB in 3.1 ms at one thread,
    about 5 GB/s, and threading is what recovers it. One observation recorded without a cause: at
    ``512^3`` the `Float32` scalar row is ``1.04``–``1.29\times`` SLOWER than `Float64` on every CPU
    lane. The archives were not spliced — `src/` moved with this decision, which is the case the
    splice tool refuses — so the rows enter `RESULTS.md` at the next sweep.

    **What decision 71 keeps.** The check reports; the projection is an explicit verb the caller
    invokes; no transform enforces the symmetry — per-operation enforcement would tax every transform
    for a problem only a multiplicative forcing creates, and a decaying run never needs it. What 71
    loses is one sentence, "everything the package produces satisfies the constraint by
    construction", which was a claim about FFTW at power-of-two sizes and is now stated as such
    wherever it appeared.


84. **CUDA unified memory is a supported configuration, chosen by CUDA.jl's preference and not by the
    package** (2026-09-17, owner-decided). A consumer runs out of memory on a 96 GiB GH200 at ``768^3``
    by a few GiB, and CUDA.jl can place every array in unified memory, which the driver pages between
    the GPU and host RAM. The package needs no code for it: it never names a memory kind, and a
    `CuArray` allocated without one takes CUDA.jl's `default_memory` preference.

    So every allocating route — the family constructors, `adapt`, `similar_field`, the multipliers, the
    kernel builders, the traversal order, the allocating operations — follows the setting, while cuFFT's
    own workspace, which it allocates itself, stays in device memory. The how-to is one page,
    [Running on a GPU](gpu.md), which covers ROCm too, where `AMDGPU` has no unified memory at all.

    - **Invariant 14 is unchanged.** A unified `CuArray` and a device `CuArray` are one storage family,
      because the family is the kind of array and not the memory holding it, and they combine rather
      than being refused. The definitions that said "host memory, or one vendor's device memory" were
      wrong under this configuration and now say "the kind of array".

    - **The whole process, not per field.** Unified memory for some fields and device memory for
      others is not offered. The family constructors read only a family's element type, so
      `CuArray{Float64,3,UnifiedMemory}` yields device memory, and their docstrings now say so; and in a
      mixed pair the field broadcast takes the result's memory from its first operand, where CUDA.jl's
      own array broadcast promotes to unified either way. Per-field placement would need both settled,
      and it is deferred until a measurement on GH200 shows all-unified is too slow to use.

    - **What the configuration cannot check.** CUDA.jl serves element-by-element access to a unified
      array through the host and does not honour `allowscalar(false)` for it, so a unified run is blind
      to invariant 6. The unified test lane, `test/gpu/cuda-unified`, therefore adds to the device lane
      rather than replacing it; it refuses to run when the preference has not taken effect, asserts that
      every allocating route is unified, and runs a working set larger than the card.

    - **What it cannot measure.** The benchmark harness decides its per-row GC from
      `CUDA.used_memory()`, which does not count unified allocations, so it refuses the configuration
      outright rather than report timings of the wrong thing. The one measurement taken is a bespoke
      script on an x86 card (Performance finding (as)); GH200 is unmeasured (Performance §7 gap 9).

    - **The preference itself is the fragile part.** CUDA.jl 6 reads it inside its `CUDACore`
      subpackage, which the running project must name in `[extras]`, and CUDA.jl's own template still
      shows the section as `[CUDA]` — silently ignored. The documentation build rejects that spelling,
      and the test lane's first act is a residency check, because the failure mode is a green run that
      proves nothing.

85. **Two grids over one box share their low modes, and two verbs move them** (2026-09-18,
    user-directed, after an adversarial naming panel). A consumer forcing a turbulent flow needs
    content computed on a small grid — a stochastic process on a few dozen modes, or the nonlinear
    term of a low-wavenumber block obeying its own equations — to reach a large field every stage, and
    the reverse for the block's input. Nothing in the method set did that: the algebra needs operands
    of one shape, a kernel multiplies rather than adds, and the point transfer would sum over points at
    every mode.

    A grid of ``N`` points over a domain of length ``L`` resolves the wavenumbers ``2\pi/L`` times the
    integers it stores, so two grids over the SAME box name the same physical modes where they
    overlap, whatever their counts. The verb [`embed_modes!`](@ref) writes a coarser field's modes into a finer
    one and [`extract_modes!`](@ref) reads them back, each leaving every other mode of its destination
    untouched, at a cost set by the coarse field.

    - **Why two verbs for one index map.** The directions are different operations: embedding is
      injective and lossless, extraction discards everything the coarse grid cannot hold, and their
      scale factors are reciprocal. The deciding argument is a failure mode rather than taxonomy. The
      motivating consumer calls both directions on the same pair of fields a few lines apart, so under
      a single verb taking its direction from which argument is coarser, a transposed call would be
      legal by definition — no assertion could be written against it — and would leave a run silently
      unforced. With two verbs each wrong argument order is refused from grid metadata before a
      coefficient is read.

    - **Amplitudes are physical.** The stored coefficient of a mode is `prod(grid_size)` times its
      amplitude (invariant 4), so a transfer between resolutions carries the ratio of the two counts,
      and the operations apply it. That is what makes the round trip an identity on the shared modes,
      keeps a grid-size ratio out of the middle of a consumer's equation of motion, and makes the two
      verbs **exact adjoints under `inner`, with no measure factor** — unlike the point transfer's
      `W`/`Wᵀ`, which carries `N/M`. Raw coefficient copying would be adjoint only up to
      ``(N_c/N_f)^2``.

    - **The coarse grid's Nyquist shell is excluded, and that exclusion is what makes the shared set a
      subspace.** A coarse mode at ``|k| = N_c/2`` on an even axis describes one sampled wave that the
      fine grid splits into two modes, so the single coarse coefficient does not determine them.
      Transferring it would have to choose, and either choice breaks the reality condition or the
      adjointness. Excluding it costs nothing a de-aliased solver relies on.

    - **Refusals are structural, never data-dependent**: same domain size, origin, Fourier layout,
      scalar type, tensor order and storage family, and a coarse grid no larger on any axis and
      smaller on at least one. **Equal grids are refused**, because the Nyquist exclusion would make
      such a call a copy that silently leaves those planes stale, and two fields on one grid combine
      with `add!` or `combine!`.

    - **Neither verb has an allocating sibling.** The result depends on the destination's prior
      contents — the modes outside the shared set survive — so an allocating form would have to invent
      them. The same reasoning as `combine!` and `displace!`.

    - **The NUFFT was refactored onto these verbs, as the strongest available test of them.** Its
      oversampled work grid covers the same box as the reference with more points, so the reference's
      modes are a subset of it and the scheme's own `_nufft_embed_kernel!`/`_nufft_extract_kernel!`
      were this operation in private form. They are gone, with `_nufft_index_map` and the three
      `embed_map_*` fields and their type parameter: 57 lines, three device arrays per plan, and a
      piece of index arithmetic that had to be kept in step with the layout by hand. The scheme is
      verified exact against `DirectDFT`, and that equality still holds — which is a test no fixture
      of this operation's own could give it.

      Two differences had to be paid rather than assumed. The old map carried the reference's Nyquist
      shell to `-N/2` of the oversampled grid where the shared set excludes it, which is consistent
      with the scheme's documented band but means its scratch must now be ZEROED, since the
      operation writes only shared modes and `similar` returns whatever was in memory — the first run
      after the refactor produced `NaN` for exactly that reason. And the scale factor moved: the
      embed site dropped its hand-applied `total_oversampling` because the operation carries that
      ratio, while the extract site multiplies by it, the operation dividing where the old kernel did
      nothing. The NUFFT had been applying the same physical-amplitude convention all along.

    - **The names were chosen adversarially**, against the alternatives `truncate`, `project`,
      `inject`, `restrict`, `prolong`, `pad` and a single `copy_shared_modes!`. `truncate` and `chop`
      are exported by `Base` and `truncate` already means de-aliasing in the consuming solver;
      `project` is spent here on two genuine idempotent projections; `inject` reverses direction
      between audiences and means energy injection in the calling module; `restrict` reads as this
      package's word for an invariant-1 absence; `prolong`/`restrict` are multigrid's PHYSICAL-space
      transfer operators and would become a lie the day a physical analogue arrives. The `_modes`
      suffix is earned by the same rule as the package's other verb-plus-object names: the bare verb
      is ambiguous, this package embedding points into cells and coarse spectra into oversampled ones
      elsewhere.

86. **The Lamb vector is ``\omega \times u``** (2026-09-24, owner-decided). For a velocity field ``u``
    with vorticity ``\omega = \nabla \times u``, the rotational form of the Navier–Stokes nonlinearity
    is ``u \cdot \nabla u = \omega \times u + \nabla(\tfrac{1}{2}\lvert u\rvert^{2})``, and the package's
    documentation calls ``\omega \times u`` the Lamb vector. That is the literature's convention:
    Sagaut & Cambon (2018) name "the Lamb vector ``\omega \times u``" (their Eq. 12.2 and the text after
    it), and Pope (2000) writes the opposite product ``U \times \omega`` in the same identity but never
    uses the name. The opposite sign, ``u \times \omega``, is in circulation too, as Wikipedia's article
    shows, so the name without its sign is ambiguous.

    - **What it changed.** The CPU example advances the Leray projection ``\mathbb{P}`` of the transform
      of ``u \times \omega``, and called ``u \times \omega`` the Lamb vector. The equation was right and the name was off by a sign; the
      prose now says the term is minus the Lamb vector. The code is unchanged, since it computes
      ``u \times \omega``, which enters with the sign the equation needs.

    - **How it surfaced.** The first documentation review's differential-geometry reader flagged it
      (finding `004` of 2026-09-22), and the wording changed only after the sign was checked in Pope
      (2000) and Sagaut & Cambon (2018).

87. **A top-hat window of any width, and the cloud-in-cell window as its square** (2026-09-26,
    owner-approved; requested by `GBGHomogeneousTurbulence` on 2026-09-22). The builder
    `tophat_window(multipliers, width)` returns the box average of edges ``l_a`` as a `SeparableKernel`
    whose per-axis factors are ``\operatorname{sinc}(k_a l_a / 2)``, taken from the true wavenumber
    component ``k_a`` so the window is real and even. Physically it is the normalized indicator of the
    box: convolving a field with it replaces the field at each point by its mean over the box centred
    there.


    - **Why the package builds it.** The consumer needed the kinetic energy held in scales below a size
      ``l`` and the matching dissipation, both of which reduce exactly to spectral reductions weighted by
      ``1 - \hat W_l^2``, with ``\hat W_l`` this window. The per-axis sinc is physics-free field
      mathematics, and `SeparableKernel` has no public constructor, so the caller could not build it;
      the diagnostic itself stays with the caller (invariant 12), as the pair-correlation recipe does
      beside `assignment_window`.

    - **The window, not its square.** ``\hat W`` is what acts on a field. Its square is the window
      convolved with itself, which separable kernels already compose per axis at no cost (decision 50),
      so shipping both would be adding an operation for completeness (invariant 1). The caller squares
      it with `convolve(w, w)`.

    - **`assignment_window` is now that square at the grid spacing.** The cloud-in-cell tent is a
      cell-wide top-hat convolved with itself, so the older builder became the composition of two
      cell-wide windows. The result is bitwise the former closed form, because squaring a
      floating-point factor is the same product either way; this was checked in both precisions on a
      cubic grid and on an anisotropic grid with an odd axis. The two builders now share one formula.

    - **The name and the argument.** It is not `box_window`, because "the box" means the domain
      throughout this package. The width is positional, since it changes the result: one number is a
      cube, which is the consumer's case, and a triple a rectangular box, as `assignment_window` uses
      one spacing per axis. A negative or non-finite edge is refused, a zero edge leaves its axis
      unfiltered, and an edge as long as the domain is allowed: on a periodic domain it cancels every
      nonzero wavenumber along that axis, so a cube the size of the domain keeps the mean alone.

    - **A continuum average.** The sinc is the transform of the continuum box, so the result is the
      exact box mean of the band-limited field, not the mean of the grid values inside the box, even
      for an edge of a whole number of cells, and it can exceed the range of those values.

    - **A caution passed to the consumer.** Batching many widths into one tuple reduction nests one
      product kernel per width. Finding (aq) measured register pressure halving occupancy on the AMD
      card in another kernel, a wide tuple accumulator is the kind of shape that raises it, and nested
      lazy broadcasts are the fragile spot on that backend, so the batch size is to be swept rather than
      assumed.

88. **An operand count the caller chooses is worked through in groups of a fixed size** (2026-09-26,
    owner-approved; reported by `GBGHomogeneousTurbulence` on 2026-09-26). Four operations take as
    many operands as their caller passes: `add!` and `subtract!` over sections (with the `+` and `-`
    they back), `map!` over sources, `displace!` over terms, and `weighted_inner` over a tuple of
    weights. Each was written as one pass over all of its operands.

    Each now handles at most a fixed number per pass — eight for the first three, four weights for
    the reduction — and continues from its own partial result. Within a pass every per-element step
    that indexes the operands is written out with a literal index per operand, generated per count.

    - **What broke.** The consumer's `weighted_inner` with 32 weights did not compile on a device.
      The research the report prompted found the same shape in the other three, where the count had
      simply never been large: an unnamed trailing argument list (`fields...`), which Julia need not
      specialize on its length, and tuple `map`s and splats, which leave `Base`'s specialized path at
      32 entries for a generic one that allocates on a CPU and cannot run in a kernel. A device kernel's
      arguments are also limited in size, which bounds how many lazy operands one launch may carry.

    - **What it cost before.** Measured on the CPU before the change, with every operand written out at the call site and a
      ``24^3`` vector field: at 33 operands `add!` allocated 775 MB per call, the 33-weight
      `weighted_inner` 139 MB, `displace!` 0.6 MB, and `map!` over six tensor fields 57 MB already
      at six sources. At 9 operands `add!` allocated 16.7 KB, still more than it does now at 33.

    - **A fixed size, not a tuned one.** The owner raised the danger of tuning the group size to a
      backend or a card and proposed a fixed safe size instead. The limits above differ between
      vendors and drivers, a tuned constant would be right only on the machine that measured it, and nothing the package does needs a pass wider than the counts a
      solver passes, which fit in one group. Eight and four sit well below every ceiling named above.
      The alternative of recursing on argument lists was declined for the same reason as splatting:
      it relies on the compiler's heuristics rather than stating the count.

    - **Grouping changes no result.** Each group continues the previous one's left-to-right order, so
      `add!` over 33 sections is bitwise the plain left fold, `displace!` over 20 terms bitwise the
      term-by-term sum, and the tuple `weighted_inner` on the CPU bitwise one single-weight call per
      weight. Two cases needed care. An operand that is also the destination would be overwritten by
      the first group before a later group reads it, so the later group reads a copy of it; and the
      torus form of `displace!` wraps once, after the last group, since wrapping between groups would
      round differently wherever an intermediate position crossed the boundary.

    - **What it costs.** At one thread every grouped call allocates zero bytes at 9 and at 33 operands;
      threaded, a field `add!` pays `Base.Threads` task state once per pass; and `weighted_inner`
      allocates one single-weight call's worth per group of four (Performance finding (au)). Above one
      group, a pass per group re-reads what one pass would have read once: a tuple of 33 weights takes
      nine traversals. Measured, that is exactly the added traffic — `add!` past eight operands about 20–24%
      slower than one pass would be — and 33 grouped weights still beat 33 separate calls (finding (au)).

    - **The first version broke a case the CPU suite passed.** The per-element read was first an
      `ntuple` over a closure, `i -> arrays[i][n]`. When the operands are of different types, as in a
      kernel-composed `combine!` or `convolve!` where a radial kernel's lazy expression sits beside
      plain arrays, the compiler did not inline that closure and indexed the tuple at run time. On the
      CPU that ran, allocating 8.3 MB per call on a ``16^3`` vector field; on a device it did not
      compile.

    - **Why only the device saw it, and the repair.** The CUDA suite caught it, and the CPU
      allocation audit had not, its kernel-composed rows using only a stored kernel, whose operands
      are all plain arrays. The read is now a generated
      function with a literal index per operand, back to the 16 bytes the call cost before, and the
      audit has rows for every compressed kernel class, which fail against the closure form.

    - **The repair itself cost speed until the canary caught it.** `@inline` cannot annotate a
      `@generated` function, so the generated read stayed a call inside the executor's `@simd` loop and
      blocked vectorization: the `mul!` canary ran ``3.2\times`` slower on one CPU thread and
      ``13.5\times`` slower on the device, `sym!` ``2.1\times`` and ``9.5\times``. Every test passed
      throughout, the pass being correct and allocation-free. The generated bodies now carry their own
      inline marker, and the canary reads flat on the device and at eight threads and faster at one:
      `mul!` 7.1 to 5.7 ms, `sym!` 13.1 to 9.3 ms.

    - **The exhaustive survey found the `map` path past 32 sources.** Its first run with sources past
      the group size reported the allocating `map` over 33 sources inferring a `Union` of every tensor
      order. The cause was three `Base.map` calls over the source tuple in the shared driver, which
      leave the specialized path from 32 elements.

    - **And what the survey's type check could not see.** Chasing it found that `map!` over 33 sources allocated about 1.9 KB per point, 38 MB per call on a ``24^3`` vector
      field, in a per-point recursion over the sources whose results were splatted into φ. A generated
      tuple map replaces the three calls and a generated call replaces the recursion; both now read zero
      bytes and a concrete type, with `map!` unchanged at ordinary counts.

    - **How it is pinned.** The file `test/caller_counts.jl` sweeps each operation past its group size
      and past 32 operands against raw-array arithmetic, including a destination that aliases a later
      operand; `test/allocations.jl` asserts the serial zero with every operand written out at the call
      site, a splat of more than 32 values allocating in the caller; and the GPU suite runs each class
      past the old ceiling on the device. The operand count is Testing axis 23. Two falsification runs
      confirmed the new tests bite: removing the aliased-operand copy fails 28 assertions, and wrapping
      after every group fails 6.

89. **The four audit harnesses are declared to [GBGCodingTools](https://grigorysarnitsky.github.io/GBGCodingTools.jl/)** (2026-09-27, owner-ruled). The allocation
    audit, the element-traffic audit, the oracle registry and method parity now call the tool's
    engines, `GBGCodingTools.TestHarness`, in place of the copies each test file defined. The tool's
    engines were extracted from those same files, so every row, frozen count and exemption stays in PF;
    what moved is the machinery that reads them.

    - **Why.** The rulebook's four harness rules bind only a package that declares the harness, and a
      package declares one by calling the tool's engine from its suite. Undeclared, the rules did not
      bind PF, so `CLAUDE.md`'s own statements of the audits were the only binding text and could not be
      cut as restatements of the rulebook.

    - **Two counts moved, and no method was added.** The tool's surface walk descends into `Base`'s
      submodules, so it sees the `Base.Broadcast.broadcastable` methods of `Fields` and `Points`, which
      PF's own scan never did: the derived method counts are refrozen at 177 and 235, and
      `broadcastable` is classified in the oracle registry as structural, returning the section itself.

    - **What was kept of PF's.** The frozen method counts moved to `test/method_parity_baseline.toml`,
      their refreeze history with them. The oracle table stays in Julia, being partly generated and
      heavily annotated, and is handed to the engine in the shape it reads. `PASS_AUDIT_PRINT=1` still
      regenerates the traffic table.

    - **Verified.** Each ported file passes unchanged, and each fails on a planted defect, naming it:
      a removed allocation row (`wrap!` uncovered), a removed traffic row (`transpose!` uncovered), an
      altered frozen traffic count, an altered method count, and a removed oracle entry.
90. **Removing a field's mean, and evaluating a kernel into existing storage, are named operations** (2026-09-28, owner-ruled). The consumer `GBGHomogeneousTurbulence` asked PF
    to review how it uses PF, and two of its workarounds turned out to be missing operations rather
    than misuse. `mean_free_projection!(f)` sets the mean of a field in spectral representation to
    exactly zero, and `materialize_kernel!(destination, kernel)` writes a kernel's coefficients into a
    `StoredKernel` that already exists.

    - **Why a projector, rather than guidance.** The consumer zeroed its nonlinear term's mean by
      writing into the stored coefficient at index ``(1, 1, 1)``, which is correct under every layout
      but is knowledge PF owns. The first answer drafted for it was a recipe: fold a kernel that
      vanishes at ``k = 0`` into a pass it already makes, relying on how the projection treats that
      mode, that composition multiplies every other mode by exactly one, and that the ordinary cutoff
      must not change because it also truncates initial conditions. A consumer should not need four
      facts about the implementation to take a mean out, so the operation was named instead.

    - **Why subtracting the mean does not serve.** Subtracting `mean(f)` is not a substitute: it reads the value back to the host, leaves round-off
      at a grid size that is not a power of two, and clears only the real part, `mean` being real.

    - **What `mean_free_projection!` is.** The ``L^2``-orthogonal projector onto the complement of the
      constants, ``f \mapsto f - \lvert\Omega\rvert^{-1} \int_\Omega f \,\mathrm{d}x``, the companion
      of `reality_projection!` and `helmholtz_projection!`. In spectral representation it writes zero
      into the zero coefficient of every fiber component, both parts, and touches nothing else: one
      write per component, no read, no copy, no readback, so it is exactly idempotent and its result's
      mean is exactly zero.

    - **Spectral representation only, by the owner's ruling.** Invariant 1 has operations linear in the
      field exist in both representations. In physical space the mean occupies no single stored value,
      so the projector would be a full pass leaving round-off, which `subtract!(f, f, mean(f))` already
      is; that form stays the route there, and the absence gate asserts the physical call throws.

    - **No "set the mean to a value".** The consumer asked for zero or a given constant. Setting it to
      ``c`` is the projection followed by `add!(f, f, c)`, which already writes only the zero mode
      (invariant 4), so only the projection is new.

    - **Why `materialize_kernel!`.** The consumer's steady forcing held a band indicator as a raw
      array for the whole run (1.69 GiB at ``768^3`` in `Float64`) and multiplied it into a rate field
      every step. Once the rate is filled only when the forcing is built, the band can stay a lazy
      kernel, but filling a field with its coefficients then cost a field-sized temporary per call of
      `materialize_kernel` — two calls at construction, 3.38 GiB each at ``768^3``, on a device the
      consumer already runs out of.

    - **Why a name rather than the existing route.** An allocation-free route existed: fill the field with ones, the
      spectrum of a unit impulse, and convolve it with the kernel. It rests on a fact about Fourier
      spikes a consumer should not need, so the operation was named. Mathematically it is the in-place
      twin of `materialize_kernel`, as `translation_kernel!` is of `translation_kernel`.

    - **The destination is a `StoredKernel`, not a field.** Decision 60 separates a field from a kernel,
      and `materialize_kernel` returns a `StoredKernel`, so its twin writes one. A caller holding a
      field wraps it once as `StoredKernel(field)`, which references the field rather than copying it.
      No scale argument: a `multiply!` afterwards serves, the evaluation being a construction-time cost.

    - **The divergence's zero mean is now stated.** The consumer's scalar right-hand side zeroed a mean
      that the divergence already computes as exactly zero, every derivative wavenumber being zero at
      that mode. The `divergence!` docstring had only implied it, so it now says so, with its one
      qualifier (wavenumbers built from the grid), and `test/differentialoperators.jl` pins it; the
      consumer deletes its zeroing on the strength of that sentence. The `reality_residual` docstring
      likewise now states its units, the unnormalized stored coefficients.

    - **Declined in the same review.** A mode count for a band (the consumer's own loop is exact and
      runs on a tiny grid) and a relative form of `reality_residual` (the consumer's comparison with
      the largest stored coefficient is the right one, now documented).
