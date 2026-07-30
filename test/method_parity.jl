# Method-parity baseline for FieldAlgebra (M2 + M3 — the full public surface).
#
# Locks the generated method set so a codegen change cannot silently add or drop
# methods. Counts are "methods FieldAlgebra defines for each generic"
# (m.module === FieldAlgebra), which filters out the hundreds of Base methods on
# the operators. 206 public methods total (the pre-refactor surface plus `tr`/`tr!`,
# the weighted combination `combine!`, and the determinant `det`/`det!`).

using Test
using GBGPeriodicFields
using Statistics
include("public_surface.jl")

const FA = GBGPeriodicFields.FieldAlgebra
const IP = GBGPeriodicFields.Points
pkg_method_count(f) = count(m -> m.module === FA, methods(f))
pointvalues_method_count(f) = count(m -> m.module === IP, methods(f))

@testset "method parity" begin

  @testset "M2 + M3 baseline (206 methods)" begin
    baseline = (("add!", add!, 14), ("subtract!", subtract!, 14), ("combine!", combine!, 2),
                ("multiply!", multiply!, 16), ("divide!", divide!, 6),
                ("+", +, 15), ("-", -, 15), ("*", *, 28), ("/", /, 5),
                ("dot", dot, 10), ("dot!", dot!, 10), ("cross", cross, 5), ("cross!", cross!, 5),
                ("mul!", mul!, 30), ("transpose", transpose, 2), ("transpose!", transpose!, 2),
                ("norm", norm, 3), ("norm!", norm!, 3),
                ("sym", sym, 3), ("sym!", sym!, 2), ("skew", skew, 3), ("skew!", skew!, 2),
                ("dev", dev, 3), ("dev!", dev!, 2),
                ("tr", tr, 2), ("tr!", tr!, 2), ("det", det, 1), ("det!", det!, 1))
    for (name, f, n) in baseline
      @test pkg_method_count(f) == n
    end
    @test sum(pkg_method_count(f) for (_, f, _) in baseline) == 206
  end

  # The PointValues algebra (Points module) mirrors the fields' *physical* surface, on
  # the same generics. It is counted separately (m.module === Points), so the field
  # baseline above stays locked while this locks the new surface. Representation-free ⇒ no
  # spectral variants, so the counts are smaller than the field ones.
  @testset "PointValues algebra baseline (122 methods)" begin
    baseline = (("add!", add!, 7), ("subtract!", subtract!, 7),
                ("multiply!", multiply!, 10), ("divide!", divide!, 5),
                ("+", +, 8), ("-", -, 8), ("*", *, 18), ("/", /, 5),
                ("dot", dot, 6), ("dot!", dot!, 6), ("cross", cross, 3), ("cross!", cross!, 3),
                ("mul!", mul!, 18), ("transpose", transpose, 1), ("transpose!", transpose!, 1),
                ("norm", norm, 3), ("norm!", norm!, 3),
                ("sym", sym, 1), ("sym!", sym!, 1), ("skew", skew, 1), ("skew!", skew!, 1),
                ("dev", dev, 1), ("dev!", dev!, 1),
                ("tr", tr, 1), ("tr!", tr!, 1), ("det", det, 1), ("det!", det!, 1))
    for (name, f, n) in baseline
      @test pointvalues_method_count(f) == n
    end
    @test sum(pointvalues_method_count(f) for (_, f, _) in baseline) == 122
  end

  @testset "no ambiguities" begin
    @test isempty(detect_ambiguities(GBGPeriodicFields; recursive = true))
  end

end


# ---------------------------------------------------------------------------------------------
# Derived module baselines (decision 53).
#
# The hand-written baseline above enumerates 28 generic NAMES filtered to two modules, so it is
# blind to everything else: decisions 48, 49 and 51 each added public surface — `map!`/`map` in
# FieldAlgebra, `cov` in Reductions, the kernel builders in Convolution — and neither the 206 nor
# the 122 moved. A baseline that cannot see a new generic does not enforce "the public method set
# is the spec"; it enforces it for the names someone remembered to list.
#
# This one is DERIVED rather than enumerated: for each module, every function that module owns,
# counted over the methods defined IN that module. Adding a method anywhere moves a number, and the
# number must then be refrozen deliberately — the pass-audit protocol, applied to the method table.
# Extension methods (the HDF5 weak dependency) live in their own module and are excluded by the
# `m.module === mod` filter, so loading HDF5 does not perturb the counts.
const MODULE_BASELINE = (
  FiberSections         = 109,
  Fields                = 105,
  FieldAlgebra          = 274,
  DifferentialOperators = 79,
  Convolution           = 78,   # +6: the StoredKernel role marker and its protocol methods
  Points                = 207,
  Interpolation         = 119,
  Reductions            = 111,
)

# The candidate set is the package's whole function surface, internals included, NOT `names(mod)`.
# A method defined under a QUALIFIED name — `Base.inv(kernel::SeparableKernel) = …` — creates no
# binding in the defining module, so a namespace scan cannot see it: adding `inv(::ScalarFieldSpectral)`
# to Convolution moved no number here, which is the same hole `public_surface.jl` closes for the
# ledgers. Ownership is the question, and `m.module === mod` is the only thing that answers it.
function module_method_count(mod::Module)
  total = 0
  for name in all_package_functions()
    f = _resolve_function(name)
    f === nothing && continue
    total += count(m -> m.module === mod, methods(f))
  end
  return total
end


# A name from the derived surface may live in a package module or in the external module whose generic
# the package extends, so look in both.
function _resolve_function(name::Symbol)
  # LinearAlgebra is not a test dependency, and does not need to be: the umbrella re-exports the
  # generics the package extends from it (`dot`, `cross`, `norm`, `mul!`, `transpose`).
  for mod in (GBGPeriodicFields, Base, Statistics,
              (getfield(GBGPeriodicFields, m) for m in
               (:FiberSections, :Fields, :FieldAlgebra, :DifferentialOperators,
                :Convolution, :Points, :Interpolation, :Reductions))...)
    isdefined(mod, name) || continue
    candidate = getfield(mod, name)
    candidate isa Function && return candidate
  end
  return nothing
end

@testset "derived module baselines (decision 53)" begin
  for (name, expected) in pairs(MODULE_BASELINE)
    mod = getfield(GBGPeriodicFields, name)
    measured = module_method_count(mod)
    # On a mismatch the message says what to do, because the fix is a judgement, not a repair:
    # confirm the new methods are intended and tested, then refreeze in the same commit.
    measured == expected ||
      @info "module method count moved — refreeze deliberately, with the reason" target = name expected measured
    @test measured == expected
  end
  # The two baselines count DIFFERENT denominators and must not be compared. The enumerated one above
  # is 206 methods over 28 named generics; this one is every method FieldAlgebra owns, extended `Base`
  # operators included, which is why it is larger. Comparing them would only re-freeze a coincidence.
  @test MODULE_BASELINE.FieldAlgebra > 206
end
