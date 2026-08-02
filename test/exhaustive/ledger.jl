# The applicability ledger: every (operation × check-type) cell is IMPLEMENTED, or INAPPLICABLE for a
# derived reason, or a FINDING.
#
# WHY A LEDGER AT ALL. A product over arguments answers *what did we call it with* and says nothing
# about *what kind of question we asked*. Correctness, allocation, adjointness, thread-invariance and
# round-tripping are different questions about the same call, and a person writes all of them. Without
# a ledger the check-type axis is swept for whichever operations someone thought of.
#
# WHY APPLICABILITY IS DERIVED AND NOT DECLARED. "This check does not apply here" is where misses hide:
# it reads as a decision and is usually an omission. So each check type carries a PREDICATE over
# properties read out of the operation itself — its name, its method table, its lowered IR — and the
# reason a cell is inapplicable is the predicate that said so. An exemption nobody can justify
# mechanically does not exist here.
#
#   is the operation in-place?          its name ends in `!`
#   can it reject an argument?          its IR calls a `_check_*` predicate
#   is it nondeterministic?             its IR reaches Atomix
#   is it threaded?                     its IR reaches the `_assign!` primitive
#   is it linear?                       invariant 1: linear operations exist in BOTH representations,
#                                       so having methods on both field supertypes IS the declaration
#
# That last one is the ledger paying for itself. Linearity is not a label anyone maintains — it is
# already stated, exactly once, by the method set, which invariant 1 calls the spec.

using GBGPeriodicFields
using Statistics
const GBGL = GBGPeriodicFields

include("../public_surface.jl")

# The extension modules are included for the same reason the invocation engine includes them: the
# persistence pair owns no method in a package module, so a ledger that filters on those alone reports
# all four HDF5 operations as unplaceable rather than covering them.
const LEDGER_MODULES = package_modules()


# ── Properties, read out of each operation ──────────────────────────────────────────────────────

function _ledger_lookup(name::Symbol)
  for mod in (LEDGER_MODULES..., GBGPeriodicFields, Base, Statistics)
    isdefined(mod, name) || continue
    f = getfield(mod, name)
    f isa Function && return f
  end
  return nothing
end


# Every global name reachable from any method of `f`, to a bounded depth. Used to answer "does this
# operation ever reach an atomic / a compatibility check / the threading primitive", which cannot be
# read off the signature because the answer lives several calls down.
#
# DEPTH 4 IS NOT A ROUND NUMBER. A KernelAbstractions launch indirects four times before the kernel
# body — `anterpolate!` → `_anterpolate_kernel!` → `__anterpolate_kernel!` → `cpu__anterpolate_kernel!`
# → `Atomix` — so at depth 3 the scatter kernel's atomic is invisible and the operation is reported as
# deterministic. It is not: a nondeterministic summation order costs `anterpolate!` 2–3 ulp, which is
# precisely why it is tolerance-tested. A shallower walk would have silently exempted the one family
# the determinism check exists for.
function reachable_names(f::Function; depth::Int = 4)
  seen, out = Set{Function}(), Set{Symbol}()
  frontier = [f]
  for _ in 1:depth
    next = Function[]
    for g in frontier
      g in seen && continue
      push!(seen, g)
      names = Set{Symbol}()
      walk(x) = x isa GlobalRef ? push!(names, x.name) :
                x isa Expr     ? foreach(walk, x.args) : nothing
      for m in methods(g)
        m.module in LEDGER_MODULES || continue
        ci = try Base.uncompressed_ast(m) catch; continue end
        foreach(walk, ci.code)
      end
      union!(out, names)
      for n in names
        h = _ledger_lookup(n)
        h === nothing || push!(next, h)
      end
    end
    frontier = next
  end
  return out
end


