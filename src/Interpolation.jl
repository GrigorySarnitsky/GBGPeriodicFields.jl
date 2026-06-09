"""
    Interpolation

Transfer between the grid sections of `Fields` and the point sections of `Points`: evaluating a
field at off-grid positions, and depositing per-point quantities back onto the grid. The two
operations are formal adjoints of each other. The transfer uses the local spline interpolation of
Lalescu, Teaca & Carati (2010) as portable gather/scatter kernels (CPU / CUDA / AMDGPU, via
KernelAbstractions; the scatter accumulates atomically); the method, terminology, and GPU rationale
are in `docs/ARCHITECTURE.md` §10, and the point-value data types and their fiberwise algebra live
in the `Points` module.

# API

  * **Interpolation** (grid to point, *gather*): `interpolate(f, xs[, scheme])` / in-place
    `interpolate!(out, f, xs[, scheme])`, plus the callable `f(x)` (and its broadcast `f.(xs)`)
    as the ergonomic face of `interpolate`.
  * **Anterpolation** (point to grid, *scatter*): `anterpolate(grid, xs, qs[, scheme])` / in-place
    `anterpolate!(field, xs, qs[, scheme])`, with a five-argument `α`/`β` form (`β = 0` overwrite,
    `β ≠ 0` accumulate, the `mul!` convention; accumulation is the common case for the scatter).

`interpolate` / `anterpolate!` are the symmetric named pair (the operators `𝓘 = W` / `𝓘* = Wᵀ`);
only interpolation also carries the pointwise callable `f(x)`, because evaluation is pointwise
while its adjoint is not. Both directions share one `scheme` (the same weights) — which is what
makes them an adjoint pair.

# Why interpolation and anterpolation are adjoint: the function–measure duality

`𝓘 : G → P` and `𝓘* : P → G` satisfy `⟨𝓘 f, q⟩_P = ⟨f, 𝓘* q⟩_G`, a duality between *functions*
(which you evaluate) and *measures* (which you integrate against):

  * evaluation is pairing with a Dirac mass, `f(x) = ⟨δₓ, f⟩`, so `(𝓘 f)ₚ = ⟨δ_{xₚ}, f⟩ = f(xₚ)`;
  * its adjoint cannot be pointwise — it returns a measure, a sum of point masses
    `𝓘* q = Σₚ qₚ δ_{xₚ}`, regularized by the stencil kernel to `Σₚ qₚ β(·−xₚ)`, a point source
    density.

Hence the API asymmetry: you *evaluate functions* (`f(x)` returns a value) but *accumulate
measures* (`anterpolate!` adds a source density onto a field); there is no pointwise `f(x) = q`.
Discretely, with `G = ℝᴺ` (`N` grid nodes) and `P = ℝᴹ` (`M` points), interpolation is the matrix
`𝓘 = W` (`Wₚₙ = βₙ(xₚ)`) and anterpolation its transpose `𝓘* = Wᵀ`. With shared partition-of-unity
weights (`𝓘 𝟙 = 𝟙`, i.e. `Σₙ Wₚₙ = 1`), anterpolation is the exact transpose of interpolation and
the total deposited quantity is conserved,

    Σₙ (𝓘* q)ₙ = ⟨𝟙, 𝓘* q⟩ = ⟨𝓘 𝟙, q⟩ = ⟨𝟙, q⟩ = Σₚ qₚ,

which is mandatory for the two-way-coupled parcel application (total water mass and latent heat
conserved). This holds **only when both directions use the same weights**, so the design fixes
anterpolation as the transpose/adjoint of whatever interpolation scheme is in use (mismatched
weights inject a spurious source — Sundaram & Collins 1996). The inner products are a modelling
choice: with the Euclidean (counting) products the adjoint is the bare transpose `Wᵀ`; with
`L²`/volume-weighted products it is `M_G⁻¹ Wᵀ M_P` (the immersed-boundary spreading/interpolation
pair of Peskin), conserving an energy pairing rather than the plain sum.
"""
module Interpolation

