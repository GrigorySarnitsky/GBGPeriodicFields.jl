"""
    Reductions

The **L² / measure structure** on sections — the third operation family, alongside the fiberwise algebra
and the differential operators. Periodic convolution and the grid↔point transfer belong to this same
family, as two further roles of the one integration structure. A reduction integrates a section over
its **base** against the measure the base carries — the extensive one for `integral`, its
total-mass-one normalization for the intensive reductions: a `Grid3D` uses its uniform quadrature (the cell
volume), and a `PointSet` uses its **counting** measure (unit weight per point,
forced because a `PointSet` is grid-free). One set of formulas serves both fields and point-values,
dispatched on `AbstractFiberSection`.

The measure reductions act on **fields in physical representation and point-values** — representation-free, physical-space
quantities. Several also act on fields in **spectral representation**, returning the identical physical
value with no inverse transform: `inner`/`l2norm` by Parseval's theorem, `integral`/`mean` from the
zero (DC) Fourier mode, and the scalar-only `std`/`var` from Parseval. The remaining reductions (`lpnorm`, `cov`, `maximum`/`minimum`/`extrema`)
stay physical-only.

The parts are, each linking to the home where its formula lives.

!!! note "The moments extend `Statistics`; the order statistics extend `Base`"
    `mean`, `std`, `var` and `cov` **extend** `Statistics` rather than being owned here, and
    `maximum`, `minimum` and `extrema` extend `Base`. Either way they are used exactly as their
    standard-library counterparts are, and `using GBGPeriodicFields` alone puts all of them in scope:
    the umbrella re-exports the four `Statistics` generics, as it does `dot` and `norm` from
    `LinearAlgebra`, so a caller need not know which standard library a reduction's verb lives in.


- [`integral`](@ref) — the **extensive** integral, the one quantity that scales with the base measure.
- [`mean`](@ref) — the **intensive**, **fiber-preserving** arithmetic average over the ``N`` grid cells or
  the ``M`` points (it extends `Statistics`; the `mean` of a vector field is a `FiberVector`).
- [`std`](@ref), [`var`](@ref), [`cov`](@ref) — the base moments (extending `Statistics`, `corrected = true`
  by default). The `std` and `var` reductions are **scalar-only**: the sample standard deviation and variance
  are unambiguous
  only for a scalar section. The coordinate-free second moment of a **vector** field is the covariance
  tensor `cov` ``\\equiv R`` with entries ``R_{ij} = \\langle u'_i u'_j\\rangle`` (a symmetric `FiberTensor2`), of which a
  per-component variance would be only the basis-dependent diagonal.
- [`inner`](@ref) — the **normalized** L² inner product ``\\langle\\cdot,\\cdot\\rangle``, a scalar that
  averages the fiber contraction over the ``N`` grid cells or the ``M`` points. [`l2norm`](@ref) and
  [`lpnorm`](@ref) are the norms derived from it, and [`weighted_inner`](@ref) is its spectral
  generalization, weighting the pairing by a kernel multiplier.
- [`maximum`](@ref), [`minimum`](@ref), [`extrema`](@ref) — the ``L^\\infty`` end, extending `Base`. The bare forms take a
  scalar section; the mapped forms below lift that restriction for any order the reductions serve
  (``R \\le 2``: scalar, vector and second-order tensor sections are the supported surface, and a
  fiber-preserving reduction raises above it rather than returning a wrong answer).
- The **mapped forms** — `integral`, `mean`, `maximum`, `minimum` and `extrema` also accept a leading function, applied to the fiber
  value at every base point: `mean(det, A)` averages a determinant over the base and
  `maximum(norm, u)` takes a supremum of magnitude, each in a single pass that never builds the mapped
  quantity as a section. Naming that map is also what makes an order statistic well posed on a vector
  or tensor section, where the bare `maximum` refuses to guess. They mirror the standard-library
  `mean(f, itr)` and `maximum(f, itr)` spellings and, mapping the fiber nonlinearly, are physical-only.
- [`radial_spectrum`](@ref) and [`radial_correlation`](@ref) — a Fourier-dual pair (Wiener–Khinchin)
  that resolves `inner` over a radial coordinate, the shell-binned power spectrum over ``|k|`` and its
  physical-space two-point correlation over ``|r|``, each also in a two-field co-spectrum form.

Physics stays consumer-side: the consumer builds kinetic energy, enstrophy, dissipation, rms, and
turbulence intensities from these reductions.
"""
module Reductions

using ..FiberSections: AbstractFiberSection, section_scalar_type, section_tensor_order,
  _assign!, @_assign!, _use_threads
using ..Fields: _spectral_zero_mode_data, _spectral_zero_mode_component_data,
  _spectral_constant_scale, AbstractFieldPhysical, AbstractFieldSpectral, ScalarFieldSpectral, VectorFieldSpectral,
  TensorFieldSpectral, FiberVector, FiberTensor2, field_data,
  field_grid, field_layout, field_tensor_order, FieldSpectralMultipliers, FieldTransformPlans, to_physical,
  similar_field, _check_field_domain_compatibility, _check_multipliers_compatibility,
  _squared_wavenumber_broadcast, _vector_component_data, _tensor2_component_data,
  _same_backend, _storage_family
using ..Points: AbstractPointValues, npoints
# Every kernel class may serve as a weight: each one's `_kernel_data` is an instantiated broadcastable,
# and the fused pass below never asks which class it holds. The former Union{StoredKernel, RadialKernel}
# was a signature written narrowly rather than a constraint — measured bitwise-identical across all four
# before it was widened. (Two rationales for the old restriction were recorded over time and BOTH were
# wrong: that separable factors are not real in general, contradicted by assignment_window's sinc^2; and
# that a magnitude-dependent weight does not factor per axis, which argues about the radial class that
# WAS accepted rather than the separable one that was not. Do not invent a third.)
using ..Convolution: RadialKernel, StoredKernel, SeparableKernel, ProductKernel
using ..Fields: _kernel_data, _check_kernel_compatibility, SpectralKernel
using KernelAbstractions: @kernel, @index, @Const, get_backend, synchronize
import KernelAbstractions
import Atomix
import Statistics: mean, std, var, cov
import Base: maximum, minimum, extrema
import LinearAlgebra

export integral, inner, weighted_inner, l2norm, lpnorm, radial_spectrum, radial_correlation


# Physical fields and point-values: representation-free / physical-space sections whose base measure
# is the naive one. Fields in spectral representation are excluded from ReducibleSection: they carry only the reductions
# that have a spectral form — the Parseval `inner`/`l2norm` and the zero-mode `integral`/`mean` — each
# defined separately on AbstractFieldSpectral below.
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
_cell_measure(field::AbstractFieldSpectral) = prod(field_grid(field).grid_spacing)
_cell_measure(::AbstractPointValues{T}) where {T} = one(T)


# DISPATCHED on the tensor order, not branched on it. The three arms return a scalar, a `FiberVector`
# and a `FiberTensor2`, so a runtime `R` left the result inferring as `Any` — and that propagated to
# every fiber-preserving reduction built on it, `mean` and `cov` among them. `R` is a type parameter of
# the section, so `Val` recovers it at compile time and each arm infers concretely.
# `Val(_tensor_order(section))` is NOT enough: `_tensor_order` returns the type parameter as an `Int`,
# and inference reports `Int64` rather than a constant, so the `Val` is built dynamically and the
# dispatch stays dynamic. Taking `R` straight off the section's own type in the signature makes it a
# compile-time parameter, which is what the arms below need.
"""
    _fiberwise(section, whole_reduce, over_base_reduce)

Apply a reduction that **keeps the fiber and integrates the base away**, returning a fiber value:
a scalar for tensor order `0`, a `FiberVector` for `1`, a `FiberTensor2` for `2`. The `whole_reduce(data)` helper
is used for the scalar case (reduce the whole array); `over_base_reduce(data, base_dims)` reduces only
the leading base dimensions for higher orders. The (tiny) reduced array is copied to the host before
the `SVector`/`SMatrix` build, so no device array is scalar-indexed.
"""
_fiberwise(section::AbstractFiberSection{T, R}, whole_reduce, over_base_reduce) where {T, R} =
  _fiberwise(section, whole_reduce, over_base_reduce, Val(R))

_fiberwise(section::ReducibleSection, whole_reduce, over_base_reduce, ::Val{0}) =
  whole_reduce(field_data(section))

function _fiberwise(section::ReducibleSection, whole_reduce, over_base_reduce, ::Val{R}) where {R}
  T = section_scalar_type(section)
  data = field_data(section)
  base = ntuple(identity, ndims(data) - R)
  reduced = Array(dropdims(over_base_reduce(data, base); dims = base))
  R == 1 && return FiberVector{T}(reduced)
  R == 2 && return FiberTensor2{T}(reduced)
  throw(ArgumentError("reductions are implemented for tensor order ≤ 2 (got R = $R)"))
end


"""
    _FiberGather{V}(fiber_map)

A callable that assembles the fiber value of type `V` from its components and applies `fiber_map` to
it. It exists as a struct rather than a closure so the component count is a **type-level** quantity:
an anonymous `(values...) -> fiber_map(V(values))` leaves the tuple length uninferrable, `V(values)`
then cannot be built in registers, and the reduction allocates per base point — measured at about four
and a half times the tensor section's own size. The `Vararg{Any, N}` signature restores that inference.
"""
struct _FiberGather{V, F} <: Function
  fiber_map::F
end

_FiberGather{V}(fiber_map::F) where {V, F} = _FiberGather{V, F}(fiber_map)

(gather::_FiberGather{V})(values::Vararg{Any, N}) where {V, N} = gather.fiber_map(V(values))


# Base elements per pairwise-recursion leaf, matching Base's own reduction blocking: large enough that
# the vectorized leaf loop dominates the recursion, small enough to keep the summation error at the
# pairwise O(log n) rather than the sequential O(n).
const _FIBER_REDUCTION_BLOCK = 1024


"""
    _fiber_at(components, index, ::Val{NC})

Gather the `NC` component values of one base point into a tuple, by linear index. The component arrays
are the contiguous per-component slices of a fiber-last section, so each is a unit-stride stream.
"""
@inline _fiber_at(components, index, ::Val{NC}) where {NC} =
  ntuple(component -> @inbounds(components[component][index]), Val(NC))


"""
    _fiber_loop_reduce(fiber_map, combine, components, V, ::Val{NC}, lo, hi)

Reduce base points `lo:hi` on the **CPU**, assembling each fiber value of type `V` from `components`,
applying `fiber_map`, and combining with `combine`. The recursion splits until a leaf of
`_FIBER_REDUCTION_BLOCK` points, which runs as one vectorized loop.

The shape is Base's own `mapreduce` blocking, reproduced here because the generic path does not apply
to a fused fiber gather: reducing the equivalent lazy `Broadcasted` forgoes the vectorized loop and
runs several times slower, and the sequential alternative would give up pairwise summation's ``O(\\log n)``
error growth for ``O(n)``.
"""
function _fiber_loop_reduce(fiber_map::FiberMap, combine::Combine, components, ::Type{V},
                            ::Val{NC}, lo::Int, hi::Int) where {FiberMap, Combine, V, NC}
  if hi - lo < _FIBER_REDUCTION_BLOCK
    accumulator = fiber_map(V(_fiber_at(components, lo, Val(NC))))
    @inbounds @simd for index in (lo + 1):hi
      accumulator = combine(accumulator, fiber_map(V(_fiber_at(components, index, Val(NC)))))
    end
    return accumulator
  end
  middle = (lo + hi) >> 1
  return combine(_fiber_loop_reduce(fiber_map, combine, components, V, Val(NC), lo, middle),
                 _fiber_loop_reduce(fiber_map, combine, components, V, Val(NC), middle + 1, hi))
end


"""
    _spawn_depth()

Number of top tree levels [`_fiber_tree_reduce`](@ref) and [`_indexed_tree_reduce`](@ref) evaluate
as spawned tasks: enough binary splits to give every thread work, plus one level of slack for load
balancing. Zero when a single thread is available.
"""
_spawn_depth() = Threads.nthreads() == 1 ? 0 : (8 * sizeof(Int) - leading_zeros(Threads.nthreads() - 1)) + 1


