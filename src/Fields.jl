"""
    Fields

Field representation and transform core for scalar, vector, and second-order tensor fields on
three-dimensional rectangular periodic domains, for CPU and GPU array backends. A field is a physical
object, and the physical-space and spectral types (for example `ScalarFieldPhysical` and
`ScalarFieldSpectral`) are two representations of the **same** field.

This module provides the following.

  * **Grid and layout** — [`Grid3D`](@ref) describes the periodic domain geometry, and
    [`RealFourierLayout`](@ref) describes the real-to-complex transform layout.
  * **Fiber types** — [`FiberVector`](@ref), [`FiberTensor2`](@ref), [`FiberTensor3`](@ref), and
    [`FiberTensor4`](@ref) are `StaticArrays` aliases naming one individual tensor value of a given order.
  * **Field types** — the scalar, vector, and second-order tensor field types each come in a
    physical-space and a spectral representation (higher orders exist as `TensorFieldPhysical{R}` /
    `TensorFieldSpectral{R}`).
  * **Persistence** — [`write_field`](@ref) and [`read_field`](@ref) map a field to and from one
    self-describing HDF5 group (methods load with the `HDF5` package, as a weak-dependency extension).
  * **Transforms** — [`FieldTransformPlans`](@ref) holds the FFT plans, and [`to_physical`](@ref) and
    [`to_spectral`](@ref) move a field between the two representations. The allocating forms preserve
    their input, while the in-place `!` forms may overwrite the source; `set_fft_threads!` sets the
    thread count `FFTW` bakes into plans built afterwards.
  * **Spectral multipliers** — [`FieldSpectralMultipliers`](@ref) holds the wavenumber arrays that the
    spectral differential operators multiply by.
  * **Broadcasting** — a dotted assignment writes into the destination's storage, an out-of-place dotted
    expression allocates a like field in the same representation, and physical and spectral
    representations cannot be mixed in one broadcast.
"""
module Fields

using StaticArrays: SVector, SMatrix, SArray
using AbstractFFTs
using LinearAlgebra
import FFTW
using Base.ScopedValues: ScopedValue
using ..FiberSections: AbstractFiberSection, _assign!, _THREADING_OVERRIDE

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
       write_field,
       read_field,
       FieldTransformPlans,
       FieldSpectralMultipliers,
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
       set_fft_threads!




###################################
#        Fixed Fiber Types        #
###################################

"""
    FiberVector{T}

Static three-component Cartesian vector type used for individual vector values.

This is an alias for `SVector{3, T}`, with scalar type `T`.
"""
const FiberVector{T} = SVector{3, T}


"""
    FiberTensor2{T}

Static second-order Cartesian tensor type used for individual tensor values.

This is an alias for `SMatrix{3, 3, T, 9}`, with scalar type `T`.
"""
const FiberTensor2{T} = SMatrix{3, 3, T, 9}


"""
    FiberTensor3{T}

Static third-order Cartesian tensor type used for individual tensor values.

This is an alias for `SArray{Tuple{3, 3, 3}, T, 3, 27}`, with scalar type `T`.
"""
const FiberTensor3{T} = SArray{Tuple{3, 3, 3}, T, 3, 27}


"""
    FiberTensor4{T}

Static fourth-order Cartesian tensor type used for individual tensor values.

This is an alias for `SArray{Tuple{3, 3, 3, 3}, T, 4, 81}`, with scalar type `T`.
"""
const FiberTensor4{T} = SArray{Tuple{3, 3, 3, 3}, T, 4, 81}




#########################################
#        Domain and Fourier Layout      #
#########################################

"""
    validate_fft_dims(d::NTuple{3, Int})

Check whether `d` is a valid ordering of the three spatial Fourier-transform dimensions. Returns `true` or `false`.
"""
validate_fft_dims(d::NTuple{3, Int}) = (1 ≤ d[1] ≤ 3) && (1 ≤ d[2] ≤ 3) && (1 ≤ d[3] ≤ 3) && (d[1] != d[2]) && (d[1] != d[3]) && (d[2] != d[3])


"""
    Grid3D(
      grid_size::NTuple{3, Int},
      domain_size::NTuple{3, T},
      grid_spacing::NTuple{3, T},
      origin::NTuple{3, T},
    ) where {T<:AbstractFloat}

    Grid3D(
      grid_size::NTuple{3, Int},
      domain_size::NTuple{3, T};
      origin::NTuple{3, T} = (zero(T), zero(T), zero(T)),
    ) where {T<:AbstractFloat}

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


"""
    rfft_shape(grid_size::NTuple{3, Int}, fft_dims::NTuple{3, Int})

Return the shape of the nonredundant real-to-complex Fourier representation of a three-dimensional real field.

Here `grid_size` is the physical grid size and `fft_dims` is the order of transformed dimensions. The dimension `fft_dims[1]` is the real-FFT half
dimension: it is stored with length `grid_size[fft_dims[1]] ÷ 2 + 1`, while the other dimensions keep their physical-grid lengths.

Returns a three-tuple giving the spectral array size.
"""
rfft_shape(grid_size::NTuple{3, Int}, fft_dims::NTuple{3, Int}) = ntuple(d -> d == fft_dims[1] ? (grid_size[d] ÷ 2 + 1) : grid_size[d], 3)




########################################
#        Abstract Field Interface       #
########################################

"""
    AbstractFieldPhysical{T, R}

Abstract supertype for fields represented by values in physical space.

Here `T<:AbstractFloat` is the real scalar type associated with the field and `R` is the tensor order stored as an integer value parameter.
Concrete subtypes provide the actual storage and metadata. The generic field interface obtains `T` and `R` through [`field_scalar_type`](@ref)
and [`field_tensor_order`](@ref), and obtains the stored data through [`field_data`](@ref).
"""
abstract type AbstractFieldPhysical{T<:AbstractFloat, R} <: AbstractFiberSection{T, R} end


"""
    AbstractFieldSpectral{T, R}

Abstract supertype for fields represented by Fourier coefficients in spectral space.

Here `T<:AbstractFloat` is the real scalar type associated with the field and `R` is the tensor order stored as an integer value parameter.
Concrete subtypes provide the actual storage and metadata. The generic field interface obtains `T` and `R` through [`field_scalar_type`](@ref)
and [`field_tensor_order`](@ref), and obtains the stored data through [`field_data`](@ref).
"""
abstract type AbstractFieldSpectral{T<:AbstractFloat, R} <: AbstractFiberSection{T, R} end


"""
    AbstractField

Either representation of a field: the union of [`AbstractFieldPhysical`](@ref) and
[`AbstractFieldSpectral`](@ref).

It names the argument type of the operations that do not care which representation they are handed —
the grid, layout, element-type and tensor-order accessors, and the compatibility checks. An operation
valid in only one representation is typed with that representation instead, which is how the method
set encodes representation validity.
"""
const AbstractField = Union{AbstractFieldPhysical, AbstractFieldSpectral}


"""
    field_scalar_type(
      field::AbstractFieldPhysical{T, R},
    ) where {T<:AbstractFloat, R}

    field_scalar_type(
      field::AbstractFieldSpectral{T, R},
    ) where {T<:AbstractFloat, R}

