# Panel review — Software Architect / senior Julia hat

Reviewed: the full rendered site (`manuscript-full.md`) — Home, API overview, Architecture
(incl. §13 decision log), Formalization, Notation, Performance, Testing, Tutorial, every API
reference page, and the HIST_CPU example.

Overall the documented design is coherent and idiomatic: the `f`/`f!` convention is applied
uniformly (the `!` form is the home with the formula, the allocating form a thin `@ref` wrapper),
argument orders are idiomatic (destination first for `!`; the "context" argument — `multipliers` /
`plans` / weight `w` — last, with the optional second field inserted before it, consistently across
`radial_spectrum`/`radial_correlation`/`weighted_inner`), the α/β accumulation convention is uniform
(`mul!`/`convolve!`/`combine!`/`anterpolate!`), the intentional-absence rules (nonlinear ⇒
physical-only) are consistently stated, and the module decomposition (FiberSections core → Fields /
Points objects → FieldAlgebra / DifferentialOperators / Convolution / Interpolation / Reductions ops)
is single-source with no god-objects. The findings below are the places the documentation fights
itself or good practice.

---

## Finding 1 — §2 method-count self-contradiction: "206-method surface" but the walk-through stops at 202

- type: contradiction
- severity: major
- confidence: high
- locations:
  - architecture §2 "Representation validity lives in the method set": "The **206-method** public surface of `FieldAlgebra` is the machine-checkable encoding of the validity table above. Any refactor must reproduce the method set exactly; it was verified signature-for-signature against the original — M2 (98 methods: `add!`/`subtract!`/`multiply!`/`divide!`/`+`/`-`/`*`/`/`) and then M3 (…), bringing the total to **198**; the later trace `tr`/`tr!` addition brings it to **202**, all parity-checked at runtime in `test/method_parity.jl`."
  - architecture §6 "Verifying codegen changes": "The full M2+M3 baseline is **206** public methods (e.g. `*` 28, `mul!` 30, `dot`/`dot!` 10 each, `add!` 14, `combine!` 2, `tr` 2, `det`/`det!` 1 each)."
  - architecture §13 decision 27: "The public method set **grows to 206 field methods** (`combine!` adds 2, `det`/`det!` 1 each)…"
- contradicts: the same §2 paragraph headlines "206-method public surface" but its own running count reaches only 202 (98 M2 + M3 + `tr`/`tr!`), never reconciling the remaining 4. The M2 list ("98 methods: add!/subtract!/multiply!/divide!/+/-/*//") omits `combine!`, and the walk-through omits `combine!`/`det`/`det!` entirely — the exact +4 that decision 27 (and §6) attribute to reaching 206. Axis: total public method count (206 headline vs 202 derived).
- description: The "public method set is the spec" invariant is the flagship of the whole design, so the one place where the arithmetic must close is precisely where it does not. The headline number (206) was updated for decision 27 but the explanatory walk-through was left in its pre-decision-27 state (stopping at `tr`/`tr!` = 202). A reader auditing the invariant cannot reconcile the paragraph against itself.
- resolution_hint: extend the §2 walk-through to include `combine!` in M2 and `det`/`det!`, taking the running total 202 → 206; or drop the exact running tally and cite the §6 breakdown.

## Finding 2 — §10 says the point-data types "live in the `Interpolation` module" — stale; they live in `Points`

- type: contradiction
- severity: major
- confidence: high
- locations:
  - architecture §10 "Data types — the unstructured base": "…compatibility reduces to `M`-matching and matching tensor order (a `_check_…` predicate in the `Fields` style). **The types live in the `Interpolation` module**, importing `Fields` helpers via an explicit `using ..Fields: …`." (§10 300–337 never mentions the `Points` module.)
  - architecture §13 Phase-A decision: "The former `Interpolation` module is **split into `Points`** (unstructured-base section objects + their generated algebra — a noun peer of `Fields`) and `Interpolation` (the transfer maps…)."
  - umbrella `GBGPeriodicFields` module docstring: "`Points` supplies the point-data types and their fiberwise algebra, mirroring the physical field surface."
  - Points API module docstring: "The unstructured base of the package's fiber-bundle model: off-grid sample positions and the field values sampled at them… `Point`… `PointSet`… `ScalarPointValues`, `VectorPointValues`, and `TensorPointValues`…"
