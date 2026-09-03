# Benchmark results

Minimum time per operation; `—` = not measured for that column (a device / grid / element-type combination not run). Generated 2026-09-02 at commit `9ca38af2` on Julia 1.12.7, assembled on host `Enteropia` — a **multi-host** report (each device names its own host below). Columns are the supplied runs; grids and element types are in the row labels. **CPUs** — thread sweep 1/2/4/8: **i7-12700K** (8 P-cores — `Aiporetne`, 64³–**512³** both element types) and **Ryzen 9800X3D** (8 Zen 5 cores / 16 threads, 96 MB 3D V-Cache — `Enteropia`, 64³–**512³** both element types — the CPU production band of ARCHITECTURE.md decision 37; RAM bounds nothing at 123 GB); both CPU columns are measured at the decision-38/39 rewrite — slab-threaded assignments and the fused one-pass kernels, so thread scaling is monotone (the retired inversion the previous archive carried is finding (l) in PERFORMANCE.md §4). Both CPU columns now carry post-decision-40 threaded reductions — the fixed-tree reduce scaling monotonically with thread count (e.g. `maximum scalar` 128³ Float64, 9800X3D: 442 → 59 µs t1→t8) — so the reductions cells are cross-host comparable. **GPUs**, newest last: **RX 7900 XTX** (gfx1100, ROCm, 24 GB, power-capped 294 W — `Aiporetne`, 64³–256³ both types + 512³ `Float32`, the `transfer` and `reductions` classes omitted at 512³ — transfer's NUFFT oversamples to 1024³ and the radial diagnostics' working set hits the 24 GB ceiling); **RTX 5070 Ti** (Blackwell sm_120, CUDA, 16 GB — `Enteropia`, 64³–256³ both types; 512³ exceeds 16 GB — the `mul!` tensor field alone is 4.5 GB). **Two columns for since-retired cards were DROPPED on 2026-08-07** — both were measured under the `gcsample` regime of PERFORMANCE.md §4(s), which inflated device rows 2–29×, and neither card is in the fleet to re-sweep, so those columns could never be corrected or compared against anything measured after the fix. Every remaining column is measured at the decision-38/39 rewrite. **Both GPU columns are now in the fixed measurement regime and are comparable again.** Device lanes used to run with a blanket `gcsample = true`, so a full `GC.gc()` — whose finalizers free device buffers and synchronize — preceded every sample and dominated operations lasting tens of microseconds, inflating device rows 18.4–29.2× at ``64^3``, 5.8–19.8× at ``128^3`` and 1.9–4.25× at ``256^3`` on the AMD card. `gcsample` is now decided per row from a measured device-pool probe and kept only for rows that genuinely materialize. **GPU 7900XTX was re-swept 2026-08-07** (median −81.6%) and **GPU 5070TI on 2026-08-09** (median −46.4% over 426 rows). The NVIDIA correction is the smaller of the two because that vendor's collect-and-synchronize is cheaper, not because less was wrong: the CUDA branch of the probe called `CUDA.available_memory`, which is not a binding, so it threw on every row and the catch-all held every CUDA row on the collector until 2026-08-09 — see PERFORMANCE.md §4(w), and note that a fallback reported as a measurement is the reason that went unnoticed. CPU columns were never affected, `gcsample` being gated on the backend. See PERFORMANCE.md §4(s). **`fft` rows are comparable only within a column vintage, and the 2026-08-05 shift is `Enteropia`-specific.** That re-sweep of the 9800X3D lanes found the `fft` class 20–50% slower than the 2026-07-30 archive at the larger grids (``256^3`` `Float64` `to_physical scalar` t1: 83.8 → 116.0 ms), reproducible to under 1% across three standalone probes, while the other 596 rows moved by a median of −0.12% and the cuFFT lane showed no `fft` mover at all. It is not the package (zero changed lines on the transform path), not FFTW, and not Julia; a reboot fell between the two sweeps and no pre-reboot platform state was recorded. **The 2026-08-07 `Aiporetne` re-sweep is the control, and at the larger grids the shift does not reproduce:** across that host's 192 `fft` rows (four lanes × 48) against its 2026-07-22 archive, exactly **one** row at ``256^3`` moved slower and by +1.0%, where `Enteropia` moved +38%; per-lane medians run −4.5% to −6.8%. Twenty-three rows did move slower, but all except that one sit at ``64^3``/``128^3``, and the three exceeding 20% are small-grid high-thread-count cells where thread overhead dominates a sub-millisecond workload. This host's rows moved materially *faster* at the larger grids (up to a ratio of 0.54), which is no better explained, so a cross-vintage `fft` comparison is uninformative rather than evidence. `Aiporetne` runs kernel `7.0.0-28-generic`, the same version `Enteropia` recorded post-reboot, so a platform-wide kernel or microcode regression is not supported. **The 2026-08-09 `Enteropia` re-sweep settles it: the shift was a ONE-OFF, not a persistent state change.** Re-measuring t1/t2/t4 against the 2026-08-05 archive over an interval with no source changes, the `fft` class is flat — per-lane medians −1.1% to −1.4%, and at ``256^3`` specifically −3.7%, −6.5% and −1.2%, where the event being explained was +20–50%. Every other class is flat too (600 rows per lane, overall medians +0.0%, −0.2%, −0.2%), so the sweep reproduces itself and the instrument is sound. Those three lanes are also the first archives carrying stamped platform state (kernel, microcode, governor, SMT, transparent huge pages), so a recurrence is now falsifiable instead of unattributable. See PERFORMANCE.md §4(p). **Five CPU rows are process-history-sensitive and comparable only against same-shaped sweeps — PERFORMANCE.md §4(y).** The two `materialize_kernel` rows, `lpnorm vec Inf`, `radial_correlation vec` and `cross-correlation vec.vec` measure faster at low thread counts inside a full sweep than standalone (up to ``3.2\times`` for `materialize_kernel` at ``t1``, ``1.2``–``1.7\times`` for the reductions three), because their per-call field-sized allocation lands in a regime selected by what streamed through the process before them; the eight allocating `fft` rows are verified clean. Every CPU column here is a full sweep, so the table is self-consistent, but those cells must not be compared against a standalone probe or a class-only lane, and `materialize_kernel` thread scaling should be read from ``t4`` upward (the ``t2`` cell of `materialize_kernel separable` is bistable across sweeps). **The `CPU 9800X3D t8` column was assembled from FOUR per-grid runs, not one lane.** A single `-t8` process segfaults on `Enteropia` inside FFTW's threaded executor — PERFORMANCE.md §4(q), reproducible there and never seen on the other host — and failed three times running. Splitting the lane by grid (`CHAR_SIZES=64`, then 128, 256, 512) completes it: 64³, 256³ and 512³ passed first time and 128³ on its second attempt, and the four part-archives merge into one lane archive with disjoint rows, 150 per grid. That is what an uncrashed process would have written, and it is a harness workaround rather than a fix — the fault is unchanged and a plain `characterize.jl` invocation at `-t8` will still die here. The merged column is flat against the 2026-08-05 one it replaces (median +0.0% over 600 rows), and its largest movers are the `measure` twins, whose FFTW `MEASURE` plan search legitimately re-decides between runs. **The `ordered` transfer rows are REPAIRED in the `Enteropia` columns and STALE in `Aiporetne`'s — PERFORMANCE.md finding (ak).** Those rows time a transfer that follows a `point_traversal_order`, and until 2026-08-31 the benchmark shared ONE point set between them and the `displace!`/`wrap!` rows, which mutate positions in place. The visit order was built at setup and the motion rows then moved the points out from under it — thousands of times, since `tune!`, the device `gcsample` probe and `run` each execute every row — so the ordered rows timed a valid permutation that no longer described where the points were. The four `CPU 9800X3D` columns and `GPU 5070TI` were re-measured with the fixed harness and their `transfer` class spliced in (`benchmark/replace_class.jl`, every untouched row verified bit-identical); the four `CPU 12700K` columns and `GPU 7900XTX` still carry the defect and read as a LOSS of roughly 10–25% where the option in fact saves ``2``–``4\times``, so **ignore the `ordered` cells in those five columns** until that host re-measures. The UNORDERED rows were never affected — drifted-then-wrapped positions are as uniformly distributed as fresh ones — so every other cell in the class is sound, and that is exactly why the defect survived: the baseline each ordered row is compared against was correct throughout. **Jitter at ``256^3`` is NOT bounded by the ~10% the paragraph above suggests, for the `Float32` gather rows.** `interpolate! trilinear`, `CatmullRom` and `Lalescu(3,3)` at ``256^3`` `Float32` move as a CORRELATED BLOCK between processes — all three the same direction within a run, by up to 31% — measured on the 9800X3D as ``0.73``/``0.82``/``0.86`` at `t1` and ``1.31``/``1.22``/``1.17`` at `t2` for the same code against the same archive. Direction varies by run, so it is per-process state rather than a systematic difference, but the standing advice to compare at ``256^3`` or above does not cover these three rows: read them across at least two sweeps. A row may name an operation the package has since REMOVED — `squared_wavenumber_field` was deleted by decision 60, its |k|² being a radial symbol rather than a field.Such rows are a historical measurement, not a callable surface, and they disappear the next time their lane is swept. The GPU sweep builds one (op-class, grid, element-type) at a time so the working set stays bounded (PERFORMANCE.md §7). **Regenerate** by re-sweeping the lanes you can measure — `characterize.jl` once per lane — and then invoking `report.jl` by hand over **every** archive in `benchmark/results/`, this table's own column list included. Do not use `characterize.sh` for a multi-host report: it passes only the lanes it just produced to `report.jl`, so the columns belonging to the other host and to retired cards would silently vanish (PERFORMANCE.md §6). **Column vintages** — the commit (and sweep date) each archive was measured at, stamped into its JSON by `characterize.jl`: `6581b433 @ 2026-08-31`: CPU 9800X3D t1, CPU 9800X3D t2, CPU 9800X3D t4, CPU 9800X3D t8, GPU 5070TI; `b452fb17 @ 2026-08-31`: CPU 12700K t1, CPU 12700K t2, CPU 12700K t4, CPU 12700K t8, GPU 7900XTX. **Jitter is ~10% for most cells but NOT uniform: it reaches 1.44x at small grids under high thread counts.** Measured on the 12700K, `mean(norm) vec` `Float32`, five repeats of the same measurement: at ``64^3`` `-t8` the minimum came out 31.2, 31.0, 31.3, 30.8 and 44.4 us, where the same row at `-t1` spans 1.01x and at ``256^3`` `-t8` spans 1.09x. The work there (~31 us) is comparable to the cost of spawning eight threads, and taking BenchmarkTools' minimum over a one-second budget does not suppress it. So a movement of tens of percent in a small-grid, high-thread cell is NOT evidence of anything; compare those at ``256^3`` or above, or at low thread counts. PERFORMANCE.md §4(u).

## fft

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| to_physical scalar measure | Float32 128^3 | 3.849 ms | 2.686 ms | 2.202 ms | 2.126 ms | 2.741 ms | 1.470 ms | 826.698 μs | 526.025 μs | — | — |
| to_physical scalar measure | Float32 256^3 | 40.797 ms | 28.297 ms | 24.536 ms | 23.250 ms | 32.865 ms | 20.339 ms | 14.660 ms | 11.720 ms | — | — |
| to_physical scalar measure | Float32 512^3 | 522.625 ms | 415.796 ms | 255.717 ms | 223.327 ms | 470.885 ms | 292.836 ms | 221.111 ms | 197.481 ms | — | — |
| to_physical scalar measure | Float32 64^3 | 373.521 μs | 234.963 μs | 163.227 μs | 162.793 μs | 276.223 μs | 157.201 μs | 95.731 μs | 71.040 μs | — | — |
| to_physical scalar measure | Float64 128^3 | 6.058 ms | 5.501 ms | 5.203 ms | 4.810 ms | 3.854 ms | 2.249 ms | 1.650 ms | 1.202 ms | — | — |
| to_physical scalar measure | Float64 256^3 | 129.321 ms | 65.831 ms | 75.893 ms | 50.317 ms | 83.575 ms | 65.252 ms | 41.326 ms | 45.523 ms | — | — |
| to_physical scalar measure | Float64 512^3 | 1.114 s | 763.282 ms | 654.987 ms | 607.848 ms | 832.369 ms | 553.215 ms | 441.802 ms | 401.231 ms | — | — |
| to_physical scalar measure | Float64 64^3 | 531.060 μs | 333.897 μs | 249.645 μs | 256.156 μs | 363.403 μs | 206.932 μs | 131.771 μs | 104.641 μs | — | — |
| to_physical scalar | Float32 128^3 | 4.912 ms | 3.277 ms | 2.330 ms | 2.113 ms | 4.515 ms | 2.467 ms | 1.290 ms | 774.129 μs | 107.756 μs | 68.131 μs |
| to_physical scalar | Float32 256^3 | 89.262 ms | 50.408 ms | 34.257 ms | 27.357 ms | 169.531 ms | 88.437 ms | 48.038 ms | 27.683 ms | 1.020 ms | 1.101 ms |
| to_physical scalar | Float32 512^3 | 1.324 s | 805.904 ms | 509.457 ms | 310.679 ms | 2.091 s | 1.111 s | 628.272 ms | 390.847 ms | 13.622 ms | — |
| to_physical scalar | Float32 64^3 | 386.352 μs | 245.492 μs | 171.126 μs | 164.720 μs | 313.063 μs | 176.522 μs | 101.081 μs | 70.561 μs | 64.752 μs | 19.910 μs |
| to_physical scalar | Float64 128^3 | 7.782 ms | 5.632 ms | 4.881 ms | 4.420 ms | 10.220 ms | 5.748 ms | 3.240 ms | 1.832 ms | 297.088 μs | 430.765 μs |
| to_physical scalar | Float64 256^3 | 144.593 ms | 77.139 ms | 79.237 ms | 51.609 ms | 96.212 ms | 73.588 ms | 43.827 ms | 46.465 ms | 2.893 ms | 3.769 ms |
| to_physical scalar | Float64 512^3 | 1.514 s | 940.382 ms | 707.374 ms | 628.036 ms | 929.667 ms | 600.455 ms | 448.057 ms | 398.602 ms | — | — |
| to_physical scalar | Float64 64^3 | 678.177 μs | 406.696 μs | 282.611 μs | 270.809 μs | 541.035 μs | 285.503 μs | 167.101 μs | 119.981 μs | 82.978 μs | 51.691 μs |
| to_physical vector measure | Float32 128^3 | 11.477 ms | 8.435 ms | 7.402 ms | 6.363 ms | 9.154 ms | 5.602 ms | 3.467 ms | 2.856 ms | — | — |
| to_physical vector measure | Float32 256^3 | 203.555 ms | 127.495 ms | 118.558 ms | 77.735 ms | 137.574 ms | 102.731 ms | 77.814 ms | 65.963 ms | — | — |
| to_physical vector measure | Float32 512^3 | 1.845 s | 1.240 s | 989.555 ms | 879.546 ms | 1.413 s | 879.623 ms | 667.473 ms | 606.716 ms | — | — |
| to_physical vector measure | Float32 64^3 | 1.143 ms | 710.555 μs | 519.722 μs | 518.762 μs | 838.729 μs | 495.995 μs | 287.572 μs | 222.152 μs | — | — |
| to_physical vector measure | Float64 128^3 | 37.148 ms | 30.729 ms | 27.108 ms | 24.746 ms | 27.389 ms | 18.895 ms | 14.290 ms | 12.655 ms | — | — |
| to_physical vector measure | Float64 256^3 | 383.590 ms | 263.117 ms | 224.846 ms | 214.701 ms | 306.744 ms | 207.171 ms | 154.652 ms | 139.071 ms | — | — |
| to_physical vector measure | Float64 512^3 | 3.331 s | 2.288 s | 1.945 s | 1.828 s | 2.500 s | 1.667 s | 1.291 s | 1.165 s | — | — |
| to_physical vector measure | Float64 64^3 | 1.919 ms | 1.577 ms | 1.235 ms | 1.171 ms | 1.120 ms | 658.326 μs | 408.014 μs | 330.304 μs | — | — |
| to_physical vector | Float32 128^3 | 11.535 ms | 8.305 ms | 7.421 ms | 6.433 ms | 9.295 ms | 5.558 ms | 3.494 ms | 2.925 ms | 332.786 μs | 230.012 μs |
| to_physical vector | Float32 256^3 | 202.811 ms | 127.094 ms | 118.999 ms | 81.053 ms | 138.275 ms | 105.406 ms | 75.964 ms | 64.894 ms | 4.697 ms | 3.227 ms |
| to_physical vector | Float32 512^3 | 1.847 s | 1.241 s | 991.555 ms | 881.910 ms | 1.386 s | 876.509 ms | 665.338 ms | 605.880 ms | 56.118 ms | — |
| to_physical vector | Float32 64^3 | 1.141 ms | 714.854 μs | 529.212 μs | 569.221 μs | 845.299 μs | 480.115 μs | 288.233 μs | 224.932 μs | 100.824 μs | 45.160 μs |
| to_physical vector | Float64 128^3 | 37.143 ms | 30.903 ms | 26.962 ms | 24.825 ms | 27.376 ms | 18.902 ms | 14.200 ms | 13.114 ms | 959.148 μs | 1.352 ms |
| to_physical vector | Float64 256^3 | 385.131 ms | 263.300 ms | 223.799 ms | 215.652 ms | 298.434 ms | 204.938 ms | 155.768 ms | 139.525 ms | 13.411 ms | 11.385 ms |
| to_physical vector | Float64 512^3 | 3.320 s | 2.289 s | 1.950 s | 1.836 s | 2.488 s | 1.673 s | 1.288 s | 1.163 s | — | — |
| to_physical vector | Float64 64^3 | 1.920 ms | 1.576 ms | 1.175 ms | 1.173 ms | 1.114 ms | 685.977 μs | 399.914 μs | 335.193 μs | 200.715 μs | 145.492 μs |
| to_physical! scalar scratch | Float32 128^3 | 4.345 ms | 2.666 ms | 1.727 ms | 1.273 ms | 4.497 ms | 2.482 ms | 1.266 ms | 778.209 μs | 97.751 μs | 65.141 μs |
| to_physical! scalar scratch | Float32 256^3 | 89.540 ms | 49.698 ms | 33.134 ms | 26.674 ms | 166.684 ms | 87.438 ms | 46.212 ms | 25.776 ms | 804.696 μs | 1.029 ms |
| to_physical! scalar scratch | Float32 512^3 | 1.215 s | 657.139 ms | 405.286 ms | 287.202 ms | 1.967 s | 1.025 s | 555.355 ms | 325.957 ms | 10.198 ms | — |
| to_physical! scalar scratch | Float32 64^3 | 386.711 μs | 240.700 μs | 164.159 μs | 134.132 μs | 317.243 μs | 171.262 μs | 100.741 μs | 70.591 μs | 45.853 μs | 17.731 μs |
| to_physical! scalar scratch | Float64 128^3 | 7.819 ms | 4.922 ms | 4.055 ms | 3.541 ms | 9.717 ms | 5.018 ms | 2.721 ms | 1.579 ms | 258.440 μs | 427.915 μs |
| to_physical! scalar scratch | Float64 256^3 | 104.784 ms | 70.659 ms | 55.125 ms | 49.804 ms | 81.387 ms | 50.470 ms | 35.438 ms | 29.930 ms | 2.482 ms | 3.769 ms |
| to_physical! scalar scratch | Float64 512^3 | 1.134 s | 677.362 ms | 508.082 ms | 437.909 ms | 702.588 ms | 434.304 ms | 310.934 ms | 271.286 ms | — | — |
| to_physical! scalar scratch | Float64 64^3 | 651.088 μs | 394.454 μs | 278.650 μs | 235.994 μs | 528.076 μs | 288.003 μs | 167.142 μs | 118.271 μs | 70.934 μs | 49.620 μs |
| to_physical! scalar | Float32 128^3 | 3.986 ms | 2.186 ms | 1.214 ms | 764.930 μs | 4.370 ms | 2.252 ms | 1.132 ms | 620.057 μs | 86.460 μs | 58.870 μs |
| to_physical! scalar | Float32 256^3 | 85.412 ms | 45.809 ms | 29.239 ms | 22.469 ms | 164.478 ms | 83.934 ms | 42.697 ms | 22.781 ms | 638.820 μs | 850.858 μs |
| to_physical! scalar | Float32 512^3 | 1.183 s | 627.556 ms | 375.473 ms | 259.204 ms | 1.950 s | 1.005 s | 529.932 ms | 299.536 ms | 8.802 ms | — |
| to_physical! scalar | Float32 64^3 | 352.906 μs | 200.317 μs | 120.259 μs | 90.324 μs | 298.413 μs | 155.592 μs | 84.671 μs | 54.211 μs | 39.062 μs | 16.041 μs |
| to_physical! scalar | Float64 128^3 | 6.436 ms | 3.598 ms | 2.566 ms | 1.966 ms | 9.736 ms | 4.800 ms | 2.475 ms | 1.318 ms | 234.152 μs | 398.034 μs |
| to_physical! scalar | Float64 256^3 | 96.895 ms | 63.281 ms | 47.066 ms | 42.069 ms | 72.113 ms | 41.029 ms | 25.977 ms | 19.805 ms | 2.152 ms | 3.414 ms |
| to_physical! scalar | Float64 512^3 | 1.078 s | 623.138 ms | 447.941 ms | 380.863 ms | 654.203 ms | 380.884 ms | 257.571 ms | 217.113 ms | — | — |
| to_physical! scalar | Float64 64^3 | 575.705 μs | 325.109 μs | 202.053 μs | 146.136 μs | 496.455 μs | 257.522 μs | 139.042 μs | 86.831 μs | 68.085 μs | 47.601 μs |
| to_physical! vector scratch | Float32 128^3 | 11.342 ms | 7.925 ms | 6.564 ms | 5.887 ms | 8.169 ms | 4.452 ms | 2.564 ms | 1.622 ms | 277.406 μs | 229.302 μs |
| to_physical! vector scratch | Float32 256^3 | 123.800 ms | 83.723 ms | 73.460 ms | 69.804 ms | 109.554 ms | 63.699 ms | 45.443 ms | 38.446 ms | 2.305 ms | 3.079 ms |
| to_physical! vector scratch | Float32 512^3 | 1.366 s | 887.446 ms | 701.243 ms | 610.234 ms | 950.944 ms | 560.095 ms | 428.103 ms | 388.272 ms | 28.928 ms | — |
| to_physical! vector scratch | Float32 64^3 | 1.138 ms | 684.027 μs | 462.847 μs | 411.719 μs | 844.139 μs | 471.465 μs | 286.313 μs | 224.302 μs | 80.458 μs | 42.261 μs |
| to_physical! vector scratch | Float64 128^3 | 18.689 ms | 17.612 ms | 15.680 ms | 14.362 ms | 14.385 ms | 8.749 ms | 5.818 ms | 4.548 ms | 802.076 μs | 1.353 ms |
| to_physical! vector scratch | Float64 256^3 | 252.305 ms | 189.082 ms | 153.494 ms | 142.360 ms | 206.563 ms | 132.204 ms | 98.447 ms | 87.833 ms | 7.467 ms | 11.287 ms |
| to_physical! vector scratch | Float64 512^3 | 2.171 s | 1.502 s | 1.315 s | 1.256 s | 1.712 s | 1.102 s | 861.969 ms | 770.124 ms | — | — |
| to_physical! vector scratch | Float64 64^3 | 1.612 ms | 999.461 μs | 761.370 μs | 705.115 μs | 1.088 ms | 636.316 μs | 379.794 μs | 320.603 μs | 189.797 μs | 142.071 μs |
| to_physical! vector | Float32 128^3 | 9.819 ms | 6.274 ms | 4.956 ms | 3.933 ms | 7.741 ms | 4.056 ms | 2.146 ms | 1.204 ms | 247.730 μs | 187.692 μs |
| to_physical! vector | Float32 256^3 | 111.586 ms | 72.350 ms | 62.342 ms | 59.007 ms | 102.650 ms | 51.708 ms | 34.841 ms | 27.418 ms | 1.856 ms | 2.551 ms |
| to_physical! vector | Float32 512^3 | 1.275 s | 802.821 ms | 613.507 ms | 521.241 ms | 869.878 ms | 485.420 ms | 352.148 ms | 313.204 ms | 24.721 ms | — |
| to_physical! vector | Float32 64^3 | 1.029 ms | 574.739 μs | 350.659 μs | 288.042 μs | 804.218 μs | 424.804 μs | 244.942 μs | 177.722 μs | 82.049 μs | 40.310 μs |
| to_physical! vector | Float64 128^3 | 15.945 ms | 13.980 ms | 12.454 ms | 11.432 ms | 12.715 ms | 7.144 ms | 4.127 ms | 2.547 ms | 728.705 μs | 1.217 ms |
| to_physical! vector | Float64 256^3 | 229.655 ms | 166.031 ms | 129.620 ms | 118.949 ms | 186.633 ms | 110.856 ms | 76.230 ms | 68.368 ms | 6.452 ms | 10.229 ms |
| to_physical! vector | Float64 512^3 | 2.002 s | 1.340 s | 1.148 s | 1.087 s | 1.560 s | 955.105 ms | 721.959 ms | 620.863 ms | — | — |
| to_physical! vector | Float64 64^3 | 1.342 ms | 767.495 μs | 509.221 μs | 475.343 μs | 1.006 ms | 560.975 μs | 304.343 μs | 218.172 μs | 165.869 μs | 137.522 μs |
| to_spectral scalar measure | Float32 128^3 | 3.322 ms | 2.044 ms | 1.664 ms | 1.182 ms | 2.685 ms | 1.437 ms | 800.378 μs | 462.585 μs | — | — |
| to_spectral scalar measure | Float32 256^3 | 34.882 ms | 22.778 ms | 19.983 ms | 18.141 ms | 35.394 ms | 19.824 ms | 13.714 ms | 10.635 ms | — | — |
| to_spectral scalar measure | Float32 512^3 | 474.220 ms | 376.988 ms | 229.087 ms | 194.879 ms | 451.337 ms | 268.337 ms | 192.895 ms | 166.208 ms | — | — |
| to_spectral scalar measure | Float32 64^3 | 361.970 μs | 202.537 μs | 144.062 μs | 106.818 μs | 271.472 μs | 145.871 μs | 85.341 μs | 61.531 μs | — | — |
| to_spectral scalar measure | Float64 128^3 | 5.126 ms | 4.553 ms | 3.842 ms | 3.288 ms | 3.892 ms | 2.367 ms | 1.339 ms | 1.195 ms | — | — |
| to_spectral scalar measure | Float64 256^3 | 118.676 ms | 58.365 ms | 67.470 ms | 40.462 ms | 76.259 ms | 59.437 ms | 37.132 ms | 38.240 ms | — | — |
| to_spectral scalar measure | Float64 512^3 | 1.050 s | 716.970 ms | 562.584 ms | 515.686 ms | 748.122 ms | 491.860 ms | 365.948 ms | 332.342 ms | — | — |
| to_spectral scalar measure | Float64 64^3 | 476.706 μs | 283.888 μs | 184.040 μs | 197.552 μs | 347.013 μs | 192.922 μs | 108.801 μs | 81.090 μs | — | — |
| to_spectral scalar | Float32 128^3 | 4.389 ms | 2.732 ms | 1.709 ms | 1.271 ms | 4.636 ms | 2.402 ms | 1.254 ms | 722.728 μs | 67.467 μs | 40.670 μs |
| to_spectral scalar | Float32 256^3 | 86.061 ms | 48.399 ms | 29.297 ms | 22.684 ms | 169.465 ms | 87.023 ms | 46.184 ms | 26.272 ms | 688.361 μs | 681.007 μs |
| to_spectral scalar | Float32 512^3 | 1.287 s | 767.654 ms | 469.683 ms | 348.311 ms | 2.079 s | 1.093 s | 596.845 ms | 356.814 ms | 9.398 ms | — |
| to_spectral scalar | Float32 64^3 | 364.196 μs | 207.950 μs | 141.212 μs | 142.104 μs | 303.693 μs | 163.862 μs | 91.541 μs | 59.470 μs | 51.056 μs | 14.490 μs |
| to_spectral scalar | Float64 128^3 | 7.094 ms | 5.235 ms | 4.247 ms | 3.397 ms | 10.074 ms | 5.423 ms | 2.980 ms | 1.961 ms | 238.752 μs | 381.024 μs |
| to_spectral scalar | Float64 256^3 | 164.365 ms | 81.776 ms | 74.508 ms | 42.752 ms | 189.509 ms | 116.399 ms | 62.541 ms | 52.773 ms | 2.168 ms | 3.080 ms |
| to_spectral scalar | Float64 512^3 | 1.641 s | 947.525 ms | 652.887 ms | 538.398 ms | 1.705 s | 966.768 ms | 578.855 ms | 428.255 ms | — | — |
| to_spectral scalar | Float64 64^3 | 622.418 μs | 357.888 μs | 230.161 μs | 174.994 μs | 511.795 μs | 271.733 μs | 152.282 μs | 95.551 μs | 77.587 μs | 45.430 μs |
| to_spectral vector measure | Float32 128^3 | 10.205 ms | 7.035 ms | 5.595 ms | 4.768 ms | 9.426 ms | 5.215 ms | 3.087 ms | 2.342 ms | — | — |
| to_spectral vector measure | Float32 256^3 | 185.611 ms | 100.268 ms | 103.016 ms | 60.680 ms | 140.353 ms | 99.201 ms | 71.275 ms | 58.785 ms | — | — |
| to_spectral vector measure | Float32 512^3 | 1.709 s | 1.131 s | 843.169 ms | 733.681 ms | 1.338 s | 804.527 ms | 574.464 ms | 511.137 ms | — | — |
| to_spectral vector measure | Float32 64^3 | 1.098 ms | 629.201 μs | 394.511 μs | 372.960 μs | 825.738 μs | 444.974 μs | 254.563 μs | 186.812 μs | — | — |
| to_spectral vector measure | Float64 128^3 | 34.065 ms | 26.414 ms | 22.202 ms | 19.841 ms | 27.344 ms | 18.613 ms | 14.080 ms | 12.576 ms | — | — |
| to_spectral vector measure | Float64 256^3 | 351.014 ms | 240.615 ms | 197.552 ms | 183.621 ms | 275.949 ms | 181.730 ms | 136.881 ms | 116.291 ms | — | — |
| to_spectral vector measure | Float64 512^3 | 3.150 s | 2.157 s | 1.690 s | 1.554 s | 2.212 s | 1.452 s | 1.106 s | 960.812 ms | — | — |
| to_spectral vector measure | Float64 64^3 | 1.648 ms | 1.061 ms | 841.636 μs | 664.449 μs | 1.045 ms | 608.536 μs | 331.503 μs | 257.183 μs | — | — |
| to_spectral vector | Float32 128^3 | 10.215 ms | 7.069 ms | 5.651 ms | 4.625 ms | 9.391 ms | 5.131 ms | 3.021 ms | 2.830 ms | 207.353 μs | 157.442 μs |
| to_spectral vector | Float32 256^3 | 186.209 ms | 100.346 ms | 102.712 ms | 62.093 ms | 142.580 ms | 98.693 ms | 72.328 ms | 59.016 ms | 2.952 ms | 2.108 ms |
| to_spectral vector | Float32 512^3 | 1.704 s | 1.129 s | 850.130 ms | 741.775 ms | 1.334 s | 806.638 ms | 578.991 ms | 520.876 ms | 45.159 ms | — |
| to_spectral vector | Float32 64^3 | 1.093 ms | 625.749 μs | 457.696 μs | 388.427 μs | 830.748 μs | 437.094 μs | 255.833 μs | 191.842 μs | 67.076 μs | 30.041 μs |
| to_spectral vector | Float64 128^3 | 34.397 ms | 25.811 ms | 22.119 ms | 20.238 ms | 28.464 ms | 18.736 ms | 13.610 ms | 12.296 ms | 909.655 μs | 1.159 ms |
| to_spectral vector | Float64 256^3 | 350.447 ms | 239.468 ms | 196.947 ms | 199.354 ms | 280.845 ms | 183.201 ms | 133.491 ms | 115.841 ms | 11.785 ms | 9.237 ms |
| to_spectral vector | Float64 512^3 | 3.149 s | 2.166 s | 1.695 s | 1.558 s | 2.185 s | 1.447 s | 1.104 s | 967.678 ms | — | — |
| to_spectral vector | Float64 64^3 | 1.644 ms | 1.033 ms | 886.816 μs | 676.871 μs | 1.046 ms | 585.756 μs | 331.263 μs | 249.523 μs | 178.740 μs | 125.131 μs |

