# Adversarial review — the consumer's advocate (attacks 2, 5, 6, 9)

Lens: I must run `GBGIsotropicTurbulence` (IT) on Arrhenius and get physics out. Every IT `file:line` was read this session; PF citations are from `src/` at HEAD.

## A. Attack 2 — deadlocks and hangs

§4.6 is the whole deadlock story: *"A collective in a conditional deadlocks … the mitigation is documentation
plus an opt-in debug mode that Allreduces a collective-sequence counter."* Wrong rule, wrong instrument.

**A1. The rule is backwards; IT's hazard is its converse. VERDICT: UNPROVEN.** IT already has five
collectives inside conditionals and every one is *correct*:
`SimulationRun.jl:1193-1195` (a sample-cadence test gates `scalar_variance` **and** `derivative_skewness`,
which contains a distributed transform, `Observables.jl:346-353`); `Forcing.jl:440-443` (early return out of
`project_forcing!` mid-step); `Forcing.jl:774-776` (the same clamp on the **default** `VarianceController`
path); `SimulationRun.jl:1311-1321` (`if ε > 0 … else @warn; return false`, which stops the run);
`Observables.jl:350`. All five are safe only because their predicates are functions of Allreduce'd values.
A lint for "collective inside `if`" gives five false positives and zero defects; a sequence counter reports
agreement and finds nothing.
**Repair:** state the invariant over *predicates* — any predicate gating a collective, or deciding loop
continuation, must be a pure function of collective-reduced values — and name the verb that discharges it
(`MPI.Allreduce(pred, &, comm)`). The counter then *checks* that invariant instead of replacing it.

**A2. `run!`'s termination predicate is an unguarded rank-split. VERDICT: BREAKS.**
`SimulationRun.jl:1100-1108`: `keep = callback(sim); keep || break; advance!(sim; dt)`. `callback` is
arbitrary user code run on every rank. A rank returning `false` while another returns `true` leaves the
survivors in `advance!` and its 5–8 collectives (B4) — hang, no error, no output. This is the deadlock a real
IT user hits first, because the documented idioms invite it: `sim -> current_step(sim) < n` is safe;
anything reading a float, a wall clock, a file, or `rand()` is not. §5 says only "reductions must not sit
inside rank conditionals", which does not cover a conditional containing no reduction.
**Repair:** `keep = MPI.Allreduce(keep, &, comm)` inside `run!`. One line, closes the class.

**A3. The blow-up guard can fire on some ranks, or none. VERDICT: BREAKS, unmentioned.**
`SimulationRun.jl:892,899`: `isfinite(max_speed(sim.cache)) || error(…)`, where
`max_speed(u) = maximum(norm, u)` (`Observables.jl:215`) becomes `Allreduce(…, MPI_MAX)`. **The MPI standard
does not define `MPI_MAX` for NaN**, and the usual `if (a > b)` kernels drop NaN because every comparison
with NaN is false. A rank whose slab went non-finite can contribute a finite maximum, so the guard IT added
so that *"the iteration refuses to report success on a state it has just made non-finite"* stops working.
And `error()` inside SPMD is an unmatched exit: if one rank does throw, the rest hang on the next collective.
**Repair:** reduce finiteness explicitly (`Allreduce(isfinite(local), &)`) rather than inferring it from a
`MAX`; require every step-path `throw` to be preceded by an Allreduce of its predicate, or `MPI_Abort`.

**A4. Stage 3 ships a solve that cannot checkpoint, and checkpointing is where ranks throw. VERDICT:
BREAKS.** Persistence is stage 4; §4.9 records `write_field` as `g["data"] = Array(field_data(field))` — one
writer, whole array, attributes claiming the slab is the box. At stage 3 a consumer gets either four files
each claiming to be the full box (silent), or three ranks throwing on a shared HDF5 handle while rank 0
proceeds (hang). See D2.

**A5. Rank-duplicated diagnostics.** `@warn … maxlog = 1` (`Forcing.jl:441,774`) dedups per *process*, so
"one warning" becomes four; `@info` at `SimulationRun.jl:532` likewise — ~12 sites behind §5's one clause.

## B. Attack 6 — "one line differs" and the hot loop

