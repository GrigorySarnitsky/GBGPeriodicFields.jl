# Software Architect review — GBGPeriodicFields rendered docs

Reviewing the documented design (API pages + `docs/ARCHITECTURE.md`/decision log, as rendered) as a
Julia expert judging signatures, module decomposition, and decision-log internal consistency. Findings
below are ranked most-severe first.

---

## Finding 1 — `combine!`'s module placement contradicts its own stated rationale, and looks driven by a test-count artifact

**Type:** organization
**Severity:** major
**Confidence:** medium

**Locations:**
- ARCHITECTURE §13, the exponential-kernel decision: *"The method is defined in `Convolution` (the kernel is a `Convolution` concept; `FieldAlgebra` precedes it in the include order and never sees kernels), which also keeps the `FieldAlgebra` method-parity baseline untouched by construction — the parity count filters on the defining module."*
- ARCHITECTURE §13, decision 32: *"`helmholtz_projection!` and `divergence!` gain trailing `kernel[, α, β]` arities... Guards: ... in `test/differentialoperators.jl`"* — i.e. these kernel-composed methods stay inside `DifferentialOperators`, verified there, not moved to `Convolution`.
- Include order stated on the Home/api pages: `FiberSections → Fields → FieldAlgebra → DifferentialOperators → Convolution → Points → Interpolation → Reductions` — `DifferentialOperators` precedes `Convolution` exactly as `FieldAlgebra` does.

**Contradicts:** The stated reason `combine!`'s kernel-composed method had to move to `Convolution` — "`FieldAlgebra` precedes it in the include order and never sees kernels" — applies verbatim to `DifferentialOperators`, which precedes `Convolution` too, yet `divergence!`/`helmholtz_projection!`'s own kernel-composed arities were kept inside `DifferentialOperators` without incident.

**Description:** Both `FieldAlgebra` and `DifferentialOperators` sit before `Convolution` in the include order, and both needed to add a "trailing kernel" arity to an operator they already own. `DifferentialOperators` did so in its own module (decision 32); `combine!`'s otherwise-identical extension was instead placed in `Convolution`, with the given reason ("never sees kernels") that does not actually distinguish it from `DifferentialOperators`'s situation. The same sentence names the real driver: doing it in `FieldAlgebra` would have bumped the specifically-tracked 206-method parity baseline, which the package treats as sacred. That is a legitimate engineering trade-off, but presenting it as principled module ownership ("the kernel is a `Convolution` concept") while a structurally identical case was resolved the opposite way is an internal inconsistency in the architecture rationale, and it means one generic (`combine!`) now has its methods split across two modules for a reason that is really about test-baseline bookkeeping.

---

## Finding 2 — α/β is overloaded with two different roles across the API, sometimes within the same generic

**Type:** api-gap
**Severity:** minor
**Confidence:** medium

**Locations:**
- Convolution page, `exponential_convolve!` argument docs: *"α, β — in the single-operand forms, where they trail the argument list, the usual accumulation weights... α, a, β, b — in the two-operand forms, where they lead it, the real weights and fields of the combination... The two roles never share a signature, which is why one pair of glyphs can serve both."*
- FieldAlgebra page, `combine!`: `combine!(destination, α::Real, a, β::Real, b)` computes `destination = α·a + β·b` (weights of two *input* fields).
- DifferentialOperators/Convolution "kernel-composed" family (`divergence!`, `helmholtz_projection!`, `convolve!`): `op!(dest, ..., α, β)` computes `α·(new result) + β·dest` (accumulate onto a *pre-existing destination*).

**Description:** Invariant 10 states one α/β convention ("β=0 overwrite, β≠0 accumulate onto destination"), but `combine!` and the two-operand forms of `exponential_convolve!` use the identical glyphs α/β for a structurally different role — weighting two *input* operands, with no destination-accumulate semantics unless an input happens to alias the destination. The docs candidly flag this exact tension for `exponential_convolve!`'s two overloads ("the glyph-collision failure mode") but the same tension exists, unremarked, between `combine!`'s convention and the "accumulate" convention used everywhere else in the package. A reader who has internalized "α scales the new result, β accumulates onto dest" from `mul!`/`convolve!`/`divergence!` can misread `combine!`'s signature.

---

## Finding 3 — the callable-field transfer syntax uses `scheme` as a keyword while every named transfer function uses it positionally

**Type:** api-gap
**Severity:** minor
**Confidence:** high

