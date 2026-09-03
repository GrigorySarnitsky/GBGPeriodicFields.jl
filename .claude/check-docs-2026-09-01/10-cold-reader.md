# check-docs lane 09-cold-reader

Surface: the AUDIENCE half of check 2 (cold-reader opacity) — every exported docstring in
`GBGPeriodicFields`, read as a reader who has not read the module's source. Per the lane
method, the substrate was built the way a REPL reader actually sees it: for a generic with
several methods, all of a binding's methods rendered together, plus the nine module docstrings
(`GBGPeriodicFields`, `Fields`, `FieldAlgebra`, `DifferentialOperators`, `Convolution`, `Points`,
`Interpolation`, `Reductions`, `FiberSections`), which a reader reaches via `?ModuleName`.

## Method

1. Enumerated the full public surface: 316 raw tokens after `export` across all nine source files
   (after stripping prose noise from multi-line `export` statements), collapsing to the true
   `names(GBGPeriodicFields)` list of 137 bindings, plus the Base/`Statistics`/`LinearAlgebra`
   generics the package extends without a formal `export` (`mean`, `std`, `var`, `cov`,
   `maximum`, `minimum`, `extrema`, `map`, `map!`) per the umbrella docstring's own claim that
   these are "all reachable from `using GBGPeriodicFields` alone."
2. Dumped every one of those bindings' rendered docstring(s) via `Base.Docs.doc` inside a loaded
   package session (`julia --project`), reproducing what `?name` shows — 3936 lines of extracted
   text, read start to finish.
3. Read all nine module docstrings directly from source (`src/*.jl`, lines 1–~110 of each file).
4. For every noun that looked like a package term of art (`section`, `fiber`, `base`, `resolved
   band`, `storage family`, `canonical`, `assignment`, `symbol`, `Nyquist-zeroed`, `visit order`,
   `partition of unity`, etc.), checked whether it is bound in the SAME docstring, in the module
   docstring for that binding's home module, or in the umbrella `GBGPeriodicFields` module
   docstring (which explicitly defines base/fiber/section/resolved band/storage family/
   band-limited as "five words recur in every operation's documentation" — reachable via `?
   GBGPeriodicFields`) — before ever counting a candidate as a finding.
5. Investigated one structural question the substrate-building step raised: whether `@doc
   name`/`?name` actually surfaces the package's OWN docstring for a binding that extends an
   upstream generic (`mean`, `cov`, `norm`, `dot`, `cross`, `mul!`, `tr`, `det`, `transpose!`),
   since a naive `@doc` probe returned only the upstream (`Statistics`/`LinearAlgebra`/`Base`)
   docstring for all twelve of them. Verified against the REAL REPL help path
   (`REPL.helpmode`/`REPL.@repl`, not the bare `@doc` macro) with both a minimal reproduction and
   the package itself: `?mean` DOES render a `MultiDoc` concatenating every registered
   docstring for that binding, upstream ones first and the package's own last, separated by
   horizontal rules — so the naive-`@doc` result was an artifact of the extraction method, not a
   defect in the package. This is recorded as a discarded candidate below, not a finding, per the
   lane's calibration rule (verify before reporting).

## Candidates discarded on verification

Twelve candidates surfaced by the raw dump and were discarded after checking the real REPL path
(§5 above): `mean`, `std`, `var`, `cov`, `maximum`/`minimum`/`extrema`/`map`/`map!` (implied by
the same mechanism, not separately re-tested), `norm`, `dot`, `cross`, `mul!`, `tr`, `det`,
`transpose!`, `adapt`. For each, the package's own docstring (already read directly from source
and cross-checked against the rubric) IS reachable via `?name` — it simply sorts after the
upstream stdlib's own overloads in the rendered `MultiDoc`, which is standard, expected Julia
multi-dispatch documentation behavior, not something specific to this package's writing.

