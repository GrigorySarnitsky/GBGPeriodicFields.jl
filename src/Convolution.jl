"""
    Convolution

Periodic (circular) convolution of a field with a kernel. On the torus the only convolution
is the periodic one, and by the convolution theorem it is exactly a coefficientwise product of the
transforms, so the operation lives in spectral representation. A scalar kernel multiplies every [fiber](@ref GBGPeriodicFields.GBGPeriodicFields)
component, so one operation serves scalar, vector, and tensor fields. The operation is named [`convolve`](@ref)
(allocating infix `⋆`) rather than `*`, which would read as a pointwise multiplication.

A kernel is not a field. The two hold identical coefficients, so nothing but a type can say which
role is meant, and the roles differ: the coefficientwise reciprocal of a kernel is the kernel that
deconvolves by it ([`inv`](@ref)), while the same operation on a field is one the package does not
define. Every kernel subtypes [`SpectralKernel`](@ref), and the four classes below are interchangeable
wherever a kernel is applied to a field, differing in cost rather than in meaning. A kernel also
serves as a reduction weight in [`weighted_inner`](@ref GBGPeriodicFields.Reductions.weighted_inner), which is narrower in one
respect: it requires a real multiplier.

Physics stays with the calling code: an LES filter, a viscous integrating factor, or a de-aliasing mask
is a multiplier the caller supplies — through [`radial_kernel`](@ref) when it depends on the mode only through
``|k|^2``, or as coefficients built from [`FieldSpectralMultipliers`](@ref) and wrapped in
[`StoredKernel`](@ref).

The parts are, in three groups — what the module does, how a kernel is stored, and which kernels it
builds:

Convolution operations:

- `convolve` / `convolve!` — convolve a field with a kernel; the in-place form adds the
  ``\\alpha``/``\\beta`` weights on result and destination, and `convolve(g₁, g₂)` composes two kernels into one.
- [`exponential_convolve!`](@ref) / [`exponential_convolve`](@ref) — convolve with the exponential
  radial kernel, computed from the wavenumber arrays on the fly instead of stored as a field; the
  two-operand form filters a weighted combination in the same pass.
- The kernel-composed [`combine!`](@ref) method — the weighted combination of two fields convolved
  with a kernel, in one fused pass.

Kernel storage classes:

- `StoredKernel` — one coefficient per mode, the ``O(N^3)`` storage, cubic in the points per
  axis, every other class exists to avoid. It wraps a [`ScalarFieldSpectral`](@ref) in the kernel role.
- [`SeparableKernel`](@ref) — a kernel that factors over the axes, held as its three per-axis factors,
  so it costs kilobytes rather than a field; the class `translation_kernel`, `tophat_window` and
  `assignment_window` return.
- [`RadialKernel`](@ref) — a kernel depending on the mode only through ``|k|^2``, held as the function
  ``\\sigma`` computing it (a closure, evaluated per mode), so it stores no coefficients at all; the class
  `spectral_cutoff`, `spectral_band` and `radial_kernel` return.
- [`ProductKernel`](@ref) — any two kernels held unmultiplied, which is what a composition that
  cannot be collapsed into a single kernel gives: a cross-family pair, two stored kernels, or two
  radial kernels whose coordinates cannot be shown to agree. It applies in one pass.
- [`materialize_kernel`](@ref) — expand a compressed kernel into a `StoredKernel`, for a caller that
  wants to inspect or modify the coefficients, and [`materialize_kernel!`](@ref) to expand it into
  one that already exists.
- `inv` — the reciprocal kernel, which deconvolves by the original. Each class returns its own
  kind and states the precondition it can afford to check, an annihilated mode having no inverse.

Kernel builders:

- `radial_kernel` — build a `RadialKernel` from any real function ``\\sigma`` of the squared
  wavenumber, which is the route for a multiplier this module does not name (a smooth filter, a
  hyperviscosity, an integrating factor).
- [`spectral_cutoff`](@ref) / [`spectral_band`](@ref) — build the isotropic sharp low-pass kernel and
  its annular band-pass generalization, both radial kernels.
- [`tophat_window`](@ref) — the box average of a chosen width, a separable kernel.
- [`assignment_window`](@ref) — the linear (cloud-in-cell) mass-assignment window, a separable kernel,
  for deconvolving a gridded point density.
- [`translation_kernel`](@ref) / [`translation_kernel!`](@ref) — the separable kernel that translates a
  field by a physical displacement, the shift theorem's phase.
"""
module Convolution

# Imported before extending, per invariant 7. All four kernel classes move between array families;
# the family's documentation lives on `adapt` in `Fields`.
import Adapt: adapt, adapt_structure
import ..Fields: _kernel_data, _check_kernel_compatibility,   # extended for the kernels below
  _context_grid, _context_layout
using ..Fields:
  _check_matching_context,
  _show_domain,
  _show_extent,
  _array_family,
  field_spectral_shape,
  SpectralKernel,
  AbstractFieldSpectral,
  ScalarFieldSpectral,
  FieldSpectralMultipliers,
  field_data,
  field_grid,
  field_layout,
  field_scalar_type,
  field_tensor_order,
  similar_field,
  _check_field_compatibility,
  _check_field_domain_compatibility,
  _check_multipliers_compatibility,
  _multipliers_scalar_type,
  _squared_wavenumber_broadcast

using ..FiberSections:
  _assign!,
  _foreach_outer_slab,
  _use_threads,
  @_assign!,
  _fiberwise_pass!

import KernelAbstractions
using KernelAbstractions: get_backend, @kernel, @index, @Const, synchronize

# Extended with the kernel-composed method (the weighted combination convolved in the same pass);
# the generic and its docstring live in FieldAlgebra, the kerneled method here with the kernels.
import ..FieldAlgebra: combine!

export convolve, convolve!, ⋆, exponential_convolve, exponential_convolve!, spectral_cutoff,
       spectral_band, assignment_window, tophat_window, translation_kernel,
       StoredKernel, SeparableKernel, RadialKernel, ProductKernel, radial_kernel, translation_kernel!, materialize_kernel,
       materialize_kernel!


####################################################
#        Product of two kernels (any families)     #
####################################################


"""
    StoredKernel(field::ScalarFieldSpectral)

Wrap a scalar field in spectral representation so that it plays the kernel role — one coefficient
per mode, the ``O(N^3)`` storage the compressed classes exist to avoid.

The wrapper is required rather than a convenience. A field and a kernel hold identical data, so nothing
but a type can say which role is meant, and the two admit different operations: the coefficientwise
reciprocal of a *kernel* is the kernel that deconvolves by it ([`inv`](@ref)), while the same operation
on a *field* is nonlinear in that field's spectral representation and the package does not define it.
So a bare [`ScalarFieldSpectral`](@ref) passed where a kernel is expected does not dispatch — wrap it here,
or build the kernel with one of the builders, and the role is then carried by the type rather than
inferred from the call site.

Wrapping costs nothing per application: the struct holds a reference, and the fused passes reach the
coefficients through it without an extra read. Wrap once, where the kernel is built.

The expansion [`materialize_kernel`](@ref) returns is this class, so a compressed kernel expanded
into its coefficients arrives already in the kernel role.

# Fields

- `field` — the `ScalarFieldSpectral` holding the coefficients, referenced rather than copied.
"""
struct StoredKernel{T, F<:ScalarFieldSpectral{T}} <: SpectralKernel{T}
  field::F
end


# Straight to the wrapped field's storage and domain check. These used to delegate to the kernel
# protocol's own methods FOR a `ScalarFieldSpectral`, which existed only while a bare field counted as
# a kernel; with that role removed the delegation had nowhere to land.
_kernel_data(kernel::StoredKernel) = field_data(kernel.field)
_check_kernel_compatibility(field, kernel::StoredKernel) =
  _check_field_domain_compatibility(field, kernel.field)
_context_grid(kernel::StoredKernel) = _context_grid(kernel.field)
_context_layout(kernel::StoredKernel) = _context_layout(kernel.field)

"""
    ProductKernel

The coefficientwise product of two spectral kernels, held as the pair rather than evaluated — what
[`convolve`](@ref) returns whenever composing cannot produce a single kernel more cheaply. There is no
public constructor, which is why no signature is shown above: one arises only from that composition. That covers
every cross-family pair, two stored kernels (merging those would mean materializing an ``O(N^3)``
product), and two radial kernels whose coordinates cannot be shown to agree.

Composition inside a family usually stays in that family: two axis-factored kernels always multiply
into one axis-factored kernel, and two radial symbols multiply into one radial symbol when both are
evaluated against the same coordinates, which [`RadialKernel`](@ref) explains and decides by type.
Radial operands that fail that test land here instead. Across families there is no collapse at all:
a radial symbol times an axis-factored phase is neither radial nor separable, so the composite keeps
both operands and multiplies their per-mode values. Either order composes and gives the same operator,
the product being coefficientwise, and a composite composes further in either position. It still stores nothing of field size, and it
applies exactly like either operand.

This is what lets a mask and a displacement — or any radial symbol and any per-axis factor — be
applied in a single pass instead of two.

# Fields

- `first_kernel`, `second_kernel` — the two operands, held unmultiplied and evaluated per mode.
"""
struct ProductKernel{T, A, B} <: SpectralKernel{T}
  first_kernel::A
  second_kernel::B
end

function ProductKernel{T}(first_kernel::A, second_kernel::B) where {T, A, B}
  # Both factors are evaluated per mode against the SAME field, so they must have been built for the
  # same base and Fourier layout. Checked here rather than at every composition site, so no route into
  # a product can skip it.
  _check_matching_context(first_kernel, second_kernel)
  return ProductKernel{T, A, B}(first_kernel, second_kernel)
end

_kernel_data(kernel::ProductKernel) =
  Base.Broadcast.instantiate(Base.broadcasted(*, _kernel_data(kernel.first_kernel),
                                              _kernel_data(kernel.second_kernel)))

function _check_kernel_compatibility(field, kernel::ProductKernel)
  _check_kernel_compatibility(field, kernel.first_kernel)
  _check_kernel_compatibility(field, kernel.second_kernel)
  return nothing
end

"""
    inv(kernel::ProductKernel)

The reciprocal kernel ``1/\\hat g``, formed by inverting each factor — the product of the reciprocals is
the reciprocal of the product — so it is another [`ProductKernel`](@ref) and materializes nothing.

!!! warning "Each factor must have no zeros on any stored mode"
    The composite vanishes wherever either factor does, so both must be invertible; each factor's own
    `inv` states the condition it needs.
"""
Base.inv(kernel::ProductKernel{T}) where {T} =
  ProductKernel{T}(inv(kernel.first_kernel), inv(kernel.second_kernel))


# Every kernel class answers the context protocol, so a kernel can be checked against a field, a
# multiplier set or another kernel without any of those knowing its field names. A product defers to
# its first factor: a call has already required the factors to agree.
_context_grid(kernel::ProductKernel) = _context_grid(kernel.first_kernel)
_context_layout(kernel::ProductKernel) = _context_layout(kernel.first_kernel)


"""
    materialize_kernel(kernel::ProductKernel)

Evaluate a product kernel into a [`StoredKernel`](@ref), which costs the full ``O(N^3)`` the
compressed forms exist to avoid. A composite evaluates both factors per mode, so its cost against a
stored kernel follows from theirs — and the classes differ, so read the crossover for whichever they
are. The warning below applies here too.
"""
function materialize_kernel(kernel::ProductKernel{T}) where {T}
  # A product stores no base of its own: its factors carry the grid and layout, and a call has
  # already checked they agree, so either factor answers for both.
  materialized = materialize_kernel(kernel.first_kernel)
  @_assign! field_data(materialized.field) .= _kernel_data(kernel)
  return materialized
end


# Materializing a kernel already held as a field is a copy: the product path above materializes its
# first factor to obtain correctly-shaped storage carrying the right grid and layout, then overwrites
# it with the full product. A stored factor must therefore not be aliased into the result.
"""
    materialize_kernel(kernel::StoredKernel)

Return a copy of a coefficientwise kernel, a `StoredKernel` owning storage no other shares.
"""
materialize_kernel(kernel::StoredKernel) =
  StoredKernel(ScalarFieldSpectral(copy(_kernel_data(kernel)), _context_grid(kernel); layout = _context_layout(kernel)))


"""
    materialize_kernel!(destination::StoredKernel,
                        kernel::SpectralKernel) -> destination

Evaluate a kernel into storage that already exists: every coefficient of `destination` is
overwritten with the kernel's value ``\\hat g(k)`` at that mode, and `destination` is returned.

Use this in-place form when `destination` is already allocated; the allocating
[`materialize_kernel`](@ref) returns a fresh result instead. The `destination` is a
[`StoredKernel`](@ref) sharing the grid, Fourier layout, element type and array family of `kernel`,
which may be of any of the four storage classes of a [`SpectralKernel`](@ref); a mismatch is refused.
The evaluation allocates nothing, so a field-sized kernel is written without a second field-sized
temporary. A caller holding a field it means to fill wraps it once as `StoredKernel(field)`, which
references the field rather than copying it.

The cost is one pass over the modes, the same as the allocating form's without the allocation, and
the warning on `materialize_kernel` about giving up a compressed kernel's memory saving applies to
whatever the destination is then used for.
"""
function materialize_kernel! end

function materialize_kernel!(destination::StoredKernel{T}, kernel::SpectralKernel{T}) where {T}
  _check_kernel_compatibility(destination.field, kernel)
  @_assign! field_data(destination.field) .= _kernel_data(kernel)
  return destination
end


# Cross-family and mixed-storage composition. The same-family methods above take precedence, so this
# catches exactly the pairs that do not collapse, in either order — a field in spectral representation
# is no longer a kernel, so nothing here depends on which argument leads. Composing two convolution
# operators IS convolving their kernels, which is why the verb is the same one that applies them.
convolve(first_kernel::SpectralKernel{T}, second_kernel::SpectralKernel{T}) where {T} =
  ProductKernel{T}(first_kernel, second_kernel)


####################################################
#        Radial kernel (a symbol of |k|²)          #
####################################################


