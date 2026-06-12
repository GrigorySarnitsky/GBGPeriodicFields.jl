# Convolution

```@autodocs
Modules = [GBGPeriodicFields.Convolution]
Order   = [:module]
```

The `Convolution` module is the **kernel-multiplier** operation family — periodic (circular)
convolution of a field with a kernel, in spectral representation. On the torus, by the convolution
theorem, ``f \star g`` is the coefficientwise spectral product ``\hat f \cdot \hat g``; the kernel `g` is supplied by its
transfer function ``\hat g`` as a [`ScalarFieldSpectral`](Fields.md), which multiplies every fiber component
(one method serves scalar, vector, and tensor fields). It is the spectral sibling of the
[`DifferentialOperators`](DifferentialOperators.md) and the same-base counterpart of the
[`Interpolation`](Interpolation.md) transfer — both are the "kernel measure" of the measure taxonomy.
See `docs/ARCHITECTURE.md` §2 and decision 20.

`convolve`/`convolve!` apply the kernel (with allocating, in-place, and α/β-accumulate forms); because
a kernel is itself a scalar field in spectral representation, `convolve(g₁, g₂)` composes two kernels.
This is the coefficientwise spectral product invariant 1 names but bans **as `*`** — offered here under
its true name `convolve`, never as `*`. Spectral representation only; physics (an LES filter, an
integrating factor) stays a consumer-built kernel.

Four neutral builders ship (decisions 20, 21, 22): `spectral_cutoff` is the isotropic sharp low-pass
(de-aliasing) kernel; `spectral_band(ref, mult, k_lo, k_hi)` is its annular generalization (a band-pass
shell selector; the cutoff is the `k_lo = 0` case); `squared_wavenumber_field(ref, mult)` is the
``|k|^2`` radial coordinate of spectral space as a `ScalarFieldSpectral` — the consumer builds a Fourier
symbol from it (a viscous integrating factor ``\exp(-\nu |k|^2 \Delta t)``, a smooth envelope, a Germano filter) and
applies it with `convolve`; and `assignment_window(ref, mult)` is the linear/CIC mass-assignment window
``\hat W = \prod_a \operatorname{sinc}^2(k_a \Delta x_a/2)`` for deconvolving a gridded point density (the
FFT point-RDF route, decision 22 — divide by ``\hat W`` to undo the assignment smearing).

## Contents

```@contents
Pages = ["Convolution.md"]
Depth = 2:3
```

## Index

```@index
Modules = [GBGPeriodicFields.Convolution]
```

## Public API

```@autodocs
Modules = [GBGPeriodicFields.Convolution]
Public  = true
Private = false
Order   = [:function]
```

## Internal API

These symbols are not part of the public interface; they are documented for contributors — the
coefficientwise convolution kernel.

```@autodocs
Modules = [GBGPeriodicFields.Convolution]
Public  = false
Order   = [:function]
```
