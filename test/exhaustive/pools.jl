# Slot pools — DERIVED, and the derivation audits the builders.
#
# The context pool used to be the literal list `matching / foreign-grid / foreign-layout /
# foreign-eltype`, sitting in a design table under a column headed "pool, derived from". It named no
# mechanism; it restated its own contents. The adversarial pass read the label and attacked elsewhere,
# so the pool kept three of the six values it should have had — and one of the missing three, tensor
# order, is exactly why decision 52's NUFFT defect (a plan used above its own order, returning NaN)
# had to be found by mutating the source instead of by sweeping a product.
#
# THE DERIVATION. A mismatch is only possible in a quantity something compares. The package states
# every such quantity in its own compatibility predicates, so the axis set is read out of their
# lowered IR: each `_check_*` predicate is analysed for the values that flow into an equality test,
# transitively through the helpers it delegates to. Nothing is listed.
#
# WHY DATAFLOW AND NOT A NAME WALK. A predicate calls `field_data` to REACH a value and compares the
# `size` of what it reached. A walk over the names a predicate mentions cannot tell those apart and
# reports the storage accessor as a mismatch axis, which is noise that trains a reader to skim the
# report. Following what actually reaches an `==` separates them mechanically.
#
# WHAT STAYS HAND-WRITTEN, AND WHY IT IS SAFE. Constructing an object that differs in a given
# quantity cannot be derived — someone has to build it. So the builders below are hand-written, and
# the derivation is turned against them: an axis with no builder is reported as NOT REACHED rather
# than dropped. The list can therefore go stale only loudly. This is the `oracle_registry.jl`
# pattern — derive the denominator, hand-write the entries, fail on the difference.

using GBGPeriodicFields
using Random
const GBG = GBGPeriodicFields

package_modules_for_pools() = package_modules()

const EQUALITY_TESTS = (:(==), :(!=), :(===), :(!==), :isequal)


# In lowered IR a callee is often an SSA load of a `GlobalRef` rather than the `GlobalRef` itself —
# `%3 = Mod.===` then `%7 = (%3)(%5, %6)` — so resolving one indirection is required to see which
# function a statement calls at all.
_resolve_name(x, code) =
  x isa GlobalRef                                            ? x.name :
  (x isa Core.SSAValue && checkbounds(Bool, code, x.id) &&
   code[x.id] isa GlobalRef)                                 ? code[x.id].name : nothing

_callee_of(i, code) =
  (checkbounds(Bool, code, i) && code[i] isa Expr && code[i].head === :call && !isempty(code[i].args)) ?
  _resolve_name(code[i].args[1], code) : nothing


"""
    compared_and_called(f) -> (compared, called)

Analyse every method of `f`, returning the names whose result flows into an equality test and the
names `f` calls at all.

The second is what makes the analysis transitive: `_check_same_domain` compares nothing itself, it
delegates to `_same_grid`, and the comparison lives one level down.
"""
function compared_and_called(f::Function)
  compared, called = Set{Symbol}(), Set{Symbol}()
  for m in methods(f)
    ci = try Base.uncompressed_ast(m) catch; continue end
    code = ci.code
    for statement in code
      statement isa Expr && statement.head === :call && !isempty(statement.args) || continue
      name = _resolve_name(statement.args[1], code)
      name === nothing || push!(called, name)
      name in EQUALITY_TESTS || continue
      for argument in statement.args[2:end]
        argument isa Core.SSAValue || continue
        inner = _callee_of(argument.id, code)
        inner === nothing || push!(compared, inner)
      end
    end
  end
  return (compared, called)
end


_lookup(name::Symbol) = begin
  for mod in package_modules_for_pools()
    isdefined(mod, name) || continue
    f = getfield(mod, name)
    f isa Function && return f
  end
  nothing
end


"""
    comparison_predicates() -> Dict{Symbol, Function}

The package's compatibility predicates: every `_check_*` function any package module owns.

These are the functions that decide whether two objects may be used together, so the quantities they
compare are exactly the quantities in which two objects can be incompatible.
"""
function comparison_predicates()
  found = Dict{Symbol, Function}()
  for mod in package_modules_for_pools(), n in names(mod; all = true)
    startswith(String(n), "_check_") || continue
    isdefined(mod, n) || continue
    f = getfield(mod, n)
    f isa Function && (found[n] = f)
  end
  return found
