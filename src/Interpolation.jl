"""
    Interpolation

Transfer between the grid sections of [`Fields`](@ref "Fields") and the point sections of
[`Points`](@ref "Points"): **interpolation**
evaluates a field at off-grid positions, and its adjoint **anterpolation** deposits per-point quantities
back onto the grid. A `PointSet` holds the positions and an `AbstractPointValues` the per-point values.

Interpolation (`interpolate`) is the **gather** ``W``, the linear map that evaluates a field ``f`` at
the points: its value ``(Wf)_p = f(x_p)`` at the ``p``-th point is ``f`` at that point's position
``x_p``. Anterpolation (`anterpolate`) is the **scatter** ``W^\\top``, the transpose of ``W``,
its adjoint for the unnormalized sums: it spreads per-point quantities ``q`` (with ``q_p`` the value carried at
``x_p``) back onto the surrounding grid nodes with stencil weights, returning a whole field whose value
``(W^\\top q)(x)`` is what it deposits at grid position ``x``. The two are exact transposes — pairing
the gathered values against ``q`` over the ``M`` points equals pairing ``f`` against the scattered
field over the ``N`` grid cells. Written with the normalized inner product ``\\langle\\cdot,\\cdot\\rangle``
(`inner`, the fiber contraction averaged over its base), the factors ``M`` and ``N`` undo its ``1/M``
and ``1/N``:

```math
\\begin{aligned}
M \\langle Wf, q \\rangle_{\\mathrm{pts}} &= \\sum_p (Wf)_p \\cdot q_p \\\\
&= \\sum_x f(x) \\cdot (W^\\top q)(x) = N \\langle f, W^\\top q \\rangle_{\\mathrm{grid}}.
\\end{aligned}
```

The middle sum, over the ``N`` grid nodes, is the physical-representation form. For the spectral
schemes, whose scatter is the conjugate transpose, the same identity holds with the mode-wise
pairing, one number by Parseval — which is why `inner` on a field in spectral representation returns the
physical value.

Here the subscripts name the two mean-normalized inner products — over the ``M`` sample points and over the ``N`` grid nodes. This holds because each scheme's scatter applies its own gather's transpose — the same stencil weights for the local splines, the conjugate Fourier sum for the spectral pair. Because those weights sum to one
(a partition of unity), anterpolation **conserves** the total it deposits — the property that coupling a
quantity back onto the flow needs. That is a property of the **local-spline** schemes, whose weights sum
to one at every position, and it holds for [`DirectDFT`](@ref) too, by a different route: a constant is
band-limited, so the exact spectral gather reproduces it exactly, which makes the equivalent nodal
weights sum to one; and the deposited zero mode is exactly ``\\sum_p q_p``, which *is* the conservation
statement. Only [`NUFFT`](@ref) falls short, and only by its tolerance. Conservation
holds **only** when both directions use the same weights;
mismatched weights inject a spurious source (Sundaram & Collins 1996). The pair is symmetric in name and in
adjointness, and asymmetric in three places, listed together because each is easy to meet as a
surprise: a gather yields point values while its adjoint returns a field; the ``\\alpha``/``\\beta``
accumulation weights are taken by the scatter alone; and only the gather carries the callable sugar
`f(x)`, evaluation being pointwise where its adjoint is not. Each scheme's own docstring gives the gather
and scatter weights it applies.

A transfer `scheme` (an [`AbstractTransferScheme`](@ref)) fixes the weights and the representation it acts on.
Two families ship: the physical-domain local splines of Lalescu, Teaca & Carati (2010)
(the default [`CatmullRom`](@ref)), which act on a field in physical representation, and the spectral-domain exact
`DirectDFT` / fast `NUFFT` that act on a field in spectral representation. The point-value data types and their fiberwise algebra
live in the `Points` module.

The parts are:

  * **Interpolation** (grid → point, *gather*; `interpolate`, ``W``): [`interpolate`](@ref) and
    the in-place [`interpolate!`](@ref), plus the callable `f(x)` (and its broadcast `f.(xs)`) as the
    ergonomic face of a single-point gather, which the physical-domain spline schemes carry and the
    spectral ones do not.
  * **Anterpolation** (point → grid, *scatter*; `anterpolate`, ``W^\\top``): [`anterpolate`](@ref)
    and the in-place [`anterpolate!`](@ref), the latter with an ``\\alpha``/``\\beta`` accumulate form
    (``\\beta = 0`` overwrite, ``\\beta \\ne 0`` accumulate, the `mul!` convention; accumulation is the
    common case for the scatter).
  * **Traversal order.** [`point_traversal_order`](@ref) builds a [`PointTraversalOrder`](@ref), a permutation saying
    which point each work item of a transfer handles, so that neighbouring work touches neighbouring
    memory. It is an option on the four verbs above and never changes their result. Points move, and
    an order goes stale as they do, so [`point_traversal_order!`](@ref) rebuilds one in place against a
    [`PointTraversalOrderScratch`](@ref), allocating nothing that scales with the point count.
  * **Scheme persistence.** [`write_scheme`](@ref) and [`read_scheme`](@ref) map a scheme to and from
    one self-describing HDF5 group, so a checkpoint restores not only where a point set samples but
    how (methods load with the `HDF5` package, as a weak-dependency extension). A scheme is a
    parameter record rather than a section, so the group carries attributes and no dataset: the
    weights are derived and recomputed on read. `NUFFT` is excluded by design — it owns plans built
    against a reference field, so it is rebuilt rather than stored.

# References

  * C. C. Lalescu, B. Teaca, D. Carati, [*Implementation of high order spline interpolations for tracking test particles in discretized fields*](https://doi.org/10.1016/j.jcp.2009.10.046), J. Comput. Phys. **229**(17) (2010) 5862–5869.
  * S. Sundaram, L. R. Collins, [*Numerical considerations in simulating a turbulent suspension of finite-volume particles*](https://doi.org/10.1006/jcph.1996.0064), J. Comput. Phys. **124**(2) (1996) 337–350.
"""
module Interpolation

using StaticArrays: SVector, SMatrix
using LinearAlgebra: \, I
using ..FiberSections: _assign!, @_assign!, _use_threads
import ..Fields: _context_grid, _context_layout      # extended for the NUFFT plan below
using ..Fields: _check_matching_context, _storage_family, _approx, _show_domain, _show_extent
using ..Fields: AbstractFieldPhysical, ScalarFieldPhysical, VectorFieldPhysical, TensorFieldPhysical,
                AbstractFieldSpectral, ScalarFieldSpectral, VectorFieldSpectral, TensorFieldSpectral,
                Grid3D, RealFourierLayout, field_data, field_grid, field_layout, field_scalar_type,
                field_tensor_order, fiber_shape, field_physical_shape, field_spectral_shape,
                FieldTransformPlans, to_physical, to_spectral, similar_field,
                embed_modes!, extract_modes!
using ..Points: _show_count, PointSet, AbstractPointValues, ScalarPointValues, VectorPointValues, TensorPointValues,
                point_positions, point_values, npoints, point_value_tensor_order, _check_npoints_match
import Adapt: adapt, adapt_structure
using KernelAbstractions: @kernel, @index, @Const, get_backend, synchronize
import KernelAbstractions
import Atomix

export interpolate, interpolate!, anterpolate, anterpolate!, point_traversal_order, point_traversal_order!,
  PointTraversalOrderScratch, PointTraversalOrder,
  LalescuSpline, LagrangeSpline, CatmullRom,
       AbstractTransferScheme, DirectDFT, NUFFT, write_scheme, read_scheme


#####################################################
#        Spline scheme and weight generation        #
#####################################################


"""
    AbstractTransferScheme

Supertype of **all** grid↔point transfer schemes — the parameter that fixes how the adjoint pair
`interpolate` (``W``, the gather that evaluates a field at each point) / `anterpolate` (``W^\\top``,
its transpose, the scatter that deposits per-point values onto the grid) is realized. A scheme is a
choice of *kernel* and
*representation*: the **physical-domain** local splines
([`AbstractSplineScheme`](@ref) — gather/scatter on the nodal values) and the **spectral-domain**
transfers (the exact [`DirectDFT`](@ref) and the fast, approximate [`NUFFT`](@ref) — evaluate/deposit in the Fourier basis,
acting on a field in spectral representation). Same verbs, one adjointness contract, the one non-uniformity documented below; the schemes
differ only in (kernel, representation).

One place that uniformity does not reach is the **allocating** `anterpolate`'s leading argument,
which names what the fresh destination is built from: a `Grid3D` suffices for the spline schemes,
whose result is a field in physical representation, while the spectral schemes take a whole field in
spectral representation, their destination needing that representation's layout, backend and element
type too. Code
polymorphic over the allocating form therefore has to branch; the in-place `anterpolate!` forms,
where the caller owns the destination, are uniform.

Schemes divide the same way over **storage families**. The spline schemes and `DirectDFT` are
plain values — weight coefficients in an `SMatrix`, or none at all — so a kernel captures them by
value: one built on the host drives a transfer over device points with nothing copied, which is why
`adapt` (documented with [`Fields`](@ref "Fields")) does not list them. `NUFFT` is the exception,
and for the reason [`write_scheme`](@ref) also refuses it: it owns plans and buffers built from its
`reference` field, so it already lives in that field's family.
"""
abstract type AbstractTransferScheme end


"""
    AbstractSplineScheme{N2, M2, T, L}

Supertype of the physical-domain local interpolation schemes over one shared stencil: the smooth
[`LalescuSpline`](@ref) of Lalescu, Teaca & Carati (2010) and the ``C^0`` [`LagrangeSpline`](@ref), the
classical Lagrange interpolant of the same nodes, matched to TurTLE's `Lagrange_polys`. Each acts on
a field in physical representation, gathering and scattering its nodal values over a compact
``(2n{+}2)^3`` stencil around the cell ``c`` that contains a point ``x_p``. With ``t_a`` the point's
fractional position along axis ``a`` and ``w`` the scheme's per-axis weight polynomials, interpolation is
the tensor-product gather

```math
f(x_p) = \\sum_{i_1, i_2, i_3} w_{i_1}(t_1)  w_{i_2}(t_2)  w_{i_3}(t_3)
f\\bigl(x_{c + (i_1, i_2, i_3)}\\bigr),
```

and anterpolation is its transpose, adding ``w_{i_1}(t_1)  w_{i_2}(t_2)  w_{i_3}(t_3)  q_p`` (with
``q_p`` the value carried at ``x_p``) onto each of those same nodes. Concretely a scheme is a tensor product of 1D weight polynomials: a compact
stencil of ``N_2 = 2n{+}2`` nodes, each weight a degree-``(M_2-1)`` polynomial in the fractional cell
position ``t \\in [0, 1)``. The ``N_2 \\times M_2`` coefficient matrix (`[node, power]`) is precomputed
once into an `SMatrix`, so it passes into the gather/scatter kernels by value (no device array). One of
the two families of [`AbstractTransferScheme`](@ref); the spectral-domain [`DirectDFT`](@ref) /
[`NUFFT`](@ref) are the other. Only the spline family has a shared supertype: its members differ in
their weights alone and so share a parametric interface, while a stateless `DirectDFT` and a
plan-carrying `NUFFT` share no structure a supertype could hold.

Reference: C. C. Lalescu, B. Teaca, D. Carati, [*Implementation of high order spline interpolations for tracking test particles in discretized fields*](https://doi.org/10.1016/j.jcp.2009.10.046), J. Comput. Phys. **229**(17) (2010) 5862–5869.
"""
abstract type AbstractSplineScheme{N2, M2, T<:AbstractFloat, L} <: AbstractTransferScheme end


