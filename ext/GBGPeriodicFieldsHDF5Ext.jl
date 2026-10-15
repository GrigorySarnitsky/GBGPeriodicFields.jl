# HDF5 persistence for the sections — loaded automatically when both GBGPeriodicFields and HDF5 are present
# (a weak-dependency package extension, so the core stays free of the HDF5 binary). A field maps to a
# self-describing HDF5 *group*: its numeric array is the dataset `data`, and its `Grid3D` geometry, Fourier
# layout, element type, tensor order, representation, and a type/version tag are attributes. Both
# representations are handled — a physical field stores a real array, a field in spectral representation
# its complex half-spectrum. The point layer mirrors this: a `PointSet` and each point-value type map to
# their own self-describing group, positions and values kept separate because they are separate objects
# (the base, and sections over it). A transfer SCHEME is the one persisted object that is not a
# section: it owns no array, so its group carries attributes and no `data`, and the round trip stores
# the parameters a scheme is made of rather than the weights it derives from them. The consumer owns
# the file, so every method takes an open `File`/`Group`.
module GBGPeriodicFieldsHDF5Ext

using HDF5
using GBGPeriodicFields.Fields:
  ScalarFieldPhysical, ScalarFieldSpectral,
  VectorFieldPhysical, VectorFieldSpectral,
  TensorFieldPhysical, TensorFieldSpectral,
  AbstractField, AbstractFieldSpectral,
  Grid3D, RealFourierLayout,
  field_data, field_grid, field_layout, field_tensor_order, field_scalar_type
import GBGPeriodicFields.Fields: write_field, read_field, read_field!
using GBGPeriodicFields.Fields: _component_view
using GBGPeriodicFields.Points:
  PointSet, AbstractPointValues,
  ScalarPointValues, VectorPointValues, TensorPointValues,
  point_positions, point_values, point_value_tensor_order, npoints
import GBGPeriodicFields.Points: write_points, read_points
using GBGPeriodicFields.Interpolation:
  AbstractTransferScheme, LalescuSpline, LagrangeSpline, DirectDFT, NUFFT, spline_coefficients
import GBGPeriodicFields.Interpolation: write_scheme, read_scheme

const SCHEMA_VERSION = 1
# A transfer scheme's group carries its own version, so renaming a scheme's parameters does not make
# older code refuse field and point files whose format never changed. Version 2 (2026-10-07, decision
# 98) names the splines' parameters `stencil_width` and `smoothness`; version 1 stored the half-width
# `neighbours` (the width being 2·neighbours + 2) and is still read.
const SCHEME_SCHEMA_VERSION = 2

# One type tag per concrete field type. The tensor order is not encoded in the tag — it is recovered from
# the stored array's dimensionality — but it is also written as an attribute for self-description.
_type_tag(::ScalarFieldPhysical) = "GBGPeriodicFields.ScalarFieldPhysical"
_type_tag(::ScalarFieldSpectral) = "GBGPeriodicFields.ScalarFieldSpectral"
_type_tag(::VectorFieldPhysical) = "GBGPeriodicFields.VectorFieldPhysical"
_type_tag(::VectorFieldSpectral) = "GBGPeriodicFields.VectorFieldSpectral"
_type_tag(::TensorFieldPhysical) = "GBGPeriodicFields.TensorFieldPhysical"
_type_tag(::TensorFieldSpectral) = "GBGPeriodicFields.TensorFieldSpectral"
_type_tag(::PointSet)            = "GBGPeriodicFields.PointSet"
_type_tag(::ScalarPointValues)   = "GBGPeriodicFields.ScalarPointValues"
_type_tag(::VectorPointValues)   = "GBGPeriodicFields.VectorPointValues"
_type_tag(::TensorPointValues)   = "GBGPeriodicFields.TensorPointValues"
# The scheme tags. `LalescuSpline` and `LagrangeSpline` are parameterized, so one method each covers
# every parameterization; the parameters that matter are stored as attributes, not in the tag.
_type_tag(::LalescuSpline)       = "GBGPeriodicFields.LalescuSpline"
_type_tag(::LagrangeSpline)      = "GBGPeriodicFields.LagrangeSpline"
_type_tag(::DirectDFT)           = "GBGPeriodicFields.DirectDFT"

# A point object carries its own array: a PointSet its (M, 3) coordinates, point values their samples.
_point_array(points::PointSet) = point_positions(points)
_point_array(values::AbstractPointValues) = point_values(values)


