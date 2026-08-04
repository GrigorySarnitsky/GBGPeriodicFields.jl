"""
    Fields

Field representation and transform core for scalar, vector, and second-order tensor fields on
three-dimensional rectangular periodic domains, for CPU and GPU array backends. A field is a physical
object, and the physical-space and spectral types (for example `ScalarFieldPhysical` and
`ScalarFieldSpectral`) are two representations of the **same** field.

The parts are:

  * **Grid and layout** — [`Grid3D`](@ref) describes the periodic domain geometry, and
    [`RealFourierLayout`](@ref) describes the real-to-complex transform layout.
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
  * **Spectral kernels** — [`SpectralKernel`](@ref) is the supertype of every coefficientwise
    multiplier a `convolve`-style operation can apply, whatever storage it uses — including the stored
    class, which wraps a field of coefficients. It lives here, rather than with the kernels themselves,
    so every module that accepts one names a single type; [`Convolution`](@ref "Convolution") defines
    the concrete classes.
  * **Allocation** — [`similar_field`](@ref) returns uninitialized storage carrying a reference field's
    representation, tensor order, grid and backend, which is how an operation builds scratch or a
    result without naming a concrete field type.
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
using ..FiberSections:
  _check_owned_storage, AbstractFiberSection, _assign!, _THREADING_OVERRIDE,
  FiberVector, FiberTensor2, FiberTensor3, FiberTensor4, fiber_shape

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
       physical_field_shape,
       spectral_field_shape,
       similar_field,
       set_fft_threads!




###################################
#        Fixed Fiber Types        #
###################################






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

The grid is uniform, so the spacing is not independent: it must equal `domain_size ./ grid_size` along
every axis. The two-argument constructor computes it and is the one to prefer; the four-argument form
checks what it is handed and throws an `ArgumentError` on a spacing that contradicts the domain, since
a grid whose stored spacing disagrees with its domain would silently mislocate every interpolated
point rather than fail. The comparison is a floating-point tolerance, so a spacing computed by a
different but equivalent route is accepted. Every grid size must be positive, every domain length
finite and positive, and every origin coordinate finite.
"""
struct Grid3D{T<:AbstractFloat}
  grid_size::NTuple{3, Int}
  domain_size::NTuple{3, T}
  grid_spacing::NTuple{3, T}
  origin::NTuple{3, T}

  function Grid3D{T}(grid_size::NTuple{3, Int}, domain_size::NTuple{3, T}, grid_spacing::NTuple{3, T},
      origin::NTuple{3, T}) where {T<:AbstractFloat}

    all(size -> size > 0, grid_size) ||
      throw(ArgumentError("grid_size must be positive along every axis, got $grid_size"))
    # A non-finite or non-positive extent is not a domain. Left unchecked, it propagated: the spacing
    # became NaN or negative, every wavenumber built from it followed, and the failure surfaced far
    # from its cause as a field of NaNs rather than as a rejected grid.
    all(length -> isfinite(length) && length > 0, domain_size) ||
      throw(ArgumentError("domain_size must be finite and positive along every axis, got $domain_size"))
    all(isfinite, origin) ||
      throw(ArgumentError("origin must be finite along every axis, got $origin"))
    implied_spacing = domain_size ./ T.(grid_size)
    all(axis -> isapprox(grid_spacing[axis], implied_spacing[axis]; rtol = sqrt(eps(T))), 1:3) ||
      throw(ArgumentError("grid_spacing $grid_spacing contradicts domain_size ./ grid_size = $implied_spacing; " *
                          "a Grid3D is uniform, so the two must agree"))
    return new{T}(grid_size, domain_size, grid_spacing, origin)
  end
end


Grid3D(grid_size::NTuple{3, Int}, domain_size::NTuple{3, T}, grid_spacing::NTuple{3, T},
       origin::NTuple{3, T}) where {T<:AbstractFloat} =
  Grid3D{T}(grid_size, domain_size, grid_spacing, origin)


function Grid3D(grid_size::NTuple{3, Int}, domain_size::NTuple{3, T}; origin::NTuple{3, T} = (zero(T), zero(T), zero(T))) where {T<:AbstractFloat}
  grid_spacing = domain_size ./ T.(grid_size)
  return Grid3D(grid_size, domain_size, grid_spacing, origin)
end


