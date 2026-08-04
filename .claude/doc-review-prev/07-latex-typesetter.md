# LaTeX / mathematical-typesetting review — house-style enforcement

Hat: **latex-typesetter**. Scope: typesetting idiom only (not the mathematics, not the
normalization, not the prose) — enforced against `CLAUDE.md`'s "Math in docstrings and doc
pages", "Silent-rendering-failure micro-rules", "Math spacing and command support", and "One
notation per concept" sections, read as authoritative. Both the rendered manuscript
(`manuscript-full.md`) and the authored TeX source (`src/*.jl`, `docs/*.md`, `docs/src/*.md`,
`examples/*.jl`) were read; every finding below is anchored at its source `file:line`.

Method note: `\left`/`\right` (zero occurrences anywhere, including the sanctioned
`\left\{…\right.` exception — never used), `\!` misuse (only the sanctioned `\sim\!`), `\!\!`
before `\sum`/`\int` (zero), `\mathbb{}` on anything but `A`–`Z`/`k` (zero), unbraced
`\tfrac`/`\frac` arguments (zero — every numerator and denominator is braced), bare operator
names as letter-products (`det(`, `tr(`, `sin(`, `cos(`, `exp(`, `log(`, `max(`, `min(`,
`sinc(`, `conj(` — zero unwrapped instances; all correctly `\det`, `\operatorname{tr}`, `\sin`,
etc.), the bare imaginary unit and bare differential `d` (zero — `\mathrm{i}` and `\mathrm{d}`
used with no exceptions found), formulas wrapped in single backticks instead of double
(zero), inline math wrapping onto a list-marker line (zero), and delimiter-pair balance
(`\lvert`/`\rvert`, `\lVert`/`\rVert`, `\lfloor`/`\rfloor`, `\langle`/`\rangle`, `\bigl`/`\bigr`,
`\Bigl`/`\Bigr` — every pair balanced, both corpus-wide and per individual formula) were all
swept exhaustively (extracted every one of the corpus's ~2000 inline/display math spans and
LaTeXStrings labels into one file and grepped/parsed it) and came back **clean** — the house
set is very well enforced overall. The findings below are the exceptions.

---

## Finding 1 — Table cell containing a literal `|k|` breaks the Notation-page glossary table

**Type:** typesetting
**Severity:** blocker
**Confidence:** high

**Locations:**
- SOURCE — `docs/src/notation.md:32` (the only copy; this file is hand-maintained, not
  generated — unlike `architecture.md`/`formalization.md`/`performance.md`/`testing.md` under
  `docs/src/`, which `docs/make.jl`'s `copy_rationale_pages()` overwrites from `docs/*.md` on
  every build):
  ```
  | ``k`` | a wavenumber vector (``k_a`` is its ``a``-th component, ``|k|`` its magnitude) | `FieldSpectralMultipliers` |
  ```
- OUTPUT — the rendered manuscript, Notation page, "Base and fiber" table:
  ```
  $k$ | a wavenumber vector ($k_a$ is its $a$-th component, `` | k
  ```
  (the row stops dead after "component,"; "its magnitude)" and the entire third cell,
  `` `FieldSpectralMultipliers` ``, never appear — swallowed by the parse.)

**Description:** the cell's math span `` ``|k|`` `` contains two literal pipe characters. In a
GFM/CommonMark table (this is a top-level table, not indented inside a list item), an
unescaped `|` inside a cell — even one meant as an absolute-value bar inside a math span — is
counted as a column delimiter, so the parser sees more columns than the header declares and
the row is garbled/truncated. This is precisely the failure class `CLAUDE.md` itself
documents under "Markdown tables must be top-level": *"keep literal `|` out of cells (a `|` —
even inside `` `` `` math, like a norm/abs bar — is counted as a column delimiter). Bit twice:
the decision-18 and decision-19 tables."* This is now a **third**, currently-live instance —
and it evades the existing guard: `grep -rnE '^[[:space:]]+\|[-:| ]+\|' docs` only matches an
*indented* separator row (a table nested in a list item), and this table is top-level, so the
guard returns clean while the page itself is broken. Every other row in the same table correctly
uses `\lvert\Omega\rvert` (line 29) for an absolute-value-like bar — this row is the one
outlier that used a literal `|` instead.

