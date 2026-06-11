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
  form*: `∂ₓ sin x = cos x`, `Δ sin x = −sin x`, `∇ × (0,0,sin x) = (0,−cos x,0)`, a
  Helmholtz-projected field is divergence-free. These catch sign, axis, and scaling
  errors that a self-consistent round-trip would silently reproduce.
- **Trusted reference** — for representation parity and for the GPU path. The CPU path
  is pinned by analytic oracles and the parity baseline; *then* another computation of
  the same quantity (the spectral form, or the same operation on a device array) is
  required to match it. This is still "two computations of one quantity," not a thing
  against itself.
- **Structural identities** — relations the operators must satisfy for *any* input: the
  vector-calculus identities (`div(curl) = 0`, `curl(grad) = 0`) and, on a periodic box,
  the adjoint relations (divergence as the negative gradient adjoint, self-adjoint curl, a
  self-adjoint negative-definite Laplacian, a self-adjoint idempotent Helmholtz
  projection). Tested on randomized band-limited fields, they pin the discrete
  energy/entropy structure of the scheme.

**The public method set is the spec.** Two mechanisms enforce this:

- the **parity baseline** (`test/method_parity.jl`) locks the per-generic method counts
  (198 public methods) so a code-generation change cannot silently add or drop a method;
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
- **Per-module behaviour files** — `fields.jl`, `fieldalgebra.jl`,
  `differentialoperators.jl`, `convolution.jl` (periodic convolution — apply a Fourier kernel),
  `interpolation.jl` (the point-data types),
  `pointvalues_algebra.jl` (the point-value M2 + M3 surface),
  `interpolation_transfer.jl` (the Lalescu-spline interpolation / anterpolation transfer kernels), and
  `reductions.jl` (the L²/measure reductions on fields and point-values), plus
  `eltype_genericity.jl` (Float64/Float32),
  `adjointness.jl` (operator structure on random fields), `aqua.jl` (package checks),
  `threading.jl` (CPU threading; runs in both the default and a `JULIA_NUM_THREADS` lane),
  and `jet.jl` (JET `@test_call` static analysis of the public operations).
- **`test/method_parity.jl`** — the spec-lock: per-generic method counts (the
  198-method field surface and the separate 118-method point-value surface) plus
  `detect_ambiguities` (from `Test`) over the whole package. The explicit `multiply!`
  quartet exists precisely to keep that ambiguity set empty.
- **`test/Project.toml`** — the test environment's dependencies, deliberately
  **backend-free** (see §5).
- **`test/gpu/`** — the opt-in GPU suite (see §5).


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
  `(sin x, sin y, sin z)` is irrotational *and* longitudinal, so both `curl` and the
  Helmholtz projection return ~0 and test nothing. Use a field whose components depend on
  more than one coordinate.
- For **cross-backend** comparison (GPU vs CPU), the two run the same formula and agree
  to roundoff, so compare with `isapprox(Array(device), host; rtol, atol)` carrying a
  small absolute floor.
- The same trap appears for **inner products of independent fields** (e.g. ⟨∇φ, u⟩): they
  are near-orthogonal, so the common value of two equal inner products is small relative
  to the operand magnitudes. Scale the floor by the Cauchy–Schwarz product `‖a‖·‖b‖`, not
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
- [ ] **An anisotropic domain** — at least one test with `Lx ≠ Ly ≠ Lz`, so the `2π/L`
      wavenumber scaling is actually exercised and a dropped length factor is visible.
- [ ] **The in-place `!` form** with a caller-supplied destination, including the
      **aliasing branch** for alias-guarded operations (cross, transpose, sym/skew/dev,
      the curl/Helmholtz wrappers) — and, for `mul!`, the LinearAlgebra no-alias contract.
