# Fields

```@autodocs
Modules = [GBGPeriodicFields.Fields]
Order   = [:module]
```

## Fiber types

```@docs
FiberVector
FiberTensor2
FiberTensor3
FiberTensor4
```

## Base and layout types

```@docs
Grid3D
RealFourierLayout
```

## Field types

```@docs
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
fiber_shape
physical_field_shape
spectral_field_shape
```

## FFT thread configuration

```@docs
set_fft_threads!
```

## Internal API

These symbols are not part of the public interface; they are documented for contributors extending the package — field-allocation and compatibility helpers, the spectral-multiplier broadcast helpers, and the broadcast machinery.

### Types

```@autodocs
Modules = [GBGPeriodicFields.Fields]
Public  = false
Order   = [:type, :constant]
```

### Functions

```@autodocs
Modules = [GBGPeriodicFields.Fields]
Public  = false
Order   = [:function]
```