"""
    RadialKernel

A spectral kernel that depends only on the wavenumber magnitude, ``\\hat g(k) = \\sigma(|k|^2)``,
stored as the function ``\\sigma`` rather than as its values — its *symbol*, in the sense the
differential operators use for the multiplier a coefficientwise operator applies. The function is evaluated one mode at a
time from the wavenumber arrays the multipliers already hold, so the kernel occupies no field: a
closure and three references, against the ``O(N^3)`` coefficients a stored kernel needs — bytes
rather than the 129 MiB a ``256^3`` kernel would take.

There is no public constructor, which is why no signature is shown above: a kernel of this class is
always obtained from a builder, so that the multipliers it evaluates against are the ones its grid
owns. Build one with [`spectral_cutoff`](@ref) or [`spectral_band`](@ref) for the sharp masks, or with
[`radial_kernel`](@ref) for any other such function — a smooth envelope, a hyperviscous
``\\exp(-\\nu (|k|^2)^p \\tau)`` of viscosity, power and time step. Apply it like any kernel: pass it to [`convolve!`](@ref), as the trailing kernel of [`divergence!`](@ref GBGPeriodicFields.DifferentialOperators.divergence!) or
[`helmholtz_projection!`](@ref GBGPeriodicFields.DifferentialOperators.helmholtz_projection!), or to [`weighted_inner`](@ref GBGPeriodicFields.Reductions.weighted_inner) as a reduction weight.

Why this family is closed by construction: ``|k|^2`` is real and even in every component, so any
real ``\\sigma`` of it is real and even too, hence Hermitian-symmetric — the coefficients it produces
are always some real field's. It also carries the true squared wavenumber at an even axis's Nyquist —
the value a magnitude-dependent multiplier wants there, unlike the derivative wavenumbers, which are
zeroed at that mode — so no case analysis is needed anywhere in the family.

!!! note "Storing no coefficients is not the same as costing nothing"
    The symbol is evaluated per mode, and against a field of tensor order ``R \\ge 1`` it is
    broadcast over the field's components, so it is evaluated once per component rather than once
    per mode; a scalar field pays nothing extra. Whether that
    recompute or the kernel-array traffic it saves dominates depends on the base and on the element
    type.

    On small grids, and in `Float32` on some GPUs, the recompute can make this class slower than a
    [`StoredKernel`](@ref); on large grids the saved traffic usually wins. Where the recompute
    dominates, [`materialize_kernel`](@ref) stores the coefficients instead.

!!! note "Radial, not separable"
    ``|k|^2 = k_1^2 + k_2^2 + k_3^2`` is a function of the sum, so a *general* real symbol of it
    does not factor into per-axis terms and cannot be stored per axis the way a
    [`SeparableKernel`](@ref) is. The two families overlap rather than partition: the exponential is in
    both, since ``\\exp(c|k|^2) = \\prod_a \\exp(ck_a^2)``, which is why `exponential_convolve!` exists as
    its own fused operation. What this class buys is the general case, where no such factorization is
    available.

# Fields

- `sigma` — the function ``\\sigma``, called with the real ``|k|^2`` and returning a real value.
- `multipliers` — the [`FieldSpectralMultipliers`](@ref) supplying ``|k|^2``, referenced, not copied.
  Whether they are the grid's own wavenumbers (*canonical*, built by the convenience constructor from
  the grid) or a caller's own (supplied through the explicit constructor, which validates lengths and
  not values) is part of their type, and it decides
  whether composing two of these kernels collapses into one: two kernels over canonical multipliers of
  the same type hold the same coordinates by construction and merge, while a kernel over a caller's own
  coordinates keeps both operands as a [`ProductKernel`](@ref), since one composite can carry only one
  set of coordinates.
- `grid`, `layout` — the base and Fourier layout the kernel was built for, which a call checks
  the field against.
"""
struct RadialKernel{T, F, M, G, L} <: SpectralKernel{T}
  sigma::F
  multipliers::M
  grid::G
  layout::L
end

RadialKernel{T}(sigma::F, multipliers::M, grid::G, layout::L) where {T, F, M, G, L} =
  RadialKernel{T, F, M, G, L}(sigma, multipliers, grid, layout)


"""
    radial_kernel(sigma, multipliers::FieldSpectralMultipliers) -> RadialKernel

Build the [`RadialKernel`](@ref) for an arbitrary real function of the squared wavenumber — its
symbol, in the sense the differential operators use — the general constructor behind
[`spectral_cutoff`](@ref) and [`spectral_band`](@ref), for the multipliers the package does not name.

Here `sigma` is a function of one real argument — the squared wavenumber ``|k|^2`` — returning a real
value, and it must be pure and GPU-safe: it may capture only values, never a type, since a closure
holding a `Type` is not a bitstype and a device rejects it at launch, and it may hold no mutable state
and do no scalar indexing of device arrays. Anything it does capture by value, such as a viscosity or a
substep, is free to vary per call, because building a kernel allocates nothing of field size. The
`multipliers` are the [`FieldSpectralMultipliers`](@ref) supplying ``|k|^2``, and whose grid, Fourier
layout, element type and array family the kernel takes as its own.

The physics stays with the caller: an integrating factor is
`radial_kernel(k2 -> exp(-ν * k2 * Δt), …)`, a smooth filter its own envelope. Because the function is
evaluated per mode rather than stored, a kernel whose parameters change every call costs nothing to
rebuild, where a stored kernel pays a full field write. That evaluation is per mode, so on a CPU at a small grid a field of order ``R \\ge 1`` pays it once per fiber component; `RadialKernel` carries the measured trade-off against a materialized kernel.
"""
function radial_kernel(sigma::F, multipliers::FieldSpectralMultipliers) where {F}
  T = _multipliers_scalar_type(multipliers)
  return RadialKernel{T}(sigma, multipliers, multipliers.grid, multipliers.fourier_layout)
end


# The lazy per-mode multiplier: the symbol applied to the lazy |k|², itself an unfused broadcast over
# the three O(N) squared-wavenumber axis arrays. Nothing of field size is built.
_kernel_data(kernel::RadialKernel) =
  Base.Broadcast.instantiate(Base.broadcasted(kernel.sigma,
                                              _squared_wavenumber_broadcast(kernel.multipliers)))

function _check_kernel_compatibility(field, kernel::RadialKernel)
  (field_grid(field) == kernel.grid && field_layout(field) == kernel.layout) ||
    throw(ArgumentError("the radial kernel was built for a different grid or Fourier layout than the field"))
  return nothing
end


"""
    inv(kernel::RadialKernel)

The reciprocal kernel ``1/\\sigma(|k|^2)``, formed by composing the reciprocal with ``\\sigma``, so it
is another [`RadialKernel`](@ref) and still costs no storage.

!!! warning "The function must have no zeros on any stored mode"
    A ``\\sigma`` that vanishes at any stored mode gives a non-finite reciprocal — a sharp mask is
    exactly such a function, so inverting a [`spectral_cutoff`](@ref) is not meaningful.
"""
Base.inv(kernel::RadialKernel{T}) where {T} =
  RadialKernel{T}(inv ∘ kernel.sigma, kernel.multipliers, kernel.grid, kernel.layout)

_context_grid(kernel::RadialKernel) = kernel.grid
_context_layout(kernel::RadialKernel) = kernel.layout


# Composition inside the family: the symbols multiply, so the composite is another radial kernel —
# PROVIDED both operands are radial in the same coordinate. The composite keeps ONE multiplier set, so
# collapsing two kernels that evaluate their symbols against different wavenumbers would silently apply
# the second symbol at the first's ``|k|^2``. Equal grid and layout do not establish sameness on their
# own, because the six-array `FieldSpectralMultipliers` constructor validates lengths and not values —
# which is the escape hatch a sheared, time-dependent multiplier set would use.
#
# The condition is therefore decided by the TYPES rather than by a runtime test. Multipliers built from
# a grid are marked canonical, and two canonical sets of the same concrete type, on a matching grid and
# layout, hold identical values by construction: same derivation, same inputs. That is the collapsing
# case, and it is the one a caller normally has. Every other pairing keeps both operands.
#
# Deciding it statically is what makes the return type concrete. The previous form chose between
# `RadialKernel` and `ProductKernel` on an `===` test, so inference saw a Union and the result type
# depended on object identity — invisible at the call site, and surprising given that the product of
# two radial symbols is always radial.
function convolve(first_kernel::RadialKernel{T, F1, M}, second_kernel::RadialKernel{T, F2, M}) where {
    T, F1, F2, M<:FieldSpectralMultipliers{<:AbstractFloat, <:Any, <:Any, <:Any, <:Any, <:Any, <:Any,
                                           <:Any, <:Any, <:Any, <:Any, <:Any, <:Any, true}}
  _check_matching_context(first_kernel, second_kernel)
  first_sigma, second_sigma = first_kernel.sigma, second_kernel.sigma
  return RadialKernel{T}(squared -> first_sigma(squared) * second_sigma(squared),
                         first_kernel.multipliers, first_kernel.grid, first_kernel.layout)
end


# Any other radial pairing — a custom multiplier set on either side, or two sets of different concrete
# type (different backends, say) — retains both operands and costs one extra symbol evaluation per mode.
function convolve(first_kernel::RadialKernel{T}, second_kernel::RadialKernel{T}) where {T}
  _check_matching_context(first_kernel, second_kernel)
  return ProductKernel{T}(first_kernel, second_kernel)
end


"""
    materialize_kernel(kernel::RadialKernel)

Evaluate a radial kernel into a [`StoredKernel`](@ref), which costs the full ``O(N^3)`` the closure
form exists to avoid. When that trade is worth making is specific to this class: the compressed
classes are measured separately and disagree, one card having the radial form overtake a stored kernel
by ``128^3`` where the axis-factored form never overtakes. [`RadialKernel`](@ref) carries the measured
crossover, and the warning below applies here too.
"""
function materialize_kernel(kernel::RadialKernel{T}) where {T}
  data = similar(kernel.multipliers.squared_wavenumber_1, Complex{T},
                 (length(kernel.multipliers.squared_wavenumber_1),
                  length(kernel.multipliers.squared_wavenumber_2),
                  length(kernel.multipliers.squared_wavenumber_3)))
  @_assign! data .= _kernel_data(kernel)
  return StoredKernel(ScalarFieldSpectral(data, kernel.grid; layout = kernel.layout))
end


####################################################
#        Separable (axis-factored) kernel          #
####################################################


"""
    SeparableKernel

A spectral kernel that factors over the axes, ``\\hat g(k) = \\prod_a g_a(k_a)``, stored as its
three one-dimensional per-axis factors rather than as a full field. The factors are evaluated into
the product one mode at a time, so the kernel never occupies a field's worth of memory: three arrays
of ``O(N)`` entries in place of ``O(N^3)`` coefficients — kilobytes rather than the 129 MiB a ``256^3``
kernel would take — and applying it reads no field-sized kernel stream: the
three ``O(N)`` factors are read per mode, which is the saving, not zero kernel traffic.

There is no public constructor, which is why no signature is shown above: a kernel of this class is
always obtained from a builder, so that its per-axis factors match the grid they will be applied on.
Build one with [`translation_kernel`](@ref) (the displacement phase, complex factors) or
[`assignment_window`](@ref) (the mass-assignment window, real factors), and apply it exactly like a
kernel held as a field: pass it to [`convolve!`](@ref) or as the trailing kernel of [`divergence!`](@ref GBGPeriodicFields.DifferentialOperators.divergence!) or [`helmholtz_projection!`](@ref GBGPeriodicFields.DifferentialOperators.helmholtz_projection!).

Whether that is also *faster* depends on the grid. Applying it moves two field-sized streams where a
stored kernel moves three, but evaluates the product per mode, so it trails a stored kernel on a grid
small enough to sit in cache and overtakes it once the pass is bound by memory. On a small grid where
the difference matters, [`materialize_kernel`](@ref) trades the memory back, and its docstring carries
the measured crossover.
Use `inv` for the reciprocal kernel ``1/\\hat g``, which is separable too since
``1/\\prod_a g_a = \\prod_a (1/g_a)`` — the deconvolution an assignment window is built for.

!!! note "Separable, not radial"
    A kernel that depends only on the wavenumber magnitude is usually *radial*, not separable — a
    general function of ``k_1^2 + k_2^2 + k_3^2`` does not factor into per-axis terms, the exponential
    being the notable exception (``\\exp(c|k|^2)`` factors, and has its own operation). This type is for
    kernels that genuinely do factor, the typical case being a per-axis phase.

# Fields

- `factor_1`, `factor_2`, `factor_3` — the per-axis factors, each shaped to broadcast along its
  own axis, of the stored spectral length of that axis (the folded axis is the layout's `fft_dims[1]`).
- `grid`, `layout` — the base and Fourier layout the factors were built for, which a call
  checks the field against.
"""
struct SeparableKernel{T, V, G, L} <: SpectralKernel{T}
  factor_1::V
  factor_2::V
  factor_3::V
  grid::G
  layout::L
end

function SeparableKernel{T}(factor_1::V, factor_2::V, factor_3::V, grid::G, layout::L) where {T, V, G, L}
  # The type parameters promise a context that the arrays must actually match. Unvalidated, a kernel
  # could hold factors for one base while its own `grid`/`layout` named another, and the disagreement
  # surfaced only when the kernel was applied — as a shape error far from the construction that caused
  # it, or, at matching lengths, not at all.
  expected = field_spectral_shape(grid, layout, Val(0))
  lengths = (length(factor_1), length(factor_2), length(factor_3))
  lengths == expected ||
    throw(DimensionMismatch("axis factors of lengths $lengths do not match the spectral shape " *
                            "$expected implied by this kernel's grid and layout"))
  # A factor may be real or complex: `assignment_window`'s ∏sinc² window is real, `translation_kernel`'s
  # phase is not. Both are legitimate, so the requirement is that the factors carry the kernel's own
  # scalar type in one of those two forms — not that they are complex.
  eltype(factor_1) === T || eltype(factor_1) === Complex{T} ||
    throw(ArgumentError("a SeparableKernel{$T} needs $T or Complex{$T} factors; got $(eltype(factor_1))"))
  return SeparableKernel{T, V, G, L}(factor_1, factor_2, factor_3, grid, layout)
end


# The axis-factored multiplier is the LAZY product of the three per-axis factors — an instantiated
# `Broadcasted`, which both the broadcast route and the linear-indexed fiberwise executor consume
# exactly as they consume an array, so no operator body changes to accept one. The generic's docstring
# is its home, on the bare binding in `Fields`.
_kernel_data(kernel::SeparableKernel) =
  Base.Broadcast.instantiate(Base.broadcasted(*, kernel.factor_1, kernel.factor_2, kernel.factor_3))


# The axis-factored class compares the grid and layout it stored at construction, and its per-axis
# factor lengths against the field's stored spectral shape. The generic's docstring is its home, on the
# bare binding in `Fields`.
function _check_kernel_compatibility(field, kernel::SeparableKernel)
  (field_grid(field) == kernel.grid && field_layout(field) == kernel.layout) ||
    throw(ArgumentError("the separable kernel was built for a different grid or Fourier layout than the field"))
  stored = size(field_data(field))
  factors = (length(kernel.factor_1), length(kernel.factor_2), length(kernel.factor_3))
  all(d -> stored[d] == factors[d], 1:3) ||
    throw(DimensionMismatch("separable kernel factor lengths $(factors) do not match the field's stored spectral shape $(stored[1:3])"))
  return nothing
end