"""
    operation_properties(name) -> NamedTuple

The facts about one operation that decide which checks apply to it, each read from the code.
"""
function operation_properties(name::Symbol)
  f = _ledger_lookup(name)
  f === nothing && return nothing
  text = String(name)
  ms = [m for m in methods(f) if m.module in LEDGER_MODULES]
  isempty(ms) && return nothing
  signatures = [m.sig for m in ms]
  # `typeintersect`, not `T <: p`. The subtype spelling asks whether the PARAMETER is a supertype of
  # `AbstractFieldPhysical`, which holds only for a method written with the bare abstract type. Most of
  # the generated surface is spelled on parameterized concrete types — `transpose!(d::TensorFieldPhysical{T},
  # …)` — and `unwrap_unionall` leaves free TypeVars, so the test was false for `transpose!`, `tr!`,
  # `sym!`, `skew!`, `dev!`, `mul!`, `det!` and `norm!`. All eight read as accepting NEITHER
  # representation and were exempted from the representation and absence checks with the reason "no
  # representation asymmetry" — including `det!` and `norm!`, the two operations invariant 1's rule is
  # canonically about. The question is whether any physical field can satisfy the parameter, which is
  # an intersection, not a subtype relation.
  accepts(T) = any(signature -> any(parameter -> parameter isa Type && parameter !== Any &&
                                                 typeintersect(T, parameter) !== Union{},
                                    Base.unwrap_unionall(signature).parameters[2:end]), signatures)
  reachable = reachable_names(f)
  # What the operation RETURNS, by inference over its own method signatures. This is what separates the
  # checks that only make sense for an ordered result (sign, definiteness, bounds) from those that only
  # make sense for a section (realness, finiteness, zero pattern) — without either being declared.
  returns = Type[]
  inference_failures = 0
  for m in ms
    try
      append!(returns, Base.return_types(f, Base.tuple_type_tail(Base.unwrap_unionall(m.sig))))
    catch
      # COUNTED. `returns` drives whether the ordered-result and section-result checks are considered
      # applicable at all, so a silently dropped method can mark a check inapplicable for an operation
      # that needs it — and can manufacture a "the ledger and a lane disagree" guard violation out of an
      # introspection gap rather than a real contradiction. The count travels with the row so the
      # applicability verdict can be read against how complete the inference behind it was.
      inference_failures += 1
    end
  end
  return (name        = name,
          inference_failures = inference_failures,
          inplace     = endswith(text, "!"),
          returns_real    = any(R -> R <: Real, returns),
          returns_section = any(R -> R <: GBGL.FiberSections.AbstractFiberSection, returns),
          # An `f`/`f!` pair: the sibling exists as a package-owned generic.
          has_sibling = _ledger_lookup(Symbol(endswith(text, "!") ? text[1:end-1] : text * "!")) !== nothing,
          physical    = accepts(GBGL.Fields.AbstractFieldPhysical),
          spectral    = accepts(GBGL.Fields.AbstractFieldSpectral),
          pointvalues = accepts(GBGL.Points.AbstractPointValues),
          validates   = any(n -> startswith(String(n), "_check_"), reachable),
          atomic      = any(n -> occursin(r"^(atomic|Atomix)", String(n)), reachable),
          # THREE ROUTES, not one. `_assign!` and the two fiberwise executors are the broadcast and
          # fiberwise routes, but decision 40 gave the spectral one-pass operators a GATED CPU LOOP that
          # the `with_threading` override reaches directly — `helmholtz_projection!` is the instance —
          # and it calls none of those three. Deriving "threaded" from that list alone declared thread
          # invariance inapplicable to an operation whose invariance a lane then asserted, which is the
          # disagreement the second-order guard exists to surface, and it surfaced exactly this one.
          threaded    = any(n -> String(n) in ("_assign!", "_fiberwise_pass!", "_map_pass!",
                                               "_foreach_outer_slab"), reachable),
          serializes  = occursin(r"^(write|read)_", text),
          nmethods    = length(ms))
end


# Invariant 1 in the direction it actually holds. An operation carrying methods in BOTH representations
# is linear in the field — that is what makes both valid — so the method set states linearity and this
# reads it back. The CONVERSE is false and must not be assumed: `convolve` is linear yet spectral-only,
# because its physical form is an integral rather than a pointwise formula. So this name says what it
# derives, and the checks that need genuine linearity (adjointness) take their domain from the declared
# relations below instead of inverting an implication that does not invert.
both_representations(p) = p.physical && p.spectral


