# Consumer red team — findings to fold into the design (verified where marked)

VERIFIED BY ME:
- `ScalarFieldPhysical(f, grid, ...)` (Fields.jl:467-479; vector twin :612-627) allocates
  `field_physical_shape(grid, Val(0))` (LOCAL under the design) but loops `1:grid.grid_size[d]` (GLOBAL) and
  offsets from `grid.origin` (global) ⇒ BoundsError + wrong coordinates on every rank.
  ⇒ §4.4's "every allocator routes through the two shape functions, untouched" is FALSE for these two.
  FIX: iterate the rank's local index range; compute the coordinate from the GLOBAL index.
- IT's corpus names 128^3 (x18), 256^3 (x16), 384^3 (x2) and NOTHING larger. Re_λ 67 at the published point.
  ⇒ 512^3 F64 ≈ 27 GiB against 96 GiB HBM: needs NEITHER feature. The whole programme is aimed 3-4 octaves
  above anything IT has ever recorded as a target.

FROM THE REVIEWER (not independently re-verified, but cited to file:line):
- IT never builds a Grid3D — FixedDomain/Simulation do (SimulationDomain.jl:289) ⇒ §5's "one line" is unwritable
  in IT as it stands; and IT has its OWN copy of the §3.2 defect (`array_type{S}(undef,…)`, :283), with
  `storage_family` a single global setting ⇒ IT can only ask for ALL-unified, the ~9x case §3.4 forbids.
- The default hot loop gains 5-8 blocking barriers per step (3x tuple weighted_inner per RK3 stage,
  max_speed, scalar_variance, the warm-up k/ε), four of them gating a branch.
- DEADLOCK RULE IS BACKWARDS: IT already has 5 collectives inside conditionals, ALL CORRECT (the predicates are
  rank-uniform). A "collective in an if" lint = 5 false positives, 0 defects. The real hazard is `run!`'s
  `keep || break` (SimulationRun.jl:1106) — an arbitrary USER predicate that can split ranks.
  FIX: state the invariant over PREDICATES (any predicate gating a collective must be rank-uniform) and
  `Allreduce(keep, &)`. Also: MPI_MAX has NO standard-defined NaN behaviour ⇒ the blow-up guard
  (:892,:899) can go silent or fire on one rank only.
- SILENT PHYSICS CORRUPTION, missing from §8: `Forcing.jl:902` draws `randn!` per step inside the loop. Under
  SPMD every rank draws the SAME stream ⇒ each slab gets identical noise ⇒ slab-periodic forcing, only
  k_z ≡ 0 (mod nranks) excited — and after band-pass + Leray + variance normalisation it LOOKS correct.
  Same class for State.jl:156,:257 (a degenerate field, not merely a different realization).
- Restart at a different rank count voids test/hdf5_checkpoint.jl:113's "continues bitwise" (the summation
  tree changes, which redistribute! cannot restore).
- STAGING INVERTED: IT's own identity is Lagrangian tracking and its published validation is a tracer
  comparison with TurTLE — yet the point layer is staged last, behind the hardest blocker. And stage 3
  ("first useful milestone") cannot checkpoint, because persistence is stage 4: four writers each claiming
  the whole box (silent) or 3 ranks throwing while rank 0 walks on (hang).
- Stage 1's promised allocation row is VACUOUS (CPU @allocated cannot see unified memory; GPU buffers are
  invisible to it), and a CUDA-only suite axis breaks the 491/491 ROCm/CUDA parity the package treats as an
  invariant.
- §11 is unfair: the "~1040^3 with spill" figure needs ~55% of the live set in LPDDR, which §3.4 itself
  forbids ⇒ ≈20x wall time. IT has almost no cold fields (all 18 scalar-equivalents are read every step).
  THE HONEST CHEAP OPTION: 1024^3 Float32 VELOCITY-ONLY ≈ 108 GiB vs 96 GiB ⇒ feature A alone closes a 12%
  gap at ≈1.2x per step, no MPI, no decomposition.
- THE DECISIVE FACT (ESTIMATE from IT's measured 0.275 s/iter at 128^3): a 50-turnover 1024^3 warm-up is
  ≈2-3 months on a full GH200 node (≈1 in F32) ⇒ a chain of 15-30 Slurm jobs. CHECKPOINT-RESTART, not 4-GPU
  throughput, is what makes >=1024^3 possible at all — which flips the stage 3/4 priority.
- IT's compute_audit loses its CURRENCY, not just its numbers: one transform becomes two local stages plus an
  all-to-all, so "flops = transform count x FFTW's constant" stops being the right model.
