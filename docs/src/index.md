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

New here? Start with the **[Getting started](tutorial.md)** tour — a short, runnable walkthrough of
grids, fields, representations, operators, reductions, and the point transfer.

## Main components

- [`FiberSections`](api/FiberSections.md): the base-agnostic foundation — the `AbstractFiberSection` supertype shared by fields and point-values, the CPU-threading primitive, and the fiberwise-algebra code generators (each per-component formula written once, reused by `FieldAlgebra` and `Points`).
- [`Fields`](api/Fields.md): grids, Cartesian fiber types, field representations (physical and spectral), FFT transforms, field utilities, and broadcasting support.
- [`FieldAlgebra`](api/FieldAlgebra.md): fiberwise algebraic operations on fields — vector-space operations, scalar actions, vector and tensor products, contractions, norms, and tensor decompositions.
- [`DifferentialOperators`](api/DifferentialOperators.md): spectral differential operators — gradient, divergence, curl, Laplacian, inverse Laplacian, and Helmholtz projection.
- [`Convolution`](api/Convolution.md): periodic convolution of a field with a kernel, in spectral representation — `convolve`/`convolve!` apply a Fourier kernel (a `ScalarFieldSpectral` transfer function) as the coefficientwise product ``\hat f \cdot \hat g``; `spectral_cutoff`/`spectral_band` build sharp low-pass/band-pass kernels, `squared_wavenumber_field` the ``|k|^2`` radial coordinate, `assignment_window` the mass-assignment deconvolution window.
- [`Points`](api/Points.md): the unstructured base — point and point-value data types (`Point`, `PointSet`, the `PointValues`) and their full fiberwise algebra, mirroring the physical field surface.
- [`Interpolation`](api/Interpolation.md): the grid↔point transfer — interpolation (gather ``W``) and anterpolation (scatter ``W^\top``) as an L²-adjoint pair, under a choice of `AbstractTransferScheme`: the physical-domain local splines (`LalescuSpline`/`CatmullRom`, `LagrangeSpline`), the exact spectral `DirectDFT`, and the fast spectral `NUFFT`; the spline and NUFFT kernels are portable across CPU/CUDA/AMDGPU.
- [`Reductions`](api/Reductions.md): the L²/measure structure — base reductions over fields and point-values (`integral`, `inner`, `l2norm`, `lpnorm`, and `mean`/`std`/`var`/`maximum`), each integrating the base away against its measure; plus the radial pair `radial_spectrum` (the power spectrum) and `radial_correlation` (its physical-space Wiener–Khinchin dual, the two-point autocorrelation), each with a two-field **co-spectrum** form (`radial_spectrum(f, g)` / `radial_correlation(f, g)` — cross-power and cross-correlation, refining the mixed `inner(f, g)`).

Pointwise (fiberwise) products and norms live in `FieldAlgebra`; their *global* counterparts — integrals, the L² inner product and norms — live in `Reductions`. Spectral differential operators live in the separate `DifferentialOperators` module, and periodic convolution (apply a Fourier kernel) in `Convolution`.

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
  "api/Convolution.md",
  "api/Points.md",
  "api/Interpolation.md",
  "api/Reductions.md",
]
```