"""
    _fiber_tree_reduce(fiber_map, combine, components, V, ::Val{NC}, lo, hi, depth)

Threaded form of [`_fiber_loop_reduce`](@ref) with the **identical reduction tree**: it splits at
the same midpoints the serial recursion uses and combines left-before-right, evaluating the top
`depth` levels as spawned tasks and every subtree below as the untouched serial recursion — so the
result is **bitwise-identical to serial at every thread count** (the tree is a function of the
element count alone, never of the schedule).
"""
function _fiber_tree_reduce(fiber_map::FiberMap, combine::Combine, components, ::Type{V},
                            ::Val{NC}, lo::Int, hi::Int, depth::Int) where {FiberMap, Combine, V, NC}
  if depth <= 0 || hi - lo < _FIBER_REDUCTION_BLOCK
    return _fiber_loop_reduce(fiber_map, combine, components, V, Val(NC), lo, hi)
  end
  middle = (lo + hi) >> 1
  right_task = Threads.@spawn _fiber_tree_reduce(fiber_map, combine, components, V, Val(NC),
                                                 middle + 1, hi, depth - 1)
  left = _fiber_tree_reduce(fiber_map, combine, components, V, Val(NC), lo, middle, depth - 1)
  return combine(left, fetch(right_task)::typeof(left))
end


"""
    _indexed_leaf_reduce(element, combine, lo, hi)

Reduce `element(i)` over `i in lo:hi` with `combine`, as one vectorized loop below the pairwise
block size and by the fixed midpoint recursion above it — the array-kernel sibling of
[`_fiber_loop_reduce`](@ref), sharing its tree so accuracy and determinism carry over.
"""
function _indexed_leaf_reduce(element::E, combine::C, lo::Int, hi::Int) where {E, C}
  if hi - lo < _FIBER_REDUCTION_BLOCK
    accumulator = element(lo)
    @inbounds @simd for index in (lo + 1):hi
      accumulator = combine(accumulator, element(index))
    end
    return accumulator
  end
  middle = (lo + hi) >> 1
  return combine(_indexed_leaf_reduce(element, combine, lo, middle),
                 _indexed_leaf_reduce(element, combine, middle + 1, hi))
end


"""
    _indexed_tree_reduce(element, combine, lo, hi)

Reduce `element(i)` over `i in lo:hi`, spawning the top [`_spawn_depth`](@ref) levels of the fixed
midpoint tree when [`_use_threads`](@ref) allows and running [`_indexed_leaf_reduce`](@ref) below —
the same tree at every thread count, so the result is bitwise thread-count-invariant.
"""
function _indexed_tree_reduce(element::E, combine::C, lo::Int, hi::Int) where {E, C}
  _use_threads(hi - lo + 1) || return _indexed_leaf_reduce(element, combine, lo, hi)
  return _indexed_tree_step(element, combine, lo, hi, _spawn_depth())
end

function _indexed_tree_step(element::E, combine::C, lo::Int, hi::Int, depth::Int) where {E, C}
  if depth <= 0 || hi - lo < _FIBER_REDUCTION_BLOCK
    return _indexed_leaf_reduce(element, combine, lo, hi)
  end
  middle = (lo + hi) >> 1
  right_task = Threads.@spawn _indexed_tree_step(element, combine, middle + 1, hi, depth - 1)
  left = _indexed_tree_step(element, combine, lo, middle, depth - 1)
  return combine(left, fetch(right_task)::typeof(left))
end


"""
    _tree_sum(data)

Sum a CPU array (or contiguous view) through [`_indexed_tree_reduce`](@ref)'s fixed pairwise tree —
threaded above the gate, bitwise thread-count-invariant, and with no accumulator-typing peek (the
first element seeds the accumulator inside the tree itself).
"""
_tree_sum(data) = _tree_sum(KernelAbstractions.get_backend(data), data)
# An empty section must not reach the tree (the leaf seeds from element(lo), an out-of-bounds
# read on an empty range — decision 43); the empty sum is zero, matching Base and the device.
_tree_sum(::KernelAbstractions.CPU, data) =
  isempty(data) ? zero(eltype(data)) :
  _indexed_tree_reduce(index -> (@inbounds data[index]), +, 1, length(data))
_tree_sum(::Any, data) = sum(data)                      # a device runs its own parallel reduce


# THE BASE ARITY IS A TYPE PARAMETER, not an `Int`. Every `ntuple` below and the closing `reshape` are
# sized by it, so a runtime value left their types unknown and the whole reduction inferred `Any` —
# which propagated to `mean` and `cov` on any section above R = 0. The caller knows the arity
# statically (`ndims(data) - R`, both compile-time), so it is passed as the base tuple and recovered
# from its length.
"""
    _tree_dims_reduce(scalar_reduce, data, base_count)

Apply `scalar_reduce` (a whole-array tree reduction) to each fiber component of `data` — the
component slices over the leading `base_count` base axes are contiguous, so each reduces linearly —
returning the array of per-component results the `dims`-style Base call used to produce.
"""
_tree_dims_reduce(scalar_reduce::F, data, base::NTuple{B, Any}) where {F, B} =
  _tree_dims_reduce(KernelAbstractions.get_backend(data), scalar_reduce, data, Val(B))
_tree_dims_reduce(scalar_reduce::F, data, base_count::Int) where {F} =
  _tree_dims_reduce(KernelAbstractions.get_backend(data), scalar_reduce, data, base_count)
# The generic method serves a device too: the per-component views reduce through the closure,
# whose scalar kernels (`_tree_sum`, `_tree_var`) dispatch to the device's own reduce — no scalar
# indexing occurs, only whole-view reductions.
_tree_dims_reduce(::Any, scalar_reduce::F, data, base_count::Int) where {F} =
  _tree_dims_components(scalar_reduce, data, base_count)
_tree_dims_reduce(::KernelAbstractions.CPU, scalar_reduce::F, data, base_count::Int) where {F} =
  _tree_dims_components(scalar_reduce, data, base_count)
_tree_dims_reduce(::Any, scalar_reduce::F, data, ::Val{B}) where {F, B} =
  _tree_dims_components(scalar_reduce, data, Val(B))
_tree_dims_reduce(::KernelAbstractions.CPU, scalar_reduce::F, data, ::Val{B}) where {F, B} =
  _tree_dims_components(scalar_reduce, data, Val(B))

function _tree_dims_components(scalar_reduce::F, data, ::Val{B}) where {F, B}
  fiber_axes = ntuple(d -> axes(data, B + d), Val(ndims(data) - B))
  indices = CartesianIndices(fiber_axes)
  colons = ntuple(_ -> Colon(), Val(B))
  first_value = scalar_reduce(view(data, colons..., Tuple(first(indices))...))
  results = Array{typeof(first_value)}(undef, length.(fiber_axes))
  results[first(indices)] = first_value
  for fiber_index in Iterators.drop(indices, 1)
    results[fiber_index] = scalar_reduce(view(data, colons..., Tuple(fiber_index)...))
  end
  return reshape(results, ntuple(_ -> 1, Val(B))..., length.(fiber_axes)...)
end
function _tree_dims_components(scalar_reduce::F, data, base_count::Int) where {F}
  fiber_axes = ntuple(d -> axes(data, base_count + d), ndims(data) - base_count)
  # The first component's value types the results array AND fills its slot — computed once, so the
  # element-traffic ledger stays at one read per element.
  indices = CartesianIndices(fiber_axes)
  first_value = scalar_reduce(view(data, ntuple(_ -> Colon(), base_count)..., Tuple(first(indices))...))
  results = Array{typeof(first_value)}(undef, length.(fiber_axes))
  results[first(indices)] = first_value
  for fiber_index in Iterators.drop(indices, 1)
    component = view(data, ntuple(_ -> Colon(), base_count)..., Tuple(fiber_index)...)
    results[fiber_index] = scalar_reduce(component)
  end
  # Singleton base axes, so the caller's `dropdims(...; dims = base)` sees the shape a Base
  # `dims`-reduction would have produced.
  return reshape(results, ntuple(_ -> 1, base_count)..., length.(fiber_axes)...)
end


"""
    _tree_var(data; corrected)

Variance through two fixed-tree passes — the mean, then the summed squared deviation — matching
the `corrected` convention of `Statistics.var`.
"""
_tree_var(data; corrected::Bool = true) = _tree_var(KernelAbstractions.get_backend(data), data; corrected)
_tree_var(::Any, data; corrected::Bool = true) = var(data; corrected)
function _tree_var(::KernelAbstractions.CPU, data; corrected::Bool = true)
  count = length(data)
  # The Statistics convention: the variance of an empty sample is NaN (and the second tree
  # pass below must not run on an empty range — decision 43).
  count == 0 && return zero(eltype(data)) / zero(eltype(data))
  mean_value = _tree_sum(data) / count
  squared = _indexed_tree_reduce(index -> (@inbounds abs2(data[index] - mean_value)), +, 1, count)
  return squared / (corrected ? count - 1 : count)
end


"""
    _reduce_fiber(backend, fiber_map, combine, components, V, ::Val{NC})

Reduce a section's fiber values on `backend`, gathering each fiber of type `V` from its `NC` component
arrays. The two backends take different routes because they reward opposite things: a CPU wants the
vectorized blocked loop of [`_fiber_loop_reduce`](@ref), while a GPU has no such loop to lose and is
served by one fused pass over a lazy `Broadcasted`, which also spares it a section write and read-back.
"""
function _reduce_fiber end

function _reduce_fiber(::KernelAbstractions.CPU, fiber_map::FiberMap, combine::Combine, components,
                       ::Type{V}, ::Val{NC}) where {FiberMap, Combine, V, NC}
  count = length(first(components))
  # Delegate an empty base so Base raises its own empty-reduction error rather than indexing out of range.
  count == 0 && return _reduce_fiber_broadcast(fiber_map, combine, components, V, Val(NC))
  _use_threads(count) || return _fiber_loop_reduce(fiber_map, combine, components, V, Val(NC), 1, count)
  return _fiber_tree_reduce(fiber_map, combine, components, V, Val(NC), 1, count, _spawn_depth())
end

_reduce_fiber(::Any, fiber_map::FiberMap, combine::Combine, components, ::Type{V},
              ::Val{NC}) where {FiberMap, Combine, V, NC} =
  _reduce_fiber_broadcast(fiber_map, combine, components, V, Val(NC))

_reduce_fiber_broadcast(fiber_map::FiberMap, combine::Combine, components, ::Type{V},
                        ::Val{NC}) where {FiberMap, Combine, V, NC} =
  mapreduce(identity, combine,
            Broadcast.instantiate(Broadcast.broadcasted(_FiberGather{V}(fiber_map), components...)))


"""
    _fiber_mapreduce(fiber_map, combine, section)

Reduce with `combine` over the base, applying `fiber_map` to the **fiber value** at each base point:
the scalar itself for tensor order `0`, the `FiberVector` for `1`, the `FiberTensor2` for `2`. This
backs the mapped forms of the reductions, so a nonlinear fiber invariant is reduced **without
materializing it as a section** — the mapped value exists only per base point, in registers.

The fiber is gathered from the section's per-component arrays, because the fiber-last layout makes each
component a contiguous slice but places the components of one base point a whole base apart, so a fiber
cannot be reinterpreted into a `StaticArray` in place. How those components are then reduced is chosen
per backend by [`_reduce_fiber`](@ref) — a vectorized blocked loop on a CPU, one fused pass over a lazy
`Broadcasted` on a GPU — since the two reward opposite things.

One spelling to avoid either way: the multi-argument `mapreduce(fiber_map, combine, components...)` is
fused by GPUArrays but falls back on the CPU to a route that materializes a full section-sized array.

The `fiber_map::FiberMap` type parameter — here and on every public form that forwards to this one — is
required, not decoration. Julia declines to specialize on an argument of `Function` type that a method
only passes along instead of calling, so without it the map arrives boxed and the reduction allocates
on every call; naming its type in the signature forces the specialization that keeps the whole family
allocation-free.
"""
function _fiber_mapreduce(fiber_map::FiberMap, combine::Combine,
                          section::Union{AbstractFieldPhysical{T, R}, AbstractPointValues{T, R}}
                          ) where {FiberMap, Combine, T, R}
  # `T` and `R` are matched as static parameters rather than read back with `section_scalar_type` /
  # `_tensor_order`, so the fiber type below is a compile-time type rather than a runtime lookup. This
  # is for clarity, not for allocation: what keeps the family at zero bytes is the forced specialization
  # on `fiber_map` (see the docstring) — matching the parameters here changed nothing on its own.
  # Tensor order 0 needs no gather: the data array *is* the sequence of fiber values, so the backend's
  # own `mapreduce` already takes its best route on either device.
  R == 0 && return mapreduce(fiber_map, combine, field_data(section))
  backend = get_backend(field_data(section))
  if R == 1
    components = ntuple(index -> _vector_component_data(section, index), Val(3))
    return _reduce_fiber(backend, fiber_map, combine, components, FiberVector{T}, Val(3))
  elseif R == 2
    # Column-major fiber order, matching the `FiberTensor2` (`SMatrix`) constructor.
    components = ntuple(Val(9)) do index
      _tensor2_component_data(section, (index - 1) % 3 + 1, (index - 1) ÷ 3 + 1)
    end
    return _reduce_fiber(backend, fiber_map, combine, components, FiberTensor2{T}, Val(9))
  end
  throw(ArgumentError("reductions are implemented for tensor order ≤ 2 (got R = $R)"))
