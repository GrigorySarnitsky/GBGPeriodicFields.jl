# Rulings for revision 2 of DESIGN.md (binding). Apply with every item of the three REVIEW-*.md files.

R1. FLIP THE SPECTRAL SPLIT. §4.5's layout becomes:
      physical (folded axis + one other whole; the third split)
      --r2c on the folded axis + fft on the second, both local--> ONE all-to-all -->
      spectral (folded axis and the third whole; the SECOND axis split) --fft on the third, local-->
    i.e. THE FOLDED AXIS IS NEVER SPLIT, in either representation. Reasons (HPC attack 3, invariants A1/A3):
    the Parseval weight, `inner`'s two correction planes, the radial α, the reality plane selection and the
    `iseven(n)` test ALL key off the folded axis by local index; N/2+1 is ODD at every power-of-two grid
    (513, 257, 1025) so no even rank count divides it; and splitting dim 2 gives 8 KiB contiguous pack runs
    against dim 1's 2 KiB. Price, stated: the reality pairing now crosses ranks and pays the mirror exchange.
R2. THE MIRROR EXCHANGE HAS TWO PEERS, NOT ONE. The `+1` in `mod(-(j-1),n)+1` shifts the mirrored block
    across a rank boundary: rank r mirrors to all of rank P-1-r except one plane, plus exactly one plane of
    rank P-r. One Recv against two Sends is a hang. State it, and size every buffer `cld(n,P)`.
R3. THE AXES ARE DERIVED FROM `layout.fft_dims`, NEVER HARDCODED x/y/z. Decision 41 runs three folds across
    the suite; the distributed lane must run at least two.
R4. DELETE the decision-45 "exactness" argument (§4.4) — it checks a property of the GLOBAL grid and cannot
    reject anything about a rank count; the mechanism cited does not exist. Replace with: the split axis is
    divided `cld(n,P)`, local shapes MAY differ by one, therefore the transpose is `Alltoallv` with per-rank
    tables, and NO control flow may depend on a local shape. Name the consequence the reviewer found:
    `_component_offsets_align` (Fields.jl:1378-1384) computes from the local shape, so `component_scratch`
    could be `Nothing` on one rank and an array on another, making `FieldTransformPlans` a different
    concrete type per rank — it must be decided from the GLOBAL shape.
R5. ADD FOUR SILENT-WRONG-ANSWER SITES to the §6 invariant-4 list (they are the same class as the zero mode):
    (a) `Interpolation.jl:1146,1265` pass `prod(grid.grid_size)` as `points_per_fibre` and the kernels do
        `length(field_values) ÷ points_per_fibre` (:974,1032) ⇒ global grid + local storage gives 0 for P>3,
        the fibre loop never runs and `interpolate!` returns its destination UNTOUCHED. This defect is
        CREATED by the design's own ruling. Rule: kernels that index storage take the LOCAL shape and its
        product; only normalizations take the grid. Same at the NUFFT kernels (:1946,1978); `DirectDFT`'s
        `1/prod(grid.grid_size)` (:1500) stays global.
    (b) the six multiplier length validations (Fields.jl:1838-1845) compare against `field_spectral_shape`,
        which §4.4 makes LOCAL ⇒ they must become local. §4.2 said keep them global; §4.2 was wrong.
    (c) `_radial_spectrum_bin`'s shell count from `maximum(squared_wavenumber_1..3)` (Reductions.jl:1267-1269)
        becomes a LOCAL corner once the vectors are sliced ⇒ ranks allocate different bin counts ⇒ the
        ill-formed Allreduce. The per-axis maxima are a FOURTH thing that must stay global.
    (d) `radial_correlation`'s minimum-image needs the rank's index OFFSET, not only the global extent.
    Also: `_base_count` for a decomposed `PointSet` is the global M; `_locate` + `@inbounds` means an
    out-of-slab point is memory corruption, not a `BoundsError`.
R6. `Grid3D` MUST STAY `isbits`. `_same_grid` is `===` (no `==` is defined), so a partition holding an
    `MPI.Comm` (mutable) turns grid equality into POINTER identity and every two-field operation throws the
    moment sub-communicators are used — which R1's transport recommends. The partition stores the raw
    `MPI_Comm` handle plus rank and size, all bitstypes. Belongs in stage 2, not stage 3.
R7. INVARIANT 14 IS NOT THE REFUSAL. By `_storage_family` two CuArray-backed fields are the SAME family
    whatever their partition; what differs is the GRID. So a distributed/local mix is a GRID refusal
    (already enforced once R6 keeps `==` value-based), `redistribute!` is a BASE conversion beside neither
    `adapt` nor `adapt!`, and its gate belongs in `test/peer_rejections.jl`, not `test/adapt.jl`.