"""
    RealFourierLayout()
    RealFourierLayout(fft_dims::NTuple{3, Int})

Layout convention for three-dimensional real-to-complex Fourier transforms.

The main role of the ordering is to specify the real-FFT half dimension:
in dimension `fft_dims[1]`, only the nonnegative frequencies are represented, while the other dimensions use the full complex FFT frequency ordering.

The zero-argument constructor uses `fft_dims = (1, 2, 3)`.

The fields are
- `fft_dims`: the tuple of transformed dimensions passed to the FFT planner, whose first entry is the
  halved (folded) axis.
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

The fields are
- `values_at_grid`: the real scalar values, one per grid point.
- `grid`: the [`Grid3D`](@ref) on which the values are sampled.
- `fourier_layout`: the [`RealFourierLayout`](@ref) used when transforming the field.

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
    _check_owned_storage(values_at_grid, "a ScalarFieldPhysical")
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

The fields are
- `fourier_coefficients`: the complex Fourier coefficients, in real-FFT storage.
- `grid`: the [`Grid3D`](@ref) of the physical domain the coefficients represent.
- `fourier_layout`: the [`RealFourierLayout`](@ref) giving the transformed dimensions and the real-FFT half dimension.

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
    _check_owned_storage(fourier_coefficients, "a ScalarFieldSpectral")
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

The fields are
- `values_at_grid`: the real vector components, stored `values_at_grid[i, j, k, α]` with `α = 1, 2, 3`.
- `grid`: the [`Grid3D`](@ref) on which the values are sampled.
- `fourier_layout`: the [`RealFourierLayout`](@ref) used when transforming the field.

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
    _check_owned_storage(values_at_grid, "a VectorFieldPhysical")
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

The fields are
- `fourier_coefficients`: the complex vector Fourier coefficients in real-FFT storage, component index last, `fourier_coefficients[i, j, k, α]` with `α = 1, 2, 3`; its spatial part has shape `spectral_field_shape(grid, fourier_layout, Val(0))` and the whole array `spectral_field_shape(grid, fourier_layout, Val(1))`.
- `grid`: the [`Grid3D`](@ref) of the physical domain the coefficients represent.
- `fourier_layout`: the [`RealFourierLayout`](@ref); its `fft_dims[1]` is the real-FFT half dimension.

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
    _check_owned_storage(fourier_coefficients, "a VectorFieldSpectral")
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

The fields are
- `values_at_grid`: the real tensor components, stored `values_at_grid[i, j, k, α₁, ..., αᵣ]` with each tensor index of length `3`.
- `grid`: the [`Grid3D`](@ref) on which the values are sampled.
- `fourier_layout`: the [`RealFourierLayout`](@ref) used when transforming the field.

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
    _check_owned_storage(values_at_grid, "a TensorFieldPhysical")
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

The fields are
- `fourier_coefficients`: the complex tensor Fourier coefficients in real-FFT storage, tensor indices last, `fourier_coefficients[i, j, k, α₁, ..., αᵣ]` with each of length `3`; its spatial part has shape `spectral_field_shape(grid, fourier_layout, Val(0))` and the whole array `spectral_field_shape(grid, fourier_layout, Val(R))`.
- `grid`: the [`Grid3D`](@ref) of the physical domain the coefficients represent.
- `fourier_layout`: the [`RealFourierLayout`](@ref); its `fft_dims[1]` is the real-FFT half dimension. The constructors without an explicit `{R}` infer the tensor order ``R = N - 3`` from the stored array's dimension count `N`.

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
    _check_owned_storage(fourier_coefficients, "a TensorFieldSpectral")
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

# Storage family, compared by the array type's name rather than through KernelAbstractions: the
# comparison is then a compile-time property of the types, so it costs a checked operation nothing,
# and `Fields` needs no launch-layer dependency to express it. `Array` and `CuArray` differ; a plain
# array and a view of one do not, which is intended — a view shares the host's storage family and is
# a legitimate operand.
_storage_family(a) = Base.typename(typeof(parent(field_data(a)))).wrapper
_same_backend(a, b) = _storage_family(a) === _storage_family(b)


"""
    _check_same_domain(a, b)

