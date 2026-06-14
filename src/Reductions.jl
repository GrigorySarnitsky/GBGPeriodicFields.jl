"""
    Reductions

The **L² / measure structure** on sections — the third operation family alongside the vertical
(fiberwise) algebra and the horizontal (differential) operators (`docs/ARCHITECTURE.md` §2,
decision 18). A reduction integrates a section over its **base**, against the measure the base
carries: `Grid3D`'s uniform quadrature (cell volume ``\\prod_i \\Delta x_i``) and `PointSet`'s
**counting** measure (unit weight per point — forced, since a `PointSet` is grid-free). One set of
formulas serves fields and point-values, dispatched on `AbstractFiberSection`.

Defined on **physical fields and point-values** — representation-free / physical-space quantities,
where the base reduction is the naive one. `inner`/`l2norm` additionally act on fields in **spectral
representation** via Parseval (equal to the physical inner, no transform); `integral`/`mean`/`lpnorm`/
`maximum` stay physical-only.

- `integral(f)` — the **extensive** integral ``\\int_\\Omega f \\, d\\mu`` (the only quantity that
  scales with the base measure): ``\\tfrac{|\\Omega|}{N}\\sum_x f`` on a grid, ``\\sum_p f`` over points.
- `mean(f)`, `std(f)`, `var(f)` — extend `Statistics`; **intensive** and **fiber-preserving** (`mean`
  of a vector field is a `FiberVector`): the arithmetic average over base elements,
  ``\\tfrac1N\\sum_x f`` on the grid (the domain average, the grid being uniform) and
  ``\\tfrac1M\\sum_p f`` over points (a plain sample mean).
- `inner(f, g)` — the **normalized** L² inner product ``\\langle f, g\\rangle = \\tfrac1N\\sum_x f\\cdot g``
  → **scalar** (intensive, matching `mean`); ``\\mathrm{l2norm}(f) = \\sqrt{\\langle f, f\\rangle}``, and
  `lpnorm(f, p)` the ``L^p`` norm (``p = 2`` default, ``p = \\infty`` ⇒ the sup of the fiber magnitude).
- `maximum`/`minimum`/`extrema` — extend `Base` for **scalar** sections.

Two **radial reductions** resolve `inner` over a radial coordinate, a Fourier-dual pair (Wiener–Khinchin):
`radial_spectrum(f, multipliers)` bins ``|\\hat f|^2`` over ``|k|``-shells (the power spectrum, spectral
input), and `radial_correlation(f, plans)` is its physical-space dual, the shell-averaged two-point
autocorrelation ``C(r) = \\mathcal F^{-1}(|\\hat f|^2)/N``; both satisfy ``\\sum E = C(0) = \\mathrm{inner}(f, f)``.
Each also has a **two-field** form — the co-spectrum `radial_spectrum(f, g, multipliers)` (binning
``\\sum_c \\mathrm{Re}(\\hat f_c \\overline{\\hat g_c})``) and the cross-correlation `radial_correlation(f, g, plans)`
(``C_{fg}(r) = \\langle f(x)\\cdot g(x+r)\\rangle``, via ``\\overline{\\hat f}\\,\\hat g``) — refining the
mixed `inner(f, g)` (``\\sum E_{fg} = C_{fg}(0) = \\mathrm{inner}(f, g)``); the one-field forms are the ``g = f`` case.

Physics stays consumer-side: kinetic energy ``\\tfrac12 \\langle u, u\\rangle``, enstrophy
``\\tfrac12 \\langle \\omega, \\omega\\rangle``, dissipation ``\\nu \\langle \\omega, \\omega\\rangle``,
rms ``\\sqrt{\\langle \\cdot, \\cdot\\rangle}``, intensities from `std`.
"""
module Reductions

using ..FiberSections: AbstractFiberSection, section_scalar_type, _assign!, @_assign!
using ..Fields: AbstractFieldPhysical, AbstractFieldSpectral, FiberVector, FiberTensor2, field_data,
  field_grid, field_tensor_order, FieldSpectralMultipliers, FieldTransformPlans, to_physical,
  similar_field, _check_field_domain_compatibility, _check_multipliers_compatibility,
  _squared_wavenumber_broadcast
