"""
    FiberSections

Base-agnostic core of the package's fiber-bundle model.

A field (a section over a `Grid3D`) and a collection of off-grid point-values (a section over a
`PointSet`) are both *sections of a tensor bundle over a base* (`docs/ARCHITECTURE.md` §2). This
module owns the part of the design that does not depend on the base: the `AbstractFiberSection`
supertype, the CPU-threading / fused-assignment primitive `_assign!`, and the vertical-algebra
**code generators** (the per-component formula and kernel-body builders) — written once here so
that one set of generated kernels serves both field and point-value sections.

The base-specific halves live elsewhere: the concrete types, the section-interface accessors
(`field_data`, `_vector_component_data`, `_tensor2_component_data`), `fiber_shape`, and the
broadcast styles are in `Fields` (grid) and `Points` (point set), each extending the accessors
for its own types; `FieldAlgebra` and `Points` stamp the method tables from the builders here.
"""
module FiberSections

using Base.ScopedValues: ScopedValue

export AbstractFiberSection,
       with_threading,
       set_threading_cutoff!,
       threading_cutoff


"""
    AbstractFiberSection{T, R}

Supertype of every section of the package's tensor bundle: fields (sections over a `Grid3D`,
in physical-space or spectral representation) and point-values (sections over a `PointSet`).

Here `T<:AbstractFloat` is the real scalar type and `R` the tensor order (`0` scalar, `1` vector,
`2` second-order tensor, and so on). The fiberwise algebra is rooted at this supertype because it
is base-independent — the same operation on the same fiber type regardless of whether the base is
a structured grid or an unstructured point set (`docs/ARCHITECTURE.md` §2).
"""
abstract type AbstractFiberSection{T<:AbstractFloat, R} end


"""
    section_scalar_type(section::AbstractFiberSection)

Return the real scalar type `T` of any section. Defined once on `AbstractFiberSection{T}`, so it
gives the real `T` for fields (including spectral fields, whose data is `Complex{T}`) and for
point-values alike — letting the shared `sym`/`skew`/`dev` kernels obtain `T` without dispatching
on the concrete base.
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

Task-local override for the threading decision: `nothing` follows `Threads.nthreads()`,
`true`/`false` force threaded/serial. Set within a dynamic scope by [`with_threading`](@ref).
"""
const _THREADING_OVERRIDE = ScopedValue{Union{Nothing, Bool}}(nothing)


"""
    _SERIAL_CUTOFF

Element count below which an assignment runs serially regardless of thread count: threading
overhead is not worth it for small arrays, and this exempts the one-element zero-mode views.
Read in the assignment hot path; set with [`set_threading_cutoff!`](@ref).
"""
const _SERIAL_CUTOFF = Ref(1 << 14)


"""
    with_threading(f; enabled = true)

Run `f()` with the CPU-threading decision forced to `enabled` (`true`/`false`, or `nothing`
for the automatic `nthreads()`-following policy). The override is dynamically scoped and
task-local: it affects only `f()` and is restored afterwards, including on exceptions. Use
`enabled = false` around a region that already parallelizes at a higher level, to avoid
oversubscription.
"""
with_threading(f; enabled::Union{Nothing, Bool} = true) =
  Base.ScopedValues.with(f, _THREADING_OVERRIDE => enabled)


"""
    set_threading_cutoff!(n)

Set the element-count threshold below which assignments run serially. Returns `n`.
See [`threading_cutoff`](@ref).
"""
set_threading_cutoff!(n::Integer) = (_SERIAL_CUTOFF[] = Int(n); Int(n))


"""
    threading_cutoff()

The current element-count threshold below which assignments run serially.
"""
threading_cutoff() = _SERIAL_CUTOFF[]


"""
    _use_threads(element_count)

Whether an assignment over `element_count` elements should be threaded: at or above the serial
cutoff, and either forced on or — under the automatic policy — `Threads.nthreads() > 1`.
"""
@inline function _use_threads(element_count::Integer)
  element_count < _SERIAL_CUTOFF[] && return false
  override = _THREADING_OVERRIDE[]
  return override === nothing ? Threads.nthreads() > 1 : override
end


"""
    _index_ranges(axis, n)

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

Materialize the lazy `broadcasted` expression into `destination`, threaded over chunks on the
CPU when [`_use_threads`](@ref) allows. The generic method is the standard fused
`Broadcast.materialize!` — the safe polarity that keeps GPU arrays and unknown array wrappers
on their normal broadcast path (no scalar indexing, honouring invariant 6). Only dense
`Array`s and `Array`-backed `SubArray`s take the threaded path.
"""
_assign!(destination, broadcasted::Base.Broadcast.Broadcasted) =
  Base.Broadcast.materialize!(destination, broadcasted)

function _assign!(destination::Union{Array, SubArray{<:Any, <:Any, <:Array}}, broadcasted::Base.Broadcast.Broadcasted)
  _use_threads(length(destination)) || return Base.Broadcast.materialize!(destination, broadcasted)
  return _assign_threaded!(destination, broadcasted)
