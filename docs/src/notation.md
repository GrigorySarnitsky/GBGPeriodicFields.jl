# Notation

The symbols used throughout the docstrings and the design documents, with the code object each one
denotes. All mathematics is rendered LaTeX; a code identifier always appears in `backticks` and never
inside a math span. This page is the single reference — a docstring introduces a symbol on first use
and need not repeat the convention.

## Conventions

| Concept | Symbol | Convention |
|:---|:---|:---|
| Imaginary unit | ``\mathrm{i}`` | It is always upright — never bare italic ``i``, never ``\imath``. Writing it upright frees ``i`` for use as an index. |
| Indices | ``i, j, k, \dots`` | They are italic, taken in order, and used freely alongside ``\mathrm{i}`` (upright versus italic tells them apart). As an index, ``k`` occurs only in component subscripts (Einstein-summed); the standalone ``k`` of the table below is always the wavenumber, so the two roles never meet. |
| Repeated index | ``a_i b_i`` | An index repeated within a term is summed over the three components ``1, 2, 3`` (Einstein convention); an explicit ``\sum`` is reserved for the grid, point, and mode sums below. |
| Partial derivative | ``\partial_{x_i}``, ``\partial^2_{x_i x_i}`` | The coordinate is subscripted, not the fiber index; a second derivative repeats the coordinate, so the Laplacian is ``\Delta f = \partial^2_{x_i x_i} f`` (with the repeated ``i`` summed). |
| Differential | ``\mathrm{d}x``, ``\mathrm{d}\mu`` | Upright ``\mathrm{d}`` (matching the imaginary unit), with a thin space before it: ``\int_\Omega f \,\mathrm{d}\mu``. Never a bare italic ``d``. |
| Summations | ``\sum_x``, ``\sum_p``, ``\sum_k`` | They run over the ``N`` grid points, the ``M`` points, and the Fourier modes. |
| Fractions | ``\tfrac{1}{2}``, ``\frac{1}{N}`` | Every macro argument is braced, both numerator and denominator, so no argument boundary is ever ambiguous. |
| Spacing | juxtaposition | Adjacent factors sit side by side (``C_K \varepsilon^{2/3} \kappa^{-5/3}``), never separated by a thin space; a thin space appears only before the differential above. |
| Delimiters | ``\Bigl( \dots \Bigr)`` | Size delimiters by hand with the fixed-size `\bigl`/`\Bigl` … `\bigr`/`\Bigr` commands; the auto-sizing `\left`/`\right` pair is not used — it inserts a spurious gap the fixed-size forms do not. A system of cases is written with the `cases` environment, which sizes its own brace. |

## Base and fiber

| Symbol | Meaning | Code |
|:---|:---|:---|
| ``f``, ``g`` | a field: one value attached to every point of the base, that value — the fiber value — being a scalar, a vector, or a second-order tensor (a *section of the tensor bundle*, in the language the design docs use). One deliberate reuse: in `Convolution`, ``g`` and its transform ``\hat g`` denote the kernel rather than a field — the standard symbol for a convolution kernel. A kernel is not a field, so read ``g`` as the kernel on that page and as a field everywhere else | — |
| ``x`` | a position in the periodic box ``\Omega`` (``x_p`` is the ``p``-th point) | — |
| ``q`` | the value a point carries (``q_p`` sits at ``x_p``) — sampled from a field, or a quantity of the point's own that anterpolation, interpolation's adjoint, deposits onto the grid | [`AbstractPointValues`](@ref) |
| ``B`` | the base of the bundle picture — the set a section attaches values to: a [`Grid3D`](@ref GBGPeriodicFields.Grid3D)'s nodes, or a [`PointSet`](@ref GBGPeriodicFields.PointSet)'s points. A subscripted ``N_B`` is its point count (``N`` or ``M``); the bare glyph is never a scalar | [`Grid3D`](@ref) / [`PointSet`](@ref) |
| ``\Omega``, ``\lvert\Omega\rvert`` | the periodic box and its volume | [`Grid3D`](@ref) |
| ``N`` | the grid-point count ``\prod_i N_i``, the product of the counts along the axes; on a uniform periodic grid this is equally the cell count, each node carrying the volume of one cell, which is why the docs use "grid points" and "grid cells" for the same ``N``. A complexity expression may use either reading, and which one is always fixed by the shape it describes: the storage claims of the kernels and reductions — ``O(N^3)`` for a full field, ``O(N)`` for a per-axis array, ``O(N^2)`` for a plane — count per axis on the cubic grids they describe, while the transfer costs ``O(NM)`` and ``O(N \log N + M)`` count the total. The two never mix inside one formula | [`prod(grid_size)`](@ref Grid3D) |
| ``M`` | the number of points | [`npoints`](@ref) |
| ``k`` | a wavenumber vector (``k_a`` is its ``a``-th component, ``\lvert k\rvert`` its magnitude) | [`FieldSpectralMultipliers`](@ref) |
| ``a`` | the derivative wavenumber vector (``a_1, a_2, a_3`` its components) — the family the first-derivative operators multiply by, equal to ``k`` except that it is zeroed at an even-length axis's Nyquist frequency, which keeps derivatives of real fields real. The Laplacian instead uses the true ``\lvert k\rvert^2``, and the two families are stored separately for that reason. Standing alone or with a numeric subscript the glyph is this vector; *sitting in* a subscript (``k_a``, ``\Delta x_a``) it is an ordinary per-axis index | [`FieldSpectralMultipliers`](@ref) |
| ``\kappa`` | a wavenumber-shell magnitude, ``\kappa = \lvert k\rvert`` — the radial coordinate a spectrum is resolved over | [`radial_spectrum`](@ref) |
| ``h`` | a physical displacement (``h_a`` is its component along axis ``a``) | [`translation_kernel`](@ref) |
| ``\Delta`` | before a field it is the Laplacian; before a coordinate or parameter it reads as "an increment of": ``\Delta x_a`` the grid spacing on axis ``a``, ``\Delta k`` the wavenumber-shell width (the box fundamental, in `radial_spectrum`), and ``\Delta t`` a timestep — which appears only in the examples, the package itself carrying no notion of time | [`laplacian`](@ref), [`radial_spectrum`](@ref) |
| ``\hat f`` | the field ``f`` in spectral representation: its Fourier coefficients as the forward transform stores them | [`to_spectral(f)`](@ref to_spectral) |

