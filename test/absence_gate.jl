# Invariant 1's deliberate absences, ENFORCED: every representation-asymmetric operation is called on
# its ABSENT side and must refuse.
#
# The public method set is the spec, and what is deliberately missing encodes representation validity
# — a nonlinear operation has no spectral method, a spectral multiplier has no physical one. An
# absence is only load-bearing if calling it actually FAILS; a fallback quietly accepted somewhere
# would rewrite the spec without a test noticing (the exhaustive survey caught `norm!` doing exactly
# that once: it "leaked the scalar-only absence … because it HAS a fallback"). The applicability
# ledger tracked this advisorily at 19/38; this file is the enforcement, in the allocation-audit
# shape: a DERIVED denominator, one absent-side invocation per member, completeness in both
# directions. There are no exemptions, because every asymmetric operation's absent side is callable —
# an absence that cannot even be spelled needs no gate.
#
# THE DENOMINATOR IS DERIVED, mirroring the exhaustive ledger: an operation is in scope iff its
# package-owned method signatures intersect AbstractFieldPhysical or AbstractFieldSpectral but not
# both (`typeintersect`, not subtyping — the generated surface is spelled on parameterized concrete
# types, and the subtype test read `det!` as accepting neither).
#
# Both a MethodError (no method exists) and a refusing fallback (a method that exists to throw a
# better error) count as enforcement: the gate's question is whether the absent call FAILS, and which
# way it fails is the package's choice per site.

using Test
using GBGPeriodicFields
using Statistics
include("public_surface.jl")

const AG = GBGPeriodicFields
const AG_MODULES = (AG.FiberSections, AG.Fields, AG.FieldAlgebra, AG.DifferentialOperators,
                    AG.Convolution, AG.Points, AG.Interpolation, AG.Reductions)


function _ag_lookup(name::Symbol)
  for mod in (AG, Base, Statistics, AG_MODULES...)
    isdefined(mod, name) || continue
    object = getfield(mod, name)
    object isa Function && return object
  end
  return nothing
end


function asymmetric_operations()
  found = Symbol[]
  for op in sort(collect(package_operations()); by = String)
    f = _ag_lookup(op)
    f === nothing && continue
    signatures = [m.sig for m in methods(f) if m.module in AG_MODULES]
    isempty(signatures) && continue
    accepts(T) = any(sig -> any(p -> p isa Type && p !== Any && typeintersect(T, p) !== Union{},
                                Base.unwrap_unionall(sig).parameters[2:end]), signatures)
    accepts(AG.Fields.AbstractFieldPhysical) != accepts(AG.Fields.AbstractFieldSpectral) &&
      Base.push!(found, op)
  end
  return found
end


# ── Fixtures on one context ──────────────────────────────────────────────────────────────────────
const AGRID = Grid3D((8, 6, 4), (2π, 2π, 2π))
const ALAYOUT = RealFourierLayout()
agsphys() = ScalarFieldPhysical(rand(8, 6, 4), AGRID, ALAYOUT)
agvphys() = VectorFieldPhysical(rand(8, 6, 4, 3), AGRID, ALAYOUT)
agtphys() = TensorFieldPhysical{2}(rand(8, 6, 4, 3, 3), AGRID, ALAYOUT)
agsspec() = ScalarFieldSpectral(randn(ComplexF64, AG.Fields.field_spectral_shape(AGRID, ALAYOUT, Val(0))), AGRID, ALAYOUT)
agvspec() = VectorFieldSpectral(randn(ComplexF64, AG.Fields.field_spectral_shape(AGRID, ALAYOUT, Val(1))), AGRID, ALAYOUT)
agmult() = FieldSpectralMultipliers(agsspec())
agkernel() = spectral_band(agmult(), 1, 3)
agplans() = FieldTransformPlans(agsphys(), agsspec())
agpoints() = PointSet(rand(9, 3) .* 2π)


