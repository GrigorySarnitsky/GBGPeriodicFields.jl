"""
    DifferentialOperators

Differential operators on scalar, vector, and tensor fields on three-dimensional rectangular periodic
domains: `gradient` ``\\equiv \\nabla``, `divergence` ``\\equiv \\nabla\\cdot``, `curl`
``\\equiv \\nabla\\times``, `laplacian` ``\\equiv \\Delta``, `inverse_laplacian` ``\\equiv \\Delta^{-1}``,
and `helmholtz_projection` ``\\equiv \\mathbb P`` (the Leray projection onto the divergence-free
subspace).

The implemented methods act on fields in spectral representation. A field **is** its finite Fourier
representation — the physical values are the trigonometric polynomial

```math
f(x) = \\frac{1}{N} \\sum_{k} \\hat f(k)\\, e^{\\mathrm{i} k \\cdot x}
```

over the grid's represented modes (``N = N_x N_y N_z`` the total number of grid points; coefficients beyond the grid are zero by definition, not truncated; forward transform unnormalized, inverse normalized — invariant 4).
Each operator is therefore the **exact** term-by-term derivative of that polynomial, realized as a
coefficientwise multiply by its wavenumber symbol — ``\\widehat{\\partial_{x_j} f}(k) = \\mathrm{i} k_j\\, \\hat f(k)``,
``\\widehat{\\Delta f}(k) = -|k|^2\\, \\hat f(k)`` — with no finite-difference truncation. The per-operator
docstrings give the symbol each one applies; the `=` is genuine (the only deliberate departure is the
Nyquist zeroing of the first-derivative wavenumbers on even-length axes, invariant 5). Each formula
mirrors the coefficientwise kernel it documents, so the two can be checked against each other.

The wavenumber symbols are held in a `FieldSpectralMultipliers` (built from a field with
`FieldSpectralMultipliers(field)`, or from the explicit six-array constructor); each operator has an
allocating form and an in-place `!` form. `laplacian`, `inverse_laplacian`, and `helmholtz_projection`
preserve tensor order; `gradient`, `divergence`, and `curl` change it as the operator dictates.
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
  _squared_wavenumber_broadcast


using ..FiberSections:
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
    _apply_spectral_divergence!(destination_component,
                                source_1, source_2, source_3,
                                wavenumber_1, wavenumber_2, wavenumber_3, ::Type{T})

Apply a coefficientwise contraction with the wavenumber vector, ``\\mathrm{i}\\,(k_1 \\hat s_1 + k_2 \\hat s_2 + k_3 \\hat s_3)`` (``k_a`` the wavenumber component and ``\\hat s_a`` the source field's spectral component along axis ``a = 1, 2, 3``). Used by `divergence` for the vector → scalar case and per output component for tensor → vector.
"""
function _apply_spectral_divergence!(destination_component, source_component_1, source_component_2, source_component_3,
  wavenumber_1, wavenumber_2, wavenumber_3, ::Type{T}) where {T<:AbstractFloat}
  
  imaginary_unit = Complex{T}(zero(T), one(T))
  @_assign! destination_component .= imaginary_unit .* (wavenumber_1 .* source_component_1 .+  wavenumber_2 .* source_component_2 .+ wavenumber_3 .* source_component_3)
  return destination_component
end


"""
    _apply_spectral_laplacian!(destination_data, source_data, squared_wavenumber)

Apply the coefficientwise Laplacian ``-|k|^2`` to each component (`destination_data .= (-).(squared_wavenumber) .* source_data`), where `squared_wavenumber` is the lazy `_squared_wavenumber_broadcast`. Representation-preserving over every component.
"""
function _apply_spectral_laplacian!(destination_data, source_data, squared_wavenumber)
  @_assign! destination_data .= (-).(squared_wavenumber) .* source_data   # broadcast unary minus: composes with the lazy |k|²
  return destination_data
end


"""
    _apply_spectral_inverse_laplacian!(destination_data, source_data, squared_wavenumber,
                                       ::Type{T})

Apply the coefficientwise zero-mean inverse Laplacian: `-source_data ./ squared_wavenumber` for nonzero wavevectors, and zero at the zero Fourier mode.
"""
function _apply_spectral_inverse_laplacian!(destination_data, source_data, squared_wavenumber, ::Type{T}) where {T<:AbstractFloat}
  # Multiply by the safe factor -1/|k|² (0 at the zero mode), composed as a single fused broadcast so it
  # stays allocation-free with the lazy |k|² (`_squared_wavenumber_broadcast`).
  @_assign! destination_data .= (-).(source_data) .* ifelse.(squared_wavenumber .== zero(T), zero(T), inv.(squared_wavenumber))
  return destination_data
