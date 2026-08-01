# The exhaustive suite

The full Cartesian product, run **occasionally** — not part of `Pkg.test()`.

```
julia -t4 --project=test test/exhaustive/runtests.jl
```

The design — the axes, how each is derived, the applicability guards, and the adversarial pass that
shaped them — is in [`DESIGN.md`](DESIGN.md). Read that before adding a lane.

## Why it is separate

`Pkg.test()` is a gate and must stay fast; it runs about six minutes. This is a survey and must
stay complete. Giving one job to both means the survey gets trimmed until it is no longer a survey, so
they are separate lanes — the same split the GPU suite and the benchmarks already use.

## What it is for

Every other layer in `test/` checks combinations someone chose. This one enumerates them. The reason
that matters is not thoroughness for its own sake: a defect that lives in a combination nobody thought
to write down is invisible to every check that starts from a list, however careful the list is. The
storage-aliasing lane found nine such defects the first time it ran, three of which had survived a
deliberate hand-written probe of the same property an hour earlier.

The context-mismatch lane did the same on its first run. Sweeping each operation against an argument
differing in one derived quantity, it found that the **spectral** `inner` never checked tensor order:
`inner(scalar, vector)` returned a plausible number and `inner(vector, tensor)` returned `NaN`, where
both physical calls threw. The physical guard and its test had been added together and both stopped at
one representation. Fixed in `src/Reductions.jl`, pinned in `test/reductions.jl`, and the fix
mutation-verified in both places.

## The lanes

| lane | what it sweeps | oracle |
|---|---|---|
| surface coverage | every public operation | is it exercised by any lane at all? |
| universal checks | **every operation × every buildable call × every configuration × every backend** | five properties every operation must have (below) |
| reference cross-validation | the spectral operators, every configuration | independent implementations in `references.jl`, built from raw arrays |
| storage aliasing | every in-place operation × every storage relation | the same call on fresh disjoint copies |
| context mismatch | every entry point × every derived mismatch axis | a mismatched argument must be refused |
| applicability ledger | every operation × every check type | each cell implemented, or inapplicable for a derived reason |

The universal checks are the ones that sweep the whole surface, because their oracles do not depend on
what an operation computes:

- **preservation** — an allocating call leaves every argument unchanged; an in-place call changes only
  its destination
- **structural** — a finite input gives a finite result
- **metadata** — an allocating result carries its input's grid, layout and element type
- **determinism** — repeating a call reproduces it (bitwise on CPU, to a tolerance on a device)
- **result-type** — the value matches what inference promised, so a caller specializing on it is not
  specializing on a lie

All but the ledger assert behaviour and drive the exit status. **The ledger is a coverage report**: a
gap there says a question the design admits has not been asked of that operation, which is a work list
rather than a failure, so its count can grow without turning the report red.

## Running it

```
julia -t4 --project=test          test/exhaustive/runtests.jl     # CPU, plus HDF5 persistence
julia -t4 --project=test/gpu/cuda test/exhaustive/runtests.jl     # CPU and CUDA
julia -t4 --project=test/gpu/rocm test/exhaustive/runtests.jl     # CPU and ROCm
```

The vendor packages are dependencies of neither the package nor `test/`, so the device pool exists only
in a GPU environment. Run from one and the backend axis is crossed **for the universal-checks lane**;
run from `test/` and that lane says **NOT RUN** rather than passing quietly. The other eight lanes build
host fixtures and run CPU-only in every environment — `device` is threaded through the invocation engine
alone, not through `Config`, so a GPU run does not carry the value, relation, property, sequence,
aliasing or mismatch lanes onto the device.

## How to read the output

**It is a report, not a gate that has been silenced.** It runs blind to what the package has decided
and prints everything that does not work. Where a failure corresponds to a recorded decision or a
documented contract, the citation is printed beside it — as an explanation of a known gap, never as a
reason to call it green. Three things to look for:

- **`NO CITATION`** — a new finding. Nothing in the package's record explains it.
- **a cited failure** — a known gap. Still a failure, still printed, still counted.
- **`NOT REACHED` / `NOT APPLICABLE`** — a combination the lane did not construct, and why. This is
  the important one: a lane that cannot build a case must say so rather than let its silence read as a
  pass. The two are different, and the distinction is the point — `NOT REACHED` is a hole in the lane
  and is work to do; `NOT APPLICABLE` is a combination the package's model does not admit. The
  aliasing lane reports the order-changing operations as the latter: two sections of different tensor
  order can share storage only if a caller hand-builds a field over a view of another field's array,
  and there is no verb for that. A component of a vector field is obtained by contracting with a basis
  vector, which allocates its own storage.

Exit code: `0` clean, `1` failures that are all cited, `2` at least one uncited finding.

## Scale

96 configurations — element type × 4 grid shapes (one odd on every axis) × **3 layout folds** × thread
setting × 2 seeds, including a shifted non-commensurate origin — in about **85 minutes** with `-t4`,
measured on this host rather than estimated. (Three seeds and 144 configurations took 125 minutes; the
seed axis is the only one with no targeted defect class behind it, so it is where runtime is bought
back rather than from an axis that exists because a bug lived there.) The axis table, and what each axis crosses versus samples,
is in [`DESIGN.md`](DESIGN.md).

**Run it with `-t4`.** The thread-count axis is crossed by the configuration list, but a thread
invariance check can only mean something when more than one thread exists — and Julia defaults to one,
so every documented command here used to leave that axis dead: the `invariance` check type never fired,
in any configuration, and half the configurations were byte-identical work presented as a crossed axis.

`Pkg.test()` runs about six minutes for a few thousand assertions, which is the difference between a
gate and a survey: this one buys orders of magnitude more combinations because most of its checks are
universal properties or consistency relations that need no per-operation oracle.

## Lanes

- **`references.jl` + the reference-validation lane** — independent implementations of the operators,
  computed from raw arrays by the plainest expression of the definition and sharing no code with the
  package. They are the `correct` oracle the design calls for, and the lane checks them against the
  package on ordinary input **before** anything uses them: a reference that shares a misconception with
  the implementation makes every cell pass while both are wrong. Agreement is meaningful because the
  wavenumbers are rebuilt from the grid rather than taken from `FieldSpectralMultipliers`, so a
  convention error cannot hide by being copied. 112 pairs across 16 configurations; mutation-verified
  by flipping a sign in the `curl` reference.
- **`aliasing.jl`** — every in-place operation × every way its arguments can share storage. The slots
  draw from one shared pool, which is what makes aliasing reachable at all: enumerating "what is each
  argument" builds each separately, and two independently constructed arrays never share storage, so a
  per-slot product reaches an aliasing pair with probability zero. The oracle is invariant 9 itself —
  the result must equal the same call on fresh disjoint copies.

  Since decision 59 the lane has two halves. Sections own their storage, so the only way two of them
  share memory is by being the same array, and the arithmetic half enumerates that fully rather than
  sampling it. The other half asserts the **refusal has not reopened**: the borrowed-storage
  constructions that closed the class must still be rejected, checked per configuration and per tensor
  order rather than assumed from the constructor's source. A refusal that quietly stops refusing is a
  silent reopening, and it reports as an uncited finding — exit 2.
