"""
    FiberSections

It is the fiber-bundle model's base-agnostic core.

A field (a section over a `Grid3D`) and a collection of off-grid point-values (a section over a
`PointSet`) are both sections of a tensor bundle over a base. This module owns the part of the
design that does not depend on which base is used. The parts are:

- the **fiber types** — [`FiberVector`](@ref), [`FiberTensor2`](@ref), [`FiberTensor3`](@ref) and
  [`FiberTensor4`](@ref), `StaticArrays` aliases naming the value at one base point, together with
  [`fiber_shape`](@ref). A fiber is base-agnostic by construction, so it belongs here and both the
  field and point layers take their fiber vocabulary from this module;
- the [`AbstractFiberSection`](@ref) supertype, which both fields and point-values subtype;
- the CPU-threading, fused-assignment primitive [`_assign!`](@ref) and its policy controls
  ([`with_threading`](@ref), [`threading_cutoff`](@ref), and [`set_threading_cutoff!`](@ref));
- the fiberwise-algebra code generators — the per-component builders behind operations such as `dot`, `cross`, and `norm` —
  written once here so that one set of generated kernels serves both field and point-value
  sections;
- the fused fiberwise executor [`_fiberwise_pass!`](@ref) — one portable kernel and one
  CPU loop threaded over slabs, running every stamped **values function**, a pure scalar function taking
  one element per input and returning its outputs, the route for multi-output fiberwise
  operations;
- the **fiber adapter** behind `map!`/`map` — the pure-fiber wrapper that assembles a base point's
  components into a fiber, applies the caller's function, and flattens the result back, so an
  arbitrary fiber map rides the same executor as the generated algebra.

The base-specific halves live elsewhere. [`Fields`](@ref "Fields") (grid) and
[`Points`](@ref "Points") (point set) hold the
concrete section types, the section-interface accessors (`field_data`, `_vector_component_data`,
and `_tensor2_component_data`) and the broadcast styles, each extending the accessors for its own
types, while [`FieldAlgebra`](@ref "FieldAlgebra") and `Points` stamp the method tables from the
builders here.
"""
module FiberSections

using Base.ScopedValues: ScopedValue

# The fused fiberwise executor below launches one portable KernelAbstractions kernel on a device
# and a slab-threaded plain loop on the CPU, dispatched on the backend (the decision-30 idiom;
# the `import` carries `KernelAbstractions.CPU` for that dispatch).
import KernelAbstractions
using KernelAbstractions: @kernel, @index, get_backend, synchronize

# The `map!` adapter below assembles fiber values (a `SVector` / `SMatrix`) from the flat component
# scalars a fused pass hands it, applies the user map, and flattens the result — so it constructs the
# fiber static arrays directly.
using StaticArrays: SVector, SMatrix, SArray, StaticArray

export AbstractFiberSection,
       FiberVector,
       FiberTensor2,
       FiberTensor3,
       FiberTensor4,
       fiber_shape,
       with_threading,
       set_threading_cutoff!,
       threading_cutoff


"""
    AbstractFiberSection{T, R}

Supertype of every section of the package's tensor bundle, so both fields (sections over a
`Grid3D`, in physical-space or spectral representation) and point-values (sections over a
`PointSet`) subtype it.

The parameter `T<:AbstractFloat` is the real scalar type, and `R` is the tensor order (`0`
scalar, `1` vector, `2` second-order tensor, and so on). The fiberwise algebra is rooted at this
supertype because it is base-independent: it applies the same operation to the same fiber type
whether the base is a structured grid or an unstructured point set.
"""
abstract type AbstractFiberSection{T<:AbstractFloat, R} end


"""
    _section_scalar_type(section::AbstractFiberSection)

Return the real scalar type `T` of any section. Because it is defined once on
`AbstractFiberSection{T}`, it yields the real `T` for fields (including those in spectral representation, whose
data is `Complex{T}`) and for point-values alike, which lets the shared `sym`/`skew`/`dev`
kernels obtain `T` without dispatching on the concrete base.
"""
_section_scalar_type(::AbstractFiberSection{T}) where {T<:AbstractFloat} = T


"""
    _section_tensor_order(section)

Return a section's tensor order ``R``, read from its type. The peer of
[`_section_scalar_type`](@ref): both are type parameters, so a compatibility check written against
them costs nothing at run time.
"""
_section_tensor_order(::AbstractFiberSection{T, R}) where {T<:AbstractFloat, R} = R


"""
    _check_owned_storage(data, what::AbstractString)

Reject storage that does not own its memory — a `SubArray` anywhere in the parent chain — so that two
sections can share storage only by being backed by the *same* array.

A section over a view is not a construction this package has a use for. Nothing in the library builds
one; there is no verb that returns one; and on a periodic domain it is not even meaningful, since a
sub-block of a periodic base is not itself periodic and a component slice of a vector field is a
coordinate projection rather than a scalar section (a component is obtained by contracting with a basis
vector, which allocates).

What it *did* have was a silent wrong answer. A fused pass reads element ``n`` and writes element
``n``, which is safe when the destination IS an input and unsafe when one section's element ``n`` is
another's element ``n + m``. Two overlapping views at different base offsets produced exactly that, in
fourteen operations across three execution routes, with no error — and no contiguity test excludes it,
since `reshape(view(flat, 2:end), dims)` is densely strided and still overlaps at an offset. Ownership is
the property that does exclude it.

The check is on ownership, not on layout: `Array`, `CuArray`, `ROCArray` and a `reshape` of any of them
all own their memory and are accepted, so the package's backend genericity is untouched. Allocate with
`similar_field` or `similar_point_values` rather than slicing a larger buffer.
"""
function _check_owned_storage(data, what::AbstractString)
  borrowed(a) = a isa SubArray || (a !== parent(a) && borrowed(parent(a)))
  borrowed(data) &&
    throw(ArgumentError("$what must own its storage; got a view into a larger array. Two sections " *
                        "over overlapping views at different base offsets read and write the same " *
                        "memory out of step, which no operation here detects. Allocate with " *
                        "`similar_field` / `similar_point_values`, or `copy` the slice."))
  return nothing
end


###################################
#        CPU threading            #
###################################

# Shared-memory CPU threading for elementwise/fiberwise assignments. Non-reducing maps are
# bitwise-identical serial vs threaded (each output index is written once from the same fused
# expression), so threading them is safe and deterministic. The policy is hybrid: threaded by
# default when more than one Julia thread is available, with a serial cutoff (small operations
# and the one-element zero-mode views stay serial) and a task-local override for
# nested-parallel callers. The backend is Base.Threads, kept inside `_assign!` so it stays
# swappable.


"""
    _THREADING_OVERRIDE

This task-local value overrides the threading decision. A value of `nothing` follows
`Threads.nthreads()`, while `true` or `false` forces threaded or serial.
The setter [`with_threading`](@ref) sets it in a dynamic scope.
"""
const _THREADING_OVERRIDE = ScopedValue{Union{Nothing, Bool}}(nothing)


