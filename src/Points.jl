"""
    Points

The unstructured base of the package's fiber-bundle model: off-grid sample positions and the
field values sampled at them. A point set plays the role the grid plays in
[`Fields`](@ref "Fields"), and point
values are sections over it.

The parts are:

  * **Positions.** [`Point`](@ref) is a single coordinate triple, and [`PointSet`](@ref) holds
    `M` positions in a structure-of-arrays layout. A point set carries no grid; a periodic
    domain wraps any coordinate, so the grid is supplied by the transfer operator at use time.
  * **Point-value sections.** [`ScalarPointValues`](@ref), [`VectorPointValues`](@ref), and
    [`TensorPointValues`](@ref), gathered under [`AbstractPointValues`](@ref), mirror the field
    tensor orders. They are representation-free, because a sampled value is always a
    physical-space quantity.
  * **A full fiberwise algebra on the point values.** Addition, real scaling, scalar
    multiplication and division, `dot`, `cross`, `mul!`, `transpose`, `norm`, the `tr` and `det`
    invariants, and the `sym`/`skew`/`dev` decompositions form the same physical surface the fields
    carry, together with the arbitrary-fiber-map escape hatch `map!`/`map` — see
    [`FieldAlgebra`](@ref) for each operation, documented once there. The algebra reuses the shared [`FiberSections`](@ref) formula builders and fused
    values functions over the point-value section interface, so no per-component formula is written twice.

  * **Base-space motion.** [`displace!`](@ref) moves the points themselves along
    coefficient-weighted vector sections — in unwrapped coordinates, or, given a [`Grid3D`](@ref), landing
    back in the periodic box in the same fused pass — and [`wrap!`](@ref) reduces positions to
    their canonical in-box representatives. The one family that couples base and fiber; positions
    deliberately have no `+` with point values.
  * **Allocation.** [`similar_point_values`](@ref) returns uninitialized storage carrying a reference's
    tensor order and backend — the point-value twin of `similar_field`, and what the broadcast
    machinery and the allocating algebra wrappers build their results with.
  * **Persistence.** [`write_points`](@ref) and [`read_points`](@ref) map a point set or a point-value
    section to and from one self-describing HDF5 group, positions and values kept separate (methods
    load with the `HDF5` package, as a weak-dependency extension). They are the point-layer twins of
    [`write_field`](@ref GBGPeriodicFields.Fields.write_field)/[`read_field`](@ref GBGPeriodicFields.Fields.read_field).
  * **Moving between storage families.** [`adapt`](@ref) moves a `PointSet` or any point values
    between host and device memory, exactly as it moves a field; the operation is documented once,
    with its field methods, in [`Fields`](@ref "Fields").

The grid-to-point transfer (interpolation) and its adjoint (anterpolation) live in the
[`Interpolation`](@ref "Interpolation") module.
"""
module Points

using StaticArrays: SVector
# Imported before extending, per invariant 7. The point layer mirrors the field surface here as it
# does everywhere else: a `PointSet` and its values move between storage families the same way.
import Adapt: adapt, adapt_structure
using ..FiberSections:
  _check_owned_storage, AbstractFiberSection, _section_scalar_type, _assign!, @_assign!,
                       _add_values, _subtract_values,
                       _scalar_kernel_body, _vector_kernel_body, _tensor_kernel_body,
                       _sum_terms, _vector_component, _tensor_component, _product,
                       _dot_vector_rhs, _dot_tensor_rhs, _cross_formula,
                       _tensor_vector_formula, _vector_tensor_formula, _tensor_tensor_formula,
                       _transpose_formula,
                       _norm_scalar_rhs, _norm_vector_rhs, _norm_tensor_rhs,
                       _trace_tensor_rhs, _det_tensor_rhs,
                       _fiberwise_pass!,
                       _cross_values_ff, _cross_values_fc, _cross_values_cf,
                       _tensor_vector_values_ff, _tensor_vector_values_fc, _tensor_vector_values_cf,
                       _vector_tensor_values_ff, _vector_tensor_values_fc, _vector_tensor_values_cf,
                       _tensor_tensor_values_ff, _tensor_tensor_values_fc, _tensor_tensor_values_cf,
                       _transpose_values, _sym_values, _skew_values, _dev_values, _det_values

using KernelAbstractions: get_backend
using ..FiberSections: fiber_shape, FiberVector, FiberTensor2   # the fiber is base-agnostic
import Base: +, -, *, /, map, map!
import LinearAlgebra: dot, cross, mul!, transpose, transpose!, norm, tr, det
using ..Fields: _refuse_field_as_fiber_map   # the callable-field guard shared with `FieldAlgebra`
import ..Fields: adapt!, field_data, _vector_component_data, _tensor2_component_data  # extended on PointValues
import ..FieldAlgebra: add!, subtract!, multiply!, divide!, dot!, cross!,       # extended on PointValues
                       norm!, sym, sym!, skew, skew!, dev, dev!, tr!, det!
using ..FieldAlgebra: _map_pass!, _map_output_order,   # shared map!/map driver + output-order inference
  _check_map_not_aliased                              # …and the one rule both bases share


export Point,
       PointSet,
       AbstractPointValues,
       ScalarPointValues,
       VectorPointValues,
       TensorPointValues,
       point_positions,
       point_values,
       point_value_tensor_order,
       npoints,
       similar_point_values,
       displace!,
       wrap!,
       write_points,
       read_points


####################################
#            Positions             #
####################################

"""
    Point{T} = SVector{3, T}

A single position in the domain, stored as a coordinate triple. `Point` is the base-space analog
of `FiberVector`: it shares the `SVector{3,T}` representation but plays a different role, naming
a location rather than a field value. It is a type alias rather than a wrapper, so arithmetic on
positions stays StaticArrays-native and the position-versus-value distinction is one of role,
not of dispatch.
"""
const Point{T} = SVector{3, T}


"""
    PointSet(positions::AbstractArray{T, 2}) where {T<:AbstractFloat}

A collection of `M` off-grid positions, stored structure-of-arrays so that each coordinate axis is
contiguous across points, mirroring the fiber-last field layout. Storage is backend-generic: the array
may live on the CPU (`Array`) or a GPU (`CuArray`/`ROCArray`). A point set carries no grid,
because a periodic domain wraps any coordinate; a transfer operator takes the grid from the
field it acts on.

The fields are
- `positions` — the coordinate triples, an `AbstractArray` of shape `(M, 3)` — point index first,
  coordinate axis last — whose second axis must have length `3`.
"""
struct PointSet{T<:AbstractFloat, A<:AbstractArray{T, 2}}
  positions::A

  function PointSet(positions::A) where {T<:AbstractFloat, A<:AbstractArray{T, 2}}
    size(positions, 2) == 3 ||
      throw(DimensionMismatch("PointSet positions must have shape (M, 3); got $(size(positions))"))
    _check_owned_storage(positions, "a PointSet")
    return new{T, A}(positions)
  end
end


####################################
#           Point values           #
####################################

"""
    AbstractPointValues{T<:AbstractFloat, R}

Abstract supertype for field values sampled at the `M` positions of a [`PointSet`](@ref). The
parameter `T` is the real scalar type, and `R` is the tensor order, an integer value parameter.
Point values are representation-free: a sampled value is always a physical-space quantity, so
there is no physical/spectral distinction here, unlike the field types. The concrete subtypes
are [`ScalarPointValues`](@ref) at tensor order `0`, [`VectorPointValues`](@ref) at order `1`,
and [`TensorPointValues`](@ref) at order `2` and above.

!!! note "A section owns its storage"
    Every constructor here — and `PointSet`'s — **rejects borrowed storage**, a `SubArray`
    anywhere in the parent chain, so wrapping a view into a larger buffer will throw. Ownership is what
    makes aliasing safe by construction: two sections can then share memory only by being the same
    array. Allocate with [`similar_point_values`](@ref), or `copy` the slice. Any owning array is fine —
    `Array`, `CuArray`, `ROCArray`, or a `reshape` of one.
"""
abstract type AbstractPointValues{T<:AbstractFloat, R} <: AbstractFiberSection{T, R} end