# --- write: create the subgroup, store the host array as `data` and the metadata as attributes ---

# The array HDF5 is handed: a host `Array` as it is, anything else (device storage, a wrapper)
# copied to the host. `Array(a)` alone copies even an `Array` — it is not a no-op on the CPU, which a
# comment here once claimed — so every checkpoint write copied the whole state (found 2026-10-01 by
# the consumer's temporary-memory ledger).
_host_array(a::Array) = a
_host_array(a::AbstractArray) = Array(a)


function write_field(parent::HDF5.H5DataStore, name::AbstractString, field::AbstractField)
  g = create_group(parent, name)
  g["data"] = _host_array(field_data(field))
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
  # The spacing is stored, not left to be recomputed. A Grid3D built through the four-argument
  # constructor may legitimately hold a spacing that only APPROXIMATELY equals domain_size ./ grid_size
  # (decision 45 accepts that), so recomputing it on read silently returned a different grid — and
  # every interpolation position and cell measure with it.
  a["grid_spacing"] = collect(grid.grid_spacing)
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

# The group-level checks both read verbs make before touching the data; `caller` names the verb so a
# message points at what the user called.
function _open_field_group(parent::HDF5.H5DataStore, name::AbstractString, caller::AbstractString)
  haskey(parent, name) ||
    throw(ArgumentError("$caller: no object named \"$name\" under the given parent"))
  g = parent[name]
  g isa HDF5.Group ||
    throw(ArgumentError("$caller: \"$name\" is a dataset, not a field group"))
  haskey(attrs(g), "type") || throw(ArgumentError(
    "$caller: group \"$name\" has no `type` attribute — it was not written by write_field"))
  tag = attrs(g)["type"]
  haskey(g, "data") || throw(ArgumentError(
    "$caller: field group \"$name\" has no `data` dataset — the group is incomplete"))
  for attribute in ("grid_size", "domain_size", "origin", "fft_dims")
    haskey(attrs(g), attribute) || throw(ArgumentError(
      "$caller: field group \"$name\" is missing the `$attribute` attribute — the group is incomplete"))
  end
  return g, tag
end


function read_field(parent::HDF5.H5DataStore, name::AbstractString)
  g, tag = _open_field_group(parent, name, "read_field")
  data = read(g["data"])
  _validate_field_schema(g, name, tag, eltype(data), ndims(data), "read_field")
  grid = _reconstruct_grid(g, real(eltype(data)))
  layout = RealFourierLayout(Tuple(Int.(attrs(g)["fft_dims"])))
  if tag == "GBGPeriodicFields.ScalarFieldPhysical"
    return ScalarFieldPhysical(data, grid; layout)
  elseif tag == "GBGPeriodicFields.ScalarFieldSpectral"
    return ScalarFieldSpectral(data, grid; layout)
  elseif tag == "GBGPeriodicFields.VectorFieldPhysical"
    return VectorFieldPhysical(data, grid; layout)
  elseif tag == "GBGPeriodicFields.VectorFieldSpectral"
    return VectorFieldSpectral(data, grid; layout)
  elseif tag == "GBGPeriodicFields.TensorFieldPhysical"
    return TensorFieldPhysical(data, grid; layout)
  elseif tag == "GBGPeriodicFields.TensorFieldSpectral"
    return TensorFieldSpectral(data, grid; layout)
  else
    throw(ArgumentError("read_field: unrecognized field type tag \"$tag\" in group \"$name\""))
  end
end


