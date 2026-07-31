# Consistency-Matrix Audit — Hat: Consistency Auditor

Methodology: built a matrix of recurring mathematical objects, notational conventions, formulas,
method-count claims, and per-module "what this module provides" summaries, then diffed each
entity's every appearance across all 18 rendered pages (Home, api overview, architecture,
formalization, notation, performance, testing, tutorial, the eight `api/*` module pages, and the
`examples/hist_cpu` page). Most large numeric claims (benchmark ratios, method-count baselines,
citation texts, the decision-42/decision-41 formula updates) cross-checked cleanly — evidence of
real prior audit work in this codebase. The findings below are the divergences that survived that
sweep.

---

## Finding 1 — Spline reproduction-degree formula stated without its necessary boundary qualifier

**Type:** math / contradiction
**Severity:** major
**Confidence:** high

**Locations:**
- PAGE: architecture, §10 ("Method: the local splines"): *"The smooth scheme reproduces polynomials to degree `min(2m+1, 2n)`; the Lagrange scheme to degree `2n+1`."* — stated as an unqualified law, two sentences after the same paragraph says *"(C^m, 0 ≤ m ≤ 2n; **m = 0 is linear**, n = 1, m = 1 is Catmull–Rom)"*.
- PAGE: architecture, §13 decision log ("Transfer kernels implemented"): *"Reproduction is $\min(2m{+}1, 2n)$ (smooth) / $2n{+}1$ (Lagrange)"* — again unqualified, in a paragraph that also says *"($…$; $m=0$ is linear)"*.
- PAGE: api / Interpolation, `LalescuSpline` docstring: *"It reproduces polynomials up to degree $\min(2m{+}1, 2n)$ **(for $n \ge 1$)**. Special cases: $m = 0$ is linear interpolation over the two central nodes (**independent of $n$**)"* — the same formula, correctly scoped.

