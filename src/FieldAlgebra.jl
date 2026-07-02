"""
    FieldAlgebra

Fiberwise and pointwise algebra for the scalar, vector, and second-order tensor fields defined in
[`Fields`](@ref). Each operation comes as an allocating form (a `Base`/`LinearAlgebra` operator where one
exists) and an in-place `!` form. The families:

  * **Vector-space** — `add!`/`subtract!` (`+`/`-`), real scaling, and scalar-field
    multiplication/division (`multiply!`/`divide!`, `*`/`/`).
  * **Contractions** — `dot!`/`dot` (vector Euclidean and tensor Frobenius inner products, `⋅`) and
    `cross!`/`cross` (`×`).
  * **Tensor products** — `mul!` for tensor·vector (left and right action) and tensor·tensor, with the
    five-argument `α`/`β` accumulation form; allocating `*`.
  * **Permutations and decompositions** — `transpose!`/`transpose`, and `sym`/`skew`/`dev` (with `!` forms).
  * **Norms** — `norm!`/`norm` (pointwise absolute value, Euclidean, and Frobenius).

Field-field and field-constant operations preserve the representation of their arguments: they act
pointwise on fields in physical-space representation and coefficient-wise on fields in spectral
representation. Operations that are not linear in a field argument (for example multiplying two fields
together, or contracting two fields) are defined only in physical-space representation, except where one
factor is a compile-time constant fiber, which keeps the operation coefficient-wise; missing combinations
are deliberate. **Aliasing:** `mul!` follows the `LinearAlgebra` convention — the
destination must not share storage with an input — while the index-shuffling operations (`cross`,
`transpose`, `sym`/`skew`/`dev`) are alias-guarded and may be called with the destination aliasing an input.

Most of the method families below are emitted by small code generators defined in the "Code generation"
section: the per-component formulas are written once, and the generators stamp out the representation,
argument-order, and in-place/allocating variants.
"""
module FieldAlgebra


using ..Fields:
  FiberVector,
  FiberTensor2,
  AbstractField,
  AbstractFieldPhysical,
  AbstractFieldSpectral,
  ScalarFieldPhysical,
  ScalarFieldSpectral,
  VectorFieldPhysical,
  VectorFieldSpectral,
  TensorFieldPhysical,
  TensorFieldSpectral,
  field_data,
  field_grid,
  field_layout,
  field_scalar_type,
  field_tensor_order,
  similar_field,
  check_field_compatibility,
  _check_field_domain_compatibility,
  _vector_component_data,
  _tensor2_component_data


using ..FiberSections:
  section_scalar_type,
  _assign!,
  _to_broadcasted,
  @_assign!,
  _add_values,
  _subtract_values,
  _vector_component,
  _tensor_component,
  _sum_terms,
  _product,
  _vector_kernel_body,
  _tensor_kernel_body,
  _scalar_kernel_body,
  _dot_vector_rhs,
  _dot_tensor_rhs,
  _cross_formula,
  _tensor_vector_formula,
  _vector_tensor_formula,
  _tensor_tensor_formula,
  _transpose_formula,
  _norm_scalar_rhs,
  _norm_vector_rhs,
  _norm_tensor_rhs,
  _sym_kernel_body,
  _skew_kernel_body,
  _dev_kernel_body


import Base: +, -, *, /, transpose
import LinearAlgebra: dot, ⋅, cross, ×, mul!, transpose!, norm


export add!,
       subtract!,
       multiply!,
       divide!,
       dot!,
       dot,
       ⋅,
       cross!,
       cross,
       ×,
       mul!,
       transpose!,
       norm!,
       norm,
       sym!,
       sym,
       skew!,
       skew,
       dev!,
       dev


#####################################################
#        Internal Field Data Utilities              #
#####################################################


"""
    _copy_field_data!(destination::AbstractField, field::AbstractField)

Copy `field`'s storage into `destination`'s storage unless they already alias; returns `destination`. Used by copy-then-kernel paths that must not assume the destination begins empty.
"""
function _copy_field_data!(destination::AbstractField, field::AbstractField)
  destination_data = field_data(destination)
  field_data_source = field_data(field)

  destination_data === field_data_source || copyto!(destination_data, field_data_source)

  return destination
end


"""
    _spectral_constant_scale(field::AbstractFieldSpectral)

Return `prod(grid_size)`, the factor by which a physical constant scales the zero Fourier coefficient under the unnormalized-forward FFT convention. Adding a real constant in spectral representation multiplies it by this scale and writes only the zero mode.
"""
_spectral_constant_scale(field::AbstractFieldSpectral{T}) where {T<:AbstractFloat} = prod(T.(field_grid(field).grid_size))


"""
    _spectral_zero_mode_data(field::ScalarFieldSpectral)

Return a `1×1×1` view of the zero Fourier coefficient of a scalar field in spectral representation; constant additions in spectral representation write only here.
"""
_spectral_zero_mode_data(field::ScalarFieldSpectral) = view(field_data(field), 1:1, 1:1, 1:1)


"""
    _spectral_zero_mode_component_data(field::VectorFieldSpectral, component)
    _spectral_zero_mode_component_data(field::TensorFieldSpectral{2}, first_index, second_index)

Return a `1×1×1` view of the zero Fourier coefficient of one component of a vector or second-order tensor field in spectral representation.
"""
_spectral_zero_mode_component_data(field::VectorFieldSpectral, component) = view(field_data(field), 1:1, 1:1, 1:1, component:component)

_spectral_zero_mode_component_data(field::TensorFieldSpectral{2}, first_index, second_index) = view(field_data(field), 1:1, 1:1, 1:1, first_index:first_index, second_index:second_index)


"""
    _aliases_destination(destination, operands...)

Return `true` if `destination` shares its backing array with any field among `operands`. Constant fibers are not fields and never alias. Used by `_guard_noalias!`.
"""
_aliases_destination(destination, operands...) = any(operand -> (operand isa AbstractField) && (field_data(operand) === field_data(destination)), operands)


"""
    _guard_noalias!(kernel!, destination, output_order::Val, operands::Tuple)

Run `kernel!(destination, operands...)` while protecting against destination/input aliasing. If `destination` aliases any field in `operands`, run the kernel into a fresh field of tensor order `output_order` and copy the result back; otherwise run in place. Used by index-shuffling operations (cross product, transpose, sym/skew/dev) that read several source components while writing each destination component. `mul!` deliberately skips this guard and documents the no-alias requirement instead, matching the LinearAlgebra convention.
"""
function _guard_noalias!(kernel!, destination, output_order::Val, operands::Tuple)
  if _aliases_destination(destination, operands...)
    temporary = similar_field(destination, output_order)
    kernel!(temporary, operands...)
    copyto!(field_data(destination), field_data(temporary))
    return destination
  end
  return kernel!(destination, operands...)
end




"""
    _scalar_field_broadcast_data(scalar_field::ScalarFieldPhysical, field::AbstractFieldPhysical)

Reshape a scalar field's data with singleton fiber dimensions so it broadcasts against the fiber components of `field`. Used by pointwise scalar-field multiplication and division so the scalar acts on every component.
"""
function _scalar_field_broadcast_data(scalar_field::ScalarFieldPhysical, field::AbstractFieldPhysical)
  singleton_fiber_shape = ntuple(_ -> 1, field_tensor_order(field))
  return reshape(field_data(scalar_field), size(field_data(scalar_field))..., singleton_fiber_shape...)
