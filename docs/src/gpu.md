!!! info "Written by AI, not regularly reviewed"
    This page is written by AI and is not reviewed regularly by a human.

# Running on a GPU

The package runs on an NVIDIA GPU through `CUDA` and on an AMD GPU through `AMDGPU`, with no change to
the code that uses it. It depends on neither vendor package: a field wraps whatever array it is given,
so the backend is a package you add to your own environment and load beside this one.

## Fields on a device

A field's **storage family** is the kind of array holding its values — `Array` on the host, `CuArray`
on an NVIDIA GPU, `ROCArray` on an AMD one. Every field constructor accepts a family in place of an
array and allocates uninitialized storage in it, and [`adapt`](@ref) moves anything built on the host
to a device. Transform plans and spectral multipliers built from device fields live on the device too.

```julia
using CUDA, GBGPeriodicFields                 # AMD: using AMDGPU, and ROCArray below
CUDA.allowscalar(false)                       # AMD: AMDGPU.allowscalar(false)

grid = Grid3D((256, 256, 256), (2π, 2π, 2π))
u = VectorFieldPhysical(CuArray, grid)        # uninitialized, on the device
û = VectorFieldSpectral(CuArray, grid)
plans = FieldTransformPlans(u, û)             # device transform plans
multipliers = FieldSpectralMultipliers(û)     # wavenumbers on the device

θ = adapt(CuArray, ScalarFieldPhysical((x, y, z) -> sin(x), grid))   # host to device
```

Everything one operation combines must share a storage family and an element type. A host field and a
device field are refused rather than copied behind your back, so an error naming the storage family
usually means one object was left on the host; `adapt(Array, u)` brings a result back.

The `allowscalar(false)` call is optional and worth keeping while developing. Reading or writing a GPU
array one element at a time from Julia is possible but costs a transfer per element, which is
disastrous inside a loop; the call turns every such access into an error, so the mistake surfaces
instead of hiding as slowness. The package itself never indexes a device array element by element.

Device work pays a fixed launch cost per operation, so small grids gain little and large ones gain
most. [Performance](performance.md) records measured timings for both vendors.

## Fields larger than GPU memory (CUDA only)

On CUDA, fields that do not all fit in GPU memory can still run instead of failing with an
`OutOfGPUMemoryError`. CUDA.jl can allocate every array in **unified memory**, which the driver pages
between the GPU and host RAM as it is used. The package code does not change: the choice is a CUDA.jl
preference of the Julia project the job runs in. What is left over must fit in host RAM.

AMD GPUs have no counterpart. `AMDGPU` offers no unified memory, so on ROCm the fields must fit in the
card's memory.

### Turning it on

Two entries are needed, and both matter. In `LocalPreferences.toml` beside your job's `Project.toml`:

```toml
[CUDACore]
default_memory = "unified"
```

and in that `Project.toml`:

```toml
[extras]
CUDACore = "bd0ed864-bdfe-4181-a5ed-ce625a5fdea2"
```

Since CUDA.jl 6 the preference is read by its `CUDACore` subpackage, and Julia finds a preference only
for a package that the project names in `[deps]`, `[weakdeps]` or `[extras]` — which `CUDACore`, a
dependency of a dependency, is not by default. The call below writes both entries, but it rewrites
`Project.toml` and drops the comments in it:

```julia
Preferences.set_preferences!(CUDA.CUDACore, "default_memory" => "unified"; force = true)
```

Changing the preference recompiles CUDA.jl on the next load, and setting it to `"device"` restores the
default.

!!! warning "A misplaced preference is silently ignored"
    A section named `[CUDA]` — which CUDA.jl's own template still shows — or a missing `[extras]`
    entry leaves every array in ordinary device memory, with no warning. The first sign is the
    out-of-memory error you meant to avoid. Preferences also merge across Julia's whole load path, so
    an entry in a shared environment such as `@v1.12` switches unified memory on for every project.

Check before a long run; the printed field says `CuArray` either way:

```julia
CUDA.is_unified(field_data(u))    # true when the preference took effect
```

### What to expect

!!! warning "The whole process, and a guard that no longer fires"
    The preference applies to **every** CUDA array the process allocates without an explicit memory
    kind, the transform buffers included. Unified memory for some fields and device memory for others
    is not supported. And `CUDA.allowscalar(false)` does **not** catch element-by-element access to
    unified arrays: CUDA.jl serves it through the host, so that class of mistake goes unreported. Find
    it with device memory first.

What was verified, with CUDA.jl 6.3 on an x86 host and a 16 GB RTX 5070 Ti: the package's GPU test
suite passes with every array in unified memory (494 of 494, on 2026-09-17), and fields totalling 1.25
times the card's memory run through repeated transforms with their values intact.

What it costs depends on the hardware, and little of it has been measured:

- **When everything fits**, unified memory was about 8% slower than device memory on that card, for a
  ``512^3`` transform round trip. For a grid that already fits, turning it on buys nothing.

- **When the fields exceed GPU memory**, pages migrate as they are used, and the cost is set by the
  link between GPU and host. On the x86 machine above, over PCIe, the same round trip ran about three
  times slower than on device memory. That is one access pattern on one machine, not a prediction.

- **On Grace Hopper (GH200)** the GPU reaches host memory over NVLink-C2C, a far faster link, and
  nothing has been measured there yet.

- **The number of GPUs a process sees changes the behaviour.** CUDA.jl moves a whole unified array to
  the GPU before each launch only when exactly one device is visible; with several it migrates pages
  on demand. Keep that setting fixed when comparing runs.

[Performance](performance.md) records the measurements and what remains unmeasured.
