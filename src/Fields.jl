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
    `TensorFieldSpectral{R}`). The two lowest orders carry bespoke names — `ScalarFieldPhysical` and
    `VectorFieldPhysical` rather than `TensorFieldPhysical{0}` and `{1}` — because they are the
    overwhelmingly common cases and read better short. The tensor order `R` is a type parameter of
    every field type all the same, so that is a naming convenience over a uniform design, not a break
    in it.
  * **Persistence** — [`write_field`](@ref) and [`read_field`](@ref) map a field to and from one
    self-describing HDF5 group (methods load with the `HDF5` package, as a weak-dependency extension).
  * **Transforms** — [`FieldTransformPlans`](@ref) holds the FFT plans, and [`to_physical`](@ref) and
    [`to_spectral`](@ref) move a field between the two representations. The allocating forms preserve
    their input, and the plain in-place `!` forms may overwrite the source — except the four-argument
    scratch arity of `to_physical!`, which guarantees preservation by consuming a caller-supplied
    scratch instead; `set_fft_threads!` sets the thread count `FFTW` bakes into plans built
    afterwards.
  * **Spectral multipliers** — [`FieldSpectralMultipliers`](@ref) holds the wavenumber arrays the
    differential operators apply as spectral multipliers.
  * **Spectral kernels** — [`SpectralKernel`](@ref) is the supertype of every coefficientwise
    multiplier a `convolve`-style operation can apply, whatever storage it uses — including the stored
    class, which wraps a field of coefficients. It lives here, rather than with the kernels themselves,
    so every module that accepts one names a single type; [`Convolution`](@ref "Convolution") defines
    the concrete classes.
  * **Allocation** — [`similar_field`](@ref) returns uninitialized storage carrying a reference field's
    representation, tensor order, grid and backend, which is how an operation builds scratch or a
    result without naming a concrete field type.
  * **Moving between storage families** — [`adapt`](@ref) moves a field, its multipliers, its kernels
    or its transform plans between host and device memory (or any other `Adapt.jl` storage family),
    preserving the element type and everything else the object carries. Operations refuse a pair that
    disagrees rather than transferring one to meet the other, so that the cost of crossing the bus is
    always visible at the call site.
  * **Broadcasting** — a dotted assignment writes into the destination's storage, an out-of-place dotted
    expression allocates a like field in the same representation, and physical and spectral
    representations cannot be mixed in one broadcast.
"""
module Fields

using StaticArrays: SVector, SMatrix, SArray
using AbstractFFTs
using LinearAlgebra
import FFTW
# Imported before extending, per invariant 7. `adapt` is the ecosystem-standard way to move a struct
# holding arrays between storage families, and extending `adapt_structure` is its sanctioned hook.
import Adapt: adapt, adapt_structure
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
    _validate_fft_dims(d::NTuple{3, Int})

Check whether `d` is a valid ordering of the three spatial Fourier-transform dimensions. Returns `true` or `false`.
"""
_validate_fft_dims(d::NTuple{3, Int}) = (1 ≤ d[1] ≤ 3) && (1 ≤ d[2] ≤ 3) && (1 ≤ d[3] ≤ 3) && (d[1] != d[2]) && (d[1] != d[3]) && (d[2] != d[3])


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
- `grid_size::NTuple{3, Int}` — the number of grid points in each spatial direction.
- `domain_size::NTuple{3, T}` — the length of the domain in each spatial direction.
- `grid_spacing::NTuple{3, T}` — the spacing between adjacent grid points in each spatial direction.
  Stored rather than recomputed, but **not independent** — it must equal `domain_size ./ grid_size`,
  which the four-argument constructor enforces.
- `origin::NTuple{3, T}` — the physical coordinates of the first grid point.

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
- `fft_dims` — the tuple of transformed dimensions passed to the FFT planner, whose first entry is the
  halved (folded) axis.
"""
struct RealFourierLayout
  fft_dims::NTuple{3, Int}
  
  function RealFourierLayout(fft_dims::NTuple{3, Int} = (1, 2, 3))
    _validate_fft_dims(fft_dims) || throw(ArgumentError("fft_dims must be a permutation of (1, 2, 3), got $(fft_dims)"))
    return new(fft_dims)
  end
end


"""
    _rfft_shape(grid_size::NTuple{3, Int}, fft_dims::NTuple{3, Int})

Return the shape of the nonredundant real-to-complex Fourier representation of a three-dimensional real field.

Here `grid_size` is the physical grid size and `fft_dims` is the order of transformed dimensions. The dimension `fft_dims[1]` is the real-FFT half
dimension: it is stored with length `grid_size[fft_dims[1]] ÷ 2 + 1`, while the other dimensions keep their physical-grid lengths.

Returns a three-tuple giving the spectral array size.
"""
_rfft_shape(grid_size::NTuple{3, Int}, fft_dims::NTuple{3, Int}) = ntuple(d -> d == fft_dims[1] ? (grid_size[d] ÷ 2 + 1) : grid_size[d], 3)




########################################
#        Abstract Field Interface       #
########################################

"""
    AbstractFieldPhysical{T, R}

Abstract supertype for fields represented by values in physical space.

Here `T<:AbstractFloat` is the real scalar type associated with the field and `R` is the tensor order stored as an integer value parameter.
Concrete subtypes provide the actual storage and metadata. The generic field interface obtains `T` and `R` through [`field_scalar_type`](@ref)
and [`field_tensor_order`](@ref), and obtains the stored data through [`field_data`](@ref).

!!! note "A field in physical representation owns its storage"
    A concrete subtype's constructor **rejects borrowed storage** — a `SubArray` anywhere in the parent
    chain — so slicing a larger preallocated buffer and wrapping the view will throw. Ownership is what
    makes aliasing safe by construction: two sections can then share memory only by being backed by the
    same array, which every fused pass handles correctly. Allocate with [`similar_field`](@ref), or
    `copy` the slice. Storage stays otherwise free: `Array`, `CuArray`, `ROCArray` and a `reshape` of
    any of them all own their memory and are accepted.
"""
abstract type AbstractFieldPhysical{T<:AbstractFloat, R} <: AbstractFiberSection{T, R} end


"""
    AbstractFieldSpectral{T, R}

Abstract supertype for fields represented by Fourier coefficients in spectral space.

Here `T<:AbstractFloat` is the real scalar type associated with the field and `R` is the tensor order stored as an integer value parameter.
Concrete subtypes provide the actual storage and metadata. The generic field interface obtains `T` and `R` through [`field_scalar_type`](@ref)
and [`field_tensor_order`](@ref), and obtains the stored data through [`field_data`](@ref).

!!! note "A field in spectral representation owns its storage"
    A concrete subtype's constructor **rejects borrowed storage** — a `SubArray` anywhere in the parent
    chain — so slicing a larger preallocated buffer and wrapping the view will throw. Ownership is what
    makes aliasing safe by construction: two sections can then share memory only by being backed by the
    same array, which every fused pass handles correctly. Allocate with [`similar_field`](@ref), or
    `copy` the slice. Storage stays otherwise free: `Array`, `CuArray`, `ROCArray` and a `reshape` of
    any of them all own their memory and are accepted.
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

Return the storage shape of a field represented in nonredundant real-to-complex spectral space.

The arguments are:
- `grid` — the [`Grid3D`](@ref) whose point count sets the spatial dimensions.
- `fourier_layout` — the [`RealFourierLayout`](@ref) deciding which axis carries the halved real
  transform.
