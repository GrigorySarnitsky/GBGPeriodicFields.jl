# Fields.jl

```@docs
GBGPeriodicFields.Fields
```

```@contents
Pages = ["Fields.md"]
```

## Fixed fiber types

```@docs
GBGPeriodicFields.Fields.FiberVector
GBGPeriodicFields.Fields.FiberTensor2
GBGPeriodicFields.Fields.FiberTensor3
GBGPeriodicFields.Fields.FiberTensor4
```

## Domain and Fourier layout

```@docs
GBGPeriodicFields.Fields.Grid3D
GBGPeriodicFields.Fields.RealFourierLayout
GBGPeriodicFields.Fields.validate_fft_dims
GBGPeriodicFields.Fields.rfft_shape
```

## Abstract field interface

```@docs
GBGPeriodicFields.Fields.AbstractFieldPhysical
GBGPeriodicFields.Fields.AbstractFieldSpectral
GBGPeriodicFields.Fields.field_data
GBGPeriodicFields.Fields.field_grid
GBGPeriodicFields.Fields.field_layout
GBGPeriodicFields.Fields.field_scalar_type
GBGPeriodicFields.Fields.field_tensor_order
GBGPeriodicFields.Fields.fiber_shape
GBGPeriodicFields.Fields.physical_field_shape
GBGPeriodicFields.Fields.spectral_field_shape
```

## Field types

```@docs
GBGPeriodicFields.Fields.ScalarFieldPhysical
GBGPeriodicFields.Fields.ScalarFieldSpectral
GBGPeriodicFields.Fields.VectorFieldPhysical
GBGPeriodicFields.Fields.VectorFieldSpectral
GBGPeriodicFields.Fields.TensorFieldPhysical
GBGPeriodicFields.Fields.TensorFieldSpectral
```

## Field utilities

These functions allocate fields with compatible metadata or check whether fields are compatible for representation-preserving operations. They are used internally by the field algebra and are documented here because they are part of the field infrastructure.

```@docs
GBGPeriodicFields.Fields.similar_field
GBGPeriodicFields.Fields.similar_physical_field
GBGPeriodicFields.Fields.similar_spectral_field
GBGPeriodicFields.Fields.check_field_compatibility
```

## Transforming between representations

```@docs
GBGPeriodicFields.Fields.FieldTransforms
GBGPeriodicFields.Fields.to_physical!
GBGPeriodicFields.Fields.to_spectral!
GBGPeriodicFields.Fields.to_physical
GBGPeriodicFields.Fields.to_spectral
```

## Broadcasting

Field broadcasting is storage-wise and representation-preserving. Dotted assignments write into the destination field storage, while field-valued out-of-place dotted expressions allocate a compatible field in the same representation.
