module Fields

using AbstractFFTs
using LinearAlgebra
import FFTW

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




#########################################
#        FFT Auxiliary Functions        #
#########################################

"""
    rfft_shape(grid_size::NTuple{3, Int}, fft_dims::NTuple{3, Int})

Return the shape of the nonredundant real-to-complex Fourier representation of a three-dimensional real field.

Here `grid_size` is the physical grid size and `fft_dims` is the order of transformed dimensions. The dimension `fft_dims[1]` is the real-FFT half
dimension: it is stored with length `grid_size[fft_dims[1]] ÷ 2 + 1`, while the other dimensions keep their physical-grid lengths.

Returns a three-tuple giving the spectral array size.
"""
rfft_shape(grid_size::NTuple{3, Int}, fft_dims::NTuple{3, Int}) = ntuple(d -> d == fft_dims[1] ? (grid_size[d] ÷ 2 + 1) : grid_size[d], 3)




###############################
#        Domain Layout        #
###############################

"""
    validate_fft_dims(d::NTuple{3, Int})

Check whether `d` is a valid ordering of the three spatial Fourier-transform dimensions. Returns `true` or `false`.
"""
validate_fft_dims(d::NTuple{3, Int}) = (1 ≤ d[1] ≤ 3) && (1 ≤ d[2] ≤ 3) && (1 ≤ d[3] ≤ 3) && (d[1] != d[2]) && (d[1] != d[3]) && (d[2] != d[3])


"""
    Grid3D(grid_size::NTuple{3, Int}, domain_size::NTuple{3, T}, grid_spacing::NTuple{3, T}, origin::NTuple{3, T}) where {T<:AbstractFloat}
    Grid3D(grid_size::NTuple{3, Int}, domain_size::NTuple{3, T}; origin::NTuple{3, T} = (zero(T), zero(T), zero(T))) where {T<:AbstractFloat}

Uniform three-dimensional grid for a periodic rectangular domain.

The fields are
- `grid_size::NTuple{3, Int}`: the number of grid points in each spatial direction.
- `domain_size::NTuple{3, T}`: the length of the domain in each spatial direction.
- `grid_spacing::NTuple{3, T}`: the spacing between adjacent grid points in each spatial direction.
- `origin::NTuple{3, T}`: the physical coordinates of the first grid point.

The two-argument constructor computes `grid_spacing = domain_size ./ grid_size`.
"""
struct Grid3D{T<:AbstractFloat}
  grid_size::NTuple{3, Int}
  domain_size::NTuple{3, T}
  grid_spacing::NTuple{3, T}
  origin::NTuple{3, T}
end


function Grid3D(grid_size::NTuple{3, Int}, domain_size::NTuple{3, T}; origin::NTuple{3, T} = (zero(T), zero(T), zero(T))) where {T<:AbstractFloat}
  grid_spacing = domain_size ./ T.(grid_size)
  return Grid3D(grid_size, domain_size, grid_spacing, origin)
end


"""
    RealFourierLayout()
    RealFourierLayout(fft_dims::NTuple{3, Int})

Layout convention for three-dimensional real-to-complex Fourier transforms.

Here `fft_dims` is the tuple of transformed dimensions passed to the FFT planner. The main role of the ordering is to specify the real-FFT half dimension:
in dimension `fft_dims[1]`, only the nonnegative frequencies are represented, while the other dimensions use the full complex FFT frequency ordering.

The zero-argument constructor uses `fft_dims = (1, 2, 3)`.
"""
struct RealFourierLayout
  fft_dims::NTuple{3, Int}
  
  function RealFourierLayout(fft_dims::NTuple{3, Int} = (1, 2, 3))
    validate_fft_dims(fft_dims) || throw(ArgumentError("fft_dims must be a permutation of (1, 2, 3), got $(fft_dims)"))
    return new(fft_dims)
  end
end




######################################
#        Abstract Field Types        #
######################################

"""
    AbstractFieldPhysical{T, R}
    AbstractFieldSpectral{T, R}

Abstract supertypes for fields represented in physical space and spectral space.

Here `T<:AbstractFloat` is the real scalar type associated with the field, and `R` is the tensor order stored as an integer value parameter:
`R = 0` for scalar fields, `R = 1` for vector fields, `R = 2` for second-order tensor fields, and higher values for higher-order tensor fields.

Concrete subtypes provide the actual storage and metadata. The generic field interface obtains `T` and `R` through [`field_scalar_type`](@ref)
and [`field_tensor_order`](@ref); concrete subtypes should provide access to their stored data through [`field_data`](@ref).
"""
abstract type AbstractFieldPhysical{T<:AbstractFloat, R} end
abstract type AbstractFieldSpectral{T<:AbstractFloat, R} end


const AbstractField = Union{AbstractFieldPhysical, AbstractFieldSpectral}


"""
    field_scalar_type(field::AbstractFieldPhysical{T, R}) where {T<:AbstractFloat, R}
    field_scalar_type(field::AbstractFieldSpectral{T, R}) where {T<:AbstractFloat, R}

Return the real scalar type `T` associated with a field.
"""
field_scalar_type(::AbstractFieldPhysical{T, R}) where {T<:AbstractFloat, R} = T
field_scalar_type(::AbstractFieldSpectral{T, R}) where {T<:AbstractFloat, R} = T


"""
    field_tensor_order(field::AbstractFieldPhysical{T, R}) where {T<:AbstractFloat, R}
    field_tensor_order(field::AbstractFieldSpectral{T, R}) where {T<:AbstractFloat, R}

Return the tensor order `R` of a field.
"""
field_tensor_order(::AbstractFieldPhysical{T, R}) where {T<:AbstractFloat, R} = R
field_tensor_order(::AbstractFieldSpectral{T, R}) where {T<:AbstractFloat, R} = R


