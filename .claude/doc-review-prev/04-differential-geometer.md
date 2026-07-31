# Panel review — the Pure Mathematician (differential geometry / measure theory / functional analysis)

Hat: **differential-geometer**. Scope: the intrinsic / structural mathematics — base vs fiber,
vertical vs horizontal, a section vs its representation, the honest domain/codomain of every map,
the measure taxonomy, and the adjoint / self-adjoint / idempotent / duality claims.

## Overall assessment

The package's structural mathematics is, to my eye, in **excellent** shape and better than most
research code I audit. The things my hat exists to catch are handled correctly and often
explicitly:

- The **fiber `V` vs tensor order `R`** distinction is clean everywhere (`formalization`
  `V := (\mathbb R^3)^{\otimes R}`; `FiberSections`/`Fields`/`Points` all say "`R` the tensor order,
  an integer value parameter"). The old "the fiber is the tensor order" category error stays fixed.
- The **section space is never flattened**: `formalization` explicitly warns
  "$\Gamma_P$ is $\mathbb R^{3M}$ only when the sampled field is a vector … in general it is
  $\mathbb R^M \otimes V$, just as the grid value space is not $\mathbb R^{3N}$", and keeps
  `W := W_b \otimes \mathrm{id}_V` with the fiber factor explicit.
- The **two all-ones vectors** are kept distinct (`\mathbf 1_N \in \mathbb R^N`, `\mathbf 1_M \in \mathbb R^M`).
- The **N/M measure-adjoint** is handled impeccably: `formalization` states and *derives* that the
  bare `⟨Wf,q⟩ = ⟨f,Wᵀq⟩` "is false unless N = M — the two sides differ by N/M", and gives the exact
  L²-adjoint `\iota_* = (N/M)W^\top`. The pullback/pushforward square, Parseval (correct `1/N²`, not
  claimed unitary), self-adjoint curl/Δ/ℙ, idempotent ℙ, and the Wiener–Khinchin normalizations
  (`C(r) = 𝓕⁻¹(|f̂|²)/N`, `C_fg(r) = 𝓕⁻¹(f̂̄ ĝ)/N`) all expand correctly against the stated
  conventions.

No blocker or major issues from my hat. The findings below are precision/consistency slips —
mostly notation and definiteness wording, plus one substantive reproduction-degree slip.

---

## Finding 1 — `\Pi_m` should be `\Pi_d`: smoothness parameter substituted for the reproduction degree

- **type:** math
- **severity:** minor
- **confidence:** high

**Locations**
- `architecture`, §10 (interpolation), the "Intrinsically the pair is a pullback–pushforward" paragraph:
  "(Strictly $W$ is $\iota^{*}$ after a reconstruction — the spline or band-limited spectral
  interpolant lifting grid samples to a section over $\Omega$ — **which the reproduction identity above
  shows is exact on $\Pi_m$**.)"

**Contradicts**
- `architecture`, §10, eleven lines earlier: "$\phi$ for any polynomial in **$\Pi_d$** (the polynomials
  up to the scheme's **reproduction degree $d$**)", and the reproduction identity itself
  "$W(\operatorname{sample}_{\text{grid}} \phi) = \operatorname{eval}_{\text{pts}} \phi \quad (\phi \in \Pi_d)$".
- `architecture`, §10: "The smooth scheme reproduces polynomials to degree **$\min(2m+1, 2n)$**".
- `api / Interpolation`, `CatmullRom`: the cubic `n=1, m=1` "reproduces the Catmull–Rom spline (and
  **quadratic** polynomials exactly)".
- Axis of disagreement: the **smoothness parameter `m`** vs the **derived reproduction degree
  `d = min(2m+1, 2n)`**.

**Description.** The reconstruction note says interpolation is "exact on $\Pi_m$", but the "reproduction
identity above" it cites was stated for $\Pi_d$ with $d$ the reproduction degree, and everywhere else
the degree is $\min(2m+1,2n)$, *not* $m$. This is a genuine (not cosmetic) slip of exactly the kind my
hat hunts — an **operator's parameter (`m`, smoothness) written where its derived quantity (`d`,
reproduction degree) is meant**. It also mis-states the numbers: for the default Catmull–Rom
(`n=1, m=1`) the true reproduction degree is $\min(3,2)=2$ (quadratic, as the `CatmullRom` docstring
says), whereas "$\Pi_m = \Pi_1$" claims only linear reproduction — understating the scheme by a full
polynomial degree. Fix: `\Pi_m` → `\Pi_d`.

