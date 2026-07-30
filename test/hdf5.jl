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
      f = VectorFieldSpectral(rand(Complex{T}, 8, 4, 6, 3), grid, layout)
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
        @test point_coordinates(back_positions) == point_coordinates(positions)
        @test eltype(point_coordinates(back_positions)) === T
        @test npoints(back_positions) == M

        for (name, original, Type_, order) in (("scalars", scalars, ScalarPointValues, 0),
                                               ("vectors", vectors, VectorPointValues, 1),
                                               ("tensors", tensors, TensorPointValues, 2),
                                               ("third",   third,   TensorPointValues, 3))
          back = read_points(file, name)
          @test back isa Type_
          @test point_values(back) == point_values(original)     # bit-for-bit
          @test eltype(point_values(back)) === T
          @test pointvalue_tensor_order(back) == order           # recovered from the array's dimensionality
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
