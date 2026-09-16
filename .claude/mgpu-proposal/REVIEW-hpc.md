# Adversarial review — the HPC-practitioner lens

Brief attacks 1, 2, 4, 7, plus the load-bearing arithmetic: §4.5 slab, §4.6/§4.7 spectral indexing, §6, `02-cost-model-draft.md`, and fit to
`01-hardware-facts.md`. Every code claim was read at the cited line in the tree, not taken from `03-code-facts.md`.

## 1. (brief 1) The half-spectrum's special cases are resolved by LOCAL index, and §4.5 splits the axis they all live on

Scenario: `Grid3D((1024,1024,1024), (2π,2π,2π); partition = SlabPartition(comm))`, 4 ranks, default `fft_dims = (1,2,3)`. §4.5 gives spectral
(ky, kz whole; kx split). Rank 1 holds global kx 130:257 as local 1:128. Call `E = inner(û, û)`.
- `_parseval_weight` (`Reductions.jl:945-953`): `fill(T(2), size(field_data(f), folded))`, then `weight_host[1] = 1` and
  `weight_host[folded_length] = 1`. Both **local**. On ranks 1–3 two interior kx planes get weight 1 instead of
  2. Reaches `weighted_inner` (8 IT sites/step).
- `inner` (`:895-897, 911-913`): subtracts `_folded_abs2_plane(data, folded, 1)` and `…, size(data_f, folded))` — the same two local indices.
  Reaches `l2norm`, `var`, `std`.
- `_radial_spectrum_bin` (`:1283-1291`): `nyquist_index = spatial_shape[folded]` (local); the kernel (`:1249-1252`) tests `folded_mode == 1 ||
  == nyquist_index` on the **local** mode index.

Magnitude: O(1/N_kx) relative — ~0.2% at 1024³/4 ranks, systematic, same sign, inside the kinetic energy that drives IT's forcing. Exactly the
class `reality_projection!` was built for: a small biased error amplified by a proportional forcing. **BREAKS.** §6 says invariant 5 is
"unchanged — but the `iseven(n)` test must read the global length"; that covers the multipliers' Nyquist *zeroing*, not the Parseval
*multiplicity* α(k), which is an ownership question, not a length question, and §4.6's global list omits it. Repair: derive α(k) and both
correction-plane selections from the **global** folded index (partition offset + global length), never `size(data, folded)` — three sites,
five index expressions. Better: attack 3.

Contrast the design should state: `DifferentialOperators` special-cases DC by **value** (`ifelse(iszero(squared), …)` at `:215,274,595,645`),
so `inverse_laplacian`, `helmholtz_projection!` and `inverse_curl` are genuinely decomposition-safe; `Reductions` special-cases by **index**.
§4.2's "unchanged by construction" is true of one family and false of the other, and the design treats them alike.

## 2. (brief 1; verified per instruction) §4.7's reality claim — pairing right, plane selection wrong

`Fields.jl:2641-2653, 2712-2760`. Pairing is `jp = mod(-(j-1), na)+1`, `lp = mod(-(l-1), nb)+1` with `na, nb = sizes[others[1]],
sizes[others[2]]` — the stored extents of the two **non-folded** axes. §4.7's claim that keeping both whole makes the pairing local is
**correct**; `_owns_pair` (`:2743`) then partitions the work with no communication, and `_plane_linear` (`:2712-2714`) indexes the local array
linearly and needs no change. DEFEATED there.