using ..Points: AbstractPointValues, npoints
import Statistics: mean, std, var
import Base: maximum, minimum, extrema
import LinearAlgebra

export integral, inner, l2norm, lpnorm, radial_spectrum, radial_correlation


# Physical fields and point-values: representation-free / physical-space sections whose base measure
# is the naive one. Spectral fields are excluded from ReducibleSection (the measure reductions are
# physical-only); the Parseval `inner`/`l2norm` are defined separately on AbstractFieldSpectral below.
const ReducibleSection = Union{AbstractFieldPhysical, AbstractPointValues}

_tensor_order(::AbstractFiberSection{T, R}) where {T, R} = R


###################################
#        The base measure         #
###################################
#
# `_base_count` — number of base elements (grid points N / particles M); the divisor for `mean`.
# `_cell_measure` — the per-element measure: a grid cell's volume, or 1 for the point counting
# measure. Their product is the total measure (|Ω| for a grid, M for points).

_base_count(field::AbstractFieldPhysical) = prod(field_grid(field).grid_size)
_base_count(values::AbstractPointValues) = npoints(values)

_cell_measure(field::AbstractFieldPhysical) = prod(field_grid(field).grid_spacing)
_cell_measure(::AbstractPointValues{T}) where {T} = one(T)


"""
    _fiberwise(section, whole_reduce, over_base_reduce)

Apply a reduction that **keeps the fiber and integrates the base away**, returning a fiber value:
a scalar for tensor order `0`, a `FiberVector` for `1`, a `FiberTensor2` for `2`. `whole_reduce(data)`
is used for the scalar case (reduce the whole array); `over_base_reduce(data, base_dims)` reduces only
the leading base dimensions for higher orders. The (tiny) reduced array is copied to the host before
the `SVector`/`SMatrix` build, so no device array is scalar-indexed (invariant 6).
"""
function _fiberwise(section::ReducibleSection, whole_reduce, over_base_reduce)
  T = section_scalar_type(section)
  data = field_data(section)
  R = _tensor_order(section)
  R == 0 && return whole_reduce(data)
  base = ntuple(identity, ndims(data) - R)
  reduced = Array(dropdims(over_base_reduce(data, base); dims = base))
  R == 1 && return FiberVector{T}(reduced)
  R == 2 && return FiberTensor2{T}(reduced)
  throw(ArgumentError("reductions are implemented for tensor order ≤ 2 (got R = $R)"))
end


###################################
#        Reductions               #
###################################


"""
    integral(f)

The base integral ``\\int_\\Omega f \\, d\\mu`` of a section (`integral` ``\\equiv \\int\\,d\\mu``) —
**extensive** (scales with the base measure). Computed as the measure-weighted sum over base elements
(the uniform quadrature on a `Grid3D`, the counting measure on a `PointSet`):

```math
\\int_\\Omega f \\, d\\mu = \\frac{|\\Omega|}{N} \\sum_{x} f(x) \\quad (\\texttt{Grid3D}),
\\qquad
\\sum_{p} f_p \\quad (\\texttt{PointSet}).
```

Here ``N`` is the number of base points (grid cells) and ``|\\Omega|`` the domain volume. For a band-limited field the grid quadrature is exact (the periodic trapezoidal rule integrates the
represented modes exactly). Fiber-preserving: a scalar for a scalar section, a `FiberVector` for a
vector section, a `FiberTensor2` for a tensor section. Physical-space only; spectral integration is future.
"""
function integral end
integral(section::ReducibleSection) =
  _fiberwise(section, sum, (data, base) -> sum(data; dims = base)) .* _cell_measure(section)


# `mean`, `std`, `var` (extending Statistics) — intensive, fiber-preserving base reductions.
# `mean(f) = (1/count)·Σf`: the arithmetic average over base elements (a plain sample mean over
# points). `std`/`var` are the per-fiber-component base moments.
mean(section::ReducibleSection) = _fiberwise(section, mean, (data, base) -> mean(data; dims = base))

var(section::ReducibleSection; corrected::Bool = true) =
  _fiberwise(section, data -> var(data; corrected = corrected),
             (data, base) -> var(data; dims = base, corrected = corrected))

