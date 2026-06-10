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
  end

  # ---- intentional absence: reductions are physical-space only ----
  @testset "spectral fields have no reductions (physical-only)" begin
    N = 8
    g = Grid3D((N, N, N), (2π, 2π, 2π))
    layout = RealFourierLayout()
    spec = ScalarFieldSpectral(zeros(ComplexF64, spectral_field_shape(g, layout, Val(0))), g)
    @test_throws MethodError mean(spec)
    @test_throws MethodError integral(spec)
    @test_throws MethodError inner(spec, spec)
    @test_throws MethodError l2norm(spec)
  end
end
