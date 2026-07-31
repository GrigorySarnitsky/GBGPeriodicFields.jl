# Panel review — LaTeX & Mathematical-Typesetting hat

Scope: typesetting quality of every rendered formula against LaTeX best practice and the
package's stated house conventions (imaginary unit upright `\mathrm{i}`; differential upright
`\,\mathrm{d}`; component (not bold) vectors/tensors; fixed-size `\Bigl…\Bigr` preferred over
`\left…\right`; every macro argument braced; no gratuitous `\,`). Not judging the mathematics
or normalizations (other hats own those). Document read in full: `manuscript-full.md` (the
consolidated rendered site incl. design docs). The deterministic lint (`\,` before non-`d`,
unbraced `\tfrac`) is otherwise clean — no gratuitous thin spaces anywhere.

---

## F1. Bare italic imaginary unit `$ik$` — the exact failure the house convention forbids
- type: contradiction / severity: major / confidence: high
- PAGE architecture, §13 decision log (decision 19, the measure taxonomy), line 408:
  "`gradient`/`curl`/`laplacian` are the unbounded multipliers (symbols `$ik$`, `$-|k|^2 \notin L^\infty$`)"
- The imaginary unit is written as a **bare italic `i`** juxtaposed with `k` (`$ik$`), i.e. exactly
  the `ik` → `\mathrm{i}k` case the house style singles out. Every other occurrence in the whole
  document (28 of them) correctly writes `\mathrm{i}k`. Because `i` is deliberately reserved as an
  index, `ik` is genuinely ambiguous (reads as "index i times k").
- contradicts: PAGE notation, §Conventions, line 622 — "Imaginary unit | `$\mathrm{i}$` | Upright,
  always — never bare italic i, never \imath." Axis: the doc states the upright-i rule and then
  violates it one page over.
- resolution_hint: `$\mathrm{i}k$`.

## F2. `\left[…\right]` used where the house style prefers fixed-size delimiters
- type: contradiction / severity: minor / confidence: high
- PAGE api / Convolution, `spectral_cutoff`, line 1035:
  `\[\hat g(k) = \mathbb 1\!\left[  |k| \le k_c  \right].\]`
- This is the **only** `\left…\right` in the rendered math of the entire site. Its content
  (`|k| \le k_c`) is not tall, so the auto-sized brackets over-inflate — precisely the case the
  convention warns against. Everywhere else the docs use `\bigl/\bigr`, `\Bigl/\Bigr` (26 of each).
- contradicts: PAGE notation, §Conventions, line 630 — "Delimiters | Fixed-size \Bigl … \Bigr is
  preferred to auto-sized \left … \right, which over-inflates around subscripted sums." Axis:
  stated delimiter preference vs. its lone violation.
- resolution_hint: `\bigl[…\bigr]` or plain `[…]`.

## F3. Unbraced macro arguments (`\tfrac NM`, `\sqrt3`) — backstop for the braced-argument rule
- type: typesetting / severity: minor / confidence: high
- PAGE formalization, §Interpolation/anterpolation (normalized-inner adjoint), line 593:
  `= \frac{1}{N}\sum_n f_n\cdot\tfrac NM (W^{\top}q)_n` — `\tfrac NM` has both arguments unbraced.
- PAGE api / Reductions, `radial_correlation`, line 3168:
  "the minimum-image corner `$\sqrt{\sum_a (L_a/2)^2}$` (`$\sqrt3 L/2$` for a cubic box)" — `\sqrt3`
  unbraced. Contrast the examples page (line 3287) which writes the same constant `\sqrt{3}` braced.
- These render correctly (single-token arguments) but violate the stated rule and are inconsistent
  with the braced usage everywhere else.
- contradicts: PAGE notation, §Conventions, line 628 — "Fractions | … Every macro argument is
  braced, both numerator and denominator." Axis: stated braced-argument rule vs. these two sites.
- resolution_hint: `\tfrac{N}{M}`, `\sqrt{3}`.