"""
    inv(kernel::SeparableKernel)

The reciprocal kernel ``1/\\hat g``, itself separable
because ``1/\\prod_a g_a = \\prod_a (1/g_a)`` — so it is formed per axis, at ``O(N)`` cost, with no
field materialized. Applying it
deconvolves by `kernel`, which is what a mass-assignment window is built for
([`assignment_window`](@ref)).

!!! warning "The factors must have no zeros, and this method checks"
    Every per-axis factor must be non-zero at every stored mode. Unlike the radial method, this one can
    afford to verify it — the factors are ``O(N)`` — so a zero throws rather than returning a
    non-finite reciprocal. An `assignment_window` satisfies the condition on every stored mode, whereas
    a phase kernel does not in general (a displacement can drive an even axis's Nyquist factor to
    zero).
"""
function Base.inv(kernel::SeparableKernel{T}) where {T}
  # A zero factor entry inverts to a non-finite reciprocal, which then contaminates every mode of that
  # plane. The factors are O(N), so this is checked rather than documented — the reciprocal is the
  # deconvolution, and deconvolving by a kernel that annihilates a mode is not a recoverable
  # operation. (A `RadialKernel` cannot be checked the same way without evaluating its symbol over the
  # whole band, so there the precondition stays documented; see its `inv` above.)
  all(factor -> all(!iszero, factor), (kernel.factor_1, kernel.factor_2, kernel.factor_3)) ||
    throw(ArgumentError("this kernel has a zero factor entry and is therefore not invertible; " *
                        "deconvolving by it would divide an annihilated mode by zero"))
  return SeparableKernel{T}(inv.(kernel.factor_1), inv.(kernel.factor_2), inv.(kernel.factor_3),
                            kernel.grid, kernel.layout)
end


"""
    inv(kernel::StoredKernel)

The coefficientwise reciprocal of a kernel held as a field, which is the kernel that deconvolves by it.

A kernel with a zero coefficient annihilates that mode, so no kernel undoes it and this throws rather
than returning a non-finite coefficient. The check is a full pass over the coefficients, which an
explicit inversion can afford; the axis-factored [`SeparableKernel`](@ref) method checks its ``O(N)``
factors instead, and the radial method documents the precondition it cannot test cheaply.
"""
function Base.inv(kernel::StoredKernel)
  data = _kernel_data(kernel)
  all(!iszero, data) ||
    throw(ArgumentError("this kernel has a zero coefficient and is therefore not invertible; " *
                        "deconvolving by it would divide an annihilated mode by zero"))
  return StoredKernel(ScalarFieldSpectral(inv.(data), _context_grid(kernel); layout = _context_layout(kernel)))
end

_context_grid(kernel::SeparableKernel) = kernel.grid
_context_layout(kernel::SeparableKernel) = kernel.layout


# Composing two separable kernels stays inside the family: the product factors axis by axis, so the
# composition is formed from three O(N) products and never materializes either kernel.
#
# A caution the type cannot enforce: composing two *translation* kernels is not the same operator as
# one kernel for the summed displacement. Off the Nyquist plane the per-axis phases multiply as
# expected, but at an even axis's Nyquist the factor is the real cos(π hₐ/Δxₐ) (decision 28), and
# cos(a)·cos(b) ≠ cos(a + b). Add displacements to compose translations; compose kernels only when the
# coefficientwise product is what is actually meant.
function convolve(first_kernel::SeparableKernel{T}, second_kernel::SeparableKernel{T}) where {T}
  (first_kernel.grid == second_kernel.grid && first_kernel.layout == second_kernel.layout) ||
    throw(ArgumentError("the separable kernels were built for different grids or Fourier layouts"))
  return SeparableKernel{T}(first_kernel.factor_1 .* second_kernel.factor_1,
                            first_kernel.factor_2 .* second_kernel.factor_2,
                            first_kernel.factor_3 .* second_kernel.factor_3,
                            first_kernel.grid, first_kernel.layout)
end


"""
    materialize_kernel(kernel::SeparableKernel)

Evaluate an axis-factored kernel into a kernel held as a field, returning the `StoredKernel`
whose coefficients are the product of the per-axis factors. The result applies identically and, for
real factors, gives bit-identical results — the two differ only in what they cost. Complex factors
agree bitwise on the host and to rounding on a device.

Use this to trade memory back for speed on a small grid. Applying an axis-factored kernel moves two
field-sized streams where a stored kernel moves three, but evaluates the product per mode, so the
stored kernel is usually faster on small grids and the axis-factored one on large grids with many
threads; on a GPU the crossover depends on the card. A run whose grids are small, or which applies
one fixed kernel very many times with memory to spare, can materialize once and keep the field; a
threaded run at production resolution should not, and pays a field of residency for nothing if it
does (129 MiB at ``256^3``, against about 10 KiB for the factors).

!!! warning "This gives up the memory saving entirely"
    The returned field costs the full ``O(N^3)`` the axis-factored form exists to avoid. Materialize
    deliberately, for a measured reason on a specific grid — not by default.
"""
function materialize_kernel(kernel::SeparableKernel{T}) where {T}
  shape = (length(kernel.factor_1), length(kernel.factor_2), length(kernel.factor_3))
  data = similar(kernel.factor_1, Complex{T}, shape)
  @_assign! data .= kernel.factor_1 .* kernel.factor_2 .* kernel.factor_3
  return StoredKernel(ScalarFieldSpectral(data, kernel.grid; layout = kernel.layout))
end





"""
    _apply_separable_combination!(destination_data, a_data, b_data, kernel, α, β)

Convolve a weighted combination with a [`SeparableKernel`](@ref) in one pass, writing
``\\texttt{dst} \\mathrel{.=} \\hat g(\\alpha \\hat a + \\beta \\hat b)``. It takes the same
cartesian routes as [`_apply_separable_convolution!`](@ref), and for the same measured reason.
"""
function _apply_separable_combination!(destination_data, a_data, b_data, kernel::SeparableKernel, α, β)
  _separable_combination_pass!(get_backend(destination_data), destination_data, a_data, b_data,
                               kernel.factor_1, kernel.factor_2, kernel.factor_3, α, β)
  return nothing
end


# Device route: one flat broadcast (cartesian indexing, coalesced launch).
function _separable_combination_pass!(backend, destination_data, a_data, b_data,
    factor_1, factor_2, factor_3, α, β)
  @_assign! destination_data .= factor_1 .* factor_2 .* factor_3 .* (α .* a_data .+ β .* b_data)
  return nothing
end


# CPU route: the gated slab loop, component-major, matching the convolution twin.
function _separable_combination_pass!(::KernelAbstractions.CPU, destination_data, a_data, b_data,
    factor_1, factor_2, factor_3, α, β)
  destination = _fiber_flattened(destination_data)
  a = _fiber_flattened(a_data)
  b = _fiber_flattened(b_data)
  axis_1, axis_2 = axes(destination, 1), axes(destination, 2)
  components = axes(destination, 4)
  _foreach_outer_slab(axes(destination, 3), length(destination)) do outer_modes
    @inbounds for component in components
      for mode_3 in outer_modes
        factor_value_3 = factor_3[mode_3]
        for mode_2 in axis_2
          factor_value_2 = factor_2[mode_2]
          @simd for mode_1 in axis_1
            destination[mode_1, mode_2, mode_3, component] =
              ((factor_1[mode_1] * factor_value_2) * factor_value_3) *
              (α * a[mode_1, mode_2, mode_3, component] + β * b[mode_1, mode_2, mode_3, component])
          end
        end
      end
    end
  end
  return nothing
end


# The generic compressed route: one flat broadcast over the kernel's lazy per-mode values. Every
# compressed kernel can be applied this way; the two families above additionally carry a hand-written
# CPU twin, which the broadcast does not vectorize as well (`PERFORMANCE.md` finding (o)).
function _apply_compressed_convolution!(destination_data, source_data, kernel, α, β)
  kernel_data = _kernel_data(kernel)
  if iszero(β)
    @_assign! destination_data .= α .* kernel_data .* source_data
  else
    @_assign! destination_data .= α .* kernel_data .* source_data .+ β .* destination_data
  end
  return nothing
end


# A radial kernel applies through the same two routes as an axis-factored one, and for the same
# measured reason (`PERFORMANCE.md` finding (o)): a device takes one flat broadcast, a CPU takes the
# gated component-major loop, and both index the wavenumber axes CARTESIAN so no element pays a
# linear-to-cartesian integer division. The squared wavenumber is summed as (k1 + k2) + k3, matching
# the broadcast's own left association, so every route agrees bit for bit with a stored kernel.
function _apply_radial_convolution!(destination_data, source_data, kernel::RadialKernel, α, β)
  multipliers = kernel.multipliers
  _radial_convolution_pass!(get_backend(destination_data), destination_data, source_data,
                            kernel.sigma, multipliers.squared_wavenumber_1,
                            multipliers.squared_wavenumber_2, multipliers.squared_wavenumber_3, α, β)
  return nothing
end

function _radial_convolution_pass!(backend, destination_data, source_data, sigma,
    squared_1, squared_2, squared_3, α, β)
  kernel_data = Base.broadcasted(sigma,
    Base.broadcasted(+, reshape(squared_1, :, 1, 1), reshape(squared_2, 1, :, 1),
                     reshape(squared_3, 1, 1, :)))
  if iszero(β)
    @_assign! destination_data .= α .* kernel_data .* source_data
  else
    @_assign! destination_data .= α .* kernel_data .* source_data .+ β .* destination_data
  end
  return nothing
end

function _radial_convolution_pass!(::KernelAbstractions.CPU, destination_data, source_data, sigma::F,
    squared_1, squared_2, squared_3, α, β) where {F}
  destination = _fiber_flattened(destination_data)
  source = _fiber_flattened(source_data)
  axis_1, axis_2 = axes(destination, 1), axes(destination, 2)
  components = axes(destination, 4)
  _foreach_outer_slab(axes(destination, 3), length(destination)) do outer_modes
    @inbounds for component in components
      for mode_3 in outer_modes
        squared_value_3 = squared_3[mode_3]
        for mode_2 in axis_2
          squared_value_2 = squared_2[mode_2]
          if iszero(β)
            @simd for mode_1 in axis_1
              destination[mode_1, mode_2, mode_3, component] =
                α * sigma((squared_1[mode_1] + squared_value_2) + squared_value_3) *
                source[mode_1, mode_2, mode_3, component]
            end
          else
            @simd for mode_1 in axis_1
              destination[mode_1, mode_2, mode_3, component] =
                α * sigma((squared_1[mode_1] + squared_value_2) + squared_value_3) *
                source[mode_1, mode_2, mode_3, component] +
                β * destination[mode_1, mode_2, mode_3, component]
            end
          end
        end
      end
    end
  end
  return nothing
end


"""
    _apply_separable_convolution!(destination_data, source_data, kernel, α, β)

Apply a [`SeparableKernel`](@ref) as one broadcast over the whole section, writing
``\\texttt{dst} \\mathrel{.=} \\alpha \\hat g \\cdot \\hat f + \\beta \\texttt{dst}``. The three per-axis
factors carry singleton axes, so they broadcast along the remaining mode axes and along the fiber,
and one expression serves scalar, vector, and tensor fields exactly as the stored-kernel path does.

The shape is chosen for two measured reasons. Broadcasting indexes the factors cartesian, so no
element pays a linear-to-cartesian conversion — an integer division, emulated on a GPU. And the launch
stays flat, which keeps it *coalesced* — neighbouring threads reading neighbouring addresses, which
a GPU serves as one wide transaction. The folded axis is
``N/2 + 1`` modes long, half its point count plus one (129 at ``256^3``), so a three-dimensional launch would cut each row against a
length that is not a multiple of the *warp* — the group of threads a GPU issues in lockstep, 32 on
NVIDIA and 64 on AMD — leaving every row's last transaction partly idle.

The kernel value, the axis factors in order, is associated as the stored path does,
``\\alpha((\\sigma_1\\sigma_2)\\sigma_3)\\hat f``, so a real-factored kernel and its materialized
product agree bitwise. A complex-factored one can differ by an ulp on a device: the compiler contracts the ``ac - bd`` of a complex multiply into a fused multiply-add,
differently when the product is inlined here than when a stored kernel rounds it to memory first.
"""
function _apply_separable_convolution!(destination_data, source_data, kernel::SeparableKernel, α, β)
  _separable_convolution_pass!(get_backend(destination_data), destination_data, source_data,
                               kernel.factor_1, kernel.factor_2, kernel.factor_3, α, β)
  return nothing
end


# Device route: one flat broadcast, which indexes the factors cartesian and keeps the launch coalesced.
function _separable_convolution_pass!(backend, destination_data, source_data,
    factor_1, factor_2, factor_3, α, β)
  # The parentheses are load-bearing, not decoration. Broadcasting associates left, so the unbracketed
  # form computed ``(((\alpha\sigma_1)\sigma_2)\sigma_3)\hat f`` while the stored path and the CPU
  # twin below both compute ``\alpha((\sigma_1\sigma_2)\sigma_3)\hat f`` — the same value in exact
  # arithmetic, a different rounding in floating point. At ``\alpha = 1`` the two coincide (scaling by
  # one is exact), which is why every test the package had passed: they all take the three-argument
  # form, which delegates ``\alpha = 1``. At any other ``\alpha`` the device route disagreed with its
  # own materialized kernel, and it is the ONLY route that did, being unreachable on a CPU.
  if iszero(β)
    @_assign! destination_data .= α .* (factor_1 .* factor_2 .* factor_3) .* source_data
  else
    @_assign! destination_data .= α .* (factor_1 .* factor_2 .* factor_3) .* source_data .+
                                  β .* destination_data
  end
  return nothing
end


# CPU route (the decision-38 gated twin). The broadcast above is right for a device but wrong here: a
# five-operand broadcast whose middle three carry singleton axes does not vectorize, and it runs at a
# fixed ~330 M elements/s — the SAME rate in `Float32` as in `Float64`, the signature of an
# element-bound loop rather than a bandwidth-bound one, roughly a sixth of what the stored kernel
# achieves. This loop hoists the two outer factors to scalars, leaving an inner pass over contiguous
# storage that `@simd` can widen. The product is associated exactly as the broadcast and the stored
# path associate it, ``\alpha((\sigma_1\sigma_2)\sigma_3)\hat f``, so all three agree bit for bit.
function _separable_convolution_pass!(::KernelAbstractions.CPU, destination_data, source_data,
    factor_1, factor_2, factor_3, α, β)
  destination = _fiber_flattened(destination_data)
  source = _fiber_flattened(source_data)
  axis_1, axis_2 = axes(destination, 1), axes(destination, 2)
  components = axes(destination, 4)
  # Component-major inside the slab: for its band of `mode_3`, a thread walks each fiber component's
  # block from start to end, so every run is long and contiguous. The obvious order — components
  # innermost — instead jumps between blocks every row, which costs the threaded pass more than the
  # SIMD widening gains (measured 0.98× against 1.16× at 256³).
  _foreach_outer_slab(axes(destination, 3), length(destination)) do outer_modes
    @inbounds for component in components
      for mode_3 in outer_modes
        factor_value_3 = factor_3[mode_3]
        for mode_2 in axis_2
          factor_value_2 = factor_2[mode_2]
          if iszero(β)
            @simd for mode_1 in axis_1
              destination[mode_1, mode_2, mode_3, component] =
                α * ((factor_1[mode_1] * factor_value_2) * factor_value_3) *
                source[mode_1, mode_2, mode_3, component]
            end
          else
            @simd for mode_1 in axis_1
              destination[mode_1, mode_2, mode_3, component] =
                α * ((factor_1[mode_1] * factor_value_2) * factor_value_3) *
                source[mode_1, mode_2, mode_3, component] +
                β * destination[mode_1, mode_2, mode_3, component]
            end
          end
        end
      end
    end
  end
  return nothing
