# Formalization — the typed statements behind the prose

This page is the **formal backing** for the mathematical statements made informally in
[Architecture](architecture.md), the module docstrings, and the API pages. For each nontrivial
operation it records a *typed* statement — every object given its space, every operator its domain and
codomain — and checks each claim by expansion, with the definitions **taken from the implementation**
(`src/`) and a link to the **test** that verifies the claim numerically.

It exists as a precision check, not as a page a user reads. Writing a statement formally forces every
type and normalization into the open, which is exactly where imprecision in the prose becomes visible:
the all-ones ``\mathbf 1`` that was secretly two different vectors, or a section space written
``\mathbb R^N`` that had quietly flattened the fiber away. These are **hand-verified notes, not
machine-checked proofs** — the deterministic check is the linked test (the test suite plays the role of
the compiler), so a statement here with no test is a coverage gap to close.

!!! note "Coordinate forms live here"
    The coordinate-free preference (`CLAUDE.md`) governs the *user-facing* prose. This page is the
    sanctioned home for the coordinate/matrix/component expansions — a basis, the matrix entries
    ``W_{pn}``, the all-ones ``\mathbf 1_N`` / ``\mathbf 1_M`` — because *checking* precision requires
    expanding into components. The statements here must still be **correct**; they need not be
    coordinate-free.

## Declarations

Fixed throughout (definitions read from `src/`):

```math
\begin{aligned}
V        &:= (\mathbb R^3)^{\otimes R}   &&\text{fiber, tensor order } R\ (\dim 3^R)\\
\Gamma_G &:= \mathbb R^{N_x}\otimes\mathbb R^{N_y}\otimes\mathbb R^{N_z}\otimes V &&\text{grid sections, } N = N_x N_y N_z \text{ cells}\\
\Gamma_P &:= \mathbb R^M \otimes V        &&\text{point sections, } M \text{ scattered points}
\end{aligned}
```

A grid cell is a triple ``(i_1, i_2, i_3)`` of per-axis indices (a **standalone** ``k`` is reserved for
the wavenumber below; as a subscripted *component* index — ``\varepsilon_{ijk}``, ``A_{ik}B_{kj}`` — it
keeps its ordinary meaning, the two never colliding since one is a free symbol and the other always
sits in a subscript run), so the scalar field over the grid is the 3-axis tensor product
``\mathbb R^{N_x}\otimes\mathbb R^{N_y}\otimes\mathbb R^{N_z}`` (the array ``f_{i_1 i_2 i_3}``) — one real per cell.
As a vector space this is ``\mathbb R^N`` with ``N = N_x N_y N_z``: a column-major flat index ``n`` collapses
``(i_1, i_2, i_3)``, and the global pairings below use that flat ``n`` (the per-axis structure is irrelevant to
them — it is what the tensor-product stencil weights ``w_{i_1}w_{i_2}w_{i_3}`` (the per-axis transfer
weights, defined in the interpolation section below) and the differential
multipliers ``\mathrm{i} k_a`` (``k_a`` a component of the wavenumber ``k``, set up with the transforms
below) act on). The factor ``\otimes V`` then attaches the fiber, so a grid section is a ``V``-value *at
each cell* (``\cong V^N``; a single real only in the scalar case ``R = 0``). The point base ``\mathbb R^M``
is **unstructured** — ``M`` scattered points, no product — which is exactly the structured-to-unstructured
nature of the transfer. A point's *position* ``x_p \in \mathbb R^3`` is a separate object from the value it
carries: the positions are the `PointSet` geometry (``\mathbb R^M \otimes \mathbb R^3 \cong \mathbb R^{3M}``,
themselves a vector-valued section over the points) and enter only through the transfer weights
``w_n(x_p)`` (the interpolation stencil weight of grid node ``n`` at position ``x_p``, defined in the
interpolation section), whereas ``\Gamma_P`` is the space of *values* — a ``V`` per point. So ``\Gamma_P`` is
``\mathbb R^{3M}`` only when the sampled field is a vector (``V = \mathbb R^3``); in general it is
``\mathbb R^M \otimes V``, just as the grid value space is not ``\mathbb R^{3N}``.

The transform ``\mathcal F`` (`to_spectral`, inverse `to_physical`) is the rfft isomorphism between the
physical (nodal) and spectral representations of a grid section; ``\hat f = \mathcal F f``. Its codomain
needs naming, because the obvious candidate is wrong: ``\mathcal F`` is **not** onto the stored complex
array ``\mathbb C^{N_{k_1} N_2 N_3} \otimes V``, which has strictly more real dimensions than
``\Gamma_G``. The image is the **Hermitian-constrained subspace**: the planes the folded axis maps to itself under
``k \mapsto -k`` (the zero plane, and on an even axis the Nyquist plane) are **closed under
conjugation**, so each stored coefficient there has its partner stored too and the pair must satisfy
``\hat f(-k) = \overline{\hat f(k)}``. Individual coefficients on those planes are not real — only
the self-paired modes, ``k = -k``, are. That constraint is exactly what makes the map a bijection onto
its image and the round trip exact. Every "coefficients of a real field" statement below means an
element of that subspace, which is also why a kernel must be Hermitian for its result to be one. With the fiber
contraction ``\cdot : V \times V \to \mathbb R`` and the wavenumber ``k``, the inner products are the
package's **normalized** reductions (`inner`, `src/Reductions.jl` = `dot(data, data) / _base_count`):

```math
\langle a, b\rangle_{\mathrm{pts}} := \frac{1}{M} \sum_{p=1}^{M} a_p\cdot b_p,
\qquad
\langle f, g\rangle_{\mathrm{grid}} := \frac{1}{N} \sum_{n=1}^{N} f_n\cdot g_n .
```

## Representations and transforms (`Fields`)

Design rationale: [Architecture](architecture.md) §4.

``\mathcal F`` is **forward unnormalized, inverse carrying ``1/N``** (AbstractFFTs convention,
`plan_rfft`/`plan_irfft`), with ``k`` ranging over the wavenumbers and ``x`` over the ``N`` grid nodes —
where ``x`` denotes a node's offset **from the grid origin** ``o``, not its absolute position. A grid
carries an arbitrary origin, so the absolute node position is ``o + x``; writing the pair in the offset
coordinate is what makes it agree with the spectral transfer below, whose phase ``e^{\mathrm{i}k\cdot(x_p - o)}``
subtracts that origin explicitly because a point ``x_p`` is given in absolute coordinates:

