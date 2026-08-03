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
transpose
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
# The BASE EXTENSIONS the package owns are public, but Documenter cannot know that: the package
# extends them without re-exporting them, so `Public = false` sweeps them into this section. The four
# bare operators were already excluded for exactly this reason; `map`, `map!` and `transpose` are the
# same class and were not. `map`/`map!` appeared TWICE — correctly under their own heading and again
# here — while `transpose` appeared ONLY here, so the allocating half of an `f`/`f!` pair was
# documented under a heading saying it is not part of the public interface.
Filter  = f -> !(nameof(f) in (:+, :-, :*, :/, :map, :map!, :transpose))
```