end


###################################
#        Reductions               #
###################################


"""
    integral(f)
    integral(fiber_map, f)

The base integral ``\\int f \\,\\mathrm{d}\\mu`` of a section (`integral` ``\\equiv \\int\\,\\mathrm{d}\\mu``) — the
measure-weighted sum of `f` over its base. It is the one **extensive** reduction, the only one that
scales with the base measure; reach for [`inner`](@ref) or `mean` when you want an intensive,
size-independent average instead. On a `Grid3D` the sum uses the uniform cell-volume quadrature, and on
a `PointSet` it uses the unit-weight counting measure:

```math
\\int f \\,\\mathrm{d}\\mu =
\\begin{cases}
  \\dfrac{|\\Omega|}{N} \\sum_{x} f(x), & \\text{base a } \\texttt{Grid3D} \\text{ — the box } \\Omega \\text{ and its } N \\text{ cells},\\\\[4pt]
  \\sum_{p} f_p,                          & \\text{base a } \\texttt{PointSet} \\text{ — no domain, unit weight per point},
\\end{cases}
```

where ``N`` is the number of grid cells and ``|\\Omega|`` the domain volume. The result is
fiber-preserving: a scalar for a scalar section, a `FiberVector` for a vector section, and a
`FiberTensor2` for a tensor section. For a band-limited field the grid quadrature is exact, because the
periodic trapezoidal rule integrates the represented modes exactly. For a field in **spectral
representation** the same value comes from the zero (DC) Fourier mode with no inverse transform,
``\\int_\\Omega f\\,\\mathrm{d}\\mu = \\tfrac{|\\Omega|}{N} \\hat f(0)``, since the DC coefficient
``\\hat f(0) = \\sum_x f(x)`` is real for a real field.

# The mapped form

Given a leading function `fiber_map`, the integrand becomes that function of the section's fiber value
at each base point rather than the fiber value itself:

```math
\\int_\\Omega (\\texttt{fiber\\_map} \\circ f) \\,\\mathrm{d}\\mu.
```

The map receives the scalar for a scalar section, the `FiberVector` for a vector
section, and the `FiberTensor2` for a tensor section, so `integral(det, A)` integrates a determinant
and `integral(norm, u)` a magnitude. The mapped value is formed one base point at a time and consumed
by the reduction immediately, so nothing section-sized is built — where writing the same quantity as
`integral(det(A))` first materializes a whole determinant field. Passing `identity` recovers the bare
form. The same leading function is taken by `mean` (which divides by the base count instead of weighting
by the measure) and by `maximum`/`minimum`/`extrema`; for the order statistics it is also what makes
them well posed above tensor order zero, the bare forms being scalar-only by design.

The mapped form is the cheaper route on both backends — one pass that allocates nothing, against a
materialized section plus a second pass over it — by roughly two and a half times on a CPU and a
quarter on a GPU. It gets there by different means on each, chosen internally: a fixed reduction tree
over vectorized blocked loops on a CPU, a single fused pass on a GPU. That tree's shape does not
depend on the thread count, so a CPU result is **bitwise identical** however many threads it runs on.

!!! note "The fiber map's own cost can dominate"
    The fiber map's own cost can outweigh the choice of route. `LinearAlgebra.norm` applied to a fiber
    uses the overflow-safe scaled algorithm, several times the cost of the plain
    ``\\sqrt{\\sum_i u_i^2}`` that the fieldwise `norm` evaluates, which is enough to make
    `maximum(norm, u)` costlier than `lpnorm(u, Inf)` on a CPU despite allocating nothing; passing a plain
    magnitude instead reverses that. Pick the map for the accuracy the result needs.
"""
function integral end
integral(section::ReducibleSection) =
  _fiberwise(section, _tree_sum, (data, base) -> _tree_dims_reduce(_tree_sum, data, base)) .* _cell_measure(section)

integral(fiber_map::FiberMap, section::ReducibleSection) where {FiberMap} =
  _fiber_mapreduce(fiber_map, +, section) * _cell_measure(section)


"""
    mean(f)
    mean(fiber_map, f)

The arithmetic average of a section over its base, fiber-preserving: on a grid the equal-weight
cell average ``\\tfrac{1}{N}\\sum_n f_n`` over the ``N`` cells, on a point-set the sample mean
``\\tfrac{1}{M}\\sum_p f_p`` over the ``M`` points — a vector field's mean is one `FiberVector`, a
second-order tensor field's one `FiberTensor2`. The mapped form `mean(fiber_map, f)` averages
``(\\texttt{fiber\\_map} \\circ f)(x_n)`` (for example `mean(det, A)`) in one fused pass with no
intermediate section; the map is nonlinear in general, so the mapped forms exist on fields in physical representation
and point-values only. On a field in spectral representation the mean is read from the zero (DC)
Fourier mode in ``O(1)``, equal to the physical value with no transform. See [`integral`](@ref) for
the extensive (measure-weighted) sibling.
"""
mean

"""
    var(f; corrected = true)

The sample **variance** of a **scalar** section over its base: the Bessel-corrected mean (dividing by
one less than the count, the standard correction that makes the sample variance an unbiased estimate of
the population one) of the squared
deviation from the average, ``\\tfrac{1}{N-1}\\sum_n (f_n - \\bar f)^2`` over a grid's ``N`` cells and
``\\tfrac{1}{M-1}\\sum_p`` over a point set's ``M`` points (matching `Statistics.var`'s default correction).

`var`/`std` are **scalar-only**: the sample variance is unambiguous only for a scalar section. A vector
field's coordinate-free second moment is the covariance tensor [`cov`](@ref); a per-component variance
would be only its basis-dependent diagonal, so it is not offered — calling `var`/`std` on a vector or
tensor section raises a clear error pointing to `cov`.

In physical representation it runs as two fused passes — the mean, then the squared deviations — with no
intermediate deviation section (the numerically stable form). In **spectral** representation it is read
from Parseval: the *population* moment is
``\\langle f, f\\rangle - \\langle f\\rangle^2 = N^{-2}\\sum_{\\text{stored } k \\ne 0} \\alpha(k) |\\hat f_k|^2`` — the
fluctuation energy, with ``N`` the number of grid cells, ``\\alpha(k)`` the half-spectrum multiplicity
of mode ``k``, and the ``N^{-2}`` the normalization the inner product itself carries — and the default
`corrected = true` multiplies it by ``N/(N-1)``. Either way it equals the physical value with no
inverse transform; that one-pass form loses
precision to cancellation when the mean dominates the fluctuations, so prefer the physical form there.

The arguments are:
- `f` — the scalar section the moment is taken over: a field in physical or spectral
  representation, or point values.
- `corrected` — divide by the count minus one (the sample convention, the default, matching
  `Statistics.var`) or by the count itself. A grid holds the *complete* population of a field rather
  than a sample of it, so `corrected = false` is often what a field diagnostic wants; the default
  follows the standard library rather than the base.

See [`std`](@ref) for its square root, `cov` for the vector second moment, and [`mean`](@ref) for
the first moment.
"""
var

"""
    std(f; corrected = true)

The sample **standard deviation** of a **scalar** section: the square root of [`var`](@ref), over the same
bases `var` serves — a `Grid3D` or a `PointSet` — and, for a field, in spectral representation as
well. Point values are representation-free, so that last clause reaches fields alone. Like `var` it is **scalar-only** —
``\\operatorname{std} = \\sqrt{\\operatorname{var}}`` has no canonical form for a vector (the matrix square root of the covariance is not a standard deviation);
use [`cov`](@ref) for the vector second central moment.

The arguments are:
- `f` — the scalar section the moment is taken over: a field in physical or spectral
  representation, or point values.
- `corrected` — divide by the base count minus one (Bessel's correction, the default) rather than by
  the count, exactly as it does for `var`, of which this is the square root.
"""
std

"""
    maximum(f)
    maximum(fiber_map, f)

The largest value of a scalar section over its base — a grid's cells or a point-set's points. The
bare form exists only at tensor order zero: the maximum of a vector or tensor section is ill posed
(which component?), and naming a fiber map in the mapped form `maximum(fiber_map, f)` is what makes it well
posed — `maximum(norm, u)` takes the largest fiber magnitude in one fused pass with no intermediate
section. Physical fields and point-values only. The materializing route to the same supremum is
[`lpnorm(f, Inf)`](@ref lpnorm). An order statistic has no neutral element, so reducing an empty section
(a zero-point set) throws an `ArgumentError` — the same contract as reducing an empty collection in
`Base` — rather than fabricating a value.
"""
maximum

"""
    minimum(f)
    minimum(fiber_map, f)

The smallest value of a scalar section over its base — the mirror of [`maximum`](@ref); see there
for the bases, the scalar-only restriction, and the mapped form.
"""
minimum

"""
    extrema(f)
    extrema(fiber_map, f)

The pair `(minimum(f), maximum(f))` of a scalar section over its base, in one call — and with a
leading fiber map, the pair `(minimum(fiber_map, f), maximum(fiber_map, f))`, which is what makes the
order statistics well posed above tensor order 0. See [`maximum`](@ref).
"""
extrema

# `mean`, `std`, `var` (extending Statistics) — intensive, fiber-preserving base reductions.
# `mean(f) = (1/count)·Σf`: the arithmetic average over base elements — the volume average
# (1/|Ω|)∫_Ω f dx on a grid, a plain sample mean over points. `std`/`var` are the per-fiber-component
# base moments.
mean(section::ReducibleSection) =
  _fiberwise(section, data -> _tree_sum(data) / length(data),
             (data, base) -> _tree_dims_reduce(component -> _tree_sum(component) / length(component), data, base))

mean(fiber_map::FiberMap, section::ReducibleSection) where {FiberMap} =
  _fiber_mapreduce(fiber_map, +, section) / _base_count(section)

# `var`/`std` are SCALAR-ONLY (decision 49). The sample variance/standard deviation is unambiguous only
# for a scalar section: for a vector the coordinate-free second central moment is the covariance tensor
# `cov`, and a per-component `var` would be only its basis-dependent diagonal; `std = √var` has no
# canonical vector form (the matrix square root of the covariance is not a standard deviation). So there
# is deliberately no `var`/`std` on a vector or tensor section — use `cov` for the vector second moment.
var(field::AbstractFieldPhysical{T, 0}; corrected::Bool = true) where {T} = _tree_var(field_data(field); corrected = corrected)
var(values::AbstractPointValues{T, 0}; corrected::Bool = true) where {T} = _tree_var(field_data(values); corrected = corrected)
std(field::AbstractFieldPhysical{T, 0}; corrected::Bool = true) where {T} = sqrt(_tree_var(field_data(field); corrected = corrected))
std(values::AbstractPointValues{T, 0}; corrected::Bool = true) where {T} = sqrt(_tree_var(field_data(values); corrected = corrected))

# A clear error for the scalar-only restriction — a vector/tensor section would otherwise fall through to
# Statistics' iterable `var`/`std` and fail to iterate the section with a cryptic message.
_var_scalar_only(::AbstractFiberSection) =
  throw(ArgumentError("`var`/`std` are defined for scalar sections only; the second moment of a vector section is the covariance tensor `cov`"))
var(section::AbstractFiberSection; corrected::Bool = true) = _var_scalar_only(section)
std(section::AbstractFiberSection; corrected::Bool = true) = _var_scalar_only(section)


"""
    cov(u; corrected = true)

The **covariance tensor** ``R_{ij} = \\langle u'_i u'_j\\rangle`` of a vector section over its base,
where ``u' = u - \\bar u`` is the fluctuation about the base mean — the
coordinate-free second central moment of a vector-valued field or point set, the vector analogue of the
scalar [`var`](@ref). It returns one symmetric `FiberTensor2`: the diagonal holds the per-component
variances (the *normal* stresses, in a turbulence reading), the off-diagonal the component covariances
(the *shear* stresses) that a per-component variance would discard.

Use this for the second moment of a vector field. The `var`/`std` pair is deliberately scalar-only: a
per-component `var` would be only the basis-dependent diagonal of this tensor, and
``\\operatorname{std} = \\sqrt{\\operatorname{var}}`` has no
canonical vector form, so the covariance tensor is the honest object. The mean ``\\bar u`` is subtracted
first, so this is the covariance of the fluctuations, not the raw second moment ``\\langle u_i u_j\\rangle``.

The arguments are:
- `u` — the vector section whose fluctuations the covariance tensor is built from.
- `corrected` — divide by the base count minus one (the sample convention, the default, matching
  `Statistics.cov`); `false` divides by the count (the population covariance).

Physical-space only, since the outer product ``u \\otimes u`` is nonlinear. Computed in one fused mapped
pass as ``\\operatorname{mean}(u \\otimes u) - \\bar u \\otimes \\bar u`` (Bessel-scaled), over the grid
cell-average measure and the point counting measure alike.
"""
function cov end

