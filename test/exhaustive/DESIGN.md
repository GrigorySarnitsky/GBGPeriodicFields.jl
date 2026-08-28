# The exhaustive check — design

## The claim this must satisfy

> **No test a person would write is outside the product — except a benchmark.**

That is only verifiable if every axis is *derived from the code*, never listed by hand. Every axis
written from memory in this project has been missing values: the coverage-axes list had no storage
kind (decision 59), the aliasing axis had two of six values (decision 56), the context detector could
not see union-typed slots and then could not see the `UnionAll` wrapping them (decision 58). The
design below therefore contains no list that a person maintains, only derivations and
exemptions-with-reasons.

## The cell

```
CELL = operation × argument-assignment × configuration × CHECK-TYPE × sequence-length × seed
```

The fourth axis is the one usually left out. A product over arguments answers *what did we call it
with*; it says nothing about *what kind of question we asked*. "Is the answer correct", "does it
allocate", "is it the adjoint", "does it round-trip" are different questions about the same call, and
a person writes all of them.

---

## Axis 1 — operation

Derived by `test/public_surface.jl`: every function a package module owns methods of, extensions of
external generics included (`map`, `cov`, `inv`, the field arithmetic).

**And the lanes take their domain from it**, through the invocation engine in `invocations.jl`: for
each operation the package-owned methods are read from the method table, each parameter slot is filled
from a canonical pool covering every type the signatures mention, and `applicable` settles which
combinations are real calls. Adding an operation to the package adds it to the sweep. An operation the
engine cannot call is reported, not skipped.

Three things the engine had to get right, each of which silently emptied the domain when it did not:

- **Slot matching compares type CONSTRUCTORS, not `isa`.** A parameter is usually a `UnionAll` with
  free type variables — `TensorFieldPhysical{2, T, A, G} where {A, G}` — and `object isa that` is false
  for every object, so every slot came back empty and `det`, `tr`, `sym`, `to_physical` and fifty more
  were reported unbuildable. `applicable` then settles each candidate exactly, so the looseness costs
  work and never correctness.
- **Method ownership includes the extension modules.** The persistence pair lives in
  `GBGPeriodicFieldsHDF5Ext`, which is not a package module, so filtering on `PACKAGE_MODULES` alone
  hid all four HDF5 operations behind "no buildable call".
- **Zero-arity and variadic methods are still methods.** Skipping empty parameter lists lost
  `threading_cutoff`; skipping a variadic tail lost the whole multi-input `map!`/`map` surface, which
  is expanded to its one- and two-argument forms instead.

## Axis 2 — argument assignment

For each operation, the product over its slots. Each slot's pool is keyed by its **declared parameter
type** and is itself derived:

| slot type | pool | derivation mechanism |
|---|---|---|
| kernel | the concrete kernel classes | **literal, audited**: building a kernel needs constructor arguments, so the pool is written out and `pool_class_gaps` checks it against `subtypes(AbstractSpectralKernel)` |
| transfer scheme | the concrete schemes | **literal, audited** against `subtypes(AbstractTransferScheme)`, descending through `AbstractSplineScheme` since `subtypes` is not recursive |
| section | order × representation × storage relation | the constructors, crossed |
| numeric parameter | the boundaries themselves | the comparisons in the **validation code**, not invented values |
| context object | one `foreign-<q>` per compared quantity | `comparable_quantities()` in `pools.jl` — the equality tests inside every `_check_*` predicate, read from lowered IR |
| point set — count | `M = 0`, `1`, typical | the boundaries of a count |
| point set — geometry | uniform / on-node / clustered / outside the box | **declared-sampled**: no predicate compares position, so nothing derives it |

Since decision 59 a section owns its storage, so the storage relation has three values and is
enumerated completely rather than sampled.

### The rule that table exists to enforce

The context row used to read `matching / foreign-grid / foreign-layout / foreign-eltype`, under a
column headed *derived from*. It named no mechanism — it restated its own contents — and the
adversarial pass **read the label and attacked elsewhere**, so the pool kept three of the seventeen
values it should have had. One of the missing values was tensor order, which is exactly why decision
52's NUFFT defect had to be found by mutating the source instead of by sweeping a product.

> **A cell claiming a derivation must name a MECHANISM. A cell whose source restates its own contents
> is a list, and must be labelled one.**

