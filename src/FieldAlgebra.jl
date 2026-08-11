"""
    FieldAlgebra

Fiberwise and pointwise algebra for the scalar, vector, and second-order tensor fields defined in
[`Fields`](@ref). Each operation comes as an allocating form — a `Base` or `LinearAlgebra` operator where
one exists — and an in-place `!` form.

Every operation here acts **pointwise over the base** — the set of locations the field attaches a value
to, which for a field is the grid's points — applying the same formula to the value at each one and
touching no neighbours. That is what the formulas below mean by "pointwise over the base".

Acting pointwise is *not* what makes an operation available in both representations, and the two must
not be confused: `det` and `norm` are as pointwise as any operation here and are physical-space only.
What carries an operation across the transform is **linearity in the field argument**, since only a
linear map commutes with the rfft isomorphism — which is why the linear operations below (the sums,
the fiber-constant contractions, the transposes, `sym`/`skew`/`dev`) exist in both representations
while every operation nonlinear in a field is defined in physical representation alone.

The parts are:

  * **Vector-space and scalar-field-scaling operations** — [`add!`](@ref) and `subtract!` (`+`, `-`), the weighted
    combination [`combine!`](@ref) (``\\alpha a + \\beta b``), real scaling, and scalar-field
    multiplication and division ([`multiply!`](@ref), `divide!`, `*`, `/`). Addition, weighted combination,
    and real scaling are the vector-space structure; scalar-field multiplication is the action that makes
    fields a *module* over the ring of scalar fields — the algebraic sense of the word, not a Julia
    module: scaling a field by another field rather than by a number.
  * **Contraction and product operations** — [`dot!`](@ref) computes the vector Euclidean and tensor
    Frobenius inner products (`⋅`), [`cross!`](@ref) the cross product (`×`), [`mul!`](@ref) the
    tensor-on-vector action (left and right) and the tensor-on-tensor product — contracted (matrix)
    products, not the outer tensor product — with a five-argument `α`/`β` accumulation form and an
    allocating `*`, [`tr!`](@ref) the trace, the self-contraction of a tensor's own two indices, and
    [`det!`](@ref) the determinant, the tensor's third principal invariant.
  * **Transposition and decomposition operations** — [`transpose!`](@ref) transposes the fiber indices,
    and `sym`, `skew`, `dev` split off the symmetric, skew-symmetric, and deviatoric parts (each with a
    `!` form).
  * **Norm operations** — [`norm!`](@ref) computes the pointwise absolute-value, Euclidean, and Frobenius
    norms.
Two words recur below. A **fiber** is the value at one base point — a scalar, a `FiberVector` or a
`FiberTensor2` — and a **section** is one fiber at every point of a base, which is what a field and a
set of point-values each are. That shared shape is why one set of formulas serves both.

  * **Arbitrary fiber map** — [`map!`](@ref) and [`map`](@ref) apply *any* fiber map `φ` you supply at
    every base point — a composition like `exp ∘ det`, a pointwise equation of state, whatever is not one
    of the named operations above. This is the section-valued **escape hatch** for un-named maps (and the
    sibling of the mapped reductions such as `mean(det, ·)`): `φ` may change the tensor order, and the
    result's order is `φ`'s (`map(det, A)` gives a scalar field). A field must be in physical representation, since an arbitrary
    `φ` is nonlinear.

Field-field and field-constant operations preserve the representation of their arguments: they act
pointwise on fields in physical representation and coefficient-wise on fields in spectral
representation. An operation that is not linear in a field argument — multiplying two fields together, or
contracting two fields — is defined only in physical representation, except where one factor is a
compile-time constant fiber, which keeps the operation coefficient-wise; the missing combinations are
deliberate.

!!! warning "Nonlinear results are spectrally aliased"
    (*Spectral* aliasing here — content folding back onto resolved modes — not the storage aliasing of
    the admonition below, which is about two arguments sharing memory. The two senses are unrelated.)
    A nonlinear operation — a field-field product (`*`, `mul!`, `dot`, `cross`, `divide!`) or a nonlinear
    fiber invariant (`det`, `norm`) — generates content above the grid's Nyquist wavenumber, so its result
    is not band-limited — it carries wavenumbers the grid cannot represent. The pointwise values at the
    grid nodes are exact, but transforming the result to
    spectral representation folds that out-of-band content back onto the resolved modes as aliasing error.
    Before feeding such a result into a spectral computation — a solver's nonlinear term — de-alias it with
    the sharp low-pass `spectral_cutoff` or the phase-shift `translation_kernel` from
    [`Convolution`](@ref). This is the same fact that makes these operations physical-space only: a
    nonlinearity has no finite-band spectral form.

The `mul!` product follows the `LinearAlgebra` convention that the destination must not share storage with an input,
while the index-shuffling operations (`cross`, `transpose`, `sym`, `skew`, `dev`) are alias-safe by construction (each fused pass reads an element's sources before writing any output) and
may be called with the destination aliasing an input.

!!! note "Why an aliased in-place call is safe"
    `destination` may **be** an input — `sym!(A, A)` is computed directly and is bitwise-identical to
    the non-aliased call — because a fused pass reads all of an element's sources into registers before
    writing any of that element's outputs. That argument needs one section's element ``n`` to be the
    other's element ``n``, and it is the **ownership** rule that supplies it: a section's constructor
    refuses borrowed storage, so two sections can share memory only by being backed by the same array.
    Two partially-overlapping views at *different* base indices would break the argument, and they are
    not merely undetected — they cannot be constructed. The `mul!` operation is the one exception, keeping
    `LinearAlgebra`'s contract that its destination must not alias.

Most of this module is mirrored onto point-values (`AbstractPointValues`) — the same fiberwise algebra
applied to field values sampled at an unstructured point set, generated from the same builders so no
formula is written twice. The mirror covers the physical-representation surface, not every binding: the
weighted combination `combine!` has no point-value method, for instance. See the [`Points`](@ref)
module for what the point layer provides.
"""
module FieldAlgebra


using ..Fields:
  _spectral_constant_scale,
  _spectral_zero_mode_data,
  _spectral_zero_mode_component_data,
  FiberVector,
  FiberTensor2,
  AbstractField,
  AbstractFieldPhysical,
  AbstractFieldSpectral,
  ScalarFieldPhysical,
  ScalarFieldSpectral,
  VectorFieldPhysical,
  VectorFieldSpectral,
  TensorFieldPhysical,
  TensorFieldSpectral,
  field_data,
  field_grid,
  field_layout,
  field_scalar_type,
  field_tensor_order,
  similar_field,
  check_field_compatibility,
  _check_field_domain_compatibility,
  _vector_component_data,
  _tensor2_component_data


using ..FiberSections:
  AbstractFiberSection,
  section_scalar_type,
  _assign!,
  _to_broadcasted,
  @_assign!,
  _add_values,
  _subtract_values,
  _vector_component,
  _tensor_component,
  _sum_terms,
  _product,
  _vector_kernel_body,
  _tensor_kernel_body,
  _scalar_kernel_body,
  _dot_vector_rhs,
  _dot_tensor_rhs,
  _cross_formula,
  _tensor_vector_formula,
  _vector_tensor_formula,
  _tensor_tensor_formula,
  _transpose_formula,
  _norm_scalar_rhs,
  _norm_vector_rhs,
  _norm_tensor_rhs,
  _trace_tensor_rhs,
  _det_tensor_rhs,
  _fiberwise_pass!,
  _cross_values_ff, _cross_values_fc, _cross_values_cf,
  _tensor_vector_values_ff, _tensor_vector_values_fc, _tensor_vector_values_cf,
  _vector_tensor_values_ff, _vector_tensor_values_fc, _vector_tensor_values_cf,
  _tensor_tensor_values_ff, _tensor_tensor_values_fc, _tensor_tensor_values_cf,
  _transpose_values, _sym_values, _skew_values, _dev_values, _det_values,
  _scale_vector_values, _scale_tensor_values,
  _scale_fiber_vector_values, _scale_fiber_tensor_values,
  _divide_vector_values, _divide_tensor_values,
  _divide_fiber_vector_values, _divide_fiber_tensor_values,
  _MapValues, _section_order, _fiber_type, _fiber_order

using KernelAbstractions: get_backend


import Base: +, -, *, /, transpose, map, map!
import LinearAlgebra: dot, ⋅, cross, ×, mul!, transpose!, norm, tr, det


export add!,
       subtract!,
       combine!,
       multiply!,
       divide!,
       dot!,
       dot,
       ⋅,
       cross!,
       cross,
       ×,
       mul!,
       transpose!,
       norm!,
       norm,
       sym!,
       sym,
       skew!,
       skew,
       dev!,
       dev,
       tr!,
       tr,
       det!,
       det


#####################################################
#        Internal Field Data Utilities              #
#####################################################


"""
    _copy_field_data!(destination::AbstractField, field::AbstractField)

Copy `field`'s storage into `destination`'s storage unless they already alias; returns `destination`. Used by copy-then-kernel paths that must not assume the destination begins empty.
"""
function _copy_field_data!(destination::AbstractField, field::AbstractField)
  destination_data = field_data(destination)
  field_data_source = field_data(field)

  destination_data === field_data_source || copyto!(destination_data, field_data_source)

  return destination
end





"""
    _scalar_field_broadcast_data(scalar_field::ScalarFieldPhysical,
                                 field::AbstractFieldPhysical)

Reshape a scalar field's data with singleton fiber dimensions so it broadcasts against the fiber components of `field`. Used by pointwise scalar-field multiplication and division so the scalar acts on every component.
"""
function _scalar_field_broadcast_data(scalar_field::ScalarFieldPhysical, field::AbstractFieldPhysical)
  singleton_fiber_shape = ntuple(_ -> 1, field_tensor_order(field))
  return reshape(field_data(scalar_field), size(field_data(scalar_field))..., singleton_fiber_shape...)
end




#####################################################
#        Field Addition and Subtraction             #
#####################################################


"""
    add!(destination, a, b, fields...)
    add!(destination, field, constant)
    add!(destination, constant, field)

Add fields, or a field and a constant, in place, and return `destination`.

Use this in-place form when `destination` is already allocated; the allocating `+`
returns a fresh result instead.

The arguments are:
- `destination` — the field that receives the sum; it shares the domain and tensor order of the operands.
- `a`, `b`, `fields...` — two or more fields to add.
- `field`, `constant` — the field-and-constant variants, in either argument order: a `Real` with a scalar field, a `FiberVector` with a vector field, a `FiberTensor2` with a second-order tensor field.

Field-field addition is storage-wise and representation-preserving: it acts pointwise on fields in physical representation and coefficient-wise on fields in spectral representation.

In physical representation the constant is added at every grid point. In spectral representation only the zero Fourier coefficient changes, scaled by the number of grid points `prod(grid_size)`, so that the physical values shift by exactly the constant.
"""
function add! end


