# Benchmark results

Minimum time per operation; `—` = not measured for that column (a device / grid / element-type combination not run). Generated 2026-08-31 at commit `6581b433` on Julia 1.12.7, assembled on host `Enteropia` — a **multi-host** report (each device names its own host below). Columns are the supplied runs; grids and element types are in the row labels. **CPUs** — thread sweep 1/2/4/8: **i7-12700K** (8 P-cores — `Aiporetne`, 64³–**512³** both element types) and **Ryzen 9800X3D** (8 Zen 5 cores / 16 threads, 96 MB 3D V-Cache — `Enteropia`, 64³–**512³** both element types — the CPU production band of ARCHITECTURE.md decision 37; RAM bounds nothing at 123 GB); both CPU columns are measured at the decision-38/39 rewrite — slab-threaded assignments and the fused one-pass kernels, so thread scaling is monotone (the retired inversion the previous archive carried is finding (l) in PERFORMANCE.md §4). Both CPU columns now carry post-decision-40 threaded reductions — the fixed-tree reduce scaling monotonically with thread count (e.g. `maximum scalar` 128³ Float64, 9800X3D: 442 → 59 µs t1→t8) — so the reductions cells are cross-host comparable. **GPUs**, newest last: **RX 7900 XTX** (gfx1100, ROCm, 24 GB, power-capped 294 W — `Aiporetne`, 64³–256³ both types + 512³ `Float32`, the `transfer` and `reductions` classes omitted at 512³ — transfer's NUFFT oversamples to 1024³ and the radial diagnostics' working set hits the 24 GB ceiling); **RTX 5070 Ti** (Blackwell sm_120, CUDA, 16 GB — `Enteropia`, 64³–256³ both types; 512³ exceeds 16 GB — the `mul!` tensor field alone is 4.5 GB). **Two columns for since-retired cards were DROPPED on 2026-08-07** — both were measured under the `gcsample` regime of PERFORMANCE.md §4(s), which inflated device rows 2–29×, and neither card is in the fleet to re-sweep, so those columns could never be corrected or compared against anything measured after the fix. Every remaining column is measured at the decision-38/39 rewrite. **Both GPU columns are now in the fixed measurement regime and are comparable again.** Device lanes used to run with a blanket `gcsample = true`, so a full `GC.gc()` — whose finalizers free device buffers and synchronize — preceded every sample and dominated operations lasting tens of microseconds, inflating device rows 18.4–29.2× at ``64^3``, 5.8–19.8× at ``128^3`` and 1.9–4.25× at ``256^3`` on the AMD card. `gcsample` is now decided per row from a measured device-pool probe and kept only for rows that genuinely materialize. **GPU 7900XTX was re-swept 2026-08-07** (median −81.6%) and **GPU 5070TI on 2026-08-09** (median −46.4% over 426 rows). The NVIDIA correction is the smaller of the two because that vendor's collect-and-synchronize is cheaper, not because less was wrong: the CUDA branch of the probe called `CUDA.available_memory`, which is not a binding, so it threw on every row and the catch-all held every CUDA row on the collector until 2026-08-09 — see PERFORMANCE.md §4(w), and note that a fallback reported as a measurement is the reason that went unnoticed. CPU columns were never affected, `gcsample` being gated on the backend. See PERFORMANCE.md §4(s). **`fft` rows are comparable only within a column vintage, and the 2026-08-05 shift is `Enteropia`-specific.** That re-sweep of the 9800X3D lanes found the `fft` class 20–50% slower than the 2026-07-30 archive at the larger grids (``256^3`` `Float64` `to_physical scalar` t1: 83.8 → 116.0 ms), reproducible to under 1% across three standalone probes, while the other 596 rows moved by a median of −0.12% and the cuFFT lane showed no `fft` mover at all. It is not the package (zero changed lines on the transform path), not FFTW, and not Julia; a reboot fell between the two sweeps and no pre-reboot platform state was recorded. **The 2026-08-07 `Aiporetne` re-sweep is the control, and at the larger grids the shift does not reproduce:** across that host's 192 `fft` rows (four lanes × 48) against its 2026-07-22 archive, exactly **one** row at ``256^3`` moved slower and by +1.0%, where `Enteropia` moved +38%; per-lane medians run −4.5% to −6.8%. Twenty-three rows did move slower, but all except that one sit at ``64^3``/``128^3``, and the three exceeding 20% are small-grid high-thread-count cells where thread overhead dominates a sub-millisecond workload. This host's rows moved materially *faster* at the larger grids (up to a ratio of 0.54), which is no better explained, so a cross-vintage `fft` comparison is uninformative rather than evidence. `Aiporetne` runs kernel `7.0.0-28-generic`, the same version `Enteropia` recorded post-reboot, so a platform-wide kernel or microcode regression is not supported. **The 2026-08-09 `Enteropia` re-sweep settles it: the shift was a ONE-OFF, not a persistent state change.** Re-measuring t1/t2/t4 against the 2026-08-05 archive over an interval with no source changes, the `fft` class is flat — per-lane medians −1.1% to −1.4%, and at ``256^3`` specifically −3.7%, −6.5% and −1.2%, where the event being explained was +20–50%. Every other class is flat too (600 rows per lane, overall medians +0.0%, −0.2%, −0.2%), so the sweep reproduces itself and the instrument is sound. Those three lanes are also the first archives carrying stamped platform state (kernel, microcode, governor, SMT, transparent huge pages), so a recurrence is now falsifiable instead of unattributable. See PERFORMANCE.md §4(p). **Five CPU rows are process-history-sensitive and comparable only against same-shaped sweeps — PERFORMANCE.md §4(y).** The two `materialize_kernel` rows, `lpnorm vec Inf`, `radial_correlation vec` and `cross-correlation vec.vec` measure faster at low thread counts inside a full sweep than standalone (up to ``3.2\times`` for `materialize_kernel` at ``t1``, ``1.2``–``1.7\times`` for the reductions three), because their per-call field-sized allocation lands in a regime selected by what streamed through the process before them; the eight allocating `fft` rows are verified clean. Every CPU column here is a full sweep, so the table is self-consistent, but those cells must not be compared against a standalone probe or a class-only lane, and `materialize_kernel` thread scaling should be read from ``t4`` upward (the ``t2`` cell of `materialize_kernel separable` is bistable across sweeps). **The `CPU 9800X3D t8` column was assembled from FOUR per-grid runs, not one lane.** A single `-t8` process segfaults on `Enteropia` inside FFTW's threaded executor — PERFORMANCE.md §4(q), reproducible there and never seen on the other host — and failed three times running. Splitting the lane by grid (`CHAR_SIZES=64`, then 128, 256, 512) completes it: 64³, 256³ and 512³ passed first time and 128³ on its second attempt, and the four part-archives merge into one lane archive with disjoint rows, 150 per grid. That is what an uncrashed process would have written, and it is a harness workaround rather than a fix — the fault is unchanged and a plain `characterize.jl` invocation at `-t8` will still die here. The merged column is flat against the 2026-08-05 one it replaces (median +0.0% over 600 rows), and its largest movers are the `measure` twins, whose FFTW `MEASURE` plan search legitimately re-decides between runs. A row may name an operation the package has since REMOVED — `squared_wavenumber_field` was deleted by decision 60, its |k|² being a radial symbol rather than a field. Such rows are a historical measurement, not a callable surface, and they disappear the next time their lane is swept. The GPU sweep builds one (op-class, grid, element-type) at a time so the working set stays bounded (PERFORMANCE.md §7). **Regenerate** by re-sweeping the lanes you can measure — `characterize.jl` once per lane — and then invoking `report.jl` by hand over **every** archive in `benchmark/results/`, this table's own column list included. Do not use `characterize.sh` for a multi-host report: it passes only the lanes it just produced to `report.jl`, so the columns belonging to the other host and to retired cards would silently vanish (PERFORMANCE.md §6). **Column vintages** — the commit (and sweep date) each archive was measured at, stamped into its JSON by `characterize.jl`: `6581b433 @ 2026-08-31`: CPU 9800X3D t1, CPU 9800X3D t2, CPU 9800X3D t4, CPU 9800X3D t8, GPU 5070TI; `93d9d8da @ 2026-08-07`: GPU 7900XTX; `bd1e4f30 @ 2026-08-07`: CPU 12700K t1, CPU 12700K t2, CPU 12700K t4, CPU 12700K t8. **Jitter is ~10% for most cells but NOT uniform: it reaches 1.44x at small grids under high thread counts.** Measured on the 12700K, `mean(norm) vec` `Float32`, five repeats of the same measurement: at ``64^3`` `-t8` the minimum came out 31.2, 31.0, 31.3, 30.8 and 44.4 us, where the same row at `-t1` spans 1.01x and at ``256^3`` `-t8` spans 1.09x. The work there (~31 us) is comparable to the cost of spawning eight threads, and taking BenchmarkTools' minimum over a one-second budget does not suppress it. So a movement of tens of percent in a small-grid, high-thread cell is NOT evidence of anything; compare those at ``256^3`` or above, or at low thread counts. PERFORMANCE.md §4(u).

## fft

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| to_physical scalar measure | Float32 128^3 | 3.940 ms | 2.704 ms | 2.251 ms | 2.117 ms | 2.741 ms | 1.470 ms | 826.698 μs | 526.025 μs | — | — |
| to_physical scalar measure | Float32 256^3 | 41.346 ms | 28.361 ms | 23.974 ms | 23.526 ms | 32.865 ms | 20.339 ms | 14.660 ms | 11.720 ms | — | — |
| to_physical scalar measure | Float32 512^3 | 520.095 ms | 274.759 ms | 231.175 ms | 274.469 ms | 470.885 ms | 292.836 ms | 221.111 ms | 197.481 ms | — | — |
| to_physical scalar measure | Float32 64^3 | 371.922 μs | 241.902 μs | 160.965 μs | 141.497 μs | 276.223 μs | 157.201 μs | 95.731 μs | 71.040 μs | — | — |
| to_physical scalar measure | Float64 128^3 | 6.068 ms | 5.522 ms | 5.182 ms | 4.508 ms | 3.854 ms | 2.249 ms | 1.650 ms | 1.202 ms | — | — |
| to_physical scalar measure | Float64 256^3 | 103.157 ms | 70.830 ms | 49.714 ms | 56.313 ms | 83.575 ms | 65.252 ms | 41.326 ms | 45.523 ms | — | — |
| to_physical scalar measure | Float64 512^3 | 1.102 s | 720.100 ms | 657.297 ms | 618.290 ms | 832.369 ms | 553.215 ms | 441.802 ms | 401.231 ms | — | — |
| to_physical scalar measure | Float64 64^3 | 545.365 μs | 351.124 μs | 260.592 μs | 226.641 μs | 363.403 μs | 206.932 μs | 131.771 μs | 104.641 μs | — | — |
| to_physical scalar | Float32 128^3 | 4.920 ms | 3.213 ms | 2.415 ms | 2.308 ms | 4.515 ms | 2.467 ms | 1.290 ms | 774.129 μs | 114.940 μs | 68.131 μs |
| to_physical scalar | Float32 256^3 | 88.021 ms | 49.841 ms | 33.533 ms | 26.385 ms | 169.531 ms | 88.437 ms | 48.038 ms | 27.683 ms | 1.114 ms | 1.101 ms |
| to_physical scalar | Float32 512^3 | 1.309 s | 667.091 ms | 506.857 ms | 390.054 ms | 2.091 s | 1.111 s | 628.272 ms | 390.847 ms | 13.304 ms | — |
| to_physical scalar | Float32 64^3 | 384.770 μs | 252.646 μs | 166.414 μs | 146.793 μs | 313.063 μs | 176.522 μs | 101.081 μs | 70.561 μs | 61.998 μs | 19.910 μs |
| to_physical scalar | Float64 128^3 | 7.749 ms | 5.805 ms | 4.775 ms | 4.337 ms | 10.220 ms | 5.748 ms | 3.240 ms | 1.832 ms | 308.747 μs | 430.765 μs |
| to_physical scalar | Float64 256^3 | 127.268 ms | 80.088 ms | 51.637 ms | 52.488 ms | 96.212 ms | 73.588 ms | 43.827 ms | 46.465 ms | 2.851 ms | 3.769 ms |
| to_physical scalar | Float64 512^3 | 1.450 s | 892.696 ms | 709.422 ms | 633.442 ms | 929.667 ms | 600.455 ms | 448.057 ms | 398.602 ms | — | — |
| to_physical scalar | Float64 64^3 | 672.104 μs | 404.924 μs | 286.897 μs | 276.351 μs | 541.035 μs | 285.503 μs | 167.101 μs | 119.981 μs | 87.954 μs | 51.691 μs |
| to_physical vector measure | Float32 128^3 | 11.689 ms | 8.998 ms | 8.221 ms | 7.647 ms | 9.154 ms | 5.602 ms | 3.467 ms | 2.856 ms | — | — |
| to_physical vector measure | Float32 256^3 | 125.496 ms | 94.289 ms | 75.629 ms | 74.747 ms | 137.574 ms | 102.731 ms | 77.814 ms | 65.963 ms | — | — |
| to_physical vector measure | Float32 512^3 | 1.861 s | 1.311 s | 1.015 s | 912.763 ms | 1.413 s | 879.623 ms | 667.473 ms | 606.716 ms | — | — |
| to_physical vector measure | Float32 64^3 | 1.231 ms | 809.758 μs | 564.304 μs | 498.312 μs | 838.729 μs | 495.995 μs | 287.572 μs | 222.152 μs | — | — |
| to_physical vector measure | Float64 128^3 | 30.774 ms | 18.363 ms | 21.288 ms | 27.609 ms | 27.389 ms | 18.895 ms | 14.290 ms | 12.655 ms | — | — |
| to_physical vector measure | Float64 256^3 | 361.550 ms | 268.443 ms | 234.660 ms | 227.607 ms | 306.744 ms | 207.171 ms | 154.652 ms | 139.071 ms | — | — |
| to_physical vector measure | Float64 512^3 | 3.338 s | 2.365 s | 2.031 s | 1.797 s | 2.500 s | 1.667 s | 1.291 s | 1.165 s | — | — |
| to_physical vector measure | Float64 64^3 | 1.988 ms | 1.748 ms | 1.271 ms | 1.358 ms | 1.120 ms | 658.326 μs | 408.014 μs | 330.304 μs | — | — |
| to_physical vector | Float32 128^3 | 14.719 ms | 11.254 ms | 7.979 ms | 7.291 ms | 9.295 ms | 5.558 ms | 3.494 ms | 2.925 ms | 349.248 μs | 230.012 μs |
| to_physical vector | Float32 256^3 | 263.761 ms | 187.728 ms | 116.684 ms | 97.607 ms | 138.275 ms | 105.406 ms | 75.964 ms | 64.894 ms | 5.600 ms | 3.227 ms |
| to_physical vector | Float32 512^3 | 4.218 s | 2.962 s | 1.764 s | 1.387 s | 1.386 s | 876.509 ms | 665.338 ms | 605.880 ms | 36.129 ms | — |
| to_physical vector | Float32 64^3 | 1.273 ms | 984.725 μs | 561.725 μs | 481.941 μs | 845.299 μs | 480.115 μs | 288.233 μs | 224.932 μs | 71.413 μs | 45.160 μs |
| to_physical vector | Float64 128^3 | 35.147 ms | 19.672 ms | 25.810 ms | 25.688 ms | 27.376 ms | 18.902 ms | 14.200 ms | 13.114 ms | 960.784 μs | 1.352 ms |
| to_physical vector | Float64 256^3 | 435.564 ms | 343.093 ms | 242.970 ms | 228.550 ms | 298.434 ms | 204.938 ms | 155.768 ms | 139.525 ms | 12.478 ms | 11.385 ms |
| to_physical vector | Float64 512^3 | 4.538 s | 3.422 s | 2.259 s | 2.009 s | 2.488 s | 1.673 s | 1.288 s | 1.163 s | — | — |
| to_physical vector | Float64 64^3 | 2.542 ms | 2.131 ms | 1.398 ms | 1.193 ms | 1.114 ms | 685.977 μs | 399.914 μs | 335.193 μs | 143.480 μs | 145.492 μs |
| to_physical! scalar scratch | Float32 128^3 | — | — | — | — | 4.497 ms | 2.482 ms | 1.266 ms | 778.209 μs | — | 65.141 μs |
| to_physical! scalar scratch | Float32 256^3 | — | — | — | — | 166.684 ms | 87.438 ms | 46.212 ms | 25.776 ms | — | 1.029 ms |
| to_physical! scalar scratch | Float32 512^3 | — | — | — | — | 1.967 s | 1.025 s | 555.355 ms | 325.957 ms | — | — |
| to_physical! scalar scratch | Float32 64^3 | — | — | — | — | 317.243 μs | 171.262 μs | 100.741 μs | 70.591 μs | — | 17.731 μs |
| to_physical! scalar scratch | Float64 128^3 | — | — | — | — | 9.717 ms | 5.018 ms | 2.721 ms | 1.579 ms | — | 427.915 μs |
| to_physical! scalar scratch | Float64 256^3 | — | — | — | — | 81.387 ms | 50.470 ms | 35.438 ms | 29.930 ms | — | 3.769 ms |
| to_physical! scalar scratch | Float64 512^3 | — | — | — | — | 702.588 ms | 434.304 ms | 310.934 ms | 271.286 ms | — | — |
| to_physical! scalar scratch | Float64 64^3 | — | — | — | — | 528.076 μs | 288.003 μs | 167.142 μs | 118.271 μs | — | 49.620 μs |
| to_physical! scalar | Float32 128^3 | — | — | — | — | 4.370 ms | 2.252 ms | 1.132 ms | 620.057 μs | — | 58.870 μs |
| to_physical! scalar | Float32 256^3 | — | — | — | — | 164.478 ms | 83.934 ms | 42.697 ms | 22.781 ms | — | 850.858 μs |
| to_physical! scalar | Float32 512^3 | — | — | — | — | 1.950 s | 1.005 s | 529.932 ms | 299.536 ms | — | — |
| to_physical! scalar | Float32 64^3 | — | — | — | — | 298.413 μs | 155.592 μs | 84.671 μs | 54.211 μs | — | 16.041 μs |
| to_physical! scalar | Float64 128^3 | — | — | — | — | 9.736 ms | 4.800 ms | 2.475 ms | 1.318 ms | — | 398.034 μs |
| to_physical! scalar | Float64 256^3 | — | — | — | — | 72.113 ms | 41.029 ms | 25.977 ms | 19.805 ms | — | 3.414 ms |
| to_physical! scalar | Float64 512^3 | — | — | — | — | 654.203 ms | 380.884 ms | 257.571 ms | 217.113 ms | — | — |
| to_physical! scalar | Float64 64^3 | — | — | — | — | 496.455 μs | 257.522 μs | 139.042 μs | 86.831 μs | — | 47.601 μs |
| to_physical! vector scratch | Float32 128^3 | — | — | — | — | 8.169 ms | 4.452 ms | 2.564 ms | 1.622 ms | — | 229.302 μs |
| to_physical! vector scratch | Float32 256^3 | — | — | — | — | 109.554 ms | 63.699 ms | 45.443 ms | 38.446 ms | — | 3.079 ms |
| to_physical! vector scratch | Float32 512^3 | — | — | — | — | 950.944 ms | 560.095 ms | 428.103 ms | 388.272 ms | — | — |
| to_physical! vector scratch | Float32 64^3 | — | — | — | — | 844.139 μs | 471.465 μs | 286.313 μs | 224.302 μs | — | 42.261 μs |
| to_physical! vector scratch | Float64 128^3 | — | — | — | — | 14.385 ms | 8.749 ms | 5.818 ms | 4.548 ms | — | 1.353 ms |
| to_physical! vector scratch | Float64 256^3 | — | — | — | — | 206.563 ms | 132.204 ms | 98.447 ms | 87.833 ms | — | 11.287 ms |
| to_physical! vector scratch | Float64 512^3 | — | — | — | — | 1.712 s | 1.102 s | 861.969 ms | 770.124 ms | — | — |
| to_physical! vector scratch | Float64 64^3 | — | — | — | — | 1.088 ms | 636.316 μs | 379.794 μs | 320.603 μs | — | 142.071 μs |
| to_physical! vector | Float32 128^3 | — | — | — | — | 7.741 ms | 4.056 ms | 2.146 ms | 1.204 ms | — | 187.692 μs |
| to_physical! vector | Float32 256^3 | — | — | — | — | 102.650 ms | 51.708 ms | 34.841 ms | 27.418 ms | — | 2.551 ms |
| to_physical! vector | Float32 512^3 | — | — | — | — | 869.878 ms | 485.420 ms | 352.148 ms | 313.204 ms | — | — |
| to_physical! vector | Float32 64^3 | — | — | — | — | 804.218 μs | 424.804 μs | 244.942 μs | 177.722 μs | — | 40.310 μs |
| to_physical! vector | Float64 128^3 | — | — | — | — | 12.715 ms | 7.144 ms | 4.127 ms | 2.547 ms | — | 1.217 ms |
| to_physical! vector | Float64 256^3 | — | — | — | — | 186.633 ms | 110.856 ms | 76.230 ms | 68.368 ms | — | 10.229 ms |
| to_physical! vector | Float64 512^3 | — | — | — | — | 1.560 s | 955.105 ms | 721.959 ms | 620.863 ms | — | — |
| to_physical! vector | Float64 64^3 | — | — | — | — | 1.006 ms | 560.975 μs | 304.343 μs | 218.172 μs | — | 137.522 μs |
| to_spectral scalar measure | Float32 128^3 | 3.332 ms | 2.325 ms | 1.567 ms | 1.196 ms | 2.685 ms | 1.437 ms | 800.378 μs | 462.585 μs | — | — |
| to_spectral scalar measure | Float32 256^3 | 35.032 ms | 22.432 ms | 19.125 ms | 18.101 ms | 35.394 ms | 19.824 ms | 13.714 ms | 10.635 ms | — | — |
| to_spectral scalar measure | Float32 512^3 | 488.544 ms | 224.043 ms | 271.721 ms | 267.653 ms | 451.337 ms | 268.337 ms | 192.895 ms | 166.208 ms | — | — |
| to_spectral scalar measure | Float32 64^3 | 362.043 μs | 202.388 μs | 136.870 μs | 98.325 μs | 271.472 μs | 145.871 μs | 85.341 μs | 61.531 μs | — | — |
| to_spectral scalar measure | Float64 128^3 | 5.352 ms | 4.279 ms | 3.655 ms | 3.403 ms | 3.892 ms | 2.367 ms | 1.339 ms | 1.195 ms | — | — |
| to_spectral scalar measure | Float64 256^3 | 96.587 ms | 68.564 ms | 38.813 ms | 62.826 ms | 76.259 ms | 59.437 ms | 37.132 ms | 38.240 ms | — | — |
| to_spectral scalar measure | Float64 512^3 | 1.088 s | 631.184 ms | 567.274 ms | 527.390 ms | 748.122 ms | 491.860 ms | 365.948 ms | 332.342 ms | — | — |
| to_spectral scalar measure | Float64 64^3 | 498.914 μs | 294.077 μs | 194.581 μs | 228.182 μs | 347.013 μs | 192.922 μs | 108.801 μs | 81.090 μs | — | — |
| to_spectral scalar | Float32 128^3 | 4.355 ms | 2.699 ms | 1.747 ms | 1.679 ms | 4.636 ms | 2.402 ms | 1.254 ms | 722.728 μs | 77.694 μs | 40.670 μs |
| to_spectral scalar | Float32 256^3 | 84.124 ms | 45.903 ms | 29.063 ms | 21.624 ms | 169.465 ms | 87.023 ms | 46.184 ms | 26.272 ms | 651.168 μs | 681.007 μs |
| to_spectral scalar | Float32 512^3 | 1.289 s | 647.466 ms | 480.683 ms | 353.029 ms | 2.079 s | 1.093 s | 596.845 ms | 356.814 ms | 9.570 ms | — |
| to_spectral scalar | Float32 64^3 | 363.076 μs | 209.386 μs | 130.953 μs | 105.406 μs | 303.693 μs | 163.862 μs | 91.541 μs | 59.470 μs | 51.190 μs | 14.490 μs |
| to_spectral scalar | Float64 128^3 | 6.933 ms | 5.128 ms | 3.945 ms | 3.368 ms | 10.074 ms | 5.423 ms | 2.980 ms | 1.961 ms | 257.021 μs | 381.024 μs |
| to_spectral scalar | Float64 256^3 | 140.834 ms | 87.104 ms | 46.038 ms | 64.462 ms | 189.509 ms | 116.399 ms | 62.541 ms | 52.773 ms | 2.430 ms | 3.080 ms |
| to_spectral scalar | Float64 512^3 | 1.577 s | 880.360 ms | 659.997 ms | 549.715 ms | 1.705 s | 966.768 ms | 578.855 ms | 428.255 ms | — | — |
| to_spectral scalar | Float64 64^3 | 631.171 μs | 355.908 μs | 222.473 μs | 195.482 μs | 511.795 μs | 271.733 μs | 152.282 μs | 95.551 μs | 77.482 μs | 45.430 μs |
| to_spectral vector measure | Float32 128^3 | 10.269 ms | 7.369 ms | 5.918 ms | 5.451 ms | 9.426 ms | 5.215 ms | 3.087 ms | 2.342 ms | — | — |
| to_spectral vector measure | Float32 256^3 | 106.816 ms | 72.627 ms | 59.081 ms | 58.272 ms | 140.353 ms | 99.201 ms | 71.275 ms | 58.785 ms | — | — |
| to_spectral vector measure | Float32 512^3 | 1.730 s | 1.170 s | 869.340 ms | 751.569 ms | 1.338 s | 804.527 ms | 574.464 ms | 511.137 ms | — | — |
| to_spectral vector measure | Float32 64^3 | 1.124 ms | 689.278 μs | 468.611 μs | 381.687 μs | 825.738 μs | 444.974 μs | 254.563 μs | 186.812 μs | — | — |
| to_spectral vector measure | Float64 128^3 | 27.195 ms | 15.470 ms | 22.360 ms | 12.680 ms | 27.344 ms | 18.613 ms | 14.080 ms | 12.576 ms | — | — |
| to_spectral vector measure | Float64 256^3 | 342.075 ms | 244.051 ms | 198.161 ms | 185.245 ms | 275.949 ms | 181.730 ms | 136.881 ms | 116.291 ms | — | — |
| to_spectral vector measure | Float64 512^3 | 3.271 s | 2.198 s | 1.720 s | 1.513 s | 2.212 s | 1.452 s | 1.106 s | 960.812 ms | — | — |
| to_spectral vector measure | Float64 64^3 | 1.791 ms | 1.443 ms | 985.889 μs | 718.537 μs | 1.045 ms | 608.536 μs | 331.503 μs | 257.183 μs | — | — |
| to_spectral vector | Float32 128^3 | 13.253 ms | 9.696 ms | 6.487 ms | 5.719 ms | 9.391 ms | 5.131 ms | 3.021 ms | 2.830 ms | 198.619 μs | 157.442 μs |
| to_spectral vector | Float32 256^3 | 257.120 ms | 178.171 ms | 99.371 ms | 80.132 ms | 142.580 ms | 98.693 ms | 72.328 ms | 59.016 ms | 3.517 ms | 2.108 ms |
| to_spectral vector | Float32 512^3 | 4.109 s | 2.923 s | 1.634 s | 1.256 s | 1.334 s | 806.638 ms | 578.991 ms | 520.876 ms | 25.678 ms | — |
| to_spectral vector | Float32 64^3 | 1.205 ms | 875.734 μs | 475.570 μs | 395.918 μs | 830.748 μs | 437.094 μs | 255.833 μs | 191.842 μs | 60.315 μs | 30.041 μs |
| to_spectral vector | Float64 128^3 | 32.548 ms | 18.443 ms | 22.319 ms | 12.273 ms | 28.464 ms | 18.736 ms | 13.610 ms | 12.296 ms | 783.462 μs | 1.159 ms |
| to_spectral vector | Float64 256^3 | 488.801 ms | 367.693 ms | 232.568 ms | 204.396 ms | 280.845 ms | 183.201 ms | 133.491 ms | 115.841 ms | 11.643 ms | 9.237 ms |
| to_spectral vector | Float64 512^3 | 4.975 s | 3.661 s | 2.193 s | 1.837 s | 2.185 s | 1.447 s | 1.104 s | 967.678 ms | — | — |
| to_spectral vector | Float64 64^3 | 2.079 ms | 1.860 ms | 1.176 ms | 806.065 μs | 1.046 ms | 585.756 μs | 331.263 μs | 249.523 μs | 126.340 μs | 125.131 μs |

