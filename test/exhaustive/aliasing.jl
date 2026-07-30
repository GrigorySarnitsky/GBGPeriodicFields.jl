# The storage/aliasing product: every in-place operation × every way its arguments can share storage.
#
# This lane exists because a per-slot sweep can never reach aliasing. Enumerating "what is each
# argument" builds each one separately, and two independently constructed arrays never share storage —
# so the probability that such a product produces an aliasing pair is zero, not small. Reaching it
# requires the slots to draw from ONE SHARED POOL whose entries are deliberately related.
#
# The pool below is that shared set. Crossing it over an operation's slots yields, without any special
# case: the same object twice (`dest === source`), two views of one parent at the SAME base indices,
# two views of one parent at DIFFERENT base indices, and two views of unrelated parents.
#
# The oracle is uniform and is exactly what invariant 9 claims: for every assignment, the result must
# equal the result computed from fresh disjoint copies of the same values. Aliasing may not change the
# answer.

using GBGPeriodicFields
using Statistics

const XN = 8
const XGRID = Grid3D((XN, XN, XN), (2π, 2π, 2π))
const XLAYOUT = RealFourierLayout()
xshape(R, cplx) = cplx ? GBGPeriodicFields.Fields.spectral_field_shape(XGRID, XLAYOUT, Val(R)) :
                         (XN, XN, XN, (R == 0 ? () : ntuple(_ -> 3, R))...)

# The five storage configurations. `viewP@0` and `viewP@1` are the pair that matters: two views of one
# parent offset by one along the first base axis, so one section's element n is the other's element n+1.
const POOL_NAMES = ("plain", "plain2", "viewP@0", "viewP@1", "viewQ@0")

function build_pool(R, cplx)
  shape = xshape(R, cplx)
  T = cplx ? ComplexF64 : Float64
  parent_shape = (shape[1] + 1, shape[2:end]...)
  P, Q = rand(T, parent_shape...), rand(T, parent_shape...)
  wrap(data) = cplx ?
    (R == 0 ? ScalarFieldSpectral(data, XGRID, XLAYOUT) :
     R == 1 ? VectorFieldSpectral(data, XGRID, XLAYOUT) : TensorFieldSpectral{2}(data, XGRID, XLAYOUT)) :
    (R == 0 ? ScalarFieldPhysical(data, XGRID, XLAYOUT) :
     R == 1 ? VectorFieldPhysical(data, XGRID, XLAYOUT) : TensorFieldPhysical{2}(data, XGRID, XLAYOUT))
  trailing = ntuple(_ -> Colon(), length(shape) - 3)
  entries = [wrap(rand(T, shape...)),
             wrap(rand(T, shape...)),
             wrap(view(P, 1:shape[1], :, :, trailing...)),
             wrap(view(P, 2:shape[1] + 1, :, :, trailing...)),
             wrap(view(Q, 1:shape[1], :, :, trailing...))]
  return (entries = entries, parents = (P, Q), pristine = (copy(P), copy(Q)), wrap = wrap)
end


"""
    aliasing_failures(orders, complexvalued, operation!) -> Vector{String}

Cross the pool over an operation's argument slots and return the names of the assignments whose result
disagrees with the same call on fresh disjoint copies.
"""
function aliasing_failures(orders, complexvalued, operation!)
  distinct_orders = unique(orders)
  pools = Dict(R => build_pool(R, complexvalued) for R in distinct_orders)
  slots = [pools[R].entries for R in orders]
  failures = String[]
  for combination in Iterators.product((eachindex(s) for s in slots)...)
    for R in distinct_orders                       # every case starts from the same parent state
      copyto!(pools[R].parents[1], pools[R].pristine[1])
      copyto!(pools[R].parents[2], pools[R].pristine[2])
    end
    arguments = [slots[i][combination[i]] for i in eachindex(slots)]
    values = [Array(field_data(a)) for a in arguments]
    reference = [pools[orders[i]].wrap(copy(values[i])) for i in eachindex(arguments)]
    try
      operation!(reference...)
      operation!(arguments...)
      Array(field_data(arguments[1])) ≈ Array(field_data(reference[1])) && continue
      push!(failures, join((POOL_NAMES[combination[i]] for i in eachindex(combination)), " ← "))
    catch exception
      push!(failures, join((POOL_NAMES[combination[i]] for i in eachindex(combination)), " ← ") *
                      "  [threw $(nameof(typeof(exception)))]")
    end
  end
  return failures
end
