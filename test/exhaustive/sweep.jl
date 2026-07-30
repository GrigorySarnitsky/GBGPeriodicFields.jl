# The sweep: every operation × every argument assignment × every configuration, checked against an
# INDEPENDENT reference.
#
# The oracle is the whole point. An earlier version compared an aliased call against an unaliased one —
# the package against itself — which sees a defect that depends on aliasing and is blind to every
# defect that does not. A wrong cross product is wrong identically on both sides and reports clean.
#
# Here each operation is checked against `references.jl`, which computes the same quantity from raw
# arrays by the plainest expression of the definition, sharing no code with the implementation. That
# also subsumes the aliasing question: if a call whose destination aliases an input still produces the
# right answer, aliasing did not break it. One oracle, not two.
#
# Inputs are SNAPSHOT before the call, because an in-place operation may overwrite an argument it also
# reads; the reference is computed from the snapshots, which is what the answer must equal.

using GBGPeriodicFields

include("references.jl")

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
    for (gname, grid) in (("cubic", Grid3D((8, 8, 8), (T(2π), T(2π), T(2π)))),
                          ("mixed", Grid3D((8, 6, 5), (T(2π), T(4π), T(6π))))),
        (lname, layout) in (("fold1", RealFourierLayout()), ("fold2", RealFourierLayout((2, 1, 3)))),
        threaded in (false, true)
      push!(cs, Config("$T/$gname/$lname/$(threaded ? "threaded" : "serial")", T, grid, layout, threaded))
    end
  end
  return cs
end

xshape(c::Config, R, cplx) =
  cplx ? GBGPeriodicFields.Fields.spectral_field_shape(c.grid, c.layout, Val(R)) :
         (c.grid.grid_size..., (R == 0 ? () : ntuple(_ -> 3, R))...)

wrap(c::Config, R, cplx, data) = cplx ?
  (R == 0 ? ScalarFieldSpectral(data, c.grid, c.layout) :
   R == 1 ? VectorFieldSpectral(data, c.grid, c.layout) : TensorFieldSpectral{2}(data, c.grid, c.layout)) :
  (R == 0 ? ScalarFieldPhysical(data, c.grid, c.layout) :
   R == 1 ? VectorFieldPhysical(data, c.grid, c.layout) : TensorFieldPhysical{2}(data, c.grid, c.layout))

# Since decision 59 a section owns its storage, so the only sharing left is being the SAME field. The
# aliasing axis is therefore three values and is enumerated completely rather than sampled.
const ASSIGNMENTS = ("distinct", "dest≡a", "dest≡b")


"""
    sweep_operation(config, orders, complexvalued, call, reference; tolerance)

Run one operation over every argument assignment and return the assignments whose result disagrees
with the reference.
"""
function sweep_operation(c::Config, orders, cplx, call, reference; tolerance = nothing)
  shapes = [xshape(c, R, cplx) for R in orders]
  T = cplx ? Complex{c.eltype} : c.eltype
  rtol = tolerance === nothing ? (c.eltype === Float32 ? 1.0f-3 : 1e-9) : tolerance
  failures = String[]
  for assignment in ASSIGNMENTS
    fields = [wrap(c, orders[i], cplx, rand(T, shapes[i]...)) for i in eachindex(orders)]
    # The destination may BE one of the sources — the only sharing a section now permits.
    assignment == "dest≡a" && length(fields) >= 2 && orders[1] == orders[2] && (fields[1] = fields[2])
    assignment == "dest≡b" && length(fields) >= 3 && orders[1] == orders[3] && (fields[1] = fields[3])
    snapshots = [Array(field_data(f)) for f in fields]
    expected = try
      reference(snapshots...)
    catch exception
      push!(failures, "$assignment  [reference threw $(nameof(typeof(exception)))]"); continue
    end
    try
      call(fields...)
    catch exception
      push!(failures, "$assignment  [$(nameof(typeof(exception)))]"); continue
    end
    isapprox(Array(field_data(fields[1])), expected; rtol = rtol) ||
      push!(failures, assignment)
  end
  return failures
end
