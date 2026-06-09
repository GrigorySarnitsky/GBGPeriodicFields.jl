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
#
# The whole suite runs for each element type in ELEMENT_TYPES — Float32 is the
# realistic GPU precision (consumer GPUs run Float64 far slower), so it must be
# exercised on-device, not just Float64.

using Test
using GBGPeriodicFields

const F = GBGPeriodicFields.Fields
const IP = GBGPeriodicFields.Points
const ELEMENT_TYPES = (Float64, Float32)

# Two analytic 3x3 tensor fields, matching test/fieldalgebra.jl. Element-type
# independent: the field constructor converts each sampled value to the grid's type.
tensor_a(x, y, z) = [sin(x) cos(y) 0.3; 0.5 sin(z) cos(x); 1.0 cos(z) sin(y)]
tensor_b(x, y, z) = [cos(x) 0.1 sin(y); sin(z) cos(y) 0.2; 0.7 sin(x) cos(z)]

# A device twin of `field`: same field type, grid, and layout; data copied to the
# device. `to_device` is supplied by the backend entry script.
on_device(field) = F.similar_field(field, to_device(copy(field_data(field))))

# A device twin of point values: same type and tensor order, data copied to the device.
on_device_pv(values) = IP.similar_pointvalues(values, to_device(copy(point_values(values))))


function run_gpu_suite(::Type{T}) where {T<:AbstractFloat}
  grid = Grid3D((8, 7, 6), (T(2π), T(2π), T(2π)))   # mixed parity (even, odd, even)
  layout = RealFourierLayout()

  # Float32 round-trips and derivatives lose precision relative to Float64; scale the
  # comparison tolerances by element type. The absolute floor keeps comparisons of
  # near-zero results meaningful (device and host run the same formula).
  rtol = T === Float32 ? 1.0f-3 : 1e-8
  atol = T === Float32 ? 1.0f-4 : 1e-8
  matches(device_field, host_field) =
    isapprox(Array(field_data(device_field)), field_data(host_field); rtol = rtol, atol = atol)

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

  @testset "T = $T" begin

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

    @testset "PointValues algebra" begin
      M = 12
      sv = ScalarPointValues(rand(T, M) .+ T(1))     # nonzero everywhere (division)
      vv = VectorPointValues(rand(T, M, 3)); vv2 = VectorPointValues(rand(T, M, 3))
      A = TensorPointValues(rand(T, M, 3, 3)); B = TensorPointValues(rand(T, M, 3, 3))
      a = FiberVector{T}(T(0.3), T(-0.7), T(1.1))
      Af = FiberTensor2{T}(T(0.2), T(0.5), T(-0.3), T(0.7), T(0.1), T(0.9), T(-0.4), T(0.6), T(0.8))
      svd, vvd, vvd2, Ad, Bd = on_device_pv.((sv, vv, vv2, A, B))

      # vector space, scaling, fused dotted assignment into device storage
      @test matches(vvd + vvd2, vv + vv2)
      @test matches(T(2.5) * vvd, T(2.5) * vv)
      @test matches(vvd / T(4), vv / T(4))
      device_dest = IP.similar_pointvalues(vvd, Val(1)); host_dest = IP.similar_pointvalues(vv, Val(1))
      @. device_dest = vvd - vvd2
      @. host_dest = vv - vv2
      @test matches(device_dest, host_dest)

      # scalar-field products, ± constant fiber, scalar × fiber, division
      @test matches(svd * vvd, sv * vv)
      @test matches(vvd / svd, vv / sv)
      @test matches(vvd + a, vv + a)
      @test matches(Ad + Af, A + Af)
      @test matches(svd * a, sv * a)
      @test matches(a / svd, a / sv)

      # contractions
      @test matches(dot(vvd, vvd2), dot(vv, vv2))
      @test matches(cross(vvd, vvd2), cross(vv, vv2))
      @test matches(dot(Ad, Bd), dot(A, B))
      @test matches(Ad * vvd, A * vv)
      @test matches(vvd * Ad, vv * A)
      @test matches(Ad * Bd, A * B)

      # mul! five-argument: accumulate (β ≠ 0) and overwrite (β = 0, NaN-prefilled)
      host_acc = T(2) * (A * vv); device_acc = on_device_pv(host_acc)
      mul!(host_acc, A, vv, T(3), T(5)); mul!(device_acc, Ad, vvd, T(3), T(5))
      @test matches(device_acc, host_acc)
      device_ow = IP.similar_pointvalues(vvd, Val(1)); fill!(point_values(device_ow), T(NaN))
      host_ow = IP.similar_pointvalues(vv, Val(1)); fill!(point_values(host_ow), T(NaN))
      mul!(device_ow, Ad, vvd, T(1), T(0)); mul!(host_ow, A, vv, T(1), T(0))
      @test matches(device_ow, host_ow)
      @test matches(device_ow, A * vv)              # NaNs gone ⇒ overwrite, not accumulate

      # transpose, decompositions, norms
      @test matches(transpose(Ad), transpose(A))
      @test matches(sym(Ad), sym(A))
      @test matches(skew(Ad), skew(A))
      @test matches(dev(Ad), dev(A))
      @test matches(norm(vvd), norm(vv))
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


@testset "GPU [$GPU_BACKEND]" begin

  if !device_functional()
    @warn "No functional $GPU_BACKEND device detected — skipping on-device tests."
    @test_skip false
  else
    @info "GPU tests running on $GPU_BACKEND."
    for T in ELEMENT_TYPES
      run_gpu_suite(T)
    end
  end

end
