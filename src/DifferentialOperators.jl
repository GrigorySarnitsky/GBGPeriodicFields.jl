"""
    DifferentialOperators

Spectral differential operators on scalar, vector, and tensor fields over three-dimensional
rectangular periodic domains. A field in this module is its finite Fourier representation, so each
operator is the exact term-by-term derivative of that trigonometric polynomial, realized as a
coefficientwise multiply by a wavenumber symbol with no finite-difference truncation. The wavenumber
symbols are held in a [`FieldSpectralMultipliers`](@ref), built from a field with
`FieldSpectralMultipliers(field)` or from the explicit six-array constructor. Every operator provides
an allocating form and an in-place `!` form, and each per-operator docstring gives both the
physical-space meaning and the spectral symbol it applies.

The parts are:

- [`gradient`](@ref) ``\\equiv \\nabla`` raises the tensor order: a scalar field becomes a vector field, and a vector field becomes a second-order tensor field.
- [`divergence`](@ref) ``\\equiv \\nabla\\cdot`` lowers the tensor order: a vector field becomes a scalar field, and a second-order tensor field becomes a vector field; an optional kernel argument composes a convolution into the same pass.
- [`curl`](@ref) ``\\equiv \\nabla\\times`` returns the curl of a vector field, which measures its local
  rotation at **twice** the angular rate — the rate itself is ``\\tfrac{1}{2}\\nabla\\times u`` — and preserves
  the tensor order. (A fluid-dynamics consumer calls ``\\nabla\\times u`` the vorticity; the package keeps
  the neutral mathematical name, as it does for `symmetric_gradient` against "strain rate".)
- [`symmetric_gradient`](@ref) ``\\equiv \\operatorname{sym}\\nabla`` returns the symmetric part of a vector field's gradient as a second-order tensor field, formed directly without the full gradient — the fused symmetric peer of `curl`.
- [`laplacian`](@ref) ``\\equiv \\Delta`` applies the second-derivative operator to every component and preserves the tensor order.
- [`inverse_laplacian`](@ref) ``\\equiv \\Delta^{-1}`` returns the zero-mean solution of Poisson's equation and preserves the tensor order.
- [`helmholtz_projection`](@ref) ``\\equiv \\mathbb P`` projects a vector field onto its divergence-free part, in one pass whose destination may alias its source; an optional kernel argument composes a convolution into the same pass.

The Nyquist frequency is treated differently by symbol: first-derivative wavenumbers are zeroed at the
Nyquist frequency on even-length axes, while squared wavenumbers keep the true squared wavenumber
there.
"""
module DifferentialOperators


using ..Fields:
  SpectralKernel,
  _kernel_data,
  _check_kernel_compatibility,
  AbstractFieldSpectral,
  ScalarFieldSpectral,
  VectorFieldSpectral,
  TensorFieldSpectral,
  FieldSpectralMultipliers,
  field_data,
  similar_field,
  field_tensor_order,
  check_field_compatibility,
  _check_field_domain_compatibility,
  _vector_component_data,
  _tensor2_component_data,
  _check_multipliers_compatibility,
  _wavenumber_broadcast_view,
  _squared_wavenumber_broadcast


using ..FiberSections:
  _assign!,
  _foreach_outer_slab,
  @_assign!,
  _use_threads,
  _index_ranges


# The fused operators write several destination components per mode from shared source reads,
# which a single broadcast cannot express — so they are portable KernelAbstractions kernels on a
# device (like the transfer kernels in Interpolation and the shell binning in Reductions) and
# plain slab-threaded `@simd` loops on the CPU, dispatched on the backend (the `import` carries
# `KernelAbstractions.CPU` for that dispatch, the decision-30 idiom).
import KernelAbstractions
using KernelAbstractions: @kernel, @index, @Const, get_backend, synchronize


export gradient!,
       gradient,
       divergence!,
       divergence,
       curl!,
       curl,
       symmetric_gradient!,
       symmetric_gradient,
       laplacian!,
       laplacian,
       inverse_laplacian!,
       inverse_laplacian,
       helmholtz_projection!,
       helmholtz_projection


####################################################
#        Spectral Operator Kernels                 #
####################################################
#
# Coefficientwise spectral kernels for the operators below. The wavenumber
# multipliers (`FieldSpectralMultipliers`) and their compatibility and
# broadcast-view helpers live in Fields and are imported above; the Nyquist
# split between derivative and squared wavenumbers is handled there.


"""
    _apply_spectral_divergence!(destination_component,
                                source_1, source_2, source_3,
                                wavenumber_1, wavenumber_2, wavenumber_3, ::Type{T})

    _apply_spectral_divergence!(destination_component,
                                source_1, source_2, source_3,
                                wavenumber_1, wavenumber_2, wavenumber_3,
                                kernel_data, α, β, ::Type{T})

Apply a coefficientwise contraction with the wavenumber vector, computing ``\\mathrm{i} (k_1 \\hat s_1 + k_2 \\hat s_2 + k_3 \\hat s_3)``, where ``k_a`` is the wavenumber component and ``\\hat s_a`` is the source field's spectral component along axis ``a = 1, 2, 3``. The `divergence` operator uses this kernel for the vector-to-scalar case, and once per output component for the tensor-to-vector case.

The eleven-argument form composes the contraction with a coefficientwise kernel and the
``\\alpha``/``\\beta`` accumulate in the same fused pass, computing
``\\texttt{dst} \\mathrel{.=} \\alpha \\hat g \\cdot \\mathrm{i} (k_a \\hat s_a) + \\beta \\texttt{dst}``
with ``\\hat g`` = `kernel_data`, branching on `iszero(β)` to overwrite or accumulate — the
divergence analogue of `_apply_convolution!`.
"""
function _apply_spectral_divergence!(destination_component, source_component_1, source_component_2, source_component_3,
  wavenumber_1, wavenumber_2, wavenumber_3, ::Type{T}) where {T<:AbstractFloat}

  imaginary_unit = Complex{T}(zero(T), one(T))
  @_assign! destination_component .= imaginary_unit .* (wavenumber_1 .* source_component_1 .+  wavenumber_2 .* source_component_2 .+ wavenumber_3 .* source_component_3)
  return destination_component
end


function _apply_spectral_divergence!(destination_component, source_component_1, source_component_2, source_component_3,
  wavenumber_1, wavenumber_2, wavenumber_3, kernel_data, α, β, ::Type{T}) where {T<:AbstractFloat}

  imaginary_unit = Complex{T}(zero(T), one(T))
  if iszero(β)
    @_assign! destination_component .= α .* kernel_data .* (imaginary_unit .* (wavenumber_1 .* source_component_1 .+ wavenumber_2 .* source_component_2 .+ wavenumber_3 .* source_component_3))
  else
    @_assign! destination_component .= α .* kernel_data .* (imaginary_unit .* (wavenumber_1 .* source_component_1 .+ wavenumber_2 .* source_component_2 .+ wavenumber_3 .* source_component_3)) .+ β .* destination_component
  end
  return destination_component
end


"""
    _apply_spectral_laplacian!(destination_data, source_data, squared_wavenumber)

Apply the coefficientwise Laplacian symbol ``-|k|^2`` to each component, computing `destination_data .= (-).(squared_wavenumber) .* source_data`, where `squared_wavenumber` is the lazy `_squared_wavenumber_broadcast`. The kernel preserves the tensor order because it acts on every component alike.
"""
function _apply_spectral_laplacian!(destination_data, source_data, squared_wavenumber)
  @_assign! destination_data .= (-).(squared_wavenumber) .* source_data   # broadcast unary minus: composes with the lazy |k|²
  return destination_data
end


"""
    _apply_spectral_inverse_laplacian!(destination_data, source_data,
                                       squared_wavenumber, ::Type{T})

Apply the coefficientwise zero-mean inverse Laplacian, computing `-source_data ./ squared_wavenumber` at every nonzero wavevector and setting the zero Fourier mode to zero.
"""
function _apply_spectral_inverse_laplacian!(destination_data, source_data, squared_wavenumber, ::Type{T}) where {T<:AbstractFloat}
  # Multiply by the safe factor -1/|k|² (0 at the zero mode), composed as a single fused broadcast so it
  # stays allocation-free with the lazy |k|² (`_squared_wavenumber_broadcast`).
  @_assign! destination_data .= (-).(source_data) .* ifelse.(squared_wavenumber .== zero(T), zero(T), inv.(squared_wavenumber))
  return destination_data
end


"""
    _optional_kernel_value(kernel_data, mode_1, mode_2, mode_3)

Read the coefficientwise kernel value at one mode, or return the multiplicative identity `true`
when no kernel is attached (`kernel_data === nothing`). Dispatch on `Nothing` lets one fused
operator kernel serve both its plain and kernel-composed forms with the branch compiled away.
"""
@inline _optional_kernel_value(kernel_data, mode_1, mode_2, mode_3) =
  @inbounds kernel_data[mode_1, mode_2, mode_3]