"""
    _SERIAL_CUTOFF

Below this element count an assignment runs serially regardless of thread count. Threading
does not pay on small arrays, and the cutoff also exempts one-element
views of the zero Fourier mode. The assignment path reads it, and [`set_threading_cutoff!`](@ref) sets it.
"""
const _SERIAL_CUTOFF = Ref(1 << 14)


"""
    with_threading(f; enabled::Union{Nothing, Bool} = true)

Run `f()` with the CPU-threading decision forced to `enabled`, restore the previous setting, and return
`f()`'s value. The override is dynamically scoped and task-local, affecting only `f()`, and is restored
even on an exception.

The arguments are:

- `f` — the zero-argument function to run under the override.
- `enabled` — `true` or `false` to force the threaded or serial path, or `nothing` to follow the
  automatic `nthreads()`-based policy. Pass `false` around a region already parallel at a higher
  level, avoiding oversubscription.

!!! warning "Not every operation is governed by this override"
    The override (and the cutoff) governs the fused broadcast assignments, the fused CPU loops
    behind the algebra and the differential operators (`helmholtz_projection!` included), and the
    fixed-tree reductions — a reduction whose summation tree is a function of the array length
    alone, so it returns the same value at every thread count. Two groups of operations run as
    portable device-style kernels on **every**
    backend and partition by `Threads.nthreads()` directly, ignoring this setting: the grid↔point
    transfer (`interpolate!`/`anterpolate!`) and the radial reductions
    (`radial_spectrum`/`radial_correlation`) — the kernels with atomic or irregular access, which a
    gated loop cannot serve — "gated" meaning a CPU loop that consults this setting before
    threading, as against a kernel that always partitions by thread count. To run those
    serially, start Julia with one thread.

    A third category is neither governed nor exempt: an operation that is **not threaded at all**, and
    so unaffected by this setting for a different reason. The `weighted_inner` reduction is the one to know about —
    its single fused pass is serial, which is why it diverges from `inner` as threads are added.
    Nothing is wrong there; it simply has no threaded route to override.
"""
with_threading(f; enabled::Union{Nothing, Bool} = true) =
  Base.ScopedValues.with(f, _THREADING_OVERRIDE => enabled)


"""
    set_threading_cutoff!(n::Integer)

Set [`threading_cutoff`](@ref) to `n` and return it. A CPU field assignment whose destination has
fewer than `n` elements then runs serially instead of threaded. Raise `n` to keep small
operations off the thread pool, or lower it to thread smaller writes.

The cutoff is a single process-wide setting, unlike [`with_threading`](@ref), whose override is
dynamically scoped and therefore task-local. Set it once at startup rather than around a call.
"""
function set_threading_cutoff!(n::Integer)
  # A cutoff below one is not a threshold: at zero an EMPTY destination counts as threadable, and the
  # partitioner then forms a zero-length block and a zero-step range, so an operation on an empty
  # field fails inside the scheduler for a reason the caller cannot see.
  n >= 1 || throw(ArgumentError("the threading cutoff must be at least 1; got $n"))
  _SERIAL_CUTOFF[] = Int(n)
  return Int(n)
end


"""
    threading_cutoff()

Return the element count at or above which a CPU field assignment is split across `Base.Threads`
workers rather than run serially. Here an assignment is a fused elementwise write into field
storage — the [`_assign!`](@ref) primitive behind broadcasts, and the same gate guards the
fused CPU loops behind the algebra and the differential operators, and the fixed-tree reductions
(a reduction whose summation tree depends on the array length alone, so its value is the same at
every thread count). Two
groups of operations sit outside the gate and thread by `Threads.nthreads()` regardless (see the
warning on [`with_threading`](@ref)): the grid↔point transfer and the radial reductions. The count is measured as the destination array's length (grid points
times fiber components), and it applies on the CPU only, since GPU arrays are never threaded. The
default is `16384`, and [`set_threading_cutoff!`](@ref) changes it.
"""
threading_cutoff() = _SERIAL_CUTOFF[]


"""
    _use_threads(element_count)

Return whether an assignment over `element_count` elements should be threaded. It is threaded when
the count is at or above the serial cutoff and threading is either forced on or, under the
automatic policy, `Threads.nthreads() > 1`.
"""
@inline function _use_threads(element_count::Integer)
  element_count < _SERIAL_CUTOFF[] && return false
  override = _THREADING_OVERRIDE[]
  return override === nothing ? Threads.nthreads() > 1 : override
end


"""
    _index_ranges(axis::AbstractUnitRange, n::Integer)

Partition the index range `axis` into at most `n` contiguous, near-equal `UnitRange`s.
"""
function _index_ranges(axis::AbstractUnitRange, n::Integer)
  total = length(axis)
  parts = max(1, min(Int(n), total))
  block = cld(total, parts)
  return [(first(axis) + offset):min(first(axis) + offset + block - 1, last(axis)) for offset in 0:block:(total - 1)]
end


# `eachindex` of a NON-CONTIGUOUS view is cartesian, not a range, so a field backed by such a view had
# no partition and the fused executor threw a MethodError from inside the scheduler — while the same
# call succeeded serially, because the serial path iterates `eachindex` directly. Storage is generic
# `AbstractArray` by invariant 6, so a view is a legitimate operand and must not depend on the thread
# count. Partition the OUTERMOST axis, which keeps each slab's inner traversal contiguous.
function _index_ranges(indices::CartesianIndices, n::Integer)
  index_axes = axes(indices)
  inner = ntuple(d -> index_axes[d], length(index_axes) - 1)
  return [CartesianIndices((inner..., slab)) for slab in _index_ranges(index_axes[end], n)]
end


"""
    _assign!(destination, broadcasted)

Materialize the lazy `broadcasted` expression into `destination` and return it, threading over
chunks on the CPU when [`_use_threads`](@ref) allows. The generic method is plain
`Broadcast.materialize!`, the safe default that keeps GPU arrays and unknown array wrappers on
their broadcast path with no scalar indexing. Only dense `Array`s and `Array`-backed
`SubArray`s take the threaded path.
"""
_assign!(destination, broadcasted::Base.Broadcast.Broadcasted) =
  Base.Broadcast.materialize!(destination, broadcasted)

function _assign!(destination::Union{Array, SubArray{<:Any, <:Any, <:Array}}, broadcasted::Base.Broadcast.Broadcasted)
  _use_threads(length(destination)) || return Base.Broadcast.materialize!(destination, broadcasted)
  return _assign_threaded!(destination, broadcasted)
end


