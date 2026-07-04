"""
    Convolution

Periodic (circular) convolution of a field with a kernel, computed in spectral representation. This
is the kernel-multiplier operation family — a grid→grid multiplier that filters a field against a
fixed kernel — the spectral sibling of the differential operators and the same-base counterpart of
`Interpolation`. On the torus the only convolution is the periodic one, and by the convolution
theorem it is exactly a coefficientwise product of the transforms, so the operation lives in spectral
representation. A kernel is supplied by its transfer function as a scalar field in spectral
representation, and a scalar kernel multiplies every fiber component, so one operation serves scalar,
vector, and tensor fields. The operation is named `convolve` (allocating infix `⋆`) rather than `*`,
because the coefficientwise product would read as a pointwise multiplication, which it is not.

Physics stays consumer-side: an LES filter, a viscous integrating factor, or a de-aliasing mask is a
scalar field in spectral representation that the consumer builds from `FieldSpectralMultipliers` and
convolves with — the package supplies the operation, not the physical meaning.

- [`convolve`](@ref) / [`convolve!`](@ref) — convolve a field with a kernel; the in-place form adds
  ``\\alpha``/``\\beta`` accumulation, and `convolve(g₁, g₂)` composes two kernels into one.
- [`spectral_cutoff`](@ref) / [`spectral_band`](@ref) — build the isotropic sharp low-pass kernel and
  its annular band-pass generalization.
- [`squared_wavenumber_field`](@ref) — the squared-wavenumber radial coordinate of spectral space, as
  a scalar field in spectral representation, from which a consumer builds a Fourier symbol.
- [`assignment_window`](@ref) — the linear (cloud-in-cell) mass-assignment window, for deconvolving a
  gridded point density.
"""
module Convolution

using ..Fields:
  AbstractFieldSpectral,
  ScalarFieldSpectral,
  FieldSpectralMultipliers,
  field_data,
  field_grid,
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

export convolve, convolve!, ⋆, spectral_cutoff, spectral_band, squared_wavenumber_field, assignment_window


####################################################
#        Convolution kernel                        #
####################################################


"""
    _apply_convolution!(destination_data, source_data, kernel_data, alpha, beta)

Apply the coefficientwise spectral product that realizes the periodic convolution in spectral
representation, writing ``\\mathrm{dst} \\mathrel{.=} \\alpha\\,\\hat g \\cdot \\hat f + \\beta\\,\\mathrm{dst}``
(``\\mathrm{dst}`` the `destination_data`, ``\\hat f`` the `source_data`, ``\\hat g`` = `kernel_data`).
The scalar `kernel_data`, of shape `(Nx, Ny, Nz)`, broadcasts over the fiber components of
`source_data` exactly as the Laplacian's ``|k|^2`` does, so one body serves every tensor order. The
call branches on `iszero(beta)` to overwrite or accumulate. The product is coefficientwise, so it is
aliasing-safe: `destination_data` may be `source_data` or the kernel.
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

Convolve `field` with the kernel whose transfer function is `kernel`, writing the result into
`destination` in place; both `field` and `destination` are in spectral representation.

As a real physical object the periodic convolution is the kernel-weighted local average of the field
``f`` about each point ``x`` — a low-pass filter when the kernel ``g`` is a smoothing bump:

```math
(f \\star g)(x) = \\int_\\Omega f(y)\\, g(x - y)\\, dy ,
```

with ``\\Omega`` the periodic box and the displacement ``x - y`` reduced onto the torus; on the grid
this is the circular sum ``(f \\star g)[n] = \\sum_m f[m]\\, g[n - m]`` with indices modulo the grid
size. By the convolution theorem (the forward transform unnormalized) it is exactly the
coefficientwise product of the transforms, which is what this operation computes — ``\\hat g`` =
`kernel`, broadcast over every fiber component of ``\\hat f``, with the ``\\alpha``/``\\beta``
accumulate:

```math
\\widehat{\\mathrm{destination}}(k) = \\alpha\\, \\hat f(k)\\, \\hat g(k) + \\beta\\, \\widehat{\\mathrm{destination}}(k).
```

- `field` — the field to filter, in spectral representation.
- `kernel` — the kernel's transfer function ``\\hat g``, a scalar field in spectral representation;
  one scalar kernel serves scalar, vector, and tensor `field`s.
- `destination` — the field written with the result; it may alias `field` or `kernel`, since the
  product is coefficientwise.
- `α`, `β` — real accumulation weights, converted to the field's scalar type; the three-argument form
  overwrites (``\\alpha = 1``, ``\\beta = 0``), the five-argument form computes
  ``\\alpha\\,(f \\star g) + \\beta\\,\\mathrm{destination}``.

Spectral representation only: on the torus convolution is the coefficientwise spectral product.
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

Allocate the result and return the periodic convolution of `field` with the kernel `kernel`, in
spectral representation. Because a kernel is itself a scalar field in spectral representation,
`convolve(g₁, g₂)` composes two kernels into one. See [`convolve!`](@ref) for the componentwise
definition and the spectral kernel; the representation and tensor order are preserved.
"""
function convolve end


