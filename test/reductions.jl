# Behaviour tests for the L²/measure reductions (Reductions module): integral / mean / std / var /
# inner / l2norm / lpnorm / maximum, on physical fields and point-values, against analytic or manual
# references (independent of the reduction implementation). Both element types and both bases; the
# physical-only restriction is asserted as an intentional absence.

using Test
using Random: MersenneTwister
using GBGPeriodicFields
using GBGPeriodicFields: field_data
using Statistics: mean, std, var      # extended on sections in the Reductions module (not re-exported)
                                      # `det`/`tr`/`norm` (the fiber maps below) come from the package's re-export

@testset "L²/measure reductions" begin
  for T in (Float64, Float32)
    atol = T == Float64 ? 1e-12 : 1f-5

    # ---- grid: a uniform box and an anisotropic one ----
    N = 8
    g  = Grid3D((N, N, N), (T(2π), T(2π), T(2π)))
    ga = Grid3D((N, N, N), (T(2π), T(4π), T(6π)))                 # anisotropic ⇒ exercises cell volume

    @testset "grid scalar — mean/integral/extrema ($T)" begin
      c = T(3)
      s = ScalarFieldPhysical(fill(c, N, N, N), g)
      @test mean(s) ≈ c
      @test integral(s) ≈ c * prod(g.domain_size)               # ∫c dx = c|Ω|
      @test integral(s) ≈ prod(g.domain_size) * mean(s)         # extensive = |Ω|·intensive
      @test maximum(s) ≈ c && minimum(s) ≈ c && extrema(s) == (c, c)

      # analytic: ⟨sin x⟩ = 0, ⟨sin²x⟩ = 1/2 on a full period
      sx  = ScalarFieldPhysical((x, y, z) -> sin(x), g)
      sx2 = ScalarFieldPhysical((x, y, z) -> sin(x)^2, g)
      @test abs(mean(sx)) < atol
      @test mean(sx2) ≈ T(1) / 2 atol = atol
      @test var(ScalarFieldPhysical(fill(c, N, N, N), g)) ≈ 0 atol = atol
      # population variance of sin over a full period is ⟨sin²⟩ − ⟨sin⟩² = 1/2
      @test var(sx; corrected = false) ≈ T(1) / 2 atol = atol
      @test std(sx; corrected = false) ≈ sqrt(T(1) / 2) atol = atol
    end

    @testset "grid vector — fiber-valued mean, inner, norms ($T)" begin
      v = VectorFieldPhysical((x, y, z) -> (T(1), T(2), T(2)), g)
      m = mean(v)
      @test m isa FiberVector{T}
      @test m ≈ T[1, 2, 2]
      @test integral(v) isa FiberVector{T}                       # fiber-valued ∫
      @test integral(v) ≈ T[1, 2, 2] .* prod(g.domain_size)
      @test inner(v, v) ≈ T(9)                                   # ⟨|v|²⟩ = 1+4+4
      @test l2norm(v) ≈ T(3)
      @test l2norm(v) isa T                                      # element type preserved
      @test lpnorm(v, 2) ≈ l2norm(v)
      @test lpnorm(v, Inf) ≈ T(3)                                # sup |v|
      @test lpnorm(v, 4) ≈ T(3)                                  # constant ⇒ any p

      # inner symmetry and the energy identity ½⟨|u|²⟩
      u = VectorFieldPhysical((x, y, z) -> (sin(x), cos(y), sin(z) * cos(x)), g)
      @test inner(u, v) ≈ inner(v, u)
      @test 0.5 * inner(u, u) ≈ 0.5 * sum(abs2, field_data(u)) / N^3 atol = atol
      @test l2norm(u) ≈ sqrt(sum(abs2, field_data(u)) / N^3) atol = atol
    end

    @testset "grid tensor — mean is a FiberTensor2 ($T)" begin
      A = TensorFieldPhysical(ones(T, N, N, N, 3, 3), g)
      @test mean(A) isa FiberTensor2{T}
      @test mean(A) ≈ ones(T, 3, 3)
    end

    @testset "anisotropic box — integral uses the cell volume ($T)" begin
      s = ScalarFieldPhysical(fill(T(2), N, N, N), ga)
      @test integral(s) ≈ T(2) * prod(ga.domain_size)           # 2·(2π·4π·6π)
      @test mean(s) ≈ T(2)                                       # intensive: unchanged by the box
    end

    # ---- points: the counting measure ⇒ plain arithmetic mean ----
    @testset "points — mean = (1/M)·Σ, integral = Σ ($T)" begin
      sp = ScalarPointValues(T[1, 2, 3, 4])
      @test mean(sp) ≈ T(10) / 4                                 # plain sample mean
      @test integral(sp) ≈ T(10)                                 # counting ⇒ raw sum
      @test integral(sp) ≈ npoints(sp) * mean(sp)               # extensive = M·intensive
      @test l2norm(sp) ≈ sqrt(T(1 + 4 + 9 + 16) / 4)
      @test lpnorm(sp, 1) ≈ T(10) / 4                            # normalized L¹ = mean|·| = 2.5
      @test maximum(sp) ≈ T(4) && minimum(sp) ≈ T(1)
      @test var(ScalarPointValues(fill(T(5), 4))) ≈ 0 atol = atol

      vp = VectorPointValues(T[1 2 3; 4 5 6])                    # M=2 × 3 comps
      mv = mean(vp)
      @test mv isa FiberVector{T}
      @test mv ≈ T[2.5, 3.5, 4.5]                                # column means
      @test inner(vp, vp) ≈ (sum(abs2, field_data(vp))) / 2      # ⟨|·|²⟩ over 2 points

      tp = TensorPointValues(ones(T, 3, 3, 3))                   # M=3 points × 3×3
      @test mean(tp) isa FiberTensor2{T}
      @test mean(tp) ≈ ones(T, 3, 3)
    end

    # ---- the mapped forms: reduce a nonlinear fiber invariant with no intermediate section ----
    @testset "mapped reductions — mean/integral/maximum of a fiber map ($T)" begin
      # A constant diagonal tensor has analytically known invariants: det = 2·3·4, tr = 2+3+4.
      diagonal = zeros(T, N, N, N, 3, 3)
      diagonal[:, :, :, 1, 1] .= T(2)
      diagonal[:, :, :, 2, 2] .= T(3)
      diagonal[:, :, :, 3, 3] .= T(4)
      D = TensorFieldPhysical(diagonal, g)
      @test mean(det, D) ≈ T(24)
      @test mean(tr, D) ≈ T(9)
      @test mean(det, D) isa T                                   # element type preserved
      @test integral(det, D) ≈ T(24) * prod(g.domain_size)       # extensive = |Ω|·intensive
      @test maximum(det, D) ≈ T(24) && minimum(det, D) ≈ T(24)

      # The identity map must reproduce the bare, fiber-preserving reductions exactly.
      v = VectorFieldPhysical((x, y, z) -> (T(1), T(2), T(2)), g)
      @test mean(identity, v) ≈ mean(v)
      @test integral(identity, v) ≈ integral(v)
      @test mean(identity, D) ≈ mean(D)

      # Analytic: ⟨sin²x⟩ = 1/2 over a full period.
      sx = ScalarFieldPhysical((x, y, z) -> sin(x), g)
      @test mean(abs2, sx) ≈ T(0.5) atol = atol

      # `maximum(norm, ·)` is the fused peer of the materializing `lpnorm(·, Inf)`.
      @test maximum(norm, v) ≈ T(3)
      @test maximum(norm, v) ≈ lpnorm(v, Inf)
      u = VectorFieldPhysical((x, y, z) -> (sin(x), cos(y), sin(z) * cos(x)), g)
      @test maximum(norm, u) ≈ lpnorm(u, Inf) atol = atol
      @test extrema(norm, u) == (minimum(norm, u), maximum(norm, u))

      # Random tensor against an independent per-point reduction (explicit loop, not the package's).
      rng = MersenneTwister(20260719)
      noise = randn(rng, T, N, N, N, 3, 3)
      A = TensorFieldPhysical(noise, g)
      fiber_at(x, y, z) = FiberTensor2{T}(ntuple(k -> noise[x, y, z, (k - 1) % 3 + 1, (k - 1) ÷ 3 + 1], 9))
      manual_mean = sum(det(fiber_at(x, y, z)) for x in 1:N, y in 1:N, z in 1:N) / N^3
      manual_max = maximum(det(fiber_at(x, y, z)) for x in 1:N, y in 1:N, z in 1:N)
      @test mean(det, A) ≈ manual_mean atol = atol
      @test maximum(det, A) ≈ manual_max atol = atol

      # Point-values base: the same maps against the counting measure.
      vp = VectorPointValues(T[1 2 3; 4 5 6])
      @test mean(norm, vp) ≈ (sqrt(T(14)) + sqrt(T(77))) / 2
      @test maximum(norm, vp) ≈ sqrt(T(77))
      @test integral(norm, vp) ≈ sqrt(T(14)) + sqrt(T(77))       # counting ⇒ raw sum
    end

    @testset "spectral inner via Parseval == physical inner ($T)" begin
      layout = RealFourierLayout()
      rtol = T == Float64 ? 1e-10 : 1.0f-3
      # even Nₓ = 8 exercises the Nyquist correction; odd Nₓ = 7 the no-Nyquist branch
      for gp in (Grid3D((8, 8, 8), (T(2π), T(2π), T(2π))), Grid3D((7, 8, 6), (T(2π), T(2π), T(2π))))
        tospec(phys) = (R = field_tensor_order(phys);
                        shape = spectral_field_shape(gp, layout, Val(R));
                        spec0 = R == 0 ? ScalarFieldSpectral(zeros(Complex{T}, shape), gp) :
                                R == 1 ? VectorFieldSpectral(zeros(Complex{T}, shape), gp) :
                                         TensorFieldSpectral{R}(zeros(Complex{T}, shape), gp);
                        to_spectral(phys, FieldTransformPlans(phys, spec0)))
        atol = T == Float64 ? 1e-10 : 1.0f-4
        # pairs are deliberately NON-orthogonal (shared modes) so the inner is O(1) and rtol genuinely
        # exercises the Parseval normalization, not two near-zero round-off values
        f1 = ScalarFieldPhysical((x, y, z) -> sin(x) + cos(2y) * sin(z), gp)
        f2 = ScalarFieldPhysical((x, y, z) -> 2sin(x) - cos(2y) * sin(z), gp)        # ⟨f1 f2⟩ = 3/4
        u1 = VectorFieldPhysical((x, y, z) -> (sin(x), cos(y), sin(2z)), gp)
        u2 = VectorFieldPhysical((x, y, z) -> (2sin(x), cos(y), cos(z)), gp)         # ⟨u1·u2⟩ = 3/2
        A1 = TensorFieldPhysical{2}((x, y, z) -> [sin(x) cos(y) 0.3; 0.5 sin(z) cos(x); 1.0 cos(z) sin(y)], gp)
        A2 = TensorFieldPhysical{2}((x, y, z) -> [2sin(x) 0 0; 0 sin(z) 0; 0 0 sin(y)], gp)   # diagonal overlap = 2
        for (a, b) in ((f1, f2), (u1, u2), (A1, A2))
          @test isapprox(inner(tospec(a), tospec(b)), inner(a, b); rtol = rtol, atol = atol)   # Parseval, all orders
        end
        @test isapprox(l2norm(tospec(u1)), l2norm(u1); rtol = rtol, atol = atol)
        @test isapprox(inner(tospec(u1), tospec(u1)), inner(u1, u1); rtol = rtol, atol = atol) # energy ≥ 0, = physical
        @test inner(tospec(f1), tospec(f1)) isa T                                              # real scalar, eltype preserved
      end
    end

    @testset "spectral integral & mean via the zero (DC) mode ($T)" begin
      layout = RealFourierLayout()
      rtol = T == Float64 ? 1e-10 : 1.0f-3
      atol = T == Float64 ? 1e-12 : 1.0f-5
      # even Nₓ = 8 and odd Nₓ = 7 both place the DC coefficient at index [1,1,1]; check both
      for gp in (Grid3D((8, 8, 8), (T(2π), T(4π), T(6π))), Grid3D((7, 8, 6), (T(2π), T(2π), T(2π))))
        tospec(phys) = (R = field_tensor_order(phys);
                        shape = spectral_field_shape(gp, layout, Val(R));
                        spec0 = R == 0 ? ScalarFieldSpectral(zeros(Complex{T}, shape), gp) :
                                R == 1 ? VectorFieldSpectral(zeros(Complex{T}, shape), gp) :
                                         TensorFieldSpectral{R}(zeros(Complex{T}, shape), gp);
                        to_spectral(phys, FieldTransformPlans(phys, spec0)))
        # non-zero DC components so the checks exercise real values, not two round-off zeros
        f = ScalarFieldPhysical((x, y, z) -> 2 + sin(x) + cos(2y) * sin(z), gp)
        u = VectorFieldPhysical((x, y, z) -> (T(1) + sin(x), T(2) + cos(y), sin(2z)), gp)
        A = TensorFieldPhysical{2}((x, y, z) -> [1+sin(x) cos(y) 0.3; 0.5 sin(z) cos(x); 1.0 cos(z) 2+sin(y)], gp)
        for section in (f, u, A)                        # scalar / vector / tensor, both grids
          spectral = tospec(section)
          # independent oracle: the physical reduction (summed in physical space) == the zero-mode read
          @test isapprox(integral(spectral), integral(section); rtol = rtol, atol = atol)
          @test isapprox(mean(spectral),     mean(section);     rtol = rtol, atol = atol)
        end
        # fiber-preserving, eltype-preserving (scalar → T, vector → FiberVector, tensor → FiberTensor2)
        @test integral(tospec(f)) isa T && mean(tospec(f)) isa T
        @test integral(tospec(u)) isa FiberVector{T} && mean(tospec(u)) isa FiberVector{T}
        @test integral(tospec(A)) isa FiberTensor2{T} && mean(tospec(A)) isa FiberTensor2{T}
        # analytical oracles: a constant carries all of ∫ and the mean in the DC mode
        c = T(2.5); cs = tospec(ScalarFieldPhysical((x, y, z) -> c, gp))
        @test isapprox(mean(cs), c; rtol = rtol, atol = atol)                          # ⟨c⟩ = c
        @test isapprox(integral(cs), c * prod(gp.domain_size); rtol = rtol, atol = atol) # ∫c dx = c|Ω|
        # a zero-mean fluctuation has a vanishing DC coefficient
        @test isapprox(mean(tospec(ScalarFieldPhysical((x, y, z) -> sin(x), gp))), 0; atol = atol)
        # extensive = |Ω|·intensive holds in the spectral representation too
        @test isapprox(integral(tospec(f)), prod(gp.domain_size) * mean(tospec(f)); rtol = rtol, atol = atol)
      end
    end

    @testset "radial_spectrum refines the Parseval inner ($T)" begin
      layout = RealFourierLayout()
      atol = T == Float64 ? 1e-12 : 1.0f-5
      rtol = T == Float64 ? 1e-10 : 1.0f-3
      for gp in (Grid3D((8, 8, 8), (T(2π), T(2π), T(2π))), Grid3D((7, 8, 6), (T(2π), T(2π), T(2π))))
        tospec(phys) = (R = field_tensor_order(phys);
                        shape = spectral_field_shape(gp, layout, Val(R));
                        spec0 = R == 0 ? ScalarFieldSpectral(zeros(Complex{T}, shape), gp) :
                                R == 1 ? VectorFieldSpectral(zeros(Complex{T}, shape), gp) :
                                         TensorFieldSpectral{R}(zeros(Complex{T}, shape), gp);
                        to_spectral(phys, FieldTransformPlans(phys, spec0)))
        m = FieldSpectralMultipliers(ScalarFieldSpectral(zeros(Complex{T}, spectral_field_shape(gp, layout, Val(0))), gp))
        f = ScalarFieldPhysical((x, y, z) -> sin(x) + cos(2y) * sin(z), gp)
        u = VectorFieldPhysical((x, y, z) -> (sin(x), cos(y), sin(2z)), gp)
        A = TensorFieldPhysical{2}((x, y, z) -> [sin(x) cos(y) 0.3; 0.5 sin(z) cos(x); 1.0 cos(z) sin(y)], gp)
        for section in (f, u, A)                          # scalar / vector / tensor, both grids
          spectral = tospec(section)
          shells, spectrum = radial_spectrum(spectral, m)
          @test sum(spectrum) ≈ inner(spectral, spectral)  # the exact inner refinement (Parseval)
          @test all(>=(0), spectrum)                       # |f̂|² ≥ 0 ⇒ each shell sum ≥ 0
          @test length(shells) == length(spectrum) && eltype(spectrum) === T && shells[1] == 0
        end
        # analytical oracle: a constant field c has ALL energy in the |k| = 0 shell, E(0) = c² = inner
        c = T(2.5)
        constant = tospec(ScalarFieldPhysical((x, y, z) -> c, gp))
        _, constant_spectrum = radial_spectrum(constant, m)
        @test isapprox(constant_spectrum[1], c^2; rtol = rtol, atol = atol)
        @test isapprox(constant_spectrum[1], inner(constant, constant); rtol = rtol, atol = atol)
        @test isapprox(sum(constant_spectrum[2:end]), 0; atol = atol)        # nothing above |k| = 0
        # analytical oracle: cos(x) puts ALL its energy ⟨cos²⟩ = 1/2 in the |k| = 1 shell
        cosine = tospec(ScalarFieldPhysical((x, y, z) -> cos(x), gp))
        _, cosine_spectrum = radial_spectrum(cosine, m)
        @test isapprox(cosine_spectrum[2], T(1) / 2; rtol = rtol, atol = atol)   # E(|k| = 1) = 1/2
        @test isapprox(cosine_spectrum[2], inner(cosine, cosine); rtol = rtol, atol = atol)
        @test argmax(cosine_spectrum) == 2 && isapprox(sum(cosine_spectrum[3:end]), 0; atol = atol)
      end
    end

    @testset "weighted_inner ⟨f, w·g⟩ ($T)" begin
      layout = RealFourierLayout()
      atol = T == Float64 ? 1e-11 : 1.0f-4
      rtol = T == Float64 ? 1e-9 : 1.0f-3
      for gp in (Grid3D((8, 8, 8), (T(2π), T(2π), T(2π))), Grid3D((7, 8, 6), (T(2π), T(2π), T(2π))))
        tospec(phys) = (R = field_tensor_order(phys);
                        shape = spectral_field_shape(gp, layout, Val(R));
                        spec0 = R == 0 ? ScalarFieldSpectral(zeros(Complex{T}, shape), gp) :
                                R == 1 ? VectorFieldSpectral(zeros(Complex{T}, shape), gp) :
                                         TensorFieldSpectral{R}(zeros(Complex{T}, shape), gp);
                        to_spectral(phys, FieldTransformPlans(phys, spec0)))
        zero_scalar() = ScalarFieldSpectral(zeros(Complex{T}, spectral_field_shape(gp, layout, Val(0))), gp)
        m = FieldSpectralMultipliers(zero_scalar())
        ones_w = ScalarFieldSpectral(fill(one(Complex{T}), spectral_field_shape(gp, layout, Val(0))), gp)  # w ≡ 1
        ksq  = squared_wavenumber_field(zero_scalar(), m)                       # w = |k|² (keeps true Nyquist k²)
        band = spectral_cutoff(zero_scalar(), m, T(2.5))                        # sharp 0/1 mask ⇒ w² = w

        f = tospec(ScalarFieldPhysical((x, y, z) -> sin(x) + cos(2y) * sin(z), gp))
        u = tospec(VectorFieldPhysical((x, y, z) -> (sin(x), cos(y), sin(2z)), gp))
        A = tospec(TensorFieldPhysical{2}((x, y, z) -> [sin(x) cos(y) 0.3; 0.5 sin(z) cos(x); 1.0 cos(z) sin(y)], gp))

        # w ≡ 1 reduces to the plain inner (scalar / vector / tensor)
        for spectral in (f, u, A)
          @test isapprox(weighted_inner(spectral, ones_w), inner(spectral, spectral); rtol = rtol, atol = atol)
        end
        # w = |k|² is ⟨f, −Δf⟩ exactly (both keep the true Nyquist k²) — the Dirichlet/H¹ energy
        @test isapprox(weighted_inner(f, ksq), -inner(f, laplacian(f, m)); rtol = rtol, atol = atol)
        @test isapprox(weighted_inner(u, ksq), -inner(u, laplacian(u, m)); rtol = rtol, atol = atol)
        # and it equals ⟨∇f, ∇f⟩ for these sub-Nyquist test fields (the ∇ multiplier zeroes only the empty Nyquist plane)
        @test isapprox(weighted_inner(f, ksq), inner(gradient(f, m), gradient(f, m)); rtol = rtol, atol = atol)
        @test isapprox(weighted_inner(u, ksq), inner(gradient(u, m), gradient(u, m)); rtol = rtol, atol = atol)
        # sharp band is idempotent (w² = w) ⇒ ⟨f, w·f⟩ = ‖w⋆f‖² = inner(convolve, convolve)
        for spectral in (f, u)
          conv = convolve(spectral, band)
          @test isapprox(weighted_inner(spectral, band), inner(conv, conv); rtol = rtol, atol = atol)
        end
        # mixed form is symmetric in f, g; the two-argument form is the g = f case
        g = tospec(ScalarFieldPhysical((x, y, z) -> cos(x) * sin(y) + sin(3z), gp))
        @test isapprox(weighted_inner(f, g, ksq), weighted_inner(g, f, ksq); rtol = rtol, atol = atol)
        @test weighted_inner(f, f, ksq) ≈ weighted_inner(f, ksq)
        # spectral-only: a physical field has no weighted_inner
        @test_throws MethodError weighted_inner(ScalarFieldPhysical((x, y, z) -> sin(x), gp), ones_w)
      end
    end

    @testset "radial_correlation: Wiener–Khinchin autocorrelation vs circshift ($T)" begin
      layout = RealFourierLayout()
      rtol = T == Float64 ? 1e-9 : 1.0f-2
      atol = T == Float64 ? 1e-11 : 1.0f-3
      for gp in (Grid3D((8, 8, 8), (T(2π), T(2π), T(2π))), Grid3D((7, 8, 6), (T(2π), T(2π), T(2π))))
        gs = gp.grid_size; spacing = gp.grid_spacing; bin_width = minimum(spacing)
        minimage(I) = sqrt(sum((min(i - 1, n - (i - 1)) * sp)^2 for (i, n, sp) in zip(Tuple(I), gs, spacing)))
        # independent oracle: the autocorrelation by direct circshift, binned the same way (host loop)
        function binned_circshift(phys, nshell)
          d = field_data(phys); total = prod(gs); R = field_tensor_order(phys)
          shell_sum = zeros(T, nshell); shell_count = zeros(Int, nshell)
          for I in CartesianIndices(gs)
            shift = (.-(Tuple(I) .- 1)..., ntuple(_ -> 0, R)...)
            value = T(sum(d .* circshift(d, shift)) / total)     # (1/N) Σ_x f(x)·f(x+r), fiber-contracted
            b = round(Int, minimage(I) / bin_width) + 1
            b <= nshell && (shell_sum[b] += value; shell_count[b] += 1)
          end
          return [iszero(shell_count[i]) ? zero(T) : shell_sum[i] / shell_count[i] for i in 1:nshell]
        end
        for phys in (ScalarFieldPhysical((x, y, z) -> sin(x) + cos(2y) * sin(z), gp),
                     VectorFieldPhysical((x, y, z) -> (sin(x), cos(y), sin(2z)), gp),
                     TensorFieldPhysical{2}((x, y, z) -> [sin(x) cos(y) 0.3; 0.5 sin(z) cos(x); 1.0 cos(z) sin(y)], gp),
                     # a RANDOM field — exercises all modes, checked directly in physical space (circshift)
                     ScalarFieldPhysical(randn(MersenneTwister(11), T, gs...), gp))
          R = field_tensor_order(phys)
          shape = spectral_field_shape(gp, layout, Val(R))
          spec0 = R == 0 ? ScalarFieldSpectral(zeros(Complex{T}, shape), gp) :
                  R == 1 ? VectorFieldSpectral(zeros(Complex{T}, shape), gp) :
                           TensorFieldSpectral{R}(zeros(Complex{T}, shape), gp)
          plans = FieldTransformPlans(phys, spec0)
          spectral = to_spectral(phys, plans)
          separations, correlation = radial_correlation(spectral, plans)
          @test correlation[1] ≈ inner(spectral, spectral)              # C(0) = ⟨|f|²⟩ = inner, exact
          @test isapprox(correlation, binned_circshift(phys, length(correlation)); rtol = rtol, atol = atol)
          @test separations[1] == 0 && eltype(correlation) === T && length(separations) == length(correlation)
        end
        # analytical oracle: a constant field c is perfectly correlated, C(r) = c² at every separation
        c = T(1.7)
        constant = ScalarFieldPhysical((x, y, z) -> c, gp)
        plans_c = FieldTransformPlans(constant, ScalarFieldSpectral(zeros(Complex{T}, spectral_field_shape(gp, layout, Val(0))), gp))
        _, constant_corr = radial_correlation(to_spectral(constant, plans_c), plans_c)
        @test isapprox(constant_corr[1], c^2; rtol = rtol, atol = atol)                       # C(0) = c²
        @test all(x -> isapprox(x, c^2; rtol = rtol, atol = atol) || iszero(x), constant_corr)  # c² on every populated shell
      end
    end

    @testset "radial_spectrum co-spectrum refines the mixed inner ($T)" begin
      layout = RealFourierLayout()
      atol = T == Float64 ? 1e-12 : 1.0f-5
      rtol = T == Float64 ? 1e-9 : 1.0f-3
      for gp in (Grid3D((8, 8, 8), (T(2π), T(2π), T(2π))), Grid3D((7, 8, 6), (T(2π), T(2π), T(2π))))
        tospec(phys) = (R = field_tensor_order(phys);
                        shape = spectral_field_shape(gp, layout, Val(R));
                        spec0 = R == 0 ? ScalarFieldSpectral(zeros(Complex{T}, shape), gp) :
                                R == 1 ? VectorFieldSpectral(zeros(Complex{T}, shape), gp) :
                                         TensorFieldSpectral{R}(zeros(Complex{T}, shape), gp);
                        to_spectral(phys, FieldTransformPlans(phys, spec0)))
        m = FieldSpectralMultipliers(ScalarFieldSpectral(zeros(Complex{T}, spectral_field_shape(gp, layout, Val(0))), gp))
        # distinct scalar / vector / tensor pairs so the co-spectrum is non-trivial (g ≠ f)
        pairs = ((ScalarFieldPhysical((x, y, z) -> sin(x) + cos(2y) * sin(z), gp),
                  ScalarFieldPhysical((x, y, z) -> cos(x) + sin(2y) + T(2) / 5 * cos(z), gp)),
                 (VectorFieldPhysical((x, y, z) -> (sin(x), cos(y), sin(2z)), gp),
                  VectorFieldPhysical((x, y, z) -> (cos(x), sin(y) + 3 * cos(2z) / 10, sin(z)), gp)),
                 (TensorFieldPhysical{2}((x, y, z) -> [sin(x) cos(y) 0.3; 0.5 sin(z) cos(x); 1.0 cos(z) sin(y)], gp),
                  TensorFieldPhysical{2}((x, y, z) -> [cos(x) sin(y) 0.2; 0.7 cos(z) sin(x); 0.1 sin(z) cos(y)], gp)))
        for (pf, pg) in pairs
          fh = tospec(pf); gh = tospec(pg)
          _, Efg = radial_spectrum(fh, gh, m)
          _, Egf = radial_spectrum(gh, fh, m)
          _, Eff = radial_spectrum(fh, fh, m)
          _, Eff_one = radial_spectrum(fh, m)
          @test isapprox(sum(Efg), inner(fh, gh); rtol = rtol, atol = atol)  # refines the mixed inner (Parseval)
          @test Efg == Egf                                  # symmetric: Re(f̂ conj ĝ) = Re(ĝ conj f̂), exact
          @test Eff == Eff_one                              # the g = f case IS the one-argument power spectrum
        end
        # analytical oracle (both signs): f = cos x + cos 2x, g = cos x − cos 2x.
        #   inner(f, g) = ⟨cos²x⟩ − ⟨cos²2x⟩ = 0, but the co-spectrum resolves that cancellation into
        #   E(|k| = 1) = +⟨cos²x⟩ = +1/2  and  E(|k| = 2) = −⟨cos²2x⟩ = −1/2.
        fpm = tospec(ScalarFieldPhysical((x, y, z) -> cos(x) + cos(2x), gp))
        gpm = tospec(ScalarFieldPhysical((x, y, z) -> cos(x) - cos(2x), gp))
        _, Epm = radial_spectrum(fpm, gpm, m)
        @test isapprox(Epm[2], T(1) / 2;  rtol = rtol, atol = atol)         # +1/2 in the |k| = 1 shell
        @test isapprox(Epm[3], -T(1) / 2; rtol = rtol, atol = atol)         # −1/2 in the |k| = 2 shell (negative!)
        @test isapprox(sum(Epm), inner(fpm, gpm); rtol = rtol, atol = atol) # … and the two cancel: Σ = inner = 0
        @test isapprox(sum(Epm), 0; atol = atol)
        # orthogonal pair cos(x) ⟂ sin(x): zero co-spectrum everywhere (and inner = 0)
        fo = tospec(ScalarFieldPhysical((x, y, z) -> cos(x), gp))
        go = tospec(ScalarFieldPhysical((x, y, z) -> sin(x), gp))
        _, Eo = radial_spectrum(fo, go, m)
        @test all(x -> isapprox(x, 0; atol = atol), Eo) && isapprox(inner(fo, go), 0; atol = atol)
      end
    end

    @testset "radial_correlation cross-correlation vs circshift ($T)" begin
      layout = RealFourierLayout()
      rtol = T == Float64 ? 1e-9 : 1.0f-2
      atol = T == Float64 ? 1e-11 : 1.0f-3
      for gp in (Grid3D((8, 8, 8), (T(2π), T(2π), T(2π))), Grid3D((7, 8, 6), (T(2π), T(2π), T(2π))))
        gs = gp.grid_size; spacing = gp.grid_spacing; bin_width = minimum(spacing)
        minimage(I) = sqrt(sum((min(i - 1, n - (i - 1)) * sp)^2 for (i, n, sp) in zip(Tuple(I), gs, spacing)))
        # independent oracle: the cross-correlation ⟨f(x)·g(x+r)⟩ by direct circshift, binned the same way
        function binned_circshift_cross(physf, physg, nshell)
          df = field_data(physf); dg = field_data(physg); total = prod(gs); R = field_tensor_order(physf)
          shell_sum = zeros(T, nshell); shell_count = zeros(Int, nshell)
          for I in CartesianIndices(gs)
            shift = (.-(Tuple(I) .- 1)..., ntuple(_ -> 0, R)...)
            value = T(sum(df .* circshift(dg, shift)) / total)   # (1/N) Σ_x f(x)·g(x+r), fiber-contracted
            b = round(Int, minimage(I) / bin_width) + 1
            b <= nshell && (shell_sum[b] += value; shell_count[b] += 1)
          end
          return [iszero(shell_count[i]) ? zero(T) : shell_sum[i] / shell_count[i] for i in 1:nshell]
        end
        spec0(R) = (shape = spectral_field_shape(gp, layout, Val(R));
                    R == 0 ? ScalarFieldSpectral(zeros(Complex{T}, shape), gp) :
                    R == 1 ? VectorFieldSpectral(zeros(Complex{T}, shape), gp) :
                             TensorFieldSpectral{R}(zeros(Complex{T}, shape), gp))
        # scalar / vector / tensor pairs + a RANDOM scalar pair (exercises all modes, checked in physical space)
        pairs = ((ScalarFieldPhysical((x, y, z) -> sin(x) + cos(2y) * sin(z), gp),
                  ScalarFieldPhysical((x, y, z) -> cos(x) + sin(2y) + T(2) / 5 * cos(z), gp)),
                 (VectorFieldPhysical((x, y, z) -> (sin(x), cos(y), sin(2z)), gp),
                  VectorFieldPhysical((x, y, z) -> (cos(x), sin(y) + 3 * cos(2z) / 10, sin(z)), gp)),
                 (TensorFieldPhysical{2}((x, y, z) -> [sin(x) cos(y) 0.3; 0.5 sin(z) cos(x); 1.0 cos(z) sin(y)], gp),
                  TensorFieldPhysical{2}((x, y, z) -> [cos(x) sin(y) 0.2; 0.7 cos(z) sin(x); 0.1 sin(z) cos(y)], gp)),
                 (ScalarFieldPhysical(randn(MersenneTwister(11), T, gs...), gp),
                  ScalarFieldPhysical(randn(MersenneTwister(23), T, gs...), gp)))
        for (pf, pg) in pairs
          R = field_tensor_order(pf)
          plans = FieldTransformPlans(pf, spec0(R))
          fh = to_spectral(pf, plans); gh = to_spectral(pg, plans)
          seps, Cfg = radial_correlation(fh, gh, plans)
          _, Cgf = radial_correlation(gh, fh, plans)
          _, Cff = radial_correlation(fh, fh, plans)
          _, Cff_one = radial_correlation(fh, plans)
          @test isapprox(Cfg[1], inner(fh, gh); rtol = rtol, atol = atol)                          # C_fg(0) = ⟨f·g⟩ = inner
          @test isapprox(Cfg, binned_circshift_cross(pf, pg, length(Cfg)); rtol = rtol, atol = atol) # direct physical oracle
          @test isapprox(Cfg, Cgf; rtol = rtol, atol = atol)                                       # radial binning symmetrizes
          @test Cff == Cff_one                                                                     # g = f case IS the autocorrelation
          @test seps[1] == 0 && eltype(Cfg) === T && length(seps) == length(Cfg)
        end
      end
    end
  end

  # ---- spectral: inner/l2norm (Parseval) and integral/mean (zero mode) are defined; the rest stay physical ----
  @testset "spectral fields: inner/l2norm (Parseval) and integral/mean (zero mode)" begin
    N = 8
    g = Grid3D((N, N, N), (2π, 2π, 2π))
    layout = RealFourierLayout()
    spec = ScalarFieldSpectral(zeros(ComplexF64, spectral_field_shape(g, layout, Val(0))), g)
    m = FieldSpectralMultipliers(spec)
    @test inner(spec, spec) === 0.0          # Parseval inner defined (zero field ⇒ 0), real scalar
    @test l2norm(spec) === 0.0
    @test radial_spectrum(spec, m)[2] == zeros(length(radial_spectrum(spec, m)[2]))  # spectral-only, zero field ⇒ 0
    @test mean(spec) === 0.0                  # zero-mode measure reductions defined (zero field ⇒ 0)
    @test integral(spec) === 0.0
    @test_throws MethodError lpnorm(spec, 2)  # lpnorm / std / var / maximum have no single-coefficient form
    @test_throws MethodError std(spec)
    @test_throws MethodError var(spec)
    @test_throws MethodError maximum(spec)
    # radial_spectrum is the mirror image — spectral-only, no physical-field method
    @test_throws MethodError radial_spectrum(ScalarFieldPhysical((x, y, z) -> sin(x), g), m)

    # The mapped forms apply a nonlinear map to the fiber, so they are physical-only for the same
    # reason `lpnorm`/`std` are: a coefficientwise map has no meaning on a spectral representation.
    @test_throws MethodError mean(abs2, spec)
    @test_throws MethodError integral(abs2, spec)
    @test_throws MethodError maximum(abs2, spec)
    @test_throws MethodError minimum(abs2, spec)
    @test_throws MethodError extrema(abs2, spec)
  end
