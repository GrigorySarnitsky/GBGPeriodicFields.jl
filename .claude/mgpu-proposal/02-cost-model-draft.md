# Order-of-magnitude cost model (my own arithmetic; to be labelled ESTIMATE, never measured)

One 3D r2c transform, 1024^3 Float64, spectral array 1024x1024x513 complex = 8.05 GiB.

INTRA-NODE, 4 GH200, 2D pencil ⇒ two all-to-all transposes per transform.
  Each GPU holds ~2 GiB; in one all-to-all it ships 3/4 of that = 1.5 GiB, 0.5 GiB to each of 3 peers.
  Per-pair link 150 GB/s/direction ⇒ ~3.3 ms per transpose ⇒ ~6.6 ms of communication per transform.
  Local FFT work: the array is read/written several times; ~48 GiB of HBM traffic over 4 GPUs at ~4 TB/s each
  ⇒ ~3 ms, call it 3-8 ms with library overheads.
  ⇒ communication ~= computation. Expect ~2.5-3.5x on 4 GPUs for transform-dominated work,
    ~4x (linear) for the fused pointwise/fiberwise work, which is pure local bandwidth.
  NOTE: the 2026-09-05 answer to the same question estimated 2.5-3x from PCIe numbers measured at home
  (12.6/16.3 GB/s). NVLink at 150 GB/s/pair is ~10x that, so the intra-node estimate should be revised UP,
  and the "cross-node capacity only" half revised DOWN (see below).

INTER-NODE, Slingshot ~100 GB/s per node per direction.
  The same 8 GiB array crossing the node boundary once ⇒ ~86 ms against ~3-8 ms of local FFT.
  ⇒ a transpose that leaves the node costs ~10-25x a transpose that does not.
  ⇒ DESIGN CONSEQUENCE: a 2D pencil decomposition must put the FAST transpose on the intra-node axis
    and the slow one across nodes, and multi-node scaling is capacity-first, throughput-second.
    4 GPUs on ONE node is the sweet spot; that is exactly what the owner asked for.

SPILL, same field, on GH200: reading a spilled field costs ~9x a resident one (450 GB/s vs >4 TB/s).
  A step that spills HALF its traffic runs ~5x slower; a step that spills EVERYTHING runs ~9x slower.
  ⇒ spill is for fields streamed rarely (checkpoints, accumulators, diagnostics, the observables cache),
    never for the transform's working set. Per-FIELD residency, not per-run.
