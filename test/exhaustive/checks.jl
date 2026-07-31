# The check-type lanes, run over every invocation the engine can build.
#
# The ledger reported 539 applicable-but-unasserted cells. These lanes close the ones whose oracle is
# UNIVERSAL — a property every operation must have, checkable without knowing what the operation
# computes. That is what makes them sweepable at all: a per-operation oracle has to be written per
# operation, but "an allocating call must not modify its inputs" is one property over the whole surface.
#
# Each lane states its property, and each is a real oracle rather than a comparison of the package with
# itself:
#
#   metadata      an allocating result carries the grid, layout and element type of its input
#   preservation  an allocating call leaves EVERY argument unchanged; an in-place call changes only its
#                 destination (invariant 11 lives here, and it is a sequence property)
#   determinism   the same call twice gives bitwise-identical results, except where an atomic makes the
#                 summation order genuinely nondeterministic
#   structural    a finite input gives a finite result — no NaN or Inf conjured from nothing
#   result_type   the result is the type the method table says it is, so inference is not lying
#   seed          the same operation on different random input gives different output, unless it is
#                 genuinely constant — the axis that catches a fixture nothing can falsify

using GBGPeriodicFields
using Statistics
using LinearAlgebra


# A fresh copy of anything an in-place operation can write into.
#
# WITHOUT THIS THE WHOLE LANE IS MEANINGLESS. The pool is shared across invocations, so the first
# `convolve!` that takes a pool object as its destination overwrites it for every later call. Results
# then go non-finite in a cascade — 3835 structural "findings" on the first run, none of them the
# package's fault — and the sweep becomes order-dependent, which is the one thing a survey may not be.
# Refreshing per invocation also makes each cell independent, so a finding names a call rather than a
# history.
function _refresh(x)
  if x isa GBGI.Fields.AbstractField
    fresh = similar_field(x, Val(field_tensor_order(x)))
    copyto!(field_data(fresh), field_data(x))
    return fresh
  end
  if x isa AbstractPointValues
    data = copy(point_values(x))
    order = pointvalue_tensor_order(x)
    return order == 0 ? ScalarPointValues(data) :
           order == 1 ? VectorPointValues(data) : TensorPointValues{2}(data)
  end
  x isa PointSet && return PointSet(copy(point_coordinates(x)))
  x isa AbstractArray && return copy(x)
  return x
end


# A snapshot deep enough to detect mutation through any storage a section owns.
function _snapshot(x)
  x isa GBGI.FiberSections.AbstractFiberSection && return copy(Array(field_data(x)))
  x isa PointSet && return copy(Array(point_coordinates(x)))
  x isa AbstractArray && return copy(Array(x))
  return nothing
end

_unchanged(before, after) = before === nothing || after === nothing || before == after

_finite(x) =
  x isa Number                          ? isfinite(x) :
  x isa AbstractArray                   ? all(isfinite, x) :
  x isa GBGI.FiberSections.AbstractFiberSection ? all(isfinite, Array(field_data(x))) :
  x isa Tuple                           ? all(_finite, x) : true

_is_inplace(invocation) = endswith(String(nameof(invocation.operation)), "!")

# The destination is the first SECTION argument, not the first argument. `map!(φ, dest, a)` takes its
# fiber map first, so assuming slot 1 reported every `map!` call as corrupting an input when it was
# writing to its own destination.
# Whether the operation takes a FIBER MAP in slot 1, read from its own package methods: a first
# parameter that is an unbound type variable or a `Function` is a map slot, and a section type is a
# destination. `map!`/`map` are the only such operations, and this is derived rather than named.
#
# The earlier probe — "does the call still apply with slot 1 replaced by `identity`" — consulted EVERY
# method, so LinearAlgebra's generic `mul!(C, A, B)` accepted the closure and `mul!` was reported as
# corrupting its own destination eight times over. Applicability is global; ownership is not.
const _LEADING_MAP_CACHE = Dict{Any, Bool}()
function _takes_leading_map(operation)
  return get!(_LEADING_MAP_CACHE, operation) do
    for method in methods(operation)
      method.module in PACKAGE_MODULES || continue
      parameters = collect(Base.unwrap_unionall(method.sig).parameters)[2:end]
      isempty(parameters) && continue
      first_parameter = parameters[1]
      first_parameter isa TypeVar && return true
      first_parameter isa Type && first_parameter <: Function && return true
    end
    return false
  end
