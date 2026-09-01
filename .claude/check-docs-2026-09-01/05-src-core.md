# check-docs lane 04-src-core

Surface: docstrings (public and internal) in `src/FiberSections.jl`, `src/Fields.jl`,
`src/FieldAlgebra.jl`, `src/DifferentialOperators.jl`. `#` comments exempt (not rendered).

## Method

Read all four files in full. For each docstring: (1) verified every formula, normalization
constant, adjoint/conservation relation and quantifier against the implementing code (quoting
the decisive line); (2) enumerated every math symbol and cross-checked it is bound in prose
(a scripted sweep extracted every symbol appearing inside a display ```` ```math ```` block and
checked whether it also appears — bound — somewhere in the surrounding prose of the SAME
docstring, index letters `i,j,k,n,x,y,z` and `T,N,R,L,O,d,e` exempted as standard); (3) grepped
for module names outside backticks, code identifiers inside math spans, formulas in single
backticks, `\left`/`\right`, manual spacing (`\;`/`\:` next to a relation), `\mathbb{}` on a
non-`A`–`Z`/`k` glyph, and conjugate-notation consistency; (4) checked struct "The fields are"
bullets against the actual struct fields; (5) checked module docstrings' operation-family lists
against current exports/method tables.

## Finding 1

- Check: 2 (self-contained — argument coverage)
- Location: `src/FieldAlgebra.jl:1339-1355` (the `transpose!` docstring)
- Quote: `"Transpose the fiber indices of a second-order tensor field in place (`transpose` ``\equiv (\cdot)^\top``), and return `destination`."` … `"Pointwise over the base: ```math \texttt{destination}_{ij} = A_{ji}. ```"`
- Rule: CLAUDE.md's argument-coverage sweep — "an argument that surfaces only inside a formula
  reads as 'bound by use' and slips through" (the docstring-rubric §"Argument coverage
  (signature-driven)" and the doc-edit-checklist §self-contained). `transpose!` has two
  arguments, `destination` and `A`; below the 3-argument threshold the rubric requires each to be
  "bound in running prose". `destination` is bound (via "and return `destination`" / the in-place
  steer sentence), but `A` never appears anywhere in the body prose — only in the top signature's
  type annotation and inside the display formula `A_{ji}`. Every sibling decomposition in the
  same file explicitly names its input tensor argument in the first sentence — `sym!`/`skew!`/
  `dev!` all read "the second-order tensor field `A`", `tr!` reads "the second-order tensor field
  `A`", `det!` uses `A` in running prose ("the signed factor by which ``A`` scales volumes") — so
  `transpose!` is the one outlier in its own family, confirming this is a gap rather than a
  house-style choice.
- Fix: add a clause naming `A`, e.g. "Transpose the fiber indices of the second-order tensor
  field ``A`` in place, writing the result into `destination`, which is returned."
- Confidence: high

## Finding 2

- Check: 2 (self-contained — argument coverage)
- Location: `src/DifferentialOperators.jl:1306-1320` (the `laplacian!` docstring)
- Quote: `"The Laplacian is a local operator: it sums the second partial derivatives of a scalar field ``f`` over the three axes, and it acts on each component of a vector or tensor field alike, so it preserves the tensor order: ```math \Delta f = \partial^2_{x_i x_i} f, \qquad (\Delta u)_j = \partial^2_{x_i x_i} u_j. ```"`
- Rule: same argument-coverage rule as Finding 1. The scalar case's symbol `f` is bound ("a
  scalar field ``f``"), but the vector/tensor case's symbol `u` in `(\Delta u)_j` is never
  introduced — the surrounding prose only says "a vector or tensor field", never naming it `u`.
  A systematic sweep of every display-math symbol in this file against its own docstring's prose
  found this as the one other unbound-argument instance beyond the index letters (`i`, `j`,
  which are exempt as standard summation indices) — every sibling differential operator in the
  same file (`gradient!`, `divergence!`, `curl!`, `symmetric_gradient!`, `helmholtz_projection!`,
  `inverse_curl!`) explicitly names its field argument (`\varphi`, `u`, `A`, `w`) in prose
  immediately before its formula, so `laplacian!` is again the outlier in its own family.
- Fix: add the name to the sentence, e.g. "...and it acts on each component of a vector or
  tensor field ``u`` alike, so it preserves the tensor order" (or introduce `u` in a second
  clause covering the vector/tensor case).
- Confidence: high

## Verified clean (enumerated and checked, no defect found)

- **Formulas verified against code, all correct**: `_det_tensor_rhs`'s cofactor expansion
  (`FiberSections.jl:687-713`) against the standard first-row Laplace expansion; `_cross_formula`
  (`FiberSections.jl:592-605`) against `(u×v)_i = ε_ijk u_j v_k`; `_tensor_vector_formula`/
  `_vector_tensor_formula`/`_tensor_tensor_formula` against standard matrix-vector/matrix-matrix
  contraction; `_norm_vector_rhs`/`_norm_tensor_rhs` against Euclidean/Frobenius norms;
  `_axis_wavenumber_values` (`Fields.jl:1850-1870`) against the `fftfreq`/`rfftfreq` convention
  including the even-axis Nyquist placement (`-N/2`) and the Nyquist-zeroing index; the forward
  transform "unnormalized" / inverse "carries `1/N`" claim (`Fields.jl:1528-1531`) against
  invariant 4 and `_spectral_constant_scale = prod(grid_size)`; `reality_residual`'s reversal +
  circshift-by-one derivation (`Fields.jl:2408-2419`) algebraically re-derived and confirmed
  equal to the stated `mod(-(j-1), n) + 1` partner index, and its displayed formula
  `max|f̂(k) - conj(f̂(-k))|` confirmed equivalent to the stated reality condition
  `f̂(-k) = conj(f̂(k))`; every `DifferentialOperators.jl` spectral symbol — `gradient!` (`i k`),
  `divergence!` (`i(k₁ŝ₁+k₂ŝ₂+k₃ŝ₃)`), `curl!` (`i(k×û)`, all three components independently
  re-derived), `symmetric_gradient!` (`(i/2)(k_jû_i+k_iû_j)`, including the diagonal collapse),
  `laplacian!`/`inverse_laplacian!` (`-|k|²`, zero-mean convention), `helmholtz_projection!`
  (`id - aaᵀ/(a·a)`), `inverse_curl!` (`i a×ŵ/|a|²`, cross-checked against the vector identity
  `∇×(∇×u) = ∇(∇·u) - Δu`) — all checked line-by-line against their kernel code and found exact.
- **Struct field-doc consistency**: `Grid3D`, `RealFourierLayout`, `ScalarFieldPhysical`,
  `VectorFieldPhysical`, `TensorFieldPhysical`, their Spectral counterparts, `FieldTransformPlans`
  and `FieldSpectralMultipliers` — each "The fields are" bullet list checked one-for-one against
  the actual `struct` field list; all match (type parameters such as `Canonical` correctly
  excluded, since they are not accessor-visible fields).
- **Formatting, bidirectional**: no code identifier found inside a math span (checked every
  `` ``…`` `` span in all four files); no ASCII-math wrapped in single backticks (every
  single-backtick span containing `=`/`+`/`^`/`*` is genuine Julia syntax matching the adjacent
  source, e.g. `` `R = N - 3` `` mirrors `TensorFieldPhysical{N - 3}(...)`); every `[`Module`](@ref
  "Module")` occurrence of a bare module name is legitimate Documenter link syntax, not
  unbacktick prose; no `\left`/`\right` outside `\leftarrow` (a distinct command); no manual
  `\;`/`\:` spacing around a relation/operator; no `\mathbb{}` on a non-`A`–`Z`/`k` glyph; no
  markdown table indented in a list; conjugate notation (`\overline{}`) used exactly once, in
  `reality_residual`, with no competing notation for the same concept elsewhere in these files.
- **Module docstrings current/complete**: `FieldAlgebra`'s operation-family list matches its
  `export` list plus the `import Base: map, map!` extension; `DifferentialOperators`'s bulleted
  operator list (`gradient`, `divergence`, `curl`, `symmetric_gradient`, `laplacian`,
  `inverse_laplacian`, `helmholtz_projection`) matches its `export` list (`inverse_curl` is
  covered by its own full docstring though not in the module's bulleted summary — a possible
  completeness gap, but low-confidence given `inverse_curl`'s recency (decision 77) and that
  module summaries elsewhere in the corpus are periodically audited for exactly this; not
  reported as a finding since I could not confirm this against the family list's intended scope
  versus a deliberate omission).
- **`combine!`'s two-exception status** cross-checked against invariant 10's text (the α/β glyph
  rule) and against `exponential_convolve!`'s cited two-operand form — consistent.
- **Argument-coverage bulleted-form threshold** spot-checked on `gradient!`, `divergence!`,
  `curl!`, `symmetric_gradient!`, `laplacian!`, `inverse_laplacian!`, `helmholtz_projection!`,
  `inverse_curl!`, `combine!`, `multiply!`, `divide!`, `dot!`, `cross!`, `mul!`,
  `FieldTransformPlans`, `to_physical!` (4-arg form) — every one at or above the 3-argument/
  keyword threshold uses the bulleted "The arguments are:" form; every one below it (`transpose!`,
  `tr!`, `det!`, `sym!`/`skew!`/`dev!`, `norm!`) uses prose, correctly.

## Enumeration summary

- FiberSections.jl: ~55 docstrings read (module + public API + internal codegen builders +
  the fused executor + the `map!` adapter helpers). All internal (`_`-prefixed) helpers correctly
  exempted from the argument-bulleting threshold.
- Fields.jl: ~90 docstrings read (module + `Grid3D`/`RealFourierLayout`/field types +
  `FieldTransformPlans`/`to_physical!`/`to_spectral!` + `FieldSpectralMultipliers` +
  `SpectralKernel` protocol + `adapt`/`adapt!` + `reality_residual` + persistence stubs).
- FieldAlgebra.jl: ~45 docstrings read (module + the full M2/M3 public surface + `map!`/`map`).
- DifferentialOperators.jl: ~30 docstrings read (module + all seven operator families, both
  arities, kernel-composed forms).

Findings count: 2 (both check 2, self-contained argument coverage; both high confidence).
