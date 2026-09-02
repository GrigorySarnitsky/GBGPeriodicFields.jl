# Do-not-re-flag list

Findings settled as **not defects**, or as decisions the owner has taken deliberately. `panel.js`
injects this into every hat's preamble and the two verifiers read it, so a finding recorded here is
correctly left unfixed and must not be graded `UNDONE`.

**Nothing merely FIXED belongs here.** Re-flagging a bad fix is exactly what the panel is for, so a
finding's absence from this file proves nothing about it.

---

## 2026-09-01 — substrate artifacts (a finding the hat's own manuscript could not disprove)

### ``N_B`` is introduced in the notation glossary but never exercised
**NOT a defect — do not re-flag.** ``N_B`` (the base point count, ``N`` for a grid and ``M`` for a
point set) is defined on the notation page and **is** used: `docs/FORMALIZATION.md` carries it four
times in the Bessel-corrected `var` and `cov` statements, with its own binding beside them.

The finding is correct within its substrate and wrong about the corpus. The `cold-reader` hat runs on
**SITEONLY**, which withholds the four design docs by design, so the one page that exercises the symbol
was not in front of it. Its narrower phrasing — "no *docstring* uses it" — is literally true and is not
a defect either: the glossary serves the whole rendered site, and a symbol used in `FORMALIZATION` is
exercised.

This will recur on every SITEONLY round unless recorded, which is why it is here rather than merely
dismissed in a verdict file. A future panel re-raising it should close against this note.

Settles, verbatim: `N_B` introduced in the notation glossary but never exercised in any docstring

## 2026-09-02 — settled by measurement

### `AbstractField` is a `Union` rather than an abstract type
**SETTLED 2026-09-02 (user): NOT a defect — leave it as is, do not re-flag.** The alias stays a
`Union{AbstractFieldPhysical, AbstractFieldSpectral}`.

The finding is usually raised by analogy with decision 60, which replaced a `Union` with an abstract
hierarchy — but that decision was about **naming and dispatch semantics** (the abstract type read
broader than the union while being narrower, and `convolve` was asymmetric because argument position
was the only thing carrying the role), not about speed. What decision 60 *measured* was its
replacement being free, not the union being slow.

The cost question here was then settled by measurement rather than argument. The same body under
`::AbstractField`, under `::AbstractFieldPhysical` and untyped runs at 15.92 / 15.99 / 16.15 µs on a
``64^3`` scalar field — identical within noise — and inference returns a concrete `Float64` through
the Union. Julia specialises on the concrete argument type at each call site, so the annotation never
reaches the compiled code. A `Union` costs where it is a **struct field type** or an **array element
type**; this one is neither, appearing in 31 method signatures and nowhere else.

Converting the package's most foundational alias would be a breaking type-hierarchy change buying a
naming preference and no measured cost. A future panel re-raising it should close against this note.

Settles, verbatim: `AbstractField` is a documented `Union`

## 2026-09-01 — the panel's escalated findings, walked one by one with the owner

### `Grid3D`'s two-argument constructor takes `origin` as a keyword
**SETTLED 2026-09-02 (user): the keyword STAYS — leave it as is, do not re-flag.** Superseding the
2026-09-01 deferral: this is no longer waiting for a breaking round, it is closed.

The finding is correct and is not disputed — the four-argument form takes `origin` positionally, and
the policy makes a result-affecting argument positional, `origin` shifting every node. It is now a
**recorded exception in the policy itself** (`CLAUDE.md`, positional-vs-keyword), which is where a
re-raise should close.

Two facts narrowed it before the ruling. `Grid3D` is the **only public entry point that takes an
origin at all** — `PointSet` takes coordinates, and every transfer path reads `grid.origin` — so the
disagreement is confined to one type's own constructor pair rather than being a convention spread
across the surface. And every *internal* taker (`_locate`, `_wrap_coordinate`, the tile-key kernel)
already has it positional, so the keyword is the lone outlier rather than the prevailing style.
Blast radius at the ruling: 24 in-repo `origin =` call sites, up from 15 on 2026-08-15, plus unknown
use in `GBGIsotropicTurbulence`.

Settles, verbatim: `Grid3D`'s convenience constructor puts `origin` in a keyword, contradicting the
package's own positional-vs-keyword rule (and its own other constructor)

### `inv` has three different failure behaviours across the four `SpectralKernel` subtypes
**SETTLED 2026-09-01 (user): NOT a defect — do not re-flag.** `StoredKernel` and `SeparableKernel`
throw on a zero coefficient; `RadialKernel` returns a non-finite multiplier, and `ProductKernel`
inherits whichever its factors do. The asymmetry is real but it is a CONSEQUENCE of the class design
rather than an oversight: a radial kernel's symbol is a closure, and testing it for zeros needs an
``O(N)`` pass over the modes — exactly the cost the compressed class exists to avoid. Making it throw
would pay that cost on every inversion; the user weighed that and declined.

