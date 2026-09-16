# Code facts (from the two inventory agents, 2026-09-16). file:line are PF unless marked IT.

## Cheap / free
- `Grid3D` second type parameter: 76 spellings, but 58 are `::Grid3D{T}` SIGNATURES (non-breaking UnionAll) and 13 are
  `G<:Grid3D{T}` BOUNDS (non-breaking). Only ~6 real edits: 2 ctor calls (Fields.jl:152,175), 1 concrete struct field
  (Fields.jl:1792 multipliers), 2 in NUFFT (Interpolation.jl:1712,1714), 1 display (Fields.jl:2334).
- `FieldSpectralMultipliers`: every consumer indexes a per-axis vector BY LOCAL MODE INDEX
  (DifferentialOperators.jl:360-371,193-215,417,505,583,669; Convolution.jl:1286,1307; Reductions.jl:1243-1259).
  ⇒ slicing the six vectors to the rank's local mode range makes ~28 operations correct with ZERO kernel edits.
  Must keep GLOBAL: `2π/domain_length`, the `iseven(n)` Nyquist zeroing, the six length validations (Fields.jl:1840-1845).
  `Canonical` (14 type params, 3 POSITIONAL matchers: `_is_canonical`, `adapt_structure`, Convolution's static collapse).
- Fiberwise algebra (31 ops), differential operators (16), convolution appliers (12) are UNCHANGED by decomposition —
  element n → element n. This is §2's vertical/horizontal split paying off.
- `similar` on `CuArray{T,N,UnifiedMemory}` PRESERVES the memory kind ⇒ `similar_field` already works for spill.
  Not asserted anywhere.

## Defects that exist TODAY
- **Family-taking constructors destroy the memory kind** (Fields.jl:893-896 `_allocated_field_storage`:
  `wrapper = Base.typename(family).wrapper; wrapper{S}(undef, shape)`). Ask for `CuArray{Float64,3,UnifiedMemory}`,
  get device memory, silently. `_check_family_element_type` (908-919) vets only the element type. [SPILL BLOCKER]
- `_storage_family` (Fields.jl:1157-1160) erases every parameter ⇒ unified and device arrays are the SAME family
  (they mix with no complaint — right for interop, but nothing can express residency, incl. the display).
- THREE one-level `parent` spellings still un-unified: Fields.jl:1966-1970 (`_check_multipliers_compatibility`),
  Interpolation.jl:1080 (`_check_transfer_colocation`), Interpolation.jl:1907-1908 (NUFFT). They answer the INNER
  wrapper where `_same_backend` answers `CuArray` — a live divergence the moment any wrapper type appears.

## Hard blockers
- `_check_owned_storage` (FiberSections.jl:119-126, called from all 6 field ctors + 4 point ctors) rejects a `SubArray`
  ANYWHERE in the parent chain ⇒ halo padding with an interior view is UNCONSTRUCTIBLE. Either a `HaloArray` that owns
  its buffer and exposes the interior without a SubArray, or relax decision 59 with a replacement property.
- `_spectral_zero_mode_data` (Fields.jl:1663, +1668-1670) hardcodes the DC mode at LOCAL (1,1,1) ⇒ on a non-owning rank
  every `+ constant` and every spectral `integral`/`mean` writes/reads the wrong mode. SILENT WRONG ANSWER.
  Consumers: FieldAlgebra.jl:270,276,290-296,310-316; Reductions.jl:708-723.
- `FieldTransformPlans` (Fields.jl:1337-1363) holds ONE plan pair, ONE shape. A pencil transform needs an input AND an
  output decomposition + a communicator; `adapt_structure` (2608-2630) rebuilds from shapes alone and cannot carry a
  communicator. BUT `_forward_components!`/`_inverse_components!` (1444-1472) already apply ONE 3-D transform per
  contiguous component — so the replacement is the `mul!`, not the loop. Decision 76 turns out to help here.
- Reality condition: `_reality_residual_plane` (2641-2653) pairs via whole-array `reverse`+`circshift` spanning the FULL
  non-folded axes; `_owns_pair` (2743-2745) assumes both members addressable. Under a split of a non-folded axis the
  partner is on another rank. FIX: one PAIRWISE block exchange with the mirror rank per stored plane; then each rank
  computes m=(x+conj(y))/2 for its OWN elements and `_owns_pair` is not needed at all (B's m' = conj(A's m)).
  Size at 1024^3, 4 ranks: a kx-plane block is ~4 MiB ⇒ ~27 µs on NVLink against ~10 ms for the transform. Negligible.
- Every terminal reduction needs an Allreduce (Reductions.jl table): scalar, FiberVector(3), FiberTensor2(9),
  NTuple{n} (decision 72's tuple form — one Allreduce of n reals keeps the decision's point), and TWO O(N) shell
  vectors for the radial pair. Shell count MUST be computed from the GLOBAL corner or ranks disagree on bin count.
  `radial_correlation`'s kernel uses minimum-image from the GLOBAL index (Reductions.jl:1399-1401).
- Bitwise thread-count invariance (the fixed tree, Reductions.jl:305-323) does NOT extend across ranks. New tolerance
  class, same shape as the existing Atomix exemption (threading.jl:340-341).
- Invariant-4 global sites: `_spectral_constant_scale` (1655), `_base_count` (Reductions.jl:107),
  normalizations at Reductions.jl:884,1167,1202,1294,1526,1539, `var` count at 731 — all must stay GLOBAL.
- HDF5 ext writes `g["data"] = Array(field_data(field))` (ext:61) — whole array, one writer, no hyperslab, no
  MPI-IO fapl, and the attributes would claim the slab is the box.

## Point/transfer layer
- One stencil for all spline schemes: `2n+2` nodes at offsets {-n … n+1} (Interpolation.jl:169,975-979).
  ⇒ halo is ASYMMETRIC: n below, n+1 above. CatmullRom (n=1): 1/2. Lalescu(3,3): 3/4. NUFFT window W=12 default ⇒ 6
  oversampled = 3 coarse cells, but NUFFT owns a GLOBAL 8x-oversampled FFT anyway.
- `_wrap_step` (954) hardcodes "the array's extent IS the period" ⇒ a sub-box array silently folds the stencil back
  onto the rank's own far side. `_locate` (417-421) has no range check and no notion of "not mine".
- Scatter: `Atomix.@atomic` into wrapped indices (1050); the α/β prescale is applied to the WHOLE array before launch
  (1259-1263) — must not touch ghost cells twice. Conservation would still pass a total-mass check while being wrong.
- `point_traversal_order` keys from grid_size/domain_size/origin and SATURATES out-of-range points (596-602) ⇒ it is
  not an ownership test. Scratch refuses a different grid (927-932) ⇒ rebuild after every migration.
- `PointSet` is ONE owned (M,3) array (Points.jl:125-135); `npoints = size(positions,1)`. Migration changes M ⇒
  realloc (a capacity array with a live view is blocked by `_check_owned_storage`). Every `PointValues` beside it must
  be compacted identically. **There is NO point identity — a point IS its row index.**
- `DirectDFT` is all-to-all both ways (every point needs every mode; every mode needs every point).

## Tests / benchmarks (what a distributed lane must satisfy or be exempted from)
- allocations.jl: `@alloc_below threshold interpolate!/anterpolate!` (304,306), `point_traversal_order!` rebuild bound
  4096*nthreads (329-330), `displace!`/`wrap!` (338-339) ⇒ a halo exchange allocating per call FAILS these.
- pass_audit.jl: gather frozen at `3*4^3*M` reads (393-396); `anterpolate!` and `point_traversal_order!` are already
  recorded exemptions (438,440).
- method_parity.jl: 206 / 122 / per-module (Fields 130) — ANY new verb refreezes these in the same commit.
- threading.jl: the GATHER is asserted bitwise-exact (336-337); the SCATTER is already tolerance-only (340-341).
- GPU suites are single-process `julia --project=test/gpu/<backend>`; an MPI lane needs a launcher, a gathered oracle,
  a 4-process result reduction and rank-aware device binding. benchmark baselines are named <host>-<backend>[-tN]
  with no rank field.

## Consumer (IT)
- Per step (RK3/TwoThirds/no scalar): 18 c2r + 9 r2c scalar-equivalent transforms; 41 spectral + 10 physical
  full-field passes; resident 4 spectral vectors + 2 physical vectors.
- PF call sites: to_physical! 16, to_spectral! 5, convolve! 14, combine! 11, weighted_inner 8, exponential_convolve! 8,
  reality_projection! 7, helmholtz_projection! 7, radial_spectrum 1, maximum(norm,·) 2.
- ~14 scalar-reduction sites become collectives (Observables.jl:79,137,140,169,215,255,281,349,353,382; Forcing.jl:438,731,787,906; SimulationRun.jl:948).
- `random_solenoidal_velocity_spectral!` builds the WHOLE field from one RNG stream host-side (State.jl:156, scalar :257);
  tracer seeding likewise (Particles.jl:172) ⇒ a decomposition changes the realization for a given seed.
- Tracers: `Tracers{positions, scheme, unwrapped_positions}` (Particles.jl:152-157), CatmullRom default; the velocity
  history ring (Cache.jl:150-152) and ParticleIntegratorBuffers (Particles.jl:378-386) are all M-indexed.
- IT has NO MPI anywhere. `FixedDomain` carries a storage family and nothing else about placement.
- Two frozen audits (memory_audit BASE, compute_audit PASSES/TRANSFORMS) become per-rank ledgers.
