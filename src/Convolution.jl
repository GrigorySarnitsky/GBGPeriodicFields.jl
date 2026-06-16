"""
    Convolution

The **kernel-multiplier** operation family (`docs/ARCHITECTURE.md` §2, decision 20): periodic
convolution of a field with a kernel, in spectral representation. It is the spectral sibling of the
differential operators and the same-base counterpart of `Interpolation` — both realize the "kernel
measure" of the measure taxonomy (decision 19); convolution is the grid→grid multiplier,
interpolation the grid↔point base-change.

On the torus the only convolution is the periodic (circular) one (`convolve` ``\\equiv \\star``). With
``\\Omega`` the periodic box, in physical space it is the **filtering integral**

```math
(f \\star g)(x) = \\int_\\Omega f(y)\\, g(x - y)\\, dy ,
```

the kernel-weighted local average of the field ``f`` about the point ``x`` (a low-pass filter when the
kernel ``g`` is a smoothing bump), with the displacement ``x - y`` reduced onto the torus; discretized on
the grid this is the circular sum over grid points ``(f \\star g)[n] = \\sum_m f[m]\\, g[n - m]``. By the
convolution theorem (the forward transform unnormalized, invariant 4) the convolution is *exactly* the
**coefficientwise spectral product** ``\\widehat{f \\star g} = \\hat f \\cdot \\hat g`` — one multiply per
coefficient, which is why `convolve` lives in spectral representation. The kernel `g` is supplied by its
transfer function ``\\hat g`` as a **scalar field in spectral representation** (`ScalarFieldSpectral`); a
scalar kernel multiplies every fiber component, so one operation serves scalar, vector, and tensor fields.

This coefficientwise product is exactly the operation invariant 1 names but bans **as `*`** (because
`*` would be read as the spectral *pointwise* product, which it is not). It is offered here under its
true name — `convolve`, never `*` — and is linear in the field for a fixed kernel. The pointwise
spectral product, division, and norms remain absent.

- `convolve(f, g)` / `convolve!` — the convolution ``f \\star g = \\mathcal F^{-1}(\\hat f \\cdot \\hat g)``,
  with the in-place and ``\\alpha``/``\\beta``-accumulate forms. Because a kernel is itself a scalar
  field in spectral representation, `convolve(g₁, g₂)` composes two kernels. Spectral representation only.
- `spectral_cutoff` / `spectral_band` — neutral kernel builders: the isotropic sharp low-pass
  ``\\hat g(k) = \\mathbb 1[\\,|k| \\le k_c\\,]`` (de-aliasing) and its annular generalization.
- `squared_wavenumber_field` — the radial coordinate ``|k|^2`` as a `ScalarFieldSpectral`.
- `assignment_window` — the linear/CIC mass-assignment window: the B-spline tent cloud ``W`` in physical space, returned as its transfer function ``\\hat W = \\prod_a \\operatorname{sinc}^2(k_a \\Delta x_a/2)``, divided out to deconvolve a gridded point density (decision 22).

Physics stays consumer-side: an LES filter, an integrating factor ``\\exp(-\\nu |k|^2 \\Delta t)``, or
a de-aliasing mask is a `ScalarFieldSpectral` the consumer builds from `FieldSpectralMultipliers` and
convolves with — the package supplies the operation, not the physical meaning (invariant 12).
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

export convolve, convolve!, spectral_cutoff, spectral_band, squared_wavenumber_field, assignment_window


####################################################
#        Convolution kernel                        #
####################################################


"""
    _apply_convolution!(destination_data, source_data, kernel_data, alpha, beta)

