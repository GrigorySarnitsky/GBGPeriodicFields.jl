# HDF5 persistence (the weak-dependency extension): every field type writes to / reads from an HDF5 *group*
# in a file the consumer owns, exactly (data, grid geometry, element type, tensor order, representation).
# Loading HDF5 here triggers the extension `GBGPeriodicFieldsHDF5Ext`.
using Test
using GBGPeriodicFields
using HDF5
using Random

@testset "HDF5 persistence (extension)" begin
  @test length(methods(write_field)) ≥ 1        # the extension actually loaded
  @test length(methods(read_field)) ≥ 1
  @test length(methods(write_points)) ≥ 1       # …and its point-layer twin
  @test length(methods(read_points)) ≥ 1

  mktempdir() do dir
    path = joinpath(dir, "fields.h5")
    Random.seed!(1)

    @testset "exact round-trip: every field type ($T)" for T in (Float64, Float32)
      # a non-cubic, shifted box exercises the full Grid3D round-trip; grid (8,8,6) ⇒ rfft (5,8,6). A
      # random complex array is a structurally valid spectral field — enough for the serialization test.
      grid = Grid3D((8, 8, 6), (T(2π), T(4π), T(2π)); origin = (T(0.1), T(0.2), T(0.3)))
      fields = [
        "scalar_physical" => ScalarFieldPhysical(rand(T, 8, 8, 6), grid),
        "scalar_spectral" => ScalarFieldSpectral(rand(Complex{T}, 5, 8, 6), grid),
        "vector_physical" => VectorFieldPhysical(rand(T, 8, 8, 6, 3), grid),
        "vector_spectral" => VectorFieldSpectral(rand(Complex{T}, 5, 8, 6, 3), grid),
        "tensor_physical" => TensorFieldPhysical(rand(T, 8, 8, 6, 3, 3), grid),
        "tensor_spectral" => TensorFieldSpectral(rand(Complex{T}, 5, 8, 6, 3, 3), grid),
      ]
      h5open(path, "w") do file
        for (name, f) in fields
          write_field(file, name, f)
        end
      end
      h5open(path, "r") do file
        for (name, f) in fields
          r = read_field(file, name)
          @test nameof(typeof(r)) == nameof(typeof(f))          # same field type
          @test field_data(r) == field_data(f)                  # data bit-for-bit
          @test eltype(field_data(r)) == eltype(field_data(f))  # real vs complex preserved
          @test field_scalar_type(r) == T                       # element type preserved
          @test field_tensor_order(r) == field_tensor_order(f)
          g = field_grid(r)
          @test g.grid_size == grid.grid_size
          @test g.domain_size == grid.domain_size
          @test g.origin == grid.origin
          @test g.grid_spacing == grid.grid_spacing             # geometry exact
          @test field_layout(r).fft_dims == field_layout(f).fft_dims
        end
      end
    end

    @testset "permuted rfft layout: fft_dims round-trips ($T)" for T in (Float64, Float32)
      grid = Grid3D((8, 7, 6), (T(2π), T(4π), T(2π)))
      layout = RealFourierLayout((2, 1, 3))                   # odd fold on spatial axis 2 ⇒ data (8, 4, 6)
      f = VectorFieldSpectral(rand(Complex{T}, 8, 4, 6, 3), grid; layout)
      h5open(path, "w") do file
        write_field(file, "permuted", f)
      end
      h5open(path, "r") do file
        r = read_field(file, "permuted")
        @test field_layout(r).fft_dims == (2, 1, 3)
        @test field_data(r) == field_data(f)
        @test field_scalar_type(r) == T
      end
    end

    @testset "consumer owns the file: sugar + a full snapshot bundle" begin
      grid = Grid3D((8, 8, 8), (2π, 2π, 2π))
      u = VectorFieldPhysical(rand(8, 8, 8, 3), grid)
      ω = VectorFieldPhysical(rand(8, 8, 8, 3), grid)
      # a whole "iteration snapshot": several fields plus the consumer's OWN time/iteration attributes, in
      # one file — the package serializes the fields, the consumer owns the bundling and the clock.
      h5open(path, "w") do file
        file["note"] = "run-42"                     # the user's own data, beside the fields
        snap = create_group(file, "step_0100")
        write_field(snap, "velocity", u)            # verb form, into a group they made
        snap["vorticity"] = ω                       # the setindex! sugar
        attrs(snap)["time"] = 1.25                   # consumer-owned metadata (the package has no time)
        attrs(snap)["iteration"] = 100
      end
      h5open(path, "r") do file
        @test field_data(read_field(file, "step_0100/velocity")) == field_data(u)     # by path
        @test field_data(read_field(file["step_0100"], "vorticity")) == field_data(ω) # by group handle
        @test attrs(file["step_0100"])["time"] == 1.25
      end
    end

    @testset "self-describing as plain HDF5" begin
      grid = Grid3D((8, 8, 8), (2π, 2π, 2π))
      h5open(path, "w") do file
        write_field(file, "u", ScalarFieldSpectral(rand(ComplexF64, 5, 8, 8), grid))
        # The verb is NAMED in the assertion so the ledger can attribute it — `write_field` returns
        # the group it wrote, so this asks "does the verb record the attributes its schema promises"
        # of the verb itself rather than of a local binding. Everything below reads those same
        # attributes back and checks their VALUES; this line is the presence half.
        @test issubset(("type", "version", "representation", "tensor_order", "grid_size"), keys(attrs(write_field(file, "probe", ScalarFieldSpectral(rand(ComplexF64, 5, 8, 8), grid)))))
      end
      h5open(path, "r") do file
        g = file["u"]
        @test attrs(g)["type"] == "GBGPeriodicFields.ScalarFieldSpectral"
        @test attrs(g)["version"] == 1
        @test attrs(g)["representation"] == "spectral"
        @test attrs(g)["tensor_order"] == 0
        @test collect(attrs(g)["grid_size"]) == [8, 8, 8]
        @test Set(keys(g)) == Set(["data"])
      end
    end

    @testset "error paths" begin
      grid = Grid3D((8, 8, 8), (2π, 2π, 2π))
      h5open(path, "w") do file
        file["plain"] = [1.0, 2.0]
        write_field(file, "field", ScalarFieldPhysical(rand(8, 8, 8), grid))
        create_group(file, "tagless")
      end
      h5open(path, "r") do file
        @test_throws ArgumentError read_field(file, "plain")    # a dataset, not a group
        @test_throws ArgumentError read_field(file, "absent")   # no such object
        @test_throws ArgumentError read_field(file, "tagless")  # a group, but no field type tag
      end
    end

    @testset "error paths: corrupted field groups" begin
      grid = Grid3D((8, 8, 8), (2π, 2π, 2π))
      h5open(path, "w") do file
        write_field(file, "bogus_tag", ScalarFieldPhysical(rand(8, 8, 8), grid))
        attrs(file["bogus_tag"])["type"] = "GBGPeriodicFields.NoSuchField"
        write_field(file, "no_data", ScalarFieldPhysical(rand(8, 8, 8), grid))
        HDF5.delete_object(file["no_data"], "data")
        write_field(file, "no_geometry", ScalarFieldPhysical(rand(8, 8, 8), grid))
        HDF5.delete_attribute(file["no_geometry"], "grid_size")
      end
      h5open(path, "r") do file
        @test_throws ArgumentError read_field(file, "bogus_tag")    # present but unrecognized tag
        @test_throws ArgumentError read_field(file, "no_data")      # tagged group missing its data
        @test_throws ArgumentError read_field(file, "no_geometry")  # missing a geometry attribute
      end
    end
    @testset "exact round-trip: the point layer ($T)" for T in (Float64, Float32)
      # The point layer has no grid and no representation, so a group carries only the array, the
      # element type, the point count and (for values) the tensor order. M = 5 with a deliberately
      # non-round coordinate set, so an element-type slip would show.
      M = 5
      Random.seed!(7)
      positions = PointSet(T.(2π .* rand(M, 3)))
      scalars   = ScalarPointValues(T.(randn(M)))
      vectors   = VectorPointValues(T.(randn(M, 3)))
      tensors   = TensorPointValues(T.(randn(M, 3, 3)))
      third     = TensorPointValues{3}(T.(randn(M, 3, 3, 3)))

      h5open(path, "w") do file
        write_points(file, "positions", positions)
        write_points(file, "scalars", scalars)
        write_points(file, "vectors", vectors)
        write_points(file, "tensors", tensors)
        file["third"] = third                          # the setindex! sugar, as for fields
      end

      h5open(path, "r") do file
        back_positions = read_points(file, "positions")
        @test back_positions isa PointSet
        @test point_positions(back_positions) == point_positions(positions)
        @test eltype(point_positions(back_positions)) === T
        @test npoints(back_positions) == M

        for (name, original, Type_, order) in (("scalars", scalars, ScalarPointValues, 0),
                                               ("vectors", vectors, VectorPointValues, 1),
                                               ("tensors", tensors, TensorPointValues, 2),
                                               ("third",   third,   TensorPointValues, 3))
          back = read_points(file, name)
          @test back isa Type_
          @test point_values(back) == point_values(original)     # bit-for-bit
          @test eltype(point_values(back)) === T
          @test point_value_tensor_order(back) == order           # recovered from the array's dimensionality
          @test npoints(back) == M
        end
      end
    end

    @testset "point groups are self-describing, and independent of the field ones" begin
      Random.seed!(11)
      grid = Grid3D((8, 8, 8), (2π, 2π, 2π))
      positions = PointSet(2π .* rand(4, 3))
      h5open(path, "w") do file
        write_points(file, "positions", positions)
        write_points(file, "q", VectorPointValues(randn(4, 3)))
        # The presence half, named on the line so the ledger attributes it to the verb (as with
        # `write_field` above). A base records no fiber, so `tensor_order` is deliberately absent
        # here and asserted absent below — the schema differs by what is written, which is the
        # point of asking this of each verb separately.
        @test issubset(("type", "version", "npoints"), keys(attrs(write_points(file, "probe", positions))))
        write_field(file, "u", VectorFieldPhysical(rand(8, 8, 8, 3), grid))
      end
      h5open(path, "r") do file
        a = attrs(file["positions"])
        @test a["type"] == "GBGPeriodicFields.PointSet"
        @test a["npoints"] == 4
        @test !haskey(a, "tensor_order")                        # a base carries no fiber
        @test !haskey(a, "grid_size")                           # and no grid geometry
        @test haskey(attrs(file["q"]), "tensor_order")
        @test attrs(file["q"])["tensor_order"] == 1
        # the two families share one file and neither reader accepts the other's groups
        @test read_field(file, "u") isa VectorFieldPhysical
        @test_throws ArgumentError read_points(file, "u")       # a field group, unrecognized tag here
        @test_throws ArgumentError read_field(file, "positions") # a point group, no geometry attributes
      end
    end

    @testset "error paths: corrupted point groups" begin
      h5open(path, "w") do file
        file["plain_points"] = [1.0, 2.0]
        write_points(file, "bogus_tag", PointSet(rand(3, 3)))
        attrs(file["bogus_tag"])["type"] = "GBGPeriodicFields.NoSuchPointThing"
        write_points(file, "no_data", PointSet(rand(3, 3)))
        HDF5.delete_object(file["no_data"], "data")
        create_group(file, "tagless_points")
      end
      h5open(path, "r") do file
        @test_throws ArgumentError read_points(file, "plain_points")    # a dataset, not a group
        @test_throws ArgumentError read_points(file, "absent")          # no such object
        @test_throws ArgumentError read_points(file, "tagless_points")  # a group, but no type tag
        @test_throws ArgumentError read_points(file, "bogus_tag")       # present but unrecognized tag
        @test_throws ArgumentError read_points(file, "no_data")         # tagged group missing its data
      end
    end
  end
