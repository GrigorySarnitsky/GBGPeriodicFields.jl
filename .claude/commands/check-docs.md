---
description: Run the COMPLETE documentation-quality battery — every check across every doc surface, fix all findings, rebuild.
---

Run the **entire** documentation-quality battery. This is the full matrix of (every check) × (every
surface), run to completion in one invocation — not a single check, not a single file. Do not stop after
one check or one file, and do not ask which check to run. Cover every cell, fix every genuine finding in
one pass, rebuild, and report the matrix.

## Surfaces (ALL of them)

1. `docs/ARCHITECTURE.md` — every section §1–§13 and §References.
2. `docs/TESTING.md`, `docs/PERFORMANCE.md`.
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
   derivation. Flag false / imprecise / overclaim.
2. **Self-contained** — enumerate every symbol, sub/superscript, operator name, and bold/blackboard letter;
   cite the clause that binds each; flag any unbound. (Universally standard math — `∇`, `Δ`, `∫`, `ℝ`, `π`,
   the imaginary unit `i`, plain summation indices — needs no binding.)
3. **Notation — one symbol per concept, one concept per symbol, and coordinate-free** — flag a concept
   wearing two symbols; a glyph with two meanings in one section; and basis-dependent *section-level*
   machinery (a dense map matrix `W_{pn}`, an all-ones vector `𝟙`, flattening a section space `ℝ^N⊗V` to
   `ℝ^N`) that buries the base⊗fiber structure. Prefer intrinsic operators and honest sums/integrals; fiber
   component notation (`A_{ij}u_j`, the genuine 3×3 fiber matrix) is fine; if a matrix form mirrors the
   code, name the basis and the space.
4. **Formatted (bidirectional)** — math is LaTeX, never backticks (incl. ASCII-math like `S = J*` that
   carries no glyph); every code identifier / type / module name is backticked, never bare; check BOTH
   directions. Markdown tables top-level, never indented in a list.
5. **Current** — every claim matches the code's present state; no stale *future / deferred / none-exist*.
6. **Cited** — context-standard author–year; ≤3 authors named, `First et al.` for 4+; inline references
   verbatim-consistent with the `ARCHITECTURE.md` §References entry.

`CLAUDE.md` (the doc-edit checklist and the standing notation/structure rules) holds the authoritative
definitions; this command runs all of them.

## Mechanism

- Fan out subagents across the surfaces in parallel — each runs ALL six checks on its surface via the
  positive procedures above, reading `src/` as ground truth, and returns genuine findings with evidence and
  a proposed fix.
- Run the deterministic grep guards too: the table guard `grep -rnE '^[[:space:]]+\|[-:| ]+\|' docs` (must
  be empty); a bare-module-name scan; a glyph-vs-backtick scan.
- Triage (drop false positives — universally standard math; kwarg names correctly backticked), then fix
  EVERY genuine finding in one pass.
- Rebuild: `julia --project=docs docs/make.jl` (doctests + cross-references + render) — must be clean.
- Commit + push (no `[skip ci]`; the docs site must redeploy).

## Report

Report the full matrix: which surfaces × checks were run, the findings (class and count) with fixes, and
what was verified clean. Done only when every cell is covered and the build is clean.
