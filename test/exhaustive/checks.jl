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
#   type_stability  inference reaches a concrete type — this replaced an earlier `result_type` check
#                   that compared the result against what inference promised, which `Base.return_types`
#                   makes unfalsifiable
#
# The seed is a CONFIGURATION axis, not a check here: `canonical_pool` seeds from `config.seed` so each
# configuration draws different data, and every lane reports the seed with its findings.

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
# Every array reachable from an object by walking its stored fields.
#
# This is what makes the harness see kernels, plans and multipliers at all. `_snapshot` and `_refresh`
# previously handled only sections, `PointSet` and bare arrays and returned `nothing` for everything
# else — and `_unchanged` treats `nothing` as unchanged. So a `SeparableKernel`, a
# `FieldSpectralMultipliers`, a `FieldTransformPlans` or a `Broadcasted` was never watched for
# mutation, never refreshed between invocations, and never compared for determinism. That is not
# hypothetical: `translation_kernel!` mutates a `SeparableKernel` in place, the engine builds it from
# the shared pool, and the rewritten kernel was then read by every later cell in that configuration.
function _array_leaves(x, found = Any[], seen = Base.IdSet{Any}())
  x === nothing && return found
  x in seen && return found
  x isa AbstractArray && return (Base.push!(found, x); found)
  (x isa Symbol || x isa AbstractString || x isa Function) && return found
  # A transform library's PLAN is the library's state, not the package's: CUDA.jl's inverse real plan
  # carries a `buffer` it overwrites on every execution, to spare the c2r transform's input. Watching
  # it reported every `to_physical`, `radial_correlation` and `NUFFT` call on a device as modifying its
  # plans argument (102 cells in one configuration), and FFTW's plans hold no arrays, which is why the
  # host never showed it.
  x isa GBGI.Fields.AbstractFFTs.Plan && return found
  # And the package's own transform plans hold nothing but those library plans and `component_scratch`,
  # the documented component-sized buffer a device grid with misaligned component offsets transforms
  # through: overwriting it is its purpose. Watched, every transform on the odd grid read as modifying
  # its plans (111 cells across four device configurations).
  x isa FieldTransformPlans && return found
  # A NUMBER, TYPE or TUPLE is a comparable leaf in its own right. Collecting only arrays left
  # `Grid3D`, `RealFourierLayout` and a bare `Type` with no leaves at all — `isstructtype` excludes
  # `Tuple`, so the recursion stopped immediately — which made determinism and finiteness vacuous for
  # every accessor returning one.
  (x isa Number || x isa Type) && return (Base.push!(found, x); found)
  x isa Tuple && return (foreach(element -> _array_leaves(element, found, seen), x); found)
  isstructtype(typeof(x)) || return found
  Base.push!(seen, x)
  for name in fieldnames(typeof(x))
    isdefined(x, name) || continue
    _array_leaves(getfield(x, name), found, seen)
  end
  return found
end


function _refresh(x)
  if x isa GBGI.Fields.AbstractField
    fresh = similar_field(x, Val(field_tensor_order(x)))
    copyto!(field_data(fresh), field_data(x))
    return fresh
  end
  if x isa AbstractPointValues
    data = copy(point_values(x))
    order = point_value_tensor_order(x)
    return order == 0 ? ScalarPointValues(data) :
           order == 1 ? VectorPointValues(data) : TensorPointValues{2}(data)
  end
  x isa PointSet && return PointSet(copy(point_positions(x)))
  x isa AbstractArray && return copy(x)
  # Anything else that OWNS arrays — a kernel, a multipliers object — is deep-copied so an in-place
  # operation cannot reach the shared pool through it. Plans are excluded: they wrap FFTW plan objects
  # that do not survive `deepcopy`, and they are covered by the sequence lane's plan-reuse check.
  if !(x isa FieldTransformPlans) && !isempty(_array_leaves(x))
    return try deepcopy(x) catch; x end
  end
  return x
end


# A snapshot deep enough to detect mutation through any storage a section owns.
function _snapshot(x)
  x isa GBGI.FiberSections.AbstractFiberSection && return copy(Array(field_data(x)))
  x isa PointSet && return copy(Array(point_positions(x)))
  x isa AbstractArray && return copy(Array(x))
  # Everything else by its array leaves, so a kernel's per-axis factors and a multipliers object's
  # wavenumber arrays are watched too.
  leaves = _array_leaves(x)
  isempty(leaves) && return nothing
  return [_leaf_value(leaf) for leaf in leaves]
