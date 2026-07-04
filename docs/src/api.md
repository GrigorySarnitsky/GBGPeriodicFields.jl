# API overview

The package is an umbrella module (`GBGPeriodicFields`) that re-exports a set of submodules. The
include order reflects the dependency layering: `FiberSections` → `Fields` → `FieldAlgebra` →
`DifferentialOperators` → `Convolution` → `Points` → `Interpolation` → `Reductions`.

- [GBGPeriodicFields](api/GBGPeriodicFields.md): the top-level module and public re-export surface.
- [FiberSections](api/FiberSections.md): the base-agnostic foundation — the `AbstractFiberSection` supertype, the `_assign!` threading primitive, and the fiberwise-algebra code generators reused by `FieldAlgebra` and `Points`.
- [Fields](api/Fields.md): grids, Cartesian fiber types, field representations, FFT transforms, field utilities, and broadcasting support.
- [FieldAlgebra](api/FieldAlgebra.md): fiberwise algebraic operations on scalar, vector, and tensor fields.
- [DifferentialOperators](api/DifferentialOperators.md): differential operators on fields in spectral representation.
- [Convolution](api/Convolution.md): periodic convolution of a field with a Fourier kernel (`convolve`/`convolve!`, the coefficientwise product ``\hat f \cdot \hat g``; the builders `spectral_cutoff`/`spectral_band`/`squared_wavenumber_field`/`assignment_window`), in spectral representation.
- [Points](api/Points.md): the unstructured-base point and point-value data types and their fiberwise algebra.
- [Interpolation](api/Interpolation.md): the grid↔point transfer — interpolation (gather) and anterpolation (scatter) as an L²-adjoint pair, under an `AbstractTransferScheme`: the local splines (`LalescuSpline`/`CatmullRom`, `LagrangeSpline`), the exact spectral `DirectDFT`, and the fast spectral `NUFFT`.
- [Reductions](api/Reductions.md): the L²/measure structure — base reductions (`integral`, `inner`, `l2norm`, `lpnorm`, `mean`/`std`/`var`, `maximum`) over fields and point-values, plus the radial pair `radial_spectrum` (the power spectrum) and `radial_correlation` (its Wiener–Khinchin dual, the two-point autocorrelation), each with a two-field **co-spectrum** form (`radial_spectrum(f, g)` / `radial_correlation(f, g)`).

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