"""
    subtract!(destination, a, b, fields...)
    subtract!(destination, field, constant)
    subtract!(destination, constant, field)

Subtract fields, or a field and a constant, in place, and return `destination`.

Use this in-place form when `destination` is already allocated; the allocating `-`
returns a fresh result instead.

The arguments are:
- `destination` — the field that receives the difference.
- `a`, `b`, `fields...` — the fields to subtract in order.
- `field`, `constant` — the field-and-constant variants, with the constant typed as in [`add!`](@ref); the reversed order computes `constant - field`.

Field-field subtraction subtracts `b`, then each of `fields` in turn, from `a`; it is storage-wise and representation-preserving. In physical representation the constant is subtracted at every grid point; in spectral representation it changes only the zero Fourier coefficient. The reversed argument order computes `constant - field`.
"""
function subtract! end


# Zero-mode updates adding a real constant to a spectral scalar field.
function _add_scalar_constant!(field::ScalarFieldSpectral{T}, scalar::Real) where {T<:AbstractFloat}
  _spectral_zero_mode_data(field) .+= _spectral_constant_scale(field) * T(scalar)
  return field
end


function _subtract_scalar_constant!(field::ScalarFieldSpectral{T}, scalar::Real) where {T<:AbstractFloat}
  _spectral_zero_mode_data(field) .-= _spectral_constant_scale(field) * T(scalar)
  return field
end


# Constant-fiber update kernels. The update statement is written once per
# operation and stamped out for the three vector / nine tensor components.
# Physical-space methods update every grid point; spectral methods touch only
# the zero Fourier coefficient, scaled by the inverse-transform normalisation.
for (kernel, update) in (
    (:_add_fiber_vector!,      (target, value) -> :($target .+= $value)),
    (:_subtract_fiber_vector!, (target, value) -> :($target .-= $value)),
  )

  @eval function $kernel(field::VectorFieldPhysical{T}, a::FiberVector{T}) where {T<:AbstractFloat}
    $([update(:(_vector_component_data(field, $i)), :(a[$i])) for i in 1:3]...)
    return field
  end

  @eval function $kernel(field::VectorFieldSpectral{T}, a::FiberVector{T}) where {T<:AbstractFloat}
    scale = _spectral_constant_scale(field)
    $([update(:(_spectral_zero_mode_component_data(field, $i)), :(scale * a[$i])) for i in 1:3]...)
    return field
  end
end


for (kernel, update) in (
    (:_add_fiber_tensor2!,      (target, value) -> :($target .+= $value)),
    (:_subtract_fiber_tensor2!, (target, value) -> :($target .-= $value)),
  )

  @eval function $kernel(field::TensorFieldPhysical{2, T}, A::FiberTensor2{T}) where {T<:AbstractFloat}
    $([update(:(_tensor2_component_data(field, $i, $j)), :(A[$i, $j])) for i in 1:3 for j in 1:3]...)
    return field
  end

  @eval function $kernel(field::TensorFieldSpectral{2, T}, A::FiberTensor2{T}) where {T<:AbstractFloat}
    scale = _spectral_constant_scale(field)
    $([update(:(_spectral_zero_mode_component_data(field, $i, $j)), :(scale * A[$i, $j])) for i in 1:3 for j in 1:3]...)
    return field
  end
end


# Field-field combination and its operators: the bodies are identical for the
# two representations (the broadcast machinery enforces compatibility), so each
# operation contributes one row and the loop stamps out the representation variants.
for (bang, operator, reducer) in ((:add!, :+, :_add_values), (:subtract!, :-, :_subtract_values))
  for Representation in (:AbstractFieldPhysical, :AbstractFieldSpectral)

    @eval function $bang(destination::$Representation, a::$Representation, b::$Representation, fields::$Representation...)
      destination .= $reducer.(a, b, fields...)
      return destination
    end

    @eval function $operator(a::$Representation, b::$Representation, fields::$Representation...)
      return $reducer.(a, b, fields...)
    end
  end
end


"""
    +(a, b, fields...)

Allocating form of [`add!`](@ref): add fields or point-value collections — or a section and a
compatible constant — and return a new section. The unary `+` returns its section unchanged. See
`add!` for the componentwise definition and the representation-validity rules.
"""
+

"""
    -(a, b)

Allocating form of [`subtract!`](@ref): subtract fields or point-value collections (or negate one)
and return a new section. See `subtract!` for the componentwise definition and the
representation-validity rules.
"""
-

"""
    *(a, b)

Allocating form of [`multiply!`](@ref) and, for the tensor contractions, [`mul!`](@ref): a real scale,
a scalar-field action, or a fiber-constant contraction, returning a new section (fields and
point-value collections alike). See those for the componentwise definitions. There is deliberately no field-times-field method in spectral representation — that
coefficientwise product is a convolution and lives under `convolve`'s name, in the [`Convolution`](@ref "Convolution") module.
"""
*

"""
    /(a, b)

Allocating form of [`divide!`](@ref): divide a field or point-value collection by a real — or, in
physical representation only, by a scalar section — and return a new section. See `divide!` for the
componentwise definition.
"""
/

+(field::AbstractField) = field


function -(field::AbstractField)
  return (-).(field)
end


# Scalar field ± real number. Kept explicit: the physical-space methods are plain
# broadcasts, the spectral methods touch only the zero mode after copying, and
# the reversed subtraction is its own operation rather than a delegation.
function add!(destination::ScalarFieldPhysical, field::ScalarFieldPhysical, scalar::Real)
  destination .= field .+ scalar
  return destination
end


add!(destination::ScalarFieldPhysical, scalar::Real, field::ScalarFieldPhysical) = add!(destination, field, scalar)


function add!(destination::ScalarFieldSpectral, field::ScalarFieldSpectral, scalar::Real)
  check_field_compatibility(destination, field)
  _copy_field_data!(destination, field)
  return _add_scalar_constant!(destination, scalar)
end


add!(destination::ScalarFieldSpectral, scalar::Real, field::ScalarFieldSpectral) = add!(destination, field, scalar)


function subtract!(destination::ScalarFieldPhysical, field::ScalarFieldPhysical, scalar::Real)
  destination .= field .- scalar
  return destination
end


function subtract!(destination::ScalarFieldPhysical, scalar::Real, field::ScalarFieldPhysical)
  destination .= scalar .- field
  return destination
end


function subtract!(destination::ScalarFieldSpectral, field::ScalarFieldSpectral, scalar::Real)
  check_field_compatibility(destination, field)
  _copy_field_data!(destination, field)
  return _subtract_scalar_constant!(destination, scalar)
end


function subtract!(destination::ScalarFieldSpectral, scalar::Real, field::ScalarFieldSpectral)
  check_field_compatibility(destination, field)
  @_assign! field_data(destination) .= (-).(field_data(field))
  return _add_scalar_constant!(destination, scalar)
end


# Allocating operators for the scalar-constant variants.
for Scalar in (:ScalarFieldPhysical, :ScalarFieldSpectral)

  @eval function +(field::$Scalar, scalar::Real)
    destination = similar_field(field, similar(field_data(field)))
    return add!(destination, field, scalar)
  end

  @eval function +(scalar::Real, field::$Scalar)
    destination = similar_field(field, similar(field_data(field)))
    return add!(destination, scalar, field)
  end

  @eval function -(field::$Scalar, scalar::Real)
    destination = similar_field(field, similar(field_data(field)))
    return subtract!(destination, field, scalar)
  end

  @eval function -(scalar::Real, field::$Scalar)
    destination = similar_field(field, similar(field_data(field)))
    return subtract!(destination, scalar, field)
  end
end


# Field ± constant fiber: each table row stamps out the forward and reversed
# in-place methods and the four allocating operators for one field type.
for (FieldType, Constant, add_kernel, subtract_kernel) in (
    (:(VectorFieldPhysical{T}),    :(FiberVector{T}),  :_add_fiber_vector!,  :_subtract_fiber_vector!),
    (:(VectorFieldSpectral{T}),    :(FiberVector{T}),  :_add_fiber_vector!,  :_subtract_fiber_vector!),
    (:(TensorFieldPhysical{2, T}), :(FiberTensor2{T}), :_add_fiber_tensor2!, :_subtract_fiber_tensor2!),
    (:(TensorFieldSpectral{2, T}), :(FiberTensor2{T}), :_add_fiber_tensor2!, :_subtract_fiber_tensor2!),
  )

  @eval function add!(destination::$FieldType, field::$FieldType, constant::$Constant) where {T<:AbstractFloat}
    check_field_compatibility(destination, field)
    _copy_field_data!(destination, field)
    return $add_kernel(destination, constant)
  end

  @eval add!(destination::$FieldType, constant::$Constant, field::$FieldType) where {T<:AbstractFloat} =
    add!(destination, field, constant)

  @eval function subtract!(destination::$FieldType, field::$FieldType, constant::$Constant) where {T<:AbstractFloat}
    check_field_compatibility(destination, field)
    _copy_field_data!(destination, field)
    return $subtract_kernel(destination, constant)
  end

  @eval function subtract!(destination::$FieldType, constant::$Constant, field::$FieldType) where {T<:AbstractFloat}
    check_field_compatibility(destination, field)
    @_assign! field_data(destination) .= (-).(field_data(field))
    return $add_kernel(destination, constant)
  end

  @eval function +(field::$FieldType, constant::$Constant) where {T<:AbstractFloat}
    destination = similar_field(field, similar(field_data(field)))
    return add!(destination, field, constant)
  end

  @eval function +(constant::$Constant, field::$FieldType) where {T<:AbstractFloat}
    destination = similar_field(field, similar(field_data(field)))
    return add!(destination, constant, field)
  end

  @eval function -(field::$FieldType, constant::$Constant) where {T<:AbstractFloat}
    destination = similar_field(field, similar(field_data(field)))
    return subtract!(destination, field, constant)
  end

  @eval function -(constant::$Constant, field::$FieldType) where {T<:AbstractFloat}
    destination = similar_field(field, similar(field_data(field)))
    return subtract!(destination, constant, field)
  end
end


#####################################################
#        Weighted Field Combination                 #
#####################################################


