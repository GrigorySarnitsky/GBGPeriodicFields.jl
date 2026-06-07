"""
    FieldAlgebra

Fiberwise and pointwise algebra for the scalar, vector, and second-order tensor fields defined in [`Fields`](@ref).

This module extends arithmetic (`+`, `-`, `*`, `/`) and the relevant `LinearAlgebra` operations (`dot`, `cross`, `mul!`, `transpose`, `norm`) to fields, together with in-place `add!`, `subtract!`, `multiply!`, `divide!`, `dot!`, `cross!`, `mul!`, `transpose!`, `norm!`, `sym!`, `skew!`, and `dev!`.

Field-field and field-constant operations preserve the representation of their arguments: they act pointwise on fields in physical-space representation and coefficient-wise on fields in spectral representation. Operations that are not linear in a field argument (for example multiplying two fields together, or contracting two fields) are defined only in physical-space representation, except where one factor is a compile-time constant fiber, which keeps the operation coefficient-wise.

Most of the method families below are emitted by small code generators defined in the "Code generation" section: the per-component formulas are written once, and the generators stamp out the representation, argument-order, and in-place/allocating variants.
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


function _copy_field_data!(destination::AbstractField, field::AbstractField)
  destination_data = field_data(destination)
  field_data_source = field_data(field)

  destination_data === field_data_source || copyto!(destination_data, field_data_source)

  return destination
end


_spectral_constant_scale(field::AbstractFieldSpectral{T}) where {T<:AbstractFloat} = prod(T.(field_grid(field).grid_size))

_spectral_zero_mode_data(field::ScalarFieldSpectral) = view(field_data(field), 1:1, 1:1, 1:1)

_spectral_zero_mode_component_data(field::VectorFieldSpectral, component) = view(field_data(field), 1:1, 1:1, 1:1, component:component)

_spectral_zero_mode_component_data(field::TensorFieldSpectral{2}, first_index, second_index) = view(field_data(field), 1:1, 1:1, 1:1, first_index:first_index, second_index:second_index)


# True if `destination` shares its backing array with any field among `operands`
# (constant fibers are not fields and never alias). Used by the no-alias guard.
_aliases_destination(destination, operands...) = any(operand -> (operand isa AbstractField) && (field_data(operand) === field_data(destination)), operands)


# Run an in-place kernel that requires its destination not to alias its inputs.
# If aliasing is detected, the kernel writes into a fresh field of tensor order
# `output_order` and the result is copied back. `operands` is the kernel argument
# tuple following `destination`.
function _guard_noalias!(kernel!, destination, output_order::Val, operands::Tuple)
  if _aliases_destination(destination, operands...)
    temporary = similar_field(destination, output_order)
    kernel!(temporary, operands...)
    copyto!(field_data(destination), field_data(temporary))
    return destination
  end
  return kernel!(destination, operands...)
end


@inline _add_values(x, y) = x + y
@inline _add_values(x, y, z, rest...) = _add_values(x + y, z, rest...)

@inline _subtract_values(x, y) = x - y
@inline _subtract_values(x, y, z, rest...) = _subtract_values(x - y, z, rest...)


# Reshape a scalar field's data so it broadcasts against the fiber dimensions of `field`.
function _scalar_field_broadcast_data(scalar_field::ScalarFieldPhysical, field::AbstractFieldPhysical)
  singleton_fiber_shape = ntuple(_ -> 1, field_tensor_order(field))
  return reshape(field_data(scalar_field), size(field_data(scalar_field))..., singleton_fiber_shape...)
end


#################################
#        Code generation        #
#################################
#
# The helpers below build expressions for the per-component access and write-back
# of generated kernels, so that each operation's formula is written exactly once.
#
#   `kind` is :field   -> access through the component views (a field argument)
#             :fiber   -> index a constant SVector / SMatrix argument
#
# Field component views are spliced directly into the formulas rather than bound
# to locals first; the views are lazy, so this is equivalent to the hand-written
# kernels it replaces.


_vector_component(symbol, kind, i)    = kind === :field ? :(_vector_component_data( $symbol, $i))     : :($symbol[$i])
_tensor_component(symbol, kind, i, j) = kind === :field ? :(_tensor2_component_data($symbol, $i, $j)) : :($symbol[$i, $j])


# Broadcasted sum  `term_1 .+ term_2 .+ ...`  of a non-empty collection of expressions.
_sum_terms(terms) = reduce((accumulated, term) -> :($accumulated .+ $term), terms)

# Broadcasted product  `x .* y`.
_product(x, y) = :($x .* $y)


# Body of a vector-valued kernel: `destination_i .= formula(i)` for i in 1:3.
# With `alpha_beta`, emits the five-argument `destination = α * formula + β * destination`
# form, branching on `iszero(β_value)` to keep the pure-overwrite path allocation free.
function _vector_kernel_body(formula; alpha_beta::Bool)
  target(i) = :(_vector_component_data(destination, $i))

  if alpha_beta
    overwrite = [:($(target(i)) .= α_value .* $(formula(i))) for i in 1:3]
    accumulate = [:($(target(i)) .= α_value .* $(formula(i)) .+ β_value .* $(target(i))) for i in 1:3]

    return quote
      if iszero(β_value)
        $(overwrite...)
      else
        $(accumulate...)
      end

      return destination
    end
  else
    statements = [:($(target(i)) .= $(formula(i))) for i in 1:3]

    return quote
      $(statements...)

      return destination
    end
  end
end


# Body of a tensor-valued kernel: `destination_ij .= formula(i, j)` for i, j in 1:3.
function _tensor_kernel_body(formula; alpha_beta::Bool)
  target(i, j) = :(_tensor2_component_data(destination, $i, $j))

  if alpha_beta
    overwrite = [:($(target(i, j)) .= α_value .* $(formula(i, j))) for i in 1:3 for j in 1:3]
    accumulate = [:($(target(i, j)) .= α_value .* $(formula(i, j)) .+ β_value .* $(target(i, j))) for i in 1:3 for j in 1:3]

    return quote
      if iszero(β_value)
        $(overwrite...)
      else
        $(accumulate...)
      end

      return destination
    end
  else
    statements = [:($(target(i, j)) .= $(formula(i, j))) for i in 1:3 for j in 1:3]

    return quote
      $(statements...)

      return destination
    end
  end
end


# Body of a scalar-field-valued kernel (a contraction with a scalar result):
# `field_data(destination) .= rhs`.
function _scalar_kernel_body(rhs)
  return quote
    field_data(destination) .= $rhs

    return destination
  end
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
  field_data(destination) .= (-).(field_data(field))
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
    field_data(destination) .= (-).(field_data(field))
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

  field_data(destination) .= _scalar_field_broadcast_data(scalar_field, field) .* field_data(field)

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

  field_data(destination) .= field_data(field) ./ _scalar_field_broadcast_data(scalar_field, field)

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
#
# Per-component formulas for the contraction and permutation families, written
# once and fed to the kernel-body builders. `kind` is :field (component view) or
# :fiber (StaticArrays indexing), as in the M1 builders above.


# Vector inner product rhs:  Σᵢ uᵢ vᵢ.
_dot_vector_rhs(u_symbol, u_kind, v_symbol, v_kind) =
  _sum_terms([_product(_vector_component(u_symbol, u_kind, i), _vector_component(v_symbol, v_kind, i)) for i in 1:3])


# Tensor Frobenius inner product rhs:  Σᵢⱼ Aᵢⱼ Bᵢⱼ.
_dot_tensor_rhs(A_symbol, A_kind, B_symbol, B_kind) =
  _sum_terms([_product(_tensor_component(A_symbol, A_kind, i, j), _tensor_component(B_symbol, B_kind, i, j)) for i in 1:3 for j in 1:3])


# Cross product component i:  with cyclic (j, k), uⱼ v_k − u_k vⱼ.
function _cross_formula(left_symbol, left_kind, right_symbol, right_kind)
  return function (i)
    j = mod1(i + 1, 3)
    k = mod1(i + 2, 3)
    first_term  = _product(_vector_component(left_symbol, left_kind, j), _vector_component(right_symbol, right_kind, k))
    second_term = _product(_vector_component(left_symbol, left_kind, k), _vector_component(right_symbol, right_kind, j))
    return :($first_term .- $second_term)
  end
end


# Tensor-on-vector left action component i:  Σⱼ Aᵢⱼ uⱼ.
_tensor_vector_formula(A_symbol, A_kind, u_symbol, u_kind) =
  i -> _sum_terms([_product(_tensor_component(A_symbol, A_kind, i, j), _vector_component(u_symbol, u_kind, j)) for j in 1:3])


# Vector-on-tensor right action component i:  Σⱼ uⱼ Aⱼᵢ.
_vector_tensor_formula(u_symbol, u_kind, A_symbol, A_kind) =
  i -> _sum_terms([_product(_vector_component(u_symbol, u_kind, j), _tensor_component(A_symbol, A_kind, j, i)) for j in 1:3])


# Tensor-tensor product component (i, j):  Σₖ Aᵢₖ Bₖⱼ.
_tensor_tensor_formula(A_symbol, A_kind, B_symbol, B_kind) =
  (i, j) -> _sum_terms([_product(_tensor_component(A_symbol, A_kind, i, k), _tensor_component(B_symbol, B_kind, k, j)) for k in 1:3])


# Transpose component (i, j):  Aⱼᵢ.
_transpose_formula(A_symbol, A_kind) = (i, j) -> _tensor_component(A_symbol, A_kind, j, i)


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

For vector arguments this is the Euclidean scalar product `uᵢ vᵢ`; for second-order tensors it is the Frobenius double contraction `Aᵢⱼ Bᵢⱼ`. Either argument order is accepted.

Contraction of two fields is nonlinear and defined only in physical-space representation. In spectral representation only contraction with a constant fiber vector or fiber tensor is provided, which keeps the operation coefficient-wise.
"""
function dot! end


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

