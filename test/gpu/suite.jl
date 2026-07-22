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
using Statistics: mean      # extended on sections in the Reductions module (not re-exported)

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

# A device twin of a point set: coordinates copied to the device.
on_device_ps(point_set) = PointSet(to_device(copy(point_coordinates(point_set))))


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
      @test matches(combine!(F.similar_field(ad, Val(0)), 2.0, ad, -3.0, bd),   # combine! (axpby)
                    combine!(F.similar_field(a, Val(0)), 2.0, a, -3.0, b))
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
      @test matches(tr(Ad), tr(A))
      @test matches(det(Ad), det(A))               # nonlinear fiber invariant
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
      @test matches(tr(Ad), tr(A))
      @test matches(det(Ad), det(A))
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
      @test matches(symmetric_gradient(u_spec_d, mult_d), symmetric_gradient(u_spec_h, mult_h))  # fused sym∇
      @test matches(helmholtz_projection(u_spec_d, mult_d), helmholtz_projection(u_spec_h, mult_h))

      # the aliased in-place projection: the one-pass kernel computes destination === source with
      # no guard temporary (decision 32)
      aliased_h = to_spectral(u, plans_for(u));  aliased_d = to_spectral(ud, plans_for(ud))
      helmholtz_projection!(aliased_h, aliased_h, mult_h)
      helmholtz_projection!(aliased_d, aliased_d, mult_d)
      @test matches(aliased_d, aliased_h)

      # spectral linear tensor ops are coefficientwise (valid in spectral representation)
      A_spec_h = to_spectral(A, plans_for(A))
      A_spec_d = to_spectral(Ad, plans_for(Ad))
      @test matches(transpose(A_spec_d), transpose(A_spec_h))
      @test matches(sym(A_spec_d), sym(A_spec_h))
      @test matches(combine!(F.similar_field(A_spec_d, Val(2)), 2.0, A_spec_d, -3.0, A_spec_d),  # combine! spectral
                    combine!(F.similar_field(A_spec_h, Val(2)), 2.0, A_spec_h, -3.0, A_spec_h))

      # kernel-composed operators (a convolution fused into ℙ and ∇·; decision 32), incl. α/β
      kernel_h = spectral_cutoff(u_spec_h, mult_h, T(5) / 2)
      kernel_d = spectral_cutoff(u_spec_d, mult_d, T(5) / 2)
      @test matches(helmholtz_projection(u_spec_d, mult_d, kernel_d),
                    helmholtz_projection(u_spec_h, mult_h, kernel_h))
      @test matches(divergence(u_spec_d, mult_d, kernel_d), divergence(u_spec_h, mult_h, kernel_h))
      @test matches(divergence(A_spec_d, mult_d, kernel_d), divergence(A_spec_h, mult_h, kernel_h))
      composed_h = T(1) * u_spec_h;  composed_d = on_device(composed_h)
      helmholtz_projection!(composed_h, u_spec_h, mult_h, kernel_h, T(3), T(5))
      helmholtz_projection!(composed_d, u_spec_d, mult_d, kernel_d, T(3), T(5))
      @test matches(composed_d, composed_h)
    end

    @testset "convolution (apply a Fourier kernel)" begin
      phi = ScalarFieldPhysical((x, y, z) -> sin(x) * cos(y) + T(0.3), grid)
      u = VectorFieldPhysical((x, y, z) -> (sin(x), cos(y), sin(2z)), grid)
      phid, ud = on_device.((phi, u))

      phi_spec_h = to_spectral(phi, plans_for(phi));  phi_spec_d = to_spectral(phid, plans_for(phid))
      u_spec_h = to_spectral(u, plans_for(u));        u_spec_d = to_spectral(ud, plans_for(ud))
      mult_h = FieldSpectralMultipliers(phi_spec_h);  mult_d = FieldSpectralMultipliers(phi_spec_d)

      # spectral_cutoff allocates the kernel on the reference field's backend, so the device builder
      # must run entirely on-device (no scalar indexing) and match the host kernel.
      cutoff_h = spectral_cutoff(phi_spec_h, mult_h, T(3))
      cutoff_d = spectral_cutoff(phi_spec_d, mult_d, T(3))
      @test matches(cutoff_d, cutoff_h)                                              # the builder itself
      @test matches(convolve(phi_spec_d, cutoff_d), convolve(phi_spec_h, cutoff_h))  # scalar field
      @test matches(convolve(u_spec_d, cutoff_d), convolve(u_spec_h, cutoff_h))      # scalar kernel over a vector field
      A = TensorFieldPhysical{2}(tensor_a, grid); Ad = on_device(A)
      A_spec_h = to_spectral(A, plans_for(A)); A_spec_d = to_spectral(Ad, plans_for(Ad))
      @test matches(convolve(A_spec_d, cutoff_d), convolve(A_spec_h, cutoff_h))      # scalar kernel over a tensor field (R=2)

      # α/β accumulate branch on device
      host_dest = T(2) * convolve(phi_spec_h, cutoff_h); device_dest = on_device(host_dest)
      convolve!(host_dest, phi_spec_h, cutoff_h, T(3), T(5))
      convolve!(device_dest, phi_spec_d, cutoff_d, T(3), T(5))
      @test matches(device_dest, host_dest)

      # the lazy exponential kernel and the kernel-composed combine! (decision 33)
      @test matches(exponential_convolve(u_spec_d, mult_d, T(-1) / 20),
                    exponential_convolve(u_spec_h, mult_h, T(-1) / 20))
      k2_h = squared_wavenumber_field(phi_spec_h, mult_h)
      k2_d = squared_wavenumber_field(phi_spec_d, mult_d)
      @test matches(exponential_convolve(phi_spec_d, mult_d, T(-1) / 20, T(1) / 100, k2_d),
                    exponential_convolve(phi_spec_h, mult_h, T(-1) / 20, T(1) / 100, k2_h))
      # the fiber-extruded offset: a VECTOR field with the per-mode ŵ (the pass-audit ŵ row's GPU twin)
      @test matches(exponential_convolve(u_spec_d, mult_d, T(-1) / 20, T(1) / 100, k2_d),
                    exponential_convolve(u_spec_h, mult_h, T(-1) / 20, T(1) / 100, k2_h))
      combined_h = T(1) * u_spec_h;  combined_d = on_device(combined_h)
      exponential_convolve!(combined_h, T(3) / 10, u_spec_h, T(7) / 10, combined_h, mult_h, T(-1) / 20)
      exponential_convolve!(combined_d, T(3) / 10, u_spec_d, T(7) / 10, combined_d, mult_d, T(-1) / 20)
      @test matches(combined_d, combined_h)
      kerneled_h = T(1) * u_spec_h;  kerneled_d = on_device(kerneled_h)
      combine!(kerneled_h, T(3) / 10, u_spec_h, T(7) / 10, kerneled_h, cutoff_h)
      combine!(kerneled_d, T(3) / 10, u_spec_d, T(7) / 10, kerneled_d, cutoff_d)
      @test matches(kerneled_d, kerneled_h)

      # spectral_band (annular) and squared_wavenumber_field build entirely on-device (no scalar index)
      @test matches(spectral_band(phi_spec_d, mult_d, T(1), T(3)), spectral_band(phi_spec_h, mult_h, T(1), T(3)))
      @test matches(squared_wavenumber_field(phi_spec_d, mult_d), squared_wavenumber_field(phi_spec_h, mult_h))
      # assignment_window (the CIC deconvolution window, ∏ sinc²) — device-clean (ifelse, not Base.sinc)
      @test matches(assignment_window(phi_spec_d, mult_d), assignment_window(phi_spec_h, mult_h))
      # translation_kernel — the one complex kernel; the per-axis cos/sin phase builds on-device
      offset = ntuple(d -> T(0.5) * grid.grid_spacing[d], 3)                  # a half-cell displacement
      shift_h = translation_kernel(phi_spec_h, mult_h, offset)
      shift_d = translation_kernel(phi_spec_d, mult_d, offset)
      @test matches(shift_d, shift_h)                                          # the builder itself
      @test matches(convolve(phi_spec_d, shift_d), convolve(phi_spec_h, shift_h))   # scalar field
      @test matches(convolve(u_spec_d, shift_d), convolve(u_spec_h, shift_h))       # over a vector fiber
      @test matches(convolve(A_spec_d, shift_d), convolve(A_spec_h, shift_h))       # over a tensor fiber (R=2)
    end

    @testset "interpolation / anterpolation (Lalescu splines)" begin
      number_of_points = 50
      host_points = PointSet(T(2π) .* rand(T, number_of_points, 3))
      device_points = on_device_ps(host_points)
      cases = ((ScalarFieldPhysical((x, y, z) -> sin(x) * cos(y) + T(0.3), grid),  ScalarPointValues(rand(T, number_of_points))),
               (VectorFieldPhysical((x, y, z) -> (sin(x), cos(y), sin(2z)), grid), VectorPointValues(rand(T, number_of_points, 3))),
               (TensorFieldPhysical{2}(tensor_a, grid),                            TensorPointValues{2}(rand(T, number_of_points, 3, 3))))
      for (host_field, host_quantities) in cases
        device_field = on_device(host_field)
        device_quantities = on_device_pv(host_quantities)
        # gather
        @test matches(interpolate(device_field, device_points), interpolate(host_field, host_points))
        # scatter (allocating)
        @test matches(anterpolate(grid, device_points, device_quantities), anterpolate(grid, host_points, host_quantities))
        # scatter accumulate (β = 1) exercises the atomic add on top of existing data
        device_accumulated = anterpolate(grid, device_points, device_quantities)
        host_accumulated = anterpolate(grid, host_points, host_quantities)
        anterpolate!(device_accumulated, device_points, device_quantities, CatmullRom, T(1), T(1))
        anterpolate!(host_accumulated, host_points, host_quantities, CatmullRom, T(1), T(1))
        @test matches(device_accumulated, host_accumulated)
      end
      # Non-default schemes: the smooth LalescuSpline(2,1) has a rectangular (6×4) coefficient
      # SMatrix and LagrangeSpline(2) a wider 6-node stencil — both exercise device code paths the
      # square 4×4 CatmullRom does not. Check gather + scatter parity against the CPU.
      for scheme in (LalescuSpline(2, 1), LagrangeSpline(2))
        scalar_host = ScalarFieldPhysical((x, y, z) -> sin(x) * cos(y) + T(0.3), grid)
        quantities_host = ScalarPointValues(rand(T, number_of_points))
        @test matches(interpolate(on_device(scalar_host), device_points, scheme),
                      interpolate(scalar_host, host_points, scheme))
        @test matches(anterpolate(grid, device_points, on_device_pv(quantities_host), scheme),
                      anterpolate(grid, host_points, quantities_host, scheme))
      end
      # heavy atomic-scatter contention: thousands of points crowded into one cell, so the device
      # atomics take many concurrent adds to a few nodes — a race would make this differ from CPU.
      crowded = PointSet(T(0.3) .* rand(T, 3000, 3))
      crowded_quantities = ScalarPointValues(rand(T, 3000))
      @test matches(anterpolate(grid, on_device_ps(crowded), on_device_pv(crowded_quantities)),
                    anterpolate(grid, crowded, crowded_quantities))
    end

    @testset "spectral transfer (DirectDFT / NUFFT)" begin
      number_of_points = 40
      host_points = PointSet(T(2π) .* rand(T, number_of_points, 3))
      device_points = on_device_ps(host_points)
      tol = T === Float32 ? 1.0f-3 : 1e-9
      # band-limited below the Nyquist of (8,7,6) ⇒ NUFFT is exact; scalar + vector
      sf = ScalarFieldPhysical((x, y, z) -> cos(2x) + T(1) / 2 * sin(y) * cos(z) + T(3) / 10, grid)
      vf = VectorFieldPhysical((x, y, z) -> (sin(y) + cos(2z), sin(2x) + cos(z), sin(x) + cos(2y)), grid)
      for host_physical in (sf, vf)
        R = field_tensor_order(host_physical)
        host_spectral = to_spectral(host_physical, plans_for(host_physical))
        device_spectral = to_spectral(on_device(host_physical), plans_for(on_device(host_physical)))
        host_q = R == 0 ? ScalarPointValues(rand(T, number_of_points)) : VectorPointValues(rand(T, number_of_points, 3))
        device_q = on_device_pv(host_q)
        # DirectDFT (stateless): device vs CPU, gather + scatter
        @test matches(interpolate(device_spectral, device_points, DirectDFT()), interpolate(host_spectral, host_points, DirectDFT()))
        @test matches(anterpolate(device_spectral, device_points, device_q, DirectDFT()), anterpolate(host_spectral, host_points, host_q, DirectDFT()))
        # NUFFT (per-backend plan: device plan ↔ device arrays): device vs CPU
        device_nufft = NUFFT(device_spectral; tol = tol)
        host_nufft = NUFFT(host_spectral; tol = tol)
        @test matches(interpolate(device_spectral, device_points, device_nufft), interpolate(host_spectral, host_points, host_nufft))
        @test matches(anterpolate(device_spectral, device_points, device_q, device_nufft), anterpolate(host_spectral, host_points, host_q, host_nufft))
      end
    end

    @testset "L²/measure reductions" begin
      # Reductions return host scalars / fiber values; compare device vs CPU directly. (Summation
      # order differs on the device, so this is a tolerance check, not bitwise.) `var`/`std` are
      # CPU-verified only for now; the device-array Statistics path is a separate follow-up.
      rtol = T == Float64 ? 1e-9 : 1.0f-3
      eq(a, b) = isapprox(a, b; rtol = rtol, atol = rtol)
      sf = ScalarFieldPhysical((x, y, z) -> sin(x) * cos(y) + T(0.3), grid)
      vf = VectorFieldPhysical((x, y, z) -> (sin(x), cos(y), sin(2z) + T(0.1)), grid)
      sfd, vfd = on_device.((sf, vf))
      @test eq(integral(sfd), integral(sf))
      @test eq(mean(sfd), mean(sf))
      @test eq(maximum(sfd), maximum(sf)) && eq(minimum(sfd), minimum(sf))
      @test eq(mean(vfd), mean(vf))                 # fiber-valued (FiberVector), componentwise
      @test eq(integral(vfd), integral(vf))
      @test eq(inner(vfd, vfd), inner(vf, vf))
      @test eq(l2norm(vfd), l2norm(vf))
      @test eq(lpnorm(vfd, Inf), lpnorm(vf, Inf)) && eq(lpnorm(vfd, 4), lpnorm(vf, 4))

      # Mapped forms: the fiber is gathered per base point through a lazy broadcast, so the whole
      # reduction stays one on-device pass with no intermediate section and no scalar indexing.
      tf = TensorFieldPhysical(rand(T, size(field_data(vf))..., 3), grid)
      tfd = on_device(tf)
      @test eq(mean(det, tfd), mean(det, tf))
      @test eq(mean(tr, tfd), mean(tr, tf))
      @test eq(mean(norm, vfd), mean(norm, vf))
      @test eq(mean(abs2, sfd), mean(abs2, sf))
      @test eq(integral(det, tfd), integral(det, tf))
      @test eq(mean(identity, vfd), mean(vf))              # identity map ⇒ the bare fiber reduction
      @test eq(maximum(norm, vfd), maximum(norm, vf))
      @test eq(minimum(norm, vfd), minimum(norm, vf))
      @test eq(maximum(norm, vfd), lpnorm(vf, Inf))        # fused peer of the materializing form

      # spectral (Parseval) inner / l2norm: device == CPU, and equal to the physical inner
      vf_spec_h = to_spectral(vf, plans_for(vf)); vf_spec_d = to_spectral(vfd, plans_for(vfd))
      @test eq(inner(vf_spec_d, vf_spec_d), inner(vf_spec_h, vf_spec_h))
      @test eq(inner(vf_spec_h, vf_spec_h), inner(vf, vf)) && eq(l2norm(vf_spec_d), l2norm(vf_spec_h))

      # spectral integral/mean via the zero (DC) mode: the DC-slot device→host copy runs on-device,
      # matches the CPU, and equals the physical reductions (scalar and fiber-valued)
      sf_spec_h = to_spectral(sf, plans_for(sf)); sf_spec_d = to_spectral(sfd, plans_for(sfd))
      @test eq(integral(sf_spec_d), integral(sf_spec_h)) && eq(mean(sf_spec_d), mean(sf))
      @test eq(integral(vf_spec_d), integral(vf_spec_h)) && eq(mean(vf_spec_d), mean(vf))

      # radial_spectrum: the per-shell binning runs on-device (masked reductions, no scalar indexing).
      # The returned host vectors match the CPU, and sum(spectrum) == inner (the exact refinement).
      mult_h = FieldSpectralMultipliers(vf_spec_h); mult_d = FieldSpectralMultipliers(vf_spec_d)
      shells_d, spectrum_d = radial_spectrum(vf_spec_d, mult_d)
      shells_h, spectrum_h = radial_spectrum(vf_spec_h, mult_h)
      @test shells_d == shells_h && eq(spectrum_d, spectrum_h)
      @test eq(sum(spectrum_d), inner(vf_spec_d, vf_spec_d))

      # weighted_inner ⟨f, w·g⟩: the |k|² weight builds on-device and the reduction is fused (no field);
      # matches the CPU and the exact −Δ identity ⟨f, |k|²·f⟩ = −⟨f, Δf⟩.
      ksq_d = squared_wavenumber_field(sf_spec_d, mult_d); ksq_h = squared_wavenumber_field(sf_spec_h, mult_h)
      @test eq(weighted_inner(vf_spec_d, ksq_d), weighted_inner(vf_spec_h, ksq_h))
      @test eq(weighted_inner(vf_spec_d, ksq_d), -inner(vf_spec_d, laplacian(vf_spec_d, mult_d)))

      # radial_correlation: the inverse rfft + masked-reduction binning run on-device; the returned
      # host vectors match the CPU, and C(0) == inner (the Wiener–Khinchin dual of radial_spectrum).
      seps_d, corr_d = radial_correlation(vf_spec_d, plans_for(vfd))
      seps_h, corr_h = radial_correlation(vf_spec_h, plans_for(vf))
      @test seps_d == seps_h && eq(corr_d, corr_h)
      @test eq(corr_d[1], inner(vf_spec_d, vf_spec_d))

      # co-spectra (two-field forms): the cross-power radial_spectrum(f, g) and the cross-correlation
      # radial_correlation(f, g) run the same device kernels, match the CPU, and refine inner(f, g).
      wf = VectorFieldPhysical((x, y, z) -> (cos(x), sin(y) + T(0.2), cos(2z)), grid)
      wfd = on_device(wf)
      wf_spec_h = to_spectral(wf, plans_for(wf)); wf_spec_d = to_spectral(wfd, plans_for(wfd))
      _, cospectrum_d = radial_spectrum(vf_spec_d, wf_spec_d, mult_d)
      _, cospectrum_h = radial_spectrum(vf_spec_h, wf_spec_h, mult_h)
      @test eq(cospectrum_d, cospectrum_h) && eq(sum(cospectrum_d), inner(vf_spec_d, wf_spec_d))
      _, xcorrelation_d = radial_correlation(vf_spec_d, wf_spec_d, plans_for(vfd))
      _, xcorrelation_h = radial_correlation(vf_spec_h, wf_spec_h, plans_for(vf))
      @test eq(xcorrelation_d, xcorrelation_h) && eq(xcorrelation_d[1], inner(vf_spec_d, wf_spec_d))
      @test eq(weighted_inner(vf_spec_d, wf_spec_d, ksq_d), weighted_inner(vf_spec_h, wf_spec_h, ksq_h))  # weighted mixed co-form

      M = 40
      sp = ScalarPointValues(rand(T, M) .+ T(1)); vp = VectorPointValues(rand(T, M, 3))
      spd, vpd = on_device_pv.((sp, vp))
      @test eq(mean(spd), mean(sp)) && eq(integral(spd), integral(sp))   # counting measure ⇒ (1/M)Σ, Σ
      @test eq(mean(vpd), mean(vp))
      @test eq(inner(vpd, vpd), inner(vp, vp)) && eq(l2norm(vpd), l2norm(vp))
      @test eq(maximum(spd), maximum(sp))
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
