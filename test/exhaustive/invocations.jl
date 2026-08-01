# The invocation engine: build calls to every public operation MECHANICALLY, from its own method
# signatures.
#
# WHY THIS EXISTS. Every lane before it carried a hand-written entry list — 31 operations in the
# aliasing lane, 14 in the mismatch lane, 7 in the reference lane — under a design whose Axis 1 claims
# the operation domain is derived from `public_surface.jl`. That is a list where a derivation is
# claimed, the exact defect the design's own rule names, and it left 39 of 112 public operations
# (35%) exercised by nothing.
#
# HOW IT WORKS. The domain is `package_operations()`. For each operation, its package-owned methods are
# read from the method table; each parameter slot is filled from a pool of canonical objects covering
# every type the package takes; `applicable` decides which combinations are real calls. Nothing is
# listed — adding an operation to the package adds it here, and an operation the engine cannot call is
# REPORTED rather than skipped, so the remaining gap stays visible.

using GBGPeriodicFields
using Statistics
using LinearAlgebra
using Random
using InteractiveUtils

# The persistence pair lives in a weak-dependency extension, so without this the four HDF5 operations
# own no method and the suite reports them as unreachable rather than testing them.
const HDF5_AVAILABLE = try
  @eval using HDF5
  true
catch
  false
end

# The persistence methods live in the extension MODULE, which is not a package module, so filtering
# methods by `PACKAGE_MODULES` alone hid all four HDF5 operations behind "no buildable call".
const EXTENSION_MODULES = let found = Module[]
  if HDF5_AVAILABLE
    extension = Base.get_extension(GBGPeriodicFields, :GBGPeriodicFieldsHDF5Ext)
    extension === nothing || Base.push!(found, extension)
  end
  Tuple(found)
end

_owned_by_package(method) = method.module in PACKAGE_MODULES || method.module in EXTENSION_MODULES


# The storage backends this process can build a pool on. CPU is always present; a device appears only
# when its vendor package is loaded, which happens in the `test/gpu/*` environments. When one is
# absent the suite says so — the backend axis is NOT RUN, never silently dropped.
function device_backends()
  # Import the vendor package if the active project HAS it. Gating on `isdefined(Main, :CUDA)` alone
  # meant the axis could never fire: activating `test/gpu/cuda` makes CUDA *available*, not imported,
  # so the lane printed "NOT RUN — run from test/gpu/cuda" to a user who had just done that.
  for vendor in (:CUDA, :AMDGPU)
    isdefined(Main, vendor) && continue
    try
      @eval Main using $vendor
    catch
    end
  end
  backends = Any[("cpu", identity)]
  for (name, symbol, adapt) in (("cuda", :CUDA, x -> Base.invokelatest(getfield(Main, :CUDA).CuArray, x)),
                                ("rocm", :AMDGPU, x -> Base.invokelatest(getfield(Main, :AMDGPU).ROCArray, x)))
    isdefined(Main, symbol) || continue
    vendor = getfield(Main, symbol)
    functional = try Base.invokelatest(getfield(vendor, :functional)) catch; false end
    functional && Base.push!(backends, (name, adapt))
  end
  return backends
end


const GBGI = GBGPeriodicFields

# What the lanes actually assert, recorded AS THEY RUN rather than scraped from their source.
#
# The ledger's coverage attribution reads test sources and matches assertion patterns, which cannot see
# a lane whose checks are table rows rather than `@test` macros — it kept reporting 564 cells as
# unasserted after they were implemented, describing the suite as it was two commits earlier. A lane
# that knows what it checked can simply say so, and that is a derivation rather than a guess.
const LANE_COVERAGE = Set{Tuple{Symbol, Symbol}}()

# `⋅`, `×` and `⋆` are exported bindings of `dot`, `cross` and `convolve`. `package_operations()`
# carries both spellings, but every lane records coverage under `nameof(f)` — which returns the target
# name — so the glyph names could never be credited and read as permanent, uncloseable gaps. Crediting
# every binding of the same function object fixes the ledger without shrinking the domain.
const _ALIAS_NAMES = let map = Dict{Symbol, Vector{Symbol}}()
  for name in names(GBGPeriodicFields)
    isdefined(GBGPeriodicFields, name) || continue
    f = getfield(GBGPeriodicFields, name)
    f isa Function || continue
    Base.push!(get!(map, nameof(f), Symbol[]), name)
  end
  map