But `reality_residual` selects planes as `iseven(grid_size[folded]) ? (1, size(data, folded)) : (1,)` (`:2701-2702`) — local first and local
last. With kx split 4 ways **every rank projects its own first and last local plane**, imposing Hermitian symmetry on six interior planes that
are not self-conjugate: `reality_projection!` (7 IT sites/step) overwrites `f̂(k)` with `(f̂(k)+conj(f̂(k')))/2` for unrelated k, k'. Silent —
and it *lowers* the reported residual, so the package's own diagnostic certifies the corruption. **BREAKS**; §4.7 calls this "free". It needs
the same global-ownership test as `_spectral_zero_mode_data`, which the design *does* flag — the same defect, one caught and one missed.
Repair: `stored_planes` = intersection of `{1, global_nyquist}` with the rank's global folded range, mapped to local (possibly empty). Note
also that with kx split, 2 of 4 ranks launch no kernel, so the launch must sit outside the ownership branch (attack 8d).

## 3. (own; brief 1+4) §4.5 splits the WRONG axis — the alternative slab wins on four of five counts

§4.5 justifies splitting the folded axis in spectral with exactly one argument (the reality pairing). The alternative is equally realisable:
```
physical (x,y whole; z split) --rfft_x, fft_y local--> ONE all-to-all --> spectral (kx,kz whole; ky split) --fft_z local-->
```
Both stages are local in both layouts; the transpose trades split-z for split-ky instead of split-kx. Under the alternative `_parseval_weight`
is **unchanged and correct**; `inner`'s two correction sums are **unchanged and correct**, and Allreduce-composable (each rank sums its share
of the kx=0 plane); the radial α is **unchanged and correct**; and the odd extent 513 stops being the split axis, killing attack 4. Cost: the
reality pairing crosses ranks and needs the mirror exchange §4.7 itself prices (~4 MiB, ~27 µs against ~10 ms/transform; ~0.4 ms/step over
IT's 7 calls) — and §4.7 says that exchange makes the kernel *simpler* (`_owns_pair` disappears). Pack quality agrees: splitting **dim 1**
chops the stride-1 axis, giving contiguous runs of 513/P = 128 complex (2 KiB), where splitting dim 2 gives runs of 513 complex (8 KiB).

One correction to §4.7's fallback recipe: the mirror of rank r's block is **not** a single partner. For an equal split of N over P, rank r≥1
mirrors to `[(P-r-1)B+2, (P-r)B+1]` — all of rank P-1-r except one plane, plus exactly **one** plane of rank P-r; the `+1` in
`mod(-(j-1),n)+1` shifts the block across a rank boundary. A rank posting one Recv against a partner posting two Sends is a hang.

**BREAKS** (decided on one of five criteria, losing the other four). Repair: split a non-folded axis in spectral and pay the mirror exchange;
if the folded split is kept for another reason, §4.5 must name the four sites it breaks and §4.6 must list them. Unstated and related: the
partition must be **derived from `layout.fft_dims`**, not hardcoded x/y/z. PF runs three layout folds across its suite (decision 41); at
`fft_dims = (3,1,2)` the folded axis is 3 and §4.5's diagram is wrong, so a lane testing only the default fold leaves untested an axis tested
everywhere else.

## 4. (own; brief 1+3) The exactness argument is a non-sequitur, and exact division of the folded axis is IMPOSSIBLE

§4.4: "the decomposition is exact on the split axes, because `Grid3D`'s four-argument constructor rejects a `grid_spacing` that contradicts
`domain_size ./ grid_size` (decision 45) — a remainder rank would be unconstructible." The constructor (`Fields.jl:155-168`) checks
`grid_spacing ≈ domain_size ./ grid_size`, a property of the **global** grid, which §4.4 insists is global and therefore identical on every
rank. It cannot reject anything about a rank count; the cited mechanism does not exist.

The arithmetic is worse. The spectral folded extent is `Nx/2+1`. For any `Nx = 2^m, m ≥ 2`, `Nx/2` is even so `Nx/2+1` is **odd**: 513
(=3³·19), 257 (prime), 1025. An odd extent divides by no even rank count, so under §4.5's layout an exact spectral decomposition is
**impossible at every production grid and practical rank count**; 4 ranks give 129/128/128/128 permanently. Consequences not drawn: the
transpose is `Alltoallv` with per-rank tables, never `Alltoall`; local shapes differ per rank, so `_component_offsets_align`
(`Fields.jl:1378-1384`), computing `physical_stride`/`spectral_stride` from the local shape, can answer differently per rank, making
`component_scratch` `Nothing` on some ranks and an array on others and `FieldTransformPlans` a **different concrete type per rank** (attack
8d); and an allocation or pass-audit row taken on rank 0 does not describe rank 1. **BREAKS.** Repair: adopt attack 3's layout (Ny divides
evenly), or state plainly that the split is uneven, size every buffer `cld(n,P)`, and forbid control flow depending on a local shape.

