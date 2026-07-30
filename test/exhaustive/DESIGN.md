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
external generics included (`map`, `cov`, `inv`, the field arithmetic). **Extended here to callable
types** — `Grid3D`, the six field types, `PointSet`, the four kernel classes, `NUFFT`,
`FieldTransformPlans` — because constructors are things people write tests for and a function-only
derivation cannot see them. This gap is not hypothetical: `StoredKernel` could not be entered in the
oracle registry for exactly this reason.

## Axis 2 — argument assignment

For each operation, the product over its slots. Each slot's pool is keyed by its **declared parameter
type** and is itself derived:

| slot type | pool, derived from |
|---|---|
| kernel | concrete subtypes of `AbstractSpectralKernel` — the sweep that caught `StoredKernel` |
| transfer scheme | concrete subtypes of `AbstractTransferScheme` |
| section | tensor order × representation × storage relation (`distinct`, `dest≡a`, `dest≡b`) |
| numeric parameter | the boundaries in the **validation code** (``0 \le lo \le hi``, ``p \ge 1``, ``tol > 0``), not invented values |
| context object | matching / foreign-grid / foreign-layout / foreign-eltype |
| point set | typical / `M = 0` / `M = 1` / clustered / on-node / outside the box |

Since decision 59 a section owns its storage, so the storage relation has three values and is
enumerated completely rather than sampled.

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
`has-example`

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
pattern, applied to the check-type axis.

An exemption reason is itself checkable, and must be checked, or it becomes the place misses hide:

- an operation **declared linear** may not be exempt from `adjoint` or `representation-agreement`
- an operation with an **in-place form** may not be exempt from `allocation`
- an operation that **allocates its result** may not be exempt from `metadata`

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

## Explicitly out of scope, with reasons

- **Benchmarks.** Time measurement is a different instrument with a different discipline (a quiet
  machine, frozen baselines) and lives in `benchmark/`.
- **Doctests.** A doctest asserts rendered output for one fixed input; there is no product to sweep.
  The sweepable part of the same question — *does every public operation have a runnable example* — is
  kept as the `has-example` completeness value.
- **Multi-process and true concurrency.** Two operations running simultaneously on shared data is a
  different failure model; the thread-count axis covers the parallelism the package actually has.
