#=
AI tips for code generation

Conceptual model
----------------
This package represents real periodic fields on rectangular Cartesian domains. A field is a physical object; physical-space and spectral representations are storage/manipulation representations of that same object. In docstrings, prefer "scalar/vector/tensor field in physical-space representation" and "scalar/vector/tensor field in spectral representation". Avoid phrases such as "physical field" and "spectral field" unless the grammar would otherwise become unnatural.

All exposed mathematical objects should be real-valued physical objects. Complex arrays are an implementation detail of spectral storage, not user-facing complex fields.

The fiber dimension is three. Fiber vectors and tensors use the Cartesian Euclidean structure. Do not introduce curvilinear-coordinate machinery, explicit metric tensors, or vector/covector distinctions unless the package design changes.

Physical meaning of operations
------------------------------
Operations should represent operations on the underlying physical fields. Implement an operation in spectral representation only when it is mathematically equivalent to the physical-space operation and is efficient or more accurate there. Otherwise, restrict the method to the representation where the operation is sensible.

Linear algebra operations on fields are fiberwise operations. For example, `dot`, `⋅`, `cross`, `×`, `mul!`, `transpose`, scalar multiplication, and vector-space operations act pointwise on the fiber. Global \(L^2\)-type products, norms, adjoints, and integration-based operators belong to separate code with explicit notation.

Do not expose coefficientwise spectral products if they are not the Fourier representation of the corresponding physical operation. In particular, scalar-field multiplication is physical-space pointwise multiplication, products of two vector or tensor fields are defined only in physical-space representation, contractions and linear actions with constant fiber objects are allowed in both representations, and addition of constants in spectral representation must update only the zero Fourier mode.

Fourier normalization
---------------------
For FFT normalization, follow the convention of the Julia FFT packages actually used by the implementation. Under the AbstractFFTs convention, forward transforms are unnormalized, while inverse transforms include normalization. Therefore adding a physical constant `c` to a spectral representation updates only the zero Fourier coefficient by `c * prod(grid_size)` for the transformed spatial grid. Do not add `c` to all spectral coefficients.

CPU/GPU portability
-------------------
Storage arrays must be generic `AbstractArray`s. Allocate output arrays with `similar(field_data(reference), ...)`. Avoid CPU-specific assumptions.

GPU-compatible code must avoid scalar indexing of GPU arrays in package methods. Use broadcast, `map`, `mapreduce`, `copyto!`, views with broadcasted assignment, or explicit kernels when needed. Test CUDA and AMDGPU paths with scalar indexing disabled. Be careful with wrapped GPU arrays and nested views: if a wrapper causes fallback scalar iteration, rewrite the operation or use a backend-appropriate kernel.

Mutating methods should write into existing storage and return the modified destination. Prefer fused broadcasted assignments such as `destination_data .= expression` for elementwise operations; on CPU these thread only when routed through `Fields._assign!` / the `@_assign!` macro (a bare `.=` runs single-threaded), so hand-written kernels write `@_assign! destination_data .= expression` and the FieldAlgebra codegen body builders emit `_assign!`. Use explicit small-component formulas for three-component vector and second-order tensor operations when this is clearer and avoids reductions over the fiber dimension.

Do not add or suggest symmetric mixed-representation broadcast-style rules. Julia's broadcast style promotion only needs one binary method for a pair of styles.

Julia style
-----------
Use idiomatic Julia dispatch. Avoid type piracy: do not extend external functions on argument types that all belong to other packages. Extend external functions only when at least one argument type belongs to this package.

Import external functions before extending them, e.g. `import Base: +, -, *, /` and `import LinearAlgebra: dot, ⋅, cross, ×, mul!`.

For package-owned generic functions, attach the operation docstring to `function f end`. For additional method-family documentation on an already-defined package-owned generic, attach the docstring to the existing bare binding `f`. For imported Base, LinearAlgebra, or package functions, attach package-specific method-family documentation to the imported binding using the bare name `f`; do not write `function f end`, since a missing import could silently create a new local generic.

Do not define methods for pure fiber-fiber operations such as `dot(::FiberVector, ::FiberVector)` or `transpose(::FiberTensor2)`: these fiber types are aliases for StaticArrays types, and LinearAlgebra/StaticArrays already handles such operations.

Use descriptive names. Avoid abbreviations unless they are standard mathematical notation. Use two-space indentation. Follow the existing code style in this package. Normal Julia code may use moderately long lines when this improves readability or matches the surrounding style; do not aggressively split ordinary function signatures. In docstrings, prose may also use long lines, but verbatim signatures and code examples should remain conservatively narrow because Documenter renders them in a documentation column.

