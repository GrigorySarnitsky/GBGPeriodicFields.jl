# Closure grading — 08-cold-reader (7 findings)

Graded against `git diff d03a2e9c..HEAD`, plus a full `julia --project docs/make.jl` build and
inspection of the rendered `docs/build/notation/index.html`.

## Finding 1

**Verdict:** HONORED

**Evidence:** `docs/src/notation.md` diff:
```
-| ``\lvert\cdot\rvert`` | ... the plain-bar spelling ``|k|^2`` is the same symbol, ... | `norm` |
+| ``\lvert\cdot\rvert`` | ... the plain-bar spelling `\|k\|^2` (with the bars escaped here for the same reason) is the same symbol, ... | `norm` |
```
The literal `|k|^2` inside a double-backtick math span was itself a literal pipe eaten as a GFM
column delimiter — the exact defect the surrounding sentence was warning about. The fix re-spells it
with escaped bars in a single-backtick code span, matching the row's own established convention of
quoting raw LaTeX source (`` `\lvert…\rvert` `` earlier in the same cell). Rebuilt the docs
(`julia --project docs/make.jl`, clean lint output) and confirmed in the built
`docs/build/notation/index.html` that the row now renders complete, ending correctly at `<td>norm</td>`
with the full sentence and `<code>|k|^2</code>` intact — it no longer truncates mid-sentence.

**class_surfaces:** The finding is scoped to this one row (`docs/src/notation.md`, Operators table,
the `\lvert\cdot\rvert` row). Swept the rest of `docs/src/notation.md` and the other doc-page tables
(`docs/TESTING.md`/`docs/src/testing.md`) for a second literal-pipe-inside-a-table-cell instance;
none found — this was the only occurrence of the class in the tree. No other surface is named or
implied by the finding's own text.

## Finding 2

**Verdict:** UNDONE

**Evidence:** `git diff d03a2e9c..HEAD -- docs/FORMALIZATION.md` touches only two unrelated regions
(a new "reality condition" entry inserted around line 106–123, and a `weighted_inner` tuple-fusion
addition around line 556–566, plus a one-line edit near 723–728 dropping "and its tensor order"). The
"Base-space motion" section (lines 738–787 in the current file) is byte-for-byte untouched — confirmed
by `grep -n "Base-space motion" -A60 docs/FORMALIZATION.md`, which still reads: "a section ``v`` of
the (trivialized) tangent bundle", "no connection choice enters", "the exponential map of the flat
metric lifted to the universal cover" — none of these terms carry any gloss, exactly as flagged.

**class_surfaces:** Finding's own location IS the whole affected passage
(`docs/FORMALIZATION.md:745` trivialized tangent bundle, `:756` connection / exponential map /
universal cover). None of it was swept.

## Finding 3

**Verdict:** UNDONE

**Evidence:** Same diff evidence as Finding 2 — Statement 4 of the Base-space motion section
(`docs/FORMALIZATION.md:777`, "Interpolation is invariant under the deck group") is untouched by the
diff; `deck group` still appears with no gloss.

**class_surfaces:** `docs/FORMALIZATION.md:777` is the finding's own location; not swept. (No other
occurrence of "deck group" exists elsewhere in the tree to check as a sibling.)

## Finding 4

**Verdict:** HONORED

**Evidence:** `src/Convolution.jl` diff:
```
-of depositing point mass onto grid cells, unrelated to the fused elementwise write that
-`threading_cutoff` measures — as a [`SeparableKernel`](@ref) — its three
+of depositing a point's mass onto the grid cells around it, not the sense of writing a value into an
+array — as a [`SeparableKernel`](@ref) — its three
```
The disambiguating aside no longer sends a cold reader to `threading_cutoff` (a `FiberSections`
binding on a different page) to resolve what "assignment" is not; it now states the contrast
("not... writing a value into an array") in self-contained plain language.

**class_surfaces:** Grepped every `.jl`/`.md` doc surface for `threading_cutoff`
(`grep -rn threading_cutoff src/*.jl docs/*.md docs/src/*.md`); the only remaining hits are inside
`src/GBGPeriodicFields.jl` (its own export list) and `src/FiberSections.jl` (the binding's own home
docstring, where citing it is not a cross-page reference). No other page still leans on
`threading_cutoff` to disambiguate a term the way `assignment_window` used to. Class swept.

## Finding 5

**Verdict:** LINE-ONLY

**Evidence:** `src/DifferentialOperators.jl` module docstring diff:
```
-operator is the exact term-by-term derivative of that trigonometric polynomial on the resolved band,
-the even-axis Nyquist term being zeroed (see the Nyquist split below), realized as a
+operator is the exact term-by-term derivative of that trigonometric polynomial on the resolved band —
+the band a grid's resolution actually represents, which excludes the Nyquist frequency of each
+even-length axis — realized as a coefficientwise multiply ...
```
The cited site (the `DifferentialOperators` module docstring) now glosses "the resolved band" inline,
so that specific page is self-contained.

**class_surfaces:** The finding's own reasoning — "Defined only on the umbrella page, two pages
earlier in the nav" — names the general defect: the term's one home is
`src/GBGPeriodicFields.jl:25`, and every OTHER page that uses it cold shares the exact same problem
this finding is about. Grepped the term across the tree and it is used unglossed, with no link back
to the umbrella definition, in several sibling surfaces the diff never touches:
`src/Interpolation.jl:753,769,1028,1074,1118` ("the resolved sub-Nyquist band" / "the resolved band"),
`docs/FORMALIZATION.md:220,678`, `docs/ARCHITECTURE.md:115,890,1904,1923,2535,2537`, and
`docs/TESTING.md:373`. Only the one named site was patched; the class (this term used cold, off the
umbrella page) was not swept.

## Finding 6

**Verdict:** LINE-ONLY

**Evidence:** `src/Points.jl` diff:
```
-Without a `grid` the sum is taken literally, in the universal cover: coordinates may leave the
+Without a `grid` the sum is taken literally, in the universal cover — the unwrapped picture of the
+torus, in which a coordinate keeps growing instead of folding back: coordinates may leave the
```
The named site (`displace!`'s docstring) now glosses "the universal cover" inline and is
self-contained.

**class_surfaces:** `docs/FORMALIZATION.md`'s "Base-space motion" section is the formal counterpart
of this exact operation (`displace!`) — it "Backs" the same decision (73) and is what
`test/displacement.jl` is checked against, per the doc-chain convention this project's own CLAUDE.md
states ("prose ↔ formalization ↔ test"). That section uses the identical unglossed term "the universal
cover" at `docs/FORMALIZATION.md:756` (Statement 1), and per Findings 2/3 above it was left completely
untouched by this fix pass. The same term, same concept, same operation's formal home — one sibling
swept, the other (linked) sibling not.

## Finding 7

**Verdict:** HONORED

**Evidence:** `docs/src/api/Fields.md` diff:
```
-kernel-composed differential operators on the whole hierarchy, `weighted_inner` on every class
+kernel-composed differential operators on all four storage classes, `weighted_inner` on every class
```
The ambiguous "the whole hierarchy" (which per the finding could read as either the four storage
classes or the tensor orders) is replaced with the explicit, disambiguated "all four storage classes".

**class_surfaces:** Grepped the tree for "whole hierarchy"
(`grep -rn "whole hierarchy" src/*.jl docs/*.md docs/src/*.md docs/src/api/*.md`) — zero remaining
hits anywhere, including the fixed line. No sibling occurrence of this exact ambiguous phrase exists
elsewhere to check; the finding names only this one site and it is the only site. Class swept (trivially,
being a single instance).
