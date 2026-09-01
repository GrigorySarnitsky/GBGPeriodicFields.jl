RANGE: ac1226e4..HEAD

## Finding 1

**Verdict:** HONORED

**Evidence:** `git diff ac1226e4..HEAD -- examples/HIST_CPU.jl`:
```
-# that its shells sum to the kinetic energy: ``\sum_\kappa E(\kappa) =
-# \tfrac{1}{2}\langle\lvert u\rvert^{2}\rangle = k``, the kinetic energy.
+# that its shells sum to the kinetic energy:
+# ``\sum_\kappa E(\kappa) = \tfrac{1}{2}\langle\lvert u\rvert^{2}\rangle = k``.
```
The inline `` ``…`` `` span now lands entirely on one source line, matching the finding's exact
fix suggestion (and the already-correct `HIST_ROCm.jl` sibling wording).

**class_surfaces:** The finding's own text names only ONE other surface for comparison —
`examples/gpu/rocm/HIST_ROCm.jl:194-195` — and states that surface was *already correct* ("which
already states the identical formula on one line"), not a second site needing a fix. The finding
does not claim or imply any other multi-line inline-span instance exists elsewhere in either file.
I independently swept both files for any other paragraph-level `` ``…`` `` span crossing a source
line (a Python line-scan counting `` `` `` occurrences per full-line `#`/`#md #` comment, run
against both `examples/HIST_CPU.jl` and `examples/gpu/rocm/HIST_ROCm.jl`): every apparent
multi-line "span" found (`HIST_CPU.jl:25-26,234-239,478-483,492-497`,
`HIST_ROCm.jl:263-268`) is inside a ` ```math ` display fence, which is a different Markdown
construct (a literal fenced code block, not a paragraph subject to CommonMark's inline-code-span
line-joining rule that motivates CLAUDE.md's rule (c)) and is explicitly exempt ("inline math
reflows and is exempt" — display blocks are a separate case). No genuine second instance of the
finding's defect class exists in either file, so the single fix fully closes the class as scoped
by the finding.

## Finding 2

**Verdict:** HONORED

**Evidence:** `git diff ac1226e4..HEAD -- examples/gpu/rocm/HIST_ROCm.jl`:
```
-# DNS built on this package is GBGIsotropicTurbulence.jl, documented at
-# https://grigorysarnitsky.github.io/GBGIsotropicTurbulence.jl .
+# DNS built on this package is
+# [`GBGIsotropicTurbulence.jl`](https://grigorysarnitsky.github.io/GBGIsotropicTurbulence.jl).
```
Matches the finding's fix exactly and now mirrors the CPU sibling's form
(`examples/HIST_CPU.jl:12`, unchanged, already correct).

**class_surfaces:** The finding is a single cross-check against one sibling location
(`examples/HIST_CPU.jl:11-12`, already compliant, cited as the correct-form comparator, not a
second defect site). I grepped both files for every other bare mention of a package/module name
(`GBGIsotropicTurbulence`, `GBGPeriodicFields`, `GBGStreamingStatistics`) to check whether the
finding's class (a bare module name in rendered prose) recurs elsewhere: `GBGPeriodicFields`
appears bare at `examples/HIST_CPU.jl:1` and `examples/gpu/rocm/HIST_ROCm.jl` (implicitly, via the
shared title convention) inside the page's level-1 Markdown TITLE HEADING ("# Forced HIT — building
a pseudospectral DNS on GBGPeriodicFields"), and as `using GBGPeriodicFields` in actual code (not
prose, exempt). The finding's own quoted rule and fix are scoped strictly to the one
sentence naming `GBGIsotropicTurbulence.jl` as a demonstration cross-reference; it makes no claim
about the page's own title line, which is a different rendering context (a heading, not body
prose) that the finding never raises. Since the finding does not name or imply the title-heading
site as part of its class, and the one location it does name is fixed and verified against its
own comparator, this is graded HONORED rather than demoted for the unrelated heading occurrence.

## Finding 3

**Verdict:** HONORED

**Evidence:** The banked file's own addendum records an intermediate LINE-ONLY grade (three of
five named sites fixed on the first pass) followed by a second pass closing the remaining two.
Verified directly against the diff and current tree, not merely trusted from the addendum text.
`git diff ac1226e4..HEAD` shows all five originally-named sites converted from bare `` ``L`` `` to
`` \mathcal{L} `` (prose) / `ℒ` (`##` code-comment lines, Unicode-exempt per house style):
- `examples/HIST_CPU.jl:408` — `` L = \int... `` → `` \mathcal{L} = \int... `` (with an inline
  gloss: "written `` \mathcal{L} `` because `` L `` is already the box size on this page").
- `examples/HIST_CPU.jl:503` (`#md` Results section) — same substitution.
- `examples/HIST_CPU.jl:375` (`##` comment) — `L = ∫ρ` → `ℒ = ∫ρ`.
- `examples/gpu/rocm/HIST_ROCm.jl:399` (`##` comment) — `L = ∫ρ` → `ℒ = ∫ρ`.
- `examples/gpu/rocm/HIST_ROCm.jl:431` — `` L = \int... `` → `` \mathcal{L} = \int... ``.

Post-fix grep (`grep -n '``L``\|box size'`) confirms `` ``L`` `` now denotes only the box size
throughout both files (`HIST_CPU.jl:70,91,408-409`; `HIST_ROCm.jl:67`), and a second grep for
"integral length L" / "length L =" returns nothing — no remaining collision.

**class_surfaces:** The finding's own fix bullet enumerates exactly five sites plus one explicit
caveat, so the class is self-bounded by the finding's own text rather than needing external
inference:
1. `examples/HIST_CPU.jl:408` (prose, "Method"/scales section) — swept (`\mathcal{L}`).
2. `examples/HIST_CPU.jl:502-503` (`#md` Results section) — swept (`\mathcal{L}`, landed at line
   503 after the earlier edit shifted numbering).
3. `examples/gpu/rocm/HIST_ROCm.jl:399` (the finding cites this as a *box-size* representative,
   not an integral-length site — re-checked: line 399 in the CURRENT tree is the box-size doc
   comment `L::Float64 = 2π # box size`, unaffected and correctly untouched; the integral-length
   sibling of `HIST_CPU.jl:408` is `HIST_ROCm.jl:431`, which IS swept).
4. `examples/gpu/rocm/HIST_ROCm.jl:431` (the actual integral-length prose site, paired with
   `HIST_CPU.jl:408`) — swept.
5. "the `L_int` HDF5-bundle comment" — the finding names this explicitly. The addendum states this
   was deliberately left unchanged with a stated reason (the `"L_int"` string is a serialized HDF5
   schema key; renaming it breaks every stored bundle a consumer has written). Verified: `git diff`
   shows no change to the `L_int` key or local variable, and `grep -n "L_int"` in both files still
   shows the identifier untouched. This is a reasoned exemption from the fix, not an oversight — the
   underlying defect (bare-`L`-in-rendered-math ambiguity) does not apply to a code identifier that
   is never rendered as bare math notation.

All five named sites are accounted for — four fixed, one explicitly and correctly exempted with a
stated reason that holds up (a schema key is not the "single glyph carries two meanings in
rendered math" defect the finding is about). The addendum's own closing check
(`grep -n "integral length L\b\|length L ="` → empty) was independently re-run and reproduces.
Graded HONORED: the class as the finding itself defined it is fully closed, and the one
non-edit is a defensible, disclosed reason rather than a silent gap.
