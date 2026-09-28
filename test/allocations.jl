# =============================================================================
# Allocation audit — every "non-allocating" function actually allocates ~0, exhaustively.
#
# WHY THIS MATTERS. The in-place `!` operators (and the reductions that contract a field to a scalar)
# must allocate NO field-sized scratch. An internal temporary is invisible on the CPU — the GC reclaims
# it — but on the GPU it grows the device memory pool every step until the run wedges or `hipMalloc`
# aborts. This bit the HIST demos twice: the spectral operators (decision 24) and the radial-correlation
# shell binning (decision 25, which materialized one full-grid mask *per shell*, ~N of them per call).
#
# WHY THE TEST RUNS ON THE CPU. `@allocated` counts *host* bytes. On the CPU a materialized field is a
# host `Array`, so its full bytes are counted and a stray temporary trips the threshold. On the GPU the
# same `similar`/broadcast would allocate a *device* buffer behind a tiny host wrapper, so GPU
# `@allocated` would report only the wrapper and MISS the very leak we are hunting. The operator code is
# generic over the array type, so a CPU materialization *is* a GPU materialization — the CPU is simply
# where it is visible. (GPU correctness lives in `test/gpu/suite.jl`; this file owns the alloc contract.)
#
# COVERAGE. For every intended-alloc-free generic we exercise the distinct code paths that could each
# break independently: both element types, both representations (physical / spectral — the spectral
# constant path updates only the zero mode), tensor orders R = 0/1/2, the field·field / field·constant /
# constant·field argument patterns, the three-argument and five-argument (α/β) forms, the field surface
# AND the point-value surface, and the grid↔point spline transfer. The deliberate allocators
# (`norm!`/`lpnorm` materialize one field by design — `dev!` no longer does, its trace fused
# into the executor pass; the radial diagnostics allocate a
# bounded O(1) set per call) get a *bounded* guard instead of a zero guard — enough to catch a regression
# to O(N) or O(shells) without forbidding their one-field temporary.
#
# METHOD. Warm each call once (exclude compilation / FFT-plan / first-touch), then measure one in-place
# call with `@allocated`. A field-sized temporary is hundreds of KB; the threshold is a small fraction of
# one field, catching any field allocation while tolerating the few hundred bytes of scalar/closure noise.
# =============================================================================

using Test
using GBGPeriodicFields                       # exports `mul!` (re-exported), so no LinearAlgebra import
using GBGPeriodicFields: field_data, point_values
using Statistics: mean, std, var, cov              # `Reductions` extends these; bring them into scope to call
using Statistics
include("public_surface.jl")


# The allocation audit is DECLARED to GBGCodingTools (RULE.TEST.ALLOC_ZERO): `@alloc_below` and the
# completeness check at the foot are the tool's engines, `GBGCodingTools.TestHarness`, which were
# extracted from this file. The macro warms each expression up once, asserts one call allocates fewer
# than `bound` bytes, turns a throw into a failed test, and records the callee so the completeness
# check is DERIVED from the export list rather than trusted to memory (decision 53).
using GBGCodingTools.TestHarness: @alloc_below
import GBGCodingTools


# Named maps for the map! rows: `@alloc_below` splices its expr twice (warm-up + measure), which would
# give an anonymous closure two distinct types (only the second is timed, so it would read as a compile
# allocation). A named function has one type across both splices, so it warms up correctly.
_map_double(x) = 2x
_map_add(a, b) = a + b
_six_tensor_map(A, B, C, D, E, F) = A * B + 2C - D * E + transpose(F)   # six slots, none symmetric
_sum_all(xs...) = sum(xs)                                                 # any number of sources


