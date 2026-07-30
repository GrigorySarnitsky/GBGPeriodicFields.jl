# The exhaustive suite

The full Cartesian product, run **occasionally** — not part of `Pkg.test()`.

```
julia --project=. test/exhaustive/runtests.jl
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

The aliasing lane crosses eight axes: element type, grid shape (parity, cubicity, anisotropy),
spectral fold, thread count, storage kind, aliasing relation, tensor order and representation. That is
**5,616 cases over 16 configurations in about 30 seconds.** It was 17,200 before decision 59: once a
section must own its storage, most of the aliasing axis stopped being arithmetic to verify and became a
construction to refuse, which is both cheaper and a stronger claim. `Pkg.test()` runs 360 s for a few
thousand assertions, which is the difference between a gate and a survey — this one buys two orders of
magnitude more combinations for a quarter of the time, because a negative or consistency check is
cheap and needs no oracle beyond "the answer must not change".

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
