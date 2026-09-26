# GBGPeriodicFields — umbrella module: it sets the include order and assembles the public API.
#
# The conceptual model (a field is a section of a trivial, flat tensor bundle; physical and
# spectral are representations of one object), the representation-validity rules, the FFT/Nyquist
# conventions, and the writing/docstring conventions are not duplicated here — they live in
# `docs/ARCHITECTURE.md` (the rationale) and `CLAUDE.md` (the operational rules).


"""
    GBGPeriodicFields

GBGPeriodicFields carries real-valued scalar, vector and second-order-tensor fields on
three-dimensional rectangular periodic domains, in physical-space and real-to-complex spectral
representations, on CPU and GPU backends, with HDF5 field persistence.

The tensors are **Cartesian** — components on one fixed right-handed orthonormal frame, with no
curvilinear coordinates or metric machinery — so this is an applied field toolkit
rather than a general differential-geometry package.

These words recur in every operation's documentation:

- a **base** is the set of locations a value is attached to: a `Grid3D` of nodes, or a `PointSet` of
  off-grid positions. A grid cell carries the quadrature weight a reduction integrates against; the
  values themselves sit on the nodes.
- a **fiber** is the value at one such location — a scalar, a `FiberVector`, or a `FiberTensor2`.
- a **section** puts the two together: it assigns one fiber to every point of a base, which is what a
  field and a set of point-values each are, and why one set of formulas serves both.
- the **resolved band** is the set of wavenumbers a grid's resolution actually represents, *excluding*
  the Nyquist frequency of each even-length axis. Those planes are excluded because there the wavenumbers
  used for first derivatives are zeroed while the squared ones used for the Laplacian keep the true
  value — so every identity scoped "on the resolved band" holds off them and may
  fail on them. An odd-length axis has no exact Nyquist mode and so loses nothing.
- a field is **band-limited** when its Fourier content vanishes above the wavenumbers the grid stores,
  so the finite trigonometric series those coefficients define represents it exactly. A product of two
  such fields is not band-limited, which is why the operations that form one are offered in physical
  representation only.
- a section's **scalar type** is its real precision — the `T <: AbstractFloat` every field and
  point-value type is parameterized on, `Float64` or `Float32`, read back by
  [`field_scalar_type`](@ref). Its **element type** is what the storage array actually holds, and the
  two part company in spectral representation: physical storage holds `T`, spectral storage holds
  `Complex{T}` at the same scalar type. Precision is the scalar type; the complex storage is
  representation detail, so a field in spectral representation is no less a `Float64` field.
- a section's **storage family** is the kind of array its data lives in — `Array` on the host,
  `CuArray` or `ROCArray` on a device — taken as the array's underlying type rather than its wrapping,
  so a `reshape` of an `Array` is still the `Array` family. Two sections combine only within one
  storage family and one element type; a mixed pair is refused rather than converted, and
  [`adapt`](@ref) moves one explicitly — a field, the wavenumber multipliers and convolution kernels
  built for it, its transform plans, a point set or point values — into another family, never changing the
  element type.

The package is the field layer for pseudospectral fluid and turbulence solvers, and it
carries a point layer that evaluates fields between grid nodes for Lagrangian-particle
methods. A field is one real physical object; the physical and spectral forms are two
representations of that same object.

This top-level module assembles its public interface from the submodules below. Each module's own
docstring maps what it provides, so this list says what each is for rather than repeating it:

- [`FiberSections`](@ref) — the base-agnostic foundation both layers share: the fiber types
  [`FiberVector`](@ref) and [`FiberTensor2`](@ref)/[`FiberTensor3`](@ref)/[`FiberTensor4`](@ref), which name the value
  at one base point and so belong to neither base in particular.
- [`Fields`](@ref) — the field and grid types, the two representations and the transforms between
  them, allocation, broadcasting, HDF5 persistence, and the storage-family move `adapt`.
- [`FieldAlgebra`](@ref) — the fiberwise algebra on fields, including [`map!`](@ref)/[`map`](@ref)
  for any fiber map it does not name.
- [`DifferentialOperators`](@ref) — the differential operators, applied as spectral multipliers.
- [`Convolution`](@ref) — periodic convolution against a kernel, and the kernel builders. A kernel is
  its own kind of object rather than a field.
- [`Points`](@ref) — the unstructured base: point-data types, their fiberwise algebra mirroring the
  field surface, spatial motion, and HDF5 persistence.
- [`Interpolation`](@ref) — the grid↔point transfer, [`interpolate`](@ref) and [`anterpolate`](@ref) as an
  adjoint pair, under a choice of scheme.
- [`Reductions`](@ref) — the L²/measure reductions over fields and point-values, against the base's
  own measure.

!!! note "Scalar, vector and second-order tensors only"
    Sections of tensor order ``R = 0, 1, 2`` — scalar, vector and second-order tensor — are the
    supported surface: no operation reaches past it, though not all span all three. Some are
    defined at one order by their own mathematics — `det` and `tr` need a matrix, `cov` a vector,
    `std`, `var` and the bare `maximum`/`minimum`/`extrema` a scalar — and each says so in its own
    docstring. The field and point-value types are
    parameterized on `R`, so higher orders can be constructed and several layers serve them
    (storage, HDF5 persistence, the vector-space operations, `inner`, `l2norm`, and spline
    interpolation between grid and points). Others do not: the reductions returning a fiber or taking
    a fiber map (`mean(det, A)`), `map`, and `sym`/`skew`/`dev` are defined for ``R \\le 2`` and
    **throw** above it.

    General `R` was deferred rather than declined, to ship a usable field layer for the second-order
    surface a pseudospectral solver actually needs. Above the ceiling an operation either works or
    raises — none returns a wrong answer — and the test suite checks that.
"""
module GBGPeriodicFields