end


@testset "permuted rfft layout: the fold follows fft_dims ($T)" for T in (Float64, Float32)
  atol = T === Float64 ? 1e-11 : 1e-3
  # mixed parity: the (2,1,3) fold is odd (N=7, no Nyquist plane), the (3,2,1) fold even (N=6)
  grid = Grid3D((8, 7, 6), (T(2π), T(2π), T(2π)))
  for dims in ((2, 1, 3), (3, 2, 1))
    layout = RealFourierLayout(dims)
    phys = VectorFieldPhysical(rand(T, 8, 7, 6, 3), grid, layout)
    phys2 = VectorFieldPhysical(rand(T, 8, 7, 6, 3), grid, layout)
    scaffold = VectorFieldSpectral(zeros(Complex{T}, spectral_field_shape(grid, layout, Val(1))), grid, layout)
    plans = FieldTransformPlans(phys, scaffold)
    sp = to_spectral(phys, plans)
    sp2 = to_spectral(phys2, plans)
    m = FieldSpectralMultipliers(sp)
    # Parseval under the permuted fold: the doubled and self-conjugate planes sit on axis dims[1],
    # not on axis 1 — pre-generalization these all read the wrong planes and fail.
    @test inner(sp, sp) ≈ inner(phys, phys) atol = atol
    @test inner(sp, sp2) ≈ inner(phys, phys2) atol = atol
    shells, spectrum = radial_spectrum(sp, m)
    @test sum(spectrum) ≈ inner(sp, sp) atol = atol
    ones_w = ScalarFieldSpectral(fill(one(Complex{T}), spectral_field_shape(grid, layout, Val(0))), grid, layout)
    @test weighted_inner(sp, ones_w) ≈ inner(sp, sp) atol = atol
    separations, correlation = radial_correlation(sp, plans)  # end-to-end under the permuted fold
    @test correlation[1] ≈ inner(sp, sp) atol = atol          # C(0) = ⟨|f|²⟩
  end
