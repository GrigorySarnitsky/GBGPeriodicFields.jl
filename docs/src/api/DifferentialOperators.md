# DifferentialOperators

```@autodocs
Modules = [GBGPeriodicFields.DifferentialOperators]
Order   = [:module]
```

The `DifferentialOperators` module provides spectral differential operators on the fields defined in [`Fields`](Fields.md): `gradient`, `divergence`, `curl`, `laplacian`, `inverse_laplacian`, and `helmholtz_projection`, each with an in-place `!` form and an allocating form.

The operators act on fields in **spectral representation** and are coefficientwise: differentiation is multiplication by the wavenumber multipliers held in a `FieldSpectralMultipliers` (built from a field with `FieldSpectralMultipliers(field)`, or from the explicit six-array constructor). The `laplacian`, `inverse_laplacian`, and `helmholtz_projection` are representation-preserving; `gradient`/`divergence`/`curl` change tensor order as the operator dictates.

The Nyquist convention is handled by the multipliers (see `FieldSpectralMultipliers` in [`Fields`](Fields.md)): first-derivative wavenumbers are zeroed at the Nyquist mode on even-length axes, while squared wavenumbers keep the true `k²`.

## Contents

```@contents
Pages = ["DifferentialOperators.md"]
Depth = 2:3
```

## Index

```@index
Modules = [GBGPeriodicFields.DifferentialOperators]
```

## Public API

### Functions

```@autodocs
Modules = [GBGPeriodicFields.DifferentialOperators]
Public  = true
Private = false
Order   = [:function]
```

## Internal API

The coefficientwise spectral kernels and the aliasing-aware wrappers, documented for contributors.

### Functions

```@autodocs
Modules = [GBGPeriodicFields.DifferentialOperators]
Public  = false
Order   = [:function]
```
