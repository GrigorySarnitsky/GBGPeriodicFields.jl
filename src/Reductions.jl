"""
    Reductions

The **L² / measure structure** on sections — the third operation family alongside the vertical
(fiberwise) algebra and the horizontal (differential) operators (`docs/ARCHITECTURE.md` §2,
decision 18). A reduction integrates a section over its **base**, against the measure the base
carries: `Grid3D`'s uniform quadrature (cell volume `∏Δxᵢ`) and `PointSet`'s **counting** measure
(unit weight per point — forced, since a `PointSet` is grid-free). One set of formulas serves
fields and point-values, dispatched on `AbstractFiberSection`.

Defined on **physical fields and point-values** — representation-free / physical-space quantities,
where the base reduction is the naive one. Spectral (Parseval) reductions are future.

- `integral(f)` — the **extensive** `∫ f dμ` (the only quantity that scales with the base measure):
  `(|Ω|/N)·Σf` on a grid, `Σf` over points.
- `mean(f)`, `std(f)`, `var(f)` — extend `Statistics`; **intensive** and **fiber-preserving**
  (`mean` of a vector field is a `FiberVector`). `mean(f) = (1/count)·Σf` — the arithmetic average
  over base elements: `(1/N)·Σ` on the grid (the domain average, the grid being uniform), `(1/M)·Σ`
  over points (a plain sample mean).
- `inner(f, g)` — the **normalized** L² inner product `⟨f,g⟩ = (1/count)·Σ f·g` → **scalar**
  (intensive, matching `mean`); `l2norm(f) = √inner(f,f)`, `lpnorm(f, p)` (`p = 2` default,
  `p = Inf` ⇒ sup of the fiber magnitude).
- `maximum`/`minimum`/`extrema` — extend `Base` for **scalar** sections.

Physics stays consumer-side: kinetic energy `½ inner(u,u)`, enstrophy `½ inner(ω,ω)`, dissipation
`ν inner(ω,ω)`, rms `√inner`, intensities from `std`.
"""
module Reductions

using ..FiberSections: AbstractFiberSection, section_scalar_type
using ..Fields: AbstractFieldPhysical, FiberVector, FiberTensor2, field_data, field_grid
using ..Points: AbstractPointValues, npoints
import Statistics: mean, std, var
import Base: maximum, minimum, extrema
import LinearAlgebra

export integral, inner, l2norm, lpnorm


# Physical fields and point-values: representation-free / physical-space sections whose base measure
# is the naive one. Spectral fields are deliberately excluded (their reduction is the Parseval one,
# future) even though they also subtype AbstractFiberSection.
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

The base integral `∫_Ω f dμ` of a section — **extensive** (scales with the base measure): the
uniform-quadrature `(|Ω|/N)·Σf` on a `Grid3D`, the counting-measure `Σf` over a `PointSet`.
Fiber-preserving: a scalar for a scalar section, a `FiberVector` for a vector section, a
`FiberTensor2` for a tensor section. Physical-space only; spectral integration is future.
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

The **normalized L² inner product** `⟨f, g⟩ = (1/count)·Σ f·g` of two compatible sections (full
fiber contraction summed over the base, divided by the base count) — a scalar, intensive (matching
`mean`). For homogeneous turbulence this is the natural pairing: kinetic energy is `½ inner(u, u)`.
Physical-space only (spectral, via Parseval, is future).
"""
function inner end
function inner(f::ReducibleSection, g::ReducibleSection)
  _base_count(f) == _base_count(g) ||
    throw(DimensionMismatch("sections have different base sizes: $(_base_count(f)) and $(_base_count(g))"))
  return LinearAlgebra.dot(field_data(f), field_data(g)) / _base_count(f)
end


"""
    l2norm(f)

The **normalized L² norm** `√inner(f, f) = √⟨|f|²⟩` of a section — the root-mean-square of the fiber
magnitude. The `p = 2` case of [`lpnorm`](@ref). Physical-space only.
"""
l2norm(section::ReducibleSection) = sqrt(inner(section, section))


"""
    lpnorm(f, p = 2)

The **normalized Lᵖ norm** `(⟨|f|ᵖ⟩)^{1/p}` of a section, where `|f|` is the pointwise fiber
magnitude (the vertical `norm`). `p = 2` reduces to [`l2norm`](@ref); `p = Inf` is the sup of the
fiber magnitude `‖f‖_∞` (e.g. the maximum speed for a CFL condition). Physical-space only.
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
