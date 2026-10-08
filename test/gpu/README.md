# GPU tests

The GPU suite, separate from `Pkg.test()` and run only on a machine with a device. Each backend has
its own environment, so a machine installs only its own vendor's stack; the tests themselves are shared
in [`suite.jl`](suite.jl).

```sh
julia --project=test/gpu/cuda -e 'using Pkg; Pkg.instantiate()'   # NVIDIA, one-time
julia --project=test/gpu/cuda test/gpu/cuda/runtests.jl

julia --project=test/gpu/rocm -e 'using Pkg; Pkg.instantiate()'   # AMD, one-time
julia --project=test/gpu/rocm test/gpu/rocm/runtests.jl
```

Without a working device the suite warns and skips rather than failing.

## What it checks

Scalar indexing of device arrays is disabled, so a package method that indexes one element at a time
throws (invariant 6). Within that:

- **Parity.** The public surface, run on device arrays in `Float64` and `Float32`, against the same
  call on the CPU.
- **Allocation.** Every in-place operation with its destination also an input allocates nothing on the
  device. Only a backend that can count device bytes runs this check; today that is CUDA.
- **Cost.** Ten operations at 256³, timed against the memory each must move, with bounds frozen per
  backend and precision. A backend without frozen bounds reports without judging.

## Unified memory (CUDA)

```sh
julia --project=test/gpu/cuda-unified -e 'using Pkg; Pkg.instantiate()'   # one-time
julia --project=test/gpu/cuda-unified test/gpu/cuda-unified/runtests.jl
```

The same suite with every CUDA array in unified memory, which the driver pages between the GPU and
host RAM; the tracked `LocalPreferences.toml` in that directory selects it, and `docs/src/gpu.md`
explains the setting. The lane refuses to run if the setting did not take effect, and checks a working
set larger than the card. Run it in addition to the device lane, never instead: CUDA.jl does not
disable scalar indexing for unified arrays, so this lane cannot catch it.

## Adding a backend

Copy `cuda/` or `rocm/`: a `Project.toml` with the backend's package in place of the other, and a
`runtests.jl` that defines `GPU_BACKEND`, `device_functional`, `to_device`, `device_array_family`
and `device_synchronize`, and `device_bytes_allocated` if the backend can count device bytes, calls
`allowscalar(false)`, and includes `suite.jl`.
`suite.jl` needs no change.
