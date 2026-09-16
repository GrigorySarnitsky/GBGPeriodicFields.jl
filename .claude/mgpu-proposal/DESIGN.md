# Multi-GPU and memory spill — a design proposal for GBGPeriodicFields

**Status: a proposal, revision 2, nothing implemented.** It overturns a recorded scope decision (`ARCHITECTURE.md` §1,
`PERFORMANCE.md` §1, decision 37), so it needs the owner's ruling before any code moves. Facts are in `01-hardware-facts.md`,
`02-cost-model-draft.md`, `03-code-facts.md`, `05-ecosystem-facts.md`; three adversarial reviews in `REVIEW-hpc.md`,
`REVIEW-invariants.md`, `REVIEW-consumer.md`; the owner's rulings on them in `07-revision-rulings.md`. Every `file:line` was
read in the tree at `390fced5`. Anything unmeasured is labelled **ESTIMATE**.

---

## 0. What the adversarial pass changed

**Decisions that reversed** — each argued where it is cited.

1. **The spectral split is flipped** (§4.5): the folded axis is never split, the second axis is, and the mirror exchange is paid.
2. **The exactness argument is deleted** (§4.4): replaced by uneven `cld(n,P)`, `Alltoallv`, and no local-shape branching.
3. **§4.7's "this is free" is withdrawn**: free in communication, false in correctness.
4. **Invariant 14 is not the refusal** (§6): a distributed/local mix is a **grid** refusal; `redistribute!` is a base conversion.
5. **The distributed generics and types move to core** (§4.4): every derived ledger filters `m.module === mod`.
6. **`Grid3D` must stay `isbits`** (§4.4): `_same_grid` is `===`, so a carried `MPI.Comm` makes grid equality pointer identity.
7. **The spill allocator becomes an open question** (§3.3): `unified = true` is the migrating allocator the facts reject.
8. **The numbers are restated** (§2): an overhead line, a spilled-fraction column, "at GPU speed" deleted, slab cost model.
9. **Persistence precedes the first distributed solve; `aarch64` is its own step; the point layer precedes MPI-IO** (§9).
10. **§11 becomes three fairly-compared options**, ensemble parallelism promoted to the baseline feature B must beat.
11. **The deadlock rule is restated over predicates** (§4.6): the consumer's five collectives-in-conditionals are all correct.

**Defects found that revision 1 did not have.**

- `points_per_fibre` makes `interpolate!` return its destination untouched — **created by this design's own ruling** (§4.8).
- The six multiplier length validations must become local, or §4.2's own mechanism is unbuildable (§4.2).
- The radial shell corner becomes a per-rank maximum ⇒ different bin counts ⇒ an ill-formed `Allreduce` (§4.2).
- `radial_correlation`'s minimum-image needs the rank's index *offset*, not only the global extent (§6).
- `_base_count` for a decomposed `PointSet` must become the global M (§4.8).
- The two function-initialized field constructors `BoundsError` on every rank — the consumer's first line (§4.4).
- `reality_projection!` — not just the residual — corrupts the field in place, 7× per step in the consumer (§4.5).
- `run!`'s `keep` is an unguarded rank-split, and `MPI_MAX` has no standard-defined NaN behaviour (§4.6).
- `Forcing.jl:902` draws the same noise on every rank ⇒ slab-periodic forcing that looks correct after band-pass (§1).

---

## 1. The question, and the short answer

Arrhenius gives four GH200 per node and lets each GPU reach its host memory when HBM runs out. What does the package need to use
both? **Two different features, built in that order.**

- **(A) Spill** — one device, host-backed storage. **Small**: the package is nearly transparent to it and one real defect blocks
  it. **CUDA-only** — AMDGPU.jl has no unified memory at all — so it cannot be validated on the home box, and *which* host
  allocator to use is an open question (§3.3).
- **(B) Four GPUs** — a **partitioned base**, MPI, one rank per superchip, a distributed transform, collective reductions.
  **Large**: the biggest single change in the package's life, and it reaches into the consumer.

**The worst thing in this document is not a performance claim; it is a silent physics corruption.** Under SPMD every rank runs
the same program with the same seed, so `Forcing.jl:902`'s per-step `randn!(ou.rng, field_data(noise_physical))` gives **every
slab identical noise**: the forcing becomes periodic with period `L/P` and excites only modes with `k ≡ 0 (mod P)` on the split
axis — then it is band-passed, Leray-projected and variance-normalised, so it emerges solenoidal, correctly band-limited and at
exactly the requested variance. Nothing throws. `State.jl:156,:257` is the same class in the initial condition: with a supplied
seed — the reproducible route every consumer test uses — each rank draws the same block, so the field is *degenerate*, not
merely a different realization. No decomposition may ship without a rank-aware, globally-indexed seeding scheme (§8). Nothing
else here is as dangerous.

The mathematics still predicts what (B) costs, and the prediction survived review: **59 of the ~93 public operations in the
field half are unchanged by construction** (verified per site, `REVIEW-invariants.md` A8), because fiberwise algebra is vertical
(base-independent) and the differential operators and convolution are pointwise in mode space. What communicates is the
transform, the measure reductions, the reality condition and the grid↔point transfer.

One fact carries that claim and deserves naming: the differential operators special-case DC and Nyquist **by value** —
`ifelse(iszero(squared_wavenumber), …)` at `DifferentialOperators.jl:215,274,595,645` — not by index, so `inverse_laplacian`,
`helmholtz_projection!` and `inverse_curl` are decomposition-safe for free. `Reductions` special-cases the same modes **by
index**, and is not. Revision 1 treated the two families alike.

---

## 2. The hardware, and what it forces

| path | bandwidth | vs HBM |
|---|---|---|
| GPU → own HBM3 | > 4000 GB/s | 1× |
| GPU → own Grace LPDDR (NVLink-C2C, hardware-coherent) | 450 GB/s | **~9×** |
| GPU → a peer superchip's memory (NVLink 4) | ~150 GB/s | ~27× |
| node → network (4× Slingshot) | ~100 GB/s | ~40× |
| x86 host over PCIe 5 (for contrast) | ~64 GB/s | ~60× |

Per node: 4 × (96 GiB HBM + 120–128 GB LPDDR + 72 Grace cores) = 384 GiB HBM, ~861 GiB coherent.

1. **Spilling is viable here and nowhere else in the fleet**: hardware-coherent access, no migration, no thrash mode, a
   predictable ~9×. On x86 the same code is ~60× slower on spilled data; on the home RX 7900 XTX it does not run.
2. **A quad-GH200 node is four NUMA domains**, and which domain a page lands in is set by two launcher flags. Without
   `--gpu-bind=closest` and a correct `--cpu-bind`, "own Grace LPDDR at 450 GB/s" silently becomes "a peer's at 150 GB/s" and
   the spill penalty goes ~9× → ~27×. A 3× swing in the headline number, unverifiable at home, and it belongs in a definition of
   done (§9).
3. **Inside the node is 1.5× the network; across nodes is 40× slower than HBM.** Four GPUs on one node is the question asked;
   §4.5 explains why a slab makes multi-node a bad story.

### Capacity, stated honestly

