# Doc review — Pure Mathematician / Differential Geometer hat

Audit of the RENDERED documentation of GBGPeriodicFields, focused on the intrinsic /
structural mathematics: base vs fiber, vertical vs horizontal, section vs representation,
domains/codomains of maps (especially their fiber factor), the measure taxonomy, and the
adjoint / self-adjoint / idempotence / duality claims — verified between the *right spaces*,
not merely as scalar formulas.

Overall the structural apparatus is unusually careful and mostly correct. The fiber-bundle
model (§2), the pullback–pushforward picture of the transfer (§10), the measure taxonomy
(decision 19), the Parseval/half-spectrum normalizations, the Helmholtz idempotence and
Nyquist handling (decision 42), and — notably — the formalization page's explicit refusal to
flatten the fiber (`Γ_P = ℝ^M ⊗ V`, not `ℝ^{3M}`; two distinct all-ones `𝟙_N`/`𝟙_M`) all
check out. The findings below are the residual imprecisions.

---

## Finding 1 — "L²-adjoint pair" mislabels the shipped transpose pair (the very slip the formalization page exists to catch)

- **type:** contradiction / normalization
- **severity:** minor
- **confidence:** medium

**Locations (the loose label):**
- Home page, Main-components bullet: *"interpolation (gather $W$) and anterpolation (scatter $W^\top$) as an **L²-adjoint pair**"* (PAGE: Home, line 40).
- API overview bullet: *"interpolation (gather) and anterpolation (scatter) as an **L²-adjoint pair**"* (PAGE: api, line 123).
- Architecture decision 23: *"unified under a new supertype `AbstractTransferScheme`, sharing the `interpolate`/`anterpolate` verbs and the **L²-adjoint contract**"* (PAGE: architecture, decision 23).
- Interpolation module docstring: *"Anterpolation (`anterpolate`) is the scatter $W^\top$, **the adjoint (transpose) of $W$**"* and AbstractTransferScheme: *"the adjoint pair `interpolate` $= W$ … / `anterpolate` $= W^\top$ (its transpose …). Same verbs, **one adjointness contract**"* (PAGE: api / Interpolation).

**Contradicts (the careful statement):**
- Formalization, Interpolation/anterpolation section: *"So the bare $\langle Wf, q\rangle_{\text{pts}} = \langle f, W^{\top}q\rangle_{\text{grid}}$ is **false** unless $N = M$ — the two sides differ by $N/M$. This is the slip the formalization catches: it type-checks, but the expansion does not match. The clean adjunction uses the measure-adjoint $\iota_* := (N/M) W^{\top}$"* (PAGE: formalization).
- Architecture §10: *"for the uniform measures $\iota_{*} = (N/M) W^{\top}$, the scalar rescaling **that turns the implemented transpose $W^{\top}$ into the exact L²-adjoint**"* — i.e. the exact L²-adjoint is $(N/M)W^\top$, **not** the shipped $W^\top = $ `anterpolate` (PAGE: architecture, §10).
- Architecture decision 19: *"the adjointness … hold in the **counting/transpose pairing** … The measure-weighted **L² adjoint** … is $(N/M) W^{\top}$"* (PAGE: architecture, decision 19).

**Axis of disagreement:** *adjoint under which inner product, and the measure (N/M) factor.*
The shipped pair is `interpolate` $= W$ and `anterpolate` $= W^\top$ (the partition-of-unity
transpose). Under the package's own normalized `inner` — the $\langle\cdot,\cdot\rangle_{\text{pts}}$
/ $\langle\cdot,\cdot\rangle_{\text{grid}}$ that every summary invokes — $(W, W^\top)$ is
**not** an adjoint pair: the true L²-adjoint of $W$ is $\iota_* = (N/M)W^\top$, a *different*
operator from `anterpolate` whenever $N \ne M$ (the generic case). $(W, W^\top)$ is an adjoint
pair only in the *counting* (unnormalized) pairing $\sum_p a_p\!\cdot\! b_p$. Calling the
shipped pair an "L²-adjoint pair/contract" — naming L² specifically — asserts exactly the
equality the formalization page flags as "false". Every actual *equation* in the docs carries
the $M$/$N$ factors correctly ($M\langle Wf,q\rangle = N\langle f,W^\top q\rangle$); only the
prose *label* on the summary surfaces overclaims. (The Interpolation module's
"adjoint (transpose)" is the milder cousin — it at least glosses "transpose" and then shows
the $M$/$N$ relation.)