end




#####################################################
#        Field Addition and Subtraction             #
#####################################################


"""
    add!(destination, a, b, fields...)
    add!(destination, field, constant)
    add!(destination, constant, field)

Add fields, or a field and a constant, in place; returns `destination`.

Field-field addition is storage-wise and representation-preserving: pointwise for fields in physical-space representation and coefficient-wise for fields in spectral representation.

The constant variants pair a scalar field with a `Real`, a vector field with a `FiberVector`, and a second-order tensor field with a `FiberTensor2`, in either argument order. In physical-space representation the constant is added at every grid point; in spectral representation only the zero Fourier coefficient changes, scaled by the inverse-transform normalisation, so that the physical values shift by exactly the constant.
"""
function add! end


"""
    subtract!(destination, a, b, fields...)
    subtract!(destination, field, constant)
    subtract!(destination, constant, field)

Subtract fields, or a field and a constant, in place; returns `destination`.

Field-field subtraction computes `a - b - fields...`, storage-wise and representation-preserving. The constant variants mirror [`add!`](@ref) — a `Real` for scalar fields, a `FiberVector` for vector fields, a `FiberTensor2` for second-order tensor fields — acting on every grid point in physical-space representation and on the zero Fourier coefficient only in spectral representation. The reversed argument order computes `constant - field`.
"""
function subtract! end


# Zero-mode updates adding a real constant to a spectral scalar field.
function _add_scalar_constant!(field::ScalarFieldSpectral{T}, scalar::Real) where {T<:AbstractFloat}
  _spectral_zero_mode_data(field) .+= _spectral_constant_scale(field) * T(scalar)
  return field
end


function _subtract_scalar_constant!(field::ScalarFieldSpectral{T}, scalar::Real) where {T<:AbstractFloat}
  _spectral_zero_mode_data(field) .-= _spectral_constant_scale(field) * T(scalar)
  return field
end


# Constant-fiber update kernels. The update statement is written once per
# operation and stamped out for the three vector / nine tensor components.
# Physical-space methods update every grid point; spectral methods touch only
# the zero Fourier coefficient, scaled by the inverse-transform normalisation.
for (kernel, update) in (
    (:_add_fiber_vector!,      (target, value) -> :($target .+= $value)),
    (:_subtract_fiber_vector!, (target, value) -> :($target .-= $value)),
  )

  @eval function $kernel(field::VectorFieldPhysical{T}, a::FiberVector{T}) where {T<:AbstractFloat}
    $([update(:(_vector_component_data(field, $i)), :(a[$i])) for i in 1:3]...)
    return field
  end

  @eval function $kernel(field::VectorFieldSpectral{T}, a::FiberVector{T}) where {T<:AbstractFloat}
    scale = _spectral_constant_scale(field)
    $([update(:(_spectral_zero_mode_component_data(field, $i)), :(scale * a[$i])) for i in 1:3]...)
    return field
  end
end


for (kernel, update) in (
    (:_add_fiber_tensor2!,      (target, value) -> :($target .+= $value)),
    (:_subtract_fiber_tensor2!, (target, value) -> :($target .-= $value)),
  )

  @eval function $kernel(field::TensorFieldPhysical{2, T}, A::FiberTensor2{T}) where {T<:AbstractFloat}
    $([update(:(_tensor2_component_data(field, $i, $j)), :(A[$i, $j])) for i in 1:3 for j in 1:3]...)
    return field
  end

  @eval function $kernel(field::TensorFieldSpectral{2, T}, A::FiberTensor2{T}) where {T<:AbstractFloat}
    scale = _spectral_constant_scale(field)
    $([update(:(_spectral_zero_mode_component_data(field, $i, $j)), :(scale * A[$i, $j])) for i in 1:3 for j in 1:3]...)
    return field
  end
end


# Field-field combination and its operators: the bodies are identical for the
# two representations (the broadcast machinery enforces compatibility), so each
# operation contributes one row and the loop stamps out the representation variants.
for (bang, operator, reducer) in ((:add!, :+, :_add_values), (:subtract!, :-, :_subtract_values))
  for Representation in (:AbstractFieldPhysical, :AbstractFieldSpectral)

    @eval function $bang(destination::$Representation, a::$Representation, b::$Representation, fields::$Representation...)
      destination .= $reducer.(a, b, fields...)
      return destination
    end

    @eval function $operator(a::$Representation, b::$Representation, fields::$Representation...)
      return $reducer.(a, b, fields...)
    end
  end
end


+(field::AbstractField) = field


function -(field::AbstractField)
  return (-).(field)
end


# Scalar field ± real number. Kept explicit: the physical-space methods are plain
# broadcasts, the spectral methods touch only the zero mode after copying, and
# the reversed subtraction is its own operation rather than a delegation.
function add!(destination::ScalarFieldPhysical, field::ScalarFieldPhysical, scalar::Real)
  destination .= field .+ scalar
  return destination
end


add!(destination::ScalarFieldPhysical, scalar::Real, field::ScalarFieldPhysical) = add!(destination, field, scalar)


function add!(destination::ScalarFieldSpectral, field::ScalarFieldSpectral, scalar::Real)
  check_field_compatibility(destination, field)
  _copy_field_data!(destination, field)
  return _add_scalar_constant!(destination, scalar)
end


add!(destination::ScalarFieldSpectral, scalar::Real, field::ScalarFieldSpectral) = add!(destination, field, scalar)


function subtract!(destination::ScalarFieldPhysical, field::ScalarFieldPhysical, scalar::Real)
  destination .= field .- scalar
  return destination
end


function subtract!(destination::ScalarFieldPhysical, scalar::Real, field::ScalarFieldPhysical)
  destination .= scalar .- field
  return destination
end


function subtract!(destination::ScalarFieldSpectral, field::ScalarFieldSpectral, scalar::Real)
  check_field_compatibility(destination, field)
  _copy_field_data!(destination, field)
  return _subtract_scalar_constant!(destination, scalar)
end


function subtract!(destination::ScalarFieldSpectral, scalar::Real, field::ScalarFieldSpectral)
  check_field_compatibility(destination, field)
  @_assign! field_data(destination) .= (-).(field_data(field))
  return _add_scalar_constant!(destination, scalar)
end


# Allocating operators for the scalar-constant variants.
for Scalar in (:ScalarFieldPhysical, :ScalarFieldSpectral)

  @eval function +(field::$Scalar, scalar::Real)
    destination = similar_field(field, similar(field_data(field)))
    return add!(destination, field, scalar)
  end

  @eval function +(scalar::Real, field::$Scalar)
    destination = similar_field(field, similar(field_data(field)))
    return add!(destination, scalar, field)
  end

  @eval function -(field::$Scalar, scalar::Real)
    destination = similar_field(field, similar(field_data(field)))
    return subtract!(destination, field, scalar)
  end

  @eval function -(scalar::Real, field::$Scalar)
    destination = similar_field(field, similar(field_data(field)))
    return subtract!(destination, scalar, field)
  end
end


