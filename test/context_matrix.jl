# The context-mismatch matrix (external audit TEST-09 / its recommended support-matrix denominator).
#
# WHY A MATRIX RATHER THAN CASES. The suite already held ~94 negative assertions before this file, so
# the gap was never "no negative tests". It was that every one of them was written by hand, which makes
# the negative surface complete only until someone adds an argument slot — and the audit's source
# findings were almost entirely SEMANTIC mismatches (a multiplier set for another domain, a plan for
# another grid) that are structurally indistinguishable from valid input and therefore fail silently
# rather than announcing themselves.
#
# So the denominator is DERIVED, twice over:
#
#   Tier 1 (this file, below) — the protocol product. Every participant in the context protocol is
#   read from `methods(_context_grid)`, and every ORDERED PAIR of participants is checked against every
#   mismatch axis. A new participant type adds a row and a column on its own; a participant with no
#   builder fails the completeness assertion rather than being skipped.
#
#   Tier 2 (context_entrypoints.jl) — the entry-point product, over the (method, slot) pairs derived
#   from the method table.
#
# The axes are the ways two contexts can differ while both remaining well-formed. `domain` is the one
# that matters most and the one a hand-written test is least likely to include: the grids have the SAME
# SHAPE, so every array involved has identical size and nothing structural distinguishes them.

using Test
using GBGPeriodicFields

const CM = GBGPeriodicFields.Fields
const DEFAULT_LAYOUT = RealFourierLayout()

# The mismatch axes. Each names a context that differs from `base` in exactly one respect.
const CONTEXTS = (
  base   = (grid = Grid3D((8, 6, 4), (2π, 2π, 2π)),  layout = DEFAULT_LAYOUT),
  domain = (grid = Grid3D((8, 6, 4), (4π, 4π, 4π)),  layout = DEFAULT_LAYOUT),   # SAME SHAPE
  shape  = (grid = Grid3D((10, 6, 4), (2π, 2π, 2π)), layout = DEFAULT_LAYOUT),
  layout = (grid = Grid3D((8, 6, 4), (2π, 2π, 2π)),  layout = RealFourierLayout((2, 1, 3))),
)

scalar_on(ctx) = ScalarFieldSpectral(
  zeros(ComplexF64, CM.field_spectral_shape(ctx.grid, ctx.layout, Val(0))), ctx.grid, ctx.layout)

# One builder per participant type. Keyed by the type the protocol dispatches on, so the completeness
# assertion below can compare this table against the protocol's own method list.
function participant_builders()
  field(ctx)       = scalar_on(ctx)
  multipliers(ctx) = FieldSpectralMultipliers(scalar_on(ctx))
  radial(ctx)      = spectral_band(multipliers(ctx), 1, 3)
  separable(ctx)   = translation_kernel(multipliers(ctx),
                                        ntuple(d -> 0.5 * ctx.grid.grid_spacing[d], 3))
  return Dict{Any, Function}(
    CM.AbstractFieldSpectral   => field,
    FieldSpectralMultipliers   => multipliers,
    RadialKernel               => radial,
    SeparableKernel            => separable,
    StoredKernel               => ctx -> materialize_kernel(radial(ctx)),   # already the stored class
    ProductKernel              => ctx -> convolve(radial(ctx), separable(ctx)),
    NUFFT                      => ctx -> NUFFT(field(ctx)),
  )
end


@testset "context protocol: every participant PAIR, every mismatch axis" begin
  builders = participant_builders()

  # Completeness first: the participant set is whatever answers the protocol, so a type that gains a
  # `_context_grid` method without gaining a builder here fails rather than quietly sitting out.
  declared = Any[]
  for m in methods(CM._context_grid)
    slot = m.sig.parameters[2]
    # The field method is written on a Union of the two representations; name the spectral half, which
    # is the one every spectral operation takes.
    slot = slot === Union{CM.AbstractFieldPhysical, CM.AbstractFieldSpectral} ? CM.AbstractFieldSpectral : slot
    push!(declared, slot)
  end
  missing_builders = setdiff(Set(declared), Set(keys(builders)))
  isempty(missing_builders) ||
    @error "a context-protocol participant has no builder in this matrix" missing_builders
  @test isempty(missing_builders)
  @test isempty(setdiff(Set(keys(builders)), Set(declared)))     # and no stale builder

  # Build every participant on every context once; the pairings below are then free.
  built = Dict((name, T) => builder(ctx)
               for (name, ctx) in pairs(CONTEXTS)
               for (T, builder) in builders)

  # THE PRODUCT: every ordered pair × every axis.
  participants = sort(collect(keys(builders)); by = string)
  for A in participants, B in participants
    # Same context: the predicate must accept, or the matrix is testing nothing.
    @test CM._check_matching_context(built[(:base, A)], built[(:base, B)]) === nothing

    # Different context along each axis: the predicate must reject, in BOTH argument orders, since a
    # one-sided check is a real failure mode and costs nothing to rule out.
    for axis in (:domain, :shape, :layout)
      @test_throws ArgumentError CM._check_matching_context(built[(:base, A)], built[(axis, B)])
      @test_throws ArgumentError CM._check_matching_context(built[(axis, A)], built[(:base, B)])
    end
  end
end