**resolution_hint:** On Home / api / decision 23, say "a conserving adjoint pair (exact
transpose under the counting pairing; the measure-consistent L²-adjoint is the trivial
$(N/M)$-rescaling)" or simply "a formal adjoint pair" (the wording architecture §10 line 313
already uses), reserving "L²-adjoint" for $(N/M)W^\top$ as the careful pages do.

---

## Finding 2 — The horizontal / differential-operator family is characterized as "the covariant derivative, order one", but the family includes a nonlocal order −2 operator and an order-0 projection

- **type:** math (category / order imprecision)
- **severity:** minor
- **confidence:** medium

**Location:** Architecture §2, the vertical/horizontal parenthetical: *"the fiberwise algebra
is order-zero and fiber-preserving, **the differential operators are the connection's
covariant derivative, order one.**"* (PAGE: architecture, §2).

**Why it's imprecise:** The horizontal family, as realized in `DifferentialOperators` and
listed in the §2 architecture map (*"`gradient`, `divergence`, `curl`, `symmetric_gradient`,
`laplacian`, …"*, line 212), is *not* uniformly "the covariant derivative, order one":
- `laplacian` $\equiv \Delta$ is order **two** (the contracted second covariant derivative), not one.
- `inverse_laplacian` $\equiv \Delta^{-1}$ is **not a differential operator at all** — it is a
  nonlocal pseudodifferential operator of order **−2**. The package's own docstring says so:
  *"As the inverse of a differential operator, $\Delta^{-1}$ is nonlocal: unlike the Laplacian
  it has no local partial-derivative formula, and the value at any point depends on the whole
  field."* (PAGE: api / DifferentialOperators, `inverse_laplacian!`).
- `helmholtz_projection` $\equiv \mathbb P$ is a bounded **order-0** orthogonal projection
  (symbol $\mathrm{id} - \hat a\hat a^\top \in L^\infty$; decision 42 makes it exactly
  idempotent), not a derivative.

Only `gradient` (and the first-order `divergence`/`curl`) are literally the covariant
derivative. Lumping the whole family as "the covariant derivative, order one" conflates the
generator (order-1 $\nabla$) with the polynomial/rational/pseudodifferential *functions* of it
that make up the family — the kind of operator-vs-parameter/order slip this hat watches for.
The "applied here by analogy" framing softens it, but a structural reader will trip on
$\Delta^{-1}$ and $\mathbb P$ being called "the covariant derivative, order one".

**resolution_hint:** e.g. "the differential operators are built from the connection's covariant
derivative (order one) — its contraction $\Delta$, its inverse $\Delta^{-1}$, and the projector
$\mathbb P$ formed from it" — keep the generator order-one, don't ascribe order one to the
whole family.

---

## Finding 3 — Formalization reuses `W` for a generic fiber-map codomain, colliding with `W` = the interpolation gather operator on the same page and package-wide

- **type:** clarity (one-concept-one-notation)
- **severity:** nit
- **confidence:** medium-low

**Location:** Formalization, mapped-forms statement: *"Given a map $\varphi : V \to W$ into
any space **$W$** carrying the reducing operation, the mapped reductions are the bare ones
applied to $\varphi \circ f$"* (PAGE: formalization, Reductions section).

**Collides with:**
- Formalization, Interpolation section, two sections later on the *same page*:
  *"$W := W_b \otimes \mathrm{id}_V : \Gamma_G \to \Gamma_P$"* (PAGE: formalization).
- Notation page binding: *"$W$, $W^{\top}$ | interpolation (gather) and its adjoint
  anterpolation (scatter) | interpolate, anterpolate"* (PAGE: notation).
- Architecture code↔symbol table: *"`interpolate`/`anterpolate` $\equiv W$/$W^\top$"* (PAGE:
  architecture, §2).

`W` is one of the package's most load-bearing bound symbols (the interpolation operator).
Reusing it for a throwaway codomain vector space in the mapped-reduction statement is a mild
"one glyph, two meanings" collision on a single page. Different sections give some cover, and
"$\varphi : V \to W$" is a standard idiom, so this is only a nit — but it is exactly the class
the "one concept per notation" rule targets, and the cleaner choice avoids `W` here.

**resolution_hint:** Name the codomain something free, e.g. `$\varphi : V \to U$` (or "a space
$S$"), since the reducing operation only needs a vector space / ordered set, not the letter `W`.

---

## Finding 4 — "Self-adjoint curl" is asserted and tested but has no typed entry in the Formalization differential-operators section

- **type:** other (formalization coverage gap)
- **severity:** minor
- **confidence:** medium-low

**Asserted (as a tested structural identity):**
- Testing philosophy: *"the adjoint relations (divergence as the negative gradient adjoint,
  **self-adjoint curl**, a self-adjoint negative-semidefinite Laplacian, an exactly idempotent
  self-adjoint Helmholtz projection — decision 42)"* (PAGE: testing, §1).
- Testing coverage: *"the operator adjoint/structural identities … — divergence as the negative
  gradient adjoint, **self-adjoint curl**, a self-adjoint negative-semidefinite Laplacian …"*
  (PAGE: testing, §7).
- Architecture decision-log: *"($\nabla\cdot = -\nabla^\top$, **self-adjoint curl**,
  negative-semidefinite Laplacian …)"* (PAGE: architecture, §13).

