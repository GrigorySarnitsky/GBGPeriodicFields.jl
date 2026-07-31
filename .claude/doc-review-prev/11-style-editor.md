# Panel review — Hat 11: Technical copy-editor (internal uniformity + silent rendering failures)

Sources: `manuscript-full.md` (rendered reader-text, all pages) + raw built HTML under
`docs/build/`. KaTeX renders **client-side** in this Documenter build (math is stored as raw
TeX in the HTML; no epsilon codepoints exist statically), so TeX-glyph differences in the
source are genuinely reader-visible after the browser renders them.

Note on "run-together" text in the manuscript (e.g. `never as *.The pointwise`,
`kernelThe stored`, `WarningAs the inverse`, `$\checkmark$Backs`): I verified these against the
raw HTML and they are **consolidation artifacts only** — the HTML has proper block structure
(`</ul><p>…`, `<header class="admonition-header">…`, separate `<p class="math-container">` for
display math). They are NOT defects and are not reported. Likewise the 4 "·" glyphs on the
examples page are the `<title>`/`<meta>` "Examples · GBGPeriodicFields" separator, not prose.

---

## Finding 1 — BLOCKER: Performance page §6 and §7 paragraphs render catastrophically broken (inverted code spans, stripped underscores, collapsed spaces, stray backtick)

- type: format
- severity: blocker
- confidence: high

**Locations (PAGE: performance):**

- §6 "…and per-platform results", lead paragraph "Across vendors the reductions class shows the
  widest gap…". Raw HTML:
  `the radial diagnostics (`radial</em>spectrum<code>/</code>radial<em>correlation<code>) bin on an Atomix scatter-add histogram, and CUDA&#39;s atomic throughput far outruns RDNA3&#39;s —</code>radial</em>spectrum<code>at 256³ … in</code>Float32<code>, widening to ≈32× in</code>Float64<code>(92 → 2.9 ms) … matrix is in</code>RESULTS.md`:</p>`
- §7 "Current coverage and known gaps", paragraph "The decision-27 additions (…)". Raw HTML:
  `decision-27 additions (<code>combine!</code>, <code>det!</code>, `symmetric</em>gradient!<code>,</code>weighted<em>inner<code>) are wired … for</code>symmetric</em>gradient!<code>/</code>weighted_inner<code>); they enter the committed</code>RESULTS.md` table …`

**Description.** Two whole paragraphs on the Performance page suffer a CommonMark parse failure:
the paragraph contains an **unbalanced (odd) number of inline-code backticks**, which inverts
every code span downstream — prose gets wrapped in `<code>` (rendered monospace) while the
intended code tokens fall into plain text. Reader-visible consequences:
1. `radial_spectrum` / `radial_correlation` render as **"radialspectrum" / "radialcorrelation"**
   (underscores eaten, partly italicised via a spurious `<em>`); a reader copying the name gets
   the wrong identifier.
2. `symmetric_gradient!` and `weighted_inner` render as **"symmetricgradient!" / "weightedinner"**
   in §7 — and, jarringly, `weighted_inner` renders **correctly** two words later in the same
   sentence, so the two spellings sit side by side.
3. `Float32` / `Float64` lose their surrounding spaces and their monospace ("…in`Float32`,"
   collapses to run-in normal-font text), while the surrounding prose is shown in monospace.
4. A **stray literal backtick** renders before the colon: "…matrix is in`RESULTS.md`:" and
   "…committed`RESULTS.md` table". (Confirmed 4 stray literal backticks on the page.)

This is the only page in the whole site with this failure (mangled code/em adjacency count = 4,
all on performance; the 4 stray backticks on `examples/hist_cpu` are legitimate literal backticks
inside Julia code blocks, not a defect). It is on a key reference page and is misleading, hence
blocker.