## algebra

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| add! scalar | Float32 128^3 | 388.209 μs | 236.369 μs | 170.421 μs | 74.913 μs | 162.312 μs | 84.191 μs | 44.031 μs | 35.670 μs | 60.557 μs | 34.360 μs |
| add! scalar | Float32 256^3 | 8.073 ms | 7.299 ms | 5.615 ms | 5.178 ms | 3.481 ms | 3.003 ms | 2.759 ms | 2.805 ms | 347.110 μs | 273.212 μs |
| add! scalar | Float32 512^3 | 68.673 ms | 62.603 ms | 48.877 ms | 45.609 ms | 40.662 ms | 36.891 ms | 36.798 ms | 37.219 ms | 2.556 ms | — |
| add! scalar | Float32 64^3 | 42.178 μs | 22.703 μs | 10.208 μs | 9.854 μs | 20.470 μs | 12.250 μs | 7.080 μs | 6.897 μs | 30.954 μs | 10.190 μs |
| add! scalar | Float64 128^3 | 1.461 ms | 1.286 ms | 958.019 μs | 807.698 μs | 324.114 μs | 164.221 μs | 86.110 μs | 72.861 μs | 61.219 μs | 38.570 μs |
| add! scalar | Float64 256^3 | 15.938 ms | 15.300 ms | 11.800 ms | 10.935 ms | 10.258 ms | 8.539 ms | 8.442 ms | 8.567 ms | 537.938 μs | 511.885 μs |
| add! scalar | Float64 512^3 | 136.659 ms | 126.580 ms | 97.743 ms | 91.293 ms | 83.871 ms | 72.244 ms | 73.742 ms | 74.035 ms | — | — |
| add! scalar | Float64 64^3 | 83.825 μs | 51.628 μs | 21.309 μs | 18.978 μs | 40.200 μs | 22.700 μs | 12.170 μs | 9.420 μs | 32.169 μs | 10.160 μs |
| combine! vec | Float32 128^3 | 2.597 ms | 2.332 ms | 1.819 ms | 1.600 ms | 650.586 μs | 315.543 μs | 167.392 μs | 115.561 μs | 190.915 μs | 131.502 μs |
| combine! vec | Float32 256^3 | 25.251 ms | 23.119 ms | 18.200 ms | 16.717 ms | 13.661 ms | 13.987 ms | 13.429 ms | 13.769 ms | 1.359 ms | 966.100 μs |
| combine! vec | Float32 512^3 | 207.335 ms | 185.538 ms | 148.923 ms | 138.000 ms | 114.404 ms | 110.351 ms | 110.841 ms | 111.140 ms | 11.362 ms | — |
| combine! vec | Float32 64^3 | 126.992 μs | 69.138 μs | 39.003 μs | 20.367 μs | 62.761 μs | 38.750 μs | 20.000 μs | 14.851 μs | 46.555 μs | 22.130 μs |
| combine! vec | Float64 128^3 | 5.894 ms | 5.405 ms | 4.131 ms | 3.742 ms | 2.205 ms | 1.778 ms | 1.581 ms | 1.490 ms | 236.950 μs | 193.102 μs |
| combine! vec | Float64 256^3 | 49.976 ms | 46.284 ms | 36.866 ms | 34.033 ms | 28.681 ms | 26.750 ms | 27.113 ms | 27.444 ms | 1.665 ms | 1.533 ms |
| combine! vec | Float64 512^3 | 407.338 ms | 375.527 ms | 293.122 ms | 275.044 ms | 233.665 ms | 217.929 ms | 220.731 ms | 221.675 ms | — | — |
| combine! vec | Float64 64^3 | 260.077 μs | 140.990 μs | 81.376 μs | 46.383 μs | 123.461 μs | 64.171 μs | 34.581 μs | 28.270 μs | 48.695 μs | 22.201 μs |
| cross! | Float32 128^3 | 2.931 ms | 2.398 ms | 2.118 ms | 1.967 ms | 2.017 ms | 993.451 μs | 499.146 μs | 249.073 μs | 51.046 μs | 85.151 μs |
| cross! | Float32 256^3 | 27.269 ms | 24.773 ms | 23.393 ms | 22.109 ms | 23.285 ms | 14.622 ms | 12.569 ms | 12.632 ms | 853.987 μs | 771.408 μs |
| cross! | Float32 512^3 | 227.705 ms | 202.770 ms | 192.348 ms | 183.951 ms | 174.385 ms | 121.423 ms | 110.867 ms | 110.566 ms | 7.355 ms | — |
| cross! | Float32 64^3 | 256.097 μs | 132.155 μs | 68.616 μs | 38.814 μs | 230.892 μs | 115.981 μs | 58.990 μs | 32.890 μs | 35.411 μs | 9.070 μs |
| cross! | Float64 128^3 | 6.250 ms | 5.759 ms | 5.075 ms | 4.877 ms | 3.783 ms | 2.303 ms | 1.586 ms | 1.477 ms | 231.569 μs | 196.411 μs |
| cross! | Float64 256^3 | 52.123 ms | 50.663 ms | 47.305 ms | 45.604 ms | 42.187 ms | 30.200 ms | 27.441 ms | 27.531 ms | 1.639 ms | 1.539 ms |
| cross! | Float64 512^3 | 412.992 ms | 409.844 ms | 382.736 ms | 369.731 ms | 334.645 ms | 231.727 ms | 222.479 ms | 224.392 ms | — | — |
| cross! | Float64 64^3 | 358.517 μs | 184.977 μs | 96.655 μs | 54.729 μs | 224.912 μs | 115.441 μs | 58.710 μs | 36.810 μs | 40.744 μs | 14.790 μs |
| det! tensor | Float32 128^3 | 3.328 ms | 2.464 ms | 2.006 ms | 1.795 ms | 2.168 ms | 1.086 ms | 546.435 μs | 287.303 μs | 74.568 μs | 101.961 μs |
| det! tensor | Float32 256^3 | 33.753 ms | 25.624 ms | 22.255 ms | 19.874 ms | 32.872 ms | 15.652 ms | 12.173 ms | 11.999 ms | 935.334 μs | 826.488 μs |
| det! tensor | Float32 512^3 | 246.816 ms | 196.652 ms | 180.822 ms | 165.881 ms | 230.659 ms | 124.103 ms | 104.614 ms | 103.552 ms | 7.869 ms | — |
| det! tensor | Float32 64^3 | 306.996 μs | 162.094 μs | 81.729 μs | 46.453 μs | 250.702 μs | 128.311 μs | 66.000 μs | 36.211 μs | 41.205 μs | 10.880 μs |
| det! tensor | Float64 128^3 | 6.405 ms | 5.546 ms | 4.775 ms | 4.289 ms | 4.019 ms | 2.384 ms | 1.676 ms | 1.618 ms | 249.941 μs | 197.562 μs |
| det! tensor | Float64 256^3 | 48.213 ms | 48.572 ms | 43.502 ms | 39.145 ms | 41.921 ms | 29.273 ms | 25.581 ms | 25.577 ms | 1.764 ms | 1.697 ms |
| det! tensor | Float64 512^3 | 374.082 ms | 400.702 ms | 340.725 ms | 309.426 ms | 426.193 ms | 273.463 ms | 213.736 ms | 211.173 ms | — | — |
| det! tensor | Float64 64^3 | 353.499 μs | 191.768 μs | 105.859 μs | 62.011 μs | 253.982 μs | 130.311 μs | 68.020 μs | 42.710 μs | 43.388 μs | 16.210 μs |
| dot! vec.vec | Float32 128^3 | 2.801 ms | 1.659 ms | 1.250 ms | 1.094 ms | 2.448 ms | 1.246 ms | 629.007 μs | 319.764 μs | 83.889 μs | 71.461 μs |
| dot! vec.vec | Float32 256^3 | 23.089 ms | 16.664 ms | 15.307 ms | 13.902 ms | 25.653 ms | 12.291 ms | 8.242 ms | 8.076 ms | 657.554 μs | 610.146 μs |
| dot! vec.vec | Float32 512^3 | 197.477 ms | 138.245 ms | 125.530 ms | 114.873 ms | 167.955 ms | 98.806 ms | 75.324 ms | 75.779 ms | 5.132 ms | — |
| dot! vec.vec | Float32 64^3 | 329.279 μs | 201.884 μs | 104.408 μs | 59.006 μs | 310.603 μs | 159.572 μs | 81.561 μs | 44.430 μs | 34.583 μs | 13.470 μs |
| dot! vec.vec | Float64 128^3 | 4.241 ms | 3.743 ms | 3.108 ms | 2.856 ms | 3.460 ms | 1.728 ms | 889.959 μs | 583.297 μs | 173.709 μs | 134.141 μs |
| dot! vec.vec | Float64 256^3 | 39.060 ms | 35.067 ms | 29.190 ms | 26.830 ms | 32.800 ms | 19.903 ms | 18.548 ms | 18.083 ms | 1.218 ms | 1.157 ms |
| dot! vec.vec | Float64 512^3 | 297.167 ms | 278.968 ms | 232.243 ms | 216.914 ms | 257.743 ms | 158.990 ms | 149.721 ms | 150.451 ms | — | — |
| dot! vec.vec | Float64 64^3 | 337.330 μs | 213.313 μs | 106.683 μs | 63.337 μs | 318.913 μs | 160.472 μs | 81.921 μs | 44.891 μs | 34.942 μs | 13.840 μs |
| map!(+) vec | Float32 128^3 | 2.918 ms | 2.404 ms | 2.077 ms | 1.970 ms | 1.765 ms | 844.519 μs | 419.374 μs | 206.412 μs | 51.024 μs | 79.221 μs |
| map!(+) vec | Float32 256^3 | 27.153 ms | 24.773 ms | 23.295 ms | 22.193 ms | 21.947 ms | 14.284 ms | 12.654 ms | 12.714 ms | 852.095 μs | 772.308 μs |
| map!(+) vec | Float32 512^3 | 224.921 ms | 202.036 ms | 192.171 ms | 183.733 ms | 159.353 ms | 118.575 ms | 110.697 ms | 110.538 ms | 6.801 ms | — |
| map!(+) vec | Float32 64^3 | 246.068 μs | 129.376 μs | 69.145 μs | 37.851 μs | 199.441 μs | 95.671 μs | 48.730 μs | 27.090 μs | 35.155 μs | 9.021 μs |
| map!(+) vec | Float64 128^3 | 6.207 ms | 5.662 ms | 5.053 ms | 4.902 ms | 3.654 ms | 2.268 ms | 1.571 ms | 1.490 ms | 232.656 μs | 196.502 μs |
| map!(+) vec | Float64 256^3 | 51.690 ms | 50.585 ms | 47.081 ms | 45.616 ms | 40.105 ms | 29.720 ms | 27.332 ms | 27.585 ms | 1.624 ms | 1.539 ms |
| map!(+) vec | Float64 512^3 | 408.672 ms | 409.233 ms | 381.435 ms | 368.940 ms | 318.480 ms | 226.374 ms | 221.774 ms | 222.455 ms | — | — |
| map!(+) vec | Float64 64^3 | 347.120 μs | 185.466 μs | 99.091 μs | 55.074 μs | 175.262 μs | 94.001 μs | 48.500 μs | 33.110 μs | 37.006 μs | 12.540 μs |
| map!(det) tensor | Float32 128^3 | 3.299 ms | 2.463 ms | 1.944 ms | 1.780 ms | 2.157 ms | 1.094 ms | 542.775 μs | 285.283 μs | 74.570 μs | 101.531 μs |
| map!(det) tensor | Float32 256^3 | 33.741 ms | 25.569 ms | 21.965 ms | 19.736 ms | 33.013 ms | 15.634 ms | 12.180 ms | 12.028 ms | 930.303 μs | 835.018 μs |
| map!(det) tensor | Float32 512^3 | 245.565 ms | 196.788 ms | 179.313 ms | 164.276 ms | 232.130 ms | 123.654 ms | 104.306 ms | 103.343 ms | 7.522 ms | — |
| map!(det) tensor | Float32 64^3 | 302.407 μs | 157.977 μs | 79.788 μs | 48.134 μs | 249.823 μs | 130.692 μs | 65.381 μs | 36.010 μs | 41.089 μs | 10.780 μs |
| map!(det) tensor | Float64 128^3 | 6.411 ms | 5.559 ms | 4.790 ms | 4.298 ms | 4.069 ms | 2.390 ms | 1.650 ms | 1.615 ms | 262.578 μs | 197.702 μs |
| map!(det) tensor | Float64 256^3 | 48.213 ms | 48.708 ms | 43.442 ms | 39.103 ms | 42.003 ms | 29.110 ms | 25.527 ms | 25.555 ms | 1.763 ms | 1.703 ms |
| map!(det) tensor | Float64 512^3 | 373.637 ms | 400.176 ms | 342.339 ms | 309.659 ms | 399.760 ms | 268.799 ms | 211.647 ms | 210.092 ms | — | — |
| map!(det) tensor | Float64 64^3 | 351.321 μs | 184.872 μs | 107.432 μs | 62.416 μs | 251.312 μs | 129.781 μs | 66.491 μs | 43.280 μs | 42.628 μs | 16.221 μs |
| mul! tensor.vec | Float32 128^3 | 5.085 ms | 4.259 ms | 3.736 ms | 3.545 ms | 3.579 ms | 1.878 ms | 999.160 μs | 800.418 μs | 213.240 μs | 151.131 μs |
| mul! tensor.vec | Float32 256^3 | 48.770 ms | 40.311 ms | 37.044 ms | 34.905 ms | 42.342 ms | 24.902 ms | 23.385 ms | 21.924 ms | 1.440 ms | 1.259 ms |
| mul! tensor.vec | Float32 512^3 | 403.678 ms | 313.946 ms | 302.395 ms | 285.772 ms | 335.639 ms | 216.482 ms | 177.813 ms | 174.639 ms | 11.929 ms | — |
| mul! tensor.vec | Float32 64^3 | 434.693 μs | 234.878 μs | 121.989 μs | 67.468 μs | 369.614 μs | 212.352 μs | 107.151 μs | 59.950 μs | 46.998 μs | 12.820 μs |
| mul! tensor.vec | Float64 128^3 | 10.698 ms | 9.242 ms | 9.156 ms | 8.672 ms | 7.037 ms | 5.284 ms | 4.363 ms | 4.291 ms | 390.915 μs | 319.843 μs |
| mul! tensor.vec | Float64 256^3 | 80.789 ms | 78.511 ms | 74.473 ms | 71.012 ms | 59.582 ms | 49.493 ms | 43.862 ms | 43.564 ms | 2.806 ms | 2.508 ms |
| mul! tensor.vec | Float64 512^3 | 606.952 ms | 632.000 ms | 592.094 ms | 565.883 ms | 584.406 ms | 407.714 ms | 352.521 ms | 351.009 ms | — | — |
| mul! tensor.vec | Float64 64^3 | 704.424 μs | 457.010 μs | 344.518 μs | 204.337 μs | 379.004 μs | 217.732 μs | 111.121 μs | 59.221 μs | 45.913 μs | 19.580 μs |
| norm! vec | Float32 128^3 | 805.111 μs | 580.083 μs | 465.693 μs | 339.052 μs | 216.772 μs | 119.751 μs | 63.990 μs | 52.270 μs | 66.827 μs | 39.551 μs |
| norm! vec | Float32 256^3 | 10.068 ms | 9.420 ms | 7.829 ms | 7.169 ms | 5.328 ms | 4.288 ms | 4.076 ms | 4.226 ms | 455.723 μs | 335.074 μs |
| norm! vec | Float32 512^3 | 82.552 ms | 80.164 ms | 66.460 ms | 62.401 ms | 49.340 ms | 44.364 ms | 45.828 ms | 46.797 ms | 3.354 ms | — |
| norm! vec | Float32 64^3 | 53.448 μs | 38.390 μs | 19.352 μs | 16.953 μs | 31.280 μs | 21.060 μs | 13.140 μs | 11.400 μs | 32.270 μs | 11.040 μs |
| norm! vec | Float64 128^3 | 2.096 ms | 1.912 ms | 1.478 ms | 1.341 ms | 489.994 μs | 247.853 μs | 128.041 μs | 105.531 μs | 132.647 μs | 79.460 μs |
| norm! vec | Float64 256^3 | 21.357 ms | 19.485 ms | 16.164 ms | 15.044 ms | 11.883 ms | 10.281 ms | 10.280 ms | 10.558 ms | 935.300 μs | 671.927 μs |
| norm! vec | Float64 512^3 | 165.424 ms | 159.487 ms | 133.072 ms | 124.108 ms | 102.305 ms | 90.356 ms | 92.070 ms | 92.572 ms | — | — |
| norm! vec | Float64 64^3 | 157.715 μs | 89.236 μs | 50.120 μs | 32.556 μs | 56.461 μs | 34.991 μs | 21.270 μs | 16.600 μs | 40.881 μs | 16.621 μs |
| tr! tensor | Float32 128^3 | 691.097 μs | 523.363 μs | 440.842 μs | 322.273 μs | 214.512 μs | 116.262 μs | 60.831 μs | 51.071 μs | 65.463 μs | 39.271 μs |
| tr! tensor | Float32 256^3 | 10.241 ms | 9.433 ms | 7.656 ms | 7.048 ms | 5.142 ms | 4.372 ms | 4.280 ms | 4.369 ms | 419.196 μs | 332.223 μs |
| tr! tensor | Float32 512^3 | 84.908 ms | 77.523 ms | 64.685 ms | 61.041 ms | 52.028 ms | 45.475 ms | 46.366 ms | 47.048 ms | 3.416 ms | — |
| tr! tensor | Float32 64^3 | 52.733 μs | 32.379 μs | 15.337 μs | 13.594 μs | 30.730 μs | 18.610 μs | 10.840 μs | 9.640 μs | 32.381 μs | 10.900 μs |
| tr! tensor | Float64 128^3 | 2.087 ms | 1.877 ms | 1.437 ms | 1.305 ms | 472.345 μs | 237.172 μs | 125.412 μs | 100.761 μs | 71.947 μs | 70.411 μs |
| tr! tensor | Float64 256^3 | 20.335 ms | 19.187 ms | 15.923 ms | 14.596 ms | 11.427 ms | 10.606 ms | 10.556 ms | 10.755 ms | 729.404 μs | 672.027 μs |
| tr! tensor | Float64 512^3 | 153.574 ms | 155.349 ms | 130.436 ms | 121.342 ms | 104.408 ms | 93.094 ms | 92.962 ms | 94.010 ms | — | — |
| tr! tensor | Float64 64^3 | 104.769 μs | 60.834 μs | 34.275 μs | 19.486 μs | 53.280 μs | 31.560 μs | 19.040 μs | 14.320 μs | 33.554 μs | 11.030 μs |