It is documented where the behaviour lives: `inv(::RadialKernel)` carries a titled warning ("The
function must have no zeros on any stored mode") naming `spectral_cutoff` — which does return a
`RadialKernel` — as the case where inversion is meaningless. A future panel re-raising this should
close against this note.

### `Points` accessors use three naming conventions
**FIXED 2026-09-02 — the finding was right and is now done, so it is not a dismissal.** Recorded here
only because this file's earlier entry said "deferred to a breaking round" and would otherwise read as
still-open. `Points` now uses one prefix, spelled the way the prose spells it:

- `point_coordinates` → `point_positions`, and the `PointSet` field `coordinates` → `positions`
- `pointvalue_tensor_order` → `point_value_tensor_order`
- `similar_pointvalues` → `similar_point_values`, plus five internals on the same stem
- `point_values` and `npoints` unchanged — the latter is defined on BOTH types, so no prefix fits

Two things decided the spelling. "pointvalue" unhyphenated appeared in prose **zero** times against 98
for "point-value", so the identifiers were the outlier, not the docs. And `point_value_*` keeps the
type distinction — those accessors are on `AbstractPointValues`, not `PointSet` — which a bare
`point_*` would have thrown away.

### Consumer-contingent API-symmetry observations
**SETTLED 2026-09-01 (user): NOT a defect — do not re-flag.** *(software-architect 2, 5, 6, 7, 8.)*
Which operators take a kernel-composed arity, why `combine!` is field-only, why `weighted_inner`'s
tuple form has no two-field analogue, `map!`'s α/β arity, and where Convolution's kernel-composed
`combine!` is documented.

The hat read these as tracking one consumer's request history rather than a rule. They track a RULE,
and it is stated: **invariant 1** — "The public method set is the spec. Deliberate absences encode
representation validity … Never add a missing combination *for completeness*" — together with §2's
no-speculative-structure principle. "No consumer asked" is the operational test of that principle, not
a substitute for one, and every absence in the list carries its reason at its own site (the
`Points` API page for `combine!` — verified 2026-09-02, `Points.jl` itself never mentions it and this
entry said it did — ARCHITECTURE §13 for the `curl!` kernel arity, decision 27's entry for the
`weighted_inner` generalization).

The residual point — that a second consumer cannot enumerate the gaps without reading each docstring —
was weighed against three remedies (a consolidated absence list in §2, per-module absence notes, and
deferral to the breaking round) and the user declined all three: the rule is stated once and the
absences are documented where they occur, which is where "one concept, one home" puts them.

Settles, verbatim — the five titles this entry covers:
- The public surface's regularity is consumer-contingent, not structural: several operator families are
  asymmetric only because "no consumer asked yet"
- `exponential_convolve!`'s six overloads let `α, β` play two different positional roles, disambiguated
  only by argument position/arity
- The "mapped form" (leading fiber-map argument) covers five reductions but not `std`/`var`, with no
  structural predicate distinguishing them
- `map!`'s α/β accumulate arity exists only for the single-source form, not the variadic multi-source
  form
- The Convolution kernel-composed `combine!` method is documented on a page (`Convolution`) different
  from its generic's primary home (`FieldAlgebra`)

### The intrinsic-structure findings — DERIVED then FIXED (2026-09-01)
*(differential-geometer 1, 3, 10; spectral-methods-mathematician 7.)* The user asked for each to be
worked out formally before anything was edited. The derivations, kept because two of the three verdicts
are not what the hats assumed:

**∇'s codomain — TRUE, a real type error.** The text said "``\nabla`` maps a section of ``E`` to a
section of ``T^{*}\Omega \otimes E``, and the frame identifies ``T\Omega`` with ``V``". Typed from
the document's own definitions, ``T\Omega`` has rank 3 while ``V = (\mathbb R^3)^{\otimes R}`` has
rank ``3^R``, so the identification holds ONLY at ``R = 1`` — it equates a rank-3 bundle with a rank-1
one at ``R = 0`` and a rank-9 one at ``R = 2``. The conclusion it justifies is nonetheless right: the
orthonormal frame identifies ``T^{*}\Omega \cong T\Omega \cong \mathbb R^3``, the GENERATING
space, and then ``T^{*}\Omega \otimes E`` has fiber ``\mathbb R^3 \otimes V``, one order higher.
A wrong reason under a right result. **Fixed.**

**The adjointness display — IMPRECISE, not false.** The middle term ``\sum_x f(x)\cdot(W^\top q)(x)``
is a nodal sum, and for `DirectDFT` the natural pairing is mode-wise with the ``\alpha(k)`` weights.
They are the SAME NUMBER by Parseval, which is why `inner` on a spectral field returns the physical
value, and `test/transfer_spectral.jl` asserts the spectral form and passes. So the identity is true as
claimed; only its presentation was nodal-only. **Fixed by scoping, not by correction.**

**``\sum_k`` — TRUE, one concept with two notations.** Line 89's sum reconstructs ``f`` from every
mode (full spectrum); lines 493 and 584 carry ``\alpha(k)``, the half-spectrum multiplicity, so they
run over the stored set. Identical glyph, distinguished only by knowing what ``\alpha`` is — while
line 693 already writes ``\sum_{\text{stored }k}`` explicitly. The corpus contained its own remedy.
**Fixed by adopting the explicit marker.**

None of these is a do-not-re-flag entry: all three are FIXED, and this file's header says a fixed
finding does not belong here. They are recorded only because the derivations are the durable part —
a future reader re-raising the ∇ claim should see why the conclusion survived its broken premise.