Float64, a live set of 25 scalar-field-equivalents (decision 37's own figure). **Nominal** is `capacity ÷ 25`; **usable**
discounts 15–20% for the Julia runtime, the CUDA context, the cuFFT workspace, MPI, fragmentation and the transpose's
pack/unpack buffers, which invariant 13 requires the *plan to own permanently* (~2 of the 25). **Spilled** is the fraction of
the live set that cannot be in HBM. ESTIMATE throughout.

| configuration | nominal | usable (−15–20%) | spilled | per-step cost |
|---|---|---|---|---|
| one GH200, today | ~768³ | ~760³ | 0% | 1× |
| one GH200 + spill (A) | ~1040³ | ~990³ | **54%** | ~5× |
| four GH200, HBM only (B) | ~1270³ | ~1200³ | 0% | 1× (+ comm, §4.5) |
| four GH200 + spill (A+B) | ~1650³ | ~1550³ | **55%** | ~5× |

**The failure mode at the ceiling is not an error**: `cuMemAllocManaged` never returns OOM; past host RAM the OS kills the
process on the page fault. A 97–99% utilisation figure is a cliff, not a target.

**The spilled rows violate §3.4's own policy**, which rules that only *cold* fields should be spilled and that the transform's
working set is the worst candidate. At 54% spilled there are no cold fields left to be the spilled ones — decision 37's 25
fields are a *live* set, and the consumer's ledger is worse: all 18 of its scalar-equivalents are read every step, and the one
genuinely cold object (rank-2 plans) was already made lazy by its decision 78. The honest headline is **"~1200³ at full speed;
~1550³ at ~1/5 speed"**, and the marginal value of A on top of B is *2.2× the cells at ~5× the per-step cost*.

**"At GPU speed" is deleted.** At ~1/5 speed a full node is ~1.8–3.2 TB/s effective against a thin CPU node's ~0.6–1.15 TB/s
achievable DDR5 — **~2–3×, not the ~14× the phrase implied** — and after the usable discount the *capacity* comparison (~1550³
vs ~1536³) is a tie.

### The cost model, recomputed for the decomposition actually chosen

`02-cost-model-draft.md` computed a **2D pencil** (two all-to-all transposes, each shipping 3/4). §4.5 chose **slab**: **one**
all-to-all shipping 3/4 ⇒ **~3.3 ms**, not 6.6, at 1024³/4 ranks, against ~3–8 ms of local FFT — comm ≈ 0.4–1× compute. Two
omissions are now added: **pack and unpack** (~1.5 GiB each way ⇒ ~1 ms of extra HBM traffic per transform, plus a strided
kernel), and the fact that `Alltoallv` on device buffers without NVSHMEM does not reach peak. The estimate **2.5–3.5× on four
GPUs for transform-bound work** survives, but is now derived from this design rather than a different one. ESTIMATE.

**Multi-node is where slab fails, and the 2048³/4096³ rows are withdrawn.** The cost model's own design consequence is that a 2D
pencil must put the fast transpose on the intra-node axis and the slow one across nodes; *a slab has one transpose and cannot do
that*. At 2 nodes / 8 ranks the single all-to-all crosses Slingshot for 4/7 of its traffic: ~20 ms per transform per node
against ~1.7 ms intra-node, ×27 transforms per step ≈ **540 ms/step of communication**. Either the transpose layer is
parameterised by the number of split axes from the start — slab as the type-dispatched specialisation, the Oceananigans
mechanism §4.5 cites — or multi-node is not claimed.

**This still falsifies decision 37's premise, but by less than revision 1 said**: decision 37 routes the beyond-one-GPU band to
CPU nodes *because* multi-GPU is out of scope, and with (A)+(B) one GPU node covers that band ~2–3× faster. Note what the
demotion costs: decision 37's conclusion becomes conditional, and four recorded roadmap items that rest on the CPU path being
the production platform for large grids (x-inner loop order at 1536³, the pass-audit gaps priced out of cache, NUMA first-touch,
and the gap that no CPU benchmark column above 256³ exists) dissolve with it. §12 ruling 2 must list them.

---

## 3. Feature A — spill

### 3.1 What already works

`CuArray{T,N,M}` carries the memory kind as a **type parameter of the one type**, so a unified array is still `<:
AbstractGPUArray`, `get_backend` still answers `CUDABackend()`, every KA kernel still launches, and `similar`, `copy` and
broadcast all preserve the kind. `similar_field` (`Fields.jl:1030-1063`) is built on `similar`, so it already produces spillable
storage from a spillable reference. The package names no vendor type in `src/`.

### 3.2 The one defect that blocks it, today

```julia
# Fields.jl:893-896, _allocated_field_storage
wrapper = Base.typename(family).wrapper      # CuArray{Float64,3,UnifiedMemory} -> CuArray
wrapper{S}(undef, shape)                     # ... -> device memory, silently
```

`_check_family_element_type` (`:908-919`) vets only the element type. **A live defect independent of everything else in this
document**, and the consumer has its own copy of it (`SimulationDomain.jl:283`, `_zeros(array_type, S, dims) =
fill!(array_type{S}(undef, dims...), …)`).

### 3.3 The API: the spelling is portable, the mechanism is an open question

KernelAbstractions — already a dependency — has the portable spelling at the package's compat floor (verified in the installed
KA 0.9.41, `KernelAbstractions.jl:546,594`): `KA.allocate(backend, T, dims; unified = true)` and `KA.supports_unified(backend)`
(CUDA true; AMDGPU implements neither, so it throws).

**But `unified = true` is `cudaMallocManaged` — *migrating* memory — and `01-hardware-facts.md` recommends against it for this
access pattern**: managed memory is measured to win only after ~128 back-to-back passes over the same data, and a pseudospectral
sweep streams each field once per pass. The allocator the fact file prefers on GH200 is plain system/host memory reached through
ATS hardware coherence, which has **no KA spelling** — taking "no vendor dependency" with it. The run-time discriminator the
fact file names (`cudaDevAttrPageableMemoryAccessUsesHostPageTables`) is about *pageable* memory, which managed memory is not,
so it does not settle the choice either.

**Ruling: stage 1 A/Bs three candidates on a GH200 before the package blesses one** — managed (`unified = true`), pinned host
(`HostMemory`), and plain host memory via ATS. Keep the KA spelling as the portable *surface*; do not claim it is the right
*mechanism*. The code path is testable at home; the choice is not, on any hardware here.

One signature mismatch either way: `KA.allocate(backend, …)` takes a **`Backend` instance** while `_allocated_field_storage`
holds a **type** (`family::Type{<:AbstractArray}`) and `get_backend` is defined on arrays, not array types. Either the
constructor builds a zero-element probe to resolve type → backend, or it keeps the fully-parameterised family and never touches
KA. Two changes do not suffice; two and a half do.

Two further changes: `_allocated_field_storage` preserves a fully-parameterised family and **throws**, naming the backend, when
unified storage is asked of a backend that lacks it; and the display names the residency — `_storage_family`
(`Fields.jl:1157-1160`) erases every type parameter by design, so `nameof(_storage_family(f))` structurally cannot say
"unified", and the display gains one predicate call, not a new predicate.

**Invariant 14 is not amended.** A unified field and a device field are the same storage family and combine correctly; refusing
the mix would break the very use case. That is a deliberate ruling to record.

**But mixing has a consequence revision 1 missed**: CUDA.jl *promotes* a mixed pair to unified, and the allocating broadcast
takes its output from `_first_field` (`Fields.jl:2128-2145`) while `map` takes it from `source1`. So `u_device .+ v_unified`
lands in HBM and `v_unified .+ u_device` in LPDDR — **residency is argument-order dependent**. Under invariant 1 that is new
semantics in the method set and needs a stated rule: either the allocating forms take residency from the first field argument,
documented, or they grow an explicit residency argument.

### 3.4 What must be said honestly

- **Spill is CUDA-only.** AMDGPU.jl has device and pinned-host buffers and no managed memory; gfx1100 is absent from AMD's own
  support table. `HostBuffer` is *not* a substitute: it never migrates.
- **The home box cannot validate it**; the office 5070 Ti exercises the code path on x86 software HMM, whose performance model
  is not GH200's. Same class as `PERFORMANCE.md` §7 gap 8 (`aarch64`, zero coverage).
- **Policy matters more than mechanism**: a transform's working set is the worst thing to spill (~9× on the dominant cost); cold
  fields are the right things, so residency is **per field**. §2 records that at the capacity ceilings this policy is
  unsatisfiable, and §11 records the one configuration where it is not.
- **Feature A does not reach the consumer as it stands.** `FixedDomain` holds `storage_family::SF`, one global setting, so even
  after stage 1 it can express *all unified* or *none* — and all-unified is exactly the ~9× case forbidden above. Either a
  consumer-side per-field residency policy is scoped inside stage 1, or stage 1 delivers nothing to the consumer until it does
  its own work. Say which.
- Two library traps: `CUDA.zeros/ones/fill` drop back to device memory, and cuFFT's *allocating* path returns device memory
  whatever the input. The package already transforms with `mul!` into a preallocated destination (`_forward_components!`,
  `Fields.jl:1444-1457`), so it is on the safe side.

---

## 4. Feature B — the partitioned base

### 4.1 Why this cannot be the consumer's problem

`ARCHITECTURE.md` §1 says distributed execution is "a consumer's concern if ever needed, not this field layer's". That fails on
one operation: **the Fourier transform is global**. A consumer cannot decompose the box without a distributed transform, and the
transform lives here. Everything else follows from the transform's decomposition.

### 4.2 The mathematics, and the prediction it makes

`ARCHITECTURE.md` §2 models a field as a section of a trivial bundle over a base. **Decompose the base; the fiber is untouched**
— a partition into non-overlapping blocks makes a global section exactly the tuple of its restrictions. That predicts, before
any code is read: **vertical (fiberwise) algebra is unchanged** (31 operations, base-independent by construction); **horizontal
operators are unchanged** (16, plus 12 convolution verbs — pointwise in mode space, with multipliers built from the base, so
they inherit the partition); **measure reductions integrate the base away**, so they and only they must cross the partition; the
**transform** changes representation, and the two representations are partitioned differently — that difference *is* the
transpose; and a **halo** is not new data but a cached restriction of a neighbour's section, stale the moment the neighbour
writes.

