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

@testset "Spectral transfer (NUFFT)" begin
  for T in (Float64, Float32)
    tol = T == Float64 ? 1e-10 : 1.0f-4
    atol = T == Float64 ? 1e-8 : 1.0f-3
    layout = RealFourierLayout()
    grid = Grid3D((16, 16, 16), (T(2π), T(2π), T(2π)))   # oversampled 32³ ≥ stencil width

    tospec(phys) = (R = field_tensor_order(phys);
                    shape = spectral_field_shape(grid, layout, Val(R));
                    spec0 = R == 0 ? ScalarFieldSpectral(zeros(Complex{T}, shape), grid) :
                                     VectorFieldSpectral(zeros(Complex{T}, shape), grid);
                    plans = FieldTransformPlans(phys, spec0);
                    (to_spectral(phys, plans), plans))

    rng = MersenneTwister(99)
    P = T.(rand(rng, 8, 3) .* 2π)
    points = PointSet(P)

    # band-limited well below the Nyquist (= the resolved band the gridding NUFFT is exact on)
    scalar(x, y, z) = cos(2x) + T(1) / 2 * sin(y) * cos(3z) + T(3) / 10
    vector(x, y, z) = (sin(y) + cos(2z), sin(2x) + cos(z), sin(x) + cos(2y))

    @testset "NUFFT == DirectDFT (the oracle) to tol ($T)" begin
      for phys in (ScalarFieldPhysical(scalar, grid), VectorFieldPhysical(vector, grid))
        fh, plans = tospec(phys)
        nufft = NUFFT(fh; tol = tol)
        fast = Array(point_values(interpolate(fh, points, nufft)))
        oracle = Array(point_values(interpolate(fh, points, DirectDFT())))
        @test isapprox(fast, oracle; rtol = atol, atol = atol)
        # …hence exact reconstruction of the band-limited field, and == to_physical at the nodes
        if field_tensor_order(phys) == 0
          want = T[scalar(P[r, 1], P[r, 2], P[r, 3]) for r in 1:size(P, 1)]
          @test isapprox(vec(fast), want; rtol = atol, atol = atol)
        end
      end
    end

    @testset "NUFFT adjoint pair M·⟨Wf̂,q⟩ = N·⟨f̂,Wᵀq⟩ ($T)" begin
      for (phys, q) in ((ScalarFieldPhysical(scalar, grid), ScalarPointValues(randn(rng, T, 8))),
                        (VectorFieldPhysical(vector, grid), VectorPointValues(randn(rng, T, 8, 3))))
        fh, _ = tospec(phys)
        nufft = NUFFT(fh; tol = tol)
        gathered = interpolate(fh, points, nufft)
        deposited = anterpolate(fh, points, q, nufft)
        left = sum(vec(Array(point_values(gathered))) .* vec(Array(point_values(q))))   # = M·inner_pts
        right = prod(grid.grid_size) * inner(fh, deposited)
        @test isapprox(left, right; rtol = atol, atol = atol)
      end
    end

    @testset "NUFFT α/β accumulate + tunable width ($T)" begin
      phys = ScalarFieldPhysical(scalar, grid); fh, _ = tospec(phys)
      nufft = NUFFT(fh; width = 8, beta = 18)            # explicit ES parameters
      q = ScalarPointValues(randn(rng, T, 8))
      once = anterpolate(fh, points, q, nufft)
      twice = ScalarFieldSpectral(copy(field_data(once)), grid)
      anterpolate!(twice, points, q, nufft, T(1), T(1))
      @test isapprox(Array(field_data(twice)), 2 .* Array(field_data(once)); rtol = atol, atol = atol)
    end
  end
end