**Locations:**
- Interpolation page: `interpolate(field::AbstractFieldPhysical, points, scheme = CatmullRom)`, `interpolate!(out, field, points, scheme::AbstractSplineScheme = CatmullRom)`, `anterpolate(grid, points, quantities, scheme = CatmullRom)`, `anterpolate!(field, points, quantities, scheme::AbstractSplineScheme = CatmullRom, α::Real = true, β::Real = false)` — `scheme` positional-with-default in all four.
- Interpolation page, the callable: `(field::AbstractFieldPhysical)(x; scheme = CatmullRom)` — `scheme` is keyword-only here.

**Description:** The callable `f(x)` is documented as "the ergonomic face of a one-point `interpolate` gather," i.e. the same concept as `interpolate`'s `scheme` argument, yet it is passed a different way (keyword vs. positional-with-default) than every other transfer entry point. This is a small but real convention break in an otherwise tightly disciplined naming/argument-order system; a user who writes `interpolate(f, xs, LagrangeSpline(2))` by analogy will find `f(x, LagrangeSpline(2))` fails and `f(x; scheme = LagrangeSpline(2))` is required.

---

## Finding 4 — the "Fourier-dual pair" `radial_spectrum`/`radial_correlation` take differently-typed second arguments

**Type:** api-gap
**Severity:** minor
**Confidence:** medium

**Locations:**
- Reductions page: `radial_spectrum(f, multipliers)` / `radial_spectrum(f, g, multipliers)`.
- Reductions page: `radial_correlation(f, plans)` / `radial_correlation(f, g, plans)`.
- Home page: *"the radial reductions `radial_spectrum` (the power spectrum) and `radial_correlation` (its physical-space Wiener–Khinchin dual...), each with a two-field co-spectrum form"* — presented throughout as a matched, symmetric pair.

**Description:** The two operations are marketed everywhere (module docstring, ARCHITECTURE §12, the decision log) as a tightly mirrored Fourier-dual pair with parallel signatures, but their second positional argument is a different type — `FieldSpectralMultipliers` for the spectrum, `FieldTransformPlans` for the correlation (the latter needs an inverse transform, the former does not). This is mathematically well-motivated (recorded in the decision log: "`radial_correlation(f, plans)`... symmetric with how the differential operators take `multipliers`"), but from the outside the pair reads as "same shape, different second argument type," which is an easy mistake for a caller reasoning by analogy from `radial_spectrum` to `radial_correlation`.

---

## Finding 5 — `radial_kernel`'s argument order breaks the family convention of the other kernel builders

**Type:** api-gap
**Severity:** nit
**Confidence:** medium

**Locations:**
- Convolution page: `radial_kernel(sigma, reference::AbstractFieldSpectral, multipliers::FieldSpectralMultipliers) -> RadialKernel` — the function argument leads.
- Same page: `spectral_cutoff(reference::AbstractFieldSpectral, multipliers::FieldSpectralMultipliers, wavenumber_cutoff) -> RadialKernel`, and (by the same pattern) `assignment_window(reference, multipliers)`, `translation_kernel(reference, multipliers, h)` — all put `reference, multipliers` first and the builder-specific parameter(s) last.

**Description:** Within the single documented "Kernel builders" family, `radial_kernel` is the only member whose distinguishing argument comes first rather than last. It is defensible on its own (mirroring `map(f, itr)`/`mapreduce(f, op, itr)` house style, since `sigma` is a callable), but it is inconsistent with its four siblings in the same table, which a reader is invited to compare directly.

---

## Finding 6 — the §2 naming-conventions bullet list is stale: `cov` is missing from the "extends Statistics" enumeration

**Type:** other
**Severity:** nit
**Confidence:** high

**Locations:**
- ARCHITECTURE §2, "Naming conventions": *"Extensions of Base / LinearAlgebra / Statistics keep the source name, overriding the above (`dot`, `cross`, `mul!`, `transpose`, `norm`, `mean`, `std`, `var`, `maximum`, `minimum`, `extrema`)..."* — no `cov`.
- Reductions API page, "Moments and order statistics": *"These extend the standard-library generics — `mean`, `std`, `var`, and `cov` from `Statistics`... rather than introducing package names..."* — `cov` is present.

**Contradicts:** §2's enumerated list of Base/Statistics-extending names vs. the Reductions page's own (correct, more current) list of the same category.