# Into a field that already exists: every stored property is checked against the destination before
# anything is written, from the dataset's metadata alone, so a refused read touches nothing.
function read_field!(destination::AbstractField, parent::HDF5.H5DataStore, name::AbstractString)
  g, tag = _open_field_group(parent, name, "read_field!")
  dataset = g["data"]
  _validate_field_schema(g, name, tag, eltype(dataset), ndims(dataset), "read_field!")
  tag == _type_tag(destination) || throw(ArgumentError(
    "read_field!: group \"$name\" holds a $(replace(tag, "GBGPeriodicFields." => "")), but the " *
    "destination is a $(nameof(typeof(destination)))"))
  storage = field_data(destination)
  # The precision is named by the field's real scalar type, never the complex storage element a field
  # in spectral representation keeps, complex arrays being storage detail (invariant 2).
  eltype(dataset) == eltype(storage) || throw(ArgumentError(
    "read_field!: group \"$name\" holds a $(real(eltype(dataset))) field, but the destination is " *
    "$(field_scalar_type(destination)); reading does not convert between precisions"))
  grid = _reconstruct_grid(g, field_scalar_type(destination))
  grid == field_grid(destination) || throw(ArgumentError(
    "read_field!: group \"$name\" was written on $(grid), but the destination is on " *
    "$(field_grid(destination))"))
  layout = RealFourierLayout(Tuple(Int.(attrs(g)["fft_dims"])))
  layout == field_layout(destination) || throw(ArgumentError(
    "read_field!: group \"$name\" was written with $(layout), but the destination has " *
    "$(field_layout(destination))"))
  # Grid and layout agree, so a differing array size can only be a differing tensor order.
  size(dataset) == size(storage) || throw(ArgumentError(
    "read_field!: group \"$name\" stores a field of tensor order $(ndims(dataset) - 3), but the " *
    "destination's is $(field_tensor_order(destination))"))
  _read_into!(storage, dataset, Val(field_tensor_order(destination)))
  return destination
end

# A host array is read straight into; anything else is staged one fiber component at a time
# through a host buffer of one component, so the transient is a component, never a field.
_read_into!(storage::Array, dataset, ::Val) = (copyto!(storage, dataset); nothing)

function _read_into!(storage::AbstractArray, dataset, ::Val{R}) where {R}
  buffer = Array{eltype(storage)}(undef, size(storage)[1:3])
  for component in 1:(3^R)
    fiber_index = Tuple(CartesianIndices(ntuple(_ -> 3, Val(R)))[component])
    copyto!(buffer, dataset, :, :, :, fiber_index...)
    copyto!(_component_view(storage, Val(R), component), buffer)
  end
  return nothing
end


# The group's self-describing attributes are CHECKED, not merely written. They were recorded for a
# human or an external tool and then ignored on read, so the package did not enforce its own schema: a
# file from a future version was accepted, and a group whose `representation`, `eltype` or
# `tensor_order` contradicted its type tag and its data reconstructed silently into whatever the tag
# said. Every attribute here is redundant with the tag or the data, which is exactly why a disagreement
# means the file is not what it claims to be.
# The version gate, shared by all three read verbs: a file from a future schema is refused rather
# than guessed at. `caller` names the verb so the message points at what the user called.
function _validate_schema_version(a, name::AbstractString, caller::AbstractString;
                                  understood::Integer = SCHEMA_VERSION)
  haskey(a, "version") || return nothing
  version = Int(a["version"])
  version <= understood || throw(ArgumentError(
    "$caller: group \"$name\" declares schema version $version, but this package understands " *
    "up to $understood — the file was written by a newer version"))
  return nothing
end


function _validate_field_schema(g, name, tag, element_type, dimensions, caller)
  a = attrs(g)
  _validate_schema_version(a, name, caller)
  if haskey(a, "representation")
    declared = a["representation"]
    implied = occursin("Spectral", tag) ? "spectral" : "physical"
    declared == implied || throw(ArgumentError(
      "$caller: group \"$name\" declares representation \"$declared\" but its type tag \"$tag\" is $implied"))
  end
  if haskey(a, "eltype")
    declared = a["eltype"]
    string(real(element_type)) == declared || throw(ArgumentError(
      "$caller: group \"$name\" declares eltype \"$declared\" but its data carries " *
      "$(real(element_type))"))
  end
  if haskey(a, "tensor_order")
    declared = Int(a["tensor_order"])
    # A field's data is the three base axes plus one axis per fiber index.
    implied = dimensions - 3
    declared == implied || throw(ArgumentError(
      "$caller: group \"$name\" declares tensor_order $declared but its data has $(dimensions) " *
      "dimensions, implying order $implied"))
  end
  return nothing
end

# The grid's real element type `T` is taken from the stored data, so it matches the field exactly. The
# spacing is read back when the file carries it, which makes the round trip exact even for a grid whose
# spacing is only approximately domain_size ./ grid_size; a file written before the attribute existed
# has it recomputed, which reproduces what that writer stored.
function _reconstruct_grid(g, ::Type{T}) where {T<:AbstractFloat}
  grid_size = Tuple(Int.(attrs(g)["grid_size"]))
  domain_size = Tuple(T.(attrs(g)["domain_size"]))
  origin = Tuple(T.(attrs(g)["origin"]))
  haskey(attrs(g), "grid_spacing") || return Grid3D(grid_size, domain_size; origin = origin)
  grid_spacing = Tuple(T.(attrs(g)["grid_spacing"]))
  return Grid3D(grid_size, domain_size, grid_spacing, origin)