**B1. §5's one changed line cannot be written by an IT user. VERDICT: BREAKS.** IT never constructs a
`Grid3D` in user code: `FixedDomain(; grid_points_per_axis, side_length, dealiasing, element_type,
array_type)` (`SimulationDomain.jl:289`) builds it, and `Simulation(grid_points_per_axis = 1024, …)` builds
the `FixedDomain`. A `partition` keyword must be threaded through both IT entry points before any consumer
line changes. §5 measures the diff at PF's API, not at the one the consumer uses.

**B2. IT's frame construction throws on a partitioned grid. VERDICT: BREAKS (loudly, at least).**
`SimulationDomain.jl:299`: `VectorFieldPhysical((x, y, z) -> …, grid; array_type)`. PF's function-initialized
constructors (`Fields.jl:467-479`, `:612-627`) allocate `field_physical_shape(grid, …)` — **local** under
§4.4 — then loop `for k in 1:grid.grid_size[3], j in …, i in …` — **global**, since §4.4 rules the grid stays
global — writing `values_at_grid[i,j,k]` and computing `x₀ + (i-1)Δx` with no rank offset. Every IT run's
first line is a `BoundsError`. §4.4's *"every allocator routes through those two functions, so … all keep
working untouched"* is false for exactly these two, which are allocators that also *index*.
**Repair:** name them as a fourth stage-2 edit site; "~6 real edits" becomes ~8.

**B3. Feature A never reaches this consumer. VERDICT: BREAKS.** `SimulationDomain.jl:283` is
`_zeros(array_type, S, dims) = fill!(array_type{S}(undef, dims...), …)` — IT's own copy of the §3.2 defect —
and `:462-493`'s `new_*_field_*` use PF's family-taking constructors, which §3.2 says destroy the memory
kind. `FixedDomain` holds `storage_family::SF`, one global setting, so even after stage 1 IT can express
*all unified* or *none* — and §3.4 says all-unified is the ~9× case never to choose. §11's *"the consumer
changes nothing"* is false for the cheap alternative too.
**Repair:** scope an IT-side per-field residency policy inside stage 1, or say plainly that stage 1 delivers
nothing to IT until IT does its own work.

