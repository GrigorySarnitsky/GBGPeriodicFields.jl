# Lane 10 — surface 6, the BUILT API pages (`docs/build/api/*/index.html`)

Run 2026-09-01 after `docs/make.jl` exited 0. This surface is not a rendering of the `.md` sources:
those pages are mostly `@autodocs`/`@docs` blocks whose CONTENTS ARE DERIVED, and the source lane
skips block contents by instruction. What each block actually collected is visible only here.

Nine module pages parsed: 159 public and 140 internal rendered docstrings.

## Question 1 — nothing public under "Internal API": CLEAN

No `Base.*` binding appears in any Internal API section. The `Filter` that was added after `map`,
`map!` and `transpose` leaked there is still doing its job on every module, not just the one that was
reported.

## Question 2 — nothing rendered twice: CLEAN

No binding appears in both a public section and an Internal API section on any page.

## Question 3 — nothing public missing: CLEAN (one dismissal)

The derived public surface (`test/public_surface.jl`'s `package_operations()`) is 123 operations.
Diffed against every non-Internal section, the residue is:

- the nine unexported `Base` extensions `size`, `eltype`, `axes`, `copy`, `copyto!`, `getindex`,
  `setindex!`, `ndims`, `length` — deliberately omitted, `checkdocs = :exports` does not require them;
- `adapt_structure` — **dismissed with reason**. It is `Adapt.jl`'s hook, not an operation a user
  calls: decision 63 records that the package extends `adapt_structure` and re-exports `adapt`, and
  `adapt` and `adapt!` are both rendered under Fields' "Moving between storage families". Documenting
  each one-line hook method would restate on nine types what `adapt` documents once. Same class as the
  Base extensions above.

**Instrument note (not a docs finding):** the command's expected-residue list predates decision 63 and
does not name `adapt_structure`, so this dismissal will be re-derived on every future run. Worth one
deliberate line in `check-docs.md`, as its own commit.

## Finding 1

- **Check:** 5 (current and complete).
- **Location:** `docs/src/api/FiberSections.md:36` — the Internal API blurb.
- **Quote:** "the CPU-threading primitives and the fiberwise-algebra code generators, for anyone
  extending the package's algebra."
- **Rule:** check 4 of surface 6 — an Internal API blurb is hand-written while its list is derived, so
  the two drift silently; and CLAUDE.md check 5, under which a summary naming only a SUBSET of what the
  block holds is stale even if every clause is true.
- **Evidence:** the block collects 47 entries. Two whole families are unnamed: the **fused fiberwise
  executor** (`_fiberwise_pass!`, `_fiberwise_slab!`, `_foreach_outer_slab`, `_write_values!`,
  `_accumulate_values!`, `_assemble_fiber`, `_assemble_inputs`, `_flatten_fiber`, `_MapValues`) — which
  is decision 39's machinery and is named as such in CLAUDE.md's own module list — and the
  **storage-ownership check** `_check_owned_storage`, decision 59's rejection of borrowed storage. The
  section-introspection helpers (`section_scalar_type`, `section_tensor_order`, `_fiber_type`,
  `_fiber_order`) are likewise neither a threading primitive nor a code generator.
- **Fix:** name the executor and the ownership check in the blurb.
- **Status:** FIXED.

## Finding 2

- **Check:** 5 (current and complete).
- **Location:** `docs/src/api/Interpolation.md:55` — the Internal API blurb.
- **Quote:** "the scheme supertype `AbstractSplineScheme`, the spline-weight generators (Fornberg
  finite differences plus a small linear solve), the periodic cell-finding, and the in-kernel helpers."
- **Rule:** as Finding 1.
- **Evidence:** three of the four clauses match what the block collected (`AbstractSplineScheme`;
  `_fornberg`, `_hermite_weight_matrix`, `_lagrange_weight_matrix`; `_locate`). The fourth does not:
  the block holds no in-kernel helpers, it holds two COMPATIBILITY CHECKS,
  `_check_nufft_compatibility` and `_check_transfer_colocation`.
- **Fix:** replace the "in-kernel helpers" clause with the compatibility checks it actually holds.
- **Status:** FIXED.

## Finding 3

- **Check:** 5 (current and complete).
- **Location:** `docs/src/api/Convolution.md:83` — the Internal API blurb.
- **Quote:** "the coefficientwise convolution, combination and exponential-kernel bodies, and the
  axis-factored pair that evaluates a separable kernel per mode."
- **Rule:** as Finding 1.
- **Evidence:** the block now collects eight entries, and two of them are decision 79's
  `_exponential_convolution_modes!` / `_exponential_combination_modes!` — a KERNEL PAIR (a
  KernelAbstractions kernel with a gated CPU twin), not a coefficientwise "body". The blurb was written
  before that decision and describes six of the eight.
- **Fix:** name the kernel pair beside the bodies.
- **Status:** FIXED.

## Verified clean, recorded so silence is not mistaken for absence

`FieldAlgebra` ("two storage helpers", holds exactly two), `Fields`, `Points`, `Reductions` and
`DifferentialOperators` blurbs each name every family their block collected. `GBGPeriodicFields`
has one public entry and no Internal API section.

**Not a finding:** 17 of 22 internal definitions in `src/Interpolation.jl` carry no docstring
(`_dft_axis`, `_fresh`, `_nufft_beta`, …). CLAUDE.md requires docstrings on named CATEGORIES of
hand-written machinery — codegen builders, the fused executor, shared `Fields` helpers, spectral
kernels — not on every `_`-prefixed local helper, and it reserves plain comments for exactly this
kind of small local rationale. Documenting all 17 would be scope creep against that balance.