"""
    LalescuSpline(n, m = 1; T = Float64)

Smooth (``C^m``) local spline interpolation follows Lalescu, Teaca & Carati (2010), pinned to
1e-12 against
the ``\\texttt{beta\\_n}n\\texttt{\\_m}m`` weights of TurTLE, the reference pseudospectral turbulence solver with Lagrangian
particle tracking (its `interp_neighbours = n`, `smoothness = m`). Over a compact stencil
of ``2n{+}2`` nodes at offsets ``\\{-n, \\dots, n{+}1\\}`` (``n \\ge 0``, the first argument — the
finite-difference half-width), the per-axis weights ``w_q(t)`` for fractional cell position ``t \\in [0, 1)`` are the
coefficients of the **two-point Hermite** interpolant of degree ``2m{+}1``: the polynomial that
reproduces the field value and the derivatives of order ``1, \\dots, m`` at the two bracketing nodes
(offsets ``0`` and ``1``), each derivative estimated by a centred finite difference over a
``2n{+}1``-node stencil about that node (Fornberg weights). The second argument `m` sets the
smoothness, ``C^m`` with ``0 \\le m \\le 2n``. That bound makes the default ``m = 1`` valid only for
``n \\ge 1``, so the one-argument `LalescuSpline(0)` is rejected rather than silently repaired: the
smallest stencil admits ``m = 0`` alone, spelled `LalescuSpline(0, 0)` (the linear scheme). The weights
are stored in the ``(2n{+}2) \\times (2m{+}2)`` `SMatrix` `coefficients`
(``w_q(t) = \\sum_r \\texttt{coefficients}[q, r{+}1]  t^r``, the exponent ``r`` running over the polynomial degrees).

The `T` keyword sets the element type the weight coefficients are stored in (`Float64` by default).

The fields are
- `neighbours` — the stencil half-width ``n``, as passed.
- `smoothness` — the continuity order ``m``, as passed.
- `coefficients` — the weight polynomial's coefficients, derived from ``(n, m)`` rather than stored
  independently, which is why [`write_scheme`](@ref) persists the two parameters and no dataset.

It reproduces polynomials up to degree ``\\min(2m{+}1, 2n)`` (for ``n \\ge 1``) wherever the whole
stencil samples one branch of that polynomial — a periodic base wraps the stencil at the boundary, and
the wrapped samples come from the opposite edge, which no non-periodic polynomial continues. Special cases:
``m = 0`` is linear interpolation over the two central nodes (independent of ``n``); ``n = 1, m = 1``
is the Catmull–Rom spline (the default [`CatmullRom`](@ref), quadratic precision). For the ``C^0``
Lagrange hierarchy (degree ``2n{+}1``, all ``2n{+}2`` nodes interpolated) use [`LagrangeSpline`](@ref).
Used by [`interpolate`](@ref) (grid → point) and [`anterpolate`](@ref) (point → grid).

# References

  * C. C. Lalescu, B. Teaca, D. Carati, [*Implementation of high order spline interpolations for tracking test particles in discretized fields*](https://doi.org/10.1016/j.jcp.2009.10.046), J. Comput. Phys. **229**(17) (2010) 5862–5869.
  * C. C. Lalescu, B. Bramas, M. Rampp, M. Wilczek, [*An efficient particle tracking algorithm for large-scale parallel pseudo-spectral simulations of turbulence*](https://doi.org/10.1016/j.cpc.2022.108406) (TurTLE), Comput. Phys. Commun. **278** (2022) 108406; arXiv:2107.01104. Code: gitlab.mpcdf.mpg.de/TurTLE/turtle.
  * B. Fornberg, [*Generation of finite difference formulas on arbitrarily spaced grids*](https://doi.org/10.1090/S0025-5718-1988-0935077-0), Math. Comp. **51**(184) (1988) 699–706.
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

Local, ``C^0``, Lagrange interpolation: the unique degree-``2n{+}1`` polynomial through the ``2n{+}2``
nearest grid nodes (the stencil offsets ``\\{-n, \\dots, n{+}1\\}``, ``n \\ge 0``). The per-axis weights
are the Lagrange cardinal polynomials, stored in the ``(2n{+}2) \\times (2n{+}2)`` `SMatrix`
`coefficients`. The `n` argument is the stencil half-width: it fixes both the stencil, which reaches
`n` nodes below a point and `n + 1` above it, and the degree, so a larger `n` buys reproduction of a
higher-degree polynomial at the cost of a wider gather. It reproduces polynomials up to degree ``2n{+}1`` exactly wherever the whole stencil
samples one branch of that polynomial (a wrapped stencil draws from the opposite edge, which no
non-periodic polynomial continues), but is only ``C^0`` (the
interpolant kinks at the nodes); for smooth derivatives use [`LalescuSpline`](@ref) instead. The case ``n = 0`` is
linear interpolation over the two bracketing nodes. Matches `Lagrange_polys` of TurTLE, the reference
pseudospectral turbulence solver with Lagrangian particle tracking. The `T` keyword sets the element
type the weight coefficients are stored in (`Float64` by default).


The fields are
- `neighbours` — the stencil half-width ``n``, as passed.
- `coefficients` — the cardinal-basis weights, derived from ``n`` rather than stored
  independently, which is why [`write_scheme`](@ref) persists the parameter and no dataset.

# References

  * C. C. Lalescu, B. Teaca, D. Carati, [*Implementation of high order spline interpolations for tracking test particles in discretized fields*](https://doi.org/10.1016/j.jcp.2009.10.046), J. Comput. Phys. **229**(17) (2010) 5862–5869.
  * C. C. Lalescu, B. Bramas, M. Rampp, M. Wilczek, [*An efficient particle tracking algorithm for large-scale parallel pseudo-spectral simulations of turbulence*](https://doi.org/10.1016/j.cpc.2022.108406) (TurTLE), Comput. Phys. Commun. **278** (2022) 108406; arXiv:2107.01104. Code: gitlab.mpcdf.mpg.de/TurTLE/turtle.
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
evaluated at `evaluation_point`. A host-side helper for spline weights.

Reference: B. Fornberg, [*Generation of finite difference formulas on arbitrarily spaced grids*](https://doi.org/10.1090/S0025-5718-1988-0935077-0), Math. Comp. **51**(184) (1988) 699–706.
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

Build the ``(2n{+}2) \\times (2m{+}2)`` matrix of smooth-spline weight-polynomial coefficients (row ``q``
is the weight polynomial for stencil offset ``q - 1 - n \\in \\{-n, \\dots, n{+}1\\}``; column ``r+1`` is
the ``t^r`` coefficient). Each weight has degree ``2m{+}1``; together they form the two-point Hermite
interpolant reproducing the value and the order-``1, \\dots, m`` derivatives at the two bracketing nodes
(offsets ``0`` and ``1``), the derivatives taken from centred finite differences over a
``2n{+}1``-node stencil about each bracketing node. See [`LalescuSpline`](@ref); pinned to 1e-12 against TurTLE's weights.
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
stencil offsets ``\\{-n, \\dots, n{+}1\\}`` (row ``q`` is the cardinal polynomial of node ``q``; column
``r+1`` is the ``t^r`` coefficient). Each is the degree-``2n{+}1`` polynomial that is one at its own node
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

`CatmullRom` is the default: the cubic ``n = 1, m = 1``
[`LalescuSpline`](@ref), a four-point
``C^1`` stencil that reproduces the Catmull–Rom spline (and quadratic polynomials exactly).
"""
const CatmullRom = LalescuSpline(1, 1)


#####################################################
#        In-kernel helpers (GPU-portable)           #
#####################################################


"""
    _axis_weights(coefficients, t)

Evaluate the per-axis spline weights ``w_q(t)`` for all `N2` stencil nodes at fractional position
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
containing `coordinate`, and the fractional position ``t \\in [0, 1)`` within it. Periodic wrapping of the
stencil is applied later via `mod`. Pure scalar arithmetic, kernel-safe.
"""
@inline function _locate(coordinate::T, origin::T, spacing::T, number_of_grid_points::Int) where {T}
  continuous_index = (coordinate - origin) / spacing
  base_cell = floor(Int, continuous_index)
  return base_cell, continuous_index - base_cell
end




#####################################################
#        Traversal order (spatial locality)             #
#####################################################


# A transfer's cost is dominated by where its points READ and WRITE, not by the arithmetic on them.
# Points arrive in whatever order the consumer holds them — for a turbulence solver, the order they
# were seeded in, which is spatially random — so consecutive work-items touch unrelated parts of the
# field and every stencil is a fresh set of cache misses. Visiting them in an order that follows the
# grid makes consecutive work-items share cache lines instead.
#
# THE ORDER IS A TRAVERSAL ORDER, NOT A REORDERING. `traversal[i]` is the point that work-item `i` handles;
# nothing is moved, and each point's result still lands in its own slot. That distinction is what
# makes the option safe to add to a package whose consumer holds `PointValues` indexed alongside its
# `PointSet`: a permuted `PointSet` would desynchronise from them silently, while a traversal order
# cannot, because the arrays it indexes never change. It also makes the gather BITWISE INVARIANT
# under the order — each output element is an independent sum — which is the property the tests
# assert, and the scatter's atomic summation order changes as it already does between runs.
#
# MEASURED (2026-08-30, RTX 5070 Ti / Ryzen 9800X3D, ``256^3`` grid, ``10^6`` points, `Float64`):
# GPU gather 2.59 → 0.82 ms and scatter 7.35 → 1.86 ms; CPU gather 35.3 → 9.7 ms. The ordering
# itself costs 0.111 ms to build on device, so it repays inside a SINGLE transfer — where the
# estimate this replaces guessed 12–24. See `docs/PERFORMANCE.md` finding (ad).


# The point handled by work-item `i`. `Nothing` is the unordered case and compiles the indirection
# away, the same dispatch-on-Nothing the optional operator kernels use.
"""
    PointTraversalOrder(indices)

A `PointTraversalOrder` validates a **traversal order**: a permutation of `1:M`, for `M`
points, saying which point each unit of a transfer's work handles. Build one with [`point_traversal_order`](@ref), or wrap your
own permutation by calling this constructor, which checks it.

An order changes only the sequence in which points are handled, never the result, and it moves no
data. Entry `i` names the point that the `i`-th unit of work takes, so the point set and any
point-values indexed alongside it keep their own indexing, and every result lands in the slot it
would have landed in anyway.

The constructor throws an `ArgumentError` unless `indices` names every point in `1:M` exactly once.
It accepts any integer vector, including a `UnitRange` such as `1:M`, and keeps the storage family it
is given, since a transfer will not mix families. Use `adapt` to move one between families.

!!! warning "The guarantee is made once, at construction"
    Writing through `indices` afterwards can leave a duplicate or an out-of-range entry that no later
    call re-checks, and a transfer will then leave some points unhandled and others handled twice.
    Treat the field as read-only, and rebuild with [`point_traversal_order!`](@ref) rather than
    editing in place.

The fields are
- `indices` — the permutation itself, one point index per unit of work, in the storage family the
  constructor was given.
"""
struct PointTraversalOrder{V <: AbstractVector}
  indices::V

  function PointTraversalOrder{V}(indices::V; _validated::Bool = false) where {V <: AbstractVector}
    _validated || _validate_traversal(indices)
    return new{V}(indices)
  end
end

PointTraversalOrder(indices::V) where {V <: AbstractVector} = PointTraversalOrder{V}(indices)
# A range is a lawful spelling of an order (`1:M` is the identity, `M:-1:1` the reversal) but carries
# no storage family a kernel can index, so it is materialized into an ordinary vector.
PointTraversalOrder(indices::AbstractRange) = PointTraversalOrder(collect(Int32, indices))

# A traversal order is a validated permutation of point indices; moving it between storage families
# preserves that, so the moved order is marked validated rather than re-checked on the far side. This
# method exists because `_check_point_traversal_order`'s refusal tells a caller to use `adapt`, and
# without it that advice was Adapt's identity default — the same host order handed straight back.
adapt_structure(to, traversal::PointTraversalOrder) =
  PointTraversalOrder{typeof(adapt(to, traversal.indices))}(adapt(to, traversal.indices);
                                                            _validated = true)

Base.length(traversal::PointTraversalOrder) = length(traversal.indices)
Base.eltype(traversal::PointTraversalOrder) = eltype(traversal.indices)


@kernel function _mark_visited_kernel!(seen, @Const(indices), number_of_points)
  slot = @index(Global, Linear)
  if slot ≤ number_of_points
    @inbounds begin
      index = indices[slot]
      # The range was established before this kernel ran, so the write is in bounds.
      seen[index] = true
    end
  end
end