**Contradicts:** N/A (a self-contained source→render break, not a cross-location disagreement).

**Resolution hint:** replace `` ``|k|`` `` with `` ``\lvert k\rvert`` `` (matching the
`\lvert\Omega\rvert` convention already used two rows above in the same table), and extend the
existing top-level-table guard to also catch a bare `|` inside a `` `` `` `` span on an
un-indented table row (not just an indented one).

---

## Finding 2 — Code identifiers embedded in formulas alternate between `\texttt{}` and `\mathrm{}`

**Type:** typesetting
**Severity:** major
**Confidence:** medium-high (very high for the `inner` case specifically, quoted below;
medium for the full scope of the class)

**Locations — the clean, direct contradiction (the same identifier, two treatments):**
- `src/Reductions.jl:993` — `` ``C(0) = \\langle |f|^2\\rangle = \\texttt{inner}(f, f)`` `` (also
  lines 728, 994, 1012 — all `\texttt{inner}`).
- `docs/ARCHITECTURE.md:999` — `` ``M \mathrm{inner}(Wf, q) = N \mathrm{inner}(f, W^\top q)`` ``
  (also lines 1032, 1043, 1052, 1053, 1105, and `docs/TESTING.md:319,332,336` — all
  `\mathrm{inner}`, never `\texttt{inner}`).

**Locations — the wider pattern (one identifier, one treatment, but the wrong one per the house
rule, and never the type-name treatment used elsewhere):**
- `src/Convolution.jl:154` — `` ``\widehat{\mathrm{destination}}(k) = \alpha \hat f(k) \hat g(k) + \beta \widehat{\mathrm{destination}}(k).`` ``
  — `\mathrm{destination}` recurs identically in `src/Convolution.jl` (×4), `src/DifferentialOperators.jl`
  (×6), `src/FieldAlgebra.jl` (×3+), `src/Reductions.jl`'s `\mathrm{dest}`/`\mathrm{dst}` variants
  (×19 combined) — **44 instances total, never once as `\texttt{destination}`** (confirmed:
  zero matches for `\texttt{dest` anywhere in the corpus).
