"""
    DifferentialOperators

Spectral differential operators on scalar, vector, and tensor fields over three-dimensional
rectangular periodic domains. A field in this module is its finite Fourier representation, so each
operator is the exact term-by-term derivative of that trigonometric polynomial, realized as a
coefficientwise multiply by a wavenumber symbol with no finite-difference truncation. The wavenumber
symbols are held in a [`FieldSpectralMultipliers`](@ref), built from a field with
`FieldSpectralMultipliers(field)` or from the explicit six-array constructor. Every operator provides
an allocating form and an in-place `!` form, and each per-operator docstring gives both the
physical-space meaning and the spectral symbol it applies.

The operation families are:

- [`gradient`](@ref) ``\\equiv \\nabla`` raises the tensor order: a scalar field becomes a vector field, and a vector field becomes a second-order tensor field.
- [`divergence`](@ref) ``\\equiv \\nabla\\cdot`` lowers the tensor order: a vector field becomes a scalar field, and a second-order tensor field becomes a vector field.
- [`curl`](@ref) ``\\equiv \\nabla\\times`` returns the local rotation rate of a vector field and preserves the tensor order.
- [`symmetric_gradient`](@ref) ``\\equiv \\operatorname{sym}\\nabla`` returns the symmetric part of a vector field's gradient as a second-order tensor field, formed directly without the full gradient — the fused symmetric peer of `curl`.
- [`laplacian`](@ref) ``\\equiv \\Delta`` applies the second-derivative operator to every component and preserves the tensor order.
- [`inverse_laplacian`](@ref) ``\\equiv \\Delta^{-1}`` returns the zero-mean solution of Poisson's equation and preserves the tensor order.
- [`helmholtz_projection`](@ref) ``\\equiv \\mathbb P`` projects a vector field onto its divergence-free part.

The Nyquist frequency is treated differently by symbol: first-derivative wavenumbers are zeroed at the
Nyquist frequency on even-length axes, while squared wavenumbers keep the true squared wavenumber
there.
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
       symmetric_gradient!,
       symmetric_gradient,
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

Apply a coefficientwise first derivative along one axis, computing `destination_component .= im * wavenumber .* source_component`, where `wavenumber` is a `_wavenumber_broadcast_view`. This kernel is the building block that `gradient` and `divergence` share.
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

Apply a coefficientwise contraction with the wavenumber vector, computing ``\\mathrm{i} (k_1 \\hat s_1 + k_2 \\hat s_2 + k_3 \\hat s_3)``, where ``k_a`` is the wavenumber component and ``\\hat s_a`` is the source field's spectral component along axis ``a = 1, 2, 3``. The `divergence` operator uses this kernel for the vector-to-scalar case, and once per output component for the tensor-to-vector case.
"""
function _apply_spectral_divergence!(destination_component, source_component_1, source_component_2, source_component_3,
  wavenumber_1, wavenumber_2, wavenumber_3, ::Type{T}) where {T<:AbstractFloat}
  
  imaginary_unit = Complex{T}(zero(T), one(T))
  @_assign! destination_component .= imaginary_unit .* (wavenumber_1 .* source_component_1 .+  wavenumber_2 .* source_component_2 .+ wavenumber_3 .* source_component_3)
  return destination_component
end


"""
    _apply_spectral_laplacian!(destination_data, source_data, squared_wavenumber)

Apply the coefficientwise Laplacian symbol ``-|k|^2`` to each component, computing `destination_data .= (-).(squared_wavenumber) .* source_data`, where `squared_wavenumber` is the lazy `_squared_wavenumber_broadcast`. The kernel preserves the tensor order because it acts on every component alike.
"""
function _apply_spectral_laplacian!(destination_data, source_data, squared_wavenumber)
  @_assign! destination_data .= (-).(squared_wavenumber) .* source_data   # broadcast unary minus: composes with the lazy |k|²
  return destination_data
end


