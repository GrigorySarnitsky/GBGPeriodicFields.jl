# Package-quality checks via Aqua.jl: method ambiguities, unbound type parameters,
# undefined exports, Project/compat consistency, stale dependencies, type piracy, and
# persistent tasks. (Ambiguities are also locked per-generic in method_parity.jl; here
# they are part of the broader Aqua sweep. Piracy passing confirms invariant 8 — the
# fiber types are StaticArrays aliases, so the package never extends Base/LinearAlgebra
# for them without a package-owned argument.)

using Test
using GBGPeriodicFields
using Aqua

@testset "Aqua quality assurance" begin
  Aqua.test_all(GBGPeriodicFields)
end