@testset "allocation audit" begin
  for T in (Float64, Float32)
    @testset "$T" begin
      N = 24
      M = 4000                                  # enough points that a point-value temporary exceeds `threshold`
      grid = Grid3D((N, N, N), (T(2π), T(2π), T(2π)))
      layout = RealFourierLayout()

      spectral_vector() = VectorFieldSpectral(zeros(Complex{T}, field_spectral_shape(grid, layout, Val(1))), grid)
      spectral_scalar() = ScalarFieldSpectral(zeros(Complex{T}, field_spectral_shape(grid, layout, Val(0))), grid)
      spectral_tensor() = TensorFieldSpectral(zeros(Complex{T}, field_spectral_shape(grid, layout, Val(2))), grid)
      physical_vector() = VectorFieldPhysical(zeros(T, N, N, N, 3), grid)
      physical_scalar() = ScalarFieldPhysical(zeros(T, N, N, N), grid)
      physical_tensor() = TensorFieldPhysical(zeros(T, N, N, N, 3, 3), grid)
      scalar_points() = ScalarPointValues(zeros(T, M))
      vector_points() = VectorPointValues(zeros(T, M, 3))
      tensor_points() = TensorPointValues(zeros(T, M, 3, 3))
      randomize!(f) = (field_data(f) .= rand(eltype(field_data(f)), size(field_data(f))); f)
      randomize_points!(f) = (point_values(f) .= rand(eltype(point_values(f)), size(point_values(f))); f)

      multipliers   = FieldSpectralMultipliers(spectral_vector())
      vector_plans  = FieldTransformPlans(physical_vector(), spectral_vector())
      scalar_plans  = FieldTransformPlans(physical_scalar(), spectral_scalar())
      tensor_plans  = FieldTransformPlans(physical_tensor(), spectral_tensor())

      # A spectral vector field is this many bytes; allow only a small fraction (a field-sized temp fails).
      field_bytes = sizeof(field_data(spectral_vector()))
      threshold = field_bytes ÷ 16
      # The FIELD-destination ops additionally absorb the threaded `_assign!` path's size-independent
      # per-task bookkeeping (slab views, rebuilt `Broadcasted` nodes, task objects — measured ≤ ~3.5 KB
      # per thread, worst on the deep lazy-|k|² trees; the same class as the KA launch's documented
      # 1.5–7 KB). The floor scales with the thread count and stays far below the smallest real field
      # temporary here (a `Float32` scalar spectral field is ~60 KB), so a leaked field still fails.
      # Point-value ops keep the plain `threshold`: their smallest real temporary (a scalar point
      # array, ~16 KB `Float32`) must remain above the bound, and they never take the threaded path
      # at this M.
      field_threshold = threshold + 4096 * Threads.nthreads()
      # Decision 76 made a rank-R transform issue one plan execution PER CONTIGUOUS COMPONENT where
      # it had been one batched execution, and FFTW's worker callback allocates task state per
      # execution — measured at exactly 4032 B each on four threads, and 0 B on one, where the
      # callback is absent. So the §4(t) slack has to scale with the component count as well as the
      # thread count: `field_threshold` covers one execution, which is why the scalar and vector rows
      # still pass and the nine-component tensor rows did not. This was decision 76's to re-derive
      # and was missed; the threaded CI lane has been failing these three rows since.
      transform_threshold(components) = threshold + 4096 * Threads.nthreads() * components

      # constants for the linear-in-field variants
      const_real = T(2)
      const_vec  = rand(FiberVector{T})
      const_ten  = rand(FiberTensor2{T})

      # spectral sources / distinct destinations
      sv, ss, st = randomize!(spectral_vector()), randomize!(spectral_scalar()), randomize!(spectral_tensor())
      svd, ssd, std_ = spectral_vector(), spectral_scalar(), spectral_tensor()
      # A field of coefficients declared as a kernel. A `ScalarFieldSpectral` is no longer accepted in
      # the kernel role — the two hold identical data and only a type can say which is meant — so the
      # role is stated here, once, where the kernel is built.
      kernel_field = spectral_scalar(); field_data(kernel_field) .= one(Complex{T})
      kernel = GBGPeriodicFields.Convolution.StoredKernel(kernel_field)

      # physical sources / distinct destinations
      pu, pv2 = randomize!(physical_vector()), randomize!(physical_vector())
      ps, pt = randomize!(physical_scalar()), randomize!(physical_tensor())
      pvd, psd, ptd = physical_vector(), physical_scalar(), physical_tensor()
      psd2 = physical_scalar(); field_data(psd2) .= rand(T, N, N, N) .+ one(T)   # nonzero divisor

      # point-value sources / distinct destinations
      qs, qv, qt = randomize_points!(scalar_points()), randomize_points!(vector_points()), randomize_points!(tensor_points())
      qsd, qvd, qtd = scalar_points(), vector_points(), tensor_points()
      qs_pos = scalar_points(); point_values(qs_pos) .= rand(T, M) .+ one(T)     # nonzero divisor
      # A coarser field over the same box, for the resolution verbs below.
      coarse_grid = Grid3D(grid.grid_size .÷ 2, grid.domain_size)
      coarse_spectral = VectorFieldSpectral(Array, coarse_grid, layout)
      field_data(coarse_spectral) .= 0

      # ----- spectral differential operators (lazy |k|² + fused kernels; decision 24) -----
      @alloc_below field_threshold laplacian!(svd, sv, multipliers)
      @alloc_below field_threshold inverse_laplacian!(svd, sv, multipliers)
      @alloc_below field_threshold helmholtz_projection!(svd, sv, multipliers)
      @alloc_below field_threshold helmholtz_projection!(svd, svd, multipliers)                       # aliased in place — the one-pass kernel needs no guard temporary (decision 32)
      @alloc_below field_threshold helmholtz_projection!(svd, sv, multipliers, kernel)                # kernel-composed ℙ
      @alloc_below field_threshold helmholtz_projection!(svd, sv, multipliers, kernel, T(0.5), T(1))
      # the reality projector (decision 83): in place on the planes, and the copying two-argument form
      @alloc_below field_threshold reality_projection!(ssd)
      @alloc_below field_threshold reality_projection!(svd)
      @alloc_below field_threshold reality_projection!(svd, sv)
      # the mean-free projector (decision 90): one coefficient per component, so the tight bound
      @alloc_below threshold mean_free_projection!(ssd)
      @alloc_below threshold mean_free_projection!(svd)
      @alloc_below threshold mean_free_projection!(std_)
      # Moving modes between grid resolutions (decision 85): the pass walks the COARSE field, so its
      # cost and its allocation are set by the small grid whatever the fine one is.
      @alloc_below field_threshold embed_modes!(sv, coarse_spectral)
      @alloc_below field_threshold embed_modes!(sv, coarse_spectral, T(0.5), T(1))
      @alloc_below field_threshold extract_modes!(coarse_spectral, sv)
      @alloc_below field_threshold extract_modes!(coarse_spectral, sv, T(0.5), T(1))
      @alloc_below field_threshold curl!(svd, sv, multipliers)
      @alloc_below field_threshold inverse_curl!(svd, sv, multipliers)
      @alloc_below field_threshold divergence!(ssd, sv, multipliers)            # vector → scalar
      @alloc_below field_threshold divergence!(svd, st, multipliers)            # tensor → vector
      @alloc_below field_threshold divergence!(ssd, sv, multipliers, kernel)                          # kernel-composed ∇·
      @alloc_below field_threshold divergence!(ssd, sv, multipliers, kernel, T(0.5), T(1))
      @alloc_below field_threshold divergence!(svd, st, multipliers, kernel)
      @alloc_below field_threshold divergence!(svd, st, multipliers, kernel, T(0.5), T(1))
      @alloc_below field_threshold gradient!(svd, ss, multipliers)             # scalar → vector
      @alloc_below field_threshold gradient!(std_, sv, multipliers)            # vector → tensor
      @alloc_below field_threshold symmetric_gradient!(std_, sv, multipliers)  # vector → tensor, fused sym∇

      # ----- transforms, all tensor orders (plans reuse their own work buffers; invariant 11) -----
      @alloc_below field_threshold to_physical!(psd, ss, scalar_plans)
      @alloc_below transform_threshold(3) to_physical!(pvd, sv, vector_plans)
      @alloc_below transform_threshold(9) to_physical!(ptd, st, tensor_plans)
      # The preserving scratch arity (decision 64): allocation-free is its entire reason to exist, so
      # this pin IS the feature. The destination fields double as scratch here — they are spectral
      # fields of the right context whose contents this audit does not reuse.
      @alloc_below field_threshold to_physical!(psd, ss, scalar_plans, ssd)
      @alloc_below transform_threshold(3) to_physical!(pvd, sv, vector_plans, svd)
      @alloc_below transform_threshold(9) to_physical!(ptd, st, tensor_plans, std_)
      @alloc_below field_threshold to_spectral!(ssd, ps, scalar_plans)
      @alloc_below transform_threshold(3) to_spectral!(svd, pu, vector_plans)
      @alloc_below transform_threshold(9) to_spectral!(std_, pt, tensor_plans)

      # ----- convolution: scalar / vector / tensor fiber broadcast, three- and five-argument -----
      @alloc_below field_threshold convolve!(ssd, ss, kernel)
      @alloc_below field_threshold convolve!(svd, sv, kernel)
      @alloc_below field_threshold convolve!(std_, st, kernel)
      @alloc_below field_threshold convolve!(svd, sv, kernel, T(0.5), T(1))
      @alloc_below field_threshold convolve!(std_, st, kernel, T(0.5), T(1))

      # ----- the axis-factored SeparableKernel (decision 50): the builders allocate three O(N) axis
      # arrays where they used to allocate a whole field, and applying one materializes nothing. The
      # builder rows are the load-bearing ones: a regression to a materialized kernel fails them.
      separable = translation_kernel(multipliers, (T(0.3), T(-0.7), T(1.1)))
      @alloc_below field_threshold translation_kernel(multipliers, (T(0.3), T(-0.7), T(1.1)))
      @alloc_below field_threshold assignment_window(multipliers)
      @alloc_below field_threshold tophat_window(multipliers, 0.7)
      @alloc_below field_threshold inv(separable)                       # reciprocal: three O(N) axes
      @alloc_below threshold translation_kernel!(separable, multipliers, (T(0.1), T(0.2), T(0.3)))
      # Evaluating a kernel into an existing StoredKernel (decision 90) allocates nothing, in every
      # class: the pin IS the feature, the allocating `materialize_kernel` costing a field.
      materialized_destination = GBGPeriodicFields.Convolution.StoredKernel(spectral_scalar())
      radial_band = spectral_band(multipliers, T(1), T(3))
      product_kernel = convolve(radial_band, separable)
      @alloc_below threshold materialize_kernel!(materialized_destination, radial_band)
      @alloc_below threshold materialize_kernel!(materialized_destination, separable)
      @alloc_below threshold materialize_kernel!(materialized_destination, kernel)
      @alloc_below threshold materialize_kernel!(materialized_destination, product_kernel)
      @alloc_below field_threshold convolve!(ssd, ss, separable)        # applying it materializes nothing
      @alloc_below field_threshold convolve!(svd, sv, separable)
      @alloc_below field_threshold convolve!(std_, st, separable)
      @alloc_below field_threshold convolve!(svd, sv, separable, T(0.5), T(1))
      # the lazy exponential kernel and the kernel-composed combination (decision 33)
      @alloc_below field_threshold exponential_convolve!(svd, sv, multipliers, T(-0.1))
      @alloc_below field_threshold exponential_convolve!(svd, sv, multipliers, T(-0.1), T(0.5), T(1))
      @alloc_below field_threshold exponential_convolve!(ssd, ss, multipliers, T(-0.1), T(0.01), kernel_field)
      @alloc_below field_threshold exponential_convolve!(svd, T(0.3), sv, T(0.7), sv, multipliers, T(-0.1))
      @alloc_below field_threshold exponential_convolve!(ssd, T(0.3), ss, T(0.7), ss, multipliers, T(-0.1), T(0.01), kernel_field)
      @alloc_below field_threshold combine!(ssd, T(0.3), ss, T(0.7), ss, kernel)
      @alloc_below field_threshold combine!(svd, T(0.3), sv, T(0.7), sv, kernel)
      @alloc_below field_threshold combine!(std_, T(0.3), st, T(0.7), st, kernel)
      # The same passes with each COMPRESSED kernel class. A stored kernel is a plain array like the
      # fields beside it; a radial, separable or product kernel is a lazy expression of a different
      # type, so the pass reads a MIXED tuple of operands. Decision 88's first version indexed that
      # tuple through a closure the compiler did not inline, which allocated 8.3 MB per call on a
      # `16^3` vector field here and did not compile on a device, while every row above passed.
      radial_class = spectral_band(multipliers, T(1), T(2))
      product_class = convolve(spectral_cutoff(multipliers, T(3)), separable)
      for mixed in (radial_class, separable, product_class)
        @alloc_below field_threshold convolve!(svd, sv, mixed)
        @alloc_below field_threshold convolve!(std_, st, mixed)
        @alloc_below field_threshold combine!(svd, T(0.3), sv, T(0.7), sv, mixed)
        @alloc_below field_threshold combine!(std_, T(0.3), st, T(0.7), st, mixed)
      end

      # ----- add! / subtract!: physical + spectral, R = 0/1/2, field·field + field·constant + reversed -----
      for (d, a, c) in ((psd, ps, const_real), (pvd, pu, const_vec), (ptd, pt, const_ten),
                        (ssd, ss, const_real), (svd, sv, const_vec), (std_, st, const_ten))
        @alloc_below field_threshold add!(d, a, a)              # field · field
        @alloc_below field_threshold add!(d, a, c)              # field · constant
        @alloc_below field_threshold add!(d, c, a)              # constant · field (reversed; the spectral zero-mode path)
        @alloc_below field_threshold subtract!(d, a, a)
        @alloc_below field_threshold subtract!(d, a, c)
        @alloc_below field_threshold subtract!(d, c, a)
      end

      # ----- combine! (axpby α·a + β·b): physical + spectral, R = 0/1/2; coefficientwise ⇒ alias-safe -----
      for (d, a) in ((psd, ps), (pvd, pu), (ptd, pt), (ssd, ss), (svd, sv), (std_, st))
        @alloc_below field_threshold combine!(d, T(2), a, T(3), a)
      end

      # ----- mul!: field·field contractions (physical) + constant-matrix actions (linear; both reps), α/β
      # (mul! is the matrix/tensor contraction; Real scaling is `multiply!`/`*`, tested below) -----
      @alloc_below field_threshold mul!(pvd, pt, pu)                       # tensor-field · vector-field
      @alloc_below field_threshold mul!(pvd, pt, pu, T(0.5), T(1))         #   accumulate
      @alloc_below field_threshold mul!(ptd, pt, pt)                       # tensor-field · tensor-field
      @alloc_below field_threshold mul!(ptd, pt, pt, T(0.5), T(1))
      @alloc_below field_threshold mul!(pvd, const_ten, pu)               # constant matrix · vector-field (physical)
      @alloc_below field_threshold mul!(svd, const_ten, sv)               # constant matrix · vector-field (spectral)
      @alloc_below field_threshold mul!(svd, const_ten, sv, T(0.5), T(1))

      # ----- multiply!: scalar-field action, physical + spectral, with α/β where it applies -----
      @alloc_below field_threshold multiply!(pvd, ps, pu)                  # scalar-field · vector-field
      @alloc_below field_threshold multiply!(ptd, ps, pt)                  # scalar-field · tensor-field
      @alloc_below field_threshold multiply!(psd, ps, ps)                  # scalar-field · scalar-field
      @alloc_below field_threshold multiply!(pvd, const_vec, ps)          # constant · scalar-field → vector
      @alloc_below field_threshold multiply!(ptd, const_ten, ps)          # constant · scalar-field → tensor
      @alloc_below field_threshold multiply!(pvd, const_real, pu)        # Real · field (physical)
      @alloc_below field_threshold multiply!(svd, const_real, sv)       # Real · field (spectral)
      @alloc_below field_threshold multiply!(svd, const_vec, ss)        # constant · scalar-field (spectral)

      # ----- divide!: physical field / scalar-field and / Real, spectral / Real -----
      @alloc_below field_threshold divide!(pvd, pu, psd2)                  # vector-field / scalar-field
      @alloc_below field_threshold divide!(ptd, pt, psd2)                  # tensor-field / scalar-field
      @alloc_below field_threshold divide!(pvd, pu, const_real)          # field / Real (physical)
      @alloc_below field_threshold divide!(svd, sv, const_real)         # field / Real (spectral)
      @alloc_below field_threshold divide!(pvd, const_vec, psd2)         # constant / scalar-field → vector

      # ----- dot!: fiber inner products → scalar field, physical + spectral, field·field + field·constant -----
      @alloc_below field_threshold dot!(psd, pu, pv2)                      # vector · vector
      @alloc_below field_threshold dot!(psd, pt, pt)                       # tensor : tensor
      @alloc_below field_threshold dot!(psd, pu, const_vec)              # field · constant (physical)
      @alloc_below field_threshold dot!(ssd, sv, const_vec)             # field · constant (spectral)
      @alloc_below field_threshold dot!(ssd, st, const_ten)             # tensor : constant (spectral)

      # ----- cross!: physical field·field + field·constant + reversed; spectral field·constant -----
      @alloc_below field_threshold cross!(pvd, pu, pv2)
      @alloc_below field_threshold cross!(pvd, pu, const_vec)
      @alloc_below field_threshold cross!(pvd, const_vec, pu)
      @alloc_below field_threshold cross!(svd, sv, const_vec)
      @alloc_below field_threshold cross!(svd, const_vec, sv)

      # ----- transpose! / sym! / skew!: tensor index shuffles, physical + spectral -----
      @alloc_below field_threshold transpose!(ptd, pt)
      @alloc_below field_threshold transpose!(std_, st)
      @alloc_below field_threshold sym!(ptd, pt)
      @alloc_below field_threshold sym!(std_, st)
      @alloc_below field_threshold skew!(ptd, pt)
      @alloc_below field_threshold dev!(ptd, pt)   # fused: the trace is a register, not a field (was a documented materializer)
      @alloc_below field_threshold skew!(std_, st)
      @alloc_below field_threshold tr!(psd, pt)                # linear tensor → scalar, fused
      @alloc_below field_threshold tr!(ssd, st)
      @alloc_below field_threshold det!(psd, pt)               # nonlinear tensor → scalar, fused (physical only)

      # ----- map! (arbitrary φ): the fused arbitrary-map pass, physical only (decision 35's map! instance) -----
      @alloc_below field_threshold map!(det, psd, pt)                 # tensor → scalar
      @alloc_below field_threshold map!(_map_double, ptd, pt)             # tensor → tensor
      @alloc_below field_threshold map!(_map_add, pvd, pu, pv2)   # multi-input vector → vector
      @alloc_below field_threshold map!(det, psd, pt, T(0.5), T(1))   # α/β accumulate

      # ----- point-value algebra (mirrors the physical surface; same generated bodies, different base) -----
      @alloc_below threshold add!(qvd, qv, qv)
      @alloc_below threshold add!(qvd, qv, const_vec)
      @alloc_below threshold subtract!(qtd, qt, const_ten)
      @alloc_below threshold mul!(qvd, qt, qv)
      @alloc_below threshold mul!(qvd, const_ten, qv)
      @alloc_below threshold multiply!(qvd, qs, qv)
      @alloc_below threshold divide!(qvd, qv, qs_pos)
      @alloc_below threshold dot!(qsd, qv, qv)
      @alloc_below threshold cross!(qvd, qv, qv)
      @alloc_below threshold transpose!(qtd, qt)
      @alloc_below threshold sym!(qtd, qt)
      @alloc_below threshold tr!(qsd, qt)
      @alloc_below threshold det!(qsd, qt)
      @alloc_below threshold map!(det, qsd, qt)                 # map! on point-values (representation-free)
      @alloc_below threshold map!(_map_double, qtd, qt)
      @alloc_below threshold map!(_map_add, qvd, qv, qv)

      # ----- grid↔point transfer (local spline; the particle-tracking hot path) -----
      points = PointSet(T(2π) .* rand(T, M, 3))
      out_v = vector_points()
      @alloc_below threshold interpolate!(out_v, pu, points, CatmullRom)
      @alloc_below threshold anterpolate!(pvd, points, qv, CatmullRom)
      @alloc_below threshold anterpolate!(pvd, points, qv, CatmullRom, T(0.5), T(1))   # α/β accumulate
      # The traversal order (decision 78) is an OPTION on the same hot path, so it must not cost the
      # contract: passing one adds a keyword sorter and nothing else — no staging, no copy of the
      # points. `point_traversal_order` ITSELF allocates by design (its result plus the counting sort's keys
      # and bucket counts), so it is a documented allocator with a bounded guard rather than a zero
      # one, and the bound is written against the point count it is proportional to.
      visit_order = point_traversal_order(grid, points)
      @alloc_below threshold interpolate!(out_v, pu, points, CatmullRom; traversal = visit_order)
      @alloc_below threshold anterpolate!(pvd, points, qv, CatmullRom; traversal = visit_order)
      @alloc_below threshold anterpolate!(pvd, points, qv, CatmullRom, T(0.5), T(1); traversal = visit_order)
      @test (@allocated point_traversal_order(grid, points)) < 64 * M + 200_000
      # The in-place rebuild is why that bound is tolerable: a consumer whose points move stops
      # paying it per rebuild. It is NOT zero — three `KernelAbstractions` launches and the
      # validation's own leave about 1.2 KiB of host-side launch bookkeeping, the same class as the
      # FFTW callback of §4(t) — but nothing it allocates SCALES with the point count, which is the
      # property a device pool cares about. The bound is far below one point-sized array, so a
      # regression that started allocating per point could not hide under it.
      rebuild_scratch = PointTraversalOrderScratch(grid, points)
      # The bound scales with the thread count because what is left is KA launch bookkeeping, which
      # spawns per thread — a FIXED bound here was wrong the moment the suite ran threaded, and the
      # threaded CI lane would have failed it (9472 against 8192 at four threads). The same idiom as
      # the storage-family rows below. At ONE thread the spawning is absent and the true value is
      # 1248 B, which this pins tightly; above it the slack covers someone else's nondeterminism.
      rebuild_bound = Threads.nthreads() == 1 ? 4096 : 4096 * Threads.nthreads()
      @alloc_below rebuild_bound point_traversal_order!(visit_order, grid, points, rebuild_scratch)

      # ----- base-space motion (decision 73: displace! in the cover and on the torus, wrap!) -----
      motion_points = PointSet(T(2π) .* rand(T, M, 3))
      motion_source = PointSet(T(2π) .* rand(T, M, 3))
      @alloc_below threshold displace!(motion_points, (T(0.1), qv))
      @alloc_below threshold displace!(motion_points, (T(0.1), qv), (T(0.2), qv), (T(0.3), qv))
      @alloc_below threshold displace!(motion_points, motion_source, (T(0.1), qv), (T(0.2), qv))
      @alloc_below threshold displace!(motion_points, grid, (T(0.1), qv), (T(0.2), qv), (T(0.3), qv))
      @alloc_below threshold wrap!(motion_points, grid)
    end
  end
