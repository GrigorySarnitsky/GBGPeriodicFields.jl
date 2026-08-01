# The suite checking ITSELF.
#
# WHY. Every false-finding class this suite produced was a defect in the HARNESS, not in the package:
# a shared pool that let one in-place call poison every later one, a destination index that blamed
# `map!` for writing to its own destination, a pool function whose second arity meant something else,
# and NaN inequality — which had to be fixed TWICE, once per comparison branch, because fixing the
# instance is not fixing the class. Each was found by reading output and repaired in place, and nothing
# was left behind that would catch a recurrence. This file is that guard.
#
# AND THE HARDER HALF. A false POSITIVE announces itself; a false NEGATIVE is silent. The five checks
# report tens of thousands of clean cells, and nothing in the sweep demonstrates that any of them can
# fire — a vacuous check looks exactly like a passing one. This suite has already shipped a vacuous
# assertion once (the C6 threading assertion, decision 47, which compared a path against itself), and
# its own fiber-generic probe once let a defect declare itself inapplicable. So every check is driven
# here against an operation built to violate it, and a check that does NOT fire is a failure.

using GBGPeriodicFields
using Statistics
using LinearAlgebra


# ── Operations built to violate exactly one property ────────────────────────────────────────────
#
# Each is a plain function, so the checks see them the way they see the package's own.

function _defect_preservation!(destination, source)
  fill!(field_data(source), 0)                       # writes an argument that is not the destination
  copyto!(field_data(destination), field_data(source))
  return destination
end

_defect_structural(field) = ScalarFieldPhysical(fill(NaN, size(field_data(field))),
                                                field_grid(field), field_layout(field))

# Returns a field on a DIFFERENT grid and layout: the metadata-propagation defect that broke `map` for
# every permuted layout from the day it shipped (decision 48).
_defect_metadata(field) =
  ScalarFieldPhysical(copy(field_data(field)),
                      Grid3D(field_grid(field).grid_size, (4π, 4π, 4π)),
                      RealFourierLayout((2, 1, 3)))

_defect_determinism(field) = sum(field_data(field)) + rand()

# Type-unstable by construction: the return type depends on a runtime value, so inference can only
# offer a Union. Note that the check this replaced could NOT be violated at all — `return_types` is
# sound, so no valid Julia function disagrees with it, and that is precisely why the self-check
# reported it vacuous.
_defect_type_stability(field) = sum(field_data(field)) > 0 ? 1 : "unstable"