end


# A quantity extractor takes ONE object and returns the thing being compared. Two-argument helpers
# (`_same_grid(a, b)`) are comparisons, not quantities; the arity filter separates them by nature
# rather than by an exclusion list.
function _is_quantity_extractor(name::Symbol)
  f = _lookup(name)
  f === nothing && return false
  return any(m -> m.nargs == 2 && m.module in package_modules_for_pools(), methods(f))
end


# The arity filter alone admits the unary OPERATIONS — `+(field)`, `-(field)`, `transpose(A)` all take
# one section — which reach an equality test through the compatibility check they perform internally.
# They are not attributes, and the difference is settled by what they return rather than by excluding
# them by name: an attribute returns a property, an operation returns another section.
function _is_attribute(name::Symbol, carriers)
  f = _lookup(name)
  f === nothing && return true          # unresolvable here; reported as unreached rather than judged
  for carrier in carriers
    value = try f(carrier) catch; continue end
    return !(value isa GBG.FiberSections.AbstractFiberSection)
  end
  return true                            # not reachable on any canonical carrier; let the audit say so
end


"""
    quantities_compared_by(predicates; depth = 3) -> Set{Symbol}

The quantities that reach an equality test inside any of `predicates`, following delegation.

Taking the predicate set as an argument is what lets the same derivation answer two different
questions: over ALL predicates it gives the pool's axis set, and over the predicates ONE operation
reaches it gives the axes that operation constrains — which is the difference between a mismatch and a
perfectly legal call.
"""
function quantities_compared_by(predicates; depth::Int = 3)
  quantities, seen = Set{Symbol}(), Set{Symbol}()
  frontier = collect(predicates)
  for _ in 1:depth
    isempty(frontier) && break
    next = Function[]
    for f in frontier
      compared, called = compared_and_called(f)
      for c in compared
        _is_quantity_extractor(c) && push!(quantities, c)
      end
      # Follow only into package functions, and only once each: the point is to reach a delegated
      # comparison, not to walk all of Base.
      for name in called
        name in seen && continue
        push!(seen, name)
        g = _lookup(name)
        g === nothing || push!(next, g)
      end
    end
    frontier = next
  end
  carriers = canonical_carriers()
  return Set(q for q in quantities if _is_attribute(q, carriers))
end


"""
    comparable_quantities(; depth = 3) -> Vector{Symbol}

The pool's denominator: every one-argument quantity that reaches an equality test inside any
compatibility predicate.

Two objects can be incompatible in these quantities and no others, because these are the only ones the
package ever compares.
"""
comparable_quantities(; depth::Int = 3) =
  sort(collect(quantities_compared_by(values(comparison_predicates()); depth = depth)); by = String)


"""
    reachable_predicates(operation; depth = 4) -> Vector{Function}

The mismatch axes one operation actually constrains: the quantities compared by the compatibility
predicates it reaches.

An operation constrains an axis only if it checks it. `laplacian` accepts any tensor order by design
and `mean` takes a single argument with no partner to match, so sweeping a foreign tensor order through
either is a legal call, not a defect. Without this the lane reports dozens of cells that are simply the
package working — and a report that cries wolf is read the way a report that says nothing is.
"""
function reachable_predicates(operation::Function; depth::Int = 4)
  reached = Set{Symbol}()
  frontier, seen = [operation], Set{Function}()
  for _ in 1:depth
    next = Function[]
    for g in frontier
      g in seen && continue
      push!(seen, g)
      _, called = compared_and_called(g)
      for n in called
        startswith(String(n), "_check_") && push!(reached, n)
        h = _lookup(n)
        h === nothing || push!(next, h)
      end
    end
    frontier = next
  end
  return filter(!isnothing, [_lookup(n) for n in reached])
end


