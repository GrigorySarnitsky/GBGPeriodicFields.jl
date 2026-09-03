# Lane 05-src-ops — findings

Surface: docstrings (public and internal) in `src/Convolution.jl` (1990 lines), `src/Points.jl`
(1478 lines), `src/Interpolation.jl` (1840 lines), `src/Reductions.jl` (1637 lines), and the umbrella
`src/GBGPeriodicFields.jl` (438 lines). `#` comments exempt per lane scope. All five files read in
full, end to end (not sampled).

## Result: no findings survive verification

Every candidate raised during the pass was checked against the implementation, against sibling
docstrings, or against an explicit CLAUDE.md rule, and each one resolved as compliant. None is
reported as a finding. What follows is the enumeration and the checks run, per the "positive
procedure" instruction, so the absence of findings is verifiable rather than asserted.

### Check 1 — CORRECT — formulas, normalizations, adjoints, complexity claims, quantifiers

Checked against the implementing code, line by line, for every display formula in the five files:

- **Convolution.jl**: the circular-sum definition of `convolve!` (`(f⋆g)[n] = Σ_m f[m]g[n-m]`, no
  cell-volume factor) against `_apply_convolution!`/`_apply_compressed_convolution!`; the
  continuum-integral-to-circular-sum bridge (`|Ω|/N` factor); the α/β accumulate form; the
  `spectral_band`/`spectral_cutoff` indicator formula against the `ifelse` in the builder; the
  `assignment_window` tent `W(x)` and its `sinc²(k_aΔx_a/2)` transform against `axis(...)` (verified
  the tent's unit integral by direct triangle-area calculation, and the sinc² form by the
  box-convolved-with-box derivation); the `translation_kernel` phase split (`cos` from the *true*
  wavenumber, `sin` from the *derivative* one) against `axis_phase`, matching invariant 5's Nyquist
  split; the exponential-kernel formulas (`_apply_exponential_convolution!`,
  `_exponential_convolution_modes!`) against decision 79's fiber-hoisted kernel pair — confirmed the
  hoisted form preserves the broadcast's exact association `(c·k²)+(s·ŵ)`,
  `(k_1²+k_2²)+k_3²`, `(αf)·factor` then `+(β·dst)`.
- **Reductions.jl**: `integral`/`mean`'s grid-vs-point-set case split; `inner`'s Parseval weight
  `α(k)` and the `2·total − correction` construction (verified against the rfft half-spectrum
  double-counting argument); the spectral `var` formula `⟨f,f⟩−⟨f⟩² = N⁻²Σ_{k≠0}α(k)|f̂_k|²` — derived
  by hand that subtracting `mean(f)²` from `inner(f,f)` removes exactly the `k=0` term of the Parseval
  sum, confirming the `N⁻²` normalization and the `k≠0` restriction are both correct (this is the
  exact formula CLAUDE.md's history records as having been wrong three times before — now correct);
  `cov`'s `R_ij = ⟨u'_i u'_j⟩` against `_covariance` (`mean(outer_product, u) − ū⊗ū`, Bessel-scaled);
  `weighted_inner`'s formula against `_weighted_step`/the CPU weight-source structs; `radial_spectrum`
  / `radial_correlation`'s shell formulas, the `ties-to-even` claim (verified `round(Int, ...)` is
  Julia's `RoundNearest`, i.e., ties-to-even) against the actual binning kernels; the
  `radial_correlation` normalization — traced through the correlation theorem by hand (the package's
  own convolution theorem, unnormalized-forward, gives `corr(x) = to_physical(conj(f̂)ĝ)` with **no**
  extra `1/N`, so the code's explicit `/ T(number_of_points)` in `_radial_average` is the *one*
  `1/N` the docstring's `C(r) = (1/N)Σf(x)f(x+r)` definition needs — confirmed neither missing nor
  double-counted).
- **Interpolation.jl**: the gather/scatter adjoint identity `M⟨Wf,q⟩_pts = N⟨f,W^Tq⟩_grid` (verified
  the `M`/`N` factors correctly undo the two mean-normalizations); the spline tensor-product gather
  formula against `_interpolate_kernel!`'s `weight_yz * weights_1[i] * field_values[...]` structure;
  `DirectDFT`'s inverse/forward DFT sums against `_direct_dft_interpolate_kernel!` /
  `_direct_dft_anterpolate_kernel!`; the NUFFT width/beta formulas and the deconvolution's Nyquist
  projection against `_nufft_deconvolution`.
- **Points.jl**: `displace!`'s `x_p ← x_p + Σ_j c_j v_j(p)` against `_displacement_rhs`'s recursive
  fold; `wrap!`'s `x_{p,a} ← mod(x_{p,a}−o_a, L_a)+o_a` against `_wrap_coordinate`.

No false, imprecise, or overclaimed statement found. No nontrivial formula lacking a
`docs/FORMALIZATION.md` correspondence was spot-checked further given the volume, but every formula
independently re-derived above matched the code exactly.

### Check 2 — SELF-CONTAINED — symbol and argument-coverage sweep

Enumerated every math symbol, sub/superscript, and operator name across all display formulas in the
five files; every one traced to a binding clause (own-docstring or the package-wide convention stated
in the umbrella module docstring / CLAUDE.md's documentation policy — e.g. `M`/`N` as base counts, `Ω`
as the periodic box, the hat convention for spectral representation). No unbound symbol found.

Ran the argument-coverage sweep from each docstring's *signature* (not the union across overloads)
against its body for every operation in the five files, including the freshest additions (decision 78's
`PointTraversalOrder`/`point_traversal_order`, decision 79's `exponential_convolve!` fiber-hoist doc, decision 73's
`displace!`/`wrap!`). Every positional and keyword argument is documented. Checked in particular:

- The bulleted-vs-prose threshold (CLAUDE.md rubric shape rule 1): confirmed every ≥3-argument or
  any-keyword signature uses the bulleted form (`convolve!`, `spectral_band`, `point_traversal_order`,
  `interpolate!`/`anterpolate!`, `NUFFT`, `displace!`, `weighted_inner`) and every ≤2-positional,
  no-keyword signature uses prose (`radial_kernel`, `spectral_cutoff`, `assignment_window`,
  `translation_kernel`, `wrap!`, `lpnorm`).
- The two explicit single-keyword exemptions the rubric names — `LalescuSpline`'s/`LagrangeSpline`'s
  `T = Float64` and the callable field's `scheme` keyword — are both correctly rendered in prose, not
  bullets, exactly as the exemption specifies.
- Thin allocating wrappers (`interpolate`, `anterpolate`, `convolve`, `exponential_convolve`) document
  no arguments and `@ref`-link their home, per the thin-wrapper exemption.

Terms of art (a "kernel" vs. a "field", "canonical" multipliers, a "visit order", the "resolved band")
are each explained in the owning docstring before or at first use.

### Check 3 — NOTATION — one symbol per concept, one concept per symbol

No synonym pair or symbol collision found across the five files. Checked in particular that
`RadialKernel`'s "canonical" vs. "caller's own" multiplier distinction is introduced once (its own
docstring) and referenced, not re-derived, at `convolve(::RadialKernel, ::RadialKernel)`. No
section/base-flattening matrix notation found in these five files (the `𝟙`/`W_{pn}` class CLAUDE.md
flags as a past defect belongs to `docs/FORMALIZATION.md`, not these docstrings). Fiber-component
notation (`A_{ij}`, `(Au)_i = A_{ij}u_j`) is the sanctioned carve-out and is used consistently with it.