## operators

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| curl! vec->vec | Float32 128^3 | 5.570 ms | 2.817 ms | 1.534 ms | 1.201 ms | 3.225 ms | 1.662 ms | 830.059 μs | 423.315 μs | 54.268 μs | 37.591 μs |
| curl! vec->vec | Float32 256^3 | 44.143 ms | 22.594 ms | 17.329 ms | 16.603 ms | 25.582 ms | 13.222 ms | 8.829 ms | 8.561 ms | 599.665 μs | 541.556 μs |
| curl! vec->vec | Float32 512^3 | 352.634 ms | 178.081 ms | 143.986 ms | 137.109 ms | 221.916 ms | 116.620 ms | 83.223 ms | 83.772 ms | 4.585 ms | — |
| curl! vec->vec | Float32 64^3 | 701.076 μs | 360.763 μs | 183.790 μs | 97.418 μs | 413.914 μs | 219.992 μs | 110.881 μs | 58.211 μs | 36.591 μs | 11.760 μs |
| curl! vec->vec | Float64 128^3 | 5.472 ms | 3.970 ms | 3.543 ms | 3.407 ms | 3.715 ms | 1.878 ms | 923.080 μs | 533.235 μs | 132.590 μs | 142.691 μs |
| curl! vec->vec | Float64 256^3 | 48.491 ms | 38.152 ms | 35.526 ms | 34.402 ms | 33.518 ms | 20.339 ms | 19.335 ms | 19.541 ms | 1.171 ms | 1.076 ms |
| curl! vec->vec | Float64 512^3 | 357.994 ms | 295.934 ms | 285.142 ms | 276.230 ms | 263.706 ms | 168.288 ms | 164.977 ms | 166.920 ms | — | — |
| curl! vec->vec | Float64 64^3 | 669.677 μs | 353.934 μs | 178.966 μs | 98.998 μs | 463.114 μs | 233.472 μs | 120.691 μs | 64.021 μs | 46.655 μs | 20.790 μs |
| divergence! vec->scalar | Float32 128^3 | 3.488 ms | 1.379 ms | 714.512 μs | 410.273 μs | 3.375 ms | 1.137 ms | 569.886 μs | 287.743 μs | 58.304 μs | 31.620 μs |
| divergence! vec->scalar | Float32 256^3 | 28.222 ms | 11.020 ms | 9.254 ms | 8.271 ms | 26.737 ms | 8.971 ms | 4.529 ms | 4.140 ms | 395.405 μs | 342.194 μs |
| divergence! vec->scalar | Float32 512^3 | 225.599 ms | 89.683 ms | 78.305 ms | 70.431 ms | 211.421 ms | 70.710 ms | 46.335 ms | 46.775 ms | 2.937 ms | — |
| divergence! vec->scalar | Float32 64^3 | 427.450 μs | 176.172 μs | 92.150 μs | 51.564 μs | 433.305 μs | 152.721 μs | 78.161 μs | 42.550 μs | 33.643 μs | 11.370 μs |
| divergence! vec->scalar | Float64 128^3 | 3.577 ms | 2.025 ms | 1.630 ms | 1.420 ms | 3.345 ms | 1.061 ms | 545.376 μs | 277.293 μs | 87.801 μs | 76.081 μs |
| divergence! vec->scalar | Float64 256^3 | 31.003 ms | 21.358 ms | 17.413 ms | 15.758 ms | 27.449 ms | 11.125 ms | 10.314 ms | 10.316 ms | 744.887 μs | 678.946 μs |
| divergence! vec->scalar | Float64 512^3 | 241.030 ms | 164.044 ms | 135.853 ms | 126.447 ms | 211.704 ms | 96.078 ms | 93.528 ms | 93.519 ms | — | — |
| divergence! vec->scalar | Float64 64^3 | 407.318 μs | 162.684 μs | 86.541 μs | 56.911 μs | 435.395 μs | 138.741 μs | 73.801 μs | 40.960 μs | 37.895 μs | 13.941 μs |
| divergence!∘kernel vec->scalar | Float32 128^3 | 5.666 ms | 2.475 ms | 1.254 ms | 702.418 μs | 5.007 ms | 2.062 ms | 1.033 ms | 517.695 μs | 68.536 μs | 39.161 μs |
| divergence!∘kernel vec->scalar | Float32 256^3 | 45.296 ms | 18.812 ms | 10.055 ms | 8.952 ms | 39.527 ms | 16.194 ms | 8.130 ms | 4.253 ms | 423.792 μs | 343.373 μs |
| divergence!∘kernel vec->scalar | Float32 512^3 | 358.585 ms | 148.701 ms | 84.490 ms | 75.767 ms | 312.006 ms | 128.579 ms | 64.036 ms | 46.982 ms | 3.431 ms | — |
| divergence!∘kernel vec->scalar | Float32 64^3 | 704.011 μs | 323.268 μs | 163.944 μs | 90.991 μs | 634.947 μs | 271.213 μs | 139.321 μs | 74.511 μs | 36.052 μs | 13.240 μs |
| divergence!∘kernel vec->scalar | Float64 128^3 | 5.773 ms | 2.442 ms | 1.726 ms | 1.441 ms | 5.004 ms | 1.990 ms | 998.470 μs | 499.695 μs | 107.119 μs | 77.520 μs |
| divergence!∘kernel vec->scalar | Float64 256^3 | 47.041 ms | 22.120 ms | 17.989 ms | 16.251 ms | 40.014 ms | 15.819 ms | 10.315 ms | 10.273 ms | 755.065 μs | 681.156 μs |
| divergence!∘kernel vec->scalar | Float64 512^3 | 371.499 ms | 168.086 ms | 138.832 ms | 128.627 ms | 312.274 ms | 127.491 ms | 93.969 ms | 93.686 ms | — | — |
| divergence!∘kernel vec->scalar | Float64 64^3 | 697.877 μs | 309.333 μs | 158.013 μs | 89.429 μs | 635.446 μs | 255.153 μs | 132.461 μs | 70.711 μs | 42.687 μs | 18.130 μs |
| gradient! scalar->vec | Float32 128^3 | 3.126 ms | 1.674 ms | 877.614 μs | 514.574 μs | 1.967 ms | 971.410 μs | 490.155 μs | 251.663 μs | 45.579 μs | 27.840 μs |
| gradient! scalar->vec | Float32 256^3 | 25.011 ms | 14.353 ms | 13.055 ms | 12.729 ms | 15.614 ms | 7.821 ms | 5.665 ms | 5.645 ms | 441.593 μs | 379.483 μs |
| gradient! scalar->vec | Float32 512^3 | 199.337 ms | 116.955 ms | 111.158 ms | 107.159 ms | 125.223 ms | 66.503 ms | 64.258 ms | 64.439 ms | 3.415 ms | — |
| gradient! scalar->vec | Float32 64^3 | 392.515 μs | 215.930 μs | 106.683 μs | 58.804 μs | 248.313 μs | 125.591 μs | 64.671 μs | 35.260 μs | 34.365 μs | 10.390 μs |
| gradient! scalar->vec | Float64 128^3 | 3.352 ms | 2.822 ms | 2.461 ms | 2.283 ms | 2.067 ms | 978.670 μs | 495.985 μs | 258.463 μs | 96.900 μs | 99.511 μs |
| gradient! scalar->vec | Float64 256^3 | 30.957 ms | 28.470 ms | 27.121 ms | 26.391 ms | 20.238 ms | 14.734 ms | 13.986 ms | 14.126 ms | 903.515 μs | 745.877 μs |
| gradient! scalar->vec | Float64 512^3 | 234.597 ms | 227.254 ms | 221.627 ms | 215.372 ms | 163.396 ms | 129.490 ms | 127.405 ms | 128.301 ms | — | — |
| gradient! scalar->vec | Float64 64^3 | 361.664 μs | 189.697 μs | 97.431 μs | 59.724 μs | 262.722 μs | 125.652 μs | 63.240 μs | 34.641 μs | 41.009 μs | 16.270 μs |
| helmholtz! vec->vec | Float32 128^3 | 4.366 ms | 2.237 ms | 1.410 ms | 1.200 ms | 3.384 ms | 1.698 ms | 854.019 μs | 432.135 μs | 56.797 μs | 37.111 μs |
| helmholtz! vec->vec | Float32 256^3 | 34.153 ms | 18.814 ms | 17.207 ms | 16.560 ms | 26.893 ms | 13.444 ms | 8.551 ms | 8.560 ms | 599.661 μs | 542.115 μs |
| helmholtz! vec->vec | Float32 512^3 | 272.421 ms | 152.183 ms | 144.369 ms | 137.372 ms | 234.709 ms | 116.604 ms | 82.986 ms | 83.863 ms | 4.617 ms | — |
| helmholtz! vec->vec | Float32 64^3 | 550.289 μs | 284.226 μs | 145.361 μs | 78.711 μs | 447.534 μs | 230.002 μs | 115.621 μs | 60.911 μs | 37.002 μs | 12.080 μs |
| helmholtz! vec->vec | Float64 128^3 | 4.893 ms | 3.985 ms | 3.532 ms | 3.402 ms | 3.884 ms | 1.988 ms | 1.014 ms | 555.466 μs | 167.443 μs | 137.971 μs |
| helmholtz! vec->vec | Float64 256^3 | 45.002 ms | 38.172 ms | 35.478 ms | 34.248 ms | 37.826 ms | 20.305 ms | 19.409 ms | 19.583 ms | 1.194 ms | 1.073 ms |
| helmholtz! vec->vec | Float64 512^3 | 315.824 ms | 295.597 ms | 286.143 ms | 276.325 ms | 277.286 ms | 168.692 ms | 165.432 ms | 167.094 ms | — | — |
| helmholtz! vec->vec | Float64 64^3 | 582.096 μs | 305.179 μs | 154.864 μs | 89.158 μs | 508.735 μs | 260.462 μs | 134.411 μs | 71.391 μs | 53.199 μs | 26.911 μs |
| helmholtz!∘kernel vec->vec | Float32 128^3 | 7.476 ms | 3.848 ms | 1.972 ms | 1.257 ms | 6.317 ms | 3.165 ms | 1.654 ms | 809.558 μs | 65.590 μs | 40.931 μs |
| helmholtz!∘kernel vec->vec | Float32 256^3 | 59.239 ms | 30.726 ms | 17.653 ms | 16.575 ms | 50.148 ms | 25.095 ms | 12.622 ms | 8.536 ms | 592.501 μs | 542.175 μs |
| helmholtz!∘kernel vec->vec | Float32 512^3 | 469.969 ms | 242.465 ms | 146.286 ms | 137.596 ms | 404.131 ms | 201.824 ms | 101.600 ms | 83.328 ms | 4.561 ms | — |
| helmholtz!∘kernel vec->vec | Float32 64^3 | 944.376 μs | 493.213 μs | 247.877 μs | 135.415 μs | 827.318 μs | 426.344 μs | 215.282 μs | 110.931 μs | 39.497 μs | 13.640 μs |
| helmholtz!∘kernel vec->vec | Float64 128^3 | 7.923 ms | 4.200 ms | 3.595 ms | 3.432 ms | 6.788 ms | 3.479 ms | 1.796 ms | 879.579 μs | 179.882 μs | 168.381 μs |
| helmholtz!∘kernel vec->vec | Float64 256^3 | 71.545 ms | 39.009 ms | 35.692 ms | 34.390 ms | 55.004 ms | 27.966 ms | 19.336 ms | 19.363 ms | 1.224 ms | 1.228 ms |
| helmholtz!∘kernel vec->vec | Float64 512^3 | 512.004 ms | 297.228 ms | 286.499 ms | 276.579 ms | 444.705 ms | 230.994 ms | 165.845 ms | 166.390 ms | — | — |
| helmholtz!∘kernel vec->vec | Float64 64^3 | 1.010 ms | 518.394 μs | 263.698 μs | 138.878 μs | 909.569 μs | 455.485 μs | 233.172 μs | 121.401 μs | 56.041 μs | 33.020 μs |
| inverse_curl! vec->vec | Float32 128^3 | — | — | — | — | 3.503 ms | 1.747 ms | 876.009 μs | 449.434 μs | — | 35.331 μs |
| inverse_curl! vec->vec | Float32 256^3 | — | — | — | — | 28.150 ms | 13.994 ms | 8.563 ms | 8.568 ms | — | 541.605 μs |
| inverse_curl! vec->vec | Float32 512^3 | — | — | — | — | 242.037 ms | 119.563 ms | 83.059 ms | 83.839 ms | — | — |
| inverse_curl! vec->vec | Float32 64^3 | — | — | — | — | 444.975 μs | 225.722 μs | 114.301 μs | 60.401 μs | — | 12.210 μs |
| inverse_curl! vec->vec | Float64 128^3 | — | — | — | — | 3.664 ms | 1.842 ms | 912.639 μs | 528.055 μs | — | 155.081 μs |
| inverse_curl! vec->vec | Float64 256^3 | — | — | — | — | 33.468 ms | 20.224 ms | 19.336 ms | 19.543 ms | — | 1.123 ms |
| inverse_curl! vec->vec | Float64 512^3 | — | — | — | — | 261.491 ms | 167.628 ms | 164.623 ms | 166.410 ms | — | — |
| inverse_curl! vec->vec | Float64 64^3 | — | — | — | — | 456.514 μs | 229.833 μs | 119.012 μs | 63.381 μs | — | 30.980 μs |
| inverse_laplacian! scalar | Float32 128^3 | 4.619 ms | 1.699 ms | 874.350 μs | 478.487 μs | 3.898 ms | 1.323 ms | 669.076 μs | 343.404 μs | 60.328 μs | 33.521 μs |
| inverse_laplacian! scalar | Float32 256^3 | 36.493 ms | 13.270 ms | 6.780 ms | 5.142 ms | 31.487 ms | 10.596 ms | 5.322 ms | 2.700 ms | 331.970 μs | 222.813 μs |
| inverse_laplacian! scalar | Float32 512^3 | 289.881 ms | 105.008 ms | 55.020 ms | 45.689 ms | 250.540 ms | 83.592 ms | 42.550 ms | 26.620 ms | 2.527 ms | — |
| inverse_laplacian! scalar | Float32 64^3 | 571.631 μs | 230.821 μs | 124.980 μs | 73.228 μs | 496.625 μs | 177.962 μs | 92.351 μs | 52.561 μs | 31.868 μs | 11.100 μs |
| inverse_laplacian! scalar | Float64 128^3 | 4.916 ms | 1.857 ms | 954.022 μs | 521.556 μs | 4.249 ms | 1.424 ms | 729.628 μs | 372.114 μs | 93.645 μs | 48.710 μs |
| inverse_laplacian! scalar | Float64 256^3 | 38.595 ms | 14.717 ms | 10.574 ms | 8.591 ms | 34.282 ms | 11.519 ms | 5.806 ms | 4.836 ms | 588.303 μs | 348.714 μs |
| inverse_laplacian! scalar | Float64 512^3 | 311.341 ms | 114.326 ms | 86.574 ms | 67.315 ms | 272.559 ms | 91.169 ms | 54.288 ms | 54.398 ms | — | — |
| inverse_laplacian! scalar | Float64 64^3 | 610.294 μs | 249.984 μs | 132.548 μs | 75.193 μs | 540.355 μs | 190.252 μs | 99.841 μs | 55.980 μs | 36.186 μs | 14.110 μs |
| laplacian! scalar | Float32 128^3 | 1.958 ms | 637.398 μs | 340.757 μs | 178.083 μs | 2.144 ms | 493.565 μs | 250.263 μs | 129.481 μs | 52.067 μs | 26.170 μs |
| laplacian! scalar | Float32 256^3 | 16.095 ms | 5.947 ms | 4.924 ms | 4.107 ms | 17.028 ms | 3.872 ms | 1.954 ms | 1.191 ms | 253.225 μs | 189.202 μs |
| laplacian! scalar | Float32 512^3 | 130.712 ms | 49.243 ms | 41.556 ms | 34.570 ms | 136.008 ms | 30.759 ms | 26.172 ms | 26.298 ms | 1.817 ms | — |
| laplacian! scalar | Float32 64^3 | 247.546 μs | 88.361 μs | 48.332 μs | 30.833 μs | 274.793 μs | 68.580 μs | 36.640 μs | 22.240 μs | 30.560 μs | 9.290 μs |
| laplacian! scalar | Float64 128^3 | 2.086 ms | 799.821 μs | 610.172 μs | 425.664 μs | 2.205 ms | 528.455 μs | 271.723 μs | 140.672 μs | 56.710 μs | 29.140 μs |
| laplacian! scalar | Float64 256^3 | 17.976 ms | 11.880 ms | 11.313 ms | 10.666 ms | 17.726 ms | 5.003 ms | 4.779 ms | 4.837 ms | 375.941 μs | 357.304 μs |
| laplacian! scalar | Float64 512^3 | 136.821 ms | 96.697 ms | 94.873 ms | 90.073 ms | 141.578 ms | 53.753 ms | 53.595 ms | 54.419 ms | — | — |
| laplacian! scalar | Float64 64^3 | 252.148 μs | 92.048 μs | 50.748 μs | 35.051 μs | 281.772 μs | 73.040 μs | 38.830 μs | 23.571 μs | 31.976 μs | 10.130 μs |
| symmetric_gradient! vec->tensor | Float32 128^3 | 12.011 ms | 6.218 ms | 4.382 ms | 4.151 ms | 9.617 ms | 4.884 ms | 2.444 ms | 1.236 ms | 84.963 μs | 148.641 μs |
| symmetric_gradient! vec->tensor | Float32 256^3 | 91.737 ms | 48.169 ms | 42.396 ms | 41.755 ms | 76.731 ms | 40.089 ms | 22.914 ms | 23.123 ms | 1.938 ms | 1.127 ms |
| symmetric_gradient! vec->tensor | Float32 512^3 | 719.902 ms | 388.330 ms | 348.213 ms | 336.925 ms | 650.497 ms | 337.874 ms | 209.978 ms | 201.112 ms | 14.724 ms | — |
| symmetric_gradient! vec->tensor | Float32 64^3 | 1.439 ms | 735.446 μs | 376.005 μs | 199.969 μs | 1.214 ms | 621.927 μs | 316.023 μs | 168.062 μs | 44.229 μs | 17.740 μs |
| symmetric_gradient! vec->tensor | Float64 128^3 | 13.391 ms | 10.959 ms | 9.649 ms | 9.488 ms | 10.705 ms | 5.704 ms | 3.591 ms | 3.761 ms | 454.036 μs | 286.953 μs |
| symmetric_gradient! vec->tensor | Float64 256^3 | 115.709 ms | 91.065 ms | 86.479 ms | 84.782 ms | 93.313 ms | 57.178 ms | 49.033 ms | 49.609 ms | 3.517 ms | 2.225 ms |
| symmetric_gradient! vec->tensor | Float64 512^3 | 842.034 ms | 696.672 ms | 673.680 ms | 681.051 ms | 703.560 ms | 447.543 ms | 395.311 ms | 433.016 ms | — | — |
| symmetric_gradient! vec->tensor | Float64 64^3 | 1.535 ms | 791.321 μs | 413.076 μs | 221.171 μs | 1.275 ms | 645.046 μs | 326.464 μs | 166.971 μs | 55.551 μs | 32.210 μs |