end

# `isequal`, not `==`: the determinism branches were fixed for this NaN trap and the mutation check
# was left behind, so a NaN surviving a call unchanged read as "modified".
_unchanged(before, after) = before === nothing || after === nothing || reproduces(before, after)

_finite(x) =
  x isa Number                          ? isfinite(x) :
  (!(x isa AbstractArray) && !(x isa Tuple) &&
   !(x isa GBGI.FiberSections.AbstractFiberSection) &&
   !isempty(_array_leaves(x)))          ? all(_finite_leaf, _array_leaves(x)) :
  x isa AbstractArray                   ? all(isfinite, x) :
  x isa GBGI.FiberSections.AbstractFiberSection ? all(isfinite, Array(field_data(x))) :
  x isa Tuple                           ? all(_finite, x) : true

# A leaf is an array, a number or a type; each needs its own comparable and finiteness form.
_leaf_value(l) = l isa AbstractArray ? copy(Array(l)) : l

# The floating-point type a comparable result is computed in: its first real number or real array
# element type, `Float64` when it holds none (an integer index, a flag), so `_value_tolerance` applies
# the precision the operation actually ran at.
_result_precision(x::AbstractFloat) = typeof(x)
_result_precision(x::Complex{<:AbstractFloat}) = real(typeof(x))
_result_precision(x::AbstractArray{<:Union{AbstractFloat, Complex{<:AbstractFloat}}}) = real(eltype(x))
# A container of mixed leaves — the field list `_comparable` builds for a kernel or a point set — takes
# the narrowest precision any leaf carries, so one `Float32` array among integers sets the tolerance.
function _result_precision(x::Union{AbstractArray, Tuple})
  narrower = filter(!=(Float64), Any[_result_precision(element) for element in x])
  return isempty(narrower) ? Float64 : first(narrower)
end
_result_precision(x) = Float64
_finite_leaf(l) = l isa AbstractArray ? all(isfinite, Array(l)) : (l isa Number ? isfinite(l) : true)


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
      method.module in package_modules() || continue
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
const UNINITIALIZED_ALLOCATORS = (:similar_field, :similar_point_values)
_returns_uninitialized(invocation) = nameof(invocation.operation) in UNINITIALIZED_ALLOCATORS

# Operations whose output is NOT bounded by their input, so "finite in, finite out" is not a property
# they have. The exponential kernel applies exp(c·|k|²): with a positive c the exponent reaches ~96 on
# an 8³ grid and overflows Float32 by arithmetic, not by defect. This produced 192 structural findings
# and, through NaN, 100 determinism ones — every one of them the pool handing a growth coefficient to
# an operation documented for decay.
# Division by the pool's zero is arithmetic, not a defect — the same class as the exponential kernel's
# overflow. `/` and `divide!` join the list now that a zero is in the pool so invariant 10's overwrite
# branch is reachable; naming only the verb "divide" missed the operator and produced 960 cells.
const UNBOUNDED_OUTPUT = (:exponential_convolve, :exponential_convolve!, :/, :divide!,
                          # `radial_kernel` stores a user-supplied symbol LAZILY and evaluates nothing
                          # at construction, so the finiteness of its result is not defined until the
                          # kernel is applied — and the symbol is a caller's arbitrary real function,
                          # free to be unbounded. Its σ slot is untyped, so the engine also fills it
                          # with objects that are not callable at all; the resulting kernel carries
                          # their uninitialized scratch, which reads as non-finite at random.
                          # The package question this raises — whether the constructor should reject a
                          # non-callable symbol instead of deferring the failure to use — is a package
                          # finding, recorded rather than fixed here.
                          :radial_kernel)

# Operations allowed to return a non-finite value from finite input, because they divide by something
# the pool is permitted to make zero: the inverse Laplacian's zero mode, division, and kernel inversion.
# EXACT names. As a substring test, `"inv"` matched — and so exempted — anything merely containing it.
const FINITENESS_EXEMPT = (:inverse_laplacian, :inverse_laplacian!, :divide, :divide!, :/, :inv)