## algebra

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| add! scalar | Float32 128^3 | 464.189 μs | 241.643 μs | 170.288 μs | 75.674 μs | 162.312 μs | 84.191 μs | 44.031 μs | 35.670 μs | 60.750 μs | 34.360 μs |
| add! scalar | Float32 256^3 | 8.072 ms | 7.349 ms | 5.627 ms | 5.159 ms | 3.481 ms | 3.003 ms | 2.759 ms | 2.805 ms | 345.734 μs | 273.212 μs |
| add! scalar | Float32 512^3 | 66.777 ms | 62.182 ms | 48.736 ms | 45.554 ms | 40.662 ms | 36.891 ms | 36.798 ms | 37.219 ms | 2.547 ms | — |
| add! scalar | Float32 64^3 | 41.989 μs | 21.308 μs | 10.490 μs | 8.381 μs | 20.470 μs | 12.250 μs | 7.080 μs | 6.897 μs | 31.115 μs | 10.190 μs |
| add! scalar | Float64 128^3 | 1.458 ms | 1.289 ms | 965.313 μs | 798.914 μs | 324.114 μs | 164.221 μs | 86.110 μs | 72.861 μs | 61.324 μs | 38.570 μs |
| add! scalar | Float64 256^3 | 16.778 ms | 15.318 ms | 11.770 ms | 10.882 ms | 10.258 ms | 8.539 ms | 8.442 ms | 8.567 ms | 538.575 μs | 511.885 μs |
| add! scalar | Float64 512^3 | 136.296 ms | 124.752 ms | 97.623 ms | 91.103 ms | 83.871 ms | 72.244 ms | 73.742 ms | 74.035 ms | — | — |
| add! scalar | Float64 64^3 | 83.749 μs | 48.434 μs | 21.002 μs | 18.284 μs | 40.200 μs | 22.700 μs | 12.170 μs | 9.420 μs | 32.460 μs | 10.160 μs |
| combine! vec | Float32 128^3 | 2.592 ms | 2.341 ms | 1.812 ms | 1.597 ms | 650.586 μs | 315.543 μs | 167.392 μs | 115.561 μs | 187.145 μs | 131.502 μs |
| combine! vec | Float32 256^3 | 25.371 ms | 23.173 ms | 18.239 ms | 16.939 ms | 13.661 ms | 13.987 ms | 13.429 ms | 13.769 ms | 1.370 ms | 966.100 μs |
| combine! vec | Float32 512^3 | 199.285 ms | 183.944 ms | 147.781 ms | 138.044 ms | 114.404 ms | 110.351 ms | 110.841 ms | 111.140 ms | 11.384 ms | — |
| combine! vec | Float32 64^3 | 127.247 μs | 68.966 μs | 38.204 μs | 23.887 μs | 62.761 μs | 38.750 μs | 20.000 μs | 14.851 μs | 46.583 μs | 22.130 μs |
| combine! vec | Float64 128^3 | 5.922 ms | 5.397 ms | 4.136 ms | 3.743 ms | 2.205 ms | 1.778 ms | 1.581 ms | 1.490 ms | 229.399 μs | 193.102 μs |
| combine! vec | Float64 256^3 | 49.781 ms | 46.459 ms | 36.850 ms | 34.136 ms | 28.681 ms | 26.750 ms | 27.113 ms | 27.444 ms | 1.633 ms | 1.533 ms |
| combine! vec | Float64 512^3 | 410.015 ms | 376.163 ms | 293.283 ms | 274.556 ms | 233.665 ms | 217.929 ms | 220.731 ms | 221.675 ms | — | — |
| combine! vec | Float64 64^3 | 266.344 μs | 144.196 μs | 76.736 μs | 44.749 μs | 123.461 μs | 64.171 μs | 34.581 μs | 28.270 μs | 48.989 μs | 22.201 μs |
| cross! | Float32 128^3 | 2.904 ms | 2.446 ms | 2.118 ms | 1.972 ms | 2.017 ms | 993.451 μs | 499.146 μs | 249.073 μs | 51.723 μs | 85.151 μs |
| cross! | Float32 256^3 | 27.540 ms | 25.053 ms | 23.535 ms | 22.525 ms | 23.285 ms | 14.622 ms | 12.569 ms | 12.632 ms | 861.196 μs | 771.408 μs |
| cross! | Float32 512^3 | 209.709 ms | 198.953 ms | 190.898 ms | 184.836 ms | 174.385 ms | 121.423 ms | 110.867 ms | 110.566 ms | 6.974 ms | — |
| cross! | Float32 64^3 | 255.382 μs | 129.347 μs | 69.829 μs | 38.393 μs | 230.892 μs | 115.981 μs | 58.990 μs | 32.890 μs | 35.914 μs | 9.070 μs |
| cross! | Float64 128^3 | 6.273 ms | 5.760 ms | 5.112 ms | 4.870 ms | 3.783 ms | 2.303 ms | 1.586 ms | 1.477 ms | 230.485 μs | 196.411 μs |
| cross! | Float64 256^3 | 52.122 ms | 49.341 ms | 47.594 ms | 45.538 ms | 42.187 ms | 30.200 ms | 27.441 ms | 27.531 ms | 1.632 ms | 1.539 ms |
| cross! | Float64 512^3 | 414.323 ms | 405.884 ms | 382.892 ms | 367.833 ms | 334.645 ms | 231.727 ms | 222.479 ms | 224.392 ms | — | — |
| cross! | Float64 64^3 | 364.260 μs | 184.366 μs | 95.676 μs | 54.145 μs | 224.912 μs | 115.441 μs | 58.710 μs | 36.810 μs | 41.047 μs | 14.790 μs |
| det! tensor | Float32 128^3 | 3.279 ms | 2.377 ms | 1.965 ms | 1.804 ms | 2.168 ms | 1.086 ms | 546.435 μs | 287.303 μs | 74.739 μs | 101.961 μs |
| det! tensor | Float32 256^3 | 34.194 ms | 25.570 ms | 22.475 ms | 19.985 ms | 32.872 ms | 15.652 ms | 12.173 ms | 11.999 ms | 920.132 μs | 826.488 μs |
| det! tensor | Float32 512^3 | 268.724 ms | 203.766 ms | 182.164 ms | 164.318 ms | 230.659 ms | 124.103 ms | 104.614 ms | 103.552 ms | 7.709 ms | — |
| det! tensor | Float32 64^3 | 304.925 μs | 156.619 μs | 82.412 μs | 46.730 μs | 250.702 μs | 128.311 μs | 66.000 μs | 36.211 μs | 41.421 μs | 10.880 μs |
| det! tensor | Float64 128^3 | 6.835 ms | 5.852 ms | 4.777 ms | 4.191 ms | 4.019 ms | 2.384 ms | 1.676 ms | 1.618 ms | 255.585 μs | 197.562 μs |
| det! tensor | Float64 256^3 | 50.841 ms | 48.521 ms | 43.046 ms | 39.629 ms | 41.921 ms | 29.273 ms | 25.581 ms | 25.577 ms | 1.758 ms | 1.697 ms |
| det! tensor | Float64 512^3 | 373.343 ms | 395.860 ms | 343.608 ms | 317.568 ms | 426.193 ms | 273.463 ms | 213.736 ms | 211.173 ms | — | — |
| det! tensor | Float64 64^3 | 353.979 μs | 185.662 μs | 105.239 μs | 60.320 μs | 253.982 μs | 130.311 μs | 68.020 μs | 42.710 μs | 43.859 μs | 16.210 μs |
| dot! vec.vec | Float32 128^3 | 2.766 ms | 1.661 ms | 1.263 ms | 1.086 ms | 2.448 ms | 1.246 ms | 629.007 μs | 319.764 μs | 84.348 μs | 71.461 μs |
| dot! vec.vec | Float32 256^3 | 24.090 ms | 17.216 ms | 15.410 ms | 14.090 ms | 25.653 ms | 12.291 ms | 8.242 ms | 8.076 ms | 649.245 μs | 610.146 μs |
| dot! vec.vec | Float32 512^3 | 196.167 ms | 135.120 ms | 124.691 ms | 115.329 ms | 167.955 ms | 98.806 ms | 75.324 ms | 75.779 ms | 5.194 ms | — |
| dot! vec.vec | Float32 64^3 | 328.592 μs | 201.330 μs | 104.465 μs | 59.563 μs | 310.603 μs | 159.572 μs | 81.561 μs | 44.430 μs | 35.128 μs | 13.470 μs |
| dot! vec.vec | Float64 128^3 | 4.318 ms | 3.785 ms | 3.109 ms | 2.847 ms | 3.460 ms | 1.728 ms | 889.959 μs | 583.297 μs | 174.384 μs | 134.141 μs |
| dot! vec.vec | Float64 256^3 | 38.290 ms | 34.620 ms | 29.432 ms | 27.060 ms | 32.800 ms | 19.903 ms | 18.548 ms | 18.083 ms | 1.218 ms | 1.157 ms |
| dot! vec.vec | Float64 512^3 | 293.199 ms | 279.043 ms | 232.350 ms | 216.898 ms | 257.743 ms | 158.990 ms | 149.721 ms | 150.451 ms | — | — |
| dot! vec.vec | Float64 64^3 | 335.816 μs | 204.763 μs | 105.660 μs | 63.560 μs | 318.913 μs | 160.472 μs | 81.921 μs | 44.891 μs | 35.624 μs | 13.840 μs |
| map!(+) vec | Float32 128^3 | 2.877 ms | 2.473 ms | 2.156 ms | 1.969 ms | 1.765 ms | 844.519 μs | 419.374 μs | 206.412 μs | 52.201 μs | 79.221 μs |
| map!(+) vec | Float32 256^3 | 27.368 ms | 25.021 ms | 23.375 ms | 22.334 ms | 21.947 ms | 14.284 ms | 12.654 ms | 12.714 ms | 860.798 μs | 772.308 μs |
| map!(+) vec | Float32 512^3 | 207.163 ms | 198.981 ms | 190.838 ms | 184.352 ms | 159.353 ms | 118.575 ms | 110.697 ms | 110.538 ms | 7.207 ms | — |
| map!(+) vec | Float32 64^3 | 247.203 μs | 129.892 μs | 68.550 μs | 37.706 μs | 199.441 μs | 95.671 μs | 48.730 μs | 27.090 μs | 35.959 μs | 9.021 μs |
| map!(+) vec | Float64 128^3 | 6.217 ms | 5.723 ms | 5.151 ms | 4.875 ms | 3.654 ms | 2.268 ms | 1.571 ms | 1.490 ms | 230.168 μs | 196.502 μs |
| map!(+) vec | Float64 256^3 | 51.742 ms | 49.288 ms | 47.307 ms | 45.451 ms | 40.105 ms | 29.720 ms | 27.332 ms | 27.585 ms | 1.628 ms | 1.539 ms |
| map!(+) vec | Float64 512^3 | 410.128 ms | 405.185 ms | 381.510 ms | 367.835 ms | 318.480 ms | 226.374 ms | 221.774 ms | 222.455 ms | — | — |
| map!(+) vec | Float64 64^3 | 351.520 μs | 188.241 μs | 98.971 μs | 54.128 μs | 175.262 μs | 94.001 μs | 48.500 μs | 33.110 μs | 38.459 μs | 12.540 μs |
| map!(det) tensor | Float32 128^3 | 3.233 ms | 2.423 ms | 1.943 ms | 1.793 ms | 2.157 ms | 1.094 ms | 542.775 μs | 285.283 μs | 74.674 μs | 101.531 μs |
| map!(det) tensor | Float32 256^3 | 34.110 ms | 25.446 ms | 22.343 ms | 19.686 ms | 33.013 ms | 15.634 ms | 12.180 ms | 12.028 ms | 917.548 μs | 835.018 μs |
| map!(det) tensor | Float32 512^3 | 268.854 ms | 203.567 ms | 180.574 ms | 163.383 ms | 232.130 ms | 123.654 ms | 104.306 ms | 103.343 ms | 7.734 ms | — |
| map!(det) tensor | Float32 64^3 | 299.888 μs | 175.885 μs | 80.127 μs | 45.399 μs | 249.823 μs | 130.692 μs | 65.381 μs | 36.010 μs | 41.416 μs | 10.780 μs |
| map!(det) tensor | Float64 128^3 | 6.830 ms | 5.845 ms | 4.831 ms | 4.199 ms | 4.069 ms | 2.390 ms | 1.650 ms | 1.615 ms | 253.144 μs | 197.702 μs |
| map!(det) tensor | Float64 256^3 | 50.520 ms | 48.697 ms | 43.005 ms | 39.682 ms | 42.003 ms | 29.110 ms | 25.527 ms | 25.555 ms | 1.756 ms | 1.703 ms |
| map!(det) tensor | Float64 512^3 | 372.745 ms | 395.558 ms | 343.361 ms | 317.304 ms | 399.760 ms | 268.799 ms | 211.647 ms | 210.092 ms | — | — |
| map!(det) tensor | Float64 64^3 | 351.830 μs | 190.105 μs | 103.703 μs | 60.850 μs | 251.312 μs | 129.781 μs | 66.491 μs | 43.280 μs | 42.918 μs | 16.221 μs |
| mul! tensor.vec | Float32 128^3 | 4.832 ms | 4.283 ms | 3.732 ms | 3.522 ms | 3.579 ms | 1.878 ms | 999.160 μs | 800.418 μs | 212.826 μs | 151.131 μs |
| mul! tensor.vec | Float32 256^3 | 52.494 ms | 40.716 ms | 37.807 ms | 35.013 ms | 42.342 ms | 24.902 ms | 23.385 ms | 21.924 ms | 1.469 ms | 1.259 ms |
| mul! tensor.vec | Float32 512^3 | 410.472 ms | 322.453 ms | 303.156 ms | 286.594 ms | 335.639 ms | 216.482 ms | 177.813 ms | 174.639 ms | 11.904 ms | — |
| mul! tensor.vec | Float32 64^3 | 474.852 μs | 290.684 μs | 120.031 μs | 69.586 μs | 369.614 μs | 212.352 μs | 107.151 μs | 59.950 μs | 47.207 μs | 12.820 μs |
| mul! tensor.vec | Float64 128^3 | 10.930 ms | 9.854 ms | 9.212 ms | 8.175 ms | 7.037 ms | 5.284 ms | 4.363 ms | 4.291 ms | 387.204 μs | 319.843 μs |
| mul! tensor.vec | Float64 256^3 | 79.909 ms | 77.232 ms | 74.306 ms | 70.760 ms | 59.582 ms | 49.493 ms | 43.862 ms | 43.564 ms | 2.785 ms | 2.508 ms |
| mul! tensor.vec | Float64 512^3 | 634.738 ms | 629.406 ms | 594.193 ms | 566.488 ms | 584.406 ms | 407.714 ms | 352.521 ms | 351.009 ms | — | — |
| mul! tensor.vec | Float64 64^3 | 718.425 μs | 441.370 μs | 345.085 μs | 215.364 μs | 379.004 μs | 217.732 μs | 111.121 μs | 59.221 μs | 46.215 μs | 19.580 μs |
| norm! vec | Float32 128^3 | 733.462 μs | 606.099 μs | 462.548 μs | 352.646 μs | 216.772 μs | 119.751 μs | 63.990 μs | 52.270 μs | 67.048 μs | 39.551 μs |
| norm! vec | Float32 256^3 | 10.302 ms | 9.490 ms | 7.898 ms | 7.426 ms | 5.328 ms | 4.288 ms | 4.076 ms | 4.226 ms | 437.730 μs | 335.074 μs |
| norm! vec | Float32 512^3 | 84.168 ms | 78.693 ms | 67.086 ms | 62.872 ms | 49.340 ms | 44.364 ms | 45.828 ms | 46.797 ms | 3.436 ms | — |
| norm! vec | Float32 64^3 | 53.592 μs | 37.255 μs | 18.706 μs | 15.767 μs | 31.280 μs | 21.060 μs | 13.140 μs | 11.400 μs | 32.457 μs | 11.040 μs |
| norm! vec | Float64 128^3 | 2.108 ms | 1.913 ms | 1.463 ms | 1.329 ms | 489.994 μs | 247.853 μs | 128.041 μs | 105.531 μs | 133.163 μs | 79.460 μs |
| norm! vec | Float64 256^3 | 20.870 ms | 19.479 ms | 16.238 ms | 15.025 ms | 11.883 ms | 10.281 ms | 10.280 ms | 10.558 ms | 921.410 μs | 671.927 μs |
| norm! vec | Float64 512^3 | 168.996 ms | 156.488 ms | 132.956 ms | 124.495 ms | 102.305 ms | 90.356 ms | 92.070 ms | 92.572 ms | — | — |
| norm! vec | Float64 64^3 | 157.722 μs | 89.224 μs | 50.097 μs | 31.373 μs | 56.461 μs | 34.991 μs | 21.270 μs | 16.600 μs | 41.186 μs | 16.621 μs |
| tr! tensor | Float32 128^3 | 758.689 μs | 530.401 μs | 458.512 μs | 338.313 μs | 214.512 μs | 116.262 μs | 60.831 μs | 51.071 μs | 65.881 μs | 39.271 μs |
| tr! tensor | Float32 256^3 | 10.172 ms | 9.443 ms | 7.657 ms | 7.112 ms | 5.142 ms | 4.372 ms | 4.280 ms | 4.369 ms | 436.037 μs | 332.223 μs |
| tr! tensor | Float32 512^3 | 83.139 ms | 76.575 ms | 65.342 ms | 61.146 ms | 52.028 ms | 45.475 ms | 46.366 ms | 47.048 ms | 3.470 ms | — |
| tr! tensor | Float32 64^3 | 52.395 μs | 35.022 μs | 15.206 μs | 14.651 μs | 30.730 μs | 18.610 μs | 10.840 μs | 9.640 μs | 32.391 μs | 10.900 μs |
| tr! tensor | Float64 128^3 | 2.108 ms | 1.884 ms | 1.430 ms | 1.289 ms | 472.345 μs | 237.172 μs | 125.412 μs | 100.761 μs | 71.975 μs | 70.411 μs |
| tr! tensor | Float64 256^3 | 19.178 ms | 19.222 ms | 15.646 ms | 14.674 ms | 11.427 ms | 10.606 ms | 10.556 ms | 10.755 ms | 725.503 μs | 672.027 μs |
| tr! tensor | Float64 512^3 | 156.381 ms | 154.802 ms | 130.025 ms | 121.598 ms | 104.408 ms | 93.094 ms | 92.962 ms | 94.010 ms | — | — |
| tr! tensor | Float64 64^3 | 104.742 μs | 62.844 μs | 34.680 μs | 23.018 μs | 53.280 μs | 31.560 μs | 19.040 μs | 14.320 μs | 34.074 μs | 11.030 μs |