## F4. Exponential base set upright `\mathrm{e}` in exactly one formula
- type: contradiction / severity: minor / confidence: high
- PAGE api / Convolution, `translation_kernel`, line 1097:
  `\[\hat g(k) = \mathrm{e}^{-\mathrm{i}  k \cdot h} = \prod_{a=1}^{3} \bigl[ \cos(k_a h_a) - \mathrm{i} \sin(k_a h_a) \bigr].\]`
- The exponential base is the **upright `\mathrm{e}`** here, but italic `e^{…}` in all 21 other
  phase-exponent occurrences (e.g. formalization line 506 `e^{-\mathrm{i} k\cdot x}`, DirectDFT line
  2816 `e^{\mathrm{i} k\cdot(x_p-o)}`, decision 28 line 476 `e^{-\mathrm i k\cdot h}`), and `\exp(…)`
  in 11 more. The very same translation phase is written with italic `e` in the architecture/
  formalization/api-overview but upright `\mathrm{e}` only in this docstring.
- contradicts: PAGE formalization, §Convolution, line 553 — `e^{-\mathrm i \kappa_a h_a}` and
  `\hat g_h(k) = e^{-\mathrm i k \cdot h}` (italic base for the identical kernel). Axis: exponential
  base italic vs. upright for the same object.
- resolution_hint: pick one; italic `e^{…}` is the majority form.

## F5. Levi-Civita symbol: `\epsilon` (formalization) vs `\varepsilon` (docstrings)
- type: contradiction / severity: minor / confidence: high
- PAGE formalization, §Fiberwise algebra: line 516 `(u\times v)_i &= \epsilon_{ijk} u_j v_k`; line
  520 `\det A=\epsilon_{ijk}A_{1i}A_{2j}A_{3k}=I_3` — both `\epsilon` (lunate ϵ).
- PAGE api / DifferentialOperators `curl!` line 1210 `\varepsilon_{ijk}`; PAGE api / FiberSections
  `_det_tensor_rhs` line 1518 `\varepsilon_{ijk}`; PAGE api / FieldAlgebra `cross!` line 1819/1821
  and `det!` line 1884/1885 — all `\varepsilon`.
- The same symbol renders as two different glyphs (ϵ vs ε) depending on page.
- contradicts: (the two clusters above, each other). Axis: `\epsilon` vs `\varepsilon` for the
  Levi-Civita symbol. Note: `\varepsilon` for the dissipation rate on the examples page is a
  separate, correct use and not in conflict.
- resolution_hint: standardize on `\varepsilon` (the docstring majority; frees ϵ if ever needed).

## F6. Fiber norm written with the `\lVert·\rVert` glyph reserved for `l2norm`
- type: contradiction / severity: major / confidence: medium
- PAGE formalization, §Fiberwise algebra, line 518:
  `\lVert u\rVert &= \sqrt{u_i u_i}, & \lVert A\rVert &= \sqrt{A_{ij}A_{ij}}` — the **fiberwise**
  norm (sum over the 3 fiber components) set with double bars.
- PAGE api / FieldAlgebra, `norm!`, line 1967/1970: "(`norm` `$\equiv |\cdot|$`)" and
  `\[|\varphi|, \qquad |u| = \sqrt{u_i u_i}, \qquad |A| = \sqrt{A_{ij} A_{ij}}.\]` — the identical
  operation with **single** bars.
- The notation page (line 656) reserves `$\lVert\cdot\rVert$` for the global `l2norm`, and the
  package's "one concept, one notation" rule forbids one glyph carrying two meanings. Formalization's
  `\lVert u\rVert` for the fiber norm both (a) disagrees with the docstring's `|u|` and (b) collides
  with the L²-norm symbol used (correctly) at formalization line 533 (`-\lVert\nabla\phi\rVert^2`).
- contradicts: PAGE api / FieldAlgebra line 1970 `|u| = \sqrt{u_i u_i}` and PAGE notation line 656
  (`\lVert·\rVert` = l2norm). Axis: fiber norm as `\lVert·\rVert` vs `|·|`, and glyph overloaded.
