# Static robustness check via JET.jl. `@test_call` asserts that a call has no
# inference-detected possible errors (MethodError, BoundsError, undefined variables) — the
# class of latent bug that doesn't show up until a specific code path runs. `target_modules`
# restricts reports to GBGPeriodicFields' own modules, filtering out Base-internal
# abstract-interpretation false positives (e.g. inside `@sync`).
#
# This is a *per-Julia-version* static check: JET analyzes the running Julia, so it cannot catch
# divergence between Julia versions on its own. With the compat floor at 1.12 (decision 31) the CI
# matrix runs a single version, so that coverage now comes from the floor lane tracking the declared
# minimum rather than from a second, older lane.

using Test
using JET
using GBGPeriodicFields

const M = GBGPeriodicFields
const PACKAGE_MODULES = (M, M.Fields, M.FieldAlgebra, M.DifferentialOperators)

const T = Float64
const grid = Grid3D((8, 7, 6), (2π, 2π, 2π))
const layout = RealFourierLayout()

function plans_for(physical)
  R = field_tensor_order(physical)
  shape = M.Fields.field_spectral_shape(grid, layout, Val(R))
  spectral = R == 0 ? ScalarFieldSpectral(zeros(Complex{T}, shape), grid) :
             R == 1 ? VectorFieldSpectral(zeros(Complex{T}, shape), grid) :
                      TensorFieldSpectral{R}(zeros(Complex{T}, shape), grid)
  return FieldTransformPlans(physical, spectral)
end


@testset "JET static analysis" begin
  a = ScalarFieldPhysical(Array, (x, y, z) -> sin(x), grid)
  b = ScalarFieldPhysical(Array, (x, y, z) -> cos(y), grid)
  sf = ScalarFieldPhysical(Array, (x, y, z) -> 2.0 + sin(x), grid)
  u = VectorFieldPhysical(Array, (x, y, z) -> (sin(x), cos(y), sin(z)), grid)
  v = VectorFieldPhysical(Array, (x, y, z) -> (cos(x), sin(y), 1.0), grid)
  A = TensorFieldPhysical{2}(Array, (x, y, z) -> fill(sin(x), 3, 3), grid)
  as = to_spectral(a, plans_for(a))
  us = to_spectral(u, plans_for(u))
  m = FieldSpectralMultipliers(as)

  # vector-space + scalar-field algebra (routes through the threaded field broadcast)
  @test_call target_modules = PACKAGE_MODULES a + b
  @test_call target_modules = PACKAGE_MODULES 2.5 * a
  @test_call target_modules = PACKAGE_MODULES sf * u
  @test_call target_modules = PACKAGE_MODULES u / sf

  # contractions / products / decompositions (the codegen kernels)
  @test_call target_modules = PACKAGE_MODULES dot(u, v)
  @test_call target_modules = PACKAGE_MODULES cross(u, v)
  @test_call target_modules = PACKAGE_MODULES A * u
  @test_call target_modules = PACKAGE_MODULES A * A
  @test_call target_modules = PACKAGE_MODULES transpose(A)
  @test_call target_modules = PACKAGE_MODULES sym(A)
  @test_call target_modules = PACKAGE_MODULES norm(u)

  # transforms
  @test_call target_modules = PACKAGE_MODULES to_spectral(a, plans_for(a))
  @test_call target_modules = PACKAGE_MODULES to_physical(as, plans_for(a))

  # spectral differential operators
  @test_call target_modules = PACKAGE_MODULES gradient(as, m)
  @test_call target_modules = PACKAGE_MODULES divergence(us, m)
  @test_call target_modules = PACKAGE_MODULES curl(us, m)
  @test_call target_modules = PACKAGE_MODULES laplacian(as, m)
  @test_call target_modules = PACKAGE_MODULES helmholtz_projection(us, m)
end