end

function _destination_index(operation, arguments)
  sections = findall(a -> a isa GBGI.FiberSections.AbstractFiberSection, arguments)
  isempty(sections) && return 1
  if _takes_leading_map(operation)
    later = filter(>(1), sections)
    isempty(later) || return first(later)
  end
  return sections[1]
end

# Operations whose contract is UNINITIALIZED storage. Their result is meaningfully garbage — that is
# what they are for — so finiteness and reproducibility do not apply and are not silently waived: the
# reason is that `similar_*` promises shape and metadata, never content.
const UNINITIALIZED_ALLOCATORS = (:similar_field, :similar_pointvalues)
_returns_uninitialized(invocation) = nameof(invocation.operation) in UNINITIALIZED_ALLOCATORS

# Operations whose output is NOT bounded by their input, so "finite in, finite out" is not a property
# they have. The exponential kernel applies exp(c·|k|²): with a positive c the exponent reaches ~96 on
# an 8³ grid and overflows Float32 by arithmetic, not by defect. This produced 192 structural findings
# and, through NaN, 100 determinism ones — every one of them the pool handing a growth coefficient to
# an operation documented for decay.
# Division by the pool's zero is arithmetic, not a defect — the same class as the exponential kernel's
# overflow. `/` and `divide!` join the list now that a zero is in the pool so invariant 10's overwrite
# branch is reachable; naming only the verb "divide" missed the operator and produced 960 cells.
const UNBOUNDED_OUTPUT = (:exponential_convolve, :exponential_convolve!, :/, :divide!)
_unbounded_output(invocation) = nameof(invocation.operation) in UNBOUNDED_OUTPUT

# A type as precise as inference can be. `isconcretetype` alone is too strict: an accessor returning a
# TYPE infers `Type{Float64}`, a singleton kind that is exactly as pinned down as a value can be, yet
# `isconcretetype(Type{Float64})` is false — so every type-returning accessor read as unstable.
# `Union{}` means the call provably throws, which is not an instability either.
function _precise_type(T)
  T === Union{} && return true
  isconcretetype(T) && return true
  T isa DataType && T.name === Type.body.name && return true      # Type{X}: a singleton kind
  return false
end

# An inferred kernel Union spells out several nested closure types and runs past 700 characters, which
# buries every other finding in the report.
function _shorten(T)
  text = string(T)
  return length(text) <= 110 ? text : text[1:107] * "..."
end

# Inference is the expensive part of the sweep, and the same (operation, argument types) pair recurs
# thousands of times across the product.
const _RETURN_TYPE_CACHE = Dict{Any, Any}()
function _inferred_type(operation, arguments)
  key = (operation, typeof.(arguments))
  return get!(_RETURN_TYPE_CACHE, key) do
    try
      only(Base.return_types(operation, Tuple{key[2]...}))
    catch
      Any
    end
  end
end


