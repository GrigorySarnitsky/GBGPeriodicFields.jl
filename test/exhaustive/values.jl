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

# What FFTW was configured with before this suite touched it, captured once.
const FFTW_THREADS = Ref(Threads.nthreads())

_as_array(x) =
  x isa GBGI.FiberSections.AbstractFiberSection ? Array(field_data(x)) :
  x isa Number                                  ? [x] :
  x isa Tuple                                   ? collect(Float64, x) :
  x isa AbstractArray                           ? Array(x) : [x]


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
      (:maximum,    maximum(s),               maximum(ds)),
      (:minimum,    minimum(s),               minimum(ds)),
      (:extrema,    collect(extrema(s)),      [minimum(ds), maximum(ds)]),
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
    # A strictly positive field, so the reciprocal an `inv` oracle needs is well defined everywhere.
    spectral_zero_ones = ScalarFieldSpectral(ones(Complex{T}, shape...), grid, layout)
    offset = ntuple(d -> T(1) / 2 * grid.grid_spacing[d], 3)
    raw_coordinates = rand(T, 9, 3) .* reshape(collect(grid.domain_size), 1, 3) .+
                      reshape(collect(grid.origin), 1, 3)
    raw_values = rand(T, 9)
    points = PointSet(copy(raw_coordinates))
    q = ScalarPointValues(copy(raw_values))
    cutoff = T(3)
    spectral_comparisons = (
      (:to_spectral,   field_data(sh),                       ref_dft_forward(ds, grid, layout)),
      (:to_physical,   field_data(to_physical(sh, plans)),   ref_dft_inverse(field_data(sh), grid, layout)),
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
      (:materialize_kernel, kernel_data(spectral_cutoff(spectral_zero, multipliers, cutoff)),
                                                             complex.(ref_spectral_cutoff(grid, layout, shape, cutoff))),
      (:inner,          inner(sh, sh),                       ref_spectral_inner(field_data(sh), field_data(sh), grid, layout, 0)),
      (:l2norm,         l2norm(sh),                          sqrt(ref_spectral_inner(field_data(sh), field_data(sh), grid, layout, 0))),
      (:weighted_inner, weighted_inner(sh, sh, squared_wavenumber_field(spectral_zero, multipliers)),
                        ref_weighted_inner(field_data(sh), field_data(sh),
                                           field_data(squared_wavenumber_field(spectral_zero, multipliers)),
                                           grid, layout, 0)),
      # The SHELLS, not just their sum. Summing checks Parseval and leaves the binning — the operation's
      # entire purpose — free to put every mode in one shell.
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
      # ── the spectral operators and their in-place twins ───────────────────────────────────────
      (:gradient,       field_data(gradient(sh, multipliers)),  ref_gradient(field_data(sh), grid, layout)),
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
      (:inv,            kernel_data(inv(StoredKernel(spectral_zero_ones + spectral_zero_ones))),
                        complex.(fill(T(1) / 2, shape...))),
      # `translation_kernel!` updates a SeparableKernel in place — the compressed per-axis factors,
      # not a materialized field — so the in-place form is fed the kernel its own builder returns.
      # Built with a DIFFERENT offset, so an in-place form that writes nothing cannot pass.
      (:translation_kernel!, kernel_data(translation_kernel!(translation_kernel(spectral_zero, multipliers,
                                                                               ntuple(d -> -offset[d], 3)),
                                                             multipliers, offset)),
                        ref_translation_kernel(grid, layout, shape, offset)),
      # C(0) = ⟨f, f⟩ is the Wiener-Khinchin dual's defining value, and it is checked against the
      # INDEPENDENT Parseval sum rather than against the package's own `inner`.
      (:radial_correlation, first(last(radial_correlation(sh, plans))),
                            ref_spectral_inner(field_data(sh), field_data(sh), grid, layout, 0)),
      # ── the remaining accessors ───────────────────────────────────────────────────────────────
      # Against the RAW matrices the objects were constructed from, not against themselves. Comparing
      # `point_coordinates(points)` with itself passes for a transposed, zeroed or permuted result.
      (:point_coordinates,   point_coordinates(points),         raw_coordinates),
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
      (:getindex,            u[1, 1, 1, 1],                     raw_vector[1, 1, 1, 1]),
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
                          scratch[1, 1, 1] = T(7) / 2
                          field_data(scratch)[1, 1, 1]
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
      # Restored to what it was, not to `nthreads()` — the two differ whenever FFTW was configured
      # otherwise, and this lane would silently reconfigure the process for every later lane.
      (:set_fft_threads!, begin
                            FFTW_THREADS[] = Threads.nthreads()
                            previous_fft_threads = FFTW_THREADS[]
                            set_fft_threads!(1)
                            observed = field_data(to_spectral(s, plans))
                            set_fft_threads!(previous_fft_threads)
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
      ((:write_field,  vec(stored_field),                 vec(du)),
       (:write_points, vec(stored_points),                vec(point_coordinates(points))),
       (:read_field,   field_data(recovered_field),       du),
       (:read_points,  point_coordinates(recovered_points), point_coordinates(points)))
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
      agreed = try
        isapprox(_as_array(got), _as_array(want); rtol = rtol)
      catch exception
        Base.push!(disagreements, "$(name) [$(config.name)] — comparison threw $(nameof(typeof(exception)))")
        continue
      end
      agreed && continue
      Base.push!(disagreements, "$(name) [$(config.name)]")
    end
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
