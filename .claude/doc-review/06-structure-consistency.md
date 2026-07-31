# Documentation-Structure Consistency Audit

## Inferred template

**Function docstring** (the `f`/`f!` pair, `f!` is the "home"): (1) signature code
block; (2) one-sentence identity, often folding in the return value ("...into
`destination`, returning `destination`"); (3) when-to-use guidance versus the
sibling form/alternatives; (4) an argument-by-argument account; (5) one
physical-meaning-first display formula; (6) caveats as a `!!!` admonition where
load-bearing; (7) a representation-validity scope statement; (8) a citation at the
very end when applicable; (9) a cross-link back to the home. The allocating form is
meant to be a thin wrapper: "Allocating form of `f!`: allocate the result and
return it... See `f!` for..."

**Type docstring**: (1) constructor signature(s); (2) one-sentence identity; (3) a
"The fields are" bulleted list, one bullet per constructor argument / stored field;
(4) trailing behavioral notes; (5) `source`.

Both templates are followed closely in places (e.g. FieldAlgebra's fiberwise
formulas are uniformly led by "Pointwise over the base..."), which is what makes
the deviations below legible as deviations rather than noise.

---

## Finding 1

**Type:** organization
**Severity:** blocker
**Confidence:** high
**Locations:** PAGE: api / Reductions — `## Internal API` section, entries
`Base.extrema`, `Base.maximum`, `Base.minimum`, `Statistics.mean`, `Statistics.std`,
`Statistics.var`.
**Quote:** "These symbols are not part of the public interface" (heads the section
containing `Statistics.mean`).

**Description:** The paragraph immediately before `## Internal API` states `mean`,
`std`, `var`, `maximum`, `minimum`, `extrema` "are also defined for sections... and
are described in the module summary above" — i.e. asserts they are public. The very
next heading is "## Internal API", whose own intro claims its contents "are not
part of the public interface," and all six bindings are rendered inside it,
interleaved with genuinely internal `_`-prefixed methods. No other stdlib extension
in the corpus (`dot`, `cross`, `tr`, `det`, `norm`, `transpose`, `mul!`) is placed
under an "Internal API" heading; all get named public sections.

---

## Finding 2

**Type:** organization
**Severity:** major
**Confidence:** high
**Locations:** PAGE: api / DifferentialOperators, `gradient!` ("The arguments
are:"); PAGE: api / Convolution, `convolve!` (bare bullets); PAGE: api /
FieldAlgebra, `dot!`/`add!` (no bullets at all).
**Quote:** "The arguments are:" vs. unlensed "- `field` — the field to filter".

**Description:** Argument documentation uses at least three incompatible shapes
with no visible governing rule: a lead-in sentence "The arguments are:" plus
bullets (every DifferentialOperators operator, `combine!`); bare bullets with no
lead-in (`convolve!` and all five Convolution kernel-builders); and pure
prose with no bullets anywhere (`dot!`, `cross!`, `mul!`, `tr!`, `det!`,
`transpose!`, `sym!`/`skew!`/`dev!`, `norm!`, `add!`, `subtract!`, `multiply!`,
`divide!` — i.e. almost all of FieldAlgebra).

---

## Finding 3

**Type:** organization
**Severity:** major
**Confidence:** high
**Locations:** PAGE: api / Fields — `ScalarFieldPhysical`, `VectorFieldPhysical`,
`TensorFieldPhysical`, and their Spectral counterparts (prose); `Grid3D`,
`FieldSpectralMultipliers` (bulleted "The fields are").
**Quote:** "Here `values_at_grid` contains the real scalar values" vs. "The fields
are\n\n- `grid_size::NTuple{3, Int}`".

**Description:** All six field types document their constructor arguments in
"Here `x` contains..." running prose, with no "The fields are" section at all,
while `Grid3D` and `FieldSpectralMultipliers` use a bulleted "The fields are" list
for the identical job. `FieldTransformPlans` mixes both styles in one docstring —
prose for its constructor arguments, then a separate bulleted list for its
differently-named stored fields. A "# Fields" section is present on some types and
absent on others with no stated rule for which.

---

## Finding 4

**Type:** organization
**Severity:** major
**Confidence:** high
**Locations:** PAGE: api / FieldAlgebra, `mul!` ("Warning..."); PAGE: api /
Convolution, `convolve!` ("A real field needs a Hermitian kernel"); PAGE: api /
Fields, `to_physical!` ("The source is used as scratch").
**Quote:** "WarningAs with `LinearAlgebra.mul!`" vs. "A real field needs a
Hermitian kernelThe stored half-spectrum".

**Description:** Admonitions split into two families with no unifying rule:
generic Documenter-default titles (literally "Warning"/"Note" — `mul!`,
`inverse_laplacian!`, `helmholtz_projection!`, `NUFFT`, `integral`'s Note) versus
custom descriptive titles (`convolve!`, `exponential_convolve!`,
`translation_kernel`, `to_physical!`, `to_spectral!`, `FieldTransformPlans`,
`with_threading`). The split loosely tracks module boundaries but is never stated
as a rule, and both styles gate comparably load-bearing caveats.

---

## Finding 5

**Type:** organization
**Severity:** major
**Confidence:** high
**Locations:** PAGE: api / DifferentialOperators, `gradient!`/`divergence!`/
`curl!`/`laplacian!`/`inverse_laplacian!`/`helmholtz_projection!`; PAGE: api /
Interpolation, `interpolate!`; PAGE: api / Convolution, `combine!`.
**Quote:** "Use this in-place form when `destination` is already allocated" vs.
"This is the in-place home of the gather".

**Description:** Three different phrasings cover the same "this is the in-place
primary form; use the allocating sibling for a fresh result" idea. DifferentialOperators
uses one fixed sentence verbatim in every operator. Interpolation uses a distinct
fixed phrasing ("This is the in-place home of..."). FieldAlgebra/Convolution
`!`-operators either improvise bespoke wording (`combine!`: "Reach for `combine!`
with a preallocated destination...") or omit the guidance entirely (`convolve!`,
`exponential_convolve!`, `dot!`, `cross!`, `mul!`).

---

## Finding 6

**Type:** organization
**Severity:** major
**Confidence:** high
**Locations:** PAGE: api / FieldAlgebra, `sym`, `skew`, `dev` (wrappers) vs.
`transpose` (same section) and `gradient`/`curl`/`tr` (other sections).
**Quote:** "Allocate the result and compute the symmetric part" vs. "Allocating
form of `transpose!`: allocate the result and return".

**Description:** Every other allocating wrapper in the corpus opens "Allocating
form of `f!`: allocate the result and return...". `sym`, `skew`, and `dev` instead
open "Allocate the result and compute the X part of...", a distinct template used
nowhere else — including by their own section-mate `transpose`, which follows the
standard phrasing. This is exactly the f/f!-pair-organized-differently case: three
wrappers in one section break from both the corpus norm and their nearest
neighbor.

---

## Finding 7

**Type:** organization
**Severity:** moderate
**Confidence:** high
**Locations:** PAGE: api / Convolution, `convolve!` (formula before args) vs.
`exponential_convolve!`/`combine!` (formula after args); PAGE: api /
DifferentialOperators, all operators (formula after args).
**Quote:** "As a real physical object the periodic convolution is..." (precedes
the bullets) vs. "...for the field's grid.Each output component is" (follows
them).

**Description:** `convolve!` places both its physical- and spectral-form
formulas immediately after the identity sentence, before the argument bullets.
Its own module siblings `exponential_convolve!` and `combine!` place the formula
after the argument list instead (appended to the trailing prose), matching the
DifferentialOperators family's uniform placement. `convolve!` is the outlier
against both its closest siblings and the wider corpus.

---

## Finding 8

**Type:** organization
**Severity:** moderate
**Confidence:** high
**Locations:** PAGE: api / DifferentialOperators, `gradient!` (folded); PAGE: api
/ Convolution, `convolve!` (trailing); PAGE: api / Fields, `write_field`
(trailing).
**Quote:** "...returning `destination`." vs. "Returns the modified
`destination`."

**Description:** Return-value documentation is either folded into the opening
sentence (DifferentialOperators, most of FieldAlgebra: "...write it into
`destination`, returning `destination`") or split into a separate trailing
sentence at the very end (`convolve!`, `exponential_convolve!`, `write_field`,
`read_field`, `set_fft_threads!`). No rule distinguishes which docstrings get
which placement.

---

## Finding 9

**Type:** organization
**Severity:** moderate
**Confidence:** high
**Locations:** PAGE: api / Reductions, `weighted_inner` (bulleted) vs. `integral`,
`inner`, `l2norm`, `lpnorm`, `radial_spectrum`, `radial_correlation` (all prose).
**Quote:** "The arguments are:\n\n- `f`, `g` — two compatible, equal-order
fields".

**Description:** Within Reductions, `weighted_inner` is the sole function using a
bulleted "The arguments are:" list. Its six module-mates all describe their
arguments in running prose with no bullets anywhere. This is a clean single-outlier
case inside an otherwise internally uniform family.

---

## Finding 10

**Type:** organization
**Severity:** moderate
**Confidence:** medium
**Locations:** PAGE: api / FieldAlgebra, `dot` and `cross` (wrappers) vs.
`gradient`/`curl`/`tr` (other modules' wrappers).
**Quote:** "Two fields contract only in physical-space representation; with a
constant fiber..." (restated in the wrapper).

**Description:** `dot` and `cross` restate their entire representation-validity
paragraph (physical-only for two fields, coefficient-wise for a constant fiber) in
addition to linking `dot!`/`cross!`. Comparable wrappers elsewhere (`gradient`,
`curl`, `tr`, `laplacian`) link back in one short sentence without re-deriving the
validity discussion, keeping closer to the thin-wrapper template.

---

## Finding 11

**Type:** organization
**Severity:** moderate
**Confidence:** medium
**Locations:** PAGE: api / Interpolation — `## Transfer-scheme types`: `NUFFT`
("The options:" bullets) vs. `LalescuSpline`/`LagrangeSpline` (inline prose).
**Quote:** "The options:\n\n- `tol` — the target accuracy" vs. "$n \ge 0$, the
first argument — the finite-difference half-width".

**Description:** Within the same "Transfer-scheme types" section, `NUFFT`
documents its keyword options (`tol`, `oversampling`, `width`, `beta`) as a
bulleted list, while `LalescuSpline` and `LagrangeSpline` — equally parameterized
scheme constructors in the same section — embed their parameter meanings inline
within flowing mathematical narrative, never as bullets.

---

## Finding 12

**Type:** organization
**Severity:** moderate
**Confidence:** medium
**Locations:** PAGE: api / Interpolation — module docstring, embedded "API" and
"References" sub-headers.
**Quote:** "...live in the `Points` module.\nAPI\n\n- Interpolation (grid →
point...".

**Description:** The Interpolation module docstring is the only one in the corpus
that embeds its own internal "API" and "References" labeled sub-structure inside
the module-level docstring body. No sibling module docstring (Convolution,
DifferentialOperators, FieldAlgebra, Fields, FiberSections, Points, Reductions) has
either — references, where present at all, live on individual function
docstrings, and none label a bare "API" block.

---

## Finding 13

**Type:** organization
**Severity:** moderate
**Confidence:** medium
**Locations:** PAGE: api / FieldAlgebra (bullets = header names) vs. PAGE: api /
DifferentialOperators and PAGE: api / Convolution (bullets ≠ header names) vs.
PAGE: api / Points (a promised family with no matching section).
**Quote:** "Vector-space and module operations — `add!` and `subtract!`" (bullet
text = the later `##` header, verbatim).

**Description:** FieldAlgebra's module-docstring bullets are verbatim the page's
later section headers. DifferentialOperators' and Convolution's module-docstring
bullets instead name individual operations, and the actual page introduces new
group headers ("First-order differential operators", "Kernel-multiplier
builders") never mentioned in the module docstring. Points promises "a full
fiberwise algebra" as one bulleted family, but the Points API page has no section
for it at all.

---

## Finding 14

**Type:** organization
**Severity:** minor
**Confidence:** medium
**Locations:** PAGE: api / Points — `ScalarPointValues`/`VectorPointValues`/
`TensorPointValues` vs. PAGE: api / Fields — the six field types.
**Quote:** "Scalar field values sampled at `M` points, stored in `data` with
shape `(M,)`." (the entire docstring).

**Description:** The point-value types are documented in a single terse sentence
with no "Here `x` is..." explanatory prose at all, a third and sparser tier of
type-doc depth alongside Grid3D's bulleted-fields tier and the six field types'
prose-paragraph tier — three distinct depths for structurally analogous
"data-holder with a shape" types.

---

## Finding 15

**Type:** organization
**Severity:** minor
**Confidence:** medium
**Locations:** PAGE: api / Interpolation, `anterpolate!`.
**Quote:** "- `α` scales the deposited contribution.\n- `β` sets the
accumulation".

**Description:** `anterpolate!` is the only docstring in the corpus that mixes
argument-documentation styles within itself: `field`, `points`, `quantities`, and
`scheme` are explained in prose, while `α` and `β` alone are then pulled into a
bulleted list with no lead-in sentence. Every other docstring elsewhere is either
all-prose or all-bulleted for its own argument set.

---

## Finding 16

**Type:** organization
**Severity:** minor
**Confidence:** medium
**Locations:** PAGE: api / FieldAlgebra, `tr` vs. `det` (same "Contraction and
product operations" section).
**Quote:** "the fiberwise determinant — the third principal invariant $I_3$" vs.
"return the fiberwise trace of a second-order tensor field."

**Description:** `det`'s wrapper restates the identifying fact "the third
principal invariant $I_3$" from its `!` home. `tr`'s wrapper, in the same section
and the same pairing pattern, does not restate the parallel fact ("the first
tensor invariant") that `tr!` gives it. The two closest-possible sibling wrappers
leak a different amount of home content.

---

## Finding 17

**Type:** organization
**Severity:** minor
**Confidence:** medium
**Locations:** PAGE: api / FieldAlgebra, PAGE: api / DifferentialOperators, PAGE:
api / Interpolation (no disclaimer) vs. PAGE: api / Fields, FiberSections,
Convolution, Points, Reductions (disclaimer present).
**Quote:** "These symbols are not part of the public interface; they are
documented for contributors —".

**Description:** Five of eight modules open their "## Internal API" section with
this (near-)verbatim disclaimer sentence. FieldAlgebra, DifferentialOperators, and
Interpolation instead open with a shorter description of the contents and skip the
disclaimer entirely. A fixed boilerplate opener is used by most but not all
Internal API sections.

---

## Finding 18

**Type:** organization
**Severity:** minor
**Confidence:** medium
**Locations:** PAGE: api / DifferentialOperators, `divergence!`/
`helmholtz_projection!`; PAGE: api / Convolution, `combine!` ("The kernel-composed
form" subheading) vs. `exponential_convolve!` (no subheading).
**Quote:** "The kernel-composed form\nPassing a `kernel` composes..." vs. "...the
two-operand forms apply the same kernel to the combination".

**Description:** Three operations that fuse a second mechanism into one pass each
get an explicit demoted subheading, "The kernel-composed form". `exponential_convolve!`
has an equivalent fused two-operand mechanism (documented as the "lazy-kernel twin
of the kernel-composed `combine!` method") but it is folded into running prose with
no comparable subheading of its own.

---

## Finding 19

**Type:** organization
**Severity:** nit
**Confidence:** medium
**Locations:** PAGE: api / GBGPeriodicFields (umbrella) vs. every submodule page.
**Quote:** "Represent, transform, and manipulate real-valued scalar, vector, and
second-order-tensor fields".

**Description:** The umbrella module's docstring opens with an imperative verb
phrase. Every one of its eight submodules opens with a descriptive noun phrase
instead (e.g. "Fiberwise and pointwise algebra for...", "Spectral differential
operators on...", "Periodic (circular) convolution of..."). The umbrella is the
one docstring in the corpus using the imperative-mood opener.

---

## Finding 20

**Type:** organization
**Severity:** nit
**Confidence:** medium
**Locations:** PAGE: api / Fields ("This module provides the following."); PAGE:
api / Points ("This module provides three things."); PAGE: api /
DifferentialOperators ("The operation families are:"); PAGE: api / FieldAlgebra
("The families are:"); PAGE: api / Reductions ("Each family links to the home
where its formula lives:").
**Quote:** "This module provides the following." vs. "The families are:".

**Description:** The sentence introducing a module docstring's bulleted
operation-family list is phrased differently in nearly every module, with no
shared template — five distinct wordings across seven modules for what is
structurally the same slot.