### Check 4 — FORMATTED, BIDIRECTIONALLY

- Ran an automated sweep for a code identifier sitting inside a `` `` ``…`` `` `` math span across all
  five files (regex over every double-backtick span, flagging any `snake_case` token not already
  wrapped in `\texttt{}`/`\mathrm{}`): every hit was a false positive — a LaTeX subscripted variable
  (`k_1`, `x_p`, `\sum_x`, `\min_a`, …), not a Julia identifier. Confirmed by hand-checking a sample
  from each file. No violation.
- Ran a sweep for `\left`/`\right` (only `\leftarrow` hits, a different, permitted command), for
  manual `\;`/`\:` spacing (none), and for `\!` immediately before `\bigl`/`\Bigl` or doubled before
  `\sum`/`\int` (none).
- Checked `\quad`/`\qquad` usage: the only occurrence in these five files is `l2norm`'s
  `Grid3D`/`PointSet` case split (`Reductions.jl:926-931`). Initially flagged this as the banned
  "packing equations behind `\quad`" anti-pattern, then verified against CLAUDE.md's own "these are
  correct — do NOT fix" list, which names exactly this use ("`\quad`/`\qquad` for display-equation
  separation") as sanctioned — and confirmed the identical technique (a formula, then `\qquad` alone
  on its own source line, then the parallel formula) is the established convention elsewhere in the
  package (`DifferentialOperators.jl:801-803`, `:898-901`; `FieldAlgebra.jl:1020-1025`). Not a
  finding — retracted after cross-checking against the explicit exemption and its precedents.
- Every code identifier, type, and module name in running prose is backticked; checked the five module
  names (`Fields`, `Points`, `Interpolation`, `Reductions`, `Convolution`, `FieldAlgebra`,
  `DifferentialOperators`, `FiberSections`, `GBGPeriodicFields`) for bare occurrences outside `#`
  comments and found none (one ambiguous case, `Interpolation.jl:1104`, "Interpolation reproduces the
  band-limited field exactly" inside `DirectDFT`'s docstring, reads as the English noun describing the
  operation in context, not the module name — too ambiguous to report with confidence).
- No indented Markdown table found in these five files (the decision-18/19 hazard CLAUDE.md records
  was in `ARCHITECTURE.md`, not here).
