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

## Kernel storage classes

A kernel is anything an operation can apply as the coefficientwise product ``\hat f\,\hat g``, and the
package holds one in whichever of four forms is cheapest for its multiplier: a `ScalarFieldSpectral` of
coefficients wrapped in a `StoredKernel` when the multiplier is arbitrary, the per-axis factors when it
separates, the **function** computing it when it depends on the wavenumber only through
``\lvert k\rvert^2``, or a pair of the last two held unmultiplied when a composition crosses those two
families. All four are applied identically and give bitwise-identical results, so the choice is one of
storage, not of meaning.

Every operation taking a kernel dispatches on
[`SpectralKernel`](@ref GBGPeriodicFields.Fields.SpectralKernel), the supertype of the four classes
below. It is documented with [`Fields`](@ref "Fields"), where the protocol is defined so the
differential operators and the reductions can name it too.

A field in spectral representation is **not** a kernel. A `StoredKernel` and a `ScalarFieldSpectral`
hold identical data, so only a type can say which role is meant, and the distinction is load-bearing:
the coefficientwise reciprocal of a kernel is the kernel that deconvolves by it (`inv`), while the same
operation on a field is one the package does not define. Wrap the field in a `StoredKernel` to declare
the role.

```@docs
StoredKernel
SeparableKernel
RadialKernel
ProductKernel
inv
materialize_kernel
```

## Kernel builders

Each returns a kernel for a multiplier the package names, in whichever storage class that multiplier
admits — and each signature says which class, since that is what determines the cost of applying it:
`radial_kernel`, `spectral_cutoff` and `spectral_band` give a `RadialKernel` (a closure);
`translation_kernel` and `assignment_window` give a `SeparableKernel` (three ``O(N)`` factors).
`radial_kernel` is the escape hatch: it builds one from any other real **function** of
``\lvert k\rvert^2``, which is the route for a filter, a hyperviscosity, or an integrating factor the
package does not name.

```@docs
radial_kernel
spectral_cutoff
spectral_band
assignment_window
translation_kernel
translation_kernel!
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
