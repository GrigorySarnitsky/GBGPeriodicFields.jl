!!! info "Written by AI, not regularly reviewed"
    This page is written by AI and is not reviewed regularly by a human.

# Running on a GPU

The package runs on NVIDIA GPUs through `CUDA` and on AMD GPUs through `AMDGPU`, and depends on neither:
add the one for your card to your own environment. The first section describes what holds on both
vendors; each vendor section then starts with a complete example you can run as it stands.

## Both vendors

### Fields on a device

The kind of array holding a field's values is its **storage family**: `Array` on the host, `CuArray` on
an NVIDIA GPU, `ROCArray` on an AMD GPU. Every field constructor accepts a family in place of an array
and allocates uninitialized storage in it. Fields, their [multipliers](@ref FieldSpectralMultipliers), [kernels](@ref SpectralKernel),
point sets and transform [plans](@ref FieldTransformPlans) move to another family with [`adapt`](@ref), and [`adapt!`](@ref) copies into an existing field.
Plans and multipliers built from device fields live there too.

The fields, multipliers and kernels one operation combines must share a storage family and an element
type. Anything else throws an `ArgumentError` rather than being copied, so such an error usually means
one object was left on the host.

### Writing efficient device code

Four habits make the difference on either vendor:

- **Never touch single elements.** Reading or writing one element of a device array is a transfer
  between host and GPU. The package never does it, and `CUDA.allowscalar(false)` or
  `AMDGPU.allowscalar(false)` makes your own code throw where it would otherwise crawl.

- **Preallocate, and call in-place operators.** In-place `!` operators other than `norm!` allocate no
  field-sized scratch, so a loop that calls only them needs no manual garbage collection. Allocating
  calls — `to_spectral`, `lpnorm`, `radial_correlation` — create a new device array each time.

- **Consider `Float32`.** It halves the memory of every field, which is usually what limits the grid on a
  GPU; `Float64` works on both vendors.

- **Use a GPU for large grids.** Each GPU operation has a fixed start-up cost, so small grids gain
  little. [Performance](performance.md) has timings for both vendors.

### Transforms may overwrite their input

Whether `to_spectral!` or `to_physical!` overwrites its input differs between transform libraries, so
never rely on the input surviving. Use the allocating `to_spectral` or `to_physical`, or
`to_physical!(physical, spectral, plans, spectral_scratch)`, where `spectral_scratch` is a second field
shaped like `spectral` and is overwritten instead.

## CUDA (NVIDIA)

### A first run on CUDA

```julia
using CUDA, GBGPeriodicFields
CUDA.functional() || error("no usable CUDA device")
CUDA.allowscalar(false)

L = Float32(2π)
grid = Grid3D((256, 256, 256), (L, L, L))       # Float32 fields, set by the grid
u = VectorFieldPhysical(CuArray, grid)          # uninitialized, on the GPU
û = VectorFieldSpectral(CuArray, grid)
plans = FieldTransformPlans(u, û)               # built from GPU fields, so on the GPU
multipliers = FieldSpectralMultipliers(û)

θ = adapt(CuArray, ScalarFieldPhysical((x, y, z) -> sin(x), grid))  # host to GPU
θ̂ = ScalarFieldSpectral(CuArray, grid)
to_spectral!(θ̂, θ, plans)                       # a transform on the GPU
∇θ̂ = gradient(θ̂, multipliers)                   # an operator on the GPU
θ_host = adapt(Array, θ)                        # GPU to host
```

The package is tested on an RTX 5070 Ti. Transforms need the default [`RealFourierLayout`](@ref), which
the constructors above use when no layout is passed: cuFFT cannot plan one with its axes reordered.
The turbulence simulation in the ROCm section has no CUDA version; its CPU version is in
[Examples](examples/hist_cpu.md).

### Fields larger than GPU memory

CUDA.jl can allocate every `CuArray` in unified memory, which the driver pages between the GPU and host
RAM, so the package runs unchanged on fields that exceed the card, as long as the excess fits in host
RAM. Turn it on once, from Julia started in the project the job runs in, then restart Julia:

```julia
using CUDA
CUDA.CUDACore.Preferences.set_preferences!(CUDA.CUDACore,
                                           "default_memory" => "unified"; force = true)
```

The call writes two entries, which can also be added by hand. The first goes in `LocalPreferences.toml`
beside the project's `Project.toml`:

```toml
[CUDACore]
default_memory = "unified"
```

The second goes under the `[extras]` table of that `Project.toml`, created if it is absent. The call
rewrites `Project.toml` to add it and drops any comments there, so add it by hand to keep them:

```toml
[extras]
CUDACore = "bd0ed864-bdfe-4181-a5ed-ce625a5fdea2"
```

!!! warning "Without both entries nothing changes, and nothing says so"
    Since CUDA.jl 6 this preference is read through its `CUDACore` subpackage, which Julia finds only
    when the project names it. A `[CUDA]` section, as CUDA.jl's own template shows, or a missing
    `[extras]` entry leaves every array in device memory without a warning.

The setting takes effect in a new Julia session, which recompiles CUDA.jl; the same call with
`"device"` restores the default. The printed field says `CuArray` either way, so rerun the first example and check
`CUDA.is_unified(field_data(u))` on the array holding `u`'s values: it returns `true`. The setting covers every array the process
allocates, so keep it out of a shared environment such as `@v1.12`,
which every project uses. Unified arrays also ignore `allowscalar(false)`, so develop with
device memory.

On a PCIe host with an RTX 5070 Ti, a ``512^3`` `Float64` scalar transform round trip took about 8%
longer in unified memory than in device memory while every field fit on the card, and about 2.9 times as
long once the fields in use totalled 1.3 times the card's memory. Other access patterns and hosts, Grace
Hopper included, are unmeasured; see [Performance](performance.md).

## ROCm (AMD)

### A first run on ROCm

```julia
using AMDGPU, GBGPeriodicFields
AMDGPU.functional() || error("no usable ROCm device")
AMDGPU.allowscalar(false)

L = Float32(2π)
grid = Grid3D((256, 256, 256), (L, L, L))       # Float32 fields, set by the grid
u = VectorFieldPhysical(ROCArray, grid)         # uninitialized, on the GPU
û = VectorFieldSpectral(ROCArray, grid)
plans = FieldTransformPlans(u, û)               # built from GPU fields, so on the GPU
multipliers = FieldSpectralMultipliers(û)

θ = adapt(ROCArray, ScalarFieldPhysical((x, y, z) -> sin(x), grid))  # host to GPU
θ̂ = ScalarFieldSpectral(ROCArray, grid)
to_spectral!(θ̂, θ, plans)                       # a transform on the GPU
∇θ̂ = gradient(θ̂, multipliers)                   # an operator on the GPU
θ_host = adapt(Array, θ)                        # GPU to host
```

The package is tested on an RX 7900 XTX. Transforms on a layout with its axes reordered are untested on
ROCm, so use the default layout there too. AMDGPU.jl has no unified memory, so fields must fit on the
card.

### Known pitfalls on ROCm

!!! warning "The first run after a reboot looks like a hang"
    The first GPU use after a reboot compiles kernels on the host for minutes, with no output, the GPU
    idle and the CPU busy. Let it finish: an interrupted compile is not saved, so the next run starts cold
    again. rocFFT also recompiles its own kernels in each new process unless `ROCFFT_RTC_CACHE_PATH`
    names a writable file for it to keep them in.

On the tested card the `Float64` forms of `radial_spectrum` and its co-spectrum are exceptionally slow,
about 48 times slower than an RTX 5070 Ti at ``256^3`` where `Float32` is within about 10%, so a run that
needs them is best done in `Float32` throughout.

### A turbulence simulation on ROCm

A forced isotropic-turbulence simulation runs on an AMD GPU in `Float32`, writing its results and figures
to `examples/gpu/rocm/output`; the figures need a LaTeX installation. From the root of a clone of the
repository:

```sh
julia --project=examples/gpu/rocm -e 'using Pkg; Pkg.instantiate()'
julia --project=examples/gpu/rocm examples/gpu/rocm/HIST_ROCm.jl --smoke
```
