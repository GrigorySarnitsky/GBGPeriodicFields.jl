RANGE: ac1226e4..HEAD

## Finding 1

- **Verdict:** HONORED
- **Evidence:** `git diff ac1226e4..HEAD -- docs/src/notation.md` shows the `norm` row's cell rewritten:
  the false claim "in running math outside tables the plain-bar spelling `\|k\|^2` … is the same
  symbol" is replaced with "in running math outside a table the same symbol is written with plain
  single bars, which cannot be shown in this cell because the literal pipe would split it — note that
  `\|` is NOT that spelling, being LaTeX's DOUBLE bar and so the ``\lVert\cdot\rVert`` of the next
  row." Both defects the finding named are gone: (a) the cell no longer asserts `\|k\|^2` in single
  backticks as if it were the running-math spelling (the single-backtick span now cites the literal
  LaTeX command `\|` itself, the same legitimate use-pattern the finding itself approved for
  `\lvert…\rvert`/`\imath`/`\bigl`), and (b) the content is now correct — it explicitly says `\|` is
  the *double*-bar command, not the plain-bar spelling, matching the finding's own correctness
  argument. The fixer did not literally follow the finding's proposed fix (rendering `` ``|k|^2`` ``
  directly in the cell) — but that proposed fix would itself violate the project's own documented
  table rule ("keep literal `|` out of cells … even inside math", `CLAUDE.md`), so declining it and
  instead stating the constraint honestly is the more correct outcome, not a lesser one.
- **class_surfaces:** The finding's own text states the check was run against `src/` usage
  (`src/DifferentialOperators.jl:1333`, `src/Fields.jl:1937`, `src/Convolution.jl:993`) and concludes
  "Nowhere in `src/` is the escaped-backslash-pipe spelling `\|k\|` used for this symbol" — i.e. the
  finding itself establishes this is an isolated, one-cell defect in `docs/src/notation.md:57`, not a
  repeated pattern across other doc surfaces or docstrings. A independent grep for the erroneous
  spelling (`\|k\|`, `` `\\|` ``) across `docs/src/` after the fix returns nothing beyond the corrected
  line, confirming no sibling instance was left unswept. No other surface is named or implied by the
  finding's own text, so there is nothing further to sweep.

## Finding 2

- **Verdict:** HONORED
- **Evidence:** `git diff ac1226e4..HEAD -- docs/src/index.md docs/src/api.md` shows both cited bullets
  edited to name the new entry point. `api.md:14`: "...the fast spectral `NUFFT`, **an optional visit
  order (`point_traversal_order`, `PointTraversalOrder`)**, together with scheme persistence...". `index.md:48`:
  "...the fast spectral `NUFFT`, **with an optional visit order (`point_traversal_order`, `PointTraversalOrder`)
  that changes only which point each work-item handles**; all three schemes' kernels are portable...".
  Both are exactly the two locations the finding quoted (`index.md:48` and `api.md:14`), both now name
  both `point_traversal_order` and `PointTraversalOrder`, and each addition is scoped to one clause as the finding's
  proposed fix requested, without disturbing the rest of the bullet.
- **class_surfaces:** The finding names exactly two surfaces as the complete set to fix — the
  `index.md:48` "Main components" bullet and the `api.md:14` "API overview" bullet — and states
  explicitly that the module's own dedicated page (`docs/src/api/Interpolation.md:18-26`, "## Visit
  order") already documents the feature and was not itself missing anything. No third top-level summary
  surface is named or implied (the finding does not, for instance, point at the `tutorial.md` or any
  other module's bullet). Both of the two named surfaces are edited in the diff, so the finding's own
  complete surface list is swept.
