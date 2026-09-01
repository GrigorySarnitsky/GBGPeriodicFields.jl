# Lane 07 — examples (`examples/HIST_CPU.jl`, `examples/gpu/rocm/HIST_ROCm.jl`)

## Scope and method

Read both files in full (534 + 487 lines). Both are Literate pages: every full-line `# ` comment
(and `#md #` for `HIST_CPU.jl`'s appended Results section) renders as Markdown prose; `##`-prefixed
and inline-after-code `#` comments stay as code comments and are exempt.

Positive procedures run:

- Enumerated every `` ``…`` `` math span and every `` `…` `` code span; checked each formula against
  `src/Reductions.jl`, `src/DifferentialOperators.jl`, `src/Convolution.jl` and standard turbulence
  identities (K41 second-order structure functions, Taylor microscale, Kolmogorov scales, the
  longitudinal/trace integral-length relation `L = (2/3)L_11`, homogeneous dissipation
  `ε = ν⟨|ω|²⟩`, Parseval/`radial_spectrum` energy-sum identity).
- Grepped for bare Unicode math glyphs outside `` ``…`` `` spans (none found outside fenced `sh`
  blocks, which are exempt).
- Grepped for backtick-wrapped formulas (none — every single-backtick span is a real Julia
  identifier).
- Checked every `` ``…`` `` span for balanced open/close per source line (found one violation, #1
  below).
- Checked every bare capitalized/CamelCase word against backtick coverage (found one violation, #2
  below).
- Cross-checked all numeric claims shared between the two files (`Re_λ`, `κ_max·η`, `ν`, peak/±GB
  figures for `--mega`/`--giant`) for consistency — all matched.
- Checked `\left`/`\right`, `\mathbb{}`, `\;`/`\:`/`\!` spacing, `\mathrm{d}` differential usage —
  all compliant (the one `\sim\!` at `HIST_CPU.jl:318` is the CLAUDE.md-sanctioned exception).
- Checked the K41 spectrum guide (`E(κ) = C_K ε^{2/3} κ^{-5/3}`) for the required dimensional
  constant per the CLAUDE.md demo standard — present and explicitly justified (`HIST_CPU.jl:513-517`).
- Checked for citations — none present; K41/Kolmogorov/Taylor are used only as eponymous,
  uncited classical terms, which the citation policy exempts. No reference to `inspiration/`, an
  "accompanying thesis", or any other inaccessible material.
- Verified `src/*.jl` has no `rand`/`Random` usage, confirming the "package ships no random-field
  generator" claim (`HIST_CPU.jl:277`).

## Finding 1

- **Check:** 4 (Formatted, bidirectionally — silent rendering failures)
- **Location:** `examples/HIST_CPU.jl:168-170`
- **Quote:**
  ```
  168:# The spectrum is half the shell-resolved Parseval inner, ``E(\kappa) = \tfrac{1}{2} P(\kappa)``, so
  169:# that its shells sum to the kinetic energy: ``\sum_\kappa E(\kappa) =
  170:# \tfrac{1}{2}\langle\lvert u\rvert^{2}\rangle = k``, the kinetic energy.
  ```
- **Rule violated:** CLAUDE.md §Style, silent-rendering-failure micro-rule (c): "Inline math stays
  on ONE source line... `docs/make.jl`'s `lint_inline_math()` fails the build on it... so even a
  docstring-only change must pass it." The inline `` ``…`` `` span opens on line 169
  (`` ``\sum_\kappa E(\kappa) =``) and only closes on line 170. This exact rule is why the
  CLAUDE.md "Literate example IS a rendered doc page" section exists: "the battery above (and
  `/check-docs`) must build and grep `examples/*.jl` too, not only `ARCHITECTURE.md` / `src/`."
- **Why it matters here specifically:** `docs/make.jl`'s `lint_inline_math()` is **not** a guard
  against this instance — verified by reading `_doc_lint_sources()` (`docs/make.jl:38-51`), which
  collects only `src/*.jl` and the four rationale `.md` docs plus `docs/src/**/*.md`; it never lists
  anything under `examples/`. So this is exactly the gap the "Literate pages must be swept like a
  doc page" rule anticipates: a defect class the build lint catches everywhere else, uncaught here.
  Mitigating factor (why this reads MEDIUM rather than a certain breakage): CommonMark's own inline
  code-span rule converts an embedded line ending to a space as long as the span isn't broken by a
  block-level construct, and line 170's continuation does not begin with a list/blockquote leader
  (the specific breakage mechanism CLAUDE.md documents) — so this particular instance likely renders
  correctly today. It should still be fixed to the letter of the rule, both because the guard cannot
  currently verify that and because the next edit to this passage could easily reflow it onto a line
  that *does* start with a stray `-`/`*`/digit, silently breaking it with no build failure to catch
  it.
