# GBGPeriodicFields.jl

This package provides tools for representing, transforming, and manipulating scalar, vector, and tensor fields on three-dimensional rectangular periodic domains. The tensors are **Cartesian** — components on one fixed orthonormal frame, with no curvilinear coordinates and no metric machinery — so this is an applied field toolkit rather than a general differential-geometry package.

The package is aimed primarily at fluid-dynamics and turbulence simulations, with physical-space and real-to-complex spectral representations designed for both CPU and GPU array backends, with HDF5 field persistence. It also targets Lagrangian particle simulations through interpolation tools for evaluating fields between grid nodes.

The package's primary consumer is [`GBGHomogeneousTurbulence.jl`](https://grigorysarnitsky.github.io/GBGHomogeneousTurbulence.jl), a pseudospectral direct numerical simulation of homogeneous isotropic turbulence built on these fields — the place to see the field layer driving a full solver.

The `GBG` part in the name `GBGPeriodicFields.jl` comes from the city of Göteborg (Gothenburg, Sweden), where the primary development took place.

## Installation

The package's releases are listed in its own registry, GBGRegistry, alongside Julia's `General`.
Add both registries once, then install the package by name, which gives its latest release:

```julia
using Pkg
Pkg.Registry.add("General")
Pkg.Registry.add(url = "https://github.com/GrigorySarnitsky/GBGRegistry.git")
Pkg.add("GBGPeriodicFields")
```

or, in the package REPL:

```julia
]registry add General https://github.com/GrigorySarnitsky/GBGRegistry.git
]add GBGPeriodicFields
```

From then on `Pkg.update()` moves the package only from one release to the next.

Then you can use it as usual:

```julia
using GBGPeriodicFields
```

## Documentation

Documentation with the full API reference is available at [https://grigorysarnitsky.github.io/GBGPeriodicFields.jl/](https://grigorysarnitsky.github.io/GBGPeriodicFields.jl/).

