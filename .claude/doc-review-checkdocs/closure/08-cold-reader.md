RANGE: d03a2e9c..HEAD

## Finding 1

**Verdict:** HONORED

**Evidence:** `docs/src/notation.md` line 57, the `` `\lvert\cdot\rvert` `` row of the Operators table.
Before: `...the plain-bar spelling ``|k|^2`` is the same symbol...` — a literal, unescaped `|`
inside a table cell, which GFM parses as a column delimiter and breaks the row (exactly the defect
the row's own sentence warns about, one clause later). After (this diff):
```
| ``\lvert\cdot\rvert`` | the pointwise (fiberwise) magnitude. In this table the bars are written
`\lvert…\rvert` because a literal pipe inside a cell is eaten as a column delimiter; in running math
outside tables the plain-bar spelling `\|k\|^2` (with the bars escaped here for the same reason) is
the same symbol, and both denote one concept | `norm` |
```
The literal `|` is now the escaped `\|` inside a plain (non-math) code span, so no bare pipe remains
in the cell.

**class_surfaces:** The finding is scoped to one specific table row in one specific file
(`docs/src/notation.md` Operators table) — its own text names no sibling table or other page. A
sweep for the same defect class (an unescaped `|` inside a Markdown table cell, as opposed to running
prose where a bare `|k|` is harmless) turns up nothing else: every other `|k|`/`|r|`/`|u|`/`|A|`
occurrence in `docs/*.md` and `docs/src/*.md` sits in running prose or a display-math block, never
inside a `| ... | ... |` table row. `docs/ARCHITECTURE.md`'s own tables (§13 decision entries) use
nested bullet lists per the project's own table-avoidance-in-lists convention, so they carry no `|k|`
cells either. Class swept.

## Finding 2

**Verdict:** HONORED

**Evidence:** `docs/FORMALIZATION.md`, Base-space motion section (lines ~739–784), the site named by
the finding. All four terms now carry an inline plain-language gloss at first use:
- "trivialized tangent bundle" (line 745): "*trivialized* meaning the displacement at each point is
  read in the single fixed Cartesian frame the flat torus supplies, so no curvilinear machinery
  enters".
- "connection" (line 760): "No choice of connection (a rule for comparing vectors over different
  points) enters".
- "exponential map" (line 758): "the exponential map of the flat metric — the map carrying a point
  along a vector for unit time".
- "universal cover" (line 759): "lifted to the universal cover, the *unwrapped* picture of the torus,
  in which a coordinate keeps growing instead of folding back".

