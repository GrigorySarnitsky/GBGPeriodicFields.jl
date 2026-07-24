# Interpolation

```@autodocs
Modules = [GBGPeriodicFields.Interpolation]
Order   = [:module]
```

## Transfer operations

```@docs
interpolate!
interpolate
GBGPeriodicFields.Fields.AbstractFieldPhysical(::Any)
anterpolate!
anterpolate
```

## Transfer-scheme types

```@docs
AbstractTransferScheme
LalescuSpline
CatmullRom
LagrangeSpline
DirectDFT
NUFFT
```

## Internal API

These symbols are not part of the public interface; they are documented for contributors — the scheme
supertype `AbstractSplineScheme`, the spline-weight generators (Fornberg finite differences plus a
small linear solve), the periodic cell-finding, and the in-kernel helpers.

### Types

```@autodocs
Modules = [GBGPeriodicFields.Interpolation]
Public  = false
Order   = [:type, :constant]
Filter  = t -> t !== GBGPeriodicFields.Fields.AbstractFieldPhysical
```

### Functions

```@autodocs
Modules = [GBGPeriodicFields.Interpolation]
Public  = false
Order   = [:function]
Filter  = t -> t !== GBGPeriodicFields.Fields.AbstractFieldPhysical
```
