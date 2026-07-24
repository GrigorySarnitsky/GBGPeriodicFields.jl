# GBGPeriodicFields.jl

This package provides tools for representing, transforming, and manipulating scalar, vector, and tensor fields on three-dimensional rectangular periodic domains.

The package is aimed primarily at fluid-dynamics and turbulence simulations, with physical-space and real-to-complex spectral representations designed for both CPU and GPU array backends. It also targets Lagrangian particle simulations through interpolation tools for evaluating fields between grid nodes.

The package's primary consumer is [`GBGIsotropicTurbulence.jl`](https://grigorysarnitsky.github.io/GBGIsotropicTurbulence.jl), a pseudospectral direct numerical simulation of homogeneous isotropic turbulence built on these fields — the place to see the field layer driving a full solver.

The `GBG` part in the name `GBGPeriodicFields.jl` comes from the city of Göteborg (Gothenburg, Sweden), where the primary development took place.

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

## Documentation

Documentation with the full API reference is available at [https://grigorysarnitsky.github.io/GBGPeriodicFields.jl/](https://grigorysarnitsky.github.io/GBGPeriodicFields.jl/).

