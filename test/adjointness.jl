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
# No package-level integral is needed (and a global L² product is reserved for separate
# code by design — see the umbrella's AI-tips block). The inner product is computed here
# from physical-space data; trapezoidal quadrature on a periodic grid is spectrally exact,
# so it is the exact discrete inner product for band-limited fields.
#
# Fields are kept band-limited below the Nyquist mode (kmax < N/2). The dissipation
# identity relates the Laplacian (which keeps k² at the Nyquist mode) to grad·grad (whose
# derivative wavenumber is zeroed there), and the two agree only away from Nyquist.

using Test
using GBGPeriodicFields
using Random

const F = GBGPeriodicFields.Fields
const T = Float64
const grid = Grid3D((12, 12, 12), (2π, 2π, 2π))
const layout = RealFourierLayout()

# Forward+inverse plans, one set per tensor order, reused across the suite.
function plans_of_order(R)
  shape = F.spectral_field_shape(grid, layout, Val(R))
  physical = R == 0 ? ScalarFieldPhysical(zeros(T, F.physical_field_shape(grid, Val(0))), grid) :
             R == 1 ? VectorFieldPhysical(zeros(T, F.physical_field_shape(grid, Val(1))), grid) :
                      TensorFieldPhysical{R}(zeros(T, F.physical_field_shape(grid, Val(R))), grid)
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

random_scalar(rng; nmodes = 10, kmax = 4) =
  let modes = random_modes(rng, nmodes, kmax)
    ScalarFieldPhysical((x, y, z) -> eval_modes(modes, x, y, z), grid)
  end

function random_vector(rng; nmodes = 10, kmax = 4)
  mx = random_modes(rng, nmodes, kmax)
  my = random_modes(rng, nmodes, kmax)
  mz = random_modes(rng, nmodes, kmax)
  return VectorFieldPhysical((x, y, z) -> (eval_modes(mx, x, y, z), eval_modes(my, x, y, z), eval_modes(mz, x, y, z)), grid)
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

end
