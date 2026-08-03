# Metadata propagation — a generated sweep (decision 53, guard 4).
#
# WHY THIS FILE EXISTS. A field carries a grid, a spectral layout, an element type and a tensor
# order. Every operation that ALLOCATES its result must propagate all four, and the failure mode is
# silent: the result comes back on the default layout, and the next call throws "field Fourier
# layouts must be equal" somewhere else entirely. That shipped once (`map`, decision 48, fixed in
# fad1456b) and the mutation audit then found four more unguarded allocators, including
# `materialize_kernel` — written two commits AFTER that fix, reproducing it exactly.
#
# WHY THE EXISTING LANES MISS IT. The decision-41 permuted-layout lane is a hand-maintained set of
# call sites, so it covers what someone remembered; and `docs/TESTING.md` §4 reads "tensor order R"
# as *vary R*, never as *vary one argument's R independently of another's* — every fixture in the
# suite builds its field, its point-values and its plan from a single R, so the whole sweep runs
# down the diagonal of a cube and the bugs live off it.
#
# WHAT THIS DOES. Runs every field-producing operation under several folds and asserts the result's
# layout and grid, and — where an operation has more than one order-carrying argument — varies those
# slots INDEPENDENTLY. The oracle is free: no numerics, only metadata, so the sweep costs nothing
# per case and needs no hand-written expectation.

using Test
using GBGPeriodicFields
using GBGPeriodicFields: field_data
using Random: MersenneTwister

const FOLDS = ((1, 2, 3), (2, 1, 3), (3, 2, 1), (1, 3, 2))

@testset "metadata propagation sweep" begin
  for TP in (Float64, Float32), fold in FOLDS
    @testset "$TP fold=$fold" begin
      gs = (8, 6, 4)
      g = Grid3D(gs, (TP(2π), TP(4π), TP(6π)); origin = (TP(0.3), TP(-0.7), TP(1.1)))
      layout = RealFourierLayout(fold)
      rng = MersenneTwister(53)
      spec(R) = (shape = spectral_field_shape(g, layout, Val(R));
                 data = rand(rng, Complex{TP}, shape...);
                 R == 0 ? ScalarFieldSpectral(data, g, layout) :
                 R == 1 ? VectorFieldSpectral(data, g, layout) : TensorFieldSpectral(data, g, layout))
      phys(R) = (shape = physical_field_shape(g, Val(R));
                 data = rand(rng, TP, shape...);
                 R == 0 ? ScalarFieldPhysical(data, g, layout) :
                 R == 1 ? VectorFieldPhysical(data, g, layout) : TensorFieldPhysical(data, g, layout))

      s0, u0, A0 = spec(0), spec(1), spec(2)
      sp, up, Ap = phys(0), phys(1), phys(2)
      m = FieldSpectralMultipliers(s0)
      sep = translation_kernel(s0, m, (TP(0.3), TP(-0.7), TP(1.1)))
      rad = spectral_cutoff(s0, m, TP(3))

      # (name, produces a field, expected tensor order). The oracle is metadata alone.
      cases = [
        ("similar_field R=0",        () -> GBGPeriodicFields.Fields.similar_field(u0, Val(0)), 0),
        ("similar_field R=1",        () -> GBGPeriodicFields.Fields.similar_field(s0, Val(1)), 1),
        ("similar_field R=2",        () -> GBGPeriodicFields.Fields.similar_field(s0, Val(2)), 2),
        ("similar_field physical",   () -> GBGPeriodicFields.Fields.similar_field(up, Val(1)), 1),
        ("gradient",                 () -> gradient(s0, m),                     1),
        ("gradient vector",          () -> gradient(u0, m),                     2),
        ("divergence vector",        () -> divergence(u0, m),                   0),
        ("divergence tensor",        () -> divergence(A0, m),                   1),
        ("curl",                     () -> curl(u0, m),                         1),
        ("laplacian",                () -> laplacian(u0, m),                    1),
        ("inverse_laplacian",        () -> inverse_laplacian(u0, m),            1),
        ("helmholtz_projection",     () -> helmholtz_projection(u0, m),         1),
        ("symmetric_gradient",       () -> symmetric_gradient(u0, m),           2),
        ("convolve ∘ separable",     () -> convolve(u0, sep),                   1),
        ("convolve ∘ radial",        () -> convolve(u0, rad),                   1),
        ("convolve ∘ product",       () -> convolve(u0, convolve(rad, sep)),    1),
        ("exponential_convolve",     () -> exponential_convolve(u0, m, TP(-0.1)), 1),
        ("materialize_kernel sep",   () -> materialize_kernel(sep),             0),
        ("materialize_kernel rad",   () -> materialize_kernel(rad),             0),
        ("squared_wavenumber_field", () -> squared_wavenumber_field(s0, m),     0),
        ("assignment_window",        () -> materialize_kernel(assignment_window(s0, m)), 0),
        ("map tensor→scalar",        () -> map(det, Ap),                        0),
        ("map vector→tensor",        () -> map(x -> x * transpose(x), up),      2),
        ("map order-preserving",     () -> map(x -> 2x, up),                    1),
        ("add!",                     () -> up + up,                             1),
        ("cross",                    () -> cross(up, up),                       1),
        ("dot",                      () -> dot(up, up),                         0),
        ("sym",                      () -> sym(Ap),                             2),
        ("norm",                     () -> norm(up),                            0),
        ("scalar × vector",          () -> sp * up,                             1),
      ]
      for (name, build, expected_order) in cases
        # A `StoredKernel` carries its metadata in the field it wraps: `materialize_kernel` returns the
        # stored KERNEL class, since a field in spectral representation is not a kernel and the role has
        # to be declared by a type. The metadata question is the same one either way, asked of the field
        # inside.
        result = build()
        result = result isa GBGPeriodicFields.Convolution.StoredKernel ? result.field : result
        @test field_layout(result).fft_dims == fold          # the layout survives
        @test field_grid(result) == g                        # so do the grid and its origin
        @test field_tensor_order(result) == expected_order   # and the order is the operation's
        @test field_scalar_type(result) === TP               # and the element type
      end

      # INDEPENDENT SLOTS. Where an operation takes more than one order-carrying argument, the
      # suite's habit is to build them all from one R — the diagonal. These vary them apart, which
      # is the sampling that would have exposed the NUFFT plan-order bug (decision 52, L1).
      @testset "independent argument slots" begin
        points = PointSet(TP(2π) .* rand(rng, TP, 6, 3))
        for (field_order, value_order) in ((0, 0), (1, 1), (2, 2))
          q = value_order == 0 ? ScalarPointValues(rand(rng, TP, 6)) :
              value_order == 1 ? VectorPointValues(rand(rng, TP, 6, 3)) :
                                 TensorPointValues(rand(rng, TP, 6, 3, 3))
          deposited = anterpolate(spec(field_order), points, q, DirectDFT())
          @test field_tensor_order(deposited) == value_order   # the VALUES' order, not the field's
          @test field_layout(deposited).fft_dims == fold
        end
        # a mismatched pair must be refused, not silently mis-sized
        @test_throws ArgumentError anterpolate(spec(0), points,
                                               VectorPointValues(rand(rng, TP, 6, 3)),
                                               NUFFT(spec(0); tol = TP === Float64 ? 1e-8 : 1.0f-4))
      end
    end
  end
end