This generalizes past this table. The same defect has now appeared four times in this project, each
time as *labelled derived, but not*: the oracle registry derived from `names()`, which could not see an
extended generic (15 operations missing); the pass audit deriving symbols with `first(split(name))`,
which produced phantoms; `MODULE_BASELINE` counting by namespace, blind to a qualified `Base.inv`; and
this pool. So the adversarial protocol carries a standing item:

> **The adversary must verify the design's claims about itself, not accept them.** For every place the
> design says "derived", ask *derived from what, by what call* — and check that the answer is not the
> value list read backwards.

### And the derivation must not consult the artifact under test

Deriving *applicability* from behaviour is the same trap wearing different clothes. The mismatch lane
first decided whether a slot was generic over tensor order by **asking the package** — calling the slot
at each order and inferring genericity when several succeeded. Re-injecting the spectral `inner` defect
showed what that costs: with the bug present `inner(scalar, vector)` succeeds, the probe concludes the
slot is generic, and the lane **skips the one cell that would have exposed it**. The defect made itself
inapplicable, and the lane reported all-clear while sweeping two fewer cells.

> **A contract is declared; a probe is an assertion against it — never a filter that decides what to
> check.**

So the fiber contract is stated per slot and the probe now *checks* it: a slot declared to take one
tensor order that accepts three is itself a finding. That inversion is what turned the lane from silent
to catching the defect twice over.

## Axis 3 — configuration

Element type · grid shape, parity and anisotropy · layout fold · origin · thread count · backend ·
Nyquist content. **Each axis declares whether it is crossed or sampled**, and a sampled axis is
reported as a coverage limitation, because an interaction defect needs its values crossed — a defect
may require a permuted fold *and* an odd axis *and* `Float32` at once.

## Axis 4 — check type, derived by classifying what people already wrote

The existing suite holds **1,424 assertions**. Those are what people write, so the axis is obtained by
classifying them, and **an assertion that cannot be classified is a missing axis value** — that is the
mechanical form of the claim at the top.

The classification is implemented in `classify_checks.jl` and its output — not a list written here —
is the axis. Running it over the 1,424 existing assertions yields:

`correct` (independent reference) · `identity` (algebraic law) · `adjoint` · `representation-agreement` ·
`invariance` (thread count, fold, storage relation) · `absence` (throws) · `static-absence`
(`hasmethod`) · `domain-rejection` · `allocation` · `element-traffic` · `metadata` · `schema-presence` ·
`result-type` · `inequality` (sign, definiteness, bounds) · `structural` (a property of the result:
realness, finiteness, zero pattern) · `round-trip` · `determinism` · `type-stability` · `completeness` ·
`has-example` (**not implemented** — see below)

**Five of those were missing from the list originally written here** — `result-type`, `inequality`,
`static-absence`, `schema-presence` and `structural` — and were added only because assertions fell
through the classifier. That is the derivation doing its job on its first run, and it is the reason the
axis may not be maintained by hand.

One further class is named so it can be **excluded** rather than counted: a **fixture precondition**
(`@test perturbed != canonical`) asserts the test's own setup is valid and makes no claim about the
package.

## Axis 5 — sequence length

`{1, 2}` crossed, plus an `n`-step lane over the in-place surface only.

Two steps is not an embellishment here. **Invariant 11 is a sequence property** — the inverse real
transform destroys its input, which is invisible to any single call and only appears when the source
is used afterwards. So are round-trip identity, idempotence (``\mathbb P^2 = \mathbb P``), and reusing
a plan whose construction overwrites its arrays.

`n ≈ 50`–`100` earns its own lane because **invariant 13 exists because of an n-step defect**: a
per-call device temporary escapes Julia's GC, which triggers on host pressure and is blind to the
device buffer, so a single call allocates fine and a hot loop wedges the card (decisions 24–26).

## Axis 6 — seed

**A complete Cartesian product over structure still samples the values.** The axes enumerate shapes,
types, relations and configurations; they cannot enumerate ``\mathbb R``. Every cell still puts one
particular array in the slot.

That gap has already produced a defect here: `PERFORMANCE.md` finding (m), where a fixed exponent put
a `Float32` result in the subnormal band and cost ~16× per element. Nothing structural revealed it.