The inventory confirms it operation by operation: **59 unchanged, 20 communicate, 14 need a ruling** (`03-code-facts.md`), and
an independent per-site audit confirmed the 59 (`REVIEW-invariants.md` A8). The multipliers are the sharpest case — every
consumer indexes a per-axis wavenumber vector *by local mode index* (`DifferentialOperators.jl:360-371,193-215,417,505,583,669`;
`Convolution.jl:1286,1307`; `Reductions.jl:1243-1259`) — so **slicing the six vectors to a rank's mode range makes ~28
operations correct with zero kernel edits**. The kernel builders ride on the sliced arrays for free: `spectral_cutoff`,
`spectral_band`, `radial_kernel`, `assignment_window` and `translation_kernel(!)` build from the per-axis arrays only
(`Convolution.jl:1856-1870,1933-1951`), so decision 28's Nyquist split survives per entry and `spectral_cutoff`'s idempotence is
per-mode.

**Revision 1's global list was wrong in one place and short in another.** It ruled the six multiplier length validations
(`Fields.jl:1838-1845`) global; they compare against `field_spectral_shape(grid, layout, Val(0))` (`:1838`), which §4.4 makes
**local**, so keeping them global makes sliced vectors throw `DimensionMismatch` and §4.2's own mechanism unbuildable. **They
must become local.** And a fourth thing must stay global that the list omitted: the per-axis maxima
`maximum(squared_wavenumber_1..3)` that `_radial_spectrum_bin` sums to get the corner (`Reductions.jl:1275-1277`) — sliced
multipliers make that a *local* corner, so ranks allocate different bin counts and the `Allreduce` is ill-formed. What stays
global: `2π/L`, the `iseven(n)` Nyquist test, and those three maxima.

One more unlisted edit: the convenience constructor builds from `grid.grid_size[d]` (`Fields.jl:1889-1891`), so
`FieldSpectralMultipliers(û)` does not produce local slices without it.

### 4.3 Process model: one rank per GH200, MPI

Three independent reasons, any one sufficient. **The hardware**: a superchip is a NUMA domain, and spilled memory must be local
to the GPU that reads it. **The runtime**: KA backends are device-agnostic singletons with no device field, device identity is
task-local, and "allocations are tied to the device that was active when requesting the memory … similar restrictions apply to
library objects, like CUFFT plans." **Reach**: the same code runs across nodes.

**Process placement is part of the design, not of the job script**: one rank per GPU, device chosen from the node-local rank,
`--gpu-bind=closest` and a matching `--cpu-bind`, and a **run-time affinity check that warns once** when the rank's Grace domain
is not the one behind its GPU. Without it §2's ~9× is ~27×.

**SPMD is what makes this tolerable for the consumer**: every rank runs the same program, so the solver's hot loop is textually
unchanged. Rank-awareness lives at the edges — setup, RNG seeding, I/O, printing, tracers — and §1 records what happens when the
RNG edge is missed.

Rejected, with reasons: *one process, four devices* (per-device plans, `device!` juggling, manual NUMA placement, no
multi-node); *fiber/component parallelism* (three GPUs at best, and `curl!`, `helmholtz_projection!` and `dot` read all
components of a mode, so it needs the same all-to-all it was meant to avoid); *peer-GPU memory pooling* (capacity without
throughput). **Ensemble parallelism is not rejected here** — it is the baseline feature B must beat, judged in §11.

### 4.4 Where the partition lives: on the base

```julia
struct Grid3D{T<:AbstractFloat, P<:AbstractPartition}   # P = NoPartition() today
```

The grid stays **global** — it defines the box and the wavenumbers — and the *storage* becomes local:
`field_physical_shape`/`field_spectral_shape` (`Fields.jl:350,368`) return the rank's shape. `similar_field` (`:1030-1063`), the
six family-taking constructors (`:893-925`) and `_wrap_field` all route through those two functions and keep working untouched —
verified per site.

**`Grid3D` must stay `isbits`, and this is a hard constraint.** `_same_grid(a,b) = field_grid(a) == field_grid(b)`
(`Fields.jl:1139`), and `Grid3D` defines no `==`, so it is `===`. Today `Grid3D{Float64}` is `isbits` and `===` compares
*values*, so two independently built identical grids are equal. A partition holding an `MPI.Comm` — mutable in MPI.jl — makes
`Grid3D` non-`isbits`, and `===` then compares that field by **pointer**: two grids built from separate `Comm_split` results
compare unequal and *every* two-field operation throws "field grids must be equal", through `_check_same_domain`,
`_check_adapt_target`, `_check_matching_context` and the broadcast path. With `COMM_WORLD` everywhere it happens to work; it
breaks the moment §4.5's own recommendation (sub-communicators per direction) is followed. **The partition therefore stores the
raw `MPI_Comm` handle plus rank, size and the two index ranges — all bitstypes** — never the wrapper. That also keeps the "pure
bitstypes ride along unchanged" property `SeparableKernel`/`RadialKernel`'s `adapt_structure` asserts (`Convolution.jl:1995`).
It belongs in **stage 2**, where it is provable at home.

**The partition carries both representations' local ranges**, so a physical and a spectral field share one `Grid3D` and
`_check_field_domain_compatibility` keeps its present meaning; without that the transpose would make every transform argument
pair incompatible.

**The decomposition is NOT exact, and revision 1's argument that it would be is deleted.** That argument said decision 45's
four-argument constructor makes a remainder rank unconstructible; the constructor (`Fields.jl:155-168`) checks `grid_spacing ≈
domain_size ./ grid_size`, a property of the *global* grid, identical on every rank. It can reject nothing about a rank count;
the mechanism does not exist. The arithmetic is worse than the argument: the spectral folded extent is `N/2+1`, **odd for every
power-of-two N** — 513, 257, 1025 — so an even rank count divides it never. §4.5's flip takes it off the split axis, but the
second axis need not divide either. Therefore:

- the split axis is divided `cld(n, P)`; local shapes **may differ by one** between ranks;
- the transpose is **`Alltoallv` with per-rank tables**, never `Alltoall`; every buffer is sized `cld(n,P)`;
- **no control flow may depend on a local shape**, asserted by one `Allreduce` of a branch id in §4.6's debug mode.

The consequence the reviewers found, and the reason that last rule is a rule: `_component_offsets_align` (`Fields.jl:1378-1384`)
computes `physical_stride`/`spectral_stride` from the **local** shape and can answer differently per rank, making
`component_scratch` `Nothing` on one rank and an array on another — so `FieldTransformPlans` would be a **different concrete
type per rank**. It must be decided from the **global** shape. Same class: an allocation or pass-audit row taken on rank 0 does
not describe rank 1.

**Two allocators that also *index* are a fourth edit site, and they throw on every rank.** The function-initialized constructors
`ScalarFieldPhysical(f, grid, …)` (`Fields.jl:467-479`) and its vector twin (`:612-627`) allocate `field_physical_shape(grid,
Val(0))` — local — then loop `for k in 1:grid.grid_size[3], j in …, i in …` — global — and compute `x₀ + (i-1)Δx` from the
global origin with no rank offset. **`BoundsError` on every rank**, and it is the first line of every consumer run
(`SimulationDomain.jl:299`). Fix: iterate the rank's local index range, compute the coordinate from the **global** index. "~6
real edits" becomes ~8.

**The edit count is right and the risk it hides is not.** Of the 76 spellings of `Grid3D{`, 58 are `::Grid3D{T}` signatures (a
partial application still matches) and 13 are `G<:Grid3D{T}` bounds (the bound widens); the six field types, the plans and both
stored-kernel classes take `G<:Grid3D{T}` bounds with `grid::G` (`Fields.jl:452,520,597,665,756,845,1337`;
`Convolution.jl:334,496`) and stay concrete for free. But `FieldSpectralMultipliers` (`:1792`) is the one concrete `Grid3D{T}`
struct field, and the file records what touching it costs (`:1814-1818`): a **15th type parameter, which moves `Canonical` and
breaks three positional matchers at once** — `_is_canonical` (`:2577`), `adapt_structure` (`:2596`) and Convolution's static
collapse (`:416`), the exact failure recorded from the decision-70 change. True in count, wrong in kind for one of the six.

**The distributed generics and types live in core; only the MPI methods live in the extension.** This reverses revision 1.
`test/method_parity.jl:74` filters `m.module === mod`, so extension methods are excluded from the derived baseline by
construction — and `oracle_registry.jl`, the per-method ledger, `test/exhaustive/invocations.jl`, `absence_gate.jl` and
`peer_rejections.jl` all take their domain from method ownership too. An extension would remove invariant 1's enforcement from
the largest addition the package has ever made. So `redistribute!`, the partition types, the exchange type and any `HaloArray`
are **declared in core** (the `write_field` precedent — a bare `function … end` plus a docstring), with the MPI-specific methods
in the extension. The ledgers must additionally be extended to count extension methods — a `MODULE_BASELINE` entry, a
`public_surface` contribution and oracle rows for the MPI module, counted inside the MPI lane — or the residual gap is recorded
as one. `NoPartition` is a zero-field singleton, so nothing changes for a non-MPI user.

### 4.5 The transform: write the transpose, slab-first — with the folded axis never split

