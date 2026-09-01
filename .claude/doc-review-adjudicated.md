# Do-not-re-flag list

Findings settled as **not defects**, or as decisions the owner has taken deliberately. `panel.js`
injects this into every hat's preamble and the two verifiers read it, so a finding recorded here is
correctly left unfixed and must not be graded `UNDONE`.

**Nothing merely FIXED belongs here.** Re-flagging a bad fix is exactly what the panel is for, so a
finding's absence from this file proves nothing about it.

---

## 2026-09-01 — the panel's escalated findings, walked one by one with the owner

### `Grid3D`'s two-argument constructor takes `origin` as a keyword
**DECIDED 2026-09-01 (user): deferred to a breaking round — do not re-flag.** The rule makes a
result-affecting argument positional and `origin` shifts every node, so the finding is correct and the
two constructors do disagree. The user declined all three non-deferral options — a recorded exception,
a second positional method, and the breaking rename — and parked it in CLAUDE.md's "Open interface
questions" as item 5, to be decided with the other breaking naming items rather than piecemeal.
Blast radius measured at the time: 15 in-repo call sites, none in `examples/` or `benchmark/`, and no
`origin =` call in `GBGIsotropicTurbulence`.

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
**ALREADY DECIDED — do not re-flag.** `point_coordinates` / `point_values` / `pointvalue_tensor_order`
/ `npoints` against Fields' uniform `field_*` family. This was recorded as breaking and unstarted in
CLAUDE.md's "Open interface questions" (item 4) on 2026-08-15, and the 2026-09-01 panel re-raised it
independently — which is the panel working, not a new finding. It waits for the breaking round
alongside `Grid3D`'s `origin` (item 5), deferred there by the user on 2026-09-01.

### Consumer-contingent API-symmetry observations
**SETTLED 2026-09-01 (user): NOT a defect — do not re-flag.** *(software-architect 2, 5, 6, 7, 8.)*
Which operators take a kernel-composed arity, why `combine!` is field-only, why `weighted_inner`'s
tuple form has no two-field analogue, `map!`'s α/β arity, and where Convolution's kernel-composed
`combine!` is documented.

The hat read these as tracking one consumer's request history rather than a rule. They track a RULE,
and it is stated: **invariant 1** — "The public method set is the spec. Deliberate absences encode
representation validity … Never add a missing combination *for completeness*" — together with §2's
no-speculative-structure principle. "No consumer asked" is the operational test of that principle, not
a substitute for one, and every absence in the list carries its reason at its own site (`Points.jl`
for `combine!`, ARCHITECTURE §13 for the `curl!` kernel arity, decision 27's entry for the
`weighted_inner` generalization).

The residual point — that a second consumer cannot enumerate the gaps without reading each docstring —
was weighed against three remedies (a consolidated absence list in §2, per-module absence notes, and
deferral to the breaking round) and the user declined all three: the rule is stated once and the
absences are documented where they occur, which is where "one concept, one home" puts them.

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
