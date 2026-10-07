# The VALUE lane: is the computed result correct?
#
# This is the lane the suite was missing. The universal checks in `checks.jl` verify PROPERTIES — that
# a call corrupts no input, returns something finite, keeps its metadata, reproduces, and infers a
# concrete type — and a wrong answer passes every one of them. A `gradient` returning 2∇f instead of
# ∇f is finite, reproducible, metadata-preserving and type-stable. Before this lane the only operations
# whose VALUE was checked here were the seven spectral operators, 168 cells out of 85008.
#
# Each reference in `references.jl` is written from the operation's DOCUMENTED definition — the display
# formula in its own docstring — and from raw arrays, sharing no code with the implementation. That
# direction matters: an oracle copied off the code checks that the code equals itself, while one
# written from the stated contract checks that the code means what the documentation claims, so a
# disagreement is a finding either way round.

using GBGPeriodicFields
using Statistics
using LinearAlgebra
using Adapt
using Random


# A tolerance that tracks the element type and the length of the reduction. The references sum in a
# different order from the package (a plain loop against a pairwise-blocked or fused pass), so exact
# equality is not the property — agreement to the arithmetic's own precision is.
_value_tolerance(T) = T === Float32 ? 1.0f-4 : 1e-10

# The package's load-time FFT thread count (`Fields._init_fft_threads` sets `max(1, nthreads())`).
# There is no getter, so this is the value to restore TO, not a capture of what was there.
const FFTW_DEFAULT_THREADS = max(1, Threads.nthreads())

# The per-method ledger runs this lane TWICE under coverage: once whole, and once with the assertion
# tuples empty but every fixture still built. Subtracting the second from the first leaves the methods
# an ASSERTION reached, not the ones a destination allocation happened to touch on the way. Without
# that subtraction the ledger credits `similar_field` and friends as covered and reports a coverage it
# does not have — which is the failure mode this instrument exists to avoid, one level up.
const LEDGER_FIXTURES_ONLY = haskey(ENV, "GBG_LEDGER_FIXTURES_ONLY")

_as_array(x) =
  x isa GBGI.FiberSections.AbstractFiberSection ? Array(field_data(x)) :
  x isa Number                                  ? [x] :
  x isa Tuple                                   ? collect(Float64, x) :
  x isa AbstractArray                           ? Array(x) : [x]


"""
    value_agrees(got, want, rtol) -> Bool, or the exception type on a throw

The value lane's comparison step, extracted so the self-check can prove this lane can fire too.
"""
function value_agrees(got, want, rtol)
  return comparison_outcome() do
    isapprox(_as_array(got), _as_array(want); rtol = rtol)
  end
end


