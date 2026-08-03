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
# (`norm!`/`lpnorm`/`std`/`var` materialize one field by design — `dev!` no longer does, its trace fused
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


# Warm up `expr` once, then assert a single call allocates strictly less than `bound` bytes. A thrown
# error (e.g. a mistyped signature in this file) becomes a failed test rather than aborting the testset,
# so one bad line cannot mask every check after it.
# Every audited call records the operation it exercised, so the completeness testset at the foot of
# this file can be DERIVED from the export list rather than trusted to memory (decision 53).
const AUDITED_OPS = Set{Symbol}()

macro alloc_below(bound, expr)
  callee = (expr isa Expr && expr.head === :call && expr.args[1] isa Symbol) ? expr.args[1] : nothing
  record = callee === nothing ? :() : :(push!(AUDITED_OPS, $(QuoteNode(callee))))
  quote
    $record
    local limit = $(esc(bound))
    try
      $(esc(expr))                              # warm-up call (compilation, plan/first-touch)
      @test (@allocated $(esc(expr))) < limit
    catch err
      @error "alloc check threw (likely a test-side signature error, not an allocation)" exception = (err, catch_backtrace())
      @test false
    end
  end
end


# Named maps for the map! rows: `@alloc_below` splices its expr twice (warm-up + measure), which would
# give an anonymous closure two distinct types (only the second is timed, so it would read as a compile
# allocation). A named function has one type across both splices, so it warms up correctly.
_map_double(x) = 2x
_map_add(a, b) = a + b


@testset "allocation audit" begin
  for T in (Float64, Float32)
    @testset "$T" begin
      N = 24
      M = 4000                                  # enough points that a point-value temporary exceeds `threshold`
      grid = Grid3D((N, N, N), (T(2π), T(2π), T(2π)))
      layout = RealFourierLayout()

      spectral_vector() = VectorFieldSpectral(zeros(Complex{T}, spectral_field_shape(grid, layout, Val(1))), grid)
      spectral_scalar() = ScalarFieldSpectral(zeros(Complex{T}, spectral_field_shape(grid, layout, Val(0))), grid)
      spectral_tensor() = TensorFieldSpectral(zeros(Complex{T}, spectral_field_shape(grid, layout, Val(2))), grid)
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

      # ----- spectral differential operators (lazy |k|² + fused kernels; decision 24) -----
      @alloc_below field_threshold laplacian!(svd, sv, multipliers)
      @alloc_below field_threshold inverse_laplacian!(svd, sv, multipliers)
      @alloc_below field_threshold helmholtz_projection!(svd, sv, multipliers)
      @alloc_below field_threshold helmholtz_projection!(svd, svd, multipliers)                       # aliased in place — the one-pass kernel needs no guard temporary (decision 32)
      @alloc_below field_threshold helmholtz_projection!(svd, sv, multipliers, kernel)                # kernel-composed ℙ
      @alloc_below field_threshold helmholtz_projection!(svd, sv, multipliers, kernel, T(0.5), T(1))
      @alloc_below field_threshold curl!(svd, sv, multipliers)
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
      @alloc_below field_threshold to_physical!(pvd, sv, vector_plans)
      @alloc_below field_threshold to_physical!(ptd, st, tensor_plans)
      @alloc_below field_threshold to_spectral!(ssd, ps, scalar_plans)
      @alloc_below field_threshold to_spectral!(svd, pu, vector_plans)
      @alloc_below field_threshold to_spectral!(std_, pt, tensor_plans)

      # ----- convolution: scalar / vector / tensor fiber broadcast, three- and five-argument -----
      @alloc_below field_threshold convolve!(ssd, ss, kernel)
      @alloc_below field_threshold convolve!(svd, sv, kernel)
      @alloc_below field_threshold convolve!(std_, st, kernel)
      @alloc_below field_threshold convolve!(svd, sv, kernel, T(0.5), T(1))
      @alloc_below field_threshold convolve!(std_, st, kernel, T(0.5), T(1))

      # ----- the axis-factored SeparableKernel (decision 50): the builders allocate three O(N) axis
      # arrays where they used to allocate a whole field, and applying one materializes nothing. The
      # builder rows are the load-bearing ones: a regression to a materialized kernel fails them.
      separable = translation_kernel(ss, multipliers, (T(0.3), T(-0.7), T(1.1)))
      @alloc_below field_threshold translation_kernel(ss, multipliers, (T(0.3), T(-0.7), T(1.1)))
      @alloc_below field_threshold assignment_window(ss, multipliers)
      @alloc_below field_threshold inv(separable)                       # reciprocal: three O(N) axes
      @alloc_below threshold translation_kernel!(separable, multipliers, (T(0.1), T(0.2), T(0.3)))
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
                                         ScalarFieldSpectral(zeros(Complex{T}, spectral_field_shape(grid, layout, Val(0))), grid))
      ss = to_spectral(ps, scalar_plans)
      vplans = FieldTransformPlans(VectorFieldPhysical(zeros(T, N, N, N, 3), grid),
                                   VectorFieldSpectral(zeros(Complex{T}, spectral_field_shape(grid, layout, Val(1))), grid))
      vs = to_spectral(pv, vplans)
      tplans = FieldTransformPlans(TensorFieldPhysical(zeros(T, N, N, N, 3, 3), grid),
                                   TensorFieldSpectral{2}(zeros(Complex{T}, spectral_field_shape(grid, layout, Val(2))), grid))
      ts = to_spectral(pt, tplans)
      threshold = sizeof(field_data(vs)) ÷ 16

      @alloc_below threshold inner(pv, pv)                 # physical inner = dot
      @alloc_below threshold inner(ss, ss)                 # scalar spectral inner: small kₓ planes, ≪ one field
      @alloc_below threshold inner(vs, vs)                 # spectral vector inner(f,f): fused abs2 fast path, allocation-free
      @alloc_below threshold l2norm(pv)                    # = sqrt(inner): physical, dot
      @alloc_below threshold l2norm(vs)                    # = sqrt(inner(f,f)): spectral, allocation-free
      # weighted_inner ⟨f, w·g⟩: fused lazy-broadcast reduction, only `_parseval_weight`'s tiny (Nkx,) vector
      wfield = ScalarFieldSpectral(zeros(Complex{T}, spectral_field_shape(grid, layout, Val(0))), grid)
      field_data(wfield) .= one(Complex{T})
      wkernel = GBGPeriodicFields.Convolution.StoredKernel(wfield)   # a weight is a kernel
      @alloc_below threshold weighted_inner(ss, wkernel)       # scalar self-pairing (g = f)
      @alloc_below threshold weighted_inner(vs, wkernel)       # vector self-pairing (weight broadcasts over fiber)
      @alloc_below threshold weighted_inner(ss, ss, wkernel)   # mixed scalar
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
                                   VectorFieldSpectral(zeros(Complex{T}, spectral_field_shape(grid, layout, Val(1))), grid))
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
                                   VectorFieldSpectral(zeros(Complex{T}, spectral_field_shape(grid, layout, Val(1))), grid))
      m = FieldSpectralMultipliers(VectorFieldSpectral(zeros(Complex{T}, spectral_field_shape(grid, layout, Val(1))), grid))
      vs = to_spectral(pv, vplans)

      bound = 8 * sizeof(field_data(pv))            # ≤ 8 physical vector fields; an O(shells) regression is ~220
      @alloc_below bound norm!(ps, pv)
      @alloc_below bound lpnorm(pv, 3)
      @alloc_below bound radial_correlation(vs, vplans)
      @alloc_below bound radial_correlation(vs, vs, vplans)
    end
  end
