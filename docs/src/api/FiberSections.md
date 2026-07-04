# FiberSections

```@autodocs
Modules = [GBGPeriodicFields.FiberSections]
Order   = [:module]
```

## Fiber-section supertype

```@docs
AbstractFiberSection
```

## Threading configuration

```@docs
threading_cutoff
set_threading_cutoff!
with_threading
```

## Internal API

The CPU-threading primitives and the fiberwise-algebra code generators — not part of the public
interface, documented for contributors extending the package's algebra.

```@autodocs
Modules = [GBGPeriodicFields.FiberSections]
Public  = false
Order   = [:type, :constant, :function, :macro]
```