## operators

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| curl! vec->vec | Float32 128^3 | 5.601 ms | 2.814 ms | 1.524 ms | 1.193 ms | 3.225 ms | 1.662 ms | 830.059 μs | 423.315 μs | 54.447 μs | 37.591 μs |
| curl! vec->vec | Float32 256^3 | 44.512 ms | 22.745 ms | 17.411 ms | 16.374 ms | 25.582 ms | 13.222 ms | 8.829 ms | 8.561 ms | 599.757 μs | 541.556 μs |
| curl! vec->vec | Float32 512^3 | 353.454 ms | 179.497 ms | 143.969 ms | 137.767 ms | 221.916 ms | 116.620 ms | 83.223 ms | 83.772 ms | 4.675 ms | — |
| curl! vec->vec | Float32 64^3 | 701.433 μs | 361.150 μs | 184.037 μs | 98.127 μs | 413.914 μs | 219.992 μs | 110.881 μs | 58.211 μs | 36.797 μs | 11.760 μs |
| curl! vec->vec | Float64 128^3 | 5.619 ms | 3.984 ms | 3.549 ms | 3.419 ms | 3.715 ms | 1.878 ms | 923.080 μs | 533.235 μs | 134.294 μs | 142.691 μs |
| curl! vec->vec | Float64 256^3 | 46.063 ms | 37.255 ms | 35.891 ms | 33.893 ms | 33.518 ms | 20.339 ms | 19.335 ms | 19.541 ms | 1.174 ms | 1.076 ms |
| curl! vec->vec | Float64 512^3 | 358.302 ms | 297.171 ms | 285.115 ms | 278.516 ms | 263.706 ms | 168.288 ms | 164.977 ms | 166.920 ms | — | — |
| curl! vec->vec | Float64 64^3 | 667.721 μs | 350.535 μs | 174.492 μs | 95.386 μs | 463.114 μs | 233.472 μs | 120.691 μs | 64.021 μs | 46.662 μs | 20.790 μs |
| divergence! vec->scalar | Float32 128^3 | 3.574 ms | 1.387 ms | 717.187 μs | 410.276 μs | 3.375 ms | 1.137 ms | 569.886 μs | 287.743 μs | 58.474 μs | 31.620 μs |
| divergence! vec->scalar | Float32 256^3 | 28.090 ms | 11.222 ms | 9.157 ms | 8.285 ms | 26.737 ms | 8.971 ms | 4.529 ms | 4.140 ms | 393.628 μs | 342.194 μs |
| divergence! vec->scalar | Float32 512^3 | 225.912 ms | 90.903 ms | 78.072 ms | 70.387 ms | 211.421 ms | 70.710 ms | 46.335 ms | 46.775 ms | 2.884 ms | — |
| divergence! vec->scalar | Float32 64^3 | 419.615 μs | 177.148 μs | 92.388 μs | 52.647 μs | 433.305 μs | 152.721 μs | 78.161 μs | 42.550 μs | 33.777 μs | 11.370 μs |
| divergence! vec->scalar | Float64 128^3 | 3.683 ms | 1.976 ms | 1.639 ms | 1.416 ms | 3.345 ms | 1.061 ms | 545.376 μs | 277.293 μs | 88.294 μs | 76.081 μs |
| divergence! vec->scalar | Float64 256^3 | 29.855 ms | 20.850 ms | 17.193 ms | 15.792 ms | 27.449 ms | 11.125 ms | 10.314 ms | 10.316 ms | 739.697 μs | 678.946 μs |
| divergence! vec->scalar | Float64 512^3 | 251.127 ms | 165.735 ms | 137.426 ms | 126.198 ms | 211.704 ms | 96.078 ms | 93.528 ms | 93.519 ms | — | — |
| divergence! vec->scalar | Float64 64^3 | 421.386 μs | 162.407 μs | 88.248 μs | 57.264 μs | 435.395 μs | 138.741 μs | 73.801 μs | 40.960 μs | 38.085 μs | 13.941 μs |
| divergence!∘kernel vec->scalar | Float32 128^3 | 5.651 ms | 2.409 ms | 1.244 ms | 690.284 μs | 5.007 ms | 2.062 ms | 1.033 ms | 517.695 μs | 69.389 μs | 39.161 μs |
| divergence!∘kernel vec->scalar | Float32 256^3 | 44.515 ms | 19.085 ms | 10.144 ms | 8.955 ms | 39.527 ms | 16.194 ms | 8.130 ms | 4.253 ms | 423.413 μs | 343.373 μs |
| divergence!∘kernel vec->scalar | Float32 512^3 | 358.502 ms | 149.754 ms | 84.258 ms | 75.848 ms | 312.006 ms | 128.579 ms | 64.036 ms | 46.982 ms | 3.466 ms | — |
| divergence!∘kernel vec->scalar | Float32 64^3 | 701.659 μs | 314.373 μs | 163.116 μs | 91.041 μs | 634.947 μs | 271.213 μs | 139.321 μs | 74.511 μs | 35.949 μs | 13.240 μs |
| divergence!∘kernel vec->scalar | Float64 128^3 | 5.820 ms | 2.429 ms | 1.749 ms | 1.435 ms | 5.004 ms | 1.990 ms | 998.470 μs | 499.695 μs | 106.710 μs | 77.520 μs |
| divergence!∘kernel vec->scalar | Float64 256^3 | 45.886 ms | 21.403 ms | 17.723 ms | 15.918 ms | 40.014 ms | 15.819 ms | 10.315 ms | 10.273 ms | 754.845 μs | 681.156 μs |
| divergence!∘kernel vec->scalar | Float64 512^3 | 386.413 ms | 171.612 ms | 141.748 ms | 128.151 ms | 312.274 ms | 127.491 ms | 93.969 ms | 93.686 ms | — | — |
| divergence!∘kernel vec->scalar | Float64 64^3 | 688.300 μs | 302.980 μs | 158.764 μs | 91.008 μs | 635.446 μs | 255.153 μs | 132.461 μs | 70.711 μs | 42.759 μs | 18.130 μs |
| gradient! scalar->vec | Float32 128^3 | 3.197 ms | 1.630 ms | 869.431 μs | 497.219 μs | 1.967 ms | 971.410 μs | 490.155 μs | 251.663 μs | 45.830 μs | 27.840 μs |
| gradient! scalar->vec | Float32 256^3 | 25.567 ms | 14.334 ms | 13.090 ms | 12.457 ms | 15.614 ms | 7.821 ms | 5.665 ms | 5.645 ms | 449.490 μs | 379.483 μs |
| gradient! scalar->vec | Float32 512^3 | 199.846 ms | 116.915 ms | 111.782 ms | 107.483 ms | 125.223 ms | 66.503 ms | 64.258 ms | 64.439 ms | 3.467 ms | — |
| gradient! scalar->vec | Float32 64^3 | 399.488 μs | 215.350 μs | 107.402 μs | 60.044 μs | 248.313 μs | 125.591 μs | 64.671 μs | 35.260 μs | 34.659 μs | 10.390 μs |
| gradient! scalar->vec | Float64 128^3 | 3.339 ms | 2.732 ms | 2.470 ms | 2.313 ms | 2.067 ms | 978.670 μs | 495.985 μs | 258.463 μs | 96.991 μs | 99.511 μs |
| gradient! scalar->vec | Float64 256^3 | 30.567 ms | 28.362 ms | 26.990 ms | 26.094 ms | 20.238 ms | 14.734 ms | 13.986 ms | 14.126 ms | 899.357 μs | 745.877 μs |
| gradient! scalar->vec | Float64 512^3 | 238.976 ms | 230.773 ms | 222.039 ms | 216.286 ms | 163.396 ms | 129.490 ms | 127.405 ms | 128.301 ms | — | — |
| gradient! scalar->vec | Float64 64^3 | 353.709 μs | 182.808 μs | 94.432 μs | 56.772 μs | 262.722 μs | 125.652 μs | 63.240 μs | 34.641 μs | 41.081 μs | 16.270 μs |
| helmholtz! vec->vec | Float32 128^3 | 4.411 ms | 2.231 ms | 1.401 ms | 1.193 ms | 3.384 ms | 1.698 ms | 854.019 μs | 432.135 μs | 56.905 μs | 37.111 μs |
| helmholtz! vec->vec | Float32 256^3 | 35.019 ms | 18.655 ms | 17.232 ms | 16.365 ms | 26.893 ms | 13.444 ms | 8.551 ms | 8.560 ms | 598.176 μs | 542.115 μs |
| helmholtz! vec->vec | Float32 512^3 | 272.644 ms | 152.412 ms | 143.225 ms | 137.881 ms | 234.709 ms | 116.604 ms | 82.986 ms | 83.863 ms | 4.634 ms | — |
| helmholtz! vec->vec | Float32 64^3 | 549.250 μs | 283.265 μs | 146.494 μs | 78.363 μs | 447.534 μs | 230.002 μs | 115.621 μs | 60.911 μs | 37.395 μs | 12.080 μs |
| helmholtz! vec->vec | Float64 128^3 | 4.971 ms | 4.028 ms | 3.561 ms | 3.419 ms | 3.884 ms | 1.988 ms | 1.014 ms | 555.466 μs | 173.249 μs | 137.971 μs |
| helmholtz! vec->vec | Float64 256^3 | 42.633 ms | 37.318 ms | 35.921 ms | 33.958 ms | 37.826 ms | 20.305 ms | 19.409 ms | 19.583 ms | 1.191 ms | 1.073 ms |
| helmholtz! vec->vec | Float64 512^3 | 318.115 ms | 297.608 ms | 285.489 ms | 279.078 ms | 277.286 ms | 168.692 ms | 165.432 ms | 167.094 ms | — | — |
| helmholtz! vec->vec | Float64 64^3 | 583.614 μs | 302.234 μs | 155.986 μs | 85.974 μs | 508.735 μs | 260.462 μs | 134.411 μs | 71.391 μs | 50.130 μs | 26.911 μs |
| helmholtz!∘kernel vec->vec | Float32 128^3 | 7.541 ms | 3.839 ms | 1.962 ms | 1.239 ms | 6.317 ms | 3.165 ms | 1.654 ms | 809.558 μs | 65.640 μs | 40.931 μs |
| helmholtz!∘kernel vec->vec | Float32 256^3 | 60.150 ms | 30.768 ms | 17.865 ms | 16.457 ms | 50.148 ms | 25.095 ms | 12.622 ms | 8.536 ms | 588.737 μs | 542.175 μs |
| helmholtz!∘kernel vec->vec | Float32 512^3 | 473.484 ms | 241.867 ms | 146.245 ms | 137.830 ms | 404.131 ms | 201.824 ms | 101.600 ms | 83.328 ms | 4.560 ms | — |
| helmholtz!∘kernel vec->vec | Float32 64^3 | 956.302 μs | 491.107 μs | 252.122 μs | 132.817 μs | 827.318 μs | 426.344 μs | 215.282 μs | 110.931 μs | 39.951 μs | 13.640 μs |
| helmholtz!∘kernel vec->vec | Float64 128^3 | 8.078 ms | 4.205 ms | 3.599 ms | 3.411 ms | 6.788 ms | 3.479 ms | 1.796 ms | 879.579 μs | 182.891 μs | 168.381 μs |
| helmholtz!∘kernel vec->vec | Float64 256^3 | 64.892 ms | 37.637 ms | 36.100 ms | 34.028 ms | 55.004 ms | 27.966 ms | 19.336 ms | 19.363 ms | 1.210 ms | 1.228 ms |
| helmholtz!∘kernel vec->vec | Float64 512^3 | 510.381 ms | 298.560 ms | 286.010 ms | 278.260 ms | 444.705 ms | 230.994 ms | 165.845 ms | 166.390 ms | — | — |
| helmholtz!∘kernel vec->vec | Float64 64^3 | 1.014 ms | 516.847 μs | 258.364 μs | 139.260 μs | 909.569 μs | 455.485 μs | 233.172 μs | 121.401 μs | 55.907 μs | 33.020 μs |
| inverse_curl! vec->vec | Float32 128^3 | 6.559 ms | 3.371 ms | 1.705 ms | 1.197 ms | 3.503 ms | 1.747 ms | 876.009 μs | 449.434 μs | 56.551 μs | 35.331 μs |
| inverse_curl! vec->vec | Float32 256^3 | 51.945 ms | 26.930 ms | 17.637 ms | 16.436 ms | 28.150 ms | 13.994 ms | 8.563 ms | 8.568 ms | 595.303 μs | 541.605 μs |
| inverse_curl! vec->vec | Float32 512^3 | 413.151 ms | 211.915 ms | 145.279 ms | 138.362 ms | 242.037 ms | 119.563 ms | 83.059 ms | 83.839 ms | 4.650 ms | — |
| inverse_curl! vec->vec | Float32 64^3 | 824.851 μs | 444.471 μs | 221.810 μs | 116.075 μs | 444.975 μs | 225.722 μs | 114.301 μs | 60.401 μs | 35.385 μs | 12.210 μs |
| inverse_curl! vec->vec | Float64 128^3 | 6.276 ms | 3.993 ms | 3.564 ms | 3.403 ms | 3.664 ms | 1.842 ms | 912.639 μs | 528.055 μs | 177.165 μs | 155.081 μs |
| inverse_curl! vec->vec | Float64 256^3 | 50.771 ms | 37.329 ms | 35.880 ms | 33.904 ms | 33.468 ms | 20.224 ms | 19.336 ms | 19.543 ms | 1.200 ms | 1.123 ms |
| inverse_curl! vec->vec | Float64 512^3 | 399.445 ms | 297.513 ms | 285.711 ms | 278.784 ms | 261.491 ms | 167.628 ms | 164.623 ms | 166.410 ms | — | — |
| inverse_curl! vec->vec | Float64 64^3 | 765.346 μs | 398.569 μs | 200.319 μs | 108.042 μs | 456.514 μs | 229.833 μs | 119.012 μs | 63.381 μs | 54.720 μs | 30.980 μs |
| inverse_laplacian! scalar | Float32 128^3 | 4.654 ms | 1.661 ms | 850.386 μs | 464.490 μs | 3.898 ms | 1.323 ms | 669.076 μs | 343.404 μs | 60.248 μs | 33.521 μs |
| inverse_laplacian! scalar | Float32 256^3 | 36.454 ms | 13.565 ms | 6.779 ms | 5.154 ms | 31.487 ms | 10.596 ms | 5.322 ms | 2.700 ms | 333.794 μs | 222.813 μs |
| inverse_laplacian! scalar | Float32 512^3 | 289.995 ms | 106.268 ms | 54.001 ms | 45.950 ms | 250.540 ms | 83.592 ms | 42.550 ms | 26.620 ms | 2.547 ms | — |
| inverse_laplacian! scalar | Float32 64^3 | 571.498 μs | 220.734 μs | 115.248 μs | 72.274 μs | 496.625 μs | 177.962 μs | 92.351 μs | 52.561 μs | 31.896 μs | 11.100 μs |
| inverse_laplacian! scalar | Float64 128^3 | 4.915 ms | 1.819 ms | 971.540 μs | 540.885 μs | 4.249 ms | 1.424 ms | 729.628 μs | 372.114 μs | 93.850 μs | 48.710 μs |
| inverse_laplacian! scalar | Float64 256^3 | 39.081 ms | 14.357 ms | 10.541 ms | 8.515 ms | 34.282 ms | 11.519 ms | 5.806 ms | 4.836 ms | 594.812 μs | 348.714 μs |
| inverse_laplacian! scalar | Float64 512^3 | 311.055 ms | 113.023 ms | 86.455 ms | 67.384 ms | 272.559 ms | 91.169 ms | 54.288 ms | 54.398 ms | — | — |
| inverse_laplacian! scalar | Float64 64^3 | 604.634 μs | 243.068 μs | 132.487 μs | 75.022 μs | 540.355 μs | 190.252 μs | 99.841 μs | 55.980 μs | 36.177 μs | 14.110 μs |
| laplacian! scalar | Float32 128^3 | 2.004 ms | 635.095 μs | 327.682 μs | 189.295 μs | 2.144 ms | 493.565 μs | 250.263 μs | 129.481 μs | 52.464 μs | 26.170 μs |
| laplacian! scalar | Float32 256^3 | 16.207 ms | 5.911 ms | 4.898 ms | 4.102 ms | 17.028 ms | 3.872 ms | 1.954 ms | 1.191 ms | 250.836 μs | 189.202 μs |
| laplacian! scalar | Float32 512^3 | 130.211 ms | 50.153 ms | 41.843 ms | 34.859 ms | 136.008 ms | 30.759 ms | 26.172 ms | 26.298 ms | 1.813 ms | — |
| laplacian! scalar | Float32 64^3 | 247.290 μs | 89.705 μs | 48.290 μs | 30.230 μs | 274.793 μs | 68.580 μs | 36.640 μs | 22.240 μs | 30.850 μs | 9.290 μs |
| laplacian! scalar | Float64 128^3 | 2.146 ms | 798.926 μs | 659.459 μs | 438.940 μs | 2.205 ms | 528.455 μs | 271.723 μs | 140.672 μs | 56.906 μs | 29.140 μs |
| laplacian! scalar | Float64 256^3 | 17.264 ms | 11.742 ms | 11.248 ms | 10.635 ms | 17.726 ms | 5.003 ms | 4.779 ms | 4.837 ms | 365.703 μs | 357.304 μs |
| laplacian! scalar | Float64 512^3 | 136.289 ms | 97.296 ms | 95.438 ms | 90.207 ms | 141.578 ms | 53.753 ms | 53.595 ms | 54.419 ms | — | — |
| laplacian! scalar | Float64 64^3 | 268.621 μs | 92.316 μs | 52.232 μs | 33.457 μs | 281.772 μs | 73.040 μs | 38.830 μs | 23.571 μs | 32.266 μs | 10.130 μs |
| symmetric_gradient! vec->tensor | Float32 128^3 | 11.751 ms | 6.152 ms | 4.293 ms | 4.171 ms | 9.617 ms | 4.884 ms | 2.444 ms | 1.236 ms | 107.617 μs | 148.641 μs |
| symmetric_gradient! vec->tensor | Float32 256^3 | 87.658 ms | 46.321 ms | 42.355 ms | 42.084 ms | 76.731 ms | 40.089 ms | 22.914 ms | 23.123 ms | 1.870 ms | 1.127 ms |
| symmetric_gradient! vec->tensor | Float32 512^3 | 720.770 ms | 382.625 ms | 346.701 ms | 338.705 ms | 650.497 ms | 337.874 ms | 209.978 ms | 201.112 ms | 14.494 ms | — |
| symmetric_gradient! vec->tensor | Float32 64^3 | 1.441 ms | 748.903 μs | 386.031 μs | 199.678 μs | 1.214 ms | 621.927 μs | 316.023 μs | 168.062 μs | 44.573 μs | 17.740 μs |
| symmetric_gradient! vec->tensor | Float64 128^3 | 13.486 ms | 10.730 ms | 9.605 ms | 9.480 ms | 10.705 ms | 5.704 ms | 3.591 ms | 3.761 ms | 453.064 μs | 286.953 μs |
| symmetric_gradient! vec->tensor | Float64 256^3 | 110.396 ms | 92.704 ms | 85.316 ms | 84.326 ms | 93.313 ms | 57.178 ms | 49.033 ms | 49.609 ms | 3.444 ms | 2.225 ms |
| symmetric_gradient! vec->tensor | Float64 512^3 | 841.212 ms | 706.462 ms | 679.345 ms | 668.668 ms | 703.560 ms | 447.543 ms | 395.311 ms | 433.016 ms | — | — |
| symmetric_gradient! vec->tensor | Float64 64^3 | 1.538 ms | 803.942 μs | 406.359 μs | 219.907 μs | 1.275 ms | 645.046 μs | 326.464 μs | 166.971 μs | 55.424 μs | 32.210 μs |