- **Fix:** Put the whole span on one source line (break the prose around it, not the span), matching
  the corresponding passage in `examples/gpu/rocm/HIST_ROCm.jl:194-195`, which already states the
  identical formula on one line:
  ```julia
  # The spectrum is half the shell-resolved Parseval inner, ``E(\kappa) = \tfrac{1}{2} P(\kappa)``,
  # so the shell sum recovers the turbulent kinetic energy: ``\sum_\kappa E(\kappa) =
  # \tfrac{1}{2}\langle\lvert u\rvert^{2}\rangle = k``.
  ```
  rewrapped so the `` ``…`` `` delimiters both land on the same physical line.
- **Confidence:** medium (real rule violation and a real gap in lint coverage; uncertain whether it
  currently mis-renders, given CommonMark's line-joining behaviour and the absence of a list leader).

## Finding 2

- **Check:** 4 (Formatted, bidirectionally — every code identifier and module name backticked)
- **Location:** `examples/gpu/rocm/HIST_ROCm.jl:11-13`
- **Quote:**
  ```
  11:# Like its CPU sibling this is a DEMONSTRATION, not the production solver: the full pseudospectral
  12:# DNS built on this package is GBGIsotropicTurbulence.jl, documented at
  13:# https://grigorysarnitsky.github.io/GBGIsotropicTurbulence.jl .
  ```
- **Rule violated:** CLAUDE.md §Style silent-rendering-failure rubric / check item 4: "every code
  identifier ... **module names** ... is **always** backticked and **never** bare ... check *both*
  directions." `GBGIsotropicTurbulence.jl` names a real Julia package/module and appears here as
  bare prose text, with no backticks and no markdown link.
- **Cross-check confirming this is drift, not house style:** the CPU sibling states the identical
  fact correctly, `examples/HIST_CPU.jl:11-12`:
  ```
  11:# **This is a demonstration, not the production solver.** The full pseudospectral DNS built on this
  12:# package is [`GBGIsotropicTurbulence.jl`](https://grigorysarnitsky.github.io/GBGIsotropicTurbulence.jl) — that is where the
  ```
  — backticked and wrapped as a markdown link. The GPU file's version dropped both the backticks and
  the link, giving the exact same fact a lesser, non-conforming rendering.
- **Fix:** match the CPU sibling's form:
  ```julia
  # Like its CPU sibling this is a DEMONSTRATION, not the production solver: the full pseudospectral
  # DNS built on this package is [`GBGIsotropicTurbulence.jl`](https://grigorysarnitsky.github.io/GBGIsotropicTurbulence.jl).
  ```
- **Confidence:** high.

## Finding 3

- **Check:** 3 (Notation — one symbol per concept, one concept per symbol)
- **Location:** both files; representative instances:
  - `examples/HIST_CPU.jl:91` — `` "...the box size ``L``..." ``
  - `examples/HIST_CPU.jl:262` — `` "Positions wrap into ``[0, L)``" ``
  - `examples/HIST_CPU.jl:408` — `` "``L = \int_0^\infty \rho(r)\,\mathrm{d}r``, which is ``\tfrac{2}{3}L_{11}`` of the longitudinal scale" ``
  - `examples/HIST_CPU.jl:502-503` (`#md` Results section) — `` "the trace-correlation integral length ``L = \int_0^\infty \rho(r)\,\mathrm{d}r`` (``= \tfrac{2}{3}L_{11}``)" ``
  - `examples/gpu/rocm/HIST_ROCm.jl:67,88,291` (box size) vs. `:399,431` (integral length), same pattern.
- **Rule violated:** CLAUDE.md §Style: "One notation per concept and one concept per symbol...
  When you introduce a symbol, grep the section for the glyph and confirm it is free... a single
  glyph must not carry two meanings." Here the bare math symbol `` ``L`` `` denotes two distinct
  physical quantities within the same rendered page: the periodic-domain **box size** (`Params.L`,
  the simulation domain edge length, used e.g. in `[0, L)` position wrapping and in the
  scale-separation statement `λ ≪ L`) and the **trace-correlation integral length**
  (`∫₀^∞ ρ(r) dr`, a turbulence statistic derived from `radial_correlation`, `= (2/3)L₁₁`). These
  are two different lengths that appear together in the same physics narrative (a reader checking
  scale separation compares the integral length against the box size), so the shared bare symbol is
  exactly the collision the rule targets.
- **Evidence the two are genuinely distinct quantities, not a restatement:** the code itself already
  disambiguates them by name — `p.L` (box size, a `Params` field, `Float64`) vs. `L_int` (integral
  length, computed by `integral_scale(sep, C)` at `HIST_CPU.jl:414`) — so the collision exists only
  in the rendered math prose, not in the implementation.
- **Fix:** give the integral length its own symbol distinct from the box size — e.g. `` \mathcal{L} ``
  or `` L_{11} ``'s own prefactor form `` \tfrac{2}{3}L_{11} `` used standalone (drop the bare `` L ``
  restatement and keep only the `` L_{11} ``-based form, which is already present alongside it at
  both sites) — applied consistently across both files (`HIST_CPU.jl:408,502-503`;
  `HIST_ROCm.jl:399,431`) and in the `L_int` HDF5-bundle comment.
