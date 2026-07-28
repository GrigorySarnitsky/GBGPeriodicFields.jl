# Testing — GBGPeriodicFields

This is one of three design companions: [`ARCHITECTURE.md`](architecture.md) explains why the
*package* is built the way it is, [`PERFORMANCE.md`](performance.md) how it performs and is
benchmarked, and this one explains how the *tests* are built and what they must cover. Read it
before adding or changing tests. The goal is not a test count — it is that every claim the package
makes is checked against something independent of the package.


## 1. Philosophy

**Verify against independent ground truth, never against the code's own other path.**
A test that compares one package routine to another package routine only proves they
agree, not that either is correct. Two kinds of oracle are used:

- **Analytic oracles** — for the differential operators. A field is taken to spectral
  representation, the operator applied, and the result compared to a *known closed
  form*: ``\partial_x \sin x = \cos x``, ``\Delta \sin x = -\sin x``,
  ``\nabla \times (0, 0, \sin x) = (0, -\cos x, 0)``, a Helmholtz-projected field is
  divergence-free. These catch sign, axis, and scaling
  errors that a self-consistent round-trip would silently reproduce.
- **Trusted reference** — for representation parity and for the GPU path. The CPU path
  is pinned by analytic oracles and the parity baseline; *then* another computation of
  the same quantity (the spectral form, or the same operation on a device array) is
  required to match it. This is still "two computations of one quantity," not a thing
  against itself.
- **Structural identities** — relations the operators must satisfy for *any* input: the
  vector-calculus identities (``\nabla\cdot(\nabla\times u) = 0``, ``\nabla\times(\nabla\varphi) = 0``) and, on a periodic box,
  the adjoint relations (divergence as the negative gradient adjoint, self-adjoint curl, a
  self-adjoint negative-semidefinite Laplacian, an exactly idempotent self-adjoint Helmholtz
  projection — decision 42). Tested on randomized band-limited fields, they pin the discrete
  energy/entropy structure of the scheme.

**The public method set is the spec.** Two mechanisms enforce this:

- the **parity baseline** (`test/method_parity.jl`) locks the per-generic method counts
  (206 public methods) so a code-generation change cannot silently add or drop a method;
- **intentional-absence tests** assert that invalid combinations *do not exist*
  (`@test_throws MethodError`), symmetrically across representations: nonlinear products
  are absent in spectral (field×field, division by a scalar field, pointwise norms), and
  the differential operators are absent in physical (differentiation is spectral-only —
  there are no finite-difference physical operators yet). A deliberate gap is a tested gap.

**"Should work" is not done.** The minimum bar for any change is: the package loads,
the parity baseline and ambiguity check pass, and the suite is green.


## 2. Layout

- **`test/runtests.jl`** includes each module's file inside its own wrapper module
  (`module FieldAlgebraTests; include("fieldalgebra.jl"); end`), so per-file helpers and
  constants (`comp`, `plans_for`, `grid`, `T`) cannot collide. Every file is also
  runnable on its own (`julia --project=. test/<file>.jl`).
