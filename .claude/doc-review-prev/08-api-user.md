# API-User Review — GBGPeriodicFields rendered docs

Hat: **Computational scientist trying to USE the library from the docs alone.**
Method: read the whole rendered site (Home, api overview, architecture, formalization,
notation, performance, testing, tutorial, all nine api/* module pages, examples/hist_cpu),
then reconstructed the constructor + call surface a user must reach for, walked the two
worked examples (Getting-started doctests, HIST_CPU) line by line against the documented
API, and cross-referenced every one-liner/summary against each operation's own docstring.

Overall the API surface is unusually well-documented: every field/point type constructor,
every operator's args, return shapes/representations, and the intentional absences are
present and mostly self-consistent. Findings below are the drift/gaps I did find.

---

## Finding 1 — `FieldSpectralMultipliers(field)` (the single-arg convenience constructor) is used everywhere but has no documented signature; its docstring promises a separate entry that does not exist
- **type:** api-gap
- **severity:** major
- **confidence:** high

**Locations / evidence.**
- Fields API page, `FieldSpectralMultipliers` type: the *only two* documented signatures both require all six wavenumber arrays —
  `FieldSpectralMultipliers(grid, fourier_layout, wavenumber_1, wavenumber_2, wavenumber_3, squared_wavenumber_1, squared_wavenumber_2, squared_wavenumber_3)` (line 2330) and
  `FieldSpectralMultipliers(field::AbstractFieldSpectral{T}, wavenumber_1, …, squared_wavenumber_3)` (line 2337).
- Same docstring, prose: *"A convenience constructor `FieldSpectralMultipliers(field)` builds both families from the field's grid and layout with the correct Nyquist treatment; **it is documented separately below**."* (line 2349) — nothing is documented below it; the next entry on the page is `## Transform operations` / `to_physical!`.
- The single-arg form is the one actually used: tutorial line 916 `multipliers = FieldSpectralMultipliers(scalar_spectral);` and HIST line 3419 `m = FieldSpectralMultipliers(uspec0)`.
- DifferentialOperators module docstring (line 1122): *"built from a field with `FieldSpectralMultipliers(field)` or from the explicit six-array constructor."*

**Why it matters.** `FieldSpectralMultipliers(field)` is the primary constructor — required for every differential operator, the radial spectrum, and the convolution builders — yet the API reference documents only the two advanced six-array forms. A user reading the API page for how to build multipliers would conclude they must first construct the wavenumber vectors themselves. The prose does describe the convenience form by name, but the explicit promise "documented separately below" resolves to nothing (a broken forward-reference). Architecture §4 (lines 251–254) describes exactly two constructors — "an explicit constructor taking all six arrays" and "a convenience constructor from a field" — so the intended surface is the six-array *and* the single-arg form; the Fields page instead shows two six-array variants and omits the convenience one.

**Resolution hint.** Give `FieldSpectralMultipliers(field)` its own signature block in the `@docs` entry (it clearly has behavior worth a line: "builds both wavenumber families with the correct Nyquist split"), or drop the "documented separately below" clause and fold the single-arg signature into the shown list.

---

## Finding 2 — the symbol `E(κ)` means the raw power spectrum on the Reductions page but the (half-as-large) kinetic-energy spectrum in the architecture and the HIST example
- **type:** contradiction
- **severity:** major
- **confidence:** high
- **contradicts:** Reductions API page `radial_spectrum` docstring (line 3148, *"`radial_spectrum` $\equiv E(\kappa)$ … the power spectrum $E(\kappa)$"*, with line 3153 *"$\sum_\kappa E(\kappa) = \langle f, f\rangle$"*) — vs — architecture decision-21 (line 430, *"the energy spectrum … is $E(\kappa) = \tfrac{1}{2}\,\mathrm{spectrum}$"*) and HIST example (line 3292 *"$E(\kappa) = \tfrac{1}{2}\times$ the shell-resolved Parseval inner; $\sum_\kappa E(\kappa) = \tfrac12\langle|u|^2\rangle = k$"*, line 3586 *"The energy spectrum $E(\kappa)$ … $E(\kappa) = C_K\varepsilon^{2/3}\kappa^{-5/3}$"*). **Axis of disagreement: what the symbol `E(κ)` denotes — `radial_spectrum` itself (Σ = ⟨|u|²⟩ = 2k) vs. `½·radial_spectrum` (Σ = k).**

**Locations / evidence.**
- Reductions API page (line 3148): binds `radial_spectrum` $\equiv E(\kappa)$ and calls the returned `spectrum` the power spectrum $E(\kappa)$; line 3153 asserts $\sum_\kappa E(\kappa) = \langle f,f\rangle$, i.e. for velocity $\sum E(\kappa) = \langle|u|^2\rangle = 2k$. It then says (line 3153) *"The consumer's kinetic-energy spectrum is $\tfrac12 E(\kappa)$."*
- Architecture (line 430 and 434): $E(\kappa) = \tfrac12\,\mathrm{spectrum} = \tfrac12\,\mathrm{radial\_spectrum}$.
- HIST example (lines 3281, 3292, 3297, 3586): `energy_spectrum` returns `0.5 .* spectrum` and labels *that* $E(\kappa)$; $\sum_\kappa E(\kappa) = k$; and the plotted $E(\kappa)$ is compared against $C_K\varepsilon^{2/3}\kappa^{-5/3}$.

**Why it matters.** The same glyph `E(κ)` is the reduction's raw output on one page and half of it on the other two. A user who reads the Reductions docstring's binding `radial_spectrum ≡ E(κ)` and plots `radial_spectrum` directly against the K41 form $C_K\varepsilon^{2/3}\kappa^{-5/3}$ (as the HIST example labels $E(κ)$) is off by exactly 2×. Each page is internally consistent, but the cross-page symbol is not — a one-notation-one-concept violation, and a factor-of-2 in a plotted physical quantity. (The tutorial sidesteps it by never naming the output `E(κ)`: line 940 checks `sum(spectrum) == inner(u,u) = 1.5`, consistent with `radial_spectrum` = the raw power spectrum.)

**Resolution hint.** Reserve `E(κ)` for the ½-normalized energy spectrum everywhere (matching the turbulence convention and the example), and bind `radial_spectrum` to a neutral symbol for the raw shell power (e.g. `radial_spectrum ≡ S(κ)` with `E(κ) = ½ S(κ)`), or state on the Reductions page that its `E(κ)` is 2× the consumer energy spectrum used in the example.

---

## Finding 3 — `check_field_compatibility` is called "public" in the architecture but sits under "Internal API — not part of the public interface" on the Fields page
- **type:** contradiction
- **severity:** minor
- **confidence:** high
- **contradicts:** architecture §5 (line 268, *"the public `check_field_compatibility`"*) — vs — Fields API page Internal-API heading (line 2492, *"These symbols are not part of the public interface; they are documented for contributors"*) under which `check_field_compatibility` is listed (line 2624). **Axis: public vs. internal status of `check_field_compatibility`.**

**Why it matters.** A user cannot tell whether `check_field_compatibility(a, b)` is a supported entry point they may call to validate two fields, or an internal helper. The architecture presents it as the public compatibility check (peer of the underscore-prefixed internal ones); the API page files it with the `_`-prefixed internals under an explicit "not part of the public interface" banner. One of the two must yield.

---

## Finding 4 — the callable field evaluation `f(x)` / `f.(xs)` is advertised as public ergonomic API but documented under "Internal API"
- **type:** organization
- **severity:** minor
- **confidence:** high

**Locations / evidence.**
- Advertised public: Interpolation module docstring (line 2725, *"plus the callable `f(x)` (and its broadcast `f.(xs)`) as the ergonomic face of a single-point gather"*) and architecture §10 (line 303, same wording, "the ergonomic face of `interpolate`").
- Documented internal: Interpolation API page, `## Internal API` (line 2841, *"documented for contributors"*), where the callable `(field::AbstractFieldPhysical)(x; scheme = CatmullRom)` is the first entry (line 2843).

**Why it matters.** `f(x)` is the friendliest way to evaluate a field at a point and is prominently promoted in two module docstrings, yet a user scanning the Interpolation "Transfer operations" section finds only `interpolate`/`anterpolate`; the callable is buried in the contributor-facing Internal API. Its `scheme` keyword and its physical-field-only restriction are only discoverable there.

**Resolution hint.** Move the callable's `@docs` entry into the public "Transfer operations" group (or add a public entry cross-linking it), since the module docstring already treats it as public.

---

## Finding 5 — the architecture's own method-count walk reaches 202 while the same passage declares a "206-method public surface"
- **type:** contradiction
- **severity:** minor
- **confidence:** medium
- **contradicts:** architecture §2 line 228 (*"The 206-method public surface of `FieldAlgebra` … M2 (98 methods …) and then M3 (…), bringing the total to 198; the later trace `tr`/`tr!` addition brings it to 202"*) — vs — §6 line 285 (*"The full M2+M3 baseline is 206 public methods (… `combine!` 2 … `det`/`det!` 1 each)"*). **Axis: the running total (98 → 198 → 202) does not reach the declared 206.**

**Why it matters.** The passage opens with "206-method public surface" but the step-by-step walk stops at 202, silently omitting the decision-27 additions (`combine!` +2, `det`/`det!` +2) that make up the difference. A reader adding it up cannot reconcile the two numbers. Related, lower-severity drift: the append-only §13 decision log states "198 methods, the full surface" (line 364) and "the 198-method field surface" / "118-method" point baseline (lines 388, 390) — historical snapshots that are superseded by 206/122 in decisions 27–28 (lines 470, 480), but which describe 198/118 as "the full surface"; the testing page and §10 body use the current 206/122.

**Resolution hint.** Extend the §2 line-228 walk to 206 (…198 → 202 with `tr`/`tr!` → 206 with `combine!` and `det`/`det!`), matching §6.

---

## Finding 6 — the aliasing contract of the alias-guarded spectral operators (`curl!`, `helmholtz_projection!`) is undocumented, though the HIST example relies on it and the peer operators document theirs
- **type:** api-gap
- **severity:** minor
- **confidence:** medium

**Locations / evidence.**
- HIST example relies on aliased in-place projection: line 3384 `helmholtz_projection!(uh, uh, m)   # make solenoidal (alias-guarded)` (destination = source).
- The `helmholtz_projection!` docstring (lines 1326–1345) and the `curl!` docstring (lines 1202–1226) say nothing about whether the destination may alias the source; the DifferentialOperators module docstring (lines 1122–1131) is likewise silent. That the ops *are* alias-guarded is stated only in the architecture (decision-24, line 453, "the aliased `helmholtz_projection!(x, x)` allocates its guard temporary upstream") and the testing page (line 830, listing `curl!`/`helmholtz_projection!` among "alias-guarded operations").
- By contrast the aliasing contract *is* documented for the peer operators: `combine!` (line 1751, *"`a`, `b`, or both may be `destination` itself"*), `convolve!` (line 1003, *"it may alias `field` or `kernel`"*), `mul!` (line 1854, *"`destination` must not share storage with any input"*), and the FieldAlgebra module docstring (line 1714, the index-shuffling ops "may be called with the destination aliasing an input").

**Why it matters.** A user copying the HIST idiom `helmholtz_projection!(uh, uh, m)` has no way, from the operator's own docstring, to confirm that aliasing is legal (or that it costs a guard temporary when aliased) — even though the same package documents this contract explicitly for `combine!`/`convolve!`/`mul!`. The aliasing documentation is inconsistent across operator families.

**Resolution hint.** Add a one-line aliasing note to `curl!`/`helmholtz_projection!` (and, for parity, the FieldAlgebra `cross!`/`transpose!`/`sym!`/`skew!`/`dev!` `!`-docstrings) mirroring `combine!`/`mul!`.

---

## Finding 7 — the `--smoke` configuration is defined and handled but omitted from the HIST run-command list
- **type:** organization
- **severity:** nit
- **confidence:** high

**Locations / evidence.** The command list (lines 3197–3202) shows `--fast`, `--huge`, `--mega`, and the default, but not `--smoke`; yet `smoke()` is defined (line 3237), described (line 3234, *"A tiny configuration for a quick end-to-end check (`--smoke`)"*), listed among the size selectors (line 3216), and dispatched in `main()` (line 3559). A reader scanning the runnable command block would not see the quickest option.

**Resolution hint.** Add a `--smoke` line to the command block.

---

## Checked and found consistent (for the record)
- Every package symbol used in the tutorial and HIST resolves to a documented binding **except** `FieldSpectralMultipliers(field)` (Finding 1).
- Tutorial doctests are self-consistent: `field_tensor_order(u)==1`, `size(field_data(u))==(16,16,16,3)`, round-trip `to_physical(to_spectral(u))≈u`, `laplacian(sin x)==-sin x`, `inner(u,u)==1.5` for `u=(sin x, cos y, sin z)`, `sum(spectrum)==inner(u,u)==1.5`, `spectral_cutoff(uh, m, 4.0)`, `PointSet([… ; …])` with `npoints==2`, `pointvalue_tensor_order(interpolate(u, points))==1`.
- HIST call signatures all match the documented API: `convolve!` 3-arg and 5-arg (α/β, aliased dest), `curl!`/`to_physical!`/`cross!`/`to_spectral!`/`helmholtz_projection!`, `spectral_cutoff`/`spectral_band`/`squared_wavenumber_field`, `radial_correlation(uh, plans)` vs `radial_spectrum(uh, multipliers)` (the deliberate `plans` vs `multipliers` split, correctly documented on both), `interpolate(u, PointSet(X))`, `inner`/`l2norm`/`divergence`/`curl`.
- Return representations are clear: spectral operators return typed spectral destinations; `inner`→scalar, `integral`/`mean`→fiber-preserving (FiberVector/FiberTensor2), `radial_*`→(bins, profile) tuples, `interpolate`→AbstractPointValues, `anterpolate`→field.
- Representation validity is consistent across the module summaries, decision-27 formalization, and each operation's docstring (nonlinear ops physical-only; `inner`/`l2norm`/`integral`/`mean` also spectral; `weighted_inner`/`radial_*` spectral-only; `lpnorm`/`std`/`var`/`max`/`min`/`extrema` physical-only).
- Umbrella one-liners (GBGPeriodicFields page, Home, api overview) match the per-module documented surfaces; `translation_kernel` (the 5th convolution builder) is documented with all three args.
