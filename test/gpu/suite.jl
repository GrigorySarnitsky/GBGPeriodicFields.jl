# Backend-agnostic GPU test suite for GBGPeriodicFields.
#
# This file is included by a backend entry script (test/gpu/<backend>/runtests.jl)
# that must define, before the include:
#   to_device(host_array)  -> a device array (e.g. ROCArray / CuArray)
#   device_functional()    -> Bool, whether a usable device is present
#   GPU_BACKEND::String     -> a human-readable backend label
# and must already have called <Backend>.allowscalar(false). With scalar indexing
# disabled, any scalar index into device memory inside a *package method* throws,
# so the suite mechanically enforces invariant 6 (no scalar indexing of GPU arrays)
# rather than trusting it by inspection.
#
# Strategy: the CPU path is the trusted reference (covered by the top-level suite).
# Each check runs the same operation on a host field and on its device twin — built
# from identical input data — and asserts Array(device_result) ≈ host_result. Any
# scalar indexing done by the *tests themselves* is on host arrays, after Array().

using Test
using GBGPeriodicFields

const F = GBGPeriodicFields.Fields
const T = Float64
const grid = Grid3D((8, 7, 6), (2π, 2π, 2π))     # mixed parity (even, odd, even), as in test/fields.jl
const layout = RealFourierLayout()

# Two analytic 3x3 tensor fields, matching test/fieldalgebra.jl.
tensor_a(x, y, z) = [sin(x) cos(y) 0.3; 0.5 sin(z) cos(x); 1.0 cos(z) sin(y)]
tensor_b(x, y, z) = [cos(x) 0.1 sin(y); sin(z) cos(y) 0.2; 0.7 sin(x) cos(z)]

# A device twin of `field`: same field type, grid, and layout; data copied to the device.
on_device(field) = F.similar_field(field, to_device(copy(field_data(field))))

# Compare a field held on the device against a host field. The small absolute floor
# (atol) keeps the comparison meaningful when the exact result is ~zero: device and
# host run the same formula, so they agree to roundoff, but bare `≈` has atol = 0 and
# would flag two near-zero arrays that differ only by GPU/CPU rounding.
matches(device_field, host_field) =
  isapprox(Array(field_data(device_field)), field_data(host_field); rtol = 1e-8, atol = 1e-8)

# Same-backend forward+inverse plans for a physical field (host or device): the zero
# spectral array is allocated with `similar(field_data(physical), ...)`, so it lands
# on whatever backend `physical` lives on.
function plans_for(physical)
  R = field_tensor_order(physical)
  shape = F.spectral_field_shape(grid, layout, Val(R))
  zero_spectral = similar(field_data(physical), Complex{T}, shape)
  fill!(zero_spectral, 0)
  spectral = R == 0 ? ScalarFieldSpectral(zero_spectral, grid) :
             R == 1 ? VectorFieldSpectral(zero_spectral, grid) :
                      TensorFieldSpectral{R}(zero_spectral, grid)
  return FieldTransformPlans(physical, spectral)
end


