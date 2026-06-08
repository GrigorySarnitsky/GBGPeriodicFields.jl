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

Mutating methods should write into existing storage and return the modified destination. Prefer fused broadcasted assignments such as `destination_data .= expression` for elementwise operations; on CPU these thread only when routed through `Fields._assign!` / the `@_assign!` macro (a bare `.=` runs single-threaded), so hand-written kernels write `@_assign! destination_data .= expression` and the FieldAlgebra codegen body builders emit `_assign!`. Use explicit small-component formulas for three-component vector and second-order tensor operations when this is clearer and avoids reductions over the fiber dimension.

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
    DifferentialOperators

Differential operators on scalar, vector, and tensor fields on three-dimensional rectangular periodic domains.

The implemented methods act on fields in spectral representation. Spectral coefficients are used as the implementation representation for Fourier differentiation.
"""
module DifferentialOperators


using ..Fields:
  AbstractFieldSpectral,
  ScalarFieldSpectral,
  VectorFieldSpectral,
  TensorFieldSpectral,
  FieldSpectralMultipliers,
  field_data,
  similar_field,
  field_tensor_order,
  check_field_compatibility,
  _check_field_domain_compatibility,
  _vector_component_data,
  _tensor2_component_data,
  _check_multipliers_compatibility,
  _wavenumber_broadcast_view,
  _squared_wavenumber_broadcast,
  _assign!,
  @_assign!


export gradient!,
       gradient,
       divergence!,
       divergence,
       curl!,
       curl,
       laplacian!,
       laplacian,
       inverse_laplacian!,
       inverse_laplacian,
       helmholtz_projection!,
       helmholtz_projection


####################################################
#        Spectral Operator Kernels                 #
####################################################
#
# Coefficientwise spectral kernels for the operators below. The wavenumber
# multipliers (`FieldSpectralMultipliers`) and their compatibility and
# broadcast-view helpers live in Fields and are imported above; the Nyquist
# split between derivative and squared wavenumbers is handled there.


"""
    _apply_spectral_derivative!(destination_component, source_component, wavenumber, ::Type{T})

Apply a coefficientwise first derivative along one axis: `destination_component .= im * wavenumber .* source_component`, where `wavenumber` is a `_wavenumber_broadcast_view`. The building block for `gradient` and `divergence`.
"""
function _apply_spectral_derivative!(destination_component, source_component, wavenumber, ::Type{T}) where {T<:AbstractFloat}
  imaginary_unit = Complex{T}(zero(T), one(T))
  @_assign! destination_component .= imaginary_unit .* wavenumber .* source_component
  return destination_component
end


"""
    _apply_spectral_divergence!(destination_component, source_1, source_2, source_3, wavenumber_1, wavenumber_2, wavenumber_3, ::Type{T})

Apply a coefficientwise contraction with the wavenumber vector: `destination .= im * (k₁ s₁ + k₂ s₂ + k₃ s₃)`. Used by `divergence` for the vector → scalar case and per output component for tensor → vector.
"""
function _apply_spectral_divergence!(destination_component, source_component_1, source_component_2, source_component_3,
  wavenumber_1, wavenumber_2, wavenumber_3, ::Type{T}) where {T<:AbstractFloat}
  
  imaginary_unit = Complex{T}(zero(T), one(T))
  @_assign! destination_component .= imaginary_unit .* (wavenumber_1 .* source_component_1 .+  wavenumber_2 .* source_component_2 .+ wavenumber_3 .* source_component_3)
  return destination_component
end


"""
    _apply_spectral_laplacian!(destination_data, source_data, squared_wavenumber)

Apply the coefficientwise Laplacian: `destination_data .= -squared_wavenumber .* source_data`, where `squared_wavenumber` is `_squared_wavenumber_broadcast`. Representation-preserving over every component.
"""
function _apply_spectral_laplacian!(destination_data, source_data, squared_wavenumber)
  @_assign! destination_data .= -squared_wavenumber .* source_data
  return destination_data
end


"""
    _apply_spectral_inverse_laplacian!(destination_data, source_data, squared_wavenumber, ::Type{T})

Apply the coefficientwise zero-mean inverse Laplacian: `-source_data ./ squared_wavenumber` for nonzero wavevectors, and zero at the zero Fourier mode.
"""
function _apply_spectral_inverse_laplacian!(destination_data, source_data, squared_wavenumber, ::Type{T}) where {T<:AbstractFloat}
  @_assign! destination_data .= ifelse.(squared_wavenumber .== zero(T), zero(Complex{T}), -source_data ./ ifelse.(squared_wavenumber .== zero(T), one(T), squared_wavenumber))
  return destination_data
end


"""
    _apply_spectral_helmholtz_projection!(d_1, d_2, d_3, source_1, source_2, source_3, k_1, k_2, k_3, squared_wavenumber, ::Type{T})