end

function record_coverage!(operation::Symbol, kind::Symbol)
  push!(LANE_COVERAGE, (operation, kind))
  for alias in get(_ALIAS_NAMES, operation, Symbol[])
    push!(LANE_COVERAGE, (alias, kind))
  end
  return nothing
end


# ── The canonical pool ──────────────────────────────────────────────────────────────────────────
#
# One object per type the package's signatures mention. Values are random rather than zero: a zero
# fixture cannot see a defect that scales its input, and decision 52's lesson is that a fixture unable
# to falsify the claim is not a fixture.

# Handles the pools open, so a run does not accumulate one per configuration.
const OPEN_HDF5_HANDLES = Any[]
close_pool_handles!() = (foreach(h -> (try close(h) catch end), OPEN_HDF5_HANDLES);
                         empty!(OPEN_HDF5_HANDLES); nothing)

struct PoolEntry
  label::String
  object::Any
end


_concrete_subtypes(T) = isabstracttype(T) ?
  reduce(vcat, (_concrete_subtypes(S) for S in InteractiveUtils.subtypes(T)); init = Type[]) : Type[T]

"""
    _pool_class_gaps(entries) -> Vector{Symbol}

Concrete kernel and transfer-scheme classes with no representative in the pool.

The pools cannot be derived — building a kernel needs constructor arguments — so they stay literal and
this audits them against `subtypes`, which is what DESIGN.md claimed was happening and what a comment
in this file claimed was "checked below". A new class is now reported, not silently unswept.
"""
function _pool_class_gaps(entries)
  present = Set(nameof(typeof(e.object)) for e in entries)
  wanted = Symbol[]
  for root in (GBGI.Convolution.AbstractSpectralKernel, GBGI.Interpolation.AbstractTransferScheme)
    for T in _concrete_subtypes(root)
      nameof(T) in present || Base.push!(wanted, nameof(T))
    end
  end
  return wanted
end