## convolution

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| assignment_window | Float32 128^3 | 1.115 μs | 1.123 μs | 1.112 μs | 1.117 μs | 1.165 μs | 1.169 μs | 1.168 μs | 1.169 μs | 80.141 μs | 25.631 μs |
| assignment_window | Float32 256^3 | 2.180 μs | 2.324 μs | 2.190 μs | 2.189 μs | 2.227 μs | 2.231 μs | 2.236 μs | 2.221 μs | 81.977 μs | 25.500 μs |
| assignment_window | Float32 512^3 | 4.426 μs | 4.439 μs | 4.429 μs | 4.427 μs | 4.467 μs | 4.462 μs | 4.470 μs | 4.466 μs | 81.245 μs | — |
| assignment_window | Float32 64^3 | 589.887 ns | 606.474 ns | 585.571 ns | 588.286 ns | 608.177 ns | 610.062 ns | 611.663 ns | 611.091 ns | 87.128 μs | 25.091 μs |
| assignment_window | Float64 128^3 | 1.441 μs | 1.445 μs | 1.432 μs | 1.431 μs | 1.559 μs | 1.551 μs | 1.567 μs | 1.575 μs | 85.568 μs | 26.821 μs |
| assignment_window | Float64 256^3 | 2.951 μs | 2.998 μs | 2.961 μs | 3.265 μs | 3.115 μs | 3.076 μs | 3.089 μs | 3.074 μs | 83.355 μs | 27.501 μs |
| assignment_window | Float64 512^3 | 5.700 μs | 5.821 μs | 5.707 μs | 5.687 μs | 6.022 μs | 5.962 μs | 5.932 μs | 5.966 μs | — | — |
| assignment_window | Float64 64^3 | 729.850 ns | 731.811 ns | 729.944 ns | 729.795 ns | 829.115 ns | 821.532 ns | 827.192 ns | 824.948 ns | 75.670 μs | 26.250 μs |
| combine!∘kernel vector | Float32 128^3 | 3.872 ms | 2.202 ms | 1.633 ms | 1.476 ms | 3.155 ms | 1.548 ms | 777.248 μs | 396.384 μs | 58.366 μs | 79.330 μs |
| combine!∘kernel vector | Float32 256^3 | 30.542 ms | 20.451 ms | 19.527 ms | 18.458 ms | 25.242 ms | 12.704 ms | 9.938 ms | 9.887 ms | 957.892 μs | 863.549 μs |
| combine!∘kernel vector | Float32 512^3 | 268.068 ms | 172.697 ms | 161.458 ms | 153.403 ms | 242.879 ms | 102.236 ms | 92.999 ms | 93.344 ms | 7.402 ms | — |
| combine!∘kernel vector | Float32 64^3 | 491.033 μs | 273.904 μs | 134.001 μs | 75.647 μs | 422.295 μs | 206.253 μs | 105.651 μs | 56.551 μs | 38.387 μs | 13.340 μs |
| combine!∘kernel vector | Float64 128^3 | 5.327 ms | 4.578 ms | 4.142 ms | 3.922 ms | 3.748 ms | 2.080 ms | 1.108 ms | 754.328 μs | 259.347 μs | 225.052 μs |
| combine!∘kernel vector | Float64 256^3 | 47.724 ms | 43.124 ms | 39.908 ms | 38.468 ms | 34.090 ms | 23.100 ms | 21.977 ms | 22.168 ms | 1.876 ms | 1.713 ms |
| combine!∘kernel vector | Float64 512^3 | 367.903 ms | 332.699 ms | 322.711 ms | 308.506 ms | 289.421 ms | 190.866 ms | 183.886 ms | 185.179 ms | — | — |
| combine!∘kernel vector | Float64 64^3 | 488.596 μs | 280.480 μs | 141.962 μs | 80.990 μs | 383.943 μs | 223.292 μs | 114.301 μs | 62.341 μs | 50.366 μs | 25.210 μs |
| convolve! scalar | Float32 128^3 | 1.600 ms | 298.731 μs | 203.374 μs | 98.981 μs | 920.519 μs | 104.561 μs | 53.651 μs | 35.850 μs | 42.267 μs | 21.390 μs |
| convolve! scalar | Float32 256^3 | 13.339 ms | 7.686 ms | 7.252 ms | 6.736 ms | 7.584 ms | 2.799 ms | 2.704 ms | 2.738 ms | 291.202 μs | 260.513 μs |
| convolve! scalar | Float32 512^3 | 105.952 ms | 66.070 ms | 63.444 ms | 59.398 ms | 62.301 ms | 37.346 ms | 36.616 ms | 37.005 ms | 2.073 ms | — |
| convolve! scalar | Float32 64^3 | 197.892 μs | 28.194 μs | 21.030 μs | 13.782 μs | 116.872 μs | 16.201 μs | 9.000 μs | 7.554 μs | 29.603 μs | 8.200 μs |
| convolve! scalar | Float64 128^3 | 1.787 ms | 1.351 ms | 1.157 ms | 1.030 ms | 1.000 ms | 173.062 μs | 90.971 μs | 72.090 μs | 57.340 μs | 33.070 μs |
| convolve! scalar | Float64 256^3 | 17.872 ms | 16.156 ms | 15.183 ms | 14.243 ms | 10.939 ms | 7.897 ms | 7.612 ms | 7.756 ms | 556.582 μs | 516.776 μs |
| convolve! scalar | Float64 512^3 | 142.841 ms | 131.984 ms | 126.189 ms | 118.576 ms | 90.042 ms | 73.691 ms | 73.668 ms | 74.107 ms | — | — |
| convolve! scalar | Float64 64^3 | 176.482 μs | 52.788 μs | 26.031 μs | 19.285 μs | 127.711 μs | 26.650 μs | 13.790 μs | 10.140 μs | 33.477 μs | 9.970 μs |
| convolve! vector | Float32 128^3 | 2.634 ms | 1.840 ms | 1.572 ms | 1.482 ms | 2.103 ms | 1.099 ms | 551.226 μs | 282.593 μs | 48.783 μs | 59.581 μs |
| convolve! vector | Float32 256^3 | 23.191 ms | 20.383 ms | 19.151 ms | 18.284 ms | 19.800 ms | 10.967 ms | 9.857 ms | 9.886 ms | 620.535 μs | 618.736 μs |
| convolve! vector | Float32 512^3 | 194.018 ms | 169.279 ms | 159.678 ms | 153.241 ms | 178.202 ms | 94.040 ms | 92.441 ms | 93.133 ms | 4.740 ms | — |
| convolve! vector | Float32 64^3 | 309.536 μs | 173.193 μs | 91.431 μs | 51.159 μs | 270.172 μs | 147.462 μs | 74.430 μs | 39.981 μs | 36.827 μs | 10.610 μs |
| convolve! vector | Float64 128^3 | 4.925 ms | 4.613 ms | 4.104 ms | 3.940 ms | 2.658 ms | 1.541 ms | 877.809 μs | 751.219 μs | 178.377 μs | 160.172 μs |
| convolve! vector | Float64 256^3 | 44.745 ms | 42.617 ms | 39.419 ms | 38.487 ms | 30.584 ms | 22.849 ms | 21.958 ms | 22.125 ms | 1.214 ms | 1.228 ms |
| convolve! vector | Float64 512^3 | 347.136 ms | 331.855 ms | 321.099 ms | 307.743 ms | 239.732 ms | 188.786 ms | 183.720 ms | 185.473 ms | — | — |
| convolve! vector | Float64 64^3 | 262.393 μs | 164.202 μs | 85.200 μs | 58.318 μs | 219.633 μs | 136.691 μs | 70.381 μs | 39.240 μs | 42.450 μs | 18.600 μs |
| convolve! vector ∘ radial    | Float32 128^3 | 4.160 ms | 2.163 ms | 1.476 ms | 1.228 ms | 2.505 ms | 1.250 ms | 628.887 μs | 321.373 μs | 128.737 μs | 83.061 μs |
| convolve! vector ∘ radial    | Float32 256^3 | 33.263 ms | 19.226 ms | 16.147 ms | 14.084 ms | 19.845 ms | 10.077 ms | 8.208 ms | 8.362 ms | 853.818 μs | 610.286 μs |
| convolve! vector ∘ radial    | Float32 512^3 | 260.072 ms | 153.496 ms | 126.771 ms | 106.314 ms | 158.316 ms | 86.586 ms | 89.653 ms | 82.221 ms | 6.575 ms | — |
| convolve! vector ∘ radial    | Float32 64^3 | 535.058 μs | 257.234 μs | 132.561 μs | 73.702 μs | 315.844 μs | 160.552 μs | 82.201 μs | 43.561 μs | 44.168 μs | 16.651 μs |
| convolve! vector ∘ radial    | Float64 128^3 | 5.076 ms | 4.083 ms | 3.505 ms | 2.920 ms | 2.878 ms | 1.454 ms | 727.637 μs | 408.764 μs | 156.808 μs | 136.721 μs |
| convolve! vector ∘ radial    | Float64 256^3 | 41.531 ms | 36.385 ms | 29.821 ms | 26.263 ms | 24.296 ms | 18.669 ms | 18.791 ms | 19.079 ms | 1.081 ms | 1.065 ms |
| convolve! vector ∘ radial    | Float64 512^3 | 326.838 ms | 288.513 ms | 224.803 ms | 198.647 ms | 197.514 ms | 161.014 ms | 162.505 ms | 163.970 ms | — | — |
| convolve! vector ∘ radial    | Float64 64^3 | 536.158 μs | 294.472 μs | 142.317 μs | 88.577 μs | 352.993 μs | 177.482 μs | 89.621 μs | 48.370 μs | 46.641 μs | 18.450 μs |
| convolve! vector ∘ radial-stored | Float32 128^3 | 2.687 ms | 1.839 ms | 1.575 ms | 1.479 ms | 2.105 ms | 1.103 ms | 550.245 μs | 282.943 μs | 48.673 μs | 60.920 μs |
| convolve! vector ∘ radial-stored | Float32 256^3 | 23.874 ms | 20.295 ms | 19.301 ms | 18.309 ms | 19.701 ms | 10.964 ms | 9.795 ms | 9.884 ms | 618.716 μs | 619.116 μs |
| convolve! vector ∘ radial-stored | Float32 512^3 | 194.634 ms | 171.065 ms | 159.913 ms | 153.354 ms | 177.509 ms | 93.862 ms | 92.252 ms | 92.768 ms | 4.701 ms | — |
| convolve! vector ∘ radial-stored | Float32 64^3 | 309.394 μs | 173.242 μs | 89.382 μs | 49.775 μs | 269.593 μs | 147.372 μs | 74.521 μs | 39.940 μs | 36.096 μs | 10.570 μs |
| convolve! vector ∘ radial-stored | Float64 128^3 | 4.938 ms | 4.591 ms | 4.089 ms | 3.931 ms | 2.652 ms | 1.551 ms | 888.369 μs | 749.988 μs | 180.452 μs | 160.271 μs |
| convolve! vector ∘ radial-stored | Float64 256^3 | 44.762 ms | 42.489 ms | 39.328 ms | 38.484 ms | 30.365 ms | 22.484 ms | 21.926 ms | 22.024 ms | 1.217 ms | 1.229 ms |
| convolve! vector ∘ radial-stored | Float64 512^3 | 348.334 ms | 332.404 ms | 320.538 ms | 307.247 ms | 238.013 ms | 186.294 ms | 183.911 ms | 184.397 ms | — | — |
| convolve! vector ∘ radial-stored | Float64 64^3 | 261.187 μs | 166.317 μs | 87.858 μs | 55.285 μs | 230.442 μs | 136.732 μs | 70.230 μs | 38.340 μs | 42.390 μs | 18.620 μs |
| convolve! vector ∘ separable | Float32 128^3 | 6.776 ms | 3.446 ms | 1.755 ms | 1.212 ms | 4.689 ms | 2.349 ms | 1.169 ms | 591.396 μs | 124.168 μs | 83.821 μs |
| convolve! vector ∘ separable | Float32 256^3 | 53.562 ms | 26.812 ms | 16.929 ms | 13.282 ms | 37.225 ms | 18.611 ms | 9.372 ms | 8.451 ms | 851.399 μs | 613.806 μs |
| convolve! vector ∘ separable | Float32 512^3 | 428.234 ms | 214.788 ms | 137.070 ms | 107.540 ms | 296.142 ms | 148.181 ms | 82.539 ms | 82.763 ms | 6.882 ms | — |
| convolve! vector ∘ separable | Float32 64^3 | 842.559 μs | 441.129 μs | 219.619 μs | 117.159 μs | 588.566 μs | 297.343 μs | 150.462 μs | 78.021 μs | 44.126 μs | 16.850 μs |
| convolve! vector ∘ separable | Float64 128^3 | 6.695 ms | 4.113 ms | 3.394 ms | 2.460 ms | 3.958 ms | 1.994 ms | 1.003 ms | 510.466 μs | 245.316 μs | 144.741 μs |
| convolve! vector ∘ separable | Float64 256^3 | 53.696 ms | 36.655 ms | 29.551 ms | 23.271 ms | 32.560 ms | 19.223 ms | 19.009 ms | 19.292 ms | 1.735 ms | 1.077 ms |
| convolve! vector ∘ separable | Float64 512^3 | 430.490 ms | 291.823 ms | 230.024 ms | 185.465 ms | 259.746 ms | 164.962 ms | 163.125 ms | 165.071 ms | — | — |
| convolve! vector ∘ separable | Float64 64^3 | 809.885 μs | 420.271 μs | 221.790 μs | 115.411 μs | 495.104 μs | 248.922 μs | 125.841 μs | 66.181 μs | 57.896 μs | 25.410 μs |
| convolve! vector ∘ stored    | Float32 128^3 | 2.627 ms | 1.844 ms | 1.573 ms | 1.482 ms | 2.106 ms | 1.097 ms | 555.286 μs | 286.613 μs | 49.035 μs | 58.650 μs |
| convolve! vector ∘ stored    | Float32 256^3 | 23.102 ms | 20.367 ms | 19.236 ms | 18.267 ms | 19.818 ms | 10.941 ms | 9.833 ms | 9.908 ms | 624.675 μs | 619.657 μs |
| convolve! vector ∘ stored    | Float32 512^3 | 194.484 ms | 169.438 ms | 160.108 ms | 153.395 ms | 178.025 ms | 94.514 ms | 92.389 ms | 93.192 ms | 4.689 ms | — |
| convolve! vector ∘ stored    | Float32 64^3 | 309.289 μs | 178.942 μs | 89.782 μs | 50.701 μs | 270.233 μs | 147.781 μs | 75.350 μs | 39.921 μs | 36.671 μs | 10.670 μs |
| convolve! vector ∘ stored    | Float64 128^3 | 4.934 ms | 4.561 ms | 4.094 ms | 3.950 ms | 2.644 ms | 1.546 ms | 907.549 μs | 757.729 μs | 170.725 μs | 159.682 μs |
| convolve! vector ∘ stored    | Float64 256^3 | 44.693 ms | 42.464 ms | 39.423 ms | 38.502 ms | 30.489 ms | 22.879 ms | 21.948 ms | 22.105 ms | 1.221 ms | 1.228 ms |
| convolve! vector ∘ stored    | Float64 512^3 | 347.249 ms | 332.863 ms | 320.633 ms | 307.935 ms | 243.545 ms | 188.576 ms | 183.820 ms | 185.276 ms | — | — |
| convolve! vector ∘ stored    | Float64 64^3 | 260.840 μs | 173.558 μs | 92.173 μs | 60.452 μs | 221.182 μs | 136.832 μs | 71.981 μs | 40.610 μs | 42.402 μs | 18.590 μs |
| exponential_convolve! scalar | Float32 128^3 | 6.109 ms | 2.703 ms | 1.387 ms | 736.949 μs | 5.033 ms | 2.121 ms | 1.064 ms | 540.475 μs | 50.112 μs | 26.510 μs |
| exponential_convolve! scalar | Float32 256^3 | 48.269 ms | 21.168 ms | 10.632 ms | 5.960 ms | 39.779 ms | 16.571 ms | 8.360 ms | 4.232 ms | 259.298 μs | 189.642 μs |
| exponential_convolve! scalar | Float32 512^3 | 383.809 ms | 168.190 ms | 84.402 ms | 50.065 ms | 317.441 ms | 131.850 ms | 66.198 ms | 34.871 ms | 1.907 ms | — |
| exponential_convolve! scalar | Float32 64^3 | 764.482 μs | 350.609 μs | 179.990 μs | 101.012 μs | 640.306 μs | 280.483 μs | 145.271 μs | 77.911 μs | 30.932 μs | 9.300 μs |
| exponential_convolve! scalar | Float64 128^3 | 5.828 ms | 2.562 ms | 1.336 ms | 805.069 μs | 5.558 ms | 2.382 ms | 1.193 ms | 608.507 μs | 94.305 μs | 79.371 μs |
| exponential_convolve! scalar | Float64 256^3 | 46.247 ms | 20.299 ms | 12.026 ms | 11.071 ms | 44.292 ms | 18.813 ms | 9.470 ms | 4.995 ms | 599.659 μs | 565.516 μs |
| exponential_convolve! scalar | Float64 512^3 | 367.589 ms | 160.180 ms | 98.184 ms | 90.593 ms | 350.959 ms | 149.802 ms | 75.166 ms | 55.078 ms | — | — |
| exponential_convolve! scalar | Float64 64^3 | 721.942 μs | 329.853 μs | 171.489 μs | 99.183 μs | 701.017 μs | 306.833 μs | 159.081 μs | 85.241 μs | 40.123 μs | 17.450 μs |
| exponential_convolve! vector | Float32 128^3 | 5.397 ms | 2.633 ms | 1.501 ms | 1.230 ms | 4.716 ms | 1.869 ms | 943.920 μs | 477.715 μs | 47.062 μs | 36.990 μs |
| exponential_convolve! vector | Float32 256^3 | 42.762 ms | 22.632 ms | 17.597 ms | 16.283 ms | 41.279 ms | 16.485 ms | 10.175 ms | 8.989 ms | 576.950 μs | 541.605 μs |
| exponential_convolve! vector | Float32 512^3 | 346.225 ms | 192.897 ms | 146.156 ms | 135.808 ms | 514.995 ms | 144.093 ms | 94.993 ms | 83.391 ms | 4.259 ms | — |
| exponential_convolve! vector | Float32 64^3 | 677.484 μs | 327.276 μs | 165.086 μs | 87.937 μs | 624.156 μs | 251.363 μs | 127.711 μs | 66.861 μs | 34.917 μs | 10.040 μs |
| exponential_convolve! vector | Float64 128^3 | 5.848 ms | 4.005 ms | 3.572 ms | 3.385 ms | 5.235 ms | 2.080 ms | 1.033 ms | 552.436 μs | 101.650 μs | 143.992 μs |
| exponential_convolve! vector | Float64 256^3 | 47.664 ms | 37.216 ms | 35.200 ms | 33.676 ms | 69.074 ms | 24.888 ms | 20.769 ms | 20.232 ms | 1.162 ms | 1.077 ms |
| exponential_convolve! vector | Float64 512^3 | 371.397 ms | 291.482 ms | 283.208 ms | 269.076 ms | 1.007 s | 201.032 ms | 167.389 ms | 165.459 ms | — | — |
| exponential_convolve! vector | Float64 64^3 | 628.616 μs | 278.937 μs | 141.593 μs | 84.214 μs | 674.077 μs | 252.593 μs | 126.201 μs | 67.411 μs | 40.736 μs | 20.170 μs |
| inv separable | Float32 128^3 | 961.000 ns | 951.571 ns | 956.421 ns | 977.143 ns | 765.185 ns | 765.048 ns | 761.914 ns | 758.791 ns | 203.657 μs | 51.590 μs |
| inv separable | Float32 256^3 | 1.969 μs | 1.954 μs | 1.965 μs | 1.961 μs | 1.554 μs | 1.564 μs | 1.553 μs | 1.557 μs | 211.744 μs | 57.001 μs |
| inv separable | Float32 512^3 | 3.850 μs | 3.801 μs | 3.852 μs | 3.802 μs | 2.994 μs | 3.024 μs | 3.010 μs | 3.105 μs | 243.186 μs | — |
| inv separable | Float32 64^3 | 508.073 ns | 506.622 ns | 509.848 ns | 503.531 ns | 407.755 ns | 408.648 ns | 408.455 ns | 410.357 ns | 206.470 μs | 49.491 μs |
| inv separable | Float64 128^3 | 1.085 μs | 1.119 μs | 1.254 μs | 1.085 μs | 1.066 μs | 1.065 μs | 1.065 μs | 1.054 μs | 199.786 μs | 53.400 μs |
| inv separable | Float64 256^3 | 2.122 μs | 2.132 μs | 2.135 μs | 2.130 μs | 2.038 μs | 2.036 μs | 2.054 μs | 2.047 μs | 198.026 μs | 59.981 μs |
| inv separable | Float64 512^3 | 4.045 μs | 4.041 μs | 4.050 μs | 4.043 μs | 3.977 μs | 4.019 μs | 4.003 μs | 3.986 μs | — | — |
| inv separable | Float64 64^3 | 535.021 ns | 528.905 ns | 535.016 ns | 537.203 ns | 520.110 ns | 532.361 ns | 523.339 ns | 536.147 ns | 202.554 μs | 49.920 μs |
| materialize_kernel radial | Float32 128^3 | 1.391 ms | 604.296 μs | 439.055 μs | 234.335 μs | 1.130 ms | 351.443 μs | 178.282 μs | 93.241 μs | 52.251 μs | 26.180 μs |
| materialize_kernel radial | Float32 256^3 | 11.178 ms | 4.596 ms | 3.630 ms | 2.721 ms | 8.973 ms | 2.764 ms | 1.984 ms | 2.035 ms | 328.517 μs | 150.362 μs |
| materialize_kernel radial | Float32 512^3 | 88.504 ms | 36.193 ms | 28.505 ms | 22.088 ms | 71.419 ms | 22.162 ms | 32.141 ms | 17.154 ms | 4.960 ms | — |
| materialize_kernel radial | Float32 64^3 | 171.240 μs | 73.729 μs | 40.335 μs | 30.064 μs | 145.731 μs | 47.990 μs | 25.570 μs | 15.730 μs | 38.864 μs | 9.830 μs |
| materialize_kernel radial | Float64 128^3 | 1.410 ms | 799.377 μs | 691.979 μs | 478.175 μs | 1.179 ms | 372.844 μs | 226.272 μs | 305.163 μs | 61.668 μs | 29.721 μs |
| materialize_kernel radial | Float64 256^3 | 11.810 ms | 7.880 ms | 5.660 ms | 5.511 ms | 9.497 ms | 3.984 ms | 3.874 ms | 3.802 ms | 369.123 μs | 177.302 μs |
| materialize_kernel radial | Float64 512^3 | 94.085 ms | 141.765 ms | 45.526 ms | 45.165 ms | 75.444 ms | 33.815 ms | 53.247 ms | 35.706 ms | — | — |
| materialize_kernel radial | Float64 64^3 | 175.924 μs | 73.937 μs | 46.010 μs | 38.891 μs | 151.641 μs | 48.180 μs | 25.691 μs | 15.740 μs | 39.126 μs | 11.440 μs |
| materialize_kernel separable | Float32 128^3 | 1.790 ms | 782.561 μs | 455.910 μs | 319.118 μs | 1.533 ms | 446.084 μs | 227.382 μs | 116.862 μs | 53.203 μs | 25.980 μs |
| materialize_kernel separable | Float32 256^3 | 14.289 ms | 6.140 ms | 3.941 ms | 3.068 ms | 12.131 ms | 3.526 ms | 1.970 ms | 1.945 ms | 331.390 μs | 156.032 μs |
| materialize_kernel separable | Float32 512^3 | 113.850 ms | 49.089 ms | 31.445 ms | 23.920 ms | 96.540 ms | 27.869 ms | 35.141 ms | 17.953 ms | 5.509 ms | — |
| materialize_kernel separable | Float32 64^3 | 227.179 μs | 102.273 μs | 54.854 μs | 37.382 μs | 196.462 μs | 60.211 μs | 32.061 μs | 18.910 μs | 39.701 μs | 9.840 μs |
| materialize_kernel separable | Float64 128^3 | 1.777 ms | 976.686 μs | 776.631 μs | 539.041 μs | 1.449 ms | 453.995 μs | 240.243 μs | 291.063 μs | 75.606 μs | 36.891 μs |
| materialize_kernel separable | Float64 256^3 | 14.266 ms | 7.941 ms | 5.979 ms | 5.716 ms | 11.562 ms | 4.422 ms | 3.885 ms | 4.034 ms | 632.957 μs | 233.583 μs |
| materialize_kernel separable | Float64 512^3 | 115.075 ms | 156.007 ms | 47.145 ms | 50.535 ms | 91.967 ms | 38.488 ms | 61.319 ms | 44.372 ms | — | — |
| materialize_kernel separable | Float64 64^3 | 225.766 μs | 99.187 μs | 58.224 μs | 48.530 μs | 186.732 μs | 61.210 μs | 32.101 μs | 19.271 μs | 42.336 μs | 11.900 μs |
| radial_kernel | Float32 128^3 | 0.803 ns | 1.195 ns | 0.803 ns | 1.193 ns | 1.330 ns | 1.330 ns | 1.330 ns | 1.330 ns | 325.138 ns | 315.045 ns |
| radial_kernel | Float32 256^3 | 0.802 ns | 1.195 ns | 0.803 ns | 1.194 ns | 1.330 ns | 1.330 ns | 1.330 ns | 1.330 ns | 321.238 ns | 309.516 ns |
| radial_kernel | Float32 512^3 | 0.803 ns | 1.194 ns | 0.803 ns | 1.194 ns | 1.330 ns | 1.330 ns | 1.330 ns | 1.330 ns | 316.460 ns | — |
| radial_kernel | Float32 64^3 | 0.803 ns | 1.195 ns | 0.820 ns | 1.196 ns | 1.330 ns | 1.330 ns | 1.330 ns | 1.330 ns | 328.320 ns | 308.324 ns |
| radial_kernel | Float64 128^3 | 0.803 ns | 1.220 ns | 0.819 ns | 1.193 ns | 1.330 ns | 1.330 ns | 1.330 ns | 0.960 ns | 323.079 ns | 307.718 ns |
| radial_kernel | Float64 256^3 | 0.803 ns | 1.194 ns | 0.819 ns | 1.194 ns | 1.330 ns | 1.330 ns | 1.330 ns | 0.960 ns | 328.960 ns | 307.514 ns |
| radial_kernel | Float64 512^3 | 0.803 ns | 1.195 ns | 0.803 ns | 1.195 ns | 1.330 ns | 1.330 ns | 1.330 ns | 1.320 ns | — | — |
| radial_kernel | Float64 64^3 | 0.803 ns | 1.195 ns | 0.803 ns | 1.193 ns | 1.330 ns | 1.330 ns | 1.330 ns | 0.960 ns | 325.681 ns | 307.841 ns |
| spectral_band | Float32 128^3 | 0.803 ns | 1.197 ns | 0.819 ns | 1.219 ns | 0.960 ns | 1.330 ns | 0.960 ns | 1.000 ns | 326.627 ns | 311.684 ns |
| spectral_band | Float32 256^3 | 0.802 ns | 1.195 ns | 0.803 ns | 1.194 ns | 1.330 ns | 1.330 ns | 1.330 ns | 0.960 ns | 323.070 ns | 310.428 ns |
| spectral_band | Float32 512^3 | 0.803 ns | 1.194 ns | 0.803 ns | 1.194 ns | 1.330 ns | 1.330 ns | 1.330 ns | 1.330 ns | 322.087 ns | — |
| spectral_band | Float32 64^3 | 0.803 ns | 1.196 ns | 0.820 ns | 1.219 ns | 1.330 ns | 1.340 ns | 1.360 ns | 0.980 ns | 330.573 ns | 307.914 ns |
| spectral_band | Float64 128^3 | 0.802 ns | 1.194 ns | 0.803 ns | 1.193 ns | 1.330 ns | 0.960 ns | 0.960 ns | 1.330 ns | 328.575 ns | 307.386 ns |
| spectral_band | Float64 256^3 | 0.803 ns | 1.194 ns | 0.819 ns | 1.194 ns | 1.330 ns | 0.960 ns | 0.960 ns | 1.320 ns | 325.253 ns | 307.024 ns |
| spectral_band | Float64 512^3 | 0.803 ns | 1.195 ns | 0.819 ns | 1.193 ns | 1.320 ns | 0.960 ns | 0.960 ns | 1.330 ns | — | — |
| spectral_band | Float64 64^3 | 0.803 ns | 1.194 ns | 0.803 ns | 1.193 ns | 1.330 ns | 0.960 ns | 0.960 ns | 0.950 ns | 323.188 ns | 308.238 ns |
| spectral_cutoff | Float32 128^3 | 0.803 ns | 1.194 ns | 0.803 ns | 1.194 ns | 1.330 ns | 1.330 ns | 1.330 ns | 0.960 ns | 329.295 ns | 307.963 ns |
| spectral_cutoff | Float32 256^3 | 0.803 ns | 1.194 ns | 0.803 ns | 1.195 ns | 1.330 ns | 1.330 ns | 1.330 ns | 0.990 ns | 325.250 ns | 317.525 ns |
| spectral_cutoff | Float32 512^3 | 0.803 ns | 1.193 ns | 0.802 ns | 1.195 ns | 1.330 ns | 1.320 ns | 1.320 ns | 0.960 ns | 321.439 ns | — |
| spectral_cutoff | Float32 64^3 | 0.803 ns | 1.193 ns | 0.803 ns | 1.194 ns | 1.330 ns | 1.330 ns | 1.330 ns | 1.330 ns | 326.982 ns | 307.914 ns |
| spectral_cutoff | Float64 128^3 | 0.803 ns | 1.195 ns | 0.803 ns | 1.219 ns | 0.960 ns | 1.320 ns | 1.330 ns | 0.980 ns | 327.809 ns | 307.759 ns |
| spectral_cutoff | Float64 256^3 | 0.803 ns | 1.194 ns | 0.819 ns | 1.195 ns | 0.960 ns | 1.330 ns | 0.960 ns | 0.960 ns | 329.265 ns | 307.381 ns |
| spectral_cutoff | Float64 512^3 | 0.803 ns | 1.219 ns | 0.819 ns | 1.194 ns | 0.960 ns | 0.960 ns | 1.330 ns | 1.330 ns | — | — |
| spectral_cutoff | Float64 64^3 | 0.803 ns | 1.219 ns | 0.819 ns | 1.194 ns | 0.960 ns | 0.960 ns | 1.330 ns | 1.000 ns | 324.460 ns | 307.922 ns |
| translation_kernel | Float32 128^3 | 1.797 μs | 1.800 μs | 1.800 μs | 1.805 μs | 1.447 μs | 1.410 μs | 1.418 μs | 1.429 μs | 53.106 μs | 15.960 μs |
| translation_kernel | Float32 256^3 | 3.533 μs | 3.535 μs | 3.542 μs | 3.609 μs | 2.797 μs | 2.733 μs | 2.738 μs | 2.741 μs | 54.635 μs | 16.250 μs |
| translation_kernel | Float32 512^3 | 6.900 μs | 6.898 μs | 6.897 μs | 6.898 μs | 5.422 μs | 5.313 μs | 5.302 μs | 5.295 μs | 53.324 μs | — |
| translation_kernel | Float32 64^3 | 896.744 ns | 897.242 ns | 896.881 ns | 898.585 ns | 760.095 ns | 741.534 ns | 741.139 ns | 748.632 ns | 55.888 μs | 15.670 μs |
| translation_kernel | Float64 128^3 | 2.011 μs | 2.022 μs | 2.006 μs | 2.009 μs | 1.844 μs | 1.835 μs | 1.843 μs | 1.826 μs | 56.595 μs | 17.670 μs |
| translation_kernel | Float64 256^3 | 3.812 μs | 3.841 μs | 3.810 μs | 3.829 μs | 3.474 μs | 3.474 μs | 3.483 μs | 3.462 μs | 63.934 μs | 18.620 μs |
| translation_kernel | Float64 512^3 | 7.347 μs | 7.325 μs | 7.334 μs | 7.314 μs | 6.760 μs | 6.867 μs | 6.770 μs | 6.778 μs | — | — |
| translation_kernel | Float64 64^3 | 1.009 μs | 1.016 μs | 1.073 μs | 1.012 μs | 931.786 ns | 944.828 ns | 954.862 ns | 941.111 ns | 60.642 μs | 16.980 μs |
| translation_kernel! | Float32 128^3 | 1.757 μs | 1.754 μs | 1.754 μs | 1.754 μs | 1.369 μs | 1.370 μs | 1.375 μs | 1.372 μs | 31.558 μs | 13.110 μs |
| translation_kernel! | Float32 256^3 | 3.420 μs | 3.408 μs | 3.407 μs | 3.407 μs | 2.648 μs | 2.626 μs | 2.616 μs | 2.622 μs | 35.024 μs | 13.290 μs |
| translation_kernel! | Float32 512^3 | 6.723 μs | 6.719 μs | 6.715 μs | 6.714 μs | 5.110 μs | 5.158 μs | 5.112 μs | 5.112 μs | 31.432 μs | — |
| translation_kernel! | Float32 64^3 | 857.613 ns | 857.032 ns | 855.889 ns | 857.274 ns | 704.660 ns | 710.146 ns | 703.410 ns | 704.203 ns | 35.224 μs | 13.201 μs |
| translation_kernel! | Float64 128^3 | 1.859 μs | 1.870 μs | 1.866 μs | 1.973 μs | 1.692 μs | 1.698 μs | 1.703 μs | 1.701 μs | 36.637 μs | 14.460 μs |
| translation_kernel! | Float64 256^3 | 3.609 μs | 3.629 μs | 3.618 μs | 3.611 μs | 3.245 μs | 3.239 μs | 3.239 μs | 3.241 μs | 36.892 μs | 15.690 μs |
| translation_kernel! | Float64 512^3 | 7.118 μs | 7.088 μs | 7.086 μs | 7.070 μs | 6.352 μs | 6.358 μs | 6.350 μs | 6.400 μs | — | — |
| translation_kernel! | Float64 64^3 | 960.778 ns | 964.316 ns | 962.000 ns | 959.111 ns | 878.620 ns | 881.538 ns | 886.154 ns | 882.820 ns | 37.976 μs | 14.270 μs |

