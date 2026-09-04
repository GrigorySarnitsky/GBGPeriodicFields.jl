# Benchmark results

Minimum time per operation; `—` = not measured for that column (a device / grid / element-type combination not run). Generated 2026-09-04 at commit `84cd34aa` on Julia 1.12.7, assembled on host `Aiporetne` — a **multi-host** report (each device names its own host below). Columns are the supplied runs; grids and element types are in the row labels. **CPUs** — thread sweep 1/2/4/8: **i7-12700K** (8 P-cores — `Aiporetne`, 64³–**512³** both element types) and **Ryzen 9800X3D** (8 Zen 5 cores / 16 threads, 96 MB 3D V-Cache — `Enteropia`, 64³–**512³** both element types — the CPU production band of ARCHITECTURE.md decision 37; RAM bounds nothing at 123 GB); both CPU columns are measured at the decision-38/39 rewrite — slab-threaded assignments and the fused one-pass kernels, so thread scaling is monotone (the retired inversion the previous archive carried is finding (l) in PERFORMANCE.md §4). Both CPU columns now carry post-decision-40 threaded reductions — the fixed-tree reduce scaling monotonically with thread count (e.g. `maximum scalar` 128³ Float64, 9800X3D: 442 → 59 µs t1→t8) — so the reductions cells are cross-host comparable. **GPUs**, newest last: **RX 7900 XTX** (gfx1100, ROCm, 24 GB, power-capped 294 W — `Aiporetne`, 64³–256³ both types + 512³ `Float32`, the `transfer` and `reductions` classes omitted at 512³ — transfer's NUFFT oversamples to 1024³ and the radial diagnostics' working set hits the 24 GB ceiling); **RTX 5070 Ti** (Blackwell sm_120, CUDA, 16 GB — `Enteropia`, 64³–256³ both types; 512³ exceeds 16 GB — the `mul!` tensor field alone is 4.5 GB). **Two columns for since-retired cards were DROPPED on 2026-08-07** — both were measured under the `gcsample` regime of PERFORMANCE.md §4(s), which inflated device rows 2–29×, and neither card is in the fleet to re-sweep, so those columns could never be corrected or compared against anything measured after the fix. Every remaining column is measured at the decision-38/39 rewrite. **Both GPU columns are now in the fixed measurement regime and are comparable again.** Device lanes used to run with a blanket `gcsample = true`, so a full `GC.gc()` — whose finalizers free device buffers and synchronize — preceded every sample and dominated operations lasting tens of microseconds, inflating device rows 18.4–29.2× at ``64^3``, 5.8–19.8× at ``128^3`` and 1.9–4.25× at ``256^3`` on the AMD card. `gcsample` is now decided per row from a measured device-pool probe and kept only for rows that genuinely materialize. **GPU 7900XTX was re-swept 2026-08-07** (median −81.6%) and **GPU 5070TI on 2026-08-09** (median −46.4% over 426 rows). The NVIDIA correction is the smaller of the two because that vendor's collect-and-synchronize is cheaper, not because less was wrong: the CUDA branch of the probe called `CUDA.available_memory`, which is not a binding, so it threw on every row and the catch-all held every CUDA row on the collector until 2026-08-09 — see PERFORMANCE.md §4(w), and note that a fallback reported as a measurement is the reason that went unnoticed. CPU columns were never affected, `gcsample` being gated on the backend. See PERFORMANCE.md §4(s). **`fft` rows are comparable only within a column vintage, and the 2026-08-05 shift is `Enteropia`-specific.** That re-sweep of the 9800X3D lanes found the `fft` class 20–50% slower than the 2026-07-30 archive at the larger grids (``256^3`` `Float64` `to_physical scalar` t1: 83.8 → 116.0 ms), reproducible to under 1% across three standalone probes, while the other 596 rows moved by a median of −0.12% and the cuFFT lane showed no `fft` mover at all. It is not the package (zero changed lines on the transform path), not FFTW, and not Julia; a reboot fell between the two sweeps and no pre-reboot platform state was recorded. **The 2026-08-07 `Aiporetne` re-sweep is the control, and at the larger grids the shift does not reproduce:** across that host's 192 `fft` rows (four lanes × 48) against its 2026-07-22 archive, exactly **one** row at ``256^3`` moved slower and by +1.0%, where `Enteropia` moved +38%; per-lane medians run −4.5% to −6.8%. Twenty-three rows did move slower, but all except that one sit at ``64^3``/``128^3``, and the three exceeding 20% are small-grid high-thread-count cells where thread overhead dominates a sub-millisecond workload. This host's rows moved materially *faster* at the larger grids (up to a ratio of 0.54), which is no better explained, so a cross-vintage `fft` comparison is uninformative rather than evidence. `Aiporetne` runs kernel `7.0.0-28-generic`, the same version `Enteropia` recorded post-reboot, so a platform-wide kernel or microcode regression is not supported. **The 2026-08-09 `Enteropia` re-sweep settles it: the shift was a ONE-OFF, not a persistent state change.** Re-measuring t1/t2/t4 against the 2026-08-05 archive over an interval with no source changes, the `fft` class is flat — per-lane medians −1.1% to −1.4%, and at ``256^3`` specifically −3.7%, −6.5% and −1.2%, where the event being explained was +20–50%. Every other class is flat too (600 rows per lane, overall medians +0.0%, −0.2%, −0.2%), so the sweep reproduces itself and the instrument is sound. Those three lanes are also the first archives carrying stamped platform state (kernel, microcode, governor, SMT, transparent huge pages), so a recurrence is now falsifiable instead of unattributable. See PERFORMANCE.md §4(p). **Five CPU rows are process-history-sensitive and comparable only against same-shaped sweeps — PERFORMANCE.md §4(y).** The two `materialize_kernel` rows, `lpnorm vec Inf`, `radial_correlation vec` and `cross-correlation vec.vec` measure faster at low thread counts inside a full sweep than standalone (up to ``3.2\times`` for `materialize_kernel` at ``t1``, ``1.2``–``1.7\times`` for the reductions three), because their per-call field-sized allocation lands in a regime selected by what streamed through the process before them; the eight allocating `fft` rows are verified clean. Every CPU column here is a full sweep, so the table is self-consistent, but those cells must not be compared against a standalone probe or a class-only lane, and `materialize_kernel` thread scaling should be read from ``t4`` upward (the ``t2`` cell of `materialize_kernel separable` is bistable across sweeps). **The `CPU 9800X3D t8` column was assembled from FOUR per-grid runs, not one lane.** A single `-t8` process segfaults on `Enteropia` inside FFTW's threaded executor — PERFORMANCE.md §4(q), reproducible there and never seen on the other host — and failed three times running. Splitting the lane by grid (`CHAR_SIZES=64`, then 128, 256, 512) completes it: 64³, 256³ and 512³ passed first time and 128³ on its second attempt, and the four part-archives merge into one lane archive with disjoint rows, 150 per grid. That is what an uncrashed process would have written, and it is a harness workaround rather than a fix — the fault is unchanged and a plain `characterize.jl` invocation at `-t8` will still die here. The merged column is flat against the 2026-08-05 one it replaces (median +0.0% over 600 rows), and its largest movers are the `measure` twins, whose FFTW `MEASURE` plan search legitimately re-decides between runs. **Jitter at ``256^3`` is NOT bounded by the ~10% the paragraph above suggests, for the `Float32` gather rows.** `interpolate! trilinear`, `CatmullRom` and `Lalescu(3,3)` at ``256^3`` `Float32` move as a CORRELATED BLOCK between processes — all three the same direction within a run, by up to 31% — measured on the 9800X3D as ``0.73``/``0.82``/``0.86`` at `t1` and ``1.31``/``1.22``/``1.17`` at `t2` for the same code against the same archive. Direction varies by run, so it is per-process state rather than a systematic difference, but the standing advice to compare at ``256^3`` or above does not cover these three rows: read them across at least two sweeps. A row may name an operation the package has since REMOVED — `squared_wavenumber_field` was deleted by decision 60, its |k|² being a radial symbol rather than a field.Such rows are a historical measurement, not a callable surface, and they disappear the next time their lane is swept. The GPU sweep builds one (op-class, grid, element-type) at a time so the working set stays bounded (PERFORMANCE.md §7). **Regenerate** by re-sweeping the lanes you can measure — `characterize.jl` once per lane — and then invoking `report.jl` by hand over **every** archive in `benchmark/results/`, this table's own column list included. Do not use `characterize.sh` for a multi-host report: it passes only the lanes it just produced to `report.jl`, so the columns belonging to the other host and to retired cards would silently vanish (PERFORMANCE.md §6). **Column vintages** — the commit (and sweep date) each archive was measured at, stamped into its JSON by `characterize.jl`: `6581b433 @ 2026-08-31`: CPU 9800X3D t1, CPU 9800X3D t2, CPU 9800X3D t4, CPU 9800X3D t8, GPU 5070TI; `84cd34aa @ 2026-09-04`: CPU 12700K t1, CPU 12700K t2, CPU 12700K t4, CPU 12700K t8, GPU 7900XTX. **Jitter is ~10% for most cells but NOT uniform: it reaches 1.44x at small grids under high thread counts.** Measured on the 12700K, `mean(norm) vec` `Float32`, five repeats of the same measurement: at ``64^3`` `-t8` the minimum came out 31.2, 31.0, 31.3, 30.8 and 44.4 us, where the same row at `-t1` spans 1.01x and at ``256^3`` `-t8` spans 1.09x. The work there (~31 us) is comparable to the cost of spawning eight threads, and taking BenchmarkTools' minimum over a one-second budget does not suppress it. So a movement of tens of percent in a small-grid, high-thread cell is NOT evidence of anything; compare those at ``256^3`` or above, or at low thread counts. PERFORMANCE.md §4(u).

## fft

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| to_physical scalar measure | Float32 128^3 | 3.918 ms | 2.714 ms | 2.355 ms | 2.195 ms | 2.741 ms | 1.470 ms | 826.698 μs | 526.025 μs | — | — |
| to_physical scalar measure | Float32 256^3 | 40.787 ms | 27.828 ms | 24.381 ms | 23.142 ms | 32.865 ms | 20.339 ms | 14.660 ms | 11.720 ms | — | — |
| to_physical scalar measure | Float32 512^3 | 518.930 ms | 415.058 ms | 266.003 ms | 236.036 ms | 470.885 ms | 292.836 ms | 221.111 ms | 197.481 ms | — | — |
| to_physical scalar measure | Float32 64^3 | 372.401 μs | 239.133 μs | 167.030 μs | 136.804 μs | 276.223 μs | 157.201 μs | 95.731 μs | 71.040 μs | — | — |
| to_physical scalar measure | Float64 128^3 | 6.074 ms | 5.447 ms | 5.263 ms | 4.635 ms | 3.854 ms | 2.249 ms | 1.650 ms | 1.202 ms | — | — |
| to_physical scalar measure | Float64 256^3 | 100.561 ms | 65.859 ms | 53.371 ms | 51.162 ms | 83.575 ms | 65.252 ms | 41.326 ms | 45.523 ms | — | — |
| to_physical scalar measure | Float64 512^3 | 1.109 s | 758.793 ms | 647.602 ms | 602.269 ms | 832.369 ms | 553.215 ms | 441.802 ms | 401.231 ms | — | — |
| to_physical scalar measure | Float64 64^3 | 552.097 μs | 330.769 μs | 248.346 μs | 239.370 μs | 363.403 μs | 206.932 μs | 131.771 μs | 104.641 μs | — | — |
| to_physical scalar | Float32 128^3 | 4.907 ms | 3.194 ms | 2.387 ms | 2.489 ms | 4.515 ms | 2.467 ms | 1.290 ms | 774.129 μs | 109.907 μs | 68.131 μs |
| to_physical scalar | Float32 256^3 | 88.659 ms | 51.334 ms | 35.026 ms | 26.894 ms | 169.531 ms | 88.437 ms | 48.038 ms | 27.683 ms | 1.023 ms | 1.101 ms |
| to_physical scalar | Float32 512^3 | 1.318 s | 805.427 ms | 510.403 ms | 310.947 ms | 2.091 s | 1.111 s | 628.272 ms | 390.847 ms | 13.707 ms | — |
| to_physical scalar | Float32 64^3 | 384.471 μs | 247.724 μs | 167.950 μs | 155.804 μs | 313.063 μs | 176.522 μs | 101.081 μs | 70.561 μs | 63.122 μs | 19.910 μs |
| to_physical scalar | Float64 128^3 | 7.964 ms | 5.763 ms | 4.826 ms | 4.459 ms | 10.220 ms | 5.748 ms | 3.240 ms | 1.832 ms | 287.085 μs | 430.765 μs |
| to_physical scalar | Float64 256^3 | 127.275 ms | 77.838 ms | 58.295 ms | 50.526 ms | 96.212 ms | 73.588 ms | 43.827 ms | 46.465 ms | 3.184 ms | 3.769 ms |
| to_physical scalar | Float64 512^3 | 1.452 s | 961.990 ms | 712.318 ms | 616.776 ms | 929.667 ms | 600.455 ms | 448.057 ms | 398.602 ms | — | — |
| to_physical scalar | Float64 64^3 | 674.464 μs | 406.860 μs | 287.362 μs | 270.478 μs | 541.035 μs | 285.503 μs | 167.101 μs | 119.981 μs | 94.651 μs | 51.691 μs |
| to_physical vector measure | Float32 128^3 | 11.438 ms | 8.690 ms | 7.341 ms | 5.698 ms | 9.154 ms | 5.602 ms | 3.467 ms | 2.856 ms | — | — |
| to_physical vector measure | Float32 256^3 | 201.767 ms | 126.468 ms | 88.118 ms | 111.194 ms | 137.574 ms | 102.731 ms | 77.814 ms | 65.963 ms | — | — |
| to_physical vector measure | Float32 512^3 | 1.855 s | 1.248 s | 990.574 ms | 930.481 ms | 1.413 s | 879.623 ms | 667.473 ms | 606.716 ms | — | — |
| to_physical vector measure | Float32 64^3 | 1.138 ms | 718.460 μs | 554.849 μs | 540.123 μs | 838.729 μs | 495.995 μs | 287.572 μs | 222.152 μs | — | — |
| to_physical vector measure | Float64 128^3 | 36.948 ms | 31.648 ms | 26.802 ms | 19.002 ms | 27.389 ms | 18.895 ms | 14.290 ms | 12.655 ms | — | — |
| to_physical vector measure | Float64 256^3 | 354.957 ms | 261.067 ms | 226.953 ms | 217.675 ms | 306.744 ms | 207.171 ms | 154.652 ms | 139.071 ms | — | — |
| to_physical vector measure | Float64 512^3 | 3.305 s | 2.288 s | 1.954 s | 1.822 s | 2.500 s | 1.667 s | 1.291 s | 1.165 s | — | — |
| to_physical vector measure | Float64 64^3 | 1.977 ms | 1.560 ms | 1.213 ms | 1.019 ms | 1.120 ms | 658.326 μs | 408.014 μs | 330.304 μs | — | — |
| to_physical vector | Float32 128^3 | 11.328 ms | 8.317 ms | 7.390 ms | 6.398 ms | 9.295 ms | 5.558 ms | 3.494 ms | 2.925 ms | 328.878 μs | 230.012 μs |
| to_physical vector | Float32 256^3 | 202.499 ms | 126.490 ms | 88.286 ms | 111.113 ms | 138.275 ms | 105.406 ms | 75.964 ms | 64.894 ms | 4.782 ms | 3.227 ms |
| to_physical vector | Float32 512^3 | 1.859 s | 1.246 s | 990.652 ms | 920.670 ms | 1.386 s | 876.509 ms | 665.338 ms | 605.880 ms | 55.475 ms | — |
| to_physical vector | Float32 64^3 | 1.137 ms | 711.582 μs | 517.997 μs | 518.713 μs | 845.299 μs | 480.115 μs | 288.233 μs | 224.932 μs | 102.124 μs | 45.160 μs |
| to_physical vector | Float64 128^3 | 36.878 ms | 30.607 ms | 27.018 ms | 18.629 ms | 27.376 ms | 18.902 ms | 14.200 ms | 13.114 ms | 978.819 μs | 1.352 ms |
| to_physical vector | Float64 256^3 | 355.242 ms | 260.258 ms | 225.147 ms | 216.074 ms | 298.434 ms | 204.938 ms | 155.768 ms | 139.525 ms | 13.143 ms | 11.385 ms |
| to_physical vector | Float64 512^3 | 3.303 s | 2.286 s | 1.956 s | 1.818 s | 2.488 s | 1.673 s | 1.288 s | 1.163 s | — | — |
| to_physical vector | Float64 64^3 | 1.942 ms | 1.235 ms | 1.131 ms | 1.047 ms | 1.114 ms | 685.977 μs | 399.914 μs | 335.193 μs | 201.711 μs | 145.492 μs |
| to_physical! scalar scratch | Float32 128^3 | 4.319 ms | 2.775 ms | 1.710 ms | 1.295 ms | 4.497 ms | 2.482 ms | 1.266 ms | 778.209 μs | 98.005 μs | 65.141 μs |
| to_physical! scalar scratch | Float32 256^3 | 87.514 ms | 50.357 ms | 34.032 ms | 26.671 ms | 166.684 ms | 87.438 ms | 46.212 ms | 25.776 ms | 800.392 μs | 1.029 ms |
| to_physical! scalar scratch | Float32 512^3 | 1.212 s | 666.404 ms | 399.497 ms | 287.211 ms | 1.967 s | 1.025 s | 555.355 ms | 325.957 ms | 10.410 ms | — |
| to_physical! scalar scratch | Float32 64^3 | 387.269 μs | 237.149 μs | 160.957 μs | 135.737 μs | 317.243 μs | 171.262 μs | 100.741 μs | 70.591 μs | 44.697 μs | 17.731 μs |
| to_physical! scalar scratch | Float64 128^3 | 7.569 ms | 4.995 ms | 3.969 ms | 3.525 ms | 9.717 ms | 5.018 ms | 2.721 ms | 1.579 ms | 261.508 μs | 427.915 μs |
| to_physical! scalar scratch | Float64 256^3 | 110.001 ms | 69.803 ms | 55.753 ms | 50.432 ms | 81.387 ms | 50.470 ms | 35.438 ms | 29.930 ms | 2.490 ms | 3.769 ms |
| to_physical! scalar scratch | Float64 512^3 | 1.115 s | 683.453 ms | 505.187 ms | 441.897 ms | 702.588 ms | 434.304 ms | 310.934 ms | 271.286 ms | — | — |
| to_physical! scalar scratch | Float64 64^3 | 658.970 μs | 393.844 μs | 276.115 μs | 237.625 μs | 528.076 μs | 288.003 μs | 167.142 μs | 118.271 μs | 71.194 μs | 49.620 μs |
| to_physical! scalar | Float32 128^3 | 3.964 ms | 2.167 ms | 1.220 ms | 746.371 μs | 4.370 ms | 2.252 ms | 1.132 ms | 620.057 μs | 86.754 μs | 58.870 μs |
| to_physical! scalar | Float32 256^3 | 83.317 ms | 46.246 ms | 29.619 ms | 22.648 ms | 164.478 ms | 83.934 ms | 42.697 ms | 22.781 ms | 625.905 μs | 850.858 μs |
| to_physical! scalar | Float32 512^3 | 1.181 s | 636.763 ms | 371.380 ms | 261.204 ms | 1.950 s | 1.005 s | 529.932 ms | 299.536 ms | 8.988 ms | — |
| to_physical! scalar | Float32 64^3 | 355.770 μs | 204.846 μs | 122.039 μs | 89.025 μs | 298.413 μs | 155.592 μs | 84.671 μs | 54.211 μs | 40.729 μs | 16.041 μs |
| to_physical! scalar | Float64 128^3 | 6.178 ms | 3.689 ms | 2.571 ms | 1.980 ms | 9.736 ms | 4.800 ms | 2.475 ms | 1.318 ms | 241.243 μs | 398.034 μs |
| to_physical! scalar | Float64 256^3 | 102.156 ms | 62.437 ms | 47.968 ms | 43.002 ms | 72.113 ms | 41.029 ms | 25.977 ms | 19.805 ms | 2.157 ms | 3.414 ms |
| to_physical! scalar | Float64 512^3 | 1.058 s | 623.895 ms | 444.914 ms | 386.486 ms | 654.203 ms | 380.884 ms | 257.571 ms | 217.113 ms | — | — |
| to_physical! scalar | Float64 64^3 | 580.189 μs | 327.868 μs | 201.891 μs | 147.426 μs | 496.455 μs | 257.522 μs | 139.042 μs | 86.831 μs | 68.024 μs | 47.601 μs |
| to_physical! vector scratch | Float32 128^3 | 11.281 ms | 7.913 ms | 6.645 ms | 6.090 ms | 8.169 ms | 4.452 ms | 2.564 ms | 1.622 ms | 277.999 μs | 229.302 μs |
| to_physical! vector scratch | Float32 256^3 | 121.884 ms | 82.851 ms | 71.943 ms | 69.537 ms | 109.554 ms | 63.699 ms | 45.443 ms | 38.446 ms | 2.333 ms | 3.079 ms |
| to_physical! vector scratch | Float32 512^3 | 1.370 s | 872.062 ms | 700.371 ms | 648.995 ms | 950.944 ms | 560.095 ms | 428.103 ms | 388.272 ms | 28.880 ms | — |
| to_physical! vector scratch | Float32 64^3 | 1.134 ms | 685.101 μs | 462.505 μs | 389.456 μs | 844.139 μs | 471.465 μs | 286.313 μs | 224.302 μs | 80.688 μs | 42.261 μs |
| to_physical! vector scratch | Float64 128^3 | 18.786 ms | 16.201 ms | 16.212 ms | 14.417 ms | 14.385 ms | 8.749 ms | 5.818 ms | 4.548 ms | 817.459 μs | 1.353 ms |
| to_physical! vector scratch | Float64 256^3 | 242.345 ms | 170.045 ms | 154.983 ms | 149.289 ms | 206.563 ms | 132.204 ms | 98.447 ms | 87.833 ms | 7.524 ms | 11.287 ms |
| to_physical! vector scratch | Float64 512^3 | 2.219 s | 1.516 s | 1.320 s | 1.238 s | 1.712 s | 1.102 s | 861.969 ms | 770.124 ms | — | — |
| to_physical! vector scratch | Float64 64^3 | 1.663 ms | 1.008 ms | 736.922 μs | 645.643 μs | 1.088 ms | 636.316 μs | 379.794 μs | 320.603 μs | 189.753 μs | 142.071 μs |
| to_physical! vector | Float32 128^3 | 9.762 ms | 6.329 ms | 5.007 ms | 3.922 ms | 7.741 ms | 4.056 ms | 2.146 ms | 1.204 ms | 247.858 μs | 187.692 μs |
| to_physical! vector | Float32 256^3 | 110.444 ms | 71.466 ms | 60.793 ms | 58.428 ms | 102.650 ms | 51.708 ms | 34.841 ms | 27.418 ms | 1.824 ms | 2.551 ms |
| to_physical! vector | Float32 512^3 | 1.284 s | 780.400 ms | 612.590 ms | 559.012 ms | 869.878 ms | 485.420 ms | 352.148 ms | 313.204 ms | 24.807 ms | — |
| to_physical! vector | Float32 64^3 | 1.031 ms | 573.114 μs | 344.172 μs | 257.261 μs | 804.218 μs | 424.804 μs | 244.942 μs | 177.722 μs | 82.162 μs | 40.310 μs |
| to_physical! vector | Float64 128^3 | 16.039 ms | 13.039 ms | 13.184 ms | 11.525 ms | 12.715 ms | 7.144 ms | 4.127 ms | 2.547 ms | 728.504 μs | 1.217 ms |
| to_physical! vector | Float64 256^3 | 219.920 ms | 147.665 ms | 131.664 ms | 127.501 ms | 186.633 ms | 110.856 ms | 76.230 ms | 68.368 ms | 6.436 ms | 10.229 ms |
| to_physical! vector | Float64 512^3 | 2.049 s | 1.348 s | 1.150 s | 1.067 s | 1.560 s | 955.105 ms | 721.959 ms | 620.863 ms | — | — |
| to_physical! vector | Float64 64^3 | 1.427 ms | 759.497 μs | 496.185 μs | 393.014 μs | 1.006 ms | 560.975 μs | 304.343 μs | 218.172 μs | 169.631 μs | 137.522 μs |
| to_spectral scalar measure | Float32 128^3 | 3.333 ms | 2.233 ms | 1.852 ms | 1.178 ms | 2.685 ms | 1.437 ms | 800.378 μs | 462.585 μs | — | — |
| to_spectral scalar measure | Float32 256^3 | 35.062 ms | 23.865 ms | 19.458 ms | 18.319 ms | 35.394 ms | 19.824 ms | 13.714 ms | 10.635 ms | — | — |
| to_spectral scalar measure | Float32 512^3 | 475.660 ms | 373.303 ms | 239.272 ms | 208.051 ms | 451.337 ms | 268.337 ms | 192.895 ms | 166.208 ms | — | — |
| to_spectral scalar measure | Float32 64^3 | 358.002 μs | 211.899 μs | 143.962 μs | 110.840 μs | 271.472 μs | 145.871 μs | 85.341 μs | 61.531 μs | — | — |
| to_spectral scalar measure | Float64 128^3 | 5.370 ms | 4.241 ms | 3.870 ms | 3.193 ms | 3.892 ms | 2.367 ms | 1.339 ms | 1.195 ms | — | — |
| to_spectral scalar measure | Float64 256^3 | 92.991 ms | 56.793 ms | 44.107 ms | 38.889 ms | 76.259 ms | 59.437 ms | 37.132 ms | 38.240 ms | — | — |
| to_spectral scalar measure | Float64 512^3 | 1.050 s | 702.841 ms | 566.930 ms | 517.095 ms | 748.122 ms | 491.860 ms | 365.948 ms | 332.342 ms | — | — |
| to_spectral scalar measure | Float64 64^3 | 497.941 μs | 290.946 μs | 211.217 μs | 186.327 μs | 347.013 μs | 192.922 μs | 108.801 μs | 81.090 μs | — | — |
| to_spectral scalar | Float32 128^3 | 4.334 ms | 2.716 ms | 1.978 ms | 1.502 ms | 4.636 ms | 2.402 ms | 1.254 ms | 722.728 μs | 68.598 μs | 40.670 μs |
| to_spectral scalar | Float32 256^3 | 86.001 ms | 48.526 ms | 29.120 ms | 22.112 ms | 169.465 ms | 87.023 ms | 46.184 ms | 26.272 ms | 688.794 μs | 681.007 μs |
| to_spectral scalar | Float32 512^3 | 1.284 s | 771.005 ms | 480.914 ms | 345.825 ms | 2.079 s | 1.093 s | 596.845 ms | 356.814 ms | 9.542 ms | — |
| to_spectral scalar | Float32 64^3 | 365.817 μs | 214.691 μs | 153.119 μs | 110.601 μs | 303.693 μs | 163.862 μs | 91.541 μs | 59.470 μs | 51.582 μs | 14.490 μs |
| to_spectral scalar | Float64 128^3 | 7.094 ms | 5.059 ms | 4.138 ms | 3.380 ms | 10.074 ms | 5.423 ms | 2.980 ms | 1.961 ms | 236.989 μs | 381.024 μs |
| to_spectral scalar | Float64 256^3 | 141.209 ms | 80.312 ms | 53.117 ms | 47.281 ms | 189.509 ms | 116.399 ms | 62.541 ms | 52.773 ms | 2.581 ms | 3.080 ms |
| to_spectral scalar | Float64 512^3 | 1.650 s | 996.590 ms | 657.866 ms | 550.924 ms | 1.705 s | 966.768 ms | 578.855 ms | 428.255 ms | — | — |
| to_spectral scalar | Float64 64^3 | 674.857 μs | 350.652 μs | 214.929 μs | 212.164 μs | 511.795 μs | 271.733 μs | 152.282 μs | 95.551 μs | 77.780 μs | 45.430 μs |
| to_spectral vector measure | Float32 128^3 | 10.146 ms | 6.952 ms | 5.689 ms | 4.714 ms | 9.426 ms | 5.215 ms | 3.087 ms | 2.342 ms | — | — |
| to_spectral vector measure | Float32 256^3 | 183.803 ms | 98.448 ms | 67.770 ms | 93.801 ms | 140.353 ms | 99.201 ms | 71.275 ms | 58.785 ms | — | — |
| to_spectral vector measure | Float32 512^3 | 1.705 s | 1.117 s | 862.006 ms | 771.945 ms | 1.338 s | 804.527 ms | 574.464 ms | 511.137 ms | — | — |
| to_spectral vector measure | Float32 64^3 | 1.091 ms | 625.562 μs | 397.960 μs | 384.518 μs | 825.738 μs | 444.974 μs | 254.563 μs | 186.812 μs | — | — |
| to_spectral vector measure | Float64 128^3 | 34.025 ms | 25.277 ms | 21.979 ms | 16.017 ms | 27.344 ms | 18.613 ms | 14.080 ms | 12.576 ms | — | — |
| to_spectral vector measure | Float64 256^3 | 340.506 ms | 242.428 ms | 197.282 ms | 178.283 ms | 275.949 ms | 181.730 ms | 136.881 ms | 116.291 ms | — | — |
| to_spectral vector measure | Float64 512^3 | 3.162 s | 2.105 s | 1.695 s | 1.561 s | 2.212 s | 1.452 s | 1.106 s | 960.812 ms | — | — |
| to_spectral vector measure | Float64 64^3 | 1.620 ms | 1.043 ms | 817.617 μs | 739.979 μs | 1.045 ms | 608.536 μs | 331.503 μs | 257.183 μs | — | — |
| to_spectral vector | Float32 128^3 | 10.176 ms | 6.771 ms | 5.703 ms | 4.933 ms | 9.391 ms | 5.131 ms | 3.021 ms | 2.830 ms | 214.393 μs | 157.442 μs |
| to_spectral vector | Float32 256^3 | 182.844 ms | 98.822 ms | 66.499 ms | 95.495 ms | 142.580 ms | 98.693 ms | 72.328 ms | 59.016 ms | 2.852 ms | 2.108 ms |
| to_spectral vector | Float32 512^3 | 1.703 s | 1.113 s | 858.402 ms | 770.860 ms | 1.334 s | 806.638 ms | 578.991 ms | 520.876 ms | 44.808 ms | — |
| to_spectral vector | Float32 64^3 | 1.089 ms | 629.159 μs | 401.498 μs | 449.608 μs | 830.748 μs | 437.094 μs | 255.833 μs | 191.842 μs | 61.467 μs | 30.041 μs |
| to_spectral vector | Float64 128^3 | 34.651 ms | 25.479 ms | 21.547 ms | 14.343 ms | 28.464 ms | 18.736 ms | 13.610 ms | 12.296 ms | 757.621 μs | 1.159 ms |
| to_spectral vector | Float64 256^3 | 339.611 ms | 242.025 ms | 199.458 ms | 179.282 ms | 280.845 ms | 183.201 ms | 133.491 ms | 115.841 ms | 11.470 ms | 9.237 ms |
| to_spectral vector | Float64 512^3 | 3.155 s | 2.115 s | 1.704 s | 1.566 s | 2.185 s | 1.447 s | 1.104 s | 967.678 ms | — | — |
| to_spectral vector | Float64 64^3 | 1.598 ms | 1.058 ms | 1.057 ms | 760.270 μs | 1.046 ms | 585.756 μs | 331.263 μs | 249.523 μs | 180.596 μs | 125.131 μs |

