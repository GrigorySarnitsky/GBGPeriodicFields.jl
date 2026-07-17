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

A grid cell is a triple ``(i, j, k)``, so the scalar field over the grid is the 3-axis tensor product
``\mathbb R^{N_x}\otimes\mathbb R^{N_y}\otimes\mathbb R^{N_z}`` (the array ``f_{ijk}``) — one real per cell.
As a vector space this is ``\mathbb R^N`` with ``N = N_x N_y N_z``: a column-major flat index ``n`` collapses
``(i, j, k)``, and the global pairings below use that flat ``n`` (the per-axis structure is irrelevant to
them — it is what the tensor-product stencil weights ``w_{i_1}w_{i_2}w_{i_3}`` and the differential
multipliers ``\mathrm{i} k_a`` act on). The factor ``\otimes V`` then attaches the fiber, so a grid section is a ``V``-value *at
each cell* (``\cong V^N``; a single real only in the scalar case ``R = 0``). The point base ``\mathbb R^M``
is **unstructured** — ``M`` scattered points, no product — which is exactly the structured-to-unstructured
nature of the transfer. A point's *position* ``x_p \in \mathbb R^3`` is a separate object from the value it
carries: the positions are the `PointSet` geometry (``\mathbb R^M \otimes \mathbb R^3 \cong \mathbb R^{3M}``,
themselves a vector-valued section over the points) and enter only through the transfer weights
``w_n(x_p)``, whereas ``\Gamma_P`` is the space of *values* — a ``V`` per point. So ``\Gamma_P`` is
``\mathbb R^{3M}`` only when the sampled field is a vector (``V = \mathbb R^3``); in general it is
``\mathbb R^M \otimes V``, just as the grid value space is not ``\mathbb R^{3N}``.

The transform ``\mathcal F`` (`to_spectral`, inverse `to_physical`) is the rfft isomorphism between the
physical (nodal) and spectral representations of a grid section; ``\hat f = \mathcal F f``. With the fiber
contraction ``\cdot : V \times V \to \mathbb R`` and the wavenumber ``k``, the inner products are the
package's **normalized** reductions (`inner`, `src/Reductions.jl` = `dot(data, data) / _base_count`):

```math
\langle a, b\rangle_{\text{pts}} := \frac{1}{M} \sum_{p=1}^{M} a_p\cdot b_p,
\qquad
\langle f, g\rangle_{\text{grid}} := \frac{1}{N} \sum_{n=1}^{N} f_n\cdot g_n .
```

## Representations and transforms (`Fields`, [Architecture](architecture.md) §4)

``\mathcal F`` is **forward unnormalized, inverse carrying ``1/N``** (AbstractFFTs convention,
`plan_rfft`/`plan_irfft`):

```math
\hat f(k) = \sum_{x} f(x) e^{-\mathrm{i} k\cdot x}, \qquad
f(x) = \frac{1}{N} \sum_{k} \hat f(k) e^{\mathrm{i} k\cdot x}, \qquad N = N_x N_y N_z,
```

so ``\mathcal F^{-1}\mathcal F = \mathrm{id}`` (exact to round-off). Two consequences used elsewhere:

- **Half-spectrum + conjugate symmetry.** ``f`` real ``\Rightarrow`` ``\hat f(-k) = \overline{\hat f(k)}``,
  so only ``k_x \ge 0`` is stored (`rfft_shape`: length ``N_x/2{+}1`` on the rfft axis); the ``k_x = 0``
  plane, and on an even axis the Nyquist plane, are self-conjugate.
- **Adding a real constant** ``c`` touches only the zero mode, scaled by ``N``:
  ``\mathcal F(f + c) = \hat f + c N \delta_{k,0}`` (`_spectral_constant_scale = prod(grid_size)`), since
  the unnormalized forward sums ``N`` copies of ``c`` at ``k = 0``. ``\checkmark``

**Backs** [Architecture](architecture.md) §4 and the `Fields` transform docstrings.
**Checked by** `test/fields.jl` — FFT round-trip, multipliers vs `fftfreq`/`rfftfreq`, the Nyquist
behaviour, and transform input-preservation — and `test/fieldalgebra.jl` (the constant/zero-mode invariant).