- contradicts: §10 (a body/"home" section) states `Point`/`PointSet`/`PointValues` live in `Interpolation`, while the §13 Phase-A decision, the umbrella docstring, and the entire Points API page place them in the `Points` module. Axis: which module hosts the point-data types.
- description: This is an intra-document contradiction — §10 and §13 of the same architecture file disagree — and §10 also contradicts the Points API page and the umbrella. §10 is the designated home for the transfer-layer detail, so it should reflect the post-Phase-A layout. As written it will mislead a reader (or a future contributor extending the point layer) about where the types live.
- resolution_hint: update §10's "Data types" paragraph to say the point-data types live in `Points` (transfer maps in `Interpolation`), matching the Phase-A split.

## Finding 3 — Performance §6/§7: rendered identifiers lose their underscores (and spaces around inline code)

- type: typesetting
- severity: major
- confidence: high
- locations:
  - performance §6: "the radial diagnostics (`radialspectrum`/`radialcorrelation`) bin on an Atomix scatter-add histogram, and CUDA's atomic throughput far outruns RDNA3's —`radialspectrum`at 256³ is ≈12× faster on the 5070 Ti than the 7900 XTX in`Float32`, widening to ≈32× in`Float64`(92 → 2.9 ms); the extra`Float64`factor…for`Float32`→`Float64`on this op… The full…matrix is in`RESULTS.md`:"
  - performance §7: "The decision-27 additions (`combine!`, `det!`, `symmetricgradient!`,`weightedinner`) are wired into their classes and CPU-verified (0 allocations for`combine!`/`det!`; the small bounded wrappers for`symmetricgradient!`/`weighted_inner`)…they enter the committed`RESULTS.md` table…"
- contradicts: the identifiers `radial_spectrum`, `radial_correlation`, `symmetric_gradient!`, `weighted_inner` are spelled with underscores everywhere else in the docs (API pages, Reductions/DifferentialOperators docstrings, §12, Testing). Here they render as `radialspectrum` / `radialcorrelation` / `symmetricgradient!` / `weightedinner`. Line 769 even shows `weighted_inner` correctly once and as `weightedinner` once, in the same sentence.
- description: These prose mentions were written without backticks (or the backticks were mis-placed), so CommonMark ate the underscores as emphasis and collapsed the spaces adjacent to inline code (`in`Float32``, `—`radialspectrum`at`). The rendered page shows public API names that do not exist (`radialspectrum`, `weightedinner`) — a reader who tries to grep or call them fails, and it directly conflicts with the correctly-spelled names on every other surface. This is the exact class the project's own doc rules call out (an underscored identifier in prose must be backticked).
- resolution_hint: backtick every identifier in these two paragraphs (`radial_spectrum`, `radial_correlation`, `symmetric_gradient!`, `weighted_inner`) and restore the spaces around each inline-code span.

## Finding 4 — Decision-log entries still assert the pre-decision-27 baselines (198 / 118) as "unchanged"

- type: contradiction
- severity: minor
- confidence: medium
- locations:
  - architecture §13 decision 20 (Convolution): "`convolve` / `convolve!` / `spectral_cutoff` are separate generics, so the `FieldAlgebra` **198-method** and point-value **118-method** parity baselines **are unchanged**."
  - architecture §13 decision 22 (co-spectra): "no export change, the **198/118** parity baselines are unchanged."
  - architecture §13 decision 23 (spectral transfer): "method parity **198/118** unchanged (the transfer verbs are not in those surfaces)."
  - architecture §13 decision 27 / §10 / testing: "**206** field methods … **122** point-value methods"; "locked by a separate **122**-method parity baseline, the **206**-method field surface"; "the 206-method field and 122-method point-value parity baselines".