## convolution

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| assignment_window | Float32 128^3 | 1.184 μs | 1.116 μs | 1.122 μs | 1.118 μs | 1.165 μs | 1.169 μs | 1.168 μs | 1.169 μs | 78.810 μs | 25.631 μs |
| assignment_window | Float32 256^3 | 2.182 μs | 2.182 μs | 2.189 μs | 2.200 μs | 2.227 μs | 2.231 μs | 2.236 μs | 2.221 μs | 80.246 μs | 25.500 μs |
| assignment_window | Float32 512^3 | 4.430 μs | 4.419 μs | 4.440 μs | 4.459 μs | 4.467 μs | 4.462 μs | 4.470 μs | 4.466 μs | 74.877 μs | — |
| assignment_window | Float32 64^3 | 604.128 ns | 590.983 ns | 609.251 ns | 601.374 ns | 608.177 ns | 610.062 ns | 611.663 ns | 611.091 ns | 83.731 μs | 25.091 μs |
| assignment_window | Float64 128^3 | 1.466 μs | 1.505 μs | 1.496 μs | 1.577 μs | 1.559 μs | 1.551 μs | 1.567 μs | 1.575 μs | 75.875 μs | 26.821 μs |
| assignment_window | Float64 256^3 | 3.065 μs | 3.143 μs | 3.116 μs | 3.315 μs | 3.115 μs | 3.076 μs | 3.089 μs | 3.074 μs | 81.655 μs | 27.501 μs |
| assignment_window | Float64 512^3 | 5.945 μs | 6.063 μs | 6.048 μs | 6.401 μs | 6.022 μs | 5.962 μs | 5.932 μs | 5.966 μs | — | — |
| assignment_window | Float64 64^3 | 734.540 ns | 743.932 ns | 799.793 ns | 786.742 ns | 829.115 ns | 821.532 ns | 827.192 ns | 824.948 ns | 76.851 μs | 26.250 μs |
| combine!∘kernel vector | Float32 128^3 | 4.733 ms | 2.219 ms | 1.598 ms | 1.471 ms | 3.155 ms | 1.548 ms | 777.248 μs | 396.384 μs | 58.199 μs | 79.330 μs |
| combine!∘kernel vector | Float32 256^3 | 31.065 ms | 20.832 ms | 19.500 ms | 18.608 ms | 25.242 ms | 12.704 ms | 9.938 ms | 9.887 ms | 956.156 μs | 863.549 μs |
| combine!∘kernel vector | Float32 512^3 | 263.209 ms | 173.203 ms | 161.672 ms | 153.536 ms | 242.879 ms | 102.236 ms | 92.999 ms | 93.344 ms | 7.226 ms | — |
| combine!∘kernel vector | Float32 64^3 | 490.575 μs | 278.176 μs | 136.540 μs | 74.747 μs | 422.295 μs | 206.253 μs | 105.651 μs | 56.551 μs | 37.616 μs | 13.340 μs |
| combine!∘kernel vector | Float64 128^3 | 5.425 ms | 4.648 ms | 4.138 ms | 3.926 ms | 3.748 ms | 2.080 ms | 1.108 ms | 754.328 μs | 244.750 μs | 225.052 μs |
| combine!∘kernel vector | Float64 256^3 | 48.876 ms | 43.187 ms | 40.859 ms | 38.569 ms | 34.090 ms | 23.100 ms | 21.977 ms | 22.168 ms | 1.849 ms | 1.713 ms |
| combine!∘kernel vector | Float64 512^3 | 355.482 ms | 337.734 ms | 321.947 ms | 308.026 ms | 289.421 ms | 190.866 ms | 183.886 ms | 185.179 ms | — | — |
| combine!∘kernel vector | Float64 64^3 | 518.029 μs | 280.676 μs | 141.916 μs | 84.508 μs | 383.943 μs | 223.292 μs | 114.301 μs | 62.341 μs | 50.051 μs | 25.210 μs |
| convolve! scalar | Float32 128^3 | 1.593 ms | 299.555 μs | 202.038 μs | 87.165 μs | 920.519 μs | 104.561 μs | 53.651 μs | 35.850 μs | 42.054 μs | 21.390 μs |
| convolve! scalar | Float32 256^3 | 13.168 ms | 7.734 ms | 7.298 ms | 6.742 ms | 7.584 ms | 2.799 ms | 2.704 ms | 2.738 ms | 282.937 μs | 260.513 μs |
| convolve! scalar | Float32 512^3 | 105.047 ms | 65.771 ms | 63.420 ms | 59.295 ms | 62.301 ms | 37.346 ms | 36.616 ms | 37.005 ms | 2.061 ms | — |
| convolve! scalar | Float32 64^3 | 196.941 μs | 26.366 μs | 21.237 μs | 13.663 μs | 116.872 μs | 16.201 μs | 9.000 μs | 7.554 μs | 29.300 μs | 8.200 μs |
| convolve! scalar | Float64 128^3 | 1.766 ms | 1.342 ms | 1.158 ms | 1.024 ms | 1.000 ms | 173.062 μs | 90.971 μs | 72.090 μs | 57.277 μs | 33.070 μs |
| convolve! scalar | Float64 256^3 | 17.950 ms | 16.185 ms | 15.215 ms | 14.239 ms | 10.939 ms | 7.897 ms | 7.612 ms | 7.756 ms | 553.726 μs | 516.776 μs |
| convolve! scalar | Float64 512^3 | 144.010 ms | 132.439 ms | 125.743 ms | 118.467 ms | 90.042 ms | 73.691 ms | 73.668 ms | 74.107 ms | — | — |
| convolve! scalar | Float64 64^3 | 176.050 μs | 53.891 μs | 36.206 μs | 21.416 μs | 127.711 μs | 26.650 μs | 13.790 μs | 10.140 μs | 33.147 μs | 9.970 μs |
| convolve! vector | Float32 128^3 | 2.984 ms | 1.838 ms | 1.551 ms | 1.479 ms | 2.103 ms | 1.099 ms | 551.226 μs | 282.593 μs | 49.134 μs | 59.581 μs |
| convolve! vector | Float32 256^3 | 22.387 ms | 20.504 ms | 19.166 ms | 18.409 ms | 19.800 ms | 10.967 ms | 9.857 ms | 9.886 ms | 622.981 μs | 618.736 μs |
| convolve! vector | Float32 512^3 | 191.859 ms | 170.217 ms | 159.751 ms | 153.181 ms | 178.202 ms | 94.040 ms | 92.441 ms | 93.133 ms | 4.636 ms | — |
| convolve! vector | Float32 64^3 | 310.204 μs | 175.555 μs | 91.565 μs | 50.635 μs | 270.172 μs | 147.462 μs | 74.430 μs | 39.981 μs | 36.096 μs | 10.610 μs |
| convolve! vector | Float64 128^3 | 4.894 ms | 4.657 ms | 4.123 ms | 3.924 ms | 2.658 ms | 1.541 ms | 877.809 μs | 751.219 μs | 180.042 μs | 160.172 μs |
| convolve! vector | Float64 256^3 | 45.023 ms | 42.534 ms | 40.240 ms | 38.388 ms | 30.584 ms | 22.849 ms | 21.958 ms | 22.125 ms | 1.211 ms | 1.228 ms |
| convolve! vector | Float64 512^3 | 334.361 ms | 334.536 ms | 321.022 ms | 307.704 ms | 239.732 ms | 188.786 ms | 183.720 ms | 185.473 ms | — | — |
| convolve! vector | Float64 64^3 | 275.006 μs | 169.460 μs | 89.733 μs | 55.406 μs | 219.633 μs | 136.691 μs | 70.381 μs | 39.240 μs | 42.174 μs | 18.600 μs |
| convolve! vector ∘ radial    | Float32 128^3 | 4.137 ms | 2.168 ms | 1.467 ms | 1.230 ms | 2.505 ms | 1.250 ms | 628.887 μs | 321.373 μs | 125.566 μs | 83.061 μs |
| convolve! vector ∘ radial    | Float32 256^3 | 32.442 ms | 19.540 ms | 16.261 ms | 14.167 ms | 19.845 ms | 10.077 ms | 8.208 ms | 8.362 ms | 852.081 μs | 610.286 μs |
| convolve! vector ∘ radial    | Float32 512^3 | 260.754 ms | 153.051 ms | 125.871 ms | 105.766 ms | 158.316 ms | 86.586 ms | 89.653 ms | 82.221 ms | 6.554 ms | — |
| convolve! vector ∘ radial    | Float32 64^3 | 525.698 μs | 272.587 μs | 132.730 μs | 75.186 μs | 315.844 μs | 160.552 μs | 82.201 μs | 43.561 μs | 43.746 μs | 16.651 μs |
| convolve! vector ∘ radial    | Float64 128^3 | 5.089 ms | 4.032 ms | 3.543 ms | 2.914 ms | 2.878 ms | 1.454 ms | 727.637 μs | 408.764 μs | 163.756 μs | 136.721 μs |
| convolve! vector ∘ radial    | Float64 256^3 | 41.150 ms | 36.634 ms | 29.849 ms | 26.341 ms | 24.296 ms | 18.669 ms | 18.791 ms | 19.079 ms | 1.067 ms | 1.065 ms |
| convolve! vector ∘ radial    | Float64 512^3 | 328.914 ms | 292.288 ms | 227.544 ms | 198.790 ms | 197.514 ms | 161.014 ms | 162.505 ms | 163.970 ms | — | — |
| convolve! vector ∘ radial    | Float64 64^3 | 532.804 μs | 275.934 μs | 146.401 μs | 94.811 μs | 352.993 μs | 177.482 μs | 89.621 μs | 48.370 μs | 46.419 μs | 18.450 μs |
| convolve! vector ∘ radial-stored | Float32 128^3 | 2.965 ms | 1.833 ms | 1.563 ms | 1.486 ms | 2.105 ms | 1.103 ms | 550.245 μs | 282.943 μs | 49.126 μs | 60.920 μs |
| convolve! vector ∘ radial-stored | Float32 256^3 | 22.549 ms | 20.741 ms | 19.339 ms | 18.401 ms | 19.701 ms | 10.964 ms | 9.795 ms | 9.884 ms | 620.835 μs | 619.116 μs |
| convolve! vector ∘ radial-stored | Float32 512^3 | 193.133 ms | 169.985 ms | 159.839 ms | 153.165 ms | 177.509 ms | 93.862 ms | 92.252 ms | 92.768 ms | 4.649 ms | — |
| convolve! vector ∘ radial-stored | Float32 64^3 | 310.387 μs | 176.035 μs | 91.522 μs | 51.388 μs | 269.593 μs | 147.372 μs | 74.521 μs | 39.940 μs | 36.090 μs | 10.570 μs |
| convolve! vector ∘ radial-stored | Float64 128^3 | 4.923 ms | 4.608 ms | 4.180 ms | 3.932 ms | 2.652 ms | 1.551 ms | 888.369 μs | 749.988 μs | 180.471 μs | 160.271 μs |
| convolve! vector ∘ radial-stored | Float64 256^3 | 44.713 ms | 42.494 ms | 40.030 ms | 38.411 ms | 30.365 ms | 22.484 ms | 21.926 ms | 22.024 ms | 1.216 ms | 1.229 ms |
| convolve! vector ∘ radial-stored | Float64 512^3 | 333.016 ms | 334.888 ms | 320.659 ms | 307.456 ms | 238.013 ms | 186.294 ms | 183.911 ms | 184.397 ms | — | — |
| convolve! vector ∘ radial-stored | Float64 64^3 | 276.289 μs | 168.856 μs | 88.106 μs | 52.225 μs | 230.442 μs | 136.732 μs | 70.230 μs | 38.340 μs | 42.120 μs | 18.620 μs |
| convolve! vector ∘ separable | Float32 128^3 | 6.760 ms | 3.455 ms | 1.754 ms | 1.213 ms | 4.689 ms | 2.349 ms | 1.169 ms | 591.396 μs | 130.674 μs | 83.821 μs |
| convolve! vector ∘ separable | Float32 256^3 | 53.473 ms | 27.624 ms | 17.239 ms | 13.202 ms | 37.225 ms | 18.611 ms | 9.372 ms | 8.451 ms | 867.930 μs | 613.806 μs |
| convolve! vector ∘ separable | Float32 512^3 | 426.551 ms | 218.832 ms | 136.861 ms | 106.705 ms | 296.142 ms | 148.181 ms | 82.539 ms | 82.763 ms | 6.851 ms | — |
| convolve! vector ∘ separable | Float32 64^3 | 842.577 μs | 435.665 μs | 225.713 μs | 118.591 μs | 588.566 μs | 297.343 μs | 150.462 μs | 78.021 μs | 43.832 μs | 16.850 μs |
| convolve! vector ∘ separable | Float64 128^3 | 6.753 ms | 4.128 ms | 3.389 ms | 2.475 ms | 3.958 ms | 1.994 ms | 1.003 ms | 510.466 μs | 241.880 μs | 144.741 μs |
| convolve! vector ∘ separable | Float64 256^3 | 53.841 ms | 36.812 ms | 29.162 ms | 23.952 ms | 32.560 ms | 19.223 ms | 19.009 ms | 19.292 ms | 1.696 ms | 1.077 ms |
| convolve! vector ∘ separable | Float64 512^3 | 428.037 ms | 295.548 ms | 232.862 ms | 189.892 ms | 259.746 ms | 164.962 ms | 163.125 ms | 165.071 ms | — | — |
| convolve! vector ∘ separable | Float64 64^3 | 808.651 μs | 436.674 μs | 215.832 μs | 120.351 μs | 495.104 μs | 248.922 μs | 125.841 μs | 66.181 μs | 57.607 μs | 25.410 μs |
| convolve! vector ∘ stored    | Float32 128^3 | 2.991 ms | 1.833 ms | 1.554 ms | 1.483 ms | 2.106 ms | 1.097 ms | 555.286 μs | 286.613 μs | 48.991 μs | 58.650 μs |
| convolve! vector ∘ stored    | Float32 256^3 | 22.564 ms | 20.516 ms | 19.219 ms | 18.417 ms | 19.818 ms | 10.941 ms | 9.833 ms | 9.908 ms | 621.345 μs | 619.657 μs |
| convolve! vector ∘ stored    | Float32 512^3 | 193.408 ms | 169.825 ms | 159.741 ms | 153.249 ms | 178.025 ms | 94.514 ms | 92.389 ms | 93.192 ms | 4.641 ms | — |
| convolve! vector ∘ stored    | Float32 64^3 | 309.962 μs | 178.565 μs | 91.368 μs | 54.553 μs | 270.233 μs | 147.781 μs | 75.350 μs | 39.921 μs | 36.063 μs | 10.670 μs |
| convolve! vector ∘ stored    | Float64 128^3 | 4.906 ms | 4.598 ms | 4.136 ms | 3.929 ms | 2.644 ms | 1.546 ms | 907.549 μs | 757.729 μs | 181.099 μs | 159.682 μs |
| convolve! vector ∘ stored    | Float64 256^3 | 44.753 ms | 42.666 ms | 40.028 ms | 38.471 ms | 30.489 ms | 22.879 ms | 21.948 ms | 22.105 ms | 1.214 ms | 1.228 ms |
| convolve! vector ∘ stored    | Float64 512^3 | 330.158 ms | 334.980 ms | 320.788 ms | 307.347 ms | 243.545 ms | 188.576 ms | 183.820 ms | 185.276 ms | — | — |
| convolve! vector ∘ stored    | Float64 64^3 | 274.539 μs | 164.133 μs | 88.964 μs | 60.719 μs | 221.182 μs | 136.832 μs | 71.981 μs | 40.610 μs | 42.133 μs | 18.590 μs |
| exponential_convolve! scalar | Float32 128^3 | 6.109 ms | 2.702 ms | 1.361 ms | 722.348 μs | 5.033 ms | 2.121 ms | 1.064 ms | 540.475 μs | 50.382 μs | 26.510 μs |
| exponential_convolve! scalar | Float32 256^3 | 48.311 ms | 21.234 ms | 10.718 ms | 6.141 ms | 39.779 ms | 16.571 ms | 8.360 ms | 4.232 ms | 258.551 μs | 189.642 μs |
| exponential_convolve! scalar | Float32 512^3 | 384.722 ms | 167.829 ms | 84.785 ms | 50.497 ms | 317.441 ms | 131.850 ms | 66.198 ms | 34.871 ms | 1.888 ms | — |
| exponential_convolve! scalar | Float32 64^3 | 762.967 μs | 349.962 μs | 179.859 μs | 101.305 μs | 640.306 μs | 280.483 μs | 145.271 μs | 77.911 μs | 31.027 μs | 9.300 μs |
| exponential_convolve! scalar | Float64 128^3 | 5.784 ms | 2.553 ms | 1.331 ms | 835.192 μs | 5.558 ms | 2.382 ms | 1.193 ms | 608.507 μs | 94.509 μs | 79.371 μs |
| exponential_convolve! scalar | Float64 256^3 | 45.717 ms | 20.058 ms | 12.133 ms | 10.752 ms | 44.292 ms | 18.813 ms | 9.470 ms | 4.995 ms | 600.686 μs | 565.516 μs |
| exponential_convolve! scalar | Float64 512^3 | 364.009 ms | 160.020 ms | 97.219 ms | 90.369 ms | 350.959 ms | 149.802 ms | 75.166 ms | 55.078 ms | — | — |
| exponential_convolve! scalar | Float64 64^3 | 719.321 μs | 328.503 μs | 170.993 μs | 103.498 μs | 701.017 μs | 306.833 μs | 159.081 μs | 85.241 μs | 39.895 μs | 17.450 μs |
| exponential_convolve! vector | Float32 128^3 | 20.248 ms | 9.678 ms | 4.892 ms | 2.629 ms | 4.716 ms | 1.869 ms | 943.920 μs | 477.715 μs | 131.385 μs | 36.990 μs |
| exponential_convolve! vector | Float32 256^3 | 160.278 ms | 76.157 ms | 38.541 ms | 22.375 ms | 41.279 ms | 16.485 ms | 10.175 ms | 8.989 ms | 866.298 μs | 541.605 μs |
| exponential_convolve! vector | Float32 512^3 | 1.274 s | 603.661 ms | 304.604 ms | 182.939 ms | 514.995 ms | 144.093 ms | 94.993 ms | 83.391 ms | 6.877 ms | — |
| exponential_convolve! vector | Float32 64^3 | 2.542 ms | 1.233 ms | 639.809 μs | 332.578 μs | 624.156 μs | 251.363 μs | 127.711 μs | 66.861 μs | 43.958 μs | 10.040 μs |
| exponential_convolve! vector | Float64 128^3 | 19.539 ms | 9.328 ms | 4.822 ms | 3.554 ms | 5.235 ms | 2.080 ms | 1.033 ms | 552.436 μs | 263.200 μs | 143.992 μs |
| exponential_convolve! vector | Float64 256^3 | 154.206 ms | 72.909 ms | 38.108 ms | 33.695 ms | 69.074 ms | 24.888 ms | 20.769 ms | 20.232 ms | 1.887 ms | 1.077 ms |
| exponential_convolve! vector | Float64 512^3 | 1.226 s | 579.498 ms | 304.348 ms | 273.431 ms | 1.007 s | 201.032 ms | 167.389 ms | 165.459 ms | — | — |
| exponential_convolve! vector | Float64 64^3 | 2.475 ms | 1.167 ms | 606.307 μs | 324.223 μs | 674.077 μs | 252.593 μs | 126.201 μs | 67.411 μs | 60.930 μs | 20.170 μs |
| inv separable | Float32 128^3 | 951.739 ns | 950.238 ns | 952.333 ns | 966.625 ns | 765.185 ns | 765.048 ns | 761.914 ns | 758.791 ns | 201.579 μs | 51.590 μs |
| inv separable | Float32 256^3 | 1.964 μs | 1.958 μs | 1.961 μs | 1.977 μs | 1.554 μs | 1.564 μs | 1.553 μs | 1.557 μs | 210.015 μs | 57.001 μs |
| inv separable | Float32 512^3 | 3.819 μs | 3.800 μs | 3.825 μs | 3.861 μs | 2.994 μs | 3.024 μs | 3.010 μs | 3.105 μs | 241.827 μs | — |
| inv separable | Float32 64^3 | 506.674 ns | 505.212 ns | 506.068 ns | 509.042 ns | 407.755 ns | 408.648 ns | 408.455 ns | 410.357 ns | 202.306 μs | 49.491 μs |
| inv separable | Float64 128^3 | 1.096 μs | 1.129 μs | 1.097 μs | 1.132 μs | 1.066 μs | 1.065 μs | 1.065 μs | 1.054 μs | 194.038 μs | 53.400 μs |
| inv separable | Float64 256^3 | 2.143 μs | 2.425 μs | 2.151 μs | 2.153 μs | 2.038 μs | 2.036 μs | 2.054 μs | 2.047 μs | 195.568 μs | 59.981 μs |
| inv separable | Float64 512^3 | 4.041 μs | 4.067 μs | 4.037 μs | 4.086 μs | 3.977 μs | 4.019 μs | 4.003 μs | 3.986 μs | — | — |
| inv separable | Float64 64^3 | 530.085 ns | 531.698 ns | 530.872 ns | 533.005 ns | 520.110 ns | 532.361 ns | 523.339 ns | 536.147 ns | 196.892 μs | 49.920 μs |
| materialize_kernel radial | Float32 128^3 | 1.380 ms | 607.802 μs | 408.922 μs | 232.532 μs | 1.130 ms | 351.443 μs | 178.282 μs | 93.241 μs | 55.598 μs | 26.180 μs |
| materialize_kernel radial | Float32 256^3 | 11.162 ms | 4.595 ms | 3.615 ms | 2.618 ms | 8.973 ms | 2.764 ms | 1.984 ms | 2.035 ms | 339.070 μs | 150.362 μs |
| materialize_kernel radial | Float32 512^3 | 88.854 ms | 36.249 ms | 28.671 ms | 21.990 ms | 71.419 ms | 22.162 ms | 32.141 ms | 17.154 ms | 4.562 ms | — |
| materialize_kernel radial | Float32 64^3 | 174.953 μs | 85.421 μs | 40.399 μs | 31.178 μs | 145.731 μs | 47.990 μs | 25.570 μs | 15.730 μs | 39.123 μs | 9.830 μs |
| materialize_kernel radial | Float64 128^3 | 1.481 ms | 916.003 μs | 693.147 μs | 440.954 μs | 1.179 ms | 372.844 μs | 226.272 μs | 305.163 μs | 64.210 μs | 29.721 μs |
| materialize_kernel radial | Float64 256^3 | 11.692 ms | 7.861 ms | 5.675 ms | 5.391 ms | 9.497 ms | 3.984 ms | 3.874 ms | 3.802 ms | 486.936 μs | 177.302 μs |
| materialize_kernel radial | Float64 512^3 | 93.204 ms | 142.965 ms | 76.707 ms | 47.893 ms | 75.444 ms | 33.815 ms | 53.247 ms | 35.706 ms | — | — |
| materialize_kernel radial | Float64 64^3 | 177.126 μs | 71.706 μs | 53.233 μs | 35.568 μs | 151.641 μs | 48.180 μs | 25.691 μs | 15.740 μs | 37.026 μs | 11.440 μs |
| materialize_kernel separable | Float32 128^3 | 1.794 ms | 782.748 μs | 448.019 μs | 322.260 μs | 1.533 ms | 446.084 μs | 227.382 μs | 116.862 μs | 56.445 μs | 25.980 μs |
| materialize_kernel separable | Float32 256^3 | 14.330 ms | 6.139 ms | 3.949 ms | 3.060 ms | 12.131 ms | 3.526 ms | 1.970 ms | 1.945 ms | 341.665 μs | 156.032 μs |
| materialize_kernel separable | Float32 512^3 | 114.889 ms | 49.178 ms | 31.341 ms | 23.919 ms | 96.540 ms | 27.869 ms | 35.141 ms | 17.953 ms | 4.659 ms | — |
| materialize_kernel separable | Float32 64^3 | 227.903 μs | 102.342 μs | 54.917 μs | 34.716 μs | 196.462 μs | 60.211 μs | 32.061 μs | 18.910 μs | 39.063 μs | 9.840 μs |
| materialize_kernel separable | Float64 128^3 | 1.778 ms | 958.451 μs | 773.722 μs | 503.520 μs | 1.449 ms | 453.995 μs | 240.243 μs | 291.063 μs | 86.700 μs | 36.891 μs |
| materialize_kernel separable | Float64 256^3 | 14.237 ms | 7.910 ms | 5.980 ms | 5.604 ms | 11.562 ms | 4.422 ms | 3.885 ms | 4.034 ms | 652.647 μs | 233.583 μs |
| materialize_kernel separable | Float64 512^3 | 114.959 ms | 63.370 ms | 82.029 ms | 50.289 ms | 91.967 ms | 38.488 ms | 61.319 ms | 44.372 ms | — | — |
| materialize_kernel separable | Float64 64^3 | 224.892 μs | 101.110 μs | 56.287 μs | 51.687 μs | 186.732 μs | 61.210 μs | 32.101 μs | 19.271 μs | 41.853 μs | 11.900 μs |
| radial_kernel | Float32 128^3 | 3.451 ns | 2.814 ns | 2.817 ns | 2.817 ns | 1.330 ns | 1.330 ns | 1.330 ns | 1.330 ns | 337.000 ns | 315.045 ns |
| radial_kernel | Float32 256^3 | 2.814 ns | 2.814 ns | 2.817 ns | 2.815 ns | 1.330 ns | 1.330 ns | 1.330 ns | 1.330 ns | 340.000 ns | 309.516 ns |
| radial_kernel | Float32 512^3 | 2.814 ns | 2.815 ns | 2.817 ns | 2.820 ns | 1.330 ns | 1.330 ns | 1.330 ns | 1.330 ns | 337.000 ns | — |
| radial_kernel | Float32 64^3 | 2.818 ns | 2.815 ns | 2.816 ns | 2.816 ns | 1.330 ns | 1.330 ns | 1.330 ns | 1.330 ns | 341.000 ns | 308.324 ns |
| radial_kernel | Float64 128^3 | 3.014 ns | 3.014 ns | 3.017 ns | 3.013 ns | 1.330 ns | 1.330 ns | 1.330 ns | 0.960 ns | 348.000 ns | 307.718 ns |
| radial_kernel | Float64 256^3 | 3.015 ns | 3.014 ns | 3.020 ns | 3.014 ns | 1.330 ns | 1.330 ns | 1.330 ns | 0.960 ns | 349.000 ns | 307.514 ns |
| radial_kernel | Float64 512^3 | 3.015 ns | 3.014 ns | 3.016 ns | 3.013 ns | 1.330 ns | 1.330 ns | 1.330 ns | 1.320 ns | — | — |
| radial_kernel | Float64 64^3 | 3.014 ns | 3.014 ns | 3.016 ns | 3.013 ns | 1.330 ns | 1.330 ns | 1.330 ns | 0.960 ns | 347.000 ns | 307.841 ns |
| spectral_band | Float32 128^3 | 12.428 ns | 10.398 ns | 11.325 ns | 11.830 ns | 0.960 ns | 1.330 ns | 0.960 ns | 1.000 ns | 357.000 ns | 311.684 ns |
| spectral_band | Float32 256^3 | 12.430 ns | 10.404 ns | 11.311 ns | 11.829 ns | 1.330 ns | 1.330 ns | 1.330 ns | 0.960 ns | 358.000 ns | 310.428 ns |
| spectral_band | Float32 512^3 | 12.417 ns | 10.391 ns | 11.282 ns | 11.829 ns | 1.330 ns | 1.330 ns | 1.330 ns | 1.330 ns | 341.000 ns | — |
| spectral_band | Float32 64^3 | 12.417 ns | 10.359 ns | 11.441 ns | 11.831 ns | 1.330 ns | 1.340 ns | 1.360 ns | 0.980 ns | 350.000 ns | 307.914 ns |
| spectral_band | Float64 128^3 | 11.688 ns | 10.924 ns | 11.498 ns | 11.851 ns | 1.330 ns | 0.960 ns | 0.960 ns | 1.330 ns | 349.000 ns | 307.386 ns |
| spectral_band | Float64 256^3 | 11.688 ns | 10.916 ns | 11.493 ns | 11.852 ns | 1.330 ns | 0.960 ns | 0.960 ns | 1.320 ns | 344.000 ns | 307.024 ns |
| spectral_band | Float64 512^3 | 11.668 ns | 10.915 ns | 11.499 ns | 11.855 ns | 1.320 ns | 0.960 ns | 0.960 ns | 1.330 ns | — | — |
| spectral_band | Float64 64^3 | 11.686 ns | 10.913 ns | 11.498 ns | 11.847 ns | 1.330 ns | 0.960 ns | 0.960 ns | 0.950 ns | 342.000 ns | 308.238 ns |
| spectral_cutoff | Float32 128^3 | 11.711 ns | 10.366 ns | 10.675 ns | 11.023 ns | 1.330 ns | 1.330 ns | 1.330 ns | 0.960 ns | 353.000 ns | 307.963 ns |
| spectral_cutoff | Float32 256^3 | 11.704 ns | 10.550 ns | 10.680 ns | 11.023 ns | 1.330 ns | 1.330 ns | 1.330 ns | 0.990 ns | 356.000 ns | 317.525 ns |
| spectral_cutoff | Float32 512^3 | 11.706 ns | 10.368 ns | 10.676 ns | 11.021 ns | 1.330 ns | 1.320 ns | 1.320 ns | 0.960 ns | 345.000 ns | — |
| spectral_cutoff | Float32 64^3 | 11.714 ns | 10.358 ns | 10.668 ns | 11.022 ns | 1.330 ns | 1.330 ns | 1.330 ns | 1.330 ns | 352.000 ns | 307.914 ns |
| spectral_cutoff | Float64 128^3 | 11.674 ns | 10.926 ns | 11.456 ns | 11.642 ns | 0.960 ns | 1.320 ns | 1.330 ns | 0.980 ns | 345.000 ns | 307.759 ns |
| spectral_cutoff | Float64 256^3 | 11.669 ns | 10.909 ns | 11.461 ns | 11.648 ns | 0.960 ns | 1.330 ns | 0.960 ns | 0.960 ns | 350.000 ns | 307.381 ns |
| spectral_cutoff | Float64 512^3 | 11.673 ns | 10.931 ns | 11.460 ns | 11.644 ns | 0.960 ns | 0.960 ns | 1.330 ns | 1.330 ns | — | — |
| spectral_cutoff | Float64 64^3 | 11.670 ns | 10.891 ns | 11.469 ns | 11.642 ns | 0.960 ns | 0.960 ns | 1.330 ns | 1.000 ns | 346.000 ns | 307.922 ns |
| translation_kernel | Float32 128^3 | 1.837 μs | 1.801 μs | 1.813 μs | 1.805 μs | 1.447 μs | 1.410 μs | 1.418 μs | 1.429 μs | 51.833 μs | 15.960 μs |
| translation_kernel | Float32 256^3 | 3.550 μs | 3.551 μs | 3.571 μs | 3.558 μs | 2.797 μs | 2.733 μs | 2.738 μs | 2.741 μs | 54.419 μs | 16.250 μs |
| translation_kernel | Float32 512^3 | 6.921 μs | 6.928 μs | 6.938 μs | 6.920 μs | 5.422 μs | 5.313 μs | 5.302 μs | 5.295 μs | 50.052 μs | — |
| translation_kernel | Float32 64^3 | 898.475 ns | 898.286 ns | 908.450 ns | 900.683 ns | 760.095 ns | 741.534 ns | 741.139 ns | 748.632 ns | 52.453 μs | 15.670 μs |
| translation_kernel | Float64 128^3 | 2.032 μs | 2.041 μs | 2.035 μs | 2.149 μs | 1.844 μs | 1.835 μs | 1.843 μs | 1.826 μs | 58.936 μs | 17.670 μs |
| translation_kernel | Float64 256^3 | 3.872 μs | 3.864 μs | 3.868 μs | 4.096 μs | 3.474 μs | 3.474 μs | 3.483 μs | 3.462 μs | 61.653 μs | 18.620 μs |
| translation_kernel | Float64 512^3 | 7.391 μs | 7.417 μs | 7.390 μs | 7.712 μs | 6.760 μs | 6.867 μs | 6.770 μs | 6.778 μs | — | — |
| translation_kernel | Float64 64^3 | 1.018 μs | 1.019 μs | 1.019 μs | 1.071 μs | 931.786 ns | 944.828 ns | 954.862 ns | 941.111 ns | 57.776 μs | 16.980 μs |
| translation_kernel! | Float32 128^3 | 1.775 μs | 1.757 μs | 1.775 μs | 1.761 μs | 1.369 μs | 1.370 μs | 1.375 μs | 1.372 μs | 31.682 μs | 13.110 μs |
| translation_kernel! | Float32 256^3 | 3.433 μs | 3.411 μs | 3.421 μs | 3.430 μs | 2.648 μs | 2.626 μs | 2.616 μs | 2.622 μs | 34.762 μs | 13.290 μs |
| translation_kernel! | Float32 512^3 | 6.790 μs | 6.763 μs | 6.760 μs | 6.778 μs | 5.110 μs | 5.158 μs | 5.112 μs | 5.112 μs | 31.335 μs | — |
| translation_kernel! | Float32 64^3 | 855.857 ns | 858.097 ns | 856.365 ns | 856.349 ns | 704.660 ns | 710.146 ns | 703.410 ns | 704.203 ns | 34.609 μs | 13.201 μs |
| translation_kernel! | Float64 128^3 | 1.869 μs | 1.861 μs | 1.869 μs | 1.896 μs | 1.692 μs | 1.698 μs | 1.703 μs | 1.701 μs | 36.474 μs | 14.460 μs |
| translation_kernel! | Float64 256^3 | 3.619 μs | 3.666 μs | 3.606 μs | 3.691 μs | 3.245 μs | 3.239 μs | 3.239 μs | 3.241 μs | 36.599 μs | 15.690 μs |
| translation_kernel! | Float64 512^3 | 7.133 μs | 7.091 μs | 7.125 μs | 7.262 μs | 6.352 μs | 6.358 μs | 6.350 μs | 6.400 μs | — | — |
| translation_kernel! | Float64 64^3 | 961.850 ns | 963.632 ns | 960.789 ns | 984.600 ns | 878.620 ns | 881.538 ns | 886.154 ns | 882.820 ns | 37.894 μs | 14.270 μs |

