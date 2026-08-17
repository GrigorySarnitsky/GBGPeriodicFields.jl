# Moving sections, their companions and their plans between storage families.
#
# On the host `adapt(Array, x)` is deliberately the IDENTITY, so adapting to `Array` cannot exercise
# the rebuild at all — it returns its argument. The rebuild is what carries the grid, the layout, the
# origin and the tensor order, and that is exactly the propagation whose absence broke `map` for every
# permuted layout (decision 48). So the gate drives it with a custom adaptor that maps a host array to
# a DISTINCT host array: every metadata assertion below then runs on CPU, in the gate, rather than
# only in the opt-in GPU suite.
using Test
using GBGPeriodicFields
using GBGPeriodicFields: field_data, field_grid, field_layout, field_tensor_order,
                         spectral_field_shape, physical_field_shape
using GBGPeriodicFields.Fields: similar_spectral_field, _is_canonical
import Adapt
using FFTW: MEASURE


# A stand-in storage family: same array type, different object. `adapt` on it must therefore rebuild.
struct CopyStorage end
Adapt.adapt_storage(::CopyStorage, x::Array) = copy(x)


const GRID   = Grid3D((8, 8, 8), (2pi, 4pi, 6pi); origin = (0.5, 0.25, 0.125))
const FOLDS  = (RealFourierLayout(), RealFourierLayout((2, 1, 3)), RealFourierLayout((3, 1, 2)))

# A field's element type and its grid's are the SAME parameter — `Grid3D{T}` stores the domain size,
# spacing and origin as `NTuple{3, T}` — so a `Float32` field needs a `Float32` grid. That coupling is
# also why converting precision is a different operation from moving storage: it has to rebuild the
# grid, where a move touches only the array.
grid_of(::Type{T}) where {T} = Grid3D((8, 8, 8), T.((2pi, 4pi, 6pi)); origin = T.((0.5, 0.25, 0.125)))


@testset "adapt: sections move and carry their metadata" begin
  for layout in FOLDS, T in (Float64, Float32)
    grid = grid_of(T)
    physical = (ScalarFieldPhysical(rand(T, physical_field_shape(grid, Val(0))...), grid, layout),
                VectorFieldPhysical(rand(T, physical_field_shape(grid, Val(1))...), grid, layout),
                TensorFieldPhysical{2}(rand(T, physical_field_shape(grid, Val(2))...), grid, layout))
    spectral = (ScalarFieldSpectral(rand(Complex{T}, spectral_field_shape(grid, layout, Val(0))...), grid, layout),
                VectorFieldSpectral(rand(Complex{T}, spectral_field_shape(grid, layout, Val(1))...), grid, layout),
                TensorFieldSpectral{2}(rand(Complex{T}, spectral_field_shape(grid, layout, Val(2))...), grid, layout))

    for field in (physical..., spectral...)
      moved = adapt(CopyStorage(), field)
      @test typeof(moved) === typeof(field)                       # same kind of object
      @test field_data(moved) !== field_data(field)               # genuinely rebuilt, not returned
      @test field_data(moved) == field_data(field)                # and bitwise equal
      @test eltype(field_data(moved)) === eltype(field_data(field))   # precision NEVER rides along
      @test field_grid(moved)   == field_grid(field)
      @test field_layout(moved) == field_layout(field)            # the fold `map` used to drop
      @test field_grid(moved).origin == field_grid(field).origin
      @test field_tensor_order(moved) == field_tensor_order(field)
    end
  end
end


@testset "adapt: the extension hook is what adapt dispatches to" begin
  # `adapt_structure` is the method a package defines; `adapt` is the verb a user calls. A consumer
  # writing its own adaptor reaches the hook directly, so it is exercised directly here rather than
  # only through the verb.
  u = ScalarFieldPhysical(rand(Float64, 8, 8, 8), GRID, RealFourierLayout())
  viaHook = Adapt.adapt_structure(CopyStorage(), u)
  viaVerb = adapt(CopyStorage(), u)
  @test typeof(viaHook) === typeof(viaVerb) === typeof(u)
  @test field_data(viaHook) == field_data(u)
  @test field_data(viaHook) !== field_data(u)
  @test field_grid(viaHook) == field_grid(u) && field_layout(viaHook) == field_layout(u)