@testset "GPU [$GPU_BACKEND]" begin

  if !device_functional()
    @warn "No functional $GPU_BACKEND device detected — skipping on-device tests."
    @test_skip false
  else
    @info "GPU tests running on $GPU_BACKEND."

    @testset "FFT round-trip (scalar / vector / tensor)" begin
      for host in (
          ScalarFieldPhysical((x, y, z) -> sin(x) * cos(y) + 0.3, grid),
          VectorFieldPhysical((x, y, z) -> (sin(x), cos(y), sin(2z)), grid),
          TensorFieldPhysical{2}((x, y, z) -> [sin(x) cos(y) 0.0; 0.0 sin(z) cos(x); 1.0 0.0 sin(y)], grid),
        )
        device = on_device(host)
        plans = plans_for(device)
        back = to_physical(to_spectral(device, plans), plans)
        @test matches(back, host)
      end
    end

    @testset "vector-space ops + broadcasting" begin
      a = ScalarFieldPhysical((x, y, z) -> sin(x), grid)
      b = ScalarFieldPhysical((x, y, z) -> cos(y), grid)
      sf = ScalarFieldPhysical((x, y, z) -> 2.0 + sin(x), grid)   # nonzero everywhere
      v = VectorFieldPhysical((x, y, z) -> (cos(x), sin(y), 1.0), grid)
      ad, bd, sfd, vd = on_device.((a, b, sf, v))

      @test matches(ad + bd, a + b)
      @test matches(ad - bd, a - b)
      @test matches(2.5 * ad, 2.5 * a)
      @test matches(ad / 4.0, a / 4.0)
      @test matches(sfd * vd, sf * v)        # scalar field × vector field
      @test matches(vd / sfd, v / sf)        # division by a scalar field

      # fused dotted assignment writes into device storage
      device_dest = F.similar_field(ad, Val(0))
      host_dest = F.similar_field(a, Val(0))
      @. device_dest = ad - bd
      @. host_dest = a - b
      @test matches(device_dest, host_dest)
    end

    @testset "spectral zero-mode update (invariant 4)" begin
      a = ScalarFieldPhysical((x, y, z) -> sin(x) * cos(y), grid)
      device = on_device(a)
      spectral = to_spectral(device, plans_for(device))
      shifted = spectral + 1.5

      # Bring both to the host before indexing (scalar indexing is disabled on device).
      delta = Array(field_data(shifted)) .- Array(field_data(spectral))
      @test delta[1, 1, 1] ≈ 1.5 * prod(grid.grid_size)
      rest = copy(delta); rest[1, 1, 1] = 0
      @test all(iszero, rest)
    end

    @testset "contractions and products" begin
      u = VectorFieldPhysical((x, y, z) -> (sin(x), cos(y), sin(z) + 0.2), grid)
      v = VectorFieldPhysical((x, y, z) -> (cos(x), sin(2y), cos(z)), grid)
      A = TensorFieldPhysical{2}(tensor_a, grid)
      B = TensorFieldPhysical{2}(tensor_b, grid)
      ud, vd, Ad, Bd = on_device.((u, v, A, B))

      @test matches(dot(ud, vd), dot(u, v))
      @test matches(cross(ud, vd), cross(u, v))
      @test matches(dot(Ad, Bd), dot(A, B))        # tensor Frobenius inner product
      @test matches(Ad * ud, A * u)                # tensor·vector (left action)
      @test matches(ud * Ad, u * A)                # vector·tensor (right action)
      @test matches(Ad * Bd, A * B)                # tensor·tensor

      # mul! five-argument accumulate branch (β ≠ 0)
      host_dest = 2.0 * (A * u)
      device_dest = on_device(host_dest)
      mul!(host_dest, A, u, 3.0, 5.0)
      mul!(device_dest, Ad, ud, 3.0, 5.0)
      @test matches(device_dest, host_dest)

      # mul! overwrite branch (β = 0) must ignore the destination's prior contents:
      # pre-fill with NaN; if it accumulated instead of overwriting, the NaNs survive.
      device_overwrite = F.similar_field(ud, Val(1)); fill!(field_data(device_overwrite), NaN)
      host_overwrite = F.similar_field(u, Val(1)); fill!(field_data(host_overwrite), NaN)
      mul!(device_overwrite, Ad, ud, 1.0, 0.0)
      mul!(host_overwrite, A, u, 1.0, 0.0)
      @test matches(device_overwrite, host_overwrite)
      @test matches(device_overwrite, A * u)       # NaNs gone ⇒ overwrite, not accumulate
    end

    @testset "transpose, sym / skew / dev, norms" begin
      A = TensorFieldPhysical{2}(tensor_a, grid)
      u = VectorFieldPhysical((x, y, z) -> (sin(x), cos(y), sin(z)), grid)
      s = ScalarFieldPhysical((x, y, z) -> sin(x) - 0.5, grid)
      Ad, ud, sd = on_device.((A, u, s))

      @test matches(transpose(Ad), transpose(A))
      @test matches(sym(Ad), sym(A))
      @test matches(skew(Ad), skew(A))
      @test matches(dev(Ad), dev(A))
      @test matches(norm(sd), norm(s))
      @test matches(norm(ud), norm(u))
      @test matches(norm(Ad), norm(A))
    end

    @testset "spectral linear ops + differential operators" begin
      phi = ScalarFieldPhysical((x, y, z) -> sin(x) * cos(y), grid)
      # Components depend on more than one coordinate so curl and the Helmholtz
      # projection are genuinely nonzero: a purely axis-aligned field (sin x, sin y,
      # sin z) is irrotational and longitudinal, so both would project to ~0 and the
      # comparison would degenerate to roundoff.
      u = VectorFieldPhysical((x, y, z) -> (sin(x) + cos(y), sin(y) + cos(z), sin(z) + cos(x)), grid)
      A = TensorFieldPhysical{2}(tensor_a, grid)
      phid, ud, Ad = on_device.((phi, u, A))

      phi_spec_h = to_spectral(phi, plans_for(phi))
      phi_spec_d = to_spectral(phid, plans_for(phid))
      # Multipliers depend only on grid/layout, so one set per representation suffices;
      # built from a device field, the wavenumber arrays land on the device.
      mult_h = FieldSpectralMultipliers(phi_spec_h)
      mult_d = FieldSpectralMultipliers(phi_spec_d)

      # scalar field operators
      @test matches(gradient(phi_spec_d, mult_d), gradient(phi_spec_h, mult_h))
      @test matches(laplacian(phi_spec_d, mult_d), laplacian(phi_spec_h, mult_h))
      @test matches(inverse_laplacian(laplacian(phi_spec_d, mult_d), mult_d),
                    inverse_laplacian(laplacian(phi_spec_h, mult_h), mult_h))

      # vector field operators
      u_spec_h = to_spectral(u, plans_for(u))
      u_spec_d = to_spectral(ud, plans_for(ud))
      @test matches(divergence(u_spec_d, mult_d), divergence(u_spec_h, mult_h))
      @test matches(curl(u_spec_d, mult_d), curl(u_spec_h, mult_h))
      @test matches(gradient(u_spec_d, mult_d), gradient(u_spec_h, mult_h))          # vector -> tensor
      @test matches(helmholtz_projection(u_spec_d, mult_d), helmholtz_projection(u_spec_h, mult_h))

      # spectral linear tensor ops are coefficientwise (valid in spectral representation)
      A_spec_h = to_spectral(A, plans_for(A))
      A_spec_d = to_spectral(Ad, plans_for(Ad))
      @test matches(transpose(A_spec_d), transpose(A_spec_h))
      @test matches(sym(A_spec_d), sym(A_spec_h))
    end

  end

end