"""
    fiber_shape(::Val{R}) where {R}

Return the tensor-fiber shape associated with tensor order `R`.

For scalar fields, `R = 0` gives `()`. For higher tensor orders, each tensor index has length `3`,
so `R = 1` gives `(3,)`, `R = 2` gives `(3, 3)`, and so on.
"""
fiber_shape(::Val{0}) = ()
fiber_shape(::Val{R}) where {R} = ntuple(_ -> 3, Val(R))


"""
    physical_field_shape(grid::Grid3D, ::Val{R}) where {R}

Return the storage shape of a field of tensor order `R` represented in physical space on `grid`.
"""
physical_field_shape(grid::Grid3D, ::Val{R}) where {R} = (grid.grid_size..., fiber_shape(Val(R))...)


"""
    spectral_field_shape(grid::Grid3D, fourier_layout::RealFourierLayout, ::Val{R}) where {R}

Return the storage shape of a field of tensor order `R` represented in nonredundant real-to-complex spectral space.
"""
spectral_field_shape(grid::Grid3D, fourier_layout::RealFourierLayout, ::Val{R}) where {R} = (rfft_shape(grid.grid_size, fourier_layout.fft_dims)..., fiber_shape(Val(R))...)


"""
    field_grid(field::AbstractField)

Return the [`Grid3D`](@ref) associated with a field.
"""
field_grid(field::AbstractField) = field.grid


"""
    field_layout(field::AbstractField)

Return the [`RealFourierLayout`](@ref) associated with a field.
"""
field_layout(field::AbstractField) = field.fourier_layout


"""
    field_data(field::AbstractField)

Return the array storing the field data.

For fields represented in physical space, this is the array of values on the grid. For fields represented in spectral space,
this is the array of Fourier coefficients.
"""
function field_data end




####################################
#        Scalar Field Types        #
####################################

"""
    ScalarFieldPhysical(values_at_grid::AbstractArray{T, 3}, grid::Grid3D{T}, fourier_layout::RealFourierLayout) where {T<:AbstractFloat}
    ScalarFieldPhysical(values_at_grid::AbstractArray{T, 3}, grid::Grid3D{T}) where {T<:AbstractFloat}

Scalar field stored as its values on a three-dimensional physical grid.

Here `values_at_grid` contains the real scalar values, `grid` is the [`Grid3D`](@ref)
on which the values are sampled, and `fourier_layout` is the [`RealFourierLayout`](@ref) used when transforming the field.

Broadcasting over physical scalar fields is lifted to `values_at_grid`. Thus dotted assignments such as `@. destination = a - b + c`
write into `destination.values_at_grid`, while field-valued out-of-place dotted expressions return a new `ScalarFieldPhysical`.

The two-argument constructor uses the default `RealFourierLayout()` for the layout.
"""
struct ScalarFieldPhysical{T<:AbstractFloat, A<:AbstractArray{T, 3}, G<:Grid3D{T}, L<:RealFourierLayout} <: AbstractFieldPhysical{T, 0}
  values_at_grid::A
  grid::G
  fourier_layout::L

  function ScalarFieldPhysical(values_at_grid::A, grid::G, fourier_layout::L) where {T<:AbstractFloat, A<:AbstractArray{T, 3}, G<:Grid3D{T}, L<:RealFourierLayout}
    size(values_at_grid) == physical_field_shape(grid, Val(0)) || throw(DimensionMismatch("size(values_at_grid) must be equal to physical_field_shape(grid, Val(0))"))
    return new{T, A, G, L}(values_at_grid, grid, fourier_layout)
  end
end

ScalarFieldPhysical(values_at_grid::AbstractArray{T, 3}, grid::Grid3D{T}) where {T<:AbstractFloat} = ScalarFieldPhysical(values_at_grid, grid, RealFourierLayout())


"""
    ScalarFieldPhysical(f, grid::Grid3D{T}, fourier_layout::RealFourierLayout = RealFourierLayout(); array_type = Array) where {T<:AbstractFloat}

Construct a physical scalar field by sampling a real-valued function on a three-dimensional physical grid.

Here `f` is called as `f(x, y, z)`, `grid` is the [`Grid3D`](@ref) on which the values are sampled, `fourier_layout` is the [`RealFourierLayout`](@ref)
used when transforming the field, and `array_type` is the array type used to store the sampled values.

The two-argument constructor uses the default `RealFourierLayout()` for the layout.
"""
function ScalarFieldPhysical(f, grid::Grid3D{T}, fourier_layout::RealFourierLayout = RealFourierLayout(); array_type = Array) where {T<:AbstractFloat}
  values_at_grid = Array{T}(undef, physical_field_shape(grid, Val(0))...)

  Δx₁, Δx₂, Δx₃ = grid.grid_spacing
  x₀, y₀, z₀ = grid.origin

  for k in 1:grid.grid_size[3], j in 1:grid.grid_size[2], i in 1:grid.grid_size[1]
    values_at_grid[i, j, k] = T(f(x₀ + (i - 1) * Δx₁, y₀ + (j - 1) * Δx₂, z₀ + (k - 1) * Δx₃))
  end

  values_at_grid = array_type === Array ? values_at_grid : array_type(values_at_grid)

  return ScalarFieldPhysical(values_at_grid, grid, fourier_layout)
end