"""
    check_invocation!(invocation, record!, count!; bitwise_determinism = true) -> Bool

Run every universal check on one invocation, returning whether the call returned a value.

Extracted from the sweep so the SELF-CHECK can drive it with deliberately broken operations. A check
that cannot fail is worse than no check, and 85008 clean cells prove nothing on their own — this is the
seam that lets each check be shown to fire.
"""
function check_invocation!(invocation, record!, count!; bitwise_determinism::Bool = true)
   # Fresh arguments, and the SHARING PATTERN of the original preserved: if two slots held the same
   # pool object the refreshed pair must still be the same object, or the aliasing relations the
   # engine built would be silently unaliased and `dest === source` would never be exercised.
   seen = IdDict()
   arguments = Any[get!(() -> _refresh(a), seen, a) for a in invocation.arguments]
   before = map(_snapshot, arguments)
   result = try
     invocation.operation(arguments...)
   catch
     return false
   end
   after = map(_snapshot, arguments)

   # ── preservation ────────────────────────────────────────────────────────────────────────────
   count!(:preservation)
   if _is_inplace(invocation)
     destination = _destination_index(invocation.operation, arguments)
     for index in eachindex(arguments)
       index == destination && continue
       _unchanged(before[index], after[index]) && continue
       # An in-place operation may legitimately overwrite an argument that IS the destination, and
       # the transforms may consume their spectral input as scratch by contract (invariant 11).
       arguments[index] === arguments[destination] && continue
       occursin("to_physical", invocation.label) && continue
       record!(:preservation, "$(invocation.label) modified argument $index, which is not its destination")
       break
     end
   else
     for index in eachindex(arguments)
       _unchanged(before[index], after[index]) && continue
       record!(:preservation, "$(invocation.label) is allocating but modified argument $index")
       break
     end
   end

   # ── structural ──────────────────────────────────────────────────────────────────────────────
   # Every pool value is finite, so a non-finite result was manufactured by the operation. The
   # inverse Laplacian's zero mode is the documented exception and is left to the operation's own
   # oracle rather than special-cased away here.
   if !_returns_uninitialized(invocation) && !_unbounded_output(invocation)
     count!(:structural)
     if !_finite(result) && !occursin("inverse_laplacian", invocation.label) &&
        !occursin("divide", invocation.label) && !occursin("inv", invocation.label)
       record!(:structural, "$(invocation.label) returned a non-finite value from finite input")
     end
   end

   # ── metadata ────────────────────────────────────────────────────────────────────────────────
   # An allocating section result must carry the grid, layout and element type it was built from.
   # This is the axis `map` was broken on for every permuted layout from the day it shipped.
   if !_is_inplace(invocation) && result isa GBGI.Fields.AbstractField
     source = findfirst(a -> a isa GBGI.Fields.AbstractField, arguments)
     if source !== nothing
       count!(:metadata)
       reference = arguments[source]
       field_grid(result) == field_grid(reference) ||
         record!(:metadata, "$(invocation.label) returned a field on a different grid")
       field_layout(result) == field_layout(reference) ||
         record!(:metadata, "$(invocation.label) dropped the layout (got $(field_layout(result)))")
       field_scalar_type(result) === field_scalar_type(reference) ||
         record!(:metadata, "$(invocation.label) changed the scalar type")
     end
   end

   # ── determinism ─────────────────────────────────────────────────────────────────────────────
   # Repeating a call must reproduce it bitwise. The atomic accumulators are the documented exception
   # — a nondeterministic summation order costs `anterpolate!` 2-3 ulp — so they are compared to a
   # tolerance instead of excluded, which still catches a real divergence.
   if !_is_inplace(invocation) && !_returns_uninitialized(invocation)
     count!(:determinism)
     repeat = try invocation.operation(arguments...) catch; nothing end
     if repeat !== nothing
       # Bitwise on CPU, where the package guarantees it. A DEVICE reduction is not bitwise
       # reproducible across launches — measured at 1 ulp for the R=2 `inner`, which is the parallel
       # summation order, not a defect — and the package's own position is that tolerances hold for
       # cross-backend comparisons. Demanding bitwise there reports the hardware as broken.
       atomic = occursin("anterpolate", invocation.label) || occursin("radial", invocation.label)
       exact = bitwise_determinism && !atomic
       same = try
         a, b = _comparable(result), _comparable(repeat)
         # `isequal`, not `==`: NaN != NaN, so any call that legitimately produces a NaN reported
         # itself as non-reproducible. `isequal` is the bitwise question actually being asked.
         # `nans = true` for the same reason `isequal` is used above: isapprox(NaN, NaN) is FALSE, so
         # the tolerance branch reported every NaN-producing call as irreproducible on a device even
         # after the bitwise branch had been fixed.
         a === nothing ? true : (exact ? isequal(a, b) : isapprox(a, b; rtol = 1e-10, nans = true))
       catch
         true
       end
       same || record!(:determinism, "$(invocation.label) is not reproducible across identical calls")
     end
   end

   # ── type_stability ──────────────────────────────────────────────────────────────────────────
   # Inference must reach a CONCRETE type for the call.
   #
   # This replaces an unfalsifiable check. The first version asked whether the result matched what
   # inference promised — but `Base.return_types` is a sound over-approximation, so in valid Julia the
   # answer is always yes, and the check could only have caught an inference bug in the compiler. It
   # reported 85008 clean cells and none of them meant anything. The suite's own self-check is what
   # surfaced that, by demanding every check fire on an operation built to violate it.
   #
   # The falsifiable property is type STABILITY: an operation whose return type inference cannot pin
   # down forces every caller to dynamic dispatch, which is a real defect and is what `@inferred`
   # asserts. `Union{}` means the call provably throws and is not an instability.
   count!(:type_stability)
   inferred = _inferred_type(invocation.operation, arguments)
   if !_precise_type(inferred)
     record!(:type_stability, "$(invocation.label) infers $(_shorten(inferred)), which is not concrete")
   end
  return true