## algebra

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| add! scalar | Float32 128^3 | 394.768 μs | 241.694 μs | 172.350 μs | 76.417 μs | 162.312 μs | 84.191 μs | 44.031 μs | 35.670 μs | 59.397 μs | 34.360 μs |
| add! scalar | Float32 256^3 | 8.151 ms | 7.354 ms | 5.632 ms | 5.172 ms | 3.481 ms | 3.003 ms | 2.759 ms | 2.805 ms | 345.049 μs | 273.212 μs |
| add! scalar | Float32 512^3 | 68.219 ms | 62.765 ms | 48.666 ms | 45.603 ms | 40.662 ms | 36.891 ms | 36.798 ms | 37.219 ms | 2.562 ms | — |
| add! scalar | Float32 64^3 | 42.302 μs | 20.924 μs | 9.892 μs | 10.125 μs | 20.470 μs | 12.250 μs | 7.080 μs | 6.897 μs | 31.189 μs | 10.190 μs |
| add! scalar | Float64 128^3 | 1.461 ms | 1.282 ms | 945.520 μs | 803.412 μs | 324.114 μs | 164.221 μs | 86.110 μs | 72.861 μs | 60.389 μs | 38.570 μs |
| add! scalar | Float64 256^3 | 16.662 ms | 15.274 ms | 11.809 ms | 11.014 ms | 10.258 ms | 8.539 ms | 8.442 ms | 8.567 ms | 534.412 μs | 511.885 μs |
| add! scalar | Float64 512^3 | 135.906 ms | 123.786 ms | 97.631 ms | 91.228 ms | 83.871 ms | 72.244 ms | 73.742 ms | 74.035 ms | — | — |
| add! scalar | Float64 64^3 | 83.709 μs | 49.523 μs | 20.896 μs | 12.218 μs | 40.200 μs | 22.700 μs | 12.170 μs | 9.420 μs | 31.898 μs | 10.160 μs |
| combine! vec | Float32 128^3 | 2.594 ms | 2.393 ms | 1.802 ms | 1.589 ms | 650.586 μs | 315.543 μs | 167.392 μs | 115.561 μs | 189.099 μs | 131.502 μs |
| combine! vec | Float32 256^3 | 25.266 ms | 23.207 ms | 18.280 ms | 16.899 ms | 13.661 ms | 13.987 ms | 13.429 ms | 13.769 ms | 1.334 ms | 966.100 μs |
| combine! vec | Float32 512^3 | 199.716 ms | 183.841 ms | 149.155 ms | 137.937 ms | 114.404 ms | 110.351 ms | 110.841 ms | 111.140 ms | 11.393 ms | — |
| combine! vec | Float32 64^3 | 127.298 μs | 69.076 μs | 40.129 μs | 23.645 μs | 62.761 μs | 38.750 μs | 20.000 μs | 14.851 μs | 46.454 μs | 22.130 μs |
| combine! vec | Float64 128^3 | 5.883 ms | 5.416 ms | 4.113 ms | 3.726 ms | 2.205 ms | 1.778 ms | 1.581 ms | 1.490 ms | 236.122 μs | 193.102 μs |
| combine! vec | Float64 256^3 | 47.105 ms | 46.765 ms | 36.661 ms | 34.203 ms | 28.681 ms | 26.750 ms | 27.113 ms | 27.444 ms | 1.691 ms | 1.533 ms |
| combine! vec | Float64 512^3 | 408.479 ms | 372.299 ms | 294.881 ms | 274.458 ms | 233.665 ms | 217.929 ms | 220.731 ms | 221.675 ms | — | — |
| combine! vec | Float64 64^3 | 264.849 μs | 150.197 μs | 76.214 μs | 45.340 μs | 123.461 μs | 64.171 μs | 34.581 μs | 28.270 μs | 48.839 μs | 22.201 μs |
| cross! | Float32 128^3 | 2.720 ms | 2.487 ms | 2.109 ms | 1.970 ms | 2.017 ms | 993.451 μs | 499.146 μs | 249.073 μs | 52.034 μs | 85.151 μs |
| cross! | Float32 256^3 | 27.416 ms | 25.121 ms | 23.436 ms | 22.340 ms | 23.285 ms | 14.622 ms | 12.569 ms | 12.632 ms | 863.742 μs | 771.408 μs |
| cross! | Float32 512^3 | 214.072 ms | 198.194 ms | 193.490 ms | 185.004 ms | 174.385 ms | 121.423 ms | 110.867 ms | 110.566 ms | 7.279 ms | — |
| cross! | Float32 64^3 | 246.702 μs | 128.695 μs | 71.534 μs | 38.146 μs | 230.892 μs | 115.981 μs | 58.990 μs | 32.890 μs | 36.223 μs | 9.070 μs |
| cross! | Float64 128^3 | 6.274 ms | 5.649 ms | 5.109 ms | 4.874 ms | 3.783 ms | 2.303 ms | 1.586 ms | 1.477 ms | 234.140 μs | 196.411 μs |
| cross! | Float64 256^3 | 48.709 ms | 50.835 ms | 47.889 ms | 45.256 ms | 42.187 ms | 30.200 ms | 27.441 ms | 27.531 ms | 1.628 ms | 1.539 ms |
| cross! | Float64 512^3 | 406.884 ms | 403.297 ms | 385.082 ms | 368.655 ms | 334.645 ms | 231.727 ms | 222.479 ms | 224.392 ms | — | — |
| cross! | Float64 64^3 | 360.048 μs | 188.619 μs | 95.905 μs | 54.238 μs | 224.912 μs | 115.441 μs | 58.710 μs | 36.810 μs | 41.287 μs | 14.790 μs |
| det! tensor | Float32 128^3 | 3.245 ms | 2.475 ms | 2.005 ms | 1.795 ms | 2.168 ms | 1.086 ms | 546.435 μs | 287.303 μs | 74.505 μs | 101.961 μs |
| det! tensor | Float32 256^3 | 34.829 ms | 26.684 ms | 22.230 ms | 19.169 ms | 32.872 ms | 15.652 ms | 12.173 ms | 11.999 ms | 924.348 μs | 826.488 μs |
| det! tensor | Float32 512^3 | 269.696 ms | 205.446 ms | 180.708 ms | 164.431 ms | 230.659 ms | 124.103 ms | 104.614 ms | 103.552 ms | 7.751 ms | — |
| det! tensor | Float32 64^3 | 305.379 μs | 155.974 μs | 82.421 μs | 46.381 μs | 250.702 μs | 128.311 μs | 66.000 μs | 36.211 μs | 41.720 μs | 10.880 μs |
| det! tensor | Float64 128^3 | 6.788 ms | 5.509 ms | 4.741 ms | 4.140 ms | 4.019 ms | 2.384 ms | 1.676 ms | 1.618 ms | 256.242 μs | 197.562 μs |
| det! tensor | Float64 256^3 | 50.686 ms | 48.346 ms | 42.893 ms | 39.713 ms | 41.921 ms | 29.273 ms | 25.581 ms | 25.577 ms | 1.773 ms | 1.697 ms |
| det! tensor | Float64 512^3 | 374.619 ms | 399.163 ms | 340.632 ms | 316.102 ms | 426.193 ms | 273.463 ms | 213.736 ms | 211.173 ms | — | — |
| det! tensor | Float64 64^3 | 351.752 μs | 187.150 μs | 110.118 μs | 63.817 μs | 253.982 μs | 130.311 μs | 68.020 μs | 42.710 μs | 43.371 μs | 16.210 μs |
| dot! vec.vec | Float32 128^3 | 2.740 ms | 1.671 ms | 1.262 ms | 1.102 ms | 2.448 ms | 1.246 ms | 629.007 μs | 319.764 μs | 85.003 μs | 71.461 μs |
| dot! vec.vec | Float32 256^3 | 24.149 ms | 17.264 ms | 15.421 ms | 13.925 ms | 25.653 ms | 12.291 ms | 8.242 ms | 8.076 ms | 684.643 μs | 610.146 μs |
| dot! vec.vec | Float32 512^3 | 202.410 ms | 136.894 ms | 126.265 ms | 114.990 ms | 167.955 ms | 98.806 ms | 75.324 ms | 75.779 ms | 5.421 ms | — |
| dot! vec.vec | Float32 64^3 | 329.659 μs | 199.082 μs | 104.985 μs | 59.178 μs | 310.603 μs | 159.572 μs | 81.561 μs | 44.430 μs | 34.981 μs | 13.470 μs |
| dot! vec.vec | Float64 128^3 | 4.235 ms | 3.768 ms | 3.151 ms | 2.803 ms | 3.460 ms | 1.728 ms | 889.959 μs | 583.297 μs | 177.146 μs | 134.141 μs |
| dot! vec.vec | Float64 256^3 | 37.273 ms | 35.125 ms | 29.203 ms | 27.052 ms | 32.800 ms | 19.903 ms | 18.548 ms | 18.083 ms | 1.224 ms | 1.157 ms |
| dot! vec.vec | Float64 512^3 | 288.057 ms | 275.061 ms | 234.425 ms | 216.575 ms | 257.743 ms | 158.990 ms | 149.721 ms | 150.451 ms | — | — |
| dot! vec.vec | Float64 64^3 | 337.903 μs | 213.034 μs | 106.815 μs | 63.950 μs | 318.913 μs | 160.472 μs | 81.921 μs | 44.891 μs | 34.808 μs | 13.840 μs |
| map!(+) vec | Float32 128^3 | 2.741 ms | 2.463 ms | 2.127 ms | 1.965 ms | 1.765 ms | 844.519 μs | 419.374 μs | 206.412 μs | 52.143 μs | 79.221 μs |
| map!(+) vec | Float32 256^3 | 27.236 ms | 25.048 ms | 23.395 ms | 22.340 ms | 21.947 ms | 14.284 ms | 12.654 ms | 12.714 ms | 865.368 μs | 772.308 μs |
| map!(+) vec | Float32 512^3 | 212.368 ms | 198.161 ms | 192.453 ms | 184.242 ms | 159.353 ms | 118.575 ms | 110.697 ms | 110.538 ms | 7.307 ms | — |
| map!(+) vec | Float32 64^3 | 241.663 μs | 128.393 μs | 71.643 μs | 37.873 μs | 199.441 μs | 95.671 μs | 48.730 μs | 27.090 μs | 35.407 μs | 9.021 μs |
| map!(+) vec | Float64 128^3 | 6.210 ms | 5.685 ms | 5.069 ms | 4.879 ms | 3.654 ms | 2.268 ms | 1.571 ms | 1.490 ms | 229.661 μs | 196.502 μs |
| map!(+) vec | Float64 256^3 | 48.534 ms | 50.678 ms | 47.661 ms | 45.511 ms | 40.105 ms | 29.720 ms | 27.332 ms | 27.585 ms | 1.605 ms | 1.539 ms |
| map!(+) vec | Float64 512^3 | 404.152 ms | 402.276 ms | 382.914 ms | 368.224 ms | 318.480 ms | 226.374 ms | 221.774 ms | 222.455 ms | — | — |
| map!(+) vec | Float64 64^3 | 349.556 μs | 188.333 μs | 98.811 μs | 54.632 μs | 175.262 μs | 94.001 μs | 48.500 μs | 33.110 μs | 39.557 μs | 12.540 μs |
| map!(det) tensor | Float32 128^3 | 3.227 ms | 2.473 ms | 1.987 ms | 1.781 ms | 2.157 ms | 1.094 ms | 542.775 μs | 285.283 μs | 74.914 μs | 101.531 μs |
| map!(det) tensor | Float32 256^3 | 34.801 ms | 26.725 ms | 22.041 ms | 19.134 ms | 33.013 ms | 15.634 ms | 12.180 ms | 12.028 ms | 923.472 μs | 835.018 μs |
| map!(det) tensor | Float32 512^3 | 269.600 ms | 205.517 ms | 179.268 ms | 163.133 ms | 232.130 ms | 123.654 ms | 104.306 ms | 103.343 ms | 7.815 ms | — |
| map!(det) tensor | Float32 64^3 | 300.234 μs | 152.070 μs | 81.456 μs | 48.385 μs | 249.823 μs | 130.692 μs | 65.381 μs | 36.010 μs | 41.331 μs | 10.780 μs |
| map!(det) tensor | Float64 128^3 | 6.784 ms | 5.586 ms | 4.759 ms | 4.137 ms | 4.069 ms | 2.390 ms | 1.650 ms | 1.615 ms | 254.510 μs | 197.702 μs |
| map!(det) tensor | Float64 256^3 | 50.709 ms | 48.427 ms | 42.876 ms | 39.719 ms | 42.003 ms | 29.110 ms | 25.527 ms | 25.555 ms | 1.755 ms | 1.703 ms |
| map!(det) tensor | Float64 512^3 | 373.186 ms | 399.393 ms | 341.073 ms | 317.422 ms | 399.760 ms | 268.799 ms | 211.647 ms | 210.092 ms | — | — |
| map!(det) tensor | Float64 64^3 | 348.776 μs | 186.642 μs | 106.469 μs | 59.339 μs | 251.312 μs | 129.781 μs | 66.491 μs | 43.280 μs | 42.507 μs | 16.221 μs |
| mul! tensor.vec | Float32 128^3 | 4.689 ms | 4.256 ms | 3.781 ms | 3.553 ms | 3.579 ms | 1.878 ms | 999.160 μs | 800.418 μs | 214.159 μs | 151.131 μs |
| mul! tensor.vec | Float32 256^3 | 53.208 ms | 41.247 ms | 37.525 ms | 34.583 ms | 42.342 ms | 24.902 ms | 23.385 ms | 21.924 ms | 1.446 ms | 1.259 ms |
| mul! tensor.vec | Float32 512^3 | 411.912 ms | 322.148 ms | 305.492 ms | 286.379 ms | 335.639 ms | 216.482 ms | 177.813 ms | 174.639 ms | 11.876 ms | — |
| mul! tensor.vec | Float32 64^3 | 464.734 μs | 229.217 μs | 121.734 μs | 73.626 μs | 369.614 μs | 212.352 μs | 107.151 μs | 59.950 μs | 47.308 μs | 12.820 μs |
| mul! tensor.vec | Float64 128^3 | 10.976 ms | 9.235 ms | 9.276 ms | 8.019 ms | 7.037 ms | 5.284 ms | 4.363 ms | 4.291 ms | 392.904 μs | 319.843 μs |
| mul! tensor.vec | Float64 256^3 | 78.463 ms | 78.742 ms | 74.593 ms | 70.686 ms | 59.582 ms | 49.493 ms | 43.862 ms | 43.564 ms | 2.808 ms | 2.508 ms |
| mul! tensor.vec | Float64 512^3 | 620.002 ms | 639.205 ms | 595.716 ms | 566.782 ms | 584.406 ms | 407.714 ms | 352.521 ms | 351.009 ms | — | — |
| mul! tensor.vec | Float64 64^3 | 691.553 μs | 450.545 μs | 352.251 μs | 215.068 μs | 379.004 μs | 217.732 μs | 111.121 μs | 59.221 μs | 46.245 μs | 19.580 μs |
| norm! vec | Float32 128^3 | 727.052 μs | 595.821 μs | 472.882 μs | 349.322 μs | 216.772 μs | 119.751 μs | 63.990 μs | 52.270 μs | 66.987 μs | 39.551 μs |
| norm! vec | Float32 256^3 | 10.265 ms | 9.491 ms | 7.857 ms | 7.329 ms | 5.328 ms | 4.288 ms | 4.076 ms | 4.226 ms | 432.178 μs | 335.074 μs |
| norm! vec | Float32 512^3 | 79.706 ms | 79.082 ms | 66.803 ms | 62.751 ms | 49.340 ms | 44.364 ms | 45.828 ms | 46.797 ms | 3.454 ms | — |
| norm! vec | Float32 64^3 | 53.459 μs | 37.584 μs | 18.899 μs | 16.396 μs | 31.280 μs | 21.060 μs | 13.140 μs | 11.400 μs | 32.593 μs | 11.040 μs |
| norm! vec | Float64 128^3 | 2.096 ms | 1.913 ms | 1.473 ms | 1.330 ms | 489.994 μs | 247.853 μs | 128.041 μs | 105.531 μs | 134.313 μs | 79.460 μs |
| norm! vec | Float64 256^3 | 21.312 ms | 19.852 ms | 16.262 ms | 15.109 ms | 11.883 ms | 10.281 ms | 10.280 ms | 10.558 ms | 916.596 μs | 671.927 μs |
| norm! vec | Float64 512^3 | 172.936 ms | 156.727 ms | 132.872 ms | 125.190 ms | 102.305 ms | 90.356 ms | 92.070 ms | 92.572 ms | — | — |
| norm! vec | Float64 64^3 | 157.680 μs | 89.235 μs | 50.074 μs | 31.397 μs | 56.461 μs | 34.991 μs | 21.270 μs | 16.600 μs | 41.177 μs | 16.621 μs |
| tr! tensor | Float32 128^3 | 734.483 μs | 559.301 μs | 430.532 μs | 335.228 μs | 214.512 μs | 116.262 μs | 60.831 μs | 51.071 μs | 65.701 μs | 39.271 μs |
| tr! tensor | Float32 256^3 | 10.244 ms | 9.450 ms | 7.650 ms | 7.084 ms | 5.142 ms | 4.372 ms | 4.280 ms | 4.369 ms | 437.144 μs | 332.223 μs |
| tr! tensor | Float32 512^3 | 79.574 ms | 77.635 ms | 65.168 ms | 60.970 ms | 52.028 ms | 45.475 ms | 46.366 ms | 47.048 ms | 3.459 ms | — |
| tr! tensor | Float32 64^3 | 52.453 μs | 33.802 μs | 15.555 μs | 14.256 μs | 30.730 μs | 18.610 μs | 10.840 μs | 9.640 μs | 32.527 μs | 10.900 μs |
| tr! tensor | Float64 128^3 | 2.103 ms | 1.853 ms | 1.430 ms | 1.286 ms | 472.345 μs | 237.172 μs | 125.412 μs | 100.761 μs | 71.183 μs | 70.411 μs |
| tr! tensor | Float64 256^3 | 19.755 ms | 19.194 ms | 15.903 ms | 14.845 ms | 11.427 ms | 10.606 ms | 10.556 ms | 10.755 ms | 719.948 μs | 672.027 μs |
| tr! tensor | Float64 512^3 | 156.280 ms | 155.233 ms | 131.168 ms | 121.900 ms | 104.408 ms | 93.094 ms | 92.962 ms | 94.010 ms | — | — |
| tr! tensor | Float64 64^3 | 104.864 μs | 63.597 μs | 33.899 μs | 23.482 μs | 53.280 μs | 31.560 μs | 19.040 μs | 14.320 μs | 33.635 μs | 11.030 μs |