Compute a fiberwise cross product `u × v` in-place; returns `destination`.

Cross products of two fields are nonlinear and defined only in physical-space representation. In spectral representation only the cross product with a constant fiber vector (either argument order) is provided, which keeps the operation coefficient-wise.
"""
function cross! end


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
    mul!(destination::VectorFieldPhysical, A::TensorFieldPhysical{2}, u::VectorFieldPhysical[, α, β])
    mul!(destination::VectorFieldPhysical, A::TensorFieldPhysical{2}, a::FiberVector[, α, β])
    mul!(destination::VectorFieldSpectral, A::FiberTensor2, u::VectorFieldSpectral[, α, β])
    mul!(destination::TensorFieldPhysical{2}, A::TensorFieldPhysical{2}, B::TensorFieldPhysical{2}[, α, β])
    mul!(destination::TensorFieldPhysical{2}, A::TensorFieldPhysical{2}, B::FiberTensor2[, α, β])

Compute a fiberwise tensor product in-place; returns `destination`.

For a vector destination this is the action of a second-order tensor on a vector: the left action `Aᵢⱼ uⱼ`, the right action `uⱼ Aⱼᵢ`. For a tensor destination it is the tensor product `(A B)ᵢⱼ = Aᵢₖ Bₖⱼ`.

Products of two fields are nonlinear and defined only in physical-space representation; spectral-space methods require one factor to be a constant fiber tensor or fiber vector. The five-argument form computes `destination = α * product + β * destination`. As with `LinearAlgebra.mul!`, `destination` must not share storage with any input.
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

Transpose the fiber indices of a second-order tensor field in-place: `destinationᵢⱼ = Aⱼᵢ`; returns `destination`.

The operation is linear and representation-preserving, so it is defined for both physical-space and spectral representations. Unlike Julia's matrix `transpose`, this writes a canonical tensor field rather than a lazy wrapper.
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

Compute the fiberwise norm of a field in physical-space representation in-place; returns `destination`.

This is the pointwise absolute value `abs(φ)` for scalar fields, the Euclidean norm `sqrt(uᵢ uᵢ)` for vector fields, and the Frobenius norm `sqrt(Aᵢⱼ Aᵢⱼ)` (not the operator norm) for second-order tensor fields. The norm is nonlinear and is not defined for spectral representation.
"""
function norm! end