**class_surfaces:** The finding names only `docs/FORMALIZATION.md` Base-space motion, but the same
terms recur package-wide (they name a vocabulary class, not a single sentence), so the honest sweep
checks the other sites the commit message itself claims to have swept: `docs/ARCHITECTURE.md` §2
(line 111: "a *connection* being the rule that says how to compare vectors sitting over different base
points, and a flat one letting them be compared directly"; line 114 "no tangent bundle of its own"
— both glossed) and §13 decision 73 (lines 3805–3816: "the exponential map of the flat metric, which
carries a point along a vector for unit time" — glossed). `src/Points.jl`'s `displace!` docstring
(finding 6, graded separately) also glosses "universal cover" independently. No remaining bare,
unglossed occurrence of these four terms was found in a `grep -n` sweep of `docs/FORMALIZATION.md`,
`docs/ARCHITECTURE.md`, and `src/Points.jl`. Class swept.

## Finding 3

**Verdict:** HONORED

**Evidence:** `docs/FORMALIZATION.md` Statement 4 (line 782), the exact site named by the finding:
"Interpolation is invariant under the deck group — the whole-period lattice shifts that map the
unwrapped picture onto itself: for any such shift ``x \mapsto x + k \cdot L``...". The gloss is
inline, immediately after the term, matching the finding's own paraphrase ("whole-period lattice
shifts").

**class_surfaces:** `grep -n "deck group" docs/*.md docs/src/*.md src/*.jl` finds exactly this one
occurrence in the whole tree, matching the finding's own claim that the term "is used once" — there
is no sibling site to sweep. Class swept (trivially, since there was only ever one instance).

## Finding 4

**Verdict:** HONORED

**Evidence:** `src/Convolution.jl`, `assignment_window` docstring (the exact site named). Before: "*assignment*
in the particle-mesh sense of depositing point mass onto grid cells, unrelated to the fused elementwise
write that `threading_cutoff` measures" — the disambiguation worked by pointing at a term defined on
a different page (`threading_cutoff`), which a reader landing cold on `Convolution` cannot resolve.
After: "*assignment* in the particle-mesh sense of depositing a point's mass onto the grid cells around
it, not the sense of writing a value into an array" — now self-contained, no cross-page dependency.

**class_surfaces:** The finding is about one specific cross-page disambiguation technique at one site;
its own text does not name a sibling occurrence. A check of the only other place "assignment" carries
the particle-mesh sense (line 1501, `assignment_window`'s reproduction discussion, and line 72's
API-page one-liner) shows neither leans on `threading_cutoff` or any other page to disambiguate — both
read standalone. Class swept.

## Finding 5

**Verdict:** HONORED

**Evidence:** `src/DifferentialOperators.jl` module docstring (the exact site named), now reads: "each
operator is the exact term-by-term derivative of that trigonometric polynomial on the resolved band —
the band a grid's resolution actually represents, which excludes the Nyquist frequency of each
even-length axis — realized as a coefficientwise multiply...". The gloss is inline at first use in the
module docstring itself, not deferred to the umbrella page.

**class_surfaces:** The finding's own text names the umbrella page as the *only* place the term had
been defined ("Defined only on the umbrella page, two pages earlier in the nav") and complains that
`DifferentialOperators` uses it ungloseed — so the site to check is exactly the one now fixed. A
broader check of other bare "resolved band" uses in `src/DifferentialOperators.jl` (line 1309:
"an identity exact on the resolved band — the wavenumbers the grid resolves, excluding each even
axis's..." ) shows that occurrence is independently glossed too. `src/Interpolation.jl`'s "resolved
sub-Nyquist band" (a related but distinct term for `DirectDFT`) was also glossed in this same diff
range (commit 2a43a724). Class swept for the term and page the finding names.

## Finding 6

**Verdict:** HONORED

**Evidence:** `src/Points.jl`, `displace!` docstring (the exact site named), line ~1313. Before:
"Without a `grid` the sum is taken literally, in the universal cover: coordinates may leave the
box...". After: "Without a `grid` the sum is taken literally, in the universal cover — the unwrapped
picture of the torus, in which a coordinate keeps growing instead of folding back: coordinates may
leave the box...". Glossed inline at the exact site the finding names.

**class_surfaces:** "Universal cover" is a term-of-art the finding says needs introducing at this
site; the same term recurs in `docs/ARCHITECTURE.md` (two sites describing `displace!`, per the
commit message — verified at lines ~1010–1015 and ~3821, both now carrying the same inline gloss) and
in `docs/FORMALIZATION.md` (graded under finding 2, also glossed). `grep -n "universal cover"
src/*.jl docs/*.md` turns up no remaining bare occurrence. Class swept.

## Finding 7

**Verdict:** HONORED

**Evidence:** `docs/src/api/Fields.md`, "Spectral kernel protocol" section (the exact site named).
Before: "the kernel-composed differential operators on the whole hierarchy" — ambiguous antecedent
(four storage classes, or tensor orders, per the finding). After: "the kernel-composed differential
operators on all four storage classes" — the ambiguity is resolved by naming the referent directly
rather than leaving a dangling "the whole hierarchy".

**class_surfaces:** The finding is scoped to this one page/section; `grep -n "whole hierarchy"
docs/src/api/*.md docs/*.md src/*.jl` returns nothing anywhere in the tree, so there is no sibling
occurrence of the same ambiguous phrase left standing. Class swept.
