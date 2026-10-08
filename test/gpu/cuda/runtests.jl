# CUDA / NVIDIA entry point for the GPU test suite.
#
# Opt-in, separate from the default `Pkg.test()` (which stays backend-free). Run on a
# machine with a working NVIDIA GPU + driver:
#
#   julia --project=test/gpu/cuda -e 'using Pkg; Pkg.add("CUDA"); Pkg.instantiate()'   # one-time (installs CUDA)
#   julia --project=test/gpu/cuda test/gpu/cuda/runtests.jl
#
# See test/gpu/README.md for the ROCm counterpart.

using CUDA

# Disable scalar indexing of device arrays: any scalar index inside a package method
# now throws, turning invariant 6 from a convention into a checked guarantee.
CUDA.allowscalar(false)

const GPU_BACKEND = "CUDA / NVIDIA"
device_functional() = CUDA.functional()
to_device(host_array) = CUDA.CuArray(host_array)
# The array family itself, for `adapt`: the suite moves whole sections, kernels and plans with the
# package's own interface rather than rewrapping arrays by hand.
device_array_family() = CUDA.CuArray
# Device bytes one call allocates, for the aliased-allocation lane. `CUDA.@allocated` counts the device
# pool, which host-side `@allocated` cannot see.
device_bytes_allocated(operation) = (CUDA.synchronize(); CUDA.@allocated operation())

# Waits for the device, for the device-cost lane's timings.
device_synchronize() = CUDA.synchronize()

include(joinpath(@__DIR__, "..", "suite.jl"))