# The covariance reuses the mapped `mean` with the outer-product fiber map (a `FiberVector → FiberTensor2`
# map), then subtracts the outer product of the mean — one fused reduction pass plus O(1) fiber algebra.
_outer_product(x) = x * transpose(x)

function _covariance(u, corrected::Bool)
  average = mean(u)
  count = _base_count(u)
  population = mean(_outer_product, u) - average * transpose(average)
  return corrected ? population * count / (count - 1) : population
end

cov(u::AbstractFieldPhysical{T, 1}; corrected::Bool = true) where {T} = _covariance(u, corrected)
cov(u::AbstractPointValues{T, 1}; corrected::Bool = true) where {T} = _covariance(u, corrected)


# Spectral representation: `integral` and `mean` are carried entirely by the zero (DC) Fourier mode, so
# both are read with no inverse transform. Under the unnormalized-forward convention (invariant 4) the DC
# coefficient is f̂(0) = Σₓ f(x), real for a real field — the same zero-mode slot the constant-add writes.
# `_real_zero_mode` copies just that slot to the host (GPU-safe; no scalar indexing of the device array)
# and returns a real fiber value; `mean = f̂(0)/N` and `integral = ΔV·f̂(0)` then equal the physical
# reductions (up to FFT round-off). `lpnorm`/`maximum` have no single-coefficient form and stay
# physical-only; scalar `std`/`var` read from Parseval (`inner − mean²`), below.
_real_zero_mode(field::ScalarFieldSpectral) = real(only(Array(_spectral_zero_mode_data(field))))

function _real_zero_mode(field::VectorFieldSpectral)
  T = section_scalar_type(field)
  return FiberVector{T}(ntuple(c -> real(only(Array(_spectral_zero_mode_component_data(field, c)))), Val(3)))
end

function _real_zero_mode(field::TensorFieldSpectral{2})
  T = section_scalar_type(field)
  return FiberTensor2{T}(ntuple(k -> real(only(Array(_spectral_zero_mode_component_data(field,
                                        (k - 1) % 3 + 1, (k - 1) ÷ 3 + 1)))), Val(9)))
end

integral(field::AbstractFieldSpectral) = _real_zero_mode(field) * _cell_measure(field)

mean(field::AbstractFieldSpectral) = _real_zero_mode(field) / _spectral_constant_scale(field)

# `var`/`std` in spectral representation — SCALAR-ONLY, and physical-only-by-scoping now closed: the sample
# variance is the fluctuation energy `inner(f, f) - mean(f)²` (`Σ_{k≠0} |f̂_k|²` by Parseval), equal to the
# physical value with no inverse transform. It is the one-pass form, so a field whose mean dominates its
# fluctuations loses precision to cancellation (the physical two-pass does not) — prefer the physical form
# there. `std` is the square root.
function var(field::ScalarFieldSpectral; corrected::Bool = true)
  count = prod(field_grid(field).grid_size)
  population = inner(field, field) - mean(field)^2
  return corrected ? population * count / (count - 1) : population
end
std(field::ScalarFieldSpectral; corrected::Bool = true) = sqrt(var(field; corrected = corrected))


"""
    inner(f, g)

The **normalized L² inner product** ``\\langle f, g\\rangle`` of two compatible sections
(`inner` ``\\equiv \\langle\\cdot,\\cdot\\rangle``) — the fiber contraction ``f \\cdot g`` averaged over the
base, returning a scalar. It is intensive (it matches `mean`), which makes it the natural pairing for
homogeneous turbulence, where kinetic energy is ``\\tfrac{1}{2}\\langle u, u\\rangle``. For the norms derived
from it use [`l2norm`](@ref) or [`lpnorm`](@ref); to resolve the pairing over a wavenumber or separation
shell use [`radial_spectrum`](@ref) or [`radial_correlation`](@ref).

The arguments `f` and `g` are two compatible sections of equal tensor order. On a grid the pairing is the
equal-weight average over the ``N`` cells (``\\Omega`` is the periodic box, ``|\\Omega|`` its volume); on a
point-set it is the average over the ``M`` points. The grid's continuum form below is exact when the
product ``f \\cdot g`` is resolved on the grid (the periodic trapezoidal rule integrates resolved modes
exactly); under aliasing — both fields carrying Nyquist content, say — the discrete sum is the definition:

```math
\\begin{aligned}
\\langle f, g\\rangle &= \\frac{1}{|\\Omega|} \\int_\\Omega f(x) \\cdot g(x)\\,\\mathrm{d}x
  = \\frac{1}{N} \\sum_x f(x) \\cdot g(x) && (\\texttt{Grid3D}), \\\\
\\langle f, g\\rangle &= \\frac{1}{M} \\sum_p f_p \\cdot g_p && (\\texttt{PointSet}).
\\end{aligned}
```

For two fields in **spectral representation** `inner` returns the same value by Parseval's theorem with
no inverse transform, applying the rfft half-spectrum weighting internally. This ``p = 2`` inner and
`l2norm` are representation-invariant by Parseval, and `integral`/`mean` by the zero Fourier mode;
`lpnorm` and `maximum`/`minimum`/`extrema` remain physical-only; `std`/`var` gained a scalar Parseval form.

!!! note "The mixed spectral pair allocates one or two correction planes"
    In spectral representation `inner(f, f)` and `l2norm` run allocation-free, but the *mixed*
    `inner(f, g)` materializes ``O(N^2)`` correction planes — the folded axis's zero plane always, and
    its Nyquist plane as well when that axis has even length, so an odd folded axis pays for one plane
    and an even one for two. That is small beside the ``O(N^3)`` field, and it is paid per call, where `inner(f, f)` pays
    nothing. The fused alternative, a `dot` over a strided view, has no
    method on the AMD path (rocBLAS `dotc`), so one route serves every backend.
"""
function inner end
# Two sections may be contracted only when they are the same kind of section over the same base,
# carrying the same fiber and scalar type. Base kind, tensor order and scalar type are all TYPE-level
# here, so the whole predicate resolves at compile time and costs a contraction nothing.
#
# Equal base COUNT is not enough, and the gap was not academic: a scalar and a vector field over the
# same grid have equal base counts and unequal storage lengths, so the loop below indexed the shorter
# array past its end under `@inbounds` — an out-of-bounds read that returned a plausible number
# because the memory beyond happened to be zero. A grid field and point values with matching counts
# were likewise accepted, though their bases are unrelated.
_same_base_kind(::AbstractFieldPhysical, ::AbstractFieldPhysical) = true
_same_base_kind(::AbstractPointValues, ::AbstractPointValues) = true
_same_base_kind(::ReducibleSection, ::ReducibleSection) = false


function _check_contractible(f::ReducibleSection, g::ReducibleSection)
  _same_base_kind(f, g) ||
    throw(ArgumentError("a grid field and point values are sections over unrelated bases and " *
                        "cannot be contracted, even when their base counts agree"))
  section_tensor_order(f) == section_tensor_order(g) ||
    throw(DimensionMismatch("sections have different tensor orders: " *
                            "$(section_tensor_order(f)) and $(section_tensor_order(g))"))
  section_scalar_type(f) === section_scalar_type(g) ||
    throw(ArgumentError("sections have different scalar types: " *
                        "$(section_scalar_type(f)) and $(section_scalar_type(g))"))
  _base_count(f) == _base_count(g) ||
    throw(DimensionMismatch("sections have different base sizes: $(_base_count(f)) and $(_base_count(g))"))
  length(field_data(f)) == length(field_data(g)) ||
    throw(DimensionMismatch("sections have different storage lengths: " *
                            "$(length(field_data(f))) and $(length(field_data(g)))"))
  # For a FIELD pair, the base is a grid, and two grids agreeing in shape can still be different
  # manifolds — a ``2\pi`` box and a ``4\pi`` box, or two layouts. Every sibling that combines two
  # fields refuses that pair through the domain check; this one did not, so the mixed physical
  # `inner(f, g)` accepted sections over different bases and returned a number that means nothing.
  # Found by the peer-rejection gate on its first run (2026-08-29): `inner` was the single caller of
  # this predicate, and the single one of the pairwise operations whose refusal nothing asserted.
  # `ReducibleSection` is physical-fields-or-point-values, so the pair is matched as
  # physical/physical directly — which is also the only name this module imports.
  if f isa AbstractFieldPhysical && g isa AbstractFieldPhysical
    _check_field_domain_compatibility(f, g)
  end
  # STORAGE FAMILY, for the same reason `_check_same_domain` carries it: without the check a
  # host/device pair passes every structural test above and then fails somewhere below, so the error a
  # user meets depends on which operation they called and on the backend. That was literally the case
  # here — `inner(device, host)` refused only because CUBLAS has no method taking a `CuPtr` and a `Ptr`
  # together, and reported it as `no method matching dot(::Int64, ::CuPtr{Float64}, …)`. It was an
  # accident of the vendor library rather than a decision of the package, while `dot`, `add!`, `cross!`
  # and `multiply!` all refused deliberately with a clear message.
  _same_backend(f, g) ||
    throw(ArgumentError("sections must live in the same storage family; got " *
                        "$(_storage_family(f)) and $(_storage_family(g))"))
  return nothing
end


function inner(f::ReducibleSection, g::ReducibleSection)
  _check_contractible(f, g)
  a, b = field_data(f), field_data(g)
  # The fixed-tree dot on CPU (threaded, bitwise thread-count-invariant, no typing peek); a device
  # keeps its own parallel `dot` (decision-30 polarity).
  if KernelAbstractions.get_backend(a) isa KernelAbstractions.CPU
    # The empty dot is zero (so the normalized inner of an empty base is 0/0 = NaN, like
    # `mean`); the tree itself must never see an empty range (decision 43).
    isempty(a) && return zero(eltype(a)) / _base_count(f)
    return _indexed_tree_reduce(index -> (@inbounds a[index] * b[index]), +, 1, length(a)) / _base_count(f)
  end
  return LinearAlgebra.dot(a, b) / _base_count(f)
end


# Spectral (Parseval) inner product. For real fields the normalized physical inner ⟨f,g⟩ =
# (1/N)·Σₓ dot(f,g) equals, by Parseval's theorem, a weighted sum over the rfft coefficients. The rfft stores
# only the folded axis's (fft_dims[1], axis 1 by default) nonnegative frequencies, so each mode counts
# twice (it stands for itself and its unstored conjugate partner) EXCEPT that axis's self-conjugate
# zero plane and — when it is even — its Nyquist plane, which count once (decision 41).
# With Sₜ = Σ_stored Σ_c f̂_c conj(ĝ_c) = dot(ĝ, f̂):
#   ⟨f,g⟩ = Re(2·Sₜ − S_{kₓ=0} − S_{Nyquist}) / N²,   N = prod(grid_size)   (Nyquist term: even Nₓ only)
# computed as a `dot` over the whole array (contiguous ⇒ allocation-free) plus two small correction-plane
# reductions; the real part discards the round-off imaginary part of the (provably real) full-spectrum sum.
# The folded axis is a RUNTIME value, and `selectdim(data, dimension, index)` with a runtime dimension
# produces a `SubArray` whose type inference cannot pin down — so every reduction over one of these
# correction planes came back as `Any`, making the whole spectral `inner` type-unstable. Branching on
# the three literal dimensions keeps each `selectdim` inferable, and since all three arms return the
# same type the join is concrete. `inner` is a per-step reduction in a solver, so the dispatch this
# costs is worth removing.
@inline _folded_abs2_plane(data, dimension::Int, index::Int) =
  dimension == 1 ? sum(abs2, selectdim(data, 1, index)) :
  dimension == 2 ? sum(abs2, selectdim(data, 2, index)) :
                   sum(abs2, selectdim(data, 3, index))

@inline function _folded_cross_plane(data_g, data_f, dimension::Int, index::Int)
  dimension == 1 && return sum(conj.(selectdim(data_g, 1, index)) .* selectdim(data_f, 1, index))
  dimension == 2 && return sum(conj.(selectdim(data_g, 2, index)) .* selectdim(data_f, 2, index))
  return sum(conj.(selectdim(data_g, 3, index)) .* selectdim(data_f, 3, index))
end


