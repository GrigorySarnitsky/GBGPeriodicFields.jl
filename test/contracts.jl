# Negative contract tests for the strict compatibility protocol (external static audit, P0/P2).
#
# The suite already tests missing-object errors (a group without a `data` dataset, a field of the wrong
# shape). What it did not test is the class the audit's source findings almost all belong to:
# SEMANTICALLY INCONSISTENT input that is structurally fine. A multiplier set for another domain with
# the same axis lengths, a NUFFT plan for another grid, a negative band edge, an exponent outside the
# norm domain — each of these was accepted, and each returned a plausible number or a silently wrong
# field. Every assertion below is a case that previously succeeded.
#
# Grouped by what is being validated rather than by module, which is how the protocol is organized:
# one context predicate, one set of numeric domains, one set of constructor invariants.

using Test
using GBGPeriodicFields
using Statistics: mean

const CONTRACT_LAYOUT = RealFourierLayout()
spectral_scalar(grid) = ScalarFieldSpectral(
  zeros(ComplexF64, GBGPeriodicFields.Fields.spectral_field_shape(grid, CONTRACT_LAYOUT, Val(0))),
  grid, CONTRACT_LAYOUT)


@testset "context: same shape, different domain is rejected" begin
  # Two grids of IDENTICAL shape and different extent. Everything built from them has the same
  # storage, so nothing structural distinguishes them — only the context does.
  near = Grid3D((8, 6, 4), (2π, 2π, 2π))
  far = Grid3D((8, 6, 4), (4π, 4π, 4π))
  s_near, s_far = spectral_scalar(near), spectral_scalar(far)
  m_near, m_far = FieldSpectralMultipliers(s_near), FieldSpectralMultipliers(s_far)

  # translation_kernel! (audit CODE-16): rewriting a kernel from foreign multipliers installed the
  # wrong physical phase, and every later application then succeeded.
  kernel = translation_kernel(s_near, m_near, (0.1, 0.2, 0.3))
  @test translation_kernel!(kernel, m_near, (0.2, 0.3, 0.4)) === kernel     # the legal call still works
  @test_throws ArgumentError translation_kernel!(kernel, m_far, (0.2, 0.3, 0.4))

  # A NUFFT plan (audit CODE-04): a same-order field on another domain used to receive this plan's
  # index maps and deconvolution.
  plan = NUFFT(s_near)
  points = PointSet(rand(16, 3) .* 2π)
  out = ScalarPointValues(zeros(16))
  @test interpolate!(out, s_near, points, plan) === out
  @test_throws ArgumentError interpolate!(out, s_far, points, plan)
  @test_throws ArgumentError anterpolate!(s_far, points, out, plan)

  # Radial composition (audit CODE-02) may collapse only when both operands evaluate their symbol
  # against the same coordinates; a shared grid and layout does not establish that.
  band_a = spectral_band(s_near, m_near, 1, 3)
  band_b = spectral_band(s_near, m_near, 0, 2)
  @test convolve(band_a, band_b) isa RadialKernel                      # identical multiplier object
  other = FieldSpectralMultipliers(s_near)                             # equal values, different object
  @test convolve(band_a, spectral_band(s_near, other, 0, 2)) isa ProductKernel
  # ... and the retained form must agree with the collapsed one where the coordinates do agree.
  u = VectorFieldSpectral(randn(ComplexF64,
        GBGPeriodicFields.Fields.spectral_field_shape(near, CONTRACT_LAYOUT, Val(1))), near, CONTRACT_LAYOUT)
  @test field_data(convolve(u, convolve(band_a, band_b))) ==
        field_data(convolve(u, convolve(band_a, spectral_band(s_near, other, 0, 2))))
  @test_throws ArgumentError convolve(band_a, spectral_band(s_far, m_far, 0, 2))
end