end


# Persistence is a CONTRACT, not a best effort (external audit CODE-08, CODE-09).
@testset "HDF5: the grid round-trips exactly, and the schema is enforced" begin
  # CODE-08: the spacing was not stored, only recomputed. A grid built through the four-argument
  # constructor may legitimately hold a spacing that is only APPROXIMATELY domain_size ./ grid_size
  # (decision 45 accepts that), so a reload silently returned a different grid — and with it every
  # interpolation position and cell measure. The fixture has to be a grid the convenience constructor
  # cannot produce, or it proves nothing.
  sizes = (8, 8, 8)
  extent = (2π, 2π, 2π)
  canonical = extent ./ sizes
  perturbed = ntuple(d -> nextfloat(nextfloat(canonical[d])), 3)
  @test perturbed != canonical
  grid = Grid3D(sizes, extent, perturbed, (0.0, 0.0, 0.0))
  field = ScalarFieldPhysical(rand(sizes...), grid)

  mktempdir() do dir
    path = joinpath(dir, "exact.h5")
    h5open(path, "w") do io; write_field(io, "f", field); end
    back = h5open(path, "r") do io; read_field(io, "f"); end
    @test field_grid(back).grid_spacing == perturbed          # bit-for-bit, not merely ≈
    @test field_grid(back) == grid
    @test field_data(back) == field_data(field)
  end

  # CODE-09: every self-describing attribute is redundant with the type tag or the data, so a
  # disagreement means the file is not what it claims. Each tampering below used to be accepted.
  plain = ScalarFieldPhysical(rand(4, 4, 4), Grid3D((4, 4, 4), (2π, 2π, 2π)))
  tamperings = (("version", 99),
                ("representation", "spectral"),
                ("eltype", "Float32"),
                ("tensor_order", 2))
  mktempdir() do dir
    for (attribute, value) in tamperings
      path = joinpath(dir, "$(attribute).h5")
      h5open(path, "w") do io; write_field(io, "f", plain); end
      h5open(path, "r+") do io
        HDF5.delete_attribute(io["f"], attribute)
        HDF5.attrs(io["f"])[attribute] = value
      end
      @test_throws ArgumentError h5open(path, "r") do io; read_field(io, "f"); end
    end
    # And an untampered file still reads, so the validation rejects only what it should.
    path = joinpath(dir, "clean.h5")
    h5open(path, "w") do io; write_field(io, "f", plain); end
    back = h5open(path, "r") do io; read_field(io, "f"); end
    @test field_data(back) == field_data(plain)
  end
