RANGE: d03a2e9c..HEAD

# Closure verdicts — 08-cold-reader

## Finding 1

**Verdict:** HONORED

**Evidence:** `docs/src/notation.md` Operators table, `\lvert\cdot\rvert` row. Diff:
```
- ...in running math outside tables the plain-bar spelling ``|k|^2`` is the same symbol...
+ ...in running math outside tables the plain-bar spelling `\|k\|^2` (with the bars escaped here for the same reason) is the same symbol...
```
The unescaped literal `|k|` inside a double-backtick math span (itself sitting inside a table
cell) was the exact self-referential defect the finding names: the row explaining why bars must
be escaped in a table cell was itself broken by an unescaped bar. The fix escapes the pipes
(`\|k\|^2`) and drops to a single-backtick span, mirroring the row's own pre-existing convention
one clause earlier (`` `\lvert…\rvert` ``, also single-backtick, showing literal spelling rather
than rendering math) — a consistent, not ad hoc, choice. Confirmed against the rebuilt HTML
(`docs/build/notation/index.html`, built 2026-08-27 12:29, after the fix commits): the row
renders as three intact `<td>` cells ending `...<code>|k|^2</code> (with the bars escaped here for
the same reason) is the same symbol...` and a final `<td><code>norm</code></td>` — not truncated,
and the Code column is not a bare fragment, which is exactly what the finding said was broken.

**class_surfaces:** The finding names one instance: the `\lvert\cdot\rvert` row of the Operators
table in `docs/src/notation.md`. It does not itself claim other rows or pages share the defect. I
independently swept for the same class (a literal, unescaped `|` inside a double- or
single-backtick span on any table-row line) across `docs/ARCHITECTURE.md`, `docs/FORMALIZATION.md`,
`docs/TESTING.md`, `docs/PERFORMANCE.md` and every `docs/src/*.md` page with a script matching
backtick-delimited spans on lines starting with `|`; the only match anywhere in the corpus is this
fixed instance itself (already correctly escaped). The class was swept clean, not merely the one
line.

## Finding 2

**Verdict:** HONORED

**Evidence:** `docs/FORMALIZATION.md` Base-space motion (Statement 1 and its lead-in). Diff:
```
-a `VectorPointValues` is a section ``v`` of the (trivialized) tangent bundle over that
+a `VectorPointValues` is a section ``v`` of the (trivialized) tangent bundle — *trivialized*
+meaning the displacement at each point is read in the single fixed Cartesian frame the flat torus
+supplies, so no curvilinear machinery enters — over that
...
-the exponential map of the flat metric lifted to the universal cover: no connection choice enters,
+the exponential map of the flat metric — the map carrying a point along a vector for unit time —
+lifted to the universal cover, the *unwrapped* picture of the torus, in which a coordinate keeps
+growing instead of folding back. No choice of connection (a rule for comparing vectors over
+different points) enters,
```
All four terms the finding names — trivialized tangent bundle, connection, exponential map,
universal cover — are now glossed in plain language at first use in this section.

