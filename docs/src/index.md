# GBGPeriodicFields.jl

Welcome to `GBGPeriodicFields.jl`, a package for representing, transforming, and manipulating scalar, vector, and tensor fields on three-dimensional rectangular periodic domains.

The package is aimed primarily at fluid-dynamics and turbulence simulations, with physical-space and real-to-complex spectral representations designed for both CPU and GPU array backends. It also targets Lagrangian particle simulations through interpolation tools for evaluating fields between grid nodes.

This package is not intended to be a ready-to-use DNS solver; rather, it is a toolkit for building fluid-dynamics and general field solvers.

## Installation

This is an unregistered package, so it is not listed in the `General Julia` registry. To install it, run:

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

## Documentation structure

### General documentation

```@contents
Pages = ["index.md"]
```


### API reference

```@contents
Pages = ["api.md", "api/GBGPeriodicFields.md", "api/Fields.md"]
```