# Notation

The symbols used throughout the docstrings and the design documents, with the code object each one
denotes. All mathematics is rendered LaTeX; a code identifier always appears in `backticks` and never
inside a math span. This page is the single reference — a docstring introduces a symbol on first use
and need not repeat the convention.

## Conventions

| Concept | Symbol | Convention |
|:---|:---|:---|
| Imaginary unit | ``\mathrm{i}`` | Upright, always — never bare italic `i`, never `\imath`. Writing it upright frees `i` for use as an index. |
| Indices | ``i, j, k, \dots`` | Italic, taken in order; used freely alongside ``\mathrm{i}`` (upright versus italic tells them apart). As an index, ``k`` occurs only in component subscripts (Einstein-summed); the standalone ``k`` of the table below is always the wavenumber, so the two roles never meet. |
| Repeated index | ``a_i b_i`` | An index repeated within a term is summed over the three components ``1, 2, 3`` (Einstein convention); an explicit ``\sum`` is reserved for the grid, point, and mode sums below. |
| Partial derivative | ``\partial_{x_i}``, ``\partial^2_{x_i x_i}`` | The coordinate is subscripted, not the fiber index; a second derivative repeats the coordinate, so the Laplacian is ``\Delta f = \partial^2_{x_i x_i} f`` (with the repeated ``i`` summed). |
| Differential | ``\mathrm{d}x``, ``\mathrm{d}\mu`` | Upright ``\mathrm{d}`` (matching the imaginary unit), with a thin space before it: ``\int_\Omega f \,\mathrm{d}\mu``. Never a bare italic ``d``. |
| Summations | ``\sum_x``, ``\sum_p``, ``\sum_k`` | Over the ``N`` grid points, over the ``M`` points, and over the Fourier modes. |
| Fractions | ``\tfrac{1}{2}``, ``\frac{1}{N}`` | Every macro argument is braced, both numerator and denominator, so no argument boundary is ever ambiguous. |
| Spacing | juxtaposition | Adjacent factors sit side by side (``C_K \varepsilon^{2/3} \kappa^{-5/3}``), never separated by a thin space; a thin space appears only before the differential above. |
| Delimiters | ``\Bigl( \dots \Bigr)`` | Size delimiters by hand with the fixed-size `\bigl`/`\Bigl` … `\bigr`/`\Bigr` commands; the auto-sizing `\left`/`\right` pair is not used — it is an Inner atom that inserts a spurious gap where the fixed-size forms are Open/Close. The sole exception is a system, set as ``\left\{ \dots \right.``. |

## Base and fiber

| Symbol | Meaning | Code |
|:---|:---|:---|
| ``f``, ``g`` | a field: one value attached to every point of the base, the value being a scalar, a vector, or a second-order tensor (a *section of the tensor bundle*, in the language the design docs use). **One deliberate reuse:** in `Convolution`, ``g`` and its transform ``\hat g`` denote the **kernel** rather than a field — the standard symbol for a convolution kernel, kept because every formula there reads as the textbook one. A kernel is a distinct kind of object, not a field, so read ``g`` as the kernel on that page and as a field everywhere else | — |
| ``x`` | a position in the periodic box ``\Omega`` (``x_p`` is the ``p``-th point) | — |
| ``q`` | a per-point value (``q_p`` sits at ``x_p``) | — |
| ``\Omega``, ``\lvert\Omega\rvert`` | the periodic box and its volume | `Grid3D` |
| ``N`` | the grid-point count ``\prod_i N_i``; on a uniform periodic grid this is equally the **cell** count, each node carrying the volume of one cell, which is why the docs use "grid points" and "grid cells" for the same ``N`` | `prod(grid_size)` |
| ``M`` | the number of points | `npoints` |
| ``k`` | a wavenumber vector (``k_a`` is its ``a``-th component, ``\lvert k\rvert`` its magnitude) | `FieldSpectralMultipliers` |
| ``\kappa`` | a wavenumber-shell magnitude, ``\kappa = \lvert k\rvert`` — the radial coordinate a spectrum is resolved over | `radial_spectrum` |
| ``h`` | a physical displacement (``h_a`` is its component along axis ``a``) | `translation_kernel` |
| ``\Delta`` | alone, the Laplacian. Followed by another symbol it reads as "an increment of": ``\Delta x_a`` the grid spacing on axis ``a``, ``\Delta k`` the wavenumber-shell width (the box fundamental, in `radial_spectrum`), and ``\Delta t`` a timestep — which appears only in the examples, the package itself carrying no notion of time | `laplacian`, `radial_spectrum` |
| ``\hat f`` | the field ``f`` in spectral representation | `to_spectral(f)` |

The worked turbulence example sets the wavenumber vector bold, as ``\mathbf{k}``, because it follows
the turbulence convention in which italic ``k`` is the turbulent kinetic energy. That override is
local to the example and is declared there; everywhere else the wavenumber vector is the plain ``k``
of the table above.

## Operators

| Symbol | Meaning | Code |
|:---|:---|:---|
| ``\nabla`` | gradient | `gradient` |
| ``\nabla\cdot`` | divergence | `divergence` |
| ``\nabla\times`` | curl | `curl` |
| ``\Delta``, ``\Delta^{-1}`` | the Laplacian and its inverse | `laplacian`, `inverse_laplacian` |
| ``\mathbb{P}`` | the Helmholtz (Leray) projection | `helmholtz_projection` |
| ``\mathcal{F}``, ``\mathcal{F}^{-1}`` | the forward and inverse transforms | `to_spectral`, `to_physical` |
| ``\cdot``, ``\times`` | the fiber dot and cross products | `dot` (`⋅`), `cross` (`×`) |
| ``\langle\cdot,\cdot\rangle`` | the normalized ``L^2`` inner product | `inner` |
| ``\langle\cdot\rangle`` | the base average of a single argument (the same measure, one slot) | `mean` |
| ``\lvert\cdot\rvert`` | the pointwise (fiberwise) magnitude | `norm` |
| ``\lVert\cdot\rVert`` | the ``L^2`` norm | `l2norm` |
| ``\int f\,\mathrm{d}\mu`` | the integral against the base measure | `integral` |
| ``\star`` | periodic convolution | `convolve` |
| ``W``, ``W^{\top}`` | interpolation (gather) and its adjoint anterpolation (scatter). **One deliberate reuse:** `assignment_window` writes ``W`` for the linear (CIC) "tent" cloud a point deposits and ``\hat W`` for its transfer function — a real-valued function, not the gather operator. The two are related in spirit (that cloud *is* the `LalescuSpline(0, 0)` weight) but are different objects between different spaces | `interpolate`, `anterpolate` |

## Scalar weights

Two distinct quantities are written ``\alpha``, and the argument tells them apart: the caller's
accumulation weight is always the bare ``\alpha``, while the half-spectrum Parseval weight is always
written with its mode argument as ``\alpha(k)``. They never denote the same thing.

| Symbol | Meaning | Code |
|:---|:---|:---|
| ``\alpha``, ``\beta`` | the caller's accumulation weights in ``\texttt{destination} \leftarrow \alpha (\dots) + \beta \texttt{destination}`` | the trailing `α`, `β` arguments |
| ``\alpha(k)`` | the half-spectrum Parseval weight of mode ``k``: ``1`` on a self-conjugate plane of the folded axis, ``2`` elsewhere. The **folded axis** is the one the real-to-complex transform halves, storing only non-negative wavenumbers — it is the first entry of a `RealFourierLayout`'s `fft_dims`, written `fft_dims[1]` throughout, and is the first axis by default; its **self-conjugate planes** are the two — zero and, on an even axis, Nyquist — that the folding maps to themselves, so a mode's conjugate partner lies in the same plane and is stored alongside it rather than being implied; those modes are therefore counted once, not twice, so that a sum over stored modes equals the sum over the full spectrum | `inner`, `radial_spectrum` |
| ``w`` | a multiplier weighting an inner product mode by mode | `weighted_inner` |
