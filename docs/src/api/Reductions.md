# Reductions

```@autodocs
Modules = [GBGPeriodicFields.Reductions]
Order   = [:module]
```

## Public API

### Integral reductions

```@docs
integral
```

### Inner-product and norm reductions

```@docs
inner
l2norm
lpnorm
```

### Radial reductions

```@docs
radial_spectrum
radial_correlation
```

The `mean`, `std`, and `var` moments (extending `Statistics`) and the `maximum`, `minimum`, and `extrema` order statistics (extending `Base`) are also defined for sections; they are method extensions of the standard-library generics rather than package exports, and are described in the module summary above.

## Internal API

These symbols are not part of the public interface; they are documented for contributors — the base
measure (count and cell measure) and the fiber-preserving reduction helper.

```@autodocs
Modules = [GBGPeriodicFields.Reductions]
Public  = false
Order   = [:function]
```
