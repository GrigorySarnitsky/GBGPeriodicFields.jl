# FieldAlgebra.jl

```@docs
GBGPeriodicFields.FieldAlgebra
```

```@contents
Pages = ["FieldAlgebra.md"]
```

## Field vector-space operations

```@docs
GBGPeriodicFields.FieldAlgebra.add!
GBGPeriodicFields.FieldAlgebra.subtract!
```

The allocating forms are provided by methods of `Base.+` and `Base.-` for compatible field and constant-fiber combinations.

## Multiplication and division

```@docs
GBGPeriodicFields.FieldAlgebra.multiply!
GBGPeriodicFields.FieldAlgebra.divide!
```

The allocating forms are provided by methods of `Base.*` and `Base./` where the corresponding operation is representation-wise meaningful.

## Vector products

```@docs
GBGPeriodicFields.FieldAlgebra.dot!
GBGPeriodicFields.FieldAlgebra.cross!
```

The allocating forms are provided by methods of `LinearAlgebra.dot` and `LinearAlgebra.cross`. The infix Unicode aliases `⋅` and `×` are also exported.

## Tensor-vector and tensor-tensor products

```@docs
GBGPeriodicFields.FieldAlgebra.mul!
```

The allocating tensor-vector and tensor-tensor forms are provided by methods of `Base.*`.

## Tensor index permutations

```@docs
GBGPeriodicFields.FieldAlgebra.transpose!
```

The allocating tensor-index transpose is provided by methods of `Base.transpose`.

## Tensor contractions and field norms

```@docs
GBGPeriodicFields.FieldAlgebra.norm!
GBGPeriodicFields.FieldAlgebra.norm
```

Fiberwise vector inner products and tensor Frobenius inner products are provided by methods of `LinearAlgebra.dot` and documented together with `dot!`.

## Tensor decompositions

```@docs
GBGPeriodicFields.FieldAlgebra.sym!
GBGPeriodicFields.FieldAlgebra.sym
GBGPeriodicFields.FieldAlgebra.skew!
GBGPeriodicFields.FieldAlgebra.skew
GBGPeriodicFields.FieldAlgebra.dev!
GBGPeriodicFields.FieldAlgebra.dev
```
