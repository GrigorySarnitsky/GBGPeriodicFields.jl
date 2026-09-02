# Fields

```@autodocs
Modules = [GBGPeriodicFields.Fields]
Order   = [:module]
```

## Base and layout types

```@docs
Grid3D
RealFourierLayout
```

## Field types

```@docs
GBGPeriodicFields.Fields.AbstractField
AbstractFieldPhysical
AbstractFieldSpectral
ScalarFieldPhysical
ScalarFieldSpectral
VectorFieldPhysical
VectorFieldSpectral
TensorFieldPhysical
TensorFieldSpectral
```

## Transform-plan and multiplier types

```@docs
FieldTransformPlans
FieldSpectralMultipliers
```

## Transform operations

```@docs
to_physical!
to_physical
to_spectral!
to_spectral
```

## Field accessor functions

```@docs
field_data
field_grid
field_layout
field_scalar_type
field_tensor_order
field_physical_shape
field_spectral_shape
```

## Field allocation

```@docs
similar_field
```

## Moving between storage families

Host and device are **storage families**, not representations: the same mathematical object, held in
different memory. Every operation refuses a pair that disagrees, rather than transferring one to meet
the other, so that the cost of crossing the bus is always visible at the call site — `adapt` is that
call site. It is [`Adapt.jl`](https://github.com/JuliaGPU/Adapt.jl)'s verb, extended here for every section, kernel and plan and re-exported,
so a consumer needs nothing beyond `using GBGPeriodicFields`; and because it dispatches on a generic
target, `CUDA` and `AMDGPU` each supply their own storage rule without this package depending on
either. Element type is never changed by a move.

When the destination already exists, [`adapt!`](@ref) moves into it instead of allocating a fresh
result — which is most of what the return trip costs, so it is worth reaching for whenever a field
comes back from a device on any regular basis. It takes no target argument, because the destination
already is the family. It is offered for sections alone: multipliers, kernels and plans are built
rather than filled, so there is no storage for a destination to provide.

```@docs
adapt
adapt!
```

## The real-field reality condition

The real-to-complex layout stores half the spectrum because the other half is the conjugate mirror of
it. That redundancy is *implied* rather than stored, so it cannot disagree — except on the folded
axis's self-conjugate planes, where both partners are kept and a hand-written coefficient can break
the symmetry. [`reality_residual`](@ref) measures how far a field is from being the spectrum of a real
field, which is worth asking wherever responsibility for the coefficients changes hands.

```@docs
reality_residual
```

## Spectral kernel protocol

`SpectralKernel` is the exported supertype the kernel-taking operations dispatch on — `convolve` and the
kernel-composed differential operators on all four storage classes, `weighted_inner` on every class
too, subject to the separate requirement that its weight be **real**. It is defined here
rather than in [`Convolution`](@ref "Convolution") because `DifferentialOperators` also takes kernels
and is included first, so the protocol has to precede both consumers. The concrete classes that subtype
it, and the builders returning them, are documented with `Convolution`.

```@docs
SpectralKernel
```

## FFT thread configuration

```@docs
set_fft_threads!
```

## HDF5 persistence

Serialize a field to, and reconstruct it from, an HDF5 file — for checkpoint/restart, or to dump a
full-resolution snapshot for later analysis. Provided by a **package extension**, so these are available
only when the `HDF5` package is loaded; the core carries no HDF5 dependency. Each field becomes one
self-describing HDF5 group, and the consumer owns the file — every method takes an open `File` or `Group`,
so a whole iteration snapshot (several fields, plus the consumer's own time and iteration attributes) goes
into one file.

```@docs
write_field
read_field
```

## Internal API

These symbols are not part of the public interface; they are documented for contributors — field-allocation and compatibility helpers, the spectral-multiplier broadcast helpers, the broadcast machinery, and the storage-family helpers `adapt` rebuilds through.

### Types

```@autodocs
Modules = [GBGPeriodicFields.Fields]
Public  = false
Order   = [:type, :constant]
# `SpectralKernel` is rendered by the "Spectral kernel protocol" section above, so it is excluded here
# to keep it from appearing twice on one page. It is public and exported by the umbrella (decision 65);
# it still reaches this block because Documenter reads `Fields`' own export list, not the umbrella's —
# the same `Public = false` mechanism that filed `map` and `transpose` as internals.
Filter  = t -> !(t in (GBGPeriodicFields.Fields.AbstractField,
                       GBGPeriodicFields.Fields.SpectralKernel))
```

### Functions

```@autodocs
Modules = [GBGPeriodicFields.Fields]
Public  = false
Order   = [:function]
# `adapt` and `adapt!` are rendered by the "Moving between storage families" section above. They reach
# this block for two different reasons and need the same exclusion: `adapt` is an EXTERNAL generic the
# module extends rather than one it owns, and `adapt!` is owned here but exported by the umbrella
# rather than by `Fields`, which is the list Documenter reads. Either way `Public = false` does not
# filter them — the same class as the statistics on the Reductions page, and the same fix.
# `reality_residual` joins them for the SAME reason as `adapt!`: it is owned here and exported by the
# umbrella, not by `Fields`, so `Public = false` swept it in and it rendered TWICE on this page — once
# under "The reality constraint" above and once here. Found by the built-HTML pass, which is the only
# surface that can see it: the duplicate is invisible in this file, where each block looks correct
# alone. Whenever a Fields-owned binding is added to the umbrella's export list, it must be added here.
Filter  = f -> !(nameof(f) in (:adapt, :adapt!, :reality_residual))
```