function convolve(field::AbstractFieldSpectral, kernel::ScalarFieldSpectral)
  destination = similar_field(field, Val(field_tensor_order(field)))
  return convolve!(destination, field, kernel)
end


"""
    field ⋆ kernel

Infix alias for [`convolve`](@ref): `field ⋆ kernel` is `convolve(field, kernel)`, the periodic
convolution of `field` with the kernel `kernel` in spectral representation. Its own symbol keeps the
operation distinct from `*`, which would read as a pointwise product.
"""
const ⋆ = convolve


####################################################
#        Kernel builders                           #
####################################################


"""
    squared_wavenumber_field(reference::AbstractFieldSpectral,
                             multipliers::FieldSpectralMultipliers)

Return the squared wavenumber ``|k|^2`` at every mode as a scalar field in spectral representation, on
`reference`'s grid and array backend.

Use it as the neutral radial coordinate of spectral space: a consumer builds a Fourier symbol from it
— a viscous integrating factor ``\\exp(-\\nu |k|^2 \\Delta t)``, a smooth spectral envelope, or a
Germano subgrid filter — by broadcasting over its `field_data` and applying it with [`convolve`](@ref).
The package supplies the coordinate, while ``\\nu``, ``\\Delta t``, and any filter width stay
consumer-side.

- `reference` — a field in spectral representation whose grid and backend the result matches.
- `multipliers` — the wavenumber arrays for that grid, checked for compatibility with `reference`.

```math
|k|^2 = k_1^2 + k_2^2 + k_3^2 ,
```

summed with the true value kept at the Nyquist frequency (the Laplacian convention). The value is
real but is stored in the `Complex{T}` coefficient array of a scalar field in spectral representation,
its imaginary part zero, exactly as [`spectral_cutoff`](@ref) stores its ``0/1`` mask.
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
    spectral_band(reference::AbstractFieldSpectral, multipliers::FieldSpectralMultipliers,
                  wavenumber_low, wavenumber_high)

Build an isotropic sharp spectral band-pass kernel as a scalar field in spectral representation, on
`reference`'s grid and array backend: the transfer function is ``1`` on the wavenumber shell and
``0`` outside it.

Convolve a field with it to keep an isotropic shell of wavenumbers — a de-aliasing band, a forcing
band, or any shell selector. It is idempotent (``\\hat g^2 = \\hat g``), hence a projection, and it is
the annular generalization of [`spectral_cutoff`](@ref), which is the low-pass case
``k_\\mathrm{lo} = 0``.

- `reference` — a field in spectral representation whose grid and backend the kernel matches.
- `multipliers` — the wavenumber arrays for that grid, checked against `reference`.
- `wavenumber_low`, `wavenumber_high` — the inner and outer edges ``k_\\mathrm{lo}``,
  ``k_\\mathrm{hi}`` of the retained shell.

```math
\\hat g(k) = \\begin{cases} 1, & k_\\mathrm{lo} \\le |k| \\le k_\\mathrm{hi}, \\\\ 0, & \\text{otherwise,} \\end{cases}
```

with ``|k|^2`` keeping the true value at the Nyquist frequency (the Laplacian convention). The band
edges are the consumer's choice.
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
    spectral_cutoff(reference::AbstractFieldSpectral,
                    multipliers::FieldSpectralMultipliers, wavenumber_cutoff)

Build an isotropic sharp low-pass kernel as a scalar field in spectral representation, on
`reference`'s grid and array backend: the transfer function is ``1`` for ``|k| \\le k_c`` and ``0``
above it.

Convolve a field with it for the ideal low-pass projection, the basis of spectral truncation and
de-aliasing. It is idempotent (``\\hat g^2 = \\hat g``), hence a projection, and it is the low-pass
special case of [`spectral_band`](@ref) with ``k_\\mathrm{lo} = 0``.

- `reference` — a field in spectral representation whose grid and backend the kernel matches.
- `multipliers` — the wavenumber arrays for that grid, checked against `reference`.
- `wavenumber_cutoff` — the cutoff wavenumber ``k_c``; a mode is kept when ``|k| \\le k_c``.

```math
\\hat g(k) = \\mathbb 1\\!\\left[\\, |k| \\le k_c \\,\\right].
```

The choice of cutoff, such as a ``2/3`` de-aliasing rule or an LES filter scale, is the consumer's.
The squared wavenumber ``|k|^2`` keeps the true value at the Nyquist frequency (the Laplacian
convention).
"""
function spectral_cutoff(reference::AbstractFieldSpectral, multipliers::FieldSpectralMultipliers,
    wavenumber_cutoff::Real)
  return spectral_band(reference, multipliers, zero(wavenumber_cutoff), wavenumber_cutoff)