using StaticArrays: SVector, SMatrix
using LinearAlgebra: \, I
using ..Fields: AbstractFieldPhysical, ScalarFieldPhysical, VectorFieldPhysical, TensorFieldPhysical,
                Grid3D, field_data, field_grid, field_scalar_type, field_tensor_order,
                fiber_shape, physical_field_shape
using ..Points: PointSet, AbstractPointValues, ScalarPointValues, VectorPointValues, TensorPointValues,
                point_coordinates, point_values, npoints, pointvalue_tensor_order, _check_npoints_match
using KernelAbstractions: @kernel, @index, @Const, get_backend, synchronize
import KernelAbstractions
import Atomix

export interpolate, interpolate!, anterpolate, anterpolate!, LalescuSpline, LagrangeSpline, CatmullRom


#####################################################
#        Spline scheme and weight generation        #
#####################################################


"""
    AbstractSplineScheme{N2, M2, T, L}

Supertype of the local interpolation schemes — the two hierarchies of Lalescu, Teaca & Carati
(2010): the smooth [`LalescuSpline`](@ref) and the `C⁰` [`LagrangeSpline`](@ref). A scheme is a
tensor product of 1D weight polynomials over a compact stencil of `N2` nodes, each weight a
degree-`(M2−1)` polynomial in the fractional cell position `t ∈ [0,1)`. The `N2 × M2` coefficient
matrix (`[node, power]`) is precomputed once into an `SMatrix` so it passes into the gather/scatter
kernels by value (no device array).
"""
abstract type AbstractSplineScheme{N2, M2, T<:AbstractFloat, L} end


"""
    LalescuSpline(n, m = 1; T = Float64)

Smooth (`Cᵐ`) local spline interpolation of Lalescu, Teaca & Carati (2010), pinned bit-for-bit to
TurTLE's `beta_n{n}_m{m}` (TurTLE's `interp_neighbours = n`, `smoothness = m`). Over a compact
stencil of `2n+2` nodes at offsets `{−n,…,n+1}` (`n ≥ 0`, the finite-difference half-width), the
per-axis weights `βq(t)` for fractional cell position `t ∈ [0,1)` are the coefficients of the
**two-point Hermite** interpolant of degree `2m+1`: the polynomial that reproduces the field value
and the derivatives of order `1…m` at the two bracketing nodes (offsets `0` and `1`), each
derivative estimated by a centred finite difference over the `2n+2`-node stencil (Fornberg weights).
Smoothness is `Cᵐ` with `0 ≤ m ≤ 2n`; the weights are stored in the `(2n+2)×(2m+2)` `SMatrix`
`coefficients` (`βq(t) = Σₚ coefficients[q, p+1] tᵖ`).

It reproduces polynomials up to degree `min(2m+1, 2n)` (for `n ≥ 1`). Special cases: `m = 0` is
linear interpolation over the two central nodes (independent of `n`); `n = 1, m = 1` is the
Catmull–Rom spline (the default [`CatmullRom`](@ref), quadratic precision). For the `C⁰` Lagrange
hierarchy (degree `2n+1`, all `2n+2` nodes interpolated) use [`LagrangeSpline`](@ref). Used by
[`interpolate`](@ref) (grid → point) and [`anterpolate`](@ref) (point → grid).
"""
struct LalescuSpline{N2, M2, T<:AbstractFloat, L} <: AbstractSplineScheme{N2, M2, T, L}
  neighbours::Int
  smoothness::Int
  coefficients::SMatrix{N2, M2, T, L}
end


function LalescuSpline(n::Integer, m::Integer = 1; T::Type{<:AbstractFloat} = Float64)
  n ≥ 0 || throw(ArgumentError("neighbourhood n must be a nonnegative integer, got $n"))
  0 ≤ m ≤ 2n || throw(ArgumentError("smoothness m must satisfy 0 ≤ m ≤ 2n, got n=$n, m=$m"))
  number_of_nodes = 2 * Int(n) + 2
  number_of_powers = 2 * Int(m) + 2
  coefficients = _hermite_weight_matrix(Int(n), Int(m))
  return LalescuSpline{number_of_nodes, number_of_powers, T, number_of_nodes * number_of_powers}(
    Int(n), Int(m), SMatrix{number_of_nodes, number_of_powers, T}(T.(coefficients)))