end


# ---------------------------------------------------------------------------------------------
# Completeness (decision 53). The audit above is a hand-written list, and a hand-written list is
# only as complete as the last person's memory — which is exactly how the (compressed kernel ×
# operator) quadrant of decision 50 ended up with no row at all. Derive the requirement instead:
# every exported in-place operation must have been exercised above, or be named here with a reason.
@testset "every exported in-place operation has an allocation row" begin
  exempt = Dict(
    :copyto!               => "the broadcast interface: the field `copyto!` IS the `_assign!` route every audited operation writes through, measured through them rather than as a case of its own",
    :setindex!             => "the AbstractArray interface: a single-element write, not a field-shaped pass",
    :set_fft_threads!      => "a configuration setter, not a field operation: it re-plans FFTW and allocates by design",
    :set_threading_cutoff! => "a configuration setter, not a field operation",
  )
  required = inplace_operations()
  uncovered = setdiff(required, AUDITED_OPS, keys(exempt))
  isempty(uncovered) ||
    @error "in-place operations with no allocation row — add one, or exempt it with a reason" uncovered
  @test isempty(uncovered)
  # An exemption that no longer names a real operation is stale; drop it.
  @test isempty(setdiff(keys(exempt), required))

  # A guard needs a guard: every captured name must be a real package function, so a bookkeeping
  # slip cannot silently shrink the covered set (the sibling ledger had exactly that — see there).
  phantoms = setdiff(AUDITED_OPS, all_package_functions())
  isempty(phantoms) || @error "audited names that match no real function" phantoms
  @test isempty(phantoms)
end
