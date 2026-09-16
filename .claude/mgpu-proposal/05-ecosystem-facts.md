# Ecosystem facts (agent, 2026-09-16; registry snapshot 2026-09-15). VERIFIED unless marked.

DISTRIBUTED FFT ROUTES
- PencilArrays 0.19.12 / PencilFFTs 0.15.4, MIT, ONE maintainer, julia>=1.10. GPU support exists via an
  array-type parameter since 2022, r2c first-class (RFFT/RFFT!/BRFFT), `extra_dims` are fiber-last.
  BUT: (a) CI never runs on a GPU — test deps are JLArrays, no CUDA/AMDGPU, no GPU job; (b) a GPU/MPI
  data race was fixed 2026-06-03 (KA.synchronize before Isend) and the fix covers only the PointToPoint
  path — `MPI.Alltoallv!` is STILL unsynchronised; (c) the GPU transpose ALLOCATES per call
  (`# TODO this allocates on GPUArrays`) — straight against invariant 13; (d) issue #74 (ROCArray plan
  fails) still open, though its stated cause is fixed in AMDGPU 2.8.0 — unconfirmed end to end;
  (e) issue #56 (single-GPU 174 ms vs cuFFT 2.4 ms, 2022, extreme aspect ratio) still open.
  `extra_dims` CANNOT give rank-free plans (Ne is a plan type parameter) — and PencilFFTs' own docs
  recommend one scalar plan applied per component, which is exactly decision 76.
  **CUDA-aware MPI is MANDATORY: buffers are device arrays handed straight to MPI, no host staging.**
- cuFFTMp: no Julia binding, licence blocks a JLL, CUDA-only, in-place-no-strides only.
- heFFTe: HeFFTe_jll v2.4.1 EXISTS but has NO ROCm (verified from the registry recipe) and NO Julia wrapper.
- FFTW MPI: FFTW_jll is built `--disable-mpi`; not reachable.
- rocFFT: multi-device IN ONE PROCESS via `rocfft_brick_create` (ROCm 6.0+), r2c since 6.1; AMDGPU.jl
  declares the C symbols but wraps none. MPI mode experimental, off by default. AMD-only.
- NCCL.jl 0.1.3 / RCCL.jl 0.1.0 exist (immature). DaggerFFT.jl is unregistered research code.

THE REFERENCE IMPLEMENTATION: Oceananigans.jl deliberately did NOT use PencilFFTs.
  ~460 lines total: a KA kernel packs a slab into a flat buffer -> sync_device! -> MPI.Alltoall(v)! directly
  on GPU buffers -> a KA kernel unpacks. Sub-communicators per direction (Comm_split), NOT COMM_WORLD.
  SLAB IS ENCODED IN THE TYPE: `yzbuff::YZ  # if nothing, slab`, and `transpose_z_to_y!(::SlabYFields) = nothing`
  dispatches the extra transposes away at zero cost. One rank per GPU, device = node-local rank.
  CI runs 4 ranks x 1 GPU. Two divergences to re-decide: they use c2c (dodging the half-spectrum across
  transposes) and forbid z-decomposition. GPU layout lesson: reshape so the transformed axis is dim 1.
  Their AMDGPU+PencilFFTs PR was ABANDONED ("I'm not going to work on this any more").

SLAB vs PENCIL AT FOUR RANKS: slab wins. Measured crossover ~384 MPI processes (Ayala et al., SC21,
  heFFTe+cuFFT on Summit, 1024^3). Slab = 1 all-to-all and 2 local FFT stages; pencil = 2 and 3.
  Expect to be communication-bound: >90% of runtime in the one directly measured multi-GPU case (24 V100s).
  NO published single-node 4-GPU compute/comm split exists — our own estimate stays an ESTIMATE.

SPILL / UNIFIED MEMORY
- CUDA.jl 6.4: `mutable struct CuArray{T,N,M} <: AbstractGPUArray` — the memory kind is a TYPE PARAMETER of
  the one type, so generic code keeps working. `is_device/is_unified/is_host`, `memory_type`.
  `similar`, `copy` and broadcast PRESERVE M (mixing kinds promotes to unified).
  `CUDA.zeros/ones/fill` DO NOT (they drop to default_memory).
  **cuFFT's allocating path returns DEVICE memory regardless of input** (same for rocFFT) — use `mul!`
  into a preallocated destination, which is what the package already does.
  `prefetch`/`advise` take the memory object, not the array; automatic prefetch is DISABLED when ndevices()>1.
  Oversubscription works; when host RAM is exhausted the OS kills the process on the page fault.
- **AMDGPU.jl 2.8.0 HAS NO UNIFIED MEMORY AT ALL** — only HIPBuffer (device) and HostBuffer (pinned host,
  every access crosses PCIe). `# TODO use unified buffer once we support it.` No hipMallocManaged anywhere.
  AMD's own support table omits RDNA3/gfx1100 entirely. ⇒ SPILL IS CUDA-ONLY, and the home box cannot test it.
- **KernelAbstractions already has the portable spelling**: `KA.allocate(backend, T, dims; unified::Bool=false)`
  and `KA.supports_unified(backend)` (CUDA true since v5.8; AMDGPU implements neither, so it throws).
  ⇒ the package needs NO vendor dependency and NO new verb to express residency.

PROCESS MODEL
- KA backends are device-agnostic singletons (`CUDABackend` has no device field); device identity is
  task-local. `KA.device!/device/ndevices` exist. CUDA.jl: "allocations are tied to the device that was
  active when requesting the memory ... similar restrictions apply to library objects, like CUFFT plans."
  ⇒ one process per GPU; one plan set per device otherwise.
- MPI.jl 0.20.27: GPU buffers pass directly. **`MPI.has_cuda()`/`has_rocm()` return FALSE on MPICH and
  Cray-MPICH even when support is present** — never gate on them; run the alltoall_test_*_multigpu.jl examples.
  Default threadlevel is :serialized. Known issues: JULIA_CUDA_MEMORY_POOL=none for CUDA IPC, UCX signal
  handling vs Julia's GC, precompile before mpiexec.
