# FiberSections

```@autodocs
Modules = [GBGPeriodicFields.FiberSections]
Order   = [:module]
```

## Contents

```@contents
Pages = ["FiberSections.md"]
Depth = 2:3
```

## Public API

### Fiber-section supertype

```@docs
AbstractFiberSection
```

### Threading configuration

```@docs
threading_cutoff
set_threading_cutoff!
with_threading
```

## Internal API

The CPU-threading primitives and the vertical-algebra code generators — not part of the public
interface, documented for contributors extending the package's algebra.

```@autodocs
Modules = [GBGPeriodicFields.FiberSections]
Public  = false
Order   = [:type, :constant, :function, :macro]
```