"""
    ScalarPointValues(data::AbstractArray{T, 1}) where {T<:AbstractFloat}

One scalar value per point, sampled at `M` points — the point-set counterpart of a
[`ScalarFieldPhysical`](@ref GBGPeriodicFields.Fields.ScalarFieldPhysical). Point-values carry no second representation, there being no periodic
grid to transform over.

The fields are
- `data` — the values, with shape `(M,)`.
"""
struct ScalarPointValues{T<:AbstractFloat, A<:AbstractArray{T, 1}} <: AbstractPointValues{T, 0}
  data::A

  # Decision 59 applies here exactly as it does to the vector and tensor point-value types and to every
  # field type: a section owns its storage, which is what makes the aliasing argument hold. This type
  # was the one member of the family left without the check — its sibling's error message even reads
  # "a ScalarPointValues / VectorPointValues", which is where the omission shows.
  function ScalarPointValues(data::A) where {T<:AbstractFloat, A<:AbstractArray{T, 1}}
    _check_owned_storage(data, "a ScalarPointValues")
    return new{T, A}(data)
  end
end


"""
    VectorPointValues(data::AbstractArray{T, 2}) where {T<:AbstractFloat}

One vector value per point, sampled at `M` points — the point-set counterpart of a
[`VectorFieldPhysical`](@ref GBGPeriodicFields.Fields.VectorFieldPhysical).

The fields are
- `data` — the components, structure-of-arrays with shape `(M, 3)`; the second axis must have length `3`, and the constructor checks it.
"""
struct VectorPointValues{T<:AbstractFloat, A<:AbstractArray{T, 2}} <: AbstractPointValues{T, 1}
  data::A

  function VectorPointValues(data::A) where {T<:AbstractFloat, A<:AbstractArray{T, 2}}
    size(data, 2) == 3 ||
      throw(DimensionMismatch("VectorPointValues data must have shape (M, 3); got $(size(data))"))
    _check_owned_storage(data, "a ScalarPointValues / VectorPointValues")
    return new{T, A}(data)
  end
end


"""
    TensorPointValues{R}(data::AbstractArray{T}) where {R, T<:AbstractFloat}
    TensorPointValues(data::AbstractArray{T}) where {T<:AbstractFloat}

One tensor value of order `R` per point (``R \\ge 2``; use [`ScalarPointValues`](@ref) or
[`VectorPointValues`](@ref) for orders `0` and `1`, which the constructor enforces), sampled at `M` points — the point-set counterpart of a
[`TensorFieldPhysical`](@ref GBGPeriodicFields.Fields.TensorFieldPhysical).

The fields are
- `data` — the components, structure-of-arrays with shape `(M, fiber_shape(Val(R))...)` — `(M, 3, 3)` at order `2`.

The constructor written without an explicit `{R}` infers the order as `ndims(data) - 1`.
"""
struct TensorPointValues{R, T<:AbstractFloat, A<:AbstractArray{T}} <: AbstractPointValues{T, R}
  data::A

  function TensorPointValues{R}(data::A) where {R, T<:AbstractFloat, A<:AbstractArray{T}}
    # The three point-value types partition tensor order, exactly as the field types do: order 0 is
    # `ScalarPointValues`, order 1 is `VectorPointValues`, and this type covers 2 and above. Without
    # the bound `TensorPointValues{0}` and `{1}` constructed happily, so two concrete types could
    # represent one order — which makes the documented taxonomy false and any dispatch written against
    # it unreliable.
    (R isa Integer && R >= 2) ||
      throw(ArgumentError("TensorPointValues requires an integer tensor order R >= 2; got R = $R. " *
                          "Use ScalarPointValues for order 0 and VectorPointValues for order 1"))
    ndims(data) == R + 1 ||
      throw(DimensionMismatch("TensorPointValues{$R} data must have $(R + 1) dimensions; got $(ndims(data))"))
    size(data)[2:end] == fiber_shape(Val(R)) ||
      throw(DimensionMismatch("TensorPointValues{$R} data must have shape (M, $(fiber_shape(Val(R))...)); got $(size(data))"))
    _check_owned_storage(data, "a TensorPointValues")
    return new{R, T, A}(data)
  end
end

TensorPointValues(data::AbstractArray{T}) where {T<:AbstractFloat} = TensorPointValues{ndims(data) - 1}(data)


####################################
#            Accessors             #
####################################

"""
    point_positions(point_set::PointSet)

Return the `(M, 3)` array of point positions held by `point_set`.
"""
function point_positions end
point_positions(point_set::PointSet) = point_set.positions


"""
    point_values(sampled_values::AbstractPointValues)

Return the underlying array of sampled values held by `sampled_values`, a structure-of-arrays
with shape `(M, fiber_shape(Val(R))...)` — `(M,)`, `(M, 3)` and `(M, 3, 3)` at tensor orders `0`, `1`
and `2`.
"""
function point_values end
point_values(sampled_values::AbstractPointValues) = sampled_values.data


"""
    point_value_tensor_order(sampled_values::AbstractPointValues{T, R}) where
        {T<:AbstractFloat, R}

Return the tensor order `R` of `sampled_values`.
"""
function point_value_tensor_order end
point_value_tensor_order(::AbstractPointValues{T, R}) where {T<:AbstractFloat, R} = R


"""
    npoints(point_set::PointSet)
    npoints(sampled_values::AbstractPointValues)

Return the number `M` of points, the leading-axis length of the coordinate array of a
[`PointSet`](@ref) or of the value array of an [`AbstractPointValues`](@ref).
"""
function npoints end
npoints(point_set::PointSet) = size(point_set.positions, 1)
npoints(sampled_values::AbstractPointValues) = size(sampled_values.data, 1)


####################################
#          Compatibility           #
####################################

"""
    _check_npoints_match(a, b)

Throw a `DimensionMismatch` unless `a` and `b` cover the same number of points `M`, and
otherwise return `nothing`. Each of `a` and `b` is a [`PointSet`](@ref) or an
[`AbstractPointValues`](@ref). This is the internal point-count check that the point-value
algebra and the transfer operators run before combining two operands.
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
    _point_value_shape(number_of_points, ::Val{R}) where {R}

Return the storage shape `(M, fiber_shape(Val(R))...)` of point values of tensor order `R` at
`M` points, where `M` is `number_of_points`.
"""
_point_value_shape(number_of_points::Integer, ::Val{R}) where {R} = (number_of_points, fiber_shape(Val(R))...)


"""
    similar_point_values(reference::AbstractPointValues, data)
    similar_point_values(reference::AbstractPointValues, ::Val{R}) where {R}

Allocate point values shaped like `reference`. The `data` form wraps the supplied array in a
point-value type of the same tensor order as `reference`. The `Val{R}` form allocates a fresh
`(M, fiber_shape(Val(R))...)` array of order `R` on `reference`'s backend, through `similar`, and wraps it. The
broadcast machinery and the allocating algebra wrappers use it to build their results.

!!! note "Deliberately not an extension of `Base.similar`"
    The reasoning is `similar_field`'s: `Base.similar`'s second argument means an element type
    or dimensions rather than a tensor order, `similar(q, Float32)` would read as a precision change
    the package never makes implicitly, and the `data` form wraps supplied storage rather than
    allocating.
"""
function similar_point_values end

similar_point_values(::ScalarPointValues, data::AbstractArray) = ScalarPointValues(data)
similar_point_values(::VectorPointValues, data::AbstractArray) = VectorPointValues(data)
similar_point_values(::TensorPointValues{R}, data::AbstractArray) where {R} = TensorPointValues{R}(data)