@inline _optional_kernel_value(::Nothing, mode_1, mode_2, mode_3) = true


# One work-item per mode: the Leray/Helmholtz projection onto the divergence-free subspace,
# optionally composed with a coefficientwise kernel (`kernel_data`, or `nothing` for the plain
# projection) and the α/β accumulate, in one pass. The longitudinal coefficient kⱼŝⱼ/|k|² is
# computed once into a register and subtracted from all three components, so each source component
# is read once where the former three-broadcast form read each of them three times. The zero
# Fourier mode is left unchanged (safe denominator one, wavenumbers zero). The wavenumber arguments
# are the six 1-D multiplier arrays — the derivative family for the numerator, the squared family
# for the denominator, per their Nyquist split (invariant 5).
#
# All of a mode's source values are read before any of its destinations are written and modes are
# disjoint, so destination may alias source; the sources are deliberately NOT marked @Const, whose
# no-other-writes promise the aliased call would break.
@kernel function _helmholtz_projection_kernel!(destination_1, destination_2, destination_3,
    source_1, source_2, source_3,
    @Const(wavenumber_1), @Const(wavenumber_2), @Const(wavenumber_3),
    kernel_data, α, β)

  mode_1, mode_2, mode_3 = @index(Global, NTuple)
  @inbounds begin
    wavenumber_value_1 = wavenumber_1[mode_1]
    wavenumber_value_2 = wavenumber_2[mode_2]
    wavenumber_value_3 = wavenumber_3[mode_3]
    # The denominator is the derivative-family |a|², squared from the same values the numerator
    # reads — NOT the true-|k|² family — so ℙ = id − a aᵀ/(a·a) is exactly idempotent and exactly
    # annihilates the discrete divergence at every mode, Nyquist planes included (decision 42).
    # Sub-Nyquist the two families coincide bitwise, so resolved-band results are unchanged.
    squared = wavenumber_value_1 * wavenumber_value_1 + wavenumber_value_2 * wavenumber_value_2 +
              wavenumber_value_3 * wavenumber_value_3

    source_value_1 = source_1[mode_1, mode_2, mode_3]
    source_value_2 = source_2[mode_1, mode_2, mode_3]
    source_value_3 = source_3[mode_1, mode_2, mode_3]

    longitudinal = (wavenumber_value_1 * source_value_1 + wavenumber_value_2 * source_value_2 + wavenumber_value_3 * source_value_3) /
                   ifelse(iszero(squared), one(squared), squared)
    scale = α * _optional_kernel_value(kernel_data, mode_1, mode_2, mode_3)

    projected_1 = scale * (source_value_1 - wavenumber_value_1 * longitudinal)
    projected_2 = scale * (source_value_2 - wavenumber_value_2 * longitudinal)
    projected_3 = scale * (source_value_3 - wavenumber_value_3 * longitudinal)

    if iszero(β)
      destination_1[mode_1, mode_2, mode_3] = projected_1
      destination_2[mode_1, mode_2, mode_3] = projected_2
      destination_3[mode_1, mode_2, mode_3] = projected_3
    else
      destination_1[mode_1, mode_2, mode_3] = projected_1 + β * destination_1[mode_1, mode_2, mode_3]
      destination_2[mode_1, mode_2, mode_3] = projected_2 + β * destination_2[mode_1, mode_2, mode_3]
      destination_3[mode_1, mode_2, mode_3] = projected_3 + β * destination_3[mode_1, mode_2, mode_3]
    end
  end
end


"""
    _apply_helmholtz_projection!(destination, field, multipliers,
                                 kernel_data, α, β)

Run the projection over every spectral mode through `_helmholtz_projection_modes!`, which dispatches
on the backend of `destination`'s storage: a `KernelAbstractions` launch of
`_helmholtz_projection_kernel!` on a device, or the gated slab-threaded loop on a CPU. It passes the
**three** derivative-wavenumber arrays and the already-converted `α`/`β` — the projector's denominator
is formed inside the pass by squaring those same three values, so no second multiplier family is
read. The `kernel_data` is either a coefficientwise kernel's storage or `nothing` for the
plain projection. Shared by every `helmholtz_projection!` method.
"""
# The gated CPU twin of the projection kernel (the decision-38 pattern): the same per-mode
# arithmetic as `_helmholtz_projection_kernel!`, expression for expression, so the two engines are
# bitwise-equal — but run as a slab-threaded stride-1 loop through the `_use_threads` gate, which a
# KA launch cannot consult. Alias-safe for the same reason as the kernel: all of a mode's reads
# precede its writes.
function _helmholtz_projection_modes!(::KernelAbstractions.CPU,
    destination_1, destination_2, destination_3, source_1, source_2, source_3,
    wavenumber_1, wavenumber_2, wavenumber_3,
    kernel_data, α, β)
  # The denominator is the derivative-family |a|², squared from the same values the numerator reads —
  # NOT a stored true-|k|² array — so ℙ = id − a aᵀ/(a·a) is exactly idempotent and annihilates the
  # discrete divergence at every mode, Nyquist planes included (decision 42). This mirrors the KA
  # kernel; the two must agree bit-for-bit, since GPU parity compares them.
  axis_1, axis_2 = axes(source_1, 1), axes(source_1, 2)
  _foreach_outer_slab(axes(source_1, 3), 3 * length(source_1)) do outer_modes
    @inbounds for mode_3 in outer_modes
      wavenumber_value_3 = wavenumber_3[mode_3]
      squared_3 = wavenumber_value_3 * wavenumber_value_3
      for mode_2 in axis_2
        wavenumber_value_2 = wavenumber_2[mode_2]
        squared_23 = wavenumber_value_2 * wavenumber_value_2 + squared_3
        @simd for mode_1 in axis_1
          wavenumber_value_1 = wavenumber_1[mode_1]
          squared = wavenumber_value_1 * wavenumber_value_1 + squared_23
          source_value_1 = source_1[mode_1, mode_2, mode_3]
          source_value_2 = source_2[mode_1, mode_2, mode_3]
          source_value_3 = source_3[mode_1, mode_2, mode_3]
          longitudinal = (wavenumber_value_1 * source_value_1 + wavenumber_value_2 * source_value_2 + wavenumber_value_3 * source_value_3) /
                         ifelse(iszero(squared), one(squared), squared)
          scale = α * _optional_kernel_value(kernel_data, mode_1, mode_2, mode_3)
          projected_1 = scale * (source_value_1 - wavenumber_value_1 * longitudinal)
          projected_2 = scale * (source_value_2 - wavenumber_value_2 * longitudinal)
          projected_3 = scale * (source_value_3 - wavenumber_value_3 * longitudinal)
          if iszero(β)
            destination_1[mode_1, mode_2, mode_3] = projected_1
            destination_2[mode_1, mode_2, mode_3] = projected_2
            destination_3[mode_1, mode_2, mode_3] = projected_3
          else
            destination_1[mode_1, mode_2, mode_3] = projected_1 + β * destination_1[mode_1, mode_2, mode_3]
            destination_2[mode_1, mode_2, mode_3] = projected_2 + β * destination_2[mode_1, mode_2, mode_3]
            destination_3[mode_1, mode_2, mode_3] = projected_3 + β * destination_3[mode_1, mode_2, mode_3]
          end
        end
      end
    end
  end
  return nothing
end

function _helmholtz_projection_modes!(backend,
    destination_1, destination_2, destination_3, source_1, source_2, source_3,
    wavenumber_1, wavenumber_2, wavenumber_3,
    kernel_data, α, β)
  _helmholtz_projection_kernel!(backend)(
    destination_1, destination_2, destination_3, source_1, source_2, source_3,
    wavenumber_1, wavenumber_2, wavenumber_3,
    kernel_data, α, β;
    ndrange = size(destination_1))
  synchronize(backend)
  return nothing
end


function _apply_helmholtz_projection!(destination::VectorFieldSpectral{T}, field::VectorFieldSpectral{T},
    multipliers::FieldSpectralMultipliers, kernel_data, α::T, β::T) where {T<:AbstractFloat}
  _helmholtz_projection_modes!(get_backend(field_data(destination)),
    _vector_component_data(destination, 1), _vector_component_data(destination, 2), _vector_component_data(destination, 3),
    _vector_component_data(field, 1), _vector_component_data(field, 2), _vector_component_data(field, 3),
    multipliers.wavenumber_1, multipliers.wavenumber_2, multipliers.wavenumber_3,
    kernel_data, α, β)
  return destination
end