**Decision: hand-roll the transpose; do not take PencilFFTs as a dependency.** It is genuinely capable (r2c first-class,
fiber-last extra dims, chosen decomposition dims), but its CI **never runs on a GPU** (JLArrays only); a GPU/MPI synchronisation
race was fixed three months ago and **the fix covers only the point-to-point path — `MPI.Alltoallv!` is still unsynchronised**;
its GPU transpose **allocates per call** (`# TODO this allocates on GPUArrays`), against invariant 13; the ROCm plan issue is
open; and it is a single-maintainer package.

The alternative is smaller than it sounds, with a Julia reference for exactly this topology: **Oceananigans.jl deliberately did
not use PencilFFTs and hand-rolls the whole distributed transpose in ~460 lines** — a KA kernel packs a slab into a flat buffer,
`MPI.Alltoall(v)!` runs on GPU buffers, a KA kernel unpacks; sub-communicators per direction; **slab encoded in the type so the
extra transposes dispatch away at zero cost**; one rank per GPU; CI that runs 4 ranks × 1 GPU. Writing our own keeps this
package's own precedent — it owns its NUFFT, its binning kernels and its transfer kernels for the same reason.

**Slab, not pencil, at four ranks**: the measured crossover is ~384 processes (SC21, heFFTe + cuFFT on Summit at 1024³); slab
costs one all-to-all and two local stages against pencil's two and three. But the transpose layer is **parameterised by the
number of split axes from the start**, with slab as the type-dispatched specialisation, because §2 shows slab is the wrong shape
the moment a second node enters.

**THE LAYOUT IS FLIPPED FROM REVISION 1: the folded axis is never split, in either representation.** Let `a =
layout.fft_dims[1]` (the folded axis), `b = fft_dims[2]`, `c = fft_dims[3]`. **The axes are derived from `layout.fft_dims`,
never hardcoded x/y/z** — decision 41 runs three folds across the suite, and the distributed lane must run at least two.

```
physical  (a, b whole; c split)   --r2c along a, fft along b, both local-->
                                  --ONE all-to-all (Alltoallv)-->
spectral  (a, c whole; b split)   --fft along c, local-->
```

**Why, against revision 1's folded split.** All five of the half-spectrum's index-based special cases live on the folded axis
and are resolved by **local** index, so keeping that axis whole makes every one of them correct **with no edit at all**:

- `_parseval_weight` (`Reductions.jl:945-951`) fills `T(2)` over `size(field_data(f), folded)` and sets `weight_host[1] = 1` and
  `weight_host[folded_length] = 1`. Under the rejected layout ranks 1–3 would give two *interior* planes weight 1 instead of 2 —
  reaching `weighted_inner`, 8 consumer sites per step.
- `inner` (`:895-897, 911-913`) subtracts `_folded_abs2_plane(data, folded, 1)` and `…, size(data, folded))` — the same two
  local indices, reaching `l2norm`, `var`, `std`.
- `_spectral_shell_bin_kernel!` (`:1249-1252`, selected at `:1283-1291`) takes `nyquist_index = spatial_shape[folded]` and tests
  the **local** mode index *inside the fused kernel* — a signature change and a new `pass_audit.jl` row, had it been needed.
- `reality_residual` selects `stored_planes = iseven(grid_size[folded]) ? (1, size(data, folded)) : (1,)`
  (`Fields.jl:2701-2702`) — the **local** first and last plane. Under a folded split *every* rank would project its own first
  and last local plane, imposing Hermitian symmetry on six interior planes at P = 4 that are not self-conjugate — **and it
  lowers the reported residual**, so the package's own diagnostic would certify the corruption. The sharpest single argument for
  the flip.
- `reality_projection!` (`Fields.jl:2840-2871`, decision 83 — the consumer calls it **7× per step**) selects planes the same way
  and writes the average back **in place**: not a wrong diagnostic, a corrupted field.

Under the rejected layout the α(k) multiplicity would have been a systematic ~0.2% bias at 1024³/4 ranks, same sign on every
rank, **inside the kinetic energy that drives the consumer's forcing** — precisely the class `reality_projection!` exists to
remove. Three further counts point the same way: `N/2+1` is odd at every power-of-two grid, so no even rank count divides the
folded axis; splitting dim 1 chops the stride-1 axis, giving contiguous pack runs of 513/P complex (~2 KiB) against dim 2's 513
complex (**8 KiB**); and `iseven(n)` on a whole axis needs no global lookup.

**The price, stated: the reality pairing now crosses ranks and the mirror exchange is paid** (§4.7).

**The mirror exchange has two peers, not one.** For an equal split of `n_b` over `P`, rank `r ≥ 1` mirrors to the global block
`[(P-r-1)B+2, (P-r)B+1]`: **all of rank `P-1-r` except one plane, plus exactly one plane of rank `P-r`** — the `+1` in
`mod(-(j-1),n)+1` shifts the block across a rank boundary. One Recv against two Sends is a hang. Every buffer is sized `cld(n_b,
P)`.

**What r2c costs across a transpose — three prices, each now answered.** Oceananigans used c2c to dodge all three; the
divergence has to be paid for deliberately. (1) **The folded extent is odd**, so no even rank count divides it — answered by
never splitting it. (2) **The half-spectrum's special planes are an ownership question, not a geometry question** — answered by
the same flip. (3) **Asymmetric buffers and a consumed destination**: the forward pack is complex `(Na/2+1)·Nb·Nc/P` and the
physical side real `Na·Nb·Nc/P`, two buffer shapes rather than one; and the inverse c2r destroys its input, so distributed it
consumes the *unpack destination*. **Invariant 11's size contract is therefore amended**: honouring decision 64's preservation
promise needs scratch of one local spectral field **plus** the pack/unpack pair, not one field.

**GPU-aware MPI needs a run-time fallback, and it is not optional.** This design puts `MPI.Alltoall(v)!` directly on device
buffers. Arrhenius' GPU-awareness is *not documented* on the NSC pages and needs `MPICH_GPU_SUPPORT_ENABLED=1` **and** the GTL
linked **and** `MPIPreferences.use_system_binary()` — three things each silent when wrong. The home box's default JLL MPICH is
not GPU-aware, so handing it a `ROCArray` pointer gives a segfault or silently wrong data. **The pack/unpack layer selects
device-direct or host-staging at run time from a probe at init, with an env override** — one buffer pair and one branch outside
the hot path. It de-risks the home box, the office box and Arrhenius at once, and without it §7's "everything is testable at
home except performance" is false for the one path that carries the design.

Where it lands in the existing code is kind: decision 76 already made `_forward_components!` apply **one 3-D transform per
contiguous component** (`Fields.jl:1444-1472`), so what is replaced is the `mul!`, not the loop. `FieldTransformPlans` gains one
type parameter for the exchange object (`Nothing` when serial). `adapt_structure` (`:2608-2630`) rebuilds from
`field_*_shape(grid, …)` and so carries the partition through the grid — **provided the rebuilt plan dispatches to the
distributed constructor through the grid's `P`**, or `adapt(Array, plans)` silently turns one distributed transform into four
wrong local ones.

### 4.6 Reductions become collectives

Every terminal reduction needs one Allreduce, and the accumulators are small: a scalar, a `FiberVector` (3), a `FiberTensor2`
(9), an `NTuple{n}` for decision 72's tuple form (one Allreduce of *n* reals — the decision's point survives), and **three**
O(N) vectors for the radial pair (the two shell vectors and `count_bins`). The shell count comes from the **global** corner
(§4.2) or ranks disagree on the bin count and the Allreduce is ill-formed — which is undefined behaviour, not an error.

- **Bitwise thread-count invariance does not extend across ranks.** The fixed reduction tree (`Reductions.jl:305-323`) is
  bitwise-invariant in thread count by construction; an Allreduce is not invariant in rank count. Same *class* of exemption as
  the two Atomix accumulators (`threading.jl:340-341`) — tolerance, not bitwise — but a new member, and it also removes bitwise
  comparison against the serial path, the package's usual first debugging move. Two documented consumer equalities stop holding
  unless the tuple and scalar forms reduce over identical trees (`kinetic_energy_and_dissipation`'s "bitwise identical to its
  single call"; `Forcing.jl`'s 3-tuple comment): require identical trees, or retract both docstrings.
- **The hot loop gains 5–8 blocking barriers per step** where none existed. On the default consumer configuration: 3 × the
  3-tuple `weighted_inner` (one per RK3 stage), 3 × `_injection_amplitude`'s branch on it, 1 × `max_speed`, 1 ×
  `scalar_variance`, plus the warm-up's k/ε. The call sites are textually unchanged; four of them gate a branch. It also
  invalidates decision 72's recorded rationale — the readback is no longer the dominant latency, the barrier is.
- **Deadlock is a property of predicates, not of syntax.** "A collective in a conditional" is the wrong rule: the consumer has
  five such sites today (`SimulationRun.jl:1193-1195,1311-1321`; `Forcing.jl:440-443,774-776`; `Observables.jl:350`) and **all
  five are correct**, because each predicate is a function of already-reduced values. A lint for that shape gives five false
  positives and zero defects. **The invariant: any predicate that gates a collective, or decides loop continuation, must be a
  pure function of collective-reduced values**, and the verb that discharges it is `MPI.Allreduce(pred, &, comm)`. The real
  hazard is the one the old rule did not cover: `run!`'s `keep = callback(sim); keep || break` (`SimulationRun.jl:1100-1108`)
  runs **arbitrary user code on every rank**, and a rank returning `false` while another returns `true` leaves the survivors
  inside `advance!` and its 5–8 collectives. One line — `keep = MPI.Allreduce(keep, &, comm)` — closes the class. The opt-in
  sequence counter then *checks* the invariant instead of replacing it, and is **on by default in the test lane**.
- **Two members of the same class.** `MPI_MAX` has no standard-defined NaN behaviour, and the usual `if (a > b)` kernels drop
  NaN because every comparison with NaN is false, so the consumer's blow-up guard (`SimulationRun.jl:892,899`, built on
  `maximum(norm, u)`) can go silent — reduce finiteness explicitly with `Allreduce(isfinite(local), &)` rather than inferring it
  from a MAX. And **a throw on one rank is a deadlock**: the package validates by throwing at ~40 sites, several rank-dependent
  under uneven division, and the survivors block in the all-to-all until Slurm kills them with no stack trace. Either every
  rank-dependent validation is itself collective, or the extension installs a global handler calling `MPI.Abort` — the second is
  cheap and belongs in stage 3.
