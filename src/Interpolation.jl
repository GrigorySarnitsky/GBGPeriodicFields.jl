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
`docs/ARCHITECTURE.md` §10.

The **data types** above and their **full fiberwise algebra** — the fields' physical surface
(`+`, scaling, `dot`, `cross`, `mul!`, `transpose`, `norm`, `sym`/`skew`/`dev`, … with
storage-wise broadcasting), generated from the same FieldAlgebra builders — are implemented and
tested. The **transfer kernels** (`f(x)` / `interpolate` / `anterpolate!`) are the remaining
piece and are not yet implemented.

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
using ..FiberSections: AbstractFiberSection
using ..Fields: fiber_shape, _assign!, @_assign!, FiberVector, FiberTensor2
using ..FieldAlgebra: _add_values, _subtract_values,
                      _scalar_kernel_body, _vector_kernel_body, _tensor_kernel_body,
                      _sum_terms, _vector_component, _tensor_component, _product,
                      _dot_vector_rhs, _dot_tensor_rhs, _cross_formula,
                      _tensor_vector_formula, _vector_tensor_formula, _tensor_tensor_formula,
                      _transpose_formula
import Base: +, -, *, /
import LinearAlgebra: dot, cross, mul!, transpose, transpose!, norm
import ..Fields: field_data, _vector_component_data, _tensor2_component_data  # extended on PointValues
import ..FieldAlgebra: add!, subtract!, multiply!, divide!, dot!, cross!,       # extended on PointValues
                       norm!, sym, sym!, skew, skew!, dev, dev!


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
abstract type AbstractPointValues{T<:AbstractFloat, R} <: AbstractFiberSection{T, R} end


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



####################################
#   Section interface (codegen reuse)
####################################
#
# PointValues implement the minimal "fiber-section" interface the FieldAlgebra kernel-body
# builders depend on — storage via `field_data`, component views via `_vector_component_data` /
# `_tensor2_component_data` — so those builders generate point-value algebra unchanged. The
# component-view helpers are rank-generic (they index by `ndims(field_data(...))`), so the field
# bodies (3 spatial axes) and point bodies (1 point axis) share one definition. Extending these
# Fields generics on our own value types is not piracy.

field_data(values::AbstractPointValues) = point_values(values)

_vector_component_data(values::VectorPointValues, component) =
  selectdim(field_data(values), ndims(field_data(values)), component)

function _tensor2_component_data(values::TensorPointValues{2}, first_index, second_index)
  data = field_data(values)
  return selectdim(selectdim(data, ndims(data) - 1, first_index), ndims(data) - 1, second_index)
end


"""
    pointvalue_shape(number_of_points, ::Val{R}) where {R}

Storage shape `(M, fiber_shape(Val(R))...)` of point values of tensor order `R` at `M` points.
"""
pointvalue_shape(number_of_points::Integer, ::Val{R}) where {R} = (number_of_points, fiber_shape(Val(R))...)


"""
    similar_pointvalues(reference::AbstractPointValues, data)
    similar_pointvalues(reference::AbstractPointValues, ::Val{R}) where {R}

Allocate point values like `reference`. The `data` form wraps a supplied array in a `PointValues`
type of the same tensor order as `reference`; the `Val{R}` form allocates a fresh `(M, fiber…)`
array of order `R` on `reference`'s backend (via `similar`) and wraps it. Used by the broadcast
machinery and the allocating algebra wrappers.
"""
function similar_pointvalues end

similar_pointvalues(::ScalarPointValues, data::AbstractArray) = ScalarPointValues(data)
similar_pointvalues(::VectorPointValues, data::AbstractArray) = VectorPointValues(data)
similar_pointvalues(::TensorPointValues{R}, data::AbstractArray) where {R} = TensorPointValues{R}(data)

similar_pointvalues(reference::AbstractPointValues{T}, ::Val{0}) where {T<:AbstractFloat} =
  ScalarPointValues(similar(field_data(reference), T, pointvalue_shape(npoints(reference), Val(0))))
similar_pointvalues(reference::AbstractPointValues{T}, ::Val{1}) where {T<:AbstractFloat} =
  VectorPointValues(similar(field_data(reference), T, pointvalue_shape(npoints(reference), Val(1))))
similar_pointvalues(reference::AbstractPointValues{T}, ::Val{R}) where {T<:AbstractFloat, R} =
  TensorPointValues{R}(similar(field_data(reference), T, pointvalue_shape(npoints(reference), Val(R))))



####################################
#      Storage-wise broadcasting    #
####################################
#
# Point values broadcast storage-wise, like fields: a `PointValues` stands for its data array in
# a broadcast, and the style materializes the result back into a `PointValues` of the same order.
# `copyto!` routes through the shared `_assign!` (threaded on CPU, GPU-safe materialize! fallback).
# Representation-free, so a single style suffices (no physical/spectral split, no mixing rule).

"""
    PointValuesBroadcastStyle{N}

Broadcast style for point values (`N = 1 + tensor_order`: `(M,)` / `(M,3)` / `(M,3,3)`). A
`PointValues` stands for its storage array inside a broadcast; the style materializes the result
back into a `PointValues`.
"""
struct PointValuesBroadcastStyle{N} <: Base.Broadcast.AbstractArrayStyle{N} end

