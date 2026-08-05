# Hat: Computational Scientist / API User

Reviewed the full rendered-docs consolidation (Home, api overview, architecture, formalization,
notation, performance, testing, tutorial, all eight module API pages, and the HIST_CPU example) as a
user trying to build a field, transform it, differentiate, convolve, reduce, and transfer to/from
points using only the docs. Six findings, most-severe first.

---

## Finding 1 — `interpolate!`'s own tensor-order restriction contradicts the umbrella page's claim that the local-spline transfer serves higher orders

- **Type:** contradiction
- **Severity:** major
- **Confidence:** high

**Locations:**
- PAGE: `api / GBGPeriodicFields`, module docstring: *"The field and point-value types are parameterized on `R`, so higher orders can be constructed and several layers serve them (storage, HDF5 persistence, the vector-space operations, `inner`, `l2norm`, and **the local-spline transfer**)."*
- PAGE: `api / Interpolation`, `interpolate!` — arguments list: *"`out` — the point-value section written with the gathered values. It must match `field` in tensor order (**scalar, vector, or second-order tensor**) and cover the same number of points as `points`."*

**Contradicts:** The umbrella page explicitly names "the local-spline transfer" as one of the layers
that serves tensor orders above `R = 2` (alongside storage, HDF5, the vector-space ops, `inner`,
`l2norm`). But `interpolate!`'s own argument documentation caps `out`/`field` at "scalar, vector, or
second-order tensor" — i.e. `R ≤ 2` — with no mention of `R ≥ 3` support. A reader relying on the
umbrella page's capability claim to interpolate a third-order tensor field would be misled by the very
function's own docstring, which reads as an explicit ceiling. Only one of the two can be correct as
written; neither qualifies the other (no "unlike the field-value operations, transfer permits R≥3" or
converse caveat appears on either page).

**Resolution hint:** Either extend `interpolate!`'s argument prose to state its actual supported tensor
orders (if it does serve `R ≥ 3`), or drop "the local-spline transfer" from the umbrella page's
higher-order-support list (if `interpolate!` really is capped at `R = 2`).

---

## Finding 2 — `LalescuSpline`'s default smoothness `m = 1` violates its own documented bound `0 ≤ m ≤ 2n` at `n = 0`

- **Type:** contradiction
- **Severity:** major
- **Confidence:** high

**Locations:**
- PAGE: `api / Interpolation`, `LalescuSpline` signature: *"`LalescuSpline(n, m = 1; T = Float64)`"*
- Same docstring, a few lines later: *"The second argument `m` sets the smoothness, $C^m$ with
  $0 \le m \le 2n$"* — and separately, the stencil is valid for *"$n \ge 0$"* (the half-width, first
  argument).

**Contradicts:** For `n = 0` — an explicitly permitted value (`n ≥ 0`) — the documented bound forces
`m = 0` (`2n = 0`), but the constructor's own default is `m = 1`. Calling `LalescuSpline(0)` therefore
invokes a default that the docstring's own inequality says is invalid, and nothing on the page states
what happens (throw? silently wrong stencil?) when `m` exceeds `2n`. A user reading only the signature
line would reasonably expect `LalescuSpline(0)` to be a legal, documented call.

**Resolution hint:** State the constructor's behavior on an out-of-range `(n, m)` pair (validated throw,
or clamp), or make the default n-dependent / require `m` explicitly when `n = 0`.

---

## Finding 3 — the `scheme` argument is positional everywhere except the callable field-evaluation sugar, where it is a keyword

- **Type:** api-gap
- **Severity:** major
- **Confidence:** high

