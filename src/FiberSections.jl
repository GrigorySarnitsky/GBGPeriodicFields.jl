"""
    FiberSections

Base-agnostic core of the package's fiber-bundle model.

A field (a section over a `Grid3D`) and a collection of off-grid point-values (a section over a
`PointSet`) are both sections of a tensor bundle over a base. This module owns the part of the
design that does not depend on which base is used, and it groups four families of
contributor-facing machinery:

- the [`AbstractFiberSection`](@ref) supertype, which both fields and point-values subtype;
- the CPU-threading, fused-assignment primitive [`_assign!`](@ref) and its policy controls
  ([`with_threading`](@ref), [`threading_cutoff`](@ref), and [`set_threading_cutoff!`](@ref));
- the fiberwise-algebra code generators — the per-component builders behind operations such as `dot`, `cross`, and `norm` —
  written once here so that one set of generated kernels serves both field and point-value
  sections;
- the fused fiberwise executor [`_fiberwise_pass!`](@ref) — one portable kernel and one
  slab-threaded CPU loop that run every stamped per-element values function, the execution route
  for multi-output fiberwise operations.

The base-specific halves live elsewhere. `Fields` (grid) and `Points` (point set) hold the
concrete types, the section-interface accessors (`field_data`, `_vector_component_data`, and
`_tensor2_component_data`), `fiber_shape`, and the broadcast styles, each extending the accessors
for its own types, while `FieldAlgebra` and `Points` stamp the method tables from the builders
here.
"""
module FiberSections

using Base.ScopedValues: ScopedValue

# The fused fiberwise executor below launches one portable KernelAbstractions kernel on a device
# and a slab-threaded plain loop on the CPU, dispatched on the backend (the decision-30 idiom;
# the `import` carries `KernelAbstractions.CPU` for that dispatch).
import KernelAbstractions
using KernelAbstractions: @kernel, @index, get_backend, synchronize

export AbstractFiberSection,
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
    section_scalar_type(section::AbstractFiberSection)

Return the real scalar type `T` of any section. Because it is defined once on
`AbstractFiberSection{T}`, it yields the real `T` for fields (including spectral fields, whose
data is `Complex{T}`) and for point-values alike, which lets the shared `sym`/`skew`/`dev`
kernels obtain `T` without dispatching on the concrete base.
"""
section_scalar_type(::AbstractFiberSection{T}) where {T<:AbstractFloat} = T


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

Task-local override for the threading decision. A value of `nothing` follows
`Threads.nthreads()`, while `true` or `false` forces the threaded or serial path.
[`with_threading`](@ref) sets it within a dynamic scope.
"""
const _THREADING_OVERRIDE = ScopedValue{Union{Nothing, Bool}}(nothing)


"""
    _SERIAL_CUTOFF

Element count below which an assignment runs serially regardless of thread count. Threading
overhead is not worth it for small arrays, and this cutoff also exempts the one-element
zero-mode views. The assignment hot path reads it, and [`set_threading_cutoff!`](@ref) sets it.
"""
const _SERIAL_CUTOFF = Ref(1 << 14)


"""
    with_threading(f; enabled::Union{Nothing, Bool} = true)

Run `f()` with the CPU-threading decision forced to `enabled`, then restore the previous setting.
Pass `true` or `false` to force the threaded or serial path, or `nothing` to follow the automatic
`nthreads()`-based policy. The override is dynamically scoped and task-local, so it affects only
`f()` and is restored afterwards, including on exceptions. Use `enabled = false` around a region
that already parallelizes at a higher level, to avoid oversubscription.

!!! warning "Two operation families thread outside this override"
    The override (and the cutoff) governs the fused broadcast assignments, the fused CPU loops
    behind the algebra and the spectral operators (`helmholtz_projection!` included), and the
    fixed-tree reductions. Two operation families run as portable device-style kernels on **every**
    backend and partition by `Threads.nthreads()` directly, ignoring this setting: the grid↔point
    transfer (`interpolate!`/`anterpolate!`) and the radial diagnostics
    (`radial_spectrum`/`radial_correlation`) — the kernels with atomic or irregular access, which a
    gated loop cannot serve. To run those serially, start Julia with one thread.
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
set_threading_cutoff!(n::Integer) = (_SERIAL_CUTOFF[] = Int(n); Int(n))


"""
    threading_cutoff()

