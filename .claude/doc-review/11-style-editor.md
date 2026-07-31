# Style / Copy-Editor Review — GBGPeriodicFields rendered docs

Hat: **technical copy-editor enforcing internal uniformity** (notation rendering, docstring
skeleton, heading levels, tables, citation format, register, and silent HTML rendering failures).

Scope read: the full reader-text consolidation (`manuscript-full.md`, all pages) plus the raw
built HTML under `docs/build/**/index.html` (18 pages, enumerated by `find . -name index.html`
inside `docs/build`, since every page lives at `<section>/index.html`, not `<section>.html`).

Overall impression: the corpus is unusually disciplined — the imaginary unit is upright
`\mathrm{i}` everywhere, the differential is upright `\mathrm{d}` everywhere, `\partial_{x_i}`
subscripting is used with only one defensible one-off exception, `\mathbb{}` is applied only to
`P`/`R`, `\left`/`\right` appears nowhere outside its one documented exception, DOI/title pairs
are verbatim-identical at every one of their 19 occurrences, and every one of the ~235 docstring
blocks across the 9 module pages has exactly one matching "source" link. Against that high bar,
five genuine findings survived.

---

## Finding 1 — Notation-page table row silently loses content (literal `|` inside a math span)

- **Type:** format (silent HTML rendering failure)
- **Severity:** blocker
- **Confidence:** high

**Location:** PAGE "Notation" → "Base and fiber" table, the row for the wavenumber-vector symbol
`k`.

