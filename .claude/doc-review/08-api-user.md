# API-user hat — findings

Reviewer stance: a computational scientist trying to use `GBGPeriodicFields` purely from
the rendered docs — build a field, transform it, differentiate, convolve, reduce,
interpolate to points — checking constructors, argument/keyword coverage, return
shapes, and drift between the tutorial/example and the API reference.

---

## Finding 1 — `mul!`'s right (tensor-on-vector) action is asserted but never shown as a signature

**Type:** api-gap
**Severity:** major
**Confidence:** high

**Locations:**
- PAGE `api / FieldAlgebra`, module docstring: "`mul!` the tensor-on-vector action **(left and right)** and the tensor-on-tensor product"
- PAGE `api / FieldAlgebra`, `mul!` docstring formula block: "$(A u)_i = A_{ij} u_j, \qquad (u A)_i = u_j A_{ji}$"
- PAGE `api / FieldAlgebra`, `mul!` docstring code block and "The arguments are" bullets: only shows
  `mul!(destination::VectorFieldPhysical, A::TensorFieldPhysical{2}, u::VectorFieldPhysical[, α, β])`
  and three sibling A-first signatures; the argument bullets read "`A` — the left operand... `u`, `B`
  — the right operand", i.e. every documented call puts the tensor first.

**Description:** The module overview and the `mul!` docstring's own formula both promise a
right-multiplication method (`u * A`, tensor acting from the right on a vector), but the
docstring's code block — the only place a signature is shown — lists nothing with a vector
field as the first field argument. A user cannot learn from this page how to invoke the
right action (e.g. `mul!(dest, u, A)` vs some other call shape), yet CLAUDE.md's own method-count
note (30 `mul!` methods vs ~10 shown) confirms the surface is larger than what's documented.

**Contradicts:** module docstring's "(left and right)" + the `(uA)_i` formula vs. the `mul!`
docstring's code block and "arguments" bullets, which document only the left-action call shape.

**resolution_hint:** Add at least one representative right-action signature (e.g.
`mul!(destination::VectorFieldPhysical, u::VectorFieldPhysical, A::TensorFieldPhysical{2}[, α, β])`)
to the code block, or clarify in prose exactly how the right action is invoked.

---

## Finding 2 — Field/point-value constructors silently reject `SubArray`-backed storage, undocumented at the point of use

**Type:** api-gap
**Severity:** major
**Confidence:** high

**Locations:**
- PAGE `api / FiberSections`, Internal API: "`_check_owned_storage` ... Reject storage that does not
  own its memory — a `SubArray` anywhere in the parent chain — so that two sections can share storage
  only by being backed by the same array."
- PAGE `architecture`, §7/decision 59: "the constructors **reject borrowed storage** — a `SubArray`
  anywhere in the parent chain".
- PAGE `api / Fields`, `ScalarFieldPhysical`/`VectorFieldPhysical`/`TensorFieldPhysical` constructor
  docstrings and PAGE `api / Points`, `PointSet`/`ScalarPointValues`/`VectorPointValues`/
  `TensorPointValues` constructor docstrings: none mention this rejection.

**Description:** A load-bearing validation rule — passing a `view`/`SubArray` (e.g. slicing a larger
preallocated buffer, a very natural thing to try) into any field or point-value constructor throws —
is documented only in the internal-API section (marked "not part of the public interface... for
contributors") and in the Architecture design document. None of the public constructor docstrings a
user actually reads before calling `ScalarFieldPhysical(view(data, :,:,:), grid)` or
`PointSet(view(coords, 1:100, :))` mention it, so the first encounter is an unexplained thrown error.

**resolution_hint:** Add a one-line note (or a `!!!` warning) to each public field/point-value
constructor docstring: storage must own its memory (no `SubArray` anywhere in its parent chain);
allocate with `similar_field`/`similar_pointvalues` or copy first.

---

## Finding 3 — Docstrings with a keyword argument inconsistently skip the corpus's own bulleted-argument convention

**Type:** format
**Severity:** minor
**Confidence:** high

**Locations:**
- PAGE `api / Interpolation`: `(field::AbstractFieldPhysical)(x; scheme = CatmullRom)` — "Evaluate
  `field` at a single off-grid position `x`... The `scheme` keyword selects the transfer scheme,
  `CatmullRom` by default." (prose, no "The arguments are:" bullets)
- PAGE `api / FiberSections`: `with_threading(f; enabled::Union{Nothing, Bool} = true)` — "Pass `true`
  or `false` to force the threaded or serial path, or `nothing` to follow..." (prose)
- PAGE `api / Interpolation`: `LalescuSpline(n, m = 1; T = Float64)` — "The `T` keyword sets the
  element type..." (prose, appended after the `n`/`m` prose)
- PAGE `api / Interpolation`: `LagrangeSpline(n; T = Float64)` — same pattern.

**Contradicts:** the same corpus's own established convention: every other docstring carrying a
keyword argument (`NUFFT(reference; tol=…, oversampling=…, width=…, beta=…)`, `Grid3D(...; origin=…)`,
`FieldTransformPlans(...; fft_flags=…, fft_timelimit=…)`, `translation_kernel!`, `map!`, `anterpolate!`)
uses the bulleted "The arguments are:" form. These four docstrings are the outliers.

**Description:** A reader skimming for "does this take a keyword, and what does it do" has to switch
reading mode for these four bindings versus the rest of the reference, which is a small but real
consistency gap — worth fixing as a class (four instances of the same pattern) rather than one at a
time.

---

## Finding 4 — Tutorial never constructs or exercises a second-order tensor field

**Type:** clarity
**Severity:** minor
**Confidence:** medium

**Locations:**
- PAGE `tutorial`: constructs only `ScalarFieldPhysical` and `VectorFieldPhysical`; the differential
  operators section demonstrates only `laplacian` on a scalar field; no `TensorFieldPhysical`/
  `TensorFieldSpectral` appears anywhere.

**Description:** The package's headline surface is "scalar, vector, and second-order tensor fields"
(Home page's first sentence), and several operators the tutorial mentions in passing (`gradient` of a
vector field, `symmetric_gradient`) *produce* a tensor field, but the walkthrough never shows building
one directly, indexing its components, or running a tensor-only operation (`tr`, `det`, `sym`/`skew`/
`dev`). A first-time reader following only the tutorial would not see a `TensorFieldPhysical`
construction pattern before needing one.

**resolution_hint:** Add one short tensor-field snippet (e.g. `gradient(u, multipliers)` then `tr`/
`det` on the result) to round out the "whole surface in miniature" claim at the tutorial's close.

---

## Finding 5 — Radial-reduction return values are typed only by inference, never stated explicitly

**Type:** clarity
**Severity:** nit
**Confidence:** low

**Locations:**
- PAGE `api / Reductions`, `radial_spectrum`: "It returns `(shells, spectrum)`, where `shells` are the
  bin-center wavenumber magnitudes $\kappa$ and `spectrum[i]` sums..."
- PAGE `api / Reductions`, `radial_correlation`: "It returns `(separations, correlation)`, where
  `separations` are the bin-center magnitudes $r$..."

**Description:** Both return descriptions establish the arrays' meaning and indexing but never state
their concrete type (e.g. `Vector{T}` on the host, or whether they can live on a GPU array) the way
constructor docstrings do for their stored fields. A user chaining the result into further code (e.g.
plotting, or feeding `shells` into another reduction) has to infer the type from context (`spectrum[i]`
indexing) rather than read it.

**resolution_hint:** State the concrete return type (and host/device residency) alongside the existing
semantic description, consistent with how every other public function's return is typed elsewhere on
the same page.