end


# Reductions that contract a field to a scalar (or a fiber) must not materialize an O(N³) field. The
# physical `inner` is a `dot`; the scalar spectral `inner` reduces a single small kₓ plane; `maximum` /
# `minimum` / `extrema` and the `maximum(abs, …)` CFL idiom are fused mapreduces; `integral` / `mean`
# reduce over the base into a fiber-sized result physically, and in spectral representation read the zero
# (DC) mode via a tiny device→host copy; `std` / `var` stream (Statistics does not materialize the
# deviations). Each allocates only O(1)/O(fiber) — measured well under a kilobyte, far under one field.
@testset "reductions do not materialize a field" begin
  for T in (Float64, Float32)
    @testset "$T" begin
      N = 24
      grid = Grid3D((N, N, N), (T(2π), T(2π), T(2π)))
      layout = RealFourierLayout()
      ps = ScalarFieldPhysical(rand(T, N, N, N), grid)
      pv = VectorFieldPhysical(rand(T, N, N, N, 3), grid)
      pt = TensorFieldPhysical(rand(T, N, N, N, 3, 3), grid)
      scalar_plans = FieldTransformPlans(ScalarFieldPhysical(zeros(T, N, N, N), grid),
                                         ScalarFieldSpectral(zeros(Complex{T}, field_spectral_shape(grid, layout, Val(0))), grid))
      ss = to_spectral(ps, scalar_plans)
      vplans = FieldTransformPlans(VectorFieldPhysical(zeros(T, N, N, N, 3), grid),
                                   VectorFieldSpectral(zeros(Complex{T}, field_spectral_shape(grid, layout, Val(1))), grid))
      vs = to_spectral(pv, vplans)
      tplans = FieldTransformPlans(TensorFieldPhysical(zeros(T, N, N, N, 3, 3), grid),
                                   TensorFieldSpectral{2}(zeros(Complex{T}, field_spectral_shape(grid, layout, Val(2))), grid))
      ts = to_spectral(pt, tplans)
      threshold = sizeof(field_data(vs)) ÷ 16

      @alloc_below threshold inner(pv, pv)                 # physical inner = dot
      @alloc_below threshold inner(ss, ss)                 # scalar spectral inner: small kₓ planes, ≪ one field
      @alloc_below threshold inner(vs, vs)                 # spectral vector inner(f,f): fused abs2 fast path, allocation-free
      @alloc_below threshold l2norm(pv)                    # = sqrt(inner): physical, dot
      @alloc_below threshold l2norm(vs)                    # = sqrt(inner(f,f)): spectral, allocation-free
      # weighted_inner ⟨f, w·g⟩: fused lazy-broadcast reduction, only `_parseval_weight`'s tiny (Nkx,) vector
      wfield = ScalarFieldSpectral(zeros(Complex{T}, field_spectral_shape(grid, layout, Val(0))), grid)
      field_data(wfield) .= one(Complex{T})
      wkernel = GBGPeriodicFields.Convolution.StoredKernel(wfield)   # a weight is a kernel
      @alloc_below threshold weighted_inner(ss, wkernel)       # scalar self-pairing (g = f)
      @alloc_below threshold weighted_inner(vs, wkernel)       # vector self-pairing (weight broadcasts over fiber)
      # The tuple form (decision 72) must stay as light as the single one: it shares the pass rather
      # than adding one, so n weights must not cost n times the scratch.
      @alloc_below threshold weighted_inner(vs, (wkernel, wkernel, wkernel))
      @alloc_below threshold weighted_inner(ss, ss, wkernel)   # mixed scalar
      # ...and every other storage class stays fused too (decision 62): the compressed kernels are lazy,
      # so admitting them materializes no coefficients — this is the assertion that would catch a widening
      # that quietly reached for `materialize_kernel`.
      mult_w = FieldSpectralMultipliers(ss)
      @alloc_below threshold weighted_inner(ss, spectral_cutoff(mult_w, T(2.5)))    # RadialKernel
      @alloc_below threshold weighted_inner(ss, assignment_window(mult_w))          # SeparableKernel
      @alloc_below threshold weighted_inner(ss, convolve(spectral_cutoff(mult_w, T(2.5)),
                                                        assignment_window(mult_w))) # ProductKernel
      # radial_spectrum: since decision 34 the shell index, fiber contraction, and Parseval weight are
      # derived per mode inside the binning kernel, so the only arrays are the tiny shell accumulators
      m = FieldSpectralMultipliers(vs)
      @alloc_below threshold radial_spectrum(ss, m)
      @alloc_below threshold radial_spectrum(vs, m)
      @alloc_below threshold radial_spectrum(ts, m)
      @alloc_below threshold radial_spectrum(vs, vs, m)        # the cross-power form shares the kernel
      @alloc_below threshold maximum(ps)                   # scalar-section maximum
      @alloc_below threshold minimum(ps)
      @alloc_below threshold extrema(ps)
      @alloc_below threshold maximum(abs, field_data(pv))  # the CFL-speed idiom (fused mapreduce)
      @alloc_below threshold integral(ps)
      @alloc_below threshold integral(pv)
      @alloc_below threshold integral(pt)
      @alloc_below threshold mean(ps)
      @alloc_below threshold mean(pv)
      @alloc_below threshold std(ps)                       # var/std are scalar-only now (decision 49)
      @alloc_below threshold var(ps)
      @alloc_below threshold cov(pv)                       # the covariance tensor of a vector field: O(fiber), no field
      # spectral integral/mean read the zero (DC) mode via a tiny device→host copy (O(1)/O(fiber)), no field
      @alloc_below threshold integral(ss)
      @alloc_below threshold integral(vs)
      @alloc_below threshold integral(ts)
      @alloc_below threshold mean(ss)
      @alloc_below threshold mean(vs)
      @alloc_below threshold mean(ts)
      # The mapped forms reduce a nonlinear fiber invariant with no intermediate section: the fiber is
      # gathered per base point through a lazy broadcast, so nothing section-sized is ever built. They
      # are the fused peers of the materializing `lpnorm(·, Inf)` / `mean(det(A))` spellings.
      @alloc_below threshold mean(det, pt)
      @alloc_below threshold mean(tr, pt)
      @alloc_below threshold mean(norm, pv)
      @alloc_below threshold mean(abs2, ps)
      @alloc_below threshold integral(det, pt)
      @alloc_below threshold maximum(norm, pv)                 # fused peer of lpnorm(pv, Inf)
      @alloc_below threshold minimum(norm, pv)
      @alloc_below threshold extrema(norm, pv)
      @alloc_below threshold mean(norm, VectorPointValues(rand(T, 64, 3)))   # point-values base
    end
  end