end


# The fiber components of a section's storage as one trailing axis, so a scalar, vector, and tensor
# field share one loop. Reshaping shares storage.
_fiber_flattened(data::AbstractArray{<:Any, 3}) = reshape(data, size(data)..., 1)
_fiber_flattened(data::AbstractArray) =
  reshape(data, size(data, 1), size(data, 2), size(data, 3), :)


####################################################
#        Convolution kernel                        #
####################################################


"""
    _apply_convolution!(destination_data, source_data, kernel_data, α, β)

Apply the coefficientwise spectral product that realizes the periodic convolution in spectral
representation, writing ``\\texttt{dst} \\mathrel{.=} \\alpha \\hat g \\cdot \\hat f + \\beta \\texttt{dst}``
(``\\texttt{dst}`` the `destination_data`, ``\\hat f`` the `source_data`, ``\\hat g`` = `kernel_data`).
The scalar `kernel_data`, of the field's spectral spatial shape (the folded axis halved), broadcasts over the fiber components of
`source_data` exactly as the Laplacian's ``|k|^2`` does, so one body serves every tensor order. The
call branches on `iszero(β)` to overwrite or accumulate. The product is coefficientwise, so it is
alias-safe: `destination_data` may be `source_data` or the kernel.
"""
function _apply_convolution!(destination_data::AbstractArray{<:Any, 3}, source_data, kernel_data, α, β)
  if iszero(β)
    @_assign! destination_data .= α .* kernel_data .* source_data
  else
    @_assign! destination_data .= α .* kernel_data .* source_data .+ β .* destination_data
  end
  return destination_data
end

# The fiber cases fuse through the generic executor so the scalar kernel is read once per mode,
# not once per fiber component. The values functions fold α as `(α ĝ) f̂` — the broadcast's own
# association — so the fused result is bitwise-identical; the executor's own α is then the exact
# one(T), and its β carries the accumulate (reading the destination only when β ≠ 0).
@inline function _convolve_vector_values(kernel_value, source_1, source_2, source_3, α)
  scaled = α * kernel_value
  return (scaled * source_1, scaled * source_2, scaled * source_3)
end

@inline function _convolve_tensor_values(kernel_value, source_11, source_12, source_13,
    source_21, source_22, source_23, source_31, source_32, source_33, α)
  scaled = α * kernel_value
  return (scaled * source_11, scaled * source_12, scaled * source_13,
          scaled * source_21, scaled * source_22, scaled * source_23,
          scaled * source_31, scaled * source_32, scaled * source_33)
end

function _apply_convolution!(destination_data::AbstractArray{<:Any, 4}, source_data, kernel_data, α, β)
  _fiberwise_pass!(get_backend(destination_data), _convolve_vector_values,
                   ntuple(component -> view(destination_data, :, :, :, component), Val(3)),
                   (kernel_data, ntuple(component -> view(source_data, :, :, :, component), Val(3))...),
                   (α,), one(α), β)
  return destination_data
end

function _apply_convolution!(destination_data::AbstractArray{<:Any, 5}, source_data, kernel_data, α, β)
  _fiberwise_pass!(get_backend(destination_data), _convolve_tensor_values,
                   ntuple(n -> view(destination_data, :, :, :, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9)),
                   (kernel_data, ntuple(n -> view(source_data, :, :, :, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9))...),
                   (α,), one(α), β)
  return destination_data
end


####################################################
#        Convolution (apply a Fourier kernel)      #
####################################################


"""
    convolve!(destination, field, kernel::SpectralKernel)
    convolve!(destination, field, kernel::SpectralKernel, α, β)

Convolve `field` with the kernel whose transfer function is `kernel`, writing the result into
`destination` in place and returning `destination`; both `field` and `destination` are in spectral
representation.

Use this in-place form when `destination` is already allocated; the allocating [`convolve`](@ref)
returns a fresh result instead.

# Arguments

- `field` — the field to filter, in spectral representation.
- `kernel` — the kernel's transfer function ``\\hat g``, in any storage class of a
  [`SpectralKernel`](@ref): a `StoredKernel` holding one coefficient per mode, or one of the compressed
  classes evaluated per mode (radial, separable, or their product), which costs ``O(N)`` or a closure
  rather than ``O(N^3)``. One scalar kernel serves scalar, vector, and tensor `field`s, and every
  storage class gives bitwise-identical results on the host, a *complex* kernel on a device agreeing
  to rounding instead.
- `destination` — the field written with the result; it may alias `field` or `kernel`, since the
  product is coefficientwise.
- `α`, `β` — real accumulation weights, mirroring `LinearAlgebra.mul!(C, A, B, α, β)` and converted to
  the field's scalar type; the three-argument form
  overwrites (``\\alpha = 1``, ``\\beta = 0``), the five-argument form computes
  ``\\alpha (f \\star g) + \\beta \\texttt{destination}``.

Physically the periodic convolution is the kernel-weighted local average of the field
``f`` about each point ``x`` — a low-pass filter when the kernel ``g`` is a smoothing bump:

```math
(f \\star g)(x) = \\int_\\Omega f(y)  g(x - y)\\,\\mathrm{d}y ,
```

with ``\\Omega`` the periodic box and the displacement ``x - y`` reduced onto the torus. On the grid
the operation computes the *circular sum* ``(f \\star g)[n] = \\sum_m f[m]  g[n - m]`` (indices
modulo the grid) — the integral's Riemann sum *without* the cell volume ``|\\Omega|/\\prod_i N_i``, box volume over the product of the point counts ``N_i`` along the axes, the
dimensionless convention that makes a kernel act as a per-mode transfer function (``\\hat g \\equiv 1``
is the identity; a sharp cutoff is a projection); the continuum integral above is ``|\\Omega|/\\prod_i N_i``
times it. By the convolution theorem (the forward transform unnormalized) the circular sum is exactly
the coefficientwise product of the transforms, which this operation computes — ``\\hat g`` =
`kernel`, broadcast over every fiber component of ``\\hat f``, with the ``\\alpha``/``\\beta``
accumulate, with ``\\hat d`` the coefficients of `destination`:

```math
\\hat d(k) \\leftarrow \\alpha \\hat f(k) \\hat g(k) + \\beta \\hat d(k).
```


!!! warning "A real field needs a Hermitian kernel"
    The stored half-spectrum holds only the modes with a non-negative wavenumber along the folded
    axis (the layout's `fft_dims[1]`, not necessarily the first physical axis); the rest are
    implied by the reality of the field, ``\\hat f(-k) = \\overline{\\hat f(k)}``. A kernel
    returns a field that is still real exactly when its own transfer function carries that
    symmetry, ``\\hat g(-k) = \\overline{\\hat g(k)}`` — equivalently, when the physical-space
    kernel ``g`` is real. Every kernel the package builds satisfies it: the real, even ones
    ([`spectral_cutoff`](@ref), [`spectral_band`](@ref), [`assignment_window`](@ref)) trivially, and the complex
    [`translation_kernel`](@ref) by construction. A `radial_kernel` — and so the exponential
    kernel `exponential_convolve!` applies — satisfies it too, and for the strongest reason: a
    real symbol of ``\\lvert k\\rvert^2`` is real, and ``\\lvert k\\rvert^2`` is even in ``k``, so
    the multiplier is real and even whatever the caller's closure computes. A caller-built
    kernel that breaks the symmetry yields coefficients that are those of no real field, and the
    inverse transform then silently keeps only their Hermitian part.

!!! note "Two kernels compose through the allocating form, which allocates nothing"
    This operation applies a kernel to a field. Composing two kernels into one is `convolve(g₁, g₂)`,
    and there is deliberately no in-place spelling, because there is nothing for one to save:
    composition never builds a field of coefficients in any storage class. Two separable kernels compose
    into their per-axis products, and two radial ones into a single closure when both are built over
    *canonical* multipliers — the grid's own wavenumbers, built by the convenience constructor rather than
    supplied by the caller — of the same concrete type ([`RadialKernel`](@ref) gives the condition); every
    other pair — two stored kernels, a cross-family pair, or radial operands failing that test —
    becomes a [`ProductKernel`](@ref) holding both factors unmultiplied and evaluating them in a
    single pass. Composing two stored kernels allocates zero bytes, against
    the ``O(N^3)`` a materialized product would cost, and applying the composite is bitwise-identical
    to applying the two in sequence. Use [`materialize_kernel`](@ref) if the coefficients themselves
    are wanted.
"""
function convolve! end


function convolve!(destination::AbstractFieldSpectral{T, R}, field::AbstractFieldSpectral{T, R},
    kernel::SpectralKernel{T}, α::Real, β::Real) where {T<:AbstractFloat, R}
  _check_field_compatibility(destination, field)
  _check_kernel_compatibility(field, kernel)
  kernel isa SeparableKernel &&
    return (_apply_separable_convolution!(field_data(destination), field_data(field), kernel, T(α), T(β));
            destination)
  kernel isa RadialKernel &&
    return (_apply_radial_convolution!(field_data(destination), field_data(field), kernel, T(α), T(β));
            destination)
  # THE STORED CLASS TAKES THE FUSED PASS. It holds one coefficient per mode, so `_apply_convolution!`
  # reads it once per mode through the fiberwise executor; the compressed broadcast below would read it
  # once per fiber COMPONENT instead. This guard used to be spelled `kernel isa AbstractSpectralKernel`
  # and meant "compressed", which a bare field was not — renaming the supertype to `SpectralKernel` made
  # the test true for every kernel and silently routed the stored class the wrong way. The pass audit
  # caught it as vector traffic of 3M reads against a frozen ideal of M.
  kernel isa StoredKernel &&
    return (_apply_convolution!(field_data(destination), field_data(field), _kernel_data(kernel),
                                T(α), T(β));
            destination)
  # Any other compressed kernel (a cross-family product) takes the flat cartesian broadcast: still no
  # kernel storage and no linear-to-cartesian conversion, just without a family-specific CPU twin.
  _apply_compressed_convolution!(field_data(destination), field_data(field), kernel, T(α), T(β))
  return destination
end


function convolve!(destination::AbstractFieldSpectral{T, R}, field::AbstractFieldSpectral{T, R},
    kernel::SpectralKernel{T}) where {T<:AbstractFloat, R}
  return convolve!(destination, field, kernel, one(T), zero(T))
end


"""
    convolve(field, kernel::SpectralKernel)
    convolve(kernel::SpectralKernel, field)
    convolve(first_kernel::SpectralKernel, second_kernel::SpectralKernel)

Allocating form of [`convolve!`](@ref): allocate the result and return the periodic convolution of its
two arguments, in spectral representation. A field and a kernel, either way round, give the filtered
field, with its representation and tensor order preserved; two kernels give the single kernel that
applies both, which is composition and allocates nothing of field size. See `convolve!` for the
componentwise definition, the storage classes, and why composition has no in-place form.
"""
function convolve end


function convolve(field::AbstractFieldSpectral, kernel::SpectralKernel)
  destination = similar_field(field, Val(field_tensor_order(field)))
  return convolve!(destination, field, kernel)
end

# EITHER ORDER APPLIES. Convolution is commutative, so `convolve(kernel, field)` and
# `convolve(field, kernel)` are the same operation and must return the same thing — the field, at the
# field's own tensor order. This method used to compose instead, because a bare field could itself be a
# kernel and argument position was the only thing left to carry the role; with a field no longer a
# kernel the types settle it and the asymmetry is gone.
convolve(kernel::SpectralKernel, field::AbstractFieldSpectral) = convolve(field, kernel)


"""
    field ⋆ kernel
    kernel ⋆ field
    first_kernel ⋆ second_kernel

Infix alias for [`convolve`](@ref), in every arity: `a ⋆ b` is `convolve(a, b)`. Convolving a field
with a kernel, either way round, filters the field in spectral representation; convolving two kernels
composes them into one. The distinct glyph keeps the operation apart from `*`, which would read as a
pointwise product.
"""
const ⋆ = convolve


####################################################
#        Kernel-composed combination               #
####################################################


"""
    _apply_convolution_combination!(destination_data, a_data, b_data, kernel_data,
                                    α, β)

Apply the fused kernel-times-combination product, computing
``\\texttt{dst} \\mathrel{.=} \\hat g \\cdot (\\alpha \\hat a + \\beta \\hat b)`` in one
coefficientwise pass (``\\hat g`` = `kernel_data`). The scalar `kernel_data` broadcasts over the
fiber components exactly as in `_apply_convolution!`, and the product is coefficientwise, so the
destination may alias either operand or the kernel.
"""
function _apply_convolution_combination!(destination_data::AbstractArray{<:Any, 3}, a_data, b_data, kernel_data, α, β)
  @_assign! destination_data .= kernel_data .* (α .* a_data .+ β .* b_data)
  return destination_data
end

# The fiber cases fuse like `_apply_convolution!` above: ĝ read once per mode. The executor's β
# is zero — the combination's own β lives inside the values (the `b === destination` filtered
# accumulate stays safe: an element's operands are read before its destination is written).
@inline function _combine_kernel_vector_values(kernel_value, a_1, a_2, a_3, b_1, b_2, b_3, α, β)
  return (kernel_value * (α * a_1 + β * b_1),
          kernel_value * (α * a_2 + β * b_2),
          kernel_value * (α * a_3 + β * b_3))
end

@inline function _combine_kernel_tensor_values(kernel_value,
    a_11, a_12, a_13, a_21, a_22, a_23, a_31, a_32, a_33,
    b_11, b_12, b_13, b_21, b_22, b_23, b_31, b_32, b_33, α, β)
  return (kernel_value * (α * a_11 + β * b_11), kernel_value * (α * a_12 + β * b_12),
          kernel_value * (α * a_13 + β * b_13), kernel_value * (α * a_21 + β * b_21),
          kernel_value * (α * a_22 + β * b_22), kernel_value * (α * a_23 + β * b_23),
          kernel_value * (α * a_31 + β * b_31), kernel_value * (α * a_32 + β * b_32),
          kernel_value * (α * a_33 + β * b_33))
end

function _apply_convolution_combination!(destination_data::AbstractArray{<:Any, 4}, a_data, b_data, kernel_data, α, β)
  _fiberwise_pass!(get_backend(destination_data), _combine_kernel_vector_values,
                   ntuple(component -> view(destination_data, :, :, :, component), Val(3)),
                   (kernel_data,
                    ntuple(component -> view(a_data, :, :, :, component), Val(3))...,
                    ntuple(component -> view(b_data, :, :, :, component), Val(3))...),
                   (α, β), one(α), zero(α))
  return destination_data
end