So the seed is an axis with `k = 2`–`3`, and **the seed is printed on every failure**, so a cell stays
reproducible.

---

## Applicability, and the guard on it

Not every check applies to every operation: `adjoint` needs a known adjoint, `identity` needs a law.
So every `(operation × check-type)` pair is **implemented, or exempted with a reason** — the ledger
pattern, applied to the check-type axis. It is implemented in `ledger.jl`.

**The reason is a predicate, not a sentence.** "This does not apply here" reads as a decision and is
usually an omission, so each check type carries a rule over properties read out of the operation
itself, and the reason printed for an inapplicable cell is the rule that said so:

| property | read from |
|---|---|
| in-place | the name ends in `!` |
| can reject an argument | its IR reaches a `_check_*` predicate |
| nondeterministic | its IR reaches `Atomix` |
| threaded | its IR reaches the `_assign!` primitive |
| valid in both representations | it has methods on both field supertypes |
| result is ordered / is a section | inferred return types over its own methods |

The IR walk runs to **depth 4** because a KernelAbstractions launch indirects four times before the
kernel body (`anterpolate!` → `_anterpolate_kernel!` → `__anterpolate_kernel!` →
`cpu__anterpolate_kernel!` → `Atomix`). At depth 3 the scatter kernel's atomic is invisible and the one
family the determinism check exists for is silently exempted.

**Invariant 1 is read only in the direction it holds.** An operation with methods in both
representations is linear, so the method set states linearity. The converse is false — `convolve` is
linear yet spectral-only — so the checks needing genuine linearity take their domain from the declared
relation table rather than from inverting an implication that does not invert.

An exemption reason is itself checkable, and must be checked, or it becomes the place misses hide:

- an operation valid in **both representations** may not be exempt from `representation-agreement`
- an operation with an **in-place form** may not be exempt from `allocation`
- an operation that **allocates its result** may not be exempt from `metadata`
- an operation reaching an **atomic** may not be exempt from `determinism`

### Coverage is attributed through the suite's own assertion helpers

An assertion is not always written where the operation is named. A well-factored suite wraps its
assertions — `@alloc_below 1000 add!(d, a, b)`, `audit(op!, name, Traffic(...))` — and then the `@test`
is in the helper's body while the operation appears only at the call site. Attributing coverage to
lines containing `@test` therefore misses whole files, and misses them **worse the better factored they
are**: it reported `test/allocations.jl`, the suite's most systematic audit, as asserting nothing.

So the helpers are derived too — the test sources are parsed, and any macro or function whose body
contains a `@test…` macrocall is one. (`@test\b` also fails to match `@test_call`, `_` being a word
character, which had made every JET assertion invisible.)

Attribution is **by mention** and can over-credit, which is stated in the report rather than corrected:
the alternative is attributing by hand, which is the listing this design exists to avoid.

## Cross-operation identities

`\nabla\cdot(\nabla\times u) = 0`, `\operatorname{sym} + \operatorname{skew} = \mathrm{id}`,
`gradient` then `divergence` against `laplacian`. These constrain *two* operations, so they are not in
a per-operation product at all. They live in a declared identity table, and **each identity names the
operations it constrains**, so an operation constrained by none is visible rather than assumed fine.

## The oracle

Every `correct` cell compares against a reference in `references.jl`, computed from raw arrays by the
plainest expression of the definition, sharing no code with the implementation. Wavenumbers are
rebuilt from the grid rather than taken from `FieldSpectralMultipliers`, or the spectral references
would inherit the convention they are meant to check.

A reference is **cross-validated before use**. This is not optional: a reference that shares a
misconception with the implementation makes the cell pass while both are wrong, which is the
self-referential oracle decision 52 named and which the first version of this sweep rebuilt at 17,000
cases by comparing an aliased call against an unaliased one.

A correctness oracle also **subsumes the aliasing one**: if a call whose destination aliases an input
produces the right answer, aliasing did not break it.

## Reporting

Unchanged from the current runner, and load-bearing:

- failures print with their citation **beside** them, never instead of them
- `NO CITATION` marks a new finding
- `NOT APPLICABLE` marks a combination the model does not admit; `NOT REACHED` marks a hole in the lane
- a conditional cell that could not run (no device) reports **NOT RUN**, never silence

---

