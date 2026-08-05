# LaTeX / Typesetting Hat — Findings

Scope: rendered manuscript (`manuscript-full.md`), authored TeX source (`src/*.jl` docstrings,
`docs/*.md`, `docs/src/*.md`, `examples/*.jl`), judged against the CLAUDE.md house rulebook
(imaginary unit, differential, `\partial_{x_i}`, braced fractions, the spacing/`\left`/`\mathbb`
DON'Ts, the silent-rendering-failure micro-rules).

**Method.** Grepped every file for the enforced-DON'T patterns (`\left`/`\right` outside the
sanctioned system brace, `\!` before `\bigl`/`\Bigl`, `\!\!` before `\sum`/`\int`, `\mathbb{}` on
anything but A–Z/`k`, manual `\;`/`\:`/`\,` around a relation/operator, unbraced `\tfrac`/`\frac`
arguments, bare italic operator products for `det`/`tr`/`sym`/`skew`/`dev`/`sin`/`cos`/`exp`/`Re`/
`conj`, bare `\partial_i` instead of `\partial_{x_i}`, bare imaginary units), then read every
`\begin{aligned}`/`\begin{gathered}`/`\begin{cases}` block, every `\bigl`/`\Bigl` pairing, and the
full `notation.md` glossary by hand. The package's own math-authoring discipline is unusually
strict and it shows: nearly every mechanically-checkable rule in the house style comes back clean
(zero stray `\left`/`\right`, zero misapplied `\mathbb`, zero unbraced fractions, zero bare
`\partial_i`, zero bare imaginary units, consistent `\operatorname{}`/`\overline{}`/`\lvert`·`\rvert`
usage, consistent `\mathbf{k}` scoping to the one declared local override). The two findings below
are the genuine misses that survived that sweep.

---

## Finding 1 — Two display formulas in the HIST_CPU example pack independent equations onto one
line with `\qquad`, exactly the anti-pattern the house rule names

- **Type:** typesetting
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - `examples/HIST_CPU.jl:471-476` (source):
    ```
    S^{(E)}(\Delta x) = \tfrac{1}{3}\bigl\langle \lvert u(x+\Delta x) - u(x)\rvert^{2}\bigr\rangle
                      = \tfrac{2}{3}\bigl(C(0) - C(r)\bigr),
    \qquad
    S^{(L)}(\Delta t) = \tfrac{1}{3}\bigl\langle \lvert U(t+\Delta t) - U(t)\rvert^{2}\bigr\rangle
                      = \tfrac{2}{3}\bigl(R(0) - R(\Delta t)\bigr),
    ```
  - `examples/HIST_CPU.jl:483-489` (source):
    ```
    \frac{S^{(E)}(\Delta x)}{\tfrac{11}{9} C_2 \varepsilon^{2/3} \Delta x^{2/3}}
      \quad\text{vs}\quad \frac{\Delta x}{\eta},
    \qquad\qquad
    \frac{S^{(L)}(\Delta t)}{C_0 \varepsilon \Delta t}
      \quad\text{vs}\quad \frac{\Delta t}{\tau_\eta},
    ```
  - Rendered (`manuscript-full.md:4895-4903`, "PAGE: examples / hist_cpu"): both blocks come out
    as one unbroken `\[...\]` line — e.g. `S^{(E)}(\Delta x) = \tfrac{1}{3}\bigl\langle ... \bigr\rangle
    = \tfrac{2}{3}\bigl(C(0) - C(r)\bigr), \qquad S^{(L)}(\Delta t) = \tfrac{1}{3}\bigl\langle ...
    \bigr\rangle = \tfrac{2}{3}\bigl(R(0) - R(\Delta t)\bigr),` — a single very wide formula.
- **Contradicts:** CLAUDE.md, "Silent-rendering-failure micro-rules", item (d): *"a wide display
  formula with `aligned`/`gathered`, never one line packing equations behind `\quad`"* — this is
  that exact anti-pattern, not a paraphrase of it. Both blocks define two independent equations
  (the Eulerian and Lagrangian structure functions; the two K41-normalized ratios) joined only by
  `\qquad`/`\qquad\qquad`, with no `\\` line break and no `aligned`/`gathered` environment, so
  neither has any way to wrap.