## operators

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| curl! vec->vec | Float32 128^3 | 5.576 ms | 2.823 ms | 1.538 ms | 1.196 ms | 3.225 ms | 1.662 ms | 830.059 μs | 423.315 μs | 54.837 μs | 37.591 μs |
| curl! vec->vec | Float32 256^3 | 44.148 ms | 22.919 ms | 17.301 ms | 16.534 ms | 25.582 ms | 13.222 ms | 8.829 ms | 8.561 ms | 588.036 μs | 541.556 μs |
| curl! vec->vec | Float32 512^3 | 353.315 ms | 179.508 ms | 143.990 ms | 137.294 ms | 221.916 ms | 116.620 ms | 83.223 ms | 83.772 ms | 4.680 ms | — |
| curl! vec->vec | Float32 64^3 | 705.825 μs | 359.143 μs | 183.677 μs | 98.611 μs | 413.914 μs | 219.992 μs | 110.881 μs | 58.211 μs | 36.793 μs | 11.760 μs |
| curl! vec->vec | Float64 128^3 | 5.713 ms | 4.006 ms | 3.545 ms | 3.405 ms | 3.715 ms | 1.878 ms | 923.080 μs | 533.235 μs | 133.364 μs | 142.691 μs |
| curl! vec->vec | Float64 256^3 | 48.083 ms | 37.613 ms | 35.070 ms | 33.967 ms | 33.518 ms | 20.339 ms | 19.335 ms | 19.541 ms | 1.162 ms | 1.076 ms |
| curl! vec->vec | Float64 512^3 | 355.045 ms | 298.578 ms | 288.045 ms | 278.013 ms | 263.706 ms | 168.288 ms | 164.977 ms | 166.920 ms | — | — |
| curl! vec->vec | Float64 64^3 | 672.572 μs | 348.449 μs | 179.546 μs | 95.193 μs | 463.114 μs | 233.472 μs | 120.691 μs | 64.021 μs | 46.910 μs | 20.790 μs |
| divergence! vec->scalar | Float32 128^3 | 3.527 ms | 1.383 ms | 712.452 μs | 408.305 μs | 3.375 ms | 1.137 ms | 569.886 μs | 287.743 μs | 57.945 μs | 31.620 μs |
| divergence! vec->scalar | Float32 256^3 | 27.713 ms | 11.144 ms | 9.169 ms | 8.573 ms | 26.737 ms | 8.971 ms | 4.529 ms | 4.140 ms | 392.418 μs | 342.194 μs |
| divergence! vec->scalar | Float32 512^3 | 226.517 ms | 90.485 ms | 77.760 ms | 70.354 ms | 211.421 ms | 70.710 ms | 46.335 ms | 46.775 ms | 2.965 ms | — |
| divergence! vec->scalar | Float32 64^3 | 419.119 μs | 177.124 μs | 92.531 μs | 52.493 μs | 433.305 μs | 152.721 μs | 78.161 μs | 42.550 μs | 33.857 μs | 11.370 μs |
| divergence! vec->scalar | Float64 128^3 | 3.698 ms | 1.979 ms | 1.633 ms | 1.414 ms | 3.345 ms | 1.061 ms | 545.376 μs | 277.293 μs | 87.620 μs | 76.081 μs |
| divergence! vec->scalar | Float64 256^3 | 30.673 ms | 21.194 ms | 16.964 ms | 15.544 ms | 27.449 ms | 11.125 ms | 10.314 ms | 10.316 ms | 746.127 μs | 678.946 μs |
| divergence! vec->scalar | Float64 512^3 | 242.568 ms | 165.413 ms | 137.421 ms | 126.645 ms | 211.704 ms | 96.078 ms | 93.528 ms | 93.519 ms | — | — |
| divergence! vec->scalar | Float64 64^3 | 432.321 μs | 162.474 μs | 86.499 μs | 56.835 μs | 435.395 μs | 138.741 μs | 73.801 μs | 40.960 μs | 38.025 μs | 13.941 μs |
| divergence!∘kernel vec->scalar | Float32 128^3 | 5.702 ms | 2.434 ms | 1.244 ms | 692.779 μs | 5.007 ms | 2.062 ms | 1.033 ms | 517.695 μs | 69.330 μs | 39.161 μs |
| divergence!∘kernel vec->scalar | Float32 256^3 | 44.640 ms | 18.893 ms | 10.021 ms | 8.968 ms | 39.527 ms | 16.194 ms | 8.130 ms | 4.253 ms | 421.421 μs | 343.373 μs |
| divergence!∘kernel vec->scalar | Float32 512^3 | 358.158 ms | 149.536 ms | 84.462 ms | 75.408 ms | 312.006 ms | 128.579 ms | 64.036 ms | 46.982 ms | 3.433 ms | — |
| divergence!∘kernel vec->scalar | Float32 64^3 | 726.125 μs | 319.160 μs | 163.816 μs | 90.956 μs | 634.947 μs | 271.213 μs | 139.321 μs | 74.511 μs | 36.197 μs | 13.240 μs |
| divergence!∘kernel vec->scalar | Float64 128^3 | 5.822 ms | 2.460 ms | 1.740 ms | 1.436 ms | 5.004 ms | 1.990 ms | 998.470 μs | 499.695 μs | 107.350 μs | 77.520 μs |
| divergence!∘kernel vec->scalar | Float64 256^3 | 46.563 ms | 21.865 ms | 17.488 ms | 15.830 ms | 40.014 ms | 15.819 ms | 10.315 ms | 10.273 ms | 773.989 μs | 681.156 μs |
| divergence!∘kernel vec->scalar | Float64 512^3 | 372.240 ms | 171.894 ms | 141.659 ms | 128.498 ms | 312.274 ms | 127.491 ms | 93.969 ms | 93.686 ms | — | — |
| divergence!∘kernel vec->scalar | Float64 64^3 | 695.916 μs | 304.124 μs | 159.747 μs | 89.859 μs | 635.446 μs | 255.153 μs | 132.461 μs | 70.711 μs | 42.792 μs | 18.130 μs |
| gradient! scalar->vec | Float32 128^3 | 3.186 ms | 1.663 ms | 860.037 μs | 523.230 μs | 1.967 ms | 971.410 μs | 490.155 μs | 251.663 μs | 45.290 μs | 27.840 μs |
| gradient! scalar->vec | Float32 256^3 | 25.611 ms | 14.266 ms | 13.060 ms | 12.654 ms | 15.614 ms | 7.821 ms | 5.665 ms | 5.645 ms | 454.539 μs | 379.483 μs |
| gradient! scalar->vec | Float32 512^3 | 199.885 ms | 117.273 ms | 111.807 ms | 107.941 ms | 125.223 ms | 66.503 ms | 64.258 ms | 64.439 ms | 3.440 ms | — |
| gradient! scalar->vec | Float32 64^3 | 400.236 μs | 222.293 μs | 108.992 μs | 59.583 μs | 248.313 μs | 125.591 μs | 64.671 μs | 35.260 μs | 34.679 μs | 10.390 μs |
| gradient! scalar->vec | Float64 128^3 | 3.286 ms | 2.726 ms | 2.445 ms | 2.312 ms | 2.067 ms | 978.670 μs | 495.985 μs | 258.463 μs | 96.994 μs | 99.511 μs |
| gradient! scalar->vec | Float64 256^3 | 30.343 ms | 28.512 ms | 27.158 ms | 26.222 ms | 20.238 ms | 14.734 ms | 13.986 ms | 14.126 ms | 903.390 μs | 745.877 μs |
| gradient! scalar->vec | Float64 512^3 | 234.131 ms | 231.614 ms | 222.220 ms | 216.104 ms | 163.396 ms | 129.490 ms | 127.405 ms | 128.301 ms | — | — |
| gradient! scalar->vec | Float64 64^3 | 348.222 μs | 179.004 μs | 98.332 μs | 59.368 μs | 262.722 μs | 125.652 μs | 63.240 μs | 34.641 μs | 41.213 μs | 16.270 μs |
| helmholtz! vec->vec | Float32 128^3 | 4.374 ms | 2.291 ms | 1.397 ms | 1.196 ms | 3.384 ms | 1.698 ms | 854.019 μs | 432.135 μs | 56.988 μs | 37.111 μs |
| helmholtz! vec->vec | Float32 256^3 | 34.745 ms | 18.942 ms | 17.159 ms | 16.545 ms | 26.893 ms | 13.444 ms | 8.551 ms | 8.560 ms | 585.309 μs | 542.115 μs |
| helmholtz! vec->vec | Float32 512^3 | 272.622 ms | 152.243 ms | 143.418 ms | 137.564 ms | 234.709 ms | 116.604 ms | 82.986 ms | 83.863 ms | 4.648 ms | — |
| helmholtz! vec->vec | Float32 64^3 | 550.689 μs | 284.112 μs | 145.572 μs | 79.303 μs | 447.534 μs | 230.002 μs | 115.621 μs | 60.911 μs | 37.518 μs | 12.080 μs |
| helmholtz! vec->vec | Float64 128^3 | 5.151 ms | 3.954 ms | 3.561 ms | 3.406 ms | 3.884 ms | 1.988 ms | 1.014 ms | 555.466 μs | 166.017 μs | 137.971 μs |
| helmholtz! vec->vec | Float64 256^3 | 44.785 ms | 37.406 ms | 35.231 ms | 33.842 ms | 37.826 ms | 20.305 ms | 19.409 ms | 19.583 ms | 1.199 ms | 1.073 ms |
| helmholtz! vec->vec | Float64 512^3 | 314.156 ms | 298.479 ms | 287.970 ms | 278.325 ms | 277.286 ms | 168.692 ms | 165.432 ms | 167.094 ms | — | — |
| helmholtz! vec->vec | Float64 64^3 | 594.686 μs | 300.358 μs | 154.333 μs | 86.174 μs | 508.735 μs | 260.462 μs | 134.411 μs | 71.391 μs | 53.498 μs | 26.911 μs |
| helmholtz!∘kernel vec->vec | Float32 128^3 | 7.577 ms | 3.843 ms | 1.972 ms | 1.209 ms | 6.317 ms | 3.165 ms | 1.654 ms | 809.558 μs | 65.597 μs | 40.931 μs |
| helmholtz!∘kernel vec->vec | Float32 256^3 | 60.390 ms | 30.946 ms | 17.514 ms | 16.672 ms | 50.148 ms | 25.095 ms | 12.622 ms | 8.536 ms | 583.095 μs | 542.175 μs |
| helmholtz!∘kernel vec->vec | Float32 512^3 | 474.078 ms | 241.014 ms | 146.510 ms | 137.760 ms | 404.131 ms | 201.824 ms | 101.600 ms | 83.328 ms | 4.546 ms | — |
| helmholtz!∘kernel vec->vec | Float32 64^3 | 955.217 μs | 494.739 μs | 253.212 μs | 131.800 μs | 827.318 μs | 426.344 μs | 215.282 μs | 110.931 μs | 39.954 μs | 13.640 μs |
| helmholtz!∘kernel vec->vec | Float64 128^3 | 8.237 ms | 4.179 ms | 3.584 ms | 3.393 ms | 6.788 ms | 3.479 ms | 1.796 ms | 879.579 μs | 184.993 μs | 168.381 μs |
| helmholtz!∘kernel vec->vec | Float64 256^3 | 70.956 ms | 37.634 ms | 35.250 ms | 33.845 ms | 55.004 ms | 27.966 ms | 19.336 ms | 19.363 ms | 1.207 ms | 1.228 ms |
| helmholtz!∘kernel vec->vec | Float64 512^3 | 511.003 ms | 301.233 ms | 288.076 ms | 277.913 ms | 444.705 ms | 230.994 ms | 165.845 ms | 166.390 ms | — | — |
| helmholtz!∘kernel vec->vec | Float64 64^3 | 1.012 ms | 516.659 μs | 265.114 μs | 138.736 μs | 909.569 μs | 455.485 μs | 233.172 μs | 121.401 μs | 55.466 μs | 33.020 μs |
| inverse_curl! vec->vec | Float32 128^3 | 6.531 ms | 3.382 ms | 1.742 ms | 1.192 ms | 3.503 ms | 1.747 ms | 876.009 μs | 449.434 μs | 56.557 μs | 35.331 μs |
| inverse_curl! vec->vec | Float32 256^3 | 51.502 ms | 27.069 ms | 17.321 ms | 16.616 ms | 28.150 ms | 13.994 ms | 8.563 ms | 8.568 ms | 587.430 μs | 541.605 μs |
| inverse_curl! vec->vec | Float32 512^3 | 411.603 ms | 212.734 ms | 145.589 ms | 137.813 ms | 242.037 ms | 119.563 ms | 83.059 ms | 83.839 ms | 4.649 ms | — |
| inverse_curl! vec->vec | Float32 64^3 | 833.873 μs | 434.990 μs | 222.331 μs | 116.996 μs | 444.975 μs | 225.722 μs | 114.301 μs | 60.401 μs | 35.599 μs | 12.210 μs |
| inverse_curl! vec->vec | Float64 128^3 | 6.366 ms | 3.961 ms | 3.557 ms | 3.406 ms | 3.664 ms | 1.842 ms | 912.639 μs | 528.055 μs | 171.421 μs | 155.081 μs |
| inverse_curl! vec->vec | Float64 256^3 | 52.451 ms | 37.454 ms | 35.089 ms | 33.986 ms | 33.468 ms | 20.224 ms | 19.336 ms | 19.543 ms | 1.212 ms | 1.123 ms |
| inverse_curl! vec->vec | Float64 512^3 | 398.158 ms | 299.273 ms | 287.454 ms | 277.968 ms | 261.491 ms | 167.628 ms | 164.623 ms | 166.410 ms | — | — |
| inverse_curl! vec->vec | Float64 64^3 | 766.468 μs | 397.197 μs | 202.002 μs | 107.326 μs | 456.514 μs | 229.833 μs | 119.012 μs | 63.381 μs | 54.489 μs | 30.980 μs |
| inverse_laplacian! scalar | Float32 128^3 | 4.616 ms | 1.639 ms | 869.612 μs | 465.599 μs | 3.898 ms | 1.323 ms | 669.076 μs | 343.404 μs | 60.702 μs | 33.521 μs |
| inverse_laplacian! scalar | Float32 256^3 | 36.468 ms | 13.547 ms | 6.985 ms | 5.125 ms | 31.487 ms | 10.596 ms | 5.322 ms | 2.700 ms | 342.919 μs | 222.813 μs |
| inverse_laplacian! scalar | Float32 512^3 | 289.921 ms | 106.433 ms | 55.016 ms | 45.671 ms | 250.540 ms | 83.592 ms | 42.550 ms | 26.620 ms | 2.560 ms | — |
| inverse_laplacian! scalar | Float32 64^3 | 587.664 μs | 215.132 μs | 125.199 μs | 71.579 μs | 496.625 μs | 177.962 μs | 92.351 μs | 52.561 μs | 31.416 μs | 11.100 μs |
| inverse_laplacian! scalar | Float64 128^3 | 4.917 ms | 1.802 ms | 960.242 μs | 536.484 μs | 4.249 ms | 1.424 ms | 729.628 μs | 372.114 μs | 94.128 μs | 48.710 μs |
| inverse_laplacian! scalar | Float64 256^3 | 39.099 ms | 14.679 ms | 10.747 ms | 8.523 ms | 34.282 ms | 11.519 ms | 5.806 ms | 4.836 ms | 598.742 μs | 348.714 μs |
| inverse_laplacian! scalar | Float64 512^3 | 311.328 ms | 115.447 ms | 86.369 ms | 66.977 ms | 272.559 ms | 91.169 ms | 54.288 ms | 54.398 ms | — | — |
| inverse_laplacian! scalar | Float64 64^3 | 606.968 μs | 227.658 μs | 133.217 μs | 76.041 μs | 540.355 μs | 190.252 μs | 99.841 μs | 55.980 μs | 36.287 μs | 14.110 μs |
| laplacian! scalar | Float32 128^3 | 2.006 ms | 638.071 μs | 330.526 μs | 179.956 μs | 2.144 ms | 493.565 μs | 250.263 μs | 129.481 μs | 52.059 μs | 26.170 μs |
| laplacian! scalar | Float32 256^3 | 16.194 ms | 5.998 ms | 4.967 ms | 4.096 ms | 17.028 ms | 3.872 ms | 1.954 ms | 1.191 ms | 255.126 μs | 189.202 μs |
| laplacian! scalar | Float32 512^3 | 131.457 ms | 49.960 ms | 41.539 ms | 34.753 ms | 136.008 ms | 30.759 ms | 26.172 ms | 26.298 ms | 1.818 ms | — |
| laplacian! scalar | Float32 64^3 | 251.534 μs | 88.207 μs | 48.327 μs | 30.670 μs | 274.793 μs | 68.580 μs | 36.640 μs | 22.240 μs | 30.793 μs | 9.290 μs |
| laplacian! scalar | Float64 128^3 | 2.153 ms | 816.715 μs | 625.347 μs | 440.196 μs | 2.205 ms | 528.455 μs | 271.723 μs | 140.672 μs | 56.643 μs | 29.140 μs |
| laplacian! scalar | Float64 256^3 | 17.397 ms | 11.879 ms | 11.293 ms | 10.519 ms | 17.726 ms | 5.003 ms | 4.779 ms | 4.837 ms | 361.322 μs | 357.304 μs |
| laplacian! scalar | Float64 512^3 | 137.178 ms | 97.215 ms | 95.315 ms | 90.000 ms | 141.578 ms | 53.753 ms | 53.595 ms | 54.419 ms | — | — |
| laplacian! scalar | Float64 64^3 | 266.849 μs | 94.208 μs | 50.539 μs | 33.956 μs | 281.772 μs | 73.040 μs | 38.830 μs | 23.571 μs | 32.122 μs | 10.130 μs |
| symmetric_gradient! vec->tensor | Float32 128^3 | 11.759 ms | 6.054 ms | 4.261 ms | 4.161 ms | 9.617 ms | 4.884 ms | 2.444 ms | 1.236 ms | 84.635 μs | 148.641 μs |
| symmetric_gradient! vec->tensor | Float32 256^3 | 89.641 ms | 46.997 ms | 42.527 ms | 42.023 ms | 76.731 ms | 40.089 ms | 22.914 ms | 23.123 ms | 1.894 ms | 1.127 ms |
| symmetric_gradient! vec->tensor | Float32 512^3 | 733.400 ms | 382.725 ms | 346.421 ms | 334.824 ms | 650.497 ms | 337.874 ms | 209.978 ms | 201.112 ms | 14.546 ms | — |
| symmetric_gradient! vec->tensor | Float32 64^3 | 1.466 ms | 741.265 μs | 375.621 μs | 201.462 μs | 1.214 ms | 621.927 μs | 316.023 μs | 168.062 μs | 44.361 μs | 17.740 μs |
| symmetric_gradient! vec->tensor | Float64 128^3 | 13.174 ms | 10.926 ms | 9.482 ms | 9.473 ms | 10.705 ms | 5.704 ms | 3.591 ms | 3.761 ms | 462.875 μs | 286.953 μs |
| symmetric_gradient! vec->tensor | Float64 256^3 | 111.993 ms | 89.767 ms | 85.834 ms | 84.383 ms | 93.313 ms | 57.178 ms | 49.033 ms | 49.609 ms | 3.417 ms | 2.225 ms |
| symmetric_gradient! vec->tensor | Float64 512^3 | 844.164 ms | 712.063 ms | 688.155 ms | 679.399 ms | 703.560 ms | 447.543 ms | 395.311 ms | 433.016 ms | — | — |
| symmetric_gradient! vec->tensor | Float64 64^3 | 1.511 ms | 814.580 μs | 420.871 μs | 221.147 μs | 1.275 ms | 645.046 μs | 326.464 μs | 166.971 μs | 55.850 μs | 32.210 μs |