## What the suite reaches, and what it does not — measured, not estimated

Every number here is measured by the suite itself, so it cannot drift into optimism.

| axis | status |
|---|---|
| public operations exercised | **112 of 112** — the invocation engine builds calls from the method table |
| operations with an independent VALUE oracle | **112 of 112**, written from each operation's documented definition |
| universal check types | preservation, structural, metadata, determinism, type-stability, over every invocation |
| declared relations | **all 25 executed** — adjointness, algebraic identity, round-tripping |
| representation · invariance · allocation · ordering · rejection | crossed per configuration |
| sequences | plan reuse, repeated application, round-trip cycling, n-step allocation |
| backend | CPU and CUDA, when run from a vendor environment — **the universal-checks lane only**. `device` is not a `Config` field; the value, relation, property, sequence, aliasing, mismatch and reference lanes build host fixtures and run CPU-only even from a GPU environment. |
| element type · grid · fold · threads · origin · seed | crossed, **96 configurations** (all three folds, two seeds) |
| argument combinations per method | **SAMPLED** at a cap of 400; the number dropped is printed |
| ledger cells applicable but unasserted | **321** — per-operation questions, not sweepable properties |

Wall clock: **75 minutes**, measured with `-t4` on an idle host. (It was 43 before the thread axis was made live, the third layout fold added, and the seed axis trimmed — a figure that had drifted precisely because it was written rather than re-measured, under a heading promising the opposite.)

The operation row was **39 of 112 (35%) exercised by nothing** one commit ago, because three lanes
carried hand-written entry lists under an axis that claims to be derived — this document's own rule
broken by its own lanes, shipped in the same change that recorded the rule. The invocation engine
replaced the lists with the method table, which is what closed it.

### How to cross the backend axis

The vendor packages are not dependencies of the package or of `test/`, so the device pool exists only
where one is loaded:

```
julia --project=test          test/exhaustive/runtests.jl     # CPU, plus HDF5 persistence
julia --project=test/gpu/cuda test/exhaustive/runtests.jl     # CPU and CUDA
julia --project=test/gpu/rocm test/exhaustive/runtests.jl     # CPU and ROCm
```

Determinism is asserted **bitwise on CPU** and to a tolerance on a device: a device reduction is not
reproducible across launches — measured at 1 ulp for the ``R = 2`` `inner`, which is the parallel
summation order rather than a defect — and the package's own position is that tolerances hold for
cross-backend comparisons.

### An open finding the shell-by-shell comparison exposed

`radial_spectrum` was compared only through `sum(...)` until the adversarial pass; the sum is invariant
to how modes are distributed among bins, so the binning — the operation's entire purpose — was checked
by nothing. Comparing shell by shell immediately disagreed on **`Float32` with the anisotropic
`(8, 6, 5)` grid**: the totals match to 7 digits and the shell counts agree, but energy sits in a
different adjacent shell for a handful of modes. The cause is a bin-boundary tie — `round(Int, |k|/Δk)`
with `|k|` computed in a different association order by the package and by the reference, so a mode
landing within a `Float32` epsilon of a boundary falls either side. It is a genuine numerical
sensitivity of the binning rather than a wrong formula, and it is reported rather than tuned away.

### What a relational identity can and cannot see

The adjointness and idempotence relations are **algebraically true for any real symbol**. `⟨∇·u, φ⟩ =
−⟨u, ∇φ⟩` holds for any real `k`; `ℙ² = ℙ` holds for any real `a`; `Δ⁻¹Δ = id` is `y = cx, z = y/c` for
any nonzero `c`; `M⟨Wf,q⟩ = N⟨f,Wᵀq⟩` holds for any stencil, correct or not, because gather and scatter
share one weight builder. So the relations lane cannot catch a wrong wavenumber, a wrong cutoff radius
or a wrong spline coefficient — only an INCONSISTENCY between two operations that should agree, which
is what a relation is for and is exactly the shape of the decision-42 defect.

The symbols themselves are covered elsewhere and independently: `references.jl` rebuilds the
wavenumbers from the grid and the value lane compares every operator against them. The division of
labour is deliberate; what was wrong was only that the ledger presented `:adjoint`/`:identity` coverage
without it, and that nothing proved the relations lane could fire at all. `selfcheck.jl` now drives
every lane's comparison step against a triple that is false by construction — the discipline it
enforced for the five universal checks, extended to the other lanes.