**Missing from:** Formalization, differential-operators section — which types the identities
$\nabla\cdot(\nabla\times u)=0$, $\nabla\times(\nabla\phi)=0$, $\mathbb P^2=\mathbb P$,
$\nabla\cdot(\mathbb P u)=0$, the dissipation identity, and even parenthetically
*"($\mathbb P$ and $\Delta$ are self-adjoint — their multipliers … are real symmetric.)"* —
but **not** the self-adjointness of curl (nor, explicitly, divergence = −gradient-adjoint,
though the latter is implicit in the dissipation identity) (PAGE: formalization).

**Why it's a gap:** The formalization page states its own contract — *"a statement here with no
test is a coverage gap to close"* — and the converse holds by the CLAUDE-level rule that a
nontrivial claim with no typed entry is a coverage gap. Curl's self-adjointness is nontrivial
(it rests on the symbol $\mathrm i k\times$ being Hermitian: $(\mathrm i\varepsilon_{ijk}k_j)$
equals $\overline{(\mathrm i\varepsilon_{kji}k_j)}$ because $\varepsilon_{kji}=-\varepsilon_{ijk}$
— true, but worth typing), it is on the same `test/adjointness.jl` list as $\mathbb P$ and
$\Delta$, and the formalization conspicuously types 2 of the 3 self-adjoint operators while
dropping curl. Adding a one-line typed entry (symbol Hermitian ⇒ operator self-adjoint) closes
it.

**resolution_hint:** Extend the parenthetical to "($\nabla\times$, $\mathbb P$, and $\Delta$
are self-adjoint — their symbols $\mathrm i k\times$, $\mathrm{id}-\hat a\hat a^\top$, $-|k|^2$
are Hermitian)".

---

## Finding 5 — Stale references to the retired alias-guard mechanism (contradicting the "guards retired" design)

- **type:** contradiction (currency)
- **severity:** minor
- **confidence:** medium

