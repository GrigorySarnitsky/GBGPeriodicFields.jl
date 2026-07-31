# Cold-reader review — scientific programmer, new to the package

Hat: **cold-reader**. Read top-to-bottom as a scientific programmer comfortable with Fourier
analysis but with no prior exposure to `GBGPeriodicFields`, no access to the design docs
(`ARCHITECTURE.md`, `FORMALIZATION.md`, etc.) and no access to source. Judged only the document
supplied (`manuscript-siteonly.md`): Home, API overview, Notation, Getting-started tutorial, the
eight module API pages (Convolution, DifferentialOperators, FiberSections, FieldAlgebra, Fields,
GBGPeriodicFields.jl, Interpolation, Points, Reductions), and the `examples/hist_cpu` Literate
page. Mathematical content (operator formulas, adjoint relations, Wiener–Khinchin/Parseval
identities, the K41 dimensional argument in the example page) was independently re-derived where
feasible and found correct; no findings below are math errors — all are self-containedness /
internal-consistency issues: a term, symbol, or classification used inconsistently, or used
without ever being defined on the page(s) the reader is confined to.

Findings are ordered most- to least-severe.

---

## Finding 1 — "Operation family" is used as the package's organizing taxonomy, but four different pages give four different, mutually inconsistent accounts of what the families are and how many there are

**Type:** contradiction
**Severity:** major
**Confidence:** high

**Locations:**
- PAGE: Home, opening paragraph: *"Every operation is one of three kinds: it acts within each fiber (the pointwise algebra — add, contract, transpose), it couples neighbouring base points (the differential operators and the grid↔point transfer), or it integrates the base away against the base's measure (the reductions)."* — three kinds; `Convolution` is not placed in any of them.
- PAGE: api / Convolution, module docstring: *"This is the kernel-multiplier operation family — a grid→grid multiplier that filters a field against a fixed kernel — the spectral sibling of the differential operators and the same-base counterpart of `Interpolation`."* — Convolution declares itself its own named family.
- PAGE: api / DifferentialOperators, module docstring: *"The operation families are:"* followed by a bulleted list of `gradient`, `divergence`, `curl`, `symmetric_gradient`, `laplacian`, `inverse_laplacian`, `helmholtz_projection` — here "family" means one named operator (plus its `!`/allocating pair), i.e. seven families inside one module.
- PAGE: api / FiberSections, `threading_cutoff`: *"Two operation families sit outside the gate and thread by `Threads.nthreads()` regardless … the grid↔point transfer and the radial diagnostics."* — here "family" means an ad hoc pairing that cuts across modules (all of `Interpolation`, plus only the radial half of `Reductions`).
- PAGE: api / GBGPeriodicFields, module docstring: *"The umbrella assembles its public surface from the submodules below, each of which owns one operation family:"* — here "family" = "submodule", one-to-one, for all eight listed submodules.
- PAGE: api / Reductions, module docstring: *"The L² / measure structure on sections — the third operation family, alongside the fiberwise algebra and the differential operators."* — an explicit ordinal claim: exactly three families total, and `Reductions` is the third. This directly conflicts with Convolution's self-declared family status one page earlier (alphabetically) and with the umbrella's "each submodule owns one" framing (which would make eight).