std(section::ReducibleSection; corrected::Bool = true) =
  _fiberwise(section, data -> std(data; corrected = corrected),
             (data, base) -> std(data; dims = base, corrected = corrected))


"""
    inner(f, g)

The **normalized L² inner product** of two compatible sections (`inner` ``\\equiv \\langle\\cdot,\\cdot\\rangle``)
— the full fiber contraction ``f \\cdot g`` summed over the base and divided by the base count ``N``; a
scalar, intensive (matching `mean`). Computed as

```math
\\langle f, g\\rangle = \\frac1N \\sum_x f(x) \\cdot g(x).
```

For homogeneous turbulence this is the natural pairing: kinetic energy is ``\\tfrac12\\langle u, u\\rangle``.

For two fields in **spectral representation** the same value is computed by Parseval, without an inverse
transform. The rfft stores only ``k_x \\ge 0``, so each mode counts twice except those on the
``k_x = 0`` plane (and, for even ``N_x``, the Nyquist plane) — the planes the rfft maps to themselves
under conjugation, whose partners are already stored, so they count once; the kernel forms a `dot` over the stored
coefficients and subtracts those planes:

```math
\\langle f, g\\rangle = \\frac{1}{N^2}\\,\\mathrm{Re}\\!\\left(
2 \\sum_{k_x \\ge 0} \\hat f(k)\\, \\overline{\\hat g(k)}
\\;-\\; \\sum_{k_x = 0} \\hat f\\, \\overline{\\hat g}
\\;-\\; \\sum_{k_x = N_x/2} \\hat f\\, \\overline{\\hat g}
\\right),
```

with the last (Nyquist) sum present only for even ``N_x``, and ``N = \\prod_i N_i``. `lpnorm`, `integral`,
`mean`, `maximum` remain physical-only (only the ``p = 2`` inner is representation-invariant).
"""
function inner end
function inner(f::ReducibleSection, g::ReducibleSection)
  _base_count(f) == _base_count(g) ||
    throw(DimensionMismatch("sections have different base sizes: $(_base_count(f)) and $(_base_count(g))"))
  return LinearAlgebra.dot(field_data(f), field_data(g)) / _base_count(f)
end


# Spectral (Parseval) inner product. For real fields the normalized physical inner ⟨f,g⟩ =
# (1/N)·Σₓ dot(f,g) equals, by Parseval, a weighted sum over the rfft coefficients. The rfft stores
# only kₓ ≥ 0, so each mode counts twice (it stands for itself and its unstored conjugate partner)
# EXCEPT the self-conjugate kₓ=0 plane and — when Nₓ is even — the Nyquist plane, which count once.
# With Sₜ = Σ_stored Σ_c f̂_c conj(ĝ_c) = dot(ĝ, f̂):
#   ⟨f,g⟩ = Re(2·Sₜ − S_{kₓ=0} − S_{Nyquist}) / N²,   N = prod(grid_size)   (Nyquist term: even Nₓ only)
# computed allocation-free as `dot` over the whole array and its two correction planes (views), the
# real part discarding the round-off imaginary part of the (provably real) full-spectrum sum.
function inner(f::AbstractFieldSpectral{T}, g::AbstractFieldSpectral{T}) where {T<:AbstractFloat}
  _check_field_domain_compatibility(f, g)
  data_f = field_data(f)
  data_g = field_data(g)
  total = LinearAlgebra.dot(data_g, data_f)                       # Σ_stored f̂ conj(ĝ) (contiguous ⇒ BLAS dot)
  # The self-conjugate kₓ=0 plane (and the Nyquist plane for even Nₓ) are counted once, not twice;
  # subtract them. A `dot` over a strided slice is unsupported on the GPU (rocBLAS `dotc`), so reduce a
  # broadcast instead — each plane is a single kₓ index, a negligible allocation.
  plane(i) = sum(conj.(selectdim(data_g, 1, i)) .* selectdim(data_f, 1, i))
  correction = plane(1)
  iseven(field_grid(f).grid_size[1]) && (correction += plane(size(data_f, 1)))
  return real(2 * total - correction) / T(prod(field_grid(f).grid_size))^2