## Fiberwise algebra (`FieldAlgebra` / `FiberSections`, [Architecture](architecture.md) §2, §6)

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
``\checkmark`` the `mul!` family carries the α/β accumulate ``\mathrm{dst}=\alpha(\cdot)+\beta \mathrm{dst}``,
and the weighted combination ``\alpha a+\beta b`` (`combine!`) is its linear two-field peer — coefficientwise,
hence representation-preserving and alias-safe, with ``\alpha=\beta=1`` the plain `add!`.

**Backs** [Architecture](architecture.md) §2, §6, decision 27, and the `FieldAlgebra` docstrings.
**Checked by** `test/fieldalgebra.jl` (and `test/pointvalues_algebra.jl` for the identical point-value
mirror) — dot/cross, tensor products with α/β, transpose, norms, the trace, the determinant (against a
per-point LU oracle), the weighted combination, and the sym/skew/dev identities.

## Differential operators (`DifferentialOperators`, [Architecture](architecture.md) §4)

Each operator ``L`` is **diagonalized** by ``\mathcal F`` into a pointwise multiplier ``\hat L`` — the
intertwiner square ``\mathcal F\circ L = \hat L\circ\mathcal F`` — applied coefficientwise in spectral
representation (`src/DifferentialOperators.jl`):

```math
\begin{aligned}
\nabla &\to \mathrm{i}k, & \nabla\cdot &\to \mathrm{i}k\cdot, & \nabla\times &\to \mathrm{i}k\times,\\
\Delta &\to -|k|^2, & \Delta^{-1} &\to -|k|^{-2}\ (0\text{ at }k=0), & \mathbb P &\to I - \hat k \hat k^{\top}\ \ (\hat k = k/|k|).
\end{aligned}
```

**Nyquist split** (even axes, deliberate — `FieldSpectralMultipliers`): the **derivative** wavenumber is
**zeroed** at Nyquist (the Nyquist mode is a real cosine, so ``\mathrm{i}k_N`` would break reality), while the
**squared** wavenumber keeps the true ``k^2`` (correct ``\Delta`` / ``\Delta^{-1}``). Identities, each a
one-line spectral check:

```math
\nabla\cdot(\nabla\times u) = 0\ \ \bigl(k\cdot(k\times\hat u)=0\bigr), \qquad
\nabla\times(\nabla\phi) = 0\ \ \bigl(k\times \mathrm{i}k\hat\phi=0\bigr), \qquad
\mathbb P^2 = \mathbb P, \qquad
\langle \Delta\phi,\phi\rangle = -\lVert\nabla\phi\rVert^2 \le 0. \quad\checkmark
```

(``\mathbb P`` and ``\Delta`` are self-adjoint — their multipliers ``I-\hat k\hat k^{\top}``, ``-|k|^2`` are
real symmetric.)

The **symmetric gradient** ``\operatorname{sym}\nabla`` (`symmetric_gradient`) is the **fused symmetric peer**
of ``\nabla\times`` (which takes the antisymmetric part of ``\nabla u``): its multiplier is the symmetric
part of ``\nabla u``'s multiplier ``\mathrm{i}k_j\hat u_i``,

```math
\hat S_{ij} = \tfrac{\mathrm{i}}{2} (k_j\hat u_i + k_i\hat u_j), \qquad S = \operatorname{sym}(\nabla u), \quad\checkmark
```

formed without materializing the full gradient tensor and sharing the derivative-wavenumber Nyquist zeroing.

**Backs** [Architecture](architecture.md) §4, decision 27.
**Checked by** `test/differentialoperators.jl` (analytic round-trips, the Nyquist split,
``\nabla\cdot(\nabla\times)=0``, ``\nabla\times\nabla=0``, and ``\operatorname{sym}\nabla u=\operatorname{sym}(\nabla u)``)
and `test/adjointness.jl` (self-adjointness, idempotent projection, negative-semidefinite Laplacian).

## Convolution (`Convolution`, [Architecture](architecture.md) §11)

By the convolution theorem, periodic convolution is the coefficientwise spectral product; `convolve`
applies a scalar kernel ``\hat g`` (a `ScalarFieldSpectral`, broadcast over the fiber) with α/β accumulate
(`src/Convolution.jl`):