```math
\hat f(k) = \sum_{x} f(x) e^{-\mathrm{i} k\cdot x}, \qquad
f(x) = \frac{1}{N} \sum_{k} \hat f(k) e^{\mathrm{i} k\cdot x},
```

so ``\mathcal F^{-1}\mathcal F = \mathrm{id}`` (exact to round-off). Two consequences used elsewhere:

- **Half-spectrum + conjugate symmetry.** ``f`` real ``\Rightarrow`` ``\hat f(-k) = \overline{\hat f(k)}``,
  so only ``k_x \ge 0`` is stored (`rfft_shape`: length ``N_x/2{+}1`` on the rfft axis — the folded
  axis is `fft_dims[1]`, the first by default, and ``x`` names it throughout); the ``k_x = 0``
  plane, and on an even axis the Nyquist plane (the highest stored frequency, ``k_x = \pi/\Delta x``),
  are self-conjugate.
- **Adding a real constant** ``c`` touches only the zero mode, scaled by ``N``:
  ``\mathcal F(f + c) = \hat f + c N \delta_{k,0}`` (`_spectral_constant_scale = prod(grid_size)`), since
  the unnormalized forward sums ``N`` copies of ``c`` at ``k = 0``. ``\checkmark``

**Backs** [Architecture](architecture.md) §4 and the `Fields` transform docstrings.
**Checked by** `test/fields.jl` — FFT round-trip, multipliers vs `fftfreq`/`rfftfreq`, the Nyquist
behaviour, and transform input-preservation — and `test/fieldalgebra.jl` (the constant/zero-mode invariant).

## Fiberwise algebra (`FieldAlgebra` / `FiberSections`)

Design rationale: [Architecture](architecture.md) §2, §6.

The **vertical** operations act inside the fiber ``V`` at each base point, identically over grid and
point bases (one set of generated kernels, `src/FiberSections.jl`). A `FiberVector` is ``\mathbb R^3``, a
`FiberTensor2` genuinely a ``3\times3`` matrix, so component notation is the natural form here:

```math
\begin{aligned}
u\cdot v &= u_i v_i, & A : B &= A_{ij}B_{ij}, & (u\times v)_i &= \varepsilon_{ijk} u_j v_k,\\
(Au)_i &= A_{ij}u_j, & (uA)_i &= u_j A_{ji}, & (AB)_{ij} &= A_{ik}B_{kj},\\
(A^{\top})_{ij} &= A_{ji}, & |u| &= \sqrt{u_i u_i}, & |A| &= \sqrt{A_{ij}A_{ij}}.
\end{aligned}
```

The decompositions are ``\operatorname{sym}(A)=\tfrac{1}{2}(A+A^{\top})``,
``\operatorname{skew}(A)=\tfrac{1}{2}(A-A^{\top})``, ``\operatorname{dev}(A)=A-\tfrac{1}{3}(\operatorname{tr}A) I``,
so ``\operatorname{sym}+\operatorname{skew}=\mathrm{id}`` and ``\operatorname{tr}\operatorname{dev}(A)=0``.
The trace ``\operatorname{tr}(A)=A_{ii}`` — the first tensor invariant that `dev` removes — is exposed as
`tr`/`tr!`, and being linear it is representation-preserving (the trace of the spectral coefficients is
the spectral representation of ``\operatorname{tr}A``). The **third** invariant, the determinant
``\det A=\varepsilon_{ijk}A_{1i}A_{2j}A_{3k}=I_3`` (`det`/`det!`), is a homogeneous cubic form in the
components, hence
**nonlinear** — physical-space only, like the norm — and multiplicative ``\det(AB)=\det A \det B``; it
reuses the one shared formula builder, so it mirrors `tr` onto both fields and point-values.
``\checkmark`` the `mul!` family carries the α/β accumulate ``\texttt{dest}=\alpha(\cdot)+\beta \texttt{dest}``,
and the weighted combination ``\alpha a+\beta b`` (`combine!`) is its linear two-field peer — coefficientwise,
hence representation-preserving and alias-safe, with ``\alpha=\beta=1`` the plain `add!`.

**Backs** [Architecture](architecture.md) §2, §6, decision 27, and the `FieldAlgebra` docstrings.
**Checked by** `test/fieldalgebra.jl` (and `test/pointvalues_algebra.jl` for the identical point-value
mirror) — dot/cross, tensor products with α/β, transpose, norms, the trace, the determinant (against a
per-point LU oracle), the weighted combination, and the sym/skew/dev identities.

The **arbitrary fiber map** (`map!`/`map`, decision 48) lifts a chosen map on the fibers,
``\varphi : V_1 \times \dots \times V_m \to U``, to a section map applied pointwise over the base: at each
base point ``x``, ``\texttt{destination}(x) = \varphi\bigl(s_1(x), \dots, s_m(x)\bigr)`` for sources
``s_1, \dots, s_m``. The output fiber space ``U`` — written ``U`` rather than ``W``, which this page reserves for the
gather operator — hence `destination`'s tensor order — is ``\varphi``'s
codomain, which need not match the inputs' (``\varphi = \det`` sends ``V = \mathbb R^{3\times3} \to
\mathbb R``). It is the section-valued companion of the mapped reductions (which instead reduce ``\varphi``
over the base) and the arbitrary-``\varphi`` generalization of the named vertical operations above; a
general ``\varphi`` is nonlinear, so — like ``\det`` and the norm — it is **physical-space only** on
fields (invariant 1), and representation-free on point-values. The single-source form carries the α/β
accumulate ``\texttt{destination} = \alpha \varphi(\texttt{source}) + \beta \texttt{destination}``.
``\checkmark``

**Backs** [Architecture](architecture.md) §2, decision 48, and the `map!` / `map` docstring.
**Checked by** `test/fieldalgebra.jl` and `test/pointvalues_algebra.jl` (against the named operations as
oracles, ``\exp\circ\det`` hand references, order changes, multi-input, α/β, aliasing, and the
physical-only absence), GPU parity in `test/gpu/suite.jl`, allocation-freedom in `test/allocations.jl`,
and the fused-ideal element traffic in `test/pass_audit.jl`.

