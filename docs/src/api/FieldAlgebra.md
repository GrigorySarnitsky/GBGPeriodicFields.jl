# FieldAlgebra

```@autodocs
Modules = [GBGPeriodicFields.FieldAlgebra]
Order   = [:module]
```

## Vector-space and scalar-field-scaling operations

```@docs
add!
+
subtract!
-
combine!
multiply!
*
divide!
/
```

## Contraction and product operations

```@docs
dot!
dot
⋅
cross!
cross
×
mul!
tr!
tr
det!
det
```

## Transposition and decomposition operations

```@docs
transpose!
sym!
sym
skew!
skew
dev!
dev
```

## Norm operations

```@docs
norm!
norm
```

## Arbitrary fiber map

The escape hatch for an arbitrary fiber map that is not one of the named operations above — fields in physical representation here, point-values in [`Points`](@ref); see [`map!`](@ref) for the physical-space-only and aliasing caveats.

```@docs
map!
map
```

## Internal API

These symbols are not part of the public interface; they are documented for contributors adding operations — the code-generation machinery: the expression and kernel-body builders, the contraction formula builders, and the constant / zero-mode helpers. The per-operation methods are stamped out from these by `@eval` tables and are not themselves documented.

```@autodocs
Modules = [GBGPeriodicFields.FieldAlgebra]
Public  = false
Order   = [:function]
Filter  = f -> !(nameof(f) in (:+, :-, :*, :/))
```