"""
    _slab_axis(dimensions)

Pick the axis a threaded assignment is split along: the **last among the largest**, so each slab
is a large contiguous block and a trailing fiber axis of length 3 never caps the parallelism (a
whole-vector-field write `(N, N, N, 3)` splits along the third axis, not the fourth).
"""
function _slab_axis(dimensions::Dims)
  best = 1
  for dimension in 2:length(dimensions)
    dimensions[dimension] >= dimensions[best] && (best = dimension)
  end
  return best
end


"""
    _broadcast_sliceable(argument)

Return whether every leaf of a broadcast argument tree is a type [`_slice_broadcast_argument`](@ref)
knows how to slice or pass through — arrays, numbers, `Ref`s, and nested `Broadcasted` trees over
them. Anything else makes the threaded path bail out to the serial `materialize!` (the safe
polarity; the field kernels only ever build trees of these types).
"""
_broadcast_sliceable(argument::Base.Broadcast.Broadcasted) = all(_broadcast_sliceable, argument.args)
_broadcast_sliceable(::AbstractArray) = true
_broadcast_sliceable(::Number) = true
_broadcast_sliceable(::Ref) = true
_broadcast_sliceable(::Any) = false


"""
    _slice_broadcast_argument(argument, axis::Val, slab)

Restrict one broadcast argument to the `slab` range of broadcast axis `axis`. An array spanning
that axis is viewed to the slab (a view re-bases its axes, so all sliced operands land on matching
`OneTo` axes); an array with a singleton or missing `axis` passes through unchanged (broadcasting
extrudes it exactly as in the full assignment); a nested `Broadcasted` is rebuilt over its sliced
arguments; scalars and `Ref`s are shape-free and pass through. The axis is a `Val` so the whole
recursive slice specializes: with it a runtime `Int` would leave every view and rebuilt node
un-inferred, boxing kilobytes per slab where the specialized form allocates only the small wrapper
objects themselves.
"""
_slice_broadcast_argument(argument::Base.Broadcast.Broadcasted, axis::Val, slab::UnitRange{Int}) =
  Base.Broadcast.broadcasted(argument.f,
                             map(a -> _slice_broadcast_argument(a, axis, slab), argument.args)...)

function _slice_broadcast_argument(argument::AbstractArray, ::Val{A}, slab::UnitRange{Int}) where {A}
  (ndims(argument) < A || size(argument, A) == 1) && return argument
  return view(argument, ntuple(d -> d == A ? slab : Colon(), Val(ndims(argument)))...)
end

_slice_broadcast_argument(argument, ::Val, ::UnitRange{Int}) = argument


"""
    _assign_threaded!(destination, broadcasted)

Thread a fused broadcast assignment by splitting the [`_slab_axis`](@ref) of `destination` into
contiguous slabs and running the standard fused `Broadcast.materialize!` on each slab in its own
task — the destination viewed to the slab, the `Broadcasted` tree rebuilt over
[`_slice_broadcast_argument`](@ref)-sliced operands. Each slab therefore executes the same
SIMD-vectorized broadcast kernel the serial path uses, only over a sub-range: fusion is preserved
(no temporaries), and the result is bitwise-identical to serial, since each element is written
exactly once from the same fused expression and no value crosses a slab boundary. This replaced a
per-element `CartesianIndex` loop over the whole `Broadcasted`, which does not vectorize — measured
at ~4.7× slower per core than `materialize!`, so threading *inverted* at low thread counts
(2026-07-21; the finding and the numbers live with the benchmarks). The method falls back to serial
when the axes do not match or an argument type is not sliceable, which is defensive because the
field kernels always match and only build sliceable trees.
"""
function _assign_threaded!(destination, broadcasted::Base.Broadcast.Broadcasted)
  instantiated = Base.Broadcast.instantiate(broadcasted)
  axes(instantiated) == axes(destination) || return Base.Broadcast.materialize!(destination, instantiated)
  _broadcast_sliceable(instantiated)      || return Base.Broadcast.materialize!(destination, instantiated)

  # One dynamic dispatch converts the runtime axis into a `Val`, so slicing and the per-slab
  # `materialize!` below all specialize (the function barrier `_assign_slabs!`).
  return _assign_slabs!(destination, instantiated, Val(_slab_axis(size(destination))))
end


"""
    _assign_slabs!(destination, instantiated, axis::Val)

Run the slab tasks of [`_assign_threaded!`](@ref): partition the given axis of `destination` with
[`_index_ranges`](@ref) and `materialize!` each slab's sliced assignment in its own task. Separated
behind a `Val` function barrier so every slice and kernel call compiles for the concrete axis.
"""
function _assign_slabs!(destination, instantiated, axis::Val{A}) where {A}
  @sync for slab in _index_ranges(axes(destination, A), Threads.nthreads())
    Threads.@spawn Base.Broadcast.materialize!(
      _slice_broadcast_argument(destination, axis, slab),
      _slice_broadcast_argument(instantiated, axis, slab))
  end
  return destination
end


"""
    _assign!(destination, source)

Handle a non-`Broadcasted` right-hand side — for example a bare component view from a transpose,
or a constant — by wrapping it as an identity broadcast so the same threaded assignment path
applies.
"""
_assign!(destination, source) = _assign!(destination, Base.Broadcast.broadcasted(identity, source))


"""
    _to_broadcasted(expr)

Rewrite a dotted expression — an infix dotted operator such as `a .* b .+ c`, or a broadcast call
such as `f.(x)` — into the lazy `Base.Broadcast.broadcasted(f, args...)` tree, recursing into
operands and leaving non-broadcast subexpressions untouched. This codegen helper lets generated
and hand-written kernels route a fused assignment through [`_assign!`](@ref) without materializing
intermediates, so fusion is preserved.
"""
function _to_broadcasted(expr)
  if expr isa Expr && expr.head === :call && expr.args[1] isa Symbol && startswith(string(expr.args[1]), ".")
    operator = Symbol(string(expr.args[1])[2:end])
    return Expr(:call, :(Base.Broadcast.broadcasted), operator, map(_to_broadcasted, expr.args[2:end])...)
  elseif expr isa Expr && expr.head === :. && length(expr.args) == 2 && expr.args[2] isa Expr && expr.args[2].head === :tuple
    return Expr(:call, :(Base.Broadcast.broadcasted), expr.args[1], map(_to_broadcasted, expr.args[2].args)...)
  else
    return expr
  end
end


"""
    @_assign!(destination .= rhs)

Replace a fused broadcast assignment with a threaded one: rewrite `rhs` to a lazy broadcast tree
(via [`_to_broadcasted`](@ref)) and assign it through [`_assign!`](@ref), so the write threads on
the CPU. Use it in hand-written kernels in place of `.=`, and note that `_assign!` must be in
scope at the call site.
"""
macro _assign!(assignment)
  (assignment isa Expr && assignment.head === Symbol(".=")) ||
    throw(ArgumentError("@_assign! expects a `destination .= rhs` expression"))
  destination, rhs = assignment.args
  return esc(:(_assign!($destination, $(_to_broadcasted(rhs)))))