## Differential operators (`DifferentialOperators`)

Design rationale: [Architecture](architecture.md) §4.

Each operator ``L`` is **diagonalized** by ``\mathcal F`` into a pointwise multiplier ``\hat L`` — the
intertwiner square ``\mathcal F\circ L = \hat L\circ\mathcal F`` — applied coefficientwise in spectral
representation (`src/DifferentialOperators.jl`):

```math
\begin{aligned}
\nabla &\to \mathrm{i}k, & \nabla\cdot &\to \mathrm{i}k\cdot, & \nabla\times &\to \mathrm{i}k\times,\\
\Delta &\to -|k|^2, & \Delta^{-1} &\to -|k|^{-2}\ (0\text{ at }k=0), & \mathbb P &\to \mathrm{id} - \frac{a a^{\top}}{a \cdot a}\ (\mathrm{id}\text{ where } a\cdot a = 0).
\end{aligned}
```

**Nyquist split** (even axes, deliberate — `FieldSpectralMultipliers`): the **derivative** wavenumber is
**zeroed** at Nyquist (the Nyquist mode is a real cosine, so ``\mathrm{i}k_N`` would break reality), while the
**squared** wavenumber keeps the true ``k^2`` (correct ``\Delta`` / ``\Delta^{-1}``). Here ``a``
denotes the derivative-wavenumber vector, so the ``a`` in ``\mathbb P``'s multiplier above is that
derivative wavenumber — the projector is built entirely from that one family (decision 42), and
sub-Nyquist ``a = k``. Identities, each a one-line spectral check:

```math
\begin{gathered}
\nabla\cdot(\nabla\times u) = 0\ \ \bigl(k\cdot(k\times\hat u)=0\bigr), \qquad
\nabla\times(\nabla\phi) = 0\ \ \bigl(k\times \mathrm{i}k\hat\phi=0\bigr), \\
\mathbb P^2 = \mathbb P, \qquad \nabla\cdot(\mathbb P u) = 0, \quad\checkmark
\end{gathered}
```

all four unconditional — the first two because `curl`, `divergence`, and `gradient` share the one
derivative-wavenumber family, the last two because ``\mathbb P = \mathrm{id} - (a a^{\top})/(a \cdot a)``
is built entirely from that same family (decision 42), the Nyquist planes included. The dissipation
identity alone is scoped: on the resolved band — every mode off the even-axis Nyquist planes —

```math
\langle \Delta\phi,\phi\rangle = -\lVert\nabla\phi\rVert^2 \le 0, \quad\checkmark
```

since ``\Delta`` keeps the true ``k^2`` (invariant 5) against ``\nabla``'s Nyquist-zeroed derivative
family; with Nyquist content only the sign ``\langle\Delta\phi,\phi\rangle \le 0`` survives
(`test/adjointness.jl` scopes its dissipation fixtures sub-Nyquist and asserts the sign
unconditionally; the projector identities are pinned with full-spectrum Nyquist content in
`test/differentialoperators.jl`).

(``\mathbb P`` and ``\Delta`` are self-adjoint — their multipliers ``\mathrm{id}-(a a^{\top})/(a \cdot a)``, ``-|k|^2`` are
real symmetric.)

The **divergence is the negative adjoint of the gradient**, the one relation here between sections of
*different* tensor order — ``\nabla : \Gamma_G^{R=0} \to \Gamma_G^{R=1}`` and
``\nabla\cdot : \Gamma_G^{R=1} \to \Gamma_G^{R=0}``, so the two inner products below are taken in
different spaces (scalar sections on the right, vector sections on the left):

```math
\langle \nabla\phi, u\rangle_{\Gamma^{R=1}} = -\langle \phi, \nabla\cdot u\rangle_{\Gamma^{R=0}},
\quad\checkmark
```

because the gradient's multiplier is ``\mathrm{i}a`` and the divergence's the contraction ``\mathrm{i}a\cdot``
with the same derivative-wavenumber family ``a``: moving the factor across the Hermitian pairing
conjugates it, and ``\overline{\mathrm{i}a} = -\mathrm{i}a`` for real ``a`` supplies the sign. Unconditional
— it needs only that both operators read one derivative family, the Nyquist planes included, which
invariant 5 guarantees. Pinned in `test/adjointness.jl`.

The **`curl` is self-adjoint** on the same pairing,

```math
\langle \nabla\times u, v\rangle = \langle u, \nabla\times v\rangle, \quad\checkmark
```

because its multiplier is ``\mathrm{i}`` times the real antisymmetric matrix ``[a]_\times`` (the cross-product
matrix of the derivative wavenumber ``a``, so ``[a]_\times^{\top} = -[a]_\times``): the transpose flips the
antisymmetric matrix's sign and conjugating the pairing's other slot flips ``\mathrm{i}``'s, and the two
cancel. Unconditional — it needs only that one derivative-wavenumber family, Nyquist planes included.
Pinned in `test/adjointness.jl`.

The **symmetric gradient** ``\operatorname{sym}\nabla`` (`symmetric_gradient`) is the **fused symmetric peer**
of ``\nabla\times`` (which takes the antisymmetric part of ``\nabla u``): its multiplier is the symmetric
part of ``\nabla u``'s multiplier ``\mathrm{i}k_j\hat u_i``,

```math
\hat S_{ij} = \tfrac{\mathrm{i}}{2} (k_j\hat u_i + k_i\hat u_j), \qquad S = \operatorname{sym}(\nabla u), \quad\checkmark
```

formed without materializing the full gradient tensor and sharing the derivative-wavenumber Nyquist zeroing.

**The kernel-composed forms** (decision 32): for a scalar Fourier symbol ``\hat g : K \to \mathbb C``
(``K`` the stored mode set; the kernel `convolve!` takes) and the operator multipliers above, the
scalar commutes through both the matrix symbol and the contraction — per mode ``k``, with
``\hat u(k) \in \mathbb C^3``,

```math
\hat g \Bigl(\mathrm{id} - \frac{a a^{\top}}{a \cdot a}\Bigr) \hat u = \Bigl(\mathrm{id} - \frac{a a^{\top}}{a \cdot a}\Bigr) (\hat g \hat u)
\in \mathbb C^3, \qquad
\hat g  \bigl(\mathrm{i}k\cdot\hat u\bigr) = \mathrm{i}k\cdot(\hat g \hat u) \in \mathbb C
\qquad\checkmark
```

