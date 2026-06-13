# Interpolation

```@autodocs
Modules = [GBGPeriodicFields.Interpolation]
Order   = [:module]
```

The `Interpolation` module is the grid↔point transfer layer: **interpolation** (grid → point, the
gather ``\mathcal I = W``) evaluates a field at off-grid positions, and its adjoint **anterpolation**
(point → grid, the scatter ``\mathcal I^* = W^\top``) deposits per-point quantities back onto the grid.
The two are an L²-adjoint pair under a shared scheme; the scheme — an [`AbstractTransferScheme`](@ref) —
is the choice of *kernel* and *representation*. Two families:

  * **Physical-domain splines** ([`AbstractSplineScheme`](@ref)) — the local high-order splines of
    Lalescu, Teaca & Carati (2010): the smooth [`LalescuSpline`](@ref) (two-point Hermite, default
    [`CatmullRom`](@ref), pinned bit-for-bit to TurTLE) and the ``C^0`` [`LagrangeSpline`](@ref). They
    act on the **physical** nodal values; interpolation and anterpolation are exact transposes and
    conserve the deposited total.
  * **Spectral-domain exact transfer** ([`DirectDFT`](@ref)) — the literal ``O(NM)`` discrete Fourier
    sum, acting on a field in **spectral** representation: ``f(x_p) = \tfrac1N \sum_k \hat f(k)\,
    e^{i k\cdot(x_p-o)}`` and its adjoint. It reproduces the band-limited field **exactly** (so it is
    pointwise divergence-free, matching [`to_physical`](@ref) at the grid nodes) and is the oracle for
    the fast [`NUFFT`](@ref).
  * **Spectral-domain fast transfer** ([`NUFFT`](@ref)) — the ``O(N\log N + M)`` windowed-gridding
    version of `DirectDFT` (spread → oversampled FFT → deconvolve), owned natively, exact to a tolerance
    on the resolved sub-Nyquist band. See `docs/ARCHITECTURE.md` §10 / decision 23.

The spline kernels are portable across CPU / CUDA / AMDGPU (KernelAbstractions); the point-data types
live in the [`Points`](Points.md) module.

## Contents

```@contents
Pages = ["Interpolation.md"]
Depth = 2:3
```

## Index

```@index
Modules = [GBGPeriodicFields.Interpolation]
```

## Public API

### Types

```@autodocs
Modules = [GBGPeriodicFields.Interpolation]
Public  = true
Private = false
Order   = [:type, :constant]
```

### Functions

```@autodocs
Modules = [GBGPeriodicFields.Interpolation]
Public  = true
Private = false
Order   = [:function]
```

## Internal API

The scheme supertype `AbstractSplineScheme`, the spline-weight generators (Fornberg finite
differences + a small linear solve), the periodic cell-finding, and the in-kernel helpers —
documented for contributors.

```@autodocs
Modules = [GBGPeriodicFields.Interpolation]
Public  = false
Order   = [:type, :function]
```
