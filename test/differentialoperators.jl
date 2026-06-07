# Tests for src/DifferentialOperators.jl: the spectral differential operators,
# verified by analytic round-trips (physical -> spectral -> operator -> physical)
# using the Fields convenience constructor FieldSpectralMultipliers(field).

using Test
using GBGPeriodicFields

const T = Float64
const gs = (8, 8, 8)
const grid = Grid3D(gs, (2π, 2π, 2π))
const layout = RealFourierLayout()
const F = GBGPeriodicFields.Fields

comp(data, i) = data[:, :, :, i]
tcomp(data, i, j) = data[:, :, :, i, j]
scalar_field(f) = ScalarFieldPhysical(f, grid)

# Forward+inverse plans matching the tensor order of `physical`.
function plans_for(physical)
  R = field_tensor_order(physical)
  shape = F.spectral_field_shape(grid, layout, Val(R))
  spectral = R == 0 ? ScalarFieldSpectral(zeros(Complex{T}, shape), grid) :
             R == 1 ? VectorFieldSpectral(zeros(Complex{T}, shape), grid) :
                      TensorFieldSpectral{R}(zeros(Complex{T}, shape), grid)
  return FieldTransformPlans(physical, spectral)
end

zero_vector() = VectorFieldPhysical(zeros(T, gs..., 3), grid)
zero_tensor() = TensorFieldPhysical{2}(zeros(T, gs..., 3, 3), grid)

@testset "DifferentialOperators.jl" begin

  @testset "gradient (scalar -> vector)" begin
    phi = scalar_field((x, y, z) -> sin(x))
    m = FieldSpectralMultipliers(to_spectral(phi, plans_for(phi)))
    g = to_physical(gradient(to_spectral(phi, plans_for(phi)), m), plans_for(zero_vector()))
    @test comp(field_data(g), 1) ≈ field_data(scalar_field((x, y, z) -> cos(x)))   # ∂ₓ sin x = cos x
    @test maximum(abs, comp(field_data(g), 2)) < 1e-12
    @test maximum(abs, comp(field_data(g), 3)) < 1e-12
  end

  @testset "gradient (vector -> tensor): (∇u)ᵢⱼ = ∂ⱼuᵢ" begin
    u = VectorFieldPhysical((x, y, z) -> (sin(x), sin(y), sin(z)), grid)
    m = FieldSpectralMultipliers(to_spectral(u, plans_for(u)))
    G = to_physical(gradient(to_spectral(u, plans_for(u)), m), plans_for(zero_tensor()))
    @test tcomp(field_data(G), 1, 1) ≈ field_data(scalar_field((x, y, z) -> cos(x)))
    @test tcomp(field_data(G), 2, 2) ≈ field_data(scalar_field((x, y, z) -> cos(y)))
    @test tcomp(field_data(G), 3, 3) ≈ field_data(scalar_field((x, y, z) -> cos(z)))
    @test maximum(abs, tcomp(field_data(G), 1, 2)) < 1e-12
  end

  @testset "divergence (vector -> scalar)" begin
    u = VectorFieldPhysical((x, y, z) -> (sin(x), sin(y), sin(z)), grid)
    m = FieldSpectralMultipliers(to_spectral(u, plans_for(u)))
    d = to_physical(divergence(to_spectral(u, plans_for(u)), m), plans_for(scalar_field((x, y, z) -> 0.0)))
    @test field_data(d) ≈ field_data(scalar_field((x, y, z) -> cos(x) + cos(y) + cos(z)))
  end

  @testset "curl" begin
    u = VectorFieldPhysical((x, y, z) -> (0.0, 0.0, sin(x)), grid)   # ∇ × u = (0, -cos x, 0)
    m = FieldSpectralMultipliers(to_spectral(u, plans_for(u)))
    c = to_physical(curl(to_spectral(u, plans_for(u)), m), plans_for(zero_vector()))
    @test maximum(abs, comp(field_data(c), 1)) < 1e-12
    @test comp(field_data(c), 2) ≈ field_data(scalar_field((x, y, z) -> -cos(x)))
    @test maximum(abs, comp(field_data(c), 3)) < 1e-12
  end

  @testset "laplacian: Δ sin(x) = -sin(x)" begin
    phi = scalar_field((x, y, z) -> sin(x))
    m = FieldSpectralMultipliers(to_spectral(phi, plans_for(phi)))
    lap = to_physical(laplacian(to_spectral(phi, plans_for(phi)), m), plans_for(phi))
    @test field_data(lap) ≈ .-field_data(phi)
  end

  @testset "inverse_laplacian inverts laplacian on a zero-mean field" begin
    phi = scalar_field((x, y, z) -> sin(x) * cos(y))
    m = FieldSpectralMultipliers(to_spectral(phi, plans_for(phi)))
    lap_spec = laplacian(to_spectral(phi, plans_for(phi)), m)
    recovered = to_physical(inverse_laplacian(lap_spec, m), plans_for(phi))
    @test field_data(recovered) ≈ field_data(phi)
  end

  @testset "helmholtz projection yields a divergence-free field" begin
    u = VectorFieldPhysical((x, y, z) -> (sin(x), sin(y), 0.0), grid)   # ∇·u = cos x + cos y ≠ 0
    m = FieldSpectralMultipliers(to_spectral(u, plans_for(u)))
    projected = helmholtz_projection(to_spectral(u, plans_for(u)), m)
    div_after = to_physical(divergence(projected, m), plans_for(scalar_field((x, y, z) -> 0.0)))
    @test maximum(abs, field_data(div_after)) < 1e-12
  end

end
