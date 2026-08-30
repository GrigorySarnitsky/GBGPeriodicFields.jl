# Tier 3 of the context-mismatch matrix: the PEER-SECTION product.
#
# Tier 1 (`context_matrix.jl`) proves the predicates reject mismatched pairs; tier 2
# (`context_entrypoints.jl`) proves every operation taking a context CARRIER — multipliers, kernel,
# plans, a scheme — calls one. This tier covers the operations tier 2 cannot see: the ones whose
# context check is against a PEER — a second section whose grid, domain, layout or point count must
# agree — plus the unaries and readers whose refusal lives elsewhere and is cited, not waved at.
#
# WHY IT EXISTS (2026-08-29). The applicability ledger reported `domain_rejection` at 35/88 and the
# number was advisory: nothing failed when an operation that validates had no refusal test, so the
# list drifted. Measured against tier 2, 88 operations validate, 36 were enforced there, and 52 had
# NO gate. This file is the allocation-audit shape applied to those 52: a DERIVED denominator, an
# invocation or an exemption-with-cited-assertion for every member, and completeness assertions in
# both directions, so a new validating operation fails the suite until someone decides what it is.
#
# THE DENOMINATOR IS DERIVED, mirroring the exhaustive ledger's `validates` bit: an operation is in
# scope iff a `_check_*` predicate is reachable from it in the lowered IR of its package-owned
# methods (depth-4 walk, identical to `test/exhaustive/ledger.jl`'s `reachable_names`). Nothing here
# is a hand-kept list of operations; only the DISPOSITIONS are hand-written, which is the part that
# needs judgment.

using Test
using GBGPeriodicFields
using Statistics
include("public_surface.jl")

const PF = GBGPeriodicFields
const PRLAYOUT = RealFourierLayout()
const PR_MODULES = (PF.FiberSections, PF.Fields, PF.FieldAlgebra, PF.DifferentialOperators,
                    PF.Convolution, PF.Points, PF.Interpolation, PF.Reductions)


function _pr_lookup(name::Symbol)
  for mod in (PF, Base, Statistics, PR_MODULES...)
    isdefined(mod, name) || continue
    object = getfield(mod, name)
    object isa Function && return object
  end
  return nothing
end


# The ledger's `reachable_names`, verbatim in behaviour: which helper names appear in the lowered IR
# of this operation's package-owned methods, followed to depth 4.
function _pr_reachable(f::Function; depth::Int = 4)
  seen, out = Set{Function}(), Set{Symbol}()
  frontier = Function[f]
  for _ in 1:depth
    next = Function[]
    for g in frontier
      g in seen && continue
      push!(seen, g)
      names = Set{Symbol}()
      walk(x) = x isa GlobalRef ? push!(names, x.name) :
                x isa Expr     ? foreach(walk, x.args) : nothing
      for m in methods(g)
        m.module in PR_MODULES || continue
        ci = try Base.uncompressed_ast(m) catch; continue end
        foreach(walk, ci.code)
      end
      union!(out, names)
      for n in names
        h = _pr_lookup(n)
        h === nothing || Base.push!(next, h)
      end
    end
    frontier = next
  end
  return out
end


validating_operations() = sort([op for op in package_operations()
                                if (f = _pr_lookup(op)) !== nothing &&
                                   any(n -> startswith(String(n), "_check_"), _pr_reachable(f))];
                               by = String)


# The operations tier 2 already enforces, read from its OWN invocation registry rather than kept as
# a second list that could drift. The file holds them as `(:name, :kind) =>` literals; every parsed
# name is then required to be a real package function, so a parse slip cannot silently shrink the set.
function carrier_enforced()
  text = read(joinpath(@__DIR__, "context_entrypoints.jl"), String)
  found = Set{Symbol}()
  for m in eachmatch(r"\(:([A-Za-z_][A-Za-z0-9_]*!?), :[a-z_]+\)\s*=>", text)
    Base.push!(found, Symbol(m.captures[1]))
  end
  phantoms = [op for op in found if _pr_lookup(op) === nothing]
  isempty(phantoms) || error("carrier_enforced parsed names that are no real function: $phantoms")
  return found
end


# ── Contexts: same grid SHAPE, different domain / shape / layout — tier 2's axes ─────────────────
const PRCTX = (
  base   = (grid = Grid3D((8, 6, 4), (2π, 2π, 2π)),  layout = PRLAYOUT),
  domain = (grid = Grid3D((8, 6, 4), (4π, 4π, 4π)),  layout = PRLAYOUT),
  shape  = (grid = Grid3D((10, 6, 4), (2π, 2π, 2π)), layout = PRLAYOUT),
  layout = (grid = Grid3D((8, 6, 4), (2π, 2π, 2π)),  layout = RealFourierLayout((2, 1, 3))),
)

