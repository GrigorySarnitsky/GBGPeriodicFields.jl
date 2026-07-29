# Method-parity baseline for FieldAlgebra (M2 + M3 — the full public surface).
#
# Locks the generated method set so a codegen change cannot silently add or drop
# methods. Counts are "methods FieldAlgebra defines for each generic"
# (m.module === FieldAlgebra), which filters out the hundreds of Base methods on
# the operators. 206 public methods total (the pre-refactor surface plus `tr`/`tr!`,
# the weighted combination `combine!`, and the determinant `det`/`det!`).

using Test
using GBGPeriodicFields

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
  FiberSections         = 108,   # +1: section_tensor_order, the type-level order accessor
  Fields                = 92,   # +2 _storage_family/_same_backend (CODE-06); +3 the context protocol
  FieldAlgebra          = 206,
  DifferentialOperators = 79,
  Convolution           = 55,   # +2: materialize_kernel for ProductKernel and ScalarFieldSpectral (audit CODE-11)
  Points                = 61,
  Interpolation         = 115,
  Reductions            = 88,   # +4: _same_base_kind (3 methods) + _check_contractible (audit CODE-01)
)

function module_method_count(mod::Module)
  total = 0
  for name in names(mod; all = true)
    isdefined(mod, name) || continue
    f = getfield(mod, name)
    f isa Function || continue
    total += count(m -> m.module === mod, methods(f))
  end
  return total
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
  # The hand-written FieldAlgebra total must agree with the derived one, or one of them is stale.
  @test MODULE_BASELINE.FieldAlgebra == 206
end