####################################################
#        Fused multi-output operator passes        #
####################################################
#
# The per-component-formula operators below — `gradient!` (both arities), `curl!`, and
# `symmetric_gradient!` — formerly ran one broadcast per output component, re-reading every shared
# source component once per formula containing it (the pass audit's standing gaps: 3×, 2×, 5×).
# Each is now one pass per mode: all needed source values are read once into registers and every
# output component is written from them, so the audit rows sit at their fused ideals. Execution is
# split by backend, the decision-30 shape: any non-CPU backend launches a KernelAbstractions
# kernel (the decision-32 Helmholtz precedent), while the CPU runs a plain typed loop — stride-1
# `@simd` inner axis, per-axis wavenumbers hoisted one loop level up — because per-element access
# through either a `Broadcasted` tree or the KA CPU backend runs well below the SIMD streaming
# rate (measured 8.6 and 17.7 GB/s against `materialize!`'s 41 on one Zen 5 core). The CPU loop
# threads by splitting the outermost mode axis into contiguous slabs through the same
# gate/cutoff/override as the broadcast route (`_use_threads`), which a KA launch cannot consult.
# The arithmetic mirrors the replaced broadcasts expression for expression — `(i k) û`, not
# `i (k û)` — so the rewrite is bitwise-identical to the broadcast form it replaces.





# --- gradient, scalar → vector -------------------------------------------------------------

# One work-item per mode: the source read once, the three components of i k ŝ written from it.
# An order-raising operator cannot alias (scalar source, vector destination), so the sources are
# @Const (unlike the aliasable Helmholtz projection and curl).
@kernel function _scalar_gradient_kernel!(destination_1, destination_2, destination_3,
    @Const(source), @Const(wavenumber_1), @Const(wavenumber_2), @Const(wavenumber_3),
    imaginary_unit)

  mode_1, mode_2, mode_3 = @index(Global, NTuple)
  @inbounds begin
    source_value = source[mode_1, mode_2, mode_3]
    destination_1[mode_1, mode_2, mode_3] = (imaginary_unit * wavenumber_1[mode_1]) * source_value
    destination_2[mode_1, mode_2, mode_3] = (imaginary_unit * wavenumber_2[mode_2]) * source_value
    destination_3[mode_1, mode_2, mode_3] = (imaginary_unit * wavenumber_3[mode_3]) * source_value
  end
end


"""
    _scalar_gradient_modes!(backend, destination_1, destination_2, destination_3,
                            source, wavenumber_1, wavenumber_2, wavenumber_3, imaginary_unit)

Run the fused scalar-gradient pass over every mode: read the source coefficient once, write the
three components of ``\\mathrm{i} k \\hat s``. The generic method launches
`_scalar_gradient_kernel!` on the backend; the `CPU` method runs the slab-threaded `@simd` loop.
"""
function _scalar_gradient_modes!(backend, destination_1, destination_2, destination_3,
    source, wavenumber_1, wavenumber_2, wavenumber_3, imaginary_unit)
  _scalar_gradient_kernel!(backend)(destination_1, destination_2, destination_3,
                                    source, wavenumber_1, wavenumber_2, wavenumber_3,
                                    imaginary_unit; ndrange = size(destination_1))
  synchronize(backend)
  return nothing
end

function _scalar_gradient_modes!(::KernelAbstractions.CPU, destination_1, destination_2, destination_3,
    source, wavenumber_1, wavenumber_2, wavenumber_3, imaginary_unit)
  axis_1, axis_2 = axes(source, 1), axes(source, 2)
  _foreach_outer_slab(axes(source, 3), 3 * length(source)) do outer_modes
    @inbounds for mode_3 in outer_modes
      scaled_wavenumber_3 = imaginary_unit * wavenumber_3[mode_3]
      for mode_2 in axis_2
        scaled_wavenumber_2 = imaginary_unit * wavenumber_2[mode_2]
        @simd for mode_1 in axis_1
          source_value = source[mode_1, mode_2, mode_3]
          destination_1[mode_1, mode_2, mode_3] = (imaginary_unit * wavenumber_1[mode_1]) * source_value
          destination_2[mode_1, mode_2, mode_3] = scaled_wavenumber_2 * source_value
          destination_3[mode_1, mode_2, mode_3] = scaled_wavenumber_3 * source_value
        end
      end
    end
  end
  return nothing
end


# --- gradient, vector → tensor -------------------------------------------------------------

# One work-item per mode: the three source components read once each, the nine components of
# i k_j û_i written from them. Order-raising, so no aliasing and the sources are @Const.
@kernel function _vector_gradient_kernel!(
    destination_11, destination_12, destination_13,
    destination_21, destination_22, destination_23,
    destination_31, destination_32, destination_33,
    @Const(source_1), @Const(source_2), @Const(source_3),
    @Const(wavenumber_1), @Const(wavenumber_2), @Const(wavenumber_3),
    imaginary_unit)

  mode_1, mode_2, mode_3 = @index(Global, NTuple)
  @inbounds begin
    scaled_wavenumber_1 = imaginary_unit * wavenumber_1[mode_1]
    scaled_wavenumber_2 = imaginary_unit * wavenumber_2[mode_2]
    scaled_wavenumber_3 = imaginary_unit * wavenumber_3[mode_3]
    source_value_1 = source_1[mode_1, mode_2, mode_3]
    source_value_2 = source_2[mode_1, mode_2, mode_3]
    source_value_3 = source_3[mode_1, mode_2, mode_3]

    destination_11[mode_1, mode_2, mode_3] = scaled_wavenumber_1 * source_value_1
    destination_12[mode_1, mode_2, mode_3] = scaled_wavenumber_2 * source_value_1
    destination_13[mode_1, mode_2, mode_3] = scaled_wavenumber_3 * source_value_1
    destination_21[mode_1, mode_2, mode_3] = scaled_wavenumber_1 * source_value_2
    destination_22[mode_1, mode_2, mode_3] = scaled_wavenumber_2 * source_value_2
    destination_23[mode_1, mode_2, mode_3] = scaled_wavenumber_3 * source_value_2
    destination_31[mode_1, mode_2, mode_3] = scaled_wavenumber_1 * source_value_3
    destination_32[mode_1, mode_2, mode_3] = scaled_wavenumber_2 * source_value_3
    destination_33[mode_1, mode_2, mode_3] = scaled_wavenumber_3 * source_value_3
  end
end


"""
    _vector_gradient_modes!(backend, destinations::NTuple{9}, sources::NTuple{3},
                            wavenumber_1, wavenumber_2, wavenumber_3, imaginary_unit)

Run the fused vector-gradient pass over every mode: read the three source coefficients once,
write the nine components of ``\\mathrm{i} k_j \\hat u_i``. Destinations are ordered row-major —
`(1,1), (1,2), (1,3), (2,1), …` — matching `_tensor2_component_data`.
"""
function _vector_gradient_modes!(backend, destinations::NTuple{9, AbstractArray},
    sources::NTuple{3, AbstractArray}, wavenumber_1, wavenumber_2, wavenumber_3, imaginary_unit)
  _vector_gradient_kernel!(backend)(destinations..., sources...,
                                    wavenumber_1, wavenumber_2, wavenumber_3,
                                    imaginary_unit; ndrange = size(destinations[1]))
  synchronize(backend)
  return nothing
end

function _vector_gradient_modes!(::KernelAbstractions.CPU, destinations::NTuple{9, AbstractArray},
    sources::NTuple{3, AbstractArray}, wavenumber_1, wavenumber_2, wavenumber_3, imaginary_unit)
  destination_11, destination_12, destination_13,
    destination_21, destination_22, destination_23,
    destination_31, destination_32, destination_33 = destinations
  source_1, source_2, source_3 = sources
  axis_1, axis_2 = axes(source_1, 1), axes(source_1, 2)
  _foreach_outer_slab(axes(source_1, 3), 9 * length(source_1)) do outer_modes
    @inbounds for mode_3 in outer_modes
      scaled_wavenumber_3 = imaginary_unit * wavenumber_3[mode_3]
      for mode_2 in axis_2
        scaled_wavenumber_2 = imaginary_unit * wavenumber_2[mode_2]
        @simd for mode_1 in axis_1
          scaled_wavenumber_1 = imaginary_unit * wavenumber_1[mode_1]
          source_value_1 = source_1[mode_1, mode_2, mode_3]
          source_value_2 = source_2[mode_1, mode_2, mode_3]
          source_value_3 = source_3[mode_1, mode_2, mode_3]
          destination_11[mode_1, mode_2, mode_3] = scaled_wavenumber_1 * source_value_1
          destination_12[mode_1, mode_2, mode_3] = scaled_wavenumber_2 * source_value_1
          destination_13[mode_1, mode_2, mode_3] = scaled_wavenumber_3 * source_value_1
          destination_21[mode_1, mode_2, mode_3] = scaled_wavenumber_1 * source_value_2
          destination_22[mode_1, mode_2, mode_3] = scaled_wavenumber_2 * source_value_2
          destination_23[mode_1, mode_2, mode_3] = scaled_wavenumber_3 * source_value_2
          destination_31[mode_1, mode_2, mode_3] = scaled_wavenumber_1 * source_value_3
          destination_32[mode_1, mode_2, mode_3] = scaled_wavenumber_2 * source_value_3
          destination_33[mode_1, mode_2, mode_3] = scaled_wavenumber_3 * source_value_3
        end
      end
    end
  end
  return nothing