end


# Spectral `inner(f, g)` of two DISTINCT vector/tensor fields is the one reduction that allocates above
# O(1): the kₓ = 0 (and even-Nₓ Nyquist) Parseval correction is `sum(conj.(ĝ).*f̂)` over a single kₓ plane,
# and that product-broadcast materializes — TWO plane-sized (O(N²)) temporaries per call. It is NOT O(N³):
# a `dot` over the strided plane view (which would fuse, no temporary) is unsupported on the GPU (rocBLAS
# `dotc` has no strided method — verified). The f === g case (an energy / `l2norm`) takes the fused-`abs2`
# fast path and is allocation-free (tested above); only the genuinely mixed f ≠ g inner pays the O(N²) — and
# the demos' hot-loop energies are `inner(f, f)` or the physical `inner` (a `dot`), never this. This guard
# pins it to "a few planes, never a field": it catches a regression to an O(N³) full-field materialization.
@testset "spectral inner of two DISTINCT fields allocates only the O(N²) correction planes" begin
  for T in (Float64, Float32)
    @testset "$T" begin
      N = 24
      grid = Grid3D((N, N, N), (T(2π), T(2π), T(2π)))
      layout = RealFourierLayout()
      vplans = FieldTransformPlans(VectorFieldPhysical(zeros(T, N, N, N, 3), grid),
                                   VectorFieldSpectral(zeros(Complex{T}, field_spectral_shape(grid, layout, Val(1))), grid))
      vs  = to_spectral(VectorFieldPhysical(rand(T, N, N, N, 3), grid), vplans)
      vs2 = to_spectral(VectorFieldPhysical(rand(T, N, N, N, 3), grid), vplans)
      half_field = sizeof(field_data(vs)) ÷ 2       # > 2 correction planes (≈ field/6), < one full field

      @alloc_below half_field inner(vs, vs2)          # f ≠ g: the O(N²) correction-plane broadcast
    end
  end