end


@testset "anisotropic box: the radial family, shell width Δk = 2π/max L ($T)" for T in (Float64, Float32)
  # Unequal domain lengths give unequal per-axis fundamentals (1, 1/2, 1/3): the shell width, the
  # per-mode |k|, and each single-mode wavenumber are three genuinely different scales here, so a
  # dropped 2π/L factor or a wrong shell width cannot cancel out of these oracles.
  atol = T === Float64 ? 1e-11 : 1e-3
  grid_a = Grid3D((8, 8, 8), (T(2π), T(4π), T(6π)))
  layout_a = RealFourierLayout()
  phys = VectorFieldPhysical(rand(T, 8, 8, 8, 3), grid_a)
  phys2 = VectorFieldPhysical(rand(T, 8, 8, 8, 3), grid_a)
  scaffold = VectorFieldSpectral(zeros(Complex{T}, spectral_field_shape(grid_a, layout_a, Val(1))),
                                 grid_a)
  plans = FieldTransformPlans(phys, scaffold)
  sp = to_spectral(phys, plans)
  sp2 = to_spectral(phys2, plans)
  m = FieldSpectralMultipliers(sp)

  shells, spectrum = radial_spectrum(sp, m)
  @test sum(spectrum) ≈ inner(sp, sp) atol = atol               # Parseval closure, full Nyquist content
  @test shells[2] - shells[1] ≈ T(2π) / T(6π) atol = atol       # Δk = the coarsest fundamental 2π/max L
  _, cospectrum = radial_spectrum(sp, sp2, m)
  @test sum(cospectrum) ≈ inner(sp, sp2) atol = atol

  # single-mode placement oracles: cos(x) has |k| = 1 ⇒ shell round(1/Δk) = 3 (bin 4);
  # cos(y·2π/L₂) has |k| = 1/2 ⇒ shell round((1/2)/(1/3)) = 2 (bin 3) — mode, fundamental, and
  # shell width all differ, so the placement pins the anisotropic Δk arithmetic exactly
  sscaffold = ScalarFieldSpectral(zeros(Complex{T}, spectral_field_shape(grid_a, layout_a, Val(0))),
                                  grid_a)
  cos_x = ScalarFieldPhysical([cos((i - 1) * T(2π) / 8) for i in 1:8, j in 1:8, l in 1:8], grid_a)
  cos_y = ScalarFieldPhysical([cos(T(1) / 2 * (j - 1) * T(4π) / 8) for i in 1:8, j in 1:8, l in 1:8],
                              grid_a)
  splans = FieldTransformPlans(cos_x, sscaffold)
  _, spec_x = radial_spectrum(to_spectral(cos_x, splans), m)
  @test isapprox(spec_x[4], T(1) / 2; atol = atol) && argmax(spec_x) == 4
  _, spec_y = radial_spectrum(to_spectral(cos_y, splans), m)
  @test isapprox(spec_y[3], T(1) / 2; atol = atol) && argmax(spec_y) == 3

  separations, correlation = radial_correlation(sp, plans)
  @test correlation[1] ≈ inner(sp, sp) atol = atol              # C(0) = ⟨|f|²⟩ at unequal spacings
  @test separations[2] - separations[1] ≈ minimum(grid_a.grid_spacing) atol = atol
  _, cocorrelation = radial_correlation(sp, sp2, plans)
  @test cocorrelation[1] ≈ inner(sp, sp2) atol = atol
end


@testset "empty base (M = 0): deliberate semantics, no out-of-bounds ($T)" for T in (Float64, Float32)
  # The CPU fixed tree seeded its accumulator from element(1) BEFORE checking emptiness — an
  # @inbounds out-of-bounds read on an empty section, which fabricated maximum(q) = 0 instead
  # of erroring (decision 43). Each guard mirrors the op's stdlib counterpart: order statistics
  # throw (the Base empty-collection contract), the mean family is NaN (Statistics), and the
  # raw sum is zero, so `integral` over no points is exactly zero.
  q = ScalarPointValues(zeros(T, 0))
  @test_throws ArgumentError maximum(q)
  @test_throws ArgumentError minimum(q)
  @test_throws ArgumentError extrema(q)
  @test isnan(mean(q))
  @test isnan(var(q))
  @test isnan(std(q))
  @test isnan(l2norm(q))
  @test isnan(inner(q, q))
  @test integral(q) == 0
  vq = VectorPointValues(zeros(T, 0, 3))
  @test all(isnan, mean(vq))                                # fiber-preserving mean: a NaN fiber
  @test integral(vq) == zero(FiberVector{T})
  @test_throws ArgumentError maximum(norm, vq)              # the mapped path delegates to Base
end
