# Generated analytic oracles over a de-symmetrized fixture family (decision 53, guard 4b).
#
# WHY THIS FILE EXISTS. The mutation audit's sharpest finding was not a missing test but a blind
# FIXTURE. The vector-gradient testset is named for the convention (∇u)ᵢⱼ = ∂_{xⱼ}uᵢ, yet its fixture
# u = (sin x, sin y, sin z) has a DIAGONAL gradient — so transposing the whole operator passed
# silently, and the name asserted a convention the fixture could not falsify. The tensor divergence
# was worse: its only value fixture had nine identical components, hence A ≡ Aᵀ, so contracting the
# wrong index was invisible, and every other assertion on it compared one contraction against itself.
#
# THE FIX IS MECHANICAL, WHICH IS THE POINT. A human writing these by hand would never reuse one
# frequency — they would give each slot its own frequency, amplitude and phase, precisely so that an
# accidental symmetry cannot hide a permutation. That instinct is generatable: draw every slot from
# distinct parameters, and the fixture becomes asymmetric BY CONSTRUCTION rather than by care.
#
# AND THE ORACLE STAYS FREE. The derivative of a sinusoid is closed-form whatever its parameters, so
# the oracle is one rule per operator, written once as a formula in the fixture's own parameters, and
# instantiated automatically. This is what makes generation worthwhile here: it is not that more
# cases are run, but that no case is symmetric — a transposed index, a swapped axis, a dropped
# component or a scaled term shows up by signature.
#
# THE FAMILY. Each component is a sum over the three axes,
#     s(x)    = Σₐ  A[a]     · sin(q[a]     · xₐ + φ[a])
#     uᵢ(x)   = Σₐ  A[i,a]   · sin(q[i,a]   · xₐ + φ[i,a])
#     Tᵢⱼ(x)  = Σₐ  A[i,j,a] · sin(q[i,j,a] · xₐ + φ[i,j,a])
# with a distinct amplitude in every slot (so no two slots can be confused), integer frequencies
# safely below the Nyquist of the test grid (so every field is exactly band-limited and the spectral
# operators are exact), and a distinct phase (so no slot is even or odd by accident).

using Test
using GBGPeriodicFields
using GBGPeriodicFields: field_data
using Statistics: mean, var      # the umbrella re-exports these too; explicit here so the file reads standalone

const GRID_POINTS = 16                      # Nyquist = 8; every frequency below stays exactly resolved
const PRIMES = (2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71, 73,
                79, 83, 89, 97, 101, 103)   # 27 distinct amplitudes: enough for a full 3×3×3 tensor

amplitude(n) = PRIMES[n] / 10               # distinct in every slot
frequency(n) = 1 + (n - 1) % 5              # 1..5, comfortably sub-Nyquist
phase(n)     = n / 17                       # distinct, and never 0 or π/2

# The three fixture families and their exact derivatives, as formulas in the parameters above.
scalar_value(x, y, z) = sum(amplitude(a) * sin(frequency(a) * (a == 1 ? x : a == 2 ? y : z) + phase(a)) for a in 1:3)
scalar_gradient(j) = (x, y, z) -> amplitude(j) * frequency(j) * cos(frequency(j) * (j == 1 ? x : j == 2 ? y : z) + phase(j))
scalar_laplacian(x, y, z) = -sum(frequency(a)^2 * amplitude(a) * sin(frequency(a) * (a == 1 ? x : a == 2 ? y : z) + phase(a)) for a in 1:3)

vslot(i, a) = 3 * (i - 1) + a                                  # a distinct parameter index per (component, axis)
vector_value(i) = (x, y, z) -> sum(amplitude(vslot(i, a)) * sin(frequency(vslot(i, a)) * (a == 1 ? x : a == 2 ? y : z) + phase(vslot(i, a))) for a in 1:3)
# ∂_{xⱼ} uᵢ — only the term that depends on xⱼ survives
vector_gradient(i, j) = (x, y, z) -> (n = vslot(i, j); amplitude(n) * frequency(n) * cos(frequency(n) * (j == 1 ? x : j == 2 ? y : z) + phase(n)))
vector_divergence(x, y, z) = sum(vector_gradient(i, i)(x, y, z) for i in 1:3)
vector_laplacian(i) = (x, y, z) -> -sum((n = vslot(i, a); frequency(n)^2 * amplitude(n) * sin(frequency(n) * (a == 1 ? x : a == 2 ? y : z) + phase(n))) for a in 1:3)
# (∇×u)ᵢ = ∂_{xⱼ}u_k − ∂_{x_k}uⱼ for (i,j,k) cyclic
vector_curl(i) = (x, y, z) -> (j = mod1(i + 1, 3); k = mod1(i + 2, 3);
                               vector_gradient(k, j)(x, y, z) - vector_gradient(j, k)(x, y, z))