## convolution

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| assignment_window | Float32 128^3 | 1.111 μs | 1.183 μs | 1.124 μs | 1.118 μs | 1.165 μs | 1.169 μs | 1.168 μs | 1.169 μs | 80.434 μs | 25.631 μs |
| assignment_window | Float32 256^3 | 2.176 μs | 2.180 μs | 2.191 μs | 2.193 μs | 2.227 μs | 2.231 μs | 2.236 μs | 2.221 μs | 81.047 μs | 25.500 μs |
| assignment_window | Float32 512^3 | 4.432 μs | 4.707 μs | 4.430 μs | 4.435 μs | 4.467 μs | 4.462 μs | 4.470 μs | 4.466 μs | 74.238 μs | — |
| assignment_window | Float32 64^3 | 590.096 ns | 586.921 ns | 607.798 ns | 600.357 ns | 608.177 ns | 610.062 ns | 611.663 ns | 611.091 ns | 86.113 μs | 25.091 μs |
| assignment_window | Float64 128^3 | 1.438 μs | 1.587 μs | 1.439 μs | 1.459 μs | 1.559 μs | 1.551 μs | 1.567 μs | 1.575 μs | 77.699 μs | 26.821 μs |
| assignment_window | Float64 256^3 | 2.953 μs | 2.957 μs | 2.952 μs | 3.272 μs | 3.115 μs | 3.076 μs | 3.089 μs | 3.074 μs | 81.776 μs | 27.501 μs |
| assignment_window | Float64 512^3 | 5.689 μs | 5.701 μs | 5.703 μs | 5.797 μs | 6.022 μs | 5.962 μs | 5.932 μs | 5.966 μs | — | — |
| assignment_window | Float64 64^3 | 728.504 ns | 730.866 ns | 734.373 ns | 741.992 ns | 829.115 ns | 821.532 ns | 827.192 ns | 824.948 ns | 77.382 μs | 26.250 μs |
| combine!∘kernel vector | Float32 128^3 | 3.868 ms | 2.155 ms | 1.630 ms | 1.471 ms | 3.155 ms | 1.548 ms | 777.248 μs | 396.384 μs | 58.003 μs | 79.330 μs |
| combine!∘kernel vector | Float32 256^3 | 31.418 ms | 20.656 ms | 19.439 ms | 18.404 ms | 25.242 ms | 12.704 ms | 9.938 ms | 9.887 ms | 957.388 μs | 863.549 μs |
| combine!∘kernel vector | Float32 512^3 | 263.337 ms | 171.413 ms | 161.639 ms | 153.417 ms | 242.879 ms | 102.236 ms | 92.999 ms | 93.344 ms | 7.318 ms | — |
| combine!∘kernel vector | Float32 64^3 | 495.976 μs | 259.925 μs | 139.983 μs | 74.257 μs | 422.295 μs | 206.253 μs | 105.651 μs | 56.551 μs | 38.774 μs | 13.340 μs |
| combine!∘kernel vector | Float64 128^3 | 5.275 ms | 4.587 ms | 4.146 ms | 3.909 ms | 3.748 ms | 2.080 ms | 1.108 ms | 754.328 μs | 255.325 μs | 225.052 μs |
| combine!∘kernel vector | Float64 256^3 | 49.026 ms | 42.950 ms | 40.623 ms | 38.529 ms | 34.090 ms | 23.100 ms | 21.977 ms | 22.168 ms | 1.869 ms | 1.713 ms |
| combine!∘kernel vector | Float64 512^3 | 361.282 ms | 337.301 ms | 320.499 ms | 307.009 ms | 289.421 ms | 190.866 ms | 183.886 ms | 185.179 ms | — | — |
| combine!∘kernel vector | Float64 64^3 | 509.952 μs | 274.727 μs | 142.654 μs | 83.806 μs | 383.943 μs | 223.292 μs | 114.301 μs | 62.341 μs | 50.231 μs | 25.210 μs |
| convolve! scalar | Float32 128^3 | 1.589 ms | 300.612 μs | 198.800 μs | 88.466 μs | 920.519 μs | 104.561 μs | 53.651 μs | 35.850 μs | 41.907 μs | 21.390 μs |
| convolve! scalar | Float32 256^3 | 12.941 ms | 7.711 ms | 7.237 ms | 6.804 ms | 7.584 ms | 2.799 ms | 2.704 ms | 2.738 ms | 291.904 μs | 260.513 μs |
| convolve! scalar | Float32 512^3 | 105.016 ms | 65.359 ms | 63.431 ms | 59.542 ms | 62.301 ms | 37.346 ms | 36.616 ms | 37.005 ms | 2.052 ms | — |
| convolve! scalar | Float32 64^3 | 198.017 μs | 41.158 μs | 21.757 μs | 13.901 μs | 116.872 μs | 16.201 μs | 9.000 μs | 7.554 μs | 28.054 μs | 8.200 μs |
| convolve! scalar | Float64 128^3 | 1.762 ms | 1.355 ms | 1.156 ms | 1.019 ms | 1.000 ms | 173.062 μs | 90.971 μs | 72.090 μs | 57.715 μs | 33.070 μs |
| convolve! scalar | Float64 256^3 | 17.998 ms | 16.174 ms | 15.283 ms | 14.244 ms | 10.939 ms | 7.897 ms | 7.612 ms | 7.756 ms | 553.143 μs | 516.776 μs |
| convolve! scalar | Float64 512^3 | 142.058 ms | 131.762 ms | 125.751 ms | 118.876 ms | 90.042 ms | 73.691 ms | 73.668 ms | 74.107 ms | — | — |
| convolve! scalar | Float64 64^3 | 175.791 μs | 49.950 μs | 25.817 μs | 21.086 μs | 127.711 μs | 26.650 μs | 13.790 μs | 10.140 μs | 33.041 μs | 9.970 μs |
| convolve! vector | Float32 128^3 | 2.647 ms | 1.818 ms | 1.554 ms | 1.471 ms | 2.103 ms | 1.099 ms | 551.226 μs | 282.593 μs | 49.104 μs | 59.581 μs |
| convolve! vector | Float32 256^3 | 22.493 ms | 20.375 ms | 19.207 ms | 18.249 ms | 19.800 ms | 10.967 ms | 9.857 ms | 9.886 ms | 623.018 μs | 618.736 μs |
| convolve! vector | Float32 512^3 | 190.919 ms | 168.582 ms | 159.982 ms | 153.464 ms | 178.202 ms | 94.040 ms | 92.441 ms | 93.133 ms | 4.735 ms | — |
| convolve! vector | Float32 64^3 | 312.956 μs | 173.772 μs | 90.333 μs | 50.263 μs | 270.172 μs | 147.462 μs | 74.430 μs | 39.981 μs | 36.744 μs | 10.610 μs |
| convolve! vector | Float64 128^3 | 4.842 ms | 4.559 ms | 4.147 ms | 3.936 ms | 2.658 ms | 1.541 ms | 877.809 μs | 751.219 μs | 187.728 μs | 160.172 μs |
| convolve! vector | Float64 256^3 | 44.952 ms | 42.233 ms | 40.173 ms | 38.406 ms | 30.584 ms | 22.849 ms | 21.958 ms | 22.125 ms | 1.213 ms | 1.228 ms |
| convolve! vector | Float64 512^3 | 340.338 ms | 334.419 ms | 318.403 ms | 308.204 ms | 239.732 ms | 188.786 ms | 183.720 ms | 185.473 ms | — | — |
| convolve! vector | Float64 64^3 | 268.475 μs | 162.630 μs | 87.980 μs | 63.610 μs | 219.633 μs | 136.691 μs | 70.381 μs | 39.240 μs | 42.638 μs | 18.600 μs |
| convolve! vector ∘ radial    | Float32 128^3 | 4.110 ms | 2.145 ms | 1.473 ms | 1.230 ms | 2.505 ms | 1.250 ms | 628.887 μs | 321.373 μs | 127.777 μs | 83.061 μs |
| convolve! vector ∘ radial    | Float32 256^3 | 32.567 ms | 19.074 ms | 16.478 ms | 13.995 ms | 19.845 ms | 10.077 ms | 8.208 ms | 8.362 ms | 861.276 μs | 610.286 μs |
| convolve! vector ∘ radial    | Float32 512^3 | 260.725 ms | 153.055 ms | 126.764 ms | 106.445 ms | 158.316 ms | 86.586 ms | 89.653 ms | 82.221 ms | 6.548 ms | — |
| convolve! vector ∘ radial    | Float32 64^3 | 497.765 μs | 260.128 μs | 132.560 μs | 77.743 μs | 315.844 μs | 160.552 μs | 82.201 μs | 43.561 μs | 44.101 μs | 16.651 μs |
| convolve! vector ∘ radial    | Float64 128^3 | 5.103 ms | 4.101 ms | 3.508 ms | 2.949 ms | 2.878 ms | 1.454 ms | 727.637 μs | 408.764 μs | 149.936 μs | 136.721 μs |
| convolve! vector ∘ radial    | Float64 256^3 | 41.527 ms | 36.672 ms | 29.820 ms | 26.141 ms | 24.296 ms | 18.669 ms | 18.791 ms | 19.079 ms | 1.084 ms | 1.065 ms |
| convolve! vector ∘ radial    | Float64 512^3 | 329.321 ms | 290.663 ms | 225.546 ms | 199.280 ms | 197.514 ms | 161.014 ms | 162.505 ms | 163.970 ms | — | — |
| convolve! vector ∘ radial    | Float64 64^3 | 533.590 μs | 278.916 μs | 142.231 μs | 88.343 μs | 352.993 μs | 177.482 μs | 89.621 μs | 48.370 μs | 46.540 μs | 18.450 μs |
| convolve! vector ∘ radial-stored | Float32 128^3 | 2.676 ms | 1.820 ms | 1.553 ms | 1.481 ms | 2.105 ms | 1.103 ms | 550.245 μs | 282.943 μs | 48.915 μs | 60.920 μs |
| convolve! vector ∘ radial-stored | Float32 256^3 | 23.272 ms | 20.388 ms | 19.238 ms | 18.286 ms | 19.701 ms | 10.964 ms | 9.795 ms | 9.884 ms | 623.028 μs | 619.116 μs |
| convolve! vector ∘ radial-stored | Float32 512^3 | 192.103 ms | 169.090 ms | 159.970 ms | 153.358 ms | 177.509 ms | 93.862 ms | 92.252 ms | 92.768 ms | 4.645 ms | — |
| convolve! vector ∘ radial-stored | Float32 64^3 | 313.944 μs | 176.488 μs | 90.261 μs | 50.077 μs | 269.593 μs | 147.372 μs | 74.521 μs | 39.940 μs | 36.861 μs | 10.570 μs |
| convolve! vector ∘ radial-stored | Float64 128^3 | 4.881 ms | 4.565 ms | 4.088 ms | 3.913 ms | 2.652 ms | 1.551 ms | 888.369 μs | 749.988 μs | 179.090 μs | 160.271 μs |
| convolve! vector ∘ radial-stored | Float64 256^3 | 44.967 ms | 42.369 ms | 40.157 ms | 38.402 ms | 30.365 ms | 22.484 ms | 21.926 ms | 22.024 ms | 1.212 ms | 1.229 ms |
| convolve! vector ∘ radial-stored | Float64 512^3 | 342.881 ms | 334.479 ms | 319.558 ms | 308.139 ms | 238.013 ms | 186.294 ms | 183.911 ms | 184.397 ms | — | — |
| convolve! vector ∘ radial-stored | Float64 64^3 | 271.151 μs | 166.509 μs | 88.254 μs | 58.057 μs | 230.442 μs | 136.732 μs | 70.230 μs | 38.340 μs | 42.660 μs | 18.620 μs |
| convolve! vector ∘ separable | Float32 128^3 | 6.741 ms | 3.449 ms | 1.776 ms | 1.200 ms | 4.689 ms | 2.349 ms | 1.169 ms | 591.396 μs | 125.778 μs | 83.821 μs |
| convolve! vector ∘ separable | Float32 256^3 | 53.348 ms | 27.340 ms | 16.981 ms | 13.330 ms | 37.225 ms | 18.611 ms | 9.372 ms | 8.451 ms | 850.028 μs | 613.806 μs |
| convolve! vector ∘ separable | Float32 512^3 | 423.606 ms | 221.217 ms | 137.072 ms | 107.433 ms | 296.142 ms | 148.181 ms | 82.539 ms | 82.763 ms | 6.745 ms | — |
| convolve! vector ∘ separable | Float32 64^3 | 853.568 μs | 435.299 μs | 223.806 μs | 118.335 μs | 588.566 μs | 297.343 μs | 150.462 μs | 78.021 μs | 44.128 μs | 16.850 μs |
| convolve! vector ∘ separable | Float64 128^3 | 6.730 ms | 4.084 ms | 3.388 ms | 2.462 ms | 3.958 ms | 1.994 ms | 1.003 ms | 510.466 μs | 246.534 μs | 144.741 μs |
| convolve! vector ∘ separable | Float64 256^3 | 53.933 ms | 36.967 ms | 29.232 ms | 23.130 ms | 32.560 ms | 19.223 ms | 19.009 ms | 19.292 ms | 1.685 ms | 1.077 ms |
| convolve! vector ∘ separable | Float64 512^3 | 431.280 ms | 292.886 ms | 230.767 ms | 186.772 ms | 259.746 ms | 164.962 ms | 163.125 ms | 165.071 ms | — | — |
| convolve! vector ∘ separable | Float64 64^3 | 816.311 μs | 426.235 μs | 220.551 μs | 114.761 μs | 495.104 μs | 248.922 μs | 125.841 μs | 66.181 μs | 58.106 μs | 25.410 μs |
| convolve! vector ∘ stored    | Float32 128^3 | 2.643 ms | 1.825 ms | 1.552 ms | 1.487 ms | 2.106 ms | 1.097 ms | 555.286 μs | 286.613 μs | 48.644 μs | 58.650 μs |
| convolve! vector ∘ stored    | Float32 256^3 | 23.216 ms | 20.411 ms | 19.232 ms | 18.265 ms | 19.818 ms | 10.941 ms | 9.833 ms | 9.908 ms | 620.710 μs | 619.657 μs |
| convolve! vector ∘ stored    | Float32 512^3 | 191.075 ms | 168.881 ms | 159.844 ms | 153.313 ms | 178.025 ms | 94.514 ms | 92.389 ms | 93.192 ms | 4.785 ms | — |
| convolve! vector ∘ stored    | Float32 64^3 | 313.061 μs | 176.906 μs | 92.055 μs | 50.540 μs | 270.233 μs | 147.781 μs | 75.350 μs | 39.921 μs | 37.027 μs | 10.670 μs |
| convolve! vector ∘ stored    | Float64 128^3 | 4.884 ms | 4.599 ms | 4.076 ms | 3.916 ms | 2.644 ms | 1.546 ms | 907.549 μs | 757.729 μs | 181.592 μs | 159.682 μs |
| convolve! vector ∘ stored    | Float64 256^3 | 45.015 ms | 42.347 ms | 40.188 ms | 38.434 ms | 30.489 ms | 22.879 ms | 21.948 ms | 22.105 ms | 1.214 ms | 1.228 ms |
| convolve! vector ∘ stored    | Float64 512^3 | 343.345 ms | 334.625 ms | 319.410 ms | 308.221 ms | 243.545 ms | 188.576 ms | 183.820 ms | 185.276 ms | — | — |
| convolve! vector ∘ stored    | Float64 64^3 | 272.169 μs | 163.688 μs | 90.400 μs | 61.108 μs | 221.182 μs | 136.832 μs | 71.981 μs | 40.610 μs | 42.381 μs | 18.590 μs |
| exponential_convolve! scalar | Float32 128^3 | 6.107 ms | 2.697 ms | 1.360 ms | 727.276 μs | 5.033 ms | 2.121 ms | 1.064 ms | 540.475 μs | 49.958 μs | 26.510 μs |
| exponential_convolve! scalar | Float32 256^3 | 48.322 ms | 21.149 ms | 10.632 ms | 6.139 ms | 39.779 ms | 16.571 ms | 8.360 ms | 4.232 ms | 259.740 μs | 189.642 μs |
| exponential_convolve! scalar | Float32 512^3 | 383.996 ms | 167.866 ms | 84.733 ms | 49.804 ms | 317.441 ms | 131.850 ms | 66.198 ms | 34.871 ms | 1.853 ms | — |
| exponential_convolve! scalar | Float32 64^3 | 763.831 μs | 349.404 μs | 179.776 μs | 101.066 μs | 640.306 μs | 280.483 μs | 145.271 μs | 77.911 μs | 31.203 μs | 9.300 μs |
| exponential_convolve! scalar | Float64 128^3 | 5.771 ms | 2.555 ms | 1.369 ms | 855.123 μs | 5.558 ms | 2.382 ms | 1.193 ms | 608.507 μs | 94.223 μs | 79.371 μs |
| exponential_convolve! scalar | Float64 256^3 | 45.741 ms | 20.253 ms | 11.999 ms | 10.926 ms | 44.292 ms | 18.813 ms | 9.470 ms | 4.995 ms | 602.281 μs | 565.516 μs |
| exponential_convolve! scalar | Float64 512^3 | 363.451 ms | 160.232 ms | 97.879 ms | 90.643 ms | 350.959 ms | 149.802 ms | 75.166 ms | 55.078 ms | — | — |
| exponential_convolve! scalar | Float64 64^3 | 718.522 μs | 329.227 μs | 171.598 μs | 96.254 μs | 701.017 μs | 306.833 μs | 159.081 μs | 85.241 μs | 40.426 μs | 17.450 μs |
| exponential_convolve! vector | Float32 128^3 | 5.381 ms | 2.624 ms | 1.502 ms | 1.221 ms | 4.716 ms | 1.869 ms | 943.920 μs | 477.715 μs | 47.339 μs | 36.990 μs |
| exponential_convolve! vector | Float32 256^3 | 43.128 ms | 22.920 ms | 17.686 ms | 16.394 ms | 41.279 ms | 16.485 ms | 10.175 ms | 8.989 ms | 557.247 μs | 541.605 μs |
| exponential_convolve! vector | Float32 512^3 | 341.219 ms | 192.776 ms | 145.958 ms | 135.677 ms | 514.995 ms | 144.093 ms | 94.993 ms | 83.391 ms | 4.150 ms | — |
| exponential_convolve! vector | Float32 64^3 | 678.353 μs | 320.987 μs | 163.749 μs | 88.537 μs | 624.156 μs | 251.363 μs | 127.711 μs | 66.861 μs | 34.994 μs | 10.040 μs |
| exponential_convolve! vector | Float64 128^3 | 5.870 ms | 4.010 ms | 3.573 ms | 3.358 ms | 5.235 ms | 2.080 ms | 1.033 ms | 552.436 μs | 97.710 μs | 143.992 μs |
| exponential_convolve! vector | Float64 256^3 | 50.211 ms | 37.296 ms | 35.338 ms | 33.608 ms | 69.074 ms | 24.888 ms | 20.769 ms | 20.232 ms | 1.161 ms | 1.077 ms |
| exponential_convolve! vector | Float64 512^3 | 367.007 ms | 294.295 ms | 282.292 ms | 269.246 ms | 1.007 s | 201.032 ms | 167.389 ms | 165.459 ms | — | — |
| exponential_convolve! vector | Float64 64^3 | 633.589 μs | 278.332 μs | 142.529 μs | 87.097 μs | 674.077 μs | 252.593 μs | 126.201 μs | 67.411 μs | 40.796 μs | 20.170 μs |
| inv separable | Float32 128^3 | 957.105 ns | 965.000 ns | 965.421 ns | 960.000 ns | 765.185 ns | 765.048 ns | 761.914 ns | 758.791 ns | 210.459 μs | 51.590 μs |
| inv separable | Float32 256^3 | 1.964 μs | 1.974 μs | 1.979 μs | 1.969 μs | 1.554 μs | 1.564 μs | 1.553 μs | 1.557 μs | 210.382 μs | 57.001 μs |
| inv separable | Float32 512^3 | 3.863 μs | 3.882 μs | 3.871 μs | 3.837 μs | 2.994 μs | 3.024 μs | 3.010 μs | 3.105 μs | 247.647 μs | — |
| inv separable | Float32 64^3 | 507.161 ns | 513.573 ns | 527.387 ns | 509.646 ns | 407.755 ns | 408.648 ns | 408.455 ns | 410.357 ns | 205.344 μs | 49.491 μs |
| inv separable | Float64 128^3 | 1.123 μs | 1.089 μs | 1.089 μs | 1.091 μs | 1.066 μs | 1.065 μs | 1.065 μs | 1.054 μs | 200.968 μs | 53.400 μs |
| inv separable | Float64 256^3 | 2.143 μs | 2.128 μs | 2.154 μs | 2.151 μs | 2.038 μs | 2.036 μs | 2.054 μs | 2.047 μs | 197.643 μs | 59.981 μs |
| inv separable | Float64 512^3 | 4.067 μs | 4.055 μs | 4.040 μs | 4.043 μs | 3.977 μs | 4.019 μs | 4.003 μs | 3.986 μs | — | — |
| inv separable | Float64 64^3 | 530.915 ns | 532.984 ns | 536.330 ns | 535.312 ns | 520.110 ns | 532.361 ns | 523.339 ns | 536.147 ns | 205.420 μs | 49.920 μs |
| materialize_kernel radial | Float32 128^3 | 1.436 ms | 605.672 μs | 404.875 μs | 220.775 μs | 1.130 ms | 351.443 μs | 178.282 μs | 93.241 μs | 53.151 μs | 26.180 μs |
| materialize_kernel radial | Float32 256^3 | 11.302 ms | 4.562 ms | 3.621 ms | 2.611 ms | 8.973 ms | 2.764 ms | 1.984 ms | 2.035 ms | 336.736 μs | 150.362 μs |
| materialize_kernel radial | Float32 512^3 | 89.600 ms | 35.943 ms | 28.688 ms | 22.224 ms | 71.419 ms | 22.162 ms | 32.141 ms | 17.154 ms | 5.278 ms | — |
| materialize_kernel radial | Float32 64^3 | 170.431 μs | 73.861 μs | 40.301 μs | 30.156 μs | 145.731 μs | 47.990 μs | 25.570 μs | 15.730 μs | 39.873 μs | 9.830 μs |
| materialize_kernel radial | Float64 128^3 | 1.492 ms | 968.027 μs | 693.167 μs | 442.106 μs | 1.179 ms | 372.844 μs | 226.272 μs | 305.163 μs | 61.949 μs | 29.721 μs |
| materialize_kernel radial | Float64 256^3 | 11.617 ms | 7.891 ms | 5.700 ms | 5.474 ms | 9.497 ms | 3.984 ms | 3.874 ms | 3.802 ms | 381.730 μs | 177.302 μs |
| materialize_kernel radial | Float64 512^3 | 92.516 ms | 142.871 ms | 76.942 ms | 45.746 ms | 75.444 ms | 33.815 ms | 53.247 ms | 35.706 ms | — | — |
| materialize_kernel radial | Float64 64^3 | 176.983 μs | 72.429 μs | 44.095 μs | 39.376 μs | 151.641 μs | 48.180 μs | 25.691 μs | 15.740 μs | 38.382 μs | 11.440 μs |
| materialize_kernel separable | Float32 128^3 | 1.797 ms | 781.498 μs | 446.815 μs | 296.831 μs | 1.533 ms | 446.084 μs | 227.382 μs | 116.862 μs | 53.450 μs | 25.980 μs |
| materialize_kernel separable | Float32 256^3 | 14.331 ms | 6.140 ms | 3.898 ms | 3.075 ms | 12.131 ms | 3.526 ms | 1.970 ms | 1.945 ms | 351.038 μs | 156.032 μs |
| materialize_kernel separable | Float32 512^3 | 114.594 ms | 49.139 ms | 31.253 ms | 24.042 ms | 96.540 ms | 27.869 ms | 35.141 ms | 17.953 ms | 5.207 ms | — |
| materialize_kernel separable | Float32 64^3 | 227.545 μs | 102.107 μs | 55.041 μs | 37.769 μs | 196.462 μs | 60.211 μs | 32.061 μs | 18.910 μs | 39.842 μs | 9.840 μs |
| materialize_kernel separable | Float64 128^3 | 1.788 ms | 972.334 μs | 772.567 μs | 535.672 μs | 1.449 ms | 453.995 μs | 240.243 μs | 291.063 μs | 74.883 μs | 36.891 μs |
| materialize_kernel separable | Float64 256^3 | 14.287 ms | 7.885 ms | 6.048 ms | 5.751 ms | 11.562 ms | 4.422 ms | 3.885 ms | 4.034 ms | 648.892 μs | 233.583 μs |
| materialize_kernel separable | Float64 512^3 | 116.085 ms | 63.147 ms | 81.939 ms | 48.531 ms | 91.967 ms | 38.488 ms | 61.319 ms | 44.372 ms | — | — |
| materialize_kernel separable | Float64 64^3 | 225.180 μs | 103.673 μs | 54.521 μs | 50.833 μs | 186.732 μs | 61.210 μs | 32.101 μs | 19.271 μs | 42.113 μs | 11.900 μs |
| radial_kernel | Float32 128^3 | 0.803 ns | 1.193 ns | 1.194 ns | 1.194 ns | 1.330 ns | 1.330 ns | 1.330 ns | 1.330 ns | 329.831 ns | 315.045 ns |
| radial_kernel | Float32 256^3 | 0.803 ns | 1.194 ns | 1.193 ns | 1.194 ns | 1.330 ns | 1.330 ns | 1.330 ns | 1.330 ns | 321.031 ns | 309.516 ns |
| radial_kernel | Float32 512^3 | 0.803 ns | 1.195 ns | 1.194 ns | 1.194 ns | 1.330 ns | 1.330 ns | 1.330 ns | 1.330 ns | 320.269 ns | — |
| radial_kernel | Float32 64^3 | 0.819 ns | 1.195 ns | 1.194 ns | 1.195 ns | 1.330 ns | 1.330 ns | 1.330 ns | 1.330 ns | 330.570 ns | 308.324 ns |
| radial_kernel | Float64 128^3 | 0.803 ns | 1.290 ns | 1.219 ns | 1.193 ns | 1.330 ns | 1.330 ns | 1.330 ns | 0.960 ns | 327.885 ns | 307.718 ns |
| radial_kernel | Float64 256^3 | 0.803 ns | 1.392 ns | 1.196 ns | 1.194 ns | 1.330 ns | 1.330 ns | 1.330 ns | 0.960 ns | 331.798 ns | 307.514 ns |
| radial_kernel | Float64 512^3 | 0.803 ns | 1.392 ns | 1.194 ns | 1.193 ns | 1.330 ns | 1.330 ns | 1.330 ns | 1.320 ns | — | — |
| radial_kernel | Float64 64^3 | 0.803 ns | 1.391 ns | 1.195 ns | 1.194 ns | 1.330 ns | 1.330 ns | 1.330 ns | 0.960 ns | 330.665 ns | 307.841 ns |
| spectral_band | Float32 128^3 | 0.803 ns | 1.194 ns | 1.219 ns | 1.195 ns | 0.960 ns | 1.330 ns | 0.960 ns | 1.000 ns | 326.191 ns | 311.684 ns |
| spectral_band | Float32 256^3 | 0.803 ns | 1.194 ns | 1.195 ns | 1.194 ns | 1.330 ns | 1.330 ns | 1.330 ns | 0.960 ns | 322.173 ns | 310.428 ns |
| spectral_band | Float32 512^3 | 0.803 ns | 1.194 ns | 1.194 ns | 1.194 ns | 1.330 ns | 1.330 ns | 1.330 ns | 1.330 ns | 319.587 ns | — |
| spectral_band | Float32 64^3 | 0.820 ns | 1.219 ns | 1.195 ns | 1.194 ns | 1.330 ns | 1.340 ns | 1.360 ns | 0.980 ns | 326.009 ns | 307.914 ns |
| spectral_band | Float64 128^3 | 0.803 ns | 1.196 ns | 1.195 ns | 1.193 ns | 1.330 ns | 0.960 ns | 0.960 ns | 1.330 ns | 326.665 ns | 307.386 ns |
| spectral_band | Float64 256^3 | 0.802 ns | 1.221 ns | 1.219 ns | 1.193 ns | 1.330 ns | 0.960 ns | 0.960 ns | 1.320 ns | 328.926 ns | 307.024 ns |
| spectral_band | Float64 512^3 | 0.803 ns | 1.197 ns | 1.195 ns | 1.192 ns | 1.320 ns | 0.960 ns | 0.960 ns | 1.330 ns | — | — |
| spectral_band | Float64 64^3 | 0.803 ns | 1.195 ns | 1.194 ns | 1.193 ns | 1.330 ns | 0.960 ns | 0.960 ns | 0.950 ns | 325.250 ns | 308.238 ns |
| spectral_cutoff | Float32 128^3 | 0.803 ns | 1.194 ns | 1.193 ns | 1.193 ns | 1.330 ns | 1.330 ns | 1.330 ns | 0.960 ns | 325.436 ns | 307.963 ns |
| spectral_cutoff | Float32 256^3 | 0.803 ns | 1.196 ns | 1.217 ns | 1.193 ns | 1.330 ns | 1.330 ns | 1.330 ns | 0.990 ns | 321.170 ns | 317.525 ns |
| spectral_cutoff | Float32 512^3 | 0.803 ns | 1.219 ns | 1.193 ns | 1.218 ns | 1.330 ns | 1.320 ns | 1.320 ns | 0.960 ns | 317.395 ns | — |
| spectral_cutoff | Float32 64^3 | 0.803 ns | 1.194 ns | 1.193 ns | 1.193 ns | 1.330 ns | 1.330 ns | 1.330 ns | 1.330 ns | 323.729 ns | 307.914 ns |
| spectral_cutoff | Float64 128^3 | 0.803 ns | 1.193 ns | 1.220 ns | 1.194 ns | 0.960 ns | 1.320 ns | 1.330 ns | 0.980 ns | 328.724 ns | 307.759 ns |
| spectral_cutoff | Float64 256^3 | 0.803 ns | 1.194 ns | 1.220 ns | 1.195 ns | 0.960 ns | 1.330 ns | 0.960 ns | 0.960 ns | 325.535 ns | 307.381 ns |
| spectral_cutoff | Float64 512^3 | 0.803 ns | 1.218 ns | 1.220 ns | 1.218 ns | 0.960 ns | 0.960 ns | 1.330 ns | 1.330 ns | — | — |
| spectral_cutoff | Float64 64^3 | 0.803 ns | 1.218 ns | 1.195 ns | 1.193 ns | 0.960 ns | 0.960 ns | 1.330 ns | 1.000 ns | 326.791 ns | 307.922 ns |
| translation_kernel | Float32 128^3 | 1.795 μs | 1.804 μs | 1.851 μs | 1.819 μs | 1.447 μs | 1.410 μs | 1.418 μs | 1.429 μs | 53.639 μs | 15.960 μs |
| translation_kernel | Float32 256^3 | 3.535 μs | 3.543 μs | 3.550 μs | 3.592 μs | 2.797 μs | 2.733 μs | 2.738 μs | 2.741 μs | 53.241 μs | 16.250 μs |
| translation_kernel | Float32 512^3 | 6.890 μs | 6.908 μs | 6.904 μs | 6.933 μs | 5.422 μs | 5.313 μs | 5.302 μs | 5.295 μs | 51.266 μs | — |
| translation_kernel | Float32 64^3 | 897.860 ns | 902.929 ns | 911.951 ns | 900.658 ns | 760.095 ns | 741.534 ns | 741.139 ns | 748.632 ns | 55.253 μs | 15.670 μs |
| translation_kernel | Float64 128^3 | 2.010 μs | 2.134 μs | 2.020 μs | 2.074 μs | 1.844 μs | 1.835 μs | 1.843 μs | 1.826 μs | 61.541 μs | 17.670 μs |
| translation_kernel | Float64 256^3 | 3.830 μs | 3.821 μs | 3.834 μs | 3.947 μs | 3.474 μs | 3.474 μs | 3.483 μs | 3.462 μs | 60.245 μs | 18.620 μs |
| translation_kernel | Float64 512^3 | 7.310 μs | 7.296 μs | 7.311 μs | 7.501 μs | 6.760 μs | 6.867 μs | 6.770 μs | 6.778 μs | — | — |
| translation_kernel | Float64 64^3 | 1.011 μs | 1.018 μs | 1.083 μs | 1.032 μs | 931.786 ns | 944.828 ns | 954.862 ns | 941.111 ns | 59.045 μs | 16.980 μs |
| translation_kernel! | Float32 128^3 | 1.857 μs | 1.774 μs | 1.755 μs | 1.762 μs | 1.369 μs | 1.370 μs | 1.375 μs | 1.372 μs | 31.686 μs | 13.110 μs |
| translation_kernel! | Float32 256^3 | 3.407 μs | 3.432 μs | 3.413 μs | 3.416 μs | 2.648 μs | 2.626 μs | 2.616 μs | 2.622 μs | 35.119 μs | 13.290 μs |
| translation_kernel! | Float32 512^3 | 6.714 μs | 6.726 μs | 6.733 μs | 6.795 μs | 5.110 μs | 5.158 μs | 5.112 μs | 5.112 μs | 31.667 μs | — |
| translation_kernel! | Float32 64^3 | 856.651 ns | 864.484 ns | 857.397 ns | 856.586 ns | 704.660 ns | 710.146 ns | 703.410 ns | 704.203 ns | 35.232 μs | 13.201 μs |
| translation_kernel! | Float64 128^3 | 1.897 μs | 1.865 μs | 1.859 μs | 1.878 μs | 1.692 μs | 1.698 μs | 1.703 μs | 1.701 μs | 36.949 μs | 14.460 μs |
| translation_kernel! | Float64 256^3 | 3.585 μs | 3.617 μs | 3.603 μs | 3.624 μs | 3.245 μs | 3.239 μs | 3.239 μs | 3.241 μs | 37.060 μs | 15.690 μs |
| translation_kernel! | Float64 512^3 | 7.111 μs | 7.139 μs | 7.069 μs | 7.160 μs | 6.352 μs | 6.358 μs | 6.350 μs | 6.400 μs | — | — |
| translation_kernel! | Float64 64^3 | 961.579 ns | 967.368 ns | 961.000 ns | 966.200 ns | 878.620 ns | 881.538 ns | 886.154 ns | 882.820 ns | 38.003 μs | 14.270 μs |

