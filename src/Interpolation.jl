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

  * **Interpolation** (grid to point, *gather*; `interpolate` ``\\equiv \\mathcal I = W``):
    `interpolate(f, xs[, scheme])` / in-place `interpolate!(out, f, xs[, scheme])`, plus the callable
    `f(x)` (and its broadcast `f.(xs)`) as the ergonomic face of `interpolate`.
  * **Anterpolation** (point to grid, *scatter*; `anterpolate` ``\\equiv \\mathcal I^* = W^\\top``):
    `anterpolate(grid, xs, qs[, scheme])` / in-place `anterpolate!(field, xs, qs[, scheme])`, with a
    five-argument ``\\alpha``/``\\beta`` form (``\\beta = 0`` overwrite, ``\\beta \\ne 0`` accumulate,
    the `mul!` convention; accumulation is the common case for the scatter).

`interpolate` / `anterpolate!` are the symmetric named pair (the operators ``\\mathcal I = W`` /
``\\mathcal I^* = W^\\top``); only interpolation also carries the pointwise callable `f(x)`, because
evaluation is pointwise while its adjoint is not. Both directions share one `scheme` (the same
weights) — which is what makes them an adjoint pair.

# Why interpolation and anterpolation are adjoint: the function–measure duality

``\\mathcal I : G \\to P`` and ``\\mathcal I^* : P \\to G`` satisfy ``\\langle \\mathcal I f, q\\rangle_P
= \\langle f, \\mathcal I^* q\\rangle_G``, a duality between *functions* (which you evaluate) and
*measures* (which you integrate against):

  * evaluation is pairing with a Dirac mass, ``f(x) = \\langle \\delta_x, f\\rangle``, so
    ``(\\mathcal I f)_p = \\langle \\delta_{x_p}, f\\rangle = f(x_p)``;
  * its adjoint cannot be pointwise — it returns a measure, a sum of point masses
    ``\\mathcal I^* q = \\sum_p q_p\\,\\delta_{x_p}``, regularized by the stencil kernel to
    ``\\sum_p q_p\\,\\beta(\\cdot - x_p)``, a point-source density.

Hence the API asymmetry: you *evaluate functions* (`f(x)` returns a value) but *accumulate measures*
(`anterpolate!` adds a source density onto a field); there is no pointwise `f(x) = q`. Discretely,
with ``G = \\mathbb R^N`` (``N`` grid nodes) and ``P = \\mathbb R^M`` (``M`` points), interpolation is
the matrix ``\\mathcal I = W`` (``W_{pn} = \\beta_n(x_p)``) and anterpolation its transpose
``\\mathcal I^* = W^\\top``. With shared partition-of-unity weights (``\\mathcal I\\,\\mathbf 1 = \\mathbf 1``,
i.e. ``\\sum_n W_{pn} = 1``), anterpolation is the exact transpose of interpolation and the total
deposited quantity is conserved,

```math
\\sum_n (\\mathcal I^* q)_n = \\langle \\mathbf 1, \\mathcal I^* q\\rangle = \\langle \\mathcal I\\,\\mathbf 1, q\\rangle = \\langle \\mathbf 1, q\\rangle = \\sum_p q_p,
```

which is mandatory for the two-way-coupled parcel application (total water mass and latent heat
conserved). This holds **only when both directions use the same weights**, so the design fixes
anterpolation as the transpose/adjoint of whatever interpolation scheme is in use (mismatched weights
inject a spurious source — Sundaram & Collins 1996). The inner products are a modelling choice: with
the Euclidean (counting) products the adjoint is the bare transpose ``W^\\top``; with ``L^2``/volume-
weighted products it is ``M_G^{-1} W^\\top M_P`` (the immersed-boundary spreading/interpolation pair of
Peskin 2002), conserving an energy pairing rather than the plain sum.

# References

  * C. C. Lalescu, B. Teaca, D. Carati, *Implementation of high order spline interpolations for
    tracking test particles in discretized fields*, J. Comput. Phys. **229**(17) (2010) 5862–5869.
  * S. Sundaram, L. R. Collins, *Numerical considerations in simulating a turbulent suspension of
    finite-volume particles*, J. Comput. Phys. **124**(2) (1996) 337–350.
  * C. S. Peskin, *The immersed boundary method*, Acta Numerica **11** (2002) 479–517.
"""
module Interpolation

using StaticArrays: SVector, SMatrix
using LinearAlgebra: \, I
using ..FiberSections: _assign!, @_assign!
using ..Fields: AbstractFieldPhysical, ScalarFieldPhysical, VectorFieldPhysical, TensorFieldPhysical,
                AbstractFieldSpectral, ScalarFieldSpectral, VectorFieldSpectral, TensorFieldSpectral,
                Grid3D, RealFourierLayout, field_data, field_grid, field_layout, field_scalar_type,
                field_tensor_order, fiber_shape, physical_field_shape, spectral_field_shape,
                FieldTransformPlans, to_physical, to_spectral, similar_field
using ..Points: PointSet, AbstractPointValues, ScalarPointValues, VectorPointValues, TensorPointValues,
                point_coordinates, point_values, npoints, pointvalue_tensor_order, _check_npoints_match
using KernelAbstractions: @kernel, @index, @Const, get_backend, synchronize
import KernelAbstractions
import Atomix

export interpolate, interpolate!, anterpolate, anterpolate!, LalescuSpline, LagrangeSpline, CatmullRom,
       AbstractTransferScheme, DirectDFT, NUFFT


#####################################################
#        Spline scheme and weight generation        #
#####################################################


"""
    AbstractTransferScheme

Supertype of **all** grid↔point transfer schemes — the parameter that fixes how the adjoint pair
`interpolate` ``= W`` / `anterpolate` ``= W^\\top`` is realized (the function–measure duality above).
A scheme is a choice of *kernel* and *representation*: the **physical-domain** local splines
([`AbstractSplineScheme`](@ref) — gather/scatter on the nodal values) and the **spectral-domain**
exact transfers ([`DirectDFT`](@ref) and [`NUFFT`](@ref) — evaluate/deposit in the Fourier basis,
acting on a field in spectral representation). Same verbs, one adjointness contract; the schemes
differ only in (kernel, representation). See `docs/ARCHITECTURE.md` §10.
"""
abstract type AbstractTransferScheme end


"""
    AbstractSplineScheme{N2, M2, T, L}