(::Type{<:PointValuesBroadcastStyle})(::Val{N}) where {N} = PointValuesBroadcastStyle{N}()

Base.BroadcastStyle(::Type{<:AbstractPointValues{T, R}}) where {T<:AbstractFloat, R} = PointValuesBroadcastStyle{1 + R}()
Base.BroadcastStyle(::PointValuesBroadcastStyle{M}, ::PointValuesBroadcastStyle{N}) where {M, N} = PointValuesBroadcastStyle{max(M, N)}()

Base.broadcastable(values::AbstractPointValues) = values

Base.axes(values::AbstractPointValues) = axes(field_data(values))
Base.size(values::AbstractPointValues) = size(field_data(values))
Base.ndims(::Type{<:AbstractPointValues{T, R}}) where {T<:AbstractFloat, R} = 1 + R
Base.ndims(values::AbstractPointValues) = ndims(field_data(values))
Base.eltype(::Type{<:AbstractPointValues{T, R}}) where {T<:AbstractFloat, R} = T
Base.eltype(values::AbstractPointValues) = eltype(field_data(values))


"""
    _first_pointvalues(x)

Return the first `AbstractPointValues` found in `x` (a value, a `Broadcasted` tree, or an argument
tuple), or `nothing`. Out-of-place broadcasting uses it to seed the allocated result.
"""
_first_pointvalues(values::AbstractPointValues) = values
_first_pointvalues(::Any) = nothing
_first_pointvalues(broadcasted::Base.Broadcast.Broadcasted) = _first_pointvalues(broadcasted.args)
_first_pointvalues(::Tuple{}) = nothing
function _first_pointvalues(args::Tuple)
  found = _first_pointvalues(first(args))
  return isnothing(found) ? _first_pointvalues(Base.tail(args)) : found
end


"""
    _check_broadcast_pointvalues_compatibility(destination, argument)

Check, during broadcasting, that `argument` covers the same number of points as `destination`;
non-`PointValues` arguments (real numbers, fibers, plain arrays) are accepted. Recurses into a
`Broadcasted` argument.
"""
_check_broadcast_pointvalues_compatibility(destination::AbstractPointValues, values::AbstractPointValues) = _check_npoints_match(destination, values)
_check_broadcast_pointvalues_compatibility(::AbstractPointValues, ::Any) = nothing
function _check_broadcast_pointvalues_compatibility(destination::AbstractPointValues, broadcasted::Base.Broadcast.Broadcasted)
  foreach(argument -> _check_broadcast_pointvalues_compatibility(destination, argument), broadcasted.args)
  return nothing
end


"""
    _unwrap_pointvalues_argument(x)

Replace each `PointValues` in a broadcast expression with its storage array, recursing through a
`Broadcasted` tree, so a point-value broadcast lowers to a plain array broadcast on the backend.
"""
_unwrap_pointvalues_argument(values::AbstractPointValues) = field_data(values)
_unwrap_pointvalues_argument(argument) = argument
function _unwrap_pointvalues_argument(broadcasted::Base.Broadcast.Broadcasted)
  return Base.Broadcast.broadcasted(broadcasted.f, map(_unwrap_pointvalues_argument, broadcasted.args)...)
end


function Base.copyto!(destination::AbstractPointValues, broadcasted::Base.Broadcast.Broadcasted)
  _check_broadcast_pointvalues_compatibility(destination, broadcasted)
  unwrapped = _unwrap_pointvalues_argument(broadcasted)
  unwrapped_with_destination_axes = Base.Broadcast.Broadcasted(unwrapped.style, unwrapped.f, unwrapped.args, axes(field_data(destination)))
  _assign!(field_data(destination), unwrapped_with_destination_axes)
  return destination
end

function Base.copy(broadcasted::Base.Broadcast.Broadcasted{<:PointValuesBroadcastStyle})
  reference = _first_pointvalues(broadcasted)
  isnothing(reference) && throw(ArgumentError("broadcast expression does not contain point values"))
  destination = similar_pointvalues(reference, similar(field_data(reference)))
  return copyto!(destination, broadcasted)
end


####################################
#      M2 — broadcast-based algebra  #
####################################
#
# Vector-space operations fall out of the storage-wise broadcast (above): field-field add /
# subtract and real scaling are dotted expressions that materialize a `PointValues`. Because
# point values are representation-free, scalar ± Real is a plain elementwise broadcast (no
# zero-mode handling). The component-kernel families (± constant fiber, scalar-PointValues
# products) reuse the M3 kernel-body builders and are generated alongside M3.

# Field-field combination (variadic) and its operators; reuse the FieldAlgebra n-ary reducers.
for (bang, operator, reducer) in ((:add!, :+, :_add_values), (:subtract!, :-, :_subtract_values))
  @eval function $bang(destination::AbstractPointValues, a::AbstractPointValues, b::AbstractPointValues, rest::AbstractPointValues...)
    destination .= $reducer.(a, b, rest...)
    return destination
  end

  @eval function $operator(a::AbstractPointValues, b::AbstractPointValues, rest::AbstractPointValues...)
    return $reducer.(a, b, rest...)
  end