## transfer

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| anterpolate! CatmullRom ordered | Float32 128^3 | — | — | — | — | 20.745 ms | 10.796 ms | 5.742 ms | 3.321 ms | — | 143.122 μs |
| anterpolate! CatmullRom ordered | Float32 256^3 | — | — | — | — | 184.720 ms | 88.989 ms | 46.740 ms | 24.633 ms | — | 3.149 ms |
| anterpolate! CatmullRom ordered | Float32 512^3 | — | — | — | — | 3.600 s | 1.799 s | 942.592 ms | 540.675 ms | — | — |
| anterpolate! CatmullRom ordered | Float32 64^3 | — | — | — | — | 2.443 ms | 1.371 ms | 879.849 μs | 611.736 μs | — | 51.820 μs |
| anterpolate! CatmullRom ordered | Float64 128^3 | — | — | — | — | 22.133 ms | 11.643 ms | 6.312 ms | 3.714 ms | — | 147.251 μs |
| anterpolate! CatmullRom ordered | Float64 256^3 | — | — | — | — | 313.872 ms | 158.002 ms | 81.007 ms | 43.827 ms | — | 4.850 ms |
| anterpolate! CatmullRom ordered | Float64 512^3 | — | — | — | — | 3.786 s | 1.897 s | 1.009 s | 559.759 ms | — | — |
| anterpolate! CatmullRom ordered | Float64 64^3 | — | — | — | — | 2.476 ms | 1.432 ms | 928.259 μs | 659.946 μs | — | 51.121 μs |
| anterpolate! CatmullRom vector ordered | Float32 128^3 | — | — | — | — | 63.374 ms | 32.188 ms | 16.718 ms | 9.067 ms | — | 404.404 μs |
| anterpolate! CatmullRom vector ordered | Float32 256^3 | — | — | — | — | 919.301 ms | 468.417 ms | 239.911 ms | 134.241 ms | — | 10.952 ms |
| anterpolate! CatmullRom vector ordered | Float32 512^3 | — | — | — | — | 9.642 s | 5.009 s | 2.625 s | 1.510 s | — | — |
| anterpolate! CatmullRom vector ordered | Float32 64^3 | — | — | — | — | 7.248 ms | 3.952 ms | 2.466 ms | 1.735 ms | — | 135.911 μs |
| anterpolate! CatmullRom vector ordered | Float64 128^3 | — | — | — | — | 67.248 ms | 34.301 ms | 17.939 ms | 10.128 ms | — | 683.927 μs |
| anterpolate! CatmullRom vector ordered | Float64 256^3 | — | — | — | — | 1.111 s | 563.227 ms | 305.274 ms | 172.794 ms | — | 14.958 ms |
| anterpolate! CatmullRom vector ordered | Float64 512^3 | — | — | — | — | 9.871 s | 5.082 s | 2.657 s | 1.571 s | — | — |
| anterpolate! CatmullRom vector ordered | Float64 64^3 | — | — | — | — | 7.733 ms | 4.302 ms | 2.692 ms | 1.874 ms | — | 112.971 μs |
| anterpolate! CatmullRom vector | Float32 128^3 | — | — | — | — | 63.688 ms | 32.078 ms | 16.623 ms | 9.157 ms | — | 362.413 μs |
| anterpolate! CatmullRom vector | Float32 256^3 | — | — | — | — | 837.839 ms | 429.745 ms | 217.387 ms | 118.703 ms | — | 10.689 ms |
| anterpolate! CatmullRom vector | Float32 512^3 | — | — | — | — | 8.882 s | 4.626 s | 2.433 s | 1.390 s | — | — |
| anterpolate! CatmullRom vector | Float32 64^3 | — | — | — | — | 7.238 ms | 3.992 ms | 2.488 ms | 1.755 ms | — | 114.771 μs |
| anterpolate! CatmullRom vector | Float64 128^3 | — | — | — | — | 66.889 ms | 34.179 ms | 17.970 ms | 10.212 ms | — | 652.076 μs |
| anterpolate! CatmullRom vector | Float64 256^3 | — | — | — | — | 1.032 s | 523.050 ms | 285.418 ms | 161.574 ms | — | 14.599 ms |
| anterpolate! CatmullRom vector | Float64 512^3 | — | — | — | — | 9.123 s | 4.730 s | 2.463 s | 1.474 s | — | — |
| anterpolate! CatmullRom vector | Float64 64^3 | — | — | — | — | 7.745 ms | 4.333 ms | 2.690 ms | 1.893 ms | — | 111.831 μs |
| anterpolate! CatmullRom | Float32 128^3 | 27.523 ms | 13.706 ms | 7.329 ms | 4.417 ms | 20.945 ms | 10.844 ms | 5.816 ms | 3.393 ms | 186.914 μs | 126.961 μs |
| anterpolate! CatmullRom | Float32 256^3 | 392.571 ms | 204.137 ms | 108.428 ms | 67.165 ms | 174.386 ms | 86.331 ms | 45.336 ms | 23.975 ms | 1.344 ms | 2.784 ms |
| anterpolate! CatmullRom | Float32 512^3 | 3.899 s | 2.043 s | 1.152 s | 802.658 ms | 2.965 s | 1.466 s | 787.811 ms | 444.411 ms | — | — |
| anterpolate! CatmullRom | Float32 64^3 | 3.184 ms | 1.886 ms | 1.209 ms | 858.655 μs | 2.445 ms | 1.376 ms | 880.369 μs | 618.916 μs | 70.805 μs | 44.191 μs |
| anterpolate! CatmullRom | Float64 128^3 | 28.517 ms | 14.544 ms | 7.615 ms | 4.620 ms | 21.873 ms | 11.769 ms | 6.381 ms | 3.803 ms | 249.010 μs | 149.941 μs |
| anterpolate! CatmullRom | Float64 256^3 | 515.747 ms | 260.488 ms | 147.343 ms | 103.501 ms | 260.029 ms | 129.572 ms | 65.746 ms | 36.010 ms | 2.426 ms | 4.545 ms |
| anterpolate! CatmullRom | Float64 512^3 | 4.975 s | 2.629 s | 1.421 s | 881.899 ms | 3.216 s | 1.594 s | 835.395 ms | 474.677 ms | — | — |
| anterpolate! CatmullRom | Float64 64^3 | 3.273 ms | 1.912 ms | 1.242 ms | 897.872 μs | 2.467 ms | 1.437 ms | 941.570 μs | 680.907 μs | 100.725 μs | 50.541 μs |
| anterpolate! Lalescu(3,3) | Float32 128^3 | 197.640 ms | 100.081 ms | 50.847 ms | 28.541 ms | 154.243 ms | 77.841 ms | 39.364 ms | 21.000 ms | 1.257 ms | 897.779 μs |
| anterpolate! Lalescu(3,3) | Float32 256^3 | 2.313 s | 1.165 s | 669.872 ms | 483.110 ms | 1.248 s | 621.235 ms | 313.110 ms | 157.709 ms | 14.164 ms | 14.906 ms |
| anterpolate! Lalescu(3,3) | Float32 512^3 | 21.687 s | 11.570 s | 6.858 s | 5.090 s | 11.808 s | 6.017 s | 3.156 s | 1.859 s | — | — |
| anterpolate! Lalescu(3,3) | Float32 64^3 | 23.886 ms | 13.323 ms | 8.134 ms | 5.592 ms | 19.212 ms | 10.343 ms | 6.337 ms | 4.275 ms | 401.373 μs | 246.973 μs |
| anterpolate! Lalescu(3,3) | Float64 128^3 | 203.551 ms | 105.091 ms | 52.715 ms | 29.850 ms | 154.874 ms | 78.297 ms | 39.745 ms | 21.397 ms | 1.995 ms | 936.339 μs |
| anterpolate! Lalescu(3,3) | Float64 256^3 | 2.781 s | 1.392 s | 837.619 ms | 617.127 ms | 1.381 s | 696.392 ms | 352.388 ms | 184.567 ms | 26.794 ms | 24.205 ms |
| anterpolate! Lalescu(3,3) | Float64 512^3 | 23.251 s | 12.461 s | 7.362 s | 5.495 s | 19.552 s | 9.567 s | 5.135 s | 2.755 s | — | — |
| anterpolate! Lalescu(3,3) | Float64 64^3 | 24.346 ms | 13.244 ms | 8.209 ms | 5.637 ms | 19.247 ms | 10.436 ms | 6.404 ms | 4.339 ms | 563.974 μs | 276.553 μs |
| anterpolate! NUFFT | Float32 128^3 | 396.778 ms | 226.554 ms | 136.043 ms | 108.198 ms | 355.108 ms | 186.437 ms | 94.362 ms | 59.519 ms | 2.950 ms | 2.702 ms |
| anterpolate! NUFFT | Float32 256^3 | 4.215 s | 2.310 s | 1.384 s | 1.018 s | 3.776 s | 1.996 s | 1.115 s | 599.616 ms | 33.140 ms | 28.905 ms |
| anterpolate! NUFFT | Float32 512^3 | 38.579 s | 21.459 s | 12.714 s | 9.095 s | 31.412 s | 16.496 s | 9.109 s | 5.619 s | — | — |
| anterpolate! NUFFT | Float32 64^3 | 31.561 ms | 18.156 ms | 11.315 ms | 8.234 ms | 27.002 ms | 14.295 ms | 8.665 ms | 5.819 ms | 525.400 μs | 326.743 μs |
| anterpolate! NUFFT | Float64 128^3 | 515.978 ms | 298.422 ms | 216.821 ms | 176.299 ms | 421.075 ms | 223.988 ms | 143.263 ms | 109.710 ms | 10.092 ms | 6.612 ms |
| anterpolate! NUFFT | Float64 256^3 | 4.964 s | 2.890 s | 1.931 s | 1.565 s | 3.642 s | 2.037 s | 1.237 s | 887.107 ms | 55.413 ms | 58.998 ms |
| anterpolate! NUFFT | Float64 512^3 | 44.022 s | 25.243 s | 16.235 s | 12.790 s | 40.084 s | 21.842 s | 12.758 s | 8.307 s | — | — |
| anterpolate! NUFFT | Float64 64^3 | 36.987 ms | 21.460 ms | 14.337 ms | 10.866 ms | 33.162 ms | 17.831 ms | 10.717 ms | 7.356 ms | 951.238 μs | 781.277 μs |
| anterpolate! trilinear | Float32 128^3 | 4.695 ms | 2.261 ms | 1.352 ms | 881.126 μs | 4.184 ms | 2.272 ms | 1.243 ms | 746.408 μs | 52.056 μs | 25.770 μs |
| anterpolate! trilinear | Float32 256^3 | 80.940 ms | 44.334 ms | 25.586 ms | 20.086 ms | 44.759 ms | 22.209 ms | 11.816 ms | 6.427 ms | 308.344 μs | 676.007 μs |
| anterpolate! trilinear | Float32 512^3 | 730.809 ms | 400.257 ms | 248.098 ms | 201.541 ms | 553.844 ms | 280.560 ms | 156.384 ms | 89.707 ms | — | — |
| anterpolate! trilinear | Float32 64^3 | 485.517 μs | 322.905 μs | 208.906 μs | 161.045 μs | 345.704 μs | 203.852 μs | 146.222 μs | 107.752 μs | 34.865 μs | 13.010 μs |
| anterpolate! trilinear | Float64 128^3 | 5.140 ms | 2.667 ms | 1.561 ms | 1.087 ms | 6.215 ms | 3.343 ms | 1.820 ms | 1.071 ms | 66.586 μs | 38.681 μs |
| anterpolate! trilinear | Float64 256^3 | 93.226 ms | 51.331 ms | 33.258 ms | 27.126 ms | 59.656 ms | 30.641 ms | 16.399 ms | 9.784 ms | 637.033 μs | 1.054 ms |
| anterpolate! trilinear | Float64 512^3 | 788.544 ms | 452.004 ms | 270.764 ms | 210.306 ms | 584.053 ms | 301.519 ms | 173.367 ms | 98.735 ms | — | — |
| anterpolate! trilinear | Float64 64^3 | 522.769 μs | 338.908 μs | 241.823 μs | 191.637 μs | 354.413 μs | 220.983 μs | 151.891 μs | 114.051 μs | 46.714 μs | 20.440 μs |
| displace! 1-term | Float32 128^3 | 53.830 μs | 34.942 μs | 19.813 μs | 13.012 μs | 45.780 μs | 25.830 μs | 14.090 μs | 9.530 μs | 25.956 μs | 7.670 μs |
| displace! 1-term | Float32 256^3 | 466.209 μs | 263.686 μs | 135.063 μs | 73.291 μs | 365.925 μs | 188.772 μs | 98.501 μs | 53.830 μs | 40.262 μs | 18.200 μs |
| displace! 1-term | Float32 512^3 | 6.036 ms | 5.117 ms | 4.544 ms | 4.130 ms | 3.209 ms | 1.686 ms | 909.449 μs | 733.858 μs | — | — |
| displace! 1-term | Float32 64^3 | 6.737 μs | 7.199 μs | 5.428 μs | 5.967 μs | 5.730 μs | 5.050 μs | 3.530 μs | 4.041 μs | 25.791 μs | 6.365 μs |
| displace! 1-term | Float64 128^3 | 66.863 μs | 36.749 μs | 20.283 μs | 15.228 μs | 48.580 μs | 26.430 μs | 14.190 μs | 9.510 μs | 27.819 μs | 7.720 μs |
| displace! 1-term | Float64 256^3 | 948.336 μs | 557.894 μs | 427.815 μs | 216.328 μs | 387.465 μs | 192.812 μs | 100.432 μs | 53.700 μs | 45.661 μs | 19.630 μs |
| displace! 1-term | Float64 512^3 | 12.090 ms | 11.345 ms | 9.781 ms | 9.269 ms | 4.526 ms | 4.051 ms | 3.904 ms | 3.956 ms | — | — |
| displace! 1-term | Float64 64^3 | 7.078 μs | 7.319 μs | 5.575 μs | 6.599 μs | 5.990 μs | 4.927 μs | 3.638 μs | 3.954 μs | 26.785 μs | 6.425 μs |
| displace! 3-term torus | Float32 128^3 | 866.819 μs | 481.162 μs | 254.967 μs | 159.077 μs | 708.287 μs | 404.695 μs | 210.162 μs | 119.281 μs | 63.789 μs | 23.100 μs |
| displace! 3-term torus | Float32 256^3 | 7.065 ms | 3.756 ms | 1.969 ms | 1.142 ms | 5.678 ms | 3.139 ms | 1.582 ms | 808.208 μs | 58.564 μs | 31.130 μs |
| displace! 3-term torus | Float32 512^3 | 56.790 ms | 29.969 ms | 16.164 ms | 10.334 ms | 45.492 ms | 24.786 ms | 12.454 ms | 6.389 ms | — | — |
| displace! 3-term torus | Float32 64^3 | 107.941 μs | 108.082 μs | 107.937 μs | 105.779 μs | 88.081 μs | 88.201 μs | 88.171 μs | 88.211 μs | 50.365 μs | 22.250 μs |
| displace! 3-term torus | Float64 128^3 | 871.380 μs | 490.514 μs | 258.649 μs | 149.431 μs | 737.058 μs | 420.084 μs | 218.683 μs | 123.541 μs | 53.225 μs | 26.930 μs |
| displace! 3-term torus | Float64 256^3 | 7.025 ms | 3.790 ms | 2.000 ms | 1.410 ms | 5.923 ms | 3.265 ms | 1.656 ms | 846.119 μs | 91.502 μs | 109.381 μs |
| displace! 3-term torus | Float64 512^3 | 56.454 ms | 30.516 ms | 17.740 ms | 16.342 ms | 47.486 ms | 25.984 ms | 13.063 ms | 8.910 ms | — | — |
| displace! 3-term torus | Float64 64^3 | 108.280 μs | 108.158 μs | 108.382 μs | 106.021 μs | 91.731 μs | 91.791 μs | 116.651 μs | 91.721 μs | 65.335 μs | 24.290 μs |
| displace! 3-term | Float32 128^3 | 167.001 μs | 104.950 μs | 56.014 μs | 33.463 μs | 94.461 μs | 80.071 μs | 41.480 μs | 24.140 μs | 28.684 μs | 8.670 μs |
| displace! 3-term | Float32 256^3 | 1.470 ms | 850.045 μs | 470.063 μs | 239.996 μs | 749.128 μs | 603.497 μs | 307.374 μs | 158.851 μs | 45.439 μs | 22.760 μs |
| displace! 3-term | Float32 512^3 | 13.333 ms | 9.474 ms | 8.182 ms | 7.622 ms | 7.980 ms | 5.424 ms | 3.444 ms | 3.414 ms | — | — |
| displace! 3-term | Float32 64^3 | 20.896 μs | 17.857 μs | 11.928 μs | 10.046 μs | 11.570 μs | 12.890 μs | 8.400 μs | 7.150 μs | 25.650 μs | 7.040 μs |
| displace! 3-term | Float64 128^3 | 170.048 μs | 109.853 μs | 56.923 μs | 35.563 μs | 96.251 μs | 83.761 μs | 42.710 μs | 25.160 μs | 33.073 μs | 9.760 μs |
| displace! 3-term | Float64 256^3 | 2.185 ms | 1.698 ms | 1.435 ms | 1.235 ms | 768.280 μs | 642.057 μs | 322.774 μs | 178.481 μs | 64.565 μs | 70.491 μs |
| displace! 3-term | Float64 512^3 | 21.836 ms | 20.060 ms | 17.248 ms | 16.034 ms | 10.507 ms | 9.445 ms | 8.843 ms | 8.802 ms | — | — |
| displace! 3-term | Float64 64^3 | 20.901 μs | 18.513 μs | 11.953 μs | 10.347 μs | 12.320 μs | 13.360 μs | 8.560 μs | 7.430 μs | 29.115 μs | 7.670 μs |
| interpolate! CatmullRom ordered | Float32 128^3 | — | — | — | — | 3.647 ms | 1.869 ms | 940.769 μs | 505.805 μs | — | 73.931 μs |
| interpolate! CatmullRom ordered | Float32 256^3 | — | — | — | — | 56.324 ms | 22.796 ms | 13.350 ms | 6.756 ms | — | 1.034 ms |
| interpolate! CatmullRom ordered | Float32 512^3 | — | — | — | — | 1.571 s | 790.744 ms | 431.660 ms | 253.439 ms | — | — |
| interpolate! CatmullRom ordered | Float32 64^3 | — | — | — | — | 347.913 μs | 186.662 μs | 116.831 μs | 80.051 μs | — | 31.150 μs |
| interpolate! CatmullRom ordered | Float64 128^3 | — | — | — | — | 4.118 ms | 2.121 ms | 1.093 ms | 638.957 μs | — | 103.531 μs |
| interpolate! CatmullRom ordered | Float64 256^3 | — | — | — | — | 141.384 ms | 71.682 ms | 36.633 ms | 20.242 ms | — | 1.756 ms |
| interpolate! CatmullRom ordered | Float64 512^3 | — | — | — | — | 1.753 s | 886.186 ms | 502.247 ms | 292.434 ms | — | — |
| interpolate! CatmullRom ordered | Float64 64^3 | — | — | — | — | 421.224 μs | 224.952 μs | 137.082 μs | 94.731 μs | — | 44.150 μs |
| interpolate! CatmullRom vector ordered | Float32 128^3 | — | — | — | — | 8.427 ms | 4.287 ms | 2.171 ms | 1.196 ms | — | 198.302 μs |
| interpolate! CatmullRom vector ordered | Float32 256^3 | — | — | — | — | 329.966 ms | 169.612 ms | 88.220 ms | 50.035 ms | — | 3.670 ms |
| interpolate! CatmullRom vector ordered | Float32 512^3 | — | — | — | — | 3.314 s | 1.710 s | 922.679 ms | 540.345 ms | — | — |
| interpolate! CatmullRom vector ordered | Float32 64^3 | — | — | — | — | 898.179 μs | 468.165 μs | 283.542 μs | 193.382 μs | — | 75.731 μs |
| interpolate! CatmullRom vector ordered | Float64 128^3 | — | — | — | — | 10.518 ms | 5.370 ms | 2.863 ms | 1.734 ms | — | 251.842 μs |
| interpolate! CatmullRom vector ordered | Float64 256^3 | — | — | — | — | 393.885 ms | 203.397 ms | 113.506 ms | 67.067 ms | — | 5.241 ms |
| interpolate! CatmullRom vector ordered | Float64 512^3 | — | — | — | — | 3.741 s | 1.925 s | 1.074 s | 663.972 ms | — | — |
| interpolate! CatmullRom vector ordered | Float64 64^3 | — | — | — | — | 944.279 μs | 500.795 μs | 304.523 μs | 207.992 μs | — | 91.541 μs |
| interpolate! CatmullRom vector | Float32 128^3 | — | — | — | — | 7.667 ms | 3.955 ms | 1.973 ms | 1.078 ms | — | 204.921 μs |
| interpolate! CatmullRom vector | Float32 256^3 | — | — | — | — | 295.079 ms | 151.885 ms | 78.095 ms | 43.707 ms | — | 3.284 ms |
| interpolate! CatmullRom vector | Float32 512^3 | — | — | — | — | 2.883 s | 1.505 s | 812.994 ms | 484.127 ms | — | — |
| interpolate! CatmullRom vector | Float32 64^3 | — | — | — | — | 831.929 μs | 442.765 μs | 264.923 μs | 180.772 μs | — | 76.541 μs |
| interpolate! CatmullRom vector | Float64 128^3 | — | — | — | — | 9.529 ms | 4.776 ms | 2.555 ms | 1.593 ms | — | 244.672 μs |
| interpolate! CatmullRom vector | Float64 256^3 | — | — | — | — | 349.714 ms | 180.769 ms | 102.455 ms | 60.750 ms | — | 4.789 ms |
| interpolate! CatmullRom vector | Float64 512^3 | — | — | — | — | 3.368 s | 1.739 s | 968.953 ms | 607.341 ms | — | — |
| interpolate! CatmullRom vector | Float64 64^3 | — | — | — | — | 883.309 μs | 465.935 μs | 281.913 μs | 193.742 μs | — | 90.371 μs |
| interpolate! CatmullRom | Float32 128^3 | 11.612 ms | 5.895 ms | 2.955 ms | 1.650 ms | 3.167 ms | 1.607 ms | 806.148 μs | 436.614 μs | 106.344 μs | 75.751 μs |
| interpolate! CatmullRom | Float32 256^3 | 271.654 ms | 139.395 ms | 75.000 ms | 47.020 ms | 38.485 ms | 15.929 ms | 9.225 ms | 4.873 ms | 627.839 μs | 774.018 μs |
| interpolate! CatmullRom | Float32 512^3 | 2.493 s | 1.307 s | 770.720 ms | 536.386 ms | 1.170 s | 580.229 ms | 328.418 ms | 199.346 ms | — | — |
| interpolate! CatmullRom | Float32 64^3 | 1.311 ms | 708.196 μs | 429.733 μs | 300.112 μs | 330.273 μs | 177.422 μs | 107.581 μs | 73.451 μs | 53.885 μs | 29.560 μs |
| interpolate! CatmullRom | Float64 128^3 | 12.345 ms | 6.808 ms | 3.482 ms | 1.941 ms | 3.410 ms | 1.734 ms | 915.839 μs | 531.486 μs | 136.993 μs | 102.941 μs |
| interpolate! CatmullRom | Float64 256^3 | 312.744 ms | 154.605 ms | 88.131 ms | 60.708 ms | 102.727 ms | 52.135 ms | 26.660 ms | 14.578 ms | 1.048 ms | 1.497 ms |
| interpolate! CatmullRom | Float64 512^3 | 2.726 s | 1.439 s | 765.411 ms | 487.613 ms | 1.524 s | 757.008 ms | 431.816 ms | 249.107 ms | — | — |
| interpolate! CatmullRom | Float64 64^3 | 1.360 ms | 739.388 μs | 449.929 μs | 314.905 μs | 379.164 μs | 203.782 μs | 124.551 μs | 85.451 μs | 80.880 μs | 43.851 μs |
| interpolate! Lalescu(3,3) | Float32 128^3 | 73.947 ms | 37.408 ms | 18.912 ms | 10.471 ms | 17.071 ms | 8.626 ms | 4.441 ms | 2.702 ms | 559.598 μs | 229.182 μs |
| interpolate! Lalescu(3,3) | Float32 256^3 | 1.512 s | 784.647 ms | 496.217 ms | 326.458 ms | 200.808 ms | 74.855 ms | 50.358 ms | 25.771 ms | 5.570 ms | 3.497 ms |
| interpolate! Lalescu(3,3) | Float32 512^3 | 15.272 s | 8.498 s | 5.646 s | 3.875 s | 4.526 s | 2.364 s | 1.462 s | 1.027 s | — | — |
| interpolate! Lalescu(3,3) | Float32 64^3 | 8.741 ms | 4.700 ms | 2.857 ms | 1.950 ms | 2.042 ms | 1.064 ms | 652.586 μs | 431.655 μs | 306.223 μs | 76.061 μs |
| interpolate! Lalescu(3,3) | Float64 128^3 | 78.951 ms | 42.466 ms | 21.810 ms | 12.118 ms | 17.242 ms | 8.783 ms | 4.720 ms | 3.192 ms | 824.893 μs | 430.724 μs |
| interpolate! Lalescu(3,3) | Float64 256^3 | 1.986 s | 993.830 ms | 653.060 ms | 434.240 ms | 410.214 ms | 210.002 ms | 107.926 ms | 66.207 ms | 5.306 ms | 8.532 ms |
| interpolate! Lalescu(3,3) | Float64 512^3 | 16.377 s | 8.856 s | 5.559 s | 3.792 s | 6.424 s | 2.995 s | 1.673 s | 830.557 ms | — | — |
| interpolate! Lalescu(3,3) | Float64 64^3 | 8.954 ms | 4.856 ms | 2.961 ms | 2.003 ms | 2.107 ms | 1.112 ms | 674.297 μs | 455.434 μs | 468.356 μs | 140.742 μs |
| interpolate! NUFFT | Float32 128^3 | 307.002 ms | 186.337 ms | 125.670 ms | 97.362 ms | 231.910 ms | 132.865 ms | 65.864 ms | 45.381 ms | 2.090 ms | 1.946 ms |
| interpolate! NUFFT | Float32 256^3 | 3.498 s | 1.980 s | 1.276 s | 917.061 ms | 2.995 s | 1.626 s | 940.719 ms | 548.291 ms | 26.237 ms | 17.873 ms |
| interpolate! NUFFT | Float32 512^3 | 31.922 s | 18.012 s | 11.453 s | 8.282 s | 24.781 s | 13.302 s | 7.687 s | 4.999 s | — | — |
| interpolate! NUFFT | Float32 64^3 | 16.519 ms | 10.207 ms | 6.795 ms | 5.326 ms | 11.987 ms | 6.398 ms | 3.727 ms | 2.440 ms | 413.539 μs | 410.063 μs |
| interpolate! NUFFT | Float64 128^3 | 421.433 ms | 255.981 ms | 192.904 ms | 161.776 ms | 222.849 ms | 126.378 ms | 96.373 ms | 79.822 ms | 8.509 ms | 5.562 ms |
| interpolate! NUFFT | Float64 256^3 | 3.901 s | 2.356 s | 1.699 s | 1.365 s | 2.047 s | 1.254 s | 872.325 ms | 724.205 ms | 40.571 ms | 48.125 ms |
| interpolate! NUFFT | Float64 512^3 | 35.462 s | 20.845 s | 14.870 s | 13.148 s | 24.936 s | 14.207 s | 8.822 s | 9.482 s | — | — |
| interpolate! NUFFT | Float64 64^3 | 21.974 ms | 14.169 ms | 10.812 ms | 9.007 ms | 17.797 ms | 9.837 ms | 6.159 ms | 4.090 ms | 835.506 μs | 898.928 μs |
| interpolate! trilinear | Float32 128^3 | 2.029 ms | 1.026 ms | 520.481 μs | 291.684 μs | 1.091 ms | 556.885 μs | 278.583 μs | 150.772 μs | 32.797 μs | 15.710 μs |
| interpolate! trilinear | Float32 256^3 | 54.025 ms | 28.417 ms | 15.244 ms | 8.952 ms | 12.299 ms | 5.379 ms | 3.061 ms | 1.511 ms | 120.643 μs | 171.502 μs |
| interpolate! trilinear | Float32 512^3 | 482.975 ms | 257.090 ms | 148.905 ms | 97.158 ms | 423.177 ms | 208.919 ms | 108.209 ms | 58.940 ms | — | — |
| interpolate! trilinear | Float32 64^3 | 227.223 μs | 124.212 μs | 77.823 μs | 55.854 μs | 121.391 μs | 66.260 μs | 38.870 μs | 27.501 μs | 30.081 μs | 10.790 μs |
| interpolate! trilinear | Float64 128^3 | 2.207 ms | 1.220 ms | 654.707 μs | 379.324 μs | 1.073 ms | 561.876 μs | 277.553 μs | 152.102 μs | 50.404 μs | 26.440 μs |
| interpolate! trilinear | Float64 256^3 | 60.265 ms | 31.979 ms | 19.700 ms | 13.551 ms | 30.623 ms | 15.069 ms | 7.698 ms | 3.828 ms | 238.024 μs | 300.893 μs |
| interpolate! trilinear | Float64 512^3 | 511.520 ms | 279.357 ms | 155.258 ms | 105.064 ms | 431.950 ms | 213.624 ms | 112.294 ms | 60.785 ms | — | — |
| interpolate! trilinear | Float64 64^3 | 239.320 μs | 132.276 μs | 81.600 μs | 57.898 μs | 129.451 μs | 69.050 μs | 40.391 μs | 27.541 μs | 40.168 μs | 16.920 μs |
| transfer_order | Float32 128^3 | — | — | — | — | 673.237 μs | 426.875 μs | 290.973 μs | 226.882 μs | — | 91.611 μs |
| transfer_order | Float32 256^3 | — | — | — | — | 5.976 ms | 2.996 ms | 1.641 ms | 1.038 ms | — | 204.352 μs |
| transfer_order | Float32 512^3 | — | — | — | — | 58.208 ms | 59.901 ms | 57.533 ms | 42.969 ms | — | — |
| transfer_order | Float32 64^3 | — | — | — | — | 85.271 μs | 145.731 μs | 159.192 μs | 134.821 μs | — | 82.470 μs |
| transfer_order | Float64 128^3 | — | — | — | — | 679.896 μs | 435.664 μs | 289.493 μs | 214.793 μs | — | 89.361 μs |
| transfer_order | Float64 256^3 | — | — | — | — | 6.189 ms | 3.179 ms | 1.777 ms | 1.060 ms | — | 229.202 μs |
| transfer_order | Float64 512^3 | — | — | — | — | 60.184 ms | 34.884 ms | 20.815 ms | 14.718 ms | — | — |
| transfer_order | Float64 64^3 | — | — | — | — | 85.531 μs | 160.481 μs | 155.232 μs | 129.552 μs | — | 81.900 μs |
| wrap! | Float32 128^3 | 526.428 μs | 337.965 μs | 168.903 μs | 114.155 μs | 442.164 μs | 273.323 μs | 139.042 μs | 84.131 μs | 35.636 μs | 10.730 μs |
| wrap! | Float32 256^3 | 4.257 ms | 2.623 ms | 1.303 ms | 848.706 μs | 3.544 ms | 2.144 ms | 1.077 ms | 561.226 μs | 43.670 μs | 14.360 μs |
| wrap! | Float32 512^3 | 34.015 ms | 20.658 ms | 10.568 ms | 7.612 ms | 28.384 ms | 17.112 ms | 8.567 ms | 4.913 ms | — | — |
| wrap! | Float32 64^3 | 65.705 μs | 65.589 μs | 65.615 μs | 64.332 μs | 55.270 μs | 55.280 μs | 55.331 μs | 55.361 μs | 34.478 μs | 10.820 μs |
| wrap! | Float64 128^3 | 576.324 μs | 370.903 μs | 194.994 μs | 125.910 μs | 441.344 μs | 282.363 μs | 142.911 μs | 86.421 μs | 39.668 μs | 15.940 μs |
| wrap! | Float64 256^3 | 4.660 ms | 2.957 ms | 1.508 ms | 887.407 μs | 3.538 ms | 2.194 ms | 1.105 ms | 574.577 μs | 52.011 μs | 58.830 μs |
| wrap! | Float64 512^3 | 37.471 ms | 23.418 ms | 11.922 ms | 7.668 ms | 28.333 ms | 17.493 ms | 8.815 ms | 4.458 ms | — | — |
| wrap! | Float64 64^3 | 71.689 μs | 71.537 μs | 71.838 μs | 70.138 μs | 58.031 μs | 55.151 μs | 55.191 μs | 55.150 μs | 35.852 μs | 12.080 μs |