- `R` — the tensor order, whose fiber dimensions are appended after the spatial ones.
"""
spectral_field_shape(grid::Grid3D, fourier_layout::RealFourierLayout, ::Val{R}) where {R} = (_rfft_shape(grid.grid_size, fourier_layout.fft_dims)..., fiber_shape(Val(R))...)


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

    ScalarFieldPhysical(
      family::Type{<:AbstractArray},
      grid::Grid3D{T},
      fourier_layout::RealFourierLayout = RealFourierLayout(),
    ) where {T<:AbstractFloat}

Scalar field in physical representation, stored as its values on a three-dimensional physical grid.

The fields are
- `values_at_grid` — the real scalar values, one per grid point.
- `grid` — the [`Grid3D`](@ref) on which the values are sampled.
- `fourier_layout` — the [`RealFourierLayout`](@ref) used when transforming the field.

The function constructor constructs a scalar field in physical representation by sampling a real-valued function on a three-dimensional physical grid.
The arguments are:

- `f` — the sampled function, called as `f(x, y, z)` at each grid point.
- `grid` — the `Grid3D` the values are sampled on.
- `fourier_layout` — the `RealFourierLayout` used when transforming the field.
- `array_type` — the array type the sampled values are stored in (`Array` on the host, a
  device array such as `CuArray` or `ROCArray` to build the field on a GPU).

The allocating constructor takes a storage *family* — `Array`, `CuArray`, `ROCArray` — in place of the array, and produces **uninitialized** value storage itself, on that family's backend, shaped by the grid and the tensor order. It exists for a caller holding only the domain context and no array or field to copy from; with a field in hand, [`similar_field`](@ref) is the shorter spelling. The element type is the grid's: a bare family takes it from there, a parameterized one must agree with it (a mixed pair is refused, never converted), and a complex parameter is always refused — complex storage is representation detail, not a user-facing element type.

Broadcasting over scalar fields in physical representation is lifted to `values_at_grid`. Thus dotted assignments such as `@. destination = a - b + c`
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


    ScalarFieldSpectral(
      family::Type{<:AbstractArray},
      grid::Grid3D{T},
      fourier_layout::RealFourierLayout = RealFourierLayout(),
    ) where {T<:AbstractFloat}

Scalar field in spectral representation, stored as its nonredundant real-to-complex Fourier coefficients.

The fields are
- `fourier_coefficients` — the complex Fourier coefficients, in real-FFT storage.
- `grid` — the [`Grid3D`](@ref) of the physical domain the coefficients represent.
- `fourier_layout` — the [`RealFourierLayout`](@ref) giving the transformed dimensions and the real-FFT half dimension.

The coefficient array has shape `spectral_field_shape(grid, fourier_layout, Val(0))`.
The dimension `fourier_layout.fft_dims[1]` is the real-FFT half dimension.

The allocating constructor takes a storage *family* — `Array`, `CuArray`, `ROCArray` — in place of the array, and produces **uninitialized** coefficient storage (element type `Complex{T}`) itself, on that family's backend, shaped by the grid, the layout and the tensor order. It exists for a caller holding only the domain context and no array or field to copy from; with a field in hand, [`similar_field`](@ref) is the shorter spelling. The element type is the grid's: a bare family takes it from there, a parameterized one must agree with it (a mixed pair is refused, never converted), and a complex parameter is always refused — complex storage is representation detail, not a user-facing element type.

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


    VectorFieldPhysical(
      family::Type{<:AbstractArray},
      grid::Grid3D{T},
      fourier_layout::RealFourierLayout = RealFourierLayout(),
    ) where {T<:AbstractFloat}

Vector field in physical representation, stored as its components on a three-dimensional physical grid.

The fields are
- `values_at_grid` — the real vector components, stored `values_at_grid[i, j, k, α]` with ``\\alpha = 1, 2, 3``.
- `grid` — the [`Grid3D`](@ref) on which the values are sampled.
- `fourier_layout` — the [`RealFourierLayout`](@ref) used when transforming the field.

The function constructor constructs a vector field in physical representation by sampling a real vector-valued function on a three-dimensional physical grid.
The arguments are:

- `f` — the sampled function, called as `f(x, y, z)`; it must return a three-component
  indexable object.
- `grid` — the `Grid3D` the values are sampled on.
- `fourier_layout` — the `RealFourierLayout` used when transforming the field.
- `array_type` — the array type the sampled values are stored in (`Array` on the host, a
  device array such as `CuArray` or `ROCArray` to build the field on a GPU).

The allocating constructor takes a storage *family* — `Array`, `CuArray`, `ROCArray` — in place of the array, and produces **uninitialized** value storage itself, on that family's backend, shaped by the grid and the tensor order. It exists for a caller holding only the domain context and no array or field to copy from; with a field in hand, [`similar_field`](@ref) is the shorter spelling. The element type is the grid's: a bare family takes it from there, a parameterized one must agree with it (a mixed pair is refused, never converted), and a complex parameter is always refused — complex storage is representation detail, not a user-facing element type.

Broadcasting over vector fields in physical representation is lifted to `values_at_grid`. Thus dotted assignments such as `@. destination = a - b + c`
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


    VectorFieldSpectral(
      family::Type{<:AbstractArray},
      grid::Grid3D{T},
      fourier_layout::RealFourierLayout = RealFourierLayout(),
    ) where {T<:AbstractFloat}

Vector field in spectral representation, stored as its nonredundant real-to-complex Fourier coefficients.

The fields are
- `fourier_coefficients` — the complex vector Fourier coefficients in real-FFT storage, component index last, `fourier_coefficients[i, j, k, α]` with ``\\alpha = 1, 2, 3``; its spatial part has shape `spectral_field_shape(grid, fourier_layout, Val(0))` and the whole array `spectral_field_shape(grid, fourier_layout, Val(1))`.
- `grid` — the [`Grid3D`](@ref) of the physical domain the coefficients represent.
- `fourier_layout` — the [`RealFourierLayout`](@ref); its `fft_dims[1]` is the real-FFT half dimension.

The allocating constructor takes a storage *family* — `Array`, `CuArray`, `ROCArray` — in place of the array, and produces **uninitialized** coefficient storage (element type `Complex{T}`) itself, on that family's backend, shaped by the grid, the layout and the tensor order. It exists for a caller holding only the domain context and no array or field to copy from; with a field in hand, [`similar_field`](@ref) is the shorter spelling. The element type is the grid's: a bare family takes it from there, a parameterized one must agree with it (a mixed pair is refused, never converted), and a complex parameter is always refused — complex storage is representation detail, not a user-facing element type.

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


    TensorFieldPhysical{R}(
      family::Type{<:AbstractArray},
      grid::Grid3D{T},
      fourier_layout::RealFourierLayout = RealFourierLayout(),
    ) where {T<:AbstractFloat}

Tensor field of order ``R \\ge 2`` in physical representation, stored as its components on a three-dimensional physical grid.

The fields are
- `values_at_grid` — the real tensor components, stored `values_at_grid[i, j, k, α₁, ..., αᵣ]` with each tensor index of length `3`.
- `grid` — the [`Grid3D`](@ref) on which the values are sampled.
- `fourier_layout` — the [`RealFourierLayout`](@ref) used when transforming the field.

The array has shape `physical_field_shape(grid, Val(R))`. The constructors without explicit `{R}` infer `R = N - 3` from the array dimension `N`.

The function constructor constructs a tensor field of order ``R \\ge 2`` in physical representation by sampling a real tensor-valued function on a three-dimensional physical grid.
The arguments are:

- `f` — the sampled function, called as `f(x, y, z)`; it must return an indexable object with
  tensor-fiber shape `fiber_shape(Val(R))`.
- `grid` — the `Grid3D` the values are sampled on.
- `fourier_layout` — the `RealFourierLayout` used when transforming the field.
- `array_type` — the array type the sampled values are stored in (`Array` on the host, a
  device array such as `CuArray` or `ROCArray` to build the field on a GPU).

The allocating constructor takes a storage *family* — `Array`, `CuArray`, `ROCArray` — in place of the array, and produces **uninitialized** value storage itself, on that family's backend, shaped by the grid and the tensor order. It exists for a caller holding only the domain context and no array or field to copy from; with a field in hand, [`similar_field`](@ref) is the shorter spelling. The element type is the grid's: a bare family takes it from there, a parameterized one must agree with it (a mixed pair is refused, never converted), and a complex parameter is always refused — complex storage is representation detail, not a user-facing element type.

Broadcasting over tensor fields in physical representation is lifted to `values_at_grid`. Thus dotted assignments such as `@. destination = a - b + c`
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


    TensorFieldSpectral{R}(
      family::Type{<:AbstractArray},
      grid::Grid3D{T},
      fourier_layout::RealFourierLayout = RealFourierLayout(),
    ) where {T<:AbstractFloat}

Tensor field of order ``R \\ge 2`` in spectral representation, stored as its nonredundant real-to-complex Fourier coefficients.

The fields are
- `fourier_coefficients` — the complex tensor Fourier coefficients in real-FFT storage, tensor indices last, `fourier_coefficients[i, j, k, α₁, ..., αᵣ]` with each of length `3`; its spatial part has shape `spectral_field_shape(grid, fourier_layout, Val(0))` and the whole array `spectral_field_shape(grid, fourier_layout, Val(R))`.
- `grid` — the [`Grid3D`](@ref) of the physical domain the coefficients represent.
- `fourier_layout` — the [`RealFourierLayout`](@ref); its `fft_dims[1]` is the real-FFT half dimension. The constructors without an explicit `{R}` infer the tensor order ``R = N - 3`` from the stored array's dimension count `N`.

The allocating constructor takes a storage *family* — `Array`, `CuArray`, `ROCArray` — in place of the array, and produces **uninitialized** coefficient storage (element type `Complex{T}`) itself, on that family's backend, shaped by the grid, the layout and the tensor order. It exists for a caller holding only the domain context and no array or field to copy from; with a field in hand, [`similar_field`](@ref) is the shorter spelling. The element type is the grid's: a bare family takes it from there, a parameterized one must agree with it (a mixed pair is refused, never converted), and a complex parameter is always refused — complex storage is representation detail, not a user-facing element type.

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




####################################################
#   Allocating constructors — storage from context #
####################################################
#
# Construction from metadata alone (decision 74): every constructor above takes a storage array the
# caller must already have produced on the right backend, and `similar_field` needs an existing
# field to copy context from. A frame-holding consumer that deliberately owns no field-sized arrays
# (the design the lazy kernels enable) therefore had no sanctioned route to its first field. These
# methods close it: the same six constructors accept a storage FAMILY — `Array`, `CuArray`,
# `ROCArray` — in place of the array, and produce the storage themselves. The element type comes
# from the grid, which already carries it; the backend comes as a generic array type, the
# decision-63 argument (dispatch on a generic target gains both vendors without depending on
# either).

"""
    _allocated_field_storage(family, ::Type{S}, shape)

Produce an uninitialized array of element type `S` and shape `shape` in the storage `family` —
the storage-producing step of the allocating `(family, grid[, layout])` constructors. The family
is reduced to its unparameterized wrapper first, so `Array` and `Array{Float64}` allocate
identically once [`_check_family_element_type`](@ref) has vetted the declared element type.
"""
function _allocated_field_storage(family::Type{<:AbstractArray}, ::Type{S}, shape::Dims) where {S}
  wrapper = Base.typename(family).wrapper
  return wrapper{S}(undef, shape)
end


"""
    _check_family_element_type(family, grid)

