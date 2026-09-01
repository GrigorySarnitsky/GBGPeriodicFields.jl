RANGE: ac1226e4..HEAD

Note: the assignment named the banked-findings path as `.claude/check-docs-2026-09-01/08-examples.md`,
which does not exist. The file matching the "examples" hat (header: "Lane 07 — examples
(`examples/HIST_CPU.jl`, `examples/gpu/rocm/HIST_ROCm.jl`)") is banked at
`.claude/check-docs-2026-09-01/07-examples.md`. Graded that file as the intended target; `08-family.md`
is a distinct hat ("family") and is not this lane's assignment.

## Finding 1

**Verdict:** HONORED

**Evidence:** The finding named exactly one violation of "inline math stays on ONE source line"
(`examples/HIST_CPU.jl:168-170`) and the hat's own scope note records that it swept *every*
`` ``…`` `` span in both files for this defect and found only this one instance. The diff:

```
-# that its shells sum to the kinetic energy: ``\sum_\kappa E(\kappa) =
-# \tfrac{1}{2}\langle\lvert u\rvert^{2}\rangle = k``, the kinetic energy.
+# that its shells sum to the kinetic energy:
+# ``\sum_\kappa E(\kappa) = \tfrac{1}{2}\langle\lvert u\rvert^{2}\rangle = k``.
```

Confirmed in the current file (lines 168-170): the whole `` ``…`` `` span now sits on one physical
source line. The finding's suggested reference sibling, `examples/gpu/rocm/HIST_ROCm.jl:194-195`,
already conformed and needed no change (verified unchanged in the diff).

**class_surfaces:** The finding names only one site (`HIST_CPU.jl:168-170`) as the defect and cites
`HIST_ROCm.jl:194-195` only as an already-correct reference form, not a second defect site. The
hat's method section states a full per-line balanced-span check was run across both files and
returned exactly one violation, so the finding's own text implies no other uncorrected surface. Diff
covers the one named site. Class swept as the finding itself scoped it.

## Finding 2

**Verdict:** HONORED

**Evidence:** Diff:

```
-# DNS built on this package is GBGIsotropicTurbulence.jl, documented at
-# https://grigorysarnitsky.github.io/GBGIsotropicTurbulence.jl .
+# DNS built on this package is
+# [`GBGIsotropicTurbulence.jl`](https://grigorysarnitsky.github.io/GBGIsotropicTurbulence.jl).
```

(`examples/gpu/rocm/HIST_ROCm.jl:11-13`). This matches the finding's prescribed fix and the CPU
sibling's form verbatim (backticked module name wrapped as a markdown link to the same URL).

**class_surfaces:** The finding names `examples/gpu/rocm/HIST_ROCm.jl:11-13` as the sole defect site
and `examples/HIST_CPU.jl:11-12` as the already-correct sibling used as the fix template (not a
second defect). The hat's scope note records a full bare-capitalized/CamelCase-word sweep across
both files, finding exactly one violation. No other surface is named or implied. Diff addresses the
one named site; class swept as scoped.

## Finding 3

**Verdict:** LINE-ONLY

**Evidence:** The finding's own "Fix" bullet explicitly lists the required sites: `HIST_CPU.jl:408`,
`HIST_CPU.jl:502-503`, `HIST_ROCm.jl:399`, `HIST_ROCm.jl:431`, and "the `L_int` HDF5-bundle comment."
The diff renames the bare `` ``L`` `` (integral length) to `` ``\mathcal{L}`` `` at three of the four
named rendered-prose sites:

```
- # ``L = \int_0^\infty \rho(r)\,\mathrm{d}r``, which is ...
+ # ``\mathcal{L} = \int_0^\infty \rho(r)\,\mathrm{d}r`` — written ``\mathcal{L}`` because ``L`` is
+ # already the box size on this page — which is ...
```
(`HIST_CPU.jl:407-409`, was :408)

```
-#md # scales are marked: the trace-correlation integral length ``L = \int_0^\infty \rho(r)\,\mathrm{d}r``
+#md # scales are marked: the trace-correlation integral length ``\mathcal{L} = \int_0^\infty \rho(r)\,\mathrm{d}r``
```
(`HIST_CPU.jl:503`)

```
-  # ``C(0) = \langle\lvert u\rvert^{2}\rangle``) gives the integral length ``L = \int_0^\infty \rho(r)\,\mathrm{d}r``
+  # ``C(0) = \langle\lvert u\rvert^{2}\rangle``) gives the integral length ``\mathcal{L} = \int_0^\infty \rho(r)\,\mathrm{d}r``
```
(`HIST_ROCm.jl:431`)

But `examples/gpu/rocm/HIST_ROCm.jl:399` — explicitly named in the finding's fix list — is
untouched: it is a `##`-prefixed code comment ("`## ... integral length L = ∫ρ follow from it ...`"),
unchanged before and after the diff (verified via `git show ac1226e4:...` against current). The
mirror `##` comment in the CPU file (`HIST_CPU.jl:375`, same "integral length L = ∫ρ" wording,
same class, not separately named by number in the finding but the same instance of the collision the
finding is about) is likewise untouched. Neither was addressed. The "`L_int` HDF5-bundle comment"
the finding also names could not be located as a distinct prose site carrying the collision (the
`L_int` occurrences found are all plain `Dict`/variable keys, not math prose), so that part of the
fix instruction is unaccounted for either way.

**class_surfaces:** From the finding's own text: (1) `examples/HIST_CPU.jl:408` — swept (now
`\mathcal{L}`); (2) `examples/HIST_CPU.jl:502-503` — swept; (3) `examples/gpu/rocm/HIST_ROCm.jl:399`
— NOT swept, still bare `L` inside a `##` comment naming the same collision; (4)
`examples/gpu/rocm/HIST_ROCm.jl:431` — swept; (5) "the `L_int` HDF5-bundle comment" — not
identifiable as swept (no matching prose site found changed). Two of five named surfaces were left
untouched, so the class as the finding itself scoped it was not fully swept — LINE-ONLY.
