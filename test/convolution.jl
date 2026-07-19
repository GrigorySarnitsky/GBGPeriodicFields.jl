# Tests for src/Convolution.jl: periodic convolution as the coefficientwise spectral product
# f̂·ĝ, with the kernel ĝ a ScalarFieldSpectral. Verified against independent oracles —
#   * identity kernel ĝ≡1 ⇒ f, constant kernel ĝ≡c ⇒ scaling,
#   * the translation kernel exp(-i kₓ m Δx) ⇔ circshift by m cells (the strong physical oracle),
#   * sharp-cutoff idempotence (a 0/1 low-pass projection), and kernel-composition associativity,
# plus the α/β accumulate form, in-place aliasing safety, both element types, and the physical-space
# intentional absence.
#
# translation_kernel gets the same circshift oracle on a *random* field — one that carries Nyquist
# content, unlike the band-limited fields above — plus an analytic shifted-cosine, the exact DirectDFT
# evaluation at the displaced nodes (a sub-cell displacement), and the reality check that pins the
# Nyquist convention: a kernel built from the true Nyquist phase leaves a half-spectrum that is no
# real field's, and one built from the Nyquist-zeroed derivative wavenumbers misses the sign flip of
# an odd whole-cell shift.

using Test
using Random
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
      @test field_data(phi_s ⋆ ones_kernel) == field_data(convolve(phi_s, ones_kernel))   # the exported infix ⋆ alias
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

    @testset "translation_kernel: f ↦ f(x − Δ), the shift theorem's phase" begin
      mult = FieldSpectralMultipliers(phi_s)
      dx = grid.grid_spacing

      # a zero displacement is the identity kernel
      @test approx(field_data(translation_kernel(phi_s, mult, (T(0), T(0), T(0)))), ones(Complex{T}, shape0))

      # analytic oracle: translating cos(2x + 0.3)·sin(y) by Δ gives cos(2(x − Δ₁) + 0.3)·sin(y − Δ₂)
      offset = (T(0.37), T(-0.21), T(0.11))
      g = ScalarFieldPhysical((x, y, z) -> cos(2x + T(0.3)) * sin(y), grid)
      g_s = to_spectral(g, plans_for(g))
      moved = to_physical(convolve(g_s, translation_kernel(g_s, mult, offset)), plans_for(g))
      analytic = ScalarFieldPhysical((x, y, z) -> cos(2 * (x - offset[1]) + T(0.3)) * sin(y - offset[2]), grid)
      @test approx(field_data(moved), field_data(analytic))

      # a whole-cell displacement is exactly circshift. The field is random, so every mode carries
      # content — the Nyquist mode included, where the kernel's real factor cos(π m) = (−1)^m must
      # flip the sign on an odd shift (a kernel built from the derivative wavenumbers would not).
      Random.seed!(20260713)
      noise = ScalarFieldPhysical(randn(T, gs...), grid)
      noise_s = to_spectral(noise, plans_for(noise))
      for axis in 1:3, cells in (1, 2)                       # an odd and an even whole-cell shift
        displacement = ntuple(d -> d == axis ? cells * dx[d] : zero(T), 3)
        shifted = to_physical(convolve(noise_s, translation_kernel(noise_s, mult, displacement)), plans_for(noise))
        @test approx(field_data(shifted), circshift(field_data(noise), ntuple(d -> d == axis ? cells : 0, 3)))
      end

      # one scalar kernel translates a whole vector or tensor field (it broadcasts over the fiber)
      one_cell = ntuple(d -> dx[d], 3)
      cell_kernel = translation_kernel(phi_s, mult, one_cell)
      @test approx(field_data(to_physical(convolve(u_s, cell_kernel), plans_for(u))),
                   circshift(field_data(u), (1, 1, 1, 0)))
      @test approx(field_data(to_physical(convolve(A_s, cell_kernel), plans_for(A))),
                   circshift(field_data(A), (1, 1, 1, 0, 0)))

      # the displaced field is still a *real* field: its half-spectrum stays Hermitian, so transforming
      # out and back changes nothing (to_spectral ∘ to_physical is exactly the Hermitian projector).
      # This is the check the true-Nyquist-phase kernel fails.
      half_cell = ntuple(d -> dx[d] / 2, 3)
      half_shifted = convolve(noise_s, translation_kernel(noise_s, mult, half_cell))
      @test approx(field_data(to_spectral(to_physical(half_shifted, plans_for(noise)), plans_for(noise))),
                   field_data(half_shifted))

      # at Nyquist the mode is attenuated, not moved: cos(4x) is the Nyquist mode of an 8-point 2π
      # axis, so a half-cell displacement annihilates it and a whole-cell one flips its sign
      nyquist = ScalarFieldPhysical((x, y, z) -> cos(4x), grid)
      nyquist_s = to_spectral(nyquist, plans_for(nyquist))
      annihilated = to_physical(convolve(nyquist_s, translation_kernel(nyquist_s, mult, (dx[1] / 2, T(0), T(0)))),
                                plans_for(nyquist))
      @test all(v -> abs(v) <= abstol, field_data(annihilated))
      flipped = to_physical(convolve(nyquist_s, translation_kernel(nyquist_s, mult, (dx[1], T(0), T(0)))),
                            plans_for(nyquist))
      @test approx(field_data(flipped), .-field_data(nyquist))

      # a pure phase of unit modulus on every resolved mode — the attenuation is confined to the
      # Nyquist frequencies, which are the modes whose derivative wavenumber is zeroed but whose
      # squared wavenumber is not
      kernel_values = field_data(translation_kernel(phi_s, mult, (T(0.3), T(0.4), T(-0.2))))
      derivative = (Array(mult.wavenumber_1), Array(mult.wavenumber_2), Array(mult.wavenumber_3))
      squared = (Array(mult.squared_wavenumber_1), Array(mult.squared_wavenumber_2), Array(mult.squared_wavenumber_3))
      at_nyquist(axis, index) = iszero(derivative[axis][index]) && !iszero(squared[axis][index])
      @test all(abs(kernel_values[i, j, l]) ≈ one(T)
                for i in 1:shape0[1], j in 1:shape0[2], l in 1:shape0[3]
                if !(at_nyquist(1, i) || at_nyquist(2, j) || at_nyquist(3, l)))

      # translations compose and invert on the resolved band (phi carries no Nyquist content)
      forth = translation_kernel(phi_s, mult, offset)
      back = translation_kernel(phi_s, mult, .-offset)
      @test approx(field_data(convolve(convolve(phi_s, forth), back)), field_data(phi_s))
      @test approx(field_data(convolve(phi_s, convolve(forth, forth))),                 # kernel(Δ)·kernel(Δ)
                   field_data(convolve(phi_s, translation_kernel(phi_s, mult, 2 .* offset))))   # = kernel(2Δ)
    end

    @testset "translation_kernel == the exact DirectDFT evaluation at the displaced nodes" begin
      # The independent oracle for a sub-cell displacement: the package's exact spectral interpolator,
      # asked for the band-limited field at the displaced grid nodes xₙ − Δ. Exact agreement (phi has
      # no Nyquist content, the one frequency where the two conventions part).
      mult = FieldSpectralMultipliers(phi_s)
      offset = (T(0.41), T(0.13), T(-0.29))
      moved = to_physical(convolve(phi_s, translation_kernel(phi_s, mult, offset)), plans_for(phi))
      coordinates = zeros(T, prod(gs), 3)
      index = 0
      for l in 1:gs[3], j in 1:gs[2], i in 1:gs[1]          # column-major, matching vec(field_data)
        index += 1
        for (axis, cell) in enumerate((i, j, l))
          coordinates[index, axis] = grid.origin[axis] + (cell - 1) * grid.grid_spacing[axis] - offset[axis]
        end
      end
      exact = interpolate(phi_s, PointSet(coordinates), DirectDFT())
      @test approx(vec(field_data(moved)), field_data(exact))
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

    @testset "spectral_band: annular band-pass generalizing spectral_cutoff" begin
      m = FieldSpectralMultipliers(phi_s)
      band = spectral_band(phi_s, m, T(1.5), T(3.0))
      vals = field_data(band)
      @test band isa ScalarFieldSpectral
      @test all(v -> v == zero(Complex{T}) || v == one(Complex{T}), vals)    # a sharp 0/1 shell mask
      @test vals[1, 1, 1] == zero(Complex{T})                               # |k| = 0 excluded (low edge > 0)
      @test approx(field_data(convolve(band, band)), vals)                  # idempotent projection
      # the low-pass special case: spectral_cutoff(k) === spectral_band(0, k)
      @test field_data(spectral_cutoff(phi_s, m, T(2.5))) == field_data(spectral_band(phi_s, m, T(0), T(2.5)))
      # membership oracle: ĝ = 1 exactly on the closed shell 1.5 ≤ |k| ≤ 3.0
      k_squared = real.(field_data(squared_wavenumber_field(phi_s, m)))
      expected = map(k2 -> (T(1.5)^2 <= k2 <= T(3.0)^2) ? one(Complex{T}) : zero(Complex{T}), k_squared)
      @test vals == expected
    end

    @testset "squared_wavenumber_field: |k|² as a real-valued ScalarFieldSpectral" begin
      m = FieldSpectralMultipliers(phi_s)
      k2 = squared_wavenumber_field(phi_s, m)
      @test k2 isa ScalarFieldSpectral
      reference = reshape(Array(m.squared_wavenumber_1), :, 1, 1) .+
                  reshape(Array(m.squared_wavenumber_2), 1, :, 1) .+
                  reshape(Array(m.squared_wavenumber_3), 1, 1, :)
      @test real.(field_data(k2)) ≈ reference
      @test all(iszero, imag.(field_data(k2)))                              # real, stored in the complex array
      @test field_data(k2)[1, 1, 1] == zero(Complex{T})                     # |k| = 0 at the origin mode
      # consumer use: build a viscous integrating factor exp(−ν|k|²Δt) and apply it with convolve
      factor = scalar_kernel(exp.(-T(0.1) .* field_data(k2) .* T(0.05)))
      @test all(v -> abs(v) <= 1 + abstol, field_data(factor))              # a decay (|symbol| ≤ 1), real
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

    @testset "exponential_convolve: the lazy exp(c|k|² + s·ŵ) kernel (decision 33)" begin
      m = FieldSpectralMultipliers(phi_s)
      coefficient = T(-0.037)

      # oracle 1: the same kernel built as a stored field and applied with convolve
      k2 = squared_wavenumber_field(phi_s, m)
      stored = scalar_kernel(exp.(coefficient .* field_data(k2)))
      @test field_data(exponential_convolve(phi_s, m, coefficient)) == field_data(convolve(phi_s, stored))
      u_s = to_spectral(VectorFieldPhysical((x, y, z) -> (sin(x), cos(y), sin(2z)), grid),
                        plans_for(VectorFieldPhysical((x, y, z) -> (T(0), T(0), T(0)), grid)))
      @test field_data(exponential_convolve(u_s, m, coefficient)) == field_data(convolve(u_s, stored))

      # oracle 2 (independent): a single mode is an eigenvector — exp(c·1)·cos(x) for cos(x)
      cosx = ScalarFieldPhysical((x, y, z) -> cos(x), grid)
      cosx_s = to_spectral(cosx, plans_for(cosx))
      smoothed = to_physical(exponential_convolve(cosx_s, m, coefficient), plans_for(cosx))
      @test approx(field_data(smoothed), exp(coefficient) .* field_data(cosx))

      # α/β accumulate against a hand-built reference
      dest0 = randn(Complex{T}, shape0)
      dest = scalar_kernel(copy(dest0))
      exponential_convolve!(dest, phi_s, m, coefficient, T(0.5), T(-1.5))
      @test approx(field_data(dest),
                   T(0.5) .* (exp.(coefficient .* field_data(k2)) .* field_data(phi_s)) .+ T(-1.5) .* dest0)

      # the per-mode offset enters as scale × field: exp(c|k|² + s·ŵ) with ŵ = |k|²
      offset_scale = T(0.011)
      stored_off = scalar_kernel(exp.(coefficient .* field_data(k2) .+ offset_scale .* field_data(k2)))
      @test field_data(exponential_convolve(phi_s, m, coefficient, offset_scale, k2)) ==
            field_data(convolve(phi_s, stored_off))

      # the two-operand forms == combine! then exponential_convolve!, in one pass
      b_s = scalar_kernel(randn(Complex{T}, shape0))
      sequential = scalar_kernel(zeros(Complex{T}, shape0))
      combine!(sequential, T(0.3), phi_s, T(0.7), b_s)
      exponential_convolve!(sequential, sequential, m, coefficient)
      fused = scalar_kernel(zeros(Complex{T}, shape0))
      exponential_convolve!(fused, T(0.3), phi_s, T(0.7), b_s, m, coefficient)
      @test field_data(fused) == field_data(sequential)
      combine!(sequential, T(0.3), phi_s, T(0.7), b_s)
      exponential_convolve!(sequential, sequential, m, coefficient, offset_scale, k2)
      exponential_convolve!(fused, T(0.3), phi_s, T(0.7), b_s, m, coefficient, offset_scale, k2)
      @test field_data(fused) == field_data(sequential)

      # aliasing: b === destination is the filtered accumulate in place
      inplace = scalar_kernel(copy(field_data(b_s)))
      exponential_convolve!(inplace, T(0.3), phi_s, T(0.7), inplace, m, coefficient)
      @test field_data(inplace) == field_data(exponential_convolve(
        scalar_kernel(T(0.3) .* field_data(phi_s) .+ T(0.7) .* field_data(b_s)), m, coefficient))
    end

    @testset "kernel-composed combine!: ĝ ⊙ (α·a + β·b) in one pass (decision 33)" begin
      m = FieldSpectralMultipliers(phi_s)
      g = spectral_cutoff(phi_s, m, T(3))
      b_s = scalar_kernel(randn(Complex{T}, shape0))

      sequential = scalar_kernel(zeros(Complex{T}, shape0))
      combine!(sequential, T(0.3), phi_s, T(0.7), b_s)
      convolve!(sequential, sequential, g)
      fused = scalar_kernel(zeros(Complex{T}, shape0))
      returned = combine!(fused, T(0.3), phi_s, T(0.7), b_s, g)
      @test returned === fused
      @test field_data(fused) == field_data(sequential)

      # the scalar kernel broadcasts over the fiber: the R=1 path
      u_s = to_spectral(VectorFieldPhysical((x, y, z) -> (sin(x), cos(y), sin(2z)), grid),
                        plans_for(VectorFieldPhysical((x, y, z) -> (T(0), T(0), T(0)), grid)))
      v_s = VectorFieldSpectral(randn(Complex{T}, F.spectral_field_shape(grid, layout, Val(1))), grid)
      vseq = VectorFieldSpectral(zeros(Complex{T}, F.spectral_field_shape(grid, layout, Val(1))), grid)
      combine!(vseq, T(0.3), u_s, T(0.7), v_s)
      convolve!(vseq, vseq, g)
      vfused = VectorFieldSpectral(zeros(Complex{T}, F.spectral_field_shape(grid, layout, Val(1))), grid)
      combine!(vfused, T(0.3), u_s, T(0.7), v_s, g)
      @test field_data(vfused) == field_data(vseq)

      # aliasing: b === destination (the kernel-filtered accumulate) and kernel === destination
      inplace = scalar_kernel(copy(field_data(b_s)))
      combine!(inplace, T(0.3), phi_s, T(0.7), inplace, g)
      @test field_data(inplace) == field_data(sequential)
      kernel_dest = scalar_kernel(copy(field_data(g)))
      combine!(kernel_dest, T(0.3), phi_s, T(0.7), b_s, kernel_dest)
      @test field_data(kernel_dest) == field_data(sequential)
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
    @test_throws MethodError translation_kernel(phi, FieldSpectralMultipliers(phi_s), (0.1, 0.0, 0.0))
    mult_absence = FieldSpectralMultipliers(phi_s)
    @test_throws MethodError exponential_convolve(phi, mult_absence, -0.1)          # spectral-only too
    @test_throws MethodError exponential_convolve!(phi, phi, mult_absence, -0.1)
    @test_throws MethodError combine!(phi, 0.3, phi, 0.7, phi, ones_kernel)         # kerneled combine! likewise
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

    # translation_kernel on the same mixed-parity grid, over a *random* field (Nyquist content on the
    # two even axes, none on the odd one, where the kernel stays a pure phase at every frequency)
    Random.seed!(20260713)
    noise = ScalarFieldPhysical(randn(T, 8, 7, 6), grid)
    noise_s = to_spectral(noise, plans)
    for axis in 1:3
      displacement = ntuple(d -> d == axis ? grid.grid_spacing[d] : zero(T), 3)
      shifted = to_physical(convolve(noise_s, translation_kernel(noise_s, mult, displacement)), plans)
      @test isapprox(field_data(shifted), circshift(field_data(noise), ntuple(d -> d == axis ? 1 : 0, 3));
                     rtol = 1e-10)
    end
    # and the displaced field stays real (the half-spectrum stays Hermitian) under a half-cell shift
    half_cell = ntuple(d -> grid.grid_spacing[d] / 2, 3)
    half_shifted = convolve(noise_s, translation_kernel(noise_s, mult, half_cell))
    @test isapprox(field_data(to_spectral(to_physical(half_shifted, plans), plans)),
                   field_data(half_shifted); rtol = 1e-10)
  end
end