# The finiteness scan asks whether a computation turned finite INPUT into non-finite OUTPUT. Some
# returned objects carry a non-finite number that is a SETTING rather than a result:
# `FieldTransformPlans` stores `fft_timelimit = Inf`, FFTW's spelling of "search without a time
# limit", so every `adapt(Array, plans)` was reported as producing a non-finite value (288 cells on
# the 2026-08-17 run). Excluding the type is honest where excluding the operation would not be: the
# object contains no field data at all, so there is nothing for this check to be right about.
_carries_only_settings(value) = value isa GBGPeriodicFields.Fields.FieldTransformPlans

# Operations whose second identical call cannot succeed because the FIRST changed external state:
# writing into an HDF5 file throws on a duplicate name, and the pool holds one name and one shared
# handle. The repeat therefore threw, the comparison was skipped, and the cell was counted as checked
# anyway.
# The comment here named `create_group` while the tuple did not contain it, and `setindex!` — the
# dataset write that IS in the pool — was missing from both. Recording a throwing second call as a
# finding rather than discarding it is what surfaced that: it is a genuine external effect, not a
# reproducibility defect, and this list is where that is declared.
# The operations whose summation order is genuinely nondeterministic: the two Atomix accumulators. Their
# repeat is compared to a tolerance rather than bitwise, which is a documented 2-3 ulp on `anterpolate!`.
const NONDETERMINISTIC_SUMMATION = (:anterpolate, :anterpolate!, :radial_spectrum, :radial_correlation)

const EXTERNAL_EFFECT = (:write_field, :write_points, :setindex!)

# Matching on the NAME alone was over-broad. `setindex!` is both the HDF5 dataset write — whose second
# identical call throws on a duplicate name, which is why the name is listed — and the package's own
# element assignment on a field, which is perfectly deterministic. A bare-name gate cannot tell them
# apart, so it silently exempted every field element assignment from the determinism check as well.
# The discriminator is the ARGUMENT: an external effect is one reaching outside the process, and here
# that means an HDF5 handle. (`create_group` was also listed and is inert — the extension calls it but
# owns no method for it, so it can never be an operation under test — so it is dropped rather than left
# as decoration.)
# By module NAME, so this does not require `HDF5` to be in scope: the suite runs from environments that
# do not have it, and the persistence pool is simply absent there.
_touches_external_store(x) = nameof(parentmodule(typeof(x))) === :HDF5
function _has_external_effect(invocation)
  nameof(invocation.operation) in EXTERNAL_EFFECT || return false
  nameof(invocation.operation) === :setindex! || return true
  return any(_touches_external_store, invocation.arguments)
end
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
  # Character-indexed. `text` is an inferred type name and routinely contains `⋆`, `×`, `⋅` or Unicode
  # type parameters; byte-slicing at 107 throws `StringIndexError` mid-message, and the throw happens
  # inside the per-cell handler, so the FINDING is lost and reappears as an anonymous lane error.
  return length(text) <= 110 ? text : String(first(text, 107)) * "..."
end

