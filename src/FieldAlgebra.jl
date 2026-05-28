#=
AI tips for code generation

Conceptual model
----------------
This package represents real periodic fields on rectangular Cartesian domains. A field is a physical object; physical-space and spectral representations are storage/manipulation representations of that same object. In docstrings, prefer "scalar/vector/tensor field in physical-space representation" and "scalar/vector/tensor field in spectral representation". Avoid phrases such as "physical field" and "spectral field" unless the grammar would otherwise become unnatural.

All exposed mathematical objects should be real-valued physical objects. Complex arrays are an implementation detail of spectral storage, not user-facing complex fields.

The fiber dimension is three. Fiber vectors and tensors use the Cartesian Euclidean structure. Do not introduce curvilinear-coordinate machinery, explicit metric tensors, or vector/covector distinctions unless the package design changes.

Physical meaning of operations
------------------------------
Operations should represent operations on the underlying physical fields. Implement an operation in spectral representation only when it is mathematically equivalent to the physical-space operation and is efficient or more accurate there. Otherwise, restrict the method to the representation where the operation is sensible.

Linear algebra operations on fields are fiberwise operations. For example, `dot`, `⋅`, `cross`, `×`, `mul!`, `transpose`, scalar multiplication, and vector-space operations act pointwise on the fiber. Global \(L^2\)-type products, norms, adjoints, and integration-based operators belong to separate code with explicit notation.

Do not expose coefficientwise spectral products if they are not the Fourier representation of the corresponding physical operation. In particular, scalar-field multiplication is physical-space pointwise multiplication, products of two vector or tensor fields are defined only in physical-space representation, contractions and linear actions with constant fiber objects are allowed in both representations, and addition of constants in spectral representation must update only the zero Fourier mode.

Fourier normalization
---------------------
For FFT normalization, follow the convention of the Julia FFT packages actually used by the implementation. Under the AbstractFFTs convention, forward transforms are unnormalized, while inverse transforms include normalization. Therefore adding a physical constant `c` to a spectral representation updates only the zero Fourier coefficient by `c * prod(grid_size)` for the transformed spatial grid. Do not add `c` to all spectral coefficients.

CPU/GPU portability
-------------------
Storage arrays must be generic `AbstractArray`s. Allocate output arrays with `similar(field_data(reference), ...)`. Avoid CPU-specific assumptions.

GPU-compatible code must avoid scalar indexing of GPU arrays in package methods. Use broadcast, `map`, `mapreduce`, `copyto!`, views with broadcasted assignment, or explicit kernels when needed. Test CUDA and AMDGPU paths with scalar indexing disabled. Be careful with wrapped GPU arrays and nested views: if a wrapper causes fallback scalar iteration, rewrite the operation or use a backend-appropriate kernel.

Mutating methods should write into existing storage and return the modified destination. Prefer fused broadcasted assignments such as `destination_data .= expression` for elementwise operations. Use explicit small-component formulas for three-component vector and second-order tensor operations when this is clearer and avoids reductions over the fiber dimension.

Do not add or suggest symmetric mixed-representation broadcast-style rules. Julia's broadcast style promotion only needs one binary method for a pair of styles.

Julia style
-----------
Use idiomatic Julia dispatch. Avoid type piracy: do not extend external functions on argument types that all belong to other packages. Extend external functions only when at least one argument type belongs to this package.

Import external functions before extending them, e.g. `import Base: +, -, *, /` and `import LinearAlgebra: dot, ⋅, cross, ×, mul!`.

For package-owned generic functions, attach the operation docstring to `function f end`. For additional method-family documentation on an already-defined package-owned generic, attach the docstring to the existing bare binding `f`. For imported Base, LinearAlgebra, or package functions, attach package-specific method-family documentation to the imported binding using the bare name `f`; do not write `function f end`, since a missing import could silently create a new local generic.

Do not define methods for pure fiber-fiber operations such as `dot(::FiberVector, ::FiberVector)` or `transpose(::FiberTensor2)`: these fiber types are aliases for StaticArrays types, and LinearAlgebra/StaticArrays already handles such operations.

Use descriptive names. Avoid abbreviations unless they are standard mathematical notation. Use two-space indentation. Follow the existing code style in this package. Normal Julia code may use moderately long lines when this improves readability or matches the surrounding style; do not aggressively split ordinary function signatures. In docstrings, prose may also use long lines, but verbatim signatures and code examples should remain conservatively narrow because Documenter renders them in a documentation column.

