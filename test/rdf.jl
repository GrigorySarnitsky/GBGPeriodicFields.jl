# Phase 2 (decision 22): the FFT route to point pair-statistics — the assignment-window deconvolution
# builder, and the worked pair-correlation g(r) recipe validated against an INDEPENDENT direct O(M²)
# pair count in physical space. The package ships the neutral primitive (assignment_window) and the
# radial reductions; the recipe below (density → deconvolve → radial_correlation → g(r)) is the
# consumer assembly (invariant 12: shot-noise / normalization conventions are the consumer's).

using Test
using Random: MersenneTwister
using GBGPeriodicFields
kernel_array(k) = Array(copy(GBGPeriodicFields.Convolution._kernel_data(k)))   # materialize a lazy kernel for inspection
using GBGPeriodicFields: field_data
using Statistics: mean

euclidean(v) = sqrt(sum(abs2, v))      # avoid a LinearAlgebra test-env dependency for one `norm`

@testset "Phase 2: assignment_window + the FFT pair-correlation recipe" begin

  # The builder is exactly ∏_a sinc²(|k_a| Δx_a / 2): real, 1 at the origin, no in-band zeros.
  @testset "assignment_window = ∏ sinc²(|k_a| Δx_a / 2) ($T)" for T in (Float64, Float32)
    layout = RealFourierLayout()
    for gs in ((8, 8, 8), (7, 8, 6))                       # even / mixed parity
      grid = Grid3D(gs, (T(2π), T(2π), T(2π)))
      spec0 = ScalarFieldSpectral(zeros(Complex{T}, spectral_field_shape(grid, layout, Val(0))), grid)
      mult = FieldSpectralMultipliers(spec0)
      window = kernel_array(assignment_window(spec0, mult))
      @test window[1, 1, 1] ≈ one(Complex{T})              # Ŵ(0) = 1
      @test all(w -> 0 < real(w) <= 1 + sqrt(eps(T)) && abs(imag(w)) <= sqrt(eps(T)), window)  # real, (0, 1], no zeros
      # independent ∏ sinc² from the per-axis |k_a|
      usinc(y) = iszero(y) ? one(y) : sin(y) / y
      k = (sqrt.(Array(mult.squared_wavenumber_1)), sqrt.(Array(mult.squared_wavenumber_2)), sqrt.(Array(mult.squared_wavenumber_3)))
      Δ = T(2π) ./ gs
      reference = [(usinc(k[1][i] * Δ[1] / 2) * usinc(k[2][j] * Δ[2] / 2) * usinc(k[3][l] * Δ[3] / 2))^2
                   for i in eachindex(k[1]), j in eachindex(k[2]), l in eachindex(k[3])]
      @test isapprox(real.(window), reference; rtol = T == Float64 ? 1e-12 : 1.0f-4)
    end
  end

  # The FFT pair-correlation estimator reproduces a direct physical-space pair count. A clustered point
  # set (so g(r) > 1 at small r) is run through the recipe and through O(M²) counting; the recipe
  # recovers both the clustering peak (vs direct counting) and the g → 1 baseline (the normalization).
  @testset "g(r): FFT estimator vs direct O(M²) pair counting" begin
    N = 24; L = 2π; grid = Grid3D((N, N, N), (L, L, L)); layout = RealFourierLayout()
    Δ = L / N; V = L^3; cell_volume = Δ^3
    spectral_zero() = ScalarFieldSpectral(zeros(ComplexF64, spectral_field_shape(grid, layout, Val(0))), grid)
    plans = FieldTransformPlans(ScalarFieldPhysical(zeros(N, N, N), grid), spectral_zero())
    multipliers = FieldSpectralMultipliers(spectral_zero())
    linear = LalescuSpline(0, 0)                            # the positive (CIC) assignment for the density

    # clustered points: cluster centers, several Gaussian-scattered points each
    rng = MersenneTwister(2024)
    number_of_clusters, per_cluster, σ = 300, 6, 0.18
    centers = L .* rand(rng, number_of_clusters, 3)
    coordinates = vcat([mod.(reshape(centers[c, :], 1, 3) .+ σ .* randn(rng, per_cluster, 3), L)
                        for c in 1:number_of_clusters]...)
    M = size(coordinates, 1)

    # --- the recipe: density → overdensity → deconvolve → radial_correlation → g(r) ---
    density = anterpolate(grid, PointSet(coordinates), ScalarPointValues(ones(M)), linear)   # counts / cell
    mean_density = M / N^3
    overdensity = to_spectral(ScalarFieldPhysical(field_data(density) ./ mean_density .- 1, grid), plans)
    window = assignment_window(overdensity, multipliers)
    deconvolved = convolve(overdensity, inv(window))     # ÷ Ŵ, fused: 1/∏σₐ = ∏(1/σₐ), no field built
    separations, ξ = radial_correlation(deconvolved, plans)
    g_fft = 1 .+ ξ                                          # g(r) = 1 + ⟨δ(x)δ(x+r)⟩  (shot noise → shell 0)

    # --- independent direct g(r): pair separations binned by the same lattice |r| shells ---
    cells_in_shell = zeros(Int, length(separations))
    for I in CartesianIndices((N, N, N))
      r = sqrt(sum((min(i - 1, N - (i - 1)) * Δ)^2 for i in Tuple(I)))
      b = round(Int, r / Δ) + 1
      b <= length(cells_in_shell) && (cells_in_shell[b] += 1)
    end
    pair_count = zeros(Int, length(separations))
    for i in 1:M-1, j in i+1:M
      d = coordinates[i, :] .- coordinates[j, :]
      d = d .- L .* round.(d ./ L)                         # minimum image
      b = round(Int, euclidean(d) / Δ) + 1
      b <= length(pair_count) && (pair_count[b] += 1)
    end
    # g_direct(shell) = ordered pairs / expected-for-uniform = 2·pairs / (M(M−1)·cells·ΔV/V)
    g_direct = [cells_in_shell[b] == 0 ? NaN :
                2 * pair_count[b] / (M * (M - 1) * cells_in_shell[b] * cell_volume / V) for b in eachindex(separations)]

    @test g_fft[2] > 1.4                                    # the clustering excess is recovered
    @test isapprox(g_fft[2], g_direct[2]; rtol = 0.1)       # and matches direct counting at the peak
    @test isapprox(mean(g_fft[6:14]), 1.0; atol = 0.04)     # g → 1 at large r (correct normalization)
    @test all(isfinite, g_fft)
  end
end