end


+(values::AbstractPointValues) = values


function -(values::AbstractPointValues)
  return (-).(values)
end


# Scaling by a real number.
function multiply!(destination::AbstractPointValues, scalar::Real, values::AbstractPointValues)
  destination .= scalar .* values
  return destination
end

function multiply!(destination::AbstractPointValues, values::AbstractPointValues, scalar::Real)
  destination .= values .* scalar
  return destination
end

function divide!(destination::AbstractPointValues, values::AbstractPointValues, scalar::Real)
  destination .= values ./ scalar
  return destination
end

function *(values::AbstractPointValues, scalar::Real)
  return values .* scalar
end

function *(scalar::Real, values::AbstractPointValues)
  return scalar .* values
end

function /(values::AbstractPointValues, scalar::Real)
  return values ./ scalar
end


# Scalar point values ± a real number (representation-free: plain elementwise).
function add!(destination::ScalarPointValues, values::ScalarPointValues, scalar::Real)
  destination .= values .+ scalar
  return destination
end

add!(destination::ScalarPointValues, scalar::Real, values::ScalarPointValues) = add!(destination, values, scalar)

function subtract!(destination::ScalarPointValues, values::ScalarPointValues, scalar::Real)
  destination .= values .- scalar
  return destination
end

function subtract!(destination::ScalarPointValues, scalar::Real, values::ScalarPointValues)
  destination .= scalar .- values
  return destination
end

function +(values::ScalarPointValues, scalar::Real)
  return values .+ scalar
end

function +(scalar::Real, values::ScalarPointValues)
  return scalar .+ values
end

function -(values::ScalarPointValues, scalar::Real)
  return values .- scalar
end

function -(scalar::Real, values::ScalarPointValues)
  return scalar .- values
end


####################################
#   M3 — contractions (reuse builders)
####################################
#
# The per-component contraction formulas and the kernel-body assembly are imported from
# FieldAlgebra and reused verbatim: the generated bodies reach components/storage through the
# section interface above, so they apply to point values unchanged. Only the thin wrappers
# (point-count checks, the alias guard, the allocator) are point-value specific.

# Alias guard — the point-value counterpart of FieldAlgebra's `_guard_noalias!`, for the
# index-shuffling operations (cross, transpose, sym/skew/dev) that read several source components
# while writing each destination component.
_aliases_destination_pv(destination, operands...) =
  any(operand -> (operand isa AbstractPointValues) && (field_data(operand) === field_data(destination)), operands)

function _guard_noalias_pv!(kernel!, destination, output_order::Val, operands::Tuple)
  if _aliases_destination_pv(destination, operands...)
    temporary = similar_pointvalues(destination, output_order)
    kernel!(temporary, operands...)
    copyto!(field_data(destination), field_data(temporary))
    return destination
  end
  return kernel!(destination, operands...)
end


# --- Inner products (scalar result) ---
@eval _dot_components_pv!(destination, u::VectorPointValues, v::VectorPointValues) = $(_scalar_kernel_body(_dot_vector_rhs(:u, :field, :v, :field)))
@eval _dot_components_pv!(destination, u::VectorPointValues, a::FiberVector) = $(_scalar_kernel_body(_dot_vector_rhs(:u, :field, :a, :fiber)))
@eval _dot_components_pv!(destination, A::TensorPointValues{2}, B::TensorPointValues{2}) = $(_scalar_kernel_body(_dot_tensor_rhs(:A, :field, :B, :field)))
@eval _dot_components_pv!(destination, A::TensorPointValues{2}, B::FiberTensor2) = $(_scalar_kernel_body(_dot_tensor_rhs(:A, :field, :B, :fiber)))

function dot!(destination::ScalarPointValues{T}, u::VectorPointValues{T}, v::VectorPointValues{T}) where {T<:AbstractFloat}
  _check_npoints_match(destination, u)
  _check_npoints_match(u, v)
  return _dot_components_pv!(destination, u, v)
end

function dot!(destination::ScalarPointValues{T}, A::TensorPointValues{2, T}, B::TensorPointValues{2, T}) where {T<:AbstractFloat}
  _check_npoints_match(destination, A)
  _check_npoints_match(A, B)
  return _dot_components_pv!(destination, A, B)
end

dot(u::VectorPointValues{T}, v::VectorPointValues{T}) where {T<:AbstractFloat} = dot!(similar_pointvalues(u, Val(0)), u, v)
dot(A::TensorPointValues{2, T}, B::TensorPointValues{2, T}) where {T<:AbstractFloat} = dot!(similar_pointvalues(A, Val(0)), A, B)

