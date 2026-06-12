# Behaviour tests for the L²/measure reductions (Reductions module): integral / mean / std / var /
# inner / l2norm / lpnorm / maximum, on physical fields and point-values, against analytic or manual
# references (independent of the reduction implementation). Both element types and both bases; the
# physical-only restriction is asserted as an intentional absence.

using Test
using GBGPeriodicFields
using GBGPeriodicFields: field_data
using Statistics: mean, std, var      # extended on sections in the Reductions module (not re-exported)

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

    @testset "shell_spectrum refines the Parseval inner ($T)" begin
      layout = RealFourierLayout()
      atol = T == Float64 ? 1e-12 : 1.0f-5
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
          shells, spectrum = shell_spectrum(spectral, m)
          @test sum(spectrum) ≈ inner(spectral, spectral)  # the exact inner refinement (Parseval)
          @test all(>=(0), spectrum)                       # |f̂|² ≥ 0 ⇒ each shell sum ≥ 0
          @test length(shells) == length(spectrum) && eltype(spectrum) === T && shells[1] == 0
        end
        # a single Fourier mode lands in exactly one shell: cos(x) puts ALL energy in |k| = 1
        single = tospec(VectorFieldPhysical((x, y, z) -> (cos(x), 0.0, 0.0), gp))
        _, single_spectrum = shell_spectrum(single, m)
        @test argmax(single_spectrum) == 2                 # shell |k| = 1 (the second, after |k| = 0)
        @test isapprox(sum(single_spectrum[3:end]), 0; atol = atol)   # nothing in |k| ≥ 2
      end
    end
  end

  # ---- spectral: the Parseval inner/l2norm are defined; the measure reductions stay physical-only ----
  @testset "spectral fields: Parseval inner/l2norm only" begin
    N = 8
    g = Grid3D((N, N, N), (2π, 2π, 2π))
    layout = RealFourierLayout()
    spec = ScalarFieldSpectral(zeros(ComplexF64, spectral_field_shape(g, layout, Val(0))), g)
    m = FieldSpectralMultipliers(spec)
    @test inner(spec, spec) === 0.0          # Parseval inner defined (zero field ⇒ 0), real scalar
    @test l2norm(spec) === 0.0
    @test shell_spectrum(spec, m)[2] == zeros(length(shell_spectrum(spec, m)[2]))  # spectral-only, zero field ⇒ 0
    @test_throws MethodError mean(spec)       # the measure reductions remain physical-only
    @test_throws MethodError integral(spec)
    @test_throws MethodError lpnorm(spec, 2)
    @test_throws MethodError maximum(spec)
    # shell_spectrum is the mirror image — spectral-only, no physical-field method
    @test_throws MethodError shell_spectrum(ScalarFieldPhysical((x, y, z) -> sin(x), g), m)
  end
end