```math
\mathcal F(f \star g) = \hat f\cdot\hat g, \qquad
\widehat{\mathrm{dst}} = \alpha \hat f \hat g + \beta \widehat{\mathrm{dst}}. \quad\checkmark
```

This is exactly the product invariant 1 bans as ``*`` — it is convolution, not the (absent) pointwise
spectral product. The neutral kernel builders: `spectral_cutoff` is the sharp low-pass ``\hat g(k)=1`` for
``|k|\le k_c`` (else ``0``), **idempotent** (``\hat g^2=\hat g``, a projection); `spectral_band` its annular
``k_{\mathrm{lo}}\le|k|\le k_{\mathrm{hi}}`` generalization (cutoff is ``k_{\mathrm{lo}}=0``); `squared_wavenumber_field` the ``|k|^2``
coordinate consumers build symbols from; and `assignment_window` the linear/CIC mass-assignment window

```math
\hat W(k) = \prod_{a=1}^{3}\operatorname{sinc}^2\Bigl(\tfrac{k_a \Delta x_a}{2}\Bigr),
\qquad \operatorname{sinc} y = \tfrac{\sin y}{y},
```

undone by dividing (deconvolution).

The fifth builder, `translation_kernel`, is the shift theorem's multiplier: for a physical displacement
``h = (h_1, h_2, h_3)`` it is the transform of the Dirac delta displaced to ``h``,
so convolving carries the field ``f`` at position ``x`` to ``f(x - h)``. Write ``\kappa_a`` for the
true signed wavenumber of axis ``a``, ``\tilde\kappa_a`` for the derivative wavenumber (equal to
``\kappa_a`` except at the Nyquist frequency of an even-length axis, where it is zeroed — invariant 5),
``N_a`` for the number of points on that axis and ``\Delta x_a`` for its grid spacing. The implemented
multiplier is the separable product

```math
\hat g_h(k) = \prod_{a=1}^{3}
  \bigl[  \cos(\kappa_a h_a) - \mathrm{i} \sin(\tilde\kappa_a h_a)  \bigr].
```

Three statements, each expanded against the code and tested:

- **A pure phase away from Nyquist.** Where no component of ``k`` sits at a Nyquist frequency we have
  ``\tilde\kappa_a = \kappa_a``, and ``\cos`` is even, so each factor collapses to
  ``\cos(\kappa_a h_a) - \mathrm{i} \sin(\kappa_a h_a) = e^{-\mathrm{i} \kappa_a h_a}``, whence
  ``\hat g_h(k) = e^{-\mathrm{i} k \cdot h}``, of unit modulus. ``\checkmark``
- **Reality: the kernel is Hermitian.** ``\hat g_h(-k) = \overline{\hat g_h(k)}`` on the discrete
  frequency torus, so `convolve` carries a real field to a real field. Each non-Nyquist factor conjugates
  under ``\kappa_a \mapsto -\kappa_a``; each Nyquist factor is the *real* number
  ``\cos(\pi h_a / \Delta x_a)``, hence its own conjugate — which is what the statement needs, the
  Nyquist frequency being its own negative modulo ``N_a``. The two candidate kernels fail here or below: the
  true phase ``e^{-\mathrm{i} k\cdot h}`` is *not* Hermitian at Nyquist for a fractional displacement, and
  the all-derivative-wavenumber kernel is Hermitian but carries the wrong value. ``\checkmark``
- **Whole-cell displacements are exact.** For ``h_a = m_a \Delta x_a`` with ``m \in \mathbb Z^3`` every
  factor is the exact phase — the Nyquist one reducing to ``\cos(\pi m_a) = (-1)^{m_a}`` — and the
  convolution is exactly the index shift, `circshift` by ``m`` cells. ``\checkmark``

**Backs** [Architecture](architecture.md) §11, decisions 20–22, 28.
**Checked by** `test/convolution.jl` — the translation kernel ``e^{-\mathrm{i} k_a m \Delta x_a} \Leftrightarrow``
`circshift` (a shift of ``m`` cells; an independent physical oracle), cutoff idempotence, and
the physical-space intentional absence (the ``\operatorname{sinc}^2`` window is checked by `test/rdf.jl`); and for `translation_kernel`, `circshift` on a *random* field (one
with Nyquist content, so the Nyquist factor is exercised), the exact `DirectDFT` evaluation at the displaced
nodes for a sub-cell displacement, and the reality check that the displaced half-spectrum survives a
transform round trip (the inverse transform being the Hermitian projector).

