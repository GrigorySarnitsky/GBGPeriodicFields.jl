# /check-consistency — panel synthesis + FINAL dispositions

**Run:** 12 hats · 96 raw findings (1 blocker, 15 major, 57 minor, 23 nit) · 3.2 M tokens.
**Triage:** every finding verified against source/built HTML (4 verification agents + hand checks).
**Fixes:** applied in commits `0385511` (the verified majors) and the follow-up minor-tail commit.
Per-hat raw findings in `NN-<key>.md`. A re-run should read this block and not re-flag settled items.

## ✅ FIXED (verified real)

**Majors (commit 0385511):** E(κ) factor-of-2 → raw output renamed `P(κ)`/`P_{fg}`, `E(κ)=½P` physics-side;
§2 arithmetic 202→206; bare `ik` (decision 19) → `\mathrm{i}k`; rocFFT reconciled to the no-guarantee
contract (user approved); glossary `‖k‖`→`|k|` + FORMALIZATION fiber norm →`|·|`; §10 point types →
`Points`; base/section/fiber gloss on the index; translation_kernel formula's wavenumber-split note.

**Minor tail (this commit):**
- **Performance §6/§7 em-inversion — the blocker, REINSTATED and fixed.** First ruled a false positive
  (the top of §6 reads clean); the latex agent overturned that with the built HTML: bare `sm_120` in
  prose opens an intraword `<em>` that inverts every later code span in the paragraph. 3 sites backticked;
  built HTML verified clean.
- "trace" structure-function misnomer → "per-component" (⅓ of the trace), 16 sites across HIST_CPU,
  HIST_ROCm, hist_postprocess, examples README — formulas/constants were per-component all along.
- RDF complexity `O(N + M log M)` → `O(N log N + M)` (decision 22).
- `Π_m` → `Π_d` (§10 reproduction identity); "negative-definite" → "negative-semidefinite" Laplacian
  (FORMALIZATION); decision-17/19 adjointness restated as the explicit counting sums (the bare `⟨·,·⟩`
  is glossary-bound to the normalized inner, under which the equality is false by N/M).
- `symmetric_gradient!` unmisfiled from PERFORMANCE §7's bounded-allocators list (it is 0-byte audited);
  decision-18's "computed allocation-free" scoped to `inner(f,f)` (the mixed form materializes planes).
- NUFFT tolerance: requested default `tol = 1e-10` vs achieved ~10⁻¹² now distinguished (decision 23).
- FORMALIZATION sinc²-window test re-attributed to `test/rdf.jl`; `convolve!`'s real-even kernel list
  completed with `squared_wavenumber_field`; `weighted_inner` added to the Home + API-overview summaries.
- The public callable `f(x)` moved out of Interpolation's "Internal API" (a `@docs` method selector +
  an `@autodocs` `Filter`; build-verified to render under Transfer operations).
- Typesetting/idiom: `\left[`→`\bigl[` (spectral_cutoff); `\tfrac NM`/`\sqrt3` braced; upright `\mathrm{e}`
  → corpus-majority italic `e` (2 sites); `\epsilon_{ijk}`→`\varepsilon_{ijk}`; `Re_λ`→`\mathrm{Re}_λ`;
  `\operatorname{Re}`→`\mathrm{Re}`; `\text{mean/measure}`→`\mathrm{}`; `\mathrm i`→`\mathrm{i}` sweep
  (12 sites); HIST RK2 display → 2×2 `aligned`; bare `\big`→`\bigl/\bigr`; pairing subscript
  `\texttt{PointSet}`→`\text{pts}` (also removed a code-name-in-math).
- Structure: transform-scratch caveats promoted to `!!! warning` (to_physical!/to_spectral!); `convolve`
  wrapper on the "Allocating form of" template; sym!/skew!/dev! formulas moved to the family's display
  template (and `I` bound); curl!/helmholtz_projection! aliasing contract documented (guards verified in
  the bodies); anterpolate! synonym list delivered (spreading/deposition/PSI-Cell/gridding + Brandt &
  Lubrecht 1990 with the full inline reference) and ARCHITECTURE's "will carry" tense retired;
  mean/std/var semantics + the `corrected` keyword documented; `|·|` row added to the glossary;
  extensive-vs-intensive fixed on Home; tutorial's repo-path pointers → live Architecture links;
  HIST's invariant-number/README citations inlined as words; `--smoke` added to the run commands;
  "public `check_field_compatibility`" → "unexported"; `Sefusatti et al.` → `Sefusatti et al. 2016`.