end


# --- curl ------------------------------------------------------------------------------------

# One work-item per mode: the three source components read once, the three components of
# i (k × û) written from them. All of a mode's reads precede its writes and modes are disjoint,
# so destination may alias source and the former guard temporary is retired (the decision-32
# Helmholtz argument); the sources are deliberately NOT @Const, whose no-other-writes promise the
# aliased call would break.
@kernel function _curl_kernel!(destination_1, destination_2, destination_3,
    source_1, source_2, source_3,
    @Const(wavenumber_1), @Const(wavenumber_2), @Const(wavenumber_3),
    imaginary_unit)

  mode_1, mode_2, mode_3 = @index(Global, NTuple)
  @inbounds begin
    wavenumber_value_1 = wavenumber_1[mode_1]
    wavenumber_value_2 = wavenumber_2[mode_2]
    wavenumber_value_3 = wavenumber_3[mode_3]
    source_value_1 = source_1[mode_1, mode_2, mode_3]
    source_value_2 = source_2[mode_1, mode_2, mode_3]
    source_value_3 = source_3[mode_1, mode_2, mode_3]

    destination_1[mode_1, mode_2, mode_3] =
      imaginary_unit * (wavenumber_value_2 * source_value_3 - wavenumber_value_3 * source_value_2)
    destination_2[mode_1, mode_2, mode_3] =
      imaginary_unit * (wavenumber_value_3 * source_value_1 - wavenumber_value_1 * source_value_3)
    destination_3[mode_1, mode_2, mode_3] =
      imaginary_unit * (wavenumber_value_1 * source_value_2 - wavenumber_value_2 * source_value_1)
  end
end


"""
    _curl_modes!(backend, destination_1, destination_2, destination_3,
                 source_1, source_2, source_3,
                 wavenumber_1, wavenumber_2, wavenumber_3, imaginary_unit)

Run the fused curl pass over every mode: read the three source coefficients once, write the three
components of ``\\mathrm{i} (k \\times \\hat u)``. Alias-safe by construction — all of a mode's
reads precede its writes — so the destination may alias the source with no guard temporary.
"""
function _curl_modes!(backend, destination_1, destination_2, destination_3,
    source_1, source_2, source_3, wavenumber_1, wavenumber_2, wavenumber_3, imaginary_unit)
  _curl_kernel!(backend)(destination_1, destination_2, destination_3,
                         source_1, source_2, source_3,
                         wavenumber_1, wavenumber_2, wavenumber_3,
                         imaginary_unit; ndrange = size(destination_1))
  synchronize(backend)
  return nothing
end

function _curl_modes!(::KernelAbstractions.CPU, destination_1, destination_2, destination_3,
    source_1, source_2, source_3, wavenumber_1, wavenumber_2, wavenumber_3, imaginary_unit)
  axis_1, axis_2 = axes(source_1, 1), axes(source_1, 2)
  _foreach_outer_slab(axes(source_1, 3), 3 * length(source_1)) do outer_modes
    @inbounds for mode_3 in outer_modes
      wavenumber_value_3 = wavenumber_3[mode_3]
      for mode_2 in axis_2
        wavenumber_value_2 = wavenumber_2[mode_2]
        @simd for mode_1 in axis_1
          wavenumber_value_1 = wavenumber_1[mode_1]
          source_value_1 = source_1[mode_1, mode_2, mode_3]
          source_value_2 = source_2[mode_1, mode_2, mode_3]
          source_value_3 = source_3[mode_1, mode_2, mode_3]
          destination_1[mode_1, mode_2, mode_3] =
            imaginary_unit * (wavenumber_value_2 * source_value_3 - wavenumber_value_3 * source_value_2)
          destination_2[mode_1, mode_2, mode_3] =
            imaginary_unit * (wavenumber_value_3 * source_value_1 - wavenumber_value_1 * source_value_3)
          destination_3[mode_1, mode_2, mode_3] =
            imaginary_unit * (wavenumber_value_1 * source_value_2 - wavenumber_value_2 * source_value_1)
        end
      end
    end
  end
  return nothing
end


# --- symmetric gradient ----------------------------------------------------------------------

# One work-item per mode: the three source components read once, the six distinct components of
# (i/2)(k_j û_i + k_i û_j) computed once and the nine entries written (each off-diagonal value to
# its symmetric pair). Order-raising, so no aliasing and the sources are @Const. Diagonal entries
# collapse to i k_i û_i, mirroring the broadcast form they replace expression for expression.
@kernel function _symmetric_gradient_kernel!(
    destination_11, destination_12, destination_13,
    destination_21, destination_22, destination_23,
    destination_31, destination_32, destination_33,
    @Const(source_1), @Const(source_2), @Const(source_3),
    @Const(wavenumber_1), @Const(wavenumber_2), @Const(wavenumber_3),
    imaginary_unit, half_imaginary)

  mode_1, mode_2, mode_3 = @index(Global, NTuple)
  @inbounds begin
    wavenumber_value_1 = wavenumber_1[mode_1]
    wavenumber_value_2 = wavenumber_2[mode_2]
    wavenumber_value_3 = wavenumber_3[mode_3]
    source_value_1 = source_1[mode_1, mode_2, mode_3]
    source_value_2 = source_2[mode_1, mode_2, mode_3]
    source_value_3 = source_3[mode_1, mode_2, mode_3]

    destination_11[mode_1, mode_2, mode_3] = (imaginary_unit * wavenumber_value_1) * source_value_1
    destination_22[mode_1, mode_2, mode_3] = (imaginary_unit * wavenumber_value_2) * source_value_2
    destination_33[mode_1, mode_2, mode_3] = (imaginary_unit * wavenumber_value_3) * source_value_3

    symmetric_12 = half_imaginary * (wavenumber_value_2 * source_value_1 + wavenumber_value_1 * source_value_2)
    destination_12[mode_1, mode_2, mode_3] = symmetric_12
    destination_21[mode_1, mode_2, mode_3] = symmetric_12

    symmetric_13 = half_imaginary * (wavenumber_value_3 * source_value_1 + wavenumber_value_1 * source_value_3)
    destination_13[mode_1, mode_2, mode_3] = symmetric_13
    destination_31[mode_1, mode_2, mode_3] = symmetric_13

    symmetric_23 = half_imaginary * (wavenumber_value_3 * source_value_2 + wavenumber_value_2 * source_value_3)
    destination_23[mode_1, mode_2, mode_3] = symmetric_23
    destination_32[mode_1, mode_2, mode_3] = symmetric_23
  end
end


"""
    _symmetric_gradient_modes!(backend, destinations::NTuple{9}, sources::NTuple{3},
                               wavenumber_1, wavenumber_2, wavenumber_3,
                               imaginary_unit, half_imaginary)

Run the fused symmetric-gradient pass over every mode: read the three source coefficients once,
compute the six distinct components of ``\\tfrac{\\mathrm{i}}{2}(k_j \\hat u_i + k_i \\hat u_j)``
once each, and write all nine entries. Destinations are ordered row-major, matching
`_tensor2_component_data`.
"""
function _symmetric_gradient_modes!(backend, destinations::NTuple{9, AbstractArray},
    sources::NTuple{3, AbstractArray}, wavenumber_1, wavenumber_2, wavenumber_3,
    imaginary_unit, half_imaginary)
  _symmetric_gradient_kernel!(backend)(destinations..., sources...,
                                       wavenumber_1, wavenumber_2, wavenumber_3,
                                       imaginary_unit, half_imaginary; ndrange = size(destinations[1]))
  synchronize(backend)
  return nothing
end