# Field ± constant fiber: each table row stamps out the forward and reversed
# in-place methods and the four allocating operators for one field type.
for (FieldType, Constant, add_kernel, subtract_kernel) in (
    (:(VectorFieldPhysical{T}),    :(FiberVector{T}),  :_add_fiber_vector!,  :_subtract_fiber_vector!),
    (:(VectorFieldSpectral{T}),    :(FiberVector{T}),  :_add_fiber_vector!,  :_subtract_fiber_vector!),
    (:(TensorFieldPhysical{2, T}), :(FiberTensor2{T}), :_add_fiber_tensor2!, :_subtract_fiber_tensor2!),
    (:(TensorFieldSpectral{2, T}), :(FiberTensor2{T}), :_add_fiber_tensor2!, :_subtract_fiber_tensor2!),
  )

  @eval function add!(destination::$FieldType, field::$FieldType, constant::$Constant) where {T<:AbstractFloat}
    check_field_compatibility(destination, field)
    _copy_field_data!(destination, field)
    return $add_kernel(destination, constant)
  end

  @eval add!(destination::$FieldType, constant::$Constant, field::$FieldType) where {T<:AbstractFloat} =
    add!(destination, field, constant)

  @eval function subtract!(destination::$FieldType, field::$FieldType, constant::$Constant) where {T<:AbstractFloat}
    check_field_compatibility(destination, field)
    _copy_field_data!(destination, field)
    return $subtract_kernel(destination, constant)
  end

  @eval function subtract!(destination::$FieldType, constant::$Constant, field::$FieldType) where {T<:AbstractFloat}
    check_field_compatibility(destination, field)
    @_assign! field_data(destination) .= (-).(field_data(field))
    return $add_kernel(destination, constant)
  end

  @eval function +(field::$FieldType, constant::$Constant) where {T<:AbstractFloat}
    destination = similar_field(field, similar(field_data(field)))
    return add!(destination, field, constant)
  end

  @eval function +(constant::$Constant, field::$FieldType) where {T<:AbstractFloat}
    destination = similar_field(field, similar(field_data(field)))
    return add!(destination, constant, field)
  end

  @eval function -(field::$FieldType, constant::$Constant) where {T<:AbstractFloat}
    destination = similar_field(field, similar(field_data(field)))
    return subtract!(destination, field, constant)
  end

  @eval function -(constant::$Constant, field::$FieldType) where {T<:AbstractFloat}
    destination = similar_field(field, similar(field_data(field)))
    return subtract!(destination, constant, field)
  end
end


#####################################################
#        Multiplication by Real Numbers             #
#####################################################


"""
    multiply!(destination, scalar::Real, field)
    multiply!(destination, field, scalar::Real)
    multiply!(destination, scalar_field, field)
    multiply!(destination, scalar_field, constant)

Multiply in place by a real number or by a scalar field; returns `destination`.

Multiplication by a real number is representation-preserving and defined for fields in physical-space and spectral representation, in either argument order.

Multiplication by a scalar field is pointwise and is therefore defined only in physical-space representation when the other factor is a field; in spectral representation the product of two fields is a convolution, which this module does not provide. When the other factor is a constant `FiberVector` or `FiberTensor2` the operation is linear in the scalar field and stays coefficient-wise, so it is defined in both representations and yields the corresponding vector or tensor field. Either argument order is accepted.
"""
function multiply! end


"""
    divide!(destination, field, scalar::Real)
    divide!(destination, field, scalar_field)
    divide!(destination, numerator, scalar_field)

Divide in place; returns `destination`.

Division by a real number is representation-preserving and defined in both representations. Division by a scalar field is pointwise and defined only in physical-space representation; the numerator may be a field of any tensor order (the division acts on all of its components), a real number (yielding a scalar field), or a constant `FiberVector` or `FiberTensor2` (yielding the corresponding vector or tensor field).
"""
function divide! end


# Scaling by a real number is the same broadcast in both representations.
for Representation in (:AbstractFieldPhysical, :AbstractFieldSpectral)

  @eval function multiply!(destination::$Representation, scalar::Real, field::$Representation)
    destination .= scalar .* field
    return destination
  end

  @eval function multiply!(destination::$Representation, field::$Representation, scalar::Real)
    destination .= field .* scalar
    return destination
  end

  @eval function divide!(destination::$Representation, field::$Representation, scalar::Real)
    destination .= field ./ scalar
    return destination
  end
end


function *(scalar::Real, field::AbstractField)
  destination = similar_field(field, similar(field_data(field)))
  return multiply!(destination, scalar, field)
end


function *(field::AbstractField, scalar::Real)
  destination = similar_field(field, similar(field_data(field)))
  return multiply!(destination, field, scalar)
end


function /(field::AbstractField, scalar::Real)
  destination = similar_field(field, similar(field_data(field)))
  return divide!(destination, field, scalar)
end


#####################################################
#        Multiplication by Scalar Fields            #
#####################################################


# Pointwise product of a scalar field with a field of any tensor order, acting
# on all components through a singleton-fiber broadcast view.
function _multiply_by_scalar_field!(destination::AbstractFieldPhysical, scalar_field::ScalarFieldPhysical, field::AbstractFieldPhysical)
  check_field_compatibility(destination, field)
  _check_field_domain_compatibility(scalar_field, field)

  @_assign! field_data(destination) .= _scalar_field_broadcast_data(scalar_field, field) .* field_data(field)

  return destination
end


# Scalar field × constant fiber and constant fiber ÷ scalar field: the kernels
# are emitted from their per-component formulas via the kernel-body builders.
# The multiplication kernels serve both representations, because the operation
# is linear in the scalar field and therefore stays coefficient-wise.
@eval function _multiply_scalar_field_by_fiber_vector!(destination, scalar_field, a::FiberVector)
  _check_field_domain_compatibility(scalar_field, destination)
  scalar_data = field_data(scalar_field)
  $(_vector_kernel_body(i -> _product(:scalar_data, _vector_component(:a, :fiber, i)); alpha_beta = false))
end


@eval function _multiply_scalar_field_by_fiber_tensor2!(destination, scalar_field, A::FiberTensor2)
  _check_field_domain_compatibility(scalar_field, destination)
  scalar_data = field_data(scalar_field)
  $(_tensor_kernel_body((i, j) -> _product(:scalar_data, _tensor_component(:A, :fiber, i, j)); alpha_beta = false))
end


@eval function _divide_fiber_vector_by_scalar_field!(destination::VectorFieldPhysical, a::FiberVector, scalar_field::ScalarFieldPhysical)
  _check_field_domain_compatibility(scalar_field, destination)
  scalar_data = field_data(scalar_field)
  $(_vector_kernel_body(i -> :($(_vector_component(:a, :fiber, i)) ./ scalar_data); alpha_beta = false))
end


@eval function _divide_fiber_tensor2_by_scalar_field!(destination::TensorFieldPhysical{2}, A::FiberTensor2, scalar_field::ScalarFieldPhysical)
  _check_field_domain_compatibility(scalar_field, destination)
  scalar_data = field_data(scalar_field)
  $(_tensor_kernel_body((i, j) -> :($(_tensor_component(:A, :fiber, i, j)) ./ scalar_data); alpha_beta = false))
