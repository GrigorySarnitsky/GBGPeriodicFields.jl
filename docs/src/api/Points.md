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
point_coordinates
point_values
pointvalue_tensor_order
npoints
```

## Point-value allocation

```@docs
similar_pointvalues
```

## Point-value algebra

The point values carry the same fiberwise algebra as physical fields, through the very same generics —
`add!`, `subtract!`, `combine!`, `multiply!`, `divide!`, `dot!`, `cross!`, `mul!`, `transpose!`,
`norm!`, `tr!`, `det!`, and the `sym`/`skew`/`dev` decompositions — extended here to accept
`AbstractPointValues`. There is no second set of docstrings for them: each per-component formula is
generated from one builder shared with `FieldAlgebra`, so the operations are documented once, on the
[FieldAlgebra](FieldAlgebra.md) page. Point values are representation-free, so the surface mirrors the
*physical* field surface only — there is nothing spectral to mirror.

## Internal API

These symbols are not part of the public interface; they are documented for contributors
extending the package — the section interface the `FieldAlgebra` builders reuse and the broadcast
style.

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
