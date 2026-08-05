# Software Architect — rendered-docs review

Hat: software-architect. Scope: documented design (API pages + the four design docs), judged as a Julia
expert would read it — signatures, module decomposition, invariant discipline, decision-log coherence.

---

## Finding 1 — Invariant 1 is defined as a representation-validity rule, then invoked to justify a
purely consumer-availability absence

**Type:** contradiction **Severity:** major **Confidence:** medium

**Locations:**
- PAGE: architecture, "The invariants": *"The public method set is the spec. Deliberate absences encode
  representation validity — there is no field-times-field multiplication in spectral representation...
  Operations linear in the field exist in both representations; nonlinear ones are physical-space only.
  A missing combination is never added for completeness."*
- PAGE: architecture, decision log ("The one-pass Helmholtz kernel..."): *"The `curl!` operator
  deliberately does not get the kernel arity: IT's curls feed transforms directly, so there is no
  consumer — the absence is the invariant-1 discipline, recorded here."*

**Contradicts:** Invariant 1, as stated, is specifically about mathematical/representation validity
(linear-vs-nonlinear). The `curl!` kernel-arity absence has nothing to do with representation validity
— `curl!` is exactly as linear-and-composable-with-a-kernel as `divergence!`/`helmholtz_projection!`,
which *did* get the kernel arity. The real reason given is "no consumer," which is the package's
separate §2 "no speculative structure" policy, not invariant 1.

**Description:** Labelling a pure YAGNI/no-consumer absence as "invariant-1 discipline" blurs the one
distinction invariant 1 exists to preserve: that a missing method is a *mathematical* statement a user
can trust, not an artefact of which downstream package happened to ask first. A future contributor
reading only invariant 1 could reasonably conclude `curl!(dest, f, m, kernel)` is invalid in the way
`*` on two spectral fields is invalid, when it is merely unbuilt. This is the one place in an otherwise
very careful decision log where the two absence-policies (validity vs. no-consumer) are conflated under
one label.

**Resolution hint:** Rephrase the `curl!` entry to cite the §2 no-speculative-structure rule instead of
"invariant-1 discipline," or extend invariant 1's own wording to explicitly cover deliberate
no-consumer gaps as a second, named class of absence.

---

## Finding 2 — `combine!`'s α/β pair carries a different contract than the package-wide α/β
convention, which the package elsewhere calls the "glyph-collision" failure mode

**Type:** contradiction **Severity:** major **Confidence:** high

**Locations:**
- PAGE: architecture, "The invariants": *"The α/β convention. A five-argument form converts both
  weights to the field's scalar type and branches on β = 0 (overwrite) versus β ≠ 0 (accumulate)."*
- PAGE: api / FieldAlgebra, `combine!`: *"Here α and β weight the two inputs, not the destination ...
  This operation is the exception the name announces: it is the weighted combination, so its α and β
  sit between the operands they weight and there is no accumulate form."*
- PAGE: architecture, decision log (the lazy-kernel pair, decision 33): *"...which is why it carries no
  second trailing accumulate pair — two α/β roles in one signature is the glyph-collision failure
  mode."*

**Contradicts:** Decision 33 explicitly names "two α/β roles in one signature" as a failure mode to be
avoided by design (hence no second accumulate pair on the kernel-composed `combine!`). But `combine!`'s
*own* base signature already commits the same act at the package scale: every other `α`, `β` pair in
the public surface means "scale the result, then accumulate onto the destination"; `combine!`'s means
"weight operand `a`, weight operand `b`," a structurally different role reusing the identical glyphs.

**Description:** The docstring is self-aware and warns the reader inline ("the exception the name
announces"), which mitigates real-world confusion, but it does not resolve the deeper tension: the
package treats "one glyph pair, two roles" as the specific bug class decision 33 was written to avoid,
yet tolerates it as the founding signature of `combine!` itself, discoverable only by reading the
warning box rather than by the type system or the naming.

**Resolution hint:** Either rename `combine!`'s weights (the same instinct that led BLAS `axpy!` vs.
`gemm!` to keep `alpha`/`beta` roles consistent across a whole library) or fold the "glyph-collision"
language into a single stated rule that explicitly carves out `combine!` as the one place both roles
legitimately reuse the glyph.

