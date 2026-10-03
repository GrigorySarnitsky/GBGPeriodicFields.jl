# ROCm / AMDGPU entry point for the GPU test suite.
#
# Opt-in, separate from the default `Pkg.test()` (which stays backend-free). Run on a
# machine with a working AMD GPU + ROCm:
#
#   julia --project=test/gpu/rocm -e 'using Pkg; Pkg.instantiate()'   # one-time (installs AMDGPU)
#   julia --project=test/gpu/rocm test/gpu/rocm/runtests.jl
#
# See test/gpu/README.md for the CUDA counterpart.

using AMDGPU

# Disable scalar indexing of device arrays: any scalar index inside a package method
# now throws, turning invariant 6 from a convention into a checked guarantee.
AMDGPU.allowscalar(false)

const GPU_BACKEND = "ROCm / AMDGPU"
device_functional() = AMDGPU.functional()
to_device(host_array) = AMDGPU.ROCArray(host_array)
# The storage family itself, for `adapt`: the suite moves whole sections, kernels and plans with the
# package's own interface rather than rewrapping arrays by hand.
device_array_type() = AMDGPU.ROCArray

# Waits for the device, for the device-cost lane's timings.
device_synchronize() = AMDGPU.synchronize()

include(joinpath(@__DIR__, "..", "suite.jl"))