so the composition "operator then convolve" is itself a single Fourier multiplier (the product of
symbols), and `helmholtz_projection!(dest, f, m, kernel, α, β)` /
`divergence!(dest, f, m, kernel, α, β)` compute ``\alpha \hat g  \hat L \hat u + \beta 
\widehat{\texttt{dest}}`` in one pass. **Alias safety of the one-pass projection**: the kernel is a
mode-local map — the values written at mode ``k`` depend only on values read at mode ``k``, and every
read of a mode precedes its writes — so `destination === field` computes the same function
(bitwise-tested). The Nyquist split is inherited unchanged: the composed symbol is a product of
per-mode scalars, so each factor keeps its own family's Nyquist value.

**Backs** [Architecture](architecture.md) §4, §7, decisions 27, 32.
**Checked by** `test/differentialoperators.jl` (analytic round-trips, the Nyquist split,
``\nabla\cdot(\nabla\times)=0``, ``\nabla\times\nabla=0``, ``\operatorname{sym}\nabla u=\operatorname{sym}(\nabla u)``,
the fused-equals-sequential kernel compositions, and the bitwise aliased projection)
and `test/adjointness.jl` (self-adjointness, exactly idempotent projection, negative-semidefinite Laplacian).

## Convolution (`Convolution`)

Design rationale: [Architecture](architecture.md) §11.

By the convolution theorem, periodic convolution is the coefficientwise spectral product; `convolve`
applies a scalar kernel ``\hat g`` (a `SpectralKernel`, broadcast over the fiber) with α/β accumulate
(`src/Convolution.jl`):

```math
\mathcal F(f \star g) = \hat f\cdot\hat g, \qquad
\widehat{\texttt{dest}} = \alpha \hat f \hat g + \beta \widehat{\texttt{dest}}. \quad\checkmark
```

This is exactly the product invariant 1 bans as ``*`` — it is convolution, not the (absent) pointwise
spectral product. The neutral kernel builders: `spectral_cutoff` is the sharp low-pass ``\hat g(k)=1`` for
``|k|\le k_c`` (else ``0``), **idempotent** (``\hat g^2=\hat g``, a projection); `spectral_band` its annular
``k_{\mathrm{lo}}\le|k|\le k_{\mathrm{hi}}`` generalization (cutoff is ``k_{\mathrm{lo}}=0``); `radial_kernel` the builder taking any real function
of ``|k|^2`` (its ``\sigma = \mathrm{identity}`` case being that coordinate itself); and `assignment_window` the linear/CIC mass-assignment window

```math
\hat W(k) = \prod_{a=1}^{3}\operatorname{sinc}^2\Bigl(\tfrac{k_a \Delta x_a}{2}\Bigr),
\qquad \operatorname{sinc} y = \tfrac{\sin y}{y},
```

undone by dividing (deconvolution).

The fifth builder, `translation_kernel`, is the shift theorem's multiplier: for a physical displacement
``h = (h_1, h_2, h_3)`` it is the transform of the Dirac delta displaced to ``h``,
so convolving carries the field ``f`` at position ``x`` to ``f(x - h)``. Write ``k_a`` for the
true signed wavenumber of axis ``a``, ``\tilde k_a`` for the derivative wavenumber (equal to
``k_a`` except at the Nyquist frequency of an even-length axis, where it is zeroed — invariant 5),
``N_a`` for the number of points on that axis and ``\Delta x_a`` for its grid spacing. The implemented
multiplier is the separable product

```math
\hat g_h(k) = \prod_{a=1}^{3}
  \bigl[  \cos(k_a h_a) - \mathrm{i} \sin(\tilde k_a h_a)  \bigr].
```

Three statements, each expanded against the code and tested:

- **A pure phase away from Nyquist.** Where no component of ``k`` sits at a Nyquist frequency we have
  ``\tilde k_a = k_a``, and ``\cos`` is even, so each factor collapses to
  ``\cos(k_a h_a) - \mathrm{i} \sin(k_a h_a) = e^{-\mathrm{i} k_a h_a}``, whence
  ``\hat g_h(k) = e^{-\mathrm{i} k \cdot h}``, of unit modulus. ``\checkmark``
- **Reality: the kernel is Hermitian.** ``\hat g_h(-k) = \overline{\hat g_h(k)}`` on the discrete
  frequency torus, so `convolve` carries a real field to a real field. Each non-Nyquist factor conjugates
  under ``k_a \mapsto -k_a``; each Nyquist factor is the *real* number
  ``\cos(\pi h_a / \Delta x_a)``, hence its own conjugate — which is what the statement needs, the
  Nyquist frequency being its own negative modulo ``N_a``. The two candidate kernels fail here or below: the
  true phase ``e^{-\mathrm{i} k\cdot h}`` is *not* Hermitian at Nyquist for a fractional displacement, and
  the all-derivative-wavenumber kernel is Hermitian but carries the wrong value. ``\checkmark``
- **Whole-cell displacements are exact.** For ``h_a = m_a \Delta x_a`` with ``m \in \mathbb Z^3`` every
  factor is the exact phase — the Nyquist one reducing to ``\cos(\pi m_a) = (-1)^{m_a}`` — and the
  convolution is exactly the index shift, `circshift` by ``m`` cells. ``\checkmark``

**The exponential radial kernel** (`exponential_convolve!`, decision 33) is the symbol
``\hat g(k) = \exp(c |k|^2 + s \hat w(k))`` with ``c, s \in \mathbb R`` and ``\hat w`` a real-valued
per-mode field, evaluated lazily (never materialized). Three statements, each expanded against the
code and tested:

- **Reality is automatic.** ``|k|^2`` is real and even in ``k`` and ``\hat w`` is required real and
  (as a stored half-spectrum of a real field) Hermitian, so ``\hat g`` is real and even —
  ``\hat g(-k) = \hat g(k) = \overline{\hat g(k)}`` — and a real field stays real for **every**
  ``c, s``; no Nyquist split arises (the exponent uses the true squared wavenumber, invariant 5's
  Laplacian family). ``\checkmark``
