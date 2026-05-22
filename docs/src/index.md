# GBGCloudPhysics.jl

Welcome to `GBGCloudPhysics.jl`, a package for simulating cloud microphysics developed in Gothenburg.

The package grew from our code used in

* Sarnitsky G, Sardina G, Svensson G, Pumir A, Hoffmann F, Mehlig B. [Does small-scale turbulence matter for ice growth in mixed-phase clouds?](https://doi.org/10.1103/PhysRevFluids.10.053803) Physical Review Fluids. 2025 May;10(5):053803.
* Wang A, Chen S, Krueger S, Dziekan P, Enokido K, Hoffmann F, Makulska A, Mehlig B, Sardina G, Sarnitsky G, Schmalfuß S. [A model intercomparison study of mixed-phase clouds in a laboratory chamber.](https://arxiv.org/abs/2512.09915) arXiv preprint arXiv:2512.09915. 2025 Dec 10.

## Installation

This is an unregistered package, so it is not listed in the `General Julia` registry. To install it, run:

```julia
]add https://github.com/GrigorySarnitsky/GBGCloudPhysics.jl
```

or

```julia
using Pkg

Pkg.add(url="https://github.com/GrigorySarnitsky/GBGCloudPhysics.jl")
```

Then you can use it as usual:

```julia
using GBGCloudPhysics
```

## Documentation structure

### General documentation

```@contents
Pages = ["index.md", "development.md"]
```


### API reference

```@contents
Pages = ["api.md", "api/GBGCloudPhysics.md", "api/Thermodynamics.md", "api/ParcelModel.md", "api/StatisticalModel.md"]
```