- resolution_hint: use `|u|`, `|A|` (single bars) for the fiber norm in formalization; keep
  `\lVert·\rVert` for `l2norm`/Dirichlet only.

## F7. Bold wavenumber `\mathbf{k}` on the examples page vs plain `k` everywhere else
- type: contradiction / severity: minor / confidence: medium
- PAGE examples / hist_cpu, Method + Spectral utilities + Forcing, 5 occurrences: line 3190
  "`$\mathbf{k}$` for the wavenumber vector … `$\kappa = \lvert\mathbf{k}\rvert$`", line 3258
  `$\lvert\mathbf{k}\rvert^{2}$`, line 3260 `$w(\mathbf{k})$`, line 3302 `$\lvert\mathbf{k}\rvert = 1$`.
- The house style uses component/plain notation, not `\mathbf`/`\boldsymbol` bold, and the notation
  page (line 641) fixes the wavenumber symbol as plain italic `$k$`. Every other page writes plain
  `k` / `|k|` / `k_a`. The examples page is the only surface using bold `\mathbf{k}`.
- contradicts: PAGE notation, §Base and fiber, line 641 — "`$k$` | a wavenumber vector (`$k_a$` is
  its `$a$`-th component, `$\lVert k\rVert$` its magnitude)". Axis: bold vs plain vector notation for
  the wavenumber.
- resolution_hint: plain `k` (and `\lvert k\rvert`) on the examples page to match the rest.

## F8. Taylor–Reynolds number: italic `Re_\lambda` (performance) vs upright `\mathrm{Re}_\lambda` (examples)
- type: contradiction / severity: minor / confidence: medium
- PAGE performance, §4(f), line 725: "`$Re_\lambda \approx 93$`" — italic letter-product "Re".
- PAGE examples / hist_cpu, 7 occurrences (lines 3194, 3244, 3250, 3570): `$\mathrm{Re}_\lambda$` —
  upright, e.g. line 3570 "`$\mathrm{Re}_\lambda \approx 130$`".
- Italic `Re` reads as a product of two variables; for a named dimensionless group upright is the
  idiomatic (and majority) form, and it disambiguates from the real-part `\mathrm{Re}` used
  elsewhere. Performance line 725 is the lone outlier.
- contradicts: PAGE examples line 3244 `$\mathrm{Re}_\lambda \approx 93$` (same quantity, upright).
  Axis: italic vs upright for the Reynolds number.
- resolution_hint: `\mathrm{Re}_\lambda` everywhere.

## F9. Real part set `\operatorname{Re}` once vs `\mathrm{Re}` 21×
- type: contradiction / severity: nit / confidence: high
- PAGE architecture, §13 (decision 27, `weighted_inner`), line 469:
  `\tfrac{1}{N^2}\sum_k \alpha(k) w(k)\sum_c \operatorname{Re}(\hat f_c  \overline{\hat g_c})` —
  `\operatorname{Re}`.
- Every other real-part (21 occurrences) is `\mathrm{Re}` (e.g. formalization line 573, api /
  Reductions line 3110/3151, DirectDFT line 2817). `\operatorname{Re}` also carries slightly
  different operator spacing than `\mathrm{Re}`.
- contradicts: PAGE api / Reductions, `weighted_inner`, line 3110 `\mathrm{Re}\bigl(\hat f_c(k)
  \overline{\hat g_c(k)}\bigr)` (the same formula, `\mathrm{Re}`). Axis: `\operatorname{Re}` vs
  `\mathrm{Re}`.
- resolution_hint: `\mathrm{Re}` for consistency (or standardize all on `\operatorname{Re}`, which is
  the more idiomatic operator form — but pick one).

## F10. Multiple equations packed on one display line — horizontal-overflow risk
- type: typesetting / severity: minor / confidence: medium
- PAGE examples / hist_cpu, "One integrating-factor RK2" step, lines 3340–3343:
  `\[\hat{N}_1 = \hat{N}(\hat{u}_n), \qquad \hat{u}^{*} = \mathcal{E} (\hat{u}_n + \Delta t \hat{N}_1),
  \qquad \hat{N}_2 = \hat{N}(\hat{u}^{*}), \qquad \hat{u}_{n+1} = \mathcal{E} \hat{u}_n +
  \tfrac{\Delta t}{2} (\mathcal{E} \hat{N}_1 + \hat{N}_2),\]` — **four** equations behind `\qquad` on
  one line. Display math does not wrap, so this scrolls horizontally on a normal viewport.
