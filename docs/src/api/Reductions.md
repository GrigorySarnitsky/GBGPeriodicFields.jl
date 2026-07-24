# Reductions

```@autodocs
Modules = [GBGPeriodicFields.Reductions]
Order   = [:module]
```

## Integral reductions

```@docs
integral
```

## Inner-product and norm reductions

```@docs
inner
weighted_inner
l2norm
lpnorm
```

## Moments and order statistics

These extend the standard-library generics — `mean`, `std`, and `var` from `Statistics`, and `maximum`, `minimum`, and `extrema` from `Base` — rather than introducing package names, so they are reached through `using Statistics` and `Base` and are used exactly as their stdlib counterparts are. Extending rather than renaming is why they are not package exports; they are part of the public interface all the same.

```@autodocs
Modules = [GBGPeriodicFields.Reductions]
Public  = false
Order   = [:function]
Filter  = f -> nameof(f) in (:mean, :std, :var, :maximum, :minimum, :extrema)
```

## Radial reductions

```@docs
radial_spectrum
radial_correlation
```

Each reduction also has a **mapped** form taking a leading function, applied to the fiber value at every base point — `mean(det, A)`, `maximum(norm, u)` — which reduces a nonlinear invariant in one pass without building it as a section. That form is documented on [`integral`](@ref), including when to prefer it on a CPU; `mean`, `maximum`, `minimum`, and `extrema` take the same leading function. `Statistics` gives `var` and `std` no such spelling, so neither does this package.

## Internal API

These symbols are not part of the public interface; they are documented for contributors — the base
measure (count and cell measure), the fiber-preserving reduction helper, and the fixed reduction tree
that makes a threaded reduction bitwise thread-count-invariant.

```@autodocs
Modules = [GBGPeriodicFields.Reductions]
Public  = false
Order   = [:function]
Filter  = f -> !(nameof(f) in (:mean, :std, :var, :maximum, :minimum, :extrema))
```