## reductions

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| co-spectrum vec.vec | Float32 128^3 | 8.085 ms | 6.996 ms | 8.357 ms | 7.972 ms | 6.955 ms | 5.053 ms | 5.864 ms | 6.421 ms | 296.995 μs | 175.002 μs |
| co-spectrum vec.vec | Float32 256^3 | 64.252 ms | 47.546 ms | 45.730 ms | 42.525 ms | 55.586 ms | 36.310 ms | 31.485 ms | 31.862 ms | 966.187 μs | 838.338 μs |
| co-spectrum vec.vec | Float32 512^3 | 510.689 ms | 356.734 ms | 266.038 ms | 229.071 ms | 447.260 ms | 266.297 ms | 190.143 ms | 154.457 ms | — | — |
| co-spectrum vec.vec | Float32 64^3 | 1.044 ms | 1.386 ms | 1.531 ms | 1.605 ms | 905.729 μs | 934.539 μs | 1.207 ms | 1.255 ms | 221.511 μs | 71.841 μs |
| co-spectrum vec.vec | Float64 128^3 | 8.408 ms | 6.415 ms | 5.999 ms | 5.322 ms | 7.293 ms | 5.117 ms | 4.571 ms | 4.438 ms | 17.366 ms | 258.092 μs |
| co-spectrum vec.vec | Float64 256^3 | 67.386 ms | 48.673 ms | 36.466 ms | 31.465 ms | 58.738 ms | 37.545 ms | 27.326 ms | 22.699 ms | 56.569 ms | 1.158 ms |
| co-spectrum vec.vec | Float64 512^3 | 556.430 ms | 370.769 ms | 239.490 ms | 195.985 ms | 476.161 ms | 282.807 ms | 172.999 ms | 129.276 ms | — | — |
| co-spectrum vec.vec | Float64 64^3 | 1.062 ms | 792.529 μs | 975.719 μs | 996.385 μs | 941.000 μs | 746.947 μs | 860.368 μs | 937.539 μs | 7.115 ms | 77.551 μs |
| cov vector | Float32 128^3 | 2.186 ms | 1.196 ms | 635.824 μs | 349.018 μs | 1.129 ms | 579.296 μs | 298.463 μs | 180.212 μs | 581.866 μs | 146.661 μs |
| cov vector | Float32 256^3 | 20.981 ms | 13.773 ms | 11.064 ms | 10.073 ms | 12.767 ms | 8.212 ms | 5.247 ms | 4.682 ms | 2.722 ms | 830.578 μs |
| cov vector | Float32 512^3 | 170.198 ms | 115.954 ms | 94.519 ms | 88.892 ms | 94.777 ms | 63.954 ms | 55.212 ms | 55.272 ms | — | — |
| cov vector | Float32 64^3 | 252.111 μs | 140.531 μs | 78.922 μs | 61.631 μs | 141.221 μs | 79.681 μs | 45.721 μs | 34.680 μs | 305.309 μs | 85.921 μs |
| cov vector | Float64 128^3 | 3.974 ms | 2.651 ms | 2.119 ms | 1.722 ms | 2.213 ms | 1.122 ms | 570.636 μs | 316.384 μs | 837.775 μs | 193.531 μs |
| cov vector | Float64 256^3 | 34.336 ms | 26.329 ms | 22.854 ms | 21.660 ms | 25.423 ms | 15.473 ms | 12.421 ms | 12.522 ms | 4.665 ms | 1.104 ms |
| cov vector | Float64 512^3 | 274.468 ms | 212.966 ms | 190.661 ms | 179.491 ms | 185.942 ms | 128.569 ms | 111.300 ms | 111.557 ms | — | — |
| cov vector | Float64 64^3 | 352.395 μs | 191.454 μs | 106.185 μs | 75.328 μs | 274.242 μs | 146.852 μs | 81.260 μs | 54.591 μs | 364.179 μs | 97.221 μs |
| cross-correlation vec.vec | Float32 128^3 | 37.668 ms | 33.117 ms | 33.833 ms | 33.859 ms | 32.907 ms | 24.414 ms | 22.285 ms | 21.375 ms | 755.001 μs | 563.865 μs |
| cross-correlation vec.vec | Float32 256^3 | 410.005 ms | 309.678 ms | 266.738 ms | 252.627 ms | 303.291 ms | 194.114 ms | 157.646 ms | 161.325 ms | 10.565 ms | 6.518 ms |
| cross-correlation vec.vec | Float32 512^3 | 3.812 s | 2.621 s | 1.856 s | 1.636 s | 2.935 s | 1.859 s | 1.394 s | 1.158 s | — | — |
| cross-correlation vec.vec | Float32 64^3 | 4.645 ms | 5.312 ms | 5.499 ms | 5.723 ms | 3.841 ms | 3.546 ms | 3.853 ms | 3.693 ms | 205.515 μs | 154.611 μs |
| cross-correlation vec.vec | Float64 128^3 | 57.857 ms | 55.261 ms | 41.756 ms | 49.781 ms | 40.003 ms | 38.574 ms | 25.627 ms | 24.757 ms | 36.448 ms | 1.938 ms |
| cross-correlation vec.vec | Float64 256^3 | 581.596 ms | 456.868 ms | 371.550 ms | 351.100 ms | 502.430 ms | 344.836 ms | 255.767 ms | 252.309 ms | 133.169 ms | 15.074 ms |
| cross-correlation vec.vec | Float64 512^3 | 5.734 s | 3.790 s | 2.943 s | 2.533 s | 4.475 s | 2.917 s | 2.091 s | 1.782 s | — | — |
| cross-correlation vec.vec | Float64 64^3 | 5.685 ms | 5.331 ms | 5.601 ms | 5.462 ms | 4.293 ms | 3.469 ms | 3.461 ms | 3.356 ms | 12.942 ms | 260.292 μs |
| inner spectral | Float32 128^3 | 2.464 ms | 1.649 ms | 1.380 ms | 1.229 ms | 1.434 ms | 808.088 μs | 494.375 μs | 364.304 μs | 200.948 μs | 120.061 μs |
| inner spectral | Float32 256^3 | 21.204 ms | 16.705 ms | 14.751 ms | 13.651 ms | 12.720 ms | 8.072 ms | 7.086 ms | 7.107 ms | 708.328 μs | 624.566 μs |
| inner spectral | Float32 512^3 | 164.737 ms | 128.807 ms | 112.670 ms | 106.006 ms | 106.804 ms | 79.869 ms | 69.979 ms | 70.829 ms | — | — |
| inner spectral | Float32 64^3 | 305.237 μs | 196.626 μs | 138.790 μs | 113.332 μs | 210.982 μs | 121.861 μs | 82.770 μs | 76.781 μs | 188.383 μs | 73.561 μs |
| inner spectral | Float64 128^3 | 4.140 ms | 3.536 ms | 3.107 ms | 2.850 ms | 1.880 ms | 1.088 ms | 722.667 μs | 601.616 μs | 252.487 μs | 200.782 μs |
| inner spectral | Float64 256^3 | 34.526 ms | 29.659 ms | 27.514 ms | 26.111 ms | 18.732 ms | 15.904 ms | 15.603 ms | 15.238 ms | 1.182 ms | 1.112 ms |
| inner spectral | Float64 512^3 | 255.858 ms | 226.744 ms | 211.250 ms | 199.676 ms | 137.901 ms | 132.354 ms | 126.422 ms | 127.880 ms | — | — |
| inner spectral | Float64 64^3 | 309.165 μs | 210.033 μs | 148.238 μs | 127.392 μs | 225.993 μs | 134.421 μs | 90.910 μs | 85.080 μs | 199.280 μs | 80.650 μs |
| inner vec.vec | Float32 128^3 | 1.323 ms | 950.160 μs | 816.944 μs | 711.423 μs | 388.584 μs | 195.622 μs | 100.441 μs | 71.860 μs | 49.104 μs | 30.500 μs |
| inner vec.vec | Float32 256^3 | 13.030 ms | 12.119 ms | 11.438 ms | 10.654 ms | 7.434 ms | 6.470 ms | 5.782 ms | 5.914 ms | 478.617 μs | 489.195 μs |
| inner vec.vec | Float32 512^3 | 104.969 ms | 99.526 ms | 96.158 ms | 89.634 ms | 65.750 ms | 58.003 ms | 55.295 ms | 55.838 ms | — | — |
| inner vec.vec | Float32 64^3 | 69.599 μs | 38.926 μs | 20.420 μs | 14.923 μs | 46.241 μs | 25.741 μs | 14.620 μs | 11.330 μs | 50.158 μs | 12.970 μs |
| inner vec.vec | Float64 128^3 | 2.926 ms | 2.506 ms | 2.293 ms | 2.133 ms | 1.157 ms | 644.167 μs | 325.423 μs | 239.522 μs | 118.997 μs | 134.851 μs |
| inner vec.vec | Float64 256^3 | 25.489 ms | 24.512 ms | 23.201 ms | 22.283 ms | 15.251 ms | 13.960 ms | 13.219 ms | 13.173 ms | 918.815 μs | 963.440 μs |
| inner vec.vec | Float64 512^3 | 212.011 ms | 198.041 ms | 189.067 ms | 178.007 ms | 125.692 ms | 114.536 ms | 112.479 ms | 112.441 ms | — | — |
| inner vec.vec | Float64 64^3 | 136.661 μs | 76.001 μs | 39.834 μs | 25.515 μs | 87.721 μs | 46.370 μs | 25.580 μs | 17.640 μs | 41.269 μs | 18.460 μs |
| integral scalar | Float32 128^3 | 113.205 μs | 61.734 μs | 29.627 μs | 19.984 μs | 61.371 μs | 33.681 μs | 20.921 μs | 12.950 μs | 132.394 μs | 31.680 μs |
| integral scalar | Float32 256^3 | 2.043 ms | 1.488 ms | 1.294 ms | 1.174 ms | 549.207 μs | 275.203 μs | 163.622 μs | 99.021 μs | 616.028 μs | 175.422 μs |
| integral scalar | Float32 512^3 | 19.678 ms | 15.746 ms | 14.784 ms | 14.224 ms | 10.766 ms | 9.397 ms | 9.028 ms | 8.864 ms | — | — |
| integral scalar | Float32 64^3 | 9.752 μs | 6.550 μs | 5.648 μs | 5.799 μs | 6.918 μs | 4.880 μs | 4.120 μs | 5.242 μs | 78.012 μs | 17.950 μs |
| integral scalar | Float64 128^3 | 253.999 μs | 119.139 μs | 66.851 μs | 38.885 μs | 121.721 μs | 63.361 μs | 36.680 μs | 23.351 μs | 149.039 μs | 32.580 μs |
| integral scalar | Float64 256^3 | 4.362 ms | 3.558 ms | 3.275 ms | 3.026 ms | 1.632 ms | 1.114 ms | 812.009 μs | 963.730 μs | 732.824 μs | 192.012 μs |
| integral scalar | Float64 512^3 | 37.576 ms | 32.135 ms | 30.033 ms | 29.174 ms | 20.531 ms | 18.597 ms | 18.159 ms | 18.072 ms | — | — |
| integral scalar | Float64 64^3 | 26.255 μs | 12.381 μs | 8.008 μs | 7.622 μs | 14.920 μs | 7.900 μs | 5.938 μs | 5.830 μs | 77.526 μs | 19.330 μs |
| integral spectral vec | Float32 128^3 | 66.121 ns | 66.808 ns | 67.436 ns | 82.462 ns | 71.240 ns | 69.673 ns | 69.315 ns | 71.692 ns | 82.405 μs | 12.780 μs |
| integral spectral vec | Float32 256^3 | 66.484 ns | 67.441 ns | 67.777 ns | 83.150 ns | 71.651 ns | 71.067 ns | 70.401 ns | 70.257 ns | 73.638 μs | 12.620 μs |
| integral spectral vec | Float32 512^3 | 66.418 ns | 67.951 ns | 67.861 ns | 84.149 ns | 72.030 ns | 72.863 ns | 73.720 ns | 69.192 ns | — | — |
| integral spectral vec | Float32 64^3 | 65.864 ns | 66.969 ns | 66.995 ns | 81.421 ns | 73.121 ns | 70.669 ns | 69.489 ns | 74.995 ns | 78.881 μs | 13.000 μs |
| integral spectral vec | Float64 128^3 | 69.031 ns | 68.348 ns | 69.255 ns | 69.653 ns | 74.637 ns | 73.351 ns | 72.016 ns | 79.590 ns | 73.952 μs | 13.131 μs |
| integral spectral vec | Float64 256^3 | 69.175 ns | 68.795 ns | 69.299 ns | 69.459 ns | 77.311 ns | 76.466 ns | 73.555 ns | 73.921 ns | 73.752 μs | 13.160 μs |
| integral spectral vec | Float64 512^3 | 69.652 ns | 69.119 ns | 70.031 ns | 70.912 ns | 78.399 ns | 78.705 ns | 78.495 ns | 77.668 ns | — | — |
| integral spectral vec | Float64 64^3 | 68.569 ns | 67.415 ns | 67.973 ns | 68.004 ns | 76.575 ns | 75.463 ns | 74.302 ns | 74.814 ns | 81.821 μs | 12.800 μs |
| l2norm vec | Float32 128^3 | 527.126 μs | 314.725 μs | 177.046 μs | 94.345 μs | 249.532 μs | 129.191 μs | 71.291 μs | 39.721 μs | 47.642 μs | 19.980 μs |
| l2norm vec | Float32 256^3 | 7.466 ms | 5.850 ms | 5.401 ms | 4.965 ms | 4.108 ms | 2.870 ms | 1.948 ms | 2.010 ms | 264.733 μs | 258.592 μs |
| l2norm vec | Float32 512^3 | 62.425 ms | 49.766 ms | 46.270 ms | 44.568 ms | 41.560 ms | 30.681 ms | 26.714 ms | 27.026 ms | — | — |
| l2norm vec | Float32 64^3 | 49.336 μs | 27.655 μs | 18.780 μs | 12.689 μs | 31.890 μs | 17.010 μs | 9.790 μs | 8.030 μs | 48.230 μs | 12.240 μs |
| l2norm vec | Float64 128^3 | 1.520 ms | 1.074 ms | 797.428 μs | 711.305 μs | 506.955 μs | 252.683 μs | 127.311 μs | 75.901 μs | 86.147 μs | 33.701 μs |
| l2norm vec | Float64 256^3 | 14.901 ms | 12.033 ms | 11.085 ms | 10.333 ms | 12.136 ms | 7.295 ms | 5.663 ms | 5.525 ms | 532.296 μs | 491.425 μs |
| l2norm vec | Float64 512^3 | 120.359 ms | 99.080 ms | 91.019 ms | 87.536 ms | 95.940 ms | 62.201 ms | 54.589 ms | 54.973 ms | — | — |
| l2norm vec | Float64 64^3 | 92.392 μs | 50.919 μs | 33.041 μs | 18.714 μs | 59.161 μs | 30.891 μs | 17.210 μs | 11.290 μs | 42.664 μs | 17.130 μs |
| lpnorm vec Inf | Float32 128^3 | 1.334 ms | 1.254 ms | 1.087 ms | 947.451 μs | 463.304 μs | 388.824 μs | 333.483 μs | 338.524 μs | 185.653 μs | 66.011 μs |
| lpnorm vec Inf | Float32 256^3 | 13.946 ms | 13.173 ms | 11.556 ms | 10.649 ms | 8.558 ms | 7.443 ms | 7.308 ms | 8.842 ms | 1.070 ms | 506.725 μs |
| lpnorm vec Inf | Float32 512^3 | 114.652 ms | 113.167 ms | 93.098 ms | 85.454 ms | 77.598 ms | 71.842 ms | 70.319 ms | 71.557 ms | — | — |
| lpnorm vec Inf | Float32 64^3 | 96.370 μs | 94.096 μs | 73.549 μs | 84.637 μs | 61.221 μs | 49.410 μs | 42.480 μs | 42.661 μs | 90.800 μs | 24.690 μs |
| lpnorm vec Inf | Float64 128^3 | 3.053 ms | 3.183 ms | 2.631 ms | 2.427 ms | 1.204 ms | 1.038 ms | 937.679 μs | 986.931 μs | 288.572 μs | 115.032 μs |
| lpnorm vec Inf | Float64 256^3 | 27.785 ms | 26.396 ms | 22.963 ms | 21.540 ms | 17.413 ms | 15.442 ms | 16.616 ms | 15.935 ms | 1.913 ms | 940.439 μs |
| lpnorm vec Inf | Float64 512^3 | 223.561 ms | 213.045 ms | 187.236 ms | 172.938 ms | 138.848 ms | 137.789 ms | 140.560 ms | 139.527 ms | — | — |
| lpnorm vec Inf | Float64 64^3 | 233.247 μs | 174.915 μs | 147.324 μs | 136.472 μs | 111.021 μs | 92.231 μs | 76.861 μs | 73.241 μs | 106.389 μs | 34.590 μs |
| maximum scalar | Float32 128^3 | 338.342 μs | 176.640 μs | 92.078 μs | 77.879 μs | 238.352 μs | 117.732 μs | 61.421 μs | 33.070 μs | 135.669 μs | 31.500 μs |
| maximum scalar | Float32 256^3 | 3.407 ms | 1.898 ms | 1.402 ms | 1.188 ms | 2.002 ms | 944.690 μs | 487.845 μs | 249.813 μs | 616.535 μs | 175.282 μs |
| maximum scalar | Float32 512^3 | 24.096 ms | 17.667 ms | 15.267 ms | 14.287 ms | 31.382 ms | 12.720 ms | 9.007 ms | 8.138 ms | — | — |
| maximum scalar | Float32 64^3 | 42.020 μs | 24.577 μs | 13.945 μs | 11.582 μs | 29.560 μs | 15.870 μs | 9.320 μs | 6.930 μs | 78.495 μs | 17.610 μs |
| maximum scalar | Float64 128^3 | 565.846 μs | 278.395 μs | 143.150 μs | 133.460 μs | 440.814 μs | 222.262 μs | 113.642 μs | 59.651 μs | 172.935 μs | 40.740 μs |
| maximum scalar | Float64 256^3 | 6.135 ms | 3.934 ms | 3.395 ms | 3.044 ms | 4.043 ms | 2.036 ms | 1.099 ms | 824.389 μs | 972.353 μs | 214.182 μs |
| maximum scalar | Float64 512^3 | 48.714 ms | 33.445 ms | 30.564 ms | 29.127 ms | 44.789 ms | 26.944 ms | 19.316 ms | 17.364 ms | — | — |
| maximum scalar | Float64 64^3 | 65.250 μs | 36.625 μs | 21.048 μs | 14.741 μs | 55.340 μs | 29.610 μs | 15.810 μs | 9.970 μs | 80.807 μs | 24.020 μs |
| maximum(norm) vec | Float32 128^3 | 1.799 ms | 947.000 μs | 474.822 μs | 245.647 μs | 773.618 μs | 389.324 μs | 197.281 μs | 105.381 μs | 194.976 μs | 41.650 μs |
| maximum(norm) vec | Float32 256^3 | 15.151 ms | 8.169 ms | 5.709 ms | 5.004 ms | 8.475 ms | 3.923 ms | 2.454 ms | 2.121 ms | 852.612 μs | 283.012 μs |
| maximum(norm) vec | Float32 512^3 | 118.979 ms | 67.746 ms | 49.904 ms | 45.549 ms | 58.330 ms | 37.931 ms | 29.689 ms | 28.233 ms | — | — |
| maximum(norm) vec | Float32 64^3 | 220.737 μs | 116.548 μs | 61.320 μs | 74.226 μs | 96.891 μs | 49.131 μs | 26.730 μs | 15.400 μs | 91.731 μs | 20.080 μs |
| maximum(norm) vec | Float64 128^3 | 5.214 ms | 2.699 ms | 1.383 ms | 823.695 μs | 1.587 ms | 793.968 μs | 400.894 μs | 212.383 μs | 252.937 μs | 129.732 μs |
| maximum(norm) vec | Float64 256^3 | 42.183 ms | 21.531 ms | 12.660 ms | 11.079 ms | 14.279 ms | 8.345 ms | 6.050 ms | 5.845 ms | 1.624 ms | 858.829 μs |
| maximum(norm) vec | Float64 512^3 | 336.030 ms | 171.441 ms | 106.202 ms | 92.733 ms | 126.735 ms | 73.108 ms | 58.531 ms | 56.879 ms | — | — |
| maximum(norm) vec | Float64 64^3 | 638.858 μs | 329.832 μs | 168.017 μs | 90.193 μs | 200.822 μs | 101.681 μs | 52.230 μs | 28.440 μs | 99.986 μs | 33.560 μs |
| mean spectral vec | Float32 128^3 | 68.912 ns | 70.049 ns | 70.289 ns | 70.490 ns | 73.919 ns | 72.396 ns | 71.544 ns | 76.506 ns | 79.850 μs | 12.661 μs |
| mean spectral vec | Float32 256^3 | 69.607 ns | 70.568 ns | 70.640 ns | 70.658 ns | 73.976 ns | 73.150 ns | 72.117 ns | 72.425 ns | 79.489 μs | 12.700 μs |
| mean spectral vec | Float32 512^3 | 70.361 ns | 74.360 ns | 70.561 ns | 72.088 ns | 74.483 ns | 74.155 ns | 75.026 ns | 73.194 ns | — | — |
| mean spectral vec | Float32 64^3 | 69.389 ns | 70.450 ns | 69.490 ns | 69.618 ns | 76.115 ns | 73.865 ns | 71.048 ns | 74.567 ns | 82.207 μs | 12.870 μs |
| mean spectral vec | Float64 128^3 | 71.489 ns | 72.792 ns | 72.690 ns | 72.359 ns | 77.486 ns | 76.192 ns | 77.119 ns | 78.135 ns | 79.575 μs | 13.080 μs |
| mean spectral vec | Float64 256^3 | 72.023 ns | 72.870 ns | 72.888 ns | 73.692 ns | 79.392 ns | 77.658 ns | 79.929 ns | 75.757 ns | 73.475 μs | 12.850 μs |
| mean spectral vec | Float64 512^3 | 72.260 ns | 79.126 ns | 73.249 ns | 74.082 ns | 81.714 ns | 80.280 ns | 83.489 ns | 79.814 ns | — | — |
| mean spectral vec | Float64 64^3 | 71.541 ns | 71.722 ns | 71.249 ns | 70.881 ns | 78.617 ns | 78.574 ns | 79.546 ns | 79.545 ns | 81.598 μs | 13.040 μs |
| mean vector | Float32 128^3 | 436.861 μs | 275.585 μs | 172.486 μs | 97.294 μs | 196.452 μs | 106.832 μs | 60.631 μs | 45.211 μs | 402.046 μs | 97.041 μs |
| mean vector | Float32 256^3 | 6.719 ms | 5.740 ms | 5.323 ms | 5.010 ms | 2.955 ms | 2.601 ms | 2.378 ms | 2.428 ms | 1.854 ms | 532.326 μs |
| mean vector | Float32 512^3 | 58.139 ms | 48.680 ms | 44.902 ms | 43.607 ms | 28.612 ms | 27.453 ms | 26.914 ms | 27.202 ms | — | — |
| mean vector | Float32 64^3 | 41.575 μs | 28.263 μs | 19.642 μs | 22.649 μs | 26.260 μs | 16.101 μs | 13.271 μs | 16.670 μs | 233.114 μs | 55.111 μs |
| mean vector | Float64 128^3 | 1.368 ms | 933.480 μs | 770.661 μs | 717.190 μs | 405.604 μs | 206.232 μs | 109.711 μs | 83.171 μs | 436.590 μs | 105.791 μs |
| mean vector | Float64 256^3 | 14.052 ms | 11.870 ms | 11.077 ms | 10.448 ms | 8.764 ms | 7.028 ms | 6.598 ms | 6.607 ms | 2.206 ms | 578.496 μs |
| mean vector | Float64 512^3 | 113.193 ms | 97.006 ms | 90.840 ms | 87.788 ms | 59.155 ms | 55.405 ms | 54.357 ms | 54.957 ms | — | — |
| mean vector | Float64 64^3 | 84.427 μs | 48.544 μs | 30.783 μs | 29.104 μs | 46.641 μs | 31.170 μs | 19.820 μs | 18.480 μs | 242.233 μs | 60.311 μs |
| mean(det) tensor | Float32 128^3 | 2.417 ms | 1.854 ms | 1.598 ms | 1.497 ms | 773.457 μs | 364.684 μs | 197.372 μs | 122.662 μs | 188.881 μs | 113.481 μs |
| mean(det) tensor | Float32 256^3 | 21.277 ms | 20.099 ms | 18.172 ms | 17.264 ms | 15.771 ms | 11.669 ms | 10.300 ms | 10.414 ms | 1.105 ms | 744.398 μs |
| mean(det) tensor | Float32 512^3 | 172.153 ms | 163.945 ms | 149.988 ms | 143.179 ms | 105.720 ms | 95.093 ms | 84.211 ms | 85.725 ms | — | — |
| mean(det) tensor | Float32 64^3 | 104.177 μs | 54.345 μs | 28.867 μs | 21.326 μs | 67.911 μs | 36.300 μs | 21.080 μs | 15.120 μs | 85.536 μs | 24.960 μs |
| mean(det) tensor | Float64 128^3 | 5.149 ms | 4.545 ms | 3.887 ms | 3.631 ms | 2.559 ms | 1.501 ms | 1.203 ms | 1.215 ms | 258.338 μs | 202.542 μs |
| mean(det) tensor | Float64 256^3 | 41.379 ms | 40.368 ms | 37.887 ms | 35.177 ms | 30.046 ms | 23.878 ms | 21.582 ms | 21.552 ms | 1.686 ms | 1.449 ms |
| mean(det) tensor | Float64 512^3 | 325.205 ms | 326.577 ms | 300.634 ms | 283.598 ms | 228.934 ms | 185.116 ms | 169.237 ms | 172.437 ms | — | — |
| mean(det) tensor | Float64 64^3 | 224.659 μs | 127.893 μs | 74.006 μs | 38.604 μs | 168.142 μs | 67.661 μs | 36.360 μs | 28.720 μs | 90.194 μs | 28.840 μs |
| mean(norm) vec | Float32 128^3 | 1.550 ms | 812.954 μs | 406.340 μs | 213.901 μs | 611.166 μs | 301.773 μs | 155.732 μs | 84.761 μs | 241.001 μs | 41.551 μs |
| mean(norm) vec | Float32 256^3 | 12.965 ms | 7.522 ms | 5.637 ms | 4.998 ms | 7.630 ms | 3.581 ms | 2.334 ms | 2.129 ms | 848.973 μs | 282.373 μs |
| mean(norm) vec | Float32 512^3 | 101.664 ms | 63.563 ms | 49.462 ms | 45.365 ms | 51.592 ms | 36.426 ms | 29.222 ms | 28.205 ms | — | — |
| mean(norm) vec | Float32 64^3 | 189.160 μs | 100.213 μs | 52.956 μs | 67.516 μs | 76.531 μs | 39.851 μs | 21.090 μs | 13.021 μs | 87.347 μs | 20.030 μs |
| mean(norm) vec | Float64 128^3 | 5.147 ms | 2.663 ms | 1.349 ms | 830.769 μs | 1.451 ms | 724.877 μs | 364.814 μs | 194.562 μs | 236.768 μs | 113.051 μs |
| mean(norm) vec | Float64 256^3 | 41.522 ms | 21.232 ms | 12.635 ms | 11.159 ms | 13.324 ms | 8.210 ms | 5.873 ms | 5.829 ms | 1.371 ms | 744.878 μs |
| mean(norm) vec | Float64 512^3 | 331.193 ms | 168.941 ms | 105.211 ms | 92.581 ms | 113.281 ms | 71.836 ms | 57.876 ms | 56.753 ms | — | — |
| mean(norm) vec | Float64 64^3 | 631.535 μs | 326.034 μs | 168.591 μs | 88.614 μs | 179.141 μs | 91.741 μs | 47.980 μs | 26.601 μs | 97.683 μs | 29.230 μs |
| mean(tr) tensor | Float32 128^3 | 399.009 μs | 245.872 μs | 147.045 μs | 59.212 μs | 193.452 μs | 95.311 μs | 52.290 μs | 36.960 μs | 146.458 μs | 39.320 μs |
| mean(tr) tensor | Float32 256^3 | 6.131 ms | 5.862 ms | 5.338 ms | 4.961 ms | 3.197 ms | 2.380 ms | 2.203 ms | 2.248 ms | 715.643 μs | 274.963 μs |
| mean(tr) tensor | Float32 512^3 | 51.993 ms | 49.935 ms | 47.562 ms | 45.092 ms | 33.637 ms | 31.377 ms | 27.724 ms | 28.224 ms | — | — |
| mean(tr) tensor | Float32 64^3 | 35.048 μs | 18.580 μs | 11.830 μs | 10.177 μs | 25.450 μs | 12.570 μs | 8.070 μs | 6.330 μs | 77.980 μs | 20.170 μs |
| mean(tr) tensor | Float64 128^3 | 1.280 ms | 949.800 μs | 800.417 μs | 692.895 μs | 395.014 μs | 178.902 μs | 93.931 μs | 74.211 μs | 162.643 μs | 48.340 μs |
| mean(tr) tensor | Float64 256^3 | 12.499 ms | 11.853 ms | 11.372 ms | 10.742 ms | 7.026 ms | 6.539 ms | 6.370 ms | 6.234 ms | 878.142 μs | 500.395 μs |
| mean(tr) tensor | Float64 512^3 | 104.298 ms | 100.708 ms | 95.066 ms | 88.987 ms | 78.651 ms | 60.699 ms | 55.700 ms | 56.931 ms | — | — |
| mean(tr) tensor | Float64 64^3 | 66.817 μs | 37.152 μs | 19.666 μs | 15.579 μs | 50.970 μs | 24.470 μs | 14.221 μs | 10.170 μs | 83.085 μs | 21.360 μs |
| radial_correlation vec | Float32 128^3 | 35.571 ms | 31.061 ms | 32.612 ms | 33.624 ms | 30.250 ms | 21.843 ms | 21.607 ms | 20.799 ms | 709.383 μs | 538.235 μs |
| radial_correlation vec | Float32 256^3 | 395.970 ms | 314.312 ms | 262.237 ms | 252.597 ms | 279.445 ms | 178.171 ms | 155.845 ms | 158.980 ms | 10.395 ms | 6.336 ms |
| radial_correlation vec | Float32 512^3 | 3.675 s | 2.544 s | 1.847 s | 1.613 s | 2.760 s | 1.743 s | 1.282 s | 1.106 s | — | — |
| radial_correlation vec | Float32 64^3 | 4.240 ms | 5.099 ms | 5.427 ms | 5.669 ms | 3.519 ms | 3.292 ms | 3.730 ms | 3.454 ms | 207.811 μs | 153.551 μs |
| radial_correlation vec | Float64 128^3 | 56.335 ms | 54.616 ms | 40.099 ms | 53.887 ms | 37.444 ms | 33.975 ms | 24.580 ms | 23.638 ms | 36.483 ms | 1.878 ms |
| radial_correlation vec | Float64 256^3 | 566.203 ms | 448.656 ms | 331.754 ms | 311.984 ms | 476.153 ms | 320.011 ms | 270.548 ms | 244.050 ms | 146.621 ms | 14.580 ms |
| radial_correlation vec | Float64 512^3 | 5.581 s | 3.664 s | 2.900 s | 2.448 s | 4.311 s | 2.792 s | 1.967 s | 1.727 s | — | — |
| radial_correlation vec | Float64 64^3 | 5.404 ms | 5.254 ms | 5.408 ms | 5.205 ms | 3.823 ms | 3.356 ms | 3.261 ms | 3.355 ms | 12.963 ms | 257.092 μs |
| radial_spectrum vec | Float32 128^3 | 7.479 ms | 6.857 ms | 8.635 ms | 8.641 ms | 6.328 ms | 4.769 ms | 5.731 ms | 5.831 ms | 324.002 μs | 172.952 μs |
| radial_spectrum vec | Float32 256^3 | 59.601 ms | 42.973 ms | 45.793 ms | 44.093 ms | 50.112 ms | 33.734 ms | 30.885 ms | 29.936 ms | 914.928 μs | 824.718 μs |
| radial_spectrum vec | Float32 512^3 | 474.263 ms | 342.922 ms | 255.081 ms | 223.928 ms | 399.577 ms | 238.150 ms | 181.107 ms | 153.786 ms | — | — |
| radial_spectrum vec | Float32 64^3 | 983.294 μs | 1.382 ms | 1.620 ms | 1.671 ms | 821.738 μs | 869.578 μs | 1.178 ms | 1.280 ms | 218.318 μs | 70.131 μs |
| radial_spectrum vec | Float64 128^3 | 7.569 ms | 5.352 ms | 6.003 ms | 6.026 ms | 6.543 ms | 4.581 ms | 4.535 ms | 4.304 ms | 17.742 ms | 250.862 μs |
| radial_spectrum vec | Float64 256^3 | 60.230 ms | 44.482 ms | 35.347 ms | 30.127 ms | 51.926 ms | 32.112 ms | 26.082 ms | 22.797 ms | 54.973 ms | 1.137 ms |
| radial_spectrum vec | Float64 512^3 | 483.046 ms | 338.977 ms | 217.670 ms | 173.729 ms | 414.658 ms | 255.715 ms | 169.072 ms | 124.622 ms | — | — |
| radial_spectrum vec | Float64 64^3 | 973.498 μs | 917.307 μs | 1.154 ms | 1.081 ms | 846.298 μs | 691.227 μs | 848.008 μs | 893.579 μs | 7.040 ms | 77.171 μs |
| reality_residual scalar | Float32 128^3 | 229.590 μs | 230.235 μs | 231.314 μs | 230.178 μs | 168.162 μs | 167.272 μs | 168.391 μs | 167.512 μs | 243.074 μs | 82.831 μs |
| reality_residual scalar | Float32 256^3 | 1.021 ms | 1.017 ms | 1.024 ms | 1.021 ms | 684.498 μs | 686.717 μs | 689.117 μs | 686.127 μs | 226.455 μs | 82.941 μs |
| reality_residual scalar | Float32 512^3 | 8.106 ms | 8.105 ms | 8.193 ms | 8.774 ms | 2.720 ms | 2.762 ms | 2.799 ms | 2.770 ms | — | — |
| reality_residual scalar | Float32 64^3 | 52.255 μs | 53.161 μs | 52.676 μs | 53.005 μs | 41.431 μs | 40.840 μs | 41.201 μs | 40.790 μs | 233.619 μs | 80.561 μs |
| reality_residual scalar | Float64 128^3 | 362.209 μs | 364.248 μs | 366.130 μs | 365.554 μs | 351.434 μs | 351.564 μs | 353.093 μs | 353.034 μs | 244.213 μs | 97.651 μs |
| reality_residual scalar | Float64 256^3 | 1.586 ms | 1.601 ms | 1.606 ms | 1.588 ms | 1.433 ms | 1.436 ms | 1.420 ms | 1.421 ms | 237.865 μs | 99.351 μs |
| reality_residual scalar | Float64 512^3 | 13.258 ms | 13.518 ms | 12.854 ms | 14.542 ms | 5.866 ms | 5.857 ms | 5.861 ms | 5.826 ms | — | — |
| reality_residual scalar | Float64 64^3 | 80.166 μs | 80.354 μs | 79.998 μs | 80.595 μs | 86.501 μs | 86.551 μs | 86.481 μs | 85.761 μs | 238.317 μs | 96.761 μs |
| reality_residual vector | Float32 128^3 | 787.510 μs | 788.210 μs | 788.489 μs | 788.956 μs | 656.336 μs | 654.547 μs | 647.486 μs | 649.897 μs | 254.669 μs | 86.441 μs |
| reality_residual vector | Float32 256^3 | 5.309 ms | 5.388 ms | 5.287 ms | 5.486 ms | 2.640 ms | 2.619 ms | 2.609 ms | 2.625 ms | 280.762 μs | 90.921 μs |
| reality_residual vector | Float32 512^3 | 33.746 ms | 31.920 ms | 33.465 ms | 32.539 ms | 16.707 ms | 16.561 ms | 16.481 ms | 16.969 ms | — | — |
| reality_residual vector | Float32 64^3 | 182.910 μs | 183.396 μs | 182.505 μs | 182.786 μs | 161.401 μs | 161.032 μs | 162.261 μs | 164.432 μs | 246.476 μs | 85.911 μs |
| reality_residual vector | Float64 128^3 | 1.247 ms | 1.253 ms | 1.255 ms | 1.263 ms | 1.247 ms | 1.250 ms | 1.250 ms | 1.244 ms | 256.991 μs | 98.111 μs |
| reality_residual vector | Float64 256^3 | 9.072 ms | 8.904 ms | 9.152 ms | 8.978 ms | 5.023 ms | 5.040 ms | 5.013 ms | 5.072 ms | 293.711 μs | 118.111 μs |
| reality_residual vector | Float64 512^3 | 47.403 ms | 47.563 ms | 47.786 ms | 58.024 ms | 35.599 ms | 35.030 ms | 34.773 ms | 35.472 ms | — | — |
| reality_residual vector | Float64 64^3 | 273.417 μs | 273.923 μs | 274.979 μs | 277.967 μs | 309.283 μs | 310.203 μs | 308.733 μs | 309.473 μs | 254.978 μs | 96.221 μs |
| var scalar | Float32 128^3 | 234.246 μs | 129.282 μs | 70.053 μs | 44.985 μs | 131.172 μs | 73.391 μs | 42.870 μs | 28.130 μs | 266.090 μs | 64.440 μs |
| var scalar | Float32 256^3 | 4.152 ms | 3.120 ms | 2.626 ms | 2.433 ms | 1.257 ms | 627.077 μs | 340.133 μs | 203.692 μs | 1.227 ms | 353.414 μs |
| var scalar | Float32 512^3 | 39.003 ms | 31.677 ms | 29.871 ms | 28.628 ms | 27.547 ms | 20.549 ms | 18.109 ms | 17.774 ms | — | — |
| var scalar | Float32 64^3 | 24.247 μs | 16.574 μs | 11.813 μs | 14.166 μs | 14.640 μs | 9.051 μs | 7.330 μs | 8.870 μs | 150.119 μs | 37.000 μs |
| var scalar | Float64 128^3 | 546.656 μs | 248.252 μs | 136.036 μs | 84.573 μs | 249.073 μs | 128.081 μs | 75.171 μs | 48.641 μs | 308.131 μs | 66.331 μs |
| var scalar | Float64 256^3 | 8.784 ms | 7.375 ms | 6.561 ms | 6.126 ms | 3.559 ms | 2.401 ms | 1.668 ms | 1.848 ms | 1.544 ms | 388.644 μs |
| var scalar | Float64 512^3 | 74.897 ms | 64.156 ms | 60.257 ms | 58.039 ms | 43.189 ms | 38.893 ms | 36.797 ms | 36.198 ms | — | — |
| var scalar | Float64 64^3 | 53.158 μs | 26.763 μs | 17.054 μs | 16.591 μs | 30.690 μs | 17.810 μs | 11.170 μs | 11.220 μs | 152.416 μs | 38.890 μs |
| var spectral scalar | Float32 128^3 | 131.168 μs | 90.581 μs | 63.026 μs | 55.036 μs | 95.661 μs | 59.790 μs | 42.860 μs | 43.321 μs | 256.148 μs | 64.341 μs |
| var spectral scalar | Float32 256^3 | 2.159 ms | 1.790 ms | 1.552 ms | 1.474 ms | 754.978 μs | 406.894 μs | 292.553 μs | 249.133 μs | 468.446 μs | 151.092 μs |
| var spectral scalar | Float32 512^3 | 19.896 ms | 17.643 ms | 16.883 ms | 16.393 ms | 12.682 ms | 10.480 ms | 10.813 ms | 10.860 ms | — | — |
| var spectral scalar | Float32 64^3 | 16.419 μs | 12.591 μs | 10.007 μs | 12.277 μs | 11.030 μs | 8.130 μs | 7.280 μs | 9.700 μs | 222.796 μs | 60.601 μs |
| var spectral scalar | Float64 128^3 | 267.726 μs | 183.123 μs | 110.537 μs | 84.526 μs | 147.541 μs | 87.031 μs | 61.850 μs | 54.271 μs | 264.955 μs | 69.811 μs |
| var spectral scalar | Float64 256^3 | 4.616 ms | 3.930 ms | 3.673 ms | 3.451 ms | 2.256 ms | 1.389 ms | 1.066 ms | 1.095 ms | 573.817 μs | 233.412 μs |
| var spectral scalar | Float64 512^3 | 39.258 ms | 34.734 ms | 33.293 ms | 31.746 ms | 21.690 ms | 20.627 ms | 20.441 ms | 20.498 ms | — | — |
| var spectral scalar | Float64 64^3 | 30.313 μs | 21.561 μs | 14.706 μs | 14.849 μs | 20.040 μs | 12.810 μs | 9.460 μs | 11.030 μs | 209.456 μs | 57.091 μs |
| weighted_inner vec | Float32 128^3 | 12.300 ms | 12.395 ms | 12.375 ms | 12.296 ms | 1.360 ms | 685.327 μs | 346.384 μs | 177.012 μs | 257.603 μs | 74.331 μs |
| weighted_inner vec | Float32 256^3 | 96.624 ms | 97.458 ms | 97.449 ms | 96.646 ms | 11.335 ms | 5.636 ms | 3.557 ms | 3.514 ms | 1.438 ms | 550.355 μs |
| weighted_inner vec | Float32 512^3 | 766.351 ms | 773.793 ms | 772.446 ms | 766.855 ms | 92.604 ms | 63.924 ms | 55.997 ms | 54.459 ms | — | — |
| weighted_inner vec | Float32 64^3 | 1.590 ms | 1.595 ms | 1.595 ms | 1.592 ms | 184.691 μs | 187.141 μs | 184.692 μs | 185.292 μs | 112.844 μs | 26.150 μs |
| weighted_inner vec | Float64 128^3 | 13.342 ms | 13.467 ms | 13.435 ms | 13.474 ms | 1.429 ms | 721.187 μs | 361.834 μs | 205.802 μs | 299.135 μs | 98.121 μs |
| weighted_inner vec | Float64 256^3 | 106.185 ms | 107.134 ms | 106.782 ms | 107.247 ms | 16.142 ms | 11.210 ms | 10.093 ms | 10.224 ms | 1.812 ms | 984.110 μs |
| weighted_inner vec | Float64 512^3 | 839.428 ms | 849.395 ms | 847.598 ms | 850.121 ms | 128.962 ms | 114.216 ms | 112.341 ms | 111.688 ms | — | — |
| weighted_inner vec | Float64 64^3 | 1.679 ms | 1.690 ms | 1.687 ms | 1.687 ms | 193.782 μs | 194.102 μs | 195.962 μs | 195.572 μs | 121.037 μs | 27.870 μs |
| weighted_inner vec.vec | Float32 128^3 | 12.348 ms | 12.463 ms | 12.439 ms | 12.347 ms | 1.390 ms | 697.227 μs | 366.533 μs | 187.402 μs | 260.055 μs | 91.731 μs |
| weighted_inner vec.vec | Float32 256^3 | 97.135 ms | 97.591 ms | 97.453 ms | 96.992 ms | 12.909 ms | 8.544 ms | 7.219 ms | 7.280 ms | 1.452 ms | 746.987 μs |
| weighted_inner vec.vec | Float32 512^3 | 769.535 ms | 774.431 ms | 777.825 ms | 771.400 ms | 103.520 ms | 90.046 ms | 85.474 ms | 84.781 ms | — | — |
| weighted_inner vec.vec | Float32 64^3 | 1.593 ms | 1.598 ms | 1.599 ms | 1.592 ms | 192.912 μs | 189.602 μs | 189.742 μs | 193.592 μs | 115.713 μs | 26.221 μs |
| weighted_inner vec.vec | Float64 128^3 | 13.591 ms | 13.697 ms | 13.706 ms | 13.796 ms | 1.955 ms | 1.049 ms | 635.257 μs | 535.806 μs | 300.598 μs | 178.332 μs |
| weighted_inner vec.vec | Float64 256^3 | 107.934 ms | 108.859 ms | 109.570 ms | 109.514 ms | 24.296 ms | 19.242 ms | 17.856 ms | 17.882 ms | 1.830 ms | 1.457 ms |
| weighted_inner vec.vec | Float64 512^3 | 852.141 ms | 862.464 ms | 861.115 ms | 866.634 ms | 203.568 ms | 176.236 ms | 170.131 ms | 170.497 ms | — | — |
| weighted_inner vec.vec | Float64 64^3 | 1.688 ms | 1.705 ms | 1.690 ms | 1.695 ms | 207.032 μs | 210.762 μs | 213.252 μs | 204.082 μs | 122.263 μs | 28.240 μs |
| weighted_inner x3 fused | Float32 128^3 | 32.408 ms | 32.342 ms | 32.307 ms | 32.320 ms | 5.073 ms | 2.473 ms | 1.270 ms | 639.767 μs | 333.088 μs | 121.521 μs |
| weighted_inner x3 fused | Float32 256^3 | 258.895 ms | 258.294 ms | 258.512 ms | 258.681 ms | 39.735 ms | 19.348 ms | 9.949 ms | 4.995 ms | 1.924 ms | 867.169 μs |
| weighted_inner x3 fused | Float32 512^3 | 2.062 s | 2.058 s | 2.059 s | 2.060 s | 314.641 ms | 153.118 ms | 77.573 ms | 40.135 ms | — | — |
| weighted_inner x3 fused | Float32 64^3 | 4.034 ms | 4.040 ms | 4.042 ms | 4.040 ms | 656.317 μs | 654.606 μs | 655.467 μs | 638.187 μs | 131.713 μs | 35.570 μs |
| weighted_inner x3 fused | Float64 128^3 | 32.208 ms | 32.161 ms | 32.154 ms | 32.140 ms | 5.083 ms | 2.505 ms | 1.276 ms | 643.336 μs | 508.608 μs | 201.922 μs |
| weighted_inner x3 fused | Float64 256^3 | 254.749 ms | 254.516 ms | 254.069 ms | 254.135 ms | 40.261 ms | 19.677 ms | 10.025 ms | 5.727 ms | 3.346 ms | 1.377 ms |
| weighted_inner x3 fused | Float64 512^3 | 2.065 s | 2.021 s | 2.022 s | 2.022 s | 316.140 ms | 156.115 ms | 79.955 ms | 55.188 ms | — | — |
| weighted_inner x3 fused | Float64 64^3 | 4.017 ms | 4.015 ms | 4.018 ms | 4.018 ms | 660.727 μs | 637.857 μs | 653.997 μs | 654.157 μs | 150.050 μs | 48.701 μs |
| weighted_inner x3 separate | Float32 128^3 | 53.173 ms | 53.112 ms | 53.029 ms | 53.013 ms | 6.323 ms | 3.135 ms | 1.574 ms | 813.328 μs | 793.494 μs | 264.132 μs |
| weighted_inner x3 separate | Float32 256^3 | 427.028 ms | 425.948 ms | 426.191 ms | 425.830 ms | 49.600 ms | 23.500 ms | 12.092 ms | 6.887 ms | 4.764 ms | 1.729 ms |
| weighted_inner x3 separate | Float32 512^3 | 3.397 s | 3.388 s | 3.378 s | 3.380 s | 394.257 ms | 185.447 ms | 106.058 ms | 81.642 ms | — | — |
| weighted_inner x3 separate | Float32 64^3 | 6.721 ms | 6.721 ms | 6.716 ms | 6.713 ms | 828.428 μs | 828.098 μs | 827.719 μs | 826.839 μs | 338.765 μs | 86.290 μs |
| weighted_inner x3 separate | Float64 128^3 | 54.580 ms | 54.549 ms | 54.521 ms | 54.592 ms | 5.877 ms | 2.953 ms | 1.560 ms | 805.609 μs | 1.018 ms | 316.023 μs |
| weighted_inner x3 separate | Float64 256^3 | 436.824 ms | 436.344 ms | 436.518 ms | 436.292 ms | 51.938 ms | 25.906 ms | 17.581 ms | 16.750 ms | 6.212 ms | 2.075 ms |
| weighted_inner x3 separate | Float64 512^3 | 3.488 s | 3.483 s | 3.472 s | 3.467 s | 399.158 ms | 219.854 ms | 164.697 ms | 164.164 ms | — | — |
| weighted_inner x3 separate | Float64 64^3 | 6.919 ms | 6.922 ms | 6.923 ms | 6.911 ms | 816.428 μs | 815.938 μs | 812.978 μs | 815.219 μs | 405.573 μs | 97.271 μs |