R8. DECISION 59 / HALOS. The property ownership stands in for is "one section's element n is another's
    element n", and it is NOT per-field: `_fiberwise_pass!` launches `ndrange = length(targets[1])` under
    `@inbounds`, so a halo field beside a plain field on the same grid reads out of bounds with no error.
    `_check_same_domain` needs a HALO-WIDTH EQUALITY clause and a halo field must refuse a non-halo peer.
    Decision 59 also makes three `===` shortcuts exhaustive (the scratch arity's anti-alias test
    Fields.jl:1541-1544, `adapt!` :2554, `reality_projection!`'s `destination !== source` :2846) — a
    `HaloArray` preserves them only if it can NEVER be constructed as a window onto another section's buffer.
R9. TEST INTEGRITY: an extension is invisible to the derived ledgers (method parity, the oracle registry,
    the method ledger, the survey), so putting the distributed surface in an extension would remove
    invariant 1's enforcement from the largest addition the package has made. RULE: every new GENERIC and
    every new TYPE is declared in core (so the ledgers see them) and only the MPI-specific METHODS live in
    the extension — the `write_field` precedent exactly. State this, and state that the ledgers must be
    extended to count extension methods or the gap is recorded.
R10. INVARIANT 11's SIZE CONTRACT IS AMENDED (unstated in rev 1): the inverse c2r destroys its input and,
    distributed, consumes the unpack destination; honouring decision 64's preservation promise needs scratch
    of one local spectral field PLUS the pack/unpack pair, not one field.
R11. HONEST NUMBERS. The capacity table gets an overhead line (3-6% for context/OS/fragmentation) and a
    SPILLED FRACTION column, and states the failure mode at the ceiling: `cuMemAllocManaged` never returns
    OOM — the OS kills the process on the page fault. Delete "at GPU speed" from the 1650³ row: 54% of the
    live set in LPDDR is ~5x slower by the design's own ~9x figure. Revise the cost model: the design chose
    SLAB, so ONE all-to-all per transform, not two (the draft computed pencil); and multi-node needs the
    pencil generalisation slab does not give.
R12. THE SPILL ALLOCATOR IS AN OPEN QUESTION, NOT A SOLVED ONE. `KA.allocate(...; unified=true)` is
    `cudaMallocManaged` — the MIGRATING allocator the hardware notes recommend AGAINST for streaming access
    with no reuse. Stage 1 must A/B three candidates on Arrhenius (managed, pinned-host, plain host memory
    via ATS) before the package blesses one. Keep the KA spelling as the portable surface; do not claim it
    is the right mechanism.
R13. NUMA BINDING decides a 3x (own-Grace 450 GB/s vs peer 150) and is absent from rev 1. Add it to the
    process model and to stage 6's definition of done, with a run-time affinity check.
R14. GPU-AWARE MPI NEEDS A FALLBACK. The pack/unpack layer selects device-direct or host-staging at run
    time; this de-risks the home box, the office box and Arrhenius at once, and it falsifies rev 1's
    "everything is testable at home" unless it exists.
R15. MEASUREMENT. Strong-scaling efficiency needs a single-device control that does not exist at the sizes
    that justify feature B. State acceptance as ABSOLUTE throughput against the roofline (achieved GB/s per
    GPU; achieved all-to-all GB/s against 150 GB/s per pair), and add a device vector-transform mechanism to
    the canary, which the package already knows is blind there.
R16. STAGING CHANGES. (a) Split `aarch64` out as its own first step — build + `Pkg.test()` on a Grace node
    before anything distributed runs there. (b) Persistence moves BEFORE the first distributed solve: a
    1024³ warm-up is months of wall clock and therefore a chain of 15-30 Slurm jobs, so checkpoint-restart
    is what makes the resolution possible at all, and stage 3 as written cannot checkpoint (four writers each
    claiming the whole box). (c) Stage 1's promised allocation row is VACUOUS (CPU `@allocated` cannot see
    unified memory) — replace it with a residency assertion. (d) A CUDA-only suite axis breaks the 491/491
    ROCm/CUDA parity the package treats as an invariant — state how the counts stay comparable.
R17. DEADLOCK RULE, RESTATED. "A collective in a conditional" is the WRONG rule: the consumer has five such
    sites today and all five are correct because the predicate is rank-uniform. The invariant is over
    PREDICATES — any predicate gating a collective must be rank-uniform — and the enforcement is
    `Allreduce(keep, &)` at `run!`'s user-supplied `keep` (SimulationRun.jl:1106), which is the real hazard.
    Add: `MPI_MAX` has no standard-defined NaN behaviour, so the consumer's blow-up guard can go silent.