function _apply_convolution_combination!(destination_data::AbstractArray{<:Any, 5}, a_data, b_data, kernel_data, α, β)
  _fiberwise_pass!(get_backend(destination_data), _combine_kernel_tensor_values,
                   ntuple(n -> view(destination_data, :, :, :, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9)),
                   (kernel_data,
                    ntuple(n -> view(a_data, :, :, :, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9))...,
                    ntuple(n -> view(b_data, :, :, :, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9))...),
                   (α, β), one(α), zero(α))
  return destination_data
end


# The kernel-composed method of FieldAlgebra's `combine!` (documented in its home docstring): the
# weighted combination convolved with a kernel in the same fused pass. It is defined here, not in
# FieldAlgebra, because the kernel is a Convolution concept — and only for fields in spectral
# representation, since a kernel is a spectral object (the physical absence is a validity absence,
# invariant 1).
function combine!(destination::AbstractFieldSpectral{T, R}, α::Real, a::AbstractFieldSpectral{T, R},
    β::Real, b::AbstractFieldSpectral{T, R}, kernel::SpectralKernel{T}) where {T<:AbstractFloat, R}
  _check_field_compatibility(destination, a)
  _check_field_compatibility(destination, b)
  _check_kernel_compatibility(a, kernel)
  # As in `convolve!`: an axis-factored kernel takes the cartesian route. Handing its lazy per-axis
  # product to the linear-indexed executor below would make every element pay a linear-to-cartesian
  # integer division — the 3.4x-slower shape `PERFORMANCE.md` finding (o) measured and rejected.
  if kernel isa SeparableKernel
    _apply_separable_combination!(field_data(destination), field_data(a), field_data(b), kernel,
                                  T(α), T(β))
    return destination
  end
  _apply_convolution_combination!(field_data(destination), field_data(a), field_data(b),
    _kernel_data(kernel), T(α), T(β))
  return destination
end


####################################################
#        Exponential convolution                   #
####################################################


"""
    _apply_exponential_convolution!(destination_data, source_data, squared_wavenumber,
                                    coefficient, α, β)

    _apply_exponential_convolution!(destination_data, source_data, squared_wavenumber,
                                    coefficient, offset_scale, offset_data, α, β)

Apply the coefficientwise product with the exponential radial kernel, computing
``\\texttt{dst} \\mathrel{.=} \\alpha \\exp(c |k|^2) \\cdot \\hat f + \\beta \\texttt{dst}``
(the eight-argument form adds ``+ s \\hat w`` inside the exponential, with ``\\hat w`` =
`offset_data` and ``s`` = `offset_scale`). The `squared_wavenumber` is the lazy
`_squared_wavenumber_broadcast`, so the kernel is evaluated per mode inside the fused assignment and
never materialized. The call branches on `iszero(β)` to overwrite or accumulate; the product is
coefficientwise, hence alias-safe.
"""
function _apply_exponential_convolution!(destination_data, source_data, squared_wavenumber,
    coefficient, α, β)
  if iszero(β)
    @_assign! destination_data .= α .* exp.(coefficient .* squared_wavenumber) .* source_data
  else
    @_assign! destination_data .= α .* exp.(coefficient .* squared_wavenumber) .* source_data .+ β .* destination_data
  end
  return destination_data
end


function _apply_exponential_convolution!(destination_data, source_data, squared_wavenumber,
    coefficient, offset_scale, offset_data, α, β)
  if iszero(β)
    @_assign! destination_data .= α .* exp.(coefficient .* squared_wavenumber .+ offset_scale .* offset_data) .* source_data
  else
    @_assign! destination_data .= α .* exp.(coefficient .* squared_wavenumber .+ offset_scale .* offset_data) .* source_data .+ β .* destination_data
  end
  return destination_data
end


"""
    _apply_exponential_combination!(destination_data, a_data, b_data,
                                    squared_wavenumber, coefficient, α, β)

    _apply_exponential_combination!(destination_data, a_data, b_data,
                                    squared_wavenumber, coefficient,
                                    offset_scale, offset_data, α, β)

Apply the exponential radial kernel to a weighted combination, computing
``\\texttt{dst} \\mathrel{.=} \\exp(c |k|^2) \\cdot (\\alpha \\hat a + \\beta \\hat b)`` (the
eight-argument form adds ``+ s \\hat w`` inside the exponential) — the exponential twin of
`_apply_convolution_combination!`, with the kernel evaluated lazily per mode instead of read from a
stored field. Coefficientwise, hence alias-safe.
"""
function _apply_exponential_combination!(destination_data, a_data, b_data, squared_wavenumber,
    coefficient, α, β)
  @_assign! destination_data .= exp.(coefficient .* squared_wavenumber) .* (α .* a_data .+ β .* b_data)
  return destination_data
end


function _apply_exponential_combination!(destination_data, a_data, b_data, squared_wavenumber,
    coefficient, offset_scale, offset_data, α, β)
  @_assign! destination_data .= exp.(coefficient .* squared_wavenumber .+ offset_scale .* offset_data) .* (α .* a_data .+ β .* b_data)
  return destination_data
end




# ── The fiber hoist (IT item 2, 2026-08-30) ────────────────────────────────────────────────────────
#
# The exponential factor depends on the MODE alone — ``\exp(c |k|^2 [+ s \hat w])`` carries no fiber
# index — yet the broadcast route above evaluates it per output ELEMENT, so a vector field pays the
# scalar `exp` three times per mode and a tensor nine times, for identical arguments. The consumer's
# codegen report measured that at ``\approx 3.5\times`` the shape-identical `combine!` single-threaded
# at ``128^3``, where `exp` is the whole difference; this was also the pass audit's standing
# ŵ-extrusion holder. The route below computes the factor ONCE per mode and reuses it across the
# fiber, which is §9's execution-route policy applied as written — a cartesian-coefficient operator
# belongs on a decision-38 kernel pair.
#
# BITWISE, BY CONSTRUCTION, and this is load-bearing: the per-element arithmetic is exactly the
# broadcast's — the exponent associates ``(c \cdot k^2) + (s \cdot \hat w)``, the squared wavenumber
# ``(k_1^2 + k_2^2) + k_3^2`` (the three-argument broadcast `+`'s own left fold), the product
# ``(\alpha f) \cdot \hat s`` then ``+ (\beta \cdot \texttt{dst})`` — only the number of times `exp`
# is EVALUATED changes, and equal arguments give equal bits. The scalar (R = 0) forms stay on the
# broadcast route: one component means there is nothing to hoist, and an untouched route cannot
# regress.

"""
    _RadialOffset(sigma)

The symbol of a radial exponent offset, carried into the exponential kernels so that the offset
``\\sigma(|k|^2)`` is evaluated per mode from the squared wavenumber the kernel already forms, rather
than read from a stored field.

# Fields

- `sigma` — the radial symbol, a function of the squared wavenumber capturing values only.
"""
struct _RadialOffset{F}
  sigma::F
end


# The exponent at one mode: the optional per-mode offset field enters by dispatch on `Nothing`, so
# the plain form compiles with no dead argument (the `_optional_kernel_value` idiom).
# A RADIAL offset (a function of |k|² alone) is evaluated from the same |k|² the exponent is built
# from, once per mode, so no field of offset values is stored or read: `_RadialOffset` carries the
# symbol into the kernel, and the symbol captures values only, a captured type not being a bitstype.
@inline _exponential_exponent(scaled_k2, ::Nothing, ::Nothing, linear_mode, k2) = scaled_k2
@inline _exponential_exponent(scaled_k2, offset_scale, offset_data, linear_mode, k2) =
  @inbounds scaled_k2 + offset_scale * offset_data[linear_mode]
@inline _exponential_exponent(scaled_k2, offset_scale, offset::_RadialOffset, linear_mode, k2) =
  scaled_k2 + offset_scale * offset.sigma(k2)


# The row buffer's element type. Without an offset the exponent is the real ``c |k|^2`` and the
# factor is real. WITH one, the factor's type is the offset storage's: ŵ is documented as a real
# per-mode field, but it arrives in a spectral field's complex storage, and the broadcast route has
# always computed the complex exponential of whatever it was handed — a buffer typed real would
# TIGHTEN that contract by InexactError, which is a behaviour change decision 79 must not make. The
# fixtures that missed this held real values in complex storage; a true spectrum as ŵ found it.
@inline _exponential_factor_type(::Type{T}, ::Nothing) where {T} = T
@inline _exponential_factor_type(::Type{T}, offset_data) where {T} = eltype(offset_data)
@inline _exponential_factor_type(::Type{T}, ::_RadialOffset) where {T} = T


# One work-item per mode: the factor computed once, every fiber component scaled with it. Linear
# offsets (`mode + modes_per_fibre * (fibre - 1)`) reach the components without a reshape — the same
# addressing the transfer kernels use — so no per-call wrapper is allocated (the decision-76 lesson).
# Coefficientwise, hence alias-safe; sources deliberately not @Const where aliasing is legal.
@kernel function _exponential_convolution_kernel!(destination, source,
    @Const(squared_1), @Const(squared_2), @Const(squared_3), coefficient, offset_scale, offset_data,
    α, β, fibres, modes_per_fibre, mode_size, ::Val{ACCUMULATE}) where {ACCUMULATE}

  mode_1, mode_2, mode_3 = @index(Global, NTuple)
  @inbounds begin
    linear_mode = mode_1 + mode_size[1] * ((mode_2 - 1) + mode_size[2] * (mode_3 - 1))
    k2 = (squared_1[mode_1] + squared_2[mode_2]) + squared_3[mode_3]
    scaled_k2 = coefficient * k2
    scaled_factor = α * exp(_exponential_exponent(scaled_k2, offset_scale, offset_data, linear_mode, k2))
    for fibre in 1:fibres
      index = linear_mode + modes_per_fibre * (fibre - 1)
      if ACCUMULATE
        destination[index] = scaled_factor * source[index] + β * destination[index]
      else
        destination[index] = scaled_factor * source[index]
      end
    end
  end
end


@kernel function _exponential_combination_kernel!(destination, a_data, b_data,
    @Const(squared_1), @Const(squared_2), @Const(squared_3), coefficient, offset_scale, offset_data,
    α, β, fibres, modes_per_fibre, mode_size)

  mode_1, mode_2, mode_3 = @index(Global, NTuple)
  @inbounds begin
    linear_mode = mode_1 + mode_size[1] * ((mode_2 - 1) + mode_size[2] * (mode_3 - 1))
    k2 = (squared_1[mode_1] + squared_2[mode_2]) + squared_3[mode_3]
    scaled_k2 = coefficient * k2
    factor = exp(_exponential_exponent(scaled_k2, offset_scale, offset_data, linear_mode, k2))
    for fibre in 1:fibres
      index = linear_mode + modes_per_fibre * (fibre - 1)
      destination[index] = factor * (α * a_data[index] + β * b_data[index])
    end
  end
end


"""
    _exponential_convolution_modes!(backend, destination, source, multipliers,
                                    coefficient, offset_scale, offset_data,
                                    α, β, fibres, mode_size)

Run the fiber-hoisted exponential pass over every mode: the factor
``\\exp(c |k|^2 [+ s \\hat w])`` computed once per mode and applied to all `fibres` components. The
generic method launches `_exponential_convolution_kernel!` on the backend; the `CPU` method runs the
slab-threaded loop, bitwise identical at every thread count (each element is written exactly once).
"""
function _exponential_convolution_modes!(backend, destination, source, multipliers, coefficient,
    offset_scale, offset_data, α, β, fibres, mode_size)
  modes_per_fibre = prod(mode_size)
  accumulate = !iszero(β)
  _exponential_convolution_kernel!(backend)(destination, source,
    multipliers.squared_wavenumber_1, multipliers.squared_wavenumber_2,
    multipliers.squared_wavenumber_3, coefficient, offset_scale, offset_data, α, β,
    fibres, modes_per_fibre, mode_size, Val(accumulate); ndrange = mode_size)
  synchronize(backend)
  return nothing
end

function _exponential_convolution_modes!(::KernelAbstractions.CPU, destination, source, multipliers,
    coefficient, offset_scale, offset_data, α, β, fibres, mode_size)
  squared_1 = multipliers.squared_wavenumber_1
  squared_2 = multipliers.squared_wavenumber_2
  squared_3 = multipliers.squared_wavenumber_3
  modes_per_fibre = prod(mode_size)
  accumulate = !iszero(β)
  T = real(eltype(destination))
  # SERIAL takes the bufferless body: decision 70's lane pins this operator at literally zero bytes
  # on the serial lane, and the row buffer below is an allocation, however small. The two bodies are
  # bitwise identical — same arithmetic per element, and elements are independent — so the split
  # costs nothing but this comment. Serial is also where the buffer bought nothing: the fibre-inner
  # walk already wins ``2.4``–``3.9\times`` there, the strided-stream penalty being a property of a
  # SATURATED memory bus, which one thread does not produce.
  if !_use_threads(fibres * modes_per_fibre)
    @inbounds for mode_3 in 1:mode_size[3]
      squared_3_value = squared_3[mode_3]
      for mode_2 in 1:mode_size[2]
        row = mode_size[1] * ((mode_2 - 1) + mode_size[2] * (mode_3 - 1))
        for mode_1 in 1:mode_size[1]
          linear_mode = mode_1 + row
          k2 = (squared_1[mode_1] + squared_2[mode_2]) + squared_3_value
          scaled_k2 = coefficient * k2
          scaled_factor = α * exp(_exponential_exponent(scaled_k2, offset_scale, offset_data, linear_mode, k2))
          for fibre in 1:fibres
            index = linear_mode + modes_per_fibre * (fibre - 1)
            destination[index] = accumulate ?
              scaled_factor * source[index] + β * destination[index] :
              scaled_factor * source[index]
          end
        end
      end
    end
    return nothing
  end
  _foreach_outer_slab(Base.OneTo(mode_size[3]), fibres * modes_per_fibre) do outer_modes
    # One x-row of factors — a wavenumber row, not a field. The first shape of this loop kept the
    # fibre loop INNERMOST, which walked 3^R strided destination and source streams concurrently and
    # measured 0.76x the broadcast at ``256^3`` `Float64` `-t8`, where the pass is at the memory
    # roof and the pattern is everything. Buffering one row of factors instead keeps the hoist (one
    # `exp` per mode) while every inner loop streams a CONTIGUOUS row of one component, the same
    # pattern the broadcast had. The buffer is per slab task, so no state is shared across threads.
    factors = Vector{_exponential_factor_type(T, offset_data)}(undef, mode_size[1])
    @inbounds for mode_3 in outer_modes
      squared_3_value = squared_3[mode_3]
      for mode_2 in 1:mode_size[2]
        row = mode_size[1] * ((mode_2 - 1) + mode_size[2] * (mode_3 - 1))
        # The FIRST component's pass computes each factor and applies it in the same iteration, so
        # the `exp` hides under that stream the way it hides under the broadcast's; the remaining
        # components reuse the buffered factors as pure contiguous streams. Strictly less work than
        # the broadcast in every regime — same first pass, then streams with no `exp` at all.
        for mode_1 in 1:mode_size[1]
          # Association preserved: (k1² + k2²) + k3² is the broadcast's own left fold — the hoist
          # may reorder nothing.
          k2 = (squared_1[mode_1] + squared_2[mode_2]) + squared_3_value
          scaled_k2 = coefficient * k2
          scaled_factor = α * exp(_exponential_exponent(scaled_k2, offset_scale, offset_data, mode_1 + row, k2))
          factors[mode_1] = scaled_factor
          destination[mode_1 + row] = accumulate ?
            scaled_factor * source[mode_1 + row] + β * destination[mode_1 + row] :
            scaled_factor * source[mode_1 + row]
        end
        for fibre in 2:fibres
          base = row + modes_per_fibre * (fibre - 1)
          if accumulate
            @simd for mode_1 in 1:mode_size[1]
              destination[mode_1 + base] = factors[mode_1] * source[mode_1 + base] +
                                           β * destination[mode_1 + base]
            end
          else
            @simd for mode_1 in 1:mode_size[1]
              destination[mode_1 + base] = factors[mode_1] * source[mode_1 + base]
            end
          end
        end
      end
    end
  end
  return nothing