Apply the coefficientwise spectral product ``\\mathrm{dst} \\mathrel{.=} \\alpha\\,\\hat g \\cdot \\hat f
+ \\beta\\,\\mathrm{dst}`` (``\\mathrm{dst}`` the `destination_data`, ``\\hat f`` the `source_data`) — the
periodic convolution ``f \\star g`` in spectral representation, with
`kernel_data` ``= \\hat g``. The scalar `kernel_data` (`(Nx, Ny, Nz)`) broadcasts over the fiber
components of `source_data`, exactly as the Laplacian's ``|k|^2`` does, so one body serves every tensor
order. Branches on `iszero(beta)` (overwrite vs. accumulate, invariant 10). Coefficientwise ⇒
aliasing-safe: `destination` may be `source` (or the kernel).
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
writing into `destination` in-place. On the grid the periodic (circular) convolution
``(f \\star g)[n] = \\sum_m f[m]\\, g[n - m]`` (indices modulo the grid size) is, by the discrete
convolution theorem, **exactly** the coefficientwise product of the transforms — which is what the kernel computes (``\\hat g`` = `kernel`,
broadcast over every fiber component of ``\\hat f``, with the ``\\alpha``/``\\beta`` accumulate):

```math
\\widehat{f \\star g}(k) = \\hat f(k)\\, \\hat g(k),
\\qquad
\\widehat{\\mathrm{destination}}(k) = \\alpha\\, \\hat f(k)\\, \\hat g(k) + \\beta\\, \\widehat{\\mathrm{destination}}(k).
```

A scalar `kernel` serves scalar, vector, and tensor `field`s (one method); representation-preserving.
The three-argument form overwrites (``\\alpha = 1``, ``\\beta = 0``); ``\\alpha``, ``\\beta`` are real,
converted to the field's scalar type. Coefficientwise ⇒ aliasing-safe: `destination` may alias `field`
(or the kernel).

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

Allocate and return the periodic convolution of `field` with the kernel ``\\hat g`` = `kernel`, in
spectral representation — ``f \\star g``, the coefficientwise product ``\\hat f \\cdot \\hat g``.
Representation- and tensor-order-preserving. Because a kernel is itself a scalar field in spectral
representation, `convolve(g₁, g₂)` composes two kernels (the product ``\\hat g_1 \\cdot \\hat g_2`` of
their transfer functions). Spectral representation only.
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

The **squared-wavenumber field** as a scalar field in spectral representation, on `reference`'s grid
and array backend — the value at each mode is

```math
|k|^2 = k_1^2 + k_2^2 + k_3^2.
```

The neutral isotropic radial coordinate of
spectral space: the consumer builds a Fourier symbol from it — a viscous integrating factor
``\\exp(-\\nu |k|^2 \\Delta t)``, a smooth spectral envelope ``\\exp(-(|k|/k_p)^2)``, a Germano filter
``1/(1 + \\Delta^2 |k|^2)`` — by broadcasting over its `field_data`, then applies it with
[`convolve`](@ref). Carrying ``\\nu``, ``\\Delta t``, and the filter width is the consumer's
(invariant 12); the package supplies only the coordinate.

``|k|^2`` is summed with the true value kept at the Nyquist frequency (the Laplacian convention,
invariant 5). The value is real but stored in the `Complex{T}` coefficient array of a
`ScalarFieldSpectral` (imaginary part zero), exactly as [`spectral_cutoff`](@ref) stores its ``0/1``
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

Build the **isotropic sharp spectral band-pass** as a scalar field in spectral representation, on
`reference`'s grid and array backend — the transfer function (with `k_lo = wavenumber_low`,
`k_hi = wavenumber_high`)

```math
\\hat g(k) = \\mathbb 1\\!\\left[\\, k_\\mathrm{lo}^2 \\le |k|^2 \\le k_\\mathrm{hi}^2 \\,\\right]
= \\begin{cases} 1, & k_\\mathrm{lo} \\le |k| \\le k_\\mathrm{hi}, \\\\ 0, & \\text{otherwise.} \\end{cases}
```

