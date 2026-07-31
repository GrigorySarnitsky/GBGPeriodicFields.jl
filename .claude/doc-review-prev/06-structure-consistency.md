# Documentation-Structure Auditor — findings

## Inferred template (the implicit skeleton the corpus follows)

**Function `f!`/`f` pair.** The in-place `!` form is the "home": signature block →
one-sentence identity ("Compute the X (`X` ≡ symbol) … write it into `destination`,
returning `destination`") → physical-meaning + formula → optional load-bearing caveat →
arguments → spectral form. The allocating `f` is a thin wrapper opening
"**Allocating form of `X!`:** allocate the result and return it …" + one-sentence meaning
+ "See `X!` for the componentwise definition and the spectral kernel." This is followed
almost verbatim by every DifferentialOperators operator and by `dot`/`cross`/`tr`/`det`/
`norm`/`interpolate`/`anterpolate`/`to_physical`/`to_spectral`.

**Type docstring.** Constructor-first: signature block (constructors) → one-sentence
identity ("X in Y representation, stored as …") → per-argument prose ("Here `arg` …") →
a demoted fields list ("The fields are") only where the struct exposes meaningful named
fields → trailing constructor notes.

**Module docstring = map.** Identity → a bulleted one-liner-per-operation-family list.

The findings below are the entries that break this inferred template. All are
organizational/uniformity issues (none are factually wrong), so severities run
minor → nit.

---

## Finding 1 — Load-bearing caveats use three different mechanisms (worst: the FFT-overwrite gotcha has none)

- **type:** format
- **severity:** minor
- **confidence:** high

**Locations / quotes:**

Default-titled `!!! warning` admonitions:
- `api / DifferentialOperators` → inverse_laplacian! (L662): "**Warning**As the inverse of a differential operator, $\Delta^{-1}$ is nonlocal…"
- `api / DifferentialOperators` → helmholtz_projection! (L696): "**Warning**The inverse Laplacian $\Delta^{-1}$ is nonlocal…"
- `api / FieldAlgebra` → mul! (L1214): "**Warning**As with `LinearAlgebra.mul!`, `destination` must not share storage with any input…"
- `api / Interpolation` → NUFFT (L2194): "**Warning**A `NUFFT` plan holds an oversampled work grid…"

Custom-titled admonitions (no "Warning"/"Note" word):
- `api / Convolution` → convolve! (L364): "…$\beta \mathrm{destination}$.**A real field needs a Hermitian kernel**The stored half-spectrum holds only the modes…"
- `api / Convolution` → translation_kernel (L459): "…**At the Nyquist frequency the phase becomes a real attenuation**On an even-length axis…"

Plain prose, no admonition at all:
- `api / Fields` → to_physical! (L1724): "The inverse transform uses `spectral` as scratch space and may overwrite it: on return its coefficients are left in an undefined state…"
- `api / Fields` → to_spectral! (L1750): "The forward transform may overwrite `physical` on some backends… do not rely on the source surviving."

**Description:** Three distinct mechanisms highlight a load-bearing caveat: a default
"Warning" admonition, a descriptive custom-titled admonition, and unhighlighted running
prose. The sharpest inconsistency is that the transform functions' overwrite/scratch
caveat — the destroy-your-input FFT gotcha that the docstring rubric would treat as
maximally load-bearing — is the *only* such caveat presented with no admonition at all,
while a comparatively milder no-alias note on `mul!` gets a full Warning box. Pick one
convention (Warning admonition for genuine gotchas) and apply it uniformly; at minimum,
elevate the `to_physical!`/`to_spectral!` overwrite caveat to the same admonition class as
`mul!`.

---

## Finding 2 — Allocating-form opening sentence breaks the "Allocating form of `X!`:" template in four entries

- **type:** format
- **severity:** minor
- **confidence:** high

**Locations / quotes:**

Template followed (16 entries), e.g.:
- `api / DifferentialOperators` → gradient (L526): "**Allocating form of `gradient!`:** allocate the result and return it."
- `api / FieldAlgebra` → dot (L1160), cross (L1192), tr (L1235), det (L1252), norm (L1339): all "Allocating form of `X!`…"
- `api / Interpolation` → interpolate (L2110), anterpolate (L2130): "Allocating form of `interpolate!`/`anterpolate!`…"

Deviations (4 entries):
- `api / Convolution` → convolve (L373): "**Allocate the result and return** the periodic convolution of `field` with the kernel `kernel`…"
- `api / FieldAlgebra` → sym (L1282): "**Allocate the result and compute** the symmetric part of a second-order tensor…"
- `api / FieldAlgebra` → skew (L1299): "**Allocate the result and compute** the skew-symmetric part…"
- `api / FieldAlgebra` → dev (L1316): "**Allocate the result and compute** the deviatoric part…"

**Description:** Sixteen allocating wrappers open with the fixed phrase "Allocating form
of `X!`:"; four open with "Allocate the result and …" instead. `sym`/`skew`/`dev` have a
partial excuse (they additionally accept a bare `FiberTensor2`, so they are not purely the
allocating form of the field-only `sym!`), but `convolve` is a plain `f!`/`f` pair with no
such reason and still deviates. Normalize the opening (either bring `convolve` — and, if
desired, sym/skew/dev — onto the "Allocating form of `X!`:" phrasing, or accept the second
phrasing only where the wrapper genuinely does more than the `!` form).

---

## Finding 3 — Argument documentation has no single convention; `combine!` and `weighted_inner` are lone within-page outliers

- **type:** organization
- **severity:** minor
- **confidence:** medium

**Locations / quotes:**

Enumerated "The arguments are:" + `- `arg` — …` bullets:
- `api / DifferentialOperators`: every operator (L512, 545, 577, 608, 636, 665, 699) — uniform.
- `api / Convolution`: convolve! and all five builders use `- `arg` —` bullets — uniform.
- `api / FieldAlgebra` → combine! (L1107): "The arguments are:" — **the only op on the page with one.**
- `api / Reductions` → weighted_inner (L2465): "The arguments are:" — **the only reduction with one.**

Prose / omitted on the same pages:
- `api / FieldAlgebra` → add!, subtract!, multiply!, divide!, dot!, cross!, mul!, tr!, det!, transpose!, sym!, skew!, dev!, norm!: no per-argument enumeration.
- `api / Reductions` → inner (L2450): "The arguments `f` and `g` are two compatible sections…"; lpnorm (L2491): "The exponent `p` selects the norm…"; integral/l2norm: none; radial_* : prose.
- `api / Fields`: all field/transform functions use "Here `arg` is/contains …" prose (e.g. to_physical! L1723, ScalarFieldPhysical L1526).

The same prose-vs-bullets split recurs in the **type** docstrings: `Grid3D` (L1469),
`FieldTransformPlans` (L1680), and `FieldSpectralMultipliers` (L1704) list their fields as
"The fields are" bullets, while `RealFourierLayout` and the six field-representation types
document their constructor arguments in "Here …" prose.

**Description:** Across the corpus, arguments are documented three ways — enumerated
bullets (DifferentialOperators, Convolution), "Here `arg` …" prose (Fields), or omitted
(most FieldAlgebra) — split largely by module. Within a single page the split becomes a
visible outlier: `combine!` is the sole FieldAlgebra operation, and `weighted_inner` the
sole Reductions operation, carrying a formal "The arguments are:" bullet block while every
sibling uses prose or nothing. Both outliers are defensible (they carry the most/most-
complex arguments), but the reader meets two different exposition shapes on one page.
Decide on one argument-block convention per page (or corpus-wide) and apply it.

---

## Finding 4 — A public callable (`field(x)`) is documented under Interpolation's "Internal API" (contributors) section

- **type:** organization
- **severity:** minor
- **confidence:** medium

**Locations / quotes:**
- `api / Interpolation`, "## Internal API" header (L2202): "…documented for contributors."
- immediately under it (L2203–2207): "`GBGPeriodicFields.Fields.AbstractFieldPhysical` — Method … `(field::AbstractFieldPhysical)(x; scheme = CatmullRom)` … This is the ergonomic face of a one-point `interpolate` gather…"
- but the same callable is advertised as public in the module docstring (L2085): "plus the callable `f(x)` (and its broadcast `f.(xs)`) as the ergonomic face of a single-point gather" and in interpolate! (L2099): "and for a single position the callable `field(x)`."

**Description:** The callable-field evaluation is presented as a first-class public
convenience in two prose locations (the module map and `interpolate!`), yet its only
docstring sits inside the "Internal API … documented for contributors" block, alongside
`AbstractSplineScheme` and the Fornberg helpers. A user-facing operation filed under the
contributors-only section contradicts the page's own framing; it should live in the public
"Transfer operations" group with `interpolate`/`anterpolate`.

---

## Finding 5 — `sym!`/`skew!`/`dev!` inline their formula and skip the "Pointwise over the base:" display that their FieldAlgebra siblings use

- **type:** organization
- **severity:** minor
- **confidence:** high

**Locations / quotes:**

Sibling ! homes present the formula as a lead-in + display:
- `api / FieldAlgebra` → transpose! (L1264–1265): "…Pointwise over the base: \[\mathrm{destination}_{ij} = A_{ji}.\]"
- tr! (L1226–1227): "Pointwise over the base, it contracts the two fiber indices… \[\operatorname{tr}(A) = A_{ii} = …\]"
- det! (L1244–1245), norm! (L1329–1330): same "Pointwise over the base …" + display shape.

Deviations (formula inlined into the opening sentence, no display, no lead-in):
- sym! (L1273): "Compute the symmetric part $\operatorname{sym}(A) = \tfrac{1}{2}(A + A^\top)$ of a second-order tensor field in place, and return `destination`. The operation is linear and representation-preserving…"
- skew! (L1290): "Compute the skew-symmetric part $\operatorname{skew}(A) = \tfrac{1}{2}(A - A^\top)$ …"
- dev! (L1307): "Compute the deviatoric part $\operatorname{dev}(A) = A - \tfrac{1}{3}\operatorname{tr}(A) I$ …"

**Description:** In the "Transposition and decomposition" and "Norm" groups, `transpose!`,
`tr!`, `det!`, and `norm!` state the defining formula as a separate display under a
"Pointwise over the base" lead-in, while `sym!`/`skew!`/`dev!` fold the formula into the
first sentence and carry no display and no lead-in. Same operation family, two
formula-placement shapes. (Together with Finding 2 this makes the sym/skew/dev cluster the
most template-divergent trio in FieldAlgebra.)

---

## Finding 6 — The `!`→allocating cross-reference is present in only two modules and phrased differently between them

- **type:** organization
- **severity:** nit
- **confidence:** medium

**Locations / quotes:**

Present, phrasing A (every DifferentialOperators ! home):
- gradient! (L511), divergence! (L544), curl! (L576), symmetric_gradient! (L607), laplacian! (L635), inverse_laplacian! (L664), helmholtz_projection! (L698): "Use this in-place form when `destination` is already allocated; the allocating `X` returns a fresh result instead."

Present, phrasing B (Interpolation ! homes):
- interpolate! (L2099): "This is the in-place home of the gather $W$; for a freshly allocated result use `interpolate`…"
- anterpolate! (L2117): "This is the in-place home of the scatter $W^\top$; for a freshly allocated result use `anterpolate`."

Absent (the ! home never points forward to its allocating wrapper):
- `api / FieldAlgebra` ! homes (add!, combine!, dot!, cross!, mul!, tr!, det!, transpose!, sym!, skew!, dev!, norm!), `api / Convolution` convolve!, `api / Reductions`, and the Fields transforms.

**Description:** Every allocating wrapper points back to its `!` home ("See `X!` for …"),
but the reverse pointer (from the `!` home to the allocating form) exists only in
DifferentialOperators and Interpolation — and those two phrase it differently ("Use this
in-place form when …" vs "This is the in-place home of …"). Either add the pointer
uniformly or drop it uniformly, and settle on one phrasing.

---

## Finding 7 — Infix operator aliases are documented two ways

- **type:** organization
- **severity:** nit
- **confidence:** low

**Locations / quotes:**
- `api / Convolution` → `:⋆` (L380): a distinct, thin alias docstring — "Infix alias for `convolve`: `field ⋆ kernel` is `convolve(field, kernel)`… Its own symbol keeps the operation distinct from `*`…"
- `api / FieldAlgebra` → `LinearAlgebra.:⋅` (L1163–1168): reproduces `dot`'s full docstring verbatim (identical text to `LinearAlgebra.dot` at L1155–1160).
- `api / FieldAlgebra` → `LinearAlgebra.:×` (L1195–1199): reproduces `cross`'s full docstring verbatim (identical to `LinearAlgebra.cross` at L1188–1192).

**Description:** The convolution infix `⋆` gets a short, purpose-built "Infix alias for
`convolve`" entry, whereas the `⋅` and `×` entries render their base function's entire
docstring a second time. (The `⋅`/`×` duplication is partly language-forced — in Julia
`⋅ === dot` and `× === cross` are the same binding, so their `@doc` is the base function's —
whereas `⋆` is a separate function that can carry its own string.) Still, the API page
chooses to list all three as separate `@docs` entries, so the reader sees `dot`'s and
`cross`'s meaning printed twice but `convolve`'s alias handled as a one-liner. If the `⋆`
thin-pointer style is the intended pattern, consider not double-listing `⋅`/`×` (or
accept the duplication as an unavoidable Documenter artifact and leave `⋆` as-is for
consistency of intent).