**Contradicts:** the axis of disagreement is *how many "operation families" the package has and what counts as one* — three (Home's "kinds", excluding Convolution) vs. one-per-named-operator (DifferentialOperators) vs. one-per-submodule (umbrella, ⇒ eight) vs. exactly three with Reductions as "the third" (Reductions itself, excluding Convolution, Points, Interpolation, Fields) vs. Convolution's own claim to be a distinct family not accounted for by Reductions' count of three.

**Description:** "Operation family" reads as this package's central organizing concept — every module docstring reaches for it to explain where the module sits in the whole — so a first-time reader naturally tries to build the one true list. Doing so from the rendered text alone produces contradictory answers depending on which page is read. This is exactly the kind of assumed-taxonomy problem a cold read is meant to catch: no single page ever states the complete, authoritative list of families, so "family" ends up meaning at least four different things (a top-level kind, a per-operator cluster, an ad hoc threading-relevant grouping, and a per-submodule count) without any page acknowledging the others' groupings.

---

## Finding 2 — The Notation page's own definition of `k` (the single most-used symbol in the docs) is rendered broken/truncated

**Type:** typesetting
**Severity:** major
**Confidence:** high

**Locations:**
- PAGE: notation, "Base and fiber" table, verbatim as rendered: *"$k$ | a wavenumber vector ($k_a$ is its $a$-th component, `` | k"* — the row cuts off mid-clause, ends in a stray double backtick, and the "Code" column is left as the bare, unhelpful `k`. The row directly above and below it are intact (`$M$ | the number of points | npoints`, `$h$ | a physical displacement (...) | translation_kernel`), so this is not a general table problem, just this one row.
- Compare PAGE: api / DifferentialOperators, `laplacian!`: *"$\widehat{\Delta f}(k) = -|k|^2 \hat f(k), \qquad |k|^2 = k_1^2 + k_2^2 + k_3^2.$"* — the magnitude $|k|$, evidently what the broken row was trying to define (a `|` inside "$|k|$" is a plausible culprit for a Markdown-table parse break), is instead defined redundantly, several times, inside individual operator docstrings (`laplacian!`, `squared_wavenumber_field`, etc.).

**Description:** The Notation page bills itself as *"the single reference"* for symbols, with the explicit promise that *"a docstring introduces a symbol on first use and need not repeat the convention"* — i.e., the reader is entitled to rely on this page rather than reconstructing everything locally. For `k`, arguably the most pervasive symbol in the whole site (`|k|`, `|k|^2`, `\hat f(k)`, every kernel builder, every spectral operator), the row is corrupted and never actually states the magnitude notation `|k|` that the rest of the site leans on constantly. The practical damage is softened because `|k|^2 = k_1^2+k_2^2+k_3^2` is re-derived inline in several operator docstrings, but the canonical reference itself fails to deliver on exactly the symbol a reader would most want to look up there.

---

## Finding 3 — `symmetric_gradient` is missing from the Home page's enumeration of `DifferentialOperators`'s operators, though it is a first-class operator everywhere else

**Type:** contradiction
**Severity:** major
**Confidence:** high

**Locations:**
- PAGE: Home, "Main components": *"`DifferentialOperators`: spectral differential operators — gradient, divergence, curl, Laplacian, inverse Laplacian, and Helmholtz projection."* — six operators, phrased as an exhaustive list ("X, Y, Z, and W").
- PAGE: api / GBGPeriodicFields, module docstring: *"`DifferentialOperators` provides the spectral operators `gradient`, `divergence`, `curl`, `symmetric_gradient`, `laplacian`, `inverse_laplacian`, and `helmholtz_projection`."* — seven operators, `symmetric_gradient` included.
- PAGE: api / DifferentialOperators, module docstring itself lists `symmetric_gradient` as one of "The operation families are:", describing it as *"the fused symmetric peer of `curl`, skipping the full gradient"* — a documented performance-relevant primitive (avoids building the full nine-component gradient tensor just to symmetrize it).

**Description:** A reader who only skims the Home page's "Main components" overview — the first and most natural place to learn what a module offers — would not know `symmetric_gradient` exists, and might write `sym(gradient(u))` instead of the cheaper fused primitive the docs elsewhere specifically recommend. The umbrella module page and the DifferentialOperators page itself both include it; only the Home-page summary is stale/incomplete.

---

## Finding 4 — The glyph `α` (and `α(k)`) is reused for two unrelated meanings: the pervasive accumulation weight, and a per-mode Parseval multiplicity constant

**Type:** clarity
**Severity:** major
**Confidence:** high

**Locations:**
- PAGE: api / Convolution, `convolve!`: *"`α`, `β` — real accumulation weights, converted to the field's scalar type; the three-argument form overwrites ($\alpha = 1$, $\beta = 0$), the five-argument form computes $\alpha (f \star g) + \beta \mathrm{destination}$."* — this exact α/β-as-caller-supplied-real-scalar pattern is repeated near-verbatim across `exponential_convolve!`, `divergence!`'s kernel-composed form, `helmholtz_projection!`'s kernel-composed form, `combine!`, `mul!`, and `anterpolate!`.
- PAGE: api / Interpolation, `DirectDFT`: *"reconstructing the real field ($o$ the grid origin) from the stored rfft half-spectrum with the Parseval weight $\alpha(k) = 1$ on the self-conjugate planes … and $2$ elsewhere."* — here `α` is not a caller argument at all, but a formula-internal multiplicity factor (1 or 2) baked into the half-spectrum reconstruction sum.
- PAGE: api / Reductions, `weighted_inner`: *"By Parseval, with the rfft half-spectrum weight $\alpha(k)$ ($1$ on the folded axis's zero plane … ; $2$ otherwise …)"* — same reuse.
- PAGE: api / Reductions, `radial_spectrum`: *"with $c$ indexing the fiber components, $\alpha(k)$ the rfft half-spectrum Parseval weight ($1$ on the folded axis's zero and even-length Nyquist planes, $2$ otherwise …)"* — same reuse a third time.

**Description:** By the time a reader reaches `DirectDFT`, `weighted_inner`, or `radial_spectrum`, the α/β-accumulation idiom has been drilled in by a dozen-plus prior docstrings as "the real weight the caller passes to scale/accumulate a result." Re-using the bare glyph `α` — written as a function of `k` but still visually just "α" — for an entirely different, formula-internal quantity (a 1-or-2 multiplicity from the rfft half-spectrum convention) invites a reader to misread it as another accumulation weight. Neither meaning of `α` appears on the Notation page at all (see also Finding 13's related gap), so there's no canonical place a confused reader could go to disambiguate.

---

## Finding 5 — The {`radial_spectrum`, `radial_correlation`} pair is given four different names across the site

**Type:** contradiction
**Severity:** major
**Confidence:** high

**Locations:**
- PAGE: Home, "Main components": *"plus the radial pair `radial_spectrum` (the power spectrum) and `radial_correlation` (its physical-space Wiener–Khinchin dual, the two-point autocorrelation)…"*
- PAGE: api / GBGPeriodicFields, module docstring: *"`Reductions` provides the L²/measure reductions `integral`, `inner`, `weighted_inner`, `l2norm`, and `lpnorm`, plus the radial diagnostics `radial_spectrum` and `radial_correlation`."*
- PAGE: api / Reductions, module docstring: *"`radial_spectrum` and `radial_correlation` — a Fourier-dual pair (Wiener–Khinchin) that resolves `inner` over a radial coordinate…"*
- PAGE: api / Reductions, `weighted_inner`: *"It is thus far cheaper than the radial reductions `radial_spectrum` / `radial_correlation`, which build an $O(N)$ shell-index array and a scatter-add binning pass…"*
- PAGE: api / FiberSections, `with_threading`: *"the grid↔point transfer (`interpolate!`/`anterpolate!`) and the radial diagnostics (`radial_spectrum`/`radial_correlation`) — the kernels with atomic or irregular access…"*

**Description:** "the radial pair" (Home), "the radial diagnostics" (umbrella page, FiberSections — twice), "a Fourier-dual pair (Wiener–Khinchin)" (Reductions' own module docstring), and "the radial reductions" (Reductions' own `weighted_inner` docstring) all name the identical two-function group. None of these is wrong individually, but a reader cross-referencing pages (exactly what the task of building a mental model requires) has no signal that these are the same referent rather than four different groupings — compounded by Finding 1, since "radial diagnostics"/"radial reductions" also sound like they could be sub-families in the already-contested "operation family" taxonomy.

---

## Finding 6 — "module" is used in the abstract-algebra sense once, on a page where "Module" (capitalized, Julia-code sense) is used as a type tag dozens of times

**Type:** clarity
**Severity:** minor
**Confidence:** medium

**Locations:**
- PAGE: api / FieldAlgebra, module docstring: *"- Vector-space and module operations — `add!` and `subtract!` (`+`, `-`), the weighted combination `combine!` (…), real scaling, and scalar-field multiplication and division (…). Addition, weighted combination, and real scaling are the vector-space structure; scalar-field multiplication is the **module action** over the scalar fields."*
- Same page, immediately above: *"`GBGPeriodicFields.FieldAlgebra` — Module"* — the standard Documenter type-tag pattern repeated for every type/function/module on every API page in the site (e.g. `GBGPeriodicFields.Convolution` — Module, `GBGPeriodicFields.DifferentialOperators.gradient!` — Function).

**Description:** "the module action over the scalar fields" invokes the abstract-algebra notion of a module (a vector-space-like structure over a ring, here the ring of scalar fields) — reasonable terminology for a reader with an algebra background, but the *only* place on the entire site this sense of "module" appears, on a page where "Module" is otherwise a Julia-specific type tag used constantly for something unrelated (a source-code module). A reader skimming rather than parsing closely could easily misread "module action" as somehow referring to the Julia module system.

---

## Finding 7 — The tensor-invariant naming is inconsistent between `tr!` ("first tensor invariant") and `det!` ("third principal invariant $I_3$")

**Type:** contradiction
**Severity:** minor
**Confidence:** medium

**Locations:**
- PAGE: api / FieldAlgebra, `tr!`: *"Pointwise over the base, it contracts the two fiber indices to a scalar — the first tensor invariant:"* (no `$I_1$` symbol given).
- PAGE: api / FieldAlgebra, `det!`: *"The determinant is cubic in the tensor's components — the third principal invariant $I_3$, the signed factor by which $A$ scales volumes as a linear map."*
- PAGE: api / FieldAlgebra, module docstring: *"`tr!` the trace, the self-contraction of a tensor's own two indices, and `det!` the determinant, the tensor's third principal invariant."*

**Description:** `tr` and `det` are presumably the first and third members of the same standard numbered sequence of tensor invariants (continuum mechanics' $I_1, I_2, I_3$), but the docs call them by two different adjectives ("tensor invariant" vs. "principal invariant") and give a LaTeX index symbol ($I_3$) only to the second, never introducing $I_1$ for the trace. A reader trying to relate the two operations has to guess these are the same family under different names; the docs never say so explicitly, nor mention why $I_2$ has no counterpart operation (an intentional omission, but the naming drift around it is not).

---

## Finding 8 — "the pair-correlation route" is referenced with a definite article as a known, specific pipeline, but is never introduced anywhere else

**Type:** clarity
**Severity:** minor
**Confidence:** medium

**Locations:**
- PAGE: api / Convolution, `assignment_window`: *"Use it in the pair-correlation route. Depositing $M$ points on the grid with the positive linear assignment (`LalescuSpline(0, 0)`, the 2-point linear kernel used for a density) spreads each point's mass over a tent, so the gridded density is the true density $\rho$ convolved with this window, $\rho_g = \rho \star W$."*

**Description:** "the pair-correlation route" appears exactly once on the whole site, with the definite article implying it is a specific, previously-established procedure — but no page sets it up as a named pipeline beforehand or afterward (it is not in the Home page's vocabulary paragraph, the Notation page, or cross-referenced from `radial_correlation`, which is the natural downstream consumer of a deconvolved density). The paragraph does narrate the individual steps inline, which mitigates the gap, but the label itself reads as though it points to a defined multi-step recipe the reader is assumed to already know.

---

## Finding 9 — "(tensor/fiber) bundle" is the name of the package's whole architecture, but "bundle" itself is never defined on the user-facing site

**Type:** clarity
**Severity:** minor
**Confidence:** medium

**Locations:**
- PAGE: notation, "Base and fiber" table: *"$f$, $g$ | a field — a section of the tensor bundle over the base | —"*
- PAGE: api / FiberSections, module docstring: *"Base-agnostic core of the package's fiber-bundle model. A field (a section over a `Grid3D`) and a collection of off-grid point-values (a section over a `PointSet`) are both sections of a tensor bundle over a base."*
- PAGE: api / Points, module docstring: *"The unstructured base of the package's fiber-bundle model: off-grid sample positions and the field values sampled at them."*
- Contrast PAGE: Home, opening paragraph, which explains "section", "fiber", and "base" but never uses the word "bundle" at all: *"A field — and its off-grid point-values — is a section: one fiber value (a scalar, a vector, or a second-order tensor) attached to every point of a base…"*

**Description:** "fiber-bundle model" / "tensor bundle" is used repeatedly as the name for the package's whole design, but the word "bundle" itself — as opposed to "section", "fiber", and "base", each of which does get an explicit gloss — is never unpacked anywhere in the user-facing docs (its formal meaning presumably lives in the excluded `ARCHITECTURE.md`). A reader can reconstruct roughly what is meant (the base plus the fibers it carries, i.e. exactly what "section" was already defined to mean), but the term is used as though self-evident once the reader is expected to recognize it from differential geometry.

---

## Finding 10 — The word "assignment" is used for two unrelated concepts: a threaded elementwise write, and particle-mesh mass deposition

**Type:** clarity
**Severity:** nit
**Confidence:** low

**Locations:**
- PAGE: api / FiberSections, `threading_cutoff`: *"Here an assignment is a fused elementwise write into field storage — the `_assign!` primitive behind the broadcast route…"*
- PAGE: api / Convolution, `assignment_window`: *"Return the linear (cloud-in-cell) mass-assignment window as a scalar field in spectral representation, on `reference`'s grid and array backend, for deconvolving a gridded point density."*
- PAGE: Home, "Main components": *"`assignment_window` the mass-assignment deconvolution window"*

**Description:** "assignment" in the threading sense (a write into an array) and "(mass) assignment" in the particle-mesh sense (depositing point mass onto a grid, as in `assignment_window`) are unrelated ideas that happen to share a name. Each is glossed adequately at its own point of use, and the compound "mass-assignment" is somewhat self-distinguishing, so this is a low-stakes overlap — but a reader skimming both pages in one sitting could momentarily wonder whether `assignment_window` has anything to do with the CPU-threading "assignment" split (it does not).

---

## Finding 11 — If the API pages are read in the order this document presents them, several types are used before they are defined

**Type:** organization
**Severity:** nit
**Confidence:** low (see caveat)

**Locations:**
- PAGE: Home / PAGE: api, both state the intended reading/dependency order explicitly: *"The include order reflects the dependency layering: `FiberSections` → `Fields` → `FieldAlgebra` → `DifferentialOperators` → `Convolution` → `Points` → `Interpolation` → `Reductions`."*
- The document actually presents the API pages in a different order: Convolution, DifferentialOperators, FiberSections, FieldAlgebra, Fields, GBGPeriodicFields, Interpolation, Points, Reductions (alphabetical by module name).
- Concrete instance: PAGE: api / Convolution, `assignment_window`, cites *"the positive linear assignment (`LalescuSpline(0, 0)`, the 2-point linear kernel used for a density)"* — `LalescuSpline`'s own defining docstring (its `(n, m)` parameters, stencil, and TurTLE pin) does not appear until PAGE: api / Interpolation, later in this document.
- Concrete instance: `ScalarFieldSpectral`, `FieldSpectralMultipliers`, and `TensorFieldPhysical{2}` are used throughout Convolution, DifferentialOperators, and FieldAlgebra as type annotations before the Fields page (fifth in this document's order) defines them.

**Description:** Each individual docstring is largely self-contained via inline prose glosses (e.g. `kernel` is always re-explained as "a scalar field in spectral representation" at its point of use), which substantially mitigates the practical impact — this is why confidence is only low. Flagged because it is a genuine property of the document as given: if it reflects the live site's actual sidebar/browsing order, a first-time reader hits forward references to un-introduced types and schemes; if it is only an artifact of how this consolidated review document was assembled (e.g. alphabetical directory listing rather than the configured navigation order), then it is not a real reader-facing issue and should be discounted. Recommend confirming the live site's actual page order before acting on this one.

---

## Finding 12 — Single-argument $\langle\cdot\rangle$ ("domain average") is used in two narrative pages but is absent from the Notation page's own table

**Type:** clarity
**Severity:** nit
**Confidence:** medium

**Locations:**
- PAGE: notation, "Operators" table lists only the two-argument form: *"$\langle\cdot,\cdot\rangle$ | the normalized $L^2$ inner product | inner"*.
- PAGE: tutorial, "Fiberwise algebra and L²/measure reductions": *"single-argument angle brackets denote that average (here $\langle\sin^2\rangle + \langle\cos^2\rangle + \langle\sin^2\rangle = \tfrac{3}{2}$)"* — introduced and used once.
- PAGE: examples / hist_cpu, "Results": *"With $\langle\cdot\rangle$ the average (over space/time origins), $u$ the Eulerian velocity and $U$ a tracer's velocity,"* — introduced independently a second time, in a different page, with a slightly different gloss ("over space/time origins" vs. the tutorial's implicit domain average).

**Description:** Both introductions are locally adequate (each page glosses the notation where it first appears, consistent with the Notation page's own stated policy that a docstring "introduces a symbol on first use and need not repeat the convention"), so this is low severity. It is included because the two introductions are not quite the same (plain domain average vs. "average over space/time origins") and neither cross-references the other or the Notation page's two-argument entry, so a careful reader collating the two pages could reasonably ask whether $\langle\cdot\rangle$ and $\langle\cdot,\cdot\rangle$ are meant to compose consistently (they do: $\langle f\rangle \equiv \langle f, 1\rangle$-style domain average vs. $\langle f,g\rangle$ the inner product) — a one-line note either on the Notation page or cross-linking the two example pages would close the gap.

---

## Summary table

| # | Finding | Severity | Confidence |
|---|---|---|---|
| 1 | "Operation family" taxonomy contradicts itself across 4+ pages | major | high |
| 2 | Notation page's `k` row is rendered broken/truncated | major | high |
| 3 | `symmetric_gradient` missing from Home page's operator list | major | high |
| 4 | `α`/`α(k)` glyph reused for accumulation weight vs. Parseval multiplicity | major | high |
| 5 | Radial pair named 4 different ways across pages | major | high |
| 6 | "module action" collides with the pervasive "— Module" type tag | minor | medium |
| 7 | `tr`/`det` invariant naming inconsistent ("tensor" vs. "principal" $I_3$) | minor | medium |
| 8 | "the pair-correlation route" never introduced as a named pipeline | minor | medium |
| 9 | "(fiber-/tensor) bundle" never itself defined, only used | minor | medium |
| 10 | "assignment" collides between threading and mass-assignment senses | nit | low |
| 11 | Page order may forward-reference undefined types/schemes | nit | low |
| 12 | Single-argument $\langle\cdot\rangle$ absent from the Notation table | nit | medium |
