# The storage/aliasing product: every in-place operation × every way its arguments can share storage,
# crossed with the configuration axes (element type, grid shape, spectral layout, thread count).
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

# The configuration axes. A grid of mixed parity and unequal extents is included because an index
# defect can hide behind a cubic even grid, and a permuted fold because the folded axis moves.
struct Config
  name::String
  eltype::DataType
  grid::Grid3D
  layout::RealFourierLayout
  threaded::Bool
end

function configurations()
  cs = Config[]
  for T in (Float64, Float32)
    cubic = Grid3D((8, 8, 8), (T(2π), T(2π), T(2π)))
    mixed = Grid3D((8, 6, 5), (T(2π), T(4π), T(6π)))      # unequal, mixed parity, anisotropic
    for (gname, grid) in (("cubic", cubic), ("mixed", mixed)),
        (lname, layout) in (("fold1", RealFourierLayout()), ("fold2", RealFourierLayout((2, 1, 3)))),
        threaded in (false, true)
      push!(cs, Config("$(T)/$(gname)/$(lname)/$(threaded ? "threaded" : "serial")",
                       T, grid, layout, threaded))
    end
  end
  return cs
end

xshape(c::Config, R, cplx) =
  cplx ? GBGPeriodicFields.Fields.spectral_field_shape(c.grid, c.layout, Val(R)) :
         (c.grid.grid_size..., (R == 0 ? () : ntuple(_ -> 3, R))...)

# The five storage configurations. `viewP@0` and `viewP@1` are the pair that matters: two views of one
# parent offset by one along the first base axis, so one section's element n is the other's element n+1.
const POOL_NAMES = ("plain", "plain2", "viewP@0", "viewP@1", "viewQ@0")

function build_pool(c::Config, R, cplx)
  shape = xshape(c, R, cplx)
  T = cplx ? Complex{c.eltype} : c.eltype
  parent_shape = (shape[1] + 1, shape[2:end]...)
  P, Q = rand(T, parent_shape...), rand(T, parent_shape...)
  wrap(data) = cplx ?
    (R == 0 ? ScalarFieldSpectral(data, c.grid, c.layout) :
     R == 1 ? VectorFieldSpectral(data, c.grid, c.layout) : TensorFieldSpectral{2}(data, c.grid, c.layout)) :
    (R == 0 ? ScalarFieldPhysical(data, c.grid, c.layout) :
     R == 1 ? VectorFieldPhysical(data, c.grid, c.layout) : TensorFieldPhysical{2}(data, c.grid, c.layout))
  trailing = ntuple(_ -> Colon(), length(shape) - 3)
  entries = [wrap(rand(T, shape...)),
             wrap(rand(T, shape...)),
             wrap(view(P, 1:shape[1], :, :, trailing...)),
             wrap(view(P, 2:shape[1] + 1, :, :, trailing...)),
             wrap(view(Q, 1:shape[1], :, :, trailing...))]
  return (entries = entries, parents = (P, Q), pristine = (copy(P), copy(Q)), wrap = wrap)
end


"""
    aliasing_failures(config, orders, complexvalued, operation!) -> Vector{String}

Cross the pool over an operation's argument slots and return the names of the assignments whose result
disagrees with the same call on fresh disjoint copies.
"""
function aliasing_failures(c::Config, orders, complexvalued, operation!)
  distinct_orders = unique(orders)
  pools = Dict(R => build_pool(c, R, complexvalued) for R in distinct_orders)
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
    label = join((POOL_NAMES[combination[i]] for i in eachindex(combination)), " ← ")
    try
      operation!(reference...)
      operation!(arguments...)
      Array(field_data(arguments[1])) ≈ Array(field_data(reference[1])) && continue
      push!(failures, label)
    catch exception
      push!(failures, label * "  [threw $(nameof(typeof(exception)))]")
    end
  end
  return failures
end
