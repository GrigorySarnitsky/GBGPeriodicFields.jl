# Convolution

```@autodocs
Modules = [GBGPeriodicFields.Convolution]
Order   = [:module]
```

## Convolution operations

```@docs
convolve!
convolve
⋆
exponential_convolve!
exponential_convolve
```

The kernel-composed method of `combine!` — the weighted combination convolved with a kernel in the
same fused pass — is documented with its generic on the [FieldAlgebra](FieldAlgebra.md) page.

## Kernel-multiplier builders

```@docs
spectral_cutoff
spectral_band
squared_wavenumber_field
assignment_window
translation_kernel
translation_kernel!
```

## Kernel storage

A kernel that factors over the axes is held as its per-axis factors rather than as a field, and applied identically.

The protocol types come first: `SpectralKernel` is the union every kernel-taking operation accepts, and
`AbstractSpectralKernel` is the supertype of the compressed classes below it. Both are defined in
[`Fields`](@ref "Fields"), so that the differential operators and the reductions can name them too, and
both are documented here because this is where a reader meets them.

```@docs
GBGPeriodicFields.Fields.SpectralKernel
GBGPeriodicFields.Fields.AbstractSpectralKernel
StoredKernel
SeparableKernel
RadialKernel
ProductKernel
radial_kernel
inv
materialize_kernel
```

## Internal API

These symbols are not part of the public interface; they are documented for contributors — the
coefficientwise convolution, combination, and exponential-kernel bodies.

```@autodocs
Modules = [GBGPeriodicFields.Convolution]
Public  = false
Order   = [:function]
# `inv` is a Base extension this module owns — public, but not re-exported, so `Public = false`
# collects it. It is already documented under the kernel-storage heading, and its three
# method-specific docstrings were appearing here as well. Same class as FieldAlgebra's operators.
Filter  = f -> nameof(f) !== :inv
```