"""
    combine!(destination, α::Real, a, β::Real, b)
    combine!(destination, α::Real, a, β::Real, b, kernel::SpectralKernel)

Overwrite `destination` with the real-weighted linear combination ``\\alpha a + \\beta b`` of two
compatible fields, and return `destination`.

!!! note "Here α and β weight the two inputs, not the destination"
    Every other in-place operation in the package uses trailing `α`, `β` that
    accumulate a result **onto** `destination`: ``\\alpha (\\mathrm{result}) + \\beta \\texttt{destination}``.
    This operation is the exception the name announces: it *is* the weighted combination, so its `α`
    and `β` sit between the operands they weight and there is no accumulate form — pass
    `b === destination` when you want one.

Reach for `combine!` with a preallocated destination when you need a real-weighted combination of two
fields in a single allocation-free pass. It fills the gap between [`add!`](@ref), which is unit-weight
(``a + b``), and [`multiply!`](@ref), which scales a single field; the allocating equivalent is the
operator expression ``\\alpha a + \\beta b``, which builds scratch fields instead. The combination is
linear and representation-preserving, so it is defined for both physical-space and spectral
representation.

The arguments are:
- `destination` — the field that receives the result; either input may alias it (see below).
- `α`, `a` — the real weight and the first field.
- `β`, `b` — the real weight and the second field.

The write is coefficientwise, so aliasing is safe without a guard temporary: `a`, `b`, or both may be `destination` itself.
In particular `combine!(u, 1, u, β, b)` computes the scaled accumulate ``u \\leftarrow u + \\beta b`` in
place.

```math
\\texttt{destination} = \\alpha  a + \\beta  b.
```

# The kernel-composed form

Passing a trailing `kernel` — a kernel's transfer function ``\\hat g``, in any storage class, exactly as `convolve!` takes
it — convolves the combination with the kernel in the same fused pass. As a real physical object the
result is the kernel-weighted local average of the combination, ``g \\star (\\alpha a + \\beta b)``;
in spectral representation it is one coefficientwise product,

```math
\\widehat{\\texttt{destination}}(k) = \\hat g(k)  \\bigl(\\alpha \\hat a(k) + \\beta \\hat b(k)\\bigr),
```

replacing a `combine!` followed by a `convolve!` — one pass instead of two, saving a full read and a
full write of `destination` per call. This form exists only in spectral representation (a kernel is a
spectral object); `α`/`β` keep their combination-weight roles, and with `b === destination` it
computes the kernel-filtered accumulate in place. The scalar kernel broadcasts over the fiber, so one
method serves every tensor order, and the write stays coefficientwise.

The additional argument is:
- `kernel` — the transfer function ``\\hat g``, in any of its storage classes, exactly as `convolve!`
  takes it. It may alias `destination`, as may `a` and `b`, the write being coefficientwise.
"""
function combine! end


# One method per representation; the body is the same fused broadcast (the broadcast machinery enforces
# compatibility). Coefficientwise ⇒ alias-safe with no guard, like `laplacian!`/`convolve!`. The real
# weights are converted to the field's scalar type `T`, keeping the broadcast in-type (invariant 10).
for Representation in (:AbstractFieldPhysical, :AbstractFieldSpectral)

  @eval function combine!(destination::$Representation, α::Real, a::$Representation, β::Real, b::$Representation)
    T = field_scalar_type(destination)
    destination .= T(α) .* a .+ T(β) .* b
    return destination
  end
end


#####################################################
#        Multiplication by Real Numbers             #
#####################################################


"""
    multiply!(destination, scalar::Real, field)
    multiply!(destination, field, scalar::Real)
    multiply!(destination, scalar_field::ScalarFieldPhysical, field)
    multiply!(destination, scalar_field, constant)

Multiply a field in place by a real number or by a scalar field, and return `destination`.

Use this in-place form when `destination` is already allocated; the allocating `*`
returns a fresh result instead.

The arguments are:
- `destination` — the field that receives the product.
- `scalar` — a `Real` factor, accepted in either argument order.
- `scalar_field` — a scalar field factor, multiplying the other operand pointwise.
- `field`, `constant` — the operand being scaled: a field of any tensor order, or a constant `FiberVector` or `FiberTensor2` paired with a scalar field.

Multiplication by a real number is representation-preserving and is defined for fields in both physical-space and spectral representation, in either argument order.

Multiplication by a scalar field is pointwise, so when the other factor is a field it is defined only in physical representation; in spectral representation the product of two fields is a convolution, which this module does not provide. The field-field result is not band-limited, so it aliases if transformed back to spectral representation; de-alias (`spectral_cutoff`) before spectral reuse. When the other factor is a constant `FiberVector` or `FiberTensor2`, the operation is linear in the scalar field and stays coefficient-wise, so it is defined in both representations and yields the corresponding vector or tensor field. Either argument order is accepted.
"""
function multiply! end


"""
    divide!(destination, field, scalar::Real)
    divide!(destination, field, scalar_field::ScalarFieldPhysical)
    divide!(destination, numerator, scalar_field::ScalarFieldPhysical)

Divide a field in place, and return `destination`.

Use this in-place form when `destination` is already allocated; the allocating `/`
returns a fresh result instead.

The arguments are:
- `destination` — the field that receives the quotient.
- `field`, `numerator` — the dividend: a field of any tensor order, a `Real`, or a constant `FiberVector` or `FiberTensor2`.
- `scalar` — a `Real` divisor.
- `scalar_field` — a scalar field divisor, dividing pointwise.

Division by a real number is representation-preserving and is defined in both representations. Division by a scalar field is pointwise and is defined only in physical representation; the numerator may be a field of any tensor order (the division acts on all of its components), a real number (yielding a scalar field), or a constant `FiberVector` or `FiberTensor2` (yielding the corresponding vector or tensor field). When the divisor is a scalar field the result is not band-limited, so it aliases if transformed back to spectral representation; de-alias (`spectral_cutoff`) before spectral reuse.
"""
function divide! end


# Scaling by a real number is the same broadcast in both representations.
for Representation in (:AbstractFieldPhysical, :AbstractFieldSpectral)

  @eval function multiply!(destination::$Representation, scalar::Real, field::$Representation)
    destination .= scalar .* field
    return destination
  end

  @eval function multiply!(destination::$Representation, field::$Representation, scalar::Real)
    destination .= field .* scalar
    return destination
  end

  @eval function divide!(destination::$Representation, field::$Representation, scalar::Real)
    destination .= field ./ scalar
    return destination
  end
end


function *(scalar::Real, field::AbstractField)
  destination = similar_field(field, similar(field_data(field)))
  return multiply!(destination, scalar, field)
end


function *(field::AbstractField, scalar::Real)
  destination = similar_field(field, similar(field_data(field)))
  return multiply!(destination, field, scalar)
end


function /(field::AbstractField, scalar::Real)
  destination = similar_field(field, similar(field_data(field)))
  return divide!(destination, field, scalar)
end


#####################################################
#        Multiplication by Scalar Fields            #
#####################################################


# Pointwise product of a scalar field with a field of any tensor order, acting
# on all components through a singleton-fiber broadcast view.
function _multiply_by_scalar_field!(destination::AbstractFieldPhysical, scalar_field::ScalarFieldPhysical, field::AbstractFieldPhysical)
  check_field_compatibility(destination, field)
  _check_field_domain_compatibility(scalar_field, field)

  # The fiber cases fuse so the scalar field is read once per element, not once per output
  # component; the scalar-by-scalar case is a single ideal broadcast already.
  order = field_tensor_order(field)
  one_value = one(section_scalar_type(destination))
  if order == 1
    _fiberwise_pass!(get_backend(field_data(destination)), _scale_vector_values,
                     ntuple(component -> _vector_component_data(destination, component), Val(3)),
                     (field_data(scalar_field), ntuple(component -> _vector_component_data(field, component), Val(3))...), (), one_value, zero(one_value))
  elseif order == 2
    _fiberwise_pass!(get_backend(field_data(destination)), _scale_tensor_values,
                     ntuple(n -> _tensor2_component_data(destination, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9)),
                     (field_data(scalar_field), ntuple(n -> _tensor2_component_data(field, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9))...), (), one_value, zero(one_value))
  else
    @_assign! field_data(destination) .= _scalar_field_broadcast_data(scalar_field, field) .* field_data(field)
  end
  return destination
end


# Scalar field × constant fiber and constant fiber ÷ scalar field: the kernels
# are emitted from their per-component formulas via the kernel-body builders.
# The multiplication kernels serve both representations, because the operation
# is linear in the scalar field and therefore stays coefficient-wise.
function _multiply_scalar_field_by_fiber_vector!(destination, scalar_field, a::FiberVector)
  _check_field_domain_compatibility(scalar_field, destination)
  one_value = one(section_scalar_type(destination))
  _fiberwise_pass!(get_backend(field_data(destination)), _scale_fiber_vector_values,
                   ntuple(component -> _vector_component_data(destination, component), Val(3)),
                   (field_data(scalar_field),), (a,), one_value, zero(one_value))
  return destination
end


function _multiply_scalar_field_by_fiber_tensor2!(destination, scalar_field, A::FiberTensor2)
  _check_field_domain_compatibility(scalar_field, destination)
  one_value = one(section_scalar_type(destination))
  _fiberwise_pass!(get_backend(field_data(destination)), _scale_fiber_tensor_values,
                   ntuple(n -> _tensor2_component_data(destination, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9)),
                   (field_data(scalar_field),), (A,), one_value, zero(one_value))
  return destination
end


function _divide_fiber_vector_by_scalar_field!(destination::VectorFieldPhysical, a::FiberVector, scalar_field::ScalarFieldPhysical)
  _check_field_domain_compatibility(scalar_field, destination)
  one_value = one(section_scalar_type(destination))
  _fiberwise_pass!(get_backend(field_data(destination)), _divide_fiber_vector_values,
                   ntuple(component -> _vector_component_data(destination, component), Val(3)),
                   (field_data(scalar_field),), (a,), one_value, zero(one_value))
  return destination
end


function _divide_fiber_tensor2_by_scalar_field!(destination::TensorFieldPhysical{2}, A::FiberTensor2, scalar_field::ScalarFieldPhysical)
  _check_field_domain_compatibility(scalar_field, destination)
  one_value = one(section_scalar_type(destination))
  _fiberwise_pass!(get_backend(field_data(destination)), _divide_fiber_tensor_values,
                   ntuple(n -> _tensor2_component_data(destination, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9)),
                   (field_data(scalar_field),), (A,), one_value, zero(one_value))
  return destination
end


# Scalar-field × field methods. Kept explicit: the four dispatch signatures
# exist to resolve ambiguities between the scalar-scalar and general cases.
multiply!(destination::AbstractFieldPhysical, scalar_field::ScalarFieldPhysical, field::AbstractFieldPhysical) = _multiply_by_scalar_field!(destination, scalar_field, field)

multiply!(destination::AbstractFieldPhysical, field::AbstractFieldPhysical, scalar_field::ScalarFieldPhysical) = _multiply_by_scalar_field!(destination, scalar_field, field)

multiply!(destination::ScalarFieldPhysical, a::ScalarFieldPhysical, b::ScalarFieldPhysical) = _multiply_by_scalar_field!(destination, a, b)

multiply!(destination::AbstractFieldPhysical, a::ScalarFieldPhysical, b::ScalarFieldPhysical) = _multiply_by_scalar_field!(destination, a, b)