function inner(f::AbstractFieldSpectral{T}, g::AbstractFieldSpectral{T}) where {T<:AbstractFloat}
  _check_field_domain_compatibility(f, g)
  # The domain check settles the base — grid, layout, storage — and says nothing about the FIBER, so on
  # its own it lets a scalar be contracted with a vector. The physical path never could: it routes
  # through `_check_contractible`, which compares tensor orders. Parseval does not remove the
  # requirement that the two sections have the same fiber, and without this the mismatch is silent —
  # `inner(scalar, vector)` returned a plausible number and `inner(vector, tensor)` returned NaN.
  field_tensor_order(f) == field_tensor_order(g) ||
    throw(DimensionMismatch("sections have different tensor orders: " *
                            "$(field_tensor_order(f)) and $(field_tensor_order(g))"))
  data_f = field_data(f)
  data_g = field_data(g)
  normalization = T(prod(field_grid(f).grid_size))^2
  folded_dimension = field_layout(f).fft_dims[1]
  even_fold = iseven(field_grid(f).grid_size[folded_dimension])
  if data_f === data_g
    # f === g (an L² norm / kinetic energy — the hot-loop case): conj(f̂)·f̂ = |f̂|² is real, so the entire
    # Parseval sum is a fused `abs2` mapreduce, the correction planes included. `sum(abs2, view)` reduces
    # the strided kₓ plane WITHOUT a product-broadcast, so this branch is **allocation-free** (unlike the
    # general f ≠ g branch below). `l2norm(f) = sqrt(inner(f, f))` therefore allocates nothing either.
    total = KernelAbstractions.get_backend(data_f) isa KernelAbstractions.CPU ?
      _indexed_tree_reduce(index -> (@inbounds abs2(data_f[index])), +, 1, length(data_f)) :
      sum(abs2, data_f)                                         # Σ_stored |f̂|²  (fused, real)
    correction = _folded_abs2_plane(data_f, folded_dimension, 1)
    even_fold && (correction += _folded_abs2_plane(data_f, folded_dimension,
                                                   size(data_f, folded_dimension)))
    return (2 * total - correction) / normalization
  end
  # General f ≠ g. The whole-array term is a contiguous `dot` (allocation-free); the self-conjugate kₓ=0
  # plane (and the Nyquist plane for even Nₓ) are counted once, not twice, so subtract them. A `dot` over
  # the strided plane view (which would fuse, no temporary) is unsupported on the AMD path (rocBLAS
  # `dotc` has no strided method — a vendor gap, not a property of GPUs in general; CUDA is not the
  # constraint here). One route is taken on every backend rather than branching per vendor, so reduce
  # the product-broadcast instead — this materializes O(N²) per call (one kₓ
  # plane × fiber, twice): small vs the O(N³) field, but allocated each call. A GPU hot loop forms an energy
  # as `inner(f, f)` (the fused branch above) or uses the physical `inner` (a contiguous `dot`), not this.
  total = (KernelAbstractions.get_backend(data_g) isa KernelAbstractions.CPU ?
      _indexed_tree_reduce(index -> (@inbounds conj(data_g[index]) * data_f[index]), +, 1, length(data_g)) :
      LinearAlgebra.dot(data_g, data_f))                       # Σ_stored f̂ conj(ĝ) (contiguous ⇒ BLAS dot)
  correction = _folded_cross_plane(data_g, data_f, folded_dimension, 1)
  even_fold && (correction += _folded_cross_plane(data_g, data_f, folded_dimension,
                                                  size(data_f, folded_dimension)))
  return real(2 * total - correction) / normalization
end


"""
    l2norm(f)

The **normalized L² norm** ``\\lVert f\\rVert_2`` of a section (`l2norm` ``\\equiv \\lVert\\cdot\\rVert_2``)
— the root-mean-square of the fiber magnitude ``|f|`` over the base, and the ``p = 2`` case of
[`lpnorm`](@ref). It is ``\\sqrt{\\langle f, f\\rangle}`` built on [`inner`](@ref), so it inherits both
bases: the grid cell-volume average and the point-set counting average.

```math
\\lVert f\\rVert_2 = \\sqrt{\\langle f, f\\rangle}
  = \\sqrt{\\frac{1}{N} \\sum_x |f(x)|^2} \\quad (\\texttt{Grid3D}),
\\qquad
\\sqrt{\\frac{1}{M} \\sum_p |f_p|^2} \\quad (\\texttt{PointSet}).
```

It is defined for fields in physical representation and point-values, and — through the Parseval `inner` — for a
field in spectral representation.
"""
l2norm(section::ReducibleSection) = sqrt(inner(section, section))
l2norm(f::AbstractFieldSpectral) = sqrt(inner(f, f))


# The rfft half-spectrum Parseval weight, as a (Nkx, 1, 1) array on the field's backend so it
# broadcasts over the spectral coefficients: each stored mode counts twice (it stands for its unstored
# conjugate partner) EXCEPT the folded axis's self-conjugate zero plane and — when that axis is
# even — its Nyquist plane, which count once. The folded axis is the layout's fft_dims[1] (decision 41). The tiny host vector is built then bulk-copied to the device (no scalar indexing of
# device memory, invariant 6). Same weighting as the spectral `inner` above, here per mode.
function _parseval_weight(f::AbstractFieldSpectral{T}) where {T<:AbstractFloat}
  folded_dimension = field_layout(f).fft_dims[1]
  folded_length = size(field_data(f), folded_dimension)
  weight_host = fill(T(2), folded_length)
  weight_host[1] = T(1)
  iseven(field_grid(f).grid_size[folded_dimension]) && (weight_host[folded_length] = T(1))
  weight_device = similar(field_data(f), T, folded_length)
  copyto!(weight_device, weight_host)
  return reshape(weight_device, ntuple(d -> d == folded_dimension ? folded_length : 1, 3))
end


"""
    weighted_inner(f, w::SpectralKernel)
    weighted_inner(f, g, w::SpectralKernel)
    weighted_inner(f, weights::Tuple{Vararg{SpectralKernel}})

The **multiplier-weighted L² inner product** ``\\langle f, w g\\rangle`` of two fields in spectral
representation against a real Fourier multiplier `w`
(`weighted_inner` ``\\equiv \\langle\\cdot, w \\cdot\\rangle``). It applies the spectral symbol `w` to `g`
and reduces against `f` in a single fused pass, materializing no weighted field — the reduction-dual of
`convolve`, which instead forms ``w \\star g`` as a field. It generalizes [`inner`](@ref) (the
``w \\equiv 1`` case); the two-argument form is the ``g = f`` case ``\\langle f, w f\\rangle``.

The arguments are:
- `f`, `g` — two compatible, equal-order fields in spectral representation (`g = f` in the two-argument form).
- `weights` — in the tuple form, a tuple of such kernels: every one is answered in a single traversal
  and one device readback, bitwise-equal to calling the operation once per weight, and the results are
  returned in the order given.
- `w` — the weight: a spectral kernel in **any** of its storage classes, holding a **real** multiplier
  ``w(k)``. All four classes give bitwise-identical results, so the choice is one of storage only. The
  multiplier must be real, because ``\\langle f, w g\\rangle`` is an inner product only then: a kernel
  whose type says complex — `translation_kernel`'s phase, for one — is **rejected** rather than
  silently contributing its real part. One class is exempt, and the exemption is a hazard in its own
  right — see the warning below. Build it with the neutral builders: a band mask (`spectral_band`/`spectral_cutoff`) gives an in-band (co-)energy, and `radial_kernel(identity, multipliers)` (``w = |k|^2``) gives the Dirichlet energy ``\\langle f, -\\Delta g\\rangle`` exactly (both keep the true Nyquist ``k^2``); on fields with no Nyquist content this equals ``\\langle\\nabla f, \\nabla g\\rangle``, the derivative multiplier zeroing only the then-empty Nyquist plane.

!!! warning "A complex `StoredKernel` weight is silently reduced to its real part"
    Three of the four kernel classes **throw** on a complex multiplier, their type settling the question
    for free. A `StoredKernel` cannot: its storage is `Complex{T}` by construction, so a materialized
    `spectral_cutoff` and a materialized `translation_kernel` have the same type. Telling them
    apart needs a full extra pass over the coefficients, which this reduction's single pass does not
    permit — so that class keeps the real-part behaviour, and a complex weight reaching it returns a
    number rather than raising. It is the one route by which a phase kernel can serve as a weight and
    answer a question you did not ask.

Physically it is the L² pairing of `f` with the filtered field ``w \\star g``. By Parseval, with the rfft
half-spectrum weight ``\\alpha(k)`` (``1`` on the folded axis's zero plane and, when that axis has
even length, its Nyquist plane; ``2`` otherwise — the folded rfft axis is the layout's
`fft_dims[1]`, the first by default), ``N`` the number of grid points, and ``c`` a fiber-component index
(unrelated to the exponent coefficient `Convolution` writes ``c``),

```math
\\langle f, w g\\rangle = \\frac{1}{N} \\sum_x f(x) \\cdot (w \\star g)(x)
  = \\frac{1}{N^2} \\sum_{\\text{stored } k} \\alpha(k)  w(k) \\sum_c \\mathrm{Re}\\bigl(\\hat f_c(k) \\overline{\\hat g_c(k)}\\bigr).
```

It equals the naive ``\\texttt{inner}(w \\star f, w \\star g)`` **only** when ``w`` is an idempotent
projection (a sharp band mask, ``w^2 = w``); for a general ``w`` it is the single-weight pairing
``\\langle f, w g\\rangle`` above, not ``\\lVert w \\star f\\rVert^2``. The co-spectrum-like mixed form is
symmetric in `f`, `g` and may be negative.

Spectral representation only, being a Parseval reduction like the spectral `inner`. It is fused:
the cost is a single weighted pass over the coefficients — the same traffic as one spectral `inner`,
both reducing on the threaded fixed tree since the 2026-08-30 fix, so they agree as
threads are added — and its
only allocation is a small per-axis weight vector (one wavenumber row, not a field). It is thus far cheaper
than the radial reductions [`radial_spectrum`](@ref) / `radial_correlation`, which sweep every mode with
a scatter-add binning pass (and, for the correlation, an inverse transform).
"""
function weighted_inner end

# The weight must be REAL: <f, w g> is an inner product only for a real multiplier, and a complex one
# would otherwise contribute its real part silently — `translation_kernel`'s phase read as a cosine
# attenuation. The rejection is made where the TYPE decides it, so it costs nothing per element: the
# branch is on a compile-time-known eltype and folds away. A `StoredKernel` is the one class whose type
# cannot decide, its storage being `Complex{T}` by construction (a spectral field's is), so a real
# multiplier and a complex one look alike; separating them needs a full extra pass over the
# coefficients, which this reduction's single-pass contract does not permit. That class therefore keeps
# the documented real-part semantics, and it is the only one that does.
# `eltype` of an unmaterialized `Broadcasted` is `Any` — it does not infer — so the multiplier's element
# type comes from `combine_eltypes`, which composes the operand types through `promote_op` and is
# computed from the types alone.
@inline _multiplier_eltype(data::Base.Broadcast.Broadcasted) =
  Base.Broadcast.combine_eltypes(data.f, data.args)
@inline _multiplier_eltype(data) = eltype(data)

@inline _weight_data(w::StoredKernel) = Base.broadcasted(real, _kernel_data(w))

@inline function _weight_data(w::SpectralKernel)
  data = _kernel_data(w)
  _multiplier_eltype(data) <: Real || throw(ArgumentError(
    "weighted_inner needs a real weight, but this $(nameof(typeof(w))) has a complex multiplier " *
    "(element type $(_multiplier_eltype(data))). A complex weight does not define an inner product — " *
    "`translation_kernel`'s phase, for instance, would silently act as its real part, a cosine " *
    "attenuation. Build the weight from a real multiplier (`spectral_cutoff`, `spectral_band`, " *
    "`assignment_window`, or `radial_kernel` with a real symbol)."))
  return data
end



# ── The CPU leg of the weighted reductions ─────────────────────────────────────────────────────────
#
# The weighted inner products were GPU-first: one fused `sum`/`reduce` over a lazy `Broadcasted`,
# which a device parallelizes and a CPU quietly hands to Base's SERIAL cartesian fold. Measured on a
# 9800X3D at ``128^3`` `Float64`, that read 14.7 ms at one thread AND at eight — 70× the same-size
# `inner`, which routes through the fixed-tree reduce — and the consumer's variance controller pays it
# per stage (IT's codegen report, 2026-08-29). This leg gives the weighted family the same
# decision-30/40 split `inner` has: the tree over CONTIGUOUS axis-1 columns, one column per tree
# element, so the summation order is fixed by the tree's own shape and a threaded run stays bitwise
# equal to a serial one.
#
# One reducer serves the single-weight and tuple forms — the single weight is the 1-tuple — which is
# what makes decision 72's promise (the tuple form bitwise-equal to the separate calls) hold BY
# CONSTRUCTION on this path rather than by parallel maintenance of two loops.
#
# The Parseval factor is oriented along the FOLDED axis (decision 41), which may be any of the three:
# along axis 1 it varies within a column and is indexed per element; along axis 2 or 3 it is constant
# per column and is hoisted. A stored weight is indexed linearly down its own contiguous column; a
# compressed weight (radial / product) is a lazy `Broadcasted` and is evaluated per mode through its
# cartesian index — the same value its materialized form stores, so the storage classes stay
# bitwise-equal to each other.