"""
    ScalarFieldSpectral(fourier_coefficients::AbstractArray{Complex{T}, 3}, grid::Grid3D{T}, fourier_layout::RealFourierLayout) where {T<:AbstractFloat}
    ScalarFieldSpectral(fourier_coefficients::AbstractArray{Complex{T}, 3}, grid::Grid3D{T}) where {T<:AbstractFloat}

Scalar field stored as its nonredundant real-to-complex Fourier coefficients.

Here `fourier_coefficients` contains the complex Fourier coefficients in real-FFT storage, `grid` is the [`Grid3D`](@ref)
associated with the physical domain, and `fourier_layout` is the [`RealFourierLayout`](@ref) specifying the transformed dimensions and the real-FFT half dimension.

The coefficient array has shape `spectral_field_shape(grid, fourier_layout, Val(0))`.
The dimension `fourier_layout.fft_dims[1]` is the real-FFT half dimension.

Broadcasting over spectral scalar fields is lifted to `fourier_coefficients`. Thus dotted assignments such as `@. destination = a - b + c`
write into `destination.fourier_coefficients`, while field-valued out-of-place dotted expressions return a new `ScalarFieldSpectral`.
All such operations are coefficientwise; for example, `.*` does not represent a pseudospectral product of scalar fields.

The two-argument constructor uses the default `RealFourierLayout()` for the layout.
"""
struct ScalarFieldSpectral{T<:AbstractFloat, Â<:AbstractArray{Complex{T}, 3}, G<:Grid3D{T}, L<:RealFourierLayout} <: AbstractFieldSpectral{T, 0}
  fourier_coefficients::Â
  grid::G
  fourier_layout::L

  function ScalarFieldSpectral(fourier_coefficients::Â, grid::G, fourier_layout::L) where {T<:AbstractFloat, Â<:AbstractArray{Complex{T}, 3}, G<:Grid3D{T}, L<:RealFourierLayout}
    size(fourier_coefficients) == spectral_field_shape(grid, fourier_layout, Val(0)) || throw(DimensionMismatch("size(fourier_coefficients) must be equal to spectral_field_shape(grid, fourier_layout, Val(0))"))
    return new{T, Â, G, L}(fourier_coefficients, grid, fourier_layout)
  end
end

ScalarFieldSpectral(fourier_coefficients::AbstractArray{Complex{T}, 3}, grid::Grid3D{T}) where {T<:AbstractFloat} = ScalarFieldSpectral(fourier_coefficients, grid, RealFourierLayout())


field_data(field::ScalarFieldPhysical) = field.values_at_grid
field_data(field::ScalarFieldSpectral) = field.fourier_coefficients




####################################
#        Vector Field Types        #
####################################

"""
    VectorFieldPhysical(values_at_grid::AbstractArray{T, 4}, grid::Grid3D{T}, fourier_layout::RealFourierLayout) where {T<:AbstractFloat}
    VectorFieldPhysical(values_at_grid::AbstractArray{T, 4}, grid::Grid3D{T}) where {T<:AbstractFloat}

Vector field stored as its components on a three-dimensional physical grid.

Here `values_at_grid` contains the real vector components with storage order `values_at_grid[i, j, k, α]`, where `α = 1, 2, 3`,
`grid` is the [`Grid3D`](@ref) on which the values are sampled, and `fourier_layout` is the [`RealFourierLayout`](@ref) used when transforming the field.

Broadcasting over physical vector fields is lifted to `values_at_grid`. Thus dotted assignments such as `@. destination = a - b + c`
write into `destination.values_at_grid`, while field-valued out-of-place dotted expressions return a new `VectorFieldPhysical`.
These operations are storage-wise and componentwise.

The two-argument constructor uses the default `RealFourierLayout()` for the layout.
"""
struct VectorFieldPhysical{T<:AbstractFloat, A<:AbstractArray{T, 4}, G<:Grid3D{T}, L<:RealFourierLayout} <: AbstractFieldPhysical{T, 1}
  values_at_grid::A
  grid::G
  fourier_layout::L

  function VectorFieldPhysical(values_at_grid::A, grid::G, fourier_layout::L) where {T<:AbstractFloat, A<:AbstractArray{T, 4}, G<:Grid3D{T}, L<:RealFourierLayout}
    size(values_at_grid) == physical_field_shape(grid, Val(1)) || throw(DimensionMismatch("size(values_at_grid) must be equal to physical_field_shape(grid, Val(1))"))
    return new{T, A, G, L}(values_at_grid, grid, fourier_layout)
  end
end

VectorFieldPhysical(values_at_grid::AbstractArray{T, 4}, grid::Grid3D{T}) where {T<:AbstractFloat} = VectorFieldPhysical(values_at_grid, grid, RealFourierLayout())


"""
    VectorFieldPhysical(f, grid::Grid3D{T}, fourier_layout::RealFourierLayout = RealFourierLayout(); array_type = Array) where {T<:AbstractFloat}

Construct a physical vector field by sampling a real vector-valued function on a three-dimensional physical grid.

Here `f` is called as `f(x, y, z)` and must return a three-component indexable object, `grid` is the [`Grid3D`](@ref) on which the values are sampled,
`fourier_layout` is the [`RealFourierLayout`](@ref) used when transforming the field, and `array_type` is the array type used to store the sampled values.

The two-argument constructor uses the default `RealFourierLayout()` for the layout.
"""
function VectorFieldPhysical(f, grid::Grid3D{T}, fourier_layout::RealFourierLayout = RealFourierLayout(); array_type = Array) where {T<:AbstractFloat}
  values_at_grid = Array{T}(undef, physical_field_shape(grid, Val(1))...)

  Δx₁, Δx₂, Δx₃ = grid.grid_spacing
  x₀, y₀, z₀ = grid.origin

  for k in 1:grid.grid_size[3], j in 1:grid.grid_size[2], i in 1:grid.grid_size[1]
    vector_value = f(x₀ + (i - 1) * Δx₁, y₀ + (j - 1) * Δx₂, z₀ + (k - 1) * Δx₃)

    for α in 1:3
      values_at_grid[i, j, k, α] = T(vector_value[α])
    end
  end

  values_at_grid = array_type === Array ? values_at_grid : array_type(values_at_grid)

  return VectorFieldPhysical(values_at_grid, grid, fourier_layout)
