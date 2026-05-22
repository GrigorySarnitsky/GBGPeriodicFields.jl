"""
GBGPeriodicFields.jl provides tools for representing, transforming, and manipulating scalar, vector, and tensor fields on three-dimensional rectangular periodic domains.

The package is aimed primarily at fluid-dynamics and turbulence simulations, with physical-space and real-to-complex spectral representations
designed for both CPU and GPU array backends. It also targets Lagrangian particle simulations through interpolation tools for evaluating fields between grid nodes.
"""
module GBGPeriodicFields

export Grid3D,
       RealFourierLayout,
       AbstractFieldPhysical,
       AbstractFieldSpectral,
       ScalarFieldPhysical,
       ScalarFieldSpectral,
       VectorFieldPhysical,
       VectorFieldSpectral,
       TensorFieldPhysical,
       TensorFieldSpectral,
       FieldTransforms,
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
       spectral_field_shape

include("Fields.jl")
using .Fields


end # module GBGPeriodicFields