for (Operand, Constant) in ((:VectorPointValues, :FiberVector), (:(TensorPointValues{2}), :FiberTensor2))
  @eval function dot!(destination::ScalarPointValues{T}, operand::$Operand{T}, constant::$Constant{T}) where {T<:AbstractFloat}
    _check_npoints_match(destination, operand)
    return _dot_components_pv!(destination, operand, constant)
  end
  @eval dot!(destination::ScalarPointValues{T}, constant::$Constant{T}, operand::$Operand{T}) where {T<:AbstractFloat} =
    dot!(destination, operand, constant)
  @eval dot(operand::$Operand{T}, constant::$Constant{T}) where {T<:AbstractFloat} =
    dot!(similar_pointvalues(operand, Val(0)), operand, constant)
  @eval dot(constant::$Constant{T}, operand::$Operand{T}) where {T<:AbstractFloat} =
    dot!(similar_pointvalues(operand, Val(0)), operand, constant)
end


# --- Cross products (vector result; index-shuffling ⇒ alias-guarded) ---
@eval _cross_components_pv!(destination, u::VectorPointValues, v::VectorPointValues) = $(_vector_kernel_body(_cross_formula(:u, :field, :v, :field); alpha_beta = false))
@eval _cross_components_pv!(destination, u::VectorPointValues, a::FiberVector) = $(_vector_kernel_body(_cross_formula(:u, :field, :a, :fiber); alpha_beta = false))
@eval _cross_components_pv!(destination, a::FiberVector, u::VectorPointValues) = $(_vector_kernel_body(_cross_formula(:a, :fiber, :u, :field); alpha_beta = false))

function cross!(destination::VectorPointValues{T}, u::VectorPointValues{T}, v::VectorPointValues{T}) where {T<:AbstractFloat}
  _check_npoints_match(destination, u)
  _check_npoints_match(u, v)
  return _guard_noalias_pv!(_cross_components_pv!, destination, Val(1), (u, v))
end

cross(u::VectorPointValues{T}, v::VectorPointValues{T}) where {T<:AbstractFloat} = cross!(similar_pointvalues(u, Val(1)), u, v)

function cross!(destination::VectorPointValues{T}, u::VectorPointValues{T}, a::FiberVector{T}) where {T<:AbstractFloat}
  _check_npoints_match(destination, u)
  return _guard_noalias_pv!(_cross_components_pv!, destination, Val(1), (u, a))
end

function cross!(destination::VectorPointValues{T}, a::FiberVector{T}, u::VectorPointValues{T}) where {T<:AbstractFloat}
  _check_npoints_match(destination, u)
  return _guard_noalias_pv!(_cross_components_pv!, destination, Val(1), (a, u))
end

cross(u::VectorPointValues{T}, a::FiberVector{T}) where {T<:AbstractFloat} = cross!(similar_pointvalues(u, Val(1)), u, a)
cross(a::FiberVector{T}, u::VectorPointValues{T}) where {T<:AbstractFloat} = cross!(similar_pointvalues(u, Val(1)), a, u)


# --- Tensor-vector and tensor-tensor products (α/β; no alias guard, like mul!) ---
@eval _tensor_vector_components_pv!(destination, A::TensorPointValues{2}, u::VectorPointValues, α_value, β_value) = $(_vector_kernel_body(_tensor_vector_formula(:A, :field, :u, :field); alpha_beta = true))
@eval _tensor_vector_components_pv!(destination, A::TensorPointValues{2}, a::FiberVector, α_value, β_value) = $(_vector_kernel_body(_tensor_vector_formula(:A, :field, :a, :fiber); alpha_beta = true))
@eval _tensor_vector_components_pv!(destination, A::FiberTensor2, u::VectorPointValues, α_value, β_value) = $(_vector_kernel_body(_tensor_vector_formula(:A, :fiber, :u, :field); alpha_beta = true))
@eval _vector_tensor_components_pv!(destination, u::VectorPointValues, A::TensorPointValues{2}, α_value, β_value) = $(_vector_kernel_body(_vector_tensor_formula(:u, :field, :A, :field); alpha_beta = true))
@eval _vector_tensor_components_pv!(destination, a::FiberVector, A::TensorPointValues{2}, α_value, β_value) = $(_vector_kernel_body(_vector_tensor_formula(:a, :fiber, :A, :field); alpha_beta = true))
@eval _vector_tensor_components_pv!(destination, u::VectorPointValues, A::FiberTensor2, α_value, β_value) = $(_vector_kernel_body(_vector_tensor_formula(:u, :field, :A, :fiber); alpha_beta = true))
@eval _tensor_tensor_components_pv!(destination, A::TensorPointValues{2}, B::TensorPointValues{2}, α_value, β_value) = $(_tensor_kernel_body(_tensor_tensor_formula(:A, :field, :B, :field); alpha_beta = true))
@eval _tensor_tensor_components_pv!(destination, A::TensorPointValues{2}, B::FiberTensor2, α_value, β_value) = $(_tensor_kernel_body(_tensor_tensor_formula(:A, :field, :B, :fiber); alpha_beta = true))
@eval _tensor_tensor_components_pv!(destination, A::FiberTensor2, B::TensorPointValues{2}, α_value, β_value) = $(_tensor_kernel_body(_tensor_tensor_formula(:A, :fiber, :B, :field); alpha_beta = true))

