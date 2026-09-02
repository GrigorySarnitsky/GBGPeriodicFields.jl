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

The point values carry the same fiberwise algebra as fields in physical representation, through the very same generics —
`add!`, `subtract!`, `multiply!`, `divide!`, `dot!`, `cross!`, `mul!`, `transpose!`,
`norm!`, `tr!`, `det!`, the `sym`/`skew`/`dev` decompositions, and the arbitrary-fiber-map
`map!`/`map` — extended here to accept `AbstractPointValues`. A `PointSet` and any point values also
move between storage families through `adapt`, documented with its generic on the [`Fields`](Fields.md) page. (The `combine!` combination is deliberately absent, and for the **no-consumer** reason rather than a mathematical
one: the weighted combination is linear and coefficientwise, so it would be perfectly well defined on
point-values. It exists on fields because a solver's stage updates are the one place the fused axpby saves a whole
pass over a field; nothing asks it of the point layer, so it is unbuilt rather than
invalid — the package declines speculative structure, and this absence is that rule at work rather
than a mathematical restriction a user could rely on.) There is no second set of docstrings for them: each per-component formula is
generated from one builder shared with `FieldAlgebra`, so the operations are documented once, on the
[`FieldAlgebra`](FieldAlgebra.md) page. Point values are representation-free, so the surface mirrors the
*physical* field surface only — there is nothing spectral to mirror.

## Base-space motion

Displacement moves the *points themselves* — the one operation family that couples the base and the
fiber, where the algebra above maps sections to sections and never moves a point. Each point is
carried along the weighted sum of vector values over it; without a grid the motion happens in
unwrapped coordinates, and with a grid it lands back in the periodic box in the same fused pass.
There is deliberately no `+` between a `PointSet` and a `VectorPointValues` — positions are
locations, not vectors — and no allocating sibling, displacement being motion of an existing base.

```@docs
displace!
wrap!
```

## HDF5 persistence

Serialize a `PointSet` or a point-value section to, and reconstruct it from, an HDF5 file — the
point-layer twin of the field pair on the [`Fields`](Fields.md) page, for checkpointing the unstructured
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

These symbols are not part of the public interface; they are documented for contributors — the
point-value broadcast style, the compatibility checks the algebra routes through, the shape and
unwrapping helpers, and the base-space motion internals of decision 73 — the coefficient conversion,
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