Avoid unnecessary explicit type declarations in local variables. Do not compute matrix inverses for linear solves; use `\`, factorizations followed by `\`, or `ldiv!` where an in-place solve is appropriate.

When relying on Julia, Base, standard libraries, or other Julia package behavior, always check the official documentation or docstrings.

Docstring style
---------------
Docstrings should be short, concrete, and physically meaningful. Prefer direct statements of what the method computes, in which representation it is valid, and whether it allocates or mutates.

Use representation-based terminology:
    good: "scalar field in physical-space representation"
    bad:  "physical scalar field"

State whether an operation is pointwise in physical-space representation, coefficientwise in spectral representation, representation-preserving, a zero-mode update, or a fiberwise contraction.

Use "real number" for `Real` scalar constants when this avoids confusion with scalar fields. Use "scalar field" only for field-valued scalar functions. Use "fiber vector" and "fiber tensor" for constant elements of the fiber.

Mention when a method is intentionally not provided because the operation is not physically meaningful in that representation.

Document hand-written internal machinery (the codegen builders, the alias guards, the shared Fields helpers, the spectral kernels) with docstrings too: they surface in the package's per-module "Internal API" documentation section (collected by Documenter `@autodocs` with `Public = false`), so contributors can extend the package consistently. The `@eval`-generated methods and kernels carry no docstrings — the formula docstring lives on the builder, consistent with "generators emit methods only — never docstrings". Reserve plain comments for non-intuitive rationale (the *why*) that a descriptive name cannot convey.

Maintenance
-----------
Keep this AI-tips block updated when new project requirements are established, and check generated code against it before returning changes.
=#


"""
    GBGPeriodicFields

Tools for representing, transforming, and manipulating scalar, vector, and tensor fields on three-dimensional rectangular periodic domains.

The package is aimed primarily at fluid-dynamics and turbulence simulations, with physical-space and real-to-complex spectral representations
designed for both CPU and GPU array backends. It also targets Lagrangian particle simulations through interpolation tools for evaluating fields between grid nodes.

The package provides field representations, FFT transform plans, storage-wise broadcasting, and algebraic operations on fields.
"""
module GBGPeriodicFields


include("Fields.jl")
include("FieldAlgebra.jl")
include("DifferentialOperators.jl")
include("Interpolation.jl")


using .Fields:
  FiberVector,
  FiberTensor2,
  FiberTensor3,
  FiberTensor4,
  Grid3D,
  RealFourierLayout,
  AbstractFieldPhysical,
  AbstractFieldSpectral,
  ScalarFieldPhysical,
  ScalarFieldSpectral,
  VectorFieldPhysical,
  VectorFieldSpectral,
  TensorFieldPhysical,
  TensorFieldSpectral,
  FieldTransformPlans,
  to_physical!,
  to_spectral!,
  to_physical,
  to_spectral,
  field_data,
  field_grid,
  field_layout,
  field_scalar_type,
  field_tensor_order,
  fiber_shape,
  physical_field_shape,
  spectral_field_shape,
  FieldSpectralMultipliers,
  with_threading,
  set_threading_cutoff!,
  threading_cutoff,
  set_fft_threads!


using .FieldAlgebra:
  add!,
  subtract!,
  multiply!,
  divide!,
  dot!,
  dot,
  ⋅,
  cross!,
  cross,
  ×,
  mul!,
  transpose!,
  norm!,
  norm,
  sym!,
  sym,
  skew!,
  skew,
  dev!,
  dev


using .DifferentialOperators:
  gradient!,
  gradient,
  divergence!,
  divergence,
  curl!,
  curl,
  laplacian!,
  laplacian,
  inverse_laplacian!,
  inverse_laplacian,
  helmholtz_projection!,
  helmholtz_projection


export FiberVector,
       FiberTensor2,
       FiberTensor3,
       FiberTensor4,
       Grid3D,
       RealFourierLayout,
       AbstractFieldPhysical,
       AbstractFieldSpectral,
       ScalarFieldPhysical,
       ScalarFieldSpectral,
       VectorFieldPhysical,
       VectorFieldSpectral,
       TensorFieldPhysical,
       TensorFieldSpectral,
       FieldTransformPlans,
       to_physical!,
       to_spectral!,
       to_physical,
       to_spectral,
       field_data,
       field_grid,
       field_layout,
       field_scalar_type,
       field_tensor_order,
       fiber_shape,
       physical_field_shape,
       spectral_field_shape,
       add!,
       subtract!,
       multiply!,
       divide!,
       dot!,
       dot,
       ⋅,
       cross!,
       cross,
       ×,
       mul!,
       transpose!,
       norm!,
       norm,
       sym!,
       sym,
       skew!,
       skew,
       dev!,
       dev,
       FieldSpectralMultipliers,
       gradient!,
       gradient,
       divergence!,
       divergence,
       curl!,
       curl,
       laplacian!,
       laplacian,
       inverse_laplacian!,
       inverse_laplacian,
       helmholtz_projection!,
       helmholtz_projection,
       with_threading,
       set_threading_cutoff!,
       threading_cutoff,
       set_fft_threads!


function __init__()
  Fields._init_fft_threads()
end


end # module GBGPeriodicFields