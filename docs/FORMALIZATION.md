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
\Gamma_G &:= \mathbb R^N \otimes V        &&\text{grid sections, } N \text{ cells}\\
\Gamma_P &:= \mathbb R^M \otimes V        &&\text{point sections, } M \text{ points}
\end{aligned}
```

Here ``\mathbb R^N`` is the scalar field over the ``N`` cells — one real coordinate per cell, the
discretized base — and ``\otimes V`` attaches the fiber, so a grid section carries a ``V``-value *at each
cell* (``\mathbb R^N \otimes V \cong V^N``; a cell holds a single real only in the scalar case ``R = 0``,
where ``V = \mathbb R``). Likewise ``\Gamma_P`` is a ``V``-value at each of the ``M`` points.

With the fiber contraction ``\cdot : V \times V \to \mathbb R``, the inner products are the package's
**normalized** reductions (`inner`, `src/Reductions.jl` = `dot(data, data) / _base_count`):

```math
\langle a, b\rangle_{\text{pts}} := \frac1M \sum_{p=1}^{M} a_p\cdot b_p,
\qquad
\langle f, g\rangle_{\text{grid}} := \frac1N \sum_{n=1}^{N} f_n\cdot g_n .
```

## Interpolation / anterpolation (`Interpolation`, [Architecture](architecture.md) §10)

The base gather ``W_b : \mathbb R^N \to \mathbb R^M`` has entries ``(W_b)_{pn} = w_n(x_p)`` (the local
stencil weights, `src/Interpolation.jl`), a **partition of unity** — for each point the row sums to one,
``\sum_n (W_b)_{pn} = 1``, i.e. ``W_b\,\mathbf 1_N = \mathbf 1_M`` with ``\mathbf 1_N \in \mathbb R^N`` and
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
= \sum_p \sum_n (W_b)_{pn}\,(f_n\cdot q_p)
= \sum_n f_n\cdot (W^{\top} q)_n \qquad\checkmark
```

**Adjoint, normalized inner.** Dividing the two sides by ``M`` and ``N``:

```math
M\,\langle Wf, q\rangle_{\text{pts}}
= \sum_p (Wf)_p\cdot q_p
= \sum_n f_n\cdot(W^{\top}q)_n
= N\,\langle f, W^{\top} q\rangle_{\text{grid}} \qquad\checkmark
```

So the *bare* ``\langle Wf, q\rangle_{\text{pts}} = \langle f, W^{\top}q\rangle_{\text{grid}}`` is **false**
unless ``N = M`` — the two sides differ by ``N/M``. This is the slip the formalization catches: it
type-checks, but the expansion does not match. The clean adjunction uses the measure-adjoint
``\iota_* := (N/M)\,W^{\top}``:

```math
\langle f, \iota_* q\rangle_{\text{grid}}
= \frac1N\sum_n f_n\cdot\tfrac NM\,(W^{\top}q)_n
= \frac1M\sum_n f_n\cdot(W^{\top}q)_n
= \langle Wf, q\rangle_{\text{pts}} \qquad\checkmark
```

**Conservation** (sum the deposit over the grid, per fiber component):

```math
\sum_n (W^{\top} q)_n
= \sum_n\sum_p (W_b)_{pn}\,q_p
= \sum_p \Bigl(\textstyle\sum_n (W_b)_{pn}\Bigr) q_p
= \sum_p q_p \;\in V \qquad\checkmark
```

(uses the partition-of-unity row sum ``\sum_n (W_b)_{pn} = 1``).

**Backs** [Architecture](architecture.md) §10 and the `Interpolation` module docstring.
**Checked by** `test/interpolation_transfer.jl` — the measure-weighted adjointness
``M\,\mathrm{inner}(Wf, q) = N\,\mathrm{inner}(f, W^{\top}q)``, conservation (partition of unity), and
polynomial reproduction.

## To formalize (same format)

Each is a nontrivial statement whose prose should be backed here and linked to its test:

- `inner` in spectral representation via Parseval — the ``1/N^2`` rfft half-spectrum weighting; `Reductions`, `test/reductions.jl`.
- `radial_spectrum` / `radial_correlation` — the refinements ``\sum_\kappa E = \langle f, f\rangle`` and ``C(0) = \langle f, f\rangle``; `Reductions`, `test/reductions.jl`.
- The differential-operator multipliers (``ik``, ``-|k|^2``) and the Nyquist split; `DifferentialOperators`, `test/differentialoperators.jl`.
- `convolve` ``= \hat f\cdot\hat g`` and `assignment_window` ``= \prod_a \operatorname{sinc}^2(k_a\,\Delta x_a/2)``; `Convolution`, `test/convolution.jl`.