# Five-argument mul!: `destination = α * product + β * destination`. As with LinearAlgebra.mul!,
# the destination must not alias the inputs (no guard).
function mul!(destination::VectorPointValues{T}, A::TensorPointValues{2, T}, u::VectorPointValues{T}, α::Real, β::Real) where {T<:AbstractFloat}
  _check_npoints_match(destination, u); _check_npoints_match(A, u)
  return _tensor_vector_components_pv!(destination, A, u, T(α), T(β))
end

function mul!(destination::VectorPointValues{T}, u::VectorPointValues{T}, A::TensorPointValues{2, T}, α::Real, β::Real) where {T<:AbstractFloat}
  _check_npoints_match(destination, u); _check_npoints_match(A, u)
  return _vector_tensor_components_pv!(destination, u, A, T(α), T(β))
end

function mul!(destination::VectorPointValues{T}, A::TensorPointValues{2, T}, a::FiberVector{T}, α::Real, β::Real) where {T<:AbstractFloat}
  _check_npoints_match(destination, A)
  return _tensor_vector_components_pv!(destination, A, a, T(α), T(β))
end

function mul!(destination::VectorPointValues{T}, a::FiberVector{T}, A::TensorPointValues{2, T}, α::Real, β::Real) where {T<:AbstractFloat}
  _check_npoints_match(destination, A)
  return _vector_tensor_components_pv!(destination, a, A, T(α), T(β))
end

function mul!(destination::VectorPointValues{T}, A::FiberTensor2{T}, u::VectorPointValues{T}, α::Real, β::Real) where {T<:AbstractFloat}
  _check_npoints_match(destination, u)
  return _tensor_vector_components_pv!(destination, A, u, T(α), T(β))
end

function mul!(destination::VectorPointValues{T}, u::VectorPointValues{T}, A::FiberTensor2{T}, α::Real, β::Real) where {T<:AbstractFloat}
  _check_npoints_match(destination, u)
  return _vector_tensor_components_pv!(destination, u, A, T(α), T(β))
end

function mul!(destination::TensorPointValues{2, T}, A::TensorPointValues{2, T}, B::TensorPointValues{2, T}, α::Real, β::Real) where {T<:AbstractFloat}
  _check_npoints_match(destination, A); _check_npoints_match(A, B)
  return _tensor_tensor_components_pv!(destination, A, B, T(α), T(β))
end

function mul!(destination::TensorPointValues{2, T}, A::TensorPointValues{2, T}, B::FiberTensor2{T}, α::Real, β::Real) where {T<:AbstractFloat}
  _check_npoints_match(destination, A)
  return _tensor_tensor_components_pv!(destination, A, B, T(α), T(β))
end

function mul!(destination::TensorPointValues{2, T}, A::FiberTensor2{T}, B::TensorPointValues{2, T}, α::Real, β::Real) where {T<:AbstractFloat}
  _check_npoints_match(destination, B)
  return _tensor_tensor_components_pv!(destination, A, B, T(α), T(β))
end

# Three-argument mul! delegates with α = 1, β = 0 (overwrite).
for (Destination, First, Second) in (
    (:(VectorPointValues{T}),    :(TensorPointValues{2, T}), :(VectorPointValues{T})),
    (:(VectorPointValues{T}),    :(VectorPointValues{T}),    :(TensorPointValues{2, T})),
    (:(VectorPointValues{T}),    :(TensorPointValues{2, T}), :(FiberVector{T})),
    (:(VectorPointValues{T}),    :(FiberVector{T}),          :(TensorPointValues{2, T})),
    (:(VectorPointValues{T}),    :(FiberTensor2{T}),         :(VectorPointValues{T})),
    (:(VectorPointValues{T}),    :(VectorPointValues{T}),    :(FiberTensor2{T})),
    (:(TensorPointValues{2, T}), :(TensorPointValues{2, T}), :(TensorPointValues{2, T})),
    (:(TensorPointValues{2, T}), :(TensorPointValues{2, T}), :(FiberTensor2{T})),
    (:(TensorPointValues{2, T}), :(FiberTensor2{T}),         :(TensorPointValues{2, T})),
  )

  @eval mul!(destination::$Destination, first::$First, second::$Second) where {T<:AbstractFloat} =
    mul!(destination, first, second, one(T), zero(T))
end

# Allocating `*` operators delegate to the three-argument mul!.
*(A::TensorPointValues{2, T}, a::FiberVector{T}) where {T<:AbstractFloat} = mul!(similar_pointvalues(A, Val(1)), A, a)
*(a::FiberVector{T}, A::TensorPointValues{2, T}) where {T<:AbstractFloat} = mul!(similar_pointvalues(A, Val(1)), a, A)
*(A::FiberTensor2{T}, u::VectorPointValues{T}) where {T<:AbstractFloat} = mul!(similar_pointvalues(u, Val(1)), A, u)
*(u::VectorPointValues{T}, A::FiberTensor2{T}) where {T<:AbstractFloat} = mul!(similar_pointvalues(u, Val(1)), u, A)
*(A::TensorPointValues{2, T}, u::VectorPointValues{T}) where {T<:AbstractFloat} = mul!(similar_pointvalues(u, Val(1)), A, u)
*(u::VectorPointValues{T}, A::TensorPointValues{2, T}) where {T<:AbstractFloat} = mul!(similar_pointvalues(u, Val(1)), u, A)
*(A::TensorPointValues{2, T}, B::TensorPointValues{2, T}) where {T<:AbstractFloat} = mul!(similar_pointvalues(A, Val(2)), A, B)
*(A::TensorPointValues{2, T}, B::FiberTensor2{T}) where {T<:AbstractFloat} = mul!(similar_pointvalues(A, Val(2)), A, B)
*(A::FiberTensor2{T}, B::TensorPointValues{2, T}) where {T<:AbstractFloat} = mul!(similar_pointvalues(B, Val(2)), A, B)


