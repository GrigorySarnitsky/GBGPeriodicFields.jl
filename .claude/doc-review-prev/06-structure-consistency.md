# Documentation-Structure Consistency Review

**Hat:** structure-consistency (fresh-eyes, template-uniformity audit)

## Inferred template

**Function docstring** (in-place `f!`/`f` pairs, the dominant shape across `FieldAlgebra`,
`DifferentialOperators`, `Convolution`, `Interpolation`, `Reductions`):
1. Signature block(s).
2. One-sentence identity ("Compute X ... and return `destination`.").
3. Verbatim steer sentence: *"Use this in-place form when `destination` is already allocated; the
   allocating `X` returns a fresh result instead."*
4. `The arguments are:` bulleted list (triggered at 3+ signature args or any keyword; ≤2 args stay
   in prose, no bullets) — bullets always use an em dash (`` `name` — description ``).
5. Validity/representation prose (physical-only / spectral-only / both).
6. Display-math formula.
7. Optional titled `!!!`-style admonition.
8. `source`.

The **allocating wrapper** overwhelmingly opens *"Allocating form of `X!`: allocate the result and
return it. ... See `X!` for ..."* — a thin, formula-free pointer to the `!` home.

**Type docstring**: identity paragraph, then constructor signature(s) folded into one block, then
`The fields are` with a bulleted list of stored fields.

Against that inferred template, the following are the sharpest outliers.

---

### Finding 1 — Four core allocating operators break the "Allocating form of `X!`" template
- **Type:** organization — **Severity:** major — **Confidence:** high
- **Locations:**
  - FieldAlgebra, `Base.:+`: *"Allocating sectionwise addition: add fields or point-value collections — or a section and a compatible constant — and return a new section; the in-place home is `add!`."*
  - FieldAlgebra, `Base.:-`, `Base.:*`, `Base.:/` open identically: *"Allocating sectionwise subtraction..."*, *"Allocating multiplication..."*, *"Allocating division..."*
  - Contrast, DifferentialOperators, `gradient`: *"Allocating form of `gradient!`: allocate the result and return it. ... See `gradient!` for the componentwise definition..."*
- **Description:** Every other allocating wrapper in the corpus (`gradient`, `divergence`, `curl`,
  `symmetric_gradient`, `laplacian`, `inverse_laplacian`, `helmholtz_projection`, `dot`, `cross`,
  `tr`, `det`, `transpose`, `sym`, `skew`, `dev`, `norm`, `convolve`, `exponential_convolve`,
  `interpolate`, `anterpolate`, `translation_kernel`) opens with the fixed phrase "Allocating form
  of `X!`: allocate the result and return it," and closes with "See `X!` for...". The four M2
  vector-space operators (`+`, `-`, `*`, `/`) — arguably the most-used, most-visible bindings in the
  package — use a distinct template with no "Allocating form of" opener and no "See `X!` for..."
  closer, just "...; the in-place home is `X!`."

### Finding 2 — Type "fields" list format is punctuated differently in Fields/Points vs. Convolution
- **Type:** format — **Severity:** major — **Confidence:** high
- **Locations:**
  - Fields, `Grid3D`: *"The fields are\n\n- `grid_size::NTuple{3, Int}`: the number of grid points..."* (no colon after "are"; bullet separator is a colon).
  - Points, `ScalarPointValues`: *"The fields are\n\n- `data`: the values, with shape (M,)."* (same colon-bullet style).
  - Convolution, `StoredKernel`: *"The fields are:\n\n- `field` — the `ScalarFieldSpectral` holding the coefficients..."* (colon after "are"; bullet separator is an em dash).
  - Convolution, `SeparableKernel`/`RadialKernel`/`ProductKernel` all match `StoredKernel`'s "The fields are:" + em-dash style.
- **Description:** Every `Fields`/`Points` type (12+ instances: `Grid3D`, `RealFourierLayout`,
  `ScalarFieldPhysical`/`Spectral`, `VectorFieldPhysical`/`Spectral`, `TensorFieldPhysical`/`Spectral`,
  `FieldTransformPlans`, `FieldSpectralMultipliers`, `PointSet`, `ScalarPointValues`,
  `VectorPointValues`, `TensorPointValues`) uses "The fields are" (no colon) with colon-separated
  bullets. All four `Convolution` kernel types instead use "The fields are:" (with colon) and
  em-dash-separated bullets — matching the em-dash style used everywhere else for *function*
  argument lists, but not the sibling module's own type-field lists. Two axes (header punctuation,
  bullet separator) flip together at the module boundary with no apparent reason.

