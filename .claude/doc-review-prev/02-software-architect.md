# Software Architect / Senior Julia Programmer — Documented Design Review

Reviewing the rendered manuscript (Home, Architecture, Formalization, Notation, Performance,
Testing, Tutorial, all `api/*` pages, and the `examples/hist_cpu` page) as a Julia expert judging
the *documented* API and architecture: signatures, module decomposition, abstraction boundaries,
and internal consistency of the design narrative itself.

---

## Finding 1

- **Type:** contradiction
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - PAGE: api / FieldAlgebra, section "Internal API": *"the contraction formula builders, **the aliasing guard**, and the constant / zero-mode helpers"*
  - PAGE: api / Points, section "Internal API": *"the allocator, the broadcast style, and **the alias guard**"*
  - PAGE: examples / hist_cpu: `helmholtz_projection!(uh, uh, m) # make solenoidal (alias-guarded)`, versus the same file's own `helmholtz_projection!(Nh, ws.Nt, m) # ... DISTINCT dest ⇒ no-alias path (no allocation)`
- **Contradicts:** PAGE: architecture, §7 / decision-39 entry: *"The former guard family (`_guard_noalias!`...) is retired — decision 39 removed its last callers."* — axis: whether an alias-guard mechanism still exists anywhere in the codebase.
- **Description:** Architecture repeatedly and emphatically states the alias-guard family was retired (aliased calls are now computed directly, bitwise-identical, no temporary — invariant 9). Yet two module "Internal API" intros (FieldAlgebra, Points) still list "the alias guard"/"alias guard" among contributor-facing internals — though neither section's actual listing that follows documents a guard function — and the HIST_CPU.jl example labels an aliased `helmholtz_projection!` call "(alias-guarded)" while a sibling call in the same file correctly uses current "no-alias path" language. A repeated stale-terminology class, not a one-off typo.

---

## Finding 2

- **Type:** api-gap
- **Severity:** minor
- **Confidence:** high
- **Locations:** PAGE: api / Fields, "Field types" section (lists `AbstractFieldPhysical`, `AbstractFieldSpectral`, and the six concrete types only) and "Internal API" section (no entry either); yet `AbstractField` is used as the type constraint in numerous public signatures across pages, e.g. PAGE: api / Fields `field_data(field::AbstractField)`, `field_grid(field::AbstractField)`, `similar_field(reference::AbstractField, data)`; PAGE: api / Fields "HDF5 persistence" `write_field(parent, name, field::AbstractField)`; PAGE: api / FieldAlgebra Internal API `_copy_field_data!(destination::AbstractField, field::AbstractField)`.
- **Description:** `AbstractField` is never introduced or defined on any rendered page — not in the Fields module's "Field types" list, not in its "Internal API" list — despite being the declared type of arguments in some of the most fundamental public accessors (`field_data`, `field_grid`, `field_layout`, `write_field`/`read_field`, `similar_field`). A reader meets the identifier a dozen times but is never told what it is or where it sits relative to `AbstractFieldPhysical`/`AbstractFieldSpectral`/`AbstractFiberSection` — the exact "term never defined or linked" defect the project's own self-containedness rule targets.

---

## Finding 3

- **Type:** contradiction
- **Severity:** minor
- **Confidence:** high
- **Locations:** PAGE: api / Interpolation, module docstring: *"Interpolation yields a value while its adjoint returns a field, **the one asymmetry** in the API."*
- **Contradicts:** the same docstring's own signature blocks, a few lines above/below — axis: whether that is really the *only* asymmetry between `interpolate`/`anterpolate`.
- **Description:** The same page's signatures show at least two more asymmetries the text never flags: `anterpolate!` carries an α/β accumulate pair (`α::Real = true, β::Real = false`) that `interpolate!` has no counterpart for; and the allocating `anterpolate`'s first argument is `grid::Grid3D` for the spline schemes but `reference::AbstractFieldSpectral` for `DirectDFT`/`NUFFT`, whereas `interpolate`'s first argument is uniformly a field across every scheme family. "The one asymmetry" undercounts by at least two, an overclaim of exactly the kind the project's own review checklist warns against.

---

## Finding 4

