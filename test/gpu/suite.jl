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
using Statistics: mean, std, var, cov      # the umbrella re-exports these four too; explicit here so the file reads standalone

const F = GBGPeriodicFields.Fields
const IP = GBGPeriodicFields.Points
const ELEMENT_TYPES = (Float64, Float32)

# Two analytic 3x3 tensor fields, matching test/fieldalgebra.jl. Element-type
# independent: the field constructor converts each sampled value to the grid's type.
tensor_a(x, y, z) = [sin(x) cos(y) 0.3; 0.5 sin(z) cos(x); 1.0 cos(z) sin(y)]
tensor_b(x, y, z) = [cos(x) 0.1 sin(y); sin(z) cos(y) 0.2; 0.7 sin(x) cos(z)]

# Device twins, through the package's own interface. These three were hand-written rewraps until the
# storage-family move became public: each reached into a section's storage, copied it, and rebuilt the
# section around the result — which is precisely what `adapt` now does, once, for every section, kernel
# and plan. Using it here means the suite exercises the shipped interface rather than a private
# imitation of it, so a defect in the real one cannot hide behind a parallel implementation.
on_device(field)         = adapt(device_array_type(), field)
on_device_pv(values)     = adapt(device_array_type(), values)
on_device_ps(point_set)  = adapt(device_array_type(), point_set)


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
  # An axis-factored kernel holds no field, so compare the materialized product of its per-axis
  # factors (built on whichever backend the kernel lives on).
  kernel_array(k) = Array(copy(GBGPeriodicFields.Convolution._kernel_data(k)))
  kernel_matches(device_kernel, host_kernel) =
    isapprox(kernel_array(device_kernel), kernel_array(host_kernel); rtol = rtol, atol = atol)

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

    @testset "rank-free transform plans, and the staged odd grid (decision 76)" begin
      # The suite's own grid is (8, 7, 6) — an even product, so it takes the direct path and never
      # reaches the staging branch. An all-odd grid is the only thing that does: a device backend
      # refuses a component whose start is not aligned to its complex element, so those grids
      # transform through a component buffer. Both paths must give the same answer.
      for dims in ((8, 7, 6), (7, 5, 3))
        odd_grid = Grid3D(dims, (T(2π), T(2π), T(2π)))
        device_physical = VectorFieldPhysical(device_array_type(), odd_grid, layout)
        device_spectral = VectorFieldSpectral(device_array_type(), odd_grid, layout)
        sample = rand(T, size(field_data(device_physical)))
        copyto!(field_data(device_physical), sample)
        plans = FieldTransformPlans(device_physical, device_spectral)
        # The buffer exists exactly when the offsets do not align, and not otherwise.
        @test (plans.component_scratch === nothing) == iseven(prod(dims))
        to_spectral!(device_spectral, device_physical, plans)
        to_physical!(device_physical, device_spectral, plans)
        @test isapprox(Array(field_data(device_physical)), sample; rtol = rtol, atol = atol)
      end

      # One plan pair serves every rank: built from a scalar field, applied to a vector one.
      scalar_plans = FieldTransformPlans(ScalarFieldPhysical(device_array_type(), grid, layout),
                                         ScalarFieldSpectral(device_array_type(), grid, layout))
      vector_physical = VectorFieldPhysical(device_array_type(), grid, layout)
      vector_spectral = VectorFieldSpectral(device_array_type(), grid, layout)
      vector_sample = rand(T, size(field_data(vector_physical)))
      copyto!(field_data(vector_physical), vector_sample)
      to_spectral!(vector_spectral, vector_physical, scalar_plans)
      to_physical!(vector_physical, vector_spectral, scalar_plans)
      @test isapprox(Array(field_data(vector_physical)), vector_sample; rtol = rtol, atol = atol)
    end

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

        # The preserving scratch arity (decision 64), on device: the source survives bitwise and the
        # answer equals the allocating preserving form. On some GPU backends the 3-arg form happens
        # to preserve too (invariant 11 is backend-divergent), so bitwise source equality here is
        # necessary but the CPU lane is where the preservation claim is actually falsifiable.
        spectral_device = to_spectral(device, plans)
        spectral_before = copy(field_data(spectral_device))
        scratch = F.similar_field(spectral_device, Val(field_tensor_order(spectral_device)))
        out = F.similar_field(device, Val(field_tensor_order(device)))
        to_physical!(out, spectral_device, plans, scratch)
        @test Array(field_data(spectral_device)) == Array(spectral_before)
        @test Array(field_data(out)) == Array(field_data(to_physical(spectral_device, plans)))
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

    @testset "map! / map (arbitrary φ)" begin
      A = TensorFieldPhysical{2}(tensor_a, grid)
      u = VectorFieldPhysical((x, y, z) -> (sin(x), cos(y), sin(z)), grid)
      v = VectorFieldPhysical((x, y, z) -> (cos(x), sin(2y), cos(z)), grid)
      Ad, ud, vd = on_device.((A, u, v))
      @test matches(map(det, Ad), map(det, A))                  # tensor → scalar
      @test matches(map(exp ∘ det, Ad), map(exp ∘ det, A))      # composition + exp device intrinsic
      @test matches(map(x -> 2x, Ad), map(x -> 2x, A))          # tensor → tensor
      @test matches(map(norm, ud), map(norm, u))                # vector → scalar
      @test matches(map((a, b) -> a + b, ud, vd), map((a, b) -> a + b, u, v))   # multi-input
      # single-source α/β accumulate on device matches host
      host_acc = map(det, A); device_acc = on_device(host_acc)
      map!(det, host_acc, A, 2.0, 1.0); map!(det, device_acc, Ad, 2.0, 1.0)
      @test matches(device_acc, host_acc)
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

    @testset "base-space motion (displace!/wrap!)" begin
      number_of_points = 300
      host_start = rand(T, number_of_points, 3) .* T(2π)
      host_v1 = VectorPointValues(randn(T, number_of_points, 3))
      host_v2 = VectorPointValues(randn(T, number_of_points, 3))
      device_v1 = on_device_pv(host_v1)
      device_v2 = on_device_pv(host_v2)
      motion_grid = Grid3D((8, 12, 16), (T(2π), T(4π), T(6π)))   # anisotropic box

      # Displacement is arithmetic, so the backends are compared with a tolerance rather than
      # bitwise: a device compiler contracts `x + c*v` into a fused multiply-add (one rounding)
      # where the CPU multiplies then adds (two), so the two differ in the last bit. Measured on
      # CUDA, the device result equals the host's `muladd` form exactly. Bitwise agreement is
      # required of the CPU across thread counts, never across backends.
      host_points = PointSet(copy(host_start))
      device_points = on_device_ps(PointSet(copy(host_start)))
      displace!(host_points, (T(0.3), host_v1), (T(-0.7), host_v2))
      displace!(device_points, (T(0.3), device_v1), (T(-0.7), device_v2))
      @test isapprox(Array(point_coordinates(device_points)), point_coordinates(host_points);
                     rtol = rtol, atol = atol)

      # A wrapped coordinate lives on a circle, so the torus form compares the difference
      # modulo the box: a last-bit disagreement arriving at the wrap could otherwise place the
      # backends on opposite sides of a boundary and read as a whole box length.
      box = reshape(collect(motion_grid.domain_size), 1, 3)
      wrapped_matches(device_set, host_set) =
        all(abs.(mod.(Array(point_coordinates(device_set)) .- point_coordinates(host_set) .+ box ./ 2,
                      box) .- box ./ 2) .<= atol .+ rtol .* box)

      # Torus displacement (the wrap fused in) and the standalone wrap.
      host_points = PointSet(copy(host_start))
      device_points = on_device_ps(PointSet(copy(host_start)))
      displace!(host_points, motion_grid, (T(2.5), host_v1))
      displace!(device_points, motion_grid, (T(2.5), device_v1))
      @test wrapped_matches(device_points, host_points)

      host_far = PointSet(host_start .+ T(5) .* reshape([T(2π), T(4π), T(6π)], 1, 3))
      device_far = on_device_ps(PointSet(copy(point_coordinates(host_far))))
      wrap!(host_far, motion_grid)
      wrap!(device_far, motion_grid)
      # `wrap!` alone stays bitwise: both sides start from identical host coordinates and the
      # reduction is `mod` plus an equality fold, with no multiply-add for a device to contract.
      @test Array(point_coordinates(device_far)) == point_coordinates(host_far)

      # The destination/source form, destination on the device.
      host_dest = PointSet(zeros(T, number_of_points, 3))
      device_dest = on_device_ps(PointSet(zeros(T, number_of_points, 3)))
      host_src = PointSet(copy(host_start))
      device_src = on_device_ps(PointSet(copy(host_start)))
      displace!(host_dest, host_src, (T(1.5), host_v1))
      displace!(device_dest, device_src, (T(1.5), device_v1))
      @test isapprox(Array(point_coordinates(device_dest)), point_coordinates(host_dest);
                     rtol = rtol, atol = atol)

      # A device point set refuses host sections and a mixed point-set pair — the package's own
      # ArgumentError, not a launch-layer failure (invariant 14).
      @test_throws ArgumentError displace!(device_points, (T(1), host_v1))
      @test_throws ArgumentError displace!(device_dest, host_src, (T(1), device_v1))
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
      @test matches(inverse_curl(u_spec_d, mult_d), inverse_curl(u_spec_h, mult_h))
      @test matches(gradient(u_spec_d, mult_d), gradient(u_spec_h, mult_h))          # vector -> tensor
      @test matches(symmetric_gradient(u_spec_d, mult_d), symmetric_gradient(u_spec_h, mult_h))  # fused sym∇
      @test matches(helmholtz_projection(u_spec_d, mult_d), helmholtz_projection(u_spec_h, mult_h))
      @test matches(laplacian(u_spec_d, mult_d), laplacian(u_spec_h, mult_h))        # vector Δ
      A_spec_h = gradient(u_spec_h, mult_h)
      A_spec_d = gradient(u_spec_d, mult_d)
      @test matches(divergence(A_spec_d, mult_d), divergence(A_spec_h, mult_h))      # tensor2 -> vector

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
      @test matches(skew(A_spec_d), skew(A_spec_h))
      @test matches(dev(A_spec_d), dev(A_spec_h))
      @test matches(tr(A_spec_d), tr(A_spec_h))
      @test matches(combine!(F.similar_field(A_spec_d, Val(2)), 2.0, A_spec_d, -3.0, A_spec_d),  # combine! spectral
                    combine!(F.similar_field(A_spec_h, Val(2)), 2.0, A_spec_h, -3.0, A_spec_h))

      # kernel-composed operators (a convolution fused into ℙ and ∇·; decision 32), incl. α/β
      kernel_h = spectral_cutoff(mult_h, T(5) / 2)
      kernel_d = spectral_cutoff(mult_d, T(5) / 2)
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
      cutoff_h = spectral_cutoff(mult_h, T(3))
      cutoff_d = spectral_cutoff(mult_d, T(3))
      @test kernel_matches(cutoff_d, cutoff_h)                                              # the builder itself
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
      # ŵ is a FIELD (a per-mode offset), so |k|² is materialized from its radial symbol for this use.
      k2_h = materialize_kernel(radial_kernel(identity, mult_h)).field
      k2_d = materialize_kernel(radial_kernel(identity, mult_d)).field
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

      # spectral_band (annular) and the radial |k|² symbol build entirely on-device (no scalar index)
      @test kernel_matches(spectral_band(mult_d, T(1), T(3)), spectral_band(mult_h, T(1), T(3)))
      @test matches(materialize_kernel(radial_kernel(identity, mult_d)).field, materialize_kernel(radial_kernel(identity, mult_h)).field)
      # assignment_window (the CIC deconvolution window, ∏ sinc²) — device-clean (ifelse, not Base.sinc)
      @test kernel_matches(assignment_window(mult_d), assignment_window(mult_h))
      # translation_kernel — the one complex kernel; the per-axis cos/sin phase builds on-device
      offset = ntuple(d -> T(0.5) * grid.grid_spacing[d], 3)                  # a half-cell displacement
      shift_h = translation_kernel(mult_h, offset)
      shift_d = translation_kernel(mult_d, offset)
      @test kernel_matches(shift_d, shift_h)
      # M2: a compressed kernel through the OPERATORS' kernel arity, on device — the lazy per-axis
      # product crossing a KA launch inside helmholtz/divergence, not only inside convolve!
      @test matches(helmholtz_projection(u_spec_d, mult_d, shift_d),
                    helmholtz_projection(u_spec_h, mult_h, shift_h))
      @test matches(divergence(u_spec_d, mult_d, shift_d), divergence(u_spec_h, mult_h, shift_h))                                          # the builder itself
      @test matches(convolve(phi_spec_d, shift_d), convolve(phi_spec_h, shift_h))   # scalar field
      @test matches(convolve(u_spec_d, shift_d), convolve(u_spec_h, shift_h))       # over a vector fiber
      @test matches(convolve(A_spec_d, shift_d), convolve(A_spec_h, shift_h))       # over a tensor fiber (R=2)

      # Storage-class agreement ON THE DEVICE, at α ≠ 1. The CPU suite asserts this class-wide, but
      # the compressed path it exercises is dead code there — the gated CPU twin always wins — so the
      # broadcast route was only ever compared against a materialized kernel at α = 1, where scaling
      # is exact and the association cannot show. It left-associated ((((α σ₁) σ₂) σ₃) f̂) against the
      # stored path's α((σ₁σ₂)σ₃)f̂, and disagreed with its own materialized kernel at every other α.
      # /bug-hunt 2026-08-27; REAL factors, so the complex-multiply FMA contraction below cannot
      # confound it and bitwise is the honest bar.
      window_d = assignment_window(mult_d)
      stored_d = materialize_kernel(window_d)
      for (α, β) in ((T(1), T(0)), (T(37) / 10, T(0)), (T(1) / 10, T(1) / 2))
        compressed_out = similar_field(phi_spec_d, similar(field_data(phi_spec_d)))
        stored_out     = similar_field(phi_spec_d, similar(field_data(phi_spec_d)))
        fill!(field_data(compressed_out), 0); fill!(field_data(stored_out), 0)
        convolve!(compressed_out, phi_spec_d, window_d, α, β)
        convolve!(stored_out,     phi_spec_d, stored_d, α, β)
        @test Array(field_data(compressed_out)) == Array(field_data(stored_out))
      end
      # A COMPLEX kernel is the documented exception: a device contracts the `ac - bd` of a complex
      # multiply into an FMA and does it differently inlined than read back from stored coefficients,
      # so the classes agree to rounding rather than bitwise. Pinned as a tolerance, which is what the
      # docstrings now promise — asserting bitwise here would be asserting something untrue.
      @test isapprox(Array(field_data(convolve(phi_spec_d, shift_d))),
                     Array(field_data(convolve(phi_spec_d, materialize_kernel(shift_d))));
                     rtol = rtol, atol = atol)
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
      # order differs on the device, so this is a tolerance check, not bitwise.) `var`/`std` (scalar) and
      # the covariance tensor `cov` run on the device through the same reduce / mapped-mean paths (decision 49).
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
      @test eq(var(sfd), var(sf)) && eq(std(sfd), std(sf))     # scalar var/std on the device (decision 49)
      @test eq(cov(vfd), cov(vf))                              # the covariance tensor of a vector field
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
      # A weight is a kernel, and |k|² is a radial symbol — so it is the symbol itself, not a field.
      ksq_d = radial_kernel(identity, mult_d)
      ksq_h = radial_kernel(identity, mult_h)
      @test eq(weighted_inner(vf_spec_d, ksq_d), weighted_inner(vf_spec_h, ksq_h))
      @test eq(weighted_inner(vf_spec_d, ksq_d), -inner(vf_spec_d, laplacian(vf_spec_d, mult_d)))
      # Several weights in ONE traversal (decision 72). The device is the reason it exists — three
      # separate calls block three times — and the tuple accumulator is the only spelling that stays
      # on the device at all: a `zip` of the operands falls back to scalar indexing and dies here.
      band_d = spectral_band(mult_d, 1.0, 2.0)
      band_h = spectral_band(mult_h, 1.0, 2.0)
      fused_d = weighted_inner(vf_spec_d, (ksq_d, band_d))
      @test length(fused_d) == 2
      @test eq(fused_d[1], weighted_inner(vf_spec_d, ksq_d))     # same as the separate calls,
      @test eq(fused_d[2], weighted_inner(vf_spec_d, band_d))
      @test eq(fused_d[1], weighted_inner(vf_spec_h, ksq_h))     # and same as the host
      @test eq(fused_d[2], weighted_inner(vf_spec_h, band_h))

      # Every kernel storage class serves as a weight (decision 62). This is the case worth having on a
      # device: `_kernel_data` for the compressed classes is a lazy `Broadcasted`, and `ProductKernel`
      # nests two of them, so the reduction runs over a nested lazy tree. That is exactly where the
      # `instantiate` this function already needed for AMDGPU's `mapreducedim!` (a `Broadcasted` with
      # `Nothing` axes throws there) would resurface if the nesting broke it.
      sep_d = assignment_window(mult_d);  sep_h = assignment_window(mult_h)
      cut_d = spectral_cutoff(mult_d, 2.5); cut_h = spectral_cutoff(mult_h, 2.5)
      for (kd, kh) in ((sep_d, sep_h), (cut_d, cut_h),
                       (convolve(cut_d, sep_d), convolve(cut_h, sep_h)))   # separable, radial, product
        @test eq(weighted_inner(vf_spec_d, kd), weighted_inner(vf_spec_h, kh))
        @test eq(weighted_inner(vf_spec_d, kd), weighted_inner(vf_spec_d, materialize_kernel(kd)))
      end
      # ...and a complex weight is refused on the device too, by the same type-level check.
      phase_d = translation_kernel(mult_d, (0.3, 0.1, 0.2))
      @test_throws ArgumentError weighted_inner(vf_spec_d, phase_d)

      # Permuted rfft layout: the Parseval fold follows fft_dims on the device too — the spectral
      # inner's correction planes and the shell kernel's weight axis are selected by the layout.
      permuted_layout = RealFourierLayout((2, 1, 3))
      permuted_h = ScalarFieldSpectral(rand(Complex{T}, spectral_field_shape(grid, permuted_layout, Val(0))),
                                       grid, permuted_layout)
      permuted_d = on_device(permuted_h)
      pmult_h = FieldSpectralMultipliers(permuted_h); pmult_d = FieldSpectralMultipliers(permuted_d)
      @test eq(inner(permuted_d, permuted_d), inner(permuted_h, permuted_h))
      pshells_d, pspectrum_d = radial_spectrum(permuted_d, pmult_d)
      pshells_h, pspectrum_h = radial_spectrum(permuted_h, pmult_h)
      @test pshells_d == pshells_h && eq(pspectrum_d, pspectrum_h)

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

    # ── mixing a device section with a host one must be REFUSED, deliberately ──────────────────
    #
    # This needs two storage families in one process, so it can only live here. `dot`, `add!`,
    # `cross!` and `multiply!` all refused through the package's own domain check with a clear
    # message, while `inner` refused only because the vendor BLAS has no method taking a device
    # pointer and a host pointer together — reported as `no method matching dot(::Int64,
    # ::CuPtr{Float64}, …)`. That was an accident of the library rather than a decision of the
    # package, and it would have gone quiet the moment any path accepted mixed pointers. The
    # storage-family check now sits in `_check_contractible`, which every reduction routes through.
    @testset "a device section and a host section cannot be contracted" begin
      grid = Grid3D((8, 8, 8), (2π, 2π, 2π))
      host = VectorFieldPhysical(rand(Float64, 8, 8, 8, 3), grid)
      device = on_device(host)
      @test_throws ArgumentError inner(device, host)
      @test_throws ArgumentError inner(host, device)
      host_values = ScalarPointValues(rand(Float64, 12))
      device_values = IP.ScalarPointValues(to_device(copy(point_values(host_values))))
      @test_throws ArgumentError inner(device_values, host_values)
      # The same-family calls must be untouched by the guard.
      @test inner(device, device) isa Real
      @test l2norm(device) isa Real
    end

    # ── the PARTNER arguments, which are a different check ────────────────────────────────────
    #
    # The multipliers are not a section, so they miss the section-level check entirely. Measured
    # before the guard existed: a device field with host multipliers reached `gradient`,
    # `laplacian`, `divergence`, `helmholtz_projection` and `radial_spectrum`, and every one died
    # with a `KernelError` — KernelAbstractions declining to launch over mixed arrays, which is the
    # right outcome for the wrong reason, exactly as `inner` refused only because CUBLAS lacked a
    # mixed-pointer method. `_check_multipliers_compatibility` already checked scalar type, grid and
    # layout; it was missing this one clause.
    @testset "a device field and host multipliers cannot be combined" begin
      grid = Grid3D((8, 8, 8), (2π, 2π, 2π))
      layout = RealFourierLayout()
      host_spectral = ScalarFieldSpectral(
          randn(ComplexF64, F.spectral_field_shape(grid, layout, Val(0))...), grid, layout)
      device_spectral = on_device(host_spectral)
      host_multipliers = FieldSpectralMultipliers(host_spectral)
      device_multipliers = FieldSpectralMultipliers(device_spectral)
      @test_throws ArgumentError gradient(device_spectral, host_multipliers)
      @test_throws ArgumentError laplacian(device_spectral, host_multipliers)
      @test_throws ArgumentError radial_spectrum(device_spectral, host_multipliers)
      # Matched pairs on either side stay legal, so the guard cannot pass by refusing everything.
      @test gradient(device_spectral, device_multipliers) isa VectorFieldSpectral
      @test gradient(host_spectral, host_multipliers) isa VectorFieldSpectral
    end

    # The move itself, on real hardware. The rest of the suite uses `adapt` through `on_device`, which
    # exercises the field methods everywhere; what needs its own case is the companion set, because a
    # moved field alone computes nothing — invariant 14 requires its multipliers to match, and its
    # plans cannot be transferred at all, only rebuilt.
    @testset "moving a whole workspace between storage families" begin
      grid, layout = Grid3D((8, 8, 8), (2pi, 4pi, 6pi)), RealFourierLayout()
      host_u = VectorFieldPhysical(rand(Float64, 8, 8, 8, 3), grid, layout)
      host_z = ScalarFieldSpectral(zeros(ComplexF64, spectral_field_shape(grid, layout, Val(0))...), grid, layout)
      host_plans = FieldTransformPlans(host_u, similar_field(host_z, Val(1)))
      host_multipliers = FieldSpectralMultipliers(similar_field(host_z, Val(1)))
      host_kernel = spectral_cutoff(host_multipliers, 3.0)

      AT = device_array_type()
      device_u, device_plans = adapt(AT, host_u), adapt(AT, host_plans)
      device_multipliers, device_kernel = adapt(AT, host_multipliers), adapt(AT, host_kernel)

      @test field_data(device_u) isa AT
      @test device_multipliers.wavenumber_1 isa AT

      # The reality check (decision 71) must survive `allowscalar(false)` — it walks whole planes with
      # `reverse`/`circshift` precisely so it never touches a device array one element at a time.
      @test reality_residual(adapt(AT, host_z)) == 0
      # Corrupted on the HOST and then moved, because a scalar write to a device array is exactly what
      # `allowscalar(false)` forbids — and what this operation must not need.
      host_corrupt = ScalarFieldSpectral(copy(field_data(host_z)), grid, layout)
      field_data(host_corrupt)[1, 3, 2] += 0.6 + 0.25im
      @test reality_residual(adapt(AT, host_corrupt)) ≈ reality_residual(host_corrupt)
      @test reality_residual(adapt(AT, host_corrupt)) ≈ abs(0.6 + 0.25im)

      # The IN-PLACE move (decision 69), which is the only place a second storage family exists to
      # cross. The gate proves everything about `adapt!` except the crossing itself.
      into_device = similar_field(device_u, Val(1))
      fill!(field_data(into_device), 0)
      @test adapt!(into_device, host_u) === into_device
      @test field_data(into_device) isa AT                     # the destination's family is kept
      @test Array(field_data(into_device)) == field_data(host_u)
      into_host = similar_field(host_u, Val(1))
      fill!(field_data(into_host), 0)
      @test adapt!(into_host, device_u) === into_host          # and the return trip
      @test field_data(into_host) isa Array
      @test field_data(into_host) == field_data(host_u)
      # Point sections cross too, and a mismatched pair is refused on the device exactly as on the host.
      host_q = VectorPointValues(randn(Float64, 6, 3))
      device_q = adapt(AT, host_q)
      back_q = similar_pointvalues(host_q, Val(1))
      @test adapt!(back_q, device_q) === back_q
      @test GBGPeriodicFields.Points.point_values(back_q) == GBGPeriodicFields.Points.point_values(host_q)
      @test_throws ArgumentError adapt!(similar_field(adapt(AT, host_z), Val(0)),
                                        ScalarFieldSpectral(zeros(ComplexF64, spectral_field_shape(
                                            Grid3D((8, 8, 8), (2pi, 2pi, 2pi)), layout, Val(0))...),
                                            Grid3D((8, 8, 8), (2pi, 2pi, 2pi)), layout))
      # A round trip must return the values unchanged, and the metadata with them.
      returned = adapt(Array, device_u)
      @test field_data(returned) == field_data(host_u)
      @test field_grid(returned) == field_grid(host_u)
      @test field_layout(returned) == field_layout(host_u)

      # The rebuilt plans must transform, and the moved companions must compute what the host does.
      host_curl = field_data(to_physical(curl(to_spectral(host_u, host_plans), host_multipliers), host_plans))
      device_curl = Array(field_data(to_physical(curl(to_spectral(device_u, device_plans), device_multipliers),
                                                 device_plans)))
      @test device_curl ≈ host_curl
      host_filtered = field_data(convolve(to_spectral(host_u, host_plans), host_kernel))
      device_filtered = Array(field_data(convolve(to_spectral(device_u, device_plans), device_kernel)))
      @test device_filtered ≈ host_filtered

      # The point layer mirrors it.
      host_points = PointSet(rand(Float64, 6, 3) .* 2pi)
      @test point_coordinates(adapt(AT, host_points)) isa AT
      @test Array(point_coordinates(adapt(AT, host_points))) == point_coordinates(host_points)
    end

    @testset "allocating constructors produce device fields (decision 74)" begin
      AT = device_array_type()
      grid = Grid3D((8, 6, 4), (2π, 2π, 2π))
      layout = RealFourierLayout()
      # Allocate directly on the device family — no host array, no reference field — and use it.
      device_u = VectorFieldSpectral(AT, grid, layout)
      @test field_data(device_u) isa AT
      @test size(field_data(device_u)) == spectral_field_shape(grid, layout, Val(1))
      device_s = ScalarFieldPhysical(AT, grid)
      field_data(device_s) .= 1.0
      @test integral(device_s) ≈ prod(grid.domain_size)
      # The refusals are identical on a device family.
      @test_throws ArgumentError ScalarFieldPhysical(AT{Float32}, grid)
      @test_throws ArgumentError ScalarFieldSpectral(AT{ComplexF64}, grid)
    end
  end

end