- contradicts: decisions 20/22/23 state, in the present tense, that the baselines "are unchanged" at 198/118, while decision 27, §10, and the Testing page give the current baselines as 206/122. Axis: current parity-baseline counts.
- description: The log's preamble ("later entries supersede earlier *remaining/deferred* notes rather than contradicting them") is scoped to remaining/deferred notes, not to hard numeric "…are unchanged" assertions — and the doc explicitly supports reading each decision entry "on its own." A reader landing on decision 23 reads "198/118 unchanged" as current fact, which decision 27 later falsifies. This is softer than findings 1–2 (it is the chronological log, and the current number is stated authoritatively in decision 27), but the present-tense "are unchanged" phrasing makes the staleness read as a live claim.
- resolution_hint: leave the historical entries but neutralize the present-tense counts (e.g. "left the then-current 198/118 baselines unchanged"), or drop the raw numbers from the pre-27 entries and rely on decision 27 for the count.

## Finding 5 — `weighted_inner` is missing from the Home and API-overview Reductions summaries (present in the umbrella/module/§12)

- type: contradiction
- severity: minor
- confidence: high
- locations:
  - api-overview page, Reductions bullet: "Reductions: the L²/measure structure — base reductions (`integral`, `inner`, `l2norm`, `lpnorm`, `mean`/`std`/`var`, `maximum`) over fields and point-values, plus the radial pair `radial_spectrum` … and `radial_correlation` …" — no `weighted_inner`.
  - Home page, Reductions bullet: "…the measure-weighted `integral`, `inner`, `l2norm`, `lpnorm`, and `mean`/`std`/`var` … plus the measure-independent `maximum`/`minimum`/`extrema` …; plus the radial pair `radial_spectrum` … and `radial_correlation` …" — no `weighted_inner`.
  - umbrella `GBGPeriodicFields` module docstring: "`Reductions` provides the L²/measure reductions `integral`, `inner`, **`weighted_inner`**, `l2norm`, and `lpnorm`, plus the radial diagnostics…"
  - Reductions API module docstring / architecture §12 / Formalization: all name `weighted_inner`.
- contradicts: the umbrella docstring (rendered on the GBGPeriodicFields API page) lists `weighted_inner` in the Reductions surface, but the Home page and the API-overview page — both of which mirror the same per-module component list — omit it. Axis: whether `weighted_inner` is part of the advertised Reductions surface.
- description: A public exported reduction (`weighted_inner`, decision 27) is dropped from the two top-level surface summaries while every other summary includes it. It is the class of staleness the project's doc checklist targets (a summary that names only a subset of what the module provides), and it is an internal inconsistency between summaries that should agree.
- resolution_hint: add `weighted_inner` to the Home and API-overview Reductions bullets.

## Finding 6 — `FieldSpectralMultipliers(field)` promised as "documented separately below" — no such entry appears

- type: api-gap
- severity: minor
- confidence: medium
- locations:
  - Fields API, `FieldSpectralMultipliers` type docstring: "A **convenience constructor `FieldSpectralMultipliers(field)`** builds both families from the field's grid and layout with the correct Nyquist treatment; **it is documented separately below**."
  - The rendered `FieldSpectralMultipliers` block shows only the two explicit constructors (`(grid, layout, +6 arrays)` and `(field, +6 arrays)`); no separate `FieldSpectralMultipliers(field)` (single-argument) entry appears anywhere on the Fields page.
- contradicts: the type docstring's cross-reference ("documented separately below") has no target. The single-argument convenience constructor is the one actually used in the Tutorial (`FieldSpectralMultipliers(scalar_spectral)`) and in the DifferentialOperators module docstring ("built from a field with `FieldSpectralMultipliers(field)`"), so it exists — it is just not documented where the page says it is.
- description: A dangling "documented … below" pointer on a public constructor. Either the convenience constructor's own docstring is missing from the page's `@docs` blocks, or the phrase should have been "one of the constructors above." Minor, but it is a broken promise on the primary type a user constructs to run any spectral operator. (Possible consolidation artifact — flagged as seen in the provided text.)
- resolution_hint: add a `@docs` entry for the `FieldSpectralMultipliers(field)` convenience constructor, or fold its signature into the type block and drop the "documented separately below" phrase.

## Finding 7 — the public callable `field(x)` is filed under Interpolation's "Internal API / documented for contributors"

