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

Serialize a transfer scheme to, and reconstruct it from, an HDF5 group, so a checkpoint restores not
only where a point set samples but *how*. Provided by a **package extension**, available only when
the `HDF5` package is loaded; the core carries no HDF5 dependency. A scheme is a parameter record
rather than a section, so its group holds attributes and no dataset: the weight coefficients are
derived from the parameters and recomputed on read. `NUFFT` is deliberately excluded — it owns FFT
plans built against a reference field, so it is rebuilt rather than stored, and passing one throws.

```@docs
write_scheme
read_scheme
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