end


# Scalar-field × field methods. Kept explicit: the four dispatch signatures
# exist to resolve ambiguities between the scalar-scalar and general cases.
multiply!(destination::AbstractFieldPhysical, scalar_field::ScalarFieldPhysical, field::AbstractFieldPhysical) = _multiply_by_scalar_field!(destination, scalar_field, field)

multiply!(destination::AbstractFieldPhysical, field::AbstractFieldPhysical, scalar_field::ScalarFieldPhysical) = _multiply_by_scalar_field!(destination, scalar_field, field)

multiply!(destination::ScalarFieldPhysical, a::ScalarFieldPhysical, b::ScalarFieldPhysical) = _multiply_by_scalar_field!(destination, a, b)

multiply!(destination::AbstractFieldPhysical, a::ScalarFieldPhysical, b::ScalarFieldPhysical) = _multiply_by_scalar_field!(destination, a, b)


# Scalar field × constant fiber: each row stamps out both argument orders of the
# in-place method and the two allocating operators, with the destination tensor
# order carried by the table.
for (Destination, Scalar, Constant, order, kernel) in (
    (:(VectorFieldPhysical{T}),    :(ScalarFieldPhysical{T}), :(FiberVector{T}),  1, :_multiply_scalar_field_by_fiber_vector!),
    (:(VectorFieldSpectral{T}),    :(ScalarFieldSpectral{T}), :(FiberVector{T}),  1, :_multiply_scalar_field_by_fiber_vector!),
    (:(TensorFieldPhysical{2, T}), :(ScalarFieldPhysical{T}), :(FiberTensor2{T}), 2, :_multiply_scalar_field_by_fiber_tensor2!),
    (:(TensorFieldSpectral{2, T}), :(ScalarFieldSpectral{T}), :(FiberTensor2{T}), 2, :_multiply_scalar_field_by_fiber_tensor2!),
  )

  @eval multiply!(destination::$Destination, scalar_field::$Scalar, constant::$Constant) where {T<:AbstractFloat} =
    $kernel(destination, scalar_field, constant)

  @eval multiply!(destination::$Destination, constant::$Constant, scalar_field::$Scalar) where {T<:AbstractFloat} =
    multiply!(destination, scalar_field, constant)

  @eval function *(scalar_field::$Scalar, constant::$Constant) where {T<:AbstractFloat}
    destination = similar_field(scalar_field, Val($order))
    return multiply!(destination, scalar_field, constant)
  end

  @eval function *(constant::$Constant, scalar_field::$Scalar) where {T<:AbstractFloat}
    destination = similar_field(scalar_field, Val($order))
    return multiply!(destination, constant, scalar_field)
  end
end


# Division by a scalar field (physical-space only).
divide!(destination::VectorFieldPhysical{T}, a::FiberVector{T}, scalar_field::ScalarFieldPhysical{T}) where {T<:AbstractFloat} =
  _divide_fiber_vector_by_scalar_field!(destination, a, scalar_field)

divide!(destination::TensorFieldPhysical{2, T}, A::FiberTensor2{T}, scalar_field::ScalarFieldPhysical{T}) where {T<:AbstractFloat} =
  _divide_fiber_tensor2_by_scalar_field!(destination, A, scalar_field)


function divide!(destination::AbstractFieldPhysical, field::AbstractFieldPhysical, scalar_field::ScalarFieldPhysical)
  check_field_compatibility(destination, field)
  _check_field_domain_compatibility(scalar_field, field)

  @_assign! field_data(destination) .= field_data(field) ./ _scalar_field_broadcast_data(scalar_field, field)

  return destination
end


function divide!(destination::ScalarFieldPhysical, scalar::Real, scalar_field::ScalarFieldPhysical)
  destination .= scalar ./ scalar_field
  return destination
end


function *(scalar_field::ScalarFieldPhysical, field::AbstractFieldPhysical)
  destination = similar_field(field, similar(field_data(field)))
  return multiply!(destination, scalar_field, field)
end


function *(field::AbstractFieldPhysical, scalar_field::ScalarFieldPhysical)
  destination = similar_field(field, similar(field_data(field)))
  return multiply!(destination, field, scalar_field)
end


function *(a::ScalarFieldPhysical, b::ScalarFieldPhysical)
  destination = similar_field(a, similar(field_data(a)))
  return multiply!(destination, a, b)
end


function /(field::AbstractFieldPhysical, scalar_field::ScalarFieldPhysical)
  destination = similar_field(field, similar(field_data(field)))
  return divide!(destination, field, scalar_field)
end


function /(scalar::Real, scalar_field::ScalarFieldPhysical)
  destination = similar_field(scalar_field, similar(field_data(scalar_field)))
  return divide!(destination, scalar, scalar_field)
end


function /(a::FiberVector{T}, scalar_field::ScalarFieldPhysical{T}) where {T<:AbstractFloat}
  destination = similar_field(scalar_field, Val(1))
  return divide!(destination, a, scalar_field)
end


function /(A::FiberTensor2{T}, scalar_field::ScalarFieldPhysical{T}) where {T<:AbstractFloat}
  destination = similar_field(scalar_field, Val(2))
  return divide!(destination, A, scalar_field)
end


#####################################################
#        M3 contraction formula builders            #
#####################################################


const _VectorField = Union{VectorFieldPhysical, VectorFieldSpectral}
const _Tensor2Field = Union{TensorFieldPhysical{2}, TensorFieldSpectral{2}}


#####################################################
#        Vector and Tensor Dot Products             #
#####################################################


"""
    dot!(destination::ScalarFieldPhysical, u::VectorFieldPhysical, v::VectorFieldPhysical)
    dot!(destination::ScalarFieldPhysical, u::VectorFieldPhysical, a::FiberVector)
    dot!(destination::ScalarFieldSpectral, u::VectorFieldSpectral, a::FiberVector)
    dot!(destination::ScalarFieldPhysical, A::TensorFieldPhysical{2}, B::TensorFieldPhysical{2})
    dot!(destination::ScalarFieldPhysical, A::TensorFieldPhysical{2}, B::FiberTensor2)
    dot!(destination::ScalarFieldSpectral, A::TensorFieldSpectral{2}, B::FiberTensor2)

Compute a fiberwise inner product in-place; returns `destination`.

For vector arguments this is the Euclidean scalar product ``u_i v_i``; for second-order tensors it is the Frobenius double contraction ``A_{ij} B_{ij}``. Either argument order is accepted.

Contraction of two fields is nonlinear and defined only in physical-space representation. In spectral representation only contraction with a constant fiber vector or fiber tensor is provided, which keeps the operation coefficient-wise.
"""
function dot! end


"""
    dot(u::VectorFieldPhysical, v::VectorFieldPhysical)
    dot(A::TensorFieldPhysical{2}, B::TensorFieldPhysical{2})

Allocating fiberwise inner product (`dot` ``\\equiv \\cdot``), returning a scalar field — the Euclidean
vector product or the tensor Frobenius product, applied pointwise over the base:

```math
(u \\cdot v)(x) = u_i(x)\\, v_i(x), \\qquad (A : B)(x) = A_{ij}(x)\\, B_{ij}(x)
```

(summation over repeated fiber indices). Two fields contract only in physical-space representation; with a constant fiber the contraction stays coefficient-wise and is available in both representations. See `dot!` for the in-place form. The infix alias ``\\cdot`` (`⋅`) is also exported.

This operation is also defined for `PointValues` — the same fiberwise algebra on field values sampled at an unstructured point set (see the `Points` module).
"""
dot