end


"""
    LagrangeSpline(n; T = Float64)

The `C⁰` Lagrange hierarchy of Lalescu, Teaca & Carati (2010) (TurTLE's `Lagrange_polys`): the
unique degree-`2n+1` polynomial interpolating all `2n+2` stencil nodes at offsets `{−n,…,n+1}`
(`n ≥ 0`). The per-axis weights are the Lagrange cardinal polynomials, stored in the `(2n+2)×(2n+2)`
`SMatrix` `coefficients`. Reproduces polynomials up to degree `2n+1` exactly, but is only `C⁰`
(kinks at the nodes); for smooth derivatives use [`LalescuSpline`](@ref) instead. `n = 0` is linear
interpolation.
"""
struct LagrangeSpline{N2, M2, T<:AbstractFloat, L} <: AbstractSplineScheme{N2, M2, T, L}
  neighbours::Int
  coefficients::SMatrix{N2, M2, T, L}
end


function LagrangeSpline(n::Integer; T::Type{<:AbstractFloat} = Float64)
  n ≥ 0 || throw(ArgumentError("neighbourhood n must be a nonnegative integer, got $n"))
  number_of_nodes = 2 * Int(n) + 2
  coefficients = _lagrange_weight_matrix(Int(n))
  return LagrangeSpline{number_of_nodes, number_of_nodes, T, number_of_nodes^2}(
    Int(n), SMatrix{number_of_nodes, number_of_nodes, T}(T.(coefficients)))
end


# Coefficient accessor shared by the concrete schemes (both store the same `coefficients` field),
# so the kernels and `_coefficients_as` need not branch on the scheme type.
spline_coefficients(scheme::LalescuSpline) = scheme.coefficients
spline_coefficients(scheme::LagrangeSpline) = scheme.coefficients


"""
    _fornberg(evaluation_point, nodes, max_order)

Fornberg (1988) finite-difference weights: `weights[i, k+1]` is the weight of `nodes[i]` in the
order-`k` derivative (`k = 0…max_order`) of a function sampled at `nodes`, evaluated at
`evaluation_point`. Host-side helper for the spline-weight construction.
"""
function _fornberg(evaluation_point::Float64, nodes::Vector{Float64}, max_order::Int)
  number_of_nodes = length(nodes)
  weights = zeros(Float64, number_of_nodes, max_order + 1)
  product_left = 1.0
  difference_last = nodes[1] - evaluation_point
  weights[1, 1] = 1.0
  for i in 2:number_of_nodes
    highest = min(i, max_order + 1)
    product_current = 1.0
    difference_previous = difference_last
    difference_last = nodes[i] - evaluation_point
    for j in 1:i-1
      difference_nodes = nodes[i] - nodes[j]
      product_current *= difference_nodes
      if j == i - 1
        for k in highest:-1:2
          weights[i, k] = product_left * ((k - 1) * weights[i-1, k-1] - difference_previous * weights[i-1, k]) / product_current
        end
        weights[i, 1] = -product_left * difference_previous * weights[i-1, 1] / product_current
      end
      for k in highest:-1:2
        weights[j, k] = (difference_last * weights[j, k] - (k - 1) * weights[j, k-1]) / difference_nodes
      end
      weights[j, 1] = difference_last * weights[j, 1] / difference_nodes
    end
    product_left = product_current
  end
  return weights
end