# Every index in `1:M`, and every one of them reached. The two together are a bijection: `M` entries
# drawn from `1:M` with all `M` targets marked leaves no room for a repeat. Both passes are reductions
# over the device's own arrays, so this never indexes an order elementwise from the host.
_validate_traversal(indices::AbstractVector) =
  _validate_traversal(indices, similar(indices, Bool, length(indices)))


function _validate_traversal(indices::AbstractVector, seen)
  number_of_points = length(indices)
  number_of_points == 0 && return nothing
  eltype(indices) <: Integer ||
    throw(ArgumentError("a point traversal order must hold integer indices, got $(eltype(indices))"))
  low, high = extrema(indices)
  (low ≥ 1 && high ≤ number_of_points) ||
    throw(ArgumentError("a point traversal order must name points in 1:$(number_of_points), but it spans " *
                        "$(low):$(high); an out-of-range index would read past the end of the point arrays"))
  backend = get_backend(indices)
  # `Bool`, not an integer width: the marks are one bit of information each. This is the array that
  # used to accumulate on a device when a consumer rebuilt the order as its points moved, which is
  # why the caller can now supply it — see `PointTraversalOrderScratch`.
  length(seen) == number_of_points ||
    throw(ArgumentError("the validation scratch holds $(length(seen)) marks but the traversal names " *
                        "$(number_of_points) points"))
  fill!(seen, false)
  _mark_visited_kernel!(backend)(seen, indices, number_of_points; ndrange = number_of_points)
  synchronize(backend)
  visited = Int(count(seen))
  visited == number_of_points ||
    throw(ArgumentError("a point traversal order must name every point exactly once, but it names " *
                        "$(visited) of $(number_of_points) — $(number_of_points - visited) are " *
                        "repeated and as many never visited, which would leave their results unwritten"))
  return nothing
end


# An order is an option, but a WRONG order is a silent wrong answer. Being a permutation is settled by
# `PointTraversalOrder`'s constructor, so what is left here is what only the CALL can know: that the order
# covers this transfer's points, and that it lives where the kernel can index it (invariant 14 binds
# every argument, the non-section ones included).
function _check_point_traversal_order(::Nothing, number_of_points, reference)
  return nothing
end

function _check_point_traversal_order(traversal::PointTraversalOrder, number_of_points, reference)
  length(traversal) == number_of_points ||
    throw(ArgumentError("the point traversal order has $(length(traversal)) entries but there are " *
                        "$(number_of_points) points; it must name every point exactly once"))
  get_backend(traversal.indices) === get_backend(reference) ||
    throw(ArgumentError("the point traversal order is on a different storage family than the field; " *
                        "build it from the same point set with `point_traversal_order`, or move it with `adapt`"))
  return nothing
end

function _check_point_traversal_order(traversal, number_of_points, reference)
  throw(ArgumentError("a point traversal order must be a `PointTraversalOrder`, got $(typeof(traversal)). Build one " *
                      "with `point_traversal_order(grid, points)`, or wrap your own permutation as " *
                      "`PointTraversalOrder(indices)`, which checks that it names every point exactly once " *
                      "— an unchecked traversal silently leaves points unvisited."))
end


@inline _visit(::Nothing, i) = i
@inline _visit(indices, i) = @inbounds Int(indices[i])


# The kernel takes the INDEX ARRAY, never the wrapper. `PointTraversalOrder` is a validity guarantee for
# the API boundary, and a struct holding a device array is not a bitstype, so a launch cannot carry
# it — which the GPU suite says out loud rather than silently. Unwrapping here keeps the guarantee
# where it is checked and gives the kernel the plain array it can index.
@inline _traversal_indices(::Nothing) = nothing
@inline _traversal_indices(traversal::PointTraversalOrder) = traversal.indices


# The block a coordinate falls in, SATURATING. `unsafe_trunc` wraps — it returns `typemin` for
# anything outside the integer range and for `Inf` and `NaN` — so truncating first and clamping after
# sent a far-away point to the NEAR block. The comparisons therefore happen in floating point, before
# any conversion. A non-finite coordinate is a real input here rather than a hypothetical: `wrap!`
# deliberately passes non-finite through so a diverged trajectory is never silently boxed, and such a
# point must still get a valid block, an order being a hint that never changes a result.
@inline function _tile_index(coordinate, origin, inverse_tile, tiles::Int64)
  u = (coordinate - origin) * inverse_tile
  isnan(u) && return Int64(0)
  u ≤ zero(u) && return Int64(0)
  u ≥ oftype(u, tiles) && return tiles - Int64(1)
  return unsafe_trunc(Int64, u)
end


@kernel function _tile_key_kernel!(keys, @Const(coordinates), origin, inverse_tile, tiles,
                                   number_of_points)
  point = @index(Global, Linear)
  if point ≤ number_of_points
    @inbounds begin
      i1 = _tile_index(coordinates[point, 1], origin[1], inverse_tile[1], tiles[1])
      i2 = _tile_index(coordinates[point, 2], origin[2], inverse_tile[2], tiles[2])
      i3 = _tile_index(coordinates[point, 3], origin[3], inverse_tile[3], tiles[3])
      # Int64 throughout: the bucket count is a product of three block counts and overflows Int32 at
      # a grid this package explicitly targets — 1291³ at `tile_size = 1` — where the wrapped
      # NEGATIVE key became an unguarded atomic write below the histogram, i.e. a segfault.
      # +1 twice: once for Julia's 1-based bucket index, once for the head slot that turns a plain
      # cumulative sum into the EXCLUSIVE prefix `_place_kernel!` needs.
      keys[point] = Int64(2) + i1 + tiles[1] * (i2 + tiles[2] * i3)
    end
  end
end


@kernel function _tile_count_kernel!(counts, @Const(keys), number_of_points)
  point = @index(Global, Linear)
  if point ≤ number_of_points
    @inbounds Atomix.@atomic counts[keys[point]] += Int32(1)
  end
end


@kernel function _place_kernel!(traversal, offsets, @Const(keys), number_of_points)
  point = @index(Global, Linear)
  if point ≤ number_of_points
    @inbounds begin
      # The atomic returns the INCREMENTED value, so the first point of a bucket takes the slot one
      # past the count of everything before it — its 1-based start. Points within a bucket land in
      # whatever order the atomics resolve, which is why this is an ORDER and not a sort: the
      # buckets are ordered, their contents are not, and nothing downstream needs them to be.
      slot = Atomix.@atomic offsets[keys[point] - Int64(1)] += Int32(1)
      traversal[slot] = Int32(point)
    end
  end
end


# The block counts a grid and a tile size imply. Shared so that an order and the scratch that refills
# it can never disagree about the bucket layout: a mismatch would index the histogram out of range.
function _traversal_tiles(grid::Grid3D, tile_size::Integer)
  tile_size ≥ 1 || throw(ArgumentError("tile_size must be at least 1, got $(tile_size)"))
  return ntuple(d -> Int64(max(cld(grid.grid_size[d], tile_size), 1)), 3)
end




# Minimum blocks per chunk for the threaded scan. Below it the two-pass form's extra read of `counts`
# costs more than the parallelism buys — measured at parity on 4096 blocks and 2.6–7.3× above 262144.
const _SCAN_CHUNK = 4096

"""
    _scan_offsets!(offsets, counts)

Write the inclusive running total of `counts` into `offsets`, and return `offsets`.

The generic method is `cumsum!`, which is a parallel scan on a device and a serial loop on the host.
The host method below threads it, because on a CPU this is the one stage of building a traversal
order that `KernelAbstractions` does not parallelise, and its cost is set by the number of blocks —
that is, by the grid — rather than by the point count. At ``512^3`` and the default `tile_size` it
was a quarter of the build at eight threads.
"""
_scan_offsets!(offsets, counts) = cumsum!(offsets, counts)


"""
    _scan_offsets!(offsets::Vector, counts::Vector)

Threaded inclusive running total on the host: each chunk sums its own slice, the chunk totals are
scanned serially (there are only as many as there are chunks), and each chunk then writes its slice
offset by the total of everything before it.

The result is **bitwise identical** to `cumsum!`, and for integers that is a property rather than a
tolerance: addition is exact and associative, so regrouping the sums cannot change them. A threaded
float reduction would need the fixed tree of decision 40; this needs nothing.

Two details are load-bearing. The chunk accumulator is declared `local`, because a name already
bound in the enclosing scope would be SHARED by every task rather than shadowed — a data race that
produced wrong answers and ran 50× slower when this was first written. And the grand total is
accumulated wide and checked against `typemax`, because `cumsum!` into a narrow integer is
overflow-checked while a plain accumulation wraps: a wrapped total becomes a negative offset, which
the placement kernel would use as an index inside `@inbounds`.
"""
function _scan_offsets!(offsets::Vector{T}, counts::Vector{T}) where {T<:Integer}
  number_of_blocks = length(counts)
  chunks = min(Threads.nthreads(), number_of_blocks ÷ _SCAN_CHUNK)
  (chunks < 2 || !_use_threads(number_of_blocks)) && return cumsum!(offsets, counts)
  edges = [1 + (c - 1) * number_of_blocks ÷ chunks for c in 1:(chunks + 1)]
  edges[end] = number_of_blocks + 1
  totals = zeros(widen(T), chunks)
  Threads.@threads for c in 1:chunks
    local run = zero(widen(T))
    @inbounds for i in edges[c]:(edges[c + 1] - 1)
      run += counts[i]
    end
    totals[c] = run
  end
  carry = zeros(widen(T), chunks)
  running = zero(widen(T))
  for c in 1:chunks
    carry[c] = running
    running += totals[c]
  end
  # `cumsum!` into a narrow integer raises on overflow; match that rather than wrapping silently.
  running ≤ typemax(T) ||
    throw(InexactError(:_scan_offsets!, T, running))
  Threads.@threads for c in 1:chunks
    local run = carry[c]
    @inbounds for i in edges[c]:(edges[c + 1] - 1)
      run += counts[i]
      offsets[i] = run % T
    end
  end
  return offsets
end


# The counting pass itself, over storage the caller owns. Both `point_traversal_order` and
# `point_traversal_order!` route through this, so the two cannot drift into computing different orders.
function _fill_traversal!(indices, grid::Grid3D{T}, points::PointSet, keys, counts, offsets,
                      tiles::NTuple{3, Int64}) where {T<:AbstractFloat}
  coordinates = point_positions(points)
  number_of_points = npoints(points)
  number_of_points == 0 && return indices
  inverse_tile = ntuple(d -> T(tiles[d]) / T(grid.domain_size[d]), 3)
  origin = ntuple(d -> T(grid.origin[d]), 3)
  backend = get_backend(coordinates)
  fill!(counts, Int32(0))
  _tile_key_kernel!(backend)(keys, coordinates, origin, inverse_tile, tiles, number_of_points;
                             ndrange = number_of_points)
  _tile_count_kernel!(backend)(counts, keys, number_of_points; ndrange = number_of_points)
  _scan_offsets!(offsets, counts)
  _place_kernel!(backend)(indices, offsets, keys, number_of_points; ndrange = number_of_points)
  synchronize(backend)
  return indices
end


# Invariant 14 binds every argument, not the obvious ones: an order built from points of one
# precision could never drive a transfer against a grid of another, and refusing here is the
# package's decision rather than a downstream method table's.
function _check_order_precision(coordinates, ::Type{T}) where {T}
  eltype(coordinates) === T ||
    throw(ArgumentError("the points hold $(eltype(coordinates)) coordinates but the grid is " *
                        "$(T); a point traversal order is built for one precision and does not convert"))
  return nothing
end