end


"""
    _exponential_combination_modes!(backend, destination, a_data, b_data, multipliers,
                                    coefficient, offset_scale, offset_data,
                                    α, β, fibres, mode_size)

The combination twin of [`_exponential_convolution_modes!`](@ref):
``\\exp(c |k|^2 [+ s \\hat w]) \\cdot (\\alpha \\hat a + \\beta \\hat b)`` with the factor computed once
per mode. Both operands are always read ([`combine!`](@ref)'s α/β exception class — β scales an operand,
never the destination), so there is no overwrite/accumulate split.
"""
function _exponential_combination_modes!(backend, destination, a_data, b_data, multipliers,
    coefficient, offset_scale, offset_data, α, β, fibres, mode_size)
  _exponential_combination_kernel!(backend)(destination, a_data, b_data,
    multipliers.squared_wavenumber_1, multipliers.squared_wavenumber_2,
    multipliers.squared_wavenumber_3, coefficient, offset_scale, offset_data, α, β,
    fibres, prod(mode_size), mode_size; ndrange = mode_size)
  synchronize(backend)
  return nothing
end

function _exponential_combination_modes!(::KernelAbstractions.CPU, destination, a_data, b_data,
    multipliers, coefficient, offset_scale, offset_data, α, β, fibres, mode_size)
  squared_1 = multipliers.squared_wavenumber_1
  squared_2 = multipliers.squared_wavenumber_2
  squared_3 = multipliers.squared_wavenumber_3
  modes_per_fibre = prod(mode_size)
  T = real(eltype(destination))
  # Serial bufferless, threaded row-buffered — the reason is on the convolution twin above.
  if !_use_threads(fibres * modes_per_fibre)
    @inbounds for mode_3 in 1:mode_size[3]
      squared_3_value = squared_3[mode_3]
      for mode_2 in 1:mode_size[2]
        row = mode_size[1] * ((mode_2 - 1) + mode_size[2] * (mode_3 - 1))
        for mode_1 in 1:mode_size[1]
          linear_mode = mode_1 + row
          k2 = (squared_1[mode_1] + squared_2[mode_2]) + squared_3_value
          scaled_k2 = coefficient * k2
          factor = exp(_exponential_exponent(scaled_k2, offset_scale, offset_data, linear_mode, k2))
          for fibre in 1:fibres
            index = linear_mode + modes_per_fibre * (fibre - 1)
            destination[index] = factor * (α * a_data[index] + β * b_data[index])
          end
        end
      end
    end
    return nothing
  end
  _foreach_outer_slab(Base.OneTo(mode_size[3]), fibres * modes_per_fibre) do outer_modes
    # The row-buffered shape, for the reason on the convolution twin above.
    factors = Vector{_exponential_factor_type(T, offset_data)}(undef, mode_size[1])
    @inbounds for mode_3 in outer_modes
      squared_3_value = squared_3[mode_3]
      for mode_2 in 1:mode_size[2]
        row = mode_size[1] * ((mode_2 - 1) + mode_size[2] * (mode_3 - 1))
        # First component fused with the factor fill, as in the convolution twin above.
        for mode_1 in 1:mode_size[1]
          k2 = (squared_1[mode_1] + squared_2[mode_2]) + squared_3_value
          scaled_k2 = coefficient * k2
          factor = exp(_exponential_exponent(scaled_k2, offset_scale, offset_data, mode_1 + row, k2))
          factors[mode_1] = factor
          destination[mode_1 + row] = factor * (α * a_data[mode_1 + row] + β * b_data[mode_1 + row])
        end
        for fibre in 2:fibres
          base = row + modes_per_fibre * (fibre - 1)
          @simd for mode_1 in 1:mode_size[1]
            destination[mode_1 + base] = factors[mode_1] *
                                         (α * a_data[mode_1 + base] + β * b_data[mode_1 + base])
          end
        end
      end
    end
  end
  return nothing
end


# The exponent offset ŵ is either a stored field of per-mode values or a radial kernel, a function of
# |k|² alone evaluated where the exponent is formed (2026-10-01, from the consumer's steady linear
# forcing, whose rate is radial and was held as a field of zeros but for its band). The three helpers
# are the only places the two kinds differ: the compatibility check, the lazy data the scalar
# (broadcast) route reads, and what the per-mode kernels of the R ≥ 1 route are handed.
const _ExponentOffset{T} = Union{ScalarFieldSpectral{T}, RadialKernel{T}}

_check_offset_compatibility(field, offset::ScalarFieldSpectral) = _check_field_domain_compatibility(field, offset)

function _check_offset_compatibility(field, offset::RadialKernel{T}) where {T}
  _check_kernel_compatibility(field, offset)
  _check_multipliers_compatibility(field, offset.multipliers)
  # The offset enters a REAL exponent: a complex symbol would make the factor complex, which no
  # radial offset needs and which the stored form's warning already rules out for a real field.
  offset.sigma(zero(T)) isa Real ||
    throw(ArgumentError("a radial exponent offset must be real-valued; its symbol returned " *
                        "$(typeof(offset.sigma(zero(T)))) at |k|² = 0"))
  return nothing
end

_offset_broadcast_data(offset::ScalarFieldSpectral) = field_data(offset)
_offset_broadcast_data(offset::RadialKernel) = _kernel_data(offset)
_offset_mode_data(offset::ScalarFieldSpectral) = field_data(offset)
_offset_mode_data(offset::RadialKernel) = _RadialOffset(offset.sigma)


"""
    _exponential_convolve!(destination, field, multipliers, coefficient, α, β)
    _exponential_convolve!(destination, field, multipliers, coefficient, offset_scale,
                           offset, α, β)
    _exponential_convolve!(destination, α, a, β, b, multipliers, coefficient[,
                           offset_scale, offset])

The engine behind [`exponential_convolve!`](@ref): the same operation with the exponent passed
positionally, one method per operand shape and offset class, so the offset's storage class (a stored
field or a [`RadialKernel`](@ref)) is resolved by dispatch here rather than in the public method.
"""
function _exponential_convolve!(destination::AbstractFieldSpectral{T, R}, field::AbstractFieldSpectral{T, R},
    multipliers::FieldSpectralMultipliers, coefficient::Real, α::Real, β::Real) where {T<:AbstractFloat, R}
  _check_field_compatibility(destination, field)
  _check_multipliers_compatibility(field, multipliers)
  if R == 0
    _apply_exponential_convolution!(field_data(destination), field_data(field),
      _squared_wavenumber_broadcast(multipliers), T(coefficient), T(α), T(β))
  else
    # The fiber hoist: exp once per mode, reused across the 3^R components (bitwise identical —
    # see the kernel-pair block above). The scalar case stays on the broadcast, having no fiber.
    data = field_data(destination)
    _exponential_convolution_modes!(get_backend(data), data, field_data(field), multipliers,
      T(coefficient), nothing, nothing, T(α), T(β), 3^R, size(data)[1:3])
  end
  return destination
end


function _exponential_convolve!(destination::AbstractFieldSpectral{T, R}, field::AbstractFieldSpectral{T, R},
    multipliers::FieldSpectralMultipliers, coefficient::Real) where {T<:AbstractFloat, R}
  return _exponential_convolve!(destination, field, multipliers, coefficient, one(T), zero(T))
end


function _exponential_convolve!(destination::AbstractFieldSpectral{T, R}, field::AbstractFieldSpectral{T, R},
    multipliers::FieldSpectralMultipliers, coefficient::Real, offset_scale::Real,
    offset::_ExponentOffset{T}, α::Real, β::Real) where {T<:AbstractFloat, R}
  _check_field_compatibility(destination, field)
  _check_offset_compatibility(field, offset)
  _check_multipliers_compatibility(field, multipliers)
  if R == 0
    _apply_exponential_convolution!(field_data(destination), field_data(field),
      _squared_wavenumber_broadcast(multipliers), T(coefficient), T(offset_scale),
      _offset_broadcast_data(offset), T(α), T(β))
  else
    data = field_data(destination)
    _exponential_convolution_modes!(get_backend(data), data, field_data(field), multipliers,
      T(coefficient), T(offset_scale), _offset_mode_data(offset), T(α), T(β), 3^R, size(data)[1:3])
  end
  return destination
end


function _exponential_convolve!(destination::AbstractFieldSpectral{T, R}, field::AbstractFieldSpectral{T, R},
    multipliers::FieldSpectralMultipliers, coefficient::Real, offset_scale::Real,
    offset::_ExponentOffset{T}) where {T<:AbstractFloat, R}
  return _exponential_convolve!(destination, field, multipliers, coefficient, offset_scale, offset, one(T), zero(T))
end


function _exponential_convolve!(destination::AbstractFieldSpectral{T, R}, α::Real, a::AbstractFieldSpectral{T, R},
    β::Real, b::AbstractFieldSpectral{T, R}, multipliers::FieldSpectralMultipliers,
    coefficient::Real) where {T<:AbstractFloat, R}
  _check_field_compatibility(destination, a)
  _check_field_compatibility(destination, b)
  _check_multipliers_compatibility(a, multipliers)
  if R == 0
    _apply_exponential_combination!(field_data(destination), field_data(a), field_data(b),
      _squared_wavenumber_broadcast(multipliers), T(coefficient), T(α), T(β))
  else
    data = field_data(destination)
    _exponential_combination_modes!(get_backend(data), data, field_data(a), field_data(b),
      multipliers, T(coefficient), nothing, nothing, T(α), T(β), 3^R, size(data)[1:3])
  end
  return destination
end


function _exponential_convolve!(destination::AbstractFieldSpectral{T, R}, α::Real, a::AbstractFieldSpectral{T, R},
    β::Real, b::AbstractFieldSpectral{T, R}, multipliers::FieldSpectralMultipliers,
    coefficient::Real, offset_scale::Real, offset::_ExponentOffset{T}) where {T<:AbstractFloat, R}
  _check_field_compatibility(destination, a)
  _check_field_compatibility(destination, b)
  _check_offset_compatibility(a, offset)
  _check_multipliers_compatibility(a, multipliers)
  if R == 0
    _apply_exponential_combination!(field_data(destination), field_data(a), field_data(b),
      _squared_wavenumber_broadcast(multipliers), T(coefficient), T(offset_scale),
      _offset_broadcast_data(offset), T(α), T(β))
  else
    data = field_data(destination)
    _exponential_combination_modes!(get_backend(data), data, field_data(a), field_data(b),
      multipliers, T(coefficient), T(offset_scale), _offset_mode_data(offset), T(α), T(β), 3^R,
      size(data)[1:3])
  end
  return destination
end


"""
    exponential_convolve!(destination, field, multipliers[, α::Real, β::Real];
                          coefficient::Real, offset = nothing, offset_scale::Real = 1)
    exponential_convolve!(destination, α::Real, a, β::Real, b, multipliers;
                          coefficient::Real, offset = nothing, offset_scale::Real = 1)

Convolve a field with an exponential kernel, given by its transfer function
``\\exp(c |k|^2 + s \\hat w(k))``, and write the result into `destination`, which is returned. For
``c \\le 0`` and no ``\\hat w`` this is the periodic Gaussian (heat) kernel, the operator
``e^{-c\\Delta}``, which smooths the field at the length scale ``\\sqrt{-2c}``. In spectral
representation each coefficient is multiplied by the kernel's value at its mode, with ``|k|^2`` the
true squared wavenumber, kept at the Nyquist frequency, so the kernel is real, even and positive; the
optional ``s \\hat w`` adds a per-mode term the caller supplies. The kernel is evaluated per mode and
never stored.

Use this in-place form when `destination` is already allocated; the allocating [`exponential_convolve`](@ref)
returns a fresh result instead. It acts in spectral representation only.

Prefer it to a [`StoredKernel`](@ref) holding the same factor when the exponent changes between
calls, since the stored kernel would be rebuilt each time. For one fixed kernel applied many times to a
scalar field, a stored kernel is usually faster, this form evaluating one exponential per
coefficient; on a vector or tensor field one exponential serves every component and the two are
comparable.

# Arguments

- `destination` — the field written with the result; it may alias `field` (or `a`, `b`, `offset`),
  since the product is coefficientwise.
- `field` — the field to filter, in spectral representation.
- `α`, `β` — trailing, in the single-operand forms: the accumulation weights of the formula below.
- `α`, `a`, `β`, `b` — leading, in the two-operand forms: the weights and fields of the combination
  ``\\alpha a + \\beta b``, as [`combine!`](@ref) takes them.
- `multipliers` — the wavenumber arrays for the field's grid.
- `coefficient` — a keyword: the real factor ``c`` on ``|k|^2`` in the exponent.
- `offset`, `offset_scale` — keywords: the per-mode values ``\\hat w`` and the real scale ``s`` of the
  optional exponent term ``s \\hat w``, absent with no `offset` whatever ``s`` is.

The `offset` is either a scalar field in spectral representation holding real values, or a
[`RadialKernel`](@ref) when ``\\hat w`` depends on ``|k|^2`` alone (a band, for instance), which is
evaluated per mode where the exponent is formed and stores nothing; the two give bitwise the same
result. The scale enters separately from the values, so a changed scale costs nothing.

The single-operand accumulate form computes, with ``\\hat d`` the coefficients of `destination`,

```math
\\hat d(k) \\leftarrow \\alpha \\exp\\bigl(c |k|^2 + s \\hat w(k)\\bigr) \\hat f(k) + \\beta \\hat d(k).
```

# The two-operand form

Passing `α, a, β, b` ahead of the multipliers applies the same kernel to a weighted combination,
``\\exp(c |k|^2 + s \\hat w) (\\alpha \\hat a + \\beta \\hat b)``, in one pass, as the kernel form of
`combine!` does for a stored kernel. With `b === destination` it is the filtered accumulate,
computed in place.

!!! warning "The offset must be real-valued and even"
    The exponential of a real, even multiplier keeps a real field real, and both halves of that
    hypothesis are the caller's to meet. A complex-valued `offset` breaks the Hermitian symmetry — and
    so does a real-valued one that is not even in ``k`` on the self-conjugate planes, where both
    members of a ``\\pm k`` pair are stored and nothing forces them equal. Either way the inverse
    transform then silently keeps only the Hermitian part, exactly as a caller-built kernel can
    under `convolve!`. There is deliberately no *scalar* exponent
    offset: a constant ``s_0`` in the exponent is ``e^{s_0}`` times the kernel and belongs in ``α``.

!!! warning "A deep `Float32` kernel is slow on a CPU"
    Where the exponent ``c |k|^2 + s \\hat w`` falls between about ``-103`` and ``-87``, the
    `Float32` exponential is a subnormal number, which a CPU produces through a slow hardware assist
    at many times the usual cost; a kernel deep enough to cover many modes in that band pays a
    multiple of its whole pass. `Float64` has its band near ``-708``, beyond any physical kernel, and
    GPUs flush subnormals to zero, so neither is affected. Where the band matters, use `Float64` or a
    milder exponent.
"""
function exponential_convolve! end