"""
    _hermite_weight_matrix(n, m)

Build the `(2n+2)×(2m+2)` matrix of smooth-spline weight-polynomial coefficients (row `q` is the
weight polynomial for stencil offset `q − 1 − n ∈ {−n,…,n+1}`; column `p+1` is the `tᵖ` coefficient).
Each weight has degree `2m+1`; together they form the two-point Hermite interpolant reproducing the
value and the order-`1…m` derivatives at the two bracketing nodes (offsets `0` and `1`), the
derivatives taken from centred finite differences over the `2n+2`-node stencil. See
[`LalescuSpline`](@ref); pinned bit-for-bit against TurTLE's `beta_n{n}_m{m}`.
"""
function _hermite_weight_matrix(n::Int, m::Int)
  offsets = collect(-n:n+1)
  number_of_nodes = length(offsets)                            # 2n+2
  degree = 2m + 1                                              # coefficients a₀…a_degree (2m+2 of them)
  conditions = zeros(Float64, degree + 1, degree + 1)          # square; acts on the polynomial coefficients
  nodal_values = zeros(Float64, degree + 1, number_of_nodes)   # the same conditions in terms of f_q
  row = 1
  # Two-point Hermite: at each bracketing node match the value (derivative order 0) and the
  # derivatives 1…m, the derivatives from a centred finite difference over the whole stencil.
  for (node, stencil) in ((0, collect(-n:n)), (1, collect((1 - n):(1 + n))))
    finite_difference = _fornberg(Float64(node), Float64.(stencil), m)
    for derivative_order in 0:m
      for power in derivative_order:degree
        conditions[row, power+1] = prod((power - derivative_order + 1):power) * Float64(node)^(power - derivative_order)
      end
      for (stencil_index, stencil_offset) in enumerate(stencil)
        nodal_values[row, findfirst(==(stencil_offset), offsets)] = finite_difference[stencil_index, derivative_order+1]
      end
      row += 1
    end
  end
  # Solve conditions · a = nodal_values (one right-hand side per node); the βq(t) coefficients are
  # the rows of the transpose.
  coefficients = conditions \ nodal_values
  return permutedims(coefficients)
end


"""
    _lagrange_weight_matrix(n)

Build the `(2n+2)×(2n+2)` matrix of Lagrange cardinal-polynomial coefficients over the stencil
offsets `{−n,…,n+1}` (row `q` is the cardinal polynomial of node `q`; column `p+1` is the `tᵖ`
coefficient). Each is the degree-`2n+1` polynomial that is one at its own node and zero at the
others (the inverse of the offsets' Vandermonde matrix). See [`LagrangeSpline`](@ref).
"""
function _lagrange_weight_matrix(n::Int)
  offsets = collect(-n:n+1)
  number_of_nodes = length(offsets)                            # 2n+2
  vandermonde = zeros(Float64, number_of_nodes, number_of_nodes)
  for (row, offset) in enumerate(offsets)
    for power in 0:number_of_nodes-1
      vandermonde[row, power+1] = Float64(offset)^power
    end
  end
  # vandermonde · a_q = e_q gives the cardinal polynomial of node q (1 at its node, 0 elsewhere).
  coefficients = vandermonde \ Matrix{Float64}(I, number_of_nodes, number_of_nodes)
  return permutedims(coefficients)
end


"""
    CatmullRom

The default interpolation scheme: the cubic `n = 1, m = 1` [`LalescuSpline`](@ref), a four-point
`C¹` stencil that reproduces the Catmull–Rom spline (and quadratic polynomials exactly).
"""
const CatmullRom = LalescuSpline(1, 1)


#####################################################
#        In-kernel helpers (GPU-portable)           #
#####################################################


"""
    _axis_weights(coefficients, t)

Evaluate the per-axis spline weights `βq(t)` for all `N2` stencil nodes at fractional position `t`,
returning an `SVector{N2}`. Horner over the `M2` polynomial-coefficient columns of `coefficients`
(`M2 = degree + 1`); pure and allocation-free, so it runs inside the gather/scatter kernels on CPU
and GPU.
"""
@inline function _axis_weights(coefficients::SMatrix{N2, M2, T}, t::T) where {N2, M2, T}
  weights = coefficients[:, M2]
  for power in (M2 - 1):-1:1
    weights = weights .* t .+ coefficients[:, power]
  end
  return weights