@testset "permuted rfft layout: spectral transfer ($TP)" for TP in (Float64, Float32)
  grid_p = Grid3D((8, 6, 4), (TP(2π), TP(2π), TP(2π)))
  layout_p = RealFourierLayout((2, 1, 3))                     # fold on spatial axis 2
  xs = [(i - 1) * TP(2π) / 8 for i in 1:8]
  ys = [(j - 1) * TP(2π) / 6 for j in 1:6]
  zs = [(l - 1) * TP(2π) / 4 for l in 1:4]
  phys = ScalarFieldPhysical(rand(TP, 8, 6, 4), grid_p, layout_p)
  scaffold = ScalarFieldSpectral(zeros(Complex{TP}, spectral_field_shape(grid_p, layout_p, Val(0))),
                                 grid_p, layout_p)
  plans = FieldTransformPlans(phys, scaffold)
  fh = to_spectral(phys, plans)

  # DirectDFT at the nodes == to_physical, Nyquist content included (exact at the sample points)
  node_coordinates = Matrix{TP}(undef, 8 * 6 * 4, 3)
  n = 0
  for l in 1:4, j in 1:6, i in 1:8                            # x fastest ⇒ vec (column-major) order
    n += 1
    node_coordinates[n, 1] = xs[i]
    node_coordinates[n, 2] = ys[j]
    node_coordinates[n, 3] = zs[l]
  end
  nodes = PointSet(node_coordinates)
  at_nodes = interpolate(fh, nodes, DirectDFT())
  tol_nodes = TP === Float64 ? 1e-11 : 1e-4
  @test isapprox(vec(Array(point_values(at_nodes))), vec(Array(field_data(to_physical(fh, plans))));
                 rtol = tol_nodes, atol = tol_nodes)

  # NUFFT vs its DirectDFT oracle off-grid, on a band-limited field under the permuted fold
  band = ScalarFieldPhysical([sin(xs[i]) * cos(ys[j]) + TP(3) / 10 for i in 1:8, j in 1:6, l in 1:4],
                             grid_p, layout_p)
  bh = to_spectral(band, plans)
  rng = MersenneTwister(7)
  points = PointSet(TP(2π) .* rand(rng, TP, 40, 3))
  tol = TP === Float64 ? TP(1e-8) : TP(1e-4)
  exact = Array(point_values(interpolate(bh, points, DirectDFT())))
  fast = Array(point_values(interpolate(bh, points, NUFFT(bh; tol = tol))))
  @test isapprox(fast, exact; rtol = 50 * tol, atol = 50 * tol)
end


@testset "non-zero origin: spectral transfer ($TP)" for TP in (Float64, Float32)
  origin = (TP(0.4), TP(-0.7), TP(1.1))
  grid_o = Grid3D((8, 6, 4), (TP(2π), TP(4π), TP(6π)); origin = origin)
  layout_o = RealFourierLayout()
  spacing = grid_o.grid_spacing
  fundamental = ntuple(a -> TP(2π) / grid_o.domain_size[a], 3)
  tol = TP === Float64 ? 1e-11 : 1e-4

  # node match on a random field (Nyquist content included): the DirectDFT phase is anchored
  # at the origin, so the nodes sit at origin + (i-1)Δ — a dropped or sign-flipped origin
  # misplaces every node and fails loudly
  phys = ScalarFieldPhysical(rand(TP, 8, 6, 4), grid_o)
  scaffold = ScalarFieldSpectral(zeros(Complex{TP}, spectral_field_shape(grid_o, layout_o, Val(0))),
                                 grid_o)
  plans = FieldTransformPlans(phys, scaffold)
  fh = to_spectral(phys, plans)
  node_coordinates = Matrix{TP}(undef, 8 * 6 * 4, 3)
  n = 0
  for l in 1:4, j in 1:6, i in 1:8                            # x fastest ⇒ vec (column-major) order
    n += 1
    node_coordinates[n, 1] = origin[1] + (i - 1) * spacing[1]
    node_coordinates[n, 2] = origin[2] + (j - 1) * spacing[2]
    node_coordinates[n, 3] = origin[3] + (l - 1) * spacing[3]
  end
  nodes = PointSet(node_coordinates)
  @test isapprox(vec(Array(point_values(interpolate(fh, nodes, DirectDFT())))),
                 vec(Array(field_data(to_physical(fh, plans)))); rtol = tol, atol = tol)

  # analytic absolute-coordinate oracle: the band-limited closed form must be reproduced at
  # arbitrary absolute positions — a relative-only consistency check cannot catch an origin
  # convention that is wrong the same way on both sides
  band_fn(x, y) = cos(fundamental[1] * x) + sin(fundamental[2] * y)
  band = ScalarFieldPhysical(
    [band_fn(origin[1] + (i - 1) * spacing[1], origin[2] + (j - 1) * spacing[2])
     for i in 1:8, j in 1:6, l in 1:4], grid_o)
  bh = to_spectral(band, plans)
  rng = MersenneTwister(11)
  P = Matrix{TP}(undef, 30, 3)
  for p in 1:30, a in 1:3
    P[p, a] = origin[a] + grid_o.domain_size[a] * rand(rng, TP)
  end
  points = PointSet(P)
  got = Array(point_values(interpolate(bh, points, DirectDFT())))
  expected = [band_fn(P[p, 1], P[p, 2]) for p in 1:30]
  @test isapprox(got, expected; rtol = 20 * tol, atol = 20 * tol)

  # NUFFT locates points relative to the origin too — it must agree with its oracle here
  nufft_tol = TP === Float64 ? TP(1e-8) : TP(1e-4)
  fast = Array(point_values(interpolate(bh, points, NUFFT(bh; tol = nufft_tol))))
  @test isapprox(fast, got; rtol = 50 * nufft_tol, atol = 50 * nufft_tol)

  # the adjoint relation M·⟨Wf̂,q⟩ = N·⟨f̂,Wᵀq⟩ must hold with the phase anchored at the
  # origin on both sides — a one-sided origin error breaks it
  q = ScalarPointValues(rand(MersenneTwister(12), TP, 30))
  left = 30 * inner(interpolate(bh, points, DirectDFT()), q)
  right = 8 * 6 * 4 * inner(bh, anterpolate(bh, points, q, DirectDFT()))
  @test isapprox(left, right; rtol = TP === Float64 ? 1e-10 : 2e-3)
