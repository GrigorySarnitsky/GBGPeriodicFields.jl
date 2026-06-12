"""
    Convolution

The **kernel-multiplier** operation family (`docs/ARCHITECTURE.md` §2, decision 20): periodic
convolution of a field with a kernel, in spectral representation. It is the spectral sibling of the
differential operators and the same-base counterpart of `Interpolation` — both realize the "kernel
measure" of the measure taxonomy (decision 19); convolution is the grid→grid multiplier,
interpolation the grid↔point base-change.

On the torus the only convolution is the periodic (circular) one, and by the convolution theorem it
is the **coefficientwise spectral product** `f̂ · ĝ`. The kernel `g` is supplied by its transfer
function `ĝ` as a **scalar field in spectral representation** (`ScalarFieldSpectral`); a scalar
kernel multiplies every fiber component, so one operation serves scalar, vector, and tensor fields.

This coefficientwise product is exactly the operation invariant 1 names but bans **as `*`** (because
`*` would be read as the spectral *pointwise* product, which it is not). It is offered here under its
true name — `convolve`, never `*` — and is linear in the field for a fixed kernel. The pointwise
spectral product, division, and norms remain absent.

- `convolve(f, g)` / `convolve!` — the convolution `f ⋆ g = (f̂ · ĝ)ˇ`, with the in-place and
  `α`/`β`-accumulate forms. Because a kernel is itself a scalar field in spectral representation,
  `convolve(g₁, g₂)` composes two kernels. Spectral representation only.
- `spectral_cutoff` — a neutral kernel builder: the isotropic sharp low-pass (de-aliasing) cutoff.

Physics stays consumer-side: an LES filter, an integrating factor `exp(-νk²Δt)`, or a de-aliasing
mask is a `ScalarFieldSpectral` the consumer builds from `FieldSpectralMultipliers` and convolves
with — the package supplies the operation, not the physical meaning (invariant 12).
"""
module Convolution

using ..Fields:
  AbstractFieldSpectral,
  ScalarFieldSpectral,
  FieldSpectralMultipliers,
  field_data,
  field_scalar_type,
  field_tensor_order,
  similar_field,
  check_field_compatibility,
  _check_field_domain_compatibility,
  _check_multipliers_compatibility,
  _squared_wavenumber_broadcast

using ..FiberSections:
  _assign!,
  @_assign!

export convolve, convolve!, spectral_cutoff, spectral_band, squared_wavenumber_field


####################################################
#        Convolution kernel                        #
####################################################


"""
    _apply_convolution!(destination_data, source_data, kernel_data, alpha, beta)

Apply the coefficientwise spectral product `destination .= α · kernel · source + β · destination` —
the periodic convolution `f ⋆ g` in spectral representation, with `kernel_data = ĝ`. The scalar
`kernel_data` (`(Nx, Ny, Nz)`) broadcasts over the fiber components of `source_data`, exactly as the
Laplacian's squared wavenumber does, so one body serves every tensor order. Branches on
`iszero(beta)` (overwrite vs. accumulate, invariant 10). Coefficientwise ⇒ aliasing-safe:
`destination` may be `source` (or the kernel).
"""
function _apply_convolution!(destination_data, source_data, kernel_data, alpha, beta)
  if iszero(beta)
    @_assign! destination_data .= alpha .* kernel_data .* source_data
  else
    @_assign! destination_data .= alpha .* kernel_data .* source_data .+ beta .* destination_data
  end
  return destination_data
end


####################################################
#        Convolution (apply a Fourier kernel)      #
####################################################


"""
    convolve!(destination, field, kernel::ScalarFieldSpectral)
    convolve!(destination, field, kernel::ScalarFieldSpectral, α, β)

Convolve `field` (in spectral representation) with the kernel whose transfer function is `kernel`,
writing into `destination` in-place: the periodic (circular) convolution `f ⋆ g`, realized
coefficientwise as `f̂ · ĝ`. `kernel` is a scalar field in spectral representation holding `ĝ`; it
multiplies every fiber component of `field`, so one method serves scalar, vector, and tensor fields.
Representation-preserving: `destination` has `field`'s tensor order.

The five-argument form computes `destination = α·(f ⋆ g) + β·destination` (`α`, `β` real numbers,
converted to the field's scalar type); the three-argument form overwrites (`α = 1`, `β = 0`).
Coefficientwise ⇒ aliasing-safe: `destination` may alias `field` (or the kernel).

Spectral representation only — there is no physical-space `convolve` (on the torus, convolution *is*
the coefficientwise spectral product). That product is offered here under its true name, never as
`*` (invariant 1): `convolve` is convolution, not the spectral pointwise product.

Returns the modified `destination`.
"""
function convolve! end


function convolve!(destination::AbstractFieldSpectral{T, R}, field::AbstractFieldSpectral{T, R},
    kernel::ScalarFieldSpectral{T}, alpha::Real, beta::Real) where {T<:AbstractFloat, R}
  check_field_compatibility(destination, field)
  _check_field_domain_compatibility(field, kernel)
  _apply_convolution!(field_data(destination), field_data(field), field_data(kernel), T(alpha), T(beta))
  return destination
end


