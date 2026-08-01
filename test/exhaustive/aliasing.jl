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
  seed::Int
end

function configurations(; seeds = (20260731, 815, 4241))
  cs = Config[]
  for T in (Float64, Float32)
    cubic = Grid3D((8, 8, 8), (T(2π), T(2π), T(2π)))
    mixed = Grid3D((8, 6, 5), (T(2π), T(4π), T(6π)))      # unequal, mixed parity, anisotropic
    # THE ORIGIN AXIS. Every configuration used origin 0, so an operation that forgets to subtract the
    # origin — every position-dependent one: the transfer verbs, the translation kernel, the DFT phase —
    # agreed with a correct implementation in every cell the suite ran. A shifted, non-commensurate
    # origin is the fixture that can falsify it.
    # The four-argument constructor is the only one taking an origin, and it enforces that the spacing
    # matches `domain_size ./ grid_size` (decision 45), so the spacing is passed explicitly.
    shifted = Grid3D((8, 6, 5), (T(2π), T(4π), T(6π)),
                     (T(2π) / 8, T(4π) / 6, T(6π) / 5), (T(0.3), T(-1.1), T(0.7)))
    # Odd on every axis, including the folded one: the rfft fold has no Nyquist plane at all there, so
    # every "even Nyquist" special case must be skipped rather than taken. Decision 41's bugs lived in
    # exactly this corner.
    odd = Grid3D((7, 5, 3), (T(2π), T(2π), T(2π)))
    for (gname, grid) in (("cubic", cubic), ("mixed", mixed), ("shifted", shifted), ("odd", odd)),
        (lname, layout) in (("fold1", RealFourierLayout()), ("fold2", RealFourierLayout((2, 1, 3)))),
        threaded in (false, true), seed in seeds
      push!(cs, Config("$(T)/$(gname)/$(lname)/$(threaded ? "threaded" : "serial")/seed$(seed)",
                       T, grid, layout, threaded, seed))
    end
  end
  return cs
end

xshape(c::Config, R, cplx) =
  cplx ? GBGPeriodicFields.Fields.spectral_field_shape(c.grid, c.layout, Val(R)) :
         (c.grid.grid_size..., (R == 0 ? () : ntuple(_ -> 3, R))...)

# The pool. Since decision 59 a section must OWN its storage, so the view entries are no longer fields
# that might misbehave — they are constructions that must be REFUSED, and the lane asserts that instead.
# The aliasing axis is therefore fully enumerable rather than merely sampled: two sections can share
# storage only by being backed by the same array, which is `plain ← plain`.
const POOL_NAMES = ("plain", "plain2", "same-object")

function build_pool(c::Config, R, cplx)
  shape = xshape(c, R, cplx)
  T = cplx ? Complex{c.eltype} : c.eltype
  wrap(data) = cplx ?
    (R == 0 ? ScalarFieldSpectral(data, c.grid, c.layout) :
     R == 1 ? VectorFieldSpectral(data, c.grid, c.layout) : TensorFieldSpectral{2}(data, c.grid, c.layout)) :
    (R == 0 ? ScalarFieldPhysical(data, c.grid, c.layout) :
     R == 1 ? VectorFieldPhysical(data, c.grid, c.layout) : TensorFieldPhysical{2}(data, c.grid, c.layout))
  # No parent scaffolding: decision 59 removed the view entries those parents existed for, and the
  # per-combination restore of them was a no-op copied twice per case for 96 configurations.
  shared = wrap(rand(T, shape...))
  return (entries = [wrap(rand(T, shape...)), wrap(rand(T, shape...)), shared], wrap = wrap)
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
    arguments = [slots[i][combination[i]] for i in eachindex(slots)]
    values = [Array(field_data(a)) for a in arguments]
    reference = [pools[orders[i]].wrap(copy(values[i])) for i in eachindex(arguments)]
    label = join((POOL_NAMES[combination[i]] for i in eachindex(combination)), " ← ")
    try
      operation!(reference...)
      operation!(arguments...)
      # `==`, not `≈`. Invariant 9 states the aliased result is BITWISE-identical, and `isapprox` on
      # arrays is norm-based at `rtol = √eps(T)` — 3.4e-4 for Float32 — so a corruption concentrated in
      # one element of a 1536-element array passed. The strong claim deserves the strong comparison.
      isequal(Array(field_data(arguments[1])), Array(field_data(reference[1]))) && continue
      push!(failures, label)
    catch exception
      push!(failures, label * "  [threw $(nameof(typeof(exception)))]")
    end
  end
  return failures
end


"""
    refused_constructions(config, R, complexvalued) -> Vector{String}

Return the names of the borrowed-storage constructions this configuration FAILED to reject.

Since decision 59 a section owns its storage, which is what makes the aliasing axis finite: two
sections can share memory only by being the same array. These are the constructions that closed the
class, so the lane checks they stay closed rather than checking the arithmetic that used to break.
"""
function refused_constructions(c::Config, R, cplx)
  shape = xshape(c, R, cplx)
  T = cplx ? Complex{c.eltype} : c.eltype
  P = rand(T, (shape[1] + 1, shape[2:end]...)...)
  flat = rand(T, prod(shape) + 1)
  trailing = ntuple(_ -> Colon(), length(shape) - 3)
  wrap(data) = cplx ?
    (R == 0 ? ScalarFieldSpectral(data, c.grid, c.layout) :
     R == 1 ? VectorFieldSpectral(data, c.grid, c.layout) : TensorFieldSpectral{2}(data, c.grid, c.layout)) :
    (R == 0 ? ScalarFieldPhysical(data, c.grid, c.layout) :
     R == 1 ? VectorFieldPhysical(data, c.grid, c.layout) : TensorFieldPhysical{2}(data, c.grid, c.layout))
  candidates = (("view offset",          () -> wrap(view(P, 1:shape[1], :, :, trailing...))),
                ("view full",            () -> wrap(view(rand(T, shape...), :, :, :, trailing...))),
                ("reshape(view) offset", () -> wrap(reshape(view(flat, 2:prod(shape) + 1), shape...))))
  accepted = String[]
  for (name, build) in candidates
    try
      build()
      push!(accepted, name)               # constructed when it should have been refused
    catch exception
      # The exception TYPE, as the mismatch and domain-rejection filters already do. A bare `catch`
      # counts a `MethodError` from a renamed constructor as a correct refusal — and this is the one
      # place guarding decision 59's storage-ownership rejection, so a silent regression there would
      # read as the refusal still holding.
      # The same set the mismatch and domain-rejection filters use — the comment above claimed parity
      # with them while accepting only two of the four.
      exception isa ArgumentError || exception isa DimensionMismatch ||
      exception isa InexactError || exception isa DomainError ||
        push!(accepted, "$(name) [refused with $(nameof(typeof(exception))), not a domain error]")
    end
  end
  return accepted
end