Return the real scalar type `T` associated with a field.
"""
field_scalar_type(::AbstractFieldPhysical{T, R}) where {T<:AbstractFloat, R} = T
field_scalar_type(::AbstractFieldSpectral{T, R}) where {T<:AbstractFloat, R} = T


"""
    field_tensor_order(
      field::AbstractFieldPhysical{T, R},
    ) where {T<:AbstractFloat, R}

    field_tensor_order(
      field::AbstractFieldSpectral{T, R},
    ) where {T<:AbstractFloat, R}

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
    spectral_field_shape(
      grid::Grid3D,
      fourier_layout::RealFourierLayout,
      ::Val{R},
    ) where {R}

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
    ScalarFieldPhysical(
      values_at_grid::AbstractArray{T, 3},
      grid::Grid3D{T},
      fourier_layout::RealFourierLayout,
    ) where {T<:AbstractFloat}

    ScalarFieldPhysical(
      values_at_grid::AbstractArray{T, 3},
      grid::Grid3D{T},
    ) where {T<:AbstractFloat}

    ScalarFieldPhysical(
      f,
      grid::Grid3D{T},
      fourier_layout::RealFourierLayout = RealFourierLayout();
      array_type = Array,
    ) where {T<:AbstractFloat}

Scalar field in physical-space representation, stored as its values on a three-dimensional physical grid.

Here `values_at_grid` contains the real scalar values, `grid` is the [`Grid3D`](@ref)
on which the values are sampled, and `fourier_layout` is the [`RealFourierLayout`](@ref) used when transforming the field.

The function constructor constructs a scalar field in physical-space representation by sampling a real-valued function on a three-dimensional physical grid.
Here `f` is called as `f(x, y, z)`, `grid` is the [`Grid3D`](@ref) on which the values are sampled, `fourier_layout` is the [`RealFourierLayout`](@ref)
used when transforming the field, and `array_type` is the array type used to store the sampled values.

Broadcasting over scalar fields in physical-space representation is lifted to `values_at_grid`. Thus dotted assignments such as `@. destination = a - b + c`
write into `destination.values_at_grid`, while field-valued out-of-place dotted expressions return a new `ScalarFieldPhysical`.

The two-argument constructors use the default `RealFourierLayout()` for the layout.
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
    ScalarFieldSpectral(
      fourier_coefficients::AbstractArray{Complex{T}, 3},
      grid::Grid3D{T},
      fourier_layout::RealFourierLayout,
    ) where {T<:AbstractFloat}

    ScalarFieldSpectral(
      fourier_coefficients::AbstractArray{Complex{T}, 3},
      grid::Grid3D{T},
    ) where {T<:AbstractFloat}

Scalar field in spectral representation, stored as its nonredundant real-to-complex Fourier coefficients.

Here `fourier_coefficients` contains the complex Fourier coefficients in real-FFT storage, `grid` is the [`Grid3D`](@ref)
associated with the physical domain, and `fourier_layout` is the [`RealFourierLayout`](@ref) specifying the transformed dimensions and the real-FFT half dimension.

The coefficient array has shape `spectral_field_shape(grid, fourier_layout, Val(0))`.
The dimension `fourier_layout.fft_dims[1]` is the real-FFT half dimension.

Broadcasting over scalar fields in spectral representation is lifted to `fourier_coefficients`. Thus dotted assignments such as `@. destination = a - b + c`
write into `destination.fourier_coefficients`, while field-valued out-of-place dotted expressions return a new `ScalarFieldSpectral`.
All such operations are coefficientwise; for example, `.*` does not represent a pseudospectral product of scalar fields.

The two-argument constructor uses the default `RealFourierLayout()` for the layout.
"""
struct ScalarFieldSpectral{T<:AbstractFloat, Â<:AbstractArray{Complex{T}, 3}, G<:Grid3D{T}, L<:RealFourierLayout} <: AbstractFieldSpectral{T, 0}
  fourier_coefficients::Â
  grid::G
  fourier_layout::L

  function ScalarFieldSpectral(fourier_coefficients::Â, grid::G, fourier_layout::L) where {T<:AbstractFloat, Â<:AbstractArray{Complex{T}, 3}, G<:Grid3D{T}, L<:RealFourierLayout}
    size(fourier_coefficients) == spectral_field_shape(grid, fourier_layout, Val(0)) ||
      throw(DimensionMismatch("size(fourier_coefficients) must be equal to spectral_field_shape(grid, fourier_layout, Val(0))"))
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
    VectorFieldPhysical(
      values_at_grid::AbstractArray{T, 4},
      grid::Grid3D{T},
      fourier_layout::RealFourierLayout,
    ) where {T<:AbstractFloat}

    VectorFieldPhysical(
      values_at_grid::AbstractArray{T, 4},
      grid::Grid3D{T},
    ) where {T<:AbstractFloat}

    VectorFieldPhysical(
      f,
      grid::Grid3D{T},
      fourier_layout::RealFourierLayout = RealFourierLayout();
      array_type = Array,
    ) where {T<:AbstractFloat}

Vector field in physical-space representation, stored as its components on a three-dimensional physical grid.

Here `values_at_grid` contains the real vector components with storage order `values_at_grid[i, j, k, α]`, where `α = 1, 2, 3`,
`grid` is the [`Grid3D`](@ref) on which the values are sampled, and `fourier_layout` is the [`RealFourierLayout`](@ref) used when transforming the field.

The function constructor constructs a vector field in physical-space representation by sampling a real vector-valued function on a three-dimensional physical grid.
Here `f` is called as `f(x, y, z)` and must return a three-component indexable object, `grid` is the [`Grid3D`](@ref) on which the values are sampled,
`fourier_layout` is the [`RealFourierLayout`](@ref) used when transforming the field, and `array_type` is the array type used to store the sampled values.

Broadcasting over vector fields in physical-space representation is lifted to `values_at_grid`. Thus dotted assignments such as `@. destination = a - b + c`
write into `destination.values_at_grid`, while field-valued out-of-place dotted expressions return a new `VectorFieldPhysical`.
These operations are storage-wise and componentwise.

The two-argument constructors use the default `RealFourierLayout()` for the layout.
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
    VectorFieldSpectral(
      fourier_coefficients::AbstractArray{Complex{T}, 4},
      grid::Grid3D{T},
      fourier_layout::RealFourierLayout,
    ) where {T<:AbstractFloat}

    VectorFieldSpectral(
      fourier_coefficients::AbstractArray{Complex{T}, 4},
      grid::Grid3D{T},
    ) where {T<:AbstractFloat}

Vector field in spectral representation, stored as its nonredundant real-to-complex Fourier coefficients.

Here `fourier_coefficients` contains the complex vector Fourier coefficients in real-FFT storage, with the component index last:
`fourier_coefficients[i, j, k, α]`, where `α = 1, 2, 3`. The spatial part has shape `spectral_field_shape(grid, fourier_layout, Val(0))`,
and the full array has shape `spectral_field_shape(grid, fourier_layout, Val(1))`. The dimension `fourier_layout.fft_dims[1]` is the real-FFT half dimension.

Broadcasting over vector fields in spectral representation is lifted to `fourier_coefficients`. Thus dotted assignments such as `@. destination = a - b + c`
write into `destination.fourier_coefficients`, while field-valued out-of-place dotted expressions return a new `VectorFieldSpectral`.
These operations are storage-wise and componentwise. They do not represent pseudospectral products or tensor contractions.

The two-argument constructor uses the default `RealFourierLayout()` for the layout.
"""
struct VectorFieldSpectral{T<:AbstractFloat, Â<:AbstractArray{Complex{T}, 4}, G<:Grid3D{T}, L<:RealFourierLayout} <: AbstractFieldSpectral{T, 1}
  fourier_coefficients::Â
  grid::G
  fourier_layout::L

  function VectorFieldSpectral(fourier_coefficients::Â, grid::G, fourier_layout::L) where {T<:AbstractFloat, Â<:AbstractArray{Complex{T}, 4}, G<:Grid3D{T}, L<:RealFourierLayout}
    size(fourier_coefficients) == spectral_field_shape(grid, fourier_layout, Val(1)) ||
      throw(DimensionMismatch("size(fourier_coefficients) must be equal to spectral_field_shape(grid, fourier_layout, Val(1))"))
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
    TensorFieldPhysical{R}(
      values_at_grid::AbstractArray{T},
      grid::Grid3D{T},
      fourier_layout::RealFourierLayout,
    ) where {R, T<:AbstractFloat}

    TensorFieldPhysical{R}(
      values_at_grid::AbstractArray{T},
      grid::Grid3D{T},
    ) where {R, T<:AbstractFloat}

    TensorFieldPhysical(
      values_at_grid::AbstractArray{T, N},
      grid::Grid3D{T},
      fourier_layout::RealFourierLayout,
    ) where {T<:AbstractFloat, N}

    TensorFieldPhysical(
      values_at_grid::AbstractArray{T, N},
      grid::Grid3D{T},
    ) where {T<:AbstractFloat, N}

    TensorFieldPhysical{R}(
      f,
      grid::Grid3D{T},
      fourier_layout::RealFourierLayout = RealFourierLayout();
      array_type = Array,
    ) where {R, T<:AbstractFloat}