## Reductions (`Reductions`, [Architecture](architecture.md) §12)

The L²/measure structure (`src/Reductions.jl`). The `integral` is **extensive** (against the base measure —
grid cell volume, point counting); `inner` is the **normalized** L² product (declared above); `l2norm`
``=\sqrt{\langle f,f\rangle}``:

```math
\int_\Omega f\,\mathrm{d}\mu = \frac{|\Omega|}{N}\sum_n f_n\ (\text{grid}),\quad \sum_p f_p\ (\text{points});
\qquad \int_\Omega f\,\mathrm{d}\mu = \mathrm{measure}\cdot\mathrm{mean}. \quad\checkmark
```

**`integral` and `mean` in spectral representation** (the zero mode, no transform): the unnormalized
forward gives the DC coefficient ``\hat f(0) = \sum_x f_x`` (real for a real field), so

```math
\mathrm{mean}(f) = \frac{\hat f(0)}{N}, \qquad \int_\Omega f\,\mathrm{d}\mu = \frac{|\Omega|}{N} \hat f(0). \quad\checkmark
```

Both equal the physical reductions (since ``\sum_x f_x = \hat f(0)``), read from the same zero-mode slot
the constant-add writes; `std`/`var`/`lpnorm`/`maximum` have no single-coefficient form.

**`inner` in spectral representation** (Parseval, no transform): the discrete Parseval identity
``\tfrac{1}{N}\sum_x f_x\cdot g_x = \tfrac{1}{N^2}\sum_{\text{all }k}\hat f(k) \overline{\hat g(k)}`` together with
the rfft half-spectrum (each ``k_x>0`` mode stands for its conjugate partner, so it counts twice; the
self-conjugate ``k_x=0`` and even-Nyquist planes count once) gives

```math
\langle f, g\rangle = \frac{1}{N^2} \mathrm{Re}\Bigl(2\sum_{k_x\ge0}\hat f \overline{\hat g}
-\sum_{k_x=0}\hat f \overline{\hat g}-\sum_{k_x=N_x/2}\hat f \overline{\hat g}\Bigr) \quad\checkmark
```

(the Nyquist sum only for even ``N_x``). **`radial_spectrum`** bins this with the half-spectrum weight
``\alpha(k)`` (``1`` on the self-conjugate planes, ``2`` else) over ``|k|``-shells, and
**`radial_correlation`** is the Wiener–Khinchin dual (``\mathcal F^{-1}=`` `to_physical`, the normalized
inverse):