"""
    constrained_between(operation, a, b) -> Set{Symbol}

The mismatch axes `operation` constrains **between these two particular arguments**.

Taking the whole set of predicates an operation reaches is too coarse: `convolve` reaches both the
kernel check and the broadcast check, so a union over them claims it constrains tensor order between a
field and a kernel. It does not — a scalar kernel broadcasts over the fiber by design, and reporting
that as a mismatch is the lane crying wolf.

The pairing is settled by dispatch: only a predicate with a method for this pair of types can be the
one that relates them, so the axes are read from those predicates alone.
"""
function constrained_between(operation::Function, a, b)
  predicates = reachable_predicates(operation)
  pairing = [p for p in predicates
             if hasmethod(p, Tuple{typeof(a), typeof(b)}) || hasmethod(p, Tuple{typeof(b), typeof(a)})]
  isempty(pairing) && return Set{Symbol}()
  return quantities_compared_by(pairing)
end




# ── The builders ────────────────────────────────────────────────────────────────────────────────
#
# One per derived axis: given a canonical configuration, build a carrier differing in exactly that
# quantity and nothing else. Hand-written by necessity — and audited by `unreached_axes` below, which
# reports any derived axis this table does not answer for.

const CANONICAL_GRID   = Grid3D((8, 6, 4), (2π, 2π, 2π))
const CANONICAL_LAYOUT = RealFourierLayout()
const CANONICAL_GRID32 = Grid3D((8, 6, 4), (2f0 * π, 2f0 * π, 2f0 * π))

_scalar_spectral(T, grid, layout) =
  ScalarFieldSpectral(zeros(Complex{T}, GBG.Fields.field_spectral_shape(grid, layout, Val(0))...),
                      grid, layout)
_vector_spectral(T, grid, layout) =
  VectorFieldSpectral(zeros(Complex{T}, GBG.Fields.field_spectral_shape(grid, layout, Val(1))...),
                      grid, layout)

# A foreign object AT THE TENSOR ORDER THE SLOT TAKES. Every mismatch builder used to return a scalar,
# so an entry point whose slot needs a vector or a tensor never dispatched at all: the cell threw a
# `MethodError` before reaching the package's validation and proved nothing — 67 of 133 cells, the
# lane's largest category, and all of it the harness rather than the package.
_spectral_at(T, grid, layout, order::Int) =
  order == 0 ? _scalar_spectral(T, grid, layout) :
  order == 1 ? _vector_spectral(T, grid, layout) :
               TensorFieldSpectral{2}(zeros(Complex{T},
                                            GBG.Fields.field_spectral_shape(grid, layout, Val(2))...),
                                      grid, layout)

canonical_carrier() = _scalar_spectral(Float64, CANONICAL_GRID, CANONICAL_LAYOUT)

# One canonical object per kind of carrier the package has, so a quantity defined only on the point
# base, only on a multipliers object, or only at second order can still be reached and judged. The
# tensor field is load-bearing: without it `transpose` is unreachable, `_is_attribute` cannot see that
# it returns a section, and a unary OPERATION is reported as a mismatch axis forever.
canonical_carriers() =
  (canonical_carrier(),
   TensorFieldPhysical{2}(zeros(CANONICAL_GRID.grid_size..., 3, 3), CANONICAL_GRID, CANONICAL_LAYOUT),
   PointSet(zeros(4, 3)), ScalarPointValues(zeros(4)), TensorPointValues{2}(zeros(4, 3, 3)),
   FieldSpectralMultipliers(canonical_carrier()))