- **GC becomes collective jitter.** Invariant 13 keeps the hot loop allocation-free, but the *documented* exemptions remain —
  the mixed spectral `inner(f,g)` materialises O(N²) correction planes per call. With ~41 collectives per step one rank's GC
  stalls all four every time it fires, and `PERFORMANCE.md` finding (y) records device allocation being
  process-history-sensitive to 3.2×. The bounded allocators are reclassified as collective-jitter sources and pinned to zero in
  the distributed lane.

Core stays MPI-free behind one internal generic whose `NoPartition` method is the identity.

### 4.7 The reality condition

`reality_residual` pairs `(j,l)` with `(mod(-(j-1),na)+1, mod(-(l-1),nb)+1)` where `na, nb` are the **stored extents of the two
non-folded axes** (`Fields.jl:2641-2653`), and `_owns_pair` (`:2743-2745`) assumes both members addressable.
`reality_projection!` (`:2840-2871`) pairs identically and writes back in place.

**Under §4.5's layout the plane *selection* is correct unchanged** — the folded axis is whole, so `size(data, folded)` is the
global extent and `stored_planes` names the true zero and Nyquist planes (§4.5 lists what the rejected layout would have cost
here). **The *pairing* is what now crosses ranks**: axis `b` is split, so `na` is a local extent and the partner of a local `j`
is on another rank.

The fix is **one pairwise block exchange with the mirror rank(s) per stored plane**, and it makes the kernel *simpler*: after
the exchange each rank computes `m = (x + conj(y))/2` for its own elements and `_owns_pair` is not needed at all, the mirror's
result being `conj(m)` by construction. Two constraints: **two peers, not one** (§4.5), and the pairing extents `na, nb` come
from the **global** `b` and `c` extents, not from `size(data, ·)`.

Cost at 1024³ over 4 ranks: a plane block is ~4 MiB ⇒ ~27 µs on NVLink against ~10 ms for the transform, ×7 projector calls per
step ≈ **~0.2 ms/step**. ESTIMATE. The residual's terminal `maximum` needs one Allreduce(MAX), and per §4.6 an explicit
finiteness reduction beside it. Only the ranks owning the two stored planes do work and two of four launch no kernel, so the
**launch must sit outside the ownership branch**.

### 4.8 The point/transfer layer

Revision 1 called this deferrable "because the flow solver does not need it; only Lagrangian tracers do", which inverts the
consumer's priority: **the tracers are the science**, the flow is the carrier, and the one published validation is a tracer
comparison against TurTLE. §9 re-stages it.

- **The kernels' component stride is the *global* point count, and this defect is created by §4.4's own ruling.** `interpolate!`
  and `anterpolate!` pass `prod(grid.grid_size)` as `points_per_fibre` (`Interpolation.jl:1146,1265`); the kernels compute
  `number_of_fibres = length(field_values) ÷ points_per_fibre` (`:974,1032`). Global grid + local storage gives `⌊(3N³/P)/N³⌋ =
  0` for any `P > 3`: **the fibre loop never runs and `interpolate!` returns its destination untouched**, `anterpolate!` writes
  nothing. Silent. Same at the NUFFT kernels (`:1946,1978`). **Rule: a kernel that indexes storage takes the LOCAL shape and its
  product; only a normalization takes the grid** — `DirectDFT`'s `1/prod(grid.grid_size)` (`:1500`) stays global.
- **Halo width is `n` below and `n + 1` above**, asymmetric, from the single stencil all spline schemes share (`2n+2` nodes at
  offsets `-n … n+1`, `Interpolation.jl:169,975-979`). `CatmullRom` → 1/2; `Lalescu(3,3)` → 3/4. `m` does not enter.
- **`_wrap_step` hardcodes "the array's extent is the period"** (`:954`), so on a sub-box array it silently folds a stencil back
  onto the rank's own far side — and the scatter would still pass a total-mass check, partition of unity holding locally. The
  kernel needs three quantities where it has one: local extent, global period, rank offset.
- **An out-of-slab point is memory corruption, not a `BoundsError`**: `_locate` (`:417-421`) has no range check and the kernel
  body is `@inbounds`. `point_traversal_order` *saturates* out-of-range points (`:596-602`), so it is not an ownership test
  either.
- **`_base_count` for a decomposed `PointSet` must become the global M** (`Reductions.jl:107`), or every point-measure reduction
  is normalised by a slab's count.
- **Decision 59, re-costed.** Revision 1 said invariant 9 is "amended for halos only; fields without halos keep the rule
  verbatim". Wrong twice. *(i) The property is not per-field.* Ownership stands in for *one section's element `n` is another's
  element `n`*, and `_fiberwise_pass!` launches `ndrange = length(targets[1])` (`FiberSections.jl:815-830`) reading
  `arrays[i][n]` under `@inbounds` — so a halo field beside a plain field *on the same grid* reads out of bounds with no error.
  `_check_same_domain` needs a **halo-width equality** clause and a halo field must refuse a non-halo peer. *(ii) Decision 59
  also makes three `===` shortcuts exhaustive*: the scratch arity's anti-alias test (`Fields.jl:1541-1544`, invariant 11),
  `adapt!` (`:2554`) and `reality_projection!`'s `destination !== source` (`:2846`). A `HaloArray` preserves them **only if it
  can never be constructed as a window onto another section's buffer** — an enforced constructor property, not a convention.
  `_check_owned_storage` (`FiberSections.jl:119-126`) rejects a `SubArray` anywhere in the parent chain, so "allocate padded,
  hand over the interior view" stays unconstructible. **The hardest single blocker in the document**, and it should be settled
  before the point stage opens, since it may move where the partition lives.
- **Migration has no identity to migrate.** A point *is* its row index; `PointSet` is one owned `(M,3)` array, and every
  `PointValues` beside it plus the consumer's velocity-history ring are M-indexed. A migrate verb must take the whole cortège —
  the shape `displace!` already has — and either introduce a point identity or accept that trajectories lose theirs.
- `DirectDFT` is all-to-all in both directions by construction; `NUFFT` owns a global 8×-oversampled FFT and can only follow the
  distributed transform.
- **Default to correctness**: `interpolate!` on a partitioned field performs its own halo exchange, with a keyword to skip it
  when the caller knows the halo is fresh.

### 4.9 Persistence and display