"""
    _apply_spectral_inverse_laplacian!(destination_data, source_data, squared_wavenumber,
                                       ::Type{T})

Apply the coefficientwise zero-mean inverse Laplacian, computing `-source_data ./ squared_wavenumber` at every nonzero wavevector and setting the zero Fourier mode to zero.
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

Apply the coefficientwise Leray/Helmholtz projection ``\\mathbb P`` onto the divergence-free subspace by subtracting the longitudinal part ``k_i (k_j \\hat s_j)/|k|^2`` from each component. The kernel leaves the zero Fourier mode unchanged.
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

Compute the gradient (`gradient` ``\\equiv \\nabla``) of a field and write it into `destination`,
returning `destination`. Differentiating raises the tensor order by one: a scalar field ``\\varphi``
gives the vector field with components ``(\\nabla\\varphi)_i = \\partial_{x_i}\\varphi``, and a vector
field ``u`` gives the second-order tensor field with components ``(\\nabla u)_{ij} = \\partial_{x_j} u_i``.

Use this in-place form when `destination` is already allocated; the allocating [`gradient`](@ref)
returns a fresh result instead.

The arguments are:
- `destination` — the field that receives the result; it shares the domain of `field` and holds one tensor order higher.
- `field` — the field to differentiate, in spectral representation.
- `multipliers` — the wavenumber symbols for the field's grid.

Each output component is the source component multiplied coefficientwise by ``\\mathrm{i}`` times the
wavenumber of the differentiation axis:

```math
\\widehat{(\\nabla\\varphi)_i}(k) = \\mathrm{i}  k_i  \\hat\\varphi(k),
\\qquad
\\widehat{(\\nabla u)_{ij}}(k) = \\mathrm{i}  k_j  \\hat u_i(k).
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

Allocating form of [`gradient!`](@ref): allocate the result and return it. A scalar field ``\\varphi``
gives its gradient vector field ``\\nabla\\varphi``; a vector field ``u`` gives the second-order tensor
field ``\\nabla u``. See `gradient!` for the componentwise definition and the spectral kernel.
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

Compute the divergence (`divergence` ``\\equiv \\nabla\\cdot``) of a field and write it into
`destination`, returning `destination`. Differentiating lowers the tensor order by one: a vector field
``u`` gives the scalar field ``\\nabla\\cdot u = \\partial_{x_i} u_i``, and a second-order tensor field
``A`` gives the vector field with components ``(\\nabla\\cdot A)_i = \\partial_{x_j} A_{ij}``.

Use this in-place form when `destination` is already allocated; the allocating [`divergence`](@ref)
returns a fresh result instead.

The arguments are:
- `destination` — the field that receives the result; it shares the domain of `field` and holds one tensor order lower.
- `field` — the field to differentiate, in spectral representation.
- `multipliers` — the wavenumber symbols for the field's grid.

The result is the coefficientwise contraction of the source with ``\\mathrm{i}`` times the wavenumber
vector, summed over the three axes:

```math
\\widehat{\\nabla\\cdot u}(k) = \\mathrm{i} (k_1 \\hat u_1 + k_2 \\hat u_2 + k_3 \\hat u_3),
\\qquad
\\widehat{(\\nabla\\cdot A)_i}(k) = \\mathrm{i} (k_1 \\hat A_{i1} + k_2 \\hat A_{i2} + k_3 \\hat A_{i3}).
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

Allocating form of [`divergence!`](@ref): allocate the result and return it. A vector field ``u`` gives
its scalar divergence ``\\nabla\\cdot u``; a second-order tensor field ``A`` gives the vector field
``\\nabla\\cdot A``. See `divergence!` for the componentwise definition and the spectral kernel.
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

Compute the curl (`curl` ``\\equiv \\nabla\\times``) of a vector field and write it into `destination`,
returning `destination`. The curl is the vector field whose components are, with ``\\varepsilon_{ijk}``
the Levi-Civita symbol, ``(\\nabla\\times u)_i = \\varepsilon_{ijk}  \\partial_{x_j} u_k``; written out
cyclically,

```math
\\begin{gathered}
(\\nabla\\times u)_1 = \\partial_{x_2} u_3 - \\partial_{x_3} u_2, \\\\
(\\nabla\\times u)_2 = \\partial_{x_3} u_1 - \\partial_{x_1} u_3, \\\\
(\\nabla\\times u)_3 = \\partial_{x_1} u_2 - \\partial_{x_2} u_1.
\\end{gathered}
```

Use this in-place form when `destination` is already allocated; the allocating [`curl`](@ref) returns a
fresh result instead. The `destination` may alias `field`: the aliased call is detected and computed through
a guard temporary, at the cost of one field-sized allocation.

The arguments are:
- `destination` — the vector field that receives the result; it shares the domain of `field`.
- `field` — the vector field to differentiate, in spectral representation.
- `multipliers` — the wavenumber symbols for the field's grid.

The spectral symbol is a coefficientwise multiply by ``\\mathrm{i}`` times the cross product with the
wavenumber vector, ``\\widehat{\\nabla\\times u}(k) = \\mathrm{i}  k \\times \\hat u(k)``, componentwise:

```math
\\begin{gathered}
\\widehat{(\\nabla\\times u)_1}(k) = \\mathrm{i} (k_2 \\hat u_3 - k_3 \\hat u_2), \\\\
\\widehat{(\\nabla\\times u)_2}(k) = \\mathrm{i} (k_3 \\hat u_1 - k_1 \\hat u_3), \\\\
\\widehat{(\\nabla\\times u)_3}(k) = \\mathrm{i} (k_1 \\hat u_2 - k_2 \\hat u_1).
\\end{gathered}
```
"""
function curl! end