## transfer

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| anterpolate! CatmullRom ordered | Float32 128^3 | 22.150 ms | 11.510 ms | 5.823 ms | 3.501 ms | 20.310 ms | 10.300 ms | 5.325 ms | 2.843 ms | 154.151 μs | 130.131 μs |
| anterpolate! CatmullRom ordered | Float32 256^3 | 188.335 ms | 98.427 ms | 51.682 ms | 28.791 ms | 163.951 ms | 83.737 ms | 42.376 ms | 21.865 ms | 1.008 ms | 1.003 ms |
| anterpolate! CatmullRom ordered | Float32 512^3 | 2.076 s | 1.067 s | 554.772 ms | 303.736 ms | 1.543 s | 786.928 ms | 406.293 ms | 207.933 ms | — | — |
| anterpolate! CatmullRom ordered | Float32 64^3 | 2.760 ms | 1.497 ms | 925.148 μs | 648.694 μs | 2.437 ms | 1.293 ms | 780.848 μs | 525.755 μs | 60.873 μs | 47.191 μs |
| anterpolate! CatmullRom ordered | Float64 128^3 | 23.074 ms | 11.879 ms | 6.293 ms | 3.626 ms | 21.942 ms | 11.139 ms | 5.814 ms | 3.205 ms | 247.832 μs | 141.291 μs |
| anterpolate! CatmullRom ordered | Float64 256^3 | 231.205 ms | 120.869 ms | 63.630 ms | 36.424 ms | 174.151 ms | 88.842 ms | 46.364 ms | 25.044 ms | 1.742 ms | 1.417 ms |
| anterpolate! CatmullRom ordered | Float64 512^3 | 2.431 s | 1.276 s | 688.011 ms | 406.898 ms | 2.038 s | 1.056 s | 550.749 ms | 298.541 ms | — | — |
| anterpolate! CatmullRom ordered | Float64 64^3 | 2.793 ms | 1.541 ms | 960.305 μs | 680.487 μs | 2.453 ms | 1.304 ms | 791.178 μs | 536.455 μs | 104.660 μs | 48.830 μs |
| anterpolate! CatmullRom vector ordered | Float32 128^3 | 67.648 ms | 36.096 ms | 18.228 ms | 10.546 ms | 59.648 ms | 29.953 ms | 15.347 ms | 8.304 ms | 397.145 μs | 363.584 μs |
| anterpolate! CatmullRom vector ordered | Float32 256^3 | 590.342 ms | 323.136 ms | 157.489 ms | 89.725 ms | 474.661 ms | 241.518 ms | 123.423 ms | 64.770 ms | 2.871 ms | 3.052 ms |
| anterpolate! CatmullRom vector ordered | Float32 512^3 | 5.789 s | 3.035 s | 1.594 s | 901.803 ms | 4.514 s | 2.267 s | 1.153 s | 599.291 ms | — | — |
| anterpolate! CatmullRom vector ordered | Float32 64^3 | 8.449 ms | 4.598 ms | 2.964 ms | 2.040 ms | 7.218 ms | 3.822 ms | 2.304 ms | 1.547 ms | 122.033 μs | 123.321 μs |
| anterpolate! CatmullRom vector ordered | Float64 128^3 | 73.167 ms | 38.565 ms | 20.829 ms | 12.751 ms | 59.984 ms | 30.451 ms | 15.706 ms | 8.762 ms | 654.140 μs | 481.794 μs |
| anterpolate! CatmullRom vector ordered | Float64 256^3 | 700.837 ms | 361.425 ms | 191.173 ms | 113.031 ms | 535.223 ms | 272.186 ms | 145.850 ms | 78.365 ms | 5.038 ms | 4.391 ms |
| anterpolate! CatmullRom vector ordered | Float64 512^3 | 6.611 s | 3.480 s | 1.912 s | 1.141 s | 5.378 s | 2.757 s | 1.426 s | 762.651 ms | — | — |
| anterpolate! CatmullRom vector ordered | Float64 64^3 | 8.621 ms | 4.705 ms | 2.918 ms | 2.026 ms | 7.608 ms | 4.001 ms | 2.454 ms | 1.653 ms | 249.805 μs | 108.081 μs |
| anterpolate! CatmullRom vector | Float32 128^3 | 81.514 ms | 40.430 ms | 20.648 ms | 11.951 ms | 63.555 ms | 32.408 ms | 16.693 ms | 9.141 ms | 480.734 μs | 362.243 μs |
| anterpolate! CatmullRom vector | Float32 256^3 | 934.592 ms | 499.817 ms | 331.791 ms | 239.019 ms | 829.189 ms | 430.266 ms | 225.219 ms | 117.330 ms | 8.160 ms | 10.707 ms |
| anterpolate! CatmullRom vector | Float32 512^3 | 7.667 s | 4.064 s | 2.467 s | 1.987 s | 9.065 s | 4.765 s | 2.515 s | 1.406 s | — | — |
| anterpolate! CatmullRom vector | Float32 64^3 | 9.382 ms | 4.872 ms | 3.118 ms | 2.160 ms | 7.250 ms | 3.995 ms | 2.530 ms | 1.739 ms | 126.391 μs | 114.711 μs |
| anterpolate! CatmullRom vector | Float64 128^3 | 100.099 ms | 54.382 ms | 30.850 ms | 22.301 ms | 66.086 ms | 34.334 ms | 17.942 ms | 10.274 ms | 696.236 μs | 648.116 μs |
| anterpolate! CatmullRom vector | Float64 256^3 | 969.583 ms | 524.595 ms | 372.347 ms | 276.167 ms | 1.026 s | 520.241 ms | 280.228 ms | 158.631 ms | 12.021 ms | 14.590 ms |
| anterpolate! CatmullRom vector | Float64 512^3 | 8.873 s | 4.770 s | 2.786 s | 2.234 s | 9.086 s | 4.700 s | 2.483 s | 1.436 s | — | — |
| anterpolate! CatmullRom vector | Float64 64^3 | 9.796 ms | 4.948 ms | 3.088 ms | 2.460 ms | 7.719 ms | 4.288 ms | 2.681 ms | 1.909 ms | 224.830 μs | 112.041 μs |
| anterpolate! CatmullRom | Float32 128^3 | 25.756 ms | 12.366 ms | 6.468 ms | 4.479 ms | 21.222 ms | 10.728 ms | 5.840 ms | 3.386 ms | 184.735 μs | 124.952 μs |
| anterpolate! CatmullRom | Float32 256^3 | 287.710 ms | 154.925 ms | 84.862 ms | 57.750 ms | 169.256 ms | 89.493 ms | 45.583 ms | 24.099 ms | 1.415 ms | 2.787 ms |
| anterpolate! CatmullRom | Float32 512^3 | 2.630 s | 1.417 s | 879.999 ms | 674.157 ms | 2.889 s | 1.476 s | 802.783 ms | 434.243 ms | — | — |
| anterpolate! CatmullRom | Float32 64^3 | 2.911 ms | 1.671 ms | 1.041 ms | 745.017 μs | 2.443 ms | 1.381 ms | 879.059 μs | 614.126 μs | 67.410 μs | 43.870 μs |
| anterpolate! CatmullRom | Float64 128^3 | 27.696 ms | 13.247 ms | 6.733 ms | 4.030 ms | 22.181 ms | 11.649 ms | 6.427 ms | 3.790 ms | 243.323 μs | 147.481 μs |
| anterpolate! CatmullRom | Float64 256^3 | 322.349 ms | 178.081 ms | 107.719 ms | 87.273 ms | 263.137 ms | 132.533 ms | 69.462 ms | 37.498 ms | 2.567 ms | 4.537 ms |
| anterpolate! CatmullRom | Float64 512^3 | 2.951 s | 1.590 s | 912.666 ms | 748.200 ms | 3.144 s | 1.608 s | 851.861 ms | 509.342 ms | — | — |
| anterpolate! CatmullRom | Float64 64^3 | 3.013 ms | 1.689 ms | 1.071 ms | 783.159 μs | 2.464 ms | 1.441 ms | 950.350 μs | 679.426 μs | 93.148 μs | 50.991 μs |
| anterpolate! Lalescu(3,3) | Float32 128^3 | 175.110 ms | 88.522 ms | 44.675 ms | 24.868 ms | 154.364 ms | 77.776 ms | 39.387 ms | 21.066 ms | 1.153 ms | 883.438 μs |
| anterpolate! Lalescu(3,3) | Float32 256^3 | 1.634 s | 852.769 ms | 436.554 ms | 271.828 ms | 1.240 s | 624.394 ms | 313.869 ms | 157.899 ms | 9.810 ms | 14.890 ms |
| anterpolate! Lalescu(3,3) | Float32 512^3 | 13.925 s | 7.283 s | 4.032 s | 2.910 s | 11.758 s | 6.039 s | 3.180 s | 1.801 s | — | — |
| anterpolate! Lalescu(3,3) | Float32 64^3 | 21.184 ms | 11.596 ms | 7.110 ms | 4.890 ms | 19.211 ms | 10.356 ms | 6.348 ms | 4.279 ms | 337.157 μs | 246.732 μs |
| anterpolate! Lalescu(3,3) | Float64 128^3 | 180.009 ms | 90.612 ms | 45.510 ms | 25.405 ms | 155.293 ms | 78.374 ms | 39.824 ms | 21.447 ms | 1.586 ms | 932.499 μs |
| anterpolate! Lalescu(3,3) | Float64 256^3 | 1.756 s | 928.836 ms | 507.430 ms | 379.622 ms | 1.406 s | 696.345 ms | 358.268 ms | 181.987 ms | 17.698 ms | 24.195 ms |
| anterpolate! Lalescu(3,3) | Float64 512^3 | 15.200 s | 7.900 s | 4.337 s | 3.225 s | 18.985 s | 9.557 s | 5.053 s | 2.836 s | — | — |
| anterpolate! Lalescu(3,3) | Float64 64^3 | 21.759 ms | 11.717 ms | 7.201 ms | 5.110 ms | 19.277 ms | 10.446 ms | 6.430 ms | 4.344 ms | 511.547 μs | 278.502 μs |
| anterpolate! NUFFT | Float32 128^3 | 411.356 ms | 229.080 ms | 122.227 ms | 95.784 ms | 376.122 ms | 200.931 ms | 113.020 ms | 69.823 ms | 3.013 ms | 2.702 ms |
| anterpolate! NUFFT | Float32 256^3 | 4.229 s | 2.401 s | 1.478 s | 1.126 s | 3.765 s | 2.010 s | 1.116 s | 688.029 ms | 33.093 ms | 28.643 ms |
| anterpolate! NUFFT | Float32 512^3 | 39.107 s | 21.584 s | 12.695 s | 9.236 s | 31.177 s | 16.455 s | 9.101 s | 5.564 s | — | — |
| anterpolate! NUFFT | Float32 64^3 | 31.875 ms | 17.605 ms | 11.307 ms | 8.138 ms | 27.161 ms | 14.309 ms | 8.680 ms | 5.896 ms | 517.704 μs | 325.583 μs |
| anterpolate! NUFFT | Float64 128^3 | 535.549 ms | 308.286 ms | 214.999 ms | 178.365 ms | 429.868 ms | 240.693 ms | 147.187 ms | 107.575 ms | 9.565 ms | 6.580 ms |
| anterpolate! NUFFT | Float64 256^3 | 4.989 s | 2.865 s | 1.915 s | 1.534 s | 3.596 s | 2.032 s | 1.224 s | 873.858 ms | 71.742 ms | 58.555 ms |
| anterpolate! NUFFT | Float64 512^3 | 45.051 s | 25.253 s | 16.068 s | 12.706 s | 39.727 s | 21.772 s | 12.602 s | 8.210 s | — | — |
| anterpolate! NUFFT | Float64 64^3 | 37.138 ms | 22.056 ms | 14.408 ms | 11.002 ms | 33.287 ms | 17.827 ms | 10.622 ms | 7.356 ms | 946.997 μs | 710.416 μs |
| anterpolate! trilinear | Float32 128^3 | 3.964 ms | 1.971 ms | 1.112 ms | 744.393 μs | 4.274 ms | 2.305 ms | 1.246 ms | 734.618 μs | 52.090 μs | 24.960 μs |
| anterpolate! trilinear | Float32 256^3 | 62.706 ms | 35.555 ms | 22.635 ms | 17.192 ms | 43.410 ms | 22.738 ms | 12.068 ms | 6.668 ms | 304.980 μs | 678.516 μs |
| anterpolate! trilinear | Float32 512^3 | 550.184 ms | 317.090 ms | 221.758 ms | 176.659 ms | 545.717 ms | 281.788 ms | 155.584 ms | 86.938 ms | — | — |
| anterpolate! trilinear | Float32 64^3 | 406.626 μs | 260.555 μs | 183.888 μs | 139.043 μs | 345.593 μs | 216.652 μs | 145.281 μs | 107.221 μs | 35.478 μs | 12.980 μs |
| anterpolate! trilinear | Float64 128^3 | 4.397 ms | 2.307 ms | 1.356 ms | 947.035 μs | 6.137 ms | 3.257 ms | 1.785 ms | 1.060 ms | 63.394 μs | 38.631 μs |
| anterpolate! trilinear | Float64 256^3 | 70.000 ms | 42.217 ms | 29.841 ms | 24.553 ms | 60.749 ms | 31.013 ms | 17.618 ms | 9.970 ms | 680.954 μs | 1.052 ms |
| anterpolate! trilinear | Float64 512^3 | 596.800 ms | 352.029 ms | 232.093 ms | 201.287 ms | 571.788 ms | 301.085 ms | 165.167 ms | 102.462 ms | — | — |
| anterpolate! trilinear | Float64 64^3 | 449.476 μs | 284.373 μs | 205.973 μs | 168.676 μs | 354.724 μs | 221.592 μs | 148.902 μs | 113.181 μs | 45.292 μs | 19.910 μs |
| displace! 1-term | Float32 128^3 | 53.151 μs | 35.060 μs | 19.612 μs | 12.990 μs | 45.870 μs | 25.261 μs | 13.570 μs | 9.441 μs | 26.834 μs | 7.573 μs |
| displace! 1-term | Float32 256^3 | 427.423 μs | 262.995 μs | 133.983 μs | 72.861 μs | 371.814 μs | 188.352 μs | 95.971 μs | 52.851 μs | 40.207 μs | 18.150 μs |
| displace! 1-term | Float32 512^3 | 5.600 ms | 4.822 ms | 4.418 ms | 4.084 ms | 3.283 ms | 1.804 ms | 948.849 μs | 874.309 μs | — | — |
| displace! 1-term | Float32 64^3 | 6.604 μs | 7.141 μs | 5.367 μs | 5.623 μs | 5.715 μs | 4.836 μs | 3.584 μs | 4.039 μs | 24.534 μs | 6.295 μs |
| displace! 1-term | Float64 128^3 | 64.127 μs | 36.350 μs | 19.806 μs | 14.226 μs | 48.061 μs | 28.650 μs | 14.411 μs | 10.720 μs | 25.494 μs | 7.860 μs |
| displace! 1-term | Float64 256^3 | 764.605 μs | 557.157 μs | 337.018 μs | 214.903 μs | 394.693 μs | 194.212 μs | 99.941 μs | 53.490 μs | 45.849 μs | 19.580 μs |
| displace! 1-term | Float64 512^3 | 10.839 ms | 10.408 ms | 9.634 ms | 9.106 ms | 4.891 ms | 3.798 ms | 3.958 ms | 4.007 ms | — | — |
| displace! 1-term | Float64 64^3 | 6.901 μs | 7.084 μs | 5.443 μs | 6.605 μs | 5.893 μs | 4.932 μs | 3.611 μs | 3.841 μs | 22.251 μs | 6.400 μs |
| displace! 3-term torus | Float32 128^3 | 852.590 μs | 479.035 μs | 253.276 μs | 159.987 μs | 708.857 μs | 405.354 μs | 212.642 μs | 119.881 μs | 62.827 μs | 23.011 μs |
| displace! 3-term torus | Float32 256^3 | 6.885 ms | 3.740 ms | 1.933 ms | 1.226 ms | 5.691 ms | 3.120 ms | 1.574 ms | 811.739 μs | 64.206 μs | 30.780 μs |
| displace! 3-term torus | Float32 512^3 | 56.461 ms | 41.604 ms | 15.814 ms | 9.884 ms | 45.440 ms | 24.736 ms | 12.485 ms | 6.378 ms | — | — |
| displace! 3-term torus | Float32 64^3 | 105.769 μs | 105.837 μs | 105.729 μs | 106.055 μs | 88.011 μs | 88.281 μs | 88.081 μs | 88.091 μs | 58.142 μs | 22.060 μs |
| displace! 3-term torus | Float64 128^3 | 863.284 μs | 481.175 μs | 254.980 μs | 160.632 μs | 735.877 μs | 429.754 μs | 219.893 μs | 124.861 μs | 66.448 μs | 26.930 μs |
| displace! 3-term torus | Float64 256^3 | 6.860 ms | 3.731 ms | 1.955 ms | 1.396 ms | 5.927 ms | 3.289 ms | 1.665 ms | 875.700 μs | 103.904 μs | 107.131 μs |
| displace! 3-term torus | Float64 512^3 | 54.965 ms | 30.117 ms | 18.989 ms | 16.959 ms | 47.423 ms | 25.894 ms | 13.847 ms | 8.937 ms | — | — |
| displace! 3-term torus | Float64 64^3 | 106.364 μs | 106.443 μs | 105.912 μs | 106.311 μs | 91.591 μs | 91.651 μs | 91.611 μs | 91.511 μs | 59.861 μs | 24.391 μs |
| displace! 3-term | Float32 128^3 | 163.610 μs | 103.117 μs | 56.044 μs | 34.323 μs | 93.991 μs | 79.141 μs | 41.420 μs | 24.281 μs | 25.445 μs | 8.670 μs |
| displace! 3-term | Float32 256^3 | 1.424 ms | 838.577 μs | 444.136 μs | 239.775 μs | 747.397 μs | 615.417 μs | 311.334 μs | 163.582 μs | 45.951 μs | 22.580 μs |
| displace! 3-term | Float32 512^3 | 11.803 ms | 8.742 ms | 8.480 ms | 7.664 ms | 7.705 ms | 5.289 ms | 3.413 ms | 3.425 ms | — | — |
| displace! 3-term | Float32 64^3 | 20.474 μs | 17.564 μs | 12.311 μs | 10.846 μs | 11.550 μs | 12.780 μs | 8.317 μs | 7.400 μs | 24.837 μs | 6.955 μs |
| displace! 3-term | Float64 128^3 | 163.964 μs | 107.052 μs | 56.588 μs | 35.261 μs | 94.681 μs | 81.691 μs | 43.911 μs | 24.540 μs | 33.122 μs | 9.780 μs |
| displace! 3-term | Float64 256^3 | 1.954 ms | 1.643 ms | 1.372 ms | 1.223 ms | 766.897 μs | 643.967 μs | 335.433 μs | 174.612 μs | 64.729 μs | 68.240 μs |
| displace! 3-term | Float64 512^3 | 19.022 ms | 18.480 ms | 16.932 ms | 15.893 ms | 12.851 ms | 9.430 ms | 8.952 ms | 8.853 ms | — | — |
| displace! 3-term | Float64 64^3 | 20.483 μs | 17.917 μs | 12.085 μs | 10.436 μs | 11.650 μs | 13.540 μs | 8.640 μs | 8.950 μs | 26.669 μs | 7.423 μs |
| interpolate! CatmullRom ordered | Float32 128^3 | 3.978 ms | 2.025 ms | 1.016 ms | 563.027 μs | 2.845 ms | 1.467 ms | 720.338 μs | 384.783 μs | 62.646 μs | 28.541 μs |
| interpolate! CatmullRom ordered | Float32 256^3 | 45.036 ms | 22.584 ms | 11.896 ms | 6.500 ms | 25.027 ms | 13.254 ms | 6.702 ms | 3.495 ms | 264.681 μs | 152.301 μs |
| interpolate! CatmullRom ordered | Float32 512^3 | 771.718 ms | 394.482 ms | 208.103 ms | 122.775 ms | 557.639 ms | 301.577 ms | 161.982 ms | 81.958 ms | — | — |
| interpolate! CatmullRom ordered | Float32 64^3 | 434.192 μs | 238.193 μs | 144.776 μs | 101.942 μs | 297.393 μs | 160.522 μs | 96.881 μs | 66.261 μs | 34.788 μs | 15.070 μs |
| interpolate! CatmullRom ordered | Float64 128^3 | 4.557 ms | 2.327 ms | 1.169 ms | 626.204 μs | 3.219 ms | 1.576 ms | 797.638 μs | 421.154 μs | 107.788 μs | 79.401 μs |
| interpolate! CatmullRom ordered | Float64 256^3 | 73.457 ms | 39.162 ms | 20.571 ms | 11.320 ms | 41.479 ms | 21.305 ms | 12.100 ms | 7.416 ms | 713.146 μs | 485.405 μs |
| interpolate! CatmullRom ordered | Float64 512^3 | 963.407 ms | 503.214 ms | 296.321 ms | 190.177 ms | 857.475 ms | 456.771 ms | 255.096 ms | 147.387 ms | — | — |
| interpolate! CatmullRom ordered | Float64 64^3 | 449.682 μs | 246.581 μs | 151.595 μs | 106.420 μs | 324.083 μs | 174.962 μs | 105.551 μs | 70.360 μs | 67.195 μs | 42.190 μs |
| interpolate! CatmullRom vector ordered | Float32 128^3 | 9.700 ms | 5.144 ms | 2.571 ms | 1.390 ms | 6.127 ms | 3.094 ms | 1.559 ms | 826.218 μs | 116.373 μs | 62.870 μs |
| interpolate! CatmullRom vector ordered | Float32 256^3 | 111.773 ms | 76.771 ms | 28.811 ms | 15.811 ms | 86.235 ms | 44.041 ms | 23.290 ms | 13.098 ms | 973.127 μs | 365.013 μs |
| interpolate! CatmullRom vector ordered | Float32 512^3 | 1.940 s | 1.090 s | 698.464 ms | 472.691 ms | 1.176 s | 647.718 ms | 345.041 ms | 182.558 ms | — | — |
| interpolate! CatmullRom vector ordered | Float32 64^3 | 1.017 ms | 554.127 μs | 332.848 μs | 238.215 μs | 684.527 μs | 362.524 μs | 221.673 μs | 148.131 μs | 59.070 μs | 27.610 μs |
| interpolate! CatmullRom vector ordered | Float64 128^3 | 12.268 ms | 6.518 ms | 3.541 ms | 2.389 ms | 6.795 ms | 3.426 ms | 1.767 ms | 946.989 μs | 240.450 μs | 174.672 μs |
| interpolate! CatmullRom vector ordered | Float64 256^3 | 188.781 ms | 94.515 ms | 50.188 ms | 34.708 ms | 168.474 ms | 86.145 ms | 51.119 ms | 29.089 ms | 1.844 ms | 1.184 ms |
| interpolate! CatmullRom vector ordered | Float64 512^3 | 2.292 s | 1.244 s | 748.016 ms | 517.239 ms | 1.758 s | 940.654 ms | 505.046 ms | 276.232 ms | — | — |
| interpolate! CatmullRom vector ordered | Float64 64^3 | 1.089 ms | 595.344 μs | 364.686 μs | 250.088 μs | 781.838 μs | 419.975 μs | 251.272 μs | 170.072 μs | 114.922 μs | 87.201 μs |
| interpolate! CatmullRom vector | Float32 128^3 | 22.551 ms | 12.099 ms | 6.750 ms | 3.667 ms | 7.713 ms | 3.927 ms | 1.976 ms | 1.065 ms | 277.350 μs | 202.972 μs |
| interpolate! CatmullRom vector | Float32 256^3 | 407.357 ms | 241.772 ms | 169.663 ms | 97.564 ms | 285.972 ms | 151.780 ms | 80.020 ms | 43.171 ms | 3.909 ms | 3.275 ms |
| interpolate! CatmullRom vector | Float32 512^3 | 3.208 s | 2.025 s | 1.423 s | 867.578 ms | 2.993 s | 1.533 s | 832.057 ms | 481.181 ms | — | — |
| interpolate! CatmullRom vector | Float32 64^3 | 1.182 ms | 628.861 μs | 389.213 μs | 277.421 μs | 839.498 μs | 438.225 μs | 268.003 μs | 181.102 μs | 68.320 μs | 76.081 μs |
| interpolate! CatmullRom vector | Float64 128^3 | 39.020 ms | 23.656 ms | 14.998 ms | 9.582 ms | 9.149 ms | 4.641 ms | 2.540 ms | 1.594 ms | 349.816 μs | 244.332 μs |
| interpolate! CatmullRom vector | Float64 256^3 | 417.022 ms | 253.550 ms | 166.543 ms | 104.000 ms | 350.609 ms | 181.683 ms | 100.235 ms | 59.545 ms | 6.321 ms | 4.769 ms |
| interpolate! CatmullRom vector | Float64 512^3 | 3.734 s | 2.115 s | 1.419 s | 914.247 ms | 3.354 s | 1.724 s | 940.566 ms | 565.180 ms | — | — |
| interpolate! CatmullRom vector | Float64 64^3 | 1.245 ms | 653.658 μs | 403.137 μs | 282.359 μs | 876.568 μs | 470.195 μs | 281.612 μs | 192.362 μs | 127.768 μs | 90.320 μs |
| interpolate! CatmullRom | Float32 128^3 | 4.286 ms | 2.207 ms | 1.156 ms | 626.590 μs | 3.197 ms | 1.612 ms | 812.888 μs | 436.094 μs | 109.047 μs | 75.171 μs |
| interpolate! CatmullRom | Float32 256^3 | 122.386 ms | 75.380 ms | 45.126 ms | 27.806 ms | 31.610 ms | 19.490 ms | 9.512 ms | 4.909 ms | 815.020 μs | 768.527 μs |
| interpolate! CatmullRom | Float32 512^3 | 1.175 s | 705.954 ms | 475.355 ms | 295.824 ms | 1.132 s | 594.863 ms | 337.370 ms | 195.092 ms | — | — |
| interpolate! CatmullRom | Float32 64^3 | 460.844 μs | 252.906 μs | 154.673 μs | 108.709 μs | 323.203 μs | 175.632 μs | 105.981 μs | 72.590 μs | 44.438 μs | 29.460 μs |
| interpolate! CatmullRom | Float64 128^3 | 6.201 ms | 3.041 ms | 1.490 ms | 839.866 μs | 3.413 ms | 1.752 ms | 914.479 μs | 525.595 μs | 122.843 μs | 102.741 μs |
| interpolate! CatmullRom | Float64 256^3 | 143.689 ms | 91.436 ms | 53.551 ms | 36.410 ms | 105.578 ms | 53.655 ms | 28.399 ms | 15.229 ms | 1.545 ms | 1.485 ms |
| interpolate! CatmullRom | Float64 512^3 | 1.274 s | 746.829 ms | 495.176 ms | 330.954 ms | 1.497 s | 774.276 ms | 425.414 ms | 267.711 ms | — | — |
| interpolate! CatmullRom | Float64 64^3 | 498.063 μs | 271.026 μs | 167.332 μs | 117.412 μs | 381.533 μs | 205.822 μs | 123.972 μs | 86.260 μs | 64.124 μs | 43.470 μs |
| interpolate! Lalescu(3,3) | Float32 128^3 | 22.677 ms | 11.577 ms | 5.894 ms | 3.783 ms | 17.272 ms | 8.593 ms | 4.463 ms | 2.714 ms | 324.459 μs | 229.562 μs |
| interpolate! Lalescu(3,3) | Float32 256^3 | 595.093 ms | 376.466 ms | 226.156 ms | 145.525 ms | 145.808 ms | 97.995 ms | 50.658 ms | 28.290 ms | 2.408 ms | 3.522 ms |
| interpolate! Lalescu(3,3) | Float32 512^3 | 5.787 s | 3.537 s | 2.479 s | 1.570 s | 4.498 s | 2.415 s | 1.494 s | 1.013 s | — | — |
| interpolate! Lalescu(3,3) | Float32 64^3 | 2.497 ms | 1.358 ms | 815.938 μs | 566.002 μs | 2.047 ms | 1.097 ms | 641.597 μs | 429.045 μs | 81.689 μs | 75.421 μs |
| interpolate! Lalescu(3,3) | Float64 128^3 | 32.586 ms | 15.854 ms | 7.936 ms | 4.587 ms | 17.279 ms | 8.826 ms | 4.751 ms | 3.130 ms | 396.096 μs | 429.004 μs |
| interpolate! Lalescu(3,3) | Float64 256^3 | 756.298 ms | 487.396 ms | 296.947 ms | 201.500 ms | 441.447 ms | 226.598 ms | 116.572 ms | 71.404 ms | 4.802 ms | 8.514 ms |
| interpolate! Lalescu(3,3) | Float64 512^3 | 6.381 s | 3.855 s | 2.681 s | 1.728 s | 6.022 s | 3.069 s | 1.604 s | 976.673 ms | — | — |
| interpolate! Lalescu(3,3) | Float64 64^3 | 2.797 ms | 1.508 ms | 918.995 μs | 640.034 μs | 2.130 ms | 1.123 ms | 676.986 μs | 449.664 μs | 213.473 μs | 141.041 μs |
| interpolate! NUFFT | Float32 128^3 | 325.747 ms | 186.369 ms | 123.152 ms | 104.662 ms | 262.810 ms | 144.028 ms | 85.630 ms | 58.897 ms | 1.986 ms | 1.928 ms |
| interpolate! NUFFT | Float32 256^3 | 3.500 s | 2.069 s | 1.370 s | 917.332 ms | 2.983 s | 1.619 s | 937.998 ms | 617.991 ms | 25.730 ms | 17.669 ms |
| interpolate! NUFFT | Float32 512^3 | 32.032 s | 17.990 s | 11.415 s | 8.316 s | 24.675 s | 13.209 s | 7.696 s | 4.969 s | — | — |
| interpolate! NUFFT | Float32 64^3 | 16.705 ms | 10.169 ms | 6.797 ms | 5.219 ms | 12.111 ms | 6.534 ms | 3.857 ms | 2.456 ms | 427.513 μs | 295.703 μs |
| interpolate! NUFFT | Float64 128^3 | 416.973 ms | 248.266 ms | 195.739 ms | 162.003 ms | 227.731 ms | 138.844 ms | 95.756 ms | 78.072 ms | 8.654 ms | 5.525 ms |
| interpolate! NUFFT | Float64 256^3 | 3.900 s | 2.348 s | 1.695 s | 1.394 s | 2.000 s | 1.224 s | 851.762 ms | 705.235 ms | 59.088 ms | 48.026 ms |
| interpolate! NUFFT | Float64 512^3 | 35.191 s | 20.830 s | 14.825 s | 13.183 s | 24.906 s | 14.094 s | 8.733 s | 9.442 s | — | — |
| interpolate! NUFFT | Float64 64^3 | 22.099 ms | 14.244 ms | 10.719 ms | 8.957 ms | 22.641 ms | 12.260 ms | 7.393 ms | 4.788 ms | 828.686 μs | 784.587 μs |
| interpolate! trilinear | Float32 128^3 | 1.342 ms | 694.969 μs | 353.430 μs | 197.181 μs | 1.108 ms | 553.136 μs | 281.113 μs | 152.871 μs | 31.805 μs | 15.720 μs |
| interpolate! trilinear | Float32 256^3 | 38.320 ms | 20.467 ms | 12.097 ms | 7.543 ms | 10.545 ms | 6.317 ms | 3.200 ms | 1.566 ms | 117.725 μs | 172.172 μs |
| interpolate! trilinear | Float32 512^3 | 335.141 ms | 185.452 ms | 110.428 ms | 76.718 ms | 415.424 ms | 210.850 ms | 109.939 ms | 57.482 ms | — | — |
| interpolate! trilinear | Float32 64^3 | 167.608 μs | 93.351 μs | 58.430 μs | 42.009 μs | 122.821 μs | 66.481 μs | 38.920 μs | 27.860 μs | 29.064 μs | 10.060 μs |
| interpolate! trilinear | Float64 128^3 | 1.952 ms | 875.651 μs | 447.531 μs | 264.354 μs | 1.073 ms | 544.576 μs | 285.473 μs | 151.741 μs | 46.186 μs | 26.310 μs |
| interpolate! trilinear | Float64 256^3 | 43.459 ms | 25.376 ms | 15.518 ms | 10.096 ms | 33.163 ms | 15.233 ms | 7.771 ms | 3.942 ms | 241.819 μs | 298.463 μs |
| interpolate! trilinear | Float64 512^3 | 372.865 ms | 218.219 ms | 135.777 ms | 87.993 ms | 425.905 ms | 215.163 ms | 111.942 ms | 62.444 ms | — | — |
| interpolate! trilinear | Float64 64^3 | 167.681 μs | 91.490 μs | 58.950 μs | 42.757 μs | 128.781 μs | 70.081 μs | 40.450 μs | 27.160 μs | 37.755 μs | 16.250 μs |
| point_traversal_order | Float32 128^3 | 1.020 ms | 1.193 ms | 864.955 μs | 592.713 μs | 676.626 μs | 413.745 μs | 291.743 μs | 219.902 μs | 310.671 μs | 91.741 μs |
| point_traversal_order | Float32 256^3 | 12.495 ms | 8.452 ms | 5.744 ms | 3.741 ms | 5.787 ms | 2.975 ms | 1.621 ms | 1.030 ms | 309.371 μs | 158.952 μs |
| point_traversal_order | Float32 512^3 | 136.475 ms | 74.450 ms | 42.791 ms | 26.434 ms | 62.859 ms | 30.969 ms | 16.891 ms | 10.665 ms | — | — |
| point_traversal_order | Float32 64^3 | 109.698 μs | 153.161 μs | 164.080 μs | 148.075 μs | 86.071 μs | 89.961 μs | 83.981 μs | 88.591 μs | 299.185 μs | 85.430 μs |
| point_traversal_order | Float64 128^3 | 1.025 ms | 1.097 ms | 856.873 μs | 664.379 μs | 683.407 μs | 428.994 μs | 293.163 μs | 228.183 μs | 265.348 μs | 90.471 μs |
| point_traversal_order | Float64 256^3 | 12.557 ms | 8.727 ms | 5.832 ms | 3.738 ms | 6.260 ms | 3.175 ms | 1.854 ms | 1.088 ms | 388.804 μs | 182.312 μs |
| point_traversal_order | Float64 512^3 | 138.042 ms | 77.288 ms | 43.803 ms | 27.682 ms | 64.015 ms | 36.454 ms | 19.286 ms | 13.641 ms | — | — |
| point_traversal_order | Float64 64^3 | 109.535 μs | 135.740 μs | 167.776 μs | 145.094 μs | 86.391 μs | 84.691 μs | 88.231 μs | 88.571 μs | 243.054 μs | 82.911 μs |
| point_traversal_order! | Float32 128^3 | 1.006 ms | 1.279 ms | 868.902 μs | 580.423 μs | — | — | — | — | 244.784 μs | — |
| point_traversal_order! | Float32 256^3 | 12.134 ms | 8.324 ms | 5.523 ms | 3.485 ms | — | — | — | — | 326.273 μs | — |
| point_traversal_order! | Float32 512^3 | 136.332 ms | 76.806 ms | 42.201 ms | 26.348 ms | — | — | — | — | — | — |
| point_traversal_order! | Float32 64^3 | 107.345 μs | 170.873 μs | 169.672 μs | 143.930 μs | — | — | — | — | 236.699 μs | — |
| point_traversal_order! | Float64 128^3 | 1.004 ms | 1.195 ms | 852.217 μs | 579.803 μs | — | — | — | — | 263.227 μs | — |
| point_traversal_order! | Float64 256^3 | 12.160 ms | 8.361 ms | 5.475 ms | 3.511 ms | — | — | — | — | 330.104 μs | — |
| point_traversal_order! | Float64 512^3 | 144.037 ms | 75.128 ms | 45.112 ms | 28.136 ms | — | — | — | — | — | — |
| point_traversal_order! | Float64 64^3 | 108.167 μs | 169.954 μs | 167.062 μs | 141.172 μs | — | — | — | — | 218.671 μs | — |
| wrap! | Float32 128^3 | 517.262 μs | 343.736 μs | 180.513 μs | 117.373 μs | 442.334 μs | 273.273 μs | 139.282 μs | 83.541 μs | 33.641 μs | 10.730 μs |
| wrap! | Float32 256^3 | 4.186 ms | 2.712 ms | 1.395 ms | 925.388 μs | 3.544 ms | 2.141 ms | 1.078 ms | 554.366 μs | 43.678 μs | 14.390 μs |
| wrap! | Float32 512^3 | 33.235 ms | 21.476 ms | 12.460 ms | 7.458 ms | 28.372 ms | 17.075 ms | 8.608 ms | 4.618 ms | — | — |
| wrap! | Float32 64^3 | 64.287 μs | 64.316 μs | 64.268 μs | 66.455 μs | 55.290 μs | 55.310 μs | 55.260 μs | 55.290 μs | 34.079 μs | 10.661 μs |
| wrap! | Float64 128^3 | 576.701 μs | 367.896 μs | 192.917 μs | 125.535 μs | 441.354 μs | 281.393 μs | 142.342 μs | 84.211 μs | 36.614 μs | 15.920 μs |
| wrap! | Float64 256^3 | 4.569 ms | 2.938 ms | 1.518 ms | 946.812 μs | 3.535 ms | 2.191 ms | 1.105 ms | 569.786 μs | 51.335 μs | 59.021 μs |
| wrap! | Float64 512^3 | 36.531 ms | 23.147 ms | 12.903 ms | 8.328 ms | 28.315 ms | 17.470 ms | 8.859 ms | 4.573 ms | — | — |
| wrap! | Float64 64^3 | 70.283 μs | 70.297 μs | 70.230 μs | 70.289 μs | 55.151 μs | 55.150 μs | 55.180 μs | 56.350 μs | 35.045 μs | 12.250 μs |