end


# The documented diagnostic allocators: `norm!`/`lpnorm` materialize the pointwise magnitude, and
# `radial_correlation` a bounded O(1) set — the per-component power field it
# transforms plus the allocating inverse transform (whose input copy is invariant-11 semantics); its
# staging arrays fused into the binning kernel (decision 34). (`dev!` left this list when the fused
# executor made its trace a per-element register — it is pinned in the main audit now.) They are NOT alloc-free by design — they
# are diagnostics whose cost is a few whole fields, not hot-loop calls. This guard only bounds them so a
# regression to O(N) extra (or, for the binning, back to O(shells) ≈ 220 fields) is caught while the
# legitimate few-field temporaries are allowed. `radial_spectrum` no longer belongs here: since its
# staging fused away it allocates only the shell accumulators, and it is pinned tight in the main audit.
@testset "documented diagnostic allocators are bounded (not O(shells))" begin
  for T in (Float64, Float32)
    @testset "$T" begin
      N = 24
      grid = Grid3D((N, N, N), (T(2π), T(2π), T(2π)))
      layout = RealFourierLayout()
      ps = ScalarFieldPhysical(zeros(T, N, N, N), grid)
      pv = VectorFieldPhysical(rand(T, N, N, N, 3), grid)
      pt = TensorFieldPhysical(rand(T, N, N, N, 3, 3), grid)
      ptd = TensorFieldPhysical(zeros(T, N, N, N, 3, 3), grid)
      vplans = FieldTransformPlans(VectorFieldPhysical(zeros(T, N, N, N, 3), grid),
                                   VectorFieldSpectral(zeros(Complex{T}, field_spectral_shape(grid, layout, Val(1))), grid))
      m = FieldSpectralMultipliers(VectorFieldSpectral(zeros(Complex{T}, field_spectral_shape(grid, layout, Val(1))), grid))
      vs = to_spectral(pv, vplans)

      bound = 8 * sizeof(field_data(pv))            # ≤ 8 physical vector fields; an O(shells) regression is ~220
      @alloc_below bound norm!(ps, pv)
      @alloc_below bound lpnorm(pv, 3)
      @alloc_below bound radial_correlation(vs, vplans)
      @alloc_below bound radial_correlation(vs, vs, vplans)
    end
  end