---

## Finding 2 — "negative-definite Laplacian" contradicts the (correct) "negative-semidefinite" used elsewhere

- **type:** math
- **severity:** minor
- **confidence:** high

**Locations**
- `formalization`, Differential operators, the "Backs Architecture §4" line: "Checked by
  `test/differentialoperators.jl` (…) and `test/adjointness.jl` (self-adjointness, idempotent
  projection, **negative-definite Laplacian**)."

**Contradicts**
- `formalization`, same section, the display two lines above: "$\langle \Delta\phi,\phi\rangle =
  -\lVert\nabla\phi\rVert^2 \le 0$" (i.e. negative **semi**definite: it is $\le 0$, and $=0$ on the
  constants).
- `architecture`, §13 decision log (the test-buildout entry): "**negative-semidefinite** Laplacian —
  **negative-definite on the zero-mean subspace, its kernel being the constant mode**".
- `testing`, §1 and §7: "a self-adjoint **negative-semidefinite** Laplacian" / "a self-adjoint
  **negative-semidefinite** Laplacian (with the dissipation identity)".
- Axis: **negative-definite vs negative-semidefinite**.

**Description.** The Laplacian on the periodic box is negative **semi**definite — its kernel is the
constant (zero) mode, so it is negative *definite* only on the zero-mean subspace. Three other
locations (including the formalization's own `≤ 0` display) state this precisely; only this one test
description drops to the false "negative-definite Laplacian". A pure mathematician reads
"negative-definite" as a claim that $\langle\Delta\phi,\phi\rangle<0$ for all $\phi\ne 0$, which is
false for the constants. Fix: "negative-**semi**definite Laplacian".

---

## Finding 3 — the glyph `⟨·,·⟩` is globally bound to the *normalized* inner, but decision 19 reuses it for the *unnormalized counting* pairing

- **type:** normalization
- **severity:** minor
- **confidence:** medium

**Locations**
- `notation`, Operators table: "$\langle\cdot,\cdot\rangle$ | the **normalized** $L^2$ inner product | inner".
- `architecture`, §13 decision 19 (measure taxonomy), the transfer-adjoint paragraph: "the adjointness
  **$\langle Wf, q\rangle = \langle f, W^\top q\rangle$** and conservation $\sum_g (W^\top q)_g =
  \sum_p q_p$ **hold in the counting/transpose pairing**".
- (supporting) `notation`, Base-and-fiber table: "$W$, $W^{\top}$ | interpolation (gather) and its
  **adjoint** anterpolation (scatter) | interpolate, anterpolate" — calls the plain transpose $W^\top$
  simply "adjoint", whereas the true L²-adjoint is $(N/M)W^\top$.

**Contradicts**
- `formalization`, Interpolation/anterpolation: "So the **bare $\langle Wf, q\rangle_{\text{pts}} =
  \langle f, W^{\top}q\rangle_{\text{grid}}$ is false unless $N = M$** — the two sides differ by $N/M$.
  **This is the slip the formalization catches**: it type-checks, but the expansion does not match."
- Axis: **normalized inner product (`inner`, carries `1/N`, `1/M`) vs the unnormalized counting
  pairing (plain sums)** — the same glyph `⟨·,·⟩` for both.

**Description.** The notation page fixes `⟨·,·⟩` as *the normalized L² inner product*. Under that
binding, the factor-free `⟨Wf,q⟩ = ⟨f,Wᵀq⟩` written in decision 19 is precisely the identity the
formalization page singles out as **false** (off by `N/M`). Decision 19 does disambiguate in words
("hold in the counting/transpose pairing"), so it is not stating a falsehood — but it is silently
re-loading the same bare glyph with a *second* meaning (the unnormalized pairing), in a §13 entry that
is "self-contained by design" and read on its own. This is the one-glyph-two-meanings hazard
(cf. the `CLAUDE.md` "one notation per concept — and one concept per notation" rule): a reader who
trusts the notation table and reads decision 19 alone will take the normalized identity to hold
factor-free. `§10` and `formalization` avoid this by subscripting (`⟨·,·⟩_pts`, `⟨·,·⟩_grid`) and
carrying the explicit `M`/`N`; decision 19 (and the "adjoint anterpolation" gloss) are where the bare
glyph leaks. Advisory: either subscript decision 19's pairing (e.g. `⟨·,·⟩_count`) or spell it as
`Σ_p (Wf)_p·q_p = Σ_g f_g·(Wᵀq)_g`, and consider "adjoint (transpose)" for `Wᵀ` in the notation table.

---

## Finding 4 — decision 19's "reproduction order = number of matched moments" is an off-by-one relative of the "reproduction degree" used everywhere else

- **type:** math
- **severity:** nit
- **confidence:** low

**Locations**
- `architecture`, §13 decision 19: "**Reproduction order = number of matched moments** of the kernel
  measure (0th moment `=1` = partition of unity = constants reproduced)."

**Contradicts**
- `architecture`, §10: "reproduction **degree** $d$"; "reproduces polynomials **to degree**
  $\min(2m+1,2n)$".
- `api / Interpolation`: "reproduces polynomials up **to degree** $\min(2n{+}1,2n)$…" / "up **to degree**
  $2n{+}1$".
- Axis: reproduction **"order" (= number of matched moments, so degree + 1)** vs reproduction
  **"degree"**.

**Description.** Decision 19 is internally self-consistent (1 matched moment → constants, i.e.
degree 0), but it introduces a *second* reproduction counter — "order" = number of matched moments =
`degree + 1` — under a word ("order") that collides with the "reproduction degree" every other surface
uses. For Catmull–Rom the two read as "order 3" (moments 0,1,2) vs "degree 2", for the *same* scheme.
This is a low-severity terminological wrinkle, not an error; flagging it only because the design docs
otherwise keep a single reproduction convention. Advisory: say "number of matched moments = degree + 1"
explicitly, or reuse "degree".

---

## Finding 5 — method-count drift: 206 vs 202/198 (field) and 122 vs 118 (point-value) [cross-cutting; likely owned by the architecture/consistency hats]

- **type:** contradiction
- **severity:** minor
- **confidence:** medium

**Locations**
- `architecture`, §2 (representation-validity), one paragraph: opens "**The 206-method** public surface
  of `FieldAlgebra` …", then traces "M2 (98 methods …) and then M3 (…), bringing **the total to 198**;
  the later trace `tr`/`tr!` addition brings it to **202**, all parity-checked at runtime".
- `architecture`, §6: "The full M2+M3 baseline is **206** public methods (… `combine!` 2, `tr` 2,
  `det`/`det!` 1 each)"; decision 27: "grows to **206** field methods … and **122** point-value methods".

**Contradicts**
- Within §2 itself: the paragraph is headed "206-method public surface" but its own historical
  progression ends at **202**, never reaching 206 (the `combine!`/`det`/`det!` steps that take
  202 → 206 are omitted).
- `architecture`, §13 decision-log entries (decisions ~20–23) still say "**198**-method and
  point-value **118**-method parity baselines are unchanged", while §6, decision 27, `testing`, and
  §10 say **206 / 122**.
- Axis: current method counts **206 / 122** vs the historical **198–202 / 118**.

**Description.** The append-only decision log legitimately snapshots the counts at each entry's time
(198/118 → 202/… → 206/122), so the log drift is arguably by-design. But the §2 body paragraph is *not*
a log entry, and it contradicts itself in one breath — opening "206-method surface" then walking a
history that stops at 202. Not a structural-math issue (out of my lane), recorded here only because the
panel asked for relentless internal-consistency checking; I expect the architecture/consistency hats
own the resolution. Fix: reconcile §2's opening "206" with its progression (add the combine!/det steps,
or state 202 as the pre-decision-27 figure).