"""
    point_traversal_order(grid::Grid3D, points::PointSet; tile_size = 4)

Build a [`PointTraversalOrder`](@ref) for `points` on `grid`: a permutation of `1:M`, for a set of
`M` points, that groups points lying in the same **block** of grid cells.

Pass it as the `traversal` keyword of [`interpolate!`](@ref), [`anterpolate!`](@ref) or their
allocating siblings. A transfer's cost is dominated by where its points read and write rather than by
the arithmetic on them, and points usually arrive in an order unrelated to the grid — the order they
were seeded in, say — so consecutive units of work touch unrelated memory. Following a traversal
order makes them touch neighbouring memory instead. The result is unchanged either way.

**It is not always a gain.** Points already in a lattice or a sweep order are local already, and
ordering them adds a build for no benefit. Measure the pair on your own point set before adopting it.

The arguments are:
- `grid` — the grid whose cells the blocks are cut from, and whose origin the points are measured
  from. Points lying outside it are clamped into the edge blocks rather than refused, since an order
  is a hint and cannot change a result.
- `points` — the point set to order. Its storage family decides where the order is built and used.
- `tile_size` — the block edge in grid cells (default `4`), so each axis is divided into
  ``\\lceil N / \\texttt{tile\\_size} \\rceil`` blocks for a grid of ``N`` cells along it. Smaller
  blocks group points more tightly and cost more: the number of blocks grows as the cube of the
  reciprocal edge, and with it both the build time and the working memory — 2 MiB of counters at the
  default on a ``256^3`` grid against 128 MiB at `tile_size = 1`. The best value follows the backend
  rather than the transfer scheme: a device is insensitive to it, while a CPU prefers coarser blocks,
  up to roughly 16.

Building costs one pass over the points, a running total over the blocks, and the permutation check —
``\\approx 0.27`` ms **on a device** at ``256^3`` with ``10^6`` points, against ``0.71`` ms for one
ordered gather there, so about a third of a single transfer. On a CPU the same build is
``\\approx 9`` ms, so it pays back over more transfers.

!!! warning "Rebuild with the in-place form, not this one"
    Each call here allocates about 15 MiB at ``256^3`` with ``10^6`` points. Use this form for the
    first order and [`point_traversal_order!`](@ref) for every rebuild after it, which writes into
    storage you already hold.
"""
function point_traversal_order(grid::Grid3D{T}, points::PointSet; tile_size::Integer = 4) where {T<:AbstractFloat}
  coordinates = point_positions(points)
  _check_order_precision(coordinates, T)
  number_of_points = npoints(points)
  tiles = _traversal_tiles(grid, tile_size)
  traversal = similar(coordinates, Int32, number_of_points)
  number_of_points == 0 && return PointTraversalOrder{typeof(traversal)}(traversal; _validated = true)
  keys = similar(coordinates, Int64, number_of_points)
  # One head slot so the cumulative sum below is the exclusive prefix, and one tail slot so a point
  # in the last bucket has somewhere to count.
  counts = similar(coordinates, Int32, prod(Int.(tiles)) + 2)
  _fill_traversal!(traversal, grid, points, keys, counts, similar(counts), tiles)
  # Validated rather than trusted. These are the package's own kernels, but an atomic placement over
  # a prefix sum is exactly the shape where an arithmetic slip yields a plausible-looking array —
  # the Int32 key overflow that used to live in `_tile_key_kernel!` produced a *negative* index — and
  # the check costs two reductions against a pass that already touched every point.
  return PointTraversalOrder(traversal)
end


"""
    PointTraversalOrderScratch(grid::Grid3D, points::PointSet; tile_size = 4)

A `PointTraversalOrderScratch` holds storage for [`point_traversal_order!`](@ref), so a rebuild
allocates nothing that grows with the point count.

Build one alongside the order it will refill, and hold both for as long as the point set lives. It is
storage and nothing else: it holds no order, no transfer ever reads it, and two orders over the same
grid and point count can share one — though not at the same time, since a refill overwrites it.

The arguments are:
- `grid` — the [`Grid3D`](@ref) the order will be built against. It is stored, and a refill against a
  different grid is refused.
- `points` — a [`PointSet`](@ref) of the size and storage family the refills will use. Its positions
  are not read; only its point count, element type and backend are.
- `tile_size` — the block edge in grid cells, which fixes how many blocks the grid divides into and
  therefore how large the counters below are. A refill uses this value rather than taking one of its
  own.

!!! warning "It is sized for one point count and one block layout"
    A refill checks the point count and the block layout and refuses a mismatch rather than reading
    past an array. A point set that grows, or a different `tile_size`, needs a new scratch.

The fields are
- `keys` — the block each point falls in, one entry per point.
- `counts` — how many points fall in each block.
- `offsets` — the running total of `counts`, giving each block its starting slot.
- `seen` — one mark per point, for the permutation check.
- `tiles` — the number of blocks along each axis.
- `tile_size` — the block edge the scratch was built with.
- `grid` — the grid it was built for, compared against the rebuild's on every refill.
"""
struct PointTraversalOrderScratch{K <: AbstractVector, C <: AbstractVector, S <: AbstractVector,
                                  G <: Grid3D}
  keys::K
  counts::C
  offsets::C
  seen::S
  tiles::NTuple{3, Int64}
  tile_size::Int
  grid::G
end


function PointTraversalOrderScratch(grid::Grid3D{T}, points::PointSet;
                              tile_size::Integer = 4) where {T<:AbstractFloat}
  coordinates = point_positions(points)
  _check_order_precision(coordinates, T)
  number_of_points = npoints(points)
  tiles = _traversal_tiles(grid, tile_size)
  counts = similar(coordinates, Int32, prod(Int.(tiles)) + 2)
  return PointTraversalOrderScratch(similar(coordinates, Int64, number_of_points),
                                    counts, similar(counts),
                                    similar(coordinates, Bool, number_of_points), tiles,
                                    Int(tile_size), grid)
end


"""
    point_traversal_order!(traversal::PointTraversalOrder, grid::Grid3D,
                           points::PointSet, scratch::PointTraversalOrderScratch)

Rebuild `traversal` in place for the current positions of `points`, and return it.

Use this in-place form when `traversal` is already allocated; the allocating
[`point_traversal_order`](@ref) returns a fresh result instead. The result is the one that form would
have produced, up to the sequence of points within a block, which neither form fixes.

Reach for it when the points move. An order describes where they were when it was built, so it goes
stale as they move — never wrong, only progressively less useful — and a consumer that rebuilds it
periodically would otherwise allocate about 15 MiB at ``256^3`` with ``10^6`` points on every rebuild.
On a device that memory is freed by a collector which runs on host pressure and cannot see it, so it
accumulates. Here the result is `traversal`'s own storage and everything else is `scratch`, so
**nothing allocated per rebuild grows with the point count**: about 1.2 KiB of `KernelAbstractions`
launch bookkeeping, measured unchanged from ``10^3`` points to ``10^6``. The rebuild itself costs what
a build costs, ``\\approx 0.27`` ms on a device at ``256^3`` with ``10^6`` points and ``\\approx 9`` ms
on a CPU, which is what sets how often it is worth doing.

The arguments are:
- `traversal` — the [`PointTraversalOrder`](@ref) to overwrite, whose length fixes the point count.
- `grid` — the grid whose cells the blocks are cut from, which must be the grid the `scratch` was
  built for.
- `points` — the point set whose current positions decide the order.
- `scratch` — a [`PointTraversalOrderScratch`](@ref) built for this grid, point count and
  `tile_size`. The block edge comes from it rather than from a keyword here, so there is one source
  of truth for it.

All four must agree in point count, element type and storage family, and a mismatch is refused rather
than converted.
"""
function point_traversal_order!(traversal::PointTraversalOrder, grid::Grid3D{T}, points::PointSet,
                         scratch::PointTraversalOrderScratch) where {T<:AbstractFloat}
  coordinates = point_positions(points)
  _check_order_precision(coordinates, T)
  number_of_points = npoints(points)
  length(traversal.indices) == number_of_points ||
    throw(ArgumentError("the traversal names $(length(traversal.indices)) points but the set holds " *
                        "$(number_of_points); a traversal is rebuilt for the set it was sized for"))
  length(scratch.keys) == number_of_points ||
    throw(ArgumentError("the scratch is sized for $(length(scratch.keys)) points but the set holds " *
                        "$(number_of_points)"))
  # AGREEMENT, not fit. A "does the layout fit inside this grid" test accepted a scratch built on a
  # 16^3 grid for a rebuild on a 32^3 one, silently delivering blocks twice the requested edge. The
  # grid itself is compared, so an extent or origin change is caught too, not only a size change.
  scratch.grid == grid ||
    throw(ArgumentError("the scratch was built for a different grid than this rebuild is using; a " *
                        "scratch fixes the block layout, so it is built for one grid and one " *
                        "tile_size (here $(scratch.tile_size), giving $(scratch.tiles) blocks per axis)"))
  length(scratch.counts) == prod(Int.(scratch.tiles)) + 2 ||
    throw(ArgumentError("the scratch's histogram holds $(length(scratch.counts)) buckets but its " *
                        "block layout $(scratch.tiles) needs $(prod(Int.(scratch.tiles)) + 2)"))
  _fill_traversal!(traversal.indices, grid, points, scratch.keys, scratch.counts, scratch.offsets,
               scratch.tiles)
  # The same check the allocating form runs, against the caller's marks rather than a fresh array —
  # so the safety survives the move to a non-allocating path instead of being traded away for it.
  _validate_traversal(traversal.indices, scratch.seen)
  return traversal
end


#####################################################
#        Gather (interpolation) kernel              #
#####################################################


# One step of the periodic walk: the next node index, wrapped. The stencil visits consecutive nodes
# along each axis, so each index is its predecessor plus one — a comparison and a conditional zero,
# where `mod` is an integer division. That division is not cheap and not pipelined (7 cycles on Zen 5,
# 10 on Golden Cove), it cannot be vectorized around, and the nest called it once per stencil NODE:
# LLVM shared them down to 32 divisions per point per fibre, which is over 200 cycles of divider
# occupancy for arithmetic that is three additions and a compare.
#
# The walk is exactly equivalent, not approximately: starting from `mod(base - neighbourhood, n)` and
# stepping this way visits `mod(base - neighbourhood + t, n)` for every `t`, including when the
# stencil is WIDER than the grid and wraps more than once, because each step re-checks. The three
# leading `mod`s stay, so a negative base is handled as before. Only the index arithmetic changes:
# the multiply and accumulate order is untouched, so results are BITWISE what they were.
@inline _wrap_step(next, extent) = ifelse(next == extent, zero(next), next)


# One work-item per point. For each fibre component, accumulate the tensor-product spline sum over
# the (2n+2)³ stencil and write the point's own output slot (no atomics needed). The field array and
# the output array are indexed linearly (column-major, fibre-last), so a single kernel serves scalar,
# vector, and tensor orders.
@kernel function _interpolate_kernel!(output, @Const(coordinates), @Const(field_values), coefficients,
                                      origin, spacing, grid_size, points_per_fibre, number_of_points,
                                      traversal)
  work_item = @index(Global, Linear)
  if work_item ≤ number_of_points
    point = _visit(traversal, work_item)
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
      # The three wrapped starts, once per point rather than once per stencil node (`_wrap_step`).
      first_1 = mod(base_1 - neighbourhood, grid_x)
      first_2 = mod(base_2 - neighbourhood, grid_y)
      first_3 = mod(base_3 - neighbourhood, grid_z)
      for fibre in 1:number_of_fibres
        accumulated = zero(eltype(output))
        # Contiguous (x) axis innermost ⇒ stride-1 stencil reads: a GPU-first choice (measured a
        # large GPU speedup from cache/transaction reuse; mildly slower on CPU, whose larger caches
        # absorb the stride — invariant 6 prioritises GPU). y/z weight and plane offset are hoisted.
        node_z = first_3
        for k in 1:number_of_nodes
          node_y = first_2
          for j in 1:number_of_nodes
            weight_yz = weights_2[j] * weights_3[k]
            plane = grid_x * node_y + grid_x * grid_y * node_z + points_per_fibre * (fibre - 1)
            node_x = first_1
            for i in 1:number_of_nodes
              accumulated += weight_yz * weights_1[i] * field_values[node_x + plane + 1]
              node_x = _wrap_step(node_x + 1, grid_x)
            end
            node_y = _wrap_step(node_y + 1, grid_y)
          end
          node_z = _wrap_step(node_z + 1, grid_z)
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
                                      factor, origin, spacing, grid_size, points_per_fibre, number_of_points,
                                      traversal)
  work_item = @index(Global, Linear)
  if work_item ≤ number_of_points
    point = _visit(traversal, work_item)
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
      # The three wrapped starts, once per point rather than once per stencil node (`_wrap_step`).
      first_1 = mod(base_1 - neighbourhood, grid_x)
      first_2 = mod(base_2 - neighbourhood, grid_y)
      first_3 = mod(base_3 - neighbourhood, grid_z)
      for fibre in 1:number_of_fibres
        quantity = factor * point_quantities[point + number_of_points * (fibre - 1)]
        # Contiguous (x) axis innermost ⇒ stride-1 scatter writes (same GPU-first rationale as the
        # gather's reads). y/z weight and plane offset are hoisted out of the inner loop.
        node_z = first_3
        for k in 1:number_of_nodes
          node_y = first_2
          for j in 1:number_of_nodes
            weight_yz = weights_2[j] * weights_3[k]
            plane = grid_x * node_y + grid_x * grid_y * node_z + points_per_fibre * (fibre - 1)
            node_x = first_1
            for i in 1:number_of_nodes
              Atomix.@atomic field_values[node_x + plane + 1] += weight_yz * weights_1[i] * quantity
              node_x = _wrap_step(node_x + 1, grid_x)
            end
            node_y = _wrap_step(node_y + 1, grid_y)
          end
          node_z = _wrap_step(node_z + 1, grid_z)
        end
      end
    end
  end