end


# Transfer-scheme persistence (decision 75). A scheme is a parameter record, not a section: no
# `data` dataset, and the round trip stores the parameters rather than the derived weights. The
# oracle is `===` — Julia's egality on immutable structs, which for these types means "same
# parameters and bit-identical weights" — reinforced by a behavioural check that a read scheme
# interpolates bitwise identically, so the test would still bite if a scheme ever gained state that
# `===` sees but the stored parameters do not determine.
@testset "HDF5: transfer schemes round-trip through their parameters" begin
  mktempdir() do dir
    path = joinpath(dir, "schemes.h5")

    schemes = (CatmullRom,                         # the alias: LalescuSpline(1, 1), no own identity
               LalescuSpline(2; smoothness = 0),                # trilinear, the degenerate corner
               LalescuSpline(8; smoothness = 2),
               LalescuSpline(6; smoothness = 4),                # m = 2n, the upper bound of the valid region
               LagrangeSpline(2),
               LagrangeSpline(8),
               DirectDFT())

    h5open(path, "w") do io
      for (i, scheme) in enumerate(schemes)
        g = write_scheme(io, "s$i", scheme)
        @test g isa HDF5.Group
        @test !haskey(g, "data")               # a scheme owns no array: attributes only
      end
      io["sugar"] = CatmullRom                 # the `parent[name] = scheme` sugar
    end

    h5open(path, "r") do io
      for (i, scheme) in enumerate(schemes)
        back = read_scheme(io, "s$i")
        @test back === scheme                  # egal: same type parameters AND identical weights
        @test back == scheme
        @test typeof(back) === typeof(scheme)
      end
      @test read_scheme(io, "sugar") === CatmullRom
    end

    # The reconstructed scheme must COMPUTE identically, which is the claim a consumer depends on.
    grid = Grid3D((8, 8, 8), (2π, 2π, 2π))
    field = ScalarFieldPhysical(Array, (x, y, z) -> sin(x) * cos(y) + 0.3 * sin(z), grid)
    points = PointSet(2π .* rand(16, 3))
    for scheme in (CatmullRom, LagrangeSpline(6), LalescuSpline(8; smoothness = 2))
      h5open(path, "cw") do io
        haskey(io, "behave") && delete_object(io, "behave")
        write_scheme(io, "behave", scheme)
      end
      back = h5open(path, "r") do io; read_scheme(io, "behave"); end
      @test point_values(interpolate(field, points, back)) ==
            point_values(interpolate(field, points, scheme))
    end
  end
