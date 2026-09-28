# Tier 2 of the context-mismatch matrix: the ENTRY-POINT product (audit TEST-09).
#
# Tier 1 (`context_matrix.jl`) proves the predicate rejects every mismatched participant pair. That is
# necessary and not sufficient: an operation only benefits if it CALLS the predicate. This file checks
# that, over a denominator derived from the method table rather than remembered.
#
# THE DENOMINATOR. Every method the package owns is scanned for a parameter that carries a context — a
# multiplier set, a kernel, a NUFFT plan, a transfer scheme, a transform plan set — giving a set of
# (operation, carrier-kind) pairs. That pair is the right unit: `divergence!` has α/β variants, but they
# reach the same context check, so the pair is what needs one entry rather than each method.
#
# THE ANTI-MISS MECHANISM. Every derived pair must appear below as an INVOCATION or as an EXEMPTION
# with a reason. A new operation taking a kernel, or a new carrier kind, fails this file until someone
# decides which it is. That is the point: the failure mode being guarded against is not a wrong test,
# it is a combination nobody enumerated.

using Test
using GBGPeriodicFields
using Statistics
include("public_surface.jl")

const EF = GBGPeriodicFields.Fields
const EI = GBGPeriodicFields.Interpolation
const ELAYOUT = RealFourierLayout()

# The same axes as Tier 1: `domain` differs from base with an IDENTICAL grid shape, so nothing
# structural distinguishes the two and only a context check can.
const ECONTEXTS = (
  base   = (grid = Grid3D((8, 6, 4), (2π, 2π, 2π)),  layout = ELAYOUT),
  domain = (grid = Grid3D((8, 6, 4), (4π, 4π, 4π)),  layout = ELAYOUT),
  shape  = (grid = Grid3D((10, 6, 4), (2π, 2π, 2π)), layout = ELAYOUT),
  layout = (grid = Grid3D((8, 6, 4), (2π, 2π, 2π)),  layout = RealFourierLayout((2, 1, 3))),
)

sspec(c) = ScalarFieldSpectral(zeros(ComplexF64, EF.field_spectral_shape(c.grid, c.layout, Val(0))), c.grid, c.layout)
vspec(c) = VectorFieldSpectral(randn(ComplexF64, EF.field_spectral_shape(c.grid, c.layout, Val(1))), c.grid, c.layout)
tspec(c) = TensorFieldSpectral{2}(randn(ComplexF64, EF.field_spectral_shape(c.grid, c.layout, Val(2))), c.grid, c.layout)
sphys(c) = ScalarFieldPhysical(rand(c.grid.grid_size...), c.grid, c.layout)
vphys(c) = VectorFieldPhysical(rand(c.grid.grid_size..., 3), c.grid, c.layout)
epoints(c) = PointSet(rand(12, 3) .* 2π)
evalues() = ScalarPointValues(zeros(12))

# One carrier of each kind, built on a given context.
carrier_of(::Val{:multipliers}, c) = FieldSpectralMultipliers(sspec(c))
carrier_of(::Val{:kernel}, c) = spectral_band(carrier_of(Val(:multipliers), c), 1, 3)
carrier_of(::Val{:nufft}, c) = NUFFT(sspec(c))
carrier_of(::Val{:plans}, c) = FieldTransformPlans(sphys(c), sspec(c))

