# Method-parity baseline for FieldAlgebra (M2 + M3 — the full public surface).
#
# Locks the generated method set so a codegen change cannot silently add or drop
# methods. Counts are "methods FieldAlgebra defines for each generic"
# (m.module === FieldAlgebra), which filters out the hundreds of Base methods on
# the operators. 206 public methods total (the pre-refactor surface plus `tr`/`tr!`,
# the weighted combination `combine!`, and the determinant `det`/`det!`).

using Test
using GBGPeriodicFields
using Statistics
include("public_surface.jl")

const FA = GBGPeriodicFields.FieldAlgebra
const IP = GBGPeriodicFields.Points
pkg_method_count(f) = count(m -> m.module === FA, methods(f))
pointvalues_method_count(f) = count(m -> m.module === IP, methods(f))

@testset "method parity" begin

  @testset "M2 + M3 baseline (206 methods)" begin
    baseline = (("add!", add!, 14), ("subtract!", subtract!, 14), ("combine!", combine!, 2),
                ("multiply!", multiply!, 16), ("divide!", divide!, 6),
                ("+", +, 15), ("-", -, 15), ("*", *, 28), ("/", /, 5),
                ("dot", dot, 10), ("dot!", dot!, 10), ("cross", cross, 5), ("cross!", cross!, 5),
                ("mul!", mul!, 30), ("transpose", transpose, 2), ("transpose!", transpose!, 2),
                ("norm", norm, 3), ("norm!", norm!, 3),
                ("sym", sym, 3), ("sym!", sym!, 2), ("skew", skew, 3), ("skew!", skew!, 2),
                ("dev", dev, 3), ("dev!", dev!, 2),
                ("tr", tr, 2), ("tr!", tr!, 2), ("det", det, 1), ("det!", det!, 1))
    for (name, f, n) in baseline
      @test pkg_method_count(f) == n
    end
    @test sum(pkg_method_count(f) for (_, f, _) in baseline) == 206
  end

  # The PointValues algebra (Points module) mirrors the fields' *physical* surface, on
  # the same generics. It is counted separately (m.module === Points), so the field
  # baseline above stays locked while this locks the new surface. Representation-free ⇒ no
  # spectral variants, so the counts are smaller than the field ones.
  @testset "PointValues algebra baseline (122 methods)" begin
    baseline = (("add!", add!, 7), ("subtract!", subtract!, 7),
                ("multiply!", multiply!, 10), ("divide!", divide!, 5),
                ("+", +, 8), ("-", -, 8), ("*", *, 18), ("/", /, 5),
                ("dot", dot, 6), ("dot!", dot!, 6), ("cross", cross, 3), ("cross!", cross!, 3),
                ("mul!", mul!, 18), ("transpose", transpose, 1), ("transpose!", transpose!, 1),
                ("norm", norm, 3), ("norm!", norm!, 3),
                ("sym", sym, 1), ("sym!", sym!, 1), ("skew", skew, 1), ("skew!", skew!, 1),
                ("dev", dev, 1), ("dev!", dev!, 1),
                ("tr", tr, 1), ("tr!", tr!, 1), ("det", det, 1), ("det!", det!, 1))
    for (name, f, n) in baseline
      @test pointvalues_method_count(f) == n
    end
    @test sum(pointvalues_method_count(f) for (_, f, _) in baseline) == 122
  end

  @testset "no ambiguities" begin
    @test isempty(detect_ambiguities(GBGPeriodicFields; recursive = true))
  end

end


