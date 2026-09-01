RANGE: ac1226e4..HEAD

## Finding 1

**Verdict:** HONORED

**Evidence:** `git diff ac1226e4..HEAD -- docs/src/notation.md`:

```
-| ``\lvert\cdot\rvert`` | ... in running math outside tables the plain-bar spelling `\|k\|^2` (with the bars escaped here for the same reason) is the same symbol, and both denote one concept | `norm` |
+| ``\lvert\cdot\rvert`` | ... in running math outside a table the same symbol is written with plain single bars, which cannot be shown in this cell because the literal pipe would split it — note that `\|` is NOT that spelling, being LaTeX's DOUBLE bar and so the ``\lVert\cdot\rVert`` of the next row | `norm` |
```

Both defects the finding named are resolved: (a) the wrong content — the old cell asserted
`\|k\|^2` (LaTeX double-bar) *is* the plain-bar spelling of `|k|^2` (single-bar magnitude); the new
cell explicitly states the opposite, that `\|` is the *distinct* double-bar command belonging to
the `l2norm`/`` \lVert\cdot\rVert `` row, not to this `norm` row. (b) the format defect — the old
cell rendered a full formula `` `\|k\|^2` `` in single backticks (monospace, not math); the new
cell drops the formula entirely from the cell (correctly, since a literal single bar would still
collide with the column delimiter) and keeps only `` `\|` `` in single backticks, which is now used
correctly as a literal-command citation (the pattern the finding itself sanctioned, citing
`` `\imath` ``/`` `\bigl` `` as the established precedent), not as an assertion of a formula.

**class_surfaces:** The finding is self-contained to one table cell, `docs/src/notation.md:57`
(the `norm` row). It cites `src/DifferentialOperators.jl:1333`, `src/Fields.jl:1937`,
`src/Convolution.jl:993` only as *evidence* of the correct in-source spelling, not as sibling
surfaces carrying the same defect — those source docstrings were already found correct by the
finding's own text ("every in-source use of this symbol writes the plain, unescaped single bar").
Grepped `docs/src/*.md` and `src/`, `examples/` for "plain-bar"/"plain single bar" post-fix: only
the one now-corrected instance at `notation.md:57` exists. No other surface is named or implied, so
there is no unswept sibling to demote on.

## Finding 2

**Verdict:** HONORED

**Evidence:** `git diff ac1226e4..HEAD -- docs/src/index.md docs/src/api.md`:

`docs/src/api.md` (Interpolation bullet):
```
-... the exact spectral `DirectDFT`, and the fast spectral `NUFFT`, together with scheme persistence (`write_scheme`/`read_scheme`).
+... the exact spectral `DirectDFT`, and the fast spectral `NUFFT`, an optional visit order (`transfer_order`, `TransferOrder`), together with scheme persistence (`write_scheme`/`read_scheme`).
```

`docs/src/index.md` (Interpolation bullet):
```
-... and the fast spectral `NUFFT`; all three schemes' kernels are portable across CPU/CUDA/AMDGPU.
+... and the fast spectral `NUFFT`, with an optional visit order (`transfer_order`, `TransferOrder`) that changes only which point each work-item handles; all three schemes' kernels are portable across CPU/CUDA/AMDGPU.
```

Both of the finding's two quoted locations (`index.md:48` and `api.md:14`) now name
`transfer_order`/`TransferOrder`, each in one added clause, matching the finding's proposed fix
almost verbatim (index.md's clause even echoes the "changes only which point... visit order,
without changing the transferred result" framing from the proposed fix).

**class_surfaces:** The finding names exactly two surfaces — `docs/src/index.md:48` and
`docs/src/api.md:14` — as the two top-level module-summary bullets that were stale; both are the
finding's entire scope (it does not claim a third summary surface is missing the mention). Both are
directly edited in the diff. `docs/src/api/Interpolation.md`'s own "## Visit order" section, cited
by the finding as already-correct evidence that the feature is documented somewhere, is untouched
by the diff and needed no change (the finding never asked for a change there).