prsphys(c) = ScalarFieldPhysical(rand(c.grid.grid_size...), c.grid, c.layout)
prvphys(c) = VectorFieldPhysical(rand(c.grid.grid_size..., 3), c.grid, c.layout)
prtphys(c) = TensorFieldPhysical{2}(rand(c.grid.grid_size..., 3, 3), c.grid, c.layout)
prsspec(c) = ScalarFieldSpectral(randn(ComplexF64, PF.Fields.spectral_field_shape(c.grid, c.layout, Val(0))), c.grid, c.layout)


# ── The registry: one invocation per peer operation ──────────────────────────────────────────────
# Each entry calls the operation with its FIRST operand (and any destination) on `b` and its peer on
# `f`; the sweep demands the matching call work and every foreign axis throw. In-place forms carry
# the peer check for their allocating siblings (the sibling allocates and delegates), so the `!` form
# is the one invoked and the sibling is exempted onto it.
const PEER_INVOCATIONS = Dict{Symbol, Function}(
  :+          => (b, f) -> prsphys(b) + prsphys(f),
  :-          => (b, f) -> prsphys(b) - prsphys(f),
  :*          => (b, f) -> prsphys(b) * prsphys(f),
  :/          => (b, f) -> prsphys(b) / prsphys(f),
  :add!       => (b, f) -> add!(prsphys(b), prsphys(b), prsphys(f)),
  :subtract!  => (b, f) -> subtract!(prsphys(b), prsphys(b), prsphys(f)),
  :multiply!  => (b, f) -> multiply!(prsphys(b), prsphys(b), prsphys(f)),
  :divide!    => (b, f) -> divide!(prsphys(b), prsphys(b), prsphys(f)),
  :combine!   => (b, f) -> combine!(prsphys(b), 0.5, prsphys(b), 0.5, prsphys(f)),
  :cross      => (b, f) -> cross(prvphys(b), prvphys(f)),
  :cross!     => (b, f) -> cross!(prvphys(b), prvphys(b), prvphys(f)),
  :×          => (b, f) -> prvphys(b) × prvphys(f),
  :dot        => (b, f) -> dot(prvphys(b), prvphys(f)),
  :dot!       => (b, f) -> dot!(prsphys(b), prvphys(b), prvphys(f)),
  :⋅          => (b, f) -> prvphys(b) ⋅ prvphys(f),
  :mul!       => (b, f) -> mul!(prtphys(b), prtphys(b), prtphys(f)),
  # Destination against source: the unary index-shuffles check their two sections agree.
  :det!       => (b, f) -> det!(prsphys(b), prtphys(f)),
  :dev!       => (b, f) -> dev!(prtphys(b), prtphys(f)),
  :sym!       => (b, f) -> sym!(prtphys(b), prtphys(f)),
  :skew!      => (b, f) -> skew!(prtphys(b), prtphys(f)),
  :norm!      => (b, f) -> norm!(prsphys(b), prvphys(f)),
  :tr!        => (b, f) -> tr!(prsphys(b), prtphys(f)),
  :transpose! => (b, f) -> transpose!(prtphys(b), prtphys(f)),
  # The broadcast entry point: `destination .= source` across contexts must refuse (invariant 14's
  # own example of why `copyto!` is not the conversion route).
  :copyto!    => (b, f) -> (d = prsphys(b); d .= prsphys(f); d),
  # Multi-input map with sections on two contexts.
  :map        => (b, f) -> map(+, prsphys(b), prsphys(f)),
  :map!       => (b, f) -> map!(+, prsphys(b), prsphys(b), prsphys(f)),
  # The mixed reductions.
  :inner      => (b, f) -> inner(prsphys(b), prsphys(f)),
  # adapt! into a destination that already exists: contexts must agree.
  :adapt!     => (b, f) -> adapt!(prsphys(b), prsphys(f)),
)


# ── Exemptions: every one CITES the assertion that carries its refusal, or states why none can ──
const PEER_EXEMPT = Dict{Symbol, String}(
  # Unary at the public surface: no second operand whose context could disagree. Each allocating
  # form's peer check lives in the `!` sibling it delegates to, invoked above.
  :copy   => "unary; takes one section and returns its copy — no peer to disagree",
  :det    => "unary allocating form; the peer check is `det!`'s, invoked here",
  :dev    => "unary allocating form; the peer check is `dev!`'s, invoked here",
  :sym    => "unary allocating form; the peer check is `sym!`'s, invoked here",
  :skew   => "unary allocating form; the peer check is `skew!`'s, invoked here",
  :norm   => "unary allocating form; the peer check is `norm!`'s, invoked here",
  :tr     => "unary allocating form; the peer check is `tr!`'s, invoked here",
  :transpose => "unary allocating form; the peer check is `transpose!`'s, invoked here",
  :cov    => "unary (one vector section in, one fiber tensor out); no peer",
  # A point set carries no grid affiliation, so `transfer_order(points, grid)` has no context pair
  # that COULD disagree — and a point outside the grid is deliberately clamped into an edge bucket
  # rather than refused, because an order is a hint that never changes a result (decision 78). Its
  # own refusals are of a malformed `tile_size`, asserted in test/transfer_order.jl.
  :transfer_order => "no context pair: points carry no grid, and out-of-grid points are clamped by design (decision 78); its tile_size refusals are asserted in test/transfer_order.jl",
  :ndims  => "an accessor; reads one object, validates nothing a peer could contradict",
  :setindex! => "a single-element write through the AbstractArray interface; its bounds check is Julia's, not a context check",
  :reality_residual => "unary; reads one spectral section's self-conjugate planes",
  :integral => "unary reduction (the mapped form's first argument is a function, not a section)",
  :mean     => "unary reduction, as `integral`",
  :maximum  => "unary reduction, as `integral`",
  :minimum  => "unary reduction, as `integral`",
  :extrema  => "unary reduction, as `integral`",
  :var      => "unary reduction, as `integral`",
  :std      => "unary reduction, as `integral`",
  :l2norm   => "unary reduction, as `integral`",
  :lpnorm   => "unary reduction (the order `p` is a number, not a section)",
  # Refusals asserted elsewhere, cited by file: these readers reject a corrupted or wrong-version
  # group, and the corrupted-group lanes in `test/hdf5.jl` assert exactly that.
  :read_field  => "rejects corrupted/wrong-version input — asserted by test/hdf5.jl's corrupted-group testsets",
  :read_points => "rejects corrupted/wrong-version input — asserted by test/hdf5.jl's corrupted-group testsets",
  :read_scheme => "rejects a malformed scheme group — asserted by test/hdf5.jl (decision 75's lanes)",
  :⋆ => "operator alias of `convolve`; the binding is the one swept as (:convolve, :kernel) in context_entrypoints.jl",
)


