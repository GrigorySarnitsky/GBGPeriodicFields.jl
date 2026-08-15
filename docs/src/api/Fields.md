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
FieldSpectralMultipliers(::AbstractFieldSpectral)
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
physical_field_shape
spectral_field_shape
```

## Field allocation

```@docs
similar_field
```

## Moving between storage families

Host and device are **storage families**, not representations: the same mathematical object, held in
different memory. Every operation refuses a pair that disagrees, rather than transferring one to meet
the other, so that the cost of crossing the bus is always visible at the call site — `adapt` is that
call site. It is `Adapt.jl`'s verb, extended here for every section, kernel and plan and re-exported,
so a consumer needs nothing beyond `using GBGPeriodicFields`; and because it dispatches on a generic
target, `CUDA` and `AMDGPU` each supply their own storage rule without this package depending on
either. Element type is never changed by a move.

```@docs
adapt
```

## Spectral kernel protocol

`SpectralKernel` is the exported supertype the kernel-taking operations dispatch on — `convolve` and the
kernel-composed differential operators on the whole hierarchy, `weighted_inner` on every class
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
# `adapt` is rendered by the "Moving between storage families" section above. It reaches this block
# because it is an EXTERNAL generic the module extends rather than one it owns, so `Public = false`
# does not filter it out — the same class as the statistics on the Reductions page, and the same fix.
Filter  = f -> nameof(f) !== :adapt
```