Refuse a storage family whose declared element type disagrees with the grid's — a mixed pair is
refused, never converted (invariant 14) — or is complex, because a field's element type is its
real scalar type and complex storage is representation detail the spectral constructors allocate
themselves (invariant 2). A bare family (`Array`, `ROCArray`) declares nothing and passes, the
element type coming from the grid.
"""
function _check_family_element_type(family::Type{<:AbstractArray}, ::Grid3D{T}) where {T<:AbstractFloat}
  declared = eltype(family)
  declared === Any && return nothing               # bare family: the grid supplies the element type
  declared <: Complex &&
    throw(ArgumentError("the storage family declares the complex element type $(declared); a field's " *
                        "element type is its real scalar type $(T) — spectral storage is allocated as " *
                        "Complex{$(T)} internally"))
  declared === T ||
    throw(ArgumentError("the storage family declares element type $(declared), but the grid carries " *
                        "$(T); allocation does not convert between precisions"))
  return nothing
end


function ScalarFieldPhysical(family::Type{<:AbstractArray}, grid::Grid3D{T},
    fourier_layout::RealFourierLayout = RealFourierLayout()) where {T<:AbstractFloat}
  _check_family_element_type(family, grid)
  return ScalarFieldPhysical(_allocated_field_storage(family, T, physical_field_shape(grid, Val(0))),
                             grid, fourier_layout)
end

function VectorFieldPhysical(family::Type{<:AbstractArray}, grid::Grid3D{T},
    fourier_layout::RealFourierLayout = RealFourierLayout()) where {T<:AbstractFloat}
  _check_family_element_type(family, grid)
  return VectorFieldPhysical(_allocated_field_storage(family, T, physical_field_shape(grid, Val(1))),
                             grid, fourier_layout)
end

function TensorFieldPhysical{R}(family::Type{<:AbstractArray}, grid::Grid3D{T},
    fourier_layout::RealFourierLayout = RealFourierLayout()) where {R, T<:AbstractFloat}
  _check_family_element_type(family, grid)
  return TensorFieldPhysical{R}(_allocated_field_storage(family, T, physical_field_shape(grid, Val(R))),
                                grid, fourier_layout)
end

TensorFieldPhysical(family::Type{<:AbstractArray}, grid::Grid3D{T},
    fourier_layout::RealFourierLayout = RealFourierLayout()) where {T<:AbstractFloat} =
  TensorFieldPhysical{2}(family, grid, fourier_layout)

function ScalarFieldSpectral(family::Type{<:AbstractArray}, grid::Grid3D{T},
    fourier_layout::RealFourierLayout = RealFourierLayout()) where {T<:AbstractFloat}
  _check_family_element_type(family, grid)
  return ScalarFieldSpectral(
    _allocated_field_storage(family, Complex{T}, spectral_field_shape(grid, fourier_layout, Val(0))),
    grid, fourier_layout)
end

function VectorFieldSpectral(family::Type{<:AbstractArray}, grid::Grid3D{T},
    fourier_layout::RealFourierLayout = RealFourierLayout()) where {T<:AbstractFloat}
  _check_family_element_type(family, grid)
  return VectorFieldSpectral(
    _allocated_field_storage(family, Complex{T}, spectral_field_shape(grid, fourier_layout, Val(1))),
    grid, fourier_layout)
end

function TensorFieldSpectral{R}(family::Type{<:AbstractArray}, grid::Grid3D{T},
    fourier_layout::RealFourierLayout = RealFourierLayout()) where {R, T<:AbstractFloat}
  _check_family_element_type(family, grid)
  return TensorFieldSpectral{R}(
    _allocated_field_storage(family, Complex{T}, spectral_field_shape(grid, fourier_layout, Val(R))),
    grid, fourier_layout)
end

TensorFieldSpectral(family::Type{<:AbstractArray}, grid::Grid3D{T},
    fourier_layout::RealFourierLayout = RealFourierLayout()) where {T<:AbstractFloat} =
  TensorFieldSpectral{2}(family, grid, fourier_layout)


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

This is used by out-of-place field broadcasting and by allocating algebraic operations. With no
reference field in hand — only a grid, a layout and a backend — use the allocating type
constructors instead, which take a storage family in place of the array
([`ScalarFieldPhysical`](@ref) and its five siblings).

!!! note "Deliberately not an extension of `Base.similar`"
    `Base.similar`'s second positional argument means an element type or a set of dimensions, and
    here it is the tensor order — so the name would be borrowed while the convention that gives it
    meaning was broken. Worse, its most idiomatic spelling would mislead: `similar(u, Float32)` reads
    as a request for single precision, and this package never changes precision implicitly (a mixed
    pair is refused rather than promoted, and even the explicit [`adapt`](@ref) moves storage only).
    The `data` form is not an allocation at all — it wraps storage you supply, which `Base.similar`
    never does — so half of this operation could not carry the name in any case.
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
    _similar_physical_field(reference::AbstractFieldSpectral, data)

Construct a field represented in physical space with storage array `data` and metadata copied from the spectral-space `reference`.
"""
function _similar_physical_field end

_similar_physical_field(reference::ScalarFieldSpectral{T}, data::AbstractArray{T, 3}) where {T<:AbstractFloat} =
  ScalarFieldPhysical(data, field_grid(reference), field_layout(reference))

_similar_physical_field(reference::VectorFieldSpectral{T}, data::AbstractArray{T, 4}) where {T<:AbstractFloat} =
  VectorFieldPhysical(data, field_grid(reference), field_layout(reference))

_similar_physical_field(reference::TensorFieldSpectral{R, T}, data::AbstractArray{T, N}) where {R, T<:AbstractFloat, N} =
  TensorFieldPhysical{R}(data, field_grid(reference), field_layout(reference))


"""
    _similar_spectral_field(reference::AbstractFieldPhysical, data)

Construct a field represented in spectral space with storage array `data` and metadata copied from the physical-space `reference`.
"""
function _similar_spectral_field end

_similar_spectral_field(reference::ScalarFieldPhysical{T}, data::AbstractArray{Complex{T}, 3}) where {T<:AbstractFloat} =
  ScalarFieldSpectral(data, field_grid(reference), field_layout(reference))

_similar_spectral_field(reference::VectorFieldPhysical{T}, data::AbstractArray{Complex{T}, 4}) where {T<:AbstractFloat} =
  VectorFieldSpectral(data, field_grid(reference), field_layout(reference))

_similar_spectral_field(reference::TensorFieldPhysical{R, T}, data::AbstractArray{Complex{T}, N}) where {R, T<:AbstractFloat, N} =
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
may differ). Shared body for the same-representation domain checks; the entry points that call it (`_check_field_domain_compatibility`, `_check_field_compatibility`) are each restricted to a single representation, so a physical/spectral pair has no matching method and is rejected.
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
    _check_field_compatibility(a::AbstractFieldPhysical, b::AbstractFieldPhysical)
    _check_field_compatibility(a::AbstractFieldSpectral, b::AbstractFieldSpectral)

Check that two fields in the same representation share scalar type, tensor order, grid, Fourier
layout, and storage family.

This is the check for operations that require fully matching operands. Returns `nothing` or throws.
"""
function _check_field_compatibility end

function _check_field_compatibility(a::AbstractFieldPhysical, b::AbstractFieldPhysical)
  _check_same_domain(a, b)
  _same_tensor_order(a, b) || throw(ArgumentError("field tensor orders must be equal"))
  return nothing
end

function _check_field_compatibility(a::AbstractFieldSpectral, b::AbstractFieldSpectral)
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

The Fourier layout an object was built for, the peer of [`_context_grid`](@ref).
"""
function _context_layout end

_context_grid(field::AbstractField) = field_grid(field)
_context_layout(field::AbstractField) = field_layout(field)


"""
    _check_matching_context(a, b)

Check that two participants in a spectral operation were built for the same base and Fourier layout,
throwing otherwise. This is the package's one context predicate: an operation that mixes objects from
different domains is rejected at the entry point rather than producing a wrong answer or failing later
inside a kernel.
"""
function _check_matching_context(a, b)
  _context_grid(a) == _context_grid(b) ||
    throw(ArgumentError("$(nameof(typeof(a))) and $(nameof(typeof(b))) were built for different grids"))
  _context_layout(a) == _context_layout(b) ||
    throw(ArgumentError("$(nameof(typeof(a))) and $(nameof(typeof(b))) were built for different Fourier layouts"))
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
- `physical` — the field supplying the real-space storage array to plan against.
- `spectral` — the field supplying the real-to-complex Fourier coefficient array.
- `fft_flags` — an optional backend-specific FFT planner flag.
- `fft_timelimit` — the planner time limit, used when `fft_flags` is given.
Only the spatial dimensions `field_layout(physical).fft_dims` are transformed; tensor-fiber dimensions are left untransformed.

!!! warning "The default `ESTIMATE` planner can badly mis-plan single-precision CPU transforms"
    On the CPU the plans are `FFTW` plans, and with `fft_flags` unset `FFTW` picks the algorithm by its
    built-in `ESTIMATE` heuristic — instant, but a guess. On some CPUs that guess is far off: measured
    on a Zen 5 desktop, the `Float32` transforms ran 2.3–5.1× slower than a timed plan at ``256^3``
    (the widest gap single-threaded, narrowing as threads are added),
    and at ``512^3`` still slower than `Float64` serially and at two threads, the gap closing (and
    reversing) only as more threads are added. For a
    long CPU run, pass `fft_flags = FFTW.MEASURE` (or `FFTW.PATIENT`): the one-time timed plan search
    costs seconds and removes the guess. `MEASURE` **overwrites both reference arrays while
    planning**, so construct the plans on scratch or zero-filled fields before seeding data. The
    setting is CPU-specific — the GPU FFT libraries take no planner flag and are unaffected — and
    the default stays `ESTIMATE` because it is instant, deterministic, and right for tests and short
    sessions.