# Scalar field × constant fiber: each row stamps out both argument orders of the
# in-place method and the two allocating operators, with the destination tensor
# order carried by the table.
for (Destination, Scalar, Constant, order, kernel) in (
    (:(VectorFieldPhysical{T}),    :(ScalarFieldPhysical{T}), :(FiberVector{T}),  1, :_multiply_scalar_field_by_fiber_vector!),
    (:(VectorFieldSpectral{T}),    :(ScalarFieldSpectral{T}), :(FiberVector{T}),  1, :_multiply_scalar_field_by_fiber_vector!),
    (:(TensorFieldPhysical{2, T}), :(ScalarFieldPhysical{T}), :(FiberTensor2{T}), 2, :_multiply_scalar_field_by_fiber_tensor2!),
    (:(TensorFieldSpectral{2, T}), :(ScalarFieldSpectral{T}), :(FiberTensor2{T}), 2, :_multiply_scalar_field_by_fiber_tensor2!),
  )

  @eval multiply!(destination::$Destination, scalar_field::$Scalar, constant::$Constant) where {T<:AbstractFloat} =
    $kernel(destination, scalar_field, constant)

  @eval multiply!(destination::$Destination, constant::$Constant, scalar_field::$Scalar) where {T<:AbstractFloat} =
    multiply!(destination, scalar_field, constant)

  @eval function *(scalar_field::$Scalar, constant::$Constant) where {T<:AbstractFloat}
    destination = similar_field(scalar_field, Val($order))
    return multiply!(destination, scalar_field, constant)
  end

  @eval function *(constant::$Constant, scalar_field::$Scalar) where {T<:AbstractFloat}
    destination = similar_field(scalar_field, Val($order))
    return multiply!(destination, constant, scalar_field)
  end
end


# Division by a scalar field (physical-space only).
divide!(destination::VectorFieldPhysical{T}, a::FiberVector{T}, scalar_field::ScalarFieldPhysical{T}) where {T<:AbstractFloat} =
  _divide_fiber_vector_by_scalar_field!(destination, a, scalar_field)

divide!(destination::TensorFieldPhysical{2, T}, A::FiberTensor2{T}, scalar_field::ScalarFieldPhysical{T}) where {T<:AbstractFloat} =
  _divide_fiber_tensor2_by_scalar_field!(destination, A, scalar_field)


function divide!(destination::AbstractFieldPhysical, field::AbstractFieldPhysical, scalar_field::ScalarFieldPhysical)
  check_field_compatibility(destination, field)
  _check_field_domain_compatibility(scalar_field, field)

  # The fiber cases fuse so the divisor is read once per element, not once per output component.
  order = field_tensor_order(field)
  one_value = one(section_scalar_type(destination))
  if order == 1
    _fiberwise_pass!(get_backend(field_data(destination)), _divide_vector_values,
                     ntuple(component -> _vector_component_data(destination, component), Val(3)),
                     (field_data(scalar_field), ntuple(component -> _vector_component_data(field, component), Val(3))...), (), one_value, zero(one_value))
  elseif order == 2
    _fiberwise_pass!(get_backend(field_data(destination)), _divide_tensor_values,
                     ntuple(n -> _tensor2_component_data(destination, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9)),
                     (field_data(scalar_field), ntuple(n -> _tensor2_component_data(field, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9))...), (), one_value, zero(one_value))
  else
    @_assign! field_data(destination) .= field_data(field) ./ _scalar_field_broadcast_data(scalar_field, field)
  end
  return destination
end


function divide!(destination::ScalarFieldPhysical, scalar::Real, scalar_field::ScalarFieldPhysical)
  destination .= scalar ./ scalar_field
  return destination
end


function *(scalar_field::ScalarFieldPhysical, field::AbstractFieldPhysical)
  destination = similar_field(field, similar(field_data(field)))
  return multiply!(destination, scalar_field, field)
end


function *(field::AbstractFieldPhysical, scalar_field::ScalarFieldPhysical)
  destination = similar_field(field, similar(field_data(field)))
  return multiply!(destination, field, scalar_field)
end


function *(a::ScalarFieldPhysical, b::ScalarFieldPhysical)
  destination = similar_field(a, similar(field_data(a)))
  return multiply!(destination, a, b)
end


function /(field::AbstractFieldPhysical, scalar_field::ScalarFieldPhysical)
  destination = similar_field(field, similar(field_data(field)))
  return divide!(destination, field, scalar_field)
end


function /(scalar::Real, scalar_field::ScalarFieldPhysical)
  destination = similar_field(scalar_field, similar(field_data(scalar_field)))
  return divide!(destination, scalar, scalar_field)
end


function /(a::FiberVector{T}, scalar_field::ScalarFieldPhysical{T}) where {T<:AbstractFloat}
  destination = similar_field(scalar_field, Val(1))
  return divide!(destination, a, scalar_field)
end


function /(A::FiberTensor2{T}, scalar_field::ScalarFieldPhysical{T}) where {T<:AbstractFloat}
  destination = similar_field(scalar_field, Val(2))
  return divide!(destination, A, scalar_field)
end


#####################################################
#        M3 contraction formula builders            #
#####################################################


const _VectorField = Union{VectorFieldPhysical, VectorFieldSpectral}
const _Tensor2Field = Union{TensorFieldPhysical{2}, TensorFieldSpectral{2}}


#####################################################
#        Vector and Tensor Dot Products             #
#####################################################


"""
    dot!(destination::ScalarFieldPhysical, u::VectorFieldPhysical,
         v::VectorFieldPhysical)
    dot!(destination::ScalarFieldPhysical, u::VectorFieldPhysical, a::FiberVector)
    dot!(destination::ScalarFieldSpectral, u::VectorFieldSpectral, a::FiberVector)
    dot!(destination::ScalarFieldPhysical, A::TensorFieldPhysical{2},
         B::TensorFieldPhysical{2})
    dot!(destination::ScalarFieldPhysical, A::TensorFieldPhysical{2}, B::FiberTensor2)
    dot!(destination::ScalarFieldSpectral, A::TensorFieldSpectral{2}, B::FiberTensor2)

Compute a fiberwise inner product in place, and return `destination`.

Use this in-place form when `destination` is already allocated; the allocating [`dot`](@ref)
returns a fresh result instead.

The arguments are:
- `destination` — the scalar field that receives the contraction.
- `u`, `v` — two vector fields, or `A`, `B` two second-order tensor fields.
- `a`, `B` — a constant `FiberVector` or `FiberTensor2` contracted against the field, in either argument order.

For two vector fields this is the Euclidean scalar product; for two second-order tensor fields it is the Frobenius double contraction. Either argument order is accepted.

Contraction of two fields is nonlinear and is defined only in physical representation. In spectral representation only contraction with a constant fiber vector or fiber tensor is provided, which keeps the operation coefficient-wise. The field-field result is not band-limited, so it aliases if transformed back to spectral representation; de-alias (`spectral_cutoff`) before spectral reuse.

Pointwise over the base, with summation over the repeated fiber indices:

```math
(u \\cdot v)(x) = u_i(x)  v_i(x), \\qquad (A : B)(x) = A_{ij}(x)  B_{ij}(x).
```
"""
function dot! end


"""
    dot(u::VectorFieldPhysical, v::VectorFieldPhysical)
    dot(A::TensorFieldPhysical{2}, B::TensorFieldPhysical{2})

Allocating form of [`dot!`](@ref) (`dot` ``\\equiv \\cdot``): allocate the scalar-field result and return it. For two vector fields this is their pointwise Euclidean product; for two second-order tensor fields, their pointwise Frobenius product. Two fields contract only in physical representation; with a constant fiber the contraction stays coefficient-wise and is available in both representations. The infix alias ``\\cdot`` (`⋅`) is also exported. See `dot!` for the componentwise formula.
"""
dot


# Inner-product kernels (scalar result, written through the scalar kernel body).
@eval _dot_components!(destination, u::_VectorField, v::_VectorField) =
  $(_scalar_kernel_body(_dot_vector_rhs(:u, :field, :v, :field)))

@eval _dot_components!(destination, u::_VectorField, a::FiberVector) =
  $(_scalar_kernel_body(_dot_vector_rhs(:u, :field, :a, :fiber)))

@eval _dot_components!(destination, A::_Tensor2Field, B::_Tensor2Field) =
  $(_scalar_kernel_body(_dot_tensor_rhs(:A, :field, :B, :field)))

@eval _dot_components!(destination, A::_Tensor2Field, B::FiberTensor2) =
  $(_scalar_kernel_body(_dot_tensor_rhs(:A, :field, :B, :fiber)))


# Field-field inner products (physical-space only).
function dot!(destination::ScalarFieldPhysical{T}, u::VectorFieldPhysical{T}, v::VectorFieldPhysical{T}) where {T<:AbstractFloat}
  check_field_compatibility(u, v)
  _check_field_domain_compatibility(destination, u)
  return _dot_components!(destination, u, v)
end

function dot!(destination::ScalarFieldPhysical{T}, A::TensorFieldPhysical{2, T}, B::TensorFieldPhysical{2, T}) where {T<:AbstractFloat}
  check_field_compatibility(A, B)
  _check_field_domain_compatibility(destination, A)
  return _dot_components!(destination, A, B)
end

function dot(u::VectorFieldPhysical{T}, v::VectorFieldPhysical{T}) where {T<:AbstractFloat}
  return dot!(similar_field(u, Val(0)), u, v)
end

function dot(A::TensorFieldPhysical{2, T}, B::TensorFieldPhysical{2, T}) where {T<:AbstractFloat}
  return dot!(similar_field(A, Val(0)), A, B)
end


# Field-fiber inner products (both representations; reversed order delegates,
# the contraction being commutative). One table row per (representation, rank).
for (ScalarField, OperandField, Constant) in (
    (:ScalarFieldPhysical, :VectorFieldPhysical,    :FiberVector),
    (:ScalarFieldSpectral, :VectorFieldSpectral,    :FiberVector),
    (:ScalarFieldPhysical, :(TensorFieldPhysical{2}), :FiberTensor2),
    (:ScalarFieldSpectral, :(TensorFieldSpectral{2}), :FiberTensor2),
  )

  @eval function dot!(destination::$ScalarField{T}, operand::$OperandField{T}, constant::$Constant{T}) where {T<:AbstractFloat}
    _check_field_domain_compatibility(destination, operand)
    return _dot_components!(destination, operand, constant)
  end

  @eval dot!(destination::$ScalarField{T}, constant::$Constant{T}, operand::$OperandField{T}) where {T<:AbstractFloat} =
    dot!(destination, operand, constant)

  @eval dot(operand::$OperandField{T}, constant::$Constant{T}) where {T<:AbstractFloat} =
    dot!(similar_field(operand, Val(0)), operand, constant)

  @eval dot(constant::$Constant{T}, operand::$OperandField{T}) where {T<:AbstractFloat} =
    dot!(similar_field(operand, Val(0)), operand, constant)
end


#####################################################
#        Vector Cross Products                      #
#####################################################