# Inner-product kernels (scalar result, written through the scalar kernel body).
@eval _dot_components!(destination, u::_VectorField, v::_VectorField) =
  $(_scalar_kernel_body(_dot_vector_rhs(:u, :field, :v, :field)))

@eval _dot_components!(destination, u::_VectorField, a::FiberVector) =
  $(_scalar_kernel_body(_dot_vector_rhs(:u, :field, :a, :fiber)))

@eval _dot_components!(destination, A::_Tensor2Field, B::_Tensor2Field) =
  $(_scalar_kernel_body(_dot_tensor_rhs(:A, :field, :B, :field)))

@eval _dot_components!(destination, A::_Tensor2Field, B::FiberTensor2) =
  $(_scalar_kernel_body(_dot_tensor_rhs(:A, :field, :B, :fiber)))


# Field-field inner products (physical-space only).
function dot!(destination::ScalarFieldPhysical{T}, u::VectorFieldPhysical{T}, v::VectorFieldPhysical{T}) where {T<:AbstractFloat}
  check_field_compatibility(u, v)
  _check_field_domain_compatibility(destination, u)
  return _dot_components!(destination, u, v)
end

function dot!(destination::ScalarFieldPhysical{T}, A::TensorFieldPhysical{2, T}, B::TensorFieldPhysical{2, T}) where {T<:AbstractFloat}
  check_field_compatibility(A, B)
  _check_field_domain_compatibility(destination, A)
  return _dot_components!(destination, A, B)
end

function dot(u::VectorFieldPhysical{T}, v::VectorFieldPhysical{T}) where {T<:AbstractFloat}
  return dot!(similar_field(u, Val(0)), u, v)
end

function dot(A::TensorFieldPhysical{2, T}, B::TensorFieldPhysical{2, T}) where {T<:AbstractFloat}
  return dot!(similar_field(A, Val(0)), A, B)
end


# Field-fiber inner products (both representations; reversed order delegates,
# the contraction being commutative). One table row per (representation, rank).
for (ScalarField, OperandField, Constant) in (
    (:ScalarFieldPhysical, :VectorFieldPhysical,    :FiberVector),
    (:ScalarFieldSpectral, :VectorFieldSpectral,    :FiberVector),
    (:ScalarFieldPhysical, :(TensorFieldPhysical{2}), :FiberTensor2),
    (:ScalarFieldSpectral, :(TensorFieldSpectral{2}), :FiberTensor2),
  )

  @eval function dot!(destination::$ScalarField{T}, operand::$OperandField{T}, constant::$Constant{T}) where {T<:AbstractFloat}
    _check_field_domain_compatibility(destination, operand)
    return _dot_components!(destination, operand, constant)
  end

  @eval dot!(destination::$ScalarField{T}, constant::$Constant{T}, operand::$OperandField{T}) where {T<:AbstractFloat} =
    dot!(destination, operand, constant)

  @eval dot(operand::$OperandField{T}, constant::$Constant{T}) where {T<:AbstractFloat} =
    dot!(similar_field(operand, Val(0)), operand, constant)

  @eval dot(constant::$Constant{T}, operand::$OperandField{T}) where {T<:AbstractFloat} =
    dot!(similar_field(operand, Val(0)), operand, constant)
end


#####################################################
#        Vector Cross Products                      #
#####################################################


"""
    cross!(destination::VectorFieldPhysical, u::VectorFieldPhysical, v::VectorFieldPhysical)
    cross!(destination::VectorFieldPhysical, u::VectorFieldPhysical, a::FiberVector)
    cross!(destination::VectorFieldSpectral, u::VectorFieldSpectral, a::FiberVector)

Compute a fiberwise cross product (`cross` ``\\equiv \\times``) in-place; returns `destination`.
Pointwise over the base, with the components the kernel writes (cyclic ``(i, j, k)``):

```math
(u \\times v)_i = \\varepsilon_{ijk}\\, u_j v_k = u_j v_k - u_k v_j.
```

Cross products of two fields are nonlinear and defined only in physical-space representation. In spectral representation only the cross product with a constant fiber vector (either argument order) is provided, which keeps the operation coefficient-wise.
"""
function cross! end


"""
    cross(u::VectorFieldPhysical, v::VectorFieldPhysical)

Allocating fiberwise cross product (`cross` ``\\equiv \\times``) ``u \\times v``, returning a vector field. Two vector fields cross only in physical-space representation; with a constant fiber vector the operation stays coefficient-wise and is available in both representations. See `cross!` for the in-place form. The infix alias ``\\times`` (`×`) is also exported.

This operation is also defined for `PointValues` — the same fiberwise algebra on field values sampled at an unstructured point set (see the `Points` module).
"""
cross


# Cross-product kernels (vector result). Index-shuffling reads several source
# components per written component, so the public methods wrap these through
# `_guard_noalias!`.
@eval _cross_components_noalias!(destination, u::_VectorField, v::_VectorField) =
  $(_vector_kernel_body(_cross_formula(:u, :field, :v, :field); alpha_beta = false))

@eval _cross_components_noalias!(destination, u::_VectorField, a::FiberVector) =
  $(_vector_kernel_body(_cross_formula(:u, :field, :a, :fiber); alpha_beta = false))

@eval _cross_components_noalias!(destination, a::FiberVector, u::_VectorField) =
  $(_vector_kernel_body(_cross_formula(:a, :fiber, :u, :field); alpha_beta = false))


function cross!(destination::VectorFieldPhysical{T}, u::VectorFieldPhysical{T}, v::VectorFieldPhysical{T}) where {T<:AbstractFloat}
  check_field_compatibility(u, v)
  check_field_compatibility(destination, u)
  return _guard_noalias!(_cross_components_noalias!, destination, Val(1), (u, v))
end

function cross(u::VectorFieldPhysical{T}, v::VectorFieldPhysical{T}) where {T<:AbstractFloat}
  return cross!(similar_field(u, Val(1)), u, v)
end

# Cross with a constant fiber vector (both representations, both argument orders).
for (VectorField,) in ((:VectorFieldPhysical,), (:VectorFieldSpectral,))

  @eval function cross!(destination::$VectorField{T}, u::$VectorField{T}, a::FiberVector{T}) where {T<:AbstractFloat}
    check_field_compatibility(destination, u)
    return _guard_noalias!(_cross_components_noalias!, destination, Val(1), (u, a))
  end

  @eval function cross!(destination::$VectorField{T}, a::FiberVector{T}, u::$VectorField{T}) where {T<:AbstractFloat}
    check_field_compatibility(destination, u)
    return _guard_noalias!(_cross_components_noalias!, destination, Val(1), (a, u))
  end

  @eval cross(u::$VectorField{T}, a::FiberVector{T}) where {T<:AbstractFloat} = cross!(similar_field(u, Val(1)), u, a)

  @eval cross(a::FiberVector{T}, u::$VectorField{T}) where {T<:AbstractFloat} = cross!(similar_field(u, Val(1)), a, u)