end


"""
    assignment_window(reference::AbstractFieldSpectral, multipliers::FieldSpectralMultipliers)

Return the linear (cloud-in-cell) mass-assignment window as a scalar field in spectral representation,
on `reference`'s grid and array backend, for deconvolving a gridded point density.

Use it in the pair-correlation route. Depositing ``M`` points on the grid with the positive linear
assignment (`LalescuSpline(0, 0)`, the 2-point linear kernel used for a density) spreads each point's
mass over a tent, so the gridded density is the true density ``\\rho`` convolved with this window,
``\\rho_g = \\rho \\star W``. Dividing the transform by ``\\hat W`` — a [`convolve`](@ref) by
``1/\\hat W`` — undoes that smearing before you estimate the radial distribution function.

- `reference` — a field in spectral representation whose grid and backend the window matches.
- `multipliers` — the wavenumber arrays for that grid, checked against `reference`.

As a real physical object ``W`` is the linear B-spline ("tent") cloud, the tensor product of per-axis
tents:

```math
W(x) = \\prod_{a=1}^{3} \\frac{1}{\\Delta x_a}\\,
       \\max\\!\\Bigl(0,\\; 1 - \\frac{|x_a|}{\\Delta x_a}\\Bigr),
```

each a tent of half-width one cell ``\\Delta x_a`` along axis ``a``, of unit integral and peaked at the
origin (a cell-wide top-hat convolved with itself, hence the squared sinc). The function returns its
transfer function ``\\hat W(k)``, the squared sinc

```math
\\begin{gathered}
\\hat W(k) = \\prod_{a=1}^{3} \\operatorname{sinc}^2\\!\\Bigl(\\tfrac{k_a \\Delta x_a}{2}\\Bigr), \\\\
\\operatorname{sinc}(y) = \\frac{\\sin y}{y},
\\end{gathered}
```

computed from the per-axis wavenumber ``k_a`` (kept at the Nyquist frequency) and the grid spacing
``\\Delta x_a``, so ``\\hat W(0) = 1`` and it decays toward the grid scale. Because the squared sinc
does not vanish anywhere in the resolved band, dividing by it is stable. The package supplies the
window; the density estimate and the correlation normalization stay consumer-side.
"""
function assignment_window(reference::AbstractFieldSpectral, multipliers::FieldSpectralMultipliers)
  _check_multipliers_compatibility(reference, multipliers)
  T = field_scalar_type(reference)
  spacing = field_grid(reference).grid_spacing
  # sinc²(|k_a| Δx_a / 2) per axis, GPU-safe (ifelse, not Base.sinc's branch); 1 at k_a = 0.
  axis(squared_wavenumber, Δ) =
    (y = sqrt.(squared_wavenumber) .* (T(Δ) / 2); ifelse.(iszero.(y), one(T), sin.(y) ./ y) .^ 2)
  w1 = reshape(axis(multipliers.squared_wavenumber_1, spacing[1]), :, 1, 1)
  w2 = reshape(axis(multipliers.squared_wavenumber_2, spacing[2]), 1, :, 1)
  w3 = reshape(axis(multipliers.squared_wavenumber_3, spacing[3]), 1, 1, :)
  window = similar_field(reference, Val(0))
  @_assign! field_data(window) .= Complex{T}.(w1 .* w2 .* w3)
  return window
end


end # module Convolution