end


#####################################################
#        Drivers: interpolation                     #
#####################################################


"""
    _check_transfer_colocation(field, points, values)

Check that the three operands of a grid↔point transfer carry the same scalar type and live in the same
storage family, throwing otherwise.

A transfer selects its launch backend from the field and then hands the point and value arrays to that
one kernel, so a host/device mixture reaches a launch that can only see one of them, and a mixed
precision reaches an internal locator that requires one scalar type. Both are public input errors, and
without this check both surfaced from inside the implementation instead of at the call.
"""
function _check_transfer_colocation(field, points, values)
  family(a) = Base.typename(typeof(parent(a))).wrapper
  T = field_scalar_type(field)
  eltype(point_positions(points)) === T ||
    throw(ArgumentError("point coordinates are $(eltype(point_positions(points))) but the field is $T; " *
                        "a transfer does not convert between precisions"))
  eltype(field_data(values)) === T ||
    throw(ArgumentError("point values are $(eltype(field_data(values))) but the field is $T"))
  families = (family(field_data(field)), family(point_positions(points)), family(field_data(values)))
  allequal(families) ||
    throw(ArgumentError("a transfer launches one kernel, so its field, points and values must live in " *
                        "the same storage family; got $families"))
  return nothing
end



"""
    interpolate!(out::AbstractPointValues, field::AbstractFieldPhysical,
                 points::PointSet, scheme::AbstractSplineScheme = CatmullRom)
    interpolate!(out::AbstractPointValues, field::AbstractFieldSpectral,
                 points::PointSet, scheme::DirectDFT)
    interpolate!(out::AbstractPointValues, field::AbstractFieldSpectral,
                 points::PointSet, scheme::NUFFT)

Interpolate `field` to the off-grid `points`, writing the gathered values into `out`; returns `out`. This
is the in-place home of the gather ``W``, and for a single position there is the callable `field(x)`.

Use this in-place form when `out` is already allocated; the allocating [`interpolate`](@ref) returns a
fresh result instead.

The arguments are:
- `out` — the point-value section written with the gathered values. It must match `field` in tensor
  order and cover the same number of points as `points`. The local-spline transfer is one of the few
  layers that serves tensor orders above the usual ceiling: it carries any order the field types can
  hold, third-order tensors included.
- `field` — the field to sample, in the representation the `scheme` acts on.
- `points` — the [`PointSet`](@ref) of positions to evaluate at.
- `scheme` — an [`AbstractTransferScheme`](@ref), selecting the transfer kernel and the
  representation it acts on. The physical-domain local splines ([`CatmullRom`](@ref) and the other
  [`LalescuSpline`](@ref) / [`LagrangeSpline`](@ref)) gather the nodal values of a **physical-space**
  field over a compact stencil, while [`DirectDFT`](@ref) and [`NUFFT`](@ref) evaluate a field in
  **spectral representation** in the Fourier basis; each scheme's own docstring gives its weights.
- `traversal` — an optional traversal order from [`point_traversal_order`](@ref): a permutation of the point indices
  saying which point each work item handles. It changes only the sequence in which points are
  visited, never the result — the gather is bitwise unchanged — and is worth several times the
  throughput when the points are in an order unrelated to the grid. It must name every point exactly
  once and live in the same storage family as the field; `nothing`, the default, visits them in
  index order.

The spline schemes are exact at grid nodes and for polynomials up to the scheme's reproduction degree
and approximate otherwise; the spectral schemes reconstruct the band-limited field exactly
(`DirectDFT`) or to a set tolerance (`NUFFT`).
"""
function interpolate!(out::AbstractPointValues, field::AbstractFieldPhysical, points::PointSet,
                      scheme::AbstractSplineScheme = CatmullRom; traversal = nothing)
  point_value_tensor_order(out) == field_tensor_order(field) ||
    throw(ArgumentError("output tensor order $(point_value_tensor_order(out)) must equal field tensor order $(field_tensor_order(field))"))
  _check_npoints_match(out, points)
  _check_transfer_colocation(field, points, out)
  grid = field_grid(field)
  T = field_scalar_type(field)
  coefficients = _coefficients_as(scheme, T)
  number_of_points = npoints(out)
  backend = get_backend(field_data(field))
  _check_point_traversal_order(traversal, number_of_points, field_data(field))
  _interpolate_kernel!(backend)(point_values(out), point_positions(points), field_data(field), coefficients,
    T.(grid.origin), T.(grid.grid_spacing), grid.grid_size, prod(grid.grid_size), number_of_points,
    _traversal_indices(traversal); ndrange = number_of_points)
  synchronize(backend)
  return out
end


"""
    interpolate(field::AbstractFieldPhysical, points, scheme = CatmullRom)
    interpolate(field::AbstractFieldSpectral, points, scheme::DirectDFT)
    interpolate(field::AbstractFieldSpectral, points, scheme::NUFFT)

Allocating form of [`interpolate!`](@ref): allocate a new [`AbstractPointValues`](@ref) of `field`'s
tensor order and return `field` sampled at `points`. See `interpolate!` for the schemes and their
accuracy.
"""
function interpolate(field::AbstractFieldPhysical, points::PointSet,
                     scheme::AbstractSplineScheme = CatmullRom; traversal = nothing)
  T = field_scalar_type(field)
  data = similar(point_positions(points), T, (npoints(points), fiber_shape(Val(field_tensor_order(field)))...))
  return interpolate!(_wrap_point_values(data, Val(field_tensor_order(field))), field, points, scheme; traversal)
end


"""
    (field::AbstractFieldPhysical)(x; scheme = CatmullRom)

Evaluate `field` at a single off-grid position `x` (a length-3 indexable), returning a scalar, an
`SVector{3}`, or an `SMatrix{3,3}` for a scalar, vector, or second-order-tensor field. This is the
ergonomic face of a one-point `interpolate` gather: it builds a one-point set and runs the spline
kernel. For many points, call [`interpolate`](@ref) with a [`PointSet`](@ref) instead.
The `scheme` keyword selects the transfer scheme, `CatmullRom` by default.
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
    anterpolate!(field::AbstractFieldPhysical, points::PointSet,
                 quantities::AbstractPointValues,
                 scheme::AbstractSplineScheme = CatmullRom,
                 α::Real = true, β::Real = false)
    anterpolate!(field::AbstractFieldSpectral, points::PointSet,
                 quantities::AbstractPointValues, scheme::DirectDFT,
                 α::Real = true, β::Real = false)
    anterpolate!(field::AbstractFieldSpectral, points::PointSet,
                 quantities::AbstractPointValues, scheme::NUFFT,
                 α::Real = true, β::Real = false)

Deposit (scatter) the per-point `quantities` onto `field` in place — the adjoint (transpose) of
[`interpolate!`](@ref) under the same `scheme` — computing
``\\texttt{field} = \\alpha (W^\\top q) + \\beta \\texttt{field}``; returns `field`. This is the
in-place home of the scatter ``W^\\top``.

Use this in-place form when `field` is already allocated; the allocating [`anterpolate`](@ref) returns
a fresh result instead.

Because it applies the **same** weights as the matching gather, anterpolation is the exact transpose. For
a **local-spline** scheme the weights are also a partition of unity — at any position they sum to exactly
one — and then the total deposited quantity is conserved. Other communities name
this operation *spreading* (immersed-boundary methods), *deposition* or *charge assignment*
(particle-in-cell), *projection* (PSI-Cell, particle-source-in-cell), or *gridding* (nonuniform FFTs);
*anterpolation* — the adjoint of interpolation — follows Brandt & Lubrecht (1990).

The arguments are:
- `field` — the field deposited onto, in the representation the `scheme` acts on. It shares its
  tensor order with `quantities`.
- `points` — the [`PointSet`](@ref) the quantities sit at, covering as many points as `quantities`.
- `quantities` — the per-point values to deposit.
- `scheme` — an [`AbstractTransferScheme`](@ref), selecting the transfer kernel and the
  representation: the physical-domain local splines ([`CatmullRom`](@ref) and the other
  [`LalescuSpline`](@ref) / [`LagrangeSpline`](@ref)) scatter onto a **physical-space** field, while
  [`DirectDFT`](@ref) and [`NUFFT`](@ref) deposit into a field in **spectral representation**; each
  scheme's own docstring gives the weights.
- `α` — scales the deposited contribution.
- `β` — sets the accumulation: ``\\beta = 0`` (default) overwrites `field`, ``\\beta \\ne 0``
  accumulates onto it (the `mul!` convention; accumulation is the common case for a two-way-coupling
  scatter — a deposit that accumulates onto a field the same points also sample).
- `traversal` — an optional traversal order from [`point_traversal_order`](@ref): a permutation of the point indices
  saying which point each work item handles. It changes only the sequence in which points are
  deposited, and since the accumulation is atomic its summation order was never fixed to begin with,
  so the result moves by no more than it already does between runs. It must name every point exactly
  once and live in the same storage family as the field; `nothing`, the default, visits them in
  index order.

Reference: A. Brandt, A. A. Lubrecht, [*Multilevel matrix multiplication and fast solution of integral
equations*](https://doi.org/10.1016/0021-9991%2890%2990171-V), J. Comput. Phys. **90**(2) (1990) 348–370
(an early use of "anterpolation" for the adjoint of interpolation).
"""
function anterpolate!(field::AbstractFieldPhysical, points::PointSet, quantities::AbstractPointValues,
                      scheme::AbstractSplineScheme = CatmullRom, α::Real = true, β::Real = false;
                      traversal = nothing)
  field_tensor_order(field) == point_value_tensor_order(quantities) ||
    throw(ArgumentError("field tensor order $(field_tensor_order(field)) must equal quantities tensor order $(point_value_tensor_order(quantities))"))
  _check_npoints_match(points, quantities)
  _check_transfer_colocation(field, points, quantities)
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
  _check_point_traversal_order(traversal, number_of_points, data)
  _anterpolate_kernel!(backend)(data, point_positions(points), point_values(quantities), coefficients,
    T(α), T.(grid.origin), T.(grid.grid_spacing), grid.grid_size, prod(grid.grid_size), number_of_points,
    _traversal_indices(traversal); ndrange = number_of_points)
  synchronize(backend)
  return field
end


"""
    anterpolate(grid::Grid3D, points, quantities, scheme = CatmullRom)
    anterpolate(reference::AbstractFieldSpectral, points, quantities, scheme::DirectDFT)
    anterpolate(reference::AbstractFieldSpectral, points, quantities, scheme::NUFFT)

Allocating form of [`anterpolate!`](@ref): allocate a new field of `quantities`' tensor order, deposit
(scatter) the per-point `quantities` from the positions in `points` onto it, and return it. The spline
schemes deposit onto a physical-space field on `grid`; the spectral schemes deposit into a field in
spectral representation like `reference` (same grid and layout). See `anterpolate!` for the schemes and
the ``\\alpha``/``\\beta`` accumulate form.
"""
function anterpolate(grid::Grid3D{T}, points::PointSet, quantities::AbstractPointValues,
                     scheme::AbstractSplineScheme = CatmullRom; traversal = nothing) where {T<:AbstractFloat}
  R = point_value_tensor_order(quantities)
  data = similar(point_values(quantities), T, field_physical_shape(grid, Val(R)))
  return anterpolate!(_wrap_field(data, grid, Val(R)), points, quantities, scheme; traversal)