end
# --- the point layer: same shape as the field methods above. A point object has no grid and no
# representation, so its group carries only the array, the element type, the point count, and — for
# values — the tensor order. Positions and values stay separate groups: they are separate objects, and
# several value sets often share one stored set of positions. ---

function write_points(parent::HDF5.H5DataStore, name::AbstractString,
    points::Union{PointSet, AbstractPointValues})

  g = create_group(parent, name)
  array = _point_array(points)
  g["data"] = _host_array(array)
  a = attrs(g)
  a["type"] = _type_tag(points)
  a["version"] = SCHEMA_VERSION
  a["eltype"] = string(eltype(array))        # stored for self-description; reconstruction uses `data`
  a["npoints"] = npoints(points)
  points isa AbstractPointValues && (a["tensor_order"] = point_value_tensor_order(points))
  return g
end


# the sugar: `parent[name] = points`, mirroring the field method above.
function Base.setindex!(parent::Union{HDF5.File,HDF5.Group},
    points::Union{PointSet, AbstractPointValues}, name::AbstractString)

  write_points(parent, name, points)
  return parent
end


function read_points(parent::HDF5.H5DataStore, name::AbstractString)
  haskey(parent, name) ||
    throw(ArgumentError("read_points: no object named \"$name\" under the given parent"))
  g = parent[name]
  g isa HDF5.Group ||
    throw(ArgumentError("read_points: \"$name\" is a dataset, not a point group"))
  haskey(attrs(g), "type") || throw(ArgumentError(
    "read_points: group \"$name\" has no `type` attribute — it was not written by write_points"))
  tag = attrs(g)["type"]
  # The version gate the field pair has always applied. Without it a point group written by a NEWER
  # schema was accepted and reconstructed as whatever its tag said — which the header's claim that
  # these attributes are "CHECKED, not merely written" was already asserting was impossible.
  _validate_schema_version(attrs(g), name, "read_points")
  haskey(g, "data") || throw(ArgumentError(
    "read_points: point group \"$name\" has no `data` dataset — the group is incomplete"))
  data = read(g["data"])
  if tag == "GBGPeriodicFields.PointSet"
    return PointSet(data)
  elseif tag == "GBGPeriodicFields.ScalarPointValues"
    return ScalarPointValues(data)
  elseif tag == "GBGPeriodicFields.VectorPointValues"
    return VectorPointValues(data)
  elseif tag == "GBGPeriodicFields.TensorPointValues"
    return TensorPointValues(data)          # the order follows the array's dimensionality
  else
    throw(ArgumentError("read_points: unrecognized point type tag \"$tag\" in group \"$name\""))
  end
end


# --- transfer schemes: a parameter record, not a section. No `data` dataset: a spline's weight
# matrix is DERIVED from (n, m), so storing the parameters is the faithful record and storing the
# weights would duplicate derived data — the same reasoning that has a consumer recompute plans,
# multipliers and scratch rather than store them. ---

# The element types a stored scheme may name, resolved through an explicit table. The obvious
# spelling — parse the string and evaluate it — would execute an arbitrary expression out of a file
# the package did not write, so the mapping is a closed set and anything else is refused.
const _SCHEME_ELTYPES = Dict("Float64" => Float64, "Float32" => Float32)

function _scheme_eltype(a, name::AbstractString)
  haskey(a, "eltype") || throw(ArgumentError(
    "read_scheme: scheme group \"$name\" has no `eltype` attribute — the group is incomplete"))
  declared = a["eltype"]
  haskey(_SCHEME_ELTYPES, declared) || throw(ArgumentError(
    "read_scheme: scheme group \"$name\" declares element type \"$declared\", which this package " *
    "does not build schemes in (expected one of $(join(sort(collect(keys(_SCHEME_ELTYPES))), ", ")))"))
  return _SCHEME_ELTYPES[declared]
end

function _scheme_parameter(a, name::AbstractString, key::AbstractString)
  haskey(a, key) || throw(ArgumentError(
    "read_scheme: scheme group \"$name\" has no `$key` attribute — the group is incomplete"))
  return Int(a[key])
