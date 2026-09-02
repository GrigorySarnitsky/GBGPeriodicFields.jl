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

Host and device are **storage families**, not representations: a field has both, and they vary
independently — the representation says whether its values are the field or its Fourier coefficients,
the family says which memory those values live in. Moving between families is
[`Adapt.jl`](https://github.com/JuliaGPU/Adapt.jl)'s verb, extended here for every section, kernel and
plan and re-exported, so a consumer needs nothing beyond `using GBGPeriodicFields`; and because it
dispatches on a generic target, `CUDA` and `AMDGPU` each supply their own storage rule without this
package depending on either.

```@docs
adapt
adapt!
```

## The real-field reality condition

```@docs
reality_residual
```

## Spectral kernel protocol

The kernel-taking operations dispatch on `SpectralKernel`, each accepting all four storage classes:
`convolve`, the kernel-composed differential operators, and `weighted_inner` — the last subject to the
separate requirement that its weight be **real**.

```@docs
SpectralKernel
```

## FFT thread configuration

```@docs
set_fft_threads!
```

## HDF5 persistence

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
