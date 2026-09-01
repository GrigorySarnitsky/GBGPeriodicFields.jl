# Lane 02 — FORMALIZATION.md + TESTING.md

## Enumeration performed

Read both files in full (819 + 658 lines). For check 1 (the priority for this lane), enumerated
every typed statement/formula in `FORMALIZATION.md` section by section and verified each against
`src/` by reading the deciding line(s), and confirmed each carries a "Checked by" test-file
citation. Verified the cited test files exist and, for a sample spanning every section, that the
named testset/assertion actually implements the claim (not just that the file exists).

Formulas/claims independently re-derived or checked against source (not exhaustive list, but every
section of FORMALIZATION.md got at least one point-check):

- `_spectral_constant_scale = prod(grid_size)` — `src/Fields.jl:1615`. Matches.
- `reality_residual` definition and its "reports, never repairs" claim — `src/Fields.jl:2408-2467`.
  Structure matches (max over self-conjugate planes).
- Nyquist split for `∇`/`Δ`/`ℙ` (derivative vs squared wavenumber families) — cross-checked against
  `FieldSpectralMultipliers` and `helmholtz_projection!`'s `iszero(squared)` branch,
  `src/DifferentialOperators.jl:213,272,593,643`. Matches.
- `inverse_curl!` formula `û = i·a×ŵ / |a|²`, zero-mode convention — `src/DifferentialOperators.jl:1174-1201`
  (docstring formula and implementation both). Matches FORMALIZATION.md's Statement.
- `translation_kernel` separable factor `cos(k_a h_a) - i sin(k̃_a h_a)` — `src/Convolution.jl:1888,1912-1950`.
  Matches, including the Nyquist real-cosine claim.
- `assignment_window` = `∏ sinc²(k_a Δx_a / 2)` — `src/Convolution.jl:1808-1838`. Matches.
- `var`/`std`/`cov` Bessel-correction formulas and `corrected` keyword semantics —
  `src/Reductions.jl:361-375,543-698,730-735`. Matches (default `corrected = true`, population form
  at `corrected = false`, `cov` symmetric tensor with the same `N_B/(N_B-1)` factor).
- `radial_spectrum`/`radial_correlation` shell formula `round(Int, sqrt(squared)/fundamental)`,
  `α(k)` weight, `conj(f̂)·ĝ` cross form — `src/Reductions.jl:1239-1543`. Matches, including the
  ties-to-even rounding convention FORMALIZATION.md documents only implicitly (TESTING.md doesn't
  restate it, which is fine — the tie-break issue is a known harness gap already tracked in
  CLAUDE.md, not a doc defect in these two files).
- Interpolation partition-of-unity / adjoint claims — `src/Interpolation.jl:27-32,968`. Matches.
- `_wrap_coordinate` — `src/Points.jl:1217-1221` reproduces FORMALIZATION.md's Statement 2 (`mod`,
  then fold exactly-`extent` to zero, then restore origin) verbatim, including the
  `mod(-1e-20, 2π) === 2π` example.
- `FieldSpectralMultipliers`'s `Canonical` type parameter and its role in kernel-composition
  dispatch — `src/Fields.jl:1730-1793,2334-2366`, `src/Convolution.jl:403-415`. Matches the
  "canonical vs custom" dispatch condition described in the Convolution section.
- `helmholtz_projection!`'s `id` fallback at `a·a = 0` — `src/DifferentialOperators.jl` (`iszero`
  branches). Matches.
- `test/adjointness.jl:84-150` — confirmed it implements every identity FORMALIZATION.md cites
  (divergence = −gradient adjoint, self-adjoint curl, self-adjoint negative-semidefinite Laplacian
  with the dissipation pairing, idempotent self-adjoint Helmholtz projection), at both the
  band-limited and full-spectrum-Nyquist lanes, matching the "unconditional except dissipation"
  scoping FORMALIZATION.md states.
- `test/transfer_spectral.jl:80-156,265-345` — confirmed the `M·⟨Wf̂,q⟩ = N·⟨f̂,Wᵀq⟩` measure-weighted
  adjoint is literally what's asserted (`prod(grid_size) * inner(...)` vs `npoints * inner(...)`),
  matching FORMALIZATION.md's Interpolation section.
- `test/hdf5.jl:286-371` — counted 9 schemes round-tripped by `===` and exactly 8
  `@test_throws ArgumentError read_scheme` malformed-group refusals, matching TESTING.md's "nine
  schemes … eight malformed-group refusals" (§2).
- `test/fields.jl:191,225-246` — confirmed the four grids `(8,8,8)`, `(8,7,6)`, `(7,5,3)`, `(9,9,9)`
  and the `_component_offsets_align` predicate test cited by TESTING.md's coverage axis 18 are
  exactly what's in the file.
- `test/metadata_sweep.jl` — recounted the generated sweep: 30 cases × 4 assertions × (2 element
  types × 4 folds) = 960, plus the independent-argument-slots sub-testset (3 pairs × 2 assertions +
  1 refusal = 7) × 8 = 56; total 1016, matching TESTING.md's "1016 assertions" claim exactly.