end


"""
    l2norm(f)

The **normalized L² norm** ``\\lVert f\\rVert_2 = \\sqrt{\\langle f, f\\rangle} = \\sqrt{\\langle |f|^2\\rangle}``
of a section (`l2norm` ``\\equiv \\lVert\\cdot\\rVert_2``) — the root-mean-square of the fiber magnitude
``|f|``. The ``p = 2`` case of [`lpnorm`](@ref). Defined for physical fields and point-values, and — via
the Parseval [`inner`](@ref) — for a field in spectral representation.
"""
l2norm(section::ReducibleSection) = sqrt(inner(section, section))
l2norm(f::AbstractFieldSpectral) = sqrt(inner(f, f))


# The rfft half-spectrum Parseval weight, as a (Nkx, 1, 1) array on the field's backend so it
# broadcasts over the spectral coefficients: each stored mode counts twice (it stands for its unstored
# conjugate partner) EXCEPT the self-conjugate kₓ=0 plane and — for even Nₓ — the Nyquist plane, which
# count once. The tiny host vector is built then bulk-copied to the device (no scalar indexing of
# device memory, invariant 6). Same weighting as the spectral `inner` above, here per mode.
function _parseval_weight(f::AbstractFieldSpectral{T}) where {T<:AbstractFloat}
  number_of_kx = size(field_data(f), 1)
  weight_host = fill(T(2), number_of_kx)
  weight_host[1] = T(1)
  iseven(field_grid(f).grid_size[1]) && (weight_host[number_of_kx] = T(1))
  weight_device = similar(field_data(f), T, number_of_kx)
  copyto!(weight_device, weight_host)
  return reshape(weight_device, number_of_kx, 1, 1)
end


# Shared |k|-shell binning for the power/cross-power spectra. `per_mode_quantity` is the fiber-contracted
# real density — ``Σ_c |f̂_c|²`` (power) or ``Σ_c Re(f̂_c conj ĝ_c)`` (cross) — an (Nkx, Ny, Nz) array.
# Apply the rfft Parseval weight, normalize by N², and sum the modes whose rounded |k| falls in each
# shell; shells run 0…corner at the box-fundamental width, so ∑ over shells = the spectral `inner` exactly.
function _radial_spectrum_bin(f::AbstractFieldSpectral{T}, multipliers::FieldSpectralMultipliers,
                              per_mode_quantity) where {T<:AbstractFloat}
  _check_multipliers_compatibility(f, multipliers)
  grid = field_grid(f)
  fundamental = 2 * T(π) / T(maximum(grid.domain_size))           # the unit shell width (= 1 for a 2π box)
  shell_index = round.(Int, sqrt.(_squared_wavenumber_broadcast(multipliers)) ./ fundamental)  # shell per mode
  number_of_shells = Int(maximum(shell_index)) + 1
  weighted = _parseval_weight(f) .* per_mode_quantity            # Parseval-weighted (co-)energy per mode
  normalization = T(prod(grid.grid_size))^2
  spectrum = T[sum(weighted .* (shell_index .== shell)) / normalization for shell in 0:(number_of_shells - 1)]
  shells = T.(0:(number_of_shells - 1)) .* fundamental
  return shells, spectrum
end