function canonical_pool(config; device = identity)
  T, grid, layout = config.eltype, config.grid, config.layout
  # The seed axis. A complete product over STRUCTURE still samples the VALUES — the axes enumerate
  # shapes, types and relations, never ℝ — and a fixed draw once put a Float32 result in the subnormal
  # band at ~16x the cost per element with nothing structural to reveal it. The seed is part of the
  # configuration and is printed with every finding, so a cell stays reproducible.
  Random.seed!(config.seed)
  rand(args...) = device(Base.rand(args...))
  P(R) = (grid.grid_size..., ntuple(_ -> 3, R)...)
  S(R) = GBGI.Fields.spectral_field_shape(grid, layout, Val(R))
  physical = (ScalarFieldPhysical(rand(T, P(0)...), grid, layout),
              VectorFieldPhysical(rand(T, P(1)...), grid, layout),
              TensorFieldPhysical{2}(rand(T, P(2)...), grid, layout))
  spectral = (ScalarFieldSpectral(rand(Complex{T}, S(0)...), grid, layout),
              VectorFieldSpectral(rand(Complex{T}, S(1)...), grid, layout),
              TensorFieldSpectral{2}(rand(Complex{T}, S(2)...), grid, layout))
  multipliers = FieldSpectralMultipliers(spectral[1])
  M = 12
  # Scaled on the HOST and moved afterwards. Broadcasting a device array against a host matrix is a
  # mixed-backend expression, which fails the whole pool build with a `KernelError` — and the lane then
  # reports the entire backend axis as unbuildable rather than the one line that is wrong.
  points = PointSet(device(Base.rand(T, M, 3) .* reshape(collect(grid.domain_size), 1, 3)))
  values = (ScalarPointValues(rand(T, M)), VectorPointValues(rand(T, M, 3)),
            TensorPointValues{2}(rand(T, M, 3, 3)))
  offset = ntuple(d -> T(0.5) * grid.grid_spacing[d], 3)

  entries = PoolEntry[]
  push = (label, object) -> Base.push!(entries, PoolEntry(label, object))
  for (R, f) in enumerate(physical); push("physical R=$(R-1)", f); end
  for (R, f) in enumerate(spectral); push("spectral R=$(R-1)", f); end
  for (R, q) in enumerate(values);   push("pointvalues R=$(R-1)", q); end
  push("points", points)
  push("grid", grid)
  push("layout", layout)
  push("multipliers", multipliers)
  for R in 0:2
    push("plans R=$R", FieldTransformPlans(physical[R + 1], spectral[R + 1]))
  end
  # Every kernel storage class, so a kernel-taking operation is swept over all of them rather than
  # over whichever one someone reached for. The list is checked against `subtypes` below — DESIGN.md
  # claimed these pools were derived by `subtypes(...)` and `subtypes(` appeared nowhere in the suite.
  # `StoredKernel` marks a FIELD as playing the kernel role, so it wraps the materialized coefficients
  # rather than the compressed closure the builder returns.
  push("kernel: stored",     StoredKernel(materialize_kernel(spectral_cutoff(spectral[1], multipliers, T(3)))))
  push("kernel: radial",     spectral_cutoff(spectral[1], multipliers, T(3)))
  push("kernel: band",       spectral_band(spectral[1], multipliers, T(1), T(3)))
  push("kernel: separable",  translation_kernel(spectral[1], multipliers, offset))
  push("kernel: window",     assignment_window(spectral[1], multipliers))
  # A GENUINE ProductKernel. Composing two separables collapses per-axis back into a `SeparableKernel`,
  # so the entry that used to sit here was a third separable one and `ProductKernel`'s own
  # `_kernel_data`, compatibility check, `inv` and materialization were unreached. Radial ∘ separable is
  # the cross-family composition that actually produces one.
  push("kernel: product",    convolve(spectral_cutoff(spectral[1], multipliers, T(3)),
                                      translation_kernel(spectral[1], multipliers, offset)))
  push("kernel: field",      squared_wavenumber_field(spectral[1], multipliers))
  # Every transfer scheme.
  push("scheme: CatmullRom", CatmullRom)
  push("scheme: Lalescu21",  LalescuSpline(2, 1))
  push("scheme: Lagrange1",  LagrangeSpline(1))
  push("scheme: DirectDFT",  DirectDFT())
  push("scheme: NUFFT",      NUFFT(spectral[1]))
  # THE GUARD THE COMMENT PROMISED. DESIGN.md claims these two pools are derived by `subtypes(...)`;
  # they are literals, and `subtypes(` appeared nowhere. Deriving them outright is not possible (a
  # kernel needs constructor arguments), so the literals stay and the derived set audits them: a new
  # concrete class with no pool entry is reported instead of silently unswept. Note `subtypes` is not
  # recursive, so the scheme check descends one level through `AbstractSplineScheme`.
  Base.push!(entries, PoolEntry("__pool_audit__", _pool_class_gaps(entries)))
  # Scalars, fibers and maps.
  push("real α",  T(0.3))
  push("real β",  T(0.7))
  # ZERO. Invariant 10's five-argument forms branch on `iszero(β)` — overwrite versus accumulate — and
  # with only 0.3 and 0.7 in the pool the overwrite branch was never taken by any exhaustive lane. The
  # gate crosses it in four files; this suite crossed it in none.
  push("real zero", zero(T))
  push("int 2",   2)
  # A DECAYING exponential coefficient. Without one the only value the engine could put in that slot
  # was a positive integer, which makes exp(c·|k|²) overflow rather than filter — so the whole
  # exponential family was swept only in the regime it is not for.
  push("decay coefficient", -T(1) / 10)
  push("fiber vector", FiberVector{T}(1, 2, 3))
  push("fiber tensor", FiberTensor2{T}(1, 2, 3, 4, 5, 6, 7, 8, 9))
  push("offset", offset)
  # The fiber maps are WRAPPED closures of fixed arity, never the bare names. `norm` is the reason:
  # `norm(x, p)` is LinearAlgebra's p-norm, so a two-input `map!(norm, dest, A, s)` is applicable and
  # silently reads the second FIELD as the exponent — giving Inf wherever p < 1 and a plausible wrong
  # number elsewhere. The lane reported that as a package defect; it is the engine building a call that
  # is applicable but not meaningful, which is a hazard of deriving calls from signatures. A wrapped
  # closure has one arity, so the wrong-arity call throws and is skipped instead of being misread.
  push("map: double", x -> 2x)
  push("map: det", x -> det(x))
  push("map: norm", x -> norm(x))
  push("map: tr", x -> tr(x))
  push("map: binary", (x, y) -> x + y)
  # The shape queries dispatch on `Val(R)`, and indexing takes indices. Without these the engine
  # reported `fiber_shape`, `physical_field_shape`, `spectral_field_shape`, `getindex` and `setindex!`
  # as unbuildable, which reads as "needs no test" rather than "the pool lacks an argument".
  for R in 0:2; push("Val($R)", Val(R)); end
  push("index 1", 1)
  push("index tuple", (1, 1, 1))
  push("cartesian index", CartesianIndex(1, 1, 1))
  push("scalar value", one(T))
  # The broadcast entry points take a `Broadcasted`, not a section, so without one `copy` and `copyto!`
  # — the whole broadcast surface, and the route every fused assignment goes through — were unbuildable.
  push("broadcasted physical", Base.broadcasted(+, physical[1], physical[1]))
  push("broadcasted spectral", Base.broadcasted(+, spectral[1], spectral[1]))
  push("broadcasted pointvalues", Base.broadcasted(+, values[1], values[1]))
  push("name", "section")
  if HDF5_AVAILABLE
    path = joinpath(mktempdir(), "exhaustive.h5")
    handle = HDF5.h5open(path, "w")
    push("hdf5 file", handle)
    # Registered for closing: a handle per pool, across 96 configurations and every backend, was left
    # open for the whole run while the sweep wrote into it.
    Base.push!(OPEN_HDF5_HANDLES, handle)
  end
  return entries