Apply the coefficientwise Leray/Helmholtz projection onto the divergence-free subspace: subtract the longitudinal part `kᵢ (kⱼ ŝⱼ) / |k|²` from each component. The zero Fourier mode is left unchanged.
"""
function _apply_spectral_helmholtz_projection!(destination_component_1, destination_component_2, destination_component_3,
    source_component_1, source_component_2, source_component_3, wavenumber_1, wavenumber_2, wavenumber_3, squared_wavenumber, ::Type{T}) where {T<:AbstractFloat}
  
  safe_squared_wavenumber = ifelse.(squared_wavenumber .== zero(T), one(T), squared_wavenumber)
  longitudinal_component = (wavenumber_1 .* source_component_1 .+ wavenumber_2 .* source_component_2 .+ wavenumber_3 .* source_component_3) ./ safe_squared_wavenumber

  @_assign! destination_component_1 .= source_component_1 .- wavenumber_1 .* longitudinal_component
  @_assign! destination_component_2 .= source_component_2 .- wavenumber_2 .* longitudinal_component
  @_assign! destination_component_3 .= source_component_3 .- wavenumber_3 .* longitudinal_component

  return nothing
end




##########################
#        Gradient        #
##########################


"""
    gradient!(
      destination::VectorFieldSpectral,
      field::ScalarFieldSpectral,
      multipliers::FieldSpectralMultipliers,
    )

    gradient!(
      destination::TensorFieldSpectral{2},
      field::VectorFieldSpectral,
      multipliers::FieldSpectralMultipliers,
    )

Compute the gradient of a field in spectral representation in-place.

For a scalar field `φ`, this computes the vector field with components `(∇φ)ᵢ = ∂ᵢφ`.

For a vector field `u`, this computes the second-order tensor field with convention `(∇u)ᵢⱼ = ∂ⱼuᵢ`.

Fourier differentiation is coefficientwise, using the wavenumber arrays stored in `multipliers`.
"""
function gradient! end


function gradient!(destination::VectorFieldSpectral{T}, field::ScalarFieldSpectral{T}, multipliers::FieldSpectralMultipliers) where {T<:AbstractFloat}
  _check_field_domain_compatibility(destination, field)
  _check_multipliers_compatibility(field, multipliers)

  source = field_data(field)

  _apply_spectral_derivative!(_vector_component_data(destination, 1), source, _wavenumber_broadcast_view(multipliers, Val(1)), T)
  _apply_spectral_derivative!(_vector_component_data(destination, 2), source, _wavenumber_broadcast_view(multipliers, Val(2)), T)
  _apply_spectral_derivative!(_vector_component_data(destination, 3), source, _wavenumber_broadcast_view(multipliers, Val(3)), T)

  return destination
end


function gradient!(destination::TensorFieldSpectral{2, T}, field::VectorFieldSpectral{T}, multipliers::FieldSpectralMultipliers) where {T<:AbstractFloat}
  _check_field_domain_compatibility(destination, field)
  _check_multipliers_compatibility(field, multipliers)

  wavenumber_1 = _wavenumber_broadcast_view(multipliers, Val(1))
  wavenumber_2 = _wavenumber_broadcast_view(multipliers, Val(2))
  wavenumber_3 = _wavenumber_broadcast_view(multipliers, Val(3))

  field_component_1 = _vector_component_data(field, 1)
  field_component_2 = _vector_component_data(field, 2)
  field_component_3 = _vector_component_data(field, 3)

  _apply_spectral_derivative!(_tensor2_component_data(destination, 1, 1), field_component_1, wavenumber_1, T)
  _apply_spectral_derivative!(_tensor2_component_data(destination, 1, 2), field_component_1, wavenumber_2, T)
  _apply_spectral_derivative!(_tensor2_component_data(destination, 1, 3), field_component_1, wavenumber_3, T)

  _apply_spectral_derivative!(_tensor2_component_data(destination, 2, 1), field_component_2, wavenumber_1, T)
  _apply_spectral_derivative!(_tensor2_component_data(destination, 2, 2), field_component_2, wavenumber_2, T)
  _apply_spectral_derivative!(_tensor2_component_data(destination, 2, 3), field_component_2, wavenumber_3, T)

  _apply_spectral_derivative!(_tensor2_component_data(destination, 3, 1), field_component_3, wavenumber_1, T)
  _apply_spectral_derivative!(_tensor2_component_data(destination, 3, 2), field_component_3, wavenumber_2, T)
  _apply_spectral_derivative!(_tensor2_component_data(destination, 3, 3), field_component_3, wavenumber_3, T)

  return destination
end


"""
    gradient(field, multipliers::FieldSpectralMultipliers)