The annular generalization of [`spectral_cutoff`](@ref) — which is the low-pass special case
``k_\\mathrm{lo} = 0``. Convolving with it keeps an isotropic shell of wavenumbers: a de-aliasing band,
a forcing band (the energy held in ``1 \\le |k| \\le k_f``), or any shell selector. Idempotent
(``\\hat g^2 = \\hat g``), so it is a projection.

A neutral mathematical primitive: the band edges are the consumer's. ``|k|^2`` keeps the true value at
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

Build the **isotropic sharp spectral cutoff** as a scalar field in spectral representation, on
`reference`'s grid and array backend — the transfer function (with `k_c = wavenumber_cutoff`)

```math
\\hat g(k) = \\mathbb 1\\!\\left[\\, |k| \\le k_c \\,\\right].
```

Convolving with it is the ideal low-pass projection (idempotent — ``\\hat g^2 = \\hat g``), the basis
of spectral truncation and de-aliasing. The low-pass special case
of [`spectral_band`](@ref) (``k_\\mathrm{lo} = 0``).

A neutral mathematical primitive: the choice of cutoff (e.g. a ``2/3`` de-aliasing rule, or an LES
filter scale) is the consumer's. The squared wavenumber ``|k|^2`` is summed with the true value kept
at the Nyquist frequency (the Laplacian convention, invariant 5).
"""
function spectral_cutoff(reference::AbstractFieldSpectral, multipliers::FieldSpectralMultipliers,
    wavenumber_cutoff::Real)
  return spectral_band(reference, multipliers, zero(wavenumber_cutoff), wavenumber_cutoff)
end


"""
    assignment_window(reference::AbstractFieldSpectral, multipliers::FieldSpectralMultipliers)

The **linear (cloud-in-cell, CIC) mass-assignment window** for **deconvolving** a gridded point density.
As a real physical object, ``W`` is the **linear B-spline ("tent") cloud** — the tensor product of
per-axis tents

```math
W(x) = \\prod_{a=1}^{3} \\frac{1}{\\Delta x_a}\\,
       \\max\\!\\Bigl(0,\\; 1 - \\frac{|x_a|}{\\Delta x_a}\\Bigr),
```

each a tent of half-width one cell ``\\Delta x_a`` along axis ``a``, of unit integral and peaked at the
origin ``x = 0`` (it is a cell-wide top-hat convolved with itself — hence the *squared* sinc below).
Depositing ``M`` points with a *positive* linear assignment (`LalescuSpline(n, 0)`, i.e. linear /
`m = 0`, the positive kernel decisions 19/22 recommend for a density) spreads each point's mass over this
tent, so the gridded density is the true density ``\\rho`` convolved with the window,
``\\rho_g = \\rho \\star W``. The function returns ``W`` in **spectral representation** — its transfer
function ``\\hat W(k)`` — because that is where the deconvolution lives: ``\\hat\\rho_g = \\hat W\\,\\hat\\rho``,
so dividing by ``\\hat W`` (a `convolve` by ``1/\\hat W``) undoes the smearing. ``\\hat W`` has no in-band
zeros for the positive linear kernel, so the division is stable. Its transform is the squared sinc

```math
\\hat W(k) = \\prod_{a=1}^{3} \\operatorname{sinc}^2\\!\\Bigl(\\tfrac{k_a \\Delta x_a}{2}\\Bigr),
\\qquad \\operatorname{sinc}(y) = \\frac{\\sin y}{y},
```

computed from the **true** per-axis wavenumber ``|k_a|`` (kept at the Nyquist frequency, invariant 5) and
the grid spacing ``\\Delta x_a``, so
``\\hat W(0) = 1`` and it falls toward the grid scale. This continuous-kernel form is the standard
particle-mesh deconvolution — exact as ``k \\to 0``, with the residual sub-cell shift-dependence
(reduced by interlacing) bounding it near Nyquist. The package supplies the window; the density
estimate, shot-noise subtraction, and the RDF normalization stay consumer-side (invariant 12 — the
worked pair-correlation recipe and its direct-pair-counting check are in `test/rdf.jl`).
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