function convolve!(destination::AbstractFieldSpectral{T, R}, field::AbstractFieldSpectral{T, R},
    kernel::ScalarFieldSpectral{T}) where {T<:AbstractFloat, R}
  return convolve!(destination, field, kernel, one(T), zero(T))
end


"""
    convolve(field, kernel::ScalarFieldSpectral)

Allocate and return the periodic convolution of `field` with the kernel `ĝ = kernel`, in spectral
representation — `f ⋆ g`, the coefficientwise product `f̂ · ĝ`. Representation- and
tensor-order-preserving. Because a kernel is itself a scalar field in spectral representation,
`convolve(g₁, g₂)` composes two kernels (the product of their transfer functions). Spectral
representation only.
"""
function convolve end


function convolve(field::AbstractFieldSpectral, kernel::ScalarFieldSpectral)
  destination = similar_field(field, Val(field_tensor_order(field)))
  return convolve!(destination, field, kernel)
end


####################################################
#        Kernel builders                           #
####################################################


"""
    squared_wavenumber_field(reference::AbstractFieldSpectral, multipliers::FieldSpectralMultipliers)

The **squared-wavenumber field** `|k|² = k₁² + k₂² + k₃²` as a scalar field in spectral
representation, on `reference`'s grid and array backend. The neutral isotropic radial coordinate of
spectral space: the consumer builds a Fourier symbol from it — a viscous integrating factor
`exp(−ν|k|²Δt)`, a smooth spectral envelope `exp(−(|k|/k_p)²)`, a Germano filter `1/(1+Δ²|k|²)` — by
broadcasting over its `field_data`, then applies it with [`convolve`](@ref). Carrying `ν`, `Δt`, and
the filter width is the consumer's (invariant 12); the package supplies only the coordinate.

`|k|²` is summed with the true value kept at the Nyquist frequency (the Laplacian convention,
invariant 5). The value is real but stored in the `Complex{T}` coefficient array of a
`ScalarFieldSpectral` (imaginary part zero), exactly as [`spectral_cutoff`](@ref) stores its `0/1`
mask.
"""
function squared_wavenumber_field(reference::AbstractFieldSpectral, multipliers::FieldSpectralMultipliers)
  _check_multipliers_compatibility(reference, multipliers)
  T = field_scalar_type(reference)
  result = similar_field(reference, Val(0))
  result_data = field_data(result)
  @_assign! result_data .= Complex{T}.(_squared_wavenumber_broadcast(multipliers))
  return result
end


"""
    spectral_band(reference::AbstractFieldSpectral, multipliers::FieldSpectralMultipliers, wavenumber_low, wavenumber_high)

Build the **isotropic sharp spectral band-pass** as a scalar field in spectral representation: the
transfer function `ĝ(k) = 1` for `wavenumber_low ≤ |k| ≤ wavenumber_high` and `0` otherwise, on
`reference`'s grid and array backend. The annular generalization of [`spectral_cutoff`](@ref) — which
is the low-pass special case `wavenumber_low = 0`. Convolving with it keeps an isotropic shell of
wavenumbers: a de-aliasing band, a forcing band (the energy held in `1 ≤ |k| ≤ k_f`), or any shell
selector. Idempotent (`ĝ² = ĝ`), so it is a projection.

A neutral mathematical primitive: the band edges are the consumer's. `|k|²` keeps the true value at
the Nyquist frequency (the Laplacian convention, invariant 5).
"""
function spectral_band(reference::AbstractFieldSpectral, multipliers::FieldSpectralMultipliers,
    wavenumber_low::Real, wavenumber_high::Real)
  _check_multipliers_compatibility(reference, multipliers)
  T = field_scalar_type(reference)
  kernel = similar_field(reference, Val(0))
  kernel_data = field_data(kernel)
  squared_wavenumber = _squared_wavenumber_broadcast(multipliers)
  low_squared = T(wavenumber_low)^2
  high_squared = T(wavenumber_high)^2
  @_assign! kernel_data .= ifelse.((squared_wavenumber .>= low_squared) .& (squared_wavenumber .<= high_squared),
                                   one(Complex{T}), zero(Complex{T}))
  return kernel
end


"""
    spectral_cutoff(reference::AbstractFieldSpectral, multipliers::FieldSpectralMultipliers, wavenumber_cutoff)

Build the **isotropic sharp spectral cutoff** as a scalar field in spectral representation: the
transfer function `ĝ(k) = 1` for `|k| ≤ wavenumber_cutoff` and `0` otherwise, on `reference`'s grid
and array backend. Convolving with it is the ideal low-pass projection (idempotent — `ĝ² = ĝ`), the
basis of spectral truncation and de-aliasing. The low-pass special case of [`spectral_band`](@ref)
(`wavenumber_low = 0`).

A neutral mathematical primitive: the choice of cutoff (e.g. a `2/3` de-aliasing rule, or an LES
filter scale) is the consumer's. The squared wavenumber `|k|²` is summed with the true value kept at
the Nyquist frequency (the Laplacian convention, invariant 5).
"""
function spectral_cutoff(reference::AbstractFieldSpectral, multipliers::FieldSpectralMultipliers,
    wavenumber_cutoff::Real)
  return spectral_band(reference, multipliers, zero(wavenumber_cutoff), wavenumber_cutoff)
end


end # module Convolution