## transfer

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| anterpolate! CatmullRom ordered | Float32 128^3 | 25.510 ms | 12.302 ms | 6.455 ms | 3.807 ms | 20.310 ms | 10.300 ms | 5.325 ms | 2.843 ms | 188.085 μs | 130.131 μs |
| anterpolate! CatmullRom ordered | Float32 256^3 | 343.203 ms | 181.033 ms | 104.863 ms | 75.471 ms | 163.951 ms | 83.737 ms | 42.376 ms | 21.865 ms | 1.480 ms | 1.003 ms |
| anterpolate! CatmullRom ordered | Float32 512^3 | 3.184 s | 1.722 s | 1.054 s | 797.572 ms | 1.543 s | 786.928 ms | 406.293 ms | 207.933 ms | — | — |
| anterpolate! CatmullRom ordered | Float32 64^3 | 2.922 ms | 1.623 ms | 1.042 ms | 734.606 μs | 2.437 ms | 1.293 ms | 780.848 μs | 525.755 μs | 67.554 μs | 47.191 μs |
| anterpolate! CatmullRom ordered | Float64 128^3 | 28.946 ms | 13.584 ms | 7.033 ms | 4.092 ms | 21.942 ms | 11.139 ms | 5.814 ms | 3.205 ms | 233.176 μs | 141.291 μs |
| anterpolate! CatmullRom ordered | Float64 256^3 | 390.739 ms | 211.733 ms | 138.388 ms | 100.828 ms | 174.151 ms | 88.842 ms | 46.364 ms | 25.044 ms | 3.191 ms | 1.417 ms |
| anterpolate! CatmullRom ordered | Float64 512^3 | 3.504 s | 1.884 s | 1.132 s | 878.233 ms | 2.038 s | 1.056 s | 550.749 ms | 298.541 ms | — | — |
| anterpolate! CatmullRom ordered | Float64 64^3 | 3.049 ms | 1.690 ms | 1.086 ms | 831.701 μs | 2.453 ms | 1.304 ms | 791.178 μs | 536.455 μs | 94.581 μs | 48.830 μs |
| anterpolate! CatmullRom vector ordered | Float32 128^3 | 83.485 ms | 42.289 ms | 21.425 ms | 12.038 ms | 59.648 ms | 29.953 ms | 15.347 ms | 8.304 ms | 492.439 μs | 363.584 μs |
| anterpolate! CatmullRom vector ordered | Float32 256^3 | 1.013 s | 547.140 ms | 350.623 ms | 259.528 ms | 474.661 ms | 241.518 ms | 123.423 ms | 64.770 ms | 8.878 ms | 3.052 ms |
| anterpolate! CatmullRom vector ordered | Float32 512^3 | 8.305 s | 4.505 s | 2.856 s | 2.193 s | 4.514 s | 2.267 s | 1.153 s | 599.291 ms | — | — |
| anterpolate! CatmullRom vector ordered | Float32 64^3 | 9.322 ms | 4.827 ms | 3.091 ms | 2.298 ms | 7.218 ms | 3.822 ms | 2.304 ms | 1.547 ms | 128.389 μs | 123.321 μs |
| anterpolate! CatmullRom vector ordered | Float64 128^3 | 108.655 ms | 58.152 ms | 34.011 ms | 27.142 ms | 59.984 ms | 30.451 ms | 15.706 ms | 8.762 ms | 691.096 μs | 481.794 μs |
| anterpolate! CatmullRom vector ordered | Float64 256^3 | 1.032 s | 575.273 ms | 405.326 ms | 294.729 ms | 535.223 ms | 272.186 ms | 145.850 ms | 78.365 ms | 12.497 ms | 4.391 ms |
| anterpolate! CatmullRom vector ordered | Float64 512^3 | 9.695 s | 5.160 s | 3.050 s | 2.419 s | 5.378 s | 2.757 s | 1.426 s | 762.651 ms | — | — |
| anterpolate! CatmullRom vector ordered | Float64 64^3 | 9.809 ms | 4.912 ms | 3.098 ms | 2.346 ms | 7.608 ms | 4.001 ms | 2.454 ms | 1.653 ms | 227.558 μs | 108.081 μs |
| anterpolate! CatmullRom vector | Float32 128^3 | 81.329 ms | 40.672 ms | 20.631 ms | 11.634 ms | 63.555 ms | 32.408 ms | 16.693 ms | 9.141 ms | 487.004 μs | 362.243 μs |
| anterpolate! CatmullRom vector | Float32 256^3 | 943.195 ms | 503.630 ms | 312.180 ms | 237.940 ms | 829.189 ms | 430.266 ms | 225.219 ms | 117.330 ms | 8.103 ms | 10.707 ms |
| anterpolate! CatmullRom vector | Float32 512^3 | 7.667 s | 4.106 s | 2.471 s | 1.980 s | 9.065 s | 4.765 s | 2.515 s | 1.406 s | — | — |
| anterpolate! CatmullRom vector | Float32 64^3 | 9.374 ms | 4.860 ms | 3.099 ms | 2.174 ms | 7.250 ms | 3.995 ms | 2.530 ms | 1.739 ms | 128.496 μs | 114.711 μs |
| anterpolate! CatmullRom vector | Float64 128^3 | 101.065 ms | 54.165 ms | 30.959 ms | 22.379 ms | 66.086 ms | 34.334 ms | 17.942 ms | 10.274 ms | 689.123 μs | 648.116 μs |
| anterpolate! CatmullRom vector | Float64 256^3 | 940.377 ms | 525.945 ms | 371.488 ms | 273.346 ms | 1.026 s | 520.241 ms | 280.228 ms | 158.631 ms | 11.947 ms | 14.590 ms |
| anterpolate! CatmullRom vector | Float64 512^3 | 8.939 s | 4.766 s | 2.773 s | 2.236 s | 9.086 s | 4.700 s | 2.483 s | 1.436 s | — | — |
| anterpolate! CatmullRom vector | Float64 64^3 | 9.738 ms | 4.944 ms | 3.112 ms | 2.274 ms | 7.719 ms | 4.288 ms | 2.681 ms | 1.909 ms | 235.308 μs | 112.041 μs |
| anterpolate! CatmullRom | Float32 128^3 | 25.780 ms | 12.385 ms | 6.409 ms | 4.096 ms | 21.222 ms | 10.728 ms | 5.840 ms | 3.386 ms | 181.788 μs | 124.952 μs |
| anterpolate! CatmullRom | Float32 256^3 | 286.665 ms | 150.688 ms | 85.280 ms | 57.686 ms | 169.256 ms | 89.493 ms | 45.583 ms | 24.099 ms | 1.380 ms | 2.787 ms |
| anterpolate! CatmullRom | Float32 512^3 | 2.635 s | 1.430 s | 868.939 ms | 672.408 ms | 2.889 s | 1.476 s | 802.783 ms | 434.243 ms | — | — |
| anterpolate! CatmullRom | Float32 64^3 | 2.915 ms | 1.646 ms | 1.044 ms | 743.556 μs | 2.443 ms | 1.381 ms | 879.059 μs | 614.126 μs | 65.952 μs | 43.870 μs |
| anterpolate! CatmullRom | Float64 128^3 | 27.882 ms | 13.449 ms | 6.853 ms | 4.101 ms | 22.181 ms | 11.649 ms | 6.427 ms | 3.790 ms | 236.590 μs | 147.481 μs |
| anterpolate! CatmullRom | Float64 256^3 | 324.443 ms | 174.947 ms | 116.064 ms | 85.459 ms | 263.137 ms | 132.533 ms | 69.462 ms | 37.498 ms | 2.568 ms | 4.537 ms |
| anterpolate! CatmullRom | Float64 512^3 | 2.956 s | 1.581 s | 932.533 ms | 734.851 ms | 3.144 s | 1.608 s | 851.861 ms | 509.342 ms | — | — |
| anterpolate! CatmullRom | Float64 64^3 | 3.089 ms | 1.670 ms | 1.073 ms | 771.206 μs | 2.464 ms | 1.441 ms | 950.350 μs | 679.426 μs | 93.862 μs | 50.991 μs |
| anterpolate! Lalescu(3,3) | Float32 128^3 | 174.999 ms | 88.468 ms | 44.675 ms | 24.803 ms | 154.364 ms | 77.776 ms | 39.387 ms | 21.066 ms | 1.203 ms | 883.438 μs |
| anterpolate! Lalescu(3,3) | Float32 256^3 | 1.606 s | 824.755 ms | 435.740 ms | 271.054 ms | 1.240 s | 624.394 ms | 313.869 ms | 157.899 ms | 9.602 ms | 14.890 ms |
| anterpolate! Lalescu(3,3) | Float32 512^3 | 13.901 s | 7.299 s | 4.017 s | 2.864 s | 11.758 s | 6.039 s | 3.180 s | 1.801 s | — | — |
| anterpolate! Lalescu(3,3) | Float32 64^3 | 21.196 ms | 11.595 ms | 7.123 ms | 4.966 ms | 19.211 ms | 10.356 ms | 6.348 ms | 4.279 ms | 336.523 μs | 246.732 μs |
| anterpolate! Lalescu(3,3) | Float64 128^3 | 180.538 ms | 91.032 ms | 45.520 ms | 25.686 ms | 155.293 ms | 78.374 ms | 39.824 ms | 21.447 ms | 1.620 ms | 932.499 μs |
| anterpolate! Lalescu(3,3) | Float64 256^3 | 1.767 s | 911.612 ms | 522.189 ms | 379.301 ms | 1.406 s | 696.345 ms | 358.268 ms | 181.987 ms | 17.700 ms | 24.195 ms |
| anterpolate! Lalescu(3,3) | Float64 512^3 | 15.105 s | 7.877 s | 4.396 s | 3.123 s | 18.985 s | 9.557 s | 5.053 s | 2.836 s | — | — |
| anterpolate! Lalescu(3,3) | Float64 64^3 | 21.676 ms | 11.794 ms | 7.293 ms | 4.961 ms | 19.277 ms | 10.446 ms | 6.430 ms | 4.344 ms | 518.669 μs | 278.502 μs |
| anterpolate! NUFFT | Float32 128^3 | 411.049 ms | 218.947 ms | 150.695 ms | 102.861 ms | 376.122 ms | 200.931 ms | 113.020 ms | 69.823 ms | 2.986 ms | 2.702 ms |
| anterpolate! NUFFT | Float32 256^3 | 4.229 s | 2.418 s | 1.402 s | 1.111 s | 3.765 s | 2.010 s | 1.116 s | 688.029 ms | 33.308 ms | 28.643 ms |
| anterpolate! NUFFT | Float32 512^3 | 40.540 s | 22.651 s | 13.506 s | 9.761 s | 31.177 s | 16.455 s | 9.101 s | 5.564 s | — | — |
| anterpolate! NUFFT | Float32 64^3 | 31.802 ms | 17.735 ms | 11.433 ms | 8.234 ms | 27.161 ms | 14.309 ms | 8.680 ms | 5.896 ms | 507.480 μs | 325.583 μs |
| anterpolate! NUFFT | Float64 128^3 | 526.437 ms | 320.273 ms | 216.320 ms | 179.890 ms | 429.868 ms | 240.693 ms | 147.187 ms | 107.575 ms | 9.784 ms | 6.580 ms |
| anterpolate! NUFFT | Float64 256^3 | 5.466 s | 3.138 s | 2.055 s | 1.657 s | 3.596 s | 2.032 s | 1.224 s | 873.858 ms | 72.167 ms | 58.555 ms |
| anterpolate! NUFFT | Float64 512^3 | 44.185 s | 24.841 s | 16.001 s | 12.701 s | 39.727 s | 21.772 s | 12.602 s | 8.210 s | — | — |
| anterpolate! NUFFT | Float64 64^3 | 37.458 ms | 21.654 ms | 14.573 ms | 10.954 ms | 33.287 ms | 17.827 ms | 10.622 ms | 7.356 ms | 1.158 ms | 710.416 μs |
| anterpolate! trilinear | Float32 128^3 | 4.295 ms | 2.055 ms | 1.218 ms | 794.034 μs | 4.274 ms | 2.305 ms | 1.246 ms | 734.618 μs | 52.423 μs | 24.960 μs |
| anterpolate! trilinear | Float32 256^3 | 62.119 ms | 34.870 ms | 22.717 ms | 17.266 ms | 43.410 ms | 22.738 ms | 12.068 ms | 6.668 ms | 310.371 μs | 678.516 μs |
| anterpolate! trilinear | Float32 512^3 | 550.688 ms | 320.524 ms | 222.997 ms | 176.467 ms | 545.717 ms | 281.788 ms | 155.584 ms | 86.938 ms | — | — |
| anterpolate! trilinear | Float32 64^3 | 409.083 μs | 259.537 μs | 182.783 μs | 139.173 μs | 345.593 μs | 216.652 μs | 145.281 μs | 107.221 μs | 35.199 μs | 12.980 μs |
| anterpolate! trilinear | Float64 128^3 | 4.627 ms | 2.361 ms | 1.339 ms | 943.165 μs | 6.137 ms | 3.257 ms | 1.785 ms | 1.060 ms | 63.044 μs | 38.631 μs |
| anterpolate! trilinear | Float64 256^3 | 72.988 ms | 43.011 ms | 30.965 ms | 25.092 ms | 60.749 ms | 31.013 ms | 17.618 ms | 9.970 ms | 658.464 μs | 1.052 ms |
| anterpolate! trilinear | Float64 512^3 | 599.467 ms | 352.550 ms | 234.207 ms | 200.591 ms | 571.788 ms | 301.085 ms | 165.167 ms | 102.462 ms | — | — |
| anterpolate! trilinear | Float64 64^3 | 469.632 μs | 298.909 μs | 213.650 μs | 171.895 μs | 354.724 μs | 221.592 μs | 148.902 μs | 113.181 μs | 46.699 μs | 19.910 μs |
| displace! 1-term | Float32 128^3 | 53.142 μs | 35.284 μs | 19.953 μs | 14.363 μs | 45.870 μs | 25.261 μs | 13.570 μs | 9.441 μs | 25.842 μs | 7.573 μs |
| displace! 1-term | Float32 256^3 | 431.195 μs | 261.739 μs | 137.235 μs | 73.279 μs | 371.814 μs | 188.352 μs | 95.971 μs | 52.851 μs | 39.854 μs | 18.150 μs |
| displace! 1-term | Float32 512^3 | 5.638 ms | 4.900 ms | 4.377 ms | 4.111 ms | 3.283 ms | 1.804 ms | 948.849 μs | 874.309 μs | — | — |
| displace! 1-term | Float32 64^3 | 6.603 μs | 6.966 μs | 5.394 μs | 6.318 μs | 5.715 μs | 4.836 μs | 3.584 μs | 4.039 μs | 24.583 μs | 6.295 μs |
| displace! 1-term | Float64 128^3 | 63.083 μs | 38.500 μs | 19.676 μs | 14.864 μs | 48.061 μs | 28.650 μs | 14.411 μs | 10.720 μs | 25.197 μs | 7.860 μs |
| displace! 1-term | Float64 256^3 | 814.586 μs | 491.942 μs | 413.331 μs | 257.974 μs | 394.693 μs | 194.212 μs | 99.941 μs | 53.490 μs | 45.689 μs | 19.580 μs |
| displace! 1-term | Float64 512^3 | 11.335 ms | 10.387 ms | 9.694 ms | 9.234 ms | 4.891 ms | 3.798 ms | 3.958 ms | 4.007 ms | — | — |
| displace! 1-term | Float64 64^3 | 6.886 μs | 7.265 μs | 5.525 μs | 6.158 μs | 5.893 μs | 4.932 μs | 3.611 μs | 3.841 μs | 22.316 μs | 6.400 μs |
| displace! 3-term torus | Float32 128^3 | 852.259 μs | 481.315 μs | 253.951 μs | 169.381 μs | 708.857 μs | 405.354 μs | 212.642 μs | 119.881 μs | 58.551 μs | 23.011 μs |
| displace! 3-term torus | Float32 256^3 | 6.899 ms | 3.753 ms | 1.907 ms | 1.245 ms | 5.691 ms | 3.120 ms | 1.574 ms | 811.739 μs | 62.973 μs | 30.780 μs |
| displace! 3-term torus | Float32 512^3 | 56.573 ms | 30.202 ms | 16.095 ms | 9.723 ms | 45.440 ms | 24.736 ms | 12.485 ms | 6.378 ms | — | — |
| displace! 3-term torus | Float32 64^3 | 105.775 μs | 105.790 μs | 105.693 μs | 105.765 μs | 88.011 μs | 88.281 μs | 88.081 μs | 88.091 μs | 54.293 μs | 22.060 μs |
| displace! 3-term torus | Float64 128^3 | 862.987 μs | 481.836 μs | 255.086 μs | 151.336 μs | 735.877 μs | 429.754 μs | 219.893 μs | 124.861 μs | 62.542 μs | 26.930 μs |
| displace! 3-term torus | Float64 256^3 | 6.866 ms | 3.739 ms | 1.946 ms | 1.384 ms | 5.927 ms | 3.289 ms | 1.665 ms | 875.700 μs | 104.718 μs | 107.131 μs |
| displace! 3-term torus | Float64 512^3 | 55.078 ms | 29.725 ms | 18.282 ms | 16.319 ms | 47.423 ms | 25.894 ms | 13.847 ms | 8.937 ms | — | — |
| displace! 3-term torus | Float64 64^3 | 106.313 μs | 106.158 μs | 106.536 μs | 106.187 μs | 91.591 μs | 91.651 μs | 91.611 μs | 91.511 μs | 58.174 μs | 24.391 μs |
| displace! 3-term | Float32 128^3 | 163.693 μs | 102.803 μs | 56.263 μs | 33.284 μs | 93.991 μs | 79.141 μs | 41.420 μs | 24.281 μs | 25.324 μs | 8.670 μs |
| displace! 3-term | Float32 256^3 | 1.428 ms | 824.981 μs | 443.386 μs | 243.384 μs | 747.397 μs | 615.417 μs | 311.334 μs | 163.582 μs | 45.719 μs | 22.580 μs |
| displace! 3-term | Float32 512^3 | 11.833 ms | 8.828 ms | 8.418 ms | 7.629 ms | 7.705 ms | 5.289 ms | 3.413 ms | 3.425 ms | — | — |
| displace! 3-term | Float32 64^3 | 20.475 μs | 17.624 μs | 11.785 μs | 10.108 μs | 11.550 μs | 12.780 μs | 8.317 μs | 7.400 μs | 25.266 μs | 6.955 μs |
| displace! 3-term | Float64 128^3 | 164.050 μs | 104.262 μs | 56.765 μs | 36.939 μs | 94.681 μs | 81.691 μs | 43.911 μs | 24.540 μs | 31.099 μs | 9.780 μs |
| displace! 3-term | Float64 256^3 | 1.991 ms | 1.651 ms | 1.382 ms | 1.222 ms | 766.897 μs | 643.967 μs | 335.433 μs | 174.612 μs | 64.516 μs | 68.240 μs |
| displace! 3-term | Float64 512^3 | 19.265 ms | 18.553 ms | 17.154 ms | 15.986 ms | 12.851 ms | 9.430 ms | 8.952 ms | 8.853 ms | — | — |
| displace! 3-term | Float64 64^3 | 20.483 μs | 17.893 μs | 11.944 μs | 9.775 μs | 11.650 μs | 13.540 μs | 8.640 μs | 8.950 μs | 27.381 μs | 7.423 μs |
| interpolate! CatmullRom ordered | Float32 128^3 | 5.265 ms | 2.643 ms | 1.388 ms | 819.471 μs | 2.845 ms | 1.467 ms | 720.338 μs | 384.783 μs | 116.050 μs | 28.541 μs |
| interpolate! CatmullRom ordered | Float32 256^3 | 165.243 ms | 92.396 ms | 59.782 ms | 35.826 ms | 25.027 ms | 13.254 ms | 6.702 ms | 3.495 ms | 864.403 μs | 152.301 μs |
| interpolate! CatmullRom ordered | Float32 512^3 | 1.650 s | 972.364 ms | 631.567 ms | 378.652 ms | 557.639 ms | 301.577 ms | 161.982 ms | 81.958 ms | — | — |
| interpolate! CatmullRom ordered | Float32 64^3 | 556.907 μs | 299.740 μs | 181.428 μs | 128.747 μs | 297.393 μs | 160.522 μs | 96.881 μs | 66.261 μs | 41.174 μs | 15.070 μs |
| interpolate! CatmullRom ordered | Float64 128^3 | 8.049 ms | 4.123 ms | 2.040 ms | 1.080 ms | 3.219 ms | 1.576 ms | 797.638 μs | 421.154 μs | 126.934 μs | 79.401 μs |
| interpolate! CatmullRom ordered | Float64 256^3 | 205.147 ms | 116.926 ms | 77.429 ms | 45.658 ms | 41.479 ms | 21.305 ms | 12.100 ms | 7.416 ms | 1.812 ms | 485.405 μs |
| interpolate! CatmullRom ordered | Float64 512^3 | 1.722 s | 979.449 ms | 638.147 ms | 406.595 ms | 857.475 ms | 456.771 ms | 255.096 ms | 147.387 ms | — | — |
| interpolate! CatmullRom ordered | Float64 64^3 | 620.522 μs | 331.495 μs | 200.777 μs | 140.124 μs | 324.083 μs | 174.962 μs | 105.551 μs | 70.360 μs | 67.260 μs | 42.190 μs |
| interpolate! CatmullRom vector ordered | Float32 128^3 | 27.964 ms | 14.544 ms | 7.722 ms | 4.488 ms | 6.127 ms | 3.094 ms | 1.559 ms | 826.218 μs | 282.992 μs | 62.870 μs |
| interpolate! CatmullRom vector ordered | Float32 256^3 | 456.126 ms | 275.133 ms | 182.698 ms | 110.346 ms | 86.235 ms | 44.041 ms | 23.290 ms | 13.098 ms | 4.405 ms | 365.013 μs |
| interpolate! CatmullRom vector ordered | Float32 512^3 | 3.808 s | 2.459 s | 1.627 s | 963.186 ms | 1.176 s | 647.718 ms | 345.041 ms | 182.558 ms | — | — |
| interpolate! CatmullRom vector ordered | Float32 64^3 | 1.280 ms | 680.973 μs | 413.397 μs | 310.586 μs | 684.527 μs | 362.524 μs | 221.673 μs | 148.131 μs | 76.369 μs | 27.610 μs |
| interpolate! CatmullRom vector ordered | Float64 128^3 | 44.526 ms | 25.919 ms | 16.997 ms | 10.644 ms | 6.795 ms | 3.426 ms | 1.767 ms | 946.989 μs | 328.675 μs | 174.672 μs |
| interpolate! CatmullRom vector ordered | Float64 256^3 | 467.301 ms | 295.399 ms | 192.716 ms | 116.914 ms | 168.474 ms | 86.145 ms | 51.119 ms | 29.089 ms | 6.872 ms | 1.184 ms |
| interpolate! CatmullRom vector ordered | Float64 512^3 | 4.273 s | 2.405 s | 1.600 s | 1.036 s | 1.758 s | 940.654 ms | 505.046 ms | 276.232 ms | — | — |
| interpolate! CatmullRom vector ordered | Float64 64^3 | 1.431 ms | 734.565 μs | 452.507 μs | 319.044 μs | 781.838 μs | 419.975 μs | 251.272 μs | 170.072 μs | 129.232 μs | 87.201 μs |
| interpolate! CatmullRom vector | Float32 128^3 | 23.996 ms | 12.320 ms | 6.330 ms | 3.927 ms | 7.713 ms | 3.927 ms | 1.976 ms | 1.065 ms | 284.841 μs | 202.972 μs |
| interpolate! CatmullRom vector | Float32 256^3 | 394.219 ms | 240.878 ms | 162.498 ms | 96.438 ms | 285.972 ms | 151.780 ms | 80.020 ms | 43.171 ms | 3.934 ms | 3.275 ms |
| interpolate! CatmullRom vector | Float32 512^3 | 3.192 s | 2.067 s | 1.425 s | 851.529 ms | 2.993 s | 1.533 s | 832.057 ms | 481.181 ms | — | — |
| interpolate! CatmullRom vector | Float32 64^3 | 1.183 ms | 627.914 μs | 384.805 μs | 283.498 μs | 839.498 μs | 438.225 μs | 268.003 μs | 181.102 μs | 68.178 μs | 76.081 μs |
| interpolate! CatmullRom vector | Float64 128^3 | 39.805 ms | 23.098 ms | 14.985 ms | 9.427 ms | 9.149 ms | 4.641 ms | 2.540 ms | 1.594 ms | 329.868 μs | 244.332 μs |
| interpolate! CatmullRom vector | Float64 256^3 | 395.536 ms | 253.253 ms | 169.307 ms | 102.689 ms | 350.609 ms | 181.683 ms | 100.235 ms | 59.545 ms | 6.100 ms | 4.769 ms |
| interpolate! CatmullRom vector | Float64 512^3 | 3.739 s | 2.107 s | 1.422 s | 926.822 ms | 3.354 s | 1.724 s | 940.566 ms | 565.180 ms | — | — |
| interpolate! CatmullRom vector | Float64 64^3 | 1.242 ms | 653.854 μs | 398.452 μs | 294.227 μs | 876.568 μs | 470.195 μs | 281.612 μs | 192.362 μs | 127.501 μs | 90.320 μs |
| interpolate! CatmullRom | Float32 128^3 | 4.370 ms | 2.189 ms | 1.146 ms | 640.626 μs | 3.197 ms | 1.612 ms | 812.888 μs | 436.094 μs | 114.605 μs | 75.171 μs |
| interpolate! CatmullRom | Float32 256^3 | 126.075 ms | 71.483 ms | 46.390 ms | 28.105 ms | 31.610 ms | 19.490 ms | 9.512 ms | 4.909 ms | 772.842 μs | 768.527 μs |
| interpolate! CatmullRom | Float32 512^3 | 1.177 s | 712.491 ms | 492.676 ms | 290.085 ms | 1.132 s | 594.863 ms | 337.370 ms | 195.092 ms | — | — |
| interpolate! CatmullRom | Float32 64^3 | 464.499 μs | 253.393 μs | 158.525 μs | 110.955 μs | 323.203 μs | 175.632 μs | 105.981 μs | 72.590 μs | 44.232 μs | 29.460 μs |
| interpolate! CatmullRom | Float64 128^3 | 6.049 ms | 3.242 ms | 1.498 ms | 836.810 μs | 3.413 ms | 1.752 ms | 914.479 μs | 525.595 μs | 122.348 μs | 102.741 μs |
| interpolate! CatmullRom | Float64 256^3 | 151.487 ms | 87.625 ms | 60.974 ms | 35.651 ms | 105.578 ms | 53.655 ms | 28.399 ms | 15.229 ms | 1.540 ms | 1.485 ms |
| interpolate! CatmullRom | Float64 512^3 | 1.281 s | 740.484 ms | 503.925 ms | 325.451 ms | 1.497 s | 774.276 ms | 425.414 ms | 267.711 ms | — | — |
| interpolate! CatmullRom | Float64 64^3 | 547.063 μs | 294.234 μs | 181.353 μs | 126.146 μs | 381.533 μs | 205.822 μs | 123.972 μs | 86.260 μs | 61.786 μs | 43.470 μs |
| interpolate! Lalescu(3,3) | Float32 128^3 | 23.113 ms | 11.581 ms | 6.067 ms | 3.410 ms | 17.272 ms | 8.593 ms | 4.463 ms | 2.714 ms | 335.563 μs | 229.562 μs |
| interpolate! Lalescu(3,3) | Float32 256^3 | 616.655 ms | 344.060 ms | 224.232 ms | 144.158 ms | 145.808 ms | 97.995 ms | 50.658 ms | 28.290 ms | 2.402 ms | 3.522 ms |
| interpolate! Lalescu(3,3) | Float32 512^3 | 5.788 s | 3.563 s | 2.421 s | 1.549 s | 4.498 s | 2.415 s | 1.494 s | 1.013 s | — | — |
| interpolate! Lalescu(3,3) | Float32 64^3 | 2.560 ms | 1.382 ms | 830.067 μs | 587.072 μs | 2.047 ms | 1.097 ms | 641.597 μs | 429.045 μs | 82.144 μs | 75.421 μs |
| interpolate! Lalescu(3,3) | Float64 128^3 | 33.694 ms | 17.721 ms | 8.608 ms | 4.561 ms | 17.279 ms | 8.826 ms | 4.751 ms | 3.130 ms | 398.287 μs | 429.004 μs |
| interpolate! Lalescu(3,3) | Float64 256^3 | 801.386 ms | 447.833 ms | 332.265 ms | 200.133 ms | 441.447 ms | 226.598 ms | 116.572 ms | 71.404 ms | 4.749 ms | 8.514 ms |
| interpolate! Lalescu(3,3) | Float64 512^3 | 6.342 s | 3.860 s | 2.738 s | 1.699 s | 6.022 s | 3.069 s | 1.604 s | 976.673 ms | — | — |
| interpolate! Lalescu(3,3) | Float64 64^3 | 2.792 ms | 1.507 ms | 929.208 μs | 645.253 μs | 2.130 ms | 1.123 ms | 676.986 μs | 449.664 μs | 214.601 μs | 141.041 μs |
| interpolate! NUFFT | Float32 128^3 | 327.878 ms | 187.907 ms | 122.527 ms | 111.073 ms | 262.810 ms | 144.028 ms | 85.630 ms | 58.897 ms | 2.122 ms | 1.928 ms |
| interpolate! NUFFT | Float32 256^3 | 3.616 s | 2.078 s | 1.279 s | 1.008 s | 2.983 s | 1.619 s | 937.998 ms | 617.991 ms | 23.166 ms | 17.669 ms |
| interpolate! NUFFT | Float32 512^3 | 32.001 s | 18.083 s | 11.438 s | 8.308 s | 24.675 s | 13.209 s | 7.696 s | 4.969 s | — | — |
| interpolate! NUFFT | Float32 64^3 | 17.780 ms | 11.149 ms | 7.306 ms | 6.110 ms | 12.111 ms | 6.534 ms | 3.857 ms | 2.456 ms | 694.139 μs | 295.703 μs |
| interpolate! NUFFT | Float64 128^3 | 403.296 ms | 266.505 ms | 194.564 ms | 162.874 ms | 227.731 ms | 138.844 ms | 95.756 ms | 78.072 ms | 9.956 ms | 5.525 ms |
| interpolate! NUFFT | Float64 256^3 | 3.931 s | 2.373 s | 1.687 s | 1.389 s | 2.000 s | 1.224 s | 851.762 ms | 705.235 ms | 59.798 ms | 48.026 ms |
| interpolate! NUFFT | Float64 512^3 | 35.157 s | 20.887 s | 14.826 s | 13.122 s | 24.906 s | 14.094 s | 8.733 s | 9.442 s | — | — |
| interpolate! NUFFT | Float64 64^3 | 22.696 ms | 15.374 ms | 11.011 ms | 9.236 ms | 22.641 ms | 12.260 ms | 7.393 ms | 4.788 ms | 1.058 ms | 784.587 μs |
| interpolate! trilinear | Float32 128^3 | 1.342 ms | 693.436 μs | 355.889 μs | 196.959 μs | 1.108 ms | 553.136 μs | 281.113 μs | 152.871 μs | 31.759 μs | 15.720 μs |
| interpolate! trilinear | Float32 256^3 | 38.081 ms | 20.814 ms | 11.807 ms | 7.583 ms | 10.545 ms | 6.317 ms | 3.200 ms | 1.566 ms | 119.969 μs | 172.172 μs |
| interpolate! trilinear | Float32 512^3 | 337.918 ms | 187.520 ms | 114.076 ms | 74.608 ms | 415.424 ms | 210.850 ms | 109.939 ms | 57.482 ms | — | — |
| interpolate! trilinear | Float32 64^3 | 238.770 μs | 138.711 μs | 78.414 μs | 49.606 μs | 122.821 μs | 66.481 μs | 38.920 μs | 27.860 μs | 29.547 μs | 10.060 μs |
| interpolate! trilinear | Float64 128^3 | 1.852 ms | 937.214 μs | 451.511 μs | 249.078 μs | 1.073 ms | 544.576 μs | 285.473 μs | 151.741 μs | 46.004 μs | 26.310 μs |
| interpolate! trilinear | Float64 256^3 | 44.450 ms | 25.536 ms | 16.599 ms | 10.204 ms | 33.163 ms | 15.233 ms | 7.771 ms | 3.942 ms | 239.464 μs | 298.463 μs |
| interpolate! trilinear | Float64 512^3 | 372.048 ms | 217.672 ms | 140.144 ms | 86.540 ms | 425.905 ms | 215.163 ms | 111.942 ms | 62.444 ms | — | — |
| interpolate! trilinear | Float64 64^3 | 247.038 μs | 131.295 μs | 77.133 μs | 48.059 μs | 128.781 μs | 70.081 μs | 40.450 μs | 27.160 μs | 39.327 μs | 16.250 μs |
| point_traversal_order | Float32 128^3 | 987.556 μs | 1.182 ms | 853.572 μs | 578.786 μs | 676.626 μs | 413.745 μs | 291.743 μs | 219.902 μs | 294.438 μs | 91.741 μs |
| point_traversal_order | Float32 256^3 | 12.523 ms | 8.389 ms | 5.611 ms | 3.845 ms | 5.787 ms | 2.975 ms | 1.621 ms | 1.030 ms | 374.106 μs | 158.952 μs |
| point_traversal_order | Float32 512^3 | 159.929 ms | 103.116 ms | 65.314 ms | 45.307 ms | 62.859 ms | 30.969 ms | 16.891 ms | 10.665 ms | — | — |
| point_traversal_order | Float32 64^3 | 176.868 μs | 260.969 μs | 243.202 μs | 199.049 μs | 86.071 μs | 89.961 μs | 83.981 μs | 88.591 μs | 261.479 μs | 85.430 μs |
| point_traversal_order | Float64 128^3 | 998.964 μs | 1.180 ms | 857.526 μs | 574.395 μs | 683.407 μs | 428.994 μs | 293.163 μs | 228.183 μs | 301.532 μs | 90.471 μs |
| point_traversal_order | Float64 256^3 | 12.559 ms | 8.161 ms | 5.664 ms | 3.821 ms | 6.260 ms | 3.175 ms | 1.854 ms | 1.088 ms | 449.203 μs | 182.312 μs |
| point_traversal_order | Float64 512^3 | 155.559 ms | 85.057 ms | 47.985 ms | 30.862 ms | 64.015 ms | 36.454 ms | 19.286 ms | 13.641 ms | — | — |
| point_traversal_order | Float64 64^3 | 173.485 μs | 246.108 μs | 234.058 μs | 202.901 μs | 86.391 μs | 84.691 μs | 88.231 μs | 88.571 μs | 246.133 μs | 82.911 μs |
| wrap! | Float32 128^3 | 563.714 μs | 340.461 μs | 180.807 μs | 102.243 μs | 442.334 μs | 273.273 μs | 139.282 μs | 83.541 μs | 33.580 μs | 10.730 μs |
| wrap! | Float32 256^3 | 4.550 ms | 2.558 ms | 1.405 ms | 777.700 μs | 3.544 ms | 2.141 ms | 1.078 ms | 554.366 μs | 42.721 μs | 14.390 μs |
| wrap! | Float32 512^3 | 36.130 ms | 20.792 ms | 11.807 ms | 6.650 ms | 28.372 ms | 17.075 ms | 8.608 ms | 4.618 ms | — | — |
| wrap! | Float32 64^3 | 70.159 μs | 73.142 μs | 70.121 μs | 70.119 μs | 55.290 μs | 55.310 μs | 55.260 μs | 55.290 μs | 34.207 μs | 10.661 μs |
| wrap! | Float64 128^3 | 577.617 μs | 368.649 μs | 193.037 μs | 120.898 μs | 441.354 μs | 281.393 μs | 142.342 μs | 84.211 μs | 36.510 μs | 15.920 μs |
| wrap! | Float64 256^3 | 4.619 ms | 2.929 ms | 1.578 ms | 1.002 ms | 3.535 ms | 2.191 ms | 1.105 ms | 569.786 μs | 51.391 μs | 59.021 μs |
| wrap! | Float64 512^3 | 36.613 ms | 23.156 ms | 12.755 ms | 8.069 ms | 28.315 ms | 17.470 ms | 8.859 ms | 4.573 ms | — | — |
| wrap! | Float64 64^3 | 70.141 μs | 70.110 μs | 70.177 μs | 70.292 μs | 55.151 μs | 55.150 μs | 55.180 μs | 56.350 μs | 34.939 μs | 12.250 μs |