similar_point_values(reference::AbstractPointValues{T}, ::Val{0}) where {T<:AbstractFloat} =
  ScalarPointValues(similar(field_data(reference), T, _point_value_shape(npoints(reference), Val(0))))
similar_point_values(reference::AbstractPointValues{T}, ::Val{1}) where {T<:AbstractFloat} =
  VectorPointValues(similar(field_data(reference), T, _point_value_shape(npoints(reference), Val(1))))
similar_point_values(reference::AbstractPointValues{T}, ::Val{R}) where {T<:AbstractFloat, R} =
  TensorPointValues{R}(similar(field_data(reference), T, _point_value_shape(npoints(reference), Val(R))))



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

Broadcast style for point values, where `N` is one plus the tensor order — `1`, `2`, or `3` for
the `(M,)`, `(M, 3)` and `(M, 3, 3)` storage layouts at tensor orders `0`, `1` and `2`, and one more
dimension for each order above that. Inside a broadcast a point-value object
stands for its storage array, and this style materializes the result back into a point-value
object of the same order.
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
    _first_point_values(x)

Return the first [`AbstractPointValues`](@ref) found in `x` — a value, a `Broadcasted` tree, or
an argument tuple — or `nothing` when there is none. Out-of-place broadcasting uses it to seed
the allocated result.
"""
_first_point_values(values::AbstractPointValues) = values
_first_point_values(::Any) = nothing
_first_point_values(broadcasted::Base.Broadcast.Broadcasted) = _first_point_values(broadcasted.args)
_first_point_values(::Tuple{}) = nothing
function _first_point_values(args::Tuple)
  found = _first_point_values(first(args))
  return isnothing(found) ? _first_point_values(Base.tail(args)) : found
end


"""
    _check_broadcast_point_values_compatibility(destination, argument)

Check, during broadcasting, that `argument` covers the same number of points as `destination`,
recursing into a `Broadcasted` argument. Arguments that are not point values — real numbers,
fibers, or plain arrays — are accepted without a check.
"""
_check_broadcast_point_values_compatibility(destination::AbstractPointValues, values::AbstractPointValues) = _check_npoints_match(destination, values)
_check_broadcast_point_values_compatibility(::AbstractPointValues, ::Any) = nothing
function _check_broadcast_point_values_compatibility(destination::AbstractPointValues, broadcasted::Base.Broadcast.Broadcasted)
  foreach(argument -> _check_broadcast_point_values_compatibility(destination, argument), broadcasted.args)
  return nothing
end


"""
    _unwrap_point_values_argument(x)

Replace each point-value object in a broadcast expression with its storage array, recursing
through a `Broadcasted` tree, so that a point-value broadcast lowers to a plain array broadcast
on the backend.
"""
_unwrap_point_values_argument(values::AbstractPointValues) = field_data(values)
_unwrap_point_values_argument(argument) = argument
function _unwrap_point_values_argument(broadcasted::Base.Broadcast.Broadcasted)
  return Base.Broadcast.broadcasted(broadcasted.f, map(_unwrap_point_values_argument, broadcasted.args)...)
end


function Base.copyto!(destination::AbstractPointValues, broadcasted::Base.Broadcast.Broadcasted)
  _check_broadcast_point_values_compatibility(destination, broadcasted)
  unwrapped = _unwrap_point_values_argument(broadcasted)
  unwrapped_with_destination_axes = Base.Broadcast.Broadcasted(unwrapped.style, unwrapped.f, unwrapped.args, axes(field_data(destination)))
  _assign!(field_data(destination), unwrapped_with_destination_axes)
  return destination
end

function Base.copy(broadcasted::Base.Broadcast.Broadcasted{<:PointValuesBroadcastStyle})
  reference = _first_point_values(broadcasted)
  isnothing(reference) && throw(ArgumentError("broadcast expression does not contain point values"))
  destination = similar_point_values(reference, similar(field_data(reference)))
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

"""
    _check_combinable(values...)

Check that point-value operands may be added or subtracted: equal point count, tensor order and scalar
type, throwing otherwise.

