# Tests for src/Convolution.jl: periodic convolution as the coefficientwise spectral product
# f̂·ĝ, with the kernel ĝ a ScalarFieldSpectral. Verified against independent oracles —
#   * identity kernel ĝ≡1 ⇒ f, constant kernel ĝ≡c ⇒ scaling,
#   * the translation kernel exp(-i kₓ m Δx) ⇔ circshift by m cells (the strong physical oracle),
#   * sharp-cutoff idempotence (a 0/1 low-pass projection), and kernel-composition associativity,
# plus the α/β accumulate form, in-place aliasing safety, both element types, and the physical-space
# intentional absence.

using Test
using GBGPeriodicFields

const F = GBGPeriodicFields.Fields
const ELEMENT_TYPES = (Float64, Float32)


function run_convolution_tests(::Type{T}) where {T<:AbstractFloat}
  gs = (8, 8, 8)
  grid = Grid3D(gs, (T(2π), T(2π), T(2π)))
  layout = RealFourierLayout()
  shape0 = F.spectral_field_shape(grid, layout, Val(0))
  reltol = T === Float32 ? 1.0f-4 : 1e-10
  abstol = T === Float32 ? 1.0f-5 : 1e-12
  approx(a, b) = isapprox(a, b; rtol = reltol, atol = abstol)

  function plans_for(physical)
    R = field_tensor_order(physical)
    shape = F.spectral_field_shape(grid, layout, Val(R))
    spectral = R == 0 ? ScalarFieldSpectral(zeros(Complex{T}, shape), grid) :
               R == 1 ? VectorFieldSpectral(zeros(Complex{T}, shape), grid) :
                        TensorFieldSpectral{R}(zeros(Complex{T}, shape), grid)
    return FieldTransformPlans(physical, spectral)
  end

  scalar_kernel(data) = ScalarFieldSpectral(data, grid)

  # a resolved real scalar field and a resolved real vector field, in spectral representation
  phi = ScalarFieldPhysical((x, y, z) -> sin(x) + cos(2y) * sin(z), grid)
  phi_s = to_spectral(phi, plans_for(phi))
  u = VectorFieldPhysical((x, y, z) -> (sin(x), sin(2y), cos(z)), grid)
  u_s = to_spectral(u, plans_for(u))

  @testset "T = $T" begin

    @testset "identity kernel ĝ ≡ 1 ⇒ f (scalar kernel over any tensor order)" begin
      ones_kernel = scalar_kernel(ones(Complex{T}, shape0))
      @test approx(field_data(convolve(phi_s, ones_kernel)), field_data(phi_s))
      @test approx(field_data(convolve(u_s, ones_kernel)), field_data(u_s))   # broadcast over the fiber
      @test field_tensor_order(convolve(u_s, ones_kernel)) == 1               # representation/order preserved
    end

    @testset "constant kernel ĝ ≡ c ⇒ scaling by c" begin
      c = T(3)
      const_kernel = scalar_kernel(fill(Complex{T}(c), shape0))
      @test approx(field_data(convolve(phi_s, const_kernel)), c .* field_data(phi_s))
      @test approx(field_data(convolve(u_s, const_kernel)), c .* field_data(u_s))
    end

    @testset "translation kernel exp(-i kₓ m Δx) ⇔ circshift (independent physical oracle)" begin
      m = FieldSpectralMultipliers(phi_s)
      shift = 2
      dx = grid.grid_spacing[1]
      k1 = Array(m.wavenumber_1)
      kdata = Complex{T}[exp(-im * k1[i] * shift * dx)
                         for i in 1:shape0[1], j in 1:shape0[2], l in 1:shape0[3]]
      shifted = to_physical(convolve(phi_s, scalar_kernel(kdata)), plans_for(phi))
      @test approx(field_data(shifted), circshift(field_data(phi), (shift, 0, 0)))
    end

    @testset "spectral_cutoff: a sharp 0/1 low-pass projection" begin
      m = FieldSpectralMultipliers(phi_s)
      cutoff = spectral_cutoff(phi_s, m, T(2.5))
      vals = field_data(cutoff)
      @test cutoff isa ScalarFieldSpectral
      @test all(v -> v == zero(Complex{T}) || v == one(Complex{T}), vals)   # a sharp 0/1 mask
      @test vals[1, 1, 1] == one(Complex{T})                                # |k| = 0 kept
      @test any(iszero, vals)                                               # high modes dropped
      @test approx(field_data(convolve(cutoff, cutoff)), vals)              # idempotent: ĝ² = ĝ
      once = convolve(phi_s, cutoff)
      @test approx(field_data(convolve(once, cutoff)), field_data(once))    # convolving twice = once
      masked_u = convolve(u_s, cutoff)                                      # scalar mask over a vector field
      for i in 1:3
        @test approx(field_data(masked_u)[:, :, :, i], field_data(u_s)[:, :, :, i] .* vals)
      end
    end

    @testset "kernel composition: convolve(g₁, g₂) composes, and is associative" begin
      m = FieldSpectralMultipliers(phi_s)
      g1 = spectral_cutoff(phi_s, m, T(3))
      dx = grid.grid_spacing[1]
      k1 = Array(m.wavenumber_1)
      g2 = scalar_kernel(Complex{T}[exp(-im * k1[i] * dx)
                                    for i in 1:shape0[1], j in 1:shape0[2], l in 1:shape0[3]])
      left = convolve(convolve(phi_s, g1), g2)
      right = convolve(phi_s, convolve(g1, g2))     # convolve(g1, g2) is the composed kernel
      @test approx(field_data(left), field_data(right))
    end

    @testset "α/β accumulate form: dest = α·(f⋆g) + β·dest" begin
      g = scalar_kernel(fill(Complex{T}(2), shape0))
      dest0 = randn(Complex{T}, shape0)
      dest = scalar_kernel(copy(dest0))
      alpha, beta = T(0.5), T(-1.5)
      returned = convolve!(dest, phi_s, g, alpha, beta)
      @test returned === dest
      @test approx(field_data(dest), alpha .* (field_data(g) .* field_data(phi_s)) .+ beta .* dest0)
    end

    @testset "in-place is aliasing-safe (destination === field)" begin
      m = FieldSpectralMultipliers(phi_s)
      g = spectral_cutoff(phi_s, m, T(3))
      reference = convolve(phi_s, g)
      aliased = scalar_kernel(copy(field_data(phi_s)))
      convolve!(aliased, aliased, g)
      @test approx(field_data(aliased), field_data(reference))
    end

  end
end


@testset "Convolution.jl" begin
  for T in ELEMENT_TYPES
    run_convolution_tests(T)
  end

  @testset "physical-space convolve is intentionally absent" begin
    grid = Grid3D((8, 8, 8), (2π, 2π, 2π))
    layout = RealFourierLayout()
    shape0 = F.spectral_field_shape(grid, layout, Val(0))
    phi = ScalarFieldPhysical((x, y, z) -> sin(x), grid)
    phi_s = to_spectral(phi, FieldTransformPlans(phi, ScalarFieldSpectral(zeros(ComplexF64, shape0), grid)))
    ones_kernel = ScalarFieldSpectral(ones(ComplexF64, shape0), grid)
    @test_throws MethodError convolve(phi, ones_kernel)    # no physical-space convolution (spectral only)
    @test_throws MethodError convolve(phi_s, phi)          # the kernel must be in spectral representation
  end
end
