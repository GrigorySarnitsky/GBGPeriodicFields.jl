# Reductions

```@autodocs
Modules = [GBGPeriodicFields.Reductions]
Order   = [:module]
```

The `Reductions` module is the **L² / measure structure** on sections — the third operation family
alongside the vertical (fiberwise) algebra of [`FieldAlgebra`](FieldAlgebra.md) and the horizontal
(differential) operators of [`DifferentialOperators`](DifferentialOperators.md). A reduction
integrates a section over its base against the measure the base carries (`Grid3D`'s uniform cell
volume; `PointSet`'s counting measure), and is defined on **physical fields and point-values**
(representation-free quantities). See `docs/ARCHITECTURE.md` §2 and decision 18.

`integral` is the extensive ``\int f \, d\mu``; `inner` (``\langle\cdot,\cdot\rangle``), `l2norm`
(``\lVert\cdot\rVert_2``), and `lpnorm` (``\lVert\cdot\rVert_p``) are the normalized L² inner product
and norms. The `mean`/`std`/`var` (from `Statistics`) and `maximum`/`minimum`/`extrema` (from `Base`)
are *extended* on sections here — reached through `using Statistics` / `Base`, not re-exported.
Physics stays in the consumer (kinetic energy ``\tfrac12\langle u, u\rangle``, enstrophy, dissipation, rms).

A field in **spectral representation** also admits `inner`/`l2norm` via Parseval (equal to the physical
inner, no transform), and `radial_spectrum(f, mult)` — the **radial (shell-binned) power spectrum**
``S(\kappa)``: `inner` decomposed into isotropic ``|k|``-shells, returning `(shells, spectrum)` with the
exact refinement ``\sum_\kappa S(\kappa) = \langle f, f\rangle`` (decision 21). The consumer's energy
spectrum is ``E(\kappa) = \tfrac12\,S(\kappa)``.

Its physical-space **Wiener–Khinchin dual** is `radial_correlation(f, plans)` (decision 22) — the
shell-averaged two-point autocorrelation ``C(r) = \mathcal F^{-1}(|\hat f|^2)/N``, binned over
minimum-image ``|r|`` shells, with ``C(0) = \langle |f|^2\rangle = \mathrm{inner}(f, f)``. The two
resolve the same `inner` over the conjugate radial coordinates (``|k|`` and ``|r|``).

Each has a two-field **co-spectrum** form (decision 22): `radial_spectrum(f, g)` bins the cross-power
``\sum_c \mathrm{Re}(\hat f_c \overline{\hat g_c})`` and `radial_correlation(f, g)` is the
cross-correlation ``C_{fg}(r) = \langle f(x)\cdot g(x+r)\rangle = \mathcal F^{-1}(\overline{\hat f}\,\hat g)/N``,
each refining the **mixed** ``\mathrm{inner}(f, g)`` (``\sum_\kappa E_{fg} = C_{fg}(0) = \mathrm{inner}(f, g)``).
Both are symmetric in ``f, g``, the one-field forms are the ``g = f`` case, and — unlike the power
spectrum — the co-spectrum may be **negative** in a shell (anticorrelated modes; e.g. a momentum/scalar
flux co-spectrum, where the sign is physical).

## Contents

```@contents
Pages = ["Reductions.md"]
Depth = 2:3
```

## Index

```@index
Modules = [GBGPeriodicFields.Reductions]
```

## Public API

```@autodocs
Modules = [GBGPeriodicFields.Reductions]
Public  = true
Private = false
Order   = [:function]
```

## Internal API

These symbols are not part of the public interface; they are documented for contributors — the base
measure (count and cell measure) and the fiber-preserving reduction helper.

```@autodocs
Modules = [GBGPeriodicFields.Reductions]
Public  = false
Order   = [:function]
```