end


@testset "hostile base: odd fold + anisotropic + origin, both verbs, both schemes ($TP)" for TP in (Float64, Float32)
  # Everything at once, detection-optimal: the fold sits on an ODD axis (N = 7 — the spectral
  # schemes' own even/odd Nyquist split had never met a CPU oracle on an odd fold), the lengths
  # are unequal, and the origin is nonzero. Gather AND scatter both get independent oracles.
  origin = (TP(0.4), TP(-0.7), TP(1.1))
  grid_h = Grid3D((8, 7, 6), (TP(2π), TP(4π), TP(6π)); origin = origin)
  layout_h = RealFourierLayout((2, 1, 3))                     # fold on spatial axis 2, N = 7 odd
  spacing = grid_h.grid_spacing
  fundamental = ntuple(a -> TP(2π) / grid_h.domain_size[a], 3)
  tol = TP === Float64 ? 1e-11 : 2e-4

  phys = ScalarFieldPhysical(rand(TP, 8, 7, 6), grid_h, layout_h)
  scaff = ScalarFieldSpectral(zeros(Complex{TP}, spectral_field_shape(grid_h, layout_h, Val(0))),
                              grid_h, layout_h)
  plans = FieldTransformPlans(phys, scaff)
  fh = to_spectral(phys, plans)

  node_coordinates = Matrix{TP}(undef, 8 * 7 * 6, 3)
  n = 0
  for l in 1:6, j in 1:7, i in 1:8                            # x fastest ⇒ vec (column-major) order
    n += 1
    node_coordinates[n, 1] = origin[1] + (i - 1) * spacing[1]
    node_coordinates[n, 2] = origin[2] + (j - 1) * spacing[2]
    node_coordinates[n, 3] = origin[3] + (l - 1) * spacing[3]
  end
  nodes = PointSet(node_coordinates)
  node_values = vec(Array(field_data(to_physical(fh, plans))))
  # gather: DirectDFT at the nodes == to_physical, Nyquist content included
  @test isapprox(vec(Array(point_values(interpolate(fh, nodes, DirectDFT())))), node_values;
                 rtol = tol, atol = tol)
  # scatter: the forward DFT of the node samples IS to_spectral — an independent oracle for
  # anterpolate on the same hostile base
  deposited = anterpolate(fh, nodes, ScalarPointValues(node_values), DirectDFT())
  @test isapprox(field_data(deposited), field_data(fh); rtol = 100 * tol, atol = 100 * tol)

  # band-limited analytic reconstruction off-grid, and genuine out-of-box periodicity (whole
  # periods added per axis — never exercised for the spectral schemes before)
  band_fn(x, y) = cos(fundamental[1] * x) + sin(fundamental[2] * y)
  band = ScalarFieldPhysical(
    [band_fn(origin[1] + (i - 1) * spacing[1], origin[2] + (j - 1) * spacing[2])
     for i in 1:8, j in 1:7, l in 1:6], grid_h, layout_h)
  bh = to_spectral(band, plans)
  rng = MersenneTwister(21)
  P = Matrix{TP}(undef, 20, 3)
  for p in 1:20, a in 1:3
    P[p, a] = origin[a] + grid_h.domain_size[a] * rand(rng, TP)
  end
  points = PointSet(P)
  inside = Array(point_values(interpolate(bh, points, DirectDFT())))
  @test isapprox(inside, [band_fn(P[p, 1], P[p, 2]) for p in 1:20]; rtol = 20 * tol, atol = 20 * tol)
  offsets = reshape(TP[2, -1, 3] .* collect(grid_h.domain_size), 1, 3)
  outside = PointSet(P .+ offsets)
  @test isapprox(Array(point_values(interpolate(bh, outside, DirectDFT()))), inside;
                 rtol = 20 * tol, atol = 20 * tol)

  # NUFFT on the hostile base: gather vs its oracle (incl. a non-default oversampling — σ ≠ 2
  # was never constructed before), out-of-box points, the adjoint relation (pins the scatter
  # with the origin on both sides), and the R = 2 tensor case DirectDFT already covers
  nufft_tol = TP === Float64 ? TP(1e-8) : TP(1e-4)
  fast = NUFFT(bh; tol = nufft_tol)
  @test isapprox(Array(point_values(interpolate(bh, points, fast))), inside;
                 rtol = 50 * nufft_tol, atol = 50 * nufft_tol)
  wide = NUFFT(bh; tol = nufft_tol, oversampling = 3)
  @test isapprox(Array(point_values(interpolate(bh, points, wide))), inside;
                 rtol = 50 * nufft_tol, atol = 50 * nufft_tol)
  # oversampling must be ≥ 2: σ = 1 has no spectral guard band, so the plan build rejects it
  @test_throws ArgumentError NUFFT(bh; tol = nufft_tol, oversampling = 1)
  @test isapprox(Array(point_values(interpolate(bh, outside, fast))), inside;
                 rtol = 50 * nufft_tol, atol = 50 * nufft_tol)
  q = ScalarPointValues(rand(MersenneTwister(22), TP, 20))
  left = 20 * inner(interpolate(bh, points, fast), q)
  right = 8 * 7 * 6 * inner(bh, anterpolate(bh, points, q, fast))
  @test isapprox(left, right; rtol = TP === Float64 ? 1e-6 : 5e-3)

  # α = 0, β ≠ 0 for the spectral-scheme scatters (the pure β-rescale branch)
  dest0 = ScalarFieldSpectral(copy(field_data(bh)), grid_h, layout_h)
  before0 = copy(field_data(dest0))
  anterpolate!(dest0, points, q, DirectDFT(), TP(0), TP(2))
  @test field_data(dest0) == 2 .* before0
  anterpolate!(dest0, points, q, fast, TP(0), TP(2))
  @test field_data(dest0) == 4 .* before0

  # the bang gather called by name, overwriting a dirty (NaN-prefilled) output
  dirty = ScalarPointValues(fill(TP(NaN), 20))
  interpolate!(dirty, bh, points, DirectDFT())
  @test isapprox(Array(point_values(dirty)), inside; rtol = 20 * tol, atol = 20 * tol)

  # R = 2: NUFFT over a tensor field (never constructed before; DirectDFT is the oracle)
  t_phys = TensorFieldPhysical{2}(zeros(TP, 8, 7, 6, 3, 3), grid_h, layout_h)
  for l in 1:6, j in 1:7, i in 1:8
    field_data(t_phys)[i, j, l, :, :] .= band_fn(origin[1] + (i - 1) * spacing[1],
                                                 origin[2] + (j - 1) * spacing[2])
  end
  t_scaff = TensorFieldSpectral{2}(zeros(Complex{TP}, spectral_field_shape(grid_h, layout_h, Val(2))),
                                   grid_h, layout_h)
  plans_t = FieldTransformPlans(t_phys, t_scaff)
  th = to_spectral(t_phys, plans_t)
  exact_t = Array(point_values(interpolate(th, points, DirectDFT())))
  fast_t = Array(point_values(interpolate(th, points, NUFFT(th; tol = nufft_tol))))
  @test isapprox(fast_t, exact_t; rtol = 50 * nufft_tol, atol = 50 * nufft_tol)

  # M = 0: the zero-work launches are sane (probe-verified, decision 43) and stay pinned
  empty_points = PointSet(zeros(TP, 0, 3))
  @test npoints(interpolate(bh, empty_points, DirectDFT())) == 0
  @test npoints(interpolate(bh, empty_points, fast)) == 0