end


"""
    VectorFieldSpectral(fourier_coefficients::AbstractArray{Complex{T}, 4}, grid::Grid3D{T}, fourier_layout::RealFourierLayout) where {T<:AbstractFloat}
    VectorFieldSpectral(fourier_coefficients::AbstractArray{Complex{T}, 4}, grid::Grid3D{T}) where {T<:AbstractFloat}

Vector field stored as its nonredundant real-to-complex Fourier coefficients.

Here `fourier_coefficients` contains the complex vector Fourier coefficients in real-FFT storage, with the component index last:
`fourier_coefficients[i, j, k, α]`, where `α = 1, 2, 3`. The spatial part has shape
`spectral_field_shape(grid, fourier_layout, Val(0))`, and the full array has shape `spectral_field_shape(grid, fourier_layout, Val(1))`.
The dimension `fourier_layout.fft_dims[1]` is the real-FFT half dimension.

Broadcasting over spectral vector fields is lifted to `fourier_coefficients`. Thus dotted assignments such as `@. destination = a - b + c`
write into `destination.fourier_coefficients`, while field-valued out-of-place dotted expressions return a new `VectorFieldSpectral`.
These operations are storage-wise and componentwise. They do not represent pseudospectral products or tensor contractions.

The two-argument constructor uses the default `RealFourierLayout()` for the layout.
"""
struct VectorFieldSpectral{T<:AbstractFloat, Â<:AbstractArray{Complex{T}, 4}, G<:Grid3D{T}, L<:RealFourierLayout} <: AbstractFieldSpectral{T, 1}
  fourier_coefficients::Â
  grid::G
  fourier_layout::L

  function VectorFieldSpectral(fourier_coefficients::Â, grid::G, fourier_layout::L) where {T<:AbstractFloat, Â<:AbstractArray{Complex{T}, 4}, G<:Grid3D{T}, L<:RealFourierLayout}
    size(fourier_coefficients) == spectral_field_shape(grid, fourier_layout, Val(1)) || throw(DimensionMismatch("size(fourier_coefficients) must be equal to spectral_field_shape(grid, fourier_layout, Val(1))"))
    return new{T, Â, G, L}(fourier_coefficients, grid, fourier_layout)
  end
end

VectorFieldSpectral(fourier_coefficients::AbstractArray{Complex{T}, 4}, grid::Grid3D{T}) where {T<:AbstractFloat} = VectorFieldSpectral(fourier_coefficients, grid, RealFourierLayout())


field_data(field::VectorFieldPhysical) = field.values_at_grid
field_data(field::VectorFieldSpectral) = field.fourier_coefficients




####################################
#        Tensor Field Types        #
####################################


"""
    TensorFieldPhysical{R}(values_at_grid::AbstractArray{T}, grid::Grid3D{T}, fourier_layout::RealFourierLayout) where {R, T<:AbstractFloat}
    TensorFieldPhysical{R}(values_at_grid::AbstractArray{T}, grid::Grid3D{T}) where {R, T<:AbstractFloat}
    TensorFieldPhysical(values_at_grid::AbstractArray{T, N}, grid::Grid3D{T}, fourier_layout::RealFourierLayout) where {T<:AbstractFloat, N}
    TensorFieldPhysical(values_at_grid::AbstractArray{T, N}, grid::Grid3D{T}) where {T<:AbstractFloat, N}

Tensor field of order `R ≥ 2` stored as its components on a three-dimensional physical grid.

Here `values_at_grid` contains the real tensor components with storage order `values_at_grid[i, j, k, α₁, ..., αᵣ]`,
where each tensor index has length `3`, `grid` is the [`Grid3D`](@ref) on which the values are sampled,
and `fourier_layout` is the [`RealFourierLayout`](@ref) used when transforming the field.

The array has shape `physical_field_shape(grid, Val(R))`.
The constructors without explicit `{R}` infer `R = N - 3` from the array dimension `N`.

Broadcasting over physical tensor fields is lifted to `values_at_grid`. Thus dotted assignments such as `@. destination = a - b + c`
write into `destination.values_at_grid`, while field-valued out-of-place dotted expressions return a new `TensorFieldPhysical`.
These operations are storage-wise and componentwise. They do not represent tensor contractions.

The two-argument constructors use the default `RealFourierLayout()` for the layout.
"""
struct TensorFieldPhysical{R, T<:AbstractFloat, A<:AbstractArray{T}, G<:Grid3D{T}, L<:RealFourierLayout} <: AbstractFieldPhysical{T, R}
  values_at_grid::A
  grid::G
  fourier_layout::L

  function TensorFieldPhysical{R}(values_at_grid::A, grid::G, fourier_layout::L) where {R, T<:AbstractFloat, A<:AbstractArray{T}, G<:Grid3D{T}, L<:RealFourierLayout}
    (R isa Integer && R ≥ 2) || throw(ArgumentError("tensor order R must be an integer at least 2"))
    size(values_at_grid) == physical_field_shape(grid, Val(R)) || throw(DimensionMismatch("size(values_at_grid) must be equal to physical_field_shape(grid, Val(R))"))
    return new{R, T, A, G, L}(values_at_grid, grid, fourier_layout)
  end