"""
    _curl_noalias!(destination::VectorFieldSpectral, field::VectorFieldSpectral,
                   multipliers::FieldSpectralMultipliers)

Compute the coefficientwise curl ``\\nabla\\times u`` componentwise as ``\\mathrm{i} (k \\times \\hat u)``, assuming `destination` does not alias `field`. The public `curl!` wraps this kernel with the aliasing guard.
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

Allocating form of [`curl!`](@ref): allocate the result and return it, the curl ``\\nabla\\times u`` of a
vector field. See `curl!` for the componentwise definition and the spectral kernel.
"""
function curl end


function curl(field::VectorFieldSpectral, multipliers::FieldSpectralMultipliers)
  destination = similar_field(field, Val(1))
  return curl!(destination, field, multipliers)
end




#####################################
#        Symmetric Gradient         #
#####################################


"""
    symmetric_gradient!(
      destination::TensorFieldSpectral{2},
      field::VectorFieldSpectral,
      multipliers::FieldSpectralMultipliers,
    )

Compute the symmetric gradient (`symmetric_gradient` ``\\equiv \\operatorname{sym}\\nabla``) of a vector
field and write it into `destination`, returning `destination`. It is the symmetric part of the gradient
``\\nabla u``, the second-order tensor field

```math
S_{ij} = \\tfrac{1}{2} (\\partial_{x_j} u_i + \\partial_{x_i} u_j),
```

formed directly. It is the fused symmetric peer of [`curl`](@ref), which extracts the *antisymmetric* part
of ``\\nabla u`` as a vector: forming ``S`` this way skips the full nine-component gradient tensor that
`sym(gradient(u))` builds only to symmetrize, so reach for it whenever the symmetric part is all you need.

Use this in-place form when `destination` is already allocated; the allocating [`symmetric_gradient`](@ref)
returns a fresh result instead.

The arguments are:
- `destination` — the second-order tensor field that receives the result; it shares the domain of `field` and holds one tensor order higher.
- `field` — the vector field to differentiate, in spectral representation.
- `multipliers` — the wavenumber symbols for the field's grid.

The spectral symbol symmetrizes ``\\mathrm{i} k_j \\hat u_i`` in its two indices:

```math
\\widehat{S_{ij}}(k) = \\tfrac{\\mathrm{i}}{2} \\bigl(k_j \\hat u_i(k) + k_i \\hat u_j(k)\\bigr).
```
"""
function symmetric_gradient! end