end


#################################
#        Code generation        #
#################################
#
# The helpers below build expressions for the per-component access and write-back
# of generated kernels, so that each operation's formula is written exactly once.
#
#   `kind` is :field   -> access through the component views (a field argument)
#             :fiber   -> index a constant SVector / SMatrix argument
#
# Field component views are spliced directly into the formulas rather than bound
# to locals first; the views are lazy, so this is equivalent to the hand-written
# kernels it replaces.


"""
    _vector_component(symbol, kind, i)

Build the expression that accesses component `i` of a vector argument named `symbol`. With `kind = :field` it reads a field's component view (`_vector_component_data`); with `kind = :fiber` it indexes a constant `SVector`; with `kind = :scalar` it emits the positional scalar argument name `symbol_i` for a fused values function ([`_fiberwise_pass!`](@ref)). The builders splice the result into kernel formulas so that each per-component formula is written once.
"""
_vector_component(symbol, kind, i)    = kind === :field  ? :(_vector_component_data( $symbol, $i)) :
                                        kind === :scalar ? Symbol(symbol, "_", i)                  : :($symbol[$i])

"""
    _tensor_component(symbol, kind, i, j)

Build the expression that accesses component `(i, j)` of a second-order tensor argument named `symbol`. With `kind = :field` it reads a field's component view (`_tensor2_component_data`); with `kind = :fiber` it indexes a constant `SMatrix`; with `kind = :scalar` it emits the positional scalar argument name `symbol_ij` for a fused values function.
"""
_tensor_component(symbol, kind, i, j) = kind === :field  ? :(_tensor2_component_data($symbol, $i, $j)) :
                                        kind === :scalar ? Symbol(symbol, "_", i, j)                   : :($symbol[$i, $j])


"""
    _sum_terms(terms)

Combine a non-empty collection of expressions into a broadcasted sum `term_1 .+ term_2 .+ term_3`.
"""
_sum_terms(terms) = reduce((accumulated, term) -> :($accumulated .+ $term), terms)


"""
    _product(x, y)

Build the broadcasted product expression `x .* y`.
"""
_product(x, y) = :($x .* $y)


"""
    _vector_kernel_body(formula; alpha_beta::Bool)

Build the body of a vector-valued kernel, writing the value `formula(i)` builds into component ``i`` of `destination`, for ``i = 1, 2, 3``, where `formula(i)` is the per-component expression. With `alpha_beta = true` it emits the five-argument `destination = α * formula + β * destination` form and branches on `iszero(β_value)`, so the pure-overwrite path stays allocation-free. The body ends in `return destination` and is spliced into a function that binds `destination` (and, when `alpha_beta` is set, `α_value` and `β_value`).
"""
function _vector_kernel_body(formula; alpha_beta::Bool)
  target(i) = :(_vector_component_data(destination, $i))

  if alpha_beta
    overwrite = [:(_assign!($(target(i)), $(_to_broadcasted(:(α_value .* $(formula(i))))))) for i in 1:3]
    accumulate = [:(_assign!($(target(i)), $(_to_broadcasted(:(α_value .* $(formula(i)) .+ β_value .* $(target(i))))))) for i in 1:3]

    return quote
      if iszero(β_value)
        $(overwrite...)
      else
        $(accumulate...)
      end

      return destination
    end
  else
    statements = [:(_assign!($(target(i)), $(_to_broadcasted(formula(i))))) for i in 1:3]

    return quote
      $(statements...)

      return destination
    end
  end
end


"""
    _tensor_kernel_body(formula; alpha_beta::Bool)

Build the body of a second-order tensor-valued kernel, writing the value `formula(i, j)` builds into component ``(i,j)`` of `destination`, for ``i, j = 1, 2, 3``, with the same `alpha_beta` five-argument behaviour as `_vector_kernel_body`.
"""
function _tensor_kernel_body(formula; alpha_beta::Bool)
  target(i, j) = :(_tensor2_component_data(destination, $i, $j))

  if alpha_beta
    overwrite = [:(_assign!($(target(i, j)), $(_to_broadcasted(:(α_value .* $(formula(i, j))))))) for i in 1:3 for j in 1:3]
    accumulate = [:(_assign!($(target(i, j)), $(_to_broadcasted(:(α_value .* $(formula(i, j)) .+ β_value .* $(target(i, j))))))) for i in 1:3 for j in 1:3]

    return quote
      if iszero(β_value)
        $(overwrite...)
      else
        $(accumulate...)
      end

      return destination
    end
  else
    statements = [:(_assign!($(target(i, j)), $(_to_broadcasted(formula(i, j))))) for i in 1:3 for j in 1:3]

    return quote
      $(statements...)

      return destination
    end
  end
end


"""
    _scalar_kernel_body(rhs)

Build the body of a scalar-field-valued kernel (a contraction with a scalar result), writing `field_data(destination) .= rhs` and ending in `return destination`.
"""
function _scalar_kernel_body(rhs)
  return quote
    _assign!(field_data(destination), $(_to_broadcasted(rhs)))

    return destination
  end
end


@inline _add_values(x, y) = x + y
@inline _add_values(x, y, z, rest...) = _add_values(x + y, z, rest...)

@inline _subtract_values(x, y) = x - y
@inline _subtract_values(x, y, z, rest...) = _subtract_values(x - y, z, rest...)


#
# Per-component formulas for the contraction and permutation families, written
# once and fed to the kernel-body builders. `kind` is :field (component view) or
# :fiber (StaticArrays indexing), as in the M1 builders above.


"""
    _dot_vector_rhs(u_symbol, u_kind, v_symbol, v_kind)

Build the right-hand-side expression for a vector inner product, ``\\sum_i u_i v_i``, as a single broadcasted expression fed to `_scalar_kernel_body`. Each operand `kind` is `:field` or `:fiber`, as in `_vector_component`.
"""
_dot_vector_rhs(u_symbol, u_kind, v_symbol, v_kind) =
  _sum_terms([_product(_vector_component(u_symbol, u_kind, i), _vector_component(v_symbol, v_kind, i)) for i in 1:3])


"""
    _dot_tensor_rhs(A_symbol, A_kind, B_symbol, B_kind)

Build the right-hand-side expression for the tensor Frobenius inner product, ``\\sum_{ij} A_{ij} B_{ij}``, as a single broadcasted expression fed to `_scalar_kernel_body`.
"""
_dot_tensor_rhs(A_symbol, A_kind, B_symbol, B_kind) =
  _sum_terms([_product(_tensor_component(A_symbol, A_kind, i, j), _tensor_component(B_symbol, B_kind, i, j)) for i in 1:3 for j in 1:3])