Tensor field of order ``R \\ge 2`` in physical-space representation, stored as its components on a three-dimensional physical grid.

Here `values_at_grid` contains the real tensor components with storage order `values_at_grid[i, j, k, α₁, ..., αᵣ]`,
where each tensor index has length `3`, `grid` is the [`Grid3D`](@ref) on which the values are sampled,
and `fourier_layout` is the [`RealFourierLayout`](@ref) used when transforming the field.

The array has shape `physical_field_shape(grid, Val(R))`. The constructors without explicit `{R}` infer `R = N - 3` from the array dimension `N`.

The function constructor constructs a tensor field of order ``R \\ge 2`` in physical-space representation by sampling a real tensor-valued function on a three-dimensional physical grid.
Here `f` is called as `f(x, y, z)` and must return an indexable object with tensor-fiber shape `fiber_shape(Val(R))`, `grid` is the [`Grid3D`](@ref) on which the values are sampled,
`fourier_layout` is the [`RealFourierLayout`](@ref) used when transforming the field, and `array_type` is the array type used to store the sampled values.

Broadcasting over tensor fields in physical-space representation is lifted to `values_at_grid`. Thus dotted assignments such as `@. destination = a - b + c`
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
    TensorFieldSpectral{R}(
      fourier_coefficients::AbstractArray{Complex{T}},
      grid::Grid3D{T},
      fourier_layout::RealFourierLayout,
    ) where {R, T<:AbstractFloat}

    TensorFieldSpectral{R}(
      fourier_coefficients::AbstractArray{Complex{T}},
      grid::Grid3D{T},
    ) where {R, T<:AbstractFloat}

    TensorFieldSpectral(
      fourier_coefficients::AbstractArray{Complex{T}, N},
      grid::Grid3D{T},
      fourier_layout::RealFourierLayout,
    ) where {T<:AbstractFloat, N}

    TensorFieldSpectral(
      fourier_coefficients::AbstractArray{Complex{T}, N},
      grid::Grid3D{T},
    ) where {T<:AbstractFloat, N}

Tensor field of order ``R \\ge 2`` in spectral representation, stored as its nonredundant real-to-complex Fourier coefficients.

Here `fourier_coefficients` contains the complex tensor Fourier coefficients in real-FFT storage, with the tensor indices last:
`fourier_coefficients[i, j, k, α₁, ..., αᵣ]`, where each tensor index has length `3`. The spatial part has shape
`spectral_field_shape(grid, fourier_layout, Val(0))`, and the full array has shape `spectral_field_shape(grid, fourier_layout, Val(R))`.
The dimension `fourier_layout.fft_dims[1]` is the real-FFT half dimension. The constructors without an explicit `{R}` infer the tensor order ``R = N - 3`` from the stored array's dimension count `N`.

Broadcasting over tensor fields in spectral representation is lifted to `fourier_coefficients`. Thus dotted assignments such as `@. destination = a - b + c`
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
    size(fourier_coefficients) == spectral_field_shape(grid, fourier_layout, Val(R)) ||
      throw(DimensionMismatch("size(fourier_coefficients) must be equal to spectral_field_shape(grid, fourier_layout, Val(R))"))
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
#        Field Utilities         #
##################################

"""
    similar_field(reference::AbstractField, data)

    similar_field(reference::AbstractField, ::Val{R})

Construct a field with metadata copied from `reference`.

With storage array `data`, the field has the same representation and tensor order as `reference`. With `Val{R}`, new storage is allocated with the same representation and tensor order `R`.

This is used by out-of-place field broadcasting and by allocating algebraic operations.
"""
function similar_field end

similar_field(reference::ScalarFieldPhysical{T}, data::AbstractArray{T, 3}) where {T<:AbstractFloat} =
  ScalarFieldPhysical(data, field_grid(reference), field_layout(reference))

similar_field(reference::ScalarFieldSpectral{T}, data::AbstractArray{Complex{T}, 3}) where {T<:AbstractFloat} =
  ScalarFieldSpectral(data, field_grid(reference), field_layout(reference))

similar_field(reference::VectorFieldPhysical{T}, data::AbstractArray{T, 4}) where {T<:AbstractFloat} =
  VectorFieldPhysical(data, field_grid(reference), field_layout(reference))

similar_field(reference::VectorFieldSpectral{T}, data::AbstractArray{Complex{T}, 4}) where {T<:AbstractFloat} =
  VectorFieldSpectral(data, field_grid(reference), field_layout(reference))

similar_field(reference::TensorFieldPhysical{R, T}, data::AbstractArray{T, N}) where {R, T<:AbstractFloat, N} =
  TensorFieldPhysical{R}(data, field_grid(reference), field_layout(reference))

similar_field(reference::TensorFieldSpectral{R, T}, data::AbstractArray{Complex{T}, N}) where {R, T<:AbstractFloat, N} =
  TensorFieldSpectral{R}(data, field_grid(reference), field_layout(reference))


function similar_field(reference::AbstractFieldPhysical{T}, ::Val{0}) where {T<:AbstractFloat}
  values_at_grid = similar(field_data(reference), T, physical_field_shape(field_grid(reference), Val(0)))
  return ScalarFieldPhysical(values_at_grid, field_grid(reference), field_layout(reference))
end


function similar_field(reference::AbstractFieldPhysical{T}, ::Val{1}) where {T<:AbstractFloat}
  values_at_grid = similar(field_data(reference), T, physical_field_shape(field_grid(reference), Val(1)))
  return VectorFieldPhysical(values_at_grid, field_grid(reference), field_layout(reference))
end


function similar_field(reference::AbstractFieldPhysical{T}, ::Val{R}) where {T<:AbstractFloat, R}
  values_at_grid = similar(field_data(reference), T, physical_field_shape(field_grid(reference), Val(R)))
  return TensorFieldPhysical{R}(values_at_grid, field_grid(reference), field_layout(reference))
end


function similar_field(reference::AbstractFieldSpectral{T}, ::Val{0}) where {T<:AbstractFloat}
  fourier_coefficients = similar(field_data(reference), Complex{T}, spectral_field_shape(field_grid(reference), field_layout(reference), Val(0)))
  return ScalarFieldSpectral(fourier_coefficients, field_grid(reference), field_layout(reference))
