# FiberSections

```@autodocs
Modules = [GBGPeriodicFields.FiberSections]
Order   = [:module]
```

The `FiberSections` module is the base-agnostic core of the package's fiber-bundle model
(`docs/ARCHITECTURE.md` §2): the `AbstractFiberSection` supertype shared by fields (sections over
a `Grid3D`) and point-values (sections over a `PointSet`), the CPU-threading / fused-assignment
primitive `_assign!`, and the vertical-algebra **code generators** (per-component formula and
kernel-body builders) reused verbatim by both `FieldAlgebra` and `Points`, so each fiberwise
formula is written exactly once.

## Contents

```@contents
Pages = ["FiberSections.md"]
Depth = 2:3
```

## Index

```@index
Modules = [GBGPeriodicFields.FiberSections]
```

## Public API

```@autodocs
Modules = [GBGPeriodicFields.FiberSections]
Public  = true
Private = false
Order   = [:type, :constant, :function]
```

## Internal API

The CPU-threading primitives and the vertical-algebra code generators — not part of the public
interface, documented for contributors extending the package's algebra.

```@autodocs
Modules = [GBGPeriodicFields.FiberSections]
Public  = false
Order   = [:type, :constant, :function, :macro]
```