- [ ] **Both α/β branches** for the five-argument kernels — overwrite (`β = 0`, which must
      ignore the destination's prior contents, NaN included) and accumulate (`β ≠ 0`).
- [ ] **GPU parity** — the result matches the CPU path on a device array, under
      `allowscalar(false)`.

**Grid coverage.** Use a **mixed-parity** grid (even and odd axis lengths, e.g.
`(8, 7, 6)`) so the Nyquist split is exercised; where the Nyquist mode matters, include a
field that actually populates it and confirm the derivative of a real field stays real.


## 5. GPU testing

GPU testing is **opt-in and dependency-free for the package**. The default `Pkg.test()`
stays backend-free and portable; a GPU backend is only ever a *test* dependency. This is
possible because the data layer is generic over `AbstractArray`, FFT plans are built
through `AbstractFFTs` (dispatched on the array type), and allocations inherit their
backend via `similar` — so a field on a `ROCArray`/`CuArray` just works.

- **Per-backend environments** live under `test/gpu/` (`rocm/` now, `cuda/` later). Each
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
- CI (`.github/workflows/CI.yml`) runs the full suite on push across Julia 1.11 (the compat
  floor) and stable, at `-t1` and `-t4` respectively.
- **Performance is tracked separately**, not by `Pkg.test()`: the opt-in `benchmark/` suite and its
  coverage contract live in [`PERFORMANCE.md`](performance.md) (the third design companion).


## 7. Current coverage and known gaps

Honest status, so the contract above reads as the target rather than a description.

**Covered:** FFT round-trips; spectral multipliers cross-checked against
`AbstractFFTs.fftfreq`/`rfftfreq`; the Nyquist split both at the multiplier level and
end-to-end (the derivative wavenumber zeroed vs the squared wavenumber kept at the
Nyquist mode); M2 + M3 algebra and contractions in both representations; the spectral
zero-mode constant invariant; the **point-value algebra** — the `Interpolation` module's
M2 + M3 mirror of the *physical* field surface (storage-wise broadcasting), checked per-point
on CPU across `Float64`/`Float32` (`test/pointvalues_algebra.jl`) with the point-data types in
`test/interpolation.jl`; the in-place `!` forms with caller-supplied destinations
and the alias guards (`cross!`, `transpose!`, `sym!`/`skew!`/`dev!`, `curl!`,
`helmholtz_projection!`); the intentional absences in both representations (nonlinear products absent in spectral,
differential operators absent in physical) and the physical/spectral symmetry of every
linear field/fiber operation; the differential operators by
analytic round-trip, including an anisotropic `(2π, 4π, 6π)` box that exercises the
`2π/L` wavenumber scaling; the vector-calculus identities `div(curl u) = 0` and
`curl(grad φ) = 0`; element-type genericity on CPU (`Float64` and `Float32`, asserting
element-type preservation through operations); the 198-method field and 118-method
point-value parity baselines and zero ambiguities; `Aqua.test_all` (ambiguities, unbound type parameters, undefined exports,
Project/compat consistency, stale dependencies, type piracy, persistent tasks); the
operator adjoint/structural identities on randomized band-limited fields — divergence as
the negative gradient adjoint, self-adjoint curl, a self-adjoint negative-definite
Laplacian (with the dissipation identity), and a self-adjoint idempotent Helmholtz
projection — with the L² inner product computed inline (the global L² `inner` now lives in the
`Reductions` module, below); and GPU
parity on ROCm across `Float64` and `Float32` (`allowscalar(false)`) — the public field
surface (including the `mul!` `β = 0` / `β ≠ 0` branches), confirmed on an AMD Radeon, plus
the **PointValues algebra**, the **interpolation / anterpolation transfer** (gather, atomic
scatter, accumulate, plus a heavy atomic-contention case), **convolution** (apply a Fourier kernel),
and the **L²/measure reductions** added alongside; and CPU threading — every threaded assignment is bitwise-identical to serial
(field ops, the codegen contractions/products including `mul!`'s β=0/β≠0 branches,
transpose/sym/skew/dev, norms, and the differential operators), exercised in both the
default and a `JULIA_NUM_THREADS=4` lane (`test/threading.jl`), with the override / cutoff
gate and the GPU `materialize!` fallback also asserted; and the **L²/measure reductions**
(`test/reductions.jl`): `integral`/`mean`/`inner`/`l2norm`/`lpnorm`/`std`/`var`/`maximum` on physical
fields and point-values, against analytic oracles (`⟨sin⟩ = 0`, `⟨sin²⟩ = 1/2`) and manual references,
across `Float64`/`Float32`, with the arithmetic-mean semantics on both bases (`(1/N)·Σ` grid, `(1/M)·Σ`
points), the extensive/intensive `integral = measure · mean` relation (incl. an anisotropic box), the
energy identity `½ inner(u,u) = ½⟨|u|²⟩`, and the physical-only intentional absence on spectral fields;
and **convolution** (`test/convolution.jl`): periodic convolution as the coefficientwise product
`f̂·ĝ` with a `ScalarFieldSpectral` kernel, checked against the translation kernel
`exp(-i kₓ m Δx) ⇔ circshift` (an independent physical oracle), the identity / scaling kernels,
sharp-cutoff idempotence, kernel-composition associativity, the α/β accumulate form, in-place aliasing
safety, across `Float64`/`Float32`, and the physical-space intentional absence on physical fields.

**Gaps:**

1. **Doctests** — the plumbing exists (`doctest = true`, `DocTestSetup`), but no
   `jldoctest` examples have been written into the docstrings.
2. **Broader randomized/fuzz coverage** — the structural identities now run on randomized
   band-limited fields; extending randomized inputs across the rest of the algebra would
   broaden coverage further.