function symmetric_gradient!(destination::TensorFieldSpectral{2, T}, field::VectorFieldSpectral{T}, multipliers::FieldSpectralMultipliers) where {T<:AbstractFloat}
  _check_field_domain_compatibility(destination, field)
  _check_multipliers_compatibility(field, multipliers)

  wavenumber_1 = _wavenumber_broadcast_view(multipliers, Val(1))
  wavenumber_2 = _wavenumber_broadcast_view(multipliers, Val(2))
  wavenumber_3 = _wavenumber_broadcast_view(multipliers, Val(3))

  field_component_1 = _vector_component_data(field, 1)
  field_component_2 = _vector_component_data(field, 2)
  field_component_3 = _vector_component_data(field, 3)

  imaginary_unit = Complex{T}(zero(T), one(T))
  half_imaginary = imaginary_unit * inv(T(2))

  # Diagonal Sᵢᵢ = i·kᵢ·ûᵢ (the ½(kᵢûᵢ + kᵢûᵢ) collapses); off-diagonal Sᵢⱼ = (i/2)(kⱼûᵢ + kᵢûⱼ), written
  # from the same expression for the symmetric pair. An order-raising operator writes a tensor from a
  # vector, so destination and source occupy distinct storage and cannot alias — no guard needed (like
  # `gradient!`).
  @_assign! _tensor2_component_data(destination, 1, 1) .= imaginary_unit .* wavenumber_1 .* field_component_1
  @_assign! _tensor2_component_data(destination, 2, 2) .= imaginary_unit .* wavenumber_2 .* field_component_2
  @_assign! _tensor2_component_data(destination, 3, 3) .= imaginary_unit .* wavenumber_3 .* field_component_3

  @_assign! _tensor2_component_data(destination, 1, 2) .= half_imaginary .* (wavenumber_2 .* field_component_1 .+ wavenumber_1 .* field_component_2)
  @_assign! _tensor2_component_data(destination, 2, 1) .= half_imaginary .* (wavenumber_2 .* field_component_1 .+ wavenumber_1 .* field_component_2)

  @_assign! _tensor2_component_data(destination, 1, 3) .= half_imaginary .* (wavenumber_3 .* field_component_1 .+ wavenumber_1 .* field_component_3)
  @_assign! _tensor2_component_data(destination, 3, 1) .= half_imaginary .* (wavenumber_3 .* field_component_1 .+ wavenumber_1 .* field_component_3)

  @_assign! _tensor2_component_data(destination, 2, 3) .= half_imaginary .* (wavenumber_3 .* field_component_2 .+ wavenumber_2 .* field_component_3)
  @_assign! _tensor2_component_data(destination, 3, 2) .= half_imaginary .* (wavenumber_3 .* field_component_2 .+ wavenumber_2 .* field_component_3)

  return destination
end


"""
    symmetric_gradient(field::VectorFieldSpectral, multipliers::FieldSpectralMultipliers)

Allocating form of [`symmetric_gradient!`](@ref): allocate the result and return it, the symmetric
gradient ``\\operatorname{sym}\\nabla u`` — the symmetric part of ``\\nabla u`` as a second-order tensor
field, formed without the full gradient. See `symmetric_gradient!` for the componentwise definition and the
spectral kernel.
"""
function symmetric_gradient end


function symmetric_gradient(field::VectorFieldSpectral, multipliers::FieldSpectralMultipliers)
  destination = similar_field(field, Val(2))
  return symmetric_gradient!(destination, field, multipliers)
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

Compute the Laplacian (`laplacian` ``\\equiv \\Delta``) of a field and write it into `destination`,
returning `destination`. The Laplacian is a local operator: it sums the second partial derivatives of
a scalar field ``f`` over the three axes, and it acts on each component of a vector or tensor field
alike, so it preserves the tensor order:

```math
\\Delta f = \\partial^2_{x_i x_i} f, \\qquad (\\Delta u)_j = \\partial^2_{x_i x_i} u_j.
```

Use this in-place form when `destination` is already allocated; the allocating [`laplacian`](@ref)
returns a fresh result instead.

The arguments are:
- `destination` — the field that receives the result; it matches the domain and tensor order of `field`.
- `field` — the field to differentiate, in spectral representation.
- `multipliers` — the wavenumber symbols for the field's grid.

The spectral symbol is a coefficientwise multiply by ``-|k|^2``:

