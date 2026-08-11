# GBGPeriodicFields.jl

```@autodocs
Modules = [GBGPeriodicFields]
Order   = [:module]
```

## Re-exported modules

The top-level module includes and re-exports the public interface of:

- [`GBGPeriodicFields.FiberSections`](@ref)
- [`GBGPeriodicFields.Fields`](@ref)
- [`GBGPeriodicFields.FieldAlgebra`](@ref)
- [`GBGPeriodicFields.DifferentialOperators`](@ref)
- [`GBGPeriodicFields.Convolution`](@ref)
- [`GBGPeriodicFields.Points`](@ref)
- [`GBGPeriodicFields.Interpolation`](@ref)
- [`GBGPeriodicFields.Reductions`](@ref) — with one exception: `mean`, `std`, `var` and `cov` extend
  `Statistics` generics and are **not** re-exported, so they need `using Statistics` as well. Every
  other reduction, `maximum`/`minimum`/`extrema` included, is reachable from `using
  GBGPeriodicFields` alone.
