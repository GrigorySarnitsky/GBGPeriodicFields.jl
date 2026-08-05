# LaTeX / Typesetting Review — GBGPeriodicFields

**Hat:** latex-typesetter (house-style enforcer)
**Scope:** rendered manuscript (`manuscript-full.md`) + authored source (`src/*.jl`, `docs/*.md`, `docs/src/*.md`, `examples/*.jl`), judged against `CLAUDE.md`'s §Style math-authoring rules.

## Summary

This corpus is typographically very disciplined. Systematic greps for every banned pattern in the
house rubric turned up **zero** violations of: `\left`/`\right` (only the sanctioned
`\left\{ … \right.` system and its documentation survive), manual `\;`/`\:` spacing, `\!` before a
delimiter (only the sanctioned `\sim\!`), `\!\!` before `\sum`/`\int`, `\mathbb{}` on anything but a
capital letter, unbraced `\frac`/`\tfrac` arguments, the banned bare-index `\partial_i` variant,
mismatched `\bigl`/`\Bigl`…`\bigr`/`\Bigr` sizes, `\hat{}` on multi-character content, bare `i` for
the imaginary unit, bare `\epsilon` (always `\varepsilon`), bare `^T` (always `\top`), or literal `|`
inside a math span sitting in a Markdown table row. Five findings survived a genuinely adversarial
sweep; all are minor/nit-level internal inconsistencies rather than rendering breaks.

---

## Finding 1 — A math-span formula uses bare Unicode `φ` where the rest of the corpus uses `\varphi`

- **Type:** typesetting
- **Severity:** minor
- **Confidence:** high
- **Location:** `src/FieldAlgebra.jl:1791` (the `map!`/`map` docstring's argument list), rendered at manuscript line 2936.
  - Source: `` - `α`, `β` — the accumulation of the single-source form, ``\\texttt{destination} = α φ(\\texttt{source}) + β \\texttt{destination}`` ``
  - Rendered: `$\texttt{destination} = α φ(\texttt{source}) + β \texttt{destination}$`
- **Contradicts:** every other math-mode occurrence of phi in the corpus uses `\varphi` inside the
  math span — including the *same file*, four lines earlier: `src/FieldAlgebra.jl:1376`,
  `` |\\varphi|, \\qquad |u| = \\sqrt{u_i u_i}`` ``; also `src/FiberSections.jl:646`
  (`` ``|\\varphi|`` ``), `src/DifferentialOperators.jl:677-733` (`` ``\\varphi`` ``,
  `` ``\\nabla\\varphi`` ``), and `docs/FORMALIZATION.md:128-451` (a dozen further `\varphi`
  instances, including the very same accumulate formula spelled out as
  `` ``\\texttt{destination} = \\alpha \\varphi(\\texttt{source}) + \\beta \\texttt{destination}`` ``
  at `docs/FORMALIZATION.md:136`).
- **Description:** CLAUDE.md's Unicode-Greek carve-out is narrowly scoped to "the axpby accumulation
  scalars" `α`/`β` specifically ("two deliberate ASCII holdouts" for the reverse direction; no third
  exception is named). `φ` is not one of the named exceptions, and everywhere else the map function
  is rendered as `\varphi` in math mode (the plain `φ` only appears backticked as a *code* identifier
  in prose, e.g. `` `φ` ``, never bare inside a `` ``…`` `` span). This one formula mixes the two
  registers: `α`/`β` legitimately bare, `φ` illegitimately bare beside them, so the same expression
  contains the package's one unexplained Unicode-glyph math approximation.
- **Resolution hint:** change `φ` to `\\varphi` in that one formula, matching `docs/FORMALIZATION.md:136`'s spelling of the identical accumulate identity.

## Finding 2 — The same numeric literal `2^14` is backticked in one place and bare prose in another, same document

- **Type:** typesetting / format
- **Severity:** minor
- **Confidence:** high
- **Locations:**
  - `docs/ARCHITECTURE.md:582` (and its mirror `docs/src/architecture.md:582`): `` A serial cutoff (`_SERIAL_CUTOFF`, default 2^14) keeps small ops `` — `2^14` sits as **bare prose**, not backticked, immediately after a backticked code identifier in the same parenthetical.
  - `docs/ARCHITECTURE.md:1031` (and its mirror `docs/src/architecture.md:1031`): `` Hybrid policy: on when `nthreads() > 1` and above a `2^14` serial cutoff `` — the identical literal, describing the identical constant, **is** backticked.