```math
P(\kappa_i) = \frac{1}{N^2}\sum_{\mathrm{round}(|k|/\Delta k)=i}\alpha(k)\sum_c |\hat f_c(k)|^2,
\qquad
C(r) = \frac{1}{N} \mathcal F^{-1}\Bigl(\textstyle\sum_c|\hat f_c|^2\Bigr)(r),
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
(``w^2=w``, a sharp band), not for a general ``w``. Symmetric in ``f,g``, may be negative, spectral-only.

**Backs** [Architecture](architecture.md) §12, decisions 18/21/22/27.
**Checked by** `test/reductions.jl` — ``\langle\sin\rangle=0``, ``\langle\sin^2\rangle=\tfrac{1}{2}``,
the spectral `integral`/`mean` against the physical reductions (``\langle c\rangle=c``, ``\int c\,\mathrm{d}x=c|\Omega|``),
``\sum E=\mathrm{inner}``, ``C(0)=\mathrm{inner}`` against an independent binned-circshift oracle, the
co-spectrum signs, and `weighted_inner` against ``\langle f,-\Delta g\rangle`` and the idempotent-band identity.

## Interpolation / anterpolation (`Interpolation`, [Architecture](architecture.md) §10)

The base gather ``W_b : \mathbb R^N \to \mathbb R^M`` has entries ``(W_b)_{pn} = w_n(x_p)`` (the local
stencil weights, `src/Interpolation.jl`), a **partition of unity** — for each point the row sums to one,
``\sum_n (W_b)_{pn} = 1``, i.e. ``W_b \mathbf 1_N = \mathbf 1_M`` with ``\mathbf 1_N \in \mathbb R^N`` and
``\mathbf 1_M \in \mathbb R^M`` (two **distinct** all-ones vectors). Both transfer maps are
**fiber-preserving** (the trivial bundle leaves the fiber by the identity):

```math
W := W_b \otimes \mathrm{id}_V : \Gamma_G \to \Gamma_P,
\qquad
W^{\top} := W_b^{\top} \otimes \mathrm{id}_V : \Gamma_P \to \Gamma_G .
```

**Adjoint, raw (counting) form.** For ``f \in \Gamma_G``, ``q \in \Gamma_P``:

```math
\sum_p (Wf)_p\cdot q_p
= \sum_p \sum_n (W_b)_{pn} (f_n\cdot q_p)
= \sum_n f_n\cdot (W^{\top} q)_n \qquad\checkmark
```

**Adjoint, normalized inner.** Dividing the two sides by ``M`` and ``N``:

```math
M \langle Wf, q\rangle_{\text{pts}}
= \sum_p (Wf)_p\cdot q_p
= \sum_n f_n\cdot(W^{\top}q)_n
= N \langle f, W^{\top} q\rangle_{\text{grid}} \qquad\checkmark
```

So the *bare* ``\langle Wf, q\rangle_{\text{pts}} = \langle f, W^{\top}q\rangle_{\text{grid}}`` is **false**
unless ``N = M`` — the two sides differ by ``N/M``. This is the slip the formalization catches: it
type-checks, but the expansion does not match. The clean adjunction uses the measure-adjoint
``\iota_* := (N/M) W^{\top}``:

```math
\langle f, \iota_* q\rangle_{\text{grid}}
= \frac{1}{N}\sum_n f_n\cdot\tfrac{N}{M} (W^{\top}q)_n
= \frac{1}{M}\sum_n f_n\cdot(W^{\top}q)_n
= \langle Wf, q\rangle_{\text{pts}} \qquad\checkmark
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
``M \mathrm{inner}(Wf, q) = N \mathrm{inner}(f, W^{\top}q)``, conservation (partition of unity), and
polynomial reproduction.

## Spectral transfer: `DirectDFT` / `NUFFT` (`Interpolation`, [Architecture](architecture.md) §10, decision 23)

The exact Fourier transfer between a field's spectral coefficients and off-grid points, and its fast
windowed form — the spectral siblings of the spline ``W`` / ``W^{\top}`` above. `DirectDFT` is the literal
``O(NM)`` sum (`src/Interpolation.jl`; ``o`` the grid origin, ``\alpha`` the half-spectrum Parseval weight,
``1`` on the self-conjugate planes and ``2`` else):

```math
\text{type-2 (interpolate)}\quad f(x_p) = \frac{1}{N}\sum_{\text{stored }k}\alpha(k) \mathrm{Re}\bigl(\hat f(k) e^{\mathrm{i} k\cdot(x_p-o)}\bigr),
\qquad
\text{type-1 (anterpolate)}\quad (W^{\top}q)(k) = \sum_p q_p e^{-\mathrm{i} k\cdot(x_p-o)} .
```

Type-2 reproduces the band-limited field exactly (it matches `to_physical` at the grid nodes), and the
pair satisfies the same measure-weighted adjoint as the splines,
``M \langle W\hat f, q\rangle_{\text{pts}} = N \langle \hat f, W^{\top}q\rangle_{\text{grid}}``. ``\checkmark``
**`NUFFT`** is its ``O(N\log N + M)`` form — spread → oversampled (``\sigma=2``) FFT → deconvolve by
``1/\hat\psi`` (window ``\psi``, transform ``\hat\psi``) — exact to a tolerance ``\varepsilon`` against
`DirectDFT` on the resolved sub-Nyquist band (the rfft Nyquist is projected out), an exact adjoint pair there.

**Backs** [Architecture](architecture.md) §10, decision 23.
**Checked by** `test/transfer_spectral.jl` — `interpolate` == `to_physical` at the nodes, exact off-grid
reconstruction, the adjoint relation (``R = 0, 1, 2``), and `NUFFT` vs `DirectDFT` to ``\varepsilon``.