# The public forms take the exponent by keyword; the positional methods above are the engine. The
# offset's type (a stored field or a radial kernel) is resolved by the engine's own dispatch, so the
# public method stays one per operand shape.
function exponential_convolve!(destination::AbstractFieldSpectral{T, R}, field::AbstractFieldSpectral{T, R},
    multipliers::FieldSpectralMultipliers, α::Real, β::Real; coefficient::Real,
    offset::Union{Nothing, _ExponentOffset{T}} = nothing, offset_scale::Real = one(T)) where {T<:AbstractFloat, R}
  return offset === nothing ?
    _exponential_convolve!(destination, field, multipliers, coefficient, α, β) :
    _exponential_convolve!(destination, field, multipliers, coefficient, offset_scale, offset, α, β)
end


function exponential_convolve!(destination::AbstractFieldSpectral{T, R}, field::AbstractFieldSpectral{T, R},
    multipliers::FieldSpectralMultipliers; coefficient::Real,
    offset::Union{Nothing, _ExponentOffset{T}} = nothing, offset_scale::Real = one(T)) where {T<:AbstractFloat, R}
  return exponential_convolve!(destination, field, multipliers, one(T), zero(T);
    coefficient, offset, offset_scale)
end


function exponential_convolve!(destination::AbstractFieldSpectral{T, R}, α::Real, a::AbstractFieldSpectral{T, R},
    β::Real, b::AbstractFieldSpectral{T, R}, multipliers::FieldSpectralMultipliers; coefficient::Real,
    offset::Union{Nothing, _ExponentOffset{T}} = nothing, offset_scale::Real = one(T)) where {T<:AbstractFloat, R}
  return offset === nothing ?
    _exponential_convolve!(destination, α, a, β, b, multipliers, coefficient) :
    _exponential_convolve!(destination, α, a, β, b, multipliers, coefficient, offset_scale, offset)
end


"""
    exponential_convolve(field, multipliers; coefficient::Real, offset = nothing,
                         offset_scale::Real = 1)

Allocating form of [`exponential_convolve!`](@ref): allocate the result and return the field smoothed
by the exponential radial kernel, which for a non-positive coefficient is a periodic Gaussian blur. See
`exponential_convolve!` for the kernel, the argument meanings, and the two-operand forms; the
representation and tensor order are preserved.
"""
function exponential_convolve end


function exponential_convolve(field::AbstractFieldSpectral{T}, multipliers::FieldSpectralMultipliers;
    coefficient::Real, offset::Union{Nothing, _ExponentOffset{T}} = nothing,
    offset_scale::Real = one(T)) where {T<:AbstractFloat}
  destination = similar_field(field, Val(field_tensor_order(field)))
  return exponential_convolve!(destination, field, multipliers; coefficient, offset, offset_scale)
end


####################################################
#        Kernel builders                           #
####################################################




"""
    spectral_band(multipliers::FieldSpectralMultipliers,
                  wavenumber_low::Real, wavenumber_high::Real) -> RadialKernel

Build an isotropic sharp spectral band-pass kernel, returned as a [`RadialKernel`](@ref) — the function
itself rather than its coefficients, so it costs no field of storage. The evaluation is per mode, so on a CPU at a small grid an ``R \\ge 1`` field pays it once per fiber component — see `RadialKernel` for the measured trade-off against a materialized kernel. Use
[`materialize_kernel`](@ref) to expand it into a `StoredKernel`. It is built on
the multipliers' grid and array family: the transfer function is ``1`` on the wavenumber shell and
``0`` outside it.

Convolve a field with it to keep an isotropic shell of wavenumbers — a de-aliasing band, a forcing
band, or any shell selector. It is idempotent (``\\hat g^2 = \\hat g``), hence a projection, and it is
the annular generalization of [`spectral_cutoff`](@ref), which is the low-pass case
``k_\\mathrm{lo} = 0``.

# Arguments

- `multipliers` — the [`FieldSpectralMultipliers`](@ref) whose grid, Fourier layout, element type
  and array family the kernel takes as its own.
- `wavenumber_low`, `wavenumber_high` — the inner and outer edges ``k_\\mathrm{lo}``,
  ``k_\\mathrm{hi}`` of the retained shell.

```math
\\hat g(k) = \\begin{cases} 1, & k_\\mathrm{lo} \\le |k| \\le k_\\mathrm{hi}, \\\\ 0, & \\text{otherwise,} \\end{cases}
```

with ``|k|^2`` keeping the true value at the Nyquist frequency (the Laplacian convention). The band
edges are the caller's choice.
"""
function spectral_band(multipliers::FieldSpectralMultipliers,
                       wavenumber_low::Real, wavenumber_high::Real)
  T = _multipliers_scalar_type(multipliers)
  # The band is defined by |k|, so the edges must be non-negative and ordered. Squaring them first
  # hid both errors: a negative cutoff squared to a positive threshold and was silently reinterpreted
  # as its absolute value, and a reversed pair produced an empty kernel that filtered everything away
  # without complaint.
  (isfinite(wavenumber_low) && isfinite(wavenumber_high)) ||
    throw(ArgumentError("band edges must be finite, got ($wavenumber_low, $wavenumber_high)"))
  0 <= wavenumber_low <= wavenumber_high ||
    throw(ArgumentError("band edges must satisfy 0 <= low <= high, got ($wavenumber_low, $wavenumber_high)"))
  low_squared = T(wavenumber_low)^2
  high_squared = T(wavenumber_high)^2
  # Capture VALUES, never the type `T`: a closure that captures `Type{Float64}` is not a bitstype, and
  # a device rejects it at launch ("passing non-bitstype argument"). `one(T)`/`zero(T)` inside the body
  # would do exactly that.
  in_band, out_of_band = one(T), zero(T)
  return radial_kernel(squared -> ifelse(low_squared <= squared <= high_squared, in_band, out_of_band), multipliers)
end


"""
    spectral_cutoff(multipliers::FieldSpectralMultipliers,
                    wavenumber_cutoff::Real) -> RadialKernel

Build an isotropic sharp low-pass kernel, returned as a [`RadialKernel`](@ref) — the function itself
rather than its coefficients, so it costs no field of storage. The evaluation is per mode, so on a CPU at a small grid an ``R \\ge 1`` field pays it once per fiber component — see `RadialKernel` for the measured trade-off against a materialized kernel. Use [`materialize_kernel`](@ref) to
expand it into a `StoredKernel`. It is built on
the multipliers' grid and array family: the transfer function is ``1`` for ``|k| \\le k_c`` and ``0``
above it.

Convolve a field with it for the ideal low-pass projection, the basis of spectral truncation and
de-aliasing. It is idempotent (``\\hat g^2 = \\hat g``), hence a projection, and it is the low-pass
special case of [`spectral_band`](@ref) with ``k_\\mathrm{lo} = 0``.

Here `multipliers` is the [`FieldSpectralMultipliers`](@ref) whose grid, Fourier layout, element type
and array family the kernel takes as its own, and `wavenumber_cutoff` is the cutoff wavenumber
``k_c`` — a mode is kept when ``|k| \\le k_c``.

```math
\\hat g(k) = \\mathbf{1}\\bigl[ |k| \\le k_c \\bigr].
```

The choice of cutoff, such as a ``2/3`` de-aliasing rule or an LES filter scale, is the caller's.
The squared wavenumber ``|k|^2`` keeps the true value at the Nyquist frequency (the Laplacian
convention).
"""
function spectral_cutoff(multipliers::FieldSpectralMultipliers,
                         wavenumber_cutoff::Real)
  return spectral_band(multipliers, zero(wavenumber_cutoff), wavenumber_cutoff)
end


"""
    tophat_window(multipliers::FieldSpectralMultipliers, width::Real) -> SeparableKernel
    tophat_window(multipliers::FieldSpectralMultipliers,
                  width::NTuple{3, Real}) -> SeparableKernel

Return the top-hat (box-average) window of a given width as a [`SeparableKernel`](@ref), its three
per-axis factors on the multipliers' grid and array family: convolving a field with it replaces the
field at each point by its mean over the box of that width centred there.

Use it to average a field over sub-boxes smaller than the domain — the scale-resolved statistics
that remove a sub-box mean, such as the kinetic energy held in scales below a given size, or a box
filter of chosen width. The returned `w` is the window's transfer function ``\\hat W``; the weights those
statistics need are its square, `convolve(w, w)`, which composes per axis at no extra cost.

Here `multipliers` is the [`FieldSpectralMultipliers`](@ref) whose grid, Fourier layout, element type
and array family the window takes as its own, and `width` is the edge of the box in the units of the
domain: one number for a cube, or one per axis for a rectangular box. Each edge must be finite and
non-negative, and a zero edge leaves that axis unfiltered.

As a real physical object the window is the normalized indicator of the box, the tensor product of
per-axis top-hats, and the returned transfer function is its product of per-axis sincs:

```math
\\begin{gathered}
W(x) = \\prod_{a=1}^{3} \\frac{1}{l_a} \\mathbf{1}\\bigl[|x_a| \\le \\tfrac{l_a}{2}\\bigr], \\\\
\\hat W(k) = \\prod_{a=1}^{3} \\operatorname{sinc}\\Bigl(\\tfrac{k_a l_a}{2}\\Bigr), \\\\
\\operatorname{sinc}(y) = \\frac{\\sin y}{y},
\\end{gathered}
```

with ``l_a`` the box edge along axis ``a``, ``x_a`` the displacement along it reduced onto the periodic
domain, and ``k_a`` the true wavenumber component, kept at the Nyquist frequency so a real field stays
real. On a periodic domain the width may be any non-negative number:
at ``l_a`` equal to the domain's extent every nonzero wavenumber along that axis is cancelled to
rounding, so a box the size of the domain keeps the mean alone, and as ``l_a \\to 0`` that axis's factor
tends to one. The [`assignment_window`](@ref) is this window at the grid spacing, squared.

!!! note "It averages the band-limited field, not the grid values"
    The sinc is the transform of the continuum box, so the result is the exact box mean of the
    band-limited field the grid values represent, even for an edge of a whole number of cells: it is
    not the mean of the nodes inside the box. That field can itself exceed the range of its grid
    values, and so can its box mean, where a mean of grid values could not.
"""
function tophat_window(multipliers::FieldSpectralMultipliers, width::Real)
  return tophat_window(multipliers, (width, width, width))
end


function tophat_window(multipliers::FieldSpectralMultipliers, width::NTuple{3, Real})
  all(w -> isfinite(w) && w >= 0, width) ||
    throw(ArgumentError("a top-hat width must be finite and non-negative; got $width"))
  T = _multipliers_scalar_type(multipliers)
  # sinc(|k_a| l_a / 2) per axis, GPU-safe (ifelse, not Base.sinc's branch); 1 at k_a = 0 or l_a = 0.
  axis(squared_wavenumber, l) =
    (y = sqrt.(squared_wavenumber) .* (T(l) / 2); ifelse.(iszero.(y), one(T), sin.(y) ./ y))
  w1 = reshape(axis(multipliers.squared_wavenumber_1, width[1]), :, 1, 1)
  w2 = reshape(axis(multipliers.squared_wavenumber_2, width[2]), 1, :, 1)
  w3 = reshape(axis(multipliers.squared_wavenumber_3, width[3]), 1, 1, :)
  # Real factors: the window is an even function of each k_a, and a real multiplier against a complex
  # field is cheaper than a complex one.
  return SeparableKernel{T}(w1, w2, w3, multipliers.grid, multipliers.fourier_layout)
end


"""
    assignment_window(multipliers::FieldSpectralMultipliers) -> SeparableKernel

Return the linear (cloud-in-cell) mass-assignment window — *assignment* in the particle-mesh sense
of depositing a point's mass onto the grid cells around it, not the sense of writing a value into an
array — as a [`SeparableKernel`](@ref) — its three
per-axis factors rather than a field of coefficients — on the multipliers' grid and array family, for
deconvolving a gridded point density.

Use it when a pair correlation is estimated from points deposited on a grid rather than counted
directly. Depositing ``M`` points on the grid with the positive linear
assignment (`LalescuSpline(2)` — the two-point linear "tent" transfer kernel, the smoothness ``m = 0``
member of the `Interpolation` spline family) spreads each point's
mass over a tent, so the gridded density is the true density ``\\rho`` convolved with this window,
``\\rho_g = \\rho \\star W``. Dividing the transform by ``\\hat W`` — a [`convolve`](@ref) by
``1/\\hat W`` — undoes that smearing before you estimate the radial distribution function ``g(r)``
(the pair density at separation ``r`` relative to an uncorrelated uniform gas).

Here `multipliers` is the [`FieldSpectralMultipliers`](@ref) whose grid, Fourier layout, element type
and array family the window takes as its own.

As a real physical object ``W`` is the linear B-spline ("tent") cloud, the tensor product of per-axis
tents:

```math
W(x) = \\prod_{a=1}^{3} \\frac{1}{\\Delta x_a} 
       \\max\\Bigl(0, 1 - \\frac{|x_a|}{\\Delta x_a}\\Bigr),
```

each a tent of half-width one cell ``\\Delta x_a`` along axis ``a``, of unit integral — the
[`tophat_window`](@ref) at the grid spacing convolved with itself, hence the squared sinc. It returns its
transfer function ``\\hat W(k)``, the squared sinc

```math
\\begin{gathered}
\\hat W(k) = \\prod_{a=1}^{3} \\operatorname{sinc}^2\\Bigl(\\tfrac{k_a \\Delta x_a}{2}\\Bigr), \\\\
\\operatorname{sinc}(y) = \\frac{\\sin y}{y},
\\end{gathered}
```

computed from the per-axis wavenumber ``k_a`` (kept at the Nyquist frequency) and the grid spacing
``\\Delta x_a``, so ``\\hat W(0) = 1`` and it decays toward the grid scale. Because the squared sinc
does not vanish at any wavenumber the grid resolves, dividing by it is stable. Stable is not
exact: ``\\hat W`` is the transform of the continuum tent, while a grid deposit applies that transform plus
the aliasing sum over the periodic images of ``k``, so the division undoes the smearing only up to that
aliasing — trust the band well below the Nyquist frequency. The package supplies the
window; the density estimate and the correlation normalization stay with the caller.

# References

  * R. W. Hockney, J. W. Eastwood, [*Computer Simulation Using
    Particles*](https://doi.org/10.1201/9780367806934), Adam Hilger, Bristol, 1988 (deposition /
    charge assignment; the NGP and CIC windows).
"""
function assignment_window(multipliers::FieldSpectralMultipliers)
  # The CIC tent is a cell-wide top-hat convolved with itself; composing the two separable factors
  # squares each per-axis sinc, bitwise the direct sinc² (x^2 lowers to x*x).
  cell = tophat_window(multipliers, multipliers.grid.grid_spacing)
  return convolve(cell, cell)
