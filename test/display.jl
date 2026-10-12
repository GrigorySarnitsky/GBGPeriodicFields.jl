using Test
using GBGPeriodicFields
using GBGPeriodicFields: Fields, FiberSections, FieldAlgebra, DifferentialOperators,
                         Convolution, Points, Interpolation, Reductions

# The display layer exists because a section wraps a field-sized array and the default struct show
# prints that array in full — 5.6 million characters for a `PointSet` of 100000 points, 2.5 million
# for a `NUFFT`. That floods a REPL and, the half that bites harder, it is what an exception
# interpolating the object would carry.
#
# The gate here is the FIRST testset, and it is derived rather than listed: it enumerates every
# concrete struct type the package defines and requires each to have a package-owned `show` or a
# cited exemption. A hand-written list of types would go stale the moment a type is added, which is
# precisely when this check has something to say.

const MODULES = Set(Any[GBGPeriodicFields, Fields, FiberSections, FieldAlgebra,
                        DifferentialOperators, Convolution, Points, Interpolation, Reductions])

# Types that deliberately carry no display, each with the reason. The first is a record whose default
# is already correct; the rest are pass-local callable adapters, built inside one pass and consumed by
# it — none is returned from a public function, stored on a user-visible object, or interpolated into
# an error message, so none can reach a surface a user reads.
const NO_DISPLAY = Dict(
  :RealFourierLayout =>
    "holds one tuple; the default `RealFourierLayout((1, 2, 3))` is 28 characters, unambiguous, " *
    "and round-trips, so a method would only add a second spelling of it",
  :_StoredWeight  => "pass-local weight adapter, built and consumed inside one reduction",
  :_RadialWeight  => "pass-local weight adapter, built and consumed inside one reduction",
  :_LazyWeight    => "pass-local weight adapter, built and consumed inside one reduction",
  :_MapValues     => "pass-local values function, built and consumed inside one `map!` pass",
  :_FiberGather   => "pass-local values function, built and consumed inside one mapped reduction",
  :_RadialOffset  => "pass-local carrier of a radial exponent offset's symbol, built and consumed inside one `exponential_convolve!` pass",
)


"""Every concrete struct type the package defines, keyed by name."""
function package_struct_types()
  found = Dict{Symbol, Any}()
  for m in MODULES, name in names(m; all = true)
    isdefined(m, name) || continue
    object = getfield(m, name)
    object isa Type || continue
    # A parametric type is a `UnionAll`, so asking `isa DataType` of it is false and silently drops
    # most of the package. Unwrap first.
    base = Base.unwrap_unionall(object)
    base isa DataType || continue
    base.name.module in MODULES || continue
    (isabstracttype(base) || isempty(fieldnames(base))) && continue
    startswith(string(nameof(base)), "#") && continue
    found[nameof(base)] = object
  end
  return found
end

has_display(type) = any(m -> m.module in MODULES, methods(Base.show, Tuple{IO, type}))