# Per-class element sources. The generic route — `getindex(::Broadcasted, CartesianIndex)` — pays the
# broadcast machinery per element and measured 8.6× the stored class on the radial kernels, which are
# the consumer's hot case (`spectral_band`, the ``|\kappa|^2`` weight). Each source reproduces its
# class's `_kernel_data` expression EXACTLY — the radial one is ``\sigma((s_1+s_2)+s_3)``, the
# left-fold of the three-argument broadcast `+` — so the storage classes stay bitwise-equal to each
# other and to their materialized forms.
struct _StoredWeight{A}; data::A; end
@inline (w::_StoredWeight)(base, i, i2, i3) = @inbounds real(w.data[base + i])

struct _RadialWeight{F, V}; sigma::F; s1::V; s2::V; s3::V; end
@inline (w::_RadialWeight)(base, i, i2, i3) =
  @inbounds w.sigma((w.s1[i] + w.s2[i2]) + w.s3[i3])

struct _LazyWeight{B}; broadcastable::B; end
@inline (w::_LazyWeight)(base, i, i2, i3) = @inbounds w.broadcastable[CartesianIndex(i, i2, i3)]

_cpu_weight(w::StoredKernel) = _StoredWeight(_kernel_data(w))
_cpu_weight(w::RadialKernel) = _RadialWeight(w.sigma, w.multipliers.squared_wavenumber_1,
                                             w.multipliers.squared_wavenumber_2,
                                             w.multipliers.squared_wavenumber_3)
_cpu_weight(w::SpectralKernel) = _LazyWeight(Base.Broadcast.instantiate(_kernel_data(w)))


# One accumulation step over the weight tuple, unrolled by recursion on the tuple itself. A `map`
# with a closure here is the classic boxing trap: the accumulator is reassigned in the loop AND
# captured by the closure, so Julia boxes it and every element allocates — measured at 15 MB per call
# on a ``32^3`` field before this was written out. Recursion on `first`/`tail` carries no closure.
@inline _weighted_step(::Tuple{}, ::Tuple{}, p, d, weight_base, i, i2, i3) = ()
@inline _weighted_step(totals::Tuple, weights::Tuple, p, d, weight_base, i, i2, i3) =
  (first(totals) + p * first(weights)(weight_base, i, i2, i3) * d,
   _weighted_step(Base.tail(totals), Base.tail(weights), p, d, weight_base, i, i2, i3)...)


function _weighted_column(parseval, folded_dimension, weights::WS, a, b, column::Int,
                          n1::Int, n2::Int, weight_columns::Int, ::Val{N}) where {WS <: Tuple, N}
  T = eltype(parseval)
  base = (column - 1) * n1
  weight_column = (column - 1) % weight_columns
  weight_base = weight_column * n1
  i3, i2_zero = divrem(weight_column, n2)
  i2 = i2_zero + 1
  i3 += 1
  totals = ntuple(_ -> zero(T), Val(N))
  if folded_dimension == 1
    # The Parseval factor varies WITHIN the column; branch hoisted to column level so the inner loop
    # carries no per-element conditional.
    @inbounds for i in 1:n1
      p = parseval[i]
      d = real(a[base + i] * conj(b[base + i]))
      totals = _weighted_step(totals, weights, p, d, weight_base, i, i2, i3)
    end
  else
    pv_column = folded_dimension == 2 ? (@inbounds parseval[i2]) : (@inbounds parseval[i3])
    @inbounds for i in 1:n1
      d = real(a[base + i] * conj(b[base + i]))
      totals = _weighted_step(totals, weights, pv_column, d, weight_base, i, i2, i3)
    end
  end
  return totals
end


function _weighted_totals_cpu(a, b, parseval, folded_dimension::Int,
                              weights::WS, ::Val{N}) where {WS <: Tuple, N}
  n1, n2, n3 = size(a, 1), size(a, 2), size(a, 3)
  weight_columns = n2 * n3
  total_columns = div(length(a), n1)
  pv = vec(parseval)
  element = column -> _weighted_column(pv, folded_dimension, weights, a, b, column,
                                       n1, n2, weight_columns, Val(N))
  return _indexed_tree_reduce(element, (x, y) -> map(+, x, y), 1, total_columns)
end


function weighted_inner(f::AbstractFieldSpectral{T}, g::AbstractFieldSpectral{T},
                        w::SpectralKernel{T}) where {T<:AbstractFloat}
  _check_field_domain_compatibility(f, g)
  _check_kernel_compatibility(f, w)
  field_tensor_order(f) == field_tensor_order(g) ||
    throw(ArgumentError("weighted_inner(f, g, w) needs equal tensor orders " *
                        "(got $(field_tensor_order(f)) and $(field_tensor_order(g)))"))
  # α(k)·w(k): the rfft Parseval weight times the real multiplier, an (Nkx, Ny, Nz) factor that broadcasts
  # over the fiber (trailing singleton dims). Re(f̂_c conj ĝ_c) is the per-mode co-energy density. The whole
  # reduction is one fused `sum` over a lazy `Broadcasted` — no per-mode field is built, only
  # `_parseval_weight`'s tiny (Nkx,) vector is allocated. The `Base.Broadcast.instantiate` is load-bearing on
  # the GPU: `sum`/`mapreduce` over a `Broadcasted` needs its `axes` computed, and an unmaterialized
  # `Base.broadcasted(...)` carries `Nothing` axes, so AMDGPU's `mapreducedim!` throws `axes(::Broadcasted, ::Int)`
  # (CPU tolerates it; the GPU does not). `instantiate` fills the axes without materializing, keeping the
  # reduction fused on both backends.
  normalization = T(prod(field_grid(f).grid_size))^2
  weight_lazy = _weight_data(w)                   # the complex-multiplier refusal runs here
  if KernelAbstractions.get_backend(field_data(f)) isa KernelAbstractions.CPU
    totals = _weighted_totals_cpu(field_data(f), field_data(g), _parseval_weight(f),
                                  field_layout(f).fft_dims[1], (_cpu_weight(w),), Val(1))
    return totals[1] / normalization
  end
  weight = Base.broadcasted(*, _parseval_weight(f), weight_lazy)
  density = Base.broadcasted(real, Base.broadcasted(*, field_data(f), Base.broadcasted(conj, field_data(g))))
  return sum(Base.Broadcast.instantiate(Base.broadcasted(*, weight, density))) / normalization
end

weighted_inner(f::AbstractFieldSpectral{T}, w::SpectralKernel{T}) where {T<:AbstractFloat} =
  weighted_inner(f, f, w)


# SEVERAL WEIGHTS, ONE TRAVERSAL (decision 72). The per-mode energy density is read and formed once and
# then multiplied by each weight, where n separate calls would read the coefficient array n times and,
# on a device, block n times to bring n numbers back. The consuming solver's variance controller wants
# exactly three of these per stage — the whole field, a forced band, and |κ|² — and it is the return
# to the host, not the arithmetic, that it is paying for.
#
# The tuple accumulator is what makes one pass possible, and its spelling is not free to choose: a
# `zip` of the operands falls back to SCALAR INDEXING and dies under `allowscalar(false)`, while
# broadcasting into an `NTuple` and reducing with a tuple `+` stays on the device. Measured on an RTX
# 5070 Ti against three separate passes: 2.14x at 128^3 and 1.79x at 256^3, before counting the two
# synchronizations that stop happening.
function weighted_inner(f::AbstractFieldSpectral{T},
                        weights::Tuple{Vararg{SpectralKernel{T}}}) where {T<:AbstractFloat}
  # No weights is not an error, it is no questions asked — and answering it without touching the field
  # keeps the degenerate case from reaching a broadcast that has nothing to broadcast over.
  isempty(weights) && return ()
  foreach(w -> _check_kernel_compatibility(f, w), weights)
  weight_data = map(_weight_data, weights)          # each one's complex-multiplier refusal runs here
  parseval = _parseval_weight(f)
  normalization = T(prod(field_grid(f).grid_size))^2
  if KernelAbstractions.get_backend(field_data(f)) isa KernelAbstractions.CPU
    totals = _weighted_totals_cpu(field_data(f), field_data(f), parseval,
                                  field_layout(f).fft_dims[1], map(_cpu_weight, weights),
                                  Val(length(weights)))
    return map(total -> total / normalization, totals)
  end
  density = Base.broadcasted(abs2, field_data(f))
  # One element of the pass yields one value per weight. `map` over the tuple keeps the closure generic
  # in the count while staying isbits, which is what the device reduction requires.
  packed = Base.broadcasted((d, p, ws...) -> map(w -> p * w * d, ws), density, parseval, weight_data...)
  zeros_tuple = ntuple(_ -> zero(T), length(weights))
  totals = reduce((a, b) -> map(+, a, b), Base.Broadcast.instantiate(packed); init = zeros_tuple)
  return map(total -> total / normalization, totals)
end


# =============================================================================
# Radial shell binning — the device-friendly histogram shared by the spectrum
# (|k|-shells) and the correlation (|r|-shells). Fully fused (decision 34): each
# kernel derives its shell index, fiber contraction, and weight from the mode or
# grid index inline, so no shell-index, magnitude, or weighted full-grid array is
# ever materialized — the only per-call arrays are the tiny shell accumulators.
# =============================================================================

# The fiber-contracted density of one mode: |f̂|² for the power spectrum (no second field), or
# Re(f̂ · conj ĝ) for the cross-power. Dispatch on Nothing compiles the branch away, as
# `_optional_kernel_value` does for the operator kernels.
@inline _mode_density(value, ::Nothing, mode_1, mode_2, mode_3, component) = abs2(value)
@inline _mode_density(value, g_data, mode_1, mode_2, mode_3, component) =
  @inbounds real(value * conj(g_data[mode_1, mode_2, mode_3, component]))


# One work-item per stored mode: derive |k| from the three 1-D squared-wavenumber arrays (the same
# left-associated sum the lazy |k|² broadcast evaluates), contract the fiber inline, weight by the
# rfft Parseval factor computed from the folded-axis plane index (1 on that axis's zero plane and,
# when it is even, its Nyquist plane; 2 otherwise — the folded dimension arrives as a `Val`,
# decision 41), and scatter-add into the shell accumulator. Atomic adds, exactly
# like the anterpolation scatter. This replaces the former staged route (a materialized shell-index
# array, a fiber-contracted magnitude array, and a Parseval-weighted array — three full spectral
# planes per call); the wedge history of the per-shell masked route it in turn replaced is decision 25.
@kernel function _spectral_shell_bin_kernel!(value_bins, @Const(f_data), g_data,
    @Const(squared_wavenumber_1), @Const(squared_wavenumber_2), @Const(squared_wavenumber_3),
    fundamental, nyquist_index, ::Val{FD}, ::Val{NC}) where {FD, NC}
  mode_1, mode_2, mode_3 = @index(Global, NTuple)
  @inbounds begin
    squared = squared_wavenumber_1[mode_1] + squared_wavenumber_2[mode_2] + squared_wavenumber_3[mode_3]
    shell = round(Int, sqrt(squared) / fundamental)
    folded_mode = FD == 1 ? mode_1 : FD == 2 ? mode_2 : mode_3
    weight = ifelse(folded_mode == 1 || folded_mode == nyquist_index,
                    one(fundamental), one(fundamental) + one(fundamental))
    accumulated = zero(fundamental)
    for component in 1:NC
      accumulated += _mode_density(f_data[mode_1, mode_2, mode_3, component], g_data,
                                   mode_1, mode_2, mode_3, component)
    end
    Atomix.@atomic value_bins[shell + 1] += weight * accumulated
  end
end