## reductions

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| co-spectrum vec.vec | Float32 128^3 | 8.064 ms | 6.815 ms | 8.551 ms | 7.583 ms | 6.955 ms | 5.053 ms | 5.864 ms | 6.421 ms | 313.602 μs | 175.002 μs |
| co-spectrum vec.vec | Float32 256^3 | 64.006 ms | 47.792 ms | 47.717 ms | 44.017 ms | 55.586 ms | 36.310 ms | 31.485 ms | 31.862 ms | 945.443 μs | 838.338 μs |
| co-spectrum vec.vec | Float32 512^3 | 516.367 ms | 356.438 ms | 269.122 ms | 234.255 ms | 447.260 ms | 266.297 ms | 190.143 ms | 154.457 ms | — | — |
| co-spectrum vec.vec | Float32 64^3 | 1.039 ms | 1.374 ms | 1.580 ms | 1.715 ms | 905.729 μs | 934.539 μs | 1.207 ms | 1.255 ms | 221.505 μs | 71.841 μs |
| co-spectrum vec.vec | Float64 128^3 | 8.439 ms | 6.456 ms | 6.430 ms | 5.633 ms | 7.293 ms | 5.117 ms | 4.571 ms | 4.438 ms | 17.348 ms | 258.092 μs |
| co-spectrum vec.vec | Float64 256^3 | 66.701 ms | 48.355 ms | 37.590 ms | 32.123 ms | 58.738 ms | 37.545 ms | 27.326 ms | 22.699 ms | 55.717 ms | 1.158 ms |
| co-spectrum vec.vec | Float64 512^3 | 558.936 ms | 367.687 ms | 236.347 ms | 195.119 ms | 476.161 ms | 282.807 ms | 172.999 ms | 129.276 ms | — | — |
| co-spectrum vec.vec | Float64 64^3 | 1.064 ms | 943.736 μs | 1.053 ms | 993.498 μs | 941.000 μs | 746.947 μs | 860.368 μs | 937.539 μs | 7.083 ms | 77.551 μs |
| cov vector | Float32 128^3 | 2.222 ms | 1.199 ms | 643.345 μs | 335.169 μs | 1.129 ms | 579.296 μs | 298.463 μs | 180.212 μs | 591.550 μs | 146.661 μs |
| cov vector | Float32 256^3 | 20.968 ms | 13.727 ms | 11.107 ms | 10.100 ms | 12.767 ms | 8.212 ms | 5.247 ms | 4.682 ms | 2.710 ms | 830.578 μs |
| cov vector | Float32 512^3 | 171.047 ms | 116.107 ms | 94.908 ms | 88.975 ms | 94.777 ms | 63.954 ms | 55.212 ms | 55.272 ms | — | — |
| cov vector | Float32 64^3 | 252.100 μs | 139.323 μs | 78.265 μs | 61.802 μs | 141.221 μs | 79.681 μs | 45.721 μs | 34.680 μs | 331.775 μs | 85.921 μs |
| cov vector | Float64 128^3 | 3.970 ms | 2.633 ms | 2.104 ms | 1.735 ms | 2.213 ms | 1.122 ms | 570.636 μs | 316.384 μs | 820.302 μs | 193.531 μs |
| cov vector | Float64 256^3 | 35.611 ms | 26.313 ms | 22.936 ms | 21.701 ms | 25.423 ms | 15.473 ms | 12.421 ms | 12.522 ms | 4.652 ms | 1.104 ms |
| cov vector | Float64 512^3 | 275.872 ms | 212.727 ms | 188.815 ms | 178.576 ms | 185.942 ms | 128.569 ms | 111.300 ms | 111.557 ms | — | — |
| cov vector | Float64 64^3 | 350.476 μs | 191.341 μs | 105.326 μs | 74.817 μs | 274.242 μs | 146.852 μs | 81.260 μs | 54.591 μs | 368.937 μs | 97.221 μs |
| cross-correlation vec.vec | Float32 128^3 | 37.590 ms | 32.046 ms | 33.604 ms | 32.708 ms | 32.907 ms | 24.414 ms | 22.285 ms | 21.375 ms | 774.316 μs | 563.865 μs |
| cross-correlation vec.vec | Float32 256^3 | 411.581 ms | 264.754 ms | 259.682 ms | 247.331 ms | 303.291 ms | 194.114 ms | 157.646 ms | 161.325 ms | 9.580 ms | 6.518 ms |
| cross-correlation vec.vec | Float32 512^3 | 3.524 s | 2.477 s | 1.870 s | 1.611 s | 2.935 s | 1.859 s | 1.394 s | 1.158 s | — | — |
| cross-correlation vec.vec | Float32 64^3 | 4.491 ms | 5.211 ms | 5.533 ms | 5.727 ms | 3.841 ms | 3.546 ms | 3.853 ms | 3.693 ms | 234.717 μs | 154.611 μs |
| cross-correlation vec.vec | Float64 128^3 | 46.875 ms | 41.997 ms | 38.904 ms | 36.677 ms | 40.003 ms | 38.574 ms | 25.627 ms | 24.757 ms | 36.628 ms | 1.938 ms |
| cross-correlation vec.vec | Float64 256^3 | 541.122 ms | 448.279 ms | 371.863 ms | 333.035 ms | 502.430 ms | 344.836 ms | 255.767 ms | 252.309 ms | 131.392 ms | 15.074 ms |
| cross-correlation vec.vec | Float64 512^3 | 5.613 s | 3.782 s | 2.856 s | 2.597 s | 4.475 s | 2.917 s | 2.091 s | 1.782 s | — | — |
| cross-correlation vec.vec | Float64 64^3 | 5.458 ms | 5.083 ms | 5.516 ms | 5.471 ms | 4.293 ms | 3.469 ms | 3.461 ms | 3.356 ms | 13.435 ms | 260.292 μs |
| inner spectral | Float32 128^3 | 2.628 ms | 1.806 ms | 1.380 ms | 1.268 ms | 1.434 ms | 808.088 μs | 494.375 μs | 364.304 μs | 206.813 μs | 120.061 μs |
| inner spectral | Float32 256^3 | 22.043 ms | 16.474 ms | 14.572 ms | 14.081 ms | 12.720 ms | 8.072 ms | 7.086 ms | 7.107 ms | 712.668 μs | 624.566 μs |
| inner spectral | Float32 512^3 | 168.585 ms | 130.342 ms | 114.545 ms | 106.434 ms | 106.804 ms | 79.869 ms | 69.979 ms | 70.829 ms | — | — |
| inner spectral | Float32 64^3 | 305.144 μs | 194.397 μs | 135.738 μs | 112.466 μs | 210.982 μs | 121.861 μs | 82.770 μs | 76.781 μs | 196.768 μs | 73.561 μs |
| inner spectral | Float64 128^3 | 4.265 ms | 3.541 ms | 3.074 ms | 2.815 ms | 1.880 ms | 1.088 ms | 722.667 μs | 601.616 μs | 254.439 μs | 200.782 μs |
| inner spectral | Float64 256^3 | 35.244 ms | 30.053 ms | 27.431 ms | 26.381 ms | 18.732 ms | 15.904 ms | 15.603 ms | 15.238 ms | 1.180 ms | 1.112 ms |
| inner spectral | Float64 512^3 | 252.878 ms | 225.516 ms | 210.892 ms | 199.889 ms | 137.901 ms | 132.354 ms | 126.422 ms | 127.880 ms | — | — |
| inner spectral | Float64 64^3 | 312.791 μs | 213.868 μs | 148.688 μs | 128.417 μs | 225.993 μs | 134.421 μs | 90.910 μs | 85.080 μs | 205.430 μs | 80.650 μs |
| inner vec.vec | Float32 128^3 | 1.204 ms | 972.912 μs | 806.809 μs | 711.787 μs | 388.584 μs | 195.622 μs | 100.441 μs | 71.860 μs | 49.672 μs | 30.500 μs |
| inner vec.vec | Float32 256^3 | 13.091 ms | 11.973 ms | 11.337 ms | 10.787 ms | 7.434 ms | 6.470 ms | 5.782 ms | 5.914 ms | 479.352 μs | 489.195 μs |
| inner vec.vec | Float32 512^3 | 106.964 ms | 100.339 ms | 95.808 ms | 89.706 ms | 65.750 ms | 58.003 ms | 55.295 ms | 55.838 ms | — | — |
| inner vec.vec | Float32 64^3 | 69.043 μs | 38.944 μs | 20.032 μs | 15.339 μs | 46.241 μs | 25.741 μs | 14.620 μs | 11.330 μs | 51.415 μs | 12.970 μs |
| inner vec.vec | Float64 128^3 | 2.918 ms | 2.529 ms | 2.283 ms | 2.130 ms | 1.157 ms | 644.167 μs | 325.423 μs | 239.522 μs | 91.666 μs | 134.851 μs |
| inner vec.vec | Float64 256^3 | 26.822 ms | 24.713 ms | 23.264 ms | 22.217 ms | 15.251 ms | 13.960 ms | 13.219 ms | 13.173 ms | 923.330 μs | 963.440 μs |
| inner vec.vec | Float64 512^3 | 205.557 ms | 196.319 ms | 188.112 ms | 178.110 ms | 125.692 ms | 114.536 ms | 112.479 ms | 112.441 ms | — | — |
| inner vec.vec | Float64 64^3 | 139.730 μs | 76.390 μs | 39.494 μs | 24.061 μs | 87.721 μs | 46.370 μs | 25.580 μs | 17.640 μs | 45.468 μs | 18.460 μs |
| integral scalar | Float32 128^3 | 107.852 μs | 62.202 μs | 30.249 μs | 20.242 μs | 61.371 μs | 33.681 μs | 20.921 μs | 12.950 μs | 133.679 μs | 31.680 μs |
| integral scalar | Float32 256^3 | 1.971 ms | 1.559 ms | 1.286 ms | 1.194 ms | 549.207 μs | 275.203 μs | 163.622 μs | 99.021 μs | 610.662 μs | 175.422 μs |
| integral scalar | Float32 512^3 | 19.300 ms | 15.997 ms | 14.701 ms | 14.173 ms | 10.766 ms | 9.397 ms | 9.028 ms | 8.864 ms | — | — |
| integral scalar | Float32 64^3 | 10.045 μs | 6.844 μs | 5.338 μs | 5.589 μs | 6.918 μs | 4.880 μs | 4.120 μs | 5.242 μs | 80.032 μs | 17.950 μs |
| integral scalar | Float64 128^3 | 240.600 μs | 129.396 μs | 64.239 μs | 38.903 μs | 121.721 μs | 63.361 μs | 36.680 μs | 23.351 μs | 153.471 μs | 32.580 μs |
| integral scalar | Float64 256^3 | 4.356 ms | 3.568 ms | 3.239 ms | 3.034 ms | 1.632 ms | 1.114 ms | 812.009 μs | 963.730 μs | 731.388 μs | 192.012 μs |
| integral scalar | Float64 512^3 | 37.483 ms | 32.137 ms | 30.013 ms | 29.220 ms | 20.531 ms | 18.597 ms | 18.159 ms | 18.072 ms | — | — |
| integral scalar | Float64 64^3 | 25.825 μs | 13.121 μs | 8.252 μs | 8.011 μs | 14.920 μs | 7.900 μs | 5.938 μs | 5.830 μs | 79.386 μs | 19.330 μs |
| integral spectral vec | Float32 128^3 | 66.335 ns | 67.597 ns | 67.244 ns | 67.262 ns | 71.240 ns | 69.673 ns | 69.315 ns | 71.692 ns | 84.753 μs | 12.780 μs |
| integral spectral vec | Float32 256^3 | 65.983 ns | 67.551 ns | 67.392 ns | 67.741 ns | 71.651 ns | 71.067 ns | 70.401 ns | 70.257 ns | 75.386 μs | 12.620 μs |
| integral spectral vec | Float32 512^3 | 66.809 ns | 67.981 ns | 68.415 ns | 67.914 ns | 72.030 ns | 72.863 ns | 73.720 ns | 69.192 ns | — | — |
| integral spectral vec | Float32 64^3 | 66.145 ns | 67.149 ns | 67.312 ns | 67.191 ns | 73.121 ns | 70.669 ns | 69.489 ns | 74.995 ns | 81.113 μs | 13.000 μs |
| integral spectral vec | Float64 128^3 | 68.991 ns | 67.980 ns | 69.227 ns | 69.604 ns | 74.637 ns | 73.351 ns | 72.016 ns | 79.590 ns | 76.940 μs | 13.131 μs |
| integral spectral vec | Float64 256^3 | 69.466 ns | 68.475 ns | 70.518 ns | 69.877 ns | 77.311 ns | 76.466 ns | 73.555 ns | 73.921 ns | 81.717 μs | 13.160 μs |
| integral spectral vec | Float64 512^3 | 69.224 ns | 69.411 ns | 70.633 ns | 70.683 ns | 78.399 ns | 78.705 ns | 78.495 ns | 77.668 ns | — | — |
| integral spectral vec | Float64 64^3 | 68.881 ns | 68.275 ns | 68.597 ns | 68.165 ns | 76.575 ns | 75.463 ns | 74.302 ns | 74.814 ns | 84.185 μs | 12.800 μs |
| l2norm vec | Float32 128^3 | 570.770 μs | 339.888 μs | 192.280 μs | 84.070 μs | 249.532 μs | 129.191 μs | 71.291 μs | 39.721 μs | 48.317 μs | 19.980 μs |
| l2norm vec | Float32 256^3 | 7.513 ms | 5.910 ms | 5.359 ms | 4.990 ms | 4.108 ms | 2.870 ms | 1.948 ms | 2.010 ms | 262.666 μs | 258.592 μs |
| l2norm vec | Float32 512^3 | 61.592 ms | 50.047 ms | 46.468 ms | 44.559 ms | 41.560 ms | 30.681 ms | 26.714 ms | 27.026 ms | — | — |
| l2norm vec | Float32 64^3 | 49.518 μs | 27.342 μs | 18.743 μs | 12.988 μs | 31.890 μs | 17.010 μs | 9.790 μs | 8.030 μs | 49.254 μs | 12.240 μs |
| l2norm vec | Float64 128^3 | 1.525 ms | 1.021 ms | 813.490 μs | 708.889 μs | 506.955 μs | 252.683 μs | 127.311 μs | 75.901 μs | 87.110 μs | 33.701 μs |
| l2norm vec | Float64 256^3 | 15.965 ms | 12.290 ms | 11.018 ms | 10.394 ms | 12.136 ms | 7.295 ms | 5.663 ms | 5.525 ms | 533.318 μs | 491.425 μs |
| l2norm vec | Float64 512^3 | 120.235 ms | 98.790 ms | 91.112 ms | 87.630 ms | 95.940 ms | 62.201 ms | 54.589 ms | 54.973 ms | — | — |
| l2norm vec | Float64 64^3 | 92.869 μs | 50.435 μs | 27.281 μs | 17.187 μs | 59.161 μs | 30.891 μs | 17.210 μs | 11.290 μs | 43.288 μs | 17.130 μs |
| lpnorm vec Inf | Float32 128^3 | 1.337 ms | 1.271 ms | 1.140 ms | 1.014 ms | 463.304 μs | 388.824 μs | 333.483 μs | 338.524 μs | 185.622 μs | 66.011 μs |
| lpnorm vec Inf | Float32 256^3 | 13.317 ms | 13.614 ms | 11.658 ms | 10.629 ms | 8.558 ms | 7.443 ms | 7.308 ms | 8.842 ms | 1.071 ms | 506.725 μs |
| lpnorm vec Inf | Float32 512^3 | 113.058 ms | 117.349 ms | 95.513 ms | 85.464 ms | 77.598 ms | 71.842 ms | 70.319 ms | 71.557 ms | — | — |
| lpnorm vec Inf | Float32 64^3 | 98.618 μs | 84.324 μs | 70.600 μs | 77.405 μs | 61.221 μs | 49.410 μs | 42.480 μs | 42.661 μs | 93.637 μs | 24.690 μs |
| lpnorm vec Inf | Float64 128^3 | 3.115 ms | 3.273 ms | 2.592 ms | 2.490 ms | 1.204 ms | 1.038 ms | 937.679 μs | 986.931 μs | 292.235 μs | 115.032 μs |
| lpnorm vec Inf | Float64 256^3 | 27.709 ms | 26.734 ms | 23.187 ms | 21.812 ms | 17.413 ms | 15.442 ms | 16.616 ms | 15.935 ms | 1.919 ms | 940.439 μs |
| lpnorm vec Inf | Float64 512^3 | 217.055 ms | 234.593 ms | 188.481 ms | 172.796 ms | 138.848 ms | 137.789 ms | 140.560 ms | 139.527 ms | — | — |
| lpnorm vec Inf | Float64 64^3 | 231.948 μs | 178.291 μs | 145.984 μs | 136.748 μs | 111.021 μs | 92.231 μs | 76.861 μs | 73.241 μs | 107.105 μs | 34.590 μs |
| maximum scalar | Float32 128^3 | 336.601 μs | 176.748 μs | 92.064 μs | 50.490 μs | 238.352 μs | 117.732 μs | 61.421 μs | 33.070 μs | 136.144 μs | 31.500 μs |
| maximum scalar | Float32 256^3 | 3.489 ms | 1.792 ms | 1.414 ms | 1.215 ms | 2.002 ms | 944.690 μs | 487.845 μs | 249.813 μs | 599.642 μs | 175.282 μs |
| maximum scalar | Float32 512^3 | 23.655 ms | 17.352 ms | 15.172 ms | 14.645 ms | 31.382 ms | 12.720 ms | 9.007 ms | 8.138 ms | — | — |
| maximum scalar | Float32 64^3 | 42.020 μs | 24.561 μs | 13.804 μs | 9.827 μs | 29.560 μs | 15.870 μs | 9.320 μs | 6.930 μs | 81.300 μs | 17.610 μs |
| maximum scalar | Float64 128^3 | 549.398 μs | 289.276 μs | 143.652 μs | 133.276 μs | 440.814 μs | 222.262 μs | 113.642 μs | 59.651 μs | 179.137 μs | 40.740 μs |
| maximum scalar | Float64 256^3 | 6.209 ms | 4.121 ms | 3.394 ms | 3.054 ms | 4.043 ms | 2.036 ms | 1.099 ms | 824.389 μs | 975.969 μs | 214.182 μs |
| maximum scalar | Float64 512^3 | 48.806 ms | 34.253 ms | 30.349 ms | 29.096 ms | 44.789 ms | 26.944 ms | 19.316 ms | 17.364 ms | — | — |
| maximum scalar | Float64 64^3 | 65.149 μs | 36.445 μs | 20.614 μs | 14.264 μs | 55.340 μs | 29.610 μs | 15.810 μs | 9.970 μs | 81.183 μs | 24.020 μs |
| maximum(norm) vec | Float32 128^3 | 1.807 ms | 928.680 μs | 471.864 μs | 244.851 μs | 773.618 μs | 389.324 μs | 197.281 μs | 105.381 μs | 199.913 μs | 41.650 μs |
| maximum(norm) vec | Float32 256^3 | 15.212 ms | 8.242 ms | 5.781 ms | 5.042 ms | 8.475 ms | 3.923 ms | 2.454 ms | 2.121 ms | 849.073 μs | 283.012 μs |
| maximum(norm) vec | Float32 512^3 | 119.507 ms | 68.052 ms | 49.892 ms | 45.508 ms | 58.330 ms | 37.931 ms | 29.689 ms | 28.233 ms | — | — |
| maximum(norm) vec | Float32 64^3 | 220.708 μs | 115.996 μs | 61.320 μs | 35.459 μs | 96.891 μs | 49.131 μs | 26.730 μs | 15.400 μs | 94.461 μs | 20.080 μs |
| maximum(norm) vec | Float64 128^3 | 5.233 ms | 2.685 ms | 1.388 ms | 821.881 μs | 1.587 ms | 793.968 μs | 400.894 μs | 212.383 μs | 254.406 μs | 129.732 μs |
| maximum(norm) vec | Float64 256^3 | 41.974 ms | 21.439 ms | 12.833 ms | 10.750 ms | 14.279 ms | 8.345 ms | 6.050 ms | 5.845 ms | 1.629 ms | 858.829 μs |
| maximum(norm) vec | Float64 512^3 | 335.878 ms | 171.154 ms | 105.706 ms | 90.933 ms | 126.735 ms | 73.108 ms | 58.531 ms | 56.879 ms | — | — |
| maximum(norm) vec | Float64 64^3 | 638.372 μs | 330.043 μs | 170.297 μs | 89.581 μs | 200.822 μs | 101.681 μs | 52.230 μs | 28.440 μs | 101.994 μs | 33.560 μs |
| mean spectral vec | Float32 128^3 | 69.319 ns | 70.288 ns | 70.073 ns | 70.341 ns | 73.919 ns | 72.396 ns | 71.544 ns | 76.506 ns | 84.886 μs | 12.661 μs |
| mean spectral vec | Float32 256^3 | 70.248 ns | 70.600 ns | 71.020 ns | 70.709 ns | 73.976 ns | 73.150 ns | 72.117 ns | 72.425 ns | 82.019 μs | 12.700 μs |
| mean spectral vec | Float32 512^3 | 70.829 ns | 75.805 ns | 71.486 ns | 71.609 ns | 74.483 ns | 74.155 ns | 75.026 ns | 73.194 ns | — | — |
| mean spectral vec | Float32 64^3 | 69.851 ns | 70.131 ns | 69.954 ns | 74.169 ns | 76.115 ns | 73.865 ns | 71.048 ns | 74.567 ns | 84.518 μs | 12.870 μs |
| mean spectral vec | Float64 128^3 | 71.652 ns | 71.032 ns | 72.512 ns | 73.094 ns | 77.486 ns | 76.192 ns | 77.119 ns | 78.135 ns | 83.197 μs | 13.080 μs |
| mean spectral vec | Float64 256^3 | 71.587 ns | 71.739 ns | 77.971 ns | 74.189 ns | 79.392 ns | 77.658 ns | 79.929 ns | 75.757 ns | 76.042 μs | 12.850 μs |
| mean spectral vec | Float64 512^3 | 71.662 ns | 72.750 ns | 73.661 ns | 73.851 ns | 81.714 ns | 80.280 ns | 83.489 ns | 79.814 ns | — | — |
| mean spectral vec | Float64 64^3 | 71.432 ns | 70.993 ns | 71.713 ns | 72.426 ns | 78.617 ns | 78.574 ns | 79.546 ns | 79.545 ns | 84.016 μs | 13.040 μs |
| mean vector | Float32 128^3 | 457.741 μs | 290.287 μs | 181.836 μs | 86.000 μs | 196.452 μs | 106.832 μs | 60.631 μs | 45.211 μs | 404.816 μs | 97.041 μs |
| mean vector | Float32 256^3 | 6.663 ms | 5.717 ms | 5.286 ms | 4.986 ms | 2.955 ms | 2.601 ms | 2.378 ms | 2.428 ms | 1.876 ms | 532.326 μs |
| mean vector | Float32 512^3 | 57.992 ms | 49.331 ms | 45.188 ms | 43.812 ms | 28.612 ms | 27.453 ms | 26.914 ms | 27.202 ms | — | — |
| mean vector | Float32 64^3 | 41.594 μs | 26.265 μs | 18.553 μs | 26.047 μs | 26.260 μs | 16.101 μs | 13.271 μs | 16.670 μs | 237.930 μs | 55.111 μs |
| mean vector | Float64 128^3 | 1.454 ms | 916.718 μs | 789.970 μs | 722.330 μs | 405.604 μs | 206.232 μs | 109.711 μs | 83.171 μs | 436.976 μs | 105.791 μs |
| mean vector | Float64 256^3 | 15.053 ms | 12.179 ms | 11.002 ms | 10.392 ms | 8.764 ms | 7.028 ms | 6.598 ms | 6.607 ms | 2.213 ms | 578.496 μs |
| mean vector | Float64 512^3 | 113.045 ms | 96.366 ms | 91.023 ms | 87.599 ms | 59.155 ms | 55.405 ms | 54.357 ms | 54.957 ms | — | — |
| mean vector | Float64 64^3 | 82.736 μs | 51.562 μs | 31.910 μs | 28.569 μs | 46.641 μs | 31.170 μs | 19.820 μs | 18.480 μs | 243.020 μs | 60.311 μs |
| mean(det) tensor | Float32 128^3 | 2.323 ms | 1.869 ms | 1.600 ms | 1.471 ms | 773.457 μs | 364.684 μs | 197.372 μs | 122.662 μs | 182.169 μs | 113.481 μs |
| mean(det) tensor | Float32 256^3 | 22.209 ms | 20.586 ms | 18.188 ms | 17.283 ms | 15.771 ms | 11.669 ms | 10.300 ms | 10.414 ms | 1.084 ms | 744.398 μs |
| mean(det) tensor | Float32 512^3 | 173.675 ms | 164.058 ms | 150.746 ms | 142.971 ms | 105.720 ms | 95.093 ms | 84.211 ms | 85.725 ms | — | — |
| mean(det) tensor | Float32 64^3 | 99.580 μs | 57.158 μs | 29.346 μs | 21.386 μs | 67.911 μs | 36.300 μs | 21.080 μs | 15.120 μs | 86.588 μs | 24.960 μs |
| mean(det) tensor | Float64 128^3 | 5.198 ms | 4.542 ms | 3.897 ms | 3.632 ms | 2.559 ms | 1.501 ms | 1.203 ms | 1.215 ms | 256.306 μs | 202.542 μs |
| mean(det) tensor | Float64 256^3 | 41.684 ms | 41.616 ms | 37.660 ms | 35.455 ms | 30.046 ms | 23.878 ms | 21.582 ms | 21.552 ms | 1.728 ms | 1.449 ms |
| mean(det) tensor | Float64 512^3 | 331.474 ms | 326.591 ms | 302.221 ms | 284.814 ms | 228.934 ms | 185.116 ms | 169.237 ms | 172.437 ms | — | — |
| mean(det) tensor | Float64 64^3 | 220.525 μs | 129.689 μs | 74.208 μs | 39.665 μs | 168.142 μs | 67.661 μs | 36.360 μs | 28.720 μs | 94.284 μs | 28.840 μs |
| mean(norm) vec | Float32 128^3 | 1.562 ms | 802.624 μs | 408.758 μs | 211.664 μs | 611.166 μs | 301.773 μs | 155.732 μs | 84.761 μs | 246.831 μs | 41.551 μs |
| mean(norm) vec | Float32 256^3 | 13.077 ms | 7.487 ms | 5.720 ms | 4.996 ms | 7.630 ms | 3.581 ms | 2.334 ms | 2.129 ms | 852.710 μs | 282.373 μs |
| mean(norm) vec | Float32 512^3 | 102.254 ms | 62.285 ms | 49.569 ms | 45.418 ms | 51.592 ms | 36.426 ms | 29.222 ms | 28.205 ms | — | — |
| mean(norm) vec | Float32 64^3 | 189.104 μs | 99.893 μs | 52.618 μs | 43.256 μs | 76.531 μs | 39.851 μs | 21.090 μs | 13.021 μs | 91.394 μs | 20.030 μs |
| mean(norm) vec | Float64 128^3 | 5.166 ms | 2.645 ms | 1.361 ms | 814.529 μs | 1.451 ms | 724.877 μs | 364.814 μs | 194.562 μs | 224.808 μs | 113.051 μs |
| mean(norm) vec | Float64 256^3 | 41.451 ms | 21.184 ms | 12.794 ms | 10.855 ms | 13.324 ms | 8.210 ms | 5.873 ms | 5.829 ms | 1.399 ms | 744.878 μs |
| mean(norm) vec | Float64 512^3 | 331.360 ms | 168.987 ms | 104.467 ms | 91.298 ms | 113.281 ms | 71.836 ms | 57.876 ms | 56.753 ms | — | — |
| mean(norm) vec | Float64 64^3 | 631.447 μs | 326.384 μs | 165.195 μs | 88.981 μs | 179.141 μs | 91.741 μs | 47.980 μs | 26.601 μs | 97.775 μs | 29.230 μs |
| mean(tr) tensor | Float32 128^3 | 377.815 μs | 237.337 μs | 141.667 μs | 73.468 μs | 193.452 μs | 95.311 μs | 52.290 μs | 36.960 μs | 147.171 μs | 39.320 μs |
| mean(tr) tensor | Float32 256^3 | 6.459 ms | 5.949 ms | 5.334 ms | 4.969 ms | 3.197 ms | 2.380 ms | 2.203 ms | 2.248 ms | 695.424 μs | 274.963 μs |
| mean(tr) tensor | Float32 512^3 | 51.978 ms | 50.257 ms | 46.962 ms | 44.948 ms | 33.637 ms | 31.377 ms | 27.724 ms | 28.224 ms | — | — |
| mean(tr) tensor | Float32 64^3 | 34.418 μs | 18.605 μs | 11.840 μs | 9.824 μs | 25.450 μs | 12.570 μs | 8.070 μs | 6.330 μs | 82.494 μs | 20.170 μs |
| mean(tr) tensor | Float64 128^3 | 1.252 ms | 947.870 μs | 806.696 μs | 701.626 μs | 395.014 μs | 178.902 μs | 93.931 μs | 74.211 μs | 163.239 μs | 48.340 μs |
| mean(tr) tensor | Float64 256^3 | 12.163 ms | 12.166 ms | 11.286 ms | 10.634 ms | 7.026 ms | 6.539 ms | 6.370 ms | 6.234 ms | 873.694 μs | 500.395 μs |
| mean(tr) tensor | Float64 512^3 | 101.851 ms | 98.339 ms | 93.479 ms | 89.579 ms | 78.651 ms | 60.699 ms | 55.700 ms | 56.931 ms | — | — |
| mean(tr) tensor | Float64 64^3 | 67.405 μs | 36.863 μs | 19.348 μs | 14.849 μs | 50.970 μs | 24.470 μs | 14.221 μs | 10.170 μs | 84.623 μs | 21.360 μs |
| radial_correlation vec | Float32 128^3 | 35.464 ms | 30.684 ms | 31.999 ms | 32.226 ms | 30.250 ms | 21.843 ms | 21.607 ms | 20.799 ms | 757.017 μs | 538.235 μs |
| radial_correlation vec | Float32 256^3 | 392.471 ms | 259.641 ms | 255.979 ms | 242.034 ms | 279.445 ms | 178.171 ms | 155.845 ms | 158.980 ms | 9.446 ms | 6.336 ms |
| radial_correlation vec | Float32 512^3 | 3.387 s | 2.435 s | 1.827 s | 1.583 s | 2.760 s | 1.743 s | 1.282 s | 1.106 s | — | — |
| radial_correlation vec | Float32 64^3 | 4.187 ms | 4.913 ms | 5.482 ms | 5.742 ms | 3.519 ms | 3.292 ms | 3.730 ms | 3.454 ms | 228.570 μs | 153.551 μs |
| radial_correlation vec | Float64 128^3 | 44.171 ms | 41.317 ms | 37.236 ms | 35.077 ms | 37.444 ms | 33.975 ms | 24.580 ms | 23.638 ms | 36.046 ms | 1.878 ms |
| radial_correlation vec | Float64 256^3 | 523.535 ms | 410.010 ms | 361.747 ms | 290.639 ms | 476.153 ms | 320.011 ms | 270.548 ms | 244.050 ms | 130.153 ms | 14.580 ms |
| radial_correlation vec | Float64 512^3 | 5.475 s | 3.660 s | 2.811 s | 2.485 s | 4.311 s | 2.792 s | 1.967 s | 1.727 s | — | — |
| radial_correlation vec | Float64 64^3 | 5.164 ms | 5.051 ms | 5.090 ms | 5.320 ms | 3.823 ms | 3.356 ms | 3.261 ms | 3.355 ms | 13.247 ms | 257.092 μs |
| radial_spectrum vec | Float32 128^3 | 7.477 ms | 6.774 ms | 8.385 ms | 7.613 ms | 6.328 ms | 4.769 ms | 5.731 ms | 5.831 ms | 319.683 μs | 172.952 μs |
| radial_spectrum vec | Float32 256^3 | 59.549 ms | 41.911 ms | 46.370 ms | 43.154 ms | 50.112 ms | 33.734 ms | 30.885 ms | 29.936 ms | 919.249 μs | 824.718 μs |
| radial_spectrum vec | Float32 512^3 | 480.274 ms | 341.173 ms | 265.040 ms | 230.390 ms | 399.577 ms | 238.150 ms | 181.107 ms | 153.786 ms | — | — |
| radial_spectrum vec | Float32 64^3 | 984.146 μs | 1.336 ms | 1.604 ms | 1.591 ms | 821.738 μs | 869.578 μs | 1.178 ms | 1.280 ms | 221.808 μs | 70.131 μs |
| radial_spectrum vec | Float64 128^3 | 7.560 ms | 6.497 ms | 5.989 ms | 5.850 ms | 6.543 ms | 4.581 ms | 4.535 ms | 4.304 ms | 16.969 ms | 250.862 μs |
| radial_spectrum vec | Float64 256^3 | 60.139 ms | 45.320 ms | 34.988 ms | 31.584 ms | 51.926 ms | 32.112 ms | 26.082 ms | 22.797 ms | 53.477 ms | 1.137 ms |
| radial_spectrum vec | Float64 512^3 | 480.439 ms | 353.578 ms | 219.456 ms | 169.880 ms | 414.658 ms | 255.715 ms | 169.072 ms | 124.622 ms | — | — |
| radial_spectrum vec | Float64 64^3 | 981.356 μs | 747.168 μs | 1.051 ms | 1.079 ms | 846.298 μs | 691.227 μs | 848.008 μs | 893.579 μs | 7.026 ms | 77.171 μs |
| reality_residual scalar | Float32 128^3 | 217.636 μs | 217.142 μs | 219.299 μs | 218.391 μs | 168.162 μs | 167.272 μs | 168.391 μs | 167.512 μs | 240.668 μs | 82.831 μs |
| reality_residual scalar | Float32 256^3 | 990.443 μs | 989.844 μs | 985.893 μs | 977.974 μs | 684.498 μs | 686.717 μs | 689.117 μs | 686.127 μs | 215.716 μs | 82.941 μs |
| reality_residual scalar | Float32 512^3 | 8.067 ms | 8.021 ms | 8.046 ms | 7.901 ms | 2.720 ms | 2.762 ms | 2.799 ms | 2.770 ms | — | — |
| reality_residual scalar | Float32 64^3 | 49.221 μs | 49.150 μs | 48.627 μs | 49.073 μs | 41.431 μs | 40.840 μs | 41.201 μs | 40.790 μs | 228.217 μs | 80.561 μs |
| reality_residual scalar | Float64 128^3 | 360.195 μs | 360.022 μs | 358.108 μs | 362.629 μs | 351.434 μs | 351.564 μs | 353.093 μs | 353.034 μs | 238.806 μs | 97.651 μs |
| reality_residual scalar | Float64 256^3 | 1.619 ms | 1.588 ms | 1.576 ms | 1.584 ms | 1.433 ms | 1.436 ms | 1.420 ms | 1.421 ms | 221.526 μs | 99.351 μs |
| reality_residual scalar | Float64 512^3 | 13.085 ms | 12.727 ms | 12.682 ms | 12.379 ms | 5.866 ms | 5.857 ms | 5.861 ms | 5.826 ms | — | — |
| reality_residual scalar | Float64 64^3 | 79.055 μs | 78.900 μs | 78.673 μs | 79.064 μs | 86.501 μs | 86.551 μs | 86.481 μs | 85.761 μs | 233.248 μs | 96.761 μs |
| reality_residual vector | Float32 128^3 | 801.717 μs | 799.958 μs | 802.354 μs | 812.413 μs | 656.336 μs | 654.547 μs | 647.486 μs | 649.897 μs | 256.705 μs | 86.441 μs |
| reality_residual vector | Float32 256^3 | 5.948 ms | 5.216 ms | 5.132 ms | 5.219 ms | 2.640 ms | 2.619 ms | 2.609 ms | 2.625 ms | 293.252 μs | 90.921 μs |
| reality_residual vector | Float32 512^3 | 34.427 ms | 34.269 ms | 34.625 ms | 34.277 ms | 16.707 ms | 16.561 ms | 16.481 ms | 16.969 ms | — | — |
| reality_residual vector | Float32 64^3 | 185.114 μs | 185.327 μs | 185.433 μs | 186.000 μs | 161.401 μs | 161.032 μs | 162.261 μs | 164.432 μs | 247.060 μs | 85.911 μs |
| reality_residual vector | Float64 128^3 | 1.266 ms | 1.268 ms | 1.263 ms | 1.268 ms | 1.247 ms | 1.250 ms | 1.250 ms | 1.244 ms | 256.409 μs | 98.111 μs |
| reality_residual vector | Float64 256^3 | 8.746 ms | 9.012 ms | 8.819 ms | 8.712 ms | 5.023 ms | 5.040 ms | 5.013 ms | 5.072 ms | 293.697 μs | 118.111 μs |
| reality_residual vector | Float64 512^3 | 47.450 ms | 47.912 ms | 47.924 ms | 48.070 ms | 35.599 ms | 35.030 ms | 34.773 ms | 35.472 ms | — | — |
| reality_residual vector | Float64 64^3 | 269.141 μs | 271.558 μs | 272.197 μs | 274.561 μs | 309.283 μs | 310.203 μs | 308.733 μs | 309.473 μs | 244.756 μs | 96.221 μs |
| var scalar | Float32 128^3 | 233.568 μs | 129.219 μs | 66.215 μs | 45.657 μs | 131.172 μs | 73.391 μs | 42.870 μs | 28.130 μs | 266.533 μs | 64.440 μs |
| var scalar | Float32 256^3 | 4.071 ms | 3.143 ms | 2.658 ms | 2.445 ms | 1.257 ms | 627.077 μs | 340.133 μs | 203.692 μs | 1.225 ms | 353.414 μs |
| var scalar | Float32 512^3 | 38.132 ms | 31.942 ms | 29.590 ms | 29.102 ms | 27.547 ms | 20.549 ms | 18.109 ms | 17.774 ms | — | — |
| var scalar | Float32 64^3 | 24.936 μs | 16.622 μs | 11.799 μs | 14.495 μs | 14.640 μs | 9.051 μs | 7.330 μs | 8.870 μs | 167.346 μs | 37.000 μs |
| var scalar | Float64 128^3 | 510.335 μs | 267.802 μs | 131.516 μs | 83.287 μs | 249.073 μs | 128.081 μs | 75.171 μs | 48.641 μs | 316.275 μs | 66.331 μs |
| var scalar | Float64 256^3 | 8.776 ms | 7.404 ms | 6.536 ms | 6.125 ms | 3.559 ms | 2.401 ms | 1.668 ms | 1.848 ms | 1.522 ms | 388.644 μs |
| var scalar | Float64 512^3 | 74.745 ms | 64.150 ms | 60.248 ms | 58.417 ms | 43.189 ms | 38.893 ms | 36.797 ms | 36.198 ms | — | — |
| var scalar | Float64 64^3 | 51.968 μs | 26.136 μs | 17.964 μs | 16.488 μs | 30.690 μs | 17.810 μs | 11.170 μs | 11.220 μs | 155.162 μs | 38.890 μs |
| var spectral scalar | Float32 128^3 | 132.367 μs | 89.235 μs | 63.217 μs | 59.567 μs | 95.661 μs | 59.790 μs | 42.860 μs | 43.321 μs | 256.151 μs | 64.341 μs |
| var spectral scalar | Float32 256^3 | 2.340 ms | 1.926 ms | 1.609 ms | 1.459 ms | 754.978 μs | 406.894 μs | 292.553 μs | 249.133 μs | 474.853 μs | 151.092 μs |
| var spectral scalar | Float32 512^3 | 20.042 ms | 17.579 ms | 16.916 ms | 16.059 ms | 12.682 ms | 10.480 ms | 10.813 ms | 10.860 ms | — | — |
| var spectral scalar | Float32 64^3 | 16.561 μs | 11.978 μs | 10.038 μs | 11.212 μs | 11.030 μs | 8.130 μs | 7.280 μs | 9.700 μs | 227.632 μs | 60.601 μs |
| var spectral scalar | Float64 128^3 | 281.477 μs | 171.930 μs | 109.940 μs | 86.943 μs | 147.541 μs | 87.031 μs | 61.850 μs | 54.271 μs | 269.628 μs | 69.811 μs |
| var spectral scalar | Float64 256^3 | 4.669 ms | 4.082 ms | 3.665 ms | 3.466 ms | 2.256 ms | 1.389 ms | 1.066 ms | 1.095 ms | 574.051 μs | 233.412 μs |
| var spectral scalar | Float64 512^3 | 40.328 ms | 34.563 ms | 33.220 ms | 31.815 ms | 21.690 ms | 20.627 ms | 20.441 ms | 20.498 ms | — | — |
| var spectral scalar | Float64 64^3 | 30.342 μs | 18.939 μs | 14.362 μs | 13.812 μs | 20.040 μs | 12.810 μs | 9.460 μs | 11.030 μs | 214.070 μs | 57.091 μs |
| weighted_inner vec | Float32 128^3 | 1.695 ms | 886.084 μs | 505.142 μs | 372.993 μs | 1.360 ms | 685.327 μs | 346.384 μs | 177.012 μs | 259.148 μs | 74.331 μs |
| weighted_inner vec | Float32 256^3 | 16.562 ms | 12.438 ms | 10.860 ms | 10.078 ms | 11.335 ms | 5.636 ms | 3.557 ms | 3.514 ms | 1.445 ms | 550.355 μs |
| weighted_inner vec | Float32 512^3 | 131.120 ms | 105.873 ms | 96.336 ms | 89.264 ms | 92.604 ms | 63.924 ms | 55.997 ms | 54.459 ms | — | — |
| weighted_inner vec | Float32 64^3 | 219.115 μs | 220.093 μs | 219.740 μs | 223.011 μs | 184.691 μs | 187.141 μs | 184.692 μs | 185.292 μs | 120.668 μs | 26.150 μs |
| weighted_inner vec | Float64 128^3 | 3.185 ms | 2.383 ms | 1.865 ms | 1.591 ms | 1.429 ms | 721.187 μs | 361.834 μs | 205.802 μs | 303.043 μs | 98.121 μs |
| weighted_inner vec | Float64 256^3 | 29.764 ms | 25.092 ms | 22.906 ms | 21.466 ms | 16.142 ms | 11.210 ms | 10.093 ms | 10.224 ms | 1.823 ms | 984.110 μs |
| weighted_inner vec | Float64 512^3 | 239.076 ms | 208.228 ms | 191.032 ms | 177.558 ms | 128.962 ms | 114.216 ms | 112.341 ms | 111.688 ms | — | — |
| weighted_inner vec | Float64 64^3 | 251.985 μs | 252.396 μs | 252.915 μs | 252.062 μs | 193.782 μs | 194.102 μs | 195.962 μs | 195.572 μs | 121.755 μs | 27.870 μs |
| weighted_inner vec.vec | Float32 128^3 | 2.134 ms | 1.559 ms | 1.246 ms | 1.084 ms | 1.390 ms | 697.227 μs | 366.533 μs | 187.402 μs | 260.864 μs | 91.731 μs |
| weighted_inner vec.vec | Float32 256^3 | 21.883 ms | 18.853 ms | 17.354 ms | 16.123 ms | 12.909 ms | 8.544 ms | 7.219 ms | 7.280 ms | 1.416 ms | 746.987 μs |
| weighted_inner vec.vec | Float32 512^3 | 187.990 ms | 161.941 ms | 147.322 ms | 135.052 ms | 103.520 ms | 90.046 ms | 85.474 ms | 84.781 ms | — | — |
| weighted_inner vec.vec | Float32 64^3 | 220.192 μs | 220.918 μs | 219.916 μs | 237.681 μs | 192.912 μs | 189.602 μs | 189.742 μs | 193.592 μs | 117.012 μs | 26.221 μs |
| weighted_inner vec.vec | Float64 128^3 | 4.750 ms | 4.000 ms | 3.509 ms | 3.155 ms | 1.955 ms | 1.049 ms | 635.257 μs | 535.806 μs | 304.008 μs | 178.332 μs |
| weighted_inner vec.vec | Float64 256^3 | 43.275 ms | 38.833 ms | 35.509 ms | 33.172 ms | 24.296 ms | 19.242 ms | 17.856 ms | 17.882 ms | 1.827 ms | 1.457 ms |
| weighted_inner vec.vec | Float64 512^3 | 331.870 ms | 312.288 ms | 288.353 ms | 267.484 ms | 203.568 ms | 176.236 ms | 170.131 ms | 170.497 ms | — | — |
| weighted_inner vec.vec | Float64 64^3 | 276.710 μs | 283.295 μs | 277.089 μs | 305.118 μs | 207.032 μs | 210.762 μs | 213.252 μs | 204.082 μs | 123.490 μs | 28.240 μs |
| weighted_inner x3 fused | Float32 128^3 | 6.103 ms | 3.106 ms | 1.592 ms | 821.368 μs | 5.073 ms | 2.473 ms | 1.270 ms | 639.767 μs | 318.167 μs | 121.521 μs |
| weighted_inner x3 fused | Float32 256^3 | 46.923 ms | 23.908 ms | 12.299 ms | 6.483 ms | 39.735 ms | 19.348 ms | 9.949 ms | 4.995 ms | 1.893 ms | 867.169 μs |
| weighted_inner x3 fused | Float32 512^3 | 367.215 ms | 185.819 ms | 95.656 ms | 52.095 ms | 314.641 ms | 153.118 ms | 77.573 ms | 40.135 ms | — | — |
| weighted_inner x3 fused | Float32 64^3 | 833.923 μs | 820.299 μs | 832.791 μs | 828.867 μs | 656.317 μs | 654.606 μs | 655.467 μs | 638.187 μs | 135.193 μs | 35.570 μs |
| weighted_inner x3 fused | Float64 128^3 | 6.119 ms | 3.206 ms | 1.653 ms | 966.939 μs | 5.083 ms | 2.505 ms | 1.276 ms | 643.336 μs | 501.184 μs | 201.922 μs |
| weighted_inner x3 fused | Float64 256^3 | 47.854 ms | 24.254 ms | 13.581 ms | 11.272 ms | 40.261 ms | 19.677 ms | 10.025 ms | 5.727 ms | 3.340 ms | 1.377 ms |
| weighted_inner x3 fused | Float64 512^3 | 366.368 ms | 187.843 ms | 107.522 ms | 92.055 ms | 316.140 ms | 156.115 ms | 79.955 ms | 55.188 ms | — | — |
| weighted_inner x3 fused | Float64 64^3 | 805.947 μs | 806.894 μs | 806.588 μs | 841.813 μs | 660.727 μs | 637.857 μs | 653.997 μs | 654.157 μs | 153.153 μs | 48.701 μs |
| weighted_inner x3 separate | Float32 128^3 | 8.102 ms | 4.158 ms | 2.139 ms | 1.113 ms | 6.323 ms | 3.135 ms | 1.574 ms | 813.328 μs | 781.492 μs | 264.132 μs |
| weighted_inner x3 separate | Float32 256^3 | 61.110 ms | 31.999 ms | 19.097 ms | 16.166 ms | 49.600 ms | 23.500 ms | 12.092 ms | 6.887 ms | 4.854 ms | 1.729 ms |
| weighted_inner x3 separate | Float32 512^3 | 465.489 ms | 246.695 ms | 155.806 ms | 139.931 ms | 394.257 ms | 185.447 ms | 106.058 ms | 81.642 ms | — | — |
| weighted_inner x3 separate | Float32 64^3 | 1.125 ms | 1.056 ms | 1.056 ms | 1.094 ms | 828.428 μs | 828.098 μs | 827.719 μs | 826.839 μs | 380.315 μs | 86.290 μs |
| weighted_inner x3 separate | Float64 128^3 | 9.523 ms | 5.252 ms | 3.250 ms | 2.584 ms | 5.877 ms | 2.953 ms | 1.560 ms | 805.609 μs | 1.029 ms | 316.023 μs |
| weighted_inner x3 separate | Float64 256^3 | 74.488 ms | 45.958 ms | 35.469 ms | 32.590 ms | 51.938 ms | 25.906 ms | 17.581 ms | 16.750 ms | 6.246 ms | 2.075 ms |
| weighted_inner x3 separate | Float64 512^3 | 596.612 ms | 368.949 ms | 284.424 ms | 267.403 ms | 399.158 ms | 219.854 ms | 164.697 ms | 164.164 ms | — | — |
| weighted_inner x3 separate | Float64 64^3 | 1.164 ms | 1.113 ms | 1.113 ms | 1.112 ms | 816.428 μs | 815.938 μs | 812.978 μs | 815.219 μs | 396.794 μs | 97.271 μs |

