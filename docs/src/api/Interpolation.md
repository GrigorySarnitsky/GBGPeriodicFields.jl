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

## Visit order

An order is an option on the transfer operations above, not an operation on the sections themselves:
it changes the sequence in which the points are visited and never the result.

```@docs
TransferOrder
transfer_order
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

## Scheme persistence

```@docs
write_scheme
read_scheme
```

## Internal API

These symbols are not part of the public interface; they are documented for contributors — the scheme
supertype `AbstractSplineScheme`, the spline-weight generators (Fornberg finite differences plus a
small linear solve), the periodic cell-finding, and the compatibility checks the transfer verbs route
through.

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