end


# A NUFFT plan's oversampled buffers are sized at the tensor order of the field it was built from. Used
# at a HIGHER order the spread wrote fewer components than the extract read, and the surplus came back
# as uninitialized scratch — NaN and 1e-310, silently, where DirectDFT handled the same call correctly.
# Every fixture in this file builds field and point-values at the SAME order, so the mismatch was never
# reachable (decision 52).
@testset "NUFFT plan order must match the transfer's" begin
  for TP in (Float64, Float32)
    g = Grid3D((8, 8, 8), (TP(2π), TP(2π), TP(2π)))
    layout = RealFourierLayout()
    scalar_reference = ScalarFieldSpectral(zeros(Complex{TP}, spectral_field_shape(g, layout, Val(0))), g, layout)
    vector_reference = VectorFieldSpectral(zeros(Complex{TP}, spectral_field_shape(g, layout, Val(1))), g, layout)
    points = PointSet(TP(2π) .* rand(MersenneTwister(52), TP, 6, 3))
    vector_values = VectorPointValues(rand(MersenneTwister(53), TP, 6, 3))

    scalar_plan = NUFFT(scalar_reference; tol = TP === Float64 ? 1e-8 : 1.0f-4)
    # a plan of lower order than the transfer is refused, not silently wrong
    @test_throws ArgumentError anterpolate(scalar_reference, points, vector_values, scalar_plan)
    @test_throws ArgumentError anterpolate!(vector_reference, points, vector_values, scalar_plan)
    @test_throws ArgumentError interpolate(vector_reference, points, scalar_plan)

    # the matching plan still works and is finite everywhere
    vector_plan = NUFFT(vector_reference; tol = TP === Float64 ? 1e-8 : 1.0f-4)
    deposited = anterpolate(vector_reference, points, vector_values, vector_plan)
    @test all(isfinite, field_data(deposited))
    @test field_tensor_order(deposited) == 1
  end
