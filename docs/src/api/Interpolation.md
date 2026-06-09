# Interpolation

```@autodocs
Modules = [GBGPeriodicFields.Interpolation]
Order   = [:module]
```

The `Interpolation` module is the planned grid↔point transfer layer — interpolation (grid → point)
and its adjoint anterpolation (point → grid). **The transfer kernels are not yet implemented**; the
module currently records the design (its docstring above, and `docs/ARCHITECTURE.md` §10). The
point-value data types and their fiberwise algebra live in the [`Points`](Points.md) module.

## Index

```@index
Modules = [GBGPeriodicFields.Interpolation]
```