Allocate and return the gradient of a field in spectral representation.

For a scalar field in spectral representation, this returns a vector field in spectral representation.
For a vector field in spectral representation, this returns a second-order tensor field in spectral representation.
"""
function gradient end


function gradient(field::ScalarFieldSpectral, multipliers::FieldSpectralMultipliers)
  destination = similar_field(field, Val(1))
  return gradient!(destination, field, multipliers)
end


function gradient(field::VectorFieldSpectral, multipliers::FieldSpectralMultipliers)
  destination = similar_field(field, Val(2))
  return gradient!(destination, field, multipliers)
end




############################
#        Divergence        #
############################


"""
    divergence!(
      destination::ScalarFieldSpectral,
      field::VectorFieldSpectral,
      multipliers::FieldSpectralMultipliers,
    )

    divergence!(
      destination::VectorFieldSpectral,
      field::TensorFieldSpectral{2},
      multipliers::FieldSpectralMultipliers,
    )

Compute the divergence of a field in spectral representation in-place.

For a vector field `u`, this computes the scalar field `∇ ⋅ u = ∂ᵢuᵢ`.

For a second-order tensor field `A`, this computes the vector field with components `(∇ ⋅ A)ᵢ = ∂ⱼAᵢⱼ`.

Fourier differentiation is coefficientwise, using the wavenumber arrays stored in `multipliers`.
"""
function divergence! end


function divergence!(destination::ScalarFieldSpectral{T}, field::VectorFieldSpectral{T}, multipliers::FieldSpectralMultipliers) where {T<:AbstractFloat}
  _check_field_domain_compatibility(destination, field)
  _check_multipliers_compatibility(field, multipliers)

  _apply_spectral_divergence!(field_data(destination),
    _vector_component_data(field, 1), _vector_component_data(field, 2), _vector_component_data(field, 3),
    _wavenumber_broadcast_view(multipliers, Val(1)), _wavenumber_broadcast_view(multipliers, Val(2)), _wavenumber_broadcast_view(multipliers, Val(3)), T)

  return destination
end


function divergence!(destination::VectorFieldSpectral{T}, field::TensorFieldSpectral{2, T}, multipliers::FieldSpectralMultipliers) where {T<:AbstractFloat}
  _check_field_domain_compatibility(destination, field)
  _check_multipliers_compatibility(field, multipliers)

  wavenumber_1 = _wavenumber_broadcast_view(multipliers, Val(1))
  wavenumber_2 = _wavenumber_broadcast_view(multipliers, Val(2))
  wavenumber_3 = _wavenumber_broadcast_view(multipliers, Val(3))

  _apply_spectral_divergence!(_vector_component_data(destination, 1),
    _tensor2_component_data(field, 1, 1), _tensor2_component_data(field, 1, 2), _tensor2_component_data(field, 1, 3),
    wavenumber_1, wavenumber_2, wavenumber_3, T)

  _apply_spectral_divergence!(_vector_component_data(destination, 2),
    _tensor2_component_data(field, 2, 1), _tensor2_component_data(field, 2, 2), _tensor2_component_data(field, 2, 3),
    wavenumber_1, wavenumber_2, wavenumber_3, T)

  _apply_spectral_divergence!(_vector_component_data(destination, 3),
    _tensor2_component_data(field, 3, 1), _tensor2_component_data(field, 3, 2), _tensor2_component_data(field, 3, 3),
    wavenumber_1, wavenumber_2, wavenumber_3, T)

  return destination
end


"""
    divergence(field, multipliers::FieldSpectralMultipliers)

Allocate and return the divergence of a field in spectral representation.

For a vector field in spectral representation, this returns a scalar field in spectral representation.
For a second-order tensor field in spectral representation, this returns a vector field in spectral representation.
"""
function divergence end


function divergence(field::VectorFieldSpectral, multipliers::FieldSpectralMultipliers)
  destination = similar_field(field, Val(0))
  return divergence!(destination, field, multipliers)
end


function divergence(field::TensorFieldSpectral{2}, multipliers::FieldSpectralMultipliers)
  destination = similar_field(field, Val(1))
  return divergence!(destination, field, multipliers)
end




######################
#        Curl        #
######################


"""
    curl!(
      destination::VectorFieldSpectral,
      field::VectorFieldSpectral,
      multipliers::FieldSpectralMultipliers,
    )

