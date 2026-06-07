# Method-parity baseline for FieldAlgebra (M2 scope).
#
# Locks the generated method set so a codegen change cannot silently add or drop
# methods. Counts are "methods FieldAlgebra defines for each generic"
# (m.module === FieldAlgebra), which filters out the hundreds of Base methods on
# the operators. See CLAUDE.md "Verification workflow" for the baseline source.
#
# These numbers are the M2 snapshot. When M3/M4 land (dot, cross, mul!,
# transpose, norm, sym/skew/dev, public wrappers), update the baselines here and
# replace the "M3 pending" tripwire with the new per-generic counts.

using Test
using GBGPeriodicFields

const FA = GBGPeriodicFields.FieldAlgebra
pkg_method_count(f) = count(m -> m.module === FA, methods(f))

@testset "method parity" begin

  @testset "M2 baseline (98 methods)" begin
    baseline = (("add!", add!, 14), ("subtract!", subtract!, 14),
                ("multiply!", multiply!, 16), ("divide!", divide!, 6),
                ("+", +, 15), ("-", -, 15), ("*", *, 13), ("/", /, 5))
    for (name, f, n) in baseline
      @test pkg_method_count(f) == n
    end
    @test sum(pkg_method_count(f) for (_, f, _) in baseline) == 98
  end

  # Tripwire: M3 generics are bare bindings (exports resolvable, no methods yet).
  # When M3 is implemented, replace this with real per-generic baselines.
  @testset "M3 pending (no methods yet)" begin
    for f in (dot!, cross!, norm!, sym!, sym, skew!, skew, dev!, dev,
              dot, cross, mul!, transpose!, transpose, norm)
      @test pkg_method_count(f) == 0
    end
  end

  @testset "no ambiguities" begin
    @test isempty(detect_ambiguities(GBGPeriodicFields; recursive = true))
  end

end