# Inference is the expensive part of the sweep, and the same (operation, argument types) pair recurs
# thousands of times across the product.
const _RETURN_TYPE_CACHE = Dict{Any, Any}()
# A `Type` ARGUMENT specializes as `Type{X}`, and querying it as `typeof(X) === DataType` asks a
# different and much weaker question. It cost 2880 cells on the 2026-08-17 run: every
# `adapt_structure(Array, …)` was reported as inferring `Any`, because with the adaptor typed
# `DataType` inference genuinely cannot know WHICH adaptor and `Any` is the correct answer. A real
# call site passes `Array` as `Type{Array}` and infers concretely — verified against both layers:
# `Base.return_types(adapt_structure, (Type{Array}, ScalarPointValues))` gives
# `ScalarPointValues{Float64, Vector{Float64}}`. Asking about the type actually dispatched on is not a
# widening of the check; it is the check the operation deserves.
#
# A call with keywords is inferred through `Core.kwcall`, the entry a keyword call lowers to: asking about
# the positional signature alone would infer the method called WITHOUT them, which for a required
# keyword is a call that provably throws.
function _inferred_type(operation, arguments, keywords = (;))
  key = (operation, map(a -> a isa Type ? Type{a} : typeof(a), arguments), typeof(keywords))
  return get!(_RETURN_TYPE_CACHE, key) do
    try
      isempty(keywords) ? only(Base.return_types(operation, Tuple{key[2]...})) :
        only(Base.return_types(Core.kwcall, Tuple{key[3], typeof(operation), key[2]...}))
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
     invocation.operation(arguments...; invocation_keywords(invocation)...)
   catch exception
     # A missing required keyword is the HARNESS's omission, not a refusal by the package: rethrown so
     # the lane counts it as a harness error by name instead of skipping the call as inapplicable.
     exception isa UndefKeywordError && rethrow()
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
       # BOTH in-place transforms. Invariant 11 states the contract as a pair — "never rely on a `!`
       # transform's source" — and exempting only `to_physical!` would report a backend whose forward
       # r2c consumes its input as a package defect. An earlier edit intended this and did not land.
       (occursin("to_physical", invocation.label) ||
        occursin("to_spectral", invocation.label)) && continue
       # `point_traversal_order!(traversal, grid, points, scratch)` writes its histogram into the
       # scratch by contract (decision 80: the scratch is the workspace the allocating form would have
       # allocated), so slot 4 changing is the operation, not a corruption. Only that slot, only there.
       (occursin("point_traversal_order!", invocation.label) && index == 4) && continue
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
   # exemptions are the inverse Laplacian's zero mode, and division and kernel inversion, both of which
   # divide by a value the pool is allowed to make zero. An earlier version of this comment claimed the
   # opposite of the code beneath it.
   #
   # Matched by EXACT NAME, via `FINITENESS_EXEMPT`. It was `occursin("inv", label)`, which subsumes the
   # `inverse_laplacian` clause beside it and exempts any operation whose name merely contains those
   # three letters. Worth recording how long that survived: two consecutive commit messages announced
   # this fix — the second one asserting it had been "verified in the file, not in the message" — while
   # the line went untouched both times. A claim in a commit message is not a fix, and a reviewer
   # diffing the hunks is what caught it.
   if !_returns_uninitialized(invocation) && !_unbounded_output(invocation)
     count!(:structural)
     if !_finite(result) && !(nameof(invocation.operation) in FINITENESS_EXEMPT) &&
        !_carries_only_settings(result)
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
   # A setter has no section argument, so `_destination_index` falls back to slot 1 — the input
   # integer, not the global it mutates — and the in-place branch would compare an untouched scalar
   # with itself. The value lane checks both setters properly through their getters.
   # A destination is any argument the harness can SNAPSHOT — a section or a kernel — not only a
   # section. Requiring a `FiberSection` also excluded `translation_kernel!`, whose destination is slot
   # 1 and is a `SeparableKernel`, removing its only determinism coverage in the suite.
   _comparable_destination = _is_inplace(invocation) &&
     any(a -> _snapshot(a) !== nothing, arguments)
   if !_returns_uninitialized(invocation) && !_has_external_effect(invocation) &&
      (!_is_inplace(invocation) || _comparable_destination)
     # In-place forms too. Gating this on `!_is_inplace` excluded `anterpolate!` — the Atomix scatter
     # whose nondeterministic summation order is the entire reason the tolerance branch and the
     # depth-4 atomic detection exist. For an in-place call the comparable result is the DESTINATION
     # after a second run from identically refreshed arguments.
     repeat = if _is_inplace(invocation)
       second = Any[]
       local_seen = IdDict()
       for original in invocation.arguments
         Base.push!(second, get!(() -> _refresh(original), local_seen, original))
       end
       try
         invocation.operation(second...; invocation_keywords(invocation)...)
         second[_destination_index(invocation.operation, second)]
       catch exception
         exception
       end
     else
       try invocation.operation(arguments...; invocation_keywords(invocation)...) catch exception; exception end
     end
     # A call that SUCCEEDED once and throws on an identical second call is the strongest reproducibility
     # failure the lane can observe, and it was being discarded as "not applicable". The operations with a
     # legitimate reason — an external effect the first call already performed — are excluded above.
     if repeat isa Exception
       count!(:determinism)
       record!(:determinism, "$(invocation.label) succeeded once and then threw " *
                             "$(nameof(typeof(repeat))) on an identical second call")
       repeat = nothing
     end
     if repeat !== nothing
       # Counted HERE, once the repeat has succeeded and a comparison will actually happen. Counting
       # before it meant a cell whose second call threw was reported as checked.
       count!(:determinism)
       # Bitwise on CPU, where the package guarantees it. A DEVICE reduction is not bitwise
       # reproducible across launches — measured at 1 ulp for the R=2 `inner`, which is the parallel
       # summation order, not a defect — and the package's own position is that tolerances hold for
       # cross-backend comparisons. Demanding bitwise there reports the hardware as broken.
       # EXACT NAMES. This was the last substring gate in the file, and it matched `radial_kernel` —
       # a lazy closure wrapper with no atomics anywhere — pushing it off the strict bitwise branch onto
       # the tolerance one for no reason. The same class was converted to exact names for
       # `FINITENESS_EXEMPT`, `UNBOUNDED_OUTPUT` and `EXTERNAL_EFFECT`; this site was missed each time.
       atomic = nameof(invocation.operation) in NONDETERMINISTIC_SUMMATION
       exact = bitwise_determinism && !atomic
       same = comparison_outcome() do
         first_result = _is_inplace(invocation) ?
           arguments[_destination_index(invocation.operation, arguments)] : result
         a, b = _comparable(first_result), _comparable(repeat)
         # `isequal`, not `==`: NaN != NaN, so any call that legitimately produces a NaN reported
         # itself as non-reproducible. `isequal` is the bitwise question actually being asked.
         # `approximates`, not `isapprox`: the tolerance branch must accept every shape the bitwise
         # branch does, and `isapprox` has no `Tuple` method, so the tuple-returning radial reductions
         # — which are exactly the atomic family this branch exists for — threw here.
         # The tolerance tracks the result's PRECISION. A fixed `1e-10` sits a thousand times below
         # `Float32`'s own resolution, so on a device every `Float32` atomic reduction and the R=2 `dot`
         # read as irreproducible (96 cells in one configuration) where `Float64` passed — the summation
         # order differing by launch, which this branch exists to allow.
         a === nothing ? true :
           (exact ? reproduces(a, b) : approximates(a, b; rtol = _value_tolerance(_result_precision(a))))
       end
       same isa Symbol && (record!(:determinism,
         "$(invocation.label) — the reproducibility comparison threw $(same)"); same = true)
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
   inferred = _inferred_type(invocation.operation, arguments, invocation_keywords(invocation))
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
  # BOTH setters, not just the cutoff. The pool holds integers, so the sweep executes
  # `set_fft_threads!(1)` too, and FFTW bakes its thread count into every plan built afterwards. The
  # comment above claimed both were put back; only one was.
  entry_fft_threads = max(1, Threads.nthreads())
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
  set_fft_threads!(entry_fft_threads)
  return (findings = findings, attempted = attempted, live = live, lane_errors = lane_errors,
          built = length(work.built), unbuildable = work.unbuildable,
          hook_extended = work.hook_extended,
          dropped = work.dropped, oversized = work.oversized, unfillable = work.unfillable,
          operations = length(work.operations),
          configuration = configuration_name)