end


@testset "the radial-symbol operators allocate NOTHING, not merely less than a field (decision 70)" begin
  # `field_threshold` is generous on purpose — it exists to catch a MATERIALIZED FIELD — and that
  # generosity is exactly why 144 B per call lived underneath it for the life of these operators:
  # `_squared_wavenumber_broadcast` and `_wavenumber_broadcast_view` rebuilt their `reshape` wrappers
  # every invocation, 48 B each. The audit said "no field" and the docs said "allocates nothing", and
  # only the consuming solver, counting bytes per step, could tell the two claims apart (2026-08-23).
  #
  # Serial is where "nothing" can be asserted literally. Threaded, `Base.Threads` allocates its own
  # task state per `_assign!` — kilobytes, independent of the grid — so that lane keeps a bound. Both
  # lanes assert something, because a testset that silently skips is how the gap reappears.
  for T in (Float64, Float32)
    @testset "$T" begin
      grid, layout = Grid3D((16, 16, 16), T.((2pi, 2pi, 2pi))), RealFourierLayout()
      sv  = VectorFieldSpectral(zeros(Complex{T}, field_spectral_shape(grid, layout, Val(1))...), grid, layout)
      dst = VectorFieldSpectral(zeros(Complex{T}, field_spectral_shape(grid, layout, Val(1))...), grid, layout)
      ss  = ScalarFieldSpectral(zeros(Complex{T}, field_spectral_shape(grid, layout, Val(0))...), grid, layout)
      m   = FieldSpectralMultipliers(sv)
      calls = (() -> laplacian!(dst, sv, m),
               () -> inverse_laplacian!(dst, sv, m),
               () -> divergence!(ss, sv, m),
               () -> exponential_convolve!(dst, sv, m, T(-0.01)))
      bound = Threads.nthreads() == 1 ? 1 : 4096 * Threads.nthreads()
      for call in calls
        call()                                    # warm up
        @test (@allocated call()) < bound
      end
    end
  end