function _symmetric_gradient_modes!(::KernelAbstractions.CPU, destinations::NTuple{9, AbstractArray},
    sources::NTuple{3, AbstractArray}, wavenumber_1, wavenumber_2, wavenumber_3,
    imaginary_unit, half_imaginary)
  destination_11, destination_12, destination_13,
    destination_21, destination_22, destination_23,
    destination_31, destination_32, destination_33 = destinations
  source_1, source_2, source_3 = sources
  axis_1, axis_2 = axes(source_1, 1), axes(source_1, 2)
  _foreach_outer_slab(axes(source_1, 3), 9 * length(source_1)) do outer_modes
    @inbounds for mode_3 in outer_modes
      wavenumber_value_3 = wavenumber_3[mode_3]
      for mode_2 in axis_2
        wavenumber_value_2 = wavenumber_2[mode_2]
        @simd for mode_1 in axis_1
          wavenumber_value_1 = wavenumber_1[mode_1]
          source_value_1 = source_1[mode_1, mode_2, mode_3]
          source_value_2 = source_2[mode_1, mode_2, mode_3]
          source_value_3 = source_3[mode_1, mode_2, mode_3]

          destination_11[mode_1, mode_2, mode_3] = (imaginary_unit * wavenumber_value_1) * source_value_1
          destination_22[mode_1, mode_2, mode_3] = (imaginary_unit * wavenumber_value_2) * source_value_2
          destination_33[mode_1, mode_2, mode_3] = (imaginary_unit * wavenumber_value_3) * source_value_3

          symmetric_12 = half_imaginary * (wavenumber_value_2 * source_value_1 + wavenumber_value_1 * source_value_2)
          destination_12[mode_1, mode_2, mode_3] = symmetric_12
          destination_21[mode_1, mode_2, mode_3] = symmetric_12

          symmetric_13 = half_imaginary * (wavenumber_value_3 * source_value_1 + wavenumber_value_1 * source_value_3)
          destination_13[mode_1, mode_2, mode_3] = symmetric_13
          destination_31[mode_1, mode_2, mode_3] = symmetric_13

          symmetric_23 = half_imaginary * (wavenumber_value_3 * source_value_2 + wavenumber_value_2 * source_value_3)
          destination_23[mode_1, mode_2, mode_3] = symmetric_23
          destination_32[mode_1, mode_2, mode_3] = symmetric_23
        end
      end
    end
  end
  return nothing
end



##########################
#        Gradient        #
##########################


"""
    gradient!(
      destination::VectorFieldSpectral,
      field::ScalarFieldSpectral,
      multipliers::FieldSpectralMultipliers,
    )

    gradient!(
      destination::TensorFieldSpectral{2},
      field::VectorFieldSpectral,
      multipliers::FieldSpectralMultipliers,
    )

Compute the gradient (`gradient` ``\\equiv \\nabla``) of a field and write it into `destination`,
returning `destination`. Differentiating raises the tensor order by one: a scalar field ``\\varphi``
gives the vector field with components ``(\\nabla\\varphi)_i = \\partial_{x_i}\\varphi``, and a vector
field ``u`` gives the second-order tensor field with components ``(\\nabla u)_{ij} = \\partial_{x_j} u_i``.

Use this in-place form when `destination` is already allocated; the allocating [`gradient`](@ref)
returns a fresh result instead.

The arguments are:
- `destination` — the field that receives the result; it shares the domain of `field` and holds one tensor order higher.
- `field` — the field to differentiate, in spectral representation.
- `multipliers` — the wavenumber symbols for the field's grid.

Each output component is the source component multiplied coefficientwise by ``\\mathrm{i}`` times the
wavenumber of the differentiation axis:

```math
\\widehat{(\\nabla\\varphi)_i}(k) = \\mathrm{i}  k_i  \\hat\\varphi(k),
\\qquad
\\widehat{(\\nabla u)_{ij}}(k) = \\mathrm{i}  k_j  \\hat u_i(k).
```
"""
function gradient! end


function gradient!(destination::VectorFieldSpectral{T}, field::ScalarFieldSpectral{T}, multipliers::FieldSpectralMultipliers) where {T<:AbstractFloat}
  _check_field_domain_compatibility(destination, field)
  _check_multipliers_compatibility(field, multipliers)

  _scalar_gradient_modes!(get_backend(field_data(destination)),
                          _vector_component_data(destination, 1),
                          _vector_component_data(destination, 2),
                          _vector_component_data(destination, 3),
                          field_data(field),
                          multipliers.wavenumber_1, multipliers.wavenumber_2, multipliers.wavenumber_3,
                          Complex{T}(zero(T), one(T)))
  return destination
end


function gradient!(destination::TensorFieldSpectral{2, T}, field::VectorFieldSpectral{T}, multipliers::FieldSpectralMultipliers) where {T<:AbstractFloat}
  _check_field_domain_compatibility(destination, field)
  _check_multipliers_compatibility(field, multipliers)

  destinations = ntuple(n -> _tensor2_component_data(destination, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9))
  sources = ntuple(n -> _vector_component_data(field, n), Val(3))
  _vector_gradient_modes!(get_backend(field_data(destination)), destinations, sources,
                          multipliers.wavenumber_1, multipliers.wavenumber_2, multipliers.wavenumber_3,
                          Complex{T}(zero(T), one(T)))
  return destination
end


"""
    gradient(field, multipliers::FieldSpectralMultipliers)

Allocating form of [`gradient!`](@ref): allocate the result and return it. A scalar field ``\\varphi``
gives its gradient vector field ``\\nabla\\varphi``; a vector field ``u`` gives the second-order tensor
field ``\\nabla u``. See `gradient!` for the componentwise definition and the spectral kernel.
"""
function gradient end


function gradient(field::ScalarFieldSpectral, multipliers::FieldSpectralMultipliers)
  destination = similar_field(field, Val(1))
  return gradient!(destination, field, multipliers)
end


function gradient(field::VectorFieldSpectral, multipliers::FieldSpectralMultipliers)
  destination = similar_field(field, Val(2))
  return gradient!(destination, field, multipliers)
end




############################
#        Divergence        #
############################


"""
    divergence!(
      destination::ScalarFieldSpectral,
      field::VectorFieldSpectral,
      multipliers::FieldSpectralMultipliers,
    )

    divergence!(
      destination::VectorFieldSpectral,
      field::TensorFieldSpectral{2},
      multipliers::FieldSpectralMultipliers,
    )

    divergence!(destination, field, multipliers, kernel::SpectralKernel)
    divergence!(destination, field, multipliers, kernel::SpectralKernel, α, β)

Compute the divergence (`divergence` ``\\equiv \\nabla\\cdot``) of a field and write it into
`destination`, returning `destination`. Differentiating lowers the tensor order by one: a vector field
``u`` gives the scalar field ``\\nabla\\cdot u = \\partial_{x_i} u_i``, and a second-order tensor field
``A`` gives the vector field with components ``(\\nabla\\cdot A)_i = \\partial_{x_j} A_{ij}``.

Use this in-place form when `destination` is already allocated; the allocating [`divergence`](@ref)
returns a fresh result instead.

The arguments are:
- `destination` — the field that receives the result; it shares the domain of `field` and holds one tensor order lower.
- `field` — the field to differentiate, in spectral representation.
- `multipliers` — the wavenumber symbols for the field's grid.

The result is the coefficientwise contraction of the source with ``\\mathrm{i}`` times the wavenumber
vector, summed over the three axes:

```math
\\widehat{\\nabla\\cdot u}(k) = \\mathrm{i} (k_1 \\hat u_1 + k_2 \\hat u_2 + k_3 \\hat u_3),
\\qquad
\\widehat{(\\nabla\\cdot A)_i}(k) = \\mathrm{i} (k_1 \\hat A_{i1} + k_2 \\hat A_{i2} + k_3 \\hat A_{i3}).
```

# The kernel-composed form

Passing a `kernel` composes the divergence with a periodic convolution in the same fused pass. As a
real physical object the result is the kernel-weighted local average of the divergence,
``g \\star (\\nabla\\cdot u)`` — a single operator, because convolution and divergence both act
coefficientwise in spectral representation, so their symbols simply multiply. The additional
arguments are:

- `kernel` — the kernel's transfer function ``\\hat g``, in any storage class of a [`SpectralKernel`](@ref) — a `StoredKernel` holding one
  coefficient per mode, or a compressed class evaluated per mode (radial,
  separable, or their product), which costs ``O(N)`` or a closure rather than ``O(N^3)``,
  exactly as `convolve!` takes it (including its reality condition on ``\\hat g``); it may
  alias `destination`, since the product is coefficientwise.
- `α`, `β` — real accumulation weights as in `convolve!`: the four-argument form overwrites
  (``\\alpha = 1``, ``\\beta = 0``), and the six-argument form computes

```math
\\widehat{\\texttt{destination}}(k) = \\alpha  \\hat g(k)  \\widehat{\\nabla\\cdot u}(k)
                                    + \\beta  \\widehat{\\texttt{destination}}(k),
```

and likewise per component for a second-order tensor `field`. The composed form replaces a
`divergence!` followed by a `convolve!` — one fused pass instead of two, saving a full read and a
full write of `destination` per call.
"""
function divergence! end


