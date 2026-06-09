# GBGPeriodicFields.jl

`GBGPeriodicFields.jl` is a package for representing, transforming, and manipulating scalar, vector, and tensor fields on three-dimensional rectangular periodic domains.

The package is aimed primarily at fluid-dynamics and turbulence simulations. Fields are physical objects, while physical-space and nonredundant spectral representations are storage and manipulation choices. The implementation is designed for both CPU and GPU array backends, and includes an unstructured **point layer**: evaluating fields at off-grid positions (interpolation) and depositing per-point quantities back onto the grid (anterpolation) — the field layer for Lagrangian-particle methods.

This package is not intended to be a ready-to-use DNS solver; rather, it is a toolkit for building fluid-dynamics and general field solvers.

## Installation

This is an unregistered package, so it is not listed in the `General` Julia registry. To install it, run:

```julia
]add https://github.com/GrigorySarnitsky/GBGPeriodicFields.jl
```

or

```julia
using Pkg

Pkg.add(url="https://github.com/GrigorySarnitsky/GBGPeriodicFields.jl")
```

Then you can use it as usual:

```julia
using GBGPeriodicFields
```

## Main components

- [`FiberSections`](api/FiberSections.md): the base-agnostic foundation — the `AbstractFiberSection` supertype shared by fields and point-values, the CPU-threading primitive, and the fiberwise-algebra code generators (each per-component formula written once, reused by `FieldAlgebra` and `Points`).
- [`Fields`](api/Fields.md): grids, Cartesian fiber types, field representations (physical and spectral), FFT transforms, field utilities, and broadcasting support.
- [`FieldAlgebra`](api/FieldAlgebra.md): fiberwise algebraic operations on fields — vector-space operations, scalar actions, vector and tensor products, contractions, norms, and tensor decompositions.
- [`DifferentialOperators`](api/DifferentialOperators.md): spectral differential operators — gradient, divergence, curl, Laplacian, inverse Laplacian, and Helmholtz projection.
- [`Points`](api/Points.md): the unstructured base — point and point-value data types (`Point`, `PointSet`, the `PointValues`) and their full fiberwise algebra, mirroring the physical field surface.
- [`Interpolation`](api/Interpolation.md): the grid↔point transfer — interpolation (gather) and anterpolation (scatter) via the local Lalescu splines, as portable CPU/CUDA/AMDGPU kernels.

Global products, global norms, and integration-based adjoints are intentionally outside the algebra; spectral differential operators live in the separate `DifferentialOperators` module.

## Documentation structure

### Design & internals

- [Architecture](architecture.md): why the package is built as it is — the fiber-bundle model, representation validity (the method set is the spec), the code-generation architecture, the spectral machinery, CPU threading, and the grid↔point transfer.
- [Testing](testing.md): how the tests are built and the per-operation coverage contract.
- [Performance](performance.md): the performance model, externally-sourced best practices, the recorded optimization findings, and the tracked benchmark suite.

### API reference

```@contents
Pages = [
  "api.md",
  "api/GBGPeriodicFields.md",
  "api/FiberSections.md",
  "api/Fields.md",
  "api/FieldAlgebra.md",
  "api/DifferentialOperators.md",
  "api/Points.md",
  "api/Interpolation.md",
]
```
