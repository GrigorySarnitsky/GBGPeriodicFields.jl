!!! info "Written by AI, not regularly reviewed"
    This page is written by AI and is not reviewed regularly by a human.

# Running on a GPU

The same code runs on NVIDIA GPUs through `CUDA` and on AMD GPUs through `AMDGPU`. This package
depends on neither; add the one for your card to your own environment.

## Both vendors

The kind of array holding a field's values is its **storage family**: `Array` on the host, or a
vendor's device array. Every field constructor accepts a family in place of an array and allocates
uninitialized storage in it, and [`adapt`](@ref) moves an existing object to another family. Run your
vendor's setup block below first: it defines `DeviceArray` as that vendor's device array type.

```julia
L = Float32(2π)
grid = Grid3D((256, 256, 256), (L, L, L))         # the element type comes from the grid
u = VectorFieldPhysical(DeviceArray, grid)        # uninitialized, on the device
û = VectorFieldSpectral(DeviceArray, grid)
plans = FieldTransformPlans(u, û)                 # built from device fields, so on the device
multipliers = FieldSpectralMultipliers(û)

θ = adapt(DeviceArray, ScalarFieldPhysical((x, y, z) -> sin(x), grid))   # host to device
θ_host = adapt(Array, θ)                                                 # device to host
```

The same `adapt` moves multipliers, kernels, point sets and transform plans, and [`adapt!`](@ref)
copies into a field that already exists.

- **Mixed arguments are refused.** The fields, multipliers and kernels one operation combines must share
  a storage family and an element type; anything else throws an `ArgumentError` rather than being
  copied. Such an error usually means one object was left on the host.

- **Element-by-element access is slow.** Reading or writing one device element is a transfer. The
  package never does it, and the setup blocks call `allowscalar(false)`, which makes your own code throw
  where it would otherwise crawl.

- **Preallocated loops create no garbage.** In-place `!` operators other than `norm!` allocate no
  field-sized scratch, so a loop over preallocated fields needs no manual garbage collection.

- **Precision.** `Float32` halves the memory of every field, which is usually what limits the grid on a
  GPU; `Float64` works on both vendors.

- **Grid size.** Starting each GPU operation has a fixed cost, so small grids gain little. Timings for
  both vendors are on [Performance](performance.md).

- **Transforms may overwrite their input.** Whether `to_spectral!` or `to_physical!` overwrites its
  input differs between transform libraries, so never rely on it surviving. Use the allocating
  `to_spectral` or `to_physical`, or `to_physical!(physical, spectral, plans, spectral_scratch)`, which
  consumes `spectral_scratch` instead.

## CUDA (NVIDIA)

```julia
using CUDA, GBGPeriodicFields
CUDA.functional() || error("no usable CUDA device")
CUDA.allowscalar(false)
const DeviceArray = CuArray
```

The package is tested on an RTX 5070 Ti. Transforms need the default `RealFourierLayout`, because cuFFT
cannot plan a layout with its axes reordered; operations that build no plan accept any layout.

### Fields larger than GPU memory

CUDA.jl can allocate every `CuArray` in unified memory, which the driver pages between the GPU and host
RAM, so the package runs unchanged on fields that exceed the card, as long as the excess fits in host
RAM. It takes two entries in the Julia project the job runs in. The first goes in `LocalPreferences.toml`
beside its `Project.toml`:

```toml
[CUDACore]
default_memory = "unified"
```

The second goes under the `[extras]` table of that `Project.toml`, created if it is absent:

```toml
[extras]
CUDACore = "bd0ed864-bdfe-4181-a5ed-ce625a5fdea2"
```

!!! warning "Without both entries nothing changes, and nothing says so"
    Since CUDA.jl 6 this preference is read through its `CUDACore` subpackage, which Julia finds only
    when the project names it. A `[CUDA]` section, as CUDA.jl's own template shows, or a missing
    `[extras]` entry leaves every array in device memory without a warning.

The setting takes effect in a new Julia session, which recompiles CUDA.jl, and `"device"` restores the
default. The printed field says `CuArray` either way, so confirm with `CUDA.is_unified(field_data(u))`.
It covers every array the process allocates, so keep it out of a shared environment such as `@v1.12`,
where it would apply to every project. Unified arrays also ignore `allowscalar(false)`, so develop with
device memory.

On a PCIe host with an RTX 5070 Ti, a ``512^3`` `Float64` scalar transform round trip took about 8%
longer in unified memory than in device memory while every field fit on the card, and about 2.9 times as
long once the fields in use totalled 1.3 times the card's memory. Other access patterns and hosts, Grace
Hopper included, are unmeasured; see [Performance](performance.md).

## ROCm (AMD)

```julia
using AMDGPU, GBGPeriodicFields
AMDGPU.functional() || error("no usable ROCm device")
AMDGPU.allowscalar(false)
const DeviceArray = ROCArray
```

The package is tested on an RX 7900 XTX. Transforms on a layout with its axes reordered are untested on
ROCm. AMDGPU.jl has no unified memory, so fields must fit on the card.

!!! warning "The first run after a reboot looks like a hang"
    The first GPU use after a reboot compiles kernels on the host for minutes, with no output, the GPU
    idle and the CPU busy. Let it finish: an interrupted compile is not saved, so the next run starts cold
    again. rocFFT also recompiles its own kernels in each new process unless `ROCFFT_RTC_CACHE_PATH`
    names a writable file for it to keep them in.

On that card the `Float64` forms of `radial_spectrum` and its co-spectrum are exceptionally slow, about
48 times slower than an RTX 5070 Ti at ``256^3`` where `Float32` is within about 10%, so a run that
needs them is best done in `Float32` throughout.

A forced isotropic-turbulence simulation runs on an AMD GPU in `Float32`. From the root of a clone of the
repository:

```sh
julia --project=examples/gpu/rocm -e 'using Pkg; Pkg.instantiate()'
julia --project=examples/gpu/rocm examples/gpu/rocm/HIST_ROCm.jl --smoke
```