function divergence!(destination::ScalarFieldSpectral{T}, field::VectorFieldSpectral{T}, multipliers::FieldSpectralMultipliers) where {T<:AbstractFloat}
  _check_field_domain_compatibility(destination, field)
  _check_multipliers_compatibility(field, multipliers)

  _apply_spectral_divergence!(field_data(destination),
    _vector_component_data(field, 1), _vector_component_data(field, 2), _vector_component_data(field, 3),
    _wavenumber_broadcast_view(multipliers, Val(1)), _wavenumber_broadcast_view(multipliers, Val(2)), _wavenumber_broadcast_view(multipliers, Val(3)), T)

  return destination
end


function divergence!(destination::VectorFieldSpectral{T}, field::TensorFieldSpectral{2, T}, multipliers::FieldSpectralMultipliers) where {T<:AbstractFloat}
  _check_field_domain_compatibility(destination, field)
  _check_multipliers_compatibility(field, multipliers)

  wavenumber_1 = _wavenumber_broadcast_view(multipliers, Val(1))
  wavenumber_2 = _wavenumber_broadcast_view(multipliers, Val(2))
  wavenumber_3 = _wavenumber_broadcast_view(multipliers, Val(3))

  _apply_spectral_divergence!(_vector_component_data(destination, 1),
    _tensor2_component_data(field, 1, 1), _tensor2_component_data(field, 1, 2), _tensor2_component_data(field, 1, 3),
    wavenumber_1, wavenumber_2, wavenumber_3, T)

  _apply_spectral_divergence!(_vector_component_data(destination, 2),
    _tensor2_component_data(field, 2, 1), _tensor2_component_data(field, 2, 2), _tensor2_component_data(field, 2, 3),
    wavenumber_1, wavenumber_2, wavenumber_3, T)

  _apply_spectral_divergence!(_vector_component_data(destination, 3),
    _tensor2_component_data(field, 3, 1), _tensor2_component_data(field, 3, 2), _tensor2_component_data(field, 3, 3),
    wavenumber_1, wavenumber_2, wavenumber_3, T)

  return destination
end


function divergence!(destination::ScalarFieldSpectral{T}, field::VectorFieldSpectral{T}, multipliers::FieldSpectralMultipliers,
    kernel::SpectralKernel{T}) where {T<:AbstractFloat}
  return divergence!(destination, field, multipliers, kernel, one(T), zero(T))
end


function divergence!(destination::ScalarFieldSpectral{T}, field::VectorFieldSpectral{T}, multipliers::FieldSpectralMultipliers,
    kernel::SpectralKernel{T}, α::Real, β::Real) where {T<:AbstractFloat}
  _check_field_domain_compatibility(destination, field)
  _check_kernel_compatibility(field, kernel)
  _check_multipliers_compatibility(field, multipliers)

  _apply_spectral_divergence!(field_data(destination),
    _vector_component_data(field, 1), _vector_component_data(field, 2), _vector_component_data(field, 3),
    _wavenumber_broadcast_view(multipliers, Val(1)), _wavenumber_broadcast_view(multipliers, Val(2)), _wavenumber_broadcast_view(multipliers, Val(3)),
    _kernel_data(kernel), T(α), T(β), T)

  return destination
end


function divergence!(destination::VectorFieldSpectral{T}, field::TensorFieldSpectral{2, T}, multipliers::FieldSpectralMultipliers,
    kernel::SpectralKernel{T}) where {T<:AbstractFloat}
  return divergence!(destination, field, multipliers, kernel, one(T), zero(T))
end


function divergence!(destination::VectorFieldSpectral{T}, field::TensorFieldSpectral{2, T}, multipliers::FieldSpectralMultipliers,
    kernel::SpectralKernel{T}, α::Real, β::Real) where {T<:AbstractFloat}
  _check_field_domain_compatibility(destination, field)
  _check_kernel_compatibility(field, kernel)
  _check_multipliers_compatibility(field, multipliers)

  wavenumber_1 = _wavenumber_broadcast_view(multipliers, Val(1))
  wavenumber_2 = _wavenumber_broadcast_view(multipliers, Val(2))
  wavenumber_3 = _wavenumber_broadcast_view(multipliers, Val(3))
  kernel_data = _kernel_data(kernel)
  α_value = T(α)
  β_value = T(β)

  _apply_spectral_divergence!(_vector_component_data(destination, 1),
    _tensor2_component_data(field, 1, 1), _tensor2_component_data(field, 1, 2), _tensor2_component_data(field, 1, 3),
    wavenumber_1, wavenumber_2, wavenumber_3, kernel_data, α_value, β_value, T)

  _apply_spectral_divergence!(_vector_component_data(destination, 2),
    _tensor2_component_data(field, 2, 1), _tensor2_component_data(field, 2, 2), _tensor2_component_data(field, 2, 3),
    wavenumber_1, wavenumber_2, wavenumber_3, kernel_data, α_value, β_value, T)

  _apply_spectral_divergence!(_vector_component_data(destination, 3),
    _tensor2_component_data(field, 3, 1), _tensor2_component_data(field, 3, 2), _tensor2_component_data(field, 3, 3),
    wavenumber_1, wavenumber_2, wavenumber_3, kernel_data, α_value, β_value, T)

  return destination
end


"""
    divergence(field, multipliers::FieldSpectralMultipliers)
    divergence(field, multipliers::FieldSpectralMultipliers,
               kernel::SpectralKernel)

Allocating form of [`divergence!`](@ref): allocate the result and return it. A vector field ``u`` gives
its scalar divergence ``\\nabla\\cdot u``; a second-order tensor field ``A`` gives the vector field
``\\nabla\\cdot A``. With a `kernel` the result is the divergence convolved with the kernel,
``g \\star (\\nabla\\cdot u)``, in one pass. See `divergence!` for the componentwise definition, the
spectral kernel, and the kernel-composed form.
"""
function divergence end


function divergence(field::VectorFieldSpectral, multipliers::FieldSpectralMultipliers)
  destination = similar_field(field, Val(0))
  return divergence!(destination, field, multipliers)
end


function divergence(field::TensorFieldSpectral{2}, multipliers::FieldSpectralMultipliers)
  destination = similar_field(field, Val(1))
  return divergence!(destination, field, multipliers)
end


function divergence(field::VectorFieldSpectral, multipliers::FieldSpectralMultipliers, kernel::SpectralKernel)
  destination = similar_field(field, Val(0))
  return divergence!(destination, field, multipliers, kernel)
end


function divergence(field::TensorFieldSpectral{2}, multipliers::FieldSpectralMultipliers, kernel::SpectralKernel)
  destination = similar_field(field, Val(1))
  return divergence!(destination, field, multipliers, kernel)
end




######################
#        Curl        #
######################


"""
    curl!(
      destination::VectorFieldSpectral,
      field::VectorFieldSpectral,
      multipliers::FieldSpectralMultipliers,
    )

Compute the curl (`curl` ``\\equiv \\nabla\\times``) of a vector field ``u`` and write it into `destination`,
returning `destination`. The curl is the vector field whose components are, with ``\\varepsilon_{ijk}``
the Levi-Civita symbol, ``(\\nabla\\times u)_i = \\varepsilon_{ijk}  \\partial_{x_j} u_k``; written out
cyclically,

```math
\\begin{gathered}
(\\nabla\\times u)_1 = \\partial_{x_2} u_3 - \\partial_{x_3} u_2, \\\\
(\\nabla\\times u)_2 = \\partial_{x_3} u_1 - \\partial_{x_1} u_3, \\\\
(\\nabla\\times u)_3 = \\partial_{x_1} u_2 - \\partial_{x_2} u_1.
\\end{gathered}
```

Use this in-place form when `destination` is already allocated; the allocating [`curl`](@ref) returns a
fresh result instead. 
The arguments are:
- `destination` — the vector field that receives the result; it shares the domain of `field`, and
  it may alias `field` freely: the fused pass reads all three source coefficients of a mode before writing any component of it, so the aliased call needs no guard temporary and is bitwise-identical to the non-aliased one.
- `field` — the vector field to differentiate, in spectral representation.
- `multipliers` — the wavenumber symbols for the field's grid.

The spectral symbol is a coefficientwise multiply by ``\\mathrm{i}`` times the cross product with the
wavenumber vector, ``\\widehat{\\nabla\\times u}(k) = \\mathrm{i}  k \\times \\hat u(k)``, componentwise:

```math
\\begin{gathered}
\\widehat{(\\nabla\\times u)_1}(k) = \\mathrm{i} (k_2 \\hat u_3 - k_3 \\hat u_2), \\\\
\\widehat{(\\nabla\\times u)_2}(k) = \\mathrm{i} (k_3 \\hat u_1 - k_1 \\hat u_3), \\\\
\\widehat{(\\nabla\\times u)_3}(k) = \\mathrm{i} (k_1 \\hat u_2 - k_2 \\hat u_1).
\\end{gathered}
```
"""
function curl! end