- **Contradicts:** two mentions of the same `_SERIAL_CUTOFF` default value in the same file disagree on whether the Julia-syntax literal `2^14` is a code span or plain text.
- **Description:** `2^14` is Julia exponent syntax (`2^14 = 16384`), not LaTeX and not English prose; left un-backticked it reads as a stray caret in running text (the `^` has no typographic role outside code or math). One of the two spellings is wrong by the corpus's own practice at the other site.
- **Resolution hint:** backtick line 582's `2^14` to match line 1031 (or write both as `` ``2^{14}`` `` if a math rendering is preferred — but pick one, not both).

## Finding 3 — Two competing conventions for an upright multi-letter subscript label: `\text{…}` vs `\mathrm{…}`

- **Type:** typesetting
- **Severity:** minor
- **Confidence:** medium
- **Locations (representative):**
  - `\text{}` family — `docs/ARCHITECTURE.md:726-796` (`` _{\\text{pts}}``, `` _{\\text{grid}}`` — the §10 adjointness identities), `docs/FORMALIZATION.md:60-591` (same), `src/Interpolation.jl:22-23,707`, `src/Reductions.jl:1223`. **72** occurrences of `\text{grid}`/`\text{pts}`/`\text{points}` as a subscript label across the corpus.
  - `\mathrm{}` family — `docs/PERFORMANCE.md:733-734` (`` t_\\mathrm{threaded}``, `` t_\\mathrm{serial}``), `docs/ARCHITECTURE.md:1409` (`` _\\mathrm{Nyq}``), `src/Convolution.jl:1377-1426` (`` k_\\mathrm{lo}``, `` k_\\mathrm{hi}``), `examples/HIST_CPU.jl:179,395` (`` u_{\\mathrm{band}}``, `` \\kappa_{\\mathrm{rms}}``). **22** occurrences of the same role via `\mathrm{}`.
- **Contradicts:** both spellings serve the identical typographic purpose — an upright, non-italic
  short label attached as a subscript to a math variable (`grid`/`pts` vs `band`/`rms`/`lo`/`hi`) — yet
  the codebase is split roughly 3:1 between the two commands with no apparent semantic reason for
  the split (it correlates with *which module's docstrings* were written, not with anything about the
  label itself).
- **Description:** Both render nearly identically for plain ASCII content in KaTeX, so this is not a
  rendering defect, but it is exactly the kind of "one concept, two notations" the house style
  otherwise disciplines closely (cf. the deliberate, explained `α` vs `α(k)` and `\hat a` retirements
  recorded in CLAUDE.md). No CLAUDE.md rule currently arbitrates `\text` vs `\mathrm` for this role.
- **Resolution hint:** pick one (`\mathrm{}` is the shorter, and already used for the Greek-letter-adjacent labels like `k_\mathrm{lo}`) and sweep the other family to match; or record the distinction if one is intended (e.g. `\text` for a base name, `\mathrm` for a physical-quantity qualifier) so it stops looking accidental.

## Finding 4 — Several inline math spans are wrapped across a source line break (no current rendering failure, but against the stated rule)

- **Type:** typesetting
- **Severity:** nit
- **Confidence:** medium
- **Locations:** e.g. `docs/ARCHITECTURE.md:751-752` (`` $M \langle W f, q\rangle_{\text{pts}} =\nN \langle f, W^{\top} q\rangle_{\text{grid}}$ ``), `docs/ARCHITECTURE.md:1621-1622` (an `α a +` / `β b` split), `docs/ARCHITECTURE.md:2536-2537` (`` \operatorname{var}(f) = \langle f, f\rangle -\n\langle f\rangle^2 = … ``), `docs/FORMALIZATION.md:131` (`` V = \mathbb R^{3\times3} \to\n\mathbb R ``), `docs/PERFORMANCE.md:732-733` (`` t_\mathrm{threaded} \le 1.1\n t_\mathrm{serial} ``).
- **Description:** CLAUDE.md's rule (c) states inline math must stay on **one source line**, because a
  continuation beginning with a CommonMark list/blockquote leader silently drops the span from math
  mode. I verified in the rendered manuscript that none of these particular continuations begin with
  such a leader (`-`/`*`/`+`/`>`/`1.`), so **all currently render intact** (confirmed against
  `manuscript-full.md` lines 368, 859, 617). This is therefore not a live defect, but it is a violation
  of the rule's literal "ONE source line" wording and is one reflow away from becoming the exact
  failure the rule exists to prevent (e.g. if a future edit inserts a `-` at the start of the wrapped
  line).