@eval _norm_components!(destination, scalar_field::ScalarFieldPhysical) =
  $(_scalar_kernel_body(:(abs.(field_data(scalar_field)))))

@eval _norm_components!(destination, u::VectorFieldPhysical) =
  $(_scalar_kernel_body(:(sqrt.($(_sum_terms([:(abs2.($(_vector_component(:u, :field, i)))) for i in 1:3]))))))

@eval _norm_components!(destination, A::TensorFieldPhysical{2}) =
  $(_scalar_kernel_body(:(sqrt.($(_sum_terms([:(abs2.($(_tensor_component(:A, :field, i, j)))) for i in 1:3 for j in 1:3]))))))


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

Compute the symmetric part `sym(A) = (A + transpose(A)) / 2` of a second-order tensor field in-place; returns `destination`. Linear and representation-preserving, so defined for both representations.
"""
function sym! end


"""
    sym(A::TensorFieldPhysical{2})
    sym(A::TensorFieldSpectral{2})
    sym(A::FiberTensor2)

Allocate and compute the symmetric part of a second-order tensor; fiberwise for fields, and a constant fiber tensor for a constant fiber tensor.
"""
function sym end


"""
    skew!(destination::TensorFieldPhysical{2}, A::TensorFieldPhysical{2})
    skew!(destination::TensorFieldSpectral{2}, A::TensorFieldSpectral{2})

