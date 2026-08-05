# Documentation-structure audit — hat: structure-consistency

## Inferred template

**Function docstring** (the `!` in-place form is the "home"): (1) one-sentence identity, often
naming the math symbol via `` `f` $\equiv$ ... ``; (2) verbatim steer sentence "Use this in-place
form when `destination` is already allocated; the allocating `f` returns a fresh result instead.";
(3) `The arguments are:` bulleted list — used when the signature has ≥3 positional args or any
keyword, otherwise the operands are bound in prose; (4) caveats as a `!!!`-style admonition with a
custom descriptive title; (5) a display formula, physical-meaning-first; (6) a citation block
(`Reference:` inline for one work, `References` bulleted for ≥2); (7) `source`. The allocating
sibling is a thin wrapper: "Allocating form of `f!`: ... See `f!` for ...", carrying no second
formula, placed immediately after its home.

**Type docstring** (constructor-first): a callable constructor-signature code block, a one-sentence
identity, then `The fields are` — one bullet per stored struct field.

**Module docstring**: identity/scope paragraphs, then `The parts are:` — one bullet per
page-section or per headline operation, linking each — then optional closing prose, `source`.

Findings below are outliers against this inferred template, ranked most-severe first.

---

### 1. Three public kernel types skip the constructor-signature code block

- **Severity:** major **Confidence:** high
- **Locations:** PAGE api/Convolution, "Kernel storage classes" — `SeparableKernel` code block is
  literally `SeparableKernel` (bare); `RadialKernel` code block is `RadialKernel` (bare);
  `ProductKernel` code block is `ProductKernel` (bare). Contrast the same section's
  `StoredKernel(field::ScalarFieldSpectral)`, which does show a constructor.
- **Contradicts:** every other public concrete type in the corpus opens with a callable signature —
  e.g. `Grid3D(grid_size::NTuple{3,Int}, ...)`, `PointSet(coordinates::AbstractArray{T,2})`,
  `LalescuSpline(n, m = 1; T = Float64)`, `NUFFT(reference::AbstractFieldSpectral; tol = 1e-10, ...)`.
- **Description:** `SeparableKernel`/`RadialKernel`/`ProductKernel` are concrete, publicly documented
  types (not abstract), yet their code fence shows only the bare type name — no constructor. They
  still carry a full `The fields are` bullet list afterward, so the template is half-applied: the
  "constructor" half of "constructor-first" is dropped for exactly these three types while the
  "fields list" half survives.

### 2. Type constructor parameters are documented in three incompatible shapes

- **Severity:** major **Confidence:** high
- **Locations:** PAGE api/Fields "Base and layout types" — `Grid3D`: `The fields are` bulleted
  list. PAGE api/Interpolation "Transfer-scheme types" — `NUFFT(reference::...; tol=1e-10,
  oversampling=2, width=0, beta=0)`: `The arguments are:` bulleted list. Same page —
  `LalescuSpline(n, m = 1; T = Float64)`: no bulleted section at all — "The `T` keyword sets the
  element type the weight coefficients are stored in (`Float64` by default)" is bound in running
  prose, and `LagrangeSpline(n; T = Float64)` does the same.
- **Contradicts:** the corpus's own inferred rule (evidenced by `NUFFT`, which has a keyword
  argument and gets a bulleted list) is that a keyword argument forces the bulleted form; both
  `LalescuSpline` and `LagrangeSpline` also take a keyword (`T`) yet stay in prose.
- **Description:** the same content category — a type's constructor parameters — is presented as
  `The fields are:` bullets, as `The arguments are:` bullets, or as unbulleted prose depending on
  which type, with no visible rule distinguishing the three (all are concrete types with a keyword
  argument or multiple positional ones).

### 3. `mul!`'s allocating wrapper `*` is not adjacent to `mul!`

- **Severity:** major **Confidence:** high
- **Locations:** PAGE api/FieldAlgebra, "Contraction and product operations" — `mul!`'s docstring
  ends "the allocating `*` returns a fresh result instead," but the next entry on the page is
  `tr!`, not `*`. The `*` docstring instead sits under "Vector-space and scalar-field-scaling
  operations", worded "Allocating form of `multiply!` and, for the tensor contractions, `mul!`: ...".
- **Contradicts:** every other `!`/wrapper pair sits back-to-back on the page: `dot!`→`dot`→`⋅`,
  `cross!`→`cross`→`×`, `tr!`→`tr`, `det!`→`det`, `transpose!`→`transpose`, `sym!`→`sym`,
  `skew!`→`skew`, `dev!`→`dev`, `norm!`→`norm`.
- **Description:** the "wrapper follows its home" adjacency that every other pair in the module
  observes is broken for `mul!`: its wrapper is folded into an unrelated section's `*` entry and
  never repeated or cross-referenced next to `mul!` itself.

### 4. FieldAlgebra's own section label doesn't match its rendered heading

- **Severity:** medium **Confidence:** high
- **Locations:** PAGE api/FieldAlgebra module docstring, "The parts are:" — first bullet:
  "**Vector-space and module operations** — `add!` and `subtract!` ...". The actual page heading
  (also listed in the sidebar/API-overview dump on PAGE Home and PAGE api) is "## Vector-space and
  scalar-field-scaling operations".