The fields are
- `grid::G` — the [`Grid3D`](@ref) for which the plans were constructed.
- `fourier_layout::L` — the [`RealFourierLayout`](@ref) for which the plans were constructed.
- `plan_forward_fft::PF` — the plan transforming physical values to spectral coefficients, for **one
  component**.
- `plan_inverse_fft::PI` — the plan transforming spectral coefficients to physical values, for one
  component.
- `fft_flags::Union{Nothing, UInt32}` — the planner flag these plans were built with, or `nothing` for
  the default. It is retained rather than merely used, so that rebuilding these plans in another
  storage family can replay the intent they were created with — see [`adapt`](@ref).
- `fft_timelimit::Float64` — the planner time limit paired with `fft_flags`, retained for the same
  reason.
- `component_scratch::S` — a component-sized buffer, or `nothing`. It exists only where a device
  backend would refuse a component's starting address, and is `nothing` for every grid whose
  component offsets align — which includes every grid a solver is likely to run.

The plans are backend-, array-type- and scalar-type-specific, and **carry no tensor order**: a real
Fourier transform on a periodic box is defined on the box, and a rank-``R`` field is that transform
applied along a fiber, so one pair of plans serves scalar, vector and tensor fields alike. Construct a
separate `FieldTransformPlans` object for each CPU/GPU backend and element type, but not for each
tensor order.
"""
struct FieldTransformPlans{T<:AbstractFloat, PF, PI, G<:Grid3D{T}, L<:RealFourierLayout, S}
  grid::G
  fourier_layout::L
  # The plans transform ONE component. A real Fourier transform on a periodic box is defined on the
  # box, and a rank-R field is that transform applied along a fiber, so the plan is a property of the
  # base and carries no tensor order: one pair serves every rank. Six type parameters, and any site
  # matching them POSITIONALLY must be updated together with this line (decision 76; decision 70 is
  # the precedent for that hazard).
  plan_forward_fft::PF
  plan_inverse_fft::PI
  # The planner request is retained so that moving these plans to another storage family can rebuild
  # them with the intent they were created with. Without it a rebuild would silently fall back to
  # `ESTIMATE`, which finding (h) in docs/PERFORMANCE.md records as capable of mis-planning a
  # single-precision transform badly — a performance regression with no wrong answer, the kind that
  # hides. Two plain fields rather than type parameters: they are read only when rebuilding, never on
  # a transform, so they must not participate in dispatch.
  fft_flags::Union{Nothing, UInt32}
  fft_timelimit::Float64
  # A component of a rank-R field begins at element offset `(c-1)*prod(grid_size)`, and a transform
  # library may refuse a pointer whose alignment differs from the one it planned for. On the host
  # that is answered by planning with `FFTW.UNALIGNED` and costs no memory; a device backend has no
  # such flag, so a misaligned grid there transforms through this component-sized buffer instead.
  # It is `nothing` — and free — whenever the offsets align, which every production grid does.
  component_scratch::S
end


"""
    _component_offsets_align(grid, layout, ::Type{T}) -> (host_aligned, device_aligned)

Report whether the component views of a rank-`R > 0` field begin at offsets a transform library will
accept, given a plan built for one component. Component `c` starts `(c-1)` whole components into the
storage, so the question is entirely a property of the base and the element type.

The two answers differ because the two backends ask different questions. A **host** (`FFTW`) plan
records the alignment *class* of the pointer it was planned for and refuses a different one, for the
real and the complex array alike; requiring each component stride to be a multiple of 64 bytes is
conservative — it preserves whatever class the base pointer has — and every production grid satisfies
it. A **device** (`cuFFT`) plan needs only the real pointer aligned to its complex element, which
reduces to the real component stride being even, i.e. to the grid not being odd on all three axes.
"""
function _component_offsets_align(grid::Grid3D, layout::RealFourierLayout, ::Type{T}) where {T<:AbstractFloat}
  physical_stride = prod(physical_field_shape(grid, Val(0)))
  spectral_stride = prod(spectral_field_shape(grid, layout, Val(0)))
  host = (physical_stride * sizeof(T)) % 64 == 0 && (spectral_stride * sizeof(Complex{T})) % 64 == 0
  device = iseven(physical_stride)
  return (host, device)
end


function FieldTransformPlans(physical::AbstractFieldPhysical{T, R}, spectral::AbstractFieldSpectral{T, R}; fft_flags = nothing, fft_timelimit = Inf) where {T<:AbstractFloat, R}
  field_grid(physical)   == field_grid(spectral)   || throw(ArgumentError("field grids must be equal"))
  field_layout(physical) == field_layout(spectral) || throw(ArgumentError("field Fourier layouts must be equal"))

  grid, layout = field_grid(physical), field_layout(physical)
  fft_dims = layout.fft_dims

  # One component, not one field: the prototypes carry the base shape at tensor order zero, so the
  # resulting plans serve a scalar, a vector and a tensor field alike.
  physical_prototype = similar(field_data(physical), T, physical_field_shape(grid, Val(0)))
  spectral_prototype = similar(field_data(spectral), Complex{T}, spectral_field_shape(grid, layout, Val(0)))

  host_aligned, device_aligned = _component_offsets_align(grid, layout, T)
  on_host = physical_prototype isa Array
  # Planner flags are an `FFTW` concept and a device backend rejects them, so the misalignment answer
  # is the flag on the host and the buffer on a device. Requesting `UNALIGNED` keeps the caller's own
  # planner effort: dropping the `ESTIMATE` bit would silently select `MEASURE`, which is zero.
  requested = isnothing(fft_flags) ? FFTW.ESTIMATE : UInt32(fft_flags)
  effective_flags = (on_host && !host_aligned) ? (requested | FFTW.UNALIGNED) : requested

  plan_forward_fft, plan_inverse_fft = if on_host
    (plan_rfft(physical_prototype, fft_dims; flags = effective_flags, timelimit = fft_timelimit),
     plan_irfft(spectral_prototype, grid.grid_size[fft_dims[1]], fft_dims; flags = effective_flags, timelimit = fft_timelimit))
  else
    (plan_rfft(physical_prototype, fft_dims),
     plan_irfft(spectral_prototype, grid.grid_size[fft_dims[1]], fft_dims))
  end

  component_scratch = (!on_host && !device_aligned) ? similar(physical_prototype) : nothing

  return FieldTransformPlans{T, typeof(plan_forward_fft), typeof(plan_inverse_fft), typeof(grid), typeof(layout), typeof(component_scratch)}(
    grid, layout, plan_forward_fft, plan_inverse_fft,
    isnothing(fft_flags) ? nothing : UInt32(fft_flags), Float64(fft_timelimit), component_scratch)
end


"""
    _component_view(data, ::Val{R}, component::Int)

One component of a section's storage, as a three-dimensional array over the base, so a rank-agnostic
plan can be applied one component at a time. The fiber-last layout of invariant 3 makes each component
contiguous, which is what makes the slice a plain strided view.

Indexing the fiber axes DIRECTLY, rather than reshaping the fiber into one trailing component axis
first, is what keeps the transforms allocation-free. A `reshape` of an `Array` returns a new `Array`
sharing the data, and that wrapper is heap-allocated: two of them per transform, one for the source
and one for the destination, cost a constant 128 bytes per call whatever the rank or the grid — small
enough to sit under `test/allocations.jl`'s field-sized threshold, and reported from a consumer whose
own contract asserts literal zero. A rank-0 section is its own component and is returned untouched,
which is also what it was before the plans became rank-agnostic.
"""
@inline _component_view(data::AbstractArray, ::Val{0}, ::Int) = data
@inline function _component_view(data::AbstractArray, ::Val{R}, component::Int) where {R}
  fiber_index = CartesianIndices(ntuple(_ -> 3, Val(R)))[component]
  return view(data, :, :, :, Tuple(fiber_index)...)
end


# The forward transform reads the REAL component, so a device grid needing staging copies the source
# in; the inverse writes the real component, so it transforms into the buffer and copies out.
@inline function _forward_components!(spectral_data, plan, physical_data, ::Val{R}, scratch) where {R}
  for component in 1:3^R
    source_view = _component_view(physical_data, Val(R), component)
    destination_view = _component_view(spectral_data, Val(R), component)
    if scratch === nothing
      mul!(destination_view, plan, source_view)
    else
      copyto!(scratch, source_view)
      mul!(destination_view, plan, scratch)
    end
  end
  return spectral_data
end


@inline function _inverse_components!(physical_data, plan, spectral_data, ::Val{R}, scratch) where {R}
  for component in 1:3^R
    source_view = _component_view(spectral_data, Val(R), component)
    destination_view = _component_view(physical_data, Val(R), component)
    if scratch === nothing
      mul!(destination_view, plan, source_view)
    else
      mul!(scratch, plan, source_view)
      copyto!(destination_view, scratch)
    end
  end
  return physical_data
end


"""
    to_physical!(
      physical::AbstractFieldPhysical{T, R},
      spectral::AbstractFieldSpectral{T, R},
      transform_plans::FieldTransformPlans{T},
    ) where {T<:AbstractFloat, R}
    to_physical!(
      physical::AbstractFieldPhysical{T, R},
      spectral::AbstractFieldSpectral{T, R},
      transform_plans::FieldTransformPlans{T},
      spectral_scratch::AbstractFieldSpectral{T, R},
    ) where {T<:AbstractFloat, R}

Transform a field from spectral space to physical space in place, returning the modified
`physical` destination.