function curl!(destination::VectorFieldSpectral{T}, field::VectorFieldSpectral{T}, multipliers::FieldSpectralMultipliers) where {T<:AbstractFloat}
  _check_field_domain_compatibility(destination, field)
  _check_multipliers_compatibility(field, multipliers)

  # Alias-safe by construction — the fused pass reads a mode's three source coefficients before
  # writing any of its components — so the former guard temporary is retired (decision 32's argument).
  _curl_modes!(get_backend(field_data(destination)),
               _vector_component_data(destination, 1), _vector_component_data(destination, 2),
               _vector_component_data(destination, 3),
               _vector_component_data(field, 1), _vector_component_data(field, 2),
               _vector_component_data(field, 3),
               multipliers.wavenumber_1, multipliers.wavenumber_2, multipliers.wavenumber_3,
               Complex{T}(zero(T), one(T)))
  return destination
end


"""
    curl(field, multipliers::FieldSpectralMultipliers)

Allocating form of [`curl!`](@ref): allocate the result and return it, the curl ``\\nabla\\times u`` of a
vector field. See `curl!` for the componentwise definition and the spectral kernel.
"""
function curl end


function curl(field::VectorFieldSpectral, multipliers::FieldSpectralMultipliers)
  destination = similar_field(field, Val(1))
  return curl!(destination, field, multipliers)
end




#####################################
#        Symmetric Gradient         #
#####################################


"""
    symmetric_gradient!(
      destination::TensorFieldSpectral{2},
      field::VectorFieldSpectral,
      multipliers::FieldSpectralMultipliers,
    )

Compute the symmetric gradient (`symmetric_gradient` ``\\equiv \\operatorname{sym}\\nabla``) of a vector
field ``u`` and write it into `destination`, returning `destination`. It is the symmetric part of the gradient
``\\nabla u``, the second-order tensor field

```math
S_{ij} = \\tfrac{1}{2} (\\partial_{x_j} u_i + \\partial_{x_i} u_j),
```

formed directly. It is the fused symmetric peer of [`curl`](@ref), which extracts the *antisymmetric* part
of ``\\nabla u`` as a vector: forming ``S`` this way skips the full nine-component gradient tensor that
`sym(gradient(u))` builds only to symmetrize, so reach for it whenever the symmetric part is all you need.

Use this in-place form when `destination` is already allocated; the allocating [`symmetric_gradient`](@ref)
returns a fresh result instead.

The arguments are:
- `destination` — the second-order tensor field that receives the result; it shares the domain of `field` and holds one tensor order higher.
- `field` — the vector field to differentiate, in spectral representation.
- `multipliers` — the wavenumber symbols for the field's grid.

The spectral symbol symmetrizes ``\\mathrm{i} k_j \\hat u_i`` in its two indices:

```math
\\widehat{S_{ij}}(k) = \\tfrac{\\mathrm{i}}{2} \\bigl(k_j \\hat u_i(k) + k_i \\hat u_j(k)\\bigr).
```
"""
function symmetric_gradient! end


function symmetric_gradient!(destination::TensorFieldSpectral{2, T}, field::VectorFieldSpectral{T}, multipliers::FieldSpectralMultipliers) where {T<:AbstractFloat}
  _check_field_domain_compatibility(destination, field)
  _check_multipliers_compatibility(field, multipliers)

  # Diagonal Sᵢᵢ = i·kᵢ·ûᵢ (the ½(kᵢûᵢ + kᵢûᵢ) collapses); off-diagonal Sᵢⱼ = (i/2)(kⱼûᵢ + kᵢûⱼ),
  # computed once per symmetric pair inside the fused pass. An order-raising operator writes a tensor
  # from a vector, so destination and source occupy distinct storage and cannot alias.
  destinations = ntuple(n -> _tensor2_component_data(destination, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9))
  sources = ntuple(n -> _vector_component_data(field, n), Val(3))
  imaginary_unit = Complex{T}(zero(T), one(T))
  _symmetric_gradient_modes!(get_backend(field_data(destination)), destinations, sources,
                             multipliers.wavenumber_1, multipliers.wavenumber_2, multipliers.wavenumber_3,
                             imaginary_unit, imaginary_unit * inv(T(2)))
  return destination
end


"""
    symmetric_gradient(field::VectorFieldSpectral,
                       multipliers::FieldSpectralMultipliers)

Allocating form of [`symmetric_gradient!`](@ref): allocate the result and return it, the symmetric
gradient ``\\operatorname{sym}\\nabla u`` — the symmetric part of ``\\nabla u`` as a second-order tensor
field, formed without the full gradient. See `symmetric_gradient!` for the componentwise definition and the
spectral kernel.
"""
function symmetric_gradient end


function symmetric_gradient(field::VectorFieldSpectral, multipliers::FieldSpectralMultipliers)
  destination = similar_field(field, Val(2))
  return symmetric_gradient!(destination, field, multipliers)
end




###########################
#        Laplacian        #
###########################


"""
    laplacian!(
      destination::AbstractFieldSpectral,
      field::AbstractFieldSpectral,
      multipliers::FieldSpectralMultipliers,
    )

Compute the Laplacian (`laplacian` ``\\equiv \\Delta``) of a field and write it into `destination`,
returning `destination`. The Laplacian is a local operator: it sums the second partial derivatives of
a scalar field ``f`` over the three axes, and it acts on each component of a vector or tensor field
alike, so it preserves the tensor order:

```math
\\Delta f = \\partial^2_{x_i x_i} f, \\qquad (\\Delta u)_j = \\partial^2_{x_i x_i} u_j.
```

Use this in-place form when `destination` is already allocated; the allocating [`laplacian`](@ref)
returns a fresh result instead.

The arguments are:
- `destination` — the field that receives the result; it matches the domain and tensor order of `field`.
- `field` — the field to differentiate, in spectral representation.
- `multipliers` — the wavenumber symbols for the field's grid.

The spectral symbol is a coefficientwise multiply by ``-|k|^2``:

```math
\\widehat{\\Delta f}(k) = -|k|^2  \\hat f(k), \\qquad |k|^2 = k_1^2 + k_2^2 + k_3^2.
```
"""
function laplacian! end


function laplacian!(destination::AbstractFieldSpectral{T, R}, field::AbstractFieldSpectral{T, R}, multipliers::FieldSpectralMultipliers) where {T<:AbstractFloat, R}
  check_field_compatibility(destination, field)
  _check_multipliers_compatibility(field, multipliers)

  squared_wavenumber = _squared_wavenumber_broadcast(multipliers)
  _apply_spectral_laplacian!(field_data(destination), field_data(field), squared_wavenumber)
  return destination
end


"""
    laplacian(field::AbstractFieldSpectral, multipliers::FieldSpectralMultipliers)

Allocating form of [`laplacian!`](@ref): allocate the result and return it, the Laplacian ``\\Delta f``.
Representation-preserving (scalar, vector, or tensor field of the same tensor order). See `laplacian!` for
the spectral form ``-|k|^2``.
"""
function laplacian end


function laplacian(field::AbstractFieldSpectral, multipliers::FieldSpectralMultipliers)
  destination = similar_field(field, Val(field_tensor_order(field)))
  return laplacian!(destination, field, multipliers)
end




###################################
#        Inverse Laplacian        #
###################################


"""
    inverse_laplacian!(
      destination::AbstractFieldSpectral,
      field::AbstractFieldSpectral,
      multipliers::FieldSpectralMultipliers,
    )

Compute the zero-mean inverse Laplacian (`inverse_laplacian` ``\\equiv \\Delta^{-1}``) of a field ``f`` and
write it into `destination`, returning `destination`. For a mean-free right-hand side the result is
the zero-mean field ``\\psi`` solving Poisson's equation — on a periodic box the system is solvable
only when ``\\int_\\Omega f\\,\\mathrm{d}x = 0``, since any periodic ``\\psi`` has
``\\int_\\Omega \\Delta\\psi\\,\\mathrm{d}x = 0`` — and because the Laplacian annihilates constants,
the solution is fixed uniquely by requiring its mean to vanish:

```math
\\Delta\\psi = f, \\qquad \\int_\\Omega f\\,\\mathrm{d}x = 0, \\qquad \\int_\\Omega \\psi \\,\\mathrm{d}x = 0.
```

A general input is projected onto that compatible part: the result's zero Fourier mode is set to
zero unconditionally, so the operator returns the zero-mean solution of ``\\Delta\\psi = f - \\bar f``
(``\\bar f`` the input's mean); the per-mode form below is the unconditional statement.

For a vector or tensor field the same solve is applied to each component, so the tensor order is
preserved.

!!! warning "The inverse Laplacian is nonlocal"
    As the inverse of a differential operator, ``\\Delta^{-1}`` is nonlocal: unlike the Laplacian it
    has no local partial-derivative formula, and the value at any point depends on the whole field.

Use this in-place form when `destination` is already allocated; the allocating
[`inverse_laplacian`](@ref) returns a fresh result instead.

The arguments are:
- `destination` — the field that receives the result; it matches the domain and tensor order of `field`.
- `field` — the field to invert, in spectral representation.
- `multipliers` — the wavenumber symbols for the field's grid.

The spectral symbol divides by ``-|k|^2`` away from the origin and sets the zero Fourier mode to zero:

```math
\\widehat{\\Delta^{-1} f}(k) =
\\begin{cases}
- \\hat f(k) / |k|^2, & k \\ne 0, \\\\
0, & k = 0.
\\end{cases}
```
"""
function inverse_laplacian! end


