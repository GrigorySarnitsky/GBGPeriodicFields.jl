# Interpolation

```@autodocs
Modules = [GBGPeriodicFields.Interpolation]
Order   = [:module]
```

The `Interpolation` module is the grid↔point transfer layer: **interpolation** (grid → point, the
gather ``\mathcal I = W``) evaluates a field at off-grid positions, and its adjoint **anterpolation**
(point → grid, the scatter ``\mathcal I^* = W^\top``) deposits per-point quantities back onto the grid. Both use the
local high-order splines of Lalescu, Teaca & Carati (2010) — the smooth [`LalescuSpline`](@ref)
(two-point Hermite, default [`CatmullRom`](@ref), pinned bit-for-bit to TurTLE) and the ``C^0``
[`LagrangeSpline`](@ref), under a shared `AbstractSplineScheme` — so interpolation and
anterpolation are exact transposes and conserve the deposited total (`docs/ARCHITECTURE.md` §10).
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

The scheme supertype `AbstractSplineScheme`, the spline-weight generators (Fornberg finite
differences + a small linear solve), the periodic cell-finding, and the in-kernel helpers —
documented for contributors.

```@autodocs
Modules = [GBGPeriodicFields.Interpolation]
Public  = false
Order   = [:type, :function]
```
