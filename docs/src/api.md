# API overview

The package is an umbrella module (`GBGPeriodicFields`) that re-exports a set of submodules. The
include order reflects the dependency layering: `FiberSections` → `Fields` → `FieldAlgebra` →
`DifferentialOperators` → `Convolution` → `Points` → `Interpolation` → `Reductions`.

What each module is for is summarised on the [Home page](index.md); the pages below are its
reference.

```@contents
Pages = [
  "api/GBGPeriodicFields.md",
  "api/FiberSections.md",
  "api/Fields.md",
  "api/FieldAlgebra.md",
  "api/DifferentialOperators.md",
  "api/Convolution.md",
  "api/Points.md",
  "api/Interpolation.md",
  "api/Reductions.md",
]
Depth = 2
```
