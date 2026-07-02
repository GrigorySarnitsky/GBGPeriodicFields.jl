---
description: Run the COMPLETE documentation-quality battery — every check across every doc surface, fix all findings, rebuild.
---

Run the **entire** documentation-quality battery. This is the full matrix of (every check) × (every
surface), run to completion in one invocation — not a single check, not a single file. Do not stop after
one check or one file, and do not ask which check to run. Cover every cell, fix every genuine finding in
one pass, rebuild, and report the matrix.

## Surfaces (ALL of them)

1. `docs/ARCHITECTURE.md` — every section §1–§13 and §References.
2. `docs/FORMALIZATION.md`, `docs/TESTING.md`, `docs/PERFORMANCE.md`.
3. Every docstring in `src/*.jl` — FiberSections, Fields, FieldAlgebra, DifferentialOperators,
   Convolution, Points, Interpolation, Reductions, and the umbrella `GBGPeriodicFields.jl` (Public **and**
   Internal docstrings; `#` comments are exempt — not rendered).
4. Every page in `docs/src/` — `index.md`, `tutorial.md`, and all `docs/src/api/*.md` (hand-written prose;
   skip `@autodocs` / `@example` / `@repl` / `@contents` / `@index` blocks).

## Checks (ALL of them, on every surface)

Run each as a POSITIVE procedure — enumerate, then verify each item. A defect that is absent-by-omission
(an unbound symbol; a false-but-plausible formula) does not announce itself on a read-through, so passive
reading is not a check.

1. **Correct** — enumerate every formula, normalization constant (the `1/N`, `1/N²`, `2π/L`, Parseval
   factors), adjoint/conservation relation, complexity claim, and quantifier (*exact / all / never /
   bit-for-bit*); verify EACH against the implementation in `src/` (read it, quote the decisive line) or by
   derivation. Flag false / imprecise / overclaim. For a nontrivial statement the sharpest method is to
   write it formally on scratch (types from the code) and expand it. The verified statements live in
   `docs/FORMALIZATION.md`: check each nontrivial prose claim **against its entry** (the chain is *prose ↔
   formalization ↔ test* — the prose agrees with the typed statement, the statement is verified against the
   code, the linked test enforces it), and flag any nontrivial statement with **no entry**, or an entry with
   **no test link**, as a coverage gap.