"""
    cross!(destination::VectorFieldPhysical, u::VectorFieldPhysical,
           v::VectorFieldPhysical)
    cross!(destination::VectorFieldPhysical, u::VectorFieldPhysical, a::FiberVector)
    cross!(destination::VectorFieldSpectral, u::VectorFieldSpectral, a::FiberVector)

Compute a fiberwise cross product (`cross` ``\\equiv \\times``) in place, and return `destination`.

Use this in-place form when `destination` is already allocated; the allocating [`cross`](@ref)
returns a fresh result instead.

The arguments are:
- `destination` — the vector field that receives the product.
- `u`, `v` — the two vector fields.
- `a` — a constant `FiberVector` crossed with the field. Both orders have methods, and being a cross
  product they differ in sign: ``a \\times u = -(u \\times a)``.

Cross products of two fields are nonlinear and are defined only in physical representation. In spectral representation only the cross product with a constant fiber vector (in either argument order) is provided, which keeps the operation coefficient-wise. The field-field result is not band-limited, so it aliases if transformed back to spectral representation; de-alias (`spectral_cutoff`) before spectral reuse.

Pointwise over the base, with the Levi-Civita symbol ``\\varepsilon_{ijk}`` (summed over the repeated ``j, k``), the components are

```math
\\begin{gathered}
(u \\times v)_i = \\varepsilon_{ijk}  u_j v_k, \\\\
(u \\times v)_1 = u_2 v_3 - u_3 v_2, \\quad
(u \\times v)_2 = u_3 v_1 - u_1 v_3, \\quad
(u \\times v)_3 = u_1 v_2 - u_2 v_1.
\\end{gathered}
```
"""
function cross! end


"""
    cross(u::VectorFieldPhysical, v::VectorFieldPhysical)

Allocating form of [`cross!`](@ref) (`cross` ``\\equiv \\times``): allocate the vector-field result ``u \\times v`` and return it. Two vector fields cross only in physical representation; with a constant fiber vector the operation stays coefficient-wise and is available in both representations. The infix alias ``\\times`` (`×`) is also exported. See `cross!` for the componentwise formula.
"""
cross


# Cross-product kernels (vector result), fused: each element's source components are read into
# registers before any output is written, so the pass is alias-safe by construction and the
# former `_guard_noalias!` wrap is retired.
function _cross_components!(destination, u::_VectorField, v::_VectorField)
  one_value = one(section_scalar_type(destination))
  _fiberwise_pass!(get_backend(field_data(destination)), _cross_values_ff,
                   ntuple(component -> _vector_component_data(destination, component), Val(3)),
                   (ntuple(component -> _vector_component_data(u, component), Val(3))..., ntuple(component -> _vector_component_data(v, component), Val(3))...), (), one_value, zero(one_value))
  return destination
end

function _cross_components!(destination, u::_VectorField, a::FiberVector)
  one_value = one(section_scalar_type(destination))
  _fiberwise_pass!(get_backend(field_data(destination)), _cross_values_fc,
                   ntuple(component -> _vector_component_data(destination, component), Val(3)),
                   ntuple(component -> _vector_component_data(u, component), Val(3)), (a,), one_value, zero(one_value))
  return destination
end

function _cross_components!(destination, a::FiberVector, u::_VectorField)
  one_value = one(section_scalar_type(destination))
  _fiberwise_pass!(get_backend(field_data(destination)), _cross_values_cf,
                   ntuple(component -> _vector_component_data(destination, component), Val(3)),
                   ntuple(component -> _vector_component_data(u, component), Val(3)), (a,), one_value, zero(one_value))
  return destination
end


function cross!(destination::VectorFieldPhysical{T}, u::VectorFieldPhysical{T}, v::VectorFieldPhysical{T}) where {T<:AbstractFloat}
  check_field_compatibility(u, v)
  check_field_compatibility(destination, u)
  return _cross_components!(destination, u, v)
end

function cross(u::VectorFieldPhysical{T}, v::VectorFieldPhysical{T}) where {T<:AbstractFloat}
  return cross!(similar_field(u, Val(1)), u, v)
end

# Cross with a constant fiber vector (both representations, both argument orders).
for (VectorField,) in ((:VectorFieldPhysical,), (:VectorFieldSpectral,))

  @eval function cross!(destination::$VectorField{T}, u::$VectorField{T}, a::FiberVector{T}) where {T<:AbstractFloat}
    check_field_compatibility(destination, u)
    return _cross_components!(destination, u, a)
  end

  @eval function cross!(destination::$VectorField{T}, a::FiberVector{T}, u::$VectorField{T}) where {T<:AbstractFloat}
    check_field_compatibility(destination, u)
    return _cross_components!(destination, a, u)
  end

  @eval cross(u::$VectorField{T}, a::FiberVector{T}) where {T<:AbstractFloat} = cross!(similar_field(u, Val(1)), u, a)

  @eval cross(a::FiberVector{T}, u::$VectorField{T}) where {T<:AbstractFloat} = cross!(similar_field(u, Val(1)), a, u)
end


#####################################################
#        Tensor-Vector and Tensor-Tensor Products   #
#####################################################


"""
    mul!(destination::VectorFieldPhysical, A::TensorFieldPhysical{2},
         u::VectorFieldPhysical[, α, β])
    mul!(destination::VectorFieldPhysical, A::TensorFieldPhysical{2},
         a::FiberVector[, α, β])
    mul!(destination::VectorFieldSpectral, A::FiberTensor2,
         u::VectorFieldSpectral[, α, β])
    mul!(destination::TensorFieldPhysical{2}, A::TensorFieldPhysical{2},
         B::TensorFieldPhysical{2}[, α, β])
    mul!(destination::TensorFieldPhysical{2}, A::TensorFieldPhysical{2},
         B::FiberTensor2[, α, β])
    mul!(destination::VectorFieldPhysical, u::VectorFieldPhysical,
         A::TensorFieldPhysical{2}[, α, β])
    mul!(destination::VectorFieldPhysical, a::FiberVector,
         A::TensorFieldPhysical{2}[, α, β])

Compute a fiberwise tensor (matrix) product in place, and return `destination`. The three-argument forms compute the tensor-on-vector left and right action, or the tensor-on-tensor product; the five-argument form scales and accumulates as ``\\texttt{destination} = \\alpha (A B) + \\beta \\texttt{destination}``.

Use this in-place form when `destination` is already allocated; the allocating `*`
returns a fresh result instead.

The arguments are:
- `destination` — the field written with the product. It must **not** share storage with either
  operand, and that is not checked: `mul!` keeps `LinearAlgebra`'s contrary contract, where every
  other in-place operation here is alias-safe by construction.
- the two operands — given in the order they multiply, so the signatures above cover both the **left**
  action ``(A u)_i = A_{ij} u_j`` and the **right** action ``(u A)_i = u_j A_{ji}``. Each may be a field
  or a fiber constant: a second-order tensor field or a `FiberTensor2`, a vector field or a
  `FiberVector`. At least one must be a field, since a product of two constants is not a field
  operation.
- `α`, `β` — real accumulation weights, converted to the field's scalar type. The three-argument forms
  overwrite (``\\alpha = 1``, ``\\beta = 0``); the five-argument forms compute
  ``\\alpha (A B) + \\beta \\texttt{destination}``, so ``\\beta = 0`` overwrites and any other value
  accumulates — the `LinearAlgebra.mul!` convention.

A product of two fields is nonlinear and is defined only in physical representation; a spectral-representation product requires one factor to be a constant fiber tensor or fiber vector. The field-field result is not band-limited, so it aliases if transformed back to spectral representation; de-alias (`spectral_cutoff`) before spectral reuse.

Pointwise over the base, with summation over the repeated fiber indices:

```math
(A u)_i = A_{ij} u_j, \\qquad (u A)_i = u_j A_{ji}, \\qquad (A B)_{ij} = A_{ik} B_{kj}.
```
"""
mul!


# Tensor-vector kernels (vector result, α/β accumulation). Destination must not alias:
# mul! documents that the destination must not alias the inputs.
function _tensor_vector_components!(destination, A::_Tensor2Field, u::_VectorField, α_value, β_value)
  _fiberwise_pass!(get_backend(field_data(destination)), _tensor_vector_values_ff,
                   ntuple(component -> _vector_component_data(destination, component), Val(3)),
                   (ntuple(n -> _tensor2_component_data(A, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9))..., ntuple(component -> _vector_component_data(u, component), Val(3))...), (), α_value, β_value)
  return destination
end

function _tensor_vector_components!(destination, A::_Tensor2Field, a::FiberVector, α_value, β_value)
  _fiberwise_pass!(get_backend(field_data(destination)), _tensor_vector_values_fc,
                   ntuple(component -> _vector_component_data(destination, component), Val(3)),
                   ntuple(n -> _tensor2_component_data(A, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9)), (a,), α_value, β_value)
  return destination
end

function _tensor_vector_components!(destination, A::FiberTensor2, u::_VectorField, α_value, β_value)
  _fiberwise_pass!(get_backend(field_data(destination)), _tensor_vector_values_cf,
                   ntuple(component -> _vector_component_data(destination, component), Val(3)),
                   ntuple(component -> _vector_component_data(u, component), Val(3)), (A,), α_value, β_value)
  return destination
end

function _vector_tensor_components!(destination, u::_VectorField, A::_Tensor2Field, α_value, β_value)
  _fiberwise_pass!(get_backend(field_data(destination)), _vector_tensor_values_ff,
                   ntuple(component -> _vector_component_data(destination, component), Val(3)),
                   (ntuple(component -> _vector_component_data(u, component), Val(3))..., ntuple(n -> _tensor2_component_data(A, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9))...), (), α_value, β_value)
  return destination
end

function _vector_tensor_components!(destination, a::FiberVector, A::_Tensor2Field, α_value, β_value)
  _fiberwise_pass!(get_backend(field_data(destination)), _vector_tensor_values_cf,
                   ntuple(component -> _vector_component_data(destination, component), Val(3)),
                   ntuple(n -> _tensor2_component_data(A, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9)), (a,), α_value, β_value)
  return destination
end

function _vector_tensor_components!(destination, u::_VectorField, A::FiberTensor2, α_value, β_value)
  _fiberwise_pass!(get_backend(field_data(destination)), _vector_tensor_values_fc,
                   ntuple(component -> _vector_component_data(destination, component), Val(3)),
                   ntuple(component -> _vector_component_data(u, component), Val(3)), (A,), α_value, β_value)
  return destination
end


# Tensor-tensor kernels (tensor result, α/β accumulation), fused like the tensor-vector family.
function _tensor_tensor_components!(destination, A::_Tensor2Field, B::_Tensor2Field, α_value, β_value)
  _fiberwise_pass!(get_backend(field_data(destination)), _tensor_tensor_values_ff,
                   ntuple(n -> _tensor2_component_data(destination, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9)),
                   (ntuple(n -> _tensor2_component_data(A, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9))..., ntuple(n -> _tensor2_component_data(B, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9))...), (), α_value, β_value)
  return destination
