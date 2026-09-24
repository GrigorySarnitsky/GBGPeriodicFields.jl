# Reductions

```@autodocs
Modules = [GBGPeriodicFields.Reductions]
Order   = [:module]
```

## Integral reductions

Five of the reductions on this page also take a leading fiber map — the **mapped** form, as in
`mean(det, A)` or `maximum(norm, u)`, which reduces a nonlinear invariant without building it as a
section. It is documented on [`integral`](@ref), which names the five. `Statistics` gives `var` and
`std` no such spelling, so neither does this package.

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

These extend the standard-library generics — `mean`, `std`, `var`, and `cov` from `Statistics`, and `maximum`, `minimum`, and `extrema` from `Base` — rather than introducing package names, and are used exactly as their stdlib counterparts are.

All seven are in scope from `using GBGPeriodicFields` alone: the `Statistics` four are re-exported by the top-level module, as `dot` and `norm` are from `LinearAlgebra`, and the `Base` three are in scope already. That split is why two blocks follow rather than one.

```@autodocs
Modules = [GBGPeriodicFields.Reductions]
Public  = true
Order   = [:function]
Filter  = f -> nameof(f) in (:mean, :std, :var, :cov)
```

```@autodocs
Modules = [GBGPeriodicFields.Reductions]
Public  = false
Order   = [:function]
Filter  = f -> nameof(f) in (:maximum, :minimum, :extrema)
```

## Radial reductions

```@docs
radial_spectrum
radial_correlation
```

## Internal API

These symbols are not part of the public interface; they are documented for contributors — the
fiberwise reduction machinery (the fiber map-reduce and its loop and tree forms) and the fixed
reduction tree that makes a threaded reduction bitwise thread-count-invariant, together with the
backend split that decides which of the two a reduction takes.

```@autodocs
Modules = [GBGPeriodicFields.Reductions]
Public  = false
Order   = [:function]
Filter  = f -> !(nameof(f) in (:mean, :std, :var, :cov, :maximum, :minimum, :extrema))
```