Compute the curl of a vector field in spectral representation in-place.

This computes the vector field ``∇ × u`` coefficientwise in spectral representation.
"""
function curl! end


"""
    _curl_noalias!(destination::VectorFieldSpectral, field::VectorFieldSpectral, multipliers::FieldSpectralMultipliers)

Coefficientwise curl `∇ × u`, written componentwise as `im * (k × û)`, assuming `destination` does not alias `field`. The public `curl!` wraps this with the aliasing guard.
"""
function _curl_noalias!(destination::VectorFieldSpectral{T}, field::VectorFieldSpectral{T}, multipliers::FieldSpectralMultipliers) where {T<:AbstractFloat}
  wavenumber_1 = _wavenumber_broadcast_view(multipliers, Val(1))
  wavenumber_2 = _wavenumber_broadcast_view(multipliers, Val(2))
  wavenumber_3 = _wavenumber_broadcast_view(multipliers, Val(3))
  imaginary_unit = Complex{T}(zero(T), one(T))

  field_component_1 = _vector_component_data(field, 1)
  field_component_2 = _vector_component_data(field, 2)
  field_component_3 = _vector_component_data(field, 3)

  @_assign! _vector_component_data(destination, 1) .= imaginary_unit .* (wavenumber_2 .* field_component_3 .- wavenumber_3 .* field_component_2)
  @_assign! _vector_component_data(destination, 2) .= imaginary_unit .* (wavenumber_3 .* field_component_1 .- wavenumber_1 .* field_component_3)
  @_assign! _vector_component_data(destination, 3) .= imaginary_unit .* (wavenumber_1 .* field_component_2 .- wavenumber_2 .* field_component_1)

  return destination
end


function curl!(destination::VectorFieldSpectral{T}, field::VectorFieldSpectral{T}, multipliers::FieldSpectralMultipliers) where {T<:AbstractFloat}
  _check_field_domain_compatibility(destination, field)
  _check_multipliers_compatibility(field, multipliers)

  if field_data(destination) === field_data(field)
    temporary = similar_field(destination, Val(1))
    _curl_noalias!(temporary, field, multipliers)
    copyto!(field_data(destination), field_data(temporary))

    return destination
  end

  return _curl_noalias!(destination, field, multipliers)
end


"""
    curl(field, multipliers::FieldSpectralMultipliers)

Allocate and return the curl of a vector field in spectral representation.
"""
function curl end


function curl(field::VectorFieldSpectral, multipliers::FieldSpectralMultipliers)
  destination = similar_field(field, Val(1))
  return curl!(destination, field, multipliers)
end




###########################
#        Laplacian        #
###########################


"""
    laplacian!(
      destination::AbstractFieldSpectral,
      field::AbstractFieldSpectral,
      multipliers::FieldSpectralMultipliers,
    )

Compute the Laplacian of a field in spectral representation in-place.

This operation is representation-preserving and coefficientwise in spectral representation. For every scalar, vector, or tensor component it computes

``\\widehat{\\Delta f}(k) = - |k|^2 \\hat f(k)``.

Returns the modified `destination` field.
"""
function laplacian! end


function laplacian!(destination::AbstractFieldSpectral{T, R}, field::AbstractFieldSpectral{T, R}, multipliers::FieldSpectralMultipliers) where {T<:AbstractFloat, R}
  check_field_compatibility(destination, field)
  _check_multipliers_compatibility(field, multipliers)

  squared_wavenumber = _squared_wavenumber_broadcast(multipliers)
  _apply_spectral_laplacian!(field_data(destination), field_data(field), squared_wavenumber)
  return destination
end


"""
    laplacian(field::AbstractFieldSpectral, multipliers::FieldSpectralMultipliers)

Allocate and return the Laplacian of a field in spectral representation.

This operation is representation-preserving: scalar fields return scalar fields, vector fields return vector fields, and tensor fields return tensor fields of the same tensor order.
"""
function laplacian end


function laplacian(field::AbstractFieldSpectral, multipliers::FieldSpectralMultipliers)
  destination = similar_field(field, Val(field_tensor_order(field)))
  return laplacian!(destination, field, multipliers)
end




###################################
#        Inverse Laplacian        #
###################################


"""
    inverse_laplacian!(
      destination::AbstractFieldSpectral,
      field::AbstractFieldSpectral,
      multipliers::FieldSpectralMultipliers,
    )

Compute the zero-mean inverse Laplacian of a field in spectral representation in-place.