- type: organization
- severity: minor
- confidence: medium
- locations:
  - Interpolation module docstring, API list: "plus the callable **`f(x)`** (and its broadcast `f.(xs)`) as the ergonomic face of a single-point gather."
  - Interpolation API page "## Internal API": "These symbols are **not part of the public interface**; they are documented for contributors — the scheme supertype `AbstractSplineScheme`, the spline-weight generators…" — immediately followed by the entry `(field::AbstractFieldPhysical)(x; scheme = CatmullRom)` ("This is the ergonomic face of a one-point `interpolate` gather…").
- contradicts: the module docstring advertises `f(x)` as a first-class ergonomic public interface, while its reference entry sits under the "not part of the public interface / documented for contributors" heading. Axis: public vs internal classification of the callable.
- description: The call-overload `field(x)` is a headline user-facing feature (the module docstring lists it under "API"), but a user browsing the reference for it finds it grouped with the spline-weight generators and cell-finding internals. This is an organization/altitude defect — a public operation placed in the contributors' section.
- resolution_hint: move the `(field::AbstractFieldPhysical)(x; scheme)` docs entry up under "Transfer operations" (alongside `interpolate`), not under "Internal API."

## Finding 8 — NUFFT default tolerance: `tol = 1e-10` (API) vs "~10⁻¹² at the default" (decision 23)

- type: contradiction
- severity: minor
- confidence: medium
- locations:
  - Interpolation API, `NUFFT` constructor: "`NUFFT(reference::AbstractFieldSpectral; tol = 1e-10, oversampling = 2, width = 0, beta = 0)`".
  - architecture §13 decision 23: "Verified against `DirectDFT` (and `to_physical`) to the requested tolerance $\varepsilon$ (**$\sim 10^{-12}$ at the default**) for scalar and vector fields, with the NUFFT pair an exact adjoint ($\sim 10^{-15}$)."
- contradicts: the default requested tolerance is `1e-10` (API), but decision 23 characterizes the default as "~10⁻¹²." Axis: the numeric value of the default NUFFT accuracy.
- description: Read literally, "the requested tolerance ε (~10⁻¹² at the default)" equates the default ε with 10⁻¹², which disagrees with the `tol = 1e-10` default. Most likely this is requested-vs-achieved (the exp-of-semicircle rule over-delivers, so a requested 1e-10 verifies at ~1e-12), but the phrasing conflates the two and reads as a contradiction to a reader cross-checking the constructor default.
- resolution_hint: reword decision 23 to distinguish requested (`tol = 1e-10`) from achieved (~10⁻¹²), e.g. "verified better than the requested `tol` (~10⁻¹² at the default `1e-10`)."

## Finding 9 — Notation glossary defines wavenumber magnitude as ‖k‖, but the entire body uses |k|

- type: normalization
- severity: minor
- confidence: medium
- locations:
  - notation page, Base-and-fiber table: "$k$ | a wavenumber vector ($k_a$ is its $a$-th component, **$\lVert k\rVert$** its magnitude) | FieldSpectralMultipliers".
  - everywhere in the body: `laplacian!` "$|k|^2 = k_1^2 + k_2^2 + k_3^2$"; §4 "$-|k|^2$"; Formalization "$\mathrm{round}(|k|/\Delta k)$", "$\sum_c |\hat f_c|^2$"; decision 21 "the shell wavenumber $\kappa$ ($= |k|$)"; radial reductions "$|k|$-shells".
- contradicts: the notation page — billed as "the single reference … with the code object each one denotes" — introduces the wavenumber magnitude as ‖k‖, a glyph that then appears nowhere in the docstrings or design docs, which uniformly write |k| (and κ for the binned/shell magnitude). Axis: the symbol for |k|.
- description: One-concept / one-notation is broken between the glossary and its own usage: a reader who meets |k| in the Laplacian docstring and looks it up in the glossary finds only ‖k‖. Since the notation page is the canonical reference, the mismatch is more visible than an ordinary body inconsistency.
- resolution_hint: change the notation-page entry to "$|k|$ its magnitude" (matching the body), or switch the body to ‖k‖ — the former is the smaller edit and matches physics convention already in use.