- **Per-module behaviour files** — `fields.jl` (including the decision-45 `Grid3D` uniformity check: a contradictory `grid_spacing` and a non-positive size are rejected, an equivalent-arithmetic spacing accepted, at both element types), `fieldalgebra.jl` (the M2 + M3 surface, incl. the weighted
  combination `combine!`, the determinant `det`, and the arbitrary-φ `map!` / `map` — decision 48 —
  against the named operations as oracles, order changes, multi-input, α/β, aliasing, and the
  physical-only absence),
  `differentialoperators.jl` (the spectral operators, incl. the fused `symmetric_gradient`), `convolution.jl` (periodic convolution + the kernel/coordinate builders
  `spectral_cutoff` / `spectral_band` / `squared_wavenumber_field` / `translation_kernel`),
  `interpolation.jl` (the point-data types),
  `pointvalues_algebra.jl` (the point-value M2 + M3 surface, incl. `det` and the representation-free `map!` / `map`),
  `interpolation_transfer.jl` (the physical-domain spline transfer — the smooth `LalescuSpline`/`CatmullRom` and the ``C^0`` `LagrangeSpline` — interpolation / anterpolation kernels),
  `transfer_spectral.jl` (the spectral-domain transfer schemes — the exact `DirectDFT` and the fast `NUFFT`), and
  `reductions.jl` (the L²/measure reductions + the multiplier-weighted `weighted_inner` + the radial reductions `radial_spectrum` / `radial_correlation`, incl. the two-field co-spectra, on fields and point-values),
  `rdf.jl` (the Phase-2 point pair-correlation: `assignment_window` + the FFT g(r) recipe vs direct counting), plus
  `eltype_genericity.jl` (Float64/Float32),
  the cross-file **permuted-layout lane** (decision 41) — a `permuted rfft layout` testset in
  `fields.jl` (a transform round-trip + both multiplier families vs `rfftfreq`/`fftfreq`, odd and
  even folds), `differentialoperators.jl` (analytic gradient/Laplacian), `convolution.jl` (the
  translation kernel's circshift oracle, a live Nyquist factor on the folded axis),
  `transfer_spectral.jl` (`DirectDFT` at the nodes + `NUFFT` vs its oracle), `reductions.jl`
  (Parseval/shell/weighted + `radial_correlation`, odd and even folds), and `hdf5.jl` (`fft_dims`
  persistence) — every layer whose correctness rests on the fold following `fft_dims`,
  `adjointness.jl` (operator structure on random fields),
  `randomized.jl` (property-based: algebraic laws on random fields / point-values / kernels),
  `allocations.jl` (a **comprehensive** `@allocated` audit, both element types: the *entire* in-place `!` surface — spectral operators (incl. `symmetric_gradient!`), transforms, `convolve!`, the M2+M3 algebra `add!`/`combine!`/`mul!`/`multiply!`/`divide!`/`dot!`/`cross!`/`transpose!`/`sym!`/`skew!`/`tr!`/`det!` over physical+spectral, all tensor orders, the constant/α/β/reversed variants, the point-value algebra (incl. `det!`), and the spline `interpolate!`/`anterpolate!` — allocates ``\sim 0`` bytes; the hot-loop reductions (physical `inner`, the fused `weighted_inner`, `maximum`, `integral`/`mean`, and the spectral zero-mode `integral`/`mean`) do not materialize a field; and the documented allocators are bounded — `norm!`/`lpnorm`/`std`/`var`/`radial_correlation` (its power field + the allocating transform; `dev!` left the list when decision 39 fused its trace into a register; `radial_spectrum` is pinned tight, its staging fused into the binning kernel by decision 34), and the spectral vector `inner`'s O(N²) Parseval-correction planes, rocBLAS offering no `dotc` over a strided `ROCArray` view; guards the GPU hot-loop discipline, decisions 24/25/34),
  `pass_audit.jl` (the element-traffic ledger, decision 36: a `CountingArray` harness measures every
  audited operation's exact per-array read/write counts against a frozen fused-ideal table — an
  above-ideal count must carry a named holder — catching the unfused-recompute class no other layer
  sees; CPU-only, `PASS_AUDIT_PRINT=1` regenerates the cells),
  `aqua.jl` (package checks),
  `threading.jl` (CPU threading; runs in both the default and a `JULIA_NUM_THREADS` lane; covers
  the `KernelAbstractions` kernels separately — bitwise for the disjoint-write gather, to a tolerance
  for the two `Atomix` accumulators — and asserts the decision-40 reductions **bitwise
  thread-count-invariant**, in-process and across a subprocess at a different `-t`),
  and `jet.jl` (`JET` `@test_call` static analysis of the public operations), and `hdf5.jl` (the
  `write_field`/`read_field` and `write_points`/`read_points` HDF5 persistence round trips — every field
  type, every point type, the self-description attributes, and the corrupted-group error paths for both
  families — run with the `HDF5` weak dependency loaded).
- **`test/method_parity.jl`** — the spec-lock: per-generic method counts (the
  206-method field surface and the separate 122-method point-value surface) plus
  `detect_ambiguities` (from `Test`) over the whole package. The explicit `multiply!`
  quartet exists precisely to keep that ambiguity set empty.
- **`test/Project.toml`** — the test environment's dependencies, deliberately
  **backend-free** (see §5).
- **`test/gpu/`** — the opt-in GPU suite (see §5).
- **Doctests** — the Getting-started tutorial (`docs/src/tutorial.md`) is written as `jldoctest`
  blocks, run and verified by `doctest = true` in `docs/make.jl` (outside `Pkg.test()`): a third
  layer of checked examples that cannot drift from the code (a wrong expected output fails the build).


## 3. Writing a test here

**Helpers and conventions.** Build fields from coordinate functions
(`ScalarFieldPhysical((x,y,z) -> …, grid)`); take component slices with the local
`comp`/`tcomp` helpers; build matching transform plans with a `plans_for(field)` helper
that allocates the spectral scratch with `similar(field_data(field), …)` so it inherits
the field's backend. Compare with `field_data(result) ≈ expected`.

**Tolerances — the part that bites.** `≈` (`isapprox`) uses a *relative* tolerance with
`atol = 0` by default:

- For an O(1) result, bare `≈` is correct.
- For a result that is **mathematically ~zero**, bare `≈` degenerates to an almost-exact
  comparison and will fail on nothing but rounding. Either assert
  `maximum(abs, data) < 1e-12`, or pass an explicit `atol`. **Also choose inputs so the
  expected result is not accidentally zero** — e.g. an axis-aligned field
  ``(\sin x, \sin y, \sin z)`` is irrotational *and* longitudinal, so both `curl` and the
  Helmholtz projection return ~0 and test nothing. Use a field whose components depend on
  more than one coordinate.
- For **cross-backend** comparison (GPU vs CPU), the two run the same formula and agree
  to roundoff, so compare with `isapprox(Array(device), host; rtol, atol)` carrying a
  small absolute floor.
- The same trap appears for **inner products of independent fields** (e.g. ``\langle \nabla\varphi, u\rangle``): they
  are near-orthogonal, so the common value of two equal inner products is small relative
  to the operand magnitudes. Scale the floor by the Cauchy–Schwarz product ``\lVert a\rVert \lVert b\rVert``, not
  by the (tiny) result.

**Pick the right oracle.** Operators → analytic closed form. Representation parity and
backend parity → trusted CPU reference. Never assert an operator only by inverting itself.


## 4. The coverage contract

For each public operation, a test must establish:

- [ ] **Physical-space correctness** against an analytic or hand-computed result.
- [ ] **Spectral-space behaviour** — correctness where the operation is linear in the
      field (valid in both representations); an asserted **intentional absence**
      (`@test_throws MethodError`) where it is nonlinear (physical-only).
- [ ] **Both element types** — `Float64` and `Float32`. (`Float32` is the realistic GPU
      precision; consumer GPUs run `Float64` far slower.)
- [ ] **An anisotropic domain** — at least one test with ``L_x \ne L_y \ne L_z``, so the ``2\pi/L``
      wavenumber scaling is actually exercised and a dropped length factor is visible.
- [ ] **The in-place `!` form** with a caller-supplied destination, including the
      **aliased in-place branch** for the by-construction alias-safe operations (cross, transpose, sym/skew/dev,
      the curl wrapper) — and, for `mul!`, the LinearAlgebra no-alias contract. An op whose kernel is
      alias-safe *by construction* (the one-pass `helmholtz_projection!`, decision 32) asserts the
      aliased call **bitwise equal** to the non-aliased one instead — a stronger check than the
      guard's tolerance.
- [ ] **Element traffic** (decision 36): a new or rewritten operation gets a `pass_audit.jl` row —
      its exact per-array read and write counts measured through the `CountingArray` harness and
      frozen beside the fused ideal, with a named holder for any deliberate gap. This is the layer
      that catches an unfused recompute, which correctness, allocation, and static analysis all pass.
- [ ] **Allocation-free** (invariant 13): every in-place `!` operator gets an `@allocated` assertion in
      `allocations.jl` — on preallocated buffers with a distinct destination it allocates ``\sim 0``
      field-sized bytes, both element types. Run **on the CPU**: there a materialized field's full bytes
      are counted, whereas GPU `@allocated` reports only the host wrapper of a device buffer and would miss
      the materialization that wedges a hot loop (the code is generic, so a CPU materialization is a GPU
      one). A deliberate materializer (`norm!`/`lpnorm`/`std`/`var`, `radial_correlation`, the
      mixed spectral `inner(f, g)`) instead gets a *bounded* guard that catches an O(N)/O(shells) regression.
- [ ] **Both α/β branches** for the five-argument kernels — overwrite (``\beta = 0``, which must
      ignore the destination's prior contents, NaN included) and accumulate (``\beta \ne 0``).
- [ ] **GPU parity** — the result matches the CPU path on a device array, under
      `allowscalar(false)`.

**Grid coverage.** Use a **mixed-parity** grid (even and odd axis lengths, e.g.
`(8, 7, 6)`) so the Nyquist split is exercised; where the Nyquist mode matters, include a
field that actually populates it and confirm the derivative of a real field stays real.

**The coverage axes — the explicit denominator (2026-07-23).** The checklist above is exhaustive
only over the axes it names; a bug class living on an *unnamed* axis is invisible to it by
construction. Three defects taught this in one week (decisions 41/42 and the `NUFFT` layout
wrapper): each sat on an input-space axis that existed in the type system yet was never varied by
any test — the rfft fold `fft_dims` had exactly one value ever constructed, and the adjointness
fixtures deliberately dodged the Nyquist band. So the denominator is written down. Every
operation's coverage is judged against the full axis list:

1. representation (physical/spectral, including the asserted intentional absences);
2. tensor order ``R``;
3. element type (`Float64`/`Float32`) **on the CPU lane** — GPU parity alone leaves the default
   `Pkg.test()` blind to the `Float32` numerics;
4. rfft layout — the fold must follow a non-default `fft_dims` (the permuted-layout lane, §2);
5. axis parity (even and odd, folded and unfolded);
6. grid-size cubicity (distinct extents, e.g. `(8, 6, 4)` — a cubic-only suite cannot see a
   transposed extent);
7. domain-length anisotropy (distinct per-axis ``2\pi/L`` factors appearing *in the oracle's own
   formula*, so a dropped factor cannot cancel);
8. origin ``\ne 0`` where the operation consumes coordinates (the transfer layer);
9. degenerate bases (an empty `PointSet`; an axis of length 1 or 2) — pinned or asserted-absent;
10. α/β including the ``\alpha = 0, \beta \ne 0`` branch (the pure ``\beta``-rescale);
11. aliasing patterns per arity (`dest === a` and `dest === b` are different hazards);
12. Nyquist content — at least one fixture populating the Nyquist planes, including the mixed case
    (Nyquist on one axis, resolved on another); a deliberately band-limited fixture states why
    (the dissipation identity is the standing example);
13. backend (GPU parity — remembering parity is shared-bug-blind, so an analytic oracle on some
    CPU lane must also cover the non-default shapes);
14. thread count (bitwise for the gated routes, tolerance for the two `Atomix` accumulators).

**The rule.** A new type parameter, constructor argument, or admissible input region is a new
axis: it gets a row in this list and a lane in the suite *in the same change*, or an explicit NA
with its reason. "Exhaustive" means exhaustive over this written list — an axis missing from the
list is the failure mode, so extending the list is part of extending the type system. The
cross-file permuted-layout lane (§2) and the anisotropic-box operator and radial testsets are the
reference implementations.


## 5. GPU testing

GPU testing is **opt-in and dependency-free for the package**. The default `Pkg.test()`
stays backend-free and portable; a GPU backend is only ever a *test* dependency. This is
possible because the data layer is generic over `AbstractArray`, FFT plans are built
through `AbstractFFTs` (dispatched on the array type), and allocations inherit their
backend via `similar` — so a field on a `ROCArray`/`CuArray` just works.

- **Per-backend environments** live under `test/gpu/` (`rocm/` and `cuda/`). Each
  is instantiated only on matching hardware (AMD at home, NVIDIA at the office); a no-GPU
  CI box never installs a vendor stack.
- A single **backend-agnostic** `test/gpu/suite.jl` holds the test logic. A thin
  per-backend entry script (`test/gpu/<backend>/runtests.jl`) supplies `to_device`,
  `device_functional`, `GPU_BACKEND`, and calls `<Backend>.allowscalar(false)` before
  including the suite. With scalar indexing disabled, any stray scalar index into device
  memory inside a package method *throws* — turning invariant 6 into a checked guarantee
  rather than a convention.
- **Strategy:** run the public surface on device arrays and compare against the trusted
  CPU result (`matches`, with an `atol` floor per §3). If no device is present the suite
  warns and skips.
- **Manifests are gitignored** (repo convention — none are tracked); each environment
  reproduces from its `Project.toml` plus a `[compat]` bound, via `Pkg.instantiate()`.

Run it on hardware:

```sh
julia --project=test/gpu/rocm -e 'using Pkg; Pkg.instantiate()'   # one-time
julia --project=test/gpu/rocm test/gpu/rocm/runtests.jl
```

Adding a backend = mirror `rocm/` (see `test/gpu/README.md`); the suite needs no changes.


## 6. Maintenance

- After any code-generation change, re-verify the **method set is unchanged**: update the
  counts in `test/method_parity.jl` only with a deliberate, reviewed reason, and keep
  `detect_ambiguities` empty.
- Keep the test summary in `CLAUDE.md` (roadmap item 4) roughly current.
- `Aqua.jl` (`test/aqua.jl`) runs `Aqua.test_all` on every `Pkg.test()` — ambiguities,
  unbound type parameters, undefined exports, project/compat consistency, stale deps,
  type piracy, persistent tasks. Keep it green; among other things it enforces that every
  dependency carries a `[compat]` bound.
- `JET.jl` (`test/jet.jl`) runs `@test_call` on the public operations, filtered to the
  package's own modules — a per-Julia-version static check for inference-detected errors
  (`MethodError`, `BoundsError`, undefined variables). It is left uncapped in
  `test/Project.toml` so each CI Julia version resolves a compatible JET. Note it analyzes
  the *running* version, so it does not catch version-divergence (that is the CI matrix's job).
- CI (`.github/workflows/CI.yml`) is **manual-only** — `workflow_dispatch` plus release tags, **not**
  every push: each commit is authored locally and the full matrix is run before pushing, so a
  push-triggered run would only re-verify what is already green (a tagged release additionally exercises a
  from-scratch clean-environment resolve, the one thing a single local run cannot give). The matrix is
  Julia 1.12 (the compat floor) at `-t1` and current stable at `-t4`, so both lanes run on one Julia and
  differ only in thread count — running them locally needs no manifest juggling. The floor was 1.11 until
  it was dropped: the package ran *faster* there, but every operation cost several times more to compile
  (`_assign!` alone 4.5×), which made the local suite take about six times as long for a Julia nothing in
  the fleet runs.
- **Performance is tracked separately**, not by `Pkg.test()`: the opt-in `benchmark/` suite and its
  coverage contract live in [`PERFORMANCE.md`](performance.md) (the third design companion).


## 7. Current coverage and known gaps

Honest status, so the contract above reads as the target rather than a description.

**Covered:** FFT round-trips; spectral multipliers cross-checked against
`AbstractFFTs.fftfreq`/`rfftfreq`; the Nyquist split both at the multiplier level and
end-to-end (the derivative wavenumber zeroed vs the squared wavenumber kept at the
Nyquist mode); M2 + M3 algebra and contractions in both representations, including the weighted
combination `combine!` (physical + spectral, alias-safe) and the physical-only determinant `det`
(against a per-point LU oracle, with its spectral absence asserted); the spectral
zero-mode constant invariant; the **point-value algebra** — the `Points` module's
M2 + M3 mirror of the *physical* field surface (storage-wise broadcasting), checked per-point
on CPU across `Float64`/`Float32` (`test/pointvalues_algebra.jl`) with the point-data types in
`test/interpolation.jl`; the in-place `!` forms with caller-supplied destinations
and the aliased in-place calls (`cross!`, `transpose!`, `sym!`/`skew!`/`dev!`, `curl!` — alias-safe by construction since decisions 38/39, bitwise-identical to non-aliased), plus the guard-free
aliased `helmholtz_projection!` (bitwise-equal to non-aliased; decision 32); the
kernel-composed operator forms (`helmholtz_projection!`/`divergence!` with a trailing kernel and
`α`/`β`, equal to the sequential operator-then-`convolve!` composition, with the ``\alpha = -1`` sign
fold and kernel-aliasing cases); the intentional absences in both representations (nonlinear products absent in spectral,
differential operators absent in physical) and the physical/spectral symmetry of every
linear field/fiber operation; the differential operators by
analytic round-trip, including an anisotropic ``(2\pi, 4\pi, 6\pi)`` box that exercises the
``2\pi/L`` wavenumber scaling; the fused `symmetric_gradient` (matching `sym(gradient)` exactly, plus its
own analytic diagonal on the anisotropic box); the vector-calculus identities ``\nabla\cdot(\nabla\times u) = 0`` and
``\nabla\times(\nabla\varphi) = 0``; element-type genericity on CPU (`Float64` and `Float32`, asserting
element-type preservation through operations); the 206-method field and 122-method
point-value parity baselines and zero ambiguities; `Aqua.test_all` (ambiguities, unbound type parameters, undefined exports,
Project/compat consistency, stale dependencies, type piracy, persistent tasks); the
operator adjoint/structural identities on randomized band-limited fields — divergence as
the negative gradient adjoint, self-adjoint curl, a self-adjoint negative-semidefinite
Laplacian (with the dissipation identity), and an exactly idempotent, self-adjoint Helmholtz
projection (decision 42; the full-spectrum Nyquist-content identities live in
`differentialoperators.jl`) — with the L² inner product computed inline (the global L² `inner` now lives in the
`Reductions` module, below); and GPU
parity on ROCm across `Float64` and `Float32` (`allowscalar(false)`) — the public field
surface (including the `mul!` ``\beta = 0`` / ``\beta \ne 0`` branches), confirmed on an AMD Radeon, plus
the **PointValues algebra**, the **interpolation / anterpolation transfer** (gather, atomic
scatter, accumulate, plus a heavy atomic-contention case), the **spectral transfer** (`DirectDFT`
and `NUFFT`), **convolution** (apply a Fourier kernel),
and the **L²/measure reductions** added alongside; and CPU threading — every threaded assignment is bitwise-identical to serial
(field ops, the codegen contractions/products including `mul!`'s ``\beta=0``/``\beta\ne0`` branches,
transpose/sym/skew/dev, norms, and the differential operators), exercised in both the
default and a `JULIA_NUM_THREADS=4` lane (`test/threading.jl`), with the override / cutoff
gate and the GPU `materialize!` fallback also asserted — and, separately, the
`KernelAbstractions` kernels, which thread by KA's own partitioning rather than through
`_assign!` and so cannot be checked by toggling `with_threading` at all: the disjoint-write gather
is asserted bitwise, including against a subprocess launched
at a different thread count, while the two `Atomix` accumulators (the anterpolation scatter, the
shell binning) are held to a tolerance because a nondeterministic summation order perturbs their
last bits. `helmholtz_projection!` is checked with the gated operations instead, decision 40 having
given it a CPU loop twin that the `with_threading` toggle does reach, and across thread counts as well ([`ARCHITECTURE.md`](architecture.md) §9); and the **L²/measure reductions**
(`test/reductions.jl`): `integral`/`mean`/`inner`/`l2norm`/`lpnorm`/`std`/`var`/`maximum`/`minimum`/`extrema` on physical
fields and point-values, against analytic oracles (``\langle \sin\rangle = 0``, ``\langle \sin^2\rangle = \tfrac{1}{2}``) and manual references,
across `Float64`/`Float32`, with the arithmetic-mean semantics on both bases (``\tfrac{1}{N}\sum`` grid, ``\tfrac{1}{M}\sum``
points), the extensive/intensive relation between ``\texttt{integral}`` and ``\texttt{mean}`` — the one is the other times the base measure — (incl. an anisotropic box), the
energy identity ``\tfrac{1}{2} \texttt{inner}(u,u) = \tfrac{1}{2}\langle |u|^2\rangle``, the **spectral Parseval `inner`/`l2norm`** (equal to the
physical inner, scalar/vector/tensor, on even- and odd-``N_x`` grids (``N_x`` the first-axis point
count) to hit both the Nyquist and
no-Nyquist branches), the **multiplier-weighted `weighted_inner`** ``\langle f, w g\rangle`` (the
``w \equiv 1`` reduction to `inner`, the ``w = |k|^2`` Dirichlet energy checked against both
``-\langle f, \Delta f\rangle`` and ``\langle \nabla f, \nabla f\rangle``, the idempotent-band identity
``\lVert w \star f\rVert^2``, and the ``f \leftrightarrow g`` symmetry — scalar/vector/tensor, spectral-only),
the **spectral zero-mode `integral`/`mean`** (equal to the physical reductions,
read from the DC coefficient; scalar/vector/tensor, even/odd grids, with `std`/`var`/`lpnorm`/`maximum`
still absent in spectral representation), the **shell-resolved Parseval inner** `radial_spectrum` (the radial power
spectrum ``P(\kappa)`` (``\kappa`` the wavenumber-shell magnitude), checked by the exact refinement ``\sum_\kappa P(\kappa) = \langle f, f\rangle`` over scalar/vector/tensor on
even-``N_x`` and odd-``N_x`` grids, plus the single-mode shell placement and its spectral-only absence),
its physical-space dual `radial_correlation` (the Wiener–Khinchin two-point autocorrelation, checked
against an **independent binned-circshift autocorrelation** and ``C(0) = \texttt{inner}(f,f)``, all orders /
both grids), the **two-field co-spectra** `radial_spectrum(f, g)` / `radial_correlation(f, g)` (the
cross-power / cross-correlation, refining the *mixed* `inner(f, g)`: analytical oracles — an orthogonal
pair ``\cos x \perp \sin x`` ⇒ zero, and ``\cos x \pm \cos 2x`` ⇒ ``\pm\tfrac{1}{2}`` in adjacent shells
cancelling to ``\texttt{inner} = 0`` (the co-spectrum **may be negative**); the ``f \leftrightarrow g``
symmetry; the ``g = f`` reduction to the single-field forms (bit-identical); and an **independent
binned-circshift cross-correlation** on a random pair — scalar/vector/tensor, both grids; the shared
``|k|``/``|r|`` shell binning is a single scatter-add pass — `KernelAbstractions` / `Atomix`, device-clean,
no scalar indexing (decision 25) — so these oracles plus the GPU parity suite also cover that histogram
kernel), the **mapped forms** (a leading function applied to the fiber value at every base point,
decision 30: the analytic invariants of a constant diagonal tensor — ``\det = 24``, ``\mathrm{tr} = 9`` —
the identity map reproducing the bare fiber-valued reductions, the analytic ``\langle \sin^2\rangle = \tfrac{1}{2}``,
the coincidence ``\max_n \lVert u_n\rVert = \lVert u\rVert_\infty`` linking `maximum(norm, u)` to the
materializing `lpnorm(u, Inf)`, a random tensor against an **independent explicit per-point reduction**,
the counting-measure forms on point-values, and the spectral absence of the whole family),
and the intentional absence of the *measure* reductions in spectral representation;
and **convolution** (`test/convolution.jl`): periodic convolution as the coefficientwise product
``\hat f \cdot \hat g`` with a `ScalarFieldSpectral` kernel, checked against the translation kernel
``\exp(-\mathrm{i} k_a m \Delta x_a)`` (a shift of ``m`` cells, with ``\Delta x_a`` the grid spacing along axis ``a``) ``\Leftrightarrow`` `circshift` along **all three axes, on scalar and vector fields** (an independent
physical oracle), the identity / scaling / cutoff kernels over **scalar, vector, and tensor (R=2)**
fields (the 5-D fiber broadcast), sharp-cutoff idempotence, kernel-composition associativity, the α/β
accumulate form (incl. R=2), in-place aliasing safety, a **mixed-parity (8,7,6) grid** (odd axis +
Nyquist), the **lazy exponential kernel** `exponential_convolve!` (decision 33: equality against the
same kernel stored and applied with `convolve!`, the independent single-mode eigenvalue oracle
``e^{c}\cos x``, the α/β accumulate, the scale-times-field offset, both two-operand forms equal to
the sequential `combine!`-then-convolve pair, and the in-place filtered accumulate), the
**kernel-composed `combine!`** (fused equals sequential over scalar and vector fields, the
``b = \texttt{dest}`` accumulate, the kernel aliasing the destination, and the physical absence), the `spectral_band` annular band-pass (`spectral_cutoff = band(0,k)`, idempotent, a ``|k|^2``
membership oracle) and `squared_wavenumber_field` (the ``|k|^2`` radial coordinate vs the analytic sum,
real-valued), across `Float64`/`Float32`, and the physical-space intentional absence on physical fields;
and — for `translation_kernel`, the displacement kernel of decision 28 — the same `circshift` oracle but on
a **random** field, which unlike the band-limited fields above carries Nyquist content and so exercises the
one frequency where the kernel is a real attenuation rather than a phase (a whole-cell displacement, odd and
even, along each axis), the exact **`DirectDFT` evaluation at the displaced nodes** as the oracle for a
sub-cell displacement, an analytic displaced cosine, the **reality check** that a displaced half-spectrum
survives a transform round trip (the inverse transform is the Hermitian projector, so a kernel built from the
true Nyquist phase would move), the Nyquist attenuation itself (a half-cell displacement annihilates
``\cos(4x)`` on an 8-point ``2\pi`` axis; a whole-cell one flips its sign), unit modulus on the resolved
band, composition and inversion, the fiber broadcast over vector and tensor fields, and the mixed-parity
grid;
the **point pair-correlation** (`rdf.jl`, decision 22 Phase 2): `assignment_window` against its
``\prod \operatorname{sinc}^2`` formula, and the FFT g(r) recipe (anterpolate density → deconvolve →
`radial_correlation`) validated against an **independent direct ``O(M^2)`` physical-space pair count** on a
clustered set (the clustering peak within ~10% and the g → 1 baseline);
and **property-based tests** (`randomized.jl`): algebraic laws on **random** fields, point-values, and
kernels over several trials — vector-space and contraction/product identities, transpose/sym/skew/dev,
the reduction laws (inner symmetry, linearity, Cauchy–Schwarz, ``\texttt{integral} = |\Omega|\cdot\texttt{mean}``), convolution
bilinearity/commutativity, and the operator identities ``\nabla\cdot(\nabla\times u)=0``, ``\nabla\times(\nabla \varphi)=0`` — which catch the
index/sign bugs that specific analytic functions can mask.

**Gaps:**

1. **Docstring doctests** — the Getting-started tutorial is doctested (§2, the third checked
   layer), but the per-function docstrings in `src/` do not yet carry their own `jldoctest`
   examples.
2. **Even-broader randomized coverage** — `randomized.jl` now covers the algebra, reductions, and
   convolution laws on random CPU data; extending property checks onto the device, and to more element
   types, is possible but lower-value (the laws are formula-level and backend-independent).
