# Interpolation

```@autodocs
Modules = [GBGPeriodicFields.Interpolation]
Order   = [:module]
```

The `Interpolation` module is the grid↔point transfer layer: **interpolation** (grid → point, the
gather `𝓘 = W`) evaluates a field at off-grid positions, and its adjoint **anterpolation**
(point → grid, the scatter `𝓘* = Wᵀ`) deposits per-point quantities back onto the grid. Both use the
local high-order spline of Lalescu, Teaca & Carati (2010) via a shared [`LalescuSpline`](@ref)
scheme, so they are exact transposes and conserve the deposited total (`docs/ARCHITECTURE.md` §10).
The kernels are portable across CPU / CUDA / AMDGPU (KernelAbstractions); the point-data types live
in the [`Points`](Points.md) module.

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

The spline-weight generator (Fornberg finite differences + a small linear solve), the periodic
cell-finding, and the in-kernel helpers — documented for contributors.

```@autodocs
Modules = [GBGPeriodicFields.Interpolation]
Public  = false
Order   = [:function]
```