- **Confidence:** medium (each individual occurrence is locally disambiguated by adjacent prose —
  "the box size `L`" vs. "the integral length `L`" — so a careful reader is not actually misled;
  the finding is that the bare symbol is reused across the same document for two different
  quantities, which the notation rule flags regardless of local disambiguation).

## Verified clean (enumerated, no defect found)

- **Correctness (check 1):** the rotational-form Navier-Stokes RHS (`HIST_CPU.jl:24-27`,
  `HIST_ROCm.jl` equivalent in `step!`'s docstring) matches the code's `curl!`/`cross!`/
  `helmholtz_projection!`/`exponential_convolve!` composition exactly. The integrating-factor RK2
  (Heun) display-math block (`HIST_CPU.jl:233-240`, `HIST_ROCm.jl:262-269`) matches `step!` line by
  line. `kinetic_energy = ½inner(u,u)`, `dissipation = ν·inner(ω,ω)`, `max_speed` (√3 bound
  verified by direct computation), `energy_spectrum = ½·radial_spectrum`, the divergence-relative
  check, `η = (ν³/ε)^{1/4}`, `τ_η = √(ν/ε)`, `λ = u'√(15ν/ε)`, `Re_λ = √(15u'⁴/(νε))` are all
  standard and correctly stated. The K41 second-order structure-function prefactor `11/9·C₂` was
  independently re-derived from `D_LL`/`D_NN` isotropy relations and matches exactly. The
  `L = (2/3)L₁₁` integral-length identity was independently re-derived from the isotropic
  correlation-tensor continuity relation `g = f + (r/2)f'` and matches exactly. `S^{(E)}(r) =
  (2/3)(C(0)-C(r))` and its Lagrangian twin were re-derived from the homogeneous expansion of
  `⟨|δu|²⟩` and match exactly. `lpnorm(u, Inf)` materializing a magnitude field
  (`HIST_CPU.jl:156,162-165`) was confirmed against `src/Reductions.jl:1621`. "The package ships no
  random-field generator" (`HIST_CPU.jl:277`) was confirmed by grepping `src/*.jl` for `rand`/
  `Random` (no hits).
- **Self-contained (check 2):** every symbol in the "Method" preamble (`\hat{\cdot}`, `u`, `ω`,
  `\mathbf{k}`, `κ`, `ν`, `ℙ`) is bound before use; the deliberate bold-`\mathbf{k}`/italic-`k`
  (wavenumber vector vs. turbulent kinetic energy) split is explicitly declared and consistently
  followed in both files (checked every bare `k` occurrence in math spans).
- **Formatted (check 4), other than findings 1-2:** no backtick-wrapped formulas found; no bare
  Unicode math glyphs outside fenced shell blocks (which are exempt, rendering as literal code); no
  `\left`/`\right`; no `\mathbb{}` on a non-`A`-`Z`/`k` glyph (`\mathbb{P}` is the only use, on a
  valid capital); no manual `\;`/`\:` spacing around relations; `\mathrm{d}r`/`\mathrm{d}\tau`
  correctly upright with a sanctioned thin space; `\sim\!` at `HIST_CPU.jl:318` is the documented
  exception, not a defect. No underscored identifier sits bare in prose outside backticks (checked
  every `[a-z]+_[a-z]+` token). Tables: none present. Display-math blocks all use `aligned`/`bigl`/
  `bigr`, never `\left`/`\right` or unwrapped `\quad`-packed single lines.
- **Current and complete (check 5):** no stale "future/deferred/none-exist" language found. The
  `smoke()`/`fast()`/`huge()`/`mega()`/`giant()` parameter-set claims (grid sizes, `Re_λ`, `κ_max·η`
  figures) cross-check consistently between `HIST_CPU.jl` and `HIST_ROCm.jl` everywhere both state
  the same fact (`Re_λ≈93/109/130`, the `320³`/`≈96 ms/step`/`≈13 GB` peak/`384³` at `≈21 GB` GPU
  figures, the "12 GB card was mega's ceiling, 24 GB unlocks giant" history). The 24 GB RX 7900 XTX
  and its historical 12 GB RX 6700 XT predecessor match the fleet's recorded GPU history.
- **Cited (check 6):** no citations present; K41/Kolmogorov/Taylor used only as uncited eponymous
  terms per policy. No reference anywhere to `inspiration/`, an "accompanying thesis", or any other
  inaccessible material.
- **Demo standards (CLAUDE.md demo & figure standards):** the plotted K41 spectrum guide
  `E(κ) = C_K ε^{2/3} κ^{-5/3}` explicitly carries its constant and states why the bare `κ^{-5/3}`
  slope would be dimensionally wrong (`HIST_CPU.jl:513-517`) — compliant.
