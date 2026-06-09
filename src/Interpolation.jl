"""
    Interpolation

Lagrangian particle-tracking transfer layer: evaluating fields off-grid and depositing
per-particle quantities back onto the grid. Two operations, formal adjoints of each other.

# API

Each operation has the usual allocating / in-place (`!`) pair, the output being the operation's
codomain — a particle-value array for interpolation, a grid field for anterpolation:

  * **Interpolation** (grid → particle, *gather*): `interpolate(f, xs[, scheme])` allocates and
    returns the particle values; `interpolate!(out, f, xs[, scheme])` writes them into `out`.
    The callable `f(x)` (and its broadcast `f.(xs)`) is the ergonomic face of `interpolate`.
  * **Anterpolation** (particle → grid, *scatter*): `anterpolate(grid, xs, qs[, scheme])`
    allocates and returns the deposited field (e.g. a particle-concentration field `Σₚ β(·−xₚ)`);
    `anterpolate!(field, xs, qs[, scheme])` deposits into `field`.

The non-`!` form allocates its output; the `!` form writes into a caller-supplied destination
passed first (Julia convention) and returns it; a five-argument `α`/`β` form accumulates
(`β = 0` overwrite, `β ≠ 0` accumulate), matching the package's `mul!` / `add!` convention —
both operations are the linear-operator applications `𝓘 = W` and `𝓘* = Wᵀ` (below), and
accumulation (`β = 1`) is the common case for the anterpolation scatter. The destination differs
by operation — a particle array vs. a grid field — which is the function/measure duality below,
not an inconsistency.

`interpolate` / `anterpolate!` are the symmetric named pair (the operators `𝓘` / `𝓘*`). The one
true asymmetry is that interpolation alone has the callable `f(x)` — evaluation is pointwise
while its adjoint is not (see below). Route both directions through one shared `scheme` so they
use the same weights — which is what makes them an adjoint pair.

Method choice (the Lalescu local splines), terminology, and GPU rationale are recorded in
`docs/ARCHITECTURE.md` §10. This module is a documented scaffold; the kernels are not yet
implemented.

# Why interpolation and anterpolation are adjoint: the function–measure duality

The two operations are adjoint linear operators, `𝓘 : G → P` (interpolation) and
`𝓘* : P → G` (anterpolation), defined by `⟨𝓘 f, q⟩_P = ⟨f, 𝓘* q⟩_G`. The content of that
identity is a duality between **functions** — which you *evaluate* — and **measures** — which
you *integrate against*:

  * Pointwise, evaluation is pairing with a Dirac mass, `f(x) = ⟨δₓ, f⟩`. So interpolation
    pairs the field with one delta per particle: `(𝓘 f)ₚ = ⟨δ_xₚ, f⟩ = f(xₚ)`.
  * Its adjoint cannot be pointwise — it returns a **measure**, a sum of point masses:

        𝓘* q = Σₚ qₚ δ_xₚ ,   ⟨𝓘* q, f⟩ = ∫ f d(𝓘* q) = Σₚ qₚ f(xₚ) = ⟨q, 𝓘 f⟩.

This is the mathematical reason for the API asymmetry: you *evaluate functions* (`f(x)` returns
a value) but *accumulate measures* (`anterpolate!` adds a source density onto a field). There is
no pointwise `f(x) = q`, because evaluation's adjoint is intrinsically a distribution spread over
the grid.

Numerically the Dirac is regularized by the stencil kernel, `δ_xₚ → β(·−xₚ)` (the
partition-of-unity weights), so anterpolation deposits `𝓘* q = Σₚ qₚ β(·−xₚ)` — exactly a
regularized particle source term, a sum of mollified deltas centred on the particles (the same
construction as a condensation/deposition source `Σ_α κ(x−x_α)(…)`). Discretely, with `G = ℝᴺ`
(`N` grid nodes) and `P = ℝᴹ` (`M` particles), interpolation is the matrix `𝓘 = W`
(`Wₚₙ = βₙ(xₚ)`, size `M×N`) and anterpolation is its transpose `𝓘* = Wᵀ`.

**Conservation** then follows by pairing with the constant field:

    Σₙ (𝓘* q)ₙ = ⟨𝟙, 𝓘* q⟩ = ⟨𝓘 𝟙, q⟩ = ⟨𝟙, q⟩ = Σₚ qₚ,

using `𝓘 𝟙 = 𝟙` — the weights reproduce constants, `Σₙ Wₚₙ = 1`. Total deposited equals total
over particles; for the parcel coupling, total water mass and latent heat are conserved. This
holds **only when both directions use the same weights**, so the design fixes anterpolation as
the transpose/adjoint of whatever interpolation scheme is in use (mismatched weights inject a
spurious source — Sundaram & Collins 1996). The inner products are a modelling choice: with the
Euclidean (counting) products the adjoint is the bare transpose `Wᵀ`; with `L²`/volume-weighted
products it is `M_G⁻¹ Wᵀ M_P` (the immersed-boundary spreading/interpolation pair of Peskin),
conserving an energy pairing rather than the plain sum.
"""
module Interpolation

# Documented scaffold for the planned Lagrangian particle-tracking layer. The design
# decision — method (Lalescu local splines), terminology, and the adjointness/conservation
# rationale summarized in the module docstring — lives in docs/ARCHITECTURE.md §10. The
# interpolation/anterpolation kernels are not yet implemented.

end # module Interpolation
