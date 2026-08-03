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

Every operation taking a kernel accepts the union
[`SpectralKernel`](@ref GBGPeriodicFields.Fields.SpectralKernel), whose members are a
`ScalarFieldSpectral` holding one coefficient per mode and the compressed classes below, which subtype
[`AbstractSpectralKernel`](@ref GBGPeriodicFields.Fields.AbstractSpectralKernel). Both are documented
with [`Fields`](@ref "Fields"), where the protocol is defined so the differential operators and the
reductions can name it too.

```@docs
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
