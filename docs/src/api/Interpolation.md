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
