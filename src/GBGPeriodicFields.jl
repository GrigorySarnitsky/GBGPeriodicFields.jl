# GBGPeriodicFields — umbrella module: it sets the include order and assembles the public API.
#
# The conceptual model (a field is a section of a trivial, flat tensor bundle; physical and
# spectral are representations of one object), the representation-validity rules, the FFT/Nyquist
# conventions, and the writing/docstring conventions are not duplicated here — they live in
# `docs/ARCHITECTURE.md` (the rationale) and `CLAUDE.md` (the operational rules).


"""
    GBGPeriodicFields

Tools for representing, transforming, and manipulating scalar, vector, and tensor fields on three-dimensional rectangular periodic domains.

The package is aimed primarily at fluid-dynamics and turbulence simulations, with physical-space and real-to-complex spectral representations
designed for both CPU and GPU array backends. It also targets Lagrangian particle simulations through interpolation tools for evaluating fields between grid nodes.

The package provides field representations and FFT transform plans, storage-wise broadcasting, the fiberwise algebra (`dot`, `cross`, `mul!`, …), spectral differential operators (`gradient`, `divergence`, `curl`, `laplacian`, `inverse_laplacian`, `helmholtz_projection`), periodic convolution (`convolve`, `spectral_cutoff`, …), the L²/measure reductions (`integral`, `inner`, `l2norm`, `radial_spectrum`, `radial_correlation`, …), and the grid↔point transfer (`interpolate`/`anterpolate`).
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