# ── The declared relations ──────────────────────────────────────────────────────────────────────
#
# Adjointness, algebraic identity and round-tripping constrain TWO operations, so they are not
# properties of one and cannot come from a per-operation product. Each entry names the operations it
# constrains, and the ledger reports an operation constrained by NOTHING rather than assuming it fine —
# which is the point: a relation table is content, and a gap in it must look like a gap.
const RELATIONS = (
  (kind = :adjoint,    name = "⟨∇·u, φ⟩ = −⟨u, ∇φ⟩",              ops = (:divergence, :gradient)),
  (kind = :adjoint,    name = "curl is self-adjoint",              ops = (:curl,)),
  (kind = :adjoint,    name = "Δ is self-adjoint, negative-definite", ops = (:laplacian,)),
  (kind = :adjoint,    name = "M⟨Wf, q⟩ = N⟨f, Wᵀq⟩",              ops = (:interpolate, :anterpolate)),
  (kind = :adjoint,    name = "ℙ is self-adjoint",                 ops = (:helmholtz_projection,)),
  (kind = :adjoint,    name = "⟨f, w·g⟩ symmetric in f, g",        ops = (:weighted_inner, :inner)),
  (kind = :identity,   name = "∇·(∇×u) = 0",                       ops = (:divergence, :curl)),
  (kind = :identity,   name = "∇×(∇φ) = 0",                        ops = (:curl, :gradient)),
  (kind = :identity,   name = "sym + skew = id",                   ops = (:sym, :skew)),
  (kind = :identity,   name = "ℙ² = ℙ",                            ops = (:helmholtz_projection,)),
  (kind = :identity,   name = "symmetric_gradient = sym∘gradient", ops = (:symmetric_gradient, :sym, :gradient)),
  (kind = :identity,   name = "det(AB) = det(A)det(B)",            ops = (:det, :mul!)),
  (kind = :identity,   name = "tr(dev A) = 0",                     ops = (:tr, :dev)),
  (kind = :identity,   name = "Δ⁻¹Δ = id on mean-free fields",     ops = (:laplacian, :inverse_laplacian)),
  (kind = :identity,   name = "sum(radial_spectrum) = inner",      ops = (:radial_spectrum, :inner)),
  (kind = :identity,   name = "C(0) = inner",                      ops = (:radial_correlation, :inner)),
  (kind = :identity,   name = "cutoff is idempotent",              ops = (:spectral_cutoff, :convolve)),
  (kind = :identity,   name = "kernel composition is associative", ops = (:convolve, :convolve!)),
  (kind = :identity,   name = "‖·‖₂² = inner(f, f)",               ops = (:l2norm, :inner)),
  (kind = :identity,   name = "integral = measure · mean",         ops = (:integral, :mean)),
  (kind = :round_trip, name = "to_physical ∘ to_spectral = id",    ops = (:to_physical, :to_spectral,
                                                                          :to_physical!, :to_spectral!)),
  (kind = :round_trip, name = "read_field ∘ write_field = id",     ops = (:read_field, :write_field)),
  (kind = :round_trip, name = "read_points ∘ write_points = id",   ops = (:read_points, :write_points)),
  (kind = :round_trip, name = "inv(k) ⋆ k = id",                   ops = (:inv, :convolve)),
  (kind = :round_trip, name = "materialize agrees with compressed", ops = (:materialize_kernel, :convolve)),
)

# ALIAS-AWARE. `⋆`, `⋅` and `×` are exported bindings of `convolve`, `dot` and `cross` — the same
# function objects — and `record_coverage!` credits every binding when one is credited. Applicability
# was resolved per NAME against a relation table that lists only the canonical spelling, so an alias
# could be credited for a kind its own rule then called inapplicable: the credit propagated and the
# lookup did not. That is not a disagreement about the operation, only about how it is spelled.
_canonical_operation(name::Symbol) =
  something(findfirst(bindings -> name in bindings, _ALIAS_NAMES), name)

relations_for(name::Symbol, kind::Symbol) =
  [r for r in RELATIONS if r.kind === kind && _canonical_operation(name) in r.ops]
constrained_by_nothing(name::Symbol) =
  isempty([r for r in RELATIONS if _canonical_operation(name) in r.ops])


# ── The check-type axis, taken from the classifier rather than listed ────────────────────────────