"""
    run_selfcheck_lane(config) -> failures

Prove each universal check can fail, and guard the four harness defects that produced false findings.
"""
function run_selfcheck_lane(config)
  println("═"^100)
  println("LANE: self-check — the harness, not the package")
  println("      every universal check is driven against an operation built to violate it; a check")
  println("      that does not fire is vacuous, and a vacuous check is worse than an absent one")
  println("═"^100)

  failures = String[]
  pool = canonical_pool(config)
  # Not `something(findfirst(...), error(...))`: Julia evaluates the fallback eagerly, so the error
  # fires whether or not the entry is present.
  function entry(label)
    index = findfirst(e -> e.label == label, pool)
    index === nothing && error("the self-check expects a pool entry named $(label)")
    return index
  end
  field = pool[entry("physical R=0")].object
  other = _refresh(field)

  # ── each check must fire ──────────────────────────────────────────────────────────────────────
  cases = (
    (:preservation, "an in-place call that writes a non-destination argument",
     (operation = _defect_preservation!, label = "_defect_preservation!(dest, source)",
      arguments = Any[other, _refresh(field)], entries = ())),
    (:structural, "a call returning NaN from finite input",
     (operation = _defect_structural, label = "_defect_structural(f)",
      arguments = Any[_refresh(field)], entries = ())),
    (:metadata, "an allocating call that drops the grid and layout",
     (operation = _defect_metadata, label = "_defect_metadata(f)",
      arguments = Any[_refresh(field)], entries = ())),
    (:determinism, "a call that does not reproduce across identical invocations",
     (operation = _defect_determinism, label = "_defect_determinism(f)",
      arguments = Any[_refresh(field)], entries = ())),
    (:type_stability, "a call whose return type inference cannot pin down",
     (operation = _defect_type_stability, label = "_defect_type_stability(f)",
      arguments = Any[_refresh(field)], entries = ())),
  )

  println("\n  EACH CHECK FIRES ON ITS OWN DEFECT")
  for (kind, description, invocation) in cases
    found = Dict{Symbol, Vector{String}}()
    record!(k, message) = Base.push!(get!(found, k, String[]), message)
    count!(_) = nothing
    try
      check_invocation!(invocation, record!, count!)
    catch exception
      Base.push!(failures, "$(kind): the self-check itself threw $(nameof(typeof(exception)))")
      println("      ", rpad(String(kind), 16), "THREW ", nameof(typeof(exception)))
      continue
    end
    fired = haskey(found, kind) && !isempty(found[kind])
    fired || Base.push!(failures, "$(kind) did NOT fire on $(description) — the check is vacuous")
    println("      ", rpad(String(kind), 16), fired ? "fires" : "VACUOUS — did not fire on $(description)")
  end

  # ── every LANE's comparison step must fire, not only the universal checks ─────────────────────
  # The self-check covered the five checks in `check_invocation!` and nothing else, so eight of nine
  # lanes were outside the discipline this file exists to enforce. A vacuity review found the relations
  # lane's comparisons unproven; these drive each lane's extracted comparison against a triple that is
  # false by construction, and a lane that reports it as holding is a failure.
  println("\n  EVERY LANE'S COMPARISON STEP FIRES")
  lane_probes = (
    ("relations lane", () -> relation_holds("planted", [1.0, 2.0], [1.0, 3.0], 1e-9, Float64) === false),
    ("relations lane (bool)", () -> relation_holds("planted", false, true, 1e-9, Float64) === false),
    # `relation_holds` returns the exception TYPE on a throw, not the sentinel `:threw` — the probe was
    # written against the older contract and the self-check caught the drift on the next run, which is
    # what it is for.
    ("relations lane (throws)", () -> relation_holds("planted", nothing, [1.0], 1e-9, Float64) isa Symbol),
    ("value lane", () -> value_agrees([1.0, 2.0], [1.0, 3.0], 1e-9) === false),
    ("value lane (agrees)", () -> value_agrees([1.0, 2.0], [1.0, 2.0], 1e-9) === true),
    ("value lane (throws)", () -> value_agrees(nothing, [1.0], 1e-9) isa Symbol),
    # The PROPERTY lanes. An earlier extension's docstring claimed to cover them and covered only the
    # relations and value lanes — which is why `serial == threaded` kept the NaN comparison every other
    # reproducibility check in the suite had been fixed for.
    ("invariance lane", () -> results_identical([1.0], [2.0]) === false),
    ("invariance lane (NaN)", () -> results_identical([NaN], [NaN]) === true),
    ("representation lane", () -> representations_agree([1.0, 2.0], [1.0, 3.0], 1e-9) === false),
    ("representation lane (throws)", () -> representations_agree(nothing, [1.0], 1e-9) isa Symbol),
    # The determinism check chooses between `reproduces` and `approximates` at runtime, so the two must
    # accept the same SHAPES or the choice silently changes the question. They did not: `isequal`
    # recurses into a tuple and `isapprox` has no method for one, so the tuple-returning radial
    # reductions — the atomic family the tolerance branch exists for — threw on it while passing the
    # bitwise branch, and a swallowed exception reported them reproducible. This probe drives BOTH
    # branches over a tuple, which is the shape that was unreachable for one of them.
    ("determinism (tuple, exact)", () -> reproduces(([1.0], [2.0]), ([1.0], [3.0])) === false),
    ("determinism (tuple, tolerance)", () -> approximates(([1.0], [2.0]), ([1.0], [3.0]); rtol = 1e-10) === false),
    ("determinism (tuple, agrees)", () -> approximates(([1.0], [2.0]), ([1.0], [2.0]); rtol = 1e-10) === true),
    ("determinism (tuple, NaN)", () -> approximates(([NaN],), ([NaN],); rtol = 1e-10) === true),
  )
  for (label, probe) in lane_probes
    fired = try probe() catch; false end
    fired || Base.push!(failures, "$(label): its comparison step does not report a false triple")
    println("      ", rpad(label, 26), fired ? "fires" : "VACUOUS — accepted a false triple")
  end

  # ── class 1: the sweep must not mutate the shared pool ────────────────────────────────────────
  # The guard is the property itself: run the checks over a pool and assert every entry is bitwise
  # unchanged afterwards. A new mutable pool entry that `_refresh` does not know how to copy reopens
  # the cascade, and this is what notices.
  println("\n  THE SWEEP DOES NOT MUTATE THE SHARED POOL")
  # The sweep below executes the pool's setters, exactly as `run_check_lanes` does — and this lane runs
  # FIRST, so a leak here corrupts every other lane. That lane saves and restores; this one did not.
  entry_cutoff = threading_cutoff()
  small = canonical_pool(config)
  before = map(e -> _snapshot(e.object), small)
  work = all_invocations(small; cap = 12)
  for invocation in work.built
    try
      check_invocation!(invocation, (_, _) -> nothing, _ -> nothing)
    catch
    end
  end
  set_threading_cutoff!(entry_cutoff)
  after = map(e -> _snapshot(e.object), small)
  mutated = [small[i].label for i in eachindex(before) if !_unchanged(before[i], after[i])]
  if isempty(mutated)
    println("      ", length(work.built), " invocations left every pool entry unchanged")
  else
    Base.push!(failures, "the sweep mutated shared pool entries: " * join(mutated, ", "))
    println("      MUTATED: ", join(mutated, ", "))
  end

  # ── class 2: the destination slot must be found correctly ─────────────────────────────────────
  println("\n  THE DESTINATION SLOT IS IDENTIFIED CORRECTLY")
  vector = pool[entry("physical R=1")].object
  tensor = pool[entry("physical R=2")].object
  expectations = ((add!, Any[_refresh(field), field, field], 1, "add!(dest, a, b)"),
                  (mul!, Any[_refresh(vector), tensor, vector], 1, "mul!(C, A, B)"),
                  (map!, Any[x -> 2x, _refresh(field), field], 2, "map!(φ, dest, a)"))
  for (operation, arguments, expected, label) in expectations
    got = _destination_index(operation, arguments)
    got == expected ||
      Base.push!(failures, "$(label): destination slot read as $(got), expected $(expected)")
    println("      ", rpad(label, 22), got == expected ? "slot $(got)" : "SLOT $(got), EXPECTED $(expected)")
  end

  # ── class 3: a pool function must have exactly one meaning ────────────────────────────────────
  # `norm(x, p)` is the p-norm, so a two-input `map!(norm, dest, A, s)` reads the second FIELD as the
  # exponent. Requiring every pool function to own exactly one method makes that unconstructible: a
  # wrong-arity call throws instead of meaning something else.
  println("\n  EVERY POOL FUNCTION HAS EXACTLY ONE METHOD")
  overloaded = String[]
  for e in pool
    e.object isa Function || continue
    count = length(methods(e.object))
    count == 1 && continue
    Base.push!(overloaded, "$(e.label) has $(count) methods")
  end
  if isempty(overloaded)
    println("      every function entry is a single-arity closure")
  else
    append!(failures, ("a pool function is overloaded, so a call can silently change meaning: " * o
                       for o in overloaded))
    for o in overloaded; println("      OVERLOADED: ", o); end
  end

  # ── class 4: NaN compares equal to itself, on BOTH branches ───────────────────────────────────
  # This is the class that recurred within one session: `isequal` fixed the bitwise branch, and the
  # tolerance branch used by device backends still needed `nans = true`. Both are asserted here so the
  # second spelling cannot come back alone.
  println("\n  NaN COMPARES EQUAL TO ITSELF ON BOTH DETERMINISM BRANCHES")
  nan_field = _defect_structural(field)
  for (branch, bitwise) in (("bitwise (CPU)", true), ("tolerance (device)", false))
    found = Dict{Symbol, Vector{String}}()
    record!(k, message) = Base.push!(get!(found, k, String[]), message)
    invocation = (operation = _ -> nan_field, label = "constant NaN field",
                  arguments = Any[_refresh(field)], entries = ())
    check_invocation!(invocation, record!, _ -> nothing; bitwise_determinism = bitwise)
    spurious = haskey(found, :determinism)
    spurious && Base.push!(failures,
                           "the $(branch) branch reports a NaN-producing call as irreproducible")
    println("      ", rpad(branch, 22), spurious ? "SPURIOUS FINDING" : "clean")
  end

  println("\n", "─"^100)
  if isempty(failures)
    println("SELF-CHECK CLEAN — every check fires on its own defect, and all four harness classes hold")
  else
    println("SELF-CHECK FAILED — ", length(failures), " problems in the harness itself:")
    for f in failures; println("    ", f); end
  end
  return length(failures)
end
