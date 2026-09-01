# GBGPeriodicFields — umbrella module: it sets the include order and assembles the public API.
#
# The conceptual model (a field is a section of a trivial, flat tensor bundle; physical and
# spectral are representations of one object), the representation-validity rules, the FFT/Nyquist
# conventions, and the writing/docstring conventions are not duplicated here — they live in
# `docs/ARCHITECTURE.md` (the rationale) and `CLAUDE.md` (the operational rules).


"""
    GBGPeriodicFields

Real-valued scalar, vector, and second-order-tensor fields on three-dimensional
rectangular periodic domains, carried in physical-space and real-to-complex spectral
representations, on both CPU and GPU array backends, with HDF5 field persistence.

The tensors are **Cartesian** — components on one fixed orthonormal frame, with no
curvilinear coordinates and no metric machinery — so this is an applied field toolkit
rather than a general differential-geometry package.

Five words recur in every operation's documentation. A **base** is the set of locations a value is
attached to: a `Grid3D` of nodes, or a `PointSet` of off-grid positions. (A grid cell carries the
quadrature weight a reduction integrates against; the values sit on the nodes.) A **fiber** is the value at
one such location — a scalar, a `FiberVector`, or a `FiberTensor2`. A **section** puts the two together — it assigns
one fiber to every point of a base — which is what a field and a set of point-values each are, and
why one set of formulas serves both. The **resolved band** is the set of wavenumbers a grid's
resolution actually represents, *excluding* the Nyquist frequency of each even-length axis. Those
Nyquist planes are excluded by definition because the package's two wavenumber families disagree
exactly there — the derivative family is zeroed there while the squared family keeps the true value
— so every identity this documentation scopes "on the resolved band" holds off them and may fail on
them. An odd-length axis has no exact Nyquist mode and so loses nothing. A field is **band-limited**
when its Fourier content vanishes above the wavenumbers the grid stores, so the finite trigonometric
series those coefficients define represents it exactly; a product of two such fields is not band-limited,
which is why the operations that form one are offered in physical representation only. A section's
**storage family** is the kind of array its data lives in — `Array` on the host, `CuArray` or
`ROCArray` on a device — taken as the array's underlying type rather than its wrapping, so that a
`reshape` of an `Array` is still the `Array` family. Two sections combine only within one storage
family and one element type; a mixed pair is refused rather than converted, and [`adapt`](@ref) is the
explicit operation that moves one — a field, its multipliers, its kernels, its transform plans, a
point set or point values — into another family when that is what you want. It never changes the element type.

!!! note "Scalar, vector and second-order tensors only"
    Scalar, vector and second-order tensor sections — ``R = 0, 1, 2`` — are the supported
    surface: no operation below reaches past it, though not every operation spans all three. Some are
    defined at one order by their own mathematics — `det` and `tr` need a matrix, `cov` a vector,
    `std`, `var` and the bare `maximum`/`minimum`/`extrema` a scalar — and each says so in its own
    docstring. The field and point-value types are
    parameterized on `R`, so higher orders can be constructed and several layers serve them
    (storage, HDF5 persistence, the vector-space operations, `inner`, `l2norm`, and the local-spline
    transfer). Others do not: the fiber-preserving and mapped reductions, `map`, and the
    decomposition family are defined for ``R \\le 2`` and **throw** above it.

    General `R` was deferred rather than declined, to ship a usable field layer for the second-order
    surface a pseudospectral solver actually needs. Above the ceiling an operation either works or
    raises — none returns a wrong answer — and a test lane pins that, so the boundary is visible
    rather than a surprise.

The package is the field layer for pseudospectral fluid and turbulence solvers, and it
carries a point layer that evaluates fields between grid nodes for Lagrangian-particle
methods. A field is one real physical object; the physical and spectral forms are two
representations of that same object.

The umbrella assembles its public surface from the submodules below:

- [`Fields`](@ref) supplies the field and grid types, the storage layout and broadcasting,
  the FFT transform plans, the transforms [`to_physical`](@ref) and
  [`to_spectral`](@ref) between the two representations, the allocator [`similar_field`](@ref) that
  builds compatible scratch, the storage-family move [`adapt`](@ref) that carries a field, its
  multipliers, its kernels, its plans, a point set or point values between host and device, and the HDF5 persistence pair
  `write_field`/`read_field` (available once `HDF5` is loaded). The six field constructors also accept a
  storage **family** in place of an array — `VectorFieldSpectral(CuArray, grid, layout)` — for a caller
  holding domain context but no field to copy from, `adapt` has an in-place sibling `adapt!` for a
  destination that already exists, and `reality_residual` reports how far a field's coefficients are
  from being a real field's spectrum (it reports, and never repairs).
- [`FieldAlgebra`](@ref) provides the fiberwise algebra: the vector-space operations `add!` and
  `subtract!`, the weighted combination [`combine!`](@ref), the scalar actions `multiply!` and
  `divide!`, the contractions `dot` and `cross`, the tensor product `mul!`, the transpose
  `transpose!`, the norm `norm`, the trace and determinant `tr`/`det`, the
  [`sym`](@ref)/`skew`/`dev` decompositions, and [`map!`](@ref)/[`map`](@ref) applying an arbitrary fiber
  map `φ` at every base point — the escape hatch for any pointwise operation not named here.
- [`DifferentialOperators`](@ref) provides the differential operators [`gradient`](@ref),
  `divergence`, `curl`, `inverse_curl`, `symmetric_gradient`, `laplacian`, `inverse_laplacian`, and
  `helmholtz_projection`.
- [`Convolution`](@ref) provides periodic convolution [`convolve`](@ref), its lazy exponential form
  `exponential_convolve` and the kernel-composed `combine!` method, together with the
  kernel builders `spectral_cutoff`, `spectral_band`, `assignment_window`, `translation_kernel`, and `radial_kernel` for any other real function of the squared
  wavenumber. A kernel is its own kind of object rather than a field: it is held as a `StoredKernel` of
  one coefficient per mode, or in one of the compressed classes `SeparableKernel`, `RadialKernel` and
  `ProductKernel`, which store a closed-form multiplier instead of its coefficients; the classes are
  interchangeable and agree bit for bit on the host (on a device a **complex**-valued kernel is the one
  exception, the classes agreeing there to rounding), and `materialize_kernel` expands a compressed one into a
  `StoredKernel`. A field of coefficients is not itself a kernel; `StoredKernel` is the wrapper that
  puts it in that role.
- [`Points`](@ref) supplies the point-data types, their fiberwise algebra mirroring the field surface in physical
  representation — including the same [`map!`](@ref)/[`map`](@ref) escape hatch, which needs no
  representation split here because point-values carry none — the spatial motion pair
  [`displace!`](@ref)/[`wrap!`](@ref) (points moved along coefficient-weighted vector sections, and
  positions reduced to their canonical in-box representatives), the matching allocator
  `similar_pointvalues`, and the HDF5 persistence pair `write_points`/`read_points` (available once
  `HDF5` is loaded).
- [`Interpolation`](@ref) provides the grid-to-point transfer [`interpolate`](@ref) and its
  adjoint point-to-grid transfer `anterpolate`, over the local-spline and spectral schemes, together
  with the scheme-persistence pair `write_scheme`/`read_scheme` (available once `HDF5` is loaded).
- [`Reductions`](@ref) provides the L²/measure reductions [`integral`](@ref), `inner`,
  `weighted_inner`, `l2norm`, and `lpnorm`; the moments `mean`, the scalar-only `std`/`var` and the
  covariance tensor `cov` that carries a vector field's second *central* moment coordinate-free, and the order
  statistics `maximum`/`minimum`/`extrema`, which extend their `Statistics` and `Base` generics on sections and are all reachable from `using GBGPeriodicFields` alone;
  and the radial reductions `radial_spectrum` and `radial_correlation`. Five of them — `integral`,
  `mean`, `maximum`, `minimum` and `extrema` — also take a **leading fiber map**, which reduces a
  nonlinear invariant without building it; the others have no mapped form.

[`FiberSections`](@ref) is the base-agnostic foundation that the field and point layers share. It owns
the fiber types [`FiberVector`](@ref) and [`FiberTensor2`](@ref)/`FiberTensor3`/`FiberTensor4`, which
name the value at one base point and so belong to neither base in particular.
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
  physical_field_shape,
  spectral_field_shape,
  similar_field,
  reality_residual,
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
  translation_kernel


using .Points:
  Point,
  PointSet,
  AbstractPointValues,
  ScalarPointValues,
  VectorPointValues,
  TensorPointValues,
  point_coordinates,
  point_values,
  pointvalue_tensor_order,
  npoints,
  similar_pointvalues,
  displace!,
  wrap!,
  write_points,
  read_points


using .Interpolation:
  interpolate,
  interpolate!,
  anterpolate,
  anterpolate!,
  transfer_order,
  TransferOrder,
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
       physical_field_shape,
       spectral_field_shape,
       similar_field,
       reality_residual,
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
       point_coordinates,
       point_values,
       pointvalue_tensor_order,
       npoints,
       similar_pointvalues,
       displace!,
       wrap!,
       write_points,
       read_points,
       interpolate,
       interpolate!,
       anterpolate,
       anterpolate!,
       transfer_order,
       TransferOrder,
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