## 5. (brief 4) §2's capacity table is a theoretical ceiling presented as achievable; the failure at it is SIGKILL

`01-hardware-facts`: past host RAM the OS kills the process on the page fault — a cliff, not a slowdown.
- "one GH200 + spill → ~1040³": 8.38 GiB/scalar field × 25 = **209.5 GiB** vs 96 + 120 = 216 GiB → **97%**, with nothing left for the Julia
  runtime, the CUDA context, MPI, or the cuFFT workspace (1040 = 2⁴·5·13, mixed-radix).
- "four GH200 HBM-only → ~1270³": 15.3 GiB × 25 = **381 GiB** vs 384 → **99.2%**.
- "four GH200 + spill → ~1650³": 33.5 GiB × 25 = **838 GiB** vs 861 → **97%**.

None leaves room for the transpose pack/unpack buffers, which §6 (invariant 13) requires the **plan to own permanently** — two
scalar-field-equivalents per rank minimum, i.e. 2 of the 25. A 15–20% discount for runtime + workspace + buffers moves 1270³ → ~1200³ and
1650³ → ~1550³. **BREAKS** as stated. Repair: publish the table with an explicit overhead line and state the failure mode at the ceiling.

## 6. (brief 4) "1650³ … beats a thin CPU node's ~1536³, **at GPU speed**" — the second half is false

At 1650³ the live set is 838 GiB against 384 GiB HBM: **54% of it sits in LPDDR**. IT streams 41 spectral + 10 physical full-field passes per
step, i.e. most of the live set every step. The design's own model: "a step that spills HALF its traffic runs ~5× slower". §3.4's policy —
spill cold fields, never the transform's working set — is unsatisfiable at 1650³, because at that size there are no cold fields left to be the
spilled ones. So it is ~1/5 GPU speed. It still beats the CPU node (4 GH200 ≈ 16 TB/s, /5 ≈ 3.2 TB/s vs ~1.15 TB/s for 2× EPYC 9755) but by
~3×, not the ~14× "GPU speed" implies — and after attack 5's discount the *capacity* comparison (1550³ vs 1536³) is a tie. **BREAKS** (the
claim, not the feature). Repair: give each table row its spilled fraction and implied slowdown; the honest headline is "~1270³ at full speed;
~1550³ at ~1/5 speed, still ~3× a CPU node".

## 7. (brief 4; own) The cost model computes PENCIL, the design chose SLAB — and §2's multi-node claim needs the decomposition §4.5 rejects

`02-cost-model-draft.md` assumes "2D pencil ⇒ two all-to-all transposes", each shipping 3/4 ⇒ 6.6 ms comm ≈ 3–8 ms compute ⇒ "communication ≈
computation"; §10 cites that as the design's estimate. §4.5 chose **slab**: **one** all-to-all shipping 3/4 ⇒ ~3.3 ms. (A real 4-rank pencil
is 2×2 and each stage ships 1/2, not 3/4, so the model overstates pencil too.) The model's comm figure is ~2× the design's own architecture —
conservative, so 2.5–3.5× survives, but it is not derived from the design. Omitted entirely: **pack and unpack** (~1.5 GiB each way ⇒ ~1 ms of
extra HBM traffic per transform, plus a strided kernel the design's own quoted lesson — "reshape so the transformed axis is dim 1" — warns
about), and the fact that `Alltoallv` on device buffers without NVSHMEM does not reach peak.