The worked turbulence example sets the wavenumber vector bold, as ``\mathbf{k}``, because it follows
the turbulence convention in which italic ``k`` is the turbulent kinetic energy. That override is
local to the example and is declared there; everywhere else the wavenumber vector is the plain ``k``
of the table above.

## Operators

| Symbol | Meaning | Code |
|:---|:---|:---|
| ``\nabla`` | gradient | [`gradient`](@ref) |
| ``\nabla\cdot`` | divergence | [`divergence`](@ref) |
| ``\nabla\times`` | curl | [`curl`](@ref) |
| ``\Delta``, ``\Delta^{-1}`` | the Laplacian and its inverse | [`laplacian`](@ref), [`inverse_laplacian`](@ref) |
| ``\mathbb{P}`` | the Helmholtz (Leray) projection | [`helmholtz_projection`](@ref) |
| ``\mathcal{F}``, ``\mathcal{F}^{-1}`` | the forward and inverse transforms | [`to_spectral`](@ref), [`to_physical`](@ref) |
| ``\cdot``, ``\times`` | the fiber dot and cross products | [`dot`](@ref) (`⋅`), [`cross`](@ref) (`×`) |
| ``\langle\cdot,\cdot\rangle`` | the ``L^2`` inner product over the base's total measure | [`inner`](@ref) |
| ``\langle\cdot\rangle`` | the base average of one argument, against the same measure | [`mean`](@ref) |
| ``\lvert\cdot\rvert`` | the pointwise (fiberwise) magnitude. In this table the bars are written `\lvert…\rvert` because a literal pipe inside a cell is eaten as a column delimiter; in running math outside a table the same symbol is written with plain single bars, which cannot be shown in this cell because the literal pipe would split it — note that LaTeX's backslash-bar is NOT that spelling, being the DOUBLE bar, the ``\lVert\cdot\rVert`` of the next row | [`norm`](@ref) |
| ``\lVert\cdot\rVert`` | the ``L^2`` norm | [`l2norm`](@ref) |
| ``\int f\,\mathrm{d}\mu`` | the integral against the base measure: cell volume on a grid, unit mass per point | [`integral`](@ref) |
| ``\star`` | periodic convolution | [`convolve`](@ref) |
| ``W``, ``W^{\top}`` | interpolation (gather) and its adjoint anterpolation (scatter). One deliberate reuse: the kernel builders [`tophat_window`](@ref GBGPeriodicFields.tophat_window) and [`assignment_window`](@ref GBGPeriodicFields.assignment_window) write ``W`` for their physical-space window — the box, and the linear cloud-in-cell "tent" a point deposits — and ``\hat W`` for its transfer function, not the gather operator; the tent *is* the `LalescuSpline(2; smoothness = 0)` weight, but the two are different objects | [`interpolate`](@ref), [`anterpolate`](@ref) |

## Scalar weights

Two distinct quantities are written ``\alpha``, and the argument tells them apart: the caller's
accumulation weight is always the bare ``\alpha``, while the half-spectrum Parseval weight is always
written with its mode argument as ``\alpha(k)``. They never denote the same thing. A third, purely local
use appears in the `Fields` storage docstrings, where ``\alpha = 1, 2, 3`` numbers a stored fiber
component; it names an array slot rather than a weight, and does not travel beyond those bullets.

| Symbol | Meaning | Code |
|:---|:---|:---|
| ``\alpha``, ``\beta`` | the caller's accumulation weights in ``\texttt{destination} \leftarrow \alpha (\dots) + \beta \texttt{destination}`` | the trailing `α`, `β` arguments |
| ``\alpha(k)`` | the half-spectrum Parseval weight of mode ``k``: ``1`` on a self-conjugate plane of the folded axis, ``2`` elsewhere. The *folded axis* is the one the real-to-complex transform halves, storing only non-negative wavenumbers — it is the first entry of a [`RealFourierLayout`](@ref GBGPeriodicFields.RealFourierLayout)'s `fft_dims`, written `fft_dims[1]` throughout, and is the first axis by default; its *self-conjugate planes* are the two — zero and, on an even axis, Nyquist — that the folding maps to themselves, so a mode's conjugate partner lies in the same plane and is stored alongside it rather than being implied; those modes are therefore counted once, not twice, so that a sum over stored modes equals the sum over the full spectrum | [`inner`](@ref), [`radial_spectrum`](@ref) |
| ``w`` | a multiplier weighting an inner product mode by mode | [`weighted_inner`](@ref) |