---

## Finding 3 — `mean`/`var`/`std`/`cov` are documented alongside the rest of `Reductions` with no
warning that, unlike everything else in the umbrella export list, they are not re-exported

**Type:** api-gap **Severity:** major **Confidence:** high

**Locations:**
- PAGE: architecture, decision 49: *"The new `cov` (extending `Statistics.cov`, not re-exported, like
  `mean`/`var`/`std`) returns the symmetric covariance..."*
- PAGE: Home, "Main components": *"`Reductions`: the L²/measure structure — base reductions over fields
  and point-values — the extensive `integral` ... and the moments `mean`, the scalar-only `std`/`var`
  and the covariance tensor `cov` ..."* (no re-export caveat given here, or on the API-overview or
  Reductions API pages, where the same four names are listed beside `integral`/`inner`/`maximum` with
  no distinguishing mark).

**Description:** Per decision 49, `mean`, `var`, `std`, and `cov` are extended from `Statistics` but
deliberately not re-exported by the umbrella module. In Julia this means a user who follows every other
piece of onboarding advice in the docs (`using GBGPeriodicFields`) cannot call `mean(field)` unqualified
— the *name* `mean` is not in their namespace until they *also* `using Statistics`. `maximum`/`minimum`/
`extrema` do not have this problem (they extend `Base`, always in scope), so the four moment reductions
are quietly less accessible than the rest of the same family, and nothing on the Home, API-overview, or
Reductions pages — where they are presented as ordinary members of one coherent operation family —
flags the asymmetry. The Getting-started tutorial never calls `mean`/`var`/`cov`, so a reader has no
occasion to discover the gap by example either.

**Resolution hint:** Either re-export the four for parity with the rest of the family, or add one
sentence to the Reductions module docstring and the tutorial noting that `using Statistics` is required
to call them unqualified.

---

## Finding 4 — `anterpolate`'s allocating form takes a structurally different leading argument
depending on the scheme family, despite the module's claim of one uniform contract

**Type:** design **Severity:** minor **Confidence:** medium

**Locations:**
- PAGE: api / Interpolation, `anterpolate`: `anterpolate(grid::Grid3D, points, quantities, scheme =
  CatmullRom)` vs. `anterpolate(reference::AbstractFieldSpectral, points, quantities,
  scheme::DirectDFT)` / `scheme::NUFFT`.
- PAGE: api / Interpolation, `AbstractTransferScheme`: *"Same verbs, one adjointness contract; the
  schemes differ only in (kernel, representation)."*

**Description:** For the spline family the allocating `anterpolate`'s first argument is a bare
`Grid3D`; for the spectral families it is a whole `AbstractFieldSpectral` (needed to fix layout,
backend and eltype for the freshly allocated spectral destination). The module explicitly advertises
"same verbs, one adjointness contract," but a caller cannot write scheme-polymorphic code around
`anterpolate` without already knowing which scheme family they hold, because the leading positional
argument's *conceptual role* — not just its type — changes. `interpolate`/`interpolate!` do not have
this asymmetry (both families take a `field`), so the inconsistency is specific to the allocating
`anterpolate`.

**Resolution hint:** Either give the spline family a `reference`-style allocating entry point too (a
physical-space reference field, mirroring the spectral case), or document the leading-argument
divergence explicitly next to the "one adjointness contract" claim so it reads as a stated exception
rather than an implicit one.

---

## Finding 5 — The Points module's absence of `combine!` is justified circularly, undercutting the
module's own "mirrors the field surface" claim

**Type:** clarity **Severity:** minor **Confidence:** medium

**Locations:**
- PAGE: api / Points: *"The point values carry the same fiberwise algebra as fields in physical
  representation, through the very same generics ... `map!`/`map` — see `FieldAlgebra` for each
  operation, documented once there. ... (`combine!` is deliberately absent: the weighted combination is
  a field operation, and the point layer has no method for it.)"*