const CLASSIFIER_PATH = joinpath(@__DIR__, "classify_checks.jl")

"""
    check_types() -> Vector{Symbol}

The check-type axis, read out of `classify_checks.jl`.

It is parsed from the classifier rather than restated here so that the two cannot drift: the
classifier's classes are themselves derived from the assertions people have written, and a class added
there because an assertion fell through must appear in this ledger in the same run.
"""
function check_types()
  found = Symbol[]
  for line in eachline(CLASSIFIER_PATH)
    m = match(r"^\s*\(:(\w+)\s*,\s*\[", line)
    m === nothing || push!(found, Symbol(m.captures[1]))
  end
  return found
end


# ── Applicability, one predicate per check type ─────────────────────────────────────────────────
#
# Each entry answers "does this question make sense for this operation", from the properties above.
# The prose is the reason printed when a cell is inapplicable, so a skipped cell always says why.

const APPLICABILITY = Dict{Symbol, Any}(
  :correct          => (p -> (true, "")),
  :result_type      => (p -> (true, "")),
  :type_stability   => (p -> (true, "")),
  # A completeness guard asserts a property of the SUITE — that a ledger's domain is covered, that a
  # method count has not moved — so it has no per-operation cell to fill. Counting it against every
  # operation would report 108 gaps that no test could ever close.
  :completeness     => (p -> (false, "a suite-level guard, not a property of one operation")),
  # Invariant 1 makes the method set the spec, so an operation valid in ONE representation has an
  # absence to prove statically and one valid in both has none. The asymmetry is the declaration.
  :static_absence   => (p -> p.physical != p.spectral ? (true, "") :
                             (false, "no representation asymmetry, so no absence to assert")),
  :inequality       => (p -> p.returns_real ? (true, "") :
                             (false, "result is not ordered; sign and bounds do not apply")),
  :structural       => (p -> p.returns_section ? (true, "") :
                             (false, "returns no section; realness and zero pattern do not apply")),
  # In-place forms, and also the reductions: `inner`, `l2norm` and the mapped forms are pinned
  # allocation-free by invariant 13 precisely because they run in hot loops, and the property lane
  # measures them. "Not in-place" is not the same as "may allocate freely".
  :allocation       => (p -> (p.inplace || p.returns_real) ? (true, "") :
                             (false, "neither in-place nor a reduction; allocation is its purpose")),
  :element_traffic  => (p -> p.inplace ? (true, "") : (false, "not in-place; no traffic ledger applies")),
  :metadata         => (p -> !p.inplace ? (true, "") :
                             (false, "in-place; the destination already carries the metadata")),
  :domain_rejection => (p -> p.validates ? (true, "") :
                             (false, "reaches no `_check_*` predicate; it rejects nothing")),
  # `absence` and `static_absence` ask the same question — is a combination genuinely unavailable —
  # and differ only in how it is proven, by throwing versus by `hasmethod`. So they share a domain:
  # wherever invariant 1 declares an asymmetry, both are applicable.
  :absence          => (p -> p.physical != p.spectral ? (true, "") :
                             (false, "no representation asymmetry, so no absence to assert")),
  :representation   => (p -> both_representations(p) ? (true, "") :
                             (false, "not valid in both representations, so there is nothing to agree")),
  :invariance       => (p -> p.threaded ? (true, "") :
                             (false, "does not reach the threading primitive")),
  # Reproducibility applies to EVERY value-returning operation; atomicity decides whether the
  # comparison is bitwise or to a tolerance, not whether the question is asked. Restricting the domain
  # to atomic operations put the ledger in contradiction with the universal check, which runs
  # determinism on everything — and the second-order guard is what surfaced it, 66 times.
  :determinism      => (p -> (true, "")),
  :schema_presence  => (p -> p.serializes ? (true, "") : (false, "does not serialize")),
  # The three relational checks take their domain from the declared relation table, because each
  # constrains a PAIR and no property of one operation can say whether a partner exists.
  :adjoint          => (p -> isempty(relations_for(p.name, :adjoint)) ?
                             (false, "no declared adjoint partner") : (true, "")),
  :identity         => (p -> isempty(relations_for(p.name, :identity)) ?
                             (false, "constrained by no declared identity") : (true, "")),
  :round_trip       => (p -> isempty(relations_for(p.name, :round_trip)) ?
                             (false, "no declared inverse") : (true, "")),
)