# ---------------------------------------------------------------------------------------------
# Derived module baselines (decision 53).
#
# The hand-written baseline above enumerates 28 generic NAMES filtered to two modules, so it is
# blind to everything else: decisions 48, 49 and 51 each added public surface — `map!`/`map` in
# FieldAlgebra, `cov` in Reductions, the kernel builders in Convolution — and neither the 206 nor
# the 122 moved. A baseline that cannot see a new generic does not enforce "the public method set
# is the spec"; it enforces it for the names someone remembered to list.
#
# This one is DERIVED rather than enumerated: for each module, every function that module owns,
# counted over the methods defined IN that module. Adding a method anywhere moves a number, and the
# number must then be refrozen deliberately — the pass-audit protocol, applied to the method table.
# Extension methods (the HDF5 weak dependency) live in their own module and are excluded by the
# `m.module === mod` filter, so loading HDF5 does not perturb the counts.
const MODULE_BASELINE = (
  FiberSections         = 110,   # + section_tensor_order, cartesian _index_ranges, _check_owned_storage
  # 105 → 103: `_kernel_data(::ScalarFieldSpectral)` and `_check_kernel_compatibility(field,
  # ::ScalarFieldSpectral)` were deleted when a field in spectral representation stopped being a kernel
  # (decision 60). Refrozen deliberately, with the reason, per decision 53's protocol.
  # 103 → 115: moving sections between storage families. Four are the `adapt_structure` methods
  # themselves (physical fields, spectral fields, `FieldSpectralMultipliers`, `FieldTransformPlans`);
  # the other eight are the internals they need — `_storage_prototype`, the two three-method families
  # `_physical_field_of_order`/`_spectral_field_of_order` that construct a field of a given tensor
  # order without a reference to copy metadata from, and `_is_canonical`, which reads back the
  # parameter that lets `convolve` collapse two radial kernels statically. Refrozen deliberately, with
  # the reason, per decision 53's protocol.
  # 115 → 116: the preserving scratch arity `to_physical!(physical, spectral, plans,
  # spectral_scratch)` (decision 64, an IT round-3 request) — the allocation-free member of the
  # preserving contract the allocating `to_physical` already offered. One new method on the existing
  # generic; the 3-arg form and the allocating forms are unchanged.
  # 116 → 119: the in-place storage move (decision 69). Two are `adapt!`'s own field methods, one per
  # representation; the third is `_check_adapt_target`, which is `_check_same_domain` without its
  # storage-family clause — the one thing this operation exists to let differ. Refrozen deliberately,
  # with the reason, per decision 53's protocol.
  # 119 → 120: `reality_residual` (decision 71), the checkable half of the real-field layout's
  # conjugate-symmetry contract. One method, on the spectral representation only — a physical field
  # has no such constraint, so it has none. Refrozen deliberately, with the reason.
  # 120 → 122 (decision 74): the two helpers behind the allocating `(family, grid[, layout])`
  # constructors — `_allocated_field_storage` and `_check_family_element_type`. The sixteen
  # constructor methods themselves are Type methods, which this per-function count does not see;
  # they are covered by the constructor testset and the ambiguity check instead.
  # 122 → 126: the transform plans stopped carrying a tensor order (decision 76). The four are
  # `_component_offsets_align` (does a component view begin where a transform library will accept
  # it), `_component_views` (the fiber flattened to a trailing axis, which the fiber-last layout of
  # invariant 3 makes contiguous), and the two per-component passes `_forward_components!` /
  # `_inverse_components!`. No public method moved: the plans type lost a type parameter and the
  # transform generics lost `R` from their signatures, but their arities are unchanged. Refrozen
  # deliberately, with the reason, per decision 53's protocol.
  Fields                = 128,
  # 127 → 128: `_reality_residual_plane`, the folded-plane pass with its axis as a `Val` type
  # parameter. The exhaustive survey's type-stability check reported `reality_residual` inferring
  # `Any` on every configuration (576 cells, one operation); reaching the plane through a runtime
  # dimension was the cause, and naming the axis in the type domain is the same remedy
  # `Interpolation`'s folded-plane helpers already use.
  # 126 → 127: `_component_views` (one method, returning a reshape) became `_component_view` (two —
  # a rank-0 identity and the rank-`R` fiber-indexed slice). The reshape allocated an `Array` wrapper
  # per call, twice per transform, which is the 128 B/call a consumer's zero-allocation invariant
  # caught and this package's field-sized threshold did not (/bug-hunt-adjacent report, 2026-08-27).
  FieldAlgebra          = 275,
  DifferentialOperators = 90,
  # 79 → 90: `inverse_curl` (2026-08-28). Two public generics with one method each, plus the
  # `@kernel` expansion of `_inverse_curl_kernel!` and the two `_inverse_curl_modes!` arms — the
  # device launch and its gated CPU twin. The same shape `curl` and `helmholtz_projection` already
  # have, so the count moves by the same amount adding either of them would.
  # 78 → 77: `squared_wavenumber_field` was deleted (decision 60). |k|² is a radial symbol, so it is
  # `radial_kernel(identity, …)` — a closure — and materializing it is the caller's explicit choice
  # through `materialize_kernel`, which is what that escape hatch is for.
  # 77 → 79 for ONE new method: `convolve(::RadialKernel, ::RadialKernel)` split into two
  # statically-dispatched methods — canonical multipliers collapse, anything else keeps both operands —
  # replacing a runtime `===` test whose two outcomes made the return type a Union. It counts twice
  # because `⋆` is `const ⋆ = convolve`, the same function object under a second name, and this baseline
  # walks names rather than objects. That double count is a property of the instrument, not of the
  # change; every alias in the package has always been counted this way. Refrozen deliberately, with the
  # reason, per decision 53's protocol.
  # 79 → 83: one `adapt_structure` per kernel storage class, so a kernel moves between storage
  # families with its field, and a `ProductKernel` moves both factors rather than being assembled
  # across families by accident.
  Convolution           = 83,   # +6 earlier: the StoredKernel role marker and its protocol methods
  # 207 → 209: `adapt_structure` for the point-value sections and for `PointSet`, mirroring the field
  # layer as the point layer does throughout.
  # 209 → 211: `adapt!`'s two point methods (decision 69), one for the point-value sections and one
  # for `PointSet`. The generic and its documentation live in `Fields`; these are the point twins, as
  # the `adapt_structure` pair above already are.
  # 211 → 226: base-space motion (decision 73). Five public methods — `displace!` ×4 (cover and
  # torus, each with a destination/source form and an in-place convenience) and `wrap!` ×1 — plus
  # ten internal ones: the recursive broadcast builders (`_displacement_rhs`, `_convert_terms`,
  # `_axis_terms`, two methods each), `_wrap_coordinate`, `_motion_storage_family`, and the two
  # compatibility checks.
  Points                = 226,
  Interpolation         = 170,
  # 120 → 151: the transfer visit order (decision 78). The public surface is UNCHANGED — the four
  # transfer verbs gained a keyword argument, not a positional method, which is what keeps the 206/122
  # baselines above intact — so every one of the 31 is new machinery or a keyword sorter: three
  # KernelAbstractions kernels for the counting sort at four methods each plus their CPU and GPU twins
  # (18), `_visit` ×2 and `_wrap_step` for the index walk, `_check_transfer_order` ×2, `transfer_order`
  # itself, and the keyword sorters the four verbs now carry. Then 151 → 156: the four ALLOCATING
  # wrappers took the same keyword, so a consumer that never writes the in-place spelling can use the
  # option — one keyword sorter each, plus the spline `interpolate`'s.  The public 206/122 baselines
  # are untouched throughout: these are keyword arguments, not new positional methods. Then 156 → 168
  # when the adversarial review of 2026-08-30 turned the order's bijection from a claim into a type:
  # `TransferOrder`'s constructors and its `length`/`eltype`, `_validate_order`, `_tile_index`, the
  # marking kernel with its CPU and GPU twins, and `_check_transfer_order`'s third method — the one
  # that refuses a bare vector, which is where the old silent-wrong-answer entered. The last two are
  # `_order_indices`, which unwraps the guarantee at the launch site because a struct holding a device
  # array is not a bitstype and cannot cross into a kernel — a defect only the GPU suite could show.
  # 119 → 120: `_stencil_half`, the NUFFT window stencil's per-axis node offset (/bug-hunt
  # 2026-08-27). An odd width had held `half = W ÷ 2` like an even one, putting the stencil a full
  # cell off centre; the offset now follows the nearer node, so it depends on `t` and needs a
  # method of its own rather than an inline expression repeated in three places.
  # 111 → 119, all of it type stability. Two helpers reaching the folded plane with a LITERAL dimension
  # (`_folded_abs2_plane`, `_folded_cross_plane`) — `selectdim` with a runtime dimension yields a view
  # inference cannot pin, which made the spectral `inner` infer `Any`. Two extra `_fiberwise` arms from
  # dispatching on the tensor order rather than branching on it. And four `_tree_dims_reduce` /
  # `_tree_dims_components` arms taking the base arity as a TYPE parameter: every `ntuple` and the
  # closing `reshape` are sized by it, so a runtime `Int` left the whole reduction `Any` and carried
  # that into `mean`, `cov` and `integral` above R = 0. Refrozen with the reason, per decision 53.
  # 119 → 123 for the `weighted_inner` widening (decision 62): its two methods now take any
  # `SpectralKernel` rather than `Union{StoredKernel, RadialKernel}` — that is a signature change, not a
  # new method — and the +4 is the two internal helpers the widening needed, `_weight_data` and
  # `_multiplier_eltype`, at two methods each. This baseline counts every function a module owns,
  # internals included, which is exactly why it moved and why the enumerated per-generic lists did not.
  # Refrozen deliberately, with the reason, per decision 53's protocol.
  # 123 → 124: `weighted_inner` gains its tuple-of-weights method (decision 72) — several weights in
  # one traversal, which is one method on the existing generic rather than a new operation.
  # Refrozen deliberately, with the reason.
  Reductions            = 131,
  # 124 → 131: the weighted reductions' CPU leg (2026-08-30, from IT's codegen report). The weighted
  # inner products ran Base's SERIAL broadcast fold on CPU — 70× the same-size `inner` at eight
  # threads — because their GPU-first fused `sum` never met the decision-30/40 backend split. Seven
  # functions give them the same split `inner` has: `_weighted_totals_cpu` and `_weighted_column`
  # (the fixed tree over contiguous axis-1 columns), `_weighted_step` ×2 (tuple-recursive
  # accumulation — a closure here boxes the accumulator and allocated 15 MB a call), and
  # `_cpu_weight` ×3 (per-class element sources, so a radial weight is evaluated by its symbol
  # rather than through per-element Broadcasted getindex).
)

