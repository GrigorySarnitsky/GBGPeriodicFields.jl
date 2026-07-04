# FieldAlgebra

```@autodocs
Modules = [GBGPeriodicFields.FieldAlgebra]
Order   = [:module]
```

## Contents

```@contents
Pages = ["FieldAlgebra.md"]
Depth = 2:3
```

## Public API

### Vector-space operations

```@docs
add!
subtract!
multiply!
divide!
```

### Contraction and product operations

```@docs
dot!
dot
⋅
cross!
cross
×
mul!
```

### Transposition and decomposition operations

```@docs
transpose!
sym!
sym
skew!
skew
dev!
dev
```

### Norm operations

```@docs
norm!
norm
```

## Internal API

The code-generation machinery, documented for contributors adding operations: the expression and kernel-body builders, the contraction formula builders, the aliasing guard, and the constant / zero-mode helpers. The per-operation methods are stamped out from these by `@eval` tables and are not themselves documented.

### Functions

```@autodocs
Modules = [GBGPeriodicFields.FieldAlgebra]
Public  = false
Order   = [:function]
```