- **It is the heat semigroup's symbol.** The Laplacian's symbol is ``-|k|^2``, so the operator
  ``e^{-c\Delta}`` has symbol ``\exp(-c \cdot (-|k|^2)) = \exp(c|k|^2)`` — for ``c \le 0`` the
  periodic Gaussian smoothing at length ``\sqrt{-2c}`` — exact on the grid because operator and
  exponent share the same wavenumber family. ``\checkmark``
- **A scalar exponent offset is redundant.** ``\exp(c|k|^2 + s_0) = e^{s_0} \exp(c|k|^2)`` for a
  constant ``s_0``, which is the accumulate weight ``\alpha``'s job — hence the deliberate absence of
  a scalar-offset method; only the per-mode ``s \hat w`` earns a signature slot. ``\checkmark``

The **kernel-composed combination** (`combine!(dest, α, a, β, b, kernel)` and the exponential
two-operand form) is the distribution of a diagonal symbol over a linear combination — per mode,
``\hat g (\alpha \hat a + \beta \hat b) = \alpha \hat g \hat a + \beta \hat g \hat b`` — computed
as the left-hand side in one coefficientwise pass; with ``b = \texttt{dest}`` it is the filtered
accumulate, alias-safe because the map is mode-local. ``\checkmark``

**Kernel storage is a representation, not a meaning.** A kernel *is* the multiplier function
``\hat g : K \to \mathbb C`` on the stored half-spectrum ``K``; how its values reach an operation is a
storage choice, and the package carries four. Write ``k_a`` for the signed wavenumber of axis
``a`` and ``|k|^2 = \sum_a k_a^2``:

- **stored** (`StoredKernel`), ``\hat g`` tabulated one coefficient per mode (``O(N^3)`` storage) — the
  class `materialize_kernel` returns, and the wrapper that gives a field of coefficients the kernel role;
- **separable** (`SeparableKernel`), ``\hat g(k) = \prod_{a=1}^{3} g_a(k_a)`` held as its three factors
  ``g_a : \mathbb R \to \mathbb C`` tabulated per axis (``O(N)``) — the class `translation_kernel`
  and `assignment_window` return, both being products over axes by construction;
- **radial** (`RadialKernel`), ``\hat g(k) = \sigma(|k|^2)`` held as the real symbol ``\sigma : \mathbb R \to \mathbb R``
  itself and evaluated per mode (``O(1)``) — the class `spectral_cutoff`, `spectral_band` and
  `radial_kernel` return;
- a **product** (`ProductKernel`), ``\hat g = \hat g_1 \hat g_2`` for any two kernels held unmultiplied and
  evaluated in one pass — what a composition gives whenever it cannot be collapsed into a single kernel.

Two statements, each expanded against the code and tested:

- **The classes are interchangeable.** For every entry point taking a kernel, and every storage class,
  the computed coefficients are those of the same ``\hat g``. The associations are chosen to make this
  hold **bitwise**, not merely to rounding: the radial route sums ``(\kappa_1^2 + \kappa_2^2) + \kappa_3^2``
  in the order the stored path's broadcast associates it, and the separable route multiplies its factors
  in axis order. ``\checkmark``
- **Composition is closed within the two compressed families but not the stored one.** Radial
  composed with radial is radial **when both are radial in the same** ``|k|^2`` — that is, over *canonical* multiplier sets of one concrete type — canonical meaning built by the convenience constructor from the grid itself, as opposed to a caller's own set supplied through the explicit six-array form — which is the hypothesis decision 61 made a dispatch condition;
  ``\sigma_1 \sigma_2`` is then again a function of that ``|k|^2``, while a pairing that fails it keeps both
  operands as a `ProductKernel` rather than silently evaluating ``\sigma_2`` at the first set's
  coordinates. Separable
  composed with separable is separable, per axis; and radial composed with separable is a `ProductKernel`,
  since a general ``\sigma(|k|^2)`` admits no factorization over axes (the exponential is the exception)
  and ``\prod_a g_a`` no reduction to
  ``|k|^2``. Stored composed with stored is deliberately **not** closed: multiplying the coefficients
  would be an ``O(N^3)`` pass building a third array, so the pair is kept as a `ProductKernel` too.
  Composition therefore never forces a materialization. ``\checkmark``

The reciprocal `inv` is the pointwise ``1/\hat g``, defined on **every** class and closed within each:
separable per axis, radial in the symbol, product factorwise, and stored coefficientwise — the last
with an explicit zero check, since it is the one class that can test its coefficients. It is what
deconvolves: ``\hat g^{-1}\hat g = 1``
wherever ``\hat g`` is nonzero, which is why a sharp cutoff has no inverse and a window has one on its
support.

**Backs** [Architecture](architecture.md) §11, decisions 20–22, 28, 33, 50, 51, 60, 61.
**Checked by** `test/convolution.jl` — the translation kernel ``e^{-\mathrm{i} k_a m \Delta x_a} \Leftrightarrow``
`circshift` (a shift of ``m`` cells; an independent physical oracle), cutoff idempotence, and
the physical-space intentional absence (the ``\operatorname{sinc}^2`` window is checked by `test/rdf.jl`); and for `translation_kernel`, `circshift` on a *random* field (one
with Nyquist content, so the Nyquist factor is exercised), the exact `DirectDFT` evaluation at the displaced
nodes for a sub-cell displacement, and the reality check that the displaced half-spectrum survives a
transform round trip (the inverse transform being the Hermitian projector); and for the decision-33
pair, the stored-kernel equality oracles, the single-mode eigenvalue ``e^{c}\cos x``, and
fused-equals-sequential for both two-operand forms; and for the storage classes, the walk over every
kernel-taking entry point that requires each class to agree **bitwise** with the materialized product,
together with the composition cases that pin which class each pairing lands in.

## Reductions (`Reductions`)

Design rationale: [Architecture](architecture.md) §12.

The L²/measure structure (`src/Reductions.jl`). The `integral` is **extensive** (against the base measure —
grid cell volume, point counting); `inner` is the **normalized** L² product (declared above); `l2norm`
``=\sqrt{\langle f,f\rangle}``:

```math
\begin{gathered}
\int f\,\mathrm{d}\mu = \frac{|\Omega|}{N}\sum_n f_n\ (\mathrm{grid}),\quad \sum_p f_p\ (\mathrm{points}); \\
\int f\,\mathrm{d}\mu = \mathrm{measure}\cdot\texttt{mean}. \quad\checkmark
\end{gathered}
```