- **Resolution hint:** low priority; if the `lint_inline_math()` build lint is ever tightened to flag any multi-line inline span (not just list-leader continuations), these will need joining onto one line first.

## Finding 5 — `\begin{CD}…\end{CD}` commutative-diagram environment: KaTeX support not verified from static output

- **Type:** typesetting
- **Severity:** nit
- **Confidence:** low
- **Locations:** `docs/ARCHITECTURE.md:256-264, 300-305, 369-373` (the three commutative squares — bundle projection, the intertwiner square, the pullback/pushforward diagram), also present in the manuscript unrendered TeX and the pre-built `docs/build/architecture/index.html` (KaTeX renders client-side via JS, so a static-file grep cannot confirm the diagram actually forms).
- **Description:** KaTeX does support a `CD` environment (added for exactly this `@>>>`/`@VVV`-style
  amscd syntax), so this is very likely fine, and the package's own extensive `/check-docs` history
  suggests it would have already surfaced if broken on a page this prominent (§2 of the architecture
  doc). Flagging only because I could not execute the client-side KaTeX pass to confirm it directly
  from the artifacts available, and a broken `CD` render would be a silent, high-visibility failure
  given its placement.
- **Resolution hint:** load `docs/build/architecture/index.html` in a browser (or `julia docs/make.jl` + open) and visually confirm the three diagrams render as arrow squares, not raw `\begin{CD}` text.

---

## Clean by construction (verified, not flagged)

For completeness, the following classes were swept exhaustively and found compliant:

- `\mathrm{i}` for the imaginary unit: 111 occurrences, zero bare-`i` or `\imath` counterexamples.
- `\,\mathrm{d}x`/`\,\mathrm{d}\mu` differentials: every `\mathrm{d}` is preceded by `\,` (or is the
  glossary's own definition row, or the unrelated `\ker \mathrm{d}\pi` pushforward, which needs no
  thin space).
- `\partial_{x_i}` coordinate-subscripted partials: the banned bare-index `\partial_i`/`\partial_j`/`\partial_k` variant has zero occurrences (`lint_notation_variants()`'s own invariant, independently reconfirmed).
- `\det`, `\operatorname{tr}`/`\operatorname{sym}`/`\operatorname{skew}`/`\operatorname{dev}`,
  `\sin`/`\cos`/`\exp`/`\log`, `\mathrm{Re}` (used consistently, never mixed with `\operatorname{Re}`),
  `\overline{\hat g}` for conjugation: all named operators are upright commands, never an italic
  letter-product.
- `\lVert\cdot\rVert` (88) vs `\lvert\cdot\rvert` (80): both used consistently for norm vs.
  absolute-value bars; no bare `\|` or unescaped `|` found.
- `\widehat{…}` reserved for multi-token spectral hats (`\widehat{\Delta f}`, `\widehat{(\nabla u)_{ij}}`, …), `\hat{}` reserved for single-symbol hats (`\hat f`, `\hat g`); no cross-contamination.
- `\mathbb{}`: every instance is on `P`, `R`, `C`, `Z` — never a digit or lowercase letter (other than the sanctioned `k`, which does not in fact occur bare); `\mathbf{1}` correctly used for the indicator function, never `\mathbb{1}`.
- `\mathbf{k}`/`\boldsymbol` bold: confined to the one declared local override in the worked turbulence example, exactly as CLAUDE.md records.
- No `\left`/`\right` outside the one sanctioned `\left\{ … \right.` system brace (and its own documentation of the rule).
- No unbraced `\frac`/`\tfrac` arguments; no `\!` misuse beyond the sanctioned `\sim\!`; no `\;`/`\:` manual spacing commands anywhere in the corpus.
- The Literate-processed `examples/HIST_CPU.jl` (the one example file actually built into the docs site) was swept line-by-line for bare Unicode math glyphs and backtick-wrapped formulas in its full-line `#` comments: clean — the apparent hits are all inside fenced ```sh code blocks, `##`-prefixed code-only comments, or genuine double-backtick math spans. `examples/hist_postprocess.jl` is *not* Literate-processed (confirmed against `docs/make.jl`), so its comments are correctly exempt and were not held to the rendered-prose standard.