R18. THE CONSUMER SECTION GAINS THE SILENT-PHYSICS FINDING: `Forcing.jl:902` draws `randn!` inside the hot
    loop; under SPMD every rank draws the same stream, so each slab gets identical noise ⇒ slab-periodic
    forcing exciting only k ≡ 0 (mod nranks) on the split axis, and after band-pass, Leray projection and
    variance normalisation it LOOKS correct. Same class at `State.jl:156,:257` (a degenerate field, not a
    different realization). This is the worst defect class in the document and belongs in §1, not §8.
    Also: §5's example is unwritable in IT as it stands (IT never builds a `Grid3D`; `FixedDomain` does), and
    `ScalarFieldPhysical(f, grid, …)` (Fields.jl:467-479, vector twin :612-627) allocates a LOCAL shape but
    loops the GLOBAL `grid.grid_size` and offsets from the global origin ⇒ BoundsError on every rank. Fix:
    iterate the local range, compute the coordinate from the GLOBAL index.
R19. §11 IS REWRITTEN AS THREE OPTIONS, fairly compared, with the threshold stated:
     (i) STAGE 0 ONLY — fix the now-six live defects; fully verifiable on the owner's hardware; no scope change.
     (ii) FEATURE A ONLY — and its honest case is NOT "~1040³" (which needs 55% of a hot live set spilled,
          ~20x wall time) but 1024³ FLOAT32 VELOCITY-ONLY ≈ 108 GiB against 96 GiB: a 12% gap closed at
          ~1.2x per step, no MPI.
     (iii) ENSEMBLE PARALLELISM as the zero-cost baseline feature B must beat: on a scheduler allocating
          whole 4-GPU nodes, four independent runs on one node is 4x the throughput of one 4-GPU run.
     And state the threshold plainly: IT's corpus names 128³ (x18), 256³ (x16), 384³ (x2) and NOTHING above.
     512³ Float64 is ~27 GiB against 96 GiB HBM and needs neither feature. Feature B is aimed three to four
     octaves above anything the consumer has recorded as a target, so the ruling the owner must give first
     is the science one.
R20. Keep every DEFEATED finding the reviewers recorded, so they are not re-raised: the differential
     operators' zero-mode/Nyquist cases are VALUE tests (`ifelse(iszero(squared),…)`), not index tests —
     that single fact is what makes the 59-unchanged claim true; the kernel builders ride on the sliced
     per-axis arrays for free, decision 28's Nyquist split included; `similar_field`, the six family
     constructors and `_wrap_field` all route through the two shape functions; `Grid3D{T,P}` really is ~6
     edits — but the multipliers site needs a 15th type parameter, which moves `Canonical` and breaks three
     positional matchers at once (`_is_canonical`, `adapt_structure`, Convolution's static collapse).

## Addendum (from the two later reviews)
R21. NAME THE PARSEVAL SITES. The rfft multiplicity α(k) is read from the LOCAL folded index at three
     places — `Reductions.jl:945-953`, `:895-897/911-913`, `:1249-1252/1283-1291` — giving a systematic
     ~0.2% bias in the kinetic energy that drives IT's forcing. Under R1's layout they are correct unchanged;
     say so, and say what they would have cost under the rejected layout.
R22. `reality_residual`'s `stored_planes = (1, size(data, folded))` (Fields.jl:2701-2702) takes the plane
     numbers from the LOCAL extent: under a folded-axis split EVERY rank would project its own first and last
     local plane — corrupting six interior planes at P=4 while LOWERING the reported residual. This is the
     sharpest single argument for R1 and belongs beside it.
R23. `KA.allocate(backend, T, dims; unified)` takes a BACKEND INSTANCE where the decision-74 constructors
     hold a TYPE. Name the mismatch; the constructors need a backend, or a type→backend resolution step.
R24. A THROW ON ONE RANK IS A DEADLOCK. PF validates by throwing at ~40 sites and several become
     rank-dependent under uneven division; add it to the deadlock section beside the predicate rule.
     Also note GC-as-collective-jitter from the documented bounded allocators.
R25. STATE THE SILENT AMENDMENTS the reviewers found: decision 37 is DEMOTED by this proposal (and four open
     roadmap items dissolve with it); `test/display.jl`'s derived struct-completeness gate is an unlisted
     definition-of-done item in every stage; and broadcast promoting a mixed pair to unified makes residency
     argument-order-dependent.
R26. Keep the reviewers' own framing where it is sharper than mine: "the enumeration is the right method — it
     was simply run incompletely" (the zero-mode class), and "true in count, wrong in kind" (the ~6 edits).
