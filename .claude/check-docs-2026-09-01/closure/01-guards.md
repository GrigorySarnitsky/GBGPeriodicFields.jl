RANGE: ac1226e4..HEAD

## Finding 1

- **Verdict:** HONORED
- **Evidence:** `git diff ac1226e4..HEAD -- src/DifferentialOperators.jl docs/ARCHITECTURE.md docs/FORMALIZATION.md` shows all three sites changed identically:
  - `src/DifferentialOperators.jl`: `` \hat u = \mathrm{i}\,a\times\hat w/\lvert a\rvert^{2} `` → `` \hat u = \mathrm{i} a\times\hat w/\lvert a\rvert^{2} ``
  - `docs/ARCHITECTURE.md`: `` (\nabla\times)^{-1}\hat w(k) = \frac{\mathrm{i}\,a\times\hat w}{\lvert a\rvert^{2}} `` → `` \frac{\mathrm{i} a\times\hat w}{\lvert a\rvert^{2}} ``
  - `docs/FORMALIZATION.md`: `` \\hat u(k) = \\frac{\\mathrm{i}\\,a(k) \\times \\hat w(k)}{\\lvert a(k)\\rvert^{2}} , `` → `` \\mathrm{i} a(k) `` (thin space dropped)
  All three carry the same decision-77 `inverse_curl` formula, so the class (this specific gratuitous
  thin space) is gone at every named surface, not merely one.
- **class_surfaces:** The finding's own location list names exactly three surfaces: `src/DifferentialOperators.jl:1179`, `docs/ARCHITECTURE.md:4050`, `docs/FORMALIZATION.md:256` — all three re-derivations of the same `inverse_curl` formula, no others implied (this is a single-formula duplication, not a package-wide convention). All three are swept per the diff above.

## Finding 2

- **Verdict:** HONORED
- **Evidence:** `git diff ac1226e4..HEAD -- src/Fields.jl`: "…is what keeps the transforms allocation-free. `reshape` on an `Array` returns a new `Array` sharing the data…" → "…is what keeps the transforms allocation-free. A `reshape` of an `Array` returns a new `Array` sharing the data…". The reword (not a capitalization of the identifier) matches the rule exactly.
- **class_surfaces:** The finding names one location only (`src/Fields.jl:1392`) and the rule it invokes (CLAUDE.md §Style sentence-opener rule) is a general fleet-wide convention already covered by the guards.sh "sentence opener" scan class, which the banked note reports as clean on re-scan (0 for the class) — i.e. the class-level scan, not just this one line, was re-verified. Treating the guard's own re-run as the class sweep, this is HONORED rather than LINE-ONLY.

## Finding 3

- **Verdict:** HONORED
- **Evidence:** `git diff ac1226e4..HEAD -- src/Convolution.jl` shows both signatures re-wrapped with one additional break, hanging indent preserved:
  - `_exponential_convolution_modes!` docstring signature: now 3 lines, max line length 78 (verified: `sed -n` + `wc -c` on lines 1311-1313 → 78/75/62 chars).
  - `_exponential_combination_modes!` docstring signature: now 3 lines, max line length 86 (lines 1413-1415 → 86/75/62 chars).
  Both ≤ 88 columns, hanging indent under the first argument as required.
  Independently re-ran the guard's own "wide docstring signature (>88)" awk scan across all nine `src/` files (`GUARDS.md` line 78's exact command) and it returns **zero** hits — the class (docstring-signature line width across the whole module surface, not just these two sites) is confirmed swept, not just the two quoted lines.
- **class_surfaces:** The finding names two sites, `src/Convolution.jl:1311` and `:1412`, and explicitly scopes the class to "decision 79's kernel-pair helpers, added 2026-08-30" — i.e. it does not claim other files have the same defect, and the guard's own repo-wide re-scan (rerun independently above) confirms no other docstring signature in any of the nine audited `src/` files exceeds 88 columns.