end




function write_scheme(parent::HDF5.H5DataStore, name::AbstractString, scheme::LalescuSpline)
  g = create_group(parent, name)
  a = attrs(g)
  a["type"] = _type_tag(scheme)
  a["version"] = SCHEME_SCHEMA_VERSION
  a["eltype"] = string(eltype(spline_coefficients(scheme)))
  a["stencil_width"] = scheme.stencil_width
  a["smoothness"] = scheme.smoothness
  return g
end

function write_scheme(parent::HDF5.H5DataStore, name::AbstractString, scheme::LagrangeSpline)
  g = create_group(parent, name)
  a = attrs(g)
  a["type"] = _type_tag(scheme)
  a["version"] = SCHEME_SCHEMA_VERSION
  a["eltype"] = string(eltype(spline_coefficients(scheme)))
  a["stencil_width"] = scheme.stencil_width
  return g
end

function write_scheme(parent::HDF5.H5DataStore, name::AbstractString, scheme::DirectDFT)
  g = create_group(parent, name)
  a = attrs(g)
  a["type"] = _type_tag(scheme)
  a["version"] = SCHEME_SCHEMA_VERSION
  return g                                   # a singleton: the tag is the whole record
end

# The one refusal, and it states something about the object rather than marking a missing feature: a
# NUFFT owns oversampled plans and a deconvolution window built against a reference field, so it is a
# compiled schedule like `FieldTransformPlans` and is rebuilt, never stored.
function write_scheme(::HDF5.H5DataStore, ::AbstractString, ::NUFFT)
  throw(ArgumentError(
    "write_scheme: a NUFFT scheme is not persistable — it owns oversampled FFT plans and a " *
    "deconvolution window built against a reference field, which are derived objects rather than " *
    "parameters. Rebuild it from the reference field you restore anyway, `NUFFT(reference; tolerance)`, " *
    "and record the tolerance in your own snapshot if it varies."))
end


# The sugar, matching the field and point pairs. It heads off a foreseeable trap rather than existing
# for symmetry: a consumer who has written `g["u"] = field` and `g["x"] = points` will write
# `g["scheme"] = scheme` by analogy, and without this method HDF5 would try to store the struct as a
# dataset and fail obscurely.
function Base.setindex!(parent::Union{HDF5.File,HDF5.Group},
    scheme::AbstractTransferScheme, name::AbstractString)

  write_scheme(parent, name, scheme)
  return parent
end


function read_scheme(parent::HDF5.H5DataStore, name::AbstractString)
  haskey(parent, name) ||
    throw(ArgumentError("read_scheme: no object named \"$name\" under the given parent"))
  g = parent[name]
  g isa HDF5.Group ||
    throw(ArgumentError("read_scheme: \"$name\" is a dataset, not a scheme group"))
  a = attrs(g)
  haskey(a, "type") || throw(ArgumentError(
    "read_scheme: group \"$name\" has no `type` attribute — it was not written by write_scheme"))
  _validate_schema_version(a, name, "read_scheme"; understood = SCHEME_SCHEMA_VERSION)
  tag = a["type"]
  version = haskey(a, "version") ? Int(a["version"]) : 1
  # Version 1 stored the half-width `n`; the width is 2n + 2.
  width() = version >= 2 ? _scheme_parameter(a, name, "stencil_width") :
                           2 * _scheme_parameter(a, name, "neighbours") + 2
  # The constructors revalidate the parameters (a spline enforces 0 <= m <= 2n), so a group asserting
  # an impossible combination throws there rather than yielding a malformed scheme.
  if tag == "GBGPeriodicFields.LalescuSpline"
    # The stored element type is validated and not rebuilt: weights are kept in Float64 since
    # decision 101 and converted to the field's type at each launch, so the result is the same.
    _scheme_eltype(a, name)
    return LalescuSpline(width(); smoothness = _scheme_parameter(a, name, "smoothness"))
  elseif tag == "GBGPeriodicFields.LagrangeSpline"
    _scheme_eltype(a, name)
    return LagrangeSpline(width())
  elseif tag == "GBGPeriodicFields.DirectDFT"
    return DirectDFT()
  else
    throw(ArgumentError("read_scheme: unrecognized scheme type tag \"$tag\" in group \"$name\""))
  end
end


end # module GBGPeriodicFieldsHDF5Ext
