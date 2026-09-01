RANGE: ac1226e4..HEAD

## Finding 1

**Verdict:** HONORED

**Evidence:** `git diff ac1226e4..HEAD -- docs/ARCHITECTURE.md` shows, at decision 56 (the
exact quoted line 3061 in the finding), the sentence:

```
that case guard-free after measurement. **(FALSE, per decision 59: the target ``(i,j)`` and source
``(j,i)`` views select disjoint memory, so `mightalias` is `false` and would not reject the call.
No guard is still the right answer, for decision 59's different reason. Marked here because this
belief deferred the defect for a day.)** Rather than ship a check that might break a measured,
```

This is a correction note at exactly the flagged location, in substance matching the fix the
finding itself proposed ("Add a parenthetical correction note at line 3061 … a `mightalias` guard
would in fact accept `sym!(A, A)`"). It states the premise was false, names decision 59 as the
source of the correction, and preserves the operational conclusion (no guard) while attributing it
to the correct reasoning — exactly the shape asked for.

**class_surfaces:** The finding's own text names the contradiction as being between exactly two
sites — decision 56 (`docs/ARCHITECTURE.md:3061`) and decision 59
(`docs/ARCHITECTURE.md:3196–3198`) — and does not claim the false `mightalias` premise is repeated
anywhere else in the log or elsewhere in the docs; it explicitly frames decisions 57/60/61 as the
*correctly-annotated* comparison class, not as further instances of the defect. A grep of
`docs/ARCHITECTURE.md` for `mightalias` (lines 3064, 3067, 3177, 3202, 3203) confirms the only two
substantive claims are the decision-56 site (now corrected) and the decision-59 site (already
correct, unchanged). No other file in the repo mentions `mightalias`. The finding names no sibling
docstring or other page carrying the same false claim, and none was found. Sweep: complete over the
finding's own named class.

## Finding 2

**Verdict:** LINE-ONLY

**Evidence:** The diff fixes exactly the two quoted sites:

```
-      magnitude via `lpnorm(·, Inf)`.
+      magnitude via `lpnorm` at ``p = \infty``.
...
-    base point and *writes a section*, where `mean(φ, ·)` reduces it. It reuses the `_fiberwise_pass!`
+    base point and *writes a section*, where a mapped `mean` reduces it. It reuses the `_fiberwise_pass!`
```

Both backtick-wrapped middle-dot placeholders named in the finding are gone from
`docs/ARCHITECTURE.md`. But the finding explicitly frames this as an instance of a *class* — "this
is precisely the class the rubric singles out by name" (a backtick span holding a non-Julia
placeholder such as a lone `·`) — and that class was not swept. `src/FieldAlgebra.jl:46`, a
rendered module docstring, still reads:

```
sibling of the mapped reductions such as `mean(det, ·)`): `φ` may change the tensor order, and the
```

— the identical defect (a backtick span containing `mean(det, ·)`, with `·` as a placeholder
argument, not valid Julia), on a different doc surface (a `src/` docstring rendered on the API
page) than either quoted site. This is exactly the sibling-surface class the finding's rubric
citation implies is in scope ("never math that merely looks code-ish … a lone ≤/·"), and it was
missed.

**class_surfaces:** The finding names the defect class generically (any backtick span holding a
bare `·` placeholder) rather than an enumerated list of sites, so the sweep obligation is to grep
the corpus for the pattern. Checked: `docs/ARCHITECTURE.md`, `docs/FORMALIZATION.md`,
`docs/TESTING.md`, `docs/PERFORMANCE.md` (clean — no remaining backtick-wrapped `·`), and
`src/*.jl` + `docs/src/*.md` + `examples/*.jl` (grep `` `[^`]*·[^`]*` ``). Found one live instance:
`src/FieldAlgebra.jl:46` (`` `mean(det, ·)` ``, inside the module's rendered docstring, un-swept by
this diff). `src/Reductions.jl:631` and `:705` contain a bare `·` but inside `#`-comments (not
backtick spans, not rendered) — correctly out of scope, not defects. Sweep: incomplete — one real
sibling instance survives.

## Finding 3

**Verdict:** HONORED

**Evidence:** The diff renames the section heading from a section-scoped label to the document-wide
one the citation policy expects:

```
-**References (this section).**
+**References.** The canonical list for the WHOLE document — every section and every docstring cites
+into it, which is why the citation policy and the `check-docs` DOI cross-check both name it
+§References. It sits here because the transfer literature is its largest single block, not because
+its scope is this section.
```

This is exactly the first of the finding's two offered fix options ("rename §10's 'References (this
section)' heading to something that documents it as the file-wide bibliography and drop 'this
section' from its own heading"), including an explanatory sentence for why it lives inside §10 despite
being document-wide. `grep -rn "References (this section)"` across the repo now returns no hits in
`docs/ARCHITECTURE.md` (only in the banked findings/closure files themselves, which is expected —
they are historical records of the finding). `CLAUDE.md`'s four `§References` citations (lines 196,
499, 502, 693) now resolve to prose that self-identifies as exactly that: "The canonical list for
the WHOLE document … §References."

**class_surfaces:** The finding's scope is a single naming mismatch between one `CLAUDE.md` policy
phrase ("`docs/ARCHITECTURE.md` §References") and one heading in `docs/ARCHITECTURE.md`
(`docs/ARCHITECTURE.md:1032`, §10's reference list) — it does not name or imply any other section
carrying the same kind of dangling pointer. Checked `grep -rn "§References" src/*.jl docs/src/*.md`
(excluding the generated `docs/src/architecture.md` mirror) — zero hits, so no other doc surface
points at a `§References` anchor that could be similarly stale. The decision-19 Grafakos citation's
adjacent "cited by that anchor rather than by this section" sentence (line 1050) was checked for
staleness against the rename and remains accurate (it distinguishes a within-§10 anchor, unrelated
to the document-wide rename). Sweep: complete — the finding names one surface and it was fixed with
no sibling left unaddressed.