- **Description:** Each equation is already non-trivial (a `\tfrac`-scaled `\bigl\langle...\bigr\rangle`
  average equated to a `\bigl(...\bigr)` difference, or a `\frac{...}{...}` ratio compared `\quad
  \text{vs}\quad` against another ratio); concatenating two of them on one horizontal line via
  `\qquad` produces a formula far wider than the page, in flat contradiction of the "no horizontal
  scroll" requirement the same rulebook section states two sentences earlier. This is also the
  Literate-example page the rulebook singles out as "a rendered doc page — sweep and verify it like
  one," so the same standard applies here as to `ARCHITECTURE.md`.
- **Resolution hint:** Wrap each pair in `\begin{aligned}...\end{aligned}` (or `gathered`), one
  equation per line, `\\`-separated — the same idiom the package already uses correctly elsewhere
  (e.g. `src/Reductions.jl:1299`'s `lpnorm` aligned block, or the RK2 `\begin{aligned}` at
  `examples/HIST_CPU.jl:231-238`).

---

## Finding 2 — `k_lo`/`k_hi` written as backtick "code" in two doc pages, but no such Julia
identifier exists (the real parameter names are `wavenumber_low`/`wavenumber_high`)

- **Type:** typesetting
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - `docs/ARCHITECTURE.md:1313-1314` (mirrored at `docs/src/architecture.md:1313-1314`):
    `` `spectral_band(reference, multipliers, k_lo, k_hi)` `` … `` `spectral_cutoff` (now its `k_lo
    = 0` special case …) ``
  - `docs/TESTING.md:503` (mirrored at `docs/src/testing.md:503`): `` the `spectral_band` annular
    band-pass (`spectral_cutoff` as its `k_lo = 0` case, idempotent, …) ``
  - Rendered (`manuscript-full.md:483`, "PAGE: architecture"): `` `spectral_band(reference,
    multipliers, k_lo, k_hi)` `` and `` `k_lo = 0` `` render as literal monospace code, asserting a
    call signature and a keyword name that do not exist.
  - Actual signature, `src/Convolution.jl:1371-1373`: `spectral_band(reference::AbstractFieldSpectral,
    multipliers::FieldSpectralMultipliers, wavenumber_low, wavenumber_high)`; the same docstring
    correctly writes the math as `` ``k_\mathrm{lo} = 0`` `` (`src/Convolution.jl:1384`).
- **Contradicts:** CLAUDE.md, "Silent-rendering-failure micro-rules", item (d): *"a backtick span
  holds only well-formed Julia — a name/type/call/expression — never math that merely looks
  code-ish."* `k_lo`/`k_hi` are not Julia identifiers anywhere in the package (`grep -rn k_lo src/`
  is empty); the source docstring for the very function these lines describe uses the correct
  ``k_\mathrm{lo}`` math span and the correct `wavenumber_low`/`wavenumber_high` code names side by
  side — so the doc pages have a shorthand that disagrees with both the code and the function's own
  docstring.
- **Description:** A reader who takes the backtick span at face value and calls
  `spectral_band(ref, mult, k_lo, k_hi)` or looks for a `k_lo` keyword gets an `UndefVarError`; the
  span is really informal math (the low/high band edge) dressed as code, which is precisely the
  class of silent failure the rule exists to catch — it "looks right" in the source and renders as
  clean monospace, giving no visual signal that it names nothing real.
- **Resolution hint:** Either use the real argument names (`` `spectral_band(reference,
  multipliers, wavenumber_low, wavenumber_high)` ``, `` `wavenumber_low = 0` ``) or drop the
  backticks and write it as math (`` ``k_\mathrm{lo} = 0`` ``), matching `Convolution.jl`'s own
  docstring.

---

## Minor observation (not filed as a separate finding — informational only)

`src/Reductions.jl:1299-1302`'s `lpnorm` `aligned` block ends its third row with a trailing empty
alignment cell — `` \lVert f\rVert_\infty &= \sup_{x} |f(x)| = \max_x |f(x)|, && `` — an unused
`&&` with nothing after it before `\end{aligned}`. Harmless (amsmath tolerates a trailing empty
cell and it renders identically to omitting it) but inconsistent with the two rows above it, which
use the trailing `&&` to carry a real `(\texttt{Grid3D})`/`(\texttt{PointSet})` tag. Nit-level,
low-value to fix; noted for completeness rather than filed as a ranked finding.