**Evidence (raw HTML, `docs/build/notation/index.html`):**
```html
<tr><td style="text-align: right"><span>$k$</span></td>
    <td style="text-align: right">a wavenumber vector (<span>$k_a$</span> is its <span>$a$</span>-th component, ``</td>
    <td style="text-align: right">k</td></tr>
```
Reader-text form (`manuscript-full.md`, "Base and fiber" table): *"`$k$` | a wavenumber vector
(`$k_a$` is its `$a$`-th component, ``\` | k"* — i.e. the row visibly ends mid-sentence on a bare,
orphaned double-backtick, and the "Code" column — which for every other row in this exact table
holds a real backtick-styled identifier (`Grid3D`, `prod(grid_size)`, `npoints`,
`translation_kernel`, `to_spectral(f)`) — instead shows the single unstyled character `k`.

**Description:** every other row in this table follows "Symbol | Meaning | Code" cleanly. This
row's Meaning cell tries to give the magnitude as an inline math span containing the literal
absolute-value bars, `` ``|k|`` ``. Markdown table syntax treats any literal `|` as a column
delimiter — *even one sitting inside a double-backtick math span* — so the two pipes of `|k|`
silently create two extra columns, and everything past the header's declared column count
(`Symbol | Meaning | Code`) is discarded. The casualties: the Meaning cell loses "its magnitude)"
and the Code cell loses `` `FieldSpectralMultipliers` `` entirely, replaced by the stray fragment
"k" between the two pipes. Two rows above it, the "Operators" table on this same page gets this
exactly right for the analogous symbols (`` \lvert\cdot\rvert ``, `` \lVert\cdot\rVert ``) by using
the pipe-free LaTeX delimiter commands instead of a literal `|` — so the fix pattern already exists
on the very same page, just not applied to this one row.

**Resolution hint:** replace the literal `` ``|k|`` `` with `` ``\lvert k\rvert`` `` (matching the
Operators table's own convention two sections down), or move the pipe/backtick text out of the
table entirely.

---

## Finding 2 — The wavenumber vector is bold in the worked example, plain everywhere else

- **Type:** contradiction
- **Severity:** major
- **Confidence:** high

**Locations:**
- PAGE "Examples" (`hist_cpu`), "Method (rotational form)": *"…`$\omega = \nabla\times u$` for the
  vorticity, **`$\mathbf{k}$`** for the wavenumber vector and `$\kappa = \lvert\mathbf{k}\rvert$`
  for its magnitude…"* — and reused bold four more times on the same page: `$w(\mathbf{k})$`,
  `$\lvert\mathbf{k}\rvert^{2}$` (×2), `$\lvert\mathbf{k}\rvert = 1$`.
- PAGE "Notation" → "Base and fiber" table (the site's own declared symbol glossary, whose stated
  purpose is that "a docstring introduces a symbol on first use and need not repeat the
  convention"): *"`$k$` | a wavenumber vector (`$k_a$` is its `$a$`-th component, …) |
  `FieldSpectralMultipliers`"* — plain, non-bold italic.
- PAGE "api/DifferentialOperators" → `gradient!`: *"`$\widehat{(\nabla\varphi)_i}(k) = \mathrm{i}
  k_i \hat\varphi(k)$`"* — plain `k`, and this exact plain-italic convention recurs without
  exception in every other operator/kernel/reduction formula site-wide (`curl!`, `laplacian!`,
  `helmholtz_projection!`, `convolve!`, `spectral_cutoff`, `translation_kernel`, `radial_spectrum`,
  …) and in every formula of "Architecture" and "Formalization".

**Contradicts:** bold-face (`\mathbf{k}`, hist_cpu) vs. plain-italic (`k`, every other page
including the site's own Notation glossary) rendering of the identical "wavenumber vector"
concept.

**Description:** a site-wide check turned up exactly two uses of `\mathbf{}` anywhere in the
rendered corpus: the correct indicator-function use `\mathbf{1}` in `spectral_cutoff`'s docstring,
and this one. Every other page — including the page whose entire job is to fix "the symbols used
throughout the docstrings and the design documents" — binds and renders `k` as plain italic. A
Literate example page is documented project policy to be read and checked "like a rendered doc
page," so a reader moving from the API/Notation surface into the worked example sees the same
object drawn two different ways with no explanation.

---

## Finding 3 — One citation on the whole site carries no clickable DOI/link

- **Type:** citation
- **Severity:** minor
- **Confidence:** high

**Location:** PAGE "Architecture", §13 decision 19 ("The measure taxonomy").

**Quote:** *"The math anchor (Grafakos, *Classical Fourier Analysis*, Thm 2.5.10): on a uniform
periodic box every homogeneous (translation-invariant) linear operator is a Fourier multiplier…"*
— rendered with no `<a href>` anywhere on "Grafakos" or "Classical Fourier Analysis" (verified
directly in the raw HTML around every occurrence of "Grafakos" on the page).

**Contrast:** every other citation on the site — 10 distinct works, 19 total appearances, checked
programmatically for DOI/title consistency and found verbatim-identical at every occurrence —
renders as a clickable `[*Title*](https://doi.org/…)` link, right down to the other citations in
this exact same decision-log entry. Grafakos is not an incidental aside either: it is invoked with
a specific theorem number as the load-bearing justification for an entire named design decision,
i.e. exactly the class of citation this project's own convention says gets a full linked
reference (the alternative — an `openlibrary.org` link for a book with no DOI — is also unused
here).

**Description:** the sole reference on the site without the "every reference carries a clickable
DOI on its title" treatment the other ten receive.

---

## Finding 4 — Formalization's section headings bake raw Markdown link syntax into their anchor IDs

- **Type:** format (silent HTML rendering failure)
- **Severity:** minor
- **Confidence:** high

**Location:** PAGE "Formalization" — all 7 of its `##`-level section headings that name an
Architecture section (every H2 except "Declarations").

**Evidence (raw HTML, representative of all 7):**
```html
<h2 id="Representations-and-transforms-(Fields,-[Architecture](architecture.md)-§4)">
  <a class="docs-heading-anchor" href="#Representations-and-transforms-(Fields,-[Architecture](architecture.md)-§4)">
    Representations and transforms (<code>Fields</code>, <a href="../architecture/">Architecture</a> §4)
  </a>
  …
</h2>
```
The other six (`Fiberwise-algebra-(FieldAlgebra-/-FiberSections,-[Architecture](architecture.md)-§2,-§6)`,
`Differential-operators-(…)-§4)`, `Convolution-(…)-§11)`, `Reductions-(…)-§12)`,
`Interpolation-/-anterpolation-(…)-§10)`, `Spectral-transfer:-…-(…)-§10,-decision-23)`) all carry
the identical defect.

**Description:** the *visible* heading text renders correctly (plain "Architecture" as working
link text), but the heading's own `id`, its self-link, its permalink anchor, and its entry in the
left-sidebar table of contents are all built from the *raw, unrendered* Markdown source of the
heading — literally embedding the source's square brackets, parentheses, and the `.md` extension
(`[Architecture](architecture.md)`) into a URL fragment — because the heading contains an inline
Markdown link and the anchor-slug generator does not resolve it first. This is silent: the page
never visibly breaks, but the permalink icon, a bookmarked/shared section link, and the sidebar
navigation for this page all carry a garbled fragment a reader would not expect to see in their
address bar. Separately (same root cause, different symptom): the "Architecture" link itself
always resolves to the top of the Architecture page, never to the specific `§4`/`§10`/`§11`/`§12`
named immediately next to it, so the deep-link the parenthetical promises is not actually
delivered on any of the 7 headings.

**Resolution hint:** drop the inline link from inside the heading text (state the module/§ in
plain text, and link "Architecture" only in the following paragraph) — the pattern every other
page on the site already uses.

---

## Finding 5 — "Internal API" subheading structure (Types/Functions split) is inconsistent across API pages

- **Type:** organization
- **Severity:** minor
- **Confidence:** medium

**Locations (heading hierarchy extracted from all 8 API module pages):**
- `api/Fields` and `api/Points`: "Internal API" (H2) → "Types" (H3) → "Functions" (H3) — both
  pages have real internal `Type`s (`FieldPhysicalBroadcastStyle`/`FieldSpectralBroadcastStyle`;
  `PointValuesBroadcastStyle`) alongside internal functions/methods, and split them accordingly.
- `api/DifferentialOperators` and `api/FieldAlgebra`: "Internal API" (H2) → "Functions" (H3) —
  a lone H3 added even though neither page's Internal API section documents any Type (only
  Methods), so there is nothing for "Functions" to be split from.
- `api/FiberSections`, `api/Convolution`, `api/Reductions`: "Internal API" (H2), **no H3 at all** —
  the functions-only case handled the other way from `DifferentialOperators`/`FieldAlgebra` above.
- `api/Interpolation`: "Internal API" (H2), **no H3** — yet this section documents a real Type,
  `AbstractSplineScheme` ("Supertype of the physical-domain local interpolation schemes…"),
  alongside five Methods (`_axis_weights`, `_fornberg`, `_hermite_weight_matrix`,
  `_lagrange_weight_matrix`, `_locate`) — structurally the same "Type + Methods" mix that
  `Fields`/`Points` use to justify their Types/Functions split, but it does not receive one.

**Description:** whether (and how) an "Internal API" section gets subdivided by heading level
is not applied by one rule across the eight module pages. `Interpolation` is the clean case: it
has exactly the situation (`Types` + `Functions` mixed) that earns a heading split on `Fields` and
`Points`, yet is formatted like the functions-only pages instead.

---

## Checks run clean (no findings)

For completeness, since a large fraction of this hat's mandate is negative evidence:
`\mathrm{i}`/`\mathrm{d}` upright rendering (site-wide, no bare-italic exceptions); `\partial_{x_i}`
subscripting (one defensible bare `$\partial_x \sin x = \cos x$` 1-D scalar illustration in
Testing, not a multi-axis package formula); `\mathbb{}` arguments restricted to `P`/`R`; `\left`/
`\right` absent outside its one sanctioned `\left\{ … \right.` use; manual `\;`/`\,`-around-`=`
and `\!\bigl`/`\!\Bigl` spacing violations (none found); code identifiers accidentally sitting
bare inside a math span (none found — the `\texttt{}` discipline holds); every one of ~235
docstring blocks across 9 module pages has exactly one matching GitHub source link; every table on
the site (`performance` ×8, `notation` ×3) has matching header/row cell counts except the one row
in Finding 1; every DOI↔title pair (10 works, 19 occurrences) is verbatim-identical across every
page it appears on; author-count citation formatting (`A & B`, `A, B & C`, `First et al.` at 4+)
correctly applied throughout; "knob"/"tweak" register violations (none); "per-step"/"every
step"/"hot loop" cadence-framing language inside actual docstrings (none — confined to
`ARCHITECTURE.md`/`PERFORMANCE.md`, which the project's own rules explicitly exempt);
particle/tracer terminology inside the package's own API (none — all such mentions are
explanatory contrasts, citations of external literature, or inside the `hist_cpu` example, which
is explicitly consumer code); constructor-first ordering for every type docstring; the
"Allocating form of `X!`: … See `X!` for …" wrapper skeleton applied consistently across 13
allocating/`!` pairs (the `sym`/`skew`/`dev` and bare-operator `+ - * /` wrappers use a visibly
different lead-in, but for a defensible reason — they cover an extra bare-`FiberTensor2` method or
route to more than one `!` home — so not reported as a defect).