end

function _tensor_tensor_components!(destination, A::_Tensor2Field, B::FiberTensor2, α_value, β_value)
  _fiberwise_pass!(get_backend(field_data(destination)), _tensor_tensor_values_fc,
                   ntuple(n -> _tensor2_component_data(destination, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9)),
                   ntuple(n -> _tensor2_component_data(A, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9)), (B,), α_value, β_value)
  return destination
end

function _tensor_tensor_components!(destination, A::FiberTensor2, B::_Tensor2Field, α_value, β_value)
  _fiberwise_pass!(get_backend(field_data(destination)), _tensor_tensor_values_cf,
                   ntuple(n -> _tensor2_component_data(destination, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9)),
                   ntuple(n -> _tensor2_component_data(B, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9)), (A,), α_value, β_value)
  return destination
end


# --- Tensor-vector mul! (five-argument forms) ---

# Field-field (physical-space only): left action A·u and right action u·A.
function mul!(destination::VectorFieldPhysical{T}, A::TensorFieldPhysical{2, T}, u::VectorFieldPhysical{T}, α::Real, β::Real) where {T<:AbstractFloat}
  check_field_compatibility(destination, u)
  _check_field_domain_compatibility(A, u)
  return _tensor_vector_components!(destination, A, u, T(α), T(β))
end

function mul!(destination::VectorFieldPhysical{T}, u::VectorFieldPhysical{T}, A::TensorFieldPhysical{2, T}, α::Real, β::Real) where {T<:AbstractFloat}
  check_field_compatibility(destination, u)
  _check_field_domain_compatibility(A, u)
  return _vector_tensor_components!(destination, u, A, T(α), T(β))
end

# Tensor field × constant fiber vector, and constant fiber tensor × vector field
# (both representations). One table row per (representation).
for (VectorField, Tensor2Field) in (
    (:VectorFieldPhysical, :(TensorFieldPhysical{2})),
    (:VectorFieldSpectral, :(TensorFieldSpectral{2})),
  )

  @eval function mul!(destination::$VectorField{T}, A::$Tensor2Field{T}, a::FiberVector{T}, α::Real, β::Real) where {T<:AbstractFloat}
    _check_field_domain_compatibility(A, destination)
    return _tensor_vector_components!(destination, A, a, T(α), T(β))
  end

  @eval function mul!(destination::$VectorField{T}, a::FiberVector{T}, A::$Tensor2Field{T}, α::Real, β::Real) where {T<:AbstractFloat}
    _check_field_domain_compatibility(A, destination)
    return _vector_tensor_components!(destination, a, A, T(α), T(β))
  end

  @eval function mul!(destination::$VectorField{T}, A::FiberTensor2{T}, u::$VectorField{T}, α::Real, β::Real) where {T<:AbstractFloat}
    check_field_compatibility(destination, u)
    return _tensor_vector_components!(destination, A, u, T(α), T(β))
  end

  @eval function mul!(destination::$VectorField{T}, u::$VectorField{T}, A::FiberTensor2{T}, α::Real, β::Real) where {T<:AbstractFloat}
    check_field_compatibility(destination, u)
    return _vector_tensor_components!(destination, u, A, T(α), T(β))
  end
end


# --- Tensor-tensor mul! (five-argument forms) ---

function mul!(destination::TensorFieldPhysical{2, T}, A::TensorFieldPhysical{2, T}, B::TensorFieldPhysical{2, T}, α::Real, β::Real) where {T<:AbstractFloat}
  check_field_compatibility(destination, A)
  check_field_compatibility(A, B)
  return _tensor_tensor_components!(destination, A, B, T(α), T(β))
end

for (Tensor2Field,) in ((:(TensorFieldPhysical{2}),), (:(TensorFieldSpectral{2}),))

  @eval function mul!(destination::$Tensor2Field{T}, A::$Tensor2Field{T}, B::FiberTensor2{T}, α::Real, β::Real) where {T<:AbstractFloat}
    check_field_compatibility(destination, A)
    return _tensor_tensor_components!(destination, A, B, T(α), T(β))
  end

  @eval function mul!(destination::$Tensor2Field{T}, A::FiberTensor2{T}, B::$Tensor2Field{T}, α::Real, β::Real) where {T<:AbstractFloat}
    check_field_compatibility(destination, B)
    return _tensor_tensor_components!(destination, A, B, T(α), T(β))
  end
end


# --- Three-argument mul! forms delegate with α = 1, β = 0 ---
for (Destination, First, Second) in (
    (:(VectorFieldPhysical{T}),    :(TensorFieldPhysical{2, T}), :(VectorFieldPhysical{T})),
    (:(VectorFieldPhysical{T}),    :(VectorFieldPhysical{T}),    :(TensorFieldPhysical{2, T})),
    (:(VectorFieldPhysical{T}),    :(TensorFieldPhysical{2, T}), :(FiberVector{T})),
    (:(VectorFieldPhysical{T}),    :(FiberVector{T}),            :(TensorFieldPhysical{2, T})),
    (:(VectorFieldPhysical{T}),    :(FiberTensor2{T}),           :(VectorFieldPhysical{T})),
    (:(VectorFieldPhysical{T}),    :(VectorFieldPhysical{T}),    :(FiberTensor2{T})),
    (:(VectorFieldSpectral{T}),    :(TensorFieldSpectral{2, T}), :(FiberVector{T})),
    (:(VectorFieldSpectral{T}),    :(FiberVector{T}),            :(TensorFieldSpectral{2, T})),
    (:(VectorFieldSpectral{T}),    :(FiberTensor2{T}),           :(VectorFieldSpectral{T})),
    (:(VectorFieldSpectral{T}),    :(VectorFieldSpectral{T}),    :(FiberTensor2{T})),
    (:(TensorFieldPhysical{2, T}), :(TensorFieldPhysical{2, T}), :(TensorFieldPhysical{2, T})),
    (:(TensorFieldPhysical{2, T}), :(TensorFieldPhysical{2, T}), :(FiberTensor2{T})),
    (:(TensorFieldPhysical{2, T}), :(FiberTensor2{T}),           :(TensorFieldPhysical{2, T})),
    (:(TensorFieldSpectral{2, T}), :(TensorFieldSpectral{2, T}), :(FiberTensor2{T})),
    (:(TensorFieldSpectral{2, T}), :(FiberTensor2{T}),           :(TensorFieldSpectral{2, T})),
  )

  @eval mul!(destination::$Destination, first::$First, second::$Second) where {T<:AbstractFloat} =
    mul!(destination, first, second, one(T), zero(T))
end


# --- Allocating `*` operators delegate to the three-argument mul! ---

# Tensor-vector: the destination is a vector field built on the vector operand
# (when present) or on the tensor field's grid.
for (TensorField,) in ((:(TensorFieldPhysical{2}),), (:(TensorFieldSpectral{2}),))

  @eval *(A::$TensorField{T}, a::FiberVector{T}) where {T<:AbstractFloat} = mul!(similar_field(A, Val(1)), A, a)
  @eval *(a::FiberVector{T}, A::$TensorField{T}) where {T<:AbstractFloat} = mul!(similar_field(A, Val(1)), a, A)
end

for (VectorField,) in ((:VectorFieldPhysical,), (:VectorFieldSpectral,))

  @eval *(A::FiberTensor2{T}, u::$VectorField{T}) where {T<:AbstractFloat} = mul!(similar_field(u, similar(field_data(u))), A, u)
  @eval *(u::$VectorField{T}, A::FiberTensor2{T}) where {T<:AbstractFloat} = mul!(similar_field(u, similar(field_data(u))), u, A)
end

*(A::TensorFieldPhysical{2, T}, u::VectorFieldPhysical{T}) where {T<:AbstractFloat} = mul!(similar_field(u, similar(field_data(u))), A, u)
*(u::VectorFieldPhysical{T}, A::TensorFieldPhysical{2, T}) where {T<:AbstractFloat} = mul!(similar_field(u, similar(field_data(u))), u, A)

# Tensor-tensor: the destination is a tensor field built on whichever operand is a field.
*(A::TensorFieldPhysical{2, T}, B::TensorFieldPhysical{2, T}) where {T<:AbstractFloat} = mul!(similar_field(A, Val(2)), A, B)

for (Tensor2Field,) in ((:(TensorFieldPhysical{2}),), (:(TensorFieldSpectral{2}),))

  @eval *(A::$Tensor2Field{T}, B::FiberTensor2{T}) where {T<:AbstractFloat} = mul!(similar_field(A, Val(2)), A, B)
  @eval *(A::FiberTensor2{T}, B::$Tensor2Field{T}) where {T<:AbstractFloat} = mul!(similar_field(B, Val(2)), A, B)
end


#####################################################
#        Tensor Index Permutations                  #
#####################################################


"""
    transpose!(destination::TensorFieldPhysical{2}, A::TensorFieldPhysical{2})
    transpose!(destination::TensorFieldSpectral{2}, A::TensorFieldSpectral{2})

Transpose the fiber indices of a second-order tensor field in place (`transpose` ``\\equiv (\\cdot)^\\top``), and return `destination`.

Use this in-place form when `destination` is already allocated; the allocating [`transpose`](@ref)
returns a fresh result instead.

The operation is linear and representation-preserving, so it is defined for both physical-space and spectral representations. Unlike Julia's matrix `transpose`, it writes a materialized tensor field rather than a lazy wrapper.

Pointwise over the base:

```math
\\texttt{destination}_{ij} = A_{ji}.
```
"""
transpose!


# Fused: each element's nine components are read into registers before any output is written,
# so the in-place transpose needs no guard temporary and may alias freely.
function _transpose_components!(destination, A)
  one_value = one(section_scalar_type(destination))
  _fiberwise_pass!(get_backend(field_data(destination)), _transpose_values,
                   ntuple(n -> _tensor2_component_data(destination, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9)),
                   ntuple(n -> _tensor2_component_data(A, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9)), (), one_value, zero(one_value))
  return destination
end


"""
    transpose(A)

Allocating form of [`transpose!`](@ref): allocate the result and return the transpose
``A^\\top`` of a second-order tensor field, in either representation. See `transpose!` for the
componentwise definition.
"""
transpose


for (Tensor2Field,) in ((:(TensorFieldPhysical{2}),), (:(TensorFieldSpectral{2}),))

  @eval function transpose!(destination::$Tensor2Field{T}, A::$Tensor2Field{T}) where {T<:AbstractFloat}
    check_field_compatibility(destination, A)
    return _transpose_components!(destination, A)
  end

  @eval transpose(A::$Tensor2Field{T}) where {T<:AbstractFloat} = transpose!(similar_field(A, Val(2)), A)
end


#####################################################
#        Field Norms                                #
#####################################################