"""
    radial_spectrum(f, multipliers)
    radial_spectrum(f, g, multipliers)

The **radial (shell-binned) spectrum** of a field in spectral representation: the one-argument form is
the **power spectrum** ``E(\\kappa)`` (`radial_spectrum` ``\\equiv E(\\kappa)``); the two-argument form is
the **co-spectrum** (cross-power) ``E_{fg}(\\kappa)`` of two compatible, equal-order fields. Returns
`(shells, spectrum)`, where `shells` are the bin-center wavenumber magnitudes ``\\kappa`` and `spectrum[i]`
sums the Parseval-weighted fiber (co-)energy over the modes whose rounded magnitude falls in shell ``i``:

```math
E(\\kappa_i) = \\frac{1}{N^2} \\sum_{\\substack{k \\,:\\, \\mathrm{round}(|k|/\\Delta k) = i}} \\alpha(k) \\sum_c |\\hat f_c(k)|^2,
\\qquad
E_{fg}(\\kappa_i) = \\frac{1}{N^2} \\sum_{\\substack{k \\,:\\, \\mathrm{round}(|k|/\\Delta k) = i}} \\alpha(k) \\sum_c \\mathrm{Re}\\!\\bigl(\\hat f_c(k)\\,\\overline{\\hat g_c(k)}\\bigr),
```

with ``c`` indexing the fiber components, ``\\alpha(k)`` the rfft half-spectrum Parseval weight (``1`` on the
``k_x = 0`` and even-``N_x`` Nyquist planes, ``2`` otherwise), and shell width ``\\Delta k`` (the box
fundamental). Each **refines** [`inner`](@ref):
``\\sum_\\kappa E(\\kappa) = \\langle f, f\\rangle`` and ``\\sum_\\kappa E_{fg}(\\kappa) = \\langle f, g\\rangle``
— the L² (co-)energy split across isotropic ``|k|``-shells of unit-fundamental width. The one-argument
form is the ``g = f`` case (``\\mathrm{Re}(\\hat f\\,\\overline{\\hat f}) = |\\hat f|^2``); the co-spectrum
is **symmetric** (``E_{fg} = E_{gf}``, ``\\mathrm{Re}`` being conjugation-symmetric) and, unlike the power
spectrum, **may be negative** in a shell (anticorrelated modes). The consumer's kinetic-energy spectrum is
``\\tfrac12 E(\\kappa)``; the package keeps the neutral name, physics stays consumer-side.

Spectral representation only (a Parseval reduction, like the spectral `inner`). Shells run from ``0``
to the corner wavenumber, so the sum is over *all* modes (an exact `inner` refinement); on a de-aliased
field the high-``|k|`` shells are empty. For a non-cubic box the shells beyond ``\\min(N_i)/2`` are
incompletely sampled (only corner modes) — the standard isotropic-spectrum caveat — but the total still
equals `inner`. GPU-portable: the binning is a sequence of masked reductions (no scalar indexing, no
histogram kernel), suited to an occasional diagnostic rather than a per-step call.
"""
function radial_spectrum end

function radial_spectrum(f::AbstractFieldSpectral{T}, multipliers::FieldSpectralMultipliers) where {T<:AbstractFloat}
  # Σ_c |f̂_c|² over the fiber, a real (Nkx, Ny, Nz) array (abs2 already drops the fiber for R = 0).
  R = field_tensor_order(f)
  fiber_dims = ntuple(d -> d + 3, R)
  magnitude_squared = R == 0 ? abs2.(field_data(f)) :
    dropdims(sum(abs2, field_data(f); dims = fiber_dims); dims = fiber_dims)
  return _radial_spectrum_bin(f, multipliers, magnitude_squared)
end

function radial_spectrum(f::AbstractFieldSpectral{T}, g::AbstractFieldSpectral{T},
                         multipliers::FieldSpectralMultipliers) where {T<:AbstractFloat}
  _check_field_domain_compatibility(f, g)
  field_tensor_order(f) == field_tensor_order(g) ||
    throw(ArgumentError("radial_spectrum(f, g, multipliers) needs equal tensor orders " *
                        "(got $(field_tensor_order(f)) and $(field_tensor_order(g)))"))
  # Σ_c Re(f̂_c · conj(ĝ_c)) over the fiber, the real co-energy density per mode (an (Nkx, Ny, Nz) array).
  R = field_tensor_order(f)
  fiber_dims = ntuple(d -> d + 3, R)
  cross_density = real.(field_data(f) .* conj.(field_data(g)))
  cross_power = R == 0 ? cross_density : dropdims(sum(cross_density; dims = fiber_dims); dims = fiber_dims)
  return _radial_spectrum_bin(f, multipliers, cross_power)
end