# ── What is implemented, read out of the test suite ──────────────────────────────────────────────
#
# An operation is covered for a check type when an assertion of that type mentions it. Attribution is
# by mention, which can over-credit: a line asserting one thing while naming another counts for both.
# That bias is stated in the report rather than corrected, because the alternative — attributing by
# hand — is the listing this whole file exists to avoid.

const CLASSIFIER_CLASSES = Ref{Any}(nothing)

function classifier_classes()
  CLASSIFIER_CLASSES[] === nothing || return CLASSIFIER_CLASSES[]
  classes = Tuple{Symbol, Vector{Regex}}[]
  source = read(CLASSIFIER_PATH, String)
  block = match(r"const CLASSES = \[(.*?)\n\]"s, source)
  if block !== nothing
    # Split on the class-opening marker instead of matching to the first `])`. The lazy form stopped
    # inside `[-=!<>])` — a character class in the :inequality patterns — so that class parsed to an
    # unterminated fragment, yielded no patterns, and was dropped. Its assertions then fell through to
    # the `:correct` catch-all, inflating correctness coverage, while `check_types()` (a different
    # parser of the same file) still reported 19 classes. Two derivations of one axis disagreeing.
    for entry in eachmatch(r"\(:(\w+)\s*,\s*\[((?:[^\[\]]|\[[^\]]*\])*)\]\)"s, block.captures[1])
      patterns = Regex[]
      for raw in eachmatch(r"r\"((?:[^\"\\]|\\.)*)\"", entry.captures[2])
        try push!(patterns, Regex(raw.captures[1])) catch end
      end
      isempty(patterns) || push!(classes, (Symbol(entry.captures[1]), patterns))
    end
  end
  CLASSIFIER_CLASSES[] = classes
  return classes
end


function _test_files()
  files = String[]
  root = joinpath(@__DIR__, "..")
  for entry in sort(readdir(root; join = true))
    endswith(entry, ".jl") && push!(files, entry)
  end
  gpu = joinpath(root, "gpu")
  isdir(gpu) && for entry in sort(readdir(gpu; join = true))
    endswith(entry, ".jl") && push!(files, entry)
  end
  # The exhaustive lanes assert too, and they are where the relations, the value oracles and the
  # representation/invariance/allocation/ordering/rejection checks now live. Scanning only `test/*.jl`
  # left the ledger reporting 564 cells as unasserted after they had been implemented — the coverage
  # number describing the suite as it was two commits earlier.
  exhaustive = joinpath(root, "exhaustive")
  isdir(exhaustive) && for entry in sort(readdir(exhaustive; join = true))
    # `runtests.jl` INCLUDED: it holds the aliasing lane's operation table and the reference lane's
    # comparison table, and neither lane calls `record_coverage!`, so excluding it made both invisible
    # to attribution by either route.
    endswith(entry, ".jl") && push!(files, entry)
  end
  return files
end


# An assertion is not always written where the operation is named. A well-factored suite wraps its
# assertions in helpers — `@alloc_below 1000 add!(d, a, b)`, `audit(op!, name, Traffic(...))` — and then
# the `@test` lives in the helper's body while the operation appears only at the call site. Attributing
# coverage to lines containing `@test` therefore MISSES ENTIRE FILES, and misses them worse the better
# factored they are: it reported `test/allocations.jl`, the suite's most systematic audit, as asserting
# nothing at all.
#
# So the helpers are derived rather than assumed away: the test sources are parsed, and any macro or
# function whose body contains a `@test…` macrocall is an assertion helper. A call to one counts as an
# assertion line.
function _contains_test_macro(x)
  x isa Expr || return false
  if x.head === :macrocall && !isempty(x.args)
    head = x.args[1]
    name = head isa Symbol ? String(head) : head isa GlobalRef ? String(head.name) : ""
    startswith(name, "@test") && return true
  end
  return any(_contains_test_macro, x.args)
end