end


function similar_field(reference::AbstractFieldSpectral{T}, ::Val{1}) where {T<:AbstractFloat}
  fourier_coefficients = similar(field_data(reference), Complex{T}, spectral_field_shape(field_grid(reference), field_layout(reference), Val(1)))
  return VectorFieldSpectral(fourier_coefficients, field_grid(reference), field_layout(reference))
end


function similar_field(reference::AbstractFieldSpectral{T}, ::Val{R}) where {T<:AbstractFloat, R}
  fourier_coefficients = similar(field_data(reference), Complex{T}, spectral_field_shape(field_grid(reference), field_layout(reference), Val(R)))
  return TensorFieldSpectral{R}(fourier_coefficients, field_grid(reference), field_layout(reference))
end


"""
    similar_physical_field(reference::AbstractFieldSpectral, data)

Construct a field represented in physical space with storage array `data` and metadata copied from the spectral-space `reference`.
"""
function similar_physical_field end

similar_physical_field(reference::ScalarFieldSpectral{T}, data::AbstractArray{T, 3}) where {T<:AbstractFloat} =
  ScalarFieldPhysical(data, field_grid(reference), field_layout(reference))

similar_physical_field(reference::VectorFieldSpectral{T}, data::AbstractArray{T, 4}) where {T<:AbstractFloat} =
  VectorFieldPhysical(data, field_grid(reference), field_layout(reference))

similar_physical_field(reference::TensorFieldSpectral{R, T}, data::AbstractArray{T, N}) where {R, T<:AbstractFloat, N} =
  TensorFieldPhysical{R}(data, field_grid(reference), field_layout(reference))


"""
    similar_spectral_field(reference::AbstractFieldPhysical, data)

Construct a field represented in spectral space with storage array `data` and metadata copied from the physical-space `reference`.
"""
function similar_spectral_field end

similar_spectral_field(reference::ScalarFieldPhysical{T}, data::AbstractArray{Complex{T}, 3}) where {T<:AbstractFloat} =
  ScalarFieldSpectral(data, field_grid(reference), field_layout(reference))

similar_spectral_field(reference::VectorFieldPhysical{T}, data::AbstractArray{Complex{T}, 4}) where {T<:AbstractFloat} =
  VectorFieldSpectral(data, field_grid(reference), field_layout(reference))

similar_spectral_field(reference::TensorFieldPhysical{R, T}, data::AbstractArray{Complex{T}, N}) where {R, T<:AbstractFloat, N} =
  TensorFieldSpectral{R}(data, field_grid(reference), field_layout(reference))


"""
    _vector_component_data(
      field::Union{VectorFieldPhysical, VectorFieldSpectral},
      component,
    )

Return a view of the storage array corresponding to vector component `component`.

The first three dimensions are spatial dimensions. The last dimension is the vector-fiber index.
This helper is internal and works for vector fields in physical-space and spectral representations.
"""
_vector_component_data(field::Union{VectorFieldPhysical, VectorFieldSpectral}, component) = selectdim(field_data(field), ndims(field_data(field)), component)


"""
    _tensor2_component_data(
      field::Union{TensorFieldPhysical{2}, TensorFieldSpectral{2}},
      first_index,
      second_index,
    )

Return a view of the storage array corresponding to component `(first_index, second_index)` of a second-order tensor field.

The first three dimensions are spatial dimensions. The last two dimensions are the tensor-fiber indices.
This helper is internal and works for second-order tensor fields in physical-space and spectral representations.
"""
function _tensor2_component_data(field::Union{TensorFieldPhysical{2}, TensorFieldSpectral{2}}, first_index, second_index)
  data = field_data(field)
  return selectdim(selectdim(data, ndims(data) - 1, first_index), ndims(data) - 1, second_index)
end




###################################
#        Field Compatibility      #
###################################

# Atomic equality predicates over field metadata. Each returns a `Bool` and is
# composed by the compatibility checks below. They give a single definition of
# "same scalar type", "same grid", and so on, reused across the package.
_same_scalar_type(a, b) = field_scalar_type(a) == field_scalar_type(b)
_same_tensor_order(a, b) = field_tensor_order(a) == field_tensor_order(b)
_same_grid(a, b) = field_grid(a) == field_grid(b)
_same_layout(a, b) = field_layout(a) == field_layout(b)


"""
    _check_same_domain(a, b)

Throw unless `a` and `b` share scalar type, grid, and Fourier layout (tensor order may differ). Shared body for the same-representation domain checks; the entry points that call it (`_check_field_domain_compatibility`, `check_field_compatibility`) are each restricted to a single representation, so a physical/spectral pair has no matching method and is rejected.
"""
function _check_same_domain(a, b)
  _same_scalar_type(a, b) || throw(ArgumentError("field scalar types must be equal"))
  _same_grid(a, b)        || throw(ArgumentError("field grids must be equal"))
  _same_layout(a, b)      || throw(ArgumentError("field Fourier layouts must be equal"))
  return nothing
end


"""
    _check_field_domain_compatibility(a::AbstractFieldPhysical,
                                      b::AbstractFieldPhysical)
    _check_field_domain_compatibility(a::AbstractFieldSpectral,
                                      b::AbstractFieldSpectral)

Check that two fields in the same representation share scalar type, grid, and Fourier layout.

Tensor order is allowed to differ, so this is the check for representation-preserving operations that change order, such as gradient and divergence. Returns `nothing` or throws.
"""
function _check_field_domain_compatibility end
_check_field_domain_compatibility(a::AbstractFieldPhysical, b::AbstractFieldPhysical) = _check_same_domain(a, b)
_check_field_domain_compatibility(a::AbstractFieldSpectral, b::AbstractFieldSpectral) = _check_same_domain(a, b)


"""
    check_field_compatibility(a::AbstractFieldPhysical, b::AbstractFieldPhysical)
    check_field_compatibility(a::AbstractFieldSpectral, b::AbstractFieldSpectral)

Check that two fields in the same representation share scalar type, tensor order, grid, and Fourier layout.

This is the check for operations that require fully matching operands. Returns `nothing` or throws.
"""
function check_field_compatibility end

function check_field_compatibility(a::AbstractFieldPhysical, b::AbstractFieldPhysical)
  _check_same_domain(a, b)
  _same_tensor_order(a, b) || throw(ArgumentError("field tensor orders must be equal"))
  return nothing
end

function check_field_compatibility(a::AbstractFieldSpectral, b::AbstractFieldSpectral)
  _check_same_domain(a, b)
  _same_tensor_order(a, b) || throw(ArgumentError("field tensor orders must be equal"))
  return nothing
end


"""
    _check_field_matches_context(field::AbstractField, context)

Check that `field` was built for the same grid and Fourier layout as `context`.

Here `context` is a precomputed spectral artifact carrying `grid` and `fourier_layout` fields, namely [`FieldTransformPlans`](@ref) or [`FieldSpectralMultipliers`](@ref). Returns `nothing` or throws.
"""
function _check_field_matches_context(field::AbstractField, context)
  field_grid(field) == context.grid || throw(ArgumentError("field grid must be equal to $(nameof(typeof(context))) grid"))
  field_layout(field) == context.fourier_layout || throw(ArgumentError("field Fourier layout must be equal to $(nameof(typeof(context))) Fourier layout"))
  return nothing
end




#######################################
#        Field Transform Plans        #
#######################################

