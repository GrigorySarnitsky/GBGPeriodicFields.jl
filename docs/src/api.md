# API overview

The package is an umbrella module (`GBGPeriodicFields`) that re-exports a set of submodules. The
include order reflects the dependency layering: `FiberSections` → `Fields` → `FieldAlgebra` →
`DifferentialOperators` → `Points` → `Interpolation`.

- [GBGPeriodicFields](api/GBGPeriodicFields.md): the top-level module and public re-export surface.
- [FiberSections](api/FiberSections.md): the base-agnostic foundation — the `AbstractFiberSection` supertype, the `_assign!` threading primitive, and the fiberwise-algebra code generators reused by `FieldAlgebra` and `Points`.
- [Fields](api/Fields.md): grids, Cartesian fiber types, field representations, FFT transforms, field utilities, and broadcasting support.
- [FieldAlgebra](api/FieldAlgebra.md): fiberwise algebraic operations on scalar, vector, and tensor fields.
- [DifferentialOperators](api/DifferentialOperators.md): spectral differential operators on fields in spectral representation.
- [Points](api/Points.md): the unstructured-base point and point-value data types and their fiberwise algebra.
- [Interpolation](api/Interpolation.md): the grid↔point transfer — interpolation (gather) and anterpolation (scatter) via the local Lalescu splines.

```@contents
Pages = [
  "api/GBGPeriodicFields.md",
  "api/FiberSections.md",
  "api/Fields.md",
  "api/FieldAlgebra.md",
  "api/DifferentialOperators.md",
  "api/Points.md",
  "api/Interpolation.md",
]
Depth = 2
```