### Finding 3 — `inv`/`materialize_kernel` document each method with its own body; `convolve` shares one body across all its signatures, in the same module
- **Type:** organization — **Severity:** major — **Confidence:** high
- **Locations:**
  - Convolution, `convolve`: one code block stacking all three call forms, `convolve(field, kernel)` / `convolve(kernel, field)` / `convolve(k1, k2)`, followed by ONE shared prose body ("Allocating form of `convolve!`: allocate the result and return...").
  - Convolution, `Base.inv`: four separate signature blocks (`inv(::ProductKernel)`, `inv(::RadialKernel)`, `inv(::SeparableKernel)`, `inv(::StoredKernel)`), each with its **own** distinct paragraph, its own titled admonition (e.g. *"Each factor must have no zeros on any stored mode"* vs. *"The function must have no zeros on any stored mode"*), and its own `source` link, all repeated under one `Base.inv — Function` heading.
  - Same per-method-body split for `materialize_kernel` (separate bodies for `ProductKernel`, `RadialKernel`, `SeparableKernel`).
- **Description:** Two different conventions coexist for "one generic name, several methods" within
  the *same* module: `convolve`, `dot!`, `cross!`, `mul!`, `gradient!` etc. use one shared prose body
  for all listed signatures; `inv` and `materialize_kernel` instead give each method its own
  complete mini-docstring stacked under one header. A reader cannot predict from the corpus which
  convention a new multi-method generic will follow.

### Finding 4 — The kernel-composed "additional arguments" bullet list is present for two operators but missing for a third with the identical pattern
- **Type:** organization — **Severity:** major — **Confidence:** high
- **Locations:**
  - DifferentialOperators, `divergence!`, "The kernel-composed form": *"The additional arguments are:\n\n- `kernel` — ...\n- `α`, `β` — ..."*
  - DifferentialOperators, `helmholtz_projection!`, "The kernel-composed form": identical bulleted "The additional arguments are:" structure.
  - FieldAlgebra, `combine!`, "The kernel-composed form": *"Passing a trailing `kernel` ... convolves the combination with the kernel in the same fused pass. ... with `b === destination` it computes the kernel-filtered accumulate in place."* — no bulleted argument list at all; `kernel` is never introduced as its own bullet anywhere in the docstring.
- **Description:** All three operations add the identical trailing-kernel arity (decision 32/33's
  idiom, per the module prose). Two spell out the added `kernel`/`α`/`β` arguments as a formal
  bulleted sub-list; `combine!`'s equivalent subsection describes the same information only in
  prose, breaking the sub-list pattern its siblings establish right next to it in the corpus.

### Finding 5 — `FieldSpectralMultipliers` splits its convenience constructor into a separate docstring; every other multi-constructor type folds all forms into one
- **Type:** organization — **Severity:** medium — **Confidence:** high
- **Locations:**
  - Fields, `FieldSpectralMultipliers — Type`: documents only the two explicit six-array constructors, then says *"A convenience constructor `FieldSpectralMultipliers(field)` builds both families... and carries its own docstring below."*
  - Fields, `FieldSpectralMultipliers — Method`: a wholly separate docstring block for `FieldSpectralMultipliers(field::AbstractFieldSpectral{T})`.
  - Contrast `ScalarFieldPhysical — Type`, which folds three constructors — two array-based plus a semantically distinct function-sampling constructor with its own `array_type` keyword — into one unified docstring; likewise `TensorFieldPhysical` folds five constructor signatures into one block.
- **Description:** Every other type with multiple constructor forms (`Grid3D`, `RealFourierLayout`,
  `ScalarFieldPhysical`/`Vector`/`TensorFieldPhysical`/`Spectral`) documents all of them — including
  a semantically distinct convenience form — under one Type docstring. `FieldSpectralMultipliers`
  alone breaks this into a Type doc plus a separate Method doc, the only such split in the corpus.

### Finding 6 — `FieldTransformPlans` is the only type with both an "arguments" list and a "fields" list
- **Type:** organization — **Severity:** medium — **Confidence:** medium
- **Locations:**
  - Fields, `FieldTransformPlans`: *"The arguments are:\n\n- `physical`: ...\n- `spectral`: ...\n- `fft_flags`: ...\n- `fft_timelimit`: ..."* followed later by *"The fields are\n\n- `grid::G`: ...\n- `fourier_layout::L`: ...\n- `plan_forward_fft::PF`: ...\n- `plan_inverse_fft::PI`: ..."*
  - Contrast Fields, `ScalarFieldPhysical`: its function-constructor's extra parameters (`f`, `array_type`) are bound only in running prose ("Here `f` is called as `f(x, y, z)`... `array_type` is the array type used...") with no "The arguments are:" heading at all.