# The candidate set is the package's whole function surface, internals included, NOT `names(mod)`.
# A method defined under a QUALIFIED name — `Base.inv(kernel::SeparableKernel) = …` — creates no
# binding in the defining module, so a namespace scan cannot see it: adding `inv(::ScalarFieldSpectral)`
# to Convolution moved no number here, which is the same hole `public_surface.jl` closes for the
# ledgers. Ownership is the question, and `m.module === mod` is the only thing that answers it.
function module_method_count(mod::Module)
  total = 0
  for name in all_package_functions()
    f = _resolve_function(name)
    f === nothing && continue
    total += count(m -> m.module === mod, methods(f))
  end
  return total
end


# A name from the derived surface may live in a package module or in the external module whose generic
# the package extends, so look in both.
function _resolve_function(name::Symbol)
  # LinearAlgebra is not a test dependency, and does not need to be: the umbrella re-exports the
  # generics the package extends from it (`dot`, `cross`, `norm`, `mul!`, `transpose`).
  for mod in (GBGPeriodicFields, Base, Statistics,
              (getfield(GBGPeriodicFields, m) for m in
               (:FiberSections, :Fields, :FieldAlgebra, :DifferentialOperators,
                :Convolution, :Points, :Interpolation, :Reductions))...)
    isdefined(mod, name) || continue
    candidate = getfield(mod, name)
    candidate isa Function && return candidate
  end
  return nothing
end

@testset "derived module baselines (decision 53)" begin
  for (name, expected) in pairs(MODULE_BASELINE)
    mod = getfield(GBGPeriodicFields, name)
    measured = module_method_count(mod)
    # On a mismatch the message says what to do, because the fix is a judgement, not a repair:
    # confirm the new methods are intended and tested, then refreeze in the same commit.
    measured == expected ||
      @info "module method count moved — refreeze deliberately, with the reason" target = name expected measured
    @test measured == expected
  end
  # The two baselines count DIFFERENT denominators and must not be compared. The enumerated one above
  # is 206 methods over 28 named generics; this one is every method FieldAlgebra owns, extended `Base`
  # operators included, which is why it is larger. Comparing them would only re-freeze a coincidence.
  @test MODULE_BASELINE.FieldAlgebra > 206
end
