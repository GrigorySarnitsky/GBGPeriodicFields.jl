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


# The keywords the engine calls a method with, which it cannot fill from a slot: `applicable` ignores
# keywords, so a call built without a required one passes the filter and then throws `UndefKeywordError`
# on every invocation. Decision 101 made `exponential_convolve!`'s coefficient a required keyword and
# its offset an optional one; without this table the family left the universal checks silently, every
# built call failing before it returned. Each entry gives one or more KEYWORD SETS, and every built
# call is made once per set, so an optional keyword that selects a different path (the offset's two
# storage classes) is swept as the positional slot it replaced was. Values come from the pool where it
# has them. A required keyword missing from here is not dropped: `check_invocation!` rethrows
# `UndefKeywordError`, so it reaches the lane's harness-error count by name.
_pool_object(pool, label) = only(e.object for e in pool if e.label == label)
_exponential_keyword_sets(pool) =
  [(coefficient = _pool_object(pool, "decay coefficient"),),
   (coefficient = _pool_object(pool, "decay coefficient"),
    offset = _pool_object(pool, "exponent offset: field"), offset_scale = 1 // 100),
   (coefficient = _pool_object(pool, "decay coefficient"),
    offset = _pool_object(pool, "kernel: band"), offset_scale = 1 // 100)]
const REQUIRED_KEYWORDS = Dict{Symbol, Function}(
  :exponential_convolve! => _exponential_keyword_sets,
  :exponential_convolve  => _exponential_keyword_sets,
  :with_threading        => pool -> [(enabled = nothing,)],
)

_keyword_sets(operation, pool) =
  haskey(REQUIRED_KEYWORDS, nameof(operation)) ? REQUIRED_KEYWORDS[nameof(operation)](pool) : [(;)]

_keyword_label(keywords) = isempty(keywords) ? "" :
  "; " * join(("$(k) = $(v isa Number ? v : nameof(typeof(v)))" for (k, v) in pairs(keywords)), ", ")

"""
    invocation_keywords(invocation) -> NamedTuple

The keywords an invocation is called with: empty for one built without any, as the self-check's are.
"""
invocation_keywords(invocation) = haskey(invocation, :keywords) ? invocation.keywords : (;)

"""
    check_required_keywords() -> Vector{String}

Every keyword `REQUIRED_KEYWORDS` names, checked against the method table: a keyword no method of its
operation declares is a stale entry, reported rather than passed silently to a call that would refuse it.
"""
function check_required_keywords()
  stale = String[]
  for (name, provide) in REQUIRED_KEYWORDS
    operation = getfield(GBGPeriodicFields, name)
    declared = Set(Iterators.flatten(Base.kwarg_decl(m) for m in methods(operation)))
    stand_in = PoolEntry[PoolEntry(label, nothing)
                         for label in ("decay coefficient", "exponent offset: field", "kernel: band")]
    for keyword in unique(Iterators.flatten(keys.(provide(stand_in))))
      keyword in declared || push!(stale, "$(name): `$(keyword)` is declared by no method")
    end
  end
  return stale
end


_concrete_subtypes(T) = isabstracttype(T) ?
  reduce(vcat, (_concrete_subtypes(S) for S in InteractiveUtils.subtypes(T)); init = Type[]) : Type[T]

"""
    _pool_class_gaps(entries) -> Vector{Symbol}

Concrete kernel and transfer-scheme classes with no representative in the pool.

The pools cannot be derived — building a kernel needs constructor arguments — so they stay literal and
this audits them against `subtypes`, which is what the survey design claimed was happening and what a comment
in this file claimed was "checked below". A new class is now reported, not silently unswept.
"""
function _pool_class_gaps(entries)
  present = Set(nameof(typeof(e.object)) for e in entries)
  wanted = Symbol[]
  for root in (GBGI.Convolution.SpectralKernel, GBGI.Interpolation.AbstractTransferScheme)
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
  # `randn` too. Only `rand` went through `device`, so on a GPU run every spectral field in the pool —
  # drawn with `randn` — stayed on the host while the physical ones moved, and no spectral operation
  # was ever swept on a device: the backend axis was silently host-only for half the surface.
  randn(args...) = device(Base.randn(args...))
  P(R) = (grid.grid_size..., ntuple(_ -> 3, R)...)
  S(R) = GBGI.Fields.field_spectral_shape(grid, layout, Val(R))
  physical = (ScalarFieldPhysical(rand(T, P(0)...), grid; layout),
              VectorFieldPhysical(rand(T, P(1)...), grid; layout),
              TensorFieldPhysical{2}(rand(T, P(2)...), grid; layout))
  # `randn`, not `rand`: uniform complex draws put every Fourier coefficient in the positive quadrant,
  # so nothing in the spectral pool ever carried a negative real or imaginary part and a sign defect had
  # no fixture that could show it. The reference lane already draws signed, mean-zero coefficients.
  spectral = (ScalarFieldSpectral(randn(Complex{T}, S(0)...), grid; layout),
              VectorFieldSpectral(randn(Complex{T}, S(1)...), grid; layout),
              TensorFieldSpectral{2}(randn(Complex{T}, S(2)...), grid; layout))
  physical2 = (ScalarFieldPhysical(rand(T, P(0)...), grid; layout),
               VectorFieldPhysical(rand(T, P(1)...), grid; layout),
               TensorFieldPhysical{2}(rand(T, P(2)...), grid; layout))
  spectral2 = (ScalarFieldSpectral(randn(Complex{T}, S(0)...), grid; layout),
               VectorFieldSpectral(randn(Complex{T}, S(1)...), grid; layout),
               TensorFieldSpectral{2}(randn(Complex{T}, S(2)...), grid; layout))
  # THE COARSE SIDE OF THE RESOLUTION VERBS (decision 85). `embed_modes!` and `extract_modes!` take two
  # spectral fields on the SAME box at DIFFERENT resolutions, and REFUSE equal grids. Every field above
  # is on `config.grid`, so both of their slots were filled from it, every built call refused, and the
  # two operations were surveyed by nothing while appearing to be reached — worse than an absence,
  # because the count said they were covered. The coarse grid is derived per configuration rather than
  # fixed: same box, same origin, same layout, half the points on each axis and never fewer than two,
  # which is coarser on at least one axis for all four grid shapes the survey enumerates.
  coarse_size = map(n -> max(2, n ÷ 2), grid.grid_size)
  coarse_grid = Grid3D(coarse_size, grid.domain_size, grid.domain_size ./ coarse_size, grid.origin)
  CS(R) = GBGI.Fields.field_spectral_shape(coarse_grid, layout, Val(R))
  coarse = (ScalarFieldSpectral(randn(Complex{T}, CS(0)...), coarse_grid; layout),
            VectorFieldSpectral(randn(Complex{T}, CS(1)...), coarse_grid; layout),
            TensorFieldSpectral{2}(randn(Complex{T}, CS(2)...), coarse_grid; layout))
  multipliers = FieldSpectralMultipliers(spectral[1])
  M = 12
  # Scaled on the HOST and moved afterwards. Broadcasting a device array against a host matrix is a
  # mixed-backend expression, which fails the whole pool build with a `KernelError` — and the lane then
  # reports the entire backend axis as unbuildable rather than the one line that is wrong.
  # PLUS THE ORIGIN. Without it these points are not in the box for the shifted configuration, which
  # exists precisely so an operation that forgets to subtract the origin can be caught. The value lane's
  # own point sets already add it; this pool did not, so the two disagreed about where the box is.
  points = PointSet(device(Base.rand(T, M, 3) .* reshape(collect(grid.domain_size), 1, 3) .+
                           reshape(collect(grid.origin), 1, 3)))
  values = (ScalarPointValues(rand(T, M)), VectorPointValues(rand(T, M, 3)),
            TensorPointValues{2}(rand(T, M, 3, 3)))
  values2 = (ScalarPointValues(rand(T, M)), VectorPointValues(rand(T, M, 3)),
             TensorPointValues{2}(rand(T, M, 3, 3)))
  # NOT a half cell on every axis. At h = Δ/2 the even-axis Nyquist multiplier `cos(πh/Δ)` is exactly
  # `cos(π/2) = 0`, so decision 28's hard case — the one term that must be a real factor rather than a
  # phase — was multiplied away in every cell, and a sign error there is invisible against `-0.0 == 0.0`.
  # The axes now carry different fractions, one of them still the half cell so that edge case stays.
  offset = ntuple(d -> (T(3)/10, T(1)/2, T(7)/10)[d] * grid.grid_spacing[d], 3)

  entries = PoolEntry[]
  push = (label, object) -> Base.push!(entries, PoolEntry(label, object))
  for (R, f) in enumerate(physical); push("physical R=$(R-1)", f); end
  for (R, f) in enumerate(spectral); push("spectral R=$(R-1)", f); end
  for (R, f) in enumerate(coarse);   push("coarse spectral R=$(R-1)", f); end
  for (R, q) in enumerate(values);   push("pointvalues R=$(R-1)", q); end
  # A DISPLACEMENT TERM. `displace!` takes its terms as `(coefficient, section)` TUPLES, and no pool
  # object was a tuple, so the variadic expansion above found the slot unfillable and the operation was
  # reported as having no buildable call at all — the only public operation whose argument SHAPE, not
  # its type, put it out of reach. One entry restores it; the engine's own Vararg expansion then builds
  # both the one-term and two-term forms, and the value lane drives the coefficients.
  push("displacement term (coefficient, vector point values)", (T(3) / 10, values[2]))
  # THE TRAVERSAL ORDER AND ITS SCRATCH (decisions 78, 80). Three public operations were reported
  # unbuildable on 2026-09-06 because no pool object filled a `PointTraversalOrder` or a
  # `PointTraversalOrderScratch` slot: `length` of an order, `point_traversal_order!`, and the order's
  # `adapt_structure` hook. Both are built from the pool's OWN point set and grid, so the in-place
  # form's precondition — an order of this point count, a scratch built for this grid and count —
  # holds by construction — `points` is the pool's own point set, pushed below; `_refresh` deep-copies
  # both before every call, since each owns arrays.
  push("traversal order", point_traversal_order(grid, points))
  push("traversal scratch", PointTraversalOrderScratch(grid, points))
  # A SECOND, INDEPENDENTLY DRAWN instance of each. With one object per (representation, order), every
  # same-order slot the engine fills draws the SAME object, so it could only ever build `add!(v, v, v)`,
  # `cross!(v, v, v)`, `dot!(s, v, v)`, `mul!(C, A, A)`. That is not merely thin coverage: the
  # preservation check skips an argument that is `===` the destination, because writing there is the
  # operation's job — so with every same-order argument forced to BE the destination, the one universal
  # check whose purpose is "did this call corrupt an argument it must not touch" had nothing left to
  # compare across the whole pairwise algebra, however many cells ran. `build_pool` in `aliasing.jl` and
  # `_bench` in `properties.jl` both draw independent instances already; this pool did not.
  for (R, f) in enumerate(physical2); push("physical R=$(R-1) (b)", f); end
  for (R, f) in enumerate(spectral2); push("spectral R=$(R-1) (b)", f); end
  for (R, q) in enumerate(values2);   push("pointvalues R=$(R-1) (b)", q); end
  push("points", points)
  push("grid", grid)
  push("layout", layout)
  push("multipliers", multipliers)
  for R in 0:2
    push("plans R=$R", FieldTransformPlans(physical[R + 1], spectral[R + 1]))
  end
  # Every kernel storage class, so a kernel-taking operation is swept over all of them rather than
  # over whichever one someone reached for. The list is checked against `subtypes` below — the design
  # claimed these pools were derived by `subtypes(...)` and `subtypes(` appeared nowhere in the suite.
  # `StoredKernel` marks a FIELD as playing the kernel role, so it wraps the materialized coefficients
  # rather than the compressed closure the builder returns.
  push("kernel: stored",     materialize_kernel(spectral_cutoff(multipliers, T(3))))
  push("kernel: radial",     spectral_cutoff(multipliers, T(3)))
  push("kernel: band",       spectral_band(multipliers, T(1), T(3)))
  push("kernel: separable",  translation_kernel(multipliers, offset))
  push("kernel: window",     assignment_window(multipliers))
  push("kernel: tophat",     tophat_window(multipliers, 0.7))
  # A GENUINE ProductKernel. Composing two separables collapses per-axis back into a `SeparableKernel`,
  # so the entry that used to sit here was a third separable one and `ProductKernel`'s own
  # `_kernel_data`, compatibility check, `inv` and materialization were unreached. Radial ∘ separable is
  # the cross-family composition that actually produces one.
  push("kernel: product",    convolve(spectral_cutoff(multipliers, T(3)),
                                      translation_kernel(multipliers, offset)))
  push("kernel: field",      materialize_kernel(radial_kernel(identity, multipliers)))
  # A TUPLE OF WEIGHTS for `weighted_inner`'s several-weights form (decision 72), which no pool object
  # could fill: its slot takes a `Tuple` of kernels, and nothing here was one, so the method was never
  # built. Thirty-three weights of mixed REAL storage classes, past the group of four the reduction
  # works in and past Julia's 32-element tuple threshold (decision 88). The complex translation phase
  # is left out, a complex weight being refused by design.
  real_weights = (materialize_kernel(spectral_cutoff(multipliers, T(3))), spectral_cutoff(multipliers, T(3)),
                  spectral_band(multipliers, T(1), T(3)), assignment_window(multipliers),
                  tophat_window(multipliers, 0.7))
  push("weights: 33 mixed", ntuple(i -> real_weights[mod1(i, length(real_weights))], 33))
  # Every transfer scheme.
  push("scheme: CatmullRom", CatmullRom)
  push("scheme: Lalescu21",  LalescuSpline(6; smoothness = 1))
  push("scheme: Lagrange1",  LagrangeSpline(4))
  push("scheme: DirectDFT",  DirectDFT())
  push("scheme: NUFFT",      NUFFT(spectral[1]))
  # The audit result is RETURNED, not pushed into the pool. Pushing it made a `Vector{Symbol}` a live
  # candidate for any loosely-typed slot, and nothing ever read it back — so the guard the docstring
  # promised was computed and discarded.
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
  # The exponential kernel's per-mode OFFSET, a keyword since decision 101: a field holding real values
  # in its complex storage, drawn like the spectral pool. Its radial sibling is "kernel: band".
  push("exponent offset: field",
       ScalarFieldSpectral(complex.(real.(randn(Complex{T}, S(0)...))), grid; layout))
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
  # ASYMMETRIC. `x + y` is commutative, so an argument-order swap inside the variadic dispatch is
  # invisible through the only two-source closure the pool has. The value lane already uses `x - 2y` for
  # exactly this reason; the sibling entry here was not updated to match.
  push("map: binary", (x, y) -> x - 2y)
  # ANY NUMBER of inputs (decision 88). Every map above takes one or two fibers, so the nine- and
  # thirty-three-source `map!` calls the variadic expansion builds all threw a `MethodError` and
  # surveyed nothing. A sum is defined for any count of same-order fibers, and a mixed-order call still
  # throws, as it should.
  push("map: sum of all", (xs...) -> sum(xs))
  # The shape queries dispatch on `Val(R)`, and indexing takes indices. Without these the engine
  # reported `fiber_shape`, `field_physical_shape`, `field_spectral_shape`, `getindex` and `setindex!`
  # as unbuildable, which reads as "needs no test" rather than "the pool lacks an argument".
  for R in 0:2; push("Val($R)", Val(R)); end
  # NOT (1, 1, 1). That triple is a FIXED POINT of every permutation of the three axes, so an
  # implementation that transposed two of them indexed the identical element and agreed with a correct
  # one in every cell — and component 1 was the only fiber component ever read. `(2, 3, 1)` is in bounds
  # on every configured grid in both representations: the tightest extents are the odd grid's spectral
  # folds, `(4, 5, 3)` and `(7, 3, 3)`.
  # BOTH 1 and 2. Moving the index entry off 1 (a fixed point of every axis permutation) removed the
  # literal 1 from the pool entirely, since the only other small-integer entry is also a 2 — so the
  # generic engine's `Int` slots lost their most common boundary value.
  push("index 1", 1)
  push("index 2", 2)
  push("index tuple", (2, 3, 1))
  push("cartesian index", CartesianIndex(2, 3, 1))
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


"""
    pool_class_gaps(config) -> Vector{Symbol}

Concrete kernel and transfer-scheme classes with no representative in the pool for `config`.
"""
pool_class_gaps(config; device = identity) = _pool_class_gaps(canonical_pool(config; device = device))


# ── Building calls ──────────────────────────────────────────────────────────────────────────────

# Whether a pool object could fill a signature slot.
#
# `isa` is the obvious test and it is WRONG here. A method's parameter is usually a `UnionAll` carrying
# free type variables — `TensorFieldPhysical{2, T, A, G} where {A, G}` — and `object isa that` is false
# for every object, so every slot came back empty and the engine skipped `det`, `tr`, `sym`,
# `to_physical` and fifty more as unbuildable. Comparing TYPE CONSTRUCTORS instead ignores the
# parameters that the `where` has not bound, which over-admits slightly; `applicable` then settles
# every candidate exactly, so the looseness costs work and never correctness.
# ADAPTOR SLOTS — the one place derivation cannot decide, and the reason is Adapt.jl's, not ours.
#
# `Adapt.adapt_structure(to, x)` takes a *target* in its leading slot — a description of the storage
# family to move into — and Adapt.jl leaves it untyped, because an adaptor may be any object a package
# cares to define. `_slot_admits` therefore admitted the WHOLE pool there and `applicable` confirmed
# every one, so the engine built calls reading "adapt these plans TO this field": 42_336 cells on the
# 2026-08-15 run, every one reported as a structural or type-stability finding, and between them they
# buried the report's real content. They are not defects and they are not calls anyone makes.
#
# Nothing in the signature separates a target from an operand, so the slot is NAMED — derivation's
# honest limit, declared rather than hidden. The slot is then filled from the adaptor pool, which
# keeps the operation covered by real calls (`adapt_structure(Array, field)` is the host-to-host
# identity) instead of dropping it.
_adaptor_slots(operation) = nameof(operation) === :adapt_structure ? (1,) : ()

# The adaptors this process can name. `Array` is always available; a device backend adds its own array
# type when the suite runs from `test/gpu/*`, which is where the cross-family move is worth checking.
_adaptor_pool() = PoolEntry[PoolEntry("adaptor: Array", Array)]

# WHICH SLOT TAKES THE COARSER FIELD (decision 85). Both verbs take two spectral fields and the
# direction is the verb's, not the caller's: `embed_modes!` writes the FINER destination from a coarser
# source, `extract_modes!` the reverse. So the coarse slot is named per operation, as `adapt_structure`'s
# adaptor slot is — derivation's honest limit, declared rather than hidden. Passing them the other way
# round is a refusal the context lane owns, not something the canonical pool should build.
_coarse_mode_slots(operation) = nameof(operation) === :embed_modes!   ? (2,) :
                                nameof(operation) === :extract_modes! ? (1,) : ()

# The coarse entries are in the ordinary pool so that `_refresh` and the class audit see them, and are
# kept OUT of every other slot: a coarse field offered to any other operation is a domain mismatch, which
# is the context lane's subject and would be noise here.
_is_coarse(entry::PoolEntry) = startswith(entry.label, "coarse ")

# `hash`'s second slot is the seed, a `UInt` no section pool holds (decision 91). Named like the
# adaptor slot and filled from a seed pool, so the operation is reached by real calls instead of
# being reported unreachable.
_seed_slots(operation) = nameof(operation) === :hash ? (2,) : ()
_seed_pool() = PoolEntry[PoolEntry("hash seed: zero(UInt)", zero(UInt)), PoolEntry("hash seed: 0x9e3779b9", UInt(0x9e3779b9))]

_slot_candidates(operation, index, parameter, pool) =
  index in _adaptor_slots(operation) ? _adaptor_pool() :
  index in _seed_slots(operation) ? _seed_pool() :
  index in _coarse_mode_slots(operation) ?
      [e for e in pool if _is_coarse(e) && _slot_admits(parameter, e.object)] :
      [e for e in pool if !_is_coarse(e) && _slot_admits(parameter, e.object)]


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
        for keywords in _keyword_sets(operation, pool)
          Base.push!(built, (operation = operation, label = "$(nameof(operation))($(_keyword_label(keywords)))",
                             arguments = Any[], entries = PoolEntry[], keywords = keywords))
        end
      continue
    end
    # A variadic tail has no finite product, but it does have a shortest meaningful expansion: one
    # argument and two. `map!` and `map` are variadic in their sections, so skipping the class entirely
    # dropped the whole multi-input surface.
    if parameters[end] isa Core.TypeofVararg
      element = parameters[end].T
      base = parameters[1:end-1]
      # ONE copy and TWO, as the design asks. Expanding to two alone never builds the single-source
      # form for an operation whose only general method is the variadic one.
      #
      # And NINE and THIRTY-THREE (decision 88). The operations with a variadic tail work through their
      # operands in groups of eight, and Julia leaves its specialized tuple path at 32, so one and two
      # copies reach neither boundary. A long expansion builds only the covering combinations below —
      # one per candidate, every slot drawing that candidate — never the product, whose size is the
      # candidate count to the thirty-third power.
      for repetitions in (1, 2, 9, 33)
        long_tail = repetitions > 2
        expanded = [base..., fill(element, repetitions)...]
        # Counted, like the non-variadic branch below. Skipping silently here is the very failure its
        # sibling's comment warns about, and it hides the `map!`/`map` forms this branch exists for.
        if !long_tail && length(expanded) > 9
          oversized += 1
          continue
        end
        slots = [_slot_candidates(operation, i, p, pool) for (i, p) in enumerate(expanded)]
        if any(isempty, slots)
          unfillable += 1
          continue
        end
        # A long tail is not truncated, it is a different expansion — covering calls only, by design —
        # so it adds nothing to `dropped`, and its product (which would overflow an `Int`) is never formed.
        total = long_tail ? 0 : prod(length.(slots))
        total > cap && (dropped += total - cap)
        # THE SAME COVERING PASS AS THE NON-VARIADIC BRANCH. Adding it there and not here was one fix
        # applied to one of two sibling call sites — and it bites harder here: `map!`'s `φ::F where {F}`
        # is an unbound TypeVar, which `_slot_admits` admits the whole pool for, so the leading slot
        # alone exhausts the cap and every trailing SOURCE slot stays frozen at its first entry for the
        # entire sweep. The two-source `map!(φ, dest, a, b)` form never varied `b` at all.
        variadic_covering = Vector{Any}[]
        if total > cap || long_tail
          for t in 1:maximum(length, slots)
            Base.push!(variadic_covering, [slot[(t - 1) % length(slot) + 1] for slot in slots])
          end
        end
        seen_count = 0
        for combination in (long_tail ? variadic_covering : Iterators.flatten((variadic_covering, Iterators.product(slots...))))
          seen_count += 1
          seen_count > cap && break
          arguments = [e.object for e in combination]
          applicable(operation, arguments...) || continue
          for keywords in _keyword_sets(operation, pool)
            Base.push!(built, (operation = operation,
                               label = "$(nameof(operation))(" *
                                       join((e.label for e in combination), ", ") * _keyword_label(keywords) * ")",
                               arguments = arguments, entries = collect(combination), keywords = keywords))
          end
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
    slots = [_slot_candidates(operation, i, p, pool) for (i, p) in enumerate(parameters)]
    # Counted, not silently dropped. A method with an unfillable slot vanished with no counter at all —
    # neither `dropped` nor `oversized` — which is how a whole method form leaves a sweep that claims
    # completeness. The operation still reports as built when another of its methods succeeds.
    if any(isempty, slots)
      unfillable += 1
      continue
    end
    total = prod(length.(slots))
    total > cap && (dropped += total - cap)
    # COVER EVERY SLOT VALUE FIRST, then fill the remaining budget from the head of the product.
    # Truncating `Iterators.product` at the cap keeps a PREFIX, and the product varies its first slot
    # fastest — so once the leading slots alone exceed the cap, every later slot is frozen at its first
    # value for the whole method. That is not sampling, it is silently deleting an axis: `map!`'s α/β
    # form never advanced past α = β = 0.3, so invariant 10's `β = 0` overwrite branch — the reason the
    # zero entry is in the pool at all — was unreachable for it; and `combine!`'s kernel-composed arity
    # never left its first kernel, so the separable and radial kernel classes were never composed with
    # it. Cycling each slot independently covers every value of every slot in `maximum(length, slots)`
    # combinations, which is free, and the head of the product then supplies the interactions.
    covering = Vector{Any}[]
    if total > cap
      for t in 1:maximum(length, slots)
        Base.push!(covering, [slot[(t - 1) % length(slot) + 1] for slot in slots])
      end
    end
    count = 0
    for combination in Iterators.flatten((covering, Iterators.product(slots...)))
      count += 1
      count > cap && break
      arguments = [e.object for e in combination]
      applicable(operation, arguments...) || continue
      for keywords in _keyword_sets(operation, pool)
        Base.push!(built, (operation = operation,
                           label = "$(nameof(operation))(" *
                                   join((e.label for e in combination), ", ") * _keyword_label(keywords) * ")",
                           arguments = arguments,
                           entries = collect(combination),
                           keywords = keywords))
      end
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
  # An operation the package does not define AT ALL is a different thing from one whose arguments the
  # pool cannot build, and lumping them together reads as a coverage hole where there is none.
  # `adapt` is Adapt.jl's own generic: the package extends `adapt_structure`, the hook it dispatches
  # through, and never adds an `adapt` method. So there is no package-owned method here to call, and
  # the operation is covered exactly where that hook is covered.
  hook_extended = Symbol[]
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
    if isempty(result.built)
      # No package-owned method at all → the hook class above. Otherwise the pool genuinely could not
      # fill a slot, which IS a hole and stays named as one.
      any(_owned_by_package, methods(f)) ? Base.push!(unbuildable, name) : Base.push!(hook_extended, name)
    else
      append!(built, result.built)
    end
  end
  return (built = built, unbuildable = unbuildable, hook_extended = hook_extended,
          dropped = dropped, oversized = oversized,
          unfillable = unfillable, operations = operations)
end