end


@testset "caller-controlled counts allocate nothing past the group size (decision 88)" begin
  # `add!`/`subtract!`, `map!`, `displace!` and `weighted_inner` take as many operands as the caller
  # passes, and each now works through them in fixed-size groups. The rows above stop at three
  # operands, below the first group boundary, so they cannot see what grouping costs. These rows go
  # past it, and past Julia's 32-element tuple threshold, where a tuple-mapping implementation
  # falls off its specialized path and starts allocating.
  #
  # The calls are built with `@eval` so every operand is a literal argument at the call site. A
  # splat of more than 32 operands, `add!(d, operands...)`, allocates on the CALLER's side before the
  # package is entered, which would make these rows measure the test rather than the operation.
  #
  # Serial, the true value is zero and is asserted as such. Threaded, each pass is one threaded
  # assignment carrying `Base.Threads` task state, so the slack is per pass: grouping multiplies
  # passes, and that is the only cost it is allowed to add.
  for T in (Float64, Float32)
    @testset "$T" begin
      N, M = 24, 4000
      grid, layout = Grid3D((N, N, N), T.((2pi, 2pi, 2pi))), RealFourierLayout()
      fields = [VectorFieldPhysical(rand(T, N, N, N, 3), grid, layout) for _ in 1:33]
      values = [VectorPointValues(rand(T, M, 3)) for _ in 1:33]
      tensors = [TensorFieldPhysical{2}(rand(T, N, N, N, 3, 3), grid, layout) for _ in 1:6]
      tensor_values = [TensorPointValues(rand(T, M, 3, 3)) for _ in 1:6]
      points, source = PointSet(T(2pi) .* rand(T, M, 3)), PointSet(T(2pi) .* rand(T, M, 3))
      per_pass = Threads.nthreads() == 1 ? 1 : 4096 * Threads.nthreads()

      for n in (9, 33)
        combine_passes = 1 + cld(n - 8, 7)          # eight operands, then seven more per pass
        bound = combine_passes * per_pass
        @eval @alloc_below $bound add!($(fields[1]), $(fields[1:n]...))
        @eval @alloc_below $bound subtract!($(fields[1]), $(fields[1:n]...))
        @eval @alloc_below $bound add!($(values[1]), $(values[1:n]...))
        @eval @alloc_below $bound subtract!($(values[1]), $(values[1:n]...))

        terms = [(T(0.01), values[i]) for i in 1:n]
        bound = cld(n, 8) * per_pass                # eight terms per pass
        @eval @alloc_below $bound displace!($points, $(terms...))
        @eval @alloc_below $bound displace!($points, $grid, $(terms...))
        @eval @alloc_below $bound displace!($points, $source, $(terms...))
        @eval @alloc_below $bound displace!($points, $source, $grid, $(terms...))
      end

      @eval @alloc_below $per_pass map!(_six_tensor_map, $(tensors[1]), $(tensors...))
      @eval @alloc_below $per_pass map!(_six_tensor_map, $(tensor_values[1]), $(tensor_values...))
      # Thirty-three sources. The per-point fiber reads recursed over the sources and splatted the
      # result into φ, which past 32 allocated about 1.9 KB per point — 38 MB per call on this
      # vector field — until the call was generated with one read per source.
      @eval @alloc_below $per_pass map!(_sum_all, $(fields[1]), $(fields...))
      @eval @alloc_below $per_pass map!(_sum_all, $(values[1]), $(values...))

      # `weighted_inner` is not allocation-free — one call carries the Parseval weight's row, a few
      # hundred bytes — so the claim is relative: n weights cost no more than their groups of four,
      # each priced at one single-weight call. A regression that allocated per weight, or per mode,
      # breaks it.
      scalar = ScalarFieldSpectral(zeros(Complex{T}, field_spectral_shape(grid, layout, Val(0))...), grid, layout)
      spectral = similar_field(scalar, Val(1))
      field_data(spectral) .= one(Complex{T})
      multipliers = FieldSpectralMultipliers(spectral)
      classes = (spectral_band(multipliers, T(1), T(2)), assignment_window(multipliers),
                 materialize_kernel(spectral_cutoff(multipliers, T(3))),
                 convolve(spectral_cutoff(multipliers, T(3)), assignment_window(multipliers)))
      weighted_inner(spectral, classes[1])
      single = @allocated weighted_inner(spectral, classes[1])
      for n in (9, 33)
        weights = ntuple(i -> classes[mod1(i, 4)], n)
        bound = cld(n, 4) * single + 1
        @eval @alloc_below $bound weighted_inner($spectral, $weights)
      end
    end
  end