**`integral` and `mean` in spectral representation** (the zero mode, no transform): the unnormalized
forward gives the DC coefficient ``\hat f(0) = \sum_x f_x`` (real for a real field), so

```math
\texttt{mean}(f) = \frac{\hat f(0)}{N}, \qquad \int_\Omega f\,\mathrm{d}\mu = \frac{|\Omega|}{N} \hat f(0). \quad\checkmark
```

Both equal the physical reductions (since ``\sum_x f_x = \hat f(0)``), read from the same zero-mode slot
the constant-add writes; `lpnorm`/`maximum` have no single-coefficient form.

**Variance, standard deviation, and covariance** (decision 49). The reductions ``\operatorname{var}``/``\operatorname{std}``
are **scalar-only**. The *population* second central moment is what Parseval gives directly, as the
fluctuation energy carried by every mode but the mean:

```math
\operatorname{var}(f)\bigm|_{\texttt{corrected=false}} = \langle f, f\rangle - \langle f\rangle^2
  = \frac{1}{N^2}\sum_{k\ne 0} \alpha(k) |\hat f(k)|^2, \quad\checkmark
```

with ``\alpha(k)`` the rfft half-spectrum multiplicity of mode ``k`` and the ``1/N^2`` the
normalization ``\langle\cdot,\cdot\rangle`` itself carries. The **default** applies Bessel's
correction on top,

```math
\operatorname{var}(f) = \frac{B}{B-1}\Bigl(\langle f, f\rangle - \langle f\rangle^2\Bigr),
  \quad\checkmark
```

with ``B`` the base count — ``N`` cells for a grid, ``M`` points for a point set, `var` being defined
on both exactly as `cov` is — so the identity reads from **both** representations, with ``\operatorname{std} = \sqrt{\operatorname{var}}``. A vector section's coordinate-free
second central moment is the **covariance tensor** ``R = \operatorname{cov}(u) \in
\operatorname{Sym}^2(\mathbb R^3)``,

```math
R_{ij} = \frac{B}{B-1}\Bigl(\operatorname{mean}(u \otimes u) - \bar u \otimes \bar u\Bigr)_{ij}
       = \frac{1}{B-1}\sum_n (u_{n,i} - \bar u_i)(u_{n,j} - \bar u_j), \quad\checkmark
```

where ``B`` is the count of the base the section lives over — ``N`` cells for a grid, ``M`` points for
a point set — since `cov` is defined on both. The result is
a symmetric `FiberTensor2` whose diagonal is the per-component variance a fiber-preserving `var` would
have returned; ``\operatorname{std} = \sqrt{\operatorname{var}}`` has no canonical vector form, so it is
not offered. Physical-only (the outer product is nonlinear). **Checked by** `test/reductions.jl` (scalar
var/std vs a two-pass reference and the equal spectral form; `cov` vs a per-point covariance, its
symmetry, and its per-component diagonal) and GPU parity in `test/gpu/suite.jl`.

**The mapped forms** (decision 30). Write ``V`` for the fiber — the vector space over one base point, so
``V = \mathbb{R}`` at tensor order ``0``, ``\mathbb{R}^3`` at order ``1``, ``\mathbb{R}^{3\times3}`` at
order ``2`` — and ``f_n \in V`` for the fiber value of the section at base point ``n``. Given a map
``\varphi : V \to U`` into any space ``U`` carrying the reducing operation (``W`` on this page is the
gather operator, so the generic codomain takes another letter), the mapped reductions are the
bare ones applied to ``\varphi \circ f``:

```math
\begin{gathered}
\texttt{mean}(\varphi, f) = \frac{1}{N}\sum_n \varphi(f_n), \\
\int_\Omega (\varphi \circ f)\,\mathrm{d}\mu = \frac{|\Omega|}{N}\sum_n \varphi(f_n)\ (\mathrm{grid}), \quad
\sum_p \varphi(f_p)\ (\mathrm{points}), \quad\checkmark
\end{gathered}
```

The order statistics reduce the same mapped values, with a maximum or a minimum in place of the sum.
Two consequences are worth stating
because they are what the tests pin. Taking the identity map recovers the bare reduction
exactly, ``\texttt{mean}(\mathrm{id}, f) = \texttt{mean}(f)``, including its fiber-valued result at
order ``1`` and ``2``. And with ``\varphi = \lVert\cdot\rVert`` the order statistic coincides with the
existing supremum norm, ``\max_n \lVert f_n\rVert = \lVert f\rVert_\infty``, so `maximum(norm, u)` and
`lpnorm(u, Inf)` are the same number by different routes — the first without materializing
``\varphi \circ f`` as a section. The mapped forms exist only on fields in physical representation and point-values:
``\varphi`` is nonlinear in general, so it has no coefficientwise meaning on a spectral representation
(invariant 1). Tests: `test/reductions.jl` (the analytic diagonal-tensor invariants, the identity-map
agreement, the `lpnorm` coincidence, an independent per-point reduction, and the spectral
absence), `test/allocations.jl` (the family allocates zero bytes), `test/gpu/suite.jl` (device parity).

**`inner` in spectral representation** (Parseval, no transform): the discrete Parseval identity
``\tfrac{1}{N}\sum_x f_x\cdot g_x = \tfrac{1}{N^2}\sum_{\text{all }k}\hat f(k) \overline{\hat g(k)}`` together with
the rfft half-spectrum (each ``k_x>0`` mode stands for its conjugate partner, so it counts twice; the
self-conjugate ``k_x=0`` and even-Nyquist planes count once) gives

```math
\langle f, g\rangle = \frac{1}{N^2} \mathrm{Re}\Bigl(2\sum_{k_x\ge0}\hat f \overline{\hat g}
-\sum_{\text{zero plane}}\hat f \overline{\hat g}-\sum_{\text{Nyquist plane}}\hat f \overline{\hat g}\Bigr) \quad\checkmark
```

(the Nyquist sum only for even ``N_x``). **`radial_spectrum`** bins this with the half-spectrum weight
``\alpha(k)`` (``1`` on the self-conjugate planes, ``2`` else) over ``|k|``-shells, and
**`radial_correlation`** is the Wiener–Khinchin dual (the inverse transform ``\mathcal F^{-1}`` is `to_physical`, the normalized
inverse):