function _definition_name(call)
  call isa Symbol && return call
  call isa Expr || return nothing
  call.head in (:call, :where) && return _definition_name(call.args[1])
  return nothing
end

"""
    assertion_helpers() -> Set{String}

Names of the suite's own assertion helpers: every macro or function defined under `test/` whose body
contains a `@test…` macrocall.

Derived by parsing the sources, so a new helper is picked up without being registered anywhere.
"""
function assertion_helpers()
  helpers = Set{String}()
  function walk(x)
    x isa Expr || return
    if x.head in (:macro, :function) && length(x.args) >= 2 && _contains_test_macro(x.args[2])
      name = _definition_name(x.args[1])
      name === nothing || push!(helpers, (x.head === :macro ? "@" : "") * String(name))
    end
    foreach(walk, x.args)
  end
  for file in _test_files()
    ast = try Meta.parseall(read(file, String); filename = file) catch; continue end
    walk(ast)
  end
  return helpers
end


const HELPER_PATTERN = Ref{Union{Nothing, Regex}}(nothing)

function helper_pattern()
  HELPER_PATTERN[] === nothing || return HELPER_PATTERN[]
  helpers = sort(collect(assertion_helpers()); by = length, rev = true)
  HELPER_PATTERN[] = isempty(helpers) ? r"$^" :
    Regex(join((replace(h, "@" => "@", "!" => "\\!") for h in helpers), "|"))
  return HELPER_PATTERN[]
end

# `@test\b` does NOT match `@test_call`: `_` is a word character, so the boundary fails and every JET
# assertion in the suite was invisible to the filter. Matching the prefix without a boundary is what
# the classifier's own patterns already assume.
# A lane's comparison table is an assertion in every sense that matters — `(:cross!, cross!(...),
# ref_cross(...))` states an expected value and is checked — it simply carries no `@test` macro,
# because the lanes report rather than throw. Recognizing the table rows is what lets the ledger see
# the coverage those lanes provide.
const _LANE_ROW = r"^\s*\(:?[A-Za-z_⋅×⋆+\-*/\"][^,]*,\s*(ref_|.*\bref_)"
is_assertion_line(line) =
  occursin(r"@test|@inferred|@allocated", line) || occursin(helper_pattern(), line) ||
  occursin(_LANE_ROW, line) || occursin(r"^\s*\(\"[^\"]+\",\s*$", line)


"""
    coverage(operations) -> Dict{Tuple{Symbol, Symbol}, Vector{String}}

Map each `(operation, check-type)` to the places asserting it, by classifying every assertion in the
suite and attributing it to the operations it names.
"""
function coverage(operations)
  classes = classifier_classes()
  patterns = Dict{Symbol, Regex}()
  for op in operations
    text = String(op)
    # An operator name is punctuation, not an identifier, so a word-boundary guard would never match
    # it. Escape it and require a non-word neighbour only where one is meaningful.
    patterns[op] = occursin(r"^[A-Za-z_]", text) ?
      Regex("(?<![A-Za-z0-9_.])" * replace(text, "!" => "\\!") * "(?![A-Za-z0-9_])") :
      Regex("\\Q" * text * "\\E")
  end
  found = Dict{Tuple{Symbol, Symbol}, Vector{String}}()
  for file in _test_files()
    for (n, line) in enumerate(eachline(file))
      startswith(lstrip(line), "#") && continue          # a comment is not an assertion
      is_assertion_line(line) || continue
      class = nothing
      for (c, ps) in classes
        any(p -> occursin(p, line), ps) && (class = c; break)
      end
      class === nothing && continue
      for op in operations
        occursin(patterns[op], line) || continue
        push!(get!(found, (op, class), String[]), "$(basename(file)):$n")
      end
    end
  end
  return found
end


# ── The second-order guards ─────────────────────────────────────────────────────────────────────
#
# An exemption reason is itself checkable, and must be checked, or the ledger becomes the place misses
# hide. These are the properties under which a cell may NOT be inapplicable, each derived from the
# same facts — so a wrong exemption is caught by the code rather than by a reader's judgement.