"""
    FieldTransformPlans(
      physical::AbstractFieldPhysical{T, R},
      spectral::AbstractFieldSpectral{T, R};
      fft_flags = nothing,
      fft_timelimit = Inf,
    ) where {T<:AbstractFloat, R}

Forward and inverse FFT plans connecting compatible fields represented in physical and spectral space.

Here `physical` provides the real-space storage array, `spectral` provides the real-to-complex Fourier coefficient array,
`fft_flags` is an optional backend-specific FFT planner flag, and `fft_timelimit` is the planner time limit used when `fft_flags` is provided.
Only the spatial dimensions `field_layout(physical).fft_dims` are transformed; tensor-fiber dimensions are left untransformed.

!!! warning "CPU planner choice: the default `ESTIMATE` can badly mis-plan single-precision transforms"
    On the CPU the plans are `FFTW` plans, and with `fft_flags` unset `FFTW` picks the algorithm by its
    built-in `ESTIMATE` heuristic — instant, but a guess. On some CPUs that guess is far off: measured
    on a Zen 5 desktop, the `Float32` transforms ran 3.4–5.4× slower than a timed plan at ``256^3``,
    and at ``512^3`` no faster than `Float64`, in both directions and at every thread count. For a
    long CPU run, pass `fft_flags = FFTW.MEASURE` (or `FFTW.PATIENT`): the one-time timed plan search
    costs seconds and removes the guess. `MEASURE` **overwrites both reference arrays while
    planning**, so construct the plans on scratch or zero-filled fields before seeding data. The
    setting is CPU-specific — the GPU FFT libraries take no planner flag and are unaffected — and
    the default stays `ESTIMATE` because it is instant, deterministic, and right for tests and short
    sessions.

The fields are
- `grid::G`: the [`Grid3D`](@ref) for which the plans were constructed.
- `fourier_layout::L`: the [`RealFourierLayout`](@ref) for which the plans were constructed.
- `plan_forward_fft::PF`: the plan transforming physical values to spectral coefficients.
- `plan_inverse_fft::PI`: the plan transforming spectral coefficients to physical values.

The plans are backend-, array-type-, scalar-type-, and tensor-order-specific; construct a separate `FieldTransformPlans` object for each CPU/GPU backend and field tensor order.
"""
struct FieldTransformPlans{T<:AbstractFloat, R, PF, PI, G<:Grid3D{T}, L<:RealFourierLayout}
  grid::G
  fourier_layout::L
  plan_forward_fft::PF
  plan_inverse_fft::PI
end


function FieldTransformPlans(physical::AbstractFieldPhysical{T, R}, spectral::AbstractFieldSpectral{T, R}; fft_flags = nothing, fft_timelimit = Inf) where {T<:AbstractFloat, R}
  field_grid(physical)   == field_grid(spectral)   || throw(ArgumentError("field grids must be equal"))
  field_layout(physical) == field_layout(spectral) || throw(ArgumentError("field Fourier layouts must be equal"))

  fft_dims = field_layout(physical).fft_dims

  plan_forward_fft =
    isnothing(fft_flags) ? plan_rfft(field_data(physical), fft_dims) :
    plan_rfft(field_data(physical), fft_dims; flags = fft_flags, timelimit = fft_timelimit)

  plan_inverse_fft =
    isnothing(fft_flags) ? plan_irfft(field_data(spectral), field_grid(physical).grid_size[fft_dims[1]], fft_dims) :
    plan_irfft(field_data(spectral), field_grid(physical).grid_size[fft_dims[1]], fft_dims; flags = fft_flags, timelimit = fft_timelimit)

  return FieldTransformPlans{T, R, typeof(plan_forward_fft), typeof(plan_inverse_fft), typeof(field_grid(physical)), typeof(field_layout(physical))}(
    field_grid(physical), field_layout(physical), plan_forward_fft, plan_inverse_fft)
end


"""
    to_physical!(
      physical::AbstractFieldPhysical{T, R},
      spectral::AbstractFieldSpectral{T, R},
      transform_plans::FieldTransformPlans{T, R},
    ) where {T<:AbstractFloat, R}

Transform a field from spectral space to physical space in-place.

Here `physical` is the destination, `spectral` is the source, and `transform_plans` provides the inverse FFT plan.

!!! warning "The source is used as scratch"
    The inverse transform uses `spectral` as scratch space and may overwrite it: on return its
    coefficients are left in an undefined state (the `FFTW` CPU backend destroys them — complex-to-real
    transforms have no input-preserving algorithm in the multidimensional case; some GPU backends
    happen to preserve them, but this is not guaranteed). Use the allocating [`to_physical`](@ref)
    when `spectral` must be preserved.

Returns the modified destination field.
"""
function to_physical!(physical::AbstractFieldPhysical{T, R}, spectral::AbstractFieldSpectral{T, R}, transform_plans::FieldTransformPlans{T, R}) where {T<:AbstractFloat, R}
  _check_field_matches_context(physical, transform_plans)
  _check_field_matches_context(spectral, transform_plans)

  mul!(field_data(physical), transform_plans.plan_inverse_fft, field_data(spectral))

  return physical
end


"""
    to_spectral!(
      spectral::AbstractFieldSpectral{T, R},
      physical::AbstractFieldPhysical{T, R},
      transform_plans::FieldTransformPlans{T, R},
    ) where {T<:AbstractFloat, R}

Transform a field from physical space to spectral space in-place.

Here `spectral` is the destination, `physical` is the source, and `transform_plans` provides the forward FFT plan.

!!! warning "The source may be overwritten"
    The forward transform may overwrite `physical` on some backends (for example rocFFT reserves the
    right to use real-to-complex inputs as scratch); the `FFTW` CPU backend preserves it, but do not
    rely on the source surviving. Use the allocating [`to_spectral`](@ref) when `physical` must be
    preserved.

Returns the modified destination field.
"""
function to_spectral!(spectral::AbstractFieldSpectral{T, R}, physical::AbstractFieldPhysical{T, R}, transform_plans::FieldTransformPlans{T, R}) where {T<:AbstractFloat, R}
  _check_field_matches_context(spectral, transform_plans)
  _check_field_matches_context(physical, transform_plans)

  mul!(field_data(spectral), transform_plans.plan_forward_fft, field_data(physical))

  return spectral
end


"""
    to_physical(
      spectral::AbstractFieldSpectral{T, R},
      transform_plans::FieldTransformPlans{T, R},
    ) where {T<:AbstractFloat, R}

Transform a field from spectral space to physical space, returning a newly allocated physical-space field.

Here `spectral` is the source and `transform_plans` provides the inverse FFT plan.

This is the allocating form of [`to_physical!`](@ref). Unlike the in-place form, it leaves the input `spectral` unchanged, because it copies the coefficients before transforming. Use it when `spectral` must be preserved, and use the in-place form when it need not be.
"""
function to_physical(spectral::AbstractFieldSpectral{T, R}, transform_plans::FieldTransformPlans{T, R}) where {T<:AbstractFloat, R}
  values_at_grid = similar(field_data(spectral), T, physical_field_shape(field_grid(spectral), Val(R)))
  physical = similar_physical_field(spectral, values_at_grid)
  # The inverse transform may overwrite its input (see to_physical!); copy the
  # coefficients so the caller's field is preserved.
  spectral_preserved = similar_field(spectral, copy(field_data(spectral)))
  return to_physical!(physical, spectral_preserved, transform_plans)
end