end


#####################################################
#        Tensor-Vector and Tensor-Tensor Products   #
#####################################################


"""
    mul!(destination::VectorFieldPhysical, A::TensorFieldPhysical{2},
         u::VectorFieldPhysical[, α, β])
    mul!(destination::VectorFieldPhysical, A::TensorFieldPhysical{2}, a::FiberVector[, α, β])
    mul!(destination::VectorFieldSpectral, A::FiberTensor2, u::VectorFieldSpectral[, α, β])
    mul!(destination::TensorFieldPhysical{2}, A::TensorFieldPhysical{2},
         B::TensorFieldPhysical{2}[, α, β])
    mul!(destination::TensorFieldPhysical{2}, A::TensorFieldPhysical{2}, B::FiberTensor2[, α, β])

Compute a fiberwise tensor (matrix) product in-place; returns `destination`. Pointwise over the base —
the tensor-on-vector left/right action, or the matrix product, exactly as the kernel computes them:

```math
(A u)_i = A_{ij} u_j, \\qquad (u A)_i = u_j A_{ji}, \\qquad (A B)_{ij} = A_{ik} B_{kj}.
```

Products of two fields are nonlinear and defined only in physical-space representation; spectral-space methods require one factor to be a constant fiber tensor or fiber vector. The five-argument form computes ``\\mathrm{destination} = \\alpha\\,(A B) + \\beta\\,\\mathrm{destination}``. As with `LinearAlgebra.mul!`, `destination` must not share storage with any input.

This operation is also defined for `PointValues` — the same fiberwise algebra on field values sampled at an unstructured point set (see the `Points` module).
"""
mul!


# Tensor-vector kernels (vector result, α/β accumulation). No alias guard:
# mul! documents that the destination must not alias the inputs.
@eval _tensor_vector_components!(destination, A::_Tensor2Field, u::_VectorField, α_value, β_value) =
  $(_vector_kernel_body(_tensor_vector_formula(:A, :field, :u, :field); alpha_beta = true))

@eval _tensor_vector_components!(destination, A::_Tensor2Field, a::FiberVector, α_value, β_value) =
  $(_vector_kernel_body(_tensor_vector_formula(:A, :field, :a, :fiber); alpha_beta = true))

@eval _tensor_vector_components!(destination, A::FiberTensor2, u::_VectorField, α_value, β_value) =
  $(_vector_kernel_body(_tensor_vector_formula(:A, :fiber, :u, :field); alpha_beta = true))

@eval _vector_tensor_components!(destination, u::_VectorField, A::_Tensor2Field, α_value, β_value) =
  $(_vector_kernel_body(_vector_tensor_formula(:u, :field, :A, :field); alpha_beta = true))

@eval _vector_tensor_components!(destination, a::FiberVector, A::_Tensor2Field, α_value, β_value) =
  $(_vector_kernel_body(_vector_tensor_formula(:a, :fiber, :A, :field); alpha_beta = true))

@eval _vector_tensor_components!(destination, u::_VectorField, A::FiberTensor2, α_value, β_value) =
  $(_vector_kernel_body(_vector_tensor_formula(:u, :field, :A, :fiber); alpha_beta = true))


# Tensor-tensor kernels (tensor result, α/β accumulation).
@eval _tensor_tensor_components!(destination, A::_Tensor2Field, B::_Tensor2Field, α_value, β_value) =
  $(_tensor_kernel_body(_tensor_tensor_formula(:A, :field, :B, :field); alpha_beta = true))

@eval _tensor_tensor_components!(destination, A::_Tensor2Field, B::FiberTensor2, α_value, β_value) =
  $(_tensor_kernel_body(_tensor_tensor_formula(:A, :field, :B, :fiber); alpha_beta = true))

@eval _tensor_tensor_components!(destination, A::FiberTensor2, B::_Tensor2Field, α_value, β_value) =
  $(_tensor_kernel_body(_tensor_tensor_formula(:A, :fiber, :B, :field); alpha_beta = true))


# --- Tensor-vector mul! (five-argument forms) ---

# Field-field (physical-space only): left action A·u and right action u·A.
function mul!(destination::VectorFieldPhysical{T}, A::TensorFieldPhysical{2, T}, u::VectorFieldPhysical{T}, α::Real, β::Real) where {T<:AbstractFloat}
  check_field_compatibility(destination, u)
  _check_field_domain_compatibility(A, u)
  return _tensor_vector_components!(destination, A, u, T(α), T(β))
end

function mul!(destination::VectorFieldPhysical{T}, u::VectorFieldPhysical{T}, A::TensorFieldPhysical{2, T}, α::Real, β::Real) where {T<:AbstractFloat}
  check_field_compatibility(destination, u)
  _check_field_domain_compatibility(A, u)
  return _vector_tensor_components!(destination, u, A, T(α), T(β))
end

# Tensor field × constant fiber vector, and constant fiber tensor × vector field
# (both representations). One table row per (representation).
for (VectorField, Tensor2Field) in (
    (:VectorFieldPhysical, :(TensorFieldPhysical{2})),
    (:VectorFieldSpectral, :(TensorFieldSpectral{2})),
  )

  @eval function mul!(destination::$VectorField{T}, A::$Tensor2Field{T}, a::FiberVector{T}, α::Real, β::Real) where {T<:AbstractFloat}
    _check_field_domain_compatibility(A, destination)
    return _tensor_vector_components!(destination, A, a, T(α), T(β))
  end

  @eval function mul!(destination::$VectorField{T}, a::FiberVector{T}, A::$Tensor2Field{T}, α::Real, β::Real) where {T<:AbstractFloat}
    _check_field_domain_compatibility(A, destination)
    return _vector_tensor_components!(destination, a, A, T(α), T(β))
  end

  @eval function mul!(destination::$VectorField{T}, A::FiberTensor2{T}, u::$VectorField{T}, α::Real, β::Real) where {T<:AbstractFloat}
    check_field_compatibility(destination, u)
    return _tensor_vector_components!(destination, A, u, T(α), T(β))
  end

  @eval function mul!(destination::$VectorField{T}, u::$VectorField{T}, A::FiberTensor2{T}, α::Real, β::Real) where {T<:AbstractFloat}
    check_field_compatibility(destination, u)
    return _vector_tensor_components!(destination, u, A, T(α), T(β))
  end
end


# --- Tensor-tensor mul! (five-argument forms) ---

function mul!(destination::TensorFieldPhysical{2, T}, A::TensorFieldPhysical{2, T}, B::TensorFieldPhysical{2, T}, α::Real, β::Real) where {T<:AbstractFloat}
  check_field_compatibility(destination, A)
  check_field_compatibility(A, B)
  return _tensor_tensor_components!(destination, A, B, T(α), T(β))
end

for (Tensor2Field,) in ((:(TensorFieldPhysical{2}),), (:(TensorFieldSpectral{2}),))

  @eval function mul!(destination::$Tensor2Field{T}, A::$Tensor2Field{T}, B::FiberTensor2{T}, α::Real, β::Real) where {T<:AbstractFloat}
    check_field_compatibility(destination, A)
    return _tensor_tensor_components!(destination, A, B, T(α), T(β))
  end

  @eval function mul!(destination::$Tensor2Field{T}, A::FiberTensor2{T}, B::$Tensor2Field{T}, α::Real, β::Real) where {T<:AbstractFloat}
    check_field_compatibility(destination, B)
    return _tensor_tensor_components!(destination, A, B, T(α), T(β))
  end
