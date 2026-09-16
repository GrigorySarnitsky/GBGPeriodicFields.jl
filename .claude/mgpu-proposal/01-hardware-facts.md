# Hardware facts (verified 2026-09-16; agent report, sources in the transcript)

ARRHENIUS (NAISS, hosted by NSC Linköping; HPE Cray EX; production May/June 2026; inaugurated 8 Sep 2026)
- GPU partition: 382 nodes × 4 × NVIDIA GH200. Per superchip: 96 GiB HBM3 + 128 GB LPDDR5X + 72-core Grace (Neoverse V2).
  Per node: 384 GiB HBM + ~477-512 GiB LPDDR (NAISS says 128 GB/superchip; the identical Alps node is documented 120 GB — use 120 for a floor), 288 Arm cores, 4 × Slingshot NIC.
- Intra-node: 4 GH200 fully connected by NVLink 4.0, ~150 GB/s per direction per peer pair; the node is ONE cache-coherent address space (inferred from the identical HPE EX254n / Alps blade).
- Inter-node: Slingshot-11, 200 Gb/s per NIC ⇒ ~25 GB/s per NIC, ~100 GB/s per node per direction.
- CPU thin: 192 × 2 × EPYC 9755 (128c) + 768 GB DDR5. CPU fat: 20 × 3 TB.
- Scheduler Slurm; launcher `mpprun` (NSC wrapper over srun); GPU buildenv `buildenv-nvhpc/25.9-cu13.0` SHIPS NCCL, NVSHMEM and **cuFFTMp**.
- GPU-aware MPI NOT documented on the Arrhenius pages. Cray MPICH is GPU-aware only with `MPICH_GPU_SUPPORT_ENABLED=1` AND the GTL linked (`CRAY_ACCEL_TARGET`); sm_90 target value to confirm. MPI.jl must be bound to the system MPI with `MPIPreferences.use_system_binary()` or GPU-awareness is simply absent.

THE BANDWIDTH LADDER (this is the whole spill story)
  GPU → own HBM3            > 4000 GB/s        1x
  GPU → own Grace LPDDR      450 GB/s/dir      ~9x slower   (NVLink-C2C, hardware-coherent ATS)
  GPU → peer superchip mem   ~150 GB/s/dir     ~27x slower  (NVLink 4)
  GPU → x86 host over PCIe5  ~64 GB/s          ~60x slower  (why x86 spill experience misleads)
- GH200 gives (b) ATS hardware coherence, no migration: system-allocated memory is directly addressable,
  degradation is graceful and predictable, oversubscription is a design goal, NO thrash mode.
  `cudaMallocManaged` (migrating) still exists and is WORSE for streaming access with no reuse — measured to win
  only after ~128 back-to-back passes over the same data. A pseudospectral sweep streams each field once per pass.
  ⇒ prefer plain host/system allocation + ATS over managed memory for spilled fields.
  Discriminator at run time: `cudaDevAttrPageableMemoryAccessUsesHostPageTables` = 1 means ATS (GH200), 0 means software HMM (x86+H100).
- AMD: MI300A is a true APU (one pool); MI250X/MI300X need `HSA_XNACK=1` + HMM; **consumer RDNA3 gfx1100 has XNACK disabled
  and no in-kernel `malloc`** ⇒ the home 7900 XTX can validate the CODE PATH but not the performance or fault semantics.

SIZING (Float64; the rfft spectral field is within 0.2% of the physical field, so the same size)
  N=1024: 8.0 GiB/scalar field   N=2048: 64 GiB   N=4096: 512 GiB   (vector = 3x)
  Capacity per GPU node: 384 GiB HBM; 861 GiB HBM+LPDDR.
  Live set of 25 scalar fields (decision 37's own figure) reaches:
    1 GH200 (96 GiB)          ~768^3   <- decision 37's recorded ceiling
    4 GH200, HBM only         ~1270^3
    4 GH200 + spill (861 GiB) ~1650^3  <- BEATS the thin CPU node's ~1536^3, at GPU speed
    2048^3 needs ~1.6 TiB     => 2 nodes with spill, or ~5 nodes HBM-only
    4096^3 needs ~12.8 TiB    => 16+ nodes
