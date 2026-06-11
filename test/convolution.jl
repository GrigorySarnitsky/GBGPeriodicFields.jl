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
  A = TensorFieldPhysical{2}((x, y, z) -> [sin(x) cos(y) 0.3; 0.5 sin(z) cos(x); 1.0 cos(z) sin(y)], grid)
  A_s = to_spectral(A, plans_for(A))

  @testset "T = $T" begin

    @testset "identity kernel ĝ ≡ 1 ⇒ f (scalar kernel over any tensor order)" begin
      ones_kernel = scalar_kernel(ones(Complex{T}, shape0))
      @test approx(field_data(convolve(phi_s, ones_kernel)), field_data(phi_s))
      @test approx(field_data(convolve(u_s, ones_kernel)), field_data(u_s))   # broadcast over a 1-index fiber
      @test approx(field_data(convolve(A_s, ones_kernel)), field_data(A_s))   # over a 2-index fiber (R=2, 5-D broadcast)
      @test field_tensor_order(convolve(u_s, ones_kernel)) == 1               # representation/order preserved
      @test field_tensor_order(convolve(A_s, ones_kernel)) == 2
    end

    @testset "constant kernel ĝ ≡ c ⇒ scaling by c" begin
      c = T(3)
      const_kernel = scalar_kernel(fill(Complex{T}(c), shape0))
      @test approx(field_data(convolve(phi_s, const_kernel)), c .* field_data(phi_s))
      @test approx(field_data(convolve(u_s, const_kernel)), c .* field_data(u_s))
      @test approx(field_data(convolve(A_s, const_kernel)), c .* field_data(A_s))
    end

    @testset "translation kernel exp(-i kₐ m Δ) ⇔ circshift along each axis (independent oracle)" begin
      mult = FieldSpectralMultipliers(phi_s)
      shift = 2
      wn = (Array(mult.wavenumber_1), Array(mult.wavenumber_2), Array(mult.wavenumber_3))
      for axis in 1:3
        k = wn[axis]; dx = grid.grid_spacing[axis]
        kdata = Complex{T}[exp(-im * (axis == 1 ? k[i] : axis == 2 ? k[j] : k[l]) * shift * dx)
                           for i in 1:shape0[1], j in 1:shape0[2], l in 1:shape0[3]]
        kern = scalar_kernel(kdata)
        sh = ntuple(d -> d == axis ? shift : 0, 3)
        @test approx(field_data(to_physical(convolve(phi_s, kern), plans_for(phi))),   # scalar field
                     circshift(field_data(phi), sh))
        @test approx(field_data(to_physical(convolve(u_s, kern), plans_for(u))),       # vector field, each component
                     circshift(field_data(u), (sh..., 0)))
      end
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
      masked_A = convolve(A_s, cutoff)                                      # scalar mask over a tensor field (R=2)
      for i in 1:3, j in 1:3
        @test approx(field_data(masked_A)[:, :, :, i, j], field_data(A_s)[:, :, :, i, j] .* vals)
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

      # the R=2 in-place α/β path (scalar kernel broadcasts over the 2-index fiber)
      Adest0 = randn(Complex{T}, F.spectral_field_shape(grid, layout, Val(2)))
      Adest = TensorFieldSpectral{2}(copy(Adest0), grid)
      convolve!(Adest, A_s, g, alpha, beta)
      @test approx(field_data(Adest), alpha .* (field_data(g) .* field_data(A_s)) .+ beta .* Adest0)
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

  @testset "mixed-parity grid (8, 7, 6): odd axis (no Nyquist) + even axes, all 3 directions" begin
    T = Float64
    grid = Grid3D((8, 7, 6), (T(2π), T(2π), T(2π)))        # x even, y odd, z even — exercises rfft on an odd axis
    layout = RealFourierLayout()
    shape0 = F.spectral_field_shape(grid, layout, Val(0))
    plans = FieldTransformPlans(ScalarFieldPhysical(zeros(T, 8, 7, 6), grid),
                                ScalarFieldSpectral(zeros(Complex{T}, shape0), grid))
    phi = ScalarFieldPhysical((x, y, z) -> sin(x) + cos(2y) + sin(z), grid)
    phi_s = to_spectral(phi, plans)
    @test isapprox(field_data(convolve(phi_s, ScalarFieldSpectral(ones(Complex{T}, shape0), grid))),
                   field_data(phi_s); rtol = 1e-10)         # identity holds on the mixed-parity grid
    mult = FieldSpectralMultipliers(phi_s)
    wn = (Array(mult.wavenumber_1), Array(mult.wavenumber_2), Array(mult.wavenumber_3))
    for axis in 1:3
      k = wn[axis]; dx = grid.grid_spacing[axis]; shift = 1
      kdata = Complex{T}[exp(-im * (axis == 1 ? k[i] : axis == 2 ? k[j] : k[l]) * shift * dx)
                         for i in 1:shape0[1], j in 1:shape0[2], l in 1:shape0[3]]
      shifted = to_physical(convolve(phi_s, ScalarFieldSpectral(kdata, grid)), plans)
      sh = ntuple(d -> d == axis ? shift : 0, 3)
      @test isapprox(field_data(shifted), circshift(field_data(phi), sh); rtol = 1e-10)
    end
  end
end