end


@testset "adapt: to the family a section is already in, it is the identity" begin
  u = ScalarFieldPhysical(rand(Float64, 8, 8, 8), GRID, RealFourierLayout())
  @test adapt(Array, u) === u
  q = ScalarPointValues(rand(Float64, 5))
  @test adapt(Array, q) === q
end


@testset "adapt: the point layer mirrors the field layer" begin
  points = PointSet(rand(Float64, 6, 3) .* 2pi)
  values = (ScalarPointValues(rand(Float64, 6)),
            VectorPointValues(rand(Float64, 6, 3)),
            TensorPointValues{2}(rand(Float64, 6, 3, 3)))
  moved_points = adapt(CopyStorage(), points)
  @test point_coordinates(moved_points) !== point_coordinates(points)
  @test point_coordinates(moved_points) == point_coordinates(points)
  for v in values
    moved = adapt(CopyStorage(), v)
    @test typeof(moved) === typeof(v)
    @test point_values(moved) !== point_values(v)
    @test point_values(moved) == point_values(v)
  end
end


@testset "adapt: multipliers move, and the Canonical parameter survives" begin
  layout = RealFourierLayout()
  z = ScalarFieldSpectral(zeros(ComplexF64, spectral_field_shape(GRID, layout, Val(0))...), GRID, layout)
  # The convenience constructor derives the wavenumbers from the grid and so marks them canonical;
  # the explicit six-array form does not. Both must come back as they went in, because that parameter
  # is what lets `convolve` collapse two radial kernels statically (decision 61). A rebuild that
  # dropped it would be a silent performance regression with no wrong answer.
  canonical = FieldSpectralMultipliers(z)
  explicit  = FieldSpectralMultipliers(GRID, layout,
                                       copy(canonical.wavenumber_1), copy(canonical.wavenumber_2),
                                       copy(canonical.wavenumber_3), copy(canonical.squared_wavenumber_1),
                                       copy(canonical.squared_wavenumber_2), copy(canonical.squared_wavenumber_3))
  @test _is_canonical(canonical)
  @test !_is_canonical(explicit)
  for multipliers in (canonical, explicit)
    moved = adapt(CopyStorage(), multipliers)
    @test _is_canonical(moved) == _is_canonical(multipliers)
    @test moved.wavenumber_1 !== multipliers.wavenumber_1
    @test moved.wavenumber_1 == multipliers.wavenumber_1
    @test moved.squared_wavenumber_3 == multipliers.squared_wavenumber_3
    @test moved.grid == multipliers.grid
    @test moved.fourier_layout == multipliers.fourier_layout
  end
end


@testset "adapt: every kernel storage class moves and still applies" begin
  layout = RealFourierLayout()
  z = ScalarFieldSpectral(zeros(ComplexF64, spectral_field_shape(GRID, layout, Val(0))...), GRID, layout)
  m = FieldSpectralMultipliers(z)
  u = ScalarFieldPhysical(rand(Float64, physical_field_shape(GRID, Val(0))...), GRID, layout)
  plans = FieldTransformPlans(u, z)
  uh = to_spectral(u, plans)

  kernels = (spectral_cutoff(m, 3.0),                    # RadialKernel
             translation_kernel(m, (0.1, 0.2, 0.3)),     # SeparableKernel
             materialize_kernel(spectral_cutoff(m, 3.0)),# StoredKernel
             convolve(spectral_cutoff(m, 3.0), translation_kernel(m, (0.1, 0.2, 0.3))))  # ProductKernel
  for kernel in kernels
    moved = adapt(CopyStorage(), kernel)
    @test nameof(typeof(moved)) === nameof(typeof(kernel))
    # The moved kernel must compute the same thing: that is what makes the move meaningful.
    @test field_data(convolve(uh, moved)) ≈ field_data(convolve(uh, kernel))
  end