# ── The registry: each operation called on the side invariant 1 leaves ABSENT ────────────────────
const ABSENT_CALLS = Dict{Symbol, Function}(
  # Nonlinear-in-the-field, so physical-only — the spectral spelling must refuse.
  :det      => () -> det(TensorFieldSpectral{2}(randn(ComplexF64, AG.Fields.field_spectral_shape(AGRID, ALAYOUT, Val(2))), AGRID, ALAYOUT)),
  :det!     => () -> det!(agsspec(), TensorFieldSpectral{2}(randn(ComplexF64, AG.Fields.field_spectral_shape(AGRID, ALAYOUT, Val(2))), AGRID, ALAYOUT)),
  :norm     => () -> AG.norm(agvspec()),
  :norm!    => () -> norm!(agsspec(), agvspec()),
  :lpnorm   => () -> lpnorm(agsspec(), 3),
  :maximum  => () -> maximum(agsspec()),
  :minimum  => () -> minimum(agsspec()),
  :map      => () -> map(x -> 2x, agsspec()),
  :map!     => () -> map!(x -> 2x, agsspec(), agsspec()),
  :cov      => () -> cov(agvspec()),
  # The differential operators are applied as spectral multipliers — a physical field must refuse.
  :gradient             => () -> gradient(agsphys(), agmult()),
  :gradient!            => () -> gradient!(agvphys(), agsphys(), agmult()),
  :divergence           => () -> divergence(agvphys(), agmult()),
  :divergence!          => () -> divergence!(agsphys(), agvphys(), agmult()),
  :curl                 => () -> curl(agvphys(), agmult()),
  :curl!                => () -> curl!(agvphys(), agvphys(), agmult()),
  :inverse_curl         => () -> inverse_curl(agvphys(), agmult()),
  :inverse_curl!        => () -> inverse_curl!(agvphys(), agvphys(), agmult()),
  :laplacian            => () -> laplacian(agsphys(), agmult()),
  :laplacian!           => () -> laplacian!(agsphys(), agsphys(), agmult()),
  :inverse_laplacian    => () -> inverse_laplacian(agsphys(), agmult()),
  :inverse_laplacian!   => () -> inverse_laplacian!(agsphys(), agsphys(), agmult()),
  :helmholtz_projection => () -> helmholtz_projection(agvphys(), agmult()),
  :helmholtz_projection! => () -> helmholtz_projection!(agvphys(), agvphys(), agmult()),
  :symmetric_gradient   => () -> symmetric_gradient(agvphys(), agmult()),
  :symmetric_gradient!  => () -> symmetric_gradient!(agtphys(), agvphys(), agmult()),
  # Convolution and its kin are coefficientwise, spectral-only.
  :convolve             => () -> convolve(agsphys(), agkernel()),
  :convolve!            => () -> convolve!(agsphys(), agsphys(), agkernel()),
  :⋆                    => () -> agsphys() ⋆ agkernel(),
  :exponential_convolve => () -> exponential_convolve(agsphys(), agmult(), -0.1),
  :exponential_convolve! => () -> exponential_convolve!(agsphys(), agsphys(), agmult(), -0.1),
  :weighted_inner       => () -> weighted_inner(agsphys(), agkernel()),
  :radial_spectrum      => () -> radial_spectrum(agsphys(), agmult()),
  :radial_correlation   => () -> radial_correlation(agsphys(), agplans()),
  :reality_residual     => () -> reality_residual(agsphys()),
  :reality_projection!  => () -> reality_projection!(agsphys()),        # decision 83: physical is the identity, so no method
  # Definitional asymmetries: each transform names its input representation.
  :to_physical          => () -> to_physical(agsphys(), agplans()),
  :to_spectral          => () -> to_spectral(agsspec(), agplans()),
  # The spectral transfer's scatter takes the deposit target in spectral representation.
  :anterpolate          => () -> anterpolate(agsphys(), agpoints(), ScalarPointValues(rand(9)), DirectDFT()),
)


@testset "invariant 1: every representation-asymmetric operation refuses its absent side" begin
  denominator = asymmetric_operations()
  covered = Set(keys(ABSENT_CALLS))

  uncovered = setdiff(Set(denominator), covered)
  isempty(uncovered) ||
    @error "an asymmetric operation has no absent-side call here — write one" sort(collect(uncovered); by = String)
  @test isempty(uncovered)
  stale = setdiff(covered, Set(denominator))
  isempty(stale) ||
    @error "entries for operations that are no longer asymmetric — the absence they assert is gone" sort(collect(stale); by = String)
  @test isempty(stale)

  for (operation, call) in sort(collect(ABSENT_CALLS); by = first)
    @test_throws Exception call()
  end
end