- **Description:** `FieldTransformPlans` is the sole type docstring carrying both a formal bulleted
  "arguments" section (for constructor-only parameters that are not literally stored) and a
  "fields" section (for the struct's actual stored fields). Every other type either has one list
  ("The fields are") or explains extra constructor parameters in plain prose — never both headed
  bulleted sections in the same docstring.

### Finding 7 — Warning/caveat admonitions appear in at least three different structural positions
- **Type:** organization — **Severity:** medium — **Confidence:** medium
- **Locations:**
  - Before the steer sentence and arguments: DifferentialOperators, `inverse_laplacian!` — *"The inverse Laplacian is nonlocal"* box sits between the identity paragraph and "Use this in-place form...".
  - Between arguments and formula: Convolution, `exponential_convolve!` — *"The offset must be real-valued"* box sits right after the bulleted arguments list, before the formula.
  - After the formula, immediately before `source`: FieldAlgebra, `mul!` — *"The destination must not alias an input"*; Convolution, `convolve!` — *"A real field needs a Hermitian kernel"*; Convolution, `translation_kernel` — *"At the Nyquist frequency the phase becomes a real attenuation"*.
- **Description:** The same class of load-bearing caveat (a hazard the user must know before calling)
  is boxed in three different positions relative to the arguments list and the formula, with no
  visible rule (e.g. "safety" caveats vs. "correctness" caveats) that predicts which position a new
  admonition should take.

### Finding 8 — Infix-alias docstrings are handled two different ways
- **Type:** organization — **Severity:** minor — **Confidence:** medium
- **Locations:**
  - FieldAlgebra, `LinearAlgebra.dot` and `LinearAlgebra.:⋅`: word-for-word identical bodies ("Allocating form of `dot!`... The infix alias $\cdot$ (`⋅`) is also exported...").
  - FieldAlgebra, `LinearAlgebra.cross` and `LinearAlgebra.:×`: likewise word-for-word identical.
  - Convolution, `convolve` vs. `GBGPeriodicFields.Convolution.:⋆`: the infix docstring is distinct, shorter, freshly-written prose — *"Infix alias for `convolve`, in every arity: `a ⋆ b` is `convolve(a, b)`. ... The distinct glyph keeps the operation apart from `*`..."* — not a duplicate of `convolve`'s own body.
- **Description:** `dot`/`⋅` and `cross`/`×` duplicate the allocating function's entire docstring
  verbatim onto the infix binding; `convolve`/`⋆` instead gets its own independently-composed thin
  wrapper. Both are defensible individually, but the corpus does not commit to one approach for
  "named function + infix alias" pairs.

### Finding 9 — Convolution's module docstring uses three separate lists where six of eight module pages use one
- **Type:** organization — **Severity:** minor — **Confidence:** medium
- **Locations:**
  - Fields, DifferentialOperators, FieldAlgebra, Points, Interpolation each open their public-surface summary with one list under the fixed phrase "The parts are:" (e.g. Fields: *"The parts are:\n\n- Grid and layout — ...\n- Field types — ...\n..."*).
  - Convolution instead runs three separately-headed lists in its module docstring: *"Convolution operations:\n\n- ...\nKernel storage classes:\n\n- ...\nKernel builders:\n\n- ..."* with no unifying "The parts are:" lead-in.
- **Description:** Six of the eight submodule pages converge on exactly one "The parts are:" list as
  the module-overview shape (Reductions and FiberSections vary the lead-in phrase but still use one
  list). Convolution alone fragments its overview into three independently-titled lists, the
  strongest structural outlier among the module docstrings.

### Finding 10 — Points' "Point-value algebra" section is the only `##` section with no docstring content
- **Type:** organization — **Severity:** minor — **Confidence:** medium
- **Locations:**
  - Points, `## Point-value algebra`: entirely prose — *"The point values carry the same fiberwise algebra as fields in physical representation, through the very same generics... There is no second set of docstrings for them: each per-component formula is generated from one builder shared with `FieldAlgebra`, so the operations are documented once, on the `FieldAlgebra` page."*
  - Every other `##`-level section on every module page (e.g. Points' own "Point and point-set types", "HDF5 persistence") contains at least one rendered docstring block.
- **Description:** This is an explained, deliberate choice (avoiding duplicate docstrings), but it
  makes the section a structural outlier: a `##` heading in the sidebar TOC that a reader clicking
  through will find contains no actual API entries, unlike every sibling heading at the same level
  across the whole API reference.
