# GPU benchmarks

Per-backend GPU benchmark environments, mirroring `test/gpu/`. Opt-in; run on a machine with a
device. Each backend entry sets the device array type and includes the shared suite
(`benchmark/benchmarks.jl`) via `build_suite(; array_type = <DeviceArray>)`, with scalar indexing
disabled so invariant 6 (no scalar GPU indexing) is a checked guarantee.

- `rocm/` — AMD ROCm / AMDGPU (present).
- `cuda/` — NVIDIA CUDA (present).

```
# ROCm / AMDGPU
julia --project=benchmark/gpu/rocm -e 'using Pkg; Pkg.instantiate()'   # one-time
julia --project=benchmark/gpu/rocm benchmark/gpu/rocm/runbenchmarks.jl

# CUDA / NVIDIA
julia --project=benchmark/gpu/cuda -e 'using Pkg; Pkg.instantiate()'   # one-time
julia --project=benchmark/gpu/cuda benchmark/gpu/cuda/runbenchmarks.jl
```

GPU results are recorded by platform in `docs/PERFORMANCE.md` §6 (CI runners have no GPU, so GPU
tracking is manual).