The three-argument form consumes its source; the four-argument form **preserves it**, at the price of
one extra pass — the coefficients are copied into `spectral_scratch` and the transform runs from
there, so `spectral` returns bitwise-unchanged with nothing allocated. It is the allocation-free
member of the preserving contract that the allocating [`to_physical`](@ref) offers by copying into a
fresh field: reach for it when the spectral coefficients are a state you keep — a solver's resolved
state, a field transformed to physical space more than once — and the loop must not allocate.

The arguments are:
- `physical` — the field that receives the transformed values.
- `spectral` — the source coefficients. The three-argument form may overwrite them as scratch; the
  four-argument form leaves them bitwise-unchanged.
- `transform_plans` — the [`FieldTransformPlans`](@ref) supplying the inverse FFT plan.
- `spectral_scratch` — four-argument form only: a spectral field on the same grid and layout whose
  storage the transform consumes in `spectral`'s place; on return its coefficients are undefined,
  exactly as the three-argument form leaves its source. It must not alias `spectral` — the same
  storage would defeat the preservation the argument exists to buy, so that call is refused rather
  than defined.

!!! warning "The source is used as scratch"
    The inverse transform uses its input as scratch space and may overwrite it: on return the
    coefficients it ran from are left in an undefined state (the `FFTW` CPU backend destroys them —
    complex-to-real transforms have no input-preserving algorithm in the multidimensional case; some
    GPU backends happen to preserve them, but this is not guaranteed). In the three-argument form that
    input is `spectral` itself — use the four-argument form, or the allocating
    `to_physical`, when `spectral` must be preserved.
"""
function to_physical!(physical::AbstractFieldPhysical{T, R}, spectral::AbstractFieldSpectral{T, R}, transform_plans::FieldTransformPlans{T}) where {T<:AbstractFloat, R}
  _check_field_matches_context(physical, transform_plans)
  _check_field_matches_context(spectral, transform_plans)

  _inverse_components!(field_data(physical), transform_plans.plan_inverse_fft, field_data(spectral),
                       Val(R), transform_plans.component_scratch)

  return physical
end


function to_physical!(physical::AbstractFieldPhysical{T, R}, spectral::AbstractFieldSpectral{T, R}, transform_plans::FieldTransformPlans{T}, spectral_scratch::AbstractFieldSpectral{T, R}) where {T<:AbstractFloat, R}
  _check_field_matches_context(physical, transform_plans)
  _check_field_matches_context(spectral, transform_plans)
  _check_field_matches_context(spectral_scratch, transform_plans)
  # Aliasing is refused, not defined: with shared storage the copy is a no-op and the transform then
  # consumes `spectral` itself — silently violating the one contract this arity exists to provide.
  # Same-array is the ONLY way two sections can share memory (the constructors reject borrowed
  # storage, decision 59), so this cheap check is exhaustive.
  field_data(spectral_scratch) === field_data(spectral) &&
    throw(ArgumentError("spectral_scratch must not alias spectral: a shared array would let the " *
                        "transform consume the source this argument exists to preserve"))

  # A plain `copyto!` over the storage, deliberately: the cost of preservation is exactly one extra
  # read+write of the coefficients, and nothing else.
  copyto!(field_data(spectral_scratch), field_data(spectral))
  _inverse_components!(field_data(physical), transform_plans.plan_inverse_fft, field_data(spectral_scratch),
                       Val(R), transform_plans.component_scratch)

  return physical
end


"""
    to_spectral!(
      spectral::AbstractFieldSpectral{T, R},
      physical::AbstractFieldPhysical{T, R},
      transform_plans::FieldTransformPlans{T},
    ) where {T<:AbstractFloat, R}

Transform a field from physical space to spectral space in place, returning the modified
`spectral` destination.

The arguments are:
- `spectral` — the field that receives the transformed coefficients.
- `physical` — the source values, which the transform may overwrite as scratch.
- `transform_plans` — the [`FieldTransformPlans`](@ref) supplying the forward FFT plan.

The forward transform is **unnormalized** and the inverse carries the ``1/N`` (``N`` the number of grid
points) — the `AbstractFFTs` convention. Every normalization elsewhere in the package is stated against
it: the mean is the zero coefficient over ``N``, adding a constant scales only that coefficient by
``N``, and the Parseval sums carry ``1/N^2``.

!!! warning "The source may be overwritten"
    The forward transform may overwrite `physical` on some backends (for example rocFFT reserves the
    right to use real-to-complex inputs as scratch); the `FFTW` CPU backend preserves it, but do not
    rely on the source surviving. Use the allocating [`to_spectral`](@ref) when `physical` must be
    preserved.
"""
function to_spectral!(spectral::AbstractFieldSpectral{T, R}, physical::AbstractFieldPhysical{T, R}, transform_plans::FieldTransformPlans{T}) where {T<:AbstractFloat, R}
  _check_field_matches_context(spectral, transform_plans)
  _check_field_matches_context(physical, transform_plans)

  _forward_components!(field_data(spectral), transform_plans.plan_forward_fft, field_data(physical),
                       Val(R), transform_plans.component_scratch)

  return spectral
end


"""
    to_physical(
      spectral::AbstractFieldSpectral{T, R},
      transform_plans::FieldTransformPlans{T},
    ) where {T<:AbstractFloat, R}

Allocating form of [`to_physical!`](@ref): allocate the result and return it. A field in spectral
representation gives its physical representation on the same grid.

Unlike the three-argument in-place form this one **preserves `spectral`** — it transforms a copy —
which is the reason to reach for it: the inverse real transform may consume its input as scratch, and
whether it does is backend-specific, so a caller that still needs the coefficients must not rely on
that form. A loop that must not allocate gets the same preservation from the four-argument
`to_physical!` with a caller-supplied scratch field instead. Here `spectral` is the source and
`transform_plans` provides the inverse FFT plan.
"""
function to_physical(spectral::AbstractFieldSpectral{T, R}, transform_plans::FieldTransformPlans{T}) where {T<:AbstractFloat, R}
  values_at_grid = similar(field_data(spectral), T, physical_field_shape(field_grid(spectral), Val(R)))
  physical = _similar_physical_field(spectral, values_at_grid)
  # The inverse transform may overwrite its input (see to_physical!); copy the
  # coefficients so the caller's field is preserved.
  spectral_preserved = similar_field(spectral, copy(field_data(spectral)))
  return to_physical!(physical, spectral_preserved, transform_plans)
end


"""
    to_spectral(
      physical::AbstractFieldPhysical{T, R},
      transform_plans::FieldTransformPlans{T},
    ) where {T<:AbstractFloat, R}

Allocating form of [`to_spectral!`](@ref): allocate the result and return it. A field in physical
representation gives its spectral representation on the same grid.