```math
\begin{gathered}
P(\kappa_i) = \frac{1}{N^2}\sum_{\mathrm{round}(|k|/\Delta k)=i}\alpha(k)\sum_c |\hat f_c(k)|^2, \\
C(r) = \frac{1}{N} \mathcal F^{-1}\Bigl(\textstyle\sum_c|\hat f_c|^2\Bigr)(r),
\end{gathered}
```

with ``P(\kappa)`` the shell **power spectrum** (the consumer's physics energy spectrum is
``E(\kappa)=\tfrac{1}{2}P(\kappa)``), each refining `inner` exactly:
``\sum_i P(\kappa_i) = \langle f,f\rangle`` and ``C(0) = \langle f,f\rangle``.
``\checkmark`` The two-field forms (cross-power ``\sum_c\mathrm{Re}(\hat f_c\overline{\hat g_c})``,
cross-correlation ``C_{fg}(r)=\tfrac{1}{N}\mathcal F^{-1}(\overline{\hat f} \hat g)(r)``) refine the mixed
``\langle f,g\rangle`` (``\sum P_{fg}=C_{fg}(0)=\langle f,g\rangle``), are symmetric in ``f,g``, and may be
negative.

**`weighted_inner`** applies a real Fourier multiplier ``w(k)`` inside the same Parseval sum,

```math
\langle f, w g\rangle = \frac{1}{N^2}\sum_k \alpha(k) w(k)\sum_c \mathrm{Re}\bigl(\hat f_c \overline{\hat g_c}\bigr), \quad\checkmark
```

generalizing `inner` (the ``w\equiv1`` case) — the reduction-dual of `convolve`. For ``w=|k|^2`` (the
squared-wavenumber symbol, true ``k^2`` at Nyquist) it is the Dirichlet energy ``\langle f,-\Delta g\rangle``;
and since ``w`` is real it equals the naive ``\langle w\star f, w\star g\rangle`` **iff** ``w`` is idempotent
(``w^2=w``, a sharp band), not for a general ``w``. Symmetric in ``f,g``, may be negative, spectral-only. The realness of ``w`` is a **hypothesis of the
statement**, not a convenience: with a complex multiplier the pairing is not an inner product, so the
operation refuses one wherever the kernel's type settles the question (decision 62). The one class
whose type cannot settle it is `StoredKernel`, whose storage is complex whatever multiplier it holds;
there the real part is taken, as documented.

**`lpnorm`** is the ``p``-family around that ``L^2`` pair: on a grid
``\lVert f\rVert_p = \bigl(\tfrac{1}{N}\sum_n \lVert f_n\rVert^p\bigr)^{1/p}`` and on a point-set the
``M``-normalized analogue, with ``\lVert f_n\rVert`` the fiber Euclidean magnitude; ``p = 2``
delegates to `l2norm` ``= \sqrt{\langle f,f\rangle}`` and ``p = \infty`` is
``\max_n \lVert f_n\rVert`` (`src/Reductions.jl`). Physical fields and point-values only.
``\checkmark`` **Checked by** `test/reductions.jl` (the ``p = 2`` delegation to `l2norm` and the
``p = \infty`` coincidence with `maximum(norm, u)`).

**Backs** [Architecture](architecture.md) §12, decisions 18/21/22/27/30/49/62.
**Checked by** `test/reductions.jl` — ``\langle\sin\rangle=0``, ``\langle\sin^2\rangle=\tfrac{1}{2}``,
the spectral `integral`/`mean` against the physical reductions (``\langle c\rangle=c``, ``\int c\,\mathrm{d}x=c|\Omega|``),
``\sum_i P(\kappa_i)=\langle f,f\rangle``, ``C(0)=\langle f,f\rangle`` against an independent binned-circshift oracle, the
co-spectrum signs, and `weighted_inner` against ``\langle f,-\Delta g\rangle`` and the idempotent-band identity.

## Interpolation / anterpolation (`Interpolation`)

Design rationale: [Architecture](architecture.md) §10.

The base gather ``W_b : \mathbb R^N \to \mathbb R^M`` has entries ``(W_b)_{pn} = w_n(x_p)`` (the local
stencil weights, `src/Interpolation.jl`), a **partition of unity** — for each point the row sums to one,
``\sum_n (W_b)_{pn} = 1``, i.e. ``W_b \mathbf 1_N = \mathbf 1_M`` with ``\mathbf 1_N \in \mathbb R^N`` and
``\mathbf 1_M \in \mathbb R^M`` (two **distinct** all-ones vectors). Both transfer maps are
**fiber-preserving** (the trivial bundle leaves the fiber by the identity):

```math
\begin{gathered}
W := W_b \otimes \mathrm{id}_V : \Gamma_G \to \Gamma_P, \\
W^{\top} := W_b^{\top} \otimes \mathrm{id}_V : \Gamma_P \to \Gamma_G .
\end{gathered}
```

**Adjoint, raw (counting) form.** For ``f \in \Gamma_G``, ``q \in \Gamma_P``:

```math
\sum_p (Wf)_p\cdot q_p
= \sum_p \sum_n (W_b)_{pn} (f_n\cdot q_p)
= \sum_n f_n\cdot (W^{\top} q)_n \qquad\checkmark
```

**Adjoint, normalized inner.** Dividing the two sides by ``M`` and ``N``:

```math
M \langle Wf, q\rangle_{\mathrm{pts}}
= \sum_p (Wf)_p\cdot q_p
= \sum_n f_n\cdot(W^{\top}q)_n
= N \langle f, W^{\top} q\rangle_{\mathrm{grid}} \qquad\checkmark
```

So the *bare* ``\langle Wf, q\rangle_{\mathrm{pts}} = \langle f, W^{\top}q\rangle_{\mathrm{grid}}`` is **false**
unless ``N = M`` — the two sides differ by ``N/M``. This is the slip the formalization catches: it
type-checks, but the expansion does not match. The clean adjunction uses the measure-adjoint
``\iota_* := (N/M) W^{\top}``:

```math
\langle f, \iota_* q\rangle_{\mathrm{grid}}
= \frac{1}{N}\sum_n f_n\cdot\tfrac{N}{M} (W^{\top}q)_n
= \frac{1}{M}\sum_n f_n\cdot(W^{\top}q)_n
= \langle Wf, q\rangle_{\mathrm{pts}} \qquad\checkmark
```