```math
\\widehat{\\Delta f}(k) = -|k|^2  \\hat f(k), \\qquad |k|^2 = k_1^2 + k_2^2 + k_3^2.
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

Allocating form of [`laplacian!`](@ref): allocate the result and return it, the Laplacian ``\\Delta f``.
Representation-preserving (scalar, vector, or tensor field of the same tensor order). See `laplacian!` for
the spectral form ``-|k|^2``.
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

Compute the zero-mean inverse Laplacian (`inverse_laplacian` ``\\equiv \\Delta^{-1}``) of a field and
write it into `destination`, returning `destination`. The result is the zero-mean field ``\\psi`` that
solves Poisson's equation ``\\Delta\\psi = f``; because the Laplacian annihilates constants, the
solution is fixed uniquely by requiring its mean to vanish:

```math
\\Delta\\psi = f, \\qquad \\int_\\Omega \\psi \\,\\mathrm{d}x = 0.
```

For a vector or tensor field the same solve is applied to each component, so the tensor order is
preserved.

!!! warning
    As the inverse of a differential operator, ``\\Delta^{-1}`` is nonlocal: unlike the Laplacian it
    has no local partial-derivative formula, and the value at any point depends on the whole field.

Use this in-place form when `destination` is already allocated; the allocating
[`inverse_laplacian`](@ref) returns a fresh result instead.

The arguments are:
- `destination` — the field that receives the result; it matches the domain and tensor order of `field`.
- `field` — the field to invert, in spectral representation.
- `multipliers` — the wavenumber symbols for the field's grid.

The spectral symbol divides by ``-|k|^2`` away from the origin and sets the zero Fourier mode to zero:

```math
\\widehat{\\Delta^{-1} f}(k) =
\\begin{cases}
- \\hat f(k) / |k|^2, & k \\ne 0, \\\\
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

Allocating form of [`inverse_laplacian!`](@ref): allocate the result and return it, the zero-mean inverse
Laplacian ``\\Delta^{-1} f`` (the zero Fourier mode is set to zero). Representation-preserving (scalar,
vector, or tensor field of the same tensor order). See `inverse_laplacian!` for the spectral form.
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
field and write it into `destination`, returning `destination`. The projection removes the
longitudinal (curl-free) part of the field and keeps the divergence-free part, subtracting the
gradient of the pressure-like potential that solves the divergence:

```math
\\mathbb P u = u - \\nabla  \\Delta^{-1}(\\nabla\\cdot u).
```

!!! warning
    The inverse Laplacian ``\\Delta^{-1}`` is nonlocal, so ``\\mathbb P`` is a nonlocal operator in
    physical space even though it acts coefficientwise in spectral representation.

Use this in-place form when `destination` is already allocated; the allocating
[`helmholtz_projection`](@ref) returns a fresh result instead. The `destination` may alias `field`: the
aliased call is detected and computed through a guard temporary, at the cost of one field-sized
allocation.

The arguments are:
- `destination` — the vector field that receives the result; it shares the domain of `field`.
- `field` — the vector field to project, in spectral representation.
- `multipliers` — the wavenumber symbols for the field's grid.

The spectral symbol subtracts the longitudinal part ``k_i (k\\cdot\\hat u)/|k|^2`` from
``\\hat u_i`` at every nonzero wavevector, and leaves the zero Fourier mode unchanged:

```math
\\widehat{(\\mathbb P u)}_i(k) = \\Bigl(\\delta_{ij} - \\frac{k_i k_j}{|k|^2}\\Bigr)  \\hat u_j(k), \\qquad k \\ne 0.
```
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

Allocating form of [`helmholtz_projection!`](@ref): allocate the result and return it, the Helmholtz
(Leray) projection ``\\mathbb P u`` — the divergence-free part of a vector field, with the zero Fourier
mode left unchanged. See `helmholtz_projection!` for the spectral form.
"""
function helmholtz_projection end


function helmholtz_projection(field::VectorFieldSpectral, multipliers::FieldSpectralMultipliers)
  destination = similar_field(field, Val(1))
  return helmholtz_projection!(destination, field, multipliers)
end


end # module DifferentialOperators