Unlike the in-place form this one **preserves `physical`** — it transforms a copy — which is the reason
to reach for it: the forward transform may consume its input as scratch on some backends, so a caller
that still needs the values must not rely on the in-place form. Here `physical` is the source and `transform_plans` provides the forward FFT plan.
"""
function to_spectral(physical::AbstractFieldPhysical{T, R}, transform_plans::FieldTransformPlans{T}) where {T<:AbstractFloat, R}
  fourier_coefficients = similar(field_data(physical), Complex{T}, spectral_field_shape(field_grid(physical), field_layout(physical), Val(R)))
  spectral = _similar_spectral_field(physical, fourier_coefficients)
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

Supertype of every spectral kernel: a coefficientwise multiplier applied as the product ``\\hat f \\hat g`` of a field's coefficients ``\\hat f`` and the kernel's own multiplier ``\\hat g``, in whichever storage its symbol admits. [`Convolution`](@ref "Convolution")
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

Check that `kernel` was built for `field`'s base and Fourier layout, throwing if not. Each storage
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

    FieldSpectralMultipliers(field::AbstractFieldSpectral{T}) where {T<:AbstractFloat}

One-dimensional Fourier wavenumber arrays for the operators applied coefficientwise in spectral
representation — derivatives, the Laplacian, and the Helmholtz projection.

The arguments are:
- `grid`, `fourier_layout` — the [`Grid3D`](@ref) and [`RealFourierLayout`](@ref) the multipliers are
  built for. The two-argument forms take them from `field` instead.
- `wavenumber_1`, `wavenumber_2`, `wavenumber_3` — the per-axis **derivative** wavenumbers, written
  ``a`` where the operators' formulas need to name them apart from the true wavenumber ``k``. They are
  the physical (angular) wavenumbers used for first derivatives, through multiplication by
  ``\\mathrm{i} a``, and they carry invariant 5's Nyquist zeroing.
- `squared_wavenumber_1`, `squared_wavenumber_2`, `squared_wavenumber_3` — the per-axis squared
  wavenumbers, used for the Laplacian through multiplication by ``-k^2``. These keep the **true**
  ``k^2`` at the Nyquist frequency, which is why the two families are stored rather than derived from
  each other.
- `field` — in the one-argument convenience form, the field whose grid and layout the multipliers are
  built from; both families are then derived with the correct Nyquist treatment and allocated on that
  field's storage backend.

Each array runs along one spatial axis in the FFT frequency ordering of `fourier_layout`; the half axis `fourier_layout.fft_dims[1]` stores only the nonnegative frequencies.
The arrays must live on storage (CPU or GPU) matching the fields the multipliers are applied to.

The two array families are stored independently rather than squaring one to obtain the other,
because on even grids they use different conventions for the Nyquist mode (the highest representable frequency).
The explicit forms take both families from the caller and check only their lengths; the convenience
form derives them, which is what makes them canonical (see the `Canonical` parameter below).

Every argument above is stored under its own name. Six further fields — `wavenumber_view_1..3` and
`squared_wavenumber_view_1..3` — are derived rather than passed: each is one of the six vectors
pre-oriented as a 3-D view along its own axis, holding no data of its own, so that a broadcast-route
operator never rebuilds a `reshape` per call (decision 70). They are internal; read them through
`_wavenumber_broadcast_view` and `_squared_wavenumber_broadcast` rather than directly.

In the convenience form the wavenumbers are the physical angular wavenumbers ``k = 2\\pi n / L`` along
each axis, with ``L`` the domain length and ``n`` running over the FFT frequency indices. On an
even-length axis the highest stored mode is the Nyquist mode: its first-derivative wavenumber is set to
zero, so that derivatives of real fields stay real, while its squared wavenumber keeps the true
``k^2``, so that the Laplacian and Poisson-type solves stay correct. On an odd-length axis there is no
exact Nyquist mode and no special treatment is applied.

Whether the arrays were derived from the grid or supplied by the caller is recorded in the type, as a
final `Canonical` parameter: the convenience constructor marks them canonical, the explicit forms do
not. It is in the type rather than in a field because it decides, statically, whether two multiplier
sets provably hold the same coordinates — two canonical sets on a matching grid and layout are derived
the same way from the same inputs, so they agree by construction. That is what lets `convolve` collapse
two radial kernels into one without testing anything at run time, and it is why a caller supplying its
own coordinates (a sheared, time-dependent set, say) never has its kernels merged with one built on the
grid's own wavenumbers.
"""
struct FieldSpectralMultipliers{T<:AbstractFloat, K1<:AbstractArray{T, 1}, K2<:AbstractArray{T, 1}, K3<:AbstractArray{T, 1}, S1<:AbstractArray{T, 1}, S2<:AbstractArray{T, 1}, S3<:AbstractArray{T, 1}, V1<:AbstractArray{T, 3}, V2<:AbstractArray{T, 3}, V3<:AbstractArray{T, 3}, W1<:AbstractArray{T, 3}, W2<:AbstractArray{T, 3}, W3<:AbstractArray{T, 3}, Canonical} 
  grid::Grid3D{T}
  fourier_layout::RealFourierLayout
  wavenumber_1::K1
  wavenumber_2::K2
  wavenumber_3::K3
  squared_wavenumber_1::S1
  squared_wavenumber_2::S2
  squared_wavenumber_3::S3

  # The same six arrays ORIENTED along their own axis — shapes `(n,1,1)`, `(1,n,1)`, `(1,1,n)` — held
  # so the broadcast-route operators do not rebuild them per call. A `reshape` allocates a 48-byte
  # array header, and the two helpers below built three of them each invocation: 144 B per call of
  # `laplacian!`, `inverse_laplacian!`, `divergence!` and `exponential_convolve!`, byte-constant in the
  # grid and therefore pure per-step garbage in a solver's hot loop (raised by the consuming solver
  # 2026-08-23, measured at 1152 B per RK3 step). They alias their vectors rather than copying, so this
  # costs six array headers per multiplier set — built once, where a grid is.
  wavenumber_view_1::V1
  wavenumber_view_2::V2
  wavenumber_view_3::V3
  squared_wavenumber_view_1::W1
  squared_wavenumber_view_2::W2
  squared_wavenumber_view_3::W3

  # THREE SITES MATCH THESE PARAMETERS POSITIONALLY and must be updated together whenever one is
  # added: `_is_canonical` below, `adapt_structure`'s signature (decision 68), and `Convolution`'s
  # static collapse of two radial kernels (decision 61), which spells the canonical case as a trailing
  # `true`. Adding the six oriented views moved `Canonical` six places and broke all three at once —
  # loudly, at load, which is the only reason this comment is a warning rather than a post-mortem.
  #
  # `Canonical` records whether these arrays were DERIVED from the grid (the convenience constructor)
  # or supplied by a caller (the six-array form, which validates lengths only). It is a type parameter
  # rather than a field because it decides, statically, whether two multiplier sets provably hold the
  # same coordinates — which is what lets `convolve` collapse two radial kernels without a runtime test.
  #
  # It is taken as `Val{Canonical}` rather than as a `Bool` so the flag is in the type domain at the
  # CALL, not lifted out of a value inside `new`. Every construction here passes a literal, which
  # inference folded anyway; `adapt` does not — it forwards the flag from the object it is rebuilding —
  # and there the lift silently failed, leaving the rebuilt type's last parameter free and taking
  # `RadialKernel` and `ProductKernel` with it. Binding the parameter in the caller's signature was not
  # enough: constant propagation does not reach through this constructor's validation. Measured, both
  # ways, on 2026-08-17.
  function FieldSpectralMultipliers(::Val{Canonical}, grid::Grid3D{T}, fourier_layout::RealFourierLayout,
      wavenumber_1::K1, wavenumber_2::K2, wavenumber_3::K3,
      squared_wavenumber_1::S1, squared_wavenumber_2::S2, squared_wavenumber_3::S3) where {T<:AbstractFloat,
      K1<:AbstractArray{T, 1}, K2<:AbstractArray{T, 1}, K3<:AbstractArray{T, 1}, S1<:AbstractArray{T, 1}, S2<:AbstractArray{T, 1}, S3<:AbstractArray{T, 1}, Canonical}

    spectral_spatial_shape = spectral_field_shape(grid, fourier_layout, Val(0))

    length(wavenumber_1) == spectral_spatial_shape[1] || throw(DimensionMismatch("length(wavenumber_1) must match the first spectral spatial dimension"))
    length(wavenumber_2) == spectral_spatial_shape[2] || throw(DimensionMismatch("length(wavenumber_2) must match the second spectral spatial dimension"))
    length(wavenumber_3) == spectral_spatial_shape[3] || throw(DimensionMismatch("length(wavenumber_3) must match the third spectral spatial dimension"))
    length(squared_wavenumber_1) == spectral_spatial_shape[1] || throw(DimensionMismatch("length(squared_wavenumber_1) must match the first spectral spatial dimension"))
    length(squared_wavenumber_2) == spectral_spatial_shape[2] || throw(DimensionMismatch("length(squared_wavenumber_2) must match the second spectral spatial dimension"))
    length(squared_wavenumber_3) == spectral_spatial_shape[3] || throw(DimensionMismatch("length(squared_wavenumber_3) must match the third spectral spatial dimension"))

    view_1 = reshape(wavenumber_1, length(wavenumber_1), 1, 1)
    view_2 = reshape(wavenumber_2, 1, length(wavenumber_2), 1)
    view_3 = reshape(wavenumber_3, 1, 1, length(wavenumber_3))
    squared_view_1 = reshape(squared_wavenumber_1, length(squared_wavenumber_1), 1, 1)
    squared_view_2 = reshape(squared_wavenumber_2, 1, length(squared_wavenumber_2), 1)
    squared_view_3 = reshape(squared_wavenumber_3, 1, 1, length(squared_wavenumber_3))
    return new{T, K1, K2, K3, S1, S2, S3, typeof(view_1), typeof(view_2), typeof(view_3),
               typeof(squared_view_1), typeof(squared_view_2), typeof(squared_view_3), Canonical}(
      grid, fourier_layout, wavenumber_1, wavenumber_2, wavenumber_3,
      squared_wavenumber_1, squared_wavenumber_2, squared_wavenumber_3,
      view_1, view_2, view_3, squared_view_1, squared_view_2, squared_view_3)
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
  FieldSpectralMultipliers(Val(false), grid, fourier_layout, wavenumber_1, wavenumber_2, wavenumber_3,
                           squared_wavenumber_1, squared_wavenumber_2, squared_wavenumber_3)


function FieldSpectralMultipliers(field::AbstractFieldSpectral{T}, wavenumber_1::AbstractArray{T, 1}, wavenumber_2::AbstractArray{T, 1}, wavenumber_3::AbstractArray{T, 1},
    squared_wavenumber_1::AbstractArray{T, 1}, squared_wavenumber_2::AbstractArray{T, 1}, squared_wavenumber_3::AbstractArray{T, 1}) where {T<:AbstractFloat}
  
  return FieldSpectralMultipliers(Val(false), field_grid(field), field_layout(field), wavenumber_1, wavenumber_2, wavenumber_3, squared_wavenumber_1, squared_wavenumber_2, squared_wavenumber_3)
end


