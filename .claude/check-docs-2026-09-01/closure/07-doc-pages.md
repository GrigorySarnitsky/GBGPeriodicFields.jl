RANGE: ac1226e4..HEAD

## Finding 1

**Verdict:** HONORED

**Evidence:** `git diff ac1226e4..HEAD -- docs/src/notation.md`:

```
-| ``\lvert\cdot\rvert`` | ... in running math outside tables the plain-bar spelling `\|k\|^2` (with the bars escaped here for the same reason) is the same symbol, and both denote one concept | `norm` |
+| ``\lvert\cdot\rvert`` | ... in running math outside a table the same symbol is written with plain single bars, which cannot be shown in this cell because the literal pipe would split it — note that `\|` is NOT that spelling, being LaTeX's DOUBLE bar and so the ``\lVert\cdot\rVert`` of the next row | `norm` |
```

Both defects the finding named are fixed: (a) the content error — the cell no longer
asserts `\|k\|^2` is "the same symbol"/"the plain-bar spelling"; it now explicitly states
`\|` is NOT that spelling (it is the double-bar `l2norm` glyph), matching the finding's own
correction. (b) the formatting error — the surviving `` `\|` `` single-backtick span is now
used the way the finding's proposed fix explicitly permitted: as a literal citation of the
command text (paired with an explicit "is NOT that spelling" gloss), the same exempted
pattern as `` `\imath` ``/`` `\bigl` `` elsewhere on the page, not as an assertion of a
rendered formula. No bare `\|k\|^2`-as-formula claim remains anywhere.

**class_surfaces:** The finding is a single-cell defect (one table row, `notation.md:57`);
its own text states "Nowhere in `src/` is the escaped-backslash-pipe spelling `\|k\|` used
for this symbol" — i.e., the finding itself asserts this is the ONLY site carrying the wrong
spelling, naming no sibling surface (no other docstring, no other table row) that shares the
defect. Re-checked post-fix: `grep -rn '\\|k\\|' src/ docs/src/` returns nothing, and
`grep -rn 'plain-bar\|plain single bar'` finds only the corrected `notation.md:57` line
itself. There is no other instance of this specific mis-spelling/mis-backtick pattern on the
lane's nine files (the banked "Verified clean" section's check-4 sweep, run before the fix,
found no other single-backtick-LaTeX-as-formula violation on this lane). Class is fully
swept because the class had exactly one member.

## Finding 2

**Verdict:** HONORED

**Evidence:** `git diff ac1226e4..HEAD -- docs/src/index.md docs/src/api.md`:

- `docs/src/index.md:48` (Interpolation bullet): added ", with an optional visit order
  (`transfer_order`, `TransferOrder`) that changes only which point each work-item handles;"
  before the CPU/CUDA/AMDGPU portability clause.
- `docs/src/api.md:14` (Interpolation bullet): added ", an optional visit order
  (`transfer_order`, `TransferOrder`)," before the "together with scheme persistence" clause.

Both quoted locations the finding cited are edited, each now naming
`transfer_order`/`TransferOrder` in one clause, matching the finding's proposed fix
("Add a clause to both bullets... Keep it to one clause per bullet").

**class_surfaces:** The finding names exactly two surfaces — `docs/src/index.md:48` and
`docs/src/api.md:14` — as the two top-level module-summary bullets missing the decision-78
addition ("These two top-level summaries were evidently written... and were not updated").
It does not name or imply a third surface (the finding contrasts these two against
`docs/src/api/Interpolation.md:18-26`, which it explicitly says ALREADY documents the
feature correctly in its own "## Visit order" section, so that page is not part of the
defect class). Both of the two named surfaces are edited in the diff. Class fully swept.
