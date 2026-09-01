# Lane 06 — doc pages (index.md, tutorial.md, notation.md, api.md, api/*.md)

## Enumeration

Surface read in full: `docs/src/index.md`, `docs/src/tutorial.md`, `docs/src/notation.md`,
`docs/src/api.md`, and all nine files under `docs/src/api/` (`GBGPeriodicFields.md`,
`FiberSections.md`, `Fields.md`, `FieldAlgebra.md`, `DifferentialOperators.md`, `Convolution.md`,
`Points.md`, `Interpolation.md`, `Reductions.md`). `@autodocs`/`@docs` block *contents* were skipped
per instructions; the hand-written prose around and inside them (section headers, Internal-API
blurbs, kernel-class explanations) was read and checked.

Checks run, as positive procedures:
- Every formula/normalization constant in these pages enumerated and checked against
  `src/Reductions.jl`, `src/Convolution.jl`, `src/Interpolation.jl`, `src/DifferentialOperators.jl`,
  `src/GBGPeriodicFields.jl`: the `inner`/`M·⟨Wf,q⟩=N·⟨f,Wᵀq⟩` adjoint relation, the spectral
  `var`/`std` formula (`inner(f,f) − mean(f)²`), the `LalescuSpline(0,0)` linear-CIC identity, the
  exponential-kernel symbol `exp(c|k|²+sŵ)`, the translation-kernel phase `e^{−i k·h}`, the
  `inv` behaviour per kernel class (`StoredKernel` throws / `RadialKernel` yields non-finite /
  `SeparableKernel` per-factor), and the mapped-reduction family (`integral`, `mean`, `maximum`,
  `minimum`, `extrema` — confirmed exactly these five have a `(fiber_map, section)` method;
  `lpnorm`/`std`/`var` confirmed to have none).
- Re-export surface cross-checked: `mean`/`std`/`var`/`cov` confirmed re-exported by the umbrella
  (`src/GBGPeriodicFields.jl:285-288,428-431`) while `Reductions` itself exports only
  `integral, inner, weighted_inner, l2norm, lpnorm, radial_spectrum, radial_correlation`
  (`src/Reductions.jl:83-87`) — matches `api/Reductions.md`'s two-block `@autodocs` split and its
  prose explanation.