end


@testset "HDF5: a NUFFT is refused, and a malformed scheme group is caught" begin
  mktempdir() do dir
    path = joinpath(dir, "scheme_errors.h5")
    grid = Grid3D((8, 8, 8), (2π, 2π, 2π))
    spectral = ScalarFieldSpectral(Array, grid)

    h5open(path, "w") do io
      # The documented refusal: a NUFFT owns plans and a reference-bound window, not parameters.
      @test_throws ArgumentError write_scheme(io, "nufft", NUFFT(spectral; tol = 1e-6))
      @test_throws ArgumentError io["nufft_sugar"] = NUFFT(spectral; tol = 1e-6)

      write_scheme(io, "impossible", LalescuSpline(4; smoothness = 1))
      attrs(io["impossible"])["smoothness"] = 9        # violates 0 ≤ m ≤ 2n at n = 1
      write_scheme(io, "future", CatmullRom)
      attrs(io["future"])["version"] = 99
      write_scheme(io, "alien_eltype", CatmullRom)
      attrs(io["alien_eltype"])["eltype"] = "Float16"
      # A scheme written before decision 101 could record Float32 weights; it still reads, as the
      # Float64 scheme, the weights being converted to the field's type at each launch either way.
      write_scheme(io, "single_eltype", CatmullRom)
      attrs(io["single_eltype"])["eltype"] = "Float32"
      write_scheme(io, "no_param", CatmullRom)
      delete_attribute(io["no_param"], "stencil_width")
      write_scheme(io, "wrong_tag", CatmullRom)
      attrs(io["wrong_tag"])["type"] = "GBGPeriodicFields.NotAScheme"
      create_group(io, "bare")                         # a group with no attributes at all
      io["plain_dataset"] = [1.0, 2.0, 3.0]
    end

    h5open(path, "r") do io
      # Each malformed group is refused for its OWN reason, never silently reconstructed.
      @test_throws ArgumentError read_scheme(io, "impossible")     # constructor revalidates
      @test_throws ArgumentError read_scheme(io, "future")         # schema from a newer version
      @test_throws ArgumentError read_scheme(io, "alien_eltype")   # closed element-type table
      @test read_scheme(io, "single_eltype") === CatmullRom       # a recorded Float32 reads as Float64
      @test_throws ArgumentError read_scheme(io, "no_param")       # incomplete group
      @test_throws ArgumentError read_scheme(io, "wrong_tag")      # unrecognized tag
      @test_throws ArgumentError read_scheme(io, "bare")           # no `type` attribute
      @test_throws ArgumentError read_scheme(io, "plain_dataset")  # a dataset, not a group
      @test_throws ArgumentError read_scheme(io, "absent")         # no such object
    end

    # A scheme group written before decision 98 (schema version 1) stored the half-width `neighbours`,
    # the width being 2n + 2, and is still read as the same scheme.
    h5open(path, "r+") do io
      for (label, tag, parameters) in (("v1_lalescu", "LalescuSpline", ("neighbours" => 3, "smoothness" => 2)),
                                       ("v1_lagrange", "LagrangeSpline", ("neighbours" => 1,)))
        g = create_group(io, label)
        a = attrs(g)
        a["type"] = "GBGPeriodicFields." * tag
        a["version"] = 1
        a["eltype"] = "Float64"
        for (key, value) in parameters
          a[key] = value
        end
      end
    end
    h5open(path, "r") do io
      @test read_scheme(io, "v1_lalescu") == LalescuSpline(8; smoothness = 2)
      @test read_scheme(io, "v1_lagrange") == LagrangeSpline(4)
      # A scheme now writes schema version 2, with the renamed parameters.
      @test attrs(io["future"])["version"] == 99         # the tampered one, untouched
    end
    h5open(path, "r+") do io
      g = write_scheme(io, "v2", LalescuSpline(6; smoothness = 1))
      @test attrs(g)["version"] == 2
      @test Int(attrs(g)["stencil_width"]) == 6 && Int(attrs(g)["smoothness"]) == 1
      @test !haskey(attrs(g), "neighbours")
    end
  end