end


"""
    _locate(coordinate, origin, spacing, number_of_grid_points)

Return `(base_cell, t)` for one axis: the zero-based index `base_cell` of the left node of the cell
containing `coordinate`, and the fractional position `t ∈ [0,1)` within it. Periodic wrapping of the
stencil is applied later via `mod`. Pure scalar arithmetic, kernel-safe.
"""
@inline function _locate(coordinate::T, origin::T, spacing::T, number_of_grid_points::Int) where {T}
  continuous_index = (coordinate - origin) / spacing
  base_cell = floor(Int, continuous_index)
  return base_cell, continuous_index - base_cell
end


#####################################################
#        Gather (interpolation) kernel              #
#####################################################


# One work-item per point. For each fibre component, accumulate the tensor-product spline sum over
# the (2n+2)³ stencil and write the point's own output slot (no atomics needed). The field array and
# the output array are indexed linearly (column-major, fibre-last), so a single kernel serves scalar,
# vector, and tensor orders.
@kernel function _interpolate_kernel!(output, @Const(coordinates), @Const(field_values), coefficients,
                                      origin, spacing, grid_size, points_per_fibre, number_of_points)
  point = @index(Global, Linear)
  if point ≤ number_of_points
    @inbounds begin
      base_1, t_1 = _locate(coordinates[point, 1], origin[1], spacing[1], grid_size[1])
      base_2, t_2 = _locate(coordinates[point, 2], origin[2], spacing[2], grid_size[2])
      base_3, t_3 = _locate(coordinates[point, 3], origin[3], spacing[3], grid_size[3])
      weights_1 = _axis_weights(coefficients, t_1)
      weights_2 = _axis_weights(coefficients, t_2)
      weights_3 = _axis_weights(coefficients, t_3)
      number_of_nodes = size(coefficients, 1)
      neighbourhood = (number_of_nodes - 2) ÷ 2
      number_of_fibres = length(field_values) ÷ points_per_fibre
      grid_x, grid_y, grid_z = grid_size
      for fibre in 1:number_of_fibres
        accumulated = zero(eltype(output))
        for i in 1:number_of_nodes
          node_x = mod(base_1 + (i - 1 - neighbourhood), grid_x) + 1
          for j in 1:number_of_nodes
            node_y = mod(base_2 + (j - 1 - neighbourhood), grid_y) + 1
            weight_xy = weights_1[i] * weights_2[j]
            for k in 1:number_of_nodes
              node_z = mod(base_3 + (k - 1 - neighbourhood), grid_z) + 1
              linear = node_x + grid_x * (node_y - 1) + grid_x * grid_y * (node_z - 1) + points_per_fibre * (fibre - 1)
              accumulated += weight_xy * weights_3[k] * field_values[linear]
            end
          end
        end
        output[point + number_of_points * (fibre - 1)] = accumulated
      end
    end
  end
end


#####################################################
#        Scatter (anterpolation) kernel             #
#####################################################


