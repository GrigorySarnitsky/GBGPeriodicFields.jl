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

Physics stays consumer-side: kinetic energy ``\\tfrac12 \\langle u, u\\rangle``, enstrophy
``\\tfrac12 \\langle \\omega, \\omega\\rangle``, dissipation ``\\nu \\langle \\omega, \\omega\\rangle``,
rms ``\\sqrt{\\langle \\cdot, \\cdot\\rangle}``, intensities from `std`.
"""
module Reductions

using ..FiberSections: AbstractFiberSection, section_scalar_type
using ..Fields: AbstractFieldPhysical, AbstractFieldSpectral, FiberVector, FiberTensor2, field_data,
  field_grid, field_tensor_order, FieldSpectralMultipliers,
  _check_field_domain_compatibility, _check_multipliers_compatibility, _squared_wavenumber_broadcast
using ..Points: AbstractPointValues, npoints
import Statistics: mean, std, var
import Base: maximum, minimum, extrema
import LinearAlgebra

export integral, inner, l2norm, lpnorm, radial_spectrum


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

For a band-limited field the grid quadrature is exact (the periodic trapezoidal rule integrates the
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
transform. The rfft stores only ``k_x \\ge 0``, so each mode counts twice except the self-conjugate
``k_x = 0`` plane (and, for even ``N_x``, the Nyquist plane); the kernel forms a `dot` over the stored
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


"""
    radial_spectrum(f, multipliers)

The **radial (shell-binned) power spectrum** ``E(\\kappa)`` of a field `f` in spectral representation
(`radial_spectrum` ``\\equiv E(\\kappa)``): returns `(shells, spectrum)`, where `shells` are the
bin-center wavenumber magnitudes ``\\kappa`` and `spectrum[i]` sums the Parseval-weighted fiber energy
over the modes whose rounded magnitude falls in shell ``i``:

```math
E(\\kappa_i) = \\frac{1}{N^2} \\sum_{\\substack{k \\,:\\, \\mathrm{round}(|k|/\\Delta k) = i}} w(k) \\sum_c |\\hat f_c(k)|^2,
\\qquad
w(k) = \\begin{cases} 1, & k_x = 0 \\text{ or (even } N_x) \\ k_x = N_x/2, \\\\ 2, & \\text{otherwise,} \\end{cases}
```

with the rfft half-spectrum weight ``w`` and shell width ``\\Delta k`` (the box fundamental). It
**refines** [`inner`](@ref): ``\\sum_\\kappa E(\\kappa) = \\langle f, f\\rangle`` — the
total L² energy split across isotropic ``|k|``-shells of unit-fundamental width. The consumer's
kinetic-energy spectrum is then ``\\tfrac12 E(\\kappa)`` (so ``\\sum_\\kappa \\tfrac12 E(\\kappa) =
\\tfrac12\\langle |u|^2\\rangle``); the package keeps the neutral name, physics stays consumer-side.

Spectral representation only (a Parseval reduction, like the spectral `inner`). Shells run from ``0``
to the corner wavenumber, so the sum is over *all* modes (an exact `inner` refinement); on a de-aliased
field the high-``|k|`` shells are empty. For a non-cubic box the shells beyond ``\\min(N_i)/2`` are
incompletely sampled (only corner modes) — the standard isotropic-spectrum caveat — but
``\\sum_\\kappa E(\\kappa) = \\langle f, f\\rangle`` still holds. GPU-portable: the binning is a sequence
of masked reductions (no scalar indexing, no histogram kernel), suited to an occasional diagnostic
rather than a per-step call.
"""
function radial_spectrum(f::AbstractFieldSpectral{T}, multipliers::FieldSpectralMultipliers) where {T<:AbstractFloat}
  _check_multipliers_compatibility(f, multipliers)
  grid = field_grid(f)
  fundamental = 2 * T(π) / T(maximum(grid.domain_size))           # the unit shell width (= 1 for a 2π box)
  shell_index = round.(Int, sqrt.(_squared_wavenumber_broadcast(multipliers)) ./ fundamental)  # shell per mode
  number_of_shells = Int(maximum(shell_index)) + 1
  # Σ_c |f̂_c|² over the fiber, a real (Nkx, Ny, Nz) array (abs2 already drops the fiber for R = 0).
  R = field_tensor_order(f)
  fiber_dims = ntuple(d -> d + 3, R)
  magnitude_squared = R == 0 ? abs2.(field_data(f)) :
    dropdims(sum(abs2, field_data(f); dims = fiber_dims); dims = fiber_dims)
  weighted = _parseval_weight(f) .* magnitude_squared            # Parseval-weighted energy per mode
  normalization = T(prod(grid.grid_size))^2
  spectrum = T[sum(weighted .* (shell_index .== shell)) / normalization for shell in 0:(number_of_shells - 1)]
  shells = T.(0:(number_of_shells - 1)) .* fundamental
  return shells, spectrum
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