"""
    guard_violations(properties, applicable, covered) -> Vector{String}

Contradictions between two INDEPENDENT statements about the same cell.

The four guards this replaces were tautologies. Each tested `property && !applicable[(name, check)]`
while `applicable[(name, check)]` was set from that same property — `p.inplace && !p.inplace` — so
`guard_violations` provably returned an empty vector for every possible package, and the
`ledger_violations > 0` term in the exit condition was dead with respect to exemptions. A guard whose
condition is the predicate it audits cannot audit it.

What is falsifiable is disagreement between two things derived DIFFERENTLY:

  a lane asserted a cell the ledger calls inapplicable — the applicability rule and the lane's own
  judgement contradict each other, and one of them is wrong

  an operation the IR says reaches an atomic accumulation is not covered for determinism — the
  property that made the check applicable is exactly the property that makes it necessary

  an operation valid in both representations has no representation-agreement coverage anywhere,
  despite invariant 1 making that the defining claim about it
"""
function guard_violations(properties, applicable, covered)
  violations = String[]
  for p in properties
    for (name, kind) in ((p.name, :representation), (p.name, :allocation), (p.name, :metadata),
                         (p.name, :determinism), (p.name, :correct), (p.name, :identity),
                         (p.name, :adjoint), (p.name, :round_trip), (p.name, :invariance))
      haskey(covered, (name, kind)) || continue
      applicable[(name, kind)] && continue
      push!(violations, "$(name): a lane asserts $(kind), which the ledger calls inapplicable — " *
                        "the applicability rule and the lane disagree")
    end
    if p.atomic && !haskey(covered, (p.name, :determinism))
      push!(violations, "$(p.name): reaches an atomic accumulation and nothing checks its determinism")
    end
  end
  return violations
end


# ── The lane ────────────────────────────────────────────────────────────────────────────────────

