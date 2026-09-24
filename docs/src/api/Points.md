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
very same generics extended to accept `AbstractPointValues`. There is no second set of docstrings:
each operation is documented once, on the [`FieldAlgebra`](FieldAlgebra.md) page.

The weighted combination `combine!` is the one deliberate absence, and for the **no-consumer** reason
rather than a mathematical one: it is linear and coefficientwise, so it would be perfectly well defined
on point values. It exists on fields because a solver's stage updates are the one place the fused axpby
saves a whole pass over a field; nothing asks it of the point layer, so it is unbuilt rather than
invalid — the package declines speculative structure, and this absence is that rule at work rather
than a mathematical restriction a user could rely on.

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
the fused displacement expression, the per-axis terms and the single-coordinate wrap. (The section-interface accessors the `FieldAlgebra` builders reuse — `field_data`
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