# The transpose of the gather: one work-item per point scatters its weighted value over the (2n+2)³
# stencil, accumulating atomically into the field because distinct points can target the same grid
# node. `factor` is the α scale; the β prescale is applied to the field before launch.
@kernel function _anterpolate_kernel!(field_values, @Const(coordinates), @Const(point_quantities), coefficients,
                                      factor, origin, spacing, grid_size, points_per_fibre, number_of_points)
  point = @index(Global, Linear)
  if point ≤ number_of_points
    @inbounds begin
      base_1, t_1 = _locate(coordinates[point, 1], origin[1], spacing[1], grid_size[1])
      base_2, t_2 = _locate(coordinates[point, 2], origin[2], spacing[2], grid_size[2])
      base_3, t_3 = _locate(coordinates[point, 3], origin[3], spacing[3], grid_size[3])
      weights_1 = _axis_weights(coefficients, t_1)
      weights_2 = _axis_weights(coefficients, t_2)
      weights_3 = _axis_weights(coefficients, t_3)
      number_of_nodes = size(coefficients, 1)
      neighbourhood = (number_of_nodes - 2) ÷ 2
      number_of_fibres = length(field_values) ÷ points_per_fibre
      grid_x, grid_y, grid_z = grid_size
      for fibre in 1:number_of_fibres
        quantity = factor * point_quantities[point + number_of_points * (fibre - 1)]
        for i in 1:number_of_nodes
          node_x = mod(base_1 + (i - 1 - neighbourhood), grid_x) + 1
          for j in 1:number_of_nodes
            node_y = mod(base_2 + (j - 1 - neighbourhood), grid_y) + 1
            weight_xy = weights_1[i] * weights_2[j]
            for k in 1:number_of_nodes
              node_z = mod(base_3 + (k - 1 - neighbourhood), grid_z) + 1
              linear = node_x + grid_x * (node_y - 1) + grid_x * grid_y * (node_z - 1) + points_per_fibre * (fibre - 1)
              Atomix.@atomic field_values[linear] += weight_xy * weights_3[k] * quantity
            end
          end
        end
      end
    end
  end
end


#####################################################
#        Drivers: interpolation                     #
#####################################################


"""
    interpolate!(out::AbstractPointValues, field::AbstractFieldPhysical, points::PointSet, scheme = CatmullRom)

Interpolate `field` (physical-space representation) to the off-grid `points`, writing into `out`; returns `out`.

`out` must match `field` in tensor order and cover the same number of points as `points`. The transfer runs
as a portable gather kernel on the field's array backend (CPU / CUDA / AMDGPU). Interpolation is defined for
physical-space representation only; transform a spectral field to physical space first.
"""
function interpolate!(out::AbstractPointValues, field::AbstractFieldPhysical, points::PointSet, scheme::AbstractSplineScheme = CatmullRom)
  pointvalue_tensor_order(out) == field_tensor_order(field) ||
    throw(ArgumentError("output tensor order $(pointvalue_tensor_order(out)) must equal field tensor order $(field_tensor_order(field))"))
  _check_npoints_match(out, points)
  grid = field_grid(field)
  T = field_scalar_type(field)
  coefficients = _coefficients_as(scheme, T)
  number_of_points = npoints(out)
  backend = get_backend(field_data(field))
  _interpolate_kernel!(backend)(point_values(out), point_coordinates(points), field_data(field), coefficients,
    T.(grid.origin), T.(grid.grid_spacing), grid.grid_size, prod(grid.grid_size), number_of_points; ndrange = number_of_points)
  synchronize(backend)
  return out
end


"""
    interpolate(field::AbstractFieldPhysical, points::PointSet, scheme = CatmullRom)

Allocating form of [`interpolate!`](@ref): returns a new [`AbstractPointValues`](@ref) of `field`'s tensor
order holding `field` sampled at `points`.
"""
function interpolate(field::AbstractFieldPhysical, points::PointSet, scheme::AbstractSplineScheme = CatmullRom)
  T = field_scalar_type(field)
  data = similar(point_coordinates(points), T, (npoints(points), fiber_shape(Val(field_tensor_order(field)))...))
  return interpolate!(_wrap_pointvalues(data, Val(field_tensor_order(field))), field, points, scheme)
end


"""
    (field::AbstractFieldPhysical)(x; scheme = CatmullRom)

Evaluate `field` at a single off-grid position `x` (a length-3 indexable), returning a scalar, an
`SVector{3}`, or an `SMatrix{3,3}` for scalar/vector/second-order-tensor fields. A convenience wrapper
over [`interpolate`](@ref) (it builds a one-point set and runs the gather kernel); for many points,
call `interpolate` with a [`PointSet`](@ref) instead.
"""
function (field::AbstractFieldPhysical)(x; scheme::AbstractSplineScheme = CatmullRom)
  T = field_scalar_type(field)
  coordinates = similar(field_data(field), T, (1, 3))
  view(coordinates, 1, :) .= (T(x[1]), T(x[2]), T(x[3]))
  values = interpolate(field, PointSet(coordinates), scheme)
  return _single_point_value(values)
