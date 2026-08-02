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
using Random


# A tolerance that tracks the element type and the length of the reduction. The references sum in a
# different order from the package (a plain loop against a pairwise-blocked or fused pass), so exact
# equality is not the property — agreement to the arithmetic's own precision is.
_value_tolerance(T) = T === Float32 ? 1.0f-4 : 1e-10

# The package's load-time FFT thread count (`Fields._init_fft_threads` sets `max(1, nthreads())`).
# There is no getter, so this is the value to restore TO, not a capture of what was there.
const FFTW_DEFAULT_THREADS = max(1, Threads.nthreads())

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
    s  = ScalarFieldPhysical(rand(T, P(0)...), grid, layout)
    s2 = ScalarFieldPhysical(rand(T, P(0)...), grid, layout)
    u  = VectorFieldPhysical(copy(raw_vector), grid, layout)
    v  = VectorFieldPhysical(rand(T, P(1)...), grid, layout)
    A  = TensorFieldPhysical{2}(rand(T, P(2)...), grid, layout)
    B  = TensorFieldPhysical{2}(rand(T, P(2)...), grid, layout)
    signed = ScalarFieldPhysical(rand(T, P(0)...) .- T(1) / 2, grid, layout)
    w  = VectorFieldPhysical(rand(T, P(1)...), grid, layout)      # a THIRD distinct vector operand
    α, β = T(3) / 10, T(7) / 10
    ds, du, dA = field_data(s), field_data(u), field_data(A)

    # (name, what the package computes, what the definition says it should be)
    comparisons = (
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
      (:pointvalue_tensor_order, pointvalue_tensor_order(VectorPointValues(rand(T, 9, 3))), 1),
      (:fiber_shape,         collect(fiber_shape(Val(2))), [3, 3]),
      (:physical_field_shape, collect(physical_field_shape(grid, Val(1))), [grid.grid_size..., 3]),
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
    spectral_zero = ScalarFieldSpectral(zeros(Complex{T}, GBGI.Fields.spectral_field_shape(grid, layout, Val(0))...),
                                        grid, layout)
    plans = FieldTransformPlans(s, spectral_zero)
    multipliers = FieldSpectralMultipliers(spectral_zero)
    shape = size(field_data(spectral_zero))
    kernel_data(k) = Array(GBGI.Convolution._kernel_data(materialize_kernel(k)))
    sh = to_spectral(s, plans)
    uh = to_spectral(u, FieldTransformPlans(u, similar_field(spectral_zero, Val(1))))
    Ah = to_spectral(A, FieldTransformPlans(A, similar_field(spectral_zero, Val(2))))
    # A strictly positive field, so the reciprocal an `inv` oracle needs is well defined everywhere.
    spectral_zero_ones = ScalarFieldSpectral(ones(Complex{T}, shape...), grid, layout)
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
    sh2 = to_spectral(s2, plans)
    raw_values2 = rand(T, 9)
    q2 = ScalarPointValues(copy(raw_values2))
    cutoff = T(3)
    spectral_comparisons = (
      (:to_spectral,   field_data(sh),                       ref_dft_forward(ds, grid, layout)),
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
      (:to_spectral!,  field_data(to_spectral!(similar_field(spectral_zero, Val(0)), ScalarFieldPhysical(copy(ds), grid, layout), plans)),
                                                             ref_dft_forward(ds, grid, layout)),
      (:squared_wavenumber_field, field_data(squared_wavenumber_field(spectral_zero, multipliers)),
                                                             complex.(ref_squared_wavenumber(grid, layout, shape))),
      (:spectral_cutoff, kernel_data(spectral_cutoff(spectral_zero, multipliers, cutoff)),
                                                             complex.(ref_spectral_cutoff(grid, layout, shape, cutoff))),
      (:spectral_band,   kernel_data(spectral_band(spectral_zero, multipliers, T(1), cutoff)),
                                                             complex.(ref_spectral_band(grid, layout, shape, T(1), cutoff))),
      (:assignment_window, kernel_data(assignment_window(spectral_zero, multipliers)),
                                                             complex.(ref_assignment_window(grid, layout, shape))),
      (:translation_kernel, kernel_data(translation_kernel(spectral_zero, multipliers, offset)),
                                                             ref_translation_kernel(grid, layout, shape, offset)),
      # A SEPARABLE kernel, not the radial one the row above already materializes. `kernel_data` calls
      # `materialize_kernel` internally, so pointing this row at the same expression as its neighbour made
      # the two literally identical: it could never disagree, and it credited the operation in the oracle
      # registry while asserting nothing beyond what the neighbour asserts.
      (:materialize_kernel, kernel_data(translation_kernel(spectral_zero, multipliers, offset)),
                            ref_translation_kernel(grid, layout, shape, offset)),
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
      (:weighted_inner, weighted_inner(sh, sh, squared_wavenumber_field(spectral_zero, multipliers)),
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
                                                  point_coordinates(points), 0)),
      # ABOVE R = 0. The DFT transfer kernels carry an explicit fiber loop with hand-built linear-index
      # arithmetic that collapses to a no-op when there is one component, so a fiber-stride defect is
      # invisible at R = 0 by construction — which is the only order that was checked.
      (:interpolate,     point_values(interpolate(uh, points, DirectDFT())),
                         ref_spectral_interpolate(field_data(uh), grid, layout,
                                                  point_coordinates(points), 1)),
      # The cross-family `ProductKernel` (radial ∘ separable). Radial ∘ radial collapses back to a
      # radial kernel by decision 51, so composing two radials never builds this type at all; the pool
      # constructs one and nothing compared its coefficients to anything.
      (:convolve,        kernel_data(convolve(spectral_cutoff(spectral_zero, multipliers, cutoff),
                                              translation_kernel(spectral_zero, multipliers, offset))),
                         complex.(ref_spectral_cutoff(grid, layout, shape, cutoff)) .*
                         ref_translation_kernel(grid, layout, shape, offset)),
      # The KERNEL-COMPOSED arities (decision 32). `divergence!`/`helmholtz_projection!` with a trailing
      # kernel route through a distinct overload that fuses the convolution into the operator's own
      # pass; only the plain forms were value-checked, so a defect that dropped the kernel factor or
      # applied it with the wrong placement was indistinguishable from a correct fused pass.
      (:divergence,      field_data(divergence(uh, multipliers,
                                               spectral_cutoff(spectral_zero, multipliers, cutoff))),
                         ref_divergence(field_data(uh), grid, layout) .*
                         ref_spectral_cutoff(grid, layout, shape, cutoff)),
      (:helmholtz_projection,
                         field_data(helmholtz_projection(uh, multipliers,
                                                         spectral_cutoff(spectral_zero, multipliers, cutoff))),
                         ref_helmholtz(field_data(uh), grid, layout) .*
                         ref_spectral_cutoff(grid, layout, shape, cutoff)),
      (:interpolate,     point_values(interpolate(sh, points, NUFFT(sh; tol = 1e-10))),
                         ref_spectral_interpolate(ref_project_out_nyquist(field_data(sh), grid, layout),
                                                  grid, layout, point_coordinates(points), 0)),
      (:radial_spectrum, collect(last(radial_spectrum(sh, multipliers))),
                         ref_radial_spectrum(field_data(sh), grid, layout, 0)),
      (:interpolate,    point_values(interpolate(s, points, CatmullRom)),
                        ref_interpolate_catmull_rom(ds, grid, point_coordinates(points), 0)),
      (:anterpolate,    field_data(anterpolate(grid, points, q, CatmullRom)),
                        ref_anterpolate_catmull_rom(point_values(q), grid, point_coordinates(points), 0)),
      (:interpolate!,   point_values(interpolate!(ScalarPointValues(zeros(T, 9)), s, points, CatmullRom)),
                        ref_interpolate_catmull_rom(ds, grid, point_coordinates(points), 0)),
      (:anterpolate!,   field_data(anterpolate!(similar_field(s, Val(0)), points, q, CatmullRom)),
                        ref_anterpolate_catmull_rom(point_values(q), grid, point_coordinates(points), 0)),
      # THE GEOMETRIES THE TRANSFER EXISTS TO HANDLE, and a non-scalar fiber. Every point set compared
      # against these references was i.i.d. uniform strictly inside the box, at R = 0 — so an
      # accumulation defect in the scatter where stencils OVERLAP (last-write-wins instead of add), a
      # wrap defect for a point outside the box, and a fiber-component swap during gather were all
      # unobservable. The geometries exist in `pointset_pool` but reached only an `isfinite` check.
      (:interpolate,    point_values(interpolate(u, points, CatmullRom)),
                        ref_interpolate_catmull_rom(du, grid, point_coordinates(points), 1)),
      (:interpolate,    point_values(interpolate(s, clustered, CatmullRom)),
                        ref_interpolate_catmull_rom(ds, grid, point_coordinates(clustered), 0)),
      (:anterpolate,    field_data(anterpolate(grid, clustered, q, CatmullRom)),
                        ref_anterpolate_catmull_rom(point_values(q), grid, point_coordinates(clustered), 0)),
      (:anterpolate,    field_data(anterpolate(grid, outside, q, CatmullRom)),
                        ref_anterpolate_catmull_rom(point_values(q), grid, point_coordinates(outside), 0)),
      # ── the spectral operators and their in-place twins ───────────────────────────────────────
      (:gradient,       field_data(gradient(sh, multipliers)),  ref_gradient(field_data(sh), grid, layout)),
      # The JACOBIAN mode, with its index convention actually pinned. `gradient(vector)` was exercised
      # only through `symmetric_gradient = sym(gradient(u))`, and `sym(M) = sym(Mᵀ)` erases a transposed
      # fiber-index pair before the comparison sees it.
      (:gradient,       field_data(gradient(uh, multipliers)),
                        ref_gradient_jacobian(field_data(uh), grid, layout)),
      (:gradient!,      field_data(gradient!(similar_field(spectral_zero, Val(1)), sh, multipliers)),
                                                                ref_gradient(field_data(sh), grid, layout)),
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
      # ── convolution: the coefficientwise product of Fourier symbols ───────────────────────────
      (:convolve,       field_data(convolve(sh, spectral_cutoff(spectral_zero, multipliers, cutoff))),
                        ref_convolve(field_data(sh), complex.(ref_spectral_cutoff(grid, layout, shape, cutoff)))),
      (:convolve!,      field_data(convolve!(similar_field(spectral_zero, Val(0)), sh,
                                             spectral_cutoff(spectral_zero, multipliers, cutoff))),
                        ref_convolve(field_data(sh), complex.(ref_spectral_cutoff(grid, layout, shape, cutoff)))),
      (:⋆,              field_data(sh ⋆ spectral_cutoff(spectral_zero, multipliers, cutoff)),
                        ref_convolve(field_data(sh), complex.(ref_spectral_cutoff(grid, layout, shape, cutoff)))),
      (:exponential_convolve, field_data(exponential_convolve(sh, multipliers, -T(1) / 10)),
                        ref_convolve(field_data(sh), complex.(ref_exponential_symbol(grid, layout, shape, -T(1) / 10)))),
      (:exponential_convolve!, field_data(exponential_convolve!(similar_field(spectral_zero, Val(0)), sh,
                                                                multipliers, -T(1) / 10)),
                        ref_convolve(field_data(sh), complex.(ref_exponential_symbol(grid, layout, shape, -T(1) / 10)))),
      (:radial_kernel,  kernel_data(radial_kernel(k2 -> exp(-k2 / 10), spectral_zero, multipliers)),
                        complex.(ref_exponential_symbol(grid, layout, shape, -T(1) / 10))),
      # A NON-CONSTANT kernel. The fixture was uniformly 2 everywhere and the expectation uniformly 0.5,
      # so an implementation computing `1/data[1]` and broadcasting it over the whole array passed with
      # full marks — the reciprocal's whole point is that it is elementwise.
      (:inv,            kernel_data(inv(StoredKernel(spectral_zero_ones +
                                                     materialize_kernel(spectral_cutoff(spectral_zero, multipliers, cutoff))))),
                        complex.(one(T) ./ (one(T) .+ ref_spectral_cutoff(grid, layout, shape, cutoff)))),
      # The COMPOSED kernel, elementwise. Kernel-to-kernel composition was checked only by
      # "composition is associative" — and associativity holds for any associative combinator, so
      # elementwise addition, min, max, or "return the first operand" would all have passed while
      # silently replacing the coefficientwise product. The pool even builds a composed kernel; nothing
      # ever compared its coefficients to anything.
      (:convolve,       kernel_data(convolve(spectral_cutoff(spectral_zero, multipliers, cutoff),
                                             spectral_band(spectral_zero, multipliers, T(1), cutoff))),
                        complex.(ref_spectral_cutoff(grid, layout, shape, cutoff) .*
                                 ref_spectral_band(grid, layout, shape, T(1), cutoff))),
      # `translation_kernel!` updates a SeparableKernel in place — the compressed per-axis factors,
      # not a materialized field — so the in-place form is fed the kernel its own builder returns.
      # Built with a DIFFERENT offset, so an in-place form that writes nothing cannot pass.
      (:translation_kernel!, kernel_data(translation_kernel!(translation_kernel(spectral_zero, multipliers,
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
      # `point_coordinates(points)` with itself passes for a transposed, zeroed or permuted result.
      (:point_coordinates,   point_coordinates(points),         raw_coordinates),
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
      (:spectral_field_shape, collect(GBGI.Fields.spectral_field_shape(grid, layout, Val(1))),
                              [ntuple(d -> d == layout.fft_dims[1] ? grid.grid_size[d] ÷ 2 + 1 :
                                           grid.grid_size[d], 3)..., 3]),
      (:similar_field,       collect(size(field_data(similar_field(s, Val(1))))), [grid.grid_size..., 3]),
      (:similar_pointvalues, npoints(similar_pointvalues(q, Val(0))), 9),
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
                                                ScalarFieldSpectral(copy(field_data(sh)), grid, layout), plans)),
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
    persistence_comparisons = if HDF5_AVAILABLE
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
      stored_field = argmax(length, raw_datasets("field"))
      stored_points = argmax(length, raw_datasets("points"))
      recovered_field, recovered_points = HDF5.h5open(path, "r") do file
        (read_field(file, "field"), read_points(file, "points"))
      end
      others = HDF5.h5open(path, "r") do file
        (read_field(file, "scalar"), read_field(file, "tensor"), read_field(file, "spectral"),
         read_field(file, "spectral_tensor"), read_points(file, "qv"), read_points(file, "qt"))
      end
      ((:write_field,  vec(stored_field),                 vec(du)),
       (:write_points, vec(stored_points),                vec(point_coordinates(points))),
       (:read_field,   field_data(recovered_field),       du),
       (:read_points,  point_coordinates(recovered_points), point_coordinates(points)),
       # The round trip must return the same VALUES and the same TYPE — a tag-dispatch defect that
       # rebuilt a spectral field as a physical one, or a tensor as a vector, would otherwise survive.
       (:read_field,   field_data(others[1]),             ds),
       (:read_field,   field_data(others[2]),             dA),
       (:read_field,   field_data(others[3]),             field_data(sh)),
       (:read_field,   field_data(others[4]),             field_data(Ah)),
       (:read_field,   [typeof(others[1]) === typeof(s), typeof(others[2]) === typeof(A),
                        typeof(others[3]) === typeof(sh), typeof(others[4]) === typeof(Ah)],
                       [true, true, true, true]),
       (:read_points,  point_values(others[5]),           raw_qa),
       (:read_points,  point_values(others[6]),           raw_qt),
       (:read_points,  [typeof(others[5]) === typeof(qa), typeof(others[6]) === typeof(qt)],
                       [true, true]))
    else
      ()
    end

    for (name, got, want) in Iterators.flatten((comparisons, spectral_comparisons, persistence_comparisons))
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

  println("\n  ", cells, " value comparisons over ", length(configs), " configurations · ",
          length(covered), " of ", length(package_operations()), " operations have an independent oracle")
  if !isempty(uncovered)
    println("\n  NO VALUE ORACLE — ", length(uncovered), " operations are exercised but their computed")
    println("  result is checked against nothing:")
    for chunk in Iterators.partition(uncovered, 7); println("      ", join(String.(chunk), ", ")); end
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