"""
    _cross_formula(left_symbol, left_kind, right_symbol, right_kind)

Return a per-component function `i -> expr` for the cross product: with cyclic `(j, k)`, component `i` is ``u_j v_k - u_k v_j``. Its output feeds `_vector_kernel_body`.
"""
function _cross_formula(left_symbol, left_kind, right_symbol, right_kind)
  return function (i)
    j = mod1(i + 1, 3)
    k = mod1(i + 2, 3)
    first_term  = _product(_vector_component(left_symbol, left_kind, j), _vector_component(right_symbol, right_kind, k))
    second_term = _product(_vector_component(left_symbol, left_kind, k), _vector_component(right_symbol, right_kind, j))
    return :($first_term .- $second_term)
  end
end


"""
    _tensor_vector_formula(A_symbol, A_kind, u_symbol, u_kind)

Return a per-component function `i -> expr` for the tensor-on-vector left action, whose component `i` is ``A_{ij} u_j`` (the repeated fiber index summed). Its output feeds `_vector_kernel_body`.
"""
_tensor_vector_formula(A_symbol, A_kind, u_symbol, u_kind) =
  i -> _sum_terms([_product(_tensor_component(A_symbol, A_kind, i, j), _vector_component(u_symbol, u_kind, j)) for j in 1:3])


"""
    _vector_tensor_formula(u_symbol, u_kind, A_symbol, A_kind)

Return a per-component function `i -> expr` for the vector-on-tensor right action, whose component `i` is ``u_j A_{ji}`` (the repeated fiber index summed). Its output feeds `_vector_kernel_body`.
"""
_vector_tensor_formula(u_symbol, u_kind, A_symbol, A_kind) =
  i -> _sum_terms([_product(_vector_component(u_symbol, u_kind, j), _tensor_component(A_symbol, A_kind, j, i)) for j in 1:3])


"""
    _tensor_tensor_formula(A_symbol, A_kind, B_symbol, B_kind)

Return a per-component function `(i, j) -> expr` for the tensor-tensor product, whose component `(i, j)` is ``A_{ik} B_{kj}`` (the repeated fiber index summed). Its output feeds `_tensor_kernel_body`.
"""
_tensor_tensor_formula(A_symbol, A_kind, B_symbol, B_kind) =
  (i, j) -> _sum_terms([_product(_tensor_component(A_symbol, A_kind, i, k), _tensor_component(B_symbol, B_kind, k, j)) for k in 1:3])


"""
    _transpose_formula(A_symbol, A_kind)

Return a per-component function `(i, j) -> expr` for the transpose, whose component `(i, j)` is ``A_{ji}``. Its output feeds `_tensor_kernel_body`.
"""
_transpose_formula(A_symbol, A_kind) = (i, j) -> _tensor_component(A_symbol, A_kind, j, i)


#####################################################
#        Norm and Decomposition Formulas            #
#####################################################
#
# Per-component formulas for the pointwise norms and the symmetric/skew/deviatoric
# decompositions, written once and fed to the kernel-body builders. The scalar type
# comes from `_section_scalar_type` so the same body serves fields and point-values.


"""
    _norm_scalar_rhs(symbol)

Build, for `_scalar_kernel_body`, the scalar `symbol`'s pointwise norm ``|\\varphi|``.
"""
_norm_scalar_rhs(symbol) = :(abs.(field_data($symbol)))


"""
    _norm_vector_rhs(symbol, kind)

Build, for `_scalar_kernel_body`, the vector `symbol`'s Euclidean norm ``\\sqrt{\\sum_i u_i^2}``.
"""
_norm_vector_rhs(symbol, kind) =
  :(sqrt.($(_sum_terms([:(abs2.($(_vector_component(symbol, kind, i)))) for i in 1:3]))))


"""
    _norm_tensor_rhs(symbol, kind)

Build, for `_scalar_kernel_body`, the tensor `symbol`'s Frobenius norm ``\\sqrt{\\sum_{ij} A_{ij}^2}``.
"""
_norm_tensor_rhs(symbol, kind) =
  :(sqrt.($(_sum_terms([:(abs2.($(_tensor_component(symbol, kind, i, j)))) for i in 1:3 for j in 1:3]))))


"""
    _trace_tensor_rhs(symbol, kind)

Build the right-hand side for the fiberwise trace ``\\operatorname{tr}(A) = A_{ii} = A_{11} + A_{22} + A_{33}``, the sum of the diagonal components of the tensor `symbol` (`kind` is `:field` or `:fiber`). It feeds `_scalar_kernel_body`, and the fused `_dev_values` function reuses it for the trace it subtracts. The trace is linear, so the same body serves both physical-space and spectral representation.
"""
_trace_tensor_rhs(symbol, kind) = _sum_terms([_tensor_component(symbol, kind, d, d) for d in 1:3])


"""
    _det_tensor_rhs(symbol, kind)

Build the right-hand side for the fiberwise determinant ``\\det(A) = \\varepsilon_{ijk} A_{1i} A_{2j} A_{3k}``,
the third principal invariant ``I_3`` of the ``3\\times3`` tensor `symbol` (`kind` is `:field` or
`:fiber`), expanded by cofactors along the first row:

```math
\\begin{aligned}
\\det(A) = {} & A_{11}(A_{22}A_{33} - A_{23}A_{32}) \\\\
             & - A_{12}(A_{21}A_{33} - A_{23}A_{31}) \\\\
             & + A_{13}(A_{21}A_{32} - A_{22}A_{31}).
\\end{aligned}
```

It feeds `_scalar_kernel_body`. Unlike the linear `_trace_tensor_rhs`, the determinant is cubic in the
components (a homogeneous degree-3 form), so it is a nonlinear operation and is generated for physical-space
representation only.
"""
function _det_tensor_rhs(symbol, kind)
  component(i, j) = _tensor_component(symbol, kind, i, j)
  minor(row_1, row_2, col_1, col_2) =
    :($(_product(component(row_1, col_1), component(row_2, col_2))) .- $(_product(component(row_1, col_2), component(row_2, col_1))))
  cofactor_11 = _product(component(1, 1), minor(2, 3, 2, 3))
  cofactor_12 = _product(component(1, 2), minor(2, 3, 1, 3))
  cofactor_13 = _product(component(1, 3), minor(2, 3, 1, 2))
  return :($cofactor_11 .- $cofactor_12 .+ $cofactor_13)
end



#########################################################
#        Fused fiberwise executor (values functions)    #
#########################################################
#
# One portable executor runs every fused fiberwise operation: a pure scalar "values function"
# maps one element's source values (plus any fiber constants) to the tuple of output values, and
# the executor streams it over the common linear index range — sources read once into registers,
# every output written from them, the package-wide α/β accumulate convention owned centrally. The values functions are
# stamped below from the SAME per-component formula builders the broadcast kernels use (`kind =
# :scalar` names the positional scalar arguments; `_undot` drops the dots), so each formula stays
# written exactly once. All of an element's reads happen before its writes, which makes the pass
# alias-safe by construction and retires the index-shuffle guard for the operations routed here.