end


_comparable(x) =
  x isa Number                                  ? x :
  (!(x isa AbstractArray) && !(x isa Tuple) &&
   !(x isa GBGI.FiberSections.AbstractFiberSection) &&
   !isempty(_array_leaves(x)))                  ? [_leaf_value(l) for l in _array_leaves(x)] :
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
  built = live = dropped = oversized = unfillable = unbuilt_pools = 0
  lane_errors = Dict{String, Int}()
  unbuildable = Symbol[]
  hook_extended = Symbol[]
  operations = 0
  for config in configs, (backend_name, device) in backends
    pool = try
      canonical_pool(config; device = device)
    catch exception
      # COUNTED, not merely logged. This is the same silent-drop class already closed for `dropped`,
      # `oversized` and `unfillable`, left open in the one place that removes a whole (configuration,
      # backend) pair rather than a single method — and a mixed-backend pool failure is an anticipated
      # risk here, not a theoretical one. Untallied, an arbitrary number of configurations could fall
      # out of a sweep whose summary still reads complete.
      unbuilt_pools += 1
      println("      NOT REACHED — could not build a ", backend_name, " pool for ", config.name,
              ": ", nameof(typeof(exception)))
      continue
    end
    # The configuration's OWN thread setting. `config.threaded` was consulted by one lane of eleven, so
    # for this lane — and the value, relation and sequence lanes — half of the 96 configurations was
    # byte-identical work presented as a crossed axis.
    entry = threading_cutoff()
    set_threading_cutoff!(config.threaded ? 1 : typemax(Int))
    result = try
      run_check_lanes(pool; configuration_name = "$(config.name)/$(backend_name)",
                      bitwise_determinism = backend_name == "cpu")
    finally
      set_threading_cutoff!(entry)
    end
    built += result.built
    live += result.live
    dropped += result.dropped
    oversized += result.oversized
    unfillable += result.unfillable
    operations = result.operations
    # Accumulated, not overwritten: assigning per configuration left the printed NOT REACHED list
    # showing only whatever the last configuration happened to fail on.
    unbuildable = sort(union(unbuildable, result.unbuildable); by = String)
    hook_extended = sort(union(hook_extended, result.hook_extended); by = String)
    for (kind, messages) in result.findings
      # The BACKEND in the tag: on a device run each configuration is swept twice, and a finding
      # tagged with the configuration alone could not say which leg produced it.
      append!(get!(totals, kind, String[]), ("[$(config.name)/$(backend_name)] " * m for m in messages))
    end
    for (kind, n) in result.attempted
      attempted[kind] = get(attempted, kind, 0) + n
    end
    for (kind, n) in result.lane_errors
      lane_errors[kind] = get(lane_errors, kind, 0) + n
    end
  end

  # The pool audit, actually surfaced. It has now been unwired twice — first pushed into the pool and
  # never read, then returned and never called — which is the same defect in two spellings.
  # A THIRD spelling of the same silence: the wiring is present, but a throw returned the empty vector,
  # which is indistinguishable from "the audit ran and found nothing." An audit that cannot run must say
  # so, never print the all-clear.
  class_gaps = try
    pool_class_gaps(first(configs))
  catch exception
    println("\n  POOL CLASS AUDIT DID NOT RUN — it threw $(nameof(typeof(exception))); ",
            "its silence below is not a pass")
    nothing
  end
  if class_gaps !== nothing && !isempty(class_gaps)
    println("\n  POOL CLASS GAPS — concrete kernel/scheme classes with no pool entry: ",
            join(String.(class_gaps), ", "))
  end

  println("\n  ", operations, " public operations · ", length(unbuildable), " with no buildable call")
  isempty(unbuildable) ||
    println("      NOT REACHED: ", join(String.(unbuildable), ", "))
  # Distinct from a hole in the pool: the package defines no method for these at all. It extends the
  # HOOK they dispatch through, so they are covered wherever that hook is, and counting them as
  # unreachable reads as a coverage gap where there is none.
  isempty(hook_extended) ||
    println("      NOT DEFINED HERE (covered through the hook they dispatch to): ",
            join(String.(hook_extended), ", "))
  println("  ", built, " invocations built over ", length(configs), " configurations · ",
          live, " returned a value and were checked")
  dropped == 0 ||
    println("  ", dropped, " argument combinations dropped by the per-method cap — this lane is SAMPLED there")
  # Both silent drops, now printed. `oversized` was returned and never read; `unfillable` had no
  # counter at all. Either can remove a whole public method form from a sweep that reports complete.
  oversized == 0 ||
    println("  ", oversized, " methods NOT REACHED — more than 9 positional parameters")
  unfillable == 0 ||
    println("  ", unfillable, " methods NOT REACHED — a parameter slot no pool object can fill")
  unbuilt_pools == 0 ||
    println("  ", unbuilt_pools, " (configuration, backend) pairs NOT REACHED — the pool would not build")

  # A stale required-keyword entry is a harness gap of the same kind, counted with the lane's errors.
  for line in check_required_keywords()
    println("  STALE REQUIRED KEYWORD: ", line)
    lane_errors["stale required keyword"] = get(lane_errors, "stale required keyword", 0) + 1
  end

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
    # Zero cells is NOT RUN, never "clean" — the rule the property lanes already enforce and the one
    # place in the suite that did not. Three of these five are counted conditionally (`:metadata` needs
    # an allocating call returning a field sourced from a field argument), so a state where a condition
    # never fires across the whole sweep would have printed the all-clear over an empty denominator.
    println("      ", rpad(String(kind), 16), lpad(n, 7), " cells   ",
            n == 0 ? "NOT RUN — no cell was constructed for this check" :
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
  return (total, quality, built, length(unbuildable), sum(values(lane_errors); init = 0))
end