2. **Self-contained** — enumerate every symbol, sub/superscript, operator name, and bold/blackboard letter;
   cite the clause that binds each; flag any unbound. (Universally standard math — `∇`, `Δ`, `∫`, `ℝ`, `π`,
   the imaginary unit `i`, plain summation indices — needs no binding.) **And, separately, from each
   docstring's *signature*:** enumerate every argument (positional *and* keyword) and cite where the body
   documents it — an argument mentioned only *inside a formula* reads as bound-by-use and is `UNDOCUMENTED`.
   **And the same bar binds *terms of art*, not only symbols:** a noun naming a package concept (an
   *assignment*, a *section*, a *cutoff*, "the destination's length") must be explained in a clause on the
   page or `@ref`-linked, not left correct only to a reader who already knows the package — the **cold read**
   (parse the docstring with the module's source withheld) is the test (`threading_cutoff`'s "element count
   … assignment" passed the symbol sweep and still baffled a fresh reader). Run this in the cold-reader lane.
3. **Notation — one symbol per concept, one concept per symbol, and coordinate-free** — flag a concept
   wearing two symbols; a glyph with two meanings in one section; and basis-dependent *section-level*
   machinery (a dense map matrix `W_{pn}`, an all-ones vector `𝟙`, flattening a section space `ℝ^N⊗V` to
   `ℝ^N`) that buries the base⊗fiber structure. Prefer intrinsic operators and honest sums/integrals; fiber
   component notation (`A_{ij}u_j`, the genuine 3×3 fiber matrix) is fine; if a matrix form mirrors the
   code, name the basis and the space. (`docs/FORMALIZATION.md` is exempt — it is the home for those
   coordinate/matrix expansions — but still subject to *Correct*.)
4. **Formatted (bidirectional)** — math is LaTeX, never backticks (incl. ASCII-math like `S = J*` that
   carries no glyph); every code identifier / type / module name is backticked, never bare; check BOTH
   directions. Markdown tables top-level, never indented in a list. Also the *silent* failures (source looks
   right, page renders broken): a code name never *inside* a ``…`` span, a formula never split across a
   ``…``/`` `code` `` boundary, inline math on one source line (build-enforced), and no >88-col signature or
   wide unbroken display block (horizontal scroll).
5. **Current** — every claim matches the code's present state; no stale *future / deferred / none-exist*;
   and **complete** — a docstring or summary that names only a *subset* of what the code now provides is
   stale even if literally true (e.g. a module docstring naming one of two scheme families, or a capability
   list missing a builder). Check each module/operation/summary still names everything added since it was
   written, against the current `export`s / method set.
6. **Cited** — context-standard author–year; ≤3 authors named, `First et al.` for 4+; inline references
   verbatim-consistent with the `ARCHITECTURE.md` §References entry.
7. **Consistent across variant pairs** (the `src/` docstrings — *relational*, not per-surface) — group each
   operation's generics (allocating `f` / in-place `f!`, getter / `set_…!`, physical / spectral) and confirm
   the defining math (formula, spectral kernel) lives in **one home**, every other variant a thin
   `@ref`-linking wrapper with no second copy of the formula and no notation that differs across the pair
   (the `\partial_i` vs `\partial_{x_i}` drift). Checks 1–6 each run inside one string and cannot see this;
   run it in the family lane. See `CLAUDE.md` §Style, "the review unit is the operation family and the cold read".

`CLAUDE.md` (the doc-edit checklist and the standing notation/structure rules) holds the authoritative
definitions; this command runs all of them.

## Mechanism

- Fan out subagents across the surfaces in parallel — each runs checks 1–6 on its surface via the
  positive procedures above, reading `src/` as ground truth, and returns genuine findings with evidence and
  a proposed fix.
- Two **cross-cutting lanes** (their grouping is not per-surface, so the surface agents cannot run them):
  a **family lane** that enumerates each operation's `f`/`f!` (and getter/`set_…!`) generics and diffs their
  docstrings for one-home + notation (check 7); and a **cold-reader lane** — an agent handed each exported
  docstring's text *alone, without the module's source*, reporting every term of art it cannot parse (check
  2's audience half). Neither is expressible as a grep.
- Run the deterministic grep/awk guards below, plus a bare-module-name scan and a glyph-vs-backtick scan
  (Unicode math *outside* a backtick span). Inline-math-on-one-line and canonical notation are
  **build-enforced** — `docs/make.jl`'s `lint_inline_math()` errors on a span split by a list leader and
  `lint_notation_variants()` on a bare-index `\partial_[ijk]` — so the rebuild below IS those guards; the
  **argument-coverage** sweep (from each signature, positional + keyword; §Style) runs inside check 2.

```bash
grep -rnE '^[[:space:]]+\|[-:| ]+\|' docs                         # tables top-level only — must be empty
grep -rnE '`[^`]*[≤≥≠∈∉∇Δ⟨⟩‖√][^`]*`' src docs/src docs/*.md      # formula-in-backticks → should be ``LaTeX``
grep -rnE '\$[^$]*[\\_^{}][^$]*\$' docs                           # stray TeX $…$ → use ``…`` / ```math```
grep -rniE '\bknobs?\b' docs src examples                         # neutral register — must be empty
grep -rnE '\\partial_[ijk]' src docs/*.md docs/src                # bare-index ∂ → canonical \partial_{x_i}; build-enforced, must be empty
awk '/^"""/{d=!d;s=d;next} s&&/^[^ ]/{s=0} s&&/^    [A-Za-z_].*\(/&&length>88{print FILENAME":"FNR}' src/*.jl  # wide docstring signatures — FNR (per-file), NOT NR
```

- Triage (drop false positives — universally standard math; the real Julia operators `×`/`⋅`/`≈`; pervasive
  shorthand `L²`/`N³`/`O(N²)`; `#`-comment hits; kwarg names correctly backticked), then fix EVERY genuine
  finding in one pass.
- Rebuild: `julia --project=docs docs/make.jl` (doctests + cross-references + render) — must be clean.
- Commit + push (no `[skip ci]`; the docs site must redeploy).

## Report

Report the full matrix: which surfaces × checks were run, the findings (class and count) with fixes, and
what was verified clean — including the `FORMALIZATION.md` coverage (every nontrivial operation has a typed
entry, each test-linked), the **family lane**'s one-home/notation audit of each `f`/`f!` pair, and the
**cold-reader lane**'s pass over the exported docstrings. Done only when every cell is covered and the build
is clean.
