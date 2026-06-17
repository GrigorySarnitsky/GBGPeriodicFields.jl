# GPU tests (opt-in, per backend)

The default test suite (`julia --project -e 'using Pkg; Pkg.test()'`) is **backend-free**:
it runs on `Array` and installs no GPU stack, so it stays green on CI and on any machine.

These GPU tests are **separate environments you opt into** on a machine that has a device.
The package itself depends on no GPU backend — fields wrap a generic `AbstractArray`, FFT
plans are built through the generic `AbstractFFTs` interface, and allocations inherit their
backend via `similar`. So a GPU backend is only ever a *test* dependency, and it lives in a
per-backend environment here, never in the package's `Project.toml`.

## Why one environment per backend

With AMD at home, NVIDIA at the office, and a no-GPU CI box, a single shared GPU test
dependency would force one vendor's stack onto machines that can't use it. Instead each
backend gets its own pinned environment; on a given machine you instantiate only the one
matching its hardware. The actual test logic is shared and backend-agnostic
([`suite.jl`](suite.jl)); each backend directory only provides a thin entry script that
supplies `to_device`, `device_functional`, `GPU_BACKEND`, and calls `allowscalar(false)`.

## Run on AMD / ROCm

```sh
# one-time: resolve and install the environment (downloads the ROCm/HIP artifacts).
# AMDGPU is already a dependency here and Manifests are gitignored, so instantiate
# resolves it fresh against the [compat] bound.
julia --project=test/gpu/rocm -e 'using Pkg; Pkg.instantiate()'

# run the suite on the device
julia --project=test/gpu/rocm test/gpu/rocm/runtests.jl
```

If no functional device is present the suite warns and skips rather than failing.

## Run on NVIDIA / CUDA

```sh
# one-time: resolve and install the environment (downloads the CUDA toolkit artifacts).
# CUDA is already a dependency here and Manifests are gitignored, so instantiate
# resolves it fresh against the [compat] bound.
julia --project=test/gpu/cuda -e 'using Pkg; Pkg.instantiate()'

# run the suite on the device
julia --project=test/gpu/cuda test/gpu/cuda/runtests.jl
```

As with ROCm, the suite warns and skips if no functional device is present. (On a Pascal
card such as the GTX 1070, CUDA.jl may warn that the compute capability is "not fully
supported" by the auto-selected toolkit; the suite passes regardless.)

## Adding another backend

Mirror `rocm/` (or `cuda/`): a `Project.toml` with the same `[deps]` and `[sources]` path
(swapping the GPU backend dependency), plus a thin `runtests.jl` that swaps the backend
names — for CUDA, `AMDGPU` → `CUDA`, `AMDGPU.ROCArray` → `CUDA.CuArray`,
`AMDGPU.functional` → `CUDA.functional`, `AMDGPU.allowscalar` → `CUDA.allowscalar`, and
`GPU_BACKEND = "CUDA"`. The shared `suite.jl` needs no changes.

## What the suite checks

On the device, compared against the trusted CPU result (`Array(device) ≈ host`), with
scalar indexing **disabled** so any stray scalar index into device memory inside a package
method fails the test (invariant 6):

- FFT round-trips (scalar / vector / tensor);
- vector-space algebra and fused broadcast assignment;
- the spectral zero-mode constant update (invariant 4);
- contractions and products — `dot`, `cross`, tensor·vector, tensor·tensor, and `mul!` in
  both its overwrite (β = 0) and accumulate (β ≠ 0) branches;
- `transpose`, `sym`/`skew`/`dev`, and the pointwise norms;
- the spectral differential operators (`gradient`, `divergence`, `curl`, `laplacian`,
  `inverse_laplacian`, `helmholtz_projection`) and the spectral linear tensor ops.