end


# The completeness guard: every concrete transfer scheme the package defines must either round-trip
# or be a RECORDED refusal. Without this, adding a scheme family (the recorded van Hinsberg
# direction) would ship it silently unpersistable, and the consumer would discover it at a restart.
@testset "HDF5: every concrete transfer scheme is persistable or a recorded refusal" begin
  refused = Set([:NUFFT])          # holds plans + a reference field; rebuilt, never stored
  # Derived from the module's own bindings rather than from `subtypes`: the guard is about the
  # schemes THIS package defines, and a consumer that subtypes `AbstractTransferScheme` in its own
  # code must not fail our completeness check. A parameterized scheme is a `UnionAll`, which is not
  # abstract, so both families and the singleton are caught by the same predicate.
  Interp = GBGPeriodicFields.Interpolation
  concrete = Set{Symbol}()
  for name in names(Interp; all = true)
    isdefined(Interp, name) || continue
    binding = getfield(Interp, name)
    binding isa Type || continue
    binding === AbstractTransferScheme && continue
    (binding <: AbstractTransferScheme && !isabstracttype(binding)) || continue
    push!(concrete, Base.typename(binding).name)
  end
  @test !isempty(concrete)         # the guard must not pass by finding nothing
  mktempdir() do dir
    path = joinpath(dir, "coverage.h5")
    representative = Dict(:LalescuSpline => CatmullRom, :LagrangeSpline => LagrangeSpline(4),
                          :DirectDFT => DirectDFT())
    for name in setdiff(concrete, refused)
      @test haskey(representative, name)     # a new scheme needs a representative here…
      haskey(representative, name) || continue
      h5open(path, "w") do io; write_scheme(io, "s", representative[name]); end
      @test h5open(io -> read_scheme(io, "s"), path, "r") === representative[name]
    end
  end
