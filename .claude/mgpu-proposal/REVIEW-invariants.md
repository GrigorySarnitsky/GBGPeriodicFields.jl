# Adversarial review — lens: the package's architecture and its fourteen invariants

Brief attacks 3, 5, 8, 9, plus the verification list (the 59-unchanged claim, the `Grid3D{T,P}` edit count,
the multipliers' parameters). Every `file:line` was read at `390fced5`, not taken from the inventories.

## Part I — does "59 operations unchanged" survive contact with the code?

**A1. The rfft half-spectrum weight is rank-dependent, on exactly the axis §4.5 splits — BREAKS.**
`1024³`, 4 ranks, §4.5 layout, `E = inner(û, û)`. `inner` (`Reductions.jl:884-900`) forms
`2·Σ_stored − correction` with the correction taken at `_folded_abs2_plane(data, folded, 1)` and, when the
**global** axis is even, at `size(data, folded)` — **local index 1 and the local last index**. Split that
axis and all four ranks subtract a plane, three of them an interior plane that is not self-conjugate; §4.6's
Allreduce then sums four wrong numbers. The error is `O(N²)` against `O(N³)` — relative `~10⁻³` at `1024³`,
which survives a smoke test. Two further instances, both unmentioned: `_parseval_weight` (`:945-951`) sets
`weight_host[1]` and `weight_host[folded_length]` at the **local** length, feeding `weighted_inner` and
decision 72's tuple form (`:1170,1174,1201`); and `_spectral_shell_bin_kernel!` (`:1245-1260`) takes
`nyquist_index = spatial_shape[folded]`, **inside the fused kernel**. §4.6 prescribes an Allreduce and a
global shell count; neither repairs this. *Repair*: plane ownership from the partition's global mode offset —
a rank owns the zero plane iff its range starts at global 1, the Nyquist plane iff it ends at `n÷2+1`. For
the kernel that is a signature change ⇒ a new `pass_audit.jl` row. Note the irony: §4.5 splits the folded
axis *because* it makes the reality condition local, and that is what makes all four ranks wrong here
instead of one.

**A2. `reality_projection!` silently destroys data under the §4.5 layout — BREAKS.** §4.7 discusses
`reality_residual` only. Decision 83's projector (`Fields.jl:2840-2871`) — the operation IT calls **7× per
step** — selects `planes = iseven(global n) ? (1, size(data, folded_axis)) : (1,)` (local last index) and
pairs through `mod(-(j-1), na)+1` with `na, nb` the **local** extents. Folded axis split: three of four ranks
average two unrelated interior modes and write the result back — not a wrong diagnostic, a corrupted field,
in place, every step. Non-folded split (§4.7's fallback): wrong partner within the rank. The residual's own
`stored_planes` (`:2701`) has the identical defect. §4.7's "free" is true of communication and false of
correctness: ownership and the pair extents are both derived from local shapes today. *Repair*: as A1;
then §4.7's "only the owning ranks do work" becomes true as written.

**A3. The folded spectral axis cannot be split exactly — BREAKS §4.4 against §4.5.** §4.4 makes it a
fail-closed rule that "the decomposition is exact on the split axes"; §4.5 splits the folded axis in
spectral representation. Its length is `N/2 + 1` (`Fields.jl:219`), **odd for every power-of-two `N`** — 513
at `1024³`, 1025 at `2048³`. No exact 4-way split exists at any production grid. Either §4.4's rule is wrong
as stated (it is: decision 45 constrains the *physical* grid spacing, not a spectral mode range) or §4.5 is
unbuildable. Uneven ranges then mean per-rank local shapes, which every collective payload must respect.
This is the rock Oceananigans steered around with c2c; §4.5 cites that as "a divergence to re-decide" and
connects it to nothing.

**A4. The transfer kernels' component stride is the *global* point count — BREAKS.** `interpolate!` and
`anterpolate!` pass `prod(grid.grid_size)` as `points_per_fibre` (`Interpolation.jl:1146,1265`); the kernels
compute `number_of_fibres = length(field_values) ÷ points_per_fibre` (`:974,1032`) and offset components by
it. Global grid + local storage (§4.4's ruling) gives `⌊(3N³/P)/N³⌋ = 0` for any `P > 3`: the fibre loop
never runs, `interpolate!` returns its destination untouched, `anterpolate!` writes nothing. Silent. Same in
the NUFFT kernels (`:1946,1978`); `DirectDFT`'s `1/prod(grid.grid_size)` (`:1500`) is a normalization that
must stay global while the stride beside it must become local. §4.8 enumerates `_wrap_step` and `_locate`
and stops — this third site is *created* by §4.4's own ruling. *Repair*: kernels that index storage take the
local shape and its product; only normalizations take the grid.

**A5. `radial_correlation` bins the local index against the global extent — BREAKS.**
`_physical_shell_bin_kernel!` (`Reductions.jl:1395-1401`) derives the minimum-image separation from
`@index(Global, NTuple)` — **local** — while `points_1..3` are the **global** sizes: every rank treats its
own origin as `r = 0`. §4.6 states this site "uses the global index", which reads as reassurance; the code
uses the worst combination of the two. `count_bins` must also be Allreduced (§4.6 counts two O(N) vectors;
there are three).

**A6. §4.2 and §4.6 contradict each other over the multipliers — BREAKS.** §4.2 says slice the six vectors
and keep global "`2π/L`, the `iseven(n)` test, and the six length validations (`Fields.jl:1840-1845`)". Those
validations compare against `field_spectral_shape(grid, layout, Val(0))` (`:1838`), which §4.4 redefines to
return the **local** shape — so they must become local, or sliced vectors throw `DimensionMismatch` and
§4.2's mechanism is unbuildable. The design states the one requirement that blocks itself. In the other
direction, `_radial_spectrum_bin` derives the shell count from `maximum(squared_wavenumber_1..3)`
(`Reductions.jl:1267-1269`); sliced multipliers make that a **local** corner, so rank 0 allocates fewer
shells than rank 3 — precisely the ill-formed Allreduce §4.6 warns about, caused by §4.2's fix. The global
per-axis maxima are a fourth thing that must stay global; the design lists three. Also unstated: the
convenience constructor builds from `grid.grid_size[d]` (`:1889-1891`), so §5's
`mult = FieldSpectralMultipliers(û)  # local wavenumber slices` does not do what its comment says without an
edit the design never lists.

**A7. `Grid3D` stops being a bitstype and `_same_grid` becomes pointer identity — BREAKS.**
`_same_grid(a,b) = field_grid(a) == field_grid(b)` (`Fields.jl:1139`); `Grid3D` defines no `==`, so this is
`===`. Today `Grid3D{Float64}` is `isbits`, so `===` compares values and two independently built identical
grids are equal. A partition holding an `MPI.Comm` (mutable in MPI.jl) makes `Grid3D` non-`isbits`, and
`===` then compares that field by **pointer**. Measured: `isbits G{Float64} = true`, separate-but-equal
`== true`; with a comm-carrying `P`, `isbits = false`, same comm object `== true`, equal-but-distinct comm
objects `== false`. So with `COMM_WORLD` everywhere it happens to work, and the moment §4.5's own
recommendation is followed (sub-communicators per direction, Oceananigans' pattern, quoted approvingly) two
grids built from separate `Comm_split` results compare unequal and **every** two-field operation throws
"field grids must be equal" — via `_check_same_domain`, `_check_adapt_target`, `_check_matching_context` and
the broadcast path. *Repair, cheap, belongs in stage 2*: the partition stores the raw `MPI_Comm` handle plus
rank and size (all `isbits`), never the wrapper. `Grid3D` then stays `isbits`, `==` stays value-based, and
the grids carried inside `SeparableKernel`/`RadialKernel` keep the "pure bitstypes ride along unchanged"
property their `adapt_structure` comment asserts (`Convolution.jl:1995`).

**A8. What I could not break — DEFEATED**, and it is the design's strongest section. Verified per site, all
genuinely element-`n`-to-element-`n`: `_fiberwise_pass!` (`FiberSections.jl:815-830`, `ndrange =
length(targets[1])`, no extent anywhere, both arms); the broadcast route (`copyto!`, `Fields.jl:2113` —
checks compatibility, unwraps to storage, assigns over `axes(field_data(destination))`); `map!`/`map`
(`FieldAlgebra.jl:1756,1848-1880`, same executor, output via `similar_field`); `combine!`, the M2/M3 surface
and the kernel-composed arities (coefficientwise); the 16 differential operators — their zero-mode and
Nyquist cases are **value** tests, `ifelse(iszero(squared), …)` at `DifferentialOperators.jl:215,274,595,645`,
not index tests, which is the luckiest single fact in the proposal and it is real; every kernel builder —
`spectral_cutoff`/`spectral_band`/`radial_kernel`/`assignment_window`/`translation_kernel(!)` build from the
per-axis multiplier arrays only (`Convolution.jl:1856-1870,1933-1951`), so decision 28's Nyquist split rides
on the sliced arrays for free (even part from `√squared`, odd from the zeroed derivative wavenumber,
per entry) and `spectral_cutoff`'s idempotence is per-mode and survives; `adapt`/`adapt!` —
`adapt_structure(to, plans)` (`:2608`) rebuilds from `field_*_shape(grid,…)`, so local witnesses and a
grid-carried communicator, §4.5's claim holds *provided* the rebuilt plan dispatches to the distributed
constructor through the grid's `P`, or `adapt(Array, plans)` silently turns one distributed transform into
four wrong local ones; and `similar_field` / the six family constructors / `_wrap_field` all route through
`field_physical_shape`/`field_spectral_shape` (`:1030-1063`, `:893-925`), so §4.4's highest-leverage claim is
true. `Grid3D{T,P}` really is ~6 edits: the six field types, the plans and both stored-kernel classes take
`G<:Grid3D{T}` **bounds** with `grid::G` (`Fields.jl:452,520,597,665,756,845,1337`;
`Convolution.jl:334,496`) and stay concrete for free; `FieldSpectralMultipliers` (`:1792`) is genuinely the
only concrete `Grid3D{T}` struct field. But the count hides the risk and the file says so itself
(`:1814-1818`): fixing that site means a 15th type parameter, which moves `Canonical` and breaks **three
positional matchers at once** — `_is_canonical` (`:2577`), `adapt_structure` (`:2596`), `Convolution`'s
static collapse (`:416`) — the exact failure that comment records from the decision-70 change. "~6 edits" is
right in count and wrong in kind for one of the six.

## Part II — attack 3: invariants amended wrongly or silently

**A9. Invariant 14 is mis-assigned — BREAKS.** §6 rules that "a distributed field and a local field are
*different families* and refuse, with `redistribute!` as the named conversion". By the package's own
predicate (`_storage_family`, `Fields.jl:1153-1156`) a family is the array type's wrapper name recursed
through `parent`: two `CuArray`-backed fields are the same family whatever their partition, and what differs
is `_same_grid`. So the error would read "must live in the same storage family; got CuArray and CuArray";
`redistribute!` gets filed beside `adapt`/`adapt!` when it is a **base** conversion; and its gate goes to
`test/adapt.jl` instead of `test/peer_rejections.jl`. *Repair*: state it as a grid refusal — which, given
A7's repair, is free and already enforced, the field types carrying `G` as a type parameter.

**A10. Invariant 9: relaxing decision 59 costs more than §4.8 admits — UNPROVEN.** Decision 59's docstring
(`FiberSections.jl:105-126`) is explicit that ownership stands in for a different property: *one section's
element `n` is another's element `n`*. §4.8's "amended for halos only… fields without halos keep the rule
verbatim" is wrong twice. (i) The property is not per-field: `_fiberwise_pass!` launches
`ndrange = length(targets[1])` and reads `arrays[i][n]` under `@inbounds`, so a halo field and a plain field
on the same grid give out-of-bounds reads with no error — `_check_same_domain` needs a **halo-width
equality** clause and a halo field must refuse a non-halo peer. (ii) Decision 59 also makes three `===`
shortcuts *exhaustive*: the scratch arity's anti-aliasing test (`Fields.jl:1541-1544`, invariant 11),
`adapt!` (`:2554`), and `reality_projection!`'s `destination !== source` (`:2846`). A `HaloArray` preserves
that only if it can never be constructed as a window onto another section's buffer — an enforced
constructor property, not a convention.

**A11. Invariant 1 is amended with no row at all.** §6 rules it "unchanged — the distributed path adds no
operation a serial user can call", while §4.4 puts MPI and the partition type in a weak-dependency
extension. The derived method-parity baseline excludes extension methods by construction:
*"Extension methods (the HDF5 weak dependency) live in their own module and are excluded by the
`m.module === mod` filter"* (`test/method_parity.jl:74`). The largest addition in the package's life is the
one addition no ledger counts — see A14.

**A12. Two more silent amendments.** *Decision 37 is demoted, not reconciled*: §2 leaves the CPU path
"development, and the portable reference", restoring the sentence decision 37 was written to retract, and
dissolving with it the three tiebreaks it reopened (x-inner loop order at `1536³`, the pass-audit gaps
priced out of cache, NUMA first-touch) plus the recorded gap that no CPU column above `256³` exists. §12's
ruling 1 lists the documents that change and not the four roadmap items that change with them. *Residency
becomes argument-order-dependent*: §3.3 says residency is per field and free, but the allocating broadcast
takes its output from `_first_field` (`Fields.jl:2128-2145`) and `map` from `source1`, so
`u_device .+ v_unified` lands in HBM and `v_unified .+ u_device` in LPDDR. Under invariant 1 that is new
semantics in the method set and needs a stated rule.

## Part III — attack 5: the staging against the hardware that exists

**A13. Stage 3's home lane does not exercise the path stage 6 measures — BREAKS.** §9 marks stage 3
"correctness yes (4 ranks, 1 GPU, and CPU)". The hand-rolled transpose's defining property (§4.5) is
`MPI.Alltoall(v)!` **directly on GPU buffers**; that needs a CUDA-aware MPI, MPI.jl's default JLL is not
one, and `MPI.has_cuda()` cannot be used to find out (§7 says so). So the home lane either builds a system
CUDA-aware MPI on the office box or stages through the host — a *different transport* from production, in
which case stage 3 "done" certifies code stage 6 replaces. *Repair*: make the transport a dispatched policy
(device-direct / host-staged), exercise both at home, and say which the DoD requires. Three smaller ones.
**Stage 2 is inert only while `NoPartition` is `isbits`** (it is, zero fields) — A7's `==` change is the
non-inert half and it lands in stage 3, the stage already called "the risk"; move the isbits constraint into
stage 2's DoD, where it is provable at home. **Stage 1 breaks a fleet health check**: a unified-memory axis
can only run in `test/gpu/cuda`, so the two GPU suites stop reporting the same count, and `CLAUDE.md` treats
a ROCm/CUDA divergence as "a finding, not a rounding difference" — after stage 1 it is permanent and
expected, and must be recorded as such. **§3.3's API needs one thing it has not got**:
`KA.allocate(backend, T, dims; unified)` and `supports_unified` do exist at the package's own compat floor
(verified in the installed KA 0.9.41, `KernelAbstractions.jl:546,594`), but `allocate` takes a `Backend`
**instance** while `_allocated_field_storage` has a *type* (`family::Type{<:AbstractArray}`) and
`get_backend` is defined on arrays, not array types. The constructor must build a zero-element probe, or
keep the fully-parameterised family and never touch KA. Two changes do not suffice; two and a half do.

## Part IV — attack 8: test integrity

**A14. The ledgers cannot see the distributed surface — BREAKS.** §7's "refreeze in the same commit as any
new verb" is a **no-op** for verbs in an extension, and nothing else counts them either:
`method_parity.jl`'s derived baseline filters `m.module === mod` (`:74`); `oracle_registry.jl` and the
per-method ledger take their domain from `public_surface.jl`, i.e. method ownership;
`test/exhaustive/invocations.jl` derives the operation domain from the method table and cannot build an MPI
context; `absence_gate.jl` and `peer_rejections.jl` have derived denominators with no partitioned-peer
fixture; and `display.jl` is a **derived completeness gate over every concrete package struct**, so
`SlabPartition`, `NoPartition`, the exchange object and any `HaloArray` each need a `show` or a cited
exemption or `Pkg.test()` fails — the cheapest DoD item in the document, and it is in no stage. *Repair*:
the MPI extension gets its own `MODULE_BASELINE` entry, its own `public_surface` contribution and its own
oracle rows, all counted inside the MPI lane. Two things a green 4-rank suite would still not prove, neither
named: that the collective **sequence** is identical on all ranks for any input (§4.6's deadlock story is
documentation plus an opt-in counter — that counter should be the default in the test lane), and invariance
in the **rank count** beyond 1-vs-4, which is where an ownership-by-offset bug (A1, A2) hides — 4 ranks over
513 modes is one uneven configuration, not a family. §7's oracle answer is right and is the design's
second-best passage; strengthen it by noting that A1–A5 are each caught by an oracle the suite **already
has** (Parseval, `sum(spectrum) == inner`, `C(0) == inner`, `reality_residual == 0` after
`reality_projection!`, transfer adjointness), so the distributed lane is "these existing oracles, under
decomposition", not new tests.

## Part V — attack 9: is §11 compared fairly?

**A15. The row that justifies the programme is the row the spill policy forbids — BREAKS.** §2's ceiling
table and §2's bandwidth table are never joined. At `1650³` the live set is `25 × 1650³ × 8 B ≈ 837 GiB`
against `384 GiB` of HBM: **55% of it spilled**. §2's own model says a step spilling half its traffic runs
~5× slower, and §3.4 rules that only *cold* fields should be spilled — but decision 37's "25 fields" is a
solver's **live set**, touched every step. The headline row is the one configuration where the design's own
policy is violated and its own penalty applies; the table needs a speed column and §11 needs the marginal
value of A-on-top-of-B stated as "2.2× the cells at ~5× the per-step cost". "At GPU speed" is separately an
overclaim: 4 × 450 GB/s of LPDDR ≈ 1.8 TB/s against a thin node's ~0.6–0.8 TB/s achievable DDR5 — ~2–3×, for
four GH200 against two EPYC, not an order of magnitude.

**A16. The strongest competitor is dismissed under a different question — BREAKS.** §4.3 dismisses ensemble
parallelism as "already works today, costs nothing… simply not this question"; §11 then names
throughput-across-runs as the criterion that decides against feature B. Same option, judged twice, once out
of scope and once as the deciding criterion, never joined. On a scheduler allocating whole 4-GPU nodes, four
independent `1024³` runs on one node is 4× the throughput of one 4-GPU `1270³` run at **zero** engineering
cost; §11 should state that as the baseline feature B must beat. Also missing from §11: **stage 0 only**.
Its two defects are live today, A1/A2/A4/A5 add four more of the same class, all are worth fixing whatever
is decided, and — unlike stage 1 — every one is verifiable on the hardware the owner has.

## The five most consequential problems, ranked

1. **The half-spectrum is rank-dependent** (A1+A2): `inner`, `_parseval_weight`, the shell kernel,
   `reality_residual` and `reality_projection!` all take plane ownership from a **local** index. §4.5's
   layout makes all four ranks wrong instead of one, and §4.7 calls it free. The projector corrupts the
   field in place, 7× per step in the consumer.
2. **The folded spectral axis cannot be split exactly** (A3): `N/2+1` is odd at every power-of-two grid, so
   §4.4's exactness rule and §4.5's layout cannot both hold. It decides r2c-vs-c2c across the transpose and
   is unaddressed.
3. **The ledgers cannot see the distributed surface** (A14+A11): an extension is excluded from the derived
   method-parity baseline by construction, and with it from the oracle registry, the method ledger and the
   survey. Invariant 1 loses enforcement for the largest addition the package has made.
4. **`Grid3D` loses `isbits`, `_same_grid` becomes pointer identity** (A7): every two-field operation fails
   the moment sub-communicators are used, which §4.5 itself recommends. Cheap to prevent, invisible if not,
   and it lands in stage 3 rather than stage 2.
5. **The `1650³` headline violates the spill policy it states** (A15+A16): 55% of a hot live set spilled at
   the design's own ~5×, compared to a CPU node at "GPU speed", with the zero-cost ensemble alternative
   dismissed under a different question.

## Residual risks the owner must accept even if all the above is repaired

- **Determinism.** §4.6 is right that rank-count invariance is unattainable, but today's guarantee is
  *bitwise* and machine-checked and the replacement is a tolerance nobody has sized. The exhaustive survey
  already exits 2 over a 4e-7 shell tie-break; a rank-dependent reduction order is a larger perturbation.
- **Two of three things are verifiable at home; the transport and the spill model are not.** Decomposed
  algebra, operators and reductions can be shown on 4 CPU ranks. The production transport cannot be shown
  without a CUDA-aware MPI, and the spill performance model not at all (ATS vs software HMM). Both are the
  `PERFORMANCE.md` §7 gap-8 class the package already carries for `aarch64` — but now on the critical path.
- **The consumer's realization changes.** IT builds whole fields from one host-side RNG stream
  (`State.jl:156,:257`); under decomposition a seed no longer reproduces a flow. Not repairable without a
  per-rank deterministic reseeding scheme, and it invalidates every stored pre-decomposition comparison.
- **The point layer has no identity to migrate** (§4.8 concedes it). Accepting stage 5 means accepting
  either a new point identity or trajectories that lose theirs — a change to what a tracer *is*, forced by
  an implementation constraint.