# --- Transpose (index shuffle ⇒ alias-guarded) ---
@eval _transpose_components_pv!(destination, A) = $(_tensor_kernel_body(_transpose_formula(:A, :field); alpha_beta = false))

function transpose!(destination::TensorPointValues{2, T}, A::TensorPointValues{2, T}) where {T<:AbstractFloat}
  _check_npoints_match(destination, A)
  return _guard_noalias_pv!(_transpose_components_pv!, destination, Val(2), (A,))
end

transpose(A::TensorPointValues{2, T}) where {T<:AbstractFloat} = transpose!(similar_pointvalues(A, Val(2)), A)


# --- Norms (scalar result) ---
# NOTE: FieldAlgebra inlines the norm formula (no shared builder), so these three expressions
# are replicated here; Phase A extracts `_norm_*_rhs` builders and removes the replication.
@eval _norm_components_pv!(destination, values::ScalarPointValues) = $(_scalar_kernel_body(:(abs.(field_data(values)))))
@eval _norm_components_pv!(destination, u::VectorPointValues) = $(_scalar_kernel_body(:(sqrt.($(_sum_terms([:(abs2.($(_vector_component(:u, :field, i)))) for i in 1:3]))))))
@eval _norm_components_pv!(destination, A::TensorPointValues{2}) = $(_scalar_kernel_body(:(sqrt.($(_sum_terms([:(abs2.($(_tensor_component(:A, :field, i, j)))) for i in 1:3 for j in 1:3]))))))

for Operand in (:ScalarPointValues, :VectorPointValues, :(TensorPointValues{2}))
  @eval function norm!(destination::ScalarPointValues{T}, operand::$Operand{T}) where {T<:AbstractFloat}
    _check_npoints_match(destination, operand)
    return _norm_components_pv!(destination, operand)
  end

  @eval norm(operand::$Operand{T}) where {T<:AbstractFloat} = norm!(similar_pointvalues(operand, Val(0)), operand)
end


# --- Symmetric / skew / deviatoric decompositions (index-shuffling ⇒ alias-guarded) ---
# NOTE: also replicated from the inlined field formulas (`half`/`third`/`trace` locals); the
# scalar type comes from `eltype(field_data(A))`. Phase A extracts shared formula builders.
@eval function _sym_components_pv!(destination, A)
  half = inv(eltype(field_data(A))(2))
  $(_tensor_kernel_body((i, j) -> i == j ? _tensor_component(:A, :field, i, i) :
      :(half .* ($(_tensor_component(:A, :field, i, j)) .+ $(_tensor_component(:A, :field, j, i)))); alpha_beta = false))
end

@eval function _skew_components_pv!(destination, A)
  half = inv(eltype(field_data(A))(2))
  $(_tensor_kernel_body((i, j) -> i == j ? :(zero(eltype(field_data(A)))) :
      :(half .* ($(_tensor_component(:A, :field, i, j)) .- $(_tensor_component(:A, :field, j, i)))); alpha_beta = false))
end

@eval function _dev_components_pv!(destination, A)
  third = inv(eltype(field_data(A))(3))
  trace = $(_sum_terms([_tensor_component(:A, :field, d, d) for d in 1:3]))
  $(_tensor_kernel_body((i, j) -> i == j ? :($(_tensor_component(:A, :field, i, i)) .- third .* trace) :
      _tensor_component(:A, :field, i, j); alpha_beta = false))
end

for (kernel, bang, allocating) in (
    (:_sym_components_pv!,  :sym!,  :sym),
    (:_skew_components_pv!, :skew!, :skew),
    (:_dev_components_pv!,  :dev!,  :dev),
  )

  @eval function $bang(destination::TensorPointValues{2, T}, A::TensorPointValues{2, T}) where {T<:AbstractFloat}
    _check_npoints_match(destination, A)
    return _guard_noalias_pv!($kernel, destination, Val(2), (A,))
  end

  @eval $allocating(A::TensorPointValues{2, T}) where {T<:AbstractFloat} = $bang(similar_pointvalues(A, Val(2)), A)
end


####################################
#   M2 component kernels (±fiber, scalar-PointValues products, division)
####################################