function inverse_laplacian!(destination::AbstractFieldSpectral{T, R}, field::AbstractFieldSpectral{T, R}, multipliers::FieldSpectralMultipliers) where {T<:AbstractFloat, R}
  check_field_compatibility(destination, field)
  _check_multipliers_compatibility(field, multipliers)

  squared_wavenumber = _squared_wavenumber_broadcast(multipliers)
  _apply_spectral_inverse_laplacian!(field_data(destination), field_data(field), squared_wavenumber, T)
  return destination
end


"""
    inverse_laplacian(field::AbstractFieldSpectral,
                      multipliers::FieldSpectralMultipliers)

Allocating form of [`inverse_laplacian!`](@ref): allocate the result and return it, the zero-mean inverse
Laplacian ``\\Delta^{-1} f`` (the zero Fourier mode is set to zero). Representation-preserving (scalar,
vector, or tensor field of the same tensor order). See `inverse_laplacian!` for the spectral form.
"""
function inverse_laplacian end


function inverse_laplacian(field::AbstractFieldSpectral, multipliers::FieldSpectralMultipliers)
  destination = similar_field(field, Val(field_tensor_order(field)))
  return inverse_laplacian!(destination, field, multipliers)
end




########################################
#        Helmholtz Projection          #
########################################


"""
    helmholtz_projection!(
      destination::VectorFieldSpectral,
      field::VectorFieldSpectral,
      multipliers::FieldSpectralMultipliers,
    )

    helmholtz_projection!(destination, field, multipliers, kernel::SpectralKernel)
    helmholtz_projection!(destination, field, multipliers,
                          kernel::SpectralKernel, α, β)

Compute the Helmholtz (Leray) projection (`helmholtz_projection` ``\\equiv \\mathbb P``) of a vector
field ``u`` and write it into `destination`, returning `destination`. The projection removes the
longitudinal (curl-free) part of the field and keeps the divergence-free part, subtracting the
gradient of the pressure-like potential that solves the divergence:

```math
\\mathbb P u = u - \\nabla  \\Delta^{-1}(\\nabla\\cdot u),
```

an identity exact on the resolved band (the inverse Laplacian keeps the true ``k^2`` while the
projector is built from the derivative family — the two coincide off the Nyquist planes). The
implemented operator is the **exact orthogonal projector onto the kernel of the discrete
divergence**: ``\\mathbb P^2 = \\mathbb P``, and the divergence of the result vanishes, at every
mode — the Nyquist planes included.

!!! warning "The projection is nonlocal in physical space"
    The inverse Laplacian ``\\Delta^{-1}`` is nonlocal, so ``\\mathbb P`` is a nonlocal operator in
    physical space even though it acts coefficientwise in spectral representation.

Use this in-place form when `destination` is already allocated; the allocating
[`helmholtz_projection`](@ref) returns a fresh result instead. 
The arguments are:
- `destination` — the vector field that receives the result; it shares the domain of `field`, and
  it may alias `field` at no cost: the projection is computed in a single pass that reads all three components of a mode before writing any of them, so the aliased call needs no temporary.
- `field` — the vector field to project, in spectral representation.
- `multipliers` — the wavenumber symbols for the field's grid.

The spectral symbol subtracts the longitudinal part ``a_i (a\\cdot\\hat u)/|a|^2`` from
``\\hat u_i``, with ``a`` the derivative wavenumber — the Nyquist-zeroed family the gradient and
divergence use, equal to ``k`` on the resolved band — and passes every mode with ``a = 0``
unchanged (the zero mode, and the pure-Nyquist corners where the whole derivative wavenumber
vanishes):

```math
\\widehat{(\\mathbb P u)}_i(k) = \\Bigl(\\delta_{ij} - \\frac{a_i a_j}{|a|^2}\\Bigr)  \\hat u_j(k),
\\qquad \\delta_{ij} \\text{ the Kronecker delta}, \\qquad a \\ne 0.
```

# The kernel-composed form

Passing a `kernel` composes the projection with a periodic convolution in the same fused pass. As a
real physical object the result is the kernel-weighted local average of the projected field,
``g \\star (\\mathbb P u)`` — a single operator, because convolution and projection both act
coefficientwise in spectral representation, so the scalar symbol ``\\hat g`` multiplies the
projection symbol. The additional arguments are:

- `kernel` — the kernel's transfer function ``\\hat g``, in any storage class of a [`SpectralKernel`](@ref) — a `StoredKernel` holding one
  coefficient per mode, or a compressed class evaluated per mode (radial,
  separable, or their product), which costs ``O(N)`` or a closure rather than ``O(N^3)``,
  exactly as `convolve!` takes it (including its reality condition on ``\\hat g``); one
  scalar kernel weights all three components.
- `α`, `β` — real accumulation weights as in `convolve!`: the four-argument form overwrites
  (``\\alpha = 1``, ``\\beta = 0``), and the six-argument form computes

```math
\\widehat{\\texttt{destination}}_i(k) = \\alpha  \\hat g(k)  \\widehat{(\\mathbb P u)}_i(k)
                                      + \\beta  \\widehat{\\texttt{destination}}_i(k).
```

The composed form replaces a `helmholtz_projection!` followed by a `convolve!` — one fused pass
instead of two, saving a full read and a full write of `destination` per call.
"""
function helmholtz_projection! end


function helmholtz_projection!(destination::VectorFieldSpectral{T}, field::VectorFieldSpectral{T}, multipliers::FieldSpectralMultipliers) where {T<:AbstractFloat}
  _check_field_domain_compatibility(destination, field)
  _check_multipliers_compatibility(field, multipliers)
  return _apply_helmholtz_projection!(destination, field, multipliers, nothing, one(T), zero(T))
end


function helmholtz_projection!(destination::VectorFieldSpectral{T}, field::VectorFieldSpectral{T}, multipliers::FieldSpectralMultipliers,
    kernel::SpectralKernel{T}) where {T<:AbstractFloat}
  return helmholtz_projection!(destination, field, multipliers, kernel, one(T), zero(T))
end


function helmholtz_projection!(destination::VectorFieldSpectral{T}, field::VectorFieldSpectral{T}, multipliers::FieldSpectralMultipliers,
    kernel::SpectralKernel{T}, α::Real, β::Real) where {T<:AbstractFloat}
  _check_field_domain_compatibility(destination, field)
  _check_kernel_compatibility(field, kernel)
  _check_multipliers_compatibility(field, multipliers)
  return _apply_helmholtz_projection!(destination, field, multipliers, _kernel_data(kernel), T(α), T(β))
end


"""
    helmholtz_projection(field::VectorFieldSpectral,
                         multipliers::FieldSpectralMultipliers)
    helmholtz_projection(field, multipliers, kernel::SpectralKernel)

Allocating form of [`helmholtz_projection!`](@ref): allocate the result and return it, the Helmholtz
(Leray) projection ``\\mathbb P u`` — the divergence-free part of a vector field, with the zero Fourier
mode left unchanged. With a `kernel` the result is the projection convolved with the kernel,
``g \\star (\\mathbb P u)``, in one pass. See `helmholtz_projection!` for the spectral form and the
kernel-composed form.
"""
function helmholtz_projection end


function helmholtz_projection(field::VectorFieldSpectral, multipliers::FieldSpectralMultipliers)
  destination = similar_field(field, Val(1))
  return helmholtz_projection!(destination, field, multipliers)
end


function helmholtz_projection(field::VectorFieldSpectral, multipliers::FieldSpectralMultipliers, kernel::SpectralKernel)
  destination = similar_field(field, Val(1))
  return helmholtz_projection!(destination, field, multipliers, kernel)
end


end # module DifferentialOperators