**Locations:**
- PAGE: `api / Interpolation`, `interpolate!`: *"`interpolate!(out::AbstractPointValues,
  field::AbstractFieldPhysical, points::PointSet, scheme::AbstractSplineScheme = CatmullRom)`"* — positional.
- Same page, `interpolate`: *"`interpolate(field::AbstractFieldPhysical, points, scheme = CatmullRom)`"* — positional.
- Same page, `anterpolate!`/`anterpolate`: `scheme::AbstractSplineScheme = CatmullRom` as the 4th
  positional argument, both signatures.
- Same page, the callable: *"`(field::AbstractFieldPhysical)(x; scheme = CatmullRom)`"* — **keyword**.

**Contradicts:** The identical logical parameter (which `AbstractTransferScheme` to use) is spelled as
a positional argument with a default in `interpolate`, `interpolate!`, `anterpolate`, and `anterpolate!`,
but as a keyword argument in the one-point callable `f(x; scheme = ...)`. A user who has learned
`interpolate(u, points, LagrangeSpline(2))` and tries the natural extension `u(x, LagrangeSpline(2))`
on the callable form will get a `MethodError` — the callable requires `u(x; scheme = LagrangeSpline(2))`.
Nothing on the page flags this asymmetry.

**Resolution hint:** Either make `scheme` a keyword throughout the transfer-operation family, or note
explicitly on the callable's docstring that it deliberately diverges from the positional convention used
elsewhere in the module.

---

## Finding 4 — the Home and api-overview one-liners for `Reductions` omit that `inner`/`l2norm`/`integral`/`mean`/`std`/`var` also act on fields in spectral representation

- **Type:** clarity
- **Severity:** major
- **Confidence:** high

**Locations:**
- PAGE: `Home`, "Main components" bullet for `Reductions`: *"...the normalized, intensive `inner`,
  `l2norm`, `lpnorm`, and the moments `mean`, the scalar-only `std`/`var` and the covariance tensor
  `cov`... **each integrating the base away against its measure**, plus the measure-independent
  `maximum`/`minimum`/`extrema`..."* — no mention of spectral-representation support anywhere in the bullet.
- PAGE: `api`, overview bullet for `Reductions`: *"base reductions (`integral`, `inner`,
  `weighted_inner`, `l2norm`, `lpnorm`, `mean`/`std`/`var`/`cov`, `minimum`/`extrema`, `maximum`) over
  fields and point-values..."* — likewise silent on representation.
- PAGE: `api / Reductions`, the module's own docstring: *"Several also act on fields in **spectral
  representation**, returning the identical physical value with no inverse transform: `inner`/`l2norm`
  by Parseval's theorem, `integral`/`mean` from the zero (DC) Fourier mode, and the scalar-only
  `std`/`var` from Parseval."*

**Contradicts:** Both top-level "map" pages describe the whole `Reductions` family as acting on "fields
and point-values" without qualification, giving no hint that five of these operations are *also*
usable directly on a field in spectral representation (a capability the HIST example relies on
constantly, e.g. `inner(uh, uh)` and `radial_spectrum(uh, m)` called on the spectral velocity `uh`
without ever transforming it back). A reader who only skims the module map — which is exactly the
document's stated purpose ("a module docstring is a map") — would reasonably conclude `Reductions` is
physical-representation-only, missing one of its most useful, allocation-free properties.

**Resolution hint:** Add a clause to both overview bullets noting that `inner`/`l2norm`/`integral`/`mean`
(and the scalar `std`/`var`) also read directly from spectral representation via Parseval / the DC mode.

---

## Finding 5 — the tutorial's "Points: interpolation and anterpolation" section names and describes `anterpolate` but never demonstrates it

- **Type:** clarity
- **Severity:** minor
- **Confidence:** high

**Locations:**
- PAGE: `tutorial`, section header and lead sentence: *"## Points: interpolation and anterpolation... `interpolate` gathers a field to the points; `anterpolate` is its adjoint, scattering per-point quantities back onto the grid."*
- Same section's only code block demonstrates `PointSet`, `npoints`, and `interpolate` — no
  `anterpolate`/`anterpolate!` call appears anywhere in the tutorial.
- Closing summary line: *"That is the whole surface in miniature: build a field, move between
  representations, apply operators / convolutions, reduce it, and **transfer to and from points**."*

**Description:** The section prose and the tutorial's own closing claim ("transfer to and from points")
promise both directions of the grid↔point adjoint pair, but only the grid→point gather is shown as a
doctest. For a "Getting started" page whose explicit goal is to be a complete miniature of the surface,
omitting the one-liner `anterpolate` call (even a trivial scatter of the just-gathered `sampled` values)
leaves the "and from points" half of the closing sentence undemonstrated.

**Resolution hint:** Add a short `anterpolate`/`anterpolate!` doctest to the section, or soften the
closing sentence to "transfer to points" if only the gather direction is meant to be shown.

---

## Finding 6 — several docstrings run an admonition's title text directly into the following paragraph with no separating space

- **Type:** typesetting
- **Severity:** minor
- **Confidence:** medium

**Locations:**
- PAGE: `api / Convolution`, `convolve!`: *"...Two kernels compose through the allocating form, which
  allocates nothing**This** operation applies a kernel to a field."*
- Same page, `convolve!`, reality-condition warning: *"A real field needs a Hermitian kernel**The**
  stored half-spectrum holds only the modes with a non-negative wavenumber..."*
- Same page, `exponential_convolve!`: *"The offset must be real-valued**The** exponential of a real,
  even multiplier keeps a real field real."*
- PAGE: `Home`, "Main components" bullet for `Reductions`: *"...refining the mixed `inner(f, g)`).**Pointwise** (fiberwise) products and norms live in `FieldAlgebra`;..."*

**Description:** In each case what reads in isolation as a `!!!`-style admonition title ("Two kernels
compose through the allocating form, which allocates nothing", "A real field needs a Hermitian kernel",
"The offset must be real-valued") is concatenated directly onto the start of the next sentence with no
space or line break, producing a run-on that is momentarily unparseable on a first read — and two of the
three are load-bearing correctness warnings (the Hermitian-kernel reality condition and the
real-valued-offset requirement) rather than incidental prose. This may be an artifact of how this
review's plain-text consolidation extracted the rendered admonition boxes rather than a defect in the
live HTML site; flagged at medium confidence for that reason, but the pattern recurs identically at
least four times across two different pages, which is more consistent with a systematic markdown
source issue (a missing blank line after an admonition title line) than a one-off.

**Resolution hint:** Verify against the live rendered site; if the admonition boxes there also lack a
visible break before the following paragraph, insert a blank line after each `!!!` title in the source.