## ❌ NOT FIXED — confirmed false positives (do not re-flag)

- `FieldSpectralMultipliers(field)` "undocumented" — full docstring at `Fields.jl:~1151`, renders.
- Performance §6/§7 "underscores/jams in the *manuscript*" beyond the sm_120 class — consolidation
  artifacts of the panel's own manuscript build (source + HTML clean): jammed paragraphs, `sm120`
  spelling, list-glued paragraphs, stripped DOIs.
- translation_kernel "shows the rejected naive phase" — the docstring already carries the split + warning.
- `\mathbf{k}` on the HIST page — deliberate Pope-convention disambiguation (`k` = TKE there).
- notation.md macro names "shown literally" — they are backticked code, as intended.
- Extra `\left` sites — substring matches on `\leftrightarrow`/`\leftarrow`.
- k-as-wavenumber vs k-as-TKE on HIST — page-local, deliberate, recorded convention.

## ⚖️ NOT FIXED — deliberate, with reasons (user may overrule)

- **Decision-log 198/118 present-tense counts (4 sites in §13).** The log is append-only and its header
  says later entries supersede; the prior session's recorded convention left historical counts as
  written. The consistency agent dissents ("are unchanged" reads as current fact) and proposed
  "(then-current; now 206/122 — decision 27)" annotations. Left per convention; escalated.
- **LagrangeSpline attribution** — escalated; **user confirmed the current attribution is fine as
  written** (2026-07-15). CLOSED, no change.
- **α as fiber index (Fields) vs α/β accumulation (invariant 10).** Cross-page only; each use locally
  bound; renaming churns ~5 docstrings. Flagged for discretion.
- Grafakos "Thm 2.5.x" placeholder — **RESOLVED 2026-07-15**: confirmed as **Thm 2.5.10** against the
  user's copy (the `ℳ^{2,2}` characterization, `‖T‖_{L²→L²} = ‖û‖_∞`); filled into decision 19,
  tracker paragraph retired from CLAUDE.md, memory note deleted.
- Hockney & Eastwood / Birdsall & Langdon informal asides — policy explicitly permits.
- `⟨·,·⟩` argument-doc style split across modules; the `!`→allocating reverse pointer; `⋅`/`×` @docs
  duplication (language-forced); "assignment" homonym (locally glossed); `N` per-axis re-gloss;
  "reproduction order = moments" (self-defined); `gathered` vs `aligned` — all TRIVIAL-SKIP.

## ⏳ DEFERRED (pre-panel /check-docs triage tier, unchanged)

- **Sentence-opener class — RESOLVED (commit `692f689`).** User's rule: a sentence never opens with a
  lowercase code identifier or a math formula (REWORD to lead with a capitalized word — never capitalize
  the lowercase binding); exempt = bullets / list items (§13 entries, test-file lists, arg-docs), `#`
  code comments (but a Literate example's `# ` prose is NOT exempt), and CAPITALIZED type/module openers
  (user chose "leave capitalized"). Reworded 22 flowing-prose sites across docstrings + design docs +
  Literate examples; codified in CLAUDE.md §Style + the `/check-docs` scan (now catches formula-openers).
- **20 wide (>88-col) docstring signatures — RESOLVED (user: "fully typed, properly wrapped").**
  Hand-wrapped all 20 with a hanging indent under the first argument (the documented `anterpolate!`
  convention), keeping full types; the `pointvalue_tensor_order` `where` clause breaks after `where`.
  Wide-signature scan now zero; build green. (My earlier "untyped headers are the house convention"
  was wrong — the headers are a typed/untyped mix; user caught it, and chose fully-typed for this package.)
- **examples/README.md formula-in-backticks — RESOLVED (user chose LaTeX).** ~40 formulas → GitHub
  MathJax `$…$` (plus a ```math``` block for the Navier–Stokes display); code + figure/file names stay
  backticked; mixed physics-via-call spans render as pure math (`½ inner(u,u)` → ⟨u,u⟩) since the
  function names are already in the prose. Verified: even `$`-balance per line, no leftover
  math-glyph-in-backtick (bar the `ν` Params field), no formula sentence-openers. NOT locally
  checkable — GitHub's MathJax rendering; the 4 bold+math labels (`**$|k|$-field**` etc.) want a
  GitHub-preview eyeball.