- **Type:** design
- **Severity:** minor
- **Confidence:** high
- **Locations:** PAGE: api / Convolution, `exponential_convolve!` (six signatures shown, spanning 4–9 positional arguments); compare `NUFFT(reference; tol=1e-10, oversampling=2, width=0, beta=0)` and `Grid3D(...; origin=...)` on PAGE: api / Interpolation and PAGE: api / Fields.
- **Description:** Across `exponential_convolve!`'s own overload set, `α`/`β` name two different things: trailing accumulate weights in the single-field forms (`dest = α·kernel·field + β·dest`, `convolve!`'s convention) but leading combination weights in the two-field forms (`α·a + β·b`, `combine!`'s convention) — distinguished only by argument position/count. This is the exact "glyph-collision" failure mode decision 33's own text names and avoids *within* one signature, just not *across* the generic's method table. The `offset_scale`/`offset` pair is also handled by arity-overloading rather than as keywords, unlike the package's own keyword idiom for comparable optional extras elsewhere (`NUFFT`'s `tol`/`width`/`beta`, `Grid3D`'s `origin`).

---

## Finding 5

- **Type:** typesetting
- **Severity:** minor
- **Confidence:** high
- **Locations:** PAGE: notation, "Base and fiber" table.
- **Description:** The rendered conventions table breaks mid-row for `k`: *"$k$ | a wavenumber vector ($k_a$ is its $a$-th component, `` | k"* — a stray double-backtick and pipe truncate the "Code" column instead of rendering it, exactly the literal-pipe-in-a-table-cell hazard the project's own writing rules elsewhere warn against (for §13 decision-log tables). Notably this breaks the single canonical notation-reference page every docstring is told to defer to rather than repeat.

---

## Finding 6

- **Type:** api-gap
- **Severity:** minor
- **Confidence:** medium
- **Locations:** PAGE: api / Fields, "Internal API", `similar_field`: *"used by out-of-place field broadcasting and by allocating algebraic operations."* PAGE: examples / hist_cpu, `make_workspace`: eight scratch fields each built by hand via `spectral_field_shape(...)` + `zeros` + an explicit type constructor.
- **Description:** `similar_field`/`similar_pointvalues` are documented only as non-public Internal API, yet do exactly what a solver author needs to build compatible scratch fields. The flagship example — explicitly "written the way a real consumer would use `GBGPeriodicFields`" — never calls them, instead hand-rolling the equivalent pattern eight separate times in `make_workspace`. Either the helper deserves public status, or the reference example is missing a chance to demonstrate the idiomatic allocation pattern it exists to showcase.

---

## Finding 7

- **Type:** design
- **Severity:** minor
- **Confidence:** medium
- **Locations:** PAGE: api / Fields, `Grid3D`: four-argument constructor `(grid_size, domain_size, grid_spacing, origin)`; *"The two-argument constructor computes `grid_spacing = domain_size ./ grid_size`."*
- **Description:** `Grid3D` is introduced as a "Uniform three-dimensional grid," yet its explicit four-argument constructor accepts `grid_spacing` as an argument independent of `domain_size`/`grid_size`, with no stated invariant tying them together — only the two-argument convenience constructor guarantees consistency, by computing spacing itself. As documented, nothing stops a caller of the full constructor from passing a `grid_spacing` inconsistent with `domain_size ./ grid_size`, silently building a self-contradictory "uniform" grid — a denormalized field with no described consistency check.

---

## Finding 8

- **Type:** normalization
- **Severity:** minor
- **Confidence:** medium
- **Locations:** PAGE: api / Reductions, `Statistics.var`: *"the Bessel-corrected mean of the squared deviation... $\tfrac{1}{N-1}\sum_n$"*; contrast `mean`: *"$\tfrac{1}{N}\sum_n f_n$"*.
- **Description:** `var`/`std` default to the sample (N−1, Bessel-corrected) convention even on a `Grid3D`, where all N cells are the complete, exactly-known population, not a subsample drawn from a larger one — precisely the case where the biased 1/N estimator is exact and no correction is warranted. `mean`/`integral` use plain 1/N throughout with no such option. The package inherits `Statistics.var`'s default keyword rather than re-examining it for the always-exhaustive grid/point-set population the rest of the reduction family is built around.

---

## Finding 9

- **Type:** design
- **Severity:** nit
- **Confidence:** medium
- **Locations:** PAGE: api / FiberSections, "Threading configuration": `set_threading_cutoff!(n)` versus `with_threading(f; enabled=...)`.
- **Description:** `threading_cutoff`/`set_threading_cutoff!` mutate ordinary global state with no scoping described, while `with_threading` is explicitly *"dynamically scoped and task-local, so it affects only `f()` and is restored afterwards."* Two controls governing the same threading decision, documented side by side in one small section, follow two different concurrency-safety models — one safe under concurrent tasks by construction, the other a shared mutable global a concurrent caller could race against.

---

## Finding 10

- **Type:** organization
- **Severity:** nit
- **Confidence:** medium
- **Locations:** PAGE: architecture, decision-log "Phase A consolidation" entry: *"`Points` (unstructured-base section objects + their generated algebra — a noun peer of `Fields`)"*.
- **Description:** For the grid base, types (`Fields`) and fiberwise algebra (`FieldAlgebra`) live in two separate modules; for the point base, both roles fold into one module, `Points`, described as a "peer" of `Fields` alone. The two bases are presented throughout as symmetric ("same fibers, different base"), but their module decomposition is not: "where does the algebra for X live" has a different answer depending on which base X uses.

---

## Finding 11

- **Type:** performance
- **Severity:** nit
- **Confidence:** low
- **Locations:** PAGE: api / Reductions, `weighted_inner`: *"comparable to one spectral `inner`"*.
- **Contradicts (soft):** PAGE: architecture, decision-40 entry: *"`weighted_inner` stays serial for now... deferred with the exponential family's hoist."*
- **Description:** The `weighted_inner` docstring frames its cost as "comparable to one spectral `inner`," but Architecture's decision 40 records that every other reduction, `inner` included, now runs on the bitwise thread-count-invariant fixed tree, while `weighted_inner` explicitly stays serial. The comparison is algorithmically fair (same single-pass shape) but does not flag that the two no longer scale alike on a threaded CPU — a caller benchmarking one against the other on the decision-37 many-core target would see a gap the docstring doesn't anticipate.