end


#####################################################
#        Drivers: anterpolation                     #
#####################################################


"""
    anterpolate!(field::AbstractFieldPhysical, points::PointSet, quantities::AbstractPointValues,
                 scheme = CatmullRom, α = true, β = false)

Deposit the per-point `quantities` onto `field` in-place — the adjoint (transpose) of
[`interpolate!`](@ref) under the same `scheme` — computing `field = α·(Wᵀ quantities) + β·field`;
returns `field`. With `β = 0` (default) the field is overwritten; with `β ≠ 0` the deposit is
accumulated (the common case for the two-way-coupling scatter). `field` and `quantities` must share
tensor order and `points` must cover the same number of points. Runs as a portable atomic-scatter
kernel on the field's array backend.
"""
function anterpolate!(field::AbstractFieldPhysical, points::PointSet, quantities::AbstractPointValues,
                      scheme::AbstractSplineScheme = CatmullRom, α::Real = true, β::Real = false)
  field_tensor_order(field) == pointvalue_tensor_order(quantities) ||
    throw(ArgumentError("field tensor order $(field_tensor_order(field)) must equal quantities tensor order $(pointvalue_tensor_order(quantities))"))
  _check_npoints_match(points, quantities)
  grid = field_grid(field)
  T = field_scalar_type(field)
  data = field_data(field)
  if iszero(β)
    fill!(data, zero(T))
  else
    data .*= T(β)
  end
  coefficients = _coefficients_as(scheme, T)
  number_of_points = npoints(quantities)
  backend = get_backend(data)
  _anterpolate_kernel!(backend)(data, point_coordinates(points), point_values(quantities), coefficients,
    T(α), T.(grid.origin), T.(grid.grid_spacing), grid.grid_size, prod(grid.grid_size), number_of_points; ndrange = number_of_points)
  synchronize(backend)
  return field
end


"""
    anterpolate(grid::Grid3D, points::PointSet, quantities::AbstractPointValues, scheme = CatmullRom)

Allocating form of [`anterpolate!`](@ref): returns a new physical-space field on `grid`, of the tensor
order of `quantities`, holding the deposited (scattered) quantities.
"""
function anterpolate(grid::Grid3D{T}, points::PointSet, quantities::AbstractPointValues, scheme::AbstractSplineScheme = CatmullRom) where {T<:AbstractFloat}
  R = pointvalue_tensor_order(quantities)
  data = similar(point_values(quantities), T, physical_field_shape(grid, Val(R)))
  return anterpolate!(_wrap_field(data, grid, Val(R)), points, quantities, scheme)
end


#####################################################
#        Small wrappers                             #
#####################################################


# Convert a scheme's precomputed weight coefficients to the element type `T` of the field being
# transferred, so the kernel runs entirely in `T`.
_coefficients_as(scheme::AbstractSplineScheme{N2, M2}, ::Type{T}) where {N2, M2, T} = SMatrix{N2, M2, T}(spline_coefficients(scheme))

_wrap_pointvalues(data, ::Val{0}) = ScalarPointValues(data)
_wrap_pointvalues(data, ::Val{1}) = VectorPointValues(data)
_wrap_pointvalues(data, ::Val{R}) where {R} = TensorPointValues{R}(data)

_wrap_field(data, grid, ::Val{0}) = ScalarFieldPhysical(data, grid)
_wrap_field(data, grid, ::Val{1}) = VectorFieldPhysical(data, grid)
_wrap_field(data, grid, ::Val{R}) where {R} = TensorFieldPhysical{R}(data, grid)

_single_point_value(values::ScalarPointValues) = Array(point_values(values))[1]
_single_point_value(values::VectorPointValues) = SVector{3}(Array(point_values(values))[1, :])
_single_point_value(values::TensorPointValues{2}) = SMatrix{3, 3}(Array(point_values(values))[1, :, :])


end # module Interpolation