A vector-space combination is only defined between sections of the same bundle, and the broadcast that
implements it is not fussy enough to say so. Two failures followed, both order-dependent, which is the
tell that no operation was being expressed. Mixed precision NARROWED toward the first operand, so
`a32 + a64` silently truncated a `Float64` operand while `a64 + a32` did not. Mixed tensor order was
accepted in one order — a scalar broadcast across a vector's fiber — and rejected in the other, so `+`
was not commutative; and adding a scalar section to a vector one is not in the method set for fields
either.
"""
function _check_combinable(values::AbstractPointValues...)
  first_values = first(values)
  for other in Base.tail(values)
    npoints(other) == npoints(first_values) ||
      throw(DimensionMismatch("point counts differ: $(npoints(first_values)) and $(npoints(other))"))
    point_value_tensor_order(other) == point_value_tensor_order(first_values) ||
      throw(DimensionMismatch("point-value tensor orders differ: " *
                              "$(point_value_tensor_order(first_values)) and $(point_value_tensor_order(other))"))
    eltype(field_data(other)) === eltype(field_data(first_values)) ||
      throw(ArgumentError("point-value scalar types differ: $(eltype(field_data(first_values))) and " *
                          "$(eltype(field_data(other))); a combination does not convert between precisions"))
  end
  return nothing
end


# Field-field combination (variadic) and its operators; reuse the FieldAlgebra n-ary reducers.
for (bang, operator, reducer) in ((:add!, :+, :_add_values), (:subtract!, :-, :_subtract_values))
  @eval function $bang(destination::AbstractPointValues, a::AbstractPointValues, b::AbstractPointValues, rest::AbstractPointValues...)
    _check_combinable(destination, a, b, rest...)
    destination .= $reducer.(a, b, rest...)
    return destination
  end

  @eval function $operator(a::AbstractPointValues, b::AbstractPointValues, rest::AbstractPointValues...)
    _check_combinable(a, b, rest...)
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
# The per-component contraction formulas and the fused values functions are imported from
# FiberSections and reused verbatim: the fused passes reach components/storage through the
# section interface above, so they apply to point values unchanged, alias-safe by construction
# (an element's reads precede its writes). Only the thin wrappers (point-count checks, the
# allocator) are point-value specific.

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

dot(u::VectorPointValues{T}, v::VectorPointValues{T}) where {T<:AbstractFloat} = dot!(similar_point_values(u, Val(0)), u, v)
dot(A::TensorPointValues{2, T}, B::TensorPointValues{2, T}) where {T<:AbstractFloat} = dot!(similar_point_values(A, Val(0)), A, B)

for (Operand, Constant) in ((:VectorPointValues, :FiberVector), (:(TensorPointValues{2}), :FiberTensor2))
  @eval function dot!(destination::ScalarPointValues{T}, operand::$Operand{T}, constant::$Constant{T}) where {T<:AbstractFloat}
    _check_npoints_match(destination, operand)
    return _dot_components_pv!(destination, operand, constant)
  end
  @eval dot!(destination::ScalarPointValues{T}, constant::$Constant{T}, operand::$Operand{T}) where {T<:AbstractFloat} =
    dot!(destination, operand, constant)
  @eval dot(operand::$Operand{T}, constant::$Constant{T}) where {T<:AbstractFloat} =
    dot!(similar_point_values(operand, Val(0)), operand, constant)
  @eval dot(constant::$Constant{T}, operand::$Operand{T}) where {T<:AbstractFloat} =
    dot!(similar_point_values(operand, Val(0)), operand, constant)
end


# --- Cross products (vector result; fused ⇒ alias-safe by construction) ---
function _cross_components_pv!(destination, u::VectorPointValues, v::VectorPointValues)
  one_value = one(_section_scalar_type(destination))
  _fiberwise_pass!(get_backend(point_values(destination)), _cross_values_ff,
                   ntuple(component -> _vector_component_data(destination, component), Val(3)),
                   (ntuple(component -> _vector_component_data(u, component), Val(3))..., ntuple(component -> _vector_component_data(v, component), Val(3))...), (), one_value, zero(one_value))
  return destination
end

function _cross_components_pv!(destination, u::VectorPointValues, a::FiberVector)
  one_value = one(_section_scalar_type(destination))
  _fiberwise_pass!(get_backend(point_values(destination)), _cross_values_fc,
                   ntuple(component -> _vector_component_data(destination, component), Val(3)),
                   ntuple(component -> _vector_component_data(u, component), Val(3)), (a,), one_value, zero(one_value))
  return destination
end

function _cross_components_pv!(destination, a::FiberVector, u::VectorPointValues)
  one_value = one(_section_scalar_type(destination))
  _fiberwise_pass!(get_backend(point_values(destination)), _cross_values_cf,
                   ntuple(component -> _vector_component_data(destination, component), Val(3)),
                   ntuple(component -> _vector_component_data(u, component), Val(3)), (a,), one_value, zero(one_value))
  return destination
end

function cross!(destination::VectorPointValues{T}, u::VectorPointValues{T}, v::VectorPointValues{T}) where {T<:AbstractFloat}
  _check_npoints_match(destination, u)
  _check_npoints_match(u, v)
  return _cross_components_pv!(destination, u, v)
end

cross(u::VectorPointValues{T}, v::VectorPointValues{T}) where {T<:AbstractFloat} = cross!(similar_point_values(u, Val(1)), u, v)

function cross!(destination::VectorPointValues{T}, u::VectorPointValues{T}, a::FiberVector{T}) where {T<:AbstractFloat}
  _check_npoints_match(destination, u)
  return _cross_components_pv!(destination, u, a)
end

function cross!(destination::VectorPointValues{T}, a::FiberVector{T}, u::VectorPointValues{T}) where {T<:AbstractFloat}
  _check_npoints_match(destination, u)
  return _cross_components_pv!(destination, a, u)
end

cross(u::VectorPointValues{T}, a::FiberVector{T}) where {T<:AbstractFloat} = cross!(similar_point_values(u, Val(1)), u, a)
cross(a::FiberVector{T}, u::VectorPointValues{T}) where {T<:AbstractFloat} = cross!(similar_point_values(u, Val(1)), a, u)


# --- Tensor-vector and tensor-tensor products (α/β; destination must not alias, like mul!) ---
function _tensor_vector_components_pv!(destination, A::TensorPointValues{2}, u::VectorPointValues, α_value, β_value)
  one_value = one(_section_scalar_type(destination))
  _fiberwise_pass!(get_backend(point_values(destination)), _tensor_vector_values_ff,
                   ntuple(component -> _vector_component_data(destination, component), Val(3)),
                   (ntuple(n -> _tensor2_component_data(A, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9))..., ntuple(component -> _vector_component_data(u, component), Val(3))...), (), α_value, β_value)
  return destination
end
function _tensor_vector_components_pv!(destination, A::TensorPointValues{2}, a::FiberVector, α_value, β_value)
  one_value = one(_section_scalar_type(destination))
  _fiberwise_pass!(get_backend(point_values(destination)), _tensor_vector_values_fc,
                   ntuple(component -> _vector_component_data(destination, component), Val(3)),
                   ntuple(n -> _tensor2_component_data(A, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9)), (a,), α_value, β_value)
  return destination
end
function _tensor_vector_components_pv!(destination, A::FiberTensor2, u::VectorPointValues, α_value, β_value)
  one_value = one(_section_scalar_type(destination))
  _fiberwise_pass!(get_backend(point_values(destination)), _tensor_vector_values_cf,
                   ntuple(component -> _vector_component_data(destination, component), Val(3)),
                   ntuple(component -> _vector_component_data(u, component), Val(3)), (A,), α_value, β_value)
  return destination
end
function _vector_tensor_components_pv!(destination, u::VectorPointValues, A::TensorPointValues{2}, α_value, β_value)
  one_value = one(_section_scalar_type(destination))
  _fiberwise_pass!(get_backend(point_values(destination)), _vector_tensor_values_ff,
                   ntuple(component -> _vector_component_data(destination, component), Val(3)),
                   (ntuple(component -> _vector_component_data(u, component), Val(3))..., ntuple(n -> _tensor2_component_data(A, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9))...), (), α_value, β_value)
  return destination
end
function _vector_tensor_components_pv!(destination, a::FiberVector, A::TensorPointValues{2}, α_value, β_value)
  one_value = one(_section_scalar_type(destination))
  _fiberwise_pass!(get_backend(point_values(destination)), _vector_tensor_values_cf,
                   ntuple(component -> _vector_component_data(destination, component), Val(3)),
                   ntuple(n -> _tensor2_component_data(A, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9)), (a,), α_value, β_value)
  return destination
end
function _vector_tensor_components_pv!(destination, u::VectorPointValues, A::FiberTensor2, α_value, β_value)
  one_value = one(_section_scalar_type(destination))
  _fiberwise_pass!(get_backend(point_values(destination)), _vector_tensor_values_fc,
                   ntuple(component -> _vector_component_data(destination, component), Val(3)),
                   ntuple(component -> _vector_component_data(u, component), Val(3)), (A,), α_value, β_value)
  return destination
end
function _tensor_tensor_components_pv!(destination, A::TensorPointValues{2}, B::TensorPointValues{2}, α_value, β_value)
  one_value = one(_section_scalar_type(destination))
  _fiberwise_pass!(get_backend(point_values(destination)), _tensor_tensor_values_ff,
                   ntuple(n -> _tensor2_component_data(destination, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9)),
                   (ntuple(n -> _tensor2_component_data(A, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9))..., ntuple(n -> _tensor2_component_data(B, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9))...), (), α_value, β_value)
  return destination
end
function _tensor_tensor_components_pv!(destination, A::TensorPointValues{2}, B::FiberTensor2, α_value, β_value)
  one_value = one(_section_scalar_type(destination))
  _fiberwise_pass!(get_backend(point_values(destination)), _tensor_tensor_values_fc,
                   ntuple(n -> _tensor2_component_data(destination, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9)),
                   ntuple(n -> _tensor2_component_data(A, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9)), (B,), α_value, β_value)
  return destination
end
function _tensor_tensor_components_pv!(destination, A::FiberTensor2, B::TensorPointValues{2}, α_value, β_value)
  one_value = one(_section_scalar_type(destination))
  _fiberwise_pass!(get_backend(point_values(destination)), _tensor_tensor_values_cf,
                   ntuple(n -> _tensor2_component_data(destination, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9)),
                   ntuple(n -> _tensor2_component_data(B, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9)), (A,), α_value, β_value)
  return destination
end

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
*(A::TensorPointValues{2, T}, a::FiberVector{T}) where {T<:AbstractFloat} = mul!(similar_point_values(A, Val(1)), A, a)
*(a::FiberVector{T}, A::TensorPointValues{2, T}) where {T<:AbstractFloat} = mul!(similar_point_values(A, Val(1)), a, A)
*(A::FiberTensor2{T}, u::VectorPointValues{T}) where {T<:AbstractFloat} = mul!(similar_point_values(u, Val(1)), A, u)
*(u::VectorPointValues{T}, A::FiberTensor2{T}) where {T<:AbstractFloat} = mul!(similar_point_values(u, Val(1)), u, A)
*(A::TensorPointValues{2, T}, u::VectorPointValues{T}) where {T<:AbstractFloat} = mul!(similar_point_values(u, Val(1)), A, u)
*(u::VectorPointValues{T}, A::TensorPointValues{2, T}) where {T<:AbstractFloat} = mul!(similar_point_values(u, Val(1)), u, A)
*(A::TensorPointValues{2, T}, B::TensorPointValues{2, T}) where {T<:AbstractFloat} = mul!(similar_point_values(A, Val(2)), A, B)
*(A::TensorPointValues{2, T}, B::FiberTensor2{T}) where {T<:AbstractFloat} = mul!(similar_point_values(A, Val(2)), A, B)
*(A::FiberTensor2{T}, B::TensorPointValues{2, T}) where {T<:AbstractFloat} = mul!(similar_point_values(B, Val(2)), A, B)


# --- Transpose (fused ⇒ alias-safe by construction) ---
function _transpose_components_pv!(destination, A)
  one_value = one(_section_scalar_type(destination))
  _fiberwise_pass!(get_backend(point_values(destination)), _transpose_values,
                   ntuple(n -> _tensor2_component_data(destination, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9)),
                   ntuple(n -> _tensor2_component_data(A, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9)), (), one_value, zero(one_value))
  return destination
end

function transpose!(destination::TensorPointValues{2, T}, A::TensorPointValues{2, T}) where {T<:AbstractFloat}
  _check_npoints_match(destination, A)
  return _transpose_components_pv!(destination, A)
end

transpose(A::TensorPointValues{2, T}) where {T<:AbstractFloat} = transpose!(similar_point_values(A, Val(2)), A)


# --- Norms (scalar result) ---
# Bodies from the shared `_norm_*_rhs` builders in FiberSections — the same the field norms use.
@eval _norm_components_pv!(destination, values::ScalarPointValues) = $(_scalar_kernel_body(_norm_scalar_rhs(:values)))
@eval _norm_components_pv!(destination, u::VectorPointValues) = $(_scalar_kernel_body(_norm_vector_rhs(:u, :field)))
@eval _norm_components_pv!(destination, A::TensorPointValues{2}) = $(_scalar_kernel_body(_norm_tensor_rhs(:A, :field)))

for Operand in (:ScalarPointValues, :VectorPointValues, :(TensorPointValues{2}))
  @eval function norm!(destination::ScalarPointValues{T}, operand::$Operand{T}) where {T<:AbstractFloat}
    _check_npoints_match(destination, operand)
    return _norm_components_pv!(destination, operand)
  end

  @eval norm(operand::$Operand{T}) where {T<:AbstractFloat} = norm!(similar_point_values(operand, Val(0)), operand)
end


# --- Trace (scalar result) ---
# Body from the shared `_trace_tensor_rhs` builder in FiberSections — the same the field trace uses.
@eval _trace_components_pv!(destination, A::TensorPointValues{2}) = $(_scalar_kernel_body(_trace_tensor_rhs(:A, :field)))

function tr!(destination::ScalarPointValues{T}, A::TensorPointValues{2, T}) where {T<:AbstractFloat}
  _check_npoints_match(destination, A)
  return _trace_components_pv!(destination, A)
end

tr(A::TensorPointValues{2, T}) where {T<:AbstractFloat} = tr!(similar_point_values(A, Val(0)), A)


# --- Determinant (scalar result) ---
# Body from the shared `_det_tensor_rhs` builder in FiberSections — the same the field determinant uses.
function _det_components_pv!(destination, A::TensorPointValues{2})
  one_value = one(_section_scalar_type(destination))
  _fiberwise_pass!(get_backend(point_values(destination)), _det_values,
                   (point_values(destination),),
                   ntuple(n -> _tensor2_component_data(A, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9)), (), one_value, zero(one_value))
  return destination
end

function det!(destination::ScalarPointValues{T}, A::TensorPointValues{2, T}) where {T<:AbstractFloat}
  _check_npoints_match(destination, A)
  return _det_components_pv!(destination, A)
end

det(A::TensorPointValues{2, T}) where {T<:AbstractFloat} = det!(similar_point_values(A, Val(0)), A)


# --- Symmetric / skew / deviatoric decompositions (fused; the values functions in FiberSections
# carry the shared formulas, the same the field decompositions use). An element's nine components
# are read into registers before any output is written, so the guard wrap is retired and `dev!`
# computes its trace per element instead of materializing it.
function _sym_components_pv!(destination, A)
  one_value = one(_section_scalar_type(destination))
  _fiberwise_pass!(get_backend(point_values(destination)), _sym_values,
                   ntuple(n -> _tensor2_component_data(destination, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9)),
                   ntuple(n -> _tensor2_component_data(A, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9)), (), one_value, zero(one_value))
  return destination
end

function _skew_components_pv!(destination, A)
  one_value = one(_section_scalar_type(destination))
  _fiberwise_pass!(get_backend(point_values(destination)), _skew_values,
                   ntuple(n -> _tensor2_component_data(destination, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9)),
                   ntuple(n -> _tensor2_component_data(A, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9)), (), one_value, zero(one_value))
  return destination
end

function _dev_components_pv!(destination, A)
  one_value = one(_section_scalar_type(destination))
  _fiberwise_pass!(get_backend(point_values(destination)), _dev_values,
                   ntuple(n -> _tensor2_component_data(destination, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9)),
                   ntuple(n -> _tensor2_component_data(A, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9)), (), one_value, zero(one_value))
  return destination
end

for (kernel, bang, allocating) in (
    (:_sym_components_pv!,  :sym!,  :sym),
    (:_skew_components_pv!, :skew!, :skew),
    (:_dev_components_pv!,  :dev!,  :dev),
  )

  @eval function $bang(destination::TensorPointValues{2, T}, A::TensorPointValues{2, T}) where {T<:AbstractFloat}
    _check_npoints_match(destination, A)
    return $kernel(destination, A)
  end

  @eval $allocating(A::TensorPointValues{2, T}) where {T<:AbstractFloat} = $bang(similar_point_values(A, Val(2)), A)
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

  @eval +(values::$PVType{T}, constant::$Constant{T}) where {T<:AbstractFloat} = add!(similar_point_values(values, Val($order)), values, constant)
  @eval +(constant::$Constant{T}, values::$PVType{T}) where {T<:AbstractFloat} = add!(similar_point_values(values, Val($order)), constant, values)
  @eval -(values::$PVType{T}, constant::$Constant{T}) where {T<:AbstractFloat} = subtract!(similar_point_values(values, Val($order)), values, constant)
  @eval -(constant::$Constant{T}, values::$PVType{T}) where {T<:AbstractFloat} = subtract!(similar_point_values(values, Val($order)), constant, values)
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

  @eval *(scalar_values::ScalarPointValues{T}, constant::$Constant{T}) where {T<:AbstractFloat} = multiply!(similar_point_values(scalar_values, Val($order)), scalar_values, constant)
  @eval *(constant::$Constant{T}, scalar_values::ScalarPointValues{T}) where {T<:AbstractFloat} = multiply!(similar_point_values(scalar_values, Val($order)), constant, scalar_values)
end


# --- Scalar point values × point values (singleton-fiber broadcast over all components) ---
_scalar_pv_broadcast_data(scalar_values::ScalarPointValues, values::AbstractPointValues) =
  reshape(field_data(scalar_values), size(field_data(scalar_values))..., ntuple(_ -> 1, point_value_tensor_order(values))...)

function _multiply_by_scalar_pv!(destination::AbstractPointValues, scalar_values::ScalarPointValues, values::AbstractPointValues)
  _check_npoints_match(destination, values)
  _check_npoints_match(scalar_values, values)
  # The DESTINATION'S ORDER, which the point count cannot speak for. Scaling by a scalar section is
  # order-preserving, so the destination must carry the same order as `values`. Checking only the
  # point count let a scalar × scalar product be written into a vector destination — where it was
  # broadcast over the fiber — and, worse, let a VECTOR result be written into a tensor destination,
  # which Julia's broadcasting expands along the trailing axis and returns as a wrong-shaped answer
  # rather than an error. Invariant 14 binds every argument of a multi-argument operation, the
  # destination of an in-place call included, and the field twin has always enforced exactly this
  # through `_check_field_compatibility`; these four signatures are documented as mirroring it.
  point_value_tensor_order(destination) == point_value_tensor_order(values) ||
    throw(ArgumentError("point-value tensor orders must be equal: the destination carries order " *
                        "$(point_value_tensor_order(destination)) and scaling by a scalar section " *
                        "preserves the order $(point_value_tensor_order(values)) of its operand"))
  @_assign! field_data(destination) .= _scalar_pv_broadcast_data(scalar_values, values) .* field_data(values)
  return destination
end

# The four dispatch signatures resolve the scalar×scalar ambiguity (mirroring FieldAlgebra).
multiply!(destination::AbstractPointValues, scalar_values::ScalarPointValues, values::AbstractPointValues) = _multiply_by_scalar_pv!(destination, scalar_values, values)
multiply!(destination::AbstractPointValues, values::AbstractPointValues, scalar_values::ScalarPointValues) = _multiply_by_scalar_pv!(destination, scalar_values, values)
multiply!(destination::ScalarPointValues, a::ScalarPointValues, b::ScalarPointValues) = _multiply_by_scalar_pv!(destination, a, b)
multiply!(destination::AbstractPointValues, a::ScalarPointValues, b::ScalarPointValues) = _multiply_by_scalar_pv!(destination, a, b)

*(scalar_values::ScalarPointValues{T}, values::AbstractPointValues{T}) where {T<:AbstractFloat} = multiply!(similar_point_values(values, similar(field_data(values))), scalar_values, values)
*(values::AbstractPointValues{T}, scalar_values::ScalarPointValues{T}) where {T<:AbstractFloat} = multiply!(similar_point_values(values, similar(field_data(values))), values, scalar_values)
*(a::ScalarPointValues{T}, b::ScalarPointValues{T}) where {T<:AbstractFloat} = multiply!(similar_point_values(a, similar(field_data(a))), a, b)


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
  # The destination's ORDER, for the same reason `_multiply_by_scalar_pv!` checks it: division by a
  # scalar section preserves the order, and the point count cannot speak for the fiber.
  point_value_tensor_order(destination) == point_value_tensor_order(values) ||
    throw(ArgumentError("point-value tensor orders must be equal: the destination carries order " *
                        "$(point_value_tensor_order(destination)) and division by a scalar section " *
                        "preserves the order $(point_value_tensor_order(values)) of its operand"))
  @_assign! field_data(destination) .= field_data(values) ./ _scalar_pv_broadcast_data(scalar_values, values)
  return destination
end

function divide!(destination::ScalarPointValues, scalar::Real, scalar_values::ScalarPointValues)
  destination .= scalar ./ scalar_values
  return destination
end

/(values::AbstractPointValues{T}, scalar_values::ScalarPointValues{T}) where {T<:AbstractFloat} = divide!(similar_point_values(values, similar(field_data(values))), values, scalar_values)
/(scalar::Real, scalar_values::ScalarPointValues{T}) where {T<:AbstractFloat} = divide!(similar_point_values(scalar_values, similar(field_data(scalar_values))), scalar, scalar_values)
/(a::FiberVector{T}, scalar_values::ScalarPointValues{T}) where {T<:AbstractFloat} = divide!(similar_point_values(scalar_values, Val(1)), a, scalar_values)
/(A::FiberTensor2{T}, scalar_values::ScalarPointValues{T}) where {T<:AbstractFloat} = divide!(similar_point_values(scalar_values, Val(2)), A, scalar_values)


# The grid↔point transfer (interpolation `f(x)` / `interpolate` and its adjoint `anterpolate`) lives
# in the `Interpolation` module; `Points` owns only the point-data types and their fiberwise algebra.
# See the module docstring and docs/ARCHITECTURE.md §10.

# --- HDF5 persistence: bare generics declared here so `?write_points` and the docs work without HDF5
# present; the methods (on `HDF5.File` / `Group`) live in `ext/GBGPeriodicFieldsHDF5Ext.jl`, loaded
# automatically when the HDF5 package is. The field pair is `write_field`/`read_field` in `Fields`. ---

"""
    write_points(parent::HDF5.H5DataStore, name::AbstractString, points::PointSet)
    write_points(parent::HDF5.H5DataStore, name::AbstractString,
                 values::AbstractPointValues)

