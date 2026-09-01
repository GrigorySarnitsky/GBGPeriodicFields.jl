RANGE: ac1226e4..HEAD

## Finding 1

- **Verdict:** HONORED
- **Evidence:** `git diff ac1226e4..HEAD -- examples/HIST_CPU.jl` shows the multi-line inline math
  span at the finding's cited location was rewrapped onto one physical line:
  ```
  -# that its shells sum to the kinetic energy: ``\sum_\kappa E(\kappa) =
  -# \tfrac{1}{2}\langle\lvert u\rvert^{2}\rangle = k``, the kinetic energy.
  +# that its shells sum to the kinetic energy:
  +# ``\sum_\kappa E(\kappa) = \tfrac{1}{2}\langle\lvert u\rvert^{2}\rangle = k``.
  ```
  This matches the finding's own suggested fix and now matches the sibling passage in
  `HIST_ROCm.jl:194-195`, which the finding already noted was correctly single-line.
- **class_surfaces:** The finding's own text frames the class as "any inline `` ``…`` `` span that
  wraps across a source line boundary" in a Literate example (`examples/HIST_CPU.jl`,
  `examples/gpu/rocm/HIST_ROCm.jl`), and separately flags that `docs/make.jl`'s `lint_inline_math()`
  does not scan `examples/` at all (verified: `git diff ac1226e4..HEAD -- docs/make.jl` is empty, so
  that lint-coverage gap is untouched — but the finding's own "Fix:" section asks only for the
  rewrap, not for extending the lint, so this is not a shortfall against what was actually asked).
  I independently swept both example files for any other odd-count `` `` `` occurrence per source
  line (`awk` script counting `` `` `` per line, filtering out fenced ` ```math `/` ```sh ` block
  markers) and found none — the one cited instance was the only multi-line inline-math span in
  either file. The class (as the finding itself scopes it — the two example files) is therefore
  fully swept, not merely the quoted line.

## Finding 2

- **Verdict:** HONORED
- **Evidence:** `git diff ac1226e4..HEAD -- examples/gpu/rocm/HIST_ROCm.jl`:
  ```
  -# DNS built on this package is GBGIsotropicTurbulence.jl, documented at
  -# https://grigorysarnitsky.github.io/GBGIsotropicTurbulence.jl .
  +# DNS built on this package is
  +# [`GBGIsotropicTurbulence.jl`](https://grigorysarnitsky.github.io/GBGIsotropicTurbulence.jl).
  ```
  Exactly the finding's suggested fix, now matching the CPU sibling's form the finding cited as the
  correct convention.
- **class_surfaces:** The finding names the specific bare module-name instance and cross-checks it
  against the one sibling occurrence in `examples/HIST_CPU.jl:11-12` (already correctly backticked
  and linked, used as the reference form — no fix needed there). I grepped both example files (and
  `docs/src/examples/`, `docs/build/examples/` mirrors) for every occurrence of
  `GBGIsotropicTurbulence` and found only these two source occurrences, both now correctly
  backtick-linked; the one other repo hit (`docs/make.jl:204`, a `#`-comment provenance note, not
  rendered prose) is outside this finding's class (internal build-script comment, not a Literate
  example). No other bare occurrence remains anywhere the finding's class reaches.

## Finding 3

- **Verdict:** HONORED
- **Evidence:** The finding named five representative sites for the bare-`L` collision (box size vs.
  trace-correlation integral length) and asked for the integral-length occurrences to get a distinct
  symbol, consistently, across both files plus the `L_int` HDF5-bundle comment. The diff (plus the
  banked file's own "Fix-pass addendum" section, corroborated against the diff rather than trusted
  on its word) shows:
  - `HIST_CPU.jl:408-409`: `` ``L = \int...`` `` → `` ``\mathcal{L} = \int...`` — written
    ``\mathcal{L}`` because ``L`` is already the box size on this page`` (adds the missing
    self-contained binding for the new symbol, not just a swap).
  - `HIST_CPU.jl:502-503` (the `#md` Results section): same swap to `` \mathcal{L} ``.
  - `HIST_CPU.jl:375` (a `##` code-comment line, Literate-exempt from rendering but fixed anyway):
    `integral length L = ∫ρ` → `integral length ℒ = ∫ρ`.
  - `HIST_ROCm.jl:399` (same `##` line): `L = ∫ρ` → `ℒ = ∫ρ`.
  - `HIST_ROCm.jl:431`: `` ``L = \int...`` `` → `` ``\mathcal{L} = \int...`` ``.
  - `L_int` (the HDF5 bundle key/local, `HIST_CPU.jl:415,439`, `HIST_ROCm.jl:436,460`) is
    deliberately left unchanged, with a stated reason (serialized schema key; renaming would break
    stored bundles) — a dismissal-with-reason, not a silent omission.
  I independently verified completeness: `grep -n '\bL\b'` over both files (excluding `L_int`,
  `L_{11}`, `mathcal{L}`, and the `L)` interval notation) shows every remaining bare `L` is
  genuinely box-size usage (`p.L`, `"box size L"`, `\lambda \ll L`, the `@printf` runtime label,
  `"L_box"`) — no residual collision anywhere in either file. All five sites the finding itself named
  are addressed, and the sweep for the class (bare `L` denoting the integral length anywhere in
  either example file) comes back empty.
- **class_surfaces:** The finding's own text names the class exactly: `HIST_CPU.jl:91,262` (box
  size — correctly left as `L`), `HIST_CPU.jl:408,502-503` (integral length — fixed to
  `\mathcal{L}`), `HIST_ROCm.jl:67,88,291` (box size — correctly left as `L`) vs.
  `HIST_ROCm.jl:399,431` (integral length — fixed to `ℒ`/`\mathcal{L}`), plus "the `L_int`
  HDF5-bundle comment" (deliberately declined with a stated reason). Every site the finding names is
  accounted for by the diff, either fixed or explicitly dismissed with a reason tied to a concrete
  cost (breaking a serialization schema) rather than by silence.