# The point layer's operations, invoked in their own testset below: their peer axes are the point
# COUNT and the PRECISION of points against a grid, not the grid contexts the sweep above varies.
const POINT_COVERED = Set([:displace!, :wrap!])


@testset "peer rejections: every validating operation outside the carrier gate refuses a foreign peer" begin
  denominator = validating_operations()
  carriers = carrier_enforced()
  in_scope = setdiff(Set(denominator), carriers)
  covered = union(Set(keys(PEER_INVOCATIONS)), Set(keys(PEER_EXEMPT)), POINT_COVERED)

  # Completeness, both directions — the gate that makes the ledger's advisory row enforceable.
  uncovered = setdiff(in_scope, covered)
  isempty(uncovered) ||
    @error "a validating operation is neither invoked nor exempted here — decide which" sort(collect(uncovered); by = String)
  @test isempty(uncovered)
  # An entry outside this file's own derivation is EXTRA enforcement, kept deliberately, not an
  # error: `combine!` is carrier-enforced for its kernel but its two operand sections are a peer pair
  # only this file checks, and the readers' exemptions cite refusals this file's shallow IR walk
  # cannot see (their methods live in the HDF5 extension). What must never survive is an entry naming
  # no real function at all — the phantom guard the allocation audit also carries.
  phantoms = [op for op in covered if _pr_lookup(op) === nothing]
  isempty(phantoms) ||
    @error "entries that name no real package function" sort(collect(phantoms); by = String)
  @test isempty(phantoms)
  extra = sort(collect(setdiff(covered, in_scope)); by = String)
  isempty(extra) || @info "entries beyond this file's derived scope (extra enforcement, kept)" extra

  base = PRCTX.base
  for (operation, invoke) in sort(collect(PEER_INVOCATIONS); by = first)
    # The matching call must WORK, or the rejections below prove nothing.
    @test invoke(base, base) !== nothing
    for axis in (:domain, :shape, :layout)
      foreign = getfield(PRCTX, axis)
      @test_throws Exception invoke(base, foreign)
    end
  end
end


# The point layer's peer axis is the POINT COUNT (and, cross-backend, the storage family — a CPU
# process cannot build the mismatch, so the GPU suite carries that half).
@testset "peer rejections: the point layer refuses a mismatched point count" begin
  points12 = PointSet(rand(12, 3) .* 2π)
  values12 = VectorPointValues(rand(12, 3))
  values9  = VectorPointValues(rand(9, 3))
  @test displace!(PointSet(rand(12, 3)), points12, (0.5, values12)) !== nothing
  @test_throws Exception displace!(PointSet(rand(12, 3)), points12, (0.5, values9))
  @test add!(VectorPointValues(zeros(12, 3)), values12, values12) !== nothing
  @test_throws Exception add!(VectorPointValues(zeros(12, 3)), values12, values9)
  @test_throws Exception adapt!(VectorPointValues(zeros(9, 3)), values12)

  # `wrap!`'s one context check is PRECISION: the canonical representative is computed in the points'
  # own element type, and a grid of another precision must refuse rather than silently convert
  # (invariant 14's no-conversion rule, applied to the one pair `displace!`/`wrap!` can mismatch on
  # a single backend — the storage-family half needs a device and lives in the GPU suite).
  grid64 = Grid3D((8, 6, 4), (2π, 2π, 2π))
  points32 = PointSet(rand(Float32, 12, 3) .* 2.0f0)
  @test wrap!(PointSet(rand(12, 3) .* 2π), grid64) !== nothing
  @test_throws Exception wrap!(points32, grid64)
end