Three limitations are **structural** rather than unfinished, and no amount of work removes them:

- **Applicability is not meaning.** The engine builds a call because `applicable` says one exists, which
  is not the same as the call meaning what a reader assumes. `norm(x, p)` is LinearAlgebra's p-norm, so
  a two-input `map!(norm, dest, A, s)` silently reads the second FIELD as the exponent, giving `Inf`
  wherever ``p < 1``. The lane reported that as a package defect and it was the engine's own doing. The
  pool now holds wrapped closures of fixed arity so a wrong-arity call throws instead of being misread,
  but the general hazard remains: a derived call set contains calls nobody meant.

- **The check-type axis is derived from assertions people have written**, so it cannot contain a class
  nobody in this project has ever written. The product is complete relative to the suite's own
  imagination, which is weaker than complete.
- **A missing validation leaves nothing to derive from.** The domain-rejection pool comes from the
  boundaries in the validation code, so an argument nobody validates — the NUFFT `width` and `beta` —
  contributes no cell. The product verifies that contracts hold; it cannot invent a contract that ought
  to exist. Where a parameter has a *stated* contract but no validation, the `correct` oracle still
  reaches it; where it has neither, nothing does.

## Scale, and the rule that keeps the claim true

The naive product is not runnable: ~113 operations × up to 125 assignments × 16 configurations × 15
check types × 2 sequence lengths × 2 seeds is on the order of ``10^7`` cells, hours even at a
millisecond each.

Applicability prunes it hard — most check types do not apply to most operations, and most operations
have two or three slots rather than three. But the pruning rule matters more than the number:

> **Prune by declared inapplicability, never by sampling.**

A cell removed because the combination does not exist keeps the completeness claim true. A cell
removed because there were too many destroys it, and destroys it silently. Where an axis must be
sampled, it is declared sampled and reported as a limitation.

## FINISHING THE PRODUCT — the per-method coverage ledger (BUILT 2026-08-28, uncovered = 0)

**This resumption point is CLOSED.** The design below is what was agreed 2026-08-02 and is kept as the
record; `method_ledger.jl` and `method_reasons.jl` implement it, and the count it was built to drive
reached zero.

**Outcome.** 575 cells over 114 operations: **572 covered by an assertion, 3 closed by a recorded
reason, 0 uncovered.** The value lane went from 169 rows to 516 comparisons across eight generated
dispatch sweeps, and every one of them agrees with an independent reference.

**Coverage is derived, not declared.** The lane runs under `--code-coverage` twice — once whole, once
with the assertion tuples empty but every fixture still built — and a method counts as covered only if
an assertion added hits to its span. Rows carry no annotation saying which method they exercise,
because a hand-maintained mapping is the bookkeeping defect the ledger replaces.

**Three defects in the LEDGER ITSELF, each found by perturbation or by chasing one cell, none visible
by reading it.** A reason keyed by definition site silently closed four codegen methods at once — the
"covered by a sibling builder" escape this design warns about — so a reason now DECLARES how many
methods it closes and a miscounted one is refused. The fixture subtraction was boolean per span, so
one fixture touching a shared span stripped credit from every method at that site. And the line index
was re-enumerated from `names(mod; all = true)`, which does not report an operator a module imports
from `Base`, so every `+` method read uncovered with four recorded hits sitting in the coverage file;
that one alone was suppressing 107 cells.

**The five probes are in `selfcheck_method_ledger()` and take their target from a perturbed COPY of
the lane**, so probes 4 and 5 keep working now that the real count is zero. A check that skips on
success is the failure this lane exists to prevent.

**What the sweeps confirmed rather than found.** No dispatch defect surfaced: every one of the 347 new
comparisons matched. Two absences the sweep asked for are design — section-times-section and a
scalar-by-scalar product in spectral representation are nonlinear, so invariant 1 puts them in physical
representation only. One asymmetry IS a finding and is reported rather than normalised: the point layer
accepts `multiply!(vector_destination, scalar, scalar)` and broadcasts over the fiber, while the field
layer refuses the identical shape.

---

*The original design, kept as written on 2026-08-02:*

### The diagnosis