"""
    to_spectral(
      physical::AbstractFieldPhysical{T, R},
      transform_plans::FieldTransformPlans{T, R},
    ) where {T<:AbstractFloat, R}

Transform a field from physical space to spectral space, returning a newly allocated spectral-space field.

Here `physical` is the source and `transform_plans` provides the forward FFT plan.

This is the allocating form of [`to_spectral!`](@ref). Unlike the in-place form, it leaves the input `physical` unchanged, because it copies the values before transforming. Use it when `physical` must be preserved, and use the in-place form when it need not be.
"""
function to_spectral(physical::AbstractFieldPhysical{T, R}, transform_plans::FieldTransformPlans{T, R}) where {T<:AbstractFloat, R}
  fourier_coefficients = similar(field_data(physical), Complex{T}, spectral_field_shape(field_grid(physical), field_layout(physical), Val(R)))
  spectral = similar_spectral_field(physical, fourier_coefficients)
  # The forward transform may overwrite its input on some backends (see to_spectral!);
  # copy the values so the caller's field is preserved.
  physical_preserved = similar_field(physical, copy(field_data(physical)))
  return to_spectral!(spectral, physical_preserved, transform_plans)
end




###########################################
#        Field Spectral Multipliers       #
###########################################

"""
    FieldSpectralMultipliers(
      grid::Grid3D{T},
      fourier_layout::RealFourierLayout,
      wavenumber_1, wavenumber_2, wavenumber_3,
      squared_wavenumber_1, squared_wavenumber_2, squared_wavenumber_3,
    ) where {T<:AbstractFloat}

    FieldSpectralMultipliers(
      field::AbstractFieldSpectral{T},
      wavenumber_1, wavenumber_2, wavenumber_3,
      squared_wavenumber_1, squared_wavenumber_2, squared_wavenumber_3,
    ) where {T<:AbstractFloat}

One-dimensional Fourier wavenumber arrays for coefficientwise spectral operators such as derivatives, the Laplacian, and the Helmholtz projection.

The fields are
- `grid`, `fourier_layout`: the [`Grid3D`](@ref) and [`RealFourierLayout`](@ref) the multipliers were built for.
- `wavenumber_1`, `wavenumber_2`, `wavenumber_3`: the per-axis physical (angular) wavenumbers ``k`` along each axis, used for first derivatives via multiplication by ``\\mathrm{i} k``.
- `squared_wavenumber_1`, `squared_wavenumber_2`, `squared_wavenumber_3`: per-axis squared wavenumbers, used for the Laplacian via multiplication by ``-k^2``.

Each array runs along one spatial axis in the FFT frequency ordering of `fourier_layout`; the half axis `fourier_layout.fft_dims[1]` stores only the nonnegative frequencies.
The arrays must live on storage (CPU or GPU) matching the fields the multipliers are applied to.

These two constructors are explicit: you supply both the wavenumbers and the squared wavenumbers, and only their lengths are checked.
The two array families are stored independently rather than squaring one to obtain the other,
because on even grids they use different conventions for the Nyquist mode (the highest representable frequency).
A convenience constructor `FieldSpectralMultipliers(field)` builds both families from the field's grid and layout with the correct Nyquist treatment;
it carries its own docstring.
"""
struct FieldSpectralMultipliers{T<:AbstractFloat, K1<:AbstractArray{T, 1}, K2<:AbstractArray{T, 1}, K3<:AbstractArray{T, 1}, S1<:AbstractArray{T, 1}, S2<:AbstractArray{T, 1}, S3<:AbstractArray{T, 1}}
  grid::Grid3D{T}
  fourier_layout::RealFourierLayout
  wavenumber_1::K1
  wavenumber_2::K2
  wavenumber_3::K3
  squared_wavenumber_1::S1
  squared_wavenumber_2::S2
  squared_wavenumber_3::S3

  function FieldSpectralMultipliers(grid::Grid3D{T}, fourier_layout::RealFourierLayout,
      wavenumber_1::K1, wavenumber_2::K2, wavenumber_3::K3,
      squared_wavenumber_1::S1, squared_wavenumber_2::S2, squared_wavenumber_3::S3) where {T<:AbstractFloat,
      K1<:AbstractArray{T, 1}, K2<:AbstractArray{T, 1}, K3<:AbstractArray{T, 1}, S1<:AbstractArray{T, 1}, S2<:AbstractArray{T, 1}, S3<:AbstractArray{T, 1}}

    spectral_spatial_shape = spectral_field_shape(grid, fourier_layout, Val(0))

    length(wavenumber_1) == spectral_spatial_shape[1] || throw(DimensionMismatch("length(wavenumber_1) must match the first spectral spatial dimension"))
    length(wavenumber_2) == spectral_spatial_shape[2] || throw(DimensionMismatch("length(wavenumber_2) must match the second spectral spatial dimension"))
    length(wavenumber_3) == spectral_spatial_shape[3] || throw(DimensionMismatch("length(wavenumber_3) must match the third spectral spatial dimension"))
    length(squared_wavenumber_1) == spectral_spatial_shape[1] || throw(DimensionMismatch("length(squared_wavenumber_1) must match the first spectral spatial dimension"))
    length(squared_wavenumber_2) == spectral_spatial_shape[2] || throw(DimensionMismatch("length(squared_wavenumber_2) must match the second spectral spatial dimension"))
    length(squared_wavenumber_3) == spectral_spatial_shape[3] || throw(DimensionMismatch("length(squared_wavenumber_3) must match the third spectral spatial dimension"))

    return new{T, K1, K2, K3, S1, S2, S3}(grid, fourier_layout, wavenumber_1, wavenumber_2, wavenumber_3, squared_wavenumber_1, squared_wavenumber_2, squared_wavenumber_3)
  end
end


function FieldSpectralMultipliers(field::AbstractFieldSpectral{T}, wavenumber_1::AbstractArray{T, 1}, wavenumber_2::AbstractArray{T, 1}, wavenumber_3::AbstractArray{T, 1},
    squared_wavenumber_1::AbstractArray{T, 1}, squared_wavenumber_2::AbstractArray{T, 1}, squared_wavenumber_3::AbstractArray{T, 1}) where {T<:AbstractFloat}
  
  return FieldSpectralMultipliers(field_grid(field), field_layout(field), wavenumber_1, wavenumber_2, wavenumber_3, squared_wavenumber_1, squared_wavenumber_2, squared_wavenumber_3)
end


"""
    FieldSpectralMultipliers(field::AbstractFieldSpectral{T}) where {T<:AbstractFloat}

Build the spectral multipliers from the grid and Fourier layout of `field`, allocated on the field's storage backend.

The wavenumbers are the physical angular wavenumbers ``k = 2\\pi n / L`` along each axis, where ``L`` is the domain length and ``n`` runs over the FFT frequency indices.
On an even-length axis the highest stored mode is the Nyquist mode: its first-derivative wavenumber is set to zero, so that derivatives of real fields stay real,
while its squared wavenumber keeps the true ``k^2``, so that the Laplacian and Poisson-type solves stay correct.
On an odd-length axis there is no exact Nyquist mode and no special treatment is applied.
"""
function FieldSpectralMultipliers(field::AbstractFieldSpectral{T}) where {T<:AbstractFloat}
  grid = field_grid(field)
  fourier_layout = field_layout(field)
  half_dimension = fourier_layout.fft_dims[1]
  reference = field_data(field)

  wavenumber_1, squared_wavenumber_1 = _axis_wavenumber_arrays(reference, grid.grid_size[1], grid.domain_size[1], 1 == half_dimension)
  wavenumber_2, squared_wavenumber_2 = _axis_wavenumber_arrays(reference, grid.grid_size[2], grid.domain_size[2], 2 == half_dimension)
  wavenumber_3, squared_wavenumber_3 = _axis_wavenumber_arrays(reference, grid.grid_size[3], grid.domain_size[3], 3 == half_dimension)

  return FieldSpectralMultipliers(grid, fourier_layout,
    wavenumber_1, wavenumber_2, wavenumber_3, squared_wavenumber_1, squared_wavenumber_2, squared_wavenumber_3)