Supertype of the local interpolation schemes — the two hierarchies of Lalescu, Teaca & Carati
(2010): the smooth [`LalescuSpline`](@ref) and the ``C^0`` [`LagrangeSpline`](@ref). A scheme is a
tensor product of 1D weight polynomials over a compact stencil of ``N_2`` nodes, each weight a
degree-``(M_2-1)`` polynomial in the fractional cell position ``t \\in [0, 1)``. The ``N_2 \\times M_2``
coefficient matrix (`[node, power]`) is precomputed once into an `SMatrix` so it passes into the
gather/scatter kernels by value (no device array). The **physical-domain** family of
[`AbstractTransferScheme`](@ref) (its weights act on the physical nodal values).
"""
abstract type AbstractSplineScheme{N2, M2, T<:AbstractFloat, L} <: AbstractTransferScheme end


"""
    LalescuSpline(n, m = 1; T = Float64)

Smooth (``C^m``) local spline interpolation of Lalescu, Teaca & Carati (2010), pinned bit-for-bit to
TurTLE's `beta_n{n}_m{m}` (TurTLE's `interp_neighbours = n`, `smoothness = m`). Over a compact stencil
of ``2n{+}2`` nodes at offsets ``\\{-n, \\dots, n{+}1\\}`` (``n \\ge 0``, the finite-difference
half-width), the per-axis weights ``\\beta_q(t)`` for fractional cell position ``t \\in [0, 1)`` are the
coefficients of the **two-point Hermite** interpolant of degree ``2m{+}1``: the polynomial that
reproduces the field value and the derivatives of order ``1, \\dots, m`` at the two bracketing nodes
(offsets ``0`` and ``1``), each derivative estimated by a centred finite difference over the
``2n{+}2``-node stencil (Fornberg weights). Smoothness is ``C^m`` with ``0 \\le m \\le 2n``; the weights
are stored in the ``(2n{+}2) \\times (2m{+}2)`` `SMatrix` `coefficients`
(``\\beta_q(t) = \\sum_p \\mathrm{coefficients}[q, p{+}1]\\, t^p``).

It reproduces polynomials up to degree ``\\min(2m{+}1, 2n)`` (for ``n \\ge 1``). Special cases:
``m = 0`` is linear interpolation over the two central nodes (independent of ``n``); ``n = 1, m = 1``
is the Catmull–Rom spline (the default [`CatmullRom`](@ref), quadratic precision). For the ``C^0``
Lagrange hierarchy (degree ``2n{+}1``, all ``2n{+}2`` nodes interpolated) use [`LagrangeSpline`](@ref).
Used by [`interpolate`](@ref) (grid → point) and [`anterpolate`](@ref) (point → grid).

# References

  * C. C. Lalescu, B. Teaca, D. Carati, *Implementation of high order spline interpolations for
    tracking test particles in discretized fields*, J. Comput. Phys. **229**(17) (2010) 5862–5869.
  * C. C. Lalescu, B. Bramas, M. Rampp, M. Wilczek, *An efficient particle tracking algorithm for
    large-scale parallel pseudo-spectral simulations of turbulence* (TurTLE), Comput. Phys. Commun.
    **278** (2022) 108406.
  * B. Fornberg, *Generation of finite difference formulas on arbitrarily spaced grids*, Math. Comp.
    **51**(184) (1988) 699–706.
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