# --- Point values ± a constant fiber (fused copy+add per component, via the kernel builder) ---
@eval _add_fiber_pv!(destination, values::VectorPointValues, a::FiberVector) = $(_vector_kernel_body(i -> :($(_vector_component(:values, :field, i)) .+ $(_vector_component(:a, :fiber, i))); alpha_beta = false))
@eval _add_fiber_pv!(destination, values::TensorPointValues{2}, A::FiberTensor2) = $(_tensor_kernel_body((i, j) -> :($(_tensor_component(:values, :field, i, j)) .+ $(_tensor_component(:A, :fiber, i, j))); alpha_beta = false))
@eval _subtract_fiber_pv!(destination, values::VectorPointValues, a::FiberVector) = $(_vector_kernel_body(i -> :($(_vector_component(:values, :field, i)) .- $(_vector_component(:a, :fiber, i))); alpha_beta = false))
@eval _subtract_fiber_pv!(destination, values::TensorPointValues{2}, A::FiberTensor2) = $(_tensor_kernel_body((i, j) -> :($(_tensor_component(:values, :field, i, j)) .- $(_tensor_component(:A, :fiber, i, j))); alpha_beta = false))
@eval _subtract_from_fiber_pv!(destination, a::FiberVector, values::VectorPointValues) = $(_vector_kernel_body(i -> :($(_vector_component(:a, :fiber, i)) .- $(_vector_component(:values, :field, i))); alpha_beta = false))
@eval _subtract_from_fiber_pv!(destination, A::FiberTensor2, values::TensorPointValues{2}) = $(_tensor_kernel_body((i, j) -> :($(_tensor_component(:A, :fiber, i, j)) .- $(_tensor_component(:values, :field, i, j))); alpha_beta = false))

for (PVType, Constant, order) in (
    (:VectorPointValues, :FiberVector, 1),
    (:(TensorPointValues{2}), :FiberTensor2, 2),
  )

  @eval function add!(destination::$PVType{T}, values::$PVType{T}, constant::$Constant{T}) where {T<:AbstractFloat}
    _check_npoints_match(destination, values)
    return _add_fiber_pv!(destination, values, constant)
  end

  @eval add!(destination::$PVType{T}, constant::$Constant{T}, values::$PVType{T}) where {T<:AbstractFloat} =
    add!(destination, values, constant)

  @eval function subtract!(destination::$PVType{T}, values::$PVType{T}, constant::$Constant{T}) where {T<:AbstractFloat}
    _check_npoints_match(destination, values)
    return _subtract_fiber_pv!(destination, values, constant)
  end

  @eval function subtract!(destination::$PVType{T}, constant::$Constant{T}, values::$PVType{T}) where {T<:AbstractFloat}
    _check_npoints_match(destination, values)
    return _subtract_from_fiber_pv!(destination, constant, values)
  end

  @eval +(values::$PVType{T}, constant::$Constant{T}) where {T<:AbstractFloat} = add!(similar_pointvalues(values, Val($order)), values, constant)
  @eval +(constant::$Constant{T}, values::$PVType{T}) where {T<:AbstractFloat} = add!(similar_pointvalues(values, Val($order)), constant, values)
  @eval -(values::$PVType{T}, constant::$Constant{T}) where {T<:AbstractFloat} = subtract!(similar_pointvalues(values, Val($order)), values, constant)
  @eval -(constant::$Constant{T}, values::$PVType{T}) where {T<:AbstractFloat} = subtract!(similar_pointvalues(values, Val($order)), constant, values)
end


# --- Scalar point values × constant fiber (reuse the scalar-by-fiber kernel builder) ---
@eval function _multiply_scalar_pv_by_fiber_vector!(destination, scalar_values, a::FiberVector)
  scalar_data = field_data(scalar_values)
  $(_vector_kernel_body(i -> _product(:scalar_data, _vector_component(:a, :fiber, i)); alpha_beta = false))
end

@eval function _multiply_scalar_pv_by_fiber_tensor2!(destination, scalar_values, A::FiberTensor2)
  scalar_data = field_data(scalar_values)
  $(_tensor_kernel_body((i, j) -> _product(:scalar_data, _tensor_component(:A, :fiber, i, j)); alpha_beta = false))
end

for (Result, Constant, order, kernel) in (
    (:VectorPointValues, :FiberVector, 1, :_multiply_scalar_pv_by_fiber_vector!),
    (:(TensorPointValues{2}), :FiberTensor2, 2, :_multiply_scalar_pv_by_fiber_tensor2!),
  )

  @eval function multiply!(destination::$Result{T}, scalar_values::ScalarPointValues{T}, constant::$Constant{T}) where {T<:AbstractFloat}
    _check_npoints_match(destination, scalar_values)
    return $kernel(destination, scalar_values, constant)
  end

  @eval multiply!(destination::$Result{T}, constant::$Constant{T}, scalar_values::ScalarPointValues{T}) where {T<:AbstractFloat} =
    multiply!(destination, scalar_values, constant)

  @eval *(scalar_values::ScalarPointValues{T}, constant::$Constant{T}) where {T<:AbstractFloat} = multiply!(similar_pointvalues(scalar_values, Val($order)), scalar_values, constant)
  @eval *(constant::$Constant{T}, scalar_values::ScalarPointValues{T}) where {T<:AbstractFloat} = multiply!(similar_pointvalues(scalar_values, Val($order)), constant, scalar_values)
