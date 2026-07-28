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

The point values carry the same fiberwise algebra as fields in physical representation, through the very same generics —
`add!`, `subtract!`, `combine!`, `multiply!`, `divide!`, `dot!`, `cross!`, `mul!`, `transpose!`,
`norm!`, `tr!`, `det!`, and the `sym`/`skew`/`dev` decompositions — extended here to accept
`AbstractPointValues`. There is no second set of docstrings for them: each per-component formula is
generated from one builder shared with `FieldAlgebra`, so the operations are documented once, on the
[FieldAlgebra](FieldAlgebra.md) page. Point values are representation-free, so the surface mirrors the
*physical* field surface only — there is nothing spectral to mirror.

## HDF5 persistence

Serialize a `PointSet` or a point-value section to, and reconstruct it from, an HDF5 file — the
point-layer twin of the field pair on the [Fields](Fields.md) page, for checkpointing the unstructured
base and its samples. Provided by a **package extension**, so these are available only when the `HDF5`
package is loaded; the core carries no HDF5 dependency. Each object becomes one self-describing HDF5
group, and the consumer owns the file. Positions and values are written separately, because they are
separate objects — a base, and sections over it — which also lets several value sets share one stored
set of positions.

```@docs
write_points
read_points
```

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