Throw unless `a` and `b` share scalar type, grid, Fourier layout, and storage family (tensor order
may differ). Shared body for the same-representation domain checks; the entry points that call it (`_check_field_domain_compatibility`, `check_field_compatibility`) are each restricted to a single representation, so a physical/spectral pair has no matching method and is rejected.
"""
function _check_same_domain(a, b)
  _same_scalar_type(a, b) || throw(ArgumentError("field scalar types must be equal"))
  _same_grid(a, b)        || throw(ArgumentError("field grids must be equal"))
  _same_layout(a, b)      || throw(ArgumentError("field Fourier layouts must be equal"))
  # Storage family belongs in the domain check, not below it in the launch layer. Without it a
  # host/device pair passes every structural test and then fails inside a broadcast, a
  # KernelAbstractions launch, or an FFT multiplication — so the error a user sees depends on which
  # operation they happened to call, and on the backend.
  _same_backend(a, b) ||
    throw(ArgumentError("fields must live in the same storage family; got " *
                        "$(_storage_family(a)) and $(_storage_family(b))"))
  return nothing
end


"""
    _check_field_domain_compatibility(a::AbstractFieldPhysical,
                                      b::AbstractFieldPhysical)
    _check_field_domain_compatibility(a::AbstractFieldSpectral,
                                      b::AbstractFieldSpectral)

Check that two fields in the same representation share scalar type, grid, Fourier layout, and storage
family.

Tensor order is allowed to differ, so this is the check for representation-preserving operations that change order, such as gradient and divergence. Returns `nothing` or throws.
"""
function _check_field_domain_compatibility end
_check_field_domain_compatibility(a::AbstractFieldPhysical, b::AbstractFieldPhysical) = _check_same_domain(a, b)
_check_field_domain_compatibility(a::AbstractFieldSpectral, b::AbstractFieldSpectral) = _check_same_domain(a, b)


"""
    check_field_compatibility(a::AbstractFieldPhysical, b::AbstractFieldPhysical)
    check_field_compatibility(a::AbstractFieldSpectral, b::AbstractFieldSpectral)

Check that two fields in the same representation share scalar type, tensor order, grid, Fourier
layout, and storage family.

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
    _context_grid(object)

The base an object was built for. Every object that participates in a spectral operation — a field, a
multiplier set, a compressed kernel — answers this and its peer [`_context_layout`](@ref), so one
predicate ([`_check_matching_context`](@ref)) can compare any two of them. `Convolution` extends both
for the kernel classes, which is what lets a kernel be checked against a field or a multiplier set
without either side knowing the other's field names.
"""
function _context_grid end


"""
    _context_layout(object)

The spectral layout an object was built for, the peer of [`_context_grid`](@ref).
"""
function _context_layout end

_context_grid(field::AbstractField) = field_grid(field)
_context_layout(field::AbstractField) = field_layout(field)


"""
    _check_matching_context(a, b)

Check that two participants in a spectral operation were built for the same base and spectral layout,
throwing otherwise. This is the package's one context predicate: an operation that mixes objects from
different domains is rejected at the entry point rather than producing a wrong answer or failing later
inside a kernel.
"""
function _check_matching_context(a, b)
  _context_grid(a) == _context_grid(b) ||
    throw(ArgumentError("$(nameof(typeof(a))) and $(nameof(typeof(b))) were built for different grids"))
  _context_layout(a) == _context_layout(b) ||
    throw(ArgumentError("$(nameof(typeof(a))) and $(nameof(typeof(b))) were built for different spectral layouts"))
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

The arguments are:
- `physical`: the field supplying the real-space storage array to plan against.
- `spectral`: the field supplying the real-to-complex Fourier coefficient array.
- `fft_flags`: an optional backend-specific FFT planner flag.
- `fft_timelimit`: the planner time limit, used when `fft_flags` is given.
Only the spatial dimensions `field_layout(physical).fft_dims` are transformed; tensor-fiber dimensions are left untransformed.

!!! warning "CPU planner choice: the default `ESTIMATE` can badly mis-plan single-precision transforms"
    On the CPU the plans are `FFTW` plans, and with `fft_flags` unset `FFTW` picks the algorithm by its
    built-in `ESTIMATE` heuristic — instant, but a guess. On some CPUs that guess is far off: measured
    on a Zen 5 desktop, the `Float32` transforms ran 2.3–5.1× slower than a timed plan at ``256^3``
    (the widest gap single-threaded, narrowing as threads are added),
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

Transform a field from spectral space to physical space in place, returning the modified
`physical` destination.

Here `physical` is the destination, `spectral` is the source, and `transform_plans` provides the inverse FFT plan.

!!! warning "The source is used as scratch"
    The inverse transform uses `spectral` as scratch space and may overwrite it: on return its
    coefficients are left in an undefined state (the `FFTW` CPU backend destroys them — complex-to-real
    transforms have no input-preserving algorithm in the multidimensional case; some GPU backends
    happen to preserve them, but this is not guaranteed). Use the allocating [`to_physical`](@ref)
    when `spectral` must be preserved.
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

Transform a field from physical space to spectral space in place, returning the modified
`spectral` destination.

Here `spectral` is the destination, `physical` is the source, and `transform_plans` provides the forward FFT plan.

!!! warning "The source may be overwritten"
    The forward transform may overwrite `physical` on some backends (for example rocFFT reserves the
    right to use real-to-complex inputs as scratch); the `FFTW` CPU backend preserves it, but do not
    rely on the source surviving. Use the allocating [`to_spectral`](@ref) when `physical` must be
    preserved.
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

The forward transform is **unnormalized** and the inverse carries the ``1/N`` (``N`` the number of grid
points) — the `AbstractFFTs` convention. Every normalization elsewhere in the package is stated against
it: the mean is the zero coefficient over ``N``, adding a constant scales only that coefficient by
``N``, and the Parseval sums carry ``1/N^2``.

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

# The zero (DC) Fourier coefficient and its scale. These state invariant 4 and the rfft storage
# layout — where the constant lives and what it is scaled by — so they are representation facts,
# not algebra, and every module that reads the DC mode (the constant-add family, the spectral
# reductions) takes them from here.

"""
    _spectral_constant_scale(field::AbstractFieldSpectral)