**B4. The hot loop gains 5–8 blocking global barriers per step.** The default run
(`velocity_forcing = VarianceController(domain; target = kinetic_energy)`, `SimulationRun.jl:549-551`;
`IFLowStorageRK3`) executes per step: 3 × the 3-tuple `weighted_inner` in `add_forcing_source!` (one per
stage), 3 × `_injection_amplitude`'s branch on it, 1 × `max_speed` in `deposit!`, 1 × `scalar_variance` in
`advance!`, plus `kinetic_energy_and_dissipation` per step under `warmup!`. The *call sites* are textually
unchanged — that much of §5 holds — but each becomes a synchronisation point where none existed, and four
gate a branch. §4.6 treats reductions purely as a correctness problem and never states the step-level count.
It also invalidates IT's recorded rationale for decision 72's tuple form (*"one blocking device-to-host
readback instead of two"*): the readback is no longer the dominant latency, the barrier is.

**B5. A documented IT equality stops holding. VERDICT: UNPROVEN.** `kinetic_energy_and_dissipation`'s
docstring asserts the dissipation is *"bitwise identical to its single call"*, and `Forcing.jl`'s 3-tuple
comment *"Bitwise identical to the separate calls."* Both hold under an Allreduce only if the tuple and
scalar forms reduce over identical trees; §4.6's "one Allreduce of *n* reals" does not require that.

## C. Reproducibility, seeding, and restart

**C1. `StochasticOU` draws the *same* noise on every rank — a silent wrong forcing. VERDICT: BREAKS.**
`Forcing.jl:902`, in the per-step `prepare_forcing!`: `randn!(ou.rng, field_data(noise_physical))`. Under
SPMD every rank holds the same `MersenneTwister(seed)` (`:881`), so at 4 ranks the physical noise field is
**identical in each slab** — periodic with period L/4 — and only modes with k_z ≡ 0 (mod 4) are excited. It
is then band-passed, Leray-projected and variance-normalised, so it emerges solenoidal, correctly
band-limited, at exactly the requested variance. Nothing throws. §8 lists `State.jl:156,:257` and
`Particles.jl:172` and **misses this one** — the only one in the hot loop. (Currently archived/un-exported
but tested and slated for re-add: `test/forcing.jl:159-186`.)

**C2. Same defect in the initial condition; "changes the realization" understates it. VERDICT: BREAKS.**
`State.jl:156` / `:257`:
`copyto!(field_data(noise), randn(rng, T, field_physical_shape(domain.grid, Val(1))...))`. With a supplied
seed — the reproducible route every IT test uses — each rank draws the same block ⇒ a degenerate,
slab-periodic initial field. With the documented default `Random.default_rng()` each rank draws a different
stream ⇒ random but not reproducible and not equal to the 1-rank run. §8's *"change the realization for a
given seed unless reseeded per rank deterministically"* reads as bookkeeping; it is a wrong physical state
on the reproducible path.
**Repair:** PF exposes the rank's global index range so a consumer can seed per global block; a
counter-based RNG keyed on the global linear index is the only spelling that is both reproducible and
rank-count-invariant. Without it no IT run is reproducible across rank counts.

**C3. Tracer seeding changes what `number_of_particles` means.** `Particles.jl:172`:
`copyto!(pos, L .* rand(rng, T, M, 3))`. With a shared seed every rank draws the same M and local filtering
recovers exactly the 1-rank set — the one place SPMD helps. With `default_rng()` it does not:
`number_of_particles = 10^6` yields 4×10⁶ tracers unfiltered, or an arbitrary subset filtered.

**C4. Restart at a different rank count voids IT's strongest contract. VERDICT: BREAKS.**
`test/hdf5_checkpoint.jl:113` asserts *"a restored run continues the checkpointed one bitwise"* over the
state, the tracer positions and the AB history. `max_speed` (MAX) is order-independent and survives; every
`inner`/`weighted_inner` **SUM** is not, so the forcing amplitude differs at step 1 and trajectories separate
at the Lyapunov rate. `redistribute!` restores the layout, not the summation tree. §4.9 frames this as data
placement and never says the contract degrades to "same rank count only". IT's validation chapter rests on
bitwise continuation from a frozen TurTLE handoff state; with C2 on top, a published Arrhenius run becomes
reproducible only as *"this binary, this rank count, this decomposition"*.

**C5. `read_simulation` will not survive decomposition unedited.** `ext:383` passes
`number_of_particles = npoints(positions_host)`; `:403` `copyto!`s the whole set into a now rank-local one
— length mismatch (throw) or the wrong points (silent).

## D. Attack 5 — staging

**D1. Stage 1's definition of done cannot be met by the package's own bar. VERDICT: BREAKS.** §9 promises
"an independent oracle, GPU parity, an allocation row, a pass-audit row". Unified memory is CUDA-only;
`test/allocations.jl` measures with `@allocated` **on the CPU** by explicit PF design (a device buffer is
invisible to it), and there is no CPU unified memory — so the allocation row is measurable on **neither**
lane and is vacuous for the feature it guards. And "a GPU-suite axis" on CUDA only permanently breaks the
ROCm/CUDA test-count parity PF's `CLAUDE.md` treats as an invariant (*"491/491 … a different number is a
finding"*).
**Repair:** state stage 1 as a residency round-trip assertion plus a documented backend-asymmetric count,
refrozen with its reason; drop the allocation-row claim.

**D2. Stage 3 is stranded by stage 4, not the reverse. VERDICT: BREAKS.** §9 calls 2+3 "the first useful
milestone" and marks stage 4 "ships independently". For this consumer the order is inverted: a decomposed
1024³ run is weeks of wall time (E3) and must chain across Slurm allocations, so a solve that cannot
checkpoint is not a milestone — and at stage 3 the persistence path is not merely absent but actively wrong
(A4).
**Repair:** fold gather-to-rank-0 into stage 3, or make `write_field` on a partitioned field **throw** until
stage 4. The throw is the cheap half and should ship with stage 2.

**D3. Stage 3's home verification cannot see the class of bug that justifies its biggest decision. VERDICT:
UNPROVEN.** §4.5 rejects PencilFFTs largely because *"`MPI.Alltoallv!` is still unsynchronised"* on GPU
buffers — a device-MPI race. The home lane is "4 ranks, 1 GPU, and CPU". The 4-rank CPU lane is a real
oracle for the algorithm; the single-GPU lane needs the home MPI to be ROCm-aware (UCX+ROCm on a
workstation, not a given) and, failing that, stages through host memory — a different transport from
Arrhenius'. §7's *"everything is testable at home except performance"* misclassifies a correctness gap.

**D4. Stage 2 is "inert and provable" only in the configuration that is not the point. VERDICT: UNPROVEN.**
Its proof is that `NoPartition` changes nothing. It ships a breaking `Grid3D` parameter, a new public verb
(`redistribute!`, refreezing 206/122/Fields-130), IT-side `FixedDomain` work (B1/B2) — and zero exercised
partitioned code, because nothing can *build* a working partitioned field until stage 3.

## E. Attack 9 — the cheaper alternative, judged on what IT actually needs

**E1. What IT's record says its science is.** Published validation (`docs/src/validation.md`,
`validation/RUNBOOK.md`): **128³, Float64, Re_λ = 67.2**, 4h49m warm-up on the home RX 7900 XTX. Memory-audit
configurations (`test/memory_audit.jl`; ARCHITECTURE decisions 36/78): 256³ F64, **384³ F32 + 10⁶ tracers =
13.0 GiB**, a 512³ F64 frame figure of 2.52 GiB. Grepping the whole repository (docs, tests, runbook,
CLAUDE.md, decision log) for `1024|2048|4096|768` returns **not one grid** — only particle counts and an ODE
step count. **IT has never stated a resolution target above 512³.**