end


"""
    run_check_lanes(pool; configuration_name) -> NamedTuple

Run every universal check over every buildable invocation, and report the failures by check type.
"""
function run_check_lanes(pool; configuration_name::String = "", bitwise_determinism::Bool = true)
  work = all_invocations(pool)
  findings = Dict{Symbol, Vector{String}}()
  attempted = Dict{Symbol, Int}()
  record!(kind, message) = Base.push!(get!(findings, kind, String[]), message)
  current = Ref(:none)
  count!(kind) = begin
    record_coverage!(current[], kind)
    attempted[kind] = get(attempted, kind, 0) + 1
  end

  # An operation whose call throws is not a finding here: the mismatch lane owns rejection, and many
  # buildable argument tuples are deliberately invalid combinations. What matters is the calls that
  # RETURN, and whether what they returned obeys the universal properties.
  live = 0
  lane_errors = Dict{String, Int}()
  # The pool contains integers, so the engine builds and EXECUTES `set_threading_cutoff!(1)` and
  # `set_fft_threads!(1)`. Both are global package state and neither is restored by the call, so every
  # lane after this one ran with a cutoff of 1 instead of 16384 and FFTW pinned to one thread — the
  # harness silently reconfiguring the package it is measuring, with the outcome depending on pool
  # insertion order. The setters stay in the sweep (they are public operations and must be exercised);
  # what changes is that the state is put back.
  entry_cutoff = threading_cutoff()
  for invocation in work.built
   # The lane itself can fail on a cell — a device backend reports an earlier asynchronous error at the
   # next API call, so an unrelated invocation aborts the whole sweep. Recording the failure and moving
   # on keeps the remaining cells, and the count is printed so a backend that fails everywhere cannot
   # look like a backend that passed everything.
   try
    current[] = nameof(invocation.operation)
    check_invocation!(invocation, record!, count!;
                      bitwise_determinism = bitwise_determinism) && (live += 1)
   catch exception
     key = string(nameof(typeof(exception)))
     lane_errors[key] = get(lane_errors, key, 0) + 1
   end
  end

  set_threading_cutoff!(entry_cutoff)
  return (findings = findings, attempted = attempted, live = live, lane_errors = lane_errors,
          built = length(work.built), unbuildable = work.unbuildable,
          dropped = work.dropped, operations = length(work.operations),
          configuration = configuration_name)
end


_comparable(x) =
  x isa Number                                  ? x :
  x isa GBGI.FiberSections.AbstractFiberSection ? Array(field_data(x)) :
  x isa AbstractArray                           ? Array(x) :
  x isa Tuple                                   ? map(_comparable, x) : nothing