end


#####################################################
#        Small wrappers                             #
#####################################################


# Convert a scheme's precomputed weight coefficients to the element type `T` of the field being
# transferred, so the kernel runs entirely in `T`.
_coefficients_as(scheme::AbstractSplineScheme{N2, M2}, ::Type{T}) where {N2, M2, T} = SMatrix{N2, M2, T}(spline_coefficients(scheme))

_wrap_point_values(data, ::Val{0}) = ScalarPointValues(data)
_wrap_point_values(data, ::Val{1}) = VectorPointValues(data)
_wrap_point_values(data, ::Val{R}) where {R} = TensorPointValues{R}(data)

_wrap_field(data, grid, ::Val{0}) = ScalarFieldPhysical(data, grid)
_wrap_field(data, grid, ::Val{1}) = VectorFieldPhysical(data, grid)
_wrap_field(data, grid, ::Val{R}) where {R} = TensorFieldPhysical{R}(data, grid)

# Layout-taking forms for work fields derived from a reference: the fold must follow the
# reference's fft_dims (decision 41), which the field constructors' default would drop.
_wrap_field(data, grid, layout, ::Val{0}) = ScalarFieldPhysical(data, grid, layout)
_wrap_field(data, grid, layout, ::Val{1}) = VectorFieldPhysical(data, grid, layout)
_wrap_field(data, grid, layout, ::Val{R}) where {R} = TensorFieldPhysical{R}(data, grid, layout)

_single_point_value(values::ScalarPointValues) = Array(point_values(values))[1]
_single_point_value(values::VectorPointValues) = SVector{3}(Array(point_values(values))[1, :])
_single_point_value(values::TensorPointValues{2}) = SMatrix{3, 3}(Array(point_values(values))[1, :, :])


#####################################################
#        Spectral-domain transfer: DirectDFT        #
#####################################################


"""
    DirectDFT()

The **exact** spectral-domain transfer scheme: it interpolates and anterpolates by the literal ``O(NM)``
discrete Fourier sum over the field's stored Fourier modes ``k`` and the ``M`` points (``x_p`` the
``p``-th point position, ``q_p`` the value carried there), with ``N = N_x N_y N_z`` the grid-point
count — none of the fast scheme's apparatus (no spreading window, no oversampled grid, no FFT — the
machinery of [`NUFFT`](@ref), which it validates as the oracle). It is the *definition* of the
spectral-domain adjoint pair and the transparent exact baseline; for many points or modes, prefer
`NUFFT`. It acts on a field in **spectral representation**:

```math
\\begin{aligned}
f(x_p) &= \\frac{1}{N} \\sum_{k} \\hat f(k)  e^{\\mathrm{i} k\\cdot (x_p - o)}
        = \\frac{1}{N} \\sum_{\\text{stored }k} \\alpha(k)  \\mathrm{Re}\\bigl(\\hat f(k)  e^{\\mathrm{i} k\\cdot (x_p - o)}\\bigr), \\\\
(W^\\top q)(k) &= \\sum_p q_p  e^{-\\mathrm{i} k\\cdot (x_p - o)},
\\end{aligned}
```

The second form reconstructs the real field (``o`` the grid origin) from the stored rfft half-spectrum with the
Parseval weight ``\\alpha(k) = 1`` on the self-conjugate planes — the zero plane of the folded rfft
axis and, on an even-length folded axis, its Nyquist plane — and ``2`` elsewhere. The first equality
reads an even axis's Nyquist amplitude split across ``\\pm k`` — its band-limited cosine form, which is
what the stored-``k`` sum with the weight ``\\alpha(k)`` implements; sub-Nyquist, and at the grid nodes,
the two sides agree with no convention needed.

Interpolation reproduces the band-limited field **exactly**, so it is
pointwise divergence-free on the **resolved band** — the frequencies this grid
represents, each even axis's Nyquist plane excluded — where the local splines are not, and
matches [`to_physical`](@ref) at the grid nodes;
anterpolation matches [`to_spectral`](@ref) from grid-node samples. It is stateless — build it as
`DirectDFT()` and pass it as the `scheme`.

!!! warning "Anterpolating off-node points does not give a real field's spectrum at an even axis's Nyquist"
    The deposit ``(W^\\top q)(k)`` is evaluated at every stored mode, the Nyquist planes included, and
    it is the exact adjoint of the gather there. But an even-length axis identifies its Nyquist mode
    with its own negative, so a *real* field's coefficients must satisfy
    ``\\hat g(-k) = \\overline{\\hat g(k)}`` **within** that plane, and the sum above meets that condition
    only when every point sits on a grid node of that axis: off-node, the two sides differ by
    ``e^{-2\\mathrm{i} k_a x_{p,a}} \\ne 1``. The deposited array is then the half-spectrum of no real
    field, and `to_physical` — which is the Hermitian projector — silently keeps only its
    Hermitian part, so a transform round trip does not return it unchanged. This is the same hazard
    `translation_kernel` documents for its Nyquist factor, and it is why `NUFFT`
    projects that plane out; `DirectDFT` deliberately does not, keeping the literal adjoint instead.
    The **resolved band is unaffected**, which is the band a de-aliased spectral
    computation uses.
"""
struct DirectDFT <: AbstractTransferScheme end


# True signed wavenumbers and the rfft half-spectrum Parseval weight along one array axis of a
# field in spectral representation. `stored_length` is the array's size on this axis (halved on the rfft axis `is_half`),
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


# Build the three per-axis wavenumber + weight device vectors for a field in spectral representation (host build →
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


function interpolate!(out::AbstractPointValues, field::AbstractFieldSpectral, points::PointSet, scheme::DirectDFT)
  point_value_tensor_order(out) == field_tensor_order(field) ||
    throw(ArgumentError("output tensor order $(point_value_tensor_order(out)) must equal field tensor order $(field_tensor_order(field))"))
  _check_npoints_match(out, points)
  _check_transfer_colocation(field, points, out)
  grid = field_grid(field)
  T = field_scalar_type(field)
  data = field_data(field)
  wavenumber_1, wavenumber_2, wavenumber_3, weight_1, weight_2, weight_3 = _dft_axes(field)
  n1, n2, n3 = size(data, 1), size(data, 2), size(data, 3)
  modes_per_fibre = n1 * n2 * n3
  number_of_points = npoints(out)
  backend = get_backend(data)
  _direct_dft_interpolate_kernel!(backend)(point_values(out), point_positions(points), data,
    wavenumber_1, wavenumber_2, wavenumber_3, weight_1, weight_2, weight_3,
    T.(grid.origin), one(T) / T(prod(grid.grid_size)), modes_per_fibre, number_of_points, n1, n2, n3;
    ndrange = number_of_points)
  synchronize(backend)
  return out
end


function interpolate(field::AbstractFieldSpectral, points::PointSet, scheme::DirectDFT)
  T = field_scalar_type(field)
  R = field_tensor_order(field)
  data = similar(point_positions(points), T, (npoints(points), fiber_shape(Val(R))...))
  return interpolate!(_wrap_point_values(data, Val(R)), field, points, scheme)
end


function anterpolate!(field::AbstractFieldSpectral, points::PointSet, quantities::AbstractPointValues,
                      scheme::DirectDFT, α::Real = true, β::Real = false)
  field_tensor_order(field) == point_value_tensor_order(quantities) ||
    throw(ArgumentError("field tensor order $(field_tensor_order(field)) must equal quantities tensor order $(point_value_tensor_order(quantities))"))
  _check_npoints_match(points, quantities)
  _check_transfer_colocation(field, points, quantities)
  grid = field_grid(field)
  T = field_scalar_type(field)
  data = field_data(field)
  wavenumber_1, wavenumber_2, wavenumber_3, _, _, _ = _dft_axes(field)
  n1, n2, n3 = size(data, 1), size(data, 2), size(data, 3)
  modes_per_fibre = n1 * n2 * n3
  number_of_points = npoints(quantities)
  backend = get_backend(data)
  _direct_dft_anterpolate_kernel!(backend)(data, point_positions(points), point_values(quantities),
    wavenumber_1, wavenumber_2, wavenumber_3, T.(grid.origin), T(α), T(β),
    modes_per_fibre, number_of_points, n1, n2, n3; ndrange = modes_per_fibre)
  synchronize(backend)
  return field
end


function anterpolate(reference::AbstractFieldSpectral, points::PointSet, quantities::AbstractPointValues, scheme::DirectDFT)
  out = similar_field(reference, Val(point_value_tensor_order(quantities)))
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
# Offset of the W-point stencil around a point sitting at `base + t`, with ``t \\in [0, 1)``: node
# ``i`` of the stencil is the grid node `base + (i - half)`, at distance ``(i - \\texttt{half}) - t``
# from the point, and the window is supported on ``|distance| \\le W/2``.
#
# For an EVEN width one fixed offset serves every `t`: the W nearest nodes are always
# `base-(W/2-1) … base+W/2`, every one of them inside the support. For an ODD width no fixed offset
# can be right, because the W nearest nodes are centred on `base` while ``t < 1/2`` and on `base+1`
# once ``t \\ge 1/2`` — so the stencil must follow the nearer node. Holding `half = W ÷ 2` regardless
# put the odd-width stencil a full cell off centre: its outermost node sat at distance
# ``(W+1)/2 - t > W/2`` for ``t < 1/2``, outside the support and contributing exactly zero, while the
# genuinely nearest node was never visited. A width-`W` odd stencil was therefore doing the work of a
# `W-1` one, asymmetrically, which is why asking for a tighter tolerance could return a WORSE result
# than a looser one.
@inline _stencil_half(t::T, ::Val{W}) where {T, W} =
  (isodd(W) && t < T(1) / 2) ? (W + 1) ÷ 2 : W ÷ 2


@inline function _es_weights(t::T, beta::T, ::Val{W}) where {T, W}
  half = _stencil_half(t, Val(W))
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
    # here makes type-1 and type-2 exact adjoints on the resolved band — exactly the band
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
    NUFFT(reference::AbstractFieldSpectral;
          tol = 1e-10, oversampling = 2, width = 0, beta = 0)

The **fast, approximate** spectral-domain transfer scheme: the ``O(N\\log N + M)`` windowed-gridding
(nonuniform FFT) counterpart of [`DirectDFT`](@ref) for evaluating a field in spectral representation at
scattered points and depositing point values back, agreeing with `DirectDFT` to a tolerance `tol`. It runs the transfer through an oversampled work grid and a single FFT — spreading through a smooth
compact window then transforming for the deposit, and the reverse for the evaluation, deconvolving the
coefficients before the transform and gathering through the window after it — so
it is far cheaper than the exact ``O(NM)`` sum once the point and mode counts grow; for a few points or
modes, `DirectDFT` is simpler and exact.

Build a plan once from a `reference` field in spectral representation, which fixes the grid, layout, element type, and
tensor order, then pass it as the `scheme` to [`interpolate`](@ref) / [`anterpolate`](@ref) on fields
like the reference. The arguments are:

  - `reference` — a field in spectral representation, fixing the grid, layout, element type and tensor
    order the plan is built for. The order is fixed with the rest because the plan stores oversampled
    field templates, which carry the fiber; a plan built at one order does not serve another.
  - `tol` — the target accuracy; the window width and shape default to the values that reach it. It is
    a **target**, not a guaranteed bound: it must be finite and positive, and a value finer than the
    element type can resolve widens the window as far as the formula goes and then saturates at that
    resolution rather than erroring.
  - `oversampling` — the linear oversampling factor ``\\sigma`` of the work grid (default `2`); must be **at least 2**. That is an implementation bound rather than a
    theoretical one — lower upsampling is standard with a correspondingly wider window — because the
    width and shape formulas here are fitted for ``\\sigma \\ge 2``; a value of 1 leaves no spectral guard band, so the gridding breaks down.
  - `width` — the gridding stencil width in nodes; `0` (default) picks it from `tol`.
  - `beta` — the window shape parameter, unrelated to the accumulation weight ``\\beta`` the transfer
    verbs take; `0` (default) picks it from the width.

