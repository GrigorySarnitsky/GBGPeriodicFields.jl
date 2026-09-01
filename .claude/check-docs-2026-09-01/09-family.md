# Lane 08-family — CHECK 7 (operation-family variant-pair audit)

Unit of review: the operation FAMILY (every generic documenting one operation), not the single
docstring. For each family: does the defining math live in exactly one home; is every other variant a
thin wrapper that `@ref`-links the home with no re-derived formula; does notation stay identical across
the pair; is the verbatim in-place steer sentence present (naming the destination argument the
signature actually has) on every `!` form that has an allocating sibling.

Enumeration method: `grep -n '^function [a-zA-Z_!]* end$'` (and bare-binding docstrings, e.g. `dot`,
`cross`, `mean`) across every file in `src/`, cross-referenced against `grep -n 'Use this in-place form
when'` to confirm sentence coverage and destination-argument naming. 39 families enumerated below (33
with the verbatim in-place steer, 2 setter/no-sibling exemptions, 1 documented reworded exemption
(`translation_kernel!`), 2 documented no-sentence exemptions (`to_physical!`/`to_spectral!`), 1 no-sibling
motion verb (`displace!`), plus `wrap!`).

## `src/DifferentialOperators.jl` — 8 families, all CLEAN

All eight (`gradient`, `divergence`, `curl`, `inverse_curl`, `symmetric_gradient`, `laplacian`,
`inverse_laplacian`, `helmholtz_projection`) follow the identical, correct shape:

- The componentwise/spectral-symbol formula lives once, on the `!` form (`function f! end`).
- The allocating form (`function f end`) carries the verbatim sentence "Use this in-place form when
  `destination` is already allocated; the allocating [`f`](@ref) returns a fresh result instead." —
  confirmed present and byte-identical in wording across all 8 (`grep -c` = 8 in this file).
- No allocating docstring re-derives the spectral kernel; each links "See `f!` for the componentwise
  definition[, the spectral kernel/the gauge/the kernel-composed form]."
- Notation: every partial derivative uses `\partial_{x_i}` (never the bare-index `\partial_i` the
  decision-log records as the historical drift instance) — verified with
  `grep -rn '\\partial_[ijk][^_{]' src/*.jl`, zero hits anywhere in the package. Both `divergence!` and
  `helmholtz_projection!` carry the "kernel-composed form" section with matching α/β phrasing and
  matching `SpectralKernel` storage-class language — no drift between the two.
- `curl!`/`helmholtz_projection!` each state their own aliasing guarantee locally (the documented
  exception to the module-level rule, since each has an operation-specific reason — reading all three
  mode components before writing).

## `src/FieldAlgebra.jl` — 15 families, all CLEAN

`add!`/`+`, `subtract!`/`-`, `multiply!`/`divide!`/`*`/`/`, `dot!`/`dot`, `cross!`/`cross`, `mul!`/`*`,
`transpose!`/`transpose`, `norm!`/`norm`, `tr!`/`tr`, `det!`/`det`, `sym!`/`sym`, `skew!`/`skew`,
`dev!`/`dev`, `map!`/`map`. (`combine!` has no allocating sibling — correctly carries no such sentence,
confirmed by absence in its docstring.)

- Every `!` form's docstring is the home: the componentwise formula (`math` block) appears once, on the
  `!` binding, and the corresponding allocating/operator docstring is a one-paragraph thin wrapper
  ("Allocating form of [`f!`](@ref): ... See `f!` for the componentwise ... formula.") with no
  duplicated `math` block. Verified by reading all 15 pairs in full (lines 235–1697).