- **Contradicts:** the other four bullets in the same list match their headings verbatim
  ("Contraction and product operations", "Transposition and decomposition operations", "Norm
  operations", "Arbitrary fiber map" all appear as both bullet label and `##` heading).
- **Description:** one bullet out of five in FieldAlgebra's own "parts" list uses a label that
  disagrees with the section it is supposed to name, while its four siblings agree exactly.

### 5. Module "parts" list lead-in phrasing is inconsistent across modules

- **Severity:** minor **Confidence:** high
- **Locations:** PAGE api/DifferentialOperators, api/FieldAlgebra, api/Fields, api/Points: "The
  parts are:". PAGE api/Reductions: "The parts are, each linking to the home where its formula
  lives:". PAGE api/FiberSections: "it groups six families of machinery:". PAGE api/Convolution: no
  lead-in sentence at all — goes directly into three separately labeled lists, "Convolution
  operations:", "Kernel storage classes:", "Kernel builders:".
- **Description:** five modules use variants of one canonical lead-in sentence while two (FiberSections,
  Convolution) depart from it entirely — Convolution additionally splits into three named lists where
  every other module uses one.

### 6. Formula-preview placement in the identity sentence is inconsistent

- **Severity:** minor **Confidence:** medium
- **Locations:** PAGE api/DifferentialOperators — `gradient!`'s identity paragraph already contains
  ``$(\nabla\varphi)_i = \partial_{x_i}\varphi$``; `curl!`, `symmetric_gradient!` do the same. PAGE
  api/FieldAlgebra — `combine!`'s identity sentence contains ``$\alpha a + \beta b$``. Contrast
  `dot!`'s identity ("Compute a fiberwise inner product in place, and return `destination`." — no
  formula) and `cross!`, `mul!`, `tr!`, `det!`, `norm!`, `transpose!`, `sym!`, `skew!`, `dev!`,
  `add!`, `subtract!`, none of which preview a formula before "The arguments are:"; all push their
  formula to one closing display equation.
- **Description:** operators of comparable arity and shape (destination plus 1–3 field/constant
  operands) split roughly along module lines on whether the identity sentence previews a compact
  formula or defers all math to the closing display equation, with `combine!` as an FieldAlgebra
  exception to its own module's majority pattern.

### 7. `translation_kernel!` reworks the otherwise-verbatim in-place steer sentence

- **Severity:** minor **Confidence:** medium
- **Locations:** PAGE api/Convolution, `translation_kernel!`: "Use this in-place form when a
  displacement changes and the kernel is already allocated; the allocating `translation_kernel`
  returns a fresh kernel instead."
- **Contradicts:** the same sentence appears verbatim (substituting only the function name) in
  ~30 other `!` docstrings, e.g. `gradient!`: "Use this in-place form when `destination` is already
  allocated; the allocating `gradient` returns a fresh result instead."
- **Description:** every other steer sentence keeps "destination"/"result" as the generic nouns;
  this is the one instance reworded around the operation's specific vocabulary ("a displacement
  changes", "fresh kernel").

### 8. `to_physical!`/`to_spectral!` drop the standalone steer sentence

- **Severity:** minor **Confidence:** medium
- **Locations:** PAGE api/Fields, "Transform operations" — `to_physical!`'s only pointer to its
  allocating form is inside the admonition body: "Use the allocating `to_physical` when `spectral`
  must be preserved." There is no separate "Use this in-place form when `destination` is already
  allocated..." sentence.
- **Contradicts:** other `!` operators that also carry a caveat admonition (e.g. `convolve!`) keep
  *both* the standalone steer sentence *and* a separate admonition — the two are not treated as
  redundant elsewhere.
- **Description:** `to_physical!`/`to_spectral!` are the only pair with both an allocating sibling
  and a caveat admonition that merges the steer into the admonition instead of stating it separately.

### 9. `NUFFT`'s admonition title nearly duplicates its own opening sentence

- **Severity:** nit **Confidence:** low
- **Locations:** PAGE api/Interpolation, `NUFFT` — admonition title "A plan holds an oversampled
  work grid" immediately followed by body text "A NUFFT plan holds an oversampled work grid of
  about $\sigma^3$ times the field's memory...".
- **Description:** every other admonition title states the caveat in words distinct from the body's
  opening clause (e.g. "The destination must not alias an input" → "As with `LinearAlgebra.mul!`,
  ..."); this is the one instance where the title is essentially the body's first six words restated
  as a title.

### 10. The physical/spectral validity statement's placement (standalone vs embedded) has no visible rule

- **Severity:** nit **Confidence:** low
- **Locations:** PAGE api/Convolution, `convolve!`: standalone closing sentence "Spectral
  representation only: on the torus convolution is the coefficientwise spectral product." PAGE
  api/Reductions, `lpnorm`: standalone "It is physical-space only." Contrast PAGE api/FieldAlgebra,
  `det!`/`norm!`/`dot!`/`cross!`, where the equivalent fact is embedded mid-paragraph ("...it is
  nonlinear, so it is defined in physical-space representation only; there is no spectral form.").
- **Description:** the same category of fact (representation validity) sometimes gets its own
  short terminal sentence and sometimes is folded into a longer explanatory paragraph, without an
  evident rule for which docstrings get which treatment.

### 11. `Interpolation` module docstring's "References" sub-list appears unseparated from its preceding bullet

- **Severity:** nit **Confidence:** low
- **Locations:** PAGE api/Interpolation module docstring — "...accumulation is the common case for
  the scatter).References\n\n- C. C. Lalescu, ...".
- **Description:** the "References" heading runs directly into the previous bullet's closing
  parenthesis with no separating blank line/heading treatment, unlike e.g. `LalescuSpline`'s clearly
  separated "References" block. This may be an artifact of the HTML→text extraction rather than the
  authored source, so confidence is kept low, but it is worth checking against the live rendered page.
