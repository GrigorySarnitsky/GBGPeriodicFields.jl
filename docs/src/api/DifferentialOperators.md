# DifferentialOperators

```@autodocs
Modules = [GBGPeriodicFields.DifferentialOperators]
Order   = [:module]
```

## Public API

### First-order differential operators

```@docs
gradient!
gradient
divergence!
divergence
curl!
curl
```

### Second-order differential operators

```@docs
laplacian!
laplacian
inverse_laplacian!
inverse_laplacian
```

### Projection operators

```@docs
helmholtz_projection!
helmholtz_projection
```

## Internal API

The coefficientwise spectral kernels and the aliasing-aware wrappers, documented for contributors.

### Functions

```@autodocs
Modules = [GBGPeriodicFields.DifferentialOperators]
Public  = false
Order   = [:function]
```