## storage

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| adapt multipliers | Float32 128^3 | — | — | — | — | — | — | — | — | 148.135 μs | 11.680 μs |
| adapt multipliers | Float32 256^3 | — | — | — | — | — | — | — | — | 141.393 μs | 12.620 μs |
| adapt multipliers | Float32 512^3 | — | — | — | — | — | — | — | — | 148.798 μs | — |
| adapt multipliers | Float32 64^3 | — | — | — | — | — | — | — | — | 151.351 μs | 12.370 μs |
| adapt multipliers | Float64 128^3 | — | — | — | — | — | — | — | — | 151.754 μs | 11.890 μs |
| adapt multipliers | Float64 256^3 | — | — | — | — | — | — | — | — | 138.203 μs | 12.700 μs |
| adapt multipliers | Float64 64^3 | — | — | — | — | — | — | — | — | 147.328 μs | 12.460 μs |
| adapt plans (rebuild) | Float32 128^3 | — | — | — | — | — | — | — | — | 15.587 μs | 7.940 μs |
| adapt plans (rebuild) | Float32 256^3 | — | — | — | — | — | — | — | — | 60.891 μs | 65.061 μs |
| adapt plans (rebuild) | Float32 512^3 | — | — | — | — | — | — | — | — | 61.057 μs | — |
| adapt plans (rebuild) | Float32 64^3 | — | — | — | — | — | — | — | — | 11.484 μs | 7.670 μs |
| adapt plans (rebuild) | Float64 128^3 | — | — | — | — | — | — | — | — | 21.753 μs | 8.480 μs |
| adapt plans (rebuild) | Float64 256^3 | — | — | — | — | — | — | — | — | 61.116 μs | 63.931 μs |
| adapt plans (rebuild) | Float64 64^3 | — | — | — | — | — | — | — | — | 11.861 μs | 7.560 μs |
| adapt to device scalar | Float32 128^3 | — | — | — | — | — | — | — | — | 674.199 μs | 306.153 μs |
| adapt to device scalar | Float32 256^3 | — | — | — | — | — | — | — | — | 5.650 ms | 2.442 ms |
| adapt to device scalar | Float32 512^3 | — | — | — | — | — | — | — | — | 42.595 ms | — |
| adapt to device scalar | Float32 64^3 | — | — | — | — | — | — | — | — | 125.110 μs | 61.210 μs |
| adapt to device scalar | Float64 128^3 | — | — | — | — | — | — | — | — | 1.325 ms | 596.516 μs |
| adapt to device scalar | Float64 256^3 | — | — | — | — | — | — | — | — | 11.225 ms | 6.108 ms |
| adapt to device scalar | Float64 64^3 | — | — | — | — | — | — | — | — | 178.715 μs | 93.271 μs |
| adapt to device vector | Float32 128^3 | — | — | — | — | — | — | — | — | 2.000 ms | 884.409 μs |
| adapt to device vector | Float32 256^3 | — | — | — | — | — | — | — | — | 16.370 ms | 9.309 ms |
| adapt to device vector | Float32 512^3 | — | — | — | — | — | — | — | — | 125.982 ms | — |
| adapt to device vector | Float32 64^3 | — | — | — | — | — | — | — | — | 248.478 μs | 129.501 μs |
| adapt to device vector | Float64 128^3 | — | — | — | — | — | — | — | — | 4.311 ms | 1.772 ms |
| adapt to device vector | Float64 256^3 | — | — | — | — | — | — | — | — | 32.095 ms | 19.782 ms |
| adapt to device vector | Float64 64^3 | — | — | — | — | — | — | — | — | 507.018 μs | 236.553 μs |
| adapt to host scalar | Float32 128^3 | — | — | — | — | — | — | — | — | 515.028 μs | 431.574 μs |
| adapt to host scalar | Float32 256^3 | — | — | — | — | — | — | — | — | 12.760 ms | 11.107 ms |
| adapt to host scalar | Float32 512^3 | — | — | — | — | — | — | — | — | 92.049 ms | — |
| adapt to host scalar | Float32 64^3 | — | — | — | — | — | — | — | — | 113.784 μs | 63.360 μs |
| adapt to host scalar | Float64 128^3 | — | — | — | — | — | — | — | — | 1.023 ms | 846.988 μs |
| adapt to host scalar | Float64 256^3 | — | — | — | — | — | — | — | — | 23.683 ms | 22.800 ms |
| adapt to host scalar | Float64 64^3 | — | — | — | — | — | — | — | — | 129.384 μs | 117.062 μs |
| adapt to host vector | Float32 128^3 | — | — | — | — | — | — | — | — | 1.528 ms | 1.269 ms |
| adapt to host vector | Float32 256^3 | — | — | — | — | — | — | — | — | 34.980 ms | 33.463 ms |
| adapt to host vector | Float32 512^3 | — | — | — | — | — | — | — | — | 279.396 ms | — |
| adapt to host vector | Float32 64^3 | — | — | — | — | — | — | — | — | 194.127 μs | 169.561 μs |
| adapt to host vector | Float64 128^3 | — | — | — | — | — | — | — | — | 8.957 ms | 8.194 ms |
| adapt to host vector | Float64 256^3 | — | — | — | — | — | — | — | — | 69.007 ms | 69.071 ms |
| adapt to host vector | Float64 64^3 | — | — | — | — | — | — | — | — | 382.342 μs | 323.783 μs |
| adapt to own family (identity) | Float32 128^3 | — | — | — | — | — | — | — | — | 149.488 ns | 128.879 ns |
| adapt to own family (identity) | Float32 256^3 | — | — | — | — | — | — | — | — | 145.939 ns | 128.254 ns |
| adapt to own family (identity) | Float32 512^3 | — | — | — | — | — | — | — | — | 241.471 ns | — |
| adapt to own family (identity) | Float32 64^3 | — | — | — | — | — | — | — | — | 146.944 ns | 128.400 ns |
| adapt to own family (identity) | Float64 128^3 | — | — | — | — | — | — | — | — | 152.816 ns | 122.509 ns |
| adapt to own family (identity) | Float64 256^3 | — | — | — | — | — | — | — | — | 153.522 ns | 123.246 ns |
| adapt to own family (identity) | Float64 64^3 | — | — | — | — | — | — | — | — | 152.136 ns | 126.877 ns |
| adapt! to device scalar | Float32 128^3 | — | — | — | — | — | — | — | — | 671.051 μs | 303.983 μs |
| adapt! to device scalar | Float32 256^3 | — | — | — | — | — | — | — | — | 5.271 ms | 2.425 ms |
| adapt! to device scalar | Float32 512^3 | — | — | — | — | — | — | — | — | 41.853 ms | — |
| adapt! to device scalar | Float32 64^3 | — | — | — | — | — | — | — | — | 113.841 μs | 58.780 μs |
| adapt! to device scalar | Float64 128^3 | — | — | — | — | — | — | — | — | 1.318 ms | 589.445 μs |
| adapt! to device scalar | Float64 256^3 | — | — | — | — | — | — | — | — | 10.457 ms | 6.010 ms |
| adapt! to device scalar | Float64 64^3 | — | — | — | — | — | — | — | — | 173.098 μs | 91.541 μs |
| adapt! to device vector | Float32 128^3 | — | — | — | — | — | — | — | — | 1.994 ms | 877.428 μs |
| adapt! to device vector | Float32 256^3 | — | — | — | — | — | — | — | — | 15.583 ms | 9.089 ms |
| adapt! to device vector | Float32 512^3 | — | — | — | — | — | — | — | — | 125.063 ms | — |
| adapt! to device vector | Float32 64^3 | — | — | — | — | — | — | — | — | 244.508 μs | 127.721 μs |
| adapt! to device vector | Float64 128^3 | — | — | — | — | — | — | — | — | 3.942 ms | 1.757 ms |
| adapt! to device vector | Float64 256^3 | — | — | — | — | — | — | — | — | 31.392 ms | 18.287 ms |
| adapt! to device vector | Float64 64^3 | — | — | — | — | — | — | — | — | 502.699 μs | 233.282 μs |
| adapt! to host scalar | Float32 128^3 | — | — | — | — | — | — | — | — | 515.392 μs | 427.684 μs |
| adapt! to host scalar | Float32 256^3 | — | — | — | — | — | — | — | — | 4.164 ms | 3.367 ms |
| adapt! to host scalar | Float32 512^3 | — | — | — | — | — | — | — | — | 34.165 ms | — |
| adapt! to host scalar | Float32 64^3 | — | — | — | — | — | — | — | — | 103.503 μs | 63.470 μs |
| adapt! to host scalar | Float64 128^3 | — | — | — | — | — | — | — | — | 1.037 ms | 847.598 μs |
| adapt! to host scalar | Float64 256^3 | — | — | — | — | — | — | — | — | 8.145 ms | 6.811 ms |
| adapt! to host scalar | Float64 64^3 | — | — | — | — | — | — | — | — | 135.753 μs | 115.181 μs |
| adapt! to host vector | Float32 128^3 | — | — | — | — | — | — | — | — | 1.513 ms | 1.268 ms |
| adapt! to host vector | Float32 256^3 | — | — | — | — | — | — | — | — | 12.621 ms | 10.127 ms |
| adapt! to host vector | Float32 512^3 | — | — | — | — | — | — | — | — | 100.159 ms | — |
| adapt! to host vector | Float32 64^3 | — | — | — | — | — | — | — | — | 195.120 μs | 169.212 μs |
| adapt! to host vector | Float64 128^3 | — | — | — | — | — | — | — | — | 3.066 ms | 2.522 ms |
| adapt! to host vector | Float64 256^3 | — | — | — | — | — | — | — | — | 24.748 ms | 20.237 ms |
| adapt! to host vector | Float64 64^3 | — | — | — | — | — | — | — | — | 388.190 μs | 323.093 μs |

