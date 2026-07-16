# HDF5 persistence for the fields — loaded automatically when both GBGPeriodicFields and HDF5 are present
# (a weak-dependency package extension, so the core stays free of the HDF5 binary). A field maps to a
# self-describing HDF5 *group*: its numeric array is the dataset `data`, and its `Grid3D` geometry, Fourier
# layout, element type, tensor order, representation, and a type/version tag are attributes. Both
# representations are handled — a physical field stores a real array, a field in spectral representation
# its complex half-spectrum. The consumer owns the file, so every method takes an open `File`/`Group`.
module GBGPeriodicFieldsHDF5Ext

using HDF5
using GBGPeriodicFields.Fields:
  ScalarFieldPhysical, ScalarFieldSpectral,
  VectorFieldPhysical, VectorFieldSpectral,
  TensorFieldPhysical, TensorFieldSpectral,
  AbstractField, AbstractFieldSpectral,
  Grid3D, RealFourierLayout,
  field_data, field_grid, field_layout, field_tensor_order, field_scalar_type
import GBGPeriodicFields.Fields: write_field, read_field

const SCHEMA_VERSION = 1

# One type tag per concrete field type. The tensor order is not encoded in the tag — it is recovered from
# the stored array's dimensionality — but it is also written as an attribute for self-description.
_type_tag(::ScalarFieldPhysical) = "GBGPeriodicFields.ScalarFieldPhysical"
_type_tag(::ScalarFieldSpectral) = "GBGPeriodicFields.ScalarFieldSpectral"
_type_tag(::VectorFieldPhysical) = "GBGPeriodicFields.VectorFieldPhysical"
_type_tag(::VectorFieldSpectral) = "GBGPeriodicFields.VectorFieldSpectral"
_type_tag(::TensorFieldPhysical) = "GBGPeriodicFields.TensorFieldPhysical"
_type_tag(::TensorFieldSpectral) = "GBGPeriodicFields.TensorFieldSpectral"


# --- write: create the subgroup, store the host array as `data` and the metadata as attributes ---

function write_field(parent::HDF5.H5DataStore, name::AbstractString, field::AbstractField)
  g = create_group(parent, name)
  g["data"] = Array(field_data(field))       # Array(...) copies a device array to the host; no-op on CPU
  grid = field_grid(field)
  a = attrs(g)
  a["type"] = _type_tag(field)
  a["version"] = SCHEMA_VERSION
  a["representation"] = field isa AbstractFieldSpectral ? "spectral" : "physical"
  a["eltype"] = string(field_scalar_type(field))       # stored for self-description; reconstruction uses `data`
  a["tensor_order"] = field_tensor_order(field)
  a["grid_size"] = collect(grid.grid_size)
  a["domain_size"] = collect(grid.domain_size)
  a["origin"] = collect(grid.origin)
  a["fft_dims"] = collect(field_layout(field).fft_dims)
  return g
end


# the sugar: `parent[name] = field` mirrors HDF5.jl's own dataset-writing `setindex!`. Dispatch on the
# concrete `File`/`Group` and the specific `AbstractField`, so this method is strictly more specific than —
# never ambiguous with — HDF5's array-writing `setindex!(::Union{File,Group}, val, path)`.
function Base.setindex!(parent::Union{HDF5.File,HDF5.Group}, field::AbstractField, name::AbstractString)
  write_field(parent, name, field)
  return parent
end


# --- read: dispatch on the stored type tag, rebuild the Grid3D + layout, reconstruct via the public
# constructor. The field's element type follows the stored array (real for a physical field, complex for
# a spectral one), and the tensor order follows the array's dimensionality. ---

function read_field(parent::HDF5.H5DataStore, name::AbstractString)
  haskey(parent, name) ||
    throw(ArgumentError("read_field: no object named \"$name\" under the given parent"))
  g = parent[name]
  g isa HDF5.Group ||
    throw(ArgumentError("read_field: \"$name\" is a dataset, not a field group"))
  haskey(attrs(g), "type") || throw(ArgumentError(
    "read_field: group \"$name\" has no `type` attribute — it was not written by write_field"))
  tag = attrs(g)["type"]
  data = read(g["data"])
  grid = _reconstruct_grid(g, real(eltype(data)))
  layout = RealFourierLayout(Tuple(Int.(attrs(g)["fft_dims"])))
  if tag == "GBGPeriodicFields.ScalarFieldPhysical"
    return ScalarFieldPhysical(data, grid, layout)
  elseif tag == "GBGPeriodicFields.ScalarFieldSpectral"
    return ScalarFieldSpectral(data, grid, layout)
  elseif tag == "GBGPeriodicFields.VectorFieldPhysical"
    return VectorFieldPhysical(data, grid, layout)
  elseif tag == "GBGPeriodicFields.VectorFieldSpectral"
    return VectorFieldSpectral(data, grid, layout)
  elseif tag == "GBGPeriodicFields.TensorFieldPhysical"
    return TensorFieldPhysical(data, grid, layout)
  elseif tag == "GBGPeriodicFields.TensorFieldSpectral"
    return TensorFieldSpectral(data, grid, layout)
  else
    throw(ArgumentError("read_field: unrecognized field type tag \"$tag\" in group \"$name\""))
  end
end


# The grid's real element type `T` is taken from the stored data (so it matches the field exactly); the
# grid spacing is recomputed by the `Grid3D` constructor, bit-for-bit as on the original.
function _reconstruct_grid(g, ::Type{T}) where {T<:AbstractFloat}
  grid_size = Tuple(Int.(attrs(g)["grid_size"]))
  domain_size = Tuple(T.(attrs(g)["domain_size"]))
  origin = Tuple(T.(attrs(g)["origin"]))
  return Grid3D(grid_size, domain_size; origin = origin)
end

end # module GBGPeriodicFieldsHDF5Ext