No FORMALIZATION.md statement was found lacking a "Checked by" test citation, and every citation
resolves to an existing file. No nontrivial claim was found with no formal entry at all (the two
files are tightly coupled — every §2 TESTING.md module bullet has a matching FORMALIZATION.md
section, and vice versa).

## Findings

### Finding 1
- check: 4 (formatted, bidirectionally — silent rendering rule (a): a code identifier only belongs
  inside a math span when it must appear *inside* a formula; a bare identifier with no surrounding
  math content should be plain-backticked in prose instead)
- location: `docs/FORMALIZATION.md:748`
- quote: `because — because ``\texttt{Grid3D}`` stores the domain size, spacing and origin at the`
- why: `Grid3D` here names no formula — it is a plain prose reference to the type ("because Grid3D
  stores the domain size…"), not a symbol appearing inside an equation. The style rule's own wording
  ("a code name that **must appear inside a formula** is wrapped `\texttt{}`") implies the converse:
  a code name that does *not* need to be inside a formula belongs in an ordinary backtick span, not
  wrapped in a math span at all. Using `` ``\texttt{Grid3D}`` `` here is the same class of misuse as
  wrapping a stray word in math mode for no mathematical reason — it renders correctly (KaTeX prints
  `Grid3D` in typewriter font) but is not the intended use of the `\texttt{}` escape hatch, which
  exists specifically for a name embedded among real math operators.
- fix: replace `` ``\texttt{Grid3D}`` `` with plain `` `Grid3D` `` (ordinary backtick code span, no
  math delimiters).
- confidence: low (this is a style/consistency nit, not a rendering break — flagging because the
  rulebook explicitly scopes `\texttt{}` to the in-formula case)

### Finding 2
- check: 4 (same rule as Finding 1)
- location: `docs/TESTING.md:585`
- quote: `the extensive/intensive relation between ``\texttt{integral}`` and ``\texttt{mean}`` — the one is the other times the base measure —`
- why: as in Finding 1, `\texttt{integral}` and `\texttt{mean}` here are bare identifiers with no
  math operators around them inside their own spans — they are just named twice in a row inside math
  delimiters for no formula-internal reason (the actual relation, `integral = measure · mean`, is
  already given as a real display formula earlier in `FORMALIZATION.md:473`). Contrast with the
  correct usages at the same file's lines 586, 600, 604, 627, 647, where `\texttt{...}` sits inside
  an actual equation (`=`, `·`, etc.) and the wrapping is load-bearing.
- fix: replace both with plain backtick code spans: `` `integral` `` and `` `mean` ``.
- confidence: low (same style nit as Finding 1, not a rendering break)

## Verified clean

- All formulas and normalization constants enumerated in `FORMALIZATION.md` (transform convention,
  Parseval weighting, Nyquist splits, the projector/inverse-curl/curl-adjoint identities, the
  translation-kernel Hermitian/whole-cell claims, the exponential-kernel reality/semigroup claims,
  the kernel-storage-class interchangeability and composition-closure claims, `var`/`std`/`cov`
  formulas, the mapped-reduction identities, the Parseval `inner` decomposition, `weighted_inner`'s
  tuple-fusion identity, the interpolation adjoint/conservation derivations, the `DirectDFT`/`NUFFT`
  formulas, the storage-family `adapt` commutation/idempotence statements, and the four base-space
  motion statements) were checked against the implementing code and found correct as stated, with no
  false, imprecise, or overclaimed quantifier found.
- Every FORMALIZATION.md section carries a "Backs" + "Checked by" pair naming an existing test file;
  spot-checked test files (`adjointness.jl`, `transfer_spectral.jl`, `hdf5.jl`, `fields.jl`,
  `metadata_sweep.jl`) were read and confirmed to implement the cited claims, including exact counts
  (9 schemes / 8 refusals, the four component-offset grids, the 1016-assertion metadata sweep).
- No nontrivial claim in either file was found with a missing FORMALIZATION.md entry or a
  FORMALIZATION.md entry with no linked test.
- No math-in-backticks, no bare (unbacktricked) module/type/function names outside of legitimate
  plain-English uses of an operator's mathematical name (`gradient`, `divergence`, `curl` used as
  ordinary nouns per CLAUDE.md's own "operators are not spectral" convention — these are correctly
  unbacktricked when naming the mathematical operator rather than the Julia binding).
- No `\left`/`\right`, no manual `\;`/`\!` spacing, no `\mathbb{1}` misuse, no un-braced fraction
  arguments found in either file.
- No stale/future/deferred claims found in either file that contradict the current code state (both
  files read as current with the rest of the package's 2026-08-3x state).
- Citations: no in-text citations appear in either FORMALIZATION.md or TESTING.md requiring
  author-year verification (only the Hockney & Eastwood reference lives in `src/Convolution.jl`,
  out of this lane's two surfaces).
