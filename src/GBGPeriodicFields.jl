# GBGPeriodicFields — umbrella module: it sets the include order and assembles the public API.
#
# The conceptual model (a field is a section of a trivial, flat tensor bundle; physical and
# spectral are representations of one object), the representation-validity rules, the FFT/Nyquist
# conventions, and the writing/docstring conventions are not duplicated here — they live in
# `docs/ARCHITECTURE.md` (the rationale) and `CLAUDE.md` (the operational rules).


"""
    GBGPeriodicFields

Represent, transform, and manipulate real-valued scalar, vector, and second-order-tensor
fields on three-dimensional rectangular periodic domains, in physical-space and
real-to-complex spectral representations, on both CPU and GPU array backends.

The package is the field layer for pseudospectral fluid and turbulence solvers, and it
carries a point layer that evaluates fields between grid nodes for Lagrangian-particle
methods. A field is one real physical object; the physical and spectral forms are two
representations of that same object.

The umbrella assembles its public surface from the submodules below, each of which owns
one operation family:

- [`Fields`](@ref) supplies the field and grid types, the storage layout and broadcasting,
  the FFT transform plans, and the transforms [`to_physical`](@ref) and
  [`to_spectral`](@ref) between the two representations.
- [`FieldAlgebra`](@ref) provides the fiberwise algebra: the contractions `dot` and `cross`,
  the tensor product `mul!`, the transpose `transpose!`, the norm `norm`, and the
  [`sym`](@ref)/`skew`/`dev` decompositions.
- [`DifferentialOperators`](@ref) provides the spectral operators [`gradient`](@ref),
  `divergence`, `curl`, `laplacian`, `inverse_laplacian`, and `helmholtz_projection`.
- [`Convolution`](@ref) provides periodic convolution [`convolve`](@ref) together with the
  kernel builders `spectral_cutoff`, `spectral_band`, `squared_wavenumber_field`, and
  `assignment_window`.
- [`Points`](@ref) supplies the point-data types and their fiberwise algebra, mirroring the
  physical field surface.
- [`Interpolation`](@ref) provides the grid-to-point transfer [`interpolate`](@ref) and its
  adjoint point-to-grid transfer `anterpolate`, over the local-spline and spectral schemes.
- [`Reductions`](@ref) provides the L²/measure reductions [`integral`](@ref), `inner`,
  `l2norm`, and `lpnorm`, plus the radial diagnostics `radial_spectrum` and
  `radial_correlation`.

[`FiberSections`](@ref) is the base-agnostic foundation that the field and point layers share.
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
  with_threading,
  set_threading_cutoff!,
  threading_cutoff


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


using .Convolution:
  convolve!,
  convolve,
  spectral_cutoff,
  spectral_band,
  squared_wavenumber_field,
  assignment_window


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
  npoints


using .Interpolation:
  interpolate,
  interpolate!,
  anterpolate,
  anterpolate!,
  LalescuSpline,
  LagrangeSpline,
  CatmullRom,
  AbstractTransferScheme,
  DirectDFT,
  NUFFT


using .Reductions:
  integral,
  inner,
  l2norm,
  lpnorm,
  radial_spectrum,
  radial_correlation

# `mean`/`std`/`var` (Statistics) and `maximum`/`minimum`/`extrema` (Base) are *extended* on sections
# in `Reductions`; those methods are global and reached through `using Statistics` / Base. They are
# deliberately not re-exported here (re-exporting another package's bindings is avoided).


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
       convolve!,
       convolve,
       spectral_cutoff,
       spectral_band,
       squared_wavenumber_field,
       assignment_window,
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
       interpolate,
       interpolate!,
       anterpolate,
       anterpolate!,
       LalescuSpline,
       LagrangeSpline,
       CatmullRom,
       AbstractTransferScheme,
       DirectDFT,
       NUFFT,
       integral,
       inner,
       l2norm,
       lpnorm,
       radial_spectrum,
       radial_correlation


function __init__()
  Fields._init_fft_threads()
end


end # module GBGPeriodicFields