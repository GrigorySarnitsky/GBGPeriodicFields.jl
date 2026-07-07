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
# (`norm!`/`dev!`/`lpnorm`/`std`/`var` materialize one field by design; the radial diagnostics allocate a
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
using Statistics: mean, std, var              # `Reductions` extends these; bring them into scope to call


# Warm up `expr` once, then assert a single call allocates strictly less than `bound` bytes. A thrown
# error (e.g. a mistyped signature in this file) becomes a failed test rather than aborting the testset,
# so one bad line cannot mask every check after it.
macro alloc_below(bound, expr)
  quote
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

      # constants for the linear-in-field variants
      const_real = T(2)
      const_vec  = rand(FiberVector{T})
      const_ten  = rand(FiberTensor2{T})

      # spectral sources / distinct destinations
      sv, ss, st = randomize!(spectral_vector()), randomize!(spectral_scalar()), randomize!(spectral_tensor())
      svd, ssd, std_ = spectral_vector(), spectral_scalar(), spectral_tensor()
      kernel = spectral_scalar(); field_data(kernel) .= one(Complex{T})

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
      @alloc_below threshold laplacian!(svd, sv, multipliers)
      @alloc_below threshold inverse_laplacian!(svd, sv, multipliers)
      @alloc_below threshold helmholtz_projection!(svd, sv, multipliers)
      @alloc_below threshold curl!(svd, sv, multipliers)
      @alloc_below threshold divergence!(ssd, sv, multipliers)            # vector → scalar
      @alloc_below threshold divergence!(svd, st, multipliers)            # tensor → vector
      @alloc_below threshold gradient!(svd, ss, multipliers)             # scalar → vector
      @alloc_below threshold gradient!(std_, sv, multipliers)            # vector → tensor
      @alloc_below threshold symmetric_gradient!(std_, sv, multipliers)  # vector → tensor, fused sym∇

      # ----- transforms, all tensor orders (plans reuse their own work buffers; invariant 11) -----
      @alloc_below threshold to_physical!(psd, ss, scalar_plans)
      @alloc_below threshold to_physical!(pvd, sv, vector_plans)
      @alloc_below threshold to_physical!(ptd, st, tensor_plans)
      @alloc_below threshold to_spectral!(ssd, ps, scalar_plans)
      @alloc_below threshold to_spectral!(svd, pu, vector_plans)
      @alloc_below threshold to_spectral!(std_, pt, tensor_plans)

      # ----- convolution: scalar / vector / tensor fiber broadcast, three- and five-argument -----
      @alloc_below threshold convolve!(ssd, ss, kernel)
      @alloc_below threshold convolve!(svd, sv, kernel)
      @alloc_below threshold convolve!(std_, st, kernel)
      @alloc_below threshold convolve!(svd, sv, kernel, T(0.5), T(1))
      @alloc_below threshold convolve!(std_, st, kernel, T(0.5), T(1))

      # ----- add! / subtract!: physical + spectral, R = 0/1/2, field·field + field·constant + reversed -----
      for (d, a, c) in ((psd, ps, const_real), (pvd, pu, const_vec), (ptd, pt, const_ten),
                        (ssd, ss, const_real), (svd, sv, const_vec), (std_, st, const_ten))
        @alloc_below threshold add!(d, a, a)              # field · field
        @alloc_below threshold add!(d, a, c)              # field · constant
        @alloc_below threshold add!(d, c, a)              # constant · field (reversed; the spectral zero-mode path)
        @alloc_below threshold subtract!(d, a, a)
        @alloc_below threshold subtract!(d, a, c)
        @alloc_below threshold subtract!(d, c, a)
      end

      # ----- combine! (axpby α·a + β·b): physical + spectral, R = 0/1/2; coefficientwise ⇒ alias-safe -----
      for (d, a) in ((psd, ps), (pvd, pu), (ptd, pt), (ssd, ss), (svd, sv), (std_, st))
        @alloc_below threshold combine!(d, T(2), a, T(3), a)
      end

      # ----- mul!: field·field contractions (physical) + constant-matrix actions (linear; both reps), α/β
      # (mul! is the matrix/tensor contraction; Real scaling is `multiply!`/`*`, tested below) -----
      @alloc_below threshold mul!(pvd, pt, pu)                       # tensor-field · vector-field
      @alloc_below threshold mul!(pvd, pt, pu, T(0.5), T(1))         #   accumulate
      @alloc_below threshold mul!(ptd, pt, pt)                       # tensor-field · tensor-field
      @alloc_below threshold mul!(ptd, pt, pt, T(0.5), T(1))
      @alloc_below threshold mul!(pvd, const_ten, pu)               # constant matrix · vector-field (physical)
      @alloc_below threshold mul!(svd, const_ten, sv)               # constant matrix · vector-field (spectral)
      @alloc_below threshold mul!(svd, const_ten, sv, T(0.5), T(1))

      # ----- multiply!: scalar-field action, physical + spectral, with α/β where it applies -----
      @alloc_below threshold multiply!(pvd, ps, pu)                  # scalar-field · vector-field
      @alloc_below threshold multiply!(ptd, ps, pt)                  # scalar-field · tensor-field
      @alloc_below threshold multiply!(psd, ps, ps)                  # scalar-field · scalar-field
      @alloc_below threshold multiply!(pvd, const_vec, ps)          # constant · scalar-field → vector
      @alloc_below threshold multiply!(ptd, const_ten, ps)          # constant · scalar-field → tensor
      @alloc_below threshold multiply!(pvd, const_real, pu)        # Real · field (physical)
      @alloc_below threshold multiply!(svd, const_real, sv)       # Real · field (spectral)
      @alloc_below threshold multiply!(svd, const_vec, ss)        # constant · scalar-field (spectral)

      # ----- divide!: physical field / scalar-field and / Real, spectral / Real -----
      @alloc_below threshold divide!(pvd, pu, psd2)                  # vector-field / scalar-field
      @alloc_below threshold divide!(ptd, pt, psd2)                  # tensor-field / scalar-field
      @alloc_below threshold divide!(pvd, pu, const_real)          # field / Real (physical)
      @alloc_below threshold divide!(svd, sv, const_real)         # field / Real (spectral)
      @alloc_below threshold divide!(pvd, const_vec, psd2)         # constant / scalar-field → vector

      # ----- dot!: fiber inner products → scalar field, physical + spectral, field·field + field·constant -----
      @alloc_below threshold dot!(psd, pu, pv2)                      # vector · vector
      @alloc_below threshold dot!(psd, pt, pt)                       # tensor : tensor
      @alloc_below threshold dot!(psd, pu, const_vec)              # field · constant (physical)
      @alloc_below threshold dot!(ssd, sv, const_vec)             # field · constant (spectral)
      @alloc_below threshold dot!(ssd, st, const_ten)             # tensor : constant (spectral)

      # ----- cross!: physical field·field + field·constant + reversed; spectral field·constant -----
      @alloc_below threshold cross!(pvd, pu, pv2)
      @alloc_below threshold cross!(pvd, pu, const_vec)
      @alloc_below threshold cross!(pvd, const_vec, pu)
      @alloc_below threshold cross!(svd, sv, const_vec)
      @alloc_below threshold cross!(svd, const_vec, sv)

      # ----- transpose! / sym! / skew!: tensor index shuffles, physical + spectral -----
      @alloc_below threshold transpose!(ptd, pt)
      @alloc_below threshold transpose!(std_, st)
      @alloc_below threshold sym!(ptd, pt)
      @alloc_below threshold sym!(std_, st)
      @alloc_below threshold skew!(ptd, pt)
      @alloc_below threshold skew!(std_, st)
      @alloc_below threshold tr!(psd, pt)                # linear tensor → scalar, fused (unlike dev!)
      @alloc_below threshold tr!(ssd, st)
      @alloc_below threshold det!(psd, pt)               # nonlinear tensor → scalar, fused (physical only)

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
      wkernel = ScalarFieldSpectral(zeros(Complex{T}, spectral_field_shape(grid, layout, Val(0))), grid)
      field_data(wkernel) .= one(Complex{T})
      @alloc_below threshold weighted_inner(ss, wkernel)       # scalar self-pairing (g = f)
      @alloc_below threshold weighted_inner(vs, wkernel)       # vector self-pairing (weight broadcasts over fiber)
      @alloc_below threshold weighted_inner(ss, ss, wkernel)   # mixed scalar
      @alloc_below threshold maximum(ps)                   # scalar-section maximum
      @alloc_below threshold minimum(ps)
      @alloc_below threshold extrema(ps)
      @alloc_below threshold maximum(abs, field_data(pv))  # the CFL-speed idiom (fused mapreduce)
      @alloc_below threshold integral(ps)
      @alloc_below threshold integral(pv)
      @alloc_below threshold integral(pt)
      @alloc_below threshold mean(ps)
      @alloc_below threshold mean(pv)
      @alloc_below threshold std(pv)
      @alloc_below threshold var(pv)
      # spectral integral/mean read the zero (DC) mode via a tiny device→host copy (O(1)/O(fiber)), no field
      @alloc_below threshold integral(ss)
      @alloc_below threshold integral(vs)
      @alloc_below threshold integral(ts)
      @alloc_below threshold mean(ss)
      @alloc_below threshold mean(vs)
      @alloc_below threshold mean(ts)
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


# The documented diagnostic allocators: `norm!`/`lpnorm` materialize the pointwise magnitude, `dev!` the
# trace it subtracts, and the radial diagnostics a bounded O(1) set (the power field + one inverse
# transform + the shell-index arrays; decision 25). They are NOT alloc-free by design — they are
# occasional diagnostics, not hot-loop calls. This guard only bounds them — at most a handful of fields —
# so a regression to O(N) extra (or, for the radial binning, back to O(shells) ≈ 220 fields) is caught
# while the legitimate few-field temporaries are allowed.
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
      @alloc_below bound dev!(ptd, pt)
      @alloc_below bound lpnorm(pv, 3)
      @alloc_below bound radial_spectrum(vs, m)
      @alloc_below bound radial_correlation(vs, vplans)
    end
  end
end