end

TensorFieldPhysical{R}(values_at_grid::AbstractArray{T}, grid::Grid3D{T}) where {R, T<:AbstractFloat} =
  TensorFieldPhysical{R}(values_at_grid, grid, RealFourierLayout())

TensorFieldPhysical(values_at_grid::AbstractArray{T, N}, grid::Grid3D{T}, fourier_layout::RealFourierLayout) where {T<:AbstractFloat, N} =
  TensorFieldPhysical{N - 3}(values_at_grid, grid, fourier_layout)

TensorFieldPhysical(values_at_grid::AbstractArray{T, N}, grid::Grid3D{T}) where {T<:AbstractFloat, N} =
  TensorFieldPhysical(values_at_grid, grid, RealFourierLayout())


"""
    TensorFieldPhysical{R}(f, grid::Grid3D{T}, fourier_layout::RealFourierLayout = RealFourierLayout(); array_type = Array) where {R, T<:AbstractFloat}

Construct a physical tensor field of order `R ≥ 2` by sampling a real tensor-valued function on a three-dimensional physical grid.

Here `f` is called as `f(x, y, z)` and must return an indexable object with tensor-fiber shape `fiber_shape(Val(R))`,
`grid` is the [`Grid3D`](@ref) on which the values are sampled, `fourier_layout` is the [`RealFourierLayout`](@ref)
used when transforming the field, and `array_type` is the array type used to store the sampled values.

The two-argument constructor uses the default `RealFourierLayout()` for the layout.
"""
function TensorFieldPhysical{R}(f, grid::Grid3D{T}, fourier_layout::RealFourierLayout = RealFourierLayout(); array_type = Array) where {R, T<:AbstractFloat}
  (R isa Integer && R ≥ 2) || throw(ArgumentError("tensor order R must be an integer at least 2"))

  values_at_grid = Array{T}(undef, physical_field_shape(grid, Val(R))...)

  Δx₁, Δx₂, Δx₃ = grid.grid_spacing
  x₀, y₀, z₀ = grid.origin

  for k in 1:grid.grid_size[3], j in 1:grid.grid_size[2], i in 1:grid.grid_size[1]
    tensor_value = f(x₀ + (i - 1) * Δx₁, y₀ + (j - 1) * Δx₂, z₀ + (k - 1) * Δx₃)

    for tensor_index in CartesianIndices(fiber_shape(Val(R)))
      values_at_grid[i, j, k, Tuple(tensor_index)...] = T(tensor_value[Tuple(tensor_index)...])
    end
  end

  values_at_grid = array_type === Array ? values_at_grid : array_type(values_at_grid)

  return TensorFieldPhysical{R}(values_at_grid, grid, fourier_layout)
end


"""
    TensorFieldSpectral{R}(fourier_coefficients::AbstractArray{Complex{T}}, grid::Grid3D{T}, fourier_layout::RealFourierLayout) where {R, T<:AbstractFloat}
    TensorFieldSpectral{R}(fourier_coefficients::AbstractArray{Complex{T}}, grid::Grid3D{T}) where {R, T<:AbstractFloat}
    TensorFieldSpectral(fourier_coefficients::AbstractArray{Complex{T}, N}, grid::Grid3D{T}, fourier_layout::RealFourierLayout) where {T<:AbstractFloat, N}
    TensorFieldSpectral(fourier_coefficients::AbstractArray{Complex{T}, N}, grid::Grid3D{T}) where {T<:AbstractFloat, N}

Tensor field of order `R ≥ 2` stored as its nonredundant real-to-complex Fourier coefficients.

Here `fourier_coefficients` contains the complex tensor Fourier coefficients in real-FFT storage, with the tensor indices last:
`fourier_coefficients[i, j, k, α₁, ..., αᵣ]`, where each tensor index has length `3`. The spatial part has shape
`spectral_field_shape(grid, fourier_layout, Val(0))`, and the full array has shape `spectral_field_shape(grid, fourier_layout, Val(R))`.
The dimension `fourier_layout.fft_dims[1]` is the real-FFT half dimension.

Broadcasting over spectral tensor fields is lifted to `fourier_coefficients`. Thus dotted assignments such as `@. destination = a - b + c`
write into `destination.fourier_coefficients`, while field-valued out-of-place dotted expressions return a new `TensorFieldSpectral`.
These operations are storage-wise and componentwise. They do not represent pseudospectral products or tensor contractions.

The two-argument constructors use the default `RealFourierLayout()` for the layout.
"""
struct TensorFieldSpectral{R, T<:AbstractFloat, Â<:AbstractArray{Complex{T}}, G<:Grid3D{T}, L<:RealFourierLayout} <: AbstractFieldSpectral{T, R}
  fourier_coefficients::Â
  grid::G
  fourier_layout::L

  function TensorFieldSpectral{R}(fourier_coefficients::Â, grid::G, fourier_layout::L) where {R, T<:AbstractFloat, Â<:AbstractArray{Complex{T}}, G<:Grid3D{T}, L<:RealFourierLayout}
    (R isa Integer && R ≥ 2) || throw(ArgumentError("tensor order R must be an integer at least 2"))
    size(fourier_coefficients) == spectral_field_shape(grid, fourier_layout, Val(R)) || throw(DimensionMismatch("size(fourier_coefficients) must be equal to spectral_field_shape(grid, fourier_layout, Val(R))"))
    return new{R, T, Â, G, L}(fourier_coefficients, grid, fourier_layout)
  end