"""
    MISMATCH_BUILDERS

For each derived axis, a builder producing a carrier that differs from the canonical one in exactly
that quantity — the `foreign-<axis>` pool value a compatibility predicate must reject.

The keys are the accessor names produced by [`comparable_quantities`](@ref); an axis appearing there
and missing here is reported by [`unreached_axes`](@ref), never quietly skipped.
"""
const MISMATCH_BUILDERS = Dict{Symbol, Any}(
  # A different domain size on the same grid shape: same storage, different physics.
  # ANISOTROPIC, and not a uniform rescaling of the canonical box. Doubling every axis identically left
  # both sides axis-isotropic, so a predicate comparing `domain_size[i]` against `domain_size[σ(i)]` for
  # the wrong permutation read the same value either way and was indistinguishable from a correct one.
  :field_grid              => order -> _spectral_at(Float64, Grid3D((8, 6, 4), (4π, 2π, 6π)), CANONICAL_LAYOUT, order),
  :_context_grid           => order -> _spectral_at(Float64, Grid3D((8, 6, 4), (4π, 2π, 6π)), CANONICAL_LAYOUT, order),
  # A permuted fold moves the folded axis, so the spectral shape changes meaning while staying valid.
  :field_layout            => order -> _spectral_at(Float64, CANONICAL_GRID, RealFourierLayout((2, 1, 3)), order),
  :_context_layout         => order -> _spectral_at(Float64, CANONICAL_GRID, RealFourierLayout((2, 1, 3)), order),
  # Float32 against a Float64 canonical — on its own grid, since the grid carries the scalar type too.
  :field_scalar_type       => order -> _spectral_at(Float32, CANONICAL_GRID32, CANONICAL_LAYOUT, order),
  :_section_scalar_type     => order -> _spectral_at(Float32, CANONICAL_GRID32, CANONICAL_LAYOUT, order),
  :_multipliers_scalar_type => () -> FieldSpectralMultipliers(_scalar_spectral(Float32, CANONICAL_GRID32, CANONICAL_LAYOUT)),
  # THE AXIS THE HAND-WRITTEN LIST MISSED. A vector where a scalar is expected: identical grid,
  # layout and element type, different fiber. Decision 52 found the NUFFT instance of this by
  # mutation, because no product contained the combination.
  :field_tensor_order      => () -> _vector_spectral(Float64, CANONICAL_GRID, CANONICAL_LAYOUT),
  :_section_tensor_order    => () -> _vector_spectral(Float64, CANONICAL_GRID, CANONICAL_LAYOUT),
  :point_value_tensor_order => () -> VectorPointValues(zeros(4, 3)),
  # Point-count mismatch: the counting base's version of a shape mismatch.
  :npoints                 => () -> PointSet(zeros(7, 3)),
  :_base_count             => () -> ScalarPointValues(zeros(7)),
  # The storage-shape attributes. They are reached through the same predicates and so are derived
  # alongside the rest; a carrier differing in resolution differs in all three at once, which the
  # grouping in the report makes visible rather than hiding behind one name.
  :size                    => () -> _scalar_spectral(Float64, Grid3D((10, 6, 4), (2π, 2π, 2π)), CANONICAL_LAYOUT),
  :axes                    => () -> _scalar_spectral(Float64, Grid3D((10, 6, 4), (2π, 2π, 2π)), CANONICAL_LAYOUT),
  :ndims                   => () -> _vector_spectral(Float64, CANONICAL_GRID, CANONICAL_LAYOUT),
  :eltype                  => () -> _scalar_spectral(Float32, CANONICAL_GRID32, CANONICAL_LAYOUT),
)


"""
    UNBUILDABLE_AXES

Derived axes that cannot be built in this process, each with the reason.

A conditional cell reports NOT RUN rather than passing silently (the design's reporting rule), so an
axis that needs hardware this host lacks is named here instead of being dropped from the denominator.
"""
const UNBUILDABLE_AXES = Dict{Symbol, String}(
  :_storage_family => "needs a second storage backend (CuArray/ROCArray) — run the GPU suite for it",
)


"""
    unreached_axes() -> Vector{Symbol}

Derived axes for which [`MISMATCH_BUILDERS`](@ref) has no builder and no declared reason.

This is the guard that keeps a hand-written table honest against a derived denominator: a new
compatibility predicate comparing a new quantity adds an axis here, and the suite reports it as NOT
REACHED instead of sweeping a product that silently lacks it.
"""
unreached_axes() =
  [q for q in comparable_quantities() if !haskey(MISMATCH_BUILDERS, q) && !haskey(UNBUILDABLE_AXES, q)]


# ── The point-set pool ──────────────────────────────────────────────────────────────────────────
#
# Partly derived, partly declared-sampled, and the split is stated rather than blurred.
#
# DERIVED: the count boundaries. The point count is a comparable quantity of integer type, and the
# boundaries of a count are the empty and singleton cases — not invented values, the two points where
# a loop over points changes behaviour.
#
# DECLARED-SAMPLED: the geometry. Whether points sit on nodes, cluster, or fall outside the box is a
# property of ℝ³ that no predicate compares and no derivation can enumerate. Per the design's own
# rule, an axis that must be sampled is declared sampled and reported as a limitation — it is NOT
# presented as derived, which is the mistake this file exists to correct.