**resolution_hint:** Rebuild the two paragraphs with a space on each side of every inline-code
span (the source jams them: "outruns RDNA3's —`radial_spectrum`at 256³", "in`Float32`,",
"global`Float64`atomics", "for`combine!`/`det!`") and balance the backticks — the odd/unpaired
backtick (the tail shows as the literal `` ` `` before "RESULTS.md`:") is what inverts everything.
Add `docs/make.jl`-side guard or grep the built HTML for `</code>[A-Za-z]+<em>` and stray `` ` ``.

---

## Finding 2 — MINOR: Levi-Civita symbol is `\epsilon_{ijk}` on the Formalization page but `\varepsilon_{ijk}` on every other page

- type: typesetting
- severity: minor
- confidence: high

**Locations:**

- PAGE: formalization, "Fiberwise algebra": `(u\times v)_i &= \epsilon_{ijk} u_j v_k` and
  determinant `\det A=\epsilon_{ijk}A_{1i}A_{2j}A_{3k}=I_3` — both use `\epsilon` (KaTeX renders
  the **lunate** ϵ).
- PAGE: api / DifferentialOperators, `curl!`: "with `\varepsilon_{ijk}` the Levi-Civita symbol,
  `(\nabla\times u)_i = \varepsilon_{ijk} \partial_{x_j} u_k`".
- PAGE: api / FieldAlgebra, `cross!`: `(u \times v)_i = \varepsilon_{ijk} u_j v_k`; `det!`:
  `\det(A) = \varepsilon_{ijk} A_{1i} A_{2j} A_{3k}`.
- PAGE: api / FiberSections, `_det_tensor_rhs`: `\det(A) = \varepsilon_{ijk} A_{1i} A_{2j} A_{3k}`.

Raw-TeX confirmed in HTML: formalization has 2 `\epsilon`; FieldAlgebra has 4 `\varepsilon`, 0
`\epsilon`.

**Description.** The same tensor (the Levi-Civita/permutation symbol) is glyphed two different
ways: lunate ϵ (`\epsilon`) only on the Formalization page, varepsilon ε (`\varepsilon`)
everywhere else, including the SAME two operations (cross product, determinant) whose formulas
appear on both surfaces. "One notation per concept" is broken across pages; the majority style is
`\varepsilon`, so the Formalization page is the outlier. (Separately, `\varepsilon` also carries
the dissipation rate and the NUFFT tolerance ε, but those are disambiguated by context and are
conventional; the actionable issue is the Levi-Civita glyph split.)

**contradicts:** formalization `(u\times v)_i = \epsilon_{ijk} u_j v_k` vs FieldAlgebra
`(u \times v)_i = \varepsilon_{ijk} u_j v_k` — axis: which epsilon glyph denotes Levi-Civita.

**resolution_hint:** Change the two `\epsilon_{ijk}` on the Formalization page to `\varepsilon_{ijk}`.

---

## Finding 3 — MINOR: the L² inner-product's base/measure label is written three ways across the site

- type: typesetting
- severity: minor
- confidence: high

**Locations:**

- Abstract text subscript `\text{grid}` / `\text{pts}` on `\langle\cdot,\cdot\rangle` — PAGE:
  architecture §10 (`\langle a, b\rangle_{\text{pts}}`, `\langle f, g\rangle_{\text{grid}}`) and
  PAGE: formalization ("Declarations": `\langle a, b\rangle_{\text{pts}}`,
  `\langle f, g\rangle_{\text{grid}}`). (13× `\text{grid}`, 12× `\text{pts}` in the manuscript.)
- Code-name subscript `\texttt{PointSet}` / `\texttt{Grid3D}` on `\langle\cdot,\cdot\rangle` —
  PAGE: api / Interpolation, module docstring:
  `M \langle Wf, q \rangle_{\texttt{PointSet}} = … = N \langle f, W^\top q \rangle_{\texttt{Grid3D}}`.
- Code-name trailing annotation `(\texttt{Grid3D})` / `(\texttt{PointSet})` after the formula —
  PAGE: api / Reductions (`integral`, `inner`, `l2norm`, `lpnorm`), e.g.
  `\int_\Omega f \,\mathrm{d}\mu = \frac{|\Omega|}{N} \sum_{x} f(x) \quad (\texttt{Grid3D})`.
  (5× `\texttt{Grid3D}`, 5× `\texttt{PointSet}`.)

**Description.** The base/measure a pairing is taken over is labelled with an abstract text
subscript (`\text{grid}`/`\text{pts}`) in the design docs, but with the concrete code type name
(`\texttt{Grid3D}`/`\texttt{PointSet}`) in the API docstrings — and the Interpolation docstring
even uses the code name as a **subscript on ⟨·,·⟩**, i.e. a code identifier sitting inside a math
span (the one construction the house style otherwise routes to plain-text labels). Same concept,
two conventions on the same `\langle\cdot,\cdot\rangle` operator.

**contradicts:** architecture `\langle f, g\rangle_{\text{grid}}` vs Interpolation
`\langle f, W^\top q \rangle_{\texttt{Grid3D}}` — axis: how the pairing's base is subscripted.

**resolution_hint:** Pick one. Simplest is to make the Interpolation subscripts
`\text{pts}`/`\text{grid}` to match the design docs; the Reductions trailing `(\texttt{Grid3D})`
annotations are a distinct construct and may stay, but note they are the reason the code-name-in-
math style leaked in.

---

## Finding 4 — NIT: imaginary unit is `\mathrm{i}` in 47 places but `\mathrm i` (no braces) in 12

- type: typesetting
- severity: nit
- confidence: high

**Locations:** `\mathrm i` (no braces) — PAGE: architecture (`e^{-\mathrm i k\cdot h}` in §Home
components / §11 / decision 28; `\tfrac{\mathrm i}{2}` in decision 27) and PAGE: api / Convolution
(`\mathrm{e}^{-\mathrm{i} k \cdot h} = \prod_a[\cos(k_a h_a) - \mathrm i \sin(k_a h_a)]` — note
this one line mixes both `\mathrm{i}` and `\mathrm i`). `\mathrm{i}` (braced) — the majority, e.g.
all of DifferentialOperators, Formalization, the Notation page.

**Description.** Both forms render identically (upright roman i), so this is **invisible to a
reader** — a pure source-style inconsistency. Reported only for completeness of the uniform-
notation sweep; the Notation page's own rule ("Upright, always") is satisfied either way. The
Convolution `translation_kernel` display formula uses both spellings in one equation, which is the
clearest single instance.

**resolution_hint:** Normalise to `\mathrm{i}` (the braced majority). No rendered change; source
tidiness only.

---

## Finding 5 — NIT: `\left…\right` delimiters used in several formulas despite the Notation page declaring `\Bigl…\Bigr` preferred

- type: typesetting
- severity: nit
- confidence: medium

**Locations:**

- PAGE: notation, "Conventions" table: "Delimiters | `\Bigl(\;\Bigr)` | Fixed-size \Bigl … \Bigr
  is preferred to auto-sized \left … \right, which over-inflates around subscripted sums."
- Actual `\left…\right` in formulas: PAGE: api / Convolution `spectral_cutoff`
  (`\hat g(k) = \mathbb 1\!\left[ |k| \le k_c \right]`); PAGE: architecture (decision 13
  co-spectra); PAGE: testing (§ coverage formula); PAGE: api / FieldAlgebra. Meanwhile
  Formalization/Reductions/DifferentialOperators use `\Bigl…\Bigr` (4 / 5 / 1 occurrences).

**Description.** The site states a delimiter-sizing preference but doesn't follow it uniformly.
Visual impact is negligible in the cited cases (the bracketed content is short, so `\left[\right]`
sizes the same as fixed brackets), so this is a nit, but it is a genuine stated-rule-vs-practice
inconsistency squarely in the copy-editing remit.

**resolution_hint:** Either switch the handful of `\left…\right` to `\Bigl…\Bigr`, or soften the
Notation-page wording from "preferred" to "preferred around subscripted sums" (which is the actual
rationale given).

---

## Finding 6 — NIT: allocating-wrapper docstrings — `sym`/`skew`/`dev` break the "Allocating form of `f!`:" opener skeleton

- type: organization
- severity: nit
- confidence: medium

**Locations (PAGE: api / FieldAlgebra):**

- Majority opener: `gradient`, `divergence`, `curl`, `laplacian`, `dot`, `cross`, `tr`, `det`,
  `norm` all lead "**Allocating form of `f!`**: allocate the result and return it …" and close
  "See `f!` for the componentwise …".
- `sym` / `skew` / `dev` instead lead: "**Allocate the result and compute** the symmetric /
  skew-symmetric / deviatoric part of a second-order tensor: fiberwise for a tensor field, or
  directly on a single `FiberTensor2` value. See `sym!` for the defining formula …".

**Description.** The allocating-form docstrings share a tight skeleton ("Allocating form of
`f!`: …") across the whole module except `sym`/`skew`/`dev`, which use a different opening
sentence. The divergence is partly justified (they uniquely also accept a bare `FiberTensor2`),
but the opener could still be aligned. (The transform pair `to_physical`/`to_spectral` also opens
differently — "…returning a newly allocated … field. This is the allocating form of `to_physical!`."
— but they are full restatements, not thin `@ref` wrappers, so that divergence is defensible.)

**resolution_hint:** Optionally reword the sym/skew/dev opener to "Allocating form of `sym!`: …
(also accepts a bare `FiberTensor2`)" to match the module skeleton.