end

TensorFieldSpectral{R}(fourier_coefficients::AbstractArray{Complex{T}}, grid::Grid3D{T}) where {R, T<:AbstractFloat} =
  TensorFieldSpectral{R}(fourier_coefficients, grid, RealFourierLayout())

TensorFieldSpectral(fourier_coefficients::AbstractArray{Complex{T}, N}, grid::Grid3D{T}, fourier_layout::RealFourierLayout) where {T<:AbstractFloat, N} =
  TensorFieldSpectral{N - 3}(fourier_coefficients, grid, fourier_layout)

TensorFieldSpectral(fourier_coefficients::AbstractArray{Complex{T}, N}, grid::Grid3D{T}) where {T<:AbstractFloat, N} =
  TensorFieldSpectral(fourier_coefficients, grid, RealFourierLayout())


field_data(field::TensorFieldPhysical) = field.values_at_grid
field_data(field::TensorFieldSpectral) = field.fourier_coefficients




##################################
#        Field Transforms        #
##################################

"""
    FieldTransforms(physical::AbstractFieldPhysical{T, R}, spectral::AbstractFieldSpectral{T, R}; fft_flags = nothing, fft_timelimit = Inf) where {T<:AbstractFloat, R}

Forward and inverse FFT plans connecting compatible fields represented in physical and spectral space.

Here `physical` provides the real-space storage array, `spectral` provides the real-to-complex Fourier coefficient array,
`fft_flags` is an optional backend-specific FFT planner flag, and `fft_timelimit` is the planner time limit used when `fft_flags` is provided.
Only the spatial dimensions `field_layout(physical).fft_dims` are transformed; tensor-fiber dimensions are left untransformed.

The fields are
- `grid::G`: the [`Grid3D`](@ref) for which the plans were constructed.
- `fourier_layout::L`: the [`RealFourierLayout`](@ref) for which the plans were constructed.
- `plan_forward_fft::PF`: the plan transforming physical values to spectral coefficients.
- `plan_inverse_fft::PI`: the plan transforming spectral coefficients to physical values.

The plans are backend-, array-type-, scalar-type-, and tensor-order-specific; construct a separate `FieldTransforms` object for each CPU/GPU backend and field tensor order.
"""
struct FieldTransforms{T<:AbstractFloat, R, PF, PI, G<:Grid3D{T}, L<:RealFourierLayout}
  grid::G
  fourier_layout::L
  plan_forward_fft::PF
  plan_inverse_fft::PI
end


function FieldTransforms(physical::AbstractFieldPhysical{T, R}, spectral::AbstractFieldSpectral{T, R}; fft_flags = nothing, fft_timelimit = Inf) where {T<:AbstractFloat, R}
  field_grid(physical) == field_grid(spectral) || throw(ArgumentError("field grids must be equal"))
  field_layout(physical) == field_layout(spectral) || throw(ArgumentError("field Fourier layouts must be equal"))

  fft_dims = field_layout(physical).fft_dims

  plan_forward_fft =
    isnothing(fft_flags) ? plan_rfft(field_data(physical), fft_dims) :
    plan_rfft(field_data(physical), fft_dims; flags = fft_flags, timelimit = fft_timelimit)

  plan_inverse_fft =
    isnothing(fft_flags) ? plan_irfft(field_data(spectral), field_grid(physical).grid_size[fft_dims[1]], fft_dims) :
    plan_irfft(field_data(spectral), field_grid(physical).grid_size[fft_dims[1]], fft_dims; flags = fft_flags, timelimit = fft_timelimit)

  return FieldTransforms{T, R, typeof(plan_forward_fft), typeof(plan_inverse_fft), typeof(field_grid(physical)), typeof(field_layout(physical))}(
    field_grid(physical), field_layout(physical), plan_forward_fft, plan_inverse_fft)
end


"""
    to_physical!(physical::AbstractFieldPhysical{T, R}, spectral::AbstractFieldSpectral{T, R}, transforms::FieldTransforms{T, R}) where {T<:AbstractFloat, R}

Transform a field from spectral space to physical space in-place.

Here `physical` is the destination, `spectral` is the source, and `transforms` provides the inverse FFT plan.

Returns the modified `physical` field.
"""
function to_physical!(physical::AbstractFieldPhysical{T, R}, spectral::AbstractFieldSpectral{T, R}, transforms::FieldTransforms{T, R}) where {T<:AbstractFloat, R}
  field_grid(physical) == field_grid(spectral) || throw(ArgumentError("field grids must be equal"))
  field_grid(physical) == transforms.grid || throw(ArgumentError("field grid must be equal to transforms.grid"))
  field_layout(physical) == field_layout(spectral) || throw(ArgumentError("field Fourier layouts must be equal"))
  field_layout(physical) == transforms.fourier_layout || throw(ArgumentError("field Fourier layout must be equal to transforms.fourier_layout"))

  mul!(field_data(physical), transforms.plan_inverse_fft, field_data(spectral))

  return physical
end


"""
    to_spectral!(spectral::AbstractFieldSpectral{T, R}, physical::AbstractFieldPhysical{T, R}, transforms::FieldTransforms{T, R}) where {T<:AbstractFloat, R}

Transform a field from physical space to spectral space in-place.

Here `spectral` is the destination, `physical` is the source, and `transforms` provides the forward FFT plan.

Returns the modified `spectral` field.
"""
function to_spectral!(spectral::AbstractFieldSpectral{T, R}, physical::AbstractFieldPhysical{T, R}, transforms::FieldTransforms{T, R}) where {T<:AbstractFloat, R}
  field_grid(spectral) == field_grid(physical) || throw(ArgumentError("field grids must be equal"))
  field_grid(spectral) == transforms.grid || throw(ArgumentError("field grid must be equal to transforms.grid"))
  field_layout(spectral) == field_layout(physical) || throw(ArgumentError("field Fourier layouts must be equal"))
  field_layout(spectral) == transforms.fourier_layout || throw(ArgumentError("field Fourier layout must be equal to transforms.fourier_layout"))

  mul!(field_data(spectral), transforms.plan_forward_fft, field_data(physical))

  return spectral
