# The exhaustive suite — the full Cartesian product, run occasionally rather than on every change.
#
#   julia --project=. test/exhaustive/runtests.jl
#
# It is NOT part of `Pkg.test()`, for the same reason the GPU suite and the benchmarks are not: the
# default suite is a gate that must stay fast, and this is a survey that must stay complete. The
# default suite runs ~6 minutes; this one has no such budget and should not be given one.
#
# HOW TO READ IT. This is a REPORT, not a gate that has been silenced. It runs blind to what the
# package has decided, and prints everything that does not work. Where a failure corresponds to a
# recorded decision or a documented contract, the citation is printed BESIDE it — as an explanation of
# a known gap, never as a reason to call it green. A failure with no citation is a new finding.
#
# Its purpose is to be the place where combinations are enumerated rather than chosen, so that a defect
# is found by the product rather than by someone remembering to look.

using GBGPeriodicFields
using Statistics

include("aliasing.jl")

# Citations, applied to output only. Nothing here suppresses, filters or greens a failure: a cited
# entry is still reported as not working. The citation answers "is this known?", not "is this fine?".
const CITATIONS = Dict{Symbol, String}(
  :cross!                => "ARCHITECTURE decision 56 — fused passes read element n and write element n",
  :sym!                  => "ARCHITECTURE decision 56 — same",
  :skew!                 => "ARCHITECTURE decision 56 — same",
  :dev!                  => "ARCHITECTURE decision 56 — same",
  :transpose!            => "ARCHITECTURE decision 56 — same",
  :map!                  => "ARCHITECTURE decision 56 — same",
  :curl!                 => "ARCHITECTURE decision 56 — decision-38 kernel pair, same structure",
  :helmholtz_projection! => "ARCHITECTURE decision 56 — decision-38 kernel pair, same structure",
  :convolve!             => "ARCHITECTURE decision 56 — compressed-kernel pass, same structure",
  :mul!                  => "BY CONTRACT — mul! follows the LinearAlgebra convention that the " *
                            "destination must not alias an input (invariant 9); failing here is the " *
                            "contract being kept, not broken",
)

const PHYSICAL = false
const SPECTRAL = true

multipliers() = FieldSpectralMultipliers(
  ScalarFieldSpectral(zeros(ComplexF64, xshape(0, SPECTRAL)), XGRID, XLAYOUT))
const XM = multipliers()
const XV_PHYS = VectorFieldPhysical(rand(XN, XN, XN, 3), XGRID)
const XA_PHYS = TensorFieldPhysical{2}(rand(XN, XN, XN, 3, 3), XGRID)
const XKERNEL = translation_kernel(
  ScalarFieldSpectral(zeros(ComplexF64, xshape(0, SPECTRAL)), XGRID, XLAYOUT), XM, (0.1, 0.2, 0.3))

# (name, slot tensor orders, representation, call). The slot orders drive the pool, so a slot of a
# different order draws from a different parent — which is why an order-CHANGING operation cannot be
# given an offset-overlapping pair here, and is reported as such rather than as clean.
const OPERATIONS = [
  (:add!,                  [1, 1, 1], PHYSICAL, (d, a, b) -> add!(d, a, b)),
  (:subtract!,             [1, 1, 1], PHYSICAL, (d, a, b) -> subtract!(d, a, b)),
  (:combine!,              [1, 1, 1], PHYSICAL, (d, a, b) -> combine!(d, 0.3, a, 0.7, b)),
  (:multiply!,             [1, 1],    PHYSICAL, (d, a) -> multiply!(d, a, 2.0)),
  (:divide!,               [1, 1],    PHYSICAL, (d, a) -> divide!(d, a, 2.0)),
  (:cross!,                [1, 1],    PHYSICAL, (d, a) -> cross!(d, a, XV_PHYS)),
  (:dot!,                  [0, 1],    PHYSICAL, (d, a) -> dot!(d, a, XV_PHYS)),
  (:mul!,                  [1, 1],    PHYSICAL, (d, a) -> mul!(d, XA_PHYS, a)),
  (:sym!,                  [2, 2],    PHYSICAL, (d, a) -> sym!(d, a)),
  (:skew!,                 [2, 2],    PHYSICAL, (d, a) -> skew!(d, a)),
  (:dev!,                  [2, 2],    PHYSICAL, (d, a) -> dev!(d, a)),
  (:transpose!,            [2, 2],    PHYSICAL, (d, a) -> transpose!(d, a)),
  (:tr!,                   [0, 2],    PHYSICAL, (d, a) -> tr!(d, a)),
  (:det!,                  [0, 2],    PHYSICAL, (d, a) -> det!(d, a)),
  (:norm!,                 [0, 1],    PHYSICAL, (d, a) -> norm!(d, a)),
  (:map!,                  [1, 1],    PHYSICAL, (d, a) -> map!(x -> 2x, d, a)),
  (:laplacian!,            [0, 0],    SPECTRAL, (d, a) -> laplacian!(d, a, XM)),
  (:inverse_laplacian!,    [0, 0],    SPECTRAL, (d, a) -> inverse_laplacian!(d, a, XM)),
  (:gradient!,             [1, 0],    SPECTRAL, (d, a) -> gradient!(d, a, XM)),
  (:divergence!,           [0, 1],    SPECTRAL, (d, a) -> divergence!(d, a, XM)),
  (:curl!,                 [1, 1],    SPECTRAL, (d, a) -> curl!(d, a, XM)),
  (:symmetric_gradient!,   [2, 1],    SPECTRAL, (d, a) -> symmetric_gradient!(d, a, XM)),
  (:helmholtz_projection!, [1, 1],    SPECTRAL, (d, a) -> helmholtz_projection!(d, a, XM)),
  (:convolve!,             [1, 1],    SPECTRAL, (d, a) -> convolve!(d, a, XKERNEL)),
  (:exponential_convolve!, [0, 0],    SPECTRAL, (d, a) -> exponential_convolve!(d, a, XM, -0.1)),
]


function run_aliasing_lane()
  println("═"^100)
  println("LANE: storage aliasing — every in-place operation × every way its arguments can share storage")
  println("═"^100)
  broken = 0
  unexplained = String[]
  order_changing = String[]
  for (name, orders, representation, call) in OPERATIONS
    failures = aliasing_failures(orders, representation, call)
    if isempty(failures)
      # An order-CHANGING operation draws its slots from different parents, so this lane cannot build
      # an offset-overlapping pair for it. Say so rather than reporting a clean bill it did not earn.
      length(unique(orders)) > 1 && push!(order_changing, string(name))
      continue
    end
    broken += 1
    citation = get(CITATIONS, name, nothing)
    println("\n  ", name, "  — ", length(failures), " of 5^", length(orders), " assignments disagree")
    for f in failures
      println("      ", f)
    end
    if citation === nothing
      println("      NO CITATION — this is a new finding")
      push!(unexplained, string(name))
    else
      println("      cited: ", citation)
    end
  end

  println("\n", "─"^100)
  println("SUMMARY  ", broken, " of ", length(OPERATIONS), " operations have assignments that change the answer")
  isempty(unexplained) || println("         ", length(unexplained), " UNEXPLAINED: ", join(unexplained, ", "))
  isempty(order_changing) ||
    println("         NOT REACHED for ", length(order_changing), " order-changing operations (",
            join(order_changing, ", "), ") — their slots have different tensor orders, so this lane\n",
            "         cannot construct an offset-overlapping pair for them. Untested, not proven safe.")
  return broken, length(unexplained)
end

broken, unexplained = run_aliasing_lane()
println()
exit(unexplained > 0 ? 2 : (broken > 0 ? 1 : 0))