**Contradicts:** the Architecture page's own unqualified formula, evaluated at the explicitly-valid,
explicitly-named boundary case $n=0,\ m=0$ (`LalescuSpline(0,0)`, used by name elsewhere in the same
document — PAGE: architecture, §13 decision-22 "Assignment-window deconvolution": *"the positive
linear assignment (`LalescuSpline(0, 0)`, the 2-point linear kernel used for a density)"*), gives
$\min(2\cdot0+1,\ 2\cdot0)=\min(1,0)=0$ — i.e. "reproduces only constants." That is false: plain
2-point linear interpolation (which is exactly what $n=0,m=0$ is, and what the very same sentence
calls it) trivially reproduces every degree-≤1 polynomial exactly, independent of any finite-difference
stencil width. The `LalescuSpline` docstring on the Interpolation page gets this right by explicitly
excluding $n=0$ from the general formula and stating the $m=0$ case separately with no numeric
degree attached to the (irrelevant) general formula. The Architecture page's two restatements omit
that scoping, so read literally they assert "linear interpolation reproduces only constants" — a
direct internal contradiction with calling the same case "linear" in the same sentence.

**Description:** A formula given as a general law in the design document is technically wrong at a
boundary case that the document itself names and uses (`LalescuSpline(0,0)` — the assignment-window
kernel). The more careful, scoped version lives only on the API page for `LalescuSpline`. This is
exactly the class of "correctness verified, not asserted" defect a formula-precision sweep should
catch: the claim type-checks and reads fine casually, but literal evaluation at a valid input fails.

---

## Finding 2 — The top-level `GBGPeriodicFields.jl` module docstring under-lists what its submodules provide

**Type:** organization / contradiction (completeness)
**Severity:** major
**Confidence:** high

**Locations:**
- PAGE: api / GBGPeriodicFields (the umbrella module docstring): *"`Reductions` provides the L²/measure reductions `integral`, `inner`, `weighted_inner`, `l2norm`, and `lpnorm`, plus the radial diagnostics `radial_spectrum` and `radial_correlation`."* — no mention of `mean`, `std`, `var`, `maximum`, `minimum`, or `extrema` anywhere in the umbrella docstring.
- Same page: *"`FieldAlgebra` provides the fiberwise algebra: the weighted combination `combine!`, the contractions `dot` and `cross`, the tensor product `mul!`, the transpose `transpose!`, the norm `norm`, the trace and determinant `tr`/`det`, and the `sym`/`skew`/`dev` decompositions."* — no mention of `add!`/`subtract!` (`+`/`-`), the vector-space operations FieldAlgebra's own page lists first.
- Same page: *"`Fields` supplies the field and grid types, the storage layout and broadcasting, the FFT transform plans, and the transforms `to_physical` and `to_spectral` between the two representations."* — no mention of `write_field`/`read_field` (HDF5 persistence).

**Contradicts:**
- PAGE: Home, Main components bullet for Reductions: *"…the normalized, intensive `inner`, `l2norm`, `lpnorm`, and `mean`/`std`/`var`, … plus the measure-independent `maximum`/`minimum`/`extrema`…"*
- PAGE: api (API overview): *"Reductions: … base reductions (`integral`, `inner`, `weighted_inner`, `l2norm`, `lpnorm`, `mean`/`std`/`var`, `maximum`) over fields and point-values…"*
- PAGE: api / Reductions, module docstring: *"The `mean`, `std`, and `var` moments (extending `Statistics`) and the `maximum`, `minimum`, and `extrema` order statistics (extending `Base`) are also defined for sections; they are method extensions of the standard-library generics rather than package exports, and are described in the module summary above."*
- PAGE: api / FieldAlgebra, module docstring: *"Vector-space and module operations — `add!` and `subtract!` (`+`, `-`), the weighted combination `combine!` (αa + βb), real scaling, and scalar-field multiplication and division…"*
- PAGE: api / Fields, module docstring: *"Persistence — `write_field` and `read_field` map a field to and from one self-describing HDF5 group…"* and the page's dedicated `## HDF5 persistence` section.

**Description:** Every other index-like surface (Home's Main Components, the API-overview page, and
each submodule's own page) treats `mean`/`std`/`var`/`maximum`/`minimum`/`extrema` as core,
long-established parts of `Reductions`, and `add!`/`subtract!` as the base of `FieldAlgebra`'s M2
family, and HDF5 persistence as a first-class `Fields` feature. The umbrella docstring — the single
most prominent "what does this package do" surface, reached by `?GBGPeriodicFields` — omits all of
these while still itemizing narrower/derived operations (`combine!`, `weighted_inner`,
`radial_spectrum`). A reader who trusts the umbrella listing as complete would not know the package
has moments, order statistics, plain addition, or checkpoint/restart at all. The Reductions omission
is the most severe (six operations, roughly half the family, entirely absent).

---

## Finding 3 — "L²-adjoint pair" claimed for `interpolate`/`anterpolate` where the package's own more careful pages show the bare pair is *not* the L² adjoint

**Type:** math / contradiction
**Severity:** major
**Confidence:** medium

**Locations:**
- PAGE: Home, Main components: *"`Interpolation`: the grid↔point transfer — interpolation (gather $W$) and anterpolation (scatter $W^\top$) as an **L²-adjoint pair**, under a choice of `AbstractTransferScheme`…"*
- PAGE: api (API overview): *"Interpolation: the grid↔point transfer — interpolation (gather) and anterpolation (scatter) as an **L²-adjoint pair**, under an `AbstractTransferScheme`…"*
- PAGE: formalization, §"Interpolation / anterpolation": *"So the bare $\langle Wf, q\rangle_{\text{pts}} = \langle f, W^{\top}q\rangle_{\text{grid}}$ is **false unless $N = M$** — the two sides differ by $N/M$. **This is the slip the formalization catches**: it type-checks, but the expansion does not match. The clean adjunction uses the measure-adjoint $\iota_* := (N/M) W^{\top}$…"*
- PAGE: api / Interpolation, module docstring: never uses the phrase "L²-adjoint"; it instead says *"The two are exact transposes"* and gives the correctly $M$/$N$-scaled relation *"$M \langle Wf, q \rangle_{\text{pts}} = \sum_p (Wf)_p\cdot q_p = \sum_x f(x)\cdot(W^\top q)(x) = N \langle f, W^\top q \rangle_{\text{grid}}$."*

**Contradicts:** the Home and API-overview pages assert flatly that `interpolate`/`anterpolate`
($W$/$W^\top$, the actually-implemented, actually-callable pair) *are* "an L²-adjoint pair" — with no
qualifier. The Formalization page explicitly derives, and names as "the slip," that this exact
unqualified claim is false unless $N=M$ (grid-point count equals point count, essentially never true
in practice): the real L²-adjoint of $W$ is $\iota_* = (N/M)W^\top$, a *rescaled* anterpolate, not
`anterpolate` itself. The Interpolation module's own page and the Architecture §10 body text are
careful never to call the bare pair "L²-adjoint" for exactly this reason.

**Description:** A user who takes the Home/API-overview description at face value and tries to
verify adjointness with the package's own `inner` (its literal L² inner product) — e.g. asserting
`inner(interpolate(f, xs), q) ≈ inner(f, anterpolate(grid, xs, q))` — will get a result off by the
factor $N/M$, reproducing precisely the "slip" the Formalization page was written to catch. The two
summary pages should either drop "L²" (say "adjoint pair," matching the module page) or add the
$N/M$ caveat.

---

## Finding 4 — The symbol `N` is bound two different ways: total grid-point count vs. per-axis grid size

**Type:** normalization / contradiction (notation)
**Severity:** minor
**Confidence:** medium

**Locations:**
- PAGE: notation, "Base and fiber" table: *"$N$ | the grid-point count $\prod_i N_i$ | `prod(grid_size)`"* — the single canonical binding, and the one used pervasively in every reduction/Parseval/DC-mode formula (e.g. PAGE: formalization: *"$\langle f, g\rangle_{\text{grid}} := \frac{1}{N} \sum_{n=1}^{N} f_n\cdot g_n$"*; PAGE: api / Reductions: *"$\mathrm{mean}(f) = \hat f(0)/N$"*).
- PAGE: architecture, §13 decision log ("The CPU path's performance target…"): *"Taking one scalar field in either representation as $8 N^3$ bytes in `Float64` (the physical array and the rfft half-spectrum agree to within a part in $N$) … one GH200 stops near $768^3$ where a thin CPU node reaches about $1536^3$."*
- PAGE: performance, §1: *"Counting one scalar field in either representation as $8 N^3$ bytes in `Float64` (**$N$ the per-axis grid size**) and a solver's live set at order 25 such fields, a single GH200 runs out near $768^3$…"*

**Contradicts:** the Notation page's explicit, singular definition of $N$ as the *total* grid-point
count $\prod_i N_i$ (so, e.g., $N=256^3$ for a $256^3$ cubic grid, not $N=256$). The two design-doc
passages above instead use $N$ locally to mean the *per-axis* size, so that "$N^3$" reads as the
total point count and "$768^3$"/"$1536^3$" are meaningful grid sizes — the opposite convention from
every reduction formula elsewhere in the same document set. The Notation page states it governs
"the docstrings **and the design documents**," so this is an in-scope collision, not an out-of-scope
one. The Performance page at least glosses it locally ("$N$ the per-axis grid size"); the Architecture
decision-log copy of the same sentence carries no such gloss, so read in isolation it is ambiguous
against the pervasive $N=\text{total}$ convention.

**Description:** A minor but genuine "one glyph, two meanings" collision, confined to one
self-contained decision-log paragraph and its Performance-page mirror; low risk of confusing a
careful reader in context, but a literal violation of the page that is supposed to be the single
notation reference.

---

## Finding 5 — The hat accent, reserved throughout for "spectral representation," is reused for "unit vector" in the Helmholtz-projector formula

**Type:** normalization / contradiction (notation)
**Severity:** minor
**Confidence:** medium

**Locations:**
- PAGE: architecture, Documentation policy: *"each code object is explicitly identified with its mathematical symbol on first mention … `helmholtz_projection` $\equiv \mathbb{P}$ … a field in spectral representation written $\hat f$."*
- PAGE: notation, Base and fiber table: *"$\hat f$ | the field $f$ in spectral representation | `to_spectral(f)`"* — the only meaning given for the hat accent anywhere on the page.
- PAGE: formalization, "Differential operators": *"$\mathbb P \to \mathrm{id} - \hat a \hat a^{\top}\ \ (\hat a = a/|a|)$"* and, two lines later, in the **same displayed equation** as the genuinely-spectral $\hat u$, $\hat g$: *"$\hat g (\mathrm{id} - \hat a\hat a^{\top}) \hat u = (\mathrm{id} - \hat a\hat a^{\top}) (\hat g \hat u) \in \mathbb C^3$"*.
- PAGE: architecture, §13 decision log (decision 42): *"The denominator is now $a \cdot a$ … making $\mathbb P = \mathrm{id} - \hat a\hat a^{\top}$ the exact orthogonal projector…"*
- Contrast — PAGE: api / DifferentialOperators, `helmholtz_projection!` docstring, describing the identical object *without* the clash: *"The spectral symbol subtracts the longitudinal part $a_i (a\cdot\hat u)/|a|^2$ from $\hat u_i$, with $a$ the derivative wavenumber … $\widehat{(\mathbb P u)}_i(k) = \Bigl(\delta_{ij} - \dfrac{a_i a_j}{|a|^2}\Bigr)  \hat u_j(k)$"* — spells out $a_ia_j/|a|^2$, never writing $\hat a$.

**Contradicts:** the Notation page's sole, explicit binding of the hat accent ("spectral
representation") is overloaded on the Formalization page and in the Architecture decision-42 entry
to also mean "unit vector" ($\hat a := a/|a|$, on $a$, which is a wavenumber component — not itself a
field with any "representation" to hat-mark). This happens inside the very equation that also uses
$\hat u$ and $\hat g$ in the document's standard spectral sense, so the same glyph carries two
meanings in one formula. The operator's own docstring (DifferentialOperators page) avoids the
ambiguity entirely by writing the ratio out.

**Description:** The underlying mathematics is correct and unaffected (this is purely notational);
"hat = unit vector" is itself a completely standard convention in general physics/vector-calculus
writing, so the clash is local to *this* document's own stricter, pervasively-applied "hat = spectral
representation" rule, not to mathematics generally.

---

## Finding 6 — Ambiguous field order behind the "67 MB field fits in cache" cache-residency claim

**Type:** clarity / possible normalization slip
**Severity:** nit
**Confidence:** low

**Location:** PAGE: performance, §2 (grid↔point transfer cost model): *"at the grids we run the field
is largely cache-resident (a $256^3$ `Float32` field is 67 MB, inside the RX 6700 XT's 96 MB Infinity
Cache), so there is little locality left to win."*

**Description:** $256^3 \times 4$ bytes $= 67$ MB matches a **scalar** field exactly; a **vector**
field (the typical velocity field a Lagrangian-tracking interpolation benchmark would use, per the
rest of this document's own running example) would be $\approx 3\times$ larger ($\approx 201$ MB),
which would *not* fit inside a 96 MB cache — undercutting the sentence's own point ("little locality
left to win"). The passage never states which tensor order the 67 MB figure describes, so this may
simply be a generic scalar-field illustration rather than a description of the actual (likely
vector-field) transfer benchmarks reported a few paragraphs later; flagged at low confidence since
the ambiguity, not a demonstrated error, is what's visible in the rendered text.
