!!! info "Written by AI, not regularly reviewed"
    This page is written by AI and is not reviewed regularly by a human.

# Getting started

A short, runnable tour of the package. Every code block below is a **doctest** — the output shown is
checked when the docs are built, so the tutorial cannot silently drift from the code.

The mental model (the [Architecture](architecture.md) page): a **field** is a real physical object — a section of a
tensor bundle over a periodic box. *Physical* and *spectral* are two **representations** of the same
object; the complex coefficient arrays are storage detail, never the object itself.

## Grids and fields

A field is built from a [`Grid3D`](@ref) (the periodic box) and a function sampled on it. The
constructor sets the tensor order, and with it the fiber — the value space sitting over each point:
[`ScalarFieldPhysical`](@ref), [`VectorFieldPhysical`](@ref), [`TensorFieldPhysical`](@ref). Data
is stored fiber-last: the three grid axes come first, then one axis of length 3 for each tensor
order, so a scalar field is `(Nx, Ny, Nz)`, a vector field `(Nx, Ny, Nz, 3)` and a second-order
tensor field `(Nx, Ny, Nz, 3, 3)`.

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

Two pieces of scaffolding appear below, the spectral side being the one place
storage is not simply "the values". A [`RealFourierLayout`](@ref) records **how** the
real-to-complex transform is laid out: a real field's Fourier coefficients, by wavenumber vector, satisfy ``\hat f(-k) =
\overline{\hat f(k)}``, so only half the spectrum is stored, and the layout says which axis is the
halved one (the first, by default). The helper [`field_spectral_shape`](@ref) then gives the array
size that half-spectrum needs, and its `Val(R)` argument names the **tensor order** — `Val(0)` for a scalar
field, `Val(1)` for a vector one — passed as a `Val` so the shape is known to the compiler rather than
computed at run time.

```jldoctest tutorial
julia> layout = RealFourierLayout();

julia> spectral = VectorFieldSpectral(zeros(ComplexF64, field_spectral_shape(grid, layout, Val(1))), grid);

julia> plans = FieldTransformPlans(u, spectral);

julia> uh = to_spectral(u, plans);

julia> field_data(to_physical(uh, plans)) ≈ field_data(u)
true
```

## Differential operators

The differential operators are applied as spectral multipliers, acting on a field in spectral
representation through a [`FieldSpectralMultipliers`](@ref)
(the wavenumber arrays). They are *exact* on the band-limited field — e.g. the Laplacian of `sin(x)` is
`-sin(x)`:

```jldoctest tutorial
julia> φ = ScalarFieldPhysical((x, y, z) -> sin(x), grid);

julia> scalar_spectral = ScalarFieldSpectral(zeros(ComplexF64, field_spectral_shape(grid, layout, Val(0))), grid);

julia> multipliers = FieldSpectralMultipliers(scalar_spectral);

julia> laplacian_φ = to_physical(laplacian(to_spectral(φ, plans), multipliers), plans);

julia> field_data(laplacian_φ) ≈ -field_data(φ)
true
```

The `plans` built above for the *vector* field `u` transformed this *scalar* field `φ` too. A real
Fourier transform is defined on the box, and a field of tensor order ``R`` is that transform applied per
component, so a [`FieldTransformPlans`](@ref) carries no tensor order and one pair serves every order:
build one per storage family and element type.

The same pattern works for `gradient`, `divergence`, `curl`, `symmetric_gradient`,
`inverse_laplacian`, and `helmholtz_projection`.

## Fiberwise algebra and L²/measure reductions

The *fiberwise* (pointwise) algebra — `dot`, `cross`, `norm`, … — preserves the [base](@ref GBGPeriodicFields). The
reductions of the [`Reductions`](@ref GBGPeriodicFields.Reductions) module integrate the base out by
its measure: `inner` (``\langle\cdot,\cdot\rangle``) is the normalized L² product; `inner(u, u)`
is ``\langle |u|^2\rangle``, the average of ``|u|^2`` — single angle brackets mean that
average (here ``\langle\sin^2\rangle + \langle\cos^2\rangle + \langle\sin^2\rangle = \tfrac{3}{2}``).

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

The same quantity, twice the kinetic energy, resolved over wavenumber shells, is the radial power spectrum; its
total equals `inner` by Parseval:

```jldoctest tutorial
julia> shells, spectrum = radial_spectrum(uh, multipliers);

julia> round(sum(spectrum); digits = 4)   # Σ P(κ) = inner(u, u): the power spectrum's shells sum to inner
1.5
```

## Convolution (apply a Fourier kernel)

The `convolve` operation applies a kernel as the coefficientwise product. A kernel is not a field, and
is held per mode, as per-axis factors, or as a function of the wavenumber magnitude: `spectral_cutoff`
builds an isotropic sharp low-pass as the last, a `RadialKernel` storing no coefficients — here keeping wavenumbers
``|k| \le 4``:

```jldoctest tutorial
julia> cutoff = spectral_cutoff(multipliers, 4.0);

julia> field_tensor_order(convolve(uh, cutoff))
1
```

## Points: interpolation and anterpolation

A [`PointSet`](@ref) holds off-grid positions. The gather [`interpolate`](@ref) samples a field at
those points; its adjoint [`anterpolate`](@ref) scatters per-point quantities back onto the grid.

```jldoctest tutorial
julia> points = PointSet([0.5 1.0 1.5; 2.0 3.0 4.0]);

julia> npoints(points)
2

julia> sampled = interpolate(u, points);

julia> point_value_tensor_order(sampled)
1

julia> scattered = anterpolate(grid, points, sampled);

julia> size(field_data(scattered))
(16, 16, 16, 3)
```

Note that the adjoint takes the **grid** rather than a field as its first argument: it builds the
field it returns, so it needs only the base to build it over, where `interpolate` needs the field it
samples.

## Running multithreaded

CPU threading is on by default, but only if Julia itself has threads — the package threads nothing in
a single-threaded session, and nothing in the code you write says so. Start Julia with them:

```sh
julia -t 4 --project        # four threads
julia -t auto --project     # one per core
```

Nothing else is required: the fiberwise algebra, the differential operators and the reductions all
thread themselves from there, and the FFT plans pick up the same count when the package loads. The
work is split only above a size threshold, since threading a small field costs more than it saves:

```jldoctest tutorial
julia> threading_cutoff()
16384
```

Results do not depend on how many threads you used. The threaded routes write each output element
once, from the same fused expression a serial run uses, so they are **bitwise** identical to the
serial answer — which is what lets you tune the thread count without re-baselining anything you
compare against. The exceptions are by nature rather than oversight: [`anterpolate`](@ref),
[`radial_spectrum`](@ref) and [`radial_correlation`](@ref) accumulate with atomics, so the summation order
varies between runs and the last bits with it.

To compare against a serial run without restarting Julia, scope it with [`with_threading`](@ref);
[`set_threading_cutoff!`](@ref) moves the threshold, and [`set_fft_threads!`](@ref) sets the FFT thread count
alone, which is worth separating when the transforms and the pointwise work want different counts.

That is the whole surface in miniature: build a field, move between representations, apply operators /
convolutions, reduce it, and transfer to and from points. The [API reference](api.md) documents every
operation (with its computed formula), and the [Architecture](architecture.md) page explains *why* the package is shaped
this way.