end


# ── Building calls ──────────────────────────────────────────────────────────────────────────────

# Whether a pool object could fill a signature slot.
#
# `isa` is the obvious test and it is WRONG here. A method's parameter is usually a `UnionAll` carrying
# free type variables — `TensorFieldPhysical{2, T, A, G} where {A, G}` — and `object isa that` is false
# for every object, so every slot came back empty and the engine skipped `det`, `tr`, `sym`,
# `to_physical` and fifty more as unbuildable. Comparing TYPE CONSTRUCTORS instead ignores the
# parameters that the `where` has not bound, which over-admits slightly; `applicable` then settles
# every candidate exactly, so the looseness costs work and never correctness.
function _slot_admits(parameter, object)
  parameter isa Core.TypeofVararg && return false
  base = parameter isa UnionAll ? Base.unwrap_unionall(parameter) : parameter
  base isa Union && return _slot_admits(base.a, object) || _slot_admits(base.b, object)
  base isa DataType || return true                    # a TypeVar admits anything
  base.name.wrapper === Type && return object isa Type
  return typeof(object) <: base.name.wrapper
end


"""
    invocations(operation, pool; cap = 400) -> Vector{NamedTuple}

Every call to `operation` this pool can build, one per admissible argument tuple.

The argument tuples come from the operation's own method signatures — each slot filtered by its
declared parameter type, then confirmed with `applicable` — so the set is derived from the method
table rather than written down. `cap` bounds the product per method and the number dropped is
reported, because a silently truncated sweep reads as a complete one.
"""
function invocations(operation::Function, pool; cap::Int = 400)
  built = NamedTuple[]
  dropped = 0
  oversized = 0
  unfillable = 0
  for method in methods(operation)
    _owned_by_package(method) || continue
    signature = Base.unwrap_unionall(method.sig)
    parameters = collect(signature.parameters)[2:end]
    # A zero-argument operation is still an operation — `threading_cutoff` reads the current setting —
    # and skipping empty parameter lists reported it as unbuildable.
    if isempty(parameters)
      applicable(operation) &&
        Base.push!(built, (operation = operation, label = "$(nameof(operation))()",
                           arguments = Any[], entries = PoolEntry[]))
      continue
    end
    # A variadic tail has no finite product, but it does have a shortest meaningful expansion: one
    # argument and two. `map!` and `map` are variadic in their sections, so skipping the class entirely
    # dropped the whole multi-input surface.
    if parameters[end] isa Core.TypeofVararg
      element = parameters[end].T
      base = parameters[1:end-1]
      # ONE copy and TWO, as DESIGN.md says. Expanding to two alone never builds the single-source
      # form for an operation whose only general method is the variadic one.
      for repetitions in 1:2
        expanded = [base..., fill(element, repetitions)...]
        length(expanded) > 9 && continue
        slots = [[e for e in pool if _slot_admits(p, e.object)] for p in expanded]
        any(isempty, slots) && continue
        for combination in Iterators.take(Iterators.product(slots...), cap)
          arguments = [e.object for e in combination]
          applicable(operation, arguments...) || continue
          Base.push!(built, (operation = operation,
                             label = "$(nameof(operation))(" *
                                     join((e.label for e in combination), ", ") * ")",
                             arguments = arguments, entries = collect(combination)))
        end
      end
      continue
    end
    # Wider than five, because six is where the α/β and kernel-composed arities live:
    # `combine!(dest, α, a, β, b, kernel)`, `exponential_convolve!`'s two-operand forms,
    # `anterpolate!(…, scheme, α, β)`, the kernel-composed `divergence!`/`helmholtz_projection!`.
    # Cutting at five removed thirteen public method forms from the sweep SILENTLY — not counted in
    # `dropped`, not reported — which is the design's own "prune by declared inapplicability, never by
    # sampling" rule broken by its engine.
    if length(parameters) > 9
      oversized += 1
      continue
    end
    slots = [[e for e in pool if _slot_admits(p, e.object)] for p in parameters]
    # Counted, not silently dropped. A method with an unfillable slot vanished with no counter at all —
    # neither `dropped` nor `oversized` — which is how a whole method form leaves a sweep that claims
    # completeness. The operation still reports as built when another of its methods succeeds.
    if any(isempty, slots)
      unfillable += 1
      continue
    end
    total = prod(length.(slots))
    total > cap && (dropped += total - cap)
    count = 0
    for combination in Iterators.product(slots...)
      count += 1
      count > cap && break
      arguments = [e.object for e in combination]
      applicable(operation, arguments...) || continue
      Base.push!(built, (operation = operation,
                         label = "$(nameof(operation))(" *
                                 join((e.label for e in combination), ", ") * ")",
                         arguments = arguments,
                         entries = collect(combination)))
    end
  end
  return (built = built, dropped = dropped, oversized = oversized, unfillable = unfillable)