## reductions

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| co-spectrum vec.vec | Float32 128^3 | 8.085 ms | 7.072 ms | 8.665 ms | 7.738 ms | 6.955 ms | 5.053 ms | 5.864 ms | 6.421 ms | 326.361 μs | 175.002 μs |
| co-spectrum vec.vec | Float32 256^3 | 64.184 ms | 48.351 ms | 47.165 ms | 44.238 ms | 55.586 ms | 36.310 ms | 31.485 ms | 31.862 ms | 945.593 μs | 838.338 μs |
| co-spectrum vec.vec | Float32 512^3 | 518.943 ms | 375.467 ms | 267.661 ms | 234.091 ms | 447.260 ms | 266.297 ms | 190.143 ms | 154.457 ms | — | — |
| co-spectrum vec.vec | Float32 64^3 | 1.044 ms | 1.390 ms | 1.591 ms | 1.633 ms | 905.729 μs | 934.539 μs | 1.207 ms | 1.255 ms | 222.869 μs | 71.841 μs |
| co-spectrum vec.vec | Float64 128^3 | 8.403 ms | 6.767 ms | 6.208 ms | 5.998 ms | 7.293 ms | 5.117 ms | 4.571 ms | 4.438 ms | 17.141 ms | 258.092 μs |
| co-spectrum vec.vec | Float64 256^3 | 67.206 ms | 49.072 ms | 37.143 ms | 32.504 ms | 58.738 ms | 37.545 ms | 27.326 ms | 22.699 ms | 56.217 ms | 1.158 ms |
| co-spectrum vec.vec | Float64 512^3 | 562.298 ms | 366.443 ms | 239.354 ms | 193.400 ms | 476.161 ms | 282.807 ms | 172.999 ms | 129.276 ms | — | — |
| co-spectrum vec.vec | Float64 64^3 | 1.064 ms | 898.933 μs | 1.070 ms | 985.536 μs | 941.000 μs | 746.947 μs | 860.368 μs | 937.539 μs | 6.988 ms | 77.551 μs |
| cov vector | Float32 128^3 | 2.264 ms | 1.215 ms | 631.475 μs | 339.757 μs | 1.129 ms | 579.296 μs | 298.463 μs | 180.212 μs | 589.833 μs | 146.661 μs |
| cov vector | Float32 256^3 | 20.935 ms | 13.623 ms | 11.094 ms | 10.131 ms | 12.767 ms | 8.212 ms | 5.247 ms | 4.682 ms | 2.727 ms | 830.578 μs |
| cov vector | Float32 512^3 | 171.923 ms | 115.540 ms | 94.703 ms | 89.251 ms | 94.777 ms | 63.954 ms | 55.212 ms | 55.272 ms | — | — |
| cov vector | Float32 64^3 | 252.520 μs | 140.130 μs | 77.735 μs | 63.666 μs | 141.221 μs | 79.681 μs | 45.721 μs | 34.680 μs | 328.488 μs | 85.921 μs |
| cov vector | Float64 128^3 | 4.002 ms | 2.736 ms | 2.116 ms | 1.727 ms | 2.213 ms | 1.122 ms | 570.636 μs | 316.384 μs | 838.856 μs | 193.531 μs |
| cov vector | Float64 256^3 | 34.433 ms | 26.428 ms | 23.077 ms | 21.412 ms | 25.423 ms | 15.473 ms | 12.421 ms | 12.522 ms | 4.671 ms | 1.104 ms |
| cov vector | Float64 512^3 | 277.888 ms | 214.724 ms | 189.691 ms | 179.381 ms | 185.942 ms | 128.569 ms | 111.300 ms | 111.557 ms | — | — |
| cov vector | Float64 64^3 | 350.559 μs | 191.108 μs | 105.325 μs | 72.901 μs | 274.242 μs | 146.852 μs | 81.260 μs | 54.591 μs | 368.135 μs | 97.221 μs |
| cross-correlation vec.vec | Float32 128^3 | 37.609 ms | 31.104 ms | 33.338 ms | 33.200 ms | 32.907 ms | 24.414 ms | 22.285 ms | 21.375 ms | 762.275 μs | 563.865 μs |
| cross-correlation vec.vec | Float32 256^3 | 415.659 ms | 272.092 ms | 231.945 ms | 222.598 ms | 303.291 ms | 194.114 ms | 157.646 ms | 161.325 ms | 9.860 ms | 6.518 ms |
| cross-correlation vec.vec | Float32 512^3 | 3.530 s | 2.311 s | 1.877 s | 1.663 s | 2.935 s | 1.859 s | 1.394 s | 1.158 s | — | — |
| cross-correlation vec.vec | Float32 64^3 | 4.607 ms | 5.071 ms | 5.530 ms | 5.639 ms | 3.841 ms | 3.546 ms | 3.853 ms | 3.693 ms | 237.185 μs | 154.611 μs |
| cross-correlation vec.vec | Float64 128^3 | 45.587 ms | 50.223 ms | 39.303 ms | 36.501 ms | 40.003 ms | 38.574 ms | 25.627 ms | 24.757 ms | 37.056 ms | 1.938 ms |
| cross-correlation vec.vec | Float64 256^3 | 577.413 ms | 432.232 ms | 364.778 ms | 341.609 ms | 502.430 ms | 344.836 ms | 255.767 ms | 252.309 ms | 133.731 ms | 15.074 ms |
| cross-correlation vec.vec | Float64 512^3 | 5.581 s | 3.716 s | 2.872 s | 2.569 s | 4.475 s | 2.917 s | 2.091 s | 1.782 s | — | — |
| cross-correlation vec.vec | Float64 64^3 | 5.514 ms | 5.178 ms | 5.538 ms | 5.414 ms | 4.293 ms | 3.469 ms | 3.461 ms | 3.356 ms | 12.704 ms | 260.292 μs |
| inner spectral | Float32 128^3 | 2.504 ms | 1.786 ms | 1.389 ms | 1.201 ms | 1.434 ms | 808.088 μs | 494.375 μs | 364.304 μs | 206.150 μs | 120.061 μs |
| inner spectral | Float32 256^3 | 21.795 ms | 16.376 ms | 14.809 ms | 13.845 ms | 12.720 ms | 8.072 ms | 7.086 ms | 7.107 ms | 712.198 μs | 624.566 μs |
| inner spectral | Float32 512^3 | 165.226 ms | 129.349 ms | 112.310 ms | 105.994 ms | 106.804 ms | 79.869 ms | 69.979 ms | 70.829 ms | — | — |
| inner spectral | Float32 64^3 | 304.653 μs | 196.801 μs | 141.444 μs | 115.136 μs | 210.982 μs | 121.861 μs | 82.770 μs | 76.781 μs | 197.799 μs | 73.561 μs |
| inner spectral | Float64 128^3 | 4.361 ms | 3.484 ms | 3.012 ms | 2.936 ms | 1.880 ms | 1.088 ms | 722.667 μs | 601.616 μs | 253.212 μs | 200.782 μs |
| inner spectral | Float64 256^3 | 35.040 ms | 29.944 ms | 27.508 ms | 26.356 ms | 18.732 ms | 15.904 ms | 15.603 ms | 15.238 ms | 1.178 ms | 1.112 ms |
| inner spectral | Float64 512^3 | 269.877 ms | 226.513 ms | 211.059 ms | 199.729 ms | 137.901 ms | 132.354 ms | 126.422 ms | 127.880 ms | — | — |
| inner spectral | Float64 64^3 | 318.278 μs | 207.007 μs | 150.665 μs | 129.363 μs | 225.993 μs | 134.421 μs | 90.910 μs | 85.080 μs | 201.633 μs | 80.650 μs |
| inner vec.vec | Float32 128^3 | 1.183 ms | 986.312 μs | 808.568 μs | 711.094 μs | 388.584 μs | 195.622 μs | 100.441 μs | 71.860 μs | 49.570 μs | 30.500 μs |
| inner vec.vec | Float32 256^3 | 13.199 ms | 12.158 ms | 11.339 ms | 10.763 ms | 7.434 ms | 6.470 ms | 5.782 ms | 5.914 ms | 487.189 μs | 489.195 μs |
| inner vec.vec | Float32 512^3 | 106.913 ms | 100.014 ms | 95.675 ms | 89.716 ms | 65.750 ms | 58.003 ms | 55.295 ms | 55.838 ms | — | — |
| inner vec.vec | Float32 64^3 | 69.367 μs | 38.626 μs | 20.133 μs | 13.577 μs | 46.241 μs | 25.741 μs | 14.620 μs | 11.330 μs | 51.068 μs | 12.970 μs |
| inner vec.vec | Float64 128^3 | 2.944 ms | 2.567 ms | 2.283 ms | 2.141 ms | 1.157 ms | 644.167 μs | 325.423 μs | 239.522 μs | 90.936 μs | 134.851 μs |
| inner vec.vec | Float64 256^3 | 26.374 ms | 24.722 ms | 23.378 ms | 21.747 ms | 15.251 ms | 13.960 ms | 13.219 ms | 13.173 ms | 932.844 μs | 963.440 μs |
| inner vec.vec | Float64 512^3 | 206.188 ms | 197.179 ms | 188.901 ms | 177.967 ms | 125.692 ms | 114.536 ms | 112.479 ms | 112.441 ms | — | — |
| inner vec.vec | Float64 64^3 | 140.557 μs | 75.560 μs | 39.574 μs | 25.774 μs | 87.721 μs | 46.370 μs | 25.580 μs | 17.640 μs | 45.467 μs | 18.460 μs |
| integral scalar | Float32 128^3 | 109.414 μs | 62.463 μs | 30.521 μs | 20.090 μs | 61.371 μs | 33.681 μs | 20.921 μs | 12.950 μs | 133.850 μs | 31.680 μs |
| integral scalar | Float32 256^3 | 2.389 ms | 1.617 ms | 1.279 ms | 1.187 ms | 549.207 μs | 275.203 μs | 163.622 μs | 99.021 μs | 599.569 μs | 175.422 μs |
| integral scalar | Float32 512^3 | 20.554 ms | 16.135 ms | 14.842 ms | 14.378 ms | 10.766 ms | 9.397 ms | 9.028 ms | 8.864 ms | — | — |
| integral scalar | Float32 64^3 | 10.298 μs | 7.002 μs | 5.361 μs | 5.864 μs | 6.918 μs | 4.880 μs | 4.120 μs | 5.242 μs | 79.017 μs | 17.950 μs |
| integral scalar | Float64 128^3 | 226.462 μs | 125.840 μs | 67.042 μs | 36.952 μs | 121.721 μs | 63.361 μs | 36.680 μs | 23.351 μs | 147.500 μs | 32.580 μs |
| integral scalar | Float64 256^3 | 4.349 ms | 3.617 ms | 3.263 ms | 3.035 ms | 1.632 ms | 1.114 ms | 812.009 μs | 963.730 μs | 736.276 μs | 192.012 μs |
| integral scalar | Float64 512^3 | 37.554 ms | 32.217 ms | 30.200 ms | 28.704 ms | 20.531 ms | 18.597 ms | 18.159 ms | 18.072 ms | — | — |
| integral scalar | Float64 64^3 | 25.921 μs | 13.094 μs | 8.029 μs | 7.944 μs | 14.920 μs | 7.900 μs | 5.938 μs | 5.830 μs | 79.599 μs | 19.330 μs |
| integral spectral vec | Float32 128^3 | 66.189 ns | 67.435 ns | 67.186 ns | 67.414 ns | 71.240 ns | 69.673 ns | 69.315 ns | 71.692 ns | 85.049 μs | 12.780 μs |
| integral spectral vec | Float32 256^3 | 66.410 ns | 67.491 ns | 71.998 ns | 67.375 ns | 71.651 ns | 71.067 ns | 70.401 ns | 70.257 ns | 75.956 μs | 12.620 μs |
| integral spectral vec | Float32 512^3 | 66.622 ns | 68.094 ns | 67.989 ns | 68.387 ns | 72.030 ns | 72.863 ns | 73.720 ns | 69.192 ns | — | — |
| integral spectral vec | Float32 64^3 | 66.576 ns | 67.220 ns | 67.090 ns | 67.242 ns | 73.121 ns | 70.669 ns | 69.489 ns | 74.995 ns | 80.990 μs | 13.000 μs |
| integral spectral vec | Float64 128^3 | 67.820 ns | 67.842 ns | 69.251 ns | 69.597 ns | 74.637 ns | 73.351 ns | 72.016 ns | 79.590 ns | 81.003 μs | 13.131 μs |
| integral spectral vec | Float64 256^3 | 68.036 ns | 69.177 ns | 70.275 ns | 69.669 ns | 77.311 ns | 76.466 ns | 73.555 ns | 73.921 ns | 81.676 μs | 13.160 μs |
| integral spectral vec | Float64 512^3 | 68.668 ns | 68.451 ns | 70.606 ns | 70.166 ns | 78.399 ns | 78.705 ns | 78.495 ns | 77.668 ns | — | — |
| integral spectral vec | Float64 64^3 | 67.957 ns | 68.219 ns | 69.090 ns | 68.496 ns | 76.575 ns | 75.463 ns | 74.302 ns | 74.814 ns | 83.543 μs | 12.800 μs |
| l2norm vec | Float32 128^3 | 595.688 μs | 349.452 μs | 187.633 μs | 90.543 μs | 249.532 μs | 129.191 μs | 71.291 μs | 39.721 μs | 47.923 μs | 19.980 μs |
| l2norm vec | Float32 256^3 | 7.519 ms | 5.911 ms | 5.434 ms | 5.034 ms | 4.108 ms | 2.870 ms | 1.948 ms | 2.010 ms | 261.833 μs | 258.592 μs |
| l2norm vec | Float32 512^3 | 61.152 ms | 49.387 ms | 46.089 ms | 44.710 ms | 41.560 ms | 30.681 ms | 26.714 ms | 27.026 ms | — | — |
| l2norm vec | Float32 64^3 | 49.590 μs | 27.440 μs | 15.342 μs | 12.585 μs | 31.890 μs | 17.010 μs | 9.790 μs | 8.030 μs | 48.826 μs | 12.240 μs |
| l2norm vec | Float64 128^3 | 1.575 ms | 1.089 ms | 809.456 μs | 708.307 μs | 506.955 μs | 252.683 μs | 127.311 μs | 75.901 μs | 86.910 μs | 33.701 μs |
| l2norm vec | Float64 256^3 | 14.836 ms | 12.142 ms | 10.977 ms | 10.406 ms | 12.136 ms | 7.295 ms | 5.663 ms | 5.525 ms | 540.049 μs | 491.425 μs |
| l2norm vec | Float64 512^3 | 120.453 ms | 99.144 ms | 91.153 ms | 87.669 ms | 95.940 ms | 62.201 ms | 54.589 ms | 54.973 ms | — | — |
| l2norm vec | Float64 64^3 | 92.026 μs | 50.507 μs | 27.157 μs | 20.346 μs | 59.161 μs | 30.891 μs | 17.210 μs | 11.290 μs | 43.587 μs | 17.130 μs |
| lpnorm vec Inf | Float32 128^3 | 1.381 ms | 1.242 ms | 1.106 ms | 956.961 μs | 463.304 μs | 388.824 μs | 333.483 μs | 338.524 μs | 186.119 μs | 66.011 μs |
| lpnorm vec Inf | Float32 256^3 | 13.432 ms | 13.110 ms | 11.263 ms | 11.016 ms | 8.558 ms | 7.443 ms | 7.308 ms | 8.842 ms | 1.072 ms | 506.725 μs |
| lpnorm vec Inf | Float32 512^3 | 110.235 ms | 108.705 ms | 92.782 ms | 85.620 ms | 77.598 ms | 71.842 ms | 70.319 ms | 71.557 ms | — | — |
| lpnorm vec Inf | Float32 64^3 | 96.755 μs | 85.910 μs | 69.360 μs | 77.471 μs | 61.221 μs | 49.410 μs | 42.480 μs | 42.661 μs | 91.144 μs | 24.690 μs |
| lpnorm vec Inf | Float64 128^3 | 3.069 ms | 3.051 ms | 2.658 ms | 2.458 ms | 1.204 ms | 1.038 ms | 937.679 μs | 986.931 μs | 289.463 μs | 115.032 μs |
| lpnorm vec Inf | Float64 256^3 | 27.867 ms | 26.535 ms | 23.321 ms | 21.593 ms | 17.413 ms | 15.442 ms | 16.616 ms | 15.935 ms | 1.913 ms | 940.439 μs |
| lpnorm vec Inf | Float64 512^3 | 216.590 ms | 214.431 ms | 189.028 ms | 173.911 ms | 138.848 ms | 137.789 ms | 140.560 ms | 139.527 ms | — | — |
| lpnorm vec Inf | Float64 64^3 | 235.039 μs | 180.882 μs | 146.661 μs | 156.021 μs | 111.021 μs | 92.231 μs | 76.861 μs | 73.241 μs | 106.665 μs | 34.590 μs |
| maximum scalar | Float32 128^3 | 337.764 μs | 176.549 μs | 90.750 μs | 50.518 μs | 238.352 μs | 117.732 μs | 61.421 μs | 33.070 μs | 134.032 μs | 31.500 μs |
| maximum scalar | Float32 256^3 | 3.932 ms | 2.016 ms | 1.401 ms | 1.212 ms | 2.002 ms | 944.690 μs | 487.845 μs | 249.813 μs | 606.662 μs | 175.282 μs |
| maximum scalar | Float32 512^3 | 25.096 ms | 17.126 ms | 15.422 ms | 14.664 ms | 31.382 ms | 12.720 ms | 9.007 ms | 8.138 ms | — | — |
| maximum scalar | Float32 64^3 | 42.197 μs | 24.567 μs | 14.047 μs | 10.389 μs | 29.560 μs | 15.870 μs | 9.320 μs | 6.930 μs | 74.590 μs | 17.610 μs |
| maximum scalar | Float64 128^3 | 528.797 μs | 283.995 μs | 145.437 μs | 77.542 μs | 440.814 μs | 222.262 μs | 113.642 μs | 59.651 μs | 180.314 μs | 40.740 μs |
| maximum scalar | Float64 256^3 | 6.070 ms | 3.961 ms | 3.434 ms | 3.067 ms | 4.043 ms | 2.036 ms | 1.099 ms | 824.389 μs | 966.657 μs | 214.182 μs |
| maximum scalar | Float64 512^3 | 48.697 ms | 34.187 ms | 30.824 ms | 28.774 ms | 44.789 ms | 26.944 ms | 19.316 ms | 17.364 ms | — | — |
| maximum scalar | Float64 64^3 | 65.461 μs | 36.439 μs | 20.243 μs | 18.262 μs | 55.340 μs | 29.610 μs | 15.810 μs | 9.970 μs | 83.618 μs | 24.020 μs |
| maximum(norm) vec | Float32 128^3 | 1.811 ms | 922.566 μs | 474.844 μs | 244.528 μs | 773.618 μs | 389.324 μs | 197.281 μs | 105.381 μs | 198.149 μs | 41.650 μs |
| maximum(norm) vec | Float32 256^3 | 15.033 ms | 8.192 ms | 5.677 ms | 5.050 ms | 8.475 ms | 3.923 ms | 2.454 ms | 2.121 ms | 836.865 μs | 283.012 μs |
| maximum(norm) vec | Float32 512^3 | 120.900 ms | 68.398 ms | 49.870 ms | 45.394 ms | 58.330 ms | 37.931 ms | 29.689 ms | 28.233 ms | — | — |
| maximum(norm) vec | Float32 64^3 | 222.431 μs | 116.133 μs | 61.167 μs | 35.122 μs | 96.891 μs | 49.131 μs | 26.730 μs | 15.400 μs | 93.677 μs | 20.080 μs |
| maximum(norm) vec | Float64 128^3 | 5.212 ms | 2.679 ms | 1.387 ms | 827.978 μs | 1.587 ms | 793.968 μs | 400.894 μs | 212.383 μs | 252.671 μs | 129.732 μs |
| maximum(norm) vec | Float64 256^3 | 42.269 ms | 21.413 ms | 12.905 ms | 11.074 ms | 14.279 ms | 8.345 ms | 6.050 ms | 5.845 ms | 1.599 ms | 858.829 μs |
| maximum(norm) vec | Float64 512^3 | 336.516 ms | 171.415 ms | 105.972 ms | 92.751 ms | 126.735 ms | 73.108 ms | 58.531 ms | 56.879 ms | — | — |
| maximum(norm) vec | Float64 64^3 | 638.368 μs | 329.823 μs | 170.247 μs | 89.445 μs | 200.822 μs | 101.681 μs | 52.230 μs | 28.440 μs | 102.271 μs | 33.560 μs |
| mean spectral vec | Float32 128^3 | 69.141 ns | 70.276 ns | 70.963 ns | 70.261 ns | 73.919 ns | 72.396 ns | 71.544 ns | 76.506 ns | 84.967 μs | 12.661 μs |
| mean spectral vec | Float32 256^3 | 69.613 ns | 70.330 ns | 71.158 ns | 70.371 ns | 73.976 ns | 73.150 ns | 72.117 ns | 72.425 ns | 82.056 μs | 12.700 μs |
| mean spectral vec | Float32 512^3 | 69.234 ns | 71.054 ns | 71.069 ns | 70.932 ns | 74.483 ns | 74.155 ns | 75.026 ns | 73.194 ns | — | — |
| mean spectral vec | Float32 64^3 | 69.121 ns | 70.071 ns | 70.182 ns | 69.947 ns | 76.115 ns | 73.865 ns | 71.048 ns | 74.567 ns | 84.431 μs | 12.870 μs |
| mean spectral vec | Float64 128^3 | 71.070 ns | 71.867 ns | 73.049 ns | 72.324 ns | 77.486 ns | 76.192 ns | 77.119 ns | 78.135 ns | 83.967 μs | 13.080 μs |
| mean spectral vec | Float64 256^3 | 71.273 ns | 78.255 ns | 73.664 ns | 73.138 ns | 79.392 ns | 77.658 ns | 79.929 ns | 75.757 ns | 76.018 μs | 12.850 μs |
| mean spectral vec | Float64 512^3 | 71.664 ns | 73.460 ns | 74.082 ns | 72.926 ns | 81.714 ns | 80.280 ns | 83.489 ns | 79.814 ns | — | — |
| mean spectral vec | Float64 64^3 | 70.823 ns | 71.770 ns | 71.687 ns | 71.911 ns | 78.617 ns | 78.574 ns | 79.546 ns | 79.545 ns | 84.076 μs | 13.040 μs |
| mean vector | Float32 128^3 | 482.641 μs | 310.667 μs | 178.861 μs | 90.867 μs | 196.452 μs | 106.832 μs | 60.631 μs | 45.211 μs | 407.711 μs | 97.041 μs |
| mean vector | Float32 256^3 | 6.763 ms | 5.695 ms | 5.396 ms | 4.937 ms | 2.955 ms | 2.601 ms | 2.378 ms | 2.428 ms | 1.867 ms | 532.326 μs |
| mean vector | Float32 512^3 | 58.094 ms | 48.767 ms | 45.002 ms | 43.874 ms | 28.612 ms | 27.453 ms | 26.914 ms | 27.202 ms | — | — |
| mean vector | Float32 64^3 | 42.133 μs | 26.238 μs | 18.047 μs | 24.175 μs | 26.260 μs | 16.101 μs | 13.271 μs | 16.670 μs | 235.002 μs | 55.111 μs |
| mean vector | Float64 128^3 | 1.429 ms | 975.410 μs | 794.005 μs | 715.888 μs | 405.604 μs | 206.232 μs | 109.711 μs | 83.171 μs | 436.032 μs | 105.791 μs |
| mean vector | Float64 256^3 | 13.969 ms | 12.176 ms | 10.978 ms | 10.798 ms | 8.764 ms | 7.028 ms | 6.598 ms | 6.607 ms | 2.242 ms | 578.496 μs |
| mean vector | Float64 512^3 | 112.936 ms | 97.267 ms | 91.126 ms | 87.712 ms | 59.155 ms | 55.405 ms | 54.357 ms | 54.957 ms | — | — |
| mean vector | Float64 64^3 | 82.690 μs | 50.074 μs | 31.043 μs | 30.919 μs | 46.641 μs | 31.170 μs | 19.820 μs | 18.480 μs | 244.373 μs | 60.311 μs |
| mean(det) tensor | Float32 128^3 | 2.391 ms | 1.858 ms | 1.619 ms | 1.471 ms | 773.457 μs | 364.684 μs | 197.372 μs | 122.662 μs | 182.515 μs | 113.481 μs |
| mean(det) tensor | Float32 256^3 | 23.487 ms | 20.919 ms | 17.919 ms | 17.085 ms | 15.771 ms | 11.669 ms | 10.300 ms | 10.414 ms | 1.109 ms | 744.398 μs |
| mean(det) tensor | Float32 512^3 | 170.480 ms | 165.423 ms | 151.064 ms | 143.383 ms | 105.720 ms | 95.093 ms | 84.211 ms | 85.725 ms | — | — |
| mean(det) tensor | Float32 64^3 | 98.669 μs | 57.125 μs | 29.159 μs | 20.881 μs | 67.911 μs | 36.300 μs | 21.080 μs | 15.120 μs | 87.233 μs | 24.960 μs |
| mean(det) tensor | Float64 128^3 | 5.358 ms | 4.492 ms | 3.881 ms | 3.682 ms | 2.559 ms | 1.501 ms | 1.203 ms | 1.215 ms | 260.984 μs | 202.542 μs |
| mean(det) tensor | Float64 256^3 | 40.903 ms | 41.704 ms | 37.786 ms | 34.942 ms | 30.046 ms | 23.878 ms | 21.582 ms | 21.552 ms | 1.592 ms | 1.449 ms |
| mean(det) tensor | Float64 512^3 | 331.638 ms | 323.253 ms | 299.467 ms | 282.559 ms | 228.934 ms | 185.116 ms | 169.237 ms | 172.437 ms | — | — |
| mean(det) tensor | Float64 64^3 | 221.128 μs | 125.856 μs | 73.053 μs | 41.701 μs | 168.142 μs | 67.661 μs | 36.360 μs | 28.720 μs | 93.755 μs | 28.840 μs |
| mean(norm) vec | Float32 128^3 | 1.561 ms | 796.172 μs | 408.668 μs | 211.500 μs | 611.166 μs | 301.773 μs | 155.732 μs | 84.761 μs | 246.487 μs | 41.551 μs |
| mean(norm) vec | Float32 256^3 | 12.794 ms | 7.553 ms | 5.591 ms | 5.035 ms | 7.630 ms | 3.581 ms | 2.334 ms | 2.129 ms | 837.492 μs | 282.373 μs |
| mean(norm) vec | Float32 512^3 | 103.296 ms | 64.193 ms | 49.636 ms | 45.466 ms | 51.592 ms | 36.426 ms | 29.222 ms | 28.205 ms | — | — |
| mean(norm) vec | Float32 64^3 | 189.812 μs | 99.795 μs | 53.256 μs | 59.800 μs | 76.531 μs | 39.851 μs | 21.090 μs | 13.021 μs | 92.161 μs | 20.030 μs |
| mean(norm) vec | Float64 128^3 | 5.150 ms | 2.658 ms | 1.363 ms | 859.489 μs | 1.451 ms | 724.877 μs | 364.814 μs | 194.562 μs | 224.577 μs | 113.051 μs |
| mean(norm) vec | Float64 256^3 | 41.603 ms | 21.115 ms | 12.871 ms | 10.884 ms | 13.324 ms | 8.210 ms | 5.873 ms | 5.829 ms | 1.367 ms | 744.878 μs |
| mean(norm) vec | Float64 512^3 | 331.666 ms | 169.374 ms | 104.921 ms | 92.263 ms | 113.281 ms | 71.836 ms | 57.876 ms | 56.753 ms | — | — |
| mean(norm) vec | Float64 64^3 | 631.515 μs | 326.227 μs | 165.307 μs | 89.379 μs | 179.141 μs | 91.741 μs | 47.980 μs | 26.601 μs | 99.186 μs | 29.230 μs |
| mean(tr) tensor | Float32 128^3 | 383.753 μs | 249.344 μs | 141.769 μs | 71.857 μs | 193.452 μs | 95.311 μs | 52.290 μs | 36.960 μs | 146.107 μs | 39.320 μs |
| mean(tr) tensor | Float32 256^3 | 6.479 ms | 6.027 ms | 5.326 ms | 4.954 ms | 3.197 ms | 2.380 ms | 2.203 ms | 2.248 ms | 703.203 μs | 274.963 μs |
| mean(tr) tensor | Float32 512^3 | 52.170 ms | 50.593 ms | 47.170 ms | 45.005 ms | 33.637 ms | 31.377 ms | 27.724 ms | 28.224 ms | — | — |
| mean(tr) tensor | Float32 64^3 | 34.694 μs | 18.602 μs | 11.032 μs | 10.662 μs | 25.450 μs | 12.570 μs | 8.070 μs | 6.330 μs | 82.402 μs | 20.170 μs |
| mean(tr) tensor | Float64 128^3 | 1.240 ms | 956.573 μs | 809.477 μs | 703.590 μs | 395.014 μs | 178.902 μs | 93.931 μs | 74.211 μs | 161.262 μs | 48.340 μs |
| mean(tr) tensor | Float64 256^3 | 12.238 ms | 12.254 ms | 11.263 ms | 10.601 ms | 7.026 ms | 6.539 ms | 6.370 ms | 6.234 ms | 868.061 μs | 500.395 μs |
| mean(tr) tensor | Float64 512^3 | 103.483 ms | 98.420 ms | 93.789 ms | 89.037 ms | 78.651 ms | 60.699 ms | 55.700 ms | 56.931 ms | — | — |
| mean(tr) tensor | Float64 64^3 | 66.748 μs | 36.881 μs | 20.146 μs | 15.154 μs | 50.970 μs | 24.470 μs | 14.221 μs | 10.170 μs | 83.970 μs | 21.360 μs |
| radial_correlation vec | Float32 128^3 | 35.151 ms | 31.486 ms | 32.879 ms | 31.751 ms | 30.250 ms | 21.843 ms | 21.607 ms | 20.799 ms | 712.025 μs | 538.235 μs |
| radial_correlation vec | Float32 256^3 | 398.125 ms | 262.073 ms | 236.578 ms | 259.450 ms | 279.445 ms | 178.171 ms | 155.845 ms | 158.980 ms | 10.100 ms | 6.336 ms |
| radial_correlation vec | Float32 512^3 | 3.394 s | 2.295 s | 1.816 s | 1.610 s | 2.760 s | 1.743 s | 1.282 s | 1.106 s | — | — |
| radial_correlation vec | Float32 64^3 | 4.219 ms | 5.035 ms | 5.348 ms | 5.679 ms | 3.519 ms | 3.292 ms | 3.730 ms | 3.454 ms | 228.975 μs | 153.551 μs |
| radial_correlation vec | Float64 128^3 | 43.432 ms | 52.445 ms | 38.468 ms | 35.521 ms | 37.444 ms | 33.975 ms | 24.580 ms | 23.638 ms | 36.307 ms | 1.878 ms |
| radial_correlation vec | Float64 256^3 | 560.709 ms | 401.741 ms | 322.978 ms | 332.686 ms | 476.153 ms | 320.011 ms | 270.548 ms | 244.050 ms | 143.483 ms | 14.580 ms |
| radial_correlation vec | Float64 512^3 | 5.447 s | 3.601 s | 2.808 s | 2.482 s | 4.311 s | 2.792 s | 1.967 s | 1.727 s | — | — |
| radial_correlation vec | Float64 64^3 | 5.210 ms | 4.824 ms | 5.190 ms | 5.392 ms | 3.823 ms | 3.356 ms | 3.261 ms | 3.355 ms | 12.815 ms | 257.092 μs |
| radial_spectrum vec | Float32 128^3 | 7.486 ms | 6.712 ms | 8.332 ms | 7.899 ms | 6.328 ms | 4.769 ms | 5.731 ms | 5.831 ms | 319.559 μs | 172.952 μs |
| radial_spectrum vec | Float32 256^3 | 59.596 ms | 45.185 ms | 45.037 ms | 43.598 ms | 50.112 ms | 33.734 ms | 30.885 ms | 29.936 ms | 939.271 μs | 824.718 μs |
| radial_spectrum vec | Float32 512^3 | 476.201 ms | 349.437 ms | 262.054 ms | 230.205 ms | 399.577 ms | 238.150 ms | 181.107 ms | 153.786 ms | — | — |
| radial_spectrum vec | Float32 64^3 | 977.725 μs | 1.357 ms | 1.587 ms | 1.686 ms | 821.738 μs | 869.578 μs | 1.178 ms | 1.280 ms | 218.585 μs | 70.131 μs |
| radial_spectrum vec | Float64 128^3 | 7.572 ms | 5.542 ms | 6.097 ms | 5.876 ms | 6.543 ms | 4.581 ms | 4.535 ms | 4.304 ms | 17.266 ms | 250.862 μs |
| radial_spectrum vec | Float64 256^3 | 60.277 ms | 43.936 ms | 35.197 ms | 31.135 ms | 51.926 ms | 32.112 ms | 26.082 ms | 22.797 ms | 55.432 ms | 1.137 ms |
| radial_spectrum vec | Float64 512^3 | 490.738 ms | 337.787 ms | 219.470 ms | 168.824 ms | 414.658 ms | 255.715 ms | 169.072 ms | 124.622 ms | — | — |
| radial_spectrum vec | Float64 64^3 | 974.096 μs | 912.629 μs | 1.061 ms | 1.067 ms | 846.298 μs | 691.227 μs | 848.008 μs | 893.579 μs | 6.966 ms | 77.171 μs |
| reality_residual scalar | Float32 128^3 | 213.743 μs | 218.943 μs | 218.008 μs | 218.007 μs | 168.162 μs | 167.272 μs | 168.391 μs | 167.512 μs | 243.277 μs | 82.831 μs |
| reality_residual scalar | Float32 256^3 | 984.448 μs | 986.522 μs | 990.420 μs | 984.565 μs | 684.498 μs | 686.717 μs | 689.117 μs | 686.127 μs | 223.046 μs | 82.941 μs |
| reality_residual scalar | Float32 512^3 | 7.867 ms | 8.057 ms | 8.058 ms | 8.106 ms | 2.720 ms | 2.762 ms | 2.799 ms | 2.770 ms | — | — |
| reality_residual scalar | Float32 64^3 | 49.487 μs | 49.595 μs | 49.710 μs | 49.914 μs | 41.431 μs | 40.840 μs | 41.201 μs | 40.790 μs | 231.816 μs | 80.561 μs |
| reality_residual scalar | Float64 128^3 | 358.359 μs | 359.414 μs | 359.712 μs | 360.497 μs | 351.434 μs | 351.564 μs | 353.093 μs | 353.034 μs | 238.392 μs | 97.651 μs |
| reality_residual scalar | Float64 256^3 | 1.618 ms | 1.585 ms | 1.628 ms | 1.591 ms | 1.433 ms | 1.436 ms | 1.420 ms | 1.421 ms | 242.901 μs | 99.351 μs |
| reality_residual scalar | Float64 512^3 | 13.108 ms | 12.537 ms | 12.435 ms | 12.722 ms | 5.866 ms | 5.857 ms | 5.861 ms | 5.826 ms | — | — |
| reality_residual scalar | Float64 64^3 | 78.306 μs | 78.560 μs | 79.120 μs | 79.472 μs | 86.501 μs | 86.551 μs | 86.481 μs | 85.761 μs | 231.729 μs | 96.761 μs |
| reality_residual vector | Float32 128^3 | 797.970 μs | 802.071 μs | 805.810 μs | 802.633 μs | 656.336 μs | 654.547 μs | 647.486 μs | 649.897 μs | 248.532 μs | 86.441 μs |
| reality_residual vector | Float32 256^3 | 5.641 ms | 5.234 ms | 5.167 ms | 5.671 ms | 2.640 ms | 2.619 ms | 2.609 ms | 2.625 ms | 292.628 μs | 90.921 μs |
| reality_residual vector | Float32 512^3 | 34.370 ms | 33.639 ms | 33.893 ms | 34.058 ms | 16.707 ms | 16.561 ms | 16.481 ms | 16.969 ms | — | — |
| reality_residual vector | Float32 64^3 | 186.153 μs | 183.949 μs | 185.382 μs | 186.842 μs | 161.401 μs | 161.032 μs | 162.261 μs | 164.432 μs | 245.317 μs | 85.911 μs |
| reality_residual vector | Float64 128^3 | 1.265 ms | 1.263 ms | 1.274 ms | 1.266 ms | 1.247 ms | 1.250 ms | 1.250 ms | 1.244 ms | 254.129 μs | 98.111 μs |
| reality_residual vector | Float64 256^3 | 8.667 ms | 8.748 ms | 8.526 ms | 9.556 ms | 5.023 ms | 5.040 ms | 5.013 ms | 5.072 ms | 285.748 μs | 118.111 μs |
| reality_residual vector | Float64 512^3 | 47.947 ms | 48.343 ms | 48.199 ms | 48.095 ms | 35.599 ms | 35.030 ms | 34.773 ms | 35.472 ms | — | — |
| reality_residual vector | Float64 64^3 | 270.954 μs | 273.350 μs | 273.271 μs | 275.105 μs | 309.283 μs | 310.203 μs | 308.733 μs | 309.473 μs | 243.844 μs | 96.221 μs |
| var scalar | Float32 128^3 | 239.652 μs | 133.984 μs | 67.287 μs | 43.435 μs | 131.172 μs | 73.391 μs | 42.870 μs | 28.130 μs | 268.699 μs | 64.440 μs |
| var scalar | Float32 256^3 | 4.956 ms | 3.328 ms | 2.624 ms | 2.438 ms | 1.257 ms | 627.077 μs | 340.133 μs | 203.692 μs | 1.221 ms | 353.414 μs |
| var scalar | Float32 512^3 | 40.566 ms | 32.049 ms | 29.920 ms | 29.032 ms | 27.547 ms | 20.549 ms | 18.109 ms | 17.774 ms | — | — |
| var scalar | Float32 64^3 | 25.076 μs | 16.319 μs | 11.845 μs | 15.311 μs | 14.640 μs | 9.051 μs | 7.330 μs | 8.870 μs | 150.346 μs | 37.000 μs |
| var scalar | Float64 128^3 | 454.598 μs | 267.987 μs | 137.690 μs | 80.483 μs | 249.073 μs | 128.081 μs | 75.171 μs | 48.641 μs | 315.483 μs | 66.331 μs |
| var scalar | Float64 256^3 | 8.736 ms | 7.554 ms | 6.595 ms | 6.133 ms | 3.559 ms | 2.401 ms | 1.668 ms | 1.848 ms | 1.549 ms | 388.644 μs |
| var scalar | Float64 512^3 | 74.782 ms | 64.406 ms | 60.963 ms | 58.476 ms | 43.189 ms | 38.893 ms | 36.797 ms | 36.198 ms | — | — |
| var scalar | Float64 64^3 | 52.096 μs | 26.975 μs | 18.050 μs | 16.950 μs | 30.690 μs | 17.810 μs | 11.170 μs | 11.220 μs | 168.107 μs | 38.890 μs |
| var spectral scalar | Float32 128^3 | 130.904 μs | 93.990 μs | 60.903 μs | 55.884 μs | 95.661 μs | 59.790 μs | 42.860 μs | 43.321 μs | 257.121 μs | 64.341 μs |
| var spectral scalar | Float32 256^3 | 2.217 ms | 1.770 ms | 1.577 ms | 1.445 ms | 754.978 μs | 406.894 μs | 292.553 μs | 249.133 μs | 468.654 μs | 151.092 μs |
| var spectral scalar | Float32 512^3 | 19.848 ms | 17.694 ms | 16.980 ms | 16.349 ms | 12.682 ms | 10.480 ms | 10.813 ms | 10.860 ms | — | — |
| var spectral scalar | Float32 64^3 | 16.863 μs | 12.248 μs | 9.897 μs | 11.313 μs | 11.030 μs | 8.130 μs | 7.280 μs | 9.700 μs | 211.936 μs | 60.601 μs |
| var spectral scalar | Float64 128^3 | 250.977 μs | 181.594 μs | 113.706 μs | 87.324 μs | 147.541 μs | 87.031 μs | 61.850 μs | 54.271 μs | 269.779 μs | 69.811 μs |
| var spectral scalar | Float64 256^3 | 4.605 ms | 3.946 ms | 3.674 ms | 3.391 ms | 2.256 ms | 1.389 ms | 1.066 ms | 1.095 ms | 581.010 μs | 233.412 μs |
| var spectral scalar | Float64 512^3 | 40.653 ms | 34.727 ms | 33.266 ms | 31.667 ms | 21.690 ms | 20.627 ms | 20.441 ms | 20.498 ms | — | — |
| var spectral scalar | Float64 64^3 | 30.342 μs | 19.188 μs | 13.898 μs | 13.840 μs | 20.040 μs | 12.810 μs | 9.460 μs | 11.030 μs | 235.839 μs | 57.091 μs |
| weighted_inner vec | Float32 128^3 | 1.662 ms | 892.709 μs | 500.096 μs | 367.242 μs | 1.360 ms | 685.327 μs | 346.384 μs | 177.012 μs | 260.415 μs | 74.331 μs |
| weighted_inner vec | Float32 256^3 | 15.948 ms | 12.356 ms | 10.879 ms | 10.025 ms | 11.335 ms | 5.636 ms | 3.557 ms | 3.514 ms | 1.449 ms | 550.355 μs |
| weighted_inner vec | Float32 512^3 | 130.365 ms | 106.851 ms | 95.918 ms | 89.345 ms | 92.604 ms | 63.924 ms | 55.997 ms | 54.459 ms | — | — |
| weighted_inner vec | Float32 64^3 | 218.836 μs | 235.411 μs | 219.880 μs | 220.153 μs | 184.691 μs | 187.141 μs | 184.692 μs | 185.292 μs | 120.520 μs | 26.150 μs |
| weighted_inner vec | Float64 128^3 | 3.063 ms | 2.420 ms | 1.867 ms | 1.575 ms | 1.429 ms | 721.187 μs | 361.834 μs | 205.802 μs | 302.167 μs | 98.121 μs |
| weighted_inner vec | Float64 256^3 | 29.371 ms | 25.216 ms | 22.985 ms | 21.528 ms | 16.142 ms | 11.210 ms | 10.093 ms | 10.224 ms | 1.825 ms | 984.110 μs |
| weighted_inner vec | Float64 512^3 | 241.161 ms | 207.671 ms | 191.184 ms | 177.627 ms | 128.962 ms | 114.216 ms | 112.341 ms | 111.688 ms | — | — |
| weighted_inner vec | Float64 64^3 | 252.268 μs | 251.484 μs | 251.917 μs | 251.552 μs | 193.782 μs | 194.102 μs | 195.962 μs | 195.572 μs | 124.601 μs | 27.870 μs |
| weighted_inner vec.vec | Float32 128^3 | 2.092 ms | 1.572 ms | 1.253 ms | 1.090 ms | 1.390 ms | 697.227 μs | 366.533 μs | 187.402 μs | 263.406 μs | 91.731 μs |
| weighted_inner vec.vec | Float32 256^3 | 21.621 ms | 18.964 ms | 17.365 ms | 16.185 ms | 12.909 ms | 8.544 ms | 7.219 ms | 7.280 ms | 1.448 ms | 746.987 μs |
| weighted_inner vec.vec | Float32 512^3 | 187.332 ms | 163.004 ms | 145.978 ms | 135.174 ms | 103.520 ms | 90.046 ms | 85.474 ms | 84.781 ms | — | — |
| weighted_inner vec.vec | Float32 64^3 | 219.543 μs | 220.854 μs | 236.257 μs | 221.277 μs | 192.912 μs | 189.602 μs | 189.742 μs | 193.592 μs | 117.471 μs | 26.221 μs |
| weighted_inner vec.vec | Float64 128^3 | 4.597 ms | 4.023 ms | 3.541 ms | 3.164 ms | 1.955 ms | 1.049 ms | 635.257 μs | 535.806 μs | 302.544 μs | 178.332 μs |
| weighted_inner vec.vec | Float64 256^3 | 43.119 ms | 38.744 ms | 35.527 ms | 33.349 ms | 24.296 ms | 19.242 ms | 17.856 ms | 17.882 ms | 1.846 ms | 1.457 ms |
| weighted_inner vec.vec | Float64 512^3 | 341.644 ms | 311.669 ms | 288.879 ms | 267.629 ms | 203.568 ms | 176.236 ms | 170.131 ms | 170.497 ms | — | — |
| weighted_inner vec.vec | Float64 64^3 | 281.112 μs | 278.768 μs | 303.706 μs | 278.558 μs | 207.032 μs | 210.762 μs | 213.252 μs | 204.082 μs | 122.985 μs | 28.240 μs |
| weighted_inner x3 fused | Float32 128^3 | 6.108 ms | 3.128 ms | 1.594 ms | 814.594 μs | 5.073 ms | 2.473 ms | 1.270 ms | 639.767 μs | 327.755 μs | 121.521 μs |
| weighted_inner x3 fused | Float32 256^3 | 47.027 ms | 23.970 ms | 12.313 ms | 6.401 ms | 39.735 ms | 19.348 ms | 9.949 ms | 4.995 ms | 1.918 ms | 867.169 μs |
| weighted_inner x3 fused | Float32 512^3 | 367.060 ms | 186.553 ms | 95.774 ms | 51.866 ms | 314.641 ms | 153.118 ms | 77.573 ms | 40.135 ms | — | — |
| weighted_inner x3 fused | Float32 64^3 | 826.607 μs | 830.956 μs | 811.360 μs | 799.010 μs | 656.317 μs | 654.606 μs | 655.467 μs | 638.187 μs | 134.183 μs | 35.570 μs |
| weighted_inner x3 fused | Float64 128^3 | 6.265 ms | 3.160 ms | 1.653 ms | 967.902 μs | 5.083 ms | 2.505 ms | 1.276 ms | 643.336 μs | 508.994 μs | 201.922 μs |
| weighted_inner x3 fused | Float64 256^3 | 47.611 ms | 24.160 ms | 13.594 ms | 11.356 ms | 40.261 ms | 19.677 ms | 10.025 ms | 5.727 ms | 3.360 ms | 1.377 ms |
| weighted_inner x3 fused | Float64 512^3 | 366.249 ms | 187.237 ms | 107.897 ms | 91.901 ms | 316.140 ms | 156.115 ms | 79.955 ms | 55.188 ms | — | — |
| weighted_inner x3 fused | Float64 64^3 | 842.391 μs | 803.162 μs | 808.551 μs | 820.538 μs | 660.727 μs | 637.857 μs | 653.997 μs | 654.157 μs | 151.155 μs | 48.701 μs |
| weighted_inner x3 separate | Float32 128^3 | 8.047 ms | 4.131 ms | 2.146 ms | 1.122 ms | 6.323 ms | 3.135 ms | 1.574 ms | 813.328 μs | 787.266 μs | 264.132 μs |
| weighted_inner x3 separate | Float32 256^3 | 60.834 ms | 32.095 ms | 19.224 ms | 16.200 ms | 49.600 ms | 23.500 ms | 12.092 ms | 6.887 ms | 4.850 ms | 1.729 ms |
| weighted_inner x3 separate | Float32 512^3 | 467.438 ms | 247.507 ms | 155.081 ms | 139.185 ms | 394.257 ms | 185.447 ms | 106.058 ms | 81.642 ms | — | — |
| weighted_inner x3 separate | Float32 64^3 | 1.056 ms | 1.057 ms | 1.056 ms | 1.056 ms | 828.428 μs | 828.098 μs | 827.719 μs | 826.839 μs | 349.174 μs | 86.290 μs |
| weighted_inner x3 separate | Float64 128^3 | 9.389 ms | 5.085 ms | 3.254 ms | 2.576 ms | 5.877 ms | 2.953 ms | 1.560 ms | 805.609 μs | 1.025 ms | 316.023 μs |
| weighted_inner x3 separate | Float64 256^3 | 74.079 ms | 45.374 ms | 35.316 ms | 32.981 ms | 51.938 ms | 25.906 ms | 17.581 ms | 16.750 ms | 6.264 ms | 2.075 ms |
| weighted_inner x3 separate | Float64 512^3 | 599.118 ms | 368.754 ms | 285.475 ms | 267.885 ms | 399.158 ms | 219.854 ms | 164.697 ms | 164.164 ms | — | — |
| weighted_inner x3 separate | Float64 64^3 | 1.113 ms | 1.113 ms | 1.113 ms | 1.114 ms | 816.428 μs | 815.938 μs | 812.978 μs | 815.219 μs | 375.382 μs | 97.271 μs |

