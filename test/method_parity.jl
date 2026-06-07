# Method-parity baseline for FieldAlgebra (M2 + M3 — the full public surface).
#
# Locks the generated method set so a codegen change cannot silently add or drop
# methods. Counts are "methods FieldAlgebra defines for each generic"
# (m.module === FieldAlgebra), which filters out the hundreds of Base methods on
# the operators. 198 public methods total, matching the pre-refactor original.

using Test
using GBGPeriodicFields

const FA = GBGPeriodicFields.FieldAlgebra
pkg_method_count(f) = count(m -> m.module === FA, methods(f))

@testset "method parity" begin

  @testset "M2 + M3 baseline (198 methods)" begin
    baseline = (("add!", add!, 14), ("subtract!", subtract!, 14),
                ("multiply!", multiply!, 16), ("divide!", divide!, 6),
                ("+", +, 15), ("-", -, 15), ("*", *, 28), ("/", /, 5),
                ("dot", dot, 10), ("dot!", dot!, 10), ("cross", cross, 5), ("cross!", cross!, 5),
                ("mul!", mul!, 30), ("transpose", transpose, 2), ("transpose!", transpose!, 2),
                ("norm", norm, 3), ("norm!", norm!, 3),
                ("sym", sym, 3), ("sym!", sym!, 2), ("skew", skew, 3), ("skew!", skew!, 2),
                ("dev", dev, 3), ("dev!", dev!, 2))
    for (name, f, n) in baseline
      @test pkg_method_count(f) == n
    end
    @test sum(pkg_method_count(f) for (_, f, _) in baseline) == 198
  end

  @testset "no ambiguities" begin
    @test isempty(detect_ambiguities(GBGPeriodicFields; recursive = true))
  end

end