"""
    norm!(destination::ScalarFieldPhysical, scalar_field::ScalarFieldPhysical)
    norm!(destination::ScalarFieldPhysical, u::VectorFieldPhysical)
    norm!(destination::ScalarFieldPhysical, A::TensorFieldPhysical{2})

Compute the fiberwise norm of a physical-space field (`norm` ``\\equiv |\\cdot|``) in place, and return `destination`.

Use this in-place form when `destination` is already allocated; the allocating [`norm`](@ref)
returns a fresh result instead.

The norm is nonlinear, so it is defined only in physical representation. Its result is not band-limited, so it aliases if transformed back to spectral representation; de-alias (`spectral_cutoff`) before spectral reuse.

Pointwise over the base — the absolute value for a scalar field, the Euclidean norm for a vector field, and the Frobenius norm (not the operator norm) for a second-order tensor field:

```math
|\\varphi|, \\qquad |u| = \\sqrt{u_i u_i}, \\qquad |A| = \\sqrt{A_{ij} A_{ij}}.
```
"""
function norm! end


"""
    norm(scalar_field::ScalarFieldPhysical)
    norm(u::VectorFieldPhysical)
    norm(A::TensorFieldPhysical{2})

Allocating form of [`norm!`](@ref) (`norm` ``\\equiv |\\cdot|``): allocate the scalar-field result and return it — the pointwise fiber magnitude of a scalar, vector, or second-order tensor field. Physical-space representation only. See `norm!` for the componentwise formula.
"""
norm


@eval _norm_components!(destination, scalar_field::ScalarFieldPhysical) =
  $(_scalar_kernel_body(_norm_scalar_rhs(:scalar_field)))

@eval _norm_components!(destination, u::VectorFieldPhysical) =
  $(_scalar_kernel_body(_norm_vector_rhs(:u, :field)))

@eval _norm_components!(destination, A::TensorFieldPhysical{2}) =
  $(_scalar_kernel_body(_norm_tensor_rhs(:A, :field)))


for (Operand,) in ((:ScalarFieldPhysical,), (:VectorFieldPhysical,), (:(TensorFieldPhysical{2}),))

  @eval function norm!(destination::ScalarFieldPhysical{T}, operand::$Operand{T}) where {T<:AbstractFloat}
    _check_field_domain_compatibility(destination, operand)
    return _norm_components!(destination, operand)
  end

  @eval norm(operand::$Operand{T}) where {T<:AbstractFloat} = norm!(similar_field(operand, Val(0)), operand)
end


#####################################################
#        Tensor Trace                               #
#####################################################


"""
    tr!(destination::ScalarFieldPhysical, A::TensorFieldPhysical{2})
    tr!(destination::ScalarFieldSpectral, A::TensorFieldSpectral{2})

Compute the fiberwise trace (`tr` ``\\equiv \\operatorname{tr}``) of the second-order tensor field `A`
in place, writing it into `destination`, which is returned. The trace is linear and representation-preserving, so it is defined for both representations.

Use this in-place form when `destination` is already allocated; the allocating [`tr`](@ref)
returns a fresh result instead.

Pointwise over the base, it contracts the two fiber indices to a scalar — the first tensor invariant:

```math
\\operatorname{tr}(A) = A_{ii} = A_{11} + A_{22} + A_{33}.
```
"""
function tr! end


"""
    tr(A::TensorFieldPhysical{2})
    tr(A::TensorFieldSpectral{2})

Allocating form of [`tr!`](@ref): allocate the scalar-field result and return the fiberwise trace — the first principal invariant ``I_1`` — of a second-order tensor field. See [`tr!`](@ref) for the componentwise definition and the physical/spectral validity. (A single `FiberTensor2` value already has `LinearAlgebra.tr`.)
"""
tr


@eval _trace_components!(destination, A::_Tensor2Field) = $(_scalar_kernel_body(_trace_tensor_rhs(:A, :field)))


for (Tensor2Field, ScalarField) in (
    (:(TensorFieldPhysical{2}), :ScalarFieldPhysical),
    (:(TensorFieldSpectral{2}), :ScalarFieldSpectral),
  )

  @eval function tr!(destination::$ScalarField{T}, A::$Tensor2Field{T}) where {T<:AbstractFloat}
    _check_field_domain_compatibility(destination, A)
    return _trace_components!(destination, A)
  end

  @eval tr(A::$Tensor2Field{T}) where {T<:AbstractFloat} = tr!(similar_field(A, Val(0)), A)
end


#####################################################
#        Tensor Determinant                         #
#####################################################


"""
    det!(destination::ScalarFieldPhysical, A::TensorFieldPhysical{2})

Compute the fiberwise determinant (`det` ``\\equiv \\det``) of a second-order tensor field in place, and
return `destination`.

Use this in-place form when `destination` is already allocated; the allocating [`det`](@ref)
returns a fresh result instead.

The determinant is cubic in the tensor's components — the third principal invariant ``I_3``, the signed
factor by which ``A`` scales volumes as a linear map. Unlike the linear trace [`tr!`](@ref), it is
nonlinear, so it is defined in physical representation only; there is no spectral form. Its result is not band-limited, so it aliases if transformed back to spectral representation; de-alias (`spectral_cutoff`) before spectral reuse.

Pointwise over the base, with the Levi-Civita symbol ``\\varepsilon_{ijk}`` (summed over the repeated
fiber indices):

```math
\\det(A) = \\varepsilon_{ijk}  A_{1i}  A_{2j}  A_{3k}.
```
"""
function det! end


"""
    det(A::TensorFieldPhysical{2})

Allocating form of [`det!`](@ref): allocate the scalar-field result and return the fiberwise determinant
— the third principal invariant ``I_3`` — of a second-order tensor field. Physical-space representation
only. See [`det!`](@ref) for the componentwise formula. (A single `FiberTensor2` value already has
`LinearAlgebra.det`.)
"""
det


function _det_components!(destination, A::TensorFieldPhysical{2})
  one_value = one(section_scalar_type(destination))
  _fiberwise_pass!(get_backend(field_data(destination)), _det_values,
                   (field_data(destination),),
                   ntuple(n -> _tensor2_component_data(A, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9)), (), one_value, zero(one_value))
  return destination
end


function det!(destination::ScalarFieldPhysical{T}, A::TensorFieldPhysical{2, T}) where {T<:AbstractFloat}
  _check_field_domain_compatibility(destination, A)
  return _det_components!(destination, A)
end


det(A::TensorFieldPhysical{2, T}) where {T<:AbstractFloat} = det!(similar_field(A, Val(0)), A)


#####################################################
#        Tensor Decompositions                      #
#####################################################


"""
    sym!(destination::TensorFieldPhysical{2}, A::TensorFieldPhysical{2})
    sym!(destination::TensorFieldSpectral{2}, A::TensorFieldSpectral{2})

Compute the symmetric part of the second-order tensor field `A` in place, writing it into
`destination`, which is returned. The operation is linear and representation-preserving, so it is defined for both representations.

Use this in-place form when `destination` is already allocated; the allocating [`sym`](@ref)
returns a fresh result instead.

Pointwise over the base:

```math
\\operatorname{sym}(A) = \\tfrac{1}{2} (A + A^\\top).
```
"""
function sym! end


"""
    sym(A::TensorFieldPhysical{2})
    sym(A::TensorFieldSpectral{2})
    sym(A::FiberTensor2)

Allocating form of [`sym!`](@ref): allocate the result and return the symmetric part of a second-order tensor: fiberwise for a tensor field, or directly on a single `FiberTensor2` value. See [`sym!`](@ref) for the defining formula and the physical/spectral validity.
"""
function sym end


"""
    skew!(destination::TensorFieldPhysical{2}, A::TensorFieldPhysical{2})
    skew!(destination::TensorFieldSpectral{2}, A::TensorFieldSpectral{2})

Compute the skew-symmetric part of the second-order tensor field `A` in place, writing it into
`destination`, which is returned. The operation is linear and representation-preserving, so it is defined for both representations.

Use this in-place form when `destination` is already allocated; the allocating [`skew`](@ref)
returns a fresh result instead.

Pointwise over the base:

```math
\\operatorname{skew}(A) = \\tfrac{1}{2} (A - A^\\top).
```
"""
function skew! end


"""
    skew(A::TensorFieldPhysical{2})
    skew(A::TensorFieldSpectral{2})
    skew(A::FiberTensor2)

Allocating form of [`skew!`](@ref): allocate the result and return the skew-symmetric part of a second-order tensor: fiberwise for a tensor field, or directly on a single `FiberTensor2` value. See [`skew!`](@ref) for the defining formula and the physical/spectral validity.
"""
function skew end


"""
    dev!(destination::TensorFieldPhysical{2}, A::TensorFieldPhysical{2})
    dev!(destination::TensorFieldSpectral{2}, A::TensorFieldSpectral{2})

Compute the deviatoric (trace-free) part of the second-order tensor field `A` in place, writing it
into `destination`, which is returned. The operation is linear and representation-preserving, so it is defined for both representations.

Use this in-place form when `destination` is already allocated; the allocating [`dev`](@ref)
returns a fresh result instead.

Pointwise over the base, with ``I`` the identity tensor:

```math
\\operatorname{dev}(A) = A - \\tfrac{1}{3} \\operatorname{tr}(A) I.
```
"""
function dev! end


"""
    dev(A::TensorFieldPhysical{2})
    dev(A::TensorFieldSpectral{2})
    dev(A::FiberTensor2)

Allocating form of [`dev!`](@ref): allocate the result and return the deviatoric part of a second-order tensor: fiberwise for a tensor field, or directly on a single `FiberTensor2` value. See [`dev!`](@ref) for the defining formula and the physical/spectral validity.
"""
function dev end


# Decomposition kernels — the values functions in FiberSections carry the shared formulas (the
# same source the point algebra uses, so each is written once). Fused: an element's nine
# components are read into registers before any output is written, so the former guard wrap is
# retired, and `dev!` no longer materializes its trace field (the trace is computed per element).
function _sym_components!(destination, A)
  one_value = one(section_scalar_type(destination))
  _fiberwise_pass!(get_backend(field_data(destination)), _sym_values,
                   ntuple(n -> _tensor2_component_data(destination, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9)),
                   ntuple(n -> _tensor2_component_data(A, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9)), (), one_value, zero(one_value))
  return destination
end

function _skew_components!(destination, A)
  one_value = one(section_scalar_type(destination))
  _fiberwise_pass!(get_backend(field_data(destination)), _skew_values,
                   ntuple(n -> _tensor2_component_data(destination, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9)),
                   ntuple(n -> _tensor2_component_data(A, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9)), (), one_value, zero(one_value))
  return destination
end

function _dev_components!(destination, A)
  one_value = one(section_scalar_type(destination))
  _fiberwise_pass!(get_backend(field_data(destination)), _dev_values,
                   ntuple(n -> _tensor2_component_data(destination, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9)),
                   ntuple(n -> _tensor2_component_data(A, (n - 1) ÷ 3 + 1, (n - 1) % 3 + 1), Val(9)), (), one_value, zero(one_value))
  return destination