## storage

| operation | workload | CPU 12700K t1 | CPU 12700K t2 | CPU 12700K t4 | CPU 12700K t8 | CPU 9800X3D t1 | CPU 9800X3D t2 | CPU 9800X3D t4 | CPU 9800X3D t8 | GPU 7900XTX | GPU 5070TI |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| adapt multipliers | Float32 128^3 | — | — | — | — | — | — | — | — | 140.997 μs | 11.680 μs |
| adapt multipliers | Float32 256^3 | — | — | — | — | — | — | — | — | 146.386 μs | 12.620 μs |
| adapt multipliers | Float32 64^3 | — | — | — | — | — | — | — | — | 147.447 μs | 12.370 μs |
| adapt multipliers | Float64 128^3 | — | — | — | — | — | — | — | — | 146.471 μs | 11.890 μs |
| adapt multipliers | Float64 256^3 | — | — | — | — | — | — | — | — | 150.846 μs | 12.700 μs |
| adapt multipliers | Float64 64^3 | — | — | — | — | — | — | — | — | 152.508 μs | 12.460 μs |
| adapt plans (rebuild) | Float32 128^3 | — | — | — | — | — | — | — | — | 12.586 μs | 7.940 μs |
| adapt plans (rebuild) | Float32 256^3 | — | — | — | — | — | — | — | — | 60.577 μs | 65.061 μs |
| adapt plans (rebuild) | Float32 64^3 | — | — | — | — | — | — | — | — | 10.112 μs | 7.670 μs |
| adapt plans (rebuild) | Float64 128^3 | — | — | — | — | — | — | — | — | 18.780 μs | 8.480 μs |
| adapt plans (rebuild) | Float64 256^3 | — | — | — | — | — | — | — | — | 58.671 μs | 63.931 μs |
| adapt plans (rebuild) | Float64 64^3 | — | — | — | — | — | — | — | — | 10.139 μs | 7.560 μs |
| adapt to device scalar | Float32 128^3 | — | — | — | — | — | — | — | — | 655.642 μs | 306.153 μs |
| adapt to device scalar | Float32 256^3 | — | — | — | — | — | — | — | — | 5.659 ms | 2.442 ms |
| adapt to device scalar | Float32 64^3 | — | — | — | — | — | — | — | — | 188.894 μs | 61.210 μs |
| adapt to device scalar | Float64 128^3 | — | — | — | — | — | — | — | — | 1.304 ms | 596.516 μs |
| adapt to device scalar | Float64 256^3 | — | — | — | — | — | — | — | — | 11.416 ms | 6.108 ms |
| adapt to device scalar | Float64 64^3 | — | — | — | — | — | — | — | — | 176.581 μs | 93.271 μs |
| adapt to device vector | Float32 128^3 | — | — | — | — | — | — | — | — | 1.955 ms | 884.409 μs |
| adapt to device vector | Float32 256^3 | — | — | — | — | — | — | — | — | 16.659 ms | 9.309 ms |
| adapt to device vector | Float32 64^3 | — | — | — | — | — | — | — | — | 262.057 μs | 129.501 μs |
| adapt to device vector | Float64 128^3 | — | — | — | — | — | — | — | — | 4.354 ms | 1.772 ms |
| adapt to device vector | Float64 256^3 | — | — | — | — | — | — | — | — | 32.419 ms | 19.782 ms |
| adapt to device vector | Float64 64^3 | — | — | — | — | — | — | — | — | 514.347 μs | 236.553 μs |
| adapt to host scalar | Float32 128^3 | — | — | — | — | — | — | — | — | 514.156 μs | 431.574 μs |
| adapt to host scalar | Float32 256^3 | — | — | — | — | — | — | — | — | 12.909 ms | 11.107 ms |
| adapt to host scalar | Float32 64^3 | — | — | — | — | — | — | — | — | 145.539 μs | 63.360 μs |
| adapt to host scalar | Float64 128^3 | — | — | — | — | — | — | — | — | 1.040 ms | 846.988 μs |
| adapt to host scalar | Float64 256^3 | — | — | — | — | — | — | — | — | 24.400 ms | 22.800 ms |
| adapt to host scalar | Float64 64^3 | — | — | — | — | — | — | — | — | 132.708 μs | 117.062 μs |
| adapt to host vector | Float32 128^3 | — | — | — | — | — | — | — | — | 1.573 ms | 1.269 ms |
| adapt to host vector | Float32 256^3 | — | — | — | — | — | — | — | — | 35.319 ms | 33.463 ms |
| adapt to host vector | Float32 64^3 | — | — | — | — | — | — | — | — | 196.167 μs | 169.561 μs |
| adapt to host vector | Float64 128^3 | — | — | — | — | — | — | — | — | 9.559 ms | 8.194 ms |
| adapt to host vector | Float64 256^3 | — | — | — | — | — | — | — | — | 70.098 ms | 69.071 ms |
| adapt to host vector | Float64 64^3 | — | — | — | — | — | — | — | — | 391.320 μs | 323.783 μs |
| adapt to own family (identity) | Float32 128^3 | — | — | — | — | — | — | — | — | 145.095 ns | 128.879 ns |
| adapt to own family (identity) | Float32 256^3 | — | — | — | — | — | — | — | — | 145.762 ns | 128.254 ns |
| adapt to own family (identity) | Float32 64^3 | — | — | — | — | — | — | — | — | 143.551 ns | 128.400 ns |
| adapt to own family (identity) | Float64 128^3 | — | — | — | — | — | — | — | — | 159.363 ns | 122.509 ns |
| adapt to own family (identity) | Float64 256^3 | — | — | — | — | — | — | — | — | 156.538 ns | 123.246 ns |
| adapt to own family (identity) | Float64 64^3 | — | — | — | — | — | — | — | — | 155.749 ns | 126.877 ns |
| adapt! to device scalar | Float32 128^3 | — | — | — | — | — | — | — | — | 649.287 μs | 303.983 μs |
| adapt! to device scalar | Float32 256^3 | — | — | — | — | — | — | — | — | 5.276 ms | 2.425 ms |
| adapt! to device scalar | Float32 64^3 | — | — | — | — | — | — | — | — | 175.639 μs | 58.780 μs |
| adapt! to device scalar | Float64 128^3 | — | — | — | — | — | — | — | — | 1.297 ms | 589.445 μs |
| adapt! to device scalar | Float64 256^3 | — | — | — | — | — | — | — | — | 10.582 ms | 6.010 ms |
| adapt! to device scalar | Float64 64^3 | — | — | — | — | — | — | — | — | 171.649 μs | 91.541 μs |
| adapt! to device vector | Float32 128^3 | — | — | — | — | — | — | — | — | 1.948 ms | 877.428 μs |
| adapt! to device vector | Float32 256^3 | — | — | — | — | — | — | — | — | 15.883 ms | 9.089 ms |
| adapt! to device vector | Float32 64^3 | — | — | — | — | — | — | — | — | 256.862 μs | 127.721 μs |
| adapt! to device vector | Float64 128^3 | — | — | — | — | — | — | — | — | 3.988 ms | 1.757 ms |
| adapt! to device vector | Float64 256^3 | — | — | — | — | — | — | — | — | 31.641 ms | 18.287 ms |
| adapt! to device vector | Float64 64^3 | — | — | — | — | — | — | — | — | 511.339 μs | 233.282 μs |
| adapt! to host scalar | Float32 128^3 | — | — | — | — | — | — | — | — | 521.190 μs | 427.684 μs |
| adapt! to host scalar | Float32 256^3 | — | — | — | — | — | — | — | — | 4.294 ms | 3.367 ms |
| adapt! to host scalar | Float32 64^3 | — | — | — | — | — | — | — | — | 126.685 μs | 63.470 μs |
| adapt! to host scalar | Float64 128^3 | — | — | — | — | — | — | — | — | 1.048 ms | 847.598 μs |
| adapt! to host scalar | Float64 256^3 | — | — | — | — | — | — | — | — | 8.147 ms | 6.811 ms |
| adapt! to host scalar | Float64 64^3 | — | — | — | — | — | — | — | — | 135.976 μs | 115.181 μs |
| adapt! to host vector | Float32 128^3 | — | — | — | — | — | — | — | — | 1.560 ms | 1.268 ms |
| adapt! to host vector | Float32 256^3 | — | — | — | — | — | — | — | — | 12.638 ms | 10.127 ms |
| adapt! to host vector | Float32 64^3 | — | — | — | — | — | — | — | — | 199.243 μs | 169.212 μs |
| adapt! to host vector | Float64 128^3 | — | — | — | — | — | — | — | — | 3.121 ms | 2.522 ms |
| adapt! to host vector | Float64 256^3 | — | — | — | — | — | — | — | — | 25.120 ms | 20.237 ms |
| adapt! to host vector | Float64 64^3 | — | — | — | — | — | — | — | — | 395.344 μs | 323.093 μs |