Avoid unnecessary explicit type declarations in local variables. Do not compute matrix inverses for linear solves; use `\`, factorizations followed by `\`, or `ldiv!` where an in-place solve is appropriate.

When relying on Julia, Base, standard libraries, or other Julia package behavior, always check the official documentation or docstrings.

Docstring style
---------------
Docstrings should be short, concrete, and physically meaningful. Prefer direct statements of what the method computes, in which representation it is valid, and whether it allocates or mutates.

Use representation-based terminology:
    good: "scalar field in physical-space representation"
    bad:  "physical scalar field"

State whether an operation is pointwise in physical-space representation, coefficientwise in spectral representation, representation-preserving, a zero-mode update, or a fiberwise contraction.

Use "real number" for `Real` scalar constants when this avoids confusion with scalar fields. Use "scalar field" only for field-valued scalar functions. Use "fiber vector" and "fiber tensor" for constant elements of the fiber.

Mention when a method is intentionally not provided because the operation is not physically meaningful in that representation.

Maintenance
-----------
Keep this AI-tips block updated when new project requirements are established, and check generated code against it before returning changes.
=#

"""
    FieldAlgebra

Fiberwise algebraic operations on fields in physical-space and spectral representations.

This module provides local algebra on scalar, vector, and tensor fibers. The operations act on the physical field represented by the data, not on the storage representation as an object of interest.

Provided operations include:

- field vector-space operations: `+`, `-`, `add!`, `subtract!`;
- multiplication and division by real numbers: `*`, `/`, `multiply!`, `divide!`;
- scalar-field multiplication and division where representation-wise meaningful;
- constant additions to scalar, vector, and second-order tensor fields;
- vector operations: `dot`, `⋅`, `cross`, `×`, `dot!`, `cross!`;
- second-order tensor operations: `mul!`, `*`, `transpose`, `transpose!`, `sym`, `skew`, `dev`, `norm`;
- tensor contractions: Frobenius inner products through `dot` and `dot!`.

Representation rules:

- operations in physical-space representation are pointwise;
- linear operations are also defined in spectral representation when they can be applied coefficient-wise;
- constant additions in spectral representation update only the zero Fourier mode;
- nonlinear products, divisions, and norms are restricted to physical-space representation unless one non-scalar factor is a constant fiber object.

Global products, global norms, integration-based adjoints, and differential operators are intentionally outside this module.
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
  check_field_compatibility


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


_spectral_constant_scale(field::AbstractFieldSpectral{T}) where {T<:AbstractFloat} =
  prod(T.(field_grid(field).grid_size))


_spectral_zero_mode_data(field::ScalarFieldSpectral) = view(field_data(field), 1:1, 1:1, 1:1)


_spectral_zero_mode_component_data(field::VectorFieldSpectral, component) = view(field_data(field), 1:1, 1:1, 1:1, component:component)


_spectral_zero_mode_component_data(field::TensorFieldSpectral{2}, first_index, second_index) =
  view(field_data(field), 1:1, 1:1, 1:1, first_index:first_index, second_index:second_index)


_vector_component_data(field::Union{VectorFieldPhysical, VectorFieldSpectral}, component) =
  selectdim(field_data(field), ndims(field_data(field)), component)


function _tensor2_component_data(field::Union{TensorFieldPhysical{2}, TensorFieldSpectral{2}}, first_index, second_index)
  data = field_data(field)
  return selectdim(selectdim(data, ndims(data) - 1, first_index), ndims(data) - 1, second_index)
end


function _check_scalar_field_compatibility(scalar_field::ScalarFieldPhysical, field::AbstractFieldPhysical)
  field_scalar_type(scalar_field) == field_scalar_type(field) || throw(ArgumentError("field scalar types must be equal"))
  field_grid(scalar_field) == field_grid(field) || throw(ArgumentError("field grids must be equal"))
  field_layout(scalar_field) == field_layout(field) || throw(ArgumentError("field Fourier layouts must be equal"))
  return nothing
end


function _check_scalar_field_compatibility(scalar_field::ScalarFieldSpectral, field::AbstractFieldSpectral)
  field_scalar_type(scalar_field) == field_scalar_type(field) || throw(ArgumentError("field scalar types must be equal"))
  field_grid(scalar_field) == field_grid(field) || throw(ArgumentError("field grids must be equal"))
  field_layout(scalar_field) == field_layout(field) || throw(ArgumentError("field Fourier layouts must be equal"))
  return nothing
end


function _field_data_aliases(destination, fields...)
  destination_data = field_data(destination)

  return any(field -> field_data(field) === destination_data, fields)
end


function _apply_unary_tensor2_noalias!(operation!, destination, A)
  if field_data(destination) === field_data(A)
    temporary = similar_field(destination, Val(2))
    operation!(temporary, A)
    copyto!(field_data(destination), field_data(temporary))

    return destination
  end

  return operation!(destination, A)
end


#####################################################
#        Field Addition and Subtraction             #
#####################################################


"""
    add!(
      destination::AbstractFieldPhysical,
      a::AbstractFieldPhysical,
      b::AbstractFieldPhysical,
      fields::AbstractFieldPhysical...,
    )

    add!(
      destination::AbstractFieldSpectral,
      a::AbstractFieldSpectral,
      b::AbstractFieldSpectral,
      fields::AbstractFieldSpectral...,
    )

    add!(
      destination::ScalarFieldPhysical,
      field::ScalarFieldPhysical,
      scalar::Real,
    )

    add!(
      destination::ScalarFieldSpectral,
      field::ScalarFieldSpectral,
      scalar::Real,
    )

    add!(
      destination::VectorFieldPhysical,
      field::VectorFieldPhysical,
      a::FiberVector,
    )

    add!(
      destination::VectorFieldSpectral,
      field::VectorFieldSpectral,
      a::FiberVector,
    )

    add!(
      destination::TensorFieldPhysical{2},
      field::TensorFieldPhysical{2},
      A::FiberTensor2,
    )

    add!(
      destination::TensorFieldSpectral{2},
      field::TensorFieldSpectral{2},
      A::FiberTensor2,
    )

Add fields or constants in-place.

Field-field addition is storage-wise and representation-preserving: pointwise for fields in physical-space representation and coefficientwise
for fields in spectral representation.

Adding a real number is defined for scalar fields. In physical-space representation it adds the number to all grid-point values.
In spectral representation it modifies only the zero Fourier coefficient.

Adding a constant fiber vector is defined for vector fields. In physical-space representation it adds the vector to all grid-point values.
In spectral representation it modifies only the zero Fourier coefficient of each vector component.

Adding a constant second-order fiber tensor is defined for second-order tensor fields. In physical-space representation it adds the tensor
to all grid-point values. In spectral representation it modifies only the zero Fourier coefficient of each tensor component.

Returns the modified `destination` field.
"""
function add! end


@inline _add_values(x, y) = x + y
@inline _add_values(x, y, z, rest...) = _add_values(x + y, z, rest...)

@inline _subtract_values(x, y) = x - y
@inline _subtract_values(x, y, z, rest...) = _subtract_values(x - y, z, rest...)


function _add_scalar_constant!(field::ScalarFieldSpectral{T}, scalar::Real) where {T<:AbstractFloat}
  _spectral_zero_mode_data(field) .+= _spectral_constant_scale(field) * T(scalar)
  return field
end


function _subtract_scalar_constant!(field::ScalarFieldSpectral{T}, scalar::Real) where {T<:AbstractFloat}
  _spectral_zero_mode_data(field) .-= _spectral_constant_scale(field) * T(scalar)
  return field
end


function _add_fiber_vector!(field::VectorFieldPhysical{T}, a::FiberVector{T}) where {T<:AbstractFloat}
  _vector_component_data(field, 1) .+= a[1]
  _vector_component_data(field, 2) .+= a[2]
  _vector_component_data(field, 3) .+= a[3]

  return field
end


function _subtract_fiber_vector!(field::VectorFieldPhysical{T}, a::FiberVector{T}) where {T<:AbstractFloat}
  _vector_component_data(field, 1) .-= a[1]
  _vector_component_data(field, 2) .-= a[2]
  _vector_component_data(field, 3) .-= a[3]

  return field
end


function _add_fiber_vector!(field::VectorFieldSpectral{T}, a::FiberVector{T}) where {T<:AbstractFloat}
  scale = _spectral_constant_scale(field)

  _spectral_zero_mode_component_data(field, 1) .+= scale * a[1]
  _spectral_zero_mode_component_data(field, 2) .+= scale * a[2]
  _spectral_zero_mode_component_data(field, 3) .+= scale * a[3]

  return field
end


function _subtract_fiber_vector!(field::VectorFieldSpectral{T}, a::FiberVector{T}) where {T<:AbstractFloat}
  scale = _spectral_constant_scale(field)

  _spectral_zero_mode_component_data(field, 1) .-= scale * a[1]
  _spectral_zero_mode_component_data(field, 2) .-= scale * a[2]
  _spectral_zero_mode_component_data(field, 3) .-= scale * a[3]

  return field
end


function _add_fiber_tensor2!(field::TensorFieldPhysical{2, T}, A::FiberTensor2{T}) where {T<:AbstractFloat}
  _tensor2_component_data(field, 1, 1) .+= A[1, 1]
  _tensor2_component_data(field, 1, 2) .+= A[1, 2]
  _tensor2_component_data(field, 1, 3) .+= A[1, 3]
  _tensor2_component_data(field, 2, 1) .+= A[2, 1]
  _tensor2_component_data(field, 2, 2) .+= A[2, 2]
  _tensor2_component_data(field, 2, 3) .+= A[2, 3]
  _tensor2_component_data(field, 3, 1) .+= A[3, 1]
  _tensor2_component_data(field, 3, 2) .+= A[3, 2]
  _tensor2_component_data(field, 3, 3) .+= A[3, 3]

  return field
end


function _subtract_fiber_tensor2!(field::TensorFieldPhysical{2, T}, A::FiberTensor2{T}) where {T<:AbstractFloat}
  _tensor2_component_data(field, 1, 1) .-= A[1, 1]
  _tensor2_component_data(field, 1, 2) .-= A[1, 2]
  _tensor2_component_data(field, 1, 3) .-= A[1, 3]
  _tensor2_component_data(field, 2, 1) .-= A[2, 1]
  _tensor2_component_data(field, 2, 2) .-= A[2, 2]
  _tensor2_component_data(field, 2, 3) .-= A[2, 3]
  _tensor2_component_data(field, 3, 1) .-= A[3, 1]
  _tensor2_component_data(field, 3, 2) .-= A[3, 2]
  _tensor2_component_data(field, 3, 3) .-= A[3, 3]

  return field
end


function _add_fiber_tensor2!(field::TensorFieldSpectral{2, T}, A::FiberTensor2{T}) where {T<:AbstractFloat}
  scale = _spectral_constant_scale(field)

  _spectral_zero_mode_component_data(field, 1, 1) .+= scale * A[1, 1]
  _spectral_zero_mode_component_data(field, 1, 2) .+= scale * A[1, 2]
  _spectral_zero_mode_component_data(field, 1, 3) .+= scale * A[1, 3]
  _spectral_zero_mode_component_data(field, 2, 1) .+= scale * A[2, 1]
  _spectral_zero_mode_component_data(field, 2, 2) .+= scale * A[2, 2]
  _spectral_zero_mode_component_data(field, 2, 3) .+= scale * A[2, 3]
  _spectral_zero_mode_component_data(field, 3, 1) .+= scale * A[3, 1]
  _spectral_zero_mode_component_data(field, 3, 2) .+= scale * A[3, 2]
  _spectral_zero_mode_component_data(field, 3, 3) .+= scale * A[3, 3]

  return field
end


function _subtract_fiber_tensor2!(field::TensorFieldSpectral{2, T}, A::FiberTensor2{T}) where {T<:AbstractFloat}
  scale = _spectral_constant_scale(field)

  _spectral_zero_mode_component_data(field, 1, 1) .-= scale * A[1, 1]
  _spectral_zero_mode_component_data(field, 1, 2) .-= scale * A[1, 2]
  _spectral_zero_mode_component_data(field, 1, 3) .-= scale * A[1, 3]
  _spectral_zero_mode_component_data(field, 2, 1) .-= scale * A[2, 1]
  _spectral_zero_mode_component_data(field, 2, 2) .-= scale * A[2, 2]
  _spectral_zero_mode_component_data(field, 2, 3) .-= scale * A[2, 3]
  _spectral_zero_mode_component_data(field, 3, 1) .-= scale * A[3, 1]
  _spectral_zero_mode_component_data(field, 3, 2) .-= scale * A[3, 2]
  _spectral_zero_mode_component_data(field, 3, 3) .-= scale * A[3, 3]

  return field
end


function add!(destination::AbstractFieldPhysical, a::AbstractFieldPhysical, b::AbstractFieldPhysical, fields::AbstractFieldPhysical...)
  destination .= _add_values.(a, b, fields...)
  return destination
end


function add!(destination::AbstractFieldSpectral, a::AbstractFieldSpectral, b::AbstractFieldSpectral, fields::AbstractFieldSpectral...)
  destination .= _add_values.(a, b, fields...)
  return destination
end


function add!(destination::ScalarFieldPhysical, field::ScalarFieldPhysical, scalar::Real)
  destination .= field .+ scalar
  return destination
end


function add!(destination::ScalarFieldPhysical, scalar::Real, field::ScalarFieldPhysical)
  return add!(destination, field, scalar)
end


function add!(destination::ScalarFieldSpectral, field::ScalarFieldSpectral, scalar::Real)
  check_field_compatibility(destination, field)
  _copy_field_data!(destination, field)
  return _add_scalar_constant!(destination, scalar)
end


function add!(destination::ScalarFieldSpectral, scalar::Real, field::ScalarFieldSpectral)
  return add!(destination, field, scalar)
end


function add!(destination::VectorFieldPhysical{T}, field::VectorFieldPhysical{T}, a::FiberVector{T}) where {T<:AbstractFloat}
  check_field_compatibility(destination, field)
  _copy_field_data!(destination, field)
  return _add_fiber_vector!(destination, a)
end


function add!(destination::VectorFieldPhysical{T}, a::FiberVector{T}, field::VectorFieldPhysical{T}) where {T<:AbstractFloat}
  return add!(destination, field, a)
end


function add!(destination::VectorFieldSpectral{T}, field::VectorFieldSpectral{T}, a::FiberVector{T}) where {T<:AbstractFloat}
  check_field_compatibility(destination, field)
  _copy_field_data!(destination, field)
  return _add_fiber_vector!(destination, a)
end


function add!(destination::VectorFieldSpectral{T}, a::FiberVector{T}, field::VectorFieldSpectral{T}) where {T<:AbstractFloat}
  return add!(destination, field, a)
end


function add!(destination::TensorFieldPhysical{2, T}, field::TensorFieldPhysical{2, T}, A::FiberTensor2{T}) where {T<:AbstractFloat}
  check_field_compatibility(destination, field)
  _copy_field_data!(destination, field)
  return _add_fiber_tensor2!(destination, A)
end


function add!(destination::TensorFieldPhysical{2, T}, A::FiberTensor2{T}, field::TensorFieldPhysical{2, T}) where {T<:AbstractFloat}
  return add!(destination, field, A)
end


function add!(destination::TensorFieldSpectral{2, T}, field::TensorFieldSpectral{2, T}, A::FiberTensor2{T}) where {T<:AbstractFloat}
  check_field_compatibility(destination, field)
  _copy_field_data!(destination, field)
  return _add_fiber_tensor2!(destination, A)
end


function add!(destination::TensorFieldSpectral{2, T}, A::FiberTensor2{T}, field::TensorFieldSpectral{2, T}) where {T<:AbstractFloat}
  return add!(destination, field, A)
end


"""
    subtract!(
      destination::AbstractFieldPhysical,
      a::AbstractFieldPhysical,
      b::AbstractFieldPhysical,
      fields::AbstractFieldPhysical...,
    )

    subtract!(
      destination::AbstractFieldSpectral,
      a::AbstractFieldSpectral,
      b::AbstractFieldSpectral,
      fields::AbstractFieldSpectral...,
    )

    subtract!(
      destination::ScalarFieldPhysical,
      field::ScalarFieldPhysical,
      scalar::Real,
    )

    subtract!(
      destination::ScalarFieldSpectral,
      field::ScalarFieldSpectral,
      scalar::Real,
    )

    subtract!(
      destination::VectorFieldPhysical,
      field::VectorFieldPhysical,
      a::FiberVector,
    )

    subtract!(
      destination::VectorFieldSpectral,
      field::VectorFieldSpectral,
      a::FiberVector,
    )

    subtract!(
      destination::TensorFieldPhysical{2},
      field::TensorFieldPhysical{2},
      A::FiberTensor2,
    )

    subtract!(
      destination::TensorFieldSpectral{2},
      field::TensorFieldSpectral{2},
      A::FiberTensor2,
    )

Subtract fields or constants in-place.

Field-field subtraction is storage-wise and representation-preserving, computing `a - b - fields...`.

Subtracting a real number is defined for scalar fields. In physical-space representation it subtracts the number from all grid-point values.
In spectral representation it modifies only the zero Fourier coefficient.

Subtracting a constant fiber vector is defined for vector fields. In physical-space representation it subtracts the vector from all grid-point values.
In spectral representation it modifies only the zero Fourier coefficient of each vector component.

Subtracting a constant second-order fiber tensor is defined for second-order tensor fields. In physical-space representation it subtracts the tensor
from all grid-point values. In spectral representation it modifies only the zero Fourier coefficient of each tensor component.

Returns the modified `destination` field.
"""
function subtract! end


function subtract!(destination::AbstractFieldPhysical, a::AbstractFieldPhysical, b::AbstractFieldPhysical, fields::AbstractFieldPhysical...)
  destination .= _subtract_values.(a, b, fields...)
  return destination
end


function subtract!(destination::AbstractFieldSpectral, a::AbstractFieldSpectral, b::AbstractFieldSpectral, fields::AbstractFieldSpectral...)
  destination .= _subtract_values.(a, b, fields...)
  return destination
end


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


function subtract!(destination::VectorFieldPhysical{T}, field::VectorFieldPhysical{T}, a::FiberVector{T}) where {T<:AbstractFloat}
  check_field_compatibility(destination, field)
  _copy_field_data!(destination, field)
  return _subtract_fiber_vector!(destination, a)
end


function subtract!(destination::VectorFieldPhysical{T}, a::FiberVector{T}, field::VectorFieldPhysical{T}) where {T<:AbstractFloat}
  check_field_compatibility(destination, field)
  field_data(destination) .= (-).(field_data(field))
  return _add_fiber_vector!(destination, a)
end


function subtract!(destination::VectorFieldSpectral{T}, field::VectorFieldSpectral{T}, a::FiberVector{T}) where {T<:AbstractFloat}
  check_field_compatibility(destination, field)
  _copy_field_data!(destination, field)
  return _subtract_fiber_vector!(destination, a)
end


function subtract!(destination::VectorFieldSpectral{T}, a::FiberVector{T}, field::VectorFieldSpectral{T}) where {T<:AbstractFloat}
  check_field_compatibility(destination, field)
  field_data(destination) .= (-).(field_data(field))
  return _add_fiber_vector!(destination, a)
end


function subtract!(destination::TensorFieldPhysical{2, T}, field::TensorFieldPhysical{2, T}, A::FiberTensor2{T}) where {T<:AbstractFloat}
  check_field_compatibility(destination, field)
  _copy_field_data!(destination, field)
  return _subtract_fiber_tensor2!(destination, A)
end


function subtract!(destination::TensorFieldPhysical{2, T}, A::FiberTensor2{T}, field::TensorFieldPhysical{2, T}) where {T<:AbstractFloat}
  check_field_compatibility(destination, field)
  field_data(destination) .= (-).(field_data(field))
  return _add_fiber_tensor2!(destination, A)
end


function subtract!(destination::TensorFieldSpectral{2, T}, field::TensorFieldSpectral{2, T}, A::FiberTensor2{T}) where {T<:AbstractFloat}
  check_field_compatibility(destination, field)
  _copy_field_data!(destination, field)
  return _subtract_fiber_tensor2!(destination, A)
end


function subtract!(destination::TensorFieldSpectral{2, T}, A::FiberTensor2{T}, field::TensorFieldSpectral{2, T}) where {T<:AbstractFloat}
  check_field_compatibility(destination, field)
  field_data(destination) .= (-).(field_data(field))
  return _add_fiber_tensor2!(destination, A)
end


+(field::AbstractField) = field


function +(a::AbstractFieldPhysical, b::AbstractFieldPhysical, fields::AbstractFieldPhysical...)
  return _add_values.(a, b, fields...)
end


function +(a::AbstractFieldSpectral, b::AbstractFieldSpectral, fields::AbstractFieldSpectral...)
  return _add_values.(a, b, fields...)
end


function +(field::ScalarFieldPhysical, scalar::Real)
  destination = similar_field(field, similar(field_data(field)))
  return add!(destination, field, scalar)
end


function +(scalar::Real, field::ScalarFieldPhysical)
  destination = similar_field(field, similar(field_data(field)))
  return add!(destination, scalar, field)
end


function +(field::ScalarFieldSpectral, scalar::Real)
  destination = similar_field(field, similar(field_data(field)))
  return add!(destination, field, scalar)
end


function +(scalar::Real, field::ScalarFieldSpectral)
  destination = similar_field(field, similar(field_data(field)))
  return add!(destination, scalar, field)
end


function +(field::VectorFieldPhysical{T}, a::FiberVector{T}) where {T<:AbstractFloat}
  destination = similar_field(field, similar(field_data(field)))
  return add!(destination, field, a)
end


function +(a::FiberVector{T}, field::VectorFieldPhysical{T}) where {T<:AbstractFloat}
  destination = similar_field(field, similar(field_data(field)))
  return add!(destination, a, field)
end


function +(field::VectorFieldSpectral{T}, a::FiberVector{T}) where {T<:AbstractFloat}
  destination = similar_field(field, similar(field_data(field)))
  return add!(destination, field, a)
end


function +(a::FiberVector{T}, field::VectorFieldSpectral{T}) where {T<:AbstractFloat}
  destination = similar_field(field, similar(field_data(field)))
  return add!(destination, a, field)
end


function +(field::TensorFieldPhysical{2, T}, A::FiberTensor2{T}) where {T<:AbstractFloat}
  destination = similar_field(field, similar(field_data(field)))
  return add!(destination, field, A)
end


function +(A::FiberTensor2{T}, field::TensorFieldPhysical{2, T}) where {T<:AbstractFloat}
  destination = similar_field(field, similar(field_data(field)))
  return add!(destination, A, field)
end


function +(field::TensorFieldSpectral{2, T}, A::FiberTensor2{T}) where {T<:AbstractFloat}
  destination = similar_field(field, similar(field_data(field)))
  return add!(destination, field, A)
end


function +(A::FiberTensor2{T}, field::TensorFieldSpectral{2, T}) where {T<:AbstractFloat}
  destination = similar_field(field, similar(field_data(field)))
  return add!(destination, A, field)
end


function -(field::AbstractField)
  return (-).(field)
end


function -(a::AbstractFieldPhysical, b::AbstractFieldPhysical, fields::AbstractFieldPhysical...)
  return _subtract_values.(a, b, fields...)
end


function -(a::AbstractFieldSpectral, b::AbstractFieldSpectral, fields::AbstractFieldSpectral...)
  return _subtract_values.(a, b, fields...)
end


function -(field::ScalarFieldPhysical, scalar::Real)
  destination = similar_field(field, similar(field_data(field)))
  return subtract!(destination, field, scalar)
end


function -(scalar::Real, field::ScalarFieldPhysical)
  destination = similar_field(field, similar(field_data(field)))
  return subtract!(destination, scalar, field)
end


function -(field::ScalarFieldSpectral, scalar::Real)
  destination = similar_field(field, similar(field_data(field)))
  return subtract!(destination, field, scalar)
end


function -(scalar::Real, field::ScalarFieldSpectral)
  destination = similar_field(field, similar(field_data(field)))
  return subtract!(destination, scalar, field)
end


function -(field::VectorFieldPhysical{T}, a::FiberVector{T}) where {T<:AbstractFloat}
  destination = similar_field(field, similar(field_data(field)))
  return subtract!(destination, field, a)
end


function -(a::FiberVector{T}, field::VectorFieldPhysical{T}) where {T<:AbstractFloat}
  destination = similar_field(field, similar(field_data(field)))
  return subtract!(destination, a, field)
end


function -(field::VectorFieldSpectral{T}, a::FiberVector{T}) where {T<:AbstractFloat}
  destination = similar_field(field, similar(field_data(field)))
  return subtract!(destination, field, a)
end


function -(a::FiberVector{T}, field::VectorFieldSpectral{T}) where {T<:AbstractFloat}
  destination = similar_field(field, similar(field_data(field)))
  return subtract!(destination, a, field)
end


function -(field::TensorFieldPhysical{2, T}, A::FiberTensor2{T}) where {T<:AbstractFloat}
  destination = similar_field(field, similar(field_data(field)))
  return subtract!(destination, field, A)
end


function -(A::FiberTensor2{T}, field::TensorFieldPhysical{2, T}) where {T<:AbstractFloat}
  destination = similar_field(field, similar(field_data(field)))
  return subtract!(destination, A, field)
end


function -(field::TensorFieldSpectral{2, T}, A::FiberTensor2{T}) where {T<:AbstractFloat}
  destination = similar_field(field, similar(field_data(field)))
  return subtract!(destination, field, A)
end


function -(A::FiberTensor2{T}, field::TensorFieldSpectral{2, T}) where {T<:AbstractFloat}
  destination = similar_field(field, similar(field_data(field)))
  return subtract!(destination, A, field)
end


#####################################################
#        Multiplication by Real Numbers             #
#####################################################


"""
    multiply!(
      destination::AbstractFieldPhysical,
      scalar::Real,
      field::AbstractFieldPhysical,
    )

    multiply!(
      destination::AbstractFieldPhysical,
      field::AbstractFieldPhysical,
      scalar::Real,
    )

    multiply!(
      destination::AbstractFieldSpectral,
      scalar::Real,
      field::AbstractFieldSpectral,
    )

    multiply!(
      destination::AbstractFieldSpectral,
      field::AbstractFieldSpectral,
      scalar::Real,
    )

Multiply a field in-place by a real number.

Multiplication by a real number is representation-preserving and applies to fields represented in physical or spectral space.

Returns the modified `destination` field.
"""
function multiply! end


function multiply!(destination::AbstractFieldPhysical, scalar::Real, field::AbstractFieldPhysical)
  destination .= scalar .* field
  return destination
end


function multiply!(destination::AbstractFieldPhysical, field::AbstractFieldPhysical, scalar::Real)
  destination .= field .* scalar
  return destination
end


function multiply!(destination::AbstractFieldSpectral, scalar::Real, field::AbstractFieldSpectral)
  destination .= scalar .* field
  return destination
end


function multiply!(destination::AbstractFieldSpectral, field::AbstractFieldSpectral, scalar::Real)
  destination .= field .* scalar
  return destination
end


"""
    divide!(
      destination::AbstractFieldPhysical,
      field::AbstractFieldPhysical,
      scalar::Real,
    )

    divide!(
      destination::AbstractFieldSpectral,
      field::AbstractFieldSpectral,
      scalar::Real,
    )

Divide a field in-place by a real number.

Division by a real number is representation-preserving and applies to fields represented in physical or spectral space.

Returns the modified `destination` field.
"""
function divide! end


function divide!(destination::AbstractFieldPhysical, field::AbstractFieldPhysical, scalar::Real)
  destination .= field ./ scalar
  return destination
end


function divide!(destination::AbstractFieldSpectral, field::AbstractFieldSpectral, scalar::Real)
  destination .= field ./ scalar
  return destination
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


"""
    multiply!(
      destination::AbstractFieldPhysical,
      scalar_field::ScalarFieldPhysical,
      field::AbstractFieldPhysical,
    )

    multiply!(
      destination::AbstractFieldPhysical,
      field::AbstractFieldPhysical,
      scalar_field::ScalarFieldPhysical,
    )

    multiply!(
      destination::VectorFieldPhysical,
      scalar_field::ScalarFieldPhysical,
      a::FiberVector,
    )

    multiply!(
      destination::VectorFieldSpectral,
      scalar_field::ScalarFieldSpectral,
      a::FiberVector,
    )

    multiply!(
      destination::TensorFieldPhysical{2},
      scalar_field::ScalarFieldPhysical,
      A::FiberTensor2,
    )

    multiply!(
      destination::TensorFieldSpectral{2},
      scalar_field::ScalarFieldSpectral,
      A::FiberTensor2,
    )

Multiply by a scalar field in-place.

Multiplication by a scalar field in physical-space representation is pointwise and acts on all tensor components of the field.

Multiplication of a scalar field by a constant fiber vector or a constant second-order fiber tensor is defined in both representations.
In physical-space representation it is pointwise. In spectral representation it is coefficient-wise,
because the operation is linear in the scalar field.

Returns the modified `destination` field.
"""
multiply!


function _scalar_field_broadcast_data(scalar_field::ScalarFieldPhysical, field::AbstractFieldPhysical)
  singleton_fiber_shape = ntuple(_ -> 1, field_tensor_order(field))
  return reshape(field_data(scalar_field), size(field_data(scalar_field))..., singleton_fiber_shape...)
end


function _multiply_scalar_field_by_fiber_vector!(destination, scalar_field, a::FiberVector)
  _check_scalar_field_compatibility(scalar_field, destination)

  scalar_data = field_data(scalar_field)

  _vector_component_data(destination, 1) .= scalar_data .* a[1]
  _vector_component_data(destination, 2) .= scalar_data .* a[2]
  _vector_component_data(destination, 3) .= scalar_data .* a[3]

  return destination
end


function _multiply_scalar_field_by_fiber_tensor2!(destination, scalar_field, A::FiberTensor2)
  _check_scalar_field_compatibility(scalar_field, destination)

  scalar_data = field_data(scalar_field)

  _tensor2_component_data(destination, 1, 1) .= scalar_data .* A[1, 1]
  _tensor2_component_data(destination, 1, 2) .= scalar_data .* A[1, 2]
  _tensor2_component_data(destination, 1, 3) .= scalar_data .* A[1, 3]
  _tensor2_component_data(destination, 2, 1) .= scalar_data .* A[2, 1]
  _tensor2_component_data(destination, 2, 2) .= scalar_data .* A[2, 2]
  _tensor2_component_data(destination, 2, 3) .= scalar_data .* A[2, 3]
  _tensor2_component_data(destination, 3, 1) .= scalar_data .* A[3, 1]
  _tensor2_component_data(destination, 3, 2) .= scalar_data .* A[3, 2]
  _tensor2_component_data(destination, 3, 3) .= scalar_data .* A[3, 3]

  return destination
end


function _multiply_by_scalar_field!(destination::AbstractFieldPhysical, scalar_field::ScalarFieldPhysical, field::AbstractFieldPhysical)
  check_field_compatibility(destination, field)
  _check_scalar_field_compatibility(scalar_field, field)

  field_data(destination) .= _scalar_field_broadcast_data(scalar_field, field) .* field_data(field)

  return destination
end


function multiply!(destination::AbstractFieldPhysical, scalar_field::ScalarFieldPhysical, field::AbstractFieldPhysical)
  return _multiply_by_scalar_field!(destination, scalar_field, field)
end


function multiply!(destination::AbstractFieldPhysical, field::AbstractFieldPhysical, scalar_field::ScalarFieldPhysical)
  return _multiply_by_scalar_field!(destination, scalar_field, field)
end


function multiply!(destination::ScalarFieldPhysical, a::ScalarFieldPhysical, b::ScalarFieldPhysical)
  return _multiply_by_scalar_field!(destination, a, b)
end


function multiply!(destination::AbstractFieldPhysical, a::ScalarFieldPhysical, b::ScalarFieldPhysical)
  return _multiply_by_scalar_field!(destination, a, b)
end


function multiply!(destination::VectorFieldPhysical{T}, scalar_field::ScalarFieldPhysical{T}, a::FiberVector{T}) where {T<:AbstractFloat}
  return _multiply_scalar_field_by_fiber_vector!(destination, scalar_field, a)
end


function multiply!(destination::VectorFieldPhysical{T}, a::FiberVector{T}, scalar_field::ScalarFieldPhysical{T}) where {T<:AbstractFloat}
  return multiply!(destination, scalar_field, a)
end


function multiply!(destination::VectorFieldSpectral{T}, scalar_field::ScalarFieldSpectral{T}, a::FiberVector{T}) where {T<:AbstractFloat}
  return _multiply_scalar_field_by_fiber_vector!(destination, scalar_field, a)
end


function multiply!(destination::VectorFieldSpectral{T}, a::FiberVector{T}, scalar_field::ScalarFieldSpectral{T}) where {T<:AbstractFloat}
  return multiply!(destination, scalar_field, a)
end


function multiply!(destination::TensorFieldPhysical{2, T}, scalar_field::ScalarFieldPhysical{T}, A::FiberTensor2{T}) where {T<:AbstractFloat}
  return _multiply_scalar_field_by_fiber_tensor2!(destination, scalar_field, A)
end


function multiply!(destination::TensorFieldPhysical{2, T}, A::FiberTensor2{T}, scalar_field::ScalarFieldPhysical{T}) where {T<:AbstractFloat}
  return multiply!(destination, scalar_field, A)
end


function multiply!(destination::TensorFieldSpectral{2, T}, scalar_field::ScalarFieldSpectral{T}, A::FiberTensor2{T}) where {T<:AbstractFloat}
  return _multiply_scalar_field_by_fiber_tensor2!(destination, scalar_field, A)
end


function multiply!(destination::TensorFieldSpectral{2, T}, A::FiberTensor2{T}, scalar_field::ScalarFieldSpectral{T}) where {T<:AbstractFloat}
  return multiply!(destination, scalar_field, A)
end


"""
    divide!(
      destination::AbstractFieldPhysical,
      field::AbstractFieldPhysical,
      scalar_field::ScalarFieldPhysical,
    )

    divide!(
      destination::ScalarFieldPhysical,
      scalar::Real,
      scalar_field::ScalarFieldPhysical,
    )

    divide!(
      destination::VectorFieldPhysical,
      a::FiberVector,
      scalar_field::ScalarFieldPhysical,
    )

    divide!(
      destination::TensorFieldPhysical{2},
      A::FiberTensor2,
      scalar_field::ScalarFieldPhysical,
    )

Divide a field, a real number, or a constant fiber object in-place by a compatible scalar field in physical-space representation.

Division by a scalar field in physical-space representation is pointwise. When the numerator is a field, the division acts on all tensor components of that field. When the numerator is a real number, the result is a scalar field in physical-space representation. When the numerator is a constant fiber vector or second-order fiber tensor, the result is the corresponding vector or tensor field in physical-space representation.

Returns the modified `destination` field.
"""
divide!


function _divide_fiber_vector_by_scalar_field!(destination::VectorFieldPhysical, a::FiberVector, scalar_field::ScalarFieldPhysical)
  _check_scalar_field_compatibility(scalar_field, destination)

  scalar_data = field_data(scalar_field)

  _vector_component_data(destination, 1) .= a[1] ./ scalar_data
  _vector_component_data(destination, 2) .= a[2] ./ scalar_data
  _vector_component_data(destination, 3) .= a[3] ./ scalar_data

  return destination
end


function _divide_fiber_tensor2_by_scalar_field!(destination::TensorFieldPhysical{2}, A::FiberTensor2, scalar_field::ScalarFieldPhysical)
  _check_scalar_field_compatibility(scalar_field, destination)

  scalar_data = field_data(scalar_field)

  _tensor2_component_data(destination, 1, 1) .= A[1, 1] ./ scalar_data
  _tensor2_component_data(destination, 1, 2) .= A[1, 2] ./ scalar_data
  _tensor2_component_data(destination, 1, 3) .= A[1, 3] ./ scalar_data
  _tensor2_component_data(destination, 2, 1) .= A[2, 1] ./ scalar_data
  _tensor2_component_data(destination, 2, 2) .= A[2, 2] ./ scalar_data
  _tensor2_component_data(destination, 2, 3) .= A[2, 3] ./ scalar_data
  _tensor2_component_data(destination, 3, 1) .= A[3, 1] ./ scalar_data
  _tensor2_component_data(destination, 3, 2) .= A[3, 2] ./ scalar_data
  _tensor2_component_data(destination, 3, 3) .= A[3, 3] ./ scalar_data

  return destination
end


function divide!(destination::VectorFieldPhysical{T}, a::FiberVector{T}, scalar_field::ScalarFieldPhysical{T}) where {T<:AbstractFloat}
  return _divide_fiber_vector_by_scalar_field!(destination, a, scalar_field)
end


function divide!(destination::TensorFieldPhysical{2, T}, A::FiberTensor2{T}, scalar_field::ScalarFieldPhysical{T}) where {T<:AbstractFloat}
  return _divide_fiber_tensor2_by_scalar_field!(destination, A, scalar_field)
end


function divide!(destination::AbstractFieldPhysical, field::AbstractFieldPhysical, scalar_field::ScalarFieldPhysical)
  check_field_compatibility(destination, field)
  _check_scalar_field_compatibility(scalar_field, field)

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


function *(scalar_field::ScalarFieldPhysical{T}, a::FiberVector{T}) where {T<:AbstractFloat}
  destination = similar_field(scalar_field, Val(1))
  return multiply!(destination, scalar_field, a)
end


function *(a::FiberVector{T}, scalar_field::ScalarFieldPhysical{T}) where {T<:AbstractFloat}
  destination = similar_field(scalar_field, Val(1))
  return multiply!(destination, a, scalar_field)
end


function *(scalar_field::ScalarFieldSpectral{T}, a::FiberVector{T}) where {T<:AbstractFloat}
  destination = similar_field(scalar_field, Val(1))
  return multiply!(destination, scalar_field, a)
end


function *(a::FiberVector{T}, scalar_field::ScalarFieldSpectral{T}) where {T<:AbstractFloat}
  destination = similar_field(scalar_field, Val(1))
  return multiply!(destination, a, scalar_field)
end


function *(scalar_field::ScalarFieldPhysical{T}, A::FiberTensor2{T}) where {T<:AbstractFloat}
  destination = similar_field(scalar_field, Val(2))
  return multiply!(destination, scalar_field, A)
end


function *(A::FiberTensor2{T}, scalar_field::ScalarFieldPhysical{T}) where {T<:AbstractFloat}
  destination = similar_field(scalar_field, Val(2))
  return multiply!(destination, A, scalar_field)
end


function *(scalar_field::ScalarFieldSpectral{T}, A::FiberTensor2{T}) where {T<:AbstractFloat}
  destination = similar_field(scalar_field, Val(2))
  return multiply!(destination, scalar_field, A)
end


function *(A::FiberTensor2{T}, scalar_field::ScalarFieldSpectral{T}) where {T<:AbstractFloat}
  destination = similar_field(scalar_field, Val(2))
  return multiply!(destination, A, scalar_field)
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
#        Vector Dot Products                        #
#####################################################


"""
    dot!(
      destination::ScalarFieldPhysical,
      u::VectorFieldPhysical,
      v::VectorFieldPhysical,
    )

    dot!(
      destination::ScalarFieldPhysical,
      u::VectorFieldPhysical,
      a::FiberVector,
    )

    dot!(
      destination::ScalarFieldPhysical,
      a::FiberVector,
      u::VectorFieldPhysical,
    )

    dot!(
      destination::ScalarFieldSpectral,
      u::VectorFieldSpectral,
      a::FiberVector,
    )

    dot!(
      destination::ScalarFieldSpectral,
      a::FiberVector,
      u::VectorFieldSpectral,
    )

Compute a fiberwise Euclidean scalar product in-place.

For two vector fields in physical-space representation this computes the pointwise scalar field `u₁ * v₁ + u₂ * v₂ + u₃ * v₃`.

For a vector field and a constant fiber vector this computes the corresponding linear combination of components.
The methods for spectral representation are defined only for contraction with a constant fiber vector.

Returns the modified `destination` field.
"""
function dot! end


function _dot_components!(destination, u, v)
  field_data(destination) .=
    _vector_component_data(u, 1) .* _vector_component_data(v, 1) .+
    _vector_component_data(u, 2) .* _vector_component_data(v, 2) .+
    _vector_component_data(u, 3) .* _vector_component_data(v, 3)

  return destination
end


function _dot_components!(destination, u::Union{VectorFieldPhysical, VectorFieldSpectral}, a::FiberVector)
  field_data(destination) .=
    _vector_component_data(u, 1) .* a[1] .+
    _vector_component_data(u, 2) .* a[2] .+
    _vector_component_data(u, 3) .* a[3]

  return destination
end


function dot!(destination::ScalarFieldPhysical{T}, u::VectorFieldPhysical{T}, v::VectorFieldPhysical{T}) where {T<:AbstractFloat}
  check_field_compatibility(u, v)
  _check_scalar_field_compatibility(destination, u)
  return _dot_components!(destination, u, v)
end


function dot!(destination::ScalarFieldPhysical{T}, u::VectorFieldPhysical{T}, a::FiberVector{T}) where {T<:AbstractFloat}
  _check_scalar_field_compatibility(destination, u)
  return _dot_components!(destination, u, a)
end


function dot!(destination::ScalarFieldPhysical{T}, a::FiberVector{T}, u::VectorFieldPhysical{T}) where {T<:AbstractFloat}
  return dot!(destination, u, a)
end


function dot!(destination::ScalarFieldSpectral{T}, u::VectorFieldSpectral{T}, a::FiberVector{T}) where {T<:AbstractFloat}
  _check_scalar_field_compatibility(destination, u)
  return _dot_components!(destination, u, a)
end


function dot!(destination::ScalarFieldSpectral{T}, a::FiberVector{T}, u::VectorFieldSpectral{T}) where {T<:AbstractFloat}
  return dot!(destination, u, a)
end


function dot(u::VectorFieldPhysical{T}, v::VectorFieldPhysical{T}) where {T<:AbstractFloat}
  destination = similar_field(u, Val(0))
  return dot!(destination, u, v)
end


function dot(u::VectorFieldPhysical{T}, a::FiberVector{T}) where {T<:AbstractFloat}
  destination = similar_field(u, Val(0))
  return dot!(destination, u, a)
end


function dot(a::FiberVector{T}, u::VectorFieldPhysical{T}) where {T<:AbstractFloat}
  return dot(u, a)
end


function dot(u::VectorFieldSpectral{T}, a::FiberVector{T}) where {T<:AbstractFloat}
  destination = similar_field(u, Val(0))
  return dot!(destination, u, a)
end


function dot(a::FiberVector{T}, u::VectorFieldSpectral{T}) where {T<:AbstractFloat}
  return dot(u, a)
end




#####################################################
#        Vector Cross Products                      #
#####################################################


"""
    cross!(
      destination::VectorFieldPhysical,
      u::VectorFieldPhysical,
      v::VectorFieldPhysical,
    )

    cross!(
      destination::VectorFieldPhysical,
      u::VectorFieldPhysical,
      a::FiberVector,
    )

    cross!(
      destination::VectorFieldPhysical,
      a::FiberVector,
      u::VectorFieldPhysical,
    )

    cross!(
      destination::VectorFieldSpectral,
      u::VectorFieldSpectral,
      a::FiberVector,
    )

    cross!(
      destination::VectorFieldSpectral,
      a::FiberVector,
      u::VectorFieldSpectral,
    )

Compute a fiberwise cross product in-place.

For two vector fields this is defined only in physical-space representation and computes
`u × v` pointwise.

For a vector field and a constant fiber vector this computes the corresponding fiberwise cross product.
The methods for spectral representation are defined only for cross products with a constant fiber vector.

Returns the modified `destination` field.
"""
function cross! end


function _cross_components_noalias!(destination, u, v)
  destination_1 = _vector_component_data(destination, 1)
  destination_2 = _vector_component_data(destination, 2)
  destination_3 = _vector_component_data(destination, 3)

  u_1 = _vector_component_data(u, 1)
  u_2 = _vector_component_data(u, 2)
  u_3 = _vector_component_data(u, 3)

  v_1 = _vector_component_data(v, 1)
  v_2 = _vector_component_data(v, 2)
  v_3 = _vector_component_data(v, 3)

  destination_1 .= u_2 .* v_3 .- u_3 .* v_2
  destination_2 .= u_3 .* v_1 .- u_1 .* v_3
  destination_3 .= u_1 .* v_2 .- u_2 .* v_1

  return destination
end


function _cross_components!(destination, u, v)
  if _field_data_aliases(destination, u, v)
    temporary = similar_field(destination, Val(1))
    _cross_components_noalias!(temporary, u, v)
    copyto!(field_data(destination), field_data(temporary))

    return destination
  end

  return _cross_components_noalias!(destination, u, v)
end


function _cross_components_noalias!(
  destination,
  u::Union{VectorFieldPhysical, VectorFieldSpectral},
  a::FiberVector,
)
  destination_1 = _vector_component_data(destination, 1)
  destination_2 = _vector_component_data(destination, 2)
  destination_3 = _vector_component_data(destination, 3)

  u_1 = _vector_component_data(u, 1)
  u_2 = _vector_component_data(u, 2)
  u_3 = _vector_component_data(u, 3)

  destination_1 .= u_2 .* a[3] .- u_3 .* a[2]
  destination_2 .= u_3 .* a[1] .- u_1 .* a[3]
  destination_3 .= u_1 .* a[2] .- u_2 .* a[1]

  return destination
end


function _cross_components!(
  destination,
  u::Union{VectorFieldPhysical, VectorFieldSpectral},
  a::FiberVector,
)
  if _field_data_aliases(destination, u)
    temporary = similar_field(destination, Val(1))
    _cross_components_noalias!(temporary, u, a)
    copyto!(field_data(destination), field_data(temporary))

    return destination
  end

  return _cross_components_noalias!(destination, u, a)
end


function _cross_components_noalias!(destination, a::FiberVector, u::Union{VectorFieldPhysical, VectorFieldSpectral})
  destination_1 = _vector_component_data(destination, 1)
  destination_2 = _vector_component_data(destination, 2)
  destination_3 = _vector_component_data(destination, 3)

  u_1 = _vector_component_data(u, 1)
  u_2 = _vector_component_data(u, 2)
  u_3 = _vector_component_data(u, 3)

  destination_1 .= a[2] .* u_3 .- a[3] .* u_2
  destination_2 .= a[3] .* u_1 .- a[1] .* u_3
  destination_3 .= a[1] .* u_2 .- a[2] .* u_1

  return destination
end


function _cross_components!(destination, a::FiberVector, u::Union{VectorFieldPhysical, VectorFieldSpectral})
  if _field_data_aliases(destination, u)
    temporary = similar_field(destination, Val(1))
    _cross_components_noalias!(temporary, a, u)
    copyto!(field_data(destination), field_data(temporary))

    return destination
  end

  return _cross_components_noalias!(destination, a, u)
end


function cross!(destination::VectorFieldPhysical{T}, u::VectorFieldPhysical{T}, v::VectorFieldPhysical{T}) where {T<:AbstractFloat}
  check_field_compatibility(u, v)
  check_field_compatibility(destination, u)
  return _cross_components!(destination, u, v)
end


function cross!(destination::VectorFieldPhysical{T}, u::VectorFieldPhysical{T}, a::FiberVector{T}) where {T<:AbstractFloat}
  check_field_compatibility(destination, u)
  return _cross_components!(destination, u, a)
end


function cross!(destination::VectorFieldPhysical{T}, a::FiberVector{T}, u::VectorFieldPhysical{T}) where {T<:AbstractFloat}
  check_field_compatibility(destination, u)
  return _cross_components!(destination, a, u)
end


function cross!(destination::VectorFieldSpectral{T}, u::VectorFieldSpectral{T}, a::FiberVector{T}) where {T<:AbstractFloat}
  check_field_compatibility(destination, u)
  return _cross_components!(destination, u, a)
end


function cross!(destination::VectorFieldSpectral{T}, a::FiberVector{T}, u::VectorFieldSpectral{T}) where {T<:AbstractFloat}
  check_field_compatibility(destination, u)
  return _cross_components!(destination, a, u)
end


function cross(u::VectorFieldPhysical{T}, v::VectorFieldPhysical{T}) where {T<:AbstractFloat}
  destination = similar_field(u, Val(1))
  return cross!(destination, u, v)
end


function cross(u::VectorFieldPhysical{T}, a::FiberVector{T}) where {T<:AbstractFloat}
  destination = similar_field(u, Val(1))
  return cross!(destination, u, a)
end


function cross(a::FiberVector{T}, u::VectorFieldPhysical{T}) where {T<:AbstractFloat}
  destination = similar_field(u, Val(1))
  return cross!(destination, a, u)
end


function cross(u::VectorFieldSpectral{T}, a::FiberVector{T}) where {T<:AbstractFloat}
  destination = similar_field(u, Val(1))
  return cross!(destination, u, a)
end


function cross(a::FiberVector{T}, u::VectorFieldSpectral{T}) where {T<:AbstractFloat}
  destination = similar_field(u, Val(1))
  return cross!(destination, a, u)
end




#####################################################
#        Tensor-Vector Products                     #
#####################################################


"""
    mul!(
      destination::VectorFieldPhysical,
      A::TensorFieldPhysical{2},
      u::VectorFieldPhysical,
    )

    mul!(
      destination::VectorFieldPhysical,
      u::VectorFieldPhysical,
      A::TensorFieldPhysical{2},
    )

    mul!(
      destination::VectorFieldPhysical,
      A::TensorFieldPhysical{2},
      a::FiberVector,
    )

    mul!(
      destination::VectorFieldPhysical,
      a::FiberVector,
      A::TensorFieldPhysical{2},
    )

    mul!(
      destination::VectorFieldPhysical,
      A::FiberTensor2,
      u::VectorFieldPhysical,
    )

    mul!(
      destination::VectorFieldPhysical,
      u::VectorFieldPhysical,
      A::FiberTensor2,
    )

    mul!(
      destination::VectorFieldSpectral,
      A::TensorFieldSpectral{2},
      a::FiberVector,
    )

    mul!(
      destination::VectorFieldSpectral,
      a::FiberVector,
      A::TensorFieldSpectral{2},
    )

    mul!(
      destination::VectorFieldSpectral,
      A::FiberTensor2,
      u::VectorFieldSpectral,
    )

    mul!(
      destination::VectorFieldSpectral,
      u::VectorFieldSpectral,
      A::FiberTensor2,
    )

Compute the fiberwise action of a second-order tensor on a vector in-place.

The left action computes `Aᵢⱼ * uⱼ`. The right action computes `uᵢ * Aᵢⱼ`.

For fields in physical-space representation this is pointwise. Spectral-space methods are defined only
when one factor is a constant fiber tensor or fiber vector, so the operation remains coefficient-wise.

The five-argument form computes `destination = α * product + β * destination`.

As for `LinearAlgebra.mul!`, `destination` must not share storage with either input.

Returns the modified `destination` field.
"""
mul!


function _check_tensor2_vector_field_compatibility(tensor_field, vector_field)
  field_scalar_type(tensor_field) == field_scalar_type(vector_field) || throw(ArgumentError("field scalar types must be equal"))
  field_grid(tensor_field) == field_grid(vector_field) || throw(ArgumentError("field grids must be equal"))
  field_layout(tensor_field) == field_layout(vector_field) || throw(ArgumentError("field Fourier layouts must be equal"))
  return nothing
end


function _tensor_vector_components_noalias!(destination, A::TensorFieldPhysical{2}, u::VectorFieldPhysical, α_value, β_value)
  destination_1 = _vector_component_data(destination, 1)
  destination_2 = _vector_component_data(destination, 2)
  destination_3 = _vector_component_data(destination, 3)

  A_11 = _tensor2_component_data(A, 1, 1)
  A_12 = _tensor2_component_data(A, 1, 2)
  A_13 = _tensor2_component_data(A, 1, 3)
  A_21 = _tensor2_component_data(A, 2, 1)
  A_22 = _tensor2_component_data(A, 2, 2)
  A_23 = _tensor2_component_data(A, 2, 3)
  A_31 = _tensor2_component_data(A, 3, 1)
  A_32 = _tensor2_component_data(A, 3, 2)
  A_33 = _tensor2_component_data(A, 3, 3)

  u_1 = _vector_component_data(u, 1)
  u_2 = _vector_component_data(u, 2)
  u_3 = _vector_component_data(u, 3)

  if iszero(β_value)
    destination_1 .= α_value .* (A_11 .* u_1 .+ A_12 .* u_2 .+ A_13 .* u_3)
    destination_2 .= α_value .* (A_21 .* u_1 .+ A_22 .* u_2 .+ A_23 .* u_3)
    destination_3 .= α_value .* (A_31 .* u_1 .+ A_32 .* u_2 .+ A_33 .* u_3)
  else
    destination_1 .= α_value .* (A_11 .* u_1 .+ A_12 .* u_2 .+ A_13 .* u_3) .+ β_value .* destination_1
    destination_2 .= α_value .* (A_21 .* u_1 .+ A_22 .* u_2 .+ A_23 .* u_3) .+ β_value .* destination_2
    destination_3 .= α_value .* (A_31 .* u_1 .+ A_32 .* u_2 .+ A_33 .* u_3) .+ β_value .* destination_3
  end

  return destination
end


function _vector_tensor_components_noalias!(destination, u::VectorFieldPhysical, A::TensorFieldPhysical{2}, α_value, β_value)
  destination_1 = _vector_component_data(destination, 1)
  destination_2 = _vector_component_data(destination, 2)
  destination_3 = _vector_component_data(destination, 3)

  u_1 = _vector_component_data(u, 1)
  u_2 = _vector_component_data(u, 2)
  u_3 = _vector_component_data(u, 3)

  A_11 = _tensor2_component_data(A, 1, 1)
  A_12 = _tensor2_component_data(A, 1, 2)
  A_13 = _tensor2_component_data(A, 1, 3)
  A_21 = _tensor2_component_data(A, 2, 1)
  A_22 = _tensor2_component_data(A, 2, 2)
  A_23 = _tensor2_component_data(A, 2, 3)
  A_31 = _tensor2_component_data(A, 3, 1)
  A_32 = _tensor2_component_data(A, 3, 2)
  A_33 = _tensor2_component_data(A, 3, 3)

  if iszero(β_value)
    destination_1 .= α_value .* (u_1 .* A_11 .+ u_2 .* A_21 .+ u_3 .* A_31)
    destination_2 .= α_value .* (u_1 .* A_12 .+ u_2 .* A_22 .+ u_3 .* A_32)
    destination_3 .= α_value .* (u_1 .* A_13 .+ u_2 .* A_23 .+ u_3 .* A_33)
  else
    destination_1 .= α_value .* (u_1 .* A_11 .+ u_2 .* A_21 .+ u_3 .* A_31) .+ β_value .* destination_1
    destination_2 .= α_value .* (u_1 .* A_12 .+ u_2 .* A_22 .+ u_3 .* A_32) .+ β_value .* destination_2
    destination_3 .= α_value .* (u_1 .* A_13 .+ u_2 .* A_23 .+ u_3 .* A_33) .+ β_value .* destination_3
  end

  return destination
end


function _tensor_vector_components_noalias!(destination, A::Union{TensorFieldPhysical{2}, TensorFieldSpectral{2}}, a::FiberVector, α_value, β_value)
  destination_1 = _vector_component_data(destination, 1)
  destination_2 = _vector_component_data(destination, 2)
  destination_3 = _vector_component_data(destination, 3)

  A_11 = _tensor2_component_data(A, 1, 1)
  A_12 = _tensor2_component_data(A, 1, 2)
  A_13 = _tensor2_component_data(A, 1, 3)
  A_21 = _tensor2_component_data(A, 2, 1)
  A_22 = _tensor2_component_data(A, 2, 2)
  A_23 = _tensor2_component_data(A, 2, 3)
  A_31 = _tensor2_component_data(A, 3, 1)
  A_32 = _tensor2_component_data(A, 3, 2)
  A_33 = _tensor2_component_data(A, 3, 3)

  if iszero(β_value)
    destination_1 .= α_value .* (A_11 .* a[1] .+ A_12 .* a[2] .+ A_13 .* a[3])
    destination_2 .= α_value .* (A_21 .* a[1] .+ A_22 .* a[2] .+ A_23 .* a[3])
    destination_3 .= α_value .* (A_31 .* a[1] .+ A_32 .* a[2] .+ A_33 .* a[3])
  else
    destination_1 .= α_value .* (A_11 .* a[1] .+ A_12 .* a[2] .+ A_13 .* a[3]) .+ β_value .* destination_1
    destination_2 .= α_value .* (A_21 .* a[1] .+ A_22 .* a[2] .+ A_23 .* a[3]) .+ β_value .* destination_2
    destination_3 .= α_value .* (A_31 .* a[1] .+ A_32 .* a[2] .+ A_33 .* a[3]) .+ β_value .* destination_3
  end

  return destination
end


function _vector_tensor_components_noalias!(destination, a::FiberVector, A::Union{TensorFieldPhysical{2}, TensorFieldSpectral{2}}, α_value, β_value)
  destination_1 = _vector_component_data(destination, 1)
  destination_2 = _vector_component_data(destination, 2)
  destination_3 = _vector_component_data(destination, 3)

  A_11 = _tensor2_component_data(A, 1, 1)
  A_12 = _tensor2_component_data(A, 1, 2)
  A_13 = _tensor2_component_data(A, 1, 3)
  A_21 = _tensor2_component_data(A, 2, 1)
  A_22 = _tensor2_component_data(A, 2, 2)
  A_23 = _tensor2_component_data(A, 2, 3)
  A_31 = _tensor2_component_data(A, 3, 1)
  A_32 = _tensor2_component_data(A, 3, 2)
  A_33 = _tensor2_component_data(A, 3, 3)

  if iszero(β_value)
    destination_1 .= α_value .* (a[1] .* A_11 .+ a[2] .* A_21 .+ a[3] .* A_31)
    destination_2 .= α_value .* (a[1] .* A_12 .+ a[2] .* A_22 .+ a[3] .* A_32)
    destination_3 .= α_value .* (a[1] .* A_13 .+ a[2] .* A_23 .+ a[3] .* A_33)
  else
    destination_1 .= α_value .* (a[1] .* A_11 .+ a[2] .* A_21 .+ a[3] .* A_31) .+ β_value .* destination_1
    destination_2 .= α_value .* (a[1] .* A_12 .+ a[2] .* A_22 .+ a[3] .* A_32) .+ β_value .* destination_2
    destination_3 .= α_value .* (a[1] .* A_13 .+ a[2] .* A_23 .+ a[3] .* A_33) .+ β_value .* destination_3
  end

  return destination
end


function _tensor_vector_components_noalias!(destination, A::FiberTensor2, u::Union{VectorFieldPhysical, VectorFieldSpectral}, α_value, β_value)
  destination_1 = _vector_component_data(destination, 1)
  destination_2 = _vector_component_data(destination, 2)
  destination_3 = _vector_component_data(destination, 3)

  u_1 = _vector_component_data(u, 1)
  u_2 = _vector_component_data(u, 2)
  u_3 = _vector_component_data(u, 3)

  if iszero(β_value)
    destination_1 .= α_value .* (A[1, 1] .* u_1 .+ A[1, 2] .* u_2 .+ A[1, 3] .* u_3)
    destination_2 .= α_value .* (A[2, 1] .* u_1 .+ A[2, 2] .* u_2 .+ A[2, 3] .* u_3)
    destination_3 .= α_value .* (A[3, 1] .* u_1 .+ A[3, 2] .* u_2 .+ A[3, 3] .* u_3)
  else
    destination_1 .= α_value .* (A[1, 1] .* u_1 .+ A[1, 2] .* u_2 .+ A[1, 3] .* u_3) .+ β_value .* destination_1
    destination_2 .= α_value .* (A[2, 1] .* u_1 .+ A[2, 2] .* u_2 .+ A[2, 3] .* u_3) .+ β_value .* destination_2
    destination_3 .= α_value .* (A[3, 1] .* u_1 .+ A[3, 2] .* u_2 .+ A[3, 3] .* u_3) .+ β_value .* destination_3
  end

  return destination
end


function _vector_tensor_components_noalias!(destination, u::Union{VectorFieldPhysical, VectorFieldSpectral}, A::FiberTensor2, α_value, β_value)
  destination_1 = _vector_component_data(destination, 1)
  destination_2 = _vector_component_data(destination, 2)
  destination_3 = _vector_component_data(destination, 3)

  u_1 = _vector_component_data(u, 1)
  u_2 = _vector_component_data(u, 2)
  u_3 = _vector_component_data(u, 3)

  if iszero(β_value)
    destination_1 .= α_value .* (u_1 .* A[1, 1] .+ u_2 .* A[2, 1] .+ u_3 .* A[3, 1])
    destination_2 .= α_value .* (u_1 .* A[1, 2] .+ u_2 .* A[2, 2] .+ u_3 .* A[3, 2])
    destination_3 .= α_value .* (u_1 .* A[1, 3] .+ u_2 .* A[2, 3] .+ u_3 .* A[3, 3])
  else
    destination_1 .= α_value .* (u_1 .* A[1, 1] .+ u_2 .* A[2, 1] .+ u_3 .* A[3, 1]) .+ β_value .* destination_1
    destination_2 .= α_value .* (u_1 .* A[1, 2] .+ u_2 .* A[2, 2] .+ u_3 .* A[3, 2]) .+ β_value .* destination_2
    destination_3 .= α_value .* (u_1 .* A[1, 3] .+ u_2 .* A[2, 3] .+ u_3 .* A[3, 3]) .+ β_value .* destination_3
  end

  return destination
end


function mul!(destination::VectorFieldPhysical{T}, A::TensorFieldPhysical{2, T}, u::VectorFieldPhysical{T}, α::Real, β::Real) where {T<:AbstractFloat}
  check_field_compatibility(destination, u)
  _check_tensor2_vector_field_compatibility(A, u)
  return _tensor_vector_components_noalias!(destination, A, u, T(α), T(β))
end


function mul!(destination::VectorFieldPhysical{T}, u::VectorFieldPhysical{T}, A::TensorFieldPhysical{2, T}, α::Real, β::Real) where {T<:AbstractFloat}
  check_field_compatibility(destination, u)
  _check_tensor2_vector_field_compatibility(A, u)
  return _vector_tensor_components_noalias!(destination, u, A, T(α), T(β))
end


function mul!(destination::VectorFieldPhysical{T}, A::TensorFieldPhysical{2, T}, a::FiberVector{T}, α::Real, β::Real) where {T<:AbstractFloat}
  _check_tensor2_vector_field_compatibility(A, destination)
  return _tensor_vector_components_noalias!(destination, A, a, T(α), T(β))
end


function mul!(destination::VectorFieldPhysical{T}, a::FiberVector{T}, A::TensorFieldPhysical{2, T}, α::Real, β::Real) where {T<:AbstractFloat}
  _check_tensor2_vector_field_compatibility(A, destination)
  return _vector_tensor_components_noalias!(destination, a, A, T(α), T(β))
end


function mul!(destination::VectorFieldPhysical{T}, A::FiberTensor2{T}, u::VectorFieldPhysical{T}, α::Real, β::Real) where {T<:AbstractFloat}
  check_field_compatibility(destination, u)
  return _tensor_vector_components_noalias!(destination, A, u, T(α), T(β))
end


function mul!(destination::VectorFieldPhysical{T}, u::VectorFieldPhysical{T}, A::FiberTensor2{T}, α::Real, β::Real) where {T<:AbstractFloat}
  check_field_compatibility(destination, u)
  return _vector_tensor_components_noalias!(destination, u, A, T(α), T(β))
end


function mul!(destination::VectorFieldSpectral{T}, A::TensorFieldSpectral{2, T}, a::FiberVector{T}, α::Real, β::Real) where {T<:AbstractFloat}
  _check_tensor2_vector_field_compatibility(A, destination)
  return _tensor_vector_components_noalias!(destination, A, a, T(α), T(β))
end


function mul!(destination::VectorFieldSpectral{T}, a::FiberVector{T}, A::TensorFieldSpectral{2, T}, α::Real, β::Real) where {T<:AbstractFloat}
  _check_tensor2_vector_field_compatibility(A, destination)
  return _vector_tensor_components_noalias!(destination, a, A, T(α), T(β))
end


function mul!(destination::VectorFieldSpectral{T}, A::FiberTensor2{T}, u::VectorFieldSpectral{T}, α::Real, β::Real) where {T<:AbstractFloat}
  check_field_compatibility(destination, u)
  return _tensor_vector_components_noalias!(destination, A, u, T(α), T(β))
end


function mul!(destination::VectorFieldSpectral{T}, u::VectorFieldSpectral{T}, A::FiberTensor2{T}, α::Real, β::Real) where {T<:AbstractFloat}
  check_field_compatibility(destination, u)
  return _vector_tensor_components_noalias!(destination, u, A, T(α), T(β))
end


function mul!(destination::VectorFieldPhysical{T}, A::TensorFieldPhysical{2, T}, u::VectorFieldPhysical{T}) where {T<:AbstractFloat}
  return mul!(destination, A, u, one(T), zero(T))
end


function mul!(destination::VectorFieldPhysical{T}, u::VectorFieldPhysical{T}, A::TensorFieldPhysical{2, T}) where {T<:AbstractFloat}
  return mul!(destination, u, A, one(T), zero(T))
end


function mul!(destination::VectorFieldPhysical{T}, A::TensorFieldPhysical{2, T}, a::FiberVector{T}) where {T<:AbstractFloat}
  return mul!(destination, A, a, one(T), zero(T))
end


function mul!(destination::VectorFieldPhysical{T}, a::FiberVector{T}, A::TensorFieldPhysical{2, T}) where {T<:AbstractFloat}
  return mul!(destination, a, A, one(T), zero(T))
end


function mul!(destination::VectorFieldPhysical{T}, A::FiberTensor2{T}, u::VectorFieldPhysical{T}) where {T<:AbstractFloat}
  return mul!(destination, A, u, one(T), zero(T))
end


function mul!(destination::VectorFieldPhysical{T}, u::VectorFieldPhysical{T}, A::FiberTensor2{T}) where {T<:AbstractFloat}
  return mul!(destination, u, A, one(T), zero(T))
end


function mul!(destination::VectorFieldSpectral{T}, A::TensorFieldSpectral{2, T}, a::FiberVector{T}) where {T<:AbstractFloat}
  return mul!(destination, A, a, one(T), zero(T))
end


function mul!(destination::VectorFieldSpectral{T}, a::FiberVector{T}, A::TensorFieldSpectral{2, T}) where {T<:AbstractFloat}
  return mul!(destination, a, A, one(T), zero(T))
end


function mul!(destination::VectorFieldSpectral{T}, A::FiberTensor2{T}, u::VectorFieldSpectral{T}) where {T<:AbstractFloat}
  return mul!(destination, A, u, one(T), zero(T))
end


function mul!(destination::VectorFieldSpectral{T}, u::VectorFieldSpectral{T}, A::FiberTensor2{T}) where {T<:AbstractFloat}
  return mul!(destination, u, A, one(T), zero(T))
end


function *(A::TensorFieldPhysical{2, T}, u::VectorFieldPhysical{T}) where {T<:AbstractFloat}
  destination = similar_field(u, similar(field_data(u)))
  return mul!(destination, A, u)
end


function *(u::VectorFieldPhysical{T}, A::TensorFieldPhysical{2, T}) where {T<:AbstractFloat}
  destination = similar_field(u, similar(field_data(u)))
  return mul!(destination, u, A)
end


function *(A::TensorFieldPhysical{2, T}, a::FiberVector{T}) where {T<:AbstractFloat}
  destination = similar_field(A, Val(1))
  return mul!(destination, A, a)
end


function *(a::FiberVector{T}, A::TensorFieldPhysical{2, T}) where {T<:AbstractFloat}
  destination = similar_field(A, Val(1))
  return mul!(destination, a, A)
end


function *(A::FiberTensor2{T}, u::VectorFieldPhysical{T}) where {T<:AbstractFloat}
  destination = similar_field(u, similar(field_data(u)))
  return mul!(destination, A, u)
end


function *(u::VectorFieldPhysical{T}, A::FiberTensor2{T}) where {T<:AbstractFloat}
  destination = similar_field(u, similar(field_data(u)))
  return mul!(destination, u, A)
end


function *(A::TensorFieldSpectral{2, T}, a::FiberVector{T}) where {T<:AbstractFloat}
  destination = similar_field(A, Val(1))
  return mul!(destination, A, a)
end


function *(a::FiberVector{T}, A::TensorFieldSpectral{2, T}) where {T<:AbstractFloat}
  destination = similar_field(A, Val(1))
  return mul!(destination, a, A)
end


function *(A::FiberTensor2{T}, u::VectorFieldSpectral{T}) where {T<:AbstractFloat}
  destination = similar_field(u, similar(field_data(u)))
  return mul!(destination, A, u)
end


function *(u::VectorFieldSpectral{T}, A::FiberTensor2{T}) where {T<:AbstractFloat}
  destination = similar_field(u, similar(field_data(u)))
  return mul!(destination, u, A)
end




#####################################################
#        Tensor Index Permutations                  #
#####################################################


"""
    transpose!(
      destination::TensorFieldPhysical{2},
      A::TensorFieldPhysical{2},
    )

    transpose!(
      destination::TensorFieldSpectral{2},
      A::TensorFieldSpectral{2},
    )

Transpose the fiber indices of a second-order tensor field in-place.

This computes `destinationᵢⱼ = Aⱼᵢ`, leaving the physical-space or spectral-space representation unchanged.
The operation is linear, so it is defined for both representations.

Unlike Julia's matrix `transpose`, this method writes a canonical tensor-field representation, not a lazy transpose wrapper.

Returns the modified `destination` field.
"""
transpose!


function _transpose_tensor2_components_noalias!(destination, A)
  destination_11 = _tensor2_component_data(destination, 1, 1)
  destination_12 = _tensor2_component_data(destination, 1, 2)
  destination_13 = _tensor2_component_data(destination, 1, 3)
  destination_21 = _tensor2_component_data(destination, 2, 1)
  destination_22 = _tensor2_component_data(destination, 2, 2)
  destination_23 = _tensor2_component_data(destination, 2, 3)
  destination_31 = _tensor2_component_data(destination, 3, 1)
  destination_32 = _tensor2_component_data(destination, 3, 2)
  destination_33 = _tensor2_component_data(destination, 3, 3)

  A_11 = _tensor2_component_data(A, 1, 1)
  A_12 = _tensor2_component_data(A, 1, 2)
  A_13 = _tensor2_component_data(A, 1, 3)
  A_21 = _tensor2_component_data(A, 2, 1)
  A_22 = _tensor2_component_data(A, 2, 2)
  A_23 = _tensor2_component_data(A, 2, 3)
  A_31 = _tensor2_component_data(A, 3, 1)
  A_32 = _tensor2_component_data(A, 3, 2)
  A_33 = _tensor2_component_data(A, 3, 3)

  destination_11 .= A_11
  destination_12 .= A_21
  destination_13 .= A_31
  destination_21 .= A_12
  destination_22 .= A_22
  destination_23 .= A_32
  destination_31 .= A_13
  destination_32 .= A_23
  destination_33 .= A_33

  return destination
end


function transpose!(destination::TensorFieldPhysical{2, T}, A::TensorFieldPhysical{2, T}) where {T<:AbstractFloat}
  check_field_compatibility(destination, A)
  return _apply_unary_tensor2_noalias!(_transpose_tensor2_components_noalias!, destination, A)
end


function transpose!(destination::TensorFieldSpectral{2, T}, A::TensorFieldSpectral{2, T}) where {T<:AbstractFloat}
  check_field_compatibility(destination, A)
  return _apply_unary_tensor2_noalias!(_transpose_tensor2_components_noalias!, destination, A)
end


function transpose(A::TensorFieldPhysical{2, T}) where {T<:AbstractFloat}
  destination = similar_field(A, Val(2))
  return transpose!(destination, A)
end


function transpose(A::TensorFieldSpectral{2, T}) where {T<:AbstractFloat}
  destination = similar_field(A, Val(2))
  return transpose!(destination, A)
end




#####################################################
#        Tensor Inner Products                      #
#####################################################


"""
    dot!(
      destination::ScalarFieldPhysical,
      A::TensorFieldPhysical{2},
      B::TensorFieldPhysical{2},
    )

    dot!(
      destination::ScalarFieldPhysical,
      A::TensorFieldPhysical{2},
      B::FiberTensor2,
    )

    dot!(
      destination::ScalarFieldPhysical,
      A::FiberTensor2,
      B::TensorFieldPhysical{2},
    )

    dot!(
      destination::ScalarFieldSpectral,
      A::TensorFieldSpectral{2},
      B::FiberTensor2,
    )

    dot!(
      destination::ScalarFieldSpectral,
      A::FiberTensor2,
      B::TensorFieldSpectral{2},
    )

Compute the fiberwise Frobenius inner product of second-order tensors in-place.

This computes the double contraction `Aᵢⱼ * Bᵢⱼ`.

For two tensor fields this is defined only in physical-space representation. Methods for spectral representation are defined only
when one factor is a constant fiber tensor, so the operation remains coefficient-wise.

Returns the modified `destination` field.
"""
dot!


function _tensor_inner_product_components!(destination, A, B)
  field_data(destination) .=
    _tensor2_component_data(A, 1, 1) .* _tensor2_component_data(B, 1, 1) .+
    _tensor2_component_data(A, 1, 2) .* _tensor2_component_data(B, 1, 2) .+
    _tensor2_component_data(A, 1, 3) .* _tensor2_component_data(B, 1, 3) .+
    _tensor2_component_data(A, 2, 1) .* _tensor2_component_data(B, 2, 1) .+
    _tensor2_component_data(A, 2, 2) .* _tensor2_component_data(B, 2, 2) .+
    _tensor2_component_data(A, 2, 3) .* _tensor2_component_data(B, 2, 3) .+
    _tensor2_component_data(A, 3, 1) .* _tensor2_component_data(B, 3, 1) .+
    _tensor2_component_data(A, 3, 2) .* _tensor2_component_data(B, 3, 2) .+
    _tensor2_component_data(A, 3, 3) .* _tensor2_component_data(B, 3, 3)

  return destination
end


function _tensor_inner_product_components!(destination, A::Union{TensorFieldPhysical{2}, TensorFieldSpectral{2}}, B::FiberTensor2)
  field_data(destination) .=
    _tensor2_component_data(A, 1, 1) .* B[1, 1] .+
    _tensor2_component_data(A, 1, 2) .* B[1, 2] .+
    _tensor2_component_data(A, 1, 3) .* B[1, 3] .+
    _tensor2_component_data(A, 2, 1) .* B[2, 1] .+
    _tensor2_component_data(A, 2, 2) .* B[2, 2] .+
    _tensor2_component_data(A, 2, 3) .* B[2, 3] .+
    _tensor2_component_data(A, 3, 1) .* B[3, 1] .+
    _tensor2_component_data(A, 3, 2) .* B[3, 2] .+
    _tensor2_component_data(A, 3, 3) .* B[3, 3]

  return destination
end


function _tensor_inner_product_components!(destination, A::FiberTensor2, B::Union{TensorFieldPhysical{2}, TensorFieldSpectral{2}})
  field_data(destination) .=
    A[1, 1] .* _tensor2_component_data(B, 1, 1) .+
    A[1, 2] .* _tensor2_component_data(B, 1, 2) .+
    A[1, 3] .* _tensor2_component_data(B, 1, 3) .+
    A[2, 1] .* _tensor2_component_data(B, 2, 1) .+
    A[2, 2] .* _tensor2_component_data(B, 2, 2) .+
    A[2, 3] .* _tensor2_component_data(B, 2, 3) .+
    A[3, 1] .* _tensor2_component_data(B, 3, 1) .+
    A[3, 2] .* _tensor2_component_data(B, 3, 2) .+
    A[3, 3] .* _tensor2_component_data(B, 3, 3)

  return destination
end


function dot!(destination::ScalarFieldPhysical{T}, A::TensorFieldPhysical{2, T}, B::TensorFieldPhysical{2, T}) where {T<:AbstractFloat}
  check_field_compatibility(A, B)
  _check_scalar_field_compatibility(destination, A)
  return _tensor_inner_product_components!(destination, A, B)
end


function dot!(destination::ScalarFieldPhysical{T}, A::TensorFieldPhysical{2, T}, B::FiberTensor2{T}) where {T<:AbstractFloat}
  _check_scalar_field_compatibility(destination, A)
  return _tensor_inner_product_components!(destination, A, B)
end


function dot!(destination::ScalarFieldPhysical{T}, A::FiberTensor2{T}, B::TensorFieldPhysical{2, T}) where {T<:AbstractFloat}
  _check_scalar_field_compatibility(destination, B)
  return _tensor_inner_product_components!(destination, A, B)
end


function dot!(destination::ScalarFieldSpectral{T}, A::TensorFieldSpectral{2, T}, B::FiberTensor2{T}) where {T<:AbstractFloat}
  _check_scalar_field_compatibility(destination, A)
  return _tensor_inner_product_components!(destination, A, B)
end


function dot!(destination::ScalarFieldSpectral{T}, A::FiberTensor2{T}, B::TensorFieldSpectral{2, T}) where {T<:AbstractFloat}
  _check_scalar_field_compatibility(destination, B)
  return _tensor_inner_product_components!(destination, A, B)
end


function dot(A::TensorFieldPhysical{2, T}, B::TensorFieldPhysical{2, T}) where {T<:AbstractFloat}
  destination = similar_field(A, Val(0))
  return dot!(destination, A, B)
end


function dot(A::TensorFieldPhysical{2, T}, B::FiberTensor2{T}) where {T<:AbstractFloat}
  destination = similar_field(A, Val(0))
  return dot!(destination, A, B)
end


function dot(A::FiberTensor2{T}, B::TensorFieldPhysical{2, T}) where {T<:AbstractFloat}
  destination = similar_field(B, Val(0))
  return dot!(destination, A, B)
end


function dot(A::TensorFieldSpectral{2, T}, B::FiberTensor2{T}) where {T<:AbstractFloat}
  destination = similar_field(A, Val(0))
  return dot!(destination, A, B)
end


function dot(A::FiberTensor2{T}, B::TensorFieldSpectral{2, T}) where {T<:AbstractFloat}
  destination = similar_field(B, Val(0))
  return dot!(destination, A, B)
end




#####################################################
#        Tensor-Tensor Products                     #
#####################################################


"""
    mul!(
      destination::TensorFieldPhysical{2},
      A::TensorFieldPhysical{2},
      B::TensorFieldPhysical{2},
    )

    mul!(
      destination::TensorFieldPhysical{2},
      A::TensorFieldPhysical{2},
      B::FiberTensor2,
    )

    mul!(
      destination::TensorFieldPhysical{2},
      A::FiberTensor2,
      B::TensorFieldPhysical{2},
    )

    mul!(
      destination::TensorFieldSpectral{2},
      A::TensorFieldSpectral{2},
      B::FiberTensor2,
    )

    mul!(
      destination::TensorFieldSpectral{2},
      A::FiberTensor2,
      B::TensorFieldSpectral{2},
    )

Compute the fiberwise product of second-order tensors in-place.

This computes `(A * B)ᵢⱼ = Aᵢₖ * Bₖⱼ`.

For two tensor fields this is defined only in physical-space representation. Methods for spectral representation are defined only
when one factor is a constant fiber tensor, so the operation remains coefficient-wise.

The five-argument form computes `destination = α * product + β * destination`.

As for `LinearAlgebra.mul!`, `destination` must not share storage with either input.

Returns the modified `destination` field.
"""
mul!


function _tensor_tensor_components_noalias!(destination, A::TensorFieldPhysical{2}, B::TensorFieldPhysical{2}, α_value, β_value)
  destination_11 = _tensor2_component_data(destination, 1, 1)
  destination_12 = _tensor2_component_data(destination, 1, 2)
  destination_13 = _tensor2_component_data(destination, 1, 3)
  destination_21 = _tensor2_component_data(destination, 2, 1)
  destination_22 = _tensor2_component_data(destination, 2, 2)
  destination_23 = _tensor2_component_data(destination, 2, 3)
  destination_31 = _tensor2_component_data(destination, 3, 1)
  destination_32 = _tensor2_component_data(destination, 3, 2)
  destination_33 = _tensor2_component_data(destination, 3, 3)

  A_11 = _tensor2_component_data(A, 1, 1)
  A_12 = _tensor2_component_data(A, 1, 2)
  A_13 = _tensor2_component_data(A, 1, 3)
  A_21 = _tensor2_component_data(A, 2, 1)
  A_22 = _tensor2_component_data(A, 2, 2)
  A_23 = _tensor2_component_data(A, 2, 3)
  A_31 = _tensor2_component_data(A, 3, 1)
  A_32 = _tensor2_component_data(A, 3, 2)
  A_33 = _tensor2_component_data(A, 3, 3)

  B_11 = _tensor2_component_data(B, 1, 1)
  B_12 = _tensor2_component_data(B, 1, 2)
  B_13 = _tensor2_component_data(B, 1, 3)
  B_21 = _tensor2_component_data(B, 2, 1)
  B_22 = _tensor2_component_data(B, 2, 2)
  B_23 = _tensor2_component_data(B, 2, 3)
  B_31 = _tensor2_component_data(B, 3, 1)
  B_32 = _tensor2_component_data(B, 3, 2)
  B_33 = _tensor2_component_data(B, 3, 3)

  if iszero(β_value)
    destination_11 .= α_value .* (A_11 .* B_11 .+ A_12 .* B_21 .+ A_13 .* B_31)
    destination_12 .= α_value .* (A_11 .* B_12 .+ A_12 .* B_22 .+ A_13 .* B_32)
    destination_13 .= α_value .* (A_11 .* B_13 .+ A_12 .* B_23 .+ A_13 .* B_33)
    destination_21 .= α_value .* (A_21 .* B_11 .+ A_22 .* B_21 .+ A_23 .* B_31)
    destination_22 .= α_value .* (A_21 .* B_12 .+ A_22 .* B_22 .+ A_23 .* B_32)
    destination_23 .= α_value .* (A_21 .* B_13 .+ A_22 .* B_23 .+ A_23 .* B_33)
    destination_31 .= α_value .* (A_31 .* B_11 .+ A_32 .* B_21 .+ A_33 .* B_31)
    destination_32 .= α_value .* (A_31 .* B_12 .+ A_32 .* B_22 .+ A_33 .* B_32)
    destination_33 .= α_value .* (A_31 .* B_13 .+ A_32 .* B_23 .+ A_33 .* B_33)
  else
    destination_11 .= α_value .* (A_11 .* B_11 .+ A_12 .* B_21 .+ A_13 .* B_31) .+ β_value .* destination_11
    destination_12 .= α_value .* (A_11 .* B_12 .+ A_12 .* B_22 .+ A_13 .* B_32) .+ β_value .* destination_12
    destination_13 .= α_value .* (A_11 .* B_13 .+ A_12 .* B_23 .+ A_13 .* B_33) .+ β_value .* destination_13
    destination_21 .= α_value .* (A_21 .* B_11 .+ A_22 .* B_21 .+ A_23 .* B_31) .+ β_value .* destination_21
    destination_22 .= α_value .* (A_21 .* B_12 .+ A_22 .* B_22 .+ A_23 .* B_32) .+ β_value .* destination_22
    destination_23 .= α_value .* (A_21 .* B_13 .+ A_22 .* B_23 .+ A_23 .* B_33) .+ β_value .* destination_23
    destination_31 .= α_value .* (A_31 .* B_11 .+ A_32 .* B_21 .+ A_33 .* B_31) .+ β_value .* destination_31
    destination_32 .= α_value .* (A_31 .* B_12 .+ A_32 .* B_22 .+ A_33 .* B_32) .+ β_value .* destination_32
    destination_33 .= α_value .* (A_31 .* B_13 .+ A_32 .* B_23 .+ A_33 .* B_33) .+ β_value .* destination_33
  end

  return destination
end


function _tensor_tensor_components_noalias!(destination, A::Union{TensorFieldPhysical{2}, TensorFieldSpectral{2}}, B::FiberTensor2, α_value, β_value)
  destination_11 = _tensor2_component_data(destination, 1, 1)
  destination_12 = _tensor2_component_data(destination, 1, 2)
  destination_13 = _tensor2_component_data(destination, 1, 3)
  destination_21 = _tensor2_component_data(destination, 2, 1)
  destination_22 = _tensor2_component_data(destination, 2, 2)
  destination_23 = _tensor2_component_data(destination, 2, 3)
  destination_31 = _tensor2_component_data(destination, 3, 1)
  destination_32 = _tensor2_component_data(destination, 3, 2)
  destination_33 = _tensor2_component_data(destination, 3, 3)

  A_11 = _tensor2_component_data(A, 1, 1)
  A_12 = _tensor2_component_data(A, 1, 2)
  A_13 = _tensor2_component_data(A, 1, 3)
  A_21 = _tensor2_component_data(A, 2, 1)
  A_22 = _tensor2_component_data(A, 2, 2)
  A_23 = _tensor2_component_data(A, 2, 3)
  A_31 = _tensor2_component_data(A, 3, 1)
  A_32 = _tensor2_component_data(A, 3, 2)
  A_33 = _tensor2_component_data(A, 3, 3)

  if iszero(β_value)
    destination_11 .= α_value .* (A_11 .* B[1, 1] .+ A_12 .* B[2, 1] .+ A_13 .* B[3, 1])
    destination_12 .= α_value .* (A_11 .* B[1, 2] .+ A_12 .* B[2, 2] .+ A_13 .* B[3, 2])
    destination_13 .= α_value .* (A_11 .* B[1, 3] .+ A_12 .* B[2, 3] .+ A_13 .* B[3, 3])
    destination_21 .= α_value .* (A_21 .* B[1, 1] .+ A_22 .* B[2, 1] .+ A_23 .* B[3, 1])
    destination_22 .= α_value .* (A_21 .* B[1, 2] .+ A_22 .* B[2, 2] .+ A_23 .* B[3, 2])
    destination_23 .= α_value .* (A_21 .* B[1, 3] .+ A_22 .* B[2, 3] .+ A_23 .* B[3, 3])
    destination_31 .= α_value .* (A_31 .* B[1, 1] .+ A_32 .* B[2, 1] .+ A_33 .* B[3, 1])
    destination_32 .= α_value .* (A_31 .* B[1, 2] .+ A_32 .* B[2, 2] .+ A_33 .* B[3, 2])
    destination_33 .= α_value .* (A_31 .* B[1, 3] .+ A_32 .* B[2, 3] .+ A_33 .* B[3, 3])
  else
    destination_11 .= α_value .* (A_11 .* B[1, 1] .+ A_12 .* B[2, 1] .+ A_13 .* B[3, 1]) .+ β_value .* destination_11
    destination_12 .= α_value .* (A_11 .* B[1, 2] .+ A_12 .* B[2, 2] .+ A_13 .* B[3, 2]) .+ β_value .* destination_12
    destination_13 .= α_value .* (A_11 .* B[1, 3] .+ A_12 .* B[2, 3] .+ A_13 .* B[3, 3]) .+ β_value .* destination_13
    destination_21 .= α_value .* (A_21 .* B[1, 1] .+ A_22 .* B[2, 1] .+ A_23 .* B[3, 1]) .+ β_value .* destination_21
    destination_22 .= α_value .* (A_21 .* B[1, 2] .+ A_22 .* B[2, 2] .+ A_23 .* B[3, 2]) .+ β_value .* destination_22
    destination_23 .= α_value .* (A_21 .* B[1, 3] .+ A_22 .* B[2, 3] .+ A_23 .* B[3, 3]) .+ β_value .* destination_23
    destination_31 .= α_value .* (A_31 .* B[1, 1] .+ A_32 .* B[2, 1] .+ A_33 .* B[3, 1]) .+ β_value .* destination_31
    destination_32 .= α_value .* (A_31 .* B[1, 2] .+ A_32 .* B[2, 2] .+ A_33 .* B[3, 2]) .+ β_value .* destination_32
    destination_33 .= α_value .* (A_31 .* B[1, 3] .+ A_32 .* B[2, 3] .+ A_33 .* B[3, 3]) .+ β_value .* destination_33
  end

  return destination
end


function _tensor_tensor_components_noalias!(destination, A::FiberTensor2, B::Union{TensorFieldPhysical{2}, TensorFieldSpectral{2}}, α_value, β_value)
  destination_11 = _tensor2_component_data(destination, 1, 1)
  destination_12 = _tensor2_component_data(destination, 1, 2)
  destination_13 = _tensor2_component_data(destination, 1, 3)
  destination_21 = _tensor2_component_data(destination, 2, 1)
  destination_22 = _tensor2_component_data(destination, 2, 2)
  destination_23 = _tensor2_component_data(destination, 2, 3)
  destination_31 = _tensor2_component_data(destination, 3, 1)
  destination_32 = _tensor2_component_data(destination, 3, 2)
  destination_33 = _tensor2_component_data(destination, 3, 3)

  B_11 = _tensor2_component_data(B, 1, 1)
  B_12 = _tensor2_component_data(B, 1, 2)
  B_13 = _tensor2_component_data(B, 1, 3)
  B_21 = _tensor2_component_data(B, 2, 1)
  B_22 = _tensor2_component_data(B, 2, 2)
  B_23 = _tensor2_component_data(B, 2, 3)
  B_31 = _tensor2_component_data(B, 3, 1)
  B_32 = _tensor2_component_data(B, 3, 2)
  B_33 = _tensor2_component_data(B, 3, 3)

  if iszero(β_value)
    destination_11 .= α_value .* (A[1, 1] .* B_11 .+ A[1, 2] .* B_21 .+ A[1, 3] .* B_31)
    destination_12 .= α_value .* (A[1, 1] .* B_12 .+ A[1, 2] .* B_22 .+ A[1, 3] .* B_32)
    destination_13 .= α_value .* (A[1, 1] .* B_13 .+ A[1, 2] .* B_23 .+ A[1, 3] .* B_33)
    destination_21 .= α_value .* (A[2, 1] .* B_11 .+ A[2, 2] .* B_21 .+ A[2, 3] .* B_31)
    destination_22 .= α_value .* (A[2, 1] .* B_12 .+ A[2, 2] .* B_22 .+ A[2, 3] .* B_32)
    destination_23 .= α_value .* (A[2, 1] .* B_13 .+ A[2, 2] .* B_23 .+ A[2, 3] .* B_33)
    destination_31 .= α_value .* (A[3, 1] .* B_11 .+ A[3, 2] .* B_21 .+ A[3, 3] .* B_31)
    destination_32 .= α_value .* (A[3, 1] .* B_12 .+ A[3, 2] .* B_22 .+ A[3, 3] .* B_32)
    destination_33 .= α_value .* (A[3, 1] .* B_13 .+ A[3, 2] .* B_23 .+ A[3, 3] .* B_33)
  else
    destination_11 .= α_value .* (A[1, 1] .* B_11 .+ A[1, 2] .* B_21 .+ A[1, 3] .* B_31) .+ β_value .* destination_11
    destination_12 .= α_value .* (A[1, 1] .* B_12 .+ A[1, 2] .* B_22 .+ A[1, 3] .* B_32) .+ β_value .* destination_12
    destination_13 .= α_value .* (A[1, 1] .* B_13 .+ A[1, 2] .* B_23 .+ A[1, 3] .* B_33) .+ β_value .* destination_13
    destination_21 .= α_value .* (A[2, 1] .* B_11 .+ A[2, 2] .* B_21 .+ A[2, 3] .* B_31) .+ β_value .* destination_21
    destination_22 .= α_value .* (A[2, 1] .* B_12 .+ A[2, 2] .* B_22 .+ A[2, 3] .* B_32) .+ β_value .* destination_22
    destination_23 .= α_value .* (A[2, 1] .* B_13 .+ A[2, 2] .* B_23 .+ A[2, 3] .* B_33) .+ β_value .* destination_23
    destination_31 .= α_value .* (A[3, 1] .* B_11 .+ A[3, 2] .* B_21 .+ A[3, 3] .* B_31) .+ β_value .* destination_31
    destination_32 .= α_value .* (A[3, 1] .* B_12 .+ A[3, 2] .* B_22 .+ A[3, 3] .* B_32) .+ β_value .* destination_32
    destination_33 .= α_value .* (A[3, 1] .* B_13 .+ A[3, 2] .* B_23 .+ A[3, 3] .* B_33) .+ β_value .* destination_33
  end

  return destination
end


function mul!(destination::TensorFieldPhysical{2, T}, A::TensorFieldPhysical{2, T}, B::TensorFieldPhysical{2, T}, α::Real, β::Real) where {T<:AbstractFloat}
  check_field_compatibility(destination, A)
  check_field_compatibility(A, B)
  return _tensor_tensor_components_noalias!(destination, A, B, T(α), T(β))
end


function mul!(destination::TensorFieldPhysical{2, T}, A::TensorFieldPhysical{2, T}, B::FiberTensor2{T}, α::Real, β::Real) where {T<:AbstractFloat}
  check_field_compatibility(destination, A)
  return _tensor_tensor_components_noalias!(destination, A, B, T(α), T(β))
end


function mul!(destination::TensorFieldPhysical{2, T}, A::FiberTensor2{T}, B::TensorFieldPhysical{2, T}, α::Real, β::Real) where {T<:AbstractFloat}
  check_field_compatibility(destination, B)
  return _tensor_tensor_components_noalias!(destination, A, B, T(α), T(β))
end


function mul!(destination::TensorFieldSpectral{2, T}, A::TensorFieldSpectral{2, T}, B::FiberTensor2{T}, α::Real, β::Real) where {T<:AbstractFloat}
  check_field_compatibility(destination, A)
  return _tensor_tensor_components_noalias!(destination, A, B, T(α), T(β))
end


function mul!(destination::TensorFieldSpectral{2, T}, A::FiberTensor2{T}, B::TensorFieldSpectral{2, T}, α::Real, β::Real) where {T<:AbstractFloat}
  check_field_compatibility(destination, B)
  return _tensor_tensor_components_noalias!(destination, A, B, T(α), T(β))
end


function mul!(destination::TensorFieldPhysical{2, T}, A::TensorFieldPhysical{2, T}, B::TensorFieldPhysical{2, T}) where {T<:AbstractFloat}
  return mul!(destination, A, B, one(T), zero(T))
end


function mul!(destination::TensorFieldPhysical{2, T}, A::TensorFieldPhysical{2, T}, B::FiberTensor2{T}) where {T<:AbstractFloat}
  return mul!(destination, A, B, one(T), zero(T))
end


function mul!(destination::TensorFieldPhysical{2, T}, A::FiberTensor2{T}, B::TensorFieldPhysical{2, T}) where {T<:AbstractFloat}
  return mul!(destination, A, B, one(T), zero(T))
end


function mul!(destination::TensorFieldSpectral{2, T}, A::TensorFieldSpectral{2, T}, B::FiberTensor2{T}) where {T<:AbstractFloat}
  return mul!(destination, A, B, one(T), zero(T))
end


function mul!(destination::TensorFieldSpectral{2, T}, A::FiberTensor2{T}, B::TensorFieldSpectral{2, T}) where {T<:AbstractFloat}
  return mul!(destination, A, B, one(T), zero(T))
end


function *(A::TensorFieldPhysical{2, T}, B::TensorFieldPhysical{2, T}) where {T<:AbstractFloat}
  destination = similar_field(A, Val(2))
  return mul!(destination, A, B)
end


function *(A::TensorFieldPhysical{2, T}, B::FiberTensor2{T}) where {T<:AbstractFloat}
  destination = similar_field(A, Val(2))
  return mul!(destination, A, B)
end


function *(A::FiberTensor2{T}, B::TensorFieldPhysical{2, T}) where {T<:AbstractFloat}
  destination = similar_field(B, Val(2))
  return mul!(destination, A, B)
end


function *(A::TensorFieldSpectral{2, T}, B::FiberTensor2{T}) where {T<:AbstractFloat}
  destination = similar_field(A, Val(2))
  return mul!(destination, A, B)
end


function *(A::FiberTensor2{T}, B::TensorFieldSpectral{2, T}) where {T<:AbstractFloat}
  destination = similar_field(B, Val(2))
  return mul!(destination, A, B)
end




#####################################################
#        Field Norms                                #
#####################################################


"""
    norm!(
      destination::ScalarFieldPhysical,
      scalar_field::ScalarFieldPhysical,
    )

    norm!(
      destination::ScalarFieldPhysical,
      u::VectorFieldPhysical,
    )

    norm!(
      destination::ScalarFieldPhysical,
      A::TensorFieldPhysical{2},
    )

Compute the fiberwise norm of a field in physical-space representation in-place.

For scalar fields this computes the pointwise absolute value `abs(φ)`.

For vector fields this computes the Euclidean norm `sqrt(uᵢ * uᵢ)`.

For second-order tensor fields this computes the Frobenius norm `sqrt(Aᵢⱼ * Aᵢⱼ)`, not the operator norm.

This is a pointwise physical-space operation and is not defined for spectral representation.

Returns the modified `destination` field.
"""
function norm! end


"""
    norm(scalar_field::ScalarFieldPhysical)

    norm(u::VectorFieldPhysical)

    norm(A::TensorFieldPhysical{2})

Allocate and compute the fiberwise norm of a field in physical-space representation.

For scalar fields this returns the scalar field `abs(φ)`.

For vector fields this returns the scalar field `sqrt(uᵢ * uᵢ)`.

For second-order tensor fields this returns the Frobenius norm field `sqrt(Aᵢⱼ * Aᵢⱼ)`,
not the operator norm. Use `dot(u, u)` or `dot(A, A)` for the corresponding squared norms.
"""
norm


function _norm_components!(destination, scalar_field::ScalarFieldPhysical)
  field_data(destination) .= abs.(field_data(scalar_field))

  return destination
end


function _norm_components!(destination, u::VectorFieldPhysical)
  field_data(destination) .= sqrt.(
    abs2.(_vector_component_data(u, 1)) .+
    abs2.(_vector_component_data(u, 2)) .+
    abs2.(_vector_component_data(u, 3))
  )

  return destination
end


function _norm_components!(destination, A::TensorFieldPhysical{2})
  field_data(destination) .= sqrt.(
    abs2.(_tensor2_component_data(A, 1, 1)) .+
    abs2.(_tensor2_component_data(A, 1, 2)) .+
    abs2.(_tensor2_component_data(A, 1, 3)) .+
    abs2.(_tensor2_component_data(A, 2, 1)) .+
    abs2.(_tensor2_component_data(A, 2, 2)) .+
    abs2.(_tensor2_component_data(A, 2, 3)) .+
    abs2.(_tensor2_component_data(A, 3, 1)) .+
    abs2.(_tensor2_component_data(A, 3, 2)) .+
    abs2.(_tensor2_component_data(A, 3, 3))
  )

  return destination
end


function norm!(destination::ScalarFieldPhysical{T}, scalar_field::ScalarFieldPhysical{T}) where {T<:AbstractFloat}
  _check_scalar_field_compatibility(destination, scalar_field)
  return _norm_components!(destination, scalar_field)
end


function norm!(destination::ScalarFieldPhysical{T}, u::VectorFieldPhysical{T}) where {T<:AbstractFloat}
  _check_scalar_field_compatibility(destination, u)
  return _norm_components!(destination, u)
end


function norm!(destination::ScalarFieldPhysical{T}, A::TensorFieldPhysical{2, T}) where {T<:AbstractFloat}
  _check_scalar_field_compatibility(destination, A)
  return _norm_components!(destination, A)
end


function norm(scalar_field::ScalarFieldPhysical{T}) where {T<:AbstractFloat}
  destination = similar_field(scalar_field, similar(field_data(scalar_field)))
  return norm!(destination, scalar_field)
end


function norm(u::VectorFieldPhysical{T}) where {T<:AbstractFloat}
  destination = similar_field(u, Val(0))
  return norm!(destination, u)
end


function norm(A::TensorFieldPhysical{2, T}) where {T<:AbstractFloat}
  destination = similar_field(A, Val(0))
  return norm!(destination, A)
end


#####################################################
#        Tensor Decompositions                      #
#####################################################


"""
    sym!(
      destination::TensorFieldPhysical{2},
      A::TensorFieldPhysical{2},
    )

    sym!(
      destination::TensorFieldSpectral{2},
      A::TensorFieldSpectral{2},
    )

Compute the symmetric part of a second-order tensor field in-place.

This computes `sym(A) = (A + transpose(A)) / 2`.

The operation is linear and representation-preserving, so it is defined for tensor fields in physical-space and spectral representations.

Returns the modified `destination` field.
"""
function sym! end


"""
    sym(A::TensorFieldPhysical{2})

    sym(A::TensorFieldSpectral{2})

    sym(A::FiberTensor2)

Allocate and compute the symmetric part of a second-order tensor.

For tensor fields this is a fiberwise operation. For a constant fiber tensor this returns a constant fiber tensor.
"""
function sym end


"""
    skew!(
      destination::TensorFieldPhysical{2},
      A::TensorFieldPhysical{2},
    )

    skew!(
      destination::TensorFieldSpectral{2},
      A::TensorFieldSpectral{2},
    )

Compute the skew-symmetric part of a second-order tensor field in-place.

This computes `skew(A) = (A - transpose(A)) / 2`.

The operation is linear and representation-preserving, so it is defined for tensor fields in physical-space and spectral representations.

Returns the modified `destination` field.
"""
function skew! end


"""
    skew(A::TensorFieldPhysical{2})

    skew(A::TensorFieldSpectral{2})

    skew(A::FiberTensor2)

Allocate and compute the skew-symmetric part of a second-order tensor.

For tensor fields this is a fiberwise operation. For a constant fiber tensor this returns a constant fiber tensor.
"""
function skew end


"""
    dev!(
      destination::TensorFieldPhysical{2},
      A::TensorFieldPhysical{2},
    )

    dev!(
      destination::TensorFieldSpectral{2},
      A::TensorFieldSpectral{2},
    )

Compute the deviatoric part of a second-order tensor field in-place.

This computes `dev(A) = A - tr(A) * I / 3`.

The operation is linear and representation-preserving, so it is defined for tensor fields in physical-space and spectral representations.

Returns the modified `destination` field.
"""
function dev! end


"""
    dev(A::TensorFieldPhysical{2})

    dev(A::TensorFieldSpectral{2})

    dev(A::FiberTensor2)

Allocate and compute the deviatoric part of a second-order tensor.

For tensor fields this is a fiberwise operation. For a constant fiber tensor this returns a constant fiber tensor.
"""
function dev end


function _sym_tensor2_components_noalias!(destination, A)
  half = inv(field_scalar_type(A)(2))

  destination_11 = _tensor2_component_data(destination, 1, 1)
  destination_12 = _tensor2_component_data(destination, 1, 2)
  destination_13 = _tensor2_component_data(destination, 1, 3)
  destination_21 = _tensor2_component_data(destination, 2, 1)
  destination_22 = _tensor2_component_data(destination, 2, 2)
  destination_23 = _tensor2_component_data(destination, 2, 3)
  destination_31 = _tensor2_component_data(destination, 3, 1)
  destination_32 = _tensor2_component_data(destination, 3, 2)
  destination_33 = _tensor2_component_data(destination, 3, 3)

  A_11 = _tensor2_component_data(A, 1, 1)
  A_12 = _tensor2_component_data(A, 1, 2)
  A_13 = _tensor2_component_data(A, 1, 3)
  A_21 = _tensor2_component_data(A, 2, 1)
  A_22 = _tensor2_component_data(A, 2, 2)
  A_23 = _tensor2_component_data(A, 2, 3)
  A_31 = _tensor2_component_data(A, 3, 1)
  A_32 = _tensor2_component_data(A, 3, 2)
  A_33 = _tensor2_component_data(A, 3, 3)

  destination_11 .= A_11
  destination_12 .= half .* (A_12 .+ A_21)
  destination_13 .= half .* (A_13 .+ A_31)
  destination_21 .= half .* (A_21 .+ A_12)
  destination_22 .= A_22
  destination_23 .= half .* (A_23 .+ A_32)
  destination_31 .= half .* (A_31 .+ A_13)
  destination_32 .= half .* (A_32 .+ A_23)
  destination_33 .= A_33

  return destination
end


function _skew_tensor2_components_noalias!(destination, A)
  half = inv(field_scalar_type(A)(2))

  destination_11 = _tensor2_component_data(destination, 1, 1)
  destination_12 = _tensor2_component_data(destination, 1, 2)
  destination_13 = _tensor2_component_data(destination, 1, 3)
  destination_21 = _tensor2_component_data(destination, 2, 1)
  destination_22 = _tensor2_component_data(destination, 2, 2)
  destination_23 = _tensor2_component_data(destination, 2, 3)
  destination_31 = _tensor2_component_data(destination, 3, 1)
  destination_32 = _tensor2_component_data(destination, 3, 2)
  destination_33 = _tensor2_component_data(destination, 3, 3)

  A_12 = _tensor2_component_data(A, 1, 2)
  A_13 = _tensor2_component_data(A, 1, 3)
  A_21 = _tensor2_component_data(A, 2, 1)
  A_23 = _tensor2_component_data(A, 2, 3)
  A_31 = _tensor2_component_data(A, 3, 1)
  A_32 = _tensor2_component_data(A, 3, 2)

  destination_11 .= zero(field_scalar_type(A))
  destination_12 .= half .* (A_12 .- A_21)
  destination_13 .= half .* (A_13 .- A_31)
  destination_21 .= half .* (A_21 .- A_12)
  destination_22 .= zero(field_scalar_type(A))
  destination_23 .= half .* (A_23 .- A_32)
  destination_31 .= half .* (A_31 .- A_13)
  destination_32 .= half .* (A_32 .- A_23)
  destination_33 .= zero(field_scalar_type(A))

  return destination
end


function _dev_tensor2_components_noalias!(destination, A)
  third = inv(field_scalar_type(A)(3))

  destination_11 = _tensor2_component_data(destination, 1, 1)
  destination_12 = _tensor2_component_data(destination, 1, 2)
  destination_13 = _tensor2_component_data(destination, 1, 3)
  destination_21 = _tensor2_component_data(destination, 2, 1)
  destination_22 = _tensor2_component_data(destination, 2, 2)
  destination_23 = _tensor2_component_data(destination, 2, 3)
  destination_31 = _tensor2_component_data(destination, 3, 1)
  destination_32 = _tensor2_component_data(destination, 3, 2)
  destination_33 = _tensor2_component_data(destination, 3, 3)

  A_11 = _tensor2_component_data(A, 1, 1)
  A_12 = _tensor2_component_data(A, 1, 2)
  A_13 = _tensor2_component_data(A, 1, 3)
  A_21 = _tensor2_component_data(A, 2, 1)
  A_22 = _tensor2_component_data(A, 2, 2)
  A_23 = _tensor2_component_data(A, 2, 3)
  A_31 = _tensor2_component_data(A, 3, 1)
  A_32 = _tensor2_component_data(A, 3, 2)
  A_33 = _tensor2_component_data(A, 3, 3)

  destination_11 .= A_11 .- third .* (A_11 .+ A_22 .+ A_33)
  destination_12 .= A_12
  destination_13 .= A_13
  destination_21 .= A_21
  destination_22 .= A_22 .- third .* (A_11 .+ A_22 .+ A_33)
  destination_23 .= A_23
  destination_31 .= A_31
  destination_32 .= A_32
  destination_33 .= A_33 .- third .* (A_11 .+ A_22 .+ A_33)

  return destination
end


function sym!(destination::TensorFieldPhysical{2, T}, A::TensorFieldPhysical{2, T}) where {T<:AbstractFloat}
  check_field_compatibility(destination, A)
  return _apply_unary_tensor2_noalias!(_sym_tensor2_components_noalias!, destination, A)
end


function sym!(destination::TensorFieldSpectral{2, T}, A::TensorFieldSpectral{2, T}) where {T<:AbstractFloat}
  check_field_compatibility(destination, A)
  return _apply_unary_tensor2_noalias!(_sym_tensor2_components_noalias!, destination, A)
end


function skew!(destination::TensorFieldPhysical{2, T}, A::TensorFieldPhysical{2, T}) where {T<:AbstractFloat}
  check_field_compatibility(destination, A)
  return _apply_unary_tensor2_noalias!(_skew_tensor2_components_noalias!, destination, A)
end


function skew!(destination::TensorFieldSpectral{2, T}, A::TensorFieldSpectral{2, T}) where {T<:AbstractFloat}
  check_field_compatibility(destination, A)
  return _apply_unary_tensor2_noalias!(_skew_tensor2_components_noalias!, destination, A)
end


function dev!(destination::TensorFieldPhysical{2, T}, A::TensorFieldPhysical{2, T}) where {T<:AbstractFloat}
  check_field_compatibility(destination, A)
  return _apply_unary_tensor2_noalias!(_dev_tensor2_components_noalias!, destination, A)
end


function dev!(destination::TensorFieldSpectral{2, T}, A::TensorFieldSpectral{2, T}) where {T<:AbstractFloat}
  check_field_compatibility(destination, A)
  return _apply_unary_tensor2_noalias!(_dev_tensor2_components_noalias!, destination, A)
end


function sym(A::TensorFieldPhysical{2, T}) where {T<:AbstractFloat}
  destination = similar_field(A, Val(2))
  return sym!(destination, A)
end


function sym(A::TensorFieldSpectral{2, T}) where {T<:AbstractFloat}
  destination = similar_field(A, Val(2))
  return sym!(destination, A)
end


function skew(A::TensorFieldPhysical{2, T}) where {T<:AbstractFloat}
  destination = similar_field(A, Val(2))
  return skew!(destination, A)
end


function skew(A::TensorFieldSpectral{2, T}) where {T<:AbstractFloat}
  destination = similar_field(A, Val(2))
  return skew!(destination, A)
end


function dev(A::TensorFieldPhysical{2, T}) where {T<:AbstractFloat}
  destination = similar_field(A, Val(2))
  return dev!(destination, A)
end


function dev(A::TensorFieldSpectral{2, T}) where {T<:AbstractFloat}
  destination = similar_field(A, Val(2))
  return dev!(destination, A)
end


function sym(A::FiberTensor2{T}) where {T<:AbstractFloat}
  half = inv(T(2))

  A_12 = half * (A[1, 2] + A[2, 1])
  A_13 = half * (A[1, 3] + A[3, 1])
  A_23 = half * (A[2, 3] + A[3, 2])

  return FiberTensor2{T}(
    A[1, 1], A_12, A_13,
    A_12, A[2, 2], A_23,
    A_13, A_23, A[3, 3],
  )
end


function skew(A::FiberTensor2{T}) where {T<:AbstractFloat}
  half = inv(T(2))

  A_12 = half * (A[1, 2] - A[2, 1])
  A_13 = half * (A[1, 3] - A[3, 1])
  A_23 = half * (A[2, 3] - A[3, 2])

  return FiberTensor2{T}(
    zero(T), -A_12, -A_13,
    A_12, zero(T), -A_23,
    A_13, A_23, zero(T),
  )
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