The suite was conceived as a Cartesian product over axes, and the **universal-checks lane genuinely
implements it**: operation × argument combination × tensor order × representation × backend ×
configuration, every axis derived from the method table. The **value lane does not**. It is a
hand-written list of rows — one fixture per operation, mostly at `R = 0`, one scheme, one α/β setting —
and it is the only lane holding independent oracles. So the axes exist and are crossed everywhere
except where correctness is actually checked.

Every survivor in the queue below is that one fact, not a missing axis:

- tensor `divergence`, `convolve` above `R = 0`, the spline transfer at `R = 2` → the **tensor-order** axis
- the α/β branches of convolve, anterpolate and the kernel-composed operators → the **α/β** axis (invariant 10)
- `anterpolate` under `DirectDFT`/`NUFFT`, the non-default spline orders → the **scheme** axis
- the mapped reductions, `inner(f, g)` with `f ≠ g`, fiber-constant operands, the vector-tensor right
  action → the **operation** axis, taken per METHOD rather than per symbol
- HDF5 read-back metadata → **representation × tensor order** on the read side

### The measured denominator (2026-08-02)

- **112** public operations · **556** package-owned methods behind them · **169** value-lane rows
- 35 operations have exactly one method; 77 have several. Heaviest: `mul!` 48, `*` 46, `multiply!` 26,
  `+` 23, `-` 23, `add!` 21.

556 overstates the work. The heavy operations are code-generated — `mul!`'s 48 methods are stamped from
one formula builder across argument orders, representations, orders and arities — so many cells close
with a recorded reason rather than a row. Estimated genuinely distinct behaviours needing their own
oracle: **60–120**, against the 169 rows that exist. Roughly a doubling of the value lane.

### Definition of done

**Every `(operation × method)` cell either has a value-lane row driving it, or a recorded reason it
cannot have one — and the ledger FAILS when a cell has neither.** That is decision 55's oracle-provenance
rule applied per method instead of per symbol, which is the bookkeeping defect that let one checked
method mark a whole generic covered.

### The ledger must itself be falsifiable, and that is the hard part

It is the measuring instrument, so a defect in it reports coverage nobody then investigates. This
session produced exactly that failure once already: `survey_covered` filtered for a placeholder that is
only inserted when a key is ABSENT from the text scan, so it selected a set nearly disjoint from the one
its own comment described — and reported 84 violations falling to 0, which read as success. The number
was verified; the instrument was not.

It cannot be verified by reading. It is verified by PERTURBATION, and these four probes belong in
`selfcheck.jl` beside every other check-that-must-fire:

1. **Delete a known value row** → the uncovered count rises by exactly one and names that cell.
2. **Add a row for a known-uncovered cell** → the count falls by exactly one and that cell leaves the list.
3. **Point a row at a method that does not exist** → reported as unmatched, never silently crediting the symbol.
4. **A cell closed by a recorded reason** stays distinguishable in the output from one closed by an actual
   row — otherwise "covered by a sibling builder" becomes a way to make anything green.

### One finding the corrected instrument immediately surfaced

Rebuilding the guard's coverage set from the runtime registry changed its verdict from 0 violations to
**1**, on a full run. The buggy filter had been hiding it: by selecting only cells with no textual
footprint anywhere, it dropped every survey row that also matches the source scan — which is most of
them. The one violation is a genuine disagreement between a lane's credit and the ledger's applicability
rule, and it is the first thing to identify when this work resumes, because it is evidence the corrected
instrument reads something the broken one could not.

### The order of work

1. Build the ledger: enumerate the 556 cells, map each value-lane row to the method it dispatches to.
2. Prove it falsifiable with the four probes above, and run a mechanics audit on the ledger's own code
   before trusting any number it prints.
3. Work the queue down with the uncovered count as the progress bar, widening the references that are
   not yet generic (`ref_divergence` takes a vector fibre only; the spline references hardcode
   Catmull-Rom) and driving the ones that already are (`ref_inner`, `ref_spectral_inner`,
   `ref_radial_spectrum`, `ref_interpolate_catmull_rom`, `ref_spectral_interpolate` all accept `R` and
   are called at one value).

The advantage over the audit loop this replaces: the ledger's correctness has an objective test, and its
completion is a number reaching zero rather than an assertion that nothing is left.

## The open work queue, and the class it belongs to