@testset "display" begin

  @testset "every package struct type displays, or is exempt with a reason" begin
    types = package_struct_types()
    @test length(types) ≥ 20  # a parser that stops matching must fail, not report a clean sweep

    for (name, type) in sort!(collect(types); by = first)
      if haskey(NO_DISPLAY, name)
        @test !has_display(type)  # a stale exemption is a widened blind spot
      else
        @test has_display(type)
      end
    end

    # Both directions: an exemption naming a type the package no longer defines is stale.
    for name in keys(NO_DISPLAY)
      @test haskey(types, name)
    end
  end

  T = Float64
  layout = RealFourierLayout()
  grid = Grid3D((16, 16, 16), (T(2π), T(2π), T(2π)))
  points = PointSet(T(2π) .* rand(T, 500, 3))

  @testset "no display floods" begin
    # The bound is generous: the point is that nothing prints an array, not that any particular
    # wording fits. The largest legitimate line is a `ProductKernel`, which nests its two factors.
    multipliers = FieldSpectralMultipliers(ScalarFieldSpectral(Array, grid; layout))
    samples = Any[
      grid, layout,
      ScalarFieldPhysical(Array, grid; layout), VectorFieldSpectral(Array, grid; layout),
      TensorFieldPhysical{2}(Array, grid; layout),
      points, VectorPointValues(rand(T, 500, 3)),
      point_traversal_order(grid, points), PointTraversalOrderScratch(grid, points),
      multipliers,
      FieldTransformPlans(ScalarFieldPhysical(Array, grid; layout),
                          ScalarFieldSpectral(Array, grid; layout)),
      spectral_cutoff(multipliers, T(4)),
      translation_kernel(multipliers, (T(0.1), T(0.2), T(0.3))),
      materialize_kernel(spectral_cutoff(multipliers, T(4))),
      convolve(spectral_cutoff(multipliers, T(4)),
               translation_kernel(multipliers, (T(0.1), T(0.2), T(0.3)))),
      CatmullRom, LalescuSpline(8; smoothness = 2), LagrangeSpline(6), DirectDFT(),
      NUFFT(ScalarFieldSpectral(Array, grid; layout)),
    ]
    for sample in samples
      @test length(repr(sample)) ≤ 200
      @test !occursin("\n", repr(sample))  # the two-argument form is one line
    end
  end

  @testset "the compact form is self-delimiting" begin
    # It appears inside a container, inside `$(...)` and inside an exception, so a bare `Type: a, b`
    # could not be told from its neighbours once a container puts commas between elements.
    a = ScalarFieldPhysical(Array, grid; layout)
    b = VectorFieldPhysical(Array, grid; layout)
    for sample in (a, b, points, CatmullRom)
      @test occursin(repr(sample), repr([sample, sample]))
    end
    @test endswith(repr(a), ")")
  end

  @testset "objects the package refuses to combine display differently" begin
    # The reason the body carries extent, origin and the fold at all. Without them these five print
    # one string, and an error explaining why two of them will not combine shows the reader the same
    # text twice. Every pair here is rejected by `_check_field_domain_compatibility`.
    variants = [
      ScalarFieldPhysical(Array, grid; layout),
      ScalarFieldPhysical(Array, Grid3D((16, 16, 16), (T(4π), T(2π), T(2π))); layout),
      ScalarFieldPhysical(Array, Grid3D((16, 16, 16), (T(2π), T(2π), T(2π));
                                        origin = (T(-π), T(0), T(0))); layout),
      ScalarFieldPhysical(Array, Grid3D((8, 16, 16), (T(2π), T(2π), T(2π))); layout),
      ScalarFieldPhysical(Array, grid; layout = RealFourierLayout((3, 1, 2))),
    ]
    for i in eachindex(variants), j in eachindex(variants)
      i < j || continue
      # The predicate itself, not a broadcast: a size mismatch is caught by the broadcast machinery
      # as a `DimensionMismatch` before the domain check runs, and it is the domain check this
      # display is written against.
      @test_throws ArgumentError Fields._check_field_domain_compatibility(variants[i], variants[j])
      @test repr(variants[i]) != repr(variants[j])
    end

    # A rounded coordinate would reintroduce the same defect one axis-scale down: the grid check is
    # exact equality, so boxes differing in the sixth digit are refused and must not collide.
    near = ScalarFieldPhysical(Array, Grid3D((16, 16, 16), (T(2π), T(2π), T(2π) + T(1e-9))); layout)
    @test_throws ArgumentError Fields._check_field_domain_compatibility(variants[1], near)
    @test repr(variants[1]) != repr(near)

    # The property is not the fields' alone. Every object bound to a base and refused against another
    # base owes it, and those below were caught by re-reading rather than by this testset, which
    # covered only fields when it was written. A `NUFFT` handed a same-order field on another
    # domain applies this one's index maps and returns a wrong answer, so `_check_matching_context`
    # refuses it; a traversal scratch is refused a rebuild against a grid it was not built for.
    other_grid = Grid3D((16, 16, 16), (T(4π), T(2π), T(2π)))
    @test repr(NUFFT(ScalarFieldSpectral(Array, grid; layout))) !=
          repr(NUFFT(ScalarFieldSpectral(Array, other_grid; layout)))
    @test repr(PointTraversalOrderScratch(grid, points)) !=
          repr(PointTraversalOrderScratch(other_grid, points))
    # And the kernels, which reach the same domain check through `_check_kernel_compatibility`.
    @test repr(spectral_cutoff(FieldSpectralMultipliers(ScalarFieldSpectral(Array, grid; layout)), T(4))) !=
          repr(spectral_cutoff(FieldSpectralMultipliers(ScalarFieldSpectral(Array, other_grid; layout)), T(4)))

    # The same property for the transfer schemes: two that differ print differently.
    @test repr(LalescuSpline(8; smoothness = 2)) != repr(LalescuSpline(8; smoothness = 1))
    @test repr(LagrangeSpline(6)) != repr(LagrangeSpline(4))
  end

  @testset "the parameter records round-trip" begin
    # A spline scheme's weight matrix is derived from `(n, m)`, so the constructor call is a complete
    # description of it — the same property decision 75 persists it by.
    for scheme in (CatmullRom, LalescuSpline(8; smoothness = 2), LalescuSpline(6; smoothness = 0),
                   LagrangeSpline(6), LagrangeSpline(4))
      @test eval(Meta.parse(repr(scheme))) === scheme
    end
  end

  @testset "the REPL form carries what the compact one abbreviates" begin
    field = VectorFieldSpectral(Array, grid; layout)
    text = repr(MIME"text/plain"(), field)
    @test occursin("\n", text)
    # The stored shape is NOT the grid for a field in spectral representation, and the element type
    # is complex — the two things a reader most often wants and the compact form leaves out.
    @test occursin(string(size(field_data(field))[1]), text)
    @test occursin("ComplexF64", text)
  end

  @testset "nothing reads an element" begin
    # Every quantity is host-side metadata, so these are safe under `allowscalar(false)` and force no
    # synchronisation. Measured here on the host, where a read of a plain `Array` is invisible: the
    # standing guard is that a display allocates nothing per call beyond its own string.
    field = ScalarFieldPhysical(Array, grid; layout)
    buffer = IOBuffer()
    show(buffer, field)                       # warm up
    bytes = @allocated show(IOBuffer(), field)
    @test bytes < 4096
  end

end
