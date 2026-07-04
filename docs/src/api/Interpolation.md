# Interpolation

```@autodocs
Modules = [GBGPeriodicFields.Interpolation]
Order   = [:module]
```

## Contents

```@contents
Pages = ["Interpolation.md"]
Depth = 2:3
```

## Public API

### Transfer operations

```@docs
interpolate!
interpolate
anterpolate!
anterpolate
```

### Transfer-scheme types

```@docs
AbstractTransferScheme
LalescuSpline
CatmullRom
LagrangeSpline
DirectDFT
NUFFT
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
