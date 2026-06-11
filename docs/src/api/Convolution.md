# Convolution

```@autodocs
Modules = [GBGPeriodicFields.Convolution]
Order   = [:module]
```

The `Convolution` module is the **kernel-multiplier** operation family — periodic (circular)
convolution of a field with a kernel, in spectral representation. On the torus, by the convolution
theorem, `f ⋆ g` is the coefficientwise spectral product `f̂ · ĝ`; the kernel `g` is supplied by its
transfer function `ĝ` as a [`ScalarFieldSpectral`](Fields.md), which multiplies every fiber component
(one method serves scalar, vector, and tensor fields). It is the spectral sibling of the
[`DifferentialOperators`](DifferentialOperators.md) and the same-base counterpart of the
[`Interpolation`](Interpolation.md) transfer — both are the "kernel measure" of the measure taxonomy.
See `docs/ARCHITECTURE.md` §2 and decision 20.

`convolve`/`convolve!` apply the kernel (with allocating, in-place, and α/β-accumulate forms); because
a kernel is itself a scalar field in spectral representation, `convolve(g₁, g₂)` composes two kernels.
`spectral_cutoff` builds the isotropic sharp low-pass (de-aliasing) kernel. This is the coefficientwise
spectral product invariant 1 names but bans **as `*`** — offered here under its true name `convolve`,
never as `*`. Spectral representation only; physics (an LES filter, an integrating factor) stays a
consumer-built kernel.

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
