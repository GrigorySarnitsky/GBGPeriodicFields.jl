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
# The array family itself, for `adapt`: the suite moves whole sections, kernels and plans with the
# package's own interface rather than rewrapping arrays by hand.
device_array_family() = AMDGPU.ROCArray

# Waits for the device, for the device-cost lane's timings.
device_synchronize() = AMDGPU.synchronize()

# Whether every AMD card's performance level is pinned high, read from sysfs. The device-cost bounds
# for this backend were frozen pinned (`sudo rocm-smi --setperflevel high`); under `auto` the card
# picks a memory-clock state per process and the lane's ratios differ by up to 1.0 between
# processes, so unpinned the lane reports and does not judge. Set it back with `--setperflevel auto`.
function device_clock_pinned()
  levels = String[]
  for card in filter(startswith("card"), readdir("/sys/class/drm"))
    device = joinpath("/sys/class/drm", card, "device")
    vendor = joinpath(device, "vendor"); level = joinpath(device, "power_dpm_force_performance_level")
    isfile(vendor) && isfile(level) && strip(read(vendor, String)) == "0x1002" || continue
    push!(levels, strip(read(level, String)))
  end
  return !isempty(levels) && all(==("high"), levels)
end

include(joinpath(@__DIR__, "..", "suite.jl"))
