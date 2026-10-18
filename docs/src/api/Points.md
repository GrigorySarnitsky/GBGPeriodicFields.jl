# Points

```@autodocs
Modules = [GBGPeriodicFields.Points]
Order   = [:module]
```

## Point and point-set types

```@docs
Point
PointSet
```

## Point-value types

```@docs
AbstractPointValues
ScalarPointValues
VectorPointValues
TensorPointValues
```

## Point accessor functions

```@docs
point_positions
point_values
point_value_tensor_order
npoints
```

## Point-value allocation

```@docs
similar_point_values
```

## Point-value algebra

The point values carry the same fiberwise algebra as fields in physical representation, through the
very same generics extended to accept [`AbstractPointValues`](@ref GBGPeriodicFields.AbstractPointValues). There is no second set of docstrings:
each operation is documented once, on the [`FieldAlgebra`](FieldAlgebra.md) page.

The weighted combination [`combine!`](@ref GBGPeriodicFields.combine!) is the one deliberate absence, and not for a mathematical reason:
it is linear and coefficientwise, so it would be perfectly well defined on point values. It exists on
fields because a solver's stage updates are the one place the fused axpby saves a whole pass over a
field; nothing needs it on points, so it has not been built, and a user should not read its absence as
a mathematical restriction.

## Base-space motion

Displacement moves the *points themselves*, where every operation above maps sections over a fixed
base and never moves a point.

```@docs
displace!
wrap!
```

## HDF5 persistence

```@docs
write_points
read_points
```

## Internal API

These symbols are not part of the public interface; they are documented for contributors — the
point-value broadcast style, the compatibility checks the algebra routes through, the shape and
unwrapping helpers, and the base-space motion internals — the coefficient conversion,
the fused displacement expression, the per-axis terms and the single-coordinate wrap. (The section-interface accessors the `FieldAlgebra` builders reuse — [`field_data`](@ref GBGPeriodicFields.field_data)
and the component accessors — are extended here but owned by `Fields`, so they are documented on that
page.)

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