- PAGE api / FieldAlgebra, `cross!`, lines 1822–1824 (inside `gathered`): the three cross components
  `(u \times v)_1 = …, \quad (u \times v)_2 = …, \quad (u \times v)_3 = …` are likewise packed on one
  line with `\quad`, whereas the parallel `curl!` docstring (lines 1212–1214) stacks its three
  components one per `\\` line.
- The house rule forbids packing equations behind `\quad` and mandates no horizontal scroll; a wide
  display should hand-wrap via `aligned`/`gathered`.
- resolution_hint: break the RK2 stages across `\\` lines (aligned at `=`); make `cross!` stack its
  components like `curl!` for consistency.

## F11. Bare `\big`/`\big` delimiters (no l/r) on the examples page vs `\bigl`/`\bigr` everywhere
- type: typesetting / severity: minor / confidence: high
- PAGE examples / hist_cpu, Results (structure functions), lines 3571–3575:
  `S^{(E)}(\Delta x) = \tfrac{1}{3}\big\langle \lvert u(x+\Delta x) - u(x)\rvert^{2}\big\rangle =
  \tfrac{2}{3}\big(C(0) - C(r)\big)` — bare `\big\langle … \big\rangle` and `\big( … \big)` (no
  `l`/`r` suffix). Bare `\big` is an ordinary atom, so the spacing is that of an ordinary symbol, not
  an opening/closing delimiter.
- Every other page uses the matched forms (`\bigl`/`\bigr` 12+12, `\Bigl`/`\Bigr` 14+14). Also
  inconsistent within the page: line 3509 writes the same `C(0) - C(r)` with plain parens.
- contradicts: e.g. PAGE api / DifferentialOperators line 531 `\bigl(k\cdot(k\times\hat u)=0\bigr)`
  (proper `\bigl…\bigr`). Axis: bare `\big` vs matched `\bigl/\bigr`.
- resolution_hint: `\bigl\langle…\bigr\rangle`, `\bigl(…\bigr)` (or plain parens where content isn't
  tall).

## F12. Inner-product / measure subscript: `\text{pts}`/`\text{grid}` (design docs) vs `\texttt{PointSet}`/`\texttt{Grid3D}` (API docs)
- type: contradiction / severity: minor / confidence: medium
- PAGE architecture §2/§10 and PAGE formalization throughout use roman abbreviations, e.g.
  formalization line 500/502 `\langle a, b\rangle_{\text{pts}}`, `\langle f, g\rangle_{\text{grid}}`
  (also `_{\text{points}}`).
- PAGE api / Interpolation, module docstring, line 2720:
  `M \langle Wf, q \rangle_{\texttt{PointSet}} = … = N \langle f, W^\top q \rangle_{\texttt{Grid3D}}`;
  PAGE api / Reductions uses `(\texttt{Grid3D})` / `(\texttt{PointSet})` monospace labels (lines
  3077–3095, 3121–3135).
- The same pairing's base label differs across surfaces both in wording (pts/grid vs the full type
  names) and font (`\text` roman vs `\texttt` monospace). A monospace type name as a math subscript
  is also visually heavy.
- contradicts: PAGE formalization line 500 `\langle a, b\rangle_{\text{pts}}` vs PAGE api /
  Interpolation line 2720 `\langle Wf, q \rangle_{\texttt{PointSet}}`. Axis: subscript label wording
  and font for the base measure.
- resolution_hint: pick one convention for the pairing subscript site-wide.

