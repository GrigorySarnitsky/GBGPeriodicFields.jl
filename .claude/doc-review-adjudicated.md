# Do-not-re-flag list

Findings settled as **not defects**, or as decisions the owner has taken deliberately. `panel.js`
injects this into every hat's preamble and the two verifiers read it, so a finding recorded here is
correctly left unfixed and must not be graded `UNDONE`.

**Nothing merely FIXED belongs here.** Re-flagging a bad fix is exactly what the panel is for, so a
finding's absence from this file proves nothing about it.

---

## 2026-09-01 — escalated by the fix pass, awaiting the owner's decision

These are **real findings**, not dismissals. They are recorded so a verifier does not read them as
neglect, and each names the trade-off that stops it being a mid-pass call. They stay OPEN.

### `Grid3D`'s two-argument constructor takes `origin` as a keyword
*(software-architect 1.)* The package's own rule makes a result-affecting argument positional, and
`origin` shifts every node; the four-argument form already takes it positionally, so the two
constructors disagree. **Why not fixed here:** moving it is a breaking signature change on the most
widely used constructor in the package. It belongs with the other recorded breaking-round items
(CLAUDE.md, "Open interface questions"), not in a documentation pass.

### Nine `Internal API` entries carry no leading underscore
*(structure-consistency 1; the hat said eight, the built-HTML scan finds nine.)*
`section_scalar_type`, `section_tensor_order`, `@_assign!` (FiberSections);
`check_field_compatibility`, `rfft_shape`, `similar_physical_field`, `similar_spectral_field`,
`validate_fft_dims` (Fields); `pointvalue_shape` (Points). **Why not fixed here:** a nine-symbol
rename across `src/` and `test/` risks the frozen method-parity baselines, and some of these may be
deliberately public-shaped. It is a code change with a test-baseline refreeze, not a doc edit.

### `inv` has three different failure behaviours across the four `SpectralKernel` subtypes
*(software-architect 3.)* `StoredKernel` and `SeparableKernel` throw on a singular kernel;
`RadialKernel` returns a non-finite multiplier — and that is the class `spectral_cutoff` returns, the
case the docs themselves call the one that matters. **Why not fixed here:** the honest fix is either a
cheap analytic zero-test on `RadialKernel` or a family-wide contract stated at the supertype, and
choosing between them is an API decision. Documenting the asymmetry without deciding would be
laundering it.

### `Points` accessors use three naming conventions
*(software-architect 4.)* Already recorded in CLAUDE.md's "Open interface questions" as breaking and
unstarted. Listed here only so a verifier does not re-grade it as neglect.

### Four consumer-contingent API-symmetry observations
*(software-architect 2, 5, 6, 7, 8.)* Which operators get a kernel-composed arity, why `combine!` is
field-only, why `weighted_inner`'s tuple form has no two-field analogue, `map!`'s α/β arity, and where
Convolution's kernel-composed `combine!` is documented. Each individual absence has a recorded reason;
the finding is that collectively they track one consumer's request history rather than a rule. **Why
not fixed here:** the proposed remedy is new cross-family prose asserting a design rationale, which is
the owner's to write, not a reviewer's to infer.

### Four intrinsic-structure findings from the differential geometer
*(differential-geometer 1, 3, 10; spectral-methods-mathematician 7.)* The gradient's codomain stated
as ``T^*\Omega \otimes E`` while the frame is said to identify ``T\Omega`` with ``V``; the
interpolation adjointness display written as a nodal-grid sum and then claimed for the spectral
schemes; ``\sum_k`` meaning the full spectrum in one section and the stored half-spectrum in another.
**Why not fixed here:** each needs the statement re-derived and re-typed before rewording — the
FORMALIZATION chain is *prose ↔ typed statement ↔ test*, and editing the prose alone would break it.
The one in this family that WAS unambiguous (the first-derivative multipliers written with the true
wavenumber instead of the declared derivative one) is fixed.