**Conservation** (sum the deposit over the grid, per fiber component):

```math
\sum_n (W^{\top} q)_n
= \sum_n\sum_p (W_b)_{pn} q_p
= \sum_p \Bigl(\textstyle\sum_n (W_b)_{pn}\Bigr) q_p
= \sum_p q_p \in V \qquad\checkmark
```

(uses the partition-of-unity row sum ``\sum_n (W_b)_{pn} = 1``).

**Backs** [Architecture](architecture.md) §10 and the `Interpolation` module docstring.
**Checked by** `test/interpolation_transfer.jl` — the measure-weighted adjointness
``M \langle Wf, q\rangle_{\mathrm{pts}} = N \langle f, W^{\top}q\rangle_{\mathrm{grid}}``, conservation (partition of unity), and
polynomial reproduction.

## Spectral transfer: `DirectDFT` / `NUFFT` (`Interpolation`)

Design rationale: [Architecture](architecture.md) §10, decision 23.

The exact Fourier transfer between a field's spectral coefficients and off-grid points, and its fast
windowed form — the spectral siblings of the spline ``W`` / ``W^{\top}`` above. `DirectDFT` is the literal
``O(NM)`` sum (`src/Interpolation.jl`; ``o`` the grid origin, ``\alpha`` the half-spectrum Parseval weight,
``1`` on the self-conjugate planes and ``2`` else):

```math
\begin{gathered}
\text{type-2 (interpolate)}\quad f(x_p) = \frac{1}{N}\sum_{\text{stored }k}\alpha(k) \mathrm{Re}\bigl(\hat f(k) e^{\mathrm{i} k\cdot(x_p-o)}\bigr), \\
\text{type-1 (anterpolate)}\quad (W^{\top}q)(k) = \sum_p q_p e^{-\mathrm{i} k\cdot(x_p-o)} .
\end{gathered}
```

Type-2 reproduces the band-limited field exactly (it matches `to_physical` at the grid nodes), and the
pair satisfies the same measure-weighted adjoint as the splines,
``M \langle W\hat f, q\rangle_{\mathrm{pts}} = N \langle \hat f, W^{\top}q\rangle_{\mathrm{grid}}``. ``\checkmark``
**`NUFFT`** is its ``O(N\log N + M)`` form — spread → oversampled (``\sigma=2``) FFT → deconvolve by
``1/\hat\psi`` (window ``\psi``, transform ``\hat\psi``) — exact to a tolerance ``\varepsilon`` against
`DirectDFT` on the resolved sub-Nyquist band (the rfft Nyquist is projected out), an exact adjoint pair there.

**Backs** [Architecture](architecture.md) §10, decision 23.
**Checked by** `test/transfer_spectral.jl` — `interpolate` == `to_physical` at the nodes, exact off-grid
reconstruction, the adjoint relation (``R = 0, 1, 2``), and `NUFFT` vs `DirectDFT` to ``\varepsilon``.


## Storage families (`Fields`, `Points`, `Convolution`)

Design rationale: [Architecture](architecture.md) §13, decision 63.

A **storage family** is where a section's array lives — host memory, or one vendor's device memory. It
is not part of the mathematical object: a section is a map from the base to the fiber, and which
allocator holds its samples is no more intrinsic than which page of RAM they occupy. Writing
``\mathcal{S}`` for a section and ``\mathcal{A}`` for a family, the move is therefore stated as an
identity, not a computation:

```math
\begin{aligned}
\operatorname{adapt}(\mathcal{A}, \mathcal{S}) &= \mathcal{S}', \\
\mathcal{S}'(n) &= \mathcal{S}(n) \quad \forall n \in \text{base}, \\
\mathcal{C}(\mathcal{S}') &= \mathcal{C}(\mathcal{S}).
\end{aligned}
```

Here ``\mathcal{C}(\mathcal{S})`` is the **context** of a section — everything it carries besides its
samples, namely the grid, the Fourier layout, the origin and the tensor order — and the element type is
likewise unchanged. Only the family differs. Two consequences follow and are what the tests assert.
First, the move **commutes with every operation**: for an operation ``\Phi`` defined on both families,
``\Phi(\operatorname{adapt}(\mathcal{A}, \mathcal{S})) = \operatorname{adapt}(\mathcal{A}, \Phi(\mathcal{S}))``
up to the floating-point reassociation any backend is free to make, which is why the device suite can
compare a moved workspace against the host result at all. Second, it is **idempotent**, and on the
family a section already occupies it is the identity map on objects, ``\operatorname{adapt}(\mathcal{A},
\mathcal{S}) \equiv \mathcal{S}``, sharing storage rather than copying. ``\checkmark``

The same statement covers the **companions** a section cannot be used without, none of which is itself a
section. A `FieldSpectralMultipliers` and each of the four kernel classes move by the identity above with
``\mathcal{C}`` reading their own context, so a moved kernel denotes the **same multiplier**,
``\hat g_{\mathcal{A}} = \hat g`` as a function of the mode, and therefore computes the same convolution
on the target family as on the source. ``\checkmark``

Precision is deliberately **not** of this kind and is not offered here: changing the element type
changes the values, and — because ``\texttt{Grid3D}`` stores the domain size, spacing and origin at the
field's own element type — it changes ``\mathcal{C}`` as well, so it is a different statement rather than a
weaker one.

`FieldTransformPlans` is the one companion that is **rebuilt rather than moved**, because an FFT plan
is not a section: it is a compiled schedule bound to one storage family. It is nonetheless determined by
data it already carries — the grid, the layout, its element type and its tensor order — so the rebuild
needs no argument, and a plan is independent of the arrays it was planned against, which is what lets
the witnesses be released immediately.

**Backs** [Architecture](architecture.md) §13, decision 63.
**Checked by** `test/adapt.jl` — value and context preservation across three layout folds, a non-zero
origin, both element types, both representations and ``R = 0, 1, 2``; the identity case; the point layer
(`PointSet` and all three point-value types); each of the four kernel classes, asserted through the
convolution it computes rather than through its storage; the `Canonical` parameter of the multipliers;
and a rebuilt plan transforming equally. Commutation with the operations is checked on device in
`test/gpu/suite.jl`, where a moved workspace reproduces the host `curl` and `convolve`.