Persist a point object — a [`PointSet`](@ref) of positions, or any of the three point-value types — as a
**new HDF5 group** `name` under `parent`, returning the group it created. Use it to checkpoint the
unstructured base and its samples for restart, or to hand them to another tool; the reload with
[`read_points`](@ref) is exact. It is the point-layer twin of `write_field`, which persists a field.

The group is **self-describing**: the numeric array becomes the dataset `data`, and the metadata become
attributes — a `type` tag, a schema `version`, the element type, the point count, and, for point values,
the tensor order — so any HDF5 tool can read it. A device (GPU) array is copied to the host on write.
The sugar `parent[name] = points` is equivalent.

Positions and values are written **separately**, one group each, because they are separate objects: a
`PointSet` is the base, and point values are sections over it. A consumer that wants them together writes
both under one parent group, which also lets several value sets share one stored set of positions.

Because `parent` is a handle you opened and own, this never opens or closes a file, and the package
attaches no notion of time — the consumer bundles a snapshot and owns any `time` / `iteration`
attributes.

The arguments are:
- `parent` — an open HDF5 `File` or `Group` to create the new subgroup under.
- `name` — the name of the group to create.
- `points`, `values` — the `PointSet` or point-value section to write.

Provided by a package extension, so it is available only when [`HDF5.jl`](https://github.com/JuliaIO/HDF5.jl) is loaded.
"""
function write_points end


"""
    read_points(parent::HDF5.H5DataStore, name::AbstractString)

Reconstruct the point object written by [`write_points`](@ref) from the HDF5 group `name` under `parent`,
dispatching on the stored `type` attribute to return it in the matching type ([`PointSet`](@ref),
[`ScalarPointValues`](@ref), [`VectorPointValues`](@ref), [`TensorPointValues`](@ref)). The reload is
**exact** — the array data, the element type, the point count, and the tensor order are recovered
bit-for-bit. It is the point-layer twin of `read_field`.

The reconstructed object is a host (CPU) one regardless of where the written one lived; move it to a
device with [`adapt`](@ref) or [`adapt!`](@ref) afterward if needed.

Here `parent` is an open HDF5 `File` or `Group` holding the group, and `name` is the name (or path)
of that group under `parent`.

Provided by a package extension, so it is available only when [`HDF5.jl`](https://github.com/JuliaIO/HDF5.jl) is loaded.
"""
function read_points end


# --- map! / map (arbitrary φ) — the point-value peer of the FieldAlgebra methods, reusing the shared
# `_map_pass!` driver over the same fused executor; point-values are representation-free, so no
# physical-only restriction applies. The one docstring lives on the FieldAlgebra binding. ---
function map!(φ::F, destination::AbstractPointValues, sources::AbstractPointValues...) where {F}
  _refuse_field_as_fiber_map(φ)
  _check_map_not_aliased(φ, destination)
  for source in sources
    _check_npoints_match(destination, source)
  end
  return _map_pass!(φ, destination, sources, true, false)
end

function map!(φ::F, destination::AbstractPointValues, source::AbstractPointValues,
              α::Real, β::Real) where {F}
  _refuse_field_as_fiber_map(φ)
  _check_map_not_aliased(φ, destination)
  _check_npoints_match(destination, source)
  return _map_pass!(φ, destination, (source,), α, β)
end

function map(φ::F, source1::AbstractPointValues, sources::AbstractPointValues...) where {F}
  _refuse_field_as_fiber_map(φ)
  all_sources = (source1, sources...)
  order = _map_output_order(φ, all_sources)
  order ≥ 0 ||
    throw(ArgumentError("map: could not infer the output tensor order of `φ`; call `map!` with a preallocated `destination` instead"))
  destination = similar_point_values(source1, Val(order))
  return map!(φ, destination, all_sources...)
end



####################################
#        Base-space motion         #
####################################
#
# The one operation family that couples the base and the fiber: displacement of the point BASE
# along vector-valued sections over it. On this package's flat periodic base the tangent space at
# every point is canonically the fiber's Cartesian R^3 (one global orthonormal frame, ARCHITECTURE
# §2), so "move a point along a vector value" needs no connection machinery: it is coordinate
# addition in the universal cover R^3 and, when the periodic domain is supplied, reduction to the
# fundamental domain [o, o + L). The fiberwise algebra deliberately excludes positions (a `Point`
# names a location, not a value — the role split); displacement is the named crossing of that
# split, not an algebra on it, which is why there is no `PointSet + VectorPointValues` method.

using ..Fields: Grid3D   # the periodic-domain carrier; only `domain_size` and `origin` enter here


"""
    _displacement_rhs(base, terms...)

Fold the displacement terms into one lazy broadcast expression ``\\texttt{base} + \\sum_j c_j
v_j`` — the argument `base` is a coordinate array (or a lazy expression over one) and each
element of `terms` is a `(coefficient, data)` tuple whose parts are already converted and
unwrapped. The recursion keeps the term count in the type domain, so the fused pass specializes
per arity and allocates nothing. The public methods name the vararg count `N` in their
signatures because Julia does not specialize an unbounded `Vararg` that is only forwarded —
the same trap as the forwarded-`Function` spelling pinned in `test/allocations.jl` — and
without it a three-term call boxed per element.
"""
_displacement_rhs(base) = base
_displacement_rhs(base, term, rest...) =
  _displacement_rhs(Base.Broadcast.broadcasted(+, base,
                      Base.Broadcast.broadcasted(*, first(term), last(term))), rest...)


"""
    _wrap_coordinate(coordinate, extent, origin)

Reduce one coordinate to its canonical representative in the fundamental domain
``[\\texttt{origin}, \\texttt{origin} + \\texttt{extent})``. Floating-point `mod` can return
exactly `extent` for a coordinate a hair below `origin` (measured: `mod(-1e-20, 2π) === 2π`), so
the excluded endpoint is folded back explicitly; the fold tests equality with `extent` rather
than an order comparison, because an order test is false for a non-finite coordinate and would
silently rewrite a diverged trajectory into a tidy in-box position. A non-finite coordinate
therefore passes through non-finite (`mod` sends an infinity to `NaN`).
"""
@inline function _wrap_coordinate(coordinate::T, extent::T, origin::T) where {T<:AbstractFloat}
  offset = mod(coordinate - origin, extent)
  offset = ifelse(offset == extent, zero(T), offset)
  return offset + origin
end


"""
    _convert_terms(::Type{T}, terms...)

Convert each `(coefficient, section)` displacement term to `(T(coefficient), data)` by recursion
over the tuple rather than by a `map` closure: a closure would capture the type `T` as a
`DataType` field and heap-allocate itself per call, which is the 32-byte residue the allocation
audit would flag.
"""
_convert_terms(::Type{T}) where {T} = ()
_convert_terms(::Type{T}, term, rest...) where {T} =
  ((T(first(term)), point_values(last(term))), _convert_terms(T, rest...)...)


"""
    _axis_terms(axis, terms...)

Take the `axis` column view of each converted term's data, keeping the coefficient — the
per-axis operands of the fused displace-and-wrap pass. Recursion for the same reason as
[`_convert_terms`](@ref): a specialized tuple in, a specialized tuple out, nothing boxed.
"""
_axis_terms(axis::Int) = ()
_axis_terms(axis::Int, term, rest...) =
  ((first(term), view(last(term), :, axis)), _axis_terms(axis, rest...)...)


"""
    _motion_storage_family(array)

Identify the array's storage family by the unparameterized name of its parent's type — `Array`,
`CuArray`, `ROCArray` — the same compile-time comparison `Fields` uses, restated here on a raw
array because a `PointSet` is not a section and carries no `field_data`.
"""
_motion_storage_family(array) = Base.typename(typeof(parent(array))).wrapper


"""
    _check_displacement_compatibility(destination, source, sections)

Require the point count, scalar type and storage family of `source` and of every displacement
section to match `destination`'s, refusing with a clear `ArgumentError` rather than promoting or
transferring (invariant 14). The refusal is the package's decision, not the launch layer's: the
torus path assembles per-axis views and so bypasses the broadcast machinery's own enforcement,
and a mixed host/device pair must fail identically on every path.
"""
function _check_displacement_compatibility(destination::PointSet, source::PointSet, sections)
  _check_npoints_match(destination, source)
  family = _motion_storage_family(point_positions(destination))
  eltype(point_positions(source)) === eltype(point_positions(destination)) ||
    throw(ArgumentError("point-set scalar types differ: $(eltype(point_positions(destination))) and " *
                        "$(eltype(point_positions(source))); displacement does not convert between precisions"))
  _motion_storage_family(point_positions(source)) === family ||
    throw(ArgumentError("point sets must live in the same storage family; got " *
                        "$(family) and $(_motion_storage_family(point_positions(source)))"))
  for section in sections
    _check_npoints_match(destination, section)
    eltype(field_data(section)) === eltype(point_positions(destination)) ||
      throw(ArgumentError("a displacement section's scalar type $(eltype(field_data(section))) does not " *
                          "match the point set's $(eltype(point_positions(destination))); displacement " *
                          "does not convert between precisions"))
    _motion_storage_family(field_data(section)) === family ||
      throw(ArgumentError("a displacement section must live in the point set's storage family; got " *
                          "$(_motion_storage_family(field_data(section))) against $(family)"))
  end
  return nothing
end


"""
    _check_displacement_domain(points, grid)

Require the periodic domain's element type to match the point set's, refusing a mixed-precision
pair rather than promoting (invariant 14 binds the non-section partners too — a `Grid3D` here
plays the role `FieldSpectralMultipliers` plays for a spectral field).
"""
function _check_displacement_domain(points::PointSet, grid::Grid3D)
  T = eltype(point_positions(points))
  grid isa Grid3D{T} ||
    throw(ArgumentError("the domain's element type $(eltype(grid.domain_size)) does not match the " *
                        "point set's $(T); displacement does not convert between precisions"))
  return nothing
end


"""
    displace!(destination::PointSet, source::PointSet, terms...)
    displace!(destination::PointSet, source::PointSet, grid::Grid3D, terms...)
    displace!(points::PointSet, [grid::Grid3D,] terms...)

Move each point of a point set along the weighted sum of vector values over it: writing ``x_p``
for the position of point ``p`` and ``v_j(p)`` for the value the ``j``-th section holds at that
point,

```math
x_p \\leftarrow x_p + \\sum_j c_j v_j(p) .
```

Each element of `terms` is a tuple `(coefficient, section)`: the ``j``-th term supplies **one**
host scalar ``c_j`` — a single number, applied to every point, not a per-point array — and one
[`VectorPointValues`](@ref) section ``v_j``, which does hold one vector per point. The subscript
``j`` counts the terms of the call, so a two-term call has ``c_1, c_2`` and ``v_1, v_2``. All
terms are applied in **one fused traversal**: the
positions are read once, each section once, and the positions written once, on CPU and GPU alike.
This is the one operation that crosses the position-versus-value role split, and it is a named
operation rather than a `+` method because positions are points of the periodic domain, not
vectors: what is being applied is a displacement, exact because the domain is flat and the fiber
carries one global frame.

Without a `grid` the sum is taken literally, in the universal cover — the unwrapped picture of the
torus, in which a coordinate keeps growing instead of folding back: coordinates may leave the
box, and sampling such positions remains correct because the transfer kernels wrap their stencil
indices periodically. With a `grid` the displaced coordinates are additionally reduced,
componentwise and in the same fused pass, to the canonical representative in the fundamental
domain — the same reduction [`wrap!`](@ref) applies on its own, whose docstring states the
endpoint and non-finite contract. Displacement on the periodic domain proper is the `grid` form;
the grid-free form is its lift to the cover, which preserves winding information (a
mean-square-displacement diagnostic needs the unwrapped trajectory).

The arguments are:
- `destination` — the [`PointSet`](@ref) receiving the displaced positions. It may be the `source`
  itself (the two-argument convenience forms are exactly that call): the pass reads each
  element's inputs before writing its outputs, so the aliased call is computed directly.
- `source` — the `PointSet` holding the starting positions. When omitted, `points` is both
  source and destination.
- `grid` — optional; a [`Grid3D`](@ref) supplying the periodic domain. Only its
  `domain_size` and `origin` enter: the wrap needs the box, not the mesh.
- `terms...` — zero or more `(coefficient, section)` tuples, each pairing one real number
  with one section. The coefficients are part of
  what the operation *is* — the displacement ``\\sum_j c_j v_j`` — so they are named
  coefficients rather than the α/β accumulation scalars of invariant 10, and there is no
  trailing α/β pair. With no terms the call copies (and, with a `grid`, wraps) the source
  positions.

There is deliberately no allocating sibling: displacement is motion of an existing base, and a
freshly allocated destination would have no consumer. Sections and point sets must agree in
point count, scalar type and storage family; a mixed pair is refused, never converted.
"""
function displace! end

function displace!(destination::PointSet, source::PointSet,
                   terms::Vararg{Tuple{Real, <:VectorPointValues}, N}) where {N}
  _check_displacement_compatibility(destination, source, map(last, terms))
  converted = _convert_terms(eltype(point_positions(destination)), terms...)
  rhs = _displacement_rhs(point_positions(source), converted...)
  broadcasted = rhs isa Base.Broadcast.Broadcasted ? rhs : Base.Broadcast.broadcasted(identity, rhs)
  _assign!(point_positions(destination), broadcasted)
  return destination
end

function displace!(destination::PointSet, source::PointSet, grid::Grid3D,
                   terms::Vararg{Tuple{Real, <:VectorPointValues}, N}) where {N}
  _check_displacement_compatibility(destination, source, map(last, terms))
  _check_displacement_domain(destination, grid)
  converted = _convert_terms(eltype(point_positions(destination)), terms...)
  destination_coordinates = point_positions(destination)
  source_coordinates = point_positions(source)
  # Column-wise so each axis sees its own extent and origin as plain scalars; the columns are
  # contiguous (SoA, fiber-last), so the three passes together still read and write each element
  # exactly once — one-traversal traffic, with the wrap fused into the displacement.
  for axis in 1:3
    axis_terms = _axis_terms(axis, converted...)
    rhs = _displacement_rhs(view(source_coordinates, :, axis), axis_terms...)
    _assign!(view(destination_coordinates, :, axis),
             Base.Broadcast.broadcasted(_wrap_coordinate, rhs,
                                        grid.domain_size[axis], grid.origin[axis]))
  end
  return destination
end

displace!(points::PointSet, terms::Vararg{Tuple{Real, <:VectorPointValues}, N}) where {N} =
  displace!(points, points, terms...)
displace!(points::PointSet, grid::Grid3D, terms::Vararg{Tuple{Real, <:VectorPointValues}, N}) where {N} =
  displace!(points, points, grid, terms...)


"""
    wrap!(points::PointSet, grid::Grid3D)

Reduce every position to its canonical representative in the periodic domain: componentwise,

```math
x_{p,a} \\leftarrow \\operatorname{mod}(x_{p,a} - o_a,\\ L_a) + o_a ,
```

which lands each coordinate in the half-open fundamental domain ``[o_a, o_a + L_a)``, where
``L_a`` is the domain extent along axis ``a`` and ``o_a`` the domain origin — both read from
`grid`, whose mesh plays no role. Wrapping is never required for sampling — the transfer kernels
wrap their stencil indices, so interpolation is invariant under shifting any coordinate by whole
periods — but it is the operation that keeps coordinates bounded over a long run (absolute
floating-point resolution degrades as a coordinate grows, single precision especially) and that
presents in-box positions to a consumer bucketing by cell index. It discards winding: a
mean-square-displacement diagnostic must run on unwrapped positions, which is why displacement
and wrapping are separate operations rather than one.

!!! warning "The endpoint is folded, and non-finite coordinates pass through non-finite"
    Floating-point `mod` can return exactly ``L_a`` for a coordinate a hair below the origin
    (measured: `mod(-1e-20, 2π) === 2π`), so the excluded endpoint is folded back to ``o_a``
    explicitly. The fold tests equality rather than order, because an order test is false for
    `NaN` and `Inf` and would silently rewrite a diverged trajectory into a tidy in-box
    position — a non-finite coordinate comes out non-finite (an infinity as `NaN`, `mod`'s own
    image of it), never boxed.

The reduction runs in place and returns `points`. The domain's element type must match the point
set's; a mixed pair is refused, never converted. To wrap in the same pass as a displacement, use
the `grid` form of [`displace!`](@ref).
"""
function wrap!(points::PointSet, grid::Grid3D)
  _check_displacement_domain(points, grid)
  coordinates = point_positions(points)
  for axis in 1:3
    column = view(coordinates, :, axis)
    _assign!(column, Base.Broadcast.broadcasted(_wrap_coordinate, column,
                                                grid.domain_size[axis], grid.origin[axis]))
  end
  return points
end


###################################################
#   Moving between storage families (Adapt.jl)    #
###################################################

# The point twins of the field methods in `Fields`. `similar_point_values` carries whatever the
# section holds besides its storage, exactly as `similar_field` does; a `PointSet` holds only its
# coordinates, so it is rebuilt through its own constructor. The documentation for the whole family
# lives on `adapt` in `Fields`.
adapt_structure(to, values::AbstractPointValues) =
  similar_point_values(values, adapt(to, point_values(values)))

adapt_structure(to, point_set::PointSet) = PointSet(adapt(to, point_positions(point_set)))


# The point twins of `adapt!`, whose documentation lives with the generic in `Fields`. A point section
# carries no grid or layout, so the only thing a move must preserve besides the values is the point
# count — `_check_npoints_match` is the check the rest of this module already routes through, and a
# tensor-order mismatch has no method rather than an error, exactly as a representation mismatch does
# on the field side. Decision 69.
function adapt!(destination::AbstractPointValues{T, R}, source::AbstractPointValues{T, R}) where {T, R}
  point_values(destination) === point_values(source) && return destination
  _check_npoints_match(destination, source)
  copyto!(point_values(destination), point_values(source))
  return destination
end

function adapt!(destination::PointSet, source::PointSet)
  point_positions(destination) === point_positions(source) && return destination
  # `DimensionMismatch`, not `ArgumentError`: a point-count mismatch is what this module already
  # throws that for (`_check_npoints_match`), and the two point methods should not disagree.
  npoints(destination) == npoints(source) ||
    throw(DimensionMismatch("point counts differ: $(npoints(destination)) and $(npoints(source))"))
  copyto!(point_positions(destination), point_positions(source))
  return destination
end


end # module Points