**class_surfaces:** The finding's own text ("differential-geometry vocabulary") implies the same
terms could recur unglossed on other pages that discuss the same math (the umbrella §2 overview and
the decision-73 log entry in `docs/ARCHITECTURE.md`, which use the identical vocabulary). Checked:
`docs/ARCHITECTURE.md` was independently glossed in the same fix pass —
`docs/ARCHITECTURE.md:110` ("flat *connection* — its one fixed frame, which lets vectors over
different base points be compared directly"), `docs/ARCHITECTURE.md:1014` ("universal cover ... —
the unwrapped torus, where a coordinate keeps growing instead of folding back"), and
`docs/ARCHITECTURE.md:3814-3823` (exponential map / connection / universal cover all glossed in the
decision-73 entry). The class was swept beyond the one page the finding names.

## Finding 3

**Verdict:** HONORED

**Evidence:** `docs/FORMALIZATION.md` Statement 4. Diff:
```
-deck group: for any whole-period shift ``x \mapsto x + k \cdot L``
+deck group — the whole-period lattice shifts that map the unwrapped picture onto itself: for any such shift ``x \mapsto x + k \cdot L``
```
The term is glossed inline exactly where the finding says it was bare.

**class_surfaces:** The finding says the term "is used once" — that is the finding's own scope
statement, so there is no wider class to sweep. Confirmed by grep: `deck group`/`deck-invariant`/
`deck invariance` occur only in this one FORMALIZATION.md statement (and its mirrored
`docs/src/formalization.md` copy) across the whole doc corpus and `src/*.jl`; no other site needed
touching.

## Finding 4

**Verdict:** HONORED

**Evidence:** `src/Convolution.jl` `assignment_window` docstring. Diff:
```
-of depositing point mass onto grid cells, unrelated to the fused elementwise write that
-`threading_cutoff` measures — as a [`SeparableKernel`](@ref) — its three
+of depositing a point's mass onto the grid cells around it, not the sense of writing a value into an
+array — as a [`SeparableKernel`](@ref) — its three
```
The fix keeps the disambiguation (still tells the reader what "assignment" is *not*) but removes
the dependence on `threading_cutoff`, an unglossed term from another page — the disambiguating
clause is now self-contained ("the sense of writing a value into an array"), so a reader landing on
`Convolution` cold no longer needs to resolve an external reference. This is a genuine fix, not a
deletion of the disambiguating content.

**class_surfaces:** Checked whether `threading_cutoff` is referenced from any other page/module
without being defined locally — it is not; every remaining occurrence is inside `FiberSections.jl`
itself (`src/FiberSections.jl:16,158,196,198,216,225`), where it is defined, or in the umbrella
export list. No other cold cross-page reference to it remains.

## Finding 5

**Verdict:** HONORED

**Evidence:** `src/DifferentialOperators.jl` module docstring. Diff:
```
-operator is the exact term-by-term derivative of that trigonometric polynomial on the resolved band,
-the even-axis Nyquist term being zeroed (see the Nyquist split below), realized as a
-coefficientwise multiply by a wavenumber symbol with no finite-difference truncation. The wavenumber
+operator is the exact term-by-term derivative of that trigonometric polynomial on the resolved band —
+the band a grid's resolution actually represents, which excludes the Nyquist frequency of each
+even-length axis — realized as a coefficientwise multiply by a wavenumber symbol with no
+finite-difference truncation. The two symbol families treat that Nyquist term differently and
+deliberately so (see the Nyquist split below), so it is not simply zeroed everywhere. The wavenumber
```
"The resolved band" is now glossed in plain language at its first use on this page, rather than
relying on the reader having already read the umbrella module's definition two pages earlier in the
nav. (The edit also correctly drops a stale overclaim — "the even-axis Nyquist term being zeroed" —
that contradicted invariant 5's documented split between the two multiplier families; a bonus
correctness fix, not a defect.)

**class_surfaces:** The finding's own text names the specific problem as "defined only on the
umbrella page" — implying other module docstrings that use "the resolved band" without a nearby
gloss are the same class. Checked every other module (`Reductions.jl`, `Convolution.jl`,
`Interpolation.jl`, `Points.jl`, `FieldAlgebra.jl`, `Fields.jl`): the term appears nowhere else in
an unglossed module-docstring context — its other in-file uses inside `DifferentialOperators.jl`
itself (lines 1309, 1331) were already glossed inline before this fix, and its one other
appearance (`Interpolation.jl:1119`) is inside an error-message string, a different surface the
finding did not name. No sweep gap found.

## Finding 6

**Verdict:** HONORED

**Evidence:** `src/Points.jl` `displace!` docstring. Diff:
```
-Without a `grid` the sum is taken literally, in the universal cover: coordinates may leave the
+Without a `grid` the sum is taken literally, in the universal cover — the unwrapped picture of the
+torus, in which a coordinate keeps growing instead of folding back: coordinates may leave the
```
Glossed exactly where the finding points.

**class_surfaces:** "The universal cover" also appears at `src/Points.jl:1162` (a `#` code comment,
exempt from the gloss rule per CLAUDE.md's documentation policy — comments are not rendered) and,
per Finding 2's evidence above, was independently glossed in `docs/ARCHITECTURE.md` and
`docs/FORMALIZATION.md` in this same fix pass. No unswept unglossed instance remains on any rendered
surface.

## Finding 7

**Verdict:** HONORED

**Evidence:** `docs/src/api/Fields.md` "Spectral kernel protocol" section. Diff:
```
-kernel-composed differential operators on the whole hierarchy, `weighted_inner` on every class
+kernel-composed differential operators on all four storage classes, `weighted_inner` on every class
```
The ambiguous phrase is replaced with the explicit, disambiguated reading ("all four storage
classes"), resolving exactly the ambiguity the finding named (four storage classes vs. tensor
orders).

**class_surfaces:** The finding names one phrase on one page. Grep across the full corpus
(`src/*.jl`, `docs/*.md`, `docs/src/**/*.md`) for "the whole hierarchy" returns zero remaining
matches — the phrase does not recur anywhere else needing the same fix.