end


"""
    _apply_spectral_helmholtz_projection!(destination_component_1, destination_component_2,
                                          destination_component_3, source_component_1,
                                          source_component_2, source_component_3,
                                          wavenumber_1, wavenumber_2, wavenumber_3,
                                          squared_wavenumber, ::Type{T})

Apply the coefficientwise Leray/Helmholtz projection ``\\mathbb P`` onto the divergence-free subspace: subtract the longitudinal part ``k_i (k_j \\hat s_j)/|k|^2`` from each component. The zero Fourier mode is left unchanged.
"""
function _apply_spectral_helmholtz_projection!(destination_component_1, destination_component_2, destination_component_3,
    source_component_1, source_component_2, source_component_3, wavenumber_1, wavenumber_2, wavenumber_3, squared_wavenumber, ::Type{T}) where {T<:AbstractFloat}
  # Allocation-free: the longitudinal coefficient kⱼŝⱼ/|k|² and the safe |k|² (1 at the zero mode) are
  # fused into each component's broadcast rather than materialized as scratch arrays, so the projection
  # runs fully in place. This matters in allocating hot loops, especially on GPU where per-call scratch
  # would otherwise grow the memory pool. Correct because every caller passes distinct destination and
  # source arrays (the aliased path of `helmholtz_projection!` allocates its own temporary upstream), so
  # recomputing kⱼŝⱼ from the unmodified source for each component has no read-after-write hazard.
  @_assign! destination_component_1 .= source_component_1 .- wavenumber_1 .*
    (wavenumber_1 .* source_component_1 .+ wavenumber_2 .* source_component_2 .+ wavenumber_3 .* source_component_3) ./
    ifelse.(squared_wavenumber .== zero(T), one(T), squared_wavenumber)
  @_assign! destination_component_2 .= source_component_2 .- wavenumber_2 .*
    (wavenumber_1 .* source_component_1 .+ wavenumber_2 .* source_component_2 .+ wavenumber_3 .* source_component_3) ./
    ifelse.(squared_wavenumber .== zero(T), one(T), squared_wavenumber)
  @_assign! destination_component_3 .= source_component_3 .- wavenumber_3 .*
    (wavenumber_1 .* source_component_1 .+ wavenumber_2 .* source_component_2 .+ wavenumber_3 .* source_component_3) ./
    ifelse.(squared_wavenumber .== zero(T), one(T), squared_wavenumber)

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

Compute the gradient (`gradient` ``\\equiv \\nabla``) of a field in spectral representation in-place;
returns `destination`. A scalar field ``\\varphi`` gives the vector ``(\\nabla\\varphi)_i = \\partial_{x_i}\\varphi``;
a vector field ``u`` gives the second-order tensor ``(\\nabla u)_{ij} = \\partial_{x_j} u_i``. Computed
coefficientwise (each source component multiplied by ``\\mathrm{i} k`` of the differentiation axis):

```math
\\widehat{(\\nabla\\varphi)_i}(k) = \\mathrm{i}\\, k_i\\, \\hat\\varphi(k),
\\qquad
\\widehat{(\\nabla u)_{ij}}(k) = \\mathrm{i}\\, k_j\\, \\hat u_i(k).
```
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

Allocate and return the gradient ``\\nabla`` of a field in spectral representation.

For a scalar field this returns a vector field (``(\\nabla\\varphi)_i = \\partial_i\\varphi``); for a
vector field, a second-order tensor field (``(\\nabla u)_{ij} = \\partial_j u_i``).
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

Compute the divergence (`divergence` ``\\equiv \\nabla\\cdot``) of a field in spectral representation
in-place; returns `destination`. A vector field ``u`` gives the scalar ``\\nabla\\cdot u = \\partial_{x_i} u_i``;
a second-order tensor field ``A`` gives the vector ``(\\nabla\\cdot A)_i = \\partial_{x_j} A_{ij}``.
Computed as the coefficientwise contraction with ``i k`` (the kernel sums ``i k_j \\hat{(\\cdot)}_j`` over
the three axes):

```math
\\widehat{\\nabla\\cdot u}(k) = \\mathrm{i}\\,(k_1 \\hat u_1 + k_2 \\hat u_2 + k_3 \\hat u_3),
\\qquad
\\widehat{(\\nabla\\cdot A)_i}(k) = \\mathrm{i}\\,(k_1 \\hat A_{i1} + k_2 \\hat A_{i2} + k_3 \\hat A_{i3}).
```
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

