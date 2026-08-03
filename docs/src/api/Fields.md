# Fields

```@autodocs
Modules = [GBGPeriodicFields.Fields]
Order   = [:module]
```

## Base and layout types

```@docs
Grid3D
RealFourierLayout
```

## Field types

```@docs
GBGPeriodicFields.Fields.AbstractField
AbstractFieldPhysical
AbstractFieldSpectral
ScalarFieldPhysical
ScalarFieldSpectral
VectorFieldPhysical
VectorFieldSpectral
TensorFieldPhysical
TensorFieldSpectral
```

## Transform-plan and multiplier types

```@docs
FieldTransformPlans
FieldSpectralMultipliers
FieldSpectralMultipliers(::AbstractFieldSpectral)
```

## Transform operations

```@docs
to_physical!
to_physical
to_spectral!
to_spectral
```

## Field accessor functions

```@docs
field_data
field_grid
field_layout
field_scalar_type
field_tensor_order
physical_field_shape
spectral_field_shape
```

## Field allocation

```@docs
similar_field
```

## FFT thread configuration

```@docs
set_fft_threads!
```

## HDF5 persistence

Serialize a field to, and reconstruct it from, an HDF5 file — for checkpoint/restart, or to dump a
full-resolution snapshot for later analysis. Provided by a **package extension**, so these are available
only when the `HDF5` package is loaded; the core carries no HDF5 dependency. Each field becomes one
self-describing HDF5 group, and the consumer owns the file — every method takes an open `File` or `Group`,
so a whole iteration snapshot (several fields, plus the consumer's own time and iteration attributes) goes
into one file.

```@docs
write_field
read_field
```

## Internal API

These symbols are not part of the public interface; they are documented for contributors extending the package — field-allocation and compatibility helpers, the spectral-multiplier broadcast helpers, and the broadcast machinery.

### Types

```@autodocs
Modules = [GBGPeriodicFields.Fields]
Public  = false
Order   = [:type, :constant]
# `SpectralKernel` and `AbstractSpectralKernel` are documented on the Convolution page, beside the
# concrete kernel classes that subtype them: the protocol is DEFINED here so the differential
# operators and the reductions can name it, but a reader meets it there. They are public — the union
# appears in `convolve!`'s own signature — and were collected here only because this module does not
# re-export them, the same `Public = false` mechanism that filed `map` and `transpose` as internals.
Filter  = t -> !(t in (GBGPeriodicFields.Fields.AbstractField,
                       GBGPeriodicFields.Fields.SpectralKernel,
                       GBGPeriodicFields.Fields.AbstractSpectralKernel))
```

### Functions

```@autodocs
Modules = [GBGPeriodicFields.Fields]
Public  = false
Order   = [:function]
```
