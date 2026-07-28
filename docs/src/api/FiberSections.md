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

These symbols are not part of the public interface; they are documented for contributors. The CPU-threading primitives and the fiberwise-algebra code generators — not part of the public
interface, documented for contributors extending the package's algebra.

## The fiber

The value type at a single base point. The fiber is base-agnostic — the same `FiberVector` serves a field over a grid and a point-value section over a scattered set — so it lives here rather than with either base.

```@docs
FiberVector
FiberTensor2
FiberTensor3
FiberTensor4
fiber_shape
```

```@autodocs
Modules = [GBGPeriodicFields.FiberSections]
Public  = false
Order   = [:type, :constant, :function, :macro]
```