A second class of candidates was discarded as domain-standard vocabulary rather than
package-invented terms of art, consistent with CLAUDE.md's own carve-out for "universally
standard math" and a stated cloud-physics/turbulence audience: `enstrophy`, `dissipation`, `rms`,
`turbulence intensities` (`Reductions` module docstring, in a sentence that explicitly says these
stay consumer-side and are not computed by the package); `symbol`/`wavenumber symbol`
(`DifferentialOperators` module docstring) — standard PDE/pseudodifferential-operator
terminology for a differential operator's Fourier multiplier, and in any case glossed exactly
once, on `RadialKernel`'s docstring ("its *symbol*, in the sense the differential operators use
for the multiplier a coefficientwise operator applies"), reachable from the same page family.

A third candidate, "quadrature weight" (umbrella module docstring, in the base/fiber/section
paragraph: "a grid cell carries the quadrature weight a reduction integrates against"), was
checked and found to need no separate binding — it is explanatory apposition inside the
sentence defining `base`, not a term the reader is expected to already know or look up
elsewhere.

## Findings

None survived verification.

## Verified clean

The following were positively checked (symbol/term enumerated, binding location cited) and found
correctly self-contained for a cold reader, across every exported binding in the package:

- **Module docstrings (9/9).** `GBGPeriodicFields` (umbrella) explicitly binds `base`, `fiber`,
  `section`, `resolved band`, `band-limited`, and `storage family` in plain language before first
  use, per its own stated design ("Five words recur in every operation's documentation..."). Each
  submodule docstring (`Fields`, `FieldAlgebra`, `DifferentialOperators`, `Convolution`, `Points`,
  `Interpolation`, `Reductions`, `FiberSections`) reads as a self-contained map with no term left
  to a reader's guess — e.g. `Convolution` binds "kernel is not a field," the four kernel storage
  classes, and "the integration structure" on first mention; `Interpolation` derives the
  gather/scatter adjointness identity from definitions stated in the same paragraph;
  `FieldAlgebra` defines "pointwise over the base" and the linearity-vs-representation
  distinction before using either.
- **Type docstrings.** `Grid3D`, `RealFourierLayout`, `FieldSpectralMultipliers`,
  `FieldTransformPlans`, all six field types, `Point`, `PointSet`, the three point-value types,
  `PointTraversalOrder`, `AbstractTransferScheme`, `SpectralKernel` and its four concrete classes
  (`StoredKernel`, `SeparableKernel`, `RadialKernel`, `ProductKernel`) — every constructor
  argument and struct field is bound in a `The fields are` / `The arguments are` list, and every
  cross-referenced concept (`canonical`, `Nyquist-zeroed`, `resolved band`, `visit order`) is
  explained at first use within the same docstring.
- **Operation docstrings.** All of `add!`/`subtract!`/`combine!`/`multiply!`/`divide!`, the
  contraction family (`dot!`/`cross!`/`mul!`/`tr!`/`det!`/`norm!`), the decompositions
  (`transpose!`/`sym!`/`skew!`/`dev!`), every differential operator (`gradient!` through
  `helmholtz_projection!`), the convolution family (`convolve!`, `exponential_convolve!`, the
  four kernel builders, `translation_kernel!`), the point-layer motion pair
  (`displace!`/`wrap!`), the transfer verbs (`interpolate!`/`anterpolate!`,
  `point_traversal_order`/`PointTraversalOrder`), and the reduction family (`integral`, `mean`, `inner`,
  `weighted_inner`, `l2norm`/`lpnorm`, `var`/`std`/`cov`, `maximum`/`minimum`/`extrema`,
  `radial_spectrum`/`radial_correlation`) — each states its formula, its argument roles, and its
  representation validity in terms defined on the page, with no unglossed jargon noun found.
- **Persistence and utility functions** (`write_field`/`read_field`, `write_points`/
  `read_points`, `write_scheme`/`read_scheme`, `adapt`/`adapt!`, `similar_field`/
  `similar_pointvalues`, `set_fft_threads!`, `set_threading_cutoff!`/`threading_cutoff`/
  `with_threading`, `reality_residual`, the shape/accessor functions) — all clean.

## Findings count

0
