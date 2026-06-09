# Interpolation

```@autodocs
Modules = [GBGPeriodicFields.Interpolation]
Order   = [:module]
```

The `Interpolation` module is the (in-progress) Lagrangian transfer layer: evaluating fields at
off-grid positions and depositing per-point quantities back onto the grid. It currently provides
the data types for the *unstructured base* — positions and the field values there — reusing the
package's fibers; the transfer kernels (interpolation / anterpolation) are not yet implemented.

- **Positions** — `Point` (a single coordinate triple, an alias of `FiberVector`) and `PointSet`
  (a structure-of-arrays collection of `M` positions, grid-free).
- **Point values** — `ScalarPointValues` / `VectorPointValues` / `TensorPointValues` under
  `AbstractPointValues`: field values sampled at the `M` points, mirroring the field tensor
  orders, representation-free.

## Contents

```@contents
Pages = ["Interpolation.md"]
Depth = 2:3
```

## Index

```@index
Modules = [GBGPeriodicFields.Interpolation]
```

## Public API

### Types

```@autodocs
Modules = [GBGPeriodicFields.Interpolation]
Public  = true
Private = false
Order   = [:type, :constant]
```

### Functions

```@autodocs
Modules = [GBGPeriodicFields.Interpolation]
Public  = true
Private = false
Order   = [:function]
```

## Internal API

These symbols are not part of the public interface; they are documented for contributors
extending the package.

### Functions

```@autodocs
Modules = [GBGPeriodicFields.Interpolation]
Public  = false
Order   = [:function]
```