It agrees with `DirectDFT` (hence [`to_physical`](@ref) / [`to_spectral`](@ref) at the grid nodes) to
`tol` on the resolved band (the rfft Nyquist plane is projected out), shares its adjoint
relation, and like it reconstructs the band-limited field (divergence-free on the resolved
band — the package's derivative wavenumbers are zeroed at an even axis's Nyquist frequency
while this scheme evaluates the true phase there, so a discretely divergence-free field carrying
Nyquist content is not pointwise divergence-free in the continuum).

!!! warning "A plan costs about eight times the field in memory, for its whole lifetime"
    A `NUFFT` plan holds an oversampled work grid of about ``\\sigma^3`` times the field's memory (eight
    times at the default oversampling ``\\sigma = 2``) for its whole lifetime, which matters on a
    memory-tight GPU.

The fields are:

- `width` — the gridding stencil width in nodes, as resolved from `tol`.
- `beta` — the window shape parameter, as resolved from `tol` and `width`.
- `total_oversampling` — the ratio of the oversampled point count to the reference grid's, which
  carries the transforms' normalization between the two grids.
- `reference_grid`, `reference_layout` — the base and Fourier layout the plan was built for, kept so
  a field handed to it can be checked rather than assumed compatible.
- `oversampled_grid`, `oversampled_plans` — the work grid and its transform plans.
- `deconvolution` — the per-mode reciprocal of the window's transform, dividing out the gridding.
- `oversampled_physical`, `oversampled_spectral` — the work buffers, whose contents are scratch: the
  physical one is a template copied per call and never mutated in place.