end


"""
    _assign_threaded!(destination, broadcasted)

Thread a fused broadcast assignment over contiguous chunks of `destination`'s linear index
range. Each task converts its linear indices to Cartesian ones and writes the corresponding
broadcast elements, so fusion is preserved (one `Broadcasted` tree, no temporaries) and the
result is bitwise-identical to serial (each index is written by exactly one task). Cartesian
indexing of the `Broadcasted` works on every supported Julia version and correctly remaps
singleton operand axes — linear indexing of a multidimensional `Broadcasted` is only
supported on Julia ≥ 1.12. Falls back to serial when the axes do not match (defensive; the
field kernels always match).
"""
function _assign_threaded!(destination, broadcasted::Base.Broadcast.Broadcasted)
  instantiated = Base.Broadcast.instantiate(broadcasted)
  axes(instantiated) == axes(destination) || return Base.Broadcast.materialize!(destination, instantiated)

  cartesian = CartesianIndices(destination)
  @sync for chunk in _index_ranges(Base.OneTo(length(destination)), Threads.nthreads())
    Threads.@spawn @inbounds for linear_index in chunk
      index = cartesian[linear_index]
      destination[index] = instantiated[index]
    end
  end
  return destination
end


"""
    _assign!(destination, source)

Fallback for a non-`Broadcasted` right-hand side (e.g. a bare component view from a transpose,
or a constant): wrap it as an identity broadcast so the same threaded assignment path applies.
"""
_assign!(destination, source) = _assign!(destination, Base.Broadcast.broadcasted(identity, source))


"""
    _to_broadcasted(expr)

Codegen helper operating on expressions: rewrite a dotted expression — infix dotted operators
(`a .* b .+ c`) and broadcast calls (`f.(x)`) — into the equivalent lazy
`Base.Broadcast.broadcasted(...)` tree, recursing into operands and leaving non-broadcast
subexpressions untouched. Lets generated and hand-written kernels route a fused assignment
through [`_assign!`](@ref) without materializing intermediates (fusion is preserved).
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

Threaded replacement for a fused broadcast assignment: rewrite `rhs` to a lazy broadcast tree
(via [`_to_broadcasted`](@ref)) and assign it through [`_assign!`](@ref), so the write threads
on the CPU. Use in hand-written kernels in place of `.=`. (`_assign!` must be in scope at the
call site.)
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

Build the expression accessing component `i` of a vector argument named `symbol`. `kind = :field` reads a field's component view (`_vector_component_data`); `kind = :fiber` indexes a constant `SVector`. Spliced into kernel formulas so each per-component formula is written once.
"""
_vector_component(symbol, kind, i)    = kind === :field ? :(_vector_component_data( $symbol, $i))     : :($symbol[$i])

"""
    _tensor_component(symbol, kind, i, j)

Build the expression accessing component `(i, j)` of a second-order tensor argument named `symbol`. `kind = :field` reads a field's component view (`_tensor2_component_data`); `kind = :fiber` indexes a constant `SMatrix`.
"""
_tensor_component(symbol, kind, i, j) = kind === :field ? :(_tensor2_component_data($symbol, $i, $j)) : :($symbol[$i, $j])


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

Build the body of a vector-valued kernel: `destination_i .= formula(i)` for `i in 1:3`, where `formula(i)` is the per-component expression. With `alpha_beta = true`, emit the five-argument `destination = α * formula + β * destination` form, branching on `iszero(β_value)` so the pure-overwrite path stays allocation-free. The body ends in `return destination` and is spliced into a function binding `destination` (and, when `alpha_beta`, `α_value`/`β_value`).
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

As `_vector_kernel_body`, but for a second-order tensor-valued kernel: `destination_ij .= formula(i, j)` for `i, j in 1:3`, with the same `alpha_beta` five-argument behaviour.
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

Build the body of a scalar-field-valued kernel (a contraction with a scalar result): `field_data(destination) .= rhs`, ending in `return destination`.
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

Build the right-hand-side expression for a vector inner product, ``\\sum_i u_i v_i`` — a single broadcasted expression fed to `_scalar_kernel_body`. Operand `kind`s are `:field` or `:fiber`, as in `_vector_component`.
"""
_dot_vector_rhs(u_symbol, u_kind, v_symbol, v_kind) =
  _sum_terms([_product(_vector_component(u_symbol, u_kind, i), _vector_component(v_symbol, v_kind, i)) for i in 1:3])


"""
    _dot_tensor_rhs(A_symbol, A_kind, B_symbol, B_kind)

Build the right-hand-side expression for the tensor Frobenius inner product, ``\\sum_{ij} A_{ij} B_{ij}``, fed to `_scalar_kernel_body`.
"""
_dot_tensor_rhs(A_symbol, A_kind, B_symbol, B_kind) =
  _sum_terms([_product(_tensor_component(A_symbol, A_kind, i, j), _tensor_component(B_symbol, B_kind, i, j)) for i in 1:3 for j in 1:3])


"""
    _cross_formula(left_symbol, left_kind, right_symbol, right_kind)

