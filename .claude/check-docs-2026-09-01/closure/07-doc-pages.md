RANGE: ac1226e4..HEAD

## Finding 1

- **Verdict:** HONORED
- **Evidence:** `git diff ac1226e4..HEAD -- docs/src/notation.md`:
  ```
  -| ``\lvert\cdot\rvert`` | ... in running math outside tables the plain-bar spelling `\|k\|^2` (with the bars escaped here for the same reason) is the same symbol, and both denote one concept | `norm` |
  +| ``\lvert\cdot\rvert`` | ... in running math outside a table the same symbol is written with plain single bars, which cannot be shown in this cell because the literal pipe would split it — note that `\|` is NOT that spelling, being LaTeX's DOUBLE bar and so the ``\lVert\cdot\rVert`` of the next row | `norm` |
  ```
  The false claim (that the plain-bar spelling is `\|k\|^2`, and that `\|` denotes a single bar) is
  removed. The replacement no longer asserts a specific spelling inside the cell (sidestepping the
  literal-pipe-in-table hazard the fixer correctly reasoned about, rather than literally following the
  finding's proposed `` ``|k|^2`` `` inline substitution, which would itself have re-triggered the
  pipe-as-delimiter hazard the row already documents) and instead explicitly corrects the
  mis-identification: "`\|` is NOT that spelling, being LaTeX's DOUBLE bar". The one remaining
  single-backtick span, `` `\|` ``, cites the literal LaTeX command token (not rendered as math),
  which matches the page's own established convention for citing raw command text (`` `\imath` ``,
  `` `\bigl` `` at line 20) — the same convention the finding itself endorsed keeping for the adjacent
  `` `\lvert…\rvert` `` span. A targeted grep (`\\|k\\|` / `\|k\|`) across `docs/` and `src/` after the
  fix finds zero remaining instances of the incorrect spelling anywhere in the tree.
- **class_surfaces:** The finding is a single-cell, single-location defect (`docs/src/notation.md:57`);
  it names no sibling docstring, no other page, and no other convention instance as also carrying the
  error — its only other citations (`src/DifferentialOperators.jl:1333`, `src/Fields.jl:1937`,
  `src/Convolution.jl:993`) are quoted as the CORRECT reference usage the table cell should match, not
  as additional broken sites. The finding's own enumeration procedure (Enumeration section: "Nowhere
  in `src/` is the escaped-backslash-pipe spelling `\|k\|` used for this symbol") already establishes
  this is the sole occurrence, and a post-fix grep confirms no instance survives. No other surface for
  this specific class is implied by the finding text.

## Finding 2

- **Verdict:** HONORED
- **Evidence:** `git diff ac1226e4..HEAD -- docs/src/index.md docs/src/api.md`:
  - `docs/src/api.md:14` — Interpolation bullet gains: "...the exact spectral `DirectDFT`, and the
    fast spectral `NUFFT`, an optional visit order (`transfer_order`, `TransferOrder`), together with
    scheme persistence...".
  - `docs/src/index.md:48` — Interpolation bullet gains: "...the fast spectral `NUFFT`, with an
    optional visit order (`transfer_order`, `TransferOrder`) that changes only which point each
    work-item handles; all three schemes' kernels are portable...".
  Both of the two locations the finding cites verbatim (`docs/src/index.md:48` and
  `docs/src/api.md:14`) now name `transfer_order`/`TransferOrder`, matching the finding's proposed fix
  in substance (one added clause per bullet, terse, consistent with the surrounding additions already
  listed).
- **class_surfaces:** The finding names exactly two surfaces as stale — `docs/src/index.md:48` and
  `docs/src/api.md:14` — and explicitly notes the module's own API page
  (`docs/src/api/Interpolation.md:18-26`) already documents `transfer_order` correctly, i.e. that page
  is cited as already-current, not as a third omission site. Both of the two cited surfaces are fixed
  in the diff; no other surface is named or implied by the finding's own text.
