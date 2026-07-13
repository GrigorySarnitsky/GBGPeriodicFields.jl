# Notation

The symbols used throughout the docstrings and the design documents, with the code object each one
denotes. All mathematics is rendered LaTeX; a code identifier always appears in `backticks` and never
inside a math span. This page is the single reference — a docstring introduces a symbol on first use
and need not repeat the convention.

## Conventions

| Concept | Symbol | Convention |
|---|---|---|
| Imaginary unit | ``\mathrm{i}`` | Upright, always — never bare italic `i`, never `\imath`. Writing it upright frees `i` for use as an index. |
| Indices | ``i, j, k, \dots`` | Italic, taken in order; used freely alongside ``\mathrm{i}`` (upright versus italic tells them apart). |
| Repeated index | ``a_i b_i`` | An index repeated within a term is summed over the three components ``1, 2, 3`` (Einstein convention); an explicit ``\sum`` is reserved for the grid, point, and mode sums below. |
| Partial derivative | ``\partial_{x_i}``, ``\partial^2_{x_i x_i}`` | The coordinate is subscripted, not the fiber index; a second derivative repeats the coordinate, so the Laplacian is ``\Delta f = \partial^2_{x_i x_i} f`` (with the repeated ``i`` summed). |
| Summations | ``\sum_x``, ``\sum_p``, ``\sum_k`` | Over the ``N`` grid points, over the ``M`` points, and over the Fourier modes. |
| Delimiters | ``\Bigl(\;\Bigr)`` | Fixed-size `\Bigl \dots \Bigr` is preferred to auto-sized `\left \dots \right`, which over-inflates around subscripted sums. |

## Base and fiber

| Symbol | Meaning | Code |
|---|---|---|
| ``f``, ``g`` | a field — a section of the tensor bundle over the base | — |
| ``x`` | a position in the periodic box ``\Omega`` (``x_p`` is the ``p``-th point) | — |
| ``q`` | a per-point value (``q_p`` sits at ``x_p``) | — |
| ``\Omega``, ``\lvert\Omega\rvert`` | the periodic box and its volume | `Grid3D` |
| ``N`` | the grid-point count ``\prod_i N_i`` | `prod(grid_size)` |
| ``M`` | the number of points | `npoints` |
| ``k`` | a wavenumber vector (``k_a`` is its ``a``-th component, ``\lVert k\rVert`` its magnitude) | `FieldSpectralMultipliers` |
| ``h`` | a physical displacement (``h_a`` is its component along axis ``a``); ``\Delta`` is reserved for the Laplacian, and ``\Delta x_a`` for the grid spacing | `translation_kernel` |
| ``\hat f`` | the field ``f`` in spectral representation | `to_spectral(f)` |

## Operators

| Symbol | Meaning | Code |
|---|---|---|
| ``\nabla`` | gradient | `gradient` |
| ``\nabla\cdot`` | divergence | `divergence` |
| ``\nabla\times`` | curl | `curl` |
| ``\Delta``, ``\Delta^{-1}`` | the Laplacian and its inverse | `laplacian`, `inverse_laplacian` |
| ``\mathbb{P}`` | the Helmholtz (Leray) projection | `helmholtz_projection` |
| ``\mathcal{F}``, ``\mathcal{F}^{-1}`` | the forward and inverse transforms | `to_spectral`, `to_physical` |
| ``\cdot``, ``\times`` | the fiber dot and cross products | `dot` (`⋅`), `cross` (`×`) |
| ``\langle\cdot,\cdot\rangle`` | the normalized ``L^2`` inner product | `inner` |
| ``\lVert\cdot\rVert`` | the ``L^2`` norm | `l2norm` |
| ``\int f\,d\mu`` | the integral against the base measure | `integral` |
| ``\star`` | periodic convolution | `convolve` |
| ``W``, ``W^{\top}`` | interpolation (gather) and its adjoint anterpolation (scatter) | `interpolate`, `anterpolate` |
