# Method-parity baselines — the public method set is the spec (invariant 1).
#
# Locks the method set so a codegen change cannot silently add or drop methods. The package DECLARES
# method parity to GBGCodingTools (RULE.TEST.METHOD_PARITY): the engine is the tool's
# `TestHarness.method_parity`, extracted from this file, and the frozen numbers live in
# `test/method_parity_baseline.toml`, each moved number refrozen there with its reason.
#
# Two baselines, counting DIFFERENT denominators:
#
# - The ENUMERATED one names 28 generics and counts the methods FieldAlgebra defines for each
#   (m.module === FieldAlgebra, which filters out the hundreds of Base methods on the operators): 206
#   public methods, the pre-refactor surface plus `tr`/`tr!`, the weighted combination `combine!` and
#   the determinant `det`/`det!`. The PointValues algebra (Points) mirrors the fields' *physical*
#   surface on the same generics and is counted separately, 122 methods; representation-free, so no
#   spectral variants.
# - The DERIVED one (decision 53) is blind to nothing: for each module, every function it owns over the
#   package's whole function surface, internals included, counted over the methods defined IN that
#   module. The enumerated list missed decisions 48, 49 and 51 entirely — `map!`/`map`, `cov` and the
#   kernel builders added surface and neither number moved. The candidate set is the whole surface,
#   NOT `names(mod)`: a method defined under a QUALIFIED name creates no binding in its module, so a
#   namespace scan cannot see it, and ownership (`m.module === mod`) is the only thing that answers it.
#   Extension methods (the HDF5 weak dependency) live in their own module and are not counted.
#
# The engine also asserts that `detect_ambiguities` over the package is empty — the explicit
# `multiply!` quartet exists precisely to resolve those.

using Test
using GBGPeriodicFields
using Statistics
using TOML
import GBGCodingTools
include("public_surface.jl")

const METHOD_BASELINE = TOML.parsefile(joinpath(@__DIR__, "method_parity_baseline.toml"))

# The external modules whose generics the package extends. LinearAlgebra is not a test dependency and
# need not be: the umbrella re-exports the generics the package extends from it (`dot`, `cross`,
# `norm`, `mul!`, `transpose`), so they resolve through the package.
GBGCodingTools.TestHarness.method_parity(GBGPeriodicFields,
    filter(m -> m !== GBGPeriodicFields, collect(PACKAGE_MODULES)), METHOD_BASELINE;
    externals = (Base, Statistics))

# The two baselines must not be compared: the derived FieldAlgebra count includes the extended `Base`
# operators and every internal, which is why it is larger than the enumerated 206. Comparing them
# would only re-freeze a coincidence; this asserts only that the relation holds.
@testset "the derived FieldAlgebra count exceeds the enumerated surface" begin
  @test METHOD_BASELINE["module"]["FieldAlgebra"] > 206
end
