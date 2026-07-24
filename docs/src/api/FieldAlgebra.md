# FieldAlgebra

```@autodocs
Modules = [GBGPeriodicFields.FieldAlgebra]
Order   = [:module]
```

## Vector-space and scalar-field-scaling operations

```@docs
add!
subtract!
combine!
multiply!
divide!
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

## Internal API

The code-generation machinery, documented for contributors adding operations: the expression and kernel-body builders, the contraction formula builders, and the constant / zero-mode helpers. The per-operation methods are stamped out from these by `@eval` tables and are not themselves documented.

```@autodocs
Modules = [GBGPeriodicFields.FieldAlgebra]
Public  = false
Order   = [:function]
```