- `grep -c 'Use this in-place form when'` = 15 in this file, one per `!` form with a sibling, each
  correctly naming `destination` (the signature's actual argument in every case here).
- Bare operators (`+`, `-`, `*`, `/`) carry the required thin allocating docstrings in plain backticks
  (not `@ref`), consistent with the documented style exception.
- No notation drift: every family uses one consistent index convention (`A_{ij}`, `u_i`, `\varepsilon_{ijk}`)
  between the `!` home and its wrapper; `dot!`/`cross!`/`mul!` all consistently write "physical-space
  only" / "spectral representation only" language identically between the field-field and
  field-fiber variants within the same family.
- `map!`/`map` (decision 48): home on `map!`, thin wrapper `map` links back and does not restate the
  aliasing/physical-only warnings — it says "See `map!` for the arguments and the
  physical-representation-only / aliasing caveats." Clean.
- `Points.jl` reuses these exact same generics (`dot!`, `cross!`, `mul!`, `map!`/`map`, etc.) for
  `AbstractPointValues` with **no second docstring** — confirmed by `grep -n '"""'` count/placement in
  `Points.jl` showing no docstring immediately preceding e.g. `dot!(destination::ScalarPointValues, ...)`.
  This is the correct "one docstring per operation, on the bare binding" behaviour — zero drift risk
  because there is no duplicate to drift.

## `src/Convolution.jl` — 2 families, both CLEAN, + 1 documented exemption

- `convolve!`/`convolve`: formula home on `convolve!` (the circular-sum / coefficientwise-product
  formula and the Hermitian-kernel warning); `convolve` is a thin wrapper, no duplicate formula.
  Verbatim in-place sentence present, `destination` named correctly.
- `exponential_convolve!`/`exponential_convolve`: formula home on `exponential_convolve!` (covers both
  the single-operand and two-operand forms); `exponential_convolve` is thin, links back. Verbatim
  sentence present.
- `translation_kernel`/`translation_kernel!`: this is the **documented exemption** (CLAUDE.md, recorded
  2026-08-04): here the *allocating* form (`translation_kernel`) is the home (full formula, Nyquist
  warning), and `translation_kernel!` — which rebuilds an existing kernel rather than filling a
  `destination` — carries a reworded steer ("Use this in-place form when a displacement changes and the
  kernel is already allocated; the allocating [`translation_kernel`](@ref) returns a fresh kernel
  instead.") plus "The displacement convention and the Nyquist treatment are `translation_kernel`'s."
  with no re-derived formula. Matches the documented exemption exactly — verified by reading both
  docstrings in full (lines 1837–1967).

## `src/Interpolation.jl` — 2 families, both CLEAN

- `interpolate!`/`interpolate`: **one** docstring on `interpolate!` covers all three schemes
  (`AbstractSplineScheme`, `DirectDFT`, `NUFFT`) per the "collapses 12 → 4" consolidation the module
  docstring describes — scheme-specific accuracy/weights are delegated to each scheme's own docstring,
  not re-derived here. The `DirectDFT`/`NUFFT` methods of `interpolate!`/`anterpolate!` (lines
  1239, 1269, 1671, 1714) carry **no** docstring of their own — confirmed by reading the source directly
  above each `function` line — so there is nothing to drift. `interpolate` is a two-sentence thin
  wrapper, no formula.
- `anterpolate!`/`anterpolate`: same shape; `anterpolate!` is the home (the adjoint-transpose
  characterization, the α/β accumulate convention, the conservation property, the Brandt & Lubrecht
  1990 citation); `anterpolate` thin, links back.
- Verbatim sentence present on both, correctly naming the destination argument each signature actually
  has: `out` for `interpolate!`, `field` for `anterpolate!` — matching the documented naming exception
  in CLAUDE.md's docstring rubric ("`destination` in most of the corpus, but `out` in `interpolate!` and
  `field` in `anterpolate!`").

## `src/Fields.jl` — `to_physical!`/`to_physical`, `to_spectral!`/`to_spectral`, `adapt!`/`adapt`

- `to_physical!`/`to_physical` and `to_spectral!`/`to_spectral`: the `!` forms are the home (the
  input-preservation contract of invariant 11, the FFT normalization convention on `to_spectral!`). The
  allocating forms are thin and correctly do **not** re-derive the normalization; they state only "this
  one preserves `spectral`/`physical`" and link back. Neither carries the literal "Use this in-place
  form when `destination` is already allocated" sentence — this is the **documented exemption**
  (CLAUDE.md: "`to_physical!`/`to_spectral!` already steer to their siblings for the stronger
  input-preservation reason (invariant 11) and are not doubled"). Confirmed clean against that note.
- `adapt!`/`adapt`: unusual direction — `adapt` (allocating) is architecturally the fuller "home" because
  it alone covers the non-section classes (`FieldSpectralMultipliers`, kernels, `FieldTransformPlans`)
  that have no in-place form; `adapt!` nonetheless correctly carries the verbatim in-place sentence
  ("Use this in-place form when `destination` is already allocated; the allocating [`adapt`](@ref)
  returns a fresh result instead.") and does not duplicate `adapt`'s formula/example block — its own
  content (the destination-exists cost argument, the no-target-argument explanation) is
  argument-specific to the `!` form, not a re-derivation. No drift found.

## `src/FiberSections.jl` — `threading_cutoff`/`set_threading_cutoff!` (getter/setter), CLEAN

- `threading_cutoff()` is the home: full definitional prose (what counts as an "assignment", the two
  exempt KA-kernel groups, the default value).
- `set_threading_cutoff!(n)` is a thin wrapper: "Set [`threading_cutoff`](@ref) to `n` and return it."
  followed by one clause restating the practical effect and one clause on scoping (process-wide vs
  `with_threading`'s task-local scope) — this is argument-specific setter content, not a second copy of
  the getter's definition. No drift.
- `set_fft_threads!` has no getter and no allocating sibling — correctly carries neither a "home
  restated" issue nor the verbatim sentence (matches the documented exemption list: "A `!` form with no
  allocating sibling (`combine!`) and a setter (`set_fft_threads!`, `set_threading_cutoff!`) take no such
  sentence").

## `src/Points.jl` — `displace!` and `wrap!`, both single-form by design, CLEAN

- Neither has an allocating sibling ("There is deliberately no allocating sibling" is stated explicitly
  in `displace!`'s own docstring). Both correctly carry no verbatim in-place sentence. No family-pair
  drift possible since there is no pair.

## `src/Reductions.jl` — no `!` forms exist in this module

`grep -n 'function .*!.*end$\|^function [a-zA-Z_]*!('` over `Reductions.jl` returns no matches. The
physical/spectral duality that could have produced drift (`inner`, `integral`, `mean`, `var`, `std`) is
instead handled as **one docstring per generic** covering both representations inline (e.g. `inner`'s
docstring states the grid/point-set sum, then "For two fields in spectral representation `inner` returns
the same value by Parseval's theorem ... applying the rfft half-spectrum weighting internally" in the
same docstring) — so there is no duplicate formula to drift. `std` and `minimum`/`extrema` are thin
wrappers linking to `var`/`maximum` respectively, with no re-derivation. Clean by construction — not
applicable to the f/f! or getter/setter shape this check targets, and verified there is no violation of
"one home" for the physical/spectral duality either.

## Verdict

**0 findings.** Every operation family with more than one generic in `src/` was enumerated (39 families
across `DifferentialOperators`, `FieldAlgebra`, `Convolution`, `Interpolation`, `Fields`,
`FiberSections`, `Points`) and every one keeps its defining math in exactly one home, every wrapper
correctly `@ref`-links without re-deriving, no glyph/notation drifted across any pair (checked
specifically for the historical `\partial_i` vs `\partial_{x_i}` class — zero remaining bare-index
instances anywhere in `src/`), and the verbatim in-place steer sentence is present, word-for-word, on
every `!` form with an allocating sibling except the documented exemptions (`to_physical!`/
`to_spectral!`, `translation_kernel!`, the two setters, `combine!`, `displace!`), all of which match
their recorded CLAUDE.md exemption text exactly.