Allocate and return the divergence ``\\nabla\\cdot`` of a field in spectral representation.

For a vector field this returns a scalar field (``\\nabla\\cdot u = \\partial_i u_i``); for a
second-order tensor field, a vector field (``(\\nabla\\cdot A)_i = \\partial_j A_{ij}``).
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

Compute the curl (`curl` ``\\equiv \\nabla\\times``) of a vector field in spectral representation
in-place; returns `destination`. Coefficientwise, ``\\widehat{\\nabla\\times u}(k) = \\mathrm{i}\\, k \\times \\hat u(k)``,
i.e. componentwise (matching the kernel):

```math
\\widehat{(\\nabla\\times u)_1}(k) = \\mathrm{i}\\,(k_2 \\hat u_3 - k_3 \\hat u_2), \\quad
\\widehat{(\\nabla\\times u)_2}(k) = \\mathrm{i}\\,(k_3 \\hat u_1 - k_1 \\hat u_3), \\quad
\\widehat{(\\nabla\\times u)_3}(k) = \\mathrm{i}\\,(k_1 \\hat u_2 - k_2 \\hat u_1).
```
"""
function curl! end


"""
    _curl_noalias!(destination::VectorFieldSpectral, field::VectorFieldSpectral,
                   multipliers::FieldSpectralMultipliers)

Coefficientwise curl ``\\nabla\\times u``, written componentwise as ``\\mathrm{i}\\,(k \\times \\hat u)``, assuming `destination` does not alias `field`. The public `curl!` wraps this with the aliasing guard.
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

Allocate and return the curl ``\\nabla\\times u`` of a vector field in spectral representation.
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

Compute the Laplacian (`laplacian` ``\\equiv \\Delta``) of a field in spectral representation in-place;
returns `destination`. Representation-preserving and coefficientwise — for every scalar, vector, or
tensor component the kernel multiplies by ``-|k|^2``:

```math
\\widehat{\\Delta f}(k) = -|k|^2\\, \\hat f(k), \\qquad |k|^2 = k_1^2 + k_2^2 + k_3^2.
```
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

Allocate and return the Laplacian ``\\Delta`` (``\\widehat{\\Delta f}(k) = -|k|^2 \\hat f(k)``) of a field in spectral representation.

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

Compute the zero-mean inverse Laplacian (`inverse_laplacian` ``\\equiv \\Delta^{-1}``) of a field in
spectral representation in-place; returns `destination`. Representation-preserving and coefficientwise —
the kernel divides by ``-|k|^2`` away from the origin and zeroes the mean mode:

```math
\\widehat{\\Delta^{-1} f}(k) =
\\begin{cases}
-\\,\\hat f(k) / |k|^2, & k \\ne 0, \\\\
0, & k = 0.
\\end{cases}
```
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

Allocate and return the zero-mean inverse Laplacian ``\\Delta^{-1}`` (``\\widehat{\\Delta^{-1} f}(k) = -\\hat f(k)/|k|^2`` for ``k \\ne 0``, zero mode set to zero) of a field in spectral representation.

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

Compute the Helmholtz (Leray) projection (`helmholtz_projection` ``\\equiv \\mathbb P``) of a vector
field in spectral representation in-place; returns `destination`. It removes the longitudinal
(curl-free) part coefficientwise, leaving the divergence-free part — the kernel subtracts
``k_i\\,(k\\cdot\\hat u)/|k|^2`` from ``\\hat u_i``:

```math
\\widehat{(\\mathbb P u)}_i(k) = \\Bigl(\\delta_{ij} - \\frac{k_i k_j}{|k|^2}\\Bigr)\\, \\hat u_j(k), \\qquad k \\ne 0,
```

and leaves the zero Fourier mode unchanged.
"""
function helmholtz_projection! end


"""
    _helmholtz_projection_noalias!(destination::VectorFieldSpectral,
                                   field::VectorFieldSpectral,
                                   multipliers::FieldSpectralMultipliers)

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

Allocate and return the Helmholtz (Leray) projection ``\\mathbb P`` of a vector field in spectral representation: ``\\widehat{(\\mathbb P u)}_i(k) = (\\delta_{ij} - k_i k_j/|k|^2)\\,\\hat u_j(k)``.

The returned vector field is the divergence-free part of `field`, with the zero Fourier mode left unchanged.
"""
function helmholtz_projection end


function helmholtz_projection(field::VectorFieldSpectral, multipliers::FieldSpectralMultipliers)
  destination = similar_field(field, Val(1))
  return helmholtz_projection!(destination, field, multipliers)
end


end # module DifferentialOperators