end


# read_field! and the copy-free write (2026-10-01, from the consumer's temporary-memory ledger). The
# oracle for a read is the raw dataset read with HDF5's own API, sharing no code with the package.
@testset "HDF5: read_field! fills an existing field, and a host write makes no copy ($T)" for T in (Float64, Float32)
  sizes = (8, 6, 5)
  grid = Grid3D(sizes, T.((2π, 4π, 2π)))
  layout = RealFourierLayout((2, 1, 3))
  path = tempname() * ".h5"
  makers = (
    (R, a) -> R == 0 ? ScalarFieldPhysical(a, grid; layout) : R == 1 ? VectorFieldPhysical(a, grid; layout) :
                       TensorFieldPhysical{2}(a, grid; layout),
    (R, a) -> R == 0 ? ScalarFieldSpectral(a, grid; layout) : R == 1 ? VectorFieldSpectral(a, grid; layout) :
                       TensorFieldSpectral{2}(a, grid; layout))
  shapes = ((R) -> field_physical_shape(grid, Val(R)), (R) -> field_spectral_shape(grid, layout, Val(R)))
  elements = (T, Complex{T})
  h5open(path, "w") do file
    for (k, make) in enumerate(makers), R in (0, 1, 2)
      field = make(R, randn(elements[k], shapes[k](R)...))
      write_field(file, "f$(k)_$(R)", field)
    end
  end
  h5open(path, "r") do file
    for (k, make) in enumerate(makers), R in (0, 1, 2)
      name = "f$(k)_$(R)"
      stored = read(file[name]["data"])                       # the raw oracle
      destination = make(R, zeros(elements[k], shapes[k](R)...))
      @test read_field!(destination, file, name) === destination
      @test field_data(destination) == stored
      # Storage that is not a plain Array takes the one-component staging path.
      wrapped = make(R, PermutedDimsArray(zeros(elements[k], shapes[k](R)...), ntuple(identity, 3 + R)))
      read_field!(wrapped, file, name)
      @test field_data(wrapped) == stored
    end
    # Refused, and nothing written: another type, another tensor order, another precision, another
    # layout, another box.
    name = "f1_1"
    sentinel(field) = (fill!(field_data(field), 7); field)
    other_T = T === Float64 ? Float32 : Float64
    refusals = (
      sentinel(ScalarFieldPhysical(zeros(T, sizes...), grid; layout)),
      sentinel(VectorFieldSpectral(Array, grid; layout)),
      sentinel(VectorFieldPhysical(zeros(other_T, sizes..., 3), Grid3D(sizes, other_T.((2π, 4π, 2π))); layout)),
      sentinel(VectorFieldPhysical(zeros(T, sizes..., 3), grid; layout = RealFourierLayout())),
      sentinel(VectorFieldPhysical(zeros(T, sizes..., 3), Grid3D(sizes, T.((2π, 2π, 2π))); layout)))
    for destination in refusals
      @test_throws ArgumentError read_field!(destination, file, name)
      @test all(==(7), field_data(destination))
    end
    # A precision mismatch names the precisions, not the complex storage element of a field in
    # spectral representation.
    other_grid = Grid3D(sizes, other_T.((2π, 4π, 2π)))
    spectral = VectorFieldSpectral(Array, other_grid; layout)
    message = try read_field!(spectral, file, "f2_1"); "" catch error; sprint(showerror, error) end
    @test occursin("holds a $(T) field", message) && occursin("destination is $(other_T)", message)
    @test !occursin("Complex", message)
  end
  rm(path)

  # Neither verb copies the field: at 24³ a vector field is 324 KiB in Float64, against HDF5's own
  # fixed bookkeeping of a few KiB per call, which a field-sized copy would dwarf.
  big = Grid3D((24, 24, 24), T.((2π, 2π, 2π)))
  field = VectorFieldPhysical(randn(T, 24, 24, 24, 3), big)
  destination = VectorFieldPhysical(zeros(T, 24, 24, 24, 3), big)
  path = tempname() * ".h5"
  h5open(path, "w") do file
    write_field(file, "warm", field)
    @test @allocated(write_field(file, "u", field)) < sizeof(field_data(field)) ÷ 8
  end
  h5open(path, "r") do file
    read_field!(destination, file, "u")
    @test @allocated(read_field!(destination, file, "u")) < sizeof(field_data(destination)) ÷ 8
    @test field_data(destination) == field_data(field)
  end
  rm(path)
end