Return `prod(grid_size)`, the factor by which a physical constant scales the zero Fourier coefficient under the unnormalized-forward FFT convention. Adding a real constant in spectral representation multiplies it by this scale and writes only the zero mode.
"""
_spectral_constant_scale(field::AbstractFieldSpectral{T}) where {T<:AbstractFloat} = prod(T.(field_grid(field).grid_size))


"""
    _spectral_zero_mode_data(field::ScalarFieldSpectral)

Return a `1×1×1` view of the zero Fourier coefficient of a scalar field in spectral representation; constant additions in spectral representation write only here.
"""
_spectral_zero_mode_data(field::ScalarFieldSpectral) = view(field_data(field), 1:1, 1:1, 1:1)


"""
    _spectral_zero_mode_component_data(field::VectorFieldSpectral, component)
    _spectral_zero_mode_component_data(field::TensorFieldSpectral{2}, first_index,
                                       second_index)

Return a `1×1×1` view of the zero Fourier coefficient of one component of a vector or second-order tensor field in spectral representation.
"""
_spectral_zero_mode_component_data(field::VectorFieldSpectral, component) = view(field_data(field), 1:1, 1:1, 1:1, component:component)

_spectral_zero_mode_component_data(field::TensorFieldSpectral{2}, first_index, second_index) = view(field_data(field), 1:1, 1:1, 1:1, first_index:first_index, second_index:second_index)


####################################################
#        Spectral kernels — the protocol           #
####################################################

"""
    SpectralKernel{T}

Supertype of every spectral kernel: a coefficientwise multiplier applied as the product
``\\hat f \\hat g``, in whichever storage its symbol admits. [`Convolution`](@ref "Convolution")
defines the concrete classes under [Kernel storage classes](@ref) — `StoredKernel` holding one
coefficient per mode, `SeparableKernel` holding per-axis factors, `RadialKernel` holding the symbol
itself, and `ProductKernel` holding two factors unmultiplied — and they differ only in cost, never in
meaning. This supertype and the two generics below live here so that every module which applies a
kernel — `Convolution`, [`DifferentialOperators`](@ref "DifferentialOperators"),
[`Reductions`](@ref "Reductions") — can name one type, whichever of them is included first.

A field in spectral representation is **not** a kernel. The two hold identical data, so nothing but a
type can say which role is meant, and the distinction is load-bearing: the coefficientwise reciprocal
of a kernel is the kernel that deconvolves by it, while the same operation on a field is one the
package does not define. Wrap a field of coefficients in `StoredKernel` to declare the role, which is
what `materialize_kernel` returns.

A concrete kernel implements two methods: [`_kernel_data`](@ref), returning the multiplier it
contributes to a fused pass, and [`_check_kernel_compatibility`](@ref), checking it against the field
it is applied to.
"""
abstract type SpectralKernel{T} end


"""
    _kernel_data(kernel)