**E2. 512³ needs no feature at all.** IT's live set is 18 scalar-field-equivalents + a 3-array frame + plan
residency (2 × 3 spectral, velocity-only, decision 78) ≈ **27 GiB at 512³ F64 against one GH200's 96 GiB** —
3× headroom. Neither (A) nor (B) is needed for the largest grid IT has named. The design never asks this,
because §2's sizing uses decision 37's generic "25 scalar-field-equivalents" and is never checked against
this consumer's ledger, which IT has already frozen to 0.03%.

**E3. Above 512³ the binding constraint is wall time, not memory (ESTIMATE).** From IT's measured
0.275 s/iter at 128³ F64: to 1024³ the work grows ×733 (cells ×512, FFT log ×1.43) and the step count ×8
(CFL ∝ Δx), so a 50-turnover warm-up goes 4.8 h → ≈ 3 years on that card. A GH200 is bandwidth-bound here,
≈ 4–6× ⇒ ≈ 6–8 months on one; the design's own 2.5–3.5× on four ⇒ **≈ 2–3 months on a full node**, ≈ 1 month
in Float32. Feasible only as a chain of ~15–30 jobs — which makes D2 and C4 load-bearing, not the transform.

**E4. §11's headline contradicts §3.4's own policy.** "One GH200 + spill ⇒ ~1040³" is arithmetic on
96 GiB HBM + 120 GiB LPDDR: reaching it means **55% of the live set in LPDDR**. §3.4 calls the transform's
working set "the worst thing to spill (~9×)" and names "cold fields — checkpoint staging, accumulators, the
consumer's observables cache" as the right ones. **IT has almost no cold storage**: all 18
scalar-equivalents are read every step; the frame's three arrays are read every step by `weighted_inner` and
`convolve!`; the cache slots are read every step by the tracer gather; the one genuinely cold object (3.81
GiB of rank-2 plans at 384³/F32) was already made lazy by IT decision 78. At 55% spilled the step is ≈ 6×
slower, the grid 2.5× the work, needing 1.35× the steps ⇒ **≈ 20× the wall time of 768³ for the same physical
time**. The band is nominal capacity, not usable resolution — the alternative is stated in its own favour.