## storage

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| adapt multipliers | Float32 128^3 | — | — | — | — | — | — | — | — | 138.471 μs | 11.680 μs |
| adapt multipliers | Float32 256^3 | — | — | — | — | — | — | — | — | 153.250 μs | 12.620 μs |
| adapt multipliers | Float32 512^3 | — | — | — | — | — | — | — | — | 153.374 μs | — |
| adapt multipliers | Float32 64^3 | — | — | — | — | — | — | — | — | 146.466 μs | 12.370 μs |
| adapt multipliers | Float64 128^3 | — | — | — | — | — | — | — | — | 149.081 μs | 11.890 μs |
| adapt multipliers | Float64 256^3 | — | — | — | — | — | — | — | — | 148.469 μs | 12.700 μs |
| adapt multipliers | Float64 64^3 | — | — | — | — | — | — | — | — | 142.844 μs | 12.460 μs |
| adapt plans (rebuild) | Float32 128^3 | — | — | — | — | — | — | — | — | 17.967 μs | 7.940 μs |
| adapt plans (rebuild) | Float32 256^3 | — | — | — | — | — | — | — | — | 64.793 μs | 65.061 μs |
| adapt plans (rebuild) | Float32 512^3 | — | — | — | — | — | — | — | — | 67.511 μs | — |
| adapt plans (rebuild) | Float32 64^3 | — | — | — | — | — | — | — | — | 11.537 μs | 7.670 μs |
| adapt plans (rebuild) | Float64 128^3 | — | — | — | — | — | — | — | — | 21.871 μs | 8.480 μs |
| adapt plans (rebuild) | Float64 256^3 | — | — | — | — | — | — | — | — | 62.267 μs | 63.931 μs |
| adapt plans (rebuild) | Float64 64^3 | — | — | — | — | — | — | — | — | 12.024 μs | 7.560 μs |
| adapt to device scalar | Float32 128^3 | — | — | — | — | — | — | — | — | 672.029 μs | 306.153 μs |
| adapt to device scalar | Float32 256^3 | — | — | — | — | — | — | — | — | 5.603 ms | 2.442 ms |
| adapt to device scalar | Float32 512^3 | — | — | — | — | — | — | — | — | 42.777 ms | — |
| adapt to device scalar | Float32 64^3 | — | — | — | — | — | — | — | — | 124.403 μs | 61.210 μs |
| adapt to device scalar | Float64 128^3 | — | — | — | — | — | — | — | — | 1.342 ms | 596.516 μs |
| adapt to device scalar | Float64 256^3 | — | — | — | — | — | — | — | — | 11.259 ms | 6.108 ms |
| adapt to device scalar | Float64 64^3 | — | — | — | — | — | — | — | — | 172.713 μs | 93.271 μs |
| adapt to device vector | Float32 128^3 | — | — | — | — | — | — | — | — | 1.999 ms | 884.409 μs |
| adapt to device vector | Float32 256^3 | — | — | — | — | — | — | — | — | 16.397 ms | 9.309 ms |
| adapt to device vector | Float32 512^3 | — | — | — | — | — | — | — | — | 126.184 ms | — |
| adapt to device vector | Float32 64^3 | — | — | — | — | — | — | — | — | 258.890 μs | 129.501 μs |
| adapt to device vector | Float64 128^3 | — | — | — | — | — | — | — | — | 4.268 ms | 1.772 ms |
| adapt to device vector | Float64 256^3 | — | — | — | — | — | — | — | — | 32.157 ms | 19.782 ms |
| adapt to device vector | Float64 64^3 | — | — | — | — | — | — | — | — | 512.232 μs | 236.553 μs |
| adapt to host scalar | Float32 128^3 | — | — | — | — | — | — | — | — | 512.599 μs | 431.574 μs |
| adapt to host scalar | Float32 256^3 | — | — | — | — | — | — | — | — | 12.751 ms | 11.107 ms |
| adapt to host scalar | Float32 512^3 | — | — | — | — | — | — | — | — | 92.981 ms | — |
| adapt to host scalar | Float32 64^3 | — | — | — | — | — | — | — | — | 114.163 μs | 63.360 μs |
| adapt to host scalar | Float64 128^3 | — | — | — | — | — | — | — | — | 1.027 ms | 846.988 μs |
| adapt to host scalar | Float64 256^3 | — | — | — | — | — | — | — | — | 23.696 ms | 22.800 ms |
| adapt to host scalar | Float64 64^3 | — | — | — | — | — | — | — | — | 130.375 μs | 117.062 μs |
| adapt to host vector | Float32 128^3 | — | — | — | — | — | — | — | — | 1.526 ms | 1.269 ms |
| adapt to host vector | Float32 256^3 | — | — | — | — | — | — | — | — | 35.027 ms | 33.463 ms |
| adapt to host vector | Float32 512^3 | — | — | — | — | — | — | — | — | 280.672 ms | — |
| adapt to host vector | Float32 64^3 | — | — | — | — | — | — | — | — | 195.252 μs | 169.561 μs |
| adapt to host vector | Float64 128^3 | — | — | — | — | — | — | — | — | 9.058 ms | 8.194 ms |
| adapt to host vector | Float64 256^3 | — | — | — | — | — | — | — | — | 69.022 ms | 69.071 ms |
| adapt to host vector | Float64 64^3 | — | — | — | — | — | — | — | — | 384.091 μs | 323.783 μs |
| adapt to own family (identity) | Float32 128^3 | — | — | — | — | — | — | — | — | 147.659 ns | 128.879 ns |
| adapt to own family (identity) | Float32 256^3 | — | — | — | — | — | — | — | — | 147.047 ns | 128.254 ns |
| adapt to own family (identity) | Float32 512^3 | — | — | — | — | — | — | — | — | 158.228 ns | — |
| adapt to own family (identity) | Float32 64^3 | — | — | — | — | — | — | — | — | 147.184 ns | 128.400 ns |
| adapt to own family (identity) | Float64 128^3 | — | — | — | — | — | — | — | — | 147.794 ns | 122.509 ns |
| adapt to own family (identity) | Float64 256^3 | — | — | — | — | — | — | — | — | 146.425 ns | 123.246 ns |
| adapt to own family (identity) | Float64 64^3 | — | — | — | — | — | — | — | — | 146.381 ns | 126.877 ns |
| adapt! to device scalar | Float32 128^3 | — | — | — | — | — | — | — | — | 666.883 μs | 303.983 μs |
| adapt! to device scalar | Float32 256^3 | — | — | — | — | — | — | — | — | 5.233 ms | 2.425 ms |
| adapt! to device scalar | Float32 512^3 | — | — | — | — | — | — | — | — | 42.054 ms | — |
| adapt! to device scalar | Float32 64^3 | — | — | — | — | — | — | — | — | 113.354 μs | 58.780 μs |
| adapt! to device scalar | Float64 128^3 | — | — | — | — | — | — | — | — | 1.336 ms | 589.445 μs |
| adapt! to device scalar | Float64 256^3 | — | — | — | — | — | — | — | — | 10.414 ms | 6.010 ms |
| adapt! to device scalar | Float64 64^3 | — | — | — | — | — | — | — | — | 168.115 μs | 91.541 μs |
| adapt! to device vector | Float32 128^3 | — | — | — | — | — | — | — | — | 1.998 ms | 877.428 μs |
| adapt! to device vector | Float32 256^3 | — | — | — | — | — | — | — | — | 15.632 ms | 9.089 ms |
| adapt! to device vector | Float32 512^3 | — | — | — | — | — | — | — | — | 125.463 ms | — |
| adapt! to device vector | Float32 64^3 | — | — | — | — | — | — | — | — | 253.874 μs | 127.721 μs |
| adapt! to device vector | Float64 128^3 | — | — | — | — | — | — | — | — | 3.923 ms | 1.757 ms |
| adapt! to device vector | Float64 256^3 | — | — | — | — | — | — | — | — | 31.337 ms | 18.287 ms |
| adapt! to device vector | Float64 64^3 | — | — | — | — | — | — | — | — | 507.358 μs | 233.282 μs |
| adapt! to host scalar | Float32 128^3 | — | — | — | — | — | — | — | — | 525.143 μs | 427.684 μs |
| adapt! to host scalar | Float32 256^3 | — | — | — | — | — | — | — | — | 4.239 ms | 3.367 ms |
| adapt! to host scalar | Float32 512^3 | — | — | — | — | — | — | — | — | 33.264 ms | — |
| adapt! to host scalar | Float32 64^3 | — | — | — | — | — | — | — | — | 103.282 μs | 63.470 μs |
| adapt! to host scalar | Float64 128^3 | — | — | — | — | — | — | — | — | 1.045 ms | 847.598 μs |
| adapt! to host scalar | Float64 256^3 | — | — | — | — | — | — | — | — | 8.118 ms | 6.811 ms |
| adapt! to host scalar | Float64 64^3 | — | — | — | — | — | — | — | — | 130.692 μs | 115.181 μs |
| adapt! to host vector | Float32 128^3 | — | — | — | — | — | — | — | — | 1.516 ms | 1.268 ms |
| adapt! to host vector | Float32 256^3 | — | — | — | — | — | — | — | — | 12.544 ms | 10.127 ms |
| adapt! to host vector | Float32 512^3 | — | — | — | — | — | — | — | — | 99.702 ms | — |
| adapt! to host vector | Float32 64^3 | — | — | — | — | — | — | — | — | 198.267 μs | 169.212 μs |
| adapt! to host vector | Float64 128^3 | — | — | — | — | — | — | — | — | 3.060 ms | 2.522 ms |
| adapt! to host vector | Float64 256^3 | — | — | — | — | — | — | — | — | 24.438 ms | 20.237 ms |
| adapt! to host vector | Float64 64^3 | — | — | — | — | — | — | — | — | 385.345 μs | 323.093 μs |