"""
    _undot(expr)

Lower a dotted formula expression to its per-element form: dotted operators (`.+`, `.*`, …) lose
their dots and dotted calls `f.(x)` become plain calls, recursively. The formula builders above
emit dotted (broadcast) expressions; the fused values functions evaluate the same tree one
element at a time, so the arithmetic — and hence the result — is bitwise-identical.
"""
function _undot(expr)
  expr isa Expr || return expr
  if expr.head === :call && expr.args[1] isa Symbol && startswith(String(expr.args[1]), '.')
    return Expr(:call, Symbol(String(expr.args[1])[2:end]), map(_undot, expr.args[2:end])...)
  elseif expr.head === :. && length(expr.args) == 2 && expr.args[2] isa Expr && expr.args[2].head === :tuple
    return Expr(:call, expr.args[1], map(_undot, expr.args[2].args)...)
  end
  return Expr(expr.head, map(_undot, expr.args)...)
end


"""
    _write_values!(targets, values, α, n)

Write `α * values[i]` into `targets[i][n]` for every output, unrolled over the (static)
output count, returning `nothing`. The real `α` keeps the multiply exact for ``\\alpha = 1``, so the plain
(non-``\\alpha``/``\\beta``) forms stay bitwise-identical to broadcasting.
"""
@inline function _write_values!(targets::NTuple{N, Any}, values::NTuple{N, Any}, α, n) where {N}
  ntuple(i -> (@inbounds targets[i][n] = α * values[i]; nothing), Val(N))
  return nothing
end


"""
    _accumulate_values!(targets, values, α, β, n)

The ``\\beta \\ne 0`` counterpart of [`_write_values!`](@ref): write
`α * values[i] + β * targets[i][n]`, mirroring the accumulate branch of the broadcast
kernel bodies expression for expression.
"""
@inline function _accumulate_values!(targets::NTuple{N, Any}, values::NTuple{N, Any}, α, β, n) where {N}
  ntuple(i -> (@inbounds targets[i][n] = α * values[i] + β * targets[i][n]; nothing), Val(N))
  return nothing
end


# One work-item per element: apply the values function and write every output, the α/β branch
# uniform across items. The source arrays are deliberately not @Const: a target may alias a
# source (the aliased cross!/transpose! in place), and all of an element's reads precede its
# writes, so the aliased call is safe and bitwise-identical to the non-aliased one.
@kernel function _fiberwise_values_kernel!(f, targets, arrays, constants, α, β)
  n = @index(Global, Linear)
  @inbounds begin
    values = f(map(array -> array[n], arrays)..., constants...)
    if iszero(β)
      _write_values!(targets, values, α, n)
    else
      _accumulate_values!(targets, values, α, β, n)
    end
  end
end


"""
    _fiberwise_pass!(backend, f, targets, arrays, constants, α, β)

Run one fused fiberwise pass — every target element receives ``\\alpha f(\\text{element values}, \\text{constants})``, plus `β` times its prior value when the accumulate is requested — over the common
linear index range of the participating storage. Here `f` is a pure scalar values function: it
takes one scalar per entry of `arrays` (that array's element at the running index) followed by
the fiber `constants` verbatim, and returns the tuple of output values written to `targets`.
Every array element is read once and every output written once, and all of an element's reads
happen before its writes, so a target may alias a source array. The generic method launches the `_fiberwise_values_kernel!` device kernel on the
backend; the `KernelAbstractions.CPU` method runs a `@simd` loop, threaded over slabs, over the linear
range (component views are contiguous, so linear indexing is stride-1) through the same
[`_use_threads`](@ref) gate as broadcasts, bitwise-identical to serial because each
element is written once from the same expression. Returns `nothing`.
"""
function _fiberwise_pass!(backend, f::F, targets, arrays, constants, α, β) where {F}
  _fiberwise_values_kernel!(backend)(f, targets, arrays, constants, α, β;
                                     ndrange = length(targets[1]))
  synchronize(backend)
  return nothing
end

function _fiberwise_pass!(::KernelAbstractions.CPU, f::F, targets::NTuple{NT, Any},
    arrays, constants, α, β) where {F, NT}
  elements = eachindex(targets[1])
  _use_threads(NT * length(elements)) ||
    return _fiberwise_slab!(f, targets, arrays, constants, α, β, elements)
  @sync for slab in _index_ranges(elements, Threads.nthreads())
    Threads.@spawn _fiberwise_slab!(f, targets, arrays, constants, α, β, slab)
  end
  return nothing
end


"""
    _foreach_outer_slab(slab_body!, outer_axis, element_count)

Run `slab_body!` over the whole `outer_axis` serially, or — when [`_use_threads`](@ref) allows for
`element_count` written elements — over contiguous slabs of it, one task per slab. The caller's
`slab_body!` loops modes with the outer axis restricted to the given range, so each element is
written by exactly one task and the threaded result is bitwise-identical to serial.
"""
function _foreach_outer_slab(slab_body!::F, outer_axis, element_count) where {F}
  _use_threads(element_count) || return slab_body!(outer_axis)
  @sync for slab in _index_ranges(outer_axis, Threads.nthreads())
    Threads.@spawn slab_body!(slab)
  end
  return nothing
end


"""
    _fiberwise_slab!(f, targets, arrays, constants, α, β, elements)

Run [`_fiberwise_pass!`](@ref)'s loop over one contiguous slab of the linear index range, the
``\\beta`` branch hoisted out of the loop (the package-wide overwrite-vs-accumulate convention: ``\\beta = 0`` never reads the destination).
"""
function _fiberwise_slab!(f::F, targets, arrays, constants, α, β, elements) where {F}
  if iszero(β)
    @inbounds @simd for n in elements
      _write_values!(targets, f(map(array -> array[n], arrays)..., constants...), α, n)
    end
  else
    @inbounds @simd for n in elements
      _accumulate_values!(targets, f(map(array -> array[n], arrays)..., constants...), α, β, n)
    end
  end
  return nothing
end


#############################################
#        Stamped values functions           #
#############################################
#
# Signature convention: the indexed-array scalars come first, in the order the call site packs
# its `arrays` tuple (vector components 1:3, tensor components row-major 11, 12, …, 33), followed
# by the fiber constants verbatim. A suffix names the operand kinds left-to-right: `_ff` both
# fields, `_fc` field then fiber constant, `_cf` fiber constant then field. Each body is the
# corresponding formula builder's expression, undotted — the formula is still written only once.
# The generated methods carry no docstrings, per the codegen rule; `half`/`third` take the real
# scalar type from the first argument, exactly as the broadcast bodies took `_section_scalar_type`.

@eval @inline _cross_values_ff(u_1, u_2, u_3, v_1, v_2, v_3) =
  ($([_undot(_cross_formula(:u, :scalar, :v, :scalar)(i)) for i in 1:3]...),)