end


# --- Three-argument mul! forms delegate with α = 1, β = 0 ---
for (Destination, First, Second) in (
    (:(VectorFieldPhysical{T}),    :(TensorFieldPhysical{2, T}), :(VectorFieldPhysical{T})),
    (:(VectorFieldPhysical{T}),    :(VectorFieldPhysical{T}),    :(TensorFieldPhysical{2, T})),
    (:(VectorFieldPhysical{T}),    :(TensorFieldPhysical{2, T}), :(FiberVector{T})),
    (:(VectorFieldPhysical{T}),    :(FiberVector{T}),            :(TensorFieldPhysical{2, T})),
    (:(VectorFieldPhysical{T}),    :(FiberTensor2{T}),           :(VectorFieldPhysical{T})),
    (:(VectorFieldPhysical{T}),    :(VectorFieldPhysical{T}),    :(FiberTensor2{T})),
    (:(VectorFieldSpectral{T}),    :(TensorFieldSpectral{2, T}), :(FiberVector{T})),
    (:(VectorFieldSpectral{T}),    :(FiberVector{T}),            :(TensorFieldSpectral{2, T})),
    (:(VectorFieldSpectral{T}),    :(FiberTensor2{T}),           :(VectorFieldSpectral{T})),
    (:(VectorFieldSpectral{T}),    :(VectorFieldSpectral{T}),    :(FiberTensor2{T})),
    (:(TensorFieldPhysical{2, T}), :(TensorFieldPhysical{2, T}), :(TensorFieldPhysical{2, T})),
    (:(TensorFieldPhysical{2, T}), :(TensorFieldPhysical{2, T}), :(FiberTensor2{T})),
    (:(TensorFieldPhysical{2, T}), :(FiberTensor2{T}),           :(TensorFieldPhysical{2, T})),
    (:(TensorFieldSpectral{2, T}), :(TensorFieldSpectral{2, T}), :(FiberTensor2{T})),
    (:(TensorFieldSpectral{2, T}), :(FiberTensor2{T}),           :(TensorFieldSpectral{2, T})),
  )

  @eval mul!(destination::$Destination, first::$First, second::$Second) where {T<:AbstractFloat} =
    mul!(destination, first, second, one(T), zero(T))
end


# --- Allocating `*` operators delegate to the three-argument mul! ---

# Tensor-vector: the destination is a vector field built on the vector operand
# (when present) or on the tensor field's grid.
for (TensorField,) in ((:(TensorFieldPhysical{2}),), (:(TensorFieldSpectral{2}),))

  @eval *(A::$TensorField{T}, a::FiberVector{T}) where {T<:AbstractFloat} = mul!(similar_field(A, Val(1)), A, a)
  @eval *(a::FiberVector{T}, A::$TensorField{T}) where {T<:AbstractFloat} = mul!(similar_field(A, Val(1)), a, A)
end

for (VectorField,) in ((:VectorFieldPhysical,), (:VectorFieldSpectral,))

  @eval *(A::FiberTensor2{T}, u::$VectorField{T}) where {T<:AbstractFloat} = mul!(similar_field(u, similar(field_data(u))), A, u)
  @eval *(u::$VectorField{T}, A::FiberTensor2{T}) where {T<:AbstractFloat} = mul!(similar_field(u, similar(field_data(u))), u, A)
end

*(A::TensorFieldPhysical{2, T}, u::VectorFieldPhysical{T}) where {T<:AbstractFloat} = mul!(similar_field(u, similar(field_data(u))), A, u)
*(u::VectorFieldPhysical{T}, A::TensorFieldPhysical{2, T}) where {T<:AbstractFloat} = mul!(similar_field(u, similar(field_data(u))), u, A)

# Tensor-tensor: the destination is a tensor field built on whichever operand is a field.
*(A::TensorFieldPhysical{2, T}, B::TensorFieldPhysical{2, T}) where {T<:AbstractFloat} = mul!(similar_field(A, Val(2)), A, B)

for (Tensor2Field,) in ((:(TensorFieldPhysical{2}),), (:(TensorFieldSpectral{2}),))

  @eval *(A::$Tensor2Field{T}, B::FiberTensor2{T}) where {T<:AbstractFloat} = mul!(similar_field(A, Val(2)), A, B)
  @eval *(A::FiberTensor2{T}, B::$Tensor2Field{T}) where {T<:AbstractFloat} = mul!(similar_field(B, Val(2)), A, B)
end


#####################################################
#        Tensor Index Permutations                  #
#####################################################


"""
    transpose!(destination::TensorFieldPhysical{2}, A::TensorFieldPhysical{2})
    transpose!(destination::TensorFieldSpectral{2}, A::TensorFieldSpectral{2})

Transpose the fiber indices of a second-order tensor field in-place (`transpose` ``\\equiv (\\cdot)^\\top``): ``\\mathrm{destination}_{ij} = A_{ji}``; returns `destination`.

The operation is linear and representation-preserving, so it is defined for both physical-space and spectral representations. Unlike Julia's matrix `transpose`, this writes a canonical tensor field rather than a lazy wrapper.

This operation is also defined for `PointValues` — the same fiberwise algebra on field values sampled at an unstructured point set (see the `Points` module).
"""
transpose!


@eval _transpose_components_noalias!(destination, A) =
  $(_tensor_kernel_body(_transpose_formula(:A, :field); alpha_beta = false))


for (Tensor2Field,) in ((:(TensorFieldPhysical{2}),), (:(TensorFieldSpectral{2}),))

  @eval function transpose!(destination::$Tensor2Field{T}, A::$Tensor2Field{T}) where {T<:AbstractFloat}
    check_field_compatibility(destination, A)
    return _guard_noalias!(_transpose_components_noalias!, destination, Val(2), (A,))
  end

  @eval transpose(A::$Tensor2Field{T}) where {T<:AbstractFloat} = transpose!(similar_field(A, Val(2)), A)
end


#####################################################
#        Field Norms                                #
#####################################################


"""
    norm!(destination::ScalarFieldPhysical, scalar_field::ScalarFieldPhysical)
    norm!(destination::ScalarFieldPhysical, u::VectorFieldPhysical)
    norm!(destination::ScalarFieldPhysical, A::TensorFieldPhysical{2})

Compute the fiberwise norm of a field (`norm` ``\\equiv |\\cdot|``) in physical-space representation in-place; returns `destination`.

This is the pointwise absolute value ``|\\varphi|`` for scalar fields, the Euclidean norm ``|u| = \\sqrt{u_i u_i}`` for vector fields, and the Frobenius norm ``|A| = \\sqrt{A_{ij} A_{ij}}`` (not the operator norm) for second-order tensor fields. The norm is nonlinear and is not defined for spectral representation.
"""
function norm! end