**Description:** `cov` was added later (the 2026-07-28 `var`/`std`/`cov` decision) as exactly the kind of Statistics extension §2's bullet is meant to enumerate, but the bullet was never updated. This is a small, low-stakes instance of precisely the failure mode the decision log elsewhere calls out repeatedly and self-critically ("a hand-maintained list goes stale" — decisions 53/54): an enumerated list in the architecture doc, not derived from anything, missing one member.

---

## Finding 7 — `weighted_inner`'s documented type restriction on `w` is not visible in its rendered signature

**Type:** api-gap
**Severity:** minor
**Confidence:** low

**Locations:**
- Reductions page: rendered signature block is bare — `weighted_inner(f, w)` / `weighted_inner(f, g, w)`, no type annotation on `w`.
- Same entry's prose: *"`w` — the weight, a stored or radial spectral kernel holding a real multiplier `w(k)`... a separable kernel is deliberately not accepted, its factors not being real in general."*

**Description:** CLAUDE.md's own documentation rubric states "a docstring signature mirrors the code's types... An argument typed in the actual method is typed in the docstring." Here the prose asserts a real, load-bearing restriction (separable kernels are refused), but the rendered signature gives no type constraint on `w` at all, unlike almost every other kernel-accepting signature on the Convolution/DifferentialOperators pages (which do show `kernel::SpectralKernel`). If the restriction is enforced only by a runtime check rather than by the method's own type signature, that is worth surfacing explicitly (per the package's own "no silent failures" standard from the 2026-07-30 external-audit response); if it *is* type-enforced, the doc under-reports it relative to its own stated convention.

---

## Finding 8 — `Grid3D`'s "The fields are" list presents a derived quantity as if independent

**Type:** other
**Severity:** nit
**Confidence:** high

**Locations:**
- Fields page, `Grid3D`: *"The fields are ... `grid_spacing::NTuple{3, T}`: the spacing between adjacent grid points in each spatial direction."* — listed as a peer bullet alongside `grid_size`, `domain_size`, `origin`.
- Same entry, immediately after: *"The grid is uniform, so the spacing is not independent: it must equal `domain_size ./ grid_size` along every axis."*

**Description:** Per CLAUDE.md's own docstring rubric, "a type that stores named, user-readable fields documents them under `The fields are`, one bullet per field" — technically correct, since `grid_spacing` genuinely is stored (for the transfer kernels' benefit). But listing it as a flat, independent field alongside the three genuinely-independent ones, one sentence before explaining it is actually a *constrained*, derived quantity, is a presentation wart: a reader skimming the bullet list alone would reasonably conclude all four fields are independently settable.

---

## Finding 9 — the "symmetric named pair" framing of interpolate/anterpolate is undercut by two admitted asymmetries

**Type:** other
**Severity:** nit
**Confidence:** high

**Locations:**
- ARCHITECTURE §10 / Interpolation module docstring: *"They are the symmetric named pair"* / *"Same verbs, one adjointness contract."*
- Interpolation module docstring: *"Interpolation yields point values while its adjoint returns a field — one of two asymmetries between the pair, the other being the α/β accumulation weights that only the scatter takes."*

**Description:** Not a defect — both asymmetries are explicitly documented and individually well-motivated (evaluation is naturally an overwrite; accumulation is the natural mode for two-way-coupling scatter). But the repeated "symmetric pair" / "same verbs" framing across the Home page, the api page, and ARCHITECTURE §10 is stronger language than the actual API, which has `anterpolate!` carrying a 5-argument α/β form that `interpolate!` structurally cannot mirror. Worth a lighter touch on "symmetric" in the summary-level prose, since the detail pages already state the asymmetry correctly.

---

## Observations not raised to findings

- The four-class `SpectralKernel` hierarchy (`StoredKernel`/`SeparableKernel`/`RadialKernel`/`ProductKernel`), plus the `Canonical` type parameter on `FieldSpectralMultipliers` that decides whether two `RadialKernel`s collapse under composition, is a fair amount of machinery for "multiply two per-mode scalars." Each layer is introduced with a specific measured justification (decision log entries for decisions 50, 51, 60, 63) rather than speculatively, so this reads as disciplined accretion rather than over-engineering — flagged here only as a note that the surface is worth a periodic consolidation pass, not as a defect.
- The abstract `SpectralKernel` protocol living in `Fields` rather than `Convolution` (so that `DifferentialOperators`/`Reductions` can name it without depending on `Convolution`) is a clean instance of interface segregation and is not a coupling smell — it is the same pattern that lets Finding 1's module-split feel avoidable in principle.
