# Convolution

```@autodocs
Modules = [GBGPeriodicFields.Convolution]
Order   = [:module]
```

## Convolution operations

The verbs below are this module's own. Two further operations reach a kernel through a generic
another module owns, and are documented there: [`combine!`](@ref) has a kernel-composed method — a
weighted combination convolved with a kernel in one fused pass — on the
[`FieldAlgebra`](FieldAlgebra.md) page, and [`adapt`](@ref) moves a kernel of any class between
[storage families](@ref GBGPeriodicFields.GBGPeriodicFields) as it moves a field, on the [`Fields`](Fields.md) page.

```@docs
convolve!
convolve
⋆
exponential_convolve!
exponential_convolve
```

## Kernel storage classes

The package holds a kernel in whichever of four forms is cheapest for its multiplier: wrapped in a
`StoredKernel` when the multiplier is arbitrary, as per-axis factors when it separates, as the
**function** computing it when it depends on the wavenumber only through ``\lvert k\rvert^2``, or as
**any two kernels** held unmultiplied when a composition cannot be collapsed into one. All four apply
identically and agree bitwise on the host; on a device a **complex**-valued kernel is the one
exception, agreeing there to rounding.

They part company in one place. Inversion is a mathematical partial operation — a kernel that
annihilates a mode has no inverse there — and a class that cannot afford to test that precondition
reports a violation differently from one that can, so [`inv`](@ref) is where the choice of class
shows. It matters most for a sharp cutoff, since
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
`tophat_window`, `assignment_window` and `translation_kernel` give a `SeparableKernel` (three ``O(N)``
factors).
The escape hatch is `radial_kernel`, taking any other real **function** of ``\lvert k\rvert^2``.

```@docs
radial_kernel
spectral_cutoff
spectral_band
tophat_window
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