The ``C^0`` Lagrange hierarchy of Lalescu, Teaca & Carati (2010) (TurTLE's `Lagrange_polys`): the
unique degree-``2n{+}1`` polynomial interpolating all ``2n{+}2`` stencil nodes at offsets
``\\{-n, \\dots, n{+}1\\}`` (``n \\ge 0``). The per-axis weights are the Lagrange cardinal polynomials,
stored in the ``(2n{+}2) \\times (2n{+}2)`` `SMatrix` `coefficients`. Reproduces polynomials up to
degree ``2n{+}1`` exactly, but is only ``C^0`` (kinks at the nodes); for smooth derivatives use
[`LalescuSpline`](@ref) instead. ``n = 0`` is linear interpolation.

# References

  * C. C. Lalescu, B. Teaca, D. Carati, *Implementation of high order spline interpolations for
    tracking test particles in discretized fields*, J. Comput. Phys. **229**(17) (2010) 5862–5869.
  * C. C. Lalescu, B. Bramas, M. Rampp, M. Wilczek, *An efficient particle tracking algorithm for
    large-scale parallel pseudo-spectral simulations of turbulence* (TurTLE), Comput. Phys. Commun.
    **278** (2022) 108406.
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
order-``k`` derivative (``k = 0, 1, \\dots`` up to `max_order`) of a function sampled at `nodes`,
evaluated at `evaluation_point`. Host-side helper for the spline-weight construction.

Reference: B. Fornberg, *Generation of finite difference formulas on arbitrarily spaced grids*,
Math. Comp. **51**(184) (1988) 699–706.
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

Build the ``(2n{+}2) \\times (2m{+}2)`` matrix of smooth-spline weight-polynomial coefficients (row `q`
is the weight polynomial for stencil offset ``q - 1 - n \\in \\{-n, \\dots, n{+}1\\}``; column `p+1` is
the ``t^p`` coefficient). Each weight has degree ``2m{+}1``; together they form the two-point Hermite
interpolant reproducing the value and the order-``1, \\dots, m`` derivatives at the two bracketing nodes
(offsets ``0`` and ``1``), the derivatives taken from centred finite differences over the
``2n{+}2``-node stencil. See [`LalescuSpline`](@ref); pinned bit-for-bit against TurTLE's `beta_n{n}_m{m}`.
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

Build the ``(2n{+}2) \\times (2n{+}2)`` matrix of Lagrange cardinal-polynomial coefficients over the
stencil offsets ``\\{-n, \\dots, n{+}1\\}`` (row `q` is the cardinal polynomial of node `q`; column
`p+1` is the ``t^p`` coefficient). Each is the degree-``2n{+}1`` polynomial that is one at its own node
and zero at the others (the inverse of the offsets' Vandermonde matrix). See [`LagrangeSpline`](@ref).
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

The default interpolation scheme: the cubic ``n = 1, m = 1`` [`LalescuSpline`](@ref), a four-point
``C^1`` stencil that reproduces the Catmull–Rom spline (and quadratic polynomials exactly).
"""
const CatmullRom = LalescuSpline(1, 1)


#####################################################
#        In-kernel helpers (GPU-portable)           #
#####################################################


"""
    _axis_weights(coefficients, t)

Evaluate the per-axis spline weights ``\\beta_q(t)`` for all `N2` stencil nodes at fractional position
``t``, returning an `SVector{N2}`. Horner over the `M2` polynomial-coefficient columns of
`coefficients` (``M_2 = \\deg + 1``); pure and allocation-free, so it runs inside the gather/scatter
kernels on CPU and GPU.
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
        # Contiguous (x) axis innermost ⇒ stride-1 stencil reads: a GPU-first choice (measured a
        # large GPU speedup from cache/transaction reuse; mildly slower on CPU, whose larger caches
        # absorb the stride — invariant 6 prioritises GPU). y/z weight and plane offset are hoisted.
        for k in 1:number_of_nodes
          node_z = mod(base_3 + (k - 1 - neighbourhood), grid_z) + 1
          for j in 1:number_of_nodes
            node_y = mod(base_2 + (j - 1 - neighbourhood), grid_y) + 1
            weight_yz = weights_2[j] * weights_3[k]
            plane = grid_x * (node_y - 1) + grid_x * grid_y * (node_z - 1) + points_per_fibre * (fibre - 1)
            for i in 1:number_of_nodes
              node_x = mod(base_1 + (i - 1 - neighbourhood), grid_x) + 1
              accumulated += weight_yz * weights_1[i] * field_values[node_x + plane]
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
        # Contiguous (x) axis innermost ⇒ stride-1 scatter writes (same GPU-first rationale as the
        # gather's reads). y/z weight and plane offset are hoisted out of the inner loop.
        for k in 1:number_of_nodes
          node_z = mod(base_3 + (k - 1 - neighbourhood), grid_z) + 1
          for j in 1:number_of_nodes
            node_y = mod(base_2 + (j - 1 - neighbourhood), grid_y) + 1
            weight_yz = weights_2[j] * weights_3[k]
            plane = grid_x * (node_y - 1) + grid_x * grid_y * (node_z - 1) + points_per_fibre * (fibre - 1)
            for i in 1:number_of_nodes
              node_x = mod(base_1 + (i - 1 - neighbourhood), grid_x) + 1
              Atomix.@atomic field_values[node_x + plane] += weight_yz * weights_1[i] * quantity
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

Each point value is the tensor-product spline gather over the ``(2n{+}2)^3`` stencil around the
containing cell ``c``, with ``t_a`` the fractional position along axis ``a`` and ``\\beta`` the scheme
weights — exactly the weighted sum the kernel computes:

```math
f(x_p) \\approx \\sum_{i_1, i_2, i_3} \\beta_{i_1}(t_1)\\, \\beta_{i_2}(t_2)\\, \\beta_{i_3}(t_3)\\;
f\\bigl(x_{c + (i_1, i_2, i_3)}\\bigr).
```

The ``\\approx`` is genuine: the gather is **exact** at grid nodes and for polynomials up to the
scheme's reproduction degree (`CatmullRom` quadratic, `LalescuSpline(n,m)` ``\\min(2m{+}1, 2n)``,
`LagrangeSpline(n)` ``2n{+}1``), approximate otherwise.

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
[`interpolate!`](@ref) under the same `scheme`, ``\\mathcal I^* = W^\\top`` — computing
``\\mathrm{field} = \\alpha\\,(W^\\top q) + \\beta\\,\\mathrm{field}``. Using the **same** stencil weights
as the gather, each point ``p`` (in cell ``c``, fractional position ``t``) atomically scatters its value
``q_p`` onto the ``(2n{+}2)^3`` surrounding nodes:

```math
\\mathrm{field}\\bigl(x_{c + (i_1, i_2, i_3)}\\bigr) \\mathrel{+}= \\alpha\\;
\\beta_{i_1}(t_1)\\, \\beta_{i_2}(t_2)\\, \\beta_{i_3}(t_3)\\; q_p
```

(after an initial ``\\times \\beta`` prescale of the field). Sharing the gather weights makes this the
exact transpose, so with the partition of unity ``\\sum \\beta = 1`` the total deposited quantity is
conserved. With ``\\beta = 0`` (default) the field is overwritten; with ``\\beta \\ne 0`` the deposit is
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


#####################################################
#        Spectral-domain transfer: DirectDFT        #
#####################################################


"""
    DirectDFT()

The **exact** spectral-domain transfer scheme: interpolation/anterpolation by the literal ``O(NM)``
discrete Fourier sum — no window, no oversampling, no FFT. It is the *definition* of the
spectral-domain adjoint pair `interpolate` ``= W`` / `anterpolate` ``= W^\\top``, so it is at once a
transparent exact baseline and the oracle that validates [`NUFFT`](@ref). It acts on a field in
**spectral representation**, `interpolate(f̂, points, DirectDFT())` and
`anterpolate(reference, points, q, DirectDFT())`:

```math
f(x_p) = \\frac1N \\sum_{k} \\hat f(k)\\, e^{i k\\cdot (x_p - o)}
       = \\frac1N \\sum_{\\text{stored }k} \\alpha(k)\\, \\mathrm{Re}\\!\\bigl(\\hat f(k)\\, e^{i k\\cdot (x_p - o)}\\bigr),
\\qquad
(W^\\top q)(k) = \\sum_p q_p\\, e^{-i k\\cdot (x_p - o)},
```

reconstructing the real field (``o`` the grid origin) from the stored rfft half-spectrum with the
Parseval weight ``\\alpha(k) = 1`` on the self-conjugate ``k_x = 0`` plane (and the even-``N_x`` Nyquist
plane), ``2`` otherwise. The interpolation reproduces the band-limited field **exactly** — so it is
pointwise divergence-free (unlike the local splines) and matches [`to_physical`](@ref) at the grid
nodes; the adjoint matches [`to_spectral`](@ref) from grid-node samples. Adjoint pair:
``M\\,\\langle W\\hat f, q\\rangle_{\\mathrm{pts}} = N\\,\\langle \\hat f, W^\\top q\\rangle`` (the
measure factor, as for the splines). Stateless; ``O(NM)`` — for many points/modes prefer [`NUFFT`](@ref).
"""
struct DirectDFT <: AbstractTransferScheme end


# True signed wavenumbers and the rfft half-spectrum Parseval weight along one array axis of a
# spectral field. `stored_length` is the array's size on this axis (halved on the rfft axis `is_half`),
# `number_of_points` the corresponding grid size. Returns `(k, α)` host vectors: `k` the TRUE
# wavenumber (Nyquist kept, unlike the derivative multipliers); `α = 1` on the half-axis self-conjugate
# modes (kₓ = 0 and even-Nₓ Nyquist) and 2 elsewhere, all-ones on the full axes — so the per-mode weight
# is the product α₁α₂α₃, which reduces to the single half-axis weight.
function _dft_axis(stored_length::Int, number_of_points::Int, domain_length::T, is_half::Bool) where {T<:AbstractFloat}
  unit = 2 * T(π) / domain_length
  wavenumber = Vector{T}(undef, stored_length)
  for i in 1:stored_length
    zero_based = i - 1
    frequency = (is_half || zero_based < (number_of_points + 1) ÷ 2) ? zero_based : zero_based - number_of_points
    wavenumber[i] = unit * frequency
  end
  if is_half
    weight = fill(T(2), stored_length)
    weight[1] = one(T)
    iseven(number_of_points) && (weight[stored_length] = one(T))
  else
    weight = ones(T, stored_length)
  end
  return wavenumber, weight
end


# Build the three per-axis wavenumber + weight device vectors for a spectral field (host build →
# backend copy, mirroring `Fields._axis_wavenumber_arrays`). The half (rfft) axis is `fft_dims[1]`.
function _dft_axes(field::AbstractFieldSpectral{T}) where {T}
  grid = field_grid(field)
  half_dimension = field_layout(field).fft_dims[1]
  data = field_data(field)
  build(d) = begin
    k_host, weight_host = _dft_axis(size(data, d), grid.grid_size[d], grid.domain_size[d], d == half_dimension)
    k_device = similar(data, T, length(k_host)); copyto!(k_device, k_host)
    weight_device = similar(data, T, length(weight_host)); copyto!(weight_device, weight_host)
    (k_device, weight_device)
  end
  axis_1, axis_2, axis_3 = build(1), build(2), build(3)
  return axis_1[1], axis_2[1], axis_3[1], axis_1[2], axis_2[2], axis_3[2]
end


# type-2 / interpolate: one work-item per point sums the exact inverse DFT over every stored mode,
# reconstructing the real field via the α-weighted half-spectrum (Re of the conjugate-folded sum), /N.
@kernel function _direct_dft_interpolate_kernel!(output, @Const(coordinates), @Const(spectral),
                                                 @Const(wavenumber_1), @Const(wavenumber_2), @Const(wavenumber_3),
                                                 @Const(weight_1), @Const(weight_2), @Const(weight_3),
                                                 origin, inverse_count, modes_per_fibre, number_of_points, n1, n2, n3)
  point = @index(Global, Linear)
  if point ≤ number_of_points
    @inbounds begin
      x1 = coordinates[point, 1] - origin[1]
      x2 = coordinates[point, 2] - origin[2]
      x3 = coordinates[point, 3] - origin[3]
      number_of_fibres = length(spectral) ÷ modes_per_fibre
      for fibre in 1:number_of_fibres
        accumulated = zero(eltype(output))
        for i3 in 1:n3
          phase_3 = wavenumber_3[i3] * x3
          for i2 in 1:n2
            phase_23 = phase_3 + wavenumber_2[i2] * x2
            weight_23 = weight_2[i2] * weight_3[i3]
            plane = n1 * (i2 - 1) + n1 * n2 * (i3 - 1) + modes_per_fibre * (fibre - 1)
            for i1 in 1:n1
              phase = phase_23 + wavenumber_1[i1] * x1
              coefficient = spectral[i1 + plane]
              accumulated += weight_1[i1] * weight_23 *
                (real(coefficient) * cos(phase) - imag(coefficient) * sin(phase))
            end
          end
        end
        output[point + number_of_points * (fibre - 1)] = accumulated * inverse_count
      end
    end
  end
end


# type-1 / anterpolate: one work-item per stored mode sums the forward DFT over every point (no
# atomics — distinct modes are independent). `factor` = α, `prescale` = β (overwrite when β = 0).
@kernel function _direct_dft_anterpolate_kernel!(spectral, @Const(coordinates), @Const(quantities),
                                                 @Const(wavenumber_1), @Const(wavenumber_2), @Const(wavenumber_3),
                                                 origin, factor, prescale, modes_per_fibre, number_of_points, n1, n2, n3)
  mode = @index(Global, Linear)
  if mode ≤ modes_per_fibre
    @inbounds begin
      i1 = mod(mode - 1, n1) + 1
      i2 = mod((mode - 1) ÷ n1, n2) + 1
      i3 = (mode - 1) ÷ (n1 * n2) + 1
      kx = wavenumber_1[i1]; ky = wavenumber_2[i2]; kz = wavenumber_3[i3]
      number_of_fibres = length(spectral) ÷ modes_per_fibre
      for fibre in 1:number_of_fibres
        real_part = zero(eltype(quantities))
        imaginary_part = zero(eltype(quantities))
        for point in 1:number_of_points
          phase = kx * (coordinates[point, 1] - origin[1]) +
                  ky * (coordinates[point, 2] - origin[2]) +
                  kz * (coordinates[point, 3] - origin[3])
          quantity = quantities[point + number_of_points * (fibre - 1)]
          real_part += quantity * cos(phase)
          imaginary_part -= quantity * sin(phase)
        end
        index = mode + modes_per_fibre * (fibre - 1)
        contribution = factor * complex(real_part, imaginary_part)
        spectral[index] = iszero(prescale) ? contribution : contribution + prescale * spectral[index]
      end
    end
  end
end


"""
    interpolate!(out::AbstractPointValues, field::AbstractFieldSpectral, points::PointSet, scheme::DirectDFT)

Exact spectral interpolation (the ``O(NM)`` inverse DFT) of `field` (spectral representation) to
`points`, writing into `out`; see [`DirectDFT`](@ref). The result equals [`to_physical`](@ref) at the
grid nodes and reproduces the band-limited field exactly off-grid.
"""
function interpolate!(out::AbstractPointValues, field::AbstractFieldSpectral, points::PointSet, scheme::DirectDFT)
  pointvalue_tensor_order(out) == field_tensor_order(field) ||
    throw(ArgumentError("output tensor order $(pointvalue_tensor_order(out)) must equal field tensor order $(field_tensor_order(field))"))
  _check_npoints_match(out, points)
  grid = field_grid(field)
  T = field_scalar_type(field)
  data = field_data(field)
  wavenumber_1, wavenumber_2, wavenumber_3, weight_1, weight_2, weight_3 = _dft_axes(field)
  n1, n2, n3 = size(data, 1), size(data, 2), size(data, 3)
  modes_per_fibre = n1 * n2 * n3
  number_of_points = npoints(out)
  backend = get_backend(data)
  _direct_dft_interpolate_kernel!(backend)(point_values(out), point_coordinates(points), data,
    wavenumber_1, wavenumber_2, wavenumber_3, weight_1, weight_2, weight_3,
    T.(grid.origin), one(T) / T(prod(grid.grid_size)), modes_per_fibre, number_of_points, n1, n2, n3;
    ndrange = number_of_points)
  synchronize(backend)
  return out
end


"""
    interpolate(field::AbstractFieldSpectral, points::PointSet, scheme::DirectDFT)

Allocating form: a new [`AbstractPointValues`](@ref) of `field`'s tensor order holding `field`
evaluated exactly at `points` (the inverse DFT, [`DirectDFT`](@ref)).
"""
function interpolate(field::AbstractFieldSpectral, points::PointSet, scheme::DirectDFT)
  T = field_scalar_type(field)
  R = field_tensor_order(field)
  data = similar(point_coordinates(points), T, (npoints(points), fiber_shape(Val(R))...))
  return interpolate!(_wrap_pointvalues(data, Val(R)), field, points, scheme)
end


"""
    anterpolate!(field::AbstractFieldSpectral, points::PointSet, quantities::AbstractPointValues,
                 scheme::DirectDFT, α = true, β = false)

Exact spectral anterpolation (the ``O(NM)`` forward DFT) — the adjoint of the spectral
[`interpolate!`](@ref) — depositing the per-point `quantities` into the Fourier coefficients of
`field`: ``\\mathrm{field} = \\alpha\\,(W^\\top q) + \\beta\\,\\mathrm{field}`` with
``(W^\\top q)(k) = \\sum_p q_p\\,e^{-i k\\cdot(x_p - o)}`` (matches [`to_spectral`](@ref) from grid-node
samples). ``\\beta = 0`` overwrites, ``\\beta \\ne 0`` accumulates.
"""
function anterpolate!(field::AbstractFieldSpectral, points::PointSet, quantities::AbstractPointValues,
                      scheme::DirectDFT, α::Real = true, β::Real = false)
  field_tensor_order(field) == pointvalue_tensor_order(quantities) ||
    throw(ArgumentError("field tensor order $(field_tensor_order(field)) must equal quantities tensor order $(pointvalue_tensor_order(quantities))"))
  _check_npoints_match(points, quantities)
  grid = field_grid(field)
  T = field_scalar_type(field)
  data = field_data(field)
  wavenumber_1, wavenumber_2, wavenumber_3, _, _, _ = _dft_axes(field)
  n1, n2, n3 = size(data, 1), size(data, 2), size(data, 3)
  modes_per_fibre = n1 * n2 * n3
  number_of_points = npoints(quantities)
  backend = get_backend(data)
  _direct_dft_anterpolate_kernel!(backend)(data, point_coordinates(points), point_values(quantities),
    wavenumber_1, wavenumber_2, wavenumber_3, T.(grid.origin), T(α), T(β),
    modes_per_fibre, number_of_points, n1, n2, n3; ndrange = modes_per_fibre)
  synchronize(backend)
  return field
end


"""
    anterpolate(reference::AbstractFieldSpectral, points::PointSet, quantities::AbstractPointValues, scheme::DirectDFT)

Allocating form: a new spectral field like `reference` (same grid/layout, the tensor order of
`quantities`) holding the deposited Fourier coefficients (the forward DFT, [`DirectDFT`](@ref)).
"""
function anterpolate(reference::AbstractFieldSpectral, points::PointSet, quantities::AbstractPointValues, scheme::DirectDFT)
  out = similar_field(reference, Val(pointvalue_tensor_order(quantities)))
  return anterpolate!(out, points, quantities, scheme)
end


#####################################################
#        Spectral-domain transfer: NUFFT            #
#####################################################
#
# The fast O(N log N + M) gridding form of DirectDFT: spread → FFT → deconvolve. The non-uniform
# points are spread to / gathered from an oversampled (σ) grid with a smooth compact window ψ; the
# window's spectral footprint ψ̂ is divided out (deconvolution), and the oversampling makes the
# window's aliases negligible (the accuracy ε). All three pieces reuse existing machinery — the
# transfer kernels (with the window in place of the spline coefficients), a FieldTransformPlans on
# the oversampled grid, and an `assignment_window`-style coefficientwise deconvolution.


# Exponential-of-semicircle (ES) window weights over the W-wide stencil, GPU-trivial (exp/sqrt only).
# For fractional position t ∈ [0,1) the W nodes sit at offsets δ = i − W÷2 (i = 1…W); the weight of
# node i is ψ(t − δ) with ψ(s) = exp(β(√(1−(2s/W)²) − 1)). Returned as an SVector so the kernels
# index it by a runtime stencil index on CPU and GPU (as for the spline `_axis_weights`).
@inline function _es_weights(t::T, beta::T, ::Val{W}) where {T, W}
  half = W ÷ 2
  return SVector{W, T}(ntuple(i -> begin
    z = 2 * (t - (i - half)) / W
    exp(beta * (sqrt(max(one(T) - z * z, zero(T))) - one(T)))
  end, Val(W)))
end


# The continuous Fourier transform ψ̂(ω) = ∫_{−W/2}^{W/2} ψ(s) e^{−iωs} ds of the ES window (real,
# even). The √(1−z²) endpoint singularity is regularized by the substitution z = sin θ
# (√(1−z²) = cos θ), after which the integrand is smooth and trapezoidal converges fast. Host-only
# (called once per plan, per stored mode along each axis), so plain scalar quadrature.
function _es_window_transform(omega::T, beta::T, width::Integer; quadrature_points::Int = 256) where {T<:AbstractFloat}
  half_width = T(width) / 2
  accumulated = zero(T)
  for q in 0:quadrature_points
    theta = -T(π) / 2 + T(π) * q / quadrature_points
    trapezoidal = (q == 0 || q == quadrature_points) ? one(T) / 2 : one(T)
    accumulated += trapezoidal * exp(beta * (cos(theta) - one(T))) * cos(omega * half_width * sin(theta)) * cos(theta)
  end
  return half_width * (T(π) / quadrature_points) * accumulated
end


# Stencil width and shape parameter for a target tolerance (the exponential-of-semicircle rule for
# oversampling σ = 2: w ≈ log₁₀(1/ε) + 2, β ≈ 2.30 w — Barnett, Magland & af Klinteberg 2019).
# Verified against `DirectDFT` in `test/transfer_spectral.jl` and bumped if the measured error misses ε.
_nufft_width(tol::Real) = max(4, ceil(Int, -log10(tol)) + 2)
_nufft_beta(width::Integer, ::Type{T}) where {T} = T(23) / 10 * width


# Per-axis N→σN frequency index map: stored coarse index → stored oversampled index of the same
# Fourier frequency. On the rfft half axis the low frequencies 0…N/2 keep their index; on a full axis
# the negative frequencies fold to the high end of the oversampled axis. Host build → backend copy.
function _nufft_index_map(reference::AbstractArray, number_of_points::Int, oversampled_points::Int, stored_length::Int, is_half::Bool)
  host = Vector{Int}(undef, stored_length)
  for i in 1:stored_length
    zero_based = i - 1
    frequency = (is_half || zero_based < (number_of_points + 1) ÷ 2) ? zero_based : zero_based - number_of_points
    host[i] = frequency ≥ 0 ? frequency + 1 : oversampled_points + frequency + 1
  end
  device = similar(reference, Int, stored_length)
  copyto!(device, host)
  return device
end


# The coefficientwise deconvolution ∏_a 1/ψ̂_a(ω) on the coarse (N) spectral grid, a real (Nkx,Ny,Nz)
# device array (mirrors `Convolution.assignment_window`: per-axis host build, reshape, broadcast,
# copy). ω_a = 2π·freq/(σ N_a) is the cell-frequency of the stored mode on the oversampled grid.
function _nufft_deconvolution(reference::AbstractFieldSpectral{T}, oversampling::Int, width::Int, beta::T) where {T<:AbstractFloat}
  grid = field_grid(reference)
  half_dimension = field_layout(reference).fft_dims[1]
  data = field_data(reference)
  axis(d) = begin
    stored = size(data, d)
    number_of_points = grid.grid_size[d]
    is_half = d == half_dimension
    host = Vector{T}(undef, stored)
    for i in 1:stored
      zero_based = i - 1
      frequency = (is_half || zero_based < (number_of_points + 1) ÷ 2) ? zero_based : zero_based - number_of_points
      omega = 2 * T(π) * frequency / (oversampling * number_of_points)
      host[i] = one(T) / _es_window_transform(omega, beta, width)
    end
    # Project out the exact Nyquist mode on even axes: the rfft half-spectrum Nyquist cannot be
    # split losslessly into the finer oversampled grid (the gridding NUFFT's known edge). Zeroing it
    # here makes type-1 and type-2 exact adjoints on the resolved sub-Nyquist band — exactly the band
    # a spectral solver uses (de-aliasing zeros the Nyquist), where the transfer is exact to ε.
    if iseven(number_of_points)
      host[is_half ? stored : number_of_points ÷ 2 + 1] = zero(T)
    end
    device = similar(data, T, stored); copyto!(device, host); device
  end
  reciprocal_1 = reshape(axis(1), :, 1, 1)
  reciprocal_2 = reshape(axis(2), 1, :, 1)
  reciprocal_3 = reshape(axis(3), 1, 1, :)
  deconvolution = similar(data, T, size(data, 1), size(data, 2), size(data, 3))
  @_assign! deconvolution .= reciprocal_1 .* reciprocal_2 .* reciprocal_3
  return deconvolution
end


"""
    NUFFT(reference::AbstractFieldSpectral; tol = 1e-10, oversampling = 2, width = 0, beta = 0)

The **fast** spectral-domain transfer scheme — the ``O(N\\log N + M)`` windowed-gridding (NUFFT)
counterpart of [`DirectDFT`](@ref), exact to a tolerance `tol`. Built from a `reference` spectral
field (it fixes the grid, layout, element type, and tensor order); the plan holds the oversampled
(`oversampling`×) grid and its [`FieldTransformPlans`](@ref), the deconvolution ``1/\\hat\\psi``, and
the coarse↔oversampled mode maps. `width`/`beta` default to the exponential-of-semicircle parameters
for `tol`. Used like `DirectDFT`: `interpolate(f̂, points, nufft)` / `anterpolate(points, q, nufft)`,
on a field in **spectral representation**, of the reference's tensor order. The algorithm is

```math
\\text{type-2: deconvolve } \\hat f / \\hat\\psi \\to \\text{zero-pad} \\to \\mathcal F^{-1} \\to \\text{window-gather}, \\qquad
\\text{type-1: window-spread} \\to \\mathcal F \\to \\text{truncate} \\to \\text{deconvolve}.
```

It agrees with `DirectDFT` (hence `to_physical`/`to_spectral` at the nodes) to `tol`, shares its
adjoint relation, and like it is divergence-free (it reconstructs the band-limited field). For a few
points/modes `DirectDFT` is simpler; `NUFFT` wins as ``M, N`` grow.
"""
struct NUFFT{T, PL, DC, PP, SP, MP} <: AbstractTransferScheme
  width::Int
  beta::T
  total_oversampling::T
  oversampled_grid::Grid3D{T}
  oversampled_plans::PL
  deconvolution::DC
  oversampled_physical::PP    # template (its data is copied, never mutated, per call)
  oversampled_spectral::SP
  embed_map_1::MP
  embed_map_2::MP
  embed_map_3::MP
end


function NUFFT(reference::AbstractFieldSpectral{T, R}; tol::Real = 1e-10, oversampling::Integer = 2,
               width::Integer = 0, beta::Real = 0) where {T<:AbstractFloat, R}
  σ = Int(oversampling)
  w = width > 0 ? Int(width) : _nufft_width(tol)
  β = beta > 0 ? T(beta) : _nufft_beta(w, T)
  grid = field_grid(reference)
  layout = field_layout(reference)
  data = field_data(reference)
  oversampled_size = ntuple(d -> σ * grid.grid_size[d], 3)
  oversampled_grid = Grid3D(oversampled_size, grid.domain_size; origin = grid.origin)
  physical_template = _wrap_field(similar(data, T, physical_field_shape(oversampled_grid, Val(R))), oversampled_grid, Val(R))
  spectral_template = _wrap_field_spectral(similar(data, Complex{T}, spectral_field_shape(oversampled_grid, layout, Val(R))), oversampled_grid, Val(R))
  plans = FieldTransformPlans(physical_template, spectral_template)
  deconvolution = _nufft_deconvolution(reference, σ, w, β)
  total_oversampling = T(prod(oversampled_size) / prod(grid.grid_size))
  map_1 = _nufft_index_map(data, grid.grid_size[1], oversampled_size[1], size(data, 1), 1 == layout.fft_dims[1])
  map_2 = _nufft_index_map(data, grid.grid_size[2], oversampled_size[2], size(data, 2), 2 == layout.fft_dims[1])
  map_3 = _nufft_index_map(data, grid.grid_size[3], oversampled_size[3], size(data, 3), 3 == layout.fft_dims[1])
  return NUFFT(w, β, total_oversampling, oversampled_grid, plans, deconvolution,
               physical_template, spectral_template, map_1, map_2, map_3)
end


# Window gather (type-2): one work-item per point sums the W³ stencil of the oversampled physical
# field with the ES window weights (no atomics). Mirrors `_interpolate_kernel!`.
@kernel function _nufft_gather_kernel!(output, @Const(coordinates), @Const(field_values), beta,
                                       origin, spacing, grid_size, points_per_fibre, number_of_points, ::Val{W}) where {W}
  point = @index(Global, Linear)
  if point ≤ number_of_points
    @inbounds begin
      base_1, t_1 = _locate(coordinates[point, 1], origin[1], spacing[1], grid_size[1])
      base_2, t_2 = _locate(coordinates[point, 2], origin[2], spacing[2], grid_size[2])
      base_3, t_3 = _locate(coordinates[point, 3], origin[3], spacing[3], grid_size[3])
      weights_1 = _es_weights(t_1, beta, Val(W))
      weights_2 = _es_weights(t_2, beta, Val(W))
      weights_3 = _es_weights(t_3, beta, Val(W))
      half = W ÷ 2
      number_of_fibres = length(field_values) ÷ points_per_fibre
      grid_x, grid_y, grid_z = grid_size
      for fibre in 1:number_of_fibres
        accumulated = zero(eltype(output))
        for k in 1:W
          node_z = mod(base_3 + (k - half), grid_z) + 1
          for j in 1:W
            node_y = mod(base_2 + (j - half), grid_y) + 1
            weight_yz = weights_2[j] * weights_3[k]
            plane = grid_x * (node_y - 1) + grid_x * grid_y * (node_z - 1) + points_per_fibre * (fibre - 1)
            for i in 1:W
              node_x = mod(base_1 + (i - half), grid_x) + 1
              accumulated += weight_yz * weights_1[i] * field_values[node_x + plane]
            end
          end
        end
        output[point + number_of_points * (fibre - 1)] = accumulated
      end
    end
  end
end


# Window spread (type-1): the transpose of the gather — one work-item per point scatters its value
# over the W³ stencil, atomically. Mirrors `_anterpolate_kernel!`.
@kernel function _nufft_spread_kernel!(field_values, @Const(coordinates), @Const(point_quantities), beta,
                                       origin, spacing, grid_size, points_per_fibre, number_of_points, ::Val{W}) where {W}
  point = @index(Global, Linear)
  if point ≤ number_of_points
    @inbounds begin
      base_1, t_1 = _locate(coordinates[point, 1], origin[1], spacing[1], grid_size[1])
      base_2, t_2 = _locate(coordinates[point, 2], origin[2], spacing[2], grid_size[2])
      base_3, t_3 = _locate(coordinates[point, 3], origin[3], spacing[3], grid_size[3])
      weights_1 = _es_weights(t_1, beta, Val(W))
      weights_2 = _es_weights(t_2, beta, Val(W))
      weights_3 = _es_weights(t_3, beta, Val(W))
      half = W ÷ 2
      number_of_fibres = length(field_values) ÷ points_per_fibre
      grid_x, grid_y, grid_z = grid_size
      for fibre in 1:number_of_fibres
        quantity = point_quantities[point + number_of_points * (fibre - 1)]
        for k in 1:W
          node_z = mod(base_3 + (k - half), grid_z) + 1
          for j in 1:W
            node_y = mod(base_2 + (j - half), grid_y) + 1
            weight_yz = weights_2[j] * weights_3[k]
            plane = grid_x * (node_y - 1) + grid_x * grid_y * (node_z - 1) + points_per_fibre * (fibre - 1)
            for i in 1:W
              node_x = mod(base_1 + (i - half), grid_x) + 1
              Atomix.@atomic field_values[node_x + plane] += weight_yz * weights_1[i] * quantity
            end
          end
        end
      end
    end
  end
end


# Copy the coarse (N) spectral coefficients into the zero-padded oversampled (σN) array by the
# per-axis frequency maps (one work-item per coarse mode; the oversampled array is zeroed first).
@kernel function _nufft_embed_kernel!(oversampled, @Const(coarse), @Const(map_1), @Const(map_2), @Const(map_3),
                                      coarse_modes, oversampled_modes, n1, n2, over_n1, over_n2)
  mode = @index(Global, Linear)
  if mode ≤ coarse_modes
    @inbounds begin
      i1 = mod(mode - 1, n1) + 1
      i2 = mod((mode - 1) ÷ n1, n2) + 1
      i3 = (mode - 1) ÷ (n1 * n2) + 1
      over_base = map_1[i1] + over_n1 * (map_2[i2] - 1) + over_n1 * over_n2 * (map_3[i3] - 1)
      number_of_fibres = length(coarse) ÷ coarse_modes
      for fibre in 1:number_of_fibres
        oversampled[over_base + oversampled_modes * (fibre - 1)] = coarse[mode + coarse_modes * (fibre - 1)]
      end
    end
  end
end


# The transpose of embed: read the oversampled coefficients at the mapped positions into the coarse
# array (one work-item per coarse mode).
@kernel function _nufft_extract_kernel!(coarse, @Const(oversampled), @Const(map_1), @Const(map_2), @Const(map_3),
                                        coarse_modes, oversampled_modes, n1, n2, over_n1, over_n2)
  mode = @index(Global, Linear)
  if mode ≤ coarse_modes
    @inbounds begin
      i1 = mod(mode - 1, n1) + 1
      i2 = mod((mode - 1) ÷ n1, n2) + 1
      i3 = (mode - 1) ÷ (n1 * n2) + 1
      over_base = map_1[i1] + over_n1 * (map_2[i2] - 1) + over_n1 * over_n2 * (map_3[i3] - 1)
      number_of_fibres = length(coarse) ÷ coarse_modes
      for fibre in 1:number_of_fibres
        coarse[mode + coarse_modes * (fibre - 1)] = oversampled[over_base + oversampled_modes * (fibre - 1)]
      end
    end
  end
end


# A fresh oversampled work field (physical or spectral) from a stored template (never mutates it).
_fresh(template) = similar_field(template, similar(field_data(template)))


"""
    interpolate!(out::AbstractPointValues, field::AbstractFieldSpectral, points::PointSet, scheme::NUFFT)

Fast spectral interpolation (the windowed-gridding NUFFT, [`NUFFT`](@ref)) of `field` to `points`:
deconvolve, zero-pad to the oversampled grid, inverse FFT, window-gather. Agrees with
[`DirectDFT`](@ref) to the plan's tolerance.
"""
function interpolate!(out::AbstractPointValues, field::AbstractFieldSpectral, points::PointSet, scheme::NUFFT)
  pointvalue_tensor_order(out) == field_tensor_order(field) ||
    throw(ArgumentError("output tensor order $(pointvalue_tensor_order(out)) must equal field tensor order $(field_tensor_order(field))"))
  _check_npoints_match(out, points)
  T = field_scalar_type(field)
  backend = get_backend(field_data(field))
  oversampled_spectral = _fresh(scheme.oversampled_spectral)
  over_data = field_data(oversampled_spectral)
  fill!(over_data, zero(Complex{T}))
  # deconvolve + scale the coarse coefficients, then embed into the zero-padded oversampled grid
  coarse = similar(field_data(field))
  @_assign! coarse .= field_data(field) .* scheme.deconvolution .* scheme.total_oversampling
  data = field_data(field)
  n1, n2, n3 = size(data, 1), size(data, 2), size(data, 3)
  coarse_modes = n1 * n2 * n3
  oversampled_modes = size(over_data, 1) * size(over_data, 2) * size(over_data, 3)
  _nufft_embed_kernel!(backend)(over_data, coarse, scheme.embed_map_1, scheme.embed_map_2, scheme.embed_map_3,
    coarse_modes, oversampled_modes, n1, n2, size(over_data, 1), size(over_data, 2); ndrange = coarse_modes)
  synchronize(backend)
  oversampled_physical = to_physical(oversampled_spectral, scheme.oversampled_plans)
  over_grid = scheme.oversampled_grid
  _nufft_gather_kernel!(backend)(point_values(out), point_coordinates(points), field_data(oversampled_physical), scheme.beta,
    T.(over_grid.origin), T.(over_grid.grid_spacing), over_grid.grid_size, prod(over_grid.grid_size), npoints(out), Val(scheme.width);
    ndrange = npoints(out))
  synchronize(backend)
  return out
end


"""
    interpolate(field::AbstractFieldSpectral, points::PointSet, scheme::NUFFT)

Allocating form of the NUFFT [`interpolate!`](@ref).
"""
function interpolate(field::AbstractFieldSpectral, points::PointSet, scheme::NUFFT)
  T = field_scalar_type(field)
  R = field_tensor_order(field)
  data = similar(point_coordinates(points), T, (npoints(points), fiber_shape(Val(R))...))
  return interpolate!(_wrap_pointvalues(data, Val(R)), field, points, scheme)
end


"""
    anterpolate!(field::AbstractFieldSpectral, points::PointSet, quantities::AbstractPointValues,
                 scheme::NUFFT, α = true, β = false)

Fast spectral anterpolation (the windowed-gridding NUFFT) — the adjoint of the NUFFT
[`interpolate!`](@ref): window-spread, FFT, truncate to the coarse modes, deconvolve, accumulating
``\\mathrm{field} = \\alpha\\,(W^\\top q) + \\beta\\,\\mathrm{field}``.
"""
function anterpolate!(field::AbstractFieldSpectral, points::PointSet, quantities::AbstractPointValues,
                      scheme::NUFFT, α::Real = true, β::Real = false)
  field_tensor_order(field) == pointvalue_tensor_order(quantities) ||
    throw(ArgumentError("field tensor order $(field_tensor_order(field)) must equal quantities tensor order $(pointvalue_tensor_order(quantities))"))
  _check_npoints_match(points, quantities)
  T = field_scalar_type(field)
  backend = get_backend(field_data(field))
  oversampled_physical = _fresh(scheme.oversampled_physical)
  over_phys_data = field_data(oversampled_physical)
  fill!(over_phys_data, zero(T))
  over_grid = scheme.oversampled_grid
  _nufft_spread_kernel!(backend)(over_phys_data, point_coordinates(points), point_values(quantities), scheme.beta,
    T.(over_grid.origin), T.(over_grid.grid_spacing), over_grid.grid_size, prod(over_grid.grid_size), npoints(quantities), Val(scheme.width);
    ndrange = npoints(quantities))
  synchronize(backend)
  oversampled_spectral = to_spectral(oversampled_physical, scheme.oversampled_plans)
  over_data = field_data(oversampled_spectral)
  coarse = similar(field_data(field))
  data = field_data(field)
  n1, n2, n3 = size(data, 1), size(data, 2), size(data, 3)
  coarse_modes = n1 * n2 * n3
  oversampled_modes = size(over_data, 1) * size(over_data, 2) * size(over_data, 3)
  _nufft_extract_kernel!(backend)(coarse, over_data, scheme.embed_map_1, scheme.embed_map_2, scheme.embed_map_3,
    coarse_modes, oversampled_modes, n1, n2, size(over_data, 1), size(over_data, 2); ndrange = coarse_modes)
  synchronize(backend)
  if iszero(β)
    @_assign! data .= T(α) .* coarse .* scheme.deconvolution
  else
    @_assign! data .= T(α) .* coarse .* scheme.deconvolution .+ T(β) .* data
  end
  return field
end


"""
    anterpolate(reference::AbstractFieldSpectral, points::PointSet, quantities::AbstractPointValues, scheme::NUFFT)

Allocating form of the NUFFT [`anterpolate!`](@ref): a new spectral field like `reference`.
"""
function anterpolate(reference::AbstractFieldSpectral, points::PointSet, quantities::AbstractPointValues, scheme::NUFFT)
  out = similar_field(reference, Val(pointvalue_tensor_order(quantities)))
  return anterpolate!(out, points, quantities, scheme)
end


# Spectral-field wrappers (the spectral siblings of `_wrap_field`), for the oversampled work fields.
_wrap_field_spectral(data, grid, ::Val{0}) = ScalarFieldSpectral(data, grid)
_wrap_field_spectral(data, grid, ::Val{1}) = VectorFieldSpectral(data, grid)
_wrap_field_spectral(data, grid, ::Val{R}) where {R} = TensorFieldSpectral{R}(data, grid)


end # module Interpolation