This operation is representation-preserving and coefficientwise in spectral representation. For every scalar, vector, or tensor component it computes

``\\widehat{\\Delta^{-1} f}(k) = - \\hat f(k) / |k|^2``

for nonzero wavevectors and sets the zero Fourier mode to zero.

Returns the modified `destination` field.
"""
function inverse_laplacian! end


function inverse_laplacian!(destination::AbstractFieldSpectral{T, R}, field::AbstractFieldSpectral{T, R}, multipliers::FieldSpectralMultipliers) where {T<:AbstractFloat, R}
  check_field_compatibility(destination, field)
  _check_multipliers_compatibility(field, multipliers)

  squared_wavenumber = _squared_wavenumber_broadcast(multipliers)
  _apply_spectral_inverse_laplacian!(field_data(destination), field_data(field), squared_wavenumber, T)
  return destination
end


"""
    inverse_laplacian(field::AbstractFieldSpectral, multipliers::FieldSpectralMultipliers)

Allocate and return the zero-mean inverse Laplacian of a field in spectral representation.

This operation is representation-preserving: scalar fields return scalar fields, vector fields return vector fields, and tensor fields return tensor fields of the same tensor order.
"""
function inverse_laplacian end


function inverse_laplacian(field::AbstractFieldSpectral, multipliers::FieldSpectralMultipliers)
  destination = similar_field(field, Val(field_tensor_order(field)))
  return inverse_laplacian!(destination, field, multipliers)
end




########################################
#        Helmholtz Projection          #
########################################


"""
    helmholtz_projection!(
      destination::VectorFieldSpectral,
      field::VectorFieldSpectral,
      multipliers::FieldSpectralMultipliers,
    )

Compute the Helmholtz projection of a vector field in spectral representation in-place.

This operation projects a vector field onto its divergence-free part coefficientwise in spectral representation. For nonzero wavevectors it applies

``\\widehat{(\\mathbb{P}u)}_i(k) = \\left(\\delta_{ij} - k_i k_j / |k|^2\\right) \\hat u_j(k)``.

The zero Fourier mode is left unchanged.

Returns the modified `destination` field.
"""
function helmholtz_projection! end


"""
    _helmholtz_projection_noalias!(destination::VectorFieldSpectral, field::VectorFieldSpectral, multipliers::FieldSpectralMultipliers)

Apply the Helmholtz projection (see `_apply_spectral_helmholtz_projection!`) assuming `destination` does not alias `field`. The public `helmholtz_projection!` wraps this with the aliasing guard.
"""
function _helmholtz_projection_noalias!(destination::VectorFieldSpectral{T}, field::VectorFieldSpectral{T}, multipliers::FieldSpectralMultipliers) where {T<:AbstractFloat}
  wavenumber_1 = _wavenumber_broadcast_view(multipliers, Val(1))
  wavenumber_2 = _wavenumber_broadcast_view(multipliers, Val(2))
  wavenumber_3 = _wavenumber_broadcast_view(multipliers, Val(3))
  squared_wavenumber = _squared_wavenumber_broadcast(multipliers)

  _apply_spectral_helmholtz_projection!(
    _vector_component_data(destination, 1), _vector_component_data(destination, 2), _vector_component_data(destination, 3),
    _vector_component_data(field, 1), _vector_component_data(field, 2), _vector_component_data(field, 3),
    wavenumber_1, wavenumber_2, wavenumber_3, squared_wavenumber, T)
  return destination
end


function helmholtz_projection!(destination::VectorFieldSpectral{T}, field::VectorFieldSpectral{T}, multipliers::FieldSpectralMultipliers) where {T<:AbstractFloat}
  _check_field_domain_compatibility(destination, field)
  _check_multipliers_compatibility(field, multipliers)

  if field_data(destination) === field_data(field)
    temporary = similar_field(destination, Val(1))
    _helmholtz_projection_noalias!(temporary, field, multipliers)
    copyto!(field_data(destination), field_data(temporary))
    return destination
  end

  return _helmholtz_projection_noalias!(destination, field, multipliers)
end


"""
    helmholtz_projection(field::VectorFieldSpectral, multipliers::FieldSpectralMultipliers)

Allocate and return the Helmholtz projection of a vector field in spectral representation.

The returned vector field is the divergence-free part of `field`, with the zero Fourier mode left unchanged.
"""
function helmholtz_projection end


function helmholtz_projection(field::VectorFieldSpectral, multipliers::FieldSpectralMultipliers)
  destination = similar_field(field, Val(1))
  return helmholtz_projection!(destination, field, multipliers)
end


end # module DifferentialOperators