@eval @inline _cross_values_fc(u_1, u_2, u_3, a) =
  ($([_undot(_cross_formula(:u, :scalar, :a, :fiber)(i)) for i in 1:3]...),)

@eval @inline _cross_values_cf(u_1, u_2, u_3, a) =
  ($([_undot(_cross_formula(:a, :fiber, :u, :scalar)(i)) for i in 1:3]...),)

@eval @inline _tensor_vector_values_ff(A_11, A_12, A_13, A_21, A_22, A_23, A_31, A_32, A_33,
                                       u_1, u_2, u_3) =
  ($([_undot(_tensor_vector_formula(:A, :scalar, :u, :scalar)(i)) for i in 1:3]...),)

@eval @inline _tensor_vector_values_fc(A_11, A_12, A_13, A_21, A_22, A_23, A_31, A_32, A_33, a) =
  ($([_undot(_tensor_vector_formula(:A, :scalar, :a, :fiber)(i)) for i in 1:3]...),)

@eval @inline _tensor_vector_values_cf(u_1, u_2, u_3, A) =
  ($([_undot(_tensor_vector_formula(:A, :fiber, :u, :scalar)(i)) for i in 1:3]...),)

@eval @inline _vector_tensor_values_ff(u_1, u_2, u_3,
                                       A_11, A_12, A_13, A_21, A_22, A_23, A_31, A_32, A_33) =
  ($([_undot(_vector_tensor_formula(:u, :scalar, :A, :scalar)(i)) for i in 1:3]...),)

@eval @inline _vector_tensor_values_fc(u_1, u_2, u_3, A) =
  ($([_undot(_vector_tensor_formula(:u, :scalar, :A, :fiber)(i)) for i in 1:3]...),)

@eval @inline _vector_tensor_values_cf(A_11, A_12, A_13, A_21, A_22, A_23, A_31, A_32, A_33, a) =
  ($([_undot(_vector_tensor_formula(:a, :fiber, :A, :scalar)(i)) for i in 1:3]...),)

@eval @inline _tensor_tensor_values_ff(A_11, A_12, A_13, A_21, A_22, A_23, A_31, A_32, A_33,
                                       B_11, B_12, B_13, B_21, B_22, B_23, B_31, B_32, B_33) =
  ($([_undot(_tensor_tensor_formula(:A, :scalar, :B, :scalar)(i, j)) for i in 1:3 for j in 1:3]...),)

@eval @inline _tensor_tensor_values_fc(A_11, A_12, A_13, A_21, A_22, A_23, A_31, A_32, A_33, B) =
  ($([_undot(_tensor_tensor_formula(:A, :scalar, :B, :fiber)(i, j)) for i in 1:3 for j in 1:3]...),)

@eval @inline _tensor_tensor_values_cf(B_11, B_12, B_13, B_21, B_22, B_23, B_31, B_32, B_33, A) =
  ($([_undot(_tensor_tensor_formula(:A, :fiber, :B, :scalar)(i, j)) for i in 1:3 for j in 1:3]...),)

@eval @inline _transpose_values(A_11, A_12, A_13, A_21, A_22, A_23, A_31, A_32, A_33) =
  ($([_undot(_transpose_formula(:A, :scalar)(i, j)) for i in 1:3 for j in 1:3]...),)

@eval @inline function _sym_values(A_11, A_12, A_13, A_21, A_22, A_23, A_31, A_32, A_33)
  half = inv(real(typeof(A_11))(2))
  return ($([i == j ? Symbol("A_", i, i) :
             :(half * ($(Symbol("A_", i, j)) + $(Symbol("A_", j, i)))) for i in 1:3 for j in 1:3]...),)
end

@eval @inline function _skew_values(A_11, A_12, A_13, A_21, A_22, A_23, A_31, A_32, A_33)
  half = inv(real(typeof(A_11))(2))
  return ($([i == j ? :(zero(real(typeof(A_11)))) :
             :(half * ($(Symbol("A_", i, j)) - $(Symbol("A_", j, i)))) for i in 1:3 for j in 1:3]...),)
end

@eval @inline function _dev_values(A_11, A_12, A_13, A_21, A_22, A_23, A_31, A_32, A_33)
  third = inv(real(typeof(A_11))(3))
  trace = $(_undot(_trace_tensor_rhs(:A, :scalar)))
  return ($([i == j ? :($(Symbol("A_", i, i)) - third * trace) :
             Symbol("A_", i, j) for i in 1:3 for j in 1:3]...),)
end

@eval @inline _det_values(A_11, A_12, A_13, A_21, A_22, A_23, A_31, A_32, A_33) =
  ($(_undot(_det_tensor_rhs(:A, :scalar))),)

# The scalar-field action family: one scalar array broadcasts over the fiber, so the fused form
# reads it once per element where the broadcast route read it once per output component. The
# products commute bitwise (IEEE multiplication), so operand order here need not mirror the
# replaced broadcasts.
@inline _scale_vector_values(s, u_1, u_2, u_3) = (s * u_1, s * u_2, s * u_3)
@inline _scale_tensor_values(s, A_11, A_12, A_13, A_21, A_22, A_23, A_31, A_32, A_33) =
  (s * A_11, s * A_12, s * A_13, s * A_21, s * A_22, s * A_23, s * A_31, s * A_32, s * A_33)
@inline _scale_fiber_vector_values(s, a) = (s * a[1], s * a[2], s * a[3])
@inline _scale_fiber_tensor_values(s, A) =
  (s * A[1, 1], s * A[1, 2], s * A[1, 3], s * A[2, 1], s * A[2, 2], s * A[2, 3],
   s * A[3, 1], s * A[3, 2], s * A[3, 3])
@inline _divide_vector_values(s, u_1, u_2, u_3) = (u_1 / s, u_2 / s, u_3 / s)
@inline _divide_tensor_values(s, A_11, A_12, A_13, A_21, A_22, A_23, A_31, A_32, A_33) =
  (A_11 / s, A_12 / s, A_13 / s, A_21 / s, A_22 / s, A_23 / s, A_31 / s, A_32 / s, A_33 / s)
@inline _divide_fiber_vector_values(s, a) = (a[1] / s, a[2] / s, a[3] / s)
@inline _divide_fiber_tensor_values(s, A) =
  (A[1, 1] / s, A[1, 2] / s, A[1, 3] / s, A[2, 1] / s, A[2, 2] / s, A[2, 3] / s,
   A[3, 1] / s, A[3, 2] / s, A[3, 3] / s)


#############################################
#        The fiber: values at one point     #
#############################################
#
# The fiber is the value space at a single base point, so it is base-agnostic by construction — the
# same `FiberVector` serves a field over a grid and a point-value section over a scattered set. It
# therefore lives here rather than with either base.