"""
    run_value_lane(configs) -> (disagreements, cells)

Compare every covered operation's computed result against an independent reference, over every
configuration.
"""
function run_value_lane(configs)
  println("═"^100)
  println("LANE: value correctness — the computed result against an INDEPENDENT reference")
  println("      each reference is written from the operation's documented definition, over raw")
  println("      arrays, sharing no code with the implementation")
  println("═"^100)

  disagreements = String[]
  cells = 0
  covered = Set{Symbol}()

  for config in configs
    entry_cutoff = threading_cutoff()
    set_threading_cutoff!(config.threaded ? 1 : typemax(Int))
    T, grid, layout = config.eltype, config.grid, config.layout
    # The seed axis is part of the configuration, and a lane that draws from the global RNG makes its
    # own failure labels lie: the cell says seed815 while the data came from wherever the stream was.
    Random.seed!(config.seed)
    rtol = _value_tolerance(T)
    P(R) = (grid.grid_size..., ntuple(_ -> 3, R)...)
    # Kept separately so the accessor oracles compare against the array a field was BUILT from rather
    # than against the array the accessor returns.
    raw_vector = rand(T, P(1)...)
    s  = ScalarFieldPhysical(rand(T, P(0)...), grid; layout)
    s2 = ScalarFieldPhysical(rand(T, P(0)...), grid; layout)
    u  = VectorFieldPhysical(copy(raw_vector), grid; layout)
    v  = VectorFieldPhysical(rand(T, P(1)...), grid; layout)
    A  = TensorFieldPhysical{2}(rand(T, P(2)...), grid; layout)
    B  = TensorFieldPhysical{2}(rand(T, P(2)...), grid; layout)
    signed = ScalarFieldPhysical(rand(T, P(0)...) .- T(1) / 2, grid; layout)
    w  = VectorFieldPhysical(rand(T, P(1)...), grid; layout)      # a THIRD distinct vector operand
    α, β = T(3) / 10, T(7) / 10
    ds, du, dA = field_data(s), field_data(u), field_data(A)

    # (name, what the package computes, what the definition says it should be)
    comparisons = LEDGER_FIXTURES_ONLY ? () : (
      # ── the vertical (fiberwise) algebra ──────────────────────────────────────────────────────
      (:+,          u + v,                    ref_add(du, field_data(v))),
      (:-,          u - v,                    ref_subtract(du, field_data(v))),
      (:combine!,   combine!(similar_field(u, Val(1)), α, u, β, v),
                                              ref_combine(α, du, β, field_data(v))),
      (:add!,       add!(similar_field(u, Val(1)), u, v), ref_add(du, field_data(v))),
      # THREE DISTINCT operands. The pool holds one field per tensor order, so every variadic call the
      # engine builds is `a + a + a` — an argument that is dropped, duplicated or misrouted reproduces
      # the identical correct-looking answer. The same for a BINARY fiber map, whose two sources were
      # the same object: `φ(a, a)` cannot see a swapped pair.
      (:add!,       add!(similar_field(u, Val(1)), u, v, w), ref_add(ref_add(du, field_data(v)), field_data(w))),
      (:map!,       field_data(map!((x, y) -> x - 2y, similar_field(u, Val(1)), u, v)),
                    du .- 2 .* field_data(v)),
      # A TENSOR source through a map that is NOT transpose-invariant. `map`'s fiber assembly for R = 2
      # packs nine flat scalars into a matrix in a specific order, and that packing is used by nothing
      # else — the algebra reads components directly. Every closure the suite applied to a tensor (`2x`,
      # `det`, `norm`, `tr`) is transpose-invariant, so an index swap in the packing was unobservable
      # even in principle. Extracting one off-diagonal entry is the fixture that can falsify it.
      (:map,        field_data(map(M -> M[1, 2], A)),   dA[:, :, :, 1, 2]),
      (:subtract!,  subtract!(similar_field(u, Val(1)), u, v), ref_subtract(du, field_data(v))),
      (:multiply!,  multiply!(similar_field(u, Val(1)), u, α), ref_scale(du, α)),
      (:divide!,    divide!(similar_field(u, Val(1)), u, α), ref_divide(du, α)),
      (:cross,      cross(u, v),              ref_cross(du, field_data(v))),
      (:dot,        dot(u, v),                ref_dot(du, field_data(v))),
      (:norm,       norm(u),                  ref_norm(du)),
      (:transpose,  transpose(A),             ref_transpose(dA)),
      (:sym,        sym(A),                   ref_sym(dA)),
      (:skew,       skew(A),                  ref_skew(dA)),
      (:tr,         tr(A),                    ref_trace(dA)),
      (:dev,        dev(A),                   ref_dev(dA)),
      (:det,        det(A),                   ref_det(dA)),
      (:mul!,       mul!(similar_field(u, Val(1)), A, u), ref_matvec(dA, du)),
      (:map,        map(x -> 2x, s),          ref_scale(ds, T(2))),
      # ── the L²/measure reductions ─────────────────────────────────────────────────────────────
      (:mean,       mean(s),                  only(ref_mean(ds, 0))),
      (:mean,       collect(mean(u)),         ref_mean(du, 1)),
      (:integral,   integral(s),              only(ref_integral(ds, 0, grid))),
      (:integral,   collect(integral(u)),     ref_integral(du, 1, grid)),
      (:inner,      inner(s, s2),             ref_inner(ds, field_data(s2), 0)),
      (:inner,      inner(u, v),              ref_inner(du, field_data(v), 1)),
      (:inner,      inner(A, B),              ref_inner(dA, field_data(B), 2)),
      # The TENSOR-TENSOR product against its own definition. Its only previous exercise was
      # `det(AB) = det(A)det(B)`, which the determinant's multiplicativity and transpose-invariance make
      # equally true of `BA`, `AᵀB` and `ABᵀ` — blind to exactly the confusion it looks like it tests.
      (:mul!,       field_data(mul!(similar_field(A, Val(2)), A, B)), ref_matmul(dA, field_data(B))),
      # A SIGNED scalar. Every field reaching the norm family was `rand` on [0,1), so a scalar-specialized
      # path that dropped the absolute value — returning `f` where it owes `|f|` — was correct on every
      # value the suite ever supplied.
      (:l2norm,     l2norm(signed),           ref_l2norm(field_data(signed), 0)),
      (:lpnorm,     lpnorm(signed, 1),        ref_lpnorm(field_data(signed), 1, 0)),
      (:lpnorm,     lpnorm(signed, Inf),      ref_lpnorm(field_data(signed), Inf, 0)),
      (:l2norm,     l2norm(u),                ref_l2norm(du, 1)),
      (:l2norm,     l2norm(A),                ref_l2norm(dA, 2)),
      (:lpnorm,     lpnorm(u, 1),             ref_lpnorm(du, 1, 1)),
      (:lpnorm,     lpnorm(u, 2),             ref_lpnorm(du, 2, 1)),
      (:lpnorm,     lpnorm(u, 3),             ref_lpnorm(du, 3, 1)),
      (:lpnorm,     lpnorm(u, Inf),           ref_lpnorm(du, Inf, 1)),
      (:lpnorm,     lpnorm(A, 2),             ref_lpnorm(dA, 2, 2)),
      (:var,        var(s),                   ref_var(ds)),
      (:std,        std(s),                   ref_std(ds)),
      (:cov,        Array(cov(u)),            ref_cov(du)),
      # A SIGNED fixture. Every field here is `rand`, uniform on [0, 1), where "algebraically smallest"
      # and "smallest in magnitude" coincide — so a `minimum` that reduced `abs` would have agreed with
      # its oracle in every cell. The inequality lane cannot compensate: `minimum <= maximum` holds for
      # any consistent pair, correct or not. Only these three rows change fixture, so no other oracle
      # inherits a divisor that can approach zero.
      (:maximum,    maximum(signed),          maximum(field_data(signed))),
      (:minimum,    minimum(signed),          minimum(field_data(signed))),
      (:extrema,    collect(extrema(signed)), [minimum(field_data(signed)), maximum(field_data(signed))]),
      # ── the in-place twins, against the SAME reference as their allocating siblings ────────────
      # An `f`/`f!` pair computes one operation, so one oracle serves both. Checking only the
      # allocating form leaves the kernel the in-place one actually runs unverified, and the two are
      # different code paths — the fused executor versus a broadcast.
      (:cross!,     cross!(similar_field(u, Val(1)), u, v), ref_cross(du, field_data(v))),
      (:dot!,       dot!(similar_field(s, Val(0)), u, v),   ref_dot(du, field_data(v))),
      (:norm!,      norm!(similar_field(s, Val(0)), u),     ref_norm(du)),
      (:transpose!, transpose!(similar_field(A, Val(2)), A), ref_transpose(dA)),
      (:sym!,       sym!(similar_field(A, Val(2)), A),      ref_sym(dA)),
      (:skew!,      skew!(similar_field(A, Val(2)), A),     ref_skew(dA)),
      (:dev!,       dev!(similar_field(A, Val(2)), A),      ref_dev(dA)),
      (:tr!,        tr!(similar_field(s, Val(0)), A),       ref_trace(dA)),
      (:det!,       det!(similar_field(s, Val(0)), A),      ref_det(dA)),
      (:map!,       map!(x -> 2x, similar_field(s, Val(0)), s), ref_scale(ds, T(2))),
      # ── the operator aliases ──────────────────────────────────────────────────────────────────
      (:*,          A * u,                    ref_matvec(dA, du)),
      (:*,          α * u,                    ref_scale(du, α)),
      (:/,          u / α,                    ref_divide(du, α)),
      (:×,          u × v,                    ref_cross(du, field_data(v))),
      (:⋅,          u ⋅ v,                    ref_dot(du, field_data(v))),
      # ── the accessors: the oracle is what the section was BUILT from ──────────────────────────
      (:field_data,          field_data(u),          raw_vector),
      (:field_grid,          field_grid(u) == grid,  true),
      (:field_layout,        field_layout(u) == layout, true),
      (:field_scalar_type,   field_scalar_type(u) === T, true),
      (:field_tensor_order,  field_tensor_order(A),  2),
      (:npoints,             npoints(PointSet(rand(T, 9, 3))), 9),
      (:point_value_tensor_order, point_value_tensor_order(VectorPointValues(rand(T, 9, 3))), 1),
      (:fiber_shape,         collect(fiber_shape(Val(2))), [3, 3]),
      (:field_physical_shape, collect(field_physical_shape(grid, Val(1))), [grid.grid_size..., 3]),
      (:eltype,              eltype(u) === T,        true),
      # Against the shape the grid DECLARES, not against the stored array's own shape — `Base.size(field)
      # = size(field_data(field))`, so comparing the two was `size(du) == size(du)`.
      (:size,                collect(size(u)),       [grid.grid_size..., 3]),
      (:ndims,               ndims(u),               4),
      # `copy` is defined on a Broadcasted, not on a field — that IS its method, and it is the entry
      # point every fused allocating assignment goes through.
      (:copy,                copy(Base.broadcasted(+, u, v)), ref_add(du, field_data(v))),
    )

    # ── the spectral surface: transforms, kernels, spectral reductions, transfer ────────────────
    # Built here rather than above because they need the transform plans and multipliers, and because
    # the spectral references cost a full O(N²) DFT — cheap on these grids, and the price of an oracle
    # that calls no FFT of its own.
    spectral_zero = ScalarFieldSpectral(zeros(Complex{T}, GBGI.Fields.field_spectral_shape(grid, layout, Val(0))...), grid; layout)
    plans = FieldTransformPlans(s, spectral_zero)
    multipliers = FieldSpectralMultipliers(spectral_zero)
    shape = size(field_data(spectral_zero))
    kernel_data(k) = Array(GBGI.Convolution._kernel_data(materialize_kernel(k)))
    # The coarse side of the resolution verbs (decision 85): same box, same origin, same layout, half
    # the points on each axis and never fewer than two — coarser on at least one axis for every grid
    # shape the survey enumerates, which is what the operation requires and equal grids are refused.
    coarse_size = map(n -> max(2, n ÷ 2), grid.grid_size)
    coarse_grid = Grid3D(coarse_size, grid.domain_size, grid.domain_size ./ coarse_size, grid.origin)
    coarse_shape(R) = GBGI.Fields.field_spectral_shape(coarse_grid, layout, Val(R))
    ch = ScalarFieldSpectral(randn(Complex{T}, coarse_shape(0)...), coarse_grid; layout)
    coarse_zero = ScalarFieldSpectral(zeros(Complex{T}, coarse_shape(0)...), coarse_grid; layout)
    sh = to_spectral(s, plans)
    uh = to_spectral(u, FieldTransformPlans(u, similar_field(spectral_zero, Val(1))))
    Ah = to_spectral(A, FieldTransformPlans(A, similar_field(spectral_zero, Val(2))))
    # A strictly positive field, so the reciprocal an `inv` oracle needs is well defined everywhere.
    spectral_zero_ones = ScalarFieldSpectral(ones(Complex{T}, shape...), grid; layout)
    # Per-axis fractions, not a uniform half cell — at h = Δ/2 the even-axis Nyquist factor `cos(πh/Δ)`
    # is exactly zero, which is the one term decision 28 exists for. See `invocations.jl`.
    offset = ntuple(d -> (T(3)/10, T(1)/2, T(7)/10)[d] * grid.grid_spacing[d], 3)
    raw_coordinates = rand(T, 9, 3) .* reshape(collect(grid.domain_size), 1, 3) .+
                      reshape(collect(grid.origin), 1, 3)
    raw_values = rand(T, 9)
    points = PointSet(copy(raw_coordinates))
    q = ScalarPointValues(copy(raw_values))
    # Overlapping stencils, and points the periodic wrap must bring back into the box.
    # The per-axis rate DIFFERS. At one rate the cell-fractional coordinate is identical on all three
    # axes (the spacing cancels), so every stencil weight array is numerically equal and an axis-weight
    # swap is invisible — on the fixture written to exercise overlapping stencils.
    # Every literal is `T`. A bare `0.5` is `Float64`, so on a Float32 configuration the coordinates came
    # out Float64 and the transfer refused them — correctly, since it does not convert between
    # precisions. The element type is a configuration axis and this fixture silently left it.
    clustered = PointSet(reshape(collect(grid.origin), 1, 3) .+
                         [grid.grid_spacing[d] * (T(1)/2 + (T(1)/1000 + T(1)/10000 * d) * p)
                          for p in 1:9, d in 1:3])
    outside = PointSet(raw_coordinates .+ 3 .* reshape(collect(grid.domain_size), 1, 3))
    # VECTOR and TENSOR point values. The point-value M3 algebra had no independent value oracle at all:
    # every row in this lane used field fixtures. The per-element formulas are shared with the field
    # side, so a defect there is caught — but the Points-side wrapper that chooses WHICH kernel to call
    # and in what argument order is unique to `Points.jl` and was checked by nothing. A swapped dispatch
    # produces a finite, deterministic, well-shaped wrong answer, and `metadata` does not even apply,
    # since a point-value section is not a field.
    raw_qa, raw_qb = rand(T, 9, 3), rand(T, 9, 3)
    raw_qt = rand(T, 9, 3, 3)
    qa, qb = VectorPointValues(copy(raw_qa)), VectorPointValues(copy(raw_qb))
    qt = TensorPointValues{2}(copy(raw_qt))
    # A spectrum that is NOT a real field's: one coefficient on the folded axis's zero plane is given
    # an imaginary part its mirror does not match, which is exactly the discrepancy `reality_residual`
    # exists to report and the only way to make its zero answer falsifiable.
    broken_reality = similar_field(sh, similar(field_data(sh)))
    copyto!(field_data(broken_reality), field_data(sh))
    let d = field_data(broken_reality)
      d[CartesianIndices(d)[1]] += Complex{T}(0, 1) * T(3) / 4
    end
    rng_for_scatter = MersenneTwister(20260828)
    sh2 = to_spectral(s2, plans)
    raw_values2 = rand(T, 9)
    q2 = ScalarPointValues(copy(raw_values2))
    cutoff = T(3)
    spectral_comparisons = LEDGER_FIXTURES_ONLY ? () : (
      (:to_spectral,   field_data(sh),                       ref_dft_forward(ds, grid, layout)),
      # Plans built from the storage family alone (2026-10-01), against the same literal DFT sum.
      (:to_spectral,   field_data(to_spectral(s, FieldTransformPlans(Array, grid; layout))),
                                                             ref_dft_forward(ds, grid, layout)),
      (:to_physical,   field_data(to_physical(sh, plans)),   ref_dft_inverse(field_data(sh), grid, layout)),
      # ABOVE R = 0. The transform was anchored to a raw-array oracle only for a scalar, while every
      # spectral vector and tensor operation in the suite takes its transformed input on trust — so a
      # fiber-component permutation or an axis slip specific to the BATCHED multi-component transform
      # was invisible: the operations built on it (`add!`, `multiply!`, `sym`, `transpose`, `inner`) are
      # all invariant under a relabeling applied consistently to every operand.
      (:to_spectral,   field_data(uh),                       ref_dft_forward(du, grid, layout)),
      (:to_physical,   field_data(to_physical(uh, FieldTransformPlans(u, uh))),
                                                             ref_dft_inverse(field_data(uh), grid, layout)),
      (:to_spectral,   field_data(Ah),                       ref_dft_forward(dA, grid, layout)),
      (:to_physical,   field_data(to_physical(Ah, FieldTransformPlans(A, Ah))),
                                                             ref_dft_inverse(field_data(Ah), grid, layout)),
      (:to_spectral!,  field_data(to_spectral!(similar_field(spectral_zero, Val(0)), ScalarFieldPhysical(copy(ds), grid; layout), plans)),
                                                             ref_dft_forward(ds, grid, layout)),
      # The |k|² symbol itself, materialized: `squared_wavenumber_field` was DELETED by decision 60,
      # so this row tests `radial_kernel(identity, …)`, which is that same object at a closure's cost.
      (:radial_kernel, GBGPeriodicFields.Convolution._kernel_data(materialize_kernel(radial_kernel(identity, multipliers))),
                                                             complex.(ref_squared_wavenumber(grid, layout, shape))),
      (:spectral_cutoff, kernel_data(spectral_cutoff(multipliers, cutoff)),
                                                             complex.(ref_spectral_cutoff(grid, layout, shape, cutoff))),
      (:spectral_band,   kernel_data(spectral_band(multipliers, T(1), cutoff)),
                                                             complex.(ref_spectral_band(grid, layout, shape, T(1), cutoff))),
      (:assignment_window, kernel_data(assignment_window(multipliers)),
                                                             complex.(ref_assignment_window(grid, layout, shape))),
      (:tophat_window,   kernel_data(tophat_window(multipliers, (T(0.7), T(1.3), T(2.1)))),
                                                             complex.(ref_tophat_window(grid, layout, shape, (T(0.7), T(1.3), T(2.1))))),
      # The one-number method (a cube), which the triple row above never reaches; the reference takes
      # the edge on every axis, so a method mixing up its delegation disagrees.
      (:tophat_window,   kernel_data(tophat_window(multipliers, T(0.9))),
                                                             complex.(ref_tophat_window(grid, layout, shape, (T(0.9), T(0.9), T(0.9))))),
      (:translation_kernel, kernel_data(translation_kernel(multipliers, offset)),
                                                             ref_translation_kernel(grid, layout, shape, offset)),
      # A SEPARABLE kernel, not the radial one the row above already materializes. `kernel_data` calls
      # `materialize_kernel` internally, so pointing this row at the same expression as its neighbour made
      # the two literally identical: it could never disagree, and it credited the operation in the oracle
      # registry while asserting nothing beyond what the neighbour asserts.
      (:materialize_kernel, kernel_data(translation_kernel(multipliers, offset)),
                            ref_translation_kernel(grid, layout, shape, offset)),
      # The in-place twin (decision 90), one row per compressed class it reaches: a band (radial) and
      # a translation phase (separable), each into a StoredKernel holding unrelated values.
      (:materialize_kernel!, Array(field_data(materialize_kernel!(StoredKernel(similar_field(spectral_zero_ones, Val(0))),
                                                                  spectral_band(multipliers, T(1), cutoff)).field)),
                             complex.(ref_spectral_band(grid, layout, shape, T(1), cutoff))),
      (:materialize_kernel!, Array(field_data(materialize_kernel!(StoredKernel(similar_field(spectral_zero_ones, Val(0))),
                                                                  translation_kernel(multipliers, offset)).field)),
                             ref_translation_kernel(grid, layout, shape, offset)),
      # The mean-free projector (decision 90), on a copy so the fixture survives: the reference is the
      # definition, the zero coefficient of every component cleared and nothing else touched.
      (:mean_free_projection!, field_data(mean_free_projection!(let f = similar_field(uh, Val(1))
                                                                  copyto!(field_data(f), field_data(uh)); f end)),
                               (d = copy(field_data(uh)); d[1, 1, 1, :] .= 0; d)),
      (:inner,          inner(sh, sh),                       ref_spectral_inner(field_data(sh), field_data(sh), grid, layout, 0)),
      # The Parseval-weighted fiber contraction, anchored above R = 0. At R = 0 there are `3^0 = 1`
      # components, which collapses the distinction between a weight applied per base point and one
      # applied per component — so a defect specific to `components > 1` had no raw-array anchor
      # anywhere in the suite, only relations that use `inner` on both sides.
      (:inner,          inner(uh, uh),                       ref_spectral_inner(field_data(uh), field_data(uh), grid, layout, 1)),
      (:inner,          inner(Ah, Ah),                       ref_spectral_inner(field_data(Ah), field_data(Ah), grid, layout, 2)),
      (:l2norm,         l2norm(uh),                          sqrt(ref_spectral_inner(field_data(uh), field_data(uh), grid, layout, 1))),
      (:l2norm,         l2norm(sh),                          sqrt(ref_spectral_inner(field_data(sh), field_data(sh), grid, layout, 0))),
      # The WEIGHT is rebuilt, not borrowed. This row handed `ref_weighted_inner` the package's own
      # `squared_wavenumber_field` — the same array it gave the call under test — so any defect in the
      # weights themselves (the 2π/L scaling on an anisotropic box, a permuted-fold mistake of the
      # decision-41 class, a Nyquist slip) sat identically on both sides and the row could see only
      # `weighted_inner`'s own summation. Every sibling kernel row already used `ref_squared_wavenumber`;
      # this was the one that did not. It is the same failure decision 55 recorded for the GATE's
      # `weighted_inner` oracle — fixed there, never carried across to the survey.
      (:weighted_inner, weighted_inner(sh, sh, materialize_kernel(radial_kernel(identity, multipliers))),
                        ref_weighted_inner(field_data(sh), field_data(sh),
                                           ref_squared_wavenumber(grid, layout, shape),
                                           grid, layout, 0)),
      # The SHELLS, not just their sum. Summing checks Parseval and leaves the binning — the operation's
      # entire purpose — free to put every mode in one shell.
      # `var`/`std` on a field in SPECTRAL representation. Decision 49 gave them a distinct method,
      # `inner(f,f) - mean(f)^2`, and nothing exercised it: the value lane checked only the physical
      # form, the representation-agreement list does not include them, and coverage is bookkept by
      # SYMBOL — so `:var` read as covered while a second method went untouched. The oracle is the same
      # raw-array reference the physical row uses, which is what makes this independent rather than a
      # comparison of the two package methods against each other.
      (:var,             var(sh),                             ref_var(ds)),
      (:std,             std(sh),                             ref_std(ds)),
      # The shell binning ABOVE R = 0. The fiber-contraction step of the scatter-add kernel had no
      # independent oracle: every radial row used the scalar fixture, so a defect in how a vector or
      # tensor fiber is contracted before binning produced a finite, deterministic, correctly-shaped
      # spectrum that nothing compared to anything.
      (:radial_spectrum, collect(last(radial_spectrum(uh, multipliers))),
                         ref_radial_spectrum(field_data(uh), grid, layout, 1)),
      # The TWO-FIELD co-spectrum. A distinct branch: it may be negative, and dropping the conjugate
      # would break the documented f↔g symmetry while leaving the single-field case untouched.
      (:radial_spectrum, collect(last(radial_spectrum(sh, sh2, multipliers))),
                         ref_radial_spectrum(field_data(sh), field_data(sh2), grid, layout, 0)),
      # THE SPECTRAL TRANSFER, both schemes, against the literal evaluation sum. `DirectDFT` is exact by
      # construction and `NUFFT` is exact to its tolerance, so one reference serves both — and `NUFFT`
      # had no independent value oracle at all before this.
      (:interpolate,     point_values(interpolate(sh, points, DirectDFT())),
                         ref_spectral_interpolate(field_data(sh), grid, layout,
                                                  point_positions(points), 0)),
      # ABOVE R = 0. The DFT transfer kernels carry an explicit fiber loop with hand-built linear-index
      # arithmetic that collapses to a no-op when there is one component, so a fiber-stride defect is
      # invisible at R = 0 by construction — which is the only order that was checked.
      (:interpolate,     point_values(interpolate(uh, points, DirectDFT())),
                         ref_spectral_interpolate(field_data(uh), grid, layout,
                                                  point_positions(points), 1)),
      # The cross-family `ProductKernel` (radial ∘ separable). Radial ∘ radial collapses back to a
      # radial kernel by decision 51, so composing two radials never builds this type at all; the pool
      # constructs one and nothing compared its coefficients to anything.
      (:convolve,        kernel_data(convolve(spectral_cutoff(multipliers, cutoff),
                                              translation_kernel(multipliers, offset))),
                         complex.(ref_spectral_cutoff(grid, layout, shape, cutoff)) .*
                         ref_translation_kernel(grid, layout, shape, offset)),
      # The KERNEL-COMPOSED arities (decision 32). `divergence!`/`helmholtz_projection!` with a trailing
      # kernel route through a distinct overload that fuses the convolution into the operator's own
      # pass; only the plain forms were value-checked, so a defect that dropped the kernel factor or
      # applied it with the wrong placement was indistinguishable from a correct fused pass.
      (:divergence,      field_data(divergence(uh, multipliers,
                                               spectral_cutoff(multipliers, cutoff))),
                         ref_divergence(field_data(uh), grid, layout) .*
                         ref_spectral_cutoff(grid, layout, shape, cutoff)),
      (:helmholtz_projection,
                         field_data(helmholtz_projection(uh, multipliers,
                                                         spectral_cutoff(multipliers, cutoff))),
                         ref_helmholtz(field_data(uh), grid, layout) .*
                         ref_spectral_cutoff(grid, layout, shape, cutoff)),
      (:interpolate,     point_values(interpolate(sh, points, NUFFT(sh; tol = 1e-10))),
                         ref_spectral_interpolate(ref_project_out_nyquist(field_data(sh), grid, layout),
                                                  grid, layout, point_positions(points), 0)),
      (:radial_spectrum, collect(last(radial_spectrum(sh, multipliers))),
                         ref_radial_spectrum(field_data(sh), grid, layout, 0)),
      (:interpolate,    point_values(interpolate(s, points, CatmullRom)),
                        ref_interpolate_catmull_rom(ds, grid, point_positions(points), 0)),
      (:anterpolate,    field_data(anterpolate(grid, points, q, CatmullRom)),
                        ref_anterpolate_catmull_rom(point_values(q), grid, point_positions(points), 0)),
      (:interpolate!,   point_values(interpolate!(ScalarPointValues(zeros(T, 9)), s, points, CatmullRom)),
                        ref_interpolate_catmull_rom(ds, grid, point_positions(points), 0)),
      (:anterpolate!,   field_data(anterpolate!(similar_field(s, Val(0)), points, q, CatmullRom)),
                        ref_anterpolate_catmull_rom(point_values(q), grid, point_positions(points), 0)),
      # THE GEOMETRIES THE TRANSFER EXISTS TO HANDLE, and a non-scalar fiber. Every point set compared
      # against these references was i.i.d. uniform strictly inside the box, at R = 0 — so an
      # accumulation defect in the scatter where stencils OVERLAP (last-write-wins instead of add), a
      # wrap defect for a point outside the box, and a fiber-component swap during gather were all
      # unobservable. The geometries exist in `pointset_pool` but reached only an `isfinite` check.
      (:interpolate,    point_values(interpolate(u, points, CatmullRom)),
                        ref_interpolate_catmull_rom(du, grid, point_positions(points), 1)),
      (:interpolate,    point_values(interpolate(s, clustered, CatmullRom)),
                        ref_interpolate_catmull_rom(ds, grid, point_positions(clustered), 0)),
      (:anterpolate,    field_data(anterpolate(grid, clustered, q, CatmullRom)),
                        ref_anterpolate_catmull_rom(point_values(q), grid, point_positions(clustered), 0)),
      (:anterpolate,    field_data(anterpolate(grid, outside, q, CatmullRom)),
                        ref_anterpolate_catmull_rom(point_values(q), grid, point_positions(outside), 0)),
      # ── the spectral operators and their in-place twins ───────────────────────────────────────
      (:gradient,       field_data(gradient(sh, multipliers)),  ref_gradient(field_data(sh), grid, layout)),
      # Multipliers built from the storage family alone (decision 94), against the same oracle.
      (:gradient,       field_data(gradient(sh, FieldSpectralMultipliers(Array, grid; layout))),
                        ref_gradient(field_data(sh), grid, layout)),
      # The JACOBIAN mode, with its index convention actually pinned. `gradient(vector)` was exercised
      # only through `symmetric_gradient = sym(gradient(u))`, and `sym(M) = sym(Mᵀ)` erases a transposed
      # fiber-index pair before the comparison sees it.
      (:gradient,       field_data(gradient(uh, multipliers)),
                        ref_gradient_jacobian(field_data(uh), grid, layout)),
      (:gradient!,      field_data(gradient!(similar_field(spectral_zero, Val(1)), sh, multipliers)),
                                                                ref_gradient(field_data(sh), grid, layout)),
      (:inverse_curl,   field_data(inverse_curl(uh, multipliers)),
                        ref_inverse_curl(field_data(uh), grid, layout)),
      (:inverse_curl!,  field_data(inverse_curl!(similar_field(spectral_zero, Val(1)), uh, multipliers)),
                        ref_inverse_curl(field_data(uh), grid, layout)),
      (:laplacian,      field_data(laplacian(sh, multipliers)), ref_laplacian(field_data(sh), grid, layout)),
      (:laplacian!,     field_data(laplacian!(similar_field(spectral_zero, Val(0)), sh, multipliers)),
                                                                ref_laplacian(field_data(sh), grid, layout)),
      (:inverse_laplacian,  field_data(inverse_laplacian(sh, multipliers)),
                                                                ref_inverse_laplacian(field_data(sh), grid, layout)),
      (:inverse_laplacian!, field_data(inverse_laplacian!(similar_field(spectral_zero, Val(0)), sh, multipliers)),
                                                                ref_inverse_laplacian(field_data(sh), grid, layout)),
      (:divergence,     field_data(divergence(uh, multipliers)), ref_divergence(field_data(uh), grid, layout)),
      (:divergence!,    field_data(divergence!(similar_field(spectral_zero, Val(0)), uh, multipliers)),
                                                                ref_divergence(field_data(uh), grid, layout)),
      (:curl,           field_data(curl(uh, multipliers)),      ref_curl(field_data(uh), grid, layout)),
      (:curl!,          field_data(curl!(similar_field(spectral_zero, Val(1)), uh, multipliers)),
                                                                ref_curl(field_data(uh), grid, layout)),
      (:symmetric_gradient,  field_data(symmetric_gradient(uh, multipliers)),
                                                                ref_symmetric_gradient(field_data(uh), grid, layout)),
      (:symmetric_gradient!, field_data(symmetric_gradient!(similar_field(spectral_zero, Val(2)), uh, multipliers)),
                                                                ref_symmetric_gradient(field_data(uh), grid, layout)),
      (:helmholtz_projection,  field_data(helmholtz_projection(uh, multipliers)),
                                                                ref_helmholtz(field_data(uh), grid, layout)),
      (:helmholtz_projection!, field_data(helmholtz_projection!(similar_field(spectral_zero, Val(1)), uh, multipliers)),
                                                                ref_helmholtz(field_data(uh), grid, layout)),
      # ── moving the modes two grids share (decision 85) ──────────────────────────────────
      # The oracle matches on FREQUENCY, never on the package's index arithmetic: the operation IS an
      # index map, and a re-implemented one agrees with itself while both are wrong.
      (:embed_modes!,   field_data(embed_modes!(similar_field(sh, copy(field_data(sh))), ch)),
                        ref_shared_modes(field_data(sh), field_data(ch), grid, coarse_grid, layout,
                                         one(T), zero(T))),
      (:embed_modes!,   field_data(embed_modes!(similar_field(sh, copy(field_data(sh))), ch,
                                                T(2), one(T))),
                        ref_shared_modes(field_data(sh), field_data(ch), grid, coarse_grid, layout,
                                         T(2), one(T))),
      (:extract_modes!, field_data(extract_modes!(similar_field(ch, copy(field_data(coarse_zero))), sh)),
                        ref_shared_modes(field_data(coarse_zero), field_data(sh), coarse_grid, grid,
                                         layout, one(T), zero(T))),
      (:extract_modes!, field_data(extract_modes!(similar_field(ch, copy(field_data(ch))), sh,
                                                  T(-1), one(T))),
                        ref_shared_modes(field_data(ch), field_data(sh), coarse_grid, grid, layout,
                                         T(-1), one(T))),
      # ── convolution: the coefficientwise product of Fourier symbols ───────────────────────────
      (:convolve,       field_data(convolve(sh, spectral_cutoff(multipliers, cutoff))),
                        ref_convolve(field_data(sh), complex.(ref_spectral_cutoff(grid, layout, shape, cutoff)))),
      (:convolve!,      field_data(convolve!(similar_field(spectral_zero, Val(0)), sh,
                                             spectral_cutoff(multipliers, cutoff))),
                        ref_convolve(field_data(sh), complex.(ref_spectral_cutoff(grid, layout, shape, cutoff)))),
      (:⋆,              field_data(sh ⋆ spectral_cutoff(multipliers, cutoff)),
                        ref_convolve(field_data(sh), complex.(ref_spectral_cutoff(grid, layout, shape, cutoff)))),
      (:exponential_convolve, field_data(exponential_convolve(sh, multipliers, -T(1) / 10)),
                        ref_convolve(field_data(sh), complex.(ref_exponential_symbol(grid, layout, shape, -T(1) / 10)))),
      (:exponential_convolve!, field_data(exponential_convolve!(similar_field(spectral_zero, Val(0)), sh,
                                                                multipliers, -T(1) / 10)),
                        ref_convolve(field_data(sh), complex.(ref_exponential_symbol(grid, layout, shape, -T(1) / 10)))),
      (:radial_kernel,  kernel_data(radial_kernel(k2 -> exp(-k2 / 10), multipliers)),
                        complex.(ref_exponential_symbol(grid, layout, shape, -T(1) / 10))),
      # A NON-CONSTANT kernel. The fixture was uniformly 2 everywhere and the expectation uniformly 0.5,
      # so an implementation computing `1/data[1]` and broadcasting it over the whole array passed with
      # full marks — the reciprocal's whole point is that it is elementwise.
      # `materialize_kernel` returns a `StoredKernel` since decision 60, so the field arithmetic is done
      # on the field it wraps and the sum is re-declared as a kernel.
      (:inv,            kernel_data(inv(StoredKernel(spectral_zero_ones +
                                                     materialize_kernel(spectral_cutoff(multipliers, cutoff)).field))),
                        complex.(one(T) ./ (one(T) .+ ref_spectral_cutoff(grid, layout, shape, cutoff)))),
      # The COMPOSED kernel, elementwise. Kernel-to-kernel composition was checked only by
      # "composition is associative" — and associativity holds for any associative combinator, so
      # elementwise addition, min, max, or "return the first operand" would all have passed while
      # silently replacing the coefficientwise product. The pool even builds a composed kernel; nothing
      # ever compared its coefficients to anything.
      (:convolve,       kernel_data(convolve(spectral_cutoff(multipliers, cutoff),
                                             spectral_band(multipliers, T(1), cutoff))),
                        complex.(ref_spectral_cutoff(grid, layout, shape, cutoff) .*
                                 ref_spectral_band(grid, layout, shape, T(1), cutoff))),
      # `translation_kernel!` updates a SeparableKernel in place — the compressed per-axis factors,
      # not a materialized field — so the in-place form is fed the kernel its own builder returns.
      # Built with a DIFFERENT offset, so an in-place form that writes nothing cannot pass.
      (:translation_kernel!, kernel_data(translation_kernel!(translation_kernel(multipliers,
                                                                               ntuple(d -> -offset[d], 3)),
                                                             multipliers, offset)),
                        ref_translation_kernel(grid, layout, shape, offset)),
      # C(0) = ⟨f, f⟩ is the Wiener-Khinchin dual's defining value, and it is checked against the
      # INDEPENDENT Parseval sum rather than against the package's own `inner`.
      # SHELL BY SHELL, against an independent inverse transform — the fix  received
      # and its Wiener-Khinchin dual did not. Checking only C(0) leaves every non-zero separation, and
      # the minimum-image binning that is the operation's purpose, with no reference at all.
      (:radial_correlation, collect(last(radial_correlation(sh, plans))),
                            ref_radial_correlation(field_data(sh), grid, layout)),
      # ── the remaining accessors ───────────────────────────────────────────────────────────────
      # Against the RAW matrices the objects were constructed from, not against themselves. Comparing
      # `point_positions(points)` with itself passes for a transposed, zeroed or permuted result.
      (:point_positions,   point_positions(points),         raw_coordinates),
      # The COUNTING-MEASURE inner, against a raw sum. Its only anchor was the adjointness relation
      # `M⟨Wf,q⟩ = N⟨f,Wᵀq⟩`, where it appears on one side in company with three other operations — so
      # its own `1/M` normalization was never checked directly against an array.
      (:inner,               inner(q, q2),                      sum(raw_values .* raw_values2) / 9),
      # Written out per point from the raw arrays, in the package's own index convention
      # ((Au)_i = A_ij u_j), sharing no code with it.
      (:cross,               point_values(cross(qa, qb)),
                             hcat([raw_qa[:, 2] .* raw_qb[:, 3] .- raw_qa[:, 3] .* raw_qb[:, 2],
                                   raw_qa[:, 3] .* raw_qb[:, 1] .- raw_qa[:, 1] .* raw_qb[:, 3],
                                   raw_qa[:, 1] .* raw_qb[:, 2] .- raw_qa[:, 2] .* raw_qb[:, 1]]...)),
      (:dot,                 point_values(dot(qa, qb)),
                             vec(sum(raw_qa .* raw_qb; dims = 2))),
      (:mul!,                point_values(mul!(VectorPointValues(zeros(T, 9, 3)), qt, qa)),
                             [sum(raw_qt[p, i, j] * raw_qa[p, j] for j in 1:3) for p in 1:9, i in 1:3]),
      (:transpose,           point_values(transpose(qt)),
                             [raw_qt[p, j, i] for p in 1:9, i in 1:3, j in 1:3]),
      (:tr,                  point_values(tr(qt)),
                             [raw_qt[p, 1, 1] + raw_qt[p, 2, 2] + raw_qt[p, 3, 3] for p in 1:9]),
      (:det,                 point_values(det(qt)),
                             [raw_qt[p,1,1]*(raw_qt[p,2,2]*raw_qt[p,3,3] - raw_qt[p,2,3]*raw_qt[p,3,2]) -
                              raw_qt[p,1,2]*(raw_qt[p,2,1]*raw_qt[p,3,3] - raw_qt[p,2,3]*raw_qt[p,3,1]) +
                              raw_qt[p,1,3]*(raw_qt[p,2,1]*raw_qt[p,3,2] - raw_qt[p,2,2]*raw_qt[p,3,1])
                              for p in 1:9]),
      (:point_values,        point_values(q),                   raw_values),
      # Derived independently, the way `ref_dft_forward` derives it: the folded axis keeps its
      # non-negative frequencies, every other axis its full extent. Comparing `Val(1)` against the
      # `Val(0)` shape the fixture was built from made both sides move together.
      (:field_spectral_shape, collect(GBGI.Fields.field_spectral_shape(grid, layout, Val(1))),
                              [ntuple(d -> d == layout.fft_dims[1] ? grid.grid_size[d] ÷ 2 + 1 :
                                           grid.grid_size[d], 3)..., 3]),
      (:similar_field,       collect(size(field_data(similar_field(s, Val(1))))), [grid.grid_size..., 3]),
      (:similar_point_values, npoints(similar_point_values(q, Val(0))), 9),
      (:axes,                collect(first(axes(u))),           collect(1:grid.grid_size[1])),
      # Through the package's own `getindex` on the FIELD; reading the raw array on both sides never
      # called the method under test.
      # A point with three DISTINCT coordinates and a non-first fiber component. At `[1,1,1,1]` an axis
      # transposition and a component swap both land on the same element and agree with a correct read.
      (:getindex,            u[2, 3, 1, 2],                     raw_vector[2, 3, 1, 2]),
      (:threading_cutoff,    threading_cutoff() isa Integer,    true),
      # ── the in-place forms that had no oracle ─────────────────────────────────────────────────
      # `to_physical!` may consume its spectral input as scratch (invariant 11), so it is handed a
      # copy and the reference is taken from the pristine one.
      (:to_physical!,   field_data(to_physical!(similar_field(s, Val(0)),
                                                ScalarFieldSpectral(copy(field_data(sh)), grid; layout), plans)),
                        ref_dft_inverse(field_data(sh), grid, layout)),
      (:copyto!,        field_data(copyto!(similar_field(u, Val(1)), Base.broadcasted(+, u, v))),
                        ref_add(du, field_data(v))),
      (:setindex!,      begin
                          scratch = similar_field(s, Val(0))
                          fill!(field_data(scratch), zero(T))
                          scratch[2, 3, 1] = T(7) / 2
                          field_data(scratch)[2, 3, 1]
                        end, T(7) / 2),
      # ── the configuration setters: the oracle is that the getter reports what was set, and that
      # the computed result does not move ───────────────────────────────────────────────────────
      (:set_threading_cutoff!, begin
                                 previous = threading_cutoff()
                                 set_threading_cutoff!(4096)
                                 observed = threading_cutoff()
                                 set_threading_cutoff!(previous)
                                 observed
                               end, 4096),
      # The enabled/disabled choice is a KEYWORD, and the threaded path must compute the same value
      # as the reference — which is the property threading exists to preserve.
      (:with_threading,  with_threading(enabled = true) do
                           field_data(add!(similar_field(u, Val(1)), u, v))
                         end, ref_add(du, field_data(v))),
      # Restored to the package's own load-time default. The package exposes `set_fft_threads!` and no
      # getter, so the live value cannot be read back — an earlier version claimed to restore "what it
      # was" while assigning `nthreads()` immediately before reading it, which preserved nothing. This
      # says what it actually does.
      # ── base-space motion, the reality check, and the in-place family move ────────────────────
      # These six operations shipped between decisions 69 and 76 and reached this lane through NONE of
      # its rows: the derived lanes exercised them, but the independent value oracles are hand-written
      # and nobody wrote one. An operation covered only by universal properties is checked for being
      # finite and type-stable, not for being RIGHT.
      (:wrap!,      point_positions(wrap!(PointSet(copy(raw_coordinates) .+
                                                     3 .* reshape(collect(grid.domain_size), 1, 3)), grid)),
                    ref_wrap(raw_coordinates .+ 3 .* reshape(collect(grid.domain_size), 1, 3), grid)),
      # In the universal cover: winding is PRESERVED, so a displacement that leaves the box stays out.
      (:displace!,  point_positions(displace!(PointSet(copy(raw_coordinates)), (α, qa))),
                    ref_displace(raw_coordinates, (α, point_values(qa)))),
      # TWO terms, with distinct coefficients and distinct sections. One term cannot see a fused
      # traversal that drops or double-counts a term, and equal coefficients cannot see them swapped.
      (:displace!,  point_positions(displace!(PointSet(copy(raw_coordinates)), (α, qa), (β, qb))),
                    ref_displace(raw_coordinates, (α, point_values(qa)), (β, point_values(qb)))),
      # On the torus proper: the trailing grid fuses the wrap in, so the result is the canonical
      # representative of the same displacement.
      (:displace!,  point_positions(displace!(PointSet(copy(raw_coordinates)), grid, (α, qa), (β, qb))),
                    ref_displace_wrapped(raw_coordinates, grid, (α, point_values(qa)), (β, point_values(qb)))),
      # The traversal order (decisions 78, 80), surveyed for the first time on 2026-09-06. Its promise
      # is a PERMUTATION grouped by block: row one checks the permutation, row two reads the
      # independently recomputed block keys along the order and requires them non-decreasing. The
      # in-place form rebuilds into an identity order against a scratch built for this point set, and
      # must satisfy both; `length` is the point count, and the order's `adapt_structure` hook
      # (host-to-host, the identity) must return the same indices.
      (:point_traversal_order,  sort(Array(point_traversal_order(grid, points).indices)),
                                collect(Int32(1):Int32(npoints(points)))),
      (:point_traversal_order,  ref_traversal_keys(raw_coordinates, grid, 4)[Array(point_traversal_order(grid, points).indices)],
                                sort(ref_traversal_keys(raw_coordinates, grid, 4))),
      (:point_traversal_order!, sort(Array(point_traversal_order!(PointTraversalOrder(1:npoints(points)), grid, points,
                                                                  PointTraversalOrderScratch(grid, points)).indices)),
                                collect(Int32(1):Int32(npoints(points)))),
      (:point_traversal_order!, ref_traversal_keys(raw_coordinates, grid, 4)[Array(point_traversal_order!(PointTraversalOrder(1:npoints(points)), grid, points,
                                                                  PointTraversalOrderScratch(grid, points)).indices)],
                                sort(ref_traversal_keys(raw_coordinates, grid, 4))),
      (:length,                 length(point_traversal_order(grid, points)), npoints(points)),
      (:adapt_structure,        Array(Adapt.adapt_structure(Array, point_traversal_order(grid, points)).indices),
                                Array(point_traversal_order(grid, points).indices)),
      # Zero here, where FFTW is exact at this power-of-two size — elsewhere a fresh transform satisfies
      # the condition only to round-off (PERFORMANCE finding (ar)) — and exactly twice the imaginary
      # part it is handed otherwise. The second row is what makes the first non-vacuous: a residual
      # that always returned zero would pass the first and fail this one.
      (:reality_residual, reality_residual(sh), ref_reality_residual(field_data(sh), grid, layout)),
      (:reality_residual, reality_residual(broken_reality),
                          ref_reality_residual(field_data(broken_reality), grid, layout)),
      # The projector (decision 83), through its two-argument form so the fixtures stay intact: the
      # identity on the exact spectrum, and the pair mean on the broken one.
      (:reality_projection!, field_data(reality_projection!(similar_field(sh, similar(field_data(sh))), sh)),
                             ref_reality_projection!(field_data(sh), grid, layout)),
      (:reality_projection!, field_data(reality_projection!(similar_field(sh, similar(field_data(sh))), broken_reality)),
                             ref_reality_projection!(field_data(broken_reality), grid, layout)),
      # The one-argument in-place form is its own method and needs its own value row, or the ledger
      # reports it uncovered (it did, 2026-09-06): a copy of the broken spectrum, projected in place.
      (:reality_projection!, field_data(reality_projection!(let f = similar_field(sh, similar(field_data(sh)))
                                                              copyto!(field_data(f), field_data(broken_reality)); f end)),
                             ref_reality_projection!(field_data(broken_reality), grid, layout)),
      # The in-place family move (decision 69): into a destination that already exists, within one
      # family, which must leave the destination holding exactly the source's values.
      (:adapt!,     field_data(adapt!(similar_field(u, Val(1)), u)), du),
      # Equality by value (decision 91). The oracle is the definition: two sections are equal exactly
      # when their raw arrays agree elementwise on one domain, and equal values hash alike. A copy with
      # one element perturbed is the counterexample, so each row has something to fail on.
      (:(==),       (u == similar_field(u, copy(du)), u == similar_field(u, du .+ one(T))),      (true, false)),
      (:isequal,    (isequal(u, similar_field(u, copy(du))), isequal(u, similar_field(u, du .+ one(T)))), (true, false)),
      (:hash,       hash(u) == hash(similar_field(u, copy(du))),                                 true),
      (:(==),       (points == PointSet(copy(raw_coordinates)), points == PointSet(raw_coordinates .+ one(T))), (true, false)),
      (:(==),       (qa == VectorPointValues(copy(raw_qa)), qa == VectorPointValues(raw_qa .+ one(T))),       (true, false)),
      (:hash,       hash(qa) == hash(VectorPointValues(copy(raw_qa))),                             true),
      (:(==),       (sh == similar_field(sh, copy(field_data(sh))), sh == similar_field(sh, field_data(sh) .+ one(T))), (true, false)),
      (:isequal,    (isequal(sh, similar_field(sh, copy(field_data(sh)))), isequal(sh, similar_field(sh, field_data(sh) .+ one(T)))), (true, false)),
      (:isequal,    (isequal(points, PointSet(copy(raw_coordinates))), isequal(points, PointSet(raw_coordinates .+ one(T)))), (true, false)),
      (:isequal,    (isequal(qa, VectorPointValues(copy(raw_qa))), isequal(qa, VectorPointValues(raw_qa .+ one(T)))), (true, false)),
      (:hash,       hash(points) == hash(PointSet(copy(raw_coordinates))),                        true),
      # Adapting to one's OWN storage family is the identity — the documented no-op that makes a
      # consumer's unconditional `adapt(Array, x)` free on the host — so the values must come back
      # untouched. `adapt_structure` is the hook `adapt` dispatches through, checked at the same bar.
      (:adapt,            field_data(adapt(Array, u)),                             du),
      (:adapt_structure,  field_data(Adapt.adapt_structure(Array, u)),             du),
      (:set_fft_threads!, begin
                            set_fft_threads!(1)
                            observed = field_data(to_spectral(s, plans))
                            set_fft_threads!(FFTW_DEFAULT_THREADS)
                            observed
                          end, ref_dft_forward(ds, grid, layout)),
    )

    # ── persistence, against a RAW HDF5 read ──────────────────────────────────────────────────
    # The obvious oracle for `write_field` is `read_field`, and it is worthless: a round trip through
    # one package's own pair agrees with itself however the bytes are laid out. So the file is opened
    # again and its datasets are read with the HDF5 API directly, and the largest one is compared with
    # the array that went in.
    persistence_comparisons = if HDF5_AVAILABLE && !LEDGER_FIXTURES_ONLY
      written_scheme = LalescuSpline(6; smoothness = 1, T = T)
      written_lagrange = LagrangeSpline(6; T = T)
      path = joinpath(mktempdir(), "value.h5")
      HDF5.h5open(path, "w") do file
        write_field(file, "field", u)
        write_points(file, "points", points)
        # EVERY field kind and every point-value order, not just a vector field and a point set. The
        # tag-dispatch chains in the extension are a six-way and a four-way `elseif`; a defect confined
        # to one branch either throws — which the invocation lane swallows — or reconstructs a wrong
        # object that nothing compared to anything.
        write_field(file, "scalar", s)
        write_field(file, "tensor", A)
        write_field(file, "spectral", sh)
        write_field(file, "spectral_tensor", Ah)
        write_points(file, "qv", qa)
        write_points(file, "qt", qt)
        write_scheme(file, "scheme", written_scheme)
        write_scheme(file, "lagrange", written_lagrange)
        write_scheme(file, "direct", DirectDFT())
      end
      raw_datasets(name) = begin
        found = Array[]
        HDF5.h5open(path, "r") do file
          walk(object) = for key in keys(object)
            child = object[key]
            child isa HDF5.Dataset ? Base.push!(found, Array(HDF5.read(child))) : walk(child)
          end
          walk(file[name])
        end
        found
      end
      stored_scheme_attributes = HDF5.h5open(path, "r") do file
        a = HDF5.attrs(file["scheme"])
        [Int(a["stencil_width"]), Int(a["smoothness"])]
      end
      recovered_scheme, recovered_lagrange, recovered_direct = HDF5.h5open(path, "r") do file
        (read_scheme(file, "scheme"), read_scheme(file, "lagrange"), read_scheme(file, "direct"))
      end
      stored_field = argmax(length, raw_datasets("field"))
      stored_points = argmax(length, raw_datasets("points"))
      recovered_field, recovered_points = HDF5.h5open(path, "r") do file
        (read_field(file, "field"), read_points(file, "points"))
      end
      others = HDF5.h5open(path, "r") do file
        (read_field(file, "scalar"), read_field(file, "tensor"), read_field(file, "spectral"),
         read_field(file, "spectral_tensor"), read_points(file, "qv"), read_points(file, "qt"))
      end
      # Into fields that already exist (2026-10-01): each destination filled from the same group, the
      # oracle being the raw dataset's values as above.
      filled = HDF5.h5open(path, "r") do file
        (read_field!(similar_field(u, Val(1)), file, "field"),
         read_field!(similar_field(sh, Val(0)), file, "spectral"),
         read_field!(similar_field(Ah, Val(2)), file, "spectral_tensor"))
      end
      ((:write_field,  vec(stored_field),                 vec(du)),
       (:write_points, vec(stored_points),                vec(point_positions(points))),
       (:read_field,   field_data(recovered_field),       du),
       (:read_points,  point_positions(recovered_points), point_positions(points)),
       # The round trip must return the same VALUES and the same TYPE — a tag-dispatch defect that
       # rebuilt a spectral field as a physical one, or a tensor as a vector, would otherwise survive.
       (:read_field,   field_data(others[1]),             ds),
       (:read_field,   field_data(others[2]),             dA),
       (:read_field,   field_data(others[3]),             field_data(sh)),
       (:read_field,   field_data(others[4]),             field_data(Ah)),
       (:read_field!,  field_data(filled[1]),             du),
       (:read_field!,  field_data(filled[2]),             field_data(sh)),
       (:read_field!,  field_data(filled[3]),             field_data(Ah)),
       (:read_field,   [typeof(others[1]) === typeof(s), typeof(others[2]) === typeof(A),
                        typeof(others[3]) === typeof(sh), typeof(others[4]) === typeof(Ah)],
                       [true, true, true, true]),
       (:read_points,  point_values(others[5]),           raw_qa),
       (:read_points,  point_values(others[6]),           raw_qt),
       (:read_points,  [typeof(others[5]) === typeof(qa), typeof(others[6]) === typeof(qt)],
                       [true, true]),
       # A SCHEME is a parameter record, not a section: its group carries attributes and no `data`
       # dataset (decision 75), so the raw oracle reads the attributes rather than an array. Reading
       # back with `read_scheme` alone would again be the pair agreeing with itself.
       (:write_scheme, stored_scheme_attributes,        [6, 1]),
       (:read_scheme,  [recovered_scheme.stencil_width, recovered_scheme.smoothness], [6, 1]),
       # The TYPE must survive too — the reader resolves the element type through a closed table and
       # reconstructs through the ordinary constructor, so a tag-dispatch defect rebuilds the wrong
       # family with plausible numbers.
       (:read_scheme,  [typeof(recovered_scheme) === typeof(written_scheme),
                        typeof(recovered_lagrange) === typeof(written_lagrange),
                        typeof(recovered_direct) === typeof(DirectDFT())],
                       [true, true, true]))
    else
      ()
    end

    # ── the GENERATED dispatch sweep ──────────────────────────────────────────────────────────
    # The hand-written rows above are one fixture per operation. The per-method ledger showed what
    # that leaves: the constant-operand families dispatch on representation × tensor order × argument
    # order × operand kind, and 84 of those methods were reached by nothing. A wrong dispatch there
    # returns a finite, well-shaped, WRONG answer — the class `Points.jl`'s kernel-choosing wrappers
    # already produced once — so these are driven rather than excused as "one shared builder".
    generated = Tuple{Symbol, Any, Any}[]
    if !LEDGER_FIXTURES_ONLY
      physical_sections = ((0, s, ds), (1, u, du), (2, A, dA))
      spectral_sections = ((0, sh, field_data(sh)), (1, uh, field_data(uh)), (2, Ah, field_data(Ah)))
      point_sections    = ((0, q, point_values(q)), (1, qa, point_values(qa)), (2, qt, point_values(qt)))
      constant_for(R) = R == 0 ? T(3) / 2 : R == 1 ? rand(FiberVector{T}) : rand(FiberTensor2{T})

      for (R, section, raw) in physical_sections
        c = constant_for(R)
        push!(generated, (:+, field_data(section + c), ref_add_constant_physical(raw, c, R)))
        push!(generated, (:+, field_data(c + section), ref_add_constant_physical(raw, c, R)))
        push!(generated, (:-, field_data(section - c), ref_subtract_constant_physical(raw, c, R)))
        push!(generated, (:-, field_data(c - section), ref_constant_minus_physical(raw, c, R)))
        push!(generated, (:add!, field_data(add!(similar_field(section, Val(R)), section, c)),
                          ref_add_constant_physical(raw, c, R)))
        push!(generated, (:subtract!, field_data(subtract!(similar_field(section, Val(R)), section, c)),
                          ref_subtract_constant_physical(raw, c, R)))
        push!(generated, (:subtract!, field_data(subtract!(similar_field(section, Val(R)), c, section)),
                          ref_constant_minus_physical(raw, c, R)))
      end

      for (R, section, raw) in spectral_sections
        c = constant_for(R)
        push!(generated, (:+, field_data(section + c), ref_add_constant_spectral(raw, c, grid, R)))
        push!(generated, (:+, field_data(c + section), ref_add_constant_spectral(raw, c, grid, R)))
        push!(generated, (:-, field_data(section - c), ref_subtract_constant_spectral(raw, c, grid, R)))
        push!(generated, (:-, field_data(c - section), ref_constant_minus_spectral(raw, c, grid, R)))
        push!(generated, (:add!, field_data(add!(similar_field(section, Val(R)), section, c)),
                          ref_add_constant_spectral(raw, c, grid, R)))
        push!(generated, (:subtract!, field_data(subtract!(similar_field(section, Val(R)), section, c)),
                          ref_subtract_constant_spectral(raw, c, grid, R)))
        push!(generated, (:subtract!, field_data(subtract!(similar_field(section, Val(R)), c, section)),
                          ref_constant_minus_spectral(raw, c, grid, R)))
      end

      for (R, section, raw) in point_sections
        c = constant_for(R)
        push!(generated, (:+, point_values(section + c), ref_add_constant_physical(raw, c, R)))
        push!(generated, (:+, point_values(c + section), ref_add_constant_physical(raw, c, R)))
        push!(generated, (:-, point_values(section - c), ref_subtract_constant_physical(raw, c, R)))
        push!(generated, (:-, point_values(c - section), ref_constant_minus_physical(raw, c, R)))
      end

      # The real scaling family, both argument orders and both representations.
      for (R, section, raw) in (physical_sections..., spectral_sections...)
        push!(generated, (:*, field_data(section * α), ref_scale(raw, α)))
        push!(generated, (:*, field_data(α * section), ref_scale(raw, α)))
        push!(generated, (:/, field_data(section / α), ref_divide(raw, α)))
        push!(generated, (:multiply!, field_data(multiply!(similar_field(section, Val(R)), section, α)),
                          ref_scale(raw, α)))
        push!(generated, (:divide!, field_data(divide!(similar_field(section, Val(R)), section, α)),
                          ref_divide(raw, α)))
      end
      for (R, section, raw) in point_sections
        push!(generated, (:*, point_values(section * α), ref_scale(raw, α)))
        push!(generated, (:*, point_values(α * section), ref_scale(raw, α)))
        push!(generated, (:/, point_values(section / α), ref_divide(raw, α)))
      end
    end

    # ── sweep 2: the M3 contraction families, constants and both argument orders ────────────────
    # `dot`, `cross`, `mul!` and the scalar action dispatch on (representation × tensor order ×
    # which operand is the constant × argument order). The ledger found 130 of those methods reached
    # by nothing. The references are the base-agnostic ones, so a field row and a point-value row are
    # driven from one definition rather than two that can disagree.
    if !LEDGER_FIXTURES_ONLY
      vector_carriers = ((u, du, () -> similar_field(u, Val(1)), () -> similar_field(s, Val(0)), field_data),
                         (uh, field_data(uh), () -> similar_field(uh, Val(1)), () -> similar_field(sh, Val(0)), field_data),
                         (qa, point_values(qa), () -> similar_point_values(qa, Val(1)), () -> similar_point_values(qa, Val(0)), point_values))
      tensor_carriers = ((A, dA, () -> similar_field(A, Val(2)), () -> similar_field(u, Val(1)), () -> similar_field(s, Val(0)), field_data),
                         (Ah, field_data(Ah), () -> similar_field(Ah, Val(2)), () -> similar_field(uh, Val(1)), () -> similar_field(sh, Val(0)), field_data),
                         (qt, point_values(qt), () -> similar_point_values(qt, Val(2)), () -> similar_point_values(qa, Val(1)), () -> similar_point_values(qa, Val(0)), point_values))
      cv = rand(FiberVector{T})
      ct = rand(FiberTensor2{T})

      for (section, raw, mkvec, mkscalar, data) in vector_carriers
        broadcast_v = _fiber_broadcast(cv, size(raw), 1)
        push!(generated, (:dot, data(dot(section, cv)), ref_dot_generic(raw, broadcast_v)))
        push!(generated, (:dot, data(dot(cv, section)), ref_dot_generic(broadcast_v, raw)))
        push!(generated, (:dot!, data(dot!(mkscalar(), section, cv)), ref_dot_generic(raw, broadcast_v)))
        push!(generated, (:dot!, data(dot!(mkscalar(), cv, section)), ref_dot_generic(broadcast_v, raw)))
        push!(generated, (:cross, data(cross(section, cv)), ref_cross_generic(raw, broadcast_v)))
        push!(generated, (:cross, data(cross(cv, section)), ref_cross_generic(broadcast_v, raw)))
        push!(generated, (:cross!, data(cross!(mkvec(), section, cv)), ref_cross_generic(raw, broadcast_v)))
        push!(generated, (:cross!, data(cross!(mkvec(), cv, section)), ref_cross_generic(broadcast_v, raw)))
        push!(generated, (:mul!, data(mul!(mkvec(), ct, section)),
                          ref_matvec_generic(_fiber_broadcast(ct, (size(raw)..., 3), 2), raw)))
      end

      for (section, raw, mktensor, mkvec, mkscalar, data) in tensor_carriers
        broadcast_t = _fiber_broadcast(ct, size(raw), 2)
        push!(generated, (:dot, data(dot(section, ct)), ref_tensor_inner_generic(raw, broadcast_t)))
        push!(generated, (:dot, data(dot(ct, section)), ref_tensor_inner_generic(broadcast_t, raw)))
        push!(generated, (:dot!, data(dot!(mkscalar(), section, ct)), ref_tensor_inner_generic(raw, broadcast_t)))
        push!(generated, (:dot!, data(dot!(mkscalar(), ct, section)), ref_tensor_inner_generic(broadcast_t, raw)))
        push!(generated, (:mul!, data(mul!(mktensor(), section, ct)), ref_matmul_generic(raw, broadcast_t)))
        push!(generated, (:mul!, data(mul!(mktensor(), ct, section)), ref_matmul_generic(broadcast_t, raw)))
        push!(generated, (:mul!, data(mul!(mkvec(), section, cv)),
                          ref_matvec_generic(raw, _fiber_broadcast(cv, (_base_shape(raw, 2)..., 3), 1))))
        push!(generated, (:mul!, data(mul!(mkvec(), cv, section)),
                          ref_vecmat_generic(_fiber_broadcast(cv, (_base_shape(raw, 2)..., 3), 1), raw)))
        push!(generated, (:*, data(section * ct), ref_matmul_generic(raw, broadcast_t)))
        push!(generated, (:*, data(ct * section), ref_matmul_generic(broadcast_t, raw)))
      end
    end

    # ── sweep 3: the scalar-field action and the remaining products ─────────────────────────────
    # Multiplying a section by a SCALAR SECTION (not a number) is a separate dispatch family from the
    # real scaling above, and it exists for fields and point-values, in both argument orders, with the
    # scalar-by-scalar case its own method. The right action `u * A` is also distinct from `A * u`.
    if !LEDGER_FIXTURES_ONLY
      scalar_products = ((s, ds, s2, field_data(s2), () -> similar_field(s, Val(0)), field_data),
                         (q, point_values(q), q2, point_values(q2), () -> similar_point_values(q, Val(0)), point_values))
      for (scalar, sraw, other, oraw, mkscalar, data) in scalar_products
        push!(generated, (:multiply!, data(multiply!(mkscalar(), scalar, other)), sraw .* oraw))
        push!(generated, (:*, data(scalar * other), sraw .* oraw))
        push!(generated, (:divide!, data(divide!(mkscalar(), scalar, other)), sraw ./ oraw))
        push!(generated, (:/, data(scalar / other), sraw ./ oraw))
      end

      # A vector or tensor section scaled by a SCALAR section, both argument orders.
      for (section, raw, mk, data, scalar, sraw) in
          ((u, du, () -> similar_field(u, Val(1)), field_data, s, ds),
           (A, dA, () -> similar_field(A, Val(2)), field_data, s, ds),
           (qa, point_values(qa), () -> similar_point_values(qa, Val(1)), point_values, q, point_values(q)),
           (qt, point_values(qt), () -> similar_point_values(qt, Val(2)), point_values, q, point_values(q)))
        order = ndims(raw) - ndims(sraw)
        widened = _fiber_broadcast_scalar(sraw, size(raw), order)
        push!(generated, (:multiply!, data(multiply!(mk(), section, scalar)), raw .* widened))
        push!(generated, (:multiply!, data(multiply!(mk(), scalar, section)), widened .* raw))
        push!(generated, (:*, data(section * scalar), raw .* widened))
        push!(generated, (:*, data(scalar * section), widened .* raw))
        push!(generated, (:divide!, data(divide!(mk(), section, scalar)), raw ./ widened))
        push!(generated, (:/, data(section / scalar), raw ./ widened))
      end

      # The remaining products: tensor·vector and the vector·tensor RIGHT action, section against
      # section and against a constant, over all three carriers.
      # SECTION against SECTION is nonlinear in the fields, so invariant 1 puts it in physical
      # representation and on point-values only — a spectral pair is a deliberate absence, not a gap.
      for (vec, vraw, ten, traw, data) in ((u, du, A, dA, field_data),
                                           (qa, point_values(qa), qt, point_values(qt), point_values))
        push!(generated, (:*, data(ten * vec), ref_matvec_generic(traw, vraw)))
        push!(generated, (:*, data(vec * ten), ref_vecmat_generic(vraw, traw)))
        push!(generated, (:*, data(ten * ten), ref_matmul_generic(traw, traw)))
      end
      # A CONSTANT operand is linear in the field, so these exist in both representations.
      for (vec, vraw, ten, traw, data) in ((u, du, A, dA, field_data),
                                           (uh, field_data(uh), Ah, field_data(Ah), field_data),
                                           (qa, point_values(qa), qt, point_values(qt), point_values))
        push!(generated, (:*, data(vec * ct), ref_vecmat_generic(vraw, _fiber_broadcast(ct, (_base_shape(vraw, 1)..., 3, 3), 2))))
        push!(generated, (:*, data(ten * cv), ref_matvec_generic(traw, _fiber_broadcast(cv, (_base_shape(traw, 2)..., 3), 1))))
      end
    end

    # ── sweep 4: a fiber CONSTANT against a SCALAR section, and the point-value scalar action ────
    # `φ * v` where φ is a scalar section and v a fiber constant RAISES the order, and it dispatches
    # separately per representation, per constant kind and per argument order. Linear in the field, so
    # it exists in spectral representation too.
    if !LEDGER_FIXTURES_ONLY
      scalar_carriers = ((s, ds, () -> similar_field(s, Val(0)), () -> similar_field(u, Val(1)), () -> similar_field(A, Val(2)), field_data),
                         (sh, field_data(sh), () -> similar_field(sh, Val(0)), () -> similar_field(uh, Val(1)), () -> similar_field(Ah, Val(2)), field_data),
                         (q, point_values(q), () -> similar_point_values(q, Val(0)), () -> similar_point_values(qa, Val(1)), () -> similar_point_values(qt, Val(2)), point_values))
      for (scalar, sraw, mk0, mk1, mk2, data) in scalar_carriers
        base = size(sraw)
        wide1 = _fiber_broadcast_scalar(sraw, (base..., 3), 1)
        wide2 = _fiber_broadcast_scalar(sraw, (base..., 3, 3), 2)
        bv = _fiber_broadcast(cv, (base..., 3), 1)
        bt = _fiber_broadcast(ct, (base..., 3, 3), 2)
        push!(generated, (:*, data(scalar * cv), wide1 .* bv))
        push!(generated, (:*, data(cv * scalar), bv .* wide1))
        push!(generated, (:*, data(scalar * ct), wide2 .* bt))
        push!(generated, (:*, data(ct * scalar), bt .* wide2))
        push!(generated, (:multiply!, data(multiply!(mk1(), scalar, cv)), wide1 .* bv))
        push!(generated, (:multiply!, data(multiply!(mk1(), cv, scalar)), bv .* wide1))
        push!(generated, (:multiply!, data(multiply!(mk2(), scalar, ct)), wide2 .* bt))
        push!(generated, (:multiply!, data(multiply!(mk2(), ct, scalar)), bt .* wide2))
        # A scalar-by-scalar product and any division by a scalar section are NONLINEAR in the
        # field, so both are physical-only — in spectral representation the coefficientwise product
        # is a convolution and is offered under that name, never as `*` (invariant 1).
        if !(scalar === sh)
          push!(generated, (:multiply!, data(multiply!(mk0(), scalar, scalar)), sraw .* sraw))
          push!(generated, (:/, data(cv / scalar), bv ./ wide1))
          push!(generated, (:/, data(ct / scalar), bt ./ wide2))
          push!(generated, (:divide!, data(divide!(mk1(), cv, scalar)), bv ./ wide1))
          push!(generated, (:divide!, data(divide!(mk2(), ct, scalar)), bt ./ wide2))
          push!(generated, (:/, data(α / scalar), α ./ sraw))
          push!(generated, (:divide!, data(divide!(mk0(), α, scalar)), α ./ sraw))
        end
      end

      # The point-value real scaling, with the in-place verbs: the field side of this was swept
      # already, the point side reached nothing.
      for (section, raw, mk, data) in ((q, point_values(q), () -> similar_point_values(q, Val(0)), point_values),
                                       (qa, point_values(qa), () -> similar_point_values(qa, Val(1)), point_values),
                                       (qt, point_values(qt), () -> similar_point_values(qt, Val(2)), point_values))
        push!(generated, (:multiply!, data(multiply!(mk(), section, α)), ref_scale(raw, α)))
        push!(generated, (:multiply!, data(multiply!(mk(), α, section)), ref_scale(raw, α)))
        push!(generated, (:divide!, data(divide!(mk(), section, α)), ref_divide(raw, α)))
      end
    end

    # ── sweep 5: the type-level accessors, the point-value reductions and the fiber decompositions ─
    # The tail the ledger exposed: `eltype`/`ndims` have TYPE-level methods a value never reaches,
    # the order statistics and `std`/`var` exist on point-values as well as fields, `norm!` writes a
    # scalar point section from each order, and sym/skew/dev have point-value twins.
    if !LEDGER_FIXTURES_ONLY
      # `eltype` reports the STORAGE element type, so a field in spectral representation reports
      # `Complex{T}` — which is invariant 2's "complex arrays are storage detail" showing through an
      # accessor rather than contradicting it. The base of a point-value section is one axis, so
      # `ndims` counts one plus the tensor order.
      # Asserted as BOOLEANS, the lane's own convention for an identity: its comparator is numeric
      # and a `Type` is not a number.
      push!(generated, (:eltype, [eltype(typeof(s)) === T, eltype(typeof(sh)) === Complex{T},
                                  eltype(typeof(q)) === T], [true, true, true]))
      push!(generated, (:ndims, [ndims(typeof(s)), ndims(typeof(u)), ndims(typeof(A))], [3, 4, 5]))
      push!(generated, (:ndims, [ndims(typeof(q)), ndims(typeof(qa)), ndims(typeof(qt))], [1, 2, 3]))
      push!(generated, (:size, collect(size(qa)), collect(size(point_values(qa)))))

      pq = point_values(q)
      push!(generated, (:extrema, collect(extrema(q)), collect(extrema(pq))))
      push!(generated, (:maximum, maximum(q), maximum(pq)))
      push!(generated, (:minimum, minimum(q), minimum(pq)))
      push!(generated, (:std, std(q), ref_std(pq)))
      push!(generated, (:var, var(q), ref_var(pq)))
      # The MAPPED order statistics over a point-value section, the fused form with no intermediate.
      push!(generated, (:maximum, maximum(norm, qa), maximum(ref_norm_generic(point_values(qa)))))
      push!(generated, (:minimum, minimum(norm, qa), minimum(ref_norm_generic(point_values(qa)))))
      push!(generated, (:extrema, collect(extrema(norm, qa)), collect(extrema(ref_norm_generic(point_values(qa))))))

      # `norm!` into a scalar point section, from each tensor order.
      push!(generated, (:norm!, point_values(GBGPeriodicFields.norm!(similar_point_values(q, Val(0)), qa)),
                        ref_norm_generic(point_values(qa))))
      push!(generated, (:norm!, point_values(GBGPeriodicFields.norm!(similar_point_values(q, Val(0)), qt)),
                        ref_frobenius_generic(point_values(qt))))

      # The fiber decompositions on point-values, in place and allocating.
      push!(generated, (:sym, point_values(sym(qt)), ref_sym_generic(point_values(qt))))
      push!(generated, (:skew, point_values(skew(qt)), ref_skew_generic(point_values(qt))))
      push!(generated, (:sym!, point_values(sym!(similar_point_values(qt, Val(2)), qt)), ref_sym_generic(point_values(qt))))
      push!(generated, (:skew!, point_values(skew!(similar_point_values(qt, Val(2)), qt)), ref_skew_generic(point_values(qt))))
      push!(generated, (:dev!, point_values(dev!(similar_point_values(qt, Val(2)), qt)), ref_dev_generic(point_values(qt))))
    end

    # ── sweep 6: the storage hook, kernel composition, and the spectral scatter's arities ────────
    if !LEDGER_FIXTURES_ONLY
      # `adapt_structure` is the hook `adapt` dispatches through, one method per carrier. Adapting to
      # the family a section already occupies is the documented identity, so the values must return
      # untouched — which is exactly what a consumer's unconditional `adapt(Array, x)` relies on.
      push!(generated, (:adapt_structure, field_data(Adapt.adapt_structure(Array, sh)), field_data(sh)))
      push!(generated, (:adapt_structure, point_values(Adapt.adapt_structure(Array, qa)), point_values(qa)))
      push!(generated, (:adapt_structure, point_positions(Adapt.adapt_structure(Array, points)),
                        point_positions(points)))
      push!(generated, (:adapt_structure, Adapt.adapt_structure(Array, multipliers).wavenumber_1,
                        multipliers.wavenumber_1))
      radial_k = spectral_cutoff(multipliers, cutoff)
      separable_k = assignment_window(multipliers)
      stored_k = materialize_kernel(separable_k)
      product_k = convolve(radial_k, separable_k)
      for (name, kernel) in ((:radial, radial_k), (:separable, separable_k), (:stored, stored_k), (:product, product_k))
        push!(generated, (:adapt_structure,
                          Array(kernel_data(Adapt.adapt_structure(Array, kernel))),
                          Array(kernel_data(kernel))))
      end

      # Composing two kernels of the same class stays in that class; the composite must apply as the
      # coefficientwise product of the two symbols, which is what `convolve` on two kernels means.
      push!(generated, (:convolve, Array(kernel_data(convolve(radial_k, radial_k))),
                        Array(kernel_data(radial_k)) .* Array(kernel_data(radial_k))))
      push!(generated, (:convolve, Array(kernel_data(convolve(separable_k, separable_k))),
                        Array(kernel_data(separable_k)) .* Array(kernel_data(separable_k))))
      # Both argument orders APPLY a kernel to a field and must agree (decision 60).
      push!(generated, (:convolve, field_data(convolve(radial_k, sh)),
                        ref_convolve(field_data(sh), Array(kernel_data(radial_k)))))
      push!(generated, (:⋆, field_data(sh ⋆ radial_k),
                        ref_convolve(field_data(sh), Array(kernel_data(radial_k)))))

      # The lazy exponential kernel's TWO-OPERAND form: a weighted combination convolved in one pass.
      exponent = -T(1) / 10
      symbol = complex.(ref_exponential_symbol(grid, layout, size(field_data(sh))[1:3], exponent))
      push!(generated, (:exponential_convolve!,
                        field_data(exponential_convolve!(similar_field(sh, Val(0)), α, sh, β, sh2,
                                                         multipliers, exponent)),
                        ref_convolve(α .* field_data(sh) .+ β .* field_data(sh2), symbol)))

      # The spectral SCATTER at its arities, both schemes, against the adjoint sum — compared on the
      # RESOLVED BAND. The rfft Nyquist is projected out so the gather/scatter pair stay exact
      # adjoints, so the naive sum and the package agree everywhere except those planes, by design:
      # measured here, 55 of 160 cells differ before the projection and none after.
      band(x) = ref_project_out_nyquist(x, grid, layout)
      for scheme in (DirectDFT(), NUFFT(sh; tol = 1e-10))
        base = zeros(Complex{T}, size(field_data(sh)))
        push!(generated, (:anterpolate!,
                          band(field_data(anterpolate!(ScalarFieldSpectral(copy(base), grid; layout), points, q, scheme))),
                          band(ref_spectral_anterpolate(base, point_positions(points), point_values(q),
                                                        grid, layout, 0, one(T), zero(T)))))
        seeded = randn(rng_for_scatter, Complex{T}, size(field_data(sh)))
        push!(generated, (:anterpolate!,
                          band(field_data(anterpolate!(ScalarFieldSpectral(copy(seeded), grid; layout), points, q, scheme, α, β))),
                          band(ref_spectral_anterpolate(seeded, point_positions(points), point_values(q),
                                                        grid, layout, 0, α, β))))
      end
    end

    # ── sweep 7: the tail the ledger named one method at a time ──────────────────────────────────
    if !LEDGER_FIXTURES_ONLY
      # Unary plus and minus, on a field and on a point-value section.
      push!(generated, (:+, field_data(+s), ds))
      push!(generated, (:-, field_data(-s), -ds))
      push!(generated, (:+, point_values(+qa), point_values(qa)))
      push!(generated, (:-, point_values(-qa), -point_values(qa)))

      # The VARIADIC forms, three distinct operands so a dropped or duplicated argument shows.
      push!(generated, (:+, point_values(qa + qb + qa), point_values(qa) .+ point_values(qb) .+ point_values(qa)))
      push!(generated, (:-, point_values(qa - qb - qa), point_values(qa) .- point_values(qb) .- point_values(qa)))
      push!(generated, (:add!, point_values(add!(similar_point_values(qa, Val(1)), qa, qb, qa)),
                        point_values(qa) .+ point_values(qb) .+ point_values(qa)))
      push!(generated, (:subtract!, point_values(subtract!(similar_point_values(qa, Val(1)), qa, qb, qa)),
                        point_values(qa) .- point_values(qb) .- point_values(qa)))

      # A Real against a SCALAR point section, both argument orders.
      push!(generated, (:add!, point_values(add!(similar_point_values(q, Val(0)), q, α)), point_values(q) .+ α))
      push!(generated, (:add!, point_values(add!(similar_point_values(q, Val(0)), α, q)), α .+ point_values(q)))
      push!(generated, (:subtract!, point_values(subtract!(similar_point_values(q, Val(0)), q, α)), point_values(q) .- α))
      push!(generated, (:subtract!, point_values(subtract!(similar_point_values(q, Val(0)), α, q)), α .- point_values(q)))

      # `adapt!` into a destination of the family it already occupies: the values must arrive intact.
      push!(generated, (:adapt!, field_data(adapt!(similar_field(sh, Val(0)), sh)), field_data(sh)))
      push!(generated, (:adapt!, point_values(adapt!(similar_point_values(qa, Val(1)), qa)), point_values(qa)))
      push!(generated, (:adapt!, point_positions(adapt!(PointSet(similar(point_positions(points))), points)),
                        point_positions(points)))

      # The Frobenius pairing of two TENSOR sections, and its in-place and operator spellings.
      push!(generated, (:dot, field_data(dot(A, B)), ref_tensor_inner_generic(dA, field_data(B))))
      push!(generated, (:⋅, field_data(A ⋅ B), ref_tensor_inner_generic(dA, field_data(B))))
      push!(generated, (:dot!, field_data(dot!(similar_field(s, Val(0)), A, B)), ref_tensor_inner_generic(dA, field_data(B))))
      push!(generated, (:dot, point_values(dot(qt, qt)), ref_tensor_inner_generic(point_values(qt), point_values(qt))))
      push!(generated, (:⋅, point_values(qt ⋅ qt), ref_tensor_inner_generic(point_values(qt), point_values(qt))))
      push!(generated, (:dot!, point_values(dot!(similar_point_values(q, Val(0)), qt, qt)),
                        ref_tensor_inner_generic(point_values(qt), point_values(qt))))

      # A fiber constant on the LEFT of a section of the complementary order.
      for (vec, vraw, ten, traw, data) in ((u, du, A, dA, field_data),
                                           (uh, field_data(uh), Ah, field_data(Ah), field_data),
                                           (qa, point_values(qa), qt, point_values(qt), point_values))
        push!(generated, (:*, data(ct * vec), ref_matvec_generic(_fiber_broadcast(ct, (_base_shape(vraw, 1)..., 3, 3), 2), vraw)))
        push!(generated, (:*, data(cv * ten), ref_vecmat_generic(_fiber_broadcast(cv, (_base_shape(traw, 2)..., 3), 1), traw)))
      end

      # The tensor DIVERGENCE in spectral representation, plain and kernel-composed.
      radial_k2 = spectral_cutoff(multipliers, cutoff)
      push!(generated, (:divergence, field_data(divergence(Ah, multipliers)),
                        ref_divergence_tensor(field_data(Ah), grid, layout)))
      push!(generated, (:divergence!, field_data(divergence!(similar_field(uh, Val(1)), Ah, multipliers)),
                        ref_divergence_tensor(field_data(Ah), grid, layout)))
      push!(generated, (:divergence, field_data(divergence(Ah, multipliers, radial_k2)),
                        ref_convolve(ref_divergence_tensor(field_data(Ah), grid, layout),
                                     _fiber_broadcast_scalar(Array(kernel_data(radial_k2)),
                                                             size(field_data(uh)), 1))))

      # `map!` with α/β, and its variadic point form.
      push!(generated, (:map!, field_data(map!(x -> 2x, similar_field(s, Val(0)), s, α, zero(T))),
                        α .* (2 .* ds)))
      push!(generated, (:map!, point_values(map!(x -> 2x, similar_point_values(q, Val(0)), q, α, zero(T))),
                        α .* (2 .* point_values(q))))
      push!(generated, (:map!, point_values(map!((x, y) -> x - 2y, similar_point_values(qa, Val(1)), qa, qb)),
                        point_values(qa) .- 2 .* point_values(qb)))

      # A scalar-by-scalar product written into a destination of the general field type.
      push!(generated, (:multiply!, field_data(multiply!(similar_field(s, Val(0)), s, s2)), ds .* field_data(s2)))
      push!(generated, (:multiply!, point_values(multiply!(similar_point_values(q, Val(0)), q, q2)),
                        point_values(q) .* point_values(q2)))

      # Reductions the tail named: the spectral `integral`, the mapped form, and the whole-section
      # order statistics.
      push!(generated, (:integral, integral(sh), ref_integral(ds, 0, grid)))
      push!(generated, (:integral, integral(abs2, s), ref_integral(abs2.(ds), 0, grid)))
      push!(generated, (:extrema, collect(extrema(s)), collect(extrema(ds))))
      push!(generated, (:var, var(s), ref_var(ds)))
      push!(generated, (:ndims, [ndims(qa), ndims(typeof(sh))], [2, 3]))

      # Kernel inversion for the compressed classes, and the single-field weighted inner.
      separable_k2 = assignment_window(multipliers)
      push!(generated, (:inv, Array(kernel_data(inv(separable_k2))), 1 ./ Array(kernel_data(separable_k2))))
      push!(generated, (:weighted_inner, weighted_inner(sh, radial_k2),
                        ref_weighted_inner(field_data(sh), field_data(sh),
                                           Array(kernel_data(radial_k2)), grid, layout, 0)))

      # The preserving scratch arity of the inverse transform (decision 64) — the source must SURVIVE.
      scratch = similar_field(sh, similar(field_data(sh)))
      before = copy(field_data(sh))
      recovered = to_physical!(similar_field(s, Val(0)), sh, plans, scratch)
      push!(generated, (:to_physical!, field_data(recovered), ref_dft_inverse(field_data(sh), grid, layout)))
      push!(generated, (:to_physical!, field_data(sh), before))
    end

    # ── sweep 8: the last cells the ledger named ─────────────────────────────────────────────────
    if !LEDGER_FIXTURES_ONLY
      radial_a = spectral_cutoff(multipliers, cutoff)
      radial_b = spectral_band(multipliers, T(1), T(3))
      # Composing two radials whose multiplier sets are the SAME canonical object collapses into a
      # single radial (decision 61, decided in the type domain). Two radials over sets that are not
      # known to be the same take the other method and keep both operands — reached here by building
      # the second set through the explicit six-array constructor, which cannot claim canonicity.
      push!(generated, (:convolve, Array(kernel_data(convolve(radial_a, radial_b))),
                        Array(kernel_data(radial_a)) .* Array(kernel_data(radial_b))))
      noncanonical = FieldSpectralMultipliers(grid, layout,
                                              copy(multipliers.wavenumber_1), copy(multipliers.wavenumber_2),
                                              copy(multipliers.wavenumber_3), copy(multipliers.squared_wavenumber_1),
                                              copy(multipliers.squared_wavenumber_2), copy(multipliers.squared_wavenumber_3))
      radial_c = spectral_band(noncanonical, T(1), T(3))
      push!(generated, (:convolve, Array(kernel_data(convolve(radial_a, radial_c))),
                        Array(kernel_data(radial_a)) .* Array(kernel_data(radial_c))))
      push!(generated, (:⋆, Array(kernel_data(radial_a ⋆ radial_c)),
                        Array(kernel_data(radial_a)) .* Array(kernel_data(radial_c))))
      # `inv` of a product kernel is the product of the reciprocals — built from factors with NO
      # ZEROS, since a sharp cutoff's reciprocal is not a kernel at all. A smooth radial symbol and
      # the displacement phase (unit modulus everywhere) are both nonvanishing by construction.
      smooth_radial = radial_kernel(k2 -> exp(-T(1) / 100 * k2), multipliers)
      phase = translation_kernel(multipliers, ntuple(d -> T(1) / 2 * grid.grid_spacing[d], 3))
      product_kernel = convolve(smooth_radial, phase)
      push!(generated, (:inv, Array(kernel_data(inv(product_kernel))), 1 ./ Array(kernel_data(product_kernel))))

      # The exponential kernel's OFFSET arities: exp(c|k|² + s·ŵ), with ŵ a per-mode real field
      # entered as scale × field, in the single-operand and two-operand forms.
      exponent2 = -T(1) / 20
      offset_scale = T(3) / 10
      offset_field = ScalarFieldSpectral(real.(field_data(sh)) .+ zero(Complex{T}), grid; layout)
      symbol2 = complex.(ref_exponential_symbol(grid, layout, size(field_data(sh))[1:3], exponent2)) .*
                exp.(offset_scale .* real.(field_data(offset_field)))
      push!(generated, (:exponential_convolve,
                        field_data(exponential_convolve(sh, multipliers, exponent2, offset_scale, offset_field)),
                        ref_convolve(field_data(sh), symbol2)))
      push!(generated, (:exponential_convolve!,
                        field_data(exponential_convolve!(similar_field(sh, Val(0)), sh, multipliers,
                                                         exponent2, offset_scale, offset_field)),
                        ref_convolve(field_data(sh), symbol2)))
      push!(generated, (:exponential_convolve!,
                        field_data(exponential_convolve!(similar_field(sh, Val(0)), sh, multipliers,
                                                         exponent2, offset_scale, offset_field, α, zero(T))),
                        α .* ref_convolve(field_data(sh), symbol2)))
      push!(generated, (:exponential_convolve!,
                        field_data(exponential_convolve!(similar_field(sh, Val(0)), α, sh, β, sh2,
                                                         multipliers, exponent2, offset_scale, offset_field)),
                        ref_convolve(α .* field_data(sh) .+ β .* field_data(sh2), symbol2)))
      # A RADIAL offset (2026-10-01): ŵ = the band indicator, a function of |k|² alone, evaluated per
      # mode. The reference is the same exp(c|k|² + s·ŵ) written over the raw squared wavenumber, on the
      # scalar route and, through the vector field uh, the per-mode route.
      radial_offset = spectral_band(multipliers, T(1), cutoff)
      band_values = ref_spectral_band(grid, layout, size(field_data(sh))[1:3], T(1), cutoff)
      symbol3 = complex.(ref_exponential_symbol(grid, layout, size(field_data(sh))[1:3], exponent2) .*
                         exp.(offset_scale .* band_values))
      push!(generated, (:exponential_convolve,
                        field_data(exponential_convolve(sh, multipliers, exponent2, offset_scale, radial_offset)),
                        ref_convolve(field_data(sh), symbol3)))
      push!(generated, (:exponential_convolve!,
                        field_data(exponential_convolve!(similar_field(uh, Val(1)), uh, multipliers,
                                                         exponent2, offset_scale, radial_offset)),
                        field_data(uh) .* symbol3))
      push!(generated, (:exponential_convolve!,
                        field_data(exponential_convolve!(similar_field(uh, Val(1)), α, uh, β, uh,
                                                         multipliers, exponent2, offset_scale, radial_offset)),
                        (α .* field_data(uh) .+ β .* field_data(uh)) .* symbol3))

      # The two-field CO-correlation, the Wiener–Khinchin dual of the co-spectrum.
      separations, cross_correlation = radial_correlation(sh, sh2, plans)
      _, self_correlation = radial_correlation(sh, sh, plans)
      push!(generated, (:radial_correlation, cross_correlation,
                        ref_radial_correlation(field_data(sh), field_data(sh2), grid, layout, 0)))
      push!(generated, (:radial_correlation, self_correlation,
                        ref_radial_correlation(field_data(sh), field_data(sh), grid, layout, 0)))

      # The FIBER-level decompositions, on a bare constant rather than a section.
      push!(generated, (:sym, Array(sym(ct)), (Array(ct) .+ Array(ct)') ./ 2))
      push!(generated, (:skew, Array(skew(ct)), (Array(ct) .- Array(ct)') ./ 2))

    end

    # ── sweep 9: caller-chosen operand counts (decision 88) ────────────────────────────────────
    # `add!`/`subtract!`, `map!`, `displace!` and the tuple `weighted_inner` work through their
    # operands in fixed groups — eight, or four weights — so every row above, at three operands or
    # fewer, stays inside one group and cannot see the grouping. These go past the group size and past
    # 32, where Julia leaves its specialized tuple path, and compare against the ungrouped arithmetic
    # on raw arrays. The aliased rows make the destination an operand of a LATER group, which the
    # grouped pass must copy before the first group overwrites it.
    if !LEDGER_FIXTURES_ONLY
      for n in (9, 33)
        many = [VectorFieldPhysical(rand(T, P(1)...), grid; layout) for _ in 1:n]
        raw = [copy(field_data(f)) for f in many]
        push!(generated, (:add!, field_data(add!(similar_field(many[1], Val(1)), many...)), foldl(ref_add, raw)))
        push!(generated, (:subtract!, field_data(subtract!(similar_field(many[1], Val(1)), many...)),
                          foldl((x, y) -> x .- y, raw)))
        aliased = [similar_field(f, copy(field_data(f))) for f in many]
        push!(generated, (:add!, field_data(add!(aliased[n], aliased...)), foldl(ref_add, raw)))
        push!(generated, (:+, field_data(+(many...)), foldl(ref_add, raw)))

        spectral_many = [similar_field(spectral_zero, Val(1)) for _ in 1:n]
        foreach(f -> copyto!(field_data(f), randn(Complex{T}, size(field_data(f)))), spectral_many)
        raw_spectral = [copy(field_data(f)) for f in spectral_many]
        push!(generated, (:add!, field_data(add!(similar_field(spectral_many[1], Val(1)), spectral_many...)),
                          foldl(ref_add, raw_spectral)))

        values_many = [VectorPointValues(rand(T, 9, 3)) for _ in 1:n]
        raw_values_many = [copy(point_values(q)) for q in values_many]
        push!(generated, (:add!, point_values(add!(similar_point_values(values_many[1], Val(1)), values_many...)),
                          foldl(ref_add, raw_values_many)))
        push!(generated, (:subtract!, point_values(subtract!(values_many[n], values_many...)),
                          foldl((x, y) -> x .- y, raw_values_many)))
      end

      for n in (20, 33)
        coefficients = [T(k) / 17 - T(1) for k in 1:n]
        sections = [VectorPointValues(randn(T, 9, 3)) for _ in 1:n]
        terms = [(coefficients[k], sections[k]) for k in 1:n]
        raw_terms = [(coefficients[k], copy(point_values(sections[k]))) for k in 1:n]
        push!(generated, (:displace!, point_positions(displace!(PointSet(copy(raw_coordinates)), terms...)),
                          ref_displace(raw_coordinates, raw_terms...)))
        push!(generated, (:displace!, point_positions(displace!(PointSet(copy(raw_coordinates)), grid, terms...)),
                          ref_displace_wrapped(raw_coordinates, grid, raw_terms...)))
        push!(generated, (:displace!, point_positions(displace!(PointSet(zeros(T, 9, 3)),
                                                                 PointSet(copy(raw_coordinates)), grid, terms...)),
                          ref_displace_wrapped(raw_coordinates, grid, raw_terms...)))
        # The destination/source form in the universal cover — the one `displace!` method no row had
        # reached, which the per-method ledger named on the survey's first run with these rows.
        push!(generated, (:displace!, point_positions(displace!(PointSet(zeros(T, 9, 3)),
                                                                 PointSet(copy(raw_coordinates)), terms...)),
                          ref_displace(raw_coordinates, raw_terms...)))
      end
      push!(generated, (:displace!, point_positions(displace!(PointSet(zeros(T, 9, 3)),
                                                               PointSet(copy(raw_coordinates)), (α, qa), (β, qb))),
                        ref_displace(raw_coordinates, (α, point_values(qa)), (β, point_values(qb)))))

      # Six second-order sources, each in its own slot of an asymmetric map, on both bases.
      six(A1, A2, A3, A4, A5, A6) = A1 * A2 + 2A3 - A4 * A5 + transpose(A6)
      tensor_sources = [TensorFieldPhysical{2}(rand(T, P(2)...), grid; layout) for _ in 1:6]
      tensor_values = [TensorPointValues{2}(rand(T, 9, 3, 3)) for _ in 1:6]
      for (sources, data, count) in ((tensor_sources, field_data, prod(grid.grid_size)), (tensor_values, point_values, 9))
        raw_sources = [reshape(copy(data(x)), count, 3, 3) for x in sources]
        expected = similar(raw_sources[1])
        for p in 1:count
          fibers = [[r[p, i, j] for i in 1:3, j in 1:3] for r in raw_sources]
          expected[p, :, :] = fibers[1] * fibers[2] + 2 .* fibers[3] - fibers[4] * fibers[5] + transpose(fibers[6])
        end
        destination = sources === tensor_values ? similar_point_values(sources[1], Val(2)) : similar_field(sources[1], Val(2))
        push!(generated, (:map!, reshape(Array(data(map!(six, destination, sources...))), count, 3, 3), expected))
      end

      # The tuple form of `weighted_inner` (decision 72), never surveyed before: 33 weights of mixed
      # storage classes, each answer against the single-weight definition over a raw weight array
      # built from `ref_squared_wavenumber`, not from the package's own multipliers.
      k2 = ref_squared_wavenumber(grid, layout, shape)
      weight_classes = ((radial_kernel(identity, multipliers), k2),
                        (radial_kernel(x -> one(x), multipliers), one.(k2)),
                        (radial_kernel(x -> exp(-x / 50), multipliers), exp.(-k2 ./ 50)),
                        (materialize_kernel(radial_kernel(identity, multipliers)), k2))
      weights = ntuple(i -> weight_classes[mod1(i, 4)][1], 33)
      answers = weighted_inner(uh, weights)
      for i in (1, 2, 3, 4, 5, 17, 32, 33)
        push!(generated, (:weighted_inner, answers[i],
                          ref_weighted_inner(field_data(uh), field_data(uh), weight_classes[mod1(i, 4)][2],
                                             grid, layout, 1)))
      end
    end

    for (name, got, want) in Iterators.flatten((comparisons, spectral_comparisons, generated, persistence_comparisons))
      cells += 1
      # The comparison tuples are built eagerly, so this guards the COMPARISON; a throw during
      # construction still propagates. What it prevents is one unexpected result type aborting the lane
      # — and with it the survey, since `runtests.jl` has no top-level handler.
      push!(covered, name)
      record_coverage!(name, :correct)
      agreed = value_agrees(got, want, rtol)
      if agreed isa Symbol
        Base.push!(disagreements, "$(name) [$(config.name)] — comparison threw $(agreed)")
        continue
      end
      agreed && continue
      Base.push!(disagreements, "$(name) [$(config.name)]")
    end
    set_threading_cutoff!(entry_cutoff)
  end

  # The guard that keeps this lane honest against a derived denominator: every public operation with no
  # oracle here is NAMED. A value lane that quietly covers a third of the surface reads exactly like one
  # that covers all of it.
  uncovered = sort(collect(setdiff(package_operations(), covered)); by = String)
  # …and the INVERSE, which nothing checked: a name this lane records as covered that is not a public
  # operation at all. A row labelled for an operation that has been renamed or deleted keeps claiming
  # coverage forever, and inflates the "N of M operations have an oracle" line that is this lane's whole
  # report. `:squared_wavenumber_field` sat here after decision 60 removed it — the row still ran, and
  # still tested something real, but credited a ghost while the two operations it actually exercises got
  # nothing from it.
  ghosts = sort(collect(setdiff(covered, package_operations())); by = String)

  println("\n  ", cells, " value comparisons over ", length(configs), " configurations · ",
          length(covered), " of ", length(package_operations()), " operations have an independent oracle")
  if !isempty(uncovered)
    println("\n  NO VALUE ORACLE — ", length(uncovered), " operations are exercised but their computed")
    println("  result is checked against nothing:")
    for chunk in Iterators.partition(uncovered, 7); println("      ", join(String.(chunk), ", ")); end
  end
  if !isempty(ghosts)
    println("\n  COVERAGE CLAIMED FOR A NON-OPERATION — ", length(ghosts), " labels name nothing public:")
    println("      ", join(String.(ghosts), ", "))
    println("  Relabel the row for what it actually tests; the count above is wrong until you do.")
  end
  if isempty(disagreements)
    println("  every computed result matches its independent reference")
  else
    println("\n  THE COMPUTED RESULT DISAGREES WITH THE DEFINITION — ", length(disagreements), " cells.")
    println("  One of the two is wrong: the implementation, or the docstring the reference was")
    println("  written from. Both are findings.")
    for d in unique(disagreements); println("      ", d); end
  end
  return (length(disagreements), cells, length(covered), length(uncovered))
end
