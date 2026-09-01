RANGE: ac1226e4..HEAD

## Finding 1

- **Verdict:** HONORED
- **Evidence:** All three originally-quoted sites fixed
  (`\mathrm{i}\,a` → `\mathrm{i} a`) in `src/DifferentialOperators.jl`,
  `docs/ARCHITECTURE.md`, `docs/FORMALIZATION.md`:
  ```
  -    given ``w``, as one coefficientwise pass ``\hat u = \mathrm{i}\,a\times\hat w/\lvert a\rvert^{2}``
  +    given ``w``, as one coefficientwise pass ``\hat u = \mathrm{i} a\times\hat w/\lvert a\rvert^{2}``
  -(\nabla\times)^{-1}\hat w(k) = \frac{\mathrm{i}\,a\times\hat w}{\lvert a\rvert^{2}},
  +(\nabla\times)^{-1}\hat w(k) = \frac{\mathrm{i} a\times\hat w}{\lvert a\rvert^{2}},
  -\\hat u(k) = \\frac{\\mathrm{i}\\,a(k) \\times \\hat w(k)}{\\lvert a(k)\\rvert^{2}} ,
  +\\hat u(k) = \\frac{\\mathrm{i} a(k) \\times \\hat w(k)}{\\lvert a(k)\\rvert^{2}} ,
  ```
  Independently re-ran guards.sh's own two scan patterns
  (`grep -rnP '\\\\,(?!\\\\mathrm\{d\})' src` and `grep -rnP '\\,(?!\\mathrm\{d\})'`
  over the full `DOCS_MD` array read out of `.claude/commands/check-docs/guards.sh`,
  not merely the four rationale docs) — both zero matches. The round-4 addendum's
  fourth site, `src/DifferentialOperators.jl:576`, still carries `\mathrm{i}\,a` —
  confirmed present — but it sits in a plain `#` comment written with a SINGLE
  backslash, which guards.sh's own src pattern (requiring the double-backslash
  `\\,` a docstring's escaped Julia string produces) structurally cannot and does
  not match, and CLAUDE.md's "plain `#` code comments … are not rendered" clause
  exempts it. The dismissal is not a loophole; it is consistent with the
  instrument's own scan boundary.
- **class_surfaces:** The finding's own text names the class as "decision 77's
  `inverse_curl` formula … carried on three surfaces" — `src/DifferentialOperators.jl:1179`,
  `docs/ARCHITECTURE.md:4050`, `docs/FORMALIZATION.md:256` — with no further surface
  implied beyond that one formula's three renderings (the general rule, "the thin
  space is reserved for the differential", is stated as the rationale for this
  specific formula's sites, not as a separate broader sweep target). All three
  swept. The one additional occurrence found independently (a `#` comment
  restating the same formula) is not a rendered surface and is explicitly
  dismissed with a documented, verified reason in the round-4 addendum, which
  this audit confirms rather than merely accepts on faith.

## Finding 2

- **Verdict:** HONORED
- **Evidence:** `src/Fields.jl:1392`'s quoted sentence fixed:
  ```
  -first, is what keeps the transforms allocation-free. `reshape` on an `Array` returns a new `Array`
  +first, is what keeps the transforms allocation-free. A `reshape` of an `Array` returns a new `Array`
  ```
  This finding's own history in the banked file is a three-round self-correction
  (round 1 claimed clean on a src-only scan; round 3 swept 19 more sites across
  `docs/ARCHITECTURE.md`/`PERFORMANCE.md`/`TESTING.md`/`FORMALIZATION.md` after
  the verifier found the scan's scope was narrower than the documented rule;
  round 4 found the round-3 pattern itself excluded calls/multi-word spans and
  fixed three more survivors: `docs/ARCHITECTURE.md:1017`, `:3279`,
  `docs/PERFORMANCE.md:1496`). I independently re-ran the corrected pattern
  `\.\s+`[a-z][^`]*`` over every surface the round-3/4 addenda claim to cover
  (the four rationale docs, `docs/src/*.md`, `docs/src/api/*.md`, both Literate
  examples, and `src/*.jl`) and got 27 raw hits, every one of which resolves to
  an exempt case on inspection: list-item bullets (`docs/src/testing.md:153,178`,
  numbered decision-log entry `docs/src/architecture.md:3576`/`ARCHITECTURE.md:3576`),
  plain `#` comments in `src/*.jl` (not rendered, exempt by rule), a `#` comment
  inside a fenced ```@autodocs code block in `docs/src/api/FieldAlgebra.md:92`
  (rendered as a code block, not prose), and `examples/hist_postprocess.jl:80`
  (a `#`-comment file that is `include`d at runtime but is NOT processed by
  `Literate.markdown` — verified against `docs/make.jl`, which calls Literate only
  on `examples/HIST_CPU.jl` — so it falls under the ordinary "not rendered" `#`-comment
  exemption, not the Literate-example carve-out). Also independently checked
  `examples/gpu/rocm/HIST_ROCm.jl` (the second Literate example the round-3
  addendum claims to cover): zero hits. No genuine unswept instance found.
- **class_surfaces:** The finding's own text names the class narrowly (one
  sentence in `src/Fields.jl:1392`) but the RULE it cites is package-wide
  ("CLAUDE.md §Style — a sentence opens with …"), and the fixer's own later
  rounds correctly read that as requiring a sweep of every rendered surface —
  which is the right scope for this rule and is the scope I re-verified above.
  Graded HONORED on the final diff state (ac1226e4..HEAD), which is what this
  audit is scoped to; the intermediate rounds' errors are visible in the file's
  own addenda and were self-corrected within the same range.

## Finding 3

- **Verdict:** HONORED
- **Evidence:** Both quoted sites re-wrapped with a hanging indent, verified
  under 88 columns:
  ```
  src/Convolution.jl:1311-1313  (78, 75, 60 cols) — _exponential_convolution_modes!
  src/Convolution.jl:1413-1415  (86, 75, 60 cols) — _exponential_combination_modes!
  ```
  matching the diff:
  ```
  -    _exponential_convolution_modes!(backend, destination, source, multipliers, coefficient,
  -                                    offset_scale, offset_data, α, β, fibres, mode_size)
  +    _exponential_convolution_modes!(backend, destination, source, multipliers,
  +                                    coefficient, offset_scale, offset_data,
  +                                    α, β, fibres, mode_size)
  ```
  (and the identically-shaped edit for `_exponential_combination_modes!`).
- **class_surfaces:** The finding's own text bounds the class explicitly: "Both
  are decision 79's kernel-pair helpers, added 2026-08-30 — the wrap was one
  argument short of the limit when written." No third sibling is named or
  implied (the finding does not say "the exponential family" broadly, only these
  two specific signatures). Both named sites fixed; no other member of the class
  exists per the finding's own scoping.