`write_field` does `g["data"] = Array(field_data(field))` (`ext:61`) — whole array, one writer, no hyperslab, no MPI-IO property
list, and the attributes would claim the slab is the box. Left alone a decomposed run gets either four files each claiming to be
the full box (silent) or three ranks throwing on a shared handle while rank 0 walks on (hang). Two honest options: collective
MPI-IO hyperslabs (right, more work, needs a parallel HDF5 build), or gather-to-rank-0 (simple, capped by one rank's memory).
**`write_field` on a partitioned field throws until one of them exists, and that throw ships with stage 2** — the cheap half,
and it converts a silent corruption into an error.

A restart at a different rank count needs redistribution either way — which is `redistribute!`, the one verb that also expresses
gather and scatter as special cases. **It restores the layout, not the summation tree**: the consumer's frozen "a restored run
continues the checkpointed one bitwise" (`test/hdf5_checkpoint.jl:113`) degrades to *same rank count only*, because every
`inner`/`weighted_inner` SUM is order-dependent even though `max_speed` (MAX) is not. Say so where the contract is written.

The display already separates `grid:` from `stored:`, so a decomposed field prints a **local** `stored:` against a **global**
`grid:` — plus the rank's identity and, for feature (A), the residency. `test/display.jl` is a **derived completeness gate over
every concrete package struct**, so `NoPartition`, the partition type, the exchange object and any `HaloArray` each need a
`show` or a cited exemption or `Pkg.test()` fails. It is the cheapest definition-of-done item in the document and applies to
every stage that adds a type.

---

## 5. What a consumer writes

Revision 1 measured the diff at *this package's* API and claimed one line. At the API the consumer actually uses the claim is
false: **IT never constructs a `Grid3D`** — `FixedDomain(; grid_points_per_axis, side_length, dealiasing, element_type,
array_type)` (`SimulationDomain.jl:289`) builds it, and `Simulation(grid_points_per_axis = 1024, …)` builds the `FixedDomain`. A
`partition` keyword must be threaded through both before any consumer line changes, and the first thing `FixedDomain` then does
is call `VectorFieldPhysical((x,y,z) -> …, grid; array_type)` (`:299`), which `BoundsError`s on every rank (§4.4).

Inside this package the surface really is unchanged, and that is the claim worth making:

```julia
using MPI, GBGPeriodicFields
MPI.Init()

grid   = Grid3D((1024, 1024, 1024), (2π, 2π, 2π); partition = SlabPartition(MPI.COMM_WORLD))
layout = RealFourierLayout(grid)

u  = VectorFieldPhysical(CuArray, grid, layout)     # shapes are local, the grid is global
û  = VectorFieldSpectral(CuArray, grid, layout)
plans = FieldTransformPlans(u)                      # distributed because the grid is
mult  = FieldSpectralMultipliers(û)                 # local wavenumber slices (§4.2: needs one edit)

to_spectral!(û, u, plans)                           # one all-to-all, same verb
helmholtz_projection!(û, û, mult)                   # zero communication, same kernel
E = inner(û, û)                                     # collective; same value on every rank
```

**The asterisks, as a list rather than a clause.** The program runs under `mpprun`/`srun` with four ranks. Printing and logging
are per-process, so `@warn … maxlog = 1` (`Forcing.jl:441,774`) and `@info` (`SimulationRun.jl:532`) fire four times — ~12
sites. RNG seeding must be globally indexed (§1, §8). Any predicate gating a collective must be rank-uniform and `run!`'s `keep`
must be Allreduced (§4.6). Checkpoint writing throws until §4.9 lands, and restart at a different rank count is no longer
bitwise. The hot loop gains 5–8 barriers per step. Points must be migrated when they leave a sub-box. **The consumer-side diff
should be published as a `file:line` list before any schedule is agreed**, not summarised.

---

## 6. Invariants: what is amended, and what is not

| invariant | verdict |
|---|---|
| 1 method set is the spec | **unchanged in kind, at risk in enforcement**: no operation a serial user can call is added, but the derived ledgers cannot see an extension — §4.4 puts the generics and types in core for exactly this reason |
| 2, 3, 6, 7, 8, 10, 12 | **unchanged**: the fiber is never split (slabs cut the base), a partition is a property of space, and nothing here touches representations, indexing, piracy, fiber-fiber methods or α/β |
| 4 zero mode ×`prod(grid_size)` | **amended**: the scale stays global, `_spectral_zero_mode_data` (`Fields.jl:1663`) must stop hardcoding local `(1,1,1)`, and five more sites of the same class are listed below |
| 5 Nyquist split | unchanged — the folded axis is never split (§4.5), so `iseven(n)` and the multiplicity both read a whole axis |
| 9 aliasing safe; a section owns its storage | **amended more broadly than revision 1 said** (§4.8): the property is not per-field, `_check_same_domain` needs a halo-width clause, and three `===` shortcuts stop being exhaustive unless a `HaloArray` can never window another section's buffer |
| 11 transform input contract | **its SIZE contract is amended** (§4.5): the distributed c2r consumes the unpack destination, so decision 64's promise needs one local spectral field **plus** the pack/unpack pair |
| 13 allocation-free | **at risk, and wider than revision 1 said**: the transpose buffers and the halo exchange must be plan-owned (`allocations.jl:304,306,329-330,338-339`), *and* the documented bounded allocators become collective-jitter sources (§4.6), pinned to zero in the distributed lane |
| 14 one precision, one storage family | **unchanged, and NOT the distributed refusal**: by `_storage_family` two `CuArray`-backed fields are the same family whatever their partition, so a distributed/local mix is a **grid** refusal — free once §4.4 keeps `Grid3D` `isbits`. Unified and device memory are the same family and combine, with §3.3's argument-order rule |
| — bitwise thread-count invariance | **weakened across ranks** (§4.6); a new member of the existing tolerance class, and it removes serial-vs-parallel bitwise comparison as a debugging tool |

### The invariant-4 class: six silent wrong answers

Revision 1 found one member and stopped. The enumeration is the right method; it was run incompletely.

1. **`_spectral_zero_mode_data`** (`Fields.jl:1663,1668-1670`) hardcodes the DC mode at local `(1,1,1)`, so on a non-owning rank
   every `+ constant` and every spectral `integral`/`mean` reads and writes the wrong mode. **Live today under any
   decomposition.**
2. **The transfer kernels' `points_per_fibre`** (`Interpolation.jl:1146,1265` → `:974,1032`; NUFFT `:1946,1978`) gives
   `number_of_fibres = 0` for `P > 3` ⇒ `interpolate!` returns its destination untouched. **Created by this design's own
   ruling** (§4.8).
3. **The six multiplier length validations** (`Fields.jl:1838-1845`) must become local; revision 1 ruled them global, which
   makes §4.2's mechanism unbuildable. Loud (`DimensionMismatch`) but blocking (§4.2).
4. **The radial shell corner** (`Reductions.jl:1275-1277`) becomes a local corner once the vectors are sliced ⇒ different bin
   counts per rank ⇒ an ill-formed `Allreduce`, which is undefined behaviour, not an error (§4.2).
5. **`radial_correlation`'s minimum-image** (`Reductions.jl:1395-1401`) derives the separation from `@index(Global, NTuple)` —
   local — against global `points_1..3`, so **every rank treats its own origin as `r = 0`**. It needs the rank's index *offset*.
6. **`_base_count` for a decomposed `PointSet`** (`Reductions.jl:107`) must become the global M (§4.8).

Two loud ones, listed so they are not mistaken for absent: the function-initialized field constructors (`Fields.jl:467-479`,
`:612-627`) `BoundsError` on every rank (§4.4); and `_locate` + `@inbounds` makes an out-of-slab point **memory corruption
rather than a `BoundsError`** (§4.8).

---

## 7. Tests, benchmarks, and the oracle problem

- **A fourth opt-in environment**, beside `test/gpu/{rocm,cuda}`: an MPI lane launched with `mpiexec -n 4`, needing a launcher,
  rank-aware device binding, and a reduction of four processes' result trees to one exit code. `Pkg.test()`'s single-process
  model does not reach it.
- **The oracle is cheaper than it looks.** A 4-rank-vs-1-rank comparison is *relational*, which decision 55 forbids as the only
  evidence — but **every defect in §6's list is caught by an oracle the suite already has**: Parseval, `sum(spectrum) == inner`,
  `C(0) == inner`, `reality_residual == 0` after `reality_projection!`, transfer adjointness, and `generated_analytic.jl`'s
  closed forms. The distributed lane is "these existing oracles, under decomposition", with 1-vs-4 as a subordinate check.
- **What a green 4-rank suite still would not prove**, and both must be added: that the collective **sequence** is identical on
  all ranks for any input (§4.6's counter, on by default in the lane), and invariance in the **rank count** beyond 1-vs-4 — 4
  ranks over 513 modes is one uneven configuration, not a family, and an ownership-by-offset bug hides in exactly that gap. Run
  1, 2, 3, 4 ranks and at least two `fft_dims` folds (§4.5).
- **The ledgers.** §4.4 puts the generics and types in core so `method_parity.jl`, `oracle_registry.jl`, the per-method ledger,
  `absence_gate.jl` and `peer_rejections.jl` can see them; the MPI module additionally gets its own `MODULE_BASELINE` entry,
  `public_surface` contribution and oracle rows, counted inside the MPI lane. `test/display.jl`'s derived struct gate applies to
  every new type (§4.9), and `redistribute!`'s refusal gate is a **peer rejection**, not an `adapt` test (§6, invariant 14).
- **Frozen numbers move**: 206/122/per-module in the same commit as any new verb; the pass audit's gather traffic (`3·4³·M`) if
  a halo is re-read; the benchmark baselines are `<host>-<backend>[-tN]` with no rank field.
- **Do not gate on `MPI.has_cuda()`** — it returns `false` on MPICH and Cray-MPICH even when support is present. Use MPI.jl's
  own multi-GPU example programs.
- **Acceptance is absolute throughput, not scaling efficiency.** Strong scaling needs a single-device control and the
  configurations that justify feature B have none — they do not fit one GH200 — so the only available control is ≤768³, the
  regime where the model is *least* favourable. State acceptance as **achieved GB/s per GPU against the roofline, and achieved
  all-to-all GB/s against 150 GB/s per pair**. Compounding it: this package's GPU measurement *regime* has twice been silently
  wrong for months (`gcsample`, then the CUDA probe that never ran), each caught by an internal-consistency tell in the table,
  and a rank sweep has no such tell. **Add a device vector-transform mechanism to the canary**, which the package already knows
  is blind there.

---

## 8. The consumer

IT has no MPI anywhere today, and `FixedDomain` carries a storage family and nothing else about placement. Under SPMD its time
loop is textually unchanged; the work is at the edges, and three items are not bookkeeping.

- **Seeding is a correctness problem, not a reproducibility problem** (§1): `Forcing.jl:902` draws the same noise on every rank
  *inside the hot loop*; `State.jl:156,:257` the same in the initial condition, giving a degenerate slab-periodic field on the
  seeded — i.e. reproducible — path; `Particles.jl:172` changes what `number_of_particles` means. The repair needs something
  from this package: **expose the rank's global index range**, so a consumer can seed per global block. A counter-based RNG
  keyed on the global linear index is the only spelling that is both reproducible and rank-count-invariant.
- **Restart at another rank count voids IT's strongest contract** (`test/hdf5_checkpoint.jl:113`): MAX survives, every SUM does
  not (§4.9).
- **`compute_audit` loses its currency, not just its numbers**: it freezes scalar-equivalent FFT counts on the premise that the
  flop budget is the transform count times FFTW's constant, and under a slab decomposition one transform is two local stages
  plus an all-to-all. `memory_audit` becomes a per-rank ledger.

The rest: ~14 scalar-reduction sites become collectives (`Observables.jl:79,137,140,169,215,255,281,349,353,382`;
`Forcing.jl:438,731,787,906`; `SimulationRun.jl:948`), 21 transform sites become distributed, `read_simulation` (`ext:383,403`)
passes a global `number_of_particles` into a rank-local set, and the tracer cortège must migrate. **A real project on the
consumer's side, to be opened on the existing channel before this package commits to a schedule.**

---

## 9. Staging

Re-ordered from revision 1 on three grounds: `aarch64` is an unmeasured platform and must not be a confounder inside a campaign;
checkpoint-restart is what makes ≥1024³ possible at all, so it cannot follow the first decomposed solve; and the point layer is
the consumer's payload, not an optional extra.

| stage | content | ships independently? | verifiable at home? |
|---|---|---|---|
| **0** | The live defects: the family constructors destroying the memory kind (§3.2), the zero mode at local `(1,1,1)`, the three divergent one-level `parent` spellings. §6's other five are decomposition-only and land with their stage | yes | yes |
| **A** | **`aarch64` alone**: build and `Pkg.test()` green on a Grace node. No distributed code, no spill | yes | no — but one job, not a campaign |
| **1** | **Feature A**: the allocator A/B (§3.3), family preservation, residency in the display and the argument-order rule, the CUDA-only suite axis | yes | code path on the CUDA box; **the choice only on Arrhenius** |
| **2** | Partitioned base: `Grid3D{T,P}` **staying `isbits`**, local shapes, the two indexing constructors, sliced multipliers + the convenience constructor, compat predicates, `redistribute!` declared in core, `show` for every new type, and **`write_field` throwing on a partitioned field** | yes, inert | yes |
| **3** | The slab transpose + distributed plans (**with the device-direct / host-staged transport as a dispatched policy, both exercised**); the reality condition and its mirror exchange; collective reductions; the predicate rule and `MPI.Abort`; **gather-to-rank-0 persistence** | no — 2+3 is the first useful milestone | correctness yes (4 ranks on 1 GPU, and 4 CPU ranks); the production transport only with a GPU-aware MPI built |
| **4** | The point layer: the decision-59 ruling, halo storage, the exchange, migration, the `points_per_fibre` and `_wrap_step` repairs | yes | yes |
| **5** | MPI-IO hyperslab persistence, if gather-to-rank-0 proves too small | yes | yes |
| **6** | Arrhenius: GPU-aware MPI, NUMA binding + the affinity check, the scaling and spill measurements, the benchmark rank axis | — | no |

Three definition-of-done corrections revision 1 got wrong. **Stage 1's allocation row is vacuous** — `test/allocations.jl`
measures with `@allocated` on the **CPU** by explicit design and there is no CPU unified memory, so the row is measurable on
neither lane; replace it with a **residency round-trip assertion** (allocate unified; round-trip through `similar_field`, a
constructor and a broadcast; assert the memory kind survives each). **Stage 1 permanently breaks the 491/491 ROCm/CUDA count
parity** the package treats as an invariant: state the asymmetry, refreeze both counts with the reason in the same commit, and
record the expected delta so a *different* divergence is still a finding. **Stage 2 is inert only while `NoPartition` is
`isbits`** — that constraint is stage 2's, provable at home, and must not drift into stage 3; stage 2 still ships a breaking
`Grid3D` parameter, a new public verb (refreezing 206/122/Fields-130) and consumer-side work with zero exercised partitioned
code, so it is inert, not free.

**Effort**: stages 0–1 small; stage A one job; stage 2 medium; **stage 3 is the risk**; stage 4 comparable to stage
3. In this package's own units, of the order of the shared-tooling programme (~17–25 sessions), plus the consumer's
work, and it should not be started without deciding it is the priority.

---

## 10. What is not known, and what would change the answer

- **No published compute/communication split exists for a single-node 4-GPU 3D FFT**; the one directly measured multi-GPU case
  reports >90% communication on 24 V100s across nodes. §2's revised estimate (comm ≈ 0.4–1× compute intra-node, ~2.5–3.5× on
  four GPUs for transform-bound work) is **arithmetic, not a measurement**, and the first Arrhenius run should check it before
  anyone plans around it.
- **Wall time, not memory, may be the binding constraint above 512³** (ESTIMATE, from the consumer's measured 0.275 s/iter at
  128³ F64): work grows ×733 to 1024³ and the step count ×8, so a 50-turnover warm-up is ≈ 2–3 months on a full node, ≈ 1 in
  Float32 — a chain of 15–30 Slurm jobs. If that is even half right, **checkpoint-restart chaining is what makes 1024³ possible,
  not 4-GPU throughput**, and the stage 3/4 priority follows the chain. **Measure one 256³ step on a GH200 before ruling on
  scope.**
- Whether Arrhenius' MPI is GPU-aware under `mpprun` out of the box; the correct `CRAY_ACCEL_TARGET` for sm_90; whether NSC's
  128 GB/superchip or Alps' 120 GB is right.
- Which host allocator wins for streaming access on GH200 (§3.3) — unanswerable on any hardware here.
- Whether `PencilFFTs` on a `ROCArray` works end to end now that AMDGPU 2.8.0 has the `unsafe_wrap` method its open issue names
  — relevant only if the owner prefers the dependency to the hand-roll.
- Two cheap experiments would de-risk the most, and both need consent: MPI.jl's own multi-GPU all-to-all example on the home
  box, and a single-rank distributed plan on a `ROCArray`. A second GPU at home would make the production transport testable;
  that is a purchase, not a design decision, and is recorded here rather than staged.

---

## 11. Three options, compared on the same terms

**The threshold decides everything else, so it comes first.** Grepping the consumer's whole repository — docs, tests, runbook,
`CLAUDE.md`, decision log — for a resolution returns **128³ (×18), 256³ (×16), 384³ (×2) and nothing above**; the published
validation is 128³, Float64, Re_λ = 67.2. The largest grid it has ever named, 512³ Float64, is ≈ 27 GiB of live set against one
GH200's 96 GiB — **three times the headroom, needing neither feature**. Feature B is aimed three to four octaves above anything
the consumer has recorded as a target, so **the first ruling the owner must give is the science one**, and its honest form is
not "what fits in memory?" but *"what is the largest grid whose warm-up fits an allocation chain?"* (§10).

**(i) Stage 0 only.** Fix the live defects: the family constructors (§3.2), the zero mode, the three `parent` spellings. Every
one is real today, every one is verifiable on the hardware the owner has, and the scope statement does not move. A few sessions.
This is the floor and is worth doing whatever else is decided; §6's other five join it as each decomposition stage lands.

**(ii) Feature A only — and its case is not the one revision 1 made.** The "~1040³ with spill" headline needs 54% of a *hot*
live set in LPDDR, which §3.4's own policy forbids and §2 prices at ~5× per step; with 2.5× the work and 1.35× the steps that is
**≈ 20× the wall time of 768³ for the same physical time** — nominal capacity, not usable resolution. **The honest case is 1024³
Float32, velocity-only**: ≈ 72 GiB live + 12 GiB frame + 24 GiB plans ≈ **108 GiB against 96 GiB HBM**, a 12% gap closed by
spilling 10–15% of the live set for a step ≈ 1.2× slower, **with no MPI, no partition and no decomposition**. The consumer
already treats precision as a studied fitness axis and already runs 384³ in Float32. This is the strongest argument in the
document for feature A, and revision 1 did not make it. Its honest cost: §3.3's allocator is unchosen and unchoosable here, and
the consumer needs per-field residency before any of it reaches a run (§3.4).

**(iii) Ensemble parallelism — the baseline feature B must beat.** Revision 1 dismissed it in §4.3 as "not this question" and
then, in §11, named throughput-across-runs as the criterion deciding against feature B: the same option judged twice, out of
scope once and decisive once, never joined. Joined: on a scheduler that allocates **whole 4-GPU nodes**, four independent 1024³
runs on one node is **4× the throughput** of one 4-GPU 1270³ run, at **zero** engineering cost, today. Feature B earns its cost
only when one run must be larger than one GPU can hold *and* time-to-solution per run outranks throughput across runs — i.e.
when the science needs a single flow above ~1000³ and a parameter sweep will not do.

| | cost | largest single run | per-step | consumer work | verifiable at home |
|---|---|---|---|---|---|
| (i) stage 0 | a few sessions | ~768³ F64 | 1× | none | fully |
| (ii) + feature A | small + an unchosen allocator | ~1024³ **F32 velocity-only**; ~990³ F64 at ~5× | 1.2× in the F32 case | per-field residency in `FixedDomain` | code path only |
| (iii) ensemble | zero | ~768³ F64, ×4 concurrently | 1× | none | fully |
| (B) four GPUs | ~17–25 sessions + the consumer's project | ~1200³ F64 (~1550³ at ~5×) | 2.5–3.5× on 4 GPUs | a real project (§8) | correctness yes; transport and performance no |

---

## 12. Rulings the owner must give

1. **The science target** — §11's threshold. First, not third: it decides whether anything past stage 0 opens.
2. **Scope**: is distributed memory in scope for the field layer? (§4.1 gives the argument; `ARCHITECTURE.md` §1,
   `PERFORMANCE.md` §1, decision 37 **and the four roadmap items that rest on it** all change — §2.)
3. **Stage 0 independently**: fix the live defects now, regardless of everything else? (recommend yes)
4. **Feature A alone**, CUDA-only, with an allocator that cannot be chosen from here: proceed on §11(ii)'s Float32 case?
   (recommend yes — small, and stage 3 needs it anyway)
5. **The transform**: hand-roll the slab transpose, parameterised by the number of split axes (recommended), versus depend on
   PencilFFTs.
6. **Decision 59**: how it is relaxed for halo storage, or whether a `HaloArray` carries it — *including* the halo-width clause
   in `_check_same_domain` and the three `===` shortcuts. **Settle before stage 2 opens**; it may move where the partition
   lives.
7. **Determinism**: accept that reductions are not bitwise-invariant in rank count, that serial-vs-parallel bitwise comparison
   is gone as a debugging tool, and that two consumer docstrings must be retracted or their trees made identical.
8. **The consumer**: open the channel now, or design here first and hand over a finished interface? The seeding repair (§8)
   needs something from this package either way.

---

## Revision 2 (2026-09-16) — where every ruling and review item landed

**Rulings.** R1 §4.5 (layout flipped; §0.1). R2 §4.5 + §4.7 (two peers, `cld(n,P)`). R3 §4.5 (axes from `layout.fft_dims`) + §7
(two folds). R4 §4.4 (exactness argument deleted; `Alltoallv`, no control flow on a local shape, `_component_offsets_align` from
the global shape). R5 §6's list (a→2 + §4.8; b→3 + §4.2; c→4 + §4.2/§4.6; d→5) and §4.8/§6 for `_base_count` and
`_locate`+`@inbounds`. R6 §4.4 + §9 stage 2. R7 §6 invariant 14 + §7 (peer rejections). R8 §4.8 (not per-field, halo-width
clause, three `===` shortcuts). R9 §4.4 (core) + §7 (ledger extension or a recorded gap). R10 §6 invariant 11 + §4.5 price 3.
R11 §2 (overhead line, spilled column, "at GPU speed" deleted, slab cost model, multi-node withdrawn). R12 §3.3 (three-way A/B;
portable surface, not a blessed mechanism). R13 §2.2 + §4.3 (affinity check) + §9 stage 6. R14 §4.5 (transport probe) + §9 stage
3. R15 §7 (absolute throughput; canary mechanism). R16 §9 (a→stage A; b→persistence into stage 3, point layer to stage 4;
c→residency assertion; d→recorded count asymmetry). R17 §4.6 (predicate invariant, `run!`'s `keep`, `MPI_MAX` NaN). R18 §1
(moved from §8, detail kept in §8) + §5 (`FixedDomain`, the indexing constructors) + §4.4. R19 §11. R20 §1 (value-vs-index),
§4.2 (builders ride free), §4.4 (the six edits; the 15th parameter), §4.5/§4.7 (what the flip makes correct unchanged). R21 §4.5
(all three Parseval sites, with what the rejected layout cost). R22 §4.5 (`stored_planes`). R23 §3.3 (backend instance vs type).
R24 §4.6 (throw-as-deadlock, `MPI.Abort`, GC jitter). R25 §2 (decision 37 + four roadmap items), §4.9/§7 (`test/display.jl`),
§3.3 (residency argument-order). R26 §6 heading prose and §4.4 ("true in count, wrong in kind").

**`REVIEW-hpc.md`.** 1→§4.5 + §6. 2→§4.5 + §4.7. 3→§4.5 (adopted in full). 4→§4.4. 5→§2 table. 6→§2. 7→§2 cost model + §4.5
(parameterised transpose; the 2048³/4096³ rows withdrawn). 8a/8b→§4.6 (kept as DEFEATED, with the UB note). 8c→§4.6
(`MPI.Abort`). 8d→§4.4 + §7 (branch-id assert). 8e→§4.6. 9→§4.5 + §7. 10→§3.3. 11→§2.2, §4.3, §9 stage 6. 12→§4.5 (three r2c
prices) + §6 invariant 11. 13→recorded DEFEATED in §1 (value tests), §4.2 (builders), §4.4 (shape functions), §6 (zero mode,
shell corner), §4.8 (`_base_count`, `_locate`). 14→§7.

**`REVIEW-invariants.md`.** A1→§4.5 + §6. A2→§4.5 + §4.7. A3→§4.4 + §4.5. A4→§4.8 + §6 item 2. A5→§6 item 5. A6→§4.2 (both
directions) + §5 comment. A7→§4.4. A8→**kept as DEFEATED** in §1, §4.2, §4.4 and §4.5 (the `adapt_structure` proviso). A9→§6
invariant 14 + §7. A10→§4.8. A11→§4.4 + §7. A12→§2 + §3.3. A13→§4.5, §9 (stages A, 1, 2), §3.3. A14→§4.4 + §7. A15→§2 + §11(ii).
A16→§4.3 + §11(iii) + §11(i).

**`REVIEW-consumer.md`.** A1/A2→§4.6. A3→§4.6. A4→§9 + §4.9 (throw from stage 2). A5→§5. B1→§5. B2→§4.4 + §5. B3→§3.4 + §9 stage
1. B4→§4.6 + §5. B5→§4.6. C1/C2→§1 (promoted) + §8. C3→§8. C4→§4.9 + §8. C5→§8. D1→§9. D2→§9. D3→§4.5 + §9 stage 3. D4→§9.
E1/E2→§11 threshold. E3→§10 + §9 rationale. E4→§2 + §11(ii). E5→§11(ii). E6→§4.8 opening + §9.

**Not applied.** *HPC 7's "delete the 2048³/4096³ rows"* is applied as a withdrawal **with a condition**: the rows are gone, but
the repair kept is the parameterised transpose, because deleting the rows alone would leave slab's single-transpose limitation
unrecorded. *Consumer E6's "settle ruling 6 before stage 2"* is in §12 ruling 6, but the point layer is still staged after the
transform — the halo ruling gates the stage, not the ordering, and nothing in the point layer can be built before a decomposed
field exists. *Consumer D3's "add a second GPU at home"* is recorded in §10 as a purchase, not staged. *HPC 12's "keep r2c"* is
adopted without re-argument: the alternative doubles memory and forfeits the reality machinery, and no reviewer proposed c2c as
a repair.

**Residual risks the owner accepts even after all of the above.** Slab is a single-node decomposition, so multi-node is
capacity-only until the pencil generalisation is committed. 2.5–3.5× stays an ESTIMATE and the measurement that would confirm it
cannot be taken at the sizes that justify the work (§7). Bitwise rank-count invariance is gone and cannot be recovered. Feature
A's allocator cannot be chosen from the owner's hardware, and its performance model rests on launcher flags nobody here can
test. The production transport cannot be exercised at home without building a GPU-aware MPI. The point layer has no identity to
migrate, so stage 4 changes what a tracer *is*. And the consumer's realization changes: no stored pre-decomposition comparison
survives.