end


"""
    all_invocations(pool; cap = 400) -> NamedTuple

Build calls for every public operation, and report the ones that could not be built.

An operation with no buildable call is a hole in the pool, not an operation that does not need
testing, so it is named. That number is the suite's honest coverage of its own operation axis.
"""
function all_invocations(pool; cap::Int = 400)
  operations = sort(collect(package_operations()); by = String)
  # One pass per FUNCTION OBJECT. `:⋅` and `:dot` resolve to the same function, so iterating names ran
  # the entire invocation product twice for each of the three alias pairs.
  swept = Base.IdSet{Any}()
  built, unbuildable, dropped, oversized, unfillable = NamedTuple[], Symbol[], 0, 0, 0
  for name in operations
    f = nothing
    for mod in (GBGPeriodicFields, Base, Statistics, LinearAlgebra, PACKAGE_MODULES...)
      isdefined(mod, name) || continue
      candidate = getfield(mod, name)
      candidate isa Function && (f = candidate; break)
    end
    if f === nothing
      Base.push!(unbuildable, name)
      continue
    end
    if f in swept
      continue
    end
    Base.push!(swept, f)
    result = invocations(f, pool; cap = cap)
    dropped += result.dropped
    oversized += result.oversized
    unfillable += result.unfillable
    isempty(result.built) ? Base.push!(unbuildable, name) : append!(built, result.built)
  end
  return (built = built, unbuildable = unbuildable, dropped = dropped, oversized = oversized,
          unfillable = unfillable, operations = operations)
end