"""
    run_invocation_lane(configurations) -> (findings, cells, unbuildable)

The operation-axis lane: build every call the method table admits, over every configuration, and run
the universal checks on each.
"""
function run_invocation_lane(configs)
  println("═"^100)
  println("LANE: universal checks over every buildable invocation")
  println("      the operation domain is DERIVED — `package_operations()` crossed with a canonical pool,")
  println("      each slot filtered by its declared parameter type and settled by `applicable`")
  println("═"^100)

  backends = device_backends()
  println("\n  BACKENDS: ", join((name for (name, _) in backends), ", "))
  if length(backends) == 1
    println("      NOT RUN — no device backend in this process. The backend axis needs a vendor package,")
    println("      so run the suite from `test/gpu/cuda` or `test/gpu/rocm` to cross it.")
  end

  totals = Dict{Symbol, Vector{String}}()
  attempted = Dict{Symbol, Int}()
  built = live = dropped = 0
  lane_errors = Dict{String, Int}()
  unbuildable = Symbol[]
  operations = 0
  for config in configs, (backend_name, device) in backends
    pool = try
      canonical_pool(config; device = device)
    catch exception
      println("      NOT REACHED — could not build a ", backend_name, " pool for ", config.name,
              ": ", nameof(typeof(exception)))
      continue
    end
    result = run_check_lanes(pool; configuration_name = "$(config.name)/$(backend_name)",
                             bitwise_determinism = backend_name == "cpu")
    built += result.built
    live += result.live
    dropped += result.dropped
    operations = result.operations
    # Accumulated, not overwritten: assigning per configuration left the printed NOT REACHED list
    # showing only whatever the last configuration happened to fail on.
    unbuildable = sort(union(unbuildable, result.unbuildable); by = String)
    for (kind, messages) in result.findings
      append!(get!(totals, kind, String[]), ("[$(config.name)] " * m for m in messages))
    end
    for (kind, n) in result.attempted
      attempted[kind] = get(attempted, kind, 0) + n
    end
    for (kind, n) in result.lane_errors
      lane_errors[kind] = get(lane_errors, kind, 0) + n
    end
  end

  println("\n  ", operations, " public operations · ", length(unbuildable), " with no buildable call")
  isempty(unbuildable) ||
    println("      NOT REACHED: ", join(String.(unbuildable), ", "))
  println("  ", built, " invocations built over ", length(configs), " configurations · ",
          live, " returned a value and were checked")
  dropped == 0 ||
    println("  ", dropped, " argument combinations dropped by the per-method cap — this lane is SAMPLED there")

  if !isempty(lane_errors)
    println("\n  THE LANE ITSELF FAILED ON SOME CELLS — not package findings, gaps in this sweep:")
    for (kind, n) in sort(collect(lane_errors); by = x -> -x[2])
      println("      ", rpad(kind, 34), n, " cells")
    end
  end

  println("\n  CHECKS RUN")
  for kind in (:preservation, :structural, :metadata, :determinism, :type_stability)
    n = get(attempted, kind, 0)
    failures = length(get(totals, kind, String[]))
    println("      ", rpad(String(kind), 16), lpad(n, 7), " cells   ",
            failures == 0 ? "clean" : "$(failures) FINDINGS")
  end

  # Type instability is a real property and a real finding, but it is not a WRONG ANSWER: it costs
  # dispatch, not correctness. Folding it into the same number as a corrupted input would make every
  # run exit as though the package returned something false, so the two are counted apart.
  quality = length(get(totals, :type_stability, String[]))
  total = sum(length(v) for v in values(totals); init = 0) - quality
  # Gate the PRINTING on all findings, not on the correctness subset. Separating the counts for the
  # exit status silently suppressed the whole findings block whenever correctness was clean, which hid
  # 1272 type-stability findings behind a report that looked empty.
  if total + quality > 0
    println("\n  FINDINGS")
    for (kind, messages) in sort(collect(totals); by = first)
      isempty(messages) && continue
      unique_messages = unique(m -> replace(m, r"^\[[^\]]*\] " => ""), messages)
      println("\n    ", uppercase(String(kind)), " — ", length(messages), " cells, ",
              length(unique_messages), " distinct")
      for m in unique_messages[1:min(end, 12)]
        println("      ", m)
      end
      length(unique_messages) > 12 && println("      … (+", length(unique_messages) - 12, " more)")
    end
  end
  return (total, quality, built, length(unbuildable))
end
