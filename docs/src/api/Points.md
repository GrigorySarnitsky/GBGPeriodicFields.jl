# Points

```@autodocs
Modules = [GBGPeriodicFields.Points]
Order   = [:module]
```

## Contents

```@contents
Pages = ["Points.md"]
Depth = 2:3
```

## Public API

### Point and point-set types

```@docs
Point
PointSet
```

### Point-value types

```@docs
AbstractPointValues
ScalarPointValues
VectorPointValues
TensorPointValues
```

### Point accessor functions

```@docs
point_coordinates
point_values
pointvalue_tensor_order
npoints
```

## Internal API

These symbols are not part of the public interface; they are documented for contributors
extending the package — the section interface the `FieldAlgebra` builders reuse, the allocator, the
broadcast style, and the alias guard.

### Types

```@autodocs
Modules = [GBGPeriodicFields.Points]
Public  = false
Order   = [:type, :constant]
```

### Functions

```@autodocs
Modules = [GBGPeriodicFields.Points]
Public  = false
Order   = [:function]
```