end


@testset "the transforms allocate LITERALLY ZERO, not merely below a field" begin
  # `field_threshold` is `sizeof(one field) + 4096 * nthreads()`, and that slack exists for a real
  # reason: FFTW reaches its workers through a Julia callback, so a plan built with more than one
  # thread allocates task state per call — size-independent and nondeterministic, 7008 to 48557 B for
  # the SAME configuration across runs (`docs/PERFORMANCE.md` §4(t)). A threshold is the only honest
  # bound while that callback is live.
  #
  # But the slack also HID a defect. Decision 76 applied a rank-agnostic plan per component by first
  # reshaping the fiber into a trailing component axis, and `reshape` on an `Array` returns a new
  # `Array` sharing the data — a heap-allocated wrapper, twice per transform, a constant 128 B per
  # call whatever the rank or the grid. Comfortably under the threshold, invisible here for ten days,
  # and caught by a CONSUMER whose own hot-loop invariant asserts literal zero. A threshold cannot see
  # a constant that never grows, so the class is pinned at its true value where that value is
  # knowable: single-threaded FFTW, where the callback is gone and the only bytes left are ours.
  try
    set_fft_threads!(1)
    for T in (Float64, Float32)
      @testset "$T" begin
        grid = Grid3D((8, 8, 8), (T(2π), T(2π), T(2π)))
        layout = RealFourierLayout()
        physicals = (ScalarFieldPhysical(zeros(T, 8, 8, 8), grid),
                     VectorFieldPhysical(zeros(T, 8, 8, 8, 3), grid),
                     TensorFieldPhysical{2}(zeros(T, 8, 8, 8, 3, 3), grid))
        for (R, physical) in enumerate(physicals)
          shape = GBGPeriodicFields.field_spectral_shape(grid, layout, Val(R - 1))
          spectral = R == 1 ? ScalarFieldSpectral(zeros(Complex{T}, shape...), grid, layout) :
                     R == 2 ? VectorFieldSpectral(zeros(Complex{T}, shape...), grid, layout) :
                              TensorFieldSpectral{2}(zeros(Complex{T}, shape...), grid, layout)
          scratch = similar_field(spectral, similar(field_data(spectral)))
          plans = FieldTransformPlans(physical, spectral)
          to_spectral!(spectral, physical, plans)                       # warm both paths first
          to_physical!(physical, spectral, plans, scratch)
          @test (@allocated to_spectral!(spectral, physical, plans)) == 0
          @test (@allocated to_physical!(physical, spectral, plans, scratch)) == 0
        end
      end
    end
  finally
    set_fft_threads!(Threads.nthreads())   # the default `__init__` installs
  end
end


@testset "adapt! moves into a destination without allocating (decision 69)" begin
  # The whole reason the verb exists: finding (x) measured the return trip at a quarter of the
  # outbound rate and attributed the gap to allocating the destination. A form that allocated one
  # anyway would be pointless, so this is the assertion the feature stands on. Both representations
  # and both point sections, since each has its own method.
  for T in (Float64, Float32)
    @testset "$T" begin
      grid = Grid3D((8, 8, 8), T.((2pi, 2pi, 2pi)))
      layout = RealFourierLayout()
      pv = VectorFieldPhysical(rand(T, 8, 8, 8, 3), grid, layout)
      sv = VectorFieldSpectral(rand(Complex{T}, field_spectral_shape(grid, layout, Val(1))...), grid, layout)
      q  = VectorPointValues(randn(T, 12, 3))
      ps = PointSet(rand(T, 12, 3))
      # The destinations are built HERE, not inside the measured expression: `similar_field`
      # allocates a whole field, so measuring `adapt!(similar_field(...), x)` measures the allocation
      # this operation exists to avoid. Preallocated is the only state in which the question means
      # anything.
      into_pv, into_sv = similar_field(pv, Val(1)), similar_field(sv, Val(1))
      into_q, into_ps  = similar_point_values(q, Val(1)), PointSet(rand(T, 12, 3))
      @alloc_below 64 adapt!(into_pv, pv)
      @alloc_below 64 adapt!(into_sv, sv)
      @alloc_below 64 adapt!(into_q, q)
      @alloc_below 64 adapt!(into_ps, ps)
    end
  end
end


# ---------------------------------------------------------------------------------------------
# Completeness (decision 53). The audit above is a hand-written list, and a hand-written list is
# only as complete as the last person's memory — which is exactly how the (compressed kernel ×
# operator) quadrant of decision 50 ended up with no row at all. Derive the requirement instead:
# every exported in-place operation must have been exercised above, or be named here with a reason.
GBGCodingTools.TestHarness.allocation_completeness(GBGPeriodicFields,
    filter(m -> m !== GBGPeriodicFields, collect(PACKAGE_MODULES));
    exempt = Dict(
      :copyto!               => "the broadcast interface: the field `copyto!` IS the `_assign!` route every audited operation writes through, measured through them rather than as a case of its own",
      :setindex!             => "the AbstractArray interface: a single-element write, not a field-shaped pass",
      :set_fft_threads!      => "a configuration setter, not a field operation: it re-plans FFTW and allocates by design",
      :set_threading_cutoff! => "a configuration setter, not a field operation",
    ))
