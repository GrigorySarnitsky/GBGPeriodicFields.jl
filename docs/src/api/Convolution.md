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
same fused pass — is documented with its generic on the [`FieldAlgebra`](FieldAlgebra.md) page.

Every kernel class moves between storage families with its field: `adapt` is extended for all four,
and is documented with its generic on the [`Fields`](Fields.md) page.

## Kernel storage classes

The package holds a kernel in whichever of four forms is cheapest for its multiplier: wrapped in a
`StoredKernel` when the multiplier is arbitrary, as per-axis factors when it separates, as the
**function** computing it when it depends on the wavenumber only through ``\lvert k\rvert^2``, or as
**any two kernels** held unmultiplied when a composition cannot be collapsed into one. All four apply
identically and agree bitwise on the host; on a device a **complex**-valued kernel is the one
exception, agreeing there to rounding.

They part company in one place. [`inv`](@ref) is a mathematical partial operation — a kernel that
annihilates a mode has no inverse there — and a class that cannot afford to test that precondition
reports a violation differently from one that can. It matters most for a sharp cutoff, since
[`spectral_cutoff`](@ref) returns the class that cannot.

The supertype every kernel-taking operation dispatches on is [`SpectralKernel`](@ref), documented with
[`Fields`](@ref "Fields").

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
The escape hatch is `radial_kernel`, taking any other real **function** of ``\lvert k\rvert^2``.

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
coefficientwise convolution, combination and exponential-kernel bodies, the axis-factored pair that
evaluates a separable kernel per mode, and the exponential kernel pair — a device kernel and its
gated CPU twin — "gated" meaning a loop that consults the threading setting before splitting — that evaluates the mode factor once per mode rather than once per component.

```@autodocs
Modules = [GBGPeriodicFields.Convolution]
Public  = false
Order   = [:function]
# `inv` is a Base extension this module owns — public, but not re-exported, so `Public = false`
# collects it. It is already documented under the kernel-storage heading, and its three
# method-specific docstrings were appearing here as well. Same class as FieldAlgebra's operators.
Filter  = f -> nameof(f) !== :inv
```