Reference: A. H. Barnett, J. Magland, L. af Klinteberg, [*A parallel nonuniform fast Fourier transform library based on an exponential of semicircle kernel*](https://doi.org/10.1137/18M120885X), SIAM J. Sci. Comput. **41**(5) (2019) C479–C504.
"""
struct NUFFT{T, PL, DC, PP, SP, LO} <: AbstractTransferScheme
  width::Int
  beta::T
  total_oversampling::T
  # The context the plan was BUILT for, kept explicitly. Only the oversampled grid used to be stored,
  # and the reference grid cannot be recovered from it, so a plan could not be checked against the
  # field it was handed — a same-order field on another domain received this plan's deconvolution and
  # oversampled plans and came back silently wrong.
  reference_grid::Grid3D{T}
  reference_layout::LO
  oversampled_grid::Grid3D{T}
  oversampled_plans::PL
  deconvolution::DC
  oversampled_physical::PP    # template (its data is copied, never mutated, per call)
  oversampled_spectral::SP
end


function NUFFT(reference::AbstractFieldSpectral{T, R}; tol::Real = 1e-10, oversampling::Integer = 2,
               width::Integer = 0, beta::Real = 0) where {T<:AbstractFloat, R}
  # `tol` sets the window width through `-log10(tol)`, so a non-positive or non-finite value produced a
  # nonsense width (or a fallback one) while the docstring still promised agreement "to `tol`". It is a
  # TARGET, not a guaranteed bound: a tolerance below the element type's own resolution simply widens
  # the window as far as the formula goes and the achieved accuracy saturates at that resolution, which
  # is why `Float32` with the default `tol` is legitimate rather than an error.
  (isfinite(tol) && tol > 0) ||
    throw(ArgumentError("NUFFT tol must be finite and positive; got $tol"))
  σ = Int(oversampling)
  σ ≥ 2 || throw(ArgumentError("NUFFT oversampling must be at least 2 (got $σ): with no oversampling the work grid has no spectral guard band, so the windowed gridding aliases across the whole resolved band and cannot reach the requested tolerance."))
  w = width > 0 ? Int(width) : _nufft_width(tol)
  β = beta > 0 ? T(beta) : _nufft_beta(w, T)
  grid = field_grid(reference)
  layout = field_layout(reference)
  data = field_data(reference)
  oversampled_size = ntuple(d -> σ * grid.grid_size[d], 3)
  oversampled_grid = Grid3D(oversampled_size, grid.domain_size; origin = grid.origin)
  physical_template = _wrap_field(similar(data, T, field_physical_shape(oversampled_grid, Val(R))), oversampled_grid, layout, Val(R))
  spectral_template = _wrap_field_spectral(similar(data, Complex{T}, field_spectral_shape(oversampled_grid, layout, Val(R))), oversampled_grid, layout, Val(R))
  plans = FieldTransformPlans(physical_template, spectral_template)
  deconvolution = _nufft_deconvolution(reference, σ, w, β)
  total_oversampling = T(prod(oversampled_size) / prod(grid.grid_size))
  return NUFFT(w, β, total_oversampling, grid, layout, oversampled_grid, plans, deconvolution,
               physical_template, spectral_template)
end


# Window gather (type-2): one work-item per point sums the W³ stencil of the oversampled physical
# field with the ES window weights (no atomics). Mirrors `_interpolate_kernel!`.
@kernel function _nufft_gather_kernel!(output, @Const(coordinates), @Const(field_values), beta,
                                       origin, spacing, grid_size, points_per_fibre, number_of_points,
                                       ::Val{W}, traversal) where {W}
  work_item = @index(Global, Linear)
  if work_item ≤ number_of_points
    point = _visit(traversal, work_item)
    @inbounds begin
      base_1, t_1 = _locate(coordinates[point, 1], origin[1], spacing[1], grid_size[1])
      base_2, t_2 = _locate(coordinates[point, 2], origin[2], spacing[2], grid_size[2])
      base_3, t_3 = _locate(coordinates[point, 3], origin[3], spacing[3], grid_size[3])
      weights_1 = _es_weights(t_1, beta, Val(W))
      weights_2 = _es_weights(t_2, beta, Val(W))
      weights_3 = _es_weights(t_3, beta, Val(W))
      # Per AXIS, not one shared offset: for an odd width the stencil follows the node nearer to
      # that axis's own fractional position, so the three axes can disagree.
      half_1 = _stencil_half(t_1, Val(W))
      half_2 = _stencil_half(t_2, Val(W))
      half_3 = _stencil_half(t_3, Val(W))
      number_of_fibres = length(field_values) ÷ points_per_fibre
      grid_x, grid_y, grid_z = grid_size
      for fibre in 1:number_of_fibres
        accumulated = zero(eltype(output))
        for k in 1:W
          node_z = mod(base_3 + (k - half_3), grid_z) + 1
          for j in 1:W
            node_y = mod(base_2 + (j - half_2), grid_y) + 1
            weight_yz = weights_2[j] * weights_3[k]
            plane = grid_x * (node_y - 1) + grid_x * grid_y * (node_z - 1) + points_per_fibre * (fibre - 1)
            for i in 1:W
              node_x = mod(base_1 + (i - half_1), grid_x) + 1
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
                                       origin, spacing, grid_size, points_per_fibre, number_of_points,
                                       ::Val{W}, traversal) where {W}
  work_item = @index(Global, Linear)
  if work_item ≤ number_of_points
    point = _visit(traversal, work_item)
    @inbounds begin
      base_1, t_1 = _locate(coordinates[point, 1], origin[1], spacing[1], grid_size[1])
      base_2, t_2 = _locate(coordinates[point, 2], origin[2], spacing[2], grid_size[2])
      base_3, t_3 = _locate(coordinates[point, 3], origin[3], spacing[3], grid_size[3])
      weights_1 = _es_weights(t_1, beta, Val(W))
      weights_2 = _es_weights(t_2, beta, Val(W))
      weights_3 = _es_weights(t_3, beta, Val(W))
      # Per AXIS, not one shared offset: for an odd width the stencil follows the node nearer to
      # that axis's own fractional position, so the three axes can disagree.
      half_1 = _stencil_half(t_1, Val(W))
      half_2 = _stencil_half(t_2, Val(W))
      half_3 = _stencil_half(t_3, Val(W))
      number_of_fibres = length(field_values) ÷ points_per_fibre
      grid_x, grid_y, grid_z = grid_size
      for fibre in 1:number_of_fibres
        quantity = point_quantities[point + number_of_points * (fibre - 1)]
        for k in 1:W
          node_z = mod(base_3 + (k - half_3), grid_z) + 1
          for j in 1:W
            node_y = mod(base_2 + (j - half_2), grid_y) + 1
            weight_yz = weights_2[j] * weights_3[k]
            plane = grid_x * (node_y - 1) + grid_x * grid_y * (node_z - 1) + points_per_fibre * (fibre - 1)
            for i in 1:W
              node_x = mod(base_1 + (i - half_1), grid_x) + 1
              Atomix.@atomic field_values[node_x + plane] += weight_yz * weights_1[i] * quantity
            end
          end
        end
      end
    end
  end
end




# A fresh oversampled work field (physical or spectral) from a stored template (never mutates it).
_fresh(template) = similar_field(template, similar(field_data(template)))


# A NUFFT plan answers the context protocol, so it can be checked against the field it is handed with
# the same predicate that compares a kernel to a field.
_context_grid(scheme::NUFFT) = scheme.reference_grid
_context_layout(scheme::NUFFT) = scheme.reference_layout


"""
    _check_nufft_compatibility(scheme::NUFFT, field::AbstractFieldSpectral)

Check that a `NUFFT` plan may be used on `field`: same base, Fourier layout, scalar type, storage
family and tensor order.

The plan precomputes an oversampled work grid, its transform plans and a deconvolution for one
specific context. Applying it to a field from another context is not a shape error that surfaces on
its own — a same-order field on a different domain has identical storage, so it silently receives the
wrong deconvolution and a work grid that resolves different wavenumbers.
"""
function _check_nufft_compatibility(scheme::NUFFT{T}, field::AbstractFieldSpectral) where {T}
  _check_matching_context(scheme, field)
  field_scalar_type(field) === T ||
    throw(ArgumentError("this NUFFT plan was built for scalar type $T, but the field carries " *
                        "$(field_scalar_type(field))"))
  Base.typename(typeof(parent(field_data(scheme.oversampled_spectral)))).wrapper ===
      Base.typename(typeof(parent(field_data(field)))).wrapper ||
    throw(ArgumentError("this NUFFT plan holds work buffers in a different storage family than the field"))
  field_tensor_order(scheme.oversampled_physical) == field_tensor_order(field) ||
    throw(ArgumentError("this NUFFT plan was built at tensor order " *
                        "$(field_tensor_order(scheme.oversampled_physical)); it cannot transfer a " *
                        "field of order $(field_tensor_order(field))"))
  return nothing
end


function interpolate!(out::AbstractPointValues, field::AbstractFieldSpectral, points::PointSet,
                      scheme::NUFFT; traversal = nothing)
  _check_point_traversal_order(traversal, npoints(out), field_data(field))
  # Decision 52 checked the plan's tensor order here, because a lower-order plan let the extract read
  # uninitialized scratch. That was one component of the plan's context; all of it is checked now.
  _check_nufft_compatibility(scheme, field)
  point_value_tensor_order(out) == field_tensor_order(field) ||
    throw(ArgumentError("output tensor order $(point_value_tensor_order(out)) must equal field tensor order $(field_tensor_order(field))"))
  _check_npoints_match(out, points)
  _check_transfer_colocation(field, points, out)
  T = field_scalar_type(field)
  backend = get_backend(field_data(field))
  oversampled_spectral = _fresh(scheme.oversampled_spectral)
  over_data = field_data(oversampled_spectral)
  fill!(over_data, zero(Complex{T}))
  # Deconvolve, then write the reference field's modes into the zero-padded oversampled grid. The
  # oversampled grid covers the same box with more points, so its modes are a superset of the
  # reference's and `embed_modes!` is exactly this step (decision 85). It carries the ratio of the two
  # point counts itself, which is the `total_oversampling` factor this line used to apply by hand.
  coarse = similar_field(field, similar(field_data(field)))
  @_assign! field_data(coarse) .= field_data(field) .* scheme.deconvolution
  embed_modes!(oversampled_spectral, coarse)
  oversampled_physical = to_physical(oversampled_spectral, scheme.oversampled_plans)
  over_grid = scheme.oversampled_grid
  _nufft_gather_kernel!(backend)(point_values(out), point_positions(points), field_data(oversampled_physical), scheme.beta,
    T.(over_grid.origin), T.(over_grid.grid_spacing), over_grid.grid_size, prod(over_grid.grid_size), npoints(out),
    Val(scheme.width), _traversal_indices(traversal); ndrange = npoints(out))
  synchronize(backend)
  return out
end


function interpolate(field::AbstractFieldSpectral, points::PointSet, scheme::NUFFT; traversal = nothing)
  T = field_scalar_type(field)
  R = field_tensor_order(field)
  data = similar(point_positions(points), T, (npoints(points), fiber_shape(Val(R))...))
  return interpolate!(_wrap_point_values(data, Val(R)), field, points, scheme; traversal)
end


function anterpolate!(field::AbstractFieldSpectral, points::PointSet, quantities::AbstractPointValues,
                      scheme::NUFFT, α::Real = true, β::Real = false; traversal = nothing)
  _check_point_traversal_order(traversal, npoints(quantities), field_data(field))
  # Decision 52 checked the plan's tensor order here, because a lower-order plan let the extract read
  # uninitialized scratch. That was one component of the plan's context; all of it is checked now.
  _check_nufft_compatibility(scheme, field)
  field_tensor_order(field) == point_value_tensor_order(quantities) ||
    throw(ArgumentError("field tensor order $(field_tensor_order(field)) must equal quantities tensor order $(point_value_tensor_order(quantities))"))
  _check_npoints_match(points, quantities)
  _check_transfer_colocation(field, points, quantities)
  T = field_scalar_type(field)
  backend = get_backend(field_data(field))
  oversampled_physical = _fresh(scheme.oversampled_physical)
  over_phys_data = field_data(oversampled_physical)
  fill!(over_phys_data, zero(T))
  over_grid = scheme.oversampled_grid
  _nufft_spread_kernel!(backend)(over_phys_data, point_positions(points), point_values(quantities), scheme.beta,
    T.(over_grid.origin), T.(over_grid.grid_spacing), over_grid.grid_size, prod(over_grid.grid_size), npoints(quantities),
    Val(scheme.width), _traversal_indices(traversal); ndrange = npoints(quantities))
  synchronize(backend)
  oversampled_spectral = to_spectral(oversampled_physical, scheme.oversampled_plans)
  # The transpose of the embed above, and the same operation read the other way: take the modes the
  # reference grid shares with the oversampled one. `extract_modes!` divides by the ratio of point
  # counts where `embed_modes!` multiplied by it, so the deposit is scaled back by
  # `total_oversampling` here to keep this pair the exact adjoint of the gather.
  # Zeroed first: `extract_modes!` writes only the shared modes, and the reference grid's own Nyquist
  # shell is not among them, so those entries would otherwise carry whatever `similar` returned. Zero
  # is also the value the scheme's contract asks for there — the Nyquist plane is outside the band the
  # NUFFT represents, and the deposit into it is what the docstring's warning above is about.
  coarse = similar_field(field, similar(field_data(field)))
  fill!(field_data(coarse), zero(Complex{T}))
  extract_modes!(coarse, oversampled_spectral)
  data = field_data(field)
  if iszero(β)
    @_assign! data .= T(α) .* field_data(coarse) .* scheme.total_oversampling .* scheme.deconvolution
  else
    @_assign! data .= T(α) .* field_data(coarse) .* scheme.total_oversampling .* scheme.deconvolution .+ T(β) .* data
  end
  return field
end


function anterpolate(reference::AbstractFieldSpectral, points::PointSet, quantities::AbstractPointValues,
                     scheme::NUFFT; traversal = nothing)
  out = similar_field(reference, Val(point_value_tensor_order(quantities)))
  return anterpolate!(out, points, quantities, scheme; traversal)
end


# Spectral-field wrappers (the spectral siblings of `_wrap_field`), for the oversampled work
# fields; they carry the reference's Fourier layout so a permuted fold survives (decision 41).
_wrap_field_spectral(data, grid, layout, ::Val{0}) = ScalarFieldSpectral(data, grid, layout)
_wrap_field_spectral(data, grid, layout, ::Val{1}) = VectorFieldSpectral(data, grid, layout)
_wrap_field_spectral(data, grid, layout, ::Val{R}) where {R} = TensorFieldSpectral{R}(data, grid, layout)


#####################################################
#        Persistence: schemes to and from HDF5      #
#####################################################
#
# A transfer scheme is a **parameter record**, not a section: it carries no base, no fiber and no
# array of its own — a spline's weight matrix is derived from its `(n, m)` and recomputed by the
# constructor. So its group holds attributes and no `data` dataset, and the round trip stores the
# parameters rather than the weights. The generics and their documentation live here so `?write_scheme`
# answers without HDF5 loaded; the methods live in the weak-dependency extension, exactly as the
# field and point pairs do.

"""
    write_scheme(parent::HDF5.H5DataStore, name::AbstractString,
                 scheme::AbstractTransferScheme)

Persist a grid↔point transfer scheme — the choice of kernel and representation that fixes how
[`interpolate`](@ref) and [`anterpolate`](@ref) are realized — as a **new HDF5 group** `name` under
`parent`, returning the group it created. Use it when a checkpoint must restore not only the
positions and values of a point set but also *how* that set samples a field, so a restarted run
transfers identically rather than falling back to a default. Reload with [`read_scheme`](@ref).

The group is **self-describing** and holds **no dataset**: a scheme's weight coefficients are
derived from its parameters, so the group carries a `type` tag, a schema `version`, the weight
element type, and the defining parameters — the neighbourhood ``n`` and, for
[`LalescuSpline`](@ref), the smoothness ``m``. Reading reconstructs through the ordinary
constructor, which recomputes the weights and revalidates the parameters, so a group asserting an
impossible combination is refused rather than producing a malformed scheme. The sugar
`parent[name] = scheme` is equivalent. `CatmullRom` needs no identity of its own: it *is*
`LalescuSpline(1, 1)` and round-trips as one, comparing equal to the alias.

Because `parent` is a handle you opened and own, this never opens or closes a file, and the package
attaches no notion of time — the consumer bundles a snapshot and owns any `time` / `iteration`
attributes.

The arguments are:
- `parent` — an open HDF5 `File` or `Group` to create the new subgroup under.
- `name` — the name of the group to create.
- `scheme` — the scheme to write: a `LalescuSpline`, a `LagrangeSpline`, or
  `DirectDFT`.

!!! warning "NUFFT is deliberately not persistable"
    Every other scheme *is* its parameters, which is what makes a few attributes a faithful record.
    A [`NUFFT`](@ref) is not: it owns oversampled FFT plans and a deconvolution window built against
    a particular reference field, so a stored copy would be either a large duplicate of derived data
    or a set of parameters pretending to be the object. It is the same class as `FieldTransformPlans`,
    which is likewise rebuilt rather than moved when storage families change. Rebuild it from the
    reference field the consumer restores anyway — `NUFFT(reference; tol)` — and write the `tol` in
    the consumer's own snapshot if it varies. Passing one here throws an `ArgumentError` naming this.

Provided by a package extension, so it is available only when [`HDF5.jl`](https://github.com/JuliaIO/HDF5.jl) is loaded.
"""
function write_scheme end


"""
    read_scheme(parent::HDF5.H5DataStore, name::AbstractString)

Reconstruct the transfer scheme written by [`write_scheme`](@ref) from the HDF5 group `name` under
`parent`, dispatching on the stored `type` attribute to return it in the matching type. The reload
is **exact**: the reconstructed scheme compares equal (`==`, and in fact `===`) to the one written,
because a scheme is fully determined by the parameters the group stores and the constructor
recomputes the weights identically.

Here `parent` is an open HDF5 `File` or `Group` holding the group, and `name` is the name (or path)
of that group under `parent`. The group's schema is **checked**, not merely read: a file from a
newer schema version, a group missing a parameter its type needs, an unrecognized type tag, or a
parameter combination the scheme's own constructor rejects all raise an `ArgumentError` rather than
producing a scheme that is not what the file claims.

Provided by a package extension, so it is available only when [`HDF5.jl`](https://github.com/JuliaIO/HDF5.jl) is loaded.
"""
function read_scheme end


# Display. See the note on the field methods in `Fields` for the conventions — the parenthesised
# compact form, the `name value` vocabulary, and the rule that nothing may read an element. The
# default prints every index: an order over 100000 points renders as 689000 characters, and a
# `NUFFT` as 2.5 million, since it owns a coarse-grid deconvolution array. One form throughout, as
# in `Points` and `Convolution`: none of these types has a stored shape that differs from the
# metadata already on the compact line.
function Base.show(io::IO, traversal::PointTraversalOrder)
  print(io, "PointTraversalOrder{", eltype(traversal.indices), "}(")
  _show_count(io, length(traversal.indices))
  print(io, ", ", nameof(_storage_family(traversal.indices)), ")")
end


function Base.show(io::IO, scratch::PointTraversalOrderScratch)
  print(io, "PointTraversalOrderScratch(")
  _show_count(io, length(scratch.keys))
  print(io, ", ")
  _show_extent(io, scratch.grid.grid_size)
  print(io, " grid")
  # The scratch is bound to the grid its keys were computed for and a rebuild against another one is
  # refused, so it shows what that comparison turns on, exactly as a field does.
  _show_domain(io, scratch.grid)
  # `tiles` is derivable from the grid and `tile_size`, and naming only the parameter avoids the
  # ambiguity of "16×16×16 blocks", which reads equally as an arrangement or as a block size.
  print(io, ", tile_size ", scratch.tile_size, ", ", nameof(_storage_family(scratch.keys)), ")")
end


# A spline scheme is a parameter record whose weight matrix is DERIVED from `(n, m)` — which is what
# decision 75 rests on when it persists one as attributes and no dataset. The default display prints
# that matrix (747 characters for `LalescuSpline(3, 2)`), so it shows the derived quantity at length
# and the two numbers it was derived from not at all. The constructor call is the honest form, and it
# round-trips.
"""
    _show_spline_eltype(io, scheme)

Print a spline scheme's element type as the `T` keyword its constructor takes, and only when it is
not the default `Float64`.

Both halves are deliberate. Printing it keeps two schemes that differ only in precision — which
invariant 14 refuses against each other — from rendering as one string. Omitting it at the default
keeps the ordinary display a bare constructor call, and writing it as the keyword rather than as a
type parameter keeps both forms valid Julia that reconstructs the scheme.
"""
function _show_spline_eltype(io::IO, scheme::AbstractSplineScheme)
  T = eltype(scheme.coefficients)
  T === Float64 || print(io, "; T = ", T)
  return nothing
end


function Base.show(io::IO, scheme::LalescuSpline)
  print(io, "LalescuSpline(", scheme.neighbours, ", ", scheme.smoothness)
  _show_spline_eltype(io, scheme)
  print(io, ")")
end


function Base.show(io::IO, scheme::LagrangeSpline)
  print(io, "LagrangeSpline(", scheme.neighbours)
  _show_spline_eltype(io, scheme)
  print(io, ")")
end


# The reference grid and layout are shown for the reason the struct keeps them: a plan handed a
# same-order field on another domain applies this one's deconvolution and work grid and comes back
# silently wrong, so `_check_matching_context` refuses that pair — and two plans it refuses against
# each other must not print alike.
function Base.show(io::IO, scheme::NUFFT)
  print(io, "NUFFT{", eltype(scheme.deconvolution), "}(")
  _show_extent(io, scheme.reference_grid.grid_size)
  print(io, " grid")
  _show_domain(io, scheme.reference_grid, scheme.reference_layout)
  print(io, ", width ", scheme.width, ", oversampling ", _approx(scheme.total_oversampling),
        ", ", nameof(_storage_family(scheme.deconvolution)), ")")
end


end # module Interpolation