end


# --- Scalar point values × point values (singleton-fiber broadcast over all components) ---
_scalar_pv_broadcast_data(scalar_values::ScalarPointValues, values::AbstractPointValues) =
  reshape(field_data(scalar_values), size(field_data(scalar_values))..., ntuple(_ -> 1, pointvalue_tensor_order(values))...)

function _multiply_by_scalar_pv!(destination::AbstractPointValues, scalar_values::ScalarPointValues, values::AbstractPointValues)
  _check_npoints_match(destination, values)
  _check_npoints_match(scalar_values, values)
  @_assign! field_data(destination) .= _scalar_pv_broadcast_data(scalar_values, values) .* field_data(values)
  return destination
end

# The four dispatch signatures resolve the scalar×scalar ambiguity (mirroring FieldAlgebra).
multiply!(destination::AbstractPointValues, scalar_values::ScalarPointValues, values::AbstractPointValues) = _multiply_by_scalar_pv!(destination, scalar_values, values)
multiply!(destination::AbstractPointValues, values::AbstractPointValues, scalar_values::ScalarPointValues) = _multiply_by_scalar_pv!(destination, scalar_values, values)
multiply!(destination::ScalarPointValues, a::ScalarPointValues, b::ScalarPointValues) = _multiply_by_scalar_pv!(destination, a, b)
multiply!(destination::AbstractPointValues, a::ScalarPointValues, b::ScalarPointValues) = _multiply_by_scalar_pv!(destination, a, b)

*(scalar_values::ScalarPointValues{T}, values::AbstractPointValues{T}) where {T<:AbstractFloat} = multiply!(similar_pointvalues(values, similar(field_data(values))), scalar_values, values)
*(values::AbstractPointValues{T}, scalar_values::ScalarPointValues{T}) where {T<:AbstractFloat} = multiply!(similar_pointvalues(values, similar(field_data(values))), values, scalar_values)
*(a::ScalarPointValues{T}, b::ScalarPointValues{T}) where {T<:AbstractFloat} = multiply!(similar_pointvalues(a, similar(field_data(a))), a, b)


# --- Division by scalar point values ---
@eval function _divide_fiber_vector_by_scalar_pv!(destination, a::FiberVector, scalar_values)
  scalar_data = field_data(scalar_values)
  $(_vector_kernel_body(i -> :($(_vector_component(:a, :fiber, i)) ./ scalar_data); alpha_beta = false))
end

@eval function _divide_fiber_tensor2_by_scalar_pv!(destination, A::FiberTensor2, scalar_values)
  scalar_data = field_data(scalar_values)
  $(_tensor_kernel_body((i, j) -> :($(_tensor_component(:A, :fiber, i, j)) ./ scalar_data); alpha_beta = false))
end

function divide!(destination::VectorPointValues{T}, a::FiberVector{T}, scalar_values::ScalarPointValues{T}) where {T<:AbstractFloat}
  _check_npoints_match(destination, scalar_values)
  return _divide_fiber_vector_by_scalar_pv!(destination, a, scalar_values)
end

function divide!(destination::TensorPointValues{2, T}, A::FiberTensor2{T}, scalar_values::ScalarPointValues{T}) where {T<:AbstractFloat}
  _check_npoints_match(destination, scalar_values)
  return _divide_fiber_tensor2_by_scalar_pv!(destination, A, scalar_values)
end

function divide!(destination::AbstractPointValues, values::AbstractPointValues, scalar_values::ScalarPointValues)
  _check_npoints_match(destination, values)
  _check_npoints_match(scalar_values, values)
  @_assign! field_data(destination) .= field_data(values) ./ _scalar_pv_broadcast_data(scalar_values, values)
  return destination
end

function divide!(destination::ScalarPointValues, scalar::Real, scalar_values::ScalarPointValues)
  destination .= scalar ./ scalar_values
  return destination
end

/(values::AbstractPointValues{T}, scalar_values::ScalarPointValues{T}) where {T<:AbstractFloat} = divide!(similar_pointvalues(values, similar(field_data(values))), values, scalar_values)
/(scalar::Real, scalar_values::ScalarPointValues{T}) where {T<:AbstractFloat} = divide!(similar_pointvalues(scalar_values, similar(field_data(scalar_values))), scalar, scalar_values)
/(a::FiberVector{T}, scalar_values::ScalarPointValues{T}) where {T<:AbstractFloat} = divide!(similar_pointvalues(scalar_values, Val(1)), a, scalar_values)
/(A::FiberTensor2{T}, scalar_values::ScalarPointValues{T}) where {T<:AbstractFloat} = divide!(similar_pointvalues(scalar_values, Val(2)), A, scalar_values)


# The transfer kernels — interpolation (`f(x)` / `interpolate` / `interpolate!`) and its adjoint
# anterpolation (`anterpolate` / `anterpolate!`) — are not yet implemented; see the module
# docstring and docs/ARCHITECTURE.md §10. These data types and their compatibility check come first.

end # module Interpolation