## Triage — the born-slow scan

Two questions no per-row history can answer (finding (ag)): does a threaded operation actually scale, and is a row wildly slower than its class peers at the same workload. Flags are QUESTIONS, not verdicts — a `known` row carries its recorded reason, and an unexplained one is closed by a fix or by a recorded reason, never by deleting the row. Thresholds: flat means under 1.1x speedup lowest-to-highest thread lane with at least 1.000 ms of work; an outlier is over 8.0x its class median.

### A. Thread-flat on every host — 16 flagged (12 known)

| class | row | per-host (t_low, speedup) | note |
|:--|:--|:--|:--|
| reductions | co-spectrum vec.vec | Float32 128^3 | 12700K: 8.085 ms ×1.04; 9800X3D: 6.955 ms ×1.08 | **UNEXPLAINED** |
| reductions | co-spectrum vec.vec | Float32 64^3 | 12700K: 1.044 ms ×0.64 | **UNEXPLAINED** |
| reductions | co-spectrum vec.vec | Float64 64^3 | 12700K: 1.064 ms ×1.08 | **UNEXPLAINED** |
| reductions | cross-correlation vec.vec | Float32 64^3 | 12700K: 4.607 ms ×0.82; 9800X3D: 3.841 ms ×1.04 | known: the radial_correlation co-spectrum form — same materialization |
| reductions | radial_correlation vec | Float32 64^3 | 12700K: 4.219 ms ×0.74; 9800X3D: 3.519 ms ×1.02 | known: materializes its power field + inverse transform by design — decision 22 |
| reductions | radial_spectrum vec | Float32 128^3 | 12700K: 7.486 ms ×0.95; 9800X3D: 6.328 ms ×1.09 | **UNEXPLAINED** |
| reductions | reality_residual scalar | Float32 512^3 | 12700K: 7.867 ms ×0.97; 9800X3D: 2.720 ms ×0.98 | known: recorded: neither threads nor fuses — CLAUDE.md roadmap, decision 71 entry |
| reductions | reality_residual scalar | Float64 256^3 | 12700K: 1.618 ms ×1.02; 9800X3D: 1.433 ms ×1.01 | known: recorded: neither threads nor fuses — CLAUDE.md roadmap, decision 71 entry |
| reductions | reality_residual scalar | Float64 512^3 | 12700K: 13.108 ms ×1.03; 9800X3D: 5.866 ms ×1.01 | known: recorded: neither threads nor fuses — CLAUDE.md roadmap, decision 71 entry |
| reductions | reality_residual vector | Float32 256^3 | 12700K: 5.641 ms ×0.99; 9800X3D: 2.640 ms ×1.01 | known: recorded: neither threads nor fuses — CLAUDE.md roadmap, decision 71 entry |
| reductions | reality_residual vector | Float32 512^3 | 12700K: 34.370 ms ×1.01; 9800X3D: 16.707 ms ×0.98 | known: recorded: neither threads nor fuses — CLAUDE.md roadmap, decision 71 entry |
| reductions | reality_residual vector | Float64 128^3 | 12700K: 1.265 ms ×1.0; 9800X3D: 1.247 ms ×1.0 | known: recorded: neither threads nor fuses — CLAUDE.md roadmap, decision 71 entry |
| reductions | reality_residual vector | Float64 256^3 | 12700K: 8.667 ms ×0.91; 9800X3D: 5.023 ms ×0.99 | known: recorded: neither threads nor fuses — CLAUDE.md roadmap, decision 71 entry |
| reductions | reality_residual vector | Float64 512^3 | 12700K: 47.947 ms ×1.0; 9800X3D: 35.599 ms ×1.0 | known: recorded: neither threads nor fuses — CLAUDE.md roadmap, decision 71 entry |
| reductions | weighted_inner x3 separate | Float32 64^3 | 12700K: 1.056 ms ×1.0 | known: the finding-(ac) pathology, FIXED 2026-08-30; BOTH hosts are now re-swept (2026-08-31) and the pathology is gone — the only surviving flags are the 64^3 rows, which carry ~1.1 ms of work against a 1 ms floor and are overhead-bound, not the pathology |
| reductions | weighted_inner x3 separate | Float64 64^3 | 12700K: 1.113 ms ×1.0 | known: the finding-(ac) pathology, FIXED 2026-08-30; BOTH hosts are now re-swept (2026-08-31) and the pathology is gone — the only surviving flags are the 64^3 rows, which carry ~1.1 ms of work against a 1 ms floor and are overhead-bound, not the pathology |

### B. Declared-peer violations — 0 flagged (0 known)


## Shipped slower? — the history scan

Every cell's whole committed history, read at once — the drift and the step-in-an-unwatched-row that the canary, the triage and a one-archive-against-its-predecessor write-up all miss.

**A flagged cell is a hypothesis, not a regression.** This table mixes hosts, sweep shapes and measurement regimes, and documented effects move rows with no code change. Confirm with a matched A/B against the commit before the step before calling one real. The scan reads the *committed* history, so a sweep merged in this same change appears only at the next regeneration.

```
parsed 48 versions of RESULTS.md; 7423 (row, column) cells in-regime

=== cells at least 1.25x slower at HEAD than their in-regime best: 111

  2.77x  adapt plans (rebuild)              Float32 256^3    GPU 5070TI          0.023(08-17) ->     0.065  n=14  PERSISTENT
  2.46x  materialize_kernel separable       Float64 512^3    CPU 12700K t2      63.370(08-07) ->   156.007  n=23  PERSISTENT
  2.22x  to_spectral vector                 Float32 512^3    GPU 7900XTX        20.298(08-07) ->    45.159  n=23  PERSISTENT
  1.91x  materialize_kernel separable       Float32 512^3    CPU 9800X3D t4     18.405(08-09) ->    35.141  n=27  PERSISTENT
  1.90x  materialize_kernel radial          Float32 512^3    CPU 9800X3D t4     16.917(08-09) ->    32.141  n=27  PERSISTENT
  1.76x  to_spectral vector measure         Float64 128^3    CPU 12700K t2      15.038(07-30) ->    26.414  n=27  PERSISTENT
  1.74x  to_spectral vector measure         Float32 256^3    CPU 12700K t4      59.081(08-07) ->   103.016  n=27  PERSISTENT
  1.74x  to_spectral scalar measure         Float64 256^3    CPU 12700K t4      38.813(08-07) ->    67.470  n=27  PERSISTENT
  1.74x  to_spectral vector measure         Float32 256^3    CPU 12700K t1     106.816(08-07) ->   185.611  n=27  PERSISTENT
  1.70x  to_spectral scalar measure         Float32 512^3    CPU 9800X3D t4    113.206(08-05) ->   192.895  n=27  PERSISTENT
  1.69x  to_spectral scalar measure         Float32 512^3    CPU 9800X3D t8     98.470(08-05) ->   166.208  n=27  PERSISTENT
  1.68x  to_spectral scalar measure         Float32 512^3    CPU 12700K t2     224.043(08-07) ->   376.988  n=23  PERSISTENT
  1.68x  maximum scalar                     Float64 128^3    CPU 12700K t8       0.079(07-30) ->     0.133  n=27  one-off?
  1.68x  interpolate! NUFFT                 Float32 64^3     GPU 7900XTX         0.414(08-07) ->     0.694  n=23  PERSISTENT
  1.67x  to_physical vector measure         Float64 128^3    CPU 12700K t2      18.363(08-07) ->    30.729  n=27  PERSISTENT
  1.66x  materialize_kernel separable       Float64 512^3    CPU 9800X3D t4     36.888(08-28) ->    61.319  n=27  one-off?
  1.65x  to_spectral vector                 Float64 128^3    CPU 12700K t8      12.273(08-07) ->    20.238  n=27  PERSISTENT
  1.62x  to_spectral vector measure         Float64 128^3    CPU 9800X3D t8      7.753(07-30) ->    12.576  n=27  one-off?
  1.62x  to_physical vector measure         Float32 256^3    CPU 12700K t1     125.496(08-07) ->   203.555  n=27  PERSISTENT
  1.62x  to_physical scalar measure         Float32 512^3    CPU 9800X3D t1    290.357(07-30) ->   470.885  n=27  PERSISTENT
  1.62x  to_spectral scalar                 Float64 256^3    CPU 12700K t4      46.038(08-07) ->    74.508  n=27  PERSISTENT
  1.62x  to_spectral scalar measure         Float32 512^3    CPU 9800X3D t2    165.853(08-09) ->   268.337  n=27  PERSISTENT
  1.61x  to_spectral scalar measure         Float64 256^3    CPU 9800X3D t2     36.865(08-09) ->    59.437  n=27  PERSISTENT
  1.59x  exponential_convolve! scalar       Float32 256^3    CPU 12700K t2      13.310(07-30) ->    21.168  n=27  one-off?
  1.57x  to_physical vector                 Float64 128^3    CPU 12700K t2      19.672(08-07) ->    30.903  n=27  PERSISTENT
  1.57x  to_physical vector measure         Float32 256^3    CPU 12700K t4      75.629(08-07) ->   118.558  n=27  PERSISTENT
  1.56x  to_spectral vector measure         Float64 128^3    CPU 12700K t8      12.680(08-07) ->    19.841  n=27  PERSISTENT
  1.56x  materialize_kernel radial          Float64 512^3    CPU 9800X3D t4     34.030(08-09) ->    53.247  n=27  one-off?
  1.56x  to_physical scalar measure         Float32 512^3    CPU 9800X3D t2    188.250(07-30) ->   292.836  n=27  PERSISTENT
  1.55x  to_spectral vector measure         Float32 256^3    CPU 9800X3D t4     45.865(07-30) ->    71.275  n=27  PERSISTENT
  1.55x  to_physical vector                 Float32 512^3    GPU 7900XTX        36.129(08-07) ->    56.118  n=23  PERSISTENT
  1.55x  to_spectral vector measure         Float64 128^3    CPU 9800X3D t2     12.032(08-09) ->    18.613  n=27  one-off?
  1.54x  to_physical scalar measure         Float64 256^3    CPU 9800X3D t2     42.443(08-05) ->    65.252  n=27  PERSISTENT
  1.53x  to_physical scalar                 Float64 256^3    CPU 12700K t4      51.637(08-07) ->    79.237  n=27  PERSISTENT
  1.53x  anterpolate! Lalescu(3,3)          Float64 512^3    CPU 9800X3D t4   3307.000(08-28) ->  5053.000  n=27  PERSISTENT
  1.53x  to_physical scalar measure         Float64 256^3    CPU 12700K t4      49.714(08-07) ->    75.893  n=27  PERSISTENT
  1.52x  to_physical scalar measure         Float32 512^3    CPU 9800X3D t4    145.316(07-30) ->   221.111  n=27  PERSISTENT
  1.51x  to_physical scalar measure         Float32 512^3    CPU 12700K t2     274.759(08-07) ->   415.796  n=23  PERSISTENT
  1.51x  anterpolate! Lalescu(3,3)          Float64 512^3    CPU 9800X3D t1  12551.000(07-30) -> 18985.000  n=27  PERSISTENT
  1.51x  to_physical vector measure         Float64 128^3    CPU 9800X3D t2     12.492(08-09) ->    18.895  n=27  one-off?
  1.51x  to_physical scalar measure         Float32 512^3    CPU 9800X3D t8    131.139(08-10) ->   197.481  n=27  PERSISTENT
  1.49x  anterpolate! Lalescu(3,3)          Float64 512^3    CPU 9800X3D t2   6404.000(08-09) ->  9557.000  n=27  PERSISTENT
  1.48x  to_physical scalar                 Float64 256^3    CPU 9800X3D t2     49.727(08-05) ->    73.588  n=27  PERSISTENT
  1.47x  interpolate! NUFFT                 Float64 256^3    GPU 7900XTX        40.571(08-07) ->    59.798  n=23  PERSISTENT
  1.47x  interpolate! CatmullRom            Float64 256^3    GPU 7900XTX         1.048(08-07) ->     1.540  n=23  PERSISTENT

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