tslot(i, j, a) = 9 * (i - 1) + 3 * (j - 1) + a
tensor_value(i, j) = (x, y, z) -> sum(amplitude(tslot(i, j, a)) * sin(frequency(tslot(i, j, a)) * (a == 1 ? x : a == 2 ? y : z) + phase(tslot(i, j, a))) for a in 1:3)
# (∇·T)ᵢ = Σⱼ ∂_{xⱼ} Tᵢⱼ — only the xⱼ-dependent term of each Tᵢⱼ survives
tensor_divergence(i) = (x, y, z) -> sum((n = tslot(i, j, j); amplitude(n) * frequency(n) * cos(frequency(n) * (j == 1 ? x : j == 2 ? y : z) + phase(n))) for j in 1:3)


@testset "generated analytic oracles (asymmetric by construction)" begin
  for TP in (Float64, Float32)
    rtol = TP === Float64 ? 1e-10 : 1.0f-3
    atol = TP === Float64 ? 1e-10 : 1.0f-3
    N = GRID_POINTS
    g = Grid3D((N, N, N), (TP(2π), TP(2π), TP(2π)))
    layout = RealFourierLayout()

    plans(R) = FieldTransformPlans(
      R == 0 ? ScalarFieldPhysical(zeros(TP, N, N, N), g) :
      R == 1 ? VectorFieldPhysical(zeros(TP, N, N, N, 3), g) : TensorFieldPhysical(zeros(TP, N, N, N, 3, 3), g),
      (shape = field_spectral_shape(g, layout, Val(R));
       R == 0 ? ScalarFieldSpectral(zeros(Complex{TP}, shape), g) :
       R == 1 ? VectorFieldSpectral(zeros(Complex{TP}, shape), g) : TensorFieldSpectral(zeros(Complex{TP}, shape), g)))
    scalar_of(f) = ScalarFieldPhysical(Array, f, g)
    reference(f) = field_data(ScalarFieldPhysical(Array, f, g))

    s = scalar_of(scalar_value)
    u = VectorFieldPhysical(Array, (x, y, z) -> ntuple(i -> vector_value(i)(x, y, z), 3), g)
    T = TensorFieldPhysical{2}(Array, (x, y, z) -> [tensor_value(i, j)(x, y, z) for i in 1:3, j in 1:3], g)
    ŝ, û, T̂ = to_spectral(s, plans(0)), to_spectral(u, plans(1)), to_spectral(T, plans(2))
    m = FieldSpectralMultipliers(ŝ)

    @testset "$TP" begin
      # ∇ on a scalar — each output slot carries its own frequency, so a swapped axis is visible
      G0 = to_physical(gradient(ŝ, m), plans(1))
      for j in 1:3
        @test isapprox(field_data(G0)[:, :, :, j], reference(scalar_gradient(j)); rtol = rtol, atol = atol)
      end

      # ∇ on a vector — all NINE slots distinct, which is what the diagonal fixture could not do
      G1 = to_physical(gradient(û, m), plans(2))
      for i in 1:3, j in 1:3
        @test isapprox(field_data(G1)[:, :, :, i, j], reference(vector_gradient(i, j)); rtol = rtol, atol = atol)
      end

      # ∇· on a vector and on a tensor — the tensor case had no analytic oracle at all before
      @test isapprox(field_data(to_physical(divergence(û, m), plans(0))), reference(vector_divergence); rtol = rtol, atol = atol)
      DT = to_physical(divergence(T̂, m), plans(1))
      for i in 1:3
        @test isapprox(field_data(DT)[:, :, :, i], reference(tensor_divergence(i)); rtol = rtol, atol = atol)
      end

      # ∇×, Δ on both orders
      C = to_physical(curl(û, m), plans(1))
      for i in 1:3
        @test isapprox(field_data(C)[:, :, :, i], reference(vector_curl(i)); rtol = rtol, atol = atol)
      end
      @test isapprox(field_data(to_physical(laplacian(ŝ, m), plans(0))), reference(scalar_laplacian); rtol = rtol, atol = atol)
      L1 = to_physical(laplacian(û, m), plans(1))
      for i in 1:3
        @test isapprox(field_data(L1)[:, :, :, i], reference(vector_laplacian(i)); rtol = rtol, atol = atol)
      end

      # the fused symmetric gradient against the analytic ½(∇u + ∇uᵀ) — an asymmetric fixture makes
      # this a real check rather than a restatement, since (∇u)ᵢⱼ ≠ (∇u)ⱼᵢ everywhere here
      S = to_physical(symmetric_gradient(û, m), plans(2))
      for i in 1:3, j in 1:3
        expected = (x, y, z) -> (vector_gradient(i, j)(x, y, z) + vector_gradient(j, i)(x, y, z)) / 2
        @test isapprox(field_data(S)[:, :, :, i, j], reference(expected); rtol = rtol, atol = atol)
      end

      # ---- the L²/measure reductions, against CLOSED FORMS rather than against each other ----
      #
      # This is the gap this family closes for the reductions. Every `weighted_inner` assertion in
      # `reductions.jl` is RELATIONAL — it compares against `inner`, `laplacian`, `gradient`,
      # `convolve`, or itself. Those chains do terminate in an independent reference (the physical
      # `inner` is checked against a direct Σ|u|²/N), so they are not circular; but a defect shared
      # by two members of a chain is invisible to it, and the rfft half-spectrum weight α(k) is
      # shared by exactly the routines being compared.
      #
      # On this family the closed forms are exact and elementary, because every cross term vanishes:
      # two terms on the same axis carry different frequencies, and two terms on different axes are
      # independent with zero mean. So ⟨sin²⟩ = ½ gives
      #     ⟨|u|²⟩       = Σᵢₐ A[i,a]² / 2
      #     ⟨∇u : ∇u⟩    = Σᵢₐ (A[i,a]·q[i,a])² / 2        (each ∂ₐ brings down its own q)
      # and both are computed here from the fixture's parameters, touching no other package routine.
      inner_exact = sum(amplitude(vslot(i, a))^2 / 2 for i in 1:3, a in 1:3)
      dirichlet_exact = sum((amplitude(vslot(i, a)) * frequency(vslot(i, a)))^2 / 2 for i in 1:3, a in 1:3)
      scalar_inner_exact = sum(amplitude(a)^2 / 2 for a in 1:3)

      @test isapprox(inner(u, u), TP(inner_exact); rtol = rtol)                    # physical
      @test isapprox(inner(û, û), TP(inner_exact); rtol = rtol)                    # spectral, via Parseval
      @test isapprox(l2norm(u), sqrt(TP(inner_exact)); rtol = rtol)
      @test isapprox(inner(s, s), TP(scalar_inner_exact); rtol = rtol)
      @test isapprox(weighted_inner(û, radial_kernel(identity, m)), TP(dirichlet_exact); rtol = rtol)
      # every component has zero mean (every frequency is ≥ 1), so the variance IS the energy
      @test all(abs.(mean(u)) .< atol)
      @test isapprox(var(s; corrected = false), TP(scalar_inner_exact); rtol = rtol)
      @test isapprox(integral(s), TP(0); atol = atol * prod(g.domain_size))
      # a sharp band keeps exactly the terms whose frequency lies in it — again from the parameters
      for (lo, hi) in ((TP(0), TP(2.5)), (TP(2.5), TP(10)))
        in_band = sum((n = vslot(i, a); lo <= frequency(n) <= hi ? amplitude(n)^2 / 2 : 0.0)
                      for i in 1:3, a in 1:3)
        @test isapprox(weighted_inner(û, spectral_band(m, lo, hi)), TP(in_band); rtol = rtol)
      end
      # and the radial spectrum's shells must sum to the same closed form
      _, spectrum = radial_spectrum(û, m)
      @test isapprox(sum(spectrum), TP(inner_exact); rtol = rtol)

      # every slot of ∇u is distinguishable — the property that makes the assertions above falsifying
      signatures = [maximum(abs, field_data(G1)[:, :, :, i, j]) for i in 1:3, j in 1:3]
      @test length(unique(round.(signatures, digits = 4))) == 9
    end
  end
end