Sharper: the model's own DESIGN CONSEQUENCE is "a 2D pencil decomposition must put the FAST transpose on the intra-node axis and the slow one
across nodes". **A slab has one transpose and cannot do that.** At 2 nodes / 8 ranks the single all-to-all crosses Slingshot for 4/7 of its
traffic: ~20 ms/transform/node against ~1.7 ms intra-node, ×27 transforms/step ≈ **540 ms/step of communication**. §2 sells 2048³ on "2 nodes
with spill" — slab's worst case *and* attack 6's spill case at once. Slab at one node: **DEFEATED** (the ~384-process crossover is real; 4 ≪
384). Multi-node: **BREAKS.** Repair: parameterise the transpose layer by the number of split axes with slab as the type-dispatched
specialisation — exactly the Oceananigans mechanism §4.5 already cites — or delete the 2048³/4096³ rows.

## 8. (brief 2) Deadlocks

(a) `if rank == 0; E = inner(u,u); end` — named in §4.6 with a mitigation. **DEFEATED.**

(b) Shell-count divergence — named in §4.6. **DEFEATED**, but a mismatched `Allreduce` count is undefined behaviour (corruption or hang), not
an error, so the global-corner fix is load-bearing rather than tidiness.

(c) **A throw on one rank.** PF validates by throwing at ~40 sites. Under attack 4's uneven division several validated quantities are
rank-dependent (`_check_multipliers_compatibility`'s six length checks against `field_spectral_shape`, `_component_offsets_align`'s answer,
any shape comparison). Rank 2 throws, ranks 0/1/3 block in the all-to-all forever, Slurm kills at the wall clock with no stack trace. No story
in the design. **UNPROVEN.** Repair: either every rank-dependent validation is itself collective, or the extension installs a global handler
calling `MPI.Abort` — the second is cheap and belongs in stage 3.

(d) **Rank-dependent control flow.** Attack 4 shows `FieldTransformPlans` can have a different concrete type per rank; any method chosen by
`component_scratch === nothing` that also decides whether to enter the exchange diverges. **UNPROVEN.** Repair: state as a design rule that no
control flow may depend on a local shape, and assert it (one `Allreduce` of a branch id in the debug mode §4.6 already proposes).

(e) **GC as collective jitter.** Invariant 13 keeps the hot loop allocation-free, but the *documented* exemptions remain: mixed spectral
`inner(f,g)` materialises O(N²) correction planes per call and IT calls `weighted_inner` 8×/step. With ~41 collectives per step, one rank's GC
stalls all four every time it fires, and PF's own finding (y) records device allocation being process-history-sensitive to 3.2×. **UNPROVEN**
— §6 lists invariant 13 "at risk" for the transpose buffers only. Repair: reclassify the bounded allocators as collective-jitter sources and
pin them to zero in the distributed lane.

## 9. (brief 7) GPU-aware MPI is a hard requirement with no fallback, on machines where it is not established

§4.5 puts `MPI.Alltoall(v)!` directly on device buffers, with no host-staging path. **Arrhenius**: `01-hardware-facts` says GPU-awareness is
*not documented* on the NSC pages; Cray MPICH needs `MPICH_GPU_SUPPORT_ENABLED=1` **and** the GTL linked **and**
`MPIPreferences.use_system_binary()` — three things that must all be right and are each silent when wrong (`MPI.has_cuda()` is false either
way). **Home (AMD)**: MPI.jl's default JLL MPICH is not GPU-aware, so handing it a `ROCArray` pointer gives a segfault or silently wrong data;
making the home box a valid host means building OpenMPI with UCX+ROCm from source, so §7's "everything is testable at home except performance"
is **false** for the one path that carries the design. **Office (NVIDIA)**: same with CUDA, plus `JULIA_CUDA_MEMORY_POOL=none` for IPC.
**BREAKS** §7's testability claim. Repair: the pack/unpack layer selects host-staging vs device-direct **at run time** from a probe at init,
with an env override — one buffer pair and one branch outside the hot path, which makes the home box a real correctness host and gives
Arrhenius a fallback.