- Similarly `\mathrm{mean}` (×14), `\mathrm{integral}` (×4), `\mathrm{dot}` (×2), `\mathrm{tr}` (×1),
  and `docs/ARCHITECTURE.md:1237` — `` ``E(k) = \tfrac{1}{2} \mathrm{radial\_spectrum}`` `` (the
  function's own name, escaped underscore and all, wrapped in `\mathrm{}`).

**Contrast — the house rule is followed correctly for *type* names:** `\texttt{Grid3D}` (×8),
`\texttt{PointSet}` (×8), `\texttt{field}` (×2), `\texttt{fiber\_map}` (×2), e.g.
`docs/ARCHITECTURE.md:1019` `` `\mathrm{integral}(f) = \int_\Omega f\,\mathrm{d}x = (\lvert\Omega\rvert/N)\sum f`` (\texttt{Grid3D})`` ``
— in the very same formula, the type-name annotation is (correctly) `\texttt{}` while the
function name is (per this finding) `\mathrm{}`.

**Description:** `CLAUDE.md`'s "Silent-rendering-failure micro-rules" state plainly: *"a code
name that must appear inside a formula is wrapped `` \texttt{gradient} ``"* — and
`docs/src/notation.md` itself states the stronger form: *"a code identifier always appears in
`backticks` and never inside a math span."* `destination`/`dest`/`dst`/`inner`/`mean`/`integral`/
`dot`/`tr`/`radial_spectrum` are literal Julia identifiers (parameter and function names, several
with underscores confirming they're meant as code, not English words) placed inside formulas via
`\mathrm{}`, which renders in the ordinary upright-roman math face — visually different from the
monospace `\texttt{}` face used for `Grid3D`/`PointSet`/`field`/`fiber_map`, and different from how
the same identifier is shown in backticks everywhere in prose. The `inner` case removes any doubt
that this is a real inconsistency rather than a hypothetical one: the *same* function, in formulas
of the *same shape* (`inner(f,g) = …`), renders in two different fonts depending on which file the
reader is on.

**Contradicts:** `src/Reductions.jl:993` (`\texttt{inner}`) vs. `docs/ARCHITECTURE.md:999`
(`\mathrm{inner}`) — same code identifier `inner`, same syntactic role (a function call inside a
formula), two different math-mode font commands. Axis: font-command choice for an embedded code
identifier.

**Resolution hint:** pick one convention and sweep the whole class to it — either (a) `\texttt{}`
uniformly, per the literal `CLAUDE.md` text (and matching the four already-correct instances), or
(b) if the intent really is a deliberate split — `\texttt{}` for type names, `\mathrm{}` for
function/variable names used as formula-level "named quantities" — write that split down as an
explicit, documented exception to the blanket rule (since right now nothing records it, and
`inner` itself violates whichever half of the split is intended). Either way, `inner` needs to
converge on one spelling.

---

## Finding 3 — LaTeXStrings plot-axis labels insert thin spaces between juxtaposed factors, contradicting the house spacing rule — and it ships in the published figures

**Type:** typesetting
**Severity:** major
**Confidence:** high

**Locations:** `examples/hist_postprocess.jl:155,172,176,193`:
```
155:             ylabel = L"S^{(E)}(\Delta x)\,/\,\bigl(\tfrac{11}{9}\,C_2\,\varepsilon^{2/3}\,\Delta x^{2/3}\bigr)",
172:             ylabel = L"S^{(L)}(\Delta t)\,/\,(C_0\,\varepsilon\,\Delta t)",
176:  mark_scale!(plt, sqrt(τ_η * τ_u) / τ_η, L"\sqrt{\tau_\eta\,\tau_u}/\tau_\eta", 1.20 * ymax)
193:        label = L"C_K\,\varepsilon^{2/3}\,\kappa^{-5/3}\ \mathrm{(K41)}")
```

**Description:** `docs/src/notation.md`'s "Conventions" table states the Spacing row in absolute
terms: *"Adjacent factors sit side by side (`` ``C_K \varepsilon^{2/3} \kappa^{-5/3}`` ``), never
separated by a thin space; a thin space appears only before the differential above."* Line 193
above is *that exact formula* — the notation page's own worked example of correct
juxtaposition — but here it is typeset with `\,` between every factor (`C_K\,\varepsilon^{2/3}\,\kappa^{-5/3}`)
and again around a `/` in lines 155/172/176. This is not inert source text: `hist_postprocess.jl`
is not itself Literate-processed into a doc page (only `examples/HIST_CPU.jl` is, per
`docs/make.jl:31`), but these `L"…"` strings are the literal axis labels PGFPlotsX/LaTeX typeset
directly into the PNG figures embedded in the rendered `examples/hist_cpu` page (the "Results"
section) — so the extra spacing is not a hypothetical source-only nit, it is baked into the
published structure-function and energy-spectrum plots.

**Contradicts:** `docs/src/notation.md:19` — *"Adjacent factors sit side by side
(`` ``C_K \varepsilon^{2/3} \kappa^{-5/3}`` ``), never separated by a thin space"* — vs.
`examples/hist_postprocess.jl:193` — `` L"C_K\,\varepsilon^{2/3}\,\kappa^{-5/3}\ \mathrm{(K41)}" `` —
the identical formula, opposite spacing choice. Axis: gratuitous `\,` between multiplicative
factors and around a division slash.

**Resolution hint:** drop every `\,` in these four labels except where none currently exists to
drop incorrectly (there is no differential in any of them, so all four should lose every `\,`);
juxtapose per the house convention, e.g. `S^{(E)}(\Delta x)/\bigl(\tfrac{11}{9}C_2\varepsilon^{2/3}\Delta x^{2/3}\bigr)`.

---

## Finding 4 — Gratuitous thin space between a floor-bracket term and the following factor

**Type:** typesetting
**Severity:** minor
**Confidence:** high

**Locations:**
- SOURCE — `src/Reductions.jl:882`:
  ```
  with ``k_a^{\\mathrm{Nyq}} = \\lfloor N_a/2 \\rfloor \\, 2\\pi/L_a`` the per-axis Nyquist wavenumber — are
  ```
- OUTPUT — rendered manuscript (API/Reductions page, `radial_spectrum` docstring):
  *"with $k_a^{\mathrm{Nyq}} = \lfloor N_a/2 \rfloor \, 2\pi/L_a$ the per-axis Nyquist wavenumber"*

**Description:** `\lfloor N_a/2\rfloor` and `2\pi/L_a` are two multiplied factors, separated here
by a manual `\,`. Per the same Spacing convention as Finding 3, a thin space is reserved
exclusively for before the differential; this is the sole other `\,` in `src/*.jl` (outside the
LaTeXStrings labels of Finding 3) that isn't immediately followed by `\mathrm{d}` — every other
`\,` in `src/*.jl` (in `Convolution.jl`, `DifferentialOperators.jl`, `Reductions.jl` itself
elsewhere) is correctly reserved for the differential.

**Resolution hint:** drop the `\,`: `\lfloor N_a/2\rfloor 2\pi/L_a` (juxtaposed, matching every
other product in the file).

---

## Finding 5 — Gratuitous `\;` after a comma inside `\max(0, …)`

**Type:** typesetting
**Severity:** minor
**Confidence:** medium (the house rule's literally-listed spacing triggers are `=`/`<`/`\in`/`+`/`-`;
a comma is not named, so this reads the rule's *general* "let TeX/KaTeX space it" principle rather
than its literal letter)

**Locations:**
- SOURCE — `src/Convolution.jl:677` (`assignment_window` docstring):
  ```
  \\max\\Bigl(0,\\; 1 - \\frac{|x_a|}{\\Delta x_a}\\Bigr),
  ```
- OUTPUT — rendered manuscript (API/Convolution page): *"$\max\Bigl(0,\; 1 - \frac{|x_a|}{\Delta x_a}\Bigr)$"*

**Description:** this is the *only* `\;` anywhere in the entire corpus (`src/*.jl`, `docs/*.md`,
`examples/*.jl`) — every other formula in the package lets TeX/KaTeX space itself with no manual
override. A comma is TeX's "Punct" atom class, which already carries automatic post-comma spacing
in standard math typesetting (the same reason `f(x, y)` needs no manual space after the comma);
adding `\;` on top doubles it, the identical failure mode the house rule bans for
`=`/`<`/`\in`/`+`/`-` — the fix here is exactly the "let TeX space it" idiom, just applied one
character class further than the rule's literal list.

**Resolution hint:** drop the `\;`: `\max\Bigl(0, 1 - \frac{|x_a|}{\Delta x_a}\Bigr)`.

---

## Finding 6 — Bold `\mathbf{k}` for the wavenumber vector in the two demo files, vs. the corpus-wide plain italic `k`

**Type:** typesetting
**Severity:** minor
**Confidence:** medium

**Locations:**
- `examples/HIST_CPU.jl:12-13,115,121,170` and `examples/gpu/rocm/HIST_ROCm.jl:143,194` (6 total)
  — e.g. line 12: `` ``\mathbf{k}`` for the wavenumber vector and ``\kappa = \lvert\mathbf{k}\rvert`` for its magnitude`` ``
  — bold `k` throughout, internally consistent within these two files (`\mathbf{k}` never mixes
  with a bare `k` for the same role inside either file).
- Everywhere else in the corpus, the identical concept is plain italic `k`:
  `docs/src/notation.md:32` — *"`` ``k`` `` a wavenumber vector (`` ``k_a`` `` is its
  `` ``a``-th `` component...)"* — and every differential-operator formula, e.g.
  `src/DifferentialOperators.jl` `gradient!`: `` ``\widehat{(\nabla\varphi)_i}(k) = \mathrm{i} k_i \hat\varphi(k)`` ``.

**Description:** `\mathbf`/`\boldsymbol` do not otherwise appear anywhere in the corpus (a global
grep found zero other instances) — this is the sole use of bold vector notation, applied to
exactly one concept, in exactly two files, and it clashes with the corpus's single established
symbol for that same concept (plain italic `k`, always with component subscripts `k_a`/`k_i`, the
same *style* of notation the house rule reserves for fiber quantities generally). The likely
reason is legitimate: the demo needs italic `k(t)` free for the turbulent kinetic energy (Pope's
convention, confirmed used consistently at `examples/HIST_CPU.jl:92,327,500`), so boldfacing the
wavenumber vector avoids a `k`/`k` clash within the demo. But `CLAUDE.md`'s "One notation per
concept" rule directs the resolution the other way — *"when an edit introduces a symbol, grep the
doc for any existing symbol denoting the same thing and reconcile them"* and *"a package-wide
convention that cannot move... keeps the glyph; the local use renames"* — here the wavenumber
vector `k` is the corpus-wide, previously-established symbol (declared in the canonical
`notation.md` glossary), and turbulent kinetic energy `k(t)` is the new, demo-local physics
concept; by that stated precedence the newcomer should have been renamed instead (or the choice
cross-referenced/justified on the page), not the entrenched package symbol.

**Contradicts:** `docs/src/notation.md:32` — `` ``k`` `` = "a wavenumber vector" (plain, no bold)
— vs. `examples/HIST_CPU.jl:12` — `` ``\mathbf{k}`` `` = "the wavenumber vector" (bold). Axis:
symbol choice for one concept (wavenumber vector), package-wide glossary vs. two demo files.

**Resolution hint:** either keep `k` italic in the demo too and rename the demo-local turbulent
kinetic energy symbol instead (e.g. `\mathcal K(t)`, sidestepping the clash the way the package
already renamed the integrating factor to `\mathcal E` and the RK stages to
`\hat N_1`/`\hat N_2` for exactly this kind of collision, per the project's own turbulence-notation
memory), or keep `\mathbf{k}` but add one line at first use in the demo acknowledging the
deliberate local departure from the package's `k` convention.

---

## Finding 7 — Possible horizontal-overflow candidate (low confidence — not independently verified by rendering)

**Type:** typesetting
**Severity:** nit
**Confidence:** low

**Locations:** `src/Interpolation.jl:20`:
```
M \\langle Wf, q \\rangle_{\\text{pts}} = \\sum_p (Wf)_p \\cdot q_p = \\sum_x f(x) \\cdot (W^\\top q)(x) = N \\langle f, W^\\top q \\rangle_{\\text{grid}}.
```

**Description:** this is a single, un-split display formula chaining four equalities
(`a = b = c = d`), 155 raw source characters — the longest bare (non-`aligned`/`gathered`) display
line in the corpus. It is not the banned "two separate equations packed behind `\quad`" pattern
(it's one continuous equality chain, a legitimate construct), and I have no way in this review to
directly measure its rendered pixel width against the docs site's content column, so I cannot
confirm it actually triggers horizontal scroll. It stands out mainly by contrast: comparably dense
formulas elsewhere (e.g. `src/Reductions.jl:861-862`'s `radial_spectrum` shell-sum formulas, which
are *longer* in raw characters) are deliberately split with `\substack`/`\begin{gathered}` to
control width, while this one is not. Flagging as a candidate worth a visual check, not a
confirmed defect.

**Resolution hint:** if a rendering check confirms overflow, split at the middle `=` via
`\begin{aligned}` (e.g. `M\langle Wf,q\rangle_{\text{pts}} = \sum_p (Wf)_p\cdot q_p \\ = \sum_x f(x)\cdot(W^\top q)(x) = N\langle f, W^\top q\rangle_{\text{grid}}`).
