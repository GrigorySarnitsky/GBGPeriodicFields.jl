# The exhaustive suite

The full Cartesian product, run **occasionally** — not part of `Pkg.test()`.

```
julia --project=. test/exhaustive/runtests.jl
```

## Why it is separate

The default suite is a gate and must stay fast; it runs about six minutes. This is a survey and must
stay complete. Giving one job to both means the survey gets trimmed until it is no longer a survey, so
they are separate lanes — the same split the GPU suite and the benchmarks already use.

## What it is for

Every other layer in `test/` checks combinations someone chose. This one enumerates them. The reason
that matters is not thoroughness for its own sake: a defect that lives in a combination nobody thought
to write down is invisible to every check that starts from a list, however careful the list is. The
storage-aliasing lane found nine such defects the first time it ran, three of which had survived a
deliberate hand-written probe of the same property an hour earlier.

## How to read the output

**It is a report, not a gate that has been silenced.** It runs blind to what the package has decided
and prints everything that does not work. Where a failure corresponds to a recorded decision or a
documented contract, the citation is printed beside it — as an explanation of a known gap, never as a
reason to call it green. Three things to look for:

- **`NO CITATION`** — a new finding. Nothing in the package's record explains it.
- **a cited failure** — a known gap. Still a failure, still printed, still counted.
- **`NOT REACHED`** — a combination the lane could not construct. This is the important one: a lane
  that cannot build a case must say so rather than let its silence read as a pass. The aliasing lane
  reports the order-changing operations here, because their slots have different tensor orders and so
  cannot be given an offset-overlapping pair by this construction.

Exit code: `0` clean, `1` failures that are all cited, `2` at least one uncited finding.

## Lanes

- **`aliasing.jl`** — every in-place operation × every way its arguments can share storage. The slots
  draw from one shared pool, which is what makes aliasing reachable at all: enumerating "what is each
  argument" builds each separately, and two independently constructed arrays never share storage, so a
  per-slot product reaches an aliasing pair with probability zero. The oracle is invariant 9 itself —
  the result must equal the same call on fresh disjoint copies.