end


@testset "adapt: transform plans are rebuilt unaided, and keep their planner request" begin
  layout = RealFourierLayout()
  z = ScalarFieldSpectral(zeros(ComplexF64, spectral_field_shape(GRID, layout, Val(0))...), GRID, layout)
  u = ScalarFieldPhysical(rand(Float64, physical_field_shape(GRID, Val(0))...), GRID, layout)

  plans = FieldTransformPlans(u, z)
  # Nothing is supplied but the plans themselves: they carry their own grid, layout, element type and
  # tensor order, so the witnesses the planner needs are allocated internally and released.
  rebuilt = adapt(CopyStorage(), plans)
  @test rebuilt.grid == plans.grid
  @test rebuilt.fourier_layout == plans.fourier_layout
  # A rebuilt plan must actually transform, and agree with the original to the bit.
  @test field_data(to_physical(to_spectral(u, rebuilt), rebuilt)) ≈
        field_data(to_physical(to_spectral(u, plans), plans))

  # The planner request is recorded and survives the move. `FFTW.MEASURE` is numerically ZERO, so a
  # truthiness test would read it as "unset" — the discriminator has to be `isnothing`.
  @test plans.fft_flags === nothing
  measured = FieldTransformPlans(u, z; fft_flags = MEASURE)
  @test measured.fft_flags == UInt32(MEASURE)
  @test adapt(CopyStorage(), measured).fft_flags == UInt32(MEASURE)

  # Higher tensor orders rebuild through the same path.
  for R in (1, 2)
    zr = similar_field(z, Val(R))
    ur = similar_field(u, Val(R))
    copyto!(field_data(ur), rand(Float64, size(field_data(ur))...))
    pr = FieldTransformPlans(ur, zr)
    pr_moved = adapt(CopyStorage(), pr)
    @test field_data(to_physical(to_spectral(ur, pr_moved), pr_moved)) ≈
          field_data(to_physical(to_spectral(ur, pr), pr))
  end
end


# The flag `FieldSpectralMultipliers` carries in its type must survive a storage-family move IN THE
# TYPE, not merely in the value. Decision 61 put it there so `convolve` can collapse two radial kernels
# statically; a rebuilt object whose last parameter inference cannot resolve turns that back into a
# run-time decision, and `RadialKernel`/`ProductKernel` inherit the imprecision through the multipliers
# type they carry. The value assertion alone passed throughout the period the type assertion would have
# failed, which is why both are here. Found by the exhaustive survey (2026-08-17).
@testset "adapt preserves the canonical flag in the TYPE (decision 61)" begin
  grid = Grid3D((8, 8, 8), (2π, 2π, 2π))
  layout = RealFourierLayout()
  spectral = ScalarFieldSpectral(zeros(ComplexF64, GBGPeriodicFields.Fields.spectral_field_shape(grid, layout, Val(0))), grid)
  canonical = FieldSpectralMultipliers(spectral)
  supplied = FieldSpectralMultipliers(grid, layout,
                                      copy(canonical.wavenumber_1), copy(canonical.wavenumber_2), copy(canonical.wavenumber_3),
                                      copy(canonical.squared_wavenumber_1), copy(canonical.squared_wavenumber_2),
                                      copy(canonical.squared_wavenumber_3))
  for multipliers in (canonical, supplied)
    moved = adapt(Array, multipliers)
    @test typeof(moved) === typeof(multipliers)                                  # the value survives
    @test isconcretetype(only(Base.return_types(adapt, (Type{Array}, typeof(multipliers)))))
    for kernel in (spectral_cutoff(multipliers, 3.0),                            # radial
                   assignment_window(multipliers),                               # separable
                   convolve(spectral_cutoff(multipliers, 3.0), assignment_window(multipliers)))  # product
      @test isconcretetype(only(Base.return_types(adapt, (Type{Array}, typeof(kernel)))))
    end
  end
end