end


# ── which modes NUFFT projects out ────────────────────────────────────────────────────────────────
#
# Ported from the exhaustive survey, where writing an independent oracle for the spectral evaluation
# forced this contract into the open. NUFFT is exact against DirectDFT only on the RESOLVED SUB-NYQUIST
# band — it projects the Nyquist out so its spread and gather stay exact adjoints — and it does so on
# EVERY EVEN AXIS, not only the folded one. That distinction was measured, not assumed: on an 8³ grid,
# projecting the folded axis alone leaves NUFFT disagreeing with the reference by 0.219, while
# projecting all three brings it to 3.3e-12. Nothing pinned which modes are dropped, so a change to the
# projection would have shifted answers silently.
@testset "NUFFT projects the Nyquist plane on every even axis, not only the folded one" begin
  T = Float64
  layout = RealFourierLayout()
  grid = Grid3D((8, 8, 8), (T(2π), T(2π), T(2π)))
  rng = MersenneTwister(20260802)
  physical = ScalarFieldPhysical(rand(rng, T, 8, 8, 8), grid, layout)
  spectral = to_spectral(physical, FieldTransformPlans(physical,
      ScalarFieldSpectral(zeros(Complex{T},
          GBGPeriodicFields.Fields.spectral_field_shape(grid, layout, Val(0))...), grid, layout)))
  points = PointSet(rand(rng, T, 12, 3) .* T(2π))

  # The same field with the Nyquist plane removed on each even axis: the last stored slot on the folded
  # axis, and `n ÷ 2 + 1` elsewhere, the stored order there running 0, 1, ….
  projected_data = copy(field_data(spectral))
  for axis in 1:3
    n = grid.grid_size[axis]
    iseven(n) || continue
    index = axis == layout.fft_dims[1] ? size(projected_data, axis) : (n ÷ 2 + 1)
    plane = ntuple(d -> d == axis ? (index:index) : Base.axes(projected_data, d),
                   ndims(projected_data))
    projected_data[plane...] .= 0
  end
  projected = ScalarFieldSpectral(projected_data, grid, layout)

  fast = point_values(interpolate(spectral, points, NUFFT(spectral; tol = 1e-10)))
  exact_projected = point_values(interpolate(projected, points, DirectDFT()))
  exact_full = point_values(interpolate(spectral, points, DirectDFT()))

  @test fast ≈ exact_projected atol = 1e-8
  # The discriminator: the projection is not a no-op on this field, so the assertion above genuinely
  # pins WHICH modes are dropped rather than being satisfied by any implementation.
  @test !isapprox(exact_projected, exact_full; atol = 1e-3)
end