"""
    FiberVector{T}

A `FiberVector{T}` is one static three-component Cartesian vector value.

This is an alias for `SVector{3, T}`, with scalar type `T`.
"""
const FiberVector{T} = SVector{3, T}


"""
    FiberTensor2{T}

A `FiberTensor2{T}` is one static second-order Cartesian tensor value.

This is an alias for `SMatrix{3, 3, T, 9}`, with scalar type `T`.
"""
const FiberTensor2{T} = SMatrix{3, 3, T, 9}


"""
    FiberTensor3{T}

A `FiberTensor3{T}` is one static third-order Cartesian tensor value.

This is an alias for `SArray{Tuple{3, 3, 3}, T, 3, 27}`, with scalar type `T`.
"""
const FiberTensor3{T} = SArray{Tuple{3, 3, 3}, T, 3, 27}


"""
    FiberTensor4{T}

A `FiberTensor4{T}` is one static fourth-order Cartesian tensor value.

This is an alias for `SArray{Tuple{3, 3, 3, 3}, T, 4, 81}`, with scalar type `T`.
"""
const FiberTensor4{T} = SArray{Tuple{3, 3, 3, 3}, T, 4, 81}


"""
    fiber_shape(::Val{R}) where {R}

Return the tensor-fiber shape associated with tensor order `R`.

For scalar fields, ``R = 0`` gives `()`. For higher tensor orders, each tensor index has length `3`,
so ``R = 1`` gives `(3,)`, ``R = 2`` gives `(3, 3)`, and so on.
"""
fiber_shape(::Val{0}) = ()
fiber_shape(::Val{R}) where {R} = ntuple(_ -> 3, Val(R))


#############################################
#        map! adapter (arbitrary φ)         #
#############################################
#
# The public `map!`/`map` (FieldAlgebra for fields, Points for point-values) apply an arbitrary fiber
# map φ over the base through the same `_fiberwise_pass!` executor as the stamped algebra. The executor
# hands its values function the flat component scalars of every input; this adapter groups them back
# into fibers, applies φ, and flattens the result — the only piece φ-specific, everything else reused.
# The component packing is column-major (`Tuple(::SMatrix)` order) so assembly is a bare `SMatrix`
# constructor and the flatten is a bare `Tuple`, no row/column permutation.

"""
    _section_order(section)

Read a section's tensor order as a `Val` from its `AbstractFiberSection{T, R}` type parameter —
the compile-time quantity the `map!` adapter unrolls over.
"""
@inline _section_order(::AbstractFiberSection{T, R}) where {T, R} = Val(R)


"""
    _fiber_component_count(::Val{R})

Count the stored scalar components of a fiber of tensor order `R` (`1`, `3`, `9`).
"""
@inline _fiber_component_count(::Val{0}) = 1
@inline _fiber_component_count(::Val{1}) = 3
@inline _fiber_component_count(::Val{2}) = 9


"""
    _assemble_fiber(::Val{R}, scalars, offset)

Assemble one fiber of order `R` from the `scalars` tuple, reading `_fiber_component_count(Val(R))`
entries starting after `offset`, in column-major order (so the tensor case is a direct `SMatrix`
constructor). The `scalars` tuple is homogeneous in the section scalar type, so its reads stay type-stable
even when `offset` is not a literal.
"""
@inline _assemble_fiber(::Val{0}, scalars, offset) = @inbounds scalars[offset + 1]
@inline _assemble_fiber(::Val{1}, scalars, offset) =
  @inbounds SVector(scalars[offset + 1], scalars[offset + 2], scalars[offset + 3])
@inline _assemble_fiber(::Val{2}, scalars, offset) =
  @inbounds SMatrix{3, 3}(scalars[offset + 1], scalars[offset + 2], scalars[offset + 3],
                          scalars[offset + 4], scalars[offset + 5], scalars[offset + 6],
                          scalars[offset + 7], scalars[offset + 8], scalars[offset + 9])


"""
    _assemble_inputs(orders, scalars, offset)

Split the flat `scalars` of all inputs into a tuple of assembled fibers, one per entry of `orders` (a
tuple of `Val{R}`), advancing `offset` by each fiber's component count. The recursion is over the
`orders` tuple, so it unrolls and the offsets fold to constants.
"""
@inline _assemble_inputs(::Tuple{}, scalars, offset) = ()
@inline _assemble_inputs(orders::Tuple, scalars, offset) =
  (_assemble_fiber(orders[1], scalars, offset),
   _assemble_inputs(Base.tail(orders), scalars, offset + _fiber_component_count(orders[1]))...)


"""
    _flatten_fiber(value)

Flatten an output fiber into the column-major tuple written to the targets: a scalar becomes a
one-tuple, a `StaticArray` its `Tuple`.
"""
@inline _flatten_fiber(value::Number) = (value,)
@inline _flatten_fiber(value::StaticArray) = Tuple(value)


# The type-parameter order matches the field order (`φ` then `orders`): the GPU backends reconstruct
# kernel-argument structs positionally, so a mismatch would swap the fields on the device.
"""
    _MapValues(φ, orders)

The values function [`_fiberwise_pass!`](@ref) runs for `map!`/`map`: it takes the flat input
component scalars, groups them into fibers by `orders` (a tuple of `Val{R}`), applies `φ`, and flattens
the result. A struct rather than a closure so the input count stays type-level (the `Vararg{Any, N}`
signature).

The fields are
- `φ` — the caller's fiber map, applied to the assembled fiber at each base point.
- `orders` — the tensor orders of the inputs, carried as a type parameter so the fiber assembly is
  resolved at compile time.
"""
struct _MapValues{F, Orders} <: Function
  φ::F
  orders::Orders
end

@inline (map_values::_MapValues)(scalars::Vararg{Any, N}) where {N} =
  _flatten_fiber(map_values.φ(_assemble_inputs(map_values.orders, scalars, 0)...))


"""
    _fiber_type(::Type{T}, ::Val{R})

Return the concrete fiber type of order `R` over scalar `T`: `T`, `SVector{3, T}`, or
`SMatrix{3, 3, T, 9}`, for inferring `φ`'s output order in the allocating `map`.
"""
@inline _fiber_type(::Type{T}, ::Val{0}) where {T} = T
@inline _fiber_type(::Type{T}, ::Val{1}) where {T} = FiberVector{T}
@inline _fiber_type(::Type{T}, ::Val{2}) where {T} = FiberTensor2{T}


"""
    _fiber_order(fiber_type)

Return a concrete fiber type's tensor order, `0`, `1` or `2`, or `-1` when the type is not a
recognized fiber (an un-inferrable `φ` return), on which the allocating `map` raises a clear error.
"""
@inline _fiber_order(::Type{<:Number}) = 0
@inline _fiber_order(::Type{<:SVector{3}}) = 1
@inline _fiber_order(::Type{<:SMatrix{3, 3}}) = 2
@inline _fiber_order(::Type) = -1


end # module FiberSections
