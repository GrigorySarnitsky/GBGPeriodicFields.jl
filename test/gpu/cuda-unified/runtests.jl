# CUDA / NVIDIA entry point for the GPU test suite, with every CUDA array in UNIFIED memory.
#
# Opt-in, separate from `Pkg.test()` and from the device-memory lane in test/gpu/cuda. Run on a machine
# with an NVIDIA GPU:
#
#   julia --project=test/gpu/cuda-unified -e 'using Pkg; Pkg.instantiate()'   # one-time
#   julia --project=test/gpu/cuda-unified test/gpu/cuda-unified/runtests.jl
#
# The lane is selected by `LocalPreferences.toml` beside this file, not by anything in the code: the
# package names no memory kind, and a `CuArray` allocated without one takes CUDA.jl's `default_memory`
# preference. What this lane adds over test/gpu/cuda is three things — that the preference actually took
# effect, that every allocating route of the package honours it, and that a working set LARGER than the
# card's memory runs — and then the whole shared suite on unified storage.
#
# WHAT IT CANNOT CHECK. `allowscalar(false)` is set below as in every lane, but CUDA.jl does not enforce
# it for unified arrays: a scalar index is served through the host mapping and succeeds. So this lane is
# blind to invariant 6 (no scalar indexing of device arrays); the device-memory lane in test/gpu/cuda is
# the one that enforces it, and both must be run.

using CUDA
using Test
using GBGPeriodicFields

# Refuse to run a unified lane that is not unified. The preference fails SILENTLY when misspelled or
# unmapped — `[CUDA]` instead of `[CUDACore]`, or CUDACore missing from [extras] — and every array then
# lands in device memory while the suite goes green and proves nothing about this lane.
CUDA.is_unified(CuArray{Float64}(undef, 1)) || error(
  "test/gpu/cuda-unified: CUDA arrays are NOT being allocated in unified memory, so this lane would " *
  "silently re-run the device-memory suite. Check that LocalPreferences.toml names [CUDACore] and that " *
  "Project.toml lists CUDACore under [extras]; a changed preference also forces CUDA to recompile.")

CUDA.allowscalar(false)

const GPU_BACKEND = "CUDA / NVIDIA, unified memory"
device_functional() = CUDA.functional()
to_device(host_array) = CUDA.CuArray(host_array)
device_array_family() = CUDA.CuArray


# Every allocating route through which the package creates CUDA storage, asserted unified. The package
# never names a memory kind, so each of these takes the preference by construction — which is exactly the
# property to pin, since one route that built its storage some other way would put a field in device memory
# and leave the run to fail with an out-of-memory error at the one size this lane exists for.
function unified_residency(::Type{T}) where {T<:AbstractFloat}
  grid = Grid3D((8, 7, 6), (T(2π), T(2π), T(2π)))
  layout = RealFourierLayout()
  unified(array) = CUDA.is_unified(array)

  @testset "family constructors" begin
    for field in (ScalarFieldPhysical(CuArray, grid; layout), ScalarFieldSpectral(CuArray, grid; layout),
                  VectorFieldPhysical(CuArray, grid; layout), VectorFieldSpectral(CuArray, grid; layout),
                  TensorFieldPhysical{2}(CuArray, grid; layout), TensorFieldSpectral{2}(CuArray, grid; layout))
      @test unified(field_data(field))
    end
  end

  host_u = VectorFieldPhysical(rand(T, 8, 7, 6, 3), grid; layout)
  u = adapt(CuArray, host_u)
  spectral_u = VectorFieldSpectral(CuArray, grid; layout)
  multipliers = FieldSpectralMultipliers(spectral_u)
  plans = FieldTransformPlans(u, spectral_u)

  @testset "moves and allocators" begin
    @test unified(field_data(u))
    @test unified(field_data(similar_field(u, Val(2))))
    @test unified(multipliers.wavenumber_1)
    points = adapt(CuArray, PointSet(T(2π) .* rand(T, 40, 3)))
    @test unified(point_positions(points))
    values = adapt(CuArray, VectorPointValues(rand(T, 40, 3)))
    @test unified(point_values(values))
    @test unified(point_values(similar_point_values(values, Val(0))))
    @test unified(point_traversal_order(grid, points).indices)
  end

  @testset "results of allocating operations" begin
    @test unified(field_data(u .+ u))
    @test unified(field_data(to_spectral(u, plans)))
    @test unified(field_data(divergence(to_spectral(u, plans), multipliers)))
    @test unified(field_data(map(norm, u)))
  end

  @testset "kernels" begin
    scalar_spectral = ScalarFieldSpectral(CuArray, grid; layout)
    scalar_multipliers = FieldSpectralMultipliers(scalar_spectral)
    @test unified(translation_kernel(scalar_multipliers, (T(0.1), T(0.2), T(0.3))).factor_1)
    @test unified(field_data(materialize_kernel(spectral_cutoff(scalar_multipliers, T(2))).field))
    @test unified(NUFFT(scalar_spectral).deconvolution)
  end
end


# A working set larger than the card. Sized from the card itself, so the test means the same thing on a
# 16 GB and a 96 GB device, and SKIPPED ALOUD when host memory cannot hold the overflow — unified memory
# pages to host RAM, and a test that exhausts it would take the machine down rather than fail. Only the
# mechanism is asserted: allocation past the card succeeds, transforms run over every field, and the
# values survive the paging. Its timing is deliberately not recorded; on this path it measures the
# host's interconnect, not the package.
function unified_oversubscription()
  T = Float64
  n = 256
  grid = Grid3D((n, n, n), (T(2π), T(2π), T(2π)))
  layout = RealFourierLayout()
  pair_bytes = sizeof(T) * n^3 + 2 * sizeof(T) * n * n * (n ÷ 2 + 1)
  target = ceil(Int, 1.25 * CUDA.total_memory())
  pairs = cld(target, pair_bytes)
  needed = pairs * pair_bytes
  if Sys.free_memory() < 2 * needed
    @info "unified oversubscription SKIPPED: it needs $(round(needed / 2^30; digits = 1)) GiB of host " *
          "memory with headroom and $(round(Sys.free_memory() / 2^30; digits = 1)) GiB is free"
    @test_skip false
    return nothing
  end
  @info "unified oversubscription: $(pairs) field pairs, $(round(needed / 2^30; digits = 1)) GiB on a " *
        "$(round(CUDA.total_memory() / 2^30; digits = 1)) GiB card"
  physical = [ScalarFieldPhysical(CuArray, grid; layout) for _ in 1:pairs]
  spectral = [ScalarFieldSpectral(CuArray, grid; layout) for _ in 1:pairs]
  @test needed > CUDA.total_memory()
  plans = FieldTransformPlans(physical[1], spectral[1])
  for (index, field) in enumerate(physical)
    field_data(field) .= index
  end
  for _ in 1:2, index in 1:pairs
    to_spectral!(spectral[index], physical[index], plans)
    to_physical!(physical[index], spectral[index], plans)
  end
  for index in (1, pairs ÷ 2, pairs)
    @test all(isapprox.(Array(field_data(physical[index])), index; rtol = 1e-12))
  end
  return nothing
end


@testset "CUDA unified memory" begin
  if !device_functional()
    @info "No functional CUDA device; skipping the unified-memory lane."
  else
    for T in (Float64, Float32)
      @testset "residency, T = $T" begin
        unified_residency(T)
      end
    end
    @testset "a working set larger than the card" begin
      unified_oversubscription()
    end
    GC.gc()
    CUDA.reclaim()
  end
end

include(joinpath(@__DIR__, "..", "suite.jl"))