Return a per-component function `i -> expr` for the cross product: with cyclic `(j, k)`, component `i` is ``u_j v_k - u_k v_j``. Feeds `_vector_kernel_body`.
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

Return a per-component function `i -> expr` for the tensor-on-vector left action, component `i` being ``\\sum_j A_{ij} u_j``. Feeds `_vector_kernel_body`.
"""
_tensor_vector_formula(A_symbol, A_kind, u_symbol, u_kind) =
  i -> _sum_terms([_product(_tensor_component(A_symbol, A_kind, i, j), _vector_component(u_symbol, u_kind, j)) for j in 1:3])


"""
    _vector_tensor_formula(u_symbol, u_kind, A_symbol, A_kind)

Return a per-component function `i -> expr` for the vector-on-tensor right action, component `i` being ``\\sum_j u_j A_{ji}``. Feeds `_vector_kernel_body`.
"""
_vector_tensor_formula(u_symbol, u_kind, A_symbol, A_kind) =
  i -> _sum_terms([_product(_vector_component(u_symbol, u_kind, j), _tensor_component(A_symbol, A_kind, j, i)) for j in 1:3])


"""
    _tensor_tensor_formula(A_symbol, A_kind, B_symbol, B_kind)

Return a per-component function `(i, j) -> expr` for the tensor-tensor product, component `(i, j)` being ``\\sum_k A_{ik} B_{kj}``. Feeds `_tensor_kernel_body`.
"""
_tensor_tensor_formula(A_symbol, A_kind, B_symbol, B_kind) =
  (i, j) -> _sum_terms([_product(_tensor_component(A_symbol, A_kind, i, k), _tensor_component(B_symbol, B_kind, k, j)) for k in 1:3])


"""
    _transpose_formula(A_symbol, A_kind)

Return a per-component function `(i, j) -> expr` for the transpose, component `(i, j)` being ``A_{ji}``. Feeds `_tensor_kernel_body`.
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

Right-hand side for the scalar norm — the pointwise absolute value ``|\\varphi|``. Fed to `_scalar_kernel_body`.
"""
_norm_scalar_rhs(symbol) = :(abs.(field_data($symbol)))


"""
    _norm_vector_rhs(symbol, kind)

Right-hand side for the vector Euclidean norm ``\\sqrt{\\sum_i u_i^2}``. Fed to `_scalar_kernel_body`.
"""
_norm_vector_rhs(symbol, kind) =
  :(sqrt.($(_sum_terms([:(abs2.($(_vector_component(symbol, kind, i)))) for i in 1:3]))))


"""
    _norm_tensor_rhs(symbol, kind)

Right-hand side for the tensor Frobenius norm ``\\sqrt{\\sum_{ij} A_{ij}^2}``. Fed to `_scalar_kernel_body`.
"""
_norm_tensor_rhs(symbol, kind) =
  :(sqrt.($(_sum_terms([:(abs2.($(_tensor_component(symbol, kind, i, j)))) for i in 1:3 for j in 1:3]))))


"""
    _sym_kernel_body()

Body of the symmetric-part kernel ``\\operatorname{sym}(A) = \\tfrac12\\,(A + A^\\top)`` for a section
argument named `A` writing into `destination`. The `half` local takes the section's real scalar type
from `section_scalar_type(A)`. Index-shuffling, so callers wrap it through their alias guard.
"""
_sym_kernel_body() = quote
  half = inv(section_scalar_type(A)(2))
  $(_tensor_kernel_body((i, j) -> i == j ? _tensor_component(:A, :field, i, i) :
      :(half .* ($(_tensor_component(:A, :field, i, j)) .+ $(_tensor_component(:A, :field, j, i)))); alpha_beta = false))
end


"""
    _skew_kernel_body()

Body of the skew-symmetric-part kernel ``\\operatorname{skew}(A) = \\tfrac12\\,(A - A^\\top)``; see `_sym_kernel_body`.
"""
_skew_kernel_body() = quote
  half = inv(section_scalar_type(A)(2))
  $(_tensor_kernel_body((i, j) -> i == j ? :(zero(section_scalar_type(A))) :
      :(half .* ($(_tensor_component(:A, :field, i, j)) .- $(_tensor_component(:A, :field, j, i)))); alpha_beta = false))
end


"""
    _dev_kernel_body()

Body of the deviatoric-part kernel ``\\operatorname{dev}(A) = A - \\tfrac13\\,\\operatorname{tr}(A)\\,I``; see `_sym_kernel_body`.
"""
_dev_kernel_body() = quote
  third = inv(section_scalar_type(A)(3))
  trace = $(_sum_terms([_tensor_component(:A, :field, d, d) for d in 1:3]))
  $(_tensor_kernel_body((i, j) -> i == j ? :($(_tensor_component(:A, :field, i, i)) .- third .* trace) :
      _tensor_component(:A, :field, i, j); alpha_beta = false))
end


end # module FiberSections