**E5. The honest cheap alternative is better than §11's and is absent from the document.** 1024³ **Float32**,
velocity-only: ≈ 72 GiB live + 12 GiB frame + 24 GiB plans ≈ **108 GiB against 96 GiB HBM**, over by ~12%.
Feature A closes *that* gap by spilling 10–15% of the live set, for a step ≈ 1.2× slower rather than 6×, with
no MPI, no partition and no consumer rewrite beyond B3. IT already treats precision as a "studied fitness
axis" (its invariant 4) and already runs 384³ in Float32. **This is the case for Feature A**, and making it
would strengthen §11 while retiring the 1040³ figure.
**Repair:** replace §11's sizing with a per-consumer live-set ledger (IT has published one) and re-ask ruling
2 as *"what is the largest grid whose warm-up fits an allocation chain?"*, not *"what fits in memory?"*.

**E6. The staging puts the payload last. VERDICT: BREAKS.** IT's one-sentence self-description is *"…with
Lagrangian particle tracking and field sampling along the trajectories"*, and the project is a parcel-theory
monograph. §4.8 calls the point layer *"the one that can be deferred, because the flow solver does not need
it; only Lagrangian tracers do"* — which inverts the consumer's priority: the tracers **are** the science,
the flow is the carrier. So the payload is stage 5, behind the document's self-declared *"hardest single
blocker"* (decision 59 / `_check_owned_storage`), while stages 2–4 deliver an Eulerian DNS at a resolution IT
has never asked for. *Can IT run before stage 5?* Mechanically yes — `tracers = nothing` is supported
(`SimulationRun.jl:609`) and the solver, spectra, skewness and forcing all work. Scientifically it produces a
flow nobody asked for and cannot reproduce IT's one published validation, which is a **tracer** comparison
against TurTLE at 10⁴ particles.

## The five most consequential problems, ranked

1. **The staging inverts the consumer's value order (E6, D2).** Payload last and behind the hardest blocker;
   persistence after the first decomposed solve, which needs it to be usable. *Repair:* gather-to-rank-0 into
   stage 3; settle ruling 6 **before** stage 2 opens, since it may move where the partition lives.
2. **Reproducibility is lost on the reproducible path (C1, C2, C4).** Seeded ⇒ slab-degenerate; unseeded ⇒
   not repeatable; restart at another rank count ⇒ a different run. *Repair:* expose the rank's global index
   range, mandate globally-indexed counter-based seeding, and add `Forcing.jl:902` to §8.
3. **`run!`'s termination predicate is an unguarded rank-split, and the stated rule does not cover it
   (A1, A2).** *Repair:* restate the invariant over predicates; Allreduce `keep`.
4. **§11 is not a fair comparison (E1–E5).** No costing against IT's published live set, a spill band its own
   policy forbids, and the Float32 alternative that dominates it omitted. *Repair:* a per-consumer ledger and
   a wall-time column beside every capacity row.
5. **"One line differs" is false at every layer the consumer touches (B1–B4).** IT cannot write §5's line,
   its frame constructor throws, Feature A does not reach it, and the hot loop gains 5–8 barriers per step.
   *Repair:* rewrite §5 against `Simulation(...)` and publish the diff as a file:line list.

## Residual risks the owner must accept

- **NaN through `MPI_MAX` is undefined by the standard (A3)**: the blow-up guard is unreliable under any
  decomposition until finiteness is reduced explicitly. Cheap to fix, invisible if not.
- **The home lane cannot exercise device-MPI (D3)** — the failure class the transform decision rests on.
  Accept it, add a second GPU at home, or treat the first Arrhenius run as the integration test and budget
  for it.
- **IT's compute audit's model, not just its numbers, is invalidated.** `test/compute_audit.jl` freezes
  scalar-equivalent FFT counts on the premise that *"the flop budget IS the transform count times FFTW's
  constant"*; under a slab decomposition one transform is two local stages plus an all-to-all, and §10
  records >90% communication in the one measured multi-GPU case. §8's "become per-rank ledgers" understates
  it: the audit's currency changes.
- **Bitwise rank-invariance cannot be recovered (§4.6, C4).** Ruling 7 means no IT result is bitwise
  reproducible across node counts — a permanent change to what "reproducing a published run" means, in a
  package whose validation chapter is built on bitwise tracking.
- **E3 is an ESTIMATE from one measured 128³ point.** If it is even half right, 4-GPU throughput is not what
  makes 1024³ possible — checkpoint-restart chaining is — and the priority between stages 3 and 4 flips.
  Measure one 256³ step on a GH200 before ruling on scope.
