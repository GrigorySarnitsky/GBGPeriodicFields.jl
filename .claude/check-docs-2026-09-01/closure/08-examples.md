RANGE: ac1226e4..HEAD

## Finding 1

- **Verdict:** HONORED
- **Evidence:** `git diff ac1226e4..HEAD -- examples/HIST_CPU.jl`:
  ```
  -# that its shells sum to the kinetic energy: ``\sum_\kappa E(\kappa) =
  -# \tfrac{1}{2}\langle\lvert u\rvert^{2}\rangle = k``, the kinetic energy.
  +# that its shells sum to the kinetic energy:
  +# ``\sum_\kappa E(\kappa) = \tfrac{1}{2}\langle\lvert u\rvert^{2}\rangle = k``.
  ```
  Confirmed directly in the current file (`examples/HIST_CPU.jl:168-170`): the whole `` ``…`` `` span
  now sits on one physical source line, matching the finding's suggested fix and the already-correct
  `HIST_ROCm.jl:194-195` sibling.
- **class_surfaces:** The finding's own text scopes the class to "any inline `` ``…`` `` span that
  wraps across a source line boundary" across the two example files (`examples/HIST_CPU.jl`,
  `examples/gpu/rocm/HIST_ROCm.jl`), and its own "Positive procedures run" section states every such
  span in both files was checked for balanced open/close per line, with this the only violation
  found. `HIST_ROCm.jl:194-195` is cited only as an already-conforming reference, not a second defect
  site. The finding separately notes `docs/make.jl`'s `lint_inline_math()` does not scan `examples/`
  at all — `git diff ac1226e4..HEAD -- docs/make.jl` is empty, so that lint-coverage gap is untouched,
  but the finding's own "Fix:" instruction asks only for the rewrap, not for extending the lint
  guard, so this is not a shortfall against what the finding actually asked for. The one named site
  is fixed and the finding names no other surface, so the class as scoped is fully swept.

## Finding 2

- **Verdict:** HONORED
- **Evidence:** `git diff ac1226e4..HEAD -- examples/gpu/rocm/HIST_ROCm.jl`:
  ```
  -# DNS built on this package is GBGIsotropicTurbulence.jl, documented at
  -# https://grigorysarnitsky.github.io/GBGIsotropicTurbulence.jl .
  +# DNS built on this package is
  +# [`GBGIsotropicTurbulence.jl`](https://grigorysarnitsky.github.io/GBGIsotropicTurbulence.jl).
  ```
  Confirmed in the current file (`HIST_ROCm.jl:11-13`): backticked and wrapped as a markdown link,
  exactly matching the CPU sibling's form the finding cited as the correct convention.
- **class_surfaces:** The finding names one bare-module-name site (`HIST_ROCm.jl:11-13`) and uses
  `examples/HIST_CPU.jl:11-12` only as the already-correct reference form the fix should match (not a
  second defect). `grep -n GBGIsotropicTurbulence examples/HIST_CPU.jl examples/gpu/rocm/HIST_ROCm.jl`
  finds only these two source occurrences, both now correctly backtick-linked. The finding names no
  other surface, so the class as scoped is fully swept.

## Finding 3

- **Verdict:** HONORED
- **Evidence:** The finding's "Fix" bullet named five sites for the bare-`L` collision (box-size `L`
  vs. trace-correlation integral-length `L`): `HIST_CPU.jl:408`, `HIST_CPU.jl:502-503`,
  `HIST_ROCm.jl:399`, `HIST_ROCm.jl:431`, and "the `L_int` HDF5-bundle comment." The current diff
  (verified directly, not merely trusted from the banked addendum) shows all five accounted for:
  - `HIST_CPU.jl:407-409`: `` ``L = \int...`` `` → `` ``\mathcal{L} = \int...`` `` with an added
    self-contained gloss ("written ``\mathcal{L}`` because ``L`` is already the box size on this
    page").
  - `HIST_CPU.jl:503` (`#md` Results section): same swap to `` \mathcal{L} ``.
  - `HIST_CPU.jl:375` (a `##` code comment, Literate-exempt from rendering but fixed anyway):
    `integral length L = ∫ρ` → `integral length ℒ = ∫ρ`.
  - `HIST_ROCm.jl:399` (same `##` comment class): `L = ∫ρ` → `ℒ = ∫ρ`.
  - `HIST_ROCm.jl:431`: `` ``L = \int...`` `` → `` ``\mathcal{L} = \int...`` ``.
  - `L_int` (`HIST_CPU.jl:415,439`; `HIST_ROCm.jl:436,460`) verified by direct grep to be a plain
    Julia local/Dict key, not rendered math prose — left unchanged with a stated reason (renaming a
    serialized HDF5-bundle key would break every stored bundle a consumer has written), which is a
    dismissal-with-reason rather than a silent gap.
  Round 1's grading (`closure-round1/08-examples.md`) correctly caught this finding as LINE-ONLY at
  that point: the first pass had swapped only the three rendered-prose `` ``…`` `` sites and left both
  `##`-comment sites (`HIST_CPU.jl:375`, `HIST_ROCm.jl:399`) untouched. The addendum recorded in the
  banked findings file plus the diff confirms both remaining sites are now fixed. Independent sweep:
  `grep -nE '``L``|length L( |=)|L = \\int'` over both files returns only the one legitimate
  box-size use (`HIST_CPU.jl:91`, `` "the box size ``L``" ``) and the self-contained gloss sentence
  at `HIST_CPU.jl:408` that explicitly names `` ``L`` `` as the box size while introducing
  `` \mathcal{L} `` for the integral length — no residual collision.
- **class_surfaces:** From the finding's own text: (1) `examples/HIST_CPU.jl:408` — swept
  (`\mathcal{L}`); (2) `examples/HIST_CPU.jl:502-503` — swept; (3)
  `examples/gpu/rocm/HIST_ROCm.jl:399` — swept this round (`ℒ`), was the round-1 gap; (4)
  `examples/gpu/rocm/HIST_ROCm.jl:431` — swept; (5) "the `L_int` HDF5-bundle comment" — resolved by a
  stated reason (serialized schema key, not prose) rather than an edit, and verified that reason is
  accurate (`L_int` is a `Dict` key / local variable, not a math-prose site). The finding's own
  representative-instance list also names `HIST_CPU.jl:91,262` and `HIST_ROCm.jl:67,88,291` as the
  correctly-scoped box-size occurrences that must stay bare `L` (not a defect site) — confirmed
  unchanged and still correctly bare. All five named surfaces are accounted for; none left silently
  untouched.