# The convenience constructor. Its docstring is merged into the type's, which is where every other
# multi-constructor type in the package documents its constructors.
function FieldSpectralMultipliers(field::AbstractFieldSpectral{T}) where {T<:AbstractFloat}
  grid = field_grid(field)
  fourier_layout = field_layout(field)
  half_dimension = fourier_layout.fft_dims[1]
  reference = field_data(field)

  wavenumber_1, squared_wavenumber_1 = _axis_wavenumber_arrays(reference, grid.grid_size[1], grid.domain_size[1], 1 == half_dimension)
  wavenumber_2, squared_wavenumber_2 = _axis_wavenumber_arrays(reference, grid.grid_size[2], grid.domain_size[2], 2 == half_dimension)
  wavenumber_3, squared_wavenumber_3 = _axis_wavenumber_arrays(reference, grid.grid_size[3], grid.domain_size[3], 3 == half_dimension)

  return FieldSpectralMultipliers(Val(true), grid, fourier_layout,
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

Reshape the per-axis derivative wavenumber array for axis `1`, `2` or `3` so it broadcasts against
the three spatial dimensions of a field in spectral representation. Used by the first-derivative
differential operators (gradient, divergence, curl), applied as spectral multipliers.
"""
_wavenumber_broadcast_view(multipliers::FieldSpectralMultipliers, ::Val{1}) = multipliers.wavenumber_view_1
_wavenumber_broadcast_view(multipliers::FieldSpectralMultipliers, ::Val{2}) = multipliers.wavenumber_view_2
_wavenumber_broadcast_view(multipliers::FieldSpectralMultipliers, ::Val{3}) = multipliers.wavenumber_view_3


"""
    _squared_wavenumber_broadcast(multipliers::FieldSpectralMultipliers)

Return the total squared wavenumber ``|k|^2 = k_1^2 + k_2^2 + k_3^2`` as a **lazy** `Broadcasted` over
the three per-axis squared-wavenumber vectors (reshaped to the three spatial dimensions). Used by the
Laplacian and the inverse Laplacian. The Helmholtz projection does **not** use it: the
projector divides by the derivative family's own ``a \\cdot a``, so its pass takes the three derivative
wavenumbers and squares them inline.

Lazy on purpose: returning the unfused `Broadcasted` lets callers compose it into their own broadcasts
over the coefficients ``\\hat s`` of a field in spectral representation
(``-|k|^2 \\hat s`` for the Laplacian, ``-\\hat s / |k|^2`` for its inverse, …) without ever materializing the ``O(N^3)`` array. That keeps those
operators allocation-free in place: no ``O(N^3)`` ``|k|^2`` scratch is built, which on the GPU would
otherwise accumulate in the memory pool on each call.
"""
function _squared_wavenumber_broadcast(multipliers::FieldSpectralMultipliers)
  return Base.broadcasted(+, multipliers.squared_wavenumber_view_1,
                             multipliers.squared_wavenumber_view_2,
                             multipliers.squared_wavenumber_view_3)
end



##############################
#        Broadcasting        #
##############################

"""
    FieldPhysicalBroadcastStyle{N}

Broadcast style for fields in physical representation (``N = 3 + R``, with ``R`` the tensor order). A field stands for its storage array inside a broadcast, and the style materializes the result back into a physical-space field. See also `FieldSpectralBroadcastStyle`.
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

Check, during field broadcasting, that `argument` is compatible with `destination`: same-representation fields must pass `_check_field_compatibility`; mixing physical and spectral representations throws; non-field arguments (real numbers, plain arrays) are accepted. Recurses into the operands of a `Broadcasted` argument.
"""
_check_broadcast_field_compatibility(destination::AbstractFieldPhysical, field::AbstractFieldPhysical) = _check_field_compatibility(destination, field)

_check_broadcast_field_compatibility(destination::AbstractFieldSpectral, field::AbstractFieldSpectral) = _check_field_compatibility(destination, field)

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


###################################################
#   Moving between storage families (Adapt.jl)    #
###################################################

"""
    adapt(storage, object)

Move a section — a field or point-values — or its multipliers, its kernels, its point set or its
transform plans to another **storage family**, host to device or device to host, returning an object
of the same kind whose arrays live in the requested family. The element type is preserved exactly.

A **storage family** is where an array lives — host memory, or one vendor's device memory. Use this
when something built on one family has to be used on another. Two fields combine arithmetically only
when they share a family and an element type, and a mixed pair is **refused** rather than promoted or
transferred, because a copy across the bus is a cost that belongs at the call site; `adapt` is that
call site. The argument `storage` is the target array type (`Array`, `CuArray`, `ROCArray`, …) or any
other `Adapt.jl` adaptor, and `object` is what to move — a field or point-values (the sections), or
one of the companions a section is useless without: multipliers, a kernel, or transform plans.

The whole surface a solver needs is covered: the six field types, the point-value types, a
`PointSet`, a [`FieldSpectralMultipliers`](@ref), the four spectral-kernel classes (`StoredKernel`,
`SeparableKernel`, `RadialKernel` and `ProductKernel`, all subtypes of [`SpectralKernel`](@ref)), and
`FieldTransformPlans`. Everything the moved object carries besides its storage — the grid, the Fourier
layout, the origin, the tensor order — is preserved by construction, since it is rebuilt through the
same allocator the package uses everywhere else.

!!! warning "Moving to the family an object is already in returns it unchanged"
    Following `Adapt.jl` and `convert`, adapting to the family an object already belongs to is the
    identity: it returns the very same object, sharing storage, rather than a copy. Write `copy` when
    a distinct object is what is wanted.

!!! warning "Transform plans are rebuilt, not moved, and that costs a planning pass"
    An FFT plan is a compiled schedule tied to one storage family and cannot be transferred, so
    adapting a `FieldTransformPlans` **constructs new plans** on the target. It needs nothing from the
    caller: the plans carry their own grid, layout and element type — and no tensor order, since
    decision 76 — so the two arrays
    the planner needs as witnesses are allocated internally and released immediately. The planner
    request the plans were built with is replayed, with one exception. Planner flags are an `FFTW`
    concept — `cuFFT` rejects them outright — so a move to any non-host family does **not apply** them
    when building the new plan, but the returned plans still **record** the original flags, so a later
    move back to the host rebuilds them with the intent they were created with.

Element-type conversion is deliberately **not** part of this: a transfer that silently changed
precision would change what a solver computes. No operation in this package converts precision today.

# Examples
```julia
u_device      = adapt(CuArray, u)                 # host  -> device
u_host        = adapt(Array, u_device)            # device -> host
mult_device   = adapt(CuArray, multipliers)       # a field's multipliers must share its family
plans_device  = adapt(CuArray, plans)             # rebuilt on the device
```
"""
adapt


"""
    _storage_prototype(to, ::Type{S})

Return an empty array of element type `S` in the storage family `to`, to be grown with `similar`.

This is how [`adapt`](@ref) allocates a transform plan's witness arrays on the target without a host
round trip: adapting a zero-length array costs nothing and yields a prototype of the right family,
where allocating a full-size host array and adapting it would copy an entire field's worth of
uninitialised memory across the bus.
"""
_storage_prototype(to, ::Type{S}) where {S} = adapt(to, Array{S}(undef, 0))


"""
    _physical_field_of_order(data, grid, layout, ::Val{R})
    _spectral_field_of_order(data, grid, layout, ::Val{R})

Wrap `data` as the physical (or spectral) field type of tensor order `R` on `grid` and `layout`.

These pick the concrete type from the order alone, which `similar_field` cannot do because it copies
its metadata from a reference field. [`adapt`](@ref) rebuilding a `FieldTransformPlans` has no such
reference — it has only the plans' own grid, layout and element type, decision 76 having removed the
tensor order from `FieldTransformPlans` entirely — so it needs this form.
"""
_physical_field_of_order(data, grid, layout, ::Val{0}) = ScalarFieldPhysical(data, grid, layout)
_physical_field_of_order(data, grid, layout, ::Val{1}) = VectorFieldPhysical(data, grid, layout)
_physical_field_of_order(data, grid, layout, ::Val{R}) where {R} = TensorFieldPhysical{R}(data, grid, layout)

_spectral_field_of_order(data, grid, layout, ::Val{0}) = ScalarFieldSpectral(data, grid, layout)
_spectral_field_of_order(data, grid, layout, ::Val{1}) = VectorFieldSpectral(data, grid, layout)
_spectral_field_of_order(data, grid, layout, ::Val{R}) where {R} = TensorFieldSpectral{R}(data, grid, layout)


"""
    adapt!(destination, source)

Move `source` into `destination`, which already holds storage in the family you want, and return
`destination`.

Use this in-place form when `destination` is already allocated; the allocating [`adapt`](@ref) returns
a fresh result instead. There is no target argument here because there is nothing to name: the
destination already **is** the target family, so the two cannot disagree.

`destination` and `source` are two sections of the same kind — two fields in the same representation,
two point-value sections, or two point sets — agreeing in element type, tensor order, grid and Fourier
layout, and differing at most in the storage family they live in. Everything except the family must
match, because this moves storage and nothing else: precision is not converted here, exactly as it is
not by `adapt`. A pair that differs in representation has no method rather than an error message,
since a physical field and a spectral one are not the same section. Passing one section as both
arguments is a no-op, and a `source` already in `destination`'s family is an ordinary copy rather than
an error, so generic code need not ask which side of the bus it is on.

The reason to reach for it is the return trip. Allocating the destination is most of what a
device-to-host move costs — measured on an RTX 5070 Ti at ``256^3``, `Float64`, an allocating move
runs at ``5.1`` GiB/s against the ``19.0`` GiB/s the same transfer reaches into a destination that
already exists.

Only sections take this form. The `adapt` verb also moves a [`FieldSpectralMultipliers`](@ref), a spectral
kernel and a [`FieldTransformPlans`](@ref), and those have no in-place spelling on purpose: they are
built rather than filled — moving plans replans the transforms, and a radial kernel carries a closure
— so there is no preallocated storage for a destination to offer.
"""
function adapt! end


"""
    _check_adapt_target(destination, source)

Check that two sections agree in everything a storage move must preserve — scalar type, grid and
Fourier layout — and deliberately **not** in storage family, which is the one thing the move exists to
change.

This is [`_check_same_domain`](@ref) minus its backend clause. Reusing that check here would refuse
precisely the pair `adapt!` is for, and dropping the check entirely would let a move rewrite a
destination built for another grid.
"""
function _check_adapt_target(destination, source)
  _same_scalar_type(destination, source) ||
    throw(ArgumentError("adapt! moves storage, not precision: destination and source scalar types must be equal"))
  _same_grid(destination, source)   || throw(ArgumentError("adapt! destination and source grids must be equal"))
  _same_layout(destination, source) || throw(ArgumentError("adapt! destination and source Fourier layouts must be equal"))
  return nothing
end


# `copyto!` on the underlying arrays is what crosses the bus; the vendor packages define it in both
# directions. It is deliberately NOT the public spelling: the package's only `copyto!` methods are the
# broadcast entry point, so a section-to-section `copyto!` that crossed families would cross where
# `destination .= source` refuses (invariant 14) — the same two objects giving opposite answers under
# two spellings. Decision 69.
function adapt!(destination::AbstractFieldPhysical{T, R}, source::AbstractFieldPhysical{T, R}) where {T, R}
  field_data(destination) === field_data(source) && return destination
  _check_adapt_target(destination, source)
  copyto!(field_data(destination), field_data(source))
  return destination
end

function adapt!(destination::AbstractFieldSpectral{T, R}, source::AbstractFieldSpectral{T, R}) where {T, R}
  field_data(destination) === field_data(source) && return destination
  _check_adapt_target(destination, source)
  copyto!(field_data(destination), field_data(source))
  return destination
end

"""
    _is_canonical(multipliers::FieldSpectralMultipliers)

Read back whether a multiplier set's wavenumbers were derived from its grid, rather than supplied.

The answer is a type parameter, not a field, because it decides statically whether two multiplier sets
provably hold the same coordinates — which is what lets `convolve` collapse two radial kernels without
a runtime test. [`adapt`](@ref) has to carry it across a move deliberately: rebuilding through the
public six-array constructor would mark the result non-canonical and silently disable that collapse,
costing performance with no wrong answer to show for it.
"""
_is_canonical(::FieldSpectralMultipliers{<:AbstractFloat, <:Any, <:Any, <:Any, <:Any, <:Any, <:Any,
                                         <:Any, <:Any, <:Any, <:Any, <:Any, <:Any, Canonical}) where {Canonical} = Canonical


# Rebuilt through `similar_field`, so grid, layout, origin and tensor order propagate by construction
# rather than by remembering to pass them — the defect that made `map` drop the layout on every
# permuted fold (decision 48).
adapt_structure(to, field::AbstractFieldPhysical) = similar_field(field, adapt(to, field_data(field)))
adapt_structure(to, field::AbstractFieldSpectral) = similar_field(field, adapt(to, field_data(field)))


# `Canonical` is bound from the INPUT TYPE rather than read with `_is_canonical`, so the flag reaches
# the constructor as a compile-time constant and the rebuilt type is concrete. Read at run time it was
# an ordinary `Bool`, which inference cannot resolve into the type parameter it becomes — so
# `adapt(Array, multipliers)` inferred a `FieldSpectralMultipliers` with its last parameter free, and
# `RadialKernel`/`ProductKernel` inherited that through the multipliers type they carry. The value was
# always right; what was lost is decision 61's whole purpose, since a non-concrete `Canonical` turns
# `convolve`'s static collapse of two radial kernels back into a run-time decision after a bus
# crossing. Found by the exhaustive survey once its adaptor-slot noise was cleared (2026-08-17).
adapt_structure(to, multipliers::FieldSpectralMultipliers{T, K1, K2, K3, S1, S2, S3,
                                                          V1, V2, V3, W1, W2, W3, Canonical}) where {
    T, K1, K2, K3, S1, S2, S3, V1, V2, V3, W1, W2, W3, Canonical} =
  FieldSpectralMultipliers(Val(Canonical), multipliers.grid, multipliers.fourier_layout,
                           adapt(to, multipliers.wavenumber_1),
                           adapt(to, multipliers.wavenumber_2),
                           adapt(to, multipliers.wavenumber_3),
                           adapt(to, multipliers.squared_wavenumber_1),
                           adapt(to, multipliers.squared_wavenumber_2),
                           adapt(to, multipliers.squared_wavenumber_3))


function adapt_structure(to, plans::FieldTransformPlans{T}) where {T<:AbstractFloat}
  grid, layout = plans.grid, plans.fourier_layout
  physical_prototype = _storage_prototype(to, T)
  spectral_prototype = _storage_prototype(to, Complex{T})
  # Order-0 witnesses suffice: the plans are a property of the base and carry no tensor order.
  physical_witness = similar(physical_prototype, T, physical_field_shape(grid, Val(0)))
  spectral_witness = similar(spectral_prototype, Complex{T}, spectral_field_shape(grid, layout, Val(0)))
  # Planner flags are an FFTW concept: `cuFFT` rejects them with an unrelated-looking pointer error,
  # so they are replayed only onto a host target. They stay stored either way, so moving back to the
  # host restores the intent the plans were built with.
  replayed_flags = physical_witness isa Array ? plans.fft_flags : nothing
  rebuilt = FieldTransformPlans(_physical_field_of_order(physical_witness, grid, layout, Val(0)),
                                _spectral_field_of_order(spectral_witness, grid, layout, Val(0));
                                fft_flags = replayed_flags, fft_timelimit = plans.fft_timelimit)
  # Re-stamp the ORIGINAL request rather than the one just replayed. The outer constructor records
  # what it planned with, which on a device target is `nothing`; storing that would discard the
  # caller's intent permanently, and a later move back to the host would silently plan with
  # `ESTIMATE`. The plan objects are taken from `rebuilt` unchanged.
  return FieldTransformPlans{T, typeof(rebuilt.plan_forward_fft), typeof(rebuilt.plan_inverse_fft),
                             typeof(grid), typeof(layout), typeof(rebuilt.component_scratch)}(
    grid, layout, rebuilt.plan_forward_fft, rebuilt.plan_inverse_fft,
    plans.fft_flags, plans.fft_timelimit, rebuilt.component_scratch)
end


# The residual over one folded axis, with that axis a TYPE parameter. Reaching the plane through a
# runtime dimension is what made the whole operation infer `Any`: a filtered generator
# `Tuple(a for a in 1:3 if a != folded)` has type `Tuple{Vararg{Int}}`, which inference cannot narrow,
# and that single non-concrete value poisoned everything downstream — the shift tuple, the `dims` of
# the reversal, and the splatted index tuple of the `view`. Found by the exhaustive survey, whose
# type-stability check reported it on every configuration (576 cells, one operation). Naming the axis
# as `Val{D}` is the same remedy `Interpolation`'s folded-plane helpers already use, and it makes the
# caller's three-way branch the only place a runtime axis appears.
@inline function _reality_residual_plane(data, ::Val{D}, other_axes, stored_planes, residual::T) where {D, T}
  # Index j pairs with -j (mod n), which as a whole-array operation is a reversal followed by a shift
  # of one: `reverse` sends j to n+1-j, and the extra step lands it on the wanted mod(-(j-1), n)+1.
  # Written that way so the pass is array-level and never indexes a device array elementwise.
  shifts = ntuple(axis -> axis in other_axes ? 1 : 0, Val(ndims(data)))
  for plane_index in stored_planes
    plane = selectdim(data, D, plane_index:plane_index)
    partner = circshift(reverse(plane; dims = other_axes), shifts)
    residual = max(residual, maximum(abs, plane .- conj.(partner)))
  end
  return residual
end


"""
    reality_residual(field::AbstractFieldSpectral) -> Real

Measure how far a field's coefficients are from being the spectrum of a real field, returning `0`
exactly when they are one.

A real field's spectrum satisfies ``\\hat f(-k) = \\overline{\\hat f(k)}``, and the real-to-complex
layout exploits that by storing only half the modes — so for most of them the redundant partner is
not stored and *cannot* disagree. Two planes are the exception: the folded axis's zero plane, and its
Nyquist plane when that axis has even length, are each their own mirror image, so within them both
partners are stored and the constraint becomes a relation between entries that a caller can break.
This returns the largest such discrepancy,

```math
\\max \\bigl\\lvert \\hat f(k) - \\overline{\\hat f(-k)} \\bigr\\rvert,
```

over those planes and every fiber component. A mode that is its own partner — the corners where each axis
sits at zero or, on an even-length axis, at Nyquist; eight of them when all three axes are even,
fewer when an axis is odd and so has no Nyquist plane — must be real, and this reports twice its imaginary part, that
being the same discrepancy applied to a self-paired entry.

Reach for it where responsibility for the coefficients changes hands: after writing them directly, or
on accepting them from outside. Everything the package itself produces satisfies the constraint by
construction, because a spectrum built by transforming a real field cannot violate it. The cost is one
or two planes, ``O(N^2)``, not the ``O(N^3 \\log N)`` of the round trip below.

It **reports** rather than repairs, so the caller decides. The repair is already available and is
exactly a physical round trip — [`to_physical`](@ref) followed by [`to_spectral`](@ref) — since the
inverse real transform projects onto the coefficients of a real field; that costs two transforms and
silently rewrites the data, which is why it is not offered under a name of its own.

!!! note "The Nyquist plane is reported, never zeroed"
    Some codes symmetrize by zeroing the Nyquist planes outright. This does not: the package keeps
    Nyquist content and treats the two wavenumber families as disagreeing there on purpose, so a
    violation on that plane is named like any other and what to do about it stays the caller's.
"""
function reality_residual(field::AbstractFieldSpectral{T}) where {T<:AbstractFloat}
  data = field_data(field)
  folded_axis = field_layout(field).fft_dims[1]
  # The zero plane always; the Nyquist plane only when the FULL axis is even, which is the condition
  # for a Nyquist mode to exist at all — the same test invariant 5 turns on.
  stored_planes = iseven(field_grid(field).grid_size[folded_axis]) ?
                  (1, size(data, folded_axis)) : (1,)
  return folded_axis == 1 ? _reality_residual_plane(data, Val(1), (2, 3), stored_planes, zero(T)) :
         folded_axis == 2 ? _reality_residual_plane(data, Val(2), (1, 3), stored_planes, zero(T)) :
                            _reality_residual_plane(data, Val(3), (1, 2), stored_planes, zero(T))
end


end # module Fields
