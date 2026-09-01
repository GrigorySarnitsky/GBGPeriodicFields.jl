# GBGPeriodicFields.jl

`GBGPeriodicFields.jl` is a package for representing, transforming, and manipulating scalar, vector, and tensor fields on three-dimensional rectangular periodic domains. The tensors are **Cartesian** — components on one fixed orthonormal frame, with no curvilinear coordinates and no metric machinery — so this is an applied field toolkit rather than a general differential-geometry package.

The package is aimed primarily at fluid-dynamics and turbulence simulations. Fields are physical objects, while physical-space and nonredundant spectral representations are storage and manipulation choices. The implementation is designed for both CPU and GPU array backends, with HDF5 field persistence, and includes an unstructured **point layer**: evaluating fields at off-grid positions (interpolation) and depositing per-point quantities back onto the grid (anterpolation) — the field layer for Lagrangian-particle methods.

This package is not intended to be a ready-to-use DNS solver; rather, it is a toolkit for building fluid-dynamics and general field solvers.

[`GBGIsotropicTurbulence.jl`](https://grigorysarnitsky.github.io/GBGIsotropicTurbulence.jl) is such a solver, and the package's primary consumer: a pseudospectral direct numerical simulation of homogeneous isotropic turbulence built on these periodic fields. Its documentation shows this package in earnest — driving a complete solver, not a worked example.

A few words of vocabulary, used throughout the docs. A **field** — and its off-grid **point-values** — is a *section*: one **fiber** value (a scalar, a vector, or a second-order tensor) attached to every point of a **base** (the structured grid, or an unstructured set of points). The operations group as: pointwise algebra within the fiber; differential operators, applied as spectral multipliers; periodic convolution with a kernel; reductions against the base's own **measure** (a grid cell's volume, a point's count of one), giving a number or a radial profile; and the grid↔point transfer. Each group is catalogued under Main components below. Why they are grouped that way is the [Architecture](architecture.md) page; you do not need it to use the package.

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

New here? Start with the **[Getting started](tutorial.md)** tour — a short, runnable walkthrough of
grids, fields, representations, operators, reductions, and the point transfer. For a full solver, the
**[Examples](examples/hist_cpu.md)** page walks through a complete forced-HIT pseudospectral DNS built
on the package — the performance-first, allocation-free pattern, with results.

## Main components

- [`FiberSections`](api/FiberSections.md): the base-agnostic foundation — the Cartesian fiber types (`FiberVector`, `FiberTensor2`/`3`/`4`) naming the value at one base point, the `AbstractFiberSection` supertype shared by fields and point-values, the CPU-threading primitive, and the fiberwise-algebra code generators (each per-component formula written once, reused by `FieldAlgebra` and `Points`).
- [`Fields`](api/Fields.md): the core types — grids, fields in their physical and spectral representations, and the FFT transforms between them. The machinery the other modules build on sits here too: allocation, broadcasting, HDF5 persistence, the spectral-kernel supertype, and `adapt`/`adapt!`, which move a field, its multipliers, kernels or plans between host and device.
- [`FieldAlgebra`](api/FieldAlgebra.md): fiberwise algebraic operations on fields — vector-space operations, scalar actions, vector and tensor products, contractions, norms, and tensor decompositions, plus `map!`/`map`, which apply an arbitrary fiber map at every base point and so cover any pointwise operation the module does not name.
- [`DifferentialOperators`](api/DifferentialOperators.md): differential operators applied as spectral multipliers — gradient, divergence, curl, the inverse curl, the fused symmetric gradient, Laplacian, inverse Laplacian, and Helmholtz projection.
- [`Convolution`](api/Convolution.md): periodic convolution of a field with a kernel, in spectral representation — `convolve`/`convolve!` (infix `⋆`) apply it as the coefficientwise product of the transforms. A kernel is its own kind of object rather than a field, in four interchangeable storage classes; the builders cover sharp cutoff and band-pass masks, the assignment window, a translation phase, and any radial symbol.
- [`Points`](api/Points.md): the unstructured base — point and point-value data types (`Point`, `PointSet`, the `AbstractPointValues` types), their full fiberwise algebra mirroring the field surface in physical representation (including the arbitrary-fiber-map `map!`/`map`), the base-space motion pair `displace!`/`wrap!` (points moved along coefficient-weighted vector sections, in unwrapped coordinates or reduced to the periodic box), and HDF5 persistence.
- [`Interpolation`](api/Interpolation.md): the grid↔point transfer — interpolation (gather ``W``) and anterpolation (scatter ``W^\top``), an adjoint pair, exactly L²-adjoint once rescaled by ``N/M`` ([Formalization](formalization.md)). The scheme is a choice: local physical-domain splines, the exact spectral `DirectDFT`, or the fast `NUFFT`. All are portable across CPU/CUDA/AMDGPU, and a scheme persists alongside the points it samples.
- [`Reductions`](api/Reductions.md): the L²/measure structure — reductions that integrate the base away against its measure, over fields and point-values alike: the extensive `integral`, the normalized `inner`/`l2norm`/`lpnorm`, the moments `mean`/`std`/`var`/`cov`, `maximum`/`minimum`/`extrema`, and the spectral-only, multiplier-weighted `weighted_inner`. Several act on a field in spectral representation too, returning the same value with no transform. The radial pair `radial_spectrum` and `radial_correlation` resolve the pairing over wavenumber or separation shells.

Pointwise (fiberwise) products and norms live in `FieldAlgebra`; their *global* counterparts — integrals, the L² inner product and norms — live in `Reductions`. The differential operators, applied as spectral multipliers, live in the separate
`DifferentialOperators` module, and periodic convolution (apply a Fourier kernel) in `Convolution`.

## Documentation structure

### Start here

- [Getting started](tutorial.md): the guided tour, from a `Grid3D` to a transform, an operator and a reduction.
- [Examples](examples/hist_cpu.md): a complete forced-HIT pseudospectral DNS built on the package.
- [Notation](notation.md): the single reference for every symbol the docstrings use.

### Design & internals

- [Architecture](architecture.md): why the package is built as it is — the fiber-bundle model, representation validity (the method set is the spec), the code-generation architecture, the spectral machinery, CPU threading, and the grid↔point transfer.
- [Formalization](formalization.md): the typed statements behind the prose — each operation's spaces and normalizations checked by expansion against the code, linked to the tests that verify them.
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
  "api/Convolution.md",
  "api/Points.md",
  "api/Interpolation.md",
  "api/Reductions.md",
]
```