"""
    norm(scalar_field::ScalarFieldPhysical)
    norm(u::VectorFieldPhysical)
    norm(A::TensorFieldPhysical{2})

Allocating fiberwise norm (`norm` ``\\equiv |\\cdot|``), returning a scalar field — the pointwise fiber
magnitude:

```math
|\\varphi| \\;(\\text{scalar}), \\qquad |u| = \\sqrt{u_i u_i} \\;(\\text{vector}), \\qquad |A| = \\sqrt{A_{ij} A_{ij}} \\;(\\text{Frobenius, tensor}).
```

Physical-space representation only. See `norm!` for the in-place form.

This operation is also defined for `PointValues` — the same fiberwise algebra on field values sampled at an unstructured point set (see the `Points` module).
"""
norm


@eval _norm_components!(destination, scalar_field::ScalarFieldPhysical) =
  $(_scalar_kernel_body(_norm_scalar_rhs(:scalar_field)))

@eval _norm_components!(destination, u::VectorFieldPhysical) =
  $(_scalar_kernel_body(_norm_vector_rhs(:u, :field)))

@eval _norm_components!(destination, A::TensorFieldPhysical{2}) =
  $(_scalar_kernel_body(_norm_tensor_rhs(:A, :field)))


for (Operand,) in ((:ScalarFieldPhysical,), (:VectorFieldPhysical,), (:(TensorFieldPhysical{2}),))

  @eval function norm!(destination::ScalarFieldPhysical{T}, operand::$Operand{T}) where {T<:AbstractFloat}
    _check_field_domain_compatibility(destination, operand)
    return _norm_components!(destination, operand)
  end

  @eval norm(operand::$Operand{T}) where {T<:AbstractFloat} = norm!(similar_field(operand, Val(0)), operand)
end


#####################################################
#        Tensor Decompositions                      #
#####################################################


"""
    sym!(destination::TensorFieldPhysical{2}, A::TensorFieldPhysical{2})
    sym!(destination::TensorFieldSpectral{2}, A::TensorFieldSpectral{2})

Compute the symmetric part ``\\operatorname{sym}(A) = \\tfrac12\\,(A + A^\\top)`` of a second-order tensor field in-place; returns `destination`. Linear and representation-preserving, so defined for both representations.
"""
function sym! end


"""
    sym(A::TensorFieldPhysical{2})
    sym(A::TensorFieldSpectral{2})
    sym(A::FiberTensor2)

Allocate and compute the symmetric part of a second-order tensor; fiberwise for a tensor field, or directly on a single `FiberTensor2` value. See [`sym!`](@ref) for the defining formula and the physical/spectral validity.

This operation is also defined for `PointValues` — the same fiberwise algebra on field values sampled at an unstructured point set (see the `Points` module).
"""
function sym end


"""
    skew!(destination::TensorFieldPhysical{2}, A::TensorFieldPhysical{2})
    skew!(destination::TensorFieldSpectral{2}, A::TensorFieldSpectral{2})

Compute the skew-symmetric part ``\\operatorname{skew}(A) = \\tfrac12\\,(A - A^\\top)`` of a second-order tensor field in-place; returns `destination`. Linear and representation-preserving, so defined for both representations.
"""
function skew! end


"""
    skew(A::TensorFieldPhysical{2})
    skew(A::TensorFieldSpectral{2})
    skew(A::FiberTensor2)

Allocate and compute the skew-symmetric part of a second-order tensor; fiberwise for a tensor field, or directly on a single `FiberTensor2` value. See [`skew!`](@ref) for the defining formula and the physical/spectral validity.

This operation is also defined for `PointValues` — the same fiberwise algebra on field values sampled at an unstructured point set (see the `Points` module).
"""
function skew end


"""
    dev!(destination::TensorFieldPhysical{2}, A::TensorFieldPhysical{2})
    dev!(destination::TensorFieldSpectral{2}, A::TensorFieldSpectral{2})

Compute the deviatoric part ``\\operatorname{dev}(A) = A - \\tfrac13\\,\\operatorname{tr}(A)\\,I`` of a second-order tensor field in-place; returns `destination`. Linear and representation-preserving, so defined for both representations.
"""
function dev! end


"""
    dev(A::TensorFieldPhysical{2})
    dev(A::TensorFieldSpectral{2})
    dev(A::FiberTensor2)

Allocate and compute the deviatoric part of a second-order tensor; fiberwise for a tensor field, or directly on a single `FiberTensor2` value. See [`dev!`](@ref) for the defining formula and the physical/spectral validity.

This operation is also defined for `PointValues` — the same fiberwise algebra on field values sampled at an unstructured point set (see the `Points` module).
"""
function dev end


# Decomposition kernels — bodies from the shared `_sym_kernel_body` / `_skew_kernel_body` /
# `_dev_kernel_body` builders in FiberSections (the same builders the point algebra uses, so the
# formula is written once). Index-shuffling, so wrapped by the guard.
@eval _sym_components_noalias!(destination, A) = $(_sym_kernel_body())

@eval _skew_components_noalias!(destination, A) = $(_skew_kernel_body())

@eval _dev_components_noalias!(destination, A) = $(_dev_kernel_body())


for (kernel, bang, allocating) in (
    (:_sym_components_noalias!,  :sym!,  :sym),
    (:_skew_components_noalias!, :skew!, :skew),
    (:_dev_components_noalias!,  :dev!,  :dev),
  )

  for (Tensor2Field,) in ((:(TensorFieldPhysical{2}),), (:(TensorFieldSpectral{2}),))

    @eval function $bang(destination::$Tensor2Field{T}, A::$Tensor2Field{T}) where {T<:AbstractFloat}
      check_field_compatibility(destination, A)
      return _guard_noalias!($kernel, destination, Val(2), (A,))
    end

    @eval $allocating(A::$Tensor2Field{T}) where {T<:AbstractFloat} = $bang(similar_field(A, Val(2)), A)
  end
end


# Decompositions of a constant fiber tensor: explicit StaticArrays one-liners.
function sym(A::FiberTensor2{T}) where {T<:AbstractFloat}
  half = inv(T(2))
  off_12 = half * (A[1, 2] + A[2, 1])
  off_13 = half * (A[1, 3] + A[3, 1])
  off_23 = half * (A[2, 3] + A[3, 2])
  return FiberTensor2{T}(A[1, 1], off_12, off_13, off_12, A[2, 2], off_23, off_13, off_23, A[3, 3])
end


function skew(A::FiberTensor2{T}) where {T<:AbstractFloat}
  half = inv(T(2))
  off_12 = half * (A[1, 2] - A[2, 1])
  off_13 = half * (A[1, 3] - A[3, 1])
  off_23 = half * (A[2, 3] - A[3, 2])
  return FiberTensor2{T}(zero(T), -off_12, -off_13, off_12, zero(T), -off_23, off_13, off_23, zero(T))
end


function dev(A::FiberTensor2{T}) where {T<:AbstractFloat}
  trace_over_three = (A[1, 1] + A[2, 2] + A[3, 3]) / T(3)
  return FiberTensor2{T}(
    A[1, 1] - trace_over_three, A[2, 1], A[3, 1],
    A[1, 2], A[2, 2] - trace_over_three, A[3, 2],
    A[1, 3], A[2, 3], A[3, 3] - trace_over_three,
  )
end


end # module FieldAlgebra