**Locations (stale "guard" claims, presented as current):**
- HIST_CPU example, `random_solenoidal`: *"`helmholtz_projection!(uh, uh, m)  # make
  solenoidal (**alias-guarded**)`"* (PAGE: examples / hist_cpu). This is an inline code comment
  presenting a guard as current fact.
- Points internal-API intro: *"documented for contributors extending the package — the section
  interface the `FieldAlgebra` builders reuse, the allocator, the broadcast style, and **the
  alias guard.**"* (PAGE: api / Points) — but no alias-guard function is actually listed among
  the Points internals.

**Contradicts:**
- Architecture §7: *"The former guard family (`_guard_noalias!` and its point-value twin) …
  **is retired** — decision 39 removed its last callers."* (PAGE: architecture, §7).
- `helmholtz_projection!` docstring: *"The `destination` may alias `field` at no cost: the
  projection is computed in a single pass … so the aliased call **needs no temporary**."*
  (PAGE: api / DifferentialOperators).
- Testing coverage: *"the **guard-free** aliased `helmholtz_projection!` (bitwise-equal to
  non-aliased; decision 32)"* (PAGE: testing, §7).
- The sibling call in the same example, line 3881: *"`helmholtz_projection!(Nh, ws.Nt, m)  #
  … DISTINCT dest ⇒ no-alias path (no allocation)`"* — already frames aliasing without a guard.

**Axis of disagreement:** *does the aliased `helmholtz_projection!` run through a guard.* Per
decision 32/42 it is alias-safe by construction (guard-free); the example comment
"(alias-guarded)" and the Points intro's "the alias guard" describe a mechanism that no longer
exists. (Note: the decision-24 and decision-log historical entries that mention "alias-guard
coverage" / "guard temporary upstream" are chronological and self-annotate the later retirement
— those are fine as history; the two above present the guard as present-tense fact.)

**resolution_hint:** In the example comment write "(alias-safe, coefficientwise)" to match the
sibling `convolve!`/`helmholtz` comments; drop "the alias guard" from the Points internal-API
intro (or replace with what is actually listed).

---

## Finding 6 — Notation-table entry for the wavenumber magnitude is garbled by a table-delimiter `|` (breaks the binding); plus a stray doubled-backtick

- **type:** typesetting / format
- **severity:** nit
- **confidence:** high

**Locations:**
- Notation page, Base-and-fiber table, the `$k$` row renders as:
  *"$k$ | a wavenumber vector ($k_a$ is its $a$-th component, `` | k"* (PAGE: notation).
  The intended magnitude notation (a $|k|$ inside the cell) has been eaten by GFM's column
  `|` delimiter — the exact "`|` inside a table cell is a column separator" hazard the house
  rules warn about — leaving a stray empty `` `` `` code span and a broken cell. The effect is
  that the notation page's *binding for the wavenumber magnitude $|k|$* — a symbol used
  pervasively ($|k|^2$, shells, `squared_wavenumber_field`) — is incomplete/mangled in the one
  place meant to define it (a self-containedness defect for the notation reference).
- Reductions page, `maximum` docstring: *"The materializing route to the same supremum is
  `lpnorm``(f, Inf)`."* (PAGE: api / Reductions) — doubled backticks split "`lpnorm(f, Inf)`"
  into two adjacent code spans, rendering as `lpnorm`​`(f, Inf)`.

**resolution_hint:** In the notation cell, express the magnitude as LaTeX outside any `|`
(e.g. "its magnitude $\lVert k\rVert$", or restructure so no `|` sits in the cell); fix the
doubled backtick to a single `lpnorm(f, Inf)` span. (Format-hat territory, but the notation-table
one degrades a notation *binding*, which touches this hat's self-containedness concern.)

---

## Verified clean (structural spot-checks that hold)

For the record, these load-bearing structural claims were expanded and check out:
- The pullback–pushforward adjunction $\langle\iota^* f, q\rangle_{\text{pts}} = \langle f,
  \iota_* q\rangle_{\text{grid}}$ with $\iota_* = (N/M)W^\top$ (architecture §10) — consistent
  with the formalization's $M\langle Wf,q\rangle = N\langle f,W^\top q\rangle$; opposite-variance
  (function pullback vs measure pushforward) stated correctly.
- The fiber is never flattened: $\Gamma_G = \mathbb R^N\otimes V \cong V^N$, $\Gamma_P =
  \mathbb R^M\otimes V$ (explicitly "not $\mathbb R^{3N}$/$\mathbb R^{3M}$" except for vectors);
  $W = W_b\otimes\mathrm{id}_V$ with two distinct all-ones $\mathbf 1_N$, $\mathbf 1_M$ — the
  past flatten/𝟙-conflation error is fixed.
- Parseval: the $1/N^2$ factor and the rfft half-spectrum double-count-minus-self-conjugate-
  planes correction ($2\sum_{k_x\ge0} - \sum_{k_x=0} - \sum_{k_x=N_x/2}$) are correct.
- Helmholtz $\mathbb P = \mathrm{id}-\hat a\hat a^\top$: idempotent, self-adjoint, and
  $\nabla\cdot(\mathbb P u)=0$ unconditional (built entirely from the derivative family $a$;
  decision 42) — the physical-space $u - \nabla\Delta^{-1}(\nabla\cdot u)$ identity correctly
  scoped "exact on the resolved band" (it mixes the two multiplier families).
- Inverse-Laplacian compatibility ($\int f = 0$, Fredholm) and mean-free fixing stated correctly.
- The measure taxonomy (base-quadrature / multiplier / transfer-kernel / FDF) is coherent;
  Bochner (positive kernel ⟺ positive-definite symbol) and the $L^\infty$-multiplier scope are
  used correctly; the transfer kernel is honestly a *signed* unit-mass measure for the
  higher-order splines.
- weighted_inner equals the naive $\langle w\star f, w\star g\rangle$ iff $w^2=w$ — correct.
- Wiener–Khinchin normalization $\mathcal F C = |\hat f|^2/N$, $C(0)=\mathrm{inner}$ — correct.