- Notation table cross-checked against `docs/CLAUDE.md`'s decision log and against `src/` docstring
  usage (`|k|^2` spelling in `src/DifferentialOperators.jl:1333`, `src/Fields.jl:1937`,
  `src/Convolution.jl` vs. the table's own claimed "running-math" spelling).
- Formatting sweep (python, not naive grep) for single-backtick spans containing a LaTeX backslash
  command, distinguishing genuine single-backtick code spans from double-backtick math spans.
- Bare-module-name sweep (backtick-stripped text) across all thirteen files.
- `\left`/`\right` ban, manual spacing before relations, indented-table-in-list, citation-format
  sweeps — all clean, see below.
- Completeness sweep: every module bullet in `index.md` "Main components" and `api.md` "API
  overview" checked against the current exported surface of its module, focused on the most
  recent decisions (73–79) in `CLAUDE.md`'s roadmap, since that is exactly the failure class
  `CLAUDE.md` names ("a summary naming only a subset of what the code now provides is stale").

## Finding 1

- **Check:** 4 (FORMATTED, bidirectional) and 1 (CORRECT)
- **Location:** `docs/src/notation.md:57`
- **Quote:** `` | ``\lvert\cdot\rvert`` | the pointwise (fiberwise) magnitude. In this table the bars are written `\lvert…\rvert` because a literal pipe inside a cell is eaten as a column delimiter; in running math outside tables the plain-bar spelling `\|k\|^2` (with the bars escaped here for the same reason) is the same symbol, and both denote one concept | `norm` | ``
- **Why it violates the rule:** The cell claims that in running math *outside* tables (where there
  is no column-delimiter hazard to escape against) the "plain-bar spelling" is `` \|k\|^2 `` — but
  (a) this is wrapped in a **single backtick**, which renders as monospace code, not as LaTeX math
  (rule 4: "math is LaTeX and never backticks"), and (b) the content itself is wrong: `\|` is the
  distinct LaTeX command for a *double* bar (‖, the norm delimiter, i.e. exactly the `l2norm` glyph
  this same page defines two rows below as `` ``\lVert\cdot\rVert`` `` at line 58), not the single
  bar `|k|` used for magnitude. Checked against the package's own running-math convention: every
  in-source use of this symbol writes the plain, unescaped single bar — e.g.
  `src/DifferentialOperators.jl:1333` (``\\widehat{\\Delta f}(k) = -|k|^2 \\hat f(k), \\qquad |k|^2
  = k_1^2 + k_2^2 + k_3^2.``), `src/Fields.jl:1937` (`` ``|k|^2 = k_1^2 + k_2^2 + k_3^2`` ``),
  `src/Convolution.jl:993` (`` ``\\lvert k\\rvert^2`` `` used inside a math span, not a table).
  Nowhere in `src/` is the escaped-backslash-pipe spelling `\|k\|` used for this symbol. So the cell
  both mis-renders (backticks, not math) and mis-states the claimed "plain" spelling (an
  unnecessary, semantically different escape), conflating the `norm` row's symbol with the
  `l2norm` row's symbol the page itself distinguishes one line below.
- **Proposed fix:** Replace `` `\|k\|^2` `` with the double-backtick math span `` ``|k|^2`` `` (no
  escaping needed outside a table — there is no pipe/column-delimiter hazard there), matching the
  spelling actually used throughout `src/`. Keep the preceding `` `\lvert…\rvert` `` single-backtick
  span as-is, since that one is genuinely citing literal command text (consistent with the page's
  established pattern for `` `\imath` ``, `` `\bigl` ``/`` `\Bigl` `` etc. at line 20).
- **Confidence:** high

## Finding 2

- **Check:** 5 (CURRENT and COMPLETE)
- **Location:** `docs/src/index.md:48` (the `Interpolation` bullet under "Main components") and
  `docs/src/api.md:14` (the matching `Interpolation` bullet under "API overview")
- **Quote (index.md:48):** "`[`Interpolation`](api/Interpolation.md)`: the grid↔point transfer —
  interpolation (gather ``W``) and anterpolation (scatter ``W^\top``) as an adjoint pair … under a
  choice of `AbstractTransferScheme`: the physical-domain local splines (`LalescuSpline`/`CatmullRom`,
  `LagrangeSpline`), the exact spectral `DirectDFT`, and the fast spectral `NUFFT`; all three schemes'
  kernels are portable across CPU/CUDA/AMDGPU. A scheme itself persists through
  `write_scheme`/`read_scheme` …"
- **Quote (api.md:14):** "`[`Interpolation`](api/Interpolation.md)`: the grid↔point transfer —
  interpolation (gather) and anterpolation (scatter) as an adjoint pair …, under an
  `AbstractTransferScheme`: the local splines (`LalescuSpline`/`CatmullRom`, `LagrangeSpline`), the
  exact spectral `DirectDFT`, and the fast spectral `NUFFT`, together with scheme persistence
  (`write_scheme`/`read_scheme`)."
- **Why it violates the rule:** Both bullets summarize the `Interpolation` module's public surface but
  omit `transfer_order`/`TransferOrder` (decision 78, 2026-08-30) entirely — a headline, exported
  addition (`src/Interpolation.jl:88`: `export interpolate, interpolate!, anterpolate, anterpolate!,
  transfer_order, TransferOrder, …`) that the module's own API page documents in a dedicated
  hand-written section (`docs/src/api/Interpolation.md:18-26`, "## Visit order": "An order is an
  option on the transfer operations above … it changes the sequence in which the points are visited
  and never the result"). `CLAUDE.md`'s roadmap records this as a major, separately-measured feature
  (3.4–7×/4.5× speedups, its own decision entry, its own persistence/consistency guarantees), and
  `CLAUDE.md` itself names exactly this failure class: "a summary naming only a subset of what the
  code now provides is stale even if every sentence is literally true — check each
  module/operation/summary still names everything added since it was written". These two top-level
  summaries were evidently written (or last touched) before decision 78 landed and were not updated
  to mention the new public entry point, even though every other decision-73-through-77 addition
  (`displace!`/`wrap!`, the family-taking constructors, `write_scheme`/`read_scheme`, `inverse_curl`)
  *is* named in these same bullets.
- **Proposed fix:** Add a clause to both bullets naming `transfer_order`/`TransferOrder` as the
  point-visit-order option the four transfer verbs take (e.g., after the `NUFFT`/portability
  clause: "…; an optional `transfer_order` groups the points by grid block for a device- and
  cache-friendly visit order, without changing the transferred result."). Keep it to one clause per
  bullet, consistent with the terseness of the other additions already listed there.
- **Confidence:** high

## Verified clean (no findings)

- **CORRECT (check 1):** every formula/adjoint relation/complexity claim on these nine pages was
  matched against the implementing code and found accurate — the `N/M` interpolation-adjoint
  rescaling (`M⟨Wf,q⟩=N⟨f,Wᵀq⟩`, `src/Interpolation.jl:16-24`), the spectral `var`/`std` formula
  (`src/Reductions.jl:730-735`), `assignment_window`'s `LalescuSpline(0,0)` identity
  (`src/Convolution.jl:1797`, `src/Interpolation.jl:166-176`), the exponential kernel symbol
  (`src/Convolution.jl:1500` et al.), the translation-kernel phase (upright `\mathrm{i}`, matches
  `src/Convolution.jl`'s own docstrings), `inv`'s three per-class behaviours
  (`src/Convolution.jl:544-574`), and the mapped-reduction family membership (five reductions
  confirmed to have `(fiber_map, section)` methods, `lpnorm`/`std`/`var` confirmed not to).
- **SELF-CONTAINED (check 2):** `notation.md` is the dedicated glossary and binds every symbol it
  introduces; `tutorial.md` introduces each new term (`RealFourierLayout`, `spectral_field_shape`,
  `FieldTransformPlans`, "layout", "fold") in plain language at first use, consistent with a cold
  read. No unbound symbol or term of art found.
- **NOTATION (check 3):** the deliberate symbol reuses on this page (`g`/`ĝ` for a convolution kernel,
  `W`/`Ŵ` for `assignment_window`'s CIC window vs. the interpolation gather operator, `α` for both
  the accumulation weight and the Parseval multiplicity) are each explicitly flagged as a "deliberate
  reuse" with a disambiguating rule, matching `CLAUDE.md`'s "one notation per concept" exception
  bookkeeping. No unflagged collision found. No section-level flattening/matrix machinery found on
  these pages (the `W`/`Wᵀ` interpolation maps are stated as operators throughout, never as a dense
  matrix).
- **FORMATTED (check 4), beyond Finding 1:** no `\left`/`\right` outside the one documented exception
  at `notation.md:20`; no manual `\;`/`\,`/`\:` spacing next to a relation or binary operator; no
  `\!` before `\bigl`/`\Bigl`; no indented tables inside list items (`grep -rnE
  '^[[:space:]]+\|[-:| ]+\|'` returns nothing across the lane); no bare (unbacktick) module name in
  prose outside page/section headers (headers using a bare module name as the page title, e.g. `#
  FiberSections`, are the page's own established title convention, matching every other API page and
  Documenter's own generated titles); no ASCII-math-as-code pattern (`X = Y*` style) found by a
  targeted sweep; all display/inline math spans balanced (no mid-span line wrap into a list-marker
  line).
- **CURRENT and COMPLETE (check 5), beyond Finding 2:** cross-checked the `FieldAlgebra`, `Points`,
  `Reductions`, `Convolution`, `Fields` bullets against their current exported surface and the
  decision log; `mean`/`std`/`var`/`cov` re-export claim verified exactly against
  `src/GBGPeriodicFields.jl`; `displace!`/`wrap!`, the family constructors, `write_scheme`/
  `read_scheme`, `inverse_curl`, `adapt!` are all present and correctly attributed. No other stale
  "deferred/future/none-exist" language found on this lane's surface.
- **CITED (check 6):** no citations appear anywhere on this lane's nine files (`grep -nE 'et al\.|\
  ([0-9]{4}\)'` returns nothing); nothing to check.