**Description:** Every other named absence in the package is backed by a stated *reason* — nonlinearity
(physical-only), representation invalidity, or (per Finding 1) no consumer. Here the justification is
"the weighted combination is a field operation" immediately followed by "the point layer has no method
for it" — which restates the absence rather than explaining it. `combine!` is linear and coefficientwise
exactly like `add!`, which *is* mirrored onto point-values; nothing about the point base makes an axpby
combination less well-defined than addition. As written, the entry reads as an arbitrary scope cut
dressed as a principled one, in a document that otherwise insists every absence be a deliberate,
justified statement (invariant 1).

**Resolution hint:** Either add the actual reason (e.g., "no consumer has needed it yet, unlike `add!`")
or lift the restriction, since nothing in the surrounding text suggests a mathematical obstacle.

---

## Finding 6 — The package's central "the method set is the spec" enforcement mechanism was itself an
under-enumerated hand-written list for an extended period, mirroring the exact anti-pattern the decision
log elsewhere warns against

**Type:** design **Severity:** minor **Confidence:** high

**Locations:**
- PAGE: architecture, decision 53: *"The parity baseline is the sharpest case, because it is the one
  that claims to enforce invariant 1: it counts 28 enumerated generic names filtered to two modules, so
  decisions 48, 49 and 51 each added public surface — `map!`/`map`, `cov`, the kernel builders — and
  neither the 206 nor the 122 moved."*
- PAGE: architecture, "The invariants": *"The public method set is the spec."*

**Description:** Invariant 1's entire enforceability rests on the parity baseline in
`test/method_parity.jl`. Decision 53 reveals that this baseline was itself a hand-enumerated list of 28
generic names and was silently blind to at least three rounds of new public surface before a derived,
code-driven baseline was added. This is presented candidly and is now fixed, but it is worth recording
as an architecture observation: the mechanism meant to keep the *spec* honest was, for a nontrivial
span of the package's history, exactly the kind of "hand-maintained list that drifts" pattern the
project explicitly diagnoses (and fixes) in half a dozen *other* places (the ledgers, the JET call list,
the oracle registry). The self-referential correctness tool needed the same medicine as the code it
polices.

**Resolution hint:** None needed — already fixed by decision 53. Recorded for completeness of the
review, since the finding is about design history rather than current defect.

---

## Finding 7 — Every kernel builder requires two arguments (`reference` and `multipliers`) that carry
overlapping grid/layout metadata, needing a cross-check at every call site

**Type:** design **Severity:** minor **Confidence:** medium

**Locations:**
- PAGE: api / Convolution, `spectral_cutoff`: `spectral_cutoff(reference::AbstractFieldSpectral,
  multipliers::FieldSpectralMultipliers, wavenumber_cutoff)`.
- Same two-argument pattern recurs in `spectral_band`, `radial_kernel`, `assignment_window`,
  `translation_kernel` — each documented as *"`multipliers` — the wavenumber arrays for that grid,
  checked against `reference`."*