"""
    run_ledger_lane() -> (findings, violations, cells)

Report the applicability ledger: how many `(operation × check-type)` cells are covered, which are
applicable and uncovered, and which exemptions the second-order guards forbid.
"""
function run_ledger_lane()
  println("═"^100)
  println("LANE: the applicability ledger — every (operation × check-type) cell")
  println("      applicability is DERIVED from each operation's name, method table and lowered IR;")
  println("      coverage is attributed by classifying every assertion in the suite")
  println("═"^100)

  operations = sort(collect(package_operations()); by = String)
  properties = filter(!isnothing, [operation_properties(o) for o in operations])
  # An operation whose methods live in a weak-dependency extension has NO methods in a package module
  # here, so it silently leaves the denominator. Silently is the problem: the persistence pair is
  # exactly where the `schema_presence` check lives, and dropping it makes that check read as having no
  # domain rather than as unreachable in this process.
  covered_names = Set(p.name for p in properties)
  excluded = [o for o in operations if !(o in covered_names)]
  checks = check_types()
  covered = coverage(Set(p.name for p in properties))
  # Merge what the lanes recorded as they ran with what the source scan found. The scan sees the gate's
  # `@test` assertions; the registry sees this suite's own.
  for (operation, kind) in LANE_COVERAGE
    haskey(covered, (operation, kind)) || (covered[(operation, kind)] = ["exhaustive lane"])
  end

  applicable = Dict{Tuple{Symbol, Symbol}, Bool}()
  reasons = Dict{Tuple{Symbol, Symbol}, String}()
  for p in properties, c in checks
    predicate = get(APPLICABILITY, c, nothing)
    if predicate === nothing
      applicable[(p.name, c)] = true
      reasons[(p.name, c)] = ""
      continue
    end
    yes, why = predicate(p)
    applicable[(p.name, c)] = yes
    reasons[(p.name, c)] = why
  end

  # A check type in the classifier with no applicability predicate is a check the ledger cannot place.
  # It is reported rather than defaulted, because defaulting it to "applies everywhere" would bury it.
  unplaced = [c for c in checks if !haskey(APPLICABILITY, c)]

  gaps = Dict{Symbol, Vector{Symbol}}()
  cells = applied = 0
  for p in properties, c in checks
    cells += 1
    applicable[(p.name, c)] || continue
    applied += 1
    haskey(covered, (p.name, c)) && continue
    push!(get!(gaps, c, Symbol[]), p.name)
  end

  println("\n  ", length(properties), " operations × ", length(checks), " check types = ", cells, " cells")
  println("  ", applied, " applicable · ", cells - applied, " inapplicable for a derived reason · ",
          applied - sum(length(v) for v in values(gaps); init = 0), " covered")

  println("\n  COVERAGE BY CHECK TYPE")
  for c in checks
    n_applicable = count(p -> applicable[(p.name, c)], properties)
    n_covered = count(p -> applicable[(p.name, c)] && haskey(covered, (p.name, c)), properties)
    bar = n_applicable == 0 ? "—" : "$(n_covered)/$(n_applicable)"
    flag = n_applicable > 0 && n_covered == 0 ? "   ← APPLICABLE EVERYWHERE, ASSERTED NOWHERE" : ""
    println("      ", rpad(String(c), 20), lpad(bar, 9), flag)
  end

  total_gaps = sum(length(v) for v in values(gaps); init = 0)
  if total_gaps > 0
    println("\n  APPLICABLE BUT NOT ASSERTED — ", total_gaps, " cells")
    for c in checks
      list = get(gaps, c, Symbol[])
      isempty(list) && continue
      shown = join(String.(list[1:min(end, 14)]), ", ")
      println("      ", rpad(String(c), 20), length(list), "  ", shown,
              length(list) > 14 ? ", … (+$(length(list) - 14))" : "")
    end
  end

  # THE SURVEY'S OWN coverage, not the merged set. The guard asks whether a LANE asserts a kind the
  # applicability rule calls inapplicable — and the applicability rule for the relational kinds derives
  # from this survey's `RELATIONS` table, which by design names no operators. The merged `covered` also
  # carries the GATE's assertions, found by scanning `test/*.jl`, and the gate does assert identities on
  # `+`, `-`, `*` and `/`. Judging those against a rule that cannot see the gate's relation set produced
  # 84 guaranteed disagreements that said nothing about either side: the two derivations were simply
  # describing different universes. Comparing like with like leaves the guard able to catch what it is
  # for — one of THIS suite's lanes crediting a cell its own rule forbids.
  survey_covered = Dict(key => value for (key, value) in covered
                        if value == ["exhaustive lane"])
  violations = guard_violations(properties, applicable, survey_covered)
  if !isempty(violations)
    println("\n  SECOND-ORDER GUARD VIOLATIONS — an exemption the ledger's own rules forbid:")
    for v in violations; println("      ", v); end
  end

  orphans = [p.name for p in properties if constrained_by_nothing(p.name)]
  if !isempty(orphans)
    println("\n  CONSTRAINED BY NO DECLARED RELATION — ", length(orphans), " operations")
    println("      Not a defect by itself: most operations are constrained by their own oracle rather")
    println("      than by a relation to another. It is reported because a MISSING relation looks")
    println("      exactly like this, and the design requires the difference to be visible.")
    println("      ", join(String.(orphans[1:min(end, 22)]), ", "),
            length(orphans) > 22 ? ", … (+$(length(orphans) - 22))" : "")
  end

  if !isempty(unplaced)
    println("\n  CHECK TYPES WITH NO APPLICABILITY RULE — ", join(String.(unplaced), ", "))
  end

  # Inference gaps, surfaced. Every applicability verdict below rests on what `Base.return_types` could
  # be told about an operation, so a row built from incomplete inference is a verdict with a weaker
  # basis than the report otherwise implies.
  shaky = [p.name for p in properties if p.inference_failures > 0]
  if !isempty(shaky)
    println("\n  APPLICABILITY RESTS ON INCOMPLETE INFERENCE — ", length(shaky), " operations: ",
            join(String.(shaky[1:min(end, 18)]), ", "), length(shaky) > 18 ? ", …" : "")
    println("      Inference threw on at least one method signature, so the returned-type facts driving")
    println("      these rows' applicability are partial.")
  end

  if !isempty(excluded)
    println("\n  NOT REACHED — ", length(excluded), " public operations own no method in this process:")
    println("      ", join(String.(excluded), ", "))
    println("      They live in a weak-dependency extension. Load `HDF5` and rerun to place them.")
  end

  return (total_gaps, length(violations) + length(unplaced), cells)
end