# CROSSED, not merely declared. These two constants sat here unreferenced while DESIGN.md listed them
# as pool axes — the harness's own configuration described as coverage. `pointset_pool` is what the
# lanes now draw from, so `M = 0`, `M = 1`, on-node, clustered and outside-the-box points reach a cell.
const POINTSET_COUNT_VALUES = (0, 1, 32)                                          # derived
const POINTSET_GEOMETRY_VALUES = (:uniform, :on_node, :clustered, :outside_box)    # declared-sampled

pointset_pool(grid = CANONICAL_GRID) =
  [("M=$(n)/$(geometry)", build_pointset(n, geometry, grid))
   for n in POINTSET_COUNT_VALUES, geometry in POINTSET_GEOMETRY_VALUES] |> vec

"""
    run_mismatch_lane() -> (findings, cells)

Sweep the derived mismatch pool over every entry point that takes a context-carrying argument, and
report the combinations that are ACCEPTED rather than rejected.

The property is uniform and does not need an oracle: an argument differing from its partner in a
quantity the package compares must be refused. A call that returns instead has computed something
against a carrier built for a different object, which is the silent-corruption class — CODE-04's NUFFT
plan reused on a foreign field, and decision 52's plan used above its own tensor order.
"""
function run_mismatch_lane()
  println("═"^100)
  println("LANE: context mismatch — every entry point × every DERIVED mismatch axis")
  println("      the axes come from the compatibility predicates' own IR, not from a list")
  println("═"^100)

  axes = comparable_quantities()
  println("\n  ", length(axes), " derived axes: ", join(String.(axes), ", "))
  unreached = unreached_axes()
  if isempty(unreached)
    println("  every derived axis has a builder")
  else
    println("  NOT REACHED (a derived axis with no builder): ", join(String.(unreached), ", "))
  end
  for (axis, why) in UNBUILDABLE_AXES
    println("  NOT RUN — ", axis, ": ", why)
  end

  Random.seed!(20260801)          # the lane draws random fields; every other data-generating lane seeds
  grid, layout = CANONICAL_GRID, CANONICAL_LAYOUT
  scalar = _scalar_spectral(Float64, grid, layout)
  vector = _vector_spectral(Float64, grid, layout)
  multipliers = FieldSpectralMultipliers(scalar)
  points = build_pointset(8, :uniform, grid)
  # The declared point-set axes, actually swept: every count boundary against every geometry, checked
  # for the property that a transfer verb either works or refuses — never returns a wrong answer.
  pointset_cases = pointset_pool(grid)
  physical = ScalarFieldPhysical(rand(grid.grid_size...), grid, layout)
  values = ScalarPointValues(zeros(8))
  kernel = spectral_cutoff(multipliers, 3.0)

  # Each entry names the operation, the CANONICAL PARTNER the foreign object has to agree with, and the
  # call that puts the foreign object in the slot under test. The partner is not decoration: a mismatch
  # is a relation between two arguments, so an entry point with only one context-carrying argument —
  # `mean(f)` — has nothing to mismatch against and is not a cell at all.
  # The fourth column is the slot's DECLARED fiber contract: `:many` if the operation is generic over
  # tensor order in that slot, `:one` if it takes exactly one.
  #
  # WHY THIS IS DECLARED AND NOT PROBED. The obvious move is to ask the package — call the slot at each
  # order and call it generic when several succeed. That is a SELF-REFERENTIAL ORACLE and it fails
  # exactly when it matters: with the spectral `inner` order check removed, `inner(scalar, vector)`
  # succeeds, the probe concludes the slot is generic, and the lane skips the one cell that would have
  # exposed the defect. Verified by re-injecting the bug — the lane reported all-clear and swept two
  # fewer cells. A defect must never be able to make itself inapplicable.
  #
  # So the contract is stated here and the probe becomes the ASSERTION: a slot declared `:one` that
  # accepts more than one order is a finding, which is precisely the shape of the bug this lane found.
  entries = (
    ("gradient(f, mult)",              gradient,    multipliers, :many, foreign -> gradient(foreign, multipliers)),
    ("laplacian(f, mult)",             laplacian,   multipliers, :many, foreign -> laplacian(foreign, multipliers)),
    ("divergence(u, mult)",            divergence,  multipliers, :many, foreign -> divergence(foreign, multipliers)),
    ("helmholtz_projection(u, mult)",  helmholtz_projection, multipliers, :one,
                                                    foreign -> helmholtz_projection(foreign, multipliers)),
    ("convolve(f, kernel)",            convolve,    kernel,      :many, foreign -> convolve(foreign, kernel)),
    ("convolve!(dest, f, kernel)",     convolve!,   kernel,      :one,  foreign -> convolve!(similar_field(scalar, Val(0)), foreign, kernel)),
    ("inner(f, g) spectral",           inner,       scalar,      :one,  foreign -> inner(scalar, foreign)),
    ("inner(f, g) physical",           inner,       physical,    :one,  foreign -> inner(physical, foreign)),
    ("weighted_inner(f, g, w)",        weighted_inner, scalar,   :one,  foreign -> weighted_inner(scalar, foreign, multipliers)),
    ("add!(dest, a, b)",               add!,        physical,    :one,  foreign -> add!(similar_field(physical, Val(0)), physical, foreign)),
    ("interpolate(f, pts, NUFFT)",     interpolate, NUFFT(scalar), :one, foreign -> interpolate(foreign, points, NUFFT(scalar))),
    ("anterpolate(f, pts, q, NUFFT)",  anterpolate, NUFFT(scalar), :one, foreign -> anterpolate(scalar, points, foreign, NUFFT(scalar))),
    # The scattered values must carry the destination field's fiber, so this slot takes exactly one
    # order — declared `:many` at first, and the contract check corrected it.
    ("anterpolate(f, pts, q, spline)", anterpolate, points,      :one,  foreign -> anterpolate(grid, points, foreign, CatmullRom)),
    ("radial_spectrum(f, mult)",       radial_spectrum, multipliers, :many, foreign -> radial_spectrum(foreign, multipliers)),
  )

  # An operation that accepts several tensor orders in a slot is FIBER-GENERIC there, and handing it a
  # different order is then a supported call rather than a mismatch — `gradient` takes a scalar or a
  # vector, `laplacian` and `convolve` take any order, a scalar kernel broadcasts over the fiber. This
  # is settled by trying the slot at each order rather than by declaring it: an entry that accepts more
  # than one is generic, and one that accepts exactly one is constrained.
  order_axes = Set([:field_tensor_order, :_section_tensor_order, :point_value_tensor_order, :ndims])
  # The probe has to offer a candidate of the slot's OWN kind, at each tensor order. A slot taking point
  # values is not exercised by handing it fields: every call throws, the slot looks as though it accepts
  # nothing, and a correctly fiber-generic slot is reported as a contract breach. The point-value
  # candidates carry the same count as `points` so the base check is not what refuses them.
  M = npoints(points)
  canonical_by_order = (scalar, vector,
                        TensorFieldSpectral{2}(zeros(ComplexF64, GBG.Fields.field_spectral_shape(grid, layout, Val(2))...),
                                               grid, layout),
                        physical,
                        VectorFieldPhysical(zeros(grid.grid_size..., 3), grid, layout),
                        TensorFieldPhysical{2}(zeros(grid.grid_size..., 3, 3), grid, layout),
                        ScalarPointValues(zeros(M)), VectorPointValues(zeros(M, 3)),
                        TensorPointValues{2}(zeros(M, 3, 3)))
  # Which orders a slot accepts, and which one is its NATURAL input. The natural input matters because
  # "foreign" is relative: `helmholtz_projection` takes a vector, so handing it the vector built as the
  # foreign-tensor-order object hands it exactly what it wants. An object that does not differ from the
  # slot's own canonical input in the axis under test is not a mismatch at all.
  # Counted as DISTINCT TENSOR ORDERS accepted, not as candidates accepted: the candidate list carries
  # three representations of each order, and a slot taking one of them at two orders is generic while a
  # slot taking two representations of one order is not.
  # The names here are deliberately unlike the lane's own `accepted` list: a closure that assigns to a
  # name the enclosing function also uses REBINDS the outer one, and this one silently turned the
  # findings vector into a bag of fields.
  function slot_orders(call, label)
    taken, orders = Any[], Set{Int}()
    probe_errors = String[]
    for candidate in canonical_by_order
      try
        call(candidate)
        push!(taken, candidate)
        push!(orders, GBG.FiberSections._section_tensor_order(candidate))
      catch exception
        # An earlier commit added `probe_errors` and the report below but never wrote to it, so the
        # guard could not fire. Scaffolding without the substance reads as fixed and is worse than the
        # bare `catch` it replaced.
        #
        # The exception type alone cannot decide here, unlike the `accepts` block fifty lines below. A
        # `MethodError` is BOTH the package declining a tensor order by dispatch — the very signal this
        # probe reads — and the historical harness bug of calling an arity that does not exist. What
        # separates them is derived rather than declared: the closure is fixed and only the candidate
        # varies, so a broken closure fails for EVERY candidate while a genuine refusal spares at least
        # one. The verdict is therefore taken below, once all candidates have been tried.
        is_domain_refusal(exception) || push!(probe_errors, String(nameof(typeof(exception))))
      end
    end
    # A probe that accepted NOTHING while throwing something other than a domain refusal did not read
    # the package at all — the closure itself is wrong, and its empty `orders` would be handed to the
    # fiber contract check as though the package had declined every order.
    isempty(taken) && !isempty(probe_errors) &&
      Base.push!(lane_errors, "$(label): the slot-order probe accepted no candidate and threw " *
                              join(unique(probe_errors), "/") *
                              " — the closure is wrong, not the package")
    return (taken = taken, orders = orders)
  end

  accepted, cells, skipped = String[], 0, 0
  contract_breaches, lane_errors = String[], String[]
  for (label, operation, partner, declared, call) in entries
    probe = slot_orders(call, label)
    generic = declared === :many
    # The probe is checked AGAINST the declaration rather than replacing it. A slot declared to take one
    # tensor order that accepts several has lost a fiber check — the defect this lane found — and a slot
    # declared generic that accepts one has had its surface narrowed.
    if declared === :one && length(probe.orders) > 1
      push!(contract_breaches,
            "$(rpad(label, 34)) declared one tensor order, accepts $(length(probe.orders))")
    elseif declared === :many && length(probe.orders) <= 1
      push!(contract_breaches,
            "$(rpad(label, 34)) declared fiber-generic, accepts only $(length(probe.orders))")
    end
    natural = isempty(probe.taken) ? scalar : first(probe.taken)
    # The order the SLOT takes, so the foreign object dispatches. A builder returning a scalar into a
    # vector slot threw `MethodError` before the package saw it — the cell tested nothing, 67 times.
    slot_order = isempty(probe.orders) ? 0 : minimum(probe.orders)
    for axis in axes
      haskey(MISMATCH_BUILDERS, axis) || continue
      builder = MISMATCH_BUILDERS[axis]
      foreign = try
        applicable(builder, slot_order) ? builder(slot_order) : builder()
      catch
        continue
      end
      if generic && axis in order_axes
        skipped += 1
        continue                # the slot is fiber-generic, so a differing order is a supported call
      end
      accessor = _lookup(axis)
      if accessor !== nothing
        same = try accessor(foreign) == accessor(natural) catch; false end
        if same
          skipped += 1
          continue              # identical to the slot's own natural input in this axis: not foreign
        end
      end
      if !(axis in constrained_between(operation, foreign, partner))
        skipped += 1
        continue                # no predicate relates this pair on this axis, so differing is legal
      end
      cells += 1
      # The exception TYPE, as the property lane already does: `catch; false` scores a `MethodError`
      # from a mis-written harness call as a correct refusal. That is not hypothetical here — the two
      # entries above called a `similar_field` arity that does not exist, so every one of their cells
      # threw before reaching the package and was recorded as "refused".
      accepts = try
        call(foreign)
        true
      catch exception
        is_domain_refusal(exception) ? false :
          (Base.push!(lane_errors, "$(label) × $(axis): threw $(nameof(typeof(exception))), " *
                                   "not a domain error — the cell never reached the package"); false)
      end
      accepts && push!(accepted, "$(rpad(label, 34)) accepted a foreign $(axis)")
    end
  end

  # The point-set axes. `M = 0`, `M = 1`, on-node, clustered and outside-the-box were declared in the
  # design table and swept nowhere; `build_pointset`'s three non-uniform branches were unreachable code.
  pointset_accepted = String[]
  for (label, candidate) in pointset_cases
    for (verb, call) in (("interpolate", () -> interpolate(physical, candidate, CatmullRom)),
                         ("anterpolate", () -> anterpolate(grid, candidate,
                                                           ScalarPointValues(zeros(npoints(candidate))),
                                                           CatmullRom)))
      cells += 1
      outcome = try
        result = call()
        # An empty point set makes `all(isfinite, ...)` vacuously true, so the assertion for `M = 0` is
        # that the result is the ZERO field an empty scatter must produce, not merely that nothing threw.
        data = Array(field_data(result))
        npoints(candidate) == 0 && verb == "anterpolate" ?
          (all(iszero, data) ? :ok : :nonzero_from_empty) :
          (all(isfinite, data) ? :ok : :nonfinite)
      catch exception
        is_domain_refusal_or_bounds(exception) ? :refused : nameof(typeof(exception))
      end
      outcome in (:ok, :refused) ||
        Base.push!(pointset_accepted, "$(verb) on $(label): $(outcome)")
    end
  end
  if !isempty(pointset_accepted)
    println("\n  POINT-SET AXIS — ", length(pointset_accepted), " cells neither computed nor refused:")
    for entry in pointset_accepted; println("      ", entry); end
  end

  println("\n  ", cells, " (entry point × constrained axis) cells swept")
  println("  ", skipped, " NOT APPLICABLE — the operation does not constrain that axis, so passing a")
  println("      differing object is a legal call rather than a mismatch")
  if isempty(accepted)
    println("\n  every mismatched argument was refused")
  else
    println("\n  ACCEPTED A MISMATCHED ARGUMENT — ", length(accepted), " cells.")
    println("  A call that returns here has computed against a carrier built for a different object.")
    for a in accepted; println("      ", a); end
  end
  if !isempty(lane_errors)
    println("\n  THE CELL NEVER REACHED THE PACKAGE — ", length(unique(lane_errors)), " distinct:")
    for e in unique(lane_errors)[1:min(end, 8)]; println("      ", e); end
  end
  if !isempty(contract_breaches)
    println("\n  FIBER CONTRACT BREACHED — ", length(contract_breaches), " slots:")
    for b in contract_breaches; println("      ", b); end
  end
  return (length(accepted) + length(unreached) + length(contract_breaches) +
          length(unique(lane_errors)) + length(pointset_accepted), cells)