end


"""
    similar_physical_field(reference::AbstractFieldSpectral, data)

Construct a field represented in physical space with storage array `data` and metadata copied from the spectral-space `reference`.
"""
similar_physical_field(reference::ScalarFieldSpectral, data) = ScalarFieldPhysical(data, field_grid(reference), field_layout(reference))
similar_physical_field(reference::VectorFieldSpectral, data) = VectorFieldPhysical(data, field_grid(reference), field_layout(reference))
similar_physical_field(reference::TensorFieldSpectral{R}, data) where {R} = TensorFieldPhysical{R}(data, field_grid(reference), field_layout(reference))


"""
    similar_spectral_field(reference::AbstractFieldPhysical, data)

Construct a field represented in spectral space with storage array `data` and metadata copied from the physical-space `reference`.
"""
similar_spectral_field(reference::ScalarFieldPhysical, data) = ScalarFieldSpectral(data, field_grid(reference), field_layout(reference))
similar_spectral_field(reference::VectorFieldPhysical, data) = VectorFieldSpectral(data, field_grid(reference), field_layout(reference))
similar_spectral_field(reference::TensorFieldPhysical{R}, data) where {R} = TensorFieldSpectral{R}(data, field_grid(reference), field_layout(reference))


"""
    to_physical(spectral::AbstractFieldSpectral{T, R}, transforms::FieldTransforms{T, R}) where {T<:AbstractFloat, R}

Allocating version of [`to_physical!`](@ref).
"""
function to_physical(spectral::AbstractFieldSpectral{T, R}, transforms::FieldTransforms{T, R}) where {T<:AbstractFloat, R}
  values_at_grid = similar(field_data(spectral), T, physical_field_shape(field_grid(spectral), Val(R)))
  physical = similar_physical_field(spectral, values_at_grid)

  return to_physical!(physical, spectral, transforms)
end


"""
    to_spectral(physical::AbstractFieldPhysical{T, R}, transforms::FieldTransforms{T, R}) where {T<:AbstractFloat, R}

Allocating version of [`to_spectral!`](@ref).
"""
function to_spectral(physical::AbstractFieldPhysical{T, R}, transforms::FieldTransforms{T, R}) where {T<:AbstractFloat, R}
  fourier_coefficients = similar(field_data(physical), Complex{T}, spectral_field_shape(field_grid(physical), field_layout(physical), Val(R)))
  spectral = similar_spectral_field(physical, fourier_coefficients)

  return to_spectral!(spectral, physical, transforms)
end




##############################
#        Broadcasting        #
##############################


"""
    similar_field(reference::AbstractField, data)

Construct a field with storage array `data` and metadata copied from `reference`.

This is used by out-of-place field broadcasting.
"""
similar_field(reference::ScalarFieldPhysical, data) = ScalarFieldPhysical(data, field_grid(reference), field_layout(reference))
similar_field(reference::ScalarFieldSpectral, data) = ScalarFieldSpectral(data, field_grid(reference), field_layout(reference))
similar_field(reference::VectorFieldPhysical, data) = VectorFieldPhysical(data, field_grid(reference), field_layout(reference))
similar_field(reference::VectorFieldSpectral, data) = VectorFieldSpectral(data, field_grid(reference), field_layout(reference))
similar_field(reference::TensorFieldPhysical{R}, data) where {R} = TensorFieldPhysical{R}(data, field_grid(reference), field_layout(reference))
similar_field(reference::TensorFieldSpectral{R}, data) where {R} = TensorFieldSpectral{R}(data, field_grid(reference), field_layout(reference))


"""
    check_field_compatibility(a::AbstractFieldPhysical, b::AbstractFieldPhysical)
    check_field_compatibility(a::AbstractFieldSpectral, b::AbstractFieldSpectral)

Check that two fields with the same representation have the same scalar type, tensor order, grid, and Fourier layout.

Returns `nothing` or throws an exception.
"""
function check_field_compatibility(a::AbstractFieldPhysical, b::AbstractFieldPhysical)
  field_scalar_type(a) == field_scalar_type(b) || throw(ArgumentError("field scalar types must be equal"))
  field_tensor_order(a) == field_tensor_order(b) || throw(ArgumentError("field tensor orders must be equal"))
  field_grid(a) == field_grid(b) || throw(ArgumentError("field grids must be equal"))
  field_layout(a) == field_layout(b) || throw(ArgumentError("field Fourier layouts must be equal"))

  return nothing
end


function check_field_compatibility(a::AbstractFieldSpectral, b::AbstractFieldSpectral)
  field_scalar_type(a) == field_scalar_type(b) || throw(ArgumentError("field scalar types must be equal"))
  field_tensor_order(a) == field_tensor_order(b) || throw(ArgumentError("field tensor orders must be equal"))
  field_grid(a) == field_grid(b) || throw(ArgumentError("field grids must be equal"))
  field_layout(a) == field_layout(b) || throw(ArgumentError("field Fourier layouts must be equal"))

  return nothing
end