end


for (kernel, bang, allocating) in (
    (:_sym_components!,  :sym!,  :sym),
    (:_skew_components!, :skew!, :skew),
    (:_dev_components!,  :dev!,  :dev),
  )

  for (Tensor2Field,) in ((:(TensorFieldPhysical{2}),), (:(TensorFieldSpectral{2}),))

    @eval function $bang(destination::$Tensor2Field{T}, A::$Tensor2Field{T}) where {T<:AbstractFloat}
      check_field_compatibility(destination, A)
      return $kernel(destination, A)
    end

    @eval $allocating(A::$Tensor2Field{T}) where {T<:AbstractFloat} = $bang(similar_field(A, Val(2)), A)
  end
end


# Decompositions of a constant fiber tensor: explicit StaticArrays one-liners.
function sym(A::FiberTensor2{T}) where {T<:AbstractFloat}
  half = inv(T(2))
  off_12 = half * (A[1, 2] + A[2, 1])
  off_13 = half * (A[1, 3] + A[3, 1])
  off_23 = half * (A[2, 3] + A[3, 2])
  return FiberTensor2{T}(A[1, 1], off_12, off_13, off_12, A[2, 2], off_23, off_13, off_23, A[3, 3])
end


function skew(A::FiberTensor2{T}) where {T<:AbstractFloat}
  half = inv(T(2))
  off_12 = half * (A[1, 2] - A[2, 1])
  off_13 = half * (A[1, 3] - A[3, 1])
  off_23 = half * (A[2, 3] - A[3, 2])
  return FiberTensor2{T}(zero(T), -off_12, -off_13, off_12, zero(T), -off_23, off_13, off_23, zero(T))
end


function dev(A::FiberTensor2{T}) where {T<:AbstractFloat}
  trace_over_three = (A[1, 1] + A[2, 2] + A[3, 3]) / T(3)
  return FiberTensor2{T}(
    A[1, 1] - trace_over_three, A[2, 1], A[3, 1],
    A[1, 2], A[2, 2] - trace_over_three, A[3, 2],
    A[1, 3], A[2, 3], A[3, 3] - trace_over_three,
  )
end


#############################################
#          map! / map (arbitrary φ)         #
#############################################
#
# The physical, section-valued sibling of the mapped reductions: apply an arbitrary fiber map φ per base
# point through the shared `_fiberwise_pass!` executor. Fields in physical representation here, point-values in `Points`;
# both reuse `_map_pass!` and the `FiberSections` adapter. Arbitrary φ is nonlinear ⇒ physical-only
# (invariant 1) and aliased in spectral representation (the module warning above).

# Component arrays of a section in column-major (`Tuple(::SMatrix)`) order — the packing the adapter
# assembles from and flattens to. Generic over any `AbstractFiberSection` through the shared accessors, so
# it serves both fields and point-values.
@inline _section_components(section, ::Val{0}) = (field_data(section),)
@inline _section_components(section, ::Val{1}) =
  ntuple(component -> _vector_component_data(section, component), Val(3))
@inline _section_components(section, ::Val{2}) =
  ntuple(k -> _tensor2_component_data(section, (k - 1) % 3 + 1, (k - 1) ÷ 3 + 1), Val(9))


# Concatenate every source's component arrays into one flat tuple in argument order — the `arrays` a fused
# pass reads. Recursion over the sources tuple unrolls and stays type-stable.
@inline _cat_components(::Tuple{}) = ()
@inline _cat_components(sources::Tuple) =
  (_section_components(sources[1], _section_order(sources[1]))...,
   _cat_components(Base.tail(sources))...)


# The shared driver: pack targets/arrays, build the φ adapter, run one fused pass. Generic over the
# section kind; the public methods validate compatibility before calling it.
function _map_pass!(φ::F, destination, sources::Tuple, α::Real, β::Real) where {F}
  scalar = section_scalar_type(destination)
  orders = Base.map(_section_order, sources)
  targets = _section_components(destination, _section_order(destination))
  arrays = _cat_components(sources)
  _fiberwise_pass!(get_backend(field_data(destination)), _MapValues(φ, orders),
                   targets, arrays, (), scalar(α), scalar(β))
  return destination
end


# The output tensor order φ produces on these inputs, inferred from its return type; `-1` when
# un-inferrable (an unstable φ), which the allocating `map` turns into a clear error.
@inline function _map_output_order(φ::F, sources::Tuple) where {F}
  input_types = Base.map(source -> _fiber_type(section_scalar_type(source), _section_order(source)), sources)
  return _fiber_order(Base.promote_op(φ, input_types...))
end


# Allocate the map's result through the package's own allocator, which carries the reference's grid,
# Fourier layout, element type and backend. Building the field from a bare constructor instead drops
# the layout to its default, which broke `map` on every permuted `RealFourierLayout` (decision 48)
# from the day it shipped — the destination then mismatched its source and the call threw.
_allocate_map_output(reference::AbstractFieldPhysical, ::Val{R}) where {R} =
  similar_field(reference, Val(R))


# A fiber map that GATHERS may not alias the destination. Invariant 9's aliasing guarantee rests on a
# fused pass reading element `n` to write element `n`, which makes an in-place aliased call bitwise
# identical to a disjoint one. A section used as φ breaks that premise: a field is callable, and
# `f(x)` INTERPOLATES — it reads a neighbourhood around an arbitrary position, not the element being
# written. With φ aliasing the destination, one thread interpolates from storage another thread has
# already overwritten, so the result depends on the schedule. The exhaustive survey found exactly this:
# every failing determinism cell was `map!(x, x, x)`, in threaded configurations only, and none in a
# serial one — the serial order being fixed hides it. Refused rather than documented away, because a
# wrong answer that only appears under threading is the worst kind to leave reachable.
@inline function _check_map_not_aliased(φ, destination)
  φ isa AbstractFiberSection || return nothing
  φ === destination &&
    throw(ArgumentError("the fiber map aliases the destination: a section used as a map INTERPOLATES, " *
                        "reading positions rather than the element being written, so it must not be " *
                        "the field being written into"))
  return nothing
end


"""
    map!(φ, destination, sources...)
    map!(φ, destination, source, α, β)

Apply an arbitrary fiber map `φ` at every base point, writing the result into `destination` — the
section-valued companion of the mapped reductions (`mean(det, A)`, `maximum(norm, u)`): where those reduce
`φ` of the fiber over the base, this writes it as a field. It fuses in one pass, building no intermediate
section, and inherits the executor's parallelism (a device kernel on a GPU, a slab-threaded loop on a
CPU); being a per-point transform with disjoint writes, it is bitwise thread-count-invariant.

Use this when the operation is not one of the named fiberwise operations ([`det`](@ref), [`norm`](@ref),
the algebra) — an arbitrary pointwise function of the fiber, a composition such as `exp ∘ det` included.
Prefer the named operations where they exist (they carry their validity and their spectral forms); `map!`
is the escape hatch for the unnamed, physical-only maps.

Use this in-place form when `destination` is already allocated; the allocating [`map`](@ref) returns a
fresh result instead.

At every base point `x`, `destination`'s fiber is set to `φ` applied to the `sources`' fibers there;
`map!(φ, dest, f, g)` sets it to `φ(f(x), g(x))`.

The arguments are:
- `φ` — the fiber map, applied to the input fiber value(s) and returning the output fiber value. It must be
  a pure, GPU-safe function (no captured state, no scalar indexing of device arrays); its output tensor
  order sets `destination`'s order (`det` gives a scalar field, an `SMatrix`-valued `φ` a tensor field).
  It must also read **only the fiber it is given** — see the warning below.
- `destination` — the field in physical representation (or point-value section) that receives the result; its tensor order
  must match `φ`'s output.
- `sources` — one or more compatible fields in physical representation (or point-value sections) sharing `destination`'s
  base; `φ` receives their fiber values in argument order.
- `α`, `β` — the accumulation of the single-source form, ``\\texttt{destination} = \\alpha \\varphi(\\texttt{source}) + \\beta \\texttt{destination}`` (``β = 0`` overwrites, the `mul!` convention); the variadic form overwrites (``α = 1``, ``β = 0``).

!!! warning "A fiber map must not read the destination"
    The pass writes each base point independently and in an unspecified order, so `φ` may read only the
    fiber handed to it. A `φ` that reads elsewhere in the destination sees storage another thread may
    already have overwritten, and the result depends on the schedule — it will differ between runs, and
    between a threaded and a serial one.

    The trap is that **a field is callable**: `f(x)` interpolates, so passing a section as `φ` makes it a
    gather over a neighbourhood rather than an element-local map. That is why the usual aliasing freedom
    does not apply here. A destination may normally alias an input precisely because a fused pass
    reads element ``n`` to write element ``n``; a gathering `φ` breaks that premise.

    A **section** `φ` that is the destination is rejected — sections own their storage, so
    identity is a complete test for that case. A **closure that captures** the destination cannot be
    detected, and is the caller's responsibility. Aliasing between `destination` and the `sources`
    remains safe and is unaffected.

!!! warning "Physical-space only, and the result is aliased in spectral representation"
    An arbitrary `φ` is nonlinear, so — like the other nonlinear operations of this module — `map!` is
    defined for fields in physical representation only, and its result carries content above the grid's Nyquist: it is
    aliased once transformed to spectral representation. De-alias before spectral reuse (see the module
    docstring). Point-value sections are representation-free and carry no such restriction.
"""
function map!(φ::F, destination::AbstractFieldPhysical, sources::AbstractFieldPhysical...) where {F}
  _check_map_not_aliased(φ, destination)
  for source in sources
    _check_field_domain_compatibility(destination, source)
  end
  return _map_pass!(φ, destination, sources, true, false)
end

function map!(φ::F, destination::AbstractFieldPhysical, source::AbstractFieldPhysical,
              α::Real, β::Real) where {F}
  _check_map_not_aliased(φ, destination)
  _check_field_domain_compatibility(destination, source)
  return _map_pass!(φ, destination, (source,), α, β)
end


"""
    map(φ, sources...)

Allocating form of [`map!`](@ref): apply the fiber map `φ` at every base point and return a fresh section
holding the result. The output's tensor order is inferred from `φ` (`map(det, A)` returns a scalar field);
when it cannot be inferred, call `map!` with a preallocated `destination`. See [`map!`](@ref) for the
arguments and the physical-space-only / aliasing caveats.
"""
function map(φ::F, source1::AbstractFieldPhysical, sources::AbstractFieldPhysical...) where {F}
  all_sources = (source1, sources...)
  order = _map_output_order(φ, all_sources)
  order ≥ 0 ||
    throw(ArgumentError("map: could not infer the output tensor order of `φ`; call `map!` with a preallocated `destination` instead"))
  destination = _allocate_map_output(source1, Val(order))
  return map!(φ, destination, all_sources...)
end


end # module FieldAlgebra