end


function build_pointset(count::Int, geometry::Symbol, grid::Grid3D = CANONICAL_GRID)
  count == 0 && return PointSet(zeros(0, 3))
  L, Δ = grid.domain_size, grid.grid_spacing
  coordinates = Matrix{Float64}(undef, count, 3)
  # A DIFFERENT PROGRESSION PER AXIS. `L[d] * (p - 1) / count` over an axis-isotropic box put every
  # point on the space diagonal, where x = y = z, so permuting the coordinate columns changed nothing
  # and an axis transposition in a transfer verb was unobservable on the geometry pool that exists to
  # sweep exactly that. The stride now varies with the axis. (`:on_node` and `:clustered` were already
  # axis-dependent through `grid_size` and `Δ`.)
  # PLUS THE ORIGIN, in every branch — the sibling of the same fix in `invocations.jl`. Every other point
  # builder in the suite adds it; this one did not, so this geometry axis could never be crossed with a
  # shifted origin at all. Dormant only because its one call site passes a zero-origin grid, which is
  # what makes it the kind of gap that survives a reading.
  for p in 1:count, d in 1:3
    coordinates[p, d] = grid.origin[d] + (
      geometry === :uniform   ? L[d] * mod((p - 1) * d, count) / count :
      geometry === :on_node   ? Δ[d] * mod(p - 1, grid.grid_size[d]) :
      # The per-axis rate DIFFERS. With one rate the cell-fractional coordinate `(x_d - o_d)/Δ_d` is the
      # same number on all three axes — the spacing cancels — so all three stencil weight arrays are
      # numerically equal and swapping which one multiplies which index changes nothing, on the very
      # fixture built to exercise overlapping stencils.
      geometry === :clustered ? Δ[d] * (0.5 + (1e-3 + 1e-4 * d) * p) :
                                L[d] * mod((p - 1) * d, count) / count + 3 * L[d])  # outside the box
  end
  return PointSet(coordinates)
end