@testset "numeric domains: an invalid parameter is rejected, not reinterpreted" begin
  # Grid3D (audit CODE-17): a non-finite or non-positive extent propagated into every wavenumber.
  @test_throws ArgumentError Grid3D((4, 4, 4), (-2π, 2π, 2π))
  @test_throws ArgumentError Grid3D((4, 4, 4), (0.0, 2π, 2π))
  @test_throws ArgumentError Grid3D((4, 4, 4), (Inf, 2π, 2π))
  @test_throws ArgumentError Grid3D((4, 4, 4), (NaN, 2π, 2π))
  @test_throws ArgumentError Grid3D((4, 4, 4), (2π, 2π, 2π); origin = (NaN, 0.0, 0.0))
  @test Grid3D((4, 4, 4), (2π, 2π, 2π)) isa Grid3D                     # the legal grid is untouched

  # Band edges (audit CODE-17): a negative cutoff was silently read as its absolute value, and a
  # reversed pair produced an empty kernel that filtered everything away without complaint.
  s = spectral_scalar(Grid3D((8, 6, 4), (2π, 2π, 2π)))
  m = FieldSpectralMultipliers(s)
  @test_throws ArgumentError spectral_cutoff(s, m, -2)
  @test_throws ArgumentError spectral_band(s, m, 3, 1)
  @test_throws ArgumentError spectral_band(s, m, -1, 3)
  @test_throws ArgumentError spectral_band(s, m, 1, Inf)
  @test spectral_band(s, m, 1, 3) isa RadialKernel
  @test spectral_cutoff(s, m, 2) isa RadialKernel

  # lpnorm (audit CODE-10): outside 1 <= p <= Inf the formula still evaluated — p = 0 returned
  # exactly 1 for every input, and p = -Inf returned a maximum.
  u = VectorFieldPhysical(rand(4, 4, 4, 3), Grid3D((4, 4, 4), (2π, 2π, 2π)))
  for bad in (-Inf, -1, 0, 0.5, NaN)
    @test_throws ArgumentError lpnorm(u, bad)
  end
  @test lpnorm(u, 1) > 0
  @test lpnorm(u, Inf) > 0
  @test lpnorm(u, 2) ≈ l2norm(u)

  # The threading cutoff (audit CODE-14): at zero an empty destination counted as threadable and the
  # partitioner formed a zero-step range.
  previous = threading_cutoff()
  @test_throws ArgumentError set_threading_cutoff!(0)
  @test_throws ArgumentError set_threading_cutoff!(-5)
  @test set_threading_cutoff!(1) == 1
  set_threading_cutoff!(previous)
  @test threading_cutoff() == previous
end


@testset "constructor invariants: the type taxonomy is real" begin
  # TensorPointValues (audit CODE-13): orders 0 and 1 constructed happily, so two concrete types could
  # represent one tensor order and the documented partition was false.
  @test_throws ArgumentError TensorPointValues{0}(rand(5))
  @test_throws ArgumentError TensorPointValues{1}(rand(5, 3))
  @test TensorPointValues{2}(rand(5, 3, 3)) isa TensorPointValues
  @test TensorPointValues{3}(rand(5, 3, 3, 3)) isa TensorPointValues
  @test ScalarPointValues(rand(5)) isa ScalarPointValues
  @test VectorPointValues(rand(5, 3)) isa VectorPointValues
end


@testset "transfer colocation: one launch, one precision and one storage family" begin
  # audit CODE-05: a transfer selects its backend from the field and hands the point and value arrays
  # to that one kernel, so a mixed pair used to fail inside the locator or the launch.
  grid = Grid3D((8, 8, 8), (2π, 2π, 2π))
  field = ScalarFieldPhysical(rand(8, 8, 8), grid)
  points64 = PointSet(rand(16, 3) .* 2π)
  points32 = PointSet(Float32.(rand(16, 3) .* 2π))
  out64 = ScalarPointValues(zeros(16))
  out32 = ScalarPointValues(zeros(Float32, 16))
  @test interpolate!(out64, field, points64) === out64
  @test_throws ArgumentError interpolate!(out64, field, points32)
  @test_throws ArgumentError interpolate!(out32, field, points64)
  @test_throws ArgumentError anterpolate!(field, points32, out64)
  @test_throws ArgumentError anterpolate!(field, points64, out32)