The coefficientwise multiplier a kernel contributes to a fused pass. A kernel held as a field yields
its stored array; a compressed kernel yields whatever its own pass consumes — typically a lazy
expression over the wavenumber arrays, never a materialized field.
"""
function _kernel_data end


"""
    _check_kernel_compatibility(field, kernel)

Check that `kernel` was built for `field`'s base and spectral layout, throwing if not. Each storage
class checks whatever it stored.
"""
function _check_kernel_compatibility end


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
A convenience constructor `FieldSpectralMultipliers(field)` builds both families from the field's grid and layout with the correct Nyquist treatment, and carries
its own docstring below.

Whether the arrays were derived from the grid or supplied by the caller is recorded in the type, as a
final `Canonical` parameter: the convenience constructor marks them canonical, the explicit forms do
not. It is in the type rather than in a field because it decides, statically, whether two multiplier
sets provably hold the same coordinates — two canonical sets on a matching grid and layout are derived
the same way from the same inputs, so they agree by construction. That is what lets `convolve` collapse
two radial kernels into one without testing anything at run time, and it is why a caller supplying its
own coordinates (a sheared, time-dependent set, say) never has its kernels merged with one built on the
grid's own wavenumbers.
"""
struct FieldSpectralMultipliers{T<:AbstractFloat, K1<:AbstractArray{T, 1}, K2<:AbstractArray{T, 1}, K3<:AbstractArray{T, 1}, S1<:AbstractArray{T, 1}, S2<:AbstractArray{T, 1}, S3<:AbstractArray{T, 1}, Canonical} 
  grid::Grid3D{T}
  fourier_layout::RealFourierLayout
  wavenumber_1::K1
  wavenumber_2::K2
  wavenumber_3::K3
  squared_wavenumber_1::S1
  squared_wavenumber_2::S2
  squared_wavenumber_3::S3

  # `canonical` records whether these arrays were DERIVED from the grid (the convenience constructor)
  # or supplied by a caller (the six-array form, which validates lengths only). It is a type parameter
  # rather than a field because it decides, statically, whether two multiplier sets provably hold the
  # same coordinates — which is what lets `convolve` collapse two radial kernels without a runtime test.
  function FieldSpectralMultipliers(canonical::Bool, grid::Grid3D{T}, fourier_layout::RealFourierLayout,
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

    return new{T, K1, K2, K3, S1, S2, S3, canonical}(grid, fourier_layout, wavenumber_1, wavenumber_2, wavenumber_3, squared_wavenumber_1, squared_wavenumber_2, squared_wavenumber_3)
  end
end


# The public six-array form on a grid and layout. It forwards with `canonical = false`, because it
# validates the arrays' LENGTHS and not their values: a caller may legitimately supply coordinates that
# are not the grid's (a sheared, time-dependent set), and a kernel built on those must not be merged
# with one built on the grid's own wavenumbers.
FieldSpectralMultipliers(grid::Grid3D{T}, fourier_layout::RealFourierLayout,
    wavenumber_1::AbstractArray{T, 1}, wavenumber_2::AbstractArray{T, 1}, wavenumber_3::AbstractArray{T, 1},
    squared_wavenumber_1::AbstractArray{T, 1}, squared_wavenumber_2::AbstractArray{T, 1},
    squared_wavenumber_3::AbstractArray{T, 1}) where {T<:AbstractFloat} =
  FieldSpectralMultipliers(false, grid, fourier_layout, wavenumber_1, wavenumber_2, wavenumber_3,
                           squared_wavenumber_1, squared_wavenumber_2, squared_wavenumber_3)


function FieldSpectralMultipliers(field::AbstractFieldSpectral{T}, wavenumber_1::AbstractArray{T, 1}, wavenumber_2::AbstractArray{T, 1}, wavenumber_3::AbstractArray{T, 1},
    squared_wavenumber_1::AbstractArray{T, 1}, squared_wavenumber_2::AbstractArray{T, 1}, squared_wavenumber_3::AbstractArray{T, 1}) where {T<:AbstractFloat}
  
  return FieldSpectralMultipliers(false, field_grid(field), field_layout(field), wavenumber_1, wavenumber_2, wavenumber_3, squared_wavenumber_1, squared_wavenumber_2, squared_wavenumber_3)
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

  return FieldSpectralMultipliers(true, grid, fourier_layout,
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

_context_grid(multipliers::FieldSpectralMultipliers) = multipliers.grid
_context_layout(multipliers::FieldSpectralMultipliers) = multipliers.fourier_layout


"""
    _check_multipliers_compatibility(field::AbstractFieldSpectral,
                                     multipliers::FieldSpectralMultipliers)

Check that a spectral-space `field` and `multipliers` share scalar type, grid, Fourier layout, and
storage family. Returns `nothing` or throws.
"""
function _check_multipliers_compatibility(field::AbstractFieldSpectral, multipliers::FieldSpectralMultipliers)
  field_scalar_type(field) == _multipliers_scalar_type(multipliers) || throw(ArgumentError("field and spectral multipliers scalar types must be equal"))
  _check_field_matches_context(field, multipliers)
  # STORAGE FAMILY, for the reason `_check_same_domain` states: without it the pair passes every
  # structural test and fails later, so the error depends on the operation and the backend. Measured
  # before it was added: a device field with host multipliers reached `gradient`, `laplacian`,
  # `divergence`, `helmholtz_projection` and `radial_spectrum`, and each died with a `KernelError` from
  # KernelAbstractions declining to launch over mixed arrays — the right outcome for the wrong reason,
  # exactly as `inner` refused only because CUBLAS lacked a mixed-pointer method.
  # Compared inline rather than through a new helper: decision 53's derived per-module baseline counts
  # every method this module owns, and two one-line helpers moved `Fields` from 105 to 107 — the guard
  # doing its job. Any of the six wavenumber vectors names the family the multipliers were built on.
  Base.typename(typeof(parent(field_data(field)))).wrapper ===
      Base.typename(typeof(parent(multipliers.wavenumber_1))).wrapper ||
    throw(ArgumentError("field and spectral multipliers must live in the same storage family; got " *
                        "$(Base.typename(typeof(parent(field_data(field)))).wrapper) and " *
                        "$(Base.typename(typeof(parent(multipliers.wavenumber_1))).wrapper)"))
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
Laplacian and the inverse Laplacian. The Helmholtz projection does **not** use it: decision 42 gave the
projector the derivative family's own ``a \\cdot a`` denominator, so its pass takes the three derivative
wavenumbers and squares them inline.

Lazy on purpose: returning the unfused `Broadcasted` lets callers compose it into their own broadcasts
over the coefficients ``\\hat s`` of a field in spectral representation
(``-|k|^2 \\hat s`` for the Laplacian, ``-\\hat s / |k|^2`` for its inverse, …) without ever materializing the ``O(N^3)`` array. That keeps those
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

Broadcast style for fields in physical-space representation (``N = 3 + R``, with ``R`` the tensor order). A field stands for its storage array inside a broadcast, and the style materializes the result back into a physical-space field. See also `FieldSpectralBroadcastStyle`.
"""
struct FieldPhysicalBroadcastStyle{N} <: Base.Broadcast.AbstractArrayStyle{N} end

"""
    FieldSpectralBroadcastStyle{N}

Broadcast style for fields in spectral representation (``N = 3 + R``, with ``R`` the tensor order); the spectral counterpart of `FieldPhysicalBroadcastStyle`. Combining the two styles is an error, so physical and spectral representations never mix in one broadcast.
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

Set the number of threads `FFTW` uses and return `n`, effective for plans built afterwards (`FFTW`
fixes the count at plan construction). Code that parallelizes across many fields at once
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
**new HDF5 group** `name` under `parent`, returning the group it created. Use it to checkpoint a field for restart, save a full-resolution
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

The arguments are:
- `parent` — an open HDF5 `File` or `Group` to create the new subgroup under.
- `name` — the name of the group to create.
- `field` — the field to write.

Provided by a package extension, so it is available only when `HDF5` is loaded.
"""
function write_field end


"""
    read_field(parent::HDF5.H5DataStore, name::AbstractString)

Reconstruct the field written by [`write_field`](@ref) from the HDF5 group `name` under `parent`,
dispatching on the stored `type` attribute to return the reconstructed field in the matching type
(`ScalarFieldPhysical`, `VectorFieldSpectral`, …). The reload is **exact** — the array data, the [`Grid3D`](@ref) geometry, the
Fourier layout, the element type, and the tensor order are recovered bit-for-bit.

The reconstructed field is a host (CPU) object regardless of where the written one lived; move it to a
device afterward if needed.

Here `parent` is an open HDF5 `File` or `Group` holding the group, and `name` is the name (or path) of
that field group under `parent`.

Provided by a package extension, so it is available only when `HDF5` is loaded.
"""
function read_field end


end # module Fields