struct FieldPhysicalBroadcastStyle{N} <: Base.Broadcast.AbstractArrayStyle{N} end
struct FieldSpectralBroadcastStyle{N} <: Base.Broadcast.AbstractArrayStyle{N} end

(::Type{<:FieldPhysicalBroadcastStyle})(::Val{N}) where {N} = FieldPhysicalBroadcastStyle{N}()
(::Type{<:FieldSpectralBroadcastStyle})(::Val{N}) where {N} = FieldSpectralBroadcastStyle{N}()

Base.BroadcastStyle(::Type{<:AbstractFieldPhysical{T, R}}) where {T<:AbstractFloat, R} = FieldPhysicalBroadcastStyle{3 + R}()
Base.BroadcastStyle(::Type{<:AbstractFieldSpectral{T, R}}) where {T<:AbstractFloat, R} = FieldSpectralBroadcastStyle{3 + R}()

Base.BroadcastStyle(::FieldPhysicalBroadcastStyle{M}, ::FieldPhysicalBroadcastStyle{N}) where {M, N} = FieldPhysicalBroadcastStyle{max(M, N)}()
Base.BroadcastStyle(::FieldSpectralBroadcastStyle{M}, ::FieldSpectralBroadcastStyle{N}) where {M, N} = FieldSpectralBroadcastStyle{max(M, N)}()

Base.BroadcastStyle(::FieldPhysicalBroadcastStyle, ::FieldSpectralBroadcastStyle) =
  throw(ArgumentError("cannot broadcast fields represented in physical and spectral space together"))

Base.broadcastable(field::AbstractField) = field

Base.axes(field::AbstractField) = axes(field_data(field))
Base.size(field::AbstractField) = size(field_data(field))

Base.ndims(::Type{<:AbstractFieldPhysical{T, R}}) where {T<:AbstractFloat, R} = 3 + R
Base.ndims(::Type{<:AbstractFieldSpectral{T, R}}) where {T<:AbstractFloat, R} = 3 + R

Base.ndims(field::AbstractField) = ndims(field_data(field))

Base.eltype(::Type{<:AbstractFieldPhysical{T, R}}) where {T<:AbstractFloat, R} = T
Base.eltype(::Type{<:AbstractFieldSpectral{T, R}}) where {T<:AbstractFloat, R} = Complex{T}

Base.eltype(field::AbstractField) = eltype(field_data(field))

Base.getindex(field::AbstractField, indices...) = field_data(field)[indices...]

function Base.setindex!(field::AbstractField, value, indices...)
  setindex!(field_data(field), value, indices...)
  return field
end


_first_field(field::AbstractField) = field
_first_field(::Any) = nothing

_first_field(broadcasted::Base.Broadcast.Broadcasted) = _first_field(broadcasted.args)
_first_field(::Tuple{}) = nothing

function _first_field(args::Tuple)
  field = _first_field(first(args))
  return isnothing(field) ? _first_field(Base.tail(args)) : field
end


_check_broadcast_field_compatibility(destination::AbstractFieldPhysical, field::AbstractFieldPhysical) =
  check_field_compatibility(destination, field)

_check_broadcast_field_compatibility(destination::AbstractFieldSpectral, field::AbstractFieldSpectral) =
  check_field_compatibility(destination, field)

_check_broadcast_field_compatibility(::AbstractFieldPhysical, ::AbstractFieldSpectral) =
  throw(ArgumentError("cannot broadcast fields represented in physical and spectral space together"))

_check_broadcast_field_compatibility(::AbstractFieldSpectral, ::AbstractFieldPhysical) =
  throw(ArgumentError("cannot broadcast fields represented in spectral and physical space together"))

_check_broadcast_field_compatibility(::AbstractField, ::Any) =
  nothing

function _check_broadcast_field_compatibility(destination::AbstractField, broadcasted::Base.Broadcast.Broadcasted)
  foreach(argument -> _check_broadcast_field_compatibility(destination, argument), broadcasted.args)

  return nothing
end


_unwrap_broadcast_argument(field::AbstractField) = field_data(field)
_unwrap_broadcast_argument(argument) = argument

function _unwrap_broadcast_argument(broadcasted::Base.Broadcast.Broadcasted)
  return Base.Broadcast.broadcasted(broadcasted.f, map(_unwrap_broadcast_argument, broadcasted.args)...)
end


function Base.copyto!(destination::AbstractField, broadcasted::Base.Broadcast.Broadcasted)
  _check_broadcast_field_compatibility(destination, broadcasted)

  unwrapped = _unwrap_broadcast_argument(broadcasted)

  unwrapped_with_destination_axes =
    Base.Broadcast.Broadcasted(
      unwrapped.style,
      unwrapped.f,
      unwrapped.args,
      axes(field_data(destination)),
    )

  copyto!(field_data(destination), Base.Broadcast.instantiate(unwrapped_with_destination_axes))

  return destination
end


function Base.copy(broadcasted::Base.Broadcast.Broadcasted{<:FieldPhysicalBroadcastStyle})
  reference = _first_field(broadcasted)
  isnothing(reference) && throw(ArgumentError("broadcast expression does not contain a field represented in physical space"))

  destination = similar_field(reference, similar(field_data(reference)))

  return copyto!(destination, broadcasted)
end


function Base.copy(broadcasted::Base.Broadcast.Broadcasted{<:FieldSpectralBroadcastStyle})
  reference = _first_field(broadcasted)
  isnothing(reference) && throw(ArgumentError("broadcast expression does not contain a field represented in spectral space"))

  destination = similar_field(reference, similar(field_data(reference)))

  return copyto!(destination, broadcasted)
end

end # module Fields