Compute the skew-symmetric part `skew(A) = (A - transpose(A)) / 2` of a second-order tensor field in-place; returns `destination`. Linear and representation-preserving, so defined for both representations.
"""
function skew! end


"""
    skew(A::TensorFieldPhysical{2})
    skew(A::TensorFieldSpectral{2})
    skew(A::FiberTensor2)

Allocate and compute the skew-symmetric part of a second-order tensor; fiberwise for fields, and a constant fiber tensor for a constant fiber tensor.
"""
function skew end


"""
    dev!(destination::TensorFieldPhysical{2}, A::TensorFieldPhysical{2})
    dev!(destination::TensorFieldSpectral{2}, A::TensorFieldSpectral{2})

Compute the deviatoric part `dev(A) = A - tr(A) * I / 3` of a second-order tensor field in-place; returns `destination`. Linear and representation-preserving, so defined for both representations.
"""
function dev! end


"""
    dev(A::TensorFieldPhysical{2})
    dev(A::TensorFieldSpectral{2})
    dev(A::FiberTensor2)

Allocate and compute the deviatoric part of a second-order tensor; fiberwise for fields, and a constant fiber tensor for a constant fiber tensor.
"""
function dev end


# Decomposition kernels. The symmetric/skew kernels need `half` and the
# deviatoric kernel needs `third`; both are scalar-type locals referenced by the
# generated per-component formulas. Index-shuffling, so wrapped by the guard.
@eval function _sym_components_noalias!(destination, A)
  half = inv(field_scalar_type(A)(2))
  $(_tensor_kernel_body((i, j) -> i == j ? _tensor_component(:A, :field, i, i) :
      :(half .* ($(_tensor_component(:A, :field, i, j)) .+ $(_tensor_component(:A, :field, j, i)))); alpha_beta = false))
end

@eval function _skew_components_noalias!(destination, A)
  half = inv(field_scalar_type(A)(2))
  $(_tensor_kernel_body((i, j) -> i == j ? :(zero(field_scalar_type(A))) :
      :(half .* ($(_tensor_component(:A, :field, i, j)) .- $(_tensor_component(:A, :field, j, i)))); alpha_beta = false))
end

@eval function _dev_components_noalias!(destination, A)
  third = inv(field_scalar_type(A)(3))
  trace = $(_sum_terms([_tensor_component(:A, :field, d, d) for d in 1:3]))
  $(_tensor_kernel_body((i, j) -> i == j ? :($(_tensor_component(:A, :field, i, i)) .- third .* trace) :
      _tensor_component(:A, :field, i, j); alpha_beta = false))
end


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
