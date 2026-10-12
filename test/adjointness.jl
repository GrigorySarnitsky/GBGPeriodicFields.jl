# Adjointness and structural identities of the differential operators, on randomized
# band-limited fields. On a periodic box, integration by parts has no boundary terms, so
# with the L² inner product ⟨f, g⟩ = ∫ f·g dx:
#
#   • divergence = -gradientᵀ              ⟨∇φ, u⟩ = -⟨φ, ∇·u⟩
#   • curl is self-adjoint                  ⟨∇×u, v⟩ = ⟨u, ∇×v⟩
#   • the Laplacian is self-adjoint and negative semidefinite:
#       ⟨Δφ, ψ⟩ = ⟨φ, Δψ⟩ = -⟨∇φ, ∇ψ⟩,   so ⟨Δφ, φ⟩ = -‖∇φ‖² < 0
#   • the Helmholtz projection is a self-adjoint idempotent (orthogonal projection):
#       ⟨Pu, v⟩ = ⟨u, Pv⟩,   P² = P,   ⟨Pu, u - Pu⟩ = 0
#
# These are the discrete structural properties that make the scheme respect the energy /
# entropy budget: the Laplacian's negative-definiteness is the dissipation (entropy-
# production) guarantee, and the projection's orthogonal idempotency means the pressure
# term does no net work (energy conservation of incompressible advection).
#
# The inner product here is hand-rolled from physical-space data (node sum × cell volume) on
# purpose: it is the exact discrete L² pairing, independent of the package's own `inner`, so
# these checks do not lean on the reduction layer they help validate. On a periodic grid the
# node sum is also the spectrally exact quadrature of the continuum integral for band-limited
# fields.
#
# Two fixture lanes (decision 42). The operator identities above are exact at EVERY mode —
# both sides of each pairing use one wavenumber family consistently, and the projection is
# the exact discrete projector — so they run on full-spectrum random fields, Nyquist content
# included. The one exception is the dissipation identity ⟨Δφ, ψ⟩ = -⟨∇φ, ∇ψ⟩: it relates
# the Laplacian (true k² at the Nyquist mode, invariant 5) to grad·grad (whose derivative
# wavenumber is zeroed there), so the two agree only away from Nyquist and that identity
# keeps the band-limited fixtures (kmax < N/2).

using Test
using GBGPeriodicFields
using Random

const F = GBGPeriodicFields.Fields
const T = Float64
const grid = Grid3D((12, 9, 8), (2π, 2π, 2π))    # non-cubic, mixed parity (even, odd, even)
const layout = RealFourierLayout()

# Forward+inverse plans, one set per tensor order, reused across the suite.
function plans_of_order(R)
  shape = F.field_spectral_shape(grid, layout, Val(R))
  physical = R == 0 ? ScalarFieldPhysical(zeros(T, F.field_physical_shape(grid, Val(0))), grid) :
             R == 1 ? VectorFieldPhysical(zeros(T, F.field_physical_shape(grid, Val(1))), grid) :
                      TensorFieldPhysical{R}(zeros(T, F.field_physical_shape(grid, Val(R))), grid)
  spectral = R == 0 ? ScalarFieldSpectral(zeros(Complex{T}, shape), grid) :
             R == 1 ? VectorFieldSpectral(zeros(Complex{T}, shape), grid) :
                      TensorFieldSpectral{R}(zeros(Complex{T}, shape), grid)
  return FieldTransformPlans(physical, spectral)
end

const scalar_plans = plans_of_order(0)
const vector_plans = plans_of_order(1)

to_spec(field) = to_spectral(field, field_tensor_order(field) == 0 ? scalar_plans : vector_plans)
to_phys(field) = to_physical(field, field_tensor_order(field) == 0 ? scalar_plans : vector_plans)

# L² inner product ∫ a·b dx over the periodic box: sum over all entries (fiber components
# included), weighted by the cell volume.
l2_inner(a, b) = sum(field_data(a) .* field_data(b)) * prod(grid.grid_spacing)

# Cauchy–Schwarz magnitude ‖a‖·‖b‖ — the natural scale for the absolute floor in the
# inner-product identities below (two equal inner products can have a small common value
# when the fields are near-orthogonal, so a bare relative tolerance trips on roundoff).
cs_scale(a, b) = sqrt(l2_inner(a, a) * l2_inner(b, b))

# Random real, periodic, band-limited fields: sums of cosine modes with |kᵢ| ≤ kmax < N/2.
random_modes(rng, nmodes, kmax) = [(rand(rng, -kmax:kmax, 3), randn(rng), 2π * rand(rng)) for _ in 1:nmodes]
eval_modes(modes, x, y, z) = sum(amplitude * cos(k[1] * x + k[2] * y + k[3] * z + phase) for (k, amplitude, phase) in modes)

random_scalar(rng; nmodes = 10, kmax = 3) =
  let modes = random_modes(rng, nmodes, kmax)
    ScalarFieldPhysical(Array, (x, y, z) -> eval_modes(modes, x, y, z), grid)
  end