A reasoned mutation audit over every operation family produced eighteen survivors, and they share one
shape: **a second dispatched method of an already-covered generic**. A higher tensor order, an α/β
arity, a fiber-constant operand, a non-default scheme, the `f ≠ g` branch, the read side of a
write/read pair. Coverage in this suite is bookkept per SYMBOL — one checked method marks the name
done — so a generic with eight methods reports as covered when one is checked.

That is why the list below is a queue rather than a set of surprises, and why the durable fix is a
`(operation × method-signature)` ledger, one row per entry in `methods(f)` rather than per symbol,
which would surface the whole class mechanically instead of one instance per audit.

Currently unchecked at value level, in rough order of how much a defect there would cost:

- the mapped reductions (`mean(φ, f)`, `integral(φ, f)`, `maximum/minimum/extrema(φ, f)`)
- tensor→vector `divergence` — no reference accepts a tensor fibre
- `convolve`/`exponential_convolve` above R = 0, and every α/β accumulate branch of that family
- the spectral constant-add family (invariant 4's zero-mode-only update)
- the vector-tensor right action `u_j A_{ji}`, and `cross` with a fiber-constant operand
- spectral `inner(f, g)` with `f ≠ g` — structurally distinct code from the self branch
- `anterpolate` under `DirectDFT`/`NUFFT`, and the local-spline transfer at R = 2
- the non-default spline orders `LalescuSpline(n, m)` and `LagrangeSpline(n)`
- HDF5 read-back grid and layout metadata (the type check is vacuous for the parametric fields)
- `SeparableKernel` application, whose declared "materialize agrees with compressed" relation is built
  from a radial kernel on both sides

Several of these are covered by the GATE (`test/transfer_spectral.jl`, `test/interpolation_transfer.jl`,
`test/convolution.jl`); they are listed because the SURVEY does not reach them, which is what this
document is about.

## What this survey does NOT catch

Established by reasoning through specific defects rather than by reading the lanes — the honest
complement to the coverage tables above, and what a reader is most likely to assume wrongly.

- **A defect confined to a GPU `@kernel` body, with its CPU twin left correct.** Only the
  universal-checks lane crosses a device, and it asserts no VALUE there: preservation, finiteness,
  metadata, determinism and type-stability all pass on a wrong-but-finite result, and determinism on a
  device is compared to a tolerance, which is self-consistency rather than correctness. The package
  deliberately duplicates arithmetic into a KA kernel and a hand-written CPU twin, so this is a real
  surface rather than a hypothetical one. Value-level device parity lives in `test/gpu/suite.jl`,
  outside this survey.
- **`radial_correlation(f, g)`, and the two-field co-spectrum above R = 0.** The single-field forms have
  oracles at R = 0 and R = 1, and `radial_spectrum(f, g)` has one at R = 0; the physical-space
  cross-correlation and the higher-order co-spectra do not.
- **HDF5 persistence beyond a vector field and a point set.** The round-trip is byte-checked for
  `VectorFieldPhysical` and `PointSet`; the scalar and tensor fields, all three spectral kinds, and the
  point-value types are invoked but never read back and compared, so a defect confined to one branch of
  the tag-dispatch chain either throws or reconstructs a wrong object compared against nothing.
- **Invariants 1, 7, 8 and 12** — that a banned method stays absent, that no type piracy appears, that no
  fiber-fiber method is defined, and the no-time/no-particles naming discipline. These are completeness
  guards, and the gate-versus-survey rule places them in the gate deliberately: such a guard must fail
  the moment a violation lands, which an occasionally-run survey cannot do.
- **Grid axes of length 1 or 2.** No configured grid has one.

## Explicitly out of scope, with reasons

- **Benchmarks.** Time measurement is a different instrument with a different discipline (a quiet
  machine, frozen baselines) and lives in `benchmark/`.
- **Doctests.** A doctest asserts rendered output for one fixed input; there is no product to sweep.
  The sweepable part of the same question — *does every public operation have a runnable example* — is
  **NOT IMPLEMENTED** — no such class exists in `classify_checks.jl` and nothing counts doctests per
operation. Recorded as a gap rather than described as covered.
- **Multi-process and true concurrency.** Two operations running simultaneously on shared data is a
  different failure model; the thread-count axis covers the parallelism the package actually has.
