# FieldAlgebra

```@autodocs
Modules = [GBGPeriodicFields.FieldAlgebra]
Order   = [:module]
```

The `FieldAlgebra` module provides fiberwise, pointwise algebra on the fields defined in [`Fields`](Fields.md). Each operation comes as an in-place `!` form and an allocating form (a `Base`/`LinearAlgebra` operator where one exists).

The operation families are:

- **Vector-space operations** — `add!`/`subtract!` (and `+`/`-`), scaling by a real number, and scalar-field multiplication/division (`multiply!`/`divide!`, `*`/`/`).
- **Contractions** — `dot!`/`dot` (vector Euclidean and tensor Frobenius inner products; `⋅` alias), `cross!`/`cross` (`×` alias).
- **Tensor products** — `mul!` for tensor·vector (left and right action) and tensor·tensor, with the five-argument `α`/`β` accumulation form; allocating `*`.
- **Permutations and decompositions** — `transpose!`/`transpose`, `sym`/`skew`/`dev` (and their `!` forms).
- **Norms** — `norm!`/`norm` (pointwise absolute value, Euclidean, and Frobenius).

**Representation validity is the spec.** Operations linear in the field (vector-space operations, contractions with a *constant* fiber, transpose, sym/skew/dev) are valid in both representations. Operations nonlinear in the field (products of two fields, contractions of two fields, pointwise norms) are physical-space only — the coefficientwise spectral product is not the Fourier transform of the pointwise product. Missing combinations are deliberate.

**Aliasing.** `mul!` follows the `LinearAlgebra` convention: the destination must not share storage with an input. The index-shuffling operations (cross product, transpose, sym/skew/dev) are alias-guarded and may be called with the destination aliasing an input.

## Contents

```@contents
Pages = ["FieldAlgebra.md"]
Depth = 2:3
```

## Index

```@index
Modules = [GBGPeriodicFields.FieldAlgebra]
```

## Public API

### Functions

```@autodocs
Modules = [GBGPeriodicFields.FieldAlgebra]
Public  = true
Private = false
Order   = [:function]
```

## Internal API

The code-generation machinery, documented for contributors adding operations: the expression and kernel-body builders, the contraction formula builders, the aliasing guard, and the constant / zero-mode helpers. The per-operation methods are stamped out from these by `@eval` tables and are not themselves documented.

### Functions

```@autodocs
Modules = [GBGPeriodicFields.FieldAlgebra]
Public  = false
Order   = [:function]
```