## F13. `\mathrm{i}` braced vs `\mathrm i` unbraced — cross-doc drift (renders identically)
- type: typesetting / severity: nit / confidence: high
- Unbraced `\mathrm i`: PAGE api-overview line 37, PAGE architecture §11 line 352 and decision-27/28
  prose (lines 468, 473, 476, 477), PAGE formalization line 550/553/554. Braced `\mathrm{i}`:
  notation page line 622 (the canonical form), all of DifferentialOperators, formalization lines
  506/536/606, etc.
- Same-formula drift is visible: architecture line 468 writes `\tfrac{\mathrm i}{2}` while the
  identical symmetric-gradient symbol is `\tfrac{\mathrm{i}}{2}` in formalization line 536 and in the
  `symmetric_gradient!` docstring line 1253.
- Renders identically (single-token), so this is a source-consistency nit only, but the canonical
  form on the notation page is braced `\mathrm{i}`.
- resolution_hint: normalize to `\mathrm{i}` (braced) throughout.

## F14. Stacked-equation displays use `\begin{gathered}` where `\begin{aligned}` at `=` would align parallel equations
- type: typesetting / severity: nit / confidence: low
- PAGE api / DifferentialOperators, `curl!`, lines 1211–1215 and 1222–1226: three parallel
  component equations `(\nabla\times u)_1 = …`, `…_2 = …`, `…_3 = …` in `gathered` (centered, `=`
  not aligned). Likewise `radial_spectrum` (lines 3149–3152) and `radial_correlation` (lines
  3163–3166) stack parallel `=` equations in `gathered`.
- `gathered` centers each row, so the `=` signs of parallel equations do not line up; `aligned` with
  `&=` is the idiomatic choice for a set of related equations. The doc uses `gathered` and `aligned`
  about equally (6 each), so this is a soft consistency/quality point, not a hard error.
- resolution_hint: use `aligned` (align at `=`) for genuinely parallel equation lists; keep
  `gathered` for unrelated stacked definitions (e.g. the `\hat W` + `sinc` pair, line 1078).

## F15. Code identifiers set inside math spans via `\mathrm{}`/`\text{}` (should be `\texttt{}`), with `\mathrm{mean}`/`\text{mean}` drift
- type: typesetting / severity: nit / confidence: medium
- Function/return-value names appear as operands inside `$…$`, wrapped in `\mathrm{}` or `\text{}`
  rather than `\texttt{}`: e.g. PAGE architecture line 434 `E(k) = \tfrac{1}{2} \mathrm{radial\_spectrum}`,
  line 430 `E(\kappa) = \tfrac{1}{2} \mathrm{spectrum}`, and `\mathrm{inner}`/`\mathrm{integral}`/
  `\mathrm{l2norm}`/`\widehat{\mathrm{destination}}`/`\mathrm{dst}` throughout (e.g. lines 396, 404,
  520, 999). These render readably (upright), so they avoid the loud italic-letter-product failure,
  but the house guidance is `\texttt{}` for a code name that must sit inside a formula.
- Font drift within this class: the same operation is `\mathrm{mean}` in architecture/testing (6×,
  e.g. line 396) but `\text{mean}`/`\text{measure}`/`\text{count}` in formalization (lines 559–562).
- resolution_hint: prefer `\texttt{}` (or pull the code name out of the math span into backticked
  prose); at minimum standardize `\mathrm{}` vs `\text{}` for operation names in math.

## F16. Notation page shows raw LaTeX command names as literal prose text
- type: typesetting / severity: nit / confidence: medium
- PAGE notation, §Conventions, line 630 (Delimiters row, Convention column): "Fixed-size
  `\Bigl \dots \Bigr` is preferred to auto-sized `\left \dots \right`, which over-inflates…" — the
  command names `\Bigl`, `\dots`, `\Bigr`, `\left`, `\right` are bare backslash text (not in a math
  span, not backticked), so they render literally as "\Bigl \dots \Bigr" / "\left \dots \right".
- The page's own header (line 617) states "a code identifier always appears in `backticks`"; LaTeX
  command names named as such should be in code font/backticks (or rendered) rather than raw
  backslash prose.
- resolution_hint: backtick the command names (`` `\Bigl…\Bigr` ``) or phrase without raw macros.
