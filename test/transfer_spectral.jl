# Behaviour tests for the spectral-domain transfer schemes (Interpolation module): the exact
# DirectDFT (interpolate = the O(NM) inverse DFT, anterpolate = the forward DFT). Validated against
# the package's own exact transforms (to_physical/to_spectral at the grid nodes), analytic
# closed-form fields off-grid (exact reconstruction — the divergence-free reference property), and
# the adjoint relation M·⟨Wf̂,q⟩ = N·⟨f̂,Wᵀq⟩. DirectDFT is itself the oracle for the fast NUFFT.

using Test
using GBGPeriodicFields                  # re-exports `dot` (acts on the plain value arrays here)
using GBGPeriodicFields: field_data, point_values
using Random: MersenneTwister

@testset "Spectral transfer (DirectDFT)" begin
  for T in (Float64, Float32)
    rtol = T == Float64 ? 1e-11 : 1.0f-3
    atol = T == Float64 ? 1e-11 : 1.0f-3
    layout = RealFourierLayout()
    grid = Grid3D((8, 8, 8), (T(2π), T(2π), T(2π)))

    # Build the spectral representation of a physical sampling, plus its plans.
    tospec(phys) = (R = field_tensor_order(phys);
                    shape = spectral_field_shape(grid, layout, Val(R));
                    spec0 = R == 0 ? ScalarFieldSpectral(zeros(Complex{T}, shape), grid) :
                            R == 1 ? VectorFieldSpectral(zeros(Complex{T}, shape), grid) :
                                     TensorFieldSpectral{R}(zeros(Complex{T}, shape), grid);
                    plans = FieldTransformPlans(phys, spec0);
                    (to_spectral(phys, plans), plans))

    rng = MersenneTwister(2024)
    P = T.([0.37 1.11 2.93; 1.7 0.2 5.0; 4.4 3.3 2.2; 0.05 6.0 0.5; 2.0 2.0 2.0])
    points = PointSet(P)

    # All grid nodes, in column-major (x-fastest) order so the flattened point values align with
    # the flattened field data.
    node_coordinates = zeros(T, 512, 3)
    let n = 0
      for kz in 0:7, ky in 0:7, kx in 0:7
        n += 1
        node_coordinates[n, 1] = T(2π) * kx / 8
        node_coordinates[n, 2] = T(2π) * ky / 8
        node_coordinates[n, 3] = T(2π) * kz / 8
      end
    end
    nodes = PointSet(node_coordinates)

    @testset "interpolate == to_physical at the grid nodes ($T)" begin
      for phys in (ScalarFieldPhysical((x, y, z) -> cos(2x) + T(3) / 10, grid),
                   VectorFieldPhysical((x, y, z) -> (sin(y), cos(z), sin(x)), grid))
        fh, plans = tospec(phys)
        at_nodes = interpolate(fh, nodes, DirectDFT())
        back = to_physical(fh, plans)
        @test isapprox(vec(Array(point_values(at_nodes))), vec(Array(field_data(back))); rtol = rtol, atol = atol)
      end
    end

    @testset "interpolate reproduces the band-limited field exactly off-grid ($T)" begin
      # Exact reconstruction (to round-off) is the divergence-free-reference property the local
      # splines lack: DirectDFT evaluates the true band-limited field.
      analytic(x, y, z) = cos(2x) + T(1) / 2 * sin(y) * cos(3z) + T(3) / 10
      fh, _ = tospec(ScalarFieldPhysical(analytic, grid))
      got = Array(point_values(interpolate(fh, points, DirectDFT())))
      want = T[analytic(P[r, 1], P[r, 2], P[r, 3]) for r in 1:size(P, 1)]
      @test isapprox(got, want; rtol = rtol, atol = atol)
      # a solenoidal vector field stays exact componentwise
      solenoidal(x, y, z) = (sin(y) + cos(z), sin(z) + cos(2x), sin(2x) + cos(y))   # ∇· = 0
      uh, _ = tospec(VectorFieldPhysical(solenoidal, grid))
      got_u = Array(point_values(interpolate(uh, points, DirectDFT())))
      want_u = reduce(vcat, [reshape(collect(T, solenoidal(P[r, 1], P[r, 2], P[r, 3])), 1, 3) for r in 1:size(P, 1)])
      @test isapprox(got_u, want_u; rtol = rtol, atol = atol)
    end

    @testset "anterpolate == to_spectral from node samples ($T)" begin
      analytic(x, y, z) = cos(x) + sin(2y)
      phys = ScalarFieldPhysical(analytic, grid)
      fh, _ = tospec(phys)
      node_values = T[analytic(node_coordinates[n, 1], node_coordinates[n, 2], node_coordinates[n, 3]) for n in 1:512]
      deposited = anterpolate(fh, nodes, ScalarPointValues(node_values), DirectDFT())
      @test isapprox(Array(field_data(deposited)), Array(field_data(fh)); rtol = rtol, atol = atol)
    end

    @testset "adjointness M·⟨Wf̂,q⟩ = N·⟨f̂,Wᵀq⟩ ($T)" begin
      for R in (0, 1, 2)
        phys = R == 0 ? ScalarFieldPhysical(randn(rng, T, 8, 8, 8), grid) :
               R == 1 ? VectorFieldPhysical(randn(rng, T, 8, 8, 8, 3), grid) :
                        TensorFieldPhysical{2}(randn(rng, T, 8, 8, 8, 3, 3), grid)
        fh, _ = tospec(phys)
        q = R == 0 ? ScalarPointValues(randn(rng, T, 5)) :
            R == 1 ? VectorPointValues(randn(rng, T, 5, 3)) :
                     TensorPointValues{2}(randn(rng, T, 5, 3, 3))
        gathered = interpolate(fh, points, DirectDFT())
        deposited = anterpolate(fh, points, q, DirectDFT())
        left = dot(vec(Array(point_values(gathered))), vec(Array(point_values(q))))   # = M·inner_pts (raw Σ)
        right = prod(grid.grid_size) * inner(fh, deposited)
        @test isapprox(left, right; rtol = rtol, atol = atol)
      end
    end

    @testset "α/β accumulate + intentional absences ($T)" begin
      phys = ScalarFieldPhysical(randn(rng, T, 8, 8, 8), grid)
      fh, _ = tospec(phys)
      q = ScalarPointValues(randn(rng, T, 5))
      once = anterpolate(fh, points, q, DirectDFT())
      twice = ScalarFieldSpectral(copy(field_data(once)), grid)
      anterpolate!(twice, points, q, DirectDFT(), T(1), T(1))          # accumulate onto an existing deposit
      @test isapprox(Array(field_data(twice)), 2 .* Array(field_data(once)); rtol = rtol, atol = atol)
      # spectral schemes act on the spectral representation: no physical-field method
      @test_throws MethodError interpolate(phys, points, DirectDFT())
    end
  end
end