end


"""
    translation_kernel(multipliers::FieldSpectralMultipliers,
                       displacement::NTuple{3, Real}) -> SeparableKernel

Build the kernel that translates a field by the physical displacement ``h`` = `displacement`, returned as a
[`SeparableKernel`](@ref) on the multipliers' grid and array family: convolving a field ``f``
with it gives the displaced field ``f(x - h)``, the position ``x`` reduced onto the periodic box.

Use it to move a field onto a displaced grid without re-gridding — a shift-and-average filter, the
relocation of a probe, or the displaced evaluation of a phase-shift de-aliasing scheme. Apply it with
[`convolve`](@ref) / [`convolve!`](@ref), which is allocation-free in place; because a scalar kernel
multiplies every fiber component, one call translates a whole vector or tensor field, and because the
kernel depends on nothing but the displacement, one kernel serves every field it is applied to (and
it is separable, so building it costs three ``O(N)`` axis passes, not a field). To *sample* the field at the displaced positions
``x + h`` instead, pass the negated displacement — the two are inverse translations. This is the package's
one complex kernel: on every sub-Nyquist mode it is a pure phase of unit modulus, so it moves the
field without touching any amplitude, unlike the real and even [`spectral_cutoff`](@ref) or
[`assignment_window`](@ref). At the *Nyquist frequency* — the highest wavenumber a grid stores, ``\\pi/\\Delta x_a``, which an
even-length axis stores as a single self-conjugate mode — the factor is instead the real
number ``\\cos(\\pi h_a / \\Delta x_a)``, which attenuates rather than translates and vanishes at a
half-cell shift — the reality condition demands it, and the warning below gives the detail.

Here `multipliers` is the [`FieldSpectralMultipliers`](@ref) whose grid, Fourier layout, element type
and array family the kernel takes as its own, and `displacement` is the displacement
``h = (h_1, h_2, h_3)`` — a physical length per axis in the units of the box rather than a count of
cells, so a half-cell displacement is `0.5 .* grid.grid_spacing` on the [`Grid3D`](@ref GBGPeriodicFields.Fields.Grid3D) the field lives on.

As a real physical object the translation is the convolution with a Dirac delta displaced to ``h`` and
periodized on the box, ``g = \\delta(x - h)``, whose sifting property (integrating against a delta
evaluates the integrand at the delta's location) gives
``(f \\star g)(x) = f(x - h)`` exactly. On the grid that ``g`` is the band-limited (periodic-sinc)
interpolation stencil centred at ``h``, so the convolution re-samples the trigonometric interpolant of
``f`` at the displaced nodes ``x - h``, and collapses to a plain index shift when ``h`` is a whole
number of cells. Its transfer function ``\\hat g`` at wavenumber ``k`` is the shift theorem's phase,
assembled per axis from that wavenumber's component ``k_a`` and the displacement ``h_a`` along the
axis:

```math
\\hat g(k) = \\prod_{a=1}^{3} \\bigl[ \\cos(k_a h_a) - \\mathrm{i} \\sin(a_a h_a) \\bigr],
```

where ``k_a`` is the *true* wavenumber and ``a_a`` the *Nyquist-zeroed derivative*
one — the package's two families, and the reason this is written with two symbols rather than as the
bare phase ``e^{-\\mathrm{i} k \\cdot h}``. The two coincide on every resolved mode — so the factor there
is that pure phase — and part only at an even axis's Nyquist frequency, where the warning below
applies.

!!! warning "At the Nyquist frequency the phase becomes a real attenuation"
    On an even-length axis the Nyquist mode of a real field carries a single real amplitude that
    stands for both of the wavenumbers ``\\pm\\pi/\\Delta x_a`` (with ``\\Delta x_a`` the grid spacing
    along axis ``a``), so its band-limited form is the cosine ``\\cos(\\pi x_a/\\Delta x_a)``, and
    displacing that cosine re-samples on the grid to ``\\cos(\\pi h_a/\\Delta x_a)`` times itself. At
    that one frequency the kernel therefore carries this real factor rather than a complex phase —
    and it has to be real: the Nyquist mode is its own conjugate partner, so a complex factor there
    would leave coefficients that are those of no real field at all. A displaced Nyquist mode is thus
    attenuated rather than moved: it vanishes for a half-cell displacement and changes sign for an odd
    whole-cell one. Two consequences follow, both confined to that frequency: the translation is not
    invertible there (displacing by ``h`` and back scales the mode by ``\\cos^2``), and two
    translations compose exactly on every resolved mode but not at Nyquist. Whole-cell displacements
    are exact everywhere, and a field with no Nyquist content — one truncated by a de-aliasing cutoff —
    never meets the caveat at all.
"""
function translation_kernel(multipliers::FieldSpectralMultipliers,
                            displacement::NTuple{3, Real})
  T = _multipliers_scalar_type(multipliers)
  # exp(-i k h) = cos(k h) - i·sin(k h) splits into an even and an odd function of k, and the two
  # wavenumber families the multipliers carry (invariant 5) are precisely what each half needs: the
  # even cosine takes the true wavenumber |k_a| = √(k_a²), which keeps its Nyquist value, while the
  # odd sine takes the derivative wavenumber, which is zeroed there. Every axis factor then conjugates
  # under k_a → -k_a — real at the Nyquist slot, which is its own negative — so the kernel is Hermitian
  # and a real field stays real. A phase built from the true Nyquist wavenumber is not Hermitian, and
  # hands back coefficients that are no real field's (the docstring's warning).
  axis_phase(squared_wavenumber, derivative_wavenumber, displacement) =
    (d = T(displacement);
     Complex{T}.(cos.(sqrt.(squared_wavenumber) .* d), .-sin.(derivative_wavenumber .* d)))
  phase_1 = reshape(axis_phase(multipliers.squared_wavenumber_1, multipliers.wavenumber_1, displacement[1]), :, 1, 1)
  phase_2 = reshape(axis_phase(multipliers.squared_wavenumber_2, multipliers.wavenumber_2, displacement[2]), 1, :, 1)
  phase_3 = reshape(axis_phase(multipliers.squared_wavenumber_3, multipliers.wavenumber_3, displacement[3]), 1, 1, :)
  # The three factors ARE the kernel: their product is evaluated per mode, never materialized.
  return SeparableKernel{T}(phase_1, phase_2, phase_3, multipliers.grid, multipliers.fourier_layout)
end


"""
    translation_kernel!(kernel::SeparableKernel, multipliers::FieldSpectralMultipliers,
                        displacement::NTuple{3, Real})

Rebuild and return `kernel` for a new displacement `displacement`, overwriting its per-axis factors.
Use this
in-place form when the kernel is already allocated; the allocating
[`translation_kernel`](@ref) returns a fresh kernel instead. It costs three ``O(N)`` axis passes,
not a field.

# Arguments

- `kernel` — the translation kernel, a [`SeparableKernel`](@ref), whose factors are overwritten; a
  real-valued window is refused.
- `multipliers` — the wavenumber arrays, supplying both families (the derivative wavenumbers and
  the true squared ones), checked against `kernel`'s grid and layout.
- `displacement` — the physical displacement ``h`` as a three-tuple.

The displacement convention and the Nyquist treatment are `translation_kernel`'s.
"""
function translation_kernel!(kernel::SeparableKernel{T, V}, multipliers::FieldSpectralMultipliers,
    displacement::NTuple{3, Real}) where {T, V}
  # A translation is a complex phase, so only a kernel with complex factors can hold one. A real
  # window (`assignment_window`, `tophat_window`) was accepted and failed by conversion part-way
  # through the write — an `InexactError` on the host, a `KernelException` on a device. The check is
  # on the type, so it folds away for the kernels this function exists for.
  eltype(V) <: Complex || throw(ArgumentError(
    "translation_kernel! rebuilds a translation kernel, whose factors are complex; this " *
    "SeparableKernel holds real factors ($(eltype(V))), as a window does. Build a translation " *
    "kernel with translation_kernel(multipliers, displacement)."))
  # The allocating builder derives its context from the multipliers; this one is handed a kernel
  # and a multiplier set that were built independently, so it has to check they agree. Without the
  # check, multipliers from another domain of the same axis lengths rewrote the kernel with the wrong
  # physical phase and the wrong displacement — a silent corruption, since every subsequent
  # application succeeds and returns a plausible field.
  _check_matching_context(kernel, multipliers)
  axis_phase!(destination, squared_wavenumber, derivative_wavenumber, displacement) =
    (d = T(displacement);
     destination .= Complex{T}.(cos.(sqrt.(squared_wavenumber) .* d), .-sin.(derivative_wavenumber .* d)))
  axis_phase!(vec(kernel.factor_1), multipliers.squared_wavenumber_1, multipliers.wavenumber_1, displacement[1])
  axis_phase!(vec(kernel.factor_2), multipliers.squared_wavenumber_2, multipliers.wavenumber_2, displacement[2])
  axis_phase!(vec(kernel.factor_3), multipliers.squared_wavenumber_3, multipliers.wavenumber_3, displacement[3])
  return kernel
end


###################################################
#   Moving between array families (Adapt.jl)    #
###################################################

# One method per storage class. The compressed classes carry a grid and layout that are pure bitstypes
# and so ride along unchanged; only the arrays move. A `RadialKernel` moves its multipliers and keeps
# its symbol, which must already be a closure over VALUES rather than a type for the kernel to launch
# at all, so it is as transferable as the multipliers are. A `ProductKernel` moves both factors, which
# is what keeps a cross-family composition from being assembled by accident.
adapt_structure(to, kernel::StoredKernel) = StoredKernel(adapt(to, kernel.field))

adapt_structure(to, kernel::SeparableKernel{T}) where {T} =
  SeparableKernel{T}(adapt(to, kernel.factor_1), adapt(to, kernel.factor_2), adapt(to, kernel.factor_3),
                     kernel.grid, kernel.layout)

adapt_structure(to, kernel::RadialKernel{T}) where {T} =
  RadialKernel{T}(kernel.sigma, adapt(to, kernel.multipliers), kernel.grid, kernel.layout)

adapt_structure(to, kernel::ProductKernel{T}) where {T} =
  ProductKernel{T}(adapt(to, kernel.first_kernel), adapt(to, kernel.second_kernel))


# ---------------------------------------------------------------------------------------------
# Display. See the note on the field methods in `Fields` for why the compact form is parenthesised,
# what its body may carry and why nothing may read an element; the same rules bind here and the flood
# is worse. A `SeparableKernel` on a 512^3 grid prints 56742 characters by default and a
# `ProductKernel` 58090, because both hold or wrap coefficient arrays; a `RadialKernel` holds none
# and still printed 815, its symbol being an anonymous closure whose generated type name is most of
# the line. There is one form and no `MIME"text/plain"` sibling, for the same reason as the point
# sections: the class, element type, base and array family are the whole of a kernel's metadata,
# and they fit on the compact line.
#
# A kernel is shown as its class, element type, base and array family. The base and family are what
# `_check_kernel_compatibility` refuses on, by way of the same domain check the fields use; the class
# and element type are what distinguishes two kernels the check would accept. The SYMBOL is
# deliberately absent: a closure has no readable form, and printing
# `#spectral_band##0#spectral_band##1` names an implementation detail rather than the mathematics.
#
# THREE EXPLICIT METHODS, not one on the abstract `SpectralKernel`. A fallback there would give a
# fifth class a correct display for free, and `test/display.jl` would then pass without anyone having
# thought about it — but `SpectralKernel` is EXPORTED, so a consumer may subtype it, and a fallback
# would call `_kernel_storage` on a type that never defined it. A `show` that throws is worse than
# one that floods, because it breaks the REPL and every error message carrying the object. So the
# package's own classes are enumerated, a new one is caught by the derived gate rather than by a
# fallback, and a third-party subtype gets Julia's default, which is what it would get anyway.

"""
    _kernel_storage(kernel)

Represent the kernel's array family as an array, one method per storage class.

A kernel is not a section and has no [`field_data`](@ref), and the four classes hold their memory in four
different shapes: a stored kernel wraps a field, a separable one holds three per-axis factors, a
radial one holds no coefficients at all and borrows its family from the multipliers it evaluates
against, and a product borrows from its first factor, the two being required to agree. Used only for
display, to name the family a kernel would combine within.
"""
function _kernel_storage(kernel::StoredKernel)
  return field_data(kernel.field)
end

_kernel_storage(kernel::RadialKernel) = kernel.multipliers.wavenumber_1
_kernel_storage(kernel::SeparableKernel) = kernel.factor_1
_kernel_storage(kernel::ProductKernel) = _kernel_storage(kernel.first_kernel)


"""
    _show_kernel(io, kernel)

Print a kernel as its class, element type, base and array family.

The base and the family are what `_check_kernel_compatibility` refuses on; the class and the element
type are what separates two kernels it would accept. Shared by the three classes whose display is
this and nothing more — `ProductKernel` has its own, because it nests its factors.
"""
function _show_kernel(io::IO, kernel::SpectralKernel{T}) where {T}
  print(io, nameof(typeof(kernel)), "{", T, "}(")
  _show_extent(io, _context_grid(kernel).grid_size)
  print(io, " grid")
  _show_domain(io, _context_grid(kernel), _context_layout(kernel))
  print(io, ", ", nameof(_array_family(_kernel_storage(kernel))), ")")
end


Base.show(io::IO, kernel::StoredKernel) = _show_kernel(io, kernel)
Base.show(io::IO, kernel::RadialKernel) = _show_kernel(io, kernel)
Base.show(io::IO, kernel::SeparableKernel) = _show_kernel(io, kernel)


# The product prints its two factors in full rather than naming their types, so the form NESTS: a
# product of products renders correctly at any depth, where a "factors A and B" summary would lose
# every level below the first. The base is repeated in each factor, which is redundant but true —
# the constructor requires the two to agree on it.
function Base.show(io::IO, kernel::ProductKernel{T}) where {T}
  print(io, "ProductKernel{", T, "}(")
  show(io, kernel.first_kernel)
  print(io, ", ")
  show(io, kernel.second_kernel)
  print(io, ")")
end


end # module Convolution