**Description:** `reference` exists purely to fix grid, layout, element type and array backend for the
kernel object being built — its actual field data plays no role in the computation. `multipliers`
independently carries the grid and layout too (it is built from a field's grid). Every kernel-builder
call therefore hands the package two objects whose grid/layout must agree, verified at runtime rather
than expressed once. This is a recurring, package-wide instance of the same overlapping-metadata pattern
rather than an isolated slip, so it reads as a design choice (avoid introducing a new lightweight
"field signature" type) rather than an oversight — but it is a real, repeated ergonomic and
type-safety cost: a caller must keep a real field object alive solely as a type witness for every kernel
they build.

**Resolution hint:** A lightweight `FieldSignature`/`FieldSpec` object (grid + layout + eltype +
backend, no data) could replace `reference` across the whole builder family, or `FieldSpectralMultipliers`
could be extended to self-report eltype/backend so `reference` becomes unnecessary.

---

## Finding 8 — The `scheme` parameter's calling convention (positional-with-default vs. keyword) is
inconsistent between the transfer verbs and the single-point callable syntax

**Type:** format **Severity:** nit **Confidence:** high

**Locations:**
- PAGE: api / Interpolation, `interpolate!`: `interpolate!(out::AbstractPointValues,
  field::AbstractFieldPhysical, points::PointSet, scheme::AbstractSplineScheme = CatmullRom)` —
  positional with a default.
- PAGE: api / Interpolation, `(field::AbstractFieldPhysical)(x; scheme = CatmullRom)` — the same
  conceptual parameter, keyword-only, on the ergonomic single-point callable.

**Description:** `scheme` selects the same thing (the transfer kernel/representation) in both call
forms, but one exposes it positionally and the other only as a keyword. Minor, but it is exactly the
kind of small surface inconsistency a user notices when trying to write one helper that forwards a
scheme choice to either form.

**Resolution hint:** Make the callable's `scheme` positional-with-default too, or note the deliberate
difference (ergonomic call sites keep options as keywords) explicitly.

---

## Finding 9 — The `SpectralKernel` abstraction went through two structural rewrites within days,
suggesting the field-vs-kernel role distinction was under-specified when the type was first introduced

**Type:** design **Severity:** minor **Confidence:** medium

**Locations:**
- PAGE: architecture, decision 56 (2026-07-30): *"`StoredKernel` — the kernel role, made explicit where
  it matters ... A `ScalarFieldSpectral` serves two roles... That doubling is what the `SpectralKernel`
  union exists to express..."*
- PAGE: architecture, decision 60 (2026-08-03): *"A field in spectral representation is not a kernel...
  Three things were wrong with that [the union]. ... The union is gone."*

**Description:** Four days apart, the same core, heavily-relied-upon abstraction (every convolution,
`weighted_inner`, and kernel-composed operator dispatches on it) was redesigned twice: first patched
with a marker type layered onto a `Union`, then rebuilt as a proper abstract-type hierarchy once the
marker patch proved insufficient (the `kernel isa AbstractSpectralKernel` guard silently mis-routed the
newly-marked stored class off the fused pass, caught only by the pass-audit ledger). This is not a
correctness problem today — both fixes are well-tested and the final design is sound — but as a design
history it shows the field/kernel role ambiguity, and the four-class hierarchy it eventually needed, was
foreseeable earlier than it was designed for: the four concrete classes (`StoredKernel`,
`SeparableKernel`, `RadialKernel`, `ProductKernel`) already existed by decision 51, one week before
decision 60 finally gave them a proper common supertype.

**Resolution hint:** None needed going forward; noted as a case where "no speculative structure" (build
only what a consumer needs) traded off against a cheap bit of foresight that would have avoided two
successive breaking internal reshuffles of a widely-dispatched-on type.

---

## Finding 10 — Tensor order 0/1 get bespoke type names while order ≥2 collapses to a single
parameterized family, an asymmetry a newcomer must memorize as an exception rather than infer

**Type:** design **Severity:** nit **Confidence:** high

**Locations:**
- PAGE: api / Fields: `ScalarFieldPhysical(...)`, `VectorFieldPhysical(...)` (bespoke names, R = 0, 1)
  vs. `TensorFieldPhysical{R}(...)` (generic name, parameterized on `R`, for R ≥ 2) — and the same split
  mirrored in `Points` (`ScalarPointValues`, `VectorPointValues`, `TensorPointValues{R}`).

**Description:** This is a common and defensible physics-library convention (scalar/vector are the
overwhelmingly common cases and deserve short names), so it is recorded as a nit rather than a real
defect. It is nonetheless a naming discontinuity in an otherwise highly regular, generator-driven type
family: `R` is a first-class type parameter everywhere else in the design (the `AbstractFiberSection{T,
R}` supertype, `fiber_shape(Val(R))`, the whole codegen layer), yet the two lowest values of that same
parameter get their own concrete type names instead of being `TensorFieldPhysical{0}`/`{1}` aliases (or
`TensorFieldPhysical{R}` being named `ScalarFieldPhysical`/`VectorFieldPhysical`/... uniformly). A reader
who has internalized "the fiber is indexed by `R`" from the Architecture page's §2 must then learn that
the field *type name* does not follow that indexing below `R = 2`.

**Resolution hint:** None required; consider a one-line note in the Fields module docstring stating the
naming break explicitly, since it is currently left to be inferred from seeing all the constructors side
by side.