## 10. (brief 7; own) §3.3's spill mechanism is the allocator `01-hardware-facts` recommends AGAINST

§3.3: "`KA.allocate(backend, T, dims; unified = true)` … the package needs **no** vendor dependency and no new public verb." KA's `unified`
maps to CUDA.jl's `UnifiedMemory` = `cudaMallocManaged` — **migrating** memory. The fact file, on GH200: managed "is WORSE for streaming
access with no reuse — measured to win only after ~128 back-to-back passes… A pseudospectral sweep streams each field once per pass ⇒ prefer
plain host/system allocation + ATS". Its run-time discriminator (`pageableMemoryAccessUsesHostPageTables`) is about **pageable** memory, which
managed memory is not. So the one mechanism offered is the one the fact file rejects for this access pattern, and the right one
(system/pageable via ATS, or pinned `HostMemory`) has **no KA spelling** — taking "no vendor dependency" with it. **BREAKS.** Repair: stage 1
must A/B managed vs pinned-host vs plain-Array-via-ATS on a GH200 before committing to a spelling; until then §3.3 should say the API is
undecided. Neither alternative is measurable at home, so stage 1's definition of done is unverifiable on the owner's hardware (brief 5): the
code path is testable, the *choice* is not.

## 11. (brief 7; own) NUMA binding decides a 3× and is nowhere in the design

§2.2 says spilled memory must be allocated by the process bound to that superchip, but never that this is a **launcher** property: without
`--gpu-bind=closest` and a correct `--cpu-bind`, "own Grace LPDDR at 450 GB/s" becomes "a peer's at 150 GB/s" and the spill penalty goes from
~9× to ~27× — a 3× swing in the headline number, set by two `srun` flags, unverifiable at home and absent from stage 6's definition of done.
**UNPROVEN.** Repair: add it to stage 6, plus a run-time affinity check that warns once.

## 12. (own; the question asked) What the design gets wrong about the half-spectrum × transpose

Oceananigans used c2c to dodge this; the design adopts its architecture without asking what the divergence bought. Three things r2c costs
across a transpose, in decreasing severity:
1. **The folded extent is odd** for every power-of-two grid (attack 4), so no even rank count divides it. With c2c every axis is N and divides
   exactly — which is what let Oceananigans use `Alltoall` rather than `Alltoallv` and assume identical local shapes on every rank, which is
   in turn what makes their SPMD control flow provably rank-independent (attack 8d).
2. **The half-spectrum's special planes are an ownership question, not a geometry question** (attacks 1, 2). c2c has no self-conjugate plane,
   no α(k) multiplicity, no `_owns_pair`; r2c has five index-based special cases, and §4.5 chose the layout that puts all five on the split
   axis.
3. **Asymmetric buffers and a consumed destination.** The forward pack is complex `(Nx/2+1)·Ny·Nz/P`, the physical side real `Nx·Ny·Nz/P` —
   two buffer shapes, not one. And the inverse c2r destroys its input (invariant 11, backend-divergent), so distributed it consumes the unpack
   destination. The four-argument scratch arity (decision 64) promises the source is bitwise preserved; honouring that under decomposition
   needs scratch of one local spectral field **plus** the pack/unpack pair, not one field. §6 says invariant 11 is "re-verified, not amended"
   — its *size contract* is amended, unstated.

Keep r2c (dropping it doubles memory and forfeits the reality machinery just built), but §4.5 must state these three as the price and answer
each. It currently states none.

## 13. (brief 1) Defects the design DOES defeat — recorded so they are not re-raised