# Each entry calls the operation with its operands on `c` and the carrier supplied, so the sweep can
# hand it a matching or a foreign carrier and demand the corresponding outcome.
const INVOCATIONS = Dict{Tuple{Symbol, Symbol}, Function}(
  # --- spectral operators and builders against a multiplier set ---
  (:gradient, :multipliers)             => (c, k) -> gradient(sspec(c), k),
  (:gradient!, :multipliers)            => (c, k) -> gradient!(vspec(c), sspec(c), k),
  (:divergence, :multipliers)           => (c, k) -> divergence(vspec(c), k),
  (:divergence!, :multipliers)          => (c, k) -> divergence!(sspec(c), vspec(c), k),
  (:curl, :multipliers)                 => (c, k) -> curl(vspec(c), k),
  (:curl!, :multipliers)                => (c, k) -> curl!(vspec(c), vspec(c), k),
  (:inverse_curl, :multipliers)         => (c, k) -> inverse_curl(vspec(c), k),
  (:inverse_curl!, :multipliers)        => (c, k) -> inverse_curl!(vspec(c), vspec(c), k),
  (:laplacian, :multipliers)            => (c, k) -> laplacian(sspec(c), k),
  (:laplacian!, :multipliers)           => (c, k) -> laplacian!(sspec(c), sspec(c), k),
  (:inverse_laplacian, :multipliers)    => (c, k) -> inverse_laplacian(sspec(c), k),
  (:inverse_laplacian!, :multipliers)   => (c, k) -> inverse_laplacian!(sspec(c), sspec(c), k),
  (:symmetric_gradient, :multipliers)   => (c, k) -> symmetric_gradient(vspec(c), k),
  (:symmetric_gradient!, :multipliers)  => (c, k) -> symmetric_gradient!(tspec(c), vspec(c), k),
  (:helmholtz_projection, :multipliers) => (c, k) -> helmholtz_projection(vspec(c), k),
  (:helmholtz_projection!, :multipliers)=> (c, k) -> helmholtz_projection!(vspec(c), vspec(c), k),
  (:exponential_convolve, :multipliers) => (c, k) -> exponential_convolve(sspec(c), k, -0.1),
  (:exponential_convolve!, :multipliers)=> (c, k) -> exponential_convolve!(sspec(c), sspec(c), k, -0.1),
  (:radial_spectrum, :multipliers)      => (c, k) -> radial_spectrum(sspec(c), k),
  (:translation_kernel!, :multipliers)  => (c, k) -> translation_kernel!(
      translation_kernel(carrier_of(Val(:multipliers), c), (0.1, 0.2, 0.3)), k, (0.2, 0.3, 0.4)),

  # --- operations taking a kernel ---
  (:convolve, :kernel)                  => (c, k) -> convolve(vspec(c), k),
  (:⋆, :kernel)                         => (c, k) -> vspec(c) ⋆ k,
  (:divergence, :kernel)                => (c, k) -> divergence(vspec(c), carrier_of(Val(:multipliers), c), k),
  (:helmholtz_projection, :kernel)      => (c, k) -> helmholtz_projection(vspec(c), carrier_of(Val(:multipliers), c), k),
  (:convolve!, :kernel)                 => (c, k) -> convolve!(vspec(c), vspec(c), k),
  (:divergence!, :kernel)               => (c, k) -> divergence!(sspec(c), vspec(c), carrier_of(Val(:multipliers), c), k),
  (:helmholtz_projection!, :kernel)     => (c, k) -> helmholtz_projection!(vspec(c), vspec(c), carrier_of(Val(:multipliers), c), k),
  (:combine!, :kernel)                  => (c, k) -> combine!(vspec(c), 0.3, vspec(c), 0.7, vspec(c), k),
  (:weighted_inner, :kernel)            => (c, k) -> weighted_inner(vspec(c), k),
  (:materialize_kernel!, :kernel)       => (c, k) -> materialize_kernel!(StoredKernel(sspec(c)), k),

  # --- transform plans ---
  (:to_physical, :plans)                => (c, k) -> to_physical(sspec(c), k),
  (:to_physical!, :plans)               => (c, k) -> to_physical!(sphys(c), sspec(c), k),
  (:to_spectral, :plans)                => (c, k) -> to_spectral(sphys(c), k),
  (:to_spectral!, :plans)               => (c, k) -> to_spectral!(sspec(c), sphys(c), k),
  (:radial_correlation, :plans)         => (c, k) -> radial_correlation(sspec(c), k),

  # --- the NUFFT plan ---
  (:interpolate, :nufft)                => (c, k) -> interpolate(sspec(c), epoints(c), k),
  (:interpolate!, :nufft)               => (c, k) -> interpolate!(evalues(), sspec(c), epoints(c), k),
  (:anterpolate, :nufft)                => (c, k) -> anterpolate(sspec(c), epoints(c), evalues(), k),
  (:anterpolate!, :nufft)               => (c, k) -> anterpolate!(sspec(c), epoints(c), evalues(), k),
)