end


@testset "kernel inversion has an explicit zero policy" begin
  # audit CODE-12: a mixed compressed/stored product is legal to construct and was not legal to
  # invert. And a kernel that annihilates a mode has no inverse — that must be said, not returned as
  # a non-finite coefficient that poisons every later result.
  s = spectral_scalar(Grid3D((8, 6, 4), (2π, 2π, 2π)))
  m = FieldSpectralMultipliers(s)
  separable = translation_kernel(s, m, (0.1, 0.2, 0.3))
  stored = materialize_kernel(separable)
  @test inv(convolve(separable, stored)) isa ProductKernel
  @test inv(stored) isa ScalarFieldSpectral

  # The reciprocal really deconvolves.
  u = VectorFieldSpectral(randn(ComplexF64,
        GBGPeriodicFields.Fields.spectral_field_shape(field_grid(s), CONTRACT_LAYOUT, Val(1))),
        field_grid(s), CONTRACT_LAYOUT)
  @test isapprox(field_data(convolve(convolve(u, separable), inv(separable))), field_data(u); rtol = 1e-12)

  # A sharp cutoff is exactly the kernel with zeros, so it is exactly the one with no inverse.
  @test_throws ArgumentError inv(materialize_kernel(spectral_cutoff(s, m, 2)))
end


# The tensor-order ceiling is R < 3, stated in the umbrella docstring and recorded as decision 56.
# Orders 0, 1 and 2 are the supported surface; higher orders are constructible and partially served,
# because the field and point-value types are parameterized on R and several layers are order-generic.
#
# This lane pins the ACTUAL support matrix at R = 3, and its point is not the list but the property:
# every entry point either produces a correct result or throws. Nothing above the ceiling may return a
# WRONG answer, which is what makes documenting the ceiling sufficient and constructor rejection
# unnecessary (it would also break the R = 3 paths that legitimately work). Should an operation ever
# start returning a plausible wrong value here, this testset is what notices.
@testset "the R < 3 ceiling: above it, operations work or throw — never silently wrong" begin
  grid = Grid3D((4, 4, 4), (2π, 2π, 2π))
  data = rand(4, 4, 4, 3, 3, 3)
  third = TensorFieldPhysical{3}(data, grid)

  # SERVED at R = 3, with the result checked rather than merely observed not to throw.
  @test field_tensor_order(third) == 3
  @test inner(third, third) ≈ sum(abs2, data) / 64
  @test l2norm(third) ≈ sqrt(sum(abs2, data) / 64)
  scaled = similar_field(third, Val(3))
  multiply!(scaled, third, 2.0)
  @test field_data(scaled) ≈ 2 .* data
  summed = similar_field(third, Val(3))
  add!(summed, third, third)
  @test field_data(summed) ≈ 2 .* data

  # NOT served at R = 3 — each throws, which is the contract. A future release may serve any of these;
  # what may not happen is one of them returning a number.
  @test_throws ArgumentError integral(third)                # extensive: fiber-preserving, so R<=2
  @test_throws ArgumentError mean(third)                    # fiber-preserving: no R>2 fiber assembly
  @test_throws ArgumentError mean(norm, third)              # mapped: same assembly
  @test_throws MethodError map(x -> 2x, third)              # arbitrary fiber map
  @test_throws MethodError sym!(similar_field(third, Val(3)), third)

  # The point layer agrees with the field layer on where the ceiling falls.
  values = TensorPointValues{3}(rand(6, 3, 3, 3))
  @test pointvalue_tensor_order(values) == 3
  @test inner(values, values) > 0
  @test_throws ArgumentError mean(values)
end
