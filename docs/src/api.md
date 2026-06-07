# API overview

This package is structured as an umbrella module re-exporting three submodules:

- [GBGPeriodicFields](api/GBGPeriodicFields.md): the top-level module and public re-export surface.
- [Fields](api/Fields.md): grids, Cartesian fiber types, field representations, FFT transforms, field utilities, and broadcasting support.
- [FieldAlgebra](api/FieldAlgebra.md): fiberwise algebraic operations on scalar, vector, and tensor fields.
- [DifferentialOperators](api/DifferentialOperators.md): spectral differential operators on fields in spectral representation.

```@contents
Pages = [
  "api/GBGPeriodicFields.md",
  "api/Fields.md",
  "api/FieldAlgebra.md",
  "api/DifferentialOperators.md",
]
Depth = 2
```