include("FiberSections.jl")
include("Fields.jl")
include("FieldAlgebra.jl")
include("DifferentialOperators.jl")
include("Convolution.jl")
include("Points.jl")
include("Interpolation.jl")
include("Reductions.jl")


using .FiberSections:
  AbstractFiberSection,
  FiberVector,
  FiberTensor2,
  FiberTensor3,
  FiberTensor4,
  fiber_shape,
  with_threading,
  set_threading_cutoff!,
  threading_cutoff


using .Fields:
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
  write_field,
  read_field,
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
  field_physical_shape,
  field_spectral_shape,
  similar_field,
  reality_residual,
  reality_projection!,
  embed_modes!,
  extract_modes!,
  FieldSpectralMultipliers,
  SpectralKernel,           # the kernel supertype; Convolution defines the four storage classes
  set_fft_threads!,
  adapt,                    # extended for every section, kernel and plan; re-exported below
  adapt!                    # the in-place storage move, for sections only (decision 69)


using .FieldAlgebra:
  add!,
  subtract!,
  combine!,
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
  tr!,
  tr,
  det!,
  det


using .DifferentialOperators:
  gradient!,
  gradient,
  divergence!,
  divergence,
  curl!,
  curl,
  inverse_curl!,
  inverse_curl,
  symmetric_gradient!,
  symmetric_gradient,
  laplacian!,
  laplacian,
  inverse_laplacian!,
  inverse_laplacian,
  helmholtz_projection!,
  helmholtz_projection


using .Convolution:
  StoredKernel,
  SeparableKernel,
  RadialKernel,
  ProductKernel,
  radial_kernel,
  materialize_kernel,
  translation_kernel!,
  convolve!,
  convolve,
  ⋆,
  exponential_convolve!,
  exponential_convolve,
  spectral_cutoff,
  spectral_band,
  assignment_window,
  tophat_window,
  translation_kernel


using .Points:
  Point,
  PointSet,
  AbstractPointValues,
  ScalarPointValues,
  VectorPointValues,
  TensorPointValues,
  point_positions,
  point_values,
  point_value_tensor_order,
  npoints,
  similar_point_values,
  displace!,
  wrap!,
  write_points,
  read_points