## Triage — the born-slow scan

Two questions no per-row history can answer (finding (ag)): does a threaded operation actually scale, and is a row wildly slower than its class peers at the same workload. Flags are QUESTIONS, not verdicts — a `known` row carries its recorded reason, and an unexplained one is closed by a fix or by a recorded reason, never by deleting the row. Thresholds: flat means under 1.1x speedup lowest-to-highest thread lane with at least 1.000 ms of work; an outlier is over 8.0x its class median.

### A. Thread-flat on every host — 15 flagged (11 known)

| class | row | per-host (t_low, speedup) | note |
|:--|:--|:--|:--|
| reductions | co-spectrum vec.vec | Float32 128^3 | 12700K: 8.064 ms ×1.06; 9800X3D: 6.955 ms ×1.08 | **UNEXPLAINED** |
| reductions | co-spectrum vec.vec | Float32 64^3 | 12700K: 1.039 ms ×0.61 | **UNEXPLAINED** |
| reductions | co-spectrum vec.vec | Float64 64^3 | 12700K: 1.064 ms ×1.07 | **UNEXPLAINED** |
| reductions | cross-correlation vec.vec | Float32 64^3 | 12700K: 4.491 ms ×0.78; 9800X3D: 3.841 ms ×1.04 | known: the radial_correlation co-spectrum form — same materialization |
| reductions | radial_correlation vec | Float32 64^3 | 12700K: 4.187 ms ×0.73; 9800X3D: 3.519 ms ×1.02 | known: materializes its power field + inverse transform by design — decision 22 |
| reductions | radial_spectrum vec | Float32 128^3 | 12700K: 7.477 ms ×0.98; 9800X3D: 6.328 ms ×1.09 | **UNEXPLAINED** |
| reductions | reality_residual scalar | Float32 512^3 | 12700K: 8.067 ms ×1.02; 9800X3D: 2.720 ms ×0.98 | known: recorded: neither threads nor fuses — CLAUDE.md roadmap, decision 71 entry |
| reductions | reality_residual scalar | Float64 256^3 | 12700K: 1.619 ms ×1.02; 9800X3D: 1.433 ms ×1.01 | known: recorded: neither threads nor fuses — CLAUDE.md roadmap, decision 71 entry |
| reductions | reality_residual scalar | Float64 512^3 | 12700K: 13.085 ms ×1.06; 9800X3D: 5.866 ms ×1.01 | known: recorded: neither threads nor fuses — CLAUDE.md roadmap, decision 71 entry |
| reductions | reality_residual vector | Float32 512^3 | 12700K: 34.427 ms ×1.0; 9800X3D: 16.707 ms ×0.98 | known: recorded: neither threads nor fuses — CLAUDE.md roadmap, decision 71 entry |
| reductions | reality_residual vector | Float64 128^3 | 12700K: 1.266 ms ×1.0; 9800X3D: 1.247 ms ×1.0 | known: recorded: neither threads nor fuses — CLAUDE.md roadmap, decision 71 entry |
| reductions | reality_residual vector | Float64 256^3 | 12700K: 8.746 ms ×1.0; 9800X3D: 5.023 ms ×0.99 | known: recorded: neither threads nor fuses — CLAUDE.md roadmap, decision 71 entry |
| reductions | reality_residual vector | Float64 512^3 | 12700K: 47.450 ms ×0.99; 9800X3D: 35.599 ms ×1.0 | known: recorded: neither threads nor fuses — CLAUDE.md roadmap, decision 71 entry |
| reductions | weighted_inner x3 separate | Float32 64^3 | 12700K: 1.125 ms ×1.03 | known: the finding-(ac) pathology, FIXED 2026-08-30; BOTH hosts are now re-swept (2026-08-31) and the pathology is gone — the only surviving flags are the 64^3 rows, which carry ~1.1 ms of work against a 1 ms floor and are overhead-bound, not the pathology |
| reductions | weighted_inner x3 separate | Float64 64^3 | 12700K: 1.164 ms ×1.05 | known: the finding-(ac) pathology, FIXED 2026-08-30; BOTH hosts are now re-swept (2026-08-31) and the pathology is gone — the only surviving flags are the 64^3 rows, which carry ~1.1 ms of work against a 1 ms floor and are overhead-bound, not the pathology |

### B. Declared-peer violations — 0 flagged (0 known)


## Shipped slower? — the history scan

Every cell's whole committed history, read at once — the drift and the step-in-an-unwatched-row that the canary, the triage and a one-archive-against-its-predecessor write-up all miss.

**A flagged cell is a hypothesis, not a regression.** This table mixes hosts, sweep shapes and measurement regimes, and documented effects move rows with no code change. Confirm with a matched A/B against the commit before the step before calling one real. The scan reads the *committed* history, so a sweep merged in this same change appears only at the next regeneration.

```
parsed 46 versions of RESULTS.md; 7347 (row, column) cells in-regime

=== cells at least 1.25x slower at HEAD than their in-regime best: 111

  2.77x  adapt plans (rebuild)              Float32 256^3    GPU 5070TI          0.023(08-17) ->     0.065  n=12  PERSISTENT
  2.46x  materialize_kernel separable       Float64 512^3    CPU 12700K t2      63.370(08-07) ->   156.007  n=21  PERSISTENT
  2.22x  to_spectral vector                 Float32 512^3    GPU 7900XTX        20.298(08-07) ->    45.159  n=21  PERSISTENT
  1.91x  materialize_kernel separable       Float32 512^3    CPU 9800X3D t4     18.405(08-09) ->    35.141  n=25  PERSISTENT
  1.90x  materialize_kernel radial          Float32 512^3    CPU 9800X3D t4     16.917(08-09) ->    32.141  n=25  PERSISTENT
  1.76x  to_spectral vector measure         Float64 128^3    CPU 12700K t2      15.038(07-30) ->    26.414  n=25  PERSISTENT
  1.74x  to_spectral vector measure         Float32 256^3    CPU 12700K t4      59.081(08-07) ->   103.016  n=25  PERSISTENT
  1.74x  to_spectral scalar measure         Float64 256^3    CPU 12700K t4      38.813(08-07) ->    67.470  n=25  PERSISTENT
  1.74x  to_spectral vector measure         Float32 256^3    CPU 12700K t1     106.816(08-07) ->   185.611  n=25  PERSISTENT
  1.70x  to_spectral scalar measure         Float32 512^3    CPU 9800X3D t4    113.206(08-05) ->   192.895  n=25  PERSISTENT
  1.69x  to_spectral scalar measure         Float32 512^3    CPU 9800X3D t8     98.470(08-05) ->   166.208  n=25  PERSISTENT
  1.68x  to_spectral scalar measure         Float32 512^3    CPU 12700K t2     224.043(08-07) ->   376.988  n=21  PERSISTENT
  1.68x  maximum scalar                     Float64 128^3    CPU 12700K t8       0.079(07-30) ->     0.133  n=25  one-off?
  1.68x  interpolate! NUFFT                 Float32 64^3     GPU 7900XTX         0.414(08-07) ->     0.694  n=21  PERSISTENT
  1.67x  to_physical vector measure         Float64 128^3    CPU 12700K t2      18.363(08-07) ->    30.729  n=25  PERSISTENT
  1.66x  materialize_kernel separable       Float64 512^3    CPU 9800X3D t4     36.888(08-28) ->    61.319  n=25  one-off?
  1.65x  to_spectral vector                 Float64 128^3    CPU 12700K t8      12.273(08-07) ->    20.238  n=25  PERSISTENT
  1.62x  to_spectral vector measure         Float64 128^3    CPU 9800X3D t8      7.753(07-30) ->    12.576  n=25  one-off?
  1.62x  to_physical vector measure         Float32 256^3    CPU 12700K t1     125.496(08-07) ->   203.555  n=25  PERSISTENT
  1.62x  to_physical scalar measure         Float32 512^3    CPU 9800X3D t1    290.357(07-30) ->   470.885  n=25  PERSISTENT
  1.62x  to_spectral scalar                 Float64 256^3    CPU 12700K t4      46.038(08-07) ->    74.508  n=25  PERSISTENT
  1.62x  to_spectral scalar measure         Float32 512^3    CPU 9800X3D t2    165.853(08-09) ->   268.337  n=25  PERSISTENT
  1.61x  to_spectral scalar measure         Float64 256^3    CPU 9800X3D t2     36.865(08-09) ->    59.437  n=25  PERSISTENT
  1.59x  exponential_convolve! scalar       Float32 256^3    CPU 12700K t2      13.310(07-30) ->    21.168  n=25  one-off?
  1.57x  to_physical vector                 Float64 128^3    CPU 12700K t2      19.672(08-07) ->    30.903  n=25  PERSISTENT
  1.57x  to_physical vector measure         Float32 256^3    CPU 12700K t4      75.629(08-07) ->   118.558  n=25  PERSISTENT
  1.56x  to_spectral vector measure         Float64 128^3    CPU 12700K t8      12.680(08-07) ->    19.841  n=25  PERSISTENT
  1.56x  materialize_kernel radial          Float64 512^3    CPU 9800X3D t4     34.030(08-09) ->    53.247  n=25  PERSISTENT
  1.56x  to_physical scalar measure         Float32 512^3    CPU 9800X3D t2    188.250(07-30) ->   292.836  n=25  PERSISTENT
  1.55x  to_spectral vector measure         Float32 256^3    CPU 9800X3D t4     45.865(07-30) ->    71.275  n=25  PERSISTENT
  1.55x  to_physical vector                 Float32 512^3    GPU 7900XTX        36.129(08-07) ->    56.118  n=21  PERSISTENT
  1.55x  to_spectral vector measure         Float64 128^3    CPU 9800X3D t2     12.032(08-09) ->    18.613  n=25  PERSISTENT
  1.54x  to_physical scalar measure         Float64 256^3    CPU 9800X3D t2     42.443(08-05) ->    65.252  n=25  PERSISTENT
  1.53x  to_physical scalar                 Float64 256^3    CPU 12700K t4      51.637(08-07) ->    79.237  n=25  PERSISTENT
  1.53x  anterpolate! Lalescu(3,3)          Float64 512^3    CPU 9800X3D t4   3307.000(08-28) ->  5053.000  n=25  PERSISTENT
  1.53x  to_physical scalar measure         Float64 256^3    CPU 12700K t4      49.714(08-07) ->    75.893  n=25  PERSISTENT
  1.52x  to_physical scalar measure         Float32 512^3    CPU 9800X3D t4    145.316(07-30) ->   221.111  n=25  PERSISTENT
  1.51x  to_physical scalar measure         Float32 512^3    CPU 12700K t2     274.759(08-07) ->   415.796  n=21  PERSISTENT
  1.51x  anterpolate! Lalescu(3,3)          Float64 512^3    CPU 9800X3D t1  12551.000(07-30) -> 18985.000  n=25  PERSISTENT
  1.51x  to_physical vector measure         Float64 128^3    CPU 9800X3D t2     12.492(08-09) ->    18.895  n=25  PERSISTENT
  1.51x  to_physical scalar measure         Float32 512^3    CPU 9800X3D t8    131.139(08-10) ->   197.481  n=25  PERSISTENT
  1.49x  anterpolate! Lalescu(3,3)          Float64 512^3    CPU 9800X3D t2   6404.000(08-09) ->  9557.000  n=25  PERSISTENT
  1.48x  to_physical scalar                 Float64 256^3    CPU 9800X3D t2     49.727(08-05) ->    73.588  n=25  PERSISTENT
  1.47x  interpolate! NUFFT                 Float64 256^3    GPU 7900XTX        40.571(08-07) ->    59.798  n=21  PERSISTENT
  1.47x  interpolate! CatmullRom            Float64 256^3    GPU 7900XTX         1.048(08-07) ->     1.540  n=21  PERSISTENT

=== operations flagged in 3+ columns (a code regression usually crosses columns):
   7 columns  to_spectral vector measure
   7 columns  to_spectral scalar measure
   7 columns  to_physical scalar measure
   6 columns  to_physical vector measure
   5 columns  interpolate! NUFFT
   4 columns  to_spectral vector
   4 columns  anterpolate! Lalescu(3,3)
   4 columns  divergence!∘kernel vec->scalar
   3 columns  materialize_kernel separable
   3 columns  to_spectral scalar
   3 columns  exponential_convolve! scalar
   3 columns  helmholtz!∘kernel vec->vec
```
