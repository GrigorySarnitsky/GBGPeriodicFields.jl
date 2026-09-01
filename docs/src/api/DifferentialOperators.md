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
inverse_curl!
inverse_curl
```

## Projection operators

```@docs
helmholtz_projection!
helmholtz_projection
```

## Internal API

These symbols are not part of the public interface; they are documented for contributors — the
coefficientwise spectral kernels each operator applies per mode, and the gated CPU loops — "gated" meaning a
loop that consults the threading setting before splitting — that mirror them expression for
expression so a threaded run agrees with a device one bitwise.

```@autodocs
Modules = [GBGPeriodicFields.DifferentialOperators]
Public  = false
Order   = [:function]
```