# Minimum-image separation magnitude ``|r|`` at each grid point, as an (Nx, Ny, Nz) array on the
# field's backend: along axis a the separation index is `min(i, Nₐ − i)`, scaled by the spacing `Δxₐ`,
# so distances fold at the half-box (the autocorrelation is periodic and even). Built per-axis on the
# host then bulk-copied to the backend (no scalar indexing of device memory), like `_parseval_weight`.
function _separation_magnitude(grid, backend_reference::AbstractArray{T}) where {T}
  axis_distance(a) = begin
    n = grid.grid_size[a]
    spacing = T(grid.grid_spacing[a])
    host = T[min(i, n - i) * spacing for i in 0:(n - 1)]
    device = similar(backend_reference, T, n)
    copyto!(device, host)
    return reshape(device, ntuple(d -> d == a ? n : 1, 3))
  end
  d1, d2, d3 = axis_distance(1), axis_distance(2), axis_distance(3)
  return sqrt.(d1 .^ 2 .+ d2 .^ 2 .+ d3 .^ 2)
end


# Inverse-transform a per-component complex spectrum (already written into the spectral field `power`)
# into the real two-point correlation field: c2r per component, fiber-contract, normalize by N. The
# per-component cross spectrum conj(f̂_c)·ĝ_c (and its g = f case |f̂_c|²) is Hermitian for real f, g, so
# the c2r reconstruction is exactly real even though the cross-correlation itself is not even in r.
function _correlation_field_from(power::AbstractFieldSpectral{T}, plans::FieldTransformPlans) where {T<:AbstractFloat}
  number_of_points = prod(field_grid(power).grid_size)
  tensor_order = field_tensor_order(power)
  autocorrelation = to_physical(power, plans)                    # c2r per component (unnormalized correlation)
  data = field_data(autocorrelation)
  fiber_dims = ntuple(d -> d + 3, tensor_order)
  return (tensor_order == 0 ? data : dropdims(sum(data; dims = fiber_dims); dims = fiber_dims)) ./ T(number_of_points)
end


# Radially average a real physical (Nx, Ny, Nz) correlation field over minimum-image |r| shells (bin
# width = the finest grid spacing) — the shared back half of both `radial_correlation` methods. The
# ±r folding of the min-image shells symmetrizes the cross-correlation (C_fg(−r) = C_gf(r)).
function _radial_average(grid, correlation_field::AbstractArray{T}) where {T<:AbstractFloat}
  separation = _separation_magnitude(grid, correlation_field)
  bin_width = T(minimum(grid.grid_spacing))
  shell_index = round.(Int, separation ./ bin_width)
  number_of_shells = Int(maximum(shell_index)) + 1
  separations = T.(0:(number_of_shells - 1)) .* bin_width
  correlation = zeros(T, number_of_shells)
  for shell in 0:(number_of_shells - 1)
    in_shell = shell_index .== shell
    population = sum(in_shell)                      # number of grid points in this |r| shell
    correlation[shell + 1] = iszero(population) ? zero(T) : sum(correlation_field .* in_shell) / population
  end
  return separations, correlation
end


"""
    radial_correlation(f, plans)
    radial_correlation(f, g, plans)

The **radial (shell-averaged) two-point correlation** of a field — the physical-space Wiener–Khinchin
dual of [`radial_spectrum`](@ref). The one-argument form is the **autocorrelation** ``C(r)``; the
two-argument form is the **cross-correlation** ``C_{fg}(r) = \\langle f(x)\\cdot g(x+r)\\rangle`` of two
compatible, equal-order fields. `f` (and `g`) are in spectral representation; `plans` are their transform
plans (matching the tensor order). Returns `(separations, correlation)`, where `separations` are the
bin-center magnitudes ``r`` and `correlation[i]` is the value averaged over the minimum-image shell
``|r| \\approx r``. By the (cross-)correlation theorem the kernel forms the fiber-summed (cross-)power
spectrum, inverse-transforms it, and normalizes:

```math
C(r) = \\frac1N \\sum_x f(x)\\cdot f(x+r) = \\frac1N\\,\\mathcal F^{-1}\\!\\Bigl(\\textstyle\\sum_c |\\hat f_c|^2\\Bigr)(r),
\\qquad
C_{fg}(r) = \\frac1N \\sum_x f(x)\\cdot g(x+r) = \\frac1N\\,\\mathcal F^{-1}\\!\\Bigl(\\textstyle\\sum_c \\overline{\\hat f_c}\\,\\hat g_c\\Bigr)(r),
```

followed by the shell average ``C(r_i) = |\\text{shell } i|^{-1} \\sum_{|r| \\approx r_i} C(r)``. At zero
separation each is [`inner`](@ref): ``C(0) = \\langle |f|^2\\rangle = \\mathrm{inner}(f, f)`` and
``C_{fg}(0) = \\langle f\\cdot g\\rangle = \\mathrm{inner}(f, g)`` — `inner` resolved over physical
separation exactly as `radial_spectrum` resolves it over ``|k|`` (a Fourier pair: ``\\mathcal F C = |\\hat f|^2``,
``\\mathcal F C_{fg} = \\overline{\\hat f}\\,\\hat g``). The one-argument form is the ``g = f`` case; the
radial binning **symmetrizes** the cross-correlation — the ``\\pm r`` folding of the min-image shells
averages ``C_{fg}(r)`` with ``C_{fg}(-r) = C_{gf}(r)``, so the result equals ``\\tfrac12(C_{fg} + C_{gf})``
and is symmetric in ``f, g``. Spectral input only (it needs the inverse transform); GPU-portable (one
inverse rfft + masked-reduction binning, no scalar indexing).
"""
function radial_correlation end