end


"""
    _axis_wavenumber_values(number_of_points, domain_length, half_dimension)

Return `(derivative_wavenumber, squared_wavenumber)` as host vectors for one spatial axis. The `half_dimension` flag marks the real-FFT half axis, which stores only the nonnegative frequencies. On even-length axes the derivative wavenumber is zeroed at the Nyquist mode (so derivatives of real fields stay real) while the squared wavenumber keeps the true ``k^2`` (correct Laplacian) — the deliberate Nyquist split, stored as two independent families.
"""
function _axis_wavenumber_values(number_of_points::Int, domain_length::T, half_dimension::Bool) where {T<:AbstractFloat}
  wavenumber_unit = 2 * T(π) / domain_length
  stored_length = half_dimension ? (number_of_points ÷ 2 + 1) : number_of_points

  true_wavenumber = Vector{T}(undef, stored_length)
  for i in 1:stored_length
    zero_based_index = i - 1
    frequency_index = (half_dimension || zero_based_index < (number_of_points + 1) ÷ 2) ? zero_based_index : zero_based_index - number_of_points
    true_wavenumber[i] = wavenumber_unit * frequency_index
  end

  squared_wavenumber = true_wavenumber .^ 2

  derivative_wavenumber = copy(true_wavenumber)
  if iseven(number_of_points)
    nyquist_index = half_dimension ? stored_length : (number_of_points ÷ 2 + 1)
    derivative_wavenumber[nyquist_index] = zero(T)
  end

  return derivative_wavenumber, squared_wavenumber
end


"""
    _axis_wavenumber_arrays(reference, number_of_points, domain_length, half_dimension)

Build the per-axis derivative and squared wavenumber vectors with `_axis_wavenumber_values` on the host, then copy them onto the storage backend of `reference` (via `similar` + `copyto!`, avoiding scalar GPU writes).
"""
function _axis_wavenumber_arrays(reference::AbstractArray, number_of_points::Int, domain_length::T, half_dimension::Bool) where {T<:AbstractFloat}
  derivative_host, squared_host = _axis_wavenumber_values(number_of_points, domain_length, half_dimension)
  derivative_wavenumber = similar(reference, T, length(derivative_host))
  squared_wavenumber = similar(reference, T, length(squared_host))
  copyto!(derivative_wavenumber, derivative_host)
  copyto!(squared_wavenumber, squared_host)
  return derivative_wavenumber, squared_wavenumber
end


_multipliers_scalar_type(::FieldSpectralMultipliers{T}) where {T<:AbstractFloat} = T


"""
    _check_multipliers_compatibility(field::AbstractFieldSpectral,
                                     multipliers::FieldSpectralMultipliers)

Check that a spectral-space `field` and `multipliers` share scalar type, grid, and Fourier layout. Returns `nothing` or throws.
"""
function _check_multipliers_compatibility(field::AbstractFieldSpectral, multipliers::FieldSpectralMultipliers)
  field_scalar_type(field) == _multipliers_scalar_type(multipliers) || throw(ArgumentError("field and spectral multipliers scalar types must be equal"))
  _check_field_matches_context(field, multipliers)
  return nothing
end


"""
    _wavenumber_broadcast_view(multipliers::FieldSpectralMultipliers, ::Val{axis})

Reshape the per-axis derivative wavenumber array (`axis = 1, 2, 3`) so it broadcasts against the three spatial dimensions of a field in spectral representation. Used by the first-derivative spectral operators (gradient, divergence, curl).
"""
_wavenumber_broadcast_view(multipliers::FieldSpectralMultipliers, ::Val{1}) = reshape(multipliers.wavenumber_1, length(multipliers.wavenumber_1), 1, 1)
_wavenumber_broadcast_view(multipliers::FieldSpectralMultipliers, ::Val{2}) = reshape(multipliers.wavenumber_2, 1, length(multipliers.wavenumber_2), 1)
_wavenumber_broadcast_view(multipliers::FieldSpectralMultipliers, ::Val{3}) = reshape(multipliers.wavenumber_3, 1, 1, length(multipliers.wavenumber_3))


"""
    _squared_wavenumber_broadcast(multipliers::FieldSpectralMultipliers)

Return the total squared wavenumber ``|k|^2 = k_1^2 + k_2^2 + k_3^2`` as a **lazy** `Broadcasted` over
the three per-axis squared-wavenumber vectors (reshaped to the three spatial dimensions). Used by the
Laplacian, inverse Laplacian, and Helmholtz projection.

Lazy on purpose: returning the unfused `Broadcasted` lets callers compose it into their own broadcasts
over a spectral field's coefficients ``\\hat s``
(``-|k|^2 \\hat s``, ``\\hat s_i - k_i k_j \\hat s_j / |k|^2``, …) without ever materializing the ``O(N^3)`` array. That keeps those
operators allocation-free in place: no ``O(N^3)`` ``|k|^2`` scratch is built, which on the GPU would
otherwise accumulate in the memory pool on each call.
"""
function _squared_wavenumber_broadcast(multipliers::FieldSpectralMultipliers)
  squared_wavenumber_1 = reshape(multipliers.squared_wavenumber_1, length(multipliers.squared_wavenumber_1), 1, 1)
  squared_wavenumber_2 = reshape(multipliers.squared_wavenumber_2, 1, length(multipliers.squared_wavenumber_2), 1)
  squared_wavenumber_3 = reshape(multipliers.squared_wavenumber_3, 1, 1, length(multipliers.squared_wavenumber_3))
  return Base.broadcasted(+, squared_wavenumber_1, squared_wavenumber_2, squared_wavenumber_3)
end



##############################
#        Broadcasting        #
##############################

"""
    FieldPhysicalBroadcastStyle{N}

Broadcast style for fields in physical-space representation (`N = 3 + tensor_order`). A field stands for its storage array inside a broadcast, and the style materializes the result back into a physical-space field. See also `FieldSpectralBroadcastStyle`.
"""
struct FieldPhysicalBroadcastStyle{N} <: Base.Broadcast.AbstractArrayStyle{N} end

"""
    FieldSpectralBroadcastStyle{N}

Broadcast style for fields in spectral representation (`N = 3 + tensor_order`); the spectral counterpart of `FieldPhysicalBroadcastStyle`. Combining the two styles is an error, so physical and spectral representations never mix in one broadcast.
"""
struct FieldSpectralBroadcastStyle{N} <: Base.Broadcast.AbstractArrayStyle{N} end

(::Type{<:FieldPhysicalBroadcastStyle})(::Val{N}) where {N} = FieldPhysicalBroadcastStyle{N}()
(::Type{<:FieldSpectralBroadcastStyle})(::Val{N}) where {N} = FieldSpectralBroadcastStyle{N}()

Base.BroadcastStyle(::Type{<:AbstractFieldPhysical{T, R}}) where {T<:AbstractFloat, R} = FieldPhysicalBroadcastStyle{3 + R}()
Base.BroadcastStyle(::Type{<:AbstractFieldSpectral{T, R}}) where {T<:AbstractFloat, R} = FieldSpectralBroadcastStyle{3 + R}()

