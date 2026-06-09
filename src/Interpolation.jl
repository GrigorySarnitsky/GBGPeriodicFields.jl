"""
    Interpolation

Transfer between the grid sections of `Fields` and the point sections of `Points`: evaluating a
field at off-grid positions, and depositing per-point quantities back onto the grid. The two
operations are formal adjoints of each other. **The transfer kernels are not yet implemented**:
this module currently records only the design (its docstring). The planned method (the Lalescu
local splines), terminology, and GPU rationale are in `docs/ARCHITECTURE.md` §10; the point-value
data types and their fiberwise algebra live in the `Points` module.

# Planned API

  * **Interpolation** (grid to point, *gather*): `interpolate(f, xs[, scheme])` / in-place
    `interpolate!(out, f, xs[, scheme])`, plus the callable `f(x)` (and its broadcast `f.(xs)`)
    as the ergonomic face of `interpolate`.
  * **Anterpolation** (point to grid, *scatter*): `anterpolate(grid, xs, qs[, scheme])` / in-place
    `anterpolate!(field, xs, qs[, scheme])`, with a five-argument `α`/`β` form (`β = 0` overwrite,
    `β ≠ 0` accumulate, the `mul!` convention; accumulation is the common case for the scatter).

`interpolate` / `anterpolate!` are the symmetric named pair (the operators `𝓘 = W` / `𝓘* = Wᵀ`);
only interpolation also carries the pointwise callable `f(x)`, because evaluation is pointwise
while its adjoint is not. Both directions share one `scheme` (the same weights) — which is what
makes them an adjoint pair.

# Why interpolation and anterpolation are adjoint: the function–measure duality

`𝓘 : G → P` and `𝓘* : P → G` satisfy `⟨𝓘 f, q⟩_P = ⟨f, 𝓘* q⟩_G`, a duality between *functions*
(which you evaluate) and *measures* (which you integrate against):

  * evaluation is pairing with a Dirac mass, `f(x) = ⟨δₓ, f⟩`, so `(𝓘 f)ₚ = ⟨δ_{xₚ}, f⟩ = f(xₚ)`;
  * its adjoint cannot be pointwise — it returns a measure, a sum of point masses
    `𝓘* q = Σₚ qₚ δ_{xₚ}`, regularized by the stencil kernel to `Σₚ qₚ β(·−xₚ)`, a point source
    density.

Hence the API asymmetry: you *evaluate functions* (`f(x)` returns a value) but *accumulate
measures* (`anterpolate!` adds a source density onto a field); there is no pointwise `f(x) = q`.
Discretely, with `G = ℝᴺ` (`N` grid nodes) and `P = ℝᴹ` (`M` points), interpolation is the matrix
`𝓘 = W` (`Wₚₙ = βₙ(xₚ)`) and anterpolation its transpose `𝓘* = Wᵀ`. With shared partition-of-unity
weights (`𝓘 𝟙 = 𝟙`, i.e. `Σₙ Wₚₙ = 1`), anterpolation is the exact transpose of interpolation and
the total deposited quantity is conserved,

    Σₙ (𝓘* q)ₙ = ⟨𝟙, 𝓘* q⟩ = ⟨𝓘 𝟙, q⟩ = ⟨𝟙, q⟩ = Σₚ qₚ,

which is mandatory for the two-way-coupled parcel application (total water mass and latent heat
conserved). This holds **only when both directions use the same weights**, so the design fixes
anterpolation as the transpose/adjoint of whatever interpolation scheme is in use (mismatched
weights inject a spurious source — Sundaram & Collins 1996). The inner products are a modelling
choice: with the Euclidean (counting) products the adjoint is the bare transpose `Wᵀ`; with
`L²`/volume-weighted products it is `M_G⁻¹ Wᵀ M_P` (the immersed-boundary spreading/interpolation
pair of Peskin), conserving an energy pairing rather than the plain sum.
"""
module Interpolation

# Transfer kernels (interpolate / anterpolate) are not yet implemented. The point-value data
# types and their fiberwise algebra live in the `Points` module; implementation of the transfer
# begins from the design recorded above and in `docs/ARCHITECTURE.md` §10.

end # module Interpolation