function random_vector(rng; nmodes = 10, kmax = 3)
  mx = random_modes(rng, nmodes, kmax)
  my = random_modes(rng, nmodes, kmax)
  mz = random_modes(rng, nmodes, kmax)
  return VectorFieldPhysical(Array, (x, y, z) -> (eval_modes(mx, x, y, z), eval_modes(my, x, y, z), eval_modes(mz, x, y, z)), grid)
end


@testset "adjointness and structural identities (random band-limited fields)" begin

  for seed in (1, 2, 3)
    rng = MersenneTwister(seed)
    φ = random_scalar(rng); ψ = random_scalar(rng)
    u = random_vector(rng); v = random_vector(rng)
    φs = to_spec(φ); ψs = to_spec(ψ); us = to_spec(u); vs = to_spec(v)
    m = FieldSpectralMultipliers(φs)

    @testset "seed $seed" begin
      # transform fidelity on a complex random field
      @test isapprox(field_data(to_phys(us)), field_data(u); rtol = 1e-10)

      # divergence = -gradientᵀ:  ⟨∇φ, u⟩ = -⟨φ, ∇·u⟩
      gradφ = to_phys(gradient(φs, m))
      divu = to_phys(divergence(us, m))
      @test abs(l2_inner(gradφ, u) + l2_inner(φ, divu)) ≤ 1e-8 * cs_scale(gradφ, u)

      # curl is self-adjoint:  ⟨∇×u, v⟩ = ⟨u, ∇×v⟩
      curlu = to_phys(curl(us, m)); curlv = to_phys(curl(vs, m))
      @test abs(l2_inner(curlu, v) - l2_inner(u, curlv)) ≤ 1e-8 * cs_scale(curlu, v)

      # Laplacian: self-adjoint, equal to -grad·grad (dissipation), strictly negative
      Δφ = to_phys(laplacian(φs, m)); Δψ = to_phys(laplacian(ψs, m))
      gradψ = to_phys(gradient(ψs, m))
      @test abs(l2_inner(Δφ, ψ) - l2_inner(φ, Δψ)) ≤ 1e-8 * cs_scale(Δφ, ψ)                 # self-adjoint
      @test abs(l2_inner(Δφ, ψ) + l2_inner(gradφ, gradψ)) ≤ 1e-8 * cs_scale(gradφ, gradψ)   # = -⟨∇φ, ∇ψ⟩
      @test l2_inner(Δφ, φ) < 0                                                              # -‖∇φ‖² < 0: dissipation

      # Helmholtz projection: self-adjoint, idempotent, orthogonal decomposition
      Pus = helmholtz_projection(us, m); Pvs = helmholtz_projection(vs, m)
      Pu = to_phys(Pus); Pv = to_phys(Pvs)
      @test abs(l2_inner(Pu, v) - l2_inner(u, Pv)) ≤ 1e-8 * cs_scale(Pu, v)                  # self-adjoint
      @test isapprox(field_data(to_phys(helmholtz_projection(Pus, m))), field_data(Pu); rtol = 1e-8)  # P² = P
      @test abs(l2_inner(Pu, u - Pu)) ≤ 1e-8 * l2_inner(u, u)                                # ⟨Pu, u - Pu⟩ = 0
    end
  end

  # Full-spectrum lane (decision 42): every identity except the dissipation pairing is exact
  # at every mode, so random data arrays — Nyquist content included — must satisfy them.
  for seed in (11, 12)
    rng = MersenneTwister(seed)
    φ = ScalarFieldPhysical(randn(rng, T, 12, 9, 8), grid)
    ψ = ScalarFieldPhysical(randn(rng, T, 12, 9, 8), grid)
    u = VectorFieldPhysical(randn(rng, T, 12, 9, 8, 3), grid)
    v = VectorFieldPhysical(randn(rng, T, 12, 9, 8, 3), grid)
    φs = to_spec(φ); ψs = to_spec(ψ); us = to_spec(u); vs = to_spec(v)
    m = FieldSpectralMultipliers(φs)

    @testset "full-spectrum seed $seed" begin
      gradφ = to_phys(gradient(φs, m))
      divu = to_phys(divergence(us, m))
      @test abs(l2_inner(gradφ, u) + l2_inner(φ, divu)) ≤ 1e-8 * cs_scale(gradφ, u)
      curlu = to_phys(curl(us, m)); curlv = to_phys(curl(vs, m))
      @test abs(l2_inner(curlu, v) - l2_inner(u, curlv)) ≤ 1e-8 * cs_scale(curlu, v)
      Δφ = to_phys(laplacian(φs, m)); Δψ = to_phys(laplacian(ψs, m))
      @test abs(l2_inner(Δφ, ψ) - l2_inner(φ, Δψ)) ≤ 1e-8 * cs_scale(Δφ, ψ)
      @test l2_inner(Δφ, φ) < 0
      Pus = helmholtz_projection(us, m); Pvs = helmholtz_projection(vs, m)
      Pu = to_phys(Pus); Pv = to_phys(Pvs)
      @test abs(l2_inner(Pu, v) - l2_inner(u, Pv)) ≤ 1e-8 * cs_scale(Pu, v)
      @test isapprox(field_data(to_phys(helmholtz_projection(Pus, m))), field_data(Pu); rtol = 1e-10)
      @test abs(l2_inner(Pu, u - Pu)) ≤ 1e-8 * l2_inner(u, u)
    end
  end

end