function radial_correlation(f::AbstractFieldSpectral{T}, plans::FieldTransformPlans) where {T<:AbstractFloat}
  # Power spectrum per fiber component, |f̂_c(k)|² (real, in the complex coefficient array).
  power = similar_field(f, Val(field_tensor_order(f)))
  @_assign! field_data(power) .= complex.(abs2.(field_data(f)))
  return _radial_average(field_grid(f), _correlation_field_from(power, plans))
end

function radial_correlation(f::AbstractFieldSpectral{T}, g::AbstractFieldSpectral{T},
                            plans::FieldTransformPlans) where {T<:AbstractFloat}
  _check_field_domain_compatibility(f, g)
  field_tensor_order(f) == field_tensor_order(g) ||
    throw(ArgumentError("radial_correlation(f, g, plans) needs equal tensor orders " *
                        "(got $(field_tensor_order(f)) and $(field_tensor_order(g)))"))
  # Cross-power spectrum per fiber component, conj(f̂_c)·ĝ_c (Hermitian for real f, g ⇒ c2r is real).
  power = similar_field(f, Val(field_tensor_order(f)))
  @_assign! field_data(power) .= conj.(field_data(f)) .* field_data(g)
  return _radial_average(field_grid(f), _correlation_field_from(power, plans))
end


"""
    lpnorm(f, p = 2)

The **normalized Lᵖ norm** of a section (`lpnorm` ``\\equiv \\lVert\\cdot\\rVert_p``), where ``|f|`` is
the pointwise fiber magnitude (the vertical `norm`). Computed as

```math
\\lVert f\\rVert_p = \\Bigl(\\frac1N \\sum_x |f(x)|^p\\Bigr)^{1/p},
\\qquad
\\lVert f\\rVert_\\infty = \\max_x |f(x)|.
```

``p = 2`` reduces to [`l2norm`](@ref); ``p = \\infty`` is the sup of the fiber magnitude (e.g. the
maximum speed for a CFL condition). Physical-space only.
"""
function lpnorm(section::ReducibleSection, p::Real = 2)
  p == 2 && return l2norm(section)
  magnitude = field_data(LinearAlgebra.norm(section))      # pointwise fiber magnitude (vertical norm)
  isinf(p) && return maximum(magnitude)
  return (sum(magnitude .^ p) / _base_count(section))^(1 / p)
end


# `maximum`/`minimum`/`extrema` (extending Base) — the L∞ end, for scalar sections only (the sup of a
# vector/tensor magnitude is `lpnorm(f, Inf)`, deliberately not an ambiguous `maximum` of components).
for reducer in (:maximum, :minimum, :extrema)
  @eval $reducer(field::AbstractFieldPhysical{T, 0}) where {T} = $reducer(field_data(field))
  @eval $reducer(values::AbstractPointValues{T, 0}) where {T} = $reducer(field_data(values))
end


end # module Reductions
