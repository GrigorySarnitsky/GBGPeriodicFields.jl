# DifferentialOperators

```@autodocs
Modules = [GBGPeriodicFields.DifferentialOperators]
Order   = [:module]
```

## First-order differential operators

```@docs
gradient!
gradient
divergence!
divergence
curl!
curl
symmetric_gradient!
symmetric_gradient
```

## Second-order differential operators

```@docs
laplacian!
laplacian
inverse_laplacian!
inverse_laplacian
```

## Projection operators

```@docs
helmholtz_projection!
helmholtz_projection
```

## Internal API

These symbols are not part of the public interface; they are documented for contributors. The coefficientwise spectral kernels and the one-pass projection launcher, documented for
contributors.

```@autodocs
Modules = [GBGPeriodicFields.DifferentialOperators]
Public  = false
Order   = [:function]
```