- Checked `docs/ARCHITECTURE.md` §References for verbatim consistency against every inline citation in
  these five files (Hockney & Eastwood 1988, Lalescu/Teaca/Carati 2010, Lalescu et al. 2022 (TurTLE),
  Fornberg 1988, Sundaram & Collins 1996, Brandt & Lubrecht 1990, Barnett/Magland/af Klinteberg 2019):
  every one matches its `§References` entry character-for-character, including the DOI links.

### Check 5 — CURRENT and COMPLETE

- The umbrella `GBGPeriodicFields.jl` module docstring's per-submodule bullet list was checked against
  each submodule's actual export list (`Convolution`, `Points`, `Interpolation`, `Reductions`): every
  exported public binding is named somewhere in the umbrella docstring's description of that module,
  including the newest additions (`point_traversal_order`/`PointTraversalOrder`, `write_scheme`/`read_scheme`,
  `displace!`/`wrap!`, `cov`, the mapped-reduction family). No stale "future/deferred/none-exist"
  claim found in these five files beyond the one accurate, current statement of the `R ≤ 2` ceiling
  (`GBGPeriodicFields.jl:41-52`), which matches the code's actual `throw` behavior above that order and
  is explicitly framed as "deferred, not declined" per the roadmap.
- `Convolution`'s module docstring three-group listing (operations / storage classes / builders) was
  checked against `export convolve, convolve!, ⋆, exponential_convolve, exponential_convolve!,
  spectral_cutoff, spectral_band, assignment_window, translation_kernel, StoredKernel,
  SeparableKernel, RadialKernel, ProductKernel, radial_kernel, translation_kernel!,
  materialize_kernel` (line 118-120): every exported name is present in the docstring. Same check run
  for `Reductions` (`export integral, inner, weighted_inner, l2norm, lpnorm, radial_spectrum,
  radial_correlation`, plus the `Statistics`/`Base` extensions `mean`/`std`/`var`/`cov`/
  `maximum`/`minimum`/`extrema`) and `Interpolation`/`Points` — all current.

### Check 6 — CITED

Covered under item 4 above; every citation in these five files is verbatim-consistent with
`docs/ARCHITECTURE.md` §References, uses context-standard author-year, and carries a clickable DOI on
its title. No inaccessible source (the gitignored monograph, an "appendix", a "Fig. A.1") cited
anywhere in these five files.

## Candidates raised and retracted (recorded for the audit trail, not reported as findings)

1. **Bold vs. plain field-name bullets.** `Convolution.jl`'s `ProductKernel`/`SeparableKernel` "The
   fields are" lists use `**\`name\`**` bold, where every other "The fields are" list in the package
   (`Fields.jl`, `FiberSections.jl`, `Points.jl`) uses plain `` `name` ``. A genuine cross-file
   inconsistency, but not traceable to any explicit CLAUDE.md rule (the shape rubric's field-list rule
   says nothing about bold vs. plain), so not reported per the "do not report style preferences you
   cannot tie to a rule" instruction.
2. **`\quad`/`\qquad` in `l2norm`.** See item 4 above — raised, then retracted after finding the
   identical technique sanctioned elsewhere and explicitly whitelisted in CLAUDE.md.
3. **Bare source-line wraps inside `` ```math ``` `` blocks with no `aligned`/`gathered` and no literal
   `\\` line break** (e.g. `exponential_convolve!`'s single-operand formula,
   `Convolution.jl:1565-1566`; the tensor-product gather formula, `Interpolation.jl:133-135`;
   `assignment_window`'s `W(x)`, `Convolution.jl:1809-1810`). A bare newline inside a `` ```math ``` ``
   block is whitespace to KaTeX, not a line break, so these render as one continuous line regardless of
   the source wrap. Considered reporting under rule 4's "no horizontal scroll" / "hand-wrap … with
   `aligned`/`gathered`" clause, but could not confirm the *rendered* width actually overflows without
   building the docs site (which this lane's brief does not authorize), and each candidate, read as one
   continuous line, is not obviously wider than formulas elsewhere in the corpus that render without
   incident. Not reported for lack of a build-verified rendering; flagged here only as a location worth
   a render-and-check pass if the docs build is available to a later reviewer.

## Enumerated but not exhaustively re-derived

Given the volume (5 files, ~7400 lines, dozens of display formulas), the internal helper functions'
docstrings (Fornberg weight construction, the Hermite/Lagrange weight-matrix builders in
`Interpolation.jl`, the CPU/GPU dispatch-route comments throughout `Convolution.jl`) were read for
self-consistency and cross-checked against their callers, but their numerical derivations (e.g. the
Fornberg finite-difference recursion) were not independently re-derived from first principles — these
are internal (`_`-prefixed) and exempt from the strict argument-bulleting rule, and their formulas
already carry `Reference:` citations to the implementing literature (Fornberg 1988) rather than
standing as the package's own novel claims.