## Triage — the born-slow scan

Two questions no per-row history can answer (finding (ag)): does a threaded operation actually scale, and is a row wildly slower than its class peers at the same workload. Flags are QUESTIONS, not verdicts — a `known` row carries its recorded reason, and an unexplained one is closed by a fix or by a recorded reason, never by deleting the row. Thresholds: flat means under 1.1x speedup lowest-to-highest thread lane with at least 1.000 ms of work; an outlier is over 8.0x its class median.

### A. Thread-flat on every host — 23 flagged (19 known)

| class | row | per-host (t_low, speedup) | note |
|:--|:--|:--|:--|
| reductions | co-spectrum vec.vec | Float32 128^3 | 12700K: 8.085 ms ×1.01; 9800X3D: 6.955 ms ×1.08 | **UNEXPLAINED** |
| reductions | co-spectrum vec.vec | Float32 64^3 | 12700K: 1.044 ms ×0.65 | **UNEXPLAINED** |
| reductions | co-spectrum vec.vec | Float64 64^3 | 12700K: 1.062 ms ×1.07 | **UNEXPLAINED** |
| reductions | cross-correlation vec.vec | Float32 64^3 | 12700K: 4.645 ms ×0.81; 9800X3D: 3.841 ms ×1.04 | known: the radial_correlation co-spectrum form — same materialization |
| reductions | radial_correlation vec | Float32 64^3 | 12700K: 4.240 ms ×0.75; 9800X3D: 3.519 ms ×1.02 | known: materializes its power field + inverse transform by design — decision 22 |
| reductions | radial_spectrum vec | Float32 128^3 | 12700K: 7.479 ms ×0.87; 9800X3D: 6.328 ms ×1.09 | **UNEXPLAINED** |
| reductions | reality_residual scalar | Float32 256^3 | 12700K: 1.021 ms ×1.0 | known: recorded: neither threads nor fuses — CLAUDE.md roadmap, decision 71 entry |
| reductions | reality_residual scalar | Float32 512^3 | 12700K: 8.106 ms ×0.92; 9800X3D: 2.720 ms ×0.98 | known: recorded: neither threads nor fuses — CLAUDE.md roadmap, decision 71 entry |
| reductions | reality_residual scalar | Float64 256^3 | 12700K: 1.586 ms ×1.0; 9800X3D: 1.433 ms ×1.01 | known: recorded: neither threads nor fuses — CLAUDE.md roadmap, decision 71 entry |
| reductions | reality_residual scalar | Float64 512^3 | 12700K: 13.258 ms ×0.91; 9800X3D: 5.866 ms ×1.01 | known: recorded: neither threads nor fuses — CLAUDE.md roadmap, decision 71 entry |
| reductions | reality_residual vector | Float32 256^3 | 12700K: 5.309 ms ×0.97; 9800X3D: 2.640 ms ×1.01 | known: recorded: neither threads nor fuses — CLAUDE.md roadmap, decision 71 entry |
| reductions | reality_residual vector | Float32 512^3 | 12700K: 33.746 ms ×1.04; 9800X3D: 16.707 ms ×0.98 | known: recorded: neither threads nor fuses — CLAUDE.md roadmap, decision 71 entry |
| reductions | reality_residual vector | Float64 128^3 | 12700K: 1.247 ms ×0.99; 9800X3D: 1.247 ms ×1.0 | known: recorded: neither threads nor fuses — CLAUDE.md roadmap, decision 71 entry |
| reductions | reality_residual vector | Float64 256^3 | 12700K: 9.072 ms ×1.01; 9800X3D: 5.023 ms ×0.99 | known: recorded: neither threads nor fuses — CLAUDE.md roadmap, decision 71 entry |
| reductions | reality_residual vector | Float64 512^3 | 12700K: 47.403 ms ×0.82; 9800X3D: 35.599 ms ×1.0 | known: recorded: neither threads nor fuses — CLAUDE.md roadmap, decision 71 entry |
| reductions | weighted_inner vec | Float32 64^3 | 12700K: 1.590 ms ×1.0 | known: the finding-(ac) pathology, FIXED 2026-08-30; the 9800X3D lanes are re-swept (2026-08-31) and clean — remaining flags are the 12700K archives, stale until that host re-sweeps |
| reductions | weighted_inner vec | Float64 64^3 | 12700K: 1.679 ms ×1.0 | known: the finding-(ac) pathology, FIXED 2026-08-30; the 9800X3D lanes are re-swept (2026-08-31) and clean — remaining flags are the 12700K archives, stale until that host re-sweeps |
| reductions | weighted_inner vec.vec | Float32 64^3 | 12700K: 1.593 ms ×1.0 | known: the finding-(ac) pathology, FIXED 2026-08-30; the 9800X3D lanes are re-swept (2026-08-31) and clean — remaining flags are the 12700K archives, stale until that host re-sweeps |
| reductions | weighted_inner vec.vec | Float64 64^3 | 12700K: 1.688 ms ×1.0 | known: the finding-(ac) pathology, FIXED 2026-08-30; the 9800X3D lanes are re-swept (2026-08-31) and clean — remaining flags are the 12700K archives, stale until that host re-sweeps |
| reductions | weighted_inner x3 fused | Float32 64^3 | 12700K: 4.034 ms ×1.0 | known: the finding-(ac) pathology, FIXED 2026-08-30; the 9800X3D lanes are re-swept (2026-08-31) and clean — remaining flags are the 12700K archives, stale until that host re-sweeps |
| reductions | weighted_inner x3 fused | Float64 64^3 | 12700K: 4.017 ms ×1.0 | known: the finding-(ac) pathology, FIXED 2026-08-30; the 9800X3D lanes are re-swept (2026-08-31) and clean — remaining flags are the 12700K archives, stale until that host re-sweeps |
| reductions | weighted_inner x3 separate | Float32 64^3 | 12700K: 6.721 ms ×1.0 | known: the finding-(ac) pathology, FIXED 2026-08-30; the 9800X3D lanes are re-swept (2026-08-31) and clean — remaining flags are the 12700K archives, stale until that host re-sweeps |
| reductions | weighted_inner x3 separate | Float64 64^3 | 12700K: 6.919 ms ×1.0 | known: the finding-(ac) pathology, FIXED 2026-08-30; the 9800X3D lanes are re-swept (2026-08-31) and clean — remaining flags are the 12700K archives, stale until that host re-sweeps |

### B. Declared-peer violations — 33 flagged (33 known)

| lane | row | peer | time | peer time | ratio | documented claim |
|:--|:--|:--|:--|:--|:--|:--|
| CPU 12700K t8 | weighted_inner vec | Float32 64^3 | inner spectral | 1.592 ms | 113.332 μs | 14.0x | the weighted_inner docstring: "the same traffic as one spectral `inner`" — known: the finding-(ac) pathology, FIXED 2026-08-30; the 9800X3D lanes are re-swept (2026-08-31) and clean — remaining flags are the 12700K archives, stale until that host re-sweeps |
| CPU 12700K t8 | weighted_inner vec | Float64 64^3 | inner spectral | 1.687 ms | 127.392 μs | 13.2x | the weighted_inner docstring: "the same traffic as one spectral `inner`" — known: the finding-(ac) pathology, FIXED 2026-08-30; the 9800X3D lanes are re-swept (2026-08-31) and clean — remaining flags are the 12700K archives, stale until that host re-sweeps |
| CPU 12700K t4 | weighted_inner vec | Float32 64^3 | inner spectral | 1.595 ms | 138.790 μs | 11.5x | the weighted_inner docstring: "the same traffic as one spectral `inner`" — known: the finding-(ac) pathology, FIXED 2026-08-30; the 9800X3D lanes are re-swept (2026-08-31) and clean — remaining flags are the 12700K archives, stale until that host re-sweeps |
| CPU 12700K t4 | weighted_inner vec | Float64 64^3 | inner spectral | 1.687 ms | 148.238 μs | 11.4x | the weighted_inner docstring: "the same traffic as one spectral `inner`" — known: the finding-(ac) pathology, FIXED 2026-08-30; the 9800X3D lanes are re-swept (2026-08-31) and clean — remaining flags are the 12700K archives, stale until that host re-sweeps |
| CPU 12700K t8 | weighted_inner vec | Float32 128^3 | inner spectral | 12.296 ms | 1.229 ms | 10.0x | the weighted_inner docstring: "the same traffic as one spectral `inner`" — known: the finding-(ac) pathology, FIXED 2026-08-30; the 9800X3D lanes are re-swept (2026-08-31) and clean — remaining flags are the 12700K archives, stale until that host re-sweeps |
| CPU 12700K t1 | exponential_convolve! vector | Float64 64^3 | convolve! vector | 2.475 ms | 275.006 μs | 9.0x | the VECTOR pair is defect-shaped: with the decision-79 hoist the exp amortizes over the fiber, so a large ratio means the extrusion is back — known: the VECTOR extrusion is FIXED by decision 79 (2026-08-30); flags on the stale 12700K archives close when that host re-sweeps |
| CPU 12700K t4 | weighted_inner vec | Float32 128^3 | inner spectral | 12.375 ms | 1.380 ms | 9.0x | the weighted_inner docstring: "the same traffic as one spectral `inner`" — known: the finding-(ac) pathology, FIXED 2026-08-30; the 9800X3D lanes are re-swept (2026-08-31) and clean — remaining flags are the 12700K archives, stale until that host re-sweeps |
| CPU 12700K t1 | exponential_convolve! vector | Float32 64^3 | convolve! vector | 2.542 ms | 310.204 μs | 8.2x | the VECTOR pair is defect-shaped: with the decision-79 hoist the exp amortizes over the fiber, so a large ratio means the extrusion is back — known: the VECTOR extrusion is FIXED by decision 79 (2026-08-30); flags on the stale 12700K archives close when that host re-sweeps |
| CPU 12700K t2 | weighted_inner vec | Float32 64^3 | inner spectral | 1.595 ms | 196.626 μs | 8.1x | the weighted_inner docstring: "the same traffic as one spectral `inner`" — known: the finding-(ac) pathology, FIXED 2026-08-30; the 9800X3D lanes are re-swept (2026-08-31) and clean — remaining flags are the 12700K archives, stale until that host re-sweeps |
| CPU 12700K t2 | weighted_inner vec | Float64 64^3 | inner spectral | 1.690 ms | 210.033 μs | 8.0x | the weighted_inner docstring: "the same traffic as one spectral `inner`" — known: the finding-(ac) pathology, FIXED 2026-08-30; the 9800X3D lanes are re-swept (2026-08-31) and clean — remaining flags are the 12700K archives, stale until that host re-sweeps |
| CPU 12700K t2 | weighted_inner vec | Float32 128^3 | inner spectral | 12.395 ms | 1.649 ms | 7.5x | the weighted_inner docstring: "the same traffic as one spectral `inner`" — known: the finding-(ac) pathology, FIXED 2026-08-30; the 9800X3D lanes are re-swept (2026-08-31) and clean — remaining flags are the 12700K archives, stale until that host re-sweeps |
| CPU 12700K t8 | weighted_inner vec | Float32 512^3 | inner spectral | 766.855 ms | 106.006 ms | 7.2x | the weighted_inner docstring: "the same traffic as one spectral `inner`" — known: the finding-(ac) pathology, FIXED 2026-08-30; the 9800X3D lanes are re-swept (2026-08-31) and clean — remaining flags are the 12700K archives, stale until that host re-sweeps |
| CPU 12700K t1 | exponential_convolve! vector | Float32 256^3 | convolve! vector | 160.278 ms | 22.387 ms | 7.2x | the VECTOR pair is defect-shaped: with the decision-79 hoist the exp amortizes over the fiber, so a large ratio means the extrusion is back — known: the VECTOR extrusion is FIXED by decision 79 (2026-08-30); flags on the stale 12700K archives close when that host re-sweeps |
| CPU 12700K t8 | weighted_inner vec | Float32 256^3 | inner spectral | 96.646 ms | 13.651 ms | 7.1x | the weighted_inner docstring: "the same traffic as one spectral `inner`" — known: the finding-(ac) pathology, FIXED 2026-08-30; the 9800X3D lanes are re-swept (2026-08-31) and clean — remaining flags are the 12700K archives, stale until that host re-sweeps |
| CPU 12700K t2 | exponential_convolve! vector | Float32 64^3 | convolve! vector | 1.233 ms | 175.555 μs | 7.0x | the VECTOR pair is defect-shaped: with the decision-79 hoist the exp amortizes over the fiber, so a large ratio means the extrusion is back — known: the VECTOR extrusion is FIXED by decision 79 (2026-08-30); flags on the stale 12700K archives close when that host re-sweeps |
| CPU 12700K t2 | exponential_convolve! vector | Float64 64^3 | convolve! vector | 1.167 ms | 169.460 μs | 6.9x | the VECTOR pair is defect-shaped: with the decision-79 hoist the exp amortizes over the fiber, so a large ratio means the extrusion is back — known: the VECTOR extrusion is FIXED by decision 79 (2026-08-30); flags on the stale 12700K archives close when that host re-sweeps |
| CPU 12700K t4 | weighted_inner vec | Float32 512^3 | inner spectral | 772.446 ms | 112.670 ms | 6.9x | the weighted_inner docstring: "the same traffic as one spectral `inner`" — known: the finding-(ac) pathology, FIXED 2026-08-30; the 9800X3D lanes are re-swept (2026-08-31) and clean — remaining flags are the 12700K archives, stale until that host re-sweeps |
| CPU 12700K t1 | exponential_convolve! vector | Float32 128^3 | convolve! vector | 20.248 ms | 2.984 ms | 6.8x | the VECTOR pair is defect-shaped: with the decision-79 hoist the exp amortizes over the fiber, so a large ratio means the extrusion is back — known: the VECTOR extrusion is FIXED by decision 79 (2026-08-30); flags on the stale 12700K archives close when that host re-sweeps |
| CPU 12700K t1 | exponential_convolve! vector | Float32 512^3 | convolve! vector | 1.274 s | 191.859 ms | 6.6x | the VECTOR pair is defect-shaped: with the decision-79 hoist the exp amortizes over the fiber, so a large ratio means the extrusion is back — known: the VECTOR extrusion is FIXED by decision 79 (2026-08-30); flags on the stale 12700K archives close when that host re-sweeps |
| CPU 12700K t4 | weighted_inner vec | Float32 256^3 | inner spectral | 97.449 ms | 14.751 ms | 6.6x | the weighted_inner docstring: "the same traffic as one spectral `inner`" — known: the finding-(ac) pathology, FIXED 2026-08-30; the 9800X3D lanes are re-swept (2026-08-31) and clean — remaining flags are the 12700K archives, stale until that host re-sweeps |
| CPU 12700K t2 | weighted_inner vec | Float32 512^3 | inner spectral | 773.793 ms | 128.807 ms | 6.0x | the weighted_inner docstring: "the same traffic as one spectral `inner`" — known: the finding-(ac) pathology, FIXED 2026-08-30; the 9800X3D lanes are re-swept (2026-08-31) and clean — remaining flags are the 12700K archives, stale until that host re-sweeps |
| CPU 12700K t2 | weighted_inner vec | Float32 256^3 | inner spectral | 97.458 ms | 16.705 ms | 5.8x | the weighted_inner docstring: "the same traffic as one spectral `inner`" — known: the finding-(ac) pathology, FIXED 2026-08-30; the 9800X3D lanes are re-swept (2026-08-31) and clean — remaining flags are the 12700K archives, stale until that host re-sweeps |
| CPU 12700K t1 | weighted_inner vec | Float64 64^3 | inner spectral | 1.679 ms | 309.165 μs | 5.4x | the weighted_inner docstring: "the same traffic as one spectral `inner`" — known: the finding-(ac) pathology, FIXED 2026-08-30; the 9800X3D lanes are re-swept (2026-08-31) and clean — remaining flags are the 12700K archives, stale until that host re-sweeps |
| CPU 12700K t2 | exponential_convolve! vector | Float32 128^3 | convolve! vector | 9.678 ms | 1.838 ms | 5.3x | the VECTOR pair is defect-shaped: with the decision-79 hoist the exp amortizes over the fiber, so a large ratio means the extrusion is back — known: the VECTOR extrusion is FIXED by decision 79 (2026-08-30); flags on the stale 12700K archives close when that host re-sweeps |
| CPU 12700K t1 | weighted_inner vec | Float32 64^3 | inner spectral | 1.590 ms | 305.237 μs | 5.2x | the weighted_inner docstring: "the same traffic as one spectral `inner`" — known: the finding-(ac) pathology, FIXED 2026-08-30; the 9800X3D lanes are re-swept (2026-08-31) and clean — remaining flags are the 12700K archives, stale until that host re-sweeps |
| CPU 12700K t1 | weighted_inner vec | Float32 128^3 | inner spectral | 12.300 ms | 2.464 ms | 5.0x | the weighted_inner docstring: "the same traffic as one spectral `inner`" — known: the finding-(ac) pathology, FIXED 2026-08-30; the 9800X3D lanes are re-swept (2026-08-31) and clean — remaining flags are the 12700K archives, stale until that host re-sweeps |
| CPU 12700K t8 | weighted_inner vec | Float64 128^3 | inner spectral | 13.474 ms | 2.850 ms | 4.7x | the weighted_inner docstring: "the same traffic as one spectral `inner`" — known: the finding-(ac) pathology, FIXED 2026-08-30; the 9800X3D lanes are re-swept (2026-08-31) and clean — remaining flags are the 12700K archives, stale until that host re-sweeps |
| CPU 12700K t1 | weighted_inner vec | Float32 512^3 | inner spectral | 766.351 ms | 164.737 ms | 4.7x | the weighted_inner docstring: "the same traffic as one spectral `inner`" — known: the finding-(ac) pathology, FIXED 2026-08-30; the 9800X3D lanes are re-swept (2026-08-31) and clean — remaining flags are the 12700K archives, stale until that host re-sweeps |
| CPU 12700K t1 | weighted_inner vec | Float32 256^3 | inner spectral | 96.624 ms | 21.204 ms | 4.6x | the weighted_inner docstring: "the same traffic as one spectral `inner`" — known: the finding-(ac) pathology, FIXED 2026-08-30; the 9800X3D lanes are re-swept (2026-08-31) and clean — remaining flags are the 12700K archives, stale until that host re-sweeps |
| CPU 12700K t4 | weighted_inner vec | Float64 128^3 | inner spectral | 13.435 ms | 3.107 ms | 4.3x | the weighted_inner docstring: "the same traffic as one spectral `inner`" — known: the finding-(ac) pathology, FIXED 2026-08-30; the 9800X3D lanes are re-swept (2026-08-31) and clean — remaining flags are the 12700K archives, stale until that host re-sweeps |
| CPU 12700K t8 | weighted_inner vec | Float64 512^3 | inner spectral | 850.121 ms | 199.676 ms | 4.3x | the weighted_inner docstring: "the same traffic as one spectral `inner`" — known: the finding-(ac) pathology, FIXED 2026-08-30; the 9800X3D lanes are re-swept (2026-08-31) and clean — remaining flags are the 12700K archives, stale until that host re-sweeps |
| CPU 12700K t8 | weighted_inner vec | Float64 256^3 | inner spectral | 107.247 ms | 26.111 ms | 4.1x | the weighted_inner docstring: "the same traffic as one spectral `inner`" — known: the finding-(ac) pathology, FIXED 2026-08-30; the 9800X3D lanes are re-swept (2026-08-31) and clean — remaining flags are the 12700K archives, stale until that host re-sweeps |
| CPU 12700K t4 | weighted_inner vec | Float64 512^3 | inner spectral | 847.598 ms | 211.250 ms | 4.0x | the weighted_inner docstring: "the same traffic as one spectral `inner`" — known: the finding-(ac) pathology, FIXED 2026-08-30; the 9800X3D lanes are re-swept (2026-08-31) and clean — remaining flags are the 12700K archives, stale until that host re-sweeps |