Base.BroadcastStyle(::FieldPhysicalBroadcastStyle{M}, ::FieldPhysicalBroadcastStyle{N}) where {M, N} = FieldPhysicalBroadcastStyle{max(M, N)}()
Base.BroadcastStyle(::FieldSpectralBroadcastStyle{M}, ::FieldSpectralBroadcastStyle{N}) where {M, N} = FieldSpectralBroadcastStyle{max(M, N)}()

Base.BroadcastStyle(::FieldPhysicalBroadcastStyle, ::FieldSpectralBroadcastStyle) = throw(ArgumentError("cannot broadcast fields represented in physical and spectral space together"))

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


"""
    _first_field(x)

Return the first `AbstractField` found in `x` — a field, an arbitrary value, a `Broadcasted` tree, or an argument tuple — or `nothing` if there is none. Out-of-place field broadcasting uses it to pick the field whose grid/layout metadata seeds the allocated result.
"""
_first_field(field::AbstractField) = field
_first_field(::Any) = nothing

_first_field(broadcasted::Base.Broadcast.Broadcasted) = _first_field(broadcasted.args)
_first_field(::Tuple{}) = nothing

function _first_field(args::Tuple)
  field = _first_field(first(args))
  return isnothing(field) ? _first_field(Base.tail(args)) : field
end


"""
    _check_broadcast_field_compatibility(destination, argument)

Check, during field broadcasting, that `argument` is compatible with `destination`: same-representation fields must pass `check_field_compatibility`; mixing physical and spectral representations throws; non-field arguments (real numbers, plain arrays) are accepted. Recurses into the operands of a `Broadcasted` argument.
"""
_check_broadcast_field_compatibility(destination::AbstractFieldPhysical, field::AbstractFieldPhysical) = check_field_compatibility(destination, field)

_check_broadcast_field_compatibility(destination::AbstractFieldSpectral, field::AbstractFieldSpectral) = check_field_compatibility(destination, field)

_check_broadcast_field_compatibility(::AbstractFieldPhysical, ::AbstractFieldSpectral) = throw(ArgumentError("cannot broadcast fields represented in physical and spectral space together"))

_check_broadcast_field_compatibility(::AbstractFieldSpectral, ::AbstractFieldPhysical) = throw(ArgumentError("cannot broadcast fields represented in spectral and physical space together"))

_check_broadcast_field_compatibility(::AbstractField, ::Any) =  nothing

function _check_broadcast_field_compatibility(destination::AbstractField, broadcasted::Base.Broadcast.Broadcasted)
  foreach(argument -> _check_broadcast_field_compatibility(destination, argument), broadcasted.args)
  return nothing
end


"""
    _unwrap_broadcast_argument(x)

Replace each field in a broadcast expression with its storage array — recursing through a `Broadcasted` tree and leaving non-field arguments untouched — so a field-level broadcast lowers to a plain array broadcast on the underlying backend.
"""
_unwrap_broadcast_argument(field::AbstractField) = field_data(field)
_unwrap_broadcast_argument(argument) = argument

function _unwrap_broadcast_argument(broadcasted::Base.Broadcast.Broadcasted)
  return Base.Broadcast.broadcasted(broadcasted.f, map(_unwrap_broadcast_argument, broadcasted.args)...)
end


function Base.copyto!(destination::AbstractField, broadcasted::Base.Broadcast.Broadcasted)
  _check_broadcast_field_compatibility(destination, broadcasted)

  unwrapped = _unwrap_broadcast_argument(broadcasted)

  unwrapped_with_destination_axes = Base.Broadcast.Broadcasted(unwrapped.style, unwrapped.f, unwrapped.args, axes(field_data(destination)))

  # Threaded fused assignment on CPU (serial below the cutoff; GPU/unknown wrappers fall
  # back to standard `materialize!` inside `_assign!`). Covers all whole-field dotted ops.
  _assign!(field_data(destination), unwrapped_with_destination_axes)

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



"""
    _init_fft_threads()

Set `FFTW`'s thread count to match Julia's (one when threading is off). `FFTW` bakes the thread
count into each plan, so this runs at package load, before any `FieldTransformPlans` is built.
Retune afterwards with [`set_fft_threads!`](@ref).
"""
function _init_fft_threads()
  count = _THREADING_OVERRIDE[] === false ? 1 : max(1, Threads.nthreads())
  FFTW.set_num_threads(count)
  return count
end


"""
    set_fft_threads!(n)

Set the number of threads `FFTW` uses, effective for plans built afterwards (`FFTW` fixes the
count at plan construction). Returns `n`. Code that parallelizes across many fields at once
should build plans under `set_fft_threads!(1)` to avoid `FFTW`×Julia thread oversubscription (more
active threads than cores, contending instead of helping).
"""
set_fft_threads!(n::Integer) = (FFTW.set_num_threads(Int(n)); Int(n))


# --- HDF5 persistence: bare generics declared here so `?write_field` and the docs work without HDF5
# present; the methods (on `HDF5.File` / `Group`) live in `ext/GBGPeriodicFieldsHDF5Ext.jl`, loaded
# automatically when the HDF5 package is. ---

"""
    write_field(parent::HDF5.H5DataStore, name::AbstractString, field::AbstractField)

Persist `field` — any of the six field types, scalar / vector / tensor in either representation — as a
**new HDF5 group** `name` under `parent`. Use it to checkpoint a field for restart, save a full-resolution
snapshot for later analysis, or pass a field to another tool; the reload with [`read_field`](@ref) is exact.

The group is **self-describing**: the field's numeric array becomes the dataset `data`, and its metadata
become attributes — a `type` tag, a schema `version`, a `representation` tag (`"physical"` or
`"spectral"`), the [`Grid3D`](@ref) geometry (`grid_size`,
`domain_size`, `origin`), the Fourier layout (`fft_dims`), the element type, and the tensor order — so any
HDF5 tool can read it. A **physical** field stores a real array; a field in **spectral** representation
stores its complex half-spectrum. A device (GPU) array is copied to the host on write. The sugar
`parent[name] = field` is equivalent.

Because `parent` is a handle you opened and own, this never opens or closes a file: a consumer bundles a
whole snapshot (velocity, vorticity, …) into one file under separate names and attaches its own `time` /
`iteration` attributes — the package serializes the fields, and the consumer owns the bundling and any
notion of time.

- `parent` — an open HDF5 `File` or `Group` to create the new subgroup under.
- `name` — the name of the group to create.
- `field` — the field to write.

Provided by a package extension, so it is available only when `HDF5` is loaded. Returns the created group.
"""
function write_field end


"""
    read_field(parent::HDF5.H5DataStore, name::AbstractString)

Reconstruct the field written by [`write_field`](@ref) from the HDF5 group `name` under `parent`,
dispatching on the stored `type` attribute to return the matching field type (`ScalarFieldPhysical`,
`VectorFieldSpectral`, …). The reload is **exact** — the array data, the [`Grid3D`](@ref) geometry, the
Fourier layout, the element type, and the tensor order are recovered bit-for-bit.

The reconstructed field is a host (CPU) object regardless of where the written one lived; move it to a
device afterward if needed.

- `parent` — an open HDF5 `File` or `Group` holding the group.
- `name` — the name (or path) of the field group under `parent`.

Provided by a package extension, so it is available only when `HDF5` is loaded. Returns the reconstructed
field.
"""
function read_field end


end # module Fields