# Shared |k|-shell binning for the power/cross-power spectra: one fused scatter-add pass over the
# stored modes (`g` is `nothing` for the power spectrum, the second field for the cross-power).
# Normalize by N² and sum the modes whose rounded |k| falls in each shell; shells run 0…corner at the
# box-fundamental width, so ∑ over shells = the spectral `inner` exactly. The shell count comes from
# the corner mode analytically: the separable |k|² is maximized componentwise, so its corner value is
# the sum of the three per-axis maxima (three O(N) reductions over the 1-D multiplier arrays —
# bitwise the same sum the kernel forms for that mode, so no bin can overflow).
function _radial_spectrum_bin(f::AbstractFieldSpectral{T}, g,
                              multipliers::FieldSpectralMultipliers) where {T<:AbstractFloat}
  _check_multipliers_compatibility(f, multipliers)
  grid = field_grid(f)
  fundamental = 2 * T(π) / T(maximum(grid.domain_size))           # the unit shell width (= 1 for a 2π box)
  corner_squared = maximum(multipliers.squared_wavenumber_1) + maximum(multipliers.squared_wavenumber_2) +
                   maximum(multipliers.squared_wavenumber_3)
  number_of_shells = round(Int, sqrt(corner_squared) / fundamental) + 1

  spatial_shape = size(field_data(f))[1:3]
  components = length(field_data(f)) ÷ prod(spatial_shape)
  f_data = reshape(field_data(f), spatial_shape..., components)
  g_data = g === nothing ? nothing : reshape(field_data(g), spatial_shape..., components)
  folded_dimension = field_layout(f).fft_dims[1]
  nyquist_index = iseven(grid.grid_size[folded_dimension]) ? spatial_shape[folded_dimension] : 0

  backend = get_backend(field_data(f))
  value_bins = similar(field_data(f), T, number_of_shells)
  fill!(value_bins, zero(T))
  _spectral_shell_bin_kernel!(backend)(value_bins, f_data, g_data,
    multipliers.squared_wavenumber_1, multipliers.squared_wavenumber_2, multipliers.squared_wavenumber_3,
    fundamental, nyquist_index, Val(folded_dimension), Val(components); ndrange = spatial_shape)
  synchronize(backend)

  spectrum = Array(value_bins) ./ T(prod(grid.grid_size))^2
  shells = T.(0:(number_of_shells - 1)) .* fundamental
  return shells, spectrum
end


"""
    radial_spectrum(f, multipliers)
    radial_spectrum(f, g, multipliers)

The **radial (shell-binned) power spectrum** resolves a field's L² energy over wavenumber-magnitude
shells. Write ``P(\\kappa)`` for the one-argument **power spectrum** and ``P_{fg}(\\kappa)`` for the
two-argument **co-spectrum** (cross-power) of two compatible, equal-order fields.

The arguments are:
- `f`, `g` — the fields, in spectral representation; the two-argument form takes them compatible and of equal tensor order.
- `multipliers` — the per-axis wavenumbers ``k`` for the field's grid ([`FieldSpectralMultipliers`](@ref)).

It returns `(shells, spectrum)`, a pair of `Vector{T}` in the section's own scalar type and on the
**host** whatever backend the field lives on (the shell accumulators are small and are brought back).
Here `shells` are the bin-center
wavenumber magnitudes ``\\kappa`` and `spectrum[i]` sums the Parseval-weighted fiber (co-)energy over the
modes whose rounded magnitude falls in shell ``i``:

The shells are CENTRED on their nominal wavenumber — shell ``m`` collects
``\\lvert k\\rvert`` within ``\\pm\\Delta\\kappa/2`` of ``m\\Delta\\kappa`` — which is what makes
``\\kappa_m`` an energy-density sample AT ``\\kappa_m`` rather than at the band's edge. The abscissa is a
property of the grid alone, identical for every field on it, so two spectra are directly comparable and a
co-spectrum (which may be negative) is handled by the same rule.

!!! note "For an exact spectral moment, do not weight the abscissa"
    Reporting each shell's energy-weighted mean wavenumber would make the first moment
    ``\\sum_m \\kappa_m E(\\kappa_m)`` exact, but it is the wrong tool: the abscissa would then depend on
    the field, so two spectra on one grid would arrive on different ``\\kappa`` grids, and a co-spectrum
    would divide by a weight that can vanish or change sign. Take the moment directly instead —
    [`weighted_inner`](@ref) against a radial symbol is exact and involves no binning at all:

    ```julia
    weighted_inner(f, radial_kernel(k2 -> sqrt(k2), multipliers))   # ⟨f, |k| f⟩, exactly
    weighted_inner(f, radial_kernel(identity, multipliers))         # ⟨f, −Δf⟩, the Dirichlet energy
    ```

Given a **tuple of weights** it answers all of them in **one traversal**, returning one value per
weight in the order they were given:

    whole, band, dissipation = weighted_inner(f, (unit, band_kernel, squared_wavenumber))

Reach for that when several weighted inners of the same field are wanted together. It reads the
coefficients once instead of once per weight, and — the reason it exists — returns a single tuple
rather than a scalar at a time, so a device is asked for its answer once rather than blocking on each.
The results are **bitwise identical** to the separate calls; only the pass is shared. An empty tuple
answers `()` without touching the field, and every refusal the single-weight form makes is made here
in any position.

!!! note "The unit weight and `inner` agree numerically, not bitwise"
    ``\\langle f, 1 \\cdot f\\rangle`` is ``\\langle f, f\\rangle``, so a unit weight reproduces
    [`inner`](@ref) — to about ``10^{-14}`` relative, not to the last bit, because `inner` reduces on
    the threaded fixed tree while this pass does not. Worth knowing when replacing one with the other
    in code that compares against a stored number.

```math
\\begin{gathered}
P(\\kappa_i) = \\frac{1}{N^2} \\sum_{\\substack{k  :  \\mathrm{round}(|k|/\\Delta k) = i}} \\alpha(k) \\sum_c |\\hat f_c(k)|^2, \\\\
P_{fg}(\\kappa_i) = \\frac{1}{N^2} \\sum_{\\substack{k  :  \\mathrm{round}(|k|/\\Delta k) = i}} \\alpha(k) \\sum_c \\mathrm{Re}\\bigl(\\hat f_c(k) \\overline{\\hat g_c(k)}\\bigr),
\\end{gathered}
```

with ``c`` indexing the fiber components, ``\\alpha(k)`` the rfft half-spectrum Parseval weight (``1`` on
the folded axis's zero and even-length Nyquist planes, ``2`` otherwise — the folded rfft axis is the
layout's `fft_dims[1]`), and shell width ``\\Delta k`` (the box
fundamental). Each form **refines** [`inner`](@ref):
``\\sum_\\kappa P(\\kappa) = \\langle f, f\\rangle`` and ``\\sum_\\kappa P_{fg}(\\kappa) = \\langle f, g\\rangle``
— the L² (co-)energy split across isotropic ``|k|``-shells one fundamental wavenumber wide (the box's smallest nonzero wavenumber, ``\\Delta k = 2\\pi / \\max_a L_a``). The one-argument
form is the ``g = f`` case (``\\mathrm{Re}(\\hat f \\overline{\\hat f}) = |\\hat f|^2``); the co-spectrum
is **symmetric** (``P_{fg} = P_{gf}``, ``\\mathrm{Re}`` being conjugation-symmetric) and, unlike the power
spectrum, **may be negative** in a shell (anticorrelated modes). The consumer's physics kinetic-energy
spectrum is ``E(\\kappa) = \\tfrac{1}{2} P(\\kappa)`` (it integrates to the turbulent kinetic energy, half
the L² energy); the package keeps the neutral power-spectrum name, physics stays consumer-side.

This reduction acts on the spectral representation only, being a Parseval reduction like the spectral
`inner`. Shells run from ``0`` to the corner wavenumber, so the sum covers *all* modes (an exact `inner`
refinement); on a de-aliased field the high-``|k|`` shells are empty. On a non-cubic box the shells
beyond the inscribed sphere of the sampled band — shell index ``\\min_a k_a^{\\mathrm{Nyq}} / \\Delta k``,
with ``k_a^{\\mathrm{Nyq}} = \\lfloor N_a/2 \\rfloor 2\\pi/L_a`` the per-axis Nyquist wavenumber — are
incompletely sampled (only corner modes contribute), the standard isotropic-spectrum caveat; the total
still equals `inner`. The shell **width** carries a second anisotropy artefact worth knowing: ``\\Delta k``
is taken from the box's largest side, so on a strongly anisotropic box it is finer than the mode spacing
``2\\pi/L_a`` along every shorter axis, and a systematic fraction of shells is then empty — the profile
combs, though its sum is unaffected. The two shells meet at a half-integer ``|k|/\\Delta k``, which an anisotropic box hits exactly; such a mode is assigned by `round`'s **ties-to-even**, so the boundary belongs to neither shell by a fixed convention but to whichever has even index. The interval is deliberately not written half-open for that reason — a half-open bracket would claim round-half-up, which is not what the code does. The reduction is GPU-portable: a single
scatter-add binning pass over the modes that derives each mode's shell, fiber contraction, and
Parseval weight from its index — no full-grid staging array is built — costing more than a plain
reduction like `inner` only by the binning — whose accumulators take atomic (concurrency-safe) updates,
since several modes land in one shell — and a square root per mode.
"""
function radial_spectrum end

function radial_spectrum(f::AbstractFieldSpectral{T}, multipliers::FieldSpectralMultipliers) where {T<:AbstractFloat}
  # The fiber contraction Σ_c |f̂_c|² happens inside the binning kernel — nothing is materialized.
  return _radial_spectrum_bin(f, nothing, multipliers)
end

function radial_spectrum(f::AbstractFieldSpectral{T}, g::AbstractFieldSpectral{T},
                         multipliers::FieldSpectralMultipliers) where {T<:AbstractFloat}
  _check_field_domain_compatibility(f, g)
  field_tensor_order(f) == field_tensor_order(g) ||
    throw(ArgumentError("radial_spectrum(f, g, multipliers) needs equal tensor orders " *
                        "(got $(field_tensor_order(f)) and $(field_tensor_order(g)))"))
  # The fiber contraction Σ_c Re(f̂_c · conj(ĝ_c)) happens inside the binning kernel.
  return _radial_spectrum_bin(f, g, multipliers)
end


# One work-item per grid point: the minimum-image separation is derived from the index — along axis
# a the separation index is min(i − 1, Nₐ − (i − 1)), scaled by the spacing Δxₐ, so distances fold at
# the half-box (the autocorrelation is periodic and even) — the fiber is contracted inline, and the
# value and a population count are scatter-added into the |r|-shell accumulators. No separation,
# shell-index, or fiber-contracted array is materialized; the counts feed the shell average.
@kernel function _physical_shell_bin_kernel!(value_bins, count_bins, @Const(data),
    spacing_1, spacing_2, spacing_3, points_1, points_2, points_3, bin_width, ::Val{NC}) where {NC}
  index_1, index_2, index_3 = @index(Global, NTuple)
  @inbounds begin
    distance_1 = min(index_1 - 1, points_1 - (index_1 - 1)) * spacing_1
    distance_2 = min(index_2 - 1, points_2 - (index_2 - 1)) * spacing_2
    distance_3 = min(index_3 - 1, points_3 - (index_3 - 1)) * spacing_3
    separation = sqrt(distance_1^2 + distance_2^2 + distance_3^2)
    shell = round(Int, separation / bin_width)
    accumulated = zero(bin_width)
    for component in 1:NC
      accumulated += data[index_1, index_2, index_3, component]
    end
    Atomix.@atomic value_bins[shell + 1] += accumulated
    Atomix.@atomic count_bins[shell + 1] += 1
  end
end


# Radially average a real physical correlation field — handed as the raw (Nx, Ny, Nz[, fiber]) c2r
# output, its fiber contracted inside the kernel — over minimum-image |r| shells (bin width = the
# finest grid spacing): the shared back half of both `radial_correlation` methods, one fused
# scatter-add pass. The ±r folding of the min-image shells symmetrizes the cross-correlation
# (C_fg(−r) = C_gf(r)). The 1/N correlation normalization is folded into the per-shell average
# (bins are tiny), and the shell count comes from the corner analytically — the same
# min(i, N − i)·Δx maximum, attained at i = N ÷ 2 per axis, that the kernel computes for that point.
function _radial_average(grid, correlation_data::AbstractArray{T}, number_of_points) where {T<:AbstractFloat}
  bin_width = T(minimum(grid.grid_spacing))
  corner_1 = T(grid.grid_size[1] ÷ 2) * T(grid.grid_spacing[1])
  corner_2 = T(grid.grid_size[2] ÷ 2) * T(grid.grid_spacing[2])
  corner_3 = T(grid.grid_size[3] ÷ 2) * T(grid.grid_spacing[3])
  corner = sqrt(corner_1^2 + corner_2^2 + corner_3^2)
  number_of_shells = round(Int, corner / bin_width) + 1
  separations = T.(0:(number_of_shells - 1)) .* bin_width

  spatial_shape = size(correlation_data)[1:3]
  components = length(correlation_data) ÷ prod(spatial_shape)
  data = reshape(correlation_data, spatial_shape..., components)

  backend = get_backend(correlation_data)
  value_bins = similar(correlation_data, T, number_of_shells)
  count_bins = similar(correlation_data, Int, number_of_shells)
  fill!(value_bins, zero(T))
  fill!(count_bins, 0)
  _physical_shell_bin_kernel!(backend)(value_bins, count_bins, data,
    T(grid.grid_spacing[1]), T(grid.grid_spacing[2]), T(grid.grid_spacing[3]),
    grid.grid_size[1], grid.grid_size[2], grid.grid_size[3], bin_width, Val(components);
    ndrange = spatial_shape)
  synchronize(backend)

  shell_sum, population = Array(value_bins), Array(count_bins)
  correlation = [iszero(population[s]) ? zero(T) : shell_sum[s] / population[s] / T(number_of_points)
                 for s in 1:number_of_shells]
  return separations, correlation
