# Fields.jl

```@docs
GBGPeriodicFields.Fields
```

```@contents
Pages = ["Fields.md"]
```

## Periodic Domain Layout 

```@docs
GBGPeriodicFields.Fields.Grid3D
GBGPeriodicFields.Fields.RealFourierLayout
```

## Field Types

```@docs
GBGPeriodicFields.Fields.AbstractFieldPhysical
GBGPeriodicFields.Fields.AbstractFieldSpectral
GBGPeriodicFields.Fields.ScalarFieldPhysical
GBGPeriodicFields.Fields.ScalarFieldSpectral
GBGPeriodicFields.Fields.VectorFieldPhysical
GBGPeriodicFields.Fields.VectorFieldSpectral
GBGPeriodicFields.Fields.TensorFieldPhysical
GBGPeriodicFields.Fields.TensorFieldSpectral
```

## Accessing Field data and metadata
```@docs
GBGPeriodicFields.Fields.field_data
GBGPeriodicFields.Fields.field_grid
GBGPeriodicFields.Fields.field_layout
GBGPeriodicFields.Fields.field_scalar_type
GBGPeriodicFields.Fields.field_tensor_order
GBGPeriodicFields.Fields.fiber_shape
GBGPeriodicFields.Fields.physical_field_shape
GBGPeriodicFields.Fields.spectral_field_shape
```

## Transforming between representations in physical and spectral spaces
```@docs
GBGPeriodicFields.Fields.FieldTransforms
GBGPeriodicFields.Fields.to_physical!
GBGPeriodicFields.Fields.to_spectral!
GBGPeriodicFields.Fields.to_physical
GBGPeriodicFields.Fields.to_spectral
```

## Internal helper functions

The following functions are not exported. They are implementation helpers used by field construction, transforms, and broadcasting.

```@docs
GBGPeriodicFields.Fields.rfft_shape
GBGPeriodicFields.Fields.validate_fft_dims
GBGPeriodicFields.Fields.similar_physical_field
GBGPeriodicFields.Fields.similar_spectral_field
GBGPeriodicFields.Fields.similar_field
GBGPeriodicFields.Fields.check_field_compatibility
```