# A pair is exempt only when there is genuinely no second context for the carrier to disagree with, or
# when the carrier holds no context at all. Both are properties of the operation, not of this file.
const EXEMPT = Dict{Tuple{Symbol, Symbol}, String}(
  (:inv, :kernel)                => "single-carrier operation: a kernel is inverted alone, with nothing to mismatch against",
  (:materialize_kernel, :kernel) => "single-carrier operation: a kernel is expanded alone, with nothing to mismatch against",
  (:translation_kernel!, :kernel)=> "swept under its :multipliers pair, which is the argument carrying the foreign context",
  # Decision 66 dropped the vestigial `reference` field from the five kernel builders, so each now takes
  # exactly one context-carrying argument and the kernel simply adopts its context. There is no longer a
  # second context for it to disagree with at BUILD time. Nothing is lost: a kernel carrying a foreign
  # context is caught where it meets a field, which the nine (operation, :kernel) rows above cover.
  (:spectral_cutoff, :multipliers)    => "single-carrier operation since decision 66: the kernel adopts the multipliers' context",
  (:spectral_band, :multipliers)      => "single-carrier operation since decision 66: the kernel adopts the multipliers' context",
  (:radial_kernel, :multipliers)      => "single-carrier operation since decision 66: the kernel adopts the multipliers' context",
  (:assignment_window, :multipliers)  => "single-carrier operation since decision 66: the kernel adopts the multipliers' context",
  (:tophat_window, :multipliers)      => "single-carrier operation: the kernel adopts the multipliers' context, like assignment_window",
  (:translation_kernel, :multipliers) => "single-carrier operation since decision 66: the kernel adopts the multipliers' context",
  (:interpolate, :scheme)        => "the spline schemes carry no context — a LalescuSpline is weights only, valid on any grid",
  (:interpolate!, :scheme)       => "same: a spline scheme has no grid or layout to disagree with",
  (:anterpolate, :scheme)        => "same: a spline scheme has no grid or layout to disagree with",
  (:anterpolate!, :scheme)       => "same: a spline scheme has no grid or layout to disagree with",
  # Display takes an `IO` and ONE object. There is no second context in the signature, so there is
  # nothing for the carrier's to disagree with — the same shape as `inv` and `materialize_kernel`
  # above. It is exempted rather than filtered because `show` really is a public operation reachable
  # by a user, and a denominator that quietly drops a class is what this file exists to prevent.
  (:show, :plans)       => "single-carrier operation: a display takes one object and an `IO`",
  (:show, :scheme)      => "single-carrier operation: a display takes one object and an `IO`",
  (:show, :nufft)       => "single-carrier operation: a display takes one object and an `IO`",
  (:show, :kernel)      => "single-carrier operation: a display takes one object and an `IO`",
  (:show, :multipliers) => "single-carrier operation: a display takes one object and an `IO`",
)


function derived_pairs()
  # A slot may be declared as a UNION — `divergence`'s kernel argument is
  # `SpectralKernel`, the abstract supertype of every kernel class — a field in spectral representation
  # is not one, so
  # a plain `<:` test walks straight past it. Recursing into the union is what makes the denominator
  # honest; without it two kernel-taking operations were missing from the derived set entirely.
  function kind(T)
    # Unwrap first: `SpectralKernel{T}` is a UnionAll WRAPPING a Union, so neither `isa Union` nor `<:`
    # sees through it, and the allocating kernel arities went missing from the denominator because of
    # exactly that. Unwrap, then recurse into the union, then test.
    T isa UnionAll && return kind(Base.unwrap_unionall(T))
    T isa Union && return something(kind(T.a), kind(T.b), Some(nothing))
    T isa Type || return nothing
    T <: EF.FieldSpectralMultipliers && return :multipliers
    T <: EF.SpectralKernel && return :kernel
    T <: EI.NUFFT && return :nufft
    T <: EI.AbstractTransferScheme && return :scheme
    T <: EF.FieldTransformPlans && return :plans
    return nothing
  end
  resolve(n) = begin
    for mod in (GBGPeriodicFields, Base, Statistics)
      isdefined(mod, n) || continue
      candidate = getfield(mod, n)
      candidate isa Function && return candidate
    end
    nothing
  end
  found = Set{Tuple{Symbol, Symbol}}()
  for name in package_operations()
    f = resolve(name)
    f === nothing && continue
    for m in methods(f)
      m.module in PACKAGE_MODULES || continue
      for p in Base.unwrap_unionall(m.sig).parameters[2:end]
        k = kind(p)
        k === nothing || push!(found, (name, k))
      end
    end
  end
  return found
end


@testset "context entry points: every (operation, carrier) pair rejects a foreign context" begin
  pairs_required = derived_pairs()
  covered = union(Set(keys(INVOCATIONS)), Set(keys(EXEMPT)))

  # Completeness, both directions: nothing derived may be unaccounted for, and nothing accounted for
  # may have gone stale.
  uncovered = setdiff(pairs_required, covered)
  isempty(uncovered) ||
    @error "an (operation, carrier) pair is neither invoked nor exempted — decide which" uncovered
  @test isempty(uncovered)
  @test isempty(setdiff(covered, pairs_required))

  base = ECONTEXTS.base
  for ((operation, kind), invoke) in sort(collect(INVOCATIONS); by = first)
    matching = carrier_of(Val(kind), base)
    # The legal call must work, or the rejection below proves nothing.
    @test invoke(base, matching) !== nothing

    for axis in (:domain, :shape, :layout)
      foreign = carrier_of(Val(kind), getfield(ECONTEXTS, axis))
      @test_throws Exception invoke(base, foreign)
    end
  end
end