end


"""
    radial_correlation(f, plans)
    radial_correlation(f, g, plans)

The **radial (shell-averaged) two-point correlation** of a field is the physical-space dual of
[`radial_spectrum`](@ref) under the Wiener–Khinchin theorem — the statement that the autocorrelation
and the power spectrum are a Fourier-transform pair. The one-argument form is the **autocorrelation** ``C(r)``, and the
two-argument form is the **cross-correlation** ``C_{fg}(r) = \\langle f(x)\\cdot g(x+r)\\rangle`` of two
compatible, equal-order fields.

The arguments are:
- `f`, `g` — the fields, in spectral representation; the two-argument form takes them compatible and of equal tensor order.
- `plans` — transform plans for their grid and layout; a pair carries no tensor order and serves every rank.

It takes `plans` where its Fourier dual `radial_spectrum` takes `multipliers`, the one asymmetry in an
otherwise mirrored pair: the spectrum weighs each mode where it already sits, while the correlation
must come back to physical space, and an inverse transform needs a plan.

It returns `(separations, correlation)`, a pair of host `Vector{T}` in the section's scalar type, as
`radial_spectrum` does, where
`separations` are the
bin-center magnitudes ``r`` and `correlation[i]` is the value averaged over the minimum-image shell (each separation taken as its nearest periodic
replica, so no distance exceeds half the box)
``|r| \\approx r``. By the (cross-)correlation theorem the kernel forms the fiber-summed (cross-)power
spectrum, inverse-transforms it, and normalizes:

```math
\\begin{gathered}
C(r) = \\frac{1}{N} \\sum_x f(x)\\cdot f(x+r) = \\frac{1}{N} \\mathcal F^{-1}\\Bigl(\\textstyle\\sum_c |\\hat f_c|^2\\Bigr)(r), \\\\
C_{fg}(r) = \\frac{1}{N} \\sum_x f(x)\\cdot g(x+r) = \\frac{1}{N} \\mathcal F^{-1}\\Bigl(\\textstyle\\sum_c \\overline{\\hat f_c} \\hat g_c\\Bigr)(r),
\\end{gathered}
```

with ``c`` indexing the fiber components, followed by the shell average
``C(r_i) = |\\text{shell } i|^{-1} \\sum_{|r| \\approx r_i} C(r)``. At zero
separation each is [`inner`](@ref): ``C(0) = \\langle |f|^2\\rangle = \\texttt{inner}(f, f)`` and
``C_{fg}(0) = \\langle f\\cdot g\\rangle = \\texttt{inner}(f, g)`` — `inner` resolved over physical
separation, exactly as `radial_spectrum` resolves it over ``|k|`` (a Fourier pair up to the convention's
``1/N``: ``\\mathcal F C = |\\hat f|^2/N``, ``\\mathcal F C_{fg} = \\overline{\\hat f} \\hat g/N``). The one-argument form is the ``g = f`` case; the
radial binning **symmetrizes** the cross-correlation — the ``\\pm r`` folding of the min-image shells
averages ``C_{fg}(r)`` with ``C_{fg}(-r) = C_{gf}(r)``, so the result equals ``\\tfrac{1}{2}(C_{fg} + C_{gf})``
and is symmetric in ``f, g``.

Separations run from ``0`` to the minimum-image **corner** ``\\sqrt{\\sum_a r_a^2}``, with the per-axis
reach ``r_a = \\lfloor N_a/2\\rfloor \\Delta x_a`` (``= L_a/2`` on an even axis, half a cell less on an
odd one; ``\\sqrt{3} L/2`` for an even cubic box) at the finest spacing ``\\min_a \\Delta x_a``, the
``\\min(i, N_a - i)`` fold making ``C`` periodic and even (``C(r) = C(L - r)``). This is the
physical-space mirror of the spectrum's corner caveat: only ``|r| \\le \\min_a r_a`` — the sphere
inscribed in the min-image box — is sampled in *all*
directions; shells from there out to the corner keep only the box-diagonal directions (incompletely
sampled). And in a finite periodic box the large-``r`` tail is itself an artifact — there ``C`` reflects
the field correlating with its own periodic image, not a true infinite-domain correlation — so a consumer
extracts an integral scale (the area under the normalized correlation curve) only out to where ``C``
has decayed (e.g. the first zero crossing), not the full
curve. As with the spectrum the *total* is unaffected: ``C(0) = \\texttt{inner}(f, f)`` exactly.

It takes spectral input only, since it needs the inverse transform, and it is GPU-portable: one inverse
transform plus a single binning pass.

!!! note "This one allocates a field, unlike `radial_spectrum`"
    Its route builds a full power field and takes an allocating inverse transform, so it costs a
    field's worth of memory per call — a deliberate exception to the package's allocation-free
    default, guarded by a bounded rather than a zero assertion; `radial_spectrum` has no such
    cost, its staging having been fused into the binning kernel, leaving only the shell accumulators.
"""
function radial_correlation end

function radial_correlation(f::AbstractFieldSpectral{T}, plans::FieldTransformPlans) where {T<:AbstractFloat}
  # Power spectrum per fiber component, |f̂_c(k)|² (real, in the complex coefficient array; Hermitian,
  # so the c2r reconstruction below is exactly real). The transform output is the one materialized
  # field; its fiber contraction and 1/N normalization happen inside the binning.
  power = similar_field(f, Val(field_tensor_order(f)))
  @_assign! field_data(power) .= complex.(abs2.(field_data(f)))
  autocorrelation = to_physical(power, plans)                    # c2r per component (unnormalized)
  return _radial_average(field_grid(f), field_data(autocorrelation), prod(field_grid(f).grid_size))
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
  crosscorrelation = to_physical(power, plans)
  return _radial_average(field_grid(f), field_data(crosscorrelation), prod(field_grid(f).grid_size))
end


"""
    lpnorm(f, p = 2)

The **normalized ``L^p`` norm** ``\\lVert f\\rVert_p`` of a section (`lpnorm` ``\\equiv \\lVert\\cdot\\rVert_p``),
where ``|f|`` is the pointwise fiber magnitude (the fiberwise `norm`) — the ``L^p`` average of ``|f|`` over
the base. The exponent `p` selects the norm: `p = 2` (the default) reduces to [`l2norm`](@ref), and
`p = Inf` gives the supremum of the fiber magnitude (for example the maximum speed entering a CFL
time-step bound).
On a grid the average is the equal-weight sum over the ``N`` cells; on a point-set it is the sum over the
``M`` points:

```math
\\begin{aligned}
\\lVert f\\rVert_p &= \\Bigl(\\frac{1}{N} \\sum_x |f(x)|^p\\Bigr)^{1/p} && (\\texttt{Grid3D}), \\\\
\\lVert f\\rVert_p &= \\Bigl(\\frac{1}{M} \\sum_i |f_i|^p\\Bigr)^{1/p} && (\\texttt{PointSet}), \\\\
\\lVert f\\rVert_\\infty &= \\sup_{x} |f(x)| = \\max_x |f(x)|, &&
\\end{aligned}
```

It is physical-space only at every exponent, `p = 2` included; for a field in spectral representation use
[`l2norm`](@ref), which reads the same value off the coefficients through Parseval.

The exponent `p` must satisfy ``1 \\le p \\le \\infty``; outside that range the expression is not a norm
and the call raises rather than returning a plausible number. The result carries the section's own
element type — a `Float32` section gives a `Float32` norm at every exponent.
"""
function lpnorm(section::ReducibleSection, p::Real = 2)
  # The domain is 1 <= p <= Inf, where the expression below is a norm. Outside it the formula still
  # evaluates and returns something plausible, which is the problem: p = -Inf was treated as a
  # maximum, p = 0 gave exactly 1 for every input, and a negative p produced a finite number that
  # satisfies no norm axiom. A quantity that is not a norm must not be returned by `lpnorm`.
  (p >= 1 && !isnan(p)) ||
    throw(ArgumentError("lpnorm requires 1 <= p <= Inf; got p = $p"))
  p == 2 && return l2norm(section)
  magnitude = field_data(LinearAlgebra.norm(section))      # pointwise fiber magnitude (fiberwise norm)
  isinf(p) && return maximum(magnitude)
  # The exponents are converted to the section's own scalar type. Written as `1 / p` they are `Float64`
  # whatever the section holds, and `Float32 ^ Float64` widens — so a `Float32` field returned a
  # `Float64` norm for every `p` except the two that return early, which is both a lost element type and
  # the `Union{Float32, Float64}` inference the survey reports.
  scalar = section_scalar_type(section)
  exponent = scalar(p)
  return (sum(magnitude .^ exponent) / _base_count(section))^(one(scalar) / exponent)
end


# `maximum`/`minimum`/`extrema` (extending Base) — the L∞ end, for scalar sections only (the sup of a
# vector/tensor magnitude is `lpnorm(f, Inf)`, deliberately not an ambiguous `maximum` of components).
_tree_extreme(data, combine::C) where {C} = _tree_extreme(KernelAbstractions.get_backend(data), data, combine)
# An order statistic has no neutral element: an empty section throws, mirroring Base's
# empty-collection contract and the device branch — never a fabricated zero (decision 43).
_tree_extreme(::KernelAbstractions.CPU, data, combine::C) where {C} =
  isempty(data) ? throw(ArgumentError("reducing over an empty section is not allowed")) :
  _indexed_tree_reduce(index -> (@inbounds data[index]), combine, 1, length(data))
_tree_extreme(::Any, data, combine::C) where {C} = reduce(combine, data)   # the device's own reduce

for (reducer, combine) in ((:maximum, :max), (:minimum, :min))
  @eval $reducer(field::AbstractFieldPhysical{T, 0}) where {T} = _tree_extreme(field_data(field), $combine)
  @eval $reducer(values::AbstractPointValues{T, 0}) where {T} = _tree_extreme(field_data(values), $combine)
end
# Two fixed-tree passes, matching the mapped extrema's recorded two-pass stance.
extrema(field::AbstractFieldPhysical{T, 0}) where {T} = (minimum(field), maximum(field))
extrema(values::AbstractPointValues{T, 0}) where {T} = (minimum(values), maximum(values))
# `maximum`/`minimum` are absent above R = 0 by not being defined there, which is enough because `Base`
# has no fallback that would accept a section. `extrema` DOES have one — it would iterate and return a
# per-component pair, exactly the ill-posed answer the restriction exists to refuse — so the absence has
# to be stated explicitly here rather than left to dispatch (decision 52).
extrema(section::AbstractFiberSection) =
  throw(ArgumentError("`extrema` is defined for scalar sections only; name a fiber map, as in `extrema(norm, u)`, which makes the order statistic well posed at any tensor order"))

# The mapped forms carry no such restriction, at every order the reductions serve (R <= 2): naming the fiber map is what
# removes the ambiguity the bare forms refuse to guess, so `maximum(norm, u)` is well posed where
# `maximum(u)` is not — and it fuses, where the equivalent `lpnorm(u, Inf)` materializes a magnitude
# section first.
for (reducer, combine) in ((:maximum, :max), (:minimum, :min))
  @eval $reducer(fiber_map::FiberMap, section::ReducibleSection) where {FiberMap} =
    _fiber_mapreduce(fiber_map, $combine, section)
end

# Two passes rather than one. A single-pass form is available — reduce pairs under `Base._extrema_rf`,
# for which the GPU backend does register a neutral element — but that is an undocumented Base internal,
# and a reduction that costs one extra streaming pass is not worth taking a dependency on a name Base
# may rename. A custom pair-combiner is not an escape: the GPU path demands an explicit neutral element
# for any operator outside its known set, and that would have to be built from `fiber_map`'s result
# type, which is not knowable here.
extrema(fiber_map::FiberMap, section::ReducibleSection) where {FiberMap} =
  (minimum(fiber_map, section), maximum(fiber_map, section))


end # module Reductions
