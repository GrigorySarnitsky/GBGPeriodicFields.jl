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

using StaticArrays: SVector
using ..Fields: fiber_shape


export Point,
       PointSet,
       AbstractPointValues,
       ScalarPointValues,
       VectorPointValues,
       TensorPointValues,
       point_coordinates,
       point_values,
       pointvalue_tensor_order,
       npoints


####################################
#            Positions             #
####################################

"""
    Point{T} = SVector{3, T}

A single position in the domain — a coordinate triple. `Point` is the base-space analog of
`FiberVector`: the same `SVector{3,T}` representation, a different role (a *location*,
not a field value). It is an alias, not a wrapper, so arithmetic on positions stays
StaticArrays-native; the position/value distinction is one of role, not dispatch.
"""
const Point{T} = SVector{3, T}


"""
    PointSet(coordinates::AbstractArray{T, 2}) where {T<:AbstractFloat}

A collection of `M` off-grid positions, stored structure-of-arrays in `coordinates` with shape
`(M, 3)` — point index first, coordinate last, mirroring the fiber-last field layout so each
coordinate axis is contiguous across points. Backend-generic: `coordinates` may be any
`AbstractArray` (CPU `Array`, GPU `CuArray`/`ROCArray`). Grid-free — a periodic domain wraps any
coordinate, so positions are not tied to a grid; a transfer operator takes the grid from the field.
"""
struct PointSet{T<:AbstractFloat, A<:AbstractArray{T, 2}}
  coordinates::A

  function PointSet(coordinates::A) where {T<:AbstractFloat, A<:AbstractArray{T, 2}}
    size(coordinates, 2) == 3 ||
      throw(DimensionMismatch("PointSet coordinates must have shape (M, 3); got $(size(coordinates))"))
    return new{T, A}(coordinates)
  end
end


####################################
#           Point values           #
####################################

"""
    AbstractPointValues{T<:AbstractFloat, R}

Abstract supertype for field values sampled at the `M` positions of a [`PointSet`](@ref). `T` is
the real scalar type; `R` is the tensor order (an integer value parameter). Point values are
**representation-free** — a sampled value is always a physical-space quantity, so there is no
physical/spectral distinction here, unlike the field types. Concrete subtypes:
[`ScalarPointValues`](@ref) (`R = 0`), [`VectorPointValues`](@ref) (`R = 1`),
[`TensorPointValues`](@ref) (`R ≥ 2`).
"""
abstract type AbstractPointValues{T<:AbstractFloat, R} end


"""
    ScalarPointValues(data::AbstractArray{T, 1}) where {T<:AbstractFloat}

Scalar field values at `M` points, stored in `data` with shape `(M,)`.
"""
struct ScalarPointValues{T<:AbstractFloat, A<:AbstractArray{T, 1}} <: AbstractPointValues{T, 0}
  data::A
end


"""
    VectorPointValues(data::AbstractArray{T, 2}) where {T<:AbstractFloat}

Vector field values at `M` points, stored structure-of-arrays in `data` with shape `(M, 3)`.
"""
struct VectorPointValues{T<:AbstractFloat, A<:AbstractArray{T, 2}} <: AbstractPointValues{T, 1}
  data::A

  function VectorPointValues(data::A) where {T<:AbstractFloat, A<:AbstractArray{T, 2}}
    size(data, 2) == 3 ||
      throw(DimensionMismatch("VectorPointValues data must have shape (M, 3); got $(size(data))"))
    return new{T, A}(data)
  end
end


"""
    TensorPointValues{R}(data::AbstractArray{T}) where {R, T<:AbstractFloat}
    TensorPointValues(data::AbstractArray{T}) where {T<:AbstractFloat}

Tensor field values of order `R` at `M` points, stored structure-of-arrays in `data` with shape
`(M, fiber_shape(Val(R))...)` (e.g. `(M, 3, 3)` for `R = 2`). The constructor without an explicit
`{R}` infers `R = ndims(data) - 1`.
"""
struct TensorPointValues{R, T<:AbstractFloat, A<:AbstractArray{T}} <: AbstractPointValues{T, R}
  data::A

  function TensorPointValues{R}(data::A) where {R, T<:AbstractFloat, A<:AbstractArray{T}}
    ndims(data) == R + 1 ||
      throw(DimensionMismatch("TensorPointValues{$R} data must have $(R + 1) dimensions; got $(ndims(data))"))
    size(data)[2:end] == fiber_shape(Val(R)) ||
      throw(DimensionMismatch("TensorPointValues{$R} data must have shape (M, $(fiber_shape(Val(R))...)); got $(size(data))"))
    return new{R, T, A}(data)
  end
end

TensorPointValues(data::AbstractArray{T}) where {T<:AbstractFloat} = TensorPointValues{ndims(data) - 1}(data)


####################################
#            Accessors             #
####################################

"""
    point_coordinates(point_set::PointSet)

Return the `(M, 3)` array of point coordinates.
"""
function point_coordinates end
point_coordinates(point_set::PointSet) = point_set.coordinates


"""
    point_values(sampled_values::AbstractPointValues)

Return the underlying array of sampled values: structure-of-arrays with shape `(M,)` / `(M, 3)` /
`(M, 3, 3)` for tensor order `0` / `1` / `2`.
"""
function point_values end
point_values(sampled_values::AbstractPointValues) = sampled_values.data


"""
    pointvalue_tensor_order(sampled_values::AbstractPointValues{T, R}) where {T<:AbstractFloat, R}

Return the tensor order `R` of the sampled values.
"""
function pointvalue_tensor_order end
pointvalue_tensor_order(::AbstractPointValues{T, R}) where {T<:AbstractFloat, R} = R


"""
    npoints(point_set::PointSet)
    npoints(sampled_values::AbstractPointValues)

Return the number `M` of points — the leading-axis length of the coordinate or value array.
"""
function npoints end
npoints(point_set::PointSet) = size(point_set.coordinates, 1)
npoints(sampled_values::AbstractPointValues) = size(sampled_values.data, 1)


####################################
#          Compatibility           #
####################################

"""
    _check_npoints_match(a, b)

Throw a `DimensionMismatch` unless `a` and `b` — each a [`PointSet`](@ref) or an
[`AbstractPointValues`](@ref) — cover the same number of points `M`; otherwise return `nothing`.
Internal helper for the transfer operators (interpolation / anterpolation).
"""
function _check_npoints_match(a, b)
  npoints(a) == npoints(b) ||
    throw(DimensionMismatch("point counts differ: $(npoints(a)) and $(npoints(b))"))
  return nothing
end


# The transfer kernels — interpolation (`f(x)` / `interpolate` / `interpolate!`) and its adjoint
# anterpolation (`anterpolate` / `anterpolate!`) — are not yet implemented; see the module
# docstring and docs/ARCHITECTURE.md §10. These data types and their compatibility check come first.

end # module Interpolation