**DEFEATED**: `_spectral_zero_mode_data` at local (1,1,1) (§6/invariant 4), rightly called the one fix worth making unconditionally; the
global shell corner (`Reductions.jl:1275`); `radial_correlation`'s minimum-image from the global index (`:1399-1401`) — in principle, since it
also needs the rank's index *offset*, not only the global extent; RNG realisation changing with rank count (§8); and `_wrap_step` treating the
array extent as the period (`Interpolation.jl:954`) — though understated, because `_locate` (`:417-421`) has no range check and the kernel
body is `@inbounds`, so an out-of-slab point is memory corruption rather than a `BoundsError`, and the kernel needs three quantities where it
has one (local extent, global period, rank offset). Not named, and belonging in §4.8: `_base_count` for a decomposed `PointSet` must become
global M.

## 14. (brief 4/8) The measurement that would validate the design cannot be taken

Stage 6's definition of done is scaling efficiency, which needs a single-device control. The configurations that justify feature B (≥1270³)
have none — they do not fit one GH200. The only strong-scaling control available is ≤768³, the regime where the design's own model is *least*
favourable (least local work per transpose). The measurement that can be taken is not the measurement that decides. Compounding it: PF's
recorded history is that its GPU measurement *regime* was silently wrong for months twice (`gcsample`, then the CUDA probe that never ran),
each caught only by an internal-consistency tell in the table, and a rank-scaling sweep has no such tell. **UNPROVEN.** Repair: state
acceptance as absolute throughput against the roofline (achieved GB/s per GPU; achieved all-to-all GB/s against 150 GB/s/pair), not efficiency
against an unmeasurable baseline — and add a device vector-transform mechanism to the canary, which the package already knows is blind there.

## The five most consequential problems, ranked

1. **§4.5 splits the folded axis** (3). One criterion was weighed; four point the other way, and the alternative slab is equally realisable. A
   one-paragraph change now, a rewrite of the transpose, the Parseval weight, the correction planes, the radial α and the reality plane
   selection later. Attacks 1, 2 and 4 all follow from it.
2. **α(k) and the reality plane selection are silently wrong under any folded-axis split** (1, 2), and §4.6's global list omits both. The
   design caught the structurally identical zero-mode defect, so the enumeration is the right method, run incompletely.
3. **The exactness argument is a non-sequitur and exact division is impossible** (4); uneven local shapes then propagate into per-rank plan
   types, per-rank validation outcomes and the deadlocks in 8(c,d).
4. **GPU-aware MPI is a hard, unestablished dependency with no fallback** (9), which also falsifies §7's "everything is testable at home". A
   run-time host-staging path is cheap and de-risks three machines at once.
5. **The capacity and speed headlines** (5, 6): 97–99% memory utilisation presented as achievable with an OOM-kill failure mode, and "1650³ at
   GPU speed" when 54% of the live set is in LPDDR. Both are optimistic by enough to change the ruling they exist to inform.

## Residual risks to accept even after every repair

- **Slab is a single-node decomposition**: accepting it accepts 2048³ as capacity-only at ~540 ms/step of communication, unless the pencil
  generalisation is committed to up front (7).
- **No published single-node 4-GPU compute/comm split exists.** 2.5–3.5× stays an estimate, and 14 says the run that would confirm it cannot
  be taken at the sizes that justify the work.
- **Bitwise rank-count invariance is gone** and cannot be recovered. The design says so; it does not say that this also removes bitwise
  comparison against the serial path as a debugging tool — the package's usual first move.
- **Feature A's allocator cannot be chosen from the owner's hardware** (10), and its performance model rests on launcher flags nobody can test
  at home (11).
- **`aarch64` has zero coverage** and stage 6 stacks it with three other first-runs. Splitting it out — build and `Pkg.test()` on a Grace node
  before anything distributed runs — costs almost nothing and removes a confounder from the one measurement campaign that matters.
