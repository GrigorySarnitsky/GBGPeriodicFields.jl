# GBGPeriodicFields.jl

`GBGPeriodicFields.jl` is a package for representing, transforming, and manipulating scalar, vector, and tensor fields on three-dimensional rectangular periodic domains. The tensors are **Cartesian** — components on one fixed orthonormal frame, with no curvilinear coordinates and no metric machinery — so this is an applied field toolkit rather than a general differential-geometry package.

The package is aimed primarily at fluid-dynamics and turbulence simulations. Fields are physical objects, while physical-space and nonredundant spectral representations are storage and manipulation choices. The implementation is designed for both CPU and GPU array backends, with HDF5 field persistence, and includes an unstructured **point layer**: evaluating fields at off-grid positions (interpolation) and depositing per-point quantities back onto the grid (anterpolation) — the field layer for Lagrangian-particle methods.

This package is not intended to be a ready-to-use DNS solver; rather, it is a toolkit for building fluid-dynamics and general field solvers.

[`GBGIsotropicTurbulence.jl`](https://grigorysarnitsky.github.io/GBGIsotropicTurbulence.jl) is such a solver, and the package's primary consumer: a pseudospectral direct numerical simulation of homogeneous isotropic turbulence built on these fields. Its documentation is the place to see the surface below driving a full solver rather than a worked example.

A few words of vocabulary, used throughout the docs. A **field** — and its off-grid **point-values** — is a *section*: one **fiber** value (a scalar, a vector, or a second-order tensor) attached to every point of a **base** (the structured grid, or an unstructured set of points). Every operation is one of three kinds: it acts *within* each fiber (the pointwise algebra — add, contract, transpose), it *differentiates along the base* (the differential operators, applied as spectral multipliers), or it *pairs a section against a **measure*** — the base's own for the reductions (the weight each base point carries in a sum: a grid cell's uniform volume, a point's plain count of one), and a kernel-supplied one for periodic convolution and the grid↔point transfer — the three being one integration structure in three roles. The design behind this split is the [Architecture](architecture.md) page; you do not need it to use the package.

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
- [`Fields`](api/Fields.md): grids, field representations (physical and spectral), FFT transforms, the `similar_field` allocator, the spectral-kernel supertype every kernel-taking module names, broadcasting support, HDF5 persistence, and the storage-family move `adapt` that carries a field, its multipliers, its kernels or its plans between host and device.
- [`FieldAlgebra`](api/FieldAlgebra.md): fiberwise algebraic operations on fields — vector-space operations, scalar actions, vector and tensor products, contractions, norms, and tensor decompositions, plus `map!`/`map`, which apply an arbitrary fiber map at every base point and so cover any pointwise operation the module does not name.
- [`DifferentialOperators`](api/DifferentialOperators.md): differential operators applied as spectral multipliers — gradient, divergence, curl, the fused symmetric gradient, Laplacian, inverse Laplacian, and Helmholtz projection.
- [`Convolution`](api/Convolution.md): periodic convolution of a field with a kernel, in spectral representation — `convolve`/`convolve!` (with the infix alias `⋆`) apply a Fourier kernel as the coefficientwise product ``\hat f \cdot \hat g``; a kernel is its own kind of object rather than a field, held either as a `StoredKernel` of one coefficient per mode or in one of the compressed classes `SeparableKernel` and `RadialKernel`, which store a closed-form multiplier rather than its coefficients, or as a `ProductKernel` of any two kernels held unmultiplied; all four are interchangeable with the stored form wherever a kernel is applied (`materialize_kernel` expands one into a `StoredKernel`, and `radial_kernel` builds a kernel from any real function of ``\lvert k\rvert^2`` — its *symbol*, the multiplier a coefficientwise operator applies); `spectral_cutoff`/`spectral_band` build sharp low-pass/band-pass kernels, `assignment_window` the mass-assignment deconvolution window, `translation_kernel` the phase ``e^{-\mathrm{i} k\cdot h}`` that displaces a field by a physical offset ``h``, and `exponential_convolve`/`exponential_convolve!` apply the lazy exponential radial kernel ``\exp(c \lvert k\rvert^2 + s \hat w)`` with no kernel field built (plus the kernel-composed `combine!`, the weighted combination convolved in one pass).
- [`Points`](api/Points.md): the unstructured base — point and point-value data types (`Point`, `PointSet`, the `AbstractPointValues` types), their full fiberwise algebra mirroring the field surface in physical representation (including the arbitrary-fiber-map `map!`/`map`), and HDF5 persistence.
- [`Interpolation`](api/Interpolation.md): the grid↔point transfer — interpolation (gather ``W``) and anterpolation (scatter ``W^\top``) as an adjoint pair — exactly L²-adjoint after the measure rescaling by ``N/M`` (``N`` grid cells to ``M`` points) that the module page derives — under a choice of `AbstractTransferScheme`: the physical-domain local splines (`LalescuSpline`/`CatmullRom`, `LagrangeSpline`), the exact spectral `DirectDFT`, and the fast spectral `NUFFT`; all three schemes' kernels are portable across CPU/CUDA/AMDGPU.
- [`Reductions`](api/Reductions.md): the L²/measure structure — base reductions over fields and point-values — the extensive `integral` (it scales with the base measure) and the normalized, intensive `inner`, `l2norm`, `lpnorm`, and the moments `mean`, the scalar-only `std`/`var` and the covariance tensor `cov` (a vector field's second *central* moment, kept coordinate-free), each integrating the base away against its measure, plus the measure-independent `maximum`/`minimum`/`extrema` (sup/inf over scalar sections) and the multiplier-weighted `weighted_inner` (spectral-only, generalizing `inner`); `inner`, `l2norm`, `integral`, `mean`, `std` and `var` additionally act on a field in **spectral** representation, returning the same value with no transform (Parseval for `inner`/`l2norm`, the zero Fourier mode for `integral`/`mean`, and both together for `std`/`var`, built from ``\langle f,f\rangle`` less the squared mean); plus the radial reductions `radial_spectrum` (the power spectrum) and `radial_correlation` (its physical-space Wiener–Khinchin dual, the two-point autocorrelation), each with a two-field **co-spectrum** form (`radial_spectrum(f, g)` / `radial_correlation(f, g)` — cross-power and cross-correlation, refining the mixed `inner(f, g)`).

Pointwise (fiberwise) products and norms live in `FieldAlgebra`; their *global* counterparts — integrals, the L² inner product and norms — live in `Reductions`. The differential operators, applied as spectral multipliers, live in the separate
`DifferentialOperators` module, and periodic convolution (apply a Fourier kernel) in `Convolution`.

## Documentation structure

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