Return the element count at or above which a CPU field assignment is split across `Base.Threads`
workers rather than run serially. Here an assignment is a fused elementwise write into field
storage — the [`_assign!`](@ref) primitive behind the broadcast route, and the same gate guards the
fused CPU loops behind the algebra and the spectral operators, and the fixed-tree reductions. Two
operation families sit outside the gate and thread by `Threads.nthreads()` regardless (see the
warning on [`with_threading`](@ref)): the grid↔point transfer and the radial diagnostics. The count is measured as the destination array's length (grid points
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


"""
    _assign!(destination, broadcasted)

Materialize the lazy `broadcasted` expression into `destination`, threading over chunks on the
CPU when [`_use_threads`](@ref) allows. The generic method is the standard fused
`Broadcast.materialize!`, the safe polarity that keeps GPU arrays and unknown array wrappers on
their normal broadcast path with no scalar indexing. Only dense `Array`s and `Array`-backed
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
such as `f.(x)` — into the equivalent lazy `Base.Broadcast.broadcasted(...)` tree, recursing into
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

Combine a non-empty collection of expressions into a broadcasted sum `term_1 .+ term_2 .+ …`.
"""
_sum_terms(terms) = reduce((accumulated, term) -> :($accumulated .+ $term), terms)


"""
    _product(x, y)

Build the broadcasted product expression `x .* y`.
"""
_product(x, y) = :($x .* $y)


"""
    _vector_kernel_body(formula; alpha_beta::Bool)

Build the body of a vector-valued kernel, writing `destination_i .= formula(i)` for `i in 1:3`, where `formula(i)` is the per-component expression. With `alpha_beta = true` it emits the five-argument `destination = α * formula + β * destination` form and branches on `iszero(β_value)`, so the pure-overwrite path stays allocation-free. The body ends in `return destination` and is spliced into a function that binds `destination` (and, when `alpha_beta` is set, `α_value` and `β_value`).
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

Build the body of a second-order tensor-valued kernel, writing `destination_ij .= formula(i, j)` for `i, j in 1:3`, with the same `alpha_beta` five-argument behaviour as `_vector_kernel_body`.
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
# comes from `section_scalar_type` so the same body serves fields and point-values.


"""
    _norm_scalar_rhs(symbol)

Build the right-hand side for the scalar norm, the pointwise absolute value ``|\\varphi|``. It feeds `_scalar_kernel_body`.
"""
_norm_scalar_rhs(symbol) = :(abs.(field_data($symbol)))


"""
    _norm_vector_rhs(symbol, kind)

Build the right-hand side for the vector Euclidean norm ``\\sqrt{\\sum_i u_i^2}``. It feeds `_scalar_kernel_body`.
"""
_norm_vector_rhs(symbol, kind) =
  :(sqrt.($(_sum_terms([:(abs2.($(_vector_component(symbol, kind, i)))) for i in 1:3]))))


"""
    _norm_tensor_rhs(symbol, kind)

Build the right-hand side for the tensor Frobenius norm ``\\sqrt{\\sum_{ij} A_{ij}^2}``. It feeds `_scalar_kernel_body`.
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
\\det(A) = A_{11}(A_{22}A_{33} - A_{23}A_{32}) - A_{12}(A_{21}A_{33} - A_{23}A_{31}) + A_{13}(A_{21}A_{32} - A_{22}A_{31}).
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
    _write_values!(targets, values, alpha, n)

Write `alpha * values[i]` into `targets[i][n]` for every output, unrolled over the (static)
output count. The real `alpha` keeps the multiply exact for `alpha = 1`, so the plain
(non-``\\alpha``/``\\beta``) forms stay bitwise-identical to their broadcast predecessors.
"""
@inline function _write_values!(targets::NTuple{N, Any}, values::NTuple{N, Any}, alpha, n) where {N}
  ntuple(i -> (@inbounds targets[i][n] = alpha * values[i]; nothing), Val(N))
  return nothing
end


"""
    _accumulate_values!(targets, values, alpha, beta, n)

