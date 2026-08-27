# Getting started

A short, runnable tour of the package. Every code block below is a **doctest** — the output shown is
checked when the docs are built, so the tutorial cannot silently drift from the code.

The mental model (the [Architecture](architecture.md) page): a **field** is a real physical object — a section of a
tensor bundle over a periodic box. *Physical* and *spectral* are two **representations** of the same
object; the complex coefficient arrays are storage detail, never the object itself.

## Grids and fields

A field is built from a [`Grid3D`](@ref) (the periodic box) and a function sampled on it. The
constructor sets the tensor order, and with it the fiber — the value space sitting over each point:
[`ScalarFieldPhysical`](@ref), [`VectorFieldPhysical`](@ref), [`TensorFieldPhysical`](@ref). Data is stored fiber-last, `(Nx, Ny, Nz[, 3[, 3]])`.

```jldoctest tutorial
julia> using GBGPeriodicFields

julia> grid = Grid3D((16, 16, 16), (2π, 2π, 2π));

julia> u = VectorFieldPhysical((x, y, z) -> (sin(x), cos(y), sin(z)), grid);

julia> field_tensor_order(u)
1

julia> size(field_data(u))
(16, 16, 16, 3)
```

## Representations: physical ↔ spectral

A field goes to its spectral representation with [`to_spectral`](@ref) and back with
[`to_physical`](@ref), through a reusable [`FieldTransformPlans`](@ref). The allocating forms preserve
their input, so the round trip recovers the field.

Two pieces of scaffolding appear below and are worth a sentence each, since the spectral side is the
one place the storage is not simply "the values". A [`RealFourierLayout`](@ref) records **how** the
real-to-complex transform is laid out: a real field's coefficients satisfy ``\hat f(-k) =
\overline{\hat f(k)}``, so only half the spectrum is stored, and the layout says which axis is the
halved one (the first, by default). [`spectral_field_shape`](@ref) then gives the array size that
half-spectrum needs, and its `Val(R)` argument names the **tensor order** — `Val(0)` for a scalar
field, `Val(1)` for a vector one — passed as a `Val` so the shape is known to the compiler rather than
computed at run time.

```jldoctest tutorial
julia> layout = RealFourierLayout();

julia> spectral = VectorFieldSpectral(zeros(ComplexF64, spectral_field_shape(grid, layout, Val(1))), grid);

julia> plans = FieldTransformPlans(u, spectral);

julia> uh = to_spectral(u, plans);

julia> field_data(to_physical(uh, plans)) ≈ field_data(u)
true
```

## Differential operators

Note that the `plans` built above for the *vector* field `u` transform this *scalar* field too. A real
Fourier transform is defined on the box, and a rank-``R`` field is that transform applied along a
fiber, so a [`FieldTransformPlans`](@ref) carries no tensor order and one pair serves every rank —
build one per backend and element type, not per rank.

The differential operators are applied as spectral multipliers, acting on a field in spectral
representation through a [`FieldSpectralMultipliers`](@ref)
(the wavenumber arrays). They are *exact* on the band-limited field — e.g. the Laplacian of `sin(x)` is
`-sin(x)`:

```jldoctest tutorial
julia> φ = ScalarFieldPhysical((x, y, z) -> sin(x), grid);

julia> scalar_spectral = ScalarFieldSpectral(zeros(ComplexF64, spectral_field_shape(grid, layout, Val(0))), grid);

julia> multipliers = FieldSpectralMultipliers(scalar_spectral);

julia> laplacian_φ = to_physical(laplacian(to_spectral(φ, plans), multipliers), plans);

julia> field_data(laplacian_φ) ≈ -field_data(φ)
true
```

`gradient`, `divergence`, `curl`, `symmetric_gradient`, `inverse_laplacian`, and
`helmholtz_projection` work the same way.

## Fiberwise algebra and L²/measure reductions

The *fiberwise* (pointwise, within-fiber) algebra — `dot`, `cross`, `norm`, … — preserves the base. The
*global* reductions in [`Reductions`](@ref GBGPeriodicFields.Reductions) integrate the base away against
its measure: `inner` ``\equiv \langle\cdot,\cdot\rangle`` is the normalized L² product, so `inner(u, u)`
is ``\langle |u|^2\rangle``, the domain average of ``|u|^2`` — single-argument angle brackets denote
that average (here ``\langle\sin^2\rangle + \langle\cos^2\rangle + \langle\sin^2\rangle = \tfrac{3}{2}``).

```jldoctest tutorial
julia> field_tensor_order(cross(u, u))    # u × u
1

julia> round(inner(u, u); digits = 4)     # ⟨|u|²⟩ = 1/2 + 1/2 + 1/2
1.5
```

Second-order tensor fields complete the surface. The gradient of a vector field is one, and the
tensor-only operations act on it fiberwise — the trace of ``\nabla u`` is the divergence, which is a
useful check that the two routes agree:

```jldoctest tutorial
julia> A = gradient(uh, multipliers);      # ∇u, a tensor field in spectral representation

julia> field_tensor_order(A)
2

julia> round(inner(tr(A), divergence(uh, multipliers)); digits = 8) ==
       round(inner(divergence(uh, multipliers), divergence(uh, multipliers)); digits = 8)
true
```

The same energy, resolved over wavenumber shells, is the radial power spectrum — and by Parseval's theorem its
total equals `inner`:

```jldoctest tutorial
julia> shells, spectrum = radial_spectrum(uh, multipliers);

julia> round(sum(spectrum); digits = 4)   # Σ P(κ) = inner(u, u): the power spectrum's shells sum to inner
1.5
```

## Convolution (apply a Fourier kernel)

The `convolve` operation applies a kernel as the coefficientwise product. A kernel is its own kind of
object rather than a field of coefficients, and a builder returns whichever storage class its symbol
admits: `spectral_cutoff` builds an isotropic sharp low-pass as a `RadialKernel`, evaluated per mode and
storing no coefficients at all — here keeping ``|k| \le 4``:

```jldoctest tutorial
julia> cutoff = spectral_cutoff(multipliers, 4.0);

julia> field_tensor_order(convolve(uh, cutoff))
1
```

## Points: interpolation and anterpolation

A [`PointSet`](@ref) holds off-grid positions. [`interpolate`](@ref) gathers a field to the points;
[`anterpolate`](@ref) is its adjoint, scattering per-point quantities back onto the grid.

```jldoctest tutorial
julia> points = PointSet([0.5 1.0 1.5; 2.0 3.0 4.0]);

julia> npoints(points)
2

julia> sampled = interpolate(u, points);

julia> pointvalue_tensor_order(sampled)
1

julia> scattered = anterpolate(grid, points, sampled);

julia> size(field_data(scattered))
(16, 16, 16, 3)
```

Note that the adjoint takes the **grid** rather than a field as its first argument: it builds the
field it returns, so it needs only the base to build it over, where `interpolate` needs the field it
samples.

That is the whole surface in miniature: build a field, move between representations, apply operators /
convolutions, reduce it, and transfer to and from points. The [API reference](api.md) documents every
operation (with its computed formula), and the [Architecture](architecture.md) page explains *why* the package is shaped
this way.