using .Interpolation:
  interpolate,
  interpolate!,
  anterpolate,
  anterpolate!,
  point_traversal_order,
  point_traversal_order!,
  PointTraversalOrder,
  PointTraversalOrderScratch,
  LalescuSpline,
  LagrangeSpline,
  CatmullRom,
  AbstractTransferScheme,
  DirectDFT,
  NUFFT,
  write_scheme,
  read_scheme


using .Reductions:
  integral,
  inner,
  weighted_inner,
  l2norm,
  lpnorm,
  radial_spectrum,
  radial_correlation,
  # The `Statistics` generics the package extends, pulled through the submodule and re-exported below
  # exactly as `dot`/`cross`/`mul!`/`norm` are pulled through `FieldAlgebra` from `LinearAlgebra`: a
  # user should not have to know which standard library a reduction's verb happens to live in. Safe,
  # because two packages re-exporting the SAME binding do not collide — only two packages exporting
  # DIFFERENT bindings of one name do. `maximum`/`minimum`/`extrema` need no such treatment, being
  # `Base` and so already in scope.
  mean,
  std,
  var,
  cov


export FiberVector,
       FiberTensor2,
       FiberTensor3,
       FiberTensor4,
       Grid3D,
       RealFourierLayout,
       AbstractFiberSection,
       AbstractFieldPhysical,
       AbstractFieldSpectral,
       ScalarFieldPhysical,
       ScalarFieldSpectral,
       VectorFieldPhysical,
       VectorFieldSpectral,
       TensorFieldPhysical,
       TensorFieldSpectral,
       write_field,
       read_field,
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
       field_physical_shape,
       field_spectral_shape,
       similar_field,
       reality_residual,
       reality_projection!,
       embed_modes!,
       extract_modes!,
       # Re-exported from `Adapt`, not owned here: it is the ecosystem-standard verb for moving a
       # struct between storage families, and the package extends it for every section, kernel and
       # plan. Re-exporting is what makes it reachable from `using GBGPeriodicFields` alone — without
       # it the interface exists but a user has to know to reach for `Adapt` themselves.
       adapt,
       adapt!,
       add!,
       subtract!,
       combine!,
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
       tr!,
       tr,
       det!,
       det,
       FieldSpectralMultipliers,
       gradient!,
       gradient,
       divergence!,
       divergence,
       curl!,
       curl,
       inverse_curl!,
       inverse_curl,
       symmetric_gradient!,
       symmetric_gradient,
       laplacian!,
       laplacian,
       inverse_laplacian!,
       inverse_laplacian,
       helmholtz_projection!,
       helmholtz_projection,
       convolve!,
       convolve,
       ⋆,
       exponential_convolve!,
       exponential_convolve,
       spectral_cutoff,
       spectral_band,
            assignment_window,
            tophat_window,
       translation_kernel,
       translation_kernel!,
       SpectralKernel,
       StoredKernel,
       SeparableKernel,
       RadialKernel,
       ProductKernel,
       radial_kernel,
       materialize_kernel,
       with_threading,
       set_threading_cutoff!,
       threading_cutoff,
       set_fft_threads!,
       Point,
       PointSet,
       AbstractPointValues,
       ScalarPointValues,
       VectorPointValues,
       TensorPointValues,
       point_positions,
       point_values,
       point_value_tensor_order,
       npoints,
       similar_point_values,
       displace!,
       wrap!,
       write_points,
       read_points,
       interpolate,
       interpolate!,
       anterpolate,
       anterpolate!,
       point_traversal_order,
       point_traversal_order!,
       PointTraversalOrder,
       PointTraversalOrderScratch,
       LalescuSpline,
       LagrangeSpline,
       CatmullRom,
       AbstractTransferScheme,
       DirectDFT,
       NUFFT,
       write_scheme,
       read_scheme,
       integral,
       inner,
       weighted_inner,
       l2norm,
       lpnorm,
       radial_spectrum,
       radial_correlation,
       mean,
       std,
       var,
       cov


function __init__()
  Fields._init_fft_threads()
end


end # module GBGPeriodicFields