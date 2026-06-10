# Reductions

```@autodocs
Modules = [GBGPeriodicFields.Reductions]
Order   = [:module]
```

The `Reductions` module is the **L² / measure structure** on sections — the third operation family
alongside the vertical (fiberwise) algebra of [`FieldAlgebra`](FieldAlgebra.md) and the horizontal
(differential) operators of [`DifferentialOperators`](DifferentialOperators.md). A reduction
integrates a section over its base against the measure the base carries (`Grid3D`'s uniform cell
volume; `PointSet`'s counting measure), and is defined on **physical fields and point-values**
(representation-free quantities). See `docs/ARCHITECTURE.md` §2 and decision 18.

`integral` is the extensive `∫f dμ`; `inner`/`l2norm`/`lpnorm` are the normalized L² inner product
and norms. The `mean`/`std`/`var` (from `Statistics`) and `maximum`/`minimum`/`extrema` (from `Base`)
are *extended* on sections here — reached through `using Statistics` / `Base`, not re-exported.
Physics stays in the consumer (kinetic energy `½ inner(u,u)`, enstrophy, dissipation, rms).

## Contents

```@contents
Pages = ["Reductions.md"]
Depth = 2:3
```

## Index

```@index
Modules = [GBGPeriodicFields.Reductions]
```

## Public API

```@autodocs
Modules = [GBGPeriodicFields.Reductions]
Public  = true
Private = false
Order   = [:function]
```

## Internal API

These symbols are not part of the public interface; they are documented for contributors — the base
measure (count and cell measure) and the fiber-preserving reduction helper.

```@autodocs
Modules = [GBGPeriodicFields.Reductions]
Public  = false
Order   = [:function]
```
