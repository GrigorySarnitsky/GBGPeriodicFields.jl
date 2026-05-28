# GBGPeriodicFields.jl

`GBGPeriodicFields.jl` is a package for representing, transforming, and manipulating scalar, vector, and tensor fields on three-dimensional rectangular periodic domains.

The package is aimed primarily at fluid-dynamics and turbulence simulations. Fields are physical objects, while physical-space and nonredundant spectral representations are storage and manipulation choices. The implementation is designed for both CPU and GPU array backends, and the package is intended to support later Lagrangian-particle and interpolation tools.

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

- [`Fields`](api/Fields.md): grids, Cartesian fiber types, field representations, FFT transforms, field utilities, and broadcasting support.
- [`FieldAlgebra`](api/FieldAlgebra.md): fiberwise algebraic operations on fields, including vector-space operations, scalar actions, vector products, tensor products, tensor contractions, norms, and tensor decompositions.

Global products, global norms, integration-based adjoints, and differential operators are intentionally outside the current algebra module.

## Documentation structure

### General documentation

```@contents
Pages = ["index.md"]
```

### API reference

```@contents
Pages = ["api.md", "api/GBGPeriodicFields.md", "api/Fields.md", "api/FieldAlgebra.md"]
```