The ``\\beta \\ne 0`` counterpart of [`_write_values!`](@ref): write
`alpha * values[i] + beta * targets[i][n]`, mirroring the accumulate branch of the broadcast
kernel bodies expression for expression.
"""
@inline function _accumulate_values!(targets::NTuple{N, Any}, values::NTuple{N, Any}, alpha, beta, n) where {N}
  ntuple(i -> (@inbounds targets[i][n] = alpha * values[i] + beta * targets[i][n]; nothing), Val(N))
  return nothing
end


# One work-item per element: apply the values function and write every output, the α/β branch
# uniform across items. The source arrays are deliberately not @Const: a target may alias a
# source (the aliased cross!/transpose! in place), and all of an element's reads precede its
# writes, so the aliased call is safe and bitwise-identical to the non-aliased one.
@kernel function _fiberwise_values_kernel!(f, targets, arrays, constants, alpha, beta)
  n = @index(Global, Linear)
  @inbounds begin
    values = f(map(array -> array[n], arrays)..., constants...)
    if iszero(beta)
      _write_values!(targets, values, alpha, n)
    else
      _accumulate_values!(targets, values, alpha, beta, n)
    end
  end
end


"""
    _fiberwise_pass!(backend, f, targets, arrays, constants, alpha, beta)

Run one fused fiberwise pass — every target element receives `alpha * f(element values..., constants...)`, plus `beta` times its prior value when the accumulate is requested — over the common
linear index range of the participating storage. Here `f` is a pure scalar values function: it
takes one scalar per entry of `arrays` (that array's element at the running index) followed by
the fiber `constants` verbatim, and returns the tuple of output values written to `targets`.
Every array element is read once and every output written once, and all of an element's reads
happen before its writes, so a target may alias a source array — the index-shuffle guard is
unnecessary on this path. The generic method launches the `_fiberwise_values_kernel!` device kernel on the
backend; the `KernelAbstractions.CPU` method runs a slab-threaded `@simd` loop over the linear
range (component views are contiguous, so linear indexing is stride-1) through the same
[`_use_threads`](@ref) gate as the broadcast route, bitwise-identical to serial because each
element is written once from the same expression.
"""
function _fiberwise_pass!(backend, f::F, targets, arrays, constants, alpha, beta) where {F}
  _fiberwise_values_kernel!(backend)(f, targets, arrays, constants, alpha, beta;
                                     ndrange = length(targets[1]))
  synchronize(backend)
  return nothing
end

function _fiberwise_pass!(::KernelAbstractions.CPU, f::F, targets::NTuple{NT, Any},
    arrays, constants, alpha, beta) where {F, NT}
  elements = eachindex(targets[1])
  _use_threads(NT * length(elements)) ||
    return _fiberwise_slab!(f, targets, arrays, constants, alpha, beta, elements)
  @sync for slab in _index_ranges(elements, Threads.nthreads())
    Threads.@spawn _fiberwise_slab!(f, targets, arrays, constants, alpha, beta, slab)
  end
  return nothing
end


"""
    _fiberwise_slab!(f, targets, arrays, constants, alpha, beta, elements)

Run [`_fiberwise_pass!`](@ref)'s loop over one contiguous slab of the linear index range, the
``\\beta`` branch hoisted out of the loop (the package-wide overwrite-vs-accumulate convention: ``\\beta = 0`` never reads the destination).
"""
function _fiberwise_slab!(f::F, targets, arrays, constants, alpha, beta, elements) where {F}
  if iszero(beta)
    @inbounds @simd for n in elements
      _write_values!(targets, f(map(array -> array[n], arrays)..., constants...), alpha, n)
    end
  else
    @inbounds @simd for n in elements
      _accumulate_values!(targets, f(map(array -> array[n], arrays)..., constants...), alpha, beta, n)
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
# scalar type from the first argument, exactly as the broadcast bodies took `section_scalar_type`.

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


end # module FiberSections
