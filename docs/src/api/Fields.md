# Fields

```@autodocs
Modules = [GBGPeriodicFields.Fields]
Order   = [:module]
```

The `Fields` module defines the field objects and their storage. A field is a physical object; the physical and spectral types (e.g. `ScalarFieldPhysical` and `ScalarFieldSpectral`) are two representations of the same field. It provides:

- **Grids and layout** — `Grid3D` for the periodic domain geometry and `RealFourierLayout` for the real-to-complex transform layout.
- **Fiber types** — the Cartesian fiber types `FiberVector`, `FiberTensor2`, `FiberTensor3`, `FiberTensor4` (StaticArrays aliases), elements of the fiber ``(\mathbb R^3)^{\otimes R}`` for tensor order ``R``.
- **Field types** — scalar, vector, and second-order tensor fields, each in physical-space and spectral representation.
- **Transforms** — `FieldTransformPlans` and `to_physical(!)` / `to_spectral(!)`. The allocating forms preserve their input; the in-place `!` forms may overwrite the source (a property of the real FFT — see their docstrings).
- **Spectral multipliers** — `FieldSpectralMultipliers`, the wavenumber arrays used by the spectral differential operators.
- **Broadcasting** — fields broadcast storage-wise and representation-preserving: a dotted assignment writes into the destination field's storage, while an out-of-place dotted expression allocates a compatible field in the same representation. Physical and spectral representations cannot be mixed in one broadcast.

## Contents

```@contents
Pages = ["Fields.md"]
Depth = 2:3
```

## Index

```@index
Modules = [GBGPeriodicFields.Fields]
```

## Public API

### Types

```@autodocs
Modules = [GBGPeriodicFields.Fields]
Public  = true
Private = false
Order   = [:type, :constant]
```

### Functions

```@autodocs
Modules = [GBGPeriodicFields.Fields]
Public  = true
Private = false
Order   = [:function]
```

## Internal API

These symbols are not part of the public interface; they are documented for contributors extending the package — field-allocation and compatibility helpers, the spectral-multiplier broadcast helpers, and the broadcast machinery.

### Types

```@autodocs
Modules = [GBGPeriodicFields.Fields]
Public  = false
Order   = [:type, :constant]
```

### Functions

```@autodocs
Modules = [GBGPeriodicFields.Fields]
Public  = false
